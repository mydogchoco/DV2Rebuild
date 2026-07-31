extends Control
## 점술집(MagicShopScene) — 유리아의 가게. render 층(§8).
##
## ⚠️ 클래스 확정 근거(자산 이름으로 추측 금지 — CLAUDE.md §3):
##   원작 문자열 테이블 `DV2/string/stringsData_KR.xml` 에 `<TitleMagicShop>점술집`,
##   `<TitleMagicShopB1>점술집 지하`, `<MagicWelcomeMsg1>어서 오세요.\n이곳은 신비로운 점술집입니다.`
##   ⇒ 점술집 = **MagicShopScene**. (`TacCardScene` 은 전술카드=PvP 로 §1 CUT 이며 점술집이 아니다.)
##
## 원작 구성(audit_scene.py MagicShopScene · docs/ref/audit/MagicShopScene.md):
##   · 배경 `scene/magicshop/magicshop_bg.jpg`(1층) / `magicshop_bg2.jpg`(지하) — `changeFloor`
##   · `scene/magicshop/table.png`(rightBottom 앵커) + `crystalball.png`(탁자 위)
##   · 재화바 `common/money_bg` + `coin_small1` + `diamond_small1`
##   · 하위 레이어 = AlchemyLayer(연금술) · PotionLayer(용액) · UpgradeGemLayer(젬 강화)
##     · UpgradeSoulGemLayer(소울젬) · TransDragonLayer(드래곤 변환) · CodeLayer(쿠폰)
##   · 항목 아이콘 = `icon_gem` `icon_drink` `icon_egg` `icon_summon` `icon_slot` `icon_code`
##   · 수정구 파티클 `particle/scene/fortunetent/crystalball.plist`
##
## 오프라인 변형: **프리미엄** 카드 코드(PremiumCodeLayer)는 결제라 §1 CUT — 목록에서 제외.
## 일반 카드 코드는 살렸다(아래 '오프라인 처리' 참조).
##
## 경제 근거(위키 gems.pdf §2.2 + items.json 실재 아이템):
##   혼성젬 제작 = 공/방/체 가루 각 20개 → `att_powder`(붉은) `def_powder`(푸른) `hp_powder`(노란)
##   용액 제작   = 각 가루 N개씩       → `alchemy_moderation/wisdom/courage/justice`
##   젬 강화/승급 = data/gems.json upgrade (로직은 scripts/systems/gem.gd)

const DIR_UI := "magicshop_ui"
const DIR_BG := "res://assets/converted/magicshop_bg/%s"

## 원작 구조(2026-07-28 레퍼런스 대조로 재정정):
##   근거 = `docs/ref/orig_image/shop/점술집_젬강화.pdf` 본문 스크린샷 2장(1층·지하, 2016) +
##          `MagicShopScene::setItems`(카드 생성) + 문자열 `<MagicTitle*>` `<MagicAlchemy_menu*>`.
##   · 기능은 **카드 격자**로 고른다 — `common/item_bg` + `common/backlight3`(w/2, h/2-10)
##     + 아이콘(w/2, h/2-10) + 라벨(w/2, h-15, 앵커 0.5/1), 카드 scale 1.1,
##     행 간격 = (카드높이 + 15). (좌측 세로 리스트는 우리 자작이었다 — 폐기)
##   · 지하(연금술)는 **탭이 아니라 1층 '연금술' 카드로 들어간다**. 돌아올 땐 좌상단 뒤로 화살표.
##   · 우측에 NPC **유리아**(npc/yulia) + 하단 대사창(BottomTextBox).
## ⚠️ `alchemy/icon_soul.png` 는 추출 에셋에 없다(`--grep icon_soul` → 0건) → `icon_alchemy_05` 대체.
##    2016 레퍼런스의 지하에도 소울젬 항목이 없다 ⇒ `<MagicAlchemy_menu6>` 는 후기 추가분.
## 메뉴 구성 — **2016 구판 레퍼런스**(`docs/ref/orig_image/shop/점술집_젬강화.pdf` 본문 스크린샷)를 따른다.
##
## 판본이 갈린다(§10 의 반복 패턴: 배치코드=후기판 / 자산·레퍼런스=구판):
##   · 후기판 디컴프 `MagicShopScene::setItems`(:604-851) 는 1층 **4항목 2열**
##     (`icon_code`·`icon_summon`·`icon_slot`·`icon_code_premium`), 지하 6항목 3열이고
##     젬 강화(`icon_gem`)를 **지하**에 둔다.
##   · 구판 레퍼런스는 1층 **6항목 3열**(드링크 강화·젬 강화·뽑기 / 카드 코드·드래곤 소환·연금술),
##     지하 **5항목 3열**(혼성젬 강화·제작·젬 분해 / 용액 제작·용액 상점)이다.
## 우리 아틀라스가 구판이고(icon_soul 부재·icon_alchemy_05 실재) 레퍼런스도 구판이라
## **구판을 따른다**(사용자 확정 2026-07-28). 지하는 혼성젬 계열 전용이고, 일반 젬 강화는 1층이다.
##
## ⚠️ 2026-07-28 초기에 후기판 디컴프만 보고 1층을 2칸으로 줄였던 것은 오판이었다 — 되돌렸다.
##
## 오프라인 처리(2026-07-30 구현 완료): `카드 코드`·`드래곤 소환`은 원작이 서버 인증/서버
## 데이터였지만 **둘 다 오프라인용으로 재설계해 실제로 동작한다**. 프리미엄 카드 코드는
## 구판 1층에 없으므로 제외.
##   · `카드 코드`(CodeLayer) — 판정표는 사용자가 채우는 이스터에그(`docs/input/sheets/card_codes.csv`,
##     **gitignore**). `build_card_codes.py` 가 **코드로만 풀리는 암호문**으로 구워 `data/card_codes.json`
##     에 싣는다 → 빌드를 뜯어도 코드 목록·보상을 볼 수 없다. 로직 = `CardCode`.
##   · `드래곤 소환`(TransDragonLayer) — 원작은 DV1 계정 연동이라 이식 대상이 아니다. 보유 드래곤을
##     커스텀 종(600 수비형 / 700 공격형) 알로 바꾸는 기능으로 교체했다. 기본 잠김이고 해금
##     플래그가 있을 때만 1회. 규칙 = `Summon`, 상세 = `docs/ref/porting/TransDragonLayer.md`.
##
## 층 전환은 구판대로 **'연금술' 카드 진입 + 지하 좌상단 뒤로 화살표**다(제목바 탭이 아니다 —
## 탭은 후기판 방식이고 그 프레임도 우리 덤프에 없다, §10).
const ITEMS := [
	# 1층 — 점술집(구판 3열). 레퍼런스 스샷의 6칸 순서 그대로.
	[
		{"key": "drink", "label": "드링크 강화", "icon": "icon_drink", "dir": "ui", "orig": "DrinkCraftLayer"},
		{"key": "gem", "label": "젬 강화", "icon": "icon_gem", "dir": "ui", "orig": "GemCraftLayer"},
		{"key": "slot", "label": "뽑기", "icon": "icon_slot", "dir": "ui", "orig": "SlotLayer"},
		{"key": "code", "label": "카드 코드", "icon": "icon_code", "dir": "ui", "orig": "CodeLayer"},
		{"key": "trans", "label": "드래곤 소환", "icon": "icon_summon", "dir": "ui", "orig": "TransDragonLayer"},
		{"key": "alchemy_enter", "label": "연금술", "icon": "icon_alchemy", "dir": "al", "orig": "changeFloor(+1)"},
	],
	# 지하 — 연금술(<MagicAlchemy_menu1~5>), 구판 3열. 순서는 레퍼런스 스샷 그대로.
	# 라벨↔아이콘은 그 스샷이 제목과 UI 를 함께 보여 주므로 1차 근거다:
	#   절구 01=혼성젬 강화(용액 투입·성공률) · 망치 02=혼성젬 제작(가루 3상자) ·
	#   별+젬 04=젬 분해 · 플라스크 03=용액 제작 · 수레 05=용액 상점
	# ⚠️ `<MagicAlchemy_menu6>` 소울젬은 아이콘(`alchemy/icon_soul`) 부재 + 2016 지하에도 없다
	#    ⇒ 후기 추가분 → 제외. 소울젬 승급·강화는 1층 '젬 강화'가 함께 다룬다.
	[
		{"key": "hybrid_up", "label": "혼성젬 강화", "icon": "icon_alchemy_01", "dir": "al", "orig": "AlchemyLayer"},
		{"key": "alchemy", "label": "혼성젬 제작", "icon": "icon_alchemy_02", "dir": "al", "orig": "UpgradeGemLayer(1)"},
		{"key": "disassemble", "label": "젬 분해", "icon": "icon_alchemy_04", "dir": "al", "orig": "UpgradeGemLayer(2)"},
		{"key": "potion_make", "label": "용액 제작", "icon": "icon_alchemy_03", "dir": "al", "orig": "PotionLayer(1)"},
		{"key": "potion_shop", "label": "용액 상점", "icon": "icon_alchemy_05", "dir": "al", "orig": "구판 전용(후기판 코드에 없음)"},
		# 🔀 2026-07-31 복구: 종전엔 아이콘(`alchemy/icon_soul`) 부재 + 2016 지하 스샷에 없다는
		#   이유로 뺐는데, 사용자가 준 참조 영상(`docs/ref/gem/소울젬1.png`)의 **지하 6칸**에
		#   `소울젬 승급/강화` 카드가 실재한다 ⇒ 항목은 원작에 있다. 없는 것은 **카드 아이콘뿐**이라
		#   위키에서 복원한 소울젬 그림(`assets/converted/gem_soul/`)으로 대신한다.
		{"key": "soul", "label": "소울젬 승급/강화", "icon": "", "alt_icon": "gem_soul_att9",
			"dir": "al", "orig": "UpgradeSoulGemLayer"},
	],
]
## 두 층 다 3열(구판 레퍼런스 실측).
const FLOOR_COLS := [3, 3]
const DIR_AL := "magicshop_alchemy"

var _params: Dictionary = {}
var _pma: CanvasItemMaterial
var _man: Dictionary = {}
var _man_al: Dictionary = {}
var _tab := -1        # -1 = 메뉴 격자(원작 setItems), 그 외 = 기능 화면
var _floor := 0        # 원작 changeFloor: 0=1층, 1=지하
var _npc: NpcPortrait
var _box: BottomTextBox
var _popup: OrigPopup
var _money_root: Control
## 드래곤 소환 화면 상태 — 재료로 고른 개체 uid, 부를 종(600/700). 팝업 재빌드를 넘어 유지된다.
## 젬 분해 6칸에 올려 둔 인벤 키(원작 `UpgradeGemLayer` 의 선택 슬롯 배열).
var _dis_slots: Array = ["", "", "", "", "", ""]
## 소울젬 승급/강화의 대상 인벤 키(원작 `UpgradeSoulGemLayer::settingGem` 의 선택 젬).
var _soul_key := ""
var _summon_uid := 0
var _summon_species := Summon.SPECIES_DEF
## 이번 지급에서 **공개할 알** 대기열(`EggResultPopup`). 한 칸 = {did, opts}.
var _egg_reveal: Array = []
## 커스텀 종의 표시 이름 — 마스터 데이터에 이름이 없다(플레이어 선택권 드래곤).
const SPECIES_LABEL := {Summon.SPECIES_DEF: "수비형", Summon.SPECIES_ATK: "공격형"}

func _items() -> Array:
	return ITEMS[clampi(_floor, 0, ITEMS.size() - 1)]

func enter(params: Dictionary = {}) -> void:
	# 원작 BGM: music/bg_magicshop.mp3 (asset_index --grep magicshop → prefix:music/bg_magicsh(MagicShopScene)).
	Bgm.play("bg_magicshop")
	_params = params
	if _pma != null: _rebuild()

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

## 점술집 아틀라스 프레임 스프라이트(회전/PMA 보정). §9: 480 아틀라스는 ASSET_SCALE(4/3)로 그린다.
## dir = "ui"(scene/magicshop) / "al"(scene/magicshop/alchemy).
func _spr(name: String, scale := 1.0, dir := "ui") -> Sprite2D:
	var tex := _tex(name, dir)
	if tex == null: return null
	var s := Sprite2D.new(); s.texture = tex; s.material = _pma
	# 회전 보정 불필요 — 변환 단계가 흡수(scripts/tools/fix_rotated_frames.py)
	s.scale = Vector2(scale, scale)
	return s

func _tex(name: String, dir := "ui") -> Texture2D:
	var p := "res://assets/converted/%s/scene_magicshop_%s.tres" % [DIR_UI, name] if dir == "ui" \
		else "res://assets/converted/%s/scene_magicshop_alchemy_%s.tres" % [DIR_AL, name]
	return load(p) if ResourceLoader.exists(p) else null

func _rebuild() -> void:
	for c in get_children(): c.queue_free()
	_load_man()
	var vis := _vis()
	var S := Design.ASSET_SCALE
	# 배경(원작 magicshop_bg.jpg / 지하 magicshop_bg2.jpg).
	var bgfile := "magicshop_bg2.jpg" if _floor == 1 else "magicshop_bg.jpg"
	var bgp := DIR_BG % bgfile
	if ResourceLoader.exists(bgp):
		var full := TextureRect.new(); full.texture = load(bgp)
		full.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		full.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		full.set_anchors_preset(Control.PRESET_FULL_RECT)
		full.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(full)
	else:
		var bg := ColorRect.new(); bg.color = Color(0.10, 0.07, 0.16)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
	# 탁자 + 수정구 — 원작 initWidget 좌표(MagicShopScene.c:905~).
	#   table      : `VisibleRect::rightBottom()` anchor(1,0)  → 우하단 정렬
	#   crystalball: `CCPoint(visW - 280, 235)`  (cocos y-up → Godot y = 692 - 235)
	#   파티클     : `particle/scene/fortunetent/crystalball.plist` 를 수정구 중앙에
	var table := _spr("table", S)
	if table:
		table.centered = false
		var tw := table.texture.get_width() * S
		var th := table.texture.get_height() * S
		table.position = Vector2(vis.x - tw, vis.y - th); add_child(table)
	var ball := _spr("crystalball", S)
	if ball:
		ball.position = Vector2(vis.x - 280.0, Design.flip_y(235.0)); add_child(ball)
		_ball_particle(ball)
		# 원작 연출 액션(CCScaleTo)에 대응하는 은은한 맥동.
		var t := ball.create_tween().set_loops()
		t.tween_property(ball, "scale", Vector2(S * 1.06, S * 1.06), 1.4).set_trans(Tween.TRANS_SINE)
		t.tween_property(ball, "scale", Vector2(S, S), 1.4).set_trans(Tween.TRANS_SINE)
	# 원작 `MagicShopScene` 은 항상 카드 격자를 그린다 — 기능 화면은 그 **위에 뜨는 팝업**이지
	# 화면 교체가 아니다(`MagicShopScene.c:1471-1545` `PopupLayer::show(this, 0x82, 127.0)`).
	_build_menu(vis)           # 원작 setItems: 카드 격자
	_build_npc(vis)            # 유리아 + 하단 대사창
	_build_money(vis)
	_build_title(vis)          # 제목 + X + 뒤로 화살표

## 수정구 파티클 — 원작 `particle/scene/fortunetent/crystalball.plist`.
## 변환: `scripts/tools/particle_export.py` → assets/converted/particles/crystalball.json.
func _ball_particle(ball: Sprite2D) -> void:
	var f := FileAccess.open("res://assets/converted/particles/crystalball.json", FileAccess.READ)
	if f == null: return
	var c = JSON.parse_string(f.get_as_text())
	if typeof(c) != TYPE_DICTIONARY: return
	var p := CPUParticles2D.new()
	p.texture = _dot_tex()
	p.amount = int(c.get("amount", 60))
	p.lifetime = float(c.get("lifetime", 2.0))
	p.lifetime_randomness = float(c.get("lifetime_randomness", 0.0))
	p.direction = Vector2(float(c["direction"][0]), float(c["direction"][1]))
	p.spread = float(c.get("spread", 20.0))
	p.initial_velocity_min = maxf(0.0, float(c.get("vmin", 0.0)))
	p.initial_velocity_max = maxf(0.0, float(c.get("vmax", 10.0)))
	p.gravity = Vector2(float(c["gravity"][0]), float(c["gravity"][1]))
	p.scale_amount_min = float(c.get("scale_min", 0.2))
	p.scale_amount_max = float(c.get("scale_max", 0.5))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(float(c["emit_rect"][0]), float(c["emit_rect"][1]))
	var g := Gradient.new()
	g.set_color(0, Color(float(c["color_start"][0]), float(c["color_start"][1]),
		float(c["color_start"][2]), float(c["color_start"][3])))
	g.set_color(1, Color(float(c["color_end"][0]), float(c["color_end"][1]),
		float(c["color_end"][2]), float(c["color_end"][3])))
	p.color_ramp = g
	if bool(c.get("additive", false)):
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = m
	ball.add_child(p)

## 파티클용 부드러운 점 텍스처(원작 임베드 텍스처 대체 — battle.gd 와 같은 방식).
func _dot_tex() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

## 제목 + 닫기 X + (지하이거나 기능 화면일 때) 좌상단 뒤로 화살표.
## 원작 제목 문자열 = `<TitleMagicShop>점술집` / `<TitleMagicShopB1>점술집 지하`.
## 레퍼런스 스샷의 지하 화면 좌상단에 분홍 뒤로 화살표가 있다 — `common/back_btn` 프레임
## (원작 `LaboratoryScene::initMenu` 도 같은 프레임을 같은 용도로 쓴다).
func _build_title(vis: Vector2) -> void:
	var t := Label.new()
	t.text = "점술집 지하" if _floor == 1 else "점술집"
	t.add_theme_font_size_override("font_size", 32)
	t.add_theme_color_override("font_color", Color(1, 0.72, 0.85))
	t.add_theme_color_override("font_outline_color", Color(0.28, 0.06, 0.2, 0.95))
	t.add_theme_constant_override("outline_size", 6)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size = Vector2(vis.x, 48)
	t.position = Vector2(0, 12)
	t.z_index = 10
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)

	var x := AtlasUI.spr("common_ui", "common_close_btn", Design.ASSET_SCALE)
	if x != null:
		x.position = Vector2(vis.x - 42, 36)
		x.z_index = 11
		add_child(x)
	var xb := Button.new()
	xb.flat = true
	xb.size = Vector2(56, 56)
	xb.position = Vector2(vis.x - 70, 8)
	xb.z_index = 11
	xb.pressed.connect(_leave)
	add_child(xb)

	# 구판 층 전환: 지하에서는 좌상단 뒤로 화살표로 1층에 돌아간다(레퍼런스 지하 스샷).
	# ⚠️ 후기판은 제목바 탭이지만 그 프레임(`common/bg/tab_bg` · `txt_magicshop2_*`)이
	#    우리 덤프에 통째로 없다(§10) — 구판 방식이 자산과도 맞는다.
	if _floor > 0:
		var ba := AtlasUI.spr("common_ui", "common_back_btn", Design.ASSET_SCALE)
		if ba != null:
			ba.position = Vector2(46, 36)
			ba.z_index = 11
			add_child(ba)
		var bb := Button.new()
		bb.flat = true
		bb.size = Vector2(64, 56)
		bb.position = Vector2(14, 8)
		bb.z_index = 11
		bb.pressed.connect(func(): _set_floor(0))
		add_child(bb)

## 원작 `changeFloor` — 층을 바꾸면 배경·메뉴가 통째로 바뀐다.
func _set_floor(f: int) -> void:
	if f == _floor or is_instance_valid(_popup):
		return
	_floor = f
	_tab = -1
	_rebuild()

## 점술집을 완전히 나간다(원작 onClickClose).
func _leave() -> void:
	var from := String(_params.get("from", "town"))
	if from == "worldmap":
		Scenes.goto("worldmap", {"region": "yutakan"})
	else:
		Scenes.goto("town", {"area": _params.get("area", "elpis")})

## 원작 `MagicShopScene::setItems`(`docs/ref/orig_code/decomp/MagicShopScene.c:2346`) 1:1.
##
## 원작 값 그대로:
##   · 카드 = `common/item_bg`(109×138px = 145.3×184pt), **추가 배율 없음**
##   · `common/backlight3` `setScale(0.35)` @ `(w/2, h/2 − 10)` + `CCRotateBy(3.0, 60°)` 무한반복
##     (⚠️ 회전이 빠져 있었다)
##   · 아이콘 @ `(w/2, h/2 − 10)`
##   · 라벨 @ `(w/2, h − 15)` anchor(0.5, 1.0), `setScale(0.7)`
##   · 열 간격 = 카드폭 + 15 + 25, **행 간격도 카드높이 + 15 + 25**
##   · 마지막 줄이 열수 미만이면 `열간격 × (열수 − n%열수) × 0.5` 만큼 밀어 가운데 정렬
##
## 레퍼런스 실측(`docs/ref/orig_image/shop/점술집_젬강화.pdf` 지하 스샷, 740×415)으로 교차검증:
##   카드 폭 91px·높이 116px, 열 피치 111.5px, 행 피치 135px, 2행이 반 피치만큼 밀려 있다.
##   → 692 공간 환산 시 폭 151.7 / 피치 185.9·225.1 pt = **contentSize + 40** 과 일치하고,
##     카드 배율은 1.0(테두리 2px 포함분을 빼면 184pt)임이 확인된다.
##     ⚠️ 이전 코드의 `1.1 배율` · `행 간격 = 높이 + 15` 는 둘 다 틀렸다.
##
## ASSUMPTION: 격자 **원점**은 원작 컨테이너 계산이 디컴프에서 접혀 있어 위 레퍼런스 실측치를 썼다
##   (1행 카드 상단 = cocos y 572, 좌측 여백 = 화면폭의 15.8%).
##
## ⚠️ 메뉴 **구성**은 원작과 다르다 — 원작 1층은 4항목 2열(`icon_code`·`icon_summon`·`icon_slot`·
##   `icon_code_premium`)이고 젬/드링크는 지하 소속이다. 우리 6+6 구성은 §1 CUT(코드·프리미엄)과
##   기능 보존을 위해 앞서 정한 것이라 그대로 둔다. 배치 규격만 원작으로 맞춘다.
const MENU_ROW0_TOP_COCOS := 572.0
const MENU_LEFT_FRAC := 0.158

func _build_menu(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var cw := AtlasUI.size_pt("common_ui", "common_item_bg").x
	var ch := AtlasUI.size_pt("common_ui", "common_item_bg").y
	var items := _items()
	var n := items.size()
	var cols: int = FLOOR_COLS[clampi(_floor, 0, FLOOR_COLS.size() - 1)]
	var gx := cw + 15.0 + 25.0
	var gy := ch + 15.0 + 25.0
	var x0: float = round(vis.x * MENU_LEFT_FRAC)
	var y0 := Design.flip_y(MENU_ROW0_TOP_COCOS)
	for i in n:
		var it: Dictionary = items[i]
		var col := i % cols
		var row := i / cols
		var dx := 0.0
		if n % cols != 0 and (n - n % cols) <= i:
			dx = gx * float(cols - n % cols) * 0.5
		# 카드 로컬 좌표계(좌상단 원점) — 원작 cocos 값은 y 를 뒤집어 적는다.
		var card := Control.new()
		card.size = Vector2(cw, ch)
		card.position = Vector2(x0 + col * gx + dx, y0 + row * gy)
		card.z_index = 2
		add_child(card)
		var frame := AtlasUI.spr("common_ui", "common_item_bg", S)
		if frame != null:
			frame.position = Vector2(cw, ch) * 0.5
			card.add_child(frame)
		var back := AtlasUI.spr("common_ui", "common_backlight3", 0.35 * S)
		if back != null:
			back.position = Vector2(cw * 0.5, ch * 0.5 + 10.0)
			card.add_child(back)
			var rt := back.create_tween().set_loops()
			rt.tween_property(back, "rotation", TAU / 6.0, 3.0).as_relative()
		var ic := _spr(String(it["icon"]), S, String(it.get("dir", "ui")))
		if ic == null and String(it.get("alt_icon", "")) != "":
			# 원본 카드 아이콘이 없는 항목(소울젬 = `alchemy/icon_soul` 부재)의 대체 —
			# 위키에서 복원한 소울젬 그림. 자작 도형이 아니라 원작 자산이다.
			ic = AtlasUI.spr("gem_soul", String(it["alt_icon"]), S * 0.62)
		if ic != null:
			ic.position = Vector2(cw * 0.5, ch * 0.5 + 10.0)
			card.add_child(ic)
		var l := Label.new()
		l.text = String(it["label"])
		l.add_theme_font_size_override("font_size", 19)
		l.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size = Vector2(cw, 26.0)
		l.position = Vector2(0, 15.0 - 13.0)          # 원작 (w/2, h − 15) anchor(0.5,1.0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(l)
		var b := Button.new()
		b.flat = true
		b.size = Vector2(cw, ch)
		var idx := i
		b.pressed.connect(func(): _on_menu(idx))
		card.add_child(b)

## 원작 `onClickItem`(1층) / `onClickAlchemyItem`(지하) — 기능 레이어를 **팝업으로** 띄운다.
## 근거: `MagicShopScene.c:1471-1545` `PopupLayer::show(this, 0x82, 127.0)`.
func _on_menu(idx: int) -> void:
	# '연금술' 카드만 층 전환(원작 changeFloor(+1)) — 나머지는 팝업.
	if String((_items()[idx] as Dictionary)["key"]) == "alchemy_enter":
		_set_floor(1)
		return
	_open_feature(idx)

func _open_feature(idx: int) -> void:
	if is_instance_valid(_popup):
		return
	_tab = idx
	_popup = OrigPopup.open(self, String((_items()[idx] as Dictionary)["label"]))
	_popup.closed.connect(func():
		_tab = -1
		_say(_magic_talk()))
	_build_body(_popup)
	_say(_magic_talk())

## 기능 팝업 안에서 값이 바뀌었을 때 — 씬을 `_rebuild()` 하면 팝업이 통째로 날아간다.
func _refresh_feature() -> void:
	if not is_instance_valid(_popup):
		_rebuild()
		return
	_popup.clear_content()
	_build_body(_popup)
	if is_instance_valid(_money_root):
		_money_root.queue_free()
	_build_money(_vis())

## NPC 유리아 + 하단 대사창. 원작 `setTalker` + `BottomTextBox::setNpcManager`.
## 대사는 `data/npc_talk.json` — 1층 `UriaTalk1~8`, 지하 `AlchemyTalk1~8`,
## 기능 화면은 `MagicWelcome*`(젬/드링크/뽑기/코드) 안내문. **하드코딩하지 않는다.**
func _build_npc(vis: Vector2) -> void:
	_npc = NpcPortrait.create("yulia", _pick_emotion("yulia"))
	if _npc != null:
		_npc.z_index = 5
		add_child(_npc)
		_npc.position = Vector2(vis.x - 150.0, vis.y)
	_box = BottomTextBox.new()
	_box.max_width = vis.x - 300.0
	_box.z_index = 12
	add_child(_box)
	_box.clicked.connect(func(): _say(_magic_talk()))
	_say(_magic_talk())

## 원작 `MagicShopScene` 의 `setTalker` 호출부는 표정을 **1 또는 2** 만 넘긴다
## (welcome 은 리터럴 1, `onClickAlchemyItem` 은 `rand()` 로 1/2). 사용자 확정 2026-07-28.
const NPC_EMOTIONS := [1, 2]

func _pick_emotion(npc: String) -> int:
	var nums := AtlasUI.npc_emotions_for(npc, NPC_EMOTIONS)
	return int(nums[randi() % nums.size()]) if not nums.is_empty() else 1

func _npc_kr() -> String:
	var per = Data.npc_lines_doc.get("yulia", null)
	if per is Dictionary and per.has("name"):
		return String(per["name"])
	return "유리아"

## 화면 → 대사 묶음. 원본 문자열 테이블(`DV2/string/stringsData_KR.xml`) 대조로 확정(2026-07-28):
##   `AlchemyTalk1~8` 이 기능을 직접 말하고 있어 **2줄씩 4묶음**으로 갈라 뒀다
##   (`build_npc_talk.py` ALCHEMY_SPLIT). 혼성젬 **강화**와 소울젬에는 전용 대사가 없어
##   젬 안내문(`MagicWelcomeGem`)을 쓴다.
const MAGIC_TALK_KEY := {
	"gem": "magic.gem", "hybrid_up": "magic.gem",
	"alchemy": "magic.alchemy_make",      # AlchemyTalk1·2 — 혼성젬 제작
	"disassemble": "magic.disassemble",   # AlchemyTalk3·4 — 젬 분해
	"potion_make": "magic.potion_make",   # AlchemyTalk5·6 — 용액 제작
	"potion_shop": "magic.potion_shop",   # AlchemyTalk7·8 — 용액 상점
	"drink": "magic.drink",               # MagicWelcomeDrink — 드링크 강화
	"code": "magic.code",                 # MagicWelcomeCode — 카드 코드
	"slot": "magic.slot", "egg": "magic.egg",
}

func _magic_talk() -> String:
	var screen: Dictionary = Data.npc_talk.get("screen", {})
	var pool: Array = []
	if _tab >= 0:
		var key := String(MAGIC_TALK_KEY.get(String((_items()[_tab] as Dictionary)["key"]), ""))
		if key != "":
			pool = (screen.get(key, {}) as Dictionary).get("lines", [])
	if pool.is_empty():
		# 메뉴 화면 — 1층은 유리아 평상시(UriaTalk), 지하는 연금술사 대사(AlchemyTalk).
		if _floor == 1:
			pool = (screen.get("magic.alchemy_talk", {}) as Dictionary).get("lines", [])
		else:
			pool = Data.npc_talk.get("idle", {}).get("yulia", [])
	if pool.is_empty():
		pool = (screen.get("magic.welcome", {}) as Dictionary).get("lines", [])
	return String(pool[randi() % pool.size()]) if not pool.is_empty() else ""

## 대사 출력. 원작 `setTalker` 는 **대사와 표정이 한 묶음**이라 줄마다 얼굴이 바뀐다.
## `emo` > 0 이면 그 표정으로, 0 이면 현재 표정을 유지하되 **반응 표정이면 기본(1)으로 되돌린다**
## (원작 `setTextAgain` 의 `if (getEmotion() == 4) setTalker(..., 1, ...)` 분기).
## 반응 표정 = 원작이 결과 연출에 쓰는 값(유리아: `GemCraftLayer`·`SlotLayer`·`DrinkCraftLayer`
## ·`EggCombineLayer` 가 모두 **4**).
const REACTION_EMOTIONS := [4]

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

## 원작 `CodeLayer`(카드 코드) — 16자리 코드를 입력한다.
## 원작 프레임(`CodeLayer.c:2024-2110`): `9patch/pop_title_bg`(팝업이 이미 그림) ·
##   `common/backlight4`(뒤 후광) · `scene/magicshop/card`(카드 그림) · `CCEditBox` ×n · 확인 버튼.
##
## 원작의 검증은 서버가 한다(§2-1 CUT). 다만 **사용자가 이스터에그로 대응 기능을 넣을 예정**이라
## (확정 2026-07-28) 입력 UI 는 실제로 동작하게 만들고, 판정은 아래 `_redeem_code()` 한 곳에
## 모아 뒀다 — 코드↔보상 표를 넣을 자리다.
func _body_code(pop: OrigPopup) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var back := AtlasUI.spr("common_ui", "common_backlight4", Design.ASSET_SCALE * 0.62)
	if back != null:
		back.position = Vector2(W * 0.5, 210.0)
		back.modulate = Color(1, 1, 1, 0.55)
		pop.content.add_child(back)
		back.create_tween().set_loops().tween_property(back, "rotation", TAU, 24.0).as_relative()
	var card := _spr("card", Design.ASSET_SCALE * 1.15)
	if card != null:
		card.position = Vector2(W * 0.5, 210.0)
		pop.content.add_child(card)
	var head := _note("0과 1로 재구축된 세계의 비밀은 선형대수학에 있습니다.")
	head.position = Vector2(60.0, 92.0); head.size = Vector2(W - 120.0, 26.0)
	head.custom_minimum_size = Vector2(W - 120.0, 0)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pop.content.add_child(head)
	# 입력칸 — 원작은 4자리 CCEditBox 4개(=16자리 고정)다. 우리 표는 사용자가 채우는
	# 이스터에그라 길이가 제각각이므로(`docs/input/sheets/card_codes.csv`) **자릿수를 강제하지
	# 않는다**(사용자 확정 2026-07-30). 판정은 `CardCode.lookup` 이 정규화 후 해시로만 하므로
	# 길이에 아무 의미가 없다 — 종전의 `max_length = 19` 는 긴 코드를 **조용히 잘라** 내
	# 정상 코드도 인식 불가로 만들었다.
	var box := AtlasUI.nine("ninepatch_ui", "9patch_train_box3", Vector2(440.0, 52.0),
		Rect2(30, 16, 62, 8))
	if box != null:
		box.position = Vector2(W * 0.5 - 220.0, 318.0)
		pop.content.add_child(box)
	var edit := LineEdit.new()
	edit.placeholder_text = "코드"
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.max_length = 0           # 0 = 무제한
	edit.flat = true
	edit.add_theme_font_size_override("font_size", 22)
	edit.add_theme_color_override("font_color", Color(1, 0.97, 0.88))
	edit.add_theme_color_override("font_placeholder_color", Color(0.72, 0.66, 0.56))
	edit.size = Vector2(420.0, 44.0)
	edit.position = Vector2(W * 0.5 - 210.0, 322.0)
	pop.content.add_child(edit)
	var msg := Label.new()
	msg.add_theme_font_size_override("font_size", 17)
	msg.add_theme_color_override("font_color", Color(0.72, 0.16, 0.10))
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.size = Vector2(W - 120.0, 24.0); msg.position = Vector2(60.0, 378.0)
	pop.content.add_child(msg)
	pop.add_action_button("확인", func():
		var code := CardCode.normalize(edit.text)
		if code.is_empty():
			msg.text = "코드를 입력해 주세요."
			return
		var res := _redeem_code(code)
		if res.is_empty():
			msg.text = "사용할 수 없는 코드입니다."
			return
		msg.text = ""
		_toast(String(res.get("msg", "")) if String(res.get("msg", "")) != "" else "코드를 사용했습니다!")
		# 알 보상이 있으면 뽑기 알 개봉과 같은 공개 연출로 보여 준다(없으면 곧바로 갱신).
		_reveal_eggs("코드에 응답하여 %s의 알이 나타났습니다."),
		0, Vector2(220.0, 52.0))

## 카드 코드를 판정하고 **보상을 지급**한다. 못 쓰는 코드면 빈 사전.
##
## 원작 판정은 서버 몫이라 유실됐다(§2-1). 여기는 사용자가 채우는 이스터에그 표이고
## (확정 2026-07-28), 표는 `docs/input/sheets/card_codes.csv`(평문, gitignore)가 정본이다.
## 게임에 실리는 `data/card_codes.json` 은 **입력한 코드로만 풀리는 암호문**이라 빌드를 뜯어도
## 코드 목록·보상을 볼 수 없다(사용자 요청 2026-07-30, 구조는 `CardCode` 주석 참조).
##
## 사용 이력은 정규화된 코드가 아니라 **조회 해시**로 남긴다 — 세이브에도 평문을 남기지 않는다.
func _redeem_code(code: String) -> Dictionary:
	var res := CardCode.lookup(code, Data.card_codes)
	if res.is_empty():
		return {}
	var mark := CardCode.used_key(code, Data.card_codes)
	var used: Array = UserDB.get_pmeta("used_card_codes", [])
	# 사용 횟수 제한 — 표의 `사용제한` 열(0=무제한 / N=N번까지). 옛 표에는 `once` 만 있다.
	var uses := int(res.get("uses", 1 if bool(res.get("once", true)) else 0))
	if uses > 0:
		var spent := 0
		for m in used:
			if String(m) == mark:
				spent += 1
		if spent >= uses:
			return {}                   # 정해진 횟수를 다 썼다
	_egg_reveal.clear()                 # 이번 코드가 준 알만 공개한다(지난 지급분 누수 방지)
	for r in res.get("rewards", []):
		_grant_card_reward(r)
	if uses > 0:
		# 쓸 때마다 한 칸씩 쌓는다 — 같은 해시가 몇 번 있는지가 곧 사용 횟수다.
		var arr: Array = (used as Array).duplicate()
		arr.append(mark)
		UserDB.set_pmeta("used_card_codes", arr)
	return res

## 코드 보상 1건 지급. 종류는 `build_card_codes.py` 의 CSV `보상종류` 열과 1:1이다.
##   item(k=아이템키) · gold · dia · egg(k=드래곤id) · dragon(k=드래곤id) · flag(k=해시된 키)
func _grant_card_reward(r: Dictionary) -> void:
	var n := maxi(1, int(r.get("n", 1)))
	match String(r.get("t", "")):
		"item":
			UserDB.add_item(String(r.get("k", "")), n)
		"gold":
			UserDB.add_currency("gold", n)
		"dia":
			UserDB.add_currency("diamond", n)
		"egg":
			# 뽑기 알과 같은 가상 인벤 키 — 가방에서 개봉한다([[dv2-gacha-egg-mechanic]]).
			UserDB.add_item("egg:%d" % int(r.get("k", 0)), n)
			# 알은 토스트로 흘리지 않고 뽑기 알 개봉과 **같은 공개 연출**을 준다(사용자 요청).
			for i in n:
				_egg_reveal.append({"did": int(r.get("k", 0)), "opts": {}})
		"dragon":
			for i in n:
				UserDB.add_dragon(int(r.get("k", 0)))
		"flag":
			# 해금 플래그 — 평문 이름은 빌드·세이브 어디에도 없다(해시 키만).
			UserDB.set_pmeta(String(r.get("k", "")), true)


## 알 획득 공개(`EggResultPopup`) — 뽑기 알 개봉(`cave.gd::_show_egg_result`)과 **같은 창**이다.
## 여러 개면 확인할 때마다 하나씩 이어서 보여 주고, 마지막이 닫히면 화면을 갱신한다.
## 알이 없으면 아무것도 하지 않고 곧바로 갱신한다(호출부가 분기하지 않게).
##
## `_egg_reveal` 한 칸 = `{"did": 드래곤id, "opts": {name/art_id/element}}`.
## opts 는 **마스터에 값이 없는 커스텀 종(600/700)** 용이다 — 이름·속성·그림을 재료에게서
## 물려받으므로(`Summon.plan` inherit) 소환이 채워 넣는다. 일반 종은 비워 두면 된다.
func _reveal_eggs(msg_fmt: String) -> void:
	if _egg_reveal.is_empty():
		_refresh_feature()
		return
	var e: Dictionary = _egg_reveal.pop_front()
	var did := int(e.get("did", 0))
	var opts: Dictionary = e.get("opts", {})
	# 문구에 들어갈 이름 — 이름표와 같은 순서로 떨어진다(빈 이름이면 "%s의" 가 뻥 뚫린다).
	var nm := String(opts.get("name", ""))
	if nm == "":
		var mn = Data.get_dragon(did).get("name")
		nm = String(mn) if typeof(mn) == TYPE_STRING and String(mn) != "" else "새로운 알"
	var pop := EggResultPopup.open(self, did, "", msg_fmt % nm, opts)
	pop.closed.connect(func(): _reveal_eggs(msg_fmt))

## 원작 `DrinkCraftLayer`(드링크 강화) — 물약에 **정기**를 넣어 다음 단계로 올린다.
## 근거: `MagicWelcomeDrink` "…정기를 사용하면 기본적인 자양강장제를 강화시킬 수 있어요."
## 원작 프레임(`docs/ref/audit/DrinkCraftLayer` 리터럴 + 디컴프 :1333-1390):
##   `scene/magicshop/drink_bg`(물약 칸) · `element_bg`(정기 칸) · `common/plus` ·
##   `egg_fail`(실패 표시) · `common/coin_small1` · `RoundedButton(270×56)`
##
## ⚠️ **강화 재료 개수·골드·성공률은 원작 서버 데이터라 유실**됐다(`data/` 어디에도 없다 —
##    `item_effects.json` 의 `drink` 는 효과만 담는다). 값을 지어내지 않으므로(HARD RULE 6)
##    경로만 보여 주고 실행은 막는다. 규칙이 확보되면 이 함수의 버튼부터 살린다.
func _body_drink_craft(pop: OrigPopup) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var S := Design.ASSET_SCALE
	var cy := 236.0
	# 물약 칸 — 보유한 가장 낮은 단계 물약을 올려 둔다(없으면 빈 칸).
	var have_key := ""
	for k in UserDB.inventory().keys():
		var kk := String(k)
		var it := Data.get_item(kk)
		if String(it.get("subcategory", "")) == "drink" and int(it.get("tier", 0)) in [1, 2] 				and UserDB.item_count(kk) > 0:
			have_key = kk
			break
	var dbg := _spr("drink_bg", S * 1.15)
	if dbg != null:
		dbg.position = Vector2(W * 0.5 - 150.0, cy)
		pop.content.add_child(dbg)
	if have_key != "":
		var ip := Data.item_icon_path(have_key)
		if ip != "" and ResourceLoader.exists(ip):
			var ic := Sprite2D.new()
			ic.texture = load(ip); ic.material = AtlasUI.pma()
			ic.position = Vector2(W * 0.5 - 150.0, cy); ic.scale = Vector2(0.6, 0.6)
			pop.content.add_child(ic)
	var plus := AtlasUI.spr("common_ui", "common_plus", S * 1.1)
	if plus != null:
		plus.position = Vector2(W * 0.5 - 40.0, cy)
		pop.content.add_child(plus)
	# 정기 칸(원작 `element_bg`)
	var ebg := _spr("element_bg", S * 1.15)
	if ebg != null:
		ebg.position = Vector2(W * 0.5 + 70.0, cy)
		pop.content.add_child(ebg)
	var ep := Data.item_icon_path("ele_fire")
	if ep != "" and ResourceLoader.exists(ep):
		var ei := Sprite2D.new()
		ei.texture = load(ep); ei.material = AtlasUI.pma()
		ei.position = Vector2(W * 0.5 + 70.0, cy); ei.scale = Vector2(0.5, 0.5)
		ei.modulate = Color(1, 1, 1, 0.65)
		pop.content.add_child(ei)
	var arrow := AtlasUI.spr("common_ui", "common_btn_arrow2", S)
	if arrow != null:
		arrow.position = Vector2(W * 0.5 + 175.0, cy)
		pop.content.add_child(arrow)
	# 결과 칸
	var rbg := _spr("drink_bg", S * 1.15)
	if rbg != null:
		rbg.position = Vector2(W * 0.5 + 275.0, cy)
		rbg.modulate = Color(1, 1, 1, 0.6)
		pop.content.add_child(rbg)
	var cap := Label.new()
	cap.text = "물약   +   정기   →   다음 단계"
	cap.add_theme_font_size_override("font_size", 19)
	cap.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.size = Vector2(W - 120.0, 26.0); cap.position = Vector2(60.0, cy + 90.0)
	pop.content.add_child(cap)
	var head := _note(
		(("보유 물약: %s" % Data.item_name(have_key)) if have_key != ""
			else "강화할 물약이 없습니다(1·2단계 물약이 필요합니다).")
		+ "
물약은 1→2→3단계로 오르고, 단계마다 효과가 5%p 씩 커집니다(data/item_effects.json).")
	head.position = Vector2(60.0, 90.0); head.size = Vector2(W - 120.0, 48.0)
	head.custom_minimum_size = Vector2(W - 120.0, 0)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pop.content.add_child(head)
	var warn := _note("⚠️ 강화 재료 개수·비용·성공률은 원작 서버 데이터라 유실 — 값을 지어내지 않아 실행은 막아 둡니다.")
	warn.position = Vector2(60.0, H - 118.0); warn.size = Vector2(W - 120.0, 40.0)
	warn.custom_minimum_size = Vector2(W - 120.0, 0)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pop.content.add_child(warn)
	var b := pop.add_action_button("강화", func(): _toast("강화 규칙이 유실되어 아직 못 해요."),
		0, Vector2(270.0, 56.0))
	b.modulate = Color(0.62, 0.62, 0.62)

## 재화바 — 원작 initWidget: `common/money_bg` 우상단 + `coin_small1`@(40,85) + `diamond_small1`@(40,45).
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
	for r in [["common_coin_small1", AtlasUI.comma(UserDB.gold()), 85.0],
			["common_diamond_small1", AtlasUI.comma(UserDB.diamond()), 45.0]]:
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

## 본문 패널 — 원작 list_bg 프레임을 목록 배경으로.
## 팝업 창 안쪽 목록 영역. 좌표는 **창 로컬 포인트**(OrigPopup.content 기준).
func _body_panel(pop: OrigPopup) -> VBoxContainer:
	var pw: float = pop.win_size.x - 80.0
	var ph: float = pop.win_size.y - 86.0 - 40.0
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40.0, 86.0); scroll.size = Vector2(pw, ph)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pop.content.add_child(scroll)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(pw - 20, 0); scroll.add_child(col)
	return col

func _row_bg(w: float, h: float) -> NinePatchRect:
	var np := NinePatchRect.new()
	var p := "res://assets/converted/%s/scene_magicshop_list_bg.tres" % DIR_UI
	if not ResourceLoader.exists(p):
		p = "res://assets/converted/common_ui/common_item_bg.tres"
	if not ResourceLoader.exists(p): return null
	np.texture = load(p)
	np.patch_margin_left = 24; np.patch_margin_right = 24
	np.patch_margin_top = 20; np.patch_margin_bottom = 20
	np.size = Vector2(w, h); np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return np

func _build_body(pop: OrigPopup) -> void:
	var items := _items()
	if _tab < 0 or _tab >= items.size():
		return
	match String((items[_tab] as Dictionary)["key"]):
		"gem": _body_gem(pop)                 # 원작 GemCraftLayer (강화·복구·용액)
		"hybrid_up": _body_hybrid_upgrade(pop)  # 원작 AlchemyLayer — 용액 투입·성공률
		"alchemy": _body_alchemy(pop)         # 원작 UpgradeGemLayer(1) — 혼성젬 제작
		"potion_make": _body_drink(pop)       # 원작 PotionLayer(1) — 용액 제작
		"drink": _body_drink_craft(pop)       # 원작 DrinkCraftLayer — 드링크(물약) 강화
		"potion_shop": _body_potion_shop(pop)
		"disassemble": _body_disassemble(pop)
		"soul": _body_soul(pop)          # 원작 UpgradeSoulGemLayer — 소울젬 승급/강화
		"egg": _body_egg(pop)
		"slot": _body_slot(pop)
		"trans": _body_trans(pop)
		"code": _body_code(pop)

# ── 연금술(AlchemyLayer): 혼성젬 제작 ──────────────────────────────────────
## 위키 gems.pdf §2.2: "제작에는 각 가루 모두 20개가 필요하며, 나오는 젬의 종류는 랜덤이다."
## 가루 = items.json 실재 아이템 att_powder(붉은)/def_powder(푸른)/hp_powder(노란).
const POWDERS := {"hp_powder": "노란 마법가루", "att_powder": "붉은 마법가루", "def_powder": "푸른 마법가루"}
const ALCHEMY_COST := 20     # 위키 §2.2 각 가루 20개

## 원작 `UpgradeGemLayer::create(1)` — 재료 3줄 + `common/plus` + 결과칸 + 골드 비용.
## 레퍼런스 `docs/ref/orig_image/shop/점술집_젬강화.pdf` [혼성젬 제작] 스샷과 같은 구성이다.
##
## 원작 값(재디컴프한 `UpgradeGemLayer::initMenu` type-1 분기):
##   · 재료칸 = `RoundedLayer(250, 95, 0x66000000)` **3개**, 세로 간격 95pt (y +95 / 0 / −95)
##     — `RoundedLayer` 는 프레임이 아니라 **색+라운드로 그리는 레이어**(create(w,h,argb,…))라
##       StyleBoxFlat 로 그리는 것이 원작과 같은 방식이다(`RoundedButton` 과 다르다 — 그쪽은 9patch).
##   · `common/plus` 로 재료 묶음과 결과를 잇는다
##   · 비용 = `common/coin_small1` + 금액, 실행은 `RoundedButton`
## 확률·비용 출처: 위키 gems.pdf §2.2("각 가루 20개, 종류는 랜덤").
const ALCHEMY_GOLD := 1000     # 레퍼런스 스샷의 제작 비용 표기

func _body_alchemy(pop: OrigPopup) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var have_all := true
	var y0 := 108.0
	var n := 0
	for k: String in POWDERS:
		var have := UserDB.item_count(k)
		var enough := have >= ALCHEMY_COST
		have_all = have_all and enough
		var row := Panel.new()
		row.size = Vector2(280.0, 90.0)
		row.position = Vector2(56.0, y0 + n * 100.0)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.40)          # RoundedLayer 0x66000000
		sb.corner_radius_top_left = 14; sb.corner_radius_top_right = 14
		sb.corner_radius_bottom_left = 14; sb.corner_radius_bottom_right = 14
		row.add_theme_stylebox_override("panel", sb)
		pop.content.add_child(row)
		var ip := Data.item_icon_path(k)
		if ip != "" and ResourceLoader.exists(ip):
			var ic := Sprite2D.new()
			ic.texture = load(ip); ic.material = AtlasUI.pma()
			ic.position = Vector2(50.0, 45.0); ic.scale = Vector2(0.52, 0.52)
			row.add_child(ic)
		var l := Label.new()
		l.text = String(POWDERS[k])
		l.add_theme_font_size_override("font_size", 19)
		l.add_theme_color_override("font_color", Color(1, 0.96, 0.86))
		l.position = Vector2(96.0, 16.0); l.size = Vector2(170.0, 26.0)
		row.add_child(l)
		var c := Label.new()
		c.text = "%s / %d" % [AtlasUI.comma(have), ALCHEMY_COST]
		c.add_theme_font_size_override("font_size", 21)
		c.add_theme_color_override("font_color", Color(0.62, 1.0, 0.66) if enough else Color(1.0, 0.46, 0.40))
		c.position = Vector2(96.0, 48.0); c.size = Vector2(170.0, 28.0)
		row.add_child(c)
		n += 1
	var plus := AtlasUI.spr("common_ui", "common_plus", Design.ASSET_SCALE * 1.2)
	if plus != null:
		plus.position = Vector2(376.0, y0 + 145.0)
		pop.content.add_child(plus)
	# 결과칸 — 확률 리본 + 결과 자리(제작 전에는 무엇이 나올지 모른다 = 원작도 비어 있다).
	# 리본 문구는 **실제 판정값**이다 — 종전엔 "혼성젬 확률 100%" 하드코딩이라
	# 샌즈의 눈물을 넣어도 아무 변화가 없었다(2026-07-31 수정).
	var rib := Label.new()
	rib.text = "샌즈의 젬 확률  %d%%" % Gem.sands_chance(Data.gems, _sands_bonus_pct())
	rib.add_theme_font_size_override("font_size", 18)
	rib.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	rib.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 결과칸 위에 얹는다. 오른쪽은 샌즈의 눈물 투입 칸 자리라 폭을 그만큼 줄였다.
	rib.position = Vector2(435.0, y0); rib.size = Vector2(180.0, 26.0)
	pop.content.add_child(rib)
	_alchemy_sands_slot(pop, y0)
	var box := Panel.new()
	box.size = Vector2(180.0, 210.0)
	box.position = Vector2(435.0, y0 + 40.0)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0, 0, 0, 0.28)
	bs.corner_radius_top_left = 14; bs.corner_radius_top_right = 14
	bs.corner_radius_bottom_left = 14; bs.corner_radius_bottom_right = 14
	box.add_theme_stylebox_override("panel", bs)
	pop.content.add_child(box)
	var bl := Label.new()
	bl.text = "혼성젬\n(무작위)"
	bl.add_theme_font_size_override("font_size", 20)
	bl.add_theme_color_override("font_color", Color(1, 0.96, 0.86))
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bl.size = box.size
	box.add_child(bl)
	# 비용 = coin_small1 + 금액. 원작은 실행 버튼 안에 함께 얹는다.
	var coin := AtlasUI.spr("common_ui", "common_coin_small1", Design.ASSET_SCALE)
	if coin != null:
		coin.position = Vector2(466.0, H - 52.0)
		pop.content.add_child(coin)
	var gl := Label.new()
	gl.text = AtlasUI.comma(ALCHEMY_GOLD)
	gl.add_theme_font_size_override("font_size", 21)
	gl.add_theme_color_override("font_color", Color(1, 1, 1) if UserDB.gold() >= ALCHEMY_GOLD
		else Color(1.0, 0.46, 0.40))
	gl.add_theme_color_override("font_outline_color", Color(0.16, 0.09, 0.03))
	gl.add_theme_constant_override("outline_size", 5)
	gl.position = Vector2(486.0, H - 66.0); gl.size = Vector2(140.0, 28.0)
	pop.content.add_child(gl)
	pop.add_action_button("제작", _craft_hybrid_gem, 0, Vector2(180.0, 50.0),
		Vector2(W * 0.5 + 170.0, H - 52.0))
	if not have_all:
		var w2 := _note("마법가루는 젬 분해·탐험 보상으로 모읍니다.")
		w2.position = Vector2(56.0, H - 52.0); w2.size = Vector2(380.0, 24.0)
		pop.content.add_child(w2)

## 제작에 넣을 **샌즈의 눈물** 아이템 키. ""=미투입. 창을 닫으면 사라지는 화면 상태다.
var _sands_key := ""

## 지금 고른 눈물의 보너스(%). 미투입이거나 다 써 버렸으면 0.
func _sands_bonus_pct() -> int:
	if _sands_key == "" or UserDB.item_count(_sands_key) <= 0:
		return 0
	return Gem.sands_bonus(_sands_key, Data.gems)


## 원작 `UpgradeGemLayer::initMenu` 의 **투입 슬롯**(UpgradeGemLayer.c:1054~1090):
##   `RoundedLayer((w−100)/4, (h−100)/4×1.25, 0x66000000)` 을 `CCMenuItemImageEx` 로 감싸
##   `(w/2 + 230, h/2)` 에 ×0.95 로 놓고, 그 안에 `alchemy/posion_bg`(tag 8000)와
##   라벨(tag 9000, maxWidth 120)을 겹친다. 위에는 `9patch/train_box3` 230×43 띠.
## 우리 팝업은 크기가 달라 좌표는 결과칸 오른쪽으로 옮기되 **구성은 원작 그대로**다.
## 클릭 = 미투입 → 10% → 20% → 미투입 순환(원작 `onClickItemMenu` 는 보유 목록 팝업이지만
##   우리 눈물은 2종뿐이라 순환이 같은 일을 더 적은 클릭으로 한다). # ASSUMPTION: 순환 방식
func _alchemy_sands_slot(pop: OrigPopup, y0: float) -> void:
	var tears: Array = (Data.gems.get("craft", {}) as Dictionary).get("sands_tear_items", [])
	if tears.is_empty():
		return
	# 팝업은 800×480 이고 재료 3줄이 56~336, 결과칸이 435~615 을 쓴다 → 그 오른쪽.
	# 원작은 `(w/2 + 230, h/2)` = (630, 240) 중심인데 우리 결과칸이 거기 있어 조금 더 오른쪽이다.
	var slot := Control.new()
	slot.position = Vector2(635.0, y0 + 40.0)
	slot.size = Vector2(150.0, 160.0)
	pop.content.add_child(slot)
	# 띠 — 원작 `9patch/train_box3` 230×43 anchor(0.5,0), 슬롯 위.
	var band := AtlasUI.nine("ninepatch_ui", "9patch_train_box3", Vector2(150.0, 34.0))
	if band:
		band.position = Vector2(0, -40.0)
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(band)
	var bl := Label.new()
	bl.text = "샌즈의 눈물"
	bl.add_theme_font_size_override("font_size", 17)
	bl.add_theme_color_override("font_color", Color(1, 0.96, 0.86))
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.position = Vector2(0, -36.0); bl.size = Vector2(150.0, 26.0)
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(bl)
	# 투입 칸 배경 — 원작 `alchemy/posion_bg`.
	# 47×88px 프레임 → ×0.9×(4/3) = 56×106pt. 중심 (75,62) 이면 9~115 를 쓴다.
	var pbg := AtlasUI.spr("magicshop_alchemy", "scene_magicshop_alchemy_posion_bg",
		Design.ASSET_SCALE * 0.9)
	if pbg:
		pbg.position = Vector2(75.0, 62.0)
		slot.add_child(pbg)
	# 고른 눈물의 아이콘 + 보유 수. 미투입이면 안내 문구.
	var cur := _sands_bonus_pct()
	if _sands_key != "" and cur > 0:
		var ip := Data.item_icon_path(_sands_key)
		if ip != "" and ResourceLoader.exists(ip):
			var ic := Sprite2D.new()
			ic.texture = load(ip); ic.material = AtlasUI.pma()
			ic.position = Vector2(75.0, 58.0); ic.scale = Vector2(0.5, 0.5)
			slot.add_child(ic)
	var sl := Label.new()
	sl.text = ("+%d%%  (%d개)" % [cur, UserDB.item_count(_sands_key)]) if cur > 0 else "넣지 않음"
	sl.add_theme_font_size_override("font_size", 16)
	sl.add_theme_color_override("font_color", Color(1, 0.96, 0.86) if cur > 0
		else Color(0.85, 0.80, 0.72))
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.position = Vector2(0, 120.0); sl.size = Vector2(150.0, 24.0)   # 병 아래(115) 밑
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(sl)
	var b := Button.new()
	b.flat = true
	b.size = Vector2(150.0, 148.0)
	b.tooltip_text = "혼성젬 제작에 넣으면 샌즈의 젬이 나올 확률이 오릅니다 (클릭해서 바꾸기)"
	b.pressed.connect(_cycle_sands)
	slot.add_child(b)


## 미투입 → 보유한 눈물 순서대로 → 다시 미투입. 안 가진 것은 건너뛴다.
func _cycle_sands() -> void:
	var tears: Array = (Data.gems.get("craft", {}) as Dictionary).get("sands_tear_items", [])
	var owned: Array = []
	for t in tears:
		var k := String((t as Dictionary).get("item", ""))
		if UserDB.item_count(k) > 0:
			owned.append(k)
	if owned.is_empty():
		_toast("샌즈의 눈물이 없습니다 (용액 상점에서 살 수 있어요)")
		return
	var i := owned.find(_sands_key)
	_sands_key = "" if i == owned.size() - 1 else String(owned[i + 1] if i >= 0 else owned[0])
	_refresh_feature()


func _craft_hybrid_gem() -> void:
	for k: String in POWDERS:
		if UserDB.item_count(k) < ALCHEMY_COST:
			_toast("마법가루가 모자라요."); return
	var bonus := _sands_bonus_pct()          # 투입 전에 확정(차감하면서 0이 되면 안 된다)
	if not UserDB.spend("gold", ALCHEMY_GOLD):
		_toast("골드가 부족합니다"); return
	for k: String in POWDERS:
		UserDB.use_item(k, ALCHEMY_COST)
	# 결과 = 혼성젬 중 1종, 최소 티어(위키: "가장 초기의 작은 젬이 나온다").
	# 샌즈의 눈물을 넣었으면 샌즈의 젬 확률이 그만큼 오른다 — 판정은 logic 층(§8.2).
	if bonus > 0:
		UserDB.use_item(_sands_key, 1)
	var r := RandomNumberGenerator.new(); r.randomize()
	var got := Gem.craft_hybrid(Data.gems, bonus, r)
	if got == "":
		_toast("젬 데이터가 비어 있습니다"); return
	# 🔴버그수정(2026-07-27): 가루 60개를 먹고 **pmeta 문자열 + 토스트만** 남기고 젬을 주지 않았다.
	#   이제 실제 젬 아이템을 인벤에 넣는다(가상 키 `gem:<이름>:<티어>`, 위키 §2.2 "가장 초기의 젬").
	UserDB.add_item(Gem.item_key(got, 0), 1)
	if bonus > 0 and UserDB.item_count(_sands_key) <= 0:
		_sands_key = ""                      # 마지막 하나를 썼으면 칸을 비운다
	_toast("%s 을(를) 제작했습니다! (가방 젬 탭)" % got)
	_refresh_feature()

# ── 젬 강화/승급/복구/연금술 (GemCraftLayer · UpgradeGemLayer · UpgradeSoulGemLayer · AlchemyLayer) ──
## 원작은 이 레이어들이 **점술집 소유**다(동굴 젬 칸은 장착/해제만 한다).
## 우리는 젬을 드래곤에 장착해 두므로 활성 드래곤의 장착 젬을 대상으로 한다.
## 로직은 전부 `scripts/systems/gem.gd`(§8.2) — 이 화면은 표시·입력만 한다.
##
## 원작 자산: `scene/magicshop/gem_bg`(젬 슬롯 판) · `gem_fail`(실패) · `btn_gemrepair`(복구) ·
##   `alchemy/alchemy_point_1~5`(용액 투입 칸) · `alchemy/alchemy_success`.
func _body_gem(pop: OrigPopup) -> void:
	var col := _body_panel(pop)
	var uid := UserDB.active_uid()
	var d := UserDB.get_dragon(uid)
	if d.is_empty():
		col.add_child(_note("활성 드래곤이 없습니다.")); return
	# 원작 지하 tag1 = `GemCraftLayer`. 소울젬 전용 항목(`UpgradeSoulGemLayer`)은 후기 추가분이라
	# 우리 메뉴에 없으므로(§ITEMS) 여기서 일반·혼성·소울젬을 **모두** 다룬다.
	col.add_child(_note("장착 젬을 강화·승급합니다. 실패하면 파손되고 다이아로 복구합니다.\n(원작 GemCraftLayer — 성공률은 연금 용액으로 올립니다)"))
	var gf: Dictionary = d.get("gems", {})
	var en := Gem.entries(gf)
	if Gem.slots(gf).is_empty():
		col.add_child(_note("장착된 젬이 없습니다. 동굴 하단 젬 칸을 눌러 먼저 장착하세요.")); return
	var bw := _body_w(pop)
	var shown := 0
	for i in Gem.SLOTS:
		if en[i] == null: continue
		var e: Dictionary = en[i]
		var nm := String(e["name"])
		var tier := int(e["tier"])
		shown += 1
		var maxt := Gem.max_tier(nm, Data.gems)
		var broken := Gem.is_broken(e)
		var row := Control.new(); row.custom_minimum_size = Vector2(0, 96)
		var bgn := _row_bg(bw, 96)
		if bgn: row.add_child(bgn)
		# 젬 슬롯 판(원작 `gem_bg`) + 티어별 젬 아이콘. 파손이면 `gem_fail` 을 덮는다.
		var slot_bg := _spr("gem_bg", Design.ASSET_SCALE * 0.45)
		if slot_bg: slot_bg.position = Vector2(40, 48); row.add_child(slot_bg)
		var gi := Icons.rect(Icons.gem_texture(
			String(Gem.gem_def(nm, Data.gems).get("code", "")), tier), 40.0)
		if gi: gi.position = Vector2(20, 28); row.add_child(gi)
		if broken:
			var fx := _spr("gem_fail", Design.ASSET_SCALE * 0.45)
			if fx: fx.position = Vector2(40, 48); row.add_child(fx)
		var l := Label.new()
		l.text = "%s  [%s]  (%d/%d)" % [Gem.display_name(nm, tier, Data.gems),
			Gem.shape_label(nm, tier, Data.gems), tier + 1, maxt + 1]
		l.add_theme_font_size_override("font_size", 17)
		l.add_theme_color_override("font_color", Color(1, 0.65, 0.6) if broken else Color(0.95, 0.92, 1.0))
		l.position = Vector2(76, 12); row.add_child(l)
		var sub := Label.new()
		sub.add_theme_font_size_override("font_size", 15)
		sub.position = Vector2(76, 42)
		var pmax := int(Data.gems.get("upgrade", {}).get("potion_max_per_try", 5))
		if broken:
			sub.text = "파손 — 효과가 적용되지 않습니다"
			sub.add_theme_color_override("font_color", Color(1, 0.5, 0.45))
		elif tier < maxt:
			# 원작 AlchemyMsg8~10: 연금술 포인트 / 남은 용액 투입 수 / 성공률.
			sub.text = "성공률 %d%%   연금포인트 %d   용액 %d/%d회" % [
				Gem.success_chance(gf, i, Data.gems), int(e.get("points", 0)),
				int(e.get("potions", 0)), pmax]
			sub.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
			_point_gauge(row, int(e.get("potions", 0)), bw)
		else:
			sub.text = "최대 단계"
			sub.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		row.add_child(sub)
		var idx := i
		var bx := bw - 180.0
		if broken:
			# 원작 `btn_gemrepair` + 위키 §2.2 복구 다이아표.
			var dia := Gem.repair_cost(tier, Data.gems)
			var rb := _frame_button(row, "   복구  %d" % dia, Vector2(bx, 28), Vector2(168, 40),
				func(): _repair(uid, idx, dia), 1, UserDB.diamond() < dia)
			# 원작 복구 버튼 아이콘 `scene/magicshop/btn_gemrepair`.
			var ri := _spr("btn_gemrepair", Design.ASSET_SCALE * 0.32)
			if ri:
				ri.position = Vector2(22, 20)
				rb.add_child(ri)
		elif tier >= maxt:
			var to_code := String(Gem.gem_def(nm, Data.gems).get("promote_to", ""))
			if to_code != "":
				var gold := int(Data.gems.get("upgrade", {}).get("promote", {}).get("gold", 1000000))
				_frame_button(row, "승급 %d만G" % int(gold / 10000.0), Vector2(bx, 28),
					Vector2(168, 40), func(): _promote(uid, idx, gold), 0, UserDB.gold() < gold)
		else:
			var cost := _gem_cost(nm, tier)
			_frame_button(row, "강화 %dG" % cost, Vector2(bx, 8), Vector2(168, 38),
				func(): _try_upgrade(uid, idx, cost), 0, UserDB.gold() < cost)
			_frame_button(row, "용액 투입", Vector2(bx, 52), Vector2(168, 36),
				func(): _open_potion_use(uid, idx), 2, int(e.get("potions", 0)) >= pmax)
		col.add_child(row)
	if shown == 0:
		col.add_child(_note("강화할 젬이 없습니다."))

## 본문 패널 안쪽 폭(행 배경/버튼 정렬 기준).
func _body_w(pop: OrigPopup) -> float:
	return pop.win_size.x - 80.0 - 20.0

## 용액 투입 칸 표시 — 원작 `alchemy/alchemy_point_1~5`(투입한 횟수만큼 채워진 프레임).
func _point_gauge(row: Control, used: int, bw: float) -> void:
	if used <= 0:
		return
	var g := _spr("alchemy_point_%d" % clampi(used, 1, 5), Design.ASSET_SCALE * 0.5, "al")
	if g:
		g.position = Vector2(bw - 280.0, 70.0)
		row.add_child(g)

## 강화 시도 — 성공/실패(파손)를 원작 문구로 알린다(`MagicGemSucces`/`MagicGemFail`).
func _try_upgrade(uid: int, slot: int, cost: int) -> void:
	var gf: Dictionary = UserDB.get_dragon(uid).get("gems", {})
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var res: Dictionary = Gem.roll_upgrade(gf, slot, Data.gems, rng)
	if res.is_empty():
		_toast("강화할 수 없습니다"); return
	if not UserDB.spend("gold", cost):
		_toast("골드가 부족하네요"); return          # 원작 <MagicErrorMsg2>
	# 결과 연출은 화면을 다시 그리기 **전에** 만들어야 이전 상태(before)를 읽을 수 있다.
	var before := ""
	var en0 := Gem.entries(gf)
	if en0[slot] != null:
		before = _gem_result_line(en0[slot])
	UserDB.set_dragon_field(uid, "gems", res["field"])
	var after := ""
	var en1 := Gem.entries(UserDB.get_dragon(uid).get("gems", {}))
	if en1[slot] != null:
		after = _gem_result_line(en1[slot])
	var ok := bool(res.get("ok", false))
	# 원작 `GemCraftLayer` 는 결과 대사에 표정 4 를 쓴다(실패 반응) — 다음 대사에서 1 로 돌아온다.
	if ok:
		_toast("축하드려요! 강화에 성공했습니다!")     # <MagicGemSucces>
	else:
		_toast("아쉽게 실패했네요. 다음을 기약하죠. (성공률 %d%% — 파손)" % int(res.get("chance", 0)), 4)
	_show_upgrade_result(ok, before, after, en1[slot])
	_refresh_feature()

## 결과 연출 라벨 한 줄 — 레퍼런스의 `체력의 젬+104 [방어+11]` 형식.
func _gem_result_line(e) -> String:
	if e == null:
		return ""
	var d: Dictionary = e
	var nm := String(d["name"])
	var tier := int(d["tier"])
	return "%s  %s" % [Gem.display_name(nm, tier, Data.gems),
		Gem.effect_text(nm, tier, Data.gems)]

## 원작 강화 결과 연출 — 레퍼런스 `docs/ref/orig_image/shop/점술집_젬강화.pdf` 의 SUCCESS 화면.
##   검은 화면 + 회전하는 별빛(`common/backlight3`) + 워드아트(`scene/magicshop/success_en`
##   / 실패는 `fail_en`) + 젬 아이콘 + 하단 `이전 ▶ 이후` 띠(`9patch/chat_black` + `common/btn_arrow2`).
## 아무 곳이나 누르면 닫힌다.
func _show_upgrade_result(ok: bool, before: String, after: String, entry) -> void:
	var vis := _vis()
	var lay := Control.new()
	lay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lay.mouse_filter = Control.MOUSE_FILTER_STOP
	lay.z_index = 80
	add_child(lay)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1.0)   # 레퍼런스 연출은 완전한 검은 화면이다
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lay.add_child(bg)
	var cx := vis.x * 0.5
	var back := AtlasUI.spr("common_ui", "common_backlight3", Design.ASSET_SCALE * 1.1)
	if back != null:
		back.position = Vector2(cx, vis.y * 0.5)
		back.modulate = Color(1, 0.92, 0.35, 0.9) if ok else Color(0.6, 0.6, 0.66, 0.8)
		lay.add_child(back)
		back.create_tween().set_loops().tween_property(back, "rotation", TAU, 18.0).as_relative()
	var word := AtlasUI.spr("magicshop_ui",
		"scene_magicshop_success_en" if ok else "scene_magicshop_fail_en", Design.ASSET_SCALE * 2.4)
	if word != null:
		word.position = Vector2(cx, vis.y * 0.26)
		lay.add_child(word)
	if entry != null:
		var e: Dictionary = entry
		var gi := Icons.rect(Icons.gem_texture(
			String(Gem.gem_def(String(e["name"]), Data.gems).get("code", "")), int(e["tier"])), 84.0)
		if gi != null:
			gi.position = Vector2(cx - 42.0, vis.y * 0.5 - 42.0)
			lay.add_child(gi)
	# 하단 `이전 ▶ 이후` 띠
	var pw := 300.0
	var y := vis.y - 130.0
	var xs := [cx - pw - 30.0, cx + 30.0]
	var txt := [before, after]
	for i in 2:
		if String(txt[i]) == "":
			continue
		var pill := AtlasUI.nine("ninepatch_ui", "9patch_chat_black", Vector2(pw, 44.0), Rect2(9, 9, 9, 9))
		if pill != null:
			pill.position = Vector2(float(xs[i]), y)
			lay.add_child(pill)
		var l := Label.new()
		l.text = String(txt[i])
		l.add_theme_font_size_override("font_size", 17)
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.clip_text = true
		l.position = Vector2(float(xs[i]), y); l.size = Vector2(pw, 44.0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lay.add_child(l)
	if before != "" and after != "":
		var ar := AtlasUI.spr("common_ui", "common_btn_arrow2", Design.ASSET_SCALE)
		if ar != null:
			ar.position = Vector2(cx, y + 22.0)
			lay.add_child(ar)
	var hit := Button.new()
	hit.flat = true
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit.pressed.connect(func(): lay.queue_free())
	lay.add_child(hit)

func _repair(uid: int, slot: int, dia: int) -> void:
	if not UserDB.spend("diamond", dia):
		_toast("다이아가 부족합니다"); return
	var next: Dictionary = Gem.repair(UserDB.get_dragon(uid).get("gems", {}), slot)
	if next.is_empty():
		_toast("복구할 수 없습니다"); return
	UserDB.set_dragon_field(uid, "gems", next)
	_toast("젬을 복구했습니다"); _refresh_feature()

## 용액 투입 팝업 — 원작 `AlchemyLayer::onClickPotion`(<AlchemyMsg7>).
func _open_potion_use(uid: int, slot: int) -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 40; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: layer.queue_free())
	layer.add_child(dim)
	var BW := 540.0
	var BH := 420.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190
	win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH)
	win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	layer.add_child(win)
	var gf: Dictionary = UserDB.get_dragon(uid).get("gems", {})
	var t := Label.new()
	t.text = "연금술 — 용액 투입 (성공률 %d%%)" % Gem.success_chance(gf, slot, Data.gems)
	t.add_theme_font_size_override("font_size", 21)
	t.add_theme_color_override("font_color", Color(1, 0.95, 0.75))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size = Vector2(BW, 40); t.position = Vector2(0, 26); win.add_child(t)
	var hint := Label.new()
	hint.text = "100포인트가 넘으면 초기화됩니다 (원작 <AlchemyMsg11>)"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.75, 0.72, 0.8))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size = Vector2(BW, 22); hint.position = Vector2(0, 62); win.add_child(hint)
	var col := VBoxContainer.new()
	col.position = Vector2(56, 92); col.size = Vector2(BW - 112, BH - 156)
	col.add_theme_constant_override("separation", 6)
	win.add_child(col)
	var any := false
	for p0 in (Data.gems.get("upgrade", {}) as Dictionary).get("potions", []):
		var p: Dictionary = p0
		var nm := String(p.get("name", ""))
		var ik := String(POTION_ITEM.get(nm, ""))
		var have := UserDB.item_count(ik) if ik != "" else 0
		if have <= 0:
			continue
		any = true
		var gain := "성공률 %d%% 고정" % int(p.get("success_pct", 0))
		if p.has("points"):
			gain = "+%d~%d 포인트" % [int((p["points"] as Array)[0]), int((p["points"] as Array)[1])]
		var b := Button.new()
		b.text = "%s   %s   ×%d" % [nm, gain, have]
		b.custom_minimum_size = Vector2(0, 42)
		var pp := p
		var pk := ik
		b.pressed.connect(func():
			var rng2 := RandomNumberGenerator.new(); rng2.randomize()
			var res: Dictionary = Gem.add_potion(
				UserDB.get_dragon(uid).get("gems", {}), slot, pp, Data.gems, rng2)
			if res.is_empty():
				_toast("투입할 수 없습니다"); return
			UserDB.use_item(pk, 1)
			UserDB.set_dragon_field(uid, "gems", res["field"])
			layer.queue_free()
			if bool(res.get("reset", false)):
				_toast("연금포인트가 100을 넘어 초기화됐습니다 (+%d)" % int(res["gained"]))
			else:
				_toast("연금포인트 +%d → %d" % [int(res["gained"]), int(res["points"])])
			_refresh_feature())
		col.add_child(b)
	if not any:
		col.add_child(_note("보유한 용액이 없습니다. '용액 제작'에서 만드세요."))
	var cb := Button.new(); cb.text = "닫기"; cb.size = Vector2(120, 40)
	cb.position = Vector2((BW - 120) * 0.5, BH - 56)
	cb.pressed.connect(func(): layer.queue_free()); win.add_child(cb)

# ── 혼성젬 강화(AlchemyLayer) ──────────────────────────────────────────────
## ⚠️ 클래스 확정 근거(자산 이름으로 추측 금지 — §3): `AlchemyLayer` 가 쓰는
##   `alchemy/box_bg` 는 **가마솥 방 배경 그림**(323×375)이고 `box_cover` 는 그 위에 씌우는
##   **둥근 모서리 마스크**다(변환본 PNG 육안 확인). 레퍼런스 [혼성젬 강화] 스샷 좌측의
##   방 그림 패널이 정확히 이 둘이다 ⇒ 혼성젬 강화 = `AlchemyLayer`.
##   (`UpgradeGemLayer` 는 재료 3줄 + 골드 = **혼성젬 제작** 쪽이다 — `_body_alchemy` 참조.)
##
## 레퍼런스 `docs/ref/orig_image/shop/점술집_젬강화.pdf` [혼성젬 강화] 스샷 1:1.
##   좌 = 방 배경 패널(`alchemy/box_bg`) + "투입된 혼성젬" + 선택한 젬 아이콘
##   🟡 `box_cover`(둥근 모서리 마스크)는 Godot 에서 같은 방식으로 못 씌워 생략 — 사각 패널이다.
##   우 = 보유 용액 목록(스크롤) — 용액 아이콘판 + 이름 + POINT 리본 + 보유 개수
##   하 = 정보 패널(연금술 포인트 게이지 / 남은 용액 투입 수 / 성공률) + 안내 한 줄
##   버튼 2개 = [혼성젬 선택](btn) · [강화](btn3)
##
## 원작 프레임(디컴프 `UpgradeGemLayer::initMenu` 재추출분 — 이전엔 [skip>8000] 로 잘려 있었다):
##   `alchemy/posion_bg` · `9patch/train_box3`(230×43, 성공률 띠) · `common/diamond_big` ·
##   `scene/magicshop/gauge` / `gauge_bg`
## ⚠️ `scene/magicshop/gauge(_bg)` 는 추출 아틀라스에 없다(§10 표) → 같은 규격의
##    **`common/gauge` / `common/gauge_bg`(294×14)** 로 대체한다.
##
## ASSUMPTION: 좌우 칼럼의 정확한 좌표는 디컴프 값이 레이어 자체 크기 기준이라 우리 창(800×480)에
##   그대로 못 얹는다. 비율은 레퍼런스 스샷 실측을 따랐다.
func _body_hybrid_upgrade(pop: OrigPopup) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var uid := UserDB.active_uid()
	var d := UserDB.get_dragon(uid)
	var gf: Dictionary = d.get("gems", {})
	var en := Gem.entries(gf)
	# 대상 = 장착 젬 중 혼성(hybrid). 없으면 안내만.
	var slot := -1
	for i in Gem.SLOTS:
		if en[i] == null:
			continue
		if String(Gem.gem_def(String(en[i]["name"]), Data.gems).get("category", "")) == "hybrid":
			slot = i
			break
	# ── 좌: 투입 슬롯 ────────────────────────────────────────────────
	var slot_cx := 210.0
	var cap := Label.new()
	cap.text = "투입된 혼성젬"
	cap.add_theme_font_size_override("font_size", 20)
	cap.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.size = Vector2(300.0, 26.0); cap.position = Vector2(slot_cx - 150.0, 96.0)
	pop.content.add_child(cap)
	var panel := Control.new()
	panel.size = Vector2(300.0, 300.0)
	panel.position = Vector2(slot_cx - 150.0, 122.0)
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pop.content.add_child(panel)
	var pbg := AtlasUI.spr("magicshop_alchemy", "scene_magicshop_alchemy_box_bg",
		Design.ASSET_SCALE * 0.70)
	if pbg != null:
		pbg.position = panel.size * 0.5
		panel.add_child(pbg)
	# 투입 슬롯(원작 `alchemy/posion_bg`) — 방 배경 위에 놓인다.
	var pslot := AtlasUI.spr("magicshop_alchemy", "scene_magicshop_alchemy_posion_bg",
		Design.ASSET_SCALE * 1.2)
	if pslot != null:
		pslot.position = Vector2(slot_cx, 258.0)
		pop.content.add_child(pslot)
	if slot >= 0:
		var e: Dictionary = en[slot]
		var gi := Icons.rect(Icons.gem_texture(
			String(Gem.gem_def(String(e["name"]), Data.gems).get("code", "")), int(e["tier"])), 72.0)
		if gi != null:
			gi.position = Vector2(slot_cx - 36.0, 222.0)
			pop.content.add_child(gi)
		var nl := Label.new()
		nl.text = Gem.display_name(String(e["name"]), int(e["tier"]), Data.gems)
		nl.add_theme_font_size_override("font_size", 19)
		nl.add_theme_color_override("font_color", Color(1, 0.96, 0.82))
		nl.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.02))
		nl.add_theme_constant_override("outline_size", 5)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.size = Vector2(300.0, 26.0); nl.position = Vector2(slot_cx - 150.0, 330.0)
		pop.content.add_child(nl)
	else:
		var nl2 := Label.new()
		nl2.text = "혼성젬을 장착한 뒤\n다시 와 주세요."
		nl2.add_theme_font_size_override("font_size", 17)
		nl2.add_theme_color_override("font_color", Color(1, 0.94, 0.80))
		nl2.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.02))
		nl2.add_theme_constant_override("outline_size", 5)
		nl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl2.size = Vector2(300.0, 56.0); nl2.position = Vector2(slot_cx - 150.0, 326.0)
		pop.content.add_child(nl2)
	# ── 우: 보유 용액 목록 ────────────────────────────────────────────
	var lx := 380.0
	var lw := W - lx - 40.0
	var list := ScrollContainer.new()
	list.position = Vector2(lx, 88.0)
	list.size = Vector2(lw, 196.0)
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.clip_contents = true
	list.follow_focus = false
	pop.content.add_child(list)
	list.ready.connect(func(): list.scroll_vertical = 0)
	var holder := Control.new()
	list.add_child(holder)
	var owned: Array = []
	for p0 in (Data.gems.get("upgrade", {}) as Dictionary).get("potions", []):
		var p: Dictionary = p0
		var ik := String(POTION_ITEM.get(String(p.get("name", "")), ""))
		if ik != "" and UserDB.item_count(ik) > 0:
			owned.append(p)
	holder.custom_minimum_size = Vector2(lw - 16.0, maxf(1.0, owned.size() * 70.0))
	for i in owned.size():
		var p: Dictionary = owned[i]
		var nm := String(p.get("name", ""))
		var ik := String(POTION_ITEM[nm])
		var row := Control.new()
		row.size = Vector2(lw - 16.0, 62.0)
		row.position = Vector2(0, i * 70.0)
		holder.add_child(row)
		var bgn := AtlasUI.nine("magicshop_ui", "scene_magicshop_list_bg", row.size)
		if bgn != null:
			row.add_child(bgn)
		var ip := Data.item_icon_path(ik)
		if ip != "" and ResourceLoader.exists(ip):
			var ic := Sprite2D.new()
			ic.texture = load(ip); ic.material = AtlasUI.pma()
			ic.position = Vector2(36.0, 31.0); ic.scale = Vector2(0.46, 0.46)
			row.add_child(ic)
		var l := Label.new()
		l.text = nm
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		l.position = Vector2(70.0, 6.0); l.size = Vector2(160.0, 24.0)
		row.add_child(l)
		var badge := AtlasUI.spr("magicshop_alchemy",
			"scene_magicshop_alchemy_alchemy_point_%d" % clampi(i + 1, 1, 5), Design.ASSET_SCALE * 0.85)
		var bsz := AtlasUI.size_pt("magicshop_alchemy", "scene_magicshop_alchemy_alchemy_point_1") * 0.85
		if badge != null:
			badge.position = Vector2(70.0 + bsz.x * 0.5, 42.0)
			row.add_child(badge)
		var pts: Array = p.get("points", [0, 0])
		var pl := Label.new()
		pl.text = ("%d ~ %d" % [int(pts[0]), int(pts[1])]) if p.has("points") \
			else "성공률 %d%%" % int(p.get("success_pct", 0))
		pl.add_theme_font_size_override("font_size", 15)
		pl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		pl.position = Vector2(74.0 + bsz.x, 32.0); pl.size = Vector2(110.0, 22.0)
		row.add_child(pl)
		var cl := Label.new()
		cl.text = "%d개" % UserDB.item_count(ik)
		cl.add_theme_font_size_override("font_size", 19)
		cl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cl.position = Vector2(row.size.x - 110.0, 20.0); cl.size = Vector2(90.0, 24.0)
		row.add_child(cl)
		var b := Button.new(); b.flat = true; b.size = row.size
		b.disabled = slot < 0
		var pp := p
		var pk := ik
		var sl := slot
		b.pressed.connect(func(): _pour_potion(uid, sl, pp, pk))
		row.add_child(b)
	if owned.is_empty():
		var nn := _note("보유한 용액이 없습니다.\n'용액 제작'에서 만드세요.")
		nn.position = Vector2(10, 10)
		holder.add_child(nn)
	# ── 하: 정보 패널(포인트 게이지 / 남은 투입 수 / 성공률) ─────────────
	var info := AtlasUI.nine("ninepatch_ui", "9patch_chat_black", Vector2(lw, 104.0), Rect2(9, 9, 9, 9))
	if info != null:
		info.position = Vector2(lx, 292.0)
		pop.content.add_child(info)
	# 포인트·투입 횟수는 젬 엔트리에 들어 있다(Gem.add_potion 이 세는 값 그대로).
	var pnt := int((en[slot] as Dictionary).get("points", 0)) if slot >= 0 else 0
	var used := int((en[slot] as Dictionary).get("potions", 0)) if slot >= 0 else 0
	var pmax := int((Data.gems.get("upgrade", {}) as Dictionary).get("potion_max_per_try", 5))
	var rate := Gem.success_chance(gf, slot, Data.gems) if slot >= 0 else 0
	var gsz := AtlasUI.size_pt("common_ui", "common_gauge")
	var gbg := AtlasUI.spr("common_ui", "common_gauge_bg", Design.ASSET_SCALE)
	if gbg != null:
		gbg.centered = false
		gbg.position = Vector2(lx + 16.0, 308.0)
		pop.content.add_child(gbg)
	var gfg := AtlasUI.spr("common_ui", "common_gauge", Design.ASSET_SCALE)
	if gfg != null:
		gfg.centered = false
		gfg.position = Vector2(lx + 16.0, 308.0)
		gfg.region_enabled = true
		var t := gfg.texture
		gfg.region_rect = Rect2(0, 0, t.get_width() * clampf(pnt / 100.0, 0.0, 1.0), t.get_height())
		pop.content.add_child(gfg)
	var rows := [["연금술 포인트", "%d /100" % pnt], ["남은 용액 투입 수", "%d회" % maxi(0, pmax - used)],
		["성공률", "%d%%" % rate]]
	for i in rows.size():
		var kl := Label.new()
		kl.text = String((rows[i] as Array)[0])
		kl.add_theme_font_size_override("font_size", 17)
		kl.add_theme_color_override("font_color", Color(0.98, 0.92, 0.62))
		kl.position = Vector2(lx + 16.0, 332.0 + i * 22.0); kl.size = Vector2(200.0, 22.0)
		pop.content.add_child(kl)
		var vl := Label.new()
		vl.text = String((rows[i] as Array)[1])
		vl.add_theme_font_size_override("font_size", 17)
		vl.add_theme_color_override("font_color", Color(1, 1, 1))
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vl.position = Vector2(lx + lw - 190.0, 332.0 + i * 22.0); vl.size = Vector2(174.0, 22.0)
		pop.content.add_child(vl)
	var warn := Label.new()
	warn.text = "100포인트가 넘으면 성공률이 하락합니다."   # 원작 <AlchemyMsg11>
	warn.add_theme_font_size_override("font_size", 15)
	warn.add_theme_color_override("font_color", Color(0.36, 0.22, 0.10))
	warn.position = Vector2(lx, 402.0); warn.size = Vector2(lw, 22.0)
	pop.content.add_child(warn)
	# ── 버튼 2개 ────────────────────────────────────────────────────
	pop.add_action_button("혼성젬 선택", func(): _toast("동굴 하단 젬 칸에서 혼성젬을 장착하세요."),
		2, Vector2(190.0, 50.0), Vector2(lx + 100.0, H - 30.0))
	pop.add_action_button("강화", func(): _hybrid_upgrade(uid, slot),
		0, Vector2(190.0, 50.0), Vector2(lx + 300.0, H - 30.0))

## 용액 1개 투입 — 로직은 전부 `Gem`(§8.2). 화면은 결과 문구만 낸다.
func _pour_potion(uid: int, slot: int, potion: Dictionary, item_key: String) -> void:
	if slot < 0:
		return
	var rng2 := RandomNumberGenerator.new(); rng2.randomize()
	var res: Dictionary = Gem.add_potion(
		UserDB.get_dragon(uid).get("gems", {}), slot, potion, Data.gems, rng2)
	if res.is_empty():
		_toast("더 투입할 수 없습니다"); return
	UserDB.use_item(item_key, 1)
	UserDB.set_dragon_field(uid, "gems", res["field"])
	if bool(res.get("reset", false)):
		_toast("연금포인트가 100을 넘어 초기화됐습니다 (+%d)" % int(res["gained"]))
	else:
		_toast("연금포인트 +%d → %d" % [int(res["gained"]), int(res["points"])])
	_refresh_feature()

func _hybrid_upgrade(uid: int, slot: int) -> void:
	if slot < 0:
		_toast("강화할 혼성젬이 없어요."); return
	var gf: Dictionary = UserDB.get_dragon(uid).get("gems", {})
	var en := Gem.entries(gf)
	if en[slot] == null:
		return
	var e: Dictionary = en[slot]
	_try_upgrade(uid, slot, _gem_cost(String(e["name"]), int(e["tier"])))

# ── 젬 분해 / 용액 상점 / 알 조합 / 뽑기 ────────────────────────────────────
## ⚠️ `tier` 는 프로젝트 공통 규약대로 **0-base**(1강 = 0)다. 위키 표는 강 번호(1~18)라
##    아래 산출 함수들은 `tier + 1` 로 비교한다.

## 원작 `UpgradeGemLayer::create(2)` = 젬 분해(`<MagicAlchemy_menu3>`).
##
## 🔀 2026-07-31 재이식 — 종전엔 "젬 한 줄에 [분해] 버튼" 자작 목록이었다.
##   참조 영상(`docs/ref/gem/젬분해1~7.png`)의 원작 화면은 **6칸 일괄 분해**다:
##     · 왼쪽 = `scene/magicshop/gem_bg` 육각 칸 **2행 3열**(빈 칸엔 "젬" 글자)
##     · 가운데 = `common/btn_fold` 를 90° 돌린 ▶
##     · 오른쪽 = `9patch/train_box3` 안에 마법가루 3종(붉은/푸른/노란) 산출량
##     · 아래 = 코인 + 비용 버튼 → 확인창(`<AlchemyMsg2>`) → 결과창
##   칸을 누르면 젬 목록(원작 `setSelectedItem` 이 여는 인벤 격자)에서 고른다.
##
## 산출 규칙 출처: `docs/ref/orig_image/shop/점술집_젬강화.pdf` —
##   "분해로 얻은 가루는 혼성젬 제작·용액 제작에 이용" · "초월의 용액은 13강 이상 젬 분해로
##   1개당 최소 1 ~ 최대 36개" · "원형젬 1개 = 가루 2,666 + 용액 36".
##
## 🟦 **비용은 참조 영상에서 역산했다** — `젬분해4.png` 의 6칸 합계
##   12+11+642+597+439+1207 = 2,908개에 비용이 정확히 **1,454,000골드** ⇒ **젬 1개당 500골드**.
const DIS_SLOTS := 6
const DIS_COLS := 3

## 마법가루 3종(원작 표시 순서: 붉은 → 푸른 → 노란).
const DUST_ROWS := [
	{"key": "att_powder", "label": "붉은 마법가루"},
	{"key": "def_powder", "label": "푸른 마법가루"},
	{"key": "hp_powder", "label": "노란 마법가루"},
]

## 분해 비용(젬 1개당) — 위 역산값. 튜닝 노브는 data/gems.json `disassemble.gold_per_gem`.
func _dis_gold_per_gem() -> int:
	return int((Data.gems.get("disassemble", {}) as Dictionary).get("gold_per_gem", 500))


func _body_disassemble(pop: OrigPopup) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var S := Design.ASSET_SCALE
	while _dis_slots.size() < DIS_SLOTS:
		_dis_slots.append("")

	# ── 왼쪽 육각 칸 2×3 (원작 `gem_bg`) ────────────────────────────────
	var hex := AtlasUI.size_pt("magicshop_ui", "scene_magicshop_gem_bg") * 0.62
	var gx := hex.x + 14.0
	var gy := hex.y + 12.0
	var x0 := 70.0 + hex.x * 0.5
	var y0 := 130.0 + hex.y * 0.5
	for i in DIS_SLOTS:
		var c := Vector2(x0 + float(i % DIS_COLS) * gx, y0 + float(i / DIS_COLS) * gy)
		var root := Control.new()
		root.size = hex
		root.position = c - hex * 0.5
		pop.content.add_child(root)
		var bg := _spr("gem_bg", S * 0.62)
		if bg:
			bg.position = hex * 0.5
			root.add_child(bg)
		var ik := _dis_key(i)
		if ik == "":
			var l := Label.new()
			l.text = "젬"
			l.add_theme_font_size_override("font_size", 17)
			l.add_theme_color_override("font_color", Color(0.42, 0.30, 0.18))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.size = hex
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(l)
		else:
			var g := Gem.parse_item_key(ik)
			var gi := Icons.rect(Icons.gem_texture(
				String(Gem.gem_def(String(g["name"]), Data.gems).get("code", "")),
				int(g["tier"])), hex.x * 0.62)
			if gi:
				gi.position = (hex - gi.size) * 0.5
				root.add_child(gi)
			# 원작 `UpgradeGemLayer` 슬롯 라벨(tag 0x2510) = `"x%d"` × **그 칸에 투입한 수량**.
			# 보유량 전체가 아니다 — `requestDisassemble` 이 칸마다 `"<itemNo>_<cnt>"` 를 보낸다.
			var n := Label.new()
			n.text = "x%d" % _dis_cnt(i)
			n.add_theme_font_size_override("font_size", 15)
			n.add_theme_color_override("font_color", Color(1, 1, 1))
			n.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			n.add_theme_constant_override("outline_size", 4)
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			n.position = Vector2(0, hex.y - 24.0)
			n.size = Vector2(hex.x, 22.0)
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(n)
		var idx := i
		var b := Button.new()
		b.flat = true
		b.size = hex
		b.pressed.connect(func(): _dis_click_slot(idx))
		root.add_child(b)

	# ── ▶ (원작 `common/btn_fold` 를 90° 회전) ──────────────────────────
	var arrow := AtlasUI.spr("common_ui", "common_btn_fold", S * 0.8)
	if arrow:
		arrow.rotation = deg_to_rad(90.0)
		arrow.position = Vector2(x0 + 2.0 * gx + hex.x * 0.5 + 26.0, y0 + gy * 0.5)
		pop.content.add_child(arrow)

	# ── 오른쪽 산출 패널(원작 `9patch/train_box3`) ─────────────────────
	var yields := _dis_yields()
	var px := x0 + 2.0 * gx + hex.x * 0.5 + 56.0
	var pw := W - px - 50.0
	for r in DUST_ROWS.size():
		var d: Dictionary = DUST_ROWS[r]
		var ry := 118.0 + float(r) * 64.0
		var row := AtlasUI.nine("ninepatch_ui", "9patch_train_box3",
			Vector2(pw, 56.0), Rect2(20, 20, 4, 4))
		if row:
			row.position = Vector2(px, ry)
			pop.content.add_child(row)
		var ip := Data.item_icon_path(String(d["key"]))
		if ip != "" and ResourceLoader.exists(ip):
			var ic := Sprite2D.new()
			ic.texture = load(ip)
			ic.material = _pma
			ic.scale = Vector2(0.34, 0.34)
			ic.position = Vector2(px + 32.0, ry + 28.0)
			pop.content.add_child(ic)
		var nl := Label.new()
		nl.text = String(d["label"])
		nl.add_theme_font_size_override("font_size", 16)
		nl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nl.position = Vector2(px + 62.0, ry + 17.0)
		nl.size = Vector2(pw - 200.0, 22.0)
		pop.content.add_child(nl)
		var have := int(yields.get(String(d["key"]), 0))
		var vl := Label.new()
		vl.text = "%s개" % _comma(have)
		vl.add_theme_font_size_override("font_size", 18)
		vl.add_theme_color_override("font_color",
			Color(0.10, 0.42, 0.16) if have > 0 else Color(0.45, 0.33, 0.20))
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		vl.position = Vector2(px, ry + 16.0)
		vl.size = Vector2(pw - 22.0, 24.0)
		pop.content.add_child(vl)

	# ── 비용 버튼(원작 코인 + RoundedButton) ───────────────────────────
	var cost := _dis_cost()
	var btn := _frame_button(pop.content, _comma(cost),
		Vector2(W * 0.5 - 110.0, H - 84.0), Vector2(220.0, 52.0), _dis_confirm, 0, cost <= 0)
	var coin := AtlasUI.spr("common_ui", "common_coin_small1", S * 0.9)
	if coin:
		coin.position = Vector2(30.0, 26.0)
		btn.add_child(coin)


## 한 칸의 인벤 키 / 투입 수량. 칸은 `{"key": String, "cnt": int}` 이고 빈 칸은 `""` 다
## (예전 세이브·이전 판 코드가 문자열만 넣어 두는 경우도 받아 준다).
func _dis_key(i: int) -> String:
	var s = _dis_slots[i]
	if s is Dictionary:
		return String((s as Dictionary).get("key", ""))
	return String(s)


func _dis_cnt(i: int) -> int:
	var key := _dis_key(i)
	if key == "":
		return 0
	var s = _dis_slots[i]
	var n := int((s as Dictionary).get("cnt", 1)) if s is Dictionary else UserDB.item_count(key)
	return clampi(n, 0, UserDB.item_count(key))


## 이미 다른 칸이 쓰고 있는 수량(같은 스택을 두 칸에 나눠 담을 수 있으므로 합이 보유량을
## 넘지 않도록 막는다 — 원작도 칸마다 따로 `Item::getCount()` 를 싣는다).
func _dis_used_elsewhere(key: String, except_slot: int) -> int:
	var n := 0
	for i in _dis_slots.size():
		if i != except_slot and _dis_key(i) == key:
			n += _dis_cnt(i)
	return n


## 고른 젬들이 낼 가루(계열별 합) — 칸마다 **투입 수량만큼**.
func _dis_yields() -> Dictionary:
	var out := {"att_powder": 0, "def_powder": 0, "hp_powder": 0}
	for i in _dis_slots.size():
		var key := _dis_key(i)
		if key == "":
			continue
		var g := Gem.parse_item_key(key)
		if g.is_empty():
			continue
		var dk := Gem.dust_key_for(String(g["name"]))
		out[dk] = int(out[dk]) + Gem.disassemble_dust(int(g["tier"]), Data.gems) * _dis_cnt(i)
	return out


func _dis_special() -> int:
	var sp := 0
	for i in _dis_slots.size():
		var key := _dis_key(i)
		if key == "":
			continue
		var g := Gem.parse_item_key(key)
		if g.is_empty():
			continue
		sp += Gem.disassemble_special(int(g["tier"]), Data.gems) * _dis_cnt(i)
	return sp


func _dis_count() -> int:
	var n := 0
	for i in _dis_slots.size():
		n += _dis_cnt(i)
	return n


func _dis_cost() -> int:
	return Gem.disassemble_gold(_dis_count(), Data.gems)


## 빈 칸을 누르면 젬 고르기(원작 `MagicSelectLayer`) — 거기서 **수량까지** 정한다.
## 찬 칸을 누르면 비운다.
func _dis_click_slot(i: int) -> void:
	if _dis_key(i) != "":
		_dis_slots[i] = ""
		_refresh_feature()
		return
	_open_gem_picker("", func(key: String, cnt: int):
		_dis_slots[i] = {"key": key, "cnt": maxi(1, cnt)}
		_refresh_feature(), i)


## 원작 `<AlchemyMsg2>` 확인창 → `requestDisassemble` → `responseDisassemble` 결과창.
func _dis_confirm() -> void:
	var cost := _dis_cost()
	if cost <= 0:
		return
	if UserDB.gold() < cost:
		_toast("골드가 부족합니다")
		return
	PopupType.open(self, "알림",
		"젬을 분해할 경우 선택한 젬은 사라집니다.\n분해하시겠습니까?", _dis_run, "확인", "취소")


func _dis_run() -> void:
	var cost := _dis_cost()
	if cost <= 0 or not UserDB.spend("gold", cost):
		return
	var yields := _dis_yields()
	var sp := _dis_special()
	for i in _dis_slots.size():
		var key := _dis_key(i)
		if key != "":
			UserDB.use_item(key, _dis_cnt(i))
	var got: Array = []
	for k in yields.keys():
		var n := int(yields[k])
		if n > 0:
			UserDB.add_item(String(k), n)
			got.append({"key": String(k), "count": n})
	if sp > 0:
		UserDB.add_item("alchemy_special", sp)
		got.append({"key": "alchemy_special", "count": sp})
	_dis_slots = ["", "", "", "", "", ""]
	_refresh_feature()
	if not got.is_empty():
		GetItemPopup.open(self, got)          # 원작 `resultPopup`
	if sp > 0:
		# 원작 `<AlchemyMsg21>` — "젬분해 추가 보상으로 %s %d개를 받았습니다."
		PopupType.open(self, "알림",
			"젬분해 추가 보상으로 초월의 용액 %d개를 받았습니다." % sp, Callable(), "확인", "")
	_toast("젬 분해를 완료 하였습니다.")            # <AlchemyMsg25>


## 분해 실행 — 가루는 그 젬 계열(공/방/체)의 가루로 준다.
## 산출 공식은 전부 `Gem`(logic) 으로 옮겼다 — 원작 `UpgradeGemLayer` 디컴프 그대로다.
func _disassemble(item_key: String, gem_name: String, tier: int) -> void:
	if UserDB.item_count(item_key) <= 0:
		return
	UserDB.use_item(item_key, 1)
	var dust := Gem.disassemble_dust(tier, Data.gems)
	var sp := Gem.disassemble_special(tier, Data.gems)
	UserDB.add_item(Gem.dust_key_for(gem_name), dust)
	if sp > 0:
		UserDB.add_item("alchemy_special", sp)
	_toast("분해했습니다 — 가루 %d개%s" % [dust, ("" if sp <= 0 else " · 초월의 용액 %d개" % sp)])
	_refresh_feature()

## 원작 `AlchemyLayer` = 용액 상점(<MagicAlchemy_menu5>).
## 품목은 docs/ref/orig_image/shop/점술집_젬강화.pdf 가 확정한다 —
##   영광의 용액(연금술 포인트 +10 고정) · 전설의 용액(+25 고정) · 샌즈의 눈물 10%·20%.
## ⚠️ 가격만 위키에도 없다(서버 유실) → data/gems.json `potion_shop` 자작 노브.
## 용액 상점(<MagicAlchemy_menu5>) — **구판 전용**이라 후기판 디컴프에 대응 클래스가 없다.
## 레퍼런스 `docs/ref/orig_image/shop/점술집_젬강화.pdf` [용액 상점] 스샷 2장으로 재구성:
##   · 목록 = 2열 상품 카드(이름 위 / 아이콘 / 하단 다이아 가격) — 상점과 같은 `common/item_bg`
##     + `common/backlight3` 조합(원작 공통 상품칸, `ShopScene::setItems` 와 동일)
##   · 카드를 누르면 **상세 팝업** — 설명 + `common/btn_arrow2` 수량 ◀▶ + [구입]
## ⚠️ 가격은 원작 서버 데이터라 유실 → `data/gems.json` `potion_shop` 자작값(HARD RULE 6 표기).
func _body_potion_shop(pop: OrigPopup) -> void:
	var W: float = pop.win_size.x
	var items: Array = (Data.gems.get("potion_shop", {}) as Dictionary).get("items", [])
	var cw := AtlasUI.size_pt("common_ui", "common_item_bg").x
	var ch := AtlasUI.size_pt("common_ui", "common_item_bg").y
	# 창(800×480) 안에 2행이 들어가도록 카드를 줄인다 — 원작 판(구판)은 화면이 더 넓었다.
	const K := 0.78
	var cols := 2
	var gx := cw * K + 40.0
	var gy := ch * K + 18.0
	var x0: float = round((W - ((cols - 1) * gx + cw * K)) * 0.5)
	for i in items.size():
		var e: Dictionary = items[i]
		var key := String(e.get("item", ""))
		var price := int(e.get("price", 0))
		var cur := String(e.get("cur", "gold"))
		var card := Control.new()
		card.size = Vector2(cw, ch)
		card.scale = Vector2(K, K)
		card.position = Vector2(x0 + (i % cols) * gx, 100.0 + (i / cols) * gy)
		pop.content.add_child(card)
		var frame := AtlasUI.spr("common_ui", "common_item_bg", Design.ASSET_SCALE)
		if frame != null:
			frame.position = Vector2(cw, ch) * 0.5
			card.add_child(frame)
		var back := AtlasUI.spr("common_ui", "common_backlight3", 0.35 * Design.ASSET_SCALE)
		if back != null:
			back.position = Vector2(cw * 0.5, ch * 0.5 + 6.0)
			card.add_child(back)
		var ip := Data.item_icon_path(key)
		if ip != "" and ResourceLoader.exists(ip):
			var ic := Sprite2D.new()
			ic.texture = load(ip); ic.material = AtlasUI.pma()
			ic.position = Vector2(cw * 0.5, ch * 0.5 + 6.0); ic.scale = Vector2(0.62, 0.62)
			card.add_child(ic)
		var l := Label.new()
		l.text = Data.item_name(key)
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(cw, 22.0); l.position = Vector2(0, 12.0)
		card.add_child(l)
		var cicon := AtlasUI.spr("common_ui",
			"common_diamond_small1" if cur == "diamond" else "common_coin_small1", Design.ASSET_SCALE)
		if cicon != null:
			cicon.position = Vector2(cw * 0.5 - 26.0, ch - 22.0)
			card.add_child(cicon)
		var pl := Label.new()
		pl.text = AtlasUI.comma(price)
		pl.add_theme_font_size_override("font_size", 18)
		pl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		pl.position = Vector2(cw * 0.5 - 6.0, ch - 34.0); pl.size = Vector2(70.0, 24.0)
		card.add_child(pl)
		var b := Button.new(); b.flat = true; b.size = Vector2(cw, ch)
		var k2 := key
		var p2 := price
		var c2 := cur
		b.pressed.connect(func(): _open_potion_buy(k2, p2, c2))
		card.add_child(b)
	if items.is_empty():
		var nn := _note("파는 용액이 없습니다.")
		nn.position = Vector2(60.0, 140.0)
		pop.content.add_child(nn)
	var warn := _note("⚠️ 판매 가격은 원작 서버 데이터라 유실 — data/gems.json `potion_shop` 자작값")
	warn.position = Vector2(50.0, pop.win_size.y - 56.0)
	warn.size = Vector2(W - 100.0, 24.0)
	pop.content.add_child(warn)

## 상품 상세(레퍼런스 [용액 상점] 2번째 스샷) — 설명 + 수량 ◀▶ + [구입].
## 수량 화살표는 원작 `common/btn_arrow2`(AlchemyLayer 가 쓰는 프레임).
func _open_potion_buy(key: String, price: int, cur: String) -> void:
	var sub := OrigPopup.open(self, Data.item_name(key), Vector2(560.0, 340.0))
	var W: float = sub.win_size.x
	var H: float = sub.win_size.y
	var qty := [1]
	var ip := Data.item_icon_path(key)
	if ip != "" and ResourceLoader.exists(ip):
		var ic := Sprite2D.new()
		ic.texture = load(ip); ic.material = AtlasUI.pma()
		ic.position = Vector2(120.0, 170.0)
		sub.content.add_child(ic)
	# `data/items.json` 에는 설명문 필드가 없다(원작 문자열 미추출) → 우리가 가진 확정 데이터
	# (`data/gems.json` 의 연금포인트 표 + 보유 수량)로 설명을 만든다. 문구를 지어내지 않는다.
	var line := ""
	for p0 in (Data.gems.get("upgrade", {}) as Dictionary).get("potions", []):
		var pd: Dictionary = p0
		if String(POTION_ITEM.get(String(pd.get("name", "")), "")) != key:
			continue
		if pd.has("points"):
			var lo := int((pd["points"] as Array)[0])
			var hi := int((pd["points"] as Array)[1])
			line = ("젬 강화에 투입하면 연금포인트를 %d 올려 줍니다." % lo) if lo == hi 				else "젬 강화에 투입하면 연금포인트를 %d~%d 올려 줍니다." % [lo, hi]
		else:
			line = "젬 강화 성공률을 %d%% 로 고정합니다." % int(pd.get("success_pct", 0))
		break
	var desc := Label.new()
	desc.text = "%s

보유 %d개" % [line, UserDB.item_count(key)]
	desc.add_theme_font_size_override("font_size", 17)
	desc.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.position = Vector2(215.0, 100.0); desc.size = Vector2(300.0, 130.0)
	sub.content.add_child(desc)
	# 수량 ◀ N ▶
	var qlabel := Label.new()
	qlabel.text = "1"
	qlabel.add_theme_font_size_override("font_size", 24)
	qlabel.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	qlabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qlabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	qlabel.position = Vector2(96.0, H - 116.0); qlabel.size = Vector2(70.0, 40.0)
	sub.content.add_child(qlabel)
	var total := Label.new()
	total.add_theme_font_size_override("font_size", 21)
	total.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	total.position = Vector2(250.0, H - 110.0); total.size = Vector2(220.0, 28.0)
	sub.content.add_child(total)
	var sync := func():
		qlabel.text = str(qty[0])
		total.text = "%s %s" % [AtlasUI.comma(price * qty[0]), "다이아" if cur == "diamond" else "골드"]
	sync.call()
	for d: int in [-1, 1]:
		var ab := AtlasUI.spr("common_ui", "common_btn_arrow2", Design.ASSET_SCALE)
		var ax := 62.0 if d < 0 else 200.0
		if ab != null:
			ab.position = Vector2(ax, H - 96.0)
			ab.flip_h = d < 0
			sub.content.add_child(ab)
		var bb := Button.new(); bb.flat = true; bb.size = Vector2(44.0, 54.0)
		bb.position = Vector2(ax - 22.0, H - 123.0)
		var dd: int = d
		bb.pressed.connect(func():
			qty[0] = clampi(qty[0] + dd, 1, 99)
			sync.call())
		sub.content.add_child(bb)
	sub.add_action_button("구입", func():
		var n: int = qty[0]
		if not UserDB.spend(cur, price * n):
			_toast("재화가 부족합니다"); return
		UserDB.add_item(key, n)
		_toast("%s %d개를 구매했습니다" % [Data.item_name(key), n])
		sub.close()
		_refresh_feature(),
		0, Vector2(170.0, 50.0), Vector2(W - 130.0, H - 96.0))

## 원작 `EggCombineLayer`(<MagicTitleEgg> 알 조합) — 우리는 연구소에 구현돼 있다.
func _body_egg(pop: OrigPopup) -> void:
	var col := _body_panel(pop)
	col.add_child(_note("서로 다른 알을 조합하여 새로운 알을 얻을 수 있습니다.\n(원작 <MagicWelcomeEgg>)"))
	var recipes := 0
	if Data.combine_egg is Dictionary:
		recipes = (Data.combine_egg.get("recipes", []) as Array).size()
	if recipes == 0:
		col.add_child(_note("⚠️ 알 조합 레시피가 아직 비어 있습니다.\ndocs/input/review/combine_egg_sheet.md 를 채우면 조합할 수 있습니다."))
	var b := Button.new(); b.text = "연구소로 이동 (알 조합)"; b.custom_minimum_size = Vector2(0, 46)
	b.pressed.connect(func(): Scenes.goto("laboratory", {"area": _params.get("area", "elpis")}))
	col.add_child(b)

## 원작 <MagicTitleSlot>뽑기 — <MagicWelcomeSlot> "뽑기는 **골드를 사용하여** 여러 가지
## 아이템을 획득하는 요긴한 방법 입니다."
## 원작 `SlotLayer::initWidget`(재디컴프 `docs/ref/orig_code/decomp/SlotLayer.c:1855-1935`) 1:1.
##   · 릴 배경 `scene/magicshop/slotBG`(117×198px) **3개** @ `(창폭/2 + (−158 + 158·i), 창높이/2)`
##   · 릴 내용 `SlotRoller`(세로로 굴러가는 아이템 목록) @ 같은 자리(−157 + 157·i)
##   · 그 위에 `scene/magicshop/slot_frame`(407×226px) 을 z=1 로 덮는다
##   · 실행 = `RoundedButton(200×56)` @ `(창폭×0.25, 60)` + `common/coin_small1` 가격
##
## ★ **잭팟이다**(사용자 지적 2026-07-30 → 디컴프로 확인). `SlotLayer::ResponseSlot` :897
##     if (r1 == r2 && r1 == r3) { 결과 = r1; addItem/addEgg(결과, cnt) } else { 결과 = 0 }
##   릴 3개가 전부 같을 때만 그 아이템을 준다. 아니면 꽝 —
##   `ResponseSlotResult` 가 `music/effect_item_failed.mp3` + <MagicSlotFail> 를 낸다.
##   성공은 `successPopup` 이 `music/effect_dragon_incubation.mp3` 와 함께 획득물을 공개하고,
##   당첨 칸은 `SlotRoller::successEffect`(FadeOut/In 0.25s ×2)로 깜빡인다.
##   정지는 순차적이다 — `CCDelayTime(2.0 + i×0.5)` 로 릴 i 를 세운다.
## 10연속도 **원작에 있다**(`makeMassiveButton`→`onClickMassive`→`requestSlotTen` →
##   `game_fortune/generate_reels_v2.hb` count=10, 결과는 `ShowGetItemDetailLayer` = 우리
##   `GetItemPopup`). 종전 주석의 "원작엔 없다"는 오기였다.
## ⚠️ 가격·확률·품목표는 원작 서버 데이터라 유실 → `data/drops.json` `slot`
##   (사용자 확정 2026-07-30: 성공률 20% · 1회 1,000골드 · 혼성/소울젬 + LV±1 + 고대 포탈 +
##   의문의 알 + 빛나는 의문의 알). 판정은 전부 `Drops.roll_slot`(logic) 이 하고 여기는 그린다.
const SLOT_STOP_BASE := 2.0    # 원작 CCDelayTime(… + 2.0)
const SLOT_STOP_STEP := 0.5    # 릴 i 는 그보다 i×0.5 초 늦게 선다
const SLOT_TICK := 0.06        # 굴러가는 얼굴 교체 주기(원작 SlotRoller 는 픽셀 스크롤)
var _reels: Array = []
var _slot_faces: Array = []    # Drops.slot_faces(...) — 릴 품목표(인덱스가 곧 릴 값)
var _slot_btns: Array = []     # 굴리는 동안 잠글 버튼(원작 isAnimate 가드)
var _slot_spin := false

func _body_slot(pop: OrigPopup) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var cfg: Dictionary = Data.drops.get("slot", {})
	var price := int(cfg.get("price_gold", 1000))
	var cy := H * 0.5 + 14.0
	_slot_faces = Drops.slot_faces(Data.drops, Data.gems)
	_reels = []
	_slot_btns = []
	_slot_spin = false
	for i in 3:
		var bgspr := AtlasUI.spr("magicshop_ui", "scene_magicshop_slotBG", Design.ASSET_SCALE)
		if bgspr != null:
			bgspr.position = Vector2(W * 0.5 - 158.0 + 158.0 * i, cy)
			pop.content.add_child(bgspr)
		# 릴 = 클리핑된 세로 스크롤(원작 SlotRoller = ClippingLayer 파생).
		var reel := Control.new()
		reel.size = Vector2(150.0, 250.0)
		reel.position = Vector2(W * 0.5 - 157.0 + 157.0 * i - 75.0, cy - 125.0)
		reel.clip_contents = true
		reel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pop.content.add_child(reel)
		var face := Sprite2D.new()
		face.material = AtlasUI.pma()
		face.position = Vector2(75.0, 125.0)
		reel.add_child(face)
		_reels.append(face)
		if not _slot_faces.is_empty():
			# 시작 얼굴은 품목표에 고르게 흩어 놓는다(젬만 셋 보이면 품목이 젬뿐인 줄 알게 된다).
			_slot_set_face(face, int(round(float(i) * float(_slot_faces.size() - 1) / 2.0)))
	var frame := AtlasUI.spr("magicshop_ui", "scene_magicshop_slot_frame", Design.ASSET_SCALE)
	if frame != null:
		frame.position = Vector2(W * 0.5, cy)
		frame.z_index = 1
		pop.content.add_child(frame)
	# 원작은 가격(`common/coin_small1` + 금액)을 **실행 버튼의 자식**으로 붙인다 → 버튼 라벨이
	# 곧 가격이고, 코인은 그 왼쪽에 온다. 버튼을 먼저 만들고 코인을 그 위에 얹는다(그리기 순서).
	_slot_btns.append(pop.add_action_button("   %s" % AtlasUI.comma(price),
		func(): _pull_slot(price), 0, Vector2(200.0, 56.0), Vector2(W * 0.25, H - 46.0)))
	_slot_btns.append(pop.add_action_button("10연속", func(): _pull_slot(price, 10), 2,
		Vector2(200.0, 56.0), Vector2(W * 0.75, H - 46.0)))
	var coin := AtlasUI.spr("common_ui", "common_coin_small1", Design.ASSET_SCALE)
	if coin != null:
		coin.position = Vector2(W * 0.25 - 46.0, H - 46.0)
		pop.content.add_child(coin)

## 릴 품목 아이콘. 원작은 릴 전용 아틀라스 `item/item_small/slot_item`(SlotRoller::init 이
## 프리로드한다 — 고대 포탈·의문의 알 프레임이 실재)을 쓰므로 **그 프레임을 먼저** 찾고,
## 거기 없는 품목만 평소 젬/아이템 아이콘으로 떨어진다.
func _slot_face_tex(face: Dictionary) -> Texture2D:
	var key := String(face.get("key", ""))
	if String(face.get("kind", "")) == "item":
		var p := "res://assets/converted/slot_item/item_item_small_slot_item_%s.tres" % key
		if ResourceLoader.exists(p):
			return load(p)
		var ip := Data.item_icon_path(key)
		return load(ip) if ip != "" and ResourceLoader.exists(ip) else null
	var nm := String(face.get("gem_name", ""))
	return Icons.gem_texture(String(Gem.gem_def(nm, Data.gems).get("code", "")),
		int(face.get("tier", 0)))

func _slot_set_face(face: Sprite2D, idx: int) -> void:
	if not is_instance_valid(face) or _slot_faces.is_empty():
		return
	var f: Dictionary = _slot_faces[posmod(idx, _slot_faces.size())]
	var t := _slot_face_tex(f)
	face.texture = t
	# 릴 창(150×250 클리핑)에 맞춘다 — 젬(작은 아이콘)과 릴 전용 프레임(≈70px)이 섞인다.
	if t != null:
		var h := float(t.get_height())
		face.scale = Vector2.ONE * (1.0 if h <= 0.0 else clampf(96.0 / h, 0.8, 2.0))

## 릴 3개를 굴려 `reels`(품목표 인덱스) 에서 순차적으로 세운다 → 다 서면 `on_done`.
## 원작 `ResponseSlot` 의 `CCDelayTime(2.0 + i×0.5)` 3연속 콜백과 같은 타이밍이다.
func _slot_roll(reels: Array, on_done: Callable) -> void:
	if _reels.is_empty() or _slot_faces.is_empty():
		on_done.call(); return
	_slot_spin = true
	_slot_lock(true)
	var n := _slot_faces.size()
	var last := _reels.size() - 1
	for i in _reels.size():
		var face: Sprite2D = _reels[i]
		if not is_instance_valid(face):
			continue
		face.modulate.a = 1.0
		var steps := int((SLOT_STOP_BASE + SLOT_STOP_STEP * i) / SLOT_TICK)
		var tw := face.create_tween()
		for s in steps:
			# 이웃한 얼굴이 순서대로 지나간다(원작 SlotRoller = 품목 목록을 세로로 스크롤).
			var idx := (i * 3 + s + 1) % n
			tw.tween_callback(func(): _slot_set_face(face, idx))
			tw.tween_interval(SLOT_TICK)
		var res_idx := int(reels[i]) if i < reels.size() else 0
		tw.tween_callback(func(): _slot_set_face(face, res_idx))
		if i == last:
			tw.tween_callback(func():
				_slot_spin = false
				_slot_lock(false)
				on_done.call())

## 당첨 칸 깜빡임 — 원작 `SlotRoller::successEffect`(FadeOut 0.25 → FadeIn 0.25 ×2).
func _slot_blink() -> void:
	for f in _reels:
		var face: Sprite2D = f
		if not is_instance_valid(face):
			continue
		var tw := face.create_tween()
		for _r in 2:
			tw.tween_property(face, "modulate:a", 0.0, 0.25)
			tw.tween_property(face, "modulate:a", 1.0, 0.25)

func _slot_lock(on: bool) -> void:
	for b in _slot_btns:
		if not is_instance_valid(b):
			continue
		var root: Control = b
		root.modulate.a = 0.5 if on else 1.0
		for c in root.get_children():
			if c is Button:
				(c as Button).disabled = on

## 골드 뽑기 실행. 판정은 `Drops.roll_slot`(logic) — 여기서는 굴리고 보여 준다.
## 원작 흐름: 요청 → 응답에서 즉시 addItem → 릴 정지 연출 → `ResponseSlotResult` 가 성공/꽝 처리.
## 지급을 먼저 하는 것도 원작과 같다(연출 도중 창을 닫아도 획득물을 잃지 않는다).
func _pull_slot(price: int, count := 1) -> void:
	if _slot_spin:
		return                                    # 원작 `SlotLayer::isAnimate` 가드
	if _slot_faces.is_empty():
		_toast("뽑기 품목표가 비어 있습니다"); return
	if not UserDB.spend("gold", price * count):
		_toast("골드가 부족하네요"); return          # 원작 <MagicErrorMsg2>
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var results := Drops.roll_slot_many(Data.drops, Data.gems, rng, count)
	var got: Dictionary = {}                      # 인벤 키 → 개수
	for r in results:
		var res: Dictionary = r
		if not bool(res.get("win", false)):
			continue
		var k := String(res.get("key", ""))
		var c := int(res.get("count", 1))
		if k == "" or c <= 0:
			continue
		UserDB.add_item(k, c)
		got[k] = int(got.get(k, 0)) + c
	if is_instance_valid(_money_root):
		_money_root.queue_free()
	_build_money(_vis())
	var last: Dictionary = results[results.size() - 1]
	var win := bool(last.get("win", false))
	_slot_roll(last.get("reels", [0, 0, 0]), func(): _slot_result(got, win, count))

## 릴이 다 선 뒤의 성공/꽝 처리 — 원작 `ResponseSlotResult`.
func _slot_result(got: Dictionary, last_win: bool, count: int) -> void:
	if last_win:
		_slot_blink()                             # 원작 SlotRoller::successEffect
	if got.is_empty():
		Bgm.sfx("effect_item_failed")             # 원작 ResponseSlotResult 의 꽝 효과음
		# 원작 <MagicSlotFail>. 유리아의 결과 표정은 4(§REACTION_EMOTIONS).
		_toast("운이 좋지 않은 날인가요? 행운을 빌어요!", 4)
		return
	Bgm.sfx("effect_dragon_incubation")           # 원작 successPopup 의 성공 효과음
	var names: PackedStringArray = []
	var entries: Array = []
	for k in got:
		names.append(_slot_prize_name(String(k)))
		entries.append({"key": String(k), "count": int(got[k])})
	if count <= 1:
		# 원작 <MagicSlotSucces>
		_toast("축하드려요!\n뽑기에 성공하여 %s을(를) 획득하셨어요~ 오늘은 운이 좋으시네요!"
			% ", ".join(names), 4)
	else:
		var wins := 0
		for k in got:
			wins += int(got[k])
		_toast("%d회 중 %d번 당첨! %s을(를) 획득하셨어요~" % [count, wins, ", ".join(names)], 4)
	# 원작 10연속 결과창 `ShowGetItemDetailLayer` 이식본.
	GetItemPopup.open(self, entries)

## 당첨 품목 표시 이름 — 젬 키는 티어까지 붙는다.
func _slot_prize_name(key: String) -> String:
	if key.begins_with("gem:"):
		var g := Gem.parse_item_key(key)
		return Gem.display_name(String(g["name"]), int(g["tier"]), Data.gems)
	return Data.item_name(key)

func _comma(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out


## 강화 1회 비용. 소울젬은 위키 §3 의 단계표, 일반/혼성은
## docs/ref/orig_image/shop/점술집_젬강화.pdf 의 실측표(3,000 + 600×(티어-1))를 쓴다.
## (종전 `200 + tier*150` 자작값은 위키 표 확보로 폐기)
func _gem_cost(gem_name: String, tier: int) -> int:
	var gd: Dictionary = Gem.gem_def(gem_name, Data.gems)
	if String(gd.get("category", "")) == "soul":
		var steps: Array = Data.gems.get("upgrade", {}).get("soul_steps", [])
		var i := clampi(tier, 0, steps.size() - 1)
		if i < steps.size(): return int((steps[i] as Dictionary).get("gold", 0))
	return Gem.upgrade_cost(tier, Data.gems)

func _upgrade(uid: int, slot: int, cost: int) -> void:
	var next: Dictionary = Gem.upgrade_at(UserDB.get_dragon(uid).get("gems", {}), slot, Data.gems)
	if next.is_empty(): return
	if not UserDB.spend("gold", cost): return
	UserDB.set_dragon_field(uid, "gems", next)
	_toast("젬을 강화했습니다"); _refresh_feature()

func _promote(uid: int, slot: int, gold: int) -> void:
	var next: Dictionary = Gem.promote_at(UserDB.get_dragon(uid).get("gems", {}), slot, Data.gems)
	if next.is_empty(): return
	if not UserDB.spend("gold", gold): return
	UserDB.set_dragon_field(uid, "gems", next)
	_toast("소울젬으로 승급했습니다!"); _refresh_feature()

# ── 용액 제작(PotionLayer) ─────────────────────────────────────────────────
## 위키 gems.pdf §2.2 용액표: 절제=각1 / 지혜=각2 / 용기=각3 / 정의=각4 (공방체 가루).
## 초월의 용액은 "13강 이상 젬 분해"라 제작이 아니다 → 목록에서 제외.
## 이름 → 아이템 키. 앞 4종만 **제작 가능**하고, 영광·전설은 용액 상점 전용이다
## (docs/ref/orig_image/shop/점술집_젬강화.pdf: [용액 제작] 4종 / [용액 상점] 영광·전설·샌즈의 눈물).
const POTION_ITEM := {
	"절제의 용액": "alchemy_moderation",
	"지혜의 용액": "alchemy_wisdom",
	"용기의 용액": "alchemy_courage",
	"정의의 용액": "alchemy_justice",
	"영광의 용액": "alchemy_glory",
	"전설의 용액": "alchemy_legend",
	"초월의 용액": "alchemy_special",
}

## 원작 `PotionLayer` — 레퍼런스 `docs/ref/orig_image/shop/점술집_젬강화.pdf` [용액 제작] 스샷 1:1.
##
## 원작 프레임(전부 보유):
##   · 행 배경   `scene/magicshop/list_bg`(394×67px = 525×89pt) — 목록 한 줄
##   · 용액 아이콘판 `scene/magicshop/drink_bg`(71×81px) + `common/backlight3` + 아이템 아이콘
##   · POINT 뱃지  `scene/magicshop/alchemy/alchemy_point_1~5`(53×22px) — 용액 등급별 리본
##   · 하단 보유 가루 띠 = `9patch/train_box3` + 가루 아이콘 3종
##   · 실행 버튼  `RoundedButton` = `9patch/btn*`  ("조합하기")
##
## 레이아웃(레퍼런스 실측 비율 → 창 800×480 로컬 포인트):
##   행 y = 88 + i×96, 행 폭 = 창폭 − 80. 아이콘판 x=56, 이름 x=118(위),
##   POINT 뱃지 x=118(아래), "필요가루 :" x=300, 가루 3종 x=390+ 60×n.
##   하단 띠 y = 창높이 − 74, 실행 버튼 = 창 우하단.
##
## ⚠️ 원작 창은 이 레퍼런스(2016 구판)에서 929×635pt 인데, 디컴프(후기판)는
##    `setContentSpriteSize(800,480)` 이다. 우리 화면은 1024 폭이라 800 쪽이 NPC·대사창과
##    겹치지 않아 **디컴프 값**을 쓴다.
const POTION_ROW_H := 96.0

func _body_drink(pop: OrigPopup) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var rw := W - 80.0
	var rows: Array = []
	for p in (Data.gems.get("upgrade", {}).get("potions", []) as Array):
		var pd: Dictionary = p
		var nm := String(pd.get("name", ""))
		if not POTION_ITEM.has(nm) or bool(pd.get("shop_only", false)) or not pd.has("points"):
			continue     # 초월의 용액 = 젬 분해 산출물 / 영광·전설 = 상점 전용(위키)
		rows.append(pd)
	# 원작은 `CCTableView` 라 목록이 창 안에서 잘리고 스크롤된다 — 하단 보유띠를 덮지 않게
	# 같은 영역을 ScrollContainer 로 잡는다.
	var list := ScrollContainer.new()
	list.position = Vector2(40.0, 88.0)
	list.size = Vector2(rw, H - 88.0 - 92.0)
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.clip_contents = true
	list.follow_focus = false
	pop.content.add_child(list)
	# 버튼이 포커스를 먹어 목록이 아래로 굴러가 있는 걸 막는다(첫 줄부터 보여야 한다).
	list.ready.connect(func(): list.scroll_vertical = 0)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(rw - 16.0, rows.size() * POTION_ROW_H)
	list.add_child(holder)
	for i in rows.size():
		var pd: Dictionary = rows[i]
		var nm := String(pd.get("name", ""))
		var each := int(pd.get("cost_dust_each", 0))
		var mgold := int(pd.get("make_gold", 1000))   # 위키: 제작 비용은 4종 모두 1,000G
		var key := String(POTION_ITEM[nm])
		var ok := UserDB.gold() >= mgold
		for k: String in POWDERS:
			ok = ok and UserDB.item_count(k) >= each
		var row := Control.new()
		row.size = Vector2(rw - 16.0, POTION_ROW_H - 8.0)
		row.position = Vector2(0.0, i * POTION_ROW_H)
		holder.add_child(row)
		var bgn := AtlasUI.nine("magicshop_ui", "scene_magicshop_list_bg", row.size)
		if bgn != null:
			row.add_child(bgn)
		# 용액 아이콘 = drink_bg 판 + 회전 별빛 + 아이템 아이콘
		var plate := AtlasUI.spr("magicshop_ui", "scene_magicshop_drink_bg", Design.ASSET_SCALE * 0.75)
		if plate != null:
			plate.position = Vector2(56.0, row.size.y * 0.5)
			row.add_child(plate)
		var ip := Data.item_icon_path(key)
		if ip != "" and ResourceLoader.exists(ip):
			var ic := Sprite2D.new()
			ic.texture = load(ip)
			ic.material = AtlasUI.pma()
			ic.position = Vector2(56.0, row.size.y * 0.5)
			ic.scale = Vector2(0.62, 0.62)
			row.add_child(ic)
		var l := Label.new()
		l.text = nm
		l.add_theme_font_size_override("font_size", 21)
		l.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		l.position = Vector2(108.0, 12.0); l.size = Vector2(190.0, 26.0)
		row.add_child(l)
		# POINT 뱃지 — 용액 등급(i+1)에 대응하는 원작 리본 프레임.
		var pts: Array = pd.get("points", [0, 0])
		var badge := AtlasUI.spr("magicshop_alchemy",
			"scene_magicshop_alchemy_alchemy_point_%d" % clampi(i + 1, 1, 5), Design.ASSET_SCALE)
		var bsz := AtlasUI.size_pt("magicshop_alchemy", "scene_magicshop_alchemy_alchemy_point_1")
		if badge != null:
			badge.position = Vector2(108.0 + bsz.x * 0.5, 56.0)
			row.add_child(badge)
		var pl := Label.new()
		pl.text = "%d ~ %d" % [int(pts[0]), int(pts[1])]
		pl.add_theme_font_size_override("font_size", 17)
		pl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		pl.position = Vector2(112.0 + bsz.x, 44.0); pl.size = Vector2(90.0, 24.0)
		row.add_child(pl)
		var need := Label.new()
		need.text = "필요가루 :"
		need.add_theme_font_size_override("font_size", 18)
		need.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		need.position = Vector2(300.0, 28.0); need.size = Vector2(110.0, 26.0)
		row.add_child(need)
		var n := 0
		for k: String in POWDERS:
			var px := 410.0 + n * 66.0
			var pip := Data.item_icon_path(k)
			if pip != "" and ResourceLoader.exists(pip):
				var pic := Sprite2D.new()
				pic.texture = load(pip)
				pic.material = AtlasUI.pma()
				pic.position = Vector2(px, row.size.y * 0.5)
				pic.scale = Vector2(0.42, 0.42)
				row.add_child(pic)
			var cl := Label.new()
			cl.text = "x%d" % each
			cl.add_theme_font_size_override("font_size", 18)
			cl.add_theme_color_override("font_color",
				Color(0.30, 0.17, 0.04) if UserDB.item_count(k) >= each else Color(0.72, 0.16, 0.10))
			cl.position = Vector2(px + 14.0, row.size.y * 0.5 - 4.0); cl.size = Vector2(48.0, 24.0)
			row.add_child(cl)
			n += 1
		var b := Button.new()
		b.flat = true
		b.size = row.size
		b.disabled = not ok
		var k2 := key
		var e2 := each
		var g2 := mgold
		b.pressed.connect(func(): _craft_potion(k2, e2, g2))
		row.add_child(b)
		if not ok:
			row.modulate = Color(0.72, 0.72, 0.72)
	# 하단 보유 가루 띠 (레퍼런스: 창 좌하단에 가루 3종 보유량)
	var bar := AtlasUI.nine("ninepatch_ui", "9patch_train_box3", Vector2(rw - 250.0, 46.0),
		Rect2(30, 16, 62, 8))
	if bar != null:
		bar.position = Vector2(40.0, H - 76.0)
		pop.content.add_child(bar)
	var m := 0
	for k: String in POWDERS:
		var px := 70.0 + m * 150.0
		var pip := Data.item_icon_path(k)
		if pip != "" and ResourceLoader.exists(pip):
			var pic := Sprite2D.new()
			pic.texture = load(pip)
			pic.material = AtlasUI.pma()
			pic.position = Vector2(px, H - 53.0)
			pic.scale = Vector2(0.42, 0.42)
			pop.content.add_child(pic)
		var cl := Label.new()
		cl.text = "x%d" % UserDB.item_count(k)
		cl.add_theme_font_size_override("font_size", 19)
		cl.add_theme_color_override("font_color", Color(0.95, 0.93, 0.85))
		cl.add_theme_color_override("font_outline_color", Color(0.16, 0.09, 0.03))
		cl.add_theme_constant_override("outline_size", 4)
		cl.position = Vector2(px + 16.0, H - 66.0); cl.size = Vector2(120.0, 26.0)
		pop.content.add_child(cl)
		m += 1
	# 원작 '조합하기' = RoundedButton. 목록에서 고른 줄을 만드는 구조가 아니라
	# 우리는 줄 자체가 버튼이므로, 이 버튼은 **첫 번째 제작 가능한 용액**을 만든다.
	pop.add_action_button("조합하기", func():
		for pd2 in rows:
			var d2: Dictionary = pd2
			var e3 := int(d2.get("cost_dust_each", 0))
			var g3 := int(d2.get("make_gold", 1000))
			var can := UserDB.gold() >= g3
			for k3: String in POWDERS:
				can = can and UserDB.item_count(k3) >= e3
			if can:
				_craft_potion(String(POTION_ITEM[String(d2.get("name", ""))]), e3, g3)
				return
		_toast("재료가 모자라요."),
		0, Vector2(200.0, 52.0), Vector2(W - 150.0, H - 53.0))

func _craft_potion(item_key: String, each: int, gold: int) -> void:
	for k: String in POWDERS:
		if UserDB.item_count(k) < each: return
	if not UserDB.spend("gold", gold):
		_toast("골드가 부족합니다"); return
	for k: String in POWDERS:
		UserDB.use_item(k, each)
	UserDB.add_item(item_key, 1)
	_toast("%s 1개를 제작했습니다" % Data.item_name(item_key))
	_refresh_feature()

# ── 드래곤 변환(TransDragonLayer) ──────────────────────────────────────────
## ⚠️ 변환표(어떤 드래곤 → 어떤 드래곤, 비용)는 서버 데이터라 유실. 값 날조 금지(HARD RULE 6).
## 원작 `TransDragonLayer` — 소환진 위 받침대에 드래곤을 세우고 변환한다.
## 쓰는 프레임(`docs/ref/audit/TransDragonLayer.md` + 디컴프 :414-660):
##   `scene/magicshop/recall_stand`(받침대) · `recall_magic_circle_1/2`(소환진 2겹) ·
##   `common/shadow`(그림자) · `common/name_bg`(이름표) · `common/btn_up` · `9patch/btn`(243×50)
##
## ⚠️ **원작의 내용은 이식하지 않는다.** 원작은 드래곤빌리지 **1의 드래곤을 계정 연동으로
##    가져오는** 기능이었다 — 계정·서버가 전제라 §2-1(온라인 삭제) 대상이고 변환표도 유실됐다.
##    사용자 확정(2026-07-30): 껍데기(소환진·받침대·이름표)는 원작 프레임 그대로 쓰고,
##    내용을 **보유 드래곤 → 커스텀 종(600 수비형 / 700 공격형) 알 변환**으로 바꾼다.
##    규칙은 전부 `Summon`(logic 층)에 있다 — 이 함수는 그리기와 입력만 한다.
func _body_trans(pop: OrigPopup) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var S := Design.ASSET_SCALE
	var cx := W * 0.5
	var cy := H * 0.56
	var unlocked := bool(UserDB.get_pmeta(Summon.FLAG_UNLOCK, false))
	# 소환진 2겹 — 바깥은 느리게, 안쪽은 반대로 돈다(원작 CCRotateBy 연출).
	# ⚠️ `recall_magic_circle_1`(408×368) 은 **프레임 중심 ≠ 문양 중심**이다. 위·좌하·우하의
	#    위성 원 3개가 큰 원 밖으로 튀어나와 캔버스를 비대칭으로 넓혀서, 문양의 진짜 중심은
	#    프레임 기하중심 (204,184) 보다 **30px 아래**인 (203.3, 213.8) 이다.
	#    Sprite2D 는 **원점**을 축으로 돌므로 보정 없이 돌리면 문양이 제자리 회전이 아니라
	#    반경 30px(화면 25px)으로 **궤도를 그리며 돌아** 파란 소환진(218×218, 문양이 프레임
	#    중앙 정렬)과 축이 어긋난다. offset 은 텍스처 픽셀이고 scale 이 함께 곱해진다.
	#
	#    측정(2026-07-30) — ⚠️ 촘촘한 선화라 "중심을 찍고 링을 피팅"하면 **찍은 점이 그대로
	#    답으로 나온다**(모든 각도에서 뭔가에 맞는다). 씨앗 없는 두 방법으로만 확정했다:
	#      · 텍스처: 후보 중심 격자마다 120° 자기유사 IoU → (203,214) 0.268 ≫ (204,184) 0.119
	#      · 인게임: 양피지 배경을 뺀 문양 마스크에 씨앗 없는 원 검출(Hough)
	#          수정 전 위상A (662,395) · 위상B (655,388)  ← 파란 축에서 26~29px, 위상마다 이동
	#          수정 후 위상A (683,379) · 위상B (683,378)  ← 파란 축 (682.5,378.5) 과 0.7px
	const C1_PIVOT := Vector2(0.8, -29.8)   # = 기하중심 − 문양중심
	var c1 := _spr("recall_magic_circle_1", S * 0.62)
	if c1 != null:
		c1.position = Vector2(cx, cy)
		c1.offset = C1_PIVOT
		c1.modulate = Color(1, 1, 1, 0.55)
		pop.content.add_child(c1)
		c1.create_tween().set_loops().tween_property(c1, "rotation", TAU, 24.0).as_relative()
	var c2 := _spr("recall_magic_circle_2", S * 0.62)
	if c2 != null:
		c2.position = Vector2(cx, cy)
		c2.modulate = Color(1, 1, 1, 0.8)
		pop.content.add_child(c2)
		c2.create_tween().set_loops().tween_property(c2, "rotation", -TAU, 14.0).as_relative()
	var shadow := AtlasUI.spr("common_ui", "common_shadow", S * 0.8)
	if shadow != null:
		shadow.position = Vector2(cx, cy + 44.0)
		shadow.modulate = Color(1, 1, 1, 0.55)
		pop.content.add_child(shadow)
	var stand := _spr("recall_stand", S * 0.8)
	if stand != null:
		stand.position = Vector2(cx, cy + 52.0)
		pop.content.add_child(stand)
	# 잠김 — 소환진만 돌고 아무것도 고를 수 없다. 무엇이 트리거인지는 **밝히지 않는다**
	# (해금 조건 노출 방지, 사용자 요청 2026-07-30).
	if not unlocked:
		var lk := _note("소환진이 깊이 잠들어 있습니다.\n아직 이곳의 힘을 깨울 때가 아닙니다.")
		lk.position = Vector2(60.0, 92.0)
		lk.size = Vector2(W - 120.0, 60.0)
		lk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pop.content.add_child(lk)
		var lb := pop.add_action_button("소환", func(): _toast("소환진이 응답하지 않습니다."),
			0, Vector2(243.0, 50.0))
		lb.modulate = Color(0.72, 0.72, 0.72)
		return

	# 고를 수 있는 종(세이브당 각 1마리 상한 — 이미 가진 종은 빠진다).
	var steps := {}
	for s in Summon.SPECIES:
		steps[s] = UserDB.dex_step(int(s))
	var avail: Array = Summon.available_species(steps)
	if avail.is_empty():
		var dn := _note("소환진의 부름에 응답할 존재가 더는 남아 있지 않습니다.")
		dn.position = Vector2(60.0, 92.0); dn.size = Vector2(W - 120.0, 60.0)
		dn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pop.content.add_child(dn)
		return
	if not avail.has(_summon_species):
		_summon_species = int(avail[0])

	# 받침대 위 재료 드래곤 — 고르기 전에는 비어 있다.
	var mat := UserDB.get_dragon(_summon_uid)
	if not Summon.can_be_material(mat, _grade_of(mat)):
		mat = {}
		_summon_uid = 0
	if not mat.is_empty():
		_add_stand_dragon(pop.content, mat, Vector2(cx, cy + STAND_FOOT_Y))

	# 이름표(원작 `common/name_bg`) — 받침대에 선 드래곤 이름.
	# ⚠️ 창 높이가 480pt 뿐이고 하단 실행 버튼이 `win_size.y - 60` 을 차지한다 → 이름표는
	#    cy+92 가 상한이다(그 아래로 내리면 실행 버튼과 겹친다, 2026-07-30 스크린샷 검수).
	# ⚠️ 스파인 씬은 슬롯마다 z_index 를 갖는다(z_as_relative 라 홀더 기준으로 더해진다) →
	#    형제 순서만으로는 이름표가 드래곤 밑에 깔려 **글자가 안 보였다**(2026-07-30 검수).
	#    이름표와 글자를 명시적으로 위에 올린다.
	const NAMEPLATE_Z := 50
	var nb := AtlasUI.spr("common_ui", "common_name_bg", S)
	var nbs := AtlasUI.size_pt("common_ui", "common_name_bg")
	if nb != null:
		nb.position = Vector2(cx, cy + 92.0)
		nb.z_index = NAMEPLATE_Z
		pop.content.add_child(nb)
	var nl := Label.new()
	nl.text = _dragon_label(mat) if not mat.is_empty() else "드래곤을 골라주세요"
	nl.add_theme_font_size_override("font_size", 19)
	# `common/name_bg` 는 밝은 판이라 글자는 진한 갈색이다 — 상태창 이름판과 같은 색
	# (`status_layer.gd` :311). 종전의 흰색은 판 위에서 읽히지 않았다(2026-07-30 검수).
	nl.add_theme_color_override("font_color",
		Color(0.36, 0.22, 0.08) if not mat.is_empty() else Color(0.55, 0.44, 0.30))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.size = Vector2(nbs.x, nbs.y)
	nl.position = Vector2(cx - nbs.x * 0.5, cy + 92.0 - nbs.y * 0.5)
	nl.z_index = NAMEPLATE_Z
	pop.content.add_child(nl)

	var head := _note("가장 소중한 드래곤을 골라주세요.\n"
		+ "선택된 드래곤은 강력한 힘을 받고 다시 태어납니다.")
	head.position = Vector2(60.0, 84.0); head.size = Vector2(W - 120.0, 48.0)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pop.content.add_child(head)

	# 버튼 한 줄에 [종 선택…][재료 선택] 을 모두 넣는다 — 창 높이가 빠듯해 행을 더 못 쓴다.
	# 종 선택 = 600 수비형 / 700 공격형(이미 가진 종은 목록에 없다).
	var names := SPECIES_LABEL
	var bw := 150.0
	var gap := 12.0
	var n := avail.size() + 1                      # 종 버튼들 + '재료 선택'
	var x0 := cx - (float(n) * bw + float(n - 1) * gap) * 0.5
	for i in avail.size():
		var sp := int(avail[i])
		var on := sp == _summon_species
		_frame_button(pop.content, String(names[sp]),
			Vector2(x0 + float(i) * (bw + gap), 140.0), Vector2(bw, 46.0),
			func():
				_summon_species = sp
				_refresh_feature(),
			1 if on else 0)
	_frame_button(pop.content, "드래곤 선택",
		Vector2(x0 + float(avail.size()) * (bw + gap), 140.0), Vector2(bw, 46.0),
		func(): _open_summon_picker())

	# 실행(원작 `9patch/btn` 243×50 규격 유지)
	var ready := not mat.is_empty()
	var btn := pop.add_action_button("소환", func():
		if not ready:
			_toast("먼저 드래곤을 골라주세요.")
			return
		_do_summon(), 0, Vector2(243.0, 50.0))
	if not ready:
		btn.modulate = Color(0.72, 0.72, 0.72)


## 받침대 위 드래곤 — 초상(정지 그림)이 아니라 **스파인 대기모션**을 세운다(사용자 요청 2026-07-30).
## 씬 규약은 동굴과 같다(`cave.gd::DRAGON_SCENE`): `scenes/dragons/dragon_<art_id>_<단계>.tscn`
## 을 인스턴스화하고 `AnimationPlayer` 의 `"wait"`(대기) 를 재생한다.
##
## 크기 — 이 창은 480pt 높이에 위(y≈140 종/재료 버튼)·아래(이름표 cy+92, 실행 버튼 y≈420)가
## 이미 차 있다. 동굴은 전체화면에서 1.9배로 그리므로 그 비율을 그대로 쓰면 버튼을 덮는다
## ⇒ `STAND_SPINE_SCALE` 로 줄인다. 발밑 기준점은 받침대 윗면(`STAND_FOOT_Y`).
##
## ⚠️ 스파인 씬은 저작권상 gitignore 라 머신마다 빌드 상태가 다르다 — 없으면 종전처럼
##    초상으로 떨어진다(cave.gd 가 같은 이유로 폴백을 둔다).
## 받침대 `recall_stand`(229×91px × S×0.8 = 244×97pt)는 cy+52 에 중심을 둔다 → 윗면 = cy+3.5.
## 발을 그 위에 올린다. 아래로 더 내리면 이름표(cy+92, 높이 ≈41pt → 윗변 cy+72)를 침범한다.
const STAND_SPINE_SCALE := 0.55
const STAND_FOOT_Y := 6.0

func _add_stand_dragon(parent: Node, mat: Dictionary, foot: Vector2) -> void:
	var art := Icons.art_id_of(mat)
	var stage_name := Growth.stage_for_level(int(mat.get("level", 1)))
	var path := "res://scenes/dragons/dragon_%d_%s.tscn" % [art, stage_name]
	if ResourceLoader.exists(path):
		var holder := Node2D.new()
		holder.scale = Vector2(STAND_SPINE_SCALE, STAND_SPINE_SCALE)
		holder.position = foot
		parent.add_child(holder)
		holder.add_child(load(path).instantiate())
		var ap := holder.get_child(0).get_node_or_null("AnimationPlayer")
		if ap and ap.has_animation("wait"):
			ap.play("wait")
		return
	# 폴백 — 스파인 씬이 아직 빌드되지 않은 종.
	var por := _dragon_portrait(mat, 110.0)
	if por != null:
		por.position = foot - Vector2(0, 54.0)
		parent.add_child(por)


## 개체 파생 등급(§K-10) — cave.gd `_grade_of` 와 같은 계산이다(부화 편차 + 레벨업 롤 편차).
## 기준선 모드는 data 노브(`level_curve.json` 의 `grade`) — logic 이 파일을 모르게 여기서 주입한다(§8.2).
func _grade_of(inst: Dictionary) -> float:
	if inst.is_empty():
		return -1.0
	return Growth.compute_grade(Data.get_dragon(int(inst.get("id", 0))), Data.stat_table,
		inst.get("stat_bonus", {}), inst.get("gain_log", []), Data.level_curve.get("grade", {}))


## 재료 후보 목록. 알·잠금 개체와 커스텀 종, **자격 미달**(레벨·등급)은 `Summon.can_be_material`
## 이 걸러 낸다. 하한은 그 상수(`MATERIAL_MIN_LEVEL` · `MATERIAL_MIN_GRADE`)가 단일 출처다.
func _open_summon_picker() -> void:
	if not is_instance_valid(_popup):
		return
	_popup.clear_content()
	var col := _body_panel(_popup)
	# `_body_panel` 의 목록 영역은 창 바닥까지 내려온다 — 아래 '돌아가기' 버튼이 마지막 행을
	# 가리므로 버튼 높이만큼 줄인다(2026-07-30 스크린샷 검수).
	var scroll := col.get_parent() as Control
	if scroll != null:
		scroll.size.y = maxf(80.0, scroll.size.y - 72.0)
	var cands := []
	for d in UserDB.dragons():
		if Summon.can_be_material(d, _grade_of(d)):
			cands.append(d)
	# 자격을 목록 위에 적어 둔다 — 후보가 비었을 때 "왜 없는지" 를 알 수 있어야 한다.
	var req := _note("재료 자격: 레벨 %d 이상 · 등급 %.1f 이상\n(알·잠긴 드래곤과 소환으로 얻은 드래곤은 제외)"
		% [Summon.MATERIAL_MIN_LEVEL, Summon.MATERIAL_MIN_GRADE])
	req.custom_minimum_size = Vector2(0, 46)
	req.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(req)
	if cands.is_empty():
		var e := _note("자격을 갖춘 드래곤이 없습니다.")
		e.custom_minimum_size = Vector2(0, 40)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(e)
	var rw: float = _popup.win_size.x - 100.0
	for d in cands:
		var row := Control.new()
		row.custom_minimum_size = Vector2(rw, 64)
		col.add_child(row)
		var bgn := _row_bg(rw, 64)
		if bgn != null: row.add_child(bgn)
		var por := _dragon_portrait(d, 52.0)
		if por != null:
			por.position = Vector2(44.0, 32.0)      # 행 중앙 높이(64/2)에 맞춘 **중심** 좌표
			row.add_child(por)
		var l := Label.new()
		l.text = "%s   Lv.%d" % [_dragon_label(d), int(d.get("level", 1))]
		l.add_theme_font_size_override("font_size", 19)
		l.add_theme_color_override("font_color", Color(0.36, 0.22, 0.08))
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.position = Vector2(84.0, 0.0); l.size = Vector2(rw - 230.0, 64.0)
		row.add_child(l)
		var uid := int(d.get("uid", 0))
		_frame_button(row, "선택", Vector2(rw - 130.0, 10.0), Vector2(110.0, 44.0),
			func():
				_summon_uid = uid
				_refresh_feature())
	_popup.add_action_button("돌아가기", func(): _refresh_feature(), 0, Vector2(220.0, 52.0))


## 변환 실행 — 규칙 판정은 `Summon.plan`, 여기서는 상태 반영과 연출만 한다(§8.3).
func _do_summon() -> void:
	var mat := UserDB.get_dragon(_summon_uid)
	var plan := Summon.plan(_summon_species, mat,
		Data.get_dragon(int(mat.get("id", 0))),
		bool(UserDB.get_pmeta(Summon.FLAG_UNLOCK, false)),
		UserDB.dex_step(_summon_species), _grade_of(mat))
	if plan.is_empty():
		_toast("지금은 소환할 수 없습니다.")
		return
	# 알을 먼저 만들고 재료를 소멸시킨다 — 마지막 1마리를 바쳐도 둥지가 비지 않는다.
	UserDB.add_egg(int(plan["species"]), float(plan["grade"]), int(plan["seconds"]),
		0, plan.get("inherit", {}))
	UserDB.consume_dragon(_summon_uid)
	# 해금 플래그는 **변환 시점에 소비**한다(1회 = 1변환). 다시 열려면 트리거를 또 달성해야 한다.
	UserDB.set_pmeta(Summon.FLAG_UNLOCK, false)
	_summon_uid = 0
	# 원작 `music/effect_combine.mp3` — 교배(breeding)가 쓰는 합성 효과음. 같은 성격이라 재사용.
	Bgm.sfx("effect_combine")
	# 뽑기 알 개봉과 같은 공개 연출(`EggResultPopup`). 소환한 알은 가방이 아니라 **둥지**로 간다.
	# 커스텀 종은 마스터에 이름·속성·초상이 없다 → 재료에게 물려받은 것을 그대로 넘긴다.
	var inh: Dictionary = plan.get("inherit", {})
	var sp := int(plan["species"])
	# **종 이름을 재료에게서 물려받는다**(사용자 확정 2026-07-30) — 예: 고대신룡 "별밤이"를
	# 수비형 재료로 쓰면 600 의 종 이름이 "별밤이". 종당 1마리 상한이라 세이브당 한 번만 정해진다.
	# 이후 모든 표시는 `Icons.species_name` / `Icons.name_of` 가 이 값을 읽는다.
	var sname := String(inh.get("name", ""))
	if sname != "":
		UserDB.set_species_name(sp, sname)
	_egg_reveal = [{"did": sp, "opts": {
		# 폴백이 "수비형"/"공격형" 이던 것을 종 이름으로 바꿨다 — 재료 이름이 곧 종 이름이다.
		"name": sname if sname != "" else String(SPECIES_LABEL.get(sp, "")),
		"art_id": int(inh.get("art_id", sp)),
		"element": inh.get("element", null),
	}}]
	_reveal_eggs("소환진이 빛나고, %s의 알이 되어 둥지에 놓였습니다.")


## 개체 표시명 — 별명이 있으면 별명, 없으면 종 이름. 커스텀 종은 마스터 이름이 비어 있어
## (플레이어 선택권 드래곤) 물려받은 별명이 없으면 안내 문구로 떨어진다.
func _dragon_label(d: Dictionary) -> String:
	if d.is_empty():
		return ""
	var nick := String(d.get("nickname", ""))
	if nick != "":
		return nick
	var nm := String(Data.get_dragon(int(d.get("id", 0))).get("name", ""))
	return nm if nm != "" else "이름 없는 드래곤"


## 개체 초상 — 커스텀 종(600·700)은 물려받은 아트 id 로 그린다(`Icons.art_id_of`).
func _dragon_portrait(d: Dictionary, box: float) -> Control:
	if d.is_empty():
		return null
	var aid := Icons.art_id_of(d)
	var stage := "egg" if UserDB.is_egg(d) else Growth.stage_for_level(int(d.get("level", 1)))
	var frame := ("dragon_dragon_%d_egg" % aid) if stage == "egg" \
		else ("dragon_dragon_%d_box_%s" % [aid, stage])
	var p := "res://assets/converted/portrait_%d/%s.tres" % [aid, frame]
	if not ResourceLoader.exists(p):
		p = "res://assets/converted/portrait_%d/dragon_dragon_%d_box_adult.tres" % [aid, aid]
	if not ResourceLoader.exists(p):
		return null
	# ⚠️ 껍데기 Control 로 감싸고 그림을 그 안에서 −box/2 만큼 당긴다.
	#    그래야 호출부가 `position` 에 **중심 좌표**를 그대로 넣을 수 있다. 종전처럼 TextureRect 를
	#    직접 돌려주면 호출부의 position 대입이 그 오프셋을 덮어써 그림이 우하단으로 밀렸다
	#    (2026-07-30 목록 스크린샷에서 초상이 행 밖으로 삐져나온 원인).
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.texture = load(p)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.size = Vector2(box, box)
	tr.position = Vector2(-box * 0.5, -box * 0.5)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tr)
	return holder


## 목록 행 안의 실행 버튼 — 공용 헬퍼(`AtlasUI.frame_button`)로 원작 `RoundedButton`
## (= `9patch/btn*` Scale9)을 그린다. 연구소 화면도 같은 헬퍼를 쓴다.
func _frame_button(parent: Control, text: String, pos: Vector2, sz: Vector2, cb: Callable,
		kind := 0, disabled := false) -> Control:
	return AtlasUI.frame_button(parent, text, pos, sz, cb, kind, disabled)

# ── 소울젬 승급/강화(UpgradeSoulGemLayer) ──────────────────────────────────
## 원작 `UpgradeSoulGemLayer` (`<MagicAlchemy_menu6>` = "소울젬 승급/강화").
##
## 🔀 2026-07-31 복구 — CLAUDE.md §10 이 "2016 지하 스샷에 없다 ⇒ 후기 추가분 ⇒ 항목 삭제"로
##   적어 뒀지만, 사용자가 준 참조 영상 `docs/ref/gem/소울젬1.png` 의 지하 6칸에 이 카드가
##   실재한다. 없는 것은 **카드 아이콘(`alchemy/icon_soul`)뿐**이라 항목을 되살렸다.
##
## 원작 배치(`initWidget` 리터럴, 좌표는 창 로컬 cocos → 여기선 y 를 뒤집었다):
##   · `9patch/pop_title_bg` (w×0.9) @ (w/2, h−50) + 제목 + `common/btn_info`
##   · `9patch/scroll_box` cap(65,65,6,6) **(w×0.9, h×0.5)** @ (w/2, h/2) — 본체 상자
##   · `scene/magicshop/gem_bg` 육각 대상 칸 @ (w×0.13, h/2)
##   · `common/plus` @ (w/2 − 183, h/2)
##   · 재료 칸 3개(가운데)
##   · `common/btn_fold` **rotation 90°** @ (w/2 + 183, h/2)
##   · `scene/magicshop/element_bg` 결과 판 @ (w×0.87, h/2)
##   · `RoundedButton(205×56, onClickUpgrade)` + `common/coin_small1` 비용
##
## 규칙(위키 `<ToolTipSoulGemAlchemyExplain>` + `data/gems.json`):
##   · **19등급(최대 티어) 혼성젬을 승급**하면 소울젬이 된다 — `upgrade.promote.gold`(100만).
##   · 소울젬 강화는 **실패하지 않는다**. 단계 1~10, 비용은 `upgrade.soul_steps`
##     (참조 영상 `소울젬4.png` = 9단계 900,000골드 + 가루 2000 + 발록재료 6 + 핵 1 과 일치).
##   · 결과 이름/수치도 검산됐다 — 참조 결과창 "공격의 소울젬 [38/16/3]" =
##     `gems.json` 공격의 소울젬 tier 8 (att 38 / att_pct 16 / cri 3).
## 단계표 재료 코드 → 아이템 키. 표는 `data/gems.json` `upgrade.soul_mat_items`
## (`dust` 는 젬 계열에 따라 갈리므로 여기서 정한다). **빈 값 = 그 재료 요구 생략** —
## 위키가 말하는 '발록 재료'에 해당하는 아이템이 우리 items.json 에 없다(있는 건 발록의 핵뿐).
func _soul_mat_item(code: String) -> String:
	return String((Data.gems.get("upgrade", {}) as Dictionary)
		.get("soul_mat_items", {}).get(code, ""))

func _body_soul(pop: OrigPopup) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var S := Design.ASSET_SCALE
	var midy := H * 0.5

	# 본체 상자 — `9patch/scroll_box` (w×0.9, h×0.5) 중앙.
	var bw := W * 0.9
	var bh := H * 0.5
	var box := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", Vector2(bw, bh), Rect2(65, 65, 6, 6))
	if box:
		box.position = Vector2(W * 0.5 - bw * 0.5, midy - bh * 0.5)
		pop.content.add_child(box)

	# 대상 칸(육각) @ (w×0.13, h/2)
	var hex := AtlasUI.size_pt("magicshop_ui", "scene_magicshop_gem_bg") * 0.72
	var slot := Control.new()
	slot.size = hex
	slot.position = Vector2(W * 0.13, midy) - hex * 0.5
	pop.content.add_child(slot)
	var hbg := _spr("gem_bg", S * 0.72)
	if hbg:
		hbg.position = hex * 0.5
		slot.add_child(hbg)
	var cur := Gem.parse_item_key(_soul_key) if _soul_key != "" else {}
	if cur.is_empty():
		var hint := Label.new()
		hint.text = "젬"
		hint.add_theme_font_size_override("font_size", 18)
		hint.add_theme_color_override("font_color", Color(0.42, 0.30, 0.18))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hint.size = hex
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(hint)
	else:
		var gi := Icons.rect(Icons.gem_texture(
			String(Gem.gem_def(String(cur["name"]), Data.gems).get("code", "")),
			int(cur["tier"])), hex.x * 0.66)
		if gi:
			gi.position = (hex - gi.size) * 0.5
			slot.add_child(gi)
	var sb := Button.new()
	sb.flat = true
	sb.size = hex
	sb.pressed.connect(func(): _open_gem_picker("soul", func(k: String):
		_soul_key = k
		_refresh_feature()))
	slot.add_child(sb)

	# + / ▶
	var plus := AtlasUI.spr("common_ui", "common_plus", S * 0.8)
	if plus:
		plus.position = Vector2(W * 0.5 - 183.0, midy)
		pop.content.add_child(plus)
	var fold := AtlasUI.spr("common_ui", "common_btn_fold", S * 0.8)
	if fold:
		fold.rotation = deg_to_rad(90.0)
		fold.position = Vector2(W * 0.5 + 183.0, midy)
		pop.content.add_child(fold)

	# 재료 3칸(가운데)
	var plan := _soul_plan()
	var mats: Array = plan.get("mats", [])
	for i in mats.size():
		var m: Dictionary = mats[i]
		# 재료 칸은 개수가 1~3으로 변하므로 **묶음 자체를 가운데** 놓는다
		# (참조 `docs/ref/gem/소울젬4.png` 도 대상↔결과 사이 한가운데다).
		var c := Vector2(W * 0.5 + (float(i) - (float(mats.size()) - 1.0) * 0.5) * 100.0, midy)
		var cell := Panel.new()
		cell.size = Vector2(86.0, 92.0)
		cell.position = c - cell.size * 0.5
		var sbf := StyleBoxFlat.new()
		sbf.bg_color = Color(0, 0, 0, 0.32)
		sbf.corner_radius_top_left = 12; sbf.corner_radius_top_right = 12
		sbf.corner_radius_bottom_left = 12; sbf.corner_radius_bottom_right = 12
		cell.add_theme_stylebox_override("panel", sbf)
		pop.content.add_child(cell)
		var ip := Data.item_icon_path(String(m["key"]))
		if ip != "" and ResourceLoader.exists(ip):
			var ic := Sprite2D.new()
			ic.texture = load(ip)
			ic.material = _pma
			ic.scale = Vector2(0.36, 0.36)
			ic.position = Vector2(43.0, 38.0)
			cell.add_child(ic)
		var nl := Label.new()
		var have := UserDB.item_count(String(m["key"]))
		var need := int(m["need"])
		nl.text = "%d/%d" % [mini(have, need), need]
		nl.add_theme_font_size_override("font_size", 15)
		nl.add_theme_color_override("font_color",
			Color(0.85, 1.0, 0.85) if have >= need else Color(1.0, 0.62, 0.55))
		nl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		nl.add_theme_constant_override("outline_size", 4)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.position = Vector2(0, 68.0)
		nl.size = Vector2(86.0, 22.0)
		cell.add_child(nl)

	# 결과 판 @ (w×0.87, h/2)
	var ebg := _spr("element_bg", S * 0.85)
	if ebg:
		ebg.position = Vector2(W * 0.87, midy)
		pop.content.add_child(ebg)
	var res_name := String(plan.get("result_name", ""))
	if res_name != "":
		var rg := Icons.rect(Icons.gem_texture(String(plan.get("result_code", "")),
			int(plan.get("result_tier", 0))), 66.0)
		if rg:
			rg.position = Vector2(W * 0.87, midy) - rg.size * 0.5
			pop.content.add_child(rg)
	var rl := Label.new()
	rl.text = res_name if res_name != "" else "소울젬"
	rl.add_theme_font_size_override("font_size", 15)
	rl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.position = Vector2(W * 0.87 - 110.0, midy + bh * 0.5 - 34.0)
	rl.size = Vector2(220.0, 22.0)
	pop.content.add_child(rl)

	# 안내 + 실행 버튼
	var msg := String(plan.get("msg", ""))
	if msg != "":
		var ml := Label.new()
		ml.text = msg
		ml.add_theme_font_size_override("font_size", 15)
		ml.add_theme_color_override("font_color", Color(0.82, 0.78, 0.92))
		ml.add_theme_color_override("font_outline_color", Color(0.06, 0.03, 0.12, 0.9))
		ml.add_theme_constant_override("outline_size", 4)
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ml.position = Vector2(60.0, midy + bh * 0.5 + 6.0)
		ml.size = Vector2(W - 120.0, 44.0)
		pop.content.add_child(ml)

	var gold := int(plan.get("gold", 0))
	var can := bool(plan.get("ok", false))
	var btn := _frame_button(pop.content, _comma(gold) if gold > 0 else "승급/강화",
		Vector2(W * 0.5 - 102.0, H - 84.0), Vector2(205.0, 56.0), _soul_run, 0, not can)
	if gold > 0:
		var coin := AtlasUI.spr("common_ui", "common_coin_small1", S * 0.9)
		if coin:
			coin.position = Vector2(28.0, 28.0)
			btn.add_child(coin)


## 지금 선택으로 무엇이 되는가 — {ok, gold, mats:[{key,need}], result_*, msg}.
## 원작 `settingGem` + `settingUpgradeButton` 이 하던 판정.
func _soul_plan() -> Dictionary:
	var out := {"ok": false, "gold": 0, "mats": [], "result_name": "", "result_code": "",
		"result_tier": 0, "msg": "승급할 19등급 혼성젬이나 강화할 소울젬을 고르세요."}
	if _soul_key == "":
		return out
	var g := Gem.parse_item_key(_soul_key)
	if g.is_empty():
		return out
	var nm := String(g["name"])
	var tier := int(g["tier"])
	var gd: Dictionary = Gem.gem_def(nm, Data.gems)
	var up: Dictionary = Data.gems.get("upgrade", {})
	if String(gd.get("category", "")) == "soul":
		# 강화 — 단계표(soul_steps). 원작: 실패하지 않는다.
		var steps: Array = up.get("soul_steps", [])
		if tier + 1 >= steps.size():
			out["msg"] = "이미 최대 단계입니다."
			out["result_name"] = Gem.display_name(nm, tier, Data.gems)
			out["result_code"] = String(gd.get("code", ""))
			out["result_tier"] = tier
			return out
		var st: Dictionary = steps[tier + 1]
		out["gold"] = int(st.get("gold", 0))
		out["mats"] = _soul_mats(st, nm)
		out["result_name"] = Gem.display_name(nm, tier + 1, Data.gems)
		out["result_code"] = String(gd.get("code", ""))
		out["result_tier"] = tier + 1
		out["msg"] = "소울젬 강화는 실패하지 않습니다."
		out["ok"] = _soul_afford(int(out["gold"]), out["mats"])
		return out
	# 승급 — 최대 티어 혼성젬만.
	var to_code := String(gd.get("promote_to", ""))
	if to_code == "" or tier < Gem.max_tier(nm, Data.gems):
		out["msg"] = "최대 등급(19)의 혼성젬만 소울젬으로 승급할 수 있습니다."
		return out
	var to_name := Gem.name_of_code(to_code, Data.gems)
	out["gold"] = int((up.get("promote", {}) as Dictionary).get("gold", 1000000))
	out["mats"] = _soul_mats((up.get("soul_steps", [{}]) as Array)[0], to_name)
	out["result_name"] = Gem.display_name(to_name, 0, Data.gems)
	out["result_code"] = to_code
	out["result_tier"] = 0
	out["msg"] = "19등급 혼성젬을 소울젬으로 승급합니다."
	out["ok"] = _soul_afford(int(out["gold"]), out["mats"])
	return out


## 단계표 한 줄 → 재료 목록. 가루는 그 소울젬 계열(공/방/체)의 가루를 쓴다.
##
## 원작 세 칸의 정체(위키 item.pdf p18, `build_gems.py` SOUL_MAT_ITEMS 주석):
##   core = 발록의 핵 · dust = 마법가루(축별) · mat = 카이저 발록의 파편/발톱/뿔(축별).
## 부위 3종은 우리 items.json 에 없어 🟦 사용자 확정으로 `mat` 도 발록의 핵을 쓴다.
## ⇒ 같은 키가 두 칸에 걸리므로 **한 칸으로 합쳐** 필요 개수를 더한다(칸마다 따로 세면
##   같은 아이템의 보유량을 두 번 재게 돼 판정이 틀린다).
func _soul_mats(step: Dictionary, gem_name: String) -> Array:
	var order: Array = []
	var need: Dictionary = {}
	for row in [[Gem.dust_key_for(gem_name), int(step.get("dust", 0))],
			[_soul_mat_item("mat"), int(step.get("mat", 0))],
			[_soul_mat_item("core"), int(step.get("core", 0))]]:
		var k := String((row as Array)[0])
		var n := int((row as Array)[1])
		if k == "" or n <= 0:
			continue
		if not need.has(k):
			order.append(k)
			need[k] = 0
		need[k] = int(need[k]) + n
	var out: Array = []
	for k in order:
		out.append({"key": k, "need": int(need[k])})
	return out


func _soul_afford(gold: int, mats: Array) -> bool:
	if UserDB.gold() < gold:
		return false
	for m in mats:
		if UserDB.item_count(String((m as Dictionary)["key"])) < int((m as Dictionary)["need"]):
			return false
	return true


## 원작 `requestSoulGemMakeAndUpgrade` → `responseSoulGemMakeAndUpgrade`.
func _soul_run() -> void:
	var plan := _soul_plan()
	if not bool(plan.get("ok", false)) or _soul_key == "":
		return
	if not UserDB.spend("gold", int(plan["gold"])):
		return
	for m in (plan["mats"] as Array):
		UserDB.use_item(String((m as Dictionary)["key"]), int((m as Dictionary)["need"]))
	UserDB.use_item(_soul_key, 1)
	var g := Gem.parse_item_key(_soul_key)
	var new_name := Gem.name_of_code(String(plan["result_code"]), Data.gems)
	if new_name == "":
		new_name = String(g["name"])
	var new_key := Gem.item_key(new_name, int(plan["result_tier"]))
	UserDB.add_item(new_key, 1)
	_soul_key = new_key
	_refresh_feature()
	GetItemPopup.open(self, [{"key": new_key, "count": 1}])
	_toast("%s!" % String(plan["result_name"]), 4)


# ── 젬 고르기(원작 `MagicSelectLayer`) ─────────────────────────────────────
## 원작 클래스 확정(2026-07-31): `UpgradeGemLayer::onClickItemMenu` 가 여는 것은
## **`MagicSelectLayer`** 다(`GemsPopup` 은 `CaveScene` 전용 — `::create` 호출자 전수 확인).
## 그릇 = `9patch/popup4` + `9patch/scroll_box` 격자(셀 라벨 `"x %d"`) + 우측 상세
## (`common/shadow` + `9patch/text_box`) + `선택`, 수량은 `common/btn_up`·`btn_down`.
## 참조 `docs/ref/gem/젬분해2~3.png`.
##
## 수량 규칙 = 원작 `MagicSelectLayer::onClickCount` 그대로 **1 ↔ max 순환**:
##   ▼(tag 1): cnt == 1 이면 max 로, 아니면 cnt-1
##   ▲(tag 2): cnt == max 이면 1 로, 아니면 cnt+1
## `max` 는 보유량이다(원작이 `"cnt"/"max"/"label"` 3키를 셀 딕셔너리에 들고 다닌다).
##
## `mode` = "soul" 이면 **승급 가능한 최대티어 혼성젬 + 소울젬**만 보이고 수량칸이 없다
## (원작 `UpgradeSoulGemPopup` 은 1개만 고른다). 그 외에는 수량을 함께 고르고
## `on_pick.call(key, cnt)` 로 돌려준다.
func _open_gem_picker(mode: String, on_pick: Callable, dis_slot := -1) -> void:
	var pick_qty := mode != "soul"
	var vis := _vis()
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.z_index = 80
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)

	var sz := Vector2(minf(880.0, vis.x - 40.0), vis.y - 80.0)
	var win := Control.new()
	win.size = sz
	win.position = ((vis - sz) * 0.5).round()
	layer.add_child(win)
	var fr := AtlasUI.nine("ninepatch_ui", "9patch_popup4", sz, Rect2(130, 190, 40, 58))
	if fr:
		win.add_child(fr)
	var t := Label.new()
	t.text = "젬"                                   # <gem>
	t.add_theme_font_size_override("font_size", 26)
	t.add_theme_color_override("font_color", Color.WHITE)
	t.add_theme_color_override("font_outline_color", Color(0.35, 0.14, 0.03, 0.95))
	t.add_theme_constant_override("outline_size", 5)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.position = Vector2(0, 26.0)
	t.size = Vector2(sz.x, 40.0)
	win.add_child(t)
	var cb := TextureButton.new()
	var ct := AtlasUI.tex("common_ui", "common_close_btn")
	if ct:
		cb.texture_normal = ct
		cb.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 1.3
	cb.position = Vector2(sz.x - 76.0, 24.0)
	cb.pressed.connect(func(): layer.queue_free())
	win.add_child(cb)

	# 원작 비율: 격자는 `창너비 - 430`(우측 상세 350 + 여백), 상세는 350 폭.
	var det_w := 330.0
	var box_sz := Vector2(sz.x - 90.0 - (det_w + 20.0 if pick_qty else 0.0), sz.y - 160.0)
	var np := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", box_sz, Rect2(65, 65, 6, 6))
	if np:
		np.position = Vector2(45.0, 80.0)
		win.add_child(np)
	var sc := ScrollContainer.new()
	sc.position = Vector2(58.0, 92.0)
	sc.size = box_sz - Vector2(26.0, 26.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = maxi(1, int(sc.size.x / 104.0))
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	sc.add_child(grid)

	# 우측 상세 — 고른 젬 하나를 크게 + 수량 ▲▼ + 설명 + [선택].
	var det: Control = null
	var state := {"key": "", "cnt": 1, "max": 1}
	if pick_qty:
		det = Control.new()
		det.size = Vector2(det_w, box_sz.y)
		det.position = Vector2(sz.x - 45.0 - det_w, 80.0)
		win.add_child(det)

	var rows := 0
	for k in UserDB.inventory().keys():
		var key := String(k)
		var g := Gem.parse_item_key(key)
		if g.is_empty() or UserDB.item_count(key) <= 0:
			continue
		var nm := String(g["name"])
		var gd: Dictionary = Gem.gem_def(nm, Data.gems)
		if mode == "soul":
			# 원작 `UpgradeSoulGemPopup::ableGemCheck` — 최대티어 혼성젬(샌즈 포함) 또는
			# 아직 최대가 아닌 소울젬만 목록에 들어간다.
			var is_soul := String(gd.get("category", "")) == "soul"
			var soul_ok := is_soul and int(g["tier"]) + 1 < Gem.max_tier(nm, Data.gems) + 1
			var promotable := String(gd.get("promote_to", "")) != "" \
				and int(g["tier"]) >= Gem.max_tier(nm, Data.gems)
			if not (soul_ok or promotable):
				continue
		# 같은 스택을 이미 다른 칸이 다 쓰고 있으면 고를 게 없다.
		if pick_qty and dis_slot >= 0 \
				and UserDB.item_count(key) - _dis_used_elsewhere(key, dis_slot) <= 0:
			continue
		rows += 1
		grid.add_child(_gem_pick_cell(key, g, layer, on_pick, det, state, dis_slot))
	if rows == 0:
		var e := Label.new()
		e.text = "고를 수 있는 젬이 가방에 없습니다."
		e.add_theme_font_size_override("font_size", 18)
		e.add_theme_color_override("font_color", Color(0.42, 0.30, 0.18))
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.position = Vector2(45.0, 80.0 + box_sz.y * 0.5 - 14.0)
		e.size = Vector2(box_sz.x, 28.0)
		win.add_child(e)


func _gem_pick_cell(key: String, g: Dictionary, layer: Control, on_pick: Callable,
		det: Control = null, state: Dictionary = {}, dis_slot := -1) -> Control:
	var cell := Panel.new()
	cell.custom_minimum_size = Vector2(98.0, 104.0)
	var sbf := StyleBoxFlat.new()
	sbf.bg_color = Color(0, 0, 0, 0.32)
	sbf.corner_radius_top_left = 12; sbf.corner_radius_top_right = 12
	sbf.corner_radius_bottom_left = 12; sbf.corner_radius_bottom_right = 12
	cell.add_theme_stylebox_override("panel", sbf)
	var nm := String(g["name"])
	var gi := Icons.rect(Icons.gem_texture(
		String(Gem.gem_def(nm, Data.gems).get("code", "")), int(g["tier"])), 58.0)
	if gi:
		gi.position = Vector2(20.0, 10.0)
		cell.add_child(gi)
	var n := Label.new()
	n.text = "X %d" % UserDB.item_count(key)
	n.add_theme_font_size_override("font_size", 15)
	n.add_theme_color_override("font_color", Color(1, 1, 1))
	n.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	n.add_theme_constant_override("outline_size", 4)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.position = Vector2(0, 76.0)
	n.size = Vector2(98.0, 22.0)
	cell.add_child(n)
	cell.tooltip_text = Gem.display_name(nm, int(g["tier"]), Data.gems)
	var b := Button.new()
	b.flat = true
	b.size = Vector2(98.0, 104.0)
	if det == null:
		# 수량 없는 모드(소울젬) — 원작도 셀을 누르면 바로 확정한다.
		b.pressed.connect(func():
			layer.queue_free()
			on_pick.call(key))
	else:
		# 원작 `onClickItem`: 셀을 누르면 **우측 상세만** 갱신되고, 확정은 [선택] 이다.
		b.pressed.connect(func():
			var cap := UserDB.item_count(key)
			if dis_slot >= 0:
				cap -= _dis_used_elsewhere(key, dis_slot)
			state["key"] = key
			state["max"] = maxi(1, cap)
			state["cnt"] = 1
			_gem_pick_detail(det, layer, state, on_pick))
	cell.add_child(b)
	return cell


## 우측 상세 패널 — 원작 `MagicSelectLayer::initWidget` 의 오른쪽 CCLayer(350×420).
## 이름 라벨 · `common/shadow` 위의 큰 젬 · `9patch/text_box` 설명 · [선택],
## 그리고 그 왼쪽에 `common/btn_up`/`btn_down` 수량 ▲▼(참조 `docs/ref/gem/젬분해3.png`).
func _gem_pick_detail(det: Control, layer: Control, state: Dictionary, on_pick: Callable) -> void:
	for c in det.get_children():
		c.queue_free()
	var key := String(state.get("key", ""))
	if key == "":
		return
	var g := Gem.parse_item_key(key)
	if g.is_empty():
		return
	var nm := String(g["name"])
	var tier := int(g["tier"])
	var S := Design.ASSET_SCALE
	var W := det.size.x
	var cnt := clampi(int(state.get("cnt", 1)), 1, int(state.get("max", 1)))
	state["cnt"] = cnt

	# 제목 — "공격력의 젬+28"
	var t := Label.new()
	t.text = Gem.display_name(nm, tier, Data.gems)
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", Color.WHITE)
	t.add_theme_color_override("font_outline_color", Color(0.35, 0.14, 0.03, 0.95))
	t.add_theme_constant_override("outline_size", 5)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.position = Vector2(0, 6.0)
	t.size = Vector2(W, 34.0)
	det.add_child(t)

	# 큰 젬 + 그림자
	var cx := W * 0.62
	var cy := 130.0
	var sh := AtlasUI.spr("common_ui", "common_shadow", S)
	if sh:
		sh.position = Vector2(cx, cy + 58.0)
		det.add_child(sh)
	var big := Icons.rect(Icons.gem_texture(
		String(Gem.gem_def(nm, Data.gems).get("code", "")), tier), 132.0)
	if big:
		big.position = Vector2(cx, cy) - big.size * 0.5
		det.add_child(big)

	# 수량 ▲ / 숫자 / ▼ — 원작 tag 2 = btn_up, tag 1 = btn_down, 1↔max 순환.
	var mx := int(state.get("max", 1))
	var ax := W * 0.16
	var up := _pick_arrow(det, "common_btn_up", Vector2(ax, cy - 62.0), func():
		state["cnt"] = 1 if cnt == mx else cnt + 1
		_gem_pick_detail(det, layer, state, on_pick))
	var dn := _pick_arrow(det, "common_btn_down", Vector2(ax, cy + 62.0), func():
		state["cnt"] = mx if cnt == 1 else cnt - 1
		_gem_pick_detail(det, layer, state, on_pick))
	up.disabled = mx <= 1
	dn.disabled = mx <= 1
	var num := Label.new()
	num.text = str(cnt)
	num.add_theme_font_size_override("font_size", 26)
	num.add_theme_color_override("font_color", Color(1.0, 0.83, 0.20))
	num.add_theme_color_override("font_outline_color", Color(0.25, 0.10, 0.02, 0.95))
	num.add_theme_constant_override("outline_size", 5)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.position = Vector2(ax - 50.0, cy - 18.0)
	num.size = Vector2(100.0, 36.0)
	det.add_child(num)

	# 설명 — 원작은 `Item::getComment()` 를 `9patch/text_box` 스크롤에 넣는다.
	var tb := AtlasUI.nine("ninepatch_ui", "9patch_text_box",
		Vector2(W - 10.0, 118.0), Rect2(25, 25, 3, 3))
	if tb:
		tb.position = Vector2(5.0, cy + 108.0)
		det.add_child(tb)
	# ⚠️ 원작은 여기에 `Item::getComment()`(서버 `info_item` 의 설명문)를 넣는다 — 그 문구는
	#   유실이라 지어내지 않고 효과 문구 + 단계 표기만 낸다(HARD RULE 6).
	var cm := Label.new()
	cm.text = "%s\n%s" % [Gem.effect_text(nm, tier, Data.gems),
		Gem.shape_label(nm, tier, Data.gems)]
	cm.add_theme_font_size_override("font_size", 15)
	cm.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	cm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cm.position = Vector2(20.0, cy + 120.0)
	cm.size = Vector2(W - 40.0, 96.0)
	det.add_child(cm)

	# [선택] — 원작 `onClickOk`.
	_frame_button(det, "선택", Vector2(W * 0.5 - 92.0, det.size.y - 74.0),
		Vector2(184.0, 54.0), func():
			layer.queue_free()
			on_pick.call(key, int(state["cnt"])), 0, false)


## `common/btn_up`·`btn_down` 스프라이트 버튼 한 개(중심 좌표로 놓는다).
func _pick_arrow(parent: Control, frame: String, center: Vector2, cb: Callable) -> TextureButton:
	var b := TextureButton.new()
	var tx := AtlasUI.tex("common_ui", frame)
	if tx:
		b.texture_normal = tx
		b.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
		b.position = center - tx.get_size() * Design.ASSET_SCALE * 0.5
	else:
		b.position = center - Vector2(20, 14)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# ── 공용 위젯 ──────────────────────────────────────────────────────────────
func _note(text: String) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.82, 0.78, 0.92))
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.03, 0.12, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(500, 0)
	return l

func _kv_row(name: String, value: String, ok: bool) -> Control:
	var row := Control.new(); row.custom_minimum_size = Vector2(0, 44)
	var bgn := _row_bg(520, 44)
	if bgn: row.add_child(bgn)
	var l := Label.new(); l.text = name
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.95, 0.92, 1.0))
	l.position = Vector2(18, 11); row.add_child(l)
	var v := Label.new(); v.text = value
	v.add_theme_font_size_override("font_size", 16)
	v.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if ok else Color(1.0, 0.6, 0.55))
	v.position = Vector2(380, 11); row.add_child(v)
	return row

## 안내는 원작대로 하단 대사창(BottomTextBox::setString)으로 낸다.
func _toast(msg: String, emo := 0) -> void:
	_say(msg, emo)
