extends SceneTree

var _fail := 0

func _ok(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		print("  FAIL  ", label)
		_fail += 1

func _init() -> void:
	var t: Dictionary = _json(_data_file("box_loot.json"))
	var items: Dictionary = _items()
	var dragons: Array = _json_arr(_data_file("dragons.json"))
	var equip: Dictionary = _json(_data_file("equipment.json"))

	print("=== box_loot 표 ===")
	var boxes: Dictionary = t.get("boxes", {})
	var keys: Dictionary = t.get("keys", {})
	print("상자 %d종 · 열쇠 %d종 · 컷 %d종"
		% [boxes.size(), keys.size(), (t.get("cut", {}) as Dictionary).size()])
	_ok(boxes.size() == 13, "상자 13종 (INDEX.md '나머지 13종')")
	_ok(keys.size() == 6, "열쇠 6종")

	print("\n=== 1) 풀 항목 해석 ===")
	var dragon_ids := {}
	for d in dragons:
		dragon_ids[int((d as Dictionary)["id"])] = true
	var equip_names := {}
	for fam in (equip.get("special", {}) as Dictionary):
		for it in ((equip["special"][fam] as Dictionary).get("items", []) as Array):
			equip_names["special:%s:%s" % [fam, String((it as Dictionary)["name"])]] = true
	var bad: Array = []
	var total := 0
	for bk in boxes:
		for pool in _pools(boxes[bk]):
			for e in pool:
				total += 1
				var k := String((e as Dictionary).get("item", ""))
				if k.begins_with("egg:"):
					if not dragon_ids.has(int(k.substr(4))):
						bad.append("%s → %s (드래곤 없음)" % [bk, k])
				elif k.begins_with("equip:"):
					if not equip_names.has(k.substr(6)):
						bad.append("%s → %s (장비 없음)" % [bk, k])
				elif not items.has(k):
					bad.append("%s → %s (아이템 없음)" % [bk, k])
	for b in bad:
		print("    ", b)
	_ok(bad.is_empty(), "풀 항목 %d개 전부 실재 키" % total)

	print("\n=== 2) 열쇠 규칙 ===")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	var own := {"box": 1, "key": 1, "key_all": 1}
	var r := BoxLoot.open(t, "box", own, rng)
	_ok(bool(r.get("ok", false)) and String(r.get("key_used", "")) == "key",
		"비밀 상자: 고대 열쇠를 먼저 쓴다 (만능은 아낀다)")

	r = BoxLoot.open(t, "box_dark", {"box_dark": 1, "key_all": 1}, rng)
	_ok(bool(r.get("ok", false)) and String(r.get("key_used", "")) == "key_all",
		"어둠의 상자: 전용 열쇠가 없으면 만능 열쇠")

	r = BoxLoot.open(t, "box", {"box": 1}, rng)
	_ok(not bool(r.get("ok", false)) and String(r.get("reason", "")) == "no_key",
		"열쇠 없으면 개봉 실패(no_key)")

	_ok(not BoxLoot.keys_for(t, "magicbox").has("key_all"),
		"만능 열쇠는 마법상자를 못 연다 (위키 각주[97])")
	r = BoxLoot.open(t, "magicbox", {"magicbox": 1, "key_all": 1}, rng)
	_ok(not bool(r.get("ok", false)), "마법상자 + 만능 열쇠 → 실패")

	var gold_pool := BoxLoot.pool_for(t, "magicbox", "key_gold")
	var copper_pool := BoxLoot.pool_for(t, "magicbox", "key_copper")
	var has_chaos := func(pool: Array) -> bool:
		for e in pool:
			if String((e as Dictionary).get("item", "")).begins_with("chaos_egg_"):
				return true
		return false
	_ok(has_chaos.call(gold_pool) and not has_chaos.call(copper_pool),
		"금빛 열쇠에만 카오스의 알조각이 있다 (위키 §9.3)")

	print("\n=== 3) 열쇠 불필요 상자 ===")
	r = BoxLoot.open(t, "gudrabox_fire", {"gudrabox_fire": 1}, rng)
	_ok(bool(r.get("ok", false)) and (r["consumed"] as Array).size() == 1,
		"구드라의 상자: 열쇠 없이 열리고 상자만 소모")
	r = BoxLoot.open(t, "stone_pocket", {"stone_pocket": 1}, rng)
	_ok(bool(r.get("ok", false)) and (r["consumed"] as Array).size() == 1,
		"유용한 돌 자루: 열쇠 없이 열린다")

	print("\n=== 4) 가방에서 사용 가능한가(offline=impl) ===")
	var not_impl: Array = []
	for k in boxes:
		if String((items.get(k, {}) as Dictionary).get("offline", "")) != "impl":
			not_impl.append(String(k))
	for k in keys:
		if String((items.get(k, {}) as Dictionary).get("offline", "")) != "impl":
			not_impl.append(String(k))
	if not not_impl.is_empty():
		print("     todo/stub 로 남은 것: ", not_impl)
	_ok(not_impl.is_empty(), "상자 13 + 열쇠 6 = 19종 전부 impl")
	for k in ["box_gold", "box_silver"]:
		_ok(String((items.get(k, {}) as Dictionary).get("offline", "")) == "todo",
			"%s 는 표가 없어 계속 잠김" % Data_name(items, k))

	print("\n=== 5) 추첨 ===")
	var seen := {}
	var pool := BoxLoot.pool_for(t, "box", "key")
	_ok(BoxLoot.pool_for(t, "box").is_empty(), "열쇠를 안 주면 표가 안 나온다")
	for _i in 4000:
		var g := BoxLoot.roll(pool, rng)
		seen[String(g.get("key", ""))] = int(seen.get(String(g.get("key", "")), 0)) + 1
	_ok(seen.size() == pool.size(), "비밀 상자 %d종이 모두 나온다" % pool.size())
	var outside := false
	var in_pool := {}
	for e in pool:
		in_pool[String((e as Dictionary)["item"])] = true
	for k in seen:
		if not in_pool.has(k):
			outside = true
	_ok(not outside, "풀 밖의 것이 나오지 않는다")

	var sp := BoxLoot.pool_for(t, "stone_pocket")
	var cnt := {}
	for _i in 20000:
		var g2 := BoxLoot.roll(sp, rng)
		var kk := String(g2.get("key", ""))
		cnt[kk] = int(cnt.get(kk, 0)) + 1
	var egg_hits := 0
	for k in cnt:
		if String(k).begins_with("egg:"):
			egg_hits += int(cnt[k])
	var crystal_hits := int(cnt.get("crystal_fire", 0))
	_ok(egg_hits > 0 and egg_hits < crystal_hits * 2,
		"돌자루: 드래곤 알이 '낮은 확률로' 나온다 (알 %d회 vs 결정1종 %d회)"
			% [egg_hits, crystal_hits])

	print("\n=== 6) 연속 개봉 ===")
	var many := BoxLoot.open_many(t, "box", {"box": 10, "key": 3, "key_all": 2}, rng, 10)
	_ok(int(many.get("opened", 0)) == 5, "열쇠 5개만 있으면 5회에서 멈춘다 (실제 %d회)"
		% int(many.get("opened", 0)))

	print("\n=== %s ===" % ("ALL PASS" if _fail == 0 else "%d FAIL" % _fail))
	quit(1 if _fail > 0 else 0)

func Data_name(items: Dictionary, k: String) -> String:
	return String((items.get(k, {}) as Dictionary).get("name", k))

func _pools(box: Dictionary) -> Array:
	var out: Array = []
	if box.has("pool"):
		out.append(box["pool"])
	for tier in (box.get("tiers", {}) as Dictionary):
		out.append((box["tiers"][tier] as Dictionary).get("pool", []))
	return out

func _items() -> Dictionary:
	var d: Variant = _json_any(_data_file("items.json"))
	if d is Dictionary and (d as Dictionary).has("items"):
		return (d as Dictionary)["items"]
	return d as Dictionary

func _json(path: String) -> Dictionary:
	return _json_any(path) as Dictionary

func _json_arr(path: String) -> Array:
	return _json_any(path) as Array

func _json_any(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("못 읽음: " + path)
		return {}
	return JSON.parse_string(f.get_as_text())

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
