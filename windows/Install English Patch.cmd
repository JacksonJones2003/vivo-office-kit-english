@echo off
rem Opens the vivo Office Kit English patch installer. Windows will ask for administrator permission.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0install.ps1" %*
