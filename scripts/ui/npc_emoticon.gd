class_name NpcEmoticon
extends Node2D

const DIR := "npc_emoticon"
const SINK := 60.0
const FRAME_SEC := 0.4

const NUDGE := Vector2(-90.0, -90.0)

const SMILE_EMOTION := {"annie": 2}

var _icon: Sprite2D
var _frames: Array[Texture2D] = []
var _t := 0.0

static func show_on(portrait: NpcPortrait, no: int) -> NpcEmoticon:
	if portrait == null or no <= 0:
		return null
	if SMILE_EMOTION.has(portrait.npc_name) and portrait.emotion != int(SMILE_EMOTION[portrait.npc_name]):
		return null
	for c in portrait.get_children():
		if c is NpcEmoticon:
			c.queue_free()
	var e := NpcEmoticon.new()
	e._build(no, portrait.body_height(), portrait.body_width())
	if e._icon == null:
		e.queue_free()
		return null
	portrait.add_child(e)
	e._play()
	return e

func _build(no: int, body_h: float, body_w: float) -> void:
	var S := Design.ASSET_SCALE
	position = Vector2(-body_w * 0.42, -body_h * 0.74) + NUDGE
	var balloon := AtlasUI.spr(DIR, "npc_emoticon_balloon", S)
	if balloon != null:
		add_child(balloon)
	_frames = _load_frames(no)
	if _frames.is_empty():
		return
	_icon = Sprite2D.new()
	_icon.texture = _frames[0]
	_icon.material = AtlasUI.pma()
	_icon.scale = Vector2(S, S)
	add_child(_icon)

func _load_frames(no: int) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var single := AtlasUI.tex(DIR, "npc_emoticon_%d" % no)
	if single != null:
		out.append(single)
		return out
	for k in range(1, 6):
		var t := AtlasUI.tex(DIR, "npc_emoticon_%d_%d" % [no, k])
		if t == null:
			break
		out.append(t)
	return out

func _play() -> void:
	scale = Vector2.ZERO
	var tw := create_tween()
	tw.tween_interval(0.3)
	tw.tween_property(self, "scale", Vector2(1.5, 1.5), 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.4)
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.2, 1.2), 1.2)
	tw.tween_property(self, "position:y", position.y + SINK, 0.8)
	tw.tween_property(self, "modulate:a", 0.0, 1.2).set_delay(0.4)
	tw.set_parallel(false)
	tw.tween_interval(0.4)
	tw.tween_callback(queue_free)

func _process(delta: float) -> void:
	if _frames.size() < 2 or _icon == null:
		return
	_t += delta
	_icon.texture = _frames[int(_t / FRAME_SEC) % _frames.size()]
