extends Object
class_name WordArt

const SECS := 1.9
const FONT := "res://assets/converted/font_ui/font_title.fnt"

static func burst(host: Node, text: String, vis: Vector2, z := 195,
		rise := 100.0, fade_out := false) -> Label:
	var lb := Label.new()
	lb.text = text
	if ResourceLoader.exists(FONT):
		var fnt: FontFile = load(FONT)
		lb.add_theme_font_override("font", fnt)
		lb.add_theme_font_size_override("font_size",
			int(fnt.fixed_size) if fnt.fixed_size > 0 else 39)
	else:
		lb.add_theme_font_size_override("font_size", 34)
		lb.add_theme_color_override("font_color", Color(1, 0.9, 0.45))
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.size = Vector2(vis.x, 60)
	lb.position = Vector2(0, vis.y * 0.3 - 30.0)
	lb.pivot_offset = Vector2(vis.x * 0.5, 30.0)
	lb.z_index = z
	lb.scale = Vector2.ZERO
	host.add_child(lb)
	var t := lb.create_tween()
	t.tween_property(lb, "scale", Vector2(1.7, 1.7), 0.4)
	t.parallel().tween_property(lb, "rotation_degrees", 380.0, 0.2)
	t.tween_property(lb, "rotation_degrees", -30.0, 0.13333334)
	t.tween_property(lb, "rotation_degrees", 15.0, 0.13333334)
	t.tween_property(lb, "rotation_degrees", -5.0, 0.13333334)
	t.tween_property(lb, "scale", Vector2(1.2, 1.2), 0.1)
	t.parallel().tween_property(lb, "rotation_degrees", 0.0, 0.1)
	t.tween_interval(0.7)
	t.tween_property(lb, "position", lb.position - Vector2(0, rise), 0.2)
	if fade_out:
		t.parallel().tween_property(lb, "modulate:a", 0.0, 0.2)
		t.tween_callback(lb.queue_free)
	return lb
