#Requires -Version 5.1
<#
.SYNOPSIS
  Copy latest news JSON from separate topic repos into news-to-business-site/data
  and rebuild data/feed.json for the unified GitHub Pages site.
#>
param(
    [int]$RetentionDays = 0,
    [switch]$FullHistory
)

$ErrorActionPreference = 'Continue'
$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Repo

$LogDir = Join-Path $Repo 'Logs'
if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$Today = Get-Date -Format 'yyyy-MM-dd'
$Log = Join-Path $LogDir ("sync-{0}.log" -f $Today)
$SourcesFile = Join-Path $Repo 'sources.json'
$DataRoot = Join-Path $Repo 'data'
$FeedPath = Join-Path $DataRoot 'feed.json'
$TopicsManifest = Join-Path $DataRoot 'topics.json'

function Write-Log([string]$Message) {
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -LiteralPath $Log -Value $line -Encoding UTF8
}

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-FileHashSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Copy-IfChanged {
    param(
        [string]$Source,
        [string]$Dest
    )
    if (-not (Test-Path -LiteralPath $Source)) { return $false }
    Ensure-Dir (Split-Path -Parent $Dest)
    $srcHash = Get-FileHashSafe $Source
    $dstHash = Get-FileHashSafe $Dest
    if ($srcHash -and $dstHash -and ($srcHash -eq $dstHash)) { return $false }
    Copy-Item -LiteralPath $Source -Destination $Dest -Force
    return $true
}

function Test-WithinRetention {
    param(
        [string]$DateToken,
        [datetime]$Cutoff
    )
    if ($script:KeepAll) { return $true }
    try {
        $d = [datetime]::ParseExact($DateToken, 'yyyy-MM-dd', $null)
        return ($d -ge $Cutoff.Date)
    } catch {
        return $true
    }
}

function Get-TextSnippet([string]$Text, [int]$Max = 280) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $clean = [regex]::Replace($Text, '<[^>]+>', ' ')
    $clean = [regex]::Replace($clean, '\s+', ' ').Trim()
    if ($clean.Length -le $Max) { return $clean }
    return ($clean.Substring(0, $Max - 1) + '…')
}

function ConvertTo-FeedItem {
    param(
        [string]$TopicId,
        [string]$Day,
        $Post
    )

    $title = $Post.title
    if (-not $title -and $Post.title_th) { $title = $Post.title_th }
    $content = $Post.content
    if (-not $content -and $Post.content_html) {
        $content = Get-TextSnippet ([string]$Post.content_html) 4000
    }
    $summary = $Post.exec_blurb
    if (-not $summary) { $summary = $Post.summary }
    if (-not $summary) { $summary = Get-TextSnippet $content 220 }

    $published = $Post.published_at
    if (-not $published) { $published = $Post.announcement_date }
    if (-not $published) { $published = $Day }

    $urgency = $Post.urgency
    if (-not $urgency -and $Post.priority) {
        switch ($Post.priority) {
            'A' { $urgency = 'high' }
            'B' { $urgency = 'medium' }
            default { $urgency = 'low' }
        }
    }
    if (-not $urgency) { $urgency = 'medium' }

    $agency = $Post.agency
    if (-not $agency) { $agency = $Post.source_name }
    if (-not $agency) { $agency = $Post.primary_bureau }

    $source = $Post.source_name
    if (-not $source) { $source = $Post.topic }
    if (-not $source) { $source = $TopicId }

    $tags = @()
    if ($Post.tags) { $tags = @($Post.tags) }

    return [ordered]@{
        id           = [string]$Post.id
        topic        = $TopicId
        date         = $Day
        published_at = [string]$published
        title        = [string]$title
        summary      = [string]$summary
        content      = [string]$content
        content_html = if ($Post.content_html) { [string]$Post.content_html } else { $null }
        urgency      = ([string]$urgency).ToLowerInvariant()
        agency       = [string]$agency
        source       = [string]$source
        source_url   = [string]$Post.source_url
        tags         = $tags
        priority     = [string]$Post.priority
    }
}

function Find-DailyNewsCandidates {
    param(
        [string[]]$Paths,
        [datetime]$Cutoff
    )
    $map = @{}
    foreach ($root in $Paths) {
        if (-not (Test-Path -LiteralPath $root)) { continue }

        Get-ChildItem -LiteralPath $root -Filter '*_news.json' -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                if ($_.Name -match '^(\d{4}-\d{2}-\d{2})_news\.json$') {
                    $day = $Matches[1]
                    if (Test-WithinRetention -DateToken $day -Cutoff $Cutoff) {
                        if (-not $map.ContainsKey($day)) { $map[$day] = $_.FullName }
                    }
                }
            }

        Get-ChildItem -LiteralPath $root -Directory -Filter '*_News' -ErrorAction SilentlyContinue |
            ForEach-Object {
                if ($_.Name -match '^(\d{4}-\d{2}-\d{2})_News$') {
                    $day = $Matches[1]
                    if (-not (Test-WithinRetention -DateToken $day -Cutoff $Cutoff)) { return }
                    $candidate = Join-Path $_.FullName ('{0}_news.json' -f $day)
                    if ((Test-Path -LiteralPath $candidate) -and (-not $map.ContainsKey($day))) {
                        $map[$day] = $candidate
                    }
                }
            }
    }
    return $map
}

function Sync-DailyNewsTopic {
    param(
        $Topic,
        [datetime]$Cutoff,
        [System.Collections.Generic.List[object]]$FeedItems,
        [hashtable]$Stats
    )
    $destDir = Join-Path $DataRoot $Topic.id
    Ensure-Dir $destDir
    $map = Find-DailyNewsCandidates -Paths @($Topic.paths) -Cutoff $Cutoff
    $copied = 0
    foreach ($day in ($map.Keys | Sort-Object -Descending)) {
        $src = $map[$day]
        $dest = Join-Path $destDir ('{0}_news.json' -f $day)
        if (Copy-IfChanged -Source $src -Dest $dest) { $copied++ }

        try {
            $json = Get-Content -LiteralPath $dest -Raw -Encoding UTF8 | ConvertFrom-Json
            $posts = @()
            if ($json.posts) { $posts = @($json.posts) }
            elseif ($json -is [System.Array]) { $posts = @($json) }
            foreach ($post in $posts) {
                $FeedItems.Add((ConvertTo-FeedItem -TopicId $Topic.id -Day $day -Post $post))
            }
            $Stats[$Topic.id] = [int]$Stats[$Topic.id] + $posts.Count
        } catch {
            Write-Log ("WARN: cannot parse {0}: {1}" -f $dest, $_.Exception.Message)
        }
    }

    $manifest = @($map.Keys | Sort-Object -Descending | ForEach-Object { '{0}_news.json' -f $_ })
    $manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $destDir 'manifest.json') -Encoding UTF8
    Write-Log ("[{0}] days={1} copied={2} posts={3}" -f $Topic.id, $map.Count, $copied, $Stats[$Topic.id])
}

function Sync-PoliceTopic {
    param(
        $Topic,
        [datetime]$Cutoff,
        [System.Collections.Generic.List[object]]$FeedItems,
        [hashtable]$Stats
    )
    $destDir = Join-Path $DataRoot $Topic.id
    Ensure-Dir $destDir
    $srcRoot = @($Topic.paths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
    if (-not $srcRoot) {
        Write-Log '[police] source missing'
        return
    }

    $copied = 0
    $patterns = @('manifest.json', 'feed.json', '*_crime.json', '*_cyber.json', '*_alerts*.json', '*_bd_leads*.json')
    foreach ($pat in $patterns) {
        Get-ChildItem -LiteralPath $srcRoot -Filter $pat -File -ErrorAction SilentlyContinue | ForEach-Object {
            $include = $true
            if ($_.Name -match '^(\d{4}-\d{2}-\d{2})_') {
                $include = Test-WithinRetention -DateToken $Matches[1] -Cutoff $Cutoff
            }
            if (-not $include) { return }
            $dest = Join-Path $destDir $_.Name
            if (Copy-IfChanged -Source $_.FullName -Dest $dest) { $copied++ }
        }
    }

    Get-ChildItem -LiteralPath $destDir -Filter '*_crime.json' -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object {
            if ($_.Name -notmatch '^(\d{4}-\d{2}-\d{2})_crime\.json$') { return }
            $day = $Matches[1]
            try {
                $json = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $posts = @($json.posts)
                foreach ($post in $posts) {
                    $FeedItems.Add((ConvertTo-FeedItem -TopicId 'police' -Day $day -Post $post))
                }
                $Stats['police'] = [int]$Stats['police'] + $posts.Count
            } catch {
                Write-Log ("WARN: police parse {0}: {1}" -f $_.Name, $_.Exception.Message)
            }
        }

    Write-Log ("[police] copied={0} posts={1}" -f $copied, $Stats['police'])
}

function Sync-TechLawTopic {
    param(
        $Topic,
        [datetime]$Cutoff,
        [System.Collections.Generic.List[object]]$FeedItems,
        [hashtable]$Stats
    )
    $destDir = Join-Path $DataRoot $Topic.id
    Ensure-Dir $destDir
    $srcRoot = @($Topic.paths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
    if (-not $srcRoot) {
        Write-Log '[tech-law] source missing'
        return
    }

    $copied = 0
    $manifestSrc = Join-Path $srcRoot 'manifest.json'
    if (Test-Path -LiteralPath $manifestSrc) {
        if (Copy-IfChanged -Source $manifestSrc -Dest (Join-Path $destDir 'manifest.json')) { $copied++ }
    }

    Get-ChildItem -LiteralPath $srcRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' } |
        ForEach-Object {
            $day = $_.Name
            if (-not (Test-WithinRetention -DateToken $day -Cutoff $Cutoff)) { return }
            $srcContent = Join-Path $_.FullName 'content.json'
            if (-not (Test-Path -LiteralPath $srcContent)) { return }
            $dayDir = Join-Path $destDir $day
            Ensure-Dir $dayDir
            $destContent = Join-Path $dayDir 'content.json'
            if (Copy-IfChanged -Source $srcContent -Dest $destContent) { $copied++ }

            try {
                $json = Get-Content -LiteralPath $destContent -Raw -Encoding UTF8 | ConvertFrom-Json
                $posts = @($json.posts)
                foreach ($post in $posts) {
                    $FeedItems.Add((ConvertTo-FeedItem -TopicId 'tech-law' -Day $day -Post $post))
                }
                $Stats['tech-law'] = [int]$Stats['tech-law'] + $posts.Count
            } catch {
                Write-Log ("WARN: tech-law parse {0}: {1}" -f $day, $_.Exception.Message)
            }
        }

    Write-Log ("[tech-law] copied={0} posts={1}" -f $copied, $Stats['tech-law'])
}

# ---- main ----
Write-Log '=== Sync-FromSources START ==='
if (-not (Test-Path -LiteralPath $SourcesFile)) {
    Write-Log "ERROR: missing $SourcesFile"
    exit 1
}

$config = Get-Content -LiteralPath $SourcesFile -Raw -Encoding UTF8 | ConvertFrom-Json
$keepDays = if ($RetentionDays -gt 0) { $RetentionDays } elseif ($config.retention_days) { [int]$config.retention_days } else { 60 }
$script:KeepAll = [bool]$FullHistory
$cutoff = (Get-Date).AddDays(-($keepDays - 1))
Write-Log ("RetentionDays={0} FullHistory={1} Cutoff={2:yyyy-MM-dd}" -f $keepDays, $script:KeepAll, $cutoff)

Ensure-Dir $DataRoot
$feedItems = New-Object 'System.Collections.Generic.List[object]'
$stats = @{ ai = 0; gov = 0; police = 0; 'tech-law' = 0 }

foreach ($topic in $config.topics) {
    switch ($topic.kind) {
        'daily_news_json' { Sync-DailyNewsTopic -Topic $topic -Cutoff $cutoff -FeedItems $feedItems -Stats $stats }
        'police_kit'      { Sync-PoliceTopic -Topic $topic -Cutoff $cutoff -FeedItems $feedItems -Stats $stats }
        'tech_law'        { Sync-TechLawTopic -Topic $topic -Cutoff $cutoff -FeedItems $feedItems -Stats $stats }
        default           { Write-Log ("WARN: unknown kind {0}" -f $topic.kind) }
    }
}

$sorted = @($feedItems | Sort-Object @{ Expression = { $_.published_at } ; Descending = $true }, @{ Expression = { $_.date } ; Descending = $true })
$feed = [ordered]@{
    meta = [ordered]@{
        synced_at      = (Get-Date).ToString('o')
        retention_days = if ($script:KeepAll) { $null } else { $keepDays }
        source_count   = $config.topics.Count
        item_count     = $sorted.Count
        by_topic       = $stats
    }
    items = $sorted
}
$feed | ConvertTo-Json -Depth 8 -Compress:$false | Set-Content -LiteralPath $FeedPath -Encoding UTF8

$topicsOut = [ordered]@{
    generated_at = (Get-Date).ToString('o')
    topics       = @($config.topics | ForEach-Object {
            [ordered]@{
                id    = $_.id
                label = $_.label
                count = [int]$stats[$_.id]
            }
        })
}
$topicsOut | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $TopicsManifest -Encoding UTF8

Write-Log ("FEED items={0} path={1}" -f $sorted.Count, $FeedPath)
Write-Log '=== Sync-FromSources DONE ==='
exit 0
