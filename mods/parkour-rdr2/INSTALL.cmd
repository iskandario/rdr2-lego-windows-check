@echo off
setlocal
title Assassin Traversal - EXPERIMENTAL RDR2 mod
if not exist "%~dp0Install.ps1" (
  echo Extract the ENTIRE ZIP to a folder first. Do not run inside WinRAR.
  pause
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Install.ps1"
set "installResult=%errorlevel%"
pause
exit /b %installResult%
