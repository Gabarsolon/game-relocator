<#
.SYNOPSIS
    Game Relocator - Easily change install paths or drive letters for PC games.

.DESCRIPTION
    A unified PowerShell tool that updates Epic Games Launcher manifests,
    Ubisoft Connect (Uplay) registry configurations, and Rockstar Games Launcher
    registries when game folders are moved or drive letters change.

.PARAMETER List
    Lists all detected games across all platforms, their installation paths, and disk status.

.PARAMETER Platform
    Filter games by platform: 'All', 'Epic', 'Ubisoft', 'Rockstar'. Defaults to 'All'.

.PARAMETER Game
    The name or ID/GUID of the game to relocate.

.PARAMETER NewPath
    The new installation folder path on disk.

.PARAMETER OldDrive
    For bulk drive migration: specify the old drive letter (e.g. D: or D).

.PARAMETER NewDrive
    For bulk drive migration: specify the new drive letter (e.g. E: or E).

.PARAMETER DryRun
    Simulate the relocation process without modifying any files or registry keys.

.PARAMETER Force
    Suppress confirmation prompts and automatically proceed.

.EXAMPLE
    .\GameRelocator.ps1 -List
    Lists all detected games across Epic, Ubisoft, and Rockstar.

.EXAMPLE
    .\GameRelocator.ps1 -Game "Watch_Dogs" -NewPath "E:\Games\Watch_Dogs"
    Relocates a single game.

.EXAMPLE
    .\GameRelocator.ps1 -OldDrive "D:" -NewDrive "E:"
    Batch updates all games across all launchers from drive D: to drive E:.

.EXAMPLE
    .\GameRelocator.ps1
    Launches the interactive menu.
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
    [ValidateSet('All', 'Epic', 'Ubisoft', 'Rockstar')]
    [string]$Platform = 'All',

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$EpicManifestDir = 'C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests'
$EpicPendingDir  = 'C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests\Pending'
$UbisoftInstalls = 'HKLM:\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs'
$UbisoftBase     = 'HKLM:\SOFTWARE\WOW6432Node\Ubisoft'
$RockstarBase    = 'HKLM:\SOFTWARE\WOW6432Node\Rockstar Games'

function Write-Color([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::White) {
    Write-Host $Text -ForegroundColor $Color
}

function Write-Header {
    Write-Host ''
    Write-Color '============================================================' Cyan
    Write-Color '           Universal Game Installation Relocator          ' Cyan
    Write-Color '     [Epic Games | Ubisoft Connect | Rockstar Games]       ' Cyan
    Write-Color '============================================================' Cyan
    Write-Host ''
}

function Check-LaunchersRunning {
    $procNames = @('EpicGamesLauncher', 'upc', 'Uplay', 'UbisoftGameLauncher', 'RockstarGamesLauncher', 'RockstarService')
    $running = Get-Process -Name $procNames -ErrorAction SilentlyContinue

    if ($running) {
        $uniqueNames = ($running | Select-Object -ExpandProperty ProcessName -Unique) -join ', '
        if ($List -or $DryRun) {
            Write-Color ("[i] Note: Running launcher processes detected: " + $uniqueNames) Gray
            return
        }
        Write-Color ("[!] WARNING: Running launcher processes detected: " + $uniqueNames) Yellow
        Write-Color "    Running launchers can overwrite manifest and registry changes on exit." Yellow
        if (-not $Force) {
            $answer = Read-Host '    Do you want to automatically close these launcher processes? (Y/N)'
            if ($answer -match '^[Yy]') {
                $running | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
                Write-Color '    [+] Launcher processes terminated.' Green
            } else {
                Write-Color '    Continuing anyway. Changes will take effect once launchers are restarted.' Yellow
            }
        }
    }
}

# ----------------- Discovery Functions -----------------

function Get-EpicGames {
    $games = @()
    $searchPaths = @($EpicManifestDir, $EpicPendingDir) | Where-Object { Test-Path $_ }

    foreach ($p in $searchPaths) {
        $files = Get-ChildItem -Path $p -Filter '*.item' -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            try {
                $raw = Get-Content $file.FullName -Raw -Encoding UTF8
                $json = $raw | ConvertFrom-Json
                $exists = $false
                if ($json.InstallLocation -and (Test-Path $json.InstallLocation)) {
                    $exists = $true
                }

                $games += [PSCustomObject]@{
                    Id              = $json.InstallationGuid
                    Platform        = 'Epic Games'
                    DisplayName     = $json.DisplayName
                    InstallLocation = $json.InstallLocation
                    AppName         = $json.AppName
                    PathExists      = $exists
                    IsPending       = ($file.DirectoryName -match 'Pending')
                    ManifestFile    = $file.FullName
                    RawData         = $json
                }
            } catch {
                Write-Color ("[-] Warning: Failed to parse Epic manifest: " + $file.FullName) Yellow
            }
        }
    }
    return $games
}

function Get-UbisoftGames {
    $games = @()
    if (-not (Test-Path $UbisoftInstalls)) { return $games }

    # Map of known game names from HKLM:\SOFTWARE\WOW6432Node\Ubisoft\*
    $nameMap = @{}
    if (Test-Path $UbisoftBase) {
        $subkeys = Get-ChildItem -Path $UbisoftBase -ErrorAction SilentlyContinue
        foreach ($sub in $subkeys) {
            if ($sub.PSChildName -ne 'Launcher') {
                $props = Get-ItemProperty -Path $sub.PSPath -ErrorAction SilentlyContinue
                if ($props.InstallDir) {
                    $norm = $props.InstallDir.TrimEnd('\', '/').ToLower()
                    $nameMap[$norm] = $sub.PSChildName
                }
            }
        }
    }

    $appKeys = Get-ChildItem -Path $UbisoftInstalls -ErrorAction SilentlyContinue
    foreach ($appKey in $appKeys) {
        $props = Get-ItemProperty -Path $appKey.PSPath -ErrorAction SilentlyContinue
        if ($props.InstallDir) {
            $dir = $props.InstallDir
            $norm = $dir.TrimEnd('\', '/').ToLower()
            $cleanPath = $dir.Replace('/', '\').TrimEnd('\')

            $displayName = ""
            if ($nameMap.ContainsKey($norm)) {
                $displayName = $nameMap[$norm]
            } else {
                $displayName = Split-Path $cleanPath -Leaf
                if (-not $displayName) { $displayName = "Ubisoft App " + $appKey.PSChildName }
            }

            $exists = Test-Path $cleanPath

            $games += [PSCustomObject]@{
                Id              = $appKey.PSChildName
                Platform        = 'Ubisoft Connect'
                DisplayName     = $displayName
                InstallLocation = $cleanPath
                AppName         = $appKey.PSChildName
                PathExists      = $exists
                IsPending       = $false
                ManifestFile    = $appKey.PSPath
                RawData         = $props
            }
        }
    }
    return $games
}

function Get-RockstarStandaloneGames {
    $games = @()
    if (-not (Test-Path $RockstarBase)) { return $games }

    $subkeys = Get-ChildItem -Path $RockstarBase -ErrorAction SilentlyContinue
    foreach ($sub in $subkeys) {
        if ($sub.PSChildName -notin @('Launcher', 'Rockstar Games Social Club', 'Steam')) {
            $props = Get-ItemProperty -Path $sub.PSPath -ErrorAction SilentlyContinue
            $loc = if ($props.InstallFolder) { $props.InstallFolder } elseif ($props.InstallFolderEpic) { $props.InstallFolderEpic } else { $null }

            if ($loc) {
                $cleanPath = $loc.TrimEnd('\', '/')
                $games += [PSCustomObject]@{
                    Id              = $sub.PSChildName
                    Platform        = 'Rockstar Games'
                    DisplayName     = $sub.PSChildName
                    InstallLocation = $cleanPath
                    AppName         = $sub.PSChildName
                    PathExists      = (Test-Path $cleanPath)
                    IsPending       = $false
                    ManifestFile    = $sub.PSPath
                    RawData         = $props
                }
            }
        }
    }
    return $games
}

function Get-AllGames {
    $all = @()
    if ($Platform -in @('All', 'Epic')) { $all += Get-EpicGames }
    if ($Platform -in @('All', 'Ubisoft')) { $all += Get-UbisoftGames }
    if ($Platform -in @('All', 'Rockstar')) { $all += Get-RockstarStandaloneGames }
    return $all
}

# ----------------- Relocation Logic -----------------

function Relocate-EpicGame([PSCustomObject]$GameObj, [string]$TargetLocation) {
    $cleanTarget = $TargetLocation.TrimEnd('\', '/')
    $json = $GameObj.RawData
    $guid = $GameObj.Id

    $json.InstallLocation      = $cleanTarget
    $json.ManifestLocation     = "$cleanTarget\.egstore"
    $json.CompleteManifestPath = "$cleanTarget\.egstore\$guid.manifest"
    $json.PendingManifestPath  = "$cleanTarget\.egstore\Pending\$guid.manifest"
    $json.StagingLocation      = "$cleanTarget\.egstore/bps"
    $json.bIsIncompleteInstall = $false
    if ($json.PSObject.Properties['bNeedsValidation']) {
        $json.bNeedsValidation = $false
    }

    $destFile = Join-Path $EpicManifestDir "$guid.item"

    if ($DryRun) {
        Write-Color ("  [DryRun] Would write Epic manifest to: " + $destFile) Cyan
        if ($GameObj.IsPending) {
            Write-Color ("  [DryRun] Would remove pending manifest: " + $GameObj.ManifestFile) Cyan
        }
    } else {
        if (Test-Path $GameObj.ManifestFile) {
            Copy-Item -Path $GameObj.ManifestFile -Destination ($GameObj.ManifestFile + ".bak") -Force -ErrorAction SilentlyContinue
        }

        $newJsonText = $json | ConvertTo-Json -Depth 10
        Set-Content -Path $destFile -Value $newJsonText -Encoding UTF8 -Force
        Write-Color ("  [+] Saved Epic manifest: " + $destFile) Green

        if ($GameObj.IsPending -and (Test-Path $GameObj.ManifestFile)) {
            Remove-Item -Path $GameObj.ManifestFile -Force -ErrorAction SilentlyContinue
            Write-Color ("  [+] Removed pending manifest: " + $GameObj.ManifestFile) Green
        }
    }

    # Also update Rockstar registry if GTA/RDR title
    Update-RockstarRegistry -OldPath $GameObj.InstallLocation -NewPath $cleanTarget
}

function Relocate-UbisoftGame([PSCustomObject]$GameObj, [string]$TargetLocation) {
    $cleanTargetSlash = $TargetLocation.Replace('\', '/').TrimEnd('/') + '/'
    $cleanTargetBack  = $TargetLocation.Replace('/', '\').TrimEnd('\')
    $appId = $GameObj.Id
    $installKey = "$UbisoftInstalls\$appId"

    if ($DryRun) {
        Write-Color ("  [DryRun] Would set '" + $installKey + "\InstallDir' -> '" + $cleanTargetSlash + "'") Cyan
    } else {
        try {
            Set-ItemProperty -Path $installKey -Name "InstallDir" -Value $cleanTargetSlash -ErrorAction Stop
            Write-Color ("  [+] Updated Ubisoft App " + $appId + " InstallDir -> " + $cleanTargetSlash) Green
        } catch {
            Write-Color ("  [-] Failed to update registry (requires admin): " + $_.Exception.Message) Yellow
        }
    }

    # Update corresponding game subkey if exists
    if (Test-Path $UbisoftBase) {
        $subkeys = Get-ChildItem -Path $UbisoftBase -ErrorAction SilentlyContinue
        foreach ($sub in $subkeys) {
            if ($sub.PSChildName -ne 'Launcher') {
                $props = Get-ItemProperty -Path $sub.PSPath -ErrorAction SilentlyContinue
                if ($props.InstallDir) {
                    $normCurrent = $props.InstallDir.Replace('/', '\').TrimEnd('\').ToLower()
                    $normOld     = $GameObj.InstallLocation.ToLower()
                    if ($normCurrent -eq $normOld -or $sub.PSChildName -eq $GameObj.DisplayName) {
                        if ($DryRun) {
                            Write-Color ("  [DryRun] Would set '" + $sub.PSPath + "\InstallDir' -> '" + $cleanTargetBack + "'") Cyan
                        } else {
                            try {
                                Set-ItemProperty -Path $sub.PSPath -Name "InstallDir" -Value $cleanTargetBack -ErrorAction Stop
                                Write-Color ("  [+] Updated Ubisoft Game key '" + $sub.PSChildName + "\InstallDir' -> " + $cleanTargetBack) Green
                            } catch {}
                        }
                    }
                }
            }
        }
    }
}

function Update-RockstarRegistry([string]$OldPath, [string]$NewPath) {
    if (-not (Test-Path $RockstarBase)) { return }

    $subkeys = Get-ChildItem -Path $RockstarBase -ErrorAction SilentlyContinue
    foreach ($sub in $subkeys) {
        $props = Get-ItemProperty -Path $sub.PSPath -ErrorAction SilentlyContinue

        foreach ($propName in @('InstallFolderEpic', 'InstallFolder')) {
            if ($props.$propName) {
                $currVal = $props.$propName
                if ($currVal.TrimEnd('\', '/') -eq $OldPath.TrimEnd('\', '/') -or ($OldDrive -and $currVal -like "$OldDrive*")) {
                    $targetVal = $currVal -replace [regex]::Escape($OldPath), $NewPath
                    if ($OldDrive -and $NewDrive) {
                        $targetVal = $currVal -replace "^$([regex]::Escape($OldDrive))", $NewDrive
                    }
                    if ($DryRun) {
                        Write-Color ("  [DryRun] Would update Rockstar Registry '" + $sub.PSChildName + "\" + $propName + "': '" + $currVal + "' -> '" + $targetVal + "'") Cyan
                    } else {
                        try {
                            Set-ItemProperty -Path $sub.PSPath -Name $propName -Value $targetVal -ErrorAction Stop
                            Write-Color ("  [+] Updated Rockstar Registry '" + $sub.PSChildName + "\" + $propName + "' -> '" + $targetVal + "'") Green
                        } catch {
                            Write-Color ("  [-] Failed to update Rockstar registry (requires admin): " + $_.Exception.Message) Yellow
                        }
                    }
                }
            }
        }
    }
}

function Relocate-Game([PSCustomObject]$GameObj, [string]$TargetLocation) {
    $cleanTarget = $TargetLocation.TrimEnd('\', '/')
    $oldLocation = $GameObj.InstallLocation

    Write-Color ("`n[*] Relocating [" + $GameObj.Platform + "] '" + $GameObj.DisplayName + "'...") Cyan
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

    switch ($GameObj.Platform) {
        'Epic Games'      { Relocate-EpicGame -GameObj $GameObj -TargetLocation $cleanTarget }
        'Ubisoft Connect' { Relocate-UbisoftGame -GameObj $GameObj -TargetLocation $cleanTarget }
        'Rockstar Games'  { Update-RockstarRegistry -OldPath $oldLocation -NewPath $cleanTarget }
    }

    Write-Color ("  [OK] Relocation complete for '" + $GameObj.DisplayName + "'.") Green
}

# ----------------- Execution Handlers -----------------

Write-Header
Check-LaunchersRunning

$allGames = Get-AllGames

if ($List) {
    Write-Color 'Detected Game Installations:' White
    Write-Host ('-' * 90)
    $index = 1
    foreach ($g in $allGames) {
        $statusStr = if ($g.PathExists) { '[FOUND]' } else { '[MISSING ON DISK]' }
        $statusColor = if ($g.PathExists) { 'Green' } else { 'Red' }
        $pendingStr = if ($g.IsPending) { ' (Pending)' } else { '' }

        Write-Host ('{0,2}. ' -f $index) -NoNewline
        Write-Host ('[{0,-15}] ' -f $g.Platform) -ForegroundColor Cyan -NoNewline
        Write-Host ('{0,-35}' -f $g.DisplayName) -ForegroundColor White -NoNewline
        Write-Host (' {0,-18}' -f "$statusStr$pendingStr") -ForegroundColor $statusColor -NoNewline
        Write-Host (' -> {0}' -f $g.InstallLocation) -ForegroundColor Gray
        $index++
    }
    Write-Host ('-' * 90)
    return
}

if ($PSCmdlet.ParameterSetName -eq 'Single') {
    $match = $allGames | Where-Object {
        $_.DisplayName -like "*$Game*" -or $_.Id -eq $Game -or $_.AppName -eq $Game
    }

    if (-not $match) {
        Write-Color ("[-] Error: Could not find any game matching '" + $Game + "'.") Red
        return
    }

    if ($match.Count -gt 1) {
        Write-Color ("[!] Multiple games matched '" + $Game + "'. Please specify exact name, ID, or Platform:") Yellow
        foreach ($m in $match) {
            Write-Color ("    - [" + $m.Platform + "] " + $m.DisplayName + " (" + $m.Id + ")") Gray
        }
        return
    }

    Relocate-Game -GameObj $match[0] -TargetLocation $NewPath
    return
}

if ($PSCmdlet.ParameterSetName -eq 'BulkDrive') {
    $oldNormalized = $OldDrive.TrimEnd('\', '/').ToUpper()
    if (-not $oldNormalized.EndsWith(':')) { $oldNormalized += ':' }

    $newNormalized = $NewDrive.TrimEnd('\', '/').ToUpper()
    if (-not $newNormalized.EndsWith(':')) { $newNormalized += ':' }

    Write-Color ("[*] Bulk replacing drive " + $oldNormalized + " with " + $newNormalized + " across all platforms...") Cyan
    $matches = $allGames | Where-Object { $_.InstallLocation -and $_.InstallLocation.ToUpper().StartsWith($oldNormalized) }

    if ($matches.Count -eq 0) {
        Write-Color ("[-] No games found installed on drive " + $oldNormalized + ".") Yellow
        return
    }

    Write-Color ("Found " + $matches.Count + " game(s) on " + $oldNormalized + ":") White
    foreach ($m in $matches) {
        Write-Color ("  - [" + $m.Platform + "] " + $m.DisplayName + " (" + $m.InstallLocation + ")") Gray
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
        Relocate-Game -GameObj $m -TargetLocation $newLoc
    }
    return
}

# Interactive Menu
if ($PSCmdlet.ParameterSetName -eq 'Interactive') {
    if ($allGames.Count -eq 0) {
        Write-Color '[-] No game installations found on this system.' Yellow
        return
    }

    Write-Color 'Select an option:' White
    Write-Color '  [1] Relocate a single game' Cyan
    Write-Color '  [2] Bulk replace a drive letter across all games (e.g. D: -> E:)' Cyan
    Write-Color '  [3] List all installed games and health check' Cyan
    Write-Color '  [Q] Quit' Gray

    $choice = Read-Host "`nChoice"
    switch ($choice) {
        '1' {
            Write-Host "`nSelect a game to relocate:"
            for ($i = 0; $i -lt $allGames.Count; $i++) {
                $g = $allGames[$i]
                $statusColor = if ($g.PathExists) { 'Green' } else { 'Red' }
                $statusStr = if ($g.PathExists) { 'Ready' } else { 'Missing' }
                Write-Host ('  [{0,2}] ' -f ($i + 1)) -NoNewline
                Write-Host ('[{0,-15}] ' -f $g.Platform) -ForegroundColor Cyan -NoNewline
                Write-Host ('{0,-30} ' -f $g.DisplayName) -NoNewline
                Write-Host ('[{0}] ' -f $statusStr) -ForegroundColor $statusColor -NoNewline
                Write-Host ('(' + $g.InstallLocation + ')') -ForegroundColor Gray
            }

            $sel = Read-Host "`nEnter game number"
            $selIndex = [int]$sel - 1
            if ($selIndex -ge 0 -and $selIndex -lt $allGames.Count) {
                $targetGame = $allGames[$selIndex]
                Write-Color ("`nSelected: [" + $targetGame.Platform + "] " + $targetGame.DisplayName) White
                $targetPath = Read-Host 'Enter new directory path for this game'
                if ([string]::IsNullOrWhiteSpace($targetPath)) {
                    Write-Color '[-] Path cannot be empty.' Red
                    return
                }
                Relocate-Game -GameObj $targetGame -TargetLocation $targetPath
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
