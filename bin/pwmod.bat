@echo off
rem pwmod passthrough launcher (double-click or run with args)
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pwmod.ps1" %*
endlocal