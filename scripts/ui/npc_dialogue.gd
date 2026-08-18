extends CanvasLayer
class_name NpcDialogue

const BOX_H := 150.0
const BOX_Z := 1000
const DIALOG_BOX := "res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres"
const ARROW := "res://assets/converted/common_ui/common_btn_arrow2.tres"
const IN_DELAY := 0.45
const IN_TIME := 0.45
const BOX_DY := 170.0
const CPS := 40.0

const POS_LEFT := 1
const POS_RIGHT := 2
const POS_CENTER := 3

const SCALE_SMALL := 1.07
const SCALE_NORMAL := 1.12
const SCALE_POP := 1.17
const SCALE_UP_TIME := 0.16666667
const SCALE_SETTLE_TIME := 0.25
const SIDE_MARGIN := 20.0
const NPC_Y_OFFSET := {"jimon": 100.0, "amanta": -60.0, "hybrid": -60.0, "regiana_dragon": -60.0}
const NPC_X_EXTRA := {"annie": 20.0, "regiana_dragon": 480.0}
const SIDE_IN_TIME := 0.5
const CENTER_IN_TIME := 1.25

signal advanced()
signal chosen(index: int)

var _pma: CanvasItemMaterial
var _box: NinePatchRect
var _name: Label
var _label: Label
var _arrow: Sprite2D
var _arrow_tween: Tween
var _portrait: Node2D
var _slots: Dictionary = {}
var _opened := false
var _choice_row: Control
var _full := ""
var _shown := 0.0
var _typing := false

static func open(host: Node, npc_id: String, who: String, text: String,
		emotion := 1, body := 1, pos := POS_CENTER) -> NpcDialogue:
	var l := NpcDialogue.new()
	l.layer = 26
	host.add_child(l)
	l._build(npc_id, who, text, emotion, body, pos)
	return l

func _build(npc_id: String, who: String, text: String, emotion: int, body: int,
		pos := POS_CENTER) -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	var vis := _vis()

	var blocker := Control.new()
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_tap())
	add_child(blocker)

	var box := NinePatchRect.new()
	box.texture = load(DIALOG_BOX)
	box.patch_margin_left = 10; box.patch_margin_right = 10
	box.patch_margin_top = 4; box.patch_margin_bottom = 4
	box.size = Vector2(vis.x - 20.0, BOX_H)
	box.position = Vector2(10.0, vis.y - BOX_H + BOX_DY)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.z_index = BOX_Z
	add_child(box)
	_box = box
	var bt := box.create_tween()
	bt.tween_interval(IN_DELAY)
	bt.tween_property(box, "position:y", vis.y - BOX_H, IN_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_name = Label.new()
	_name.text = who
	_name.add_theme_font_size_override("font_size", 22)
	_name.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_name.position = Vector2(20.0, 8.0)
	_name.size = Vector2(box.size.x - 90.0, 28.0)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_name)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.position = Vector2(20.0, 38.0)
	_label.size = Vector2(box.size.x - 75.0, BOX_H - 46.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_label)

	if ResourceLoader.exists(ARROW):
		_arrow = Sprite2D.new()
		_arrow.texture = load(ARROW)
		_arrow.material = _pma
		_arrow.position = Vector2(box.size.x - 35.0, BOX_H * 0.5)
		_arrow.visible = false
		box.add_child(_arrow)

	set_talker(npc_id, who, pos, emotion, body, true, false)
	set_text(text)

func set_talker(npc_id: String, who: String, pos := POS_CENTER, emotion := 1, body := 1,
		first_show := true, start_small := false) -> void:
	set_speaker(who)
	if npc_id == "":
		return
	var vis := _vis()
	var slot: Dictionary = _slots.get(pos, {})
	var p: NpcPortrait = slot.get("node", null)
	var fresh := false
	if p == null or not is_instance_valid(p) or String(slot.get("npc", "")) != npc_id \
			or int(slot.get("body", 0)) != body:
		if p != null and is_instance_valid(p):
			p.queue_free()
		p = NpcPortrait.create(npc_id, maxi(emotion, 1), maxi(body, 1))
		if p == null:
			return
		add_child(p)
		fresh = true
	else:
		p.set_emotion(maxi(emotion, 1))
	if _portrait != null and is_instance_valid(_portrait) and _portrait != p:
		_portrait.set_talking(false)
	_slots[pos] = {"npc": npc_id, "body": body, "node": p}
	_portrait = p

	var home := _slot_home(p, npc_id, pos, vis)
	var flip := -1.0 if pos == POS_LEFT else 1.0
	if fresh:
		p.position = home
		p.scale = Vector2(flip * (SCALE_SMALL if start_small else SCALE_NORMAL),
			SCALE_SMALL if start_small else SCALE_NORMAL)
	for other_pos: int in _slots:
		if other_pos == pos:
			continue
		var o: NpcPortrait = (_slots[other_pos] as Dictionary).get("node", null)
		if o == null or not is_instance_valid(o):
			continue
		var of := signf(o.scale.x)
		var ot := o.create_tween()
		ot.tween_interval(SCALE_UP_TIME)
		ot.tween_property(o, "scale", Vector2(of * SCALE_SMALL, SCALE_SMALL), SCALE_UP_TIME)

	var t := p.create_tween()
	if fresh and first_show:
		var from := home
		var dur := SIDE_IN_TIME
		var trans := Tween.TRANS_BACK
		var ease := Tween.EASE_OUT
		match pos:
			POS_LEFT:
				from.x -= vis.x * 0.5
			POS_RIGHT:
				from.x += vis.x * 0.5
			_:
				from.y += p.body_height()
				dur = CENTER_IN_TIME
				trans = Tween.TRANS_EXPO
				ease = Tween.EASE_IN_OUT
		p.position = from
		if not _opened:
			t.tween_interval(IN_DELAY)
		t.tween_property(p, "position", home, dur).set_trans(trans).set_ease(ease)
	else:
		t.tween_interval(SCALE_UP_TIME)
	t.tween_property(p, "scale", Vector2(flip * SCALE_POP, SCALE_POP), SCALE_UP_TIME)
	t.tween_property(p, "scale", Vector2(flip * SCALE_NORMAL, SCALE_NORMAL), SCALE_SETTLE_TIME)
	_opened = true

func _slot_home(p: NpcPortrait, npc_id: String, pos: int, vis: Vector2) -> Vector2:
	var half_w: float = p.body_width() * 0.5
	var extra: float = float(NPC_X_EXTRA.get(npc_id, 0.0))
	var y: float = vis.y - float(NPC_Y_OFFSET.get(npc_id, 0.0))
	match pos:
		POS_LEFT:
			return Vector2(half_w + SIDE_MARGIN + extra, y)
		POS_RIGHT:
			return Vector2(vis.x - half_w - SIDE_MARGIN + extra, y)
	return Vector2(vis.x * 0.5, y)

func set_text(text: String) -> void:
	_full = text
	_shown = 0.0
	_typing = true
	_label.text = ""
	if _portrait != null and is_instance_valid(_portrait):
		_portrait.set_talking(true)
	_stop_arrow_tween()
	if _arrow != null:
		_arrow.visible = false

func set_speaker(who: String) -> void:
	if _name != null:
		_name.text = who

func set_choices(labels: Array) -> void:
	clear_choices()
	var vis := _vis()
	_choice_row = Control.new()
	_choice_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_choice_row.z_index = BOX_Z
	add_child(_choice_row)
	var n := labels.size()
	var w := 200.0
	var gap := 28.0
	var total := n * w + (n - 1) * gap
	var y := vis.y - BOX_H - 40.0
	for i in n:
		var b := _button(String(labels[i]))
		b.size = Vector2(w, 52.0)
		b.position = Vector2(vis.x * 0.5 - total * 0.5 + i * (w + gap), y - 26.0)
		var idx := i
		b.pressed.connect(func(): chosen.emit(idx))
		_choice_row.add_child(b)

func clear_choices() -> void:
	if _choice_row != null and is_instance_valid(_choice_row):
		_choice_row.queue_free()
	_choice_row = null

func close() -> void:
	queue_free()

func _process(delta: float) -> void:
	if not _typing:
		return
	_shown += delta * CPS
	var n := mini(int(_shown), _full.length())
	_label.text = _full.substr(0, n)
	if n >= _full.length():
		_typing = false
		if _portrait != null and is_instance_valid(_portrait):
			_portrait.set_talking(false)
		if _arrow != null:
			_stop_arrow_tween()
			_arrow.visible = true
			_arrow_tween = _arrow.create_tween().set_loops()
			_arrow_tween.tween_property(_arrow, "position:y", BOX_H * 0.5 + 6.0, 0.4).set_trans(Tween.TRANS_SINE)
			_arrow_tween.tween_property(_arrow, "position:y", BOX_H * 0.5, 0.4).set_trans(Tween.TRANS_SINE)

func _stop_arrow_tween() -> void:
	if _arrow_tween != null and _arrow_tween.is_valid():
		_arrow_tween.kill()
	_arrow_tween = null
	if is_instance_valid(_arrow):
		_arrow.position.y = BOX_H * 0.5

func _tap() -> void:
	if _typing:
		_typing = false
		_label.text = _full
		if _portrait != null and is_instance_valid(_portrait):
			_portrait.set_talking(false)
		if _arrow != null:
			_stop_arrow_tween()
			_arrow.visible = true
		return
	if _choice_row != null and is_instance_valid(_choice_row):
		return
	advanced.emit()

func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 20)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.36, 0.22, 0.09)
		if st == "hover":
			sb.bg_color = Color(0.46, 0.30, 0.13)
		elif st == "pressed":
			sb.bg_color = Color(0.28, 0.16, 0.06)
		sb.set_corner_radius_all(26)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.86, 0.72, 0.42, 0.9)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color(1, 0.95, 0.82))
	return b

func _vis() -> Vector2:
	return get_viewport().get_visible_rect().size
