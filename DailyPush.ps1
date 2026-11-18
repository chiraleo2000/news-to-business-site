#Requires -Version 5.1
<#
.SYNOPSIS
  Daily sync from separate news repos into news-to-business-site, then push GitHub Pages.
#>
param(
    [switch]$Retry,
    [switch]$SkipPush,
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
$Log = Join-Path $LogDir ("daily-{0}.log" -f $Today)
$SyncScript = Join-Path $Repo 'Sync-FromSources.ps1'
$PushBat = Join-Path $Repo 'PUSH.bat'
$script:ExitCode = 0
$script:PushMutex = $null
$script:PushMutexHeld = $false

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

$env:Path = 'C:\Program Files\Git\cmd;C:\Program Files\Git\bin;' + $env:Path
$env:HTTP_PROXY = ''
$env:HTTPS_PROXY = ''
$env:http_proxy = ''
$env:https_proxy = ''
$env:ALL_PROXY = ''
$env:all_proxy = ''
$env:NO_PROXY = '*'
$env:no_proxy = '*'

$script:PushMutex = New-Object System.Threading.Mutex($false, 'Global\NewsToBusinessDailyPush')
try {
    $script:PushMutexHeld = $script:PushMutex.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
    $script:PushMutexHeld = $true
}
if (-not $script:PushMutexHeld) {
    Write-Log 'Another News-to-Business DailyPush is already running. RESULT=SKIP'
    exit 0
}

try {
    Write-Log ("=== News-to-Business DailyPush START (Retry={0}) ===" -f [bool]$Retry)
    Write-Log ("Repo={0} Today={1}" -f $Repo, $Today)

    if (-not (Test-Path -LiteralPath $SyncScript)) {
        Write-Log ("ERROR: missing {0}" -f $SyncScript)
        Write-Log 'RESULT=FAIL'
        $script:ExitCode = 1
        exit 1
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

    Write-Log 'Running PUSH.bat'
    $p = Start-Process -FilePath $PushBat -WorkingDirectory $Repo -Wait -PassThru -NoNewWindow
    $code = 1
    if ($null -ne $p -and $null -ne $p.ExitCode) { $code = [int]$p.ExitCode }
    if ($code -eq 0) {
        Write-Log 'RESULT=PASS'
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
