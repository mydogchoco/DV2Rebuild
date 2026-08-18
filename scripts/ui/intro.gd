extends Control

const STATUS_AX := 0.85
const STATUS_Y := 80.0
const BAR_H := 50.0
const BAR_ALPHA := 125.0 / 255.0
const VER_AX := 0.05
const VER_Y := 30.0
const COPYRIGHT := "Dragon Village @ highbrow, published by Ocon"
const VERSION_TEXT := "5.1.1 (offline reimpl)"
const FONT := "res://assets/converted/font_ui/font_common.fnt"

const UI := "intro_ui"
const TITLE_SPINE := "res://scenes/fx/intro_title_spine.tscn"

const PREF_KEY := "title_screen"
const OLD_BG := "intro_old_bg"
const OLD_BG_KEY := "intro_intro_dragon_intro_dragon"
const OLD_CLOUD := "intro_old_cloud"
const OLD_CLOUD_KEY := "intro_intro_cloud_intro_cloud"
const CANVAS := Vector2(768.0, 519.0)
const SKY := "res://assets/converted/intro_old_bg/loag_main_bg.jpg"
const LOGO_INSET := Vector2(55.0, 70.0)
const LOGO_SCALE := 0.75
const CLOUD_DRIFT := 5.0
const CLOUD_PERIOD := 5.0

var _status_anchor := Vector2.INF
var _ready_to_start := false
var _started := false

func enter(_params: Dictionary = {}) -> void:
	pass

func _ready() -> void:
	Bgm.play("bg_intro")
	_build()

func _build() -> void:
	var vis := _vis()

	var back := ColorRect.new()
	back.color = Color(0, 0, 0)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.z_index = -30
	add_child(back)

	if String(UserDB.get_pmeta(PREF_KEY, "2020")) == "old":
		_build_title_old(vis)
	else:
		_build_title(vis)
	_build_copyright(vis)
	_build_start_prompt(vis)

func _build_title(vis: Vector2) -> void:
	if not ResourceLoader.exists(TITLE_SPINE):
		push_warning("[Intro] 타이틀 스파인 없음 — 인트로 자산이 DV2/ 에 준비돼 있어야 한다")
		return
	var holder := Node2D.new()
	holder.position = vis * 0.5
	holder.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	holder.z_index = -20
	add_child(holder)
	var inst := (load(TITLE_SPINE) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
	if ap != null and ap.has_animation("animation"):
		ap.get_animation("animation").loop_mode = Animation.LOOP_LINEAR
		ap.play("animation")

func _build_title_old(vis: Vector2) -> void:
	var sky_tex := load(SKY) if ResourceLoader.exists(SKY) else null
	if sky_tex != null:
		var sky := Sprite2D.new()
		sky.texture = sky_tex
		sky.position = vis * 0.5
		var ss: float = maxf(vis.x / sky_tex.get_width(), vis.y / sky_tex.get_height())
		sky.scale = Vector2(ss, ss)
		sky.z_index = -25
		add_child(sky)

	var stage := Node2D.new()
	stage.position = vis * 0.5
	var s: float = maxf(vis.x / CANVAS.x, vis.y / CANVAS.y)
	stage.scale = Vector2(s, s)
	stage.z_index = -20
	add_child(stage)

	var bg := AtlasUI.spr(OLD_BG, OLD_BG_KEY, 1.0)
	if bg == null:
		push_warning("[Intro] 구판 배경 없음 — 인트로 자산이 DV2/ 에 준비돼 있어야 한다")
		return
	stage.add_child(bg)

	var cloud := AtlasUI.spr(OLD_CLOUD, OLD_CLOUD_KEY, 1.0)
	if cloud != null:
		var off: Array = AtlasUI.manifest(OLD_CLOUD).get(OLD_CLOUD_KEY, {}).get("off", [0, 0])
		cloud.position = Vector2(float(off[0]), -float(off[1]))
		stage.add_child(cloud)
		stage.move_child(cloud, 0)
		var drift := create_tween().set_loops()
		drift.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		drift.tween_property(cloud, "position:y",
			cloud.position.y + CLOUD_DRIFT, CLOUD_PERIOD)
		drift.tween_property(cloud, "position:y",
			cloud.position.y, CLOUD_PERIOD)

	var logo := AtlasUI.spr(UI, "intro_intro_logo_kr", LOGO_SCALE * Design.ASSET_SCALE)
	if logo != null:
		var sz := AtlasUI.size_pt(UI, "intro_intro_logo_kr") * LOGO_SCALE
		var logo_bottom := LOGO_INSET.y * (vis.y / Design.DESIGN_HEIGHT)
		logo.position = Vector2(
			vis.x - LOGO_INSET.x * (vis.x / Design.REF_WIDTH) - sz.x * 0.5,
			Design.flip_y(logo_bottom, vis.y) - sz.y * 0.5)
		add_child(logo)
		_status_anchor = Vector2(logo.position.x, logo_bottom - 35.0)

func _build_copyright(vis: Vector2) -> void:
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, BAR_ALPHA)
	bar.position = Vector2(0.0, vis.y - BAR_H)
	bar.size = Vector2(vis.x, BAR_H)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	var ver := _bm_label(VERSION_TEXT, 17 * 1.2)
	ver.position = Vector2(vis.x * VER_AX, Design.flip_y(VER_Y, vis.y) - ver.size.y * 0.5)
	add_child(ver)

	var cr := _bm_label(COPYRIGHT, 17 * 1.1)
	cr.position = ver.position + Vector2(ver.size.x + 20.0, -4.0)
	add_child(cr)

	var grb := AtlasUI.spr(UI, "intro_grb_all", Design.ASSET_SCALE)
	if grb != null:
		var sz := AtlasUI.size_pt(UI, "intro_grb_all")
		grb.position = Vector2(vis.x - 10.0 - sz.x * 0.5, 10.0 + sz.y * 0.5)
		add_child(grb)

func _build_start_prompt(vis: Vector2) -> void:
	var plate := AtlasUI.spr(UI, "intro_txt_bg", Design.ASSET_SCALE)
	if plate == null:
		return
	var anchor := _status_anchor
	if anchor == Vector2.INF:
		anchor = Vector2(vis.x * STATUS_AX, STATUS_Y)
	var end_pos := Vector2(anchor.x + 20.0, Design.flip_y(anchor.y, vis.y))
	plate.position = Vector2(end_pos.x, vis.y)
	plate.modulate.a = 0.0
	add_child(plate)

	var txt := AtlasUI.spr(UI, "intro_txt_start_kr", 1.0)
	if txt != null:
		txt.position = Vector2(-20.0 / Design.ASSET_SCALE, 0.0)
		txt.modulate.a = 0.0
		plate.add_child(txt)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(plate, "modulate:a", 1.0, 0.7)
	tw.tween_property(plate, "position", end_pos, 0.8) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	if txt != null:
		var blink := create_tween().set_loops()
		blink.tween_interval(0.7)
		blink.tween_property(txt, "modulate:a", 1.0, 0.7)
		blink.tween_property(txt, "modulate:a", 0.0, 0.7)

	_ready_to_start = true

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		accept_event()
		_try_start()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		_try_start()

func _try_start() -> void:
	if _ready_to_start and not _started:
		_start()

func _start() -> void:
	_started = true
	var app := get_tree().current_scene
	if app != null and app.has_method("begin_new_game"):
		app.call("begin_new_game")
	else:
		push_warning("[Intro] Main.begin_new_game 없음 — 메인 화면으로만 이동한다")
		Scenes.goto("worldmap", {"region": "yutakan"})

func _bm_label(text: String, size: float) -> Label:
	var l := Label.new()
	l.text = text
	var f := load(FONT) if ResourceLoader.exists(FONT) else null
	if f is FontFile:
		(f as FontFile).fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", int(round(size)))
	l.add_theme_color_override("font_color", Color.WHITE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.reset_size()
	return l

func _vis() -> Vector2:
	return get_viewport_rect().size
