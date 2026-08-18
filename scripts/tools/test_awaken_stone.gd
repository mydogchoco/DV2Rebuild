extends SceneTree

func _init() -> void:
	var fails := 0
	var cfg: Dictionary = _json(_data_file("awaken.json"))
	fails += _true("awaken.json 로드", not cfg.is_empty())

	var star := 5
	var need := AwakenStone.need(cfg, star)
	fails += _eq("5성 목표 포인트", need, 20000)
	var p5 := AwakenStone.egg_points(cfg, 5)
	fails += _true("5성 알 포인트 > 0", p5 > 0)

	var kinds := AwakenStone.max_kinds(cfg)
	fails += _eq("배치 알 종류 상한", kinds, 10)
	var over_kinds: Array = []
	for i in kinds + 1:
		over_kinds.append({"star": 5, "count": 1})
	fails += _true("종류 %d개 초과는 거부" % kinds,
		AwakenStone.check_batch(cfg, star, 0, over_kinds) != "")
	var ok_kinds: Array = []
	for i in kinds:
		ok_kinds.append({"star": 5, "count": 1})
	fails += _eq("종류 %d개는 통과" % kinds, AwakenStone.check_batch(cfg, star, 0, ok_kinds), "")

	fails += _true("0개 선택 거부", AwakenStone.check_batch(cfg, star, 0, []) != "")
	fails += _true("마석 미선택 거부",
		AwakenStone.check_batch(cfg, 0, 0, [{"star": 5, "count": 1}]) != "")

	var huge: Array = [{"star": 5, "count": 100}]
	fails += _eq("초과 배치도 통과", AwakenStone.check_batch(cfg, star, 0, huge), "")
	var over := AwakenStone.overflow(cfg, star, 0, huge)
	fails += _eq("초과분 계산", over, p5 * 100 - need)
	fails += _eq("초과 없는 배치의 overflow=0",
		AwakenStone.overflow(cfg, star, 0, [{"star": 5, "count": 1}]), 0)

	var res: Dictionary = AwakenStone.apply(cfg, star, 0, huge)
	fails += _true("초과 배치로 완성", bool(res["complete"]))
	fails += _eq("완성 후 포인트 0", int(res["points"]), 0)
	var exact := int(ceil(float(need) / float(p5)))
	fails += _true("정확히 채워도 완성",
		bool(AwakenStone.apply(cfg, star, 0, [{"star": 5, "count": exact}])["complete"]))
	var part: Dictionary = AwakenStone.apply(cfg, star, 0, [{"star": 5, "count": 1}])
	fails += _true("미달은 누적", not bool(part["complete"]) and int(part["points"]) == p5)

	var gcfg: Dictionary = _json(_data_file("gacha_eggs.json"))
	var items: Dictionary = _json(_data_file("items.json"))
	var dragons: Dictionary = {}
	for d in _json_array(_data_file("dragons.json")):
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
	var rng2 := RandomNumberGenerator.new(); rng2.seed = 20260730
	fails += _eq("10회 시드 재현성",
		EggGacha.roll_many("mall_question_egg2", items["mall_question_egg2"],
			gcfg, dragons, rng2, 10), got)

	var drops: Dictionary = _json(_data_file("drops.json"))
	var gems: Dictionary = _json(_data_file("gems.json"))
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

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
