extends SceneTree

const TB := preload("res://scripts/systems/team_buff.gd")

func _init() -> void:
	var fails := 0

	var table := {
		"buffs": [
			{"no": 1, "name": "이중불", "combine": {"fire": 2}, "effect": {"atk": 10}},
			{"no": 2, "name": "삼속성", "combine": {"fire": 1, "aqua": 1, "wind": 1}, "effect": {"hp": 30, "def": 5}},
			{"no": 3, "name": "물둘", "combine": {"aqua": 2}, "effect": {"atk": 8}},
			{"no": 4, "name": "빈조합", "combine": {}, "effect": {"atk": 999}},
		]
	}

	var a1 := _names(TB.active_buffs(["fire", "fire", "aqua"], table))
	fails += _eq_arr("fire2+aqua1", a1, ["이중불"])

	var a2 := _names(TB.active_buffs(["fire", "aqua", "wind"], table))
	fails += _eq_arr("삼속성", a2, ["삼속성"])

	var a3 := _names(TB.active_buffs(["aqua", "aqua", "fire"], table))
	fails += _eq_arr("aqua2", a3, ["물둘"])

	var a4 := _names(TB.active_buffs(["fire", "fire", "fire"], table))
	fails += _eq_arr("fire3 초과", a4, ["이중불"])

	var a5 := _names(TB.active_buffs(["fire"], table))
	fails += _eq_arr("fire1 부족", a5, [])

	var a6 := _names(TB.active_buffs(["fire", "aqua", "wind", "earth"], table))
	fails += _b("빈조합 미발동", not a6.has("빈조합"))

	var s2 := TB.stats_for_party(["fire", "aqua", "wind"], table)
	fails += _eqf("삼속성 hp", float(s2.get("hp", 0)), 30.0)
	fails += _eqf("삼속성 def", float(s2.get("def", 0)), 5.0)

	var s3 := TB.stats_for_party(["fire", "fire", "aqua", "aqua"], table)
	fails += _eqf("중첩 atk", float(s3.get("atk", 0)), 18.0)

	var s0 := TB.stats_for_party(["fire", "fire"], {"buffs": []})
	fails += _b("빈테이블 no-op", s0.is_empty())

	var tfloat := {"buffs": [{"no": 9, "combine": {"fire": 2.0}, "effect": {"atk": 1}}]}
	fails += _b("float count", TB.active_buffs(["fire", "fire"], tfloat).size() == 1)

	var ttyped := {"buffs": [
		{"no": 1, "name": "코로나", "combine": {"fire": 3},
		 "effect": {"att": {"mode": "pct", "value": 25}}},
		{"no": 2, "name": "쉐도우 댄스", "combine": {"fire": 3},
		 "effect": {"cri": {"mode": "point", "value": 10}, "evd": {"mode": "point", "value": 5}}},
		{"no": 3, "name": "이클립스", "combine": {"fire": 3},
		 "effect": {"pure": {"mode": "flat", "value": 10}}},
	]}
	var ty := TB.typed_for_party(["fire", "fire", "fire"], ttyped)
	var st := TB.apply({"att": 100, "cri": 10, "evd": 10, "pure": 0}, ty)
	fails += _eqf("코로나 att ×1.25", float(st["att"]), 125.0)
	fails += _eqf("쉐도우댄스 cri +10%p", float(st["cri"]), 20.0)
	fails += _eqf("쉐도우댄스 evd +5%p", float(st["evd"]), 15.0)
	fails += _eqf("이클립스 pure flat", float(st["pure"]), 10.0)

	var real = JSON.parse_string(FileAccess.open(_data_file("team_buffs.json"), FileAccess.READ).get_as_text())
	fails += _b("실데이터 30종", (real.get("buffs", []) as Array).size() == 30)
	var fire3 := TB.active_buffs(["fire", "fire", "fire"], real)
	fails += _b("불3 → 코로나 1종만 발동", fire3.size() == 1 and String(fire3[0]["name"]) == "코로나")
	var st_c := TB.apply({"att": 100}, TB.aggregate_typed(fire3))
	fails += _eqf("코로나 ATK+25%", float(st_c["att"]), 125.0)
	var mix := TB.active_buffs(["aqua", "aqua", "light"], real)
	fails += _b("물2+빛1 → 물빛 섬광", mix.size() == 1 and String(mix[0]["name"]) == "물빛 섬광")
	var tri := TB.active_buffs(["light", "dark", "holy"], real)
	fails += _b("빛·어둠·신성 → 아마겟돈", tri.size() == 1 and String(tri[0]["name"]) == "아마겟돈")
	var elems := ["fire", "aqua", "wind", "earth", "light", "dark", "holy", "chaos", "shadow"]
	var overlaps := 0
	for a in elems:
		for b2 in elems:
			for c2 in elems:
				if TB.active_buffs([a, b2, c2], real).size() > 1:
					overlaps += 1
	fails += _b("조합 중복 발동 없음(%d)" % overlaps, overlaps == 0)
	var reachable := {}
	for a in elems:
		for b2 in elems:
			for c2 in elems:
				for bf in TB.active_buffs([a, b2, c2], real):
					reachable[int(bf["no"])] = true
	fails += _b("30종 모두 발동 가능(%d)" % reachable.size(), reachable.size() == 30)

	if fails == 0:
		print("[test_team_buff] ALL PASS")
		quit(0)
	else:
		printerr("[test_team_buff] %d FAIL" % fails)
		quit(1)

func _names(arr: Array) -> Array:
	var out: Array = []
	for b in arr:
		out.append(b.get("name", str(b.get("no"))))
	out.sort()
	return out

func _eq_arr(tag: String, got: Array, want: Array) -> int:
	var w := want.duplicate(); w.sort()
	if got == w:
		return 0
	printerr("FAIL %s: got=%s want=%s" % [tag, got, w])
	return 1

func _eqf(tag: String, got: float, want: float) -> int:
	if abs(got - want) < 0.001:
		return 0
	printerr("FAIL %s: got=%f want=%f" % [tag, got, want])
	return 1

func _b(tag: String, cond: bool) -> int:
	if cond:
		return 0
	printerr("FAIL %s" % tag)
	return 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
