@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Stop-OpsBeacon.ps1" %*
set "BeaconStopExit=%ERRORLEVEL%"
pause
exit /b %BeaconStopExit%
