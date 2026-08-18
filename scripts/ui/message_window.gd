class_name MessageWindow
extends RefCounted

const BW := 460.0
const BH := 300.0
const ITEM_BW := 650.0
const ITEM_BH := 480.0
const ITEM_BOX := Vector2(570.0, 160.0)
const ITEM_BOX_TOP_PAD := 40.0
const ITEM_ICON_X := 100.0
const ITEM_LABEL_DX := 80.0
const ITEM_BACKLIGHT_SCALE := 0.5

static func open(parent: Node, title: String, msg: String, on_confirm: Callable,
		confirm_text := "확인", cancel_text := "취소",
		cash_type := -1, cash_n := 0, on_cancel := Callable(),
		item_icon: Node2D = null, item_text := "") -> CanvasLayer:
	var vis: Vector2 = parent.get_viewport().get_visible_rect().size
	var has_item := item_icon != null or item_text != ""
	var bw := ITEM_BW if has_item else BW
	var bh := ITEM_BH if has_item else BH
	var layer := CanvasLayer.new(); layer.layer = 70
	parent.add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190
	win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(bw, bh)
	win.position = Vector2(round((vis.x - bw) * 0.5), round((vis.y - bh) * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20
	tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(300, 52); tbar.position = Vector2((bw - 300) * 0.5, 12)
	win.add_child(tbar)
	var tl := Label.new(); tl.text = title
	tl.add_theme_font_size_override("font_size", 26)
	tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	var done := [false]
	var bail := func():
		if done[0]:
			return
		done[0] = true
		layer.queue_free()
		if on_cancel.is_valid():
			on_cancel.call()
	var xb := TextureButton.new()
	xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(bw - 58, 14)
	xb.pressed.connect(bail)
	win.add_child(xb)
	var msg_top := 76.0
	var msg_pad := 34.0
	if has_item:
		msg_pad = 24.0
		msg_top = _add_item_box(win, bw, tbar.size.y, item_icon, item_text) + 12.0
	var ml := Label.new(); ml.text = msg
	ml.add_theme_font_size_override("font_size", 21)
	ml.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ml.position = Vector2(msg_pad, msg_top)
	ml.size = Vector2(bw - msg_pad * 2.0, maxf(40.0, bh - 90.0 - msg_top))
	win.add_child(ml)
	if cash_type >= 0:
		_add_cash_row(win, bw, bh, cash_type, cash_n)
	var rb := Button.new(); rb.text = confirm_text; rb.size = Vector2(160, 46)
	if cancel_text == "":
		rb.position = Vector2(bw * 0.5 - 80, bh - 66)
	else:
		rb.position = Vector2(bw * 0.5 + 14, bh - 66)
		var lb := Button.new(); lb.text = cancel_text; lb.size = Vector2(160, 46)
		lb.position = Vector2(bw * 0.5 - 174, bh - 66)
		lb.pressed.connect(bail)
		win.add_child(lb)
	rb.pressed.connect(func():
		if done[0]:
			return
		done[0] = true
		layer.queue_free()
		on_confirm.call())
	win.add_child(rb)
	return layer

static func _add_item_box(win: NinePatchRect, bw: float, tbar_h: float,
		icon: Node2D, text: String) -> float:
	var top := ITEM_BOX_TOP_PAD + tbar_h
	var box := Control.new()
	box.size = ITEM_BOX
	box.position = Vector2((bw - ITEM_BOX.x) * 0.5, top)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win.add_child(box)
	var mid := ITEM_BOX.y * 0.5
	var back := AtlasUI.spr_cocos("common_ui", "common_backlight3", ITEM_BACKLIGHT_SCALE)
	if back:
		back.position = Vector2(ITEM_ICON_X, mid)
		box.add_child(back)
	if icon:
		icon.position = Vector2(ITEM_ICON_X, mid)
		box.add_child(icon)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var lw := ITEM_BOX.x - ITEM_ICON_X - 40.0
	lbl.size = Vector2(lw, 60.0)
	lbl.position = Vector2(ITEM_BOX.x * 0.5 + ITEM_LABEL_DX - lw * 0.5, mid - 30.0)
	box.add_child(lbl)
	return top + ITEM_BOX.y

static func _add_cash_row(win: NinePatchRect, bw: float, bh: float,
		cash_type: int, n: int) -> void:
	var key := ""
	match cash_type:
		0: key = "common_diamond_small1"
		1: key = "common_coin_small1"
		_: key = "common_diamond_small1"
	var row := Control.new()
	row.size = Vector2(bw, 30.0)
	row.position = Vector2(0, bh - 104)
	win.add_child(row)
	var icon := AtlasUI.spr("common_ui", key, 1.0)
	var iw := 0.0
	if icon:
		iw = AtlasUI.size_pt("common_ui", key).x
	var lbl := Label.new()
	lbl.text = "X %d" % n
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size = Vector2(70.0, 30.0)
	var total := iw + 6.0 + 46.0
	var x0 := bw * 0.5 - total * 0.5
	if icon:
		icon.position = Vector2(x0 + iw * 0.5, 15.0)
		row.add_child(icon)
	lbl.position = Vector2(x0 + iw + 6.0, 0)
	row.add_child(lbl)
