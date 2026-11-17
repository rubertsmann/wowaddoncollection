# Builds dist/TalentShare-<version>.zip containing a single top-level TalentShare/ folder (manual release).
# Entries are written with forward slashes: Windows PowerShell 5.1's Compress-Archive stores backslashes
# ("TalentShare\Core\Game\Api.lua"), which zip tools on other platforms (and CurseForge) treat as flat file names.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repo = Split-Path -Parent $PSScriptRoot
$version = (Select-String -Path (Join-Path $repo "TalentShare.toc") -Pattern '^## Version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
$dist = Join-Path $repo "dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$zip = Join-Path $dist "TalentShare-$version.zip"
if (Test-Path $zip) { Remove-Item $zip }

# Files that ship (keep in sync with .pkgmeta ignore list).
$items = "TalentShare.toc", "Core", "Locales", "UI", "Libs", "README.md"
$files = foreach ($item in $items) {
    $path = Join-Path $repo $item
    if (-not (Test-Path $path)) { throw "missing: $path" }
    if ((Get-Item $path).PSIsContainer) { Get-ChildItem $path -Recurse -File } else { Get-Item $path }
}

$prefix = $repo.TrimEnd('\') + '\'
$archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($f in ($files | Sort-Object FullName)) {
        $name = "TalentShare/" + $f.FullName.Substring($prefix.Length).Replace('\', '/')
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
    $reader = New-Object System.IO.StreamReader($check.GetEntry("TalentShare/TalentShare.toc").Open())
    try { $tocText = $reader.ReadToEnd() } finally { $reader.Dispose() }
} finally {
    $check.Dispose()
}
$bad = @($names | Where-Object { $_ -match '\\' -or $_ -notlike 'TalentShare/*' })
if ($bad.Count -gt 0) { throw "bad zip entry names: $($bad -join ', ')" }
if ($names -notcontains "TalentShare/TalentShare.toc") { throw "TalentShare/TalentShare.toc missing from zip" }
if ($names -contains "TalentShare/TalentShare-Dev.toc") { throw "the dev TOC must not ship" }
if ($tocText -match '(?m)^## X-Build:') { throw "TalentShare.toc carries a build flag; the shipped TOC must be the live build" }
if ($tocText -notmatch '(?m)^## SavedVariables:\s*TalentShareDB\s*$') { throw "TalentShare.toc must declare '## SavedVariables: TalentShareDB'" }
Write-Host "built $zip ($($names.Count) files)"
