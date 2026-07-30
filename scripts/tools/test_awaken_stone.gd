extends SceneTree
## 헤드리스 AwakenStone / 가챠 10회 단위 테스트 (logic 은 화면 없이 검증 — CLAUDE.md §8.1).
## 실행: godot --headless --script res://scripts/tools/test_awaken_stone.gd
##
## 검증 대상(2026-07-30 변경분):
##   1) 각성마석 배치 상한 = 알 **종류** 수(`max_egg_kinds_per_batch`) — 개수 상한은 없다.
##   2) 목표 포인트 **초과가 더 이상 제작을 막지 않는다**(경고는 UI 몫, 초과분은 버려진다).
##   3) 가챠 계열 10회 사용 = 1회 개봉의 독립 시행 n 회(`EggGacha.roll_many`).

func _init() -> void:
	var fails := 0
	var cfg: Dictionary = _json("res://data/awaken.json")
	fails += _true("awaken.json 로드", not cfg.is_empty())

	var star := 5
	var need := AwakenStone.need(cfg, star)                     # 위키 확정: 5성 20000
	fails += _eq("5성 목표 포인트", need, 20000)
	var p5 := AwakenStone.egg_points(cfg, 5)
	fails += _true("5성 알 포인트 > 0", p5 > 0)

	# 1) 종류 상한 — 상한 초과는 여전히 막는다(원작 MasicStoneErroMsg_4).
	var kinds := AwakenStone.max_kinds(cfg)
	var over_kinds: Array = []
	for i in kinds + 1:
		over_kinds.append({"star": 5, "count": 1})
	fails += _true("종류 %d개 초과는 거부" % kinds,
		AwakenStone.check_batch(cfg, star, 0, over_kinds) != "")
	var ok_kinds: Array = []
	for i in kinds:
		ok_kinds.append({"star": 5, "count": 1})
	fails += _eq("종류 %d개는 통과" % kinds, AwakenStone.check_batch(cfg, star, 0, ok_kinds), "")

	# 2) 0개 선택·마석 미선택은 여전히 거부.
	fails += _true("0개 선택 거부", AwakenStone.check_batch(cfg, star, 0, []) != "")
	fails += _true("마석 미선택 거부",
		AwakenStone.check_batch(cfg, 0, 0, [{"star": 5, "count": 1}]) != "")

	# 3) 🔴 변경점: 목표를 넘겨도 `check_batch` 는 통과하고, `overflow` 가 초과분을 알려 준다.
	var huge: Array = [{"star": 5, "count": 100}]                # 5성 알 100개 = 목표 훨씬 초과
	fails += _eq("초과 배치도 통과", AwakenStone.check_batch(cfg, star, 0, huge), "")
	var over := AwakenStone.overflow(cfg, star, 0, huge)
	fails += _eq("초과분 계산", over, p5 * 100 - need)
	fails += _eq("초과 없는 배치의 overflow=0",
		AwakenStone.overflow(cfg, star, 0, [{"star": 5, "count": 1}]), 0)

	# 4) 초과해도 완성되고 포인트는 0 으로 돌아간다(초과분 소멸).
	var res: Dictionary = AwakenStone.apply(cfg, star, 0, huge)
	fails += _true("초과 배치로 완성", bool(res["complete"]))
	fails += _eq("완성 후 포인트 0", int(res["points"]), 0)
	# 정확히 목표를 맞춘 경우도 완성.
	var exact := int(ceil(float(need) / float(p5)))
	fails += _true("정확히 채워도 완성",
		bool(AwakenStone.apply(cfg, star, 0, [{"star": 5, "count": exact}])["complete"]))
	# 목표 미달이면 누적만 된다.
	var part: Dictionary = AwakenStone.apply(cfg, star, 0, [{"star": 5, "count": 1}])
	fails += _true("미달은 누적", not bool(part["complete"]) and int(part["points"]) == p5)

	# 5) 가챠 10회 — roll_many 는 n 개를 돌려주고, 각 회차는 독립이다.
	var gcfg: Dictionary = _json("res://data/gacha_eggs.json")
	var items: Dictionary = _json("res://data/items.json")
	var dragons: Dictionary = {}
	for d in _json_array("res://data/dragons.json"):
		dragons[int(d["id"])] = d
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260730
	var got: Array = EggGacha.roll_many("mall_question_egg2", items["mall_question_egg2"],
		gcfg, dragons, rng, 10)
	fails += _eq("10회 사용 = 결과 10건", got.size(), 10)
	var uniq := {}
	for id in got:
		uniq[int(id)] = true
	fails += _true("10건이 한 종으로 고정되지 않는다 (%d종)" % uniq.size(), uniq.size() > 1)
	# 시드 재현성(§4).
	var rng2 := RandomNumberGenerator.new(); rng2.seed = 20260730
	fails += _eq("10회 시드 재현성",
		EggGacha.roll_many("mall_question_egg2", items["mall_question_egg2"],
			gcfg, dragons, rng2, 10), got)

	# 6) 젬 상자 10회.
	var drops: Dictionary = _json("res://data/drops.json")
	var gems: Dictionary = _json("res://data/gems.json")
	var rng3 := RandomNumberGenerator.new(); rng3.seed = 7
	var keys: Array = Drops.roll_gem_box_many(drops, gems, rng3, 10)
	fails += _eq("젬 상자 10회 = 결과 10건", keys.size(), 10)
	var bad := 0
	for k in keys:
		if Gem.parse_item_key(String(k)).is_empty():
			bad += 1
	fails += _eq("결과가 모두 젬 인벤 키", bad, 0)

	print("AwakenStone/가챠10회 테스트 — %s (실패 %d)" % ["ALL PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)


func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _json_array(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return []
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Array else []


func _true(what: String, ok: bool) -> int:
	if not ok:
		print("  FAIL: ", what)
		return 1
	return 0


func _eq(what: String, got, want) -> int:
	if got != want:
		print("  FAIL: %s — got %s, want %s" % [what, str(got), str(want)])
		return 1
	return 0
