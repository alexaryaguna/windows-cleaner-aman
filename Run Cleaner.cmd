@echo off
setlocal
set SCRIPT_DIR=%~dp0
wscript.exe "%SCRIPT_DIR%Run Cleaner.vbs" %*
exit /b 0
