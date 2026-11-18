#Requires -Version 5.1
# Register News-to-Business-DailyPush at 15:00 (3:00 PM) daily — after topic pipelines finish.
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$TaskName = 'News-to-Business-DailyPush'
$Script = Join-Path $Repo 'DailyPush.ps1'
$Sid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value

if (-not (Test-Path -LiteralPath $Script)) {
    throw "Missing DailyPush.ps1 at $Script"
}

$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Daily News-to-Business: sync AI/Gov/Police/Tech-Law into one GitHub Pages site at 15:00</Description>
    <URI>\News-to-Business-DailyPush</URI>
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
      <StartBoundary>2026-11-18T15:00:00+07:00</StartBoundary>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -ExecutionPolicy Bypass -File "$Script"</Arguments>
      <WorkingDirectory>$Repo</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

$xmlPath = Join-Path $env:TEMP 'News-to-Business-DailyPush.xml'
Set-Content -LiteralPath $xmlPath -Value $xml -Encoding Unicode
schtasks /Create /TN $TaskName /XML $xmlPath /F | Out-Host

$t = Get-ScheduledTask -TaskName $TaskName
$info = $t | Get-ScheduledTaskInfo
Write-Host ("Registered {0} State={1} NextRun={2}" -f $t.TaskName, $t.State, $info.NextRunTime)
