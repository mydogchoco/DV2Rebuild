extends SceneTree
# Lay several converted dragon scenes in a grid and screenshot (visual QA).
# Run (NOT headless): godot --path . --script res://scripts/tools/montage.gd -- <out.png> <scene1> <scene2> ...

var _frames := 0
var _out: String

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	_out = a[0]
	var scenes := a.slice(1)

	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.18, 0.22)
	bg.size = Vector2(1920, 1080)
	get_root().add_child(bg)

	var cols := 4
	var cw := 1920.0 / cols
	var ch := 360.0
	for i in scenes.size():
		var ps: PackedScene = load(scenes[i])
		if ps == null:
			continue
		var inst := ps.instantiate()
		var holder := Node2D.new()
		var col := i % cols
		var row := i / cols
		holder.position = Vector2(col * cw + cw / 2.0, row * ch + ch * 0.78)
		holder.scale = Vector2(1.4, 1.4)
		holder.add_child(inst)
		get_root().add_child(holder)
		var ap := inst.get_node_or_null("AnimationPlayer")
		if ap and ap.has_animation("wait"):
			ap.play("wait")
		var lbl := Label.new()
		lbl.text = scenes[i].get_file().get_basename()
		lbl.position = Vector2(col * cw + 8, row * ch + 8)
		get_root().add_child(lbl)

	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frames += 1
	if _frames == 6:
		get_root().get_texture().get_image().save_png(_out)
		print("montage saved: ", _out)
		quit(0)
