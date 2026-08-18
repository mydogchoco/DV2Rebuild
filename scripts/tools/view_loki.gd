extends Node2D
const PAGES := ["① 스파인", "② 초상·도감", "③ 컷인", "④ 이펙트"]
const STAGES := ["baby", "child", "adult", "aura", "e", "advent"]
const ANIMS := ["wait", "love", "attack"]
const SKEL_H := {"baby": 122.0, "child": 210.0, "adult": 289.0, "aura": 390.0, "e": 335.0,
	"advent": 491.0}
const FIT_PX := 520.0
const FX_FPS := 24.0

var _id := 800
var _page := 0
var _si := 2
var _ai := 0
var _speed := 1.0
var _awakened := false
var _fi := 0
var _stage_root: Node2D = null
var _page_root: Node2D = null
var _ap: AnimationPlayer = null
var _label: Label = null
var _hint: Label = null

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("id="):
			_id = int(a.substr(3))
	get_window().title = "로키 뷰어 — 드빌1 이식 확인"

	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.17, 0.20)
	bg.size = get_viewport_rect().size
	bg.z_index = -100
	add_child(bg)

	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_font_size_override("font_size", 18)
	_label.z_index = 200
	add_child(_label)

	_hint = Label.new()
	_hint.position = Vector2(16, get_viewport_rect().size.y - 34)
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.modulate = Color(1, 1, 1, 0.55)
	_hint.z_index = 200
	add_child(_hint)

	_build_page()

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey) or not e.pressed or e.echo:
		return
	match (e as InputEventKey).keycode:
		KEY_ESCAPE:
			get_tree().quit()
		KEY_TAB:
			_page = (_page + 1) % PAGES.size(); _build_page()
		KEY_RIGHT:
			_step(1)
		KEY_LEFT:
			_step(-1)
		KEY_DOWN:
			_step2(1)
		KEY_UP:
			_step2(-1)
		KEY_SPACE:
			_replay()
		_:
			var k: int = (e as InputEventKey).keycode
			if k >= KEY_1 and k <= KEY_9 and _page == 0:
				_speed = float(k - KEY_0) / 2.0
				if _ap != null:
					_ap.speed_scale = _speed
				_status()

func _step(d: int) -> void:
	match _page:
		0: _si = (_si + d + STAGES.size()) % STAGES.size(); _spawn_stage()
		2: _awakened = not _awakened; _replay()
		3: _fi = (_fi + d + 3) % 3; _replay()
		_: pass

func _step2(d: int) -> void:
	if _page == 0:
		_ai = (_ai + d + ANIMS.size()) % ANIMS.size()
		_play()

func _clear_page() -> void:
	if _page_root != null:
		_page_root.queue_free()
	_page_root = Node2D.new()
	add_child(_page_root)
	if _page != 0 and _stage_root != null:
		_stage_root.queue_free()
		_stage_root = null
		_ap = null

func _build_page() -> void:
	_clear_page()
	match _page:
		0:
			_hint.text = "Tab 페이지   ← → 단계   ↑ ↓ 애니   Space 재생   1~9 배속   Esc 종료"
			_spawn_stage()
		1:
			_hint.text = "Tab 페이지   Esc 종료"
			_build_portraits()
		2:
			_hint.text = "Tab 페이지   ← → 각성 전/후   Space 다시 재생   Esc 종료"
			_replay()
		3:
			_hint.text = "Tab 페이지   ← → 이펙트 종류   Space 다시 재생   Esc 종료"
			_replay()

func _replay() -> void:
	match _page:
		0: _play()
		2: _play_cutin()
		3: _play_fx()

func _spawn_stage() -> void:
	if _stage_root != null:
		_stage_root.queue_free()
		_stage_root = null
		_ap = null
	var stage: String = STAGES[_si]
	var path := "res://scenes/dragons/dragon_%d_%s.tscn" % [_id, stage]
	if not ResourceLoader.exists(path):
		_status("씬 없음: " + path)
		return
	_stage_root = Node2D.new()
	_stage_root.position = get_viewport_rect().size * 0.5
	var s: float = FIT_PX / float(SKEL_H.get(stage, 400.0))
	_stage_root.scale = Vector2(s, s)
	add_child(_stage_root)
	_stage_root.add_child((load(path) as PackedScene).instantiate())
	_ap = _stage_root.get_child(0).get_node_or_null("AnimationPlayer")
	_play()

func _play() -> void:
	if _ap == null:
		_status("AnimationPlayer 없음")
		return
	var an: String = ANIMS[_ai]
	if not _ap.has_animation(an):
		_status("애니 없음: " + an)
		return
	_ap.speed_scale = _speed
	_ap.play(an)
	_status()

func _build_portraits() -> void:
	var keys := [["egg", "알"], ["box_baby", "해치"], ["box_child", "해츨링"],
		["box_adult", "성체"], ["box_aura", "오라성체"], ["box_evolution", "각성"],
		["egg_small", "알(작은)"]]
	var vis := get_viewport_rect().size
	var x := 90.0
	var y := vis.y * 0.42
	for pair in keys:
		var key: String = "dragon_dragon_%d_%s" % [_id, pair[0]]
		var p := "res://assets/converted/portrait_%d/%s.tres" % [_id, key]
		var lbl := Label.new()
		lbl.position = Vector2(x - 40, y + 90)
		lbl.add_theme_font_size_override("font_size", 15)
		_page_root.add_child(lbl)
		if not ResourceLoader.exists(p):
			lbl.text = "%s\n(없음)" % pair[1]
			x += 170
			continue
		lbl.text = String(pair[1])
		var spr := Sprite2D.new()
		spr.texture = load(p)
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
		spr.material = m
		spr.position = Vector2(x, y)
		_page_root.add_child(spr)
		x += 170
	_status("도감 6칸 + 알(작은) — 초상 매니페스트 실물")

func _play_cutin() -> void:
	_clear_page()
	var caster := {"id": _id, "element": "chaos", "awakened": _awakened}
	CritCutin.show(_page_root, caster, 0.6)
	_status("%s — %s" % ["각성 후 (e_cut_in)" if _awakened else "각성 전 (cut_in)",
		"CritCutin.show() 실호출"])

func _play_fx() -> void:
	_clear_page()
	var sets := [["adv_action", 2, "탐험 크리티컬 (2장 중 랜덤)"],
		["col_action1_", 12, "콜로세움 평타 12프레임"],
		["col_action2_", 16, "콜로세움 크리티컬 16프레임"]]
	var cur: Array = sets[_fi]
	var prefix: String = cur[0]
	var count: int = cur[1]
	var vis := get_viewport_rect().size
	var man := _fx_man()

	var spr := Sprite2D.new()
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	spr.material = m
	spr.position = vis * 0.5
	spr.scale = Vector2(1.4, 1.4)
	_page_root.add_child(spr)

	if prefix == "adv_action":
		var n := randi() % 2 + 1
		_set_fx(spr, man, "dragon_%d_adv_action%d" % [_id, n])
		_status("%s — 이번엔 %d번" % [cur[2], n])
		return

	var f := [0]
	_set_fx(spr, man, "dragon_%d_%s%02d" % [_id, prefix, 0])
	var t := Timer.new()
	t.wait_time = 1.0 / FX_FPS
	t.autostart = true
	_page_root.add_child(t)
	t.timeout.connect(func():
		if not is_instance_valid(spr):
			return
		f[0] = (f[0] + 1) % count
		_set_fx(spr, man, "dragon_%d_%s%02d" % [_id, prefix, f[0]]))
	_status(String(cur[2]))

func _set_fx(spr: Sprite2D, man: Dictionary, key: String) -> void:
	var p := "res://assets/converted/dragon_%d_fx/%s.tres" % [_id, key]
	if not ResourceLoader.exists(p):
		return
	spr.texture = load(p)
	var e: Dictionary = man.get(key, {})
	var off: Array = e.get("off", [0, 0])
	var src: Array = e.get("src", [0, 0])
	var _unused := src
	spr.offset = Vector2(float(off[0]), -float(off[1]))

func _fx_man() -> Dictionary:
	var f := FileAccess.open("res://assets/converted/dragon_%d_fx/_manifest.json" % _id,
		FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func _status(extra := "") -> void:
	var head := "%s   [%d 로키]" % [PAGES[_page], _id]
	if _page == 0:
		var an: String = ANIMS[_ai]
		var ln := 0.0
		if _ap != null and _ap.has_animation(an):
			ln = _ap.get_animation(an).length
		head += "   %s   %s %.2fs   x%.1f" % [STAGES[_si], an, ln, _speed]
	_label.text = head + ("   " + extra if extra != "" else "")
