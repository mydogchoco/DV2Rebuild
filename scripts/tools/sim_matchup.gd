extends Node

func _ready() -> void:
	await get_tree().process_frame
	var n := 200
	var mode := "team"
	var a_key := "999"
	var b_key := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sim-n="): n = int(arg.substr(8))
		elif arg.begins_with("--sim-mode="): mode = arg.substr(11)
		elif arg.begins_with("--sim-a="): a_key = arg.substr(8)
		elif arg.begins_with("--sim-b="): b_key = arg.substr(8)

	var why := "--sim-why=1" in OS.get_cmdline_user_args()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260805
	var foes: Array = []
	if b_key != "":
		foes.append(b_key)
	else:
		for r: Dictionary in (Data.colosseum.get("rankers", []) as Array):
			foes.append(String(r.get("nick", "")))

	print("[sim] %s vs 랭커 %d명 · %s · 각 %d판" % [a_key, foes.size(), mode, n])
	if "--sim-dump=1" in OS.get_cmdline_user_args():
		_dump(a_key, mode, rng)
		for foe_key: String in foes:
			_dump(foe_key, mode, rng)
	var tot_win := 0
	var tot := 0
	for foe_key: String in foes:
		var win := 0
		var rounds := 0
		for i in n:
			var res := _battle(a_key, foe_key, mode, rng)
			if String(res.get("winner", "")) == "ally":
				win += 1
			elif why:
				_tally(res, foe_key)
			if why:
				_tally_all(res, foe_key)
			rounds += int(res.get("rounds", 0))
		tot_win += win
		tot += n
		print("[sim]   vs %-12s  승률 %5.1f%%  (%d/%d)  평균 %.1f라운드"
			% [foe_key, 100.0 * win / n, win, n, float(rounds) / n])
	if foes.size() > 1:
		print("[sim] 전체 %5.1f%% (%d/%d)" % [100.0 * tot_win / tot, tot_win, tot])
	if why:
		_report_why()
	if "--sim-trace=1" in OS.get_cmdline_user_args():
		_report_trace()
	get_tree().quit()

var _all: Dictionary = {}
var _lose: Dictionary = {}

func _tally_all(res: Dictionary, foe_key: String) -> void:
	for k: String in _keys(res, foe_key):
		_all[k] = int(_all.get(k, 0)) + 1

func _tally(res: Dictionary, foe_key: String) -> void:
	for k: String in _keys(res, foe_key):
		_lose[k] = int(_lose.get(k, 0)) + 1

func _keys(res: Dictionary, foe_key: String) -> Array:
	var out: Array = ["상대|" + foe_key]
	out.append("무대|" + String(res.get("stage_note", "")))
	out.append("상대 드래곤|" + String(res.get("foe_names", "")))
	out.append("선대군 스킬|" + String(res.get("my_skills", "")))
	out.append("상대 스킬|" + String(res.get("foe_skills", "")))
	return out

func _report_why() -> void:
	var dims := ["무대", "상대 드래곤", "선대군 스킬", "상대 스킬", "상대"]
	for dim: String in dims:
		var rows: Array = []
		for k: String in _all:
			if not k.begins_with(dim + "|"):
				continue
			var tot := int(_all[k])
			var lost := int(_lose.get(k, 0))
			if tot < 12:
				continue
			rows.append({"cat": k.substr(dim.length() + 1), "tot": tot, "lost": lost,
				"pct": 100.0 * lost / tot})
		if rows.is_empty():
			continue
		rows.sort_custom(func(a, b): return float(a["pct"]) > float(b["pct"]))
		print("[sim] ── %s 별 패배율" % dim)
		for r: Dictionary in rows.slice(0, 8):
			print("[sim]     %-46s %5.1f%%  (%d/%d)"
				% [r["cat"], r["pct"], r["lost"], r["tot"]])

func _make(key: String, mode: String, rng: RandomNumberGenerator) -> Dictionary:
	var bot: Dictionary = {}
	if key.is_valid_int():
		var g := Colosseum.guard_for(int(key))
		if g.is_empty():
			push_error("[sim] 연승 %s 에 해당하는 방지봇이 없다" % key)
			return {}
		bot = Colosseum.make_guard(g, mode, rng)
	else:
		for r: Dictionary in (Data.colosseum.get("rankers", []) as Array):
			if String(r.get("nick", "")) == key:
				bot = Colosseum._make_ranker(r, mode, rng)
				break
	if bot.is_empty():
		push_error("[sim] '%s' 를 랭커 시트에서 못 찾았다" % key)
		return {}
	_swap_skills(bot)
	return bot

func _swap_skills(bot: Dictionary) -> void:
	var spec := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sim-skills="):
			spec = arg.substr(13)
	if spec == "":
		return
	var by_name := {}
	for sid: String in Data.skills:
		by_name[String((Data.skills[sid] as Dictionary).get("name", "")).replace(" ", "")] = int(sid)
	for chunk: String in spec.split(";", false):
		var bits: PackedStringArray = chunk.split(":", false)
		if bits.size() < 2:
			continue
		var want := bits[0].strip_edges()
		var ids: Array = []
		for nm: String in bits[1].split("+", false):
			var sid2 = by_name.get(nm.strip_edges().replace(" ", ""))
			if sid2 == null:
				push_error("[sim] 스킬 '%s' 를 못 찾았다" % nm)
				continue
			ids.append(int(sid2))
		for d: Dictionary in (bot.get("dragons", []) as Array):
			if String(Data.get_dragon(int(d.get("id", 0))).get("name", "")) != want:
				continue
			var lv := 5
			for s in (d.get("skills", []) as Array):
				lv = int((s as Dictionary).get("level", 5))
				break
			var learned: Array = []
			var eq: Array = []
			for sid3: int in ids:
				learned.append({"id": sid3, "level": lv})
				if eq.size() < Loadout.SKILL_SLOTS:
					eq.append(sid3)
			while eq.size() < Loadout.SKILL_SLOTS:
				eq.append(0)
			d["skills"] = learned
			d["skill_equip"] = eq

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
	var res: Dictionary = Battle.simulate(_side(pa, "ally"), _side(pb, "enemy"),
		rng, Data.combat, Data.skills)
	var my_buff := _buffed(pa)
	var fo_buff := _buffed(pb)
	res["stage_note"] = "%s (%s)" % [sel,
		"양쪽" if my_buff and fo_buff else
		("선대군 버프" if my_buff else ("상대 버프" if fo_buff else "무버프"))]
	res["foe_names"] = _names(pb)
	if "--sim-trace=1" in OS.get_cmdline_user_args():
		_trace(res, pa, pb)
	res["my_skills"] = _skill_names(pa)
	res["foe_skills"] = _skill_names(pb)
	return res

var _atk: Dictionary = {}

func _trace(res: Dictionary, pa: Array, pb: Array) -> void:
	var who := {}
	for i in pa.size():
		who["A%d" % i] = String((pa[i] as Dictionary).get("name", ""))
	for i in pb.size():
		who["E%d" % i] = String((pb[i] as Dictionary).get("name", ""))
	for e in (res.get("events", []) as Array):
		var ev := e as Dictionary
		if String(ev.get("type", "")) != "normal":
			continue
		if not String(ev.get("attacker", "")).begins_with("A"):
			continue
		var key := "%s → %s" % [who.get(String(ev.get("attacker", "")), "?"),
			who.get(String(ev.get("defender", "")), "?")]
		var r: Dictionary = _atk.get(key, {"n": 0, "miss": 0, "crit": 0, "dmg": 0})
		r["n"] = int(r["n"]) + 1
		if bool(ev.get("miss", false)):
			r["miss"] = int(r["miss"]) + 1
		if bool(ev.get("crit", false)):
			r["crit"] = int(r["crit"]) + 1
		r["dmg"] = int(r["dmg"]) + int(ev.get("damage", 0))
		_atk[key] = r

func _report_trace() -> void:
	var keys: Array = _atk.keys()
	keys.sort()
	print("[sim] ── 선대군 평타 판정 (상대별)")
	for k: String in keys:
		var r: Dictionary = _atk[k]
		var n := int(r["n"])
		if n < 30:
			continue
		print("[sim]     %-28s 평타 %5d회  빗나감 %4.1f%%  크리 %4.1f%%  평균피해 %d"
			% [k, n, 100.0 * int(r["miss"]) / n, 100.0 * int(r["crit"]) / n,
			int(r["dmg"]) / maxi(1, n - int(r["miss"]))])

func _buffed(team: Array) -> bool:
	for p: Dictionary in team:
		if bool(p.get("stage_buff", false)):
			return true
	return false

func _names(team: Array) -> String:
	var out: Array = []
	for p: Dictionary in team:
		out.append(String(p.get("name", "")))
	return ", ".join(out)

func _skill_names(team: Array) -> String:
	var out: Array = []
	for p: Dictionary in team:
		var ns: Array = []
		for s: Dictionary in (p.get("skills", []) as Array):
			ns.append(String(Data.skills.get(str(int(s.get("id", 0))), {}).get("name", "?")))
		ns.sort()
		out.append("+".join(ns))
	return " / ".join(out)

func _dump(key: String, mode: String, rng: RandomNumberGenerator) -> void:
	var bot := _make(key, mode, rng)
	var party: Array = PartyStats.summary_of(
		(bot.get("dragons", []) as Array).slice(0, Colosseum.party_size(mode)), false, "")
	var head: Dictionary = party[0] if not party.is_empty() else {}
	PartyStats.apply_passives(party, {"element": String(head.get("element", "")),
		"hp": int(head.get("hp_max", 1))}, {"field_element": "", "enemy_boss": false})
	print("[sim] --- %s" % String(bot.get("nick", key)))
	var cap := Battle._crit_cap(Data.combat)
	for p: Dictionary in party:
		var st: Dictionary = p["stats"]
		var c := Battle.make_combatant("X", "ally", String(p.get("element", "")), st, 0.0,
			p.get("skills", []), p.get("skill_slots", []))
		for e in (p.get("awaken_effects", []) as Array):
			(c["effects"] as Array).append((e as Dictionary).duplicate())
		print("[sim]     %-12s 등급%.1f  hp %5d  att %4d  def %4d  관통 %3d  cri %.0f(판정 %.0f)  evd %.0f  cri_pow %d"
			% [p["name"], p["grade"], int(p.get("hp_max", st.get("hp", 0))),
			Battle._eff(c, "att"), Battle._eff(c, "def"), Battle._eff(c, "pure"),
			Battle._eff_f(c, "cri"), minf(Battle._eff_f(c, "cri"), float(cap)),
			Battle._eff_f(c, "evd"), Battle._eff(c, "cri_pow")])

func _side(team: Array, side: String) -> Array:
	var out: Array = []
	for i in team.size():
		var p: Dictionary = team[i]
		var c := Battle.make_combatant(("A%d" if side == "ally" else "E%d") % i,
			side, String(p.get("element", "")), p.get("stats", {}), 0.0,
			p.get("skills", []), p.get("skill_slots", []))
		c["hp_max"] = int(p.get("hp_max", c["hp_max"]))
		c["hp"] = int(p.get("hp", c["hp_max"]))
		c["awaken_no"] = int(p.get("awaken_skill", 0))
		c["grade"] = float(p.get("grade", 0.0))
		c["dragon_id"] = int(p.get("id", 0))
		c["atk_type"] = String(p.get("atk_type", ""))
		c["awaken_gauge"] = float(p.get("awaken_gauge", 0.0))
		for e in (p.get("awaken_effects", []) as Array):
			(c["effects"] as Array).append((e as Dictionary).duplicate())
		out.append(c)
	return out
