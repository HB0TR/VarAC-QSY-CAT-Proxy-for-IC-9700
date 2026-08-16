@echo off
title VarAC QSY-CAT Proxy for IC-9700 by HB0TR V5.00
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0VarAC_QSY-CAT_Proxy_IC-9700_HB0TR.ps1"
echo.
echo Proxy stopped. Press any key to close.
pause >nul
