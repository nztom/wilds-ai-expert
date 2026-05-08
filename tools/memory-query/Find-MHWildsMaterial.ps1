param(
    [Parameter(Mandatory = $true)]
    [string]$Name
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
$materialsCsv = Join-Path $repoRoot "memory/mh-wilds/equipment_materials_normalized.csv"

if (-not (Test-Path -LiteralPath $materialsCsv -PathType Leaf)) {
    throw "Missing material data: $materialsCsv"
}

$escaped = [regex]::Escape($Name)
Import-Csv -LiteralPath $materialsCsv |
    Where-Object {
        $_.Title -match $escaped -or
        $_.WhereToFind -match $escaped -or
        $_.RewardedFrom -match $escaped -or
        $_.UsedToCraft -match $escaped -or
        $_.OtherInfo -match $escaped
    } |
    Select-Object Title,WhereToFind,RewardedFrom,UsedToCraft,Rarity,CarryMax,SellPrice |
    Format-List
