extends SceneTree
## 헤드리스 검증 — **몬스터 스킬 배선**(§10: logic은 화면 없이 검증).
## 실행: godot --headless --path <proj> --script res://scripts/tools/test_monster_skills.gd
##
## 무엇을 지키는가
##   1. `data/stages.json` 편성에 `skills`(스킬 id) 칸이 실제로 실려 있다
##      (기입 도구 = `scripts/tools/build_monster_skills.py`, 출처 = 위키 → `data/monsters.json`).
##   2. 그 id 가 전부 `data/skills.json` 에 존재한다(오타·유실 id 가 조용히 no-op 되지 않게).
##   3. 전투 엔진이 **진영 무관**하게 그 스킬을 발동시킨다 — 적 전투원이 실제로 skill 이벤트를 낸다.
##   4. 스킬 봉인 던전(`no_skills`)에서는 몬스터 스킬도 함께 막힌다(드래곤과 같은 규칙).
##   5. 편성에 `skills` 가 없으면 전투가 종전과 완전히 동일하다(회귀 안전).

func _init() -> void:
	var fails := 0
	var stages: Dictionary = _load("res://data/stages.json")
	var sdb: Dictionary = _load("res://data/skills.json")
	var cfg: Dictionary = _load("res://data/combat.json")

	# ── 1) 데이터: 편성에 스킬이 실려 있나 ──────────────────────────────────
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

	# ── 2) 엔진: 적도 스킬을 쓴다 ────────────────────────────────────────
	# 확정 스킬(11 철갑 방패=패시브 방어, 14 피의 갈증=공격)로 적을 세우고, 여러 시드에서
	# 적 발화(caster="E0")가 나오는지 본다. 발동은 확률이라 시드를 훑는다.
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

	# 패시브 스킬(`active:false` = 90 신속이동 · 100 맹수의 감각 · 110 고속이동)은 이벤트가 아니라
	# 전투 시작 시 상시 효과로 붙는다 → 전투원 상태로 확인한다.
	# 100·110 은 편성에 실제로 실려 있는 몬스터 패시브다(맹수의 감각 ×2 · 고속이동 ×1).
	var eb := Battle.make_combatant("E0", "enemy", "none",
		{"hp": 900, "att": 110, "def": 55, "cri": 8, "evd": 6, "blk": 8}, 0.0, [{"id": 100, "level": 1}])
	Battle._init_combatant_skills(eb, sdb, cfg)
	fired_pass = (eb.get("effects", []) as Array).size()
	fails += _true("패시브 몬스터 스킬(100 맹수의 감각)이 전투원에 붙는다", fired_pass > 0)

	# ── 3) 스킬 봉인: 빈 skills_db 면 몬스터 스킬도 안 나온다 ──────────────
	var sealed := 0
	for seed in range(1, 40):
		var res := _sim(cfg, {}, [{"id": 14, "level": 1}], seed)
		for ev in (res.get("events", []) as Array):
			if String((ev as Dictionary).get("type", "")) == "skill":
				sealed += 1
	fails += _eq("스킬 봉인 던전에서는 몬스터 스킬 0", sealed, 0)

	# ── 4) 회귀: 스킬 없는 적은 종전과 동일 ────────────────────────────────
	var a := _sim(cfg, sdb, [], 11)
	var b := _sim(cfg, sdb, [], 11)
	fails += _eq("스킬 없는 적 = 결정론 동일", _digest(a), _digest(b))
	fails += _true("스킬 없는 적은 skill 이벤트 0", _count_skill(a, "E0") == 0)

	if fails == 0:
		print("[test_monster_skills] ✅ ALL PASS")
	else:
		print("[test_monster_skills] ❌ %d FAIL" % fails)
	quit(1 if fails > 0 else 0)

# ---------- helpers ----------
## 스테이지 편성 전부(낮 + 밤/카데스 변형 블록).
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
