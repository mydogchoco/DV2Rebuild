extends SceneTree
# 각성기 타격 분할 + 크리티컬 배수 검증 (2026-08-06).
#   (1) `Battle._awaken_split` 이 원작 `UltimateLayer::calculateDamage` 의 타수를 낸다
#   (2) 어떤 총액에서도 **분할 합 == 총액**(마무리 타가 나머지를 먹는다)
#   (3) `resolve_awaken` 이 대상 전원에게 타수만큼 이벤트를 내고, 첫 건에만 `lead` 가 붙고,
#       HP 감소 총량이 종전(한 방)과 같다
#   (4) `_crit_mult` 이 cri_pow 를 **증가분에만** 얹는다 (1 + 0.5×(1+p/100))
# Run: godot --headless --script res://scripts/tools/test_awaken_split.gd

const Battle := preload("res://scripts/systems/battle.gd")

func _cfg() -> Dictionary:
	var f := FileAccess.open("res://data/combat.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) as Dictionary

func _fighter(nm: String, el: String, hp: int, att: int, df: int) -> Dictionary:
	return Battle.make_combatant(nm, "ally", el, {"hp": hp, "att": att, "def": df})

func _initialize() -> void:
	var cfg := _cfg()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var fails: Array = []
	var tbl: Dictionary = cfg.get("awaken", {}).get("hits_by_element", {})

	# (1)(2) 타수 + 총합 보존
	print("속성      타수  총합보존")
	for el in tbl:
		var want := int((tbl[el] as Dictionary).get("hits", 0))
		var ok := true
		for total in [0, 1, 7, 45, 60, 120, 999, 33333, 1000000]:
			var parts: Array = Battle._awaken_split(int(total), String(el), rng, cfg)
			var sum := 0
			for p in parts:
				sum += int(p)
				if int(p) < 0:
					ok = false
					fails.append("%s: 음수 타격 %d" % [el, int(p)])
			if sum != int(total):
				ok = false
				fails.append("%s total=%d 합=%d (불일치)" % [el, total, sum])
			if parts.size() != want:
				ok = false
				fails.append("%s total=%d 타수=%d (표 %d)" % [el, total, parts.size(), want])
		print("%-9s %4d  %s" % [el, want, "OK" if ok else "FAIL"])

	# (3) resolve_awaken — 이벤트 수 · lead 1건 · HP 감소 총량
	for el in ["wind", "holy", "chaos"]:
		var atk := _fighter("시전자", String(el), 5000, 900, 100)
		var foes := [_fighter("적1", "fire", 400000, 100, 120),
			_fighter("적2", "earth", 400000, 100, 120)]
		var hp0 := int(foes[0]["hp"]) + int(foes[1]["hp"])
		var evs := Battle.resolve_awaken(atk, foes, rng, cfg)
		var hp1 := int(foes[0]["hp"]) + int(foes[1]["hp"])
		var dmg_sum := 0
		var leads := 0
		for e in evs:
			dmg_sum += int((e as Dictionary).get("damage", 0))
			if bool((e as Dictionary).get("volley_lead", false)):
				leads += 1
		var want_ev := int((tbl[el] as Dictionary).get("hits", 1)) * 2
		if evs.size() != want_ev:
			fails.append("%s resolve 이벤트 %d (기대 %d)" % [el, evs.size(), want_ev])
		if leads != 1:
			fails.append("%s lead %d건 (기대 1)" % [el, leads])
		if dmg_sum != hp0 - hp1:
			fails.append("%s 이벤트 합 %d != 실제 HP 감소 %d" % [el, dmg_sum, hp0 - hp1])
		if int(evs[0].get("volley", 0)) != want_ev:
			fails.append("%s volley %d (기대 %d)" % [el, int(evs[0].get("volley", 0)), want_ev])
		print("%-9s 이벤트 %3d · lead %d · 이벤트합 %d == HP감소 %d"
			% [el, evs.size(), leads, dmg_sum, hp0 - hp1])

	# (5) 진영 게이지 — 🟦 2026-08-06 사용자 확정 3건
	var pa: Array = [_fighter("약체", "fire", 9000, 100, 50),
		_fighter("에이스", "fire", 9000, 900, 50),      # 최고 공격력 = 시전자여야 한다
		_fighter("중간", "fire", 9000, 400, 50)]
	var pb: Array = [_fighter("적1", "wind", 900000, 80, 50),
		_fighter("적2", "wind", 900000, 80, 50)]
	for c in pb:
		(c as Dictionary)["side"] = "enemy"
	Battle._bind_side_gauge(pa)
	Battle._bind_side_gauge(pb)
	# ① 진영 공유 — 한 명을 통해 올리면 전원이 같은 값을 본다
	Battle._gauge_bump(pa[0], 40.0, false)
	var shared := true
	for c in pa:
		if absf(Battle.gauge_of(c) - 40.0) > 0.001:
			shared = false
	if not shared:
		fails.append("게이지가 진영 공유가 아니다")
	if absf(Battle.gauge_of(pb[0])) > 0.001:
		fails.append("상대 진영 게이지까지 올랐다")
	print("① 진영 공유 %s (아군 %.0f · 적 %.0f)"
		% ["OK" if shared else "FAIL", Battle.gauge_of(pa[0]), Battle.gauge_of(pb[0])])
	# ② 최고 공격력 드래곤이 시전자
	var caster: Dictionary = Battle._awaken_caster(pa)
	if String(caster.get("name", "")) != "에이스":
		fails.append("시전자가 '%s' (기대 '에이스')" % caster.get("name", ""))
	pa[1]["alive"] = false                              # 에이스가 죽으면 그 다음
	var caster2: Dictionary = Battle._awaken_caster(pa)
	if String(caster2.get("name", "")) != "중간":
		fails.append("에이스 사망 후 시전자가 '%s' (기대 '중간')" % caster2.get("name", ""))
	pa[1]["alive"] = true
	print("② 시전자 = %s · 사망 시 %s" % [caster.get("name", ""), caster2.get("name", "")])
	# ③ 피격 충전 — 맞은 **진영**이 찬다
	var per := float(cfg.get("awaken", {}).get("charge_per_hit", 0.0))
	var before := Battle.gauge_of(pb[0])
	Battle._charge_on_hits([{"type": "normal", "defender": "적1", "damage": 10}], pa, pb, cfg)
	var hit_got := Battle.gauge_of(pb[0]) - before
	if absf(hit_got - per) > 0.001:
		fails.append("피격 충전 %.2f (기대 %.2f)" % [hit_got, per])
	# 각성기 연타는 대상당 1회만
	var before2 := Battle.gauge_of(pb[0])
	var volley: Array = []
	for i in 20:
		volley.append({"type": "awaken", "defender": "적1", "damage": 5, "hit": i})
	Battle._charge_on_hits(volley, pa, pb, cfg)
	var vol_got := Battle.gauge_of(pb[0]) - before2
	if absf(vol_got - per) > 0.001:
		fails.append("각성기 20타 충전 %.2f (기대 %.2f = 1회분)" % [vol_got, per])
	print("③ 피격 충전 %.2f · 각성기 20타도 %.2f (1회분)" % [hit_got, vol_got])

	# (4) 크리 배수 — 증가분에만 cri_pow
	var base := float(cfg.get("damage", {}).get("crit_mult", 1.5))
	for p in [0, 50, 100, 150]:
		var c := _fighter("c", "fire", 100, 100, 100)
		c["cri_pow"] = int(p)
		var got := Battle._crit_mult(c, cfg)
		var want := 1.0 + (base - 1.0) * (1.0 + float(p) / 100.0)
		if absf(got - want) > 0.0001:
			fails.append("cri_pow %d → %.3f (기대 %.3f)" % [p, got, want])
		print("cri_pow %3d%% → 크리 배수 %.2f" % [p, got])

	print("")
	if fails.is_empty():
		print("PASS — 전 항목 통과")
	else:
		print("FAIL %d건:" % fails.size())
		for m in fails:
			print("  - %s" % m)
	quit(0 if fails.is_empty() else 1)
