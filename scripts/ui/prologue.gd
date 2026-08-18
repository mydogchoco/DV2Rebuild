extends Control

const BOX_H := 150.0
const DIR := "res://assets/converted/prologue_ui"
const ARROW := "res://assets/converted/common_ui/common_btn_arrow2.tres"
const DIALOG_BOX := "res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres"
const CPS := 40.0
const MONSTER_FROM := 20

const BGM := "bg_yutakan"

var _params: Dictionary = {}
var _lines: Array[String] = []
var _from := 0
var _to := -1
var _idx := 0
var _label: Label
var _arrow: Sprite2D
var _typing := false
var _timer: Timer
var _arrow_tween: Tween
var _monster: Sprite2D
var _pma: CanvasItemMaterial

func enter(params: Dictionary = {}) -> void:
	_params = params
	if _pma != null:
		_rebuild()

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_rebuild()

func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_lines = Data.prologue_lines()
	_from = clampi(int(_params.get("from", 0)), 0, maxi(0, _lines.size() - 1))
	var last := _lines.size() - 1
	_to = int(_params.get("to", last))
	_to = clampi(_to if _to >= 0 else last, _from, last)
	_idx = _from
	Bgm.play(BGM)
	_build_scene()
	_build_textbox()
	if _lines.is_empty():
		_show_text("(프롤로그 대사가 없습니다 — build_scenario.py 실행)")
	else:
		_show_line(_from)

const BG_SIZE := Vector2(768.0, 519.0)
const OVL_CANVAS := Vector2(384.0, 260.0)

var _stage: Node2D

func _build_scene() -> void:
	var vis := _vis()
	var back := ColorRect.new()
	back.color = Color(0.03, 0.02, 0.05)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	_stage = Node2D.new()
	var k := maxf(vis.x / BG_SIZE.x, vis.y / BG_SIZE.y)
	_stage.scale = Vector2(k, k)
	_stage.position = (vis - BG_SIZE * k) * 0.5
	add_child(_stage)
	var bgp := "%s/prologue_1.jpg" % DIR
	if ResourceLoader.exists(bgp):
		var s := Sprite2D.new()
		s.texture = load(bgp)
		s.centered = false
		_stage.add_child(s)
	for key in ["add_houses", "add_line1", "add_line2", "add_human"]:
		_overlay(key)
	_monster = _overlay("add_monster")
	if _monster != null:
		_monster.visible = false

func _overlay(key: String) -> Sprite2D:
	var p := "%s/scenario_prologue_prologue_img_%s.tres" % [DIR, key]
	if not ResourceLoader.exists(p) or _stage == null:
		return null
	var man := _man()
	var mk := "scenario_prologue_prologue_img_%s" % key
	var info: Dictionary = man.get(mk, {})
	var tex := load(p)
	if tex == null:
		return null
	var s := Sprite2D.new()
	s.texture = tex
	s.material = _pma
	s.centered = false
	var scale := BG_SIZE.x / OVL_CANVAS.x
	s.scale = Vector2(scale, scale)
	var w := float(info.get("w", tex.get_size().x))
	var h := float(info.get("h", tex.get_size().y))
	var off: Array = info.get("off", [0, 0])
	var ox := (OVL_CANVAS.x - w) * 0.5 + float(off[0])
	var oy := (OVL_CANVAS.y - h) * 0.5 - float(off[1])
	s.position = Vector2(ox, oy) * scale
	s.z_index = 1
	_stage.add_child(s)
	return s

func _man() -> Dictionary:
	var f := FileAccess.open("%s/_manifest.json" % DIR, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func _build_textbox() -> void:
	var vis := _vis()
	var lay := CanvasLayer.new(); lay.layer = 8; add_child(lay)
	var box := NinePatchRect.new()
	box.texture = load(DIALOG_BOX)
	box.patch_margin_left = 10; box.patch_margin_right = 10
	box.patch_margin_top = 4; box.patch_margin_bottom = 4
	box.size = Vector2(vis.x - 20.0, BOX_H)
	box.position = Vector2(10.0, vis.y - BOX_H)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lay.add_child(box)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.position = Vector2(20.0, 20.0)
	_label.size = Vector2(box.size.x - 75.0, BOX_H - 34.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_label)
	if ResourceLoader.exists(ARROW):
		_arrow = Sprite2D.new()
		_arrow.texture = load(ARROW)
		_arrow.material = _pma
		_arrow.position = Vector2(box.size.x - 35.0, BOX_H * 0.5)
		_arrow.visible = false
		box.add_child(_arrow)
	var catcher := Control.new()
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_advance())
	lay.add_child(catcher)
	lay.move_child(catcher, 0)

func _show_line(i: int) -> void:
	_idx = i
	if _monster != null:
		_monster.visible = i >= MONSTER_FROM
	_show_speaker(i)
	_show_text(_lines[i])

const NO_PORTRAIT := ["hero", "prologuemonster"]
var _npc_node: Node = null
func _show_speaker(i: int) -> void:
	var sp: Dictionary = Data.tutorial_flow.get("speakers", {}).get(str(i), {})
	var npc := String(sp.get("npc", ""))
	if is_instance_valid(_npc_node):
		_npc_node.queue_free()
		_npc_node = null
	if npc == "" or npc in NO_PORTRAIT:
		return
	var p := NpcPortrait.create(npc, 1, 1)
	if p == null:
		return
	_npc_node = p
	p.position = Vector2(_vis().x * 0.5, _vis().y - BOX_H)
	p.z_index = 4
	add_child(p)
	p.modulate.a = 0.0
	p.create_tween().tween_property(p, "modulate:a", 1.0, 0.2)

func _show_text(text: String) -> void:
	_label.text = text
	_label.visible_characters = 0
	_typing = true
	_stop_arrow_tween()
	if _arrow: _arrow.visible = false
	if is_instance_valid(_timer): _timer.queue_free()
	_timer = Timer.new()
	_timer.wait_time = 1.0 / CPS
	add_child(_timer)
	var total := text.length()
	_timer.timeout.connect(func() -> void:
		_label.visible_characters += 1
		if _label.visible_characters >= total:
			_reveal_all())
	_timer.start()

func _reveal_all() -> void:
	_label.visible_characters = -1
	_typing = false
	if is_instance_valid(_timer): _timer.stop()
	if _arrow:
		_arrow.visible = true
		_stop_arrow_tween()
		_arrow_tween = _arrow.create_tween().set_loops()
		_arrow_tween.tween_property(_arrow, "position:y", BOX_H * 0.5 + 6.0, 0.4)
		_arrow_tween.tween_property(_arrow, "position:y", BOX_H * 0.5, 0.4)

func _stop_arrow_tween() -> void:
	if _arrow_tween != null and _arrow_tween.is_valid():
		_arrow_tween.kill()
	_arrow_tween = null
	if is_instance_valid(_arrow):
		_arrow.position.y = BOX_H * 0.5

func _advance() -> void:
	if _typing:
		_reveal_all()
		return
	if _lines.is_empty() or _idx >= _to:
		if _to >= _lines.size() - 1:
			UserDB.set_progress("prologue_seen", true)
		Scenes.goto(String(_params.get("back", "worldmap")), _params.get("back_params", {}))
		return
	_show_line(_idx + 1)

func _vis() -> Vector2:
	return get_viewport_rect().size
