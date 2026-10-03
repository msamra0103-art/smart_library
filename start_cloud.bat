@echo off
chcp 65001 >nul
where py >nul 2>nul
if %errorlevel%==0 (
  start "" http://localhost:8080/index.html
  py -m http.server 8080
  exit /b
)
where python >nul 2>nul
if %errorlevel%==0 (
  start "" http://localhost:8080/index.html
  python -m http.server 8080
  exit /b
)
start "" index.html
