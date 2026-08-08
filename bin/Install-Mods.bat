@echo off
rem One-click install of the bundled catalog mods and client pak mods.
rem Requires the payload archives/folders to be present under the vendor\ folder.
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pwmod.ps1" install ue4ss
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pwmod.ps1" install palminimap
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pwmod.ps1" install dungeonbosstimer
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pwmod.ps1" install betternightlight
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pwmod.ps1" install allstorageslotsx10
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pwmod.ps1" install basecampconstructionareax2
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pwmod.ps1" install paldisassemblyconveyor100slots
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pwmod.ps1" doctor
endlocal
pause