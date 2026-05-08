param(
    [Parameter(Mandatory = $true)]
    [string]$Skill,

    [switch]$Contains
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
$skillIndex = Join-Path $repoRoot "memory/mh-wilds/skill_index.csv"

if (-not (Test-Path -LiteralPath $skillIndex -PathType Leaf)) {
    throw "Missing skill index: $skillIndex"
}

$rows = Import-Csv -LiteralPath $skillIndex
if ($Contains) {
    $escaped = [regex]::Escape($Skill)
    $rows | Where-Object { $_.Skill -match $escaped } |
        Sort-Object Skill |
        Format-Table Skill,MaxLevel,SlotClass,ArmorDecorationOptions,WeaponDecorationOptions,ArmorPiecesCount,TalismansCount -AutoSize
}
else {
    $rows | Where-Object { $_.Skill -eq $Skill } | Format-List
}
