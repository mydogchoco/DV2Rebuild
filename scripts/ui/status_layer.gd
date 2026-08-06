## 상태창 — 원작 `StatusLayer` + 우측 패널 `CharacterInfoPopup` 이식. render 계층(§8.1).
##
## 포팅 카드 = `docs/ref/porting/StatusLayer.md` · 레퍼런스 `docs/ref/orig_image/cave/status/*`.
##
## ── 왜 독립 노드인가 ────────────────────────────────────────────────────────
## 원작 진입점은 **메인 화면(월드맵/마을)의 프로필 버튼**이다:
##   · `WorldMapScene::onClickMenu`   tag **0xb**   (`WorldMapScene.c:10630`)
##   · `TownMainMenuLayer::onClickMenu` tag **0x2bd** (`TownMainMenuLayer.c:188`)
## `CaveScene` 은 상태창을 열지 않는다. 종전 구현은 `cave.gd::_open_dragon_detail` 안에 있어
## **동굴 씬으로 이동해야만** 열렸다 → 어느 씬에서든 붙일 수 있는 CanvasLayer 로 뽑아냈다.
##   메인 화면:  `StatusLayer.open(self)` (씬 이동 없음)
##   동굴:       같은 호출. 심화 편집(젬/장비/레벨업…)은 `action_requested` 로 host 가 처리.
##
## ── 골격 (`StatusLayer::init` @01a5df50 + `layerDragon` @01a5e188) ──────────
##   RolledLayer(제목) — 전체화면 두루마리. 내부 CCLayer size(visW-40, visH-80) @ (20,0)
##   ├ 드래곤 무대 CCLayer size(visW-380, 340) @ (0,250)
##   │   ├ 단상   `Stand::getImagePath()`  @ (w/2, standH/2 - 45)
##   │   ├ 이름판 `common/name_bg`(302×41) + 깃펜 `common/namepen` → onClickNic
##   │   └ 스태미나 `RoundedLayer(160, 45, 0x66000000, 1, 0)`
##   ├ 우측 `CharacterInfoPopup::create(dragon, 1, …)` anchor(1,0) scale 0.95
##   │        pos = (layerW + (layerW-670)*(-0.25), 무대.y - 30)
##   └ 하단 목록 `9patch/scroll_box` capInsets(65,65,6,6) @ (0,75), 슬롯 간격 **120.5**
##
## ⚠️ 미보유(CLAUDE.md §10): `RolledLayer` 의 `common/bg/{texture,popup3_end_*,title_bar_scroll}`
##    와 `CharacterInfoPopup` 의 `common/bg/stat_box` → `9patch/popup4` · `pop_title_bg`
##    · `9patch/train_box4` 로 대체.
extends CanvasLayer
class_name StatusLayer

const DragonAwakenSkillInfoPopup := preload("res://scripts/ui/dragon_awaken_skill_info.gd")

## host 가 처리할 심화 편집 요청. arg = 슬롯 index(없으면 -1).
## 동굴은 제자리에서 팝업을 열고, 메인 화면은 `Scenes.goto("cave", {"open": action})` 로 넘긴다.
signal action_requested(action: String, arg: int)
signal closed

const DRAGON_SCENE := "res://scenes/dragons/dragon_%d_%s.tscn"
const STAND_COUNT := 16
## (구 `STAMINA_MAX = 5` 제거 — 피로도 5칸은 원작 후기판에서 삭제된 시스템이다. 2026-07-30)

## 원작 `CharacterInfoPopup` 패널 크기. 배경 프레임 `common/bg/stat_box` 가 우리 덤프에 없어
## 실측으로 되짚었다: 패널-로컬 y 오프셋(초상 H-70 · EXP H-77 · 스탯 H-130/-157/-184
## · 아이템그룹 H-265 · 드링크그룹 H-385, 그룹 높이 117.3pt)이 전부 **상단 기준 고정**이므로
## 세로는 "드링크 그룹 하단(443.7) + 여백" 으로, 가로는 레퍼런스 종횡비(w/h≈0.80)로 잡는다.
const PANEL := Vector2(362.0, 452.0)
const PANEL_SCALE := 0.95      # 원작 setScale(0x3f733333)

## 원작 `RoundedLayer::create(w, h, 0x64ffffff, 1, 0)` — 그룹 받침(흰색 alpha 100/255).
const GROUP_ALPHA := 100.0 / 255.0
## 원작 스태미나 받침 `RoundedLayer(160, 45, 0x66000000, …)` — 검정 alpha 102/255.
const STAMINA_ALPHA := 102.0 / 255.0

## 원작 `Dragon::getGemType(slot)` → 칸 프레임. 0=ATT 1=DEF 2=HP 3=ALL.
## (`CharacterInfoPopup::_showGems` @0117c0a0 의 분기 그대로)
const GEM_BOX := {"ATT": "common_gem_box2", "DEF": "common_gem_box3",
	"HP": "common_gem_box1", "ALL": "common_gem_box4"}
## 스킬 칸 모양 — 빈 칸은 `_bg`, 장착 스킬 타입이 칸과 일치하면 테두리까지 얹는다.
const SKILL_BG := {"tri": "common_skill_triangle_bg", "sq": "common_skill_square_bg",
	"cir": "common_skill_circle_bg", "star": "common_skill_star_bg"}
const SKILL_MARK := {"tri": "common_skill_triangle", "sq": "common_skill_square",
	"cir": "common_skill_circle", "star": "common_skill_star"}
const SKILL_SLOT_MARK := {"tri": "△", "sq": "□", "cir": "○", "star": "☆"}

## 하단 목록 셀 박스 배수 — 원작 `CCMenuItemImageEx::create(…, 1.05)` 가 키운 배치 박스.
## (근거·실측 교차검증은 `docs/ref/porting/CaveDragonList.md`, 같은 셀을 쓰는 동굴 목록과 공유)
const SLOT_BOX := 1.05

## 속성 아이콘 키 — 데이터의 `element` 값과 프레임 이름이 다르다(aqua→water, earth→ground).
## 동굴 `cave.gd::ELE_SMALL` 과 같은 표다. 바꿀 땐 두 곳을 함께 고칠 것.
const ELE_SMALL := {
	"all": "item_item_small_ele_all", "fire": "item_item_small_ele_fire",
	"aqua": "item_item_small_ele_water", "earth": "item_item_small_ele_ground",
	"wind": "item_item_small_ele_wind", "light": "item_item_small_ele_light",
	"dark": "item_item_small_ele_dark", "holy": "item_item_small_ele_holy",
	"chaos": "item_item_small_ele_chaos", "shadow": "item_item_small_ele_shadow"}

var _pma: CanvasItemMaterial
var _man_common: Dictionary = {}
var _man_stand: Dictionary = {}
var _man_status: Dictionary = {}
var _man_item_small: Dictionary = {}
var _man_portrait: Dictionary = {}

var _root: Control          # popup4 창(모든 좌표의 기준)
var _uid := -1              # 지금 보고 있는 드래곤(하단 목록에서 바꾼다)
## 패널 단독 모드(원작 `CharacterInfoPopup` 단독 사용 — `open_panel` 참조).
var _panel_only := false
var _panel_left := true
var _panel_pos := Vector2.INF  # 단독 모드 좌상단 강제(INF = 기본 배치)
var _panel_dismiss := true     # 단독 모드에서 바깥 클릭에 닫히는가(전투 팝업만 true)
var _record: Dictionary = {}   # 단독 모드에서 보여 줄 레코드(봇이면 세이브에 없다)

## 어느 씬에서든: `StatusLayer.open(self)`.
static func open(host: Node) -> StatusLayer:
	var l := StatusLayer.new()
	l.layer = 24            # 동굴의 드래곤 spine(별도 CanvasLayer)보다 위
	host.add_child(l)
	return l


## **패널만** 띄운다 — 원작 `CharacterInfoPopup` 을 두루마리 없이 단독으로 쓰는 경로.
##
## 원작에도 이 경로가 있다: 전투 중 드래곤을 터치하면
##   `FightScene::ccTouchesBegan` @00f8f02c (드래곤 레이어 boundingBox 히트테스트)
##     → `MakeInterface::showDragonInfo(fightDragon)` @010b22bc
##        → `FightManager::getDragonInfo(index)` 가 들고 있는 `CharacterInfoPopup` +
##          `CharacterInfoPopup::setHpData()`
##   빈 곳을 터치하면 `MakeInterface::removeDragonInfo` @010b2664.
## 레퍼런스 = `docs/ref/pvp/드래곤터치_상태창팝업.png`(전투 중) — 두루마리·단상·하단 목록이
## 없고 **우측 패널만** 뜬다. 그래서 창을 새로 짜지 않고 같은 `_build_panel` 을 쓴다.
##
## `record` = UserDB 드래곤 레코드 **또는 봇 레코드**(콜로세움 상대는 세이브에 없다).
## `left` 면 화면 왼쪽에, 아니면 오른쪽에 붙인다(원작은 터치한 드래곤 쪽에 낸다).
## `pos` 를 주면 좌우/세로 배치를 무시하고 그 좌상단에 놓는다 — 편성창(`ColosseumSelect`)이
## 원작 `changeSelect` 좌표 `(W-242, H/2+55)` 를 그대로 쓰려고 넘긴다.
##
## `dismiss` = 화면 아무 곳이나 누르면 닫히는가. **전투 중 팝업만** 그렇다
## (원작 `removeDragonInfo` = 빈 곳 터치). 편성창의 패널은 화면 구성물이라 상시 표시다.
## 🔴 2026-08-05(사용자 지적 "창을 비활성화→활성화하면 패널이 날아간다") — 전면 catcher 가
##   포커스 복귀 클릭까지 먹어서 닫혔다. `dismiss=false` 면 catcher 자체를 안 깐다
##   ⇒ 아래 화면(편성창)의 클릭도 그대로 통과한다.
static func open_panel(host: Node, record: Dictionary, left := true,
		pos := Vector2.INF, dismiss := true) -> StatusLayer:
	var l := StatusLayer.new()
	l.layer = 24
	l._panel_only = true
	l._record = record
	l._panel_left = left
	l._panel_pos = pos
	l._panel_dismiss = dismiss
	host.add_child(l)
	return l

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_man_common = _load_manifest("common_ui")
	_man_stand = _load_manifest("stand_ui")
	_man_status = _load_manifest("status_ui")
	_man_item_small = _load_manifest("item_small_ui")
	_uid = UserDB.active_uid()
	_build()

# ============================================================ 에셋 helpers
func _load_manifest(dir: String) -> Dictionary:
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

## 아틀라스 프레임 스프라이트. §9 — 프레임은 호출부에서 `Design.ASSET_SCALE` 를 곱해 그린다.
func _spr(dir: String, key: String, scale := 1.0) -> Sprite2D:
	var s := Sprite2D.new()
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	if ResourceLoader.exists(p): s.texture = load(p)
	s.material = _pma
	s.scale = Vector2(scale, scale)
	return s

func _cspr(key: String, scale := 1.0) -> Sprite2D:
	return _spr("common_ui", key, scale)

func _cw(key: String, fallback := 1.0) -> float:
	return maxf(1.0, float(_man_common.get(key, {}).get("w", fallback)))

func _ch(key: String, fallback := 1.0) -> float:
	return maxf(1.0, float(_man_common.get(key, {}).get("h", fallback)))

func _tex(dir: String, key: String) -> Texture2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	return load(p) if ResourceLoader.exists(p) else null

func _portrait(id: int, stage: String, scale := 1.0, skin := 0) -> Sprite2D:
	var dir := "portrait_%d" % id
	if not _man_portrait.has(dir):
		_man_portrait[dir] = _load_manifest(dir)
	var frame := "dragon_dragon_%d_box_%s" % [id, stage]
	if not (_man_portrait[dir] as Dictionary).has(frame) and stage == "evolution":
		frame = "dragon_dragon_%d_box_adult" % id
	if skin > 0 and (_man_portrait[dir] as Dictionary).has("%s_skin%d" % [frame, skin]):
		frame = "%s_skin%d" % [frame, skin]
	return _spr(dir, frame, scale)

func _vis() -> Vector2:
	return get_viewport().get_visible_rect().size

func _dragon() -> Dictionary:
	# 단독 패널 모드는 넘겨받은 레코드를 그대로 쓴다(콜로세움 봇은 세이브에 없다).
	if not _record.is_empty():
		return _record
	var d := UserDB.get_dragon(_uid)
	return d if not d.is_empty() else UserDB.active_dragon()

func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## 원작 BMFont 라벨(`GameManager::getFontName_subtitle` = `font/font_subtitle.fnt`).
## 한글 보강본은 `assets/converted/font_ui/`(CLAUDE.md §10) — 비트맵이라 `fixed_size_scale_mode`
## 를 켜야 `font_size` 가 먹고, 외곽선은 이미 구워져 있어 outline 오버라이드를 걸지 않는다.
## 폰트가 없으면 기존 TTF 서식으로 폴백한다.
static var _bmfonts: Dictionary = {}
func _bmfont(name := "font_subtitle") -> FontFile:
	if _bmfonts.has(name):
		return _bmfonts[name]
	var p := "res://assets/converted/font_ui/%s.fnt" % name
	if not ResourceLoader.exists(p):
		_bmfonts[name] = null
		return null
	var f: FontFile = load(p).duplicate()
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	# 원작 비트맵에 없는 희귀 음절만 시스템 한글 폰트로 폴백(도감 이름 깨짐 대응과 동일).
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Gulim"])
	f.fallbacks = [fb]
	_bmfonts[name] = f
	return f

func _bm_label(text: String, size: int, col: Color, name := "font_subtitle") -> Label:
	var l := _label(text, size, col)
	var f := _bmfont(name)
	if f != null:
		l.add_theme_font_override("font", f)
	else:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 4)
	return l

## 원작 `RoundedLayer::create(w, h, argb, 1, 0)` — 아틀라스 프레임이 아니라 코드로 그리는
## 라운드 레이어다(§3 위반 아님). StyleBoxFlat 이 정확한 이식.
func _rounded(size: Vector2, col: Color, radius := 12) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", sb)
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _close() -> void:
	closed.emit()
	queue_free()

func _act(action: String, arg := -1) -> void:
	action_requested.emit(action, arg)
	_close()

## 드래곤을 갈아 끼우고(원작 `StatusLayer::onClickDragon`) 화면만 다시 그린다.
func _reopen(uid: int) -> void:
	UserDB.set_active(uid)
	_uid = uid
	if is_instance_valid(_root): _root.queue_free()
	_build()

# ============================================================ 골격
func _build() -> void:
	var vis := _vis()
	var S := Design.ASSET_SCALE
	if _panel_only:
		_build_panel_only(vis, S)
		return

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed: _close())
	add_child(dim)

	# 원작 RolledLayer = 전체화면 두루마리. 미보유라 `9patch/popup4` 로 대체(§10).
	var W: float = vis.x - 40.0
	var H: float = vis.y - 40.0
	_root = NinePatchRect.new()
	(_root as NinePatchRect).texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	(_root as NinePatchRect).patch_margin_left = 130
	(_root as NinePatchRect).patch_margin_top = 190
	(_root as NinePatchRect).patch_margin_right = 55
	(_root as NinePatchRect).patch_margin_bottom = 81
	_root.size = Vector2(W, H)
	_root.position = Vector2(20, 20)
	add_child(_root)

	_build_title(W, S)

	var a := _dragon()
	if a.is_empty():
		var e := _label("보유 드래곤이 없습니다", 24, Color(0.9, 0.86, 0.76))
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.size = Vector2(W, 30); e.position = Vector2(0, H * 0.45)
		_root.add_child(e)
		return

	# ── 세로 배분 ─────────────────────────────────────────────────────────────
	# 원작 좌표계(layer 612pt 기준)를 그대로 쓰면 우리 창(vis.y-40)에서 제목/목록과 겹친다.
	# 구조(무대 위 이름판 → 단상 → 스태미나 / 우측 패널 / 하단 목록)는 그대로 두고
	# 세로만 창 높이에 맞춰 배분한다.
	const TITLE_H := 56.0
	# 🔴 2026-07-30: 원작에 없던 보조 버튼 줄(`_build_extras`)을 삭제(사용자 지시)하고
	#   그 세로 공간을 하단 목록에 돌려줬다 — 띠가 원작 높이(셀 박스 113.4 + 여백)를 되찾아
	#   칸을 축소 없이(cs=1.0) 그린다.
	const STRIP_H := 135.0
	var strip_y: float = H - STRIP_H - 26.0
	var body_top := TITLE_H
	var body_h: float = strip_y - body_top - 10.0

	# 원작 무대 폭 = layerW - 380. 우측 패널이 그 오른쪽에 온다.
	var stage_w: float = maxf(360.0, W - 380.0)
	_build_stage(a, stage_w, body_top, body_h, S)
	_build_panel(a, W, body_top, S)
	_build_strip(W, strip_y, STRIP_H)

## 패널 단독 모드 — 원작 전투 중 `showDragonInfo` 가 내는 모습(레퍼런스
## `docs/ref/pvp/드래곤터치_상태창팝업.png`). 두루마리·단상·하단 목록 없이 패널만 띄우고,
## 바깥을 누르면 닫힌다(원작 `removeDragonInfo` 와 같은 자리).
##
## `_build_panel` 은 창 폭 `W` 기준으로 **오른쪽에서** 들여 붙이므로, 왼쪽에 세우려면
## `_root` 를 그 폭만큼만 두고 화면 왼쪽에 놓으면 된다 — 패널 코드를 건드리지 않는다.
func _build_panel_only(vis: Vector2, S: float) -> void:
	var a := _dragon()
	if a.is_empty():
		queue_free()
		return
	# 원작 전투 팝업은 화면을 어둡게 하지 않는다(전투가 계속 보인다) — 투명 클릭 판만 깐다.
	# CanvasLayer 는 크기가 없어 앵커 프리셋이 0 으로 접힌다 → 크기를 직접 준다.
	# `_panel_dismiss` 가 꺼져 있으면(편성창) 판을 아예 안 깐다 — 아래 화면이 계속 눌린다.
	if _panel_dismiss:
		var catcher := Control.new()
		catcher.size = vis
		catcher.mouse_filter = Control.MOUSE_FILTER_STOP
		catcher.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed:
				_close())
		add_child(catcher)

	# `_build_panel` 은 pane 을 `W - inset - PW×scale` 에 놓고, inset 은
	# `clampf((W-670)×0.25, 40, 200)` 이라 좁은 창에서는 **40 고정**이다.
	# ⇒ `W = 40 + PW×scale` 을 주면 pane 이 `_root` 로컬 원점(0)에 딱 온다.
	var pw := PANEL.x * PANEL_SCALE
	var margin := 16.0
	var inner := 40.0 + pw
	_root = Control.new()
	_root.size = Vector2(pw, PANEL.y * PANEL_SCALE)
	_root.position = _panel_pos if _panel_pos.is_finite() else \
		Vector2(margin if _panel_left else vis.x - pw - margin,
			maxf(10.0, vis.y * 0.5 - PANEL.y * PANEL_SCALE * 0.5))
	add_child(_root)
	_build_panel(a, inner, 0.0, S)


## 제목 두루마리 배너 + 우상단 ✖ (원작 `common/bg/title_bar_scroll` 미보유 → `9patch/pop_title_bg`).
func _build_title(W: float, S: float) -> void:
	var tw := 300.0
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20
	tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(tw, 33.0 * S)
	tbar.position = Vector2((W - tw) * 0.5, 2.0)
	tbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tbar)
	var t := _bm_label("상태창", 30, Color.WHITE, "font_title")   # 원작 TitleLayer = font_title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size = tbar.size
	tbar.add_child(t)
	var xb := TextureButton.new()
	var xt := "res://assets/converted/common_ui/common_close_btn.tres"
	if ResourceLoader.exists(xt):
		xb.texture_normal = load(xt)
		xb.scale = Vector2(S, S)
		xb.position = Vector2(W - 24.0 - 48.0 * S, 6.0)
		xb.pressed.connect(_close)
		_root.add_child(xb)

# ============================================================ 드래곤 무대
## 원작 `StatusLayer::layerDragon` — 이름판(+깃펜) · 단상 · **스파인 드래곤** · 스태미나.
## 🔴 종전 구현은 여기에 box 초상(정사각 크롭)을 세웠다 — 원작은 동굴과 **같은 스파인**이다.
func _build_stage(a: Dictionary, stage_w: float, top: float, h: float, S: float) -> void:
	# 🔴 2026-08-07 — 이 함수의 `id` 는 **그림 id** 다(알 텍스처·스파인 씬·초상 전부).
	#   커스텀 종 600·700 은 자기 아트가 없고 소환 재료에게서 물려받는다 → `Icons.art_id_of`.
	var id := Icons.art_id_of(a)
	var lvl := int(a.get("level", 1))
	var cx := stage_w * 0.5

	# ── 이름판 `common/name_bg`(302×41) + 깃펜 `common/namepen` → onClickNic ──
	var nb_w := _cw("common_name_bg", 302.0) * S
	var nb_h := _ch("common_name_bg", 41.0) * S
	var nb_cy := top + nb_h * 0.5
	var nb := _cspr("common_name_bg", S)
	nb.position = Vector2(cx, nb_cy)
	_root.add_child(nb)
	# 원작도 이름만은 CCLabelTTF("Thonburi", 34)다(BMFont 아님).
	var nl := _label(Icons.name_of(a), 28, Color(0.36, 0.22, 0.08))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.size = Vector2(nb_w - 70.0, nb_h)
	nl.position = Vector2(cx - (nb_w - 70.0) * 0.5, nb_cy - nb_h * 0.5)
	_root.add_child(nl)
	var pen_w := _cw("common_namepen", 36.0) * S
	var pen_cx := cx + nb_w * 0.5 - pen_w * 0.5
	var pen := _cspr("common_namepen", S)
	pen.position = Vector2(pen_cx, nb_cy)
	_root.add_child(pen)
	var pen_hit := Button.new()
	pen_hit.flat = true
	pen_hit.tooltip_text = "이름 바꾸기"
	pen_hit.size = Vector2(pen_w + 16.0, nb_h)
	pen_hit.position = Vector2(pen_cx - pen_w * 0.5 - 8.0, nb_cy - nb_h * 0.5)
	pen_hit.pressed.connect(func(): _act("rename"))
	_root.add_child(pen_hit)

	# ── 스태미나(무대 맨 아래) — 원작 RoundedLayer(160, 45, 0x66000000) ───────
	var st_y: float = top + h - 52.0
	var sp := _rounded(Vector2(160.0, 45.0), Color(0, 0, 0, STAMINA_ALPHA), 22)
	sp.position = Vector2(cx - 80.0, st_y)
	_root.add_child(sp)
	# 🔴 2026-07-30 교체: 피로도(`common/fatigue` ⚡) → **허기(FOOD)**. 사용자 확정 —
	#   원작 초기의 피로도 5칸은 후기판에서 삭제되고 허기만 남았다. 아이콘도 원작 동굴이 쓰는
	#   `common/bubble_food`(asset_index: orig=CaveScene)로 바꿨다. 눈금 = 상한…0(0=굶음).
	var bolt := _cspr("common_bubble_food", 0.95)
	bolt.position = Vector2(30, 22)
	sp.add_child(bolt)
	var fmax := ItemEffect.food_max(Data.item_effects)
	var food := clampi(int(a.get("food", fmax)), 0, fmax)
	var sl := _bm_label("%d / %d" % [food, fmax], 20,
		Color(1, 0.45, 0.4) if food <= 0 else Color.WHITE)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sl.size = Vector2(100, 45); sl.position = Vector2(54, 0)
	sp.add_child(sl)

	# ── 행동불능 배지 (원작 `Dragon::isStun`) ────────────────────────────────
	# 던전 패배로 걸린 지속 상태. 원작은 여기서 **다이아로 즉시 회복**을 제공한다:
	#   `CaveScene.c:8307` → `(cureTime - now) / 0x708 < User::getCash()` 면 `setCureTime(0)`.
	#   0x708 = 1800초 ⇒ 남은 30분당 다이아 1개, **최소 1개**(2026-07-30 정정 — 근거는
	#   `Incapacitation.instant_cost` 주석). 문자열 `Tip_35` 가 이 기능을 설명한다.
	var uid_cur := int(a.get("uid", 0))
	if uid_cur > 0 and UserDB.is_down(uid_cur):
		var now := int(Time.get_unix_time_from_system())
		var ct := UserDB.cure_time(uid_cur)
		var cost := Incapacitation.instant_cost(Data.incapacitation, ct, now)
		var db := _rounded(Vector2(300.0, 40.0), Color(0.35, 0.05, 0.05, 0.78), 18)
		db.position = Vector2(cx - 150.0, st_y - 46.0)
		_root.add_child(db)
		var dl := _bm_label("행동불능 — 남은 %s   (다이아 %d)" % [
			Incapacitation.remain_text(ct, now), cost], 18, Color(1, 0.86, 0.86))
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dl.size = Vector2(300, 40)
		db.add_child(dl)
		var cb := Button.new()
		cb.flat = true; cb.size = Vector2(300, 40)
		cb.pressed.connect(func():
			if cost > 0 and not UserDB.spend("diamond", cost):
				return
			UserDB.set_cure_time(uid_cur, 0)
			_reopen(uid_cur))
		db.add_child(cb)

	# ── 단상 `Stand::getImagePath()` + 스파인 드래곤 ──────────────────────────
	# 단상은 폭을 정규화해 **바닥을 고정**한다(동굴 `_build_stage` 와 같은 규칙) — 스킨마다
	# 높이가 달라도 디스크 위치가 일정하고, 키 큰 장식 단상은 위로만 뻗는다.
	#
	# 드래곤 스파인의 원점↔단상 관계는 동굴에서 이미 맞춰 놓은 값을 비율로 옮긴다:
	#   동굴(1080 공간): 단상 폭 620, 바닥 y=357 / 드래곤 원점 y=-7, scale 1.9
	#   ⇒ 원점은 단상 바닥에서 **0.587 × 단상폭** 위, 스케일은 **1.9 × 단상폭/620**
	var si: int = UserDB.get_skin("stand_skin") % STAND_COUNT
	var st_key := "stand_stand%d" % (si + 1)
	var raw_w: float = maxf(1.0, float(_man_stand.get(st_key, {}).get("w", 305)))
	var raw_h: float = maxf(1.0, float(_man_stand.get(st_key, {}).get("h", 120)))
	# 무대 폭의 40% 를 단상 폭으로(레퍼런스 실측 비율). 화면이 좁아도 드래곤이 넘치지 않는다.
	var stand_w: float = clampf(stage_w * 0.40, 220.0, 420.0)
	var st_sc := stand_w / raw_w
	var stand_bottom: float = st_y - 6.0
	var ped := _spr("stand_ui", st_key, st_sc)
	ped.position = Vector2(cx, stand_bottom - raw_h * st_sc * 0.5)
	_root.add_child(ped)

	var origin := Vector2(cx, stand_bottom - stand_w * 0.587)
	if UserDB.is_egg(a):
		var egg := Sprite2D.new()
		egg.texture = Icons.dragon_egg_texture(id)
		egg.material = _pma
		egg.scale = Vector2(S, S)
		egg.position = origin
		_root.add_child(egg)
		return

	# 원작과 같은 스파인 씬(동굴이 쓰는 것과 동일). 미빌드 종만 초상으로 폴백한다.
	var stage_name := Growth.spine_stage(a)
	var path := DRAGON_SCENE % [id, stage_name]
	if bool(a.get("awakened", false)) and not ResourceLoader.exists(path):
		stage_name = Growth.stage_for_level(lvl)
		path = DRAGON_SCENE % [id, stage_name]
	if ResourceLoader.exists(path):
		var holder := Node2D.new()
		holder.scale = Vector2.ONE * (1.9 * stand_w / 620.0)
		holder.position = origin
		_root.add_child(holder)
		var inst := (load(path) as PackedScene).instantiate()
		holder.add_child(inst)
		var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap != null and ap.has_animation("wait"):
			ap.play("wait")
	else:
		var por := _portrait(id, Growth.portrait_stage(a), stand_w / 220.0, int(a.get("skin", 0)))
		por.position = origin
		_root.add_child(por)
		push_warning("[status] dragon %d(%s) 스파인 씬 미빌드 → 초상 폴백" % [id, stage_name])

# ============================================================ 우측 스탯 패널
## 원작 `CharacterInfoPopup::initWidget` @01172cf8 (16,820B — 기존 덤프에서 `[skip>8000]` 으로
## 잘려 있었다. `batch_decompile.py --classes CharacterInfoPopup --max 20000` 로 재생성).
##
## 패널-로컬 좌표(cocos, 원점 좌하단 · H = 패널 높이):
##   초상칸 `common/item_box2`      @ (55, H-70)  + `Dragon::getImagePathBox` + 속성 아이콘
##   EXP    `bar_bg2`+`bar_exp`+`bar_cover`+`scene/adventure/icon_exp`  @ (100, H-77)
##   FOOD   `bar_bg2`+`bar_food`+`bar_cover`+`icon_food`               @ (100, H-100)
##   스탯 3행 @ H-130 / H-157 / H-184 — 좌열 우측정렬 x=90, 우열 좌측정렬 x=W/2+30
##   아이템그룹 RoundedLayer(box.w+15, box.h+40, 0x64ffffff) @ (60, H-265)  ← MultyEquipView
##   젬그룹     RoundedLayer(220, 아이템그룹.h)  anchor(0,0.5) @ 아이템그룹 오른쪽 +5
##   드링크그룹 @ (60, H-385) · 스킬그룹 = 드링크 오른쪽 +5, 220폭
## 그룹 공통: 제목 BMFont(font_subtitle, scale 0.7) anchor(0.5,1) @ (w/2, h-8)
##
## ⚠️ FOOD 게이지는 **그리지 않는다** — 먹이/포만도 수치·주기가 서버와 함께 유실됐다(HARD RULE 6).
##    프레임(`common/bar_food`)은 보유하고 있으니 규칙이 정해지면 여기 한 줄만 살리면 된다.
## ⚫ 후기판 분기(`GameManager+0x6c >= 500`: showPiece/showGems = 핀린·소울 6그룹)는 안 쓴다.
##    우리 에셋 덤프는 구판이고 레퍼런스(2016)도 4그룹이다.
## 반환값 = 패널 하단 y(보조 버튼 줄을 그 아래에 붙이려고).
func _build_panel(a: Dictionary, W: float, top: float, S: float) -> float:
	var PW := PANEL.x
	var PH := PANEL.y
	# 원작: pos.x = layerW + (layerW-670)*(-0.25), anchor(1,0) → 오른쪽에서 그만큼 들어온다.
	var inset: float = clampf((W - 670.0) * 0.25, 40.0, 200.0)
	var pane := Control.new()
	pane.scale = Vector2(PANEL_SCALE, PANEL_SCALE)
	pane.size = Vector2(PW, PH)
	pane.position = Vector2(W - inset - PW * PANEL_SCALE, top)
	_root.add_child(pane)

	var bg := NinePatchRect.new()      # 원작 `common/bg/stat_box` 미보유 → `9patch/train_box4`
	bg.texture = load("res://assets/converted/ninepatch_ui/9patch_train_box4.tres")
	bg.patch_margin_left = 22; bg.patch_margin_right = 22
	bg.patch_margin_top = 16; bg.patch_margin_bottom = 16
	bg.size = Vector2(PW, PH)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(bg)

	var id := int(a.get("id", 1))
	var lvl := int(a.get("level", 1))
	var ddef: Dictionary = Data.get_dragon(id)
	var stage_name := Growth.portrait_stage(a)

	# ── 초상칸 `common/item_box2` @ (55, PH-70) ────────────────────────────────
	var box_w := _cw("common_item_box2", 58.0) * S
	var box := _cspr("common_item_box2", S)
	box.position = Vector2(55, 70)
	pane.add_child(box)
	# 초상만 **그림 id**로 뽑는다(위 `id` 는 마스터 조회용 종 id 라 그대로 둔다).
	var por := _portrait(Icons.art_id_of(a), stage_name, S * 0.62, int(a.get("skin", 0)))
	por.position = Vector2(55, 70)
	pane.add_child(por)
	# 원작: `item/item_small/ele_<속성>` scale 0.4, anchor(0.3,0.7) @ 칸 좌상단
	# ⚠️ 키 이름이 데이터와 다르다 — aqua→water, earth→ground(동굴 `ELE_SMALL` 과 같은 표).
	# 속성도 개체 상속값(`Icons.element_of`) — 커스텀 종은 마스터가 비어 있다.
	var ekey := String(ELE_SMALL.get(Icons.element_of(a), ""))
	if ekey != "" and _man_item_small.has(ekey):
		var eh: float = maxf(1.0, float(_man_item_small[ekey].get("h", 70)))
		var es := _spr("item_small_ui", ekey, 30.0 / eh)
		es.position = Vector2(55 - box_w * 0.5 + 11.0, 70 - box_w * 0.5 + 11.0)
		pane.add_child(es)

	# ── 레벨 / 이름 / 등급 ────────────────────────────────────────────────────
	var lv := _bm_label("레벨 %d" % lvl, 18, Color.WHITE)   # 원작 subtitle ×0.7
	lv.position = Vector2(100, 8); lv.size = Vector2(150, 24)
	pane.add_child(lv)
	var nm := _label(Icons.name_of(a), 20,
		Color(0.9, 0.87, 0.8))
	nm.position = Vector2(100, 32); nm.size = Vector2(160, 22)
	pane.add_child(nm)
	# 파생 등급(§K-10) — 동굴 HUD 와 같은 계산(`Growth.compute_grade`).
	var grade := Growth.compute_grade(ddef, Data.stat_table, a.get("stat_bonus", {}),
		a.get("gain_log", []), Data.level_curve.get("grade", {}))
	var gl := _bm_label("%.1f" % grade, 29, Color(1.0, 0.62, 0.12), "font_rating")
	gl.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.0, 0.9))
	gl.add_theme_constant_override("outline_size", 4)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gl.position = Vector2(PW - 118.0, 6); gl.size = Vector2(100, 30)
	pane.add_child(gl)

	# ── EXP 게이지 @ (100, PH-77) — bar_bg2 → bar_exp → bar_cover → icon_exp ──
	var need := LevelSystem.exp_to_next(Data.level_curve, lvl)
	var cur_exp := int(a.get("exp", 0))
	var ratio: float = clampf(float(cur_exp) / maxf(1.0, float(need)), 0.0, 1.0)
	_gauge(pane, Vector2(100, 77), "common_bar_exp", ratio, S)
	var eicon := _spr("adventure_ui", "scene_adventure_icon_exp", S * 0.85)
	if eicon.texture == null:
		eicon.queue_free()
	else:
		eicon.position = Vector2(100, 77)
		pane.add_child(eicon)
	var bw := _cw("common_bar_bg2", 162.0) * S
	var et := _bm_label("%d / %d" % [cur_exp, need], 15, Color.WHITE, "font_common")
	et.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	et.add_theme_constant_override("outline_size", 3)
	et.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	et.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	et.size = Vector2(bw - 30.0, 18); et.position = Vector2(125, 68)
	pane.add_child(et)

	# ── 스탯 6종 (좌: 생명력/공격력/방어력 · 우: 치명타/방어율/회피율) ────────
	_build_stats(pane, a, PW)

	# ── 그룹 4개 ──────────────────────────────────────────────────────────────
	var gw := box_w + 15.0            # 원작 RoundedLayer(box.w+15, box.h+40)
	var gh := box_w + 40.0
	var wide := 220.0                 # 0x435c0000
	_build_item_group(pane, a, Vector2(60.0 - gw * 0.5, 265.0 - gh * 0.5), Vector2(gw, gh), S)
	_build_gem_group(pane, a, Vector2(60.0 + gw * 0.5 + 5.0, 265.0 - gh * 0.5), Vector2(wide, gh), S)
	_build_drink_group(pane, a, Vector2(60.0 - gw * 0.5, 385.0 - gh * 0.5), Vector2(gw, gh), S)
	_build_skill_group(pane, a, Vector2(60.0 + gw * 0.5 + 5.0, 385.0 - gh * 0.5), Vector2(wide, gh), S)
	return pane.position.y + PH * PANEL_SCALE

## `bar_bg2`(빈 홈) → 채움 프레임(가로 ratio) → `bar_cover`(유리). 전부 162×11, anchor(0,0.5).
## 종전엔 `9patch/bar1` 로 자작하고 있었다 — 세 프레임 다 원본에 있다.
func _gauge(pane: Control, at: Vector2, fill_key: String, ratio: float, S: float) -> void:
	var bh := _ch("common_bar_bg2", 11.0) * S
	for k in ["common_bar_bg2", fill_key, "common_bar_cover"]:
		var sp := _cspr(k, S)
		if sp.texture == null:
			sp.queue_free(); continue
		sp.centered = false
		if k == fill_key:
			if ratio <= 0.0:
				sp.queue_free(); continue
			sp.scale = Vector2(S * ratio, S)
		sp.position = Vector2(at.x, at.y - bh * 0.5)
		pane.add_child(sp)

## 원작: 좌열 라벨 anchor(1,0.5) @ x=90, 우열 라벨 anchor(0,0.5) @ x=W/2+30, 행 y = H-130/-157/-184.
## 값은 라벨 오른쪽에 이어 붙인다(`font_common`). 우리는 "실 스탯 + 장비보정" 을 원작 표기
## (`953 + 2653`)와 같은 형식으로 나눈다.
func _build_stats(pane: Control, a: Dictionary, PW: float) -> void:
	var ddef: Dictionary = Data.get_dragon(int(a.get("id", 1)))
	var base_bonus: Dictionary = (a.get("stat_bonus", {}) as Dictionary).get("base", {})
	var main: Dictionary = Growth.main_stats(ddef, Data.stat_table, a.get("gain_log", []), base_bonus)
	var total: Dictionary = Gem.apply(main.duplicate(), a.get("gems", {}), Data.gems)
	total = Equipment.apply(total, a.get("equip", {}), Data.equipment)

	var rows_l := [["생명력", "hp"], ["공격력", "att"], ["방어력", "def"]]
	var rows_r := [["치명타", "cri"], ["방어율", "blk"], ["회피율", "evd"]]
	for i in 3:
		var y: float = [130.0, 157.0, 184.0][i]
		var kl: String = String(rows_l[i][1])
		var add: int = int(total.get(kl, 0)) - int(main.get(kl, 0))
		var txt := "%d" % int(main.get(kl, 0))
		if add != 0: txt += " + %d" % add
		var ll := _bm_label("%s : " % String(rows_l[i][0]), 19, Color(0.72, 0.68, 0.6))
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ll.size = Vector2(86, 22); ll.position = Vector2(4, y - 11)
		pane.add_child(ll)
		var lv := _bm_label(txt, 19, Color(0.98, 0.96, 0.9), "font_common")
		lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lv.size = Vector2(110, 22); lv.position = Vector2(94, y - 11)
		pane.add_child(lv)

		var kr: String = String(rows_r[i][1])
		# 원작은 좌우 두 열 모두 라벨 anchor(1,0.5) = **우측정렬**이라 콜론이 세로로 맞는다
		# (레퍼런스 `docs/ref/orig_image/cave/status/Cave_status.jpg`).
		var rl := _bm_label("%s : " % String(rows_r[i][0]), 19, Color(0.72, 0.68, 0.6))
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rl.size = Vector2(86, 22); rl.position = Vector2(PW * 0.5 + 10.0, y - 11)
		pane.add_child(rl)
		var rv := _bm_label("+%d%%" % int(total.get(kr, 0)), 19, Color(0.98, 0.96, 0.9), "font_common")
		rv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rv.size = Vector2(76, 22); rv.position = Vector2(PW * 0.5 + 102.0, y - 11)   # 라벨(우측정렬, ~277)과 6pt 간격
		pane.add_child(rv)

# ------------------------------------------------------------ 그룹 공통
## 그룹 받침 + 제목(원작 anchor(0.5,1) @ (w/2, h-8), font_subtitle scale 0.7).
func _group(pane: Control, at: Vector2, size: Vector2, title: String) -> Control:
	var g := Control.new()
	g.position = at
	g.size = size
	pane.add_child(g)
	var r := _rounded(size, Color(1, 1, 1, GROUP_ALPHA), 10)
	g.add_child(r)
	var t := _bm_label(title, 18, Color(0.24, 0.2, 0.14))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size = Vector2(size.x, 20); t.position = Vector2(0, 4)
	g.add_child(t)
	return g

## 칸 히트박스(원작 `CCMenuItemImageEx` + `setClickInfo`).
func _hit(g: Control, center: Vector2, box: float, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.tooltip_text = tip
	b.size = Vector2(box, box)
	b.position = center - Vector2(box, box) * 0.5
	if cb.is_valid():
		b.pressed.connect(cb)
	g.add_child(b)
	return b

func _icon(g: Control, tex: Texture2D, center: Vector2, scale: float) -> Sprite2D:
	if tex == null: return null
	var s := Sprite2D.new()
	s.texture = tex
	s.material = _pma
	s.scale = Vector2(scale, scale)
	s.position = center
	g.add_child(s)
	return s

# ------------------------------------------------------------ 아이템(장비) 그룹
## 원작 `showItems` — `item_box2` 1칸 anchor(0.5,0) @ (w/2, 10) 안에 `MultyEquipView`.
## ⚠️ 후기판 4칸(2×2)의 배경 `9patch/scale_streng_gear*` 는 우리 덤프에 없다(§10) → 구판 1칸.
func _build_item_group(pane: Control, a: Dictionary, at: Vector2, size: Vector2, S: float) -> void:
	var g := _group(pane, at, size, "아이템")
	var box := _cw("common_item_box2", 58.0) * S
	var c := Vector2(size.x * 0.5, size.y - 10.0 - box * 0.5)
	_icon(g, _tex("common_ui", "common_item_box2"), c, S)
	var eqf: Dictionary = a.get("equip", {})
	var shown := 0
	var tip := "장비"
	for sid: String in Equipment.slot_ids(a.get("equip_slots", 1)):
		var sd: Dictionary = Equipment.equipped(eqf, sid, Data.equipment)
		if sd.is_empty(): continue
		if shown == 0:
			_icon(g, Icons.equip_texture(sd), c, S * 0.55)
			tip = String(sd.get("name", "장비"))
		shown += 1
	if shown > 1:
		var n := _bm_label("×%d" % shown, 25, Color(1, 0.95, 0.75), "font_title")
		n.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		n.add_theme_constant_override("outline_size", 3)
		n.position = c + Vector2(box * 0.5 - 22.0, box * 0.5 - 20.0)
		n.size = Vector2(30, 18)
		g.add_child(n)
		tip += " 외 %d" % (shown - 1)
	elif shown == 0:
		_icon(g, _tex("common_ui", "common_item_box2_plus"), c, S * 0.8)
		tip = "비어 있음"
	_hit(g, c, box, "%s\n(클릭: 장비 관리)" % tip, func(): _act("equip"))

# ------------------------------------------------------------ 젬 그룹
## 원작 `_showGems` — 칸 3개, 칸 프레임은 `Dragon::getGemType(i)` 별 `gem_box1~4`.
##   slot0 anchor(0,0.5) @ (10, h/2-10) · slot1 anchor(0.5,0.5) @ (w/2, h/2-10)
##   slot2 anchor(1,0.5) @ (w-10, h/2-10) · 장착 젬 아이콘 scale 0.6
func _build_gem_group(pane: Control, a: Dictionary, at: Vector2, size: Vector2, S: float) -> void:
	var g := _group(pane, at, size, "젬")
	var gf: Dictionary = a.get("gems", {})
	var types := Gem.types(gf)
	var en := Gem.entries(gf)
	var kr: Dictionary = (Data.gems.get("slot_types", {}) as Dictionary).get("kr", {})
	var box := _cw("common_gem_box1", 44.0) * S
	var cy: float = size.y - (size.y * 0.5 - 10.0)
	var xs := [10.0 + box * 0.5, size.x * 0.5, size.x - 10.0 - box * 0.5]
	for i in Gem.SLOTS:
		var ty := String(types[i])
		var c := Vector2(float(xs[i]), cy)
		_icon(g, _tex("common_ui", String(GEM_BOX.get(ty, "common_gem_box4"))), c, S)
		var tip := "%d번 칸 (%s)" % [i + 1, String(kr.get(ty, ty))]
		if en[i] != null:
			var gname := String(en[i]["name"])
			var tier := int(en[i]["tier"])
			_icon(g, Icons.gem_texture(String(Gem.gem_def(gname, Data.gems).get("code", "")), tier),
				c, S * 0.6)
			tip += "\n%s +%d\n(클릭: 젬 관리)" % [gname, tier]
		else:
			tip += "\n비어 있음 (클릭: 장착)"
		var slot := i
		_hit(g, c, box, tip, func(): _act("gem", slot))

# ------------------------------------------------------------ 드링크 그룹
## 원작 initWidget: `item_box2` 1칸 + 비었으면 `item_box2_plus`(펄스 애니) → `Dragon::getBuf`.
## 차 있으면 그 아이템 아이콘을 **scale 0.8**(0x3f4ccccd)로 얹는다. 칸을 누르면
## `CharacterInfoPopup::setClickInfo` 가 `DrinkPopup::create(dragon)` 를 연다.
##
## 🔴 2026-08-05 정정(사용자 지적 "드링크 칸이 미구현으로 막힌다") — 종전 주석
##   "효과·지속시간이 서버와 함께 유실됐다"는 **틀렸다.** 규칙은 위키 item.pdf §2.3 에 있고
##   수치는 사용자가 2026-07-26 확정했다(`data/item_effects.json`). 판정(`ItemEffect`)·
##   저장(`drink_buffs`)·전투 반영(`PartyStats`)·턴 차감(`battle.gd`)까지 전부 이미 있었고
##   **이 칸의 배선만** 없었다. ⇒ `DrinkPopup` 을 붙인다.
##
## ⚠️ 어휘 — 우리 `drink_buffs` 는 아이템이 아니라 **능력치 축별 누적**이라
##   ({att:{pct,turns}, …}) 칸에는 그 축의 대표 드링크 아이콘을 낸다.
const DRINK_ICON := {"att": "att_drink1", "def": "def_drink1", "hp": "hp_drink1",
	"crit": "cri_drink1", "dodge": "miss_drink1", "block": "prodef_drink1"}
const DRINK_KR := {"att": "공격력", "def": "방어력", "hp": "생명력",
	"crit": "크리티컬", "dodge": "회피", "block": "방어확률"}

func _build_drink_group(pane: Control, a: Dictionary, at: Vector2, size: Vector2, S: float) -> void:
	var g := _group(pane, at, size, "드링크")
	var box := _cw("common_item_box2", 58.0) * S
	var c := Vector2(size.x * 0.5, size.y - 10.0 - box * 0.5)
	_icon(g, _tex("common_ui", "common_item_box2"), c, S)

	var buffs: Dictionary = a.get("drink_buffs", {})
	var tip := "버프 드링크\n(클릭: 먹이기)"
	if buffs.is_empty():
		# 원작: 비었으면 `item_box2_plus`. (펄스 ScaleTo 0.2/1.15→0.2/1.1→0.5/1.2→0.5/1.0 반복)
		var plus := _icon(g, _tex("common_ui", "common_item_box2_plus"), c, S * 0.8)
		if plus != null:
			var base := plus.scale
			var tw := plus.create_tween().set_loops()
			for f in [[0.2, 1.15], [0.2, 1.1], [0.5, 1.2], [0.5, 1.0]]:
				tw.tween_property(plus, "scale", base * float(f[1]), float(f[0]))
	else:
		# 가장 오래 남은 축을 대표로 그린다(원작은 아이템 하나라 대표가 자명하다).
		var top := ""
		for k in buffs.keys():
			if top == "" or int((buffs[k] as Dictionary).get("turns", 0)) \
					> int((buffs[top] as Dictionary).get("turns", 0)):
				top = String(k)
		var ip := Data.item_icon_path(String(DRINK_ICON.get(top, "")))
		if ip != "" and ResourceLoader.exists(ip):
			_icon(g, load(ip), c, S * 0.8)          # 원작 setScale(0x3f4ccccd = 0.8)
		var lines: Array = []
		for k2 in buffs.keys():
			var e: Dictionary = buffs[k2]
			lines.append("%s +%d%%  (%d턴)" % [String(DRINK_KR.get(String(k2), String(k2))),
				int(e.get("pct", 0)), int(e.get("turns", 0))])
		lines.sort()
		tip = "\n".join(PackedStringArray(lines)) + "\n(클릭: 먹이기)"

	var uid := int(a.get("uid", _uid))
	# 봇 레코드(콜로세움 상대)는 세이브에 없다 — 먹일 대상이 아니므로 창을 안 연다.
	if uid <= 0 or UserDB.get_dragon(uid).is_empty():
		_hit(g, c, box, "버프 드링크", func(): pass)
		return
	_hit(g, c, box, tip, func() -> void:
		DrinkPopup.open(self, uid, func() -> void: _redraw(uid)))


## 드링크를 먹인 뒤 화면만 다시 그린다 — 원작 `setReloadPopupForDrink` 가 `initWidget` 을
## 통째로 다시 부르는 자리다. 단독 패널 모드는 `_record` 를 세이브에서 다시 읽어야 한다.
func _redraw(uid: int) -> void:
	if not _record.is_empty():
		var fresh := UserDB.get_dragon(uid)
		if not fresh.is_empty():
			_record = fresh
		# 가림판까지 통째로 지우고 다시 그린다(`_root` 만 지우면 판이 겹쳐 쌓인다).
		for ch in get_children():
			ch.queue_free()
		_root = null
		_build()
		return
	_reopen(uid)

# ------------------------------------------------------------ 스킬 그룹
## 원작 initWidget 스킬 루프:
##   미각성: slot0 anchor(1,0.5) @ (w/2-5, h/2-5) · slot1 anchor(0,0.5) @ (w/2+5, h/2-5)
##   각성:   제목 @ (2w/3-5, h-8) / slot0 @ (w/2, h/2-5) · slot1 @ (5w/6-4, …) 둘 다 scale 0.9
##           + 각성스킬 `common/skill_evolution` @ (w/6+7, h/2-1) · 제목 "각성스킬" @ (w/6+5, h-8)
##   칸 배경 = 칸 타입(△□○☆)의 `_bg`, 장착 스킬 타입이 칸과 같으면 테두리(`skill_{모양}`)를
##   **먼저** 얹고 그 위에 스킬 아이콘 scale 0.6. Lv10/Lv35 미달이면 `common/lock`.
func _build_skill_group(pane: Control, a: Dictionary, at: Vector2, size: Vector2, S: float) -> void:
	var awakened := bool(a.get("awakened", false))
	var g := _group(pane, at, size, "스킬" if not awakened else "")
	var lvl := int(a.get("level", 1))
	var stypes := Loadout.slot_types(a)
	# 칸에 보이는 건 **장착분**(원작 Dragon::getSkill(slot))이지 학습 풀 전체가 아니다.
	var equipped := Loadout.equipped_ids(a)
	var box := _cw("common_skill_circle_bg", 65.0) * S
	var cy: float = size.y - (size.y * 0.5 - 5.0)
	var sc := 0.9 if awakened else 1.0

	if awakened:
		# 각성 시 제목이 2/3 지점으로 밀리고 왼쪽 1/6 자리에 각성스킬 칸이 들어온다.
		var t := _bm_label("스킬", 18, Color(0.24, 0.2, 0.14))
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.size = Vector2(90, 20); t.position = Vector2(size.x * 2.0 / 3.0 - 50.0, 4)
		g.add_child(t)
		var at2 := _bm_label("각성스킬", 16, Color(0.24, 0.2, 0.14))
		at2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		at2.size = Vector2(84, 20); at2.position = Vector2(size.x / 6.0 - 37.0, 4)
		g.add_child(at2)
		var ac := Vector2(size.x / 6.0 + 7.0, size.y - (size.y * 0.5 - 5.0 + 4.0))
		_icon(g, _tex("common_ui", "common_skill_evolution"), ac, S * 0.9)
		var aw := int(a.get("awaken_skill", 0))
		# ⚠️ cave.gd 와 같은 주의 — 아이콘 번호 ≠ 각성스킬 번호(시트의 `아이콘 id` 열).
		var aw_icon := Data.awaken_skill_icon(aw) if aw > 0 else 0
		if aw_icon > 0:
			_icon(g, _tex("skill_evolution", "skill_evolution_%d" % aw_icon), ac, S * 0.6)
		var aw_tip := "각성 스킬"
		var aw_row: Dictionary = Data.skill_awaken_for(aw) if aw > 0 else {}
		if not aw_row.is_empty():
			aw_tip = String(aw_row.get("name", aw_tip))
		var aw_hit := _hit(g, ac, box * 0.9, aw_tip, Callable())
		aw_hit.pressed.connect(func():
			if aw > 0:
				DragonAwakenSkillInfoPopup.open(self, aw_hit, aw))

	var xs := ([size.x * 0.5, size.x * 5.0 / 6.0 - 4.0] if awakened
		else [size.x * 0.5 - 5.0 - box * 0.5, size.x * 0.5 + 5.0 + box * 0.5])
	for i in Loadout.SKILL_SLOTS:
		var ty := String(stypes[i])
		var c := Vector2(float(xs[i]), cy)
		_icon(g, _tex("common_ui", String(SKILL_BG.get(ty, "common_skill_star_bg"))), c, S * sc)
		var tip := "%d번 칸 (%s)" % [i + 1, String(SKILL_SLOT_MARK.get(ty, "?"))]
		if not Loadout.slot_unlocked(i, lvl):
			_icon(g, _tex("common_ui", "common_lock"), c, S * 0.8)
			_hit(g, c, box * sc, tip + "\nLv.%d 에 해금" % int(Loadout.SLOT_UNLOCK_LEVEL[i]),
				func(): pass)
			continue
		if int(equipped[i]) > 0:
			var sid := int(equipped[i])
			var sdef: Dictionary = Data.skills.get(str(sid), {})
			# 타입이 일치하면 모양 테두리 + 아이콘이 **함께** 보인다(원작 goto 합류 구조).
			if String(sdef.get("slot", "")) == ty:
				_icon(g, _tex("common_ui", String(SKILL_MARK.get(ty, "common_skill_circle"))),
					c, S * sc)
			_icon(g, _tex("skill", "skill_%d" % sid), c, S * 0.6)
			var lv_e := Loadout.equipped_entry(a, i)
			tip += "\n%s Lv.%d" % [String(sdef.get("name", "스킬")), int(lv_e.get("level", 1))]
			if Loadout.slot_matches(ty, sdef):
				tip += "  (타입 일치 · %s)" % Loadout.slot_match_label(sdef, Data.combat)
			tip += "\n(클릭: 스킬 교체)"
		else:
			tip += "\n비어 있음 (클릭: 장착)"
		var slot := i
		_hit(g, c, box * sc, tip, func(): _act("skill", slot))

# ============================================================ 하단 드래곤 목록
## 원작 `9patch/scroll_box` Scale9 capInsets `CCRect(65,65,6,6)` @ (0,75), 전폭.
## `ScrollViewEx` content 폭 = 슬롯최대 × **120.5** + 70, 안쪽 여백 25.
##
## 🔴 2026-07-30 정정 — 칸 구성이 원작과 달랐다. `StatusLayer::addScroll` @01a60ba8 은
##   **동굴 좌측 목록(`CaveScene::addScroll`)과 똑같은 칸**을 그린다:
##     선택 `common/dragon_bg1`+`dragon_cover1` / 그 외 `dragon_bg2`+`dragon_cover2`
##     초상 `getImagePathBox` ×0.9, 중심 +(0,7.5)
##     레벨 `getString("level", lv)` · `font_subtitle` **BMFont** ×0.8 @ (w/2, 라벨h/2+5)
##     배치 x = (액자폭 + 15)*i + 셀박스/2 + 15 · y = 셀박스/2 + 10 (스크롤 콘텐츠 좌하단 기준)
##   종전엔 `scene/worldmap/status_currentdragon_bg(2)`(= **메인 HUD 전용** 액자)와
##   `status_currentdragon_level`("LEVEL" 구운 라벨) + TTF 숫자를 썼다 — 원작 StatusLayer 는
##   이 셋 중 무엇도 쓰지 않는다(그 프레임들은 `MainHud` 것이다). 프레임·서체 모두 원작으로 교체.
## 🟡 다만 우리 창은 원작에 없는 보조 버튼 줄(`_build_extras`)이 있어 띠 높이가 104pt 뿐이다
##   (원작은 ~135pt). 칸 구성비는 그대로 두고 **셀 전체를 균일 축소**해 넣는다.
func _build_strip(W: float, y: float, strip_h: float) -> void:
	var strip := NinePatchRect.new()
	strip.texture = load("res://assets/converted/ninepatch_ui/9patch_scroll_box.tres")
	strip.patch_margin_left = 65; strip.patch_margin_top = 65
	strip.patch_margin_right = 31; strip.patch_margin_bottom = 31
	strip.size = Vector2(W - 40.0, strip_h)
	strip.position = Vector2(20.0, y)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(strip)

	var owned: Array = UserDB.dragons()
	var S := Design.ASSET_SCALE
	var side := _cw("common_dragon_bg2", 81.0) * S     # 액자 한 변 108pt
	var box := side * SLOT_BOX                          # 셀 박스 113.4pt (CCMenuItemImageEx 1.05)
	var row_h := strip_h - 12.0
	var cs: float = minf(1.0, (row_h - 6.0) / box)      # 띠 높이에 맞춘 균일 축소(위 주석 🟡)
	var step := (side + 15.0) * cs                      # 원작 (액자폭 + 15)
	var scroll := ScrollContainer.new()
	scroll.position = strip.position + Vector2(25.0, 6.0)
	scroll.size = Vector2(strip.size.x - 50.0, row_h)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)
	var row := Control.new()
	row.custom_minimum_size = Vector2(owned.size() * step + 70.0, row_h)
	scroll.add_child(row)

	for i in owned.size():
		var d: Dictionary = owned[i]
		var uid := int(d.get("uid", -1))
		var sel := uid == _uid
		# 셀 원점 = 박스 중심. 원작 (x = step*i + box/2 + 15, y = box/2 + 10 · y-up)
		var cell := Node2D.new()
		cell.position = Vector2((15.0 + box * 0.5) * cs + i * step,
			row_h - (10.0 + box * 0.5) * cs)
		cell.scale = Vector2(cs, cs)
		row.add_child(cell)
		cell.add_child(_cspr("common_dragon_bg1" if sel else "common_dragon_bg2", S))
		var por := _portrait(Icons.art_id_of(d),        # 개체의 상속 art_id(커스텀 종 600·700)
			Growth.portrait_stage(d), 0.9 * S, int(d.get("skin", 0)))
		por.position = Vector2(0, -7.5)                 # 원작 +(0,7.5), Godot 은 y 반대
		cell.add_child(por)
		cell.add_child(_cspr("common_dragon_cover1" if sel else "common_dragon_cover2", S))
		# 레벨 — 원작 문자열 "레벨 %d", font_subtitle BMFont ×0.8, 셀 박스 하단에서 5pt 위
		var lv := _bm_label("레벨 %d" % int(d.get("level", 1)),
			int(round(19.0 * S * 0.8)), Color.WHITE)
		lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lv.size = Vector2(box, 26.0)
		lv.position = Vector2(-box * 0.5, box * 0.5 - 5.0 - 26.0)
		cell.add_child(lv)
		var b := Button.new(); b.flat = true
		b.size = Vector2(box * cs, box * cs)
		b.position = cell.position - Vector2(box * cs * 0.5, box * cs * 0.5)
		b.pressed.connect(func(): _reopen(uid))     # 원작 onClickDragon
		row.add_child(b)

# ============================================================ 보조 버튼 — 삭제됨
## 🔴 2026-07-30 삭제(사용자 지시): 원작 상태창에는 **버튼 줄이 없다** — 젬·스킬·장비는
## 위 칸을 직접 눌러 들어간다(`setClickInfo`). 여기 있던 레벨업·잠재능력·오라·각성도감·보관소는
## 우리가 임의로 붙인 줄이었다.
##
## ⚠️ 진입점 정리가 남았다. `action_requested` 는 그대로 살아 있으니(호스트가 처리) 아래를
## **원작 자리**에 붙이면 된다:
##   · 잠재능력 = 원작 `CaveScene::makePotentialButton` @00e6ad40 (동굴 버튼)
##   · 오라     = 원작 동굴 `bt_aura_on`(프레임 미보유, `docs/reimplementation_gaps.md` §CaveScene)
##   · 각성도감 = 우노 마모루딕 연구소(`AwakenDragonLayer`)
##   · 보관소   = 아이템 '드래곤의 고삐' 사용
##   · 레벨업   = 동굴 훈련/레벨업 아이템(이미 있음)
