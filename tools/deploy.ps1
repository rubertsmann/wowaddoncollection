# Links this repo into the WoW Forever AddOns folder as a junction (edit files, then /reload in game).
# Usage: powershell tools/deploy.ps1 [-WowDir "C:\Program Files (x86)\World of Warcraft"] [-WithProbe]
param(
    [string]$WowDir = "C:\Program Files (x86)\World of Warcraft",
    [switch]$WithProbe
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$addons = Join-Path $WowDir "_forever_\Interface\AddOns"
if (-not (Test-Path $addons)) { throw "AddOns folder not found: $addons" }

function Link($name, $target) {
    $link = Join-Path $addons $name
    if (Test-Path $link) {
        $item = Get-Item $link
        if ($item.LinkType -eq "Junction") { Write-Host "$name already linked"; return }
        throw "$link exists and is a real folder - remove it first"
    }
    New-Item -ItemType Junction -Path $link -Target $target | Out-Null
    Write-Host "linked $link -> $target"
}

Link "TalentShare" $repo
if ($WithProbe) { Link "TalentShareProbe" (Join-Path $repo "dev\TalentShareProbe") }
