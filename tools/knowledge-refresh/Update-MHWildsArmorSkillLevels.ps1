param(
    [string]$KiranicoArmorSeriesUrl = "https://mhwilds.kiranico.com/data/armor-series",

    [ValidateRange(1, 4)]
    [int]$ThrottleLimit = 1,

    [ValidateRange(0, 5000)]
    [int]$RequestDelayMs = 750,

    [ValidateRange(5, 120)]
    [int]$RequestTimeoutSec = 30
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

function ConvertFrom-HtmlText {
    param([string]$Html)

    if ($null -eq $Html) { return "" }
    $withoutTags = [regex]::Replace($Html, "<[^>]+>", "")
    return ([System.Net.WebUtility]::HtmlDecode($withoutTags) -replace '\s+', ' ').Trim()
}

function Get-ArmorSkillDetailsFromHtml {
    param([string]$Html)

    $rowsByPiece = @{}
    foreach ($rowMatch in [regex]::Matches($Html, '<tr\b[^>]*>.*?</tr>', [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $rowHtml = $rowMatch.Value
        if ($rowHtml -notmatch '/data/skills/') { continue }

        $tds = @([regex]::Matches($rowHtml, '<td\b[^>]*>(.*?)</td>', [System.Text.RegularExpressions.RegexOptions]::Singleline))
        if ($tds.Count -lt 4) { continue }

        $part = ConvertFrom-HtmlText $tds[0].Groups[1].Value
        if ($part -notin @("Head", "Chest", "Arms", "Waist", "Legs")) { continue }

        $pieceName = ConvertFrom-HtmlText $tds[1].Groups[1].Value
        if (-not $pieceName) { continue }

        $skillDetails = [System.Collections.Generic.List[string]]::new()
        foreach ($skillMatch in [regex]::Matches($tds[3].Groups[1].Value, '<a\b[^>]*href="/data/skills/[^"]+"[^>]*>(.*?)</a>', [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
            $skillText = ConvertFrom-HtmlText $skillMatch.Groups[1].Value
            if ($skillText -match '^(.+?)\s+\+(\d+)$') {
                $skillDetails.Add("$($matches[1].Trim()) Lv$($matches[2])")
            }
        }

        if ($skillDetails.Count -gt 0) {
            $rowsByPiece[$pieceName] = $skillDetails -join ";"
        }
    }

    return $rowsByPiece
}

function Add-OrUpdateProperty {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowNull()]
        [string]$Value
    )

    if ($Object.PSObject.Properties[$Name]) {
        $Object.$Name = $Value
    }
    else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

$repoRoot = Get-RepoRoot
$memDir = Join-Path $repoRoot "memory\mh-wilds"
$armorCsvPath = Join-Path $memDir "armor.csv"
$armorNormalizedCsvPath = Join-Path $memDir "armor_normalized.csv"
$cacheDir = Join-Path $memDir ".cache\kiranico-armor-series"
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

$headers = @{
    "User-Agent" = "mh-wilds-ai-expert knowledge refresh (local personal use; polite rate limit)"
}

Write-Host "Fetching Kiranico armor series index..."
$indexCachePath = Join-Path $cacheDir "index.html"
if (Test-Path -LiteralPath $indexCachePath -PathType Leaf) {
    $indexHtml = Get-Content -Raw -LiteralPath $indexCachePath
}
else {
    $indexHtml = (Invoke-WebRequest -Uri $KiranicoArmorSeriesUrl -UseBasicParsing -Headers $headers -TimeoutSec $RequestTimeoutSec).Content
    Set-Content -LiteralPath $indexCachePath -Value $indexHtml -Encoding UTF8
}
$seriesPaths = @(
    [regex]::Matches($indexHtml, 'href="/data/armor-series/([^"#?]+)"') |
        ForEach-Object { "armor-series/" + $_.Groups[1].Value.TrimEnd("/") } |
        Sort-Object -Unique
)

if ($seriesPaths.Count -eq 0) {
    throw "No armor-series links found at $KiranicoArmorSeriesUrl"
}

Write-Host "Fetching $($seriesPaths.Count) Kiranico armor series pages with throttle=$ThrottleLimit and delay=${RequestDelayMs}ms..."
$seriesUrls = @($seriesPaths | ForEach-Object { "https://mhwilds.kiranico.com/data/$_" })

$pageResults = @()
$pageNumber = 0
foreach ($url in $seriesUrls) {
    $pageNumber++
    $slug = ($url -replace '^https://mhwilds\.kiranico\.com/data/armor-series/', '') -replace '[^a-zA-Z0-9._-]', '_'
    $cachePath = Join-Path $cacheDir "$slug.html"
    if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
        $html = Get-Content -Raw -LiteralPath $cachePath
    }
    else {
        Write-Host "[$pageNumber/$($seriesUrls.Count)] Fetching $url"
        if ($RequestDelayMs -gt 0) {
            Start-Sleep -Milliseconds $RequestDelayMs
        }
        try {
            $html = (Invoke-WebRequest -Uri $url -UseBasicParsing -Headers $headers -TimeoutSec $RequestTimeoutSec).Content
            Set-Content -LiteralPath $cachePath -Value $html -Encoding UTF8
        }
        catch {
            Write-Warning "Skipping $url after fetch failure: $($_.Exception.Message)"
            continue
        }
    }

    $pageRows = Get-ArmorSkillDetailsFromHtml $html
    foreach ($pieceName in $pageRows.Keys) {
        $pageResults += [pscustomobject]@{
            PieceName = $pieceName
            SkillDetails = $pageRows[$pieceName]
            SourceUrl = $url
        }
    }
}

$skillDetailsByPiece = @{}
foreach ($row in $pageResults) {
    $skillDetailsByPiece[$row.PieceName] = $row.SkillDetails
}

if ($skillDetailsByPiece.Count -eq 0) {
    throw "No armor skill detail rows were parsed from Kiranico."
}

$rawRows = @(Import-Csv -LiteralPath $armorCsvPath)
$normalizedRows = @(Import-Csv -LiteralPath $armorNormalizedCsvPath)

$rawMatched = 0
foreach ($row in $rawRows) {
    $details = ""
    if ($row.Title -and $skillDetailsByPiece.ContainsKey($row.Title)) {
        $details = $skillDetailsByPiece[$row.Title]
        $rawMatched++
    }
    Add-OrUpdateProperty $row "Skill Details" $details
}

$normalizedMatched = 0
foreach ($row in $normalizedRows) {
    $details = ""
    if ($row.Title -and $skillDetailsByPiece.ContainsKey($row.Title)) {
        $details = $skillDetailsByPiece[$row.Title]
        $normalizedMatched++
    }
    Add-OrUpdateProperty $row "SkillDetails" $details
}

$rawRows | Export-Csv -LiteralPath $armorCsvPath -NoTypeInformation -Encoding UTF8
$normalizedRows | Export-Csv -LiteralPath $armorNormalizedCsvPath -NoTypeInformation -Encoding UTF8

Write-Host "Updated armor.csv Skill Details for $rawMatched/$($rawRows.Count) rows."
Write-Host "Updated armor_normalized.csv SkillDetails for $normalizedMatched/$($normalizedRows.Count) rows."

if ($normalizedMatched -lt $normalizedRows.Count) {
    $missing = @($normalizedRows | Where-Object { -not $_.SkillDetails } | Select-Object -First 20 -ExpandProperty Title)
    Write-Warning "Some local armor rows did not match Kiranico skill details. First missing titles: $($missing -join '; ')"
}
