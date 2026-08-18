extends SceneTree

const DrinkCraft := preload("res://scripts/systems/drink_craft.gd")

func _init() -> void:
	var defs: Dictionary = JSON.parse_string(FileAccess.open(
		_data_file("item_effects.json"), FileAccess.READ).get_as_text())
	var items: Dictionary = JSON.parse_string(FileAccess.open(
		_data_file("items.json"), FileAccess.READ).get_as_text())
	var fails := 0

	var cfg := DrinkCraft.cfg(defs)
	fails += _eq("drink_craft 존재", not cfg.is_empty(), true)

	fails += _eq("자양강장제 tier", int(DrinkCraft.parse(defs, "drink").get("tier", -1)), 0)
	fails += _eq("자양강장제 family", String(DrinkCraft.parse(defs, "drink").get("family", "x")), "")
	fails += _eq("att_drink2 tier", int(DrinkCraft.parse(defs, "att_drink2").get("tier", -1)), 2)
	fails += _eq("att_drink2 family",
		String(DrinkCraft.parse(defs, "att_drink2").get("family", "")), "att")
	fails += _eq("드링크 아닌 키", DrinkCraft.parse(defs, "att_powder").is_empty(), true)

	var n_drink := 0
	for k in items.keys():
		var v = items[k]
		if v is Dictionary and String((v as Dictionary).get("subcategory", "")) == "drink":
			n_drink += 1
			fails += _eq("%s 파싱됨" % k, DrinkCraft.parse(defs, String(k)).is_empty(), false)
	fails += _eq("드링크 19종(원작 itemNo 17~35)", n_drink, 19)

	fails += _eq("자양강장제 강화 가능", DrinkCraft.can_upgrade(defs, "drink"), true)
	fails += _eq("1단계 강화 가능", DrinkCraft.can_upgrade(defs, "hp_drink1"), true)
	fails += _eq("2단계 강화 가능", DrinkCraft.can_upgrade(defs, "hp_drink2"), true)
	fails += _eq("3단계는 불가", DrinkCraft.can_upgrade(defs, "hp_drink3"), false)

	fails += _eq("불의 정기", DrinkCraft.is_essence(items.get("ele_fire", {})), true)
	fails += _eq("가루는 정기 아님", DrinkCraft.is_essence(items.get("att_powder", {})), false)
	var n_ess := 0
	for k in items.keys():
		var v = items[k]
		if v is Dictionary and DrinkCraft.is_essence(v):
			n_ess += 1
			fails += _eq("%s 계열 매핑" % k,
				DrinkCraft.family_of_essence(defs, v) != "", true)
	fails += _eq("정기 9종", n_ess, 9)

	fails += _eq("자양강장제 + 불 → 공격력 1단계",
		DrinkCraft.result_key(defs, "drink", items["ele_fire"]), "att_drink1")
	fails += _eq("자양강장제 + 물 → 체력 1단계",
		DrinkCraft.result_key(defs, "drink", items["ele_water"]), "hp_drink1")
	fails += _eq("공격력1 + 물 → 공격력2(계열 유지)",
		DrinkCraft.result_key(defs, "att_drink1", items["ele_water"]), "att_drink2")
	fails += _eq("공격력2 → 공격력3",
		DrinkCraft.result_key(defs, "att_drink2", items["ele_wind"]), "att_drink3")
	fails += _eq("3단계는 결과 없음",
		DrinkCraft.result_key(defs, "att_drink3", items["ele_fire"]), "")

	fails += _eq("골드 자양강장제", DrinkCraft.gold_each(defs, "drink"), 300)
	fails += _eq("골드 1단계", DrinkCraft.gold_each(defs, "def_drink1"), 500)
	fails += _eq("골드 2단계", DrinkCraft.gold_each(defs, "def_drink2"), 700)
	fails += _eq("골드 3단계(강화 불가)", DrinkCraft.gold_each(defs, "def_drink3"), 0)
	fails += _eq("정기 3개/회", DrinkCraft.essence_each(defs), 3)

	fails += _eq("물약이 상한", DrinkCraft.max_count(defs, "drink", 2, 999, 999999), 2)
	fails += _eq("정기가 상한", DrinkCraft.max_count(defs, "drink", 99, 7, 999999), 2)
	fails += _eq("골드가 상한", DrinkCraft.max_count(defs, "drink", 99, 999, 950), 3)
	fails += _eq("3단계는 0", DrinkCraft.max_count(defs, "hp_drink3", 99, 999, 999999), 0)

	fails += _eq("▶ 1→2", DrinkCraft.cycle_count(1, 1, 5), 2)
	fails += _eq("▶ max→1", DrinkCraft.cycle_count(5, 1, 5), 1)
	fails += _eq("◀ 1→max", DrinkCraft.cycle_count(1, -1, 5), 5)
	fails += _eq("◀ 3→2", DrinkCraft.cycle_count(3, -1, 5), 2)
	fails += _eq("max 0 이면 0", DrinkCraft.cycle_count(1, 1, 0), 0)

	fails += _eq("기본 성공률 100", DrinkCraft.success_pct(defs), 100)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var r := DrinkCraft.roll(defs, 5, rng)
	fails += _eq("5개 전부 성공", int(r["ok_n"]), 5)
	fails += _eq("실패 0", int(r["fail_n"]), 0)

	print("[test_drink_craft] %s" % ("OK" if fails == 0 else "FAIL %d" % fails))
	quit(1 if fails > 0 else 0)

func _eq(what: String, got, want) -> int:
	if got == want:
		return 0
	printerr("  X %s: got %s, want %s" % [what, str(got), str(want)])
	return 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
