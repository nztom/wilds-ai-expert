param(
    [Parameter(Mandatory = $true)]
    [string]$DumpDir,

    [string]$OutDir,

    [switch]$NoResolveNames
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
    foreach ($message in $messageMap.Values) {
        $messageName = Get-ObjectPropertyValue $message "name"
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

    return [pscustomobject]@{
        enums = $enums
        mappings = $mappings
        item_fixed_enum = $itemFixedEnum
        enemy_fixed_enum = $enemyFixedEnum
        item_message_map = $itemMessageMap
        accessory_id_enum = (Get-ObjectPropertyValue $enums "app.EquipDef.ACCESSORY_ID")
        accessory_fixed_enum = (Get-ObjectPropertyValue $enums "app.EquipDef.ACCESSORY_ID_Fixed")
        accessory_hash_to_name = $accessoryHashToName
        messages = $messageMap
        enemy_names = $enemyNames
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

function Convert-EquipEntryToRow {
    param(
        [Parameter(Mandatory = $true)]
        $Entry,
        [int]$Index,
        $Resolver
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
        decoration_ids = $decorationIds
        decoration_names = $decorationNames
    })
}

function Summarize-EquipBox {
    param($Json, $Resolver)

    $rows = @()
    $index = 0
    foreach ($entry in Get-ArrayValues $Json) {
        $row = Convert-EquipEntryToRow -Entry $entry -Index $index -Resolver $Resolver
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
            "Decoration names are resolved from local Wilds assets. The raw numeric IDs are also retained in decoration_ids for cross-reference."
        )
    }
}

function Summarize-EquipCurrent {
    param($Json, $Resolver)

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
        $row = Convert-EquipEntryToRow -Entry $entry -Index $boxIdx -Resolver $Resolver
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
            "Decoration names are resolved from local Wilds assets. The raw numeric IDs are also retained in decoration_ids for cross-reference."
        )
    }
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

if (-not (Test-IsRepoSubPath -Path $resolvedDumpDir -Root $repoRoot)) {
    throw "DumpDir must be inside this repository."
}

if ($resolvedDumpDir -match "\\2246340\\|\\Steam\\userdata\\|\\win64_save\\") {
    throw "Refusing to read a path that looks like a live Steam/MH Wilds save path."
}

if (-not $OutDir) {
    $copyId = Split-Path -Leaf $resolvedDumpDir
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
Get-ChildItem -LiteralPath $resolvedOutDir -File -Filter "*.json" -ErrorAction SilentlyContinue | Remove-Item -Force
Get-ChildItem -LiteralPath $resolvedOutDir -File -Filter "*.csv" -ErrorAction SilentlyContinue | Remove-Item -Force

$written = @()
$resolver = if ($NoResolveNames) { $null } else { Initialize-NameResolver $repoRoot }

$interpreted = Read-JsonFile (Join-Path $resolvedDumpDir "interpreted-summary.json")
if ($null -ne $interpreted) {
    $profileSummary = Summarize-ProfileSlots $interpreted
    $path = Join-Path $resolvedOutDir "profile-summary.json"
    Write-JsonFile $path $profileSummary
    $written += $path

    $csvPath = Join-Path $resolvedOutDir "profile-summary.csv"
    Write-CsvFile $csvPath @($profileSummary.slots) @(
        "slot_index", "active", "hunter_name", "palico_name", "seikret_name", "pugee_name",
        "has_item", "has_equip", "has_mission", "has_animal", "has_collection", "has_enemy_report"
    )
    $written += $csvPath
}

for ($slotIndex = 0; $slotIndex -lt 3; $slotIndex++) {
    $prefix = "slot$slotIndex"

    $itemBox = Read-JsonFile (Join-Path $resolvedDumpDir "$prefix-item-box.json")
    if ($null -ne $itemBox) {
        $itemSummary = Summarize-ItemBox $itemBox $resolver
        $path = Join-Path $resolvedOutDir "$prefix-inventory-summary.json"
        Write-JsonFile $path $itemSummary
        $written += $path

        $csvPath = Join-Path $resolvedOutDir "$prefix-inventory-summary.csv"
        Write-CsvFile $csvPath @($itemSummary.items) @("item_id_fixed", "item_enum", "item_name", "quantity")
        $written += $csvPath
    }

    $equipBox = Read-JsonFile (Join-Path $resolvedDumpDir "$prefix-equip-box.json")
    if ($null -ne $equipBox) {
        $equipSummary = Summarize-EquipBox $equipBox $resolver
        $path = Join-Path $resolvedOutDir "$prefix-equip-summary.json"
        Write-JsonFile $path $equipSummary
        $written += $path

        $csvPath = Join-Path $resolvedOutDir "$prefix-equip-summary.csv"
        Write-CsvFile $csvPath @($equipSummary.entries) @(
            "index", "kind", "category_gender", "type", "enum", "name", "armor_part",
            "free_val0", "free_val1", "free_val2", "free_val3", "free_val4", "free_val5",
            "bonus_by_creating", "bonus_by_grinding", "grinding_num",
            "customize_or_skill_ids", "decoration_ids", "decoration_names"
        )
        $written += $csvPath
    }

    $equipCurrent = Read-JsonFile (Join-Path $resolvedDumpDir "$prefix-equip-current.json")
    if ($null -ne $equipCurrent) {
        $equipCurrentSummary = Summarize-EquipCurrent $equipCurrent $resolver
        $path = Join-Path $resolvedOutDir "$prefix-equip-current-summary.json"
        Write-JsonFile $path $equipCurrentSummary
        $written += $path

        $csvPath = Join-Path $resolvedOutDir "$prefix-equip-current-summary.csv"
        Write-CsvFile $csvPath @($equipCurrentSummary.slots) @(
            "slot", "slot_index", "index", "kind", "category_gender", "type", "enum", "name", "armor_part",
            "free_val0", "free_val1", "free_val2", "free_val3", "free_val4", "free_val5",
            "bonus_by_creating", "bonus_by_grinding", "grinding_num",
            "customize_or_skill_ids", "decoration_ids", "decoration_names"
        )
        $written += $csvPath
    }

    $fish = Read-JsonFile (Join-Path $resolvedDumpDir "$prefix-fish-captures.json")
    if ($null -ne $fish) {
        $fishSummary = Summarize-FishCaptures $fish $resolver
        $path = Join-Path $resolvedOutDir "$prefix-fishing-summary.json"
        Write-JsonFile $path $fishSummary
        $written += $path

        $csvPath = Join-Path $resolvedOutDir "$prefix-fishing-summary.csv"
        Write-CsvFile $csvPath @($fishSummary.records) @(
            "fixed_id", "enemy_enum", "name", "enemy_state", "capture_num", "max_size", "max_weight"
        )
        $written += $csvPath
    }

    $monster = Read-JsonFile (Join-Path $resolvedDumpDir "$prefix-monster-report.json")
    if ($null -ne $monster) {
        $monsterSummary = Summarize-MonsterReport $monster $resolver
        $path = Join-Path $resolvedOutDir "$prefix-monster-report-summary.json"
        Write-JsonFile $path $monsterSummary
        $written += $path

        $csvPath = Join-Path $resolvedOutDir "$prefix-monster-report-summary.csv"
        Write-CsvFile $csvPath (Convert-MonsterSummaryToRows $monsterSummary) @(
            "section", "fixed_id", "enemy_enum", "name", "enemy_state", "slaying_num",
            "capture_num", "mix_size", "min_size", "max_size", "max_weight"
        )
        $written += $csvPath
    }

    $endemic = Read-JsonFile (Join-Path $resolvedDumpDir "$prefix-endemic-captures.json")
    if ($null -ne $endemic) {
        $endemicSummary = Summarize-EndemicCaptures $endemic $resolver
        $path = Join-Path $resolvedOutDir "$prefix-endemic-summary.json"
        Write-JsonFile $path $endemicSummary
        $written += $path

        $csvPath = Join-Path $resolvedOutDir "$prefix-endemic-summary.csv"
        Write-CsvFile $csvPath (Convert-EndemicSummaryToRows $endemicSummary) @(
            "section", "em_id", "enemy_enum", "name", "count", "lock_states", "option_tags"
        )
        $written += $csvPath
    }

    foreach ($name in @("story", "mission", "quest-record", "delivery-bounty", "camp")) {
        $json = Read-JsonFile (Join-Path $resolvedDumpDir "$prefix-$name.json")
        if ($null -ne $json) {
            $summaryName = $name -replace "-box$", ""
            $summary = Summarize-GenericClass $json
            $path = Join-Path $resolvedOutDir "$prefix-$summaryName-summary.json"
            Write-JsonFile $path $summary
            $written += $path
        }
    }
}

$index = [ordered]@{
    source_dump_dir = $resolvedDumpDir
    output_dir = $resolvedOutDir
    generated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    names_resolved = ($null -ne $resolver)
    files = @($written | ForEach-Object { Split-Path -Leaf $_ })
}

Write-JsonFile (Join-Path $resolvedOutDir "index.json") $index

Write-Host "Wrote $($written.Count + 1) summary files to $resolvedOutDir"
