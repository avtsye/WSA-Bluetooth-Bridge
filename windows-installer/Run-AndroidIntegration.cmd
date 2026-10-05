@echo off
chcp 65001 >nul
title WSA Bluetooth Bridge - Android Integration
echo ============================================
echo WSA Bluetooth Bridge - Android/Audio HAL
echo ============================================
echo.
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0Install-WsaSystem.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
  echo ============================================
  echo ERROR: Android integration failed. Exit code: %RC%
  echo ============================================
  echo.
  echo Log:
  echo   C:\ProgramData\WSABluetoothBridge\android-integration.log
  echo.
  echo This window will stay open.
  pause
)
exit /b %RC%
