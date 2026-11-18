@echo off
setlocal EnableExtensions
cd /d "%~dp0"

set "LOGDIR=%~dp0Logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set "TODAY=%%i"
set "LOG=%LOGDIR%\push-%TODAY%.log"

echo [%DATE% %TIME%] PUSH.bat start>> "%LOG%"

where git >nul 2>&1
if errorlevel 1 (
  echo ERROR: git not found>> "%LOG%"
  echo RESULT=FAIL>> "%LOG%"
  exit /b 1
)

git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
  echo ERROR: not a git repo>> "%LOG%"
  echo RESULT=FAIL>> "%LOG%"
  exit /b 1
)

git add -- "index.html" "police-intel.html" "assets" "js" "data" "sources.json" ".nojekyll" "README.md" "Sync-FromSources.ps1" "DailyPush.ps1" "Register-DailyPushSchedule.ps1" "PUSH.bat" 1>> "%LOG%" 2>&1

git diff --cached --quiet
if %ERRORLEVEL%==0 (
  echo No staged site changes. RESULT=PASS SKIP>> "%LOG%"
  echo RESULT=PASS
  exit /b 0
)

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH:mm'"') do set "STAMP=%%i"
git commit -m "chore: sync unified news feed %STAMP%" 1>> "%LOG%" 2>&1
if errorlevel 1 (
  echo RESULT=FAIL commit>> "%LOG%"
  echo RESULT=FAIL
  exit /b 1
)

git push origin HEAD 1>> "%LOG%" 2>&1
if errorlevel 1 (
  echo RESULT=FAIL push>> "%LOG%"
  echo RESULT=FAIL
  exit /b 1
)

echo RESULT=PASS>> "%LOG%"
echo RESULT=PASS
exit /b 0
