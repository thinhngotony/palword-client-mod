@echo off
rem One-click uninstaller - removes all catalog mods for a clean baseline.
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pwmod.ps1" remove betternightlight
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pwmod.ps1" remove dungeonbosstimer
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pwmod.ps1" remove palminimap
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pwmod.ps1" remove ue4ss
endlocal
pause