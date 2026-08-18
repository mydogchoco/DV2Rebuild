extends SceneTree

func _init() -> void:
	var fails := 0
	var stages: Dictionary = _load(_data_file("stages.json"))
	var sdb: Dictionary = _load(_data_file("skills.json"))
	var cfg: Dictionary = _load(_data_file("combat.json"))

	var rosters := _rosters(stages)
	var with_skill := 0
	var bad_ids: Array = []
	for e in rosters:
		var ids: Array = (e as Dictionary).get("skills", [])
		if ids.is_empty():
			continue
		with_skill += 1
		for sid in ids:
			if not sdb.has(str(int(sid))):
				bad_ids.append(sid)
	print("[test_monster_skills] 편성 몬스터 %d / 스킬 보유 %d" % [rosters.size(), with_skill])
	fails += _true("편성에 스킬이 실려 있다", with_skill > 0)
	fails += _eq("skills.json 에 없는 id 없음", bad_ids, [])

	var fired := 0
	var fired_pass := 0
	for seed in range(1, 40):
		var res := _sim(cfg, sdb, [{"id": 14, "level": 1}], seed)
		for ev in (res.get("events", []) as Array):
			if String((ev as Dictionary).get("type", "")) == "skill" \
					and String((ev as Dictionary).get("caster", "")) == "E0":
				fired += 1
				break
	fails += _true("적 몬스터가 스킬을 발동한다(시드 39회 중 %d)" % fired, fired > 0)

	var eb := Battle.make_combatant("E0", "enemy", "none",
		{"hp": 900, "att": 110, "def": 55, "cri": 8, "evd": 6, "blk": 8}, 0.0, [{"id": 100, "level": 1}])
	Battle._init_combatant_skills(eb, sdb, cfg)
	fired_pass = (eb.get("effects", []) as Array).size()
	fails += _true("패시브 몬스터 스킬(100 맹수의 감각)이 전투원에 붙는다", fired_pass > 0)

	var sealed := 0
	for seed in range(1, 40):
		var res := _sim(cfg, {}, [{"id": 14, "level": 1}], seed)
		for ev in (res.get("events", []) as Array):
			if String((ev as Dictionary).get("type", "")) == "skill":
				sealed += 1
	fails += _eq("스킬 봉인 던전에서는 몬스터 스킬 0", sealed, 0)

	var a := _sim(cfg, sdb, [], 11)
	var b := _sim(cfg, sdb, [], 11)
	fails += _eq("스킬 없는 적 = 결정론 동일", _digest(a), _digest(b))
	fails += _true("스킬 없는 적은 skill 이벤트 0", _count_skill(a, "E0") == 0)

	if fails == 0:
		print("[test_monster_skills] ✅ ALL PASS")
	else:
		print("[test_monster_skills] ❌ %d FAIL" % fails)
	quit(1 if fails > 0 else 0)

func _rosters(stages: Dictionary) -> Array:
	var out: Array = []
	for _k in (stages.get("stages", {}) as Dictionary):
		var st: Dictionary = (stages["stages"] as Dictionary)[_k]
		for e in (st.get("enemies", []) as Array):
			out.append(e)
		for variant in ["night", "kades"]:
			var vv = st.get(variant)
			if vv is Dictionary:
				for e in ((vv as Dictionary).get("enemies", []) as Array):
					out.append(e)
	return out

func _allies() -> Array:
	var out: Array = []
	for i in 3:
		out.append(Battle.make_combatant("A%d" % i, "ally", "fire",
			{"hp": 1200, "att": 130, "def": 60, "cri": 10, "evd": 10, "blk": 10}))
	return out

func _sim(cfg: Dictionary, sdb: Dictionary, skills: Array, seed: int) -> Dictionary:
	var eb := Battle.make_combatant("E0", "enemy", "none",
		{"hp": 2600, "att": 110, "def": 55, "cri": 8, "evd": 6, "blk": 8}, 0.0, skills)
	return Battle.simulate(_allies(), [eb], _rng(seed), cfg, sdb)

func _count_skill(res: Dictionary, caster: String) -> int:
	var n := 0
	for ev in (res.get("events", []) as Array):
		if String((ev as Dictionary).get("type", "")) == "skill" \
				and String((ev as Dictionary).get("caster", "")) == caster:
			n += 1
	return n

func _digest(res: Dictionary) -> String:
	var s := String(res.get("winner", ""))
	for ev in (res.get("events", []) as Array):
		s += "|%s:%d" % [String((ev as Dictionary).get("type", "")), int((ev as Dictionary).get("damage", 0))]
	return s

func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r

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
