class_name TrainingPicker
extends RefCounted

const FONT_HEAL := "res://assets/converted/font_ui/font_heal.fnt"
const FONT_COMMON := "res://assets/converted/font_ui/font_common.fnt"

const ICON_ANIM_DELAY := 0.5

static func open(host: Node, title: String, uid: int, on_pick: Callable) -> CanvasLayer:
	var rows: Array = []
	for r in Data.promote.get("training", {}).get("info_train_v2", []):
		var row: Dictionary = (r as Dictionary).duplicate()
		row["uid"] = uid
		row["value"] = int(row.get("train_no", 0))
		row["off"] = false
		rows.append(row)
	return DragonPicker._shell(host, title, rows, on_pick, _fill_training_cell)

static func _fill_training_cell(card: Control, row: Dictionary, sz: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var cy := sz.y * 0.5

	var icon_y := sz.y - (cy + 60.0)
	var back := AtlasUI.spr("common_ui", "common_backlight3", S * 0.8)
	if back != null:
		back.position = Vector2(sz.x * 0.5, icon_y)
		back.modulate = Color(1, 1, 1, 0.8)
		card.add_child(back)
	var frames: Array[Node2D] = []
	for key: String in [String(row.get("icon", "")), String(row.get("icon2", ""))]:
		if key.is_empty():
			continue
		var f := AtlasUI.spr_cocos("promote_ui", "scene_promote_%s" % key)
		if f == null:
			continue
		f.position = Vector2(sz.x * 0.5, icon_y)
		f.visible = frames.is_empty()
		card.add_child(f)
		frames.append(f)
	if frames.size() > 1:
		var tw := card.create_tween().set_loops()
		for i in frames.size():
			tw.tween_callback(func() -> void:
				for j in frames.size():
					frames[j].visible = (j == i))
			tw.tween_interval(ICON_ANIM_DELAY)

	_center(card, DragonPicker.bmf(String(row.get("name", "")), 22), sz.x, 50.0 - 14.0)
	var big := DragonPicker.bmf("", 30)
	big.text = "+ %d" % int(row.get("exp", 0))
	if ResourceLoader.exists(FONT_HEAL):
		big.add_theme_font_override("font", load(FONT_HEAL))
	_center(card, big, sz.x, sz.y - (cy - 20.0) - 18.0)
	var need := int(row.get("need_time", 0))
	var desc := DragonPicker.bmf("(%02d : %02d : %02d)"
		% [need / 3600, (need % 3600) / 60, need % 60], 16)
	if ResourceLoader.exists(FONT_COMMON):
		desc.add_theme_font_override("font", load(FONT_COMMON))
	_center(card, desc, sz.x, sz.y - (cy - 60.0) - 10.0)

	var uid := int(row.get("uid", 0))
	var d: Dictionary = UserDB.get_dragon(uid)
	var lv0 := int(d.get("level", 1))
	var lv1 := level_after(uid, int(row.get("exp", 0)))
	var ly := sz.y - (cy - 120.0)
	var half := sz.x * 0.5
	var lf := DragonPicker.bmf("LV %d" % lv0, 18)
	lf.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lf.size = Vector2(half - 30.0, 24.0)
	lf.position = Vector2(0.0, ly - 12.0)
	card.add_child(lf)
	var ar := AtlasUI.spr("common_ui", "common_btn_arrow2", S * 0.6)
	if ar != null:
		ar.position = Vector2(half, ly)
		card.add_child(ar)
	var lt := DragonPicker.bmf("LV %d" % lv1, 18)
	lt.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6) if lv1 > lv0 else Color(1, 1, 1))
	lt.size = Vector2(half - 30.0, 24.0)
	lt.position = Vector2(half + 30.0, ly - 12.0)
	card.add_child(lt)

	var iy := sz.y - 53.0
	var dia := String(row.get("fee_type", "gold")) == "dia"
	var ci := AtlasUI.spr_cocos("common_ui",
		"common_diamond_small1" if dia else "common_coin_small1", 1.0, Vector2(1, 0.5))
	if ci != null:
		ci.position = Vector2(half - 20.0, iy)
		card.add_child(ci)
	var cl := DragonPicker.bmf(AtlasUI.comma(int(row.get("fee", 0))), 18)
	cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cl.size = Vector2(half, 24.0)
	cl.position = Vector2(half - 14.0, iy - 12.0)
	card.add_child(cl)

static func _center(card: Control, l: Label, w: float, y: float) -> void:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(w, 34.0)
	l.position = Vector2(0.0, y)
	card.add_child(l)

static func level_after(uid: int, gain: int) -> int:
	var d: Dictionary = UserDB.get_dragon(uid)
	if d.is_empty():
		return 1
	var lv := int(d.get("level", 1))
	var cap := LevelSystem.cap_for(Data.level_curve, bool(d.get("awakened", false)))
	var cur := int(d.get("exp", 0)) + gain
	while lv < cap:
		var need := LevelSystem.exp_to_next(Data.level_curve, lv)
		if need <= 0 or cur < need:
			break
		cur -= need
		lv += 1
	return lv
