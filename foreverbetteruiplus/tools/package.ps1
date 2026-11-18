# Builds dist/ForeverBetterUIPlus-<version>.zip with a single top-level ForeverBetterUIPlus/ folder (forward-slash entry names).
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repo = Split-Path -Parent $PSScriptRoot
$version = (Select-String -Path (Join-Path $repo "ForeverBetterUIPlus.toc") -Pattern '^## Version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
$dist = Join-Path $repo "dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$zip = Join-Path $dist "ForeverBetterUIPlus-$version.zip"
if (Test-Path $zip) { Remove-Item $zip }

# Files that ship: the TOC, the Lua files it lists, and the README.
$items = "ForeverBetterUIPlus.toc", "Logic.lua", "Elements.lua", "Log.lua", "Fader.lua", "EditModeProbe.lua", "Options.lua", "Commands.lua", "README.md"
$files = foreach ($item in $items) {
    $path = Join-Path $repo $item
    if (-not (Test-Path $path)) { throw "missing: $path" }
    if ((Get-Item $path).PSIsContainer) { Get-ChildItem $path -Recurse -File } else { Get-Item $path }
}
$prefix = $repo.TrimEnd('\') + '\'
$archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($f in ($files | Sort-Object FullName)) {
        $name = "ForeverBetterUIPlus/" + $f.FullName.Substring($prefix.Length).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $f.FullName, $name, [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally { $archive.Dispose() }
Write-Host "built $zip ($(@($files).Count) files)"
