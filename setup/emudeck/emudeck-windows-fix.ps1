# emudeck-windows-fix.ps1
#
# Fix the Windows-side EmuDeck launcher errors that are visible for a moment
# when an emulator starts.
#
# Tested against EmuDeck for Windows 2.7.1.0 (installer announcement
# v2.7.2-unstable.138, backend commit c4350af). The patch is pattern-based, so a
# newer EmuDeck that changes settings.ps1 is reported rather than broken.
#
# Two upstream EmuDeck problems are repaired here, without touching the
# EmuDeck backend (which is git-reset on every launch):
#
#   1. settings.ps1 always runs
#          $testdrive = New-PSDrive -Name "Z" ... -Root "\\server\share"
#      even when Z: is already a persistent SMB mapping. That creates a
#      temporary PSDrive in the current scope that shadows the real mapping.
#      PowerShell 5.1 then resolves paths such as
#          Z:\Emulation\saves
#      to a duplicated path like
#          \\server\share\server\share\...\Emulation\saves
#      so cloud-sync writes to .watching/.emulator fail with
#      "Could not find a part of the path".
#      This script rewrites that one line to reuse an existing Z: drive:
#          if (Get-PSDrive -Name "Z" ...) { $testdrive = Get-PSDrive -Name "Z" }
#          else { $testdrive = New-PSDrive ... }
#
#   2. EmuDeck's isLatestVersionGH writes to an undefined variable
#      ($rutaArchivo) when %APPDATA%\emudeck\emu_versions.json is missing, then
#      fails to read the file. Creating the file with "{}" skips that branch.
#
# What is NOT fixed here:
#   - "git : From https://..." is normal git output on stderr; PowerShell shows
#     it as a NativeCommandError. It is harmless.
#   - hideMe's "Cannot convert null to IntPtr" can appear when PowerShell has
#     no interactive window handle (e.g. Windows Terminal or a redirected
#     session). It is harmless and does not affect the launch.
#
# Usage (run after every EmuDeck Setup/update, or whenever settings change):
#   powershell -ExecutionPolicy Bypass -File emudeck-windows-fix.ps1
#   powershell -ExecutionPolicy Bypass -File emudeck-windows-fix.ps1 -CheckOnly
#
# Persistence across EmuDeck updates/Setup (recommended):
#   powershell -ExecutionPolicy Bypass -File emudeck-windows-fix.ps1 -Install
# This copies the fix to %APPDATA%\EmuDeck\crossdevice\ and adds a small block
# to the CurrentUserAllHosts PowerShell profile. Every EmuDeck launcher is a
# powershell.exe process, so the profile re-applies the settings.ps1 patch
# before the launcher runs - even after EmuDeck regenerates settings.ps1.
# Remove it again with -Uninstall.
param(
    [switch]$CheckOnly,
    [switch]$Install,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$markerStart = '# >>> emudeck-crossdevice-fix >>>'
$markerEnd   = '# <<< emudeck-crossdevice-fix <<<'
$stableDir   = "$env:APPDATA\EmuDeck\crossdevice"
$stableFix   = "$stableDir\emudeck-windows-fix.ps1"
$profileFile = $PROFILE.CurrentUserAllHosts

function Set-ProfileBlock {
    param([string]$Path, [bool]$Remove)
    $nl = "`r`n"
    $block = @(
        $markerStart,
        'if ($env:APPDATA) {',
        '    $__edSettings = Join-Path $env:APPDATA "EmuDeck\settings.ps1"',
        '    $__edFix = Join-Path $env:APPDATA "EmuDeck\crossdevice\emudeck-windows-fix.ps1"',
        '    if (Test-Path -LiteralPath $__edFix) {',
        '        $__edNeedFix = -not (Test-Path -LiteralPath (Join-Path $env:APPDATA "emudeck\emu_versions.json"))',
        '        if (Test-Path -LiteralPath $__edSettings) {',
        '            $__edText = [System.IO.File]::ReadAllText($__edSettings)',
        '            if ($__edText -notmatch "Get-PSDrive -Name") { $__edNeedFix = $true }',
        '        }',
        '        if ($__edNeedFix) { & $__edFix *> $null }',
        '    }',
        '}',
        $markerEnd
    ) -join $nl

    $text = ""
    if (Test-Path -LiteralPath $Path) {
        $text = [System.IO.File]::ReadAllText($Path)
    }
    $pattern = '(?s)' + [regex]::Escape($markerStart) + '.*?' + [regex]::Escape($markerEnd)
    $hasBlock = [regex]::IsMatch($text, $pattern)

    if ($Remove) {
        if (-not $hasBlock) { return $false }
        $newText = [regex]::Replace($text, $pattern, '').TrimEnd() + $nl
    } else {
        if ($hasBlock) {
            # Remove every existing block, then append one clean block. This
            # also avoids .NET Regex.Replace treating $env:APPDATA etc. in the
            # replacement as substitution tokens.
            $text = [regex]::Replace($text, $pattern, '').TrimEnd()
            if ($text) { $text += $nl + $nl }
            $newText = $text + $block + $nl
        } else {
            if ($text -and -not $text.EndsWith($nl)) { $text += $nl }
            $newText = $text + $block + $nl
        }
    }

    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $newText, (New-Object System.Text.UTF8Encoding($true)))
    return $true
}

if ($Uninstall) {
    $removed = Set-ProfileBlock -Path $profileFile -Remove $true
    if (Test-Path -LiteralPath $stableFix) {
        Remove-Item -LiteralPath $stableFix -Force
    }
    Write-Host "Uninstalled profile hook: $profileFile"
    Write-Host "Removed stable copy    : $stableFix"
    if (-not $removed) { Write-Host "Profile hook was not present." }
    exit 0
}

if ($Install) {
    New-Item -ItemType Directory -Path $stableDir -Force | Out-Null
    Copy-Item -LiteralPath $PSCommandPath -Destination $stableFix -Force
    Set-ProfileBlock -Path $profileFile -Remove $false | Out-Null
    Write-Host "Installed stable copy : $stableFix"
    Write-Host "Installed profile hook: $profileFile"
    Write-Host "Every PowerShell launch (including EmuDeck launchers) will re-apply the fix."
    Write-Host ""
}

$settings = "$env:APPDATA\EmuDeck\settings.ps1"
if (-not (Test-Path -LiteralPath $settings)) {
    Write-Host "ERROR: EmuDeck settings not found at $settings" -ForegroundColor Red
    Write-Host "       Run EmuDeck Setup once first."
    exit 1
}

$text = [System.IO.File]::ReadAllText($settings)
$bytes = [System.IO.File]::ReadAllBytes($settings)
$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
$nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }

$volMatch = [regex]::Match($text, '(?m)^\s*\$VolName\s*=\s*"([^"]+)"')
if (-not $volMatch.Success) {
    Write-Host "ERROR: could not find `$VolName in $settings" -ForegroundColor Red
    exit 1
}
$volName = $volMatch.Groups[1].Value.TrimEnd('\')

$driveMatch = [regex]::Match($text, '(?m)^\s*\$testdrive\s*=\s*New-PSDrive\s+-Name\s+"?([A-Za-z])"?\s+-PSProvider\s+FileSystem\s+-Root\s+"?\$VolName"?\s*$')
$alreadyPatched = ($text -match '(?m)^\s*\$testdrive\s*=\s*Get-PSDrive\s+-Name')
if (-not $driveMatch.Success -and -not $alreadyPatched) {
    Write-Host "ERROR: could not find the `$testdrive=New-PSDrive line in $settings" -ForegroundColor Red
    exit 1
}
$drive = if ($driveMatch.Success) { $driveMatch.Groups[1].Value } else { "" }

Write-Host "Settings : $settings"
Write-Host "Volume   : $volName"

# ---------------------------------------------------------------------------
# Ensure the drive is a real persistent SMB mapping, not just a temp PSDrive.
# ---------------------------------------------------------------------------
if ($drive) {
    $localPath = "$drive`:"
    $mapping = Get-SmbMapping -LocalPath $localPath -ErrorAction SilentlyContinue
    if ($mapping) {
        Write-Host ("Mapping  : {0} -> {1}" -f $localPath, $mapping.RemotePath)
        if ($mapping.RemotePath.TrimEnd('\') -ne $volName) {
            Write-Host ("WARN: {0} points at {1}, expected {2}" -f $localPath, $mapping.RemotePath, $volName) -ForegroundColor Yellow
        }
    } elseif ($CheckOnly) {
        Write-Host ("Mapping  : {0} is NOT a persistent SMB mapping (would create it)" -f $localPath) -ForegroundColor Yellow
    } else {
        Write-Host ("Mapping  : creating persistent {0} -> {1}" -f $localPath, $volName)
        try {
            New-SmbMapping -LocalPath $localPath -RemotePath $volName -Persistent $true -ErrorAction Stop | Out-Null
            Write-Host "Mapping  : created"
        } catch {
            Write-Host ("WARN: could not create {0}: {1}" -f $localPath, $_.Exception.Message) -ForegroundColor Yellow
            Write-Host ("      Map it once manually: net use {0} {1} /persistent:yes" -f $localPath, $volName) -ForegroundColor Yellow
        }
    }
}

# ---------------------------------------------------------------------------
# 1) settings.ps1: reuse the existing drive instead of creating a shadow PSDrive
# ---------------------------------------------------------------------------
if ($alreadyPatched) {
    Write-Host "settings.ps1: already patched (reuses the existing drive)"
} elseif ($CheckOnly) {
    Write-Host "settings.ps1: WOULD PATCH the New-PSDrive line to reuse the existing drive"
} else {
    $backup = "$settings.crossdevice.bak"
    if (-not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $settings -Destination $backup -Force
        Write-Host "settings.ps1: backup -> $backup"
    }

    $replacement = @(
        ("if (Get-PSDrive -Name `"$drive`" -ErrorAction SilentlyContinue) {"),
        ("    `$testdrive = Get-PSDrive -Name `"$drive`""),
        ("} else {"),
        ("    `$testdrive = New-PSDrive -Name `"$drive`" -PSProvider FileSystem -Root `"`$VolName`""),
        ("}")
    ) -join $nl

    $newText = $text.Substring(0, $driveMatch.Index) + $replacement + $text.Substring($driveMatch.Index + $driveMatch.Length)
    $enc = New-Object System.Text.UTF8Encoding($hasBom)
    [System.IO.File]::WriteAllText($settings, $newText, $enc)
    Write-Host "settings.ps1: patched to reuse the existing drive"
}

# ---------------------------------------------------------------------------
# 2) emu_versions.json: avoid the undefined-variable path in isLatestVersionGH
# ---------------------------------------------------------------------------
$emuVersions = "$env:APPDATA\emudeck\emu_versions.json"
$emuVersionsDir = Split-Path -Parent $emuVersions
$needFile = (-not (Test-Path -LiteralPath $emuVersions)) -or ((Get-Item -LiteralPath $emuVersions).Length -eq 0)
if (-not $needFile) {
    Write-Host "emu_versions.json: present"
} elseif ($CheckOnly) {
    Write-Host "emu_versions.json: MISSING (would create '{}')"
} else {
    New-Item -ItemType Directory -Path $emuVersionsDir -Force | Out-Null
    [System.IO.File]::WriteAllText($emuVersions, "{}", (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "emu_versions.json: created with {}"
}

Write-Host ""
if ($CheckOnly) {
    Write-Host "Check complete. Re-run without -CheckOnly to apply."
} else {
    $profileHasHook = $false
    if (Test-Path -LiteralPath $profileFile) {
        $profileHasHook = [regex]::IsMatch(
            [System.IO.File]::ReadAllText($profileFile),
            [regex]::Escape($markerStart))
    }
    if ($profileHasHook) {
        Write-Host "Done. The PowerShell profile hook will re-apply this after EmuDeck regenerates settings.ps1."
    } else {
        Write-Host "Done. Re-run this script after every EmuDeck Setup/update or settings change,"
        Write-Host "because EmuDeck regenerates settings.ps1. Use -Install to add the persistent hook."
    }
}
