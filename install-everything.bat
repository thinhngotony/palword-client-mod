@echo off
rem =====================================================================
rem  Palworld client mods - one click install (all catalog mods)
rem  Usage:  install-everything.bat                  auto-detect game dir
rem          install-everything.bat "<game dir>"     specify a path
rem =====================================================================
setlocal
cd /d "%~dp0"

set "GAME=%~1"

if defined GAME (
    powershell -NoProfile -ExecutionPolicy Bypass -File "bin\pwmod.ps1" set-path "%GAME%"
    if errorlevel 1 goto :fail
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module '%~dp0src\PalModMan.psm1' -Force; try { Get-PalworldPath | Out-Null; exit 0 } catch { exit 1 }"
    if errorlevel 1 goto :needpath
)

echo.
echo [1/8] UE4SS loader/runtime ...................
powershell -NoProfile -ExecutionPolicy Bypass -File "bin\pwmod.ps1" install ue4ss
if errorlevel 1 goto :fail
echo [2/8] PalMiniMap ................................
powershell -NoProfile -ExecutionPolicy Bypass -File "bin\pwmod.ps1" install palminimap
if errorlevel 1 goto :fail
echo [3/8] DungeonBossRespawnMapTimer .................
powershell -NoProfile -ExecutionPolicy Bypass -File "bin\pwmod.ps1" install dungeonbosstimer
if errorlevel 1 goto :fail
echo [4/8] Better Night Light ........................
powershell -NoProfile -ExecutionPolicy Bypass -File "bin\pwmod.ps1" install betternightlight
if errorlevel 1 goto :fail
echo [5/8] Easy Storage Slots 10x ....................
powershell -NoProfile -ExecutionPolicy Bypass -File "bin\pwmod.ps1" install easystorageslotsx10
if errorlevel 1 goto :fail
echo [6/8] Base Camp Construction Area x2 ...........
powershell -NoProfile -ExecutionPolicy Bypass -File "bin\pwmod.ps1" install basecampconstructionareax2
if errorlevel 1 goto :fail
echo [7/8] Pal Disassembly Conveyor 100 Slots ........
powershell -NoProfile -ExecutionPolicy Bypass -File "bin\pwmod.ps1" install paldisassemblyconveyor100slots
if errorlevel 1 goto :fail
echo [8/8] Health check ................................
powershell -NoProfile -ExecutionPolicy Bypass -File "bin\pwmod.ps1" doctor
goto :end

:needpath
echo.
echo [ERROR] Could not auto-detect your Palworld install.
echo Run:   install-everything.bat "C:\Path\To\Palworld"
echo e.g.   install-everything.bat "C:\Program Files (x86)\Steam\steamapps\common\Palworld"
goto :end

:fail
echo.
echo [FAILED] See the messages above for which step broke.
goto :end

:end
echo.
pause
endlocal