extends SceneTree
## 콜로세움 피해 수치 + 노란 별 육안 대조판.
##
## 원작 `MakeInterface::showDamage`(폰트 3종·낱타/누계 두 층)와 `damagedEffect`(오각별 파티클)를
## 레퍼런스 영상과 나란히 보기 위한 캡처 창.
## 근거·수치 = `docs/ref/porting/ColosseumDamageNumber.md`.
##
##     Godot --path . --script scripts/tools/shot_damage_number.gd --quit-after 240
##
## 산출 = `scratch_shots/damage_number.png` (+ 콘솔에 글리프 실측 높이)

const OUT := "res://scratch_shots/damage_number.png"
const FONT_DIR := "res://assets/converted/font_ui/%s.fnt"

var _root: Control
var _n := 0


func _initialize() -> void:
	process_frame.connect(_first, CONNECT_ONE_SHOT)


func _font(name: String) -> FontFile:
	var f: FontFile = load(FONT_DIR % name).duplicate()
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	return f


func _label(at: Vector2, text: String, size: int, name: String) -> Label:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_override("font", _font(name))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	_root.add_child(l)
	return l


func _first() -> void:
	DisplayServer.window_set_size(Vector2i(1024, 692))
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_root)

	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.09, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	# 낱타(font_normal 56) · 누계(font_total 93) · 회복(font_heal 56) — 전부 배율 1.0
	var a := _label(Vector2(60, 60), "115", 56, "font_normal")
	var b := _label(Vector2(60, 170), "1004", 93, "font_total")
	var c := _label(Vector2(60, 330), "+240", 56, "font_heal")
	await process_frame
	for pair in [["font_normal 56", a], ["font_total 93", b], ["font_heal 56", c]]:
		var l: Label = pair[1]
		print("[glyph] %-16s label size = %s" % [pair[0], l.size])

	# 노란 별 — 원작 damagedEffect 의 particle/scene/colosseum/effect_damaged.plist
	var host := Node2D.new()
	host.position = Vector2(700, 350)
	_root.add_child(host)
	CocosParticle.spawn(host, "colosseum_damaged", Vector2.ZERO, 6, 0.9)

	process_frame.connect(_tick)


func _tick() -> void:
	_n += 1
	if _n != 6:                      # 별이 퍼진 순간(수명 0.3s 중반)
		return
	DirAccess.make_dir_recursive_absolute("res://scratch_shots")
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT))
	print("[write] ", OUT)
	quit()
