extends Control

const OUTER_PAD := 10.0
const INNER_PAD := 5.0
const TEXT_PAD_Y := 20.0
const TITLE_GAP := 5.0
const MIN_INNER_W := 180.0
const INITIAL_SIZE := Vector2(300.0, 150.0)

var _anchor: Control
var _row: Dictionary
var _panel: Control

static func open(host: Node, anchor: Control, no: int) -> Control:
	var row: Dictionary = Data.skill_awaken_for(no)
	if row.is_empty():
		return null
	var layer := CanvasLayer.new()
	layer.layer = 80
	host.add_child(layer)
	var tip: Control = (load("res://scripts/ui/dragon_awaken_skill_info.gd") as GDScript).new()
	tip._anchor = anchor
	tip._row = row
	tip.tree_exiting.connect(func():
		if is_instance_valid(layer):
			layer.queue_free())
	layer.add_child(tip)
	return tip

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var local := (event as InputEventMouseButton).position
		if _panel == null or not Rect2(_panel.position, _panel.size).has_point(local):
			accept_event()
			queue_free()

func _build() -> void:
	var vis := get_viewport_rect().size
	var max_inner_w := maxf(MIN_INNER_W, vis.x / 3.0)
	var title_text := String(_row.get("name", ""))
	var comment_text := String(_row.get("comment", ""))
	var common := _font("font_common")
	var subtitle := _font("font_subtitle")
	var body_size := 18
	var title_size := 20
	var natural_w := common.get_string_size(comment_text, HORIZONTAL_ALIGNMENT_LEFT, -1, body_size).x \
		if common != null else float(comment_text.length() * body_size)
	var inner_w := clampf(natural_w, MIN_INNER_W, max_inner_w)
	var body := Label.new()
	body.text = comment_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.add_theme_font_size_override("font_size", body_size)
	body.add_theme_color_override("font_color", Color.WHITE)
	if common != null:
		body.add_theme_font_override("font", common)
	body.size = Vector2(inner_w, 1.0)
	body.reset_size()
	var body_h := maxf(float(body.get_line_count()) * body.get_line_height(), body.get_minimum_size().y)
	var title_h := maxf(24.0, subtitle.get_height(title_size) if subtitle != null else 24.0)
	var inner_h := body_h + TEXT_PAD_Y
	var win := Vector2(inner_w + OUTER_PAD * 2.0,
		inner_h + OUTER_PAD * 2.0 + title_h + TITLE_GAP)
	win.x = minf(maxf(win.x, INITIAL_SIZE.x * 0.65), max_inner_w + OUTER_PAD * 2.0)
	win.y = maxf(win.y, INITIAL_SIZE.y * 0.65)

	_panel = Control.new()
	_panel.size = win
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var outer := Panel.new()
	outer.size = win
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = Color8(0x13, 0x13, 0x13, 0xfa)
	outer_style.corner_radius_top_left = 8
	outer_style.corner_radius_top_right = 8
	outer_style.corner_radius_bottom_left = 8
	outer_style.corner_radius_bottom_right = 8
	outer.add_theme_stylebox_override("panel", outer_style)
	_panel.add_child(outer)

	var dialogue := AtlasUI.nine("ninepatch_ui", "9patch_dialogue_box", win)
	if dialogue != null:
		dialogue.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(dialogue)

	var inner_pos := Vector2(OUTER_PAD, OUTER_PAD + title_h + TITLE_GAP)
	var inner_size := Vector2(win.x - OUTER_PAD * 2.0, win.y - inner_pos.y - OUTER_PAD)
	var inner := Panel.new()
	inner.position = inner_pos
	inner.size = inner_size
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner_style := StyleBoxFlat.new()
	inner_style.bg_color = Color8(0x3c, 0x3c, 0x3c, 0xc8)
	inner_style.corner_radius_top_left = 6
	inner_style.corner_radius_top_right = 6
	inner_style.corner_radius_bottom_left = 6
	inner_style.corner_radius_bottom_right = 6
	inner.add_theme_stylebox_override("panel", inner_style)
	_panel.add_child(inner)

	var title := Label.new()
	title.text = title_text
	title.position = Vector2(OUTER_PAD, OUTER_PAD - 2.0)
	title.size = Vector2(win.x - OUTER_PAD * 2.0, title_h)
	title.add_theme_font_size_override("font_size", title_size)
	title.add_theme_color_override("font_color", Color.WHITE)
	if subtitle != null:
		title.add_theme_font_override("font", subtitle)
	_panel.add_child(title)

	body.position = inner_pos + Vector2(INNER_PAD, INNER_PAD)
	body.size = Vector2(inner_size.x - INNER_PAD * 2.0, inner_size.y - INNER_PAD * 2.0)
	_panel.add_child(body)

	var ar := _anchor.get_global_rect() if is_instance_valid(_anchor) else Rect2(vis * 0.5, Vector2.ZERO)
	var pos := Vector2(ar.position.x, ar.position.y - win.y)
	pos.x = clampf(pos.x, 4.0, maxf(4.0, vis.x - win.x - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, vis.y - win.y - 4.0))
	_panel.position = pos.round()

func _font(name: String) -> FontFile:
	var p := "res://assets/converted/font_ui/%s.fnt" % name
	if not ResourceLoader.exists(p):
		return null
	var f := load(p) as FontFile
	return f.duplicate() if f != null else null
