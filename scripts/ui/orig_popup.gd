class_name OrigPopup
extends Control
## 원작 `PopupLayer` 규격의 팝업 껍데기. render 층(CLAUDE.md §8).
##
## 연구소·점술집의 **기능 화면은 전부 이 형태**다 — 씬을 갈아끼우는 게 아니라
## 배경 씬(연구소 방/유리아의 가게 + 하단 대사창) 위에 딤을 깔고 창을 띄운다.
## 포팅 카드 = `docs/ref/porting/OrigPopup.md`.
##
## 원작 근거(전부 디컴프 실측):
##   · `PopupLayer::show(parent, zOrder, 127.0)` — 딤 레이어를 `CCFadeTo(0.2, 127)` 로 띄우고
##     내용 노드에 `CCScaleTo(0.1,1.2) → CCScaleTo(0.1,1.0)` 팝 연출을 건다
##     (`docs/ref/orig_code/decomp/PopupLayer.c:1183`).
##   · 창 = `PopupLayer::setContentSprite("9patch/popup4.png", CCRect(130,190,40,58))`
##     + `setContentSpriteSize(800, 480)` + `setContentSpritePosition(centerX, 380)`
##     (`docs/ref/orig_code/decomp/UpgradeGemLayer.c:590-602`). 화면비 1.6 이상이면 x 를 `(right-250)/2`
##     로 왼쪽에 붙이는 분기가 있으나 우리 디자인 해상도는 1024/692 = 1.48 이라 **center** 다.
##   · 제목바 = `9patch/pop_title_bg` Scale9, 크기 `(창폭 × 0.5, 프레임높이)`,
##     위치 `(창폭/2, 창높이 − 50)` (`UpgradeGemLayer.c:682-694`).
##   · 제목 = `getFontName_subtitle` BMFont, 제목바 중앙, scale 1.2.
##     ⚠️ 한글 BMFont 는 Godot 임포터 제약으로 못 쓴다(CLAUDE.md §10) → TTF.
##   · 닫기 = `common/close_btn`, scale 1.5, `(창폭 − 50, 창높이 − 50)`
##     (`UpgradeGemLayer.c:797-810`).
##   · 하단 실행 버튼 = `RoundedButton::create(CCSize(220,56), …, type)` =
##     **`9patch/btn{,2,3,4,6,8,10,11}` Scale9 capInsets(20,20,4,4)** — 도형이 아니라 프레임이다
##     (`docs/ref/orig_code/decomp/RoundedButton.c:102`). 기본 위치 `(창폭/2, 60)`.
##
## 좌표계: 원작 값은 cocos(y-up, 창 좌하단 원점) → 여기서는 창 로컬 Godot(y-down)로 뒤집어
## 적는다(`y' = 창높이 − y`). 자식은 **포인트 단위 창 로컬 좌표**를 그대로 쓴다.

signal closed

## 원작 `setContentSprite` 인자 그대로.
const WIN_CAP := Rect2(130, 190, 40, 58)
const WIN_SIZE := Vector2(800.0, 480.0)
## 원작 `setContentSpritePosition(x, 380)` — 창 **중심**의 cocos y.
const WIN_CENTER_Y := 380.0
## `PopupLayer::show(..., 127.0)` 의 딤 알파.
const DIM_ALPHA := 127.0 / 255.0
## `RoundedButton` capInsets + 기본 크기.
const BTN_CAP := Rect2(20, 20, 4, 4)
const BTN_SIZE := Vector2(220.0, 56.0)

## 창 내부(프레임·제목바·닫기 포함). 자식 좌표 = 창 좌상단 원점, 포인트 단위.
var body: Control
## 기능 내용만 담는 층. 값이 바뀌어 다시 그릴 땐 **여기만** 비운다(`clear_content`) —
## `body` 를 비우면 제목바·닫기까지 날아간다.
var content: Control
var win_size: Vector2
## 닫기(✕). 원작에 ✕ 가 없고 다른 버튼이 닫기를 겸하는 창(예: `MakeMasicStonePopup` = `check_btn`)
## 에서는 호출부가 `close_btn.visible = false` 로 숨긴다.
var close_btn: TextureButton

var _dim: ColorRect

## 원작 `PopupLayer::show(parent, tag, 127.0)`. 반환값의 `body` 에 내용을 붙인다.
static func open(parent: Node, title: String, sz := WIN_SIZE) -> OrigPopup:
	var p := OrigPopup.new()
	p.win_size = sz
	parent.add_child(p)
	p._build(title)
	return p

func _build(title: String) -> void:
	# ⚠️ `set_anchors_preset` 은 앵커만 바꾸고 오프셋을 현재 rect(0×0)에 맞춰 다시 계산해서
	#    크기가 0 으로 굳는다 — 딤이 안 보이던 원인. 앵커+오프셋을 함께 세워야 한다.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 원작 팝업 레이어는 뒤쪽 입력을 통째로 먹는다(CCLayerColor + swallowsTouches).
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	# CCFadeTo(0.2, 127)
	create_tween().tween_property(_dim, "color:a", DIM_ALPHA, 0.2)

	var vis := get_viewport_rect().size
	body = Control.new()
	body.size = win_size
	body.position = Vector2(
		round((vis.x - win_size.x) * 0.5),
		round(Design.flip_y(WIN_CENTER_Y) - win_size.y * 0.5))
	body.pivot_offset = win_size * 0.5
	add_child(body)

	var frame := AtlasUI.nine("ninepatch_ui", "9patch_popup4", win_size, WIN_CAP)
	if frame != null:
		body.add_child(frame)
		body.move_child(frame, 0)

	# CCScaleTo(0.1, 1.2) → CCScaleTo(0.1, 1.0)
	var tw := body.create_tween()
	tw.tween_property(body, "scale", Vector2(1.2, 1.2), 0.1)
	tw.tween_property(body, "scale", Vector2.ONE, 0.1)

	if title != "":
		var th := AtlasUI.size_pt("ninepatch_ui", "9patch_pop_title_bg").y
		var tw_pt := win_size.x * 0.5
		var tbar := AtlasUI.nine("ninepatch_ui", "9patch_pop_title_bg", Vector2(tw_pt, th))
		if tbar != null:
			# 원작 위치는 제목바 **중심** — Godot 은 좌상단 기준이라 절반씩 뺀다.
			tbar.position = Vector2(win_size.x * 0.5 - tw_pt * 0.5, 50.0 - th * 0.5)
			body.add_child(tbar)
		var tl := Label.new()
		tl.text = title
		tl.add_theme_font_size_override("font_size", 26)
		tl.add_theme_color_override("font_color", Color.WHITE)
		tl.add_theme_color_override("font_outline_color", Color(0.35, 0.14, 0.03, 0.95))
		tl.add_theme_constant_override("outline_size", 5)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tl.size = Vector2(tw_pt, th)
		tl.position = Vector2(win_size.x * 0.5 - tw_pt * 0.5, 50.0 - th * 0.5)
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(tl)

	# 닫기(`common/close_btn`, scale 1.5) — 원작 좌표 (창폭 − 50, 창높이 − 50).
	var cs := AtlasUI.size_pt("common_ui", "common_close_btn") * 1.5
	var x := TextureButton.new()
	var ct := AtlasUI.tex("common_ui", "common_close_btn")
	if ct != null:
		x.texture_normal = ct
		x.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 1.5
	x.position = Vector2(win_size.x - 50.0, 50.0) - cs * 0.5
	x.pressed.connect(close)
	body.add_child(x)
	close_btn = x

	content = Control.new()
	content.size = win_size
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(content)

## 내용만 비운다(제목바·닫기·프레임은 남는다).
func clear_content() -> void:
	for c in content.get_children():
		c.queue_free()
		content.remove_child(c)

## 원작 `RoundedButton` — 도형이 아니라 `9patch/btn*` Scale9 다.
## `kind` = 원작 `RoundedButtonType`(0=btn, 1=btn2, 2=btn3, 4=btn6, 5=btn8, 7=btn10, 8=btn11,
## 그 외=btn4). `pos` 는 **버튼 중심**의 창 로컬 좌표(기본 = 원작 (창폭/2, 60) 자리).
func add_action_button(text: String, cb: Callable, kind := 0, sz := BTN_SIZE,
		pos := Vector2.INF) -> Control:
	const FRAME := {0: "9patch_btn", 1: "9patch_btn2", 2: "9patch_btn3", 4: "9patch_btn6",
		5: "9patch_btn8", 7: "9patch_btn10", 8: "9patch_btn11"}
	var center := pos
	if center == Vector2.INF:
		center = Vector2(win_size.x * 0.5, win_size.y - 60.0)
	var root := Control.new()
	root.size = sz
	root.position = center - sz * 0.5
	content.add_child(root)
	var np := AtlasUI.nine("ninepatch_ui", String(FRAME.get(kind, "9patch_btn4")), sz, BTN_CAP)
	if np != null:
		root.add_child(np)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.04, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = sz
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	var b := Button.new()
	b.flat = true
	b.size = sz
	b.pressed.connect(cb)
	root.add_child(b)
	return root

## 원작 `common/btn_info` — 제목 오른쪽의 물음표. 눌리면 설명 토스트.
func add_info_button(cb: Callable) -> void:
	var sz := AtlasUI.size_pt("common_ui", "common_btn_info") * 1.05
	var root := Control.new()
	root.size = sz
	root.position = Vector2(win_size.x * 0.5 + win_size.x * 0.25 + 10.0, 50.0) - sz * 0.5
	content.add_child(root)
	var s := AtlasUI.spr("common_ui", "common_btn_info", Design.ASSET_SCALE * 1.05)
	if s != null:
		s.position = sz * 0.5
		root.add_child(s)
	var b := Button.new()
	b.flat = true
	b.size = sz
	b.pressed.connect(cb)
	root.add_child(b)

func close() -> void:
	closed.emit()
	queue_free()
