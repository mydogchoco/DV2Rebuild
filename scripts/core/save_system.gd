extends Node
## Autoload "SaveSystem": single entry point for local save/load (CLAUDE.md §5).
## All mutable game state lives here and is written to user:// (no server).

const SAVE_PATH := "user://save_0.json"
const SAVE_VERSION := 1

var state: Dictionary = {}

func _ready() -> void:
	if not load_game():
		state = default_state()

func default_state() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"currency": {"gold": 0, "diamond": 0},   # §I
		"owned_dragons": [],                       # [{id, level, exp, grade, ...}]
		"inventory": {},
		"progress": {},
		"cave_skin": 0,                            # 배경 스킨 인덱스 (0..14)
		"active_dragon": 0,                        # owned_dragons 인덱스
		"rng_seed": null,
	}

func save_game() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[Save] cannot write " + SAVE_PATH); return false
	f.store_string(JSON.stringify(state, "\t"))
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[Save] corrupt save"); return false
	state = parsed
	return true

func reset() -> void:
	state = default_state()
	save_game()

## --- helpers ---
func add_dragon(id: int, level: int = 1, grade: float = 8.0) -> Dictionary:
	var inst := {"id": id, "level": level, "exp": 0, "grade": grade}
	state["owned_dragons"].append(inst)
	return inst

func add_currency(kind: String, amount: int) -> void:
	state["currency"][kind] = int(state["currency"].get(kind, 0)) + amount
