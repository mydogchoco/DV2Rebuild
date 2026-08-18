extends SceneTree

const F := preload("res://scripts/systems/field.gd")
const D := preload("res://scripts/systems/drops.gd")

func _init() -> void:
	var fails := 0
	var stages: Dictionary = (_json(_data_file("stages.json")) as Dictionary)["stages"]

	var night_ids: Array = []
	var kades_ids: Array = []
	for sid in stages:
		var st: Dictionary = stages[sid]
		if F.has_variant(st, D.MODE_NIGHT): night_ids.append(int(sid))
		if F.has_variant(st, D.MODE_KADES): kades_ids.append(int(sid))
	night_ids.sort(); kades_ids.sort()
	fails += _eq("밤 변형 12지역", night_ids, [1, 2, 3, 4, 5, 7, 9, 10, 11, 12, 13, 14])
	fails += _eq("카데스 변형 12지역", kades_ids, [1, 2, 3, 4, 5, 7, 9, 10, 11, 12, 13, 14])

	var st1: Dictionary = stages["1"]
	fails += _true("일반은 변형 아님", not F.has_variant(st1, D.MODE_NORMAL))
	fails += _true("영웅은 변형 아님", not F.has_variant(st1, D.MODE_HERO))
	fails += _eq("일반은 원본 그대로", F.apply_variant(st1, D.MODE_NORMAL), st1)
	fails += _eq("영웅은 원본 그대로", F.apply_variant(st1, D.MODE_HERO), st1)

	var n1 := F.apply_variant(st1, D.MODE_NIGHT)
	fails += _eq("밤 variant 표시", String(n1.get("variant", "")), "night")
	fails += _true("밤 적이 낮과 다르다", str(n1.get("enemies")) != str(st1.get("enemies")))
	fails += _true("밤 드래곤이 낮과 다르다", str(n1.get("dragons")) != str(st1.get("dragons")))
	fails += _eq("밤 레벨 50", int(n1.get("level", 0)), 50)
	fails += _true("밤 설명문이 낮과 다르다", String(n1.get("desc", "")) != String(st1.get("desc", "")))
	fails += _true("변형 레코드에 night 블록 없음", not n1.has("night"))
	fails += _true("변형 레코드에 kades 블록 없음", not n1.has("kades"))
	fails += _true("원본 불변", st1.has("night") and String(st1.get("variant", "")) == "")

	var same_enemies := 0
	var lv_bad := 0
	for sid2 in night_ids:
		var base: Dictionary = stages[str(sid2)]
		var nv := F.apply_variant(base, D.MODE_NIGHT)
		if str(nv.get("enemies")) == str(base.get("enemies")): same_enemies += 1
		if int(nv.get("level", 0)) != 50: lv_bad += 1
	fails += _eq("밤인데 낮 적 그대로인 지역", same_enemies, 0)
	fails += _eq("밤 레벨이 50이 아닌 지역", lv_bad, 0)

	var k1 := F.apply_variant(st1, D.MODE_KADES)
	fails += _eq("카데스 variant 표시", String(k1.get("variant", "")), "kades")
	fails += _true("카데스 적이 낮과 다르다", str(k1.get("enemies")) != str(st1.get("enemies")))

	var st24: Dictionary = stages["24"]
	fails += _eq("변형 없는 지역 밤", F.apply_variant(st24, D.MODE_NIGHT), st24)
	fails += _eq("변형 없는 지역 카데스", F.apply_variant(st24, D.MODE_KADES), st24)

	var t = _json(_data_file("drops.json"))
	var day_pool := D.egg_pool(st1, false)
	var night_pool := D.egg_pool(n1, false)
	fails += _true("낮 알 후보 있음", not day_pool.is_empty())
	fails += _true("밤 알 후보 있음", not night_pool.is_empty())
	fails += _true("밤 알 후보가 낮과 다르다", str(day_pool) != str(night_pool))
	var rng := RandomNumberGenerator.new(); rng.seed = 31
	var leak := 0
	for _i in 3000:
		var ek := D.roll_egg(t, n1, D.SOURCE_BOSS, rng, false)
		if ek == "": continue
		if not night_pool.has(EggGacha.dragon_of(ek)): leak += 1
	fails += _eq("밤 런에서 낮 드래곤 알 누출", leak, 0)

	if fails == 0:
		print("[test_field_variant] ALL PASS")
		quit(0)
	else:
		printerr("[test_field_variant] %d FAIL" % fails)
		quit(1)

func _json(path: String):
	return JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())

func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	printerr("  FAIL %s: got=%s want=%s" % [label, str(got), str(want)])
	return 1

func _true(label: String, cond: bool) -> int:
	if cond:
		return 0
	printerr("  FAIL %s" % label)
	return 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
