extends Node2D
## 로키(800) **종합 뷰어 창** — 이번 이식으로 만들어진 것을 전부 한 창에서 돌려 본다.
##
## `shot_loki.gd` 는 PNG 를 굽고 바로 종료하므로 창으로는 못 본다. 이쪽은 창을 띄운 채
## 페이지를 넘겨 가며 재생한다. 회귀 검증은 `test_loki800.gd` 가 하고, 이건 **육안 확인**용.
##
## Run: godot --path . res://scenes/view_loki.tscn
##      godot --path . res://scenes/view_loki.tscn -- id=1     (대조군: 다른 드래곤)
##
## 페이지: ① 스파인 6단계 ② 초상·도감 ③ 크리티컬 컷인 ④ 스킬 이펙트
## 조작: Tab 페이지 · ← → · ↑ ↓ · Space 재생 · Esc 종료
const PAGES := ["① 스파인", "② 초상·도감", "③ 컷인", "④ 이펙트"]
const STAGES := ["baby", "child", "adult", "aura", "e", "advent"]
const ANIMS := ["wait", "love", "attack"]
## 원본 스켈레톤 높이(포팅 카드 §1) — 단계마다 6배 넘게 차이 나 그대로 두면 비교가 안 된다.
## ⚠️ `e` 는 **씬에 구워진 배율(root_scale 0.42, 포팅 카드 §3-5)을 반영한 값** 798×0.42 ≈ 335 다.
## 원본 798 을 그대로 두면 이 창에서만 각성체가 42% 로 작아 보인다(씬 배율에 또 나눠지므로).
const SKEL_H := {"baby": 122.0, "child": 210.0, "adult": 289.0, "aura": 390.0, "e": 335.0,
	"advent": 491.0}
const FIT_PX := 520.0
## 콜로세움 이펙트 재생 속도 — `fight.gd::FX_SEQ_FPS` 와 같은 값이어야 실제와 같아 보인다.
const FX_FPS := 24.0

var _id := 800
var _page := 0
var _si := 2                # 성체부터 — 가장 대표적인 단계
var _ai := 0
var _speed := 1.0
var _awakened := false      # 컷인: 각성 전(cut_in) / 후(e_cut_in)
var _fi := 0                # 이펙트 종류
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
				_speed = float(k - KEY_0) / 2.0   # 1=0.5배 … 9=4.5배
				if _ap != null:
					_ap.speed_scale = _speed
				_status()


## ← → : 페이지마다 다른 축
func _step(d: int) -> void:
	match _page:
		0: _si = (_si + d + STAGES.size()) % STAGES.size(); _spawn_stage()
		2: _awakened = not _awakened; _replay()
		3: _fi = (_fi + d + 3) % 3; _replay()
		_: pass


## ↑ ↓ : 스파인 페이지에서만 애니 축
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


# ── ① 스파인 ─────────────────────────────────────────────────────────────────
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
	# 이 스켈레톤들의 root 는 발밑이 아니라 몸통 부근이다(포팅 카드) → 화면 중앙 기준.
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


# ── ② 초상 · 도감 ────────────────────────────────────────────────────────────
## 도감 단계 순서(`Book::getStep` 1~6) 그대로 늘어놓는다. 6칸인 이유 = `box_evolution` 보유.
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
		# 변환본은 PMA 다 — 렌더 블렌드를 맞춰야 테두리가 뜨지 않는다.
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
		spr.material = m
		spr.position = Vector2(x, y)
		_page_root.add_child(spr)
		x += 170
	_status("도감 6칸 + 알(작은) — 초상 매니페스트 실물")


# ── ③ 크리티컬 컷인 ──────────────────────────────────────────────────────────
## 우리 게임이 쓰는 **그 함수를 그대로** 부른다(재현 아님). 각성 여부로 얼굴이 갈린다.
func _play_cutin() -> void:
	_clear_page()
	var caster := {"id": _id, "element": "chaos", "awakened": _awakened}
	# ⚠️ 호스트로 **페이지 루트**를 넘긴다. `show` 는 호스트에 `CanvasLayer` 를 붙이므로
	#    `self` 를 넘기면 페이지를 넘겨도 컷인이 안 지워지고 다음 페이지를 덮는다(실제로 겪음).
	DragonCutin.show(_page_root, caster, 0.6)      # 0.6배 = 천천히 보기
	_status("%s — %s" % ["각성 후 (e_cut_in)" if _awakened else "각성 전 (cut_in)",
		"DragonCutin.show() 실호출"])


# ── ④ 스킬 이펙트 ────────────────────────────────────────────────────────────
## 탐험 크리티컬(adv_action 2종 중 랜덤 1장) · 콜로세움 평타(col_action1 12f) ·
## 콜로세움 크리티컬(col_action2 16f). 프레임 규약은 `fight.gd::_dragon_fx_seq` 와 같다.
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
		# 탐험은 매 크리티컬마다 둘 중 하나를 무작위로 고른다(battle.gd::_critical_fx_band).
		var n := randi() % 2 + 1
		_set_fx(spr, man, "dragon_%d_adv_action%d" % [_id, n])
		_status("%s — 이번엔 %d번" % [cur[2], n])
		return

	# 시퀀스 재생 — 트림 오프셋을 반영해야 중심이 안 흔들린다(원본 캔버스 800×480 기준).
	#
	# ⚠️ GDScript 람다는 **생성 시점의 값을 캡처**한다. `var f := 0` 를 람다 안에서 증가시키면
	#    바깥 `f` 가 안 변해 매 틱 0프레임만 그린다(실제로 이렇게 나서 "단일 프레임"으로 보였다).
	#    Array 는 참조형이라 안에서 바꾼 값이 유지된다.
	var f := [0]
	_set_fx(spr, man, "dragon_%d_%s%02d" % [_id, prefix, 0])   # 첫 틱 전 빈 화면 방지
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
	# cocos 트림은 y-up 이고 원본 캔버스 중심 기준 오프셋이다 → Godot 은 y 를 뒤집는다.
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
