# Installs CtACmdr into the game.
#   powershell -ExecutionPolicy Bypass -File tools\install.ps1
# Add -GameRoot "D:\somewhere\Call To Arms - Panzer Elite" if the game moves.

param(
    [string]$GameRoot = "L:\SteamLibrary\steamapps\common\Call To Arms - Panzer Elite"
)

$ErrorActionPreference = "Stop"

$bin = Join-Path $GameRoot "call_to_arms_pe\Binaries\Win64"
$modsDir = Join-Path $bin "Mods"
$source = Join-Path $PSScriptRoot "..\CtACmdr"

if (-not (Test-Path -LiteralPath $bin)) {
    throw "Game not found at: $bin"
}
if (-not (Test-Path -LiteralPath (Join-Path $bin "UE4SS.dll"))) {
    throw "UE4SS is not installed in $bin - this mod needs it"
}
if (-not (Test-Path -LiteralPath $source)) {
    throw "Mod source not found at: $source"
}

# 1. copy the mod
Copy-Item -LiteralPath $source -Destination $modsDir -Recurse -Force
Write-Host "Copied mod to $modsDir\CtACmdr"

# 2. copy any saved camera positions
$views = Join-Path $source "CtACmdr_views.txt"
if (Test-Path -LiteralPath $views) {
    Copy-Item -LiteralPath $views -Destination $bin -Force
    Write-Host "Restored saved camera positions"
}

# 3. make sure it is switched on in mods.txt
$modsTxt = Join-Path $modsDir "mods.txt"
if (-not (Test-Path -LiteralPath $modsTxt)) {
    throw "mods.txt not found in $modsDir"
}
$content = Get-Content -LiteralPath $modsTxt -Raw
if ($content -notmatch "(?m)^\s*CtACmdr\s*:") {
    Add-Content -LiteralPath $modsTxt -Value ""
    Add-Content -LiteralPath $modsTxt -Value "CtACmdr : 1"
    Write-Host "Enabled CtACmdr in mods.txt"
} else {
    Write-Host "CtACmdr already listed in mods.txt"
}

Write-Host ""
Write-Host "Done. Start the game, get in a tank, press F3."
