#Requires -Version 5.1
<#
.SYNOPSIS
  Sync from separate news repos into news-to-business-site, then push GitHub Pages.

.DESCRIPTION
  Primary path: each topic DailyPush / git-publish calls this with -FromSource
  right after that topic's Pages push succeeds, so the unified site updates on
  every source change (not only once at 18:xx).

  Failsafe path: scheduled evening run (default -FromSource schedule) catches
  anything a source trigger missed.

.NOTES
  Live: https://chiraleo2000.github.io/news-to-business-site/
  Sources:
    AI       https://chiraleo2000.github.io/ai-news/
    Gov      https://chiraleo2000.github.io/gov-news-thailand/
    Police   https://chiraleo2000.github.io/Police-news-intel-kit/
    TechLaw  https://chiraleo2000.github.io/tech-law-thailand/
#>
param(
    [switch]$Retry,
    [switch]$SkipPush,
    [switch]$FullHistory,
    [ValidateSet('ai', 'gov', 'police', 'tech-law', 'schedule')]
    [string]$FromSource = 'schedule'
)

$ErrorActionPreference = 'Continue'
$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $Repo

$LogDir = Join-Path $Repo 'Logs'
if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$Today = Get-Date -Format 'yyyy-MM-dd'
$Log = Join-Path $LogDir ("daily-{0}.log" -f $Today)
$SyncScript = Join-Path $Repo 'Sync-FromSources.ps1'
$PushBat = Join-Path $Repo 'PUSH.bat'
$SourcesFile = Join-Path $Repo 'sources.json'
$script:ExitCode = 0
$script:PushMutex = $null
$script:PushMutexHeld = $false
$EventDriven = ($FromSource -ne 'schedule')

function Write-Log([string]$Message) {
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -LiteralPath $Log -Value $line -Encoding UTF8
}

function Release-PushMutex {
    if ($script:PushMutexHeld -and $script:PushMutex) {
        try { [void]$script:PushMutex.ReleaseMutex() } catch { }
        try { $script:PushMutex.Dispose() } catch { }
        $script:PushMutexHeld = $false
    }
}

function Test-SourceToday {
    param([string]$Day)
    $hits = [ordered]@{
        ai            = Test-Path -LiteralPath ("C:\Users\AI-PC-DEV\Documents\ai-news\data\{0}_news.json" -f $Day)
        gov           = (
            (Test-Path -LiteralPath ("C:\Users\AI-PC-DEV\Documents\Gov-News-GitHub\gov-news-thailand\data\{0}_news.json" -f $Day)) -or
            (Test-Path -LiteralPath ("C:\Users\AI-PC-DEV\Documents\Gov-News-GitHub\github-pages\data\{0}_news.json" -f $Day)) -or
            (Test-Path -LiteralPath ("C:\Users\AI-PC-DEV\Documents\Gov-News-GitHub\Document\{0}_News\{0}_news.json" -f $Day))
        )
        police_crime  = Test-Path -LiteralPath ("C:\Users\AI-PC-DEV\Documents\police-news-intel-kit\github-pages\data\{0}_crime.json" -f $Day)
        police_cyber  = Test-Path -LiteralPath ("C:\Users\AI-PC-DEV\Documents\police-news-intel-kit\github-pages\data\{0}_cyber.json" -f $Day)
        police_graph  = Test-Path -LiteralPath 'C:\Users\AI-PC-DEV\Documents\police-news-intel-kit\github-pages\data\graph.json'
        police_tunnel = Test-Path -LiteralPath 'C:\Users\AI-PC-DEV\Documents\police-news-intel-kit\github-pages\data\tunnel.json'
        tech_law      = Test-Path -LiteralPath ("C:\Users\AI-PC-DEV\Documents\tech-law-thailand\data\{0}\content.json" -f $Day)
    }
    return $hits
}

function Wait-ForCoreSources {
    param(
        [string]$Day,
        [int]$Attempts,
        [int]$Seconds
    )
    for ($i = 1; $i -le $Attempts; $i++) {
        $hits = Test-SourceToday -Day $Day
        $coreReady = $hits.ai -and $hits.gov -and $hits.police_crime
        Write-Log ("Source check {0}/{1}: ai={2} gov={3} police={4} cyber={5} graph={6} tunnel={7} tech-law={8}" -f `
            $i, $Attempts, $hits.ai, $hits.gov, $hits.police_crime, $hits.police_cyber, $hits.police_graph, $hits.police_tunnel, $hits.tech_law)
        if ($coreReady) { return $hits }
        if ($i -lt $Attempts) {
            Write-Log ("Waiting {0}s for core sources (ai/gov/police)..." -f $Seconds)
            Start-Sleep -Seconds $Seconds
        }
    }
    return (Test-SourceToday -Day $Day)
}

function Set-GitAuthorEnv {
    if (-not $env:GIT_AUTHOR_NAME) { $env:GIT_AUTHOR_NAME = 'News to Business Bot' }
    if (-not $env:GIT_AUTHOR_EMAIL) { $env:GIT_AUTHOR_EMAIL = 'chirapathleo.saelim@gmail.com' }
    if (-not $env:GIT_COMMITTER_NAME) { $env:GIT_COMMITTER_NAME = $env:GIT_AUTHOR_NAME }
    if (-not $env:GIT_COMMITTER_EMAIL) { $env:GIT_COMMITTER_EMAIL = $env:GIT_AUTHOR_EMAIL }
    Write-Log ("Git author env: {0} <{1}>" -f $env:GIT_AUTHOR_NAME, $env:GIT_AUTHOR_EMAIL)
}

$env:Path = 'C:\Program Files\Git\cmd;C:\Program Files\Git\bin;' + $env:Path
$env:HTTP_PROXY = ''
$env:HTTPS_PROXY = ''
$env:http_proxy = ''
$env:https_proxy = ''
$env:ALL_PROXY = ''
$env:all_proxy = ''
$env:NO_PROXY = '*'
$env:no_proxy = '*'
$env:GIT_TERMINAL_PROMPT = '0'

# Event-driven callers may overlap (e.g. AI+Gov at 18:00). Wait so both runs
# complete instead of the second exiting SKIP with stale unified data.
$mutexWaitMs = if ($EventDriven) { 600000 } else { 0 }
$script:PushMutex = New-Object System.Threading.Mutex($false, 'Global\NewsToBusinessDailyPush')
try {
    $script:PushMutexHeld = $script:PushMutex.WaitOne($mutexWaitMs)
} catch [System.Threading.AbandonedMutexException] {
    $script:PushMutexHeld = $true
}
if (-not $script:PushMutexHeld) {
    Write-Log ("Another News-to-Business DailyPush is already running (waited {0}ms). RESULT=SKIP" -f $mutexWaitMs)
    exit 0
}

try {
    Write-Log ("=== News-to-Business DailyPush START (FromSource={0} Retry={1}) ===" -f $FromSource, [bool]$Retry)
    Write-Log ("Repo={0} Today={1}" -f $Repo, $Today)

    if (-not (Test-Path -LiteralPath $SyncScript)) {
        Write-Log ("ERROR: missing {0}" -f $SyncScript)
        Write-Log 'RESULT=FAIL'
        $script:ExitCode = 1
        exit 1
    }
    if (-not (Test-Path -LiteralPath $SourcesFile)) {
        Write-Log ("ERROR: missing {0}" -f $SourcesFile)
        Write-Log 'RESULT=FAIL'
        $script:ExitCode = 1
        exit 1
    }

    if ($EventDriven) {
        # Immediate refresh after one topic published — sync whatever is on disk.
        $hits = Test-SourceToday -Day $Today
        Write-Log ("Event trigger from '{0}': ai={1} gov={2} police={3} cyber={4} tech-law={5}" -f `
            $FromSource, $hits.ai, $hits.gov, $hits.police_crime, $hits.police_cyber, $hits.tech_law)
    } else {
        # Evening failsafe: wait briefly for core files if Retry, else short wait.
        $attempts = if ($Retry) { 12 } else { 6 }
        $seconds = if ($Retry) { 30 } else { 20 }
        $hits = Wait-ForCoreSources -Day $Today -Attempts $attempts -Seconds $seconds
        if (-not ($hits.ai -and $hits.gov -and $hits.police_crime)) {
            Write-Log 'WARN: core sources still incomplete after wait — syncing whatever is available'
        }
        if (-not $hits.tech_law) {
            Write-Log 'INFO: no tech-law content for today (normal when no new law round)'
        }
    }

    $syncArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $SyncScript)
    if ($FullHistory) { $syncArgs += '-FullHistory' }
    Write-Log 'Running Sync-FromSources.ps1'
    & powershell.exe @syncArgs 2>&1 | ForEach-Object { Write-Log ("  sync: {0}" -f $_) }
    if ($LASTEXITCODE -ne 0) {
        Write-Log ("ERROR: sync exit={0}" -f $LASTEXITCODE)
        Write-Log 'RESULT=FAIL'
        $script:ExitCode = 1
        exit 1
    }

    $unified = [ordered]@{
        ai     = Test-Path -LiteralPath (Join-Path $Repo ("data\ai\{0}_news.json" -f $Today))
        gov    = Test-Path -LiteralPath (Join-Path $Repo ("data\gov\{0}_news.json" -f $Today))
        police = Test-Path -LiteralPath (Join-Path $Repo ("data\police\{0}_crime.json" -f $Today))
        cyber  = Test-Path -LiteralPath (Join-Path $Repo ("data\police\{0}_cyber.json" -f $Today))
        feed   = Test-Path -LiteralPath (Join-Path $Repo 'data\feed.json')
        graph  = Test-Path -LiteralPath (Join-Path $Repo 'data\police\graph.json')
        tunnel = Test-Path -LiteralPath (Join-Path $Repo 'data\police\tunnel.json')
    }
    Write-Log ("Unified today: ai={0} gov={1} police={2} cyber={3} feed={4} graph={5} tunnel={6}" -f `
        $unified.ai, $unified.gov, $unified.police, $unified.cyber, $unified.feed, $unified.graph, $unified.tunnel)

    if ($SkipPush) {
        Write-Log 'SkipPush set — local sync only. RESULT=PASS'
        $script:ExitCode = 0
        exit 0
    }

    if (-not (Test-Path -LiteralPath $PushBat)) {
        Write-Log ("ERROR: missing {0}" -f $PushBat)
        Write-Log 'RESULT=FAIL'
        $script:ExitCode = 1
        exit 1
    }

    Set-GitAuthorEnv
    Write-Log 'Running PUSH.bat'
    $p = Start-Process -FilePath $PushBat -WorkingDirectory $Repo -Wait -PassThru -NoNewWindow
    $code = 1
    if ($null -ne $p -and $null -ne $p.ExitCode) { $code = [int]$p.ExitCode }
    if ($code -eq 0) {
        Write-Log 'RESULT=PASS'
        Write-Log 'SUCCESS https://chiraleo2000.github.io/news-to-business-site/'
        $script:ExitCode = 0
    } else {
        Write-Log ("RESULT=FAIL push_exit={0}" -f $code)
        $script:ExitCode = 1
    }
    exit $script:ExitCode
}
finally {
    Release-PushMutex
}
