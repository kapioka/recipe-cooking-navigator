@echo off
pwsh.exe -NoProfile -File "%~dp0tool\build-release.ps1"
set "build_result=%errorlevel%"
pause
exit /b %build_result%
