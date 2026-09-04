# 🎮 Universal Game Relocator

A lightweight, zero-dependency PowerShell tool to relocate and fix installation paths or drive letters for PC games without re-downloading them.

Supports **Epic Games Launcher**, **Ubisoft Connect (Uplay)**, **EA App (EA Play / Origin)**, **Wargaming.net Game Center**, **Rockstar Games Launcher**, and **GOG Galaxy**.

---

## ✨ Features

- 🕹️ **Multi-Platform Support**:
  - **Epic Games Launcher**: Automatically edits `.item` manifest JSON files (`InstallLocation`, `ManifestLocation`, etc.) and restores pending installs.
  - **Ubisoft Connect (Uplay)**: Automatically updates `HKLM\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs\<AppId>` and game configuration keys.
  - **EA App / EA Play**: Updates `HKLM\SOFTWARE\WOW6432Node\EA Games\<Game>` and `Electronic Arts` registry paths (`Install Dir`).
  - **Wargaming.net Game Center**: Automatically links and updates game installations inside `C:\ProgramData\Wargaming.net\GameCenter\preferences.xml` and uninstall registry entries (*World of Tanks*, *World of Warships*, *World of Warplanes*).
  - **Rockstar Games Launcher**: Updates `HKLM\SOFTWARE\WOW6432Node\Rockstar Games\...` registry entries (`InstallFolderEpic` / `InstallFolder`) for titles like *Grand Theft Auto V* and *Red Dead Redemption 2*.
  - **GOG Galaxy**: Updates `HKLM\SOFTWARE\WOW6432Node\GOG.com\Games\<GameId>` registry paths (`PATH`).
- 🧹 **Clean Ghost & Stuck Manifests**: Deleted a game folder or removed an external drive and now the launcher refuses to let you reinstall? Clean and unregister ghost manifests instantly (`-Unregister` or `-CleanGhosts`).
- ⚡ **Bulk Drive Migration**: Swapped drives or changed drive letters (e.g., `D:` to `E:`)? Update all games across all launchers with a single command.
- 🎮 **Interactive Menu**: User-friendly colored CLI menu to browse games, check status, and enter new paths.
- 🛡️ **Safe & Non-Destructive**: Backs up manifests before editing (`.bak`), detects running launcher processes, and supports `-DryRun` simulation mode.
- 🔍 **Health Check / Listing**: `-List` displays all detected games, their platform, and verifies whether the game directory exists on disk.

---

## 📦 Quick Start

### Option A: Double-Click Runner
Double-click `relocate.bat` in File Explorer to launch the interactive menu.

### Option B: PowerShell CLI

Open PowerShell (as Administrator) and run:

```powershell
# 1. List all detected games across all platforms & check disk status
.\GameRelocator.ps1 -List

# 2. Relocate a specific game
.\GameRelocator.ps1 -Game "Need for Speed" -NewPath "E:\Games\Need for Speed"
.\GameRelocator.ps1 -Game "Watch_Dogs" -NewPath "E:\Games\Watch_Dogs"
.\GameRelocator.ps1 -Game "Grand Theft Auto V Enhanced" -NewPath "E:\Games\GTAVEnhanced"

# 3. Bulk change drive letters across ALL launchers (e.g. D: -> E:)
.\GameRelocator.ps1 -OldDrive "D:" -NewDrive "E:"

# 4. Dry run (simulate changes without modifying files or registry)
.\GameRelocator.ps1 -Game "Control" -NewPath "E:\Games\Control" -DryRun

# 5. Interactive menu
.\GameRelocator.ps1
```

---

## 🛠️ CLI Parameters

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `-List` | Switch | Lists all detected games across platforms, their paths, and disk status. |
| `-Platform <Epic|Ubisoft|EA|Wargaming|Rockstar|GOG|All>` | String | Filter games by platform (defaults to `All`). |
| `-Game <Name/ID>` | String | Game display name, app name, or installation GUID. |
| `-NewPath <Path>` | String | The target folder path on disk. |
| `-OldDrive <Drive>` | String | Old drive letter (e.g. `D:` or `D`) for bulk updates. |
| `-NewDrive <Drive>` | String | New drive letter (e.g. `E:` or `E`) for bulk updates. |
| `-DryRun` | Switch | Preview changes without modifying any files or registry keys. |
| `-Force` | Switch | Bypass interactive prompts (e.g. terminating open launcher processes). |

---

## 📋 How It Works

### Ghost Manifests & Reinstall Fix
When a game folder is deleted or moved to an unplugged drive, launchers like Epic Games and Ubisoft still store the game as "installed" in local manifests (`.item`) or registry keys (`Installs\<AppId>`). The launcher UI gets stuck in "Verify", "Resume", or broken state and disables the "Install" button. **Game Relocator** cleans these ghost records so the launcher immediately enables fresh download & installation.

### Epic Games Launcher
Epic Games stores installation data inside JSON manifests located at `C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests\<GUID>.item`. When a drive letter changes or folders move, Epic marks them as incomplete or pending. **Game Relocator** updates all internal manifest paths (`InstallLocation`, `ManifestLocation`, `CompleteManifestPath`, `PendingManifestPath`, `StagingLocation`) and sets `bIsIncompleteInstall: false`.

### Ubisoft Connect (Uplay)
Ubisoft Connect stores game installation directories in the Windows Registry under `HKLM\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs\<AppId>\InstallDir`. **Game Relocator** updates the corresponding AppID registry values and individual game configuration keys to the new folder.

### EA App (EA Play / Origin)
EA games store installation folders under `HKLM\SOFTWARE\WOW6432Node\EA Games\<Game>` and `Electronic Arts` (`Install Dir`). **Game Relocator** updates these paths to point to your new directory or drive.

### Wargaming.net Game Center
Wargaming Game Center stores installed game instance directories in `C:\ProgramData\Wargaming.net\GameCenter\preferences.xml` under `<games_manager><games>`. When WGC is reinstalled or when game folders are moved, **Game Relocator** registers the folder paths and updates the Windows uninstall registry.

### Rockstar Games Launcher
Titles like *GTA V* and *Red Dead Redemption 2* store their installation directories under `HKLM\SOFTWARE\WOW6432Node\Rockstar Games\...` in values such as `InstallFolderEpic` and `InstallFolder`. **Game Relocator** keeps these synchronized with your launcher installations.

### GOG Galaxy
GOG games store installation paths under `HKLM\SOFTWARE\WOW6432Node\GOG.com\Games\<GameId>\PATH`. **Game Relocator** updates this directory seamlessly.

---

## 📄 License

MIT License. Free to use, modify, and distribute.
