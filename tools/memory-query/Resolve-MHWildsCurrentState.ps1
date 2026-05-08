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

$repoRoot = Get-RepoRoot
$profile = & (Join-Path $PSScriptRoot "Get-MHWildsActiveSaveProfile.ps1") -ConfigPath $ConfigPath
$buildContext = & (Join-Path $PSScriptRoot "Get-MHWildsBuildContext.ps1") -ConfigPath $ConfigPath -Json | ConvertFrom-Json

$overrideExists = $buildContext.OverridePath -and (Test-Path -LiteralPath $buildContext.OverridePath -PathType Leaf)
$activeSummaryCsvs = @()
if ($profile.SummaryDirExists) {
    $activeSummaryCsvs = @(Get-ChildItem -LiteralPath $profile.SummaryDir -File -Filter "*.csv" | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{
            Name = $_.Name
            FullName = $_.FullName
            LastWriteTime = $_.LastWriteTime
        }
    })
}

$state = [pscustomobject]@{
    ResolvedAt = (Get-Date).ToString("o")
    SourceOfTruth = "Active copied-save summary CSVs plus ignored private build overrides."
    ActiveProfile = $profile
    OverridePath = $buildContext.OverridePath
    OverrideExists = [bool]$overrideExists
    OverridesApplied = @($buildContext.OverridesApplied)
    BuildContext = $buildContext
    ActiveSummaryCsvs = @($activeSummaryCsvs)
    CurrentStateSteps = @(
        "Read active profile from memory/private-save/save-inspection.config.json.",
        "Read summary CSVs from the active profile summary_dir.",
        "Apply ignored private build overrides from memory/private-save/overrides/<profile_id>.json when present.",
        "Return the resolved current state without editing generated summaries or live saves."
    )
}

if ($Json) {
    $state | ConvertTo-Json -Depth 10
    return
}

Write-Output "Resolved current state at $($state.ResolvedAt)"
Write-Output "Active profile: $($profile.ActiveProfileId)"
Write-Output "Character slot: $($profile.ActiveCharacterSlotIndex)"
Write-Output "Summary CSVs: $($profile.SummaryCsvCount)"
Write-Output "Override exists: $($state.OverrideExists)"
if ($state.OverridesApplied.Count -gt 0) {
    Write-Output ""
    Write-Output "Overrides applied"
    $state.OverridesApplied | Format-Table Applied,Detail -AutoSize
}
Write-Output ""
Write-Output "Loadout"
$buildContext.Loadout | Format-Table Slot,Kind,Type,Name,DecorationNames -AutoSize
Write-Output ""
Write-Output "Skill totals"
$buildContext.Skills | Sort-Object Skill | Format-Table Skill,Level,MaxLevel,OverCap -AutoSize
