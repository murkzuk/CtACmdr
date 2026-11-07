# Builds the two zips that end users download from the GitHub Release.
#
#   powershell -ExecutionPolicy Bypass -File tools\build-release.ps1 -Version 1.10.0
#
# Output (in .\release):
#   CtACmdr-v<Version>-Windows.zip    UE4SS + the mod. Extract into Win64. For people with no UE4SS.
#   CtACmdr-v<Version>-mod-only.zip   Just the mod folder. For people who already run UE4SS.
#   SHA256SUMS.txt                    paste this into the release notes
#
# The UE4SS build, its download address and its SHA256 are read from
# tools\setup.ps1, so there is one place to change them. The download is
# refused unless the checksum matches.
#
#   -UE4SSZip  use a UE4SS zip you already downloaded instead of fetching it
#              (it is still checked against the pinned SHA256)
#
# Nothing from the user's own game folder goes into the zips: no saved
# camera positions, no logs, no dumps.

param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$UE4SSZip = "",
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($OutDir -eq "") { $OutDir = Join-Path $here "..\release" }
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version must look like 1.10.0" }

$repo = (Resolve-Path (Join-Path $here "..")).Path

# --- read the pinned UE4SS build out of setup.ps1 ------------------------
$setupText = Get-Content -LiteralPath (Join-Path $here "setup.ps1") -Raw
function Get-Pin([string]$pattern, [string]$label) {
    $m = [regex]::Match($setupText, $pattern)
    if (-not $m.Success) { throw ("Could not find " + $label + " in tools\setup.ps1 - was it renamed?") }
    return $m.Groups[1].Value
}
$release = Get-Pin '\[string\]\$UE4SSRelease\s*=\s*"([^"]+)"' "UE4SSRelease"
$asset   = Get-Pin '\[string\]\$UE4SSAsset\s*=\s*"([^"]+)"' "UE4SSAsset"
$sha     = Get-Pin '\$UE4SS_SHA256\s*=\s*"([0-9A-Fa-f]{64})"' "UE4SS_SHA256"

Write-Host ""
Write-Host ("Version : " + $Version)
Write-Host ("UE4SS   : " + $asset + " (" + $release + ")")
Write-Host ""

# --- mod source must be complete -----------------------------------------
$modSrc = Join-Path $repo "CtACmdr"
foreach ($need in @("Scripts\main.lua", "enabled.txt")) {
    if (-not (Test-Path -LiteralPath (Join-Path $modSrc $need))) { throw ("Missing from the mod: " + $need) }
}
$kit = Join-Path $repo "release-kit"
foreach ($need in @("READ ME FIRST.txt", "READ ME FIRST (mod only).txt")) {
    if (-not (Test-Path -LiteralPath (Join-Path $kit $need))) { throw ("Missing from release-kit: " + $need) }
}

$work = Join-Path $env:TEMP ("ctacmdr_build_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null

try {
    # --- get and check UE4SS ---------------------------------------------
    if ($UE4SSZip -ne "") {
        if (-not (Test-Path -LiteralPath $UE4SSZip)) { throw ("No such file: " + $UE4SSZip) }
        $zipPath = (Resolve-Path -LiteralPath $UE4SSZip).Path
        Write-Host ("Using local UE4SS zip: " + $zipPath)
    } else {
        $url = "https://github.com/UE4SS-RE/RE-UE4SS/releases/download/" + $release + "/" + $asset
        $zipPath = Join-Path $work "ue4ss.zip"
        Write-Host ("Downloading " + $url)
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing -TimeoutSec 180
    }
    $actual = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    if ($actual -ne $sha) {
        throw ("UE4SS checksum mismatch, refusing to build." + [Environment]::NewLine +
               "  expected " + $sha + [Environment]::NewLine +
               "  got      " + $actual)
    }
    Write-Host "UE4SS checksum verified"

    $ex = Join-Path $work "ue4ss_extracted"
    Expand-Archive -LiteralPath $zipPath -DestinationPath $ex -Force
    foreach ($need in @("dwmapi.dll", "ue4ss\UE4SS.dll")) {
        if (-not (Test-Path -LiteralPath (Join-Path $ex $need))) {
            throw ("The UE4SS zip does not have " + $need + " - this script expects the new ue4ss\ layout")
        }
    }

    # --- full zip: UE4SS + mod -------------------------------------------
    $full = Join-Path $work "full"
    New-Item -ItemType Directory -Force -Path $full | Out-Null
    Copy-Item -Path (Join-Path $ex "*") -Destination $full -Recurse -Force

    $modDst = Join-Path $full "ue4ss\Mods\CtACmdr"
    New-Item -ItemType Directory -Force -Path $modDst | Out-Null
    Copy-Item -LiteralPath (Join-Path $modSrc "Scripts") -Destination $modDst -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $modSrc "enabled.txt") -Destination $modDst -Force
    Copy-Item -LiteralPath (Join-Path $repo "LICENSE") -Destination (Join-Path $modDst "LICENSE") -Force

    # UE4SS is MIT: its licence text has to travel with its files
    $haveLicense = @(Get-ChildItem -Path $ex -Recurse -File -Filter "LICENSE*" -ErrorAction SilentlyContinue).Count -gt 0
    if (-not $haveLicense) {
        $licUrl = "https://raw.githubusercontent.com/UE4SS-RE/RE-UE4SS/main/LICENSE"
        $licDst = Join-Path $full "ue4ss\UE4SS-LICENSE.txt"
        try { Invoke-WebRequest -Uri $licUrl -OutFile $licDst -UseBasicParsing -TimeoutSec 60 }
        catch { throw ("Could not fetch the UE4SS licence text from " + $licUrl + " - not shipping UE4SS without it") }
        Write-Host "Added UE4SS-LICENSE.txt"
    }

    # UE4SS's stock mods.txt switches on a cheat enabler and a console
    # enabler. A realism mod should not hand every user those without asking,
    # so they ship switched off. Nothing else in mods.txt is touched.
    $modsTxtPath = Join-Path $full "ue4ss\Mods\mods.txt"
    if (-not (Test-Path -LiteralPath $modsTxtPath)) { throw "The UE4SS zip has no ue4ss\Mods\mods.txt" }
    $modsTxt = [IO.File]::ReadAllText($modsTxtPath)
    foreach ($name in @("CheatManagerEnablerMod", "ConsoleCommandsMod", "ConsoleEnablerMod")) {
        $pattern = "(?m)^(\s*" + $name + "\s*:\s*)1"
        if ($modsTxt -notmatch $pattern) { throw ("mods.txt does not list " + $name + " as enabled - has the UE4SS build changed?") }
        $modsTxt = [regex]::Replace($modsTxt, $pattern, '${1}0')
        # a mod folder with its own enabled.txt would load regardless of mods.txt
        if (Test-Path -LiteralPath (Join-Path $full ("ue4ss\Mods\" + $name + "\enabled.txt"))) {
            throw ($name + " ships its own enabled.txt, so mods.txt cannot switch it off")
        }
    }
    [IO.File]::WriteAllText($modsTxtPath, $modsTxt, (New-Object Text.UTF8Encoding($false)))
    Write-Host "Switched off the cheat and console enabler mods in mods.txt"

    $readme = (Get-Content -LiteralPath (Join-Path $kit "READ ME FIRST.txt") -Raw).Replace("{VERSION}", "v" + $Version)
    [IO.File]::WriteAllText((Join-Path $full "READ ME FIRST.txt"), $readme, (New-Object Text.UTF8Encoding($false)))

    # --- mod-only zip ----------------------------------------------------
    $only = Join-Path $work "modonly"
    $onlyMod = Join-Path $only "CtACmdr"
    New-Item -ItemType Directory -Force -Path $onlyMod | Out-Null
    Copy-Item -LiteralPath (Join-Path $modSrc "Scripts") -Destination $onlyMod -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $modSrc "enabled.txt") -Destination $onlyMod -Force
    Copy-Item -LiteralPath (Join-Path $repo "LICENSE") -Destination (Join-Path $onlyMod "LICENSE") -Force
    $readmeOnly = (Get-Content -LiteralPath (Join-Path $kit "READ ME FIRST (mod only).txt") -Raw).Replace("{VERSION}", "v" + $Version)
    [IO.File]::WriteAllText((Join-Path $only "READ ME FIRST.txt"), $readmeOnly, (New-Object Text.UTF8Encoding($false)))

    # --- zip them --------------------------------------------------------
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $OutDir = (Resolve-Path $OutDir).Path
    $zipFull = Join-Path $OutDir ("CtACmdr-v" + $Version + "-Windows.zip")
    $zipOnly = Join-Path $OutDir ("CtACmdr-v" + $Version + "-mod-only.zip")
    foreach ($z in @($zipFull, $zipOnly)) { if (Test-Path -LiteralPath $z) { Remove-Item -LiteralPath $z -Force } }
    # Windows PowerShell 5.1 writes backslashes inside zips, which the zip
    # format does not allow and some tools mis-extract. Write the entries
    # ourselves with forward slashes.
    function New-Zip([string]$srcDir, [string]$zipPath) {
        $srcDir = (Resolve-Path -LiteralPath $srcDir).Path.TrimEnd("\")
        $fs = [IO.File]::Open($zipPath, [IO.FileMode]::CreateNew)
        try {
            $za = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($f in (Get-ChildItem -LiteralPath $srcDir -Recurse -File)) {
                    $name = $f.FullName.Substring($srcDir.Length + 1).Replace("\", "/")
                    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($za, $f.FullName, $name, [IO.Compression.CompressionLevel]::Optimal)
                }
            }
            finally { $za.Dispose() }
        }
        finally { $fs.Dispose() }
    }
    New-Zip $full $zipFull
    New-Zip $only $zipOnly

    # --- check what actually went into them ------------------------------
    function Get-Entries([string]$path) {
        $zf = [IO.Compression.ZipFile]::OpenRead($path)
        try { return @($zf.Entries | ForEach-Object { $_.FullName.Replace("\", "/") }) }
        finally { $zf.Dispose() }
    }
    $fullEntries = Get-Entries $zipFull
    $onlyEntries = Get-Entries $zipOnly
    $mustFull = @("dwmapi.dll", "ue4ss/UE4SS.dll", "ue4ss/Mods/CtACmdr/Scripts/main.lua",
                  "ue4ss/Mods/CtACmdr/enabled.txt", "READ ME FIRST.txt")
    foreach ($m in $mustFull) { if ($fullEntries -notcontains $m) { throw ("Full zip is missing " + $m) } }
    $mustOnly = @("CtACmdr/Scripts/main.lua", "CtACmdr/enabled.txt", "READ ME FIRST.txt")
    foreach ($m in $mustOnly) { if ($onlyEntries -notcontains $m) { throw ("Mod-only zip is missing " + $m) } }
    foreach ($e in ($fullEntries + $onlyEntries)) {
        if ($e -match '_views\.txt|\.log$|\.dmp$|\.bak$|\.tmp$') { throw ("Something that must not ship is in a zip: " + $e) }
    }

    # --- checksums for the release notes ---------------------------------
    $lines = @()
    foreach ($z in @($zipFull, $zipOnly)) {
        $h = (Get-FileHash -LiteralPath $z -Algorithm SHA256).Hash
        $lines += ($h + "  " + (Split-Path $z -Leaf))
    }
    Set-Content -LiteralPath (Join-Path $OutDir "SHA256SUMS.txt") -Value $lines -Encoding ASCII

    Write-Host ""
    Write-Host "Built:"
    foreach ($z in @($zipFull, $zipOnly)) {
        Write-Host ("  " + $z + "  (" + [math]::Round((Get-Item $z).Length / 1MB, 1) + " MB)")
    }
    Write-Host ""
    Write-Host "SHA256SUMS.txt:"
    $lines | ForEach-Object { Write-Host ("  " + $_) }
    Write-Host ""
    Write-Host ("Full zip holds " + $fullEntries.Count + " entries, mod-only holds " + $onlyEntries.Count + ".")
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
