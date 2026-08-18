class_name MatchingWait
extends Control

const WAIT_SPINE := "res://scenes/fx/colosseum_waiting.tscn"
const DIM_ALPHA := 200.0 / 255.0
const DIM_SEC := 0.5
const PULSE_SEC := 0.1
const PULSE := [Vector2(0.9, 1.1), Vector2(1.1, 0.9), Vector2(1.0, 1.0)]
const LABEL_DY := 125.0
const LABEL_DELAY := 0.5
const LABEL_FADE := 0.4
const LABEL_SIZE := 26

var _on_done := Callable()
var _sec := 3.0

static func open(host: Node, sec: float, on_done: Callable) -> MatchingWait:
	var m := MatchingWait.new()
	m._sec = sec
	m._on_done = on_done
	host.add_child(m)
	return m

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 4096
	var vis := Vector2(size) if size.length() > 1.0 else _vis()
	var center := vis * 0.5

	set_anchors_preset(Control.PRESET_TOP_LEFT)
	size = vis
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.position = Vector2.ZERO
	dim.size = vis
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	create_tween().tween_property(dim, "color:a", DIM_ALPHA, DIM_SEC)

	if ResourceLoader.exists(WAIT_SPINE):
		var holder := Node2D.new()
		holder.position = center
		add_child(holder)
		holder.add_child((load(WAIT_SPINE) as PackedScene).instantiate())
		var ap := _find_anim_player(holder)
		if ap != null:
			var anims := ap.get_animation_list()
			if anims.size() > 0:
				ap.get_animation(anims[0]).loop_mode = Animation.LOOP_LINEAR
				ap.play(anims[0])
		var pulse := holder.create_tween().set_loops()
		for p: Vector2 in PULSE:
			pulse.tween_property(holder, "scale", p, PULSE_SEC)

	var lab := Label.new()
	lab.text = String(Data.colosseum.get("log", {}).get("matching", Data.ui("#0c7cd7c3")))
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.size = Vector2(vis.x, 40.0)
	lab.position = Vector2(0.0, center.y + LABEL_DY - 20.0)
	lab.modulate.a = 0.0
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := _bmfont("font_subtitle")
	if f != null:
		lab.add_theme_font_override("font", f)
	lab.add_theme_font_size_override("font_size", LABEL_SIZE)
	add_child(lab)
	var lt := create_tween()
	lt.tween_interval(LABEL_DELAY)
	lt.tween_property(lab, "modulate:a", 1.0, LABEL_FADE)

	Bgm.sfx("effect_colo_waiting")

	await get_tree().create_timer(maxf(0.1, _sec)).timeout
	if not is_instance_valid(self):
		return
	var cb := _on_done
	queue_free()
	if cb.is_valid():
		cb.call()

func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null

func _bmfont(name: String) -> FontFile:
	var path := "res://assets/converted/font_ui/%s.fnt" % name
	if not ResourceLoader.exists(path):
		return null
	var f: FontFile = load(path).duplicate()
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Gulim"])
	f.fallbacks = [fb]
	return f

func _vis() -> Vector2:
	return get_viewport_rect().size
