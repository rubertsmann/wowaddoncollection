# Builds dist/FpvCigarette-<version>.zip with a single top-level FpvCigarette/ folder (forward-slash entry names).
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repo = Split-Path -Parent $PSScriptRoot
$version = (Select-String -Path (Join-Path $repo "FpvCigarette.toc") -Pattern '^## Version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
$dist = Join-Path $repo "dist"
New-Item -ItemType Directory -Force $dist | Out-Null
$zip = Join-Path $dist "FpvCigarette-$version.zip"
if (Test-Path $zip) { Remove-Item $zip }

# Files that ship: the TOC, the Lua files it lists, the textures and the README.
$items = "FpvCigarette.toc", "Geometry.lua", "Log.lua", "Logic.lua", "Overlay.lua", "Commands.lua", "Textures", "README.md"
$files = foreach ($item in $items) {
    $path = Join-Path $repo $item
    if (-not (Test-Path $path)) { throw "missing: $path" }
    if ((Get-Item $path).PSIsContainer) { Get-ChildItem $path -Recurse -File } else { Get-Item $path }
}
$prefix = $repo.TrimEnd('\') + '\'
$archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($f in ($files | Sort-Object FullName)) {
        $name = "FpvCigarette/" + $f.FullName.Substring($prefix.Length).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $f.FullName, $name, [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally { $archive.Dispose() }
Write-Host "built $zip ($(@($files).Count) files)"
