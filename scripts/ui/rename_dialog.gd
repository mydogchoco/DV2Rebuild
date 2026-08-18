extends RefCounted
class_name RenameDialog

const PANEL := Vector2(650.0, 420.0)
const BTN := Vector2(220.0, 56.0)
const EDIT := Vector2(400.0, 53.0)
const MAX_LEN := 12

const _NP := "res://assets/converted/ninepatch_ui/%s.tres"

static func open(parent: Node, is_first: bool, on_confirm := Callable()) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 40
	parent.add_child(layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var vis: Vector2 = parent.get_viewport().get_visible_rect().size
	var win := _nine(_NP % "9patch_popup4", 130, 190, 55, 81)
	win.size = PANEL
	win.position = ((vis - PANEL) * 0.5).round()
	layer.add_child(win)

	var tw := PANEL.x * 0.9
	var th := 33.0 * Design.ASSET_SCALE
	var tbar := _nine(_NP % "9patch_pop_title_bg", 20, 12, 20, 12)
	tbar.size = Vector2(tw, th)
	tbar.position = Vector2((PANEL.x - tw) * 0.5, 50.0 - th * 0.5)
	tbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win.add_child(tbar)
	win.add_child(_label("닉네임 설정" if is_first else "닉네임 변경", 28, Color.WHITE,
		tbar.position, tbar.size))

	var guide := "게임에서 사용할 닉네임을 입력하세요." if is_first else "새 닉네임을 입력하세요."
	win.add_child(_label(guide, 19, Color(0.36, 0.26, 0.12),
		Vector2(0.0, PANEL.y * 0.5 + 53.0 - 14.0), Vector2(PANEL.x, 28.0)))

	var box := _nine(_NP % "9patch_text_box", 20, 20, 16, 16)
	box.size = EDIT
	box.position = Vector2((PANEL.x - EDIT.x) * 0.5, PANEL.y * 0.5 - 13.0 - EDIT.y * 0.5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win.add_child(box)

	var edit := LineEdit.new()
	edit.max_length = MAX_LEN
	edit.text = "" if is_first else UserDB.user_nickname()
	edit.placeholder_text = "%d자 이내" % MAX_LEN
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.flat = true
	edit.size = EDIT - Vector2(36.0, 14.0)
	edit.position = box.position + Vector2(18.0, 7.0)
	edit.add_theme_font_size_override("font_size", 24)
	edit.add_theme_color_override("font_color", Color(0.22, 0.16, 0.08))
	edit.add_theme_color_override("font_placeholder_color", Color(0.55, 0.48, 0.40))
	win.add_child(edit)

	var by := PANEL.y - 75.0 - BTN.y * 0.5
	var ok_cx := PANEL.x * 0.5 + (-120.0 if not is_first else 0.0)
	var ok := _button("확인", "9patch_btn", Vector2(ok_cx - BTN.x * 0.5, by))
	win.add_child(ok)

	var cancel: Control = null
	if not is_first:
		cancel = _button("취소", "9patch_btn",
			Vector2(PANEL.x * 0.5 + 120.0 - BTN.x * 0.5, by))
		win.add_child(cancel)

	var refresh := func() -> void:
		ok.modulate = Color(1, 1, 1, 1.0 if not edit.text.strip_edges().is_empty() else 0.55)
	edit.text_changed.connect(func(_t): refresh.call())
	refresh.call()

	TextField.no_steal(win)
	var confirm := func():
		var nick := TextField.value(edit)
		if nick.is_empty():
			return
		UserDB.set_user_nickname(nick)
		layer.queue_free()
		if on_confirm.is_valid():
			on_confirm.call(nick)
	(ok.get_child(0) as Button).pressed.connect(confirm)
	edit.text_submitted.connect(func(_s): confirm.call())
	if cancel != null:
		(cancel.get_child(0) as Button).pressed.connect(func(): layer.queue_free())

	edit.grab_focus()
	return layer

static func _nine(path: String, l: int, t: int, r: int, b: int) -> NinePatchRect:
	var n := NinePatchRect.new()
	n.texture = load(path)
	n.patch_margin_left = l; n.patch_margin_top = t
	n.patch_margin_right = r; n.patch_margin_bottom = b
	return n

static func _label(text: String, size: int, color: Color, pos: Vector2, dim: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = pos; l.size = dim
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func _button(text: String, frame: String, pos: Vector2) -> Control:
	var bg := _nine(_NP % frame, 20, 20, 17, 18)
	bg.size = BTN
	bg.position = pos
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := Button.new()
	b.flat = true
	b.text = text
	b.size = BTN
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color(1, 0.97, 0.8))
	b.add_theme_color_override("font_disabled_color", Color(0.85, 0.85, 0.85, 0.6))
	bg.add_child(b)
	return bg
