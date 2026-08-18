class_name SettingsView
extends CanvasLayer

const SET := "setting_ui"

const DIM_ALPHA := 127.0 / 255.0
const TITLE_W_RATIO := 0.9
const TITLE_INSET := 50.0
const ROW_LABEL_DY := [200.0, 110.0]
const ROW_SLIDER_DY := [160.0, 70.0]
const ROW_X_OFF := -60.0
const ROW_FONT := 19
const RULE_DY := 20.0
const RULE_LABEL_DY := 25.0
const SECTION_FONT := 22
const DESC_DY := -30.0
const ACTION_DY := -110.0

signal closed
signal save_reset

var _root: Control

static func open(parent: Node) -> SettingsView:
	var l := SettingsView.new()
	l.layer = 40
	parent.add_child(l)
	return l

func _ready() -> void:
	_build()

func _build() -> void:
	if is_instance_valid(_root):
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var vis := get_viewport().get_visible_rect().size

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	create_tween().tween_property(dim, "color:a", DIM_ALPHA, 0.2)

	_build_title(vis)
	_build_volume_rows(vis)
	_build_title_screen_row(vis)
	_build_reset_section(vis)

func _build_title(vis: Vector2) -> void:
	var th := AtlasUI.size_pt("ninepatch_ui", "9patch_pop_title_bg").y
	var tw := vis.x * TITLE_W_RATIO
	var cy := TITLE_INSET
	var bar := AtlasUI.nine("ninepatch_ui", "9patch_pop_title_bg", Vector2(tw, th))
	if bar != null:
		bar.position = Vector2(vis.x * 0.5 - tw * 0.5, cy - th * 0.5)
		_root.add_child(bar)
	_root.add_child(_label("설정", 28, Color.WHITE,
		Vector2(vis.x * 0.5 - tw * 0.5, cy - th * 0.5), Vector2(tw, th)))

	var cs := AtlasUI.size_pt("common_ui", "common_close_btn") * 1.5
	var x := TextureButton.new()
	var ct := AtlasUI.tex("common_ui", "common_close_btn")
	if ct != null:
		x.texture_normal = ct
		x.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 1.5
	x.position = Vector2(vis.x - TITLE_INSET, cy) - cs * 0.5
	x.pressed.connect(close)
	_root.add_child(x)

func _build_volume_rows(vis: Vector2) -> void:
	var rows := [
		["배경음", Bgm.music_volume(), func(v: float, p: bool): Bgm.set_music_volume(v, p)],
		["효과음", Bgm.effects_volume(), func(v: float, p: bool): Bgm.set_effects_volume(v, p)],
	]
	var x := vis.x * 0.5 + ROW_X_OFF
	for i in rows.size():
		var r: Array = rows[i]
		var ly := Design.flip_y(vis.y * 0.5 + ROW_LABEL_DY[i], vis.y)
		var sy := Design.flip_y(vis.y * 0.5 + ROW_SLIDER_DY[i], vis.y)
		_root.add_child(_label(String(r[0]), ROW_FONT, Color(1, 0.94, 0.80),
			Vector2(x - 100.0, ly - 16.0), Vector2(200.0, 32.0)))
		var sl := FrameSlider.new(float(r[1]), r[2])
		sl.position = Vector2(x, sy)
		_root.add_child(sl)

const TITLE_ROW_RULE_DY := -160.0
const TITLE_ROW_LABEL_DY := -155.0
const TITLE_ROW_BTN_DY := -215.0
func _build_title_screen_row(vis: Vector2) -> void:
	var rule := AtlasUI.spr(SET, "scene_setting_line", Design.ASSET_SCALE)
	if rule != null:
		rule.position = Vector2(vis.x * 0.5, Design.flip_y(vis.y * 0.5 + TITLE_ROW_RULE_DY, vis.y))
		_root.add_child(rule)
	var hy := Design.flip_y(vis.y * 0.5 + TITLE_ROW_LABEL_DY, vis.y)
	_root.add_child(_label("타이틀 화면", SECTION_FONT, Color(1, 0.94, 0.80),
		Vector2(vis.x * 0.5 - 120.0, hy - 18.0), Vector2(240.0, 36.0)))

	var cur := String(UserDB.get_pmeta("title_screen", "2020"))
	var by := Design.flip_y(vis.y * 0.5 + TITLE_ROW_BTN_DY, vis.y)
	var bsz := Vector2(220.0, 52.0)
	var opts := [["2020 (시즌3)", "2020"], ["구판", "old"]]
	for i in opts.size():
		var o: Array = opts[i]
		var on: bool = cur == String(o[1])
		var x := vis.x * 0.5 + (-10.0 - bsz.x if i == 0 else 10.0)
		AtlasUI.frame_button(_root, String(o[0]), Vector2(x, by - bsz.y * 0.5), bsz,
			func(): _set_title_screen(String(o[1])),
			0 if on else 1, false, 20)

func _set_title_screen(kind: String) -> void:
	UserDB.set_pmeta("title_screen", kind)
	_build()

func _build_reset_section(vis: Vector2) -> void:
	var rule := AtlasUI.spr(SET, "scene_setting_line", Design.ASSET_SCALE)
	if rule != null:
		rule.position = Vector2(vis.x * 0.5, Design.flip_y(vis.y * 0.5 + RULE_DY, vis.y))
		_root.add_child(rule)
	var hy := Design.flip_y(vis.y * 0.5 + RULE_LABEL_DY, vis.y)
	_root.add_child(_label("데이터", SECTION_FONT, Color(1, 0.94, 0.80),
		Vector2(vis.x * 0.5 - 120.0, hy - 18.0), Vector2(240.0, 36.0)))

	var dy := Design.flip_y(vis.y * 0.5 + DESC_DY, vis.y)
	_root.add_child(_label(
		"모든 진행도(드래곤·재화·아이템·스토리)를 지우고 처음부터 시작합니다.\n"
		+ "되돌릴 수 없습니다. 볼륨 설정은 유지됩니다.",
		17, Color(1, 0.86, 0.72),
		Vector2(vis.x * 0.5 - 300.0, dy - 26.0), Vector2(600.0, 52.0)))
	var by := Design.flip_y(vis.y * 0.5 + ACTION_DY, vis.y)
	var bsz := Vector2(240.0, 56.0)
	AtlasUI.frame_button(_root, "세이브 데이터 초기화",
		Vector2(vis.x * 0.5 - bsz.x * 0.5, by - bsz.y * 0.5), bsz,
		_confirm_reset, 2, false, 20)

func _confirm_reset() -> void:
	MessageWindow.open(_root, "세이브 초기화",
		"정말 초기화하시겠습니까?\n모든 진행도가 사라집니다.",
		_do_reset, "초기화", "취소")

func _do_reset() -> void:
	UserDB.reset()
	save_reset.emit()
	queue_free()
	Scenes.goto("intro")

func close() -> void:
	closed.emit()
	queue_free()

func _label(text: String, size: int, color: Color, pos: Vector2, dim: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = pos
	l.size = dim
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

class FrameSlider extends Control:
	const SET := "setting_ui"

	var _value := 0.0
	var _on_change: Callable
	var _track: Texture2D
	var _progress: Texture2D
	var _thumb: Texture2D
	var _track_sz: Vector2
	var _prog_sz: Vector2
	var _thumb_sz: Vector2
	var _dragging := false

	func _init(initial: float, on_change: Callable) -> void:
		_value = clampf(initial, 0.0, 1.0)
		_on_change = on_change

	func _ready() -> void:
		_track = AtlasUI.tex(SET, "scene_setting_sliderTrack")
		_progress = AtlasUI.tex(SET, "scene_setting_sliderProgress")
		_thumb = AtlasUI.tex(SET, "scene_setting_sliderThumb")
		_track_sz = AtlasUI.size_pt(SET, "scene_setting_sliderTrack")
		_prog_sz = AtlasUI.size_pt(SET, "scene_setting_sliderProgress")
		_thumb_sz = AtlasUI.size_pt(SET, "scene_setting_sliderThumb")
		size = Vector2(_track_sz.x + _thumb_sz.x, maxf(_track_sz.y, _thumb_sz.y))
		position -= size * 0.5
		mouse_filter = Control.MOUSE_FILTER_STOP
		queue_redraw()

	func _draw() -> void:
		if _track == null:
			return
		var cy := size.y * 0.5
		var tx := (size.x - _track_sz.x) * 0.5
		draw_texture_rect(_track, Rect2(Vector2(tx, cy - _track_sz.y * 0.5), _track_sz), false)
		if _progress != null and _value > 0.0:
			var pw := _prog_sz.x * _value
			var px := tx + (_track_sz.x - _prog_sz.x) * 0.5
			draw_texture_rect_region(_progress,
				Rect2(Vector2(px, cy - _prog_sz.y * 0.5), Vector2(pw, _prog_sz.y)),
				Rect2(Vector2.ZERO, Vector2(_progress.get_width() * _value,
					_progress.get_height())))
		if _thumb != null:
			var hx := tx + _track_sz.x * _value - _thumb_sz.x * 0.5
			draw_texture_rect(_thumb, Rect2(Vector2(hx, cy - _thumb_sz.y * 0.5), _thumb_sz), false)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var mb := e as InputEventMouseButton
			if mb.pressed:
				_dragging = true
				_set_from_x(mb.position.x, false)
			elif _dragging:
				_dragging = false
				_apply(true)
			accept_event()
		elif e is InputEventMouseMotion and _dragging:
			_set_from_x((e as InputEventMouseMotion).position.x, false)
			accept_event()

	func _set_from_x(x: float, persist: bool) -> void:
		var tx := (size.x - _track_sz.x) * 0.5
		_value = clampf((x - tx) / maxf(1.0, _track_sz.x), 0.0, 1.0)
		queue_redraw()
		_apply(persist)

	func _apply(persist: bool) -> void:
		if _on_change.is_valid():
			_on_change.call(_value, persist)
