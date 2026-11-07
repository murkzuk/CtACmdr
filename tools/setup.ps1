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
    [string]$UE4SSVersion = "3.0.1",
    [switch]$QuietDumps,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Windows PowerShell 5.1 can default to old TLS, which GitHub refuses
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

# SHA256 of UE4SS_v3.0.1.zip as published on the official release. The zip
# contains a DLL that loads into the game, so it is worth not trusting the
# network blindly.
$UE4SS_SHA256 = "4B47D4BCEDDD2F561A4E395BFA00924CCFC945AF576A2D0C613E6537846C57EC"

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
$haveUE4SS = Test-Path -LiteralPath (Join-Path $bin "UE4SS.dll")
if ($haveUE4SS -and (-not $Force)) {
    Write-Host "UE4SS is already installed, leaving it alone (use -Force to replace it)"
} else {
    $url = "https://github.com/UE4SS-RE/RE-UE4SS/releases/download/v" + $UE4SSVersion + "/UE4SS_v" + $UE4SSVersion + ".zip"
    $tmp = Join-Path $env:TEMP ("ue4ss_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $zip = Join-Path $tmp "ue4ss.zip"

    Write-Host ("Downloading UE4SS v" + $UE4SSVersion + " from the official release...")
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

    foreach ($f in @("UE4SS.dll", "dwmapi.dll")) {
        $src = Join-Path $tmp $f
        if (-not (Test-Path -LiteralPath $src)) { throw ("The UE4SS zip did not contain " + $f) }
        Copy-Item -LiteralPath $src -Destination $bin -Force
    }

    # Settings and existing mods belong to the user. Only add what is missing,
    # never overwrite: -Force is meant to replace the DLLs, not reset their setup.
    $iniSrc = Join-Path $tmp "UE4SS-settings.ini"
    $iniDst = Join-Path $bin "UE4SS-settings.ini"
    if ((Test-Path -LiteralPath $iniSrc) -and (-not (Test-Path -LiteralPath $iniDst))) {
        Copy-Item -LiteralPath $iniSrc -Destination $iniDst -Force
        Write-Host "Installed a default UE4SS-settings.ini (none existed)"
    } elseif (Test-Path -LiteralPath $iniDst) {
        Write-Host "Kept your existing UE4SS-settings.ini"
    }

    $modsSrc = Join-Path $tmp "Mods"
    $modsDst = Join-Path $bin "Mods"
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
$ini = Join-Path $bin "UE4SS-settings.ini"
if ($QuietDumps -and (Test-Path -LiteralPath $ini)) {
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