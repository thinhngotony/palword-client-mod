@echo off
title Palworld Mod Uninstaller
echo ============================================
echo   Palworld mod UNINSTALLER
echo ============================================
echo.
echo This will remove:
echo   - UE4SS mod loader
echo   - PalMiniMap
echo   - DungeonBossRespawnMapTimer
echo   - Better Night Light
echo.
echo It can also restore your original files from the
echo backup the installer created (if you made one).
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall_palworld_mods.ps1"