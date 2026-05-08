param(
    [Parameter(Mandatory = $true)]
    [string]$SaveCopyPath,

    [Parameter(Mandatory = $true)]
    [string]$SteamId64,

    [Parameter(Mandatory = $true)]
    [string]$OutDir
)

$ErrorActionPreference = "Stop"

function Test-IsRepoSubPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')

    return $fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($fullRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($fullRoot + [System.IO.Path]::AltDirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$repoRoot = $repoRoot.Path
$submodule = Join-Path $repoRoot "tools\ree-save-editor"
$helperSource = Join-Path $repoRoot "tools\save-inspection\mhwilds_interpret_save.rs"
$helperDestination = Join-Path $submodule "src\bin\mhwilds_interpret_save.rs"
$saveCopy = Resolve-Path $SaveCopyPath
$saveCopy = $saveCopy.Path
if ([System.IO.Path]::IsPathRooted($OutDir)) {
    $outputDir = [System.IO.Path]::GetFullPath($OutDir)
}
else {
    $outputDir = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutDir))
}

if (-not (Test-IsRepoSubPath -Path $saveCopy -Root $repoRoot)) {
    throw "SaveCopyPath must be inside this repository. Copy the live save into memory\private-save\raw first."
}

if ($saveCopy -match "\\2246340\\|\\Steam\\userdata\\|\\win64_save\\|data\d+Slot\.bin$|data\d+-\d+\.bin$") {
    throw "Refusing to operate on a path that looks like a live Steam/MH Wilds save path."
}

if (-not (Test-IsRepoSubPath -Path $outputDir -Root $repoRoot)) {
    throw "OutDir must be inside this repository."
}

if (Test-Path $helperDestination) {
    $existing = Get-Content -Raw -LiteralPath $helperDestination
    $expected = Get-Content -Raw -LiteralPath $helperSource
    if ($existing -ne $expected) {
        throw "Temporary helper destination already exists and differs: $helperDestination"
    }
    Remove-Item -LiteralPath $helperDestination
}

$env:CARGO_HOME = Join-Path $repoRoot ".cargo-home"
$env:CARGO_TARGET_DIR = Join-Path $repoRoot ".cargo-target"

try {
    git -C $submodule submodule update --init --recursive
    git -C $submodule pull --ff-only

    New-Item -ItemType Directory -Force -Path (Split-Path $helperDestination) | Out-Null
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    Remove-Item -LiteralPath (Join-Path $outputDir "interpreted-summary.json") -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $outputDir -File -Filter "slot*-equip-box.json" -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem -LiteralPath $outputDir -File -Filter "slot*-equip-current.json" -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem -LiteralPath $outputDir -File -Filter "slot*-item-box.json" -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem -LiteralPath $outputDir -File -Filter "slot*-mission.json" -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem -LiteralPath $outputDir -File -Filter "slot*-endemic-captures.json" -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem -LiteralPath $outputDir -File -Filter "slot*-fish-captures.json" -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem -LiteralPath $outputDir -File -Filter "slot*-monster-report.json" -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem -LiteralPath $outputDir -File -Filter "slot*-story.json" -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem -LiteralPath $outputDir -File -Filter "slot*-quest-record.json" -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem -LiteralPath $outputDir -File -Filter "slot*-delivery-bounty.json" -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem -LiteralPath $outputDir -File -Filter "slot*-camp.json" -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem -LiteralPath $outputDir -File -Filter "slot*-hunter-profile.json" -ErrorAction SilentlyContinue | Remove-Item -Force
    Copy-Item -LiteralPath $helperSource -Destination $helperDestination -Force

    Push-Location $submodule
    try {
        cargo run --locked --bin mhwilds_interpret_save -- `
            $saveCopy `
            $SteamId64 `
            "assets\mhwilds\rszmhwilds.json" `
            "assets\mhwilds\enumsmhwilds.json" `
            $outputDir
    }
    finally {
        Pop-Location
    }
}
finally {
    if (Test-Path $helperDestination) {
        $existing = Get-Content -Raw -LiteralPath $helperDestination
        $expected = Get-Content -Raw -LiteralPath $helperSource
        if ($existing -eq $expected) {
            Remove-Item -LiteralPath $helperDestination
        }
    }
}
