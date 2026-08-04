extends Control
## 연구소(LaboratoryScene) — 엘피스, 애니의 연구소. render 층(§8).
##
## 원작 구성(2026-07-29 전면 재이식 — docs/ref/Lab 스크린샷 17장 + 디컴프 정독):
##   · **층 구조**(`LaboratoryScene::initMenu(int floor, bool, bool)` + `changeFloor`):
##       floor 0  = 1F 메뉴(카드 격자)          bg `laboratory.jpg`
##       floor 1  = 내부(연구소 강화 용광로)     bg `laboratory0.jpg` + `LaboratoryUpgradeLayer`
##       floor -1 = B1(결정 생산/추출)          bg `laboratory3.jpg`(생산)/`laboratory1.jpg`(추출)
##                  + `CrystalLayer(0x65/0x66)` + 깃발 탭 `common/tab_bg`+`txt_crystal1/2_%s`
##     층 전환 = 검은 오버레이 CCFadeTo(0.3)+배경 Shake(0.5,2.0) (`changeFloor`).
##   · **메뉴 라우팅**(`selectTab`): 0·1·2 = LaboratoryEggLayer(1/2/3) 팝업(알 강화/조합/방생),
##     3·4 = B1(탭 0/1), 5 = 내부, 6·7 = B1 CrystalLayer(0x67 드래곤강화/0x68 한계돌파, 후기·컷).
##   · **연구소 레벨 바**(`initWidget`): `lv_bg` Scale9 560×40 @ (폭×0.34, y=140) anchor(0.5,0)
##     + "연구소레벨" + `lv_number_bg` 뱃지 + `bar_bg2`(scaleX1.3)+`bar_exp` ProgressTimer
##     + RoundedButton "정보"(120×56, scale0.7) + `alert2`/`alert` 깜빡이(스킬포인트>0).
##   · 하위 = `LaboratorySkillLayer`(상세정보) · `LaboratoryUpgradeSelectLayer`(재료 스피너) ·
##     `CrystalSelectLayer`(드래곤 선택) · `EggSelectLayer`(알/조합서 선택).
##   · 스파인: `u_village_lab_blast`(용광로) · `u_village_lab_st`(B1 기계) — **원본 실재**
##     (DV2/480/scene/laboratory/), scenes/fx/lab_blast.tscn·lab_st.tscn 으로 변환(2026-07-29).
##     🔴 종전 주석 "u_village_lab_blast 는 변환 대상에 없어" 는 **오판**이었다(§3 사례 추가).
##
## ⚠️ 마모루딕 연구소(우노)와 다른 곳이다 — 그쪽은 `MakeSkillLayer`/`BreakDownSkillLayer`(town.gd).
##
## 수치 출처: docs/ref/wiki/labwiki.pdf(§2.8 연구소 강화) + **docs/ref/Lab 스크린샷(원작 직접 관찰)**
## — 결정 생산/추출/방생 규칙·스킬 8종은 스크린샷이 근거다(data/laboratory.json `_source`).

const DIR_UI := "laboratory_ui"
const DIR_BG := "res://assets/converted/laboratory_bg/%s"
const DragonEnhanceRules := preload("res://scripts/systems/dragon_enhance.gd")

## 원작 `LaboratoryScene::initMenu` 가 만드는 메뉴(호출 순서 그대로).
##   icon_egg_upgrade 알 강화 · icon_egg_mix 알 조합 · icon_egg_release 알 방생 ·
##   icon_crystal_make 결정 생산 · icon_crystal_extract 결정 추출 ·
##   icon_laboratory_upgrade 연구소 강화 · icon_streng 드래곤 강화 · icon_legendary 한계돌파
## ⚠️ `icon_streng` · `icon_legendary` 는 추출 아틀라스에 없다(§10 판본 불일치).
##    드래곤 강화는 보유 `icon_element` 로 대체해 유지, 한계돌파는 미구현(레퍼런스에도 NEW 뱃지).
const MENUS := [
	{"key": "egg_up", "label": "알 강화", "icon": "icon_egg_upgrade"},
	{"key": "egg_mix", "label": "알 조합", "icon": "icon_egg_mix"},
	{"key": "egg_release", "label": "알 방생", "icon": "icon_egg_release"},
	{"key": "crystal_make", "label": "결정 생산", "icon": "icon_crystal_make"},
	{"key": "crystal_extract", "label": "결정 추출", "icon": "icon_crystal_extract"},
	{"key": "lab_upgrade", "label": "연구소 강화", "icon": "icon_laboratory_upgrade"},
	{"key": "equip", "label": "드래곤 강화", "icon": "icon_material"},
]

## 드래곤/아이템 속성 → 결정·정기 키, 속성 필터 원형 아이콘(item_small_ui).
## 어휘 주의: 드래곤은 aqua/earth, 아이템 키는 water/ground(정기)·water/earth(결정).
const ELE_CRYSTAL := {"fire": "crystal_fire", "aqua": "crystal_water", "water": "crystal_water",
	"earth": "crystal_earth", "ground": "crystal_earth", "wind": "crystal_wind",
	"light": "crystal_light", "dark": "crystal_dark", "holy": "crystal_holy",
	"chaos": "crystal_chaos", "shadow": "crystal_shadow"}
const ELE_ESSENCE := {"fire": "ele_fire", "aqua": "ele_water", "water": "ele_water",
	"earth": "ele_ground", "ground": "ele_ground", "wind": "ele_wind", "light": "ele_light",
	"dark": "ele_dark", "holy": "ele_holy", "chaos": "ele_chaos", "shadow": "ele_shadow"}
const ELE_FILTER := ["all", "fire", "aqua", "earth", "wind", "light", "dark", "holy", "chaos", "shadow"]
const ELE_SMALL := {
	"all": "item_item_small_ele_all", "fire": "item_item_small_ele_fire",
	"aqua": "item_item_small_ele_water", "water": "item_item_small_ele_water",
	"earth": "item_item_small_ele_ground", "ground": "item_item_small_ele_ground",
	"wind": "item_item_small_ele_wind", "light": "item_item_small_ele_light",
	"dark": "item_item_small_ele_dark", "holy": "item_item_small_ele_holy",
	"chaos": "item_item_small_ele_chaos", "shadow": "item_item_small_ele_shadow"}

var _params: Dictionary = {}
var _pma: CanvasItemMaterial
var _man: Dictionary = {}
var _portrait_manifests: Dictionary = {}
## 층(원작 this+0x180): 0 = 1F 메뉴, 1 = 내부(강화), -1 = B1(결정).
var _floor := 0
## B1 깃발 탭(원작 this+0x1a0): 0 = 결정 생산, 1 = 결정 추출.
var _crystal_tab := 0
## 열려 있는 기능 팝업의 메뉴 index(-1 = 없음). 대사 선택에만 쓴다(`_lab_talk`).
var _tab := -1
var _npc: NpcPortrait
var _box: BottomTextBox
var _popup: OrigPopup
var _money_root: Control
var _skill_popup: Control
var _select_popup: OrigPopup
var _b1_timer: Timer
var _transition := false

func enter(params: Dictionary = {}) -> void:
	# 원작 LaboratoryScene.c:1979 — "music/bg_laboratory.mp3".
	Bgm.play("bg_laboratory")
	_params = params
	if _pma != null: _rebuild()

func _cfg() -> Dictionary:
	return Data.laboratory

func _ready() -> void:
	_pma = CanvasItemMaterial.new(); _pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_rebuild()

func _vis() -> Vector2:
	return get_viewport_rect().size

func _load_man() -> void:
	if not _man.is_empty(): return
	var p := "res://assets/converted/%s/_manifest.json" % DIR_UI
	if FileAccess.file_exists(p):
		var d = JSON.parse_string(FileAccess.open(p, FileAccess.READ).get_as_text())
		if d is Dictionary: _man = d

func _spr(name: String, scale := 1.0) -> Sprite2D:
	var key := "scene_laboratory_%s" % name
	var p := "res://assets/converted/%s/%s.tres" % [DIR_UI, key]
	if not ResourceLoader.exists(p): return null
	var s := Sprite2D.new(); s.texture = load(p); s.material = _pma
	s.scale = Vector2(scale, scale)
	return s

# ══════════════════ 층 전환 / 재구성 ═══════════════════════════════════════

func _rebuild() -> void:
	if is_instance_valid(_b1_timer):
		_b1_timer.queue_free()
		_b1_timer = null
	for c in get_children(): c.queue_free()
	_load_man()
	var vis := _vis()
	var S := Design.ASSET_SCALE
	match _floor:
		1:
			_build_bg("laboratory0.jpg")
			_build_title(vis, "드래곤 연구소 내부", true)
			_build_upgrade_floor(vis, S)
			_build_lab_level(vis)
		-1:
			_build_bg("laboratory3.jpg" if _crystal_tab == 0 else "laboratory1.jpg")
			_build_title(vis, "드래곤 연구소 B1", true)
			# 깃발 탭은 결정 생산/추출일 때만 — 드래곤 강화(0x67)는 원작도 탭 없이 들어간다
			# (`initMenu` 의 `if (param_2)` 갈래가 `setTabMenus` 를 부르지 않는다).
			if _crystal_tab < 2:
				_build_crystal_tabs(vis)
			_build_b1(vis, S)
		_:
			_build_bg("laboratory.jpg")
			_build_title(vis, "드래곤 연구소", false)
			# 원작 initMenu 는 항상 카드 격자를 그린다 — 기능 화면은 팝업/층 전환이다.
			_build_menu(vis, S)
			_build_lab_level(vis)
	_build_money(vis)
	_build_npc(vis)

func _build_bg(file: String) -> void:
	var bgp := DIR_BG % file
	if ResourceLoader.exists(bgp):
		var full := TextureRect.new(); full.texture = load(bgp)
		full.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		full.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		full.set_anchors_preset(Control.PRESET_FULL_RECT)
		full.mouse_filter = Control.MOUSE_FILTER_IGNORE
		full.name = "Bg"
		add_child(full)
	else:
		var bg := ColorRect.new(); bg.color = Color(0.08, 0.12, 0.14)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

## 원작 `changeFloor(floor, isGenerate, isExtract)` — 검은 오버레이 CCFadeTo(0.3, 255) →
## initMenu 재구성 → CCFadeTo(0.3, 0) + 배경 Shake(0.5, 2.0).
func _goto_floor(f: int, tab := -1) -> void:
	if _transition: return
	_transition = true
	if tab >= 0: _crystal_tab = tab
	var cover := ColorRect.new()
	cover.color = Color(0, 0, 0, 0)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.z_index = 100
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(cover)
	var tw := cover.create_tween()
	tw.tween_property(cover, "color:a", 1.0, 0.3)
	tw.tween_callback(func():
		_floor = f
		# 1F 로 돌아오면 화면 대사도 환영 묶음으로 되돌린다(원작 setTextAgain 끝의 `0x184 = -1`).
		if f == 0:
			_tab = -1
		_rebuild()
		if f != 0:
			_say_floor_talk(f)
		var cover2 := ColorRect.new()
		cover2.color = Color(0, 0, 0, 1)
		cover2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cover2.z_index = 100
		cover2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cover2)
		_shake_bg()
		var tw2 := cover2.create_tween()
		tw2.tween_property(cover2, "color:a", 0.0, 0.3)
		tw2.tween_callback(func():
			cover2.queue_free()
			_transition = false)
		cover.queue_free())

## 원작 changeFloor 의 `Shake::actionWithDuration(0.5, 2.0)` — 배경만 0.5초 진동.
func _shake_bg() -> void:
	var bg := get_node_or_null("Bg")
	if bg == null: return
	var tw := bg.create_tween()
	for i in 6:
		tw.tween_property(bg, "position", Vector2(randf_range(-2, 2), randf_range(-2, 2)), 0.08)
	tw.tween_property(bg, "position", Vector2.ZERO, 0.05)

# ══════════════════ 제목 배너 / 뒤로 ═══════════════════════════════════════

## 원작 `TitleLayer::create("scene/laboratory/top_title_bg.png", <제목>, this, onClickClose)`.
## 구조(`TitleLayer.c:475-517`): 배너 anchor(0.5,1.0) scaleX(폭/1024), 제목 (배너폭/2, 높이×0.65),
## 닫기 `common/close_btn` ×1.5 @ (배너폭×0.93, 높이×0.65).
## 층 1/-1 은 추가로 `common/back_btn` ×1.2 @ leftTop+(50,-35) (initMenu 리터럴).
func _build_title(vis: Vector2, title: String, with_back: bool) -> void:
	var bw := AtlasUI.size_pt(DIR_UI, "scene_laboratory_top_title_bg").x
	var bh := AtlasUI.size_pt(DIR_UI, "scene_laboratory_top_title_bg").y
	var banner := Control.new()
	banner.size = Vector2(bw, bh)
	banner.scale = Vector2(vis.x / maxf(1.0, bw), 1.0)
	banner.position = Vector2.ZERO
	banner.z_index = 10
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	var spr := _spr("top_title_bg", Design.ASSET_SCALE)
	if spr != null:
		spr.position = Vector2(bw, bh) * 0.5
		banner.add_child(spr)
	var inv := maxf(1.0, bw) / vis.x
	var t1 := Label.new(); t1.text = title
	t1.add_theme_font_size_override("font_size", 34)
	t1.add_theme_color_override("font_color", Color(1, 0.86, 0.35))
	t1.add_theme_color_override("font_outline_color", Color(0.25, 0.1, 0.02, 0.95))
	t1.add_theme_constant_override("outline_size", 6)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t1.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t1.size = Vector2(bw, 44)
	t1.position = Vector2(0, bh * 0.35 - 22.0)
	t1.scale = Vector2(inv, 1.0)
	t1.pivot_offset = Vector2(bw * 0.5, 0)
	t1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(t1)
	# 닫기 = 씬 나가기(원작 onClickClose — 어느 층이든 바로 나간다).
	var cs := AtlasUI.size_pt("common_ui", "common_close_btn") * 1.5
	var x := TextureButton.new()
	var ct := AtlasUI.tex("common_ui", "common_close_btn")
	if ct != null:
		x.texture_normal = ct
	x.scale = Vector2(Design.ASSET_SCALE * 1.5 * inv, Design.ASSET_SCALE * 1.5)
	x.position = Vector2(bw * 0.93 - cs.x * 0.5 * inv, bh * 0.35 - cs.y * 0.5)
	x.z_index = 2
	x.pressed.connect(_leave)
	banner.add_child(x)
	if with_back:
		# 원작 back_btn = 1F 로 돌아가기(keyBackClicked 도 floor!=0 이면 changeFloor(0)).
		var bsz := AtlasUI.size_pt("common_ui", "common_back_btn") * 1.2
		var bb := TextureButton.new()
		var bt := AtlasUI.tex("common_ui", "common_back_btn")
		if bt != null:
			bb.texture_normal = bt
		bb.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 1.2
		bb.position = Vector2(50.0, 35.0) - bsz * 0.5
		bb.z_index = 11
		bb.pressed.connect(func(): _goto_floor(0))
		add_child(bb)

func _leave() -> void:
	var from := String(_params.get("from", "town"))
	if from == "worldmap": Scenes.goto("worldmap", {"region": "yutakan"})
	else: Scenes.goto("town", {"area": _params.get("area", "elpis")})

# ══════════════════ 1F 메뉴 격자 ═══════════════════════════════════════════

## 원작 `LaboratoryScene::setItems`(`LaboratoryScene.c:2334`) 1:1. 값 전부 원작:
##   카드 `sub_title_bg` setScale(0.9)·메뉴아이템 setScale(1.1) · `backlight3` 0.35 회전(3s/60°)
##   · 아이콘 (w/2,h/2−10) · 라벨 (w/2,h/2+70) · 4열 · 마지막 줄 가운데 정렬.
## ASSUMPTION: 격자 원점만 디컴프에서 접혀 레퍼런스 실측(1행 상단 cocos 610, 가로 중앙).
const GRID_COLS := 4
const GRID_ROW0_TOP_COCOS := 610.0
## 격자를 화면 중앙에서 왼쪽으로 민 양(디자인 포인트). 원작 `메인화면.png` 도 카드가
## 좌측에 치우쳐 있고(오른쪽은 애니 초상·재화바 자리) 사용자 지시(2026-07-29)로 확정했다.
const GRID_SHIFT_X := -200.0

func _build_menu(vis: Vector2, S: float) -> void:
	var cw := AtlasUI.size_pt(DIR_UI, "scene_laboratory_sub_title_bg").x
	var ch := AtlasUI.size_pt(DIR_UI, "scene_laboratory_sub_title_bg").y
	var gx := cw + 8.0 + 25.0
	var gy := ch + 8.0 + 8.0
	var n := MENUS.size()
	var grid_w := (GRID_COLS - 1) * gx + cw
	var x0: float = round((vis.x - grid_w) * 0.5 + GRID_SHIFT_X)
	var y0 := Design.flip_y(GRID_ROW0_TOP_COCOS)
	for i in n:
		var col := i % GRID_COLS
		var row := i / GRID_COLS
		var dx := 0.0
		if n % GRID_COLS != 0 and (n - n % GRID_COLS) <= i:
			dx = gx * float(GRID_COLS - n % GRID_COLS) * 0.5
		var card := Control.new()
		card.size = Vector2(cw, ch)
		card.position = Vector2(x0 + col * gx + dx, y0 + row * gy)
		card.scale = Vector2(1.1, 1.1)
		card.z_index = 2
		add_child(card)
		var inner := Control.new()
		inner.size = Vector2(cw, ch)
		inner.pivot_offset = Vector2(cw, ch) * 0.5
		inner.scale = Vector2(0.9, 0.9)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(inner)
		var frame := AtlasUI.spr(DIR_UI, "scene_laboratory_sub_title_bg", S)
		if frame != null:
			frame.position = Vector2(cw, ch) * 0.5
			inner.add_child(frame)
		var back := AtlasUI.spr("common_ui", "common_backlight3", 0.35 * S)
		if back != null:
			back.position = Vector2(cw * 0.5, ch * 0.5 + 10.0)
			inner.add_child(back)
			var tw := back.create_tween().set_loops()
			tw.tween_property(back, "rotation", back.rotation + TAU / 6.0, 3.0).as_relative()
		var ic := _spr(String(MENUS[i]["icon"]), S)
		if ic != null:
			ic.position = Vector2(cw * 0.5, ch * 0.5 + 10.0)
			inner.add_child(ic)
		var lbl := Label.new(); lbl.text = String(MENUS[i]["label"])
		lbl.add_theme_font_size_override("font_size", 21)
		lbl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size = Vector2(145.0, 30.0)
		lbl.position = Vector2(cw * 0.5 - 72.5, ch * 0.5 - 70.0 - 15.0)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(lbl)
		var b := Button.new(); b.flat = true
		b.size = Vector2(cw, ch)
		var idx := i
		b.pressed.connect(func(): _open_feature(idx))
		card.add_child(b)

## 원작 `selectTab` 라우팅: 알 3종 = 팝업, 결정 생산/추출 = B1 층, 연구소 강화 = 내부 층.
## 드래곤 강화(0x67 DragonIntension)는 서버 기능이라 오프라인 대체(장비칸 해금 팝업, 위키 §2.1.1).
func _open_feature(idx: int) -> void:
	var key := String(MENUS[idx]["key"])
	match key:
		"crystal_make":
			_tab = idx
			_goto_floor(-1, 0)
			return
		"crystal_extract":
			_tab = idx
			_goto_floor(-1, 1)
			return
		"lab_upgrade":
			_tab = idx
			_goto_floor(1)
			return
		"equip":
			# 원작 selectTab case 6 = `changeFloor(-1, true, false)` → B1 `CrystalLayer(0x67)`.
			_tab = idx
			_goto_floor(-1, 2)
			return
	if is_instance_valid(_popup):
		return
	_tab = idx
	_popup = OrigPopup.open(self, String(MENUS[idx]["label"]))
	_popup.closed.connect(func():
		_tab = -1
		_say(_lab_talk()))
	_build_body(_popup)
	_say(_lab_talk())

## 기능 팝업 안에서 값이 바뀌었을 때 — 내용만 다시 그리고 재화바만 갱신.
func _refresh_feature() -> void:
	if not is_instance_valid(_popup):
		if _floor != 0: _rebuild()
		return
	_popup.clear_content()
	_build_body(_popup)
	_refresh_money()

func _refresh_money() -> void:
	if is_instance_valid(_money_root):
		_money_root.queue_free()
	_build_money(_vis())

func _build_body(pop: OrigPopup) -> void:
	match String(MENUS[_tab]["key"]):
		"egg_up": _body_egg_upgrade(pop)
		"egg_mix": _body_egg_mix(pop)
		"egg_release": _body_egg_release(pop)

# ══════════════════ 연구소 레벨 바 (1F·내부 하단) ══════════════════════════
## 원작 `initWidget`: `lv_bg` Scale9 (560,40) anchor(0.5,0) @ (폭×0.34, cocos y 140), z 90.
##   "연구소레벨"(subtitle 0.85) → `lv_number_bg` 뱃지(레벨, 0.7) → `bar_bg2` scaleX1.3 +
##   `bar_exp` ProgressTimer + "%d/%d"(0.75) → RoundedButton(120×56)×0.7 "정보"(0.8) @ (폭−50, h/2)
##   + `common/alert2`(+`alert` CCBlink 10s×10) — 스킬포인트>0 일 때만 표시.
func _build_lab_level(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var bar_w := 560.0
	var bar_h := 40.0
	var root := Control.new()
	root.size = Vector2(bar_w, bar_h)
	root.position = Vector2(vis.x * 0.34 - bar_w * 0.5, Design.flip_y(140.0) - bar_h)
	root.z_index = 9
	add_child(root)
	var bg := AtlasUI.nine(DIR_UI, "scene_laboratory_lv_bg", Vector2(bar_w, bar_h), Rect2(8, 8, 8, 8))
	if bg != null:
		root.add_child(bg)
	var l := Label.new(); l.text = "연구소레벨"
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(1, 0.97, 0.85))
	l.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.02))
	l.add_theme_constant_override("outline_size", 4)
	l.position = Vector2(10.0, bar_h * 0.5 - 13.0)
	l.size = Vector2(110.0, 26.0)
	root.add_child(l)
	# 레벨 뱃지(원작: 라벨 끝 + 15 − 35 에 anchor(0,0.5) — 뱃지가 라벨을 살짝 문다).
	var badge_x := 112.0
	var bsz := AtlasUI.size_pt(DIR_UI, "scene_laboratory_lv_number_bg")
	var badge := _spr("lv_number_bg", S)
	if badge != null:
		badge.centered = false
		badge.position = Vector2(badge_x, bar_h * 0.5 - bsz.y * 0.5)
		root.add_child(badge)
	var lv := _lab_level()
	var ll := Label.new(); ll.text = str(lv)
	ll.add_theme_font_size_override("font_size", 16)
	ll.add_theme_color_override("font_color", Color(1, 1, 1))
	ll.add_theme_color_override("font_outline_color", Color(0.16, 0.09, 0.03))
	ll.add_theme_constant_override("outline_size", 4)
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ll.size = Vector2(bsz.x, bsz.y)
	ll.position = Vector2(badge_x, bar_h * 0.5 - bsz.y * 0.5)
	root.add_child(ll)
	# 경험 게이지 — 원작 bar_bg2(scaleX 1.3) + bar_exp ProgressTimer(가로 크롭).
	var need := _lab_exp_need(lv)
	var have := _lab_exp()
	var gx := badge_x + bsz.x + 10.0
	var gsz := AtlasUI.size_pt("common_ui", "common_bar_bg2")
	var gw := gsz.x * 1.3
	var gbg := AtlasUI.spr("common_ui", "common_bar_bg2", S)
	if gbg != null:
		gbg.centered = false
		gbg.scale.x *= 1.3
		gbg.position = Vector2(gx, bar_h * 0.5 - gsz.y * 0.5)
		root.add_child(gbg)
	var gfg := AtlasUI.spr("common_ui", "common_bar_exp", S)
	if gfg != null:
		gfg.centered = false
		gfg.scale.x *= 1.3
		gfg.position = Vector2(gx, bar_h * 0.5 - gsz.y * 0.5)
		gfg.region_enabled = true
		var t := gfg.texture
		gfg.region_rect = Rect2(0, 0,
			t.get_width() * clampf(float(have) / maxf(1.0, float(need)), 0.0, 1.0), t.get_height())
		root.add_child(gfg)
	var el := Label.new(); el.text = "%d/%d" % [have, need]
	el.add_theme_font_size_override("font_size", 14)
	el.add_theme_color_override("font_color", Color(1, 1, 1))
	el.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02))
	el.add_theme_constant_override("outline_size", 4)
	el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	el.position = Vector2(gx, bar_h * 0.5 - 11.0)
	el.size = Vector2(gw, 22.0)
	el.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(el)
	# 정보 버튼(원작 RoundedButton 120×56 × scale 0.7 = 84×39, 창 우측 −50).
	var btn_sz := Vector2(120.0, 56.0) * 0.7
	var btn := AtlasUI.frame_button(root, "정보",
		Vector2(bar_w - 50.0 - btn_sz.x * 0.5, bar_h * 0.5 - btn_sz.y * 0.5), btn_sz,
		_show_lab_info, 0)
	# 스킬포인트가 남아 있으면 알림 뱃지(원작 alert2 + alert CCBlink(10,10) 반복).
	if int(UserDB.get_pmeta("lab_points", 0)) > 0 and btn != null:
		var a2 := AtlasUI.spr("common_ui", "common_alert2", Design.ASSET_SCALE)
		if a2 != null:
			a2.position = Vector2(btn_sz.x - 4.0, 4.0)
			btn.add_child(a2)
			var a1 := AtlasUI.spr("common_ui", "common_alert", Design.ASSET_SCALE)
			if a1 != null:
				a2.add_child(a1)
				var tw := a1.create_tween().set_loops()
				tw.tween_property(a1, "visible", false, 0.0).set_delay(0.5)
				tw.tween_property(a1, "visible", true, 0.0).set_delay(0.5)

# ══════════════════ 연구소 강화(레벨/스킬) 수치 ════════════════════════════
## 위키(labwiki.pdf §2.8) 확정: 하루 30개 · 최대 99 · 레벨마다 스킬포인트 1 ·
## 포인트 = 일반알 15 / 3강알 1500 / 정기 5 / 결정 4 / 그림자 결정 100.
## ⚠️ 레벨당 필요 경험치만 위키에도 없다(서버 유실) → data 의 자작 곡선.
func _lab_level() -> int:
	return int(UserDB.get_pmeta("lab_level", 1))

func _lab_exp() -> int:
	return int(UserDB.get_pmeta("lab_exp", 0))

func _lab_exp_need(level: int) -> int:
	var c: Dictionary = _cfg().get("lab_upgrade", {}).get("exp_per_level", {})
	return int(round(float(c.get("base", 900)) * pow(float(c.get("growth", 1.045)), maxi(0, level - 1))))

func _lab_daily_left() -> int:
	var lim := int(_cfg().get("lab_upgrade", {}).get("daily_limit", 30))
	var today := Time.get_date_string_from_system()
	if String(UserDB.get_pmeta("lab_feed_date", "")) != today:
		return lim
	return maxi(0, lim - int(UserDB.get_pmeta("lab_feed_count", 0)))

## 재료 1개가 주는 포인트. 위키 확정치 그대로.
func _feed_points(key: String) -> int:
	var p: Dictionary = _cfg().get("lab_upgrade", {}).get("points", {})
	if key == "crystal_shadow":
		return int(p.get("crystal_shadow", 100))
	if key.begins_with("crystal"):
		return int(p.get("crystal", 4))
	if key.begins_with("ele_"):
		return int(p.get("essence", 5))
	if key.begins_with("mall_") and key.ends_with("_egg"):
		return int(p.get("egg_normal", 15))
	return 0

## 스킬 단계·효과값. data/laboratory.json `skills.list`(8종, 원작 스크린샷 확정 구성).
func _skill_defs() -> Array:
	return _cfg().get("lab_upgrade", {}).get("skills", {}).get("list", [])

func _skill_def(id: String) -> Dictionary:
	for sd in _skill_defs():
		if String((sd as Dictionary).get("id", "")) == id:
			return sd
	return {}

func _skill_step(id: String) -> int:
	var m = UserDB.get_pmeta("lab_skills", {})
	return int((m as Dictionary).get(id, 0)) if m is Dictionary else 0

func _skill_val(id: String, step := -1) -> float:
	var sd := _skill_def(id)
	if sd.is_empty(): return 0.0
	var st := _skill_step(id) if step < 0 else step
	return float(sd.get("base", 0)) + float(sd.get("per", 0)) * st

## 표시 문자열(원작 addCell 의 case 분기: %1.f%% / %d개 / %d원 / 다이아 / %.1f%% / %.1f).
func _skill_fmt(sd: Dictionary, step: int) -> String:
	var v := float(sd.get("base", 0)) + float(sd.get("per", 0)) * step
	match String(sd.get("fmt", "")):
		"pct0": return "%d%%" % int(round(v * 100.0))
		"pct1": return "%.1f%%" % (v * 100.0)
		"pct_gold": return "%d%% 감소" % int(round(v * 100.0))
		"gold": return "%s원" % AtlasUI.comma(int(v))
		"cnt": return "%d개" % int(v)
		"grade": return "%.1f" % v
	return str(v)

# ══════════════════ 내부 층 — 연구소 강화 용광로 ═══════════════════════════
## 원작 `LaboratoryUpgradeLayer::initWidget`: `u_village_lab_blast` 스파인을 320×320 컨테이너
## 중앙에 두고 (폭×0.4, 높이−345) 에 배치. `icon_fire` = 중앙+(-2,-13),
## 일일 카운터 = RoundedLayer(120×45 흑39%)×0.65 @ 중앙+(0,-53), "%d / 30".
## 상태: 만렙(99)→"off" · 오늘 소진→"off"+문구 · 가능→"normal". 클릭 → 재료 선택창.
func _build_upgrade_floor(vis: Vector2, S: float) -> void:
	# 원작 컨테이너 중심 = cocos(폭×0.4, 높이−345). cocos y 는 바닥 기준 → godot y = 345.
	var center := Vector2(vis.x * 0.4, 345.0)
	var left := _lab_daily_left()
	var maxed := _lab_level() >= int(_cfg().get("lab_upgrade", {}).get("max_level", 99))
	var sp := _spine("res://scenes/fx/lab_blast.tscn", center, S,
		"off" if (maxed or left <= 0) else "normal")
	if sp == null:
		var fire0 := _spr("icon_fire", S * 2.2)
		if fire0 != null:
			fire0.position = center
			add_child(fire0)
	# 불 아이콘 + 일일 카운터(원작 좌표: 스파인 중앙 근처).
	if not maxed:
		var fire := _spr("icon_fire", S)
		if fire != null:
			fire.position = center + Vector2(-2.0, 13.0)
			fire.z_index = 3
			add_child(fire)
			if left > 0:
				var ft := fire.create_tween().set_loops()
				ft.tween_property(fire, "modulate", Color(1, 0.82, 0.45), 0.5).set_trans(Tween.TRANS_SINE)
				ft.tween_property(fire, "modulate", Color(1, 1, 1), 0.5).set_trans(Tween.TRANS_SINE)
		var cnt := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.39)
		sb.set_corner_radius_all(10)
		cnt.add_theme_stylebox_override("panel", sb)
		cnt.size = Vector2(120.0, 45.0) * 0.65
		cnt.position = center + Vector2(-cnt.size.x * 0.5, 53.0 - cnt.size.y * 0.5)
		cnt.z_index = 3
		add_child(cnt)
		var cl := Label.new()
		cl.text = "%d / %d" % [left, int(_cfg().get("lab_upgrade", {}).get("daily_limit", 30))]
		cl.add_theme_font_size_override("font_size", 15)
		cl.add_theme_color_override("font_color", Color(1, 1, 1))
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cl.size = cnt.size
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cnt.add_child(cl)
	# 용광로 클릭 → 재료 선택창(원작 onClickFurnace → LaboratoryUpgradeSelectLayer).
	var hit := Button.new(); hit.flat = true
	hit.size = Vector2(320.0, 320.0)
	hit.position = center - hit.size * 0.5
	hit.z_index = 4
	hit.pressed.connect(func():
		if _lab_level() >= int(_cfg().get("lab_upgrade", {}).get("max_level", 99)):
			_toast("연구소가 이미 최대 레벨이야.")
			return
		if _lab_daily_left() <= 0:
			_toast("오늘 넣을 수 있는 재료를 다 썼어. 0시에 초기화돼.")
			return
		_open_feed_select())
	add_child(hit)

## 스파인 씬 인스턴스(scenes/fx/*, build_spine_scene 산출). anim 이름을 골라 재생.
func _spine(path: String, at: Vector2, scale: float, anim := "") -> Node2D:
	if not ResourceLoader.exists(path):
		return null
	var n := (load(path) as PackedScene).instantiate() as Node2D
	n.position = at
	n.scale = Vector2(scale, scale)
	n.z_index = 2
	add_child(n)
	var ap := n.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap != null:
		var pick := anim
		if pick == "" or not ap.has_animation(pick):
			var names := ap.get_animation_list()
			pick = names[0] if names.size() > 0 else ""
		if pick != "":
			ap.get_animation(pick).loop_mode = Animation.LOOP_LINEAR
			ap.play(pick)
	return n

## 재료 선택창 — 원작 `LaboratoryUpgradeSelectLayer`(9patch/popup4 + 제목 "재료") +
## `LaboratoryUpgradeTableCell`(알 그리드 + `btn_arrow1_t`/`btn_arrow2_t` ◀▶ 스피너) +
## 우측 "재료 리스트"(scroll_box) + (n/30) + 레벨 게이지 + [강화하기].
## 스크린샷 = docs/ref/Lab/강화재료선택창.png.
func _open_feed_select() -> void:
	if is_instance_valid(_select_popup): return
	var pop := OrigPopup.open(self, "재료", Vector2(960.0, 600.0))
	pop.body.position.y = maxf(6.0, round((_vis().y - pop.win_size.y) * 0.5))
	_select_popup = pop
	var picks: Dictionary = {}          # key → n
	_feed_select_body(pop, picks)

func _feed_select_body(pop: OrigPopup, picks: Dictionary) -> void:
	pop.clear_content()
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	# 넣을 수 있는 재료(결정·정기·알) 목록.
	var feedable: Array = []
	for key in UserDB.inventory().keys():
		var k := String(key)
		if _feed_points(k) > 0 and UserDB.item_count(k) > 0:
			feedable.append(k)
	feedable.sort()
	var total := 0
	for k in picks: total += int(picks[k])
	var left := _lab_daily_left()
	# ── 좌: 재료 그리드(◀ n ▶ 스피너) ──────────────────────────
	var sc := ScrollContainer.new()
	sc.position = Vector2(36.0, 92.0)
	sc.size = Vector2(W - 340.0, H - 92.0 - 36.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pop.content.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	sc.add_child(grid)
	for k2 in feedable:
		var key := String(k2)
		var have := UserDB.item_count(key)
		var n := int(picks.get(key, 0))
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(140.0, 168.0)
		grid.add_child(cell)
		var bgc := AtlasUI.nine("cave_ui", "scene_cave_dragonbg_nomal", Vector2(140.0, 168.0), Rect2(12, 12, 12, 12))
		if bgc != null: cell.add_child(bgc)
		var nm := Label.new(); nm.text = Data.item_name(key)
		nm.add_theme_font_size_override("font_size", 13)
		nm.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
		nm.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.05))
		nm.add_theme_constant_override("outline_size", 3)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.position = Vector2(4.0, 6.0); nm.size = Vector2(132.0, 18.0)
		cell.add_child(nm)
		var ic := _item_icon(key, Vector2(70.0, 82.0), 0.52)
		if ic != null: cell.add_child(ic)
		var hv := Label.new(); hv.text = "보유 %d" % have
		hv.add_theme_font_size_override("font_size", 12)
		hv.add_theme_color_override("font_color", Color(0.92, 0.88, 0.75))
		hv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hv.position = Vector2(4.0, 118.0); hv.size = Vector2(132.0, 16.0)
		cell.add_child(hv)
		# ◀ n ▶ 스피너(원작 btn_arrow1_t/btn_arrow2_t).
		var nl := Label.new(); nl.text = str(n)
		nl.add_theme_font_size_override("font_size", 17)
		nl.add_theme_color_override("font_color", Color(1, 1, 1) if n > 0 else Color(0.85, 0.8, 0.7))
		nl.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.05))
		nl.add_theme_constant_override("outline_size", 4)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.position = Vector2(40.0, 136.0); nl.size = Vector2(60.0, 24.0)
		cell.add_child(nl)
		var mk_arrow := func(right: bool, cb: Callable) -> void:
			var ar := AtlasUI.spr("common_ui", "common_btn_arrow2_t" if right else "common_btn_arrow1_t", Design.ASSET_SCALE)
			if ar != null:
				ar.position = Vector2(120.0 if right else 20.0, 148.0)
				cell.add_child(ar)
			var ab := Button.new(); ab.flat = true
			ab.size = Vector2(36.0, 34.0)
			ab.position = Vector2(102.0 if right else 2.0, 131.0)
			ab.pressed.connect(cb)
			cell.add_child(ab)
		var kk := key
		mk_arrow.call(false, func():
			if int(picks.get(kk, 0)) > 0:
				picks[kk] = int(picks.get(kk, 0)) - 1
				if int(picks[kk]) == 0: picks.erase(kk)
				_feed_select_body(pop, picks))
		mk_arrow.call(true, func():
			var t2 := 0
			for p in picks: t2 += int(picks[p])
			if int(picks.get(kk, 0)) < UserDB.item_count(kk) and t2 < _lab_daily_left():
				picks[kk] = int(picks.get(kk, 0)) + 1
				_feed_select_body(pop, picks))
	# ── 우: 재료 리스트 + 레벨 게이지 + 강화하기 ───────────────
	var rx := W - 286.0
	var head := Label.new(); head.text = "재료 리스트"
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	head.position = Vector2(rx, 66.0); head.size = Vector2(160.0, 26.0)
	pop.content.add_child(head)
	var cap := Label.new(); cap.text = "(%d/%d)" % [total, left]
	cap.add_theme_font_size_override("font_size", 16)
	cap.add_theme_color_override("font_color", Color(0.55, 0.35, 0.15))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cap.position = Vector2(W - 120.0, 68.0); cap.size = Vector2(84.0, 24.0)
	pop.content.add_child(cap)
	var listbg := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", Vector2(250.0, H - 100.0 - 160.0), Rect2(16, 16, 16, 16))
	if listbg != null:
		listbg.position = Vector2(rx, 100.0)
		pop.content.add_child(listbg)
	var lsc := ScrollContainer.new()
	lsc.position = Vector2(rx + 12.0, 112.0)
	lsc.size = Vector2(226.0, H - 124.0 - 172.0)
	lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pop.content.add_child(lsc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	lsc.add_child(col)
	var pts := 0
	var pkeys: Array = picks.keys(); pkeys.sort()
	for pk in pkeys:
		var cnt := int(picks[pk])
		pts += _feed_points(String(pk)) * cnt
		var rl := Label.new()
		rl.text = "%s ×%d  (+%d)" % [Data.item_name(String(pk)), cnt, _feed_points(String(pk)) * cnt]
		rl.add_theme_font_size_override("font_size", 14)
		rl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		col.add_child(rl)
	# 레벨 뱃지 + 게이지(원작: 우하단 `레벨 N` + bar).
	var lv := _lab_level()
	var need := _lab_exp_need(lv)
	var have2 := _lab_exp()
	var gy := H - 132.0
	var lvl := Label.new(); lvl.text = "레벨 %d" % lv
	lvl.add_theme_font_size_override("font_size", 16)
	lvl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	lvl.position = Vector2(rx, gy); lvl.size = Vector2(70.0, 22.0)
	pop.content.add_child(lvl)
	var gsz := AtlasUI.size_pt("common_ui", "common_bar_bg2")
	var gbg := AtlasUI.spr("common_ui", "common_bar_bg2", Design.ASSET_SCALE)
	if gbg != null:
		gbg.centered = false
		gbg.scale.x *= 0.62
		gbg.position = Vector2(rx + 72.0, gy)
		pop.content.add_child(gbg)
	var gfg := AtlasUI.spr("common_ui", "common_bar_exp", Design.ASSET_SCALE)
	if gfg != null:
		gfg.centered = false
		gfg.scale.x *= 0.62
		gfg.position = Vector2(rx + 72.0, gy)
		gfg.region_enabled = true
		var t3 := gfg.texture
		gfg.region_rect = Rect2(0, 0,
			t3.get_width() * clampf((float(have2) + pts) / maxf(1.0, float(need)), 0.0, 1.0), t3.get_height())
		pop.content.add_child(gfg)
	var gl := Label.new(); gl.text = "%d/%d" % [have2 + pts, need]
	gl.add_theme_font_size_override("font_size", 13)
	gl.add_theme_color_override("font_color", Color(1, 1, 1))
	gl.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02))
	gl.add_theme_constant_override("outline_size", 3)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gl.position = Vector2(rx + 72.0, gy)
	gl.size = Vector2(gsz.x * 0.62 * Design.ASSET_SCALE, 20.0)
	pop.content.add_child(gl)
	pop.add_action_button("강화하기", func(): _feed_confirm(pop, picks), 0,
		Vector2(220.0, 56.0), Vector2(rx + 125.0, H - 62.0))

func _feed_confirm(pop: OrigPopup, picks: Dictionary) -> void:
	var total := 0
	for k in picks: total += int(picks[k])
	if total <= 0:
		_toast("재료를 골라 줘. 화살표로 개수를 정하면 돼.")
		return
	if total > _lab_daily_left():
		_toast("오늘은 %d개까지만 넣을 수 있어." % _lab_daily_left())
		return
	var pts := 0
	for k in picks:
		var kk := String(k)
		var n := int(picks[k])
		if UserDB.item_count(kk) < n: return
		pts += _feed_points(kk) * n
	for k in picks:
		UserDB.use_item(String(k), int(picks[k]))
	var today := Time.get_date_string_from_system()
	if String(UserDB.get_pmeta("lab_feed_date", "")) != today:
		UserDB.set_pmeta("lab_feed_date", today)
		UserDB.set_pmeta("lab_feed_count", 0)
	UserDB.set_pmeta("lab_feed_count", int(UserDB.get_pmeta("lab_feed_count", 0)) + total)
	var lv := _lab_level()
	var exp_now := _lab_exp() + pts
	var maxlv := int(_cfg().get("lab_upgrade", {}).get("max_level", 99))
	var gained := 0
	while lv < maxlv and exp_now >= _lab_exp_need(lv):
		exp_now -= _lab_exp_need(lv)
		lv += 1
		gained += 1
		for r in _cfg().get("lab_upgrade", {}).get("rewards", {}).get(str(lv), []):
			UserDB.add_item(String(r[0]), int(r[1]))
		UserDB.set_pmeta("lab_points", int(UserDB.get_pmeta("lab_points", 0)) + 1)
	UserDB.set_pmeta("lab_level", lv)
	UserDB.set_pmeta("lab_exp", exp_now)
	pop.close()
	_select_popup = null
	_rebuild()
	if gained > 0:
		_lab_levelup_fx()
		_toast("연구소 레벨 %d! 스킬포인트를 %d개 받았어." % [lv, gained])
	else:
		_toast("경험치를 %d 모았어." % pts)

## 연구소 레벨업 연출(원작 = ExpLayer 계열 워드아트 + 깃털) — docs/ref/Lab/연구소렙업.png.
## 워드아트 PNG(자작 절취본, cave 레벨업과 공유) + 깃털 낙하 + 금가루 파티클.
func _lab_levelup_fx() -> void:
	var vis := _vis()
	var center := Vector2(vis.x * 0.4, vis.y * 0.42)
	var wp := "res://assets/converted/lvup_ui/level_up.png"
	if ResourceLoader.exists(wp):
		var w := Sprite2D.new()
		w.texture = load(wp)
		w.position = center
		w.z_index = 60
		w.scale = Vector2(0.2, 0.2)
		add_child(w)
		var tw := w.create_tween()
		tw.tween_property(w, "scale", Vector2(1.15, 1.15), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(w, "scale", Vector2.ONE, 0.1)
		tw.tween_interval(1.2)
		tw.tween_property(w, "modulate:a", 0.0, 0.4)
		tw.tween_callback(w.queue_free)
	CocosParticle.spawn(self, "pt_feature_c", center, 61, 0.8)
	for i in 8:
		var f := AtlasUI.spr("common_ui", "common_feather%d" % (1 + i % 6), Design.ASSET_SCALE)
		if f == null: continue
		f.position = Vector2(randf_range(60.0, vis.x * 0.75), -30.0 - randf_range(0, 120.0))
		f.z_index = 59
		add_child(f)
		var d := randf_range(2.2, 3.6)
		var tw2 := f.create_tween()
		tw2.set_parallel(true)
		tw2.tween_property(f, "position:y", vis.y + 60.0, d)
		tw2.tween_property(f, "position:x", f.position.x + randf_range(-90.0, 90.0), d).set_trans(Tween.TRANS_SINE)
		tw2.tween_property(f, "rotation", randf_range(-2.0, 2.0), d)
		tw2.chain().tween_callback(f.queue_free)

# ══════════════════ B1 층 — 결정 생산/추출 ═════════════════════════════════
## 원작 `CrystalLayer` — 규칙 출처는 전부 docs/ref/Lab B1 스크린샷(원작 직접 관찰):
##   · 선택 조건 "육성 등급이 1.0 이상, 레벨 45 이상"
##   · 생산 = 슬롯 3(2·3번은 x75💎 해금), 드래곤이 N시간 일해서 속성 결정 ×floor(등급).
##     시간 = 38 − 2×floor(등급) (# ASSUMPTION — 관찰 2점 보간, data `_hours_note`)
##   · 추출 = 즉시, 결정 ×floor(등급×100). # ASSUMPTION: 드래곤 소모(아이템 설명 근거).
## 기계 = `u_village_lab_st` 스파인(생산 슬롯 0.77배 / 추출 1.0배 — initGenerateBtn/initExtractBtn),
## 가격/타이머 바 = `scene/promote/train_box1`.

## 슬롯 상태: pmeta "lab_crystal_slots" = [ {}, {}, {} ] 각 원소 {uid,end,item,amount} 또는 {}.
func _slots() -> Array:
	var v = UserDB.get_pmeta("lab_crystal_slots", [])
	var arr: Array = (v as Array).duplicate(true) if v is Array else []
	while arr.size() < 3: arr.append({})
	return arr

func _set_slots(arr: Array) -> void:
	UserDB.set_pmeta("lab_crystal_slots", arr)

func _slots_open() -> int:
	return clampi(int(UserDB.get_pmeta("lab_slots_open", 1)), 1, 3)

## B1 깃발 탭(원작 TitleLayer::setTabMenus → TabMenu, 프레임 `common/tab_bg` +
## `scene/laboratory/txt_crystal1/2_kr`). 선택 탭이 아래로 늘어진다(shop 탭과 같은 문법).
func _build_crystal_tabs(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var labels := ["txt_crystal1_kr", "txt_crystal2_kr"]
	var x := 20.0
	for i in 2:
		var tsz := AtlasUI.size_pt("common_ui", "common_tab_bg")
		var sel := i == _crystal_tab
		var root := Control.new()
		root.size = tsz
		# 깃발은 제목 배너 아래로 늘어진다 — 선택 탭이 더 내려온다(TabMenu 문법).
		root.position = Vector2(x, 78.0 if sel else 58.0)
		root.z_index = 11
		add_child(root)
		var bg := AtlasUI.spr("common_ui", "common_tab_bg", S)
		if bg != null:
			bg.position = tsz * 0.5
			if not sel: bg.modulate = Color(0.72, 0.72, 0.72)
			root.add_child(bg)
		var txt := _spr(labels[i], S)
		if txt != null:
			txt.position = tsz * 0.5 + Vector2(0, 6.0)
			if not sel: txt.modulate = Color(0.8, 0.8, 0.8)
			root.add_child(txt)
		var b := Button.new(); b.flat = true
		b.size = tsz
		var ti := i
		b.pressed.connect(func():
			if ti != _crystal_tab:
				_crystal_tab = ti
				_tab = 3 + ti
				_rebuild()
				_say(_lab_talk()))
		root.add_child(b)
		x += tsz.x + 8.0

func _build_b1(vis: Vector2, S: float) -> void:
	match _crystal_tab:
		0: _build_b1_generate(vis, S)
		2: _build_b1_enhance(vis, S)
		_: _build_b1_extract(vis, S)
	# 남은 시간 갱신 타이머(1초) — 원작 initGenerateBtn 의 CCSequence(Delay 1s + CallFuncN) 반복.
	_b1_timer = Timer.new()
	_b1_timer.wait_time = 1.0
	_b1_timer.timeout.connect(_tick_b1)
	add_child(_b1_timer)
	_b1_timer.start()

## 원작 initGenerateBtn 슬롯 위치(디컴프 리터럴): (폭×0.2, 230) · (폭×0.41, 395) · (폭×0.58, 230).
const B1_SLOTS := [[0.2, 230.0], [0.41, 395.0], [0.58, 230.0]]

func _build_b1_generate(vis: Vector2, S: float) -> void:
	var slots := _slots()
	var open := _slots_open()
	var unlock_dia := int(_cfg().get("crystal", {}).get("produce", {}).get("slot_unlock_dia", 75))
	for i in 3:
		var cx: float = vis.x * float(B1_SLOTS[i][0])
		var cy := Design.flip_y(float(B1_SLOTS[i][1]))
		var center := Vector2(cx, cy)
		var sd: Dictionary = slots[i]
		var locked := i >= open
		var machine := _spine("res://scenes/fx/lab_st.tscn", center, S * 0.77,
			"work_base" if not sd.is_empty() else "nomal")
		if machine != null and locked:
			machine.modulate = Color(0.55, 0.55, 0.55)
		# 가격/타이머 바(train_box1) — 슬롯 하단 중앙(슬롯2는 −15 보정).
		var bar := AtlasUI.spr("promote_ui", "scene_promote_train_box1", S)
		var bar_at := center + Vector2(-15.0 if i == 2 else 0.0, 92.0)
		var bl := Label.new()
		bl.add_theme_font_size_override("font_size", 18)
		bl.add_theme_color_override("font_color", Color(1, 0.97, 0.85))
		bl.add_theme_color_override("font_outline_color", Color(0.12, 0.07, 0.02))
		bl.add_theme_constant_override("outline_size", 4)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if bar != null:
			bar.position = bar_at
			bar.z_index = 3
			add_child(bar)
		var bsz := AtlasUI.size_pt("promote_ui", "scene_promote_train_box1")
		bl.size = Vector2(bsz.x, bsz.y)
		bl.position = bar_at - bl.size * 0.5 + Vector2(0, -2.0)
		bl.z_index = 4
		bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bl)
		if locked:
			bl.text = "x%d" % unlock_dia
			var dia := AtlasUI.spr("common_ui", "common_diamond_small1", S * 0.8)
			if dia != null:
				dia.position = bar_at + Vector2(-42.0, -2.0)
				dia.z_index = 5
				add_child(dia)
			var lk := AtlasUI.spr("common_ui", "common_lock", S)
			if lk != null:
				lk.position = center + Vector2(0, -30.0)
				lk.z_index = 5
				add_child(lk)
		elif sd.is_empty():
			bl.text = "  -  :  -  :  -  "
		else:
			bl.name = "SlotTime%d" % i
			_update_slot_label(bl, sd)
			# 작동 중 — 드래곤 초상 + 생산 파티클(원작은 드래곤 스파인 wait + generate_effect).
			var dd := UserDB.get_dragon(int(sd.get("uid", 0)))
			if not dd.is_empty():
				var por := _portrait_sprite(int(dd.get("id", 0)),
					Growth.stage_for_level(int(dd.get("level", 1))), 0.9)
				if por != null:
					por.position = center + Vector2(0, -85.0)
					por.z_index = 3
					add_child(por)
			CocosParticle.spawn(self, "generate_effect", center + Vector2(0, -20.0), 4, 0.3)
		var hit := Button.new(); hit.flat = true
		hit.size = Vector2(220.0, 190.0)
		hit.position = center - Vector2(110.0, 110.0)
		hit.z_index = 6
		var si := i
		hit.pressed.connect(func(): _click_gen_slot(si))
		add_child(hit)

func _update_slot_label(bl: Label, sd: Dictionary) -> void:
	var left := int(sd.get("end", 0)) - int(Time.get_unix_time_from_system())
	if left <= 0:
		bl.text = "완료! 눌러서 받기"
	else:
		bl.text = "%02d : %02d : %02d" % [left / 3600, (left % 3600) / 60, left % 60]

func _tick_b1() -> void:
	var slots := _slots()
	for i in 3:
		var bl := get_node_or_null("SlotTime%d" % i) as Label
		var sd: Dictionary = slots[i]
		if bl != null and not sd.is_empty():
			_update_slot_label(bl, sd)

func _click_gen_slot(i: int) -> void:
	var slots := _slots()
	var open := _slots_open()
	var cfg: Dictionary = _cfg().get("crystal", {}).get("produce", {})
	if i >= open:
		var dia := int(cfg.get("slot_unlock_dia", 75))
		if i != open:
			_toast("앞 슬롯부터 열 수 있어.")
			return
		_confirm_popup("슬롯 개방", "다이아 %d개로 생산 슬롯을 개방할까?" % dia, func():
			if UserDB.diamond() < dia:
				_toast("다이아가 부족해.")
				return
			UserDB.spend("diamond", dia)
			UserDB.set_pmeta("lab_slots_open", open + 1)
			_rebuild())
		return
	var sd: Dictionary = slots[i]
	if sd.is_empty():
		_open_dragon_select(true, i)
		return
	var left := int(sd.get("end", 0)) - int(Time.get_unix_time_from_system())
	if left > 0:
		_toast("아직 생산 중이야. %d시간 %d분 남았어." % [left / 3600, (left % 3600) / 60])
		return
	# 수령 — 결정 지급 + 드래곤 잠금 해제.
	var item := String(sd.get("item", ""))
	var amount := int(sd.get("amount", 0))
	if item != "" and amount > 0:
		UserDB.add_item(item, amount)
	UserDB.set_dragon_field(int(sd.get("uid", 0)), "lab_busy", false)
	slots[i] = {}
	_set_slots(slots)
	_rebuild()
	_toast("%s %d개를 받았어!" % [Data.item_name(item), amount])
	_refresh_money()

func _build_b1_extract(vis: Vector2, S: float) -> void:
	# 원작 initExtractBtn: RoundedButton(240×180) @ (화면/2 − (폭×0.1, 65)), 기계 1.0배.
	var center := Vector2(vis.x * 0.5 - vis.x * 0.1, Design.flip_y(vis.y * 0.5 - 65.0))
	_spine("res://scenes/fx/lab_st.tscn", center, S, "nomal")
	var hit := Button.new(); hit.flat = true
	hit.size = Vector2(300.0, 220.0)
	hit.position = center - hit.size * 0.5
	hit.z_index = 6
	hit.pressed.connect(func(): _open_dragon_select(false, -1))
	add_child(hit)

## 드래곤 선택 팝업 — 원작 `CrystalSelectLayer`(9patch/popup4 + "드래곤 선택" + 조건문 +
## 가로 카드 리스트). 카드: 속성 원 + 초상 + 등급(금색) + `train_box1` 이름바 +
## `icon_clock` 생산 시간 + "생산/추출 결과물" 박스. 스크린샷 = 생산선택1/추출선택1.png.
func _open_dragon_select(produce: bool, slot_i: int) -> void:
	if is_instance_valid(_select_popup): return
	var pop := OrigPopup.open(self, "드래곤 선택", Vector2(980.0, 600.0))
	pop.body.position.y = maxf(6.0, round((_vis().y - pop.win_size.y) * 0.5))
	_select_popup = pop
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var cfg: Dictionary = _cfg().get("crystal", {}).get("produce" if produce else "extract", {})
	var min_grade := float(cfg.get("min_grade", 1.0))
	if not produce:
		min_grade = _skill_val("extract_grade")     # 추출 등급 감소 스킬이 요구 등급을 낮춘다
	var min_level := int(_cfg().get("crystal", {}).get("produce", {}).get("min_level", 45))
	var note := Label.new()
	note.text = "· 육성 등급이 %.1f 이상, 레벨 %d 이상인 드래곤만 선택 할 수 있습니다." % [min_grade, min_level]
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	note.position = Vector2(44.0, 66.0); note.size = Vector2(W - 88.0, 22.0)
	pop.content.add_child(note)
	var sc := ScrollContainer.new()
	sc.position = Vector2(36.0, 96.0)
	sc.size = Vector2(W - 72.0, H - 96.0 - 40.0)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pop.content.add_child(sc)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	sc.add_child(row)
	var busy_uids: Array = []
	for s in _slots():
		if not (s as Dictionary).is_empty():
			busy_uids.append(int((s as Dictionary).get("uid", 0)))
	var active := UserDB.active_uid()
	for d in UserDB.dragons():
		var dd: Dictionary = d
		var uid := int(dd.get("uid", 0))
		if busy_uids.has(uid): continue
		var card := _dragon_card(dd, produce, min_grade, min_level, uid == active)
		row.add_child(card)
		var lvl := int(dd.get("level", 1))
		var gr := _grade_of(dd)
		var ok := gr >= min_grade and lvl >= min_level
		if ok:
			var b := Button.new(); b.flat = true
			b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var uu := uid
			b.pressed.connect(func(): _confirm_crystal(produce, slot_i, uu))
			card.add_child(b)

func _dragon_card(dd: Dictionary, produce: bool, min_grade: float, min_level: int, is_active: bool) -> Control:
	var ddef := Data.get_dragon(int(dd.get("id", 0)))
	var lvl := int(dd.get("level", 1))
	var gr := _grade_of(dd)
	var ok := gr >= min_grade and lvl >= min_level
	var card := Control.new()
	card.custom_minimum_size = Vector2(300.0, 430.0)
	# 카드 배경(원작 9patch/scale_streng_bg1 — 추출 에셋에 없다 → scene/cave/dragonbg_nomal 대체:
	# 원작 카드가 밝은 크림색이라 어두운 bg_common 보다 이쪽이 가깝다).
	var bg := AtlasUI.nine("cave_ui", "scene_cave_dragonbg_nomal", Vector2(300.0, 430.0), Rect2(12, 12, 12, 12))
	if bg != null: card.add_child(bg)
	# 속성 원(원작 좌상단).
	var el := String(ddef.get("element", ""))
	var ep := "res://assets/converted/item_small_ui/%s.tres" % String(ELE_SMALL.get(el, ELE_SMALL["all"]))
	if ResourceLoader.exists(ep):
		var es := Sprite2D.new(); es.texture = load(ep); es.material = _pma
		es.position = Vector2(38.0, 40.0)
		card.add_child(es)
	# 초상(dragon_bg2 위) + 그림자.
	var por := _portrait_sprite(int(dd.get("id", 0)), Growth.stage_for_level(lvl), 1.5)
	if por != null:
		por.position = Vector2(150.0, 140.0)
		if not ok: por.modulate = Color(0.55, 0.55, 0.55)
		card.add_child(por)
	# 등급(금색, 우하단) — 원작 카드의 큰 숫자.
	var gl := Label.new(); gl.text = "%.1f" % gr
	gl.add_theme_font_size_override("font_size", 30)
	gl.add_theme_color_override("font_color", Color(1, 0.78, 0.18))
	gl.add_theme_color_override("font_outline_color", Color(0.25, 0.14, 0.02))
	gl.add_theme_constant_override("outline_size", 6)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gl.position = Vector2(140.0, 200.0); gl.size = Vector2(140.0, 36.0)
	card.add_child(gl)
	# 이름바(train_box1 늘림) "레벨N 이름".
	var nb := AtlasUI.nine("promote_ui", "scene_promote_train_box1", Vector2(264.0, 40.0), Rect2(20, 12, 20, 12))
	if nb != null:
		nb.position = Vector2(18.0, 244.0)
		card.add_child(nb)
	var nl := Label.new()
	nl.text = "레벨%d %s" % [lvl, Icons.name_of(dd, "?")]
	nl.add_theme_font_size_override("font_size", 17)
	nl.add_theme_color_override("font_color", Color(1, 0.97, 0.85))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.position = Vector2(18.0, 244.0); nl.size = Vector2(264.0, 40.0)
	card.add_child(nl)
	var y := 296.0
	if produce:
		# 생산 시간(icon_clock + "생산 시간 : N시간").
		var hrs := _produce_hours(gr)
		var ck := AtlasUI.spr("achievement_ui", "scene_achievement_icon_clock", Design.ASSET_SCALE * 0.8)
		if ck != null:
			ck.position = Vector2(46.0, y + 14.0)
			card.add_child(ck)
		var tl := Label.new()
		tl.text = "생산 시간 : %s시간" % (str(hrs) if ok else "-")
		tl.add_theme_font_size_override("font_size", 16)
		tl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		tl.position = Vector2(66.0, y + 2.0); tl.size = Vector2(210.0, 24.0)
		card.add_child(tl)
		y += 32.0
	# 결과물 박스.
	var head := Label.new(); head.text = "%s 결과물" % ("생산" if produce else "추출")
	head.add_theme_font_size_override("font_size", 16)
	head.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.position = Vector2(50.0, y); head.size = Vector2(200.0, 22.0)
	card.add_child(head)
	var ibg := AtlasUI.nine("cave_ui", "scene_cave_dragonbg_nomal", Vector2(96.0, 96.0), Rect2(12, 12, 12, 12))
	if ibg != null:
		ibg.position = Vector2(102.0, y + 26.0)
		card.add_child(ibg)
	var ck2 := String(ELE_CRYSTAL.get(el, ""))
	if ok and ck2 != "":
		var ic := _item_icon(ck2, Vector2(150.0, y + 74.0), 0.6)
		if ic != null: card.add_child(ic)
		var amt := _produce_amount(gr) if produce else _extract_amount(gr)
		var al := Label.new(); al.text = "x%d" % amt
		al.add_theme_font_size_override("font_size", 17)
		al.add_theme_color_override("font_color", Color(1, 0.97, 0.85))
		al.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.05))
		al.add_theme_constant_override("outline_size", 4)
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		al.position = Vector2(96.0, y + 96.0); al.size = Vector2(96.0, 22.0)
		card.add_child(al)
	else:
		var ql := Label.new(); ql.text = "결정"
		ql.add_theme_font_size_override("font_size", 20)
		ql.add_theme_color_override("font_color", Color(0.45, 0.38, 0.28))
		ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ql.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ql.position = Vector2(102.0, y + 26.0); ql.size = Vector2(96.0, 96.0)
		card.add_child(ql)
	if is_active:
		var warn := Label.new(); warn.text = "활성 드래곤"
		warn.add_theme_font_size_override("font_size", 13)
		warn.add_theme_color_override("font_color", Color(0.72, 0.16, 0.10))
		warn.position = Vector2(18.0, 6.0)
		card.add_child(warn)
	return card

## 시간 = 38 − 2×floor(등급) 시간 (# ASSUMPTION, data `_hours_note`) × 생산시간감소 스킬.
func _produce_hours(grade: float) -> int:
	var cfg: Dictionary = _cfg().get("crystal", {}).get("produce", {})
	var h := float(cfg.get("hours_base", 38)) + float(cfg.get("hours_per_grade", -2)) * floorf(grade)
	h *= 1.0 - _skill_val("crystal_time")
	return maxi(1, int(round(h)))

func _produce_amount(grade: float) -> int:
	return maxi(1, int(floorf(grade)) + int(_skill_val("crystal_bonus")))

func _extract_amount(grade: float) -> int:
	var cfg: Dictionary = _cfg().get("crystal", {}).get("extract", {})
	var n := floorf(grade * float(cfg.get("yield_per_grade", 100)))
	return maxi(1, int(floorf(n * (1.0 + _skill_val("extract_bonus")))))

func _grade_of(inst: Dictionary) -> float:
	var ddef := Data.get_dragon(int(inst.get("id", 0)))
	return Growth.compute_grade(ddef, Data.stat_table, inst.get("stat_bonus", {}),
		inst.get("gain_log", []), Data.level_curve.get("grade", {}))

## 확인 팝업(원작 생산선택2.png): 썸네일 + "레벨N 이름 등급" + 경고문 + 확인/취소.
func _confirm_crystal(produce: bool, slot_i: int, uid: int) -> void:
	var dd := UserDB.get_dragon(uid)
	if dd.is_empty(): return
	var ddef := Data.get_dragon(int(dd.get("id", 0)))
	var name := Icons.name_of(dd, "?")
	var gr := _grade_of(dd)
	var pop := OrigPopup.open(self, "결정 생산" if produce else "결정 추출", Vector2(640.0, 440.0))
	var por := _portrait_sprite(int(dd.get("id", 0)),
		Growth.stage_for_level(int(dd.get("level", 1))), 0.9)
	if por != null:
		por.position = Vector2(170.0, 170.0)
		pop.content.add_child(por)
	var info := Label.new()
	info.text = "레벨%d\n%s" % [int(dd.get("level", 1)), name]
	info.add_theme_font_size_override("font_size", 22)
	info.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	info.position = Vector2(268.0, 120.0); info.size = Vector2(200.0, 70.0)
	pop.content.add_child(info)
	var gl := Label.new(); gl.text = "%.1f" % gr
	gl.add_theme_font_size_override("font_size", 30)
	gl.add_theme_color_override("font_color", Color(1, 0.78, 0.18))
	gl.add_theme_color_override("font_outline_color", Color(0.25, 0.14, 0.02))
	gl.add_theme_constant_override("outline_size", 6)
	gl.position = Vector2(430.0, 118.0); gl.size = Vector2(100.0, 40.0)
	pop.content.add_child(gl)
	var q := Label.new()
	q.text = "%s의 결정 %s을 시작하시겠습니까?" % [name, "생산" if produce else "추출"]
	q.add_theme_font_size_override("font_size", 19)
	q.add_theme_color_override("font_color", Color(0.72, 0.16, 0.10))
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.position = Vector2(40.0, 250.0); q.size = Vector2(560.0, 26.0)
	pop.content.add_child(q)
	var warn := Label.new()
	warn.text = "*선택한 용은 생산 시간동안 슬롯에서 사라집니다" if produce \
		else "*추출한 드래곤은 라테아로 돌아갑니다 (소모됩니다!)"
	warn.add_theme_font_size_override("font_size", 17)
	warn.add_theme_color_override("font_color", Color(0.16, 0.28, 0.62))
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.position = Vector2(40.0, 286.0); warn.size = Vector2(560.0, 24.0)
	pop.content.add_child(warn)
	var ok_cb := func():
		pop.close()
		_do_crystal(produce, slot_i, uid)
	pop.add_action_button("확인", ok_cb, 0, Vector2(200.0, 52.0), Vector2(220.0, 380.0))
	pop.add_action_button("취소", pop.close, 0, Vector2(200.0, 52.0), Vector2(430.0, 380.0))

func _do_crystal(produce: bool, slot_i: int, uid: int) -> void:
	var dd := UserDB.get_dragon(uid)
	if dd.is_empty(): return
	var ddef := Data.get_dragon(int(dd.get("id", 0)))
	var el := String(ddef.get("element", ""))
	var gr := _grade_of(dd)
	if produce:
		var slots := _slots()
		if slot_i < 0 or slot_i > 2 or not (slots[slot_i] as Dictionary).is_empty():
			return
		# 고유결정(전용 결정) 판정 — 5성+ 드래곤이 unique_bonus 확률로 crystal2_* 를 만든다.
		# ASSUMPTION: 대상/확률 해석은 data `_unique_note`.
		var item := String(ELE_CRYSTAL.get(el, ""))
		var star := int(ddef.get("star", 0))
		var umin := int(_cfg().get("crystal", {}).get("produce", {}).get("unique_star_min", 5))
		if star >= umin and randf() < _skill_val("unique_bonus"):
			var u := "crystal2_%s" % item.trim_prefix("crystal_")
			if Data.items.has(u): item = u
		slots[slot_i] = {
			"uid": uid,
			"end": int(Time.get_unix_time_from_system()) + _produce_hours(gr) * 3600,
			"item": item,
			"amount": _produce_amount(gr),
		}
		_set_slots(slots)
		UserDB.set_dragon_field(uid, "lab_busy", true)
		if is_instance_valid(_select_popup):
			_select_popup.close()
			_select_popup = null
		_rebuild()
		_say("생산을 시작했어! 시간이 지나면 결정을 받을 수 있어.")
	else:
		if uid == UserDB.active_uid():
			_toast("활성 드래곤은 추출할 수 없어. 다른 드래곤을 활성으로 바꿔 줘.")
			return
		var item2 := String(ELE_CRYSTAL.get(el, ""))
		var amount := _extract_amount(gr)
		if not UserDB.release_dragon(uid):
			_toast("이 드래곤은 보낼 수 없어(잠금이 걸려 있는지 확인해 줘).")
			return
		if item2 != "":
			UserDB.add_item(item2, amount)
		if is_instance_valid(_select_popup):
			_select_popup.close()
			_select_popup = null
		# 추출 연출(원작 extraction_base/top 1회) — 기계 스파인을 잠깐 추출 애니로.
		_rebuild()
		_say("%s %d개를 추출했어." % [Data.item_name(item2), amount])
		_refresh_money()

# ══════════════════ 연구소 상세정보(LaboratorySkillLayer) ══════════════════
## 원작 구성(디컴프 실측): 창 = `scene/worldmap/certificate_popup`(양피지, cap(130,190,40,58))
## 670×520 @ ((폭−250)/2, 410). 제목바 pop_title_bg ×0.9 + "연구소 상세정보"(1.2) + btn_info.
## 상단 좌 = lv_bg(400×33) 레벨 게이지, 상단 우 = 흑박스(200×45) "스킬포인트 %d" +
## `bt_laboratory_skill_reset`. 스킬 = 2열×4행, 셀 h 85, `9patch/bt_itembox_off` +
## `laboratory_upgrade_{1..8}`(0.77) + 이름 + 현재값 + `upgrade_gauge_bg/bar`(단계/10) +
## `bt_skill_up`(0.9, 비용 숫자)/`bt_skill_max`. 부족/만렙 = 회색.
func _show_lab_info() -> void:
	if is_instance_valid(_skill_popup): return
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 50
	add_child(overlay)
	_skill_popup = overlay
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	overlay.create_tween().tween_property(dim, "color:a", 127.0 / 255.0, 0.2)
	# 원작 `LabSkillMsg*` — 스킬 화면 전용 대사.
	var sk: Array = (Data.npc_talk.get("screen", {}) as Dictionary).get("lab.skill", {}).get("lines", [])
	if not sk.is_empty():
		_say(String(sk[randi() % sk.size()]))
	_skill_body(overlay)

func _skill_body(overlay: Control) -> void:
	for c in overlay.get_children():
		if c.name == "Win": c.queue_free()
	var vis := _vis()
	var W := 670.0
	var H := 520.0
	var win := Control.new()
	win.name = "Win"
	win.size = Vector2(W, H)
	win.position = Vector2(round((vis.x - 250.0) * 0.5 - W * 0.5), round(Design.flip_y(410.0) - H * 0.5))
	overlay.add_child(win)
	var frame := AtlasUI.nine("worldmap_ui", "scene_worldmap_certificate_popup", Vector2(W, H), Rect2(130, 190, 40, 58))
	if frame != null: win.add_child(frame)
	# 제목바.
	var th := AtlasUI.size_pt("ninepatch_ui", "9patch_pop_title_bg").y
	var tbar := AtlasUI.nine("ninepatch_ui", "9patch_pop_title_bg", Vector2(W * 0.9, th))
	if tbar != null:
		tbar.position = Vector2(W * 0.05, 50.0 - th * 0.5)
		win.add_child(tbar)
	var tl := Label.new(); tl.text = "연구소 상세정보"
	tl.add_theme_font_size_override("font_size", 26)
	tl.add_theme_color_override("font_color", Color.WHITE)
	tl.add_theme_color_override("font_outline_color", Color(0.35, 0.14, 0.03, 0.95))
	tl.add_theme_constant_override("outline_size", 5)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = Vector2(W * 0.9, th)
	tl.position = Vector2(W * 0.05, 50.0 - th * 0.5)
	win.add_child(tl)
	# 닫기.
	var cs := AtlasUI.size_pt("common_ui", "common_close_btn") * 1.05
	var xb := TextureButton.new()
	var ct := AtlasUI.tex("common_ui", "common_close_btn")
	if ct != null:
		xb.texture_normal = ct
		xb.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 1.05
	xb.position = Vector2(W - 50.0, 50.0) - cs * 0.5
	xb.pressed.connect(func():
		overlay.queue_free()
		_skill_popup = null
		if _floor != -1: _rebuild())
	win.add_child(xb)
	# 상단 좌: 연구소레벨 게이지(lv_bg 400×33).
	var lv := _lab_level()
	var need := _lab_exp_need(lv)
	var have := _lab_exp()
	var lb := AtlasUI.nine(DIR_UI, "scene_laboratory_lv_bg", Vector2(400.0, 33.0), Rect2(8, 8, 8, 8))
	if lb != null:
		lb.position = Vector2(30.0, 83.0)
		win.add_child(lb)
	var l1 := Label.new(); l1.text = "연구소레벨"
	l1.add_theme_font_size_override("font_size", 15)
	l1.add_theme_color_override("font_color", Color(1, 0.97, 0.85))
	l1.position = Vector2(40.0, 89.0); l1.size = Vector2(90.0, 22.0)
	win.add_child(l1)
	var bsz := AtlasUI.size_pt(DIR_UI, "scene_laboratory_lv_number_bg")
	var badge := _spr("lv_number_bg", Design.ASSET_SCALE * 0.85)
	if badge != null:
		badge.centered = false
		badge.position = Vector2(122.0, 99.5 - bsz.y * 0.42)
		win.add_child(badge)
	var l2 := Label.new(); l2.text = str(lv)
	l2.add_theme_font_size_override("font_size", 14)
	l2.add_theme_color_override("font_color", Color(1, 1, 1))
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l2.position = Vector2(122.0, 99.5 - bsz.y * 0.42)
	l2.size = Vector2(bsz.x * 0.85, bsz.y * 0.85)
	win.add_child(l2)
	var gsz := AtlasUI.size_pt("common_ui", "common_bar_bg2")
	var gbg := AtlasUI.spr("common_ui", "common_bar_bg2", Design.ASSET_SCALE)
	if gbg != null:
		gbg.centered = false
		gbg.position = Vector2(170.0, 99.5 - gsz.y * 0.5)
		win.add_child(gbg)
	var gfg := AtlasUI.spr("common_ui", "common_bar_exp", Design.ASSET_SCALE)
	if gfg != null:
		gfg.centered = false
		gfg.position = Vector2(170.0, 99.5 - gsz.y * 0.5)
		gfg.region_enabled = true
		var t := gfg.texture
		gfg.region_rect = Rect2(0, 0,
			t.get_width() * clampf(float(have) / maxf(1.0, float(need)), 0.0, 1.0), t.get_height())
		win.add_child(gfg)
	var l3 := Label.new(); l3.text = "%d/%d" % [have, need]
	l3.add_theme_font_size_override("font_size", 13)
	l3.add_theme_color_override("font_color", Color(1, 1, 1))
	l3.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02))
	l3.add_theme_constant_override("outline_size", 3)
	l3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l3.position = Vector2(170.0, 88.0); l3.size = Vector2(gsz.x * Design.ASSET_SCALE, 22.0)
	win.add_child(l3)
	# 상단 우: 스킬포인트 + 리셋(원작 RoundedLayer 200×45 흑49% + bt_laboratory_skill_reset).
	var pts := int(UserDB.get_pmeta("lab_points", 0))
	var pbox := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.49)
	sb.set_corner_radius_all(10)
	pbox.add_theme_stylebox_override("panel", sb)
	pbox.size = Vector2(200.0, 45.0) * 0.95
	pbox.position = Vector2(W - 39.0 - pbox.size.x, 80.0)
	win.add_child(pbox)
	var pl := Label.new(); pl.text = "스킬포인트 %d" % pts
	pl.add_theme_font_size_override("font_size", 17)
	pl.add_theme_color_override("font_color", Color(1, 1, 1))
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pl.size = Vector2(pbox.size.x - 24.0, pbox.size.y)
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pbox.add_child(pl)
	var rs := _spr("bt_laboratory_skill_reset", Design.ASSET_SCALE)
	if rs != null:
		rs.position = pbox.position + Vector2(pbox.size.x - 7.0, pbox.size.y * 0.5)
		win.add_child(rs)
	var rb := Button.new(); rb.flat = true
	rb.size = Vector2(44.0, 44.0)
	rb.position = pbox.position + Vector2(pbox.size.x - 29.0, pbox.size.y * 0.5 - 22.0)
	rb.pressed.connect(func(): _reset_skills(overlay))
	win.add_child(rb)
	# 스킬 2열×4행(원작 addCell: 열 0 = 아이콘 1~4, 열 1 = 아이콘 5~8).
	var defs := _skill_defs()
	var cell_w := W * 0.5 - 30.0
	var cell_h := 85.0
	var max_step := int(_cfg().get("lab_upgrade", {}).get("skills", {}).get("max_step", 10))
	for i in defs.size():
		var sd: Dictionary = defs[i]
		var coli := 0 if int(sd.get("icon", i + 1)) <= 4 else 1
		var rowi := (int(sd.get("icon", i + 1)) - 1) % 4
		var cell := _skill_cell(sd, Vector2(cell_w, cell_h - 4.0), pts, max_step, overlay)
		cell.position = Vector2(22.0 + coli * (cell_w + 14.0), 138.0 + rowi * cell_h)
		win.add_child(cell)

func _skill_cell(sd: Dictionary, sz: Vector2, pts: int, max_step: int, overlay: Control) -> Control:
	var id := String(sd.get("id", ""))
	var step := _skill_step(id)
	var cost := int(sd.get("cost", 1))
	var maxed := step >= max_step
	var cell := Control.new()
	cell.size = sz
	var bg := AtlasUI.nine("ninepatch_ui", "9patch_bt_itembox_off", sz, Rect2(16, 16, 9, 24))
	if bg != null: cell.add_child(bg)
	var ic := _spr("laboratory_upgrade_%d" % int(sd.get("icon", 1)), Design.ASSET_SCALE * 0.77)
	if ic != null:
		ic.position = Vector2(36.0, sz.y * 0.5)
		cell.add_child(ic)
	var nm := Label.new(); nm.text = String(sd.get("name", ""))
	nm.add_theme_font_size_override("font_size", 15)
	nm.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	nm.position = Vector2(72.0, 6.0); nm.size = Vector2(sz.x - 80.0, 20.0)
	cell.add_child(nm)
	var cur := Label.new(); cur.text = _skill_fmt(sd, step)
	cur.add_theme_font_size_override("font_size", 14)
	cur.add_theme_color_override("font_color", Color(0.45, 0.30, 0.12))
	cur.position = Vector2(72.0, 25.0); cur.size = Vector2(sz.x - 80.0, 18.0)
	cell.add_child(cur)
	# 단계 게이지(upgrade_gauge_bg/bar, 만렙 10) + "N단계".
	var gsz := AtlasUI.size_pt(DIR_UI, "scene_laboratory_upgrade_gauge_bg")
	var gbg := _spr("upgrade_gauge_bg", Design.ASSET_SCALE)
	if gbg != null:
		gbg.centered = false
		gbg.position = Vector2(72.0, sz.y - gsz.y - 8.0)
		cell.add_child(gbg)
	var gfg := _spr("upgrade_gauge_bar", Design.ASSET_SCALE)
	if gfg != null:
		gfg.centered = false
		gfg.position = Vector2(72.0, sz.y - gsz.y - 8.0)
		gfg.region_enabled = true
		var t := gfg.texture
		gfg.region_rect = Rect2(0, 0,
			t.get_width() * clampf(float(step) / float(max_step), 0.0, 1.0), t.get_height())
		cell.add_child(gfg)
	var sl := Label.new(); sl.text = "%d단계" % step
	sl.add_theme_font_size_override("font_size", 13)
	sl.add_theme_color_override("font_color", Color(1, 1, 1))
	sl.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02))
	sl.add_theme_constant_override("outline_size", 3)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.position = Vector2(72.0, sz.y - gsz.y - 10.0)
	sl.size = Vector2(gsz.x, 18.0)
	cell.add_child(sl)
	# 올리기(bt_skill_up ×0.9 + 비용 숫자) / 만렙(bt_skill_max).
	var can := (not maxed) and pts >= cost
	var bt := _spr("bt_skill_max" if maxed else "bt_skill_up", Design.ASSET_SCALE * 0.9)
	var bsz := AtlasUI.size_pt(DIR_UI,
		"scene_laboratory_bt_skill_max" if maxed else "scene_laboratory_bt_skill_up") * 0.9
	if bt != null:
		bt.position = Vector2(sz.x - 30.0, sz.y - 26.0)
		if not can: bt.modulate = Color(0.62, 0.62, 0.62)
		cell.add_child(bt)
	if not maxed:
		var cl := Label.new(); cl.text = str(cost)
		cl.add_theme_font_size_override("font_size", 14)
		cl.add_theme_color_override("font_color", Color(1, 1, 1))
		cl.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.25))
		cl.add_theme_constant_override("outline_size", 3)
		cl.position = Vector2(sz.x - 26.0, sz.y - 36.0); cl.size = Vector2(20.0, 20.0)
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(cl)
		var b := Button.new(); b.flat = true
		b.size = bsz + Vector2(10.0, 10.0)
		b.position = Vector2(sz.x - 30.0, sz.y - 26.0) - b.size * 0.5
		b.disabled = not can
		var sd2 := sd
		b.pressed.connect(func(): _confirm_skill_up(sd2, overlay))
		cell.add_child(b)
	return cell

## 스킬 배우기 확인 팝업(원작 상세정보_렙업.png): "0단계 ▶ 1단계" 아이콘 + 효과 전후 +
## "포인트 N를 소모하여 스킬을 배우시겠습니까?" + 확인/취소.
func _confirm_skill_up(sd: Dictionary, overlay: Control) -> void:
	var id := String(sd.get("id", ""))
	var step := _skill_step(id)
	var cost := int(sd.get("cost", 1))
	var pop := OrigPopup.open(self, String(sd.get("name", "")), Vector2(660.0, 470.0))
	pop.z_index = 60
	for j in 2:
		var cxx := 200.0 + 260.0 * j
		var stl := Label.new(); stl.text = "%d단계" % (step + j)
		stl.add_theme_font_size_override("font_size", 20)
		stl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		stl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stl.position = Vector2(cxx - 70.0, 96.0); stl.size = Vector2(140.0, 26.0)
		pop.content.add_child(stl)
		var ibg := AtlasUI.nine("ninepatch_ui", "9patch_bt_itembox_off", Vector2(86.0, 86.0), Rect2(16, 16, 9, 24))
		if ibg != null:
			ibg.position = Vector2(cxx - 43.0, 130.0)
			pop.content.add_child(ibg)
		var ic := _spr("laboratory_upgrade_%d" % int(sd.get("icon", 1)), Design.ASSET_SCALE)
		if ic != null:
			ic.position = Vector2(cxx, 173.0)
			pop.content.add_child(ic)
		var ef := Label.new()
		ef.text = "%s %s" % [String(sd.get("name", "")), _skill_fmt(sd, step + j)]
		ef.add_theme_font_size_override("font_size", 15)
		ef.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		ef.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ef.position = Vector2(cxx - 125.0, 226.0); ef.size = Vector2(250.0, 22.0)
		pop.content.add_child(ef)
	var arrow := AtlasUI.spr("common_ui", "common_btn_fold", Design.ASSET_SCALE)
	if arrow != null:
		arrow.rotation_degrees = 90.0
		arrow.position = Vector2(330.0, 172.0)
		pop.content.add_child(arrow)
	var q := Label.new()
	q.text = "포인트 %d를 소모하여 스킬을 배우시겠습니까?" % cost
	q.add_theme_font_size_override("font_size", 18)
	q.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.position = Vector2(40.0, 288.0); q.size = Vector2(580.0, 26.0)
	pop.content.add_child(q)
	var ok_cb := func():
		pop.close()
		_spend_lab_point(id, cost)
		if is_instance_valid(overlay): _skill_body(overlay)
	pop.add_action_button("확인", ok_cb, 0, Vector2(200.0, 52.0), Vector2(225.0, 410.0))
	pop.add_action_button("취소", pop.close, 0, Vector2(200.0, 52.0), Vector2(435.0, 410.0))

func _spend_lab_point(sid: String, cost: int) -> void:
	var pts := int(UserDB.get_pmeta("lab_points", 0))
	if pts < cost:
		_toast("스킬포인트가 부족해."); return
	var m = UserDB.get_pmeta("lab_skills", {})
	var d: Dictionary = (m as Dictionary).duplicate() if m is Dictionary else {}
	d[sid] = int(d.get(sid, 0)) + 1
	UserDB.set_pmeta("lab_skills", d)
	UserDB.set_pmeta("lab_points", pts - cost)

## 스킬 리셋(원작 bt_laboratory_skill_reset → requestSkillReset, 원작은 다이아 과금).
## 오프라인: 무료로 전액 환급(# ASSUMPTION — 과금 재화라 원가 유실, 단일 플레이어라 무해).
func _reset_skills(overlay: Control) -> void:
	var m = UserDB.get_pmeta("lab_skills", {})
	var d: Dictionary = (m as Dictionary) if m is Dictionary else {}
	var refund := 0
	for id in d:
		var sd := _skill_def(String(id))
		refund += int(d[id]) * int(sd.get("cost", 1))
	if refund <= 0:
		_toast("되돌릴 스킬이 없어.")
		return
	_confirm_popup("스킬 초기화", "배운 스킬을 전부 되돌리고 포인트 %d를 돌려받을까?" % refund, func():
		UserDB.set_pmeta("lab_skills", {})
		UserDB.set_pmeta("lab_points", int(UserDB.get_pmeta("lab_points", 0)) + refund)
		if is_instance_valid(overlay): _skill_body(overlay))

# ══════════════════ 알 팝업 공통 — 슬롯 배치(LaboratoryEggLayer) ═══════════
## 원작 initWidget: 주 슬롯 = RoundedLayer((폭−100)/3 × 그 1.35배, 흑40%) 좌측 (w/2+100 중심),
## `common/plus`(강화/조합) 또는 `common/btn_fold` 90°(방생 ▶), 재료 슬롯 = 절반 크기
## {상단 1 + 하단 2}(강화/조합) 또는 큰 슬롯 1(방생). 하단 = RoundedButton(실행).
## 스크린샷 = 알강화.png / 알조합.png / 알방생.png.

func _slot_box(parent: Control, pos: Vector2, sz: Vector2, label: String, cb) -> Control:
	var root := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.11, 0.05, 0.35)
	sb.set_corner_radius_all(14)
	sb.border_color = Color(0.32, 0.2, 0.08, 0.5)
	sb.set_border_width_all(2)
	root.add_theme_stylebox_override("panel", sb)
	root.position = pos
	root.size = sz
	parent.add_child(root)
	if label != "":
		var l := Label.new(); l.text = label
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_color", Color(0.42, 0.30, 0.16))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(l)
	if cb is Callable:
		var b := Button.new(); b.flat = true
		b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.pressed.connect(cb)
		root.add_child(b)
	return root

## 슬롯 채우기 — 아이콘 + 이름(하단).
func _fill_slot(slot: Control, item_key: String, icon_scale := 0.7) -> void:
	for c in slot.get_children():
		if c is Label or c is Sprite2D: c.queue_free()
	var ic := _item_icon(item_key, slot.size * 0.5 + Vector2(0, -10.0), icon_scale)
	if ic != null: slot.add_child(ic)
	var l := Label.new(); l.text = _iname(item_key)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.position = Vector2(4.0, slot.size.y - 34.0)
	l.size = Vector2(slot.size.x - 8.0, 24.0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(l)

# ── 알 강화(모드 1) ────────────────────────────────────────────────────────
## 원작 `LaboratoryEggLayer`(mode 1) — 알 슬롯 + 재료 3칸(정령석 · 스톤하트 · 결정) + 강화하기.
## 재료 3칸의 정체는 원작 `setEgg` 의 빈 슬롯 아이콘이 근거(icon_element/icon_stoneheart/icon_crystal,
## :4767/:4761/:4754). 판정은 `isPosibleUpgrade` :1120 = 칸별 "보유수 ≥ 요구수"뿐.
## 규칙 = `EggUpgrade`(logic) · 재료·비용 = data/upgrade_egg.json · 등급표 = data/laboratory.json.
## 등급은 **인벤 키에 실린다**(`egg:17#2` — `EggItem`, v15). 원작 `AccountManager::setInfoEggs` 가
## 등급별로 목록 항목을 따로 두는 것과 같아서, 같은 종류라도 0강/2강은 **다른 인벤 칸**이다.
##
## 선택 상태 `_sel_egg_up` = **그 인벤 키 그대로**. (v14 까지는 "<알키>#<등급>" 이라는 화면 전용
## 합성 id 였는데, 이제 그 형식이 곧 진짜 키라 변환이 필요 없다.)
var _sel_egg_up := ""

func _egg_cfg() -> Dictionary:
	return _cfg().get("egg_upgrade", {})

## 선택된 알 → [인벤키, 등급]. 이미 없는 알이면 ["", 0].
func _sel_egg_parts() -> Array:
	if _sel_egg_up == "" or UserDB.item_count(_sel_egg_up) <= 0:
		return ["", 0]
	return [_sel_egg_up, EggItem.grade_of(_sel_egg_up)]

## items.json·드래곤 정의는 `element`/`subcategory` 가 **명시적 null** 인 항목이 있다.
## `String(null)` 은 Godot 4.7 에서 런타임 에러("Invalid call 'String' constructor")이므로
## 문자열 필드는 반드시 타입을 확인해 읽는다(cave.gd 인벤 상세도 같은 이유로 이렇게 한다).
func _sfield(d: Dictionary, key: String) -> String:
	var v = d.get(key)
	return v if typeof(v) == TYPE_STRING else ""

## 강화 등급 접미사를 뗀 기본키. items.json 조회·레시피 매칭(`type` 열)은 전부 이쪽이다.
func _egg_base(key: String) -> String:
	return EggItem.base_of(key)

func _egg_element(key: String) -> String:
	var base := _egg_base(key)
	if base.begins_with("egg:"):
		return _sfield(EggGacha.item_def(base, Data.dragons), "element")
	return _sfield(Data.get_item(base), "element")

## 보유한 알 **인벤 키**(등급 변형 포함 — `egg:17` 과 `egg:17#2` 는 서로 다른 항목이다).
func _owned_eggs() -> Array:
	var out: Array = []
	for k in UserDB.inventory().keys():
		var key := String(k)
		var it: Dictionary = EggGacha.item_def(key, Data.dragons)
		if it.is_empty():
			it = Data.get_item(_egg_base(key))
		# 뽑기 알(의문의 알 등)은 종이 정해지지 않은 개봉 아이템 — 강화/방생 대상이 아니다.
		if EggGacha.is_gacha_egg(it):
			continue
		if _sfield(it, "category") == "egg" and UserDB.item_count(key) > 0:
			out.append(key)
	out.sort()
	return out

## 강화 대상 목록. v15 부터 **인벤 칸 하나가 곧 (종류 × 등급) 하나**라 펼칠 것이 없다
## (원작이 알 개체를 고르는 것에 대응 — EggItem 주석). 이름 뒤 `+N` 은 둥지 배지와 같은 표기.
func _owned_egg_grade_entries() -> Array:
	var out: Array = []
	for k in _owned_eggs():
		var key := String(k)
		var base := _egg_base(key)
		var grade := EggItem.grade_of(key)
		var it: Dictionary = EggGacha.item_def(base, Data.dragons)
		if it.is_empty(): it = Data.get_item(base)
		out.append({
			"id": key,
			"icon_key": base,
			"name": _iname(base) + ("  +%d" % grade if grade > 0 else ""),
			"element": _sfield(it, "element"),
			"count": UserDB.item_count(key),
			"badge": ("+%d" % grade) if grade > 0 else "",
			"desc": _sfield(it, "desc"),
		})
	out.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	return out

func _body_egg_upgrade(pop: OrigPopup) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var main_sz := Vector2((W - 100.0) / 3.0, (W - 100.0) / 3.0 * 1.35)
	var main_at := Vector2(100.0, H * 0.5 - main_sz.y * 0.5 + 10.0)
	var sel := _sel_egg_parts()
	var key := String(sel[0])
	var grade := int(sel[1])
	if key == "":
		_sel_egg_up = ""
	var picked_up := func(k: String):
		_sel_egg_up = String(k)
		_refresh_feature()
	var slot := _slot_box(pop.content, main_at, main_sz, "알" if key == "" else "",
		func(): _open_egg_select(picked_up, true))
	if key != "":
		_fill_slot(slot, key)
		# 강화 단계 표기 = 원작 둥지의 이름 앞 "+N" 배지와 같은 표기(hatchery.gd:12).
		# (종전엔 `common/eggclass` 를 숫자 배지로 썼는데 그 프레임은 원작에서 **성급 별**이다.)
		if grade > 0:
			var glb := Label.new(); glb.text = "+%d" % grade
			glb.add_theme_font_size_override("font_size", 26)
			glb.add_theme_color_override("font_color", Color(1, 0.93, 0.55))
			glb.add_theme_color_override("font_outline_color", Color(0.25, 0.13, 0.04))
			glb.add_theme_constant_override("outline_size", 5)
			glb.position = Vector2(10.0, 8.0); glb.size = Vector2(70.0, 32.0)
			slot.add_child(glb)
	# + 아이콘.
	var plus := AtlasUI.spr("common_ui", "common_plus", Design.ASSET_SCALE)
	if plus != null:
		plus.position = main_at + Vector2(main_sz.x + 32.0, main_sz.y * 0.5)
		pop.content.add_child(plus)
	# 재료 슬롯 3(상단 1, 하단 2 — 원작 배치). 세로는 주 슬롯 안에 들어오게.
	var msz := Vector2(main_sz.x * 0.62, main_sz.y * 0.44)
	var mx := main_at.x + main_sz.x + 64.0
	var mats_at := [
		Vector2(mx + msz.x * 0.55, main_at.y - 4.0),
		Vector2(mx, main_at.y + msz.y + 8.0),
		Vector2(mx + msz.x + 10.0, main_at.y + msz.y + 8.0),
	]
	var ecfg := _egg_cfg()
	var recipe: Dictionary = {}
	if key != "":
		recipe = EggUpgrade.recipe_for(key, _egg_element(key), grade, Data.upgrade_egg, ecfg)
	var mats: Array = recipe.get("materials", [])
	# 라벨은 원작 슬롯 순서 그대로(setEgg 의 icon_element / icon_stoneheart / icon_crystal).
	var labels := ["정령석", "스톤하트", "결정"]
	var maxed := key != "" and grade >= EggUpgrade.max_step(ecfg)
	var ok := key != "" and not recipe.is_empty()
	for i in 3:
		var s2 := _slot_box(pop.content, mats_at[i], msz,
			labels[i] if i >= mats.size() else "", null)
		if i < mats.size():
			var md: Dictionary = mats[i]
			var mk := String(md.get("item", ""))
			var need := int(md.get("count", 1))
			var have := UserDB.item_count(mk)
			ok = ok and have >= need
			_fill_slot(s2, mk, 0.42)
			var cl := Label.new(); cl.text = "%d/%d" % [have, need]
			cl.add_theme_font_size_override("font_size", 14)
			cl.add_theme_color_override("font_color",
				Color(0.18, 0.44, 0.20) if have >= need else Color(0.72, 0.16, 0.10))
			cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cl.position = Vector2(4.0, 4.0); cl.size = Vector2(msz.x - 8.0, 18.0)
			s2.add_child(cl)
	# 상태 안내 — 강화 결과(부화 등급 확정치, 위키 labwiki.pdf §2.1)를 미리 보여 준다.
	var note := ""
	if maxed:
		note = "+%d강 (최대) — 부화 등급 %.1f 확정" % [grade, EggUpgrade.hatch_grade(grade, ecfg)]
	elif not recipe.is_empty():
		var tg := int(recipe.get("target_grade", grade + 1))
		note = "+%d강 → +%d강   (부화 등급 %.1f 확정)" % [grade, tg, EggUpgrade.hatch_grade(tg, ecfg)]
	if note != "":
		var nl := Label.new(); nl.text = note
		nl.add_theme_font_size_override("font_size", 17)
		nl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# 재료칸 바로 아래. 실행 버튼(중앙, y=H−60, 높이 56)과 겹치지 않게 위로 자른다.
		nl.position = Vector2(mx - 30.0, minf(mats_at[1].y + msz.y + 20.0, H - 112.0))
		nl.size = Vector2(msz.x * 2.0 + 70.0, 26.0)
		pop.content.add_child(nl)
	var gold := int(recipe.get("cost", 0)) if not recipe.is_empty() else 0
	ok = ok and UserDB.gold() >= gold
	var btn_label := "강화하기" if gold <= 0 else "강화하기  (%s G)" % AtlasUI.comma(gold)
	var up_cb := func():
		if _sel_egg_parts()[0] == "": _toast("강화할 알을 골라 줘.")
		else: _upgrade_egg()
	var b := pop.add_action_button(btn_label, up_cb, 0, Vector2(280.0, 56.0))
	if not ok:
		b.modulate = Color(0.65, 0.65, 0.65)

## 원작 `onClickUpgrade` → `requestUpgrade`(서버) → `responseUpgrade`. 오프라인은 여기서 즉시 처리:
## 재료·골드를 소비하고 그 알 1개의 등급을 +1 한다(성공률 100 — data/upgrade_egg.json success_rate).
func _upgrade_egg() -> void:
	var sel := _sel_egg_parts()
	var key := String(sel[0])
	var grade := int(sel[1])
	if key == "": return
	var ecfg := _egg_cfg()
	# 레시피 `type` 열은 **기본키**로 맞춘다(`mall_back_egg` — 등급은 grade 인자가 이미 나른다).
	var recipe: Dictionary = EggUpgrade.recipe_for(_egg_base(key), _egg_element(key), grade,
		Data.upgrade_egg, ecfg)
	if recipe.is_empty():
		_toast("이 알은 더 강화할 수 없어.")
		return
	for m in (recipe.get("materials", []) as Array):
		var md: Dictionary = m
		if UserDB.item_count(String(md.get("item", ""))) < int(md.get("count", 1)):
			_toast("재료가 부족해 — %s %d개가 필요해." % [
				_iname(String(md.get("item", ""))), int(md.get("count", 1))])
			return
	var gold := int(recipe.get("cost", 0))
	if UserDB.gold() < gold:
		_toast("골드가 부족해.")
		return
	for m in (recipe.get("materials", []) as Array):
		var md: Dictionary = m
		UserDB.use_item(String(md.get("item", "")), int(md.get("count", 1)))
	UserDB.spend("gold", gold)
	# v15: 강화 = **인벤 스택을 옮기는 일**. 고른 칸에서 1개를 빼고 다음 등급 칸에 1개를 넣는다
	# (원작이 그 `Egg` 개체의 grade 를 올려 목록의 다른 항목이 되는 것과 같다 — EggItem).
	var up_key := EggUpgrade.upgraded_key(key)
	var g := int(recipe.get("target_grade", grade + 1))
	UserDB.use_item(key, 1)
	UserDB.add_item(up_key, 1)
	_sel_egg_up = up_key                    # 연속 강화를 위해 올라간 알을 그대로 물고 있는다
	_toast("%s 을(를) +%d강으로 강화했어! 부화 등급 %.1f 확정." % [
		_iname(_egg_base(key)), g, EggUpgrade.hatch_grade(g, ecfg)])
	_refresh_feature()
	_refresh_money()

# ── 알 조합(모드 2) ────────────────────────────────────────────────────────
## 원작 = 조합서(레시피) + 재료 3 + 조합하기(getCombineCost). 스크린샷 알조합.png ·
## 조합서선택클릭.png. 레시피 = data/combine_egg.json(스키마 원작, 값 자작 승인 2026-07-27).
## 조합 가격 감소 스킬을 골드가에 적용(원작은 다이아 — data `_effect_note`).
var _sel_recipe := -1

func _body_egg_mix(pop: OrigPopup) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var recipes: Array = Data.combine_egg_recipes()
	var main_sz := Vector2((W - 100.0) / 3.0, (W - 100.0) / 3.0 * 1.35)
	var main_at := Vector2(100.0, H * 0.5 - main_sz.y * 0.5 + 10.0)
	var rec: Dictionary = {}
	if _sel_recipe >= 0:
		for r in recipes:
			if int((r as Dictionary).get("combine_no", -1)) == _sel_recipe:
				rec = r
	var slot := _slot_box(pop.content, main_at, main_sz, "조합서" if rec.is_empty() else "",
		func(): _open_recipe_select())
	if not rec.is_empty():
		var target := String(rec.get("target", ""))
		# 조합서 두루마리(원작 icon_paper) + 결과 알.
		var paper := _spr("icon_paper", Design.ASSET_SCALE * 0.9)
		if paper != null:
			paper.position = main_sz * 0.5 + Vector2(0, -46.0)
			slot.add_child(paper)
		var ic := _item_icon(target, main_sz * 0.5 + Vector2(0, 26.0), 0.62)
		if ic != null: slot.add_child(ic)
		var l := Label.new(); l.text = Data.item_name(target)
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = Vector2(4.0, main_sz.y - 34.0); l.size = Vector2(main_sz.x - 8.0, 24.0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(l)
	var plus := AtlasUI.spr("common_ui", "common_plus", Design.ASSET_SCALE)
	if plus != null:
		plus.position = main_at + Vector2(main_sz.x + 32.0, main_sz.y * 0.5)
		pop.content.add_child(plus)
	var msz := Vector2(main_sz.x * 0.62, main_sz.y * 0.44)
	var mx := main_at.x + main_sz.x + 64.0
	var mats_at := [
		Vector2(mx + msz.x * 0.55, main_at.y - 4.0),
		Vector2(mx, main_at.y + msz.y + 8.0),
		Vector2(mx + msz.x + 10.0, main_at.y + msz.y + 8.0),
	]
	var mats: Array = rec.get("materials", []) if not rec.is_empty() else []
	var ok := not rec.is_empty()
	for i in 3:
		var s2 := _slot_box(pop.content, mats_at[i], msz, "재료" if i >= mats.size() else "", null)
		if i < mats.size():
			var mk := String(mats[i])
			var have := UserDB.item_count(mk)
			ok = ok and have >= 1
			_fill_slot(s2, mk, 0.42)
			var cl := Label.new(); cl.text = "%d/1" % have
			cl.add_theme_font_size_override("font_size", 14)
			cl.add_theme_color_override("font_color",
				Color(0.18, 0.44, 0.20) if have >= 1 else Color(0.72, 0.16, 0.10))
			cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cl.position = Vector2(4.0, 4.0); cl.size = Vector2(msz.x - 8.0, 18.0)
			s2.add_child(cl)
	var gold := 0
	if not rec.is_empty():
		gold = int(round(float(rec.get("cost", 0)) * (1.0 - _skill_val("mix_discount"))))
		ok = ok and UserDB.gold() >= gold
	var btn_label := "조합하기" if rec.is_empty() else "조합하기  (%s G)" % AtlasUI.comma(gold)
	var mix_cb := func():
		if _sel_recipe < 0: _toast("조합서를 골라 줘.")
		else: _do_mix()
	var b := pop.add_action_button(btn_label, mix_cb, 0, Vector2(280.0, 56.0))
	if not ok:
		b.modulate = Color(0.65, 0.65, 0.65)

func _do_mix() -> void:
	var rec: Dictionary = {}
	for r in Data.combine_egg_recipes():
		if int((r as Dictionary).get("combine_no", -1)) == _sel_recipe:
			rec = r
	if rec.is_empty(): return
	for mk in (rec.get("materials", []) as Array):
		if UserDB.item_count(String(mk)) < 1:
			_toast("재료가 부족해.")
			return
	var gold := int(round(float(rec.get("cost", 0)) * (1.0 - _skill_val("mix_discount"))))
	if UserDB.gold() < gold:
		_toast("골드가 부족해.")
		return
	for mk in (rec.get("materials", []) as Array):
		UserDB.use_item(String(mk), 1)
	UserDB.spend("gold", gold)
	var target := String(rec.get("target", ""))
	UserDB.add_item(target, 1)
	_toast("%s 을(를) 조합했어!" % Data.item_name(target))
	_refresh_feature()
	_refresh_money()

## 조합서 선택 — 전체화면 그리드(원작 EggSelectLayer 계열, 조합서선택클릭.png).
func _open_recipe_select() -> void:
	if is_instance_valid(_select_popup): return
	var pop := OrigPopup.open(self, "조합서", Vector2(1000.0, 640.0))
	pop.body.position.y = maxf(6.0, round((_vis().y - pop.win_size.y) * 0.5))
	_select_popup = pop
	var entries: Array = []
	for r in Data.combine_egg_recipes():
		var rd: Dictionary = r
		entries.append({
			"id": int(rd.get("combine_no", -1)),
			"icon_key": String(rd.get("target", "")),
			"name": Data.item_name(String(rd.get("target", ""))),
			"element": String(Data.get_item(String(rd.get("target", ""))).get("element", "")),
			"count": -1,
			"desc": "재료: " + ", ".join((rd.get("materials", []) as Array).map(
				func(m): return Data.item_name(String(m)))) \
				+ "\n비용: %s G" % AtlasUI.comma(int(rd.get("cost", 0))),
			"paper": true,
		})
	_select_grid(pop, entries, func(id):
		_sel_recipe = int(id)
		_refresh_feature())

# ── 알 방생(모드 3) ────────────────────────────────────────────────────────
## 원작 스크린샷 알방생.png · 방생결과예상.png: 알 ▶ 정기, 비용 = 골드 2,500(코인 버튼),
## 결과 = 그 속성의 정기 3~6개. 대사 <LabSmeltMsg> "방생 된 드래곤 알은 라테아로 다시 돌아가게 돼."
## 정기 추가 생산/정기 생산 가격 감소 스킬이 걸린다.
var _sel_egg_rel := ""

func _body_egg_release(pop: OrigPopup) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var main_sz := Vector2((W - 100.0) / 3.0, (W - 100.0) / 3.0 * 1.35)
	var main_at := Vector2(120.0, H * 0.5 - main_sz.y * 0.5 + 10.0)
	var key := _sel_egg_rel
	if key != "" and UserDB.item_count(key) <= 0:
		key = ""
		_sel_egg_rel = ""
	var picked_rel := func(k: String):
		_sel_egg_rel = k
		_refresh_feature()
	var slot := _slot_box(pop.content, main_at, main_sz, "알" if key == "" else "",
		func(): _open_egg_select(picked_rel))
	if key != "":
		_fill_slot(slot, key)
	# ▶ 화살표(원작 btn_fold 90° 회전).
	var arrow := AtlasUI.spr("common_ui", "common_btn_fold", Design.ASSET_SCALE)
	if arrow != null:
		arrow.rotation_degrees = 90.0
		arrow.position = main_at + Vector2(main_sz.x + 48.0, main_sz.y * 0.5)
		pop.content.add_child(arrow)
	# 정기 슬롯(같은 크기).
	var s2_at := main_at + Vector2(main_sz.x + 96.0, 0)
	var s2 := _slot_box(pop.content, s2_at, main_sz, "정기" if key == "" else "", null)
	var cfg: Dictionary = _cfg().get("egg_release", {})
	if key != "":
		var el := String(Data.get_item(key).get("element", ""))
		var ek := String(ELE_ESSENCE.get(el, ""))
		if ek != "":
			# 결과 정기 + 후광(원작 방생결과예상.png 의 노란 선버스트는 backlight 로).
			var back := AtlasUI.spr("common_ui", "common_backlight3", Design.ASSET_SCALE * 0.5)
			if back != null:
				back.position = main_sz * 0.5 + Vector2(0, -10.0)
				s2.add_child(back)
			_fill_slot(s2, ek, 0.7)
			var nmin := int(cfg.get("essence_min", 3)) + int(_skill_val("essence_bonus"))
			var nmax := int(cfg.get("essence_max", 6)) + int(_skill_val("essence_bonus"))
			var cl := Label.new(); cl.text = "%d ~ %d개" % [nmin, nmax]
			cl.add_theme_font_size_override("font_size", 17)
			cl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
			cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cl.position = Vector2(4.0, main_sz.y - 58.0); cl.size = Vector2(main_sz.x - 8.0, 22.0)
			s2.add_child(cl)
		else:
			var nn := Label.new(); nn.text = "이 알은 정기로 돌아가지 않아"
			nn.add_theme_font_size_override("font_size", 14)
			nn.add_theme_color_override("font_color", Color(0.45, 0.35, 0.2))
			nn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nn.position = Vector2(4.0, main_sz.y * 0.5)
			nn.size = Vector2(main_sz.x - 8.0, 40.0)
			s2.add_child(nn)
	# 실행 버튼 — 미선택 = "방생하기", 선택 = 코인 + 가격(방생결과예상.png).
	var cost := int(_skill_val("essence_discount")) if _skill_def("essence_discount").size() > 0 \
		else int(cfg.get("cost_gold", 2500))
	if key == "":
		pop.add_action_button("방생하기", func(): _toast("방생할 알을 골라 줘."), 0, Vector2(280.0, 56.0))
	else:
		var b := pop.add_action_button("  %s" % AtlasUI.comma(cost), func(): _do_release(cost),
			0, Vector2(280.0, 56.0))
		var coin := AtlasUI.spr("common_ui", "common_coin_small1", Design.ASSET_SCALE * 0.9)
		if coin != null:
			coin.position = Vector2(70.0, 28.0)
			b.add_child(coin)
		if UserDB.gold() < cost:
			b.modulate = Color(0.65, 0.65, 0.65)

func _do_release(cost: int) -> void:
	var key := _sel_egg_rel
	if key == "" or UserDB.item_count(key) <= 0: return
	if UserDB.gold() < cost:
		_toast("골드가 부족해.")
		return
	var el := String(Data.get_item(key).get("element", ""))
	var ek := String(ELE_ESSENCE.get(el, ""))
	if not UserDB.use_item(key, 1): return
	UserDB.spend("gold", cost)
	var cfg: Dictionary = _cfg().get("egg_release", {})
	var bonus := int(_skill_val("essence_bonus"))
	var n := randi_range(int(cfg.get("essence_min", 3)) + bonus, int(cfg.get("essence_max", 6)) + bonus)
	if ek != "":
		UserDB.add_item(ek, n)
		_toast("%s 을(를) 방생하고 %s %d개를 받았어." % [_iname(key), Data.item_name(ek), n])
	else:
		_toast("%s 을(를) 방생했어." % _iname(key))
	_refresh_feature()
	_refresh_money()

# ── 알/조합서 전체화면 선택 그리드 ─────────────────────────────────────────
## 원작 `EggSelectLayer`(+`EggSelectCell` — `scene/cave/dragonbg_nomal/select` 셀) 형태:
## 좌 = 그리드(3행 가로 스크롤, X개수), 우 = 미리보기(이름·속성·아이콘·설명·[선택]),
## 하단 = 속성 필터 원형(ALL + 9속성, item_small ele_*). 스크린샷 = 방생알선택창.png.
## by_grade=true 면 (종류 × 강화 등급)으로 펼쳐 고른다(알 강화 전용 — id가 "<키>#<등급>").
func _open_egg_select(on_pick: Callable, by_grade := false) -> void:
	if is_instance_valid(_select_popup): return
	var pop := OrigPopup.open(self, "알", Vector2(1000.0, 640.0))
	pop.body.position.y = maxf(6.0, round((_vis().y - pop.win_size.y) * 0.5))
	_select_popup = pop
	if by_grade:
		_select_grid(pop, _owned_egg_grade_entries(), on_pick)
		return
	var entries: Array = []
	for k in _owned_eggs():
		var key := String(k)
		var it := Data.get_item(key)
		entries.append({
			"id": key,
			"icon_key": key,
			"name": _iname(key),
			"element": _sfield(it, "element"),
			"count": UserDB.item_count(key),
			"desc": _sfield(it, "desc"),
		})
	_select_grid(pop, entries, on_pick)

## 공용 선택 그리드. entries = [{id, icon_key, name, element, count(-1=숨김), desc}].
func _select_grid(pop: OrigPopup, entries: Array, on_pick: Callable) -> void:
	var state := {"filter": "all", "sel": -1}
	_select_grid_body(pop, entries, on_pick, state)

func _select_grid_body(pop: OrigPopup, entries: Array, on_pick: Callable, state: Dictionary) -> void:
	pop.clear_content()
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var filter := String(state.get("filter", "all"))
	var shown: Array = []
	for e in entries:
		var ed: Dictionary = e
		if filter == "all" or String(ed.get("element", "")) == filter \
			or (filter == "aqua" and String(ed.get("element", "")) == "water") \
			or (filter == "earth" and String(ed.get("element", "")) == "ground"):
			shown.append(ed)
	# ── 좌: 그리드(3행, 가로 스크롤 — 원작과 같은 흐름) ─────────
	var sc := ScrollContainer.new()
	sc.position = Vector2(40.0, 78.0)
	sc.size = Vector2(W - 380.0, H - 78.0 - 110.0)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pop.content.add_child(sc)
	var grid := GridContainer.new()
	var rows := 3
	grid.columns = maxi(1, int(ceil(float(shown.size()) / rows)))
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	sc.add_child(grid)
	# GridContainer 는 행 우선 — 열 우선(세로 3칸)으로 재배열.
	var ordered: Array = []
	var cols: int = grid.columns
	for r in rows:
		for c2 in cols:
			var idx := c2 * rows + r
			ordered.append(shown[idx] if idx < shown.size() else null)
	for e2 in ordered:
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(118.0, 142.0)
		grid.add_child(cell)
		if e2 == null: continue
		var ed2: Dictionary = e2
		var sel_i: int = entries.find(ed2)
		var selected := sel_i == int(state.get("sel", -1))
		var bgk := "scene_cave_dragonbg_select" if selected else "scene_cave_dragonbg_nomal"
		var bg := AtlasUI.nine("cave_ui", bgk, Vector2(118.0, 142.0), Rect2(12, 12, 12, 12))
		if bg != null: cell.add_child(bg)
		# 조합서 항목은 두루마리(icon_paper)를 알 **뒤에** 깐다(원작 조합서 셀 형태).
		if bool(ed2.get("paper", false)):
			var pp := _spr("icon_paper", Design.ASSET_SCALE * 0.95)
			if pp != null:
				pp.position = Vector2(59.0, 58.0)
				cell.add_child(pp)
		var ic := _item_icon(String(ed2.get("icon_key", "")), Vector2(59.0, 62.0), 0.55)
		if ic != null: cell.add_child(ic)
		if int(ed2.get("count", -1)) >= 0:
			var cl := Label.new(); cl.text = "X %d" % int(ed2.get("count", 0))
			cl.add_theme_font_size_override("font_size", 14)
			cl.add_theme_color_override("font_color", Color(1, 0.97, 0.85))
			cl.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.05))
			cl.add_theme_constant_override("outline_size", 3)
			cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cl.position = Vector2(8.0, 116.0); cl.size = Vector2(102.0, 20.0)
			cell.add_child(cl)
			# 강화 등급 배지(`+N`) — entries 에 badge 가 있을 때만. 알 강화 목록은 같은 종류가
			# 등급별로 여러 칸이 되므로 이게 없으면 셀이 구분되지 않는다.
			var bdg := String(ed2.get("badge", ""))
			if bdg != "":
				var bl := Label.new(); bl.text = bdg
				bl.add_theme_font_size_override("font_size", 22)
				bl.add_theme_color_override("font_color", Color(1, 0.93, 0.55))
				bl.add_theme_color_override("font_outline_color", Color(0.25, 0.13, 0.04))
				bl.add_theme_constant_override("outline_size", 5)
				bl.position = Vector2(8.0, 4.0); bl.size = Vector2(60.0, 26.0)
				bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
				cell.add_child(bl)
		var b := Button.new(); b.flat = true
		b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var si := sel_i
		b.pressed.connect(func():
			state["sel"] = si
			_select_grid_body(pop, entries, on_pick, state))
		cell.add_child(b)
	# ── 우: 미리보기 ───────────────────────────────────────────
	var rx := W - 320.0
	var sel := int(state.get("sel", -1))
	if sel >= 0 and sel < entries.size():
		var ed3: Dictionary = entries[sel]
		var nm := Label.new(); nm.text = String(ed3.get("name", ""))
		nm.add_theme_font_size_override("font_size", 22)
		nm.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.position = Vector2(rx, 74.0); nm.size = Vector2(280.0, 30.0)
		pop.content.add_child(nm)
		var el := String(ed3.get("element", ""))
		var ep := "res://assets/converted/item_small_ui/%s.tres" % String(ELE_SMALL.get(el, ELE_SMALL["all"]))
		if el != "" and ResourceLoader.exists(ep):
			var es := Sprite2D.new(); es.texture = load(ep); es.material = _pma
			es.position = Vector2(rx + 34.0, 136.0)
			pop.content.add_child(es)
		var big := _item_icon(String(ed3.get("icon_key", "")), Vector2(rx + 140.0, 210.0), 1.1)
		if big != null: pop.content.add_child(big)
		# 설명 박스(원작 9patch/text_box).
		var tb := AtlasUI.nine("ninepatch_ui", "9patch_text_box", Vector2(280.0, 150.0), Rect2(14, 14, 14, 14))
		if tb != null:
			tb.position = Vector2(rx, 300.0)
			pop.content.add_child(tb)
		var dl := Label.new(); dl.text = String(ed3.get("desc", ""))
		dl.add_theme_font_size_override("font_size", 14)
		dl.add_theme_color_override("font_color", Color(0.55, 0.25, 0.15))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.position = Vector2(rx + 14.0, 312.0); dl.size = Vector2(252.0, 126.0)
		dl.clip_text = true
		pop.content.add_child(dl)
		var id3 = ed3.get("id")
		var pick_cb := func():
			pop.close()
			_select_popup = null
			on_pick.call(id3)
		pop.add_action_button("선택", pick_cb, 0, Vector2(240.0, 54.0), Vector2(rx + 140.0, H - 130.0))
	else:
		var hint := Label.new(); hint.text = "목록에서 골라 줘"
		hint.add_theme_font_size_override("font_size", 18)
		hint.add_theme_color_override("font_color", Color(0.45, 0.35, 0.2))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.position = Vector2(rx, 200.0); hint.size = Vector2(280.0, 30.0)
		pop.content.add_child(hint)
	# ── 하단: 속성 필터(ALL + 9속성 원형) ───────────────────────
	var fx := W * 0.5 - (ELE_FILTER.size() * 62.0) * 0.5 + 31.0
	for i in ELE_FILTER.size():
		var f := String(ELE_FILTER[i])
		var p := "res://assets/converted/item_small_ui/%s.tres" % String(ELE_SMALL[f])
		if not ResourceLoader.exists(p): continue
		var s := Sprite2D.new(); s.texture = load(p); s.material = _pma
		s.position = Vector2(fx + i * 62.0, H - 58.0)
		s.scale = Vector2(1.15, 1.15)
		if f != filter: s.modulate = Color(0.55, 0.55, 0.55)
		pop.content.add_child(s)
		var b2 := Button.new(); b2.flat = true
		b2.size = Vector2(56.0, 56.0)
		b2.position = Vector2(fx + i * 62.0 - 28.0, H - 86.0)
		var ff := f
		b2.pressed.connect(func():
			state["filter"] = ff
			state["sel"] = -1
			_select_grid_body(pop, entries, on_pick, state))
		pop.content.add_child(b2)

# ══════════════════ 드래곤 강화 = 장비 슬롯 확장 (B1, CrystalLayer 0x67) ═══
## 원작 흐름(docs/ref/Lab/드래곤강화*.png 실측 2026-07-29):
##   B1 기계 클릭 → **드래곤 선택**(가로 카드 + 각 카드에 '장비 슬롯' 4칸 상태)
##   → **장비 슬롯 확장** 팝업(All + 3칸, 잠긴 칸은 자물쇠, 첫 확장 전엔 '주의' 안내판)
##   → **재료 드래곤 선택**(등급 + 아니마/보네르/아모르의 축복 보유/필요)
##   → **확인**(대상 + 재료, 요구 등급/재료 등급, "재료로 사용되는 드래곤은 삭제됩니다")
##   → 성공 연출(초록 광선) + 슬롯 개방.
##
## 🔴 정정(2026-07-29): 종전 구현은 위키 문장만 보고 "**같은 종** 0.0 등급 드래곤 제물"을
##    요구하고 칸을 **순차** 해금했다. 원작 화면은 둘 다 다르다 —
##    ① 재료 드래곤은 **종 무관**, 조건은 **등급 하한**뿐(재료 선택 목록에 0.0·3.0 이 함께 뜬다).
##    ② 칸은 **임의 순서**로 연다("어떤 슬롯을 여는지 상관없이 …" 주의문).
##    ③ 요구 등급은 **확장 횟수**로 오른다(+1 0.0 / +2 3.0 / +3 6.0).
const SLOT_ITEM_AMOR := "bless_of_amor"
const SLOT_ITEM_BONNER := "bonner"
const SLOT_ITEM_ANIMA := "anima"
const SLOT_ITEM_TICKET := DragonEnhanceRules.TICKET_ITEM
## 원작 행 라벨(드래곤강화4.png). '아티펙트' 는 원작 표기 그대로.
const SLOT_ROW_KR := {
	"all": "모든 장비 장착 가능", "battle": "전투형 장비 장착 가능",
	"support": "보조형 장비 장착 가능", "artifact": "아티펙트 장비 장착 가능"}
## 슬롯 칸 안에 넣는 짧은 이름. 원작 아이콘(`addimg/intension/icon_streng_*`)은
## `addimg/` 폴더 자체가 덤프에 없다 → 원작 All 칸처럼 **글자**로 그린다.
const SLOT_TAG := {"all": "All", "battle": "전투", "support": "보조", "artifact": "아티"}
const SLOT_KR := {"all": "자유", "battle": "전투형", "support": "보조형", "artifact": "아티펙트"}

func _enh_cfg() -> Dictionary:
	return _cfg().get("dragon_enhance", {})

## 해금한 칸 id 목록(v11 배열). 구세이브(개수 int)도 Equipment 가 흡수한다.
func _unlocked_slots(d: Dictionary) -> Array:
	return Equipment.slot_ids(d.get("equip_slots", 1))

## 확장 n회차(1-base)의 재료 비용. base + per×(n−1).
func _enh_cost(n: int) -> Dictionary:
	var c: Dictionary = _enh_cfg().get("cost", {})
	var out: Dictionary = {}
	for k in [SLOT_ITEM_AMOR, SLOT_ITEM_BONNER, SLOT_ITEM_ANIMA]:
		var spec: Dictionary = c.get(k, {})
		out[k] = int(spec.get("base", 0)) + int(spec.get("per", 0)) * (n - 1)
	return out

## 확장 n회차의 재료 드래곤 **요구 등급 하한**(드래곤강화3.png 표).
func _enh_grade_min(n: int) -> float:
	var arr: Array = _enh_cfg().get("material_grade_min", [])
	if arr.is_empty():
		return 0.0
	return float(arr[clampi(n - 1, 0, arr.size() - 1)])

# ── B1 드래곤 강화 층 ─────────────────────────────────────────────────────
## 원작 `CrystalLayer(0x67)` — 추출과 같은 단일 기계(`u_village_lab_st`)에 깃발 탭이 없다.
func _build_b1_enhance(vis: Vector2, S: float) -> void:
	var center := Vector2(vis.x * 0.5 - vis.x * 0.1, Design.flip_y(vis.y * 0.5 - 65.0))
	_spine("res://scenes/fx/lab_st.tscn", center, S, "nomal")
	var hit := Button.new(); hit.flat = true
	hit.size = Vector2(300.0, 220.0)
	hit.position = center - hit.size * 0.5
	hit.z_index = 6
	hit.pressed.connect(_open_enhance_select)
	add_child(hit)

# ── ① 드래곤 선택 ─────────────────────────────────────────────────────────
## 원작 드래곤강화선택창1/2.png: 가로 카드 + 카드 하단에 "장비 슬롯" 4칸 상태.
func _open_enhance_select() -> void:
	if is_instance_valid(_select_popup): return
	var pop := OrigPopup.open(self, "드래곤 선택", Vector2(980.0, 600.0))
	pop.body.position.y = maxf(6.0, round((_vis().y - pop.win_size.y) * 0.5))
	_select_popup = pop
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var sc := ScrollContainer.new()
	sc.position = Vector2(36.0, 80.0)
	sc.size = Vector2(W - 72.0, H - 80.0 - 30.0)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pop.content.add_child(sc)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	sc.add_child(row)
	for d in UserDB.dragons():
		var dd: Dictionary = d
		var card := _enhance_dragon_card(dd)
		row.add_child(card)
		var b := Button.new(); b.flat = true
		b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var uu := int(dd.get("uid", 0))
		b.pressed.connect(func(): _open_slot_expand(uu))
		card.add_child(b)

## 선택 카드 — 속성 원 + 초상 + 등급(금색) + 이름바 + "장비 슬롯" 4칸.
func _enhance_dragon_card(dd: Dictionary) -> Control:
	var ddef := Data.get_dragon(int(dd.get("id", 0)))
	var lvl := int(dd.get("level", 1))
	var card := Control.new()
	card.custom_minimum_size = Vector2(300.0, 430.0)
	var bg := AtlasUI.nine("cave_ui", "scene_cave_dragonbg_nomal", Vector2(300.0, 430.0), Rect2(12, 12, 12, 12))
	if bg != null: card.add_child(bg)
	var el := String(ddef.get("element", ""))
	var ep := "res://assets/converted/item_small_ui/%s.tres" % String(ELE_SMALL.get(el, ELE_SMALL["all"]))
	if ResourceLoader.exists(ep):
		var es := Sprite2D.new(); es.texture = load(ep); es.material = _pma
		es.position = Vector2(38.0, 40.0)
		card.add_child(es)
	var por := _portrait_sprite(int(dd.get("id", 0)), Growth.stage_for_level(lvl), 1.5)
	if por != null:
		por.position = Vector2(150.0, 145.0)
		card.add_child(por)
	var gl := Label.new(); gl.text = "%.1f" % _grade_of(dd)
	gl.add_theme_font_size_override("font_size", 30)
	gl.add_theme_color_override("font_color", Color(1, 0.78, 0.18))
	gl.add_theme_color_override("font_outline_color", Color(0.25, 0.14, 0.02))
	gl.add_theme_constant_override("outline_size", 6)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gl.position = Vector2(140.0, 208.0); gl.size = Vector2(140.0, 36.0)
	card.add_child(gl)
	var nb := AtlasUI.nine("promote_ui", "scene_promote_train_box1", Vector2(264.0, 40.0), Rect2(20, 12, 20, 12))
	if nb != null:
		nb.position = Vector2(18.0, 252.0)
		card.add_child(nb)
	var nl := Label.new()
	nl.text = "레벨%d %s" % [lvl, Icons.name_of(dd, "?")]
	nl.add_theme_font_size_override("font_size", 17)
	nl.add_theme_color_override("font_color", Color(1, 0.97, 0.85))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.position = Vector2(18.0, 252.0); nl.size = Vector2(264.0, 40.0)
	card.add_child(nl)
	var head := Label.new(); head.text = "장비 슬롯"
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.position = Vector2(50.0, 310.0); head.size = Vector2(200.0, 24.0)
	card.add_child(head)
	var open := _unlocked_slots(dd)
	for i in Equipment.SLOT_ORDER.size():
		var sid := String(Equipment.SLOT_ORDER[i])
		_slot_chip(card, Vector2(28.0 + i * 62.0, 346.0), Vector2(56.0, 56.0), sid, open.has(sid))
	return card

## 슬롯 한 칸 — 열렸으면 종류 글자, 잠겼으면 `common/lock`.
func _slot_chip(parent: Control, pos: Vector2, sz: Vector2, sid: String, unlocked: bool) -> Control:
	var box := AtlasUI.nine("ninepatch_ui", "9patch_bt_itembox_off", sz, Rect2(16, 16, 9, 24))
	var root := Control.new()
	root.position = pos
	root.size = sz
	parent.add_child(root)
	if box != null:
		root.add_child(box)
	if unlocked:
		var l := Label.new(); l.text = String(SLOT_TAG.get(sid, sid))
		l.add_theme_font_size_override("font_size", 17)
		l.add_theme_color_override("font_color", Color(0.42, 0.38, 0.34))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size = sz
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(l)
	else:
		var lk := AtlasUI.spr("common_ui", "common_lock", Design.ASSET_SCALE * 0.75)
		if lk != null:
			lk.position = sz * 0.5
			root.add_child(lk)
	return root

# ── ② 장비 슬롯 확장 팝업 ─────────────────────────────────────────────────
## 원작 드래곤강화4/8.png: 세로 4행 [칸][라벨]. 열린 행은 밝고, 잠긴 행은 자물쇠+회색.
## 첫 확장 전에는 왼쪽에 '주의' 안내판(확장 횟수별 요구 등급 표)이 함께 뜬다.
func _open_slot_expand(uid: int) -> void:
	if is_instance_valid(_select_popup):
		_select_popup.close()
		_select_popup = null
	var d := UserDB.get_dragon(uid)
	if d.is_empty(): return
	# 크기는 공용 위젯(MultyEquipPop) 의 행 규격(125px × 4)에 맞춘다.
	var pop := OrigPopup.open(self, MultyEquipPop.S_TITLE, Vector2(560.0, 636.0))
	# 원작(드래곤강화3/4.png)은 이 창을 **오른쪽에 붙이고** 왼쪽 빈자리에 '주의' 안내판을 둔다.
	var vis := _vis()
	pop.body.position = Vector2(round(vis.x * 0.72 - pop.win_size.x * 0.5),
		maxf(6.0, round((vis.y - pop.win_size.y) * 0.5)))
	_select_popup = pop
	_slot_expand_body(pop, uid)

func _slot_expand_body(pop: OrigPopup, uid: int) -> void:
	pop.clear_content()
	var open := _unlocked_slots(UserDB.get_dragon(uid))
	# 확장 안내판 — 원작은 첫 확장 전에만 띄운다(드래곤강화3/4.png ↔ 8.png 대조).
	if open.size() <= 1:
		_expand_notice(pop)
	# 4행은 **동굴 장비창과 같은 위젯**이 그린다 — 원작도 같은 클래스(MultyEquipPop)다.
	MultyEquipPop.build_rows(pop.content, uid, "expand", pop.win_size.x - 60.0,
		Vector2(30.0, 88.0), func(sid: String, unlocked: bool):
			if unlocked:
				_say(MultyEquipPop.S_ALREADY)       # <MultyEquip_Slot_alread>
				return
			_open_enh_material_select(uid, sid))


## '주의' 안내판(원작 드래곤강화3.png). 확장 횟수별 재료 드래곤 등급 표.
func _expand_notice(pop: OrigPopup) -> void:
	var W: float = pop.win_size.x
	var panel := Control.new()
	panel.position = Vector2(-360.0, 120.0)
	panel.size = Vector2(340.0, 240.0)
	pop.content.add_child(panel)
	# 느낌표 아이콘은 원작 프레임이다 — `MultyEquipPop` 이 `common/alert4` 를 쓴다
	# (종전엔 "⚠" 글자로 대신했다. 참조 docs/ref/orig_image/lab/드래곤강화4.png).
	var al := AtlasUI.spr("common_ui", "common_alert4", Design.ASSET_SCALE * 0.85)
	if al:
		al.position = Vector2(126.0, 14.0)
		panel.add_child(al)
	var t := Label.new(); t.text = "주의"
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color(1, 1, 1))
	t.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02, 0.95))
	t.add_theme_constant_override("outline_size", 5)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.position = Vector2(24.0, 0); t.size = Vector2(340.0, 28.0)
	panel.add_child(t)
	var b := Label.new()
	b.text = "어떤 슬롯을 여는지 상관없이 슬롯을 확장할\n때마다 요구하는 재료 드래곤 등급이 상승합니다."
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02, 0.95))
	b.add_theme_constant_override("outline_size", 4)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.position = Vector2(0, 36.0); b.size = Vector2(340.0, 52.0)
	panel.add_child(b)
	var h1 := Label.new(); h1.text = "슬롯 확장 횟수"
	var h2 := Label.new(); h2.text = "재료 드래곤 등급"
	for pair in [[h1, 10.0], [h2, 180.0]]:
		var lb: Label = pair[0]
		lb.add_theme_font_size_override("font_size", 16)
		lb.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
		lb.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02, 0.95))
		lb.add_theme_constant_override("outline_size", 4)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.position = Vector2(float(pair[1]), 104.0); lb.size = Vector2(150.0, 24.0)
		panel.add_child(lb)
	var arr: Array = _enh_cfg().get("material_grade_min", [])
	for i in arr.size():
		var lo := float(arr[i])
		var txt := "%.1f ~ +++" % lo
		if i + 1 < arr.size():
			txt = "%.1f ~ %.1f" % [lo, float(arr[i + 1]) - 0.1]
		var c1 := Label.new(); c1.text = "+%d" % (i + 1)
		var c2 := Label.new(); c2.text = txt
		for pair2 in [[c1, 10.0, Color(0.55, 0.78, 1.0)], [c2, 180.0, Color(1, 0.86, 0.35)]]:
			var lb2: Label = pair2[0]
			lb2.add_theme_font_size_override("font_size", 17)
			lb2.add_theme_color_override("font_color", pair2[2])
			lb2.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02, 0.95))
			lb2.add_theme_constant_override("outline_size", 4)
			lb2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lb2.position = Vector2(float(pair2[1]), 136.0 + i * 30.0); lb2.size = Vector2(150.0, 26.0)
			panel.add_child(lb2)

# ── ③ 재료 드래곤 선택 ────────────────────────────────────────────────────
## 원작 드래곤강화재료1.png: 가로 카드(등급 + 아니마/보네르/아모르의 축복 보유/필요).
## ⚠️ 첫 칸의 'n성 드래곤 강화권' 은 그 아이템이 우리 items.json 에 없어 뺐다(data `_ticket_cut`).
func _open_enh_material_select(uid: int, slot_id: String) -> void:
	var d := UserDB.get_dragon(uid)
	if d.is_empty(): return
	var n := _unlocked_slots(d).size()          # 이번이 n회차 확장(All 1칸이 이미 열려 있다)
	var need_grade := _enh_grade_min(n)
	var cost := _enh_cost(n)
	if is_instance_valid(_select_popup):
		_select_popup.close()
		_select_popup = null
	var pop := OrigPopup.open(self, "재료 드래곤 선택", Vector2(980.0, 600.0))
	pop.body.position.y = maxf(6.0, round((_vis().y - pop.win_size.y) * 0.5))
	_select_popup = pop
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var note := Label.new()
	note.text = "· 요구 등급 %.1f 이상인 드래곤만 재료로 쓸 수 있습니다. (%d번째 확장)" % [need_grade, n]
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	note.position = Vector2(44.0, 66.0); note.size = Vector2(W - 88.0, 22.0)
	pop.content.add_child(note)
	var sc := ScrollContainer.new()
	sc.position = Vector2(36.0, 96.0)
	sc.size = Vector2(W - 72.0, H - 96.0 - 40.0)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pop.content.add_child(sc)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	sc.add_child(row)
	var ticket_card := _enh_ticket_card(cost)
	row.add_child(ticket_card)
	if DragonEnhanceRules.material_satisfies(true, UserDB.item_count(SLOT_ITEM_TICKET), 0.0, need_grade) \
			and _has_cost(cost):
		var ticket_button := Button.new(); ticket_button.flat = true
		ticket_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ticket_button.pressed.connect(func(): _confirm_enhance_ticket(uid, slot_id, n))
		ticket_card.add_child(ticket_button)
	var active := UserDB.active_uid()
	var shown := 0
	for m in UserDB.dragons():
		var md: Dictionary = m
		var muid := int(md.get("uid", 0))
		if muid == uid or muid == active:
			continue                              # 대상 자신·활성 드래곤은 재료가 될 수 없다
		if bool(md.get("locked", false)):
			continue
		shown += 1
		var card := _enh_material_card(md, need_grade, cost)
		row.add_child(card)
		var ok := DragonEnhanceRules.material_satisfies(false, 0, _grade_of(md), need_grade) and _has_cost(cost)
		if ok:
			var b := Button.new(); b.flat = true
			b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var mu := muid
			b.pressed.connect(func(): _confirm_enhance(uid, slot_id, mu, n))
			card.add_child(b)
	if shown == 0 and UserDB.item_count(SLOT_ITEM_TICKET) <= 0:
		var nn := Label.new()
		nn.text = "재료로 쓸 드래곤이 없습니다.\n(대상 드래곤·활성 드래곤·잠금 드래곤은 제외됩니다)"
		nn.add_theme_font_size_override("font_size", 18)
		nn.add_theme_color_override("font_color", Color(0.45, 0.35, 0.2))
		nn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nn.position = Vector2(60.0, 240.0); nn.size = Vector2(W - 120.0, 60.0)
		pop.content.add_child(nn)

func _enh_ticket_card(cost: Dictionary) -> Control:
	var have := UserDB.item_count(SLOT_ITEM_TICKET)
	var ok := have > 0 and _has_cost(cost)
	var card := Control.new()
	card.custom_minimum_size = Vector2(300.0, 430.0)
	var bg := AtlasUI.nine("cave_ui", "scene_cave_dragonbg_nomal", Vector2(300.0, 430.0), Rect2(12, 12, 12, 12))
	if bg != null: card.add_child(bg)
	var ic := _item_icon(SLOT_ITEM_TICKET, Vector2(150.0, 126.0), 1.05)
	if ic != null:
		if not ok: ic.modulate = Color(0.55, 0.55, 0.55)
		card.add_child(ic)
	var title := Label.new(); title.text = Data.item_name(SLOT_ITEM_TICKET)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(18.0, 218.0); title.size = Vector2(264.0, 32.0)
	card.add_child(title)
	var count := Label.new(); count.text = "보유 %d / 필요 1" % have
	count.add_theme_font_size_override("font_size", 17)
	count.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04) if have > 0 else Color(0.72, 0.16, 0.10))
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.position = Vector2(18.0, 252.0); count.size = Vector2(264.0, 28.0)
	card.add_child(count)
	var note := Label.new(); note.text = "모든 종류·등급의\n재료 드래곤 대체"
	note.add_theme_font_size_override("font_size", 17)
	note.add_theme_color_override("font_color", Color(0.18, 0.48, 0.20))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.position = Vector2(18.0, 292.0); note.size = Vector2(264.0, 52.0)
	card.add_child(note)
	var y := 350.0
	for k: String in cost:
		var need := int(cost[k])
		var owned := UserDB.item_count(k)
		var line := Label.new(); line.text = "%s  %d / %d" % [Data.item_name(k), owned, need]
		line.add_theme_font_size_override("font_size", 14)
		line.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04) if owned >= need else Color(0.72, 0.16, 0.10))
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.position = Vector2(18.0, y); line.size = Vector2(264.0, 20.0)
		card.add_child(line)
		y += 22.0
	return card

func _has_cost(cost: Dictionary) -> bool:
	for k: String in cost:
		if UserDB.item_count(k) < int(cost[k]):
			return false
	return true

func _enh_material_card(md: Dictionary, need_grade: float, cost: Dictionary) -> Control:
	var ddef := Data.get_dragon(int(md.get("id", 0)))
	var lvl := int(md.get("level", 1))
	var gr := _grade_of(md)
	var ok := gr >= need_grade and _has_cost(cost)
	var card := Control.new()
	card.custom_minimum_size = Vector2(300.0, 430.0)
	var bg := AtlasUI.nine("cave_ui", "scene_cave_dragonbg_nomal", Vector2(300.0, 430.0), Rect2(12, 12, 12, 12))
	if bg != null: card.add_child(bg)
	var el := String(ddef.get("element", ""))
	var ep := "res://assets/converted/item_small_ui/%s.tres" % String(ELE_SMALL.get(el, ELE_SMALL["all"]))
	if ResourceLoader.exists(ep):
		var es := Sprite2D.new(); es.texture = load(ep); es.material = _pma
		es.position = Vector2(38.0, 40.0)
		card.add_child(es)
	var por := _portrait_sprite(int(md.get("id", 0)), Growth.stage_for_level(lvl), 1.4)
	if por != null:
		por.position = Vector2(150.0, 130.0)
		if not ok: por.modulate = Color(0.55, 0.55, 0.55)
		card.add_child(por)
	var gl := Label.new(); gl.text = "%.1f" % gr
	gl.add_theme_font_size_override("font_size", 28)
	gl.add_theme_color_override("font_color",
		Color(1, 0.78, 0.18) if gr >= need_grade else Color(0.78, 0.30, 0.24))
	gl.add_theme_color_override("font_outline_color", Color(0.25, 0.14, 0.02))
	gl.add_theme_constant_override("outline_size", 6)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gl.position = Vector2(140.0, 186.0); gl.size = Vector2(140.0, 34.0)
	card.add_child(gl)
	var nb := AtlasUI.nine("promote_ui", "scene_promote_train_box1", Vector2(264.0, 40.0), Rect2(20, 12, 20, 12))
	if nb != null:
		nb.position = Vector2(18.0, 228.0)
		card.add_child(nb)
	var nl := Label.new()
	nl.text = "레벨%d %s" % [lvl, Icons.name_of(md, "?")]
	nl.add_theme_font_size_override("font_size", 17)
	nl.add_theme_color_override("font_color", Color(1, 0.97, 0.85))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.position = Vector2(18.0, 228.0); nl.size = Vector2(264.0, 40.0)
	card.add_child(nl)
	# 재료 3종 — 원작 카드처럼 아이콘 + "보유 / 필요".
	var y := 286.0
	for k: String in cost:
		var need := int(cost[k])
		var have := UserDB.item_count(k)
		var ic := _item_icon(k, Vector2(46.0, y + 16.0), 0.34)
		if ic != null: card.add_child(ic)
		var kl := Label.new(); kl.text = "%s :" % Data.item_name(k)
		kl.add_theme_font_size_override("font_size", 16)
		kl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		kl.position = Vector2(76.0, y + 4.0); kl.size = Vector2(130.0, 24.0)
		card.add_child(kl)
		var vl := Label.new(); vl.text = "%d / %d" % [have, need]
		vl.add_theme_font_size_override("font_size", 16)
		vl.add_theme_color_override("font_color",
			Color(0.30, 0.17, 0.04) if have >= need else Color(0.72, 0.16, 0.10))
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vl.position = Vector2(160.0, y + 4.0); vl.size = Vector2(120.0, 24.0)
		card.add_child(vl)
		y += 42.0
	if gr < need_grade:
		var warn := Label.new(); warn.text = "등급 부족 (요구 %.1f)" % need_grade
		warn.add_theme_font_size_override("font_size", 15)
		warn.add_theme_color_override("font_color", Color(0.72, 0.16, 0.10))
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.position = Vector2(20.0, 404.0); warn.size = Vector2(260.0, 22.0)
		card.add_child(warn)
	return card

# ── ④ 확인 ────────────────────────────────────────────────────────────────
## 원작 드래곤강화5.png: [대상 카드] + [재료 카드] + 요구/재료 등급 + 확장될 슬롯 안내 +
## 빨간 "*주의 재료로 사용되는 드래곤은 삭제됩니다." + 확인/취소.
func _confirm_enhance_ticket(uid: int, slot_id: String, n: int) -> void:
	var d := UserDB.get_dragon(uid)
	if d.is_empty(): return
	var pop := OrigPopup.open(self, "장비 슬롯 확장", Vector2(640.0, 430.0))
	pop.body.position.y = maxf(6.0, round((_vis().y - pop.win_size.y) * 0.5))
	var W: float = pop.win_size.x
	var lvl := int(d.get("level", 1))
	var por := _portrait_sprite(int(d.get("id", 0)), Growth.stage_for_level(lvl), 1.25)
	if por != null:
		por.position = Vector2(180.0, 185.0)
		pop.content.add_child(por)
	var ic := _item_icon(SLOT_ITEM_TICKET, Vector2(465.0, 185.0), 1.05)
	if ic != null: pop.content.add_child(ic)
	var plus := AtlasUI.spr("common_ui", "common_plus", Design.ASSET_SCALE * 1.2)
	if plus != null:
		plus.position = Vector2(W * 0.5, 185.0)
		pop.content.add_child(plus)
	var q := Label.new()
	q.text = "드래곤 강화권 1개로 [%s 장비 장착 슬롯]을 확장하시겠습니까?" \
		% String(SLOT_KR.get(slot_id, slot_id))
	q.add_theme_font_size_override("font_size", 18)
	q.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.position = Vector2(24.0, 292.0); q.size = Vector2(W - 48.0, 30.0)
	pop.content.add_child(q)
	var note := Label.new(); note.text = "강화권은 모든 종류와 등급의 재료 드래곤을 대체합니다."
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", Color(0.18, 0.48, 0.20))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.position = Vector2(24.0, 326.0); note.size = Vector2(W - 48.0, 26.0)
	pop.content.add_child(note)
	var ok_cb := func():
		pop.close()
		_do_enhance_ticket(uid, slot_id, n)
	pop.add_action_button("확인", ok_cb, 0, Vector2(170.0, 48.0), Vector2(W * 0.5 - 95.0, 388.0))
	pop.add_action_button("취소", pop.close, 0, Vector2(170.0, 48.0), Vector2(W * 0.5 + 95.0, 388.0))

func _confirm_enhance(uid: int, slot_id: String, mat_uid: int, n: int) -> void:
	var d := UserDB.get_dragon(uid)
	var m := UserDB.get_dragon(mat_uid)
	if d.is_empty() or m.is_empty(): return
	var pop := OrigPopup.open(self, "장비 슬롯 확장", Vector2(760.0, 520.0))
	pop.body.position.y = maxf(6.0, round((_vis().y - pop.win_size.y) * 0.5))
	var W: float = pop.win_size.x
	for pair in [[d, 150.0], [m, 610.0]]:
		var dd: Dictionary = pair[0]
		var cx := float(pair[1])
		var ddef := Data.get_dragon(int(dd.get("id", 0)))
		var lvl := int(dd.get("level", 1))
		var frame := AtlasUI.nine("cave_ui", "scene_cave_dragonbg_nomal", Vector2(224.0, 262.0), Rect2(12, 12, 12, 12))
		if frame != null:
			frame.position = Vector2(cx - 112.0, 92.0)
			pop.content.add_child(frame)
		var por := _portrait_sprite(int(dd.get("id", 0)), Growth.stage_for_level(lvl), 1.25)
		if por != null:
			por.position = Vector2(cx, 190.0)
			pop.content.add_child(por)
		var gl := Label.new(); gl.text = "%.1f" % _grade_of(dd)
		gl.add_theme_font_size_override("font_size", 26)
		gl.add_theme_color_override("font_color", Color(1, 0.78, 0.18))
		gl.add_theme_color_override("font_outline_color", Color(0.25, 0.14, 0.02))
		gl.add_theme_constant_override("outline_size", 6)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		gl.position = Vector2(cx - 106.0, 258.0); gl.size = Vector2(200.0, 32.0)
		pop.content.add_child(gl)
		var nb := AtlasUI.nine("promote_ui", "scene_promote_train_box1", Vector2(208.0, 36.0), Rect2(20, 12, 20, 12))
		if nb != null:
			nb.position = Vector2(cx - 104.0, 306.0)
			pop.content.add_child(nb)
		var nl := Label.new()
		nl.text = "레벨%d %s" % [lvl, Icons.name_of(dd, "?")]
		nl.add_theme_font_size_override("font_size", 15)
		nl.add_theme_color_override("font_color", Color(1, 0.97, 0.85))
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nl.position = Vector2(cx - 104.0, 306.0); nl.size = Vector2(208.0, 36.0)
		pop.content.add_child(nl)
	# 가운데: 요구 등급 / 재료 등급 + `common/plus`
	var need_grade := _enh_grade_min(n)
	var rows := [["요구 등급 :", "%.1f" % need_grade], ["재료 등급 :", "%.1f" % _grade_of(m)]]
	for i in rows.size():
		var kl := Label.new(); kl.text = String(rows[i][0])
		kl.add_theme_font_size_override("font_size", 19)
		kl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		kl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		kl.position = Vector2(W * 0.5 - 130.0, 106.0 + i * 32.0); kl.size = Vector2(120.0, 26.0)
		pop.content.add_child(kl)
		var vl := Label.new(); vl.text = String(rows[i][1])
		vl.add_theme_font_size_override("font_size", 19)
		vl.add_theme_color_override("font_color", Color(1, 0.78, 0.18))
		vl.add_theme_color_override("font_outline_color", Color(0.25, 0.14, 0.02))
		vl.add_theme_constant_override("outline_size", 4)
		vl.position = Vector2(W * 0.5 + 2.0, 106.0 + i * 32.0); vl.size = Vector2(120.0, 26.0)
		pop.content.add_child(vl)
	var plus := AtlasUI.spr("common_ui", "common_plus", Design.ASSET_SCALE * 1.3)
	if plus != null:
		plus.position = Vector2(W * 0.5, 214.0)
		pop.content.add_child(plus)
	var q := Label.new()
	q.text = "해당 드래곤을 강화하시겠습니까? 강화시 [%s 장비 장착 슬롯]이 확장됩니다." \
		% String(SLOT_KR.get(slot_id, slot_id))
	q.add_theme_font_size_override("font_size", 18)
	q.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.position = Vector2(30.0, 366.0); q.size = Vector2(W - 60.0, 26.0)
	pop.content.add_child(q)
	var warn := Label.new(); warn.text = "*주의 재료로 사용되는 드래곤은 삭제됩니다."
	warn.add_theme_font_size_override("font_size", 17)
	warn.add_theme_color_override("font_color", Color(0.85, 0.15, 0.12))
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.position = Vector2(30.0, 396.0); warn.size = Vector2(W - 60.0, 24.0)
	pop.content.add_child(warn)
	var ok_cb := func():
		pop.close()
		_do_enhance(uid, slot_id, mat_uid, n)
	pop.add_action_button("확인", ok_cb, 0, Vector2(190.0, 52.0), Vector2(W * 0.5 - 110.0, 464.0))
	pop.add_action_button("취소", pop.close, 0, Vector2(190.0, 52.0), Vector2(W * 0.5 + 110.0, 464.0))

func _do_enhance(uid: int, slot_id: String, mat_uid: int, n: int) -> void:
	var d := UserDB.get_dragon(uid)
	if d.is_empty(): return
	var open := _unlocked_slots(d)
	if open.has(slot_id):
		return
	var cost := _enh_cost(n)
	if not _has_cost(cost):
		_toast("재료가 부족해.")
		return
	var m := UserDB.get_dragon(mat_uid)
	if m.is_empty() or not DragonEnhanceRules.material_satisfies(false, 0, _grade_of(m), _enh_grade_min(n)):
		_toast("재료 드래곤의 등급이 모자라.")
		return
	if not UserDB.release_dragon(mat_uid):
		_toast("재료 드래곤을 보낼 수 없어(잠금을 확인해 줘).")
		return
	for k: String in cost:
		UserDB.use_item(k, int(cost[k]))
	_complete_enhance(uid, slot_id, open)

func _do_enhance_ticket(uid: int, slot_id: String, n: int) -> void:
	var d := UserDB.get_dragon(uid)
	if d.is_empty(): return
	var open := _unlocked_slots(d)
	if open.has(slot_id):
		return
	var cost := _enh_cost(n)
	if not _has_cost(cost):
		_toast("재료가 부족해.")
		return
	if not DragonEnhanceRules.material_satisfies(
			true, UserDB.item_count(SLOT_ITEM_TICKET), 0.0, _enh_grade_min(n)):
		_toast("드래곤 강화권이 부족해.")
		return
	if not UserDB.use_item(SLOT_ITEM_TICKET, 1):
		_toast("드래곤 강화권이 부족해.")
		return
	for k: String in cost:
		UserDB.use_item(k, int(cost[k]))
	_complete_enhance(uid, slot_id, open)

func _complete_enhance(uid: int, slot_id: String, open: Array) -> void:
	var next := open.duplicate()
	next.append(slot_id)
	UserDB.set_dragon_field(uid, "equip_slots", next)
	if is_instance_valid(_select_popup):
		_select_popup.close()
		_select_popup = null
	_rebuild()
	_enhance_success_fx()
	# 원작 성공 대사(`LabSuccessMsg` — setTextAgain case 6). 확장된 칸은 뒤에 덧붙인다.
	var done: String = _pick_talk(_talk_group("lab.success"))
	_say("%s  [%s 장비 장착 슬롯] 확장 완료!" % [done, String(SLOT_KR.get(slot_id, slot_id))])
	_refresh_money()

## 성공 연출(원작 드래곤강화6.png) — 기계 위로 초록 광선이 사방으로 뻗는다.
## 원작 스파인/파티클(`transcendence_spine`)은 덤프에 없어 광선은 도형, 반짝임은 보유 파티클.
func _enhance_success_fx() -> void:
	var vis := _vis()
	var center := Vector2(vis.x * 0.5 - vis.x * 0.1, Design.flip_y(vis.y * 0.5 - 65.0))
	for i in 14:
		var ray := ColorRect.new()
		ray.color = Color(0.35, 1.0, 0.35, 0.85)
		ray.size = Vector2(randf_range(70.0, 190.0), randf_range(4.0, 9.0))
		ray.pivot_offset = Vector2(0, ray.size.y * 0.5)
		ray.rotation = randf_range(0.0, TAU)
		ray.position = center + Vector2(randf_range(-140.0, 140.0), randf_range(-150.0, 90.0))
		ray.z_index = 60
		ray.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ray)
		var tw := ray.create_tween()
		tw.tween_property(ray, "modulate:a", 0.0, randf_range(0.5, 1.1)).set_delay(randf_range(0.0, 0.4))
		tw.tween_callback(ray.queue_free)
	CocosParticle.spawn(self, "pt_feature_c", center + Vector2(0, -40.0), 61, 0.8)

# ══════════════════ NPC / 대사 ═════════════════════════════════════════════

## NPC 애니 + 하단 대사창(원작 `setTalker` → `setTextStart`).
func _build_npc(vis: Vector2) -> void:
	_npc = NpcPortrait.create("annie", _pick_emotion("annie"))
	if _npc != null:
		_npc.z_index = 5
		add_child(_npc)
		_npc.position = Vector2(vis.x - 150.0, vis.y)
	_box = BottomTextBox.new()
	_box.max_width = vis.x - 300.0
	_box.z_index = 12
	add_child(_box)
	_box.clicked.connect(_next_line)
	_say(_lab_talk())
	if _tab < 0:
		NpcEmoticon.show_on(_npc, 8)

## 원작 `LaboratoryScene` 의 setTalker 표정 = {1, 2, 3}.
const NPC_EMOTIONS := [1, 2, 3]

func _pick_emotion(npc: String) -> int:
	var nums := AtlasUI.npc_emotions_for(npc, NPC_EMOTIONS)
	return int(nums[randi() % nums.size()]) if not nums.is_empty() else 1

const REACTION_EMOTIONS := []

func _say(line: String, emo := 0) -> void:
	if not is_instance_valid(_box):
		return
	if is_instance_valid(_npc):
		if emo > 0:
			_npc.set_emotion(emo)
		elif REACTION_EMOTIONS.has(_npc.emotion):
			_npc.set_emotion(1)
	_box.show_text(_npc_kr(), line)
	if is_instance_valid(_npc):
		_npc.set_talking(true)
		if not _box.finished.is_connected(_stop_talk):
			_box.finished.connect(_stop_talk)

func _stop_talk() -> void:
	if is_instance_valid(_npc):
		_npc.set_talking(false)

func _next_line() -> void:
	var pick := _lab_talk(true)
	_say(pick)

func _npc_kr() -> String:
	var per = Data.npc_lines_doc.get("annie", null)
	if per is Dictionary and per.has("name"):
		return String(per["name"])
	return "애니"

## 원작 대사 — `data/npc_talk.json`(build_npc_talk.py, stringsData_KR.xml 추출).
const LAB_TALK_KEY := {
	"egg_up": "lab.egg_up",
	"egg_mix": "lab.egg_mix",
	"crystal_make": "lab.crystal_make",
	"crystal_extract": "lab.crystal_extract",
	"lab_upgrade": "lab.upgrade_talk",
	"egg_release": "lab.smelt",
	"equip": "lab.normal",
}

## 현재 화면(_tab)의 대사 묶음 키.
func _talk_key() -> String:
	if _tab < 0:
		return "lab.welcome"
	return String(LAB_TALK_KEY.get(String(MENUS[_tab]["key"]), "lab.normal"))

func _talk_group(key := "") -> Dictionary:
	var screen: Dictionary = Data.npc_talk.get("screen", {})
	return screen.get(key if key != "" else _talk_key(), {})

## 대사 한 줄 고르기 + **그 줄에 짝지어진 표정·이모티콘 적용**.
##
## 원작 `setTextAgain` 은 `NpcManager::getEmotion()` 으로 **대사를 고른다**(표정 → 대사).
## 우리는 대사를 먼저 고르므로 그 대응을 뒤집은 표(`npc_talk.json` 의 `face`)를 쓴다 —
## 짝은 같고 방향만 반대다. 근거·case 별 원문은 `scripts/tools/build_npc_talk.py` FACE 주석.
## 분기가 없는 묶음(알강화·결정생산·평상시·환영)은 `entry_face`(setTalker 진입 표정)를 쓴다.
func _lab_talk(again := false) -> String:
	return _pick_talk(_talk_group(), again)

## 층 이동 대사(원작 `LabFloorUpMsg`/`LabFloorDownMsg`) — 레퍼런스 `연구소지하_생산.png` 의
## "내려가는 동안…" 이 이 묶음이다. 이동이 끝난 직후 한 번 낸다.
func _say_floor_talk(f: int) -> void:
	var key := "lab.floor_down" if f < 0 else "lab.floor_up"
	var grp: Dictionary = _talk_group(key)
	if not (grp.get("lines", []) as Array).is_empty():
		_say(_pick_talk(grp))

func _pick_talk(grp: Dictionary, again := false) -> String:
	var lines: Array = grp.get("lines", [])
	var n_own := lines.size()
	if again:
		lines = lines + (Data.npc_talk.get("idle", {}).get("annie", []) as Array)
	if lines.is_empty():
		return ""
	var i := randi() % lines.size()
	var emo: Array = grp.get("emoticon", [])
	if i < emo.size():
		NpcEmoticon.show_on(_npc, int(emo[i]))
	# 표정 — 줄마다 바뀐다(사용자 지시 2026-07-29: "각 대사에 할당된 표정으로 실시간 전환").
	if is_instance_valid(_npc):
		var face: Array = grp.get("face", [])
		if i < face.size():
			_npc.set_emotion(int(face[i]))
		elif i >= n_own:
			# 평상시 잡담(AnnieTalk*)은 원작에도 짝이 없다 → 기본 표정으로 돌린다.
			_npc.set_emotion(1)
		else:
			var ef: Array = grp.get("entry_face", [])
			if not ef.is_empty():
				_npc.set_emotion(int(ef[randi() % ef.size()]))
	return String(lines[i])

# ══════════════════ 재화바 / 공용 위젯 ═════════════════════════════════════

func _build_money(vis: Vector2) -> void:
	var sz := AtlasUI.size_pt("common_ui", "common_money_bg")
	var root := Control.new()
	_money_root = root
	root.size = sz
	root.position = Vector2(vis.x - 5.0 - sz.x, 8.0)
	root.z_index = 8
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var bg := AtlasUI.spr("common_ui", "common_money_bg", Design.ASSET_SCALE)
	if bg != null:
		bg.position = sz * 0.5
		root.add_child(bg)
	var rows := [["common_coin_small1", AtlasUI.comma(UserDB.gold()), 85.0],
		["common_diamond_small1", AtlasUI.comma(UserDB.diamond()), 45.0]]
	for r in rows:
		var ic := AtlasUI.spr("common_ui", String(r[0]), Design.ASSET_SCALE)
		if ic != null:
			ic.position = Vector2(40.0, sz.y - float(r[2]))
			root.add_child(ic)
		var l := Label.new()
		l.text = String(r[1])
		l.add_theme_font_size_override("font_size", 19)
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		l.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.04))
		l.add_theme_constant_override("outline_size", 5)
		l.position = Vector2(62.0, sz.y - float(r[2]) - 13.0)
		l.size = Vector2(sz.x - 70.0, 26.0)
		root.add_child(l)

## 확인/취소 소형 팝업(원작 생산선택2.png 형태).
func _confirm_popup(title: String, body: String, on_ok: Callable) -> void:
	var pop := OrigPopup.open(self, title, Vector2(560.0, 320.0))
	var l := Label.new(); l.text = body
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(50.0, 110.0); l.size = Vector2(460.0, 90.0)
	pop.content.add_child(l)
	var ok_cb := func():
		pop.close()
		on_ok.call()
	pop.add_action_button("확인", ok_cb, 0, Vector2(180.0, 52.0), Vector2(190.0, 260.0))
	pop.add_action_button("취소", pop.close, 0, Vector2(180.0, 52.0), Vector2(370.0, 260.0))

## 팝업 창 안의 스크롤 목록 영역(장비칸 해금 화면이 쓴다).
func _list_area(pop: OrigPopup, top: float) -> Control:
	var sc := ScrollContainer.new()
	sc.position = Vector2(48.0, top)
	sc.size = Vector2(pop.win_size.x - 96.0 + 16.0, pop.win_size.y - top - 34.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.clip_contents = true
	sc.follow_focus = false
	pop.content.add_child(sc)
	sc.ready.connect(func(): sc.scroll_vertical = 0)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(pop.win_size.x - 96.0, 4000.0)
	sc.add_child(holder)
	return holder

## 목록 한 줄 배경 — 원작 `9patch/bt_itembox_off`.
func _row(parent: Node, pos: Vector2, sz: Vector2) -> Control:
	var root := Control.new()
	root.size = sz
	root.position = pos
	parent.add_child(root)
	var np := AtlasUI.nine("ninepatch_ui", "9patch_bt_itembox_off", sz, Rect2(16, 16, 9, 24))
	if np != null:
		root.add_child(np)
	return root

func _item_icon(key: String, pos: Vector2, scale := 0.55) -> Sprite2D:
	var tex: Texture2D = null
	# 가상 알 키 `egg:<id>` — 종별 알 그림(초상 아틀라스 `dragon_dragon_<id>_egg`, Icons 규약).
	if key.begins_with("egg:"):
		tex = Icons.dragon_egg_texture(EggGacha.dragon_of(key))
	else:
		var p := Data.item_icon_path(key)
		if p != "" and ResourceLoader.exists(p):
			tex = load(p)
	if tex == null:
		return null
	var s := Sprite2D.new()
	s.texture = tex
	s.material = _pma
	s.position = pos
	s.scale = Vector2(scale, scale)
	return s

## 아이템 표시명 — 가상 알 키(`egg:<id>`)는 EggGacha 가 합성한다.
func _iname(key: String) -> String:
	if key.begins_with("egg:"):
		var d := EggGacha.item_def(key, Data.dragons)
		if not d.is_empty():
			return String(d.get("name", key))
	return Data.item_name(key)

func _portrait_sprite(id: int, stage: String, scale := 1.0) -> Sprite2D:
	var dir := "portrait_%d" % id
	if not _portrait_manifests.has(dir):
		var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
		_portrait_manifests[dir] = JSON.parse_string(f.get_as_text()) if f else {}
	var frame := "dragon_dragon_%d_box_%s" % [id, stage]
	var p := "res://assets/converted/%s/%s.tres" % [dir, frame]
	if not ResourceLoader.exists(p): return null
	var s := Sprite2D.new()
	s.texture = load(p)
	s.material = _pma
	s.scale = Vector2(scale, scale)
	return s

## 원작 실행 버튼(`RoundedButton` = `9patch/btn*`). 공용 헬퍼로 위임한다.
func _btn(parent: Node, text: String, pos: Vector2, sz: Vector2, cb: Callable,
		kind := 0, disabled := false) -> Control:
	return AtlasUI.frame_button(parent, text, pos, sz, cb, kind, disabled)

func _note(text: String) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.86, 0.92, 0.96))
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.09, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(560, 0)
	return l

## 안내는 원작대로 하단 대사창(BottomTextBox)으로 낸다.
func _toast(msg: String, emo := 0) -> void:
	_say(msg, emo)
