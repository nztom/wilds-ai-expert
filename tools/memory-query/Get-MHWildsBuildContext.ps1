param(
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

function Split-List {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    return @($Value -split ";" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Join-List {
    param([object[]]$Values)

    return (@($Values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ";")
}

function Add-SkillLevel {
    param(
        [hashtable]$Totals,
        [string]$SkillName,
        [int]$Level,
        [string]$Source
    )

    if ([string]::IsNullOrWhiteSpace($SkillName) -or $Level -le 0) {
        return
    }

    if (-not $Totals.ContainsKey($SkillName)) {
        $Totals[$SkillName] = [pscustomobject]@{
            Skill = $SkillName
            Level = 0
            Sources = [System.Collections.Generic.List[string]]::new()
        }
    }

    $Totals[$SkillName].Level += $Level
    if ($Source) {
        $Totals[$SkillName].Sources.Add($Source)
    }
}

function Add-SkillDetails {
    param(
        [hashtable]$Totals,
        [string]$Details,
        [string]$Source
    )

    foreach ($detail in (Split-List $Details)) {
        if ($detail -match '^(.+?)\s+Lv(\d+)$') {
            Add-SkillLevel -Totals $Totals -SkillName $matches[1].Trim() -Level ([int]$matches[2]) -Source $Source
        }
    }
}

function Get-DecoLookup {
    param([string]$RepoRoot)

    $lookup = @{}
    foreach ($relativePath in @(
        "memory/mh-wilds/decorations_armor_normalized.csv",
        "memory/mh-wilds/decorations_weapon_normalized.csv"
    )) {
        $path = Join-Path $RepoRoot $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }

        foreach ($row in (Import-Csv -LiteralPath $path)) {
            if (-not $lookup.ContainsKey($row.Title)) {
                $lookup[$row.Title] = [System.Collections.Generic.List[object]]::new()
            }
            $lookup[$row.Title].Add($row)
        }
    }

    return $lookup
}

function Get-DecoSkillDetails {
    param(
        [string]$DecorationName,
        [hashtable]$DecoLookup
    )

    if ([string]::IsNullOrWhiteSpace($DecorationName) -or -not $DecoLookup.ContainsKey($DecorationName)) {
        return ""
    }

    $details = foreach ($row in $DecoLookup[$DecorationName]) {
        if ($row.Skill) {
            "$($row.Skill) Lv1"
        }
    }

    return Join-List $details
}

function Update-DecorationFields {
    param(
        [object]$Row,
        [hashtable]$DecoLookup
    )

    $decorations = Split-List $Row.decoration_names
    $details = foreach ($decoration in $decorations) {
        Get-DecoSkillDetails -DecorationName $decoration -DecoLookup $DecoLookup
    }

    $Row.decoration_skill_details = Join-List $details
    $skillNames = foreach ($detail in (Split-List $Row.decoration_skill_details)) {
        if ($detail -match '^(.+?)\s+Lv\d+$') {
            $matches[1].Trim()
        }
    }
    $Row.decoration_skills = Join-List $skillNames
}

function Apply-Overrides {
    param(
        [object[]]$Rows,
        [object[]]$Overrides,
        [hashtable]$DecoLookup
    )

    $applied = [System.Collections.Generic.List[object]]::new()
    foreach ($override in $Overrides) {
        if ($override.action -ne "replace-decoration") {
            continue
        }

        $targetRows = @($Rows | Where-Object {
            (-not $override.equipment_slot -or $_.slot -eq $override.equipment_slot) -and
            ((Split-List $_.decoration_names) -contains $override.from_decoration)
        })

        $target = $targetRows | Select-Object -First 1
        if (-not $target) {
            $applied.Add([pscustomobject]@{
                Applied = $false
                Action = $override.action
                Detail = "Could not find '$($override.from_decoration)' on slot '$($override.equipment_slot)'."
            })
            continue
        }

        $decorations = [System.Collections.Generic.List[string]]::new()
        foreach ($decoration in (Split-List $target.decoration_names)) {
            $decorations.Add($decoration)
        }

        $index = $decorations.IndexOf($override.from_decoration)
        if ($index -lt 0) {
            continue
        }

        $decorations[$index] = $override.to_decoration
        $target.decoration_names = Join-List $decorations
        Update-DecorationFields -Row $target -DecoLookup $DecoLookup

        $applied.Add([pscustomobject]@{
            Applied = $true
            Action = $override.action
            Detail = "$($target.slot): $($override.from_decoration) -> $($override.to_decoration)"
        })
    }

    return @($applied)
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
$equipPath = Join-Path $summaryDir "slot$slotIndex-equip-current-summary.csv"
$skillsPath = Join-Path $summaryDir "slot$slotIndex-skills-summary.csv"
$ownedDecosPath = Join-Path $summaryDir "slot$slotIndex-decorations-summary.csv"

foreach ($required in @($equipPath, $skillsPath, $ownedDecosPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing summary file: $required"
    }
}

$rows = @(Import-Csv -LiteralPath $equipPath)
$activeRows = @($rows | Where-Object { $_.slot -in @("weapon", "head", "chest", "arms", "waist", "legs", "charm") })
$secondaryWeapons = @($rows | Where-Object { $_.slot -like "slot_*" -and $_.kind -eq "weapon" })
$ownedDecorations = @(Import-Csv -LiteralPath $ownedDecosPath)
$decoLookup = Get-DecoLookup -RepoRoot $repoRoot

$overrideDir = Join-Path $repoRoot "memory/private-save/overrides"
$overridePath = Join-Path $overrideDir "$($profile.profile_id).json"
$overrides = @()
if (Test-Path -LiteralPath $overridePath -PathType Leaf) {
    $overrideDoc = Get-Content -Raw -LiteralPath $overridePath | ConvertFrom-Json
    $overrides = @($overrideDoc.overrides)
}

$appliedOverrides = Apply-Overrides -Rows $activeRows -Overrides $overrides -DecoLookup $decoLookup

$skillTotals = @{}
foreach ($row in $activeRows) {
    $label = if ($row.name) { "$($row.slot): $($row.name)" } else { $row.slot }
    Add-SkillDetails -Totals $skillTotals -Details $row.native_skill_details -Source "$label native"
    Add-SkillDetails -Totals $skillTotals -Details $row.decoration_skill_details -Source "$label decorations"
}

$maxLevels = @{}
$overCapEligible = @{}
$skillsCsv = Join-Path $repoRoot "memory/mh-wilds/skills_normalized.csv"
if (Test-Path -LiteralPath $skillsCsv -PathType Leaf) {
    foreach ($skill in (Import-Csv -LiteralPath $skillsCsv)) {
        if ($skill.Title -and $skill.MaxLevel) {
            $maxLevels[$skill.Title] = [int]$skill.MaxLevel
        }
        elseif ($skill.Skill -and $skill.MaxLevel) {
            $maxLevels[$skill.Skill] = [int]$skill.MaxLevel
        }
    }
}

$skillIndexCsv = Join-Path $repoRoot "memory/mh-wilds/skill_index.csv"
if (Test-Path -LiteralPath $skillIndexCsv -PathType Leaf) {
    foreach ($skill in (Import-Csv -LiteralPath $skillIndexCsv)) {
        $hasDecoration = $skill.SlotClass -and $skill.SlotClass -ne "no decoration found in scraped data"
        $hasTalisman = $skill.TalismansCount -and ([int]$skill.TalismansCount) -gt 0
        $overCapEligible[$skill.Skill] = [bool]($hasDecoration -or $hasTalisman)
    }
}

$skillRows = foreach ($entry in ($skillTotals.Values | Sort-Object Skill)) {
    $max = if ($maxLevels.ContainsKey($entry.Skill)) { $maxLevels[$entry.Skill] } else { $null }
    $eligible = $overCapEligible.ContainsKey($entry.Skill) -and $overCapEligible[$entry.Skill]
    [pscustomobject]@{
        Skill = $entry.Skill
        Level = $entry.Level
        MaxLevel = $max
        OverCap = ($eligible -and $max -and $entry.Level -gt $max)
        Sources = ($entry.Sources -join "; ")
    }
}

$loadoutRows = foreach ($row in $activeRows) {
    $nameResolved = -not [string]::IsNullOrWhiteSpace($row.name)
    [pscustomobject]@{
        Slot = $row.slot
        Kind = $row.kind
        Type = $row.type
        Name = if ($row.name) { $row.name } else { $row.enum }
        NameResolved = $nameResolved
        NativeSkillDetails = $row.native_skill_details
        DecorationNames = $row.decoration_names
        DecorationSkillDetails = $row.decoration_skill_details
    }
}

$warnings = @(
    foreach ($row in $loadoutRows) {
        if ($row.Kind -eq "weapon" -and -not $row.NameResolved) {
            "Weapon display name is unresolved for $($row.Slot) ($($row.Type) $($row.Name)); this is expected for some weapon enums. Use type, enum, decorations, skills, and reinforcement fields instead of trying to resolve the name."
        }
    }
)

$ownedUsefulDecorations = foreach ($deco in ($ownedDecorations | Where-Object { [int]($_.quantity) -gt 0 } | Sort-Object decoration_name)) {
    [pscustomobject]@{
        Decoration = $deco.decoration_name
        Type = $deco.decoration_type
        SlotLevel = $deco.slot_level
        Quantity = [int]$deco.quantity
        SkillDetails = $deco.skill_details
    }
}

$context = [pscustomobject]@{
    ActiveProfileId = $profile.profile_id
    CopyId = $profile.copy_id
    ActiveCharacterSlotIndex = $slotIndex
    SummaryDir = $summaryDir
    OverridePath = $overridePath
    OverridesApplied = @($appliedOverrides)
    Warnings = @($warnings)
    Loadout = @($loadoutRows)
    Skills = @($skillRows)
    SecondaryWeapons = @($secondaryWeapons | Select-Object slot,type,name,decoration_names,decoration_skill_details)
    OwnedDecorations = @($ownedUsefulDecorations)
}

if ($Json) {
    $context | ConvertTo-Json -Depth 8
    return
}

Write-Output "Active profile: $($context.ActiveProfileId)"
Write-Output "Character slot: $slotIndex"
if ($context.Warnings.Count -gt 0) {
    Write-Output ""
    Write-Output "Warnings"
    $context.Warnings | ForEach-Object { Write-Output "- $_" }
}
Write-Output ""
Write-Output "Loadout"
$context.Loadout | Format-Table Slot,Kind,Type,Name,DecorationNames -AutoSize
Write-Output ""
Write-Output "Skill totals"
$context.Skills | Sort-Object Skill | Format-Table Skill,Level,MaxLevel,OverCap -AutoSize
if ($context.OverridesApplied.Count -gt 0) {
    Write-Output ""
    Write-Output "Private overrides"
    $context.OverridesApplied | Format-Table Applied,Detail -AutoSize
}
