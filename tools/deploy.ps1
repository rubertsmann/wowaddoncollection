# Installs the working copy into the WoW Forever AddOns folder as a SEPARATE dev addon, so it can run next to the live one.
#   AddOns\GuildGames-Dev  -> junction to this repo (edit files, then /reload in game); uses a generated, git-ignored
#                              GuildGames-Dev.toc (own title, version "-dev", SavedVariables GuildGamesDevDB)
#   AddOns\GuildGames      -> the LIVE addon (CurseForge or `-InstallLive`); never touched unless you ask
# RE-RUN THIS whenever GuildGames.toc changes (a file added or removed, a version bump): the dev TOC is a generated copy
#   and goes stale, and the dev client then fails with "attempt to index a nil value" in the file that needs the new one.
#   tests/test_load.lua fails while the generated TOC is stale. Restart the game afterwards: /reload does not re-read the TOC.
# Usage: powershell tools/deploy.ps1 [-WowDir "C:\Program Files (x86)\World of Warcraft"] [-InstallLive [-Force]]
param(
    [string]$WowDir = "C:\Program Files (x86)\World of Warcraft",
    [switch]$InstallLive,   # extract the newest dist/GuildGames-*.zip into AddOns\GuildGames
    [switch]$Force          # allow -InstallLive to replace an existing real GuildGames folder
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
$liveToc = Join-Path $repo "GuildGames.toc"
$devToc = Join-Path $repo "GuildGames-Dev.toc"
$lines = Get-Content $liveToc -Encoding UTF8 | ForEach-Object {
    if ($_ -match '^## Title:') { '## Title: GuildGames (dev)' }
    elseif ($_ -match '^## Notes:') { '## Notes: [DEV BUILD] ' + ($_ -replace '^## Notes:\s*', '') }
    elseif ($_ -match '^## Version:\s*(.+)$') { '## Version: ' + $Matches[1].Trim() + '-dev' }
    elseif ($_ -match '^## SavedVariables:') { '## SavedVariables: GuildGamesDevDB'; '## X-Build: dev' }   # X-Build = the build flag Core/Init.lua reads (addon.BUILD); the live TOC has no such line
    elseif ($_ -match '^## X-Website:') { $null }
    else { $_ }
} | Where-Object { $null -ne $_ }
# invariants: a dev TOC that kept the live SavedVariables or lost the build flag would let dev and live share state
$svLines = @($lines | Where-Object { $_ -match '^## SavedVariables' })
if ($svLines.Count -ne 1 -or $svLines[0] -ne '## SavedVariables: GuildGamesDevDB') { throw "dev TOC must declare exactly one '## SavedVariables: GuildGamesDevDB', found: $($svLines -join ' | ')" }
if (@($lines | Where-Object { $_ -eq '## X-Build: dev' }).Count -ne 1) { throw "dev TOC must contain exactly one '## X-Build: dev'" }
if (@($lines | Where-Object { $_ -match 'GuildGamesDB' }).Count -gt 0) { throw "dev TOC still mentions the live GuildGamesDB" }
[IO.File]::WriteAllText($devToc, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
Write-Host "generated $devToc"

# 2b. the embedded LibGuildSync (feature 015): Libs\LibGuildSync is a junction to the library repo next to this one
#     (git-ignored here; tools/package.ps1 copies the real files into the zip)
$libraryLink = Join-Path $repo "Libs\LibGuildSync"
$librarySource = Join-Path (Split-Path -Parent $repo) "libguildsync\LibGuildSync"
if (-not (Test-Path $libraryLink)) {
    if (-not (Test-Path (Join-Path $librarySource "LibGuildSync.xml"))) { throw "LibGuildSync not found at $librarySource (clone libguildsync next to this repo)" }
    New-Item -ItemType Junction -Path $libraryLink -Target $librarySource | Out-Null
    Write-Host "linked $libraryLink -> $librarySource"
}

# 3. link the dev addon
Link "GuildGames-Dev" $repo

# 4. optional: install the live build from the newest package
if ($InstallLive) {
    $zip = Get-ChildItem (Join-Path $repo "dist") -Filter "GuildGames-*.zip" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $zip) { throw "no dist/GuildGames-*.zip; run tools/package.ps1 first" }
    $live = Join-Path $addons "GuildGames"
    if (Test-Path $live) {
        if (IsJunction $live) { throw "$live is a junction; remove it first" }
        if (-not $Force) { throw "$live already exists (real folder). Use -Force to replace it" }
        Remove-Item $live -Recurse -Force
    }
    Expand-Archive $zip.FullName -DestinationPath $addons
    Write-Host "installed live build from $($zip.Name) into $live"
}

Write-Host ""
Write-Host "dev:  /ggd (SavedVariables GuildGamesDevDB, prefix GGamesDev)"
Write-Host "live: /gg  (SavedVariables GuildGamesDB, prefix GGames) - present: $(Test-Path (Join-Path $addons 'GuildGames'))"
