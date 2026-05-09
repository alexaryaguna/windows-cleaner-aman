@echo off
setlocal
set SCRIPT_DIR=%~dp0
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%SCRIPT_DIR%src\WindowsCleaner.ps1" %*
exit /b %ERRORLEVEL%
