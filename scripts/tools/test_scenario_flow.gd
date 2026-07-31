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
## 채택 회차 수의 **바닥값**. 종전엔 회차가 통째로 사라져도 테스트가 못 잡았다 —
## `flows` 에 없는 회차는 아래 검사 루프를 아예 안 돌기 때문이다(2026-07-31 실측:
## 추출을 고치자 3·31·36·50 이 조용히 빠졌는데 PASS 였다).
const MIN_EPISODES := 99

## 1~78화(점프 테이블 추출)는 대사 수가 정확히 맞은 것만 올린다 — 회귀 앵커.
## ⚠️ 여기 오른 회차는 **flows 에 반드시 있어야 한다**(없으면 FAIL).
const EXACT := {
	1: true, 2: true, 3: true, 4: true, 5: true, 6: true, 7: true, 8: true,
	9: true, 10: true, 11: true, 12: true, 13: true, 14: true, 15: true, 16: true,
	17: true, 18: true, 19: true, 20: true, 21: true, 22: true, 23: true, 26: true,
	27: true, 28: true, 30: true, 31: true, 32: true, 33: true, 34: true, 35: true,
	36: true, 37: true, 39: true, 40: true, 41: true, 42: true, 43: true, 44: true,
	45: true, 46: true, 47: true, 48: true, 49: true, 51: true, 52: true, 53: true,
	54: true, 55: true, 56: true, 57: true, 58: true, 59: true, 60: true, 61: true,
	63: true, 64: true, 65: true, 66: true, 67: true, 68: true, 69: true, 70: true,
	71: true, 72: true, 73: true, 74: true, 75: true, 76: true, 77: true, 78: true,
	79: true, 80: true, 81: true,
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
			if op == "setNpcTalk" or op == "setUserTalk" or op == "setTalk" or op == "setTalker":
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

	# ③-b 회차 수 바닥값 + 앵커 회차 존재 — "조용히 사라지는" 회귀를 잡는다.
	if flows.size() < MIN_EPISODES:
		print("FAIL 회차 %d < 바닥값 %d" % [flows.size(), MIN_EPISODES]); fails += 1
	for k in EXACT.keys():
		if not flows.has(str(k)):
			print("FAIL ep%d: 앵커인데 flows 에 없다(추출 회귀)" % k); fails += 1

	# ④ 화자 번호가 전부 전표에 있는가 + 초상 자산 존재
	var unresolved := 0
	var missing_art := {}
	for sn in flows.keys():
		for o in flows[sn]:
			var d: Dictionary = o
			var op := String(d.get("op", ""))
			var folder := ""
			if op == "setNpcTalk":
				# 82~101화 — 화자를 **번호**로 넘긴다(getNPCname 전표로 푼다).
				var raw = d.get("npc", null)     # 미해석 스텝은 null 로 들어온다
				var no := int(raw) if raw != null else -1
				if no <= 0 or not npcs.has(str(no)):
					unresolved += 1
					continue
				folder = String(npcs[str(no)])
			elif op == "setTalk" or op == "setTalker":
				# 1~78화 — 화자를 **문자열**로 넘긴다(원작이 this+0x1d8 에 써 두는 값).
				# ⚠️ 미해석 스텝은 JSON null 이다. `String(null)` 은 4.7 런타임 에러이고
				#    `--script` 모드에서는 **에러 출력 없이 무한 대기**로 나타난다(실제로 걸렸다).
				var nv = d.get("npc_name", null)
				if typeof(nv) != TYPE_STRING or String(nv) == "":
					# 화자 대입이 없는 스텝 = **직전 화자 유지**가 원작 동작이다
					# (원작도 멤버 this+0x1d8 을 덮어쓰지 않으면 그대로 쓴다).
					# 오류가 아니라 정상 — story.gd 도 이름칸을 안 건드린다.
					unresolved += 1
					continue
				folder = String(nv)
			else:
				continue
			var dir := "res://assets/converted/npc_%s" % folder
			if not DirAccess.dir_exists_absolute(dir):
				missing_art[folder] = true
	if not missing_art.is_empty():
		# 원작에도 아틀라스가 없는 화자들 — 이름만 나오는 정상 케이스.
		#   who            = `<NPC_who>???`(정체불명 화자)
		#   monsterevent*  = `<NPC_monsterevent1>실험체 만드라고낙` 등 스토리 몬스터 화자.
		#                    `DV2/480/npc/` 126개에 없다(몬스터라 초상 파츠가 아니라 스파인이다).
		#   stonekeeper·lightorb = 빛의 탑 몬스터가 화자로 말한다(<NPC_stonekeeper>스톤키퍼 등).
		for k_no_art in ["who", "monsterevent1", "monsterevent2", "monsterevent3",
				"stonekeeper", "lightorb"]:
			missing_art.erase(k_no_art)
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

	# 보충분(`_recovered`) = 순회가 못 닿아 **키 리터럴에서 채운** 대사.
	# 게이트(대사 수 일치)는 통과해도 추출 품질은 이 비율로 따로 본다.
	var rec := 0
	var talk_all := 0
	for sn2 in flows.keys():
		for o2 in flows[sn2]:
			var d2: Dictionary = o2
			if String(d2.get("op", "")) in ["setNpcTalk", "setUserTalk", "setTalker", "setTalk"]:
				talk_all += 1
				if bool(d2.get("_recovered", false)):
					rec += 1
	if talk_all > 0 and rec * 100 / talk_all > 15:
		print("FAIL 보충 비율 %d%% — 추출이 퇴행했다(15%% 초과)" % (rec * 100 / talk_all)); fails += 1
	print("[flow] 회차 %d · 정합 검사 %d회차 · 화자 유지 %d · 보충 %d/%d" % [
		flows.size(), checked, unresolved, rec, talk_all])
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
