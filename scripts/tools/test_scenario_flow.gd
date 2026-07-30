extends SceneTree
## 헤드리스 시나리오 연출 흐름 검증 (§8 — data 층은 화면 없이 검증).
##
## 검증 대상 = 원작 회차 클래스(`Scenario1~8`/`_zimon`/`_mamorudic`/`_Kadeath`)의
## `initScenarioData` 하드코딩분을 그대로 옮겼는지.
##   추출 = `extract_scenario_flow.py`(Ghidra 로 std::function 스텝 본문 디컴프)
##        → `parse_scenario_flow.py`(리터럴 인자 복원) → `data/scenario_flow.json`
##
## 기준값(디컴프 축자):
##   · `ScenarioSupport::getNPCname` → NPC 번호 44종. 1=randolph · 4=popo · 9=jimon ·
##     10=nuri · 21=berutaon · 24=mamorudic
##   · `ScenarioSupport::changeBackGround` → BackGruundName 1=townsquare · 4=townsquare_night ·
##     0xd(13)=탐험배경 504
##   · 82~85화는 흐름의 대사 스텝 수가 **원작 대사 줄 수와 정확히 일치**한다(추출 정합의 앵커).
##     86화는 미니게임 분기라 7줄 적은 것이 정상.
##
## 실행: godot --headless --path . --script res://scripts/tools/test_scenario_flow.gd --quit-after 3

## 회차 → 원작 대사 줄 수와 일치해야 하는가(분기 회차는 false).
const EXACT := {79: true, 80: true, 81: true,
	82: true, 83: true, 84: true, 85: true, 87: true, 88: true,
	89: true, 90: true, 91: true, 94: true, 96: true, 97: true, 99: true, 100: true}

func _init() -> void:
	var fails := 0
	var flow := _json("res://data/scenario_flow.json")
	var scen := _json("res://data/scenario.json")
	if flow.is_empty() or scen.is_empty():
		print("FAIL: data/scenario_flow.json 또는 scenario.json 로드 실패"); quit(1); return

	var npcs: Dictionary = flow.get("npc_names", {})
	var bgs: Dictionary = flow.get("backgrounds", {})
	var flows: Dictionary = flow.get("flows", {})
	var scenarios: Dictionary = scen.get("scenarios", {})

	# ① NPC 전표 — 디컴프 축자 6건
	for pair in [[1, "randolph"], [4, "popo"], [9, "jimon"], [10, "nuri"],
			[21, "berutaon"], [24, "mamorudic"]]:
		var got := String(npcs.get(str(pair[0]), ""))
		if got != String(pair[1]):
			print("FAIL npc %d: %s != %s" % [pair[0], got, pair[1]]); fails += 1

	# ② 배경 전표 — 디컴프 축자 3건
	for pair in [[1, "scenario/main_story/bg/townsquare.jpg"],
			[4, "scenario/main_story/bg/townsquare_night.jpg"],
			[13, "scene/adventure/bg/504/bg.jpg"]]:
		var arr: Array = bgs.get(str(pair[0]), [])
		if arr.is_empty() or String(arr[0]) != String(pair[1]):
			print("FAIL bg %d: %s" % [pair[0], arr]); fails += 1

	# ③ 회차별 대사 스텝 수 ↔ 원작 대사 줄 수
	var checked := 0
	for sn in flows.keys():
		var ops: Array = flows[sn]
		var talk := 0
		for o in ops:
			var op := String((o as Dictionary).get("op", ""))
			if op == "setNpcTalk" or op == "setUserTalk":
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
			# 흐름이 대사보다 길면 재생 중 빈 줄이 난다 — 분기 회차만 허용
			print("WARN ep%s: 흐름 %d > 대사 %d (분기 추정)" % [sn, talk, lines])

	# ④ 화자 번호가 전부 전표에 있는가 + 초상 자산 존재
	var unresolved := 0
	var missing_art := {}
	for sn in flows.keys():
		for o in flows[sn]:
			var d: Dictionary = o
			if String(d.get("op", "")) != "setNpcTalk":
				continue
			var raw = d.get("npc", null)         # 미해석 스텝은 null 로 들어온다
			var no := int(raw) if raw != null else -1
			if no <= 0 or not npcs.has(str(no)):
				unresolved += 1
				continue
			var folder := String(npcs[str(no)])
			var dir := "res://assets/converted/npc_%s" % folder
			if not DirAccess.dir_exists_absolute(dir):
				missing_art[folder] = true
	if not missing_art.is_empty():
		print("WARN 초상 미변환 NPC: ", missing_art.keys())

	# ⑤ 배경 번호가 우리 변환본으로 이어지는가
	var bg_missing := []
	for sn in flows.keys():
		for o in flows[sn]:
			var d: Dictionary = o
			if not String(d.get("op", "")).begins_with("changeBackGround"):
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

	print("[flow] 회차 %d · 정합 검사 %d회차 · 화자 미해석 %d" % [flows.size(), checked, unresolved])
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit(0 if fails == 0 else 1)


## story.gd `_bg_res` 와 같은 규칙(중복이지만 테스트는 오토로드 없이 돈다).
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
