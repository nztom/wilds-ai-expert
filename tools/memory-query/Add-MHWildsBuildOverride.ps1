param(
    [ValidateSet("ReplaceDecoration")]
    [string]$Action = "ReplaceDecoration",

    [Parameter(Mandatory = $true)]
    [string]$FromDecoration,

    [Parameter(Mandatory = $true)]
    [string]$ToDecoration,

    [string]$EquipmentSlot,

    [string]$Note,

    [string]$ConfigPath = "memory/private-save/save-inspection.config.json"
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    $dir = $PSScriptRoot
    while ($dir) {
        if (Test-Path -LiteralPath (Join-Path $dir ".git")) {
            return $dir
        }
        $parent = Split-Path -Parent $dir
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    throw "Could not locate repository root from $PSScriptRoot"
}

function Resolve-RepoPath {
    param(
        [string]$Path,
        [string]$RepoRoot
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $RepoRoot $Path
}

function Test-DecorationExists {
    param(
        [string]$DecorationName,
        [string]$RepoRoot
    )

    foreach ($relativePath in @(
        "memory/mh-wilds/decorations_armor_normalized.csv",
        "memory/mh-wilds/decorations_weapon_normalized.csv"
    )) {
        $path = Join-Path $RepoRoot $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }

        if (Import-Csv -LiteralPath $path | Where-Object Title -eq $DecorationName | Select-Object -First 1) {
            return $true
        }
    }

    return $false
}

$repoRoot = Get-RepoRoot
$resolvedConfig = Resolve-RepoPath -Path $ConfigPath -RepoRoot $repoRoot
if (-not (Test-Path -LiteralPath $resolvedConfig -PathType Leaf)) {
    throw "No private save config found at $resolvedConfig"
}

if (-not (Test-DecorationExists -DecorationName $ToDecoration -RepoRoot $repoRoot)) {
    throw "Unknown target decoration '$ToDecoration'. Check the decoration name in normalized CSVs."
}

$config = Get-Content -Raw -LiteralPath $resolvedConfig | ConvertFrom-Json
$profile = @($config.profiles | Where-Object profile_id -eq $config.active_profile_id | Select-Object -First 1)
if (-not $profile) {
    throw "Active profile '$($config.active_profile_id)' was not found."
}

$overrideDir = Join-Path $repoRoot "memory/private-save/overrides"
New-Item -ItemType Directory -Force -Path $overrideDir | Out-Null
$overridePath = Join-Path $overrideDir "$($profile.profile_id).json"

if (Test-Path -LiteralPath $overridePath -PathType Leaf) {
    $doc = Get-Content -Raw -LiteralPath $overridePath | ConvertFrom-Json
}
else {
    $doc = [pscustomobject]@{
        profile_id = $profile.profile_id
        copy_id = $profile.copy_id
        active_character_slot_index = $profile.active_character_slot_index
        updated_at = $null
        overrides = @()
    }
}

$existing = @($doc.overrides)
$newOverride = [pscustomobject]@{
    action = "replace-decoration"
    equipment_slot = $EquipmentSlot
    from_decoration = $FromDecoration
    to_decoration = $ToDecoration
    note = $Note
    created_at = (Get-Date).ToString("o")
}

$doc.overrides = @($existing + $newOverride)
$doc.updated_at = (Get-Date).ToString("o")

$doc | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $overridePath -Encoding UTF8

[pscustomobject]@{
    OverridePath = $overridePath
    ProfileId = $profile.profile_id
    Action = $newOverride.action
    EquipmentSlot = $EquipmentSlot
    FromDecoration = $FromDecoration
    ToDecoration = $ToDecoration
    Note = $Note
}
