#Requires -Version 5.1
# Register News-to-Business daily sync/push:
#   18:45 — after AI-News-EveningPush + Gov-News-DailyPush (both 18:00)
#   20:30 — retry after Gov-News-RetryPush (20:00)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$TaskName = 'News-to-Business-DailyPush'
$RetryName = 'News-to-Business-RetryPush'
$Script = Join-Path $Repo 'DailyPush.ps1'
$Sid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value

if (-not (Test-Path -LiteralPath $Script)) {
    throw "Missing DailyPush.ps1 at $Script"
}

function Register-NtbTask {
    param(
        [string]$Name,
        [string]$Uri,
        [string]$Description,
        [string]$StartBoundary,
        [string]$ExtraArgs = ''
    )
    $argTail = if ($ExtraArgs) { " $ExtraArgs" } else { '' }
    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>$Description</Description>
    <URI>\$Uri</URI>
  </RegistrationInfo>
  <Principals>
    <Principal id="Author">
      <UserId>$Sid</UserId>
      <LogonType>InteractiveToken</LogonType>
    </Principal>
  </Principals>
  <Settings>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <StartWhenAvailable>true</StartWhenAvailable>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
  </Settings>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>$StartBoundary</StartBoundary>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -ExecutionPolicy Bypass -File "$Script"$argTail</Arguments>
      <WorkingDirectory>$Repo</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@
    $xmlPath = Join-Path $env:TEMP ("{0}.xml" -f $Name)
    Set-Content -LiteralPath $xmlPath -Value $xml -Encoding Unicode
    schtasks /Create /TN $Name /XML $xmlPath /F | Out-Host
    $t = Get-ScheduledTask -TaskName $Name
    $info = $t | Get-ScheduledTaskInfo
    Write-Host ("Registered {0} State={1} NextRun={2}" -f $t.TaskName, $t.State, $info.NextRunTime)
}

Register-NtbTask -Name $TaskName -Uri 'News-to-Business-DailyPush' `
    -Description 'Daily News-to-Business sync/push at 18:45 after AI/Gov 18:00 pipelines' `
    -StartBoundary '2026-11-18T18:45:00+07:00'

Register-NtbTask -Name $RetryName -Uri 'News-to-Business-RetryPush' `
    -Description 'Retry News-to-Business sync/push at 20:30 after Gov-Retry 20:00' `
    -StartBoundary '2026-11-18T20:30:00+07:00' `
    -ExtraArgs '-Retry'
