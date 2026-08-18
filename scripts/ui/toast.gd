class_name Toast
extends RefCounted

const BOX := "res://assets/converted/ninepatch_ui/9patch_box1.tres"
const FONT := "res://assets/converted/font_ui/font_common.fnt"
const BOX_FRAME := 38.0
const H := 60.0
const ALPHA := 150.0 / 255.0
const FADE_IN := 0.2
const HOLD := 0.7
const FADE_OUT := 0.2
const WIDTH_RATIO := 0.6
const TEXT_PAD := 20.0
const LAYER := 40

static func show(host: Node, text: String, hold := HOLD) -> void:
	if host == null or not is_instance_valid(host) or text == "":
		return
	for c in host.get_children():
		if c is CanvasLayer and c.name == "ToastLayer" and not c.is_queued_for_deletion():
			c.queue_free()
	var vis: Vector2 = host.get_viewport().get_visible_rect().size

	var lay := CanvasLayer.new()
	lay.name = "ToastLayer"
	lay.layer = LAYER
	host.add_child(lay)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lay.add_child(root)

	var l := Label.new()
	l.text = text
	var f: Font = load(FONT) if ResourceLoader.exists(FONT) else null
	if f:
		if f is FontFile:
			(f as FontFile).fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var tw := 0.0
	var lf := l.get_theme_font("font")
	if lf:
		tw = lf.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			l.get_theme_font_size("font_size")).x
	var w := maxf(vis.x * WIDTH_RATIO, tw + TEXT_PAD)

	var np := NinePatchRect.new()
	np.texture = load(BOX)
	np.patch_margin_left = 20
	np.patch_margin_top = 20
	np.patch_margin_right = int(BOX_FRAME) - 30
	np.patch_margin_bottom = int(BOX_FRAME) - 30
	np.size = Vector2(w, H)
	np.position = Vector2(round((vis.x - w) * 0.5), round((vis.y - H) * 0.5))
	np.self_modulate = Color(0, 0, 0, ALPHA)
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(np)

	l.size = Vector2(w, H)
	l.position = Vector2(0, -5.0)
	np.add_child(l)

	root.modulate.a = 0.0
	var t := root.create_tween()
	t.tween_property(root, "modulate:a", 1.0, FADE_IN)
	t.tween_interval(hold)
	t.tween_property(root, "modulate:a", 0.0, FADE_OUT)
	t.tween_callback(lay.queue_free)
