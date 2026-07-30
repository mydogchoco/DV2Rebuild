extends Control
## 편성창 육안 확인용 — 영웅 난이도(3마리)로 탐험에 바로 진입시킨다.
## Run: godot --path . res://scenes/dev_party_select.tscn
func _ready() -> void:
	NewGame.ensure(UserDB, Data.new_game_def())
	var root := Control.new()
	root.name = "SceneRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	Scenes.bind_root(root)
	Scenes.goto("worldmap", {})
	await get_tree().process_frame
	# 영웅 = 3마리 단계 → 입장 직후 편성창이 뜬다.
	Scenes.goto("adventure", {"stage": "1", "region": "yutakan", "hero": true})
