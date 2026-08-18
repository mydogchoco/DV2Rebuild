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
	await get_tree().process_frame
	await get_tree().process_frame

	var ml := MissionBoard.open(Scenes.current_scene(), 0, "worldmap", {})
	if ml == null:
		print("미션 창 열기 실패"); get_tree().quit(1); return
	await get_tree().process_frame

	var pressed := 0
	for round_i in 3:
		var btns := _buttons(ml)
		if btns.is_empty():
			break
		var b: Button = btns[round_i % btns.size()]
		b.emit_signal("pressed")
		pressed += 1
		await get_tree().process_frame
		await get_tree().process_frame
	print("탭 버튼 pressed 방출 %d회 — 위에 시그널 방출 중 해제 에러가 없으면 통과" % pressed)
	get_tree().quit(0 if pressed > 0 else 1)

func _buttons(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Button:
			out.append(c)
		out += _buttons(c)
	return out
