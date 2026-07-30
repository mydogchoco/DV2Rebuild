# MainHud — 메인 화면(월드맵) 상시 HUD. render 계층(§8.1).
#
# 포팅 카드 = `docs/ref/porting/WorldMapMainHUD.md`.
#
# ── 판본 주의 (CLAUDE.md §10) ────────────────────────────────────────────────
# 디컴파일된 `WorldMapScene::initUI/initLeftUI/initRightUI`(docs/ref/orig_code/probe/worldmap_ui.c)는 **후기판**이고
# 쓰는 프레임이 전부 `newCommon/ma_*` · `new9patch/ma_bg_*` 다 — `asset_index.py --grep newCommon`
# → **0건**. 반대로 우리 덤프에는 **구판 아이콘 세트**(`scene/worldmap/menu_*` 54종)가 온전히 있다.
# 즉 "배치 코드는 후기판만, 자산은 구판만" 남았다. 그래서:
#   · 좌상단 프로필 / 우상단 재화 → **`TownMainMenuLayer::setMenu` 를 1:1 이식**한다.
#     (유일하게 완전히 디컴파일된 메인 HUD이고, 쓰는 프레임이 전부 보유분이다)
#   · 하단 메뉴바 → 구판 아이콘 + `9patch/menu_bg` 플레이트로 구성한다(사용자 확정 2026-07-27).
#     구판 하단바의 배치 코드는 구 libgame.so 와 함께 유실됐다.
# ⚠️ `scene/worldmap/menu_on|off|menu1_1…3_2` 는 "MENU" 글자가 **구워진** 플레이스홀더 아트라
#    아이콘 받침으로 쓸 수 없다 — 받침은 `9patch/menu_bg` 를 쓴다.
extends CanvasLayer
class_name MainHud

const COMMON := "res://assets/converted/common_ui/%s.tres"
const WMUI := "res://assets/converted/worldmap_ui/%s.tres"
const NP := "res://assets/converted/ninepatch_ui/%s.tres"

## 원작 RoundedLayer::create(200.0, 45.0, 0x66000000, …) — 재화 1행의 반투명 라운드 받침.
## 0x43480000=200.0f · 0x42340000=45.0f · 0x66=alpha 102(40%). 아틀라스 프레임이 아니라
## 코드로 그리는 레이어라 StyleBoxFlat 이 정확한 이식이다(대체품 아님).
const ROUNDED := Vector2(200.0, 45.0)
const ROUNDED_ALPHA := 102.0 / 255.0

## 하단 메뉴바 — 원작 레퍼런스에서 잘라낸 돌바 위 8칸 + 가운데 원형 [동굴] 버튼.
## 액션 코드는 `_act()` 가 해석한다. 원작 `WorldMapScene::onClickMenu` tag 매핑을 근거로 삼되
## 온라인 항목(길드 0x65 · 경매장 · 친구 0xf · 랭킹 · 대전=콜로세움)은 §2-1로 제외했다.
##
## ⚠️ 칸 수는 **레퍼런스 돌바에 실제로 새겨진 8칸**으로 고정된다(우리가 판을 다시 못 나눈다).
##   그래서 종전 9항목 중 '칭호'를 뺐다 — 칭호는 동굴 오른쪽 벽 버튼(`cave.gd:2131`)으로
##   이미 들어갈 수 있어 잃는 게 없다.
const BAR_MENU := [
	["미션", "quests"],        # 원작 tag 0x11 MissionLayer      (레퍼런스 칸: 미션)
	["도감", "dex"],           # 원작 tag 0x26 WorldDragonBookLayer (레퍼런스 칸: 길드=컷)
	["가방", "bag"],           # 원작 BagPopup                    (레퍼런스 칸: 경매장=컷)
	["상점", "shop"],          # 원작 tag 0x16 ShopScene          (레퍼런스 칸: 상점)
	# 원작 메인 메뉴의 '육성'은 `PromoteScene::scene(0)` 으로 간다(WorldMapScene.c:10813·12448).
	["육성", "promote"],       # 원작 PromoteScene                (레퍼런스 칸: 육성)
	["연구소", "laboratory"],  # 원작 LaboratoryScene             (레퍼런스 칸: 던전)
	["점술집", "magicshop"],   # 원작 tag 0x15 MagicShopScene     (레퍼런스 칸: 대전=컷)
	["월드맵", "overview"],    # 원작 tag 0x12 WorldMapFullLayer  (레퍼런스 칸: 기타)
]

## 좌상단 칭호+닉네임 띠(프로필 프레임 뒤로 깔린다).
const INFO := Vector2(200.0, 54.0)

## 하단 메뉴바 = 레퍼런스에서 **픽셀로 잘라낸 통짜 스트립**(scripts/tools/extract_main_bar.py).
## 구판 하단바 배치 코드는 유실됐고 후기판이 부르는 `newCommon/ma_panel_bottom` 등은 우리
## 덤프에 없다(§10) — 자작 도형(`9patch/ranking_teambox` + `common/skill_circle*`)으로
## 흉내 내던 것을 2026-07-28 레퍼런스 추출본으로 교체했다(사용자 지시).
##
## `_clean` = 판에 구워진 한글 라벨과 붉은 알림 뱃지를 지운 판. 우리 메뉴 이름을 얹는다.
## 원본 그대로(미션/길드/경매장/…)를 보고 싶으면 `bottom_bar.png` 로 바꾸면 된다.
const BAR_TEX := "res://assets/converted/mainbar_ui/bottom_bar_clean.png"
## 아래 좌표는 전부 **레퍼런스 원본 픽셀**(1751×986). 화면에는 k = vis.x / 1751 로 옮긴다.
## 스트립 폭·높이·상단 y 는 추출 도구가 남긴 `_bar_meta.json` 에서 읽는다 — 도구 상수를
## 손볼 때마다(원버튼 여유 등) 여기 숫자가 따라 틀어지는 일을 막는다.
const BAR_META := "res://assets/converted/mainbar_ui/_bar_meta.json"
const BAR_REF_W := 1751.0     # 레퍼런스 폭 = 스트립 폭
const BAR_REF_H_FALLBACK := 179.0
const BAR_REF_TOP_FALLBACK := 805.0
## 8칸의 중심 x(원본 픽셀) — 추출 도구 `SLOT_CX` 와 같은 값이다.
const BAR_SLOT_CX := [85.0, 243.0, 437.0, 995.0, 1158.0, 1332.0, 1500.0, 1662.0]
const BAR_SLOT_W := 150.0     # 칸 히트박스 폭(판 폭 실측 ≈160~190, 이음매 젬은 피한다)
const BAR_LABEL_CY := 943.0   # 판에 새겨져 있던 글자의 세로 중심
const BAR_LABEL_H := 34.0     # 판에 새겨져 있던 글자 높이
const BAR_LABEL_SCALE := 0.92  # 그 대비 우리 라벨 크기(사용자 조정 2026-07-28: −8%)
## 가운데 [동굴] 원형 버튼 (cx, cy, r) — 스트립에 이미 그려져 있고 여기선 히트박스만 만든다.
## 구슬은 돌바 위로 솟아 있어 스트립 상단이 여기서 정해진다(월드맵을 가려도 된다 — 사용자 확정).
const BAR_CAVE := Vector3(722.0, 897.0, 92.0)

## 라벨 폰트 = **원작 폰트**. 원작 UI 텍스트는 `GameManager::getFontName_title`(BMFont
## `font/font_title.fnt`, Noto Sans CJK KR 37) 계열이다.
## 🔴 CLAUDE.md §10 의 "BMFont 한글 불가" 는 **오진이었다**(2026-07-28 정정) — 원인은 임포터가
##    아니라 `.fnt` 헤더의 `unicode=0`(=char id 를 ANSI 로 해석) 이었다. `unicode=1` 로 바꾼
##    복사본(`scripts/tools/build_fonts.py` → `assets/converted/font_ui/`)은 1271자 전부 들어온다.
## 고를 때 두 가지를 봤다:
##   · font_title(Noto Sans CJK KR 37) → 619자뿐이라 '감·방·맵' 이 두부(□)로 뜬다. 탈락.
##   · font_subtitle(Noto Sans CJK KR 19) → 1271자 전부. 다만 19px 비트맵을 24px 로 키우면
##     획이 뭉쳐 **두껍게** 보인다(사용자 지적 2026-07-28).
##   ⇒ font_common(HCR Dotum 17, 1271자) — 원작 `getFontName_common` 이고 획이 가늘다.
const BAR_FONT := "res://assets/converted/font_ui/font_common.fnt"

var _pma: CanvasItemMaterial
var _man_common: Dictionary = {}
var _man_wm: Dictionary = {}
var _portrait_man: Dictionary = {}
var _root: Control
## 유타칸 토글을 그릴지(지역 개요/타 지역에서는 숨긴다) + 현재 상태.
var _show_variants := false
## 유타칸 시각 위상 — "day" / "night" / "kades". 월드맵이 넘겨 준다(worldmap.gd `_yutakan_phase`).
## 빈 문자열이면 `UserDB` 플래그로 직접 판단한다(다른 화면에서 붙일 때).
var _phase := ""

## scene 위에 HUD 를 얹는다. 이미 붙어 있으면 그것을 갱신한다.
static func attach(scene: Node, show_variants := false, phase := "") -> MainHud:
	for c in scene.get_children():
		# ⚠️ queue_free() 는 프레임 끝에 처리된다 — `_rebuild()` 직후에는 해제 예약된
		#    구 HUD 가 아직 자식으로 남아 있으므로 건너뛰어야 새 HUD 가 만들어진다.
		if c is MainHud and not c.is_queued_for_deletion():
			var h := c as MainHud
			h._show_variants = show_variants
			h._phase = phase
			h.refresh()
			return h
	var hud := MainHud.new()
	hud.layer = 10
	hud._show_variants = show_variants
	hud._phase = phase
	scene.add_child(hud)
	return hud

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_man_common = _manifest("common_ui")
	_man_wm = _manifest("worldmap_ui")
	refresh()

func refresh() -> void:
	if is_instance_valid(_root):
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var vis := _vis()
	_build_profile(vis)
	_build_currency(vis)
	_build_bottom_bar(vis)
	if _show_variants:
		_build_variant_toggles(vis)

# ============================================================ 좌상단 프로필
## 원작 `TownMainMenuLayer::setMenu` @01a75c40 (tag 0x2bd → StatusLayer):
##   버튼 배경 `common/dragon_bg1.png` (CCMenuItemImageEx, scale 1.05)
##   위치 = VisibleRect::leftTop() + (w*0.5 + 20, -(h*0.5 + 25))
##   z2  `common/dragon_cover1.png` @ 버튼 중앙
##   z1  대표 드래곤 초상 `Dragon::getImagePathBox()` @ 중앙 + (0, 7.5), scale = 90 / 초상폭
##   z3  레벨 BMFont "레벨 %d" scale 0.7 @ (w*0.5, boundingBox.y)
## 원작에 **유저 레벨은 없다**(User 게터 전수에 없음) — 여기 Lv 는 대표 드래곤 레벨이다.
func _build_profile(_vis_size: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var bw := float(_man_common.get("common_dragon_bg1", {}).get("w", 81)) * S * 1.05
	var bh := float(_man_common.get("common_dragon_bg1", {}).get("h", 81)) * S * 1.05
	var cx := bw * 0.5 + 20.0
	var cy := bh * 0.5 + 25.0

	# 칭호 + 닉네임 띠는 프로필 프레임 **뒤로** 깔린다(오른쪽으로 뻗어 나오는 형태) →
	# 프레임보다 먼저 add 해야 프레임이 위에 그려진다.
	# 원작 후기판은 좌상단에 기울어진 리본 배경을 쓰지만(Yutakan_main.png) 그 프레임은
	# `newCommon/ma_*` 라 우리 덤프에 없다(§10). 재화와 같은 어휘인 RoundedLayer 받침을 쓴다 —
	# 맵 라벨 위에 겹쳐도 읽히게 하려면 받침이 필요하고, 이건 원작에도 있는 표현이다.
	var ix := cx + bw * 0.5 - 14.0
	var iy := cy - INFO.y * 0.5
	var band := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0, 0, 0, ROUNDED_ALPHA)
	bsb.set_corner_radius_all(int(INFO.y * 0.35))
	band.add_theme_stylebox_override("panel", bsb)
	band.size = INFO
	band.position = Vector2(ix, iy)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(band)

	var bg := _spr("common_ui", "common_dragon_bg1", _man_common, S * 1.05)
	if bg: bg.position = Vector2(cx, cy); _root.add_child(bg)

	var a := UserDB.active_dragon()
	if not a.is_empty():
		var did := int(a.get("id", 1))
		var lvl := int(a.get("level", 1))
		var por := _portrait(did, Growth.stage_for_level(lvl), int(a.get("skin", 0)))
		if por != null:
			# 원작: 초상 폭을 90 포인트에 맞춘다(scale = 90 / boundingBox.width).
			var pw: float = maxf(1.0, float(por.texture.get_width()))
			var ps := 90.0 / pw
			por.scale = Vector2(ps, ps)
			por.position = Vector2(cx, cy - 7.5)   # 원작 +(0,7.5) 는 cocos y-up → godot 은 -
			_root.add_child(por)

	var cover := _spr("common_ui", "common_dragon_cover1", _man_common, S * 1.05)
	if cover: cover.position = Vector2(cx, cy); _root.add_child(cover)

	# 칭호(원작 User::getTitle) 아트가 곧 텍스트다(title/<no>_kr.png) — 좌측 정렬로 띠 위쪽에.
	var tno := UserDB.user_title_no()
	if tno > 0:
		var tp := "res://assets/converted/%s/title_%d_kr.tres" % [
			String(Data.titles.get("atlas_dir", "title_ui")), tno]
		if ResourceLoader.exists(tp):
			var tr := TextureRect.new()
			tr.texture = load(tp)
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.size = Vector2(INFO.x - 44.0, 24.0)
			tr.position = Vector2(ix + 34.0, iy + 3.0)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_root.add_child(tr)

	# 닉네임. BMFont 한글 불가 → TTF (§10).
	var nick := UserDB.user_nickname()
	if nick != "":
		_root.add_child(_label(nick, 19, Color(1, 0.96, 0.86),
			Vector2(ix + 36.0, iy + INFO.y * 0.5), Vector2(INFO.x - 46.0, 24.0),
			HORIZONTAL_ALIGNMENT_LEFT))
	if not a.is_empty():
		_root.add_child(_label("Lv %d" % int(a.get("level", 1)), 17, Color(1, 0.86, 0.42),
			Vector2(cx - bw * 0.5, cy + bh * 0.5 - 6.0), Vector2(bw, 22.0)))

	# 버튼 히트박스 — 원작 tag 0x2bd = StatusLayer(상태창).
	var hit := _hit(Rect2(cx - bw * 0.5, cy - bh * 0.5, bw, bh), "상태창")
	hit.pressed.connect(func(): _act("status"))
	_root.add_child(hit)

# ============================================================ 우상단 재화
## 원작 `TownMainMenuLayer::setMenu` 후반부. 한 행에 [골드 묶음][다이아 묶음] 나란히.
##   다이아 아이콘 `common/diamond_big` @ (visW - 130, visH - (h*0.5 + 25))
##   골드   아이콘 `common/coin_big`    @ (다이아X - ROUNDED.x - 50, 같은 y)
##   각 묶음: RoundedLayer(200×45, 검정 40%) anchor(1,0.5) 가 아이콘 왼쪽으로 뻗고,
##            숫자 라벨 anchor(1,0.5) @ 패널 오른쪽에서 25 안쪽,
##            충전 버튼 @ (아이콘X - ROUNDED.x + 20) — 골드 `common/charge_coin`(tag 0x2be),
##            다이아 `common/charge`(tag 0x2bf). 둘 다 PremiumShopScene 로 간다.
## 숫자는 원작 `Util::util_add_comma_to_num` = 천 단위 콤마.
func _build_currency(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var dia_h := float(_man_common.get("common_diamond_big", {}).get("h", 33)) * S
	var y := dia_h * 0.5 + 25.0
	var dia_x := vis.x - 130.0
	var gold_x := dia_x - ROUNDED.x - 50.0
	_currency_row(gold_x, y, "common_coin_big", "common_charge_coin",
		_comma(UserDB.gold()), S)
	_currency_row(dia_x, y, "common_diamond_big", "common_charge",
		_comma(UserDB.diamond()), S)

func _currency_row(icon_x: float, y: float, icon_key: String, charge_key: String,
		text: String, S: float) -> void:
	# 받침(RoundedLayer): 앵커가 오른쪽이라 아이콘 중앙에서 왼쪽으로 ROUNDED.x 만큼 뻗는다.
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, ROUNDED_ALPHA)
	sb.set_corner_radius_all(int(ROUNDED.y * 0.5))
	panel.add_theme_stylebox_override("panel", sb)
	panel.size = ROUNDED
	panel.position = Vector2(icon_x - ROUNDED.x, y - ROUNDED.y * 0.5)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(panel)

	# 숫자 — 원작 anchor(1,0.5) @ 패널 오른쪽에서 25 안쪽.
	_root.add_child(_label(text, 21, Color.WHITE,
		Vector2(panel.position.x + 34.0, y - 14.0),
		Vector2(ROUNDED.x - 34.0 - 25.0, 28.0), HORIZONTAL_ALIGNMENT_RIGHT))

	var icon := _spr("common_ui", icon_key, _man_common, S)
	if icon: icon.position = Vector2(icon_x, y); _root.add_child(icon)

	# 충전 버튼 — 원작 (아이콘X - ROUNDED.x) + 20.
	var cb := _spr("common_ui", charge_key, _man_common, S * 1.05)
	var cx := icon_x - ROUNDED.x + 20.0
	if cb: cb.position = Vector2(cx, y); _root.add_child(cb)
	var cw := float(_man_common.get(charge_key, {}).get("w", 30)) * S * 1.05
	var hit := _hit(Rect2(cx - cw * 0.5, y - cw * 0.5, cw, cw), "다이아 상점")
	hit.pressed.connect(func(): _act("cashshop"))
	_root.add_child(hit)

# ============================================================ 하단 메뉴바
## 원작 형태 = 레퍼런스 `docs/ref/orig_image/old_screenshots/Yutakan_main.png` — 화면 폭을 가로지르는 **밝은 돌바**가
## 가운데로 갈수록 살짝 내려앉는 완만한 아치를 그리고, 항목마다 판이 하나씩 얹히며 이음매에
## 작은 청록 젬이 박힌다. 가운데는 바 위로 솟은 **원형 [동굴] 버튼**.
##
## 그 프레임(`newCommon/ma_panel_bottom` · `ma_box_icon_01/02` · `ma_circle_01/02`)은
## **후기판 UI 세트라 우리 덤프에 없고**(CLAUDE.md §10) 구판 하단바의 배치 코드는 구
## libgame.so 와 함께 유실됐다. 종전에는 보유 자산(`9patch/ranking_teambox` +
## `common/skill_circle*`)으로 형태만 흉내 냈는데 — 스킬 슬롯 링을 동굴 버튼 배경으로 쓰는
## 등 — 어색해서, **레퍼런스에서 바를 픽셀로 잘라낸 통짜 스트립**으로 교체했다
## (사용자 지시 2026-07-28, 도구 `scripts/tools/extract_main_bar.py`).
##
## 그래서 여기서는 아무것도 조립하지 않는다: 스트립 1장을 화면 폭에 맞춰 깔고,
## 판에 새겨져 있던 자리(`BAR_SLOT_CX`)에 우리 라벨과 히트박스만 얹는다.
func _build_bottom_bar(vis: Vector2) -> void:
	var meta := _bar_meta()
	var bar_h := float((meta.get("crop", {}) as Dictionary).get("h", BAR_REF_H_FALLBACK))
	var bar_top_ref := float((meta.get("crop", {}) as Dictionary).get("y", BAR_REF_TOP_FALLBACK))
	var k := vis.x / BAR_REF_W                      # 레퍼런스 픽셀 → 화면 좌표 배율
	var top := vis.y - bar_h * k                    # 스트립 상단(화면)
	# 레퍼런스 원본 y → 화면 y
	var ry := func(y: float) -> float: return top + (y - bar_top_ref) * k

	var bar := TextureRect.new()
	if ResourceLoader.exists(BAR_TEX):
		bar.texture = load(BAR_TEX)
	bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bar.stretch_mode = TextureRect.STRETCH_SCALE
	bar.position = Vector2(0.0, top)
	bar.size = Vector2(vis.x, bar_h * k)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bar)

	# 8칸 — 지운 글자 자리에 우리 이름을 같은 크기·색으로 얹는다.
	# 돌판이 밝아 원작 글자도 **어두운 회색**이다(흰 글자가 아니다).
	var fs: int = maxi(10, int(round(BAR_LABEL_H * BAR_LABEL_SCALE * k)))
	var lw := BAR_SLOT_W * k
	var lh := BAR_LABEL_H * k * 1.6
	var bar_font := _orig_font()
	for i in mini(BAR_MENU.size(), BAR_SLOT_CX.size()):
		var e: Array = BAR_MENU[i]
		var mid: float = float(BAR_SLOT_CX[i]) * k
		var l := _label(String(e[0]), fs, Color(0.20, 0.20, 0.22),
			Vector2(mid - lw * 0.5, ry.call(BAR_LABEL_CY) - lh * 0.5), Vector2(lw, lh))
		l.add_theme_constant_override("outline_size", 0)
		if bar_font != null:
			l.add_theme_font_override("font", bar_font)
		_root.add_child(l)
		var hit := _hit(Rect2(Vector2(mid - lw * 0.5, top), Vector2(lw, bar_h * k)),
			String(e[0]))
		hit.pressed.connect(func(): _act(String(e[1])))
		_root.add_child(hit)

	# 중앙 [동굴] 원형 버튼 — 그림은 스트립에 이미 있다(글자 '동굴'도 원작 각인 그대로).
	# 여기서는 히트박스만 만든다. 원작 `WorldMapScene::moveCave`.
	var cr := BAR_CAVE.z * k
	var cc := Vector2(BAR_CAVE.x * k, ry.call(BAR_CAVE.y))
	var chit := _hit(Rect2(cc - Vector2(cr, cr), Vector2(cr, cr) * 2.0), "동굴")
	chit.pressed.connect(func(): _act("cave"))
	_root.add_child(chit)

# ============================================================ 유타칸 변형 토글
## 원작은 **아모르(tag 0x67) / 카데스(tag 0x68)** 를 같은 자리의 메뉴 항목으로 두고
## `setNormalSpriteFrame` 으로 프레임을 갈아끼워 현재 모드를 보여 준다
## (`WorldMapScene.c:21211 menu_amorru_mode_%s.png` / `:21287 menu_kades_mode_%s.png`,
##  `onClickChangeKades` 가 두 tag 를 한 핸들러에서 처리 — :10025/:10050).
## ⚠️ **밤/낮 토글은 전용 아이콘 근거를 못 찾았다.** `onClickChangeNight` 핸들러는 실재하지만
##    그 버튼을 만드는 코드가 디컴프 범위 밖이고, 아틀라스 전수에도 night 토글 아이콘이 없다
##    (`asset_index.py --grep night` → 맵 오버레이 프레임뿐). → 텍스트 버튼으로 둔다(§10 등재).
func _build_variant_toggles(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var x := vis.x - 58.0
	var y := 160.0        # 우상단 재화(≈y47) · 가이드 버튼(y70~104) 아래
	# 유타칸은 낮 / 밤 / 카데스의 공간 셋 중 하나다(사용자 확정 2026-07-29).
	# 월드맵이 위상을 넘겨 주면 그것을 쓴다 — 진입 params 로 덮어쓴 경우 UserDB 와 다를 수 있다.
	var night := bool(UserDB.get_pmeta("yutakan_night", false))
	var kades := bool(UserDB.get_pmeta("kades_space", false))
	if _phase != "":
		kades = _phase == "kades"
		night = _phase == "night"

	# 카데스의 공간 — 원작 프레임 그대로.
	var kb := _spr("worldmap_ui", "scene_worldmap_menu_kades_mode_kr", _man_wm, S * 0.85)
	if kb:
		kb.position = Vector2(x, y)
		kb.modulate = Color(1, 1, 1, 1.0 if kades else 0.55)
		_root.add_child(kb)
	var kh := _hit(Rect2(x - 40.0, y - 40.0, 80.0, 80.0), "카데스의 공간")
	kh.pressed.connect(func():
		UserDB.set_pmeta("kades_space", not kades)
		_reload_worldmap())
	_root.add_child(kh)

	# 밤/낮 — 원작 아이콘 미확인(§10). 보유 9patch 버튼 + 텍스트로 대체.
	# **카데스의 공간에는 낮/밤 구분이 없다**(사용자 확정 2026-07-29: 유타칸은 낮·밤·카데스 셋).
	# → 카데스가 켜져 있으면 이 버튼 자체를 내린다. 카데스를 끄면 직전 낮/밤 상태로 돌아간다
	#   (원작 `changeKadesAndAmorru(false)` 도 `getDBYutakanNight()` 로 되돌린다).
	if kades:
		return
	var ny := y + 86.0
	var nb := NinePatchRect.new()
	nb.texture = load(NP % "9patch_btn")
	nb.patch_margin_left = 20; nb.patch_margin_top = 20
	nb.patch_margin_right = 17; nb.patch_margin_bottom = 18
	nb.size = Vector2(84.0, 40.0)
	nb.position = Vector2(x - 42.0, ny - 20.0)
	nb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(nb)
	_root.add_child(_label("낮으로" if night else "밤으로", 17, Color.WHITE,
		nb.position, nb.size))
	var nh := _hit(Rect2(nb.position, nb.size), "밤/낮 전환")
	nh.pressed.connect(func():
		UserDB.set_pmeta("yutakan_night", not night)
		_reload_worldmap())
	_root.add_child(nh)

## 토글 후 월드맵 재빌드. `_rebuild()` 가 자식(=이 HUD 포함)을 전부 free 하고
## `_build_hud()` 로 새 HUD 를 붙이므로 여기서 refresh() 를 부르면 안 된다(해제된 노드 접근).
func _reload_worldmap() -> void:
	var sc := Scenes.current_scene()
	if sc != null and sc.has_method("_rebuild"):
		sc.call("_rebuild")

# ============================================================ 액션 라우팅
## 원작 `WorldMapScene::onClickMenu` / `TownMainMenuLayer::onClickMenu` 의 tag 분기 대응.
## 원작에서는 도감/가방/미션/칭호/상태창이 전부 **월드맵 위의 독립 레이어**였다.
##   · 미션(`MissionLayer`) · 상태창(`StatusLayer`) = 떼어냈다 → 여기서 제자리에서 띄운다.
##   · 도감/가방/칭호 = 아직 cave.gd 안이라 cave 씬으로 가면서 `open` 파라미터로 지정한다.
func _act(action: String) -> void:
	match action:
		"cave":
			Scenes.goto("cave")
		"shop", "magicshop", "laboratory", "breeding", "promote":
			# `from` = 나갈 때 돌아올 곳. 원작은 메인에서 직행하고 뒤로가면 메인으로 돌아온다.
			Scenes.goto(action, {"from": "worldmap"})
		"status":
			# 원작 `WorldMapScene::onClickMenu` tag 0xb / `TownMainMenuLayer::onClickMenu` tag 0x2bd
			# — 상태창은 메인 화면 **위에 뜨는 레이어**다. 씬 이동 없이 제자리에서 띄운다.
			var sl := StatusLayer.open(get_parent() if get_parent() != null else self)
			# 심화 편집(젬/장비/레벨업…)은 cave.gd 안의 팝업들이라 동굴 씬으로 넘긴다
			# (사용자 확정 2026-07-28). 상태창 자체는 여기서 즉시 열린다.
			sl.action_requested.connect(func(a: String, arg: int):
				Scenes.goto("cave", {"open": a, "arg": arg}))
			sl.closed.connect(refresh)
		"quests":
			# 원작 tag 0x11 `MissionLayer` — **메인 화면 위에 뜨는 레이어**다
			# (`WorldMapScene.c:13371` 이 `MissionLayer::create(4)` 를 월드맵 씬에 얹는다).
			# 2026-07-30 까지는 동굴 씬으로 이동해서 열었다 → 제자리에서 띄우도록 고쳤다.
			var host := get_parent() if get_parent() != null else self
			var ml := MissionLayer.open(host, 0, "worldmap", {})
			ml.changed.connect(refresh)
		"dex", "bag", "titles":
			Scenes.goto("cave", {"open": action})
		"cashshop":
			# 원작 ⊞ = PremiumShopScene 직행(tag 0x2be/0x2bf). 오프라인은 상점의 '환전' 탭.
			Scenes.goto("shop", {"tab": "cash", "from": "worldmap"})
		"overview":
			# 원작 tag 0x12 `WorldMapFullLayer` = 전체 지역 개요. 우리 월드맵의 overview 모드.
			var sc := Scenes.current_scene()
			if sc != null and sc.has_method("_rebuild") and "_mode" in sc:
				sc.set("_mode", "overview")
				sc.call("_rebuild")
			else:
				Scenes.goto("worldmap")

# ============================================================ helpers
func _vis() -> Vector2:
	return get_viewport().get_visible_rect().size

var _bar_meta_cache: Dictionary = {}
func _bar_meta() -> Dictionary:
	if _bar_meta_cache.is_empty():
		var f := FileAccess.open(BAR_META, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary: _bar_meta_cache = d
	return _bar_meta_cache

## 원작 BMFont. `fixed_size` 가 박혀 있어 기본값으로는 font_size 를 무시하고 19px 로만 그린다
## → `fixed_size_scale_mode = ENABLED` 로 크기 조절을 허용한다(리소스를 복제해서 손댄다).
var _orig_font_cache: Font = null
func _orig_font() -> Font:
	if _orig_font_cache != null:
		return _orig_font_cache
	if not ResourceLoader.exists(BAR_FONT):
		return null
	var f := (load(BAR_FONT) as FontFile)
	if f == null:
		return null
	f = f.duplicate() as FontFile
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	_orig_font_cache = f
	return f

func _manifest(dir: String) -> Dictionary:
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func _spr(dir: String, key: String, man: Dictionary, scale := 1.0) -> Sprite2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	if not ResourceLoader.exists(p):
		push_warning("[MainHud] 프레임 없음: %s/%s" % [dir, key])
		return null
	var s := Sprite2D.new()
	s.texture = load(p)
	s.material = _pma
	s.scale = Vector2(scale, scale)
	if not man.has(key):
		push_warning("[MainHud] 매니페스트에 키 없음: %s" % key)
	return s

func _portrait(id: int, stage: String, skin: int) -> Sprite2D:
	var dir := "portrait_%d" % id
	if not _portrait_man.has(dir):
		_portrait_man[dir] = _manifest(dir)
	var frame := "dragon_dragon_%d_box_%s" % [id, stage]
	if skin > 0 and (_portrait_man[dir] as Dictionary).has("%s_skin%d" % [frame, skin]):
		frame = "%s_skin%d" % [frame, skin]
	return _spr(dir, frame, _portrait_man[dir], 1.0)

func _label(text: String, size: int, color: Color, pos: Vector2, dim: Vector2,
		align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = pos; l.size = dim
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## 투명 히트박스. `flat = true` 만으로는 **hover/pressed/focus 스타일박스가 그대로 그려져**
## 돌바 위에 회색 네모가 뜬다(사용자 지적 2026-07-28) → 전 상태를 빈 스타일박스로 덮는다.
func _hit(rect: Rect2, tip: String) -> Button:
	var b := Button.new()
	b.flat = true
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	b.position = rect.position
	b.size = rect.size
	b.tooltip_text = tip
	return b

## 원작 Util::util_add_comma_to_num — 천 단위 콤마.
func _comma(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out
