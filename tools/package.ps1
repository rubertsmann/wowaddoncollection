# Builds dist/TalentShare-<version>.zip containing a single top-level TalentShare/ folder (manual release).
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$version = (Select-String -Path (Join-Path $repo "TalentShare.toc") -Pattern '^## Version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
$stage = Join-Path $env:TEMP "TalentShare-stage"
$dist = Join-Path $repo "dist"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force (Join-Path $stage "TalentShare"), $dist | Out-Null
foreach ($item in "TalentShare.toc", "Core", "Locales", "UI", "Libs", "README.md") {
    Copy-Item (Join-Path $repo $item) (Join-Path $stage "TalentShare") -Recurse
}
$zip = Join-Path $dist "TalentShare-$version.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $stage "TalentShare") -DestinationPath $zip
Write-Host "built $zip"
