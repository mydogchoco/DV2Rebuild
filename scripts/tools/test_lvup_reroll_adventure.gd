extends Node

func _ready() -> void:
	NewGame.ensure(UserDB, Data.new_game_def())
	var root := Control.new()
	root.name = "SceneRoot"
	root.size = get_viewport().get_visible_rect().size
	add_child(root)
	Scenes.bind_root(root)
	await get_tree().process_frame

	Scenes.goto("worldmap", {"region": "yutakan"})
	for i in 10: await get_tree().process_frame
	var uid := UserDB.active_uid()
	var d: Dictionary = UserDB.get_dragon(uid)
	var lv := int(d.get("level", 10))
	var ms: Dictionary = Growth.tier_growth(Data.get_dragon(int(d.get("id", 1))), Data.stat_table)
	UserDB.add_currency("gold", 100000)
	UserDB.add_currency("diamond", 1000)
	Scenes.goto("adventure", {"stage": "1", "region": "yutakan", "enc": 0,
		"hp_state": {}, "streak": 0,
		"levelups": [{"uid": uid, "name": String(d.get("name", "드래곤")),
			"from_lv": lv - 1, "to_lv": lv,
			"gains": [{"hp": int(ms.get("hp", 0)), "att": int(ms.get("att", 0)),
				"def": maxi(0, int(ms.get("def", 0)) - 1),
				"is_max": {"hp": false, "att": false, "def": false}, "tmax": {}}],
			"max_stats": ms}]})
	var screen: Node = null
	for i in 40:
		await get_tree().create_timer(0.5).timeout
		screen = _find_lvup(get_tree().root)
		if screen != null and not bool(screen.get("_lvup_fx_busy")):
			break
	var fails := 0
	if screen == null:
		print("FAIL: LevelUpScreen 이 안 열렸다"); get_tree().quit(1); return
	if bool(screen.get("_lvup_fx_busy")):
		print("FAIL: 연출 20초 후에도 _lvup_fx_busy — 차단막이 안 걷힌다(버튼 무동작의 원인)")
		fails += 1
	var btn := _find_named(screen, "RerollButton")
	if btn == null:
		print("FAIL: RerollButton 없음"); fails += 1
	else:
		var center: Vector2 = (btn as Control).get_global_rect().get_center()
		var my_layer := _canvas_layer_of(btn)
		var hits: Array = []
		_scan_hits(get_tree().root, center, hits)
		var eaters := 0
		for o in hits:
			if o != btn and _canvas_layer_of(o) > my_layer:
				print("① 버튼 위를 덮는 STOP 컨트롤: %s layer=%d" % [o.name, _canvas_layer_of(o)])
				eaters += 1
		if eaters > 0: fails += 1
		else: print("① 히트스캔: 버튼이 최상단  OK")
		var gold0 := UserDB.gold()
		var dia0 := UserDB.diamond()
		(btn as Button).emit_signal("pressed")
		for i in 6: await get_tree().process_frame
		var confirm := _find_text_button(get_tree().root, ["확인", "다시뽑기", "예"])
		if confirm != null:
			(confirm as Button).emit_signal("pressed")
			for i in 6: await get_tree().process_frame
		else:
			print("  (확인 팝업 없음 — pressed 가 아무것도 안 열었다)")
		await get_tree().create_timer(1.5).timeout
		var moved := UserDB.gold() != gold0 or UserDB.diamond() != dia0
		print("② 배선: 골드 %d→%d · 다이아 %d→%d  %s"
			% [gold0, UserDB.gold(), dia0, UserDB.diamond(), "OK" if moved else "FAIL"])
		if not moved: fails += 1
	print("=== 실패 %d건 ===" % fails)
	get_tree().quit(0 if fails == 0 else 1)

func _scan_hits(n: Node, pos: Vector2, out: Array) -> void:
	if n is Control:
		var c := n as Control
		if c.is_visible_in_tree() and c.mouse_filter != Control.MOUSE_FILTER_IGNORE \
				and c.get_global_rect().has_point(pos):
			out.append(c)
	for ch in n.get_children():
		_scan_hits(ch, pos, out)

func _canvas_layer_of(n: Node) -> int:
	var p := n
	while p != null:
		if p is CanvasLayer:
			return (p as CanvasLayer).layer
		p = p.get_parent()
	return 0

func _find_lvup(n: Node) -> Node:
	if n.get_script() != null and String(n.get_script().resource_path).ends_with("levelup_screen.gd"):
		return n
	for c in n.get_children():
		var r := _find_lvup(c)
		if r != null: return r
	return null

func _find_named(n: Node, nm: String) -> Node:
	if n.name == nm: return n
	for c in n.get_children():
		var r := _find_named(c, nm)
		if r != null: return r
	return null

func _find_text_button(n: Node, texts: Array) -> Node:
	if n is Button and String((n as Button).text) in texts and (n as Button).is_visible_in_tree():
		return n
	for c in n.get_children():
		var r := _find_text_button(c, texts)
		if r != null: return r
	return null
