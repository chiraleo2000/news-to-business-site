#Requires -Version 5.1
<#
.SYNOPSIS
  Register News-to-Business failsafe evening sync/push tasks.

.DESCRIPTION
  Primary updates happen immediately after each topic Pages push via
  Trigger-AfterSourcePush.ps1 (hooked from AI / Gov / Tech / Police publish).

  These scheduled tasks are a catch-up only:
    18:45  News-to-Business-DailyPush
    20:30  News-to-Business-RetryPush -Retry
#>
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$TaskName = 'News-to-Business-DailyPush'
$RetryName = 'News-to-Business-RetryPush'
$Script = Join-Path $Repo 'DailyPush.ps1'
$Trigger = Join-Path $Repo 'Trigger-AfterSourcePush.ps1'
$Sid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value

if (-not (Test-Path -LiteralPath $Script)) {
    throw "Missing DailyPush.ps1 at $Script"
}
if (-not (Test-Path -LiteralPath $Trigger)) {
    throw "Missing Trigger-AfterSourcePush.ps1 at $Trigger"
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
    <WakeToRun>true</WakeToRun>
    <RestartOnFailure>
      <Interval>PT10M</Interval>
      <Count>1</Count>
    </RestartOnFailure>
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
    -Description 'FAILSAFE evening News-to-Business sync/push (primary updates are event-driven after each topic Pages push)' `
    -StartBoundary '2026-11-18T18:45:00+07:00'

Register-NtbTask -Name $RetryName -Uri 'News-to-Business-RetryPush' `
    -Description 'FAILSAFE retry News-to-Business sync/push after Gov-Retry window' `
    -StartBoundary '2026-11-18T20:30:00+07:00' `
    -ExtraArgs '-Retry'

Write-Host ''
Write-Host 'Primary path: each topic calls Trigger-AfterSourcePush.ps1 -Source {ai|gov|police|tech-law}'
Write-Host '  AI     -> after ai-news DailyPush PASS'
Write-Host '  Gov    -> after gov-news DailyPush PASS'
Write-Host '  Police -> after NewsIntel git-publish push ok'
Write-Host '  Tech   -> after tech-law DailyPush PASS'
Write-Host 'Live: https://chiraleo2000.github.io/news-to-business-site/'
