class_name CounterButton
extends Node2D

const DIR := "adventure_ui"
const BTN_PX := Vector2(262.0, 94.0)
const T_LONG := 0.3
const T_SHORT := 0.12
const LAP := 1.98

signal fired
signal cancelled

const _SEGS: Array = [
	["glow_width",     Vector2(1, 1), T_LONG],
	["glow_lefttop",   Vector2(1, 1), T_SHORT],
	["glow_length",    Vector2(0, 1), T_LONG * 0.5],
	["glow_leftdown",  Vector2(0, 1), T_SHORT],
	["glow_width",     Vector2(0, 0), T_LONG],
	["glow_width",     Vector2(0, 0), T_LONG],
	["glow_rightdown", Vector2(0, 0), T_SHORT],
	["glow_length",    Vector2(1, 0), T_LONG * 0.5],
	["glow_righttop",  Vector2(1, 0), T_SHORT],
	["glow_width",     Vector2(1, 1), T_LONG],
]

var _label_key := ""
var _auto := false
var _running := false
var _fired := false
var _segs: Array = []
var _dot: Node2D
var _base: Node2D
var _hot: Node2D

static func make(label_key: String, auto: bool) -> CounterButton:
	var b := CounterButton.new()
	b._label_key = label_key
	b._auto = auto
	return b

func _ready() -> void:
	_build()
	if _auto:
		start()

func size_points() -> Vector2:
	return BTN_PX * Design.ASSET_SCALE

func _build() -> void:
	var S := Design.ASSET_SCALE
	var sz := BTN_PX * S
	_base = AtlasUI.spr_cocos(DIR, "scene_adventure_btn2", 1.0)
	if _base:
		add_child(_base)
	_hot = AtlasUI.spr_cocos(DIR, "scene_adventure_btn3", 1.0)
	if _hot:
		_hot.modulate.a = 1.0 if _auto else 0.0
		add_child(_hot)
	if _label_key != "":
		var lb := AtlasUI.spr_cocos(DIR, _label_key, 1.0)
		if lb:
			lb.z_index = 1
			add_child(lb)
	_build_glow()
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.size = sz
	hit.position = -sz * 0.5
	hit.button_down.connect(_on_down)
	hit.pressed.connect(_on_press)
	add_child(hit)

func _build_glow() -> void:
	var S := Design.ASSET_SCALE
	var man := AtlasUI.manifest(DIR)
	var W := BTN_PX.x * S
	var H := BTN_PX.y * S
	var f := func(key: String) -> Vector2:
		var i: Dictionary = man.get("scene_adventure_" + key, {})
		return Vector2(float(i.get("w", 1)), float(i.get("h", 1))) * S
	var wid := f.call("glow_width") as Vector2
	var lt := f.call("glow_lefttop") as Vector2
	var ln := f.call("glow_length") as Vector2
	var ld := f.call("glow_leftdown") as Vector2
	var rd := f.call("glow_rightdown") as Vector2
	var rt := f.call("glow_righttop") as Vector2
	var pos: Array = [
		Vector2(W * 0.5, H + 5.0),
		Vector2(W * 0.5 - wid.x, H + 5.0),
		Vector2(W * 0.5 - wid.x - lt.x, H - lt.y + 6.0),
		Vector2(-6.5, ld.y - 1.0),
		Vector2(ld.x - 7.0, -1.0),
		Vector2(ld.x + wid.x - 8.0, -1.0),
		Vector2(W * 0.5 + wid.x - 2.0, -1.0),
		Vector2(W * 0.5 + wid.x + lt.x, rd.y - 2.0),
		Vector2(W + 7.0, H - rt.y + 5.0),
		Vector2(W - rt.x + 7.5, H + 5.0),
	]
	for i in _SEGS.size():
		var row: Array = _SEGS[i]
		var n := AtlasUI.spr_cocos(DIR, "scene_adventure_" + String(row[0]), 1.0, row[1])
		if n == null:
			continue
		n.name = "Glow%d" % i
		n.position = _local(pos[i])
		n.scale = Vector2.ZERO
		n.modulate.a = 0.0
		add_child(n)
		_segs.append(n)
	_dot = AtlasUI.spr_cocos(DIR, "scene_adventure_glow_automode", 1.0)
	if _dot:
		_dot.name = "GlowDot"
		_dot.position = _local(pos[0] - Vector2(0.0, 4.0))
		_dot.modulate.a = 0.0
		_dot.z_index = 2
		add_child(_dot)

func _local(p: Vector2) -> Vector2:
	var S := Design.ASSET_SCALE
	return Vector2(p.x - BTN_PX.x * S * 0.5, BTN_PX.y * S * 0.5 - p.y)

func start() -> void:
	if _running or _fired:
		return
	_running = true
	_line_start()
	_point_start()

func stop() -> void:
	_running = false
	for n in _segs:
		var s := n as Node2D
		if not is_instance_valid(s):
			continue
		_kill_tweens(s)
		s.create_tween().tween_property(s, "modulate:a", 0.0, 0.2)
	if is_instance_valid(_dot):
		_kill_tweens(_dot)
		_dot.create_tween().tween_property(_dot, "modulate:a", 0.0, 0.2)

func _kill_tweens(n: Node) -> void:
	var tw = n.get_meta("cb_tween", null)
	if tw is Tween and (tw as Tween).is_valid():
		(tw as Tween).kill()

func _line_start() -> void:
	var delay := 0.0
	for i in _segs.size():
		var n := _segs[i] as Node2D
		if not is_instance_valid(n):
			continue
		var row: Array = _SEGS[i]
		var dur := float(row[2])
		n.modulate.a = 1.0
		n.scale = Vector2(0.0, 1.0) if i == 0 else Vector2.ZERO
		var tw := n.create_tween()
		n.set_meta("cb_tween", tw)
		if delay > 0.0:
			tw.tween_interval(delay)
		tw.tween_property(n, "scale", Vector2.ONE, dur)
		if i == _segs.size() - 1:
			tw.tween_callback(_on_lap_done)
		delay += dur

func _point_start() -> void:
	if not is_instance_valid(_dot):
		return
	var S := Design.ASSET_SCALE
	var man := AtlasUI.manifest(DIR)
	var wid := float((man.get("scene_adventure_glow_width", {}) as Dictionary).get("w", 113)) * S
	var lenh := float((man.get("scene_adventure_glow_length", {}) as Dictionary).get("h", 56)) * S
	var legs: Array = [
		[Vector2(-wid, 0.0), T_LONG],
		[Vector2(-26.0, 30.0), T_SHORT],
		[Vector2(0.0, lenh), T_LONG * 0.5],
		[Vector2(26.0, 20.0), T_SHORT],
		[Vector2(wid, 0.0), T_LONG],
		[Vector2(wid, 0.0), T_LONG],
		[Vector2(28.0, -20.0), T_SHORT],
		[Vector2(0.0, -lenh), T_LONG * 0.5],
		[Vector2(-28.0, -30.0), T_SHORT],
		[Vector2(-wid, 0.0), T_LONG],
	]
	_dot.create_tween().tween_property(_dot, "modulate:a", 1.0, 0.2)
	var tw := _dot.create_tween()
	_dot.set_meta("cb_tween", tw)
	var p := _dot.position
	for i in legs.size():
		var leg: Array = legs[i]
		p += leg[0] as Vector2
		var t := tw.tween_property(_dot, "position", p, float(leg[1]))
		if i == legs.size() - 1:
			t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_lap_done() -> void:
	if _fired or not _running:
		return
	_fired = true
	_running = false
	fired.emit()

func _on_down() -> void:
	if is_instance_valid(_base):
		_base.create_tween().tween_property(_base, "scale", Vector2(1.05, 1.05), 0.05)

func _on_press() -> void:
	if is_instance_valid(_base):
		_base.create_tween().tween_property(_base, "scale", Vector2.ONE, 0.05)
	if _fired:
		return
	if _running:
		stop()
		if is_instance_valid(_hot):
			_hot.create_tween().tween_property(_hot, "modulate:a", 0.0, 0.2)
		cancelled.emit()
		return
	_fired = true
	fired.emit()
