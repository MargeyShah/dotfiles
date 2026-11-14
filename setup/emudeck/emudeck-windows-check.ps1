# emudeck-windows-check.ps1
#
# Windows-side helper for cross-device EmuDeck saves.
#
# Windows EmuDeck creates SYMBOLIC LINKS (network-install mode) from each
# emulator's save directory to <Emulation>\saves\<emu> on the NAS. This script:
#   1. prints the Windows <-> NAS path mapping it is using,
#   2. fixes the shared NAS tools\rclone\rclone.conf if the NextCloud URL still
#      has the literal placeholder 'USERNAME' (EmuDeck Setup can rewrite it),
#   3. verifies every emulator save/state link and the config-driven save
#      paths, and
#   4. optionally (-Fix) re-points a mismatched link.
#
# Usage (run from PowerShell, after each EmuDeck Setup/update):
#   powershell -ExecutionPolicy Bypass -File emudeck-windows-check.ps1
#   powershell -ExecutionPolicy Bypass -File emudeck-windows-check.ps1 -CheckOnly
#   powershell -ExecutionPolicy Bypass -File emudeck-windows-check.ps1 -Fix
#
# Important: PowerShell displays a symlink target that lives on a UNC path as
# "UNC\server\share\..." even though the real target is "\\server\share\...".
# This script normalises that before comparing. Never compare raw .Target
# strings against a drive-letter path.
param(
    [string]$EmulationPath = "",
    [string]$UncRoot = "",
    [switch]$CheckOnly,   # skip the rclone.conf URL fix and all repairs
    [switch]$Fix          # re-point a WRONG TARGET link (merges old files)
)

$ErrorActionPreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------
# Launcher/settings fix (unless -CheckOnly). Kept in a child process so its
# exit code cannot terminate this check. It must run before settings.ps1 is
# dot-sourced below, because it patches the temporary-Z:-PSDrive line.
# ---------------------------------------------------------------------------
if (-not $CheckOnly) {
    $fixScript = Join-Path $PSScriptRoot 'emudeck-windows-fix.ps1'
    if (Test-Path -LiteralPath $fixScript) {
        Write-Host "Launcher/settings fix: running $fixScript"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fixScript
        Write-Host ""
    } else {
        Write-Host "Launcher/settings fix not found next to this script (run emudeck-windows-fix.ps1 manually)."
        Write-Host ""
    }
}

# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------
function Normalize-PathString {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    $t = $Path.Trim()
    if ($t -match '^\\\\\?\\UNC\\(.+)$') { $t = '\\' + $Matches[1] }
    elseif ($t -match '^\\\\\?\\(.+)$') { $t = $Matches[1] }
    elseif ($t -match '^UNC\\(.+)$') { $t = '\\' + $Matches[1] }
    return $t.TrimEnd('\')
}

function Resolve-LinkTarget {
    param([string]$LinkPath, $RawTarget)
    $t = (@($RawTarget) -join '')
    if ([string]::IsNullOrWhiteSpace($t)) { return "" }
    $t = $t.Trim()
    if ($t -match '^\\\\\?\\UNC\\(.+)$') { $t = '\\' + $Matches[1] }
    elseif ($t -match '^\\\\\?\\(.+)$') { $t = $Matches[1] }
    elseif ($t -match '^UNC\\(.+)$') { $t = '\\' + $Matches[1] }
    if ($t -notmatch '^[A-Za-z]:\\' -and $t -notmatch '^\\\\') {
        $t = Join-Path (Split-Path -Parent $LinkPath) $t
    }
    return $t.TrimEnd('\')
}

function Resolve-ToSavesForm {
    param([string]$Path)
    $p = Normalize-PathString $Path
    if ($p -match '^[A-Za-z]:') { return $p }
    if ($UncRoot -and $p.StartsWith($UncRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        if ($SavesRoot -match '^([A-Za-z]:)') {
            return $Matches[1] + $p.Substring($UncRoot.Length)
        }
    }
    return $p
}

function Test-PathEqual {
    param([string]$A, [string]$B)
    $a = Normalize-PathString $A
    $b = Normalize-PathString $B
    if ([string]::IsNullOrEmpty($a) -or [string]::IsNullOrEmpty($b)) { return $false }
    return $a.Equals($b, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-LinkResolves {
    param([string]$Path)
    # Trailing \. forces resolution of a directory link; false when dangling.
    return (Test-Path -LiteralPath ($Path.TrimEnd('\') + '\.'))
}

function Get-IsReparsePoint {
    param([string]$Path)
    try {
        $attrs = [int][System.IO.File]::GetAttributes($Path)
        return (($attrs -band [int][System.IO.FileAttributes]::ReparsePoint) -ne 0)
    } catch {
        return $false
    }
}

function Normalize-ConfigPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    $p = $Path.Trim().Trim('"')
    $p = $p -replace '/', '\'
    return Normalize-PathString $p
}

function Convert-ToUnc {
    param([string]$Path)
    $p = Normalize-PathString $Path
    if ($p -match '^\\\\') { return $p }
    if (-not $UncRoot) { return "" }
    $shareDrive = ""
    if ($SavesRoot -match '^([A-Za-z]):') { $shareDrive = $Matches[1] }
    if ($shareDrive -and $p -match ('^' + $shareDrive + ':(.*)$')) {
        return ($UncRoot + $Matches[2]).TrimEnd('\')
    }
    return ""
}

function Get-IniValue {
    param([string]$File, [string]$Key)
    if (-not (Test-Path -LiteralPath $File)) { return $null }
    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*(=|:)'
    $line = Get-Content -LiteralPath $File -ErrorAction SilentlyContinue |
        Select-String -Pattern $pattern |
        Select-Object -First 1
    if (-not $line) { return $null }
    $m = [regex]::Match($line.Line, '^\s*[^=:]+\s*(=|:)\s*(.*)$')
    if (-not $m.Success) { return $null }
    return $m.Groups[2].Value.Trim().Trim('"')
}

function Repair-Link {
    param(
        [string]$Source,
        [string]$Actual,
        [string]$Target
    )
    if (-not (Test-Path -LiteralPath $Target)) {
        Write-Host ("    cannot fix: expected target does not exist: " + $Target)
        return $false
    }

    # If the old target is a real directory inside saves\, merge it so no save
    # is lost when the link is re-pointed.
    $actualNorm = Resolve-ToSavesForm $Actual
    $savesNorm = Normalize-PathString $SavesRoot
    if ($actualNorm -and $savesNorm -and
        $actualNorm.StartsWith($savesNorm, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $actualNorm) -and
        -not (Get-Item -LiteralPath $actualNorm -Force).LinkType) {
        Write-Host ("    merging old target " + $actualNorm + " -> " + $Target)
        Get-ChildItem -LiteralPath $actualNorm -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $rel = $_.FullName.Substring($actualNorm.Length).TrimStart('\')
            $dest = Join-Path $Target $rel
            $destParent = Split-Path -Parent $dest
            if ($destParent) { New-Item -ItemType Directory -Path $destParent -Force | Out-Null }
            $existing = Get-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
            if (-not $existing -or $_.LastWriteTimeUtc -gt $existing.LastWriteTimeUtc) {
                Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
            }
        }
    }

    # Remove the reparse point only; never recurse into its target.
    try {
        [System.IO.Directory]::Delete($Source, $false)
    } catch {
        Write-Host ("    cannot remove link: " + $_.Exception.Message)
        return $false
    }

    try {
        New-Item -ItemType SymbolicLink -Path $Source -Target $Target -ErrorAction Stop | Out-Null
        Write-Host ("    fixed: " + $Source + " -> " + $Target)
        return $true
    } catch {
        $cmd = 'cmd /c mklink /D "' + $Source + '" "' + $Target + '"'
        Write-Host ("    cannot create symlink (run as Administrator): " + $cmd)
        return $false
    }
}

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
$SavesRoot   = if ($savesPath)   { $savesPath.TrimEnd('\') }   else { "$EmulationPath\saves" }
$StorageRoot = if ($storagePath) { $storagePath.TrimEnd('\') } else { "$EmulationPath\storage" }
$emus        = "$env:APPDATA\EmuDeck\Emulators"

# ---------------------------------------------------------------------------
# Print the Windows <-> NAS mapping before doing anything.
# Never infer the UNC form from a drive-letter path silently: show it.
# ---------------------------------------------------------------------------
if (-not $UncRoot) {
    if ($VolName) {
        $UncRoot = $VolName
    } elseif ($EmulationPath -match '^([A-Za-z]):') {
        $drv = Get-PSDrive $Matches[1] -ErrorAction SilentlyContinue
        if ($drv -and $drv.DisplayRoot) { $UncRoot = $drv.DisplayRoot }
    }
}
if ($UncRoot) { $UncRoot = $UncRoot.TrimEnd('\') }

$SavesUnc = ""
if ($SavesRoot -match '^([A-Za-z]):(.*)$' -and $UncRoot) {
    $SavesUnc = ($UncRoot + $Matches[2]).TrimEnd('\')
} elseif ($SavesRoot -match '^\\\\') {
    $SavesUnc = $SavesRoot
}

Write-Host "Emulation : $EmulationPath"
Write-Host "Saves     : $SavesRoot"
Write-Host "Storage   : $StorageRoot"
if ($UncRoot)  { Write-Host "UNC root  : $UncRoot" }
if ($SavesUnc) { Write-Host "UNC saves : $SavesUnc" }
else           { Write-Host "UNC saves : (unknown; pass -UncRoot \\server\share)" }
Write-Host ("NAS reachable: " + (Test-Path -LiteralPath $EmulationPath))

# ---------------------------------------------------------------------------
# 1) rclone.conf NextCloud URL fix (shared NAS file)
# ---------------------------------------------------------------------------
if (-not $CheckOnly) {
    $conf = "$EmulationPath\tools\rclone\rclone.conf"
    if (Test-Path -LiteralPath $conf) {
        $lines = @(Get-Content -LiteralPath $conf)
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
                    $lines[$i] = $line -replace '(/remote\.php/dav/files/)USERNAME(/?)', ('${1}' + $username + '${2}')
                    $fixed = $true
                }
            }
        }
        if ($fixed) {
            Set-Content -LiteralPath $conf -Value $lines
            Write-Host "FIXED rclone.conf URL -> $username"
        } else {
            Write-Host "rclone.conf: NextCloud URL OK (no literal USERNAME) or remote absent"
        }
    } else {
        Write-Host "rclone.conf not found at $conf (cloud sync not configured yet)"
    }
}

# ---------------------------------------------------------------------------
# 2) Link verification map (source -> NAS saves target)
#    Source paths are the ones EmuDeck for Windows creates.
#    Dolphin uses saves\dolphin\states on Windows; Linux uses the same NAS
#    folder but keeps the emulator-side directory named StateSaves.
# ---------------------------------------------------------------------------
$links = @(
    [pscustomobject]@{ Name = "Eden saves";        Source = "$emus\eden-windows-msvc\user\nand\user\save";                                     Target = "$SavesRoot\eden\saves" },
    [pscustomobject]@{ Name = "Eden profiles";     Source = "$emus\eden-windows-msvc\user\nand\system\save\8000000000000010\su\avators";       Target = "$SavesRoot\eden\profiles" },
    [pscustomobject]@{ Name = "Citron saves";      Source = "$emus\citron\user\nand\user\save";                                              Target = "$SavesRoot\citron\saves" },
    [pscustomobject]@{ Name = "Citron profiles";   Source = "$emus\citron\user\nand\system\save\8000000000000010\su\avators";                Target = "$SavesRoot\citron\profiles" },
    [pscustomobject]@{ Name = "Dolphin GC";        Source = "$emus\Dolphin-x64\User\GC";                                                     Target = "$SavesRoot\dolphin\GC" },
    [pscustomobject]@{ Name = "Dolphin Wii";       Source = "$emus\Dolphin-x64\User\Wii";                                                    Target = "$SavesRoot\dolphin\Wii" },
    [pscustomobject]@{ Name = "Dolphin StateSaves";Source = "$emus\Dolphin-x64\User\StateSaves";                                             Target = "$SavesRoot\dolphin\states" },
    [pscustomobject]@{ Name = "Cemu saves";        Source = "$emus\cemu\mlc01\usr\save";                                                     Target = "$SavesRoot\Cemu\saves" },
    [pscustomobject]@{ Name = "RPCS3 savedata";    Source = "$StorageRoot\rpcs3\dev_hdd0\home\00000001\savedata";                             Target = "$SavesRoot\rpcs3\saves"; Type = "Storage" },
    [pscustomobject]@{ Name = "RPCS3 trophy";      Source = "$StorageRoot\rpcs3\dev_hdd0\home\00000001\trophy";                              Target = "$SavesRoot\rpcs3\trophy"; Type = "Storage" },
    [pscustomobject]@{ Name = "PPSSPP saves";      Source = "$emus\PPSSPP\memstick\PSP\SAVEDATA";                                            Target = "$SavesRoot\ppsspp\saves" },
    [pscustomobject]@{ Name = "PPSSPP states";     Source = "$emus\PPSSPP\memstick\PSP\PPSSPP_STATE";                                        Target = "$SavesRoot\ppsspp\states" },
    [pscustomobject]@{ Name = "RetroArch saves";   Source = "$emus\RetroArch\saves";                                                        Target = "$SavesRoot\retroarch\saves" },
    [pscustomobject]@{ Name = "RetroArch states";  Source = "$emus\RetroArch\states";                                                       Target = "$SavesRoot\retroarch\states" },
    [pscustomobject]@{ Name = "PCSX2 saves";       Source = "$emus\PCSX2-Qt\memcards";                                                       Target = "$SavesRoot\pcsx2\saves" },
    [pscustomobject]@{ Name = "PCSX2 states";      Source = "$emus\PCSX2-Qt\sstates";                                                        Target = "$SavesRoot\pcsx2\states" },
    [pscustomobject]@{ Name = "DuckStation saves"; Source = "$emus\duckstation\memcards";                                                    Target = "$SavesRoot\duckstation\saves" },
    [pscustomobject]@{ Name = "DuckStation states";Source = "$emus\duckstation\savestates";                                                  Target = "$SavesRoot\duckstation\states" },
    [pscustomobject]@{ Name = "ShadPS4 savedata";  Source = "$emus\ShadPS4-qt\user\savedata";                                                Target = "$SavesRoot\shadps4\saves" },
    [pscustomobject]@{ Name = "Xenia content";     Source = "$emus\xenia\content";                                                           Target = "$SavesRoot\xenia\saves" },
    [pscustomobject]@{ Name = "Vita3K savedata";   Source = "$StorageRoot\Vita3K\ux0\user\00\savedata";                                      Target = "$SavesRoot\Vita3K\saves"; Type = "Storage" }
)

Write-Host ""
Write-Host "Link check (source -> NAS saves target):"
$ok = 0
$fail = 0
$warn = 0
$fixed = 0

# Windows can create a symlink on local NTFS that points at a UNC target, but
# it cannot create a symlink *on* an SMB share (the server rejects the reparse
# point). Detect that here so RPCS3/Vita3K are reported as a limitation instead
# of "launch the emulator again", which can never work for those two links.
$StorageIsNetwork = $false
if ($StorageRoot -match '^\\\\') {
    $StorageIsNetwork = $true
} elseif ($StorageRoot -match '^([A-Za-z]):') {
    $sd = Get-PSDrive $Matches[1] -ErrorAction SilentlyContinue
    if ($sd -and ($sd.DisplayRoot -or $sd.Root -match '^\\\\')) { $StorageIsNetwork = $true }
}

foreach ($l in $links) {
    $src = $l.Source
    $tgt = $l.Target

    $item = Get-Item -LiteralPath $src -Force -ErrorAction SilentlyContinue
    if (-not $item) {
        if (Get-IsReparsePoint $src) {
            Write-Host ("  {0,-22} DANGLING  (target missing; is the NAS mounted?)" -f $l.Name)
            $fail++
        } else {
            $parent = Split-Path -Parent $src
            if (Test-Path -LiteralPath $parent) {
                if ($l.Type -eq "Storage" -and $StorageIsNetwork) {
                    Write-Host ("  {0,-22} LIMITATION  (Windows cannot create a symlink on the SMB share; saves are still shared via storage)" -f $l.Name)
                } else {
                    Write-Host ("  {0,-22} NOT INITIALIZED  (source absent; launch the emulator once or run EmuDeck -> Reset config)" -f $l.Name)
                }
                $warn++
            } else {
                Write-Host ("  {0,-22} NOT INSTALLED    (emulator folder absent)" -f $l.Name)
            }
        }
        continue
    }

    if (-not $item.LinkType -and -not (Get-IsReparsePoint $src)) {
        if ($l.Type -eq "Storage") {
            # A server-side POSIX symlink may be followed by SMB and appear as
            # a real dir. Data is reachable, but cloud sync only reads saves\.
            Write-Host ("  {0,-22} REAL DIR (server-side link or unlinked data; EmuDeck Cloud Saves will miss it)" -f $l.Name)
            $warn++
        } else {
            Write-Host ("  {0,-22} REAL DIR (not a link) -> emulator is saving locally! Reset config." -f $l.Name)
            $fail++
        }
        continue
    }

    $actual = Resolve-LinkTarget $src $item.Target
    if (-not (Test-LinkResolves $src)) {
        Write-Host ("  {0,-22} DANGLING  (target missing; is the NAS mounted?) -> {1}" -f $l.Name, $actual)
        $fail++
        continue
    }

    $tgtUnc = ""
    if ($SavesUnc -and $tgt.StartsWith($SavesRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $tgtUnc = $SavesUnc + $tgt.Substring($SavesRoot.Length)
    }

    if ((Test-PathEqual $actual $tgt) -or ($tgtUnc -and (Test-PathEqual $actual $tgtUnc))) {
        Write-Host ("  {0,-22} OK" -f $l.Name)
        $ok++
    } else {
        Write-Host ("  {0,-22} WRONG TARGET -> {1} (expected {2})" -f $l.Name, $actual, $tgt)
        if ($Fix -and (Repair-Link -Source $src -Actual $actual -Target $tgt)) {
            $fixed++
        } else {
            $fail++
        }
    }
}

# ---------------------------------------------------------------------------
# 3) Config-driven save paths (no link to verify)
#    mGBA and melonDS write straight to the NAS path from their config.
# ---------------------------------------------------------------------------
$configChecks = @(
    [pscustomobject]@{ Name = "mGBA saves";     File = "$emus\mgba\config.ini";      Key = "savegamePath";   Target = "$SavesRoot\mgba\saves" },
    [pscustomobject]@{ Name = "mGBA states";    File = "$emus\mgba\config.ini";      Key = "savestatePath";  Target = "$SavesRoot\mgba\states" },
    [pscustomobject]@{ Name = "melonDS saves";  File = "$emus\melonDS\melonDS.ini";  Key = "SaveFilePath";   Target = "$SavesRoot\melonds\saves" },
    [pscustomobject]@{ Name = "melonDS states"; File = "$emus\melonDS\melonDS.ini";  Key = "SavestatePath";  Target = "$SavesRoot\melonds\states" }
)

Write-Host ""
Write-Host "Config-driven save paths:"
foreach ($c in $configChecks) {
    if (-not (Test-Path -LiteralPath $c.File)) {
        Write-Host ("  {0,-22} SKIP (config not found)" -f $c.Name)
        continue
    }
    $cur = Get-IniValue $c.File $c.Key
    if (-not $cur) {
        Write-Host ("  {0,-22} MISSING KEY '{1}' in {2}" -f $c.Name, $c.Key, $c.File)
        $warn++
        continue
    }
    $curN = Normalize-ConfigPath $cur
    $tgtN = Normalize-ConfigPath $c.Target
    $tgtUncN = ""
    if ($SavesUnc -and $c.Target.StartsWith($SavesRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $tgtUncN = Normalize-ConfigPath ($SavesUnc + $c.Target.Substring($SavesRoot.Length))
    }
    if ((Test-PathEqual $curN $tgtN) -or ($tgtUncN -and (Test-PathEqual $curN $tgtUncN))) {
        Write-Host ("  {0,-22} OK" -f $c.Name)
        $ok++
    } else {
        Write-Host ("  {0,-22} WRONG PATH -> {1} (expected {2})" -f $c.Name, $cur, $c.Target)
        $fail++
    }
}

Write-Host ""
Write-Host ("Summary: {0} OK, {1} wrong/failed, {2} warning(s), {3} fixed" -f $ok, $fail, $warn, $fixed)
if ($fail -eq 0) {
    if ($warn -eq 0) {
        Write-Host "All checked links and config paths use the NAS saves folder. Cross-device saves ready."
    } else {
        Write-Host "All checked links and config paths are correct. The $warn warning(s) above are limitations or emulators that have not initialized yet."
    }
} else {
    Write-Host "$fail item(s) need attention: in EmuDeck -> Manage Emulators -> Reset config for those emulators, then re-run this script."
}
