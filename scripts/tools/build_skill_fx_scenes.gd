extends SceneTree
const Builder = preload("res://scripts/tools/build_spine_scene.gd")

func _initialize() -> void:
	var built := 0
	var root_dir := "res://assets/converted"
	var da := DirAccess.open(root_dir)
	if da == null:
		push_error("no " + root_dir); quit(1); return
	DirAccess.make_dir_recursive_absolute("res://scenes/fx")
	for sub in da.get_directories():
		if not sub.begins_with("scenespine_skill_"):
			continue
		var d2 := DirAccess.open("%s/%s" % [root_dir, sub])
		if d2 == null: continue
		for fn in d2.get_files():
			if fn.ends_with(".json") and not fn.begins_with("_"):
				var in_path := "%s/%s/%s" % [root_dir, sub, fn]
				var name := sub.substr("scenespine_".length())
				var out_path := "res://scenes/fx/%s.tscn" % name
				if Builder.build_one(in_path, out_path) == OK:
					built += 1
	print("built %d skill fx scenes" % built)
	quit(0)
