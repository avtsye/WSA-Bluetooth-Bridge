@echo off
chcp 65001 >nul
title WSA Bluetooth Bridge - Root Upgrade
echo ============================================
echo WSA Bluetooth Bridge - Root/Magisk Upgrade
echo ============================================
echo.
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0Upgrade-Wsa.ps1" -ForceRoot
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
  echo ============================================
  echo ERROR: Root/Magisk upgrade failed. Exit code: %RC%
  echo ============================================
  echo.
  echo Logs:
  echo   %LOCALAPPDATA%\WSABluetoothBridge\wsa-upgrade.log
  echo   C:\ProgramData\WSABluetoothBridge\root-bootstrap.log
  echo.
  echo This window will stay open.
  pause
)
exit /b %RC%
