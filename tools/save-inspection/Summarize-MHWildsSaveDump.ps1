param(
    [Parameter(Mandatory = $true)]
    [string]$DumpDir,

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

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        $Value
    )

    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-CsvFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [object[]]$Rows,

        [string[]]$Columns
    )

    if ($null -eq $Rows) {
        $Rows = @()
    }

    if ($Rows.Count -eq 0) {
        if ($Columns -and $Columns.Count -gt 0) {
            $header = @($Columns | ForEach-Object { '"' + ($_ -replace '"', '""') + '"' }) -join ","
            Set-Content -LiteralPath $Path -Value $header -Encoding UTF8
        }
        else {
            Set-Content -LiteralPath $Path -Value "" -Encoding UTF8
        }
        return
    }

    $Rows | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
}

function Clear-BuildOverridesForCopy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$CopyId,

        [Parameter(Mandatory = $true)]
        [datetime]$DumpFreshnessTime
    )

    $overrideDir = Join-Path $RepoRoot "memory\private-save\overrides"
    if (-not (Test-Path -LiteralPath $overrideDir -PathType Container)) {
        return @()
    }

    $profileIds = [System.Collections.Generic.List[string]]::new()
    $configPath = Join-Path $RepoRoot "memory\private-save\save-inspection.config.json"
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
        foreach ($profile in @($config.profiles | Where-Object copy_id -eq $CopyId)) {
            if ($profile.profile_id) {
                $profileIds.Add([string]$profile.profile_id)
            }
        }
    }

    if ($profileIds.Count -eq 0) {
        $profileIds.Add($CopyId)
    }

    $removed = [System.Collections.Generic.List[string]]::new()
    foreach ($profileId in $profileIds) {
        foreach ($file in @(Get-ChildItem -LiteralPath $overrideDir -File -Filter "$profileId*.json" -ErrorAction SilentlyContinue)) {
            $override = Read-JsonFile $file.FullName
            if ($null -eq $override) {
                continue
            }

            $timestampText = [string]$override.updated_at
            if ([string]::IsNullOrWhiteSpace($timestampText)) {
                $latestOverrideTime = @($override.overrides | ForEach-Object { $_.created_at } | Sort-Object -Descending | Select-Object -First 1)
                $timestampText = if ($latestOverrideTime.Count -gt 0) { [string]$latestOverrideTime[0] } else { "" }
            }

            $overrideTime = [datetime]::MinValue
            if ([string]::IsNullOrWhiteSpace($timestampText) -or -not [datetime]::TryParse($timestampText, [ref]$overrideTime)) {
                Write-Host "Kept private build override file with unknown timestamp: $($file.Name)"
                continue
            }

            if ($overrideTime -gt $DumpFreshnessTime) {
                Write-Host "Kept private build override newer than dump: $($file.Name)"
                continue
            }

            Remove-Item -LiteralPath $file.FullName -Force
            $removed.Add($file.Name)
        }
    }

    return @($removed)
}

function Get-ObjectPropertyValue {
    param(
        $Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-EnglishMessage {
    param($Message)

    $content = Get-ObjectPropertyValue $Message "content"
    if ($null -eq $Message -or -not $content -or $content.Count -lt 2) {
        return $null
    }

    $text = [string]$content[1]
    if ($text.Length -eq 0 -or $text.StartsWith("<PLATMSG ")) {
        return $null
    }

    return ($text -replace "`r`n", " " -replace "`n", " ").Trim()
}

function Resolve-MessageRefs {
    param(
        [string]$Text,
        $MessageByName,
        [int]$Depth = 0
    )

    if ([string]::IsNullOrWhiteSpace($Text) -or $null -eq $MessageByName -or $Depth -ge 5) {
        return $Text
    }

    return [regex]::Replace($Text, '<REF\s+([^>]+)>', {
        param($Match)

        $refName = $Match.Groups[1].Value
        $message = Get-ObjectPropertyValue $MessageByName $refName
        $english = Get-EnglishMessage $message
        if ([string]::IsNullOrWhiteSpace($english)) {
            return $Match.Value
        }

        return Resolve-MessageRefs -Text $english -MessageByName $MessageByName -Depth ($Depth + 1)
    })
}

function Initialize-NameResolver {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $assetDir = Join-Path $RepoRoot "tools\ree-save-editor\assets\mhwilds"
    $enumPath = Join-Path $assetDir "enumsmhwilds.json"
    $mappingPath = Join-Path $assetDir "enums_mappings_mhwilds.json"
    $messagePath = Join-Path $assetDir "combined_msgs.json"

    if (-not (Test-Path -LiteralPath $enumPath) -or
        -not (Test-Path -LiteralPath $mappingPath) -or
        -not (Test-Path -LiteralPath $messagePath)) {
        Write-Warning "Name-resolution assets were not found; CSVs will include internal IDs only."
        return $null
    }

    Write-Host "Loading Wilds name-resolution assets..."
    $enums = Get-Content -Raw -LiteralPath $enumPath | ConvertFrom-Json -AsHashTable -Depth 20
    $mappings = Get-Content -Raw -LiteralPath $mappingPath | ConvertFrom-Json -AsHashTable -Depth 20
    $messages = Get-Content -Raw -LiteralPath $messagePath | ConvertFrom-Json -AsHashTable -Depth 20

    $itemFixedEnum = Get-ObjectPropertyValue $enums "app.ItemDef.ID_Fixed"
    $enemyFixedEnum = Get-ObjectPropertyValue $enums "app.EnemyDef.ID_Fixed"
    $itemMessageMap = Get-ObjectPropertyValue $mappings "app.ItemDef.ID_Fixed"
    $messageMap = Get-ObjectPropertyValue $messages "msgs"

    $enemyNames = @{}
    $messageByName = @{}
    foreach ($message in $messageMap.Values) {
        $messageName = Get-ObjectPropertyValue $message "name"
        if ($messageName) {
            $messageByName[$messageName] = $message
        }
        if ($messageName -and $messageName.StartsWith("EnemyText_NAME_")) {
            $enemyKey = $messageName.Substring("EnemyText_NAME_".Length)
            $english = Get-EnglishMessage $message
            if ($english) {
                $enemyNames[$enemyKey] = $english
            }
        }
    }

    # Build hash-suffix -> English name for decorations.
    # Messages use names like "Accessory_ACC_<hash>" where negative hashes are encoded as "m<abs>".
    $accessoryHashToName = @{}
    foreach ($message in $messageMap.Values) {
        $messageName = Get-ObjectPropertyValue $message "name"
        if ($messageName -and $messageName.StartsWith("Accessory_ACC_")) {
            $hashSuffix = $messageName.Substring("Accessory_ACC_".Length)
            $english = Get-EnglishMessage $message
            if ($english) {
                $accessoryHashToName[$hashSuffix] = $english
            }
        }
    }

    # Build hash-suffix -> English name for bowgun customization mods.
    # Messages use names like "BowgunCustomize_NAME<hash>" where negative hashes are encoded as "m<abs>".
    $bowgunCustomizeHashToName = @{}
    foreach ($message in $messageMap.Values) {
        $messageName = Get-ObjectPropertyValue $message "name"
        if ($messageName -and $messageName.StartsWith("BowgunCustomize_NAME")) {
            $hashSuffix = $messageName.Substring("BowgunCustomize_NAME".Length)
            $english = Get-EnglishMessage $message
            if ($english) {
                $bowgunCustomizeHashToName[$hashSuffix] = $english
            }
        }
    }

    # Mission titles are stored directly as message names like "Mission101001_100".
    # They are not exposed through enums_mappings_mhwilds.json, so build a small
    # enum key -> display title table from the message name itself.
    $missionNames = @{}
    foreach ($message in $messageMap.Values) {
        $messageName = Get-ObjectPropertyValue $message "name"
        if ($messageName -and $messageName -match '^Mission(\d{6})_100$') {
            $missionKey = "MISSION_$($matches[1])"
            $english = Get-EnglishMessage $message
            if ($english) {
                $missionNames[$missionKey] = Resolve-MessageRefs -Text $english -MessageByName $messageByName
            }
        }
    }

    return [pscustomobject]@{
        enums = $enums
        mappings = $mappings
        item_fixed_enum = $itemFixedEnum
        enemy_fixed_enum = $enemyFixedEnum
        mission_id_enum = (Get-ObjectPropertyValue $enums "app.MissionIDList.ID")
        mission_names = $missionNames
        item_message_map = $itemMessageMap
        accessory_id_enum = (Get-ObjectPropertyValue $enums "app.EquipDef.ACCESSORY_ID")
        accessory_fixed_enum = (Get-ObjectPropertyValue $enums "app.EquipDef.ACCESSORY_ID_Fixed")
        accessory_hash_to_name = $accessoryHashToName
        bowgun_customize_id_enum = (Get-ObjectPropertyValue $enums "app.CustomizeItemID.ID")
        bowgun_customize_fixed_enum = (Get-ObjectPropertyValue $enums "app.CustomizeItemID.ID_Fixed")
        bowgun_customize_hash_to_name = $bowgunCustomizeHashToName
        messages = $messageMap
        messages_by_name = $messageByName
        enemy_names = $enemyNames
    }
}

$script:_armorPartKeywords = [ordered]@{
    "HELM"  = @("Helm","Headgear","Cap","Mask","Hood","Coif","Crown","Beret","Hat","Eyepatch","Bonnet","Circlet","Visor","Brain","Face")
    "BODY"  = @("Mail","Plate","Vest","Coat","Body","Jacket","Tunic","Haubergeon","Jerkin","Muscle","Thorax")
    "ARM"   = @("Vambraces","Bracers","Braces","Sleeve","Grip","Gauntlets","Gloves","Claw")
    "WAIST" = @("Coil","Belt","Sash","Cord","Tasset","Haramaki")
    "LEG"   = @("Greaves","Boots","Leggings","Guards","Cuisses","Shinguards","Faulds","Cuish","Feet")
}

function Initialize-LocalDataResolver {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $memDir          = Join-Path $RepoRoot "memory\mh-wilds"
    $skillsCsvPath   = Join-Path $memDir "skills_normalized.csv"
    $armorCsvPath    = Join-Path $memDir "armor_normalized.csv"
    $decoCsvPaths    = @(
        (Join-Path $memDir "decorations_armor_normalized.csv"),
        (Join-Path $memDir "decorations_weapon_normalized.csv")
    )
    foreach ($p in @($skillsCsvPath, $armorCsvPath) + $decoCsvPaths) {
        if (-not (Test-Path -LiteralPath $p)) {
            Write-Warning "Local skill data not found at '$p'; native_skills and decoration_skills will be empty."
            return $null
        }
    }
    Write-Host "Loading local skill data..."

    $skillMaxLevels = @{}
    foreach ($skillRow in (Import-Csv -LiteralPath $skillsCsvPath)) {
        if ($skillRow.Title) {
            $maxLevel = 0
            if ([int]::TryParse([string]$skillRow.MaxLevel, [ref]$maxLevel)) {
                $skillMaxLevels[$skillRow.Title] = $maxLevel
            }
        }
    }

    function Get-RomanNumeralValue {
        param([string]$Value)

        switch ($Value) {
            "I" { return 1 }
            "II" { return 2 }
            "III" { return 3 }
            "IV" { return 4 }
            "V" { return 5 }
            default { return $null }
        }
    }

    function Limit-SkillLevel {
        param(
            [string]$Skill,
            [nullable[int]]$Level
        )

        if ($null -eq $Level) { return $null }
        if ($skillMaxLevels.ContainsKey($Skill) -and $skillMaxLevels[$Skill] -gt 0) {
            return [Math]::Min([int]$Level, [int]$skillMaxLevels[$Skill])
        }
        return [int]$Level
    }

    function Format-SkillDetails {
        param([object[]]$Details)

        $parts = [System.Collections.Generic.List[string]]::new()
        foreach ($detail in @($Details)) {
            if (-not $detail.skill) { continue }
            $levelText = if ($null -ne $detail.level) { "Lv$($detail.level)" } else { "Lv?" }
            $parts.Add("$($detail.skill) $levelText")
        }
        return $parts -join ";"
    }

    function Parse-SkillDetailsText {
        param([string]$Text)

        $details = @()
        if (-not $Text) { return $details }
        foreach ($part in ($Text -split ';')) {
            $part = $part.Trim()
            if (-not $part) { continue }
            if ($part -match '^(.+?)\s+(?:Lv\.?|Level)\s*(\d+)$') {
                $details += [pscustomobject]@{
                    skill = $matches[1].Trim()
                    level = [int]$matches[2]
                }
            }
            elseif ($part -match '^(.+?)\s+\+(\d+)$') {
                $details += [pscustomobject]@{
                    skill = $matches[1].Trim()
                    level = [int]$matches[2]
                }
            }
        }
        return $details
    }

    function Get-DecorationSkillDetails {
        param(
            $Row,
            [bool]$IsArmorDecoration
        )

        $title = [string]$Row.Title
        $primarySkill = [string]$Row.Skill
        if (-not $title -or -not $primarySkill) { return @() }

        $slotLevel = 0
        [void][int]::TryParse([string]$Row.SlotLevel, [ref]$slotLevel)

        $skills = [System.Collections.Generic.List[string]]::new()
        $skills.Add($primarySkill)
        if ($Row.Description -match 'grants the .+? and (.+?) skills') {
            $secondarySkill = ($matches[1] -replace '[.…]+$', '').Trim()
            if ($secondarySkill -and -not $skills.Contains($secondarySkill)) {
                $skills.Add($secondarySkill)
            }
        }

        $romanLevel = $null
        if ($title -match '\b(?:Jewel|Jwl)\s+(I|II|III|IV|V)\s*\[') {
            $romanLevel = Get-RomanNumeralValue $matches[1]
        }

        $details = @()
        for ($i = 0; $i -lt $skills.Count; $i++) {
            $skill = $skills[$i]
            $level = 1
            if (-not $IsArmorDecoration) {
                if ($null -ne $romanLevel -and $i -eq 0) {
                    $level = $romanLevel
                }
                elseif ($title -like '*/*' -and $i -eq 0 -and $slotLevel -gt 0) {
                    $level = $slotLevel
                }
            }
            $details += [pscustomobject]@{
                skill = $skill
                level = Limit-SkillLevel $skill $level
            }
        }
        return $details
    }

    # Decoration name → list of skill names/details/metadata (handles dual-skill decos via Description)
    $decoToSkills = @{}
    $decoToSkillDetails = @{}
    $decoToType = @{}
    $decoToSlotLevel = @{}
    $decoToRarity = @{}
    foreach ($csvPath in $decoCsvPaths) {
        $isArmorDecoration = ([System.IO.Path]::GetFileName($csvPath) -eq "decorations_armor_normalized.csv")
        foreach ($row in (Import-Csv -LiteralPath $csvPath)) {
            $title = $row.Title
            if (-not $title) { continue }
            $decoToType[$title] = if ($isArmorDecoration) { "armor" } else { "weapon" }
            $decoToSlotLevel[$title] = $row.SlotLevel
            $decoToRarity[$title] = $row.Rarity
            $details = @(Get-DecorationSkillDetails $row $isArmorDecoration)
            if ($details.Count -gt 0) {
                $decoToSkillDetails[$title] = $details
                $decoToSkills[$title] = @($details | ForEach-Object { $_.skill })
            }
        }
    }

    # Armor series+part → piece title lookup: (seriesCore|variant|PART_TYPE) → Title
    $armorRows = @(Import-Csv -LiteralPath $armorCsvPath)
    $armorKeyToTitle = @{}
    foreach ($row in $armorRows) {
        $title = $row.Title; $armorSet = $row.ArmorSet
        if (-not $title -or -not $armorSet) { continue }
        $variant    = if ($title -match 'β') { 'β' } elseif ($title -match 'α') { 'α' } else { '' }
        $seriesCore = ($armorSet -replace '\s*Armor Sets\s*$', '' -replace 'β', '' -replace 'α', '' -replace '\s+', ' ').Trim().ToLower()
        $partType   = $null
        foreach ($pt in $script:_armorPartKeywords.Keys) {
            foreach ($kw in $script:_armorPartKeywords[$pt]) {
                if ($title -match "(?i)\b$([regex]::Escape($kw))\b") { $partType = $pt; break }
            }
            if ($partType) { break }
        }
        if (-not $partType) { continue }
        $key = "$seriesCore|$variant|$partType"
        if (-not $armorKeyToTitle.ContainsKey($key)) { $armorKeyToTitle[$key] = $title }
    }

    # Piece title → skills and charm name → skills: invert ObtainedFrom column
    $pieceTitleToSkills = @{}
    foreach ($row in $armorRows) { if ($row.Title) { $pieceTitleToSkills[$row.Title] = [System.Collections.Generic.List[string]]::new() } }
    $pieceTitles = @($pieceTitleToSkills.Keys)
    $pieceTitleToKnownSkillDetails = @{}
    foreach ($row in $armorRows) {
        if ($row.Title -and $row.PSObject.Properties["SkillDetails"] -and $row.SkillDetails) {
            $pieceTitleToKnownSkillDetails[$row.Title] = @(Parse-SkillDetailsText $row.SkillDetails)
        }
    }
    $charmToSkills = @{}
    $charmRe = [regex]'(?<![a-z])([A-Z][A-Za-z0-9/'' ]+?) Charm (III|II|IV|V|I)(?= |$)'
    foreach ($skillRow in (Import-Csv -LiteralPath $skillsCsvPath)) {
        if (-not $skillRow.ObtainedFrom) { continue }
        $obtained = ' ' + $skillRow.ObtainedFrom + ' '
        foreach ($title in $pieceTitles) {
            if ($obtained.IndexOf(" $title ", [System.StringComparison]::Ordinal) -ge 0) {
                $pieceTitleToSkills[$title].Add($skillRow.Title)
            }
        }
        foreach ($m in $charmRe.Matches($skillRow.ObtainedFrom)) {
            $cn = "$($m.Groups[1].Value) Charm $($m.Groups[2].Value)"
            if (-not $charmToSkills.ContainsKey($cn)) { $charmToSkills[$cn] = [System.Collections.Generic.List[string]]::new() }
            $charmToSkills[$cn].Add($skillRow.Title)
        }
    }
    $directCharmNames = @{}
    foreach ($cn in @($charmToSkills.Keys)) {
        $directCharmNames[$cn] = $true
    }
    # Propagate skills to all roman-numeral tiers of each charm base so that
    # e.g. "Exploiter Charm III" resolves even when only I/II appear in ObtainedFrom.
    $charmBases = @{}
    foreach ($cn in @($charmToSkills.Keys)) {
        if ($cn -match '^(.+? Charm) (III|II|IV|V|I)$') {
            if (-not $charmBases.ContainsKey($matches[1])) { $charmBases[$matches[1]] = $charmToSkills[$cn] }
        }
    }
    foreach ($base in $charmBases.Keys) {
        foreach ($suffix in @("I", "II", "III", "IV", "V")) {
            $fullName = "$base $suffix"
            if (-not $charmToSkills.ContainsKey($fullName)) { $charmToSkills[$fullName] = $charmBases[$base] }
        }
    }

    $pieceTitleToSkillDetails = @{}
    foreach ($title in $pieceTitleToSkills.Keys) {
        if ($pieceTitleToKnownSkillDetails.ContainsKey($title) -and $pieceTitleToKnownSkillDetails[$title].Count -gt 0) {
            $pieceTitleToSkillDetails[$title] = $pieceTitleToKnownSkillDetails[$title]
        }
        else {
            $pieceTitleToSkillDetails[$title] = @($pieceTitleToSkills[$title] | ForEach-Object {
                [pscustomobject]@{ skill = $_; level = $null }
            })
        }
    }

    $charmToSkillDetails = @{}
    foreach ($charmName in $charmToSkills.Keys) {
        $charmLevel = $null
        if ($directCharmNames.ContainsKey($charmName) -and $charmName -match ' (I|II|III|IV|V)$') {
            $charmLevel = Get-RomanNumeralValue $matches[1]
        }
        $charmToSkillDetails[$charmName] = @($charmToSkills[$charmName] | ForEach-Object {
            [pscustomobject]@{ skill = $_; level = Limit-SkillLevel $_ $charmLevel }
        })
    }

    return [pscustomobject]@{
        deco_to_skills              = $decoToSkills
        deco_to_skill_details       = $decoToSkillDetails
        deco_to_type                = $decoToType
        deco_to_slot_level          = $decoToSlotLevel
        deco_to_rarity              = $decoToRarity
        armor_key_to_title          = $armorKeyToTitle
        piece_title_to_skills       = $pieceTitleToSkills
        piece_title_to_skill_details = $pieceTitleToSkillDetails
        charm_to_skills             = $charmToSkills
        charm_to_skill_details      = $charmToSkillDetails
        format_skill_details        = ${function:Format-SkillDetails}
    }
}

function Resolve-EnumMappedName {
    param(
        $Resolver,
        [Parameter(Mandatory = $true)]
        [string]$EnumType,
        $Id
    )

    $enumName = $null
    $name = $null
    if ($null -ne $Resolver -and $null -ne $Id) {
        $enumMap = Get-ObjectPropertyValue $Resolver.enums $EnumType
        $messageMap = Get-ObjectPropertyValue $Resolver.mappings $EnumType
        $enumName = Get-ObjectPropertyValue $enumMap ([string]$Id)
        if ($enumName -and $null -ne $messageMap) {
            $guid = Get-ObjectPropertyValue $messageMap $enumName
            $message = Get-ObjectPropertyValue $Resolver.messages $guid
            $name = Get-EnglishMessage $message
        }
    }

    return [ordered]@{
        enum = $enumName
        name = $name
    }
}

function Resolve-EnumValue {
    param(
        $Resolver,
        [Parameter(Mandatory = $true)]
        [string]$EnumType,
        $Id
    )

    if ($null -eq $Resolver -or $null -eq $Id) {
        return $null
    }

    $enumMap = Get-ObjectPropertyValue $Resolver.enums $EnumType
    return Get-ObjectPropertyValue $enumMap ([string]$Id)
}

function Resolve-ItemId {
    param(
        $Resolver,
        $Id
    )

    $enumName = $null
    $name = $null
    if ($null -ne $Resolver -and $null -ne $Id) {
        $enumName = Get-ObjectPropertyValue $Resolver.item_fixed_enum ([string]$Id)
        if ($enumName) {
            $guid = Get-ObjectPropertyValue $Resolver.item_message_map $enumName
            $message = Get-ObjectPropertyValue $Resolver.messages $guid
            $name = Get-EnglishMessage $message
        }
    }

    return [ordered]@{
        item_id_fixed = $Id
        item_enum = $enumName
        item_name = $name
    }
}

function Resolve-EnemyId {
    param(
        $Resolver,
        $Id
    )

    $enumName = $null
    $name = $null
    if ($null -ne $Resolver -and $null -ne $Id) {
        $enumName = Get-ObjectPropertyValue $Resolver.enemy_fixed_enum ([string]$Id)
        if ($enumName -and $Resolver.enemy_names.ContainsKey($enumName)) {
            $name = $Resolver.enemy_names[$enumName]
        }
    }

    return [ordered]@{
        fixed_id = $Id
        enemy_enum = $enumName
        name = $name
    }
}

function Resolve-AccessoryId {
    param(
        $Resolver,
        $Id
    )

    if ($null -eq $Resolver -or $null -eq $Id -or $null -eq $Resolver.accessory_id_enum) {
        return $null
    }

    $enumName = Get-ObjectPropertyValue $Resolver.accessory_id_enum ([string]$Id)
    if (-not $enumName) { return $null }

    $hash = Get-ObjectPropertyValue $Resolver.accessory_fixed_enum $enumName
    if ($null -eq $hash) { return $null }

    # Negative hashes are encoded in message names as "m<abs>" instead of "-<abs>".
    $hashSuffix = if ([int64]$hash -lt 0) { "m$([math]::Abs([int64]$hash))" } else { [string]$hash }
    return $Resolver.accessory_hash_to_name[$hashSuffix]
}

function Resolve-BowgunCustomizeId {
    param(
        $Resolver,
        $Id
    )

    if ($null -eq $Resolver -or $null -eq $Id -or $null -eq $Resolver.bowgun_customize_id_enum) {
        return $null
    }

    $enumName = Get-ObjectPropertyValue $Resolver.bowgun_customize_id_enum ([string]$Id)
    if (-not $enumName) { return $null }

    $hash = Get-ObjectPropertyValue $Resolver.bowgun_customize_fixed_enum $enumName
    if ($null -eq $hash) { return $enumName }

    # Negative hashes are encoded in message names as "m<abs>" instead of "-<abs>".
    $hashSuffix = if ([int64]$hash -lt 0) { "m$([math]::Abs([int64]$hash))" } else { [string]$hash }
    $name = $Resolver.bowgun_customize_hash_to_name[$hashSuffix]
    if ($name) { return $name }
    return $enumName
}

function Convert-MapToString {
    param($Map)

    if ($null -eq $Map) {
        return ""
    }

    $pairs = @()
    foreach ($key in ($Map.Keys | Sort-Object)) {
        $pairs += "$key=$($Map[$key])"
    }
    return ($pairs -join ";")
}

function Get-Field {
    param(
        [Parameter(Mandatory = $true)]
        $Class,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not $Class.fields) {
        return $null
    }

    return @($Class.fields | Where-Object { $_.name -eq $Name } | Select-Object -First 1)[0]
}

function Get-FieldValue {
    param(
        [Parameter(Mandatory = $true)]
        $Class,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $field = Get-Field -Class $Class -Name $Name
    if ($null -eq $field) {
        return $null
    }

    return $field.value
}

function Test-ClassHasField {
    param(
        $Class,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $Class -or -not $Class.fields) {
        return $false
    }

    return $null -ne (Get-Field -Class $Class -Name $Name)
}

function Convert-ScalarValue {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    if (($Value.PSObject.Properties.Name -contains "fields") -or
        ($Value.PSObject.Properties.Name -contains "values")) {
        return $null
    }

    if ($Value.PSObject.Properties.Name -contains "kind") {
        switch ($Value.kind) {
            "Class" { return $null }
            "Array" { return $null }
            default {
                if ($Value.PSObject.Properties.Name -contains "value") {
                    return $Value.value
                }
                return $Value
            }
        }
    }

    return $Value
}

function Get-ClassScalars {
    param($Class)

    $result = [ordered]@{}
    if (-not $Class.fields) {
        return $result
    }

    foreach ($field in $Class.fields) {
        $scalar = Convert-ScalarValue $field.value
        if ($null -ne $scalar) {
            $result[$field.name] = $scalar
        }
    }

    return $result
}

function Get-ArrayValues {
    param($Value)

    if ($null -eq $Value -or $Value.kind -ne "Array" -or -not $Value.values) {
        return @()
    }

    return @($Value.values)
}

function Get-NonzeroScalars {
    param($Class)

    $scalars = Get-ClassScalars $Class
    $result = [ordered]@{}
    foreach ($key in $scalars.Keys) {
        $value = $scalars[$key]
        if ($null -eq $value) {
            continue
        }
        if ($value -is [string] -and $value.Length -eq 0) {
            continue
        }
        if ($value -is [bool]) {
            if ($value) {
                $result[$key] = $value
            }
            continue
        }
        if ($value -is [int] -or $value -is [long] -or $value -is [double]) {
            if ($value -ne 0) {
                $result[$key] = $value
            }
            continue
        }
        $result[$key] = $value
    }

    return $result
}

function Select-Fields {
    param(
        [Parameter(Mandatory = $true)]
        $Class,

        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    $result = [ordered]@{}
    foreach ($name in $Names) {
        $fieldValue = Get-FieldValue -Class $Class -Name $name
        $scalar = Convert-ScalarValue $fieldValue
        if ($null -ne $scalar) {
            $jsonName = $name.TrimStart("_")
            $jsonName = [regex]::Replace($jsonName, "([a-z0-9])([A-Z])", '$1_$2').ToLowerInvariant()
            $result[$jsonName] = $scalar
        }
    }

    return $result
}

function Convert-IdArrayToString {
    param($Value)

    $values = Get-ArrayValues $Value
    if ($values.Count -eq 0) {
        return ""
    }

    $kept = @($values | Where-Object { $null -ne $_ -and [int64]$_ -ne -1 })
    return ($kept -join ";")
}

function Summarize-ItemBox {
    param($Json, $Resolver)

    $items = @()
    foreach ($entry in Get-ArrayValues $Json) {
        $row = Select-Fields $entry @("ItemIdFixed", "ItemId", "Num")
        if ($row.Contains("num") -and [int64]$row["num"] -ne 0) {
            $resolved = Resolve-ItemId $Resolver $row["item_id_fixed"]
            $row = [ordered]@{
                item_id_fixed = $resolved["item_id_fixed"]
                item_enum = $resolved["item_enum"]
                item_name = $resolved["item_name"]
                quantity = $row["num"]
            }
            $items += [pscustomobject]$row
        }
    }

    return [ordered]@{
        total_entries = (Get-ArrayValues $Json).Count
        nonzero_entries = $items.Count
        items = $items
    }
}

# FreeVal0 for weapon entries encodes weapon type in the traditional MH 14-weapon ordering,
# not in app.WeaponDef.TYPE_Fixed ordering. FreeVal1 is the weapon ID within the type's Fixed enum.
function Get-WeaponIdEnumType {
    param([int]$WeaponTypeId)

    switch ($WeaponTypeId) {
        0  { return "app.WeaponDef.TachiId_Fixed" }       # Great Sword
        1  { return "app.WeaponDef.ShortSwordId_Fixed" }  # Sword & Shield
        2  { return "app.WeaponDef.TwinSwordId_Fixed" }   # Dual Blades
        3  { return "app.WeaponDef.LongSwordId_Fixed" }   # Long Sword
        4  { return "app.WeaponDef.HammerId_Fixed" }      # Hammer
        5  { return "app.WeaponDef.WhistleId_Fixed" }     # Hunting Horn
        6  { return "app.WeaponDef.LanceId_Fixed" }       # Lance
        7  { return "app.WeaponDef.GunLanceId_Fixed" }    # Gunlance
        8  { return "app.WeaponDef.SlashAxeId_Fixed" }    # Switch Axe
        9  { return "app.WeaponDef.ChargeAxeId_Fixed" }   # Charge Blade
        10 { return "app.WeaponDef.RodId_Fixed" }         # Insect Glaive
        11 { return "app.WeaponDef.BowId_Fixed" }         # Bow
        12 { return "app.WeaponDef.HeavyBowgunId_Fixed" } # Heavy Bowgun
        13 { return "app.WeaponDef.LightBowgunId_Fixed" } # Light Bowgun
        default { return $null }
    }
}

function Get-WeaponTypeName {
    param([int]$WeaponTypeId)

    switch ($WeaponTypeId) {
        0  { return "GREAT_SWORD" }
        1  { return "SWORD_AND_SHIELD" }
        2  { return "DUAL_BLADES" }
        3  { return "LONG_SWORD" }
        4  { return "HAMMER" }
        5  { return "HUNTING_HORN" }
        6  { return "LANCE" }
        7  { return "GUN_LANCE" }
        8  { return "SWITCH_AXE" }
        9  { return "CHARGE_BLADE" }
        10 { return "INSECT_GLAIVE" }
        11 { return "BOW" }
        12 { return "HEAVY_BOWGUN" }
        13 { return "LIGHT_BOWGUN" }
        default { return $null }
    }
}

function Get-RomanNumeral {
    param($Value)

    switch ([int]$Value) {
        1 { return "I" }
        2 { return "II" }
        3 { return "III" }
        4 { return "IV" }
        5 { return "V" }
        default { return $null }
    }
}

function Convert-EquipEntryToRow {
    param(
        [Parameter(Mandatory = $true)]
        $Entry,
        [int]$Index,
        $Resolver,
        $LocalResolver
    )

    $category = Convert-ScalarValue (Get-FieldValue -Class $Entry -Name "Category_Gender")
    $freeVal0 = Convert-ScalarValue (Get-FieldValue -Class $Entry -Name "FreeVal0")
    $freeVal1 = Convert-ScalarValue (Get-FieldValue -Class $Entry -Name "FreeVal1")
    $freeVal2 = Convert-ScalarValue (Get-FieldValue -Class $Entry -Name "FreeVal2")
    $freeVal3 = Convert-ScalarValue (Get-FieldValue -Class $Entry -Name "FreeVal3")
    $freeVal4 = Convert-ScalarValue (Get-FieldValue -Class $Entry -Name "FreeVal4")
    $freeVal5 = Convert-ScalarValue (Get-FieldValue -Class $Entry -Name "FreeVal5")
    $bonusByCreating = Convert-ScalarValue (Get-FieldValue -Class $Entry -Name "BonusByCreating")
    $bonusByGrinding = Convert-ScalarValue (Get-FieldValue -Class $Entry -Name "BonusByGrinding")
    $grindingNum = Convert-ScalarValue (Get-FieldValue -Class $Entry -Name "GrindingNum")
    $customizeIds = Convert-IdArrayToString (Get-FieldValue -Class $Entry -Name "BowgunCustomizeId")
    $customizeIdRaw = Get-ArrayValues (Get-FieldValue -Class $Entry -Name "BowgunCustomizeId")
    $customizeIdFilled = @($customizeIdRaw | Where-Object { $null -ne $_ -and [int64]$_ -ne -1 })
    $customizeNames = if ($customizeIdFilled.Count -gt 0) {
        ($customizeIdFilled | ForEach-Object {
            $n = Resolve-BowgunCustomizeId $Resolver (Convert-ScalarValue $_)
            if ($n) { $n } else { Convert-ScalarValue $_ }
        }) -join ";"
    } else { "" }
    $decorationIdRaw = Get-ArrayValues (Get-FieldValue -Class $Entry -Name "EquipmentAccessoryIdArray")
    $decorationIds = Convert-IdArrayToString (Get-FieldValue -Class $Entry -Name "EquipmentAccessoryIdArray")
    $decorationIdFilled = @($decorationIdRaw | Where-Object { $null -ne $_ -and [int64]$_ -ne -1 })
    $decorationNames = if ($decorationIdFilled.Count -gt 0) {
        ($decorationIdFilled | ForEach-Object {
            $n = Resolve-AccessoryId $Resolver (Convert-ScalarValue $_)
            if ($n) { $n } else { Convert-ScalarValue $_ }
        }) -join ";"
    } else { "" }

    $hasScalarData = @($freeVal0, $freeVal1, $freeVal2, $freeVal3, $freeVal4, $freeVal5, $bonusByCreating, $bonusByGrinding, $grindingNum) |
        Where-Object { $null -ne $_ -and [int64]$_ -ne 0 }
    if ([int64]$category -eq 141 -and $hasScalarData.Count -eq 0 -and -not $customizeIds -and -not $decorationIds) {
        return $null
    }

    $kind = "unknown"
    $type = $null
    $enum = $null
    $name = $null
    $armorPart = $null

    if ([int64]$category -eq 0 -or [int64]$category -eq 1) {
        $kind = "armor"
        $resolved = Resolve-EnumMappedName $Resolver "app.ArmorDef.SERIES" $freeVal0
        $armorPart = Resolve-EnumValue $Resolver "app.ArmorDef.ARMOR_PARTS" $freeVal1
        $enum = $resolved["enum"]
        $type = $armorPart
        if ($resolved["name"] -and $armorPart) {
            $name = "$($resolved["name"]) $armorPart"
        }
        else {
            $name = $resolved["name"]
        }
    }
    elseif ([int64]$category -eq 21) {
        $kind = "charm"
        $resolved = Resolve-EnumMappedName $Resolver "app.ArmorDef.AmuletType" $freeVal0
        $enum = $resolved["enum"]
        $name = $resolved["name"]
        $tier = Get-RomanNumeral $freeVal1
        if ($name -and $tier -and $name -match '^(.+? Charm) (I|II|III|IV|V)$') {
            $name = "$($matches[1]) $tier"
        }
    }
    elseif ([int64]$category -eq 13) {
        # Category_Gender=13 means "weapon". FreeVal0 = weapon type in traditional MH 14-weapon
        # ordering (0=GS, 1=SnS, 2=DB, 3=LS, 4=Hammer, 5=HH, 6=Lance, 7=GL, 8=SA, 9=CB,
        # 10=IG, 11=Bow, 12=HBG, 13=LBG). FreeVal1 = weapon ID within that type's Fixed enum.
        $weaponTypeInt = [int][int64]$freeVal0
        $weaponIdEnumType = Get-WeaponIdEnumType $weaponTypeInt
        if ($weaponIdEnumType) {
            $kind = "weapon"
            $type = Get-WeaponTypeName $weaponTypeInt
            $resolved = Resolve-EnumMappedName $Resolver $weaponIdEnumType $freeVal1
            $enum = $resolved["enum"]
            $name = $resolved["name"]
        }
    }

    $nativeSkills = ""
    $decoSkillsStr = ""
    $nativeSkillDetails = ""
    $decoSkillDetails = ""
    if ($null -ne $LocalResolver) {
        # Decoration skills
        if ($decorationIdFilled.Count -gt 0 -and $decorationNames) {
            $allDecoSkills = [System.Collections.Generic.List[string]]::new()
            $allDecoDetails = @()
            foreach ($dn in ($decorationNames -split ';')) {
                $dn = $dn.Trim()
                if ($dn -and $LocalResolver.deco_to_skills.ContainsKey($dn)) {
                    foreach ($s in $LocalResolver.deco_to_skills[$dn]) { $allDecoSkills.Add($s) }
                }
                if ($dn -and $LocalResolver.deco_to_skill_details.ContainsKey($dn)) {
                    $allDecoDetails += @($LocalResolver.deco_to_skill_details[$dn])
                }
            }
            $decoSkillsStr = $allDecoSkills -join ";"
            $decoSkillDetails = & $LocalResolver.format_skill_details $allDecoDetails
        }
        # Native skills from armor piece or charm
        if ($kind -eq "armor" -and $name) {
            $lastSpace = $name.LastIndexOf(" ")
            if ($lastSpace -gt 0) {
                $partEnum   = $name.Substring($lastSpace + 1)
                $series     = $name.Substring(0, $lastSpace)
                $variant    = if ($series -match 'β') { 'β' } elseif ($series -match 'α') { 'α' } else { '' }
                $seriesCore = ($series -replace 'β', '' -replace 'α', '' -replace '\s+', ' ').Trim().ToLower()
                $key        = "$seriesCore|$variant|$partEnum"
                $pieceTitle = $LocalResolver.armor_key_to_title[$key]
                if ($pieceTitle -and $LocalResolver.piece_title_to_skills.ContainsKey($pieceTitle)) {
                    $nativeSkills = $LocalResolver.piece_title_to_skills[$pieceTitle] -join ";"
                    if ($LocalResolver.piece_title_to_skill_details.ContainsKey($pieceTitle)) {
                        $nativeSkillDetails = & $LocalResolver.format_skill_details @($LocalResolver.piece_title_to_skill_details[$pieceTitle])
                    }
                }
            }
        } elseif ($kind -eq "charm" -and $name) {
            if ($LocalResolver.charm_to_skills.ContainsKey($name)) {
                $nativeSkills = $LocalResolver.charm_to_skills[$name] -join ";"
                if ($LocalResolver.charm_to_skill_details.ContainsKey($name)) {
                    $nativeSkillDetails = & $LocalResolver.format_skill_details @($LocalResolver.charm_to_skill_details[$name])
                }
            }
        }
    }

    return [pscustomobject]([ordered]@{
        index = $Index
        kind = $kind
        category_gender = $category
        type = $type
        enum = $enum
        name = $name
        armor_part = $armorPart
        free_val0 = $freeVal0
        free_val1 = $freeVal1
        free_val2 = $freeVal2
        free_val3 = $freeVal3
        free_val4 = $freeVal4
        free_val5 = $freeVal5
        bonus_by_creating = $bonusByCreating
        bonus_by_grinding = $bonusByGrinding
        grinding_num = $grindingNum
        customize_or_skill_ids = $customizeIds
        bowgun_mod_ids = $customizeIds
        bowgun_mod_names = $customizeNames
        decoration_ids = $decorationIds
        decoration_names = $decorationNames
        native_skills = $nativeSkills
        decoration_skills = $decoSkillsStr
        native_skill_details = $nativeSkillDetails
        decoration_skill_details = $decoSkillDetails
    })
}

function Summarize-EquipBox {
    param($Json, $Resolver, $LocalResolver)

    $rows = @()
    $index = 0
    foreach ($entry in Get-ArrayValues $Json) {
        $row = Convert-EquipEntryToRow -Entry $entry -Index $index -Resolver $Resolver -LocalResolver $LocalResolver
        if ($null -ne $row) {
            $rows += $row
        }
        $index++
    }

    $byKind = [ordered]@{}
    foreach ($group in ($rows | Group-Object kind | Sort-Object Name)) {
        $byKind[$group.Name] = $group.Count
    }

    return [ordered]@{
        total_entries = (Get-ArrayValues $Json).Count
        nonempty_entries = $rows.Count
        counts_by_kind = $byKind
        entries = $rows
        caveats = @(
            "Equipment save fields are partly generic. Weapons, armor series/parts, and charms are resolved where local enum message assets support them.",
            "Bowgun mods from BowgunCustomizeId are listed in bowgun_mod_ids and bowgun_mod_names when local enum message assets support them.",
            "Decoration names are resolved from local Wilds assets. The raw numeric IDs are also retained in decoration_ids for cross-reference.",
            "Decoration and roman-numeral charm levels are inferred from local skill/deco tables. Native armor skill levels are resolved from armor_normalized.csv SkillDetails when available; otherwise they are marked Lv?."
        )
    }
}

function Summarize-EquipCurrent {
    param($Json, $Resolver, $LocalResolver)

    $slotNames = @("weapon", "head", "chest", "arms", "waist", "legs", "charm")

    $equipIndexClass = Get-FieldValue -Class $Json -Name "_EquipIndex"
    $indexArray = Get-FieldValue -Class $equipIndexClass -Name "Index"
    $indices = @(Get-ArrayValues $indexArray)

    $equipBoxArray = Get-FieldValue -Class $Json -Name "_EquipBox"
    $boxEntries = @(Get-ArrayValues $equipBoxArray)

    $slots = @()
    for ($slotPos = 0; $slotPos -lt $indices.Count; $slotPos++) {
        $boxIdx = [int]$indices[$slotPos]
        if ($boxIdx -lt 0) {
            continue
        }

        $slotName = if ($slotPos -lt $slotNames.Count) { $slotNames[$slotPos] } else { "slot_$slotPos" }
        $entry = $boxEntries[$boxIdx]
        $row = Convert-EquipEntryToRow -Entry $entry -Index $boxIdx -Resolver $Resolver -LocalResolver $LocalResolver
        if ($null -eq $row) {
            continue
        }

        $fullRow = [ordered]@{ slot = $slotName; slot_index = $slotPos }
        foreach ($key in $row.PSObject.Properties.Name) { $fullRow[$key] = $row.$key }
        $slots += [pscustomobject]$fullRow
    }

    return [ordered]@{
        equipped_count = $slots.Count
        slots = $slots
        caveats = @(
            "Equipment save fields are partly generic. Weapons, armor series/parts, and charms are resolved where local enum message assets support them.",
            "Bowgun mods from BowgunCustomizeId are listed in bowgun_mod_ids and bowgun_mod_names when local enum message assets support them.",
            "Decoration names are resolved from local Wilds assets. The raw numeric IDs are also retained in decoration_ids for cross-reference.",
            "Decoration and roman-numeral charm levels are inferred from local skill/deco tables. Native armor skill levels are resolved from armor_normalized.csv SkillDetails when available; otherwise they are marked Lv?."
        )
    }
}

function Summarize-DecorationBox {
    param($Json, $Resolver, $LocalResolver)

    $accessoryBox = Get-FieldValue -Class $Json -Name "_AccessoryBox"
    $rows = @()
    foreach ($entry in Get-ArrayValues $accessoryBox) {
        $row = Select-Fields $entry @("ID", "Num")
        $quantity = if ($row.Contains("num")) { [int64]$row["num"] } else { 0 }
        if ($quantity -le 0) {
            continue
        }

        $accessoryId = $row["id"]
        $decorationName = Resolve-AccessoryId $Resolver $accessoryId
        if (-not $decorationName) {
            $decorationName = [string]$accessoryId
        }

        $decorationType = ""
        $slotLevel = ""
        $rarity = ""
        $skills = ""
        $skillDetails = ""
        if ($null -ne $LocalResolver -and $decorationName) {
            if ($LocalResolver.deco_to_type.ContainsKey($decorationName)) {
                $decorationType = $LocalResolver.deco_to_type[$decorationName]
            }
            if ($LocalResolver.deco_to_slot_level.ContainsKey($decorationName)) {
                $slotLevel = $LocalResolver.deco_to_slot_level[$decorationName]
            }
            if ($LocalResolver.deco_to_rarity.ContainsKey($decorationName)) {
                $rarity = $LocalResolver.deco_to_rarity[$decorationName]
            }
            if ($LocalResolver.deco_to_skills.ContainsKey($decorationName)) {
                $skills = $LocalResolver.deco_to_skills[$decorationName] -join ";"
            }
            if ($LocalResolver.deco_to_skill_details.ContainsKey($decorationName)) {
                $skillDetails = & $LocalResolver.format_skill_details @($LocalResolver.deco_to_skill_details[$decorationName])
            }
        }

        $rows += [pscustomobject]([ordered]@{
            accessory_id = $accessoryId
            decoration_name = $decorationName
            decoration_type = $decorationType
            slot_level = $slotLevel
            rarity = $rarity
            quantity = $quantity
            skills = $skills
            skill_details = $skillDetails
        })
    }

    $rows = @($rows | Sort-Object decoration_type, slot_level, decoration_name)
    return [ordered]@{
        total_entries = (Get-ArrayValues $accessoryBox).Count
        owned_entries = $rows.Count
        decorations = $rows
        caveats = @(
            "This reads the loose decoration store from _Equip._AccessoryBox. Slotted decorations on saved equipment are listed separately in equipment summaries.",
            "Decoration skill levels are inferred from local decoration CSVs; dual-skill decorations include both skills when their description exposes both names."
        )
    }
}

function Build-DecorationSkillsTally {
    param([object[]]$Rows)

    $tally = [ordered]@{}
    foreach ($row in @($Rows)) {
        $quantity = 0
        [void][int]::TryParse([string]$row.quantity, [ref]$quantity)
        if ($quantity -le 0) { continue }

        foreach ($detail in ([string]$row.skill_details -split ';')) {
            $detail = $detail.Trim()
            if (-not $detail) { continue }
            if ($detail -notmatch '^(.+?)\s+Lv(\d+|\?)$') { continue }

            $skill = $matches[1].Trim()
            $level = $null
            if ($matches[2] -ne '?') { $level = [int]$matches[2] }
            if (-not $tally.Contains($skill)) {
                $tally[$skill] = [ordered]@{
                    skill_name = $skill
                    decoration_quantity = 0
                    known_total_levels = 0
                    has_unknown_level = $false
                    decorations = [System.Collections.Generic.List[string]]::new()
                }
            }

            $tally[$skill].decoration_quantity += $quantity
            if ($null -ne $level) {
                $tally[$skill].known_total_levels += ($quantity * $level)
                $tally[$skill].decorations.Add("$($row.decoration_name) x$quantity (Lv$level)")
            }
            else {
                $tally[$skill].has_unknown_level = $true
                $tally[$skill].decorations.Add("$($row.decoration_name) x$quantity (Lv?)")
            }
        }
    }

    $rows = @($tally.Values | ForEach-Object {
        [pscustomobject]([ordered]@{
            skill_name = $_.skill_name
            decoration_quantity = $_.decoration_quantity
            known_total_levels = $_.known_total_levels
            has_unknown_level = $_.has_unknown_level
            decorations = ($_.decorations -join ";")
        })
    })
    return @($rows | Sort-Object skill_name)
}

function Summarize-FishCaptures {
    param($Json, $Resolver)

    $records = @()
    foreach ($entry in Get-ArrayValues $Json) {
        $row = Select-Fields $entry @("FixedId", "EnemyState", "CaptureNum", "MaxSize", "MaxWeight")
        $captureNum = if ($row.Contains("capture_num")) { [int64]$row["capture_num"] } else { 0 }
        $enemyState = if ($row.Contains("enemy_state")) { [int64]$row["enemy_state"] } else { 0 }
        if ($captureNum -gt 0 -or $enemyState -ne 0) {
            $resolved = Resolve-EnemyId $Resolver $row["fixed_id"]
            $row = [ordered]@{
                fixed_id = $resolved["fixed_id"]
                enemy_enum = $resolved["enemy_enum"]
                name = $resolved["name"]
                enemy_state = $row["enemy_state"]
                capture_num = $row["capture_num"]
                max_size = $row["max_size"]
                max_weight = $row["max_weight"]
            }
            $records += [pscustomobject]$row
        }
    }

    return [ordered]@{
        total_entries = (Get-ArrayValues $Json).Count
        observed_entries = $records.Count
        records = $records
    }
}

function Summarize-ReportArray {
    param(
        $Json,
        [string]$FieldName,
        $Resolver
    )

    $array = Get-FieldValue -Class $Json -Name $FieldName
    $records = @()
    foreach ($entry in Get-ArrayValues $array) {
        $row = Select-Fields $entry @("FixedId", "EnemyState", "SlayingNum", "CaptureNum", "MixSize", "MinSize", "MaxSize", "MaxWeight")
        $fixedId = if ($row.Contains("fixed_id")) { [int64]$row["fixed_id"] } else { 0 }
        if ($fixedId -eq 0) {
            continue
        }

        $interesting = $false
        foreach ($key in @("enemy_state", "slaying_num", "capture_num", "mix_size", "min_size", "max_size", "max_weight")) {
            if ($row.Contains($key) -and [int64]$row[$key] -ne 0) {
                $interesting = $true
            }
        }
        if ($interesting) {
            $resolved = Resolve-EnemyId $Resolver $row["fixed_id"]
            $row = [ordered]@{
                fixed_id = $resolved["fixed_id"]
                enemy_enum = $resolved["enemy_enum"]
                name = $resolved["name"]
                enemy_state = $row["enemy_state"]
                slaying_num = $row["slaying_num"]
                capture_num = $row["capture_num"]
                mix_size = $row["mix_size"]
                min_size = $row["min_size"]
                max_size = $row["max_size"]
                max_weight = $row["max_weight"]
            }
            $records += [pscustomobject]$row
        }
    }

    return [ordered]@{
        field = $FieldName
        total_entries = (Get-ArrayValues $array).Count
        observed_entries = $records.Count
        records = $records
    }
}

function Summarize-MonsterReport {
    param($Json, $Resolver)

    $sections = [ordered]@{}
    foreach ($fieldName in @("_Boss", "_Zako", "_Animal", "_AnimalFishing")) {
        if ($null -ne (Get-Field -Class $Json -Name $fieldName)) {
            $key = $fieldName.TrimStart("_").ToLowerInvariant()
            $sections[$key] = Summarize-ReportArray $Json $fieldName $Resolver
        }
    }

    return $sections
}

function Summarize-EndemicCaptures {
    param($Json, $Resolver)

    $container = Get-FieldValue -Class $Json -Name "_CaptureContainerParam"
    if ($null -eq $container -or -not $container.fields) {
        $container = $Json
    }

    $sections = [ordered]@{}
    foreach ($field in @($container.fields)) {
        if ($field.value.kind -ne "Array") {
            continue
        }

        $rowsById = @{}
        $nonEmpty = 0
        foreach ($entry in Get-ArrayValues $field.value) {
            $scalars = Get-ClassScalars $entry
            if (-not $scalars.Contains("EmId")) {
                continue
            }

            $emId = [string]$scalars["EmId"]
            if ($emId -eq "0") {
                continue
            }

            $nonEmpty++
            if (-not $rowsById.ContainsKey($emId)) {
                $rowsById[$emId] = [ordered]@{
                    em_id = $scalars["EmId"]
                    count = 0
                    lock_states = @{}
                    option_tags = @{}
                }
            }

            $rowsById[$emId]["count"]++
            foreach ($name in @("IsLocked", "OptionTag")) {
                if ($scalars.Contains($name)) {
                    $value = [string]$scalars[$name]
                    $target = if ($name -eq "IsLocked") { "lock_states" } else { "option_tags" }
                    if (-not $rowsById[$emId][$target].ContainsKey($value)) {
                        $rowsById[$emId][$target][$value] = 0
                    }
                    $rowsById[$emId][$target][$value]++
                }
            }
        }

        $byId = @(
            foreach ($key in ($rowsById.Keys | Sort-Object { [int64]$_ })) {
                $row = $rowsById[$key]
                $resolved = Resolve-EnemyId $Resolver $row["em_id"]
                [pscustomobject]([ordered]@{
                    em_id = $row["em_id"]
                    enemy_enum = $resolved["enemy_enum"]
                    name = $resolved["name"]
                    count = $row["count"]
                    lock_states = $row["lock_states"]
                    option_tags = $row["option_tags"]
                })
            }
        )

        $sections[$field.name.TrimStart("_")] = [ordered]@{
            total_entries = (Get-ArrayValues $field.value).Count
            nonempty_entries = $nonEmpty
            by_em_id = $byId
        }
    }

    return $sections
}

function Convert-MonsterSummaryToRows {
    param($Summary)

    $rows = @()
    foreach ($section in $Summary.Keys) {
        foreach ($record in @($Summary[$section].records)) {
            $row = [ordered]@{ section = $section }
            foreach ($property in $record.PSObject.Properties) {
                $row[$property.Name] = $property.Value
            }
            $rows += [pscustomobject]$row
        }
    }
    return $rows
}

function Convert-EndemicSummaryToRows {
    param($Summary)

    $rows = @()
    foreach ($section in $Summary.Keys) {
        foreach ($record in @($Summary[$section].by_em_id)) {
            $rows += [pscustomobject]([ordered]@{
                section = $section
                em_id = $record.em_id
                enemy_enum = $record.enemy_enum
                name = $record.name
                count = $record.count
                lock_states = Convert-MapToString $record.lock_states
                option_tags = Convert-MapToString $record.option_tags
            })
        }
    }
    return $rows
}

function Build-SkillsTally {
    param([object[]]$Rows)

    function Add-SkillTallyValue {
        param(
            [System.Collections.Specialized.OrderedDictionary]$Tally,
            [string]$Skill,
            [nullable[int]]$Level,
            [string]$Source,
            [string]$SlotName,
            [string]$CharmName
        )

        $skill = $Skill.Trim()
        if (-not $skill) { return }
        if (-not $Tally.Contains($skill)) {
            $Tally[$skill] = [ordered]@{
                skill_name = $skill
                deco_count = 0
                deco_levels = 0
                native_in = [System.Collections.Generic.List[string]]::new()
                native_levels = 0
                charm = ''
                charm_level = ''
                known_total_level = 0
                has_unknown_level = $false
            }
        }

        if ($Source -eq 'decoration') {
            $Tally[$skill].deco_count++
            if ($null -ne $Level) {
                $Tally[$skill].deco_levels += [int]$Level
                $Tally[$skill].known_total_level += [int]$Level
            } else {
                $Tally[$skill].has_unknown_level = $true
            }
        }
        elseif ($Source -eq 'charm') {
            $Tally[$skill].charm = $CharmName
            if ($null -ne $Level) {
                $Tally[$skill].charm_level = [string]$Level
                $Tally[$skill].known_total_level += [int]$Level
            } else {
                $Tally[$skill].has_unknown_level = $true
            }
        }
        else {
            $Tally[$skill].native_in.Add($SlotName)
            if ($null -ne $Level) {
                $Tally[$skill].native_levels += [int]$Level
                $Tally[$skill].known_total_level += [int]$Level
            } else {
                $Tally[$skill].has_unknown_level = $true
            }
        }
    }

    function Add-SkillDetailsToTally {
        param(
            [System.Collections.Specialized.OrderedDictionary]$Tally,
            [string]$Details,
            [string]$Source,
            [string]$SlotName,
            [string]$CharmName
        )

        $added = 0
        foreach ($detail in ($Details -split ';')) {
            $detail = $detail.Trim()
            if (-not $detail) { continue }
            if ($detail -match '^(.+?)\s+Lv(\d+|\?)$') {
                $level = $null
                if ($matches[2] -ne '?') { $level = [int]$matches[2] }
                Add-SkillTallyValue $Tally $matches[1] $level $Source $SlotName $CharmName
                $added++
            }
        }
        return $added
    }

    $tally = [ordered]@{}
    foreach ($row in $Rows) {
        $slotName = $row.slot
        # Skip overflow weapon/equipment slots (slot_7, slot_8, …) — only the 7 named slots count.
        if ($slotName -like 'slot_*') { continue }

        $addedDecoDetails = 0
        if ($row.decoration_skill_details) {
            $addedDecoDetails = Add-SkillDetailsToTally $tally $row.decoration_skill_details 'decoration' $slotName ''
        }
        if ($addedDecoDetails -eq 0 -and $row.decoration_skills) {
            foreach ($skill in ($row.decoration_skills -split ';')) {
                Add-SkillTallyValue $tally $skill $null 'decoration' $slotName ''
            }
        }

        $nativeSource = if ($row.kind -eq 'charm') { 'charm' } else { 'native' }
        $addedNativeDetails = 0
        if ($row.native_skill_details) {
            $addedNativeDetails = Add-SkillDetailsToTally $tally $row.native_skill_details $nativeSource $slotName $row.name
        }
        if ($addedNativeDetails -eq 0 -and $row.native_skills) {
            foreach ($skill in ($row.native_skills -split ';')) {
                if ($row.kind -eq 'charm') {
                    Add-SkillTallyValue $tally $skill $null 'charm' $slotName $row.name
                } else {
                    Add-SkillTallyValue $tally $skill $null 'native' $slotName ''
                }
            }
        }
    }

    return @($tally.Values | Sort-Object skill_name | ForEach-Object {
        [pscustomobject][ordered]@{
            skill_name = $_.skill_name
            deco_count = $_.deco_count
            deco_levels = $_.deco_levels
            native_in  = ($_.native_in -join ";")
            native_levels = $_.native_levels
            charm      = $_.charm
            charm_level = $_.charm_level
            known_total_level = $_.known_total_level
            has_unknown_level = $_.has_unknown_level
        }
    })
}

function Summarize-GenericClass {
    param($Json)

    if ($Json.kind -eq "Array") {
        return Summarize-ArrayValue $Json
    }

    $arrays = [ordered]@{}
    $classes = [ordered]@{}
    foreach ($field in @($Json.fields)) {
        if ($field.value.kind -eq "Array") {
            $arrays[$field.name.TrimStart("_")] = Summarize-ArrayValue $field.value
        }
        elseif ($field.value.fields) {
            $nested = Summarize-GenericClass $field.value
            if ($nested.scalars.Count -gt 0 -or $nested.arrays.Count -gt 0 -or $nested.classes.Count -gt 0) {
                $classes[$field.name.TrimStart("_")] = $nested
            }
        }
    }

    return [ordered]@{
        scalars = Get-ClassScalars $Json
        arrays = $arrays
        classes = $classes
    }
}

function Summarize-ArrayValue {
    param($ArrayValue)

    $values = Get-ArrayValues $ArrayValue
    $firstClass = @($values | Where-Object { $_.PSObject.Properties.Name -contains "fields" } | Select-Object -First 1)[0]
    if ($null -eq $firstClass) {
        $nonzeroValues = @()
        for ($index = 0; $index -lt $values.Count; $index++) {
            $value = $values[$index]
            if ($null -ne $value -and $value -ne 0) {
                $nonzeroValues += [pscustomobject]([ordered]@{
                    index = $index
                    value = $value
                })
            }
        }

        return [ordered]@{
            total_entries = $values.Count
            nonzero_entries = $nonzeroValues.Count
            values = $nonzeroValues
        }
    }

    $interesting = @()
    $collapsed = 0
    $index = 0
    foreach ($entry in $values) {
        if ($entry.kind -eq "Class" -and -not $entry.fields) {
            $collapsed++
        }
        else {
            $scalars = Get-NonzeroScalars $entry
            if ($scalars.Count -gt 0) {
                $row = [ordered]@{ index = $index }
                foreach ($key in $scalars.Keys) {
                    $row[$key] = $scalars[$key]
                }
                $interesting += [pscustomobject]$row
            }
        }
        $index++
    }

    return [ordered]@{
        total_entries = $values.Count
        nonzero_entries = $interesting.Count
        collapsed_entries = $collapsed
        entries = $interesting
    }
}

function Get-FlagSetFromGenericSummary {
    param(
        $Summary,
        [Parameter(Mandatory = $true)][string]$ClassName
    )

    $set = @{}
    $classes = Get-ObjectPropertyValue $Summary "classes"
    $flagClass = Get-ObjectPropertyValue $classes $ClassName
    $arrays = Get-ObjectPropertyValue $flagClass "arrays"
    $valueArray = Get-ObjectPropertyValue $arrays "Value"
    $values = @(Get-ObjectPropertyValue $valueArray "values")

    foreach ($entry in $values) {
        $wordIndex = Get-ObjectPropertyValue $entry "index"
        $rawValue = Get-ObjectPropertyValue $entry "value"
        if ($null -eq $wordIndex -or $null -eq $rawValue) { continue }

        $value = [uint64]([Convert]::ToUInt64([string]$rawValue))
        for ($bit = 0; $bit -lt 32; $bit++) {
            $mask = ([uint64]1) -shl $bit
            if (($value -band $mask) -ne 0) {
                $set[([int]$wordIndex * 32 + $bit)] = $true
            }
        }
    }

    return $set
}

function Get-MissionCategoryGuess {
    param([string]$MissionKey)

    if ([string]::IsNullOrWhiteSpace($MissionKey)) { return "" }
    if ($MissionKey -match '^MISSION_10[1-7]\d{3}$') { return "optional" }
    if ($MissionKey -match '^MISSION_109\d{3}$') { return "hunting_exercise" }
    if ($MissionKey -match '^MISSION_199\d{3}$') { return "special_optional_ref" }
    if ($MissionKey -match '^MISSION_20\d{4}$') { return "arena" }
    if ($MissionKey -match '^MISSION_7\d{5}$') { return "event_or_challenge" }
    if ($MissionKey -match '^MISSION_\d{6}$') {
        $number = [int]$MissionKey.Substring("MISSION_".Length)
        if ($number -lt 100000) { return "story_or_assignment" }
    }
    return "other"
}

function Test-IsOptionalQuestLike {
    param([string]$CategoryGuess)

    return @("optional", "hunting_exercise", "special_optional_ref") -contains $CategoryGuess
}

function Summarize-MissionProgress {
    param(
        $MissionSummary,
        $Resolver
    )

    $missionClear = Get-FlagSetFromGenericSummary $MissionSummary "MissionClearFlag"
    $questClear = Get-FlagSetFromGenericSummary $MissionSummary "QuestClearFlag"
    $questActive = Get-FlagSetFromGenericSummary $MissionSummary "QuestActiveFlag"
    $questFailed = Get-FlagSetFromGenericSummary $MissionSummary "QuestFailedFlag"
    $questChecked = Get-FlagSetFromGenericSummary $MissionSummary "QuestCheckFlag"

    $rows = @()
    $missionEnum = Get-ObjectPropertyValue $Resolver "mission_id_enum"
    $missionNames = Get-ObjectPropertyValue $Resolver "mission_names"

    if ($null -ne $missionEnum) {
        foreach ($entry in $missionEnum.GetEnumerator()) {
            $missionKey = [string]$entry.Key
            if (-not $missionKey.StartsWith("MISSION_")) { continue }

            $index = [int]$entry.Value
            $title = [string](Get-ObjectPropertyValue $missionNames $missionKey)
            $hasAnyFlag = $missionClear.ContainsKey($index) -or
                $questClear.ContainsKey($index) -or
                $questActive.ContainsKey($index) -or
                $questFailed.ContainsKey($index) -or
                $questChecked.ContainsKey($index)

            if ([string]::IsNullOrWhiteSpace($title) -and -not $hasAnyFlag) { continue }

            $categoryGuess = Get-MissionCategoryGuess $missionKey
            $rows += [pscustomobject]([ordered]@{
                mission_index = $index
                mission_id = $missionKey
                title = $title
                category_guess = $categoryGuess
                optional_quest_like = Test-IsOptionalQuestLike $categoryGuess
                mission_clear = $missionClear.ContainsKey($index)
                quest_clear = $questClear.ContainsKey($index)
                quest_active = $questActive.ContainsKey($index)
                quest_failed = $questFailed.ContainsKey($index)
                quest_checked = $questChecked.ContainsKey($index)
            })
        }
    }

    $sortedRows = @($rows | Sort-Object mission_index)
    $optionalRows = @($sortedRows | Where-Object { $_.optional_quest_like })
    $optionalCleared = @($optionalRows | Where-Object { $_.mission_clear -or $_.quest_clear })

    return [ordered]@{
        caveats = @(
            "Mission titles are resolved from local message names like Mission######_100.",
            "category_guess is heuristic. Standard optional quests generally use MISSION_101xxx through MISSION_107xxx; hunting exercises and special optional references are tagged separately.",
            "mission_clear and quest_clear are separate save bitsets. Treat either true value as evidence the mission has been cleared."
        )
        total_missions = $sortedRows.Count
        optional_quest_like_count = $optionalRows.Count
        optional_quest_like_cleared_count = $optionalCleared.Count
        missions = $sortedRows
    }
}

function Summarize-ProfileSlots {
    param($Json)

    $slots = @()
    foreach ($slot in @($Json.slots)) {
        $basicData = $slot.basic_data
        $topFields = $slot.top_fields
        $slots += [pscustomobject]([ordered]@{
            slot_index = $slot.slot_index
            active = $slot.active
            hunter_name = Convert-ScalarValue (Get-FieldValue -Class $basicData -Name "CharName")
            palico_name = Convert-ScalarValue (Get-FieldValue -Class $basicData -Name "OtomoName")
            seikret_name = Convert-ScalarValue (Get-FieldValue -Class $basicData -Name "SeikretName")
            pugee_name = Convert-ScalarValue (Get-FieldValue -Class $basicData -Name "PugeeName")
            has_item = [bool]$slot.item_storage_present
            has_equip = [bool]$slot.equipment_storage_present
            has_mission = Test-ClassHasField -Class $topFields -Name "_Mission"
            has_animal = Test-ClassHasField -Class $topFields -Name "_Animal"
            has_collection = Test-ClassHasField -Class $topFields -Name "_Collection"
            has_enemy_report = Test-ClassHasField -Class $topFields -Name "_EnemyReport"
        })
    }

    return [ordered]@{
        source_file = $Json.source_file
        game = $Json.game
        slot_count = $slots.Count
        slots = $slots
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$repoRoot = $repoRoot.Path
$resolvedDumpDir = Resolve-Path $DumpDir
$resolvedDumpDir = $resolvedDumpDir.Path
$copyId = Split-Path -Leaf $resolvedDumpDir
$dumpFreshnessFile = Join-Path $resolvedDumpDir "interpreted-summary.json"

if (-not (Test-IsRepoSubPath -Path $resolvedDumpDir -Root $repoRoot)) {
    throw "DumpDir must be inside this repository."
}

if ($resolvedDumpDir -match "\\2246340\\|\\Steam\\userdata\\|\\win64_save\\") {
    throw "Refusing to read a path that looks like a live Steam/MH Wilds save path."
}

if (-not (Test-Path -LiteralPath $dumpFreshnessFile -PathType Leaf)) {
    throw "Missing interpreted-summary.json in dump dir: $resolvedDumpDir"
}

$dumpFreshnessTime = (Get-Item -LiteralPath $dumpFreshnessFile).LastWriteTime

if (-not $OutDir) {
    $OutDir = Join-Path $repoRoot "memory\private-save\summaries\$copyId"
}

if ([System.IO.Path]::IsPathRooted($OutDir)) {
    $resolvedOutDir = [System.IO.Path]::GetFullPath($OutDir)
}
else {
    $resolvedOutDir = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutDir))
}

if (-not (Test-IsRepoSubPath -Path $resolvedOutDir -Root $repoRoot)) {
    throw "OutDir must be inside this repository."
}

if ($resolvedOutDir -match "\\2246340\\|\\Steam\\userdata\\|\\win64_save\\") {
    throw "Refusing to write a path that looks like a live Steam/MH Wilds save path."
}

New-Item -ItemType Directory -Force -Path $resolvedOutDir | Out-Null
$jsonOutDir = Join-Path $resolvedOutDir "json"
New-Item -ItemType Directory -Force -Path $jsonOutDir | Out-Null
foreach ($pattern in @("*-summary.csv", "profile-summary.csv", "index.json")) {
    Get-ChildItem -LiteralPath $resolvedOutDir -File -Filter $pattern -ErrorAction SilentlyContinue | Remove-Item -Force
}
foreach ($pattern in @("*-summary.json", "profile-summary.json")) {
    Get-ChildItem -LiteralPath $jsonOutDir -File -Filter $pattern -ErrorAction SilentlyContinue | Remove-Item -Force
}

$writtenJson = @()
$writtenCsv = @()
$resolver = Initialize-NameResolver $repoRoot
$localResolver = Initialize-LocalDataResolver $repoRoot

$interpreted = Read-JsonFile (Join-Path $resolvedDumpDir "interpreted-summary.json")
if ($null -ne $interpreted) {
    $profileSummary = Summarize-ProfileSlots $interpreted
    $path = Join-Path $jsonOutDir "profile-summary.json"
    Write-JsonFile $path $profileSummary
    $writtenJson += $path

    $csvPath = Join-Path $resolvedOutDir "profile-summary.csv"
    Write-CsvFile $csvPath @($profileSummary.slots) @(
        "slot_index", "active", "hunter_name", "palico_name", "seikret_name", "pugee_name",
        "has_item", "has_equip", "has_mission", "has_animal", "has_collection", "has_enemy_report"
    )
    $writtenCsv += $csvPath
}

for ($slotIndex = 0; $slotIndex -lt 3; $slotIndex++) {
    $prefix = "slot$slotIndex"

    $itemBox = Read-JsonFile (Join-Path $resolvedDumpDir "$prefix-item-box.json")
    if ($null -ne $itemBox) {
        $itemSummary = Summarize-ItemBox $itemBox $resolver
        $path = Join-Path $jsonOutDir "$prefix-inventory-summary.json"
        Write-JsonFile $path $itemSummary
        $writtenJson += $path

        $csvPath = Join-Path $resolvedOutDir "$prefix-inventory-summary.csv"
        Write-CsvFile $csvPath @($itemSummary.items) @("item_id_fixed", "item_enum", "item_name", "quantity")
        $writtenCsv += $csvPath
    }

    $equipBox = Read-JsonFile (Join-Path $resolvedDumpDir "$prefix-equip-box.json")
    if ($null -ne $equipBox) {
        $equipSummary = Summarize-EquipBox $equipBox $resolver $localResolver
        $path = Join-Path $jsonOutDir "$prefix-equip-summary.json"
        Write-JsonFile $path $equipSummary
        $writtenJson += $path

        $csvPath = Join-Path $resolvedOutDir "$prefix-equip-summary.csv"
        Write-CsvFile $csvPath @($equipSummary.entries) @(
            "index", "kind", "category_gender", "type", "enum", "name", "armor_part",
            "free_val0", "free_val1", "free_val2", "free_val3", "free_val4", "free_val5",
            "bonus_by_creating", "bonus_by_grinding", "grinding_num",
            "customize_or_skill_ids", "bowgun_mod_ids", "bowgun_mod_names", "decoration_ids", "decoration_names",
            "native_skills", "decoration_skills", "native_skill_details", "decoration_skill_details"
        )
        $writtenCsv += $csvPath
    }

    $equipCurrent = Read-JsonFile (Join-Path $resolvedDumpDir "$prefix-equip-current.json")
    if ($null -ne $equipCurrent) {
        $equipCurrentSummary = Summarize-EquipCurrent $equipCurrent $resolver $localResolver
        $path = Join-Path $jsonOutDir "$prefix-equip-current-summary.json"
        Write-JsonFile $path $equipCurrentSummary
        $writtenJson += $path

        $csvPath = Join-Path $resolvedOutDir "$prefix-equip-current-summary.csv"
        Write-CsvFile $csvPath @($equipCurrentSummary.slots) @(
            "slot", "slot_index", "index", "kind", "category_gender", "type", "enum", "name", "armor_part",
            "free_val0", "free_val1", "free_val2", "free_val3", "free_val4", "free_val5",
            "bonus_by_creating", "bonus_by_grinding", "grinding_num",
            "customize_or_skill_ids", "bowgun_mod_ids", "bowgun_mod_names", "decoration_ids", "decoration_names",
            "native_skills", "decoration_skills", "native_skill_details", "decoration_skill_details"
        )
        $writtenCsv += $csvPath

        $tallyRows = Build-SkillsTally $equipCurrentSummary.slots
        $csvPath = Join-Path $resolvedOutDir "$prefix-skills-summary.csv"
        Write-CsvFile $csvPath $tallyRows @(
            "skill_name", "deco_count", "deco_levels", "native_in", "native_levels",
            "charm", "charm_level", "known_total_level", "has_unknown_level"
        )
        $writtenCsv += $csvPath

        $decorationSummary = Summarize-DecorationBox $equipCurrent $resolver $localResolver
        $path = Join-Path $jsonOutDir "$prefix-decorations-summary.json"
        Write-JsonFile $path $decorationSummary
        $writtenJson += $path

        $csvPath = Join-Path $resolvedOutDir "$prefix-decorations-summary.csv"
        Write-CsvFile $csvPath @($decorationSummary.decorations) @(
            "accessory_id", "decoration_name", "decoration_type", "slot_level",
            "rarity", "quantity", "skills", "skill_details"
        )
        $writtenCsv += $csvPath

        $decorationSkillRows = Build-DecorationSkillsTally $decorationSummary.decorations
        $csvPath = Join-Path $resolvedOutDir "$prefix-decoration-skills-summary.csv"
        Write-CsvFile $csvPath $decorationSkillRows @(
            "skill_name", "decoration_quantity", "known_total_levels",
            "has_unknown_level", "decorations"
        )
        $writtenCsv += $csvPath
    }

    $fish = Read-JsonFile (Join-Path $resolvedDumpDir "$prefix-fish-captures.json")
    if ($null -ne $fish) {
        $fishSummary = Summarize-FishCaptures $fish $resolver
        $path = Join-Path $jsonOutDir "$prefix-fishing-summary.json"
        Write-JsonFile $path $fishSummary
        $writtenJson += $path

        $csvPath = Join-Path $resolvedOutDir "$prefix-fishing-summary.csv"
        Write-CsvFile $csvPath @($fishSummary.records) @(
            "fixed_id", "enemy_enum", "name", "enemy_state", "capture_num", "max_size", "max_weight"
        )
        $writtenCsv += $csvPath
    }

    $monster = Read-JsonFile (Join-Path $resolvedDumpDir "$prefix-monster-report.json")
    if ($null -ne $monster) {
        $monsterSummary = Summarize-MonsterReport $monster $resolver
        $path = Join-Path $jsonOutDir "$prefix-monster-report-summary.json"
        Write-JsonFile $path $monsterSummary
        $writtenJson += $path

        $csvPath = Join-Path $resolvedOutDir "$prefix-monster-report-summary.csv"
        Write-CsvFile $csvPath (Convert-MonsterSummaryToRows $monsterSummary) @(
            "section", "fixed_id", "enemy_enum", "name", "enemy_state", "slaying_num",
            "capture_num", "mix_size", "min_size", "max_size", "max_weight"
        )
        $writtenCsv += $csvPath
    }

    $endemic = Read-JsonFile (Join-Path $resolvedDumpDir "$prefix-endemic-captures.json")
    if ($null -ne $endemic) {
        $endemicSummary = Summarize-EndemicCaptures $endemic $resolver
        $path = Join-Path $jsonOutDir "$prefix-endemic-summary.json"
        Write-JsonFile $path $endemicSummary
        $writtenJson += $path

        $csvPath = Join-Path $resolvedOutDir "$prefix-endemic-summary.csv"
        Write-CsvFile $csvPath (Convert-EndemicSummaryToRows $endemicSummary) @(
            "section", "em_id", "enemy_enum", "name", "count", "lock_states", "option_tags"
        )
        $writtenCsv += $csvPath
    }

    foreach ($name in @("story", "mission", "quest-record", "delivery-bounty", "camp")) {
        $json = Read-JsonFile (Join-Path $resolvedDumpDir "$prefix-$name.json")
        if ($null -ne $json) {
            $summaryName = $name -replace "-box$", ""
            $summary = Summarize-GenericClass $json
            $path = Join-Path $jsonOutDir "$prefix-$summaryName-summary.json"
            Write-JsonFile $path $summary
            $writtenJson += $path

            if ($name -eq "mission") {
                $missionProgress = Summarize-MissionProgress -MissionSummary $summary -Resolver $resolver
                $progressPath = Join-Path $jsonOutDir "$prefix-mission-progress-summary.json"
                Write-JsonFile $progressPath $missionProgress
                $writtenJson += $progressPath

                $csvPath = Join-Path $resolvedOutDir "$prefix-mission-progress-summary.csv"
                Write-CsvFile $csvPath @($missionProgress.missions) @(
                    "mission_index", "mission_id", "title", "category_guess", "optional_quest_like",
                    "mission_clear", "quest_clear", "quest_active", "quest_failed", "quest_checked"
                )
                $writtenCsv += $csvPath
            }
        }
    }
}

$index = [ordered]@{
    source_dump_dir = $resolvedDumpDir
    output_dir = $resolvedOutDir
    json_dir = $jsonOutDir
    generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    names_resolved = ($null -ne $resolver)
    csv_files = @($writtenCsv | ForEach-Object { Split-Path -Leaf $_ })
    json_files = @($writtenJson | ForEach-Object { Split-Path -Leaf $_ })
}

Write-JsonFile (Join-Path $resolvedOutDir "index.json") $index

$clearedOverrideFiles = Clear-BuildOverridesForCopy -RepoRoot $repoRoot -CopyId $copyId -DumpFreshnessTime $dumpFreshnessTime
if ($clearedOverrideFiles.Count -gt 0) {
    Write-Host "Cleared stale private build override files for copy '$copyId': $($clearedOverrideFiles -join ', ')"
}

Write-Host "Wrote $($writtenCsv.Count) CSV and $($writtenJson.Count + 1) JSON summary files to $resolvedOutDir (JSON in json\)"
