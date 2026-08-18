class_name BottomTextBox
extends Control

signal finished
signal clicked

const BOX_H := 130.0
const BOX_MARGIN := 20.0
const BOX_BOTTOM := 10.0
const NAME_POS := Vector2(30.0, 110.0)
const TEXT_INSET := 60.0
const CPS := 45.0

var max_width := 0.0

var _bg: NinePatchRect
var _name_lbl: Label
var _text_lbl: Label
var _full := ""
var _shown := 0.0
var _typing := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	get_viewport().size_changed.connect(_layout)

func _build() -> void:
	_bg = NinePatchRect.new()
	_bg.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres")
	_bg.patch_margin_left = 15
	_bg.patch_margin_top = 15
	_bg.patch_margin_right = 15
	_bg.patch_margin_bottom = 15
	_bg.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_name_lbl = Label.new()
	_name_lbl.add_theme_font_size_override("font_size", 20)
	_name_lbl.add_theme_color_override("font_color", Color(1, 0.93, 0.25))
	_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_lbl)

	_text_lbl = Label.new()
	_text_lbl.add_theme_font_size_override("font_size", 21)
	_text_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	_text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text_lbl)
	_layout()

func _layout() -> void:
	var vis := get_viewport_rect().size
	var w: float = (max_width if max_width > 0.0 else vis.x) - BOX_MARGIN
	size = Vector2(w, BOX_H)
	var x: float = round((vis.x - w) * 0.5) if max_width <= 0.0 else BOX_MARGIN * 0.5
	position = Vector2(x, round(vis.y - BOX_H - BOX_BOTTOM))
	if _bg != null:
		_bg.size = Vector2(w, BOX_H) / Design.ASSET_SCALE
	if _name_lbl != null:
		_name_lbl.position = Vector2(NAME_POS.x, BOX_H - NAME_POS.y - 14)
		_name_lbl.size = Vector2(w - TEXT_INSET, 28)
	if _text_lbl != null:
		_text_lbl.position = Vector2(NAME_POS.x, BOX_H - NAME_POS.y + 16)
		_text_lbl.size = Vector2(w - TEXT_INSET, BOX_H - 60)

func show_text(speaker: String, text: String, typewriter := true) -> void:
	_name_lbl.text = "[ %s ]" % speaker if speaker != "" else ""
	_full = text
	if typewriter:
		_shown = 0.0
		_typing = true
		_text_lbl.text = ""
	else:
		_typing = false
		_text_lbl.text = text
		finished.emit()

func show_all() -> void:
	if _typing:
		_typing = false
		_text_lbl.text = _full
		finished.emit()

func is_typing() -> bool:
	return _typing

func _process(delta: float) -> void:
	if not _typing:
		return
	_shown += delta * CPS
	var n := mini(int(_shown), _full.length())
	_text_lbl.text = _full.substr(0, n)
	if n >= _full.length():
		_typing = false
		finished.emit()

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if _typing:
			show_all()
		else:
			clicked.emit()
		accept_event()
