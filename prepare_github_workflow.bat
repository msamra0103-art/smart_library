@echo off
setlocal
cd /d "%~dp0"
if not exist ".github\workflows" mkdir ".github\workflows"
copy /Y "KEEPALIVE_GITHUB_ACTIONS.yml" ".github\workflows\keepalive.yml" >nul
if errorlevel 1 (
  echo Failed to prepare GitHub workflow.
  pause
  exit /b 1
)
echo.
echo GitHub workflow is ready at:
echo .github\workflows\keepalive.yml
echo.
echo Upload ALL files and folders in this package to the repository root.
pause
