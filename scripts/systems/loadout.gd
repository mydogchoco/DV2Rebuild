class_name Loadout

const SKILL_SLOTS := 2
const SLOT_UNLOCK_LEVEL := [10, 35]

const SLOT_TYPES := ["tri", "sq", "cir", "star"]

static func slot_count(_dragon_def: Dictionary = {}) -> int:
	return SKILL_SLOTS

static func slot_unlocked(slot: int, level: int) -> bool:
	if slot < 0 or slot >= SKILL_SLOTS:
		return false
	return level >= int(SLOT_UNLOCK_LEVEL[slot])

static func slot_types(dr: Dictionary) -> Array:
	var raw: Array = dr.get("skill_slots", [])
	var out: Array = []
	for i in SKILL_SLOTS:
		var t := String(raw[i]) if i < raw.size() else ""
		out.append(t if t != "" else "star")
	return out

static func random_slot_types(rng: RandomNumberGenerator = null) -> Array:
	var out: Array = []
	for _i in SKILL_SLOTS:
		var k := (rng.randi() if rng != null else randi()) % SLOT_TYPES.size()
		out.append(String(SLOT_TYPES[k]))
	return out

static func slot_matches(slot_type: String, skill_def: Dictionary) -> bool:
	if slot_type == "star":
		return true
	return String(skill_def.get("slot", "")) == slot_type

static func slot_match_label(skill_def: Dictionary, cfg: Dictionary) -> String:
	var m: Dictionary = cfg.get("skill_slot_match", {})
	var parts: Array[String] = []
	var lv := int(m.get("level_bonus", 0))
	if lv > 0:
		parts.append("스킬 레벨 +%d" % lv)
	var cats: Array = m.get("heal_categories", [])
	var pct := int(m.get("power_pct", 0))
	if String(skill_def.get("category", "")) in cats and int(m.get("heal_use_bonus", 0)) > 0:
		parts.append("사용횟수 +%d" % int(m["heal_use_bonus"]))
	elif pct > 0:
		parts.append("피해 +%d%%" % pct)
	return " · ".join(parts) if not parts.is_empty() else "추가효과"

static func skill_comment(skill_def: Dictionary, rest: String) -> String:
	var desc := String(skill_def.get("desc", "")).strip_edges()
	var body := rest.strip_edges()
	if desc == "":
		return body
	if body == "":
		return desc
	return "%s\n\n%s" % [desc, body]

const ITEM_PREFIX := "skill:"

static func item_key(skill_id: int, level: int) -> String:
	return "%s%d:%d" % [ITEM_PREFIX, skill_id, level]

static func parse_item_key(key: String) -> Dictionary:
	if not key.begins_with(ITEM_PREFIX):
		return {}
	var p := key.substr(ITEM_PREFIX.length()).split(":")
	if p.size() < 2 or not p[0].is_valid_int() or not p[1].is_valid_int():
		return {}
	return {"id": int(p[0]), "level": int(p[1])}

static func is_skill_scroll(subcategory: String) -> bool:
	return subcategory == "memory_random" or subcategory == "memory_select"

static func scroll_candidates(scroll_key: String, table: Dictionary, skills_db: Dictionary) -> Array:
	var row: Dictionary = table.get(scroll_key, {})
	var out: Array = []
	for lv in row.get("levels", []):
		for sid in usable_pool(skills_db):
			var maxlv := int(skills_db.get(str(sid), {}).get("max_level", 5))
			if int(lv) <= maxlv:
				out.append({"id": int(sid), "level": int(lv)})
	return out

static func scroll_is_select(scroll_key: String, table: Dictionary) -> bool:
	return bool((table.get(scroll_key, {}) as Dictionary).get("select", false))

static func roll_scroll(scroll_key: String, table: Dictionary, skills_db: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var cand := scroll_candidates(scroll_key, table, skills_db)
	if cand.is_empty():
		return {}
	return cand[rng.randi_range(0, cand.size() - 1)]

static func can_learn(pool: Array, skill_id: int, level: int) -> bool:
	var have := -1
	for s in pool:
		if int((s as Dictionary).get("id", 0)) == int(skill_id):
			have = int((s as Dictionary).get("level", 0))
	if level <= 1:
		return have < 0
	return have == level - 1

const LEARN_BLOCKED_MSG := "#2ccddb84"

static func learn_from_item(pool: Array, skill_id: int, level: int, skills_db: Dictionary) -> Dictionary:
	var sd: Dictionary = skills_db.get(str(skill_id), {})
	if sd.is_empty():
		return {"skills": pool, "ok": false, "msg": "알 수 없는 스킬입니다"}
	var lv := clampi(level, 1, int(sd.get("max_level", 5)))
	if not can_learn(pool, int(skill_id), lv):
		return {"skills": pool, "ok": false, "msg": _ui(LEARN_BLOCKED_MSG)}
	var nm := String(sd.get("name", "스킬"))
	var ns: Array = []
	var was := 0
	for s in pool:
		if int(s.get("id", 0)) == int(skill_id):
			was = int(s.get("level", 0))
			continue
		ns.append((s as Dictionary).duplicate(true))
	ns.append({"id": int(skill_id), "level": lv, "dedicated": false})
	if was == 0:
		return {"skills": ns, "ok": true, "id": int(skill_id), "level": lv, "is_new": true,
			"msg": "%s Lv.%d 습득!" % [nm, lv]}
	return {"skills": ns, "ok": true, "id": int(skill_id), "level": lv, "is_new": false,
		"msg": "%s Lv.%d → Lv.%d" % [nm, was, lv]}

static func equipped_ids(dr: Dictionary) -> Array:
	var raw: Array = dr.get("skill_equip", [])
	var pool := {}
	for s in dr.get("skills", []):
		pool[int((s as Dictionary).get("id", 0))] = true
	var out: Array = []
	for i in SKILL_SLOTS:
		var id := int(raw[i]) if i < raw.size() else 0
		out.append(id if pool.has(id) else 0)
	return out

static func equipped_entry(dr: Dictionary, slot: int) -> Dictionary:
	var ids := equipped_ids(dr)
	if slot < 0 or slot >= ids.size() or int(ids[slot]) <= 0:
		return {}
	for s in dr.get("skills", []):
		if int((s as Dictionary).get("id", 0)) == int(ids[slot]):
			return s
	return {}

static func equip_skill(dr: Dictionary, slot: int, skill_id: int) -> Array:
	var ids := equipped_ids(dr)
	if slot < 0 or slot >= ids.size():
		return ids
	if int(skill_id) > 0:
		var prev := ids.find(int(skill_id))
		if prev >= 0 and prev != slot:
			ids[prev] = ids[slot]
	ids[slot] = int(skill_id)
	return ids

const SKILL_GRANT_LEVELS := [10, 25, 45]

static func due_grants(level: int, claimed: Array) -> Array:
	var out: Array = []
	for m in SKILL_GRANT_LEVELS:
		if level >= int(m) and not claimed.has(int(m)):
			out.append(int(m))
	return out

static func roll_grant(pool: Array, skills_db: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	var owned := {}
	for s in pool:
		owned[int((s as Dictionary).get("id", 0))] = true
	var cand: Array = []
	for sid in usable_pool(skills_db):
		if not owned.has(int(sid)):
			cand.append(int(sid))
	if cand.is_empty():
		return {}
	var r := rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	return {"id": int(cand[r.randi_range(0, cand.size() - 1)]), "level": 1}

static func default_skills(dragon_def: Dictionary, _skills_db: Dictionary = {}, overrides: Dictionary = {}, _rng: RandomNumberGenerator = null) -> Array:
	var id := int(dragon_def.get("id", 0))
	if overrides.has(str(id)):
		return normalize(overrides[str(id)])
	return []

static func usable_pool(skills_db: Dictionary) -> Array:
	var out: Array = []
	for k in skills_db:
		var sd: Dictionary = skills_db[k]
		if sd.get("active", false) and sd.get("usable", false):
			out.append(int(sd.get("id", int(str(k)) if str(k).is_valid_int() else 0)))
	out.sort()
	return out

static func normalize(raw) -> Array:
	var out: Array = []
	if raw is Array:
		for it in raw:
			if it is Array and it.size() >= 1:
				out.append({"id": int(it[0]), "level": (int(it[1]) if it.size() > 1 else 1), "dedicated": false})
			elif it is Dictionary:
				out.append({"id": int(it.get("id", 0)), "level": int(it.get("level", 1)), "dedicated": bool(it.get("dedicated", false))})
			elif it is String and "_" in it:
				var p := (it as String).split("_")
				if p[0].is_valid_int():
					out.append({"id": int(p[0]), "level": (int(p[1]) if p.size() > 1 and p[1].is_valid_int() else 1), "dedicated": false})
	return out

static func _ui(key: String) -> String:
	return UiText.get_text(key)
