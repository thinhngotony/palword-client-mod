@echo off
rem =====================================================================
rem  Palworld client mods - one click uninstall (all catalog mods)
rem  Usage:  uninstall-everything.bat                 auto-detect game dir
rem          uninstall-everything.bat "<game dir>"    specify a path
rem =====================================================================
setlocal
cd /d "%~dp0"

set "GAME=%~1"

if defined GAME (
    powershell -NoProfile -ExecutionPolicy Bypass -File "bin\pwmod.ps1" set-path "%GAME%"
    if errorlevel 1 goto :fail
    goto :uninstall
)

rem Auto-detect - pwmod exits nonzero only when the game path is missing.
powershell -NoProfile -ExecutionPolicy Bypass -File "bin\pwmod.ps1" list >nul 2>&1
if errorlevel 1 goto :needpath

:uninstall

echo.
echo [1/7] Pal Disassembly Conveyor 100 Slots .........
powershell -NoProfile -ExecutionPolicy Bypass -File "bin\pwmod.ps1" remove paldisassemblyconveyor100slots
if errorlevel 1 goto :fail
echo [2/7] Base Camp Construction Area x2 ............
powershell -NoProfile -ExecutionPolicy Bypass -File "bin\pwmod.ps1" remove basecampconstructionareax2
if errorlevel 1 goto :fail
echo [3/7] Easy Storage Slots 10x .....................
powershell -NoProfile -ExecutionPolicy Bypass -File "bin\pwmod.ps1" remove easystorageslotsx10
if errorlevel 1 goto :fail
echo [4/7] Better Night Light ........................
powershell -NoProfile -ExecutionPolicy Bypass -File "bin\pwmod.ps1" remove betternightlight
if errorlevel 1 goto :fail
echo [5/7] DungeonBossRespawnMapTimer ................
powershell -NoProfile -ExecutionPolicy Bypass -File "bin\pwmod.ps1" remove dungeonbosstimer
if errorlevel 1 goto :fail
echo [6/7] PalMiniMap ................................
powershell -NoProfile -ExecutionPolicy Bypass -File "bin\pwmod.ps1" remove palminimap
if errorlevel 1 goto :fail
echo [7/7] UE4SS loader/runtime ......................
powershell -NoProfile -ExecutionPolicy Bypass -File "bin\pwmod.ps1" remove ue4ss
if errorlevel 1 goto :fail

echo.
echo Verifying clean baseline .......................
powershell -NoProfile -ExecutionPolicy Bypass -File "bin\pwmod.ps1" doctor
goto :end

:needpath
echo.
echo [ERROR] Could not auto-detect your Palworld install.
echo.
echo Your Steam library may be on a different drive/folder.
echo Run this with the exact game folder for THIS machine:
echo     uninstall-everything.bat "D:\Steam\steamapps\common\Palworld"
echo (put the path where Palworld actually is on this machine)
goto :end

:fail
echo.
echo [FAILED] See the messages above for which step broke.
goto :end

:end
echo.
pause
endlocal