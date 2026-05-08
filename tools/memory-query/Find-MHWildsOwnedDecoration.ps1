param(
    [string]$Name,

    [string]$Skill,

    [switch]$Exact,

    [string]$ConfigPath = "memory/private-save/save-inspection.config.json",

    [switch]$Json
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

if ([string]::IsNullOrWhiteSpace($Name) -and [string]::IsNullOrWhiteSpace($Skill)) {
    throw "Provide -Name, -Skill, or both."
}

$repoRoot = Get-RepoRoot
$resolvedConfig = Resolve-RepoPath -Path $ConfigPath -RepoRoot $repoRoot
if (-not (Test-Path -LiteralPath $resolvedConfig -PathType Leaf)) {
    throw "No private save config found at $resolvedConfig"
}

$config = Get-Content -Raw -LiteralPath $resolvedConfig | ConvertFrom-Json
$profile = @($config.profiles | Where-Object profile_id -eq $config.active_profile_id | Select-Object -First 1)
if (-not $profile) {
    throw "Active profile '$($config.active_profile_id)' was not found."
}

$summaryDir = Resolve-RepoPath -Path $profile.summary_dir -RepoRoot $repoRoot
$slotIndex = [int]$profile.active_character_slot_index
$decorationsPath = Join-Path $summaryDir "slot$slotIndex-decorations-summary.csv"
$decorationSkillsPath = Join-Path $summaryDir "slot$slotIndex-decoration-skills-summary.csv"

if (-not (Test-Path -LiteralPath $decorationsPath -PathType Leaf)) {
    throw "Missing owned decorations summary: $decorationsPath"
}

$decorations = @(Import-Csv -LiteralPath $decorationsPath)
$matchingDecorations = @($decorations | Where-Object {
    $quantity = if ($_.quantity) { [int]$_.quantity } else { 0 }
    $nameMatches = $true
    $skillMatches = $true

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        if ($Exact) {
            $nameMatches = $_.decoration_name -eq $Name
        }
        else {
            $nameMatches = $_.decoration_name -match [regex]::Escape($Name)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Skill)) {
        $escapedSkill = [regex]::Escape($Skill)
        $skillMatches = $_.skill_details -match $escapedSkill -or $_.skills -match $escapedSkill
    }

    $quantity -gt 0 -and
    $nameMatches -and
    $skillMatches
})

$skillRollup = @()
if ($Skill -and (Test-Path -LiteralPath $decorationSkillsPath -PathType Leaf)) {
    $skillRollup = @(Import-Csv -LiteralPath $decorationSkillsPath | Where-Object {
        if ($Exact) {
            $_.skill_name -eq $Skill
        }
        else {
            $_.skill_name -match [regex]::Escape($Skill)
        }
    })
}

$result = [pscustomobject]@{
    ActiveProfileId = $profile.profile_id
    ActiveCharacterSlotIndex = $slotIndex
    QueryName = $Name
    QuerySkill = $Skill
    Decorations = @($matchingDecorations | Sort-Object decoration_type, slot_level, decoration_name | Select-Object `
        @{ Name = "Decoration"; Expression = { $_.decoration_name } },
        @{ Name = "Type"; Expression = { $_.decoration_type } },
        @{ Name = "SlotLevel"; Expression = { $_.slot_level } },
        @{ Name = "Quantity"; Expression = { [int]$_.quantity } },
        @{ Name = "SkillDetails"; Expression = { $_.skill_details } },
        @{ Name = "Rarity"; Expression = { $_.rarity } })
    SkillRollup = @($skillRollup | Select-Object `
        @{ Name = "Skill"; Expression = { $_.skill_name } },
        @{ Name = "DecorationQuantity"; Expression = { $_.decoration_quantity } },
        @{ Name = "KnownTotalLevels"; Expression = { $_.known_total_levels } },
        @{ Name = "HasUnknownLevel"; Expression = { $_.has_unknown_level } },
        @{ Name = "Decorations"; Expression = { $_.decorations } })
}

if ($Json) {
    $result | ConvertTo-Json -Depth 5
    return
}

Write-Output "Active profile: $($result.ActiveProfileId)"
Write-Output "Character slot: $slotIndex"
if ($Skill -and $result.SkillRollup.Count -gt 0) {
    Write-Output ""
    Write-Output "Skill rollup"
    $result.SkillRollup | Format-Table Skill,DecorationQuantity,KnownTotalLevels,HasUnknownLevel,Decorations -AutoSize
}
Write-Output ""
Write-Output "Owned decorations"
if ($result.Decorations.Count -gt 0) {
    $result.Decorations | Format-Table Decoration,Type,SlotLevel,Quantity,SkillDetails,Rarity -AutoSize
}
else {
    Write-Output "No matching owned decorations found."
}
