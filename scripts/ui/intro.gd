extends Control
## 게임 시작 화면 — 원작 `cocos2d::IntroScene` 이식. render 층(CLAUDE.md §8.1).
##
## 포팅 카드 = `docs/ref/porting/IntroScene.md`.
##
## ── 원작 근거 ────────────────────────────────────────────────────────────────
## 클래스: `docs/ref/orig_code/decomp/IntroScene.c`
##   · `init` @0137df68 → `initValues`(볼륨 로드) → `initWidget` → `scheduleOnce(initSetting)`
##   · `initWidget` @0137e28c
##       - `CCSpriteFrameCache::addSpriteFramesWithFile("intro.img_plist")`
##       - 타이틀 스파인 `CCSkeletonAnimation::createWithFile("intro/intro2020_3_spine.spine_json",
##         "intro/intro_spine2020_3_spine9.img_plist", 1.0)`, 앵커 중앙, **화면 정중앙**,
##         `setAnimation("animation", loop=true)`
##       - 상태 라벨 `CCLabelBMFontEx` 흰색 @(w*0.85, 80) scale 0.8  ← 오프라인 컷(아래 §컷)
##       - 리듬 미니게임 아이콘 `intro/game/game_icon.png` → `onClickMiniGame`  ← 컷
##       - `drawCopyright()`
##   · `drawCopyright` @013813d8
##       - `CCLayerColor(rgba 0,0,0,0x7d)` 폭=화면, 높이 50 @(0,0) z=0
##       - 버전 `CCLabelBMFontEx("\n5.1.1(<리소스번호>)")` @(w*0.05, 30) 앵커(0,0.5) scale 1.2 z=1
##       - `"Dragon Village @ highbrow, published by Ocon"` 앵커(0,0.5) scale 1.1,
##         버전 라벨 오른쪽으로 (라벨폭*scale + 20, -4) z=1
##       - 한국 마켓이면 `intro/grb_all.png`(전체이용가) 앵커(1,1) @(right-10, top-10)
##   · `initSetting` @0137e6e0 (준비 완료 시)
##       - `intro/txt_bg.png` @(상태라벨.getPositionX() + 20, 0), opacity 0 → `FadeIn(0.7)`
##         + `MoveBy(0.8, (0, 상태라벨.getPositionY()))` `EaseExponentialOut`
##       - 자식으로 `intro/txt_start_<lang>.png` @(플레이트폭*0.5 - 20, 플레이트높이*0.5),
##         opacity 0 → `Delay(0.7) → FadeIn(0.7) → FadeOut(0.7)` **무한 반복**
##       - `log("Tab to start")` 후 터치 플래그 on
##   · `onEnter` @0137ff9c → `SoundManager::playBackground(this, "music/bg_intro.mp3", loop)`
##     ⚠️ 이 문자열은 디컴프 텍스트에 안 보인다(스택에 바이트로 조립). libgame.so 에서
##        `"music/bg_intro.mp3"`(va 0x20f2d81) 의 ADRP+ADD 참조를 뒤져 확정했다 —
##        참조는 딱 둘: `IntroScene::onEnter`(0x127ffdc) · `MiniGameLayer::~MiniGameLayer`(0x12aa870).
##   · `ccTouchBegan` @0138009c → 로그인 성공 상태에서 **화면 아무 데나 터치** → `LoadingLayer` → 게임
##
## ⚠️ `getPositionX/Y` 확정: vtable `+0xb8`/`+0xc8`. 근거 = `AdventureScene.c:39246`
##    `CCPoint(obj+0xb8, obj+0xc8 - 32.0)` 처럼 좌표쌍으로 쓰인다.
##
## ── 오프라인 변형 (CLAUDE.md §2-1) ───────────────────────────────────────────
## · **리듬 미니게임 전부 컷**(사용자 확정 2026-07-31) — `onClickMiniGame`/`MiniGameLayer`/
##   `intro/game/*`/`music/bg_note_intro`/`effect_intro_*`. 아이콘 자체를 만들지 않는다.
## · 로그인·회원가입·게스트·서버 점검·리소스 다운로드 = 온라인이라 삭제. 따라서 **상태 라벨도
##   보고할 내용이 없어 컷**(사용자 확정) — 자리(w*0.85, 80)는 시작 문구의 앵커로만 남는다.
## · 버전 표기는 우리 빌드(사용자 확정) — 저작권 줄은 원작 문구 그대로.
## · 터치 → 원작은 `LoadingLayer`, 우리는 `Main.begin_new_game()`(초기 로드아웃 → 프롤로그/유타칸).

## 원작 상태 라벨 자리 — 시작 문구 플레이트가 여기로 올라온다(`initSetting`).
const STATUS_AX := 0.85
const STATUS_Y := 80.0
## `drawCopyright` — 바 높이 50, α=0x7d.
const BAR_H := 50.0
const BAR_ALPHA := 125.0 / 255.0
const VER_AX := 0.05
const VER_Y := 30.0
## 원작 저작권 문구 그대로.
const COPYRIGHT := "Dragon Village @ highbrow, published by Ocon"
## 이식한 클라 버전 + 우리 빌드 표기(사용자 확정 2026-07-31).
const VERSION_TEXT := "5.1.1 (offline reimpl)"
const FONT := "res://assets/converted/font_ui/font_common.fnt"

const UI := "intro_ui"
const TITLE_SPINE := "res://scenes/fx/intro_title_spine.tscn"

var _ready_to_start := false        # 원작 this+0x1c8 (ccTouchBegan 가 검사하는 플래그)
var _started := false               # 중복 진입 방지(원작 this+0x1c9)


func enter(_params: Dictionary = {}) -> void:
	pass


func _ready() -> void:
	# 원작 `onEnter` 의 배경음(`SoundManager::playBackground("music/bg_intro.mp3", loop)`).
	# ⚠️ 리터럴로 적을 것 — `build_music.py` 가 `Bgm.play("<키>")` 문자열을 훑어 mp3 를 반입한다.
	Bgm.play("bg_intro")
	_build()


func _build() -> void:
	var vis := _vis()

	# 스파인이 화면 전체를 덮지 못하는 가장자리를 위한 배경(원작은 기기 비율이 좁아 필요 없었다).
	var back := ColorRect.new()
	back.color = Color(0, 0, 0)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.z_index = -30          # 스파인 홀더(-20)보다도 뒤
	add_child(back)

	_build_title(vis)
	_build_copyright(vis)
	# 원작은 DB 준비가 끝난 뒤 `initSetting` 이 띄운다. 오프라인은 준비할 것이 없으므로 바로.
	_build_start_prompt(vis)


## 타이틀 스파인 — 원작 `initWidget`: 앵커 중앙 + 화면 정중앙 + `setAnimation("animation", loop)`.
## 스파인 유닛은 480 아틀라스 픽셀이라 디자인 포인트로는 ×4/3 이다(§9).
func _build_title(vis: Vector2) -> void:
	if not ResourceLoader.exists(TITLE_SPINE):
		push_warning("[Intro] 타이틀 스파인 없음 — build_intro_assets.py 를 돌려야 한다")
		return
	var holder := Node2D.new()
	holder.position = vis * 0.5
	holder.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	# ⚠️ 변환된 스파인 씬은 슬롯마다 `z_index` 1~19 를 갖는다(그리기 순서 보존). z_index 는
	#    형제 순서보다 세므로, 홀더를 통째로 내려 두지 않으면 **뒤에 붙인 UI 가 그림에 가린다**
	#    (저작권 바·시작 문구가 안 보이던 원인, 2026-07-31).
	holder.z_index = -20
	add_child(holder)
	var inst := (load(TITLE_SPINE) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
	if ap != null and ap.has_animation("animation"):
		ap.get_animation("animation").loop_mode = Animation.LOOP_LINEAR
		ap.play("animation")


## 원작 `drawCopyright` 그대로 — 하단 반투명 바 + 버전 + 저작권 + 전체이용가 마크.
func _build_copyright(vis: Vector2) -> void:
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, BAR_ALPHA)
	bar.position = Vector2(0.0, vis.y - BAR_H)
	bar.size = Vector2(vis.x, BAR_H)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	# 원작 버전 라벨 scale 1.2 · 저작권 scale 1.1 — 비트맵 폰트(17px) 기준 배율이다.
	var ver := _bm_label(VERSION_TEXT, 17 * 1.2)
	ver.position = Vector2(vis.x * VER_AX, Design.flip_y(VER_Y, vis.y) - ver.size.y * 0.5)
	add_child(ver)

	var cr := _bm_label(COPYRIGHT, 17 * 1.1)
	# 원작: 버전 라벨 오른쪽으로 (라벨폭 + 20, -4).
	cr.position = ver.position + Vector2(ver.size.x + 20.0, -4.0)
	add_child(cr)

	# 전체이용가(GRB) 마크 — 앵커(1,1) @(right-10, top-10).
	var grb := AtlasUI.spr(UI, "intro_grb_all", Design.ASSET_SCALE)
	if grb != null:
		var sz := AtlasUI.size_pt(UI, "intro_grb_all")
		grb.position = Vector2(vis.x - 10.0 - sz.x * 0.5, 10.0 + sz.y * 0.5)
		add_child(grb)


## 원작 `initSetting` 의 "Tab to start" 블록.
func _build_start_prompt(vis: Vector2) -> void:
	var plate := AtlasUI.spr(UI, "intro_txt_bg", Design.ASSET_SCALE)
	if plate == null:
		return
	# 원작: 상태 라벨 위치 기준. x = 라벨x + 20, y 는 0(화면 바닥)에서 라벨y 만큼 올라온다.
	var end_pos := Vector2(vis.x * STATUS_AX + 20.0, Design.flip_y(STATUS_Y, vis.y))
	plate.position = Vector2(end_pos.x, vis.y)          # cocos y=0 = 화면 바닥
	plate.modulate.a = 0.0
	add_child(plate)

	# 시작 문구는 플레이트의 자식 — 중심에서 x 로 20pt 왼쪽(원작 `플레이트폭*0.5 - 20`).
	var txt := AtlasUI.spr(UI, "intro_txt_start_kr", 1.0)   # 부모(플레이트)가 이미 4/3 배다
	if txt != null:
		txt.position = Vector2(-20.0 / Design.ASSET_SCALE, 0.0)
		txt.modulate.a = 0.0
		plate.add_child(txt)

	# 플레이트: FadeIn(0.7) + MoveBy(0.8, EaseExponentialOut).
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(plate, "modulate:a", 1.0, 0.7)
	tw.tween_property(plate, "position", end_pos, 0.8) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	# 문구: Delay(0.7) → FadeIn(0.7) → FadeOut(0.7) 무한 반복.
	if txt != null:
		var blink := create_tween().set_loops()
		blink.tween_interval(0.7)
		blink.tween_property(txt, "modulate:a", 1.0, 0.7)
		blink.tween_property(txt, "modulate:a", 0.0, 0.7)

	_ready_to_start = true


## 원작 `ccTouchBegan` — 준비되면 **화면 아무 데나** 누르면 시작.
## ⚠️ 마우스는 `_unhandled_input` 이 아니라 여기로 온다 — 이 씬의 루트가 화면 전체를 덮는
##    Control 이고 기본 `mouse_filter` 가 STOP 이라 GUI 단계에서 이벤트를 먹는다.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		accept_event()
		_try_start()


## PC 타깃이라 키보드/게임패드도 받는다(원작엔 없는 입력이지만 마우스 전용 강제는 우리 쪽 손해다).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		_try_start()


func _try_start() -> void:
	if _ready_to_start and not _started:
		_start()


func _start() -> void:
	_started = true
	# 원작은 `LoadingLayer` → 게임. 우리는 부팅 절차와 같은 곳(Main)에 위임한다
	# (초기 로드아웃 → 새 세이브면 프롤로그 → 유타칸 → 최초 1회 닉네임).
	var app := get_tree().current_scene
	if app != null and app.has_method("begin_new_game"):
		app.call("begin_new_game")
	else:
		push_warning("[Intro] Main.begin_new_game 없음 — 메인 화면으로만 이동한다")
		Scenes.goto("worldmap", {"region": "yutakan"})


# ---------- helpers ----------

## 원작 `CCLabelBMFontEx` = 비트맵 폰트 라벨. 우리 한글 보강본(`font_ui`)을 쓴다(§10).
## 비트맵이라 `fixed_size_scale_mode` 를 켜야 `font_size` 가 먹는다.
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
