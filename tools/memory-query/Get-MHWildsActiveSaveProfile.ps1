param(
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

$dumpDir = if ([System.IO.Path]::IsPathRooted($activeProfile.dump_dir)) {
    $activeProfile.dump_dir
}
else {
    Join-Path $repoRoot $activeProfile.dump_dir
}

$saveCopyPath = if ([System.IO.Path]::IsPathRooted($activeProfile.save_copy_path)) {
    $activeProfile.save_copy_path
}
else {
    Join-Path $repoRoot $activeProfile.save_copy_path
}

$csvFiles = @()
if (Test-Path -LiteralPath $summaryDir -PathType Container) {
    $csvFiles = @(Get-ChildItem -LiteralPath $summaryDir -File -Filter "*.csv" | Sort-Object Name)
}

[pscustomobject]@{
    ActiveProfileId = $activeProfile.profile_id
    Description = $activeProfile.description
    CopyId = $activeProfile.copy_id
    SteamId64 = $activeProfile.steam_id64
    ActiveCharacterSlotIndex = $activeProfile.active_character_slot_index
    SaveCopyPath = $saveCopyPath
    SaveCopyExists = Test-Path -LiteralPath $saveCopyPath -PathType Leaf
    DumpDir = $dumpDir
    DumpDirExists = Test-Path -LiteralPath $dumpDir -PathType Container
    SummaryDir = $summaryDir
    SummaryDirExists = Test-Path -LiteralPath $summaryDir -PathType Container
    SummaryCsvCount = $csvFiles.Count
    SummaryCsvFiles = ($csvFiles.Name -join "; ")
}
