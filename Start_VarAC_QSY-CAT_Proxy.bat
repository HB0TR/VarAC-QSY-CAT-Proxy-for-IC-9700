@echo off
title VarAC QSY-CAT Proxy for IC-9700 by HB0TR V5.03
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0VarAC_QSY-CAT_Proxy_IC-9700_HB0TR.ps1"
set "proxy_rc=%ERRORLEVEL%"
if not "%proxy_rc%"=="0" (
  echo.
  echo Proxy stopped with error code %proxy_rc%.
  echo Press any key to close.
  pause >nul
)
exit /b %proxy_rc%
