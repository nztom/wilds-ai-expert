use ree_lib::{
    save::{
        game::Game,
        types::{Array, Class, EnumValue, FieldValue},
        SaveFile, SaveOptions,
    },
    sdk::type_map::{FieldInfo, TypeInfo, TypeMap},
};
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    env,
    error::Error,
    fs::{self, File},
    io::BufWriter,
    path::PathBuf,
};

fn value_preview(value: &FieldValue) -> Value {
    match value {
        FieldValue::Array(v) => json!({
            "kind": "Array",
            "member_type": format!("{:?}", v.member_type),
            "array_type": format!("{:?}", v.array_type),
            "len": v.values.len(),
        }),
        FieldValue::Unknown => json!({ "kind": "Unknown" }),
        FieldValue::Enum(v) => match v {
            EnumValue::E1(x) => json!(x),
            EnumValue::E2(x) => json!(x),
            EnumValue::E4(x) => json!(x),
            EnumValue::E8(x) => json!(x),
        },
        FieldValue::Boolean(v) => json!(v),
        FieldValue::S8(v) => json!(v),
        FieldValue::U8(v) => json!(v),
        FieldValue::S16(v) => json!(v),
        FieldValue::U16(v) => json!(v),
        FieldValue::S32(v) => json!(v),
        FieldValue::U32(v) => json!(v),
        FieldValue::S64(v) => json!(v),
        FieldValue::U64(v) => json!(v),
        FieldValue::F32(v) => json!(v),
        FieldValue::F64(v) => json!(v),
        FieldValue::C8(v) => json!(v),
        FieldValue::C16(v) => json!(v),
        FieldValue::String(v) => json!(String::from_utf16_lossy(&v.0)),
        FieldValue::Struct(v) => json!({ "kind": "Struct", "len": v.data.len() }),
        FieldValue::Class(v) => json!({
            "kind": "Class",
            "hash": format!("{:#010x}", v.hash),
            "num_fields": v.num_fields,
        }),
    }
}

fn field_info<'a>(class_info: Option<&'a TypeInfo>, hash: u32) -> Option<&'a FieldInfo> {
    class_info.and_then(|info| info.get_by_hash(hash))
}

fn type_name<'a>(
    type_map: &'a TypeMap,
    crc_map: &'a HashMap<u32, &'a TypeInfo>,
    hash: u32,
) -> Option<&'a str> {
    type_map
        .get_by_hash(hash)
        .or_else(|| crc_map.get(&hash).copied())
        .map(|info| info.name.as_str())
}

// Two function families are used intentionally:
//
//   Summary family (class_to_named_json / named_value_json / array_to_named_json):
//     Arrays truncated to first 10 elements. Used only for interpreted-summary.json.
//     Produces a compact structural overview (~10–30 k tokens for a full save).
//
//   Full family (class_to_json_full / named_value_full_json / array_to_json_full):
//     No array truncation. Used for targeted output files.
//     "values" key instead of "first_values"+"truncated".
//
// In both families, scalars (strings, ints, bools, enums) are always emitted as
// their actual value. The depth limit only gates recursion into Class and Array
// nodes; when exceeded they collapse to a shape-only preview.
//
// To add a new targeted extraction: write an extract_* fn using the full family,
// call it in the per-slot loop in main, and write output with write_json.

// --- summary walk: arrays truncated to first 10 ---

fn class_to_named_json(
    class: &Class,
    type_map: &TypeMap,
    crc_map: &HashMap<u32, &TypeInfo>,
    depth: usize,
    max_depth: usize,
) -> Value {
    let class_info = type_map
        .get_by_hash(class.hash)
        .or_else(|| crc_map.get(&class.hash).copied());
    let fields = class
        .fields
        .iter()
        .map(|field| {
            let info = field_info(class_info, field.hash);
            json!({
                "hash": format!("{:#010x}", field.hash),
                "name": info.map(|f| f.name.as_str()),
                "declared_type": info.map(|f| f.original_type.as_str()),
                "field_type": format!("{:?}", field.field_type),
                "value": named_value_json(&field.value, type_map, crc_map, depth + 1, max_depth),
            })
        })
        .collect::<Vec<_>>();

    json!({
        "hash": format!("{:#010x}", class.hash),
        "type_name": type_name(type_map, crc_map, class.hash),
        "num_fields": class.num_fields,
        "fields": fields,
    })
}

fn named_value_json(
    value: &FieldValue,
    type_map: &TypeMap,
    crc_map: &HashMap<u32, &TypeInfo>,
    depth: usize,
    max_depth: usize,
) -> Value {
    if depth > max_depth {
        return value_preview(value);
    }
    match value {
        FieldValue::Class(v) => class_to_named_json(v, type_map, crc_map, depth, max_depth),
        FieldValue::Array(v) => array_to_named_json(v, type_map, crc_map, depth, max_depth),
        _ => value_preview(value),
    }
}

fn array_to_named_json(
    array: &Array,
    type_map: &TypeMap,
    crc_map: &HashMap<u32, &TypeInfo>,
    depth: usize,
    max_depth: usize,
) -> Value {
    let values = array
        .values
        .iter()
        .take(10)
        .map(|value| named_value_json(value, type_map, crc_map, depth + 1, max_depth))
        .collect::<Vec<_>>();
    json!({
        "kind": "Array",
        "member_type": format!("{:?}", array.member_type),
        "member_size": array.member_size,
        "array_type": format!("{:?}", array.array_type),
        "len": array.values.len(),
        "first_values": values,
        "truncated": array.values.len() > 10,
    })
}

// --- targeted passes: arrays fully expanded, no truncation ---

fn as_class(value: &FieldValue) -> Option<&Class> {
    match value {
        FieldValue::Class(c) => Some(c.as_ref()),
        _ => None,
    }
}

fn as_array(value: &FieldValue) -> Option<&Array> {
    match value {
        FieldValue::Array(a) => Some(a),
        _ => None,
    }
}

fn class_to_json_full(
    class: &Class,
    type_map: &TypeMap,
    crc_map: &HashMap<u32, &TypeInfo>,
    depth: usize,
    max_depth: usize,
) -> Value {
    let class_info = type_map
        .get_by_hash(class.hash)
        .or_else(|| crc_map.get(&class.hash).copied());
    let fields = class
        .fields
        .iter()
        .map(|field| {
            let info = field_info(class_info, field.hash);
            json!({
                "hash": format!("{:#010x}", field.hash),
                "name": info.map(|f| f.name.as_str()),
                "declared_type": info.map(|f| f.original_type.as_str()),
                "field_type": format!("{:?}", field.field_type),
                "value": named_value_full_json(&field.value, type_map, crc_map, depth + 1, max_depth),
            })
        })
        .collect::<Vec<_>>();
    json!({
        "hash": format!("{:#010x}", class.hash),
        "type_name": type_name(type_map, crc_map, class.hash),
        "num_fields": class.num_fields,
        "fields": fields,
    })
}

fn named_value_full_json(
    value: &FieldValue,
    type_map: &TypeMap,
    crc_map: &HashMap<u32, &TypeInfo>,
    depth: usize,
    max_depth: usize,
) -> Value {
    if depth > max_depth {
        return value_preview(value);
    }
    match value {
        FieldValue::Class(v) => class_to_json_full(v, type_map, crc_map, depth, max_depth),
        FieldValue::Array(v) => array_to_json_full(v, type_map, crc_map, depth, max_depth),
        _ => value_preview(value),
    }
}

fn array_to_json_full(
    array: &Array,
    type_map: &TypeMap,
    crc_map: &HashMap<u32, &TypeInfo>,
    depth: usize,
    max_depth: usize,
) -> Value {
    let values = array
        .values
        .iter()
        .map(|value| named_value_full_json(value, type_map, crc_map, depth + 1, max_depth))
        .collect::<Vec<_>>();
    json!({
        "kind": "Array",
        "member_type": format!("{:?}", array.member_type),
        "member_size": array.member_size,
        "array_type": format!("{:?}", array.array_type),
        "len": array.values.len(),
        "values": values,
    })
}

// max_depth=4: piece(0) → fields(1) → deco-slot array(2) → deco class(3) → deco fields(4)
fn extract_equip_box(
    slot: &Class,
    type_map: &TypeMap,
    crc_map: &HashMap<u32, &TypeInfo>,
) -> Option<Value> {
    let equip = get_field(slot, &["_Equip"]).and_then(as_class)?;
    let arr = get_field(equip, &["_EquipBox"]).and_then(as_array)?;
    Some(array_to_json_full(arr, type_map, crc_map, 0, 4))
}

// max_depth=3: _Equip fields(0) -> current index classes/arrays(1) -> values(2)
fn extract_equip_current(
    slot: &Class,
    type_map: &TypeMap,
    crc_map: &HashMap<u32, &TypeInfo>,
) -> Option<Value> {
    let equip = get_field(slot, &["_Equip"]).and_then(as_class)?;
    Some(class_to_json_full(equip, type_map, crc_map, 0, 3))
}

// max_depth=2: item class(0) → ID and count fields(1)
fn extract_item_box(
    slot: &Class,
    type_map: &TypeMap,
    crc_map: &HashMap<u32, &TypeInfo>,
) -> Option<Value> {
    let item = get_field(slot, &["_Item"]).and_then(as_class)?;
    let arr = get_field(item, &["_BoxItem"]).and_then(as_array)?;
    Some(array_to_json_full(arr, type_map, crc_map, 0, 2))
}

// max_depth=3: _Mission fields(0) → quest flag arrays(1) → quest entry class(2) → entry fields(3)
fn extract_mission(
    slot: &Class,
    type_map: &TypeMap,
    crc_map: &HashMap<u32, &TypeInfo>,
) -> Option<Value> {
    let mission = get_field(slot, &["_Mission"]).and_then(as_class)?;
    Some(class_to_json_full(mission, type_map, crc_map, 0, 3))
}

// max_depth=3: _Animal fields(0) → capture arrays(1) → entry class(2) → entry fields(3)
fn extract_endemic_captures(
    slot: &Class,
    type_map: &TypeMap,
    crc_map: &HashMap<u32, &TypeInfo>,
) -> Option<Value> {
    let animal = get_field(slot, &["_Animal"]).and_then(as_class)?;
    Some(class_to_json_full(animal, type_map, crc_map, 0, 3))
}

// max_depth=3: _AnimalFishing array(0) → fish report class(1) → entry fields(2)
fn extract_fish_captures(
    slot: &Class,
    type_map: &TypeMap,
    crc_map: &HashMap<u32, &TypeInfo>,
) -> Option<Value> {
    let enemy_report = get_field(slot, &["_EnemyReport"]).and_then(as_class)?;
    let animal_fishing = get_field(enemy_report, &["_AnimalFishing"]).and_then(as_array)?;
    Some(array_to_json_full(animal_fishing, type_map, crc_map, 0, 3))
}

// max_depth=3: _EnemyReport fields(0) → report arrays(1) → report entry class(2) → entry fields(3)
fn extract_monster_report(
    slot: &Class,
    type_map: &TypeMap,
    crc_map: &HashMap<u32, &TypeInfo>,
) -> Option<Value> {
    let enemy_report = get_field(slot, &["_EnemyReport"]).and_then(as_class)?;
    Some(class_to_json_full(enemy_report, type_map, crc_map, 0, 3))
}

// max_depth=3: _Story fields(0) → bitsets/classes(1) → arrays/values(2) → entries(3)
fn extract_story(
    slot: &Class,
    type_map: &TypeMap,
    crc_map: &HashMap<u32, &TypeInfo>,
) -> Option<Value> {
    let story = get_field(slot, &["_Story"]).and_then(as_class)?;
    Some(class_to_json_full(story, type_map, crc_map, 0, 3))
}

// max_depth=3: _QuestRecord fields(0) → record arrays(1) → entry class(2) → entry fields(3)
fn extract_quest_record(
    slot: &Class,
    type_map: &TypeMap,
    crc_map: &HashMap<u32, &TypeInfo>,
) -> Option<Value> {
    let quest_record = get_field(slot, &["_QuestRecord"]).and_then(as_class)?;
    Some(class_to_json_full(quest_record, type_map, crc_map, 0, 3))
}

// max_depth=5: _DeliveryBounty fields(0) → bounty arrays(1) → entry class(2) → nested
// _Data class(3) → nested arrays/classes(4) → entry fields(5)
fn extract_delivery_bounty(
    slot: &Class,
    type_map: &TypeMap,
    crc_map: &HashMap<u32, &TypeInfo>,
) -> Option<Value> {
    let delivery_bounty = get_field(slot, &["_DeliveryBounty"]).and_then(as_class)?;
    Some(class_to_json_full(delivery_bounty, type_map, crc_map, 0, 5))
}

// max_depth=3: _Camp fields(0) → camp arrays(1) → entry class(2) → entry fields(3)
fn extract_camp(
    slot: &Class,
    type_map: &TypeMap,
    crc_map: &HashMap<u32, &TypeInfo>,
) -> Option<Value> {
    let camp = get_field(slot, &["_Camp"]).and_then(as_class)?;
    Some(class_to_json_full(camp, type_map, crc_map, 0, 3))
}

// max_depth=3: _HunterProfile fields(0) -> counter arrays/classes(1) -> values(2)
fn extract_hunter_profile(
    slot: &Class,
    type_map: &TypeMap,
    crc_map: &HashMap<u32, &TypeInfo>,
) -> Option<Value> {
    let hunter_profile = get_field(slot, &["_HunterProfile"]).and_then(as_class)?;
    Some(class_to_json_full(hunter_profile, type_map, crc_map, 0, 3))
}

fn get_field<'a>(class: &'a Class, names: &[&str]) -> Option<&'a FieldValue> {
    for name in names {
        let hash = TypeMap::get_hash(name);
        if let Some(field) = class.fields.iter().find(|field| field.hash == hash) {
            return Some(&field.value);
        }
    }
    None
}

fn array_classes(value: &FieldValue) -> Vec<&Class> {
    match value {
        FieldValue::Array(array) => array
            .values
            .iter()
            .filter_map(|value| match value {
                FieldValue::Class(class) => Some(class.as_ref()),
                _ => None,
            })
            .collect(),
        _ => Vec::new(),
    }
}

fn write_json(path: &PathBuf, value: &Value) -> Result<(), Box<dyn Error>> {
    let file = File::create(path)?;
    serde_json::to_writer_pretty(BufWriter::new(file), value)?;
    println!("Wrote {}", path.display());
    Ok(())
}

fn main() -> Result<(), Box<dyn Error>> {
    let args = env::args().collect::<Vec<_>>();
    if args.len() != 6 {
        return Err("usage: mhwilds_interpret_save <save-file> <steamid64> <rsz-json> <enums-json> <out-dir>".into());
    }

    let save_path = PathBuf::from(&args[1]);
    let steamid = args[2].parse::<u64>()?;
    let rsz_path = &args[3];
    let enums_path = &args[4];
    let out_dir = PathBuf::from(&args[5]);
    fs::create_dir_all(&out_dir)?;

    let type_map = TypeMap::load_from_file(rsz_path, enums_path)?;
    let crc_map = type_map
        .types
        .0
        .values()
        .map(|info| (info.crc, info))
        .collect::<HashMap<_, _>>();

    let mut options = SaveOptions::new(Game::MHWILDS).id(steamid);
    let save = SaveFile::load(&save_path, &mut options)?;

    let top_level = save
        .fields
        .iter()
        .map(|(hash, class)| {
            json!({
                "hash": format!("{:#010x}", hash),
                "class": class_to_named_json(class, &type_map, &crc_map, 0, 2),
            })
        })
        .collect::<Vec<_>>();

    let mut slot_summaries = Vec::new();
    if let Some((_, first_root)) = save.fields.first() {
        if let Some(data_value) = get_field(first_root, &["_Data"]) {
            for (slot_index, slot) in array_classes(data_value).into_iter().enumerate() {
                let basic = get_field(slot, &["_BasicData"]);
                let item = get_field(slot, &["_Item"]);
                let equip = get_field(slot, &["_Equip"]);
                slot_summaries.push(json!({
                    "slot_index": slot_index,
                    "slot_class_hash": format!("{:#010x}", slot.hash),
                    "slot_type_name": type_name(&type_map, &crc_map, slot.hash),
                    "active": get_field(slot, &["Active"]).map(value_preview),
                    "hunter_id_present": get_field(slot, &["HunterId"]).is_some(),
                    "hunter_short_id_present": get_field(slot, &["HunterShortId"]).is_some(),
                    "basic_data": basic.map(|v| named_value_json(v, &type_map, &crc_map, 0, 1)),
                    "item_storage_present": item.is_some(),
                    "equipment_storage_present": equip.is_some(),
                    "top_fields": class_to_named_json(slot, &type_map, &crc_map, 0, 1),
                }));

                if let Some(v) = extract_equip_box(slot, &type_map, &crc_map) {
                    write_json(&out_dir.join(format!("slot{slot_index}-equip-box.json")), &v)?;
                }
                if let Some(v) = extract_equip_current(slot, &type_map, &crc_map) {
                    write_json(
                        &out_dir.join(format!("slot{slot_index}-equip-current.json")),
                        &v,
                    )?;
                }
                if let Some(v) = extract_item_box(slot, &type_map, &crc_map) {
                    write_json(&out_dir.join(format!("slot{slot_index}-item-box.json")), &v)?;
                }
                if let Some(v) = extract_mission(slot, &type_map, &crc_map) {
                    write_json(&out_dir.join(format!("slot{slot_index}-mission.json")), &v)?;
                }
                if let Some(v) = extract_endemic_captures(slot, &type_map, &crc_map) {
                    write_json(
                        &out_dir.join(format!("slot{slot_index}-endemic-captures.json")),
                        &v,
                    )?;
                }
                if let Some(v) = extract_fish_captures(slot, &type_map, &crc_map) {
                    write_json(
                        &out_dir.join(format!("slot{slot_index}-fish-captures.json")),
                        &v,
                    )?;
                }
                if let Some(v) = extract_monster_report(slot, &type_map, &crc_map) {
                    write_json(
                        &out_dir.join(format!("slot{slot_index}-monster-report.json")),
                        &v,
                    )?;
                }
                if let Some(v) = extract_story(slot, &type_map, &crc_map) {
                    write_json(&out_dir.join(format!("slot{slot_index}-story.json")), &v)?;
                }
                if let Some(v) = extract_quest_record(slot, &type_map, &crc_map) {
                    write_json(
                        &out_dir.join(format!("slot{slot_index}-quest-record.json")),
                        &v,
                    )?;
                }
                if let Some(v) = extract_delivery_bounty(slot, &type_map, &crc_map) {
                    write_json(
                        &out_dir.join(format!("slot{slot_index}-delivery-bounty.json")),
                        &v,
                    )?;
                }
                if let Some(v) = extract_camp(slot, &type_map, &crc_map) {
                    write_json(&out_dir.join(format!("slot{slot_index}-camp.json")), &v)?;
                }
                if let Some(v) = extract_hunter_profile(slot, &type_map, &crc_map) {
                    write_json(
                        &out_dir.join(format!("slot{slot_index}-hunter-profile.json")),
                        &v,
                    )?;
                }
            }
        }
    }

    let interpreted = json!({
        "source_file": save_path.display().to_string(),
        "game": format!("{:?}", save.game),
        "flags": format!("{:?}", save.flags),
        "top_level_field_count": save.fields.len(),
        "top_level": top_level,
        "slots": slot_summaries,
    });

    write_json(&out_dir.join("interpreted-summary.json"), &interpreted)?;
    Ok(())
}
