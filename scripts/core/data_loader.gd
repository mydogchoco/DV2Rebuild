extends Node
## Autoload "Data": loads master data (data/*.json) and computes dragon stats.
## Master data is restored by the user (see docs/game_design.md), not in assets.

var dragons: Dictionary = {}     # id(int) -> dragon dict
var stat_table: Dictionary = {}  # type -> tier -> {base,growth}

const STAGE_BREAKS := {"baby": 9, "child": 19}  # <=9 baby, <=19 child, else adult

func _ready() -> void:
	_load_dragons("res://data/dragons.json")
	stat_table = _load_json("res://data/stat_table.json")
	print("[Data] %d dragons, stat types=%s" % [dragons.size(), str(stat_table.keys())])

func _load_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[Data] missing " + path); return {}
	return JSON.parse_string(f.get_as_text())

func _load_dragons(path: String) -> void:
	var arr = _load_json(path)
	for d in arr:
		dragons[int(d["id"])] = d

func get_dragon(id: int) -> Dictionary:
	return dragons.get(id, {})

func stage_for_level(level: int) -> String:
	if level <= STAGE_BREAKS["baby"]:
		return "baby"
	if level <= STAGE_BREAKS["child"]:
		return "child"
	return "adult"

## Final stats = base + growth*(level-1). Crit/dodge/block fixed 10% (§K-1).
## TODO: grade(개체 등급)/문장/각인 보정 (§K-5) — 추후.
func compute_stats(id: int, level: int) -> Dictionary:
	var d := get_dragon(id)
	var typ = d.get("type")
	var tier = d.get("stat_tier")
	var st = stat_table.get(typ, {}).get(tier)
	if st == null:
		return {"hp": 0, "att": 0, "def": 0, "cri": 10, "evd": 10, "blk": 10}
	var lv := maxi(1, level) - 1
	return {
		"hp": int(st["base"]["hp"] + st["growth"]["hp"] * lv),
		"att": int(st["base"]["att"] + st["growth"]["att"] * lv),
		"def": int(st["base"]["def"] + st["growth"]["def"] * lv),
		"cri": 10, "evd": 10, "blk": 10,
	}

func dragon_ids() -> Array:
	var ids := dragons.keys()
	ids.sort()
	return ids
