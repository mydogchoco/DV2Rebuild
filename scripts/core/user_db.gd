extends Node

const ADMIN := false

const ADMIN_LOCAL_FLAG := "res://admin.local"

static var _admin_local := FileAccess.file_exists(ADMIN_LOCAL_FLAG)

const SCHEMA_VERSION := 18

var _data: Dictionary = {}
var _autosave := true

func _ready() -> void:
	var loaded = SaveSystem.load_or_backup()
	if loaded == null:
		_data = _default()
		SaveSystem.save(_data)
	else:
		var was_admin := bool(loaded.get("is_admin", false))
		_data = _migrate(loaded)
		if was_admin != is_admin():
			SaveSystem.save(_data)
	print("[UserDB] v%d 로드 — 드래곤 %d마리, 골드 %d" % [
		int(_data.get("version", 0)), dragon_count(), gold()])

func _default() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"next_uid": 1,
		"user": {"nickname": ""},
		"is_admin": ADMIN or _admin_local,
		"currency": {"gold": 0, "diamond": 0},
		"dragons": [],
		"storage": [],
		"active_uid": 0,
		"inventory": {},
		"cosmetics": {"cave_skin": 0, "stand_skin": 0, "wall_skin": 0},
		"progress": {},
		"dex_master": [],
		"darknix": {"status": 0, "until": 0, "face": 0},
		"rng_seed": null,
	}

func _zero_bonus() -> Dictionary:
	return {"base": {"hp": 0, "att": 0, "def": 0}, "growth": {"hp": 0, "att": 0, "def": 0}}

func _new_dragon(id: int, level: int, stat_bonus: Dictionary) -> Dictionary:
	var uid := int(_data["next_uid"])
	_data["next_uid"] = uid + 1
	var inst := {
		"uid": uid,
		"id": id,
		"level": level,
		"exp": 0,
		"stat_bonus": stat_bonus,
		"gain_log": [],
		"awakened": false,
		"awaken_skill": 0,
		"cure_time": 0,
		"food": ItemEffect.FOOD_MAX,
		"nickname": "",
		"locked": false,
		"favorite": false,
		"skills": [],
		"skill_equip": [0, 0],
		"skill_grants": [],
		"gems": {"types": Gem.random_types(Data.gems), "slots": [null, null, null]},
		"skill_slots": Loadout.random_slot_types(),
		"acquired_at": int(Time.get_unix_time_from_system()),
	}
	inst["gain_log"] = _backfill_gain_log(inst)
	return inst

func user_nickname() -> String:
	return String(_data.get("user", {}).get("nickname", ""))

func has_user_nickname() -> bool:
	return user_nickname().strip_edges() != ""

func set_user_nickname(name: String) -> void:
	if not _data.has("user"): _data["user"] = {"nickname": ""}
	_data["user"]["nickname"] = name.strip_edges()
	_commit()

func is_admin() -> bool:
	return ADMIN or _admin_local

func user_title_no() -> int:
	return int(get_pmeta("title_no", 0))

func dragons() -> Array:
	return _data["dragons"]

func dragon_count() -> int:
	return _data["dragons"].size()

func get_dragon(uid: int) -> Dictionary:
	for d in _data["dragons"]:
		if int(d["uid"]) == uid:
			return d
	return {}

func add_dragon(id: int, level: int = 1, stat_bonus: Dictionary = {}) -> Dictionary:
	var inst := _new_dragon(id, level, _zero_bonus() if stat_bonus.is_empty() else stat_bonus)
	_data["dragons"].append(inst)
	if active_uid() == 0:
		_data["active_uid"] = inst["uid"]
	_commit()
	return inst

func add_egg(id: int, grade: float, seconds: int, enhance := 0, inherit: Dictionary = {},
		blessed := false) -> Dictionary:
	var inst := _new_dragon(id, 1, _zero_bonus())
	inst["egg"] = true
	inst["egg_grade"] = snappedf(grade, 0.1)
	inst["egg_enhance"] = int(enhance)
	inst["egg_blessed"] = bool(blessed)
	inst["hatch_at"] = int(Time.get_unix_time_from_system()) + maxi(0, seconds)
	if not inherit.is_empty():
		if int(inherit.get("art_id", 0)) > 0:
			inst["art_id"] = int(inherit["art_id"])
		if typeof(inherit.get("element")) == TYPE_STRING:
			inst["element"] = String(inherit["element"])
		if String(inherit.get("nickname", "")) != "":
			inst["nickname"] = String(inherit["nickname"])
	_data["dragons"].append(inst)
	if active_uid() == 0:
		_data["active_uid"] = inst["uid"]
	_commit()
	return inst

func has_hatched_dragon() -> bool:
	for d in _data["dragons"]:
		if not is_egg(d):
			return true
	return false

func is_egg(d: Dictionary) -> bool:
	return bool(d.get("egg", false))

func hatch_remain(d: Dictionary) -> int:
	if not is_egg(d):
		return 0
	return maxi(0, int(d.get("hatch_at", 0)) - int(Time.get_unix_time_from_system()))

func hatch_egg(uid: int, stat_bonus: Dictionary) -> bool:
	for d in _data["dragons"]:
		if int(d["uid"]) != uid or not is_egg(d):
			continue
		if hatch_remain(d) > 0:
			return false
		d.erase("egg"); d.erase("hatch_at"); d.erase("egg_blessed")
		d["level"] = 1
		d["stat_bonus"] = stat_bonus
		bump_quest("hatches")
		_commit()
		return true
	return false

func set_hatch_now(uid: int) -> bool:
	for d in _data["dragons"]:
		if int(d["uid"]) == uid and is_egg(d):
			d["hatch_at"] = int(Time.get_unix_time_from_system())
			_commit()
			return true
	return false

func storage_dragons() -> Array:
	return _data.get("storage", [])

func store_dragon(uid: int) -> bool:
	var arr: Array = _data["dragons"]
	if arr.size() <= 1:
		return false
	for i in arr.size():
		if int(arr[i]["uid"]) != uid:
			continue
		if bool(arr[i].get("locked", false)) or is_egg(arr[i]):
			return false
		var d: Dictionary = arr[i]
		arr.remove_at(i)
		(_data["storage"] as Array).append(d)
		if active_uid() == uid:
			_data["active_uid"] = int(arr[0]["uid"]) if not arr.is_empty() else 0
		_commit()
		return true
	return false

func unstore_dragon(uid: int) -> bool:
	var st: Array = _data.get("storage", [])
	for i in st.size():
		if int(st[i]["uid"]) != uid:
			continue
		var d: Dictionary = st[i]
		st.remove_at(i)
		(_data["dragons"] as Array).append(d)
		_commit()
		return true
	return false

func release_dragon(uid: int) -> bool:
	var arr: Array = _data["dragons"]
	for i in arr.size():
		if int(arr[i]["uid"]) == uid:
			if bool(arr[i].get("locked", false)):
				return false
			_push_latea(arr[i])
			arr.remove_at(i)
			if active_uid() == uid:
				_data["active_uid"] = int(arr[0]["uid"]) if not arr.is_empty() else 0
			_commit()
			return true
	return false

func consume_dragon(uid: int) -> bool:
	var arr: Array = _data["dragons"]
	for i in arr.size():
		if int(arr[i]["uid"]) != uid:
			continue
		if bool(arr[i].get("locked", false)):
			return false
		arr.remove_at(i)
		if active_uid() == uid:
			_data["active_uid"] = int(arr[0]["uid"]) if not arr.is_empty() else 0
		_commit()
		return true
	return false

func _push_latea(d: Dictionary) -> void:
	var arr: Array = latea_records().duplicate()
	arr.push_front({
		"id": int(d.get("id", 0)),
		"name": String(d.get("name", "")),
		"level": int(d.get("level", 1)),
		"date": Time.get_date_string_from_system(),
		"t": int(Time.get_unix_time_from_system()),
		"snap": d.duplicate(true),
	})
	var cap := int(Data.promote.get("latea", {}).get("max_records", 50))
	while arr.size() > maxi(1, cap):
		arr.pop_back()
	set_pmeta("latea", arr)

func latea_records() -> Array:
	var recs = get_pmeta("latea", null)
	if recs == null:
		var old = get_pmeta("sky_nest", [])
		recs = (old as Array) if old is Array else []
		set_pmeta("latea", recs)
		set_pmeta("sky_nest", null)
	if not (recs is Array):
		return []
	var days := int(Data.promote.get("latea", {}).get("expire_days", 7))
	if days <= 0:
		return recs
	var cutoff := int(Time.get_unix_time_from_system()) - days * 86400
	var live: Array = []
	for r in (recs as Array):
		if not (r is Dictionary) or not (r as Dictionary).has("t") or int((r as Dictionary)["t"]) >= cutoff:
			live.append(r)
	if live.size() != (recs as Array).size():
		set_pmeta("latea", live)
	return live

func restore_from_latea(index: int) -> Dictionary:
	var arr: Array = latea_records().duplicate()
	if index < 0 or index >= arr.size():
		return {}
	var rec: Dictionary = arr[index]
	arr.remove_at(index)
	set_pmeta("latea", arr)
	var snap = rec.get("snap")
	if not (snap is Dictionary) or (snap as Dictionary).is_empty():
		return add_dragon(int(rec.get("id", 1)), int(rec.get("level", 1)))
	var d: Dictionary = (snap as Dictionary).duplicate(true)
	if not get_dragon(int(d.get("uid", 0))).is_empty() or int(d.get("uid", 0)) <= 0:
		d["uid"] = int(_data["next_uid"])
		_data["next_uid"] = int(d["uid"]) + 1
	(_data["dragons"] as Array).append(d)
	if active_uid() <= 0:
		_data["active_uid"] = int(d["uid"])
	_commit()
	sync_skill_grants(int(d["uid"]))
	return d

func active_uid() -> int:
	return int(_data.get("active_uid", 0))

func active_dragon() -> Dictionary:
	return get_dragon(active_uid())

func set_active(uid: int) -> void:
	if not get_dragon(uid).is_empty():
		_data["active_uid"] = uid
		_commit()

func party() -> Array:
	var raw: Array = _data.get("party", [])
	var out: Array = []
	for u in raw:
		if not get_dragon(int(u)).is_empty() and not out.has(int(u)):
			out.append(int(u))
	return out.slice(0, 3)

func in_party(uid: int) -> bool:
	return party().has(int(uid))

func toggle_party(uid: int) -> bool:
	if get_dragon(uid).is_empty(): return false
	var p := party()
	if p.has(int(uid)):
		p.erase(int(uid))
	elif p.size() < 3:
		p.append(int(uid))
	else:
		return false
	_data["party"] = p
	_commit()
	return true

func clear_party() -> void:
	_data["party"] = []
	_commit()

func set_level(uid: int, level: int) -> void:
	var d := get_dragon(uid)
	if not d.is_empty():
		d["level"] = level
		_commit()
		sync_skill_grants(uid)

func grant_exp(uid: int, n: int) -> Dictionary:
	var d := get_dragon(uid)
	if d.is_empty():
		return {"levels_gained": 0}
	var ddef := Data.get_dragon(int(d.get("id", 0)))
	var max_stats := Growth.tier_growth(ddef, Data.stat_table)
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var ev := LevelSystem.apply_exp(Data.level_curve, Data.level_curve.get("roll", {}), max_stats,
		int(d.get("level", 1)), int(d.get("exp", 0)), n, rng, bool(d.get("awakened", false)))
	var before := {}
	for s in dragon_skills(uid):
		before[int((s as Dictionary).get("id", 0))] = true
	apply_levelups(uid, int(ev["level"]), int(ev["exp"]), ev.get("gains", []))
	ev["max_stats"] = max_stats
	var learned: Array = []
	for s in dragon_skills(uid):
		var sid := int((s as Dictionary).get("id", 0))
		if not before.has(sid):
			learned.append(String(Data.skills.get(str(sid), {}).get("name", "스킬")))
	ev["learned_skills"] = learned
	return ev

func apply_levelups(uid: int, new_level: int, new_exp: int, gains: Array) -> void:
	var d := get_dragon(uid)
	if d.is_empty():
		return
	var gl: Array = d.get("gain_log", [])
	for g in gains:
		gl.append({"hp": int(g.get("hp", 0)), "att": int(g.get("att", 0)), "def": int(g.get("def", 0))})
	d["gain_log"] = gl
	d["level"] = new_level
	d["exp"] = new_exp
	_commit()
	sync_skill_grants(uid)
	if Growth.is_aura_adult(new_level):
		mark_dex_master(int(d.get("id", 0)))

func level_down(uid: int) -> bool:
	var d := get_dragon(uid)
	if d.is_empty() or int(d.get("level", 1)) <= 1:
		return false
	var gl: Array = d.get("gain_log", [])
	if not gl.is_empty():
		gl.remove_at(gl.size() - 1)
	d["gain_log"] = gl
	d["level"] = int(d["level"]) - 1
	d["exp"] = 0
	_commit()
	return true

func level_up_with(uid: int, gain: Dictionary) -> bool:
	var d := get_dragon(uid)
	if d.is_empty():
		return false
	var gl: Array = d.get("gain_log", [])
	gl.append({"hp": int(gain.get("hp", 0)), "att": int(gain.get("att", 0)), "def": int(gain.get("def", 0))})
	d["gain_log"] = gl
	d["level"] = int(d.get("level", 1)) + 1
	_commit()
	sync_skill_grants(uid)
	return true

func replace_last_gain(uid: int, gain: Dictionary) -> bool:
	var d := get_dragon(uid)
	if d.is_empty():
		return false
	var gl: Array = d.get("gain_log", [])
	if gl.is_empty():
		return false
	gl[gl.size() - 1] = {"hp": int(gain.get("hp", 0)), "att": int(gain.get("att", 0)), "def": int(gain.get("def", 0))}
	d["gain_log"] = gl
	_commit()
	return true

func set_dragon_field(uid: int, key: String, value) -> void:
	var d := get_dragon(uid)
	if not d.is_empty():
		d[key] = value
		_commit()

func cure_time(uid: int) -> int:
	return int(get_dragon(uid).get("cure_time", 0))

func set_cure_time(uid: int, t: int) -> void:
	set_dragon_field(uid, "cure_time", maxi(0, t))

func is_down(uid: int) -> bool:
	return Incapacitation.is_down(cure_time(uid), int(Time.get_unix_time_from_system()))

func dragon_skills(uid: int) -> Array:
	return get_dragon(uid).get("skills", [])

func dragon_skill_equip(uid: int) -> Array:
	return Loadout.equipped_ids(get_dragon(uid))

func dragon_battle_skills(uid: int) -> Dictionary:
	var dr := get_dragon(uid)
	var types: Array = Loadout.slot_types(dr)
	var out: Array = []
	var tys: Array = []
	for i in Loadout.SKILL_SLOTS:
		var e := Loadout.equipped_entry(dr, i)
		if e.is_empty():
			continue
		out.append(e)
		tys.append(String(types[i]) if i < types.size() else "star")
	return {"skills": out, "slot_types": tys}

func sync_skill_grants(uid: int) -> Array:
	var d := get_dragon(uid)
	if d.is_empty():
		return []
	var level := int(d.get("level", 1))
	var claimed: Array = []
	for c in (d.get("skill_grants", []) as Array):
		claimed.append(int(c))
	var due := Loadout.due_grants(level, claimed)
	if due.is_empty():
		return []
	var pool: Array = d.get("skills", [])
	var learned: Array = []
	for m in due:
		var r := RandomNumberGenerator.new()
		r.seed = hash("skillgrant_%d_%d" % [uid, int(m)])
		var got := Loadout.roll_grant(pool, Data.skills, r)
		claimed.append(int(m))
		if got.is_empty():
			continue
		pool.append({"id": int(got["id"]), "level": int(got["level"]), "dedicated": false})
		learned.append({"level": int(m), "id": int(got["id"]),
			"name": String(Data.skills.get(str(int(got["id"])), {}).get("name", "스킬"))})
	d["skills"] = pool
	d["skill_grants"] = claimed
	var eq: Array = Loadout.equipped_ids(d)
	for e in learned:
		for i in Loadout.SKILL_SLOTS:
			if int(eq[i]) == 0 and Loadout.slot_unlocked(i, level):
				eq[i] = int(e["id"])
				break
	d["skill_equip"] = eq
	_commit()
	return learned

func set_dragon_skill_equip(uid: int, slot: int, skill_id: int) -> void:
	var d := get_dragon(uid)
	if d.is_empty():
		return
	d["skill_equip"] = Loadout.equip_skill(d, slot, skill_id)
	_commit()

func ensure_dragon_skills(uid: int, skills: Array) -> void:
	var d := get_dragon(uid)
	if not d.is_empty() and (d.get("skills", []) as Array).is_empty():
		d["skills"] = skills
		var eq: Array = Loadout.equipped_ids(d)
		for i in Loadout.SKILL_SLOTS:
			if int(eq[i]) == 0 and i < skills.size():
				eq[i] = int((skills[i] as Dictionary).get("id", 0))
		d["skill_equip"] = eq
		_commit()

func set_dragon_skills(uid: int, skills: Array) -> void:
	var d := get_dragon(uid)
	if not d.is_empty():
		d["skills"] = skills
		_commit()

func is_locked(uid: int) -> bool:
	return bool(get_dragon(uid).get("locked", false))

func is_favorite(uid: int) -> bool:
	return bool(get_dragon(uid).get("favorite", false))

func toggle_locked(uid: int) -> bool:
	var d := get_dragon(uid)
	if d.is_empty(): return false
	d["locked"] = not bool(d.get("locked", false))
	_commit()
	return bool(d["locked"])

func toggle_favorite(uid: int) -> bool:
	var d := get_dragon(uid)
	if d.is_empty(): return false
	d["favorite"] = not bool(d.get("favorite", false))
	_commit()
	return bool(d["favorite"])

func dex_seen(id: int) -> bool:
	for d in _data["dragons"]:
		if int(d["id"]) == id:
			return true
	return false

func dex_best_level(id: int) -> int:
	var best := 0
	for d in _data["dragons"]:
		if int(d["id"]) == id:
			best = maxi(best, int(d["level"]))
	return best

func dex_awakened(id: int) -> bool:
	for d in _data["dragons"]:
		if int(d["id"]) == id and bool(d.get("awakened", false)):
			return true
	return false

func dex_master(id: int) -> bool:
	for v in _data["dex_master"]:
		if int(v) == id:
			return true
	return false

func dex_step(id: int) -> int:
	if dex_awakened(id):
		return 6
	if dex_master(id):
		return 5
	if dex_seen(id):
		match Growth.stage_for_level(dex_best_level(id)):
			"adult": return 4
			"child": return 3
			_: return 2
	if item_count("egg:%d" % id) > 0:
		return 1
	return 0

func mark_dex_master(id: int) -> void:
	if dex_master(id):
		return
	_data["dex_master"].append(id)
	_commit()

func inventory() -> Dictionary:
	return _data["inventory"]

func item_count(key: String) -> int:
	return int(_data["inventory"].get(key, 0))

func add_item(key: String, n: int = 1) -> void:
	var inv: Dictionary = _data["inventory"]
	inv[key] = int(inv.get(key, 0)) + n
	if inv[key] <= 0:
		inv.erase(key)
	_commit()

func use_item(key: String, n: int = 1) -> bool:
	var inv: Dictionary = _data["inventory"]
	var have := int(inv.get(key, 0))
	if have < n:
		return false
	inv[key] = have - n
	if inv[key] <= 0:
		inv.erase(key)
	_commit()
	return true

func currency(kind: String) -> int:
	return int(_data["currency"].get(kind, 0))

func gold() -> int:
	return currency("gold")

func diamond() -> int:
	return currency("diamond")

func add_currency(kind: String, amount: int) -> void:
	_data["currency"][kind] = currency(kind) + amount
	_commit()

func get_pmeta(key: String, default = null):
	return _data.get("meta", {}).get(key, default)

func set_pmeta(key: String, value) -> void:
	if not _data.has("meta"): _data["meta"] = {}
	_data["meta"][key] = value
	_commit()

func reward_buff() -> Dictionary:
	var v = get_pmeta("reward_buff", {})
	return v if v is Dictionary else {}

func set_reward_buff(active: Dictionary) -> void:
	set_pmeta("reward_buff", active)

func quest_count(key: String) -> int:
	var q: Dictionary = get_pmeta("quests", {})
	if String(q.get("date", "")) != Time.get_date_string_from_system(): return 0
	return int(q.get(key, 0))

func bump_quest(key: String) -> void:
	var today := Time.get_date_string_from_system()
	var q: Dictionary = (get_pmeta("quests", {}) as Dictionary).duplicate()
	if String(q.get("date", "")) != today: q = {"date": today}
	q[key] = int(q.get(key, 0)) + 1
	set_pmeta("quests", q)

func quest_claimed(key: String) -> bool:
	var q: Dictionary = get_pmeta("quests", {})
	if String(q.get("date", "")) != Time.get_date_string_from_system(): return false
	return bool(q.get("claimed_" + key, false))

func claim_quest(key: String) -> void:
	var today := Time.get_date_string_from_system()
	var q: Dictionary = (get_pmeta("quests", {}) as Dictionary).duplicate()
	if String(q.get("date", "")) != today: q = {"date": today}
	q["claimed_" + key] = true
	set_pmeta("quests", q)

func quest_accepted(key: String) -> bool:
	var q: Dictionary = get_pmeta("quests", {})
	if String(q.get("date", "")) != Time.get_date_string_from_system(): return false
	return bool(q.get("accepted_" + key, false))

func quest_gaveup(key: String) -> bool:
	var q: Dictionary = get_pmeta("quests", {})
	if String(q.get("date", "")) != Time.get_date_string_from_system(): return false
	return bool(q.get("gaveup_" + key, false))

func accept_quest(key: String) -> void:
	var today := Time.get_date_string_from_system()
	var q: Dictionary = (get_pmeta("quests", {}) as Dictionary).duplicate()
	if String(q.get("date", "")) != today: q = {"date": today}
	q["accepted_" + key] = true
	q["base_" + key] = int(q.get(key, 0))
	set_pmeta("quests", q)

func fill_quest(key: String, goal: int) -> void:
	var today := Time.get_date_string_from_system()
	var q: Dictionary = (get_pmeta("quests", {}) as Dictionary).duplicate()
	if String(q.get("date", "")) != today: q = {"date": today}
	q["accepted_" + key] = true
	q["base_" + key] = int(q.get(key, 0)) - maxi(0, goal)
	set_pmeta("quests", q)

func giveup_quest(key: String) -> void:
	var today := Time.get_date_string_from_system()
	var q: Dictionary = (get_pmeta("quests", {}) as Dictionary).duplicate()
	if String(q.get("date", "")) != today: q = {"date": today}
	q["gaveup_" + key] = true
	q.erase("accepted_" + key)
	set_pmeta("quests", q)

func quest_progress(key: String) -> int:
	if not quest_accepted(key): return 0
	var q: Dictionary = get_pmeta("quests", {})
	return maxi(0, int(q.get(key, 0)) - int(q.get("base_" + key, 0)))

func spend(kind: String, amount: int) -> bool:
	if currency(kind) < amount:
		return false
	_data["currency"][kind] = currency(kind) - amount
	_commit()
	return true

func get_skin(slot: String) -> int:
	return int(_data["cosmetics"].get(slot, 0))

func set_skin(slot: String, idx: int) -> void:
	_data["cosmetics"][slot] = idx
	_commit()

func get_progress(key: String, default = null):
	return _data["progress"].get(key, default)

func set_progress(key: String, value) -> void:
	_data["progress"][key] = value
	_commit()

func darknix() -> Dictionary:
	var d = _data.get("darknix", {})
	return (d as Dictionary) if d is Dictionary else {}

func darknix_summon(v: Dictionary) -> void:
	_data["darknix"] = {
		"status": int(v.get("status", 1)),
		"until": int(v.get("until", 0)),
		"face": int(v.get("face", 0)),
		"seen": 0,
	}
	_commit()

func darknix_seen() -> bool:
	return int(darknix().get("seen", 0)) != 0

func darknix_mark_seen() -> void:
	var d := darknix()
	d["seen"] = 1
	_data["darknix"] = d
	_commit()

func darknix_set_face(face: int) -> void:
	var d := darknix()
	d["face"] = face
	_data["darknix"] = d
	_commit()

func darknix_clear() -> void:
	_data["darknix"] = {"status": 0, "until": 0, "face": 0}
	_commit()

func _commit() -> void:
	if _autosave:
		SaveSystem.save(_data)

func species_name(id: int) -> String:
	var all = get_pmeta("species_names", {})
	if not (all is Dictionary):
		return ""
	return String((all as Dictionary).get(str(id), ""))

func set_species_name(id: int, name: String) -> void:
	var all = get_pmeta("species_names", {})
	var d: Dictionary = (all as Dictionary) if all is Dictionary else {}
	d[str(id)] = name
	set_pmeta("species_names", d)

func species_art(id: int) -> Dictionary:
	var all = get_pmeta("species_art", {})
	if not (all is Dictionary):
		return {}
	var v = (all as Dictionary).get(str(id), {})
	return v if v is Dictionary else {}

func set_species_art(id: int, art_id: int, element: String) -> void:
	var all = get_pmeta("species_art", {})
	var d: Dictionary = (all as Dictionary) if all is Dictionary else {}
	d[str(id)] = {"art_id": art_id, "element": element}
	set_pmeta("species_art", d)

func begin_batch() -> void:
	_autosave = false

func save() -> void:
	_autosave = true
	SaveSystem.save(_data)

func reset() -> void:
	_data = _default()
	SaveSystem.save(_data)

func reload() -> void:
	var loaded = SaveSystem.load_or_backup()
	_data = _default() if loaded == null else _migrate(loaded)

func raw() -> Dictionary:
	return _data

func _migrate(d: Dictionary) -> Dictionary:
	var ver := int(d.get("version", 1))
	if ver < 2:
		d = _migrate_v1_to_v2(d)
	d = _ensure_schema(d)
	if ver < SCHEMA_VERSION:
		print("[UserDB] 세이브 마이그레이션 v%d → v%d (%d마리)" % [ver, SCHEMA_VERSION, d["dragons"].size()])
		SaveSystem.save(d)
	return d

func _migrate_v1_to_v2(d: Dictionary) -> Dictionary:
	var base := _default()
	base["currency"] = d.get("currency", base["currency"])
	base["inventory"] = d.get("inventory", base["inventory"])
	base["progress"] = d.get("progress", base["progress"])
	base["rng_seed"] = d.get("rng_seed", null)
	base["cosmetics"] = {
		"cave_skin": int(d.get("cave_skin", 0)),
		"stand_skin": int(d.get("stand_skin", 0)),
		"wall_skin": int(d.get("wall_skin", 0)),
	}
	var old_list: Array = d.get("owned_dragons", [])
	var active_idx := int(d.get("active_dragon", 0))
	var uid := 1
	for i in old_list.size():
		var od: Dictionary = old_list[i]
		base["dragons"].append({
			"uid": uid, "id": int(od.get("id", 0)),
			"level": int(od.get("level", 1)), "exp": int(od.get("exp", 0)),
		})
		if i == active_idx:
			base["active_uid"] = uid
		uid += 1
	base["next_uid"] = uid
	if active_uid_of(base) == 0 and not base["dragons"].is_empty():
		base["active_uid"] = int(base["dragons"][0]["uid"])
	return base

func active_uid_of(d: Dictionary) -> int:
	return int(d.get("active_uid", 0))

func _ensure_schema(d: Dictionary) -> Dictionary:
	var base := _default()
	for k in base.keys():
		if not d.has(k):
			d[k] = base[k]
	for k in base["cosmetics"].keys():
		if not d["cosmetics"].has(k):
			d["cosmetics"][k] = base["cosmetics"][k]
	for k in base["user"].keys():
		if not d["user"].has(k):
			d["user"][k] = base["user"][k]
	d["is_admin"] = ADMIN or _admin_local
	var dm := []
	for v in d.get("dex_master", []):
		var iv := int(v)
		if not dm.has(iv):
			dm.append(iv)
	for dr0 in (d.get("dragons", []) as Array) + (d.get("storage", []) as Array):
		if Growth.is_aura_adult(int((dr0 as Dictionary).get("level", 1))):
			var mid := int((dr0 as Dictionary).get("id", 0))
			if mid > 0 and not dm.has(mid):
				dm.append(mid)
	d["dex_master"] = dm
	var sart = (d.get("meta", {}) as Dictionary).get("species_art", {})
	if not (sart is Dictionary):
		sart = {}
	for dr3 in (d.get("dragons", []) as Array) + (d.get("storage", []) as Array):
		var cid := int((dr3 as Dictionary).get("id", 0))
		var cart := int((dr3 as Dictionary).get("art_id", 0))
		if Summon.SPECIES.has(cid) and cart > 0 and not (sart as Dictionary).has(str(cid)):
			(sart as Dictionary)[str(cid)] = {"art_id": cart,
				"element": String((dr3 as Dictionary).get("element", ""))}
	if not (sart as Dictionary).is_empty():
		(d["meta"] as Dictionary)["species_art"] = sart
	var eg = d.get("meta", {}).get("egg_grades", null)
	if eg is Dictionary and not (eg as Dictionary).is_empty():
		var inv: Dictionary = d.get("inventory", {})
		var moved := 0
		for k in (eg as Dictionary):
			var ekey := String(k)
			for g in EggUpgrade.normalize((eg as Dictionary)[ekey]):
				var n := mini(int(EggUpgrade.normalize((eg as Dictionary)[ekey])[g]),
					int(inv.get(ekey, 0)))
				if n <= 0:
					continue
				inv[ekey] = int(inv.get(ekey, 0)) - n
				if int(inv[ekey]) <= 0:
					inv.erase(ekey)
				var gk := EggItem.key(ekey, int(g))
				inv[gk] = int(inv.get(gk, 0)) + n
				moved += n
		d["inventory"] = inv
		print("[UserDB] v15: 강화 알 %d개를 등급별 인벤 칸으로 분리" % moved)
	if d.has("meta") and (d["meta"] as Dictionary).has("egg_grades"):
		(d["meta"] as Dictionary).erase("egg_grades")
	_migrate_equip_options(d)
	for dr in d.get("dragons", []):
		_ensure_dragon_schema(dr, d["inventory"])
	for dr2 in d.get("storage", []):
		_ensure_dragon_schema(dr2, d["inventory"])
	d["version"] = SCHEMA_VERSION
	return d

func _migrate_equip_options(d: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var fixed := 0
	var inv: Dictionary = d.get("inventory", {})
	for key in inv.keys():
		var k := String(key)
		if not k.begins_with(Equipment.ITEM_PREFIX):
			continue
		var meta := Equipment.item_key_meta(k)
		var res: Array = Equipment.sanitize_options(meta.get("options", []), Data.equipment, rng)
		if int(res[1]) == 0:
			continue
		meta["options"] = res[0]
		var nk := Equipment.item_key(Equipment.parse_item_key(k), meta)
		var cnt := int(inv[k])
		inv.erase(k)
		inv[nk] = int(inv.get(nk, 0)) + cnt
		fixed += int(res[1])
	for dr in (d.get("dragons", []) as Array) + (d.get("storage", []) as Array):
		for s in ((dr as Dictionary).get("equip", {}).get("slots", []) as Array):
			var sd: Dictionary = s
			var r2: Array = Equipment.sanitize_options(sd.get("options", []), Data.equipment, rng)
			if int(r2[1]) == 0:
				continue
			sd["options"] = r2[0]
			fixed += int(r2[1])
	if fixed > 0:
		print("[UserDB] v17: 없어진 옵션(명중·관통 감소) %d개를 유효 옵션으로 다시 굴렸다" % fixed)

func _ensure_dragon_schema(dr: Dictionary, inv: Dictionary) -> void:
	dr.erase("grade")
	dr.erase("crest")
	dr.erase("engravings")
	if typeof(dr.get("stat_bonus")) != TYPE_DICTIONARY:
		dr["stat_bonus"] = _zero_bonus()
	if typeof(dr.get("equip_slots")) != TYPE_ARRAY:
		var n := clampi(int(dr.get("equip_slots", 1)), 1, Equipment.SLOT_ORDER.size())
		dr["equip_slots"] = Equipment.SLOT_ORDER.slice(0, n)
	if typeof(dr.get("gain_log")) != TYPE_ARRAY:
		dr["gain_log"] = _backfill_gain_log(dr)
	var gl: Array = dr["gain_log"]
	var want := maxi(int(dr.get("level", 1)) - 1, 0)
	if gl.size() < want:
		var full := _backfill_gain_log(dr)
		if full.size() >= want:
			for i in range(gl.size(), want):
				gl.append((full[i] as Dictionary).duplicate())
	if dr.has("fatigue"):
		if not dr.has("food"):
			dr["food"] = clampi(ItemEffect.FOOD_MAX - int(dr["fatigue"]), 0, ItemEffect.FOOD_MAX)
		dr.erase("fatigue")
	var defaults := {"exp": 0, "awakened": false, "awaken_skill": 0, "cure_time": 0,
		"food": ItemEffect.FOOD_MAX,
		"nickname": "", "locked": false, "favorite": false, "skills": [], "acquired_at": 0}
	for k in defaults.keys():
		if not dr.has(k):
			dr[k] = defaults[k]
	if bool(dr.get("awakened", false)) and int(dr.get("awaken_skill", 0)) <= 0:
		dr["awaken_skill"] = Data.awaken_skill_of(int(dr.get("id", 0)))
	if typeof(dr.get("gems")) != TYPE_DICTIONARY:
		dr["gems"] = {}
	var gf: Dictionary = dr["gems"]
	if typeof(gf.get("types")) != TYPE_ARRAY or (gf["types"] as Array).size() < Gem.SLOTS:
		gf["slots"] = Gem.entries(gf)
		gf["types"] = Gem.random_types(Data.gems)
	var gtypes: Array = Gem.types(gf)
	var gents: Array = Gem.entries(gf)
	var moved := false
	for i in Gem.SLOTS:
		var e = gents[i]
		if e == null:
			continue
		if Gem.accepts(String(gtypes[i]), String(e["name"]), Data.gems):
			continue
		var rk := Gem.item_key(String(e["name"]), int(e["tier"]))
		inv[rk] = int(inv.get(rk, 0)) + 1
		gents[i] = null
		moved = true
	if moved:
		gf["slots"] = gents
		print("[UserDB] uid=%d 슬롯 타입 불일치 젬을 가방으로 반환" % int(dr.get("uid", 0)))
	if typeof(dr.get("skill_slots")) != TYPE_ARRAY or (dr["skill_slots"] as Array).size() < Loadout.SKILL_SLOTS:
		dr["skill_slots"] = Loadout.random_slot_types()
	if typeof(dr.get("skill_equip")) != TYPE_ARRAY or (dr["skill_equip"] as Array).size() < Loadout.SKILL_SLOTS:
		var eq: Array = []
		var sk: Array = dr.get("skills", [])
		for i in Loadout.SKILL_SLOTS:
			eq.append(int((sk[i] as Dictionary).get("id", 0)) if i < sk.size() else 0)
		dr["skill_equip"] = eq
	if typeof(dr.get("skill_grants")) != TYPE_ARRAY:
		var claimed: Array = []
		for m in Loadout.SKILL_GRANT_LEVELS:
			if int(dr.get("level", 1)) >= int(m):
				claimed.append(int(m))
		dr["skill_grants"] = claimed

func _backfill_gain_log(dr: Dictionary) -> Array:
	var level := int(dr.get("level", 1))
	if level <= 1:
		return []
	var ddef: Dictionary = Data.get_dragon(int(dr.get("id", 0)))
	var row := Growth._tier_row(ddef, Data.stat_table)
	if row.is_empty():
		push_warning("[UserDB] gain_log 백필 실패(티어 미매칭) uid=%d id=%s" % [int(dr.get("uid", 0)), str(dr.get("id"))])
		return []
	var gb: Dictionary = (dr.get("stat_bonus", {}) as Dictionary).get("growth", {})
	var per := {}
	for k in ["hp", "att", "def"]:
		per[k] = int(row["growth"][k]) + int(gb.get(k, 0))
	var out: Array = []
	for i in level - 1:
		out.append(per.duplicate())
	return out
