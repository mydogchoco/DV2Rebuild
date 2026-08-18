class_name EggResultView
extends CanvasLayer

signal closed

const PW := 520.0
const PH := 440.0
const LAYER_Z := 70

const BACKLIGHT_TURN := 14.0

static func open(host: Node, did: int, used := "", msg := "", opts := {}) -> EggResultView:
	var p := EggResultView.new()
	p.layer = LAYER_Z
	host.add_child(p)
	p._build(did, used, msg, opts)
	return p

func _build(did: int, used_key: String, msg: String, opts: Dictionary = {}) -> void:
	var d: Dictionary = Data.get_dragon(did)
	var vis := get_viewport().get_visible_rect().size

	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_recall_del.tres")
	win.patch_margin_left = 40; win.patch_margin_right = 40
	win.patch_margin_top = 40; win.patch_margin_bottom = 40
	win.size = Vector2(PW, PH)
	win.position = Vector2((vis.x - PW) * 0.5, (vis.y - PH) * 0.5)
	add_child(win)

	var back := AtlasUI.spr("common_ui", "common_backlight3", 1.0)
	if back:
		back.position = Vector2(PW * 0.5, 170.0)
		back.modulate = Color(1, 1, 1, 0.85)
		win.add_child(back)
		back.create_tween().set_loops().tween_property(
			back, "rotation", TAU, BACKLIGHT_TURN).from(0.0)

	var art := int(opts.get("art_id", did))
	var eggspr := AtlasUI.spr("portrait_%d" % art, "dragon_dragon_%d_egg" % art, 1.5)
	if eggspr == null and art != did:
		eggspr = AtlasUI.spr("portrait_%d" % did, "dragon_dragon_%d_egg" % did, 1.5)
	if eggspr:
		eggspr.position = Vector2(PW * 0.5, 170.0)
		win.add_child(eggspr)

	var name_l := Label.new()
	name_l.text = _str(opts.get("name"), _str(d.get("name"), "드래곤 %d" % did))
	name_l.add_theme_font_size_override("font_size", 30)
	name_l.add_theme_color_override("font_color", Color(1, 0.95, 0.82))
	name_l.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02, 0.95))
	name_l.add_theme_constant_override("outline_size", 5)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.size = Vector2(PW, 38); name_l.position = Vector2(0, 262)
	win.add_child(name_l)

	var star := int(d.get("star", 0))
	var sw := 26.0
	var x0 := PW * 0.5 - (float(star) * sw) * 0.5
	for i in star:
		var st := AtlasUI.spr("common_ui", "common_eggclass", 0.9)
		if st:
			st.position = Vector2(x0 + float(i) * sw + sw * 0.5, 316.0)
			win.add_child(st)
	var ele := _ele_frame(_str(opts.get("element"), _str(d.get("element"), "")))
	var es := AtlasUI.spr("item_small_ui", "item_item_small_ele_%s" % ele, 1.0) if ele != "" else null
	if es:
		es.position = Vector2(x0 - 34.0, 316.0)
		win.add_child(es)

	var sub := Label.new()
	if msg != "":
		sub.text = msg
	else:
		var used := Data.item_name(used_key) if used_key != "" else "알"
		sub.text = "%s을 사용하여 %s의 알을 획득하였습니다." % [used, _str(d.get("name"), "드래곤")]
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size = Vector2(PW, 24); sub.position = Vector2(0, 344)
	win.add_child(sub)

	var ok := AtlasUI.spr("common_ui", "common_check_btn", 1.0)
	if ok:
		ok.position = Vector2(PW * 0.5, PH - 52.0)
		win.add_child(ok)
	var okb := Button.new(); okb.flat = true
	okb.size = Vector2(150, 60); okb.position = Vector2((PW - 150) * 0.5, PH - 82.0)
	okb.pressed.connect(func():
		closed.emit()
		queue_free())
	win.add_child(okb)

static func _str(v, fallback: String) -> String:
	return String(v) if typeof(v) == TYPE_STRING and String(v) != "" else fallback

static func _ele_frame(element: String) -> String:
	match element:
		"earth": return "ground"
		"aqua": return "water"
		_: return element
