# One-command setup: puts UE4SS in the right place, then installs the mod.
#
#   powershell -ExecutionPolicy Bypass -File tools\setup.ps1
#   powershell -ExecutionPolicy Bypass -File tools\setup.ps1 -GameRoot "D:\Games\Call To Arms - Panzer Elite"
#
# Downloads UE4SS from its official GitHub release, extracts it next to the
# game exe, then runs install.ps1. Needs internet the first time only.
# If UE4SS is already there it is left alone, so this is safe to re-run.

param(
    [string]$GameRoot = "L:\SteamLibrary\steamapps\common\Call To Arms - Panzer Elite",
    [string]$UE4SSRelease = "experimental2",
    [string]$UE4SSAsset = "UE4SS_v3.0.1-1217-g4fb9b615.zip",
    [switch]$QuietDumps,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Windows PowerShell 5.1 can default to old TLS, which GitHub refuses
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

# SHA256 of the asset named above, checked before anything is unpacked.
#
# Why the experimental build and not the v3.0.1 release: the 3.0.1 release
# build FAILS its own signature scan on this game (UE 5.4) with
# "Failed to find FText::FText(FString&&)" and then no Lua mod loads at all.
# The experimental build from November 2026 scans it successfully. Verified
# in game on 07/11/2026, log: "PS scan successful" + "Starting Lua mod".
$UE4SS_SHA256 = "FBDACD0FAE434E23D53B1181F6B085219D7CBF7E2CC8A13A00303F842C38194F"

# Copies files that are missing, recursing into subfolders. Never overwrites
# an existing file, and never copies a folder into an existing folder of the
# same name - which is what made a second run produce ue4ss\Mods\Mods.
function Copy-MissingTree([string]$Source, [string]$Target) {
    New-Item -ItemType Directory -Force -Path $Target | Out-Null
    foreach ($f in (Get-ChildItem -LiteralPath $Source -File -ErrorAction SilentlyContinue)) {
        $t = Join-Path $Target $f.Name
        if (-not (Test-Path -LiteralPath $t)) {
            Copy-Item -LiteralPath $f.FullName -Destination $t -Force
        }
    }
    foreach ($d in (Get-ChildItem -LiteralPath $Source -Directory -ErrorAction SilentlyContinue)) {
        Copy-MissingTree $d.FullName (Join-Path $Target $d.Name)
    }
}

$bin = Join-Path $GameRoot "call_to_arms_pe\Binaries\Win64"
$exe = Join-Path $bin "call_to_arms_pe-Win64-Shipping.exe"

Write-Host ""
Write-Host "Game    : $GameRoot"
Write-Host "Plugins : $bin"
Write-Host ""

if (-not (Test-Path -LiteralPath $exe)) {
    throw ("Game not found. Expected the exe at: " + $exe + " - pass -GameRoot pointing at the folder that holds call_to_arms_pe.exe")
}

# --- is UE4SS already installed? --------------------------------
# an install counts as present in either layout
$haveUE4SS = (Test-Path -LiteralPath (Join-Path $bin "UE4SS.dll")) -or
             (Test-Path -LiteralPath (Join-Path $bin "ue4ss\UE4SS.dll"))
if ($haveUE4SS -and (-not $Force)) {
    Write-Host "UE4SS is already installed, leaving it alone (use -Force to replace it)"
} else {
    $url = "https://github.com/UE4SS-RE/RE-UE4SS/releases/download/" + $UE4SSRelease + "/" + $UE4SSAsset
    $tmp = Join-Path $env:TEMP ("ue4ss_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $zip = Join-Path $tmp "ue4ss.zip"

    Write-Host ("Downloading " + $UE4SSAsset + " from the UE4SS experimental release...")
    try {
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 120
    } catch {
        throw ("Download failed: " + $_.Exception.Message + " - get it by hand from " + $url)
    }
    $sizeMb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
    Write-Host ("Downloaded " + $sizeMb + " MB")

    $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    if ($UE4SS_SHA256 -and ($actual -ne $UE4SS_SHA256)) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        throw ("UE4SS checksum mismatch, refusing to install it." +
               [Environment]::NewLine +
               "  expected " + $UE4SS_SHA256 +
               [Environment]::NewLine +
               "  got      " + $actual +
               [Environment]::NewLine +
               "Download it by hand from " + $url + " and check it yourself.")
    }
    Write-Host "Checksum verified"

    Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force

    # Newer UE4SS builds use a subfolder: dwmapi.dll sits next to the exe and
    # everything else lives under ue4ss. Older builds are flat. Support both.
    $newLayout = Test-Path -LiteralPath (Join-Path $tmp "ue4ss")
    $dwmSrc = Join-Path $tmp "dwmapi.dll"
    if (-not (Test-Path -LiteralPath $dwmSrc)) { throw "The UE4SS zip did not contain dwmapi.dll" }
    Copy-Item -LiteralPath $dwmSrc -Destination $bin -Force

    if ($newLayout) {
        $ue4dst = Join-Path $bin "ue4ss"
        New-Item -ItemType Directory -Force -Path $ue4dst | Out-Null
        foreach ($item in (Get-ChildItem -LiteralPath (Join-Path $tmp "ue4ss"))) {
            $target = Join-Path $ue4dst $item.Name
            if ($item.PSIsContainer) {
                # merge, do not stack folders inside each other
                Copy-MissingTree $item.FullName $target
            } elseif (-not (Test-Path -LiteralPath $target) -or $item.Name -eq "UE4SS.dll") {
                # settings belong to the user, the dll does not
                Copy-Item -LiteralPath $item.FullName -Destination $target -Force
            } else {
                Write-Host ("Kept your existing " + $item.Name)
            }
        }
        Write-Host "Installed UE4SS into the ue4ss folder (new layout)"
    } else {
        $dllSrc = Join-Path $tmp "UE4SS.dll"
        if (-not (Test-Path -LiteralPath $dllSrc)) { throw "The UE4SS zip did not contain UE4SS.dll" }
        Copy-Item -LiteralPath $dllSrc -Destination $bin -Force
        $iniSrc = Join-Path $tmp "UE4SS-settings.ini"
        $iniDst = Join-Path $bin "UE4SS-settings.ini"
        if ((Test-Path -LiteralPath $iniSrc) -and (-not (Test-Path -LiteralPath $iniDst))) {
            Copy-Item -LiteralPath $iniSrc -Destination $iniDst -Force
            Write-Host "Installed a default UE4SS-settings.ini (none existed)"
        } elseif (Test-Path -LiteralPath $iniDst) {
            Write-Host "Kept your existing UE4SS-settings.ini"
        }
        Write-Host "Installed UE4SS next to the game exe (flat layout)"
    }

    $modsSrc = if ($newLayout) { Join-Path $tmp "ue4ss\Mods" } else { Join-Path $tmp "Mods" }
    $modsDst = if ($newLayout) { Join-Path $bin "ue4ss\Mods" } else { Join-Path $bin "Mods" }
    if (Test-Path -LiteralPath $modsSrc) {
        New-Item -ItemType Directory -Force -Path $modsDst | Out-Null
        foreach ($item in (Get-ChildItem -LiteralPath $modsSrc)) {
            $target = Join-Path $modsDst $item.Name
            if (Test-Path -LiteralPath $target) {
                Write-Host ("Kept your existing " + $item.Name)
            } else {
                Copy-Item -LiteralPath $item.FullName -Destination $target -Recurse -Force
            }
        }
    }
    # The official zip does not contain a LICENSE file at its root, so there
    # is nothing to copy. We download from the project rather than
    # redistributing their binary, which keeps MIT attribution moot.

    Write-Host "UE4SS installed next to the game exe"
}

# --- optionally stop the 33MB dumps ---------------------------------
# the ini lives beside UE4SS.dll, which is ue4ss\ in the new layout
$ini = Join-Path $bin "ue4ss\UE4SS-settings.ini"
if (-not (Test-Path -LiteralPath $ini)) { $ini = Join-Path $bin "UE4SS-settings.ini" }

if ($QuietDumps -and (-not (Test-Path -LiteralPath $ini))) {
    Write-Host "Could not find UE4SS-settings.ini, so crash dumping was left unchanged"
} elseif ($QuietDumps) {
    $text = Get-Content -LiteralPath $ini -Raw
    if ($text -match "(?m)^EnableDumping\s*=\s*1") {
        $text = $text -replace "(?m)^EnableDumping\s*=\s*1", "EnableDumping = 0"
        Set-Content -LiteralPath $ini -Value $text -NoNewline
        Write-Host "Turned off UE4SS crash dumping in UE4SS-settings.ini"
    } else {
        Write-Host "Crash dumping was already off"
    }
}

# --- now the mod ----------------------------------------------------
$installer = Join-Path $PSScriptRoot "install.ps1"
if (-not (Test-Path -LiteralPath $installer)) { throw ("install.ps1 not found next to setup.ps1") }
& $installer -GameRoot $GameRoot

Write-Host "All set. Launch the game, get in a tank, press F3."
Write-Host "First launch sits on a black screen for up to a minute. That is normal."
Write-Host ""