extends Node
## 미션 창 탭 전환 회귀 — 🔴 "Object was freed ... while a signal is being emitted" 재현/방지.
##
## 원인: 탭 버튼의 `pressed` 핸들러가 `_rebuild` → `_build` 를 부르는데, `_build` 가
##   `remove_child(c)` 뒤에 **`c.free()`(즉시 해제)** 를 해서 **시그널을 방출하는 중인 그 버튼
##   자신**을 지워 버렸다. 겹침 방지는 `remove_child` 가 하는 일이라 해제만 프레임 끝으로
##   미루면(`queue_free`) 두 목적이 다 선다 — `mission_layer.gd::_build` 참조.
##
## 이 스크립트는 **버튼의 pressed 를 실제로 방출**해서 그 경로를 탄다.
## 엔진 에러는 GDScript 로 못 잡으므로, 판정은 **실행 출력 grep**으로 한다:
##   godot --headless --path . res://scenes/test_mission_rebuild.tscn 2>&1 \
##     | grep -c "while a signal is being emitted"      → **0 이어야 한다**
##
## Run: godot --headless --path . res://scenes/test_mission_rebuild.tscn

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

	var ml := MissionLayer.open(Scenes.current_scene(), 0, "worldmap", {})
	if ml == null:
		print("미션 창 열기 실패"); get_tree().quit(1); return
	await get_tree().process_frame

	# 탭 버튼을 찾아 실제로 pressed 를 방출한다(= 사용자가 탭을 누르는 것과 같은 경로).
	var pressed := 0
	for round_i in 3:
		var btns := _buttons(ml)
		if btns.is_empty():
			break
		# 매 라운드 다른 탭을 눌러 재빌드를 반복시킨다.
		var b: Button = btns[round_i % btns.size()]
		b.emit_signal("pressed")
		pressed += 1
		await get_tree().process_frame
		await get_tree().process_frame
	# ⚠️ 이 문구에 판정용 검색어를 넣지 말 것 — grep 이 자기 자신을 세어 오탐이 난다(실제로 겪었다).
	print("탭 버튼 pressed 방출 %d회 — 위에 시그널 방출 중 해제 에러가 없으면 통과" % pressed)
	get_tree().quit(0 if pressed > 0 else 1)


func _buttons(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Button:
			out.append(c)
		out += _buttons(c)
	return out
