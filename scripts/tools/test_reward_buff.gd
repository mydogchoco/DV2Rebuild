extends SceneTree

const IE := preload("res://scripts/systems/item_effect.gd")

func _init() -> void:
	var fails := 0
	var defs = _json(_data_file("item_effects.json"))
	var items = _json(_data_file("items.json"))
	var shop = _json(_data_file("shop.json"))

	fails += _true("item_effects 에 reward_buff", defs.has("reward_buff"))
	fails += _eq("지속시간 3600초(1시간)", int(defs["reward_buff"]["duration_sec"]), 3600)
	fails += _eq("배수권 4종", (defs["reward_buff"]["items"] as Dictionary).size(), 4)
	for k in ["expx2", "expx4", "goldx2", "goldx4"]:
		var eff := IE.reward_buff_of(defs, k)
		fails += _true("%s 해석됨" % k, not eff.is_empty())
		var want := 2 if k.ends_with("2") else 4
		fails += _eq("%s 배수" % k, int(eff.get("mult", 0)), want)
		fails += _true("%s 축" % k,
			String(eff.get("axis", "")) == ("exp" if k.begins_with("exp") else "gold"))
		fails += _true("%s offline=impl" % k, String((items[k] as Dictionary)["offline"]) == "impl")
	fails += _true("배수권이 아닌 키는 {}", IE.reward_buff_of(defs, "att_drink1").is_empty())

	var sold := {}
	for t in (shop["tabs"] as Array):
		for s in ((t as Dictionary).get("stock", []) as Array):
			sold[String((s as Dictionary)["item"])] = String((t as Dictionary)["id"])
	for k2 in ["expx2", "expx4", "goldx2", "goldx4"]:
		fails += _true("%s 상점 진열" % k2, sold.has(k2))

	var now := 1_800_000_000
	fails += _true("무버프 exp 1.0", IE.reward_buff_mult({}, "exp", now) == 1.0)
	fails += _eq("무버프 남은시간 0", IE.reward_buff_left({}, "exp", now), 0)

	var a: Dictionary = {}
	var r := IE.apply_reward_buff(a, IE.reward_buff_of(defs, "expx2"), now)
	fails += _true("expx2 사용 성공", bool(r["ok"]))
	a = r["active"]
	fails += _true("exp 2배 적용", IE.reward_buff_mult(a, "exp", now) == 2.0)
	fails += _eq("남은시간 3600", IE.reward_buff_left(a, "exp", now), 3600)
	fails += _true("골드는 무버프", IE.reward_buff_mult(a, "gold", now) == 1.0)

	fails += _true("3599초 뒤 살아 있음", IE.reward_buff_mult(a, "exp", now + 3599) == 2.0)
	fails += _true("3601초 뒤 만료", IE.reward_buff_mult(a, "exp", now + 3601) == 1.0)
	fails += _eq("만료 후 남은시간 0", IE.reward_buff_left(a, "exp", now + 3601), 0)

	var r2 := IE.apply_reward_buff(a, IE.reward_buff_of(defs, "expx2"), now + 600)
	fails += _true("같은 배수 재사용 성공", bool(r2["ok"]))
	fails += _eq("남은 3000 + 3600 = 6600", IE.reward_buff_left(r2["active"], "exp", now + 600), 6600)

	var r3 := IE.apply_reward_buff(a, IE.reward_buff_of(defs, "expx4"), now + 600)
	fails += _true("4배로 갱신", IE.reward_buff_mult(r3["active"], "exp", now + 600) == 4.0)
	fails += _true("남은 시간 ≥ 3600", IE.reward_buff_left(r3["active"], "exp", now + 600) >= 3600)

	var r4 := IE.apply_reward_buff(r3["active"], IE.reward_buff_of(defs, "expx2"), now + 600)
	fails += _true("약한 배수 거부", not bool(r4["ok"]))
	fails += _true("거부 사유 문구 있음", String(r4["reason"]) != "")
	fails += _true("거부 시 상태 불변",
		IE.reward_buff_mult(r4["active"], "exp", now + 600) == 4.0)

	var pruned := IE.prune_reward_buff(a, now + 4000)
	fails += _eq("만료분 제거", pruned.size(), 0)
	fails += _eq("살아있는 건 유지", IE.prune_reward_buff(a, now + 10).size(), 1)

	var round_trip = JSON.parse_string(JSON.stringify(a))
	fails += _true("왕복 후 2배 유지", IE.reward_buff_mult(round_trip, "exp", now) == 2.0)
	fails += _eq("왕복 후 남은시간", IE.reward_buff_left(round_trip, "exp", now), 3600)
	fails += _true("왕복 후에도 1시간 뒤 만료",
		IE.reward_buff_mult(round_trip, "exp", now + 3601) == 1.0)

	fails += _true("59분", IE.reward_buff_left_text(3540) == "59분")
	fails += _true("1시간 10분", IE.reward_buff_left_text(4200) == "1시간 10분")
	fails += _true("만료는 빈 문자열", IE.reward_buff_left_text(0) == "")

	if fails == 0:
		print("[test_reward_buff] ALL PASS")
	else:
		printerr("[test_reward_buff] %d FAIL" % fails)
	quit(1 if fails > 0 else 0)

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
