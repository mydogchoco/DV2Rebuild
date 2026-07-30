extends SceneTree
# 스킬 이펙트 스파인을 격자로 깔아 한 장에 담는다(육안 검수용).
# godot --headless(X) 불가 — 렌더가 필요하므로 창 모드로: godot --script ... --quit-after 400
func _initialize() -> void:
	var root := Node2D.new()
	get_root().add_child(root)
	var ids := []
	var da := DirAccess.open("res://scenes/fx")
	for f in da.get_files():
		if f.begins_with("skill_") and f.ends_with(".tscn"):
			ids.append(f)
	ids.sort()
	var cols := 8
	var i := 0
	for f in ids:
		var holder := Node2D.new()
		holder.position = Vector2(90 + (i % cols) * 160, 90 + (i / cols) * 150)
		holder.scale = Vector2(0.35, 0.35)
		root.add_child(holder)
		var inst = (load("res://scenes/fx/" + f) as PackedScene).instantiate()
		holder.add_child(inst)
		var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		if ap and ap.has_animation("animation"):
			ap.play("animation")
			ap.seek(0.25, true)
		var lb := Label.new()
		lb.text = f.replace("skill_", "").replace("_spine.tscn", "")
		lb.position = Vector2(60 + (i % cols) * 160, 20 + (i / cols) * 150)
		root.add_child(lb)
		i += 1
	await process_frame
	await process_frame
	await create_timer(0.6).timeout
	var img := get_root().get_texture().get_image()
	img.save_png("scratch_shots/skillfx_grid.png")
	print("SHOT ok ", ids.size())
	quit(0)
