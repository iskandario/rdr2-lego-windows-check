@echo off
setlocal
title RDR2 + LEGO III - Installation Check
echo This checks Steam game versions. This is NOT a playable crossover mod.
echo No game files are changed. Nothing is uploaded.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Check-Games.ps1"
if errorlevel 1 echo Check failed. Please send the error text from this window.
echo.
pause
