extends Node
## 출전 인원 흐름 검증 (원작 구조 이식분).
##   일반 난이도 → 리더 1마리, 편성창 없음
##   영웅 난이도 / 랜덤보스(혼돈의 틈새) → 3마리, 편성창 표시
## main.tscn 위에서 돌려야 오토로드·Scenes 루트가 살아 있다.
## Run: godot --headless --path . res://scenes/test_party_flow.tscn

func _ready() -> void:
	# main.gd 와 같은 부트스트랩(오토로드 + Scenes 루트).
	NewGame.ensure(UserDB, Data.new_game_def())
	var root := Control.new()
	root.name = "SceneRoot"
	root.size = get_viewport().get_visible_rect().size
	add_child(root)
	Scenes.bind_root(root)
	await get_tree().process_frame
	var fails := 0

	# 일반 난이도 — 리더 1마리, 편성창 없음
	fails += await _case("일반(hero=false)", {"stage": "1", "region": "yutakan", "hero": false}, 1, false)
	# 영웅 난이도 — 3마리 + 편성창
	fails += await _case("영웅(hero=true)", {"stage": "1", "region": "yutakan", "hero": true}, 3, true)
	# 혼돈의 틈새(random_boss) — 3마리 + 편성창
	fails += await _case("혼돈의 틈새(8)", {"stage": "8", "region": "yutakan", "hero": false}, 3, true)

	# 전투가 탐험의 출전 인원을 그대로 쓰는가 — 1인 탐험에서 3마리가 나오면 실패.
	UserDB.clear_party()
	for d in UserDB.dragons().slice(0, 3):
		UserDB.toggle_party(int(d["uid"]))     # 전역 파티는 일부러 3마리로 채워 둔다
	Scenes.goto("worldmap", {})
	await get_tree().process_frame
	Scenes.goto("battle", {"stage": "1", "region": "yutakan", "enc": 0,
		"party_uids": [UserDB.active_uid()]})
	await get_tree().process_frame
	var bs := Scenes.current_scene()
	var bp: Array = bs.get("_party") if bs else []
	var ok := bp.size() == 1
	print("%-22s 전투 출전=%d(기대 1, 전역 파티는 3)  %s" % ["전투 인원 전달", bp.size(), ("OK" if ok else "FAIL")])
	if not ok: fails += 1

	# 1인 전투에서 파티 카드가 정확히 1장만 그려지는지(원작 setInterfaceDragon 배치는 1~3장 대응).
	await get_tree().process_frame
	var cards := 0
	var stack: Array = [bs]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n == null: continue
		if n.has_meta("party_card"): cards += 1
		for c in n.get_children(): stack.append(c)
	var ok2 := cards == 1
	print("%-22s 카드=%d(기대 1)  %s" % ["1인 전투 카드", cards, ("OK" if ok2 else "FAIL")])
	if not ok2: fails += 1

	print("결과: %s" % ("PASS" if fails == 0 else "FAIL(%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)


func _case(label: String, params: Dictionary, want_cap: int, want_popup: bool) -> int:
	# adventure→adventure 전환은 막혀 있다(scene_manager REGISTRY) → 월드맵을 거친다.
	Scenes.goto("worldmap", {})
	await get_tree().process_frame
	Scenes.goto("adventure", params)
	await get_tree().process_frame
	var sc := Scenes.current_scene()
	if sc == null:
		print("%-22s 씬 로드 실패" % label)
		return 1
	var cap := int(sc.call("_party_capacity"))
	var run: Array = sc.get("_run_party")
	# 편성창은 CanvasLayer(layer 30) 오버레이로 뜬다.
	var popup := false
	for c in sc.get_children():
		if c is CanvasLayer and (c as CanvasLayer).layer == 30:
			popup = true
	var ok := cap == want_cap and popup == want_popup and (want_popup or run.size() == 1)
	print("%-22s 정원=%d(기대 %d) 편성창=%s(기대 %s) 출전=%d  %s" % [
		label, cap, want_cap, popup, want_popup, run.size(), ("OK" if ok else "FAIL")])
	return 0 if ok else 1
