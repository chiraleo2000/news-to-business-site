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

foreach ($common in @(
    'C:\Scripts\SchedulerCommon.ps1'
    (Join-Path $env:USERPROFILE 'Documents\Powershell-Scheduler\SchedulerCommon.ps1')
)) {
    if (Test-Path -LiteralPath $common) { . $common; break }
}
if (Get-Command Initialize-SchedulerEnv -ErrorAction SilentlyContinue) {
    Initialize-SchedulerEnv
} else {
    $env:Path = "C:\Program Files\Git\cmd;C:\Program Files\Git\bin;" + $env:Path
    $env:HTTP_PROXY = ''; $env:HTTPS_PROXY = ''; $env:http_proxy = ''; $env:https_proxy = ''
    $env:ALL_PROXY = ''; $env:all_proxy = ''; $env:NO_PROXY = '*'; $env:no_proxy = '*'
    $env:GIT_TERMINAL_PROMPT = '0'
}

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

function Test-AnyUsableSource {
    param($Hits)
    return [bool]($Hits.ai -or $Hits.gov -or $Hits.police_crime -or $Hits.police_cyber -or $Hits.tech_law)
}

function Wait-ForUsableSources {
    param(
        [string]$Day,
        [int]$Attempts,
        [int]$Seconds
    )
    # Failsafe should NOT block for missing Gov/Tech when AI/Police already exist.
    # Only wait when nothing usable is on disk yet.
    for ($i = 1; $i -le $Attempts; $i++) {
        $hits = Test-SourceToday -Day $Day
        $usable = Test-AnyUsableSource -Hits $hits
        Write-Log ("Source check {0}/{1}: ai={2} gov={3} police={4} cyber={5} graph={6} tunnel={7} tech-law={8} usable={9}" -f `
            $i, $Attempts, $hits.ai, $hits.gov, $hits.police_crime, $hits.police_cyber, $hits.police_graph, $hits.police_tunnel, $hits.tech_law, $usable)
        if ($usable) { return $hits }
        if ($i -lt $Attempts) {
            Write-Log ("Waiting {0}s for any usable source..." -f $Seconds)
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
# Failsafe also waits briefly so it does not race an in-flight event trigger.
$mutexWaitMs = if ($EventDriven) { 600000 } else { 180000 }
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
        # Evening failsafe: sync as soon as ANY usable source exists (do not block on Gov).
        $attempts = if ($Retry) { 8 } else { 3 }
        $seconds = if ($Retry) { 20 } else { 15 }
        $hits = Wait-ForUsableSources -Day $Today -Attempts $attempts -Seconds $seconds
        if (-not (Test-AnyUsableSource -Hits $hits)) {
            Write-Log 'WARN: no usable sources after wait — syncing cached/history anyway'
        }
        if (-not $hits.gov) { Write-Log 'INFO: no gov news for today yet (will refresh when Gov DailyPush finishes)' }
        if (-not $hits.tech_law) { Write-Log 'INFO: no tech-law content for today (normal when no new law round)' }
    }

    Write-Log 'Running Sync-FromSources.ps1'
    $syncArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $SyncScript)
    if ($FullHistory) { $syncArgs += '-FullHistory' }
    $syncExit = 1
    if (Get-Command Invoke-BoundedProcess -ErrorAction SilentlyContinue) {
        $syncResult = Invoke-BoundedProcess -FilePath 'powershell.exe' -ArgumentList $syncArgs `
            -WorkingDirectory $Repo -TimeoutSec 900 -OnLine { param($l) Write-Log ("  sync: {0}" -f $l) }
        if ($syncResult.TimedOut) {
            Write-Log 'ERROR: Sync-FromSources timed out after 15m — killed'
            Write-Log 'RESULT=FAIL'
            $script:ExitCode = 1
            exit 1
        }
        $syncExit = [int]$syncResult.ExitCode
    } else {
        # Fallback: stdout/stderr must be different files (Start-Process requirement)
        $syncOut = Join-Path $env:TEMP ("ntb-sync-{0}.out.log" -f (Get-Date -Format 'yyyyMMddHHmmss'))
        $syncErr = Join-Path $env:TEMP ("ntb-sync-{0}.err.log" -f (Get-Date -Format 'yyyyMMddHHmmss'))
        $syncProc = Start-Process -FilePath 'powershell.exe' -ArgumentList $syncArgs `
            -WorkingDirectory $Repo -PassThru -NoNewWindow `
            -RedirectStandardOutput $syncOut -RedirectStandardError $syncErr
        $syncOk = $syncProc.WaitForExit(900000)
        if (-not $syncOk) {
            Write-Log 'ERROR: Sync-FromSources timed out after 15m — killing'
            try { & taskkill.exe /PID $syncProc.Id /T /F 2>$null | Out-Null } catch { }
            Write-Log 'RESULT=FAIL'
            $script:ExitCode = 1
            exit 1
        }
        foreach ($f in @($syncOut, $syncErr)) {
            if (Test-Path -LiteralPath $f) {
                Get-Content -LiteralPath $f -ErrorAction SilentlyContinue | ForEach-Object { Write-Log ("  sync: {0}" -f $_) }
                Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
            }
        }
        $syncExit = [int]$syncProc.ExitCode
    }
    if ($syncExit -ne 0) {
        Write-Log ("ERROR: sync exit={0}" -f $syncExit)
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
