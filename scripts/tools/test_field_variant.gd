extends SceneTree
## 헤드리스 Field(변형 필드 해석) 테스트 (§8 — logic은 화면 없이 검증).
##
## 검증 대상 = 🔴 2026-07-31 수정한 버그:
##   `stages.json` 의 `night` 블록(전용 적·등장 드래곤·레벨 50·설명문)이 12지역 모두
##   채워져 있는데 **런이 읽지 않아** 밤에 입장해도 낮 몬스터가 나왔다.
##
## 실행: godot --headless --path . --script res://scripts/tools/test_field_variant.gd --quit-after 5

const F := preload("res://scripts/systems/field.gd")
const D := preload("res://scripts/systems/drops.gd")

func _init() -> void:
	var fails := 0
	var stages: Dictionary = (_json("res://data/stages.json") as Dictionary)["stages"]

	# 밤 변형 보유 지역 = 1~14 중 6·8 제외 12종(build_yutakan_variants.py).
	var night_ids: Array = []
	var kades_ids: Array = []
	for sid in stages:
		var st: Dictionary = stages[sid]
		if F.has_variant(st, D.MODE_NIGHT): night_ids.append(int(sid))
		if F.has_variant(st, D.MODE_KADES): kades_ids.append(int(sid))
	night_ids.sort(); kades_ids.sort()
	fails += _eq("밤 변형 12지역", night_ids, [1, 2, 3, 4, 5, 7, 9, 10, 11, 12, 13, 14])
	fails += _eq("카데스 변형 12지역", kades_ids, [1, 2, 3, 4, 5, 7, 9, 10, 11, 12, 13, 14])

	# normal/hero 는 기본 레코드를 **그대로** 쓴다(영웅은 스탯 배율이지 다른 필드가 아니다).
	var st1: Dictionary = stages["1"]
	fails += _true("일반은 변형 아님", not F.has_variant(st1, D.MODE_NORMAL))
	fails += _true("영웅은 변형 아님", not F.has_variant(st1, D.MODE_HERO))
	fails += _eq("일반은 원본 그대로", F.apply_variant(st1, D.MODE_NORMAL), st1)
	fails += _eq("영웅은 원본 그대로", F.apply_variant(st1, D.MODE_HERO), st1)

	# 밤 레코드 — 적/드래곤/레벨/설명이 낮과 **달라야** 한다.
	var n1 := F.apply_variant(st1, D.MODE_NIGHT)
	fails += _eq("밤 variant 표시", String(n1.get("variant", "")), "night")
	fails += _true("밤 적이 낮과 다르다", str(n1.get("enemies")) != str(st1.get("enemies")))
	fails += _true("밤 드래곤이 낮과 다르다", str(n1.get("dragons")) != str(st1.get("dragons")))
	fails += _eq("밤 레벨 50", int(n1.get("level", 0)), 50)
	fails += _true("밤 설명문이 낮과 다르다", String(n1.get("desc", "")) != String(st1.get("desc", "")))
	# 변형 레코드 안에는 변형 블록이 남지 않는다(중첩 해석 방지).
	fails += _true("변형 레코드에 night 블록 없음", not n1.has("night"))
	fails += _true("변형 레코드에 kades 블록 없음", not n1.has("kades"))
	# 원본은 건드리지 않는다(얕은 복사가 아니라 깊은 복사여야 한다).
	fails += _true("원본 불변", st1.has("night") and String(st1.get("variant", "")) == "")

	# 밤 전 지역이 낮과 다른 적을 갖는다(데이터가 실제로 채워져 있는지).
	var same_enemies := 0
	var lv_bad := 0
	for sid2 in night_ids:
		var base: Dictionary = stages[str(sid2)]
		var nv := F.apply_variant(base, D.MODE_NIGHT)
		if str(nv.get("enemies")) == str(base.get("enemies")): same_enemies += 1
		if int(nv.get("level", 0)) != 50: lv_bad += 1
	fails += _eq("밤인데 낮 적 그대로인 지역", same_enemies, 0)
	fails += _eq("밤 레벨이 50이 아닌 지역", lv_bad, 0)

	# 카데스 레코드 — 적만 덮는다(레벨은 진입 시 굴린다, data/kades.json boss_level).
	var k1 := F.apply_variant(st1, D.MODE_KADES)
	fails += _eq("카데스 variant 표시", String(k1.get("variant", "")), "kades")
	fails += _true("카데스 적이 낮과 다르다", str(k1.get("enemies")) != str(st1.get("enemies")))

	# 변형이 없는 지역(우노 24)은 어떤 난이도로도 원본 그대로.
	var st24: Dictionary = stages["24"]
	fails += _eq("변형 없는 지역 밤", F.apply_variant(st24, D.MODE_NIGHT), st24)
	fails += _eq("변형 없는 지역 카데스", F.apply_variant(st24, D.MODE_KADES), st24)

	# 🔴 회귀 방지 — **알 풀이 밤 드래곤을 따라간다**(팝업 등재 = 드랍 후보, 사용자 확정).
	var t = _json("res://data/drops.json")
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
