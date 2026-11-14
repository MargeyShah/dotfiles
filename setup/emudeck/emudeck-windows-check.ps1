# emudeck-windows-check.ps1
#
# Minimal Windows-side helper for cross-device EmuDeck saves.
#
# Windows EmuDeck's OWN Setup already creates every save junction pointing at
# <Emulation>\saves\<emu> on the NAS - no emulator config changes are needed on
# this side. This script only:
#   1. fixes the shared NAS tools\rclone\rclone.conf if the NextCloud URL still
#      has the literal placeholder 'USERNAME' (EmuDeck Setup can rewrite it),
#   2. verifies every emulator save junction points at saves\<emu> on the NAS
#      (not a local dir), and
#   3. reports what to Reset in EmuDeck if anything is missing.
#
# Usage (run from PowerShell, after each EmuDeck Setup/update):
#   powershell -ExecutionPolicy Bypass -File emudeck-windows-check.ps1
#   powershell -ExecutionPolicy Bypass -File emudeck-windows-check.ps1 -CheckOnly
#
# No junctions are created or removed here; if something is missing, the
# correct action is EmuDeck -> Manage Emulators -> Reset config for that
# emulator (that re-creates the junction with EmuDeck's own paths).
param(
    [string]$EmulationPath = "",
    [switch]$CheckOnly       # skip the rclone.conf URL fix
)

$ErrorActionPreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Resolve the Emulation root (same sources EmuDeck uses)
# ---------------------------------------------------------------------------
if (-not $EmulationPath) {
    $settings = "$env:APPDATA\EmuDeck\settings.ps1"
    if (-not (Test-Path -LiteralPath $settings)) {
        $settings = "$env:USERPROFILE\EmuDeck\settings.ps1"
    }
    if (Test-Path -LiteralPath $settings) { . $settings }
    $EmulationPath = $emulationPath
}
if (-not $EmulationPath) {
    Write-Host "ERROR: cannot find the Emulation root (run EmuDeck once, or pass -EmulationPath Z:\Emulation)"
    exit 1
}
$EmulationPath = $EmulationPath.TrimEnd('\')
$saves   = if ($savesPath)   { $savesPath.TrimEnd('\') }   else { "$EmulationPath\saves" }
$storage = if ($storagePath) { $storagePath.TrimEnd('\') } else { "$EmulationPath\storage" }
$emus    = "$env:APPDATA\EmuDeck\Emulators"

Write-Host "Emulation : $EmulationPath"
Write-Host "Saves     : $saves"
Write-Host ("NAS mounted: " + (Test-Path -LiteralPath $EmulationPath))

# ---------------------------------------------------------------------------
# 1) rclone.conf NextCloud URL fix (shared NAS file)
# ---------------------------------------------------------------------------
if (-not $CheckOnly) {
    $conf = "$EmulationPath\tools\rclone\rclone.conf"
    if (Test-Path -LiteralPath $conf) {
        $lines = Get-Content -LiteralPath $conf
        $inSection = $false
        $username = ""
        $fixed = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($line -match '^\[(Emudeck-NextCloud|Emudeck-WebDAV)\]') { $inSection = $true; continue }
            if ($inSection -and $line -match '^\[') { $inSection = $false }
            if ($inSection -and $line -match '^\s*user\s*=\s*(\S+)') { $username = $Matches[1] }
            if ($inSection -and $line -match 'url\s*=\s*https?://[^/]+/remote\.php/dav/files/USERNAME/?\s*$') {
                if ($username) {
                    # keep the real host; only replace the literal USERNAME segment
                    $lines[$i] = $line -replace '(/remote\.php/dav/files/)USERNAME(/?)', ('${1}' + $username + '${2}')
                    $fixed = $true
                }
            }
        }
        if ($fixed) { Set-Content -LiteralPath $conf $lines; Write-Host "FIXED rclone.conf URL -> $username" }
        else { Write-Host "rclone.conf: NextCloud URL OK (no literal USERNAME) or remote absent" }
    } else { Write-Host "rclone.conf not found at $conf (cloud sync not configured yet)" }
}

# ---------------------------------------------------------------------------
# 2) Junction verification map (source -> NAS saves target)
#    Source paths are the ones EmuDeck for Windows creates.
# ---------------------------------------------------------------------------
$links = @(
    @{ Name = "Eden saves";        Source = "$emus\eden-windows-msvc\user\nand\user\save";                                        Target = "$saves\eden\saves" },
    @{ Name = "Eden profiles";     Source = "$emus\eden-windows-msvc\user\nand\system\save\8000000000000010\su\avators";          Target = "$saves\eden\profiles" },
    @{ Name = "Citron saves";      Source = "$emus\citron-windows-msvc\user\nand\user\save";                                     Target = "$saves\citron\saves" },
    @{ Name = "Dolphin GC";        Source = "$emus\Dolphin-x64\User\GC";                                                         Target = "$saves\dolphin\GC" },
    @{ Name = "Dolphin Wii";       Source = "$emus\Dolphin-x64\User\Wii";                                                        Target = "$saves\dolphin\Wii" },
    @{ Name = "Dolphin StateSaves";Source = "$emus\Dolphin-x64\User\StateSaves";                                                 Target = "$saves\dolphin\StateSaves" },
    @{ Name = "Cemu saves";        Source = "$emus\cemu\mlc01\usr\save";                                                         Target = "$saves\Cemu\saves" },
    @{ Name = "RPCS3 savedata";    Source = "$storage\rpcs3\dev_hdd0\home\00000001\savedata";                                     Target = "$saves\rpcs3\saves" },
    @{ Name = "RPCS3 trophy";      Source = "$storage\rpcs3\dev_hdd0\home\00000001\trophy";                                      Target = "$saves\rpcs3\trophy" },
    @{ Name = "PPSSPP saves";      Source = "$emus\PPSSPP\memstick\PSP\SAVEDATA";                                                Target = "$saves\ppsspp\saves" },
    @{ Name = "PPSSPP states";     Source = "$emus\PPSSPP\memstick\PSP\PPSSPP_STATE";                                            Target = "$saves\ppsspp\states" },
    @{ Name = "RetroArch saves";   Source = "$emus\RetroArch\saves";                                                            Target = "$saves\retroarch\saves" },
    @{ Name = "PCSX2 saves";       Source = "$emus\pcsx2\memcards";                                                             Target = "$saves\pcsx2\saves" },
    @{ Name = "DuckStation saves"; Source = "$emus\duckstation\memcards";                                                        Target = "$saves\duckstation\saves" },
    @{ Name = "Vita3K savedata";   Source = "$storage\Vita3K\ux0\user\00\savedata";                                               Target = "$saves\Vita3K\saves" }
)

Write-Host ""
Write-Host "Junction check (source -> saves\<emu>):"
$fail = 0
foreach ($l in $links) {
    $src = $l.Source
    $tgt = $l.Target
    $item = Get-Item -LiteralPath $src -ErrorAction SilentlyContinue
    if (-not $item) {
        $parent = Split-Path -Parent $src
        if (Test-Path -LiteralPath $parent) {
            Write-Host ("  {0,-20} MISSING  (source absent; run EmuDeck -> Reset config for this emulator)" -f $l.Name)
            $fail++
        } else {
            Write-Host ("  {0,-20} skip     (emulator not installed on this PC)" -f $l.Name)
        }
        continue
    }
    if ($item.LinkType) {
        $actual = (@($item.Target) -join '').TrimEnd('\').ToLowerInvariant()
        $want   = $tgt.TrimEnd('\').ToLowerInvariant()
        if ($actual -eq $want) {
            Write-Host ("  {0,-20} OK" -f $l.Name)
        } else {
            Write-Host ("  {0,-20} BROKEN   (points to: $actual)" -f $l.Name)
            $fail++
        }
    } else {
        Write-Host ("  {0,-20} REAL DIR (not a junction) -> emulator is saving locally! Reset config." -f $l.Name)
        $fail++
    }
}

Write-Host ""
if ($fail -eq 0) { Write-Host "All checked junctions point at the NAS saves folder. Cross-device saves ready." }
else { Write-Host "$fail item(s) need attention: in EmuDeck -> Manage Emulators -> Reset config for those emulators, then re-run this script." }
