extends SceneTree
# 모든 assets/converted/monster_*/monster.json → scenes/monsters/monster_N.tscn (1세션 배치).
# Run: godot --headless --script res://scripts/tools/build_monsters.gd
const Builder = preload("res://scripts/tools/build_spine_scene.gd")
func _initialize() -> void:
	var built := 0
	var da := DirAccess.open("res://assets/converted")
	for sub in da.get_directories():
		if not sub.begins_with("monster_"):
			continue
		var jp := "res://assets/converted/%s/monster.json" % sub
		if not FileAccess.file_exists(jp):
			continue
		var out_path := "res://scenes/monsters/%s.tscn" % sub
		if Builder.build_one(jp, out_path) == OK:
			built += 1
	print("built %d monster scenes" % built)
	quit(0)
