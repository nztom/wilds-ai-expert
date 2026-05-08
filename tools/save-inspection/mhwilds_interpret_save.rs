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

    let file = File::create(out_dir.join("interpreted-summary.json"))?;
    serde_json::to_writer_pretty(BufWriter::new(file), &interpreted)?;
    println!("Wrote {}", out_dir.join("interpreted-summary.json").display());
    Ok(())
}
