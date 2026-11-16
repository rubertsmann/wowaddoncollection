# Installs the working copy into the WoW Forever AddOns folder as a SEPARATE dev addon, so it can run next to the live one.
#   AddOns\TalentShare-Dev  -> junction to this repo (edit files, then /reload in game); uses a generated, git-ignored
#                              TalentShare-Dev.toc (own title, version "-dev", SavedVariables TalentShareDevDB)
#   AddOns\TalentShare      -> the LIVE addon (CurseForge or `-InstallLive`); never touched unless you ask
# Usage: powershell tools/deploy.ps1 [-WowDir "C:\Program Files (x86)\World of Warcraft"] [-WithProbe] [-InstallLive [-Force]]
param(
    [string]$WowDir = "C:\Program Files (x86)\World of Warcraft",
    [switch]$WithProbe,
    [switch]$InstallLive,   # extract the newest dist/TalentShare-*.zip into AddOns\TalentShare
    [switch]$Force          # allow -InstallLive to replace an existing real TalentShare folder
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$addons = Join-Path $WowDir "_forever_\Interface\AddOns"
if (-not (Test-Path $addons)) { throw "AddOns folder not found: $addons" }

function IsJunction($path) {
    $item = Get-Item $path -Force
    return ($item.LinkType -eq "Junction")
}
function JunctionTarget($path) { return (@((Get-Item $path -Force).Target) | Select-Object -First 1) }

function Link($name, $target) {
    $link = Join-Path $addons $name
    if (Test-Path $link) {
        if (-not (IsJunction $link)) { throw "$link exists and is a real folder - remove it first" }
        if ((JunctionTarget $link) -ne $target) { throw "$link is a junction to $(JunctionTarget $link), not to $target" }
        Write-Host "$name already linked"
        return
    }
    New-Item -ItemType Junction -Path $link -Target $target | Out-Null
    Write-Host "linked $link -> $target"
}

# 1. generate the dev TOC from the live one
$liveToc = Join-Path $repo "TalentShare.toc"
$devToc = Join-Path $repo "TalentShare-Dev.toc"
$lines = Get-Content $liveToc -Encoding UTF8 | ForEach-Object {
    if ($_ -match '^## Title:') { '## Title: TalentShare (dev)' }
    elseif ($_ -match '^## Notes:') { '## Notes: [DEV BUILD] ' + ($_ -replace '^## Notes:\s*', '') }
    elseif ($_ -match '^## Version:\s*(.+)$') { '## Version: ' + $Matches[1].Trim() + '-dev' }
    elseif ($_ -match '^## SavedVariables:') { '## SavedVariables: TalentShareDevDB' }
    elseif ($_ -match '^## X-Website:') { $null }
    else { $_ }
} | Where-Object { $null -ne $_ }
[IO.File]::WriteAllText($devToc, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
Write-Host "generated $devToc"

# 2. the old dev setup linked the repo as AddOns\TalentShare: remove that link (never the files) so the live addon can live there
$old = Join-Path $addons "TalentShare"
if ((Test-Path $old) -and (IsJunction $old) -and ((JunctionTarget $old) -eq $repo)) {
    (Get-Item $old -Force).Delete()   # removes the junction only; the target folder is not touched
    Write-Host "removed old dev junction $old"
    if (-not (Test-Path (Join-Path $repo "TalentShare.toc"))) { throw "repo files vanished - stop" }
}

# 3. link the dev addon (+ probe)
Link "TalentShare-Dev" $repo
if ($WithProbe) { Link "TalentShareProbe" (Join-Path $repo "dev\TalentShareProbe") }

# 4. optional: install the live build from the newest package
if ($InstallLive) {
    $zip = Get-ChildItem (Join-Path $repo "dist") -Filter "TalentShare-*.zip" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $zip) { throw "no dist/TalentShare-*.zip; run tools/package.ps1 first" }
    $live = Join-Path $addons "TalentShare"
    if (Test-Path $live) {
        if (IsJunction $live) { throw "$live is a junction; remove it first" }
        if (-not $Force) { throw "$live already exists (real folder). Use -Force to replace it" }
        Remove-Item $live -Recurse -Force
    }
    Expand-Archive $zip.FullName -DestinationPath $addons
    Write-Host "installed live build from $($zip.Name) into $live"
}

Write-Host ""
Write-Host "dev:  /tsd (SavedVariables TalentShareDevDB, prefix TShareDev)"
Write-Host "live: /ts  (SavedVariables TalentShareDB, prefix TShare) - present: $(Test-Path (Join-Path $addons 'TalentShare'))"
