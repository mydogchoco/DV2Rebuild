extends SceneTree
## 헤드리스 TeamBuff 단위 테스트 (§10 — logic은 화면 없이 검증).
## 원작 근거: docs/ref/design/team_buff_analysis.md §2 (TeamBuff::isActivate, TeamBuff.c:2106-2197).
## 실행: godot --headless --path <proj> --script res://scripts/tools/test_team_buff.gd

const TB := preload("res://scripts/systems/team_buff.gd")

func _init() -> void:
	var fails := 0

	# 합성 테이블(유실 실데이터 대체 — 로직만 검증). combine=필요 종족×개수, effect=스탯델타.
	var table := {
		"buffs": [
			{"no": 1, "name": "이중불", "combine": {"fire": 2}, "effect": {"atk": 10}},
			{"no": 2, "name": "삼속성", "combine": {"fire": 1, "aqua": 1, "wind": 1}, "effect": {"hp": 30, "def": 5}},
			{"no": 3, "name": "물둘", "combine": {"aqua": 2}, "effect": {"atk": 8}},
			{"no": 4, "name": "빈조합", "combine": {}, "effect": {"atk": 999}},
		]
	}

	# 1) 활성화 의미(§2): 파티가 필요 종족×개수 충족 시 발동, 초과 무방, 부족 시 미발동.
	# 파티 [fire,fire,aqua] → 버프1(fire×2) 충족, 버프3(aqua×2) 부족, 버프2(3속성) 부족.
	var a1 := _names(TB.active_buffs(["fire", "fire", "aqua"], table))
	fails += _eq_arr("fire2+aqua1", a1, ["이중불"])

	# 파티 [fire,aqua,wind] → 버프2(3속성) 충족, 버프1(fire×2) 부족.
	var a2 := _names(TB.active_buffs(["fire", "aqua", "wind"], table))
	fails += _eq_arr("삼속성", a2, ["삼속성"])

	# 파티 [aqua,aqua,fire] → 버프3(aqua×2) 충족.
	var a3 := _names(TB.active_buffs(["aqua", "aqua", "fire"], table))
	fails += _eq_arr("aqua2", a3, ["물둘"])

	# 초과 보유 무방: [fire,fire,fire] → 버프1(fire×2) 여전히 발동.
	var a4 := _names(TB.active_buffs(["fire", "fire", "fire"], table))
	fails += _eq_arr("fire3 초과", a4, ["이중불"])

	# 부족: [fire] → 아무 버프도 발동 안 함.
	var a5 := _names(TB.active_buffs(["fire"], table))
	fails += _eq_arr("fire1 부족", a5, [])

	# 빈 조합(버프4)은 절대 발동 안 함(방어적).
	var a6 := _names(TB.active_buffs(["fire", "aqua", "wind", "earth"], table))
	fails += _b("빈조합 미발동", not a6.has("빈조합"))

	# 2) 스탯 집계: [fire,aqua,wind] → 버프2만 → {hp:30, def:5}.
	var s2 := TB.stats_for_party(["fire", "aqua", "wind"], table)
	fails += _eqf("삼속성 hp", float(s2.get("hp", 0)), 30.0)
	fails += _eqf("삼속성 def", float(s2.get("def", 0)), 5.0)

	# 여러 버프 동시: [fire,fire,aqua,aqua] → 버프1(atk10)+버프3(atk8) → atk 18.
	var s3 := TB.stats_for_party(["fire", "fire", "aqua", "aqua"], table)
	fails += _eqf("중첩 atk", float(s3.get("atk", 0)), 18.0)

	# 3) 빈 테이블 = no-op(유실 데이터 미충족 시 안전).
	var s0 := TB.stats_for_party(["fire", "fire"], {"buffs": []})
	fails += _b("빈테이블 no-op", s0.is_empty())

	# 4) JSON float count 정규화(combine 값이 2.0이어도 int로 처리).
	var tfloat := {"buffs": [{"no": 9, "combine": {"fire": 2.0}, "effect": {"atk": 1}}]}
	fails += _b("float count", TB.active_buffs(["fire", "fire"], tfloat).size() == 1)

	# 5) typed effect(위키 §2.3.3.1 형식) — 스탯마다 pct/point/flat 적용 방식이 다르다.
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

	# 6) 실데이터 — 30종이 실려 있고, combine 이 비어 있어 전부 미발동(안전 no-op).
	var real = JSON.parse_string(FileAccess.open("res://data/team_buffs.json", FileAccess.READ).get_as_text())
	fails += _b("실데이터 30종", (real.get("buffs", []) as Array).size() == 30)
	# combine 을 추론 채움(2026-07-27) → 실제로 발동해야 한다.
	var fire3 := TB.active_buffs(["fire", "fire", "fire"], real)
	fails += _b("불3 → 코로나 1종만 발동", fire3.size() == 1 and String(fire3[0]["name"]) == "코로나")
	var st_c := TB.apply({"att": 100}, TB.aggregate_typed(fire3))
	fails += _eqf("코로나 ATK+25%", float(st_c["att"]), 125.0)
	var mix := TB.active_buffs(["aqua", "aqua", "light"], real)
	fails += _b("물2+빛1 → 물빛 섬광", mix.size() == 1 and String(mix[0]["name"]) == "물빛 섬광")
	var tri := TB.active_buffs(["light", "dark", "holy"], real)
	fails += _b("빛·어둠·신성 → 아마겟돈", tri.size() == 1 and String(tri[0]["name"]) == "아마겟돈")
	# 30종 조합이 서로 겹치지 않는지: 같은 파티에 2종 이상 발동하면 설계 오류.
	var elems := ["fire", "aqua", "wind", "earth", "light", "dark", "holy", "chaos", "shadow"]
	var overlaps := 0
	for a in elems:
		for b2 in elems:
			for c2 in elems:
				if TB.active_buffs([a, b2, c2], real).size() > 1:
					overlaps += 1
	fails += _b("조합 중복 발동 없음(%d)" % overlaps, overlaps == 0)
	# 모든 버프가 최소 한 파티 조합으로 발동 가능한지(고아 조합 없음).
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
