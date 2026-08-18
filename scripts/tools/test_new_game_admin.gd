extends SceneTree

const NG := preload("res://scripts/systems/new_game.gd")

const MITRA := "egg:4155"
const ANCIENT2 := "egg:4210"
const QUESTION := "mall_question_egg2"

func _init() -> void:
	var fails := 0
	var def: Dictionary = _load(_data_file("new_game.json"))
	var dragons: Array = _load_arr(_data_file("dragons.json"))

	var plain: Dictionary = NG.admin_inventory(def, false)
	fails += _eq("일반: 빛문알 10개", int(plain.get(QUESTION, 0)), 10)
	fails += _eq("일반: 미트라 알 없음", int(plain.get(MITRA, 0)), 0)

	var adm: Dictionary = NG.admin_inventory(def, true)
	fails += _eq("관리자: 빛문알 제거", int(adm.get(QUESTION, 0)), 0)
	fails += _eq("관리자: 미트라의 알 1", int(adm.get(MITRA, 0)), 1)
	fails += _eq("관리자: 고대신룡 II의 알 1", int(adm.get(ANCIENT2, 0)), 1)

	for k in ["energy_drink", "level_up", "drink", "hp_powder"]:
		fails += _eq("관리자: %s 유지" % k, int(adm.get(k, -1)), int(plain.get(k, -2)))
	fails += _eq("항목 수 = 원본 −빛문알 +알2", adm.size(), plain.size() + 1)

	var again: Dictionary = NG.admin_inventory(def, false)
	fails += _eq("def 무손상 — 재호출 시 빛문알 그대로", int(again.get(QUESTION, 0)), 10)

	fails += _eq("4155 = 미트라", _name_of(dragons, 4155), "미트라")
	fails += _eq("4210 = 고대신룡 II", _name_of(dragons, 4210), "고대신룡 II")

	print("=== test_new_game_admin: %s ===" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(1 if fails else 0)

func _name_of(dragons: Array, id: int) -> String:
	for d in dragons:
		if int((d as Dictionary).get("id", -1)) == id:
			return String((d as Dictionary).get("name", ""))
	return "(없음)"

func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}

func _load_arr(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Array else []

func _eq(what: String, got, want) -> int:
	if got == want:
		return 0
	print("  FAIL %s: got=%s want=%s" % [what, str(got), str(want)])
	return 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
