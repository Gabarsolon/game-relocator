<#
.SYNOPSIS
    Epic Game Relocator - Easily change install paths or drive letters for Epic Games.

.DESCRIPTION
    A PowerShell tool that updates Epic Games Launcher manifest (.item) files and
    associated registry keys (such as Rockstar Games Launcher) when game folders
    are moved or drive letters change, avoiding full game re-downloads.

.PARAMETER List
    Lists all detected Epic Games, their installation paths, and current status.

.PARAMETER Game
    The name or Installation GUID of the game to relocate.

.PARAMETER NewPath
    The new installation folder path on disk.

.PARAMETER OldDrive
    For bulk drive migration: specify the old drive letter (e.g. D: or D).

.PARAMETER NewDrive
    For bulk drive migration: specify the new drive letter (e.g. E: or E).

.PARAMETER DryRun
    Simulate the relocation process without making actual changes to files or registry.

.PARAMETER Force
    Suppress confirmation prompts and automatically proceed.

.EXAMPLE
    .\EpicGameRelocator.ps1 -List
    Lists all games.

.EXAMPLE
    .\EpicGameRelocator.ps1 -Game "Grand Theft Auto V Enhanced" -NewPath "E:\Games\GTAVEnhanced"
    Relocates a single game.

.EXAMPLE
    .\EpicGameRelocator.ps1 -OldDrive "D:" -NewDrive "E:"
    Batch updates all games installed on D: to E:.

.EXAMPLE
    .\EpicGameRelocator.ps1
    Launches interactive menu.
#>

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(ParameterSetName = 'List')]
    [switch]$List,

    [Parameter(ParameterSetName = 'Single', Mandatory = $true)]
    [string]$Game,

    [Parameter(ParameterSetName = 'Single', Mandatory = $true)]
    [string]$NewPath,

    [Parameter(ParameterSetName = 'BulkDrive', Mandatory = $true)]
    [string]$OldDrive,

    [Parameter(ParameterSetName = 'BulkDrive', Mandatory = $true)]
    [string]$NewDrive,

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ManifestDir = 'C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests'
$PendingDir  = 'C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests\Pending'

function Write-Color([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::White) {
    Write-Host $Text -ForegroundColor $Color
}

function Write-Header {
    Write-Host ''
    Write-Color '============================================================' Cyan
    Write-Color '           Epic Games Installation Relocator                ' Cyan
    Write-Color '============================================================' Cyan
    Write-Host ''
}

function Check-LauncherRunning {
    $processes = Get-Process -Name 'EpicGamesLauncher', 'RockstarService', 'RockstarGamesLauncher' -ErrorAction SilentlyContinue
    if ($processes) {
        if ($List -or $DryRun) {
            Write-Color '[i] Note: Epic Games Launcher is currently running.' Gray
            return
        }
        Write-Color '[!] WARNING: Epic Games Launcher is currently running.' Yellow
        Write-Color '    Running launchers may overwrite manifest changes on exit.' Yellow
        if (-not $Force) {
            $answer = Read-Host '    Do you want to automatically close Epic Games Launcher processes? (Y/N)'
            if ($answer -match '^[Yy]') {
                $processes | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
                Write-Color '    [+] Launcher processes terminated.' Green
            } else {
                Write-Color '    Continuing anyway. Manifests will take effect after launcher restart.' Yellow
            }
        }
    }
}

function Get-AllManifests {
    $items = @()
    $searchPaths = @($ManifestDir, $PendingDir) | Where-Object { Test-Path $_ }

    foreach ($path in $searchPaths) {
        $files = Get-ChildItem -Path $path -Filter '*.item' -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            try {
                $raw = Get-Content $file.FullName -Raw -Encoding UTF8
                $json = $raw | ConvertFrom-Json
                $existsOnDisk = $false
                if ($json.InstallLocation -and (Test-Path $json.InstallLocation)) {
                    $existsOnDisk = $true
                }

                $items += [PSCustomObject]@{
                    File                 = $file.FullName
                    FileName             = $file.Name
                    IsPending            = ($file.DirectoryName -match 'Pending')
                    InstallationGuid     = $json.InstallationGuid
                    DisplayName          = $json.DisplayName
                    InstallLocation      = $json.InstallLocation
                    AppName              = $json.AppName
                    MandatoryFolder      = $json.MandatoryAppFolderName
                    bIsIncompleteInstall = $json.bIsIncompleteInstall
                    PathExists           = $existsOnDisk
                    RawJson              = $json
                }
            } catch {
                Write-Color ("[-] Warning: Failed to parse manifest: " + $file.FullName) Yellow
            }
        }
    }
    return $items
}

function Update-RockstarRegistry([string]$GameName, [string]$OldPath, [string]$NewPath) {
    $rglBase = 'HKLM:\SOFTWARE\WOW6432Node\Rockstar Games'
    if (-not (Test-Path $rglBase)) { return }

    $subkeys = Get-ChildItem -Path $rglBase -ErrorAction SilentlyContinue
    foreach ($sub in $subkeys) {
        $props = Get-ItemProperty -Path $sub.PSPath -ErrorAction SilentlyContinue

        foreach ($propName in @('InstallFolderEpic', 'InstallFolder')) {
            if ($props.$propName) {
                $currVal = $props.$propName
                if ($currVal -eq $OldPath -or ($OldDrive -and $currVal -like "$OldDrive*")) {
                    $targetVal = $currVal -replace [regex]::Escape($OldPath), $NewPath
                    if ($OldDrive -and $NewDrive) {
                        $targetVal = $currVal -replace "^$([regex]::Escape($OldDrive))", $NewDrive
                    }
                    if ($DryRun) {
                        Write-Color ("  [DryRun] Would update Rockstar Registry key '" + $sub.PSChildName + "' property '" + $propName + "': '" + $currVal + "' -> '" + $targetVal + "'") Cyan
                    } else {
                        try {
                            Set-ItemProperty -Path $sub.PSPath -Name $propName -Value $targetVal -ErrorAction Stop
                            Write-Color ("  [+] Updated Rockstar Registry '" + $sub.PSChildName + "\" + $propName + "' -> '" + $targetVal + "'") Green
                        } catch {
                            Write-Color ("  [-] Failed to update registry (requires admin): " + $_.Exception.Message) Yellow
                        }
                    }
                }
            }
        }
    }
}

function Relocate-GameManifest([PSCustomObject]$ManifestObj, [string]$TargetLocation) {
    $cleanTarget = $TargetLocation.TrimEnd('\', '/')
    $oldLocation = $ManifestObj.InstallLocation

    Write-Color ("`n[*] Relocating '" + $ManifestObj.DisplayName + "'...") Cyan
    Write-Color ("    From : " + $oldLocation) Gray
    Write-Color ("    To   : " + $cleanTarget) Cyan

    if (-not (Test-Path $cleanTarget) -and -not $DryRun) {
        Write-Color ("[!] Notice: Target directory '" + $cleanTarget + "' does not exist on disk yet.") Yellow
        if (-not $Force) {
            $confirm = Read-Host '    Continue anyway? (Y/N)'
            if ($confirm -notmatch '^[Yy]') {
                Write-Color '    Skipped.' Yellow
                return
            }
        }
    }

    $json = $ManifestObj.RawJson
    $guid = $ManifestObj.InstallationGuid

    $json.InstallLocation      = $cleanTarget
    $json.ManifestLocation     = "$cleanTarget\.egstore"
    $json.CompleteManifestPath = "$cleanTarget\.egstore\$guid.manifest"
    $json.PendingManifestPath  = "$cleanTarget\.egstore\Pending\$guid.manifest"
    $json.StagingLocation      = "$cleanTarget\.egstore/bps"
    $json.bIsIncompleteInstall = $false
    if ($json.PSObject.Properties['bNeedsValidation']) {
        $json.bNeedsValidation = $false
    }

    $destFile = Join-Path $ManifestDir "$guid.item"

    if ($DryRun) {
        Write-Color ("  [DryRun] Would save manifest to: " + $destFile) Cyan
        if ($ManifestObj.IsPending) {
            Write-Color ("  [DryRun] Would remove pending manifest: " + $ManifestObj.File) Cyan
        }
    } else {
        if (Test-Path $ManifestObj.File) {
            Copy-Item -Path $ManifestObj.File -Destination ($ManifestObj.File + ".bak") -Force -ErrorAction SilentlyContinue
        }

        $newJsonText = $json | ConvertTo-Json -Depth 10
        Set-Content -Path $destFile -Value $newJsonText -Encoding UTF8 -Force
        Write-Color ("  [+] Saved active manifest: " + $destFile) Green

        if ($ManifestObj.IsPending -and (Test-Path $ManifestObj.File)) {
            Remove-Item -Path $ManifestObj.File -Force -ErrorAction SilentlyContinue
            Write-Color ("  [+] Removed pending file: " + $ManifestObj.File) Green
        }
    }

    Update-RockstarRegistry -GameName $ManifestObj.DisplayName -OldPath $oldLocation -NewPath $cleanTarget

    Write-Color ("  [OK] Relocation complete for '" + $ManifestObj.DisplayName + "'.") Green
}

# Execution Handlers
Write-Header
Check-LauncherRunning

$allManifests = Get-AllManifests

if ($List) {
    Write-Color 'Detected Epic Games Installations:' White
    Write-Host ('-' * 80)
    $index = 1
    foreach ($m in $allManifests) {
        $statusStr = if ($m.PathExists) { '[FOUND]' } else { '[MISSING ON DISK]' }
        $statusColor = if ($m.PathExists) { 'Green' } else { 'Red' }
        $pendingStr = if ($m.IsPending) { ' (Pending)' } else { '' }

        Write-Host ('{0,2}. ' -f $index) -NoNewline
        Write-Host ('{0,-35}' -f $m.DisplayName) -ForegroundColor White -NoNewline
        Write-Host (' {0,-18}' -f "$statusStr$pendingStr") -ForegroundColor $statusColor -NoNewline
        Write-Host (' -> {0}' -f $m.InstallLocation) -ForegroundColor Gray
        $index++
    }
    Write-Host ('-' * 80)
    return
}

if ($PSCmdlet.ParameterSetName -eq 'Single') {
    $match = $allManifests | Where-Object {
        $_.DisplayName -like "*$Game*" -or $_.InstallationGuid -eq $Game -or $_.AppName -eq $Game
    }

    if (-not $match) {
        Write-Color ("[-] Error: Could not find any Epic Game matching '" + $Game + "'.") Red
        return
    }

    if ($match.Count -gt 1) {
        Write-Color ("[!] Multiple games matched '" + $Game + "'. Please specify exact name or GUID:") Yellow
        foreach ($m in $match) {
            Write-Color ("    - " + $m.DisplayName + " (" + $m.InstallationGuid + ")") Gray
        }
        return
    }

    Relocate-GameManifest -ManifestObj $match[0] -TargetLocation $NewPath
    return
}

if ($PSCmdlet.ParameterSetName -eq 'BulkDrive') {
    $oldNormalized = $OldDrive.TrimEnd('\', '/').ToUpper()
    if (-not $oldNormalized.EndsWith(':')) { $oldNormalized += ':' }

    $newNormalized = $NewDrive.TrimEnd('\', '/').ToUpper()
    if (-not $newNormalized.EndsWith(':')) { $newNormalized += ':' }

    Write-Color ("[*] Bulk replacing drive " + $oldNormalized + " with " + $newNormalized + "...") Cyan
    $matches = $allManifests | Where-Object { $_.InstallLocation -and $_.InstallLocation.ToUpper().StartsWith($oldNormalized) }

    if ($matches.Count -eq 0) {
        Write-Color ("[-] No games found installed on drive " + $oldNormalized + ".") Yellow
        return
    }

    Write-Color ("Found " + $matches.Count + " game(s) on " + $oldNormalized + ":") White
    foreach ($m in $matches) {
        Write-Color ("  - " + $m.DisplayName + " (" + $m.InstallLocation + ")") Gray
    }

    if (-not $Force -and -not $DryRun) {
        $ans = Read-Host "`nProceed with updating all these games? (Y/N)"
        if ($ans -notmatch '^[Yy]') {
            Write-Color 'Aborted by user.' Yellow
            return
        }
    }

    foreach ($m in $matches) {
        $newLoc = $m.InstallLocation -replace "^$([regex]::Escape($oldNormalized))", $newNormalized
        Relocate-GameManifest -ManifestObj $m -TargetLocation $newLoc
    }
    return
}

# Interactive Menu
if ($PSCmdlet.ParameterSetName -eq 'Interactive') {
    if ($allManifests.Count -eq 0) {
        Write-Color '[-] No Epic Games manifests found on this system.' Yellow
        return
    }

    Write-Color 'Select an option:' White
    Write-Color '  [1] Relocate a single game' Cyan
    Write-Color '  [2] Bulk replace a drive letter across all games (e.g. D: -> E:)' Cyan
    Write-Color '  [3] List all installed games and statuses' Cyan
    Write-Color '  [Q] Quit' Gray

    $choice = Read-Host "`nChoice"
    switch ($choice) {
        '1' {
            Write-Host "`nSelect a game to relocate:"
            for ($i = 0; $i -lt $allManifests.Count; $i++) {
                $m = $allManifests[$i]
                $statusColor = if ($m.PathExists) { 'Green' } else { 'Red' }
                $statusStr = if ($m.PathExists) { 'Ready' } else { 'Missing' }
                Write-Host ('  [{0,2}] ' -f ($i + 1)) -NoNewline
                Write-Host ('{0,-35} ' -f $m.DisplayName) -NoNewline
                Write-Host ('[{0}] ' -f $statusStr) -ForegroundColor $statusColor -NoNewline
                Write-Host ('(' + $m.InstallLocation + ')') -ForegroundColor Gray
            }

            $sel = Read-Host "`nEnter game number"
            $selIndex = [int]$sel - 1
            if ($selIndex -ge 0 -and $selIndex -lt $allManifests.Count) {
                $targetGame = $allManifests[$selIndex]
                Write-Color ("`nSelected: " + $targetGame.DisplayName) White
                $targetPath = Read-Host 'Enter new directory path for this game'
                if ([string]::IsNullOrWhiteSpace($targetPath)) {
                    Write-Color '[-] Path cannot be empty.' Red
                    return
                }
                Relocate-GameManifest -ManifestObj $targetGame -TargetLocation $targetPath
            } else {
                Write-Color '[-] Invalid selection.' Red
            }
        }
        '2' {
            $from = Read-Host "`nEnter old drive letter (e.g. D:)"
            $to   = Read-Host 'Enter new drive letter (e.g. E:)'
            if (-not $from -or -not $to) {
                Write-Color '[-] Both drive letters are required.' Red
                return
            }
            & $PSCommandPath -OldDrive $from -NewDrive $to
        }
        '3' {
            & $PSCommandPath -List
        }
        Default {
            Write-Color 'Goodbye!' Gray
        }
    }
}
