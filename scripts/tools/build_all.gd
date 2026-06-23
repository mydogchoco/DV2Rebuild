extends SceneTree
# Build .tscn for every intermediate JSON under assets/converted/dragon_*/.
# Run: godot --headless --script res://scripts/tools/build_all.gd
const Builder = preload("res://scripts/tools/build_spine_scene.gd")

func _initialize() -> void:
	var built := 0
	var root_dir := "res://assets/converted"
	var da := DirAccess.open(root_dir)
	if da == null:
		push_error("no " + root_dir); quit(1); return
	for sub in da.get_directories():
		var d2 := DirAccess.open("%s/%s" % [root_dir, sub])
		for fn in d2.get_files():
			if fn.ends_with(".json"):
				var in_path := "%s/%s/%s" % [root_dir, sub, fn]
				var out_path := "res://scenes/dragons/%s_%s.tscn" % [sub, fn.get_basename()]
				if Builder.build_one(in_path, out_path) == OK:
					built += 1
	print("built %d scenes" % built)
	quit(0)
