extends Node

const EU := preload("res://scripts/systems/egg_upgrade.gd")

func _ready() -> void:
	var fails := 0
	var items: Dictionary = _load(_data_file("items.json"))
	var up: Dictionary = _load(_data_file("upgrade_egg.json"))
	var lab: Dictionary = _load(_data_file("laboratory.json"))
	var ecfg: Dictionary = lab.get("egg_upgrade", {})

	var checked := 0
	for k in items:
		var it = items[k]
		if not (it is Dictionary) or String((it as Dictionary).get("category", "")) != "egg":
			continue
		var ev = (it as Dictionary).get("element")
		var el: String = ev if typeof(ev) == TYPE_STRING else ""
		if el == "":
			continue
		var r: Dictionary = EU.recipe_for(String(k), el, 0, up, ecfg)
		fails += _true("레시피 해석: %s" % k, not r.is_empty())
		fails += _eq("재료 3칸: %s" % k, (r.get("materials", []) as Array).size(), 3)
		checked += 1
	fails += _true("알 종류 20종 이상 검사", checked >= 20)

	var vr: Dictionary = EU.recipe_for("egg:37", "aqua", 0, up, ecfg)
	fails += _true("가상 알도 레시피가 있다", not vr.is_empty())
	fails += _eq("가상 알 결정 = 물의 결정", String((vr["materials"][2] as Dictionary)["item"]), "crystal_water")

	var want := [["stone_spirit2", "stone_heart2"], ["stone_spirit3", "stone_heart3"],
		["stone_spirit4", "stone_heart4"]]
	for g in 3:
		var r2: Dictionary = EU.recipe_for("mall_back_egg", "light", g, up, ecfg)
		var mats: Array = r2.get("materials", [])
		fails += _eq("%d강 정령석" % (g + 1), String((mats[0] as Dictionary)["item"]), want[g][0])
		fails += _eq("%d강 스톤하트" % (g + 1), String((mats[1] as Dictionary)["item"]), want[g][1])
		fails += _eq("%d강 결정(빛)" % (g + 1), String((mats[2] as Dictionary)["item"]), "crystal_light")
		for m in mats:
			fails += _true("재료가 items.json 에 있다: %s" % (m as Dictionary)["item"],
				items.has(String((m as Dictionary)["item"])))
			fails += _eq("개수 10", int((m as Dictionary)["count"]), 10)

	fails += _eq("강화 상한", EU.max_step(ecfg), 3)
	fails += _true("3강은 레시피 없음", EU.recipe_for("mall_back_egg", "light", 3, up, ecfg).is_empty())

	fails += _eq("1강 등급", EU.hatch_grade(1, ecfg), 7.0)
	fails += _eq("2강 등급", EU.hatch_grade(2, ecfg), 7.2)
	fails += _eq("3강 등급", EU.hatch_grade(3, ecfg), 7.5)
	fails += _eq("0강은 확정 등급 없음(랜덤 굴림)", EU.hatch_grade(0, ecfg), 0.0)

	fails += _eq("0강은 접미사 없음", EggItem.key("egg:17", 0), "egg:17")
	fails += _eq("2강 키", EggItem.key("egg:17", 2), "egg:17#2")
	fails += _eq("키에서 등급 읽기", EggItem.grade_of("egg:17#2"), 2)
	fails += _eq("접미사 없으면 0강", EggItem.grade_of("egg:17"), 0)
	fails += _eq("키에서 알 종류 읽기", EggItem.base_of("egg:17#2"), "egg:17")
	fails += _true("강화된 알 판정", EggItem.is_upgraded("egg:17#2"))
	fails += _true("0강은 강화 아님", not EggItem.is_upgraded("egg:17"))
	fails += _true("같은 알의 변형", EggItem.is_variant_of("egg:17#2", "egg:17"))
	fails += _true("다른 알은 변형 아님", not EggItem.is_variant_of("egg:18#2", "egg:17"))

	fails += _eq("구형 값 = 2강 1개", str(EU.normalize(2)), str({2: 1}))
	fails += _eq("구형 테이블 정규화", str(EU.normalize({"2": 1})), str({2: 1}))

	var ci: Dictionary = _load(_data_file("combine_item.json"))
	var targets: Array = []
	for r3 in (ci.get("recipes", []) as Array):
		targets.append(String((r3 as Dictionary).get("target", "")))
	for t in ["stone_spirit2", "stone_spirit3", "stone_spirit4",
			"stone_heart2", "stone_heart3", "stone_heart4"]:
		fails += _true("환산 조합 있음: %s" % t, targets.has(t))

	print("[test_egg_upgrade] %s" % ("PASS" if fails == 0 else "FAIL(%d)" % fails))
	get_tree().quit(1 if fails > 0 else 0)

func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("  ✗ 파일 없음: ", path)
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}

func _true(what: String, cond: bool) -> int:
	if cond:
		return 0
	print("  ✗ %s" % what)
	return 1

func _eq(what: String, got, want) -> int:
	if is_same(got, want) or str(got) == str(want):
		return 0
	print("  ✗ %s — got %s, want %s" % [what, str(got), str(want)])
	return 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
