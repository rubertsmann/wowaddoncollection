# Scaffolds features/<NNN>-<slug>/ from the templates and registers it in features/INDEX.md.
# Usage (from the wowaddons root): powershell -File .claude/skills/feature-workflow/scripts/new-feature.ps1 -Name "Localization layer" -Root guildgames
# -Root is the addon folder. Feature ids are unique across the whole monorepo (every <addon>/features is scanned).
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Root
)
$ErrorActionPreference = "Stop"
$templates = Join-Path (Split-Path -Parent $PSScriptRoot) "templates"
if (-not $Root) { throw "pass -Root <addon folder>, e.g. -Root guildgames" }
$Root = (Resolve-Path $Root).Path
$features = Join-Path $Root "features"
New-Item -ItemType Directory -Force $features | Out-Null

$slug = ($Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
if (-not $slug) { throw "Name has no usable characters" }

$max = 0
$all = Get-ChildItem (Split-Path -Parent $Root) -Directory | ForEach-Object { Join-Path $_.FullName "features" } | Where-Object { Test-Path $_ }
foreach ($d in ($all | ForEach-Object { Get-ChildItem $_ -Directory })) {
    if ($d.Name -match '^(\d{3})-(.+)$' -and $d.Parent.FullName -ne $features) { $max = [Math]::Max($max, [int]$Matches[1]); continue }
    if ($d.Name -match '^(\d{3})-(.+)$') {
        if ($Matches[2] -eq $slug) { throw "feature '$slug' already exists: $($d.FullName)" }
        $max = [Math]::Max($max, [int]$Matches[1])
    }
}
$id = "{0:D3}" -f ($max + 1)
$dir = Join-Path $features "$id-$slug"
New-Item -ItemType Directory -Force (Join-Path $dir "evidence") | Out-Null

$date = Get-Date -Format "yyyy-MM-dd"
$now = Get-Date -Format "yyyy-MM-dd HH:mm"
foreach ($f in "spec.md", "log.md", "verify.md", "doc.md") {
    $text = [IO.File]::ReadAllText((Join-Path $templates $f), [Text.Encoding]::UTF8)
    $text = $text.Replace("{{ID}}", $id).Replace("{{SLUG}}", $slug).Replace("{{TITLE}}", $Name).Replace("{{NOW}}", $now).Replace("{{DATE}}", $date)
    [IO.File]::WriteAllText((Join-Path $dir $f), $text, (New-Object Text.UTF8Encoding($false)))
}
New-Item -ItemType File -Force (Join-Path $dir "evidence\.gitkeep") | Out-Null

$index = Join-Path $features "INDEX.md"
if (-not (Test-Path $index)) {
    $header = "# Features`n`nOne row per feature. Status: planned, in-progress, verifying, done, abandoned. Workflow: .claude/skills/feature-workflow/SKILL.md`n`n| ID | Feature | Status | Version | Commits | Folder |`n|---|---|---|---|---|---|`n"
    [IO.File]::WriteAllText($index, $header, (New-Object Text.UTF8Encoding($false)))
}
$row = "| $id | $Name | planned | - | - | [$id-$slug]($id-$slug/spec.md) |`n"
[IO.File]::AppendAllText($index, $row, (New-Object Text.UTF8Encoding($false)))

Write-Host "created $dir"
Write-Host "next: fill $dir\spec.md"
