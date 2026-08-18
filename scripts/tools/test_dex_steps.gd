extends SceneTree

const EGG := preload("res://scripts/systems/egg_gacha.gd")

func _init() -> void:
	var fails := 0
	var meta: Dictionary = _load(_data_file("dex_meta.json"))

	var evo := 0
	var s01 := 0
	for k in meta:
		var m: Dictionary = meta[k]
		if bool(m.get("evo", false)): evo += 1
		if bool(m.get("awaken", false)): s01 += 1
	fails += _eq("각성 보유(box_evolution)", evo, 138)
	fails += _eq("box_s01 보유(각성 아님)", s01, 13)
	fails += _true("각성 보유가 s01 보다 훨씬 많다(판별 신호가 바뀐 이유)", evo > s01 * 5)

	var checked := 0
	var mismatch: Array = []
	var evo_no_frame: Array = []
	for k in meta:
		var did := int(k)
		var dir := "portrait_%d" % did
		if not FileAccess.file_exists("res://assets/converted/%s/_manifest.json" % dir):
			continue
		checked += 1
		var man: Dictionary = _load("res://assets/converted/%s/_manifest.json" % dir)
		var has_ev: bool = man.has("dragon_dragon_%d_box_evolution" % did)
		if has_ev != bool((meta[k] as Dictionary).get("evo", false)):
			mismatch.append(did)
		if bool((meta[k] as Dictionary).get("evo", false)) and not has_ev:
			evo_no_frame.append(did)
		if not man.has("dragon_dragon_%d_box_adult" % did):
			mismatch.append(did)
	fails += _true("초상 매니페스트 검사 대상 있음(%d)" % checked, checked > 300)
	fails += _eq("meta ↔ 초상 실측 불일치 없음", mismatch, [])
	fails += _eq("각성 보유인데 프레임 없는 종 없음", evo_no_frame, [])

	var five := 0
	var six := 0
	for k in meta:
		if bool((meta[k] as Dictionary).get("evo", false)): six += 1
		else: five += 1
	fails += _eq("6단계 종 수 = 각성 보유 수", six, evo)
	fails += _eq("5단계 + 6단계 = 전체", five + six, meta.size())

	var dragons_arr = _load_any(_data_file("dragons.json"))
	var hidden: Array = []
	var nameless: Array = []
	var by_id := {}
	for d in (dragons_arr as Array):
		var dd: Dictionary = d
		by_id[int(dd.get("id", 0))] = dd
		if bool(dd.get("dex_hidden", false)):
			hidden.append(int(dd.get("id", 0)))
		if String(dd.get("name", "")).strip_edges() == "":
			nameless.append(int(dd.get("id", 0)))
	hidden.sort(); nameless.sort()
	fails += _eq("기본 숨김 종 = 600·700", hidden, [600, 700])
	fails += _eq("이름 없는 종은 전부 숨김 처리돼 있다", nameless, hidden)
	var leaked: Array = []
	var elems: Array[String] = ["", "fire", "aqua", "wind", "earth", "light",
		"dark", "holy", "chaos", "shadow"]
	for star in range(1, 8):
		for ei in elems.size():
			for cid in EGG.candidates(by_id, star, elems[ei], {}, []):
				if hidden.has(int(cid)):
					leaked.append(int(cid))
	fails += _eq("뽑기 후보에 숨김 종 유출 없음", leaked, [])
	var any_pool := 0
	for star in range(1, 8):
		any_pool += EGG.candidates(by_id, star, "", {}, []).size()
	fails += _true("성급 후보 총합이 300 이상(%d)" % any_pool, any_pool >= 300)

	fails += _true("44 는 오라성체 아님", not Growth.is_aura_adult(44))
	fails += _true("45 = 오라성체", Growth.is_aura_adult(45))
	fails += _eq("오라성체도 아트는 adult", Growth.stage_for_level(45), "adult")
	fails += _eq("성체도 adult", Growth.stage_for_level(25), "adult")

	if fails == 0:
		print("[test_dex_steps] ✅ ALL PASS  (5단계 %d종 · 6단계 %d종)" % [five, six])
	else:
		print("[test_dex_steps] ❌ %d FAIL" % fails)
	quit(1 if fails > 0 else 0)

func _load_any(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())

func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}

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
