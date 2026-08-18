class_name DragonPicker
extends RefCounted

const CELL := Vector2(320.0, 461.0)
const BOX_H := 481.0
const WIN_H := 600.0
const FONT_SUB := "res://assets/converted/font_ui/font_subtitle.fnt"

static func open(host: Node, title: String, uids: Array, disabled: Array,
		on_pick: Callable) -> CanvasLayer:
	var rows: Array = []
	for u in uids:
		rows.append({"uid": int(u), "off": disabled.has(int(u))})
	return _shell(host, title, rows, on_pick, _fill_dragon_cell)

static func _shell(host: Node, title: String, rows: Array, on_pick: Callable,
		fill: Callable) -> CanvasLayer:
	var vis: Vector2 = host.get_viewport().get_visible_rect().size
	var lay := CanvasLayer.new()
	lay.layer = 40
	host.add_child(lay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	lay.add_child(dim)

	var bw := vis.x - 50.0
	var bh := WIN_H
	var org := Vector2(round((vis.x - bw) * 0.5), round((vis.y - bh) * 0.5))
	var win := AtlasUI.nine("ninepatch_ui", "9patch_popup4", Vector2(bw, bh),
		Rect2(130, 190, 40, 58))
	if win != null:
		win.position = org
		lay.add_child(win)

	var t := bmf(title, 26)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size = Vector2(bw, 34.0)
	t.position = org + Vector2(0.0, 45.0 - 17.0)
	lay.add_child(t)

	var box_h := minf(BOX_H, bh - 100.0)
	var box := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", Vector2(bw - 100.0, box_h),
		Rect2(65, 65, 6, 6))
	if box != null:
		box.position = org + Vector2(50.0, bh - 40.0 - box_h)
		lay.add_child(box)

	var scroll := ScrollContainer.new()
	scroll.position = org + Vector2(60.0, bh - 30.0 - box_h)
	scroll.size = Vector2(bw - 120.0, box_h - 20.0)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	lay.add_child(scroll)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 12)
	scroll.add_child(strip)

	var ch := minf(CELL.y, scroll.size.y - 8.0)
	for r in rows:
		strip.add_child(_cell(r, Vector2(CELL.x, ch), fill, func(v):
			lay.queue_free()
			on_pick.call(v)))

	var xs := AtlasUI.spr("common_ui", "common_close_btn", Design.ASSET_SCALE * 1.5)
	if xs != null:
		xs.position = org + Vector2(bw - 50.0, 50.0)
		lay.add_child(xs)
	var xb := Button.new()
	xb.flat = true
	xb.size = Vector2(60, 60)
	xb.position = org + Vector2(bw - 80.0, 20.0)
	xb.pressed.connect(func():
		Bgm.sfx("effect_button")
		lay.queue_free())
	lay.add_child(xb)
	return lay

static func _cell(row: Dictionary, sz: Vector2, fill: Callable, on_pick: Callable) -> Control:
	var card := Control.new()
	card.custom_minimum_size = sz
	card.clip_contents = true
	var bg := AtlasUI.nine("ninepatch_ui", "9patch_train_box4", sz, Rect2())
	if bg != null:
		card.add_child(bg)
	fill.call(card, row, sz)
	var off := bool(row.get("off", false))
	if off:
		card.modulate = Color(0.45, 0.45, 0.45, 1.0)
		return card
	var b := Button.new()
	b.flat = true
	b.size = sz
	var v = row.get("value", row.get("uid", 0))
	b.pressed.connect(func():
		Bgm.sfx("effect_button")
		on_pick.call(v))
	card.add_child(b)
	return card

static func _fill_dragon_cell(card: Control, row: Dictionary, sz: Vector2) -> void:
	var uid := int(row.get("uid", 0))
	var d: Dictionary = UserDB.get_dragon(uid)
	if d.is_empty():
		return
	var ddef: Dictionary = Data.get_dragon(int(d.get("id", 0)))
	var S := Design.ASSET_SCALE
	var cy := sz.y * 0.5

	var feet := Vector2(sz.x * 0.5, sz.y - (cy + 30.0))
	var sh := AtlasUI.spr("common_ui", "common_shadow", S)
	if sh != null:
		sh.position = feet
		sh.modulate = Color(1, 1, 1, 0.55)
		card.add_child(sh)
	var sp := PartySelect._spine_node(Icons.art_id_of(d), Growth.spine_stage(d), 150.0)
	if sp != null:
		sp.position = feet
		card.add_child(sp)

	var plate_y := sz.y - (cy - 30.0)
	var pw := AtlasUI.src_pt("promote_ui", "scene_promote_train_box1")
	var plate := AtlasUI.spr_cocos("promote_ui", "scene_promote_train_box1", 1.0)
	if plate != null:
		plate.position = Vector2(sz.x * 0.5, plate_y)
		plate.z_index = 10
		card.add_child(plate)
	var lv := bmf("LV %d" % int(d.get("level", 1)), 15)
	lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lv.size = Vector2(60.0, 22.0)
	lv.position = Vector2(sz.x * 0.5 - pw.x * 0.5 + 20.0, plate_y - 11.0)
	lv.z_index = 20
	card.add_child(lv)
	var nm := Label.new()
	nm.text = Icons.name_of(d)
	nm.add_theme_font_size_override("font_size", 18)
	nm.add_theme_color_override("font_color", Color(1, 0.97, 0.86))
	nm.add_theme_color_override("font_outline_color", Color(0.18, 0.1, 0.03))
	nm.add_theme_constant_override("outline_size", 5)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.size = Vector2(pw.x - 70.0, 26.0)
	nm.position = Vector2(sz.x * 0.5 - pw.x * 0.5 + 60.0, plate_y - 13.0)
	nm.z_index = 20
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(nm)

	var base: Dictionary = Growth.main_stats(ddef, Data.stat_table, d.get("gain_log", []),
		(d.get("stat_bonus", {}) as Dictionary).get("base", {}))
	var fin: Dictionary = PartyStats.resolve(d, ddef, {}, false, "")
	var rows := [["생명력", "hp"], ["공격력", "att"], ["방어력", "def"]]
	for i in rows.size():
		var y := sz.y - (160.0 - 30.0 * float(i))
		var key := bmf(String(rows[i][0]), 15)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key.size = Vector2(120.0, 22.0)
		key.position = Vector2(0.0, y - 11.0)
		key.z_index = 20
		card.add_child(key)
		var b0 := int(base.get(String(rows[i][1]), 0))
		var bf := int(fin.get(String(rows[i][1]), b0)) - b0
		var val := bmf("%d + %d" % [b0, bf] if bf > 0 else str(b0), 18)
		val.size = Vector2(sz.x - 140.0, 24.0)
		val.position = Vector2(140.0, y - 12.0)
		val.z_index = 20
		card.add_child(val)

	var ek := Icons.element_small_frame(Icons.element_of(d))
	if ek != "":
		var ei := AtlasUI.spr_cocos("item_small_ui", ek, 1.0, Vector2(0, 1))
		if ei != null:
			ei.position = Vector2(10.0, 10.0)
			ei.z_index = 20
			card.add_child(ei)

	var types: Array = Loadout.slot_types(d)
	var equipped: Array = d.get("skill_equip", [])
	var bgw := AtlasUI.src_pt("common_ui", "common_skill_star_bg").x * 0.8
	for i in Loadout.SKILL_SLOTS:
		var t := String(types[i]) if i < types.size() else "star"
		var sb := AtlasUI.spr_cocos("common_ui", "common_skill_%s_bg" % _shape(t), 0.8,
			Vector2(0.5, 0))
		if sb == null:
			continue
		var cx := sz.x * 0.5 + (float(i) - 0.5) * bgw
		sb.position = Vector2(cx, sz.y - 10.0)
		sb.z_index = 15
		card.add_child(sb)
		if not Loadout.slot_unlocked(i, int(d.get("level", 1))):
			var lk := AtlasUI.spr("common_ui", "common_lock", S * 0.6)
			if lk != null:
				lk.position = Vector2(cx, sz.y - 10.0 - bgw * 0.5)
				lk.z_index = 16
				card.add_child(lk)
			continue
		var sk := _mark_shape(types, equipped, i)
		if sk != "":
			var si := AtlasUI.spr("common_ui", "common_skill_%s" % sk, S * 0.6)
			if si != null:
				si.position = Vector2(cx, sz.y - 10.0 - bgw * 0.5)
				si.z_index = 16
				card.add_child(si)

static func _shape(t: String) -> String:
	match t:
		"tri": return "triangle"
		"sq": return "square"
		"cir": return "circle"
		_: return "star"

static func _mark_shape(types: Array, equipped: Array, slot: int) -> String:
	if slot >= equipped.size():
		return ""
	var sid := int(equipped[slot])
	if sid <= 0:
		return ""
	var ty := String(types[slot]) if slot < types.size() else "star"
	if not Loadout.slot_matches(ty, Data.skills.get(str(sid), {})):
		return ""
	return _shape(ty)

static func bmf(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	if ResourceLoader.exists(FONT_SUB):
		l.add_theme_font_override("font", load(FONT_SUB))
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
