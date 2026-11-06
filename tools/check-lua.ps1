# Lua syntax check for the mod. Catches the mistakes that only show up
# as "Error loading script" deep in UE4SS.log, after a game restart.
#
#   powershell -ExecutionPolicy Bypass -File tools\check-lua.ps1
#
# Needs node/npx. luaparse is fetched on demand, nothing is installed.

param(
    [string]$File = (Join-Path $PSScriptRoot "..\CtACmdr\Scripts\main.lua")
)

$ErrorActionPreference = "Stop"
$env:npm_config_yes = "true"

if (-not (Test-Path -LiteralPath $File)) {
    throw "No such file: $File"
}

Write-Host "Checking $File"
npx --yes luaparse@0.3.1 -q "$File"

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "SYNTAX ERROR. See the message above." -ForegroundColor Red
    exit 1
}

Write-Host "OK - syntax is valid" -ForegroundColor Green
