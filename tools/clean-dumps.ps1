# Housekeeping: remove the dump files UE4SS leaves behind.
#
# UE4SS writes a crash_*.dmp in Binaries\Win64 whenever it catches an
# exception, which this game throws most sessions. They are around 33 MB
# each and they are NOT crash reports - a real crash leaves a folder under
# %LOCALAPPDATA%\call_to_arms_pe\Saved\Crashes instead.
#
#   powershell -ExecutionPolicy Bypass -File tools\clean-dumps.ps1
#   powershell -ExecutionPolicy Bypass -File tools\clean-dumps.ps1 -Keep 0
#   powershell -ExecutionPolicy Bypass -File tools\clean-dumps.ps1 -DryRun
#
# -Keep     how many of the newest dumps to leave behind (default 2)
# -DryRun   show what would go, delete nothing
# -Usmap    also remove the .usmap file left by UE4SS's DumpUSMAP

param(
    [string]$GameRoot = "L:\SteamLibrary\steamapps\common\Call To Arms - Panzer Elite",
    [int]$Keep = 2,
    [switch]$DryRun,
    [switch]$Usmap
)

$ErrorActionPreference = "Stop"

$bin = Join-Path $GameRoot "call_to_arms_pe\Binaries\Win64"
if (-not (Test-Path -LiteralPath $bin)) { throw "Game not found at: $bin" }

$targets = @()

$dumps = @(Get-ChildItem -LiteralPath $bin -Filter "crash_*.dmp" -File -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending)
if ($dumps.Count -gt $Keep) {
    $targets += $dumps[$Keep..($dumps.Count - 1)]
}

if ($Usmap) {
    $maps = @(Get-ChildItem -LiteralPath $bin -Filter "*.usmap" -File -ErrorAction SilentlyContinue)
    $targets += $maps
}

if ($targets.Count -eq 0) {
    Write-Host "Nothing to clean."
    if ($dumps.Count -gt 0) {
        $mb = [math]::Round((($dumps | Measure-Object Length -Sum).Sum) / 1MB, 1)
        Write-Host ("Kept {0} dump(s), {1} MB." -f $dumps.Count, $mb)
    }
    exit 0
}

$freed = ($targets | Measure-Object Length -Sum).Sum
Write-Host ("Removing {0} file(s), {1} MB:" -f $targets.Count, [math]::Round($freed / 1MB, 1))
foreach ($f in $targets) {
    Write-Host ("  {0}  {1}" -f $f.Name, [math]::Round($f.Length / 1MB, 1))
    if (-not $DryRun) {
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
    }
}

if ($DryRun) { Write-Host "Dry run - nothing deleted." }
else {
    $left = @(Get-ChildItem -LiteralPath $bin -Filter "crash_*.dmp" -File -ErrorAction SilentlyContinue)
    Write-Host ("Done. {0} dump(s) left." -f $left.Count)
}
