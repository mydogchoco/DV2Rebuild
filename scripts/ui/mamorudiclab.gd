extends Control
## 마모루딕 연구소(우노) — 원작 `DragonAwaken` 이식. render 층(CLAUDE.md §8).
##
## ⚠️ 엘피스 연구소(애니, `LaboratoryScene` → scripts/ui/laboratory.gd)와 **다른 곳**이다.
##
## 포팅 카드: `docs/ref/porting/MamorudicLab.md`
##
## ── 원작 구조 (`docs/ref/orig_code/decomp/DragonAwaken.c`, `[skip>8000]` 0건 = 전부 살아 있다)
##
## `init(kind, …)` 은 **탭 하나짜리 씬**이다. 탭을 바꾸면 씬을 통째로 replaceScene 한다
## (`onClickTap` @01467240 → `DragonAwaken::scene(kind, …)`).
##   kind 0 = 드래곤 각성   → `awakenStand()`
##   kind 1 = 각성마석 제작 → `masicBrazier()` + `drawMasicStoneInfo()` + `refreshStoneInfo()`
## 그리고 어느 쪽이든 `drawBase()` + `drawNpcMamorudic()` 을 부른다.
##
## `drawBase` (@01462... 전문 확인):
##   · `scene/mamorudiclab/money_bg_mamo.png` anchor(1,1) @ visibleRect.topRight-(10,30), tag 0x69
##     └ `common/coin_small1`@(40,85) · `common/diamond_small1`@(40,45)
##     └ 골드/다이아 라벨 font_subtitle scale 0.9, anchor(0,0.5) @(65,88)/(65,48), tag 0x6a/0x6b
##     └ `common/charge.png` 메뉴아이템 anchor(1,0.5) @(width-20, 45)
##   · `TitleLayer::create("scene/mamorudiclab/mamo_top_title_bg.png", <제목>, this, onClickClose)`
##   · 탭 2개 = `TabImage::create("common/tab_bg.png", getImagePath("…/txt_dragon_evolution1_%s.png"))`
##             + 같은 방식의 `…/txt_evolution_make2_%s.png` → `setTabImageMenus(onClickTap)`
##             → `TabMenu::setMenuPosX(50)` · `setTabMenusForce(현재 kind)`
##   · `common/back_btn.png` `CCMenuItemImageEx` scale 1.2 @ VisibleRect::leftTop()+(50,-35), z=1000
##
## `awakenStand` (@01463...):
##   · `machine/bg_black_island.spine_json` **2겹**(tag 0x6c 스케일 1.0 / 0x6d 스케일 z)
##     @ center-(90z, 75z), `setAnimation("animation", loop)`, 통통 튀는 액션
##     (MoveBy ±15 EaseExponentialOut + ScaleTo z∓0.02)
##   · `RoundedButton(1.1, CCSize(240,200), onClickMachine)` = 제단 클릭 → 드래곤 선택
##   · `bt_e_book.png`(scale 1.05) + `9patch/recall_del` 명찰("각성 도감") → 각성 도감
##
## `masicBrazier` (@01463c...):
##   · `furnace/furnace_normal.spine_json` tag 100 @ center-(110z, 40z), `setAnimation("animation", loop)`
##   · `RoundedButton(1.1, CCSize(200,200), onclickDoor)` @ 본 `furnace_b1`
##   · `common/finger.png` @ 본+(50,0), ScaleTo 1.2↔0.9 반복
##
## `drawMasicStoneInfo` (@00bb43c0):
##   · `scene/laboratory/lv_bg.png` Scale9 450×40 anchor(0.5,0) @(visW/2, 170), z=1000
##   · 라벨(scale 0.85) + `common/bar_bg2`(scaleX 1.3) + `common/bar_exp` CCProgressTimer(BAR)
##     + "%d/%d" 라벨 + `RoundedButton(100×56, onClickChage)`("정보"/변경)
##
## `drawNpcTalk(kind)`: kind==1 → `MamorudicLabTalkAwake_%d`, 그 외 → **언제나**
##   `MamorudicLabTalk_1_%d`(탭 무관). → `data/npc_talk.json` `mamorudic.*`
##
## ── 🔴 2026-07-29 이전 구현에서 고친 것
## 종전에는 마법진 둘레에 **자작 4아이콘 메뉴**(진화/스킬제작/아티팩트조합/스킬분해)를 두고
## 두 스파인의 용도를 반대로 알고 있었다:
##   · `machine/bg_black_island` = "분해기"(✗) → **각성 제단**(○)
##   · `furnace/furnace_normal`  = "스킬 제작"(✗) → **각성마석 화로**(○)
## 스킬 제작/분해는 이 화면 소유가 아니다 — 스킬은 가방의 스킬 탭에서 다룬다
## (`docs/ref/porting/SkillScroll.md`). `MakeSkillLayer` 를 부르는 클래스는 디컴프 397종
## 어디에도 없다(후기판 `MamorudicLab` 소유로 보이며 그 클래스는 심볼맵에도 없다).

const DIR_UI := "mamorudiclab_ui"
const BG := "res://assets/converted/mamorudiclab_bg/mamorudic_bg.jpg"

## 원작 `MamorudicLabKind`. 씬 진입 인자 `tab` 이 이 값이다.
const KIND_AWAKEN := 0
const KIND_STONE := 1
## 후기판 `MamorudicLab` 메인(양피지 카드 메뉴). 클래스가 디컴프·심볼맵에 없어 배치는
## 레퍼런스 `docs/ref/uno/연구소메인.png` 실측(§6 우선순위 3 — 관찰) + 보유 자산
## (`mamo_sub_title_bg` 양피지 카드 · `icon_dragon_evolution/artifact_mix/evolution_make`)이다.
## 진입 흐름(사용자 확인 2026-07-29): 지역맵 → **메인** → 카드 → 탭 화면,
## 탭 화면의 ← 는 메인으로, ✖ 는 지역맵으로.
const KIND_MENU := -1

## 원작 탭 라벨 이미지(둘 다 실재 — `asset_index.py --grep mamorudiclab`).
const TABS := [
	{"kind": KIND_AWAKEN, "frame": "txt_dragon_evolution1_kr", "text": "드래곤 각성"},
	{"kind": KIND_STONE, "frame": "txt_evolution_make2_kr", "text": "각성마석 제작"},
]

var _params: Dictionary = {}
var _kind := KIND_AWAKEN
var _pma: CanvasItemMaterial
var _man: Dictionary = {}
var _npc: NpcPortrait
var _box: BottomTextBox
var _gauge: ProgressBar          # 마석 제작 진행 게이지(원작 CCProgressTimer)
var _gauge_lbl: Label

func enter(params: Dictionary = {}) -> void:
	# 사용자 실측(2026-07-28): 우노의 마모루딕 연구소도 유타칸 연구소와 같은
	# `music/bg_laboratory.mp3` 를 쓴다. 원작 `DragonAwaken` 에는 playBackground 호출이
	# 없어(디컴프 확인) 코드로는 확인되지 않는 값이라 관찰(§6 우선순위 3)을 따른다.
	Bgm.play("bg_laboratory")
	_params = params
	# `tab` 없이 들어오면(지역맵에서 진입) 후기판 메인 카드 메뉴부터.
	_kind = int(params.get("tab", KIND_MENU))
	if _pma != null: _rebuild()

func _ready() -> void:
	_pma = AtlasUI.pma()
	_rebuild()

func _vis() -> Vector2:
	return get_viewport_rect().size

## 원작이 스케일 기준으로 쓰는 값 — `winSize.width / 1024`(`awakenStand`/`masicBrazier` 의
## `local_70[0] * 0.0009765625`). 배치 오프셋에 그대로 곱한다.
func _zoom() -> float:
	return _vis().x / 1024.0

func _load_man() -> void:
	if not _man.is_empty(): return
	var p := "res://assets/converted/%s/_manifest.json" % DIR_UI
	if FileAccess.file_exists(p):
		var d = JSON.parse_string(FileAccess.open(p, FileAccess.READ).get_as_text())
		if d is Dictionary: _man = d

func _spr(name: String, scale := 1.0) -> Sprite2D:
	return AtlasUI.spr(DIR_UI, "scene_mamorudiclab_%s" % name, scale)

# ============================================================ 화면 조립

func _rebuild() -> void:
	for c in get_children(): c.queue_free()
	_npc = null; _box = null; _gauge = null; _gauge_lbl = null
	_load_man()
	var vis := _vis()
	# 원작 init: `mamorudic_bg.jpg` 를 화면 중앙에, 폭이 모자라면 winW/1024 로 확대.
	if ResourceLoader.exists(BG):
		var full := TextureRect.new(); full.texture = load(BG)
		full.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		full.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		full.set_anchors_preset(Control.PRESET_FULL_RECT)
		full.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(full)
	else:
		var bg := ColorRect.new(); bg.color = Color(0.06, 0.05, 0.10)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
	if _kind == KIND_MENU:
		_build_menu(vis)
	elif _kind == KIND_STONE:
		_build_brazier(vis)
		_build_stone_info(vis)
	else:
		_build_stand(vis)
	_build_npc(vis)
	_build_base(vis)

## 원작 `drawBase` — 제목바 + 탭 + 재화 + 뒤로.
func _build_base(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	# 제목바(TitleLayer 1번 인자 = mamo_top_title_bg) + 닫기 ✖.
	var tb := _spr("mamo_top_title_bg", S)
	if tb: tb.position = Vector2(vis.x * 0.5, 40.0); tb.z_index = 20; add_child(tb)
	var t1 := Label.new(); t1.text = "마모루딕 연구소"      # <MamorudicLabMsg>
	t1.add_theme_font_size_override("font_size", 32)
	t1.add_theme_color_override("font_color", Color(1.0, 0.83, 0.30))
	t1.add_theme_color_override("font_outline_color", Color(0.20, 0.09, 0.02, 0.95))
	t1.add_theme_constant_override("outline_size", 6)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t1.size = Vector2(vis.x, 42); t1.position = Vector2(0, 18); t1.z_index = 21
	add_child(t1)
	# ✖ 위치는 레퍼런스 실측(`docs/ref/uno/드래곤각성1.png` 1381×785 에서 중심 (1287,44)
	# = 화면비 (0.932, 0.056)). 디컴프의 `TitleLayer::create` 는 좌표를 TitleLayer 안에서
	# 정하는데 그 클래스 배치 코드가 우리 덤프에 없다 → 관찰(§6 우선순위 3)을 따른다.
	var xb := TextureButton.new()
	xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.scale = Vector2(S, S)
	var xw: float = xb.texture_normal.get_width() * S
	var xh: float = xb.texture_normal.get_height() * S
	xb.position = Vector2(vis.x * 0.932 - xw * 0.5, vis.y * 0.056 - xh * 0.5); xb.z_index = 22
	xb.pressed.connect(func(): Scenes.goto("worldmap", {"region": "uno"}))
	add_child(xb)
	# 뒤로 — 원작 `common/back_btn` scale 1.2 @ leftTop+(50,-35). **탭 화면에서만** 그린다
	# (레퍼런스 `연구소메인.png` 메인에는 ✖ 뿐이다) → 메인 카드 메뉴로 돌아간다.
	# ✖ 는 어느 화면에서든 지역맵으로(위). 사용자 보고(2026-07-29): 종전엔 둘 다 지역맵이라
	# 탭에서 메인으로 돌아갈 길이 없었다.
	if _kind != KIND_MENU:
		var back := TextureButton.new()
		back.texture_normal = load("res://assets/converted/common_ui/common_back_btn.tres")
		back.scale = Vector2(1.2 * S, 1.2 * S)
		var bw: float = back.texture_normal.get_width() * 1.2 * S
		var bh: float = back.texture_normal.get_height() * 1.2 * S
		back.position = Vector2(50.0 - bw * 0.5, 35.0 - bh * 0.5); back.z_index = 22
		back.pressed.connect(func():
			_kind = KIND_MENU
			_rebuild())
		add_child(back)
		_build_tabs(vis)
	_build_money(vis)

## 원작 `TitleLayer::setTabImageMenus` + `TabMenu::setMenuPosX(50)`.
## 탭을 누르면 원작은 **씬을 갈아 끼운다**(replaceScene) — 우리는 같은 씬을 다시 조립한다.
func _build_tabs(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var x := 50.0
	for t in TABS:
		var kind := int(t["kind"])
		var on := kind == _kind
		var tab := Control.new()
		tab.z_index = 23
		# 비선택 탭은 살짝 내려 그린다(원작 TabMenu 와 우리 shop.gd::_build_tabs 규약 동일).
		tab.position = Vector2(x, 66.0 + (0.0 if on else 10.0))
		add_child(tab)
		var bgs := AtlasUI.spr("common_ui", "common_tab_bg", S)
		var tw := 120.0 * S
		var th := 64.0 * S
		if bgs:
			tw = bgs.texture.get_width() * S
			th = bgs.texture.get_height() * S
			bgs.position = Vector2(tw * 0.5, th * 0.5)
			bgs.modulate = Color(1, 1, 1) if on else Color(0.68, 0.62, 0.55)
			tab.add_child(bgs)
		var lab := _spr(String(t["frame"]), S)
		if lab:
			lab.position = Vector2(tw * 0.5, th * 0.5)
			lab.modulate = Color(1, 1, 1) if on else Color(0.72, 0.68, 0.62)
			tab.add_child(lab)
		else:
			var l := Label.new(); l.text = String(t["text"])
			l.add_theme_font_size_override("font_size", 17)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.size = Vector2(tw, 22); l.position = Vector2(0, th * 0.5 - 11)
			tab.add_child(l)
		tab.size = Vector2(tw, th)
		if not on:
			var b := Button.new(); b.flat = true; b.size = Vector2(tw, th)
			b.pressed.connect(func():
				_kind = kind
				_rebuild())
			tab.add_child(b)
		x += tw + 6.0

## 원작 drawBase 의 재화 패널 — `money_bg_mamo` anchor(1,1) @ topRight-(10,30).
## 내부 좌표(40,85)/(40,45)/(65,88)/(65,48) 는 **cocos y-up, 패널 로컬**이라 뒤집는다.
func _build_money(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var sz := AtlasUI.size_pt(DIR_UI, "scene_mamorudiclab_money_bg_mamo")
	if sz == Vector2.ZERO: sz = Vector2(300.0, 120.0)
	# ⚠️ 디컴프의 `topRight - (10,30)` 은 Ghidra 가 CCPoint→CCSize→operator- 로 접어 놓아
	#    그대로 쓰면 ✖ 와 겹친다. 레퍼런스 실측(`드래곤각성1.png`: 패널 우변 0.983·W,
	#    윗변 0.111·H)을 따른다 — ✖ 는 패널 **위**에 따로 선다.
	var root := Control.new()
	root.size = sz
	root.position = Vector2(vis.x * 0.983 - sz.x, vis.y * 0.111)
	root.z_index = 24
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var bg := _spr("money_bg_mamo", S)
	if bg: bg.position = sz * 0.5; root.add_child(bg)
	for r in [["common_coin_small1", AtlasUI.comma(UserDB.gold()), 85.0],
			["common_diamond_small1", AtlasUI.comma(UserDB.diamond()), 45.0]]:
		var cy: float = sz.y - float(r[2])
		var ic := AtlasUI.spr("common_ui", String(r[0]), S)
		if ic: ic.position = Vector2(40.0, cy); root.add_child(ic)
		var l := Label.new(); l.text = String(r[1])
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		l.add_theme_color_override("font_outline_color", Color(0.15, 0.09, 0.03))
		l.add_theme_constant_override("outline_size", 5)
		l.position = Vector2(65.0, cy - 15.0)
		l.size = Vector2(sz.x - 90.0, 30.0)
		root.add_child(l)
	# `common/charge` 충전 버튼 — 오프라인이므로 상점의 골드↔다이아 환전으로 보낸다
	# (§10 캐시상점 행: PremiumShopScene 은 결제라 컷, 환전소로 재설계).
	var ch := TextureButton.new()
	ch.texture_normal = load("res://assets/converted/common_ui/common_charge.tres")
	ch.scale = Vector2(S, S)
	var cw: float = ch.texture_normal.get_width() * S
	ch.position = Vector2(sz.x - 20.0 - cw, sz.y - 45.0 - ch.texture_normal.get_height() * S * 0.5)
	ch.pressed.connect(func(): Scenes.goto("shop", {"tab": "exchange"}))
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(ch)

## 원작 `drawNpcMamorudic` — `NpcManager`(마모루딕) + `BottomTextBox`.
func _build_npc(vis: Vector2) -> void:
	_npc = NpcPortrait.create("mamorudic", 1)
	if _npc != null:
		_npc.z_index = 5
		add_child(_npc)
		_npc.position = Vector2(vis.x - 150.0, vis.y)
	_box = BottomTextBox.new()
	_box.max_width = vis.x - 300.0
	_box.z_index = 12
	add_child(_box)
	_box.clicked.connect(func(): _say(_talk("mamorudic.idle")))
	_say(_talk("mamorudic.idle"))

## 대사 풀에서 한 줄. 원작 `drawNpcTalk` 이 `rand()` 로 고르는 것과 같다.
func _talk(key: String) -> String:
	var pool: Array = (Data.npc_talk.get("screen", {}) as Dictionary).get(key, {}).get("lines", [])
	return String(pool[randi() % pool.size()]) if not pool.is_empty() else ""

## 대사 한 줄 + 이름 치환. 🔴 원작 문자열은 **cocos 위치 지정 서식(`%1$s`)** 이라 GDScript 의
## `%` 연산자가 못 읽는다. 게다가 같은 풀 안에서 자리표시자가 있는 줄과 없는 줄이 섞여 있어
## (`mamorudic.success` 2줄 중 1줄만 `%1$s`) `%` 를 쓰면 **"not all arguments converted" 로
## 런타임 에러가 나고, 그 뒤 코드(제작 성공 팝업)가 통째로 실행되지 않았다**(2026-07-30 수정).
## ⇒ `shop.gd::_shop_talk` 과 같은 규약으로 문자열 치환만 한다.
func _talk_fmt(key: String, arg: String) -> String:
	return _talk(key).replace("%1$s", arg)

## 원작 `BottomTextBox::setString` — 이름은 노랑, 본문은 타이프라이터.
## 말하는 동안 입이 움직인다(`NpcManager::setNpcMouse`).
func _say(line: String) -> void:
	if not is_instance_valid(_box) or line == "":
		return
	_box.show_text("마모루딕", line)
	if is_instance_valid(_npc):
		_npc.set_talking(true)
		if not _box.finished.is_connected(_stop_talk):
			_box.finished.connect(_stop_talk)

func _stop_talk() -> void:
	if is_instance_valid(_npc):
		_npc.set_talking(false)

# ============================================================ 메인 — 양피지 카드 메뉴

## 후기판 카드 5장(레퍼런스 순서 그대로). 아이콘은 보유 3종만, 미보유 2종은 글자만.
## 아티펙트 합성·마공학 대장간·아티펙트 제련은 기능 자체가 ⚪미이식(포팅 카드 §7) →
## 어둡게 그리고 누르면 알린다.
const MENU_CARDS := [
	{"title": "드래곤 각성", "icon": "icon_dragon_evolution", "kind": KIND_AWAKEN},
	# 아티펙트 합성은 화면 전환이 아니라 **이 배경 위에 뜨는 팝업**이다(원작 ArtifactMix =
	# PopupLayer, 참조 `docs/ref/uno/아티팩트합성5.png` 에서 아래 대사창이 그대로 보인다).
	{"title": "아티펙트 합성", "icon": "icon_artifact_mix", "kind": -2, "popup": "artifact_mix"},
	{"title": "각성의마석 제작", "icon": "icon_evolution_make", "kind": KIND_STONE},
	{"title": "마공학 대장간", "icon": "", "kind": -2},
	# 🟢 2026-08-01 구현 — 원작 `ArtifactBox`(대상 목록) → `OptionSelectLayer` **모드 2**
	#   (`requestOptionRetry` @011ec164 → `game_lab2/regen_equip_option.hb`).
	#   위키 §2.4: "아티팩트는 마모루딕에게 가져가 아니마와 보네르로 옵션을 돌릴 수 있는데,
	#   이는 기누의 동전에 비해 관통 옵션이 나올 확률이 높다."
	{"title": "아티펙트 제련", "icon": "", "kind": -2, "popup": "artifact_smelt"},
]

## 레퍼런스 `연구소메인.png`(1384×785 → pt /1.134) 실측 배치 — 윗줄 3장 + 아랫줄 2장.
func _build_menu(_vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var k := 0.8 * S          # 카드 폭 실측 137pt / (129px × 4/3)
	var cw := 129.0 * k
	var ch := 169.0 * k
	var centers := [
		Vector2(360.0, 205.0), Vector2(507.0, 205.0), Vector2(654.0, 205.0),
		Vector2(432.0, 414.0), Vector2(578.0, 414.0),
	]
	for i in MENU_CARDS.size():
		var ent: Dictionary = MENU_CARDS[i]
		var c: Vector2 = centers[i]
		var impl := int(ent["kind"]) >= 0 or String(ent.get("popup", "")) != ""
		var card := Control.new()
		card.position = c - Vector2(cw, ch) * 0.5
		card.size = Vector2(cw, ch)
		card.z_index = 6
		if not impl: card.modulate = Color(0.58, 0.55, 0.52)
		add_child(card)
		var bgs := _spr("mamo_sub_title_bg", k)
		if bgs: bgs.position = Vector2(cw, ch) * 0.5; card.add_child(bgs)
		var tl := Label.new()
		tl.text = String(ent["title"])
		tl.add_theme_font_size_override("font_size", 16)
		tl.add_theme_color_override("font_color", Color(0.32, 0.19, 0.07))
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.position = Vector2(0, 16.0); tl.size = Vector2(cw, 22.0)
		card.add_child(tl)
		if String(ent["icon"]) != "":
			var ic := _spr(String(ent["icon"]), 0.75 * S)
			if ic:
				ic.position = Vector2(cw * 0.5, ch * 0.58)
				card.add_child(ic)
		var b := Button.new(); b.flat = true; b.size = Vector2(cw, ch)
		b.pressed.connect(func():
			if String(ent.get("popup", "")) == "artifact_mix":
				_open_artifact_mix()
			elif String(ent.get("popup", "")) == "artifact_smelt":
				_open_artifact_smelt()
			elif impl:
				_kind = int(ent["kind"])
				_rebuild()
			else:
				_say("(%s — 아직 구현되지 않은 기능입니다.)" % String(ent["title"])))
		card.add_child(b)

## 아티펙트 합성(원작 `ArtifactMix`) — 포팅 카드 `docs/ref/porting/ArtifactMix.md`.
## 대상을 안 넘기면 창이 먼저 고르기 층을 띄운다(원작 `ArtifactBox` → `ArtifactMix::create`).
func _open_artifact_mix() -> void:
	var p := ArtifactMixPopup.open(self)
	p.closed.connect(func(): _say("좋은 아티펙트가 나왔길 바라네."))


## 아티펙트 제련(원작 `ArtifactBox` → `OptionSelectLayer` 모드 2) — 대상 고르기.
##
## 원작 목록 조건 = `ArtifactBox::initData` @0143ec2c:
##   `AccountManager::getEquip()` 중 `6000 <= Item::getNo() < 7001`(아티팩트 번호대).
##   우리는 번호 대신 인벤 키가 `artifact:` 인 것으로 가른다(`Equipment.artifact_of`).
## ⚠️ 낀 아티팩트는 우리 인벤에 없다 — 벗겨서 가져와야 한다(원작은 한 배열이라 둘 다 보인다).
##   그 차이는 `docs/ref/porting/ArtifactSmelt.md` 에 적어 뒀다.
func _open_artifact_smelt() -> void:
	var cfg := Equipment.artifact_smelt_cfg(Data.equipment)
	var cost: Dictionary = cfg.get("items", {})
	var rows: Array = []
	for k in UserDB.inventory().keys():
		var key := String(k)
		if Equipment.artifact_of(key).is_empty():
			continue
		if UserDB.item_count(key) <= 0:
			continue
		# 옵션이 0개면 돌릴 것이 없다(일반 등급) — 원작도 등급을 읽어 거른다.
		if int(Equipment.item_key_meta(key).get("rarity", 0)) < 2:
			continue
		rows.append(key)
	rows.sort()

	var pop := OrigPopup.open(self, "아티펙트 제련", Vector2(720.0, 520.0))
	var cost_txt: PackedStringArray = []
	for k in cost:
		cost_txt.append("%s %d" % [Data.item_name(String(k)), int(cost[k])])
	var head := Label.new()
	head.text = "옵션을 다시 굴릴 아티펙트를 고르게.  (1회 %s)" % " · ".join(cost_txt)
	head.add_theme_font_size_override("font_size", 16)
	head.add_theme_color_override("font_color", Color(0.30, 0.18, 0.06))
	head.position = Vector2(40.0, 84.0); head.size = Vector2(640.0, 24.0)
	pop.content.add_child(head)

	var sc := ScrollContainer.new()
	sc.position = Vector2(40.0, 116.0)
	sc.size = Vector2(640.0, 330.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pop.content.add_child(sc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.custom_minimum_size.x = 620.0
	sc.add_child(col)

	if rows.is_empty():
		var none := Label.new()
		none.text = "제련할 아티펙트가 없다네. (레어 등급 이상, 장착은 먼저 벗기게)"
		none.add_theme_font_size_override("font_size", 17)
		none.add_theme_color_override("font_color", Color(0.45, 0.34, 0.22))
		col.add_child(none)
		return

	for key: String in rows:
		var meta: Dictionary = Equipment.item_key_meta(key)
		var it: Dictionary = Equipment.catalog(Data.equipment).get(
			Equipment.parse_item_key(key), {})
		var parts: PackedStringArray = []
		for o in (meta.get("options", []) as Array):
			var od := o as Dictionary
			parts.append("%s+%d" % [String(EquipOptionLayer.STAT_KR.get(
				String(od.get("stat", "")), String(od.get("stat", "")))),
				int(od.get("value", 0))])
		var b := Button.new()
		b.text = "  %s   %s   ×%d" % [String(it.get("name", key)),
			" ".join(parts) if not parts.is_empty() else "(옵션 없음)",
			UserDB.item_count(key)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(func(): _artifact_smelt_confirm(key, pop))
		col.add_child(b)


func _artifact_smelt_confirm(inv_key: String, list_pop: OrigPopup) -> void:
	var cfg := Equipment.artifact_smelt_cfg(Data.equipment)
	var cost: Dictionary = cfg.get("items", {})
	var lack: PackedStringArray = []
	for k in cost:
		if UserDB.item_count(String(k)) < int(cost[k]):
			lack.append("%s %d/%d" % [Data.item_name(String(k)),
				UserDB.item_count(String(k)), int(cost[k])])
	if not lack.is_empty():
		_notice("아티펙트 제련", "재료가 모자라네.\n%s" % " · ".join(lack))
		return
	var grade := int(Equipment.item_key_meta(inv_key).get("rarity", 0))
	var txt: PackedStringArray = []
	for k in cost:
		txt.append("%s X %d" % [Data.item_name(String(k)), int(cost[k])])
	# 원작 확인 문구 <EquipeSelectMsg1>.
	_confirm("아티펙트 제련",
		"해당 장비의 부가 옵션을 변경하시겠습니까?\n\n%s" % " · ".join(txt),
		func():
			for k in cost:
				if not UserDB.use_item(String(k), int(cost[k])):
					return
			if is_instance_valid(list_pop):
				list_pop.queue_free()
			var lay := EquipOptionLayer.open_artifact(self, inv_key, grade)
			lay.finished.connect(func(): _say("관통이 잘 붙었으면 좋겠군.")))


# ============================================================ kind 0 — 드래곤 각성

## 원작 `awakenStand` — 각성 제단(스파인 2겹) + 클릭 히트박스 + 각성 도감 버튼.
func _build_stand(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var z := _zoom()
	# 원작 좌표: visibleRect.size/2 - (90z, 75z) [cocos y-up] → Godot 은 y 를 뒤집는다.
	var at := Vector2(vis.x * 0.5 - 90.0 * z, vis.y * 0.5 + 75.0 * z)
	# 원작은 같은 스파인을 **2겹**(tag 0x6c scale 1.0 / 0x6d scale z)으로 겹친다. 원작 기준
	# 화면(1024 폭)에서는 z==1.0 이라 두 장이 정확히 포개져 밝기만 진해진다 — 우리처럼 폭이
	# 다른 화면에서 z 를 그대로 곱하면 두 장이 어긋나 원반이 겹쳐 보인다(실측). 겹치는 의도를
	# 살리려면 **같은 배율**이어야 하므로 둘 다 ASSET_SCALE 로 그린다.
	for i in 2:
		var sp := _spine("res://scenes/fx/lab_machine.tscn", at, S)
		if sp == null: continue
		# 원작: MoveBy(0.1, +15) EaseExponentialOut → MoveBy(0.1, -15), 동시에 ScaleTo 흔들림.
		var t := sp.create_tween()
		t.tween_property(sp, "position", at - Vector2(0, 15.0), 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
		t.tween_property(sp, "position", at, 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	# 제단 클릭 = 원작 `RoundedButton(CCSize(240,200), onClickMachine)` → 드래곤 선택.
	var hit := Button.new(); hit.flat = true
	hit.size = Vector2(240.0, 200.0)
	hit.position = at - hit.size * 0.5
	hit.pressed.connect(_open_dragon_select)
	add_child(hit)
	# 각성 도감 — `bt_e_book`(scale 1.05) + `9patch/recall_del` 명찰.
	#   원작은 명찰(anchor 0,0)을 좌하단에 두고 책을 그 **바로 위**(midX, maxY + iconH/2)에 놓는다.
	var plate_pos := Vector2(24.0, vis.y - BottomTextBox.BOX_H * Design.ASSET_SCALE - 60.0)
	# ⚠️ `9patch/recall_del` 은 32×20 짜리 작은 프레임이라 cap(20,20,4,4)를 주면 마진이
	#    텍스처를 넘어 아무것도 안 그려진다(실측). 기본 3분할에 맡긴다.
	var plate := AtlasUI.nine("ninepatch_ui", "9patch_recall_del", Vector2(150.0, 44.0))
	if plate:
		plate.position = plate_pos
		plate.z_index = 6
		add_child(plate)
		var pl := Label.new(); pl.text = "각성 도감"        # <AwakenSkill_Info>
		pl.add_theme_font_size_override("font_size", 21)
		pl.add_theme_color_override("font_color", Color(1, 1, 1))
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pl.size = plate.size
		plate.add_child(pl)
	var book := _spr("bt_e_book", 1.05 * S)
	if book:
		book.position = plate_pos + Vector2(75.0, -book.texture.get_height() * 1.05 * S * 0.5)
		book.z_index = 6
		add_child(book)
	var bb := Button.new(); bb.flat = true
	bb.size = Vector2(150.0, 130.0)
	bb.position = plate_pos + Vector2(0, -86.0)
	bb.pressed.connect(_open_awaken_dex)
	add_child(bb)

# ============================================================ kind 1 — 각성마석 제작

## 원작 `masicBrazier` — 화로 스파인 + `furnace_b1` 본 위의 손가락 + 클릭 히트박스.
func _build_brazier(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var z := _zoom()
	var at := Vector2(vis.x * 0.5 - 110.0 * z, vis.y * 0.5 + 40.0 * z)
	var sp := _spine("res://scenes/fx/lab_furnace.tscn", at, S)
	# 원작은 클릭 히트박스와 손가락을 스파인의 본 `furnace_b1` 자리에 붙인다.
	# 변환 씬이 본을 같은 이름의 Node2D 로 들고 있어 그대로 읽는다.
	var bone := at
	if sp != null:
		var bn := sp.get_node_or_null("root/furnace_b1")
		if bn != null:
			bone = at + (bn as Node2D).position * S
	var hit := Button.new(); hit.flat = true
	hit.size = Vector2(200.0, 200.0)
	hit.position = bone - hit.size * 0.5
	hit.pressed.connect(_on_click_furnace)
	add_child(hit)
	var fin := AtlasUI.spr("common_ui", "common_finger", S)
	if fin:
		fin.position = bone + Vector2(50.0, 0)
		fin.z_index = 7
		add_child(fin)
		var ft := fin.create_tween().set_loops()
		ft.tween_property(fin, "scale", Vector2(1.2 * S, 1.2 * S), 0.6)
		ft.tween_property(fin, "scale", Vector2(0.9 * S, 0.9 * S), 0.6)

## 화로 클릭 — 원작 `DragonAwaken::onclickDoor`(@01466288) 축자:
##   `AccountManager+0xfc`(제작중인 마석 등급) != 0 → `MasicStoneMakeLayer`(알 선택) 바로 열기
##   == 0                                        → `PopupMasicStone`(마석 종류 선택)
## 즉 마석 종류 선택창은 **미지정일 때만** 뜨고, 지정돼 있으면 화로는 알 선택으로 직행한다.
## 종류를 바꾸려면 게이지 줄의 `변경` 버튼(원작 `onClickChage`)이나 마석 아이콘을 쓴다.
## (2026-07-30 수정 — 종전엔 화로가 항상 종류 선택창을 열었다.)
func _on_click_furnace() -> void:
	if int(_stone_state().get("star", 0)) > 0:
		_open_stone_make()
	else:
		_open_stone_select()

## 원작 `drawMasicStoneInfo` + `refreshStoneInfo` — 진행 게이지 줄.
## `scene/laboratory/lv_bg` Scale9 450×40 anchor(0.5,0) @(visW/2, 170) [cocos y-up].
func _build_stone_info(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var W := 450.0
	var H := 40.0
	var st := _stone_state()
	var star := int(st.get("star", 0))
	var pts := int(st.get("points", 0))
	var need := AwakenStone.need(Data.awaken, star)
	var root := Control.new()
	root.size = Vector2(W, H)
	root.position = Vector2(vis.x * 0.5 - W * 0.5, vis.y - 170.0 - H)
	root.z_index = 14
	add_child(root)
	var bg := AtlasUI.nine("laboratory_ui", "scene_laboratory_lv_bg", Vector2(W, H), Rect2(20, 20, 4, 4))
	if bg: root.add_child(bg)
	# 원작 `refreshStoneInfo`(DragonAwaken.c:2387-2425) — 선택한 마석 아이콘
	# (`item/item_small/evol/evol_jewel_%d`, scale 0.7, anchor(1,0.5))이 패널 **왼쪽 끝에
	# 오른끝 정렬**로 겹치고, 뒤에서 `common/backlight3` 이 돌며 맥동한다
	# (RotateBy 90°/1s + ScaleTo 0.2↔0.3 반복). 레퍼런스 `마석제작1.png` 의 왼쪽 보라 마석.
	if star > 0:
		var jk := "item_item_small_evol_evol_jewel_%d" % star
		var jt := AtlasUI.tex("item_small_evol", jk)
		if jt != null:
			var jc := Vector2(-jt.get_width() * 0.7 * S * 0.5, H * 0.5)
			var bl := AtlasUI.spr("common_ui", "common_backlight3", 0.3 * S)
			if bl:
				bl.position = jc
				bl.z_index = 1
				root.add_child(bl)
				var bt := bl.create_tween().set_loops()
				bt.tween_property(bl, "scale", Vector2(0.2 * S, 0.2 * S), 0.5)
				bt.tween_property(bl, "scale", Vector2(0.3 * S, 0.3 * S), 0.5)
				var br := bl.create_tween().set_loops()
				br.tween_property(bl, "rotation_degrees", 90.0, 1.0).as_relative()
			var ji := AtlasUI.spr("item_small_evol", jk, 0.7 * S)
			if ji:
				ji.position = jc
				ji.z_index = 2
				root.add_child(ji)
				# 마석 아이콘 자체도 종류 선택창으로 — 사용자 확정(2026-07-30).
				# 원작은 아이콘이 스프라이트뿐이고 옆의 `변경` 버튼(`onClickChage`)만 눌렸다.
				var jw := jt.get_width() * 0.7 * S
				var jh := jt.get_height() * 0.7 * S
				var jb := Button.new(); jb.flat = true
				jb.size = Vector2(jw, jh)
				jb.position = jc - jb.size * 0.5
				jb.z_index = 3
				jb.pressed.connect(_open_stone_select)
				root.add_child(jb)
	var lab := Label.new()
	lab.text = "제작중" if star > 0 else "미선택"
	lab.add_theme_font_size_override("font_size", 17)
	lab.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.position = Vector2(10.0, 0); lab.size = Vector2(60.0, H)
	root.add_child(lab)
	# 게이지 = `common/bar_bg2` 위에 `common/bar_exp` CCProgressTimer(BAR, 좌→우).
	var gx := 76.0
	var gw := 240.0
	var gbg := AtlasUI.spr("common_ui", "common_bar_bg2", 1.0)
	if gbg:
		gbg.position = Vector2(gx + gw * 0.5, H * 0.5)
		gbg.scale = Vector2(gw / maxf(1.0, gbg.texture.get_width()), 1.0)
		root.add_child(gbg)
	var fill := TextureProgressBar.new()
	fill.texture_progress = load("res://assets/converted/common_ui/common_bar_exp.tres")
	fill.nine_patch_stretch = true
	fill.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	fill.min_value = 0; fill.max_value = maxi(1, need)
	fill.value = clampi(pts, 0, maxi(1, need))
	fill.position = Vector2(gx, H * 0.5 - 7.0)
	fill.size = Vector2(gw, 14.0)
	root.add_child(fill)
	_gauge_lbl = Label.new()
	# 원작 `<MasicStoneGaugeText>` = "%1$d/%2$d".
	_gauge_lbl.text = "%d/%d" % [pts, need] if star > 0 else "-"
	_gauge_lbl.add_theme_font_size_override("font_size", 15)
	_gauge_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	_gauge_lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02))
	_gauge_lbl.add_theme_constant_override("outline_size", 4)
	_gauge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gauge_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gauge_lbl.position = Vector2(gx, 0); _gauge_lbl.size = Vector2(gw, H)
	root.add_child(_gauge_lbl)
	# 원작 `onClickChage` = 만들 마석 등급 변경(누적 포인트 초기화 경고 포함).
	# 라벨 = `<MasicStoneChange>` "변경"(종전 "정보"는 근거 없는 자작 문구였다).
	AtlasUI.frame_button(root, "변경", Vector2(gx + gw + 10.0, H * 0.5 - 19.0),
		Vector2(100.0, 38.0), _open_stone_select, 0)

# ============================================================ 상태(원작 AccountManager 대체)

## 원작은 `AccountManager+0xf4/0xf8/0xfc`(현재 포인트 / 목표 / 선택 등급)를 서버에서 받았다 —
## 유실이라 로컬 pmeta 로 둔다.
func _stone_state() -> Dictionary:
	var m = UserDB.get_pmeta("awaken_stone", {})
	return m if m is Dictionary else {}

func _set_stone_state(star: int, points: int) -> void:
	UserDB.set_pmeta("awaken_stone", {"star": star, "points": points})

# ============================================================ 팝업 — 각성의 마석 선택

## 원작 `PopupMasicStone` — 3~6성 마석 중 만들 것을 고른다(레퍼런스 `docs/ref/uno/마석제작2.png`).
## 등급을 바꾸면 누적 포인트가 초기화된다(원작 문자열 `<MasicStoneChangemsg>`).
func _open_stone_select() -> void:
	# 원작 `PopupMasicStone` — popup4 + 주황 제목바 + 마석 4종은 **`item/mtr/evol_jewel_%d`
	# 큰 아이콘**(어두운 둥근 판이 그림에 포함) + 이름 + 빨간 `선택`(9patch/btn).
	# 레퍼런스 `docs/ref/uno/마석제작2.png`.
	var cur := int(_stone_state().get("star", 0))
	var pop := OrigPopup.open(self, "각성의 마석 선택", Vector2(680.0, 340.0))   # <AwakenMasicStone>
	var picked := {"star": cur if cur > 0 else 0}
	var cells: Array = []
	var n := AwakenStone.STARS.size()
	var cell_w := 120.0
	var gap := 14.0
	var x0 := (pop.win_size.x - (cell_w * n + gap * (n - 1))) * 0.5
	for i in n:
		var star: int = AwakenStone.STARS[i]
		var cell := Control.new()
		cell.position = Vector2(x0 + float(i) * (cell_w + gap), 96.0)
		cell.size = Vector2(cell_w, 150.0)
		pop.content.add_child(cell)
		var mt := AtlasUI.tex("item_mtr", "item_mtr_evol_jewel_%d" % star)
		if mt != null:
			var s := Sprite2D.new(); s.texture = mt; s.material = _pma
			var k := 100.0 / maxf(1.0, float(mt.get_width()))
			s.scale = Vector2(k, k)
			s.position = Vector2(cell_w * 0.5, 52.0)
			cell.add_child(s)
		var nl := Label.new()
		nl.text = "%d성 마석" % star                                  # <MasicStoneName>
		nl.add_theme_font_size_override("font_size", 18)
		nl.add_theme_color_override("font_color", Color(0.25, 0.15, 0.05))
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.size = Vector2(cell_w, 24.0); nl.position = Vector2(0, 108.0)
		cell.add_child(nl)
		var sel := ColorRect.new()
		sel.color = Color(1.0, 0.85, 0.35, 0.0)
		sel.size = Vector2(cell_w, 138.0)
		sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(sel)
		cells.append({"star": star, "hi": sel})
		var b := Button.new(); b.flat = true; b.size = Vector2(cell_w, 150.0)
		b.pressed.connect(func():
			picked["star"] = star
			for c in cells:
				(c["hi"] as ColorRect).color.a = 0.22 if int(c["star"]) == star else 0.0)
		cell.add_child(b)
	for c in cells:
		(c["hi"] as ColorRect).color.a = 0.22 if int(c["star"]) == picked["star"] else 0.0
	pop.add_action_button("선택", func():
		var star := int(picked["star"])
		if star <= 0:
			# <MasicStoneNonSelect>
			_say("제작할 각성 마석이 없습니다. 제작할 각성 마석을 선택하세요.")
			return
		if star == cur:
			pop.close()
			_open_stone_make()
			return
		var keep := int(_stone_state().get("points", 0))
		if cur > 0 and keep > 0:
			pop.close()
			_confirm("각성의 마석 변경",
				"각성의 마석을 변경하시겠습니까?\n변경시 기존에 누적된 포인트는 초기화 됩니다.",
				func():
					_set_stone_state(star, 0)
					_rebuild()
					_open_stone_make())
			return
		_set_stone_state(star, keep if cur == star else 0)
		pop.close()
		_rebuild()
		_open_stone_make())

# ============================================================ 팝업 — 각성의마석 제작

## 원작 `MasicStoneMakeLayer` — 좌측 `9patch/scroll_box`(창폭/2+100 × 420)에 보유 **알**을
## 세로 3개짜리 열(셀 폭 120)로 쌓고(알 위 `scene/cave/enchant_txt_bg` 포인트판 · 아래
## `9patch/recall_del` 70×30 의 선택/보유), 우측에 선택한 알(이름+성급, `btn_arrow1/2` ▲▼,
## `common/shadow`, `9patch/text_box` 290×125)과 빨간 `강화`(220×56)를 둔다.
## 레퍼런스: `docs/ref/uno/마석제작3.png`.
##
## 우리 알 보유분 = 가상 인벤 키 `egg:<드래곤id>`(뽑기 알 개봉 결과 — `EggGacha.KEY_PREFIX`).
## 부화 중인 알(UserDB 드래곤 레코드)은 **재료로 안 쓴다** — 원작도 가방의 Egg 인벤만 쓴다.
## 우측 하단 상자의 종족 소개문은 원작이 서버 문자열로 받아 **유실** → 지어내지 않고
## 알 이름·포인트 사실 정보만 적는다.
func _open_stone_make() -> void:
	var st := _stone_state()
	var star := int(st.get("star", 0))
	if star <= 0:
		_open_stone_select()
		return
	var pts := int(st.get("points", 0))
	var need := AwakenStone.need(Data.awaken, star)
	var vis := _vis()
	var pop := OrigPopup.open(self, "각성의마석 제작", Vector2(vis.x - 50.0, 600.0))   # <AwakenMasicStoneTitle>
	var W := pop.win_size.x
	var H := pop.win_size.y
	var picks := {}          # dragon_id → 투입 개수
	var state := {"sel": 0}  # 우측 패널에 뜨는 알(드래곤 id)
	# 머리글 "누적 + 투입 / 목표" — <MasicStoneInfoData> "%1$d + %2$d" + <MasicStoneInfoMaxData>.
	var head := Label.new()
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", Color(0.30, 0.18, 0.06))
	head.position = Vector2(55.0, 56.0); head.size = Vector2(400.0, 26.0)
	pop.content.add_child(head)
	# 하단 안내 — <MasicStoneEnchantDesc>.
	var hint := Label.new()
	hint.text = "강화 재료로 사용되는 알들은 등급에 따라서 포인트가 다릅니다."
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.42, 0.30, 0.16))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(40.0, H - 42.0); hint.size = Vector2(W - 80.0, 22.0)
	pop.content.add_child(hint)
	# 좌측 알 상자.
	var box_sz := Vector2(W * 0.5 + 100.0, 420.0)
	var box_pos := Vector2(48.0, 90.0)
	var box := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", box_sz, Rect2(65, 65, 6, 6))
	if box:
		box.position = box_pos
		pop.content.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.position = box_pos + Vector2(12.0, 8.0)
	scroll.size = box_sz - Vector2(24.0, 16.0)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pop.content.add_child(scroll)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 4)
	scroll.add_child(cols)
	# 우측 패널.
	var rx := box_pos.x + box_sz.x + 24.0
	var rw := W - rx - 45.0
	var right := Control.new()
	right.position = Vector2(rx, box_pos.y)
	right.size = Vector2(rw, box_sz.y)
	pop.content.add_child(right)
	# 보유 알 목록.
	var eggs: Array = []
	for key in UserDB.inventory().keys():
		var did := EggGacha.dragon_of(String(key))
		if did <= 0: continue
		var have := UserDB.item_count(String(key))
		if have <= 0: continue
		var info: Dictionary = Data.get_dragon(did)
		eggs.append({"id": did, "key": String(key), "have": have,
			"star": int(info.get("star", 0)), "name": String(info.get("name", "드래곤"))})
	eggs.sort_custom(func(a, b): return int(a["star"]) > int(b["star"]))
	if not eggs.is_empty():
		state["sel"] = int(eggs[0]["id"])
	var filt := {"elem": ""}          # 하단 속성 탭이 고른 속성("" = ALL)
	var refresh := func():
		var entries: Array = []
		for did in picks.keys():
			var s := int(Data.get_dragon(int(did)).get("star", 0))
			entries.append({"star": s, "count": int(picks[did])})
		var add := AwakenStone.batch_points(Data.awaken, entries)
		head.text = "%d + %d / %d" % [pts, add, need]
	# ⚠️ 람다는 캡처 시점 값을 물기 때문에 상호 재귀 콜백은 **딕셔너리 간접 참조**로 잇는다
	#    (`[[dv2-gdscript-lambda-self-capture]]` — placeholder 를 캡처하면 갱신이 무동작).
	var fns := {}
	var changed := func():
		refresh.call()
		(fns["list"] as Callable).call()
		(fns["right"] as Callable).call()
	fns["right"] = func():
		for c in right.get_children(): c.queue_free()
		var e := {}
		for e0 in eggs:
			if int(e0["id"]) == int(state["sel"]): e = e0; break
		if e.is_empty(): return
		_stone_make_right(right, e, picks, changed)
	fns["list"] = func():
		for c in cols.get_children(): c.queue_free()
		var want := String(filt["elem"])
		var shown: Array = eggs.filter(func(e):
			if want == "": return true
			return String(Data.get_dragon(int(e["id"])).get("element", "")) == want)
		if shown.is_empty():
			var none := Label.new()
			none.text = "재료로 쓸 알이 없습니다.\n뽑기·상점에서 알을 구하면 여기 나옵니다."
			none.add_theme_font_size_override("font_size", 17)
			none.add_theme_color_override("font_color", Color(0.42, 0.30, 0.16))
			cols.add_child(none)
			return
		# 원작 CCTableView — 셀 폭 120, 열마다 세로 3개(왼쪽 위부터 아래로).
		var per_col := 3
		var vb: VBoxContainer = null
		for i in shown.size():
			if i % per_col == 0:
				vb = VBoxContainer.new()
				vb.add_theme_constant_override("separation", 2)
				cols.add_child(vb)
			vb.add_child(_egg_cell(shown[i], picks, state, changed))
	# 속성 필터 — 원작 `onClickTypeBtn` + `common/element_bg` + `item/item_small/ele_*`.
	var tabs: Array = []
	var fx := W * 0.5 - (DEX_ELEMENTS.size() * 58.0 - 6.0) * 0.5
	for ent in DEX_ELEMENTS:
		var el := String(ent["key"])
		var holder := Control.new()
		holder.position = Vector2(fx, H - 100.0); holder.size = Vector2(52.0, 52.0)
		pop.content.add_child(holder)
		var eb := AtlasUI.spr("common_ui", "common_element_bg", 0.54)
		if eb: eb.position = Vector2(26.0, 26.0); holder.add_child(eb)
		var ei := AtlasUI.spr("item_small_ui", String(ent["icon"]), 0.54)
		if ei: ei.position = Vector2(26.0, 26.0); holder.add_child(ei)
		if el != "": holder.modulate = Color(0.62, 0.62, 0.66)
		tabs.append(holder)
		var fb := Button.new(); fb.flat = true; fb.size = Vector2(52.0, 52.0)
		fb.pressed.connect(func():
			filt["elem"] = el
			for h in tabs:
				(h as Control).modulate = Color(1, 1, 1) if h == holder else Color(0.62, 0.62, 0.66)
			(fns["list"] as Callable).call())
		holder.add_child(fb)
		fx += 58.0
	(fns["list"] as Callable).call()
	(fns["right"] as Callable).call()
	refresh.call()
	# ⚠️ 다중행 람다를 인자 자리에 두면 뒤에 위치 인자를 못 붙인다(GDScript 파서) →
	#    먼저 변수에 담고 넘긴다. `강화` 는 우측 패널 하단(레퍼런스).
	# 초과 경고를 이미 띄웠는가 — 이 창을 여는 동안 **한 번만** 뜬다(사용자 확정 2026-07-30).
	var warned := {"over": false}
	var commit := func(entries: Array):
		for did in picks.keys():
			var n := int(picks[did])
			if n > 0:
				UserDB.use_item(EggGacha.key_for(int(did)), n)
		var res := AwakenStone.apply(Data.awaken, star, pts, entries)
		_set_stone_state(star, int(res["points"]))
		pop.close()
		var done := bool(res["complete"])
		var key := AwakenStone.reward_key(star) if done else ""
		if done:
			UserDB.add_item(key, 1)
		# 🔴 순서 주의(2026-07-30 수정): `_rebuild()` 는 **씬의 자식을 전부 queue_free** 한다.
		#   종전에는 완료 팝업(`OrigPopup.open(self, …)`)과 NPC 대사(`_box`)를 먼저 만들고
		#   마지막에 `_rebuild()` 를 불러서, 원작 `MakeMasicStonePopup` 이식본이 뜬 프레임에
		#   바로 삭제됐다 — **제작 성공 연출이 아예 보이지 않았다**(사용자 지적).
		#   게이지/보유량 갱신을 먼저 하고 그 위에 연출을 얹는다.
		_rebuild()
		if done:
			_say(_talk_fmt("mamorudic.success", Data.item_name(key)))
			_make_stone_complete_popup(star, key)
	var on_enchant := func():
		var entries: Array = []
		for did in picks.keys():
			if int(picks[did]) <= 0: continue
			entries.append({"star": int(Data.get_dragon(int(did)).get("star", 0)),
				"count": int(picks[did])})
		var err := AwakenStone.check_batch(Data.awaken, star, pts, entries)
		if err != "":
			_say(err)
			return
		# 목표 초과는 **막지 않는다** — 경고를 한 번 띄우고(확인) 그 뒤로는 바로 진행한다.
		# 초과분은 버려진다(AwakenStone.apply 가 완성 시 포인트를 0 으로 되돌린다).
		var over := AwakenStone.overflow(Data.awaken, star, pts, entries)
		if over > 0 and not bool(warned["over"]):
			warned["over"] = true
			_confirm("각성의 마석 제작",
				"각성에 필요한 포인트를 초과했습니다.\n초과된 %d 포인트는 사라집니다.\n제작을 진행하시겠습니까?" % over,
				func(): commit.call(entries))
			return
		commit.call(entries)
	pop.add_action_button("강화", on_enchant, 0, Vector2(220.0, 56.0),
		Vector2(rx + rw * 0.5, 505.0))

## 알 목록 칸 1개(120×132) — 원작 셀: `scene/cave/enchant_txt_bg` 포인트판(위) + 알 아이콘
## + `9patch/recall_del`(70×30) 의 "선택수/보유수". 클릭하면 우측 패널 대상이 된다.
func _egg_cell(e: Dictionary, picks: Dictionary, state: Dictionary, changed: Callable) -> Control:
	var did := int(e["id"])
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(120.0, 132.0)
	if int(state["sel"]) == did:
		var hi := ColorRect.new()
		hi.color = Color(1.0, 0.85, 0.35, 0.20)
		hi.size = Vector2(116.0, 130.0); hi.position = Vector2(2.0, 0)
		hi.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(hi)
	# 포인트판 — enchant_txt_bg 위에 노란 포인트 숫자.
	var plate := AtlasUI.spr("cave_ui", "scene_cave_enchant_txt_bg", 1.0)
	if plate:
		plate.scale = Vector2(76.0 / maxf(1.0, plate.texture.get_width()), 1.0)
		plate.position = Vector2(44.0, 14.0)
		cell.add_child(plate)
	var pl := Label.new()
	pl.text = str(AwakenStone.egg_points(Data.awaken, int(e["star"])))
	pl.add_theme_font_size_override("font_size", 15)
	pl.add_theme_color_override("font_color", Color(1.0, 0.83, 0.30))
	pl.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.02))
	pl.add_theme_constant_override("outline_size", 4)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.position = Vector2(6.0, 2.0); pl.size = Vector2(76.0, 24.0)
	cell.add_child(pl)
	var sh := AtlasUI.spr("common_ui", "common_shadow", 0.7 * Design.ASSET_SCALE)
	if sh: sh.position = Vector2(60.0, 92.0); cell.add_child(sh)
	var tex := Icons.dragon_egg_texture(did)
	if tex != null:
		var s := Sprite2D.new(); s.texture = tex; s.material = _pma
		var k := 56.0 / maxf(1.0, float(tex.get_width()))
		s.scale = Vector2(k, k); s.position = Vector2(60.0, 62.0)
		cell.add_child(s)
	# 선택수/보유수 — recall_del 70×30.
	var rp := AtlasUI.nine("ninepatch_ui", "9patch_recall_del", Vector2(70.0, 30.0))
	if rp:
		rp.position = Vector2(25.0, 100.0)
		cell.add_child(rp)
	var cnt := Label.new()
	cnt.text = "%d/%d" % [int(picks.get(did, 0)), int(e["have"])]
	cnt.add_theme_font_size_override("font_size", 15)
	cnt.add_theme_color_override("font_color", Color(1, 1, 1))
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cnt.position = Vector2(25.0, 100.0); cnt.size = Vector2(70.0, 30.0)
	cell.add_child(cnt)
	var b := Button.new(); b.flat = true; b.size = Vector2(120.0, 132.0)
	b.pressed.connect(func():
		state["sel"] = did
		changed.call())
	cell.add_child(b)
	return cell

## 우측 패널 — 이름 + 성급(★), `btn_arrow2`(▲)/`btn_arrow1`(▼) 로 투입 수 조절,
## 큰 알 + `common/shadow`, `9patch/text_box`(290×125) 정보 상자.
func _stone_make_right(host: Control, e: Dictionary, picks: Dictionary, changed: Callable) -> void:
	var S := Design.ASSET_SCALE
	var did := int(e["id"])
	var have := int(e["have"])
	var rw := host.size.x
	var nl := Label.new()
	nl.text = String(e["name"])
	nl.add_theme_font_size_override("font_size", 20)
	nl.add_theme_color_override("font_color", Color(0.25, 0.15, 0.05))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.position = Vector2(0, 0); nl.size = Vector2(rw, 26.0)
	host.add_child(nl)
	var sl := Label.new()
	sl.text = "★".repeat(maxi(1, int(e["star"])))
	sl.add_theme_font_size_override("font_size", 16)
	sl.add_theme_color_override("font_color", Color(1.0, 0.80, 0.16))
	sl.add_theme_color_override("font_outline_color", Color(0.32, 0.18, 0.02))
	sl.add_theme_constant_override("outline_size", 4)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.position = Vector2(0, 26.0); sl.size = Vector2(rw, 22.0)
	host.add_child(sl)
	# ▲/수량/▼ 열(왼쪽) + 큰 알(오른쪽) — 레퍼런스 배치.
	var ax := rw * 0.28
	var up := TextureButton.new()
	var ut := AtlasUI.tex("common_ui", "common_btn_arrow2")
	if ut != null:
		up.texture_normal = ut
		up.scale = Vector2(S, S)
		up.pivot_offset = Vector2.ZERO
	up.rotation_degrees = -90.0
	up.position = Vector2(ax - 14.0, 116.0)
	up.pressed.connect(func():
		picks[did] = mini(have, int(picks.get(did, 0)) + 1)
		changed.call())
	host.add_child(up)
	var cnt := Label.new()
	cnt.text = str(int(picks.get(did, 0)))
	cnt.add_theme_font_size_override("font_size", 22)
	cnt.add_theme_color_override("font_color", Color(0.25, 0.15, 0.05))
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cnt.position = Vector2(ax - 34.0, 132.0); cnt.size = Vector2(56.0, 30.0)
	host.add_child(cnt)
	var dn := TextureButton.new()
	var dt := AtlasUI.tex("common_ui", "common_btn_arrow1")
	if dt != null:
		dn.texture_normal = dt
		dn.scale = Vector2(S, S)
		dn.pivot_offset = Vector2.ZERO
	dn.rotation_degrees = -90.0
	dn.position = Vector2(ax - 14.0, 214.0)
	dn.pressed.connect(func():
		picks[did] = maxi(0, int(picks.get(did, 0)) - 1)
		if int(picks[did]) == 0: picks.erase(did)
		changed.call())
	host.add_child(dn)
	var ec := Vector2(rw * 0.62, 160.0)
	var sh := AtlasUI.spr("common_ui", "common_shadow", 1.1 * S)
	if sh: sh.position = ec + Vector2(0, 52.0); host.add_child(sh)
	var tex := Icons.dragon_egg_texture(did)
	if tex != null:
		var s := Sprite2D.new(); s.texture = tex; s.material = _pma
		var k := 96.0 / maxf(1.0, float(tex.get_width()))
		s.scale = Vector2(k, k); s.position = ec
		host.add_child(s)
	# 정보 상자 — 종족 소개문은 서버 유실이라 사실 정보만.
	var tb_sz := Vector2(minf(290.0, rw), 125.0)
	var tb := AtlasUI.nine("ninepatch_ui", "9patch_text_box", tb_sz, Rect2(25, 25, 3, 3))
	if tb:
		tb.position = Vector2((rw - tb_sz.x) * 0.5, 250.0)
		host.add_child(tb)
	var info := Label.new()
	info.text = "%s의 알\n개당 %d 포인트\n보유 %d개" % [String(e["name"]),
		AwakenStone.egg_points(Data.awaken, int(e["star"])), have]
	info.add_theme_font_size_override("font_size", 15)
	info.add_theme_color_override("font_color", Color(0.42, 0.30, 0.16))
	info.position = Vector2((rw - tb_sz.x) * 0.5 + 18.0, 264.0)
	info.size = Vector2(tb_sz.x - 36.0, 100.0)
	host.add_child(info)

# ============================================================ 팝업 — 드래곤 각성

## 원작 `DragonAwakeSelectLayer` — 각성 대상 고르기(레퍼런스 `docs/ref/uno/드래곤각성2.png`).
## 안내문·조건은 원작 문자열 확정: `<DragonAwakenComment>`
## "* 드래곤 레벨 50, 각성 재료가 있는 드래곤만 선택 할 수 있습니다."
func _open_dragon_select() -> void:
	var cfg: Dictionary = Data.awaken
	var min_lv := int(cfg.get("min_level", 50))
	var owned: Array = UserDB.dragons().filter(func(d):
		return not UserDB.is_egg(d) and not bool(d.get("awakened", false)))
	if owned.is_empty():
		_say("그건 각성할 수 없는 드래곤이야!")            # <MamorudicLabTalkErro_2_1>
		return
	# 원작 `DragonAwakeSelectLayer::initWidget` — 창 (visW−50)×600. 제목(55,25)·안내문은
	# **주황 제목바 없이** 맨글자다(레퍼런스 `드래곤각성2.png`). 카드 상자 = `9patch/scroll_box`
	# (창폭−100)×481 @ (50,40)[cocos], 셀 크기 = 320×461(`tableCellSizeForIndex`).
	var vis := _vis()
	var pop := OrigPopup.open(self, "", Vector2(vis.x - 50.0, 600.0))
	var W := pop.win_size.x
	var tt := Label.new()
	tt.text = "드래곤 선택"
	tt.add_theme_font_size_override("font_size", 24)
	tt.add_theme_color_override("font_color", Color(0.25, 0.15, 0.05))
	tt.position = Vector2(55.0, 12.0); tt.size = Vector2(300.0, 30.0)
	pop.content.add_child(tt)
	var cm := Label.new()
	cm.text = "* 드래곤 레벨 %d, 각성 재료가 있는 드래곤만 선택 할 수 있습니다." % min_lv
	cm.add_theme_font_size_override("font_size", 15)
	cm.add_theme_color_override("font_color", Color(0.42, 0.30, 0.16))
	cm.position = Vector2(55.0, 44.0); cm.size = Vector2(700.0, 22.0)
	pop.content.add_child(cm)
	var box := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", Vector2(W - 100.0, 481.0),
		Rect2(65, 65, 6, 6))
	if box:
		box.position = Vector2(50.0, 600.0 - 40.0 - 481.0)
		pop.content.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(60.0, 89.0); scroll.size = Vector2(W - 120.0, 465.0)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pop.content.add_child(scroll)
	var rowbox := HBoxContainer.new()
	rowbox.add_theme_constant_override("separation", 8)
	scroll.add_child(rowbox)
	for d in owned:
		rowbox.add_child(_awaken_card(d, min_lv, pop))

## 대상 카드 1장 — 원작 `DragonAwakeCell::initWithSize/setCellData` 1:1 (셀 320×461):
##   요소 아이콘(좌상, `item/item_small/ele_*` 0.6) · 드래곤 **스파인 "wait"**(0.7) +
##   `common/shadow` · 등급(`Dragon::getRating` = 우리 `Growth.compute_grade`, font_title 금색,
##   우중) · `scene/promote/train_box1` 이름판("레벨 N 이름", 흰 글자 좌정렬 x=20) ·
##   재료 3줄(아이콘 0.6 + 이름 + 보유/필요 우정렬, 부족분 빨강 — ccColor3B::RED).
## 카드 바탕 `common/bg/stat_box2` 는 §10 공통 원인(`common/bg/` 하위가 덤프에 없다) →
## `9patch/train_box4` 로 대체. 미충족 카드는 원작처럼 **바탕만** 어둡게
## (`setColor(100,100,100)` — 드래곤·이름판은 원색 유지, 레퍼런스 `드래곤각성2.png` 3번째 카드).
## 종전의 `비용` 줄은 원작 카드에 없어 뺐다(비용은 확인 팝업 버튼이 보여 준다).
func _awaken_card(d: Dictionary, min_lv: int, pop: OrigPopup) -> Control:
	const CW := 320.0
	const CH := 461.0
	var S := Design.ASSET_SCALE
	var cfg: Dictionary = Data.awaken
	var did := int(d.get("id", 1))
	var info: Dictionary = Data.get_dragon(did)
	var star := int(info.get("star", 0))
	var lv := int(d.get("level", 1))
	var mats: Array = (cfg.get("materials_by_star", {}) as Dictionary).get(str(star), [])
	var ok := lv >= min_lv and not mats.is_empty()
	for m in mats:
		if UserDB.item_count(String(m[0])) < int(m[1]): ok = false
	var card := Control.new()
	card.custom_minimum_size = Vector2(CW, CH)
	var bg := AtlasUI.nine("ninepatch_ui", "9patch_train_box4", Vector2(CW, CH), Rect2(20, 20, 4, 4))
	if bg:
		if not ok: bg.modulate = Color(0.39, 0.39, 0.39)   # 원작 setColor(100,100,100)
		card.add_child(bg)
	# 요소 아이콘 — cocos (10, h−10) anchor(0,1) scale 0.6.
	var el := String(info.get("element", ""))
	for ent in DEX_ELEMENTS:
		if String(ent["key"]) == el:
			var ei := AtlasUI.spr("item_small_ui", String(ent["icon"]), 0.6 * S)
			if ei:
				ei.position = Vector2(10.0 + ei.texture.get_width() * 0.3 * S,
					10.0 + ei.texture.get_height() * 0.3 * S)
				ei.z_index = 100
				card.add_child(ei)
			break
	# 그림자 + 드래곤 스파인("wait" 루프). 발 위치는 레퍼런스 실측(y≈0.47·H).
	# 배율: 원작 리터럴 0.7 은 원작 셀 바탕(stat_box2, 미보유) 기준이라 그대로 곱하면
	# 320pt 카드를 넘친다(실측) → 카드에 맞춘 0.45·S.
	var feet := Vector2(CW * 0.5, CH * 0.47)
	var sh := AtlasUI.spr("common_ui", "common_shadow", S)
	if sh: sh.position = feet + Vector2(0, 4.0); card.add_child(sh)
	var sp := _dragon_node(did, Growth.stage_for_level(lv), 0.45 * S)
	sp.position = feet
	card.add_child(sp)
	# 등급 — 원작 font_title 금색, anchor(1,0) @ (w−20, h/2+5)[cocos].
	var gr := Label.new()
	gr.text = "%.1f" % Growth.compute_grade(info, Data.stat_table, d.get("stat_bonus", {}),
		d.get("gain_log", []), Data.level_curve.get("grade", {}))
	gr.add_theme_font_size_override("font_size", 26)
	gr.add_theme_color_override("font_color", Color(1.0, 0.83, 0.30))
	gr.add_theme_color_override("font_outline_color", Color(0.25, 0.12, 0.02, 0.95))
	gr.add_theme_constant_override("outline_size", 5)
	gr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gr.position = Vector2(CW - 240.0, CH * 0.5 - 35.0); gr.size = Vector2(220.0, 30.0)
	gr.z_index = 100          # 스파인 씬 내부 슬롯 z 보다 확실히 위(원작 train_box1 z=10 의도)
	card.add_child(gr)
	# 이름판 `scene/promote/train_box1` @ (w/2, h/2−30)[cocos] → y-down h/2+30. z=10(원작).
	var pill_c := Vector2(CW * 0.5, CH * 0.5 + 30.0)
	var pill_w := 280.0
	var pill := AtlasUI.spr("promote_ui", "scene_promote_train_box1", S)
	if pill:
		pill.position = pill_c
		pill_w = pill.texture.get_width() * S
		pill.z_index = 100
		card.add_child(pill)
	var nl := Label.new()
	nl.text = "레벨 %d %s" % [lv, String(d.get("name", info.get("name", "드래곤")))]
	nl.add_theme_font_size_override("font_size", 17)
	nl.add_theme_color_override("font_color", Color(1, 1, 1))
	nl.add_theme_color_override("font_outline_color", Color(0.16, 0.10, 0.04, 0.9))
	nl.add_theme_constant_override("outline_size", 4)
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.position = Vector2(pill_c.x - pill_w * 0.5 + 20.0, pill_c.y - 14.0)
	nl.size = Vector2(pill_w - 40.0, 28.0)
	nl.z_index = 101
	card.add_child(nl)
	# 재료 3줄 — 원작 표시 순서 = 마석 → 보네르 → 아니마(레퍼런스). 아이콘 anchor(0,1) 0.6,
	# 이름 라벨(subtitle 0.8) + 수량 라벨(0.7, 이름판 우변 정렬, 부족 시 RED).
	var order := mats.duplicate()
	order.sort_custom(func(a, b):
		return _mat_rank(String(a[0])) < _mat_rank(String(b[0])))
	var left := pill_c.x - pill_w * 0.5
	var right := pill_c.x + pill_w * 0.5
	var y := pill_c.y + 32.0
	for m in order:
		var key := String(m[0])
		var have := UserDB.item_count(key)
		var need := int(m[1])
		var icp := Data.item_icon_path(key)
		if icp != "" and ResourceLoader.exists(icp):
			var t: Texture2D = load(icp)
			var si := Sprite2D.new(); si.texture = t; si.material = _pma
			var ik := 34.0 / maxf(1.0, float(t.get_height()))   # 행높이 38 에 맞춘다
			si.scale = Vector2(ik, ik)
			si.position = Vector2(left + 18.0, y + 19.0)
			si.z_index = 100
			card.add_child(si)
		var ml := Label.new()
		ml.text = "%s :" % Data.item_name(key)
		ml.add_theme_font_size_override("font_size", 16)
		ml.add_theme_color_override("font_color", Color(1, 1, 1))
		ml.add_theme_color_override("font_outline_color", Color(0.16, 0.10, 0.04, 0.9))
		ml.add_theme_constant_override("outline_size", 4)
		ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ml.position = Vector2(left + 46.0, y + 6.0); ml.size = Vector2(180.0, 26.0)
		ml.z_index = 100
		card.add_child(ml)
		var cl := Label.new()
		cl.text = "%d / %d" % [have, need]
		cl.add_theme_font_size_override("font_size", 15)
		cl.add_theme_color_override("font_color",
			Color(1, 1, 1) if have >= need else Color(0.96, 0.28, 0.22))
		cl.add_theme_color_override("font_outline_color", Color(0.16, 0.10, 0.04, 0.9))
		cl.add_theme_constant_override("outline_size", 4)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cl.position = Vector2(right - 150.0, y + 6.0); cl.size = Vector2(150.0, 26.0)
		cl.z_index = 100
		card.add_child(cl)
		y += 38.0
	if ok:
		var b := Button.new(); b.flat = true; b.size = Vector2(CW, CH)
		b.pressed.connect(func():
			pop.close()
			_open_awaken_confirm(d))
		card.add_child(b)
	return card

## 재료 표시 순서(레퍼런스 `드래곤각성2.png`): 각성의 마석 → 보네르 → 아니마.
func _mat_rank(key: String) -> int:
	if key.begins_with("evol_jewel"): return 0
	if key == "bonner": return 1
	return 2

## 드래곤 스파인 노드("wait" 루프, 원작 CCSkeletonAnimation setAnimation("wait", true)).
## 씬 미빌드 종은 초상 폴백 — 스파인 원점은 발이므로 초상은 발 위로 올려 그린다.
func _dragon_node(did: int, stage: String, scale: float) -> Node2D:
	var path := "res://scenes/dragons/dragon_%d_%s.tscn" % [did, stage]
	if ResourceLoader.exists(path):
		var n := (load(path) as PackedScene).instantiate() as Node2D
		n.scale = Vector2(scale, scale)
		var ap := n.get_node_or_null("AnimationPlayer")
		if ap and ap.has_animation("wait"):
			ap.get_animation("wait").loop_mode = Animation.LOOP_LINEAR
			ap.play("wait")
		return n
	var holder := Node2D.new()
	var tex := _portrait(did, stage)
	if tex != null:
		var s := Sprite2D.new(); s.texture = tex; s.material = _pma
		var k := 160.0 / maxf(1.0, float(tex.get_width()))
		s.scale = Vector2(k, k)
		s.position = Vector2(0, -tex.get_height() * k * 0.5)
		holder.add_child(s)
	return holder

## 원작 `AwakenPopup`(650×440) — 각성 확인(레퍼런스 `docs/ref/uno/드래곤각성3.png`).
## 프레임(전부 디컴프 리터럴): `9patch/box_worldbook`(노란 액자) 안에 `common/dragon_bg1` +
## 초상 + `common/dragon_cover1`, 문구 밑줄 `9patch/menu_txt_line`, 스킬 아이콘
## `skill/evolution/%d`(scale 0.8), 버튼 = `RoundedButton(1.1)` + `common/coin_small1`.
## 문자열은 전부 원작 테이블 확정: `<DragonAwakenInfoMsg>` `<DragonAwakenSkillInfoNameMsg>`
## `<DragonAwakenPopMsg>` `<DragonAwakenPrice>`. 붉은 강조는 레퍼런스 그대로.
func _open_awaken_confirm(d: Dictionary) -> void:
	var S := Design.ASSET_SCALE
	var cfg: Dictionary = Data.awaken
	var did := int(d.get("id", 1))
	var info: Dictionary = Data.get_dragon(did)
	var star := int(info.get("star", 0))
	var name := String(info.get("name", "드래곤"))
	var mats: Array = (cfg.get("materials_by_star", {}) as Dictionary).get(str(star), [])
	var gold := int((cfg.get("gold_by_star", {}) as Dictionary).get(str(star), 0))
	var aw_no := Data.awaken_skill_of(did)
	var sk: Dictionary = Data.skill_awaken_for(aw_no) if aw_no > 0 else {}
	var pop := OrigPopup.open(self, "드래곤 각성", Vector2(650.0, 440.0))
	var col_x := 100.0          # 좌측 아이콘 열 중심
	var txt_x := 175.0
	var y := 88.0
	# 초상 액자 — box_worldbook(110×110) 안에 dragon_bg1 + 초상 + dragon_cover1.
	var wb := AtlasUI.nine("ninepatch_ui", "9patch_box_worldbook", Vector2(110.0, 110.0),
		Rect2(10, 10, 10, 10))
	if wb:
		wb.position = Vector2(col_x - 55.0, y)
		pop.content.add_child(wb)
	var pc := Vector2(col_x, y + 55.0)
	var dbg := AtlasUI.spr("common_ui", "common_dragon_bg1", S)
	if dbg:
		dbg.scale = Vector2(96.0 / maxf(1.0, dbg.texture.get_width()),
			96.0 / maxf(1.0, dbg.texture.get_height()))
		dbg.position = pc
		pop.content.add_child(dbg)
	var dpor := _portrait(did, Growth.stage_for_level(int(d.get("level", 1))))
	if dpor != null:
		var ds := Sprite2D.new(); ds.texture = dpor; ds.material = _pma
		var dk: float = minf(88.0 / maxf(1.0, float(dpor.get_width())),
			88.0 / maxf(1.0, float(dpor.get_height())))
		ds.scale = Vector2(dk, dk); ds.position = pc
		pop.content.add_child(ds)
	var dcv := AtlasUI.spr("common_ui", "common_dragon_cover1", S)
	if dcv:
		dcv.scale = Vector2(100.0 / maxf(1.0, dcv.texture.get_width()),
			100.0 / maxf(1.0, dcv.texture.get_height()))
		dcv.position = pc
		pop.content.add_child(dcv)
	# 1행 — <DragonAwakenInfoMsg> (괄호 안 빨강) + menu_txt_line 밑줄.
	var l1 := _rich(txt_x, y + 8.0, 430.0,
		"각성시 [ [color=#c22015]체력, 공격력, 방어력[/color] ] 이 증가합니다", 18)
	pop.content.add_child(l1)
	var ln1 := AtlasUI.nine("ninepatch_ui", "9patch_menu_txt_line", Vector2(440.0, 6.0))
	if ln1:
		ln1.position = Vector2(txt_x, y + 42.0)
		pop.content.add_child(ln1)
	if not sk.is_empty():
		# 2행 — <DragonAwakenSkillInfoNameMsg> (스킬명 빨강).
		var l2 := _rich(txt_x, y + 56.0, 430.0,
			"각성전용스킬 : [[color=#c22015]%s[/color]] 획득" % String(sk.get("name", "")), 18)
		pop.content.add_child(l2)
		y += 132.0
		# 각성스킬 아이콘 — 파란 날개 틀 `common/skill_evolution_bg` 위에
		# `skill/evolution/%d`(scale 0.8, 원작 setScale). 레퍼런스의 파란 날개 판.
		var sbg := AtlasUI.spr("common_ui", "common_skill_evolution_bg", 0.8 * S)
		if sbg:
			sbg.position = Vector2(col_x, y + 40.0)
			pop.content.add_child(sbg)
		var sico := int(sk.get("icon", 0))
		if sico > 0:
			var sip := "res://assets/converted/skill_evolution/skill_evolution_%d.tres" % sico
			if ResourceLoader.exists(sip):
				var sit: Texture2D = load(sip)
				var ss := Sprite2D.new(); ss.texture = sit; ss.material = _pma
				ss.scale = Vector2(0.8 * S, 0.8 * S)
				ss.position = Vector2(col_x, y + 40.0)
				pop.content.add_child(ss)
		# 효과문 — menu_txt_line 알약 안(레퍼런스의 테두리 상자).
		var pill := AtlasUI.nine("ninepatch_ui", "9patch_menu_txt_line", Vector2(440.0, 38.0))
		if pill:
			pill.position = Vector2(txt_x, y + 22.0)
			pop.content.add_child(pill)
		var eff := Label.new()
		eff.text = String(sk.get("comment", ""))
		eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		eff.add_theme_font_size_override("font_size", 15)
		eff.add_theme_color_override("font_color", Color(0.30, 0.18, 0.06))
		eff.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		eff.position = Vector2(txt_x + 12.0, y + 22.0); eff.size = Vector2(416.0, 38.0)
		pop.content.add_child(eff)
		y += 84.0
	else:
		y += 100.0
		# 각성스킬 배정이 아직 없는 종족 — 지어내지 않고 그대로 알린다.
		var l2b := Label.new()
		l2b.text = "이 종족의 각성 전용 스킬은 아직 배정되지 않았습니다(data/skill_awaken.json)."
		l2b.add_theme_font_size_override("font_size", 15)
		l2b.add_theme_color_override("font_color", Color(0.55, 0.40, 0.22))
		l2b.position = Vector2(txt_x, y); l2b.size = Vector2(430.0, 24.0)
		pop.content.add_child(l2b)
		y += 40.0
	# <DragonAwakenPopMsg> — 이름 빨강, 중앙.
	var ask := _rich(40.0, y + 14.0, 570.0,
		"[center][ [color=#c22015]%s[/color] ] 드래곤을 각성시키겠습니까?[/center]" % name, 19)
	pop.content.add_child(ask)
	var on_ok := func():
		# 원작 responceDragonAwaken 전 검증 — 실패 사유는 원작 문자열 그대로.
		if UserDB.gold() < gold:
			_say("각성 비용이 부족합니다.")               # <DragonAwakenErro_3>
			return
		for m in mats:
			if UserDB.item_count(String(m[0])) < int(m[1]):
				_say("각성 재료가 부족합니다.")            # <DragonAwakenErro_4>
				return
		pop.close()
		_do_awaken(d, mats, gold)
	# 확정 버튼 — 원작 RoundedButton(코인 아이콘 + <DragonAwakenPrice>"x%d").
	var btn := pop.add_action_button("     x%s" % AtlasUI.comma(gold), on_ok, 0, Vector2(230.0, 56.0))
	var coin := AtlasUI.spr("common_ui", "common_coin_small1", S)
	if coin:
		coin.position = Vector2(38.0, 28.0)
		btn.add_child(coin)

## 빨강 강조가 섞인 원작 문구용 RichTextLabel(기본색 = 진갈색).
func _rich(x: float, y: float, w: float, bbcode: String, fs: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", fs)
	r.add_theme_color_override("default_color", Color(0.30, 0.18, 0.06))
	r.text = bbcode
	r.position = Vector2(x, y); r.size = Vector2(w, 30.0)
	return r

## 재료·비용 소모 + 각성 확정 + 연출. 원작은 `EvolLayer` 가 `setAwaken(true)` 까지 한다.
func _do_awaken(d: Dictionary, mats: Array, gold: int) -> void:
	var uid := int(d.get("uid", 0))
	for m in mats:
		UserDB.use_item(String(m[0]), int(m[1]))
	if gold > 0:
		UserDB.spend("gold", gold)
	UserDB.set_dragon_field(uid, "awakened", true)
	# 각성스킬은 **종족 고유**다 — 원작 info_skill_awaken 의 no 를 드래곤이 들고 있었고,
	# 그 배정표는 서버 유실분을 사용자가 복원했다(data/skill_awaken.json by_dragon).
	# 배정이 아직 없는 종족은 0 → 각성칸이 빈 채로 남는다(지어내지 않는다).
	var did := int(d.get("id", 1))
	var aw_no := Data.awaken_skill_of(did)
	if aw_no > 0:
		UserDB.set_dragon_field(uid, "awaken_skill", aw_no)
	_say(_talk("mamorudic.awake"))
	# 연출 = `scripts/ui/evol_layer.gd`(원작 EvolLayer 이식).
	# 원작 `DragonAwaken.c:2859` 은 `EvolLayer::create(dragon, 시작좌표, json, cb)` — 시작좌표는
	# 각성 제단 자리다(`awakenStand` 의 center-(90z,75z)).
	var vis := _vis()
	var z := _zoom()
	EvolLayer.open(self, uid, Vector2(vis.x * 0.5 - 90.0 * z, vis.y * 0.5 + 75.0 * z),
		func(): _rebuild())

# ============================================================ 각성 도감

## 원작 `AwakenDragonLayer` — 좌측 격자 + 우측 선택 드래곤 상세(각성스킬 이름·효과)
## + 하단 속성 필터(레퍼런스 `docs/ref/uno/각성도감.png`).
## `initDesc` 가 쓰는 프레임: `common/skill_evolution`(각성스킬 틀) · `skill/evolution/<no>.png`
## · `common/element_bg` · `scene/mamorudiclab/e_symbol`.
## 원작 `AwakenDragonLayer::onClickTap` 의 속성 탭. 아이콘은 `item/item_small/ele_*` —
## 둥지 상단바(`cave.gd` ELE_SMALL)와 **같은 원본 프레임 세트**다.
## ⚠️ 프레임명은 완성형 키로 적는다(접두사 조립은 asset_index 오집계를 만든다 — cave.gd 주석 참조).
const DEX_ELEMENTS := [
	{"key": "", "icon": "item_item_small_ele_all"},
	{"key": "fire", "icon": "item_item_small_ele_fire"},
	{"key": "aqua", "icon": "item_item_small_ele_water"},
	{"key": "earth", "icon": "item_item_small_ele_ground"},
	{"key": "wind", "icon": "item_item_small_ele_wind"},
	{"key": "light", "icon": "item_item_small_ele_light"},
	{"key": "dark", "icon": "item_item_small_ele_dark"},
	{"key": "holy", "icon": "item_item_small_ele_holy"},
	{"key": "chaos", "icon": "item_item_small_ele_chaos"},
	{"key": "shadow", "icon": "item_item_small_ele_shadow"},
]

func _open_awaken_dex() -> void:
	# 원작 `AwakenDragonLayer` — 화면을 거의 채우는 popup4(사방 여백 10) + 좌측
	# `9patch/scroll_box`(창폭 0.5 × 420) 격자 + 우측 상세 + 하단 속성 탭.
	# 제목은 **주황 제목바 없이** 맨글자(레퍼런스 `각성도감.png`).
	# 목록은 원작 `initValues` — **도감(Book)의 종족** 중 각성스킬이 있는 것. 보유 개체가 아니다.
	var vis := _vis()
	var pop := OrigPopup.open(self, "", Vector2(vis.x - 20.0, vis.y - 20.0))
	pop.body.position.y = 10.0
	var W := pop.win_size.x
	var H := pop.win_size.y
	var tt := Label.new()
	tt.text = "각성 도감"                                         # <AwakenSkill_Info>
	tt.add_theme_font_size_override("font_size", 26)
	tt.add_theme_color_override("font_color", Color(0.25, 0.15, 0.05))
	tt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tt.position = Vector2(0, 16.0); tt.size = Vector2(W, 32.0)
	pop.content.add_child(tt)
	# 도감 종족 목록(각성스킬 배정분 ∩ 도감 등재).
	var species: Array = []
	for did in Data.dragons.keys():
		if Data.awaken_skill_of(int(did)) > 0 and UserDB.dex_seen(int(did)):
			species.append(int(did))
	species.sort()
	var state := {"elem": "", "sel": (species[0] if not species.is_empty() else -1)}
	# 좌측 격자 상자 — scroll_box (W/2 × 420) @ (48, 150)[cocos] → y = H−150−420.
	var box_sz := Vector2(W * 0.5, 420.0)
	var box_pos := Vector2(48.0, H - 150.0 - 420.0)
	var box := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", box_sz, Rect2(65, 65, 6, 6))
	if box:
		box.position = box_pos
		pop.content.add_child(box)
	var grid_host := Control.new()
	grid_host.position = box_pos + Vector2(14.0, 12.0)
	grid_host.size = box_sz - Vector2(28.0, 24.0)
	pop.content.add_child(grid_host)
	# 우측 상세 영역 = 상자 오른끝~창 오른끝의 가운데(원작 CCLayerColor 배치).
	var detail := Control.new()
	detail.position = Vector2(box_pos.x + box_sz.x + 24.0, box_pos.y)
	detail.size = Vector2(W - (box_pos.x + box_sz.x) - 64.0, box_sz.y)
	pop.content.add_child(detail)
	# ⚠️ 자기참조 콜백은 딕셔너리 간접 참조로(`[[dv2-gdscript-lambda-self-capture]]`).
	var fns := {}
	var redraw := func(): (fns["redraw"] as Callable).call()
	fns["redraw"] = func():
		for c in grid_host.get_children(): c.queue_free()
		for c in detail.get_children(): c.queue_free()
		var scroll := ScrollContainer.new()
		scroll.size = grid_host.size
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		grid_host.add_child(scroll)
		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		scroll.add_child(grid)
		for did in species:
			var el := String(Data.get_dragon(int(did)).get("element", ""))
			if String(state["elem"]) != "" and el != String(state["elem"]): continue
			grid.add_child(_dex_cell(int(did), state, redraw))
		if int(state["sel"]) > 0:
			_dex_detail(detail, int(state["sel"]))
	# 하단 속성 필터 — 원작 `onClickTap` + `common/element_bg`(원형 판) + `item/item_small/ele_*`.
	var fx := W * 0.5 - (DEX_ELEMENTS.size() * 66.0 - 6.0) * 0.5
	for ent in DEX_ELEMENTS:
		var el := String(ent["key"])
		var holder := Control.new()
		holder.position = Vector2(fx, H - 110.0)
		holder.size = Vector2(60.0, 60.0)
		pop.content.add_child(holder)
		var eb := AtlasUI.spr("common_ui", "common_element_bg", 0.62)
		if eb: eb.position = Vector2(30.0, 30.0); holder.add_child(eb)
		var ei := AtlasUI.spr("item_small_ui", String(ent["icon"]), 0.62)
		if ei: ei.position = Vector2(30.0, 30.0); holder.add_child(ei)
		if String(state["elem"]) != el:
			holder.modulate = Color(0.62, 0.62, 0.66)
		var b := Button.new(); b.flat = true; b.size = Vector2(60.0, 60.0)
		b.pressed.connect(func():
			state["elem"] = el
			redraw.call())
		holder.add_child(b)
		fx += 66.0
	redraw.call()

## 격자 칸 1개 — 원작 `AwakenCell`: 바탕 `scene/cave/dragonbg_nomal`(선택 시
## **`dragonbg_master`** 노란 판으로 교체) + `scene/cave/dragon_box` 액자 + 초상.
## 아직 각성 안 한 종족은 초상만 어둡게(원작 미각성 분기).
func _dex_cell(did: int, state: Dictionary, redraw: Callable) -> Control:
	var awk := UserDB.dex_awakened(did)
	var sel := int(state["sel"]) == did
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(100.0, 100.0)
	var bgk := "scene_cave_dragonbg_master" if sel else "scene_cave_dragonbg_nomal"
	var bg := AtlasUI.spr("cave_ui", bgk, 1.0)
	if bg:
		bg.position = Vector2(50.0, 50.0)
		bg.scale = Vector2(100.0 / maxf(1.0, bg.texture.get_width()),
			100.0 / maxf(1.0, bg.texture.get_height()))
		cell.add_child(bg)
	var box := AtlasUI.spr("cave_ui", "scene_cave_dragon_box", 1.0)
	if box:
		box.position = Vector2(50.0, 50.0)
		box.scale = Vector2(100.0 / maxf(1.0, box.texture.get_width()),
			100.0 / maxf(1.0, box.texture.get_height()))
		cell.add_child(box)
	var tex := _portrait(did, "adult")
	if tex != null:
		var s := Sprite2D.new(); s.texture = tex; s.material = _pma
		var k: float = minf(76.0 / maxf(1.0, float(tex.get_width())),
			76.0 / maxf(1.0, float(tex.get_height())))
		s.scale = Vector2(k, k); s.position = Vector2(50.0, 50.0)
		if not awk: s.modulate = Color(0.40, 0.40, 0.46)
		cell.add_child(s)
	var b := Button.new(); b.flat = true; b.size = Vector2(100.0, 100.0)
	b.pressed.connect(func():
		state["sel"] = did
		redraw.call())
	cell.add_child(b)
	return cell

## 우측 상세 — 원작 `initWidget`/`onClickDragon`: 이름(위) + `e_symbol`(드래곤 뒤 문양)
## + 드래곤 스파인 "wait" + 하단 `9patch/text_box`(패널폭−30 × 150) 안에
## `common/skill_evolution` 틀 + `skill/evolution/<icon>` + 스킬명(빨강) + 효과문(#81431d).
func _dex_detail(host: Control, did: int) -> void:
	var S := Design.ASSET_SCALE
	var info: Dictionary = Data.get_dragon(did)
	var pw := host.size.x
	var nl := Label.new()
	nl.text = String(info.get("name", "드래곤"))
	nl.add_theme_font_size_override("font_size", 22)
	nl.add_theme_color_override("font_color", Color(0.25, 0.15, 0.05))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.position = Vector2(0, 0); nl.size = Vector2(pw, 30.0)
	host.add_child(nl)
	# `scene/mamorudiclab/e_symbol`(225×225) — 드래곤 **뒤 배경 문양**(anchor 0.5,1 @ 패널 상단).
	var sym := _spr("e_symbol", 0.8)
	if sym:
		sym.position = Vector2(pw * 0.5, 130.0)
		sym.modulate = Color(1, 1, 1, 0.55)
		host.add_child(sym)
	# 드래곤 스파인(원작 "wait") — 발을 문양 하단쯤에.
	var sp := _dragon_node(did, "adult", 0.55 * S)
	sp.position = Vector2(pw * 0.5, 212.0)
	host.add_child(sp)
	var aw_no := Data.awaken_skill_of(did)
	if aw_no <= 0:
		return
	var sk: Dictionary = Data.skill_awaken_for(aw_no)
	# 하단 정보 상자 — text_box (패널폭−30) × 150, 패널 바닥.
	var tb_sz := Vector2(pw - 10.0, 150.0)
	var tb := AtlasUI.nine("ninepatch_ui", "9patch_text_box", tb_sz, Rect2(25, 25, 3, 3))
	if tb:
		tb.position = Vector2(5.0, host.size.y - tb_sz.y)
		host.add_child(tb)
	var ty := host.size.y - tb_sz.y
	# 각성스킬 틀 + 아이콘 — 상자 왼쪽 위에 겹친다(레퍼런스 `각성도감.png`).
	var fr := AtlasUI.spr("common_ui", "common_skill_evolution", 0.7 * S)
	if fr: fr.position = Vector2(36.0, ty + 30.0); host.add_child(fr)
	var ico := int(sk.get("icon", 0))
	if ico > 0:
		var ip := "res://assets/converted/skill_evolution/skill_evolution_%d.tres" % ico
		if ResourceLoader.exists(ip):
			var it: Texture2D = load(ip)
			var si := Sprite2D.new(); si.texture = it; si.material = _pma
			var ik := 34.0 / maxf(1.0, float(it.get_width()))
			si.scale = Vector2(ik, ik); si.position = Vector2(36.0, ty + 30.0)
			host.add_child(si)
	var sn := Label.new()
	sn.text = String(sk.get("name", ""))
	sn.add_theme_font_size_override("font_size", 17)
	sn.add_theme_color_override("font_color", Color(0.86, 0.16, 0.12))
	sn.position = Vector2(84.0, ty + 14.0); sn.size = Vector2(pw - 100.0, 24.0)
	host.add_child(sn)
	var se := Label.new()
	se.text = String(sk.get("comment", ""))
	se.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	se.add_theme_font_size_override("font_size", 15)
	se.add_theme_color_override("font_color", Color(0.51, 0.26, 0.11))   # 원작 #81431d
	se.position = Vector2(84.0, ty + 40.0); se.size = Vector2(pw - 100.0, 100.0)
	host.add_child(se)

# ============================================================ 공용 헬퍼

## 드래곤 초상 — 도감·둥지와 같은 규약(`portrait_<id>/dragon_dragon_<id>_box_<stage>`).
## 그 단계 프레임이 없으면 성체 → 알 순으로 내려간다.
func _portrait(did: int, stage: String) -> Texture2D:
	for st in [stage, "adult", "child", "baby"]:
		var p := "res://assets/converted/portrait_%d/dragon_dragon_%d_box_%s.tres" % [did, did, st]
		if ResourceLoader.exists(p):
			return load(p)
	return Icons.dragon_egg_texture(did)

## 변환된 스파인 씬을 붙이고 "animation" 을 반복 재생(원작 setAnimation(…, loop=true)).
func _spine(path: String, at: Vector2, scale: float) -> Node2D:
	if not ResourceLoader.exists(path):
		return null
	var n := (load(path) as PackedScene).instantiate() as Node2D
	n.position = at
	n.scale = Vector2(scale, scale)
	add_child(n)
	var ap := n.get_node_or_null("AnimationPlayer")
	if ap and ap.has_animation("animation"):
		ap.get_animation("animation").loop_mode = Animation.LOOP_LINEAR
		ap.play("animation")
	return n

func _confirm(title: String, body: String, on_ok: Callable) -> void:
	var pop := OrigPopup.open(self, title, Vector2(560.0, 300.0))
	var l := Label.new(); l.text = body
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.30, 0.18, 0.06))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(50.0, 90.0); l.size = Vector2(460.0, 100.0)
	pop.content.add_child(l)
	pop.add_action_button("확인", func():
		pop.close()
		on_ok.call())

## 원작 `MakeMasicStonePopup` 1:1 — **각성마석 제작 성공 팝업**.
##
## 이 클래스의 유일한 호출자가 `DragonAwaken::makeCompletPopup`(DragonAwaken.c:1547) 이다
## ⇒ 제작 완료 시 뜨는 창이 이것이고, 종전 우리 코드는 범용 `_notice` 로 때우고 있었다.
## (⚠️ 종전에 `cave.gd` 에 있던 '정령석 제작' 이식본은 이 클래스를 **다른 기능으로 오귀속**한
##  자작이었다 — 2026-07-30 제거. 원작에 정령석 제작 팝업은 없다.)
##
## 원작 구성(MakeMasicStonePopup.c::init @01476898, skip 없음):
##   · 창 `PopupLayer::setContentSprite("9patch/popup4.png", CCRect(100,150,40,58))`
##   · SFX `music/effect_equip_success.mp3`
##   · `CCSpriteFrameCache::addSpriteFramesWithFile("stand.img_plist")` → 마석 아이콘 프레임
##   · 마석 스프라이트 @ (창폭/2, 창높이/2 + 10) · scale **1.5** · 처음 opacity 0
##   · `common/backlight3` @ (창폭/2, 창높이/2 + 105) · scale **0.7** · 처음 opacity 0
##   · `AdventureItemCount` = "%1$s  -  {#4374D9:%2$d개}" · scale 1.2 @ (창폭/2, 창높이/2 − 80)
##   · `Item::getComment()` (font_common) @ (창폭/2, 창높이/2 − 120) 앵커(0.5,1)
##   · `AdventureItemTotalCount` = "{#BDBDBD:(보유 수량 : %1$d개) }" — 설명문 아래 −15
##   · 확인 `common/check_btn` scale 1.5 @ (창폭×0.9, 창높이×0.9) — **처음엔 숨김**
## 제목 문자열 = `<AwakenMasicStonePopupTitle>` "%1$d성마석 제작 성공".
##
## 🔴 2026-07-30: **연출(타임라인)이 통째로 빠져 있었다**(사용자 지적). 원작은 정적 창이 아니라
##   액션 시퀀스로 하나씩 등장한다 — `runAction` 5건의 딜레이를 그대로 옮긴다:
##     0.4s  마석 FadeIn(0.1) → ScaleTo(0.2, 1.7) → ScaleTo(0.1, 1.5)   ← 튀어나오는 오버슈트
##     1.6s  마석 MoveBy(0.5, (0,+100))                                  ← 후광 자리로 떠오른다
##     2.0s  확인 버튼 표시(CCCallFunc)
##     2.7s  후광 FadeIn(0.3)
##     2.8s  이름+개수 FadeIn(0.3) · 2.85s 설명문·보유수량 FadeIn(0.3)
##   (라인 근거: MakeMasicStonePopup.c:242-252 · 375-390 · 391-408 · 420-433)
## ⚠️ 창 크기는 우리 값이다 — 원작 `setContentSprite` 의 크기 인자가 Ghidra 인자 밀림으로
##   모호해(200/200/150/150) 특정할 수 없다. **중심 기준 오프셋(±10/±80/±105/±120)은 원작 그대로**
##   이므로 그게 다 들어가는 높이(440)를 골랐다.
func _make_stone_complete_popup(star: int, key: String) -> void:
	Bgm.sfx("effect_equip_success")            # 원작 playEffect(:init)
	var S := Design.ASSET_SCALE
	var pop := OrigPopup.open(self, "%d성마석 제작 성공" % star, Vector2(560.0, 520.0))
	var W := pop.win_size.x
	var H := pop.win_size.y
	var cy := H * 0.5
	# 원작에 ✕ 는 없다 — `check_btn` 하나가 닫기를 겸한다(`MakeMasicStonePopup.c:411` 의
	# `CCMenuItemImageEx::createWithSpriteFrameName("common/check_btn.png", …, onclose, …)`).
	if pop.close_btn != null:
		pop.close_btn.visible = false
	# 후광 — cocos (W/2, H/2+105) → 창 로컬 y 반전. 2.7s 에 페이드인(원작엔 회전 없음).
	var bl := AtlasUI.spr("common_ui", "common_backlight3", 0.7 * S)
	if bl != null:
		bl.position = Vector2(W * 0.5, cy - 105.0)
		bl.modulate.a = 0.0
		pop.content.add_child(bl)
		var tb := create_tween()
		tb.tween_interval(2.7)
		tb.tween_property(bl, "modulate:a", 1.0, 0.3)
	# 마석 아이콘 — cocos (W/2, H/2+10) scale 1.5. 0.4s 페이드인 + 1.7→1.5 오버슈트,
	# 1.6s 에 위로 100pt(후광 자리로) 떠오른다.
	var ip := Data.item_icon_path(key)
	if ResourceLoader.exists(ip):
		var icon := Sprite2D.new()
		icon.texture = load(ip)
		icon.material = AtlasUI.pma()
		icon.position = Vector2(W * 0.5, cy - 10.0)
		icon.scale = Vector2(1.5 * S, 1.5 * S)
		icon.modulate.a = 0.0
		pop.content.add_child(icon)
		var ti := create_tween()
		ti.tween_interval(0.4)
		ti.tween_property(icon, "modulate:a", 1.0, 0.1)
		ti.tween_property(icon, "scale", Vector2(1.7 * S, 1.7 * S), 0.2)
		ti.tween_property(icon, "scale", Vector2(1.5 * S, 1.5 * S), 0.1)
		var tm := create_tween()
		tm.tween_interval(1.6)
		tm.tween_property(icon, "position:y", icon.position.y - 100.0, 0.5)
	# <AdventureItemCount> — 이름 + 얻은 개수(원작 색 #4374D9), scale 1.2 상당. 2.8s 페이드인.
	var l1 := RichTextLabel.new()
	l1.bbcode_enabled = true
	l1.fit_content = true
	l1.scroll_active = false
	l1.text = "[center]%s  -  [color=#4374D9]%d개[/color][/center]" % [Data.item_name(key), 1]
	l1.add_theme_font_size_override("normal_font_size", 21)
	l1.add_theme_color_override("default_color", Color(0.30, 0.18, 0.06))
	l1.position = Vector2(50.0, cy + 68.0); l1.size = Vector2(W - 100.0, 30.0)
	l1.modulate.a = 0.0
	pop.content.add_child(l1)
	# 원작 `Item::getComment()` = 서버 info_item.comment → 우리 출처는 items.json `desc`.
	var l3 := RichTextLabel.new()
	l3.bbcode_enabled = true
	l3.fit_content = true
	l3.scroll_active = false
	l3.text = "[center]%s[/center]" % String(Data.get_item(key).get("desc", ""))
	l3.add_theme_font_size_override("normal_font_size", 16)
	l3.add_theme_color_override("default_color", Color(0.42, 0.30, 0.16))
	l3.position = Vector2(50.0, cy + 108.0); l3.size = Vector2(W - 100.0, 52.0)
	l3.modulate.a = 0.0
	pop.content.add_child(l3)
	# <AdventureItemTotalCount> — 보유 수량(원작 색 #BDBDBD). 설명문 아래.
	var l2 := RichTextLabel.new()
	l2.bbcode_enabled = true
	l2.fit_content = true
	l2.scroll_active = false
	l2.text = "[center][color=#BDBDBD](보유 수량 : %d개)[/color][/center]" % UserDB.item_count(key)
	l2.add_theme_font_size_override("normal_font_size", 15)
	l2.position = Vector2(50.0, cy + 160.0); l2.size = Vector2(W - 100.0, 24.0)
	l2.modulate.a = 0.0
	pop.content.add_child(l2)
	for pair in [[l1, 2.8], [l3, 2.85], [l2, 2.85]]:
		var tl := create_tween()
		tl.tween_interval(float(pair[1]))
		tl.tween_property(pair[0], "modulate:a", 1.0, 0.3)
	# 확인 — 원작 `common/check_btn` scale 1.5 @ cocos (W×0.9, H×0.9), 2.0s 뒤에 나타난다.
	var okr := Control.new()
	var oks := AtlasUI.size_pt("common_ui", "common_check_btn") * 1.5
	if oks == Vector2.ZERO:
		oks = Vector2(64.0, 64.0)
	okr.size = oks
	okr.position = Vector2(W * 0.9, H * 0.1) - oks * 0.5
	okr.visible = false
	pop.content.add_child(okr)
	var okspr := AtlasUI.spr("common_ui", "common_check_btn", 1.5 * S)
	if okspr != null:
		okspr.position = oks * 0.5
		okr.add_child(okspr)
	var okb := Button.new()
	okb.flat = true
	okb.size = oks
	okb.pressed.connect(func(): pop.close())
	okr.add_child(okb)
	var tk := create_tween()
	tk.tween_interval(2.0)
	tk.tween_callback(func(): okr.visible = true)

func _notice(title: String, body: String) -> void:
	var pop := OrigPopup.open(self, title, Vector2(560.0, 280.0))
	var l := Label.new(); l.text = body
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.30, 0.18, 0.06))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(50.0, 88.0); l.size = Vector2(460.0, 100.0)
	pop.content.add_child(l)
	pop.add_action_button("확인", func(): pop.close())
