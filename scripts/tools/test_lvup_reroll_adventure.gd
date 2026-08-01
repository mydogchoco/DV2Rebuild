extends Node
## 🔴 탐험 중 레벨업 창의 리롤/AUTO 버튼 무동작(2026-08-01 사용자 신고) 재현/방지.
## 흐름 = shot_helper `lvresult` 와 동일하게 탐험을 levelups 파라미터로 열고,
## 연출이 끝날 시간을 준 뒤 RerollButton.pressed 를 실제로 방출해 상태 변화를 판정한다.
## Run: godot --headless --path . res://scenes/test_lvup_reroll_adventure.tscn

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
	# 리롤 비용을 낼 수 있게 재화를 넉넉히.
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
	# 연출 타임라인(워드아트 비행 ~3s + 행 공개 + 2s 대기)이 끝날 때까지 여유 있게.
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
	# 최상위에서 리롤 버튼 좌표로 실제 클릭 이벤트를 쏜다 — 사용자가 누르는 것과 같은 경로.
	var btn := _find_named(screen, "RerollButton")
	if btn == null:
		print("FAIL: RerollButton 없음"); fails += 1
	else:
		# ① 입력 가로채기 스캔(클릭 **전** — 리롤이 화면을 다시 그려 btn 이 해제된다) —
		#    버튼 위치를 덮는, 더 높은 캔버스레이어의 STOP 컨트롤이 있으면 실패.
		#    (실제 버그: enc 0 인트로 대사 레이어 80 의 전면 캐처가 레벨업 창 31 을 덮었다.)
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
		# ② 배선 검사 — pressed 를 직접 방출해 확인 팝업→확정까지 흘러가는지.
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

## 트리 순서(=그리기 순서)대로, pos 를 덮는 '클릭을 먹는' 컨트롤을 모은다.
## CanvasLayer 는 layer 값이 높을수록 위 — 간단화를 위해 트리 순회 순서에 layer 정렬을 얹는다.
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
