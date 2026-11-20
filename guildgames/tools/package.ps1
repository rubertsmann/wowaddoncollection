# Builds dist/GuildGames-<version>.zip containing a single top-level GuildGames/ folder (manual release).
# Entries are written with forward slashes: Windows PowerShell 5.1's Compress-Archive stores backslashes
# ("GuildGames\Core\Game\Api.lua"), which zip tools on other platforms (and CurseForge) treat as flat file names.
# Usage: powershell tools/package.ps1 [-ZipVersion 0.7.0-test]   (only names the zip; default: the TOC version)
param([string]$ZipVersion)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repo = Split-Path -Parent $PSScriptRoot
$version = (Select-String -Path (Join-Path $repo "GuildGames.toc") -Pattern '^## Version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
if ($ZipVersion) { $version = $ZipVersion }
$dist = Join-Path $repo "dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$zip = Join-Path $dist "GuildGames-$version.zip"
if (Test-Path $zip) { Remove-Item $zip }

# Files that ship (the zip holds only these).
# Directory junctions (Libs\LibGuildSync -> ..\libguildsync\LibGuildSync, feature 015) are not followed by -Recurse in
# Windows PowerShell 5.1, so every junction below an item is listed on its own: the zip gets the real files.
function Get-ShippedFiles($path) {
    Get-ChildItem $path -File
    foreach ($directory in (Get-ChildItem $path -Directory)) { Get-ShippedFiles $directory.FullName }
}
$items = "GuildGames.toc", "Bindings.xml", "Core", "Locales", "UI", "Libs", "README.md"
$files = foreach ($item in $items) {
    $path = Join-Path $repo $item
    if (-not (Test-Path $path)) { throw "missing: $path" }
    if ((Get-Item $path).PSIsContainer) { Get-ShippedFiles $path } else { Get-Item $path }
}

$prefix = $repo.TrimEnd('\') + '\'
$archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($f in ($files | Sort-Object FullName)) {
        $name = "GuildGames/" + $f.FullName.Substring($prefix.Length).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $f.FullName, $name, [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally {
    $archive.Dispose()
}

# Self-check: single top-level folder, forward slashes only, TOC present.
$check = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
    $names = @($check.Entries | ForEach-Object { $_.FullName })
    # the shipped TOC must be the LIVE build: live SavedVariables, no dev build flag
    $reader = New-Object System.IO.StreamReader($check.GetEntry("GuildGames/GuildGames.toc").Open())
    try { $tocText = $reader.ReadToEnd() } finally { $reader.Dispose() }
} finally {
    $check.Dispose()
}
$bad = @($names | Where-Object { $_ -match '\\' -or $_ -notlike 'GuildGames/*' })
if ($bad.Count -gt 0) { throw "bad zip entry names: $($bad -join ', ')" }
if ($names -notcontains "GuildGames/GuildGames.toc") { throw "GuildGames/GuildGames.toc missing from zip" }
if ($names -notcontains "GuildGames/Bindings.xml") { throw "GuildGames/Bindings.xml missing from zip (AZEcaught key binding, feature 018)" }
if ($names -contains "GuildGames/GuildGames-Dev.toc") { throw "the dev TOC must not ship" }
if ($tocText -match '(?m)^## X-Build:') { throw "GuildGames.toc carries a build flag; the shipped TOC must be the live build" }
if ($tocText -notmatch '(?m)^## SavedVariables:\s*GuildGamesDB\s*$') { throw "GuildGames.toc must declare '## SavedVariables: GuildGamesDB'" }
# the embedded LibGuildSync (feature 015) must ship as real files: the xml and every file it loads
$libraryXml = Join-Path $repo "Libs\LibGuildSync\LibGuildSync.xml"
$libraryFiles = @("LibGuildSync.xml") + @([regex]::Matches((Get-Content $libraryXml -Raw), '<Script\s+file="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
foreach ($libraryFile in $libraryFiles) {
    if ($names -notcontains "GuildGames/Libs/LibGuildSync/$libraryFile") { throw "Libs/LibGuildSync/$libraryFile missing from zip" }
}
Write-Host "built $zip ($($names.Count) files)"
