# Installs CtACmdr into the game.
#
#   powershell -ExecutionPolicy Bypass -File tools\install.ps1
#   powershell -ExecutionPolicy Bypass -File tools\install.ps1 -GameRoot "D:\Games\Call To Arms - Panzer Elite"
#   powershell -ExecutionPolicy Bypass -File tools\install.ps1 -RestoreViews
#
# -RestoreViews  replace your tuned camera positions with the repo copy.
#                Without it an existing CtACmdr_views.txt is left alone.
#
# Creates the Mods folder and mods.txt when UE4SS did not leave them
# behind, which happens whenever the UE4SS zip is extracted without its
# folders.

param(
    [string]$GameRoot = "L:\SteamLibrary\steamapps\common\Call To Arms - Panzer Elite",
    [switch]$RestoreViews
)

$ErrorActionPreference = "Stop"

$bin = Join-Path $GameRoot "call_to_arms_pe\Binaries\Win64"
$modsDir = Join-Path $bin "Mods"
$source = Join-Path $PSScriptRoot "..\CtACmdr"

Write-Host ""
Write-Host ("Game    : " + $GameRoot)
Write-Host ("Plugins : " + $bin)
Write-Host ""

if (-not (Test-Path -LiteralPath $bin)) {
    throw ("Game not found at: " + $bin + " - check that -GameRoot points at the folder holding call_to_arms_pe.exe")
}

# UE4SS must be present or nothing will load
if (-not (Test-Path -LiteralPath (Join-Path $bin "UE4SS.dll"))) {
    throw ("UE4SS.dll is not in " + $bin + " - copy UE4SS.dll, dwmapi.dll and UE4SS-settings.ini next to the game exe first. See INSTALL.md step 3.")
}
Write-Host "Found UE4SS.dll"

if (-not (Test-Path -LiteralPath $source)) {
    throw ("Mod source not found at: " + $source + " - run this from the cloned repo folder")
}

# create the Mods folder if UE4SS did not
if (-not (Test-Path -LiteralPath $modsDir)) {
    New-Item -ItemType Directory -Path $modsDir -Force | Out-Null
    Write-Host "Created the missing Mods folder"
} else {
    Write-Host "Mods folder already there"
}

Copy-Item -LiteralPath $source -Destination $modsDir -Recurse -Force
Write-Host ("Copied the mod to " + $modsDir + "\CtACmdr")
Write-Host "The mod folder contains enabled.txt, so UE4SS loads it even without a mods.txt line"

# Only place the repo's positions if there are none yet. Overwriting would
# throw away every tank the user tuned in game.
$views = Join-Path $source "CtACmdr_views.txt"
$liveViews = Join-Path $bin "CtACmdr_views.txt"
if (Test-Path -LiteralPath $views) {
    if ((Test-Path -LiteralPath $liveViews) -and (-not $RestoreViews)) {
        Write-Host "Kept your existing camera positions (use -RestoreViews to replace them)"
    } else {
        Copy-Item -LiteralPath $views -Destination $bin -Force
        Write-Host "Installed camera positions from the repo"
    }
}

# create mods.txt if UE4SS did not
$modsTxt = Join-Path $modsDir "mods.txt"
if (-not (Test-Path -LiteralPath $modsTxt)) {
    Set-Content -LiteralPath $modsTxt -Value "CtACmdr : 1" -Encoding ASCII
    Write-Host "Created mods.txt and enabled CtACmdr"
} else {
    $content = Get-Content -LiteralPath $modsTxt -Raw
    if ($content -notmatch "(?m)^\s*CtACmdr\s*:") {
        Add-Content -LiteralPath $modsTxt -Value ""
        Add-Content -LiteralPath $modsTxt -Value "CtACmdr : 1"
        Write-Host "Enabled CtACmdr in mods.txt"
    } else {
        Write-Host "CtACmdr already enabled in mods.txt"
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $modsDir "CtACmdr\Scripts\main.lua"))) {
    throw "Something went wrong - main.lua did not land in the Mods folder"
}

Write-Host ""
Write-Host "Done. Start the game, get in a tank, press F3."
Write-Host "If the keys do nothing, look for the line  Starting Lua mod CtACmdr  in UE4SS.log"
Write-Host ""