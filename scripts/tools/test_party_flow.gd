extends Node

func _ready() -> void:
	NewGame.ensure(UserDB, Data.new_game_def())
	var root := Control.new()
	root.name = "SceneRoot"
	root.size = get_viewport().get_visible_rect().size
	add_child(root)
	Scenes.bind_root(root)
	await get_tree().process_frame
	var fails := 0

	fails += await _case("일반(hero=false)", {"stage": "1", "region": "yutakan", "hero": false}, 1, false)
	fails += await _case("영웅(hero=true)", {"stage": "1", "region": "yutakan", "hero": true}, 3, true)
	var carried: Array = []
	for d in UserDB.dragons().slice(0, 3):
		carried.append(int(d["uid"]))
	fails += await _case("영웅 편성 이월", {"stage": "1", "region": "yutakan", "hero": true,
		"enc": 1, "party_uids": carried, "party_ready": true}, 3, false, carried.size())
	fails += await _case("혼돈의 틈새(8)", {"stage": "8", "region": "yutakan", "hero": false}, 3, true)

	UserDB.clear_party()
	for d in UserDB.dragons().slice(0, 3):
		UserDB.toggle_party(int(d["uid"]))
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

	await get_tree().process_frame
	var cards := 0
	var card_z_ok := true
	var stack: Array = [bs]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n == null: continue
		if n.has_meta("party_card"):
			cards += 1
			card_z_ok = card_z_ok and n.z_index == 400
		for c in n.get_children(): stack.append(c)
	var ok2 := cards == 1 and card_z_ok
	print("%-22s 카드=%d(기대 1) z=400=%s  %s" % [
		"1인 전투 카드", cards, card_z_ok, ("OK" if ok2 else "FAIL")])
	if not ok2: fails += 1

	print("결과: %s" % ("PASS" if fails == 0 else "FAIL(%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)

func _case(label: String, params: Dictionary, want_cap: int, want_popup: bool, want_run := 1) -> int:
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
	var popup := false
	for c in sc.get_children():
		if c is CanvasLayer and (c as CanvasLayer).layer == 30:
			popup = true
	var ok := cap == want_cap and popup == want_popup and run.size() == want_run
	print("%-22s 정원=%d(기대 %d) 편성창=%s(기대 %s) 출전=%d  %s" % [
		label, cap, want_cap, popup, want_popup, run.size(), ("OK" if ok else "FAIL")])
	return 0 if ok else 1
