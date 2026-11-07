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
    $tmp = Join-Path $env:TEMP ("ue4ss_" + $UE4SSVersion)
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
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

    Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force

    foreach ($f in @("UE4SS.dll", "dwmapi.dll", "UE4SS-settings.ini")) {
        $src = Join-Path $tmp $f
        if (-not (Test-Path -LiteralPath $src)) { throw ("The UE4SS zip did not contain " + $f) }
        Copy-Item -LiteralPath $src -Destination $bin -Force
    }
    $modsSrc = Join-Path $tmp "Mods"
    if (Test-Path -LiteralPath $modsSrc) {
        Copy-Item -Path (Join-Path $modsSrc "*") -Destination (Join-Path $bin "Mods") -Recurse -Force -ErrorAction SilentlyContinue
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