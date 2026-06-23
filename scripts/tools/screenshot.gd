extends SceneTree
# Render a scene to a PNG for visual verification.
# Run (NOT headless): godot --path . --script res://scripts/tools/screenshot.gd -- <scene.tscn> <out.png> [scale]

var _frames := 0
var _out: String

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var scene_path: String = a[0]
	_out = a[1]
	var raw := a.size() > 2 and a[2] == "raw"   # raw: full scene as-is (no bg/reposition)
	var scl: float = float(a[2]) if (a.size() > 2 and not raw) else 2.0

	if not raw:
		var bg := ColorRect.new()
		bg.color = Color(0.18, 0.20, 0.25)
		bg.size = Vector2(1920, 1080)
		get_root().add_child(bg)

	var ps: PackedScene = load(scene_path)
	var inst := ps.instantiate()
	get_root().add_child(inst)
	if inst is Node2D and not raw:
		(inst as Node2D).position = Vector2(960, 780)
		(inst as Node2D).scale = Vector2(scl, scl)
	var ap := inst.get_node_or_null("AnimationPlayer")
	if ap and ap.get_animation_list().size() > 0:
		ap.play("wait" if ap.has_animation("wait") else ap.get_animation_list()[0])

	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frames += 1
	if _frames == 6:
		var img := get_root().get_texture().get_image()
		img.save_png(_out)
		print("screenshot saved: ", _out)
		quit(0)
