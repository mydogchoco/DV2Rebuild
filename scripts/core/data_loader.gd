extends Node
## Autoload "Data": data 층 — 정적 게임 정의(data/*.json)를 읽어 제공만 한다. (CLAUDE.md §10)
## 규칙(스탯 공식/레벨→단계 등 logic)은 여기 두지 않는다 → scripts/systems/(Growth 등).
## Master data is restored by the user (see docs/game_design.md), not in assets.

var dragons: Dictionary = {}     # id(int) -> dragon dict
var stat_table: Dictionary = {}  # type -> tier -> {base,growth}
var new_game: Dictionary = {}    # 새 게임 초기 로드아웃 정의

func _ready() -> void:
	_load_dragons("res://data/dragons.json")
	stat_table = _load_json("res://data/stat_table.json")
	new_game = _load_json("res://data/new_game.json")
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

func new_game_def() -> Dictionary:
	return new_game

func dragon_ids() -> Array:
	var ids := dragons.keys()
	ids.sort()
	return ids
