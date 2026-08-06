@echo off
title Palworld Mod Installer
echo ============================================
echo   Palworld one-click mod installer
echo ============================================
echo.
echo This will install:
echo   - UE4SS mod loader
echo   - PalMiniMap
echo   - DungeonBossRespawnMapTimer
echo   - Better Night Light
echo.
echo The game will ask for Administrator permission
echo (needed to write into the game folder).
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_palworld_mods.ps1"
