class_name StatResetView
extends Node

const CONTENT_END_Y := -50.0
const SLIDE_SECS := 0.5
const DIM_ALPHA := 200.0 / 255.0
const ROLL_TICK := 0.05
const ROLL_START := 0.3
const ROLL_END := 1.8
const FLASH_DELAY := 1.5
const FLASH_IN := 0.3
const FLASH_HOLD := 0.5
const FLASH_OUT := 0.3

const GEM_CAP := Rect2(20, 20, 2, 2)
const GEM_BOX := Vector2(70.0, 70.0)
const GEM_PITCH := 76.0
const SKILL_PITCH := 84.0
const SLOT_DX := 200.0

const GEM_FRAME := {"ATT": "9patch_gem_red_bg", "DEF": "9patch_gem_blue_bg",
	"HP": "9patch_gem_yellow_bg", "ALL": "9patch_gem_white_bg"}
const SKILL_FRAME := {"tri": "common_skill_triangle_bg", "sq": "common_skill_square_bg",
	"cir": "common_skill_circle_bg", "star": "common_skill_star_bg"}

const GEM_ROLL_WEIGHT := ["9patch_gem_blue_bg", "9patch_gem_blue_bg", "9patch_gem_blue_bg",
	"9patch_gem_red_bg", "9patch_gem_red_bg", "9patch_gem_red_bg",
	"9patch_gem_yellow_bg", "9patch_gem_yellow_bg", "9patch_gem_yellow_bg",
	"9patch_gem_white_bg"]
const SKILL_ROLL_WEIGHT := ["common_skill_circle_bg", "common_skill_circle_bg", "common_skill_circle_bg",
	"common_skill_square_bg", "common_skill_square_bg", "common_skill_square_bg",
	"common_skill_triangle_bg", "common_skill_triangle_bg", "common_skill_triangle_bg",
	"common_skill_star_bg"]

const STAGE_ADJ := {
	"baby":  {"dy": 40.0, "stand": 70.0, "shadow": 0.9},
	"child": {"dy": 35.0, "stand": 78.0, "shadow": 1.3},
	"adult": {"dy": 30.0, "stand": 78.0, "shadow": 1.5}}

const STAND_COUNT := 16
const S1080 := 692.0 / 1080.0

static func open(host: Node, uid: int, kind: String, on_close := Callable(),
		stage_node: Node = null) -> StatResetView:
	var s := StatResetView.new()
	s._uid = uid
	s._kind = kind
	s._on_close = on_close
	s._host_stage = stage_node
	host.add_child(s)
	return s

var _uid := 0
var _kind := "gem"
var _on_close := Callable()
var _host_stage: Node = null

var _vis := Vector2.ZERO
var _layer: CanvasLayer
var _dim: ColorRect
var _content: Control
var _rollers: Array[Control] = []
var _finals: Array[Control] = []
var _particles: Array[CPUParticles2D] = []
var _roll_accum := 0.0
var _rolling := false
var _msg: Label
var _closing := false

func _ready() -> void:
	_vis = get_viewport().get_visible_rect().size
	_build()

func _gp(cocos: Vector2) -> Vector2:
	return Vector2(cocos.x, _vis.y - cocos.y)

func _center() -> Vector2:
	return _vis * 0.5

func _build() -> void:
	var d := UserDB.get_dragon(_uid)
	if d.is_empty():
		_finish(); return

	_layer = CanvasLayer.new()
	_layer.layer = 60
	add_child(_layer)
	if is_instance_valid(_host_stage):
		_host_stage.visible = false
		_layer.tree_exited.connect(func():
			if is_instance_valid(_host_stage): _host_stage.visible = true)

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_dim)
	_dim.create_tween().tween_property(_dim, "color:a", DIM_ALPHA, SLIDE_SECS)

	_content = Control.new()
	_content.size = _vis
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.position = Vector2(0, -_vis.y)
	_layer.add_child(_content)
	var slide := _content.create_tween()
	slide.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
	slide.tween_property(_content, "position:y", -CONTENT_END_Y, SLIDE_SECS)

	_build_dragon(d)
	_build_name(d)
	_build_check_button()
	if _kind == "gem":
		_reset_gem_effect(d)
	else:
		_reset_skill_effect(d)
	_build_flash()

func _build_dragon(d: Dictionary) -> void:
	var stage := Growth.stage_for_level(int(d.get("level", 1)))
	var adj: Dictionary = STAGE_ADJ.get(stage, STAGE_ADJ["adult"])
	var spine_c := Vector2(_vis.x * 0.29, _vis.y * 0.5 + 40.0 + float(adj["dy"]))
	var stand_c := spine_c - Vector2(0, float(adj["stand"]))
	var shadow_c := stand_c - Vector2(0, 30.0)

	var sh := AtlasUI.spr("common_ui", "common_shadow", Design.ASSET_SCALE * float(adj["shadow"]))
	if sh != null:
		sh.position = _gp(shadow_c)
		sh.modulate = Color(1, 1, 1, 0.55)
		_content.add_child(sh)

	var holder := Node2D.new()
	holder.scale = Vector2(S1080, S1080)
	holder.position = _gp(stand_c)
	_content.add_child(holder)
	var sman := AtlasUI.manifest("stand_ui")
	var si: int = UserDB.get_skin("stand_skin") % STAND_COUNT
	var skey := "stand_stand%d" % (si + 1)
	var info: Dictionary = sman.get(skey, {})
	var pw: float = maxf(1.0, float(info.get("w", 305)))
	var ph: float = maxf(1.0, float(info.get("h", 120)))
	var psc := 620.0 / pw
	var ped := AtlasUI.spr("stand_ui", skey, psc)
	if ped != null:
		holder.add_child(ped)
	var rel := -7.0 - (357.0 - ph * psc / 2.0)
	if UserDB.is_egg(d):
		return
	var path := Icons.spine_scene(Icons.art_id_of(d), stage)
	if path == "":
		return
	var d2 := Node2D.new()
	d2.scale = Vector2(1.9, 1.9)
	d2.position = Vector2(0, rel)
	holder.add_child(d2)
	var inst = load(path).instantiate()
	d2.add_child(inst)
	var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
	if ap != null and ap.has_animation("wait"):
		ap.play("wait")
	if Growth.is_aura_adult(int(d.get("level", 1))):
		_build_aura(holder, String(Data.get_dragon(int(d.get("id", 0))).get("element", "")), rel)

func _build_aura(holder: Node2D, element: String, rel: float) -> void:
	if element == "":
		return
	var frames: Array = []
	for i in range(1, 10):
		var p := "res://assets/converted/aura_ui/dragon_aura_%s_aura%02d.tres" % [element, i]
		if ResourceLoader.exists(p):
			frames.append(load(p))
	if frames.is_empty():
		return
	var spr := Sprite2D.new()
	var addmat := CanvasItemMaterial.new()
	addmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	spr.material = addmat
	spr.scale = Vector2(1.5, 1.5)
	spr.position = Vector2(0, rel)
	spr.z_index = -1
	holder.add_child(spr)
	var tw := spr.create_tween().set_loops()
	for t in frames:
		var ft: Texture2D = t
		tw.tween_callback(func(): spr.texture = ft)
		tw.tween_interval(0.1)

func _build_name(d: Dictionary) -> void:
	var nm := Icons.name_of(d)
	var nl := Label.new()
	nl.text = nm
	nl.add_theme_font_size_override("font_size", 33)
	nl.add_theme_color_override("font_color", Color.WHITE)
	nl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	nl.add_theme_constant_override("outline_size", 5)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nw := nl.get_theme_font("font").get_string_size(
		nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 33).x
	var npos := _gp(_center() + Vector2(SLOT_DX, 175.0))
	nl.size = Vector2(nw, 40.0)
	nl.position = npos - nl.size * 0.5
	_content.add_child(nl)

	var rl := Label.new()
	rl.text = "%.1f" % _grade_of(d)
	_bm_style(rl, 30, Color(1, 0.68, 0.16), "font_rating")
	rl.size = Vector2(90.0, 36.0)
	rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rl.position = npos + Vector2(nw * 0.5 + 15.0, -5.0 - 18.0)
	rl.modulate.a = 0.0
	_content.add_child(rl)
	rl.create_tween().tween_property(rl, "modulate:a", 1.0, 0.5)

func _grade_of(d: Dictionary) -> float:
	return Growth.compute_grade(Data.get_dragon(int(d.get("id", 0))), Data.stat_table,
		d.get("stat_bonus", {}), d.get("gain_log", []), Data.level_curve.get("grade", {}))

func _build_check_button() -> void:
	var b := TextureButton.new()
	var t := AtlasUI.tex("common_ui", "common_check_btn")
	var sz := Vector2(66.0, 57.0)
	if t != null:
		b.texture_normal = t
		b.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 1.5
		sz = AtlasUI.size_pt("common_ui", "common_check_btn") * 1.5
	b.position = _gp(Vector2(_vis.x * 0.9, _vis.y * 0.95)) - sz * 0.5
	b.modulate.a = 0.0
	b.disabled = true
	b.pressed.connect(_close)
	_content.add_child(b)
	var tw := b.create_tween()
	tw.tween_interval(ROLL_END)
	tw.tween_callback(func(): b.disabled = false)
	tw.tween_property(b, "modulate:a", 1.0, FLASH_IN)

func _reset_gem_effect(d: Dictionary) -> void:
	_build_title(Data.ui("#01882329"))
	_msg = _build_msg(Data.ui("#f7c1a5e1"), 25)
	var types := Gem.types(d.get("gems", {}))
	for i in Gem.SLOTS:
		var c := Vector2(_vis.x * 0.5 + i * GEM_PITCH - GEM_PITCH + SLOT_DX, _vis.y * 0.5)
		var pos := _gp(c)
		var fin := _gem_box(String(types[i]))
		fin.position = pos - GEM_BOX * 0.5
		fin.visible = false
		_content.add_child(fin)
		_finals.append(fin)
		var ring := AtlasUI.spr("common_ui", "common_skill_circle_bg", Design.ASSET_SCALE)
		if ring != null:
			ring.position = pos + Vector2(0, 3.0)
			ring.modulate.a = 0.0
			ring.z_index = -1
			_content.add_child(ring)
			var rt := ring.create_tween()
			rt.tween_interval(ROLL_START)
			rt.tween_property(ring, "modulate:a", 1.0, 0.2)
		var roller := _gem_box(String(types[i]))
		roller.position = pos - GEM_BOX * 0.5
		_content.add_child(roller)
		_rollers.append(roller)
		var p := CocosParticle.spawn(_content, "reset_slot", pos - Vector2(0, 5.0), 1, 0.0, 90)
		if p != null:
			p.one_shot = false
			p.emitting = false
			p.scale = Vector2(1.07, 1.07)
			p.scale_amount_min = 0.06
			p.scale_amount_max = 0.40
			p.amount = 44
			_particles.append(p)
	_start_roll()

func _reset_skill_effect(d: Dictionary) -> void:
	_build_title("스킬 변경")
	_msg = _build_msg(Data.ui("#acc1b065"), 25)
	var types := Loadout.slot_types(d)
	for i in Loadout.SKILL_SLOTS:
		var c := Vector2(_vis.x * 0.5 - 42.0 + i * SKILL_PITCH + SLOT_DX, _vis.y * 0.5)
		var pos := _gp(c)
		var fin := _skill_box(String(types[i]))
		fin.position = pos - fin.size * 0.5
		fin.visible = false
		_content.add_child(fin)
		_finals.append(fin)
		var roller := _skill_box(String(types[i]))
		roller.position = pos - roller.size * 0.5
		_content.add_child(roller)
		_rollers.append(roller)
	_start_roll()

func _gem_box(ty: String) -> Control:
	var root := Control.new()
	root.size = GEM_BOX
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_meta("frame", String(GEM_FRAME.get(ty, "9patch_gem_white_bg")))
	var np := AtlasUI.nine("ninepatch_ui", String(root.get_meta("frame")), GEM_BOX, GEM_CAP)
	if np != null:
		np.name = "np"
		root.add_child(np)
	return root

func _skill_box(ty: String) -> Control:
	var key := String(SKILL_FRAME.get(ty, "common_skill_star_bg"))
	var root := Control.new()
	root.size = AtlasUI.size_pt("common_ui", key)
	if root.size == Vector2.ZERO:
		root.size = Vector2(86.0, 86.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := AtlasUI.spr("common_ui", key, Design.ASSET_SCALE)
	if s != null:
		s.name = "np"
		s.position = root.size * 0.5
		root.add_child(s)
	return root

func _set_roll_frame(box: Control, key: String) -> void:
	var n := box.get_node_or_null("np")
	if n == null:
		return
	if n is NinePatchRect:
		var t := AtlasUI.tex("ninepatch_ui", key)
		if t != null: (n as NinePatchRect).texture = t
	elif n is Sprite2D:
		var t2 := AtlasUI.tex("common_ui", key)
		if t2 != null: (n as Sprite2D).texture = t2

func _build_title(text: String) -> void:
	var l := Label.new()
	l.text = text
	_bm_style(l, 34, Color(1, 0.93, 0.15))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(420.0, 46.0)
	l.position = _gp(_center() + Vector2(SLOT_DX, 85.0)) - l.size * 0.5
	_content.add_child(l)

func _build_msg(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	_bm_style(l, size, Color(1, 1, 1), "font_common")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(720.0, 40.0)
	l.position = _gp(_center() + Vector2(SLOT_DX, -110.0)) - l.size * 0.5
	l.modulate.a = 0.0
	_content.add_child(l)
	return l

func _start_roll() -> void:
	var t := get_tree().create_timer(ROLL_START)
	t.timeout.connect(func():
		if not is_instance_valid(self): return
		_rolling = true
		for p in _particles:
			if is_instance_valid(p): p.emitting = true)
	var e := get_tree().create_timer(ROLL_END)
	e.timeout.connect(_settle)

func _process(delta: float) -> void:
	if not _rolling:
		return
	_roll_accum += delta
	while _roll_accum >= ROLL_TICK:
		_roll_accum -= ROLL_TICK
		_roll_tick()

func _roll_tick() -> void:
	var table := GEM_ROLL_WEIGHT if _kind == "gem" else SKILL_ROLL_WEIGHT
	for i in _rollers.size():
		var box := _rollers[i]
		if not is_instance_valid(box):
			continue
		_set_roll_frame(box, String(table[randi() % table.size()]))
		_shake(box)

func _shake(box: Control) -> void:
	var base: Vector2 = box.get_meta("home", box.position)
	box.set_meta("home", base)
	box.position = base + Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))

func _settle() -> void:
	if not is_instance_valid(self):
		return
	_rolling = false
	for r in _rollers:
		if is_instance_valid(r):
			r.queue_free()
	_rollers.clear()
	for f in _finals:
		if is_instance_valid(f):
			f.visible = true
	for p in _particles:
		if is_instance_valid(p):
			p.emitting = false
			p.queue_free()
	_particles.clear()
	if is_instance_valid(_msg):
		_msg.create_tween().tween_property(_msg, "modulate:a", 1.0, FLASH_IN)

func _build_flash() -> void:
	var f := ColorRect.new()
	f.color = Color(1, 1, 1, 0)
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(f)
	var tw := f.create_tween()
	tw.tween_interval(FLASH_DELAY)
	tw.tween_property(f, "color:a", 1.0, FLASH_IN)
	tw.tween_interval(FLASH_HOLD)
	tw.tween_property(f, "color:a", 0.0, FLASH_OUT)
	tw.tween_callback(f.queue_free)

func _close() -> void:
	if _closing:
		return
	_closing = true
	_rolling = false
	Bgm.sfx("effect_button")
	if is_instance_valid(_dim):
		_dim.create_tween().tween_property(_dim, "color:a", 0.0, SLIDE_SECS)
	if is_instance_valid(_content):
		var tw := _content.create_tween()
		tw.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(_content, "position:y", -CONTENT_END_Y - _vis.y, SLIDE_SECS)
		tw.tween_callback(_finish)
	else:
		_finish()

func _finish() -> void:
	if _on_close.is_valid():
		_on_close.call()
	queue_free()

static var _bmfonts: Dictionary = {}
func _bmfont(name: String) -> FontFile:
	if _bmfonts.has(name):
		return _bmfonts[name]
	var p := "res://assets/converted/font_ui/%s.fnt" % name
	if not ResourceLoader.exists(p):
		_bmfonts[name] = null
		return null
	var f: FontFile = load(p).duplicate()
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Gulim"])
	f.fallbacks = [fb]
	_bmfonts[name] = f
	return f

func _bm_style(l: Label, size: int, col: Color, font := "font_subtitle") -> void:
	var f := _bmfont(font)
	if f != null:
		l.add_theme_font_override("font", f)
	else:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 5 if size >= 24 else 4)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
