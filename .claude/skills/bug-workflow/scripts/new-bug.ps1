# Scaffolds bugs/B<NNN>-<slug>/ from the templates and registers it in bugs/INDEX.md.
# Usage (from the wowaddons root): powershell -File .claude/skills/bug-workflow/scripts/new-bug.ps1 -Name "Trap used without a message" -Root guildgames -Severity S2
# -Root is the addon folder. Bug ids are unique across the whole monorepo (every <addon>/bugs is scanned).
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Root,
    [ValidateSet("S1", "S2", "S3")][string]$Severity = "S2",
    [string]$FoundIn = "-"
)
$ErrorActionPreference = "Stop"
$templates = Join-Path (Split-Path -Parent $PSScriptRoot) "templates"
if (-not $Root) { throw "pass -Root <addon folder>, e.g. -Root guildgames" }
$Root = (Resolve-Path $Root).Path
$bugs = Join-Path $Root "bugs"
New-Item -ItemType Directory -Force $bugs | Out-Null

$slug = ($Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
if (-not $slug) { throw "Name has no usable characters" }

$max = 0
$all = Get-ChildItem (Split-Path -Parent $Root) -Directory | ForEach-Object { Join-Path $_.FullName "bugs" } | Where-Object { Test-Path $_ }
foreach ($d in ($all | ForEach-Object { Get-ChildItem $_ -Directory })) {
    if ($d.Name -match '^B(\d{3})-(.+)$') {
        if ($d.Parent.FullName -eq $bugs -and $Matches[2] -eq $slug) { throw "bug '$slug' already exists: $($d.FullName)" }
        $max = [Math]::Max($max, [int]$Matches[1])
    }
}
$id = "B{0:D3}" -f ($max + 1)
$dir = Join-Path $bugs "$id-$slug"
New-Item -ItemType Directory -Force (Join-Path $dir "evidence") | Out-Null

$date = Get-Date -Format "yyyy-MM-dd"
$now = Get-Date -Format "yyyy-MM-dd HH:mm"
foreach ($f in "bug.md", "log.md") {
    $text = [IO.File]::ReadAllText((Join-Path $templates $f), [Text.Encoding]::UTF8)
    $text = $text.Replace("{{ID}}", $id).Replace("{{SLUG}}", $slug).Replace("{{TITLE}}", $Name).Replace("{{NOW}}", $now).Replace("{{DATE}}", $date).Replace("{{SEVERITY}}", $Severity)
    [IO.File]::WriteAllText((Join-Path $dir $f), $text, (New-Object Text.UTF8Encoding($false)))
}
New-Item -ItemType File -Force (Join-Path $dir "evidence\.gitkeep") | Out-Null

$index = Join-Path $bugs "INDEX.md"
if (-not (Test-Path $index)) {
    $header = "# Bugs`n`nOne row per bug. Status: reported, confirmed, fixing, verifying, fixed, wontfix, duplicate, cannot-reproduce. Severity: S1 data/money loss or broken addon, S2 wrong or silent behaviour, S3 cosmetic. Workflow: .claude/skills/bug-workflow/SKILL.md`n`n| ID | Bug | Severity | Status | Found in | Fixed in | Folder |`n|---|---|---|---|---|---|---|`n"
    [IO.File]::WriteAllText($index, $header, (New-Object Text.UTF8Encoding($false)))
}
$row = "| $id | $Name | $Severity | reported | $FoundIn | - | [$id-$slug]($id-$slug/bug.md) |`n"
[IO.File]::AppendAllText($index, $row, (New-Object Text.UTF8Encoding($false)))

Write-Host "created $dir"
Write-Host "next: fill the Report section of $dir\bug.md"
