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

	var ml := MissionBoard.open(Scenes.current_scene(), 1, "worldmap", {})
	await get_tree().process_frame
	await get_tree().process_frame

	var sc := _scroll(ml)
	if sc == null:
		print("[scroll] 목록을 못 찾았다"); get_tree().quit(1); return
	var want := 240
	sc.scroll_vertical = want
	await get_tree().process_frame
	want = sc.scroll_vertical
	if want <= 0:
		print("[scroll] 스크롤이 안 먹는다(목록이 창보다 짧다?)"); get_tree().quit(1); return

	var cells := _cell_buttons(sc)
	if cells.is_empty():
		print("[scroll] 회차 셀이 없다"); get_tree().quit(1); return
	cells[20].emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame

	var sc2 := _scroll(ml)
	var got := sc2.scroll_vertical if sc2 != null else -1
	print("[scroll] 클릭 전 %d → 재빌드 후 %d" % [want, got])
	get_tree().quit(0 if got == want else 1)

func _scroll(n: Node) -> ScrollContainer:
	if n is ScrollContainer:
		return n
	for c in n.get_children():
		var r := _scroll(c)
		if r != null:
			return r
	return null

func _cell_buttons(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Button:
			out.append(c)
		out += _cell_buttons(c)
	return out
