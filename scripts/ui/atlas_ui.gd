class_name AtlasUI

static var _mans: Dictionary = {}

static func manifest(dir: String) -> Dictionary:
	if _mans.has(dir):
		return _mans[dir]
	var p := "res://assets/converted/%s/_manifest.json" % dir
	var d := {}
	if FileAccess.file_exists(p):
		var f := FileAccess.open(p, FileAccess.READ)
		var j = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			d = j
	_mans[dir] = d
	return d

static func tex(dir: String, key: String) -> Texture2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	return load(p) if ResourceLoader.exists(p) else null

static func spr(dir: String, key: String, scale := 1.0) -> Sprite2D:
	var t := tex(dir, key)
	if t == null:
		return null
	var s := Sprite2D.new()
	s.texture = t
	s.material = pma()
	s.scale = Vector2(scale, scale)
	return s

static func spr_cocos(dir: String, key: String, scale := 1.0,
		anchor := Vector2(0.5, 0.5)) -> Node2D:
	var t := tex(dir, key)
	if t == null:
		return null
	var S := Design.ASSET_SCALE
	var info: Dictionary = manifest(dir).get(key, {})
	var src: Array = info.get("src", [float(info.get("w", t.get_width())),
		float(info.get("h", t.get_height()))])
	var off: Array = info.get("off", [0, 0])
	var w := float(src[0]) * S
	var h := float(src[1]) * S
	var holder := Node2D.new()
	holder.scale = Vector2(scale, scale)
	var s := Sprite2D.new()
	s.texture = t
	s.material = pma()
	s.scale = Vector2(S, S)
	s.position = Vector2((0.5 - anchor.x) * w + float(off[0]) * S,
		(anchor.y - 0.5) * h - float(off[1]) * S)
	holder.add_child(s)
	return holder

static func size_pt(dir: String, key: String) -> Vector2:
	var i: Dictionary = manifest(dir).get(key, {})
	return Vector2(float(i.get("w", 0)), float(i.get("h", 0))) * Design.ASSET_SCALE

static func src_pt(dir: String, key: String) -> Vector2:
	var i: Dictionary = manifest(dir).get(key, {})
	var src: Array = i.get("src", [float(i.get("w", 0)), float(i.get("h", 0))])
	return Vector2(float(src[0]), float(src[1])) * Design.ASSET_SCALE

static var _pma_shared: CanvasItemMaterial = null
static func pma() -> CanvasItemMaterial:
	if _pma_shared == null:
		_pma_shared = CanvasItemMaterial.new()
		_pma_shared.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	return _pma_shared

static func nine(dir: String, key: String, sz_pt: Vector2, cap := Rect2()) -> NinePatchRect:
	var t := tex(dir, key)
	if t == null:
		return null
	var inv := 1.0 / Design.ASSET_SCALE
	var l := cap.position.x
	var tp := cap.position.y
	var cw := cap.size.x
	var ch := cap.size.y
	if cap.size == Vector2.ZERO:
		l = t.get_width() / 3.0
		tp = t.get_height() / 3.0
		cw = t.get_width() / 3.0
		ch = t.get_height() / 3.0
	var np := NinePatchRect.new()
	np.texture = t
	np.patch_margin_left = int(round(l))
	np.patch_margin_top = int(round(tp))
	np.patch_margin_right = int(round(maxf(0.0, t.get_width() - l - cw)))
	np.patch_margin_bottom = int(round(maxf(0.0, t.get_height() - tp - ch)))
	np.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	np.size = sz_pt * inv
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return np

const BTN_CAP := Rect2(20, 20, 4, 4)
const BTN_FRAME := {0: "9patch_btn", 1: "9patch_btn2", 2: "9patch_btn3", 4: "9patch_btn6",
	5: "9patch_btn8", 7: "9patch_btn10", 8: "9patch_btn11"}

static func frame_button(parent: Node, text: String, pos: Vector2, sz: Vector2, cb: Callable,
		kind := 0, disabled := false, font_size := 18) -> Control:
	var root := Control.new()
	root.size = sz
	root.position = pos
	parent.add_child(root)
	var np := nine("ninepatch_ui", String(BTN_FRAME.get(kind, "9patch_btn4")), sz, BTN_CAP)
	if np != null:
		root.add_child(np)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.04, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = sz
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	var b := Button.new()
	b.flat = true
	b.size = sz
	b.disabled = disabled
	b.pressed.connect(cb)
	root.add_child(b)
	if disabled:
		root.modulate = Color(0.62, 0.62, 0.62)
	return root

static func npc_emotions(npc: String) -> Array:
	var man := manifest("npc_%s" % npc)
	var out: Array = []
	var pre := "npc_%s_eye_" % npc
	var bpre := "npc_%s_body_" % npc
	var alt_bodies: Array = []
	for k in man.keys():
		var key := String(k)
		if key.begins_with(bpre):
			var b := key.substr(bpre.length())
			if b.is_valid_int() and int(b) != 1:
				alt_bodies.append(int(b))
	for k in man.keys():
		var key := String(k)
		if not key.begins_with(pre):
			continue
		var e := key.substr(pre.length()).split("_")[0]
		if not e.is_valid_int():
			continue
		var ei := int(e)
		if alt_bodies.has(ei) or out.has(ei):
			continue
		out.append(ei)
	out.sort()
	if out.is_empty():
		out.append(1)
	return out

static func npc_emotions_for(npc: String, allowed: Array) -> Array:
	var have := npc_emotions(npc)
	if allowed.is_empty():
		return have
	var out: Array = []
	for e in allowed:
		if have.has(int(e)):
			out.append(int(e))
	return out if not out.is_empty() else have

static func comma(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out
