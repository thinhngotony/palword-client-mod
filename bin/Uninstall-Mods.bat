@echo off
rem One-click uninstaller - removes all catalog mods for a clean baseline.
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pwmod.ps1" remove paldisassemblyconveyor100slots
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pwmod.ps1" remove basecampconstructionareax2
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pwmod.ps1" remove easystorageslotsx10
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pwmod.ps1" remove betternightlight
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pwmod.ps1" remove dungeonbosstimer
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pwmod.ps1" remove palminimap
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pwmod.ps1" remove ue4ss
echo.
echo Done. Run "pwmod doctor" to verify a clean baseline.
endlocal
pause