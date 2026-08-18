class_name Colosseum

const PMETA_KEY := "colosseum"

const BOT_UID_BASE := 900000

static func _default_state() -> Dictionary:
	var start := int(_cfg().get("rating", {}).get("start", 1000))
	return {
		"single": start, "tournament": start,
		"straight_single": 0, "straight_team": 0,
		"straight_single_best": 0, "straight_team_best": 0,
		"energy_single": int(_cfg().get("ticket", {}).get("max", 10)),
		"energy_at_single": 0,
		"energy_team": int(_cfg().get("ticket", {}).get("max", 10)),
		"energy_at_team": 0,
		"guard_served": {},
		"guard_met": {},
		"tier_paid": [],

		"history": [],
		"popup_welcome": false,
		"last_mode": "team",
		"rating_gap_mult": int((_cfg().get("tier", {}) as Dictionary).get("gap_mult", 1)),
	}

static func _cfg() -> Dictionary:
	return Data.colosseum

static func state() -> Dictionary:
	var s: Dictionary = UserDB.get_pmeta(PMETA_KEY, {})
	var d := _default_state()
	if s.is_empty():
		return d
	for k in s:
		d[k] = s[k]
	if not s.has("guard_served"):
		d["guard_served"] = _served_from_streaks(d)
	d.erase("guard_left")
	if not s.has("rating_gap_mult"):
		d["rating_gap_mult"] = 1
	d.erase("rating_scale")
	return _migrate_rating_scale(_migrate_energy_split(s, d))

static func _migrate_energy_split(s: Dictionary, d: Dictionary) -> Dictionary:
	if not s.has("energy"):
		return d
	var mx := int(_cfg().get("ticket", {}).get("max", 10))
	for mode in (_cfg().get("modes", {}) as Dictionary):
		var mc := mode_cfg(String(mode))
		var ek := String(mc.get("energy_key", ""))
		var ak := String(mc.get("energy_at_key", ""))
		if ek == "" or s.has(ek):
			continue
		d[ek] = clampi(int(s.get("energy", mx)), 0, mx)
		if ak != "":
			d[ak] = int(s.get("energy_at", 0))
	d.erase("energy")
	d.erase("energy_at")
	return d

static func _migrate_rating_scale(s: Dictionary) -> Dictionary:
	var tier: Dictionary = _cfg().get("tier", {})
	var want := float(tier.get("gap_mult", 1))
	var have := float(s.get("rating_gap_mult", 1))
	if want <= 0.0 or have <= 0.0 or is_equal_approx(have, want):
		return s
	var base := float(tier.get("gap_base", _cfg().get("rating", {}).get("start", 1000)))
	var k := want / have
	for key in ["single", "tournament"]:
		var r := float(s.get(key, base))
		s[key] = int(round(maxf(0.0, base + (r - base) * k)))
	s["pvp_total_rank"] = {}
	s["pvp_week_rank"] = {}
	s["pvp_rank_sig"] = ""
	s["rating_gap_mult"] = int(want)
	return s

static func _served_from_streaks(s: Dictionary) -> Dictionary:
	var out := {}
	for mode in (_cfg().get("modes", {}) as Dictionary):
		var sk := String((mode_cfg(String(mode))).get("streak_key", ""))
		var streak := int(s.get(sk, 0))
		var done: Array = []
		for g: Dictionary in (_cfg().get("guards", []) as Array):
			var at := guard_streak_at(g)
			if at <= streak:
				done.append(at)
		if not done.is_empty():
			out[String(mode)] = done
	return out

static func save_state(s: Dictionary) -> void:
	UserDB.set_pmeta(PMETA_KEY, s)

static func mode_cfg(mode: String) -> Dictionary:
	return (_cfg().get("modes", {}) as Dictionary).get(mode, {})

static func party_size(mode: String) -> int:
	return int(mode_cfg(mode).get("party", 3))

static func min_level() -> int:
	return int(_cfg().get("entry", {}).get("min_level", 25))

static func eligible(uid: int) -> bool:
	var d := UserDB.get_dragon(uid)
	return not d.is_empty() and int(d.get("level", 1)) >= min_level()

static func eligible_uids() -> Array:
	var out: Array = []
	for d in UserDB.dragons():
		if int((d as Dictionary).get("level", 1)) >= min_level():
			out.append(int((d as Dictionary).get("uid", 0)))
	return out

static func rating_of(mode: String) -> int:
	return int(state().get(String(mode_cfg(mode).get("rating_key", "tournament")), 0))

static func streak_of(mode: String) -> int:
	return int(state().get(String(mode_cfg(mode).get("streak_key", "straight_team")), 0))

static func last_mode() -> String:
	var m := String(state().get("last_mode", ""))
	return m if (_cfg().get("modes", {}) as Dictionary).has(m) else "team"

static func set_last_mode(mode: String) -> void:
	if not (_cfg().get("modes", {}) as Dictionary).has(mode):
		return
	var s := state()
	if String(s.get("last_mode", "")) == mode:
		return
	s["last_mode"] = mode
	save_state(s)

static func tier_of(rating: int) -> Dictionary:
	var list: Array = (_cfg().get("tier", {}) as Dictionary).get("list", [])
	var best: Dictionary = {}
	for t: Dictionary in list:
		if rating >= int(t.get("min_rating", 0)):
			if best.is_empty() or int(t["min_rating"]) >= int(best["min_rating"]):
				best = t
	return best

static func tier_frame(rating: int, kind: String) -> String:
	var t := tier_of(rating)
	if t.is_empty():
		return ""
	var pat := String((_cfg().get("tier", {}) as Dictionary).get("frames", {}).get(kind, ""))
	if pat == "":
		return ""
	var key := String(t.get("icon_fallback", "")) if String(t.get("icon_fallback", "")) != "" \
		else String(t.get("key", ""))
	return pat % key

static func demoted_rating(rating: int) -> int:
	var start := int(_cfg().get("rating", {}).get("start", 1000))
	var drop := season_tier_drop()
	var cur := tier_of(rating)
	if drop <= 0 or cur.is_empty():
		return start
	var want := int(cur.get("id", 0)) - drop
	var best: Dictionary = {}
	for t: Dictionary in (_cfg().get("tier", {}) as Dictionary).get("list", []):
		if int(t.get("id", 0)) <= want and (best.is_empty() or int(t["id"]) > int(best["id"])):
			best = t
	if best.is_empty():
		return start
	return maxi(start, int(best.get("min_rating", start)))

static func season_tier_drop() -> int:
	return int((_cfg().get("season", {}) as Dictionary).get("reset", {}).get("tier_drop", 0))

static func to_next_tier(rating: int) -> int:
	var list: Array = (_cfg().get("tier", {}) as Dictionary).get("list", [])
	var nxt := -1
	for t: Dictionary in list:
		var m := int(t.get("min_rating", 0))
		if m > rating and (nxt < 0 or m < nxt):
			nxt = m
	return 0 if nxt < 0 else nxt - rating

static func rating_points(rating: int) -> Dictionary:
	var r: Dictionary = _cfg().get("rating", {})
	var id := int(tier_of(rating).get("id", 0))
	var row: Dictionary = (r.get("by_tier", {}) as Dictionary).get(str(id), {})
	return {"win": int(row.get("win", r.get("win", 0))),
			"lose": int(row.get("lose", r.get("lose", 0)))}

static func rating_delta(win: bool, streak: int, rating: int) -> int:
	var r: Dictionary = _cfg().get("rating", {})
	var pts := rating_points(rating)
	if not win:
		return int(pts["lose"])
	var bonus := mini(int(r.get("streak_bonus_per", 0)) * maxi(0, streak),
		int(r.get("streak_bonus_max", 0)))
	return int(pts["win"]) + bonus

static func apply_result(mode: String, win: bool, opponent_nick := "",
		foe: Dictionary = {}) -> Dictionary:
	var s := state()
	var mc := mode_cfg(mode)
	var rk := String(mc.get("rating_key", "tournament"))
	var sk := String(mc.get("streak_key", "straight_team"))
	var bk := sk + "_best"

	s["last_mode"] = mode
	var before := int(s.get(rk, 0))
	var streak := int(s.get(sk, 0))
	var delta := rating_delta(win, streak, before)
	var after := maxi(int(_cfg().get("rating", {}).get("min", 0)), before + delta)

	var t_before := tier_of(before)
	var t_after := tier_of(after)

	s[rk] = after
	s[sk] = streak + 1 if win else 0
	s[bk] = maxi(int(s.get(bk, 0)), int(s[sk]))

	if not win:
		var srv: Dictionary = (s.get("guard_served", {}) as Dictionary).duplicate()
		srv.erase(mode)
		s["guard_served"] = srv

	var hist: Array = (s.get("history", []) as Array).duplicate()
	hist.push_front({"mode": mode, "win": win, "delta": delta, "foe": opponent_nick})
	while hist.size() > 20:
		hist.pop_back()
	s["history"] = hist

	var coin := match_coin(mode, win, streak)
	var tier_bonus := 0
	if int(t_after.get("id", 0)) > int(t_before.get("id", 0)):
		var paid: Array = (s.get("tier_paid", []) as Array).duplicate()
		var tid := int(t_after.get("id", 0))
		if not paid.has(tid):
			tier_bonus = int((_cfg().get("coin", {}).get("tier_up", {}) as Dictionary)
				.get(str(tid), 0))
			paid.append(tid)
			s["tier_paid"] = paid
	save_state(s)
	var total_coin := coin + tier_bonus
	if total_coin > 0:
		UserDB.add_item(coin_key(), total_coin)

	var unlocked := _grant_unlock(win, foe)

	return {
		"delta": delta, "rating_before": before, "rating_after": after,
		"tier_before": t_before, "tier_after": t_after,
		"tier_up": int(t_after.get("id", 0)) > int(t_before.get("id", 0)),
		"tier_down": int(t_after.get("id", 0)) < int(t_before.get("id", 0)),
		"streak": int(s[sk]), "best": int(s[bk]),
		"coin": coin, "coin_tier_bonus": tier_bonus,
		"unlocked": unlocked,
	}

static func coin_key() -> String:
	return String((_cfg().get("coin", {}) as Dictionary).get("key", "colosseum_coin"))

static func coin() -> int:
	return UserDB.item_count(coin_key())

static func match_coin(mode: String, win: bool, streak: int) -> int:
	var pm: Dictionary = (_cfg().get("coin", {}) as Dictionary).get("per_match", {})
	if pm.is_empty():
		return 0
	var base := int(pm.get("win", 0)) if win else int(pm.get("lose", 0))
	if win:
		base += mini(int(pm.get("streak_bonus_per", 0)) * maxi(0, streak),
			int(pm.get("streak_bonus_max", 0)))
	var mult := float((pm.get("mode_mult", {}) as Dictionary).get(mode, 1.0))
	return int(round(float(base) * mult))

const UNLOCK_GUARD_KEY := "sundaegun"

static func _grant_unlock(win: bool, foe: Dictionary) -> bool:
	if win or not bool(foe.get("guard", false)):
		return false
	if String(foe.get("guard_key", "")) != UNLOCK_GUARD_KEY:
		return false
	if bool(UserDB.get_pmeta(Summon.FLAG_UNLOCK, false)):
		return false
	UserDB.set_pmeta(Summon.FLAG_UNLOCK, true)
	return true

static func energy_keys(mode: String) -> Array:
	var mc := mode_cfg(mode)
	return [String(mc.get("energy_key", "energy_single")),
			String(mc.get("energy_at_key", "energy_at_single"))]

static func ticket_of(mode: String, now_unix: int = -1) -> int:
	var tc: Dictionary = _cfg().get("ticket", {})
	var mx := int(tc.get("max", 10))
	var per := maxi(1, int(tc.get("recover_seconds", 600)))
	var now := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	var s := state()
	var k := energy_keys(mode)
	var have := int(s.get(k[0], 0))
	var last := int(s.get(k[1], 0))
	if last <= 0:
		return clampi(have, 0, mx)
	return clampi(have + int((now - last) / per), 0, mx)

static func refresh_ticket(mode: String, now_unix: int = -1) -> Dictionary:
	var s := state()
	var tc: Dictionary = _cfg().get("ticket", {})
	var mx := int(tc.get("max", 10))
	var per := maxi(1, int(tc.get("recover_seconds", 600)))
	var now := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	var k := energy_keys(mode)
	var last := int(s.get(k[1], 0))
	if last <= 0:
		s[k[1]] = now
		save_state(s)
		return s
	var have := int(s.get(k[0], 0))
	if have >= mx:
		s[k[1]] = now
		save_state(s)
		return s
	var gained := int((now - last) / per)
	if gained > 0:
		s[k[0]] = mini(mx, have + gained)
		s[k[1]] = last + gained * per
		save_state(s)
	return s

static func ticket_eta(mode: String, now_unix: int = -1) -> int:
	var s := state()
	var tc: Dictionary = _cfg().get("ticket", {})
	var mx := int(tc.get("max", 10))
	var per := maxi(1, int(tc.get("recover_seconds", 600)))
	var now := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	var k := energy_keys(mode)
	var last := int(s.get(k[1], 0))
	if last <= 0:
		return per
	var have := mini(mx, int(s.get(k[0], 0)) + int((now - last) / per))
	if have >= mx:
		return 0
	return per - int(posmod(now - last, per))

static func can_enter(mode: String) -> bool:
	return int(refresh_ticket(mode).get(energy_keys(mode)[0], 0)) \
		>= int(_cfg().get("ticket", {}).get("cost_per_match", 1))

static func ticket_max() -> int:
	return int(_cfg().get("ticket", {}).get("max", 10))

static func add_ticket(n := 1) -> Dictionary:
	if n <= 0:
		return {}
	var mx := ticket_max()
	var got: Dictionary = {}
	for mode in (_cfg().get("modes", {}) as Dictionary):
		var m := String(mode)
		var s := refresh_ticket(m)
		var ek: String = energy_keys(m)[0]
		var have := int(s.get(ek, 0))
		if have >= mx:
			continue
		var add := mini(n, mx - have)
		s[ek] = have + add
		save_state(s)
		got[m] = add
	return got

static func refill_cost() -> int:
	return int(_cfg().get("ticket", {}).get("refill_dia", 0))

static func buy_refill(mode: String) -> Dictionary:
	var cost := refill_cost()
	if cost <= 0:
		return {"ok": false, "filled": 0, "reason": "off"}
	var s := refresh_ticket(mode)
	var mx := ticket_max()
	var ek: String = energy_keys(mode)[0]
	var have := int(s.get(ek, 0))
	if have >= mx:
		return {"ok": false, "filled": 0, "reason": "full"}
	if UserDB.diamond() < cost:
		return {"ok": false, "filled": 0, "reason": "money"}
	UserDB.add_currency("diamond", -cost)
	var filled := mx - have
	s[ek] = mx
	save_state(s)
	return {"ok": true, "filled": filled, "reason": "", "mode": mode}

static func spend_ticket(mode: String) -> bool:
	var s := refresh_ticket(mode)
	var cost := int(_cfg().get("ticket", {}).get("cost_per_match", 1))
	var ek: String = energy_keys(mode)[0]
	if int(s.get(ek, 0)) < cost:
		return false
	s[ek] = int(s[ek]) - cost
	save_state(s)
	return true

static func _today() -> int:
	return int(Time.get_unix_time_from_system() / 86400)

static func season_days() -> int:
	return maxi(1, int((_cfg().get("season", {}) as Dictionary).get("days", 21)))

static func season_span() -> int:
	return season_days() * 86400

static func season_index() -> int:
	return int(_today() / season_days())

static func season_start(s: Dictionary = {}) -> int:
	if s.is_empty():
		s = state()
	var v := int(s.get("season_start", 0))
	return v if v > 0 else season_index() * season_span()

static func season_left_sec() -> int:
	return maxi(0, season_start() + season_span() - int(Time.get_unix_time_from_system()))

static func claim_rewards() -> Array:
	var s := state()
	var cfg: Dictionary = _cfg().get("coin", {})
	if cfg.is_empty():
		return []
	var out: Array = []
	var now := int(Time.get_unix_time_from_system())
	var day := _today()
	var span := season_span()
	if int(s.get("season_start", 0)) <= 0:
		s["season_start"] = season_index() * span
		s.erase("reward_week")
		s.erase("reward_season")
		save_state(s)
	if int(s.get("reward_day", -1)) != day:
		var paid := false
		for mode in (_cfg().get("modes", {}) as Dictionary):
			var drow := _pay_reward(s, "daily", String(mode))
			if not drow.is_empty():
				out.append(drow)
				paid = true
		if paid:
			s["reward_day"] = day
	var elapsed := now - int(s["season_start"])
	if elapsed >= span:
		var srows: Array = []
		for mode in (_cfg().get("modes", {}) as Dictionary):
			var srow := _pay_reward(s, "season", String(mode))
			if not srow.is_empty():
				srows.append(srow)
		s["season_start"] = int(s["season_start"]) + span * int(elapsed / span)
		var sreset := _reset_season(s)
		if not srows.is_empty():
			(srows[-1] as Dictionary)["reset"] = sreset
			out.append_array(srows)
	if not out.is_empty() or elapsed >= span:
		save_state(s)
	return out

static func buy_season_reset() -> Dictionary:
	var cost := season_reset_cost()
	if cost <= 0:
		return {"ok": false, "reason": "off"}
	if UserDB.diamond() < cost:
		return {"ok": false, "reason": "money"}
	var s := state()
	UserDB.add_currency("diamond", -cost)
	var rows: Array = []
	var dia_sum := 0
	var coin_sum := 0
	for mode in (_cfg().get("modes", {}) as Dictionary):
		var r := _pay_reward(s, "season", String(mode))
		if not r.is_empty():
			rows.append(r)
			dia_sum += int(r.get("dia", 0))
			coin_sum += int(r.get("coin", 0))
	var row := {"ok": true, "reason": "", "cost": cost, "rows": rows,
		"dia": dia_sum, "coin": coin_sum, "reset": _reset_season(s)}
	s["season_start"] = int(Time.get_unix_time_from_system())
	save_state(s)
	return row

static func season_reset_cost() -> int:
	return int((_cfg().get("season", {}) as Dictionary).get("reset_dia", 0))

static func _pay_reward(s: Dictionary, kind: String, mode := "team") -> Dictionary:
	var cfg: Dictionary = _cfg().get("coin", {})
	var tier := tier_of(int(s.get(String(mode_cfg(mode).get("rating_key", "tournament")), 0)))
	var r: Dictionary = (cfg.get(kind, {}) as Dictionary).get(str(int(tier.get("id", 0))), {})
	if r.is_empty():
		return {}
	var dia := int(r.get("dia", 0))
	var coin := int(r.get("coin", 0))
	if dia > 0:
		UserDB.add_currency("diamond", dia)
	if coin > 0:
		UserDB.add_item(String(cfg.get("key", "colosseum_coin")), coin)
	return {"kind": kind, "mode": mode, "dia": dia, "coin": coin, "tier": tier}

static func _reset_season(s: Dictionary) -> Array:
	var rule: Dictionary = (_cfg().get("season", {}) as Dictionary).get("reset", {})
	var done: Array = []
	var start := int(_cfg().get("rating", {}).get("start", 1000))
	for mode in (_cfg().get("modes", {}) as Dictionary):
		var mc := mode_cfg(String(mode))
		var rk := String(mc.get("rating_key", ""))
		var sk := String(mc.get("streak_key", ""))
		if bool(rule.get("rating", true)) and rk != "":
			s[rk] = demoted_rating(int(s.get(rk, start)))
		if bool(rule.get("streak", true)) and sk != "":
			s[sk] = 0
		if bool(rule.get("streak_best", true)) and sk != "":
			s[sk + "_best"] = 0
	if bool(rule.get("rating", true)):
		done.append("rating")
	if bool(rule.get("streak", true)):
		done.append("streak")
	if bool(rule.get("streak_best", true)):
		done.append("streak_best")
	if bool(rule.get("guard_served", true)):
		s["guard_served"] = {}
		done.append("guard_served")
	return done

static func gen_nick(rng: RandomNumberGenerator) -> String:
	var n: Dictionary = _cfg().get("nick", {})
	var pre: Array = n.get("prefix", [])
	var noun: Array = n.get("noun", [])
	var suf: Array = n.get("suffix", [])
	if noun.is_empty():
		return "도전자%d" % (rng.randi() % 9000 + 1000)
	var s := ""
	if not pre.is_empty() and rng.randf() < 0.7:
		s += String(pre[rng.randi() % pre.size()])
	s += String(noun[rng.randi() % noun.size()])
	if not suf.is_empty():
		s += String(suf[rng.randi() % suf.size()])
	return s

static func gen_nicks(count: int, rng: RandomNumberGenerator, taken: Array = []) -> Array:
	var seen := {}
	for t in taken:
		seen[String(t)] = true
	var out: Array = []
	var guard := count * 40 + 50
	while out.size() < count and guard > 0:
		guard -= 1
		var nk := gen_nick(rng)
		if seen.has(nk):
			continue
		seen[nk] = true
		out.append(nk)
	while out.size() < count:
		out.append("도전자%d" % (rng.randi() % 9000 + 1000))
	return out

static func _make_bot_dragon(id: int, uid: int, spec: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var ddef := Data.get_dragon(id)
	var level := int(spec.get("level", 50))
	var awakened := bool(spec.get("awakened", false))

	var d := {
		"id": id, "uid": uid, "level": level,
		"exp": 0, "awakened": awakened, "awaken_skill": 0,
		"stat_bonus": {"base": {"hp": 0, "att": 0, "def": 0},
					   "growth": {"hp": 0, "att": 0, "def": 0}},
		"gain_log": _gain_log_for(ddef, level),
		"gems": {"types": Gem.random_types(Data.gems, rng), "slots": [null, null, null]},
		"equip": {"slots": []},
		"skills": [],
		"skill_slots": Loadout.random_slot_types(rng),
		"skill_equip": [],
		"cure_time": 0, "drink_buffs": {},
	}
	if awakened:
		d["awaken_skill"] = Data.awaken_skill_of(id)
	if not bool(spec.get("no_roll", false)):
		d["gems"] = _roll_gems(d["gems"], spec.get("gem", {}), rng)
		d["equip"] = _roll_equip(spec.get("equip", {}), rng, id)
		d["skills"] = _roll_skills(spec.get("skill", {}), rng)
	var eq: Array = []
	for i in Loadout.SKILL_SLOTS:
		if i < d["skills"].size() and Loadout.slot_unlocked(i, level):
			eq.append(int((d["skills"][i] as Dictionary).get("id", 0)))
		else:
			eq.append(0)
	d["skill_equip"] = eq
	return d

static func _gain_log_for(ddef: Dictionary, level: int) -> Array:
	if level <= 1:
		return []
	var g := Growth.tier_growth(ddef, Data.stat_table)
	if g.is_empty():
		return []
	var per := {"hp": int(g.get("hp", 0)), "att": int(g.get("att", 0)), "def": int(g.get("def", 0))}
	var out: Array = []
	for _i in level - 1:
		out.append(per.duplicate())
	return out

static func _roll_gems(gems_field: Dictionary, rule: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var cats: Array = rule.get("categories", ["normal", "hybrid", "soul"])
	var want_tier := int(rule.get("tier", -1)) if typeof(rule.get("tier")) != TYPE_STRING else -2
	var names: Array = []
	for k in Data.gems.get("gems", {}):
		var gd: Dictionary = Data.gems["gems"][k]
		if cats.has(String(gd.get("category", ""))):
			names.append(String(k))
	if names.is_empty():
		return gems_field
	var out := gems_field
	for slot in 3:
		var ty := String(Gem.types(out)[slot])
		var fit: Array = []
		for nm: String in names:
			if Gem.accepts(ty, nm, Data.gems):
				fit.append(nm)
		if fit.is_empty():
			continue
		var pick := String(fit[rng.randi() % fit.size()])
		var mx := Gem.max_tier(pick, Data.gems)
		var tier := mx if want_tier < 0 else mini(want_tier, mx)
		if want_tier == -2:
			tier = rng.randi_range(0, maxi(0, mx))
		var next := Gem.equip_at(out, slot, pick, tier, Data.gems)
		if not next.is_empty():
			out = next
	return out

static func _roll_equip(rule: Dictionary, rng: RandomNumberGenerator, dragon_id: int) -> Dictionary:
	var field := {"slots": []}
	var cat := Equipment.catalog(Data.equipment)
	if cat.is_empty():
		return field
	var gmin := int(rule.get("grade_min", 0))
	var gmax := int(rule.get("grade_max", 5))
	for slot_id: String in Equipment.slot_ids(true):
		var fit: Array = []
		for key: String in cat:
			var item: Dictionary = cat[key]
			if Equipment.can_equip(item, slot_id) and Equipment.species_allows(item, dragon_id):
				fit.append(key)
		if fit.is_empty():
			continue
		var key2 := String(fit[rng.randi() % fit.size()])
		var grade := rng.randi_range(gmin, maxi(gmin, gmax))
		var meta := {"rarity": grade, "options": Equipment.roll_options(grade, rng, Data.equipment)}
		var next := Equipment.equip(field, slot_id, key2, Data.equipment, meta, dragon_id)
		if not next.is_empty():
			field = next
	return field

static func _roll_skills(rule: Dictionary, rng: RandomNumberGenerator) -> Array:
	var pool := Loadout.usable_pool(Data.skills)
	if pool.is_empty():
		return []
	var want := mini(int(rule.get("count", 2)), pool.size())
	var lo := int(rule.get("level_min", 1))
	var hi := maxi(lo, int(rule.get("level_max", 5)))
	var picked := {}
	var out: Array = []
	var guard := want * 20 + 20
	while out.size() < want and guard > 0:
		guard -= 1
		var sid := int(pool[rng.randi() % pool.size()])
		if picked.has(sid):
			continue
		picked[sid] = true
		out.append({"id": sid, "level": rng.randi_range(lo, hi)})
	return out

static func make_bot(grade_key: String, mode: String, rating: int,
		rng: RandomNumberGenerator, nick := "") -> Dictionary:
	var spec: Dictionary = (_cfg().get("bots", {}) as Dictionary).get("grades", {}).get(grade_key, {})
	var n := party_size(mode)
	var ids := _dragon_pool()
	var dragons: Array = []
	var used := {}
	for i in n:
		if ids.is_empty():
			break
		var id := 0
		for _try in 20:
			id = int(ids[rng.randi() % ids.size()])
			if not used.has(id):
				break
		used[id] = true
		dragons.append(_make_bot_dragon(id, BOT_UID_BASE + rng.randi() % 90000, spec, rng))
	return {
		"nick": nick if nick != "" else gen_nick(rng),
		"grade": grade_key, "rating": rating,
		"tier": tier_of(rating), "dragons": dragons, "bot": true,
	}

static func _dragon_pool() -> Array:
	return Data.dragon_ids_random()

static func _make_ranker(rec: Dictionary, mode: String, rng: RandomNumberGenerator,
		authored := false) -> Dictionary:
	var spec: Dictionary = (_cfg().get("bots", {}) as Dictionary).get("grades", {}).get("ranker", {})
	var n := party_size(mode)
	var src: Array = _pick_roster(rec.get("dragons", []), n, rng, authored)
	var dragons: Array = []
	for i in n:
		if i < src.size():
			var r: Dictionary = src[i]
			var sp := spec.duplicate(true)
			sp["level"] = int(r.get("level", spec.get("level", 50)))
			sp["awakened"] = bool(r.get("awakened", spec.get("awakened", true)))
			sp["no_roll"] = authored
			var bd := _make_bot_dragon(int(r.get("id", 0)),
				BOT_UID_BASE + 500000 + i, sp, rng)
			_apply_sheet_spec(bd, r, rng)
			dragons.append(bd)
		elif not src.is_empty():
			break
	var rating := _ranker_rating(rec)
	return {
		"nick": String(rec.get("nick", "")), "grade": "ranker", "rating": rating,
		"tier": tier_of(rating), "dragons": dragons, "bot": true, "ranker": true,
	}

static func _pick_roster(src: Array, n: int, rng: RandomNumberGenerator,
		authored: bool) -> Array:
	if authored or src.size() <= n:
		return src
	var idx: Array = []
	for i in src.size():
		idx.append(i)
	while idx.size() > n:
		idx.remove_at(rng.randi() % idx.size())
	idx.sort()
	var out: Array = []
	for i: int in idx:
		out.append(src[i])
	return out

static func _apply_sheet_spec(bd: Dictionary, r: Dictionary, rng: RandomNumberGenerator) -> void:
	var did := int(bd.get("id", 0))
	var gm: Dictionary = r.get("gems", {})
	if not gm.is_empty():
		var field: Dictionary = {"types": gm.get("types", []), "slots": [null, null, null]}
		field = Gem.set_types(field, gm.get("types", []))
		for e: Dictionary in (gm.get("list", []) as Array):
			var next := Gem.equip_at(field, int(e.get("slot", 0)), String(e.get("name", "")),
				int(e.get("tier", 0)), Data.gems)
			if next.is_empty():
				push_warning("[Colosseum] 젬 장착 실패: %s (드래곤 %d)" % [e, did])
				continue
			field = next
		bd["gems"] = field
	var sk: Array = r.get("skills", [])
	if not sk.is_empty():
		var learned: Array = []
		for s: Dictionary in sk:
			learned.append({"id": int(s.get("id", 0)), "level": int(s.get("level", 1))})
		bd["skills"] = learned
		var pick: Array = []
		for i in learned.size():
			pick.append(i)
		while pick.size() > Loadout.SKILL_SLOTS:
			pick.remove_at(rng.randi() % pick.size())
		var eq: Array = []
		for i in Loadout.SKILL_SLOTS:
			eq.append(int((learned[pick[i]] as Dictionary).get("id", 0))
				if i < pick.size() and Loadout.slot_unlocked(i, int(bd.get("level", 50)))
				else 0)
		bd["skill_equip"] = eq
	var ep: Array = r.get("equip", [])
	if not ep.is_empty():
		var field2 := {"slots": []}
		for e2: Dictionary in ep:
			var slot_id := String(e2.get("slot", "all"))
			var meta := {
				"rarity": int(e2.get("rarity", 0)),
				"options": (e2.get("options", []) as Array).duplicate(true),
			}
			var next2 := Equipment.equip(field2, slot_id,
				String(e2.get("key", "")), Data.equipment, meta, did)
			if next2.is_empty():
				push_warning("[Colosseum] 장비 장착 실패: %s (드래곤 %d)" % [e2, did])
				continue
			field2 = next2
			for _i in int(e2.get("enhance", 0)):
				var up := Equipment.enhance(field2, slot_id, rng, Data.equipment)
				if up.is_empty():
					break
				field2 = up
		bd["equip"] = field2
	var ov: Dictionary = (r.get("stats", {}) as Dictionary).duplicate()
	for k in (r.get("stats_roll", {}) as Dictionary):
		var span: Array = r["stats_roll"][k]
		if span.size() >= 2:
			ov[k] = rng.randf_range(float(span[0]), float(span[1]))
	if not ov.is_empty():
		bd["stat_override"] = ov
	if r.has("grade"):
		bd["grade_override"] = float(r["grade"])
	var im: Dictionary = r.get("immune", {})
	if not im.is_empty():
		bd["immune"] = im.duplicate()

static func tier_band() -> int:
	var list: Array = (_cfg().get("tier", {}) as Dictionary).get("list", [])
	if list.size() < 2:
		return 200
	var top := int((list[list.size() - 1] as Dictionary).get("min_rating", 2000))
	var prev := int((list[list.size() - 2] as Dictionary).get("min_rating", 1800))
	return maxi(1, top - prev)

static func _tier_mid_rating(tier_key: String) -> int:
	var list: Array = (_cfg().get("tier", {}) as Dictionary).get("list", [])
	for t: Dictionary in list:
		if String(t.get("key", "")) == tier_key:
			return int(t.get("min_rating", 0)) + tier_band() / 2
	return int(_cfg().get("rating", {}).get("start", 1000))

static func roll_opponents(mode: String, rng: RandomNumberGenerator = null) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var rating := rating_of(mode)
	var tier := tier_of(rating)
	var tkey := String(tier.get("key", "bronze"))
	var bots: Dictionary = _cfg().get("bots", {})
	var mix: Dictionary = (bots.get("tier_mix", {}) as Dictionary).get(tkey, {})
	var count := int(bots.get("list_size", 5))
	var gpend := pending_guard(mode)
	var guard_on := not gpend.is_empty()

	var rankers: Array = _cfg().get("rankers", [])
	var nicks := gen_nicks(count, rng)
	var out: Array = []
	var guard_slot := -1
	if guard_on:
		out.append(make_guard(gpend, mode, rng))
		guard_slot = 0
	var used_rankers := {}
	for i in count - out.size():
		var g := _pick_grade(mix, rng)
		if guard_on and guard_slot < 0:
			g = _grade_up(g)
		if g == "ranker" and used_rankers.size() >= rankers.size():
			g = "adept"
		if g == "ranker" and not rankers.is_empty():
			var ri := rng.randi() % rankers.size()
			while used_rankers.has(ri):
				ri = (ri + 1) % rankers.size()
			used_rankers[ri] = true
			out.append(_make_ranker(rankers[ri], mode, rng))
			continue
		if g == "ranker":
			g = "adept"
		var r := maxi(0, rating + rng.randi_range(-120, 160))
		out.append(make_bot(g, mode, r, rng, String(nicks[i])))
	return out

static func _pick_grade(mix: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in mix:
		total += maxf(0.0, float(mix[k]))
	if total <= 0.0:
		return "novice"
	var r := rng.randf() * total
	var acc := 0.0
	var last := "novice"
	for k in mix:
		acc += maxf(0.0, float(mix[k]))
		last = String(k)
		if r < acc:
			return last
	return last

static func guard_for(streak: int) -> Dictionary:
	var best: Dictionary = {}
	var best_at := -1
	for g: Dictionary in (_cfg().get("guards", []) as Array):
		var at := guard_streak_at(g)
		if streak >= at and at >= best_at:
			best = g
			best_at = at
	return best

static func guard_streak_at(g: Dictionary) -> int:
	var at := int(g.get("streak_at", 0))
	var first := int(g.get("streak_at_first", 0))
	if first > 0 and first < at and first_meet(String(g.get("key", ""))):
		return first
	return at

static func next_guard_in(streak: int) -> int:
	var nxt := -1
	for g: Dictionary in (_cfg().get("guards", []) as Array):
		var at := guard_streak_at(g)
		if at > streak and (nxt < 0 or at < nxt):
			nxt = at
	return 0 if nxt < 0 else nxt - streak

static func make_guard(g: Dictionary, mode: String, rng: RandomNumberGenerator) -> Dictionary:
	var rec := {
		"nick": String(g.get("name", "")),
		"tier": "master",
		"rating": int(g.get("rating", 0)),
		"dragons": g.get("dragons", []),
	}
	var bot := _make_ranker(rec, mode, rng, true)
	var key := String(g.get("key", ""))
	bot["guard"] = true
	bot["guard_key"] = key
	bot["guard_at"] = guard_streak_at(g)
	bot["talk_stage"] = String(g.get("talk_stage", ""))
	bot["lines"] = g.get("lines", [])
	bot["lines_first"] = g.get("lines_first", [])
	bot["first_meet"] = first_meet(key)
	return bot

static func met_count(guard_key: String) -> int:
	return int((state().get("guard_met", {}) as Dictionary).get(guard_key, 0))

static func first_meet(guard_key: String) -> bool:
	if guard_key == UNLOCK_GUARD_KEY:
		return not bool(UserDB.get_pmeta(Summon.FLAG_UNLOCK, false))
	return met_count(guard_key) <= 0

static func _grade_up(g: String) -> String:
	match g:
		"novice": return "adept"
		"adept": return "ranker"
		_: return "ranker"

static func pending_guard(mode: String) -> Dictionary:
	var g := guard_for(streak_of(mode))
	if g.is_empty():
		return {}
	if bool(g.get("skip_if_admin", false)) and UserDB.is_admin():
		return {}
	return {} if _guard_served(mode, guard_streak_at(g)) else g

static func _guard_served(mode: String, at: int) -> bool:
	var done: Array = (state().get("guard_served", {}) as Dictionary).get(mode, [])
	for v in done:
		if int(v) == at:
			return true
	return false

static func guard_active(mode: String) -> bool:
	return not pending_guard(mode).is_empty()

static func consume_guard(mode: String, foe: Dictionary = {}) -> void:
	if not bool(foe.get("guard", false)):
		return
	var s := state()
	var at := int(foe.get("guard_at", 0))
	if at > 0 and not _guard_served(mode, at):
		var srv: Dictionary = (s.get("guard_served", {}) as Dictionary).duplicate()
		var done: Array = (srv.get(mode, []) as Array).duplicate()
		done.append(at)
		srv[mode] = done
		s["guard_served"] = srv
	var key := String(foe.get("guard_key", ""))
	if key != "":
		var met: Dictionary = (s.get("guard_met", {}) as Dictionary).duplicate()
		met[key] = int(met.get(key, 0)) + 1
		s["guard_met"] = met
	save_state(s)

static func roll_match(mode: String, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var rating := rating_of(mode)
	var tkey := String(tier_of(rating).get("key", "bronze"))
	var bots: Dictionary = _cfg().get("bots", {})
	var mix: Dictionary = (bots.get("tier_mix", {}) as Dictionary).get(tkey, {})

	var gnpc := pending_guard(mode)
	if not gnpc.is_empty():
		return make_guard(gnpc, mode, rng)

	var g := _pick_grade(mix, rng)
	var rankers: Array = _cfg().get("rankers", [])
	if g == "ranker" and not rankers.is_empty():
		return _make_ranker(rankers[rng.randi() % rankers.size()], mode, rng)
	if g == "ranker":
		g = "adept"
	var r := maxi(0, rating + rng.randi_range(-120, 160))
	return make_bot(g, mode, r, rng, gen_nick(rng))

const LADDER_SIZE := 30

static func ladder(mode: String, weekly := false, rng: RandomNumberGenerator = null) -> Array:
	var s := state()
	var key := "pvp_week_rank" if weekly else "pvp_total_rank"
	var by_mode: Dictionary = s.get(key, {})
	if typeof(by_mode) != TYPE_DICTIONARY:
		by_mode = {}
	var sig := _ranker_sig()
	if String(s.get("pvp_rank_sig", "")) != sig:
		s["pvp_total_rank"] = {}
		s["pvp_week_rank"] = {}
		s["pvp_rank_sig"] = sig
		by_mode = {}
	var rows: Array = by_mode.get(mode, [])
	if rows.is_empty():
		rows = _gen_ladder(mode, weekly, rng)
		by_mode[mode] = rows
		s[key] = by_mode
		save_state(s)
	return rows

static func my_rank(mode: String, weekly := false) -> int:
	var mine := rating_of(mode)
	var n := 1
	for r: Dictionary in ladder(mode, weekly):
		if int(r.get("rating", 0)) > mine:
			n += 1
	return n

static func _ranker_sig() -> String:
	var names: Array = []
	for r: Dictionary in (_cfg().get("rankers", []) as Array):
		names.append("%s:%d" % [String(r.get("nick", "")), _ranker_rating(r)])
	return "|".join(names)

static func _gen_ladder(mode: String, _weekly: bool, rng: RandomNumberGenerator) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var tiers: Array = (_cfg().get("tier", {}) as Dictionary).get("list", [])
	var top := 2000
	if not tiers.is_empty():
		top = int((tiers[tiers.size() - 1] as Dictionary).get("min_rating", 2000))
	var band := float(tier_band())
	var rankers: Array = _cfg().get("rankers", [])
	var nicks := gen_nicks(LADDER_SIZE, rng)
	var out: Array = []
	for i in rankers.size():
		var rec: Dictionary = rankers[i]
		out.append({"nick": String(rec.get("nick", "")), "rating": _ranker_rating(rec),
			"ranker": true})
	var fill_top := float(top) - band * 0.1
	var step := band * 0.13
	var jitter := int(round(band * 0.06))
	for i in maxi(0, LADDER_SIZE - rankers.size()):
		var base := int(round(fill_top - float(i) * step)) + rng.randi_range(-jitter, jitter)
		var nick := String(nicks[(i + rankers.size()) % nicks.size()])
		out.append({"nick": nick, "rating": maxi(0, base)})
	return out

static func _ranker_rating(rec: Dictionary) -> int:
	var r := int(rec.get("rating", 0))
	if r > 0:
		return r
	return _tier_mid_rating(String(rec.get("tier", "master")))

static func stage_cfg() -> Dictionary:
	return _cfg().get("stage", {})

static func stage_wheel() -> Array:
	return stage_cfg().get("wheel", [])

static func roll_stage(rng: RandomNumberGenerator = null) -> Dictionary:
	var w := stage_wheel()
	if w.is_empty():
		return {}
	return stage_at(int((rng.randi() if rng != null else randi()) % w.size()))

static func stage_at(index: int) -> Dictionary:
	var w := stage_wheel()
	if w.is_empty():
		return {}
	var i := posmod(index, w.size())
	var el := String(w[i])
	return {
		"index": i,
		"element": el,
		"bg": int((stage_cfg().get("bg", {}) as Dictionary).get(el, 3)),
	}

static func stage_of(element: String) -> Dictionary:
	var i := stage_wheel().find(element)
	return stage_at(i) if i >= 0 else {}

static func stage_mult() -> float:
	return 1.0 + float(stage_cfg().get("buff_pct", 0)) / 100.0

static func stage_stats() -> Array:
	return stage_cfg().get("buff_stats", [])

static func lobby_bgm() -> String:
	return String((_cfg().get("bgm", {}) as Dictionary).get("lobby", "bg_colosseum"))

static func battle_bgm(rng: RandomNumberGenerator = null) -> String:
	var list: Array = (_cfg().get("bgm", {}) as Dictionary).get("battle", [])
	if list.is_empty():
		return "bg_colosseum_battle_2"
	return String(list[int((rng.randi() if rng != null else randi()) % list.size())])

static func matching_seconds() -> float:
	return float(_cfg().get("entry", {}).get("matching_seconds", 3))
