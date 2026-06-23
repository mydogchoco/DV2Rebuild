extends SceneTree
# Build a Godot scene from a spine_export intermediate JSON (4b converter, step 3).
# Standalone: godot --headless --script res://scripts/tools/build_spine_scene.gd -- <in.json> <out.tscn>
# Reusable:   Builder.build_one(in_path, out_path)  (see build_all.gd)

const ROT_FIX := PI / 2.0  # atlas rotate=true compensation (verified on dragon_1)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- <in.json> <out.tscn>"); quit(1); return
	quit(0 if build_one(args[0], args[1]) == OK else 1)

static func build_one(in_path: String, out_path: String) -> int:
	var f := FileAccess.open(in_path, FileAccess.READ)
	if f == null:
		push_error("cannot open %s" % in_path); return ERR_FILE_CANT_OPEN
	var data: Dictionary = JSON.parse_string(f.get_as_text())

	var root := Node2D.new()
	root.name = "Dragon_%s_%s" % [str(data.get("id")), str(data.get("stage"))]

	# --- bones ---
	var bone_node := {}
	var bone_path := {}
	for b in data["bones"]:
		var n := Node2D.new()
		n.name = String(b["name"])
		n.position = Vector2(b["pos"][0], b["pos"][1])
		n.rotation = float(b["rot"])
		n.scale = Vector2(b["scale"][0], b["scale"][1])
		bone_node[b["name"]] = n
	for b in data["bones"]:
		var n: Node2D = bone_node[b["name"]]
		var parent = b.get("parent")
		if parent != null and bone_node.has(parent):
			bone_node[parent].add_child(n)
		else:
			root.add_child(n)
	for b in data["bones"]:
		bone_path[b["name"]] = root.get_path_to(bone_node[b["name"]])

	# --- slots (sprites) ---
	var tex_cache := {}
	for s in data["slots"]:
		var parent_node: Node2D = bone_node.get(s["bone"], root)
		var frame := Node2D.new()
		frame.name = "%s_frame" % String(s["name"])
		frame.position = Vector2(s["frame_pos"][0], s["frame_pos"][1])
		frame.rotation = float(s["frame_rot"])
		frame.scale = Vector2(s["frame_scale"][0], s["frame_scale"][1])
		parent_node.add_child(frame)

		var spr := Sprite2D.new()
		spr.name = String(s["name"])
		spr.z_index = int(s["z"])
		spr.position = Vector2(s["sprite_pos"][0], s["sprite_pos"][1])
		spr.scale = Vector2(s["sprite_scale"][0], s["sprite_scale"][1])
		if bool(s["rotated"]):
			spr.rotation = ROT_FIX
		var png: String = s["png"]
		if not tex_cache.has(png):
			tex_cache[png] = load(png)
		var at := AtlasTexture.new()
		at.atlas = tex_cache[png]
		var rr = s["region_rect"]
		at.region = Rect2(rr[0], rr[1], rr[2], rr[3])
		spr.texture = at
		frame.add_child(spr)

	_set_owner_recursive(root, root)

	# --- animations ---
	if not data.get("animations", {}).is_empty():
		var ap := AnimationPlayer.new()
		ap.name = "AnimationPlayer"
		root.add_child(ap)
		ap.owner = root
		var lib := AnimationLibrary.new()
		for an_name in data["animations"]:
			var an_data = data["animations"][an_name]
			var anim := Animation.new()
			anim.length = maxf(0.001, float(an_data["length"]))
			anim.loop_mode = Animation.LOOP_LINEAR
			for bone_name in an_data["tracks"]:
				var bt = an_data["tracks"][bone_name]
				var bp: String = str(bone_path[bone_name])
				for prop in bt:
					var ti := anim.add_track(Animation.TYPE_VALUE)
					anim.track_set_path(ti, "%s:%s" % [bp, prop])
					anim.value_track_set_update_mode(ti, Animation.UPDATE_CONTINUOUS)
					anim.track_set_interpolation_type(ti, Animation.INTERPOLATION_LINEAR)
					var keys: Array = bt[prop]
					for ki in keys.size():
						var key = keys[ki]
						var t: float = float(key[0])
						var v = (float(key[1]) if prop == "rotation"
								 else Vector2(key[1][0], key[1][1]))
						anim.track_insert_key(ti, t, v)
						var curve := (String(key[2]) if key.size() > 2 else "L")
						if curve == "S" and ki + 1 < keys.size():
							var tnext: float = float(keys[ki + 1][0])
							if tnext > t + 0.0002:
								anim.track_insert_key(ti, tnext - 0.0001, v)
			lib.add_animation(an_name, anim)
		ap.add_animation_library("", lib)

	# --- save ---
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("pack failed"); return ERR_BUG
	var err := ResourceSaver.save(packed, out_path)
	print("save %s -> %s" % [out_path, "OK" if err == OK else str(err)])
	return err

static func _set_owner_recursive(node: Node, owner: Node) -> void:
	for c in node.get_children():
		if c != owner:
			c.owner = owner
		_set_owner_recursive(c, owner)
