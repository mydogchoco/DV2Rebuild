class_name MatchingWait
extends Control
## 콜로세움 **매칭 대기 연출** — 원작 `MatchingLayer` @00fae03c 이식. render 층(§8).
##
## 🟦 2026-08-05 부활(사용자 지시). 종전엔 "봇 상대라 매칭이 없다"고 통째로 컷했는데,
## 대기 연출 자체가 원작 콜로세움 경험의 일부다. 컷하는 것은 **네트워크 요청**뿐이다.
##
## ## 원작이 하는 일
##
## `MatchingLayer::init(int)` @00fae280:
##   ① `CCLayerColor::init` — 화면 전체 레이어, 중앙 정렬, `setVisible(false)`(→ 아래에서 켠다)
##   ② `LoadingLayer::create(**3**)` — 콜로세움 전용 스타일
##   ③ 타입이 3이면 `LoadingLayer::initString(StringManager::getString(...))`
##      = `<ColosseumMatching>` **"상대를 찾는 중"**(data/colosseum.json `log.matching`)
##   ④ `LoadingLayer::show()`
##   ⑤ `NetworkManager` + `repeatRequest_VS1`/`VS3`/`VS1_Friend`/`VS3_Expediton`
##      → ⚫ **여기만 컷한다.** 우리는 상대가 이미 로컬에서 정해져 있다(`Colosseum.roll_match`).
##
## `LoadingLayer::create(3)` @011d3548 이 그리는 것(리터럴 전수):
##   · `CCLayerColor` (어둡게) — 중앙, `CCFadeTo(0.5, **200**)`
##   · `scene/colosseum/colo_waiting_spine` — 중앙,
##     `CCScaleTo(0.1, 0.9, 1.1)` → `(0.1, 1.1, 0.9)` → `(0.1, 1.0)` 를 `CCRepeatForever`
##   · `CCLabelBMFont`(`GameManager::getFontName_subtitle`) — 중앙 **− (0, 125)**,
##     anchor(0.5, 0.5), alpha 0 → `CCDelayTime(0.5)` → `CCFadeTo(0.4, 255)`
##   · 전용 효과음 `music/effect_colo_waiting.mp3` (원본 실재)
##
## ⚠️ 스타일 3 이 아닌 갈래는 `common/loading_icon.png` 를 `CCRotateBy(1.0, 360)` 로 돌린다 —
##    콜로세움은 스파인 쪽이므로 그건 안 쓴다.
##
## ## 우리 대응
##   `MatchingWait.open(host, sec, on_done)` — `host` 위에 덮고 `sec` 뒤 `on_done` 을 부른다.
##   `sec` = 🟦 **3초 고정**(사용자 확정 2026-08-05). 원작은 서버 응답까지 걸린 시간이었다.

const WAIT_SPINE := "res://scenes/fx/colosseum_waiting.tscn"
const DIM_ALPHA := 200.0 / 255.0    # 원작 CCFadeTo(0.5, 200)
const DIM_SEC := 0.5
const PULSE_SEC := 0.1              # 원작 ScaleTo 3단 공통
const PULSE := [Vector2(0.9, 1.1), Vector2(1.1, 0.9), Vector2(1.0, 1.0)]
const LABEL_DY := 125.0             # 원작 center − (0, 125)
const LABEL_DELAY := 0.5            # 원작 CCDelayTime(0.5)
const LABEL_FADE := 0.4             # 원작 CCFadeTo(0.4, 255)
const LABEL_SIZE := 26

var _on_done := Callable()
var _sec := 3.0


## 대기 화면을 `host` 위에 띄우고 `sec` 뒤 `on_done` 을 부른다.
static func open(host: Node, sec: float, on_done: Callable) -> MatchingWait:
	var m := MatchingWait.new()
	m._sec = sec
	m._on_done = on_done
	host.add_child(m)
	return m


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP     # 원작도 레이어가 아래 입력을 먹는다
	z_index = 4096
	var vis := Vector2(size) if size.length() > 1.0 else _vis()
	var center := vis * 0.5

	# ① 어둡게 — 원작 CCLayerColor + FadeTo(0.5, 200).
	# ⚠️ 앵커 프리셋은 **부모 크기**를 따르는데 이 레이어는 크기가 0 인 채로 붙는다
	#   (호스트가 크기를 안 준다) → 실측 뷰포트 크기를 직접 준다. 종전엔 이걸 빠뜨려
	#   가림막이 0×0 이라 전혀 안 어두워졌다(2026-08-05 캡처에서 확인).
	# FULL_RECT 프리셋을 그대로 두고 size 를 주면 Godot 이 "_ready 뒤 덮어쓴다"고 경고한다
	# → 크기를 직접 관리하므로 앵커를 좌상단으로 되돌린다.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	size = vis
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.position = Vector2.ZERO
	dim.size = vis
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	create_tween().tween_property(dim, "color:a", DIM_ALPHA, DIM_SEC)

	# ② 대기 스파인 — 중앙, 스케일 펄스 무한 반복.
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

	# ③ 문구 — 원작 문자열 그대로(`<ColosseumMatching>`), subtitle BMFont.
	var lab := Label.new()
	lab.text = String(Data.colosseum.get("log", {}).get("matching", "상대를 찾는 중"))
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.size = Vector2(vis.x, 40.0)
	# 원작 `center - CCPoint(0, 125)` — Cocos 는 y 가 위쪽이라 그 뺄셈이 **아래로** 125 다(§Design).
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

	# 원작 전용 효과음(music/effect_colo_waiting.mp3 실재).
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


## 전투 화면과 같은 BMFont 로더(원작 `getFontName_subtitle`).
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
