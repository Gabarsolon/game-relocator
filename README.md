# 🚀 Epic Game Relocator

A lightweight, zero-dependency PowerShell tool that lets you move or relocate installed Epic Games without redownloading them. It updates Epic Games Launcher manifest (`.item`) files and associated registry keys (including Rockstar Games Launcher for GTA V / RDR2) when moving games to another drive or directory.

---

## ✨ Features

- 🎮 **Interactive Menu**: Easily view all installed games and update their paths in seconds.
- ⚡ **Bulk Drive Migration**: Migrated all your games from `D:` to `E:`? Update all installations in one command.
- 🔄 **Rockstar Games Integration**: Automatically updates registry entries (`InstallFolderEpic`) for Rockstar titles (e.g. *Grand Theft Auto V*, *Red Dead Redemption 2*).
- 🛡️ **Safe & Non-Destructive**: Backs up `.item` manifests before editing (`.item.bak`) and supports `-DryRun` simulation mode.
- 🔍 **Status Inspection**: Lists all detected Epic Games manifests and highlights whether the game files currently exist on disk.

---

## 📦 Quick Start

### Option A: Double-Click Runner
Simply double-click `relocate.bat` to launch the interactive terminal UI.

### Option B: PowerShell CLI

Open PowerShell as Administrator and run:

```powershell
# 1. List all games and check if their folders exist on disk
.\EpicGameRelocator.ps1 -List

# 2. Relocate a specific game
.\EpicGameRelocator.ps1 -Game "Grand Theft Auto V Enhanced" -NewPath "E:\Games\GTAVEnhanced"

# 3. Bulk change drive letters (e.g. after changing or assigning a new drive)
.\EpicGameRelocator.ps1 -OldDrive "D:" -NewDrive "E:"

# 4. Dry run (simulate changes without applying)
.\EpicGameRelocator.ps1 -Game "Control" -NewPath "E:\Games\Control" -DryRun

# 5. Interactive menu
.\EpicGameRelocator.ps1
```

---

## 🛠️ Parameters

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `-List` | Switch | Lists all detected Epic Games, installation paths, and disk status. |
| `-Game <Name/GUID>` | String | Game display name, app name, or installation GUID. |
| `-NewPath <Path>` | String | The target folder path on disk. |
| `-OldDrive <Drive>` | String | Old drive letter (e.g. `D:` or `D`) for bulk updates. |
| `-NewDrive <Drive>` | String | New drive letter (e.g. `E:` or `E`) for bulk updates. |
| `-DryRun` | Switch | Preview changes without modifying any files or registry values. |
| `-Force` | Switch | Bypass interactive prompts (e.g., terminating open launcher processes). |

---

## 📋 How It Works

1. Epic Games Launcher tracks installed games inside `C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests\<GUID>.item`.
2. When a drive letter changes or files are relocated, Epic either fails to detect the game or moves its manifest to `Manifests\Pending\` marked as `bIsIncompleteInstall: true`.
3. **Epic Game Relocator** updates all internal manifest paths (`InstallLocation`, `ManifestLocation`, `CompleteManifestPath`, `PendingManifestPath`, `StagingLocation`) and restores the manifest to active state.
4. For games that use external launchers (e.g. Rockstar Games Launcher), it updates the corresponding `HKLM\SOFTWARE\WOW6432Node\Rockstar Games\...` registry entries.

---

## 📄 License

MIT License. Feel free to use, modify, and distribute.
