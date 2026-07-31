class_name SettingLayer
extends CanvasLayer
## 원작 `SettingLayer` 이식 — 메인 화면(월드맵) 위에 뜨는 전체화면 설정창. render 층(§8.1).
##
## 포팅 카드 = `docs/ref/porting/SettingLayer.md`.
##
## ── 원작 근거 ────────────────────────────────────────────────────────────────
## 진입: `WorldMapScene::onClickMenu` **tag 0x1ceb** → `SettingLayer::show(127.0)`
##       (`WorldMapScene.c:12545`). 우편(0x1ce8)·소셜(0x1cea)과 같은 메뉴 그룹이다.
## 배치: `SettingLayer::initWidget` @01723734 — 11,152B 라 `[skip>8000]` 에 걸려 있었고
##       (CLAUDE.md §7 함정) 전문은 `docs/ref/orig_code/probe/worldmap_pos_probe.c:90445` 에 있다.
##       아래 좌표는 전부 거기서 실측한 것이고 **cocos(y-up, VisibleRect 기준)** 이다.
## 자산: `scene/setting.img_plist` 16프레임 전부 실재 → `assets/converted/setting_ui/`.
##       (2026-07-30 변환 — 그 전까지 16종 모두 🟠미사용이었다)
## 문구: `stringsData_KR.xml` — 제목 `WorldmapMenu6`="설정" · `SettingMsg1`="배경음" ·
##       `SettingMsg2`="효과음".
##
## ── 오프라인 컷 (CLAUDE.md §2-1) ─────────────────────────────────────────────
## 원작 화면은 4구획이었는데 셋이 온라인이라 사라진다:
##   · 푸시 알림 5종(`ISPUSH_NOTI/WAR/DRAGON/RAID/MAIL` + `btn_on/off`) — 서버 푸시. 컷.
##   · 진동(`ISPUSH_VIBRATION` + `switchmask1`/`switchon`/`switchoff`) — PC 타깃이라 무의미. 컷.
##     마켓패스 스위치도 같은 자리이고 결제 연동이라 컷.
##   · 언어(`lang_kr/en/jp/tw/cn` + `lang_cover`) — 한국어 전용. 컷
##     (`lang_cn/en/jp/tw` 는 asset_index 에서도 이미 ⚫범위밖).
##   · 계정(`Setting_ID`/`Setting_MyID` + `onClickLogout`/`Register`/`Server`/`CopyToClipBoard`) — 컷.
## ⇒ **원작에서 살아남는 것은 볼륨 슬라이더 2개뿐**이다. 비는 아래 절반에
##    🟦사용자확정 기능인 '세이브 데이터 초기화'를 원작과 **같은 구획 어휘**로 넣는다
##    (구분선 `scene/setting/line` + 그 위 섹션 라벨 + `RoundedButton`).
##
## 미사용으로 남는 원작 프레임: `btn_on/off` · `switch*` · `lang_*` (컷 기능의 부품).

const SET := "setting_ui"

## 원작 딤 = `PopupLayer::show(…, 127.0)`.
const DIM_ALPHA := 127.0 / 255.0
## 원작 제목바: `9patch/pop_title_bg` 를 `(W*0.9, 프레임높이)` 로 늘려 `(W*0.5, H-50)` 에.
const TITLE_W_RATIO := 0.9
const TITLE_INSET := 50.0
## 원작 볼륨 구획 — 라벨은 슬라이더보다 cocos 로 40 위(= 화면에서 40 위).
## 배경음 라벨 H*0.5+200 / 슬라이더 +160, 효과음 라벨 +110 / 슬라이더 +70.
const ROW_LABEL_DY := [200.0, 110.0]
const ROW_SLIDER_DY := [160.0, 70.0]
## 슬라이더·라벨 x = W*0.5 − 60.
const ROW_X_OFF := -60.0
## 원작 라벨 scale 0.75(`0x3f400000`) — BMFont subtitle(19px) 기준이라 포인트로 ≈19pt.
const ROW_FONT := 19
## 구획 구분선 = `scene/setting/line` @ (W*0.5, H*0.5+20), 섹션 라벨은 그 5 위(선 위에 글자가 얹힌다).
## 원작 언어/계정 구획도 같은 어휘다(선 y−90, 라벨 y−85).
const RULE_DY := 20.0
const RULE_LABEL_DY := 25.0
## 원작 섹션 라벨 scale 0.9(`0x3f666666`).
const SECTION_FONT := 22
## 초기화 구획의 설명문·버튼 y.
## 원작 알림 줄(라벨 −10 / 버튼 −50)에 그대로 놓으면 두 줄짜리 설명이 머리글(+25)과 겹친다 —
## 알림이 컷돼 아래가 통째로 비었으므로(언어/계정 구획이 −90~−140 에 있었다) 그 공간을 쓴다.
const DESC_DY := -30.0
const ACTION_DY := -110.0

signal closed
## 세이브가 실제로 초기화됐다. 호출부가 화면을 다시 그려야 한다.
signal save_reset

var _root: Control

## 원작 `PopupLayer::show(parent, 127.0)`.
## ⚠️ `layer` 는 **`PopupType`(70) 보다 낮아야** 초기화 확인창이 이 화면 위에 뜬다.
##    CanvasLayer 순서는 씬 트리가 아니라 `layer` 값 하나로 정해진다(MainHud 10 · StatusLayer 24 ·
##    MissionLayer 30 · PopupType 70).
static func open(parent: Node) -> SettingLayer:
	var l := SettingLayer.new()
	l.layer = 40
	parent.add_child(l)
	return l

func _ready() -> void:
	_build()

func _build() -> void:
	if is_instance_valid(_root):
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 원작 팝업 레이어는 뒤쪽 입력을 통째로 먹는다(CCLayerColor + swallowsTouches).
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var vis := get_viewport().get_visible_rect().size

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	create_tween().tween_property(dim, "color:a", DIM_ALPHA, 0.2)

	_build_title(vis)
	_build_volume_rows(vis)
	_build_title_screen_row(vis)
	_build_reset_section(vis)

# ============================================================ 제목바 · 닫기
## 원작: `CCScale9Sprite("9patch/pop_title_bg")` 를 `(W*0.9, 프레임h)` 로 잡아 `(W*0.5, H-50)`,
## 제목 BMFont 는 그 중앙에 scale 1.2. 닫기 `common/close_btn` scale 1.5 @ `(W-50, H-50)`.
func _build_title(vis: Vector2) -> void:
	var th := AtlasUI.size_pt("ninepatch_ui", "9patch_pop_title_bg").y
	var tw := vis.x * TITLE_W_RATIO
	var cy := TITLE_INSET                                  # cocos H-50 → godot 50
	var bar := AtlasUI.nine("ninepatch_ui", "9patch_pop_title_bg", Vector2(tw, th))
	if bar != null:
		bar.position = Vector2(vis.x * 0.5 - tw * 0.5, cy - th * 0.5)
		_root.add_child(bar)
	# 원작 제목 = StringManager `WorldmapMenu6`.
	_root.add_child(_label("설정", 28, Color.WHITE,
		Vector2(vis.x * 0.5 - tw * 0.5, cy - th * 0.5), Vector2(tw, th)))

	var cs := AtlasUI.size_pt("common_ui", "common_close_btn") * 1.5
	var x := TextureButton.new()
	var ct := AtlasUI.tex("common_ui", "common_close_btn")
	if ct != null:
		x.texture_normal = ct
		x.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 1.5
	x.position = Vector2(vis.x - TITLE_INSET, cy) - cs * 0.5
	x.pressed.connect(close)
	_root.add_child(x)

# ============================================================ 볼륨 슬라이더 2개
## 원작 `CCControlSlider::create(sliderTrack, sliderProgress, sliderThumb)`,
## `setMinimumValue(0)` / `setMaximumValue(1)` / `setValue(현재볼륨)`,
## `addTargetWithActionForControlEvents(this, setVolume, ValueChanged)`, tag 1=배경음 / 2=효과음.
## (`worldmap_pos_probe.c:90720~` — 두 슬라이더가 같은 3프레임을 공유한다)
func _build_volume_rows(vis: Vector2) -> void:
	var rows := [
		# [라벨, 현재값 getter, setter] — 원작 SettingMsg1 / SettingMsg2.
		["배경음", Bgm.music_volume(), func(v: float, p: bool): Bgm.set_music_volume(v, p)],
		["효과음", Bgm.effects_volume(), func(v: float, p: bool): Bgm.set_effects_volume(v, p)],
	]
	var x := vis.x * 0.5 + ROW_X_OFF
	for i in rows.size():
		var r: Array = rows[i]
		var ly := Design.flip_y(vis.y * 0.5 + ROW_LABEL_DY[i], vis.y)
		var sy := Design.flip_y(vis.y * 0.5 + ROW_SLIDER_DY[i], vis.y)
		# 원작 라벨은 슬라이더와 같은 x 에 중앙정렬로 놓인다.
		_root.add_child(_label(String(r[0]), ROW_FONT, Color(1, 0.94, 0.80),
			Vector2(x - 100.0, ly - 16.0), Vector2(200.0, 32.0)))
		var sl := FrameSlider.new(float(r[1]), r[2])
		sl.position = Vector2(x, sy)
		_root.add_child(sl)

# ============================================================ 타이틀 화면 선택
## 🟦 **원작에 없는 항목**(사용자 확정 2026-07-31). 원작 `IntroScene` 은 2020 타이틀 하나만
## 안다 — 구판 타이틀 자산(`intro_dragon`/`intro_cloud`)은 에셋 덤프에 남아 있는데 그리는
## 코드가 5.1.1 바이너리에 없다(문자열 전수 확인). 둘 다 보고 싶다는 요청이라 고르게 한다.
## 구획 어휘는 원작 그대로(구분선 + 선 위 섹션 라벨 + `RoundedButton`).
## 자리 = 초기화 버튼(-110) **아래**. 원작에서 언어/계정 구획이 있던 빈 공간이다.
const TITLE_ROW_RULE_DY := -160.0
const TITLE_ROW_LABEL_DY := -155.0
const TITLE_ROW_BTN_DY := -215.0
func _build_title_screen_row(vis: Vector2) -> void:
	var rule := AtlasUI.spr(SET, "scene_setting_line", Design.ASSET_SCALE)
	if rule != null:
		rule.position = Vector2(vis.x * 0.5, Design.flip_y(vis.y * 0.5 + TITLE_ROW_RULE_DY, vis.y))
		_root.add_child(rule)
	var hy := Design.flip_y(vis.y * 0.5 + TITLE_ROW_LABEL_DY, vis.y)
	_root.add_child(_label("타이틀 화면", SECTION_FONT, Color(1, 0.94, 0.80),
		Vector2(vis.x * 0.5 - 120.0, hy - 18.0), Vector2(240.0, 36.0)))

	var cur := String(UserDB.get_pmeta("title_screen", "2020"))
	var by := Design.flip_y(vis.y * 0.5 + TITLE_ROW_BTN_DY, vis.y)
	var bsz := Vector2(220.0, 52.0)
	var opts := [["2020 (시즌3)", "2020"], ["구판", "old"]]
	for i in opts.size():
		var o: Array = opts[i]
		var on: bool = cur == String(o[1])
		var x := vis.x * 0.5 + (-10.0 - bsz.x if i == 0 else 10.0)
		AtlasUI.frame_button(_root, String(o[0]), Vector2(x, by - bsz.y * 0.5), bsz,
			func(): _set_title_screen(String(o[1])),
			0 if on else 1, false, 20)

func _set_title_screen(kind: String) -> void:
	UserDB.set_pmeta("title_screen", kind)
	_build()          # 선택 표시(눌린 쪽만 빨강)를 즉시 갱신

# ============================================================ 세이브 데이터 초기화
## 🟦 **원작에 없는 기능**(사용자 지시 2026-07-30). 오프라인 전용 게임이라 '새로 시작'
## 수단이 필요한데 원작에는 계정 삭제/로그아웃이 그 역할이었고 둘 다 §2-1 로 컷됐다.
## 원작 구획 어휘를 그대로 쓴다 — 구분선 `scene/setting/line` + 선 위 섹션 라벨 +
## `RoundedButton`(=`9patch/btn*`). 자리는 컷된 알림 구획이 있던 곳이다.
##
## 확인은 원작 `PopupTypeLayer`(우리 `PopupType`) 로 받는다 — 원작도 로그아웃 확인에
## 같은 클래스를 썼다(`SettingLayer::onClickLogout` → `SettingMsg7` "로그아웃 하시겠습니까?").
func _build_reset_section(vis: Vector2) -> void:
	var rule := AtlasUI.spr(SET, "scene_setting_line", Design.ASSET_SCALE)
	if rule != null:
		rule.position = Vector2(vis.x * 0.5, Design.flip_y(vis.y * 0.5 + RULE_DY, vis.y))
		_root.add_child(rule)
	var hy := Design.flip_y(vis.y * 0.5 + RULE_LABEL_DY, vis.y)
	_root.add_child(_label("데이터", SECTION_FONT, Color(1, 0.94, 0.80),
		Vector2(vis.x * 0.5 - 120.0, hy - 18.0), Vector2(240.0, 36.0)))

	var dy := Design.flip_y(vis.y * 0.5 + DESC_DY, vis.y)
	_root.add_child(_label(
		"모든 진행도(드래곤·재화·아이템·스토리)를 지우고 처음부터 시작합니다.\n"
		+ "되돌릴 수 없습니다. 볼륨 설정은 유지됩니다.",
		17, Color(1, 0.86, 0.72),
		Vector2(vis.x * 0.5 - 300.0, dy - 26.0), Vector2(600.0, 52.0)))
	var by := Design.flip_y(vis.y * 0.5 + ACTION_DY, vis.y)
	var bsz := Vector2(240.0, 56.0)
	AtlasUI.frame_button(_root, "세이브 데이터 초기화",
		Vector2(vis.x * 0.5 - bsz.x * 0.5, by - bsz.y * 0.5), bsz,
		_confirm_reset, 2, false, 20)

## `PopupType.open` 은 첫 인자에 `get_viewport_rect()` 를 부른다 — CanvasLayer 에는 없는
## 메서드라 Control 인 `_root` 를 넘긴다.
func _confirm_reset() -> void:
	# 문구는 창 폭(460 − 여백 80 = 380pt)에 맞춰 두 줄로 끊는다 — 더 길면 자동 줄바꿈이
	# '사라집니/다.' 처럼 어정쩡하게 잘린다.
	PopupType.open(_root, "세이브 초기화",
		"정말 초기화하시겠습니까?\n모든 진행도가 사라집니다.",
		_do_reset, "초기화", "취소")

func _do_reset() -> void:
	UserDB.reset()
	save_reset.emit()
	# 초기화 직후의 화면은 전부 옛 상태를 들고 있다 — 메인으로 되돌려 다시 짓게 한다.
	# `close()` 가 아니라 직접 free 한다: `closed` 를 쏘면 호출부가 곧 사라질 HUD 를 다시 그린다.
	queue_free()
	# 🔴 2026-07-31 — 초기화는 곧 **새 게임 시작**이다. 종전엔 여기서 `Scenes.goto("worldmap")`
	#    만 불러서 (a) 초기 로드아웃(시작 드래곤·재화·튜토리얼 보상 알)이 안 들어가고
	#    (b) 최초 1회 닉네임 팝업도 안 뜨고 (c) region 없이 가서 양피지 전체지도가 떴다.
	#    부팅과 **같은 절차**(`Main.begin_new_game`)를 다시 태운다.
	#    `get_tree().current_scene` 은 항상 Main 이다 — `Scenes.goto` 는 Main 안의 자식만 갈아 끼운다.
	var app := get_tree().current_scene
	if app != null and app.has_method("begin_new_game"):
		app.call("begin_new_game")
	else:
		push_warning("[SettingLayer] Main.begin_new_game 없음 — 메인 화면만 다시 연다")
		Scenes.goto("worldmap", {"region": "yutakan"})

# ============================================================ helpers
func close() -> void:
	closed.emit()
	queue_free()

func _label(text: String, size: int, color: Color, pos: Vector2, dim: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = pos
	l.size = dim
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 원작 `CCControlSlider` 를 세 프레임(`sliderTrack`/`sliderProgress`/`sliderThumb`)으로 그린다.
## Godot `HSlider` 는 이 3장 구조(트랙 위에 진행 스프라이트를 **가로로 잘라** 얹는 방식)를
## 표현하지 못해 직접 그린다 — 도형 자작이 아니라 **원본 프레임 3장을 원작 구조대로** 쓴다.
## 노드 원점 = 슬라이더 **중심**(원작 `setPosition` 이 중심 좌표다).
class FrameSlider extends Control:
	const SET := "setting_ui"

	var _value := 0.0
	var _on_change: Callable
	var _track: Texture2D
	var _progress: Texture2D
	var _thumb: Texture2D
	var _track_sz: Vector2
	var _prog_sz: Vector2
	var _thumb_sz: Vector2
	var _dragging := false

	func _init(initial: float, on_change: Callable) -> void:
		_value = clampf(initial, 0.0, 1.0)
		_on_change = on_change

	func _ready() -> void:
		_track = AtlasUI.tex(SET, "scene_setting_sliderTrack")
		_progress = AtlasUI.tex(SET, "scene_setting_sliderProgress")
		_thumb = AtlasUI.tex(SET, "scene_setting_sliderThumb")
		_track_sz = AtlasUI.size_pt(SET, "scene_setting_sliderTrack")
		_prog_sz = AtlasUI.size_pt(SET, "scene_setting_sliderProgress")
		_thumb_sz = AtlasUI.size_pt(SET, "scene_setting_sliderThumb")
		# 히트박스는 썸이 트랙 밖으로 나가는 만큼 넉넉히. 원점이 중심이라 좌상단으로 당긴다.
		size = Vector2(_track_sz.x + _thumb_sz.x, maxf(_track_sz.y, _thumb_sz.y))
		position -= size * 0.5
		mouse_filter = Control.MOUSE_FILTER_STOP
		queue_redraw()

	func _draw() -> void:
		if _track == null:
			return
		var cy := size.y * 0.5
		var tx := (size.x - _track_sz.x) * 0.5
		draw_texture_rect(_track, Rect2(Vector2(tx, cy - _track_sz.y * 0.5), _track_sz), false)
		# 진행 프레임은 트랙보다 2px 작다(155×12 vs 153×10) — 중앙에 맞춰 좌측부터 잘라 그린다.
		if _progress != null and _value > 0.0:
			var pw := _prog_sz.x * _value
			var px := tx + (_track_sz.x - _prog_sz.x) * 0.5
			draw_texture_rect_region(_progress,
				Rect2(Vector2(px, cy - _prog_sz.y * 0.5), Vector2(pw, _prog_sz.y)),
				Rect2(Vector2.ZERO, Vector2(_progress.get_width() * _value,
					_progress.get_height())))
		if _thumb != null:
			var hx := tx + _track_sz.x * _value - _thumb_sz.x * 0.5
			draw_texture_rect(_thumb, Rect2(Vector2(hx, cy - _thumb_sz.y * 0.5), _thumb_sz), false)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var mb := e as InputEventMouseButton
			if mb.pressed:
				_dragging = true
				_set_from_x(mb.position.x, false)
			elif _dragging:
				_dragging = false
				# 손을 뗄 때 저장(원작도 값 저장은 창을 닫을 때 한 번이다).
				_apply(true)
			accept_event()
		elif e is InputEventMouseMotion and _dragging:
			_set_from_x((e as InputEventMouseMotion).position.x, false)
			accept_event()

	func _set_from_x(x: float, persist: bool) -> void:
		var tx := (size.x - _track_sz.x) * 0.5
		_value = clampf((x - tx) / maxf(1.0, _track_sz.x), 0.0, 1.0)
		queue_redraw()
		_apply(persist)

	func _apply(persist: bool) -> void:
		if _on_change.is_valid():
			_on_change.call(_value, persist)
