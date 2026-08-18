extends SceneTree

const MIN_EPISODES := 108

const EXACT := {
	1: true, 2: true, 3: true, 4: true, 5: true, 6: true, 7: true, 8: true, 9: true,
	10: true, 11: true, 12: true, 13: true, 14: true, 15: true, 16: true, 17: true, 18: true,
	19: true, 20: true, 21: true, 22: true, 23: true, 24: true, 25: true, 26: true, 27: true,
	28: true, 29: true, 30: true, 31: true, 32: true, 33: true, 34: true, 35: true, 36: true,
	37: true, 38: true, 39: true, 40: true, 41: true, 42: true, 43: true, 44: true, 45: true,
	46: true, 47: true, 48: true, 49: true, 50: true, 51: true, 52: true, 53: true, 54: true,
	55: true, 56: true, 57: true, 58: true, 59: true, 60: true, 61: true, 62: true, 63: true,
	64: true, 65: true, 66: true, 67: true, 68: true, 69: true, 70: true, 71: true, 72: true,
	73: true, 74: true, 75: true, 76: true, 77: true, 78: true, 79: true, 80: true, 81: true,
	82: true, 83: true, 84: true, 85: true, 87: true, 88: true, 89: true, 90: true, 91: true,
	94: true, 96: true, 97: true, 99: true, 100: true}

func _init() -> void:
	var fails := 0
	var flow := _json(_data_file("scenario_flow.json"))
	var scen := _json(_data_file("scenario.json"))
	if flow.is_empty() or scen.is_empty():
		print("FAIL: data/scenario_flow.json 또는 scenario.json 로드 실패"); quit(1); return

	var npcs: Dictionary = flow.get("npc_names", {})
	var bgs: Dictionary = flow.get("backgrounds", {})
	var flows: Dictionary = flow.get("flows", {})
	var scenarios: Dictionary = scen.get("scenarios", {})

	for pair in [[1, "randolph"], [4, "popo"], [9, "jimon"], [10, "nuri"],
			[21, "berutaon"], [24, "mamorudic"]]:
		var got := String(npcs.get(str(pair[0]), ""))
		if got != String(pair[1]):
			print("FAIL npc %d: %s != %s" % [pair[0], got, pair[1]]); fails += 1

	for pair in [[1, "scenario/main_story/bg/townsquare.jpg"],
			[4, "scenario/main_story/bg/townsquare_night.jpg"],
			[13, "scene/adventure/bg/504/bg.jpg"]]:
		var arr: Array = bgs.get(str(pair[0]), [])
		if arr.is_empty() or String(arr[0]) != String(pair[1]):
			print("FAIL bg %d: %s" % [pair[0], arr]); fails += 1

	var checked := 0
	for sn in flows.keys():
		var ops: Array = flows[sn]
		var talk := 0
		for o in ops:
			var op := String((o as Dictionary).get("op", ""))
			if op == "npc_talk" or op == "user_talk" or op == "talk" or op == "talker_in":
				talk += 1
		var sc: Dictionary = scenarios.get(sn, {})
		var lines := 0
		for p in sc.get("parts", []):
			lines += (p as Dictionary).get("lines", []).size()
		if EXACT.get(int(sn), false):
			checked += 1
			if talk != lines:
				print("FAIL ep%s: 흐름 대사 %d != 원작 %d" % [sn, talk, lines]); fails += 1
		elif talk > lines:
			print("WARN ep%s: 흐름 %d > 대사 %d (분기 추정)" % [sn, talk, lines])

	if flows.size() < MIN_EPISODES:
		print("FAIL 회차 %d < 바닥값 %d" % [flows.size(), MIN_EPISODES]); fails += 1
	for k in EXACT.keys():
		if not flows.has(str(k)):
			print("FAIL ep%d: 앵커인데 flows 에 없다(추출 회귀)" % k); fails += 1

	var unresolved := 0
	var missing_art := {}
	for sn in flows.keys():
		for o in flows[sn]:
			var d: Dictionary = o
			var op := String(d.get("op", ""))
			var folder := ""
			if op == "npc_talk":
				var raw = d.get("npc", null)
				var no := int(raw) if raw != null else -1
				if no <= 0 or not npcs.has(str(no)):
					unresolved += 1
					continue
				folder = String(npcs[str(no)])
			elif op == "talk" or op == "talker_in":
				var nv = d.get("npc_name", null)
				if typeof(nv) != TYPE_STRING or String(nv) == "":
					unresolved += 1
					continue
				folder = String(nv)
			else:
				continue
			var dir := "res://assets/converted/npc_%s" % folder
			if not DirAccess.dir_exists_absolute(dir):
				missing_art[folder] = true
	if not missing_art.is_empty():
		for k_no_art in ["who", "monsterevent1", "monsterevent2", "monsterevent3",
				"stonekeeper", "lightorb", "prologuemonster"]:
			missing_art.erase(k_no_art)
		if not missing_art.is_empty():
			print("WARN 초상 미변환 NPC: ", missing_art.keys())

	var bg_missing := []
	for sn in flows.keys():
		for o in flows[sn]:
			var d: Dictionary = o
			if not String(d.get("op", "")).begins_with("bg"):
				continue
			var rawbg = d.get("bg", null)
			var arr: Array = bgs.get(str(int(rawbg) if rawbg != null else -1), [])
			if arr.is_empty():
				continue
			var res := _bg_res(String(arr[0]))
			if res == "" and not bg_missing.has(String(arr[0])):
				bg_missing.append(String(arr[0]))
	if not bg_missing.is_empty():
		print("WARN 배경 미보유(§10 판본 불일치): ", bg_missing)

	var rec := 0
	var talk_all := 0
	for sn2 in flows.keys():
		for o2 in flows[sn2]:
			var d2: Dictionary = o2
			if String(d2.get("op", "")) in ["npc_talk", "user_talk", "talker_in", "talk"]:
				talk_all += 1
				if d2.has("_recovered"):
					rec += 1
	if talk_all > 0 and rec * 100 / talk_all > 15:
		print("FAIL 보충 비율 %d%% — 추출이 퇴행했다(15%% 초과)" % (rec * 100 / talk_all)); fails += 1
	print("[flow] 회차 %d · 정합 검사 %d회차 · 화자 유지 %d · 보충 %d/%d" % [
		flows.size(), checked, unresolved, rec, talk_all])
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit(0 if fails == 0 else 1)

func _bg_res(orig: String) -> String:
	var cands: Array[String] = []
	var re := RegEx.create_from_string(r"scene/adventure/bg/(\d+)/")
	var r := re.search(orig)
	if r:
		cands.append("res://assets/converted/adventure_bg/bg_%s.jpg" % r.get_string(1))
	elif orig.begins_with("scenario/main_story/bg/"):
		cands.append("res://assets/converted/scenario/bg/%s" % orig.get_file())
	elif orig.begins_with("scene/magicshop/"):
		cands.append("res://assets/converted/magicshop_bg/%s" % orig.get_file())
	for c in cands:
		if ResourceLoader.exists(c):
			return c
	return ""

func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
