param(
    [string]$Skill,

    [switch]$Exact,

    [switch]$Sources,

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

function Test-SkillMatch {
    param(
        [string]$Value,
        [string]$Query,
        [bool]$Exact
    )

    if ([string]::IsNullOrWhiteSpace($Query)) {
        return $true
    }

    if ($Exact) {
        return $Value -eq $Query
    }

    return $Value -match [regex]::Escape($Query)
}

$repoRoot = Get-RepoRoot
$state = & (Join-Path $PSScriptRoot "Resolve-MHWildsCurrentState.ps1") -ConfigPath $ConfigPath -Json | ConvertFrom-Json
$skills = @($state.BuildContext.Skills | Where-Object {
    Test-SkillMatch -Value $_.Skill -Query $Skill -Exact ([bool]$Exact)
} | Sort-Object Skill)

$result = [pscustomobject]@{
    ActiveProfileId = $state.ActiveProfile.ActiveProfileId
    ActiveCharacterSlotIndex = $state.ActiveProfile.ActiveCharacterSlotIndex
    OverrideExists = $state.OverrideExists
    OverridesApplied = @($state.OverridesApplied)
    Skills = @($skills)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6
    return
}

Write-Output "Active profile: $($result.ActiveProfileId)"
Write-Output "Character slot: $($result.ActiveCharacterSlotIndex)"
Write-Output "Override exists: $($result.OverrideExists)"
Write-Output ""

if ($skills.Count -eq 0) {
    Write-Output "No matching current skills found."
    return
}

if ($Sources) {
    $skills | Format-Table Skill,Level,MaxLevel,OverCap,Sources -AutoSize
}
else {
    $skills | Format-Table Skill,Level,MaxLevel,OverCap -AutoSize
}
