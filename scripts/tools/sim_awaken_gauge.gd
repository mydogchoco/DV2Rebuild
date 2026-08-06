extends Node
## 각성기 게이지 **실측** — 실전 PvP에서 각성기가 언제(몇 라운드에) 터지는가.
##
## 조립은 `sim_matchup.gd` 와 같다(랭커/방지봇 · 무대 속성 추첨 · 스킬 2칸 재추첨) —
## 같은 매치를 돌려야 뜻이 있다. 여기서는 승패 대신 **각성기 발동 시점**만 센다.
##
## 사용(임시 오토로드로 등록해 실행):
##   --sim-n=<판수>  --sim-mode=<team|single>
##
## 왜 필요한가: `charge_per_turn` 은 "행동 1회당" 충전인데 `Battle.simulate` 는
## **매 라운드 주도 진영만** 행동시킨다 ⇒ 한 드래곤의 행동 기회는 라운드의 절반쯤이다.
## 그래서 "만충 28행동"을 라운드로 옮기면 두 배가 되고, 전투가 그 전에 끝나면 아예 못 본다.

func _ready() -> void:
	await get_tree().process_frame
	var n := 300
	var mode := "team"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sim-n="): n = int(arg.substr(8))
		elif arg.begins_with("--sim-mode="): mode = arg.substr(11)

	var aw: Dictionary = Data.combat.get("awaken", {})
	var per := float(aw.get("charge_per_turn", 3.6))
	print("[gauge] charge_per_turn=%.2f · 만충 100 ⇒ 순수 %d 행동" % [per, ceili(100.0 / per)])
	print("[gauge] %s · %d판 (랭커 전원 순회)" % [mode, n])

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260806
	var foes: Array = []
	for r: Dictionary in (Data.colosseum.get("rankers", []) as Array):
		foes.append(String(r.get("nick", "")))
	if foes.is_empty():
		push_error("[gauge] 랭커 시트가 비어 있다")
		get_tree().quit()
		return

	var battles := 0
	var with_awaken := 0          # 각성기가 한 번이라도 나온 전투
	var first_rounds: Array = []  # 그 전투에서 **첫 각성기**가 나온 라운드
	var fires := 0                # 총 발동 횟수(발동 = lead 이벤트 1건)
	var all_rounds: Array = []    # 전투 길이

	for foe_key: String in foes:
		for _i in n:
			var res := _battle("999", foe_key, mode, rng)
			if res.is_empty():
				continue
			battles += 1
			all_rounds.append(int(res.get("rounds", 0)))
			var first := -1
			for e in (res.get("events", []) as Array):
				if not (e is Dictionary):
					continue
				var ev: Dictionary = e
				# ⚠️ `bool(x)`/`String(x)` 는 x 가 null 이면 4.7 런타임 에러다 — 직접 비교한다.
				if ev.get("type", "") != "awaken" or ev.get("volley_lead", false) != true:
					continue
				fires += 1
				if first < 0:
					first = int(ev.get("round", 0))
			if first > 0:
				with_awaken += 1
				first_rounds.append(first)

	print("[gauge] 전투 %d판 · 평균 길이 %.1f라운드 (중앙값 %d · 최장 %d)"
		% [battles, _mean(all_rounds), _median(all_rounds), _max(all_rounds)])
	print("[gauge] 각성기가 나온 전투 %d판 (%.1f%%) · 총 발동 %d회"
		% [with_awaken, 100.0 * float(with_awaken) / maxf(1.0, float(battles)), fires])
	if first_rounds.is_empty():
		print("[gauge] ⇒ 실전에서 각성기를 **한 번도 못 본다**.")
	else:
		print("[gauge] 첫 각성기 라운드: 평균 %.1f · 중앙값 %d · 최소 %d"
			% [_mean(first_rounds), _median(first_rounds), _min(first_rounds)])
	# 전투가 몇 라운드까지 가야 각성기를 볼 수 있는지 — 길이 분포로 되짚는다.
	var need := ceili(100.0 / per)
	print("[gauge] 참고: 만충 %d행동 · 주도 진영만 행동하므로 라운드로는 대략 %d~%d"
		% [need, need, need * 2])
	get_tree().quit()


func _battle(a_key: String, b_key: String, mode: String, rng: RandomNumberGenerator) -> Dictionary:
	var a := _make(a_key, mode, rng)
	var b := _make(b_key, mode, rng)
	if a.is_empty() or b.is_empty():
		return {}
	var nn := Colosseum.party_size(mode)
	var sel := String(Colosseum.roll_stage(rng).get("element", ""))
	var pa: Array = PartyStats.summary_of((a.get("dragons", []) as Array).slice(0, nn),
		false, "", {}, sel)
	var pb: Array = PartyStats.summary_of((b.get("dragons", []) as Array).slice(0, nn),
		false, "", {}, sel)
	var ctx := {"field_element": sel, "enemy_boss": false}
	if not pa.is_empty() and not pb.is_empty():
		PartyStats.apply_passives(pa, {"element": String((pb[0] as Dictionary).get("element", "")),
			"hp": int((pb[0] as Dictionary).get("hp_max", 1))}, ctx)
		PartyStats.apply_passives(pb, {"element": String((pa[0] as Dictionary).get("element", "")),
			"hp": int((pa[0] as Dictionary).get("hp_max", 1))}, ctx)
	return Battle.simulate(_side(pa, "ally"), _side(pb, "enemy"), rng, Data.combat, Data.skills)


func _make(key: String, mode: String, rng: RandomNumberGenerator) -> Dictionary:
	var bot: Dictionary = {}
	if key.is_valid_int():
		var g := Colosseum.guard_for(int(key))
		if not g.is_empty():
			bot = Colosseum.make_guard(g, mode, rng)
	else:
		for r: Dictionary in (Data.colosseum.get("rankers", []) as Array):
			if String(r.get("nick", "")) == key:
				bot = Colosseum._make_ranker(r, mode, rng)
				break
	return bot


func _side(party: Array, side: String) -> Array:
	var out: Array = []
	for p in party:
		var pd := p as Dictionary
		var c := Battle.make_combatant(String(pd.get("name", "?")), side,
			String(pd.get("element", "fire")), pd, float(pd.get("pen", 0.0)),
			pd.get("skills", []), pd.get("skill_slots", []))
		c["awaken_no"] = int(pd.get("awaken_skill", 0))
		for e in (pd.get("awaken_effects", []) as Array):
			(c["effects"] as Array).append(e)
		out.append(c)
	return out


func _mean(a: Array) -> float:
	if a.is_empty(): return 0.0
	var s := 0.0
	for v in a: s += float(v)
	return s / float(a.size())

func _median(a: Array) -> int:
	if a.is_empty(): return 0
	var b := a.duplicate(); b.sort()
	return int(b[b.size() / 2])

func _min(a: Array) -> int:
	var b := a.duplicate(); b.sort()
	return int(b[0]) if not b.is_empty() else 0

func _max(a: Array) -> int:
	var b := a.duplicate(); b.sort()
	return int(b[b.size() - 1]) if not b.is_empty() else 0
