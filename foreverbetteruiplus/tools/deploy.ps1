# Links this repo into the WoW Forever AddOns folder as AddOns\ForeverBetterUIPlus (a junction: edit files, /reload in game).
# New files and TOC changes need a full game restart; edits to existing Lua files only need /reload.
# Usage: powershell tools/deploy.ps1 [-WowDir "C:\Program Files (x86)\World of Warcraft"]
param([string]$WowDir = "C:\Program Files (x86)\World of Warcraft")
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$addons = Join-Path $WowDir "_forever_\Interface\AddOns"
if (-not (Test-Path $addons)) { throw "AddOns folder not found: $addons" }
$link = Join-Path $addons "ForeverBetterUIPlus"
if (Test-Path $link) {
    $item = Get-Item $link -Force
    if ($item.LinkType -ne "Junction") { throw "$link exists and is a real folder - remove it first" }
    Write-Host "already linked: $link -> $(@($item.Target)[0])"
} else {
    New-Item -ItemType Junction -Path $link -Target $repo | Out-Null
    Write-Host "linked $link -> $repo"
}
