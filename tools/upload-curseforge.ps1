# Uploads an addon's release zip (built by <addon>/tools/package.ps1) to CurseForge. Last step of a release:
# tests, commit, tag, push, package, upload.
#
# Settings (public, committed): <addon>/tools/curseforge.json  { "projectId": 123, "gameVersions": ["1.60.1"],
#   "relations": [{ "slug": "auctionator", "type": "optionalDependency" }] }   (relations optional; types: embeddedLibrary,
#   incompatible, optionalDependency, requiredDependency, tool)
# Token (secret, gitignored): $env:CF_API_TOKEN, or the first line of .curseforge-token in the repo root or in your
#   user folder (misspellings such as .cursforge-token are accepted too). Create it at
#   https://legacy.curseforge.com/account/api-tokens
# Changelog: the newest section of <addon>/RELEASE_NOTES.md ("# <Name> <version>"), else of CHANGELOG.md ("## <version>").
#
# Usage (from the repo root):
#   powershell -File tools/upload-curseforge.ps1 -Addon professionshare -DryRun   # checks, uploads nothing
#   powershell -File tools/upload-curseforge.ps1 -Addon professionshare           # uploads (-ReleaseType beta|alpha)
#   powershell -File tools/upload-curseforge.ps1 -ListGameVersions                # names for curseforge.json
param(
    [string]$Addon,
    [ValidateSet("release", "beta", "alpha")][string]$ReleaseType = "release",
    [switch]$DryRun,
    [switch]$ListGameVersions
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Net.Http
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root = Split-Path -Parent $PSScriptRoot
$api = "https://wow.curseforge.com/api"

function Get-Token {
    if ($env:CF_API_TOKEN) { return $env:CF_API_TOKEN.Trim() }
    foreach ($folder in @($root, $HOME)) {
        # .curseforge-token, or a misspelling of it (.cursforge-token, .curseforg-token): all gitignored as .curs*-token*
        foreach ($candidate in @(Get-ChildItem $folder -Force -File -Filter ".curs*-token" -ErrorAction SilentlyContinue)) {
            $token = Get-Content $candidate.FullName -TotalCount 1
            if ($token -and $token.Trim()) { return $token.Trim() }
            throw "$($candidate.FullName) is empty"
        }
    }
    throw "no CurseForge token: set `$env:CF_API_TOKEN or put it in $root\.curseforge-token"
}

function Get-GameVersions($token) {
    Invoke-RestMethod -Uri "$api/game/versions" -Headers @{ "X-Api-Token" = $token }
}

if ($ListGameVersions) {
    $token = Get-Token
    $types = @{}
    foreach ($type in (Invoke-RestMethod -Uri "$api/game/version-types" -Headers @{ "X-Api-Token" = $token })) {
        $types[[int]$type.id] = $type.name
    }
    Get-GameVersions $token | Sort-Object gameVersionTypeID, id |
        Format-Table id, name, @{ n = "type"; e = { $types[[int]$_.gameVersionTypeID] } } -AutoSize
    return
}

# --- what to upload -------------------------------------------------------------------------------------------------
if (-not $Addon) { throw "-Addon <folder> is required (e.g. professionshare, guildgames)" }
$addonDir = Join-Path $root $Addon
if (-not (Test-Path $addonDir)) { throw "no addon folder $addonDir" }
$toc = Get-ChildItem $addonDir -Filter *.toc | Where-Object { $_.Name -notlike "*-Dev.toc" } | Select-Object -First 1
if (-not $toc) { throw "no live .toc in $addonDir" }
$name = $toc.BaseName
$version = (Select-String -Path $toc.FullName -Pattern '^## Version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
$zip = Join-Path $addonDir "dist\$name-$version.zip"
if (-not (Test-Path $zip)) { throw "missing ${zip}: run $Addon/tools/package.ps1 first" }

# the section of the notes that belongs to this version, from its heading to the next heading of the same level
function Get-Section($path, $heading, $prefix) {
    $lines = Get-Content $path -Encoding UTF8
    $start = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Trim() -eq $heading -or $lines[$index].StartsWith("$heading ")) { $start = $index; break }
    }
    if ($start -lt 0) { return $null }
    $section = @($lines[$start])
    for ($index = $start + 1; $index -lt $lines.Count -and -not $lines[$index].StartsWith($prefix); $index++) {
        $section += $lines[$index]
    }
    return ($section -join "`n").Trim()
}
$releaseNotes = Join-Path $addonDir "RELEASE_NOTES.md"
$changelogFile = Join-Path $addonDir "CHANGELOG.md"
$changelog = $null
if (Test-Path $releaseNotes) { $changelog = Get-Section $releaseNotes "# $name $version" "# " }
if (-not $changelog -and (Test-Path $changelogFile)) { $changelog = Get-Section $changelogFile "## $version" "## " }
if (-not $changelog) { throw "no notes for ${version}: add '# $name $version' to RELEASE_NOTES.md or '## $version' to CHANGELOG.md" }

$settingsPath = Join-Path $addonDir "tools\curseforge.json"
if (-not (Test-Path $settingsPath)) { throw "missing $settingsPath" }
$settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $settings.projectId) { throw "set projectId in $settingsPath (the number on the project's CurseForge page)" }
$versionNames = @($settings.gameVersions | Where-Object { $_ })
if ($versionNames.Count -eq 0) { throw "set gameVersions in $settingsPath (see -ListGameVersions)" }
# other CurseForge projects this file relates to (shown on the project's Relations tab), by project slug
$relationTypes = @("embeddedLibrary", "incompatible", "optionalDependency", "requiredDependency", "tool")
$relations = @(foreach ($relation in @($settings.relations | Where-Object { $_ })) {
    if (-not $relation.slug -or $relation.slug -notmatch '^[a-z0-9-]+$') { throw "relation without a valid slug in $settingsPath" }
    if ($relationTypes -notcontains $relation.type) { throw "relation '$($relation.slug)': type must be one of $($relationTypes -join ', ')" }
    @{ slug = [string]$relation.slug; type = [string]$relation.type }
})

Write-Host "project:   $($settings.projectId) ($name)"
Write-Host "file:      $zip ($([math]::Round((Get-Item $zip).Length / 1KB)) KB)"
Write-Host "type:      $ReleaseType"
Write-Host "game:      $($versionNames -join ', ')"
Write-Host "relations: $(if ($relations.Count) { ($relations | ForEach-Object { "$($_.slug) ($($_.type))" }) -join ', ' } else { 'none' })"
Write-Host "changelog:"
Write-Host $changelog
if ($DryRun) { Write-Host "`ndry run: nothing uploaded"; return }

# --- upload ---------------------------------------------------------------------------------------------------------
$token = Get-Token
$known = Get-GameVersions $token
$gameVersionIds = foreach ($versionName in $versionNames) {
    $match = @($known | Where-Object { $_.name -eq $versionName -or $_.slug -eq $versionName })
    if ($match.Count -eq 0) { throw "CurseForge has no game version '$versionName' (see -ListGameVersions)" }
    if ($match.Count -gt 1) { throw "game version '$versionName' is ambiguous (ids $(($match | ForEach-Object id) -join ', ')); put the id into $settingsPath" }
    [int]$match[0].id
}

$metadataFields = @{
    changelog     = $changelog
    changelogType = "markdown"
    displayName   = "$name $version"
    gameVersions  = @($gameVersionIds)
    releaseType   = $ReleaseType
}
if ($relations.Count -gt 0) { $metadataFields.relations = @{ projects = @($relations) } }
$metadata = $metadataFields | ConvertTo-Json -Compress -Depth 5

$client = New-Object System.Net.Http.HttpClient
$client.DefaultRequestHeaders.Add("X-Api-Token", $token)
$form = New-Object System.Net.Http.MultipartFormDataContent
$stream = [System.IO.File]::OpenRead($zip)
try {
    $form.Add((New-Object System.Net.Http.StringContent($metadata, [Text.Encoding]::UTF8, "application/json")), "metadata")
    $fileContent = New-Object System.Net.Http.StreamContent($stream)
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/zip")
    $form.Add($fileContent, "file", [IO.Path]::GetFileName($zip))
    $response = $client.PostAsync("$api/projects/$($settings.projectId)/upload-file", $form).Result
    $body = $response.Content.ReadAsStringAsync().Result
    if (-not $response.IsSuccessStatusCode) { throw "upload failed: HTTP $([int]$response.StatusCode) $body" }
    Write-Host "`nuploaded: file id $(($body | ConvertFrom-Json).id) (CurseForge reviews it before it goes public)"
} finally {
    $stream.Dispose(); $form.Dispose(); $client.Dispose()
}
