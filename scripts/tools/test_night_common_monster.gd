extends SceneTree

const F := preload("res://scripts/systems/field.gd")
const D := preload("res://scripts/systems/drops.gd")
const AR := preload("res://scripts/systems/adventure_run.gd")
const ADV_PATH := "res://scripts/ui/adventure.gd"
const BTL_PATH := "res://scripts/ui/battle.gd"

const ENCOUNTER_IDS := [160, 161, 162, 175]
const ENCOUNTER_BOSS_IDS := [175]
const IMP_IDS := [160, 161]

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var fails := 0
	var stages: Dictionary = (_json(_data_file("stages.json")) as Dictionary)["stages"]

	var bad_flag: Array = []
	var bad_group: Array = []
	var night_ids: Array = []
	for sid in stages:
		var st: Dictionary = stages[sid]
		if not F.has_variant(st, D.MODE_NIGHT):
			continue
		night_ids.append(int(sid))
		var nv := F.apply_variant(st, D.MODE_NIGHT)
		var commons := 0
		for e in (nv.get("enemies", []) as Array):
			var er: Dictionary = e
			var eid := int(er.get("id", -1))
			var is_b := bool(er.get("boss", false))
			var is_c := bool(er.get("encounter", false))
			if is_c: commons += 1
			if ENCOUNTER_IDS.has(eid) != is_c:
				bad_group.append("%s:%d" % [sid, eid])
			var want_boss := (not ENCOUNTER_IDS.has(eid)) or ENCOUNTER_BOSS_IDS.has(eid)
			if is_b != want_boss:
				bad_flag.append("%s:%d(boss=%s)" % [sid, eid, str(is_b)])
		if commons != ENCOUNTER_IDS.size():
			bad_group.append("%s(공용 %d종)" % [sid, commons])
	fails += _eq("밤 변형 지역 수", night_ids.size(), 12)
	fails += _eq("boss 플래그가 틀린 밤 편성", bad_flag, [])
	fails += _eq("encounter 그룹이 틀린 밤 편성", bad_group, [])

	var adv = (load(ADV_PATH) as GDScript).new()
	var night1 := F.apply_variant(stages["1"], D.MODE_NIGHT)
	adv.set("_stage", night1)
	adv.set("_params", {"enc": 0, "night": true})
	var enemies: Array = night1.get("enemies", [])
	for i in enemies.size():
		var er2: Dictionary = enemies[i]
		var eid2 := int(er2.get("id", -1))
		var want := (not ENCOUNTER_IDS.has(eid2)) or ENCOUNTER_BOSS_IDS.has(eid2)
		fails += _eq("밤 편성[%d] #%d 보스판정" % [i, eid2], bool(adv.call("_is_boss_at", i)), want)
		adv.set("_rboss_enc", i)
		fails += _eq("밤 조우 #%d 보스판정(강제 인덱스)" % eid2,
			bool(adv.call("_next_is_boss")), want)
	adv.set("_rboss_enc", -1)

	for imp in IMP_IDS:
		var idx := _index_of(enemies, imp)
		fails += _true("밤 편성에 #%d 있음" % imp, idx >= 0)
		if idx >= 0:
			fails += _true("#%d 는 일반 몬스터" % imp, not bool(adv.call("_is_boss_at", idx)))

	var day1: Dictionary = stages["1"]
	adv.set("_stage", day1)
	var dn := int((day1.get("enemies", []) as Array).size())
	for i2 in dn:
		adv.set("_params", {"enc": i2})
		fails += _eq("낮 던전 조우 %d/%d 보스판정" % [i2 + 1, dn],
			bool(adv.call("_is_boss_at", i2)), i2 == dn - 1)
	adv.free()

	var btl = (load(BTL_PATH) as GDScript).new()
	btl.set("_params", {"stage": "1", "enc": enemies.size() - 1, "night": true, "boss": false})
	btl.set("_enemy", {"boss": false})
	fails += _true("전투: 넘겨받은 비보스 판정이 순번을 이긴다", not bool(btl.call("_is_boss")))
	btl.set("_params", {"stage": "1", "enc": 0, "night": true, "boss": true})
	fails += _true("전투: 넘겨받은 보스 판정", bool(btl.call("_is_boss")))
	btl.free()

	var want_common: Array = []
	for eid3 in ENCOUNTER_IDS:
		var ci := _index_of(enemies, eid3)
		if ci >= 0: want_common.append(ci)
	want_common.sort()
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var got_common: Array = _sampled_indices(night1, 0, 100, 0, rng, 400)
	fails += _eq("'공용몹' 갈래에서 뽑히는 인덱스", got_common, want_common)
	var got_boss: Array = _sampled_indices(night1, 0, 0, 100, rng, 200)
	fails += _eq("'지역보스' 갈래에서 뽑히는 인덱스", got_boss, [0])
	var wi := _index_of(enemies, 175)
	fails += _true("윗치는 보스 취급", bool((enemies[wi] as Dictionary).get("boss", false)))

	if fails == 0:
		print("[test_night_common_monster] ALL PASS")
		quit(0)
	else:
		printerr("[test_night_common_monster] %d FAIL" % fails)
		quit(1)

func _sampled_indices(night: Dictionary, w_nothing: int, w_common: int, w_boss: int,
		rng: RandomNumberGenerator, n: int) -> Array:
	var cfg := {"night": {"weights":
		{"nothing": w_nothing, "encounter": w_common, "boss": w_boss}}}
	var seen := {}
	for _i in n:
		var s: Dictionary = AR.night_steps(night, cfg, rng)[0]
		if s.has("enemy_index"):
			seen[int(s["enemy_index"])] = true
	var out: Array = seen.keys()
	out.sort()
	return out

func _index_of(enemies: Array, mid: int) -> int:
	for i in enemies.size():
		if int((enemies[i] as Dictionary).get("id", -1)) == mid:
			return i
	return -1

func _json(path: String):
	return JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())

func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	printerr("  FAIL %s: got=%s want=%s" % [label, str(got), str(want)])
	return 1

func _true(label: String, cond: bool) -> int:
	if cond:
		return 0
	printerr("  FAIL %s" % label)
	return 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
