param(
    [string]$ConfigPath = "memory/private-save/save-inspection.config.json",
    [switch]$AllWeapons
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

$repoRoot = Get-RepoRoot
$resolvedConfig = if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath
}
else {
    Join-Path $repoRoot $ConfigPath
}

if (-not (Test-Path -LiteralPath $resolvedConfig -PathType Leaf)) {
    throw "No private save config found at $resolvedConfig"
}

$config = Get-Content -Raw -LiteralPath $resolvedConfig | ConvertFrom-Json
$activeProfile = @($config.profiles | Where-Object profile_id -eq $config.active_profile_id | Select-Object -First 1)
if (-not $activeProfile) {
    throw "Active profile '$($config.active_profile_id)' was not found in $resolvedConfig"
}

$summaryDir = if ([System.IO.Path]::IsPathRooted($activeProfile.summary_dir)) {
    $activeProfile.summary_dir
}
else {
    Join-Path $repoRoot $activeProfile.summary_dir
}

$slotIndex = [int]$activeProfile.active_character_slot_index
$equipPath = Join-Path $summaryDir "slot$slotIndex-equip-summary.csv"
if (-not (Test-Path -LiteralPath $equipPath -PathType Leaf)) {
    throw "No equipment summary found at $equipPath"
}

$rows = @(Import-Csv -LiteralPath $equipPath | Where-Object { $_.kind -eq "weapon" })
if (-not $AllWeapons) {
    $rows = @($rows | Where-Object {
        ($_.bonus_by_creating -and [int64]$_.bonus_by_creating -ne 0) -or
        ($_.bonus_by_grinding -and [uint64]$_.bonus_by_grinding -ne 0) -or
        $_.artian_performance_name
    })
}

$rows | Select-Object `
    index,
    type,
    enum,
    name,
    artian_performance_name,
    artian_creation_skill_name,
    artian_creation_bonus_names,
    artian_grinding_bonus_names,
    grinding_num,
    decoration_names,
    bonus_by_creating,
    bonus_by_grinding
