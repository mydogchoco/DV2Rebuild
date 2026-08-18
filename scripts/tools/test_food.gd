extends SceneTree

func _init() -> void:
	var fails := 0
	var defs: Dictionary = _load(_data_file("item_effects.json"))
	var items: Dictionary = _load(_data_file("items.json"))
	var fmax := ItemEffect.food_max(defs)

	var feeds: Array = []
	for k in items:
		var v = items[k]
		if v is Dictionary and ItemEffect.is_feed(v):
			feeds.append(k)
	fails += _eq("먹이 종수", feeds.size(), 18)
	fails += _eq("FOOD 상한", fmax, 100)
	var half: Array = defs.get("feed", {}).get("half", [])
	var full: Array = defs.get("feed", {}).get("full", [])
	fails += _eq("half 9종", half.size(), 9)
	fails += _eq("full 9종", full.size(), 9)
	var missing: Array = []
	for k in feeds:
		if not (half.has(k) or full.has(k)):
			missing.append(k)
	fails += _eq("모든 먹이가 half/full 중 하나", missing, [])
	var by_el := {}
	for k in feeds:
		var el := String((items[k] as Dictionary).get("element", ""))
		var e: Dictionary = by_el.get(el, {"half": 0, "full": 0})
		if half.has(k): e["half"] = int(e["half"]) + 1
		else: e["full"] = int(e["full"]) + 1
		by_el[el] = e
	fails += _eq("9속성", by_el.size(), 9)
	for el in by_el:
		var e: Dictionary = by_el[el]
		fails += _eq("%s = 절반1·전량1" % el, [int(e["half"]), int(e["full"])], [1, 1])

	var fire_full: Dictionary = items["food_fire_chicken"]
	var fire_half: Dictionary = items["food_fire_chickenleg"]
	fails += _eq("전량 먹이 pct", ItemEffect.feed_restore_pct(defs, "food_fire_chicken"), 100)
	fails += _eq("절반 먹이 pct", ItemEffect.feed_restore_pct(defs, "food_fire_chickenleg"), 50)
	fails += _eq("굶음 → 전량 = 만복",
		ItemEffect.food_after_feed(defs, fire_full, "food_fire_chicken", "fire", 0), fmax)
	fails += _eq("굶음 → 절반 = 50",
		ItemEffect.food_after_feed(defs, fire_half, "food_fire_chickenleg", "fire", 0), 50)
	fails += _eq("70 + 절반 = 상한에서 잘림",
		ItemEffect.food_after_feed(defs, fire_half, "food_fire_chickenleg", "fire", 70), fmax)

	fails += _true("불 먹이를 물 드래곤은 못 먹는다", not ItemEffect.feed_matches(fire_full, "aqua"))
	fails += _eq("불일치 먹이는 FOOD 를 안 건드린다",
		ItemEffect.food_after_feed(defs, fire_full, "food_fire_chicken", "aqua", 30), 30)
	fails += _true("드링크는 먹이 아님", not ItemEffect.is_feed(items["att_drink1"]))
	fails += _true("회복물약은 먹이 아님", not ItemEffect.is_feed(items["heal_potion1"]))

	fails += _true("0 = 굶음", ItemEffect.is_starving(defs, 0))
	fails += _true("1 = 안 굶음", not ItemEffect.is_starving(defs, 1))
	fails += _true("만복 = 안 굶음", not ItemEffect.is_starving(defs, fmax))
	var fake := {1: {"food": 0}, 2: {"food": 45}, 3: {}}
	var getter := func(uid: int): return fake.get(uid, {})
	fails += _eq("굶은 개체만 골라낸다",
		ItemEffect.starving_uids(defs, [1, 2, 3], getter), [1])

	fails += _true("불 먹이 보유 → 불 드래곤에게 먹일 수 있다",
		ItemEffect.has_matching_feed({"food_fire_chicken": 2}, items, "fire"))
	fails += _true("불 먹이만 있으면 물 드래곤에겐 없다",
		not ItemEffect.has_matching_feed({"food_fire_chicken": 2}, items, "aqua"))
	fails += _true("수량 0 은 보유가 아니다",
		not ItemEffect.has_matching_feed({"food_fire_chicken": 0}, items, "fire"))

	fails += _true("44 = 성체(오라 없음)", not Growth.is_aura_adult(44))
	fails += _true("45 = 오라성체", Growth.is_aura_adult(45))
	fails += _eq("성체 아트 임계는 그대로 25", Growth.stage_for_level(25), "adult")
	fails += _eq("24 = 해츨링", Growth.stage_for_level(24), "child")

	if fails == 0:
		print("[test_food] ✅ ALL PASS")
	else:
		print("[test_food] ❌ %d FAIL" % fails)
	quit(1 if fails > 0 else 0)

func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())

func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	print("  FAIL %s: got %s want %s" % [label, str(got), str(want)])
	return 1

func _true(label: String, ok: bool) -> int:
	if ok:
		return 0
	print("  FAIL %s" % label)
	return 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
