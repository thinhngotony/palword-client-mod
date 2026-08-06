PALWORLD - ONE-CLICK MOD INSTALLER
==================================

WHAT THIS INSTALLS (all client-side, safe for joining dedicated servers)
  - UE4SS mod loader (needed by the Lua mods)
  - PalMiniMap                 - minimap on your screen (F5 settings, F4 move/resize)
  - DungeonBossRespawnMapTimer - shows respawn countdown on fixed-dungeon boss icons
  - Better Night Light         - brighter nights

HOW TO INSTALL
  1. Make sure Palworld is NOT running.
  2. Double-click  Install-Mods.bat
  3. Click "Yes" when Windows asks for Administrator permission.
  4. It auto-detects the Palworld folder (registry + all Steam libraries).
     If it cannot find it, it asks you to TYPE the path to your
     Palworld folder, e.g.
         D:\SteamLibrary\steamapps\common\Palworld
     (or pass it directly in PowerShell with:
         .\install_palworld_mods.ps1 -PalworldPath "D:\Games\Palworld")
  5. Wait for "INSTALLATION COMPLETE".

  The UNINSTALLER (Uninstall-Mods.bat) auto-detects the same way and also
  asks for the path if it cannot find it.

WHAT IT DOES
  - Backs up your existing mod files into  PalMods_Backup_<date>
  - Copies UE4SS into     Pal\Binaries\Win64
  - Copies mods into      Pal\Binaries\Win64\ue4ss\Mods
  - Writes mods.txt so the two Lua mods are enabled
  - Copies the pak into   Pal\Content\Paks\~mods

AFTER INSTALLING
  1. Launch Palworld. A UE4SS console window appearing is NORMAL.
  2. PalMiniMap:  F5 = settings menu, F4 = edit mode (arrows move,
                  + / - resize), F2 = next corner, F3 = show/hide.
  3. DungeonBoss timer: after you defeat a fixed dungeon boss, its icon on
     the world map shows a live countdown until it respawns.
  4. Better Night Light makes nights brighter automatically.

UNINSTALLING
  - Close Palworld, then double-click  Uninstall-Mods.bat
    (accept the Administrator prompt).
  - It removes UE4SS, all mods, and the ~mods pak folder.
  - It also offers to restore your original files from the
    PalMods_Backup_<date> backup the installer created.
  - Or delete manually:
      Pal\Binaries\Win64\dwmapi.dll
      Pal\Binaries\Win64\ue4ss
      Pal\Content\Paks\~mods

NOTES
  - Version used: RE-UE4SS build "3035 260719" (3.0.5) for Palworld.
  - mods.txt (in ue4ss\Mods) is the load list in this build. Per-mod
    enabled.txt is ignored when mods.txt is present.
  - These mods do NOT modify your save; they are purely client-side.
