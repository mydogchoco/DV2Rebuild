class_name CritCutin
extends RefCounted

const LETTER := {
	"earth": "e", "aqua": "a", "fire": "f", "wind": "w", "light": "l",
	"dark": "d", "holy": "h", "chaos": "c", "shadow": "s",
}
const T := 0.1
const T2 := 0.05
const VOICE_DELAY := T2
const HOLD := 0.4
const BAND_HOLD := 0.5
const TOTAL := T + HOLD + T + 0.05
const BANNER_Y := 0.3

static func _man(dir: String) -> Dictionary:
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

static func _spr(dir: String, name: String, scale := 1.0) -> Sprite2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if not ResourceLoader.exists(p):
		return null
	var s := Sprite2D.new()
	s.texture = load(p)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	s.material = m
	s.scale = Vector2(scale, scale)
	return s

static func show(host: Node, caster: Dictionary, speed := 1.0, banner := "", layer_idx := 40) -> float:
	if not is_instance_valid(host) or not host.is_inside_tree():
		return 0.0
	var elem := String(caster.get("element", ""))
	var letter: String = LETTER.get(elem, "f")
	var bdir := "cut_in_%s" % letter
	var vis: Vector2 = host.get_viewport().get_visible_rect().size
	var sp := 1.0 / maxf(1.0 / 3.0, speed)
	var lay := CanvasLayer.new(); lay.layer = layer_idx
	host.add_child(lay)
	var center := vis * 0.5

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.size = vis
	dim.z_index = -1
	lay.add_child(dim)
	var dt := dim.create_tween()
	dt.tween_property(dim, "color:a", 150.0 / 255.0, T * sp)
	dt.tween_interval(HOLD * sp)
	dt.tween_property(dim, "color:a", 0.0, T * sp)

	var band := Sprite2D.new()
	var bp := "res://assets/converted/%s/dragon_cut_in_%s_bg_cut1.tres" % [bdir, letter]
	if ResourceLoader.exists(bp):
		band.texture = load(bp)
		band.position = center
		var s := vis.x / 576.0
		band.scale = Vector2.ONE
		lay.add_child(band)
		var frame := 1
		var ticker := Timer.new(); ticker.wait_time = 0.07 * sp; ticker.autostart = true
		ticker.timeout.connect(func():
			frame = frame % 3 + 1
			var fp := "res://assets/converted/%s/dragon_cut_in_%s_bg_cut%d.tres" % [bdir, letter, frame]
			if is_instance_valid(band) and ResourceLoader.exists(fp): band.texture = load(fp))
		lay.add_child(ticker)
		var bs := band.create_tween()
		bs.tween_property(band, "scale", Vector2(s, s * 1.05), T * sp)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var bf := band.create_tween()
		bf.tween_interval(BAND_HOLD * sp)
		bf.tween_property(band, "modulate:a", 100.0 / 255.0, T2 * sp)
		bf.tween_property(band, "modulate:a", 0.0, T * sp)
		bf.parallel().tween_property(band, "position:x", center.x - vis.x, T * sp)

	var cid := int(caster.get("id", 0))
	var cman := _man("critical_%d" % cid)
	var key := "dragon_dragon_%d_critical_cut_in" % cid
	if bool(caster.get("awakened", false)):
		var ekey := "dragon_dragon_%d_critical_e_cut_in" % cid
		if cman.has(ekey):
			key = ekey
	var cs := vis.x / 576.0
	var face := _spr("critical_%d" % cid, key, cs)
	if face == null:
		face = _spr("critical_1", "dragon_dragon_1_critical_cut_in", cs)
	if face:
		var fw: float = face.texture.get_width() * cs if face.texture else vis.x * 0.5
		face.position = Vector2(center.x + fw * 0.5, center.y)
		face.modulate.a = 0.0
		face.z_index = 5
		lay.add_child(face)
		var ft := face.create_tween().set_parallel(true)
		ft.tween_property(face, "modulate:a", 1.0, T * sp)
		ft.tween_property(face, "position", center, T * sp)

	if banner != "":
		var bl := Label.new()
		bl.text = banner
		var fpath := "res://assets/converted/font_ui/font_title.fnt"
		if ResourceLoader.exists(fpath):
			var bf: FontFile = load(fpath).duplicate()
			bf.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
			var ok := true
			for ch in banner:
				if ch != " " and not bf.has_char(ch.unicode_at(0)):
					ok = false
					break
			if ok:
				bl.add_theme_font_override("font", bf)
		bl.add_theme_font_size_override("font_size", 48)
		bl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.4))
		bl.add_theme_color_override("font_outline_color", Color(0.45, 0.1, 0.35, 1.0))
		bl.add_theme_constant_override("outline_size", 12)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bl.size = Vector2(vis.x, 90.0)
		bl.position = Vector2(0.0, vis.y * BANNER_Y - bl.size.y * 0.5)
		bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bl.z_index = 10
		bl.modulate.a = 0.0
		bl.scale = Vector2(0.6, 0.6)
		bl.pivot_offset = bl.size * 0.5
		lay.add_child(bl)
		var lt := bl.create_tween().set_parallel(true)
		lt.tween_property(bl, "modulate:a", 1.0, T * 2.0 * sp)
		lt.tween_property(bl, "scale", Vector2.ONE, T * 2.5 * sp)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	Bgm.sfx("effect_cut_in")
	var done := lay.create_tween()
	done.tween_interval(TOTAL * sp)
	done.tween_callback(func(): if is_instance_valid(lay): lay.queue_free())
	return TOTAL * sp
