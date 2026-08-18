class_name DungeonBG
extends RefCounted

const DIR := "res://assets/converted/adventure_bg"
const OVL_CANVAS := Vector2(768.0, 520.0)
const OVL_SCALE := 2.0

static var _man: Dictionary = {}

static func _manifest() -> Dictionary:
	if _man.is_empty():
		var f := FileAccess.open(DIR + "/_manifest.json", FileAccess.READ)
		if f:
			var j = JSON.parse_string(f.get_as_text())
			if typeof(j) == TYPE_DICTIONARY:
				_man = j
	return _man

static func variant_field(base: int, night: bool, kades: bool) -> int:
	if base < 1 or base > 14 or base == 6 or base == 8:
		return base
	if kades:
		return 600 + base
	if night:
		return 500 + base
	return base

static func base_field(fid: int) -> int:
	if fid >= 600 and fid < 700:
		return fid - 600
	if fid >= 500 and fid < 600:
		return fid - 500
	return fid

static func variant_of(fid: int) -> String:
	if fid >= 600 and fid < 700:
		return "kades"
	if fid >= 500 and fid < 600:
		return "night"
	return ""

static func field_id(stage: Dictionary) -> int:
	for k in ["bg", "id"]:
		var v = stage.get(k, null)
		if v != null and int(v) > 0:
			return int(v)
	return 0

static func path_for(stage: Dictionary) -> String:
	var fid := field_id(stage)
	if fid <= 0:
		return ""
	var p := "%s/bg_%d.jpg" % [DIR, fid]
	return p if ResourceLoader.exists(p) else ""

static func overlay_path_for(stage: Dictionary) -> String:
	var fid := field_id(stage)
	if fid <= 0:
		return ""
	var p := "%s/bg_%d_item.tres" % [DIR, fid]
	return p if ResourceLoader.exists(p) else ""

static func build(parent: Node, stage: Dictionary) -> TextureRect:
	var p := path_for(stage)
	if p == "":
		return null
	var bg := TextureRect.new()
	bg.texture = load(p)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	add_overlay(bg, stage)
	return bg

static func add_overlay(bg: Control, stage: Dictionary) -> void:
	var op := overlay_path_for(stage)
	if op == "":
		return
	var key := "bg_%d_item" % field_id(stage)
	var e: Dictionary = _manifest().get(key, {})
	if e.is_empty():
		return
	var off: Array = e.get("off", [0, 0])
	var w := float(e.get("w", 0)) * OVL_SCALE
	var h := float(e.get("h", 0)) * OVL_SCALE
	if w <= 0.0 or h <= 0.0:
		return
	var cx := 0.5 + float(off[0]) * OVL_SCALE / OVL_CANVAS.x
	var cy := 0.5 - float(off[1]) * OVL_SCALE / OVL_CANVAS.y
	var ovl := TextureRect.new()
	ovl.texture = load(op)
	ovl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ovl.stretch_mode = TextureRect.STRETCH_SCALE
	ovl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ovl.anchor_left = cx - w * 0.5 / OVL_CANVAS.x
	ovl.anchor_right = cx + w * 0.5 / OVL_CANVAS.x
	ovl.anchor_top = cy - h * 0.5 / OVL_CANVAS.y
	ovl.anchor_bottom = cy + h * 0.5 / OVL_CANVAS.y
	ovl.offset_left = 0.0; ovl.offset_right = 0.0
	ovl.offset_top = 0.0; ovl.offset_bottom = 0.0
	bg.add_child(ovl)
