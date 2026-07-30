extends Control
## Town(마을) 씬 — 가로 시차(parallax) 스크롤. render 층. (CLAUDE.md §10)
## 근거 레시피: docs/ref/design/render_recipe_town.md (TownScrollBgLayer 가로 스크롤 + 깊이별 시차).
## 좌표: 692 고정높이(design.gd). 지면선 = FLOOR(=692). 마우스 드래그로 가로 스크롤.
## 전환: 반드시 Scenes.goto() 경유(씬끼리 직접 로드 금지, §10.4).
##
## 두 종류 마을을 한 스키마로:
##  - dwarf = 방이 화면높이를 채움(fill_h). 3레이어(back/front/rock)가 방마다 바닥에 쌓임.
##  - elpis = 밴드 적층(하늘/원경 산/마을띠/길바닥) + 인터랙티브 건물(shop/lab/fortune…) + 낮/밤.
##
## ⚠️ dwarf 의 밴드 y(bottom)·시차 motion 은 아직 자작값 — # ASSUMPTION.
## elpis 는 2026-07-27 에 원작 `TownObjectManager::makeObjMenu` 좌표로 재구성했다(아래).

const FLOOR := 692.0   # = Design.DESIGN_HEIGHT, 지면선(godot y-down). FIXED_HEIGHT 정책.

# 구역 정의(데이터 주도). 스키마:
#   dir, title, seg_w(공유 방폭), [fill_h→scale=692/fill_h | scale], has_night, sky_day/sky_night
#   layers: [{frames:[방1,방2] 또는 [단일], motion, bottom(=지면 위 px, 기본0), night_frames?}]
#   objects/ambient: [{frame|spine|flip, x, y, anchor, night?, action?}]
#     · x,y = **원작 마을 좌표(포인트, y는 화면 바닥 기준 up)** → godot_y = FLOOR - y
#     · anchor: "center"(기본) · "bottom"(0.5,0 = 바닥중심) · "left"(원작이 폭*0.5+X 로 준 값 = 왼쪽끝)
#     · CLAUDE.md §9 규칙2 — 원작 좌표 리터럴은 이미 포인트라 ASSET_SCALE 을 다시 곱하지 않는다.
const AREAS := {
	"dwarf": {
		"dir": "town_dwarf",
		"title": "드워프 마을",
		"fill_h": 523.0,   # 방 배경이 692를 채움
		"seg_w": 1013.0,
		"layers": [
			{"frames": ["scene_town_dwarf_bg1_dwarf_back1", "scene_town_dwarf_bg2_dwarf_back2"], "motion": 0.85},
			{"frames": ["scene_town_dwarf_bg1_dwarf_front1", "scene_town_dwarf_bg2_dwarf_front2"], "motion": 1.0},
			{"frames": ["scene_town_dwarf_bg1_dwarf_rock1", "scene_town_dwarf_bg2_dwarf_rock2"], "motion": 1.05},
		],
	},
	# ── 엘피스: 원작 `TownObjectManager::makeObjMenu` + `TownLayer` 축자 이식 ────────────
	# 🔬 **원작 엘피스는 단일 스트립이 아니라 4개 섹션(시차 평면)이다.**
	#   근거: `TownElpisScene::initScrollView` 가 `TownLayer::create(0/1/3/2)` 를 **그 순서로** 만들어
	#   같은 부모에 붙인다(0 이 뒤, 2 가 앞). `TownLayer::init` 은 인자를 `this+0x224` 에 저장하고,
	#   `initWidget` 과 `makeObjMenu` 가 **같은 값으로 분기**해 밴드와 오브젝트를 나눠 갖는다.
	#     섹션0 = elpis_sky(tag 0x1f5), 폭 1229 = 뷰포트 → 스크롤 없음
	#     섹션1 = elpis_mt(0x20e)              · 오브젝트 없음
	#     섹션3 = b01+b02(0x211/0x212) 마을띠  · 연구소·상점·운세·의뢰판·오리·상자·가로등5
	#     섹션2 = a01+a02(0x20f/0x210) 지면    · 종탑·시계·분수·우편함·둥지
	#   ⇒ **좌표는 섹션마다 다른 공간**이다. 교차검증(전부 4/3배·offset 0):
	#     · 가로등(섹션3) 5개 x 와 b01/b02 에 그려진 기둥 위치가 일치
	#     · 분수(섹션2) x=1806 과 a01 우단에 그려진 분수가 일치(a01 = 0~1813.3)
	#     · 둥지(섹션2) x=3526 이 지면폭 3626.7 직전
	#   시차는 폭에서 유도한다 — motion = (섹션폭 − 뷰포트) / (최대폭 − 뷰포트).
	#   (종전엔 4섹션을 한 스트립에 합치고 motion 을 자작해, 마을 오른쪽 끝에 밴드가 끊긴
	#    빈 하늘이 남고 가로등 기둥과 광원이 어긋났다.)
	# 상세/추출 재현법: docs/ref/porting/TownElpisObjects.md
	"elpis": {
		"dir": "town_elpis",
		"title": "엘피스 마을",
		"asset_scale": true,      # 원작 스케일(4/3, CLAUDE.md §9)
		"has_night": true,
		"sky_day": Color(0.62, 0.82, 0.95),
		"sky_night": Color(0.09, 0.11, 0.24),
		# 하늘 이미지(원작 섹션 0). 폭 1231 = 디자인 뷰포트라 1:1, 스크롤하지 않는다.
		"sky_image": "res://assets/converted/town_elpis_sky/elpis_sky.jpg",
		"sky_image_night": "res://assets/converted/town_elpis_sky/elpis_sky_night.jpg",
		# 섹션은 원작 생성 순서(1→3→2) 그대로 = 뒤에서 앞으로(0=하늘은 sky_image 로 따로).
		# ⚠️ 밴드 y(bottom)는 원작이 .rodata 테이블(DAT_022bba58/68/70)에서 읽어 디컴프에 안 나온다.
		#   아트·오브젝트로 역산: 지면(2)=0(원작이 y=0.0 을 축자로 준다) ·
		#   마을띠(3)=120(b01 램프머리 행95 → B+221.3 = 광원 y 341) · 원경산(1)=250.
		"sections": [
			{"id": 1, "seg_w": 1156.0, "bottom": 250.0,
			 "frames": ["scene_town_elpis_bg_elpis_mt", "scene_town_elpis_bg_elpis_mt"],
			 "night_frames": ["scene_town_elpis_bg_night_elpis_mt", "scene_town_elpis_bg_night_elpis_mt"]},
			{"id": 3, "seg_w": 1168.0, "bottom": 120.0,
			 "frames": ["scene_town_elpis_bg_u_village_bg_b01", "scene_town_elpis_bg_u_village_bg_b02"],
			 "night_frames": ["scene_town_elpis_bg_night_u_village_bg_b01", "scene_town_elpis_bg_night_u_village_bg_b02"],
			 "objects": [
				{"frame": "scene_town_elpis_u_village_shop", "night": "scene_town_elpis_u_village_shop_night",
				 "x": 1658.0, "y": 326.0, "anchor": "left", "action": "shop", "label": "상점"},
				{"frame": "scene_town_elpis_u_village_shopname", "x": 1843.0, "y": 496.0, "anchor": "left"},
				{"frame": "scene_town_elpis_u_village_shop_book", "x": 1664.0, "y": 166.0, "anchor": "left"},
				{"frame": "scene_town_elpis_u_village_labname", "x": 872.0, "y": 318.0, "anchor": "left"},
				{"frame": "scene_town_elpis_u_village_lab_book", "x": 611.0, "y": 165.0, "anchor": "left"},
				{"frame": "scene_town_elpis_u_village_fortune", "night": "scene_town_elpis_u_village_fortune_night",
				 "x": 2831.0, "y": 254.0, "anchor": "left", "action": "fortune", "label": "운세"},
				{"frame": "scene_town_elpis_u_village_fortune_book", "x": 2812.0, "y": 105.0, "anchor": "left"},
				# ⚪ 의뢰 게시판 — **원작에서 클릭해도 아무 일도 일어나지 않는다.**
				# `makeObjMenu` 가 히트영역(CCLayerColor 130×120, tag 0x11)을 깔긴 하는데
				# `onClickMenu` 의 `param_2 == 0x11` 분기가 조기 반환한다(`goto LAB_01a83178`).
				# 마을 퀘스트는 게시판이 아니라 **NPC + HUD 두루마리(tag 0x2c1)** 로 받는다.
				# ⇒ 종전에 여기 달아 두었던 `action: "quest"` 는 자작이라 뗐다(2026-07-31).
				{"frame": "scene_town_elpis_u_village_order", "x": 619.0, "y": 151.0, "anchor": "bottom"},
				{"frame": "scene_town_elpis_u_village_order_book", "x": 608.0, "y": 165.0},
				{"frame": "scene_town_elpis_town_flower", "x": 2784.0, "y": 189.0},
			 ],
			 "ambient": [
				# 사용자 검수 조정: 원작 (959,567) → 누적 왼쪽 26 · 위 50 = (933, 617).
				# 🔴 밤은 따로 잡는다 — 낮 프레임의 원본 캔버스가 498×255 인데 밤은 201×176 이라
				#    같은 좌표를 줘도 굴뚝에서 어긋난다(트림 오프셋 기준이 다르다).
				#    night_x/night_y = 사용자 검수(2026-07-29): 낮 기준에서 오른쪽 20 · 아래 40.
				# ⚠️ **연구소보다 앞에 배치**해 연구소 건물 **뒤**로 그려지게 한다(같은 레이어·같은 z 에서는
				#    나중에 추가된 것이 위). z 를 음수로 주면 마을띠 밴드(z=0)보다도 뒤로 가 아예 안 보인다.
				{"flip": "scene_town_elpis_lab_smog_lab_smog_%s0%d", "n": 10, "day_key": "a", "night_key": "n",
				 "dir": "town_elpis_smog", "x": 933.0, "y": 617.0,
				 "night_x": 953.0, "night_y": 577.0},
				{"spine": "u_village_lab", "anim": "nomal", "x": 903.0, "y": 330.0,
				 "action": "lab", "label": "연구소"},
				{"spine": "duck", "anim": "animation", "x": 2628.0, "y": 153.0},
				{"flip": "scene_town_elpis_f_star%d", "n": 4, "x": 2959.0, "y": 369.0},
				# 가로등 5개 — 원작 switch(iVar2) case 0~4, tag=0x209+i, anim "normal" loop.
				# ⚠️ case 1 의 x 는 지역변수(local_164=1111)라 상수로 안 잡혔다 → 그 값 사용.
				{"spine": "u_village_light_spine", "anim": "normal", "x": 530.0, "y": 341.0},
				{"spine": "u_village_light_spine", "anim": "normal", "x": 1111.0, "y": 341.0},
				{"spine": "u_village_light_spine", "anim": "normal", "x": 1653.0, "y": 338.0},
				{"spine": "u_village_light_spine", "anim": "normal", "x": 2229.0, "y": 343.0},
				{"spine": "u_village_light_spine", "anim": "normal", "x": 2797.0, "y": 344.0},
			 ],
			 # 🔬 annie 만 **섹션 3** 소속이다(makeNpcMenu 의 `iVar3 == 3` 별도 분기, holder tag 0x74).
			 # **정지 NPC 확정** — 근거 3가지:
			 #   · walk 계열 애니가 없다(`wait`/`wait2`/`happy`/`quest_start` 뿐)
			 #   · `getNpcBasePoint` 에 0x74 케이스가 없다(배회 기준점 자체가 없음)
			 #   · 배회 난수 없이 좌표를 직접 준다
			 # 좌표 = 인라인 `CCPoint(1813,50) − CCPoint(900,-85)` = **(913, 135)** — 마을띠 아트의
			 # 벤치(town 933~1053) 자리다. scale = `0x3eeeeeef` = **0.4667**.
			 # `setAction` 0x133 = "wait2" 가 별도 액션으로 있다(앉은 포즈로 추정).
			 #
			 # 🔴 **잠시 내려둠(disabled)** — 우리 스파인 변환기가 이 리그를 **90° 누워** 조립한다.
			 #   실측: 애니 없이 셋업 포즈만 그려도 누워 있다 ⇒ 애니메이션이 아니라 **본 조립** 문제.
			 #   균일 회전 보정(+90°)으로는 안 펴진다(더 틀어짐). 부품 아트 자체는 정상(똑바로).
			 #   `build_spine_scene.gd` 의 본/슬롯 회전 합성을 고쳐야 하며, 고치면 아래 disabled 만 지우면 된다.
			 "npcs": [
				{"id": "annie", "tag": 0x74, "x": 1003.0, "y": 135.0, "roam": [0.0, 0.0],
				 "scale": 0.4667, "still": true, "anim": "wait"},
			 ]},
			{"id": 2, "seg_w": 1360.0, "bottom": 0.0,
			 "frames": ["scene_town_elpis_bg_u_village_bg_a01", "scene_town_elpis_bg_u_village_bg_a02"],
			 "night_frames": ["scene_town_elpis_bg_night_u_village_bg_a01", "scene_town_elpis_bg_night_u_village_bg_a02"],
			 "objects": [
				# 종탑(딩동) + 시계판/바늘. **시계판을 누르면 유타칸 밤/낮이 바뀐다**(원작
				# TownObjectManager: clockboard 옆에 CCLayerColor(200×350) tag=0x10 히트영역을
				# `clockboard.pos − size/2 − (0,70)` 에 깐다 ⇒ 중심 = 시계판 − (0,70)).
				# 길드는 §1 CUT.
				{"frame": "scene_town_elpis_u_village_dingdong", "night": "scene_town_elpis_u_village_dingdong_night",
				 "x": 1430.0, "y": 270.0},
				{"frame": "scene_town_elpis_town_clockboard", "x": 1441.0, "y": 486.0,
				 "hit_size": [200.0, 350.0], "hit_offset": [0.0, -70.0],
				 "action": "daynight", "label": "시계탑"},
				{"frame": "scene_town_elpis_town_clockpoint", "x": 1441.0, "y": 535.0},
				{"frame": "scene_town_elpis_town_door", "x": 251.0, "y": 256.0},
				{"frame": "scene_town_elpis_town_mailbox", "x": 1983.0, "y": 8.0, "anchor": "bottom"},
				{"frame": "scene_town_elpis_u_village_cave", "x": 3526.0, "y": 8.0, "anchor": "bottom",
				 "action": "cave", "label": "둥지"},
			 ],
			 "ambient": [
				{"spine": "fountain", "anim": "fountain", "x": 1806.0, "y": 184.0},
			 ],
			 # NPC — 원작 `TownNpcManager::makeNpcMenu`(8,492B, [skip>8000] 이라 --max 12000 으로 복구).
			 # 원작 구조: 투명 CCLayerColor 100×150 을 히트박스로 두고 그 안에 sd_* 스파인을 하단중앙에
			 # 붙인다. 위치는 `getNpcBasePoint(tag)` = **base(1813,50) ± 오프셋** (섹션 2 정중앙 기준)이고,
			 # 최초 배치는 그 기준점에서 `roam`(rangeX,rangeY) 범위 안 난수다. z=300.
			 # 이름·대사는 data/npc_lines.json(원작 stringsData_KR.xml, build_npc_lines.py).
			 "npcs": [
				{"id": "randolph", "qslot": 0,  "tag": 0x65, "x": 3093.0, "y": 70.0,  "roam": [200.0, 70.0],  "scale": 0.533},
				{"id": "yuria",    "qslot": 1,  "tag": 0x66, "x": 3363.0, "y": 115.0, "roam": [75.0, 20.0],   "scale": 0.533},
				{"id": "kanggalo", "qslot": 2,  "tag": 0x67, "x": 353.0,  "y": 70.0,  "roam": [180.0, 25.0],  "scale": 0.533},
				{"id": "popo",     "qslot": 3,  "tag": 0x68, "x": 2293.0, "y": 55.0,  "roam": [200.0, 35.0],  "scale": 0.533},
				{"id": "dilis",    "qslot": 4,  "tag": 0x69, "x": 1449.0, "y": 90.0,  "roam": [150.0, 25.0],  "scale": 0.533},
				{"id": "pino",     "qslot": 5,  "tag": 0x6a, "x": 713.0,  "y": 120.0, "roam": [270.0, 20.0],  "scale": 0.533},
				{"id": "romini",   "qslot": 6,  "tag": 0x6b, "x": 2663.0, "y": 65.0,  "roam": [250.0, 100.0], "scale": 0.533},
				{"id": "baruseu",  "qslot": 7,  "tag": 0x6c, "x": 1013.0, "y": 75.0,  "roam": [260.0, 55.0],  "scale": 0.533},
				{"id": "zumon",    "qslot": 8,  "tag": 0x6d, "x": 1613.0, "y": 45.0,  "roam": [300.0, 50.0],  "scale": 0.556},
				{"id": "nuri",     "qslot": 9,  "tag": 0x6e, "x": 2083.0, "y": 107.0, "roam": [250.0, 25.0],  "scale": 0.667},
				{"id": "raon",     "qslot": 10, "tag": 0x6f, "x": 1813.0, "y": 25.0,  "roam": [3000.0, 10.0], "scale": 0.533},
				{"id": "nelson",   "tag": 0x70, "x": 613.0,  "y": 135.0, "roam": [800.0, 15.0],  "scale": 0.533},
				{"id": "aria",     "tag": 0x71, "x": 3013.0, "y": 85.0,  "roam": [550.0, 30.0],  "scale": 0.533},
				{"id": "guy",      "tag": 0x72, "x": 2913.0, "y": 30.0,  "roam": [1500.0, 10.0], "scale": 0.533},
				{"id": "grandma",  "tag": 0x73, "x": 2513.0, "y": 135.0, "roam": [800.0, 15.0],  "scale": 0.533},
			 ]},
		],
		# ⚫ 미배치(상시 앰비언트가 아님): box.spine(퀘스트 상태 게이트) · euros.spine + showDia/showGold
		#    (보상·이벤트 연출) — 월드맵 showWonder/showImp 와 같은 게이트 계열.
	},
}

var _pma: CanvasItemMaterial
var _manifest: Dictionary = {}
var _area_id := "dwarf"
var _night := false
var _sky: ColorRect
var _world: Node2D
var _layers: Array = []          # [{node: Node2D, motion: float}]
var _scroll_x := 0.0
var _max_scroll := 0.0
var _sc := 1.0                   # 픽셀 스케일(fill_h 또는 scale)
var _dragging := false
var _hit_areas: Array = []       # [{rect(world), action, label}] 인터랙티브 건물 히트영역
var _clouds: Array = []          # [{node, speed, w}] 하늘 흐르는 구름(원작 showCloud)
var _hud: MainHud                # 원작 TownMainMenuLayer (town 모드)

# ---------- MainHud(town 모드)가 이 씬에 묻는 것 ----------
## 원작은 `TownManager::getElpisDic()["c_state"]` 6칸 배열에서 완료 수를 세고 `"%d/6"` 로 찍는다.
## 그 딕셔너리는 서버 테이블이라 유실 ⇒ 우리 로컬 일일퀘스트(`_QUESTS`)로 대신한다.
func town_quest_progress() -> Vector2i:
	var done := 0
	for qd in _QUESTS:
		if UserDB.quest_claimed(String(qd["key"])):
			done += 1
	return Vector2i(done, _QUESTS.size())

## 원작 `common/alert` 뱃지 — 받아갈 보상이 있으면 켠다.
func town_quest_alert() -> bool:
	for qd in _QUESTS:
		if UserDB.quest_count(String(qd["key"])) >= int(qd["goal"]) and not UserDB.quest_claimed(String(qd["key"])):
			return true
	return false

## 재화 충전(원작 tag 0x2be/0x2bf → PremiumShopScene)에서 돌아올 마을.
func town_area_id() -> String:
	return _area_id

## HUD 를 붙이거나(최초) 다시 그린다. `attach` 가 재사용/갱신을 알아서 한다.
func _refresh_hud() -> void:
	_hud = MainHud.attach(self, false, "", "town")
	if not _hud.town_close.is_connected(_on_worldmap):
		_hud.town_close.connect(_on_worldmap)
	if not _hud.town_quest.is_connected(_open_quests):
		_hud.town_quest.connect(_open_quests)

## 씬 매니저 진입점. params.area, params.night(디버그 override).
func enter(params: Dictionary = {}) -> void:
	var a: String = params.get("area", "dwarf")
	_night = _resolve_night(params)
	if a != _area_id or _world == null:
		_area_id = a
	if _pma != null:
		_rebuild()

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_rebuild()

func _rebuild() -> void:
	Bgm.play("bg_town")
	# ⚪ 앰비언트 없음 — `effect_area_village` 는 원작에서 **월드맵 유타칸의 구역 사운드**다
	#    (`WorldMapYutakanLayer::initSound` CCRect(900,700,500,300)). TownScene 소유가 아니라
	#    여기서 틀던 것은 자작이었다(2026-07-28 제거). 구역 사운드는 worldmap.gd 가 등록한다.
	for c in get_children():
		c.queue_free()
	_layers.clear()
	_hit_areas.clear()
	_npcs.clear()
	var area: Dictionary = AREAS.get(_area_id, AREAS["dwarf"])
	_manifest = _load_manifest(area["dir"])
	# asset_scale=true → 원작 스케일(4/3, CLAUDE.md §9). 아니면 구식 fill_h/scale(자작).
	if area.get("asset_scale", false):
		_sc = Design.ASSET_SCALE
	else:
		_sc = FLOOR / float(area["fill_h"]) if area.has("fill_h") else float(area.get("scale", 1.0))

	# 하늘. elpis 는 원작 섹션 0 이 `elpis_sky.jpg`(폭 1231 = 디자인 뷰포트)를 쓴다 — 스크롤 없음.
	# 단색 ColorRect 는 그 아래 기본 채움으로 남긴다(이미지 밖 영역).
	if area.has("sky_day"):
		_sky = ColorRect.new()
		_sky.color = area["sky_night"] if _night else area["sky_day"]
		_sky.set_anchors_preset(Control.PRESET_FULL_RECT)
		_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_sky)
		var skp := String(area.get("sky_image_night" if _night else "sky_image", ""))
		if skp != "" and ResourceLoader.exists(skp):
			var sky_spr := Sprite2D.new()
			sky_spr.texture = load(skp)
			sky_spr.centered = false
			add_child(sky_spr)
		_build_clouds(area)   # 원작 showCloud: 하늘에 흐르는 구름

	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)

	if area.has("sections"):
		_build_sections(area)
	else:
		_build_legacy_layers(area)

	_scroll_x = 0.0
	_apply_scroll()
	_intro_zoom()   # 원작 setZoomScale: 진입 establishing 줌
	_build_hud(area)

## 원작 섹션 구조 이식 — 섹션마다 자체 밴드 폭과 오브젝트를 갖는 시차 평면.
## 시차 계수는 자작하지 않고 **폭에서 유도**한다: 각 섹션이 자기 끝까지 정확히 도달하도록
##   motion = (섹션폭 − 뷰포트) / (최대폭 − 뷰포트)
## ⇒ 좌단(scroll 0)에서 전 섹션 왼쪽 끝이 맞고, 우단에서 전 섹션 오른쪽 끝이 맞는다.
## (종전엔 4섹션을 한 스트립에 합쳐 마을 오른쪽 끝에 밴드가 끊긴 빈 하늘이 남았다.)
func _build_sections(area: Dictionary) -> void:
	var vis_x := _vis().x
	var widths: Array = []
	for sec in area["sections"]:
		widths.append(float(sec["seg_w"]) * _sc * (sec["frames"] as Array).size())
	var max_w: float = widths.max()
	_max_scroll = maxf(0.0, max_w - vis_x)
	for i in (area["sections"] as Array).size():
		var sec: Dictionary = area["sections"][i]
		var sec_w: float = widths[i]
		var motion := 0.0
		if _max_scroll > 0.0:
			motion = clampf((sec_w - vis_x) / _max_scroll, 0.0, 1.0)
		var layer := Node2D.new()
		layer.name = "Sec%d" % int(sec.get("id", i))
		_world.add_child(layer)
		var frames: Array = sec["frames"]
		var night_frames: Array = sec.get("night_frames", frames)
		var bottom := float(sec.get("bottom", 0.0))
		var lw: float = float(sec["seg_w"]) * _sc
		for k in frames.size():
			var fr: String = night_frames[k] if _night else frames[k]
			var spr := _atlas_sprite(area["dir"], fr, _manifest, _sc)
			var h: float = float(_manifest.get(fr, {}).get("h", 260)) * _sc
			spr.position = Vector2((k + 0.5) * lw, FLOOR - bottom - h * 0.5)
			layer.add_child(spr)
		# 이 섹션 소속 오브젝트·앰비언트는 **같은 좌표 공간**이므로 같은 레이어에 넣는다.
		for ob in sec.get("objects", []):
			_place_object(layer, area["dir"], ob, area, motion)
		for am in sec.get("ambient", []):
			_place_ambient(layer, area["dir"], am, area, motion)
		for np in sec.get("npcs", []):
			_place_npc(layer, np, motion)
		_layers.append({"node": layer, "motion": motion})

## 구식 경로(dwarf) — 공유 seg_w + 자작 motion.
func _build_legacy_layers(area: Dictionary) -> void:
	var segw: float = float(area["seg_w"]) * _sc
	var town_w := segw * 2
	for ld in area["layers"]:
		var layer := Node2D.new()
		_world.add_child(layer)
		var frames: Array = ld["frames"]
		var night_frames: Array = ld.get("night_frames", frames)
		var bottom: float = float(ld.get("bottom", 0.0)) * _sc
		for i in frames.size():
			var fr: String = night_frames[i] if _night else frames[i]
			var spr := _atlas_sprite(area["dir"], fr, _manifest, _sc)
			var h: float = float(_manifest.get(fr, {}).get("h", area.get("fill_h", 260))) * _sc
			spr.position = Vector2((i + 0.5) * segw, FLOOR - bottom - h * 0.5)
			layer.add_child(spr)
		_layers.append({"node": layer, "motion": float(ld["motion"])})
	if area.has("objects"):
		var obj_layer := Node2D.new()
		_world.add_child(obj_layer)
		for ob in area["objects"]:
			_place_object(obj_layer, area["dir"], ob, area, 1.0)
		_layers.append({"node": obj_layer, "motion": 1.0})
	_max_scroll = maxf(0.0, town_w - _vis().x)

func _intro_zoom() -> void:
	if _world == null: return
	var c := _vis() * 0.5
	var s := 1.12
	_world.scale = Vector2(s, s)
	_world.position = c * (1.0 - s)   # 화면 중심을 고정한 채 줌(점 c가 c에 머묾)
	var tw := _world.create_tween().set_parallel(true)
	tw.tween_property(_world, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_world, "position", Vector2.ZERO, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## 오브젝트 1개 배치. 원작 좌표계(x,y = 마을 포인트, y는 바닥 기준 up)를 쓰는 구역은
## `asset_scale:true` 로 표시하고 좌표를 **그대로** 쓴다(§9 규칙2 — 원작 리터럴은 이미 포인트).
## 구식 구역(dwarf)은 종전대로 x·bottom 에 _sc 를 곱한다.
func _place_object(layer: Node2D, dir: String, ob: Dictionary, area: Dictionary, motion := 1.0) -> void:
	var fr: String = ob.get("night", ob["frame"]) if (_night and ob.has("night")) else ob["frame"]
	var spr := _atlas_sprite(dir, fr, _manifest, _sc)
	var info: Dictionary = _manifest.get(fr, {})
	var w: float = float(info.get("w", 100)) * _sc
	var h: float = float(info.get("h", 100)) * _sc
	var c := _obj_center(ob, area, w, h)
	spr.position = c
	layer.add_child(spr)
	# 클릭은 _gui_input에서 world좌표 히트테스트로 처리 — 여기선 히트영역만 기록.
	if String(ob.get("action", "")) != "":
		# 히트영역은 기본이 프레임 크기지만, 원작이 별도 `CCLayerColor` 로 잡는 곳은
		# `hit_size`(폭,높이) + `hit_offset`(마을좌표, +y=위) 로 그 크기를 그대로 쓴다.
		var hw := w
		var hh := h
		var hc := c
		if ob.has("hit_size"):
			var hs: Array = ob["hit_size"]
			hw = float(hs[0]) * _sc
			hh = float(hs[1]) * _sc
		if ob.has("hit_offset"):
			var ho: Array = ob["hit_offset"]
			hc = c + Vector2(float(ho[0]) * _sc, -float(ho[1]) * _sc)
		_hit_areas.append({"rect": Rect2(hc.x - hw * 0.5, hc.y - hh * 0.5, hw, hh), "motion": motion,
			"action": String(ob["action"]), "label": String(ob.get("label", ""))})

## 배치 좌표 → godot 중심좌표. anchor: center(기본) / left(원작 `폭*0.5+X`) / bottom(0.5,0).
func _obj_center(ob: Dictionary, area: Dictionary, w: float, h: float) -> Vector2:
	if not area.get("asset_scale", false):
		var bottom: float = float(ob.get("bottom", 0.0)) * _sc
		return Vector2(float(ob["x"]) * _sc, FLOOR - bottom - h * 0.5)
	var x := float(ob["x"])
	var y := float(ob.get("y", 0.0))
	match String(ob.get("anchor", "center")):
		"left":   return Vector2(x + w * 0.5, FLOOR - y)
		"bottom": return Vector2(x, FLOOR - y - h * 0.5)
		_:        return Vector2(x, FLOOR - y)

## 앰비언트 1개. spine(scenes/town_fx/*.tscn) 또는 flip(프레임 시퀀스, 0.2s — 원작 getMapAnimation 관례).
const _TOWN_FLIP_DELAY := 0.2
func _place_ambient(layer: Node2D, dir: String, am: Dictionary, area: Dictionary, motion := 1.0) -> void:
	# 밤 전용 좌표(night_x/night_y)가 있으면 그것으로 배치한다 — 낮/밤 프레임의 원본 캔버스가
	# 다른 앰비언트(연구소 연기)는 같은 좌표로 두면 밤에만 어긋난다.
	var am2 := am
	if _night and (am.has("night_x") or am.has("night_y")):
		am2 = am.duplicate()
		am2["x"] = am.get("night_x", am.get("x", 0.0))
		am2["y"] = am.get("night_y", am.get("y", 0.0))
	var pos := _obj_center(am2, area, 0.0, 0.0)
	if am.has("spine"):
		var sp := "res://scenes/town_fx/%s.tscn" % String(am["spine"])
		if not ResourceLoader.exists(sp):
			return
		var inst := (load(sp) as PackedScene).instantiate() as Node2D
		if inst == null:
			return
		inst.position = pos
		# 스파인은 원작 좌표계 저작이라 여기선 배율 1.0 — 마을 좌표계가 이미 원작과 같다
		# (월드맵과 달리 축척 변환이 없다. WorldMapAmbient_ElfDwarf.md §5b 대조).
		layer.add_child(inst)
		var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap:
			var an := String(am.get("anim", ""))
			if an == "" or not ap.has_animation(an):
				an = ap.get_animation_list()[0] if ap.get_animation_list().size() > 0 else ""
			if an != "":
				var anim := ap.get_animation(an)
				if anim: anim.loop_mode = Animation.LOOP_LINEAR
				ap.play(an)
		if String(am.get("action", "")) != "":
			_hit_areas.append({"rect": Rect2(pos.x - 90.0, pos.y - 110.0, 180.0, 220.0), "motion": motion,
				"action": String(am["action"]), "label": String(am.get("label", ""))})
		return
	if not am.has("flip"):
		return
	var fdir := String(am.get("dir", dir))
	var fman: Dictionary = _load_manifest(fdir) if fdir != dir else _manifest
	var pat := String(am["flip"])
	var daynight: bool = am.has("day_key")
	var keys: Array = []
	for i in range(1, int(am.get("n", 1)) + 1):
		# 원작은 낮/밤 세트를 `lab_smog_a0%d` / `lab_smog_n0%d` 로 부른다(i=10 → "a010").
		var k: String = (pat % [String(am["night_key"] if _night else am["day_key"]), i]) if daynight else (pat % i)
		if fman.has(k): keys.append(k)
	if keys.is_empty():
		return
	var spr := _atlas_sprite(fdir, String(keys[0]), fman, _sc)
	spr.z_index = int(am.get("z", 0))
	layer.add_child(spr)
	# 🔴 트림 오프셋 적용 — 이걸 빼면 연기가 굴뚝이 아니라 허공에서 피어오른다.
	# 원작은 `CCSprite::createWithSpriteFrameName` 이 plist 의 sourceSize(=498×255) 캔버스를
	# 지정 좌표에 중앙정렬하고 트림된 조각을 offset 만큼 밀어 넣는다. 우리 변환본은 조각만 남으므로
	# 프레임마다 크기가 달라(32×37 → 498×237) 그냥 중앙에 두면 **바닥이 프레임마다 떠다닌다**.
	# off = (조각중심 − 원본캔버스중심), cocos y-up → godot 은 y 부호를 뒤집는다.
	var frames_ta: Array = []
	for k in keys:
		var mi: Dictionary = fman.get(String(k), {})
		var o: Array = mi.get("off", [0, 0])
		frames_ta.append({"t": _atlas_tex(fdir, String(k)),
			"p": pos + Vector2(float(o[0]), -float(o[1])) * _sc})
	var tw := spr.create_tween().set_loops()
	for fr2 in frames_ta:
		var t2: Texture2D = fr2["t"]
		var p2: Vector2 = fr2["p"]
		tw.tween_callback(func():
			if t2:
				spr.texture = t2
				spr.position = p2)
		tw.tween_interval(_TOWN_FLIP_DELAY)


# ---------- NPC(원작 TownNpcManager) ----------
## 원작이 쓰는 값. `keepMovingNpcRandomly`/`keepStopingNpcRandomly` 의 난수 주기는 디컴프에서
## 상수로 안 잡혀 아래는 ASSUMPTION 이다(체감 기준). 좌표·범위·스케일은 원작 실측값.
const NPC_WALK_SPEED := 42.0     # ASSUMPTION: 걷기 속도(pt/s)
const NPC_WAIT_MIN := 1.6        # ASSUMPTION
const NPC_WAIT_MAX := 4.5        # ASSUMPTION
const NPC_HITBOX := Vector2(100.0, 150.0)   # 원작 CCLayerColor::setContentSize(100,150)

var _npcs: Array = []            # [{node, spr, ap, home, roam, id, still, walking, t}]

## NPC 1명 배치. 원작 makeNpcMenu 구조를 따른다 —
## 투명 히트박스(100×150) 안에 sd_* 스파인을 **하단 중앙**에 붙이고, 최초 위치는
## 기준점 ± roam/2 범위의 난수. z=300(원작)이라 같은 섹션의 밴드·오브젝트보다 앞.
func _place_npc(layer: Node2D, np: Dictionary, motion: float) -> void:
	if bool(np.get("disabled", false)):
		return    # 변환 산출물 결함 등으로 잠시 내려둔 NPC(사유는 데이터의 주석 참조)
	var sp := "res://scenes/npc_town/sd_%s.tscn" % String(np["id"])
	if not ResourceLoader.exists(sp):
		return
	var inst := (load(sp) as PackedScene).instantiate() as Node2D
	if inst == null:
		return
	var holder := Node2D.new()
	holder.name = "Npc_%s" % String(np["id"])
	holder.z_index = 300
	# ⚠️ ASSET_SCALE 을 곱하지 말 것 — spine_export 가 슬롯마다 1.333 을 이미 구워 넣는다
	# (scene.json sprite_scale). 원작 `setScale(0.533)` 만 그대로 얹는다.
	# 월드맵과 반대다: 거기선 bg-아틀라스 공간이 원작보다 작아 지역축척을 **더** 곱해야 했다.
	var sc := float(np.get("scale", 0.533))
	inst.scale = Vector2(sc, sc)
	holder.add_child(inst)
	layer.add_child(holder)
	var roam: Array = np.get("roam", [0.0, 0.0])
	var home := Vector2(float(np["x"]), float(np["y"]))
	var p0 := _npc_rand_point(home, roam)
	holder.position = Vector2(p0.x, FLOOR - p0.y)
	var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var rec := {"node": holder, "ap": ap, "spr": inst, "home": home, "roam": roam,
		"base_sx": sc, "facing": 1,
		"id": String(np["id"]), "still": bool(np.get("still", false)),
		"walking": false, "t": randf_range(NPC_WAIT_MIN, NPC_WAIT_MAX), "dest": holder.position}
	rec["idle_anim"] = String(np.get("anim", "wait"))
	_npcs.append(rec)
	_npc_play(rec, String(rec["idle_anim"]))
	rec["qslot"] = int(np.get("qslot", -1))
	_npc_face(rec)          # 초기 방향도 반드시 적용(종전엔 생성 직후 미적용이었다)
	_npc_quest_mark(rec)
	# 클릭 히트영역(원작 히트박스 100×150, 발밑 기준).
	_hit_areas.append({"rect": Rect2(holder.position.x - NPC_HITBOX.x * 0.5,
			holder.position.y - NPC_HITBOX.y, NPC_HITBOX.x, NPC_HITBOX.y),
		"motion": motion, "action": "npc:" + String(np["id"]), "label": "", "npc": rec})

func _npc_rand_point(home: Vector2, roam: Array) -> Vector2:
	var rx := float(roam[0]); var ry := float(roam[1])
	return Vector2(home.x + randf_range(-rx * 0.5, rx * 0.5),
		home.y + randf_range(-ry * 0.5, ry * 0.5))

## 앞뒤 정렬(원작 changeNpcZorder). y 가 클수록(화면 아래=가까움) 앞에 온다.
## 🔴 **z 를 순위마다 넉넉히 벌린다.** 스파인 내부 슬롯의 z_index 는 부모 기준 **상대값**이라
##    (z_as_relative 기본 true) 홀더 z 를 촘촘히 주면 뒷사람의 얼굴(슬롯 z 최대 34)이
##    앞사람의 몸 z 구간으로 넘어가 **겹쳐 보인다**(사용자 검수 지적).
##    전 NPC 슬롯 z 최댓값이 34이므로 순위 간격을 그보다 큰 64로 둔다.
const NPC_Z_BASE := 300      # 원작 addChild(holder, 300)
const NPC_Z_STEP := 64
func _sort_npc_z() -> void:
	var live: Array = []
	for rec in _npcs:
		var n: Node2D = rec.get("node")
		if n != null and is_instance_valid(n):
			live.append(rec)
	live.sort_custom(func(a, b):
		return (a["node"] as Node2D).position.y < (b["node"] as Node2D).position.y)
	for i in live.size():
		(live[i]["node"] as Node2D).z_index = NPC_Z_BASE + i * NPC_Z_STEP

## 퀘스트 마크(원작 makeQuestMark). NPC 머리 위에 떠서 위아래로 잦아드는 부유 애니.
##   진행중  = `scene/town/elpis/txt_balloon.png`, scale 0.8
##   보상대기 = `common/alert3.png`, scale 1.3
##   위치 = holder 기준 `(width*0.5, height + 23)` · 태그 0x66 · MoveBy ±10 → ±7 → ±3, 각 0.8초 RepeatForever
## ⚠️ **어느 NPC가 어느 퀘스트를 주는지**는 원작이 `TownManager::getElpisDic` 의 서버 테이블에서
##    읽어 유실됐다. 다만 `makeNpcMenu` 가 NPC마다 넘기는 **퀘스트 슬롯 인덱스**는 남아 있어
##    (objectAtIndex(N) == makeQuestMark(…, N)) 그 순서를 그대로 쓴다:
##    0 randolph · 1 yuria · 2 kanggalo · 3 popo · 4 dilis · 5 pino · 6 romini · 7 baruseu
##    · 8 zumon · 9 nuri · 10 raon  (11~15 = nelson/aria/guy/grandma/annie 는 퀘스트 없음)
##    ⇒ 우리 로컬 일일퀘스트 `_QUESTS[i]` 를 슬롯 i 의 NPC 에 붙인다(내용 매칭은 ASSUMPTION).
const QMARK_TAG := 0x66
func _npc_quest_state(qslot: int) -> String:
	if qslot < 0 or qslot >= _QUESTS.size():
		return ""
	var qd: Dictionary = _QUESTS[qslot]
	var key := String(qd["key"])
	if UserDB.quest_claimed(key):
		return ""
	if UserDB.quest_count(key) >= int(qd["goal"]):
		return "reward"
	return "progress"

func _npc_quest_mark(rec: Dictionary) -> void:
	var node: Node2D = rec.get("node")
	if node == null or not is_instance_valid(node):
		return
	var old := node.get_node_or_null("QMark")
	if old != null:
		old.queue_free()
	var st := _npc_quest_state(int(rec.get("qslot", -1)))
	if st == "":
		return
	var dir_ := "common_ui" if st == "reward" else "town_elpis"
	var key := "common_alert3" if st == "reward" else "scene_town_elpis_txt_balloon"
	var sc := 1.3 if st == "reward" else 0.8
	var m := _atlas_sprite(dir_, key, _load_manifest(dir_), sc)
	if m.texture == null:
		return
	m.name = "QMark"
	# 원작: holder(100×150) 기준 (width*0.5, height + 23). 우리 holder 는 발밑 원점이라 위로 올린다.
	m.position = Vector2(0.0, -(NPC_HITBOX.y + 23.0))
	m.z_index = 5
	node.add_child(m)
	# MoveBy ±10 → ±7 → ±3, 각 0.8초, 무한 반복(원작 EaseExponentialOut / EaseBounceOut 교대).
	var tw := m.create_tween().set_loops()
	var y0 := m.position.y
	for amp in [10.0, 7.0, 3.0]:
		tw.tween_property(m, "position:y", y0 - amp, 0.8).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "position:y", y0, 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

## 퀘스트 상태가 바뀌면(수령 등) 전 NPC 마크를 다시 만든다(원작 refreshQuestMark).
func _refresh_quest_marks() -> void:
	for rec in _npcs:
		_npc_quest_mark(rec)

## 몸 방향 적용. scale.x 를 뒤집어 미러링한다(원작은 NPC_DIRECTION 을 저장해 두고 같은 일을 한다).
## 🔴 `NPC_FACE_SIGN = -1` — **sd_* 아트는 기본(scale.x>0)이 왼쪽을 본다.**
##    +1 로 뒀더니 전진 방향과 시선이 항상 반대라 100% 뒷걸음질이었다(사용자 검수 지적).
##    facing(+1=오른쪽으로 감) × SIGN(-1) ⇒ scale.x 가 음수가 되어 오른쪽을 본다.
const NPC_FACE_SIGN := -1
func _npc_face(rec: Dictionary) -> void:
	var spr: Node2D = rec.get("spr")
	if spr == null or not is_instance_valid(spr):
		return
	var b := float(rec.get("base_sx", 0.533))
	spr.scale.x = b * float(int(rec.get("facing", 1)) * NPC_FACE_SIGN)

func _npc_play(rec: Dictionary, an: String) -> void:
	var ap: AnimationPlayer = rec.get("ap")
	if ap == null or not ap.has_animation(an):
		return
	var a := ap.get_animation(an)
	if a: a.loop_mode = Animation.LOOP_LINEAR if an in ["wait", "walk"] else Animation.LOOP_NONE
	ap.play(an)

## 배회 상태기계(원작 keepMovingNpcRandomly / keepStopingNpcRandomly 대응).
## 정지↔걷기를 난수 주기로 오가고, 목적지는 기준점 ± roam/2 안에서 고른다.
## y 가 작을수록(화면 아래=가까움) 앞에 오도록 z 를 갱신한다(원작 changeNpcZorder).
func _process_npcs(delta: float) -> void:
	_sort_npc_z()
	for rec in _npcs:
		var node: Node2D = rec["node"]
		if not is_instance_valid(node):
			continue
		if bool(rec["still"]) or bool(rec.get("talking", false)):
			continue
		if float(rec.get("endt", 0.0)) > 0.0:
			rec["endt"] = float(rec["endt"]) - delta
			if float(rec["endt"]) <= 0.0:
				_npc_play(rec, String(rec.get("idle_anim", "wait")))
		rec["t"] = float(rec["t"]) - delta
		if bool(rec["walking"]):
			var dest: Vector2 = rec["dest"]
			var d := dest - node.position
			if d.length() <= NPC_WALK_SPEED * delta:
				node.position = dest
				rec["walking"] = false
				rec["t"] = randf_range(NPC_WAIT_MIN, NPC_WAIT_MAX)
				_npc_play(rec, "walk_end")
				rec["endt"] = 0.4   # walk_end 1회 재생 뒤 wait 로(원작 walk_end→wait)
			else:
				node.position += d.normalized() * NPC_WALK_SPEED * delta
		elif float(rec["t"]) <= 0.0:
			var np2 := _npc_rand_point(rec["home"], rec["roam"])
			var dest2 := Vector2(np2.x, FLOOR - np2.y)
			# 🔴 뒷걸음질 금지 — 출발 직전에 **몸 방향을 목적지 쪽으로 확정**한다(원작 setNpcDirection).
			# 종전엔 걷는 동안 매 프레임 scale.x 를 다시 계산해, 목적지 근처에서 d.x 부호가 떨리면
			# 방향이 깜빡이고 결과적으로 뒤로 걷는 것처럼 보였다.
			var dx := dest2.x - node.position.x
			if absf(dx) > 1.0:
				rec["facing"] = -1 if dx < 0.0 else 1
				_npc_face(rec)
			rec["dest"] = dest2
			rec["walking"] = true
			_npc_play(rec, "walk")
		# 히트영역도 따라 움직인다.
		for ha in _hit_areas:
			if ha.get("npc") == rec:
				ha["rect"] = Rect2(node.position.x - NPC_HITBOX.x * 0.5,
					node.position.y - NPC_HITBOX.y, NPC_HITBOX.x, NPC_HITBOX.y)

## NPC 클릭 → 원작 showNpcText: 이름 + 대사(순환). 말풍선 프레임 `scene/town/elpis/txt_balloon`.
var _npc_line_idx := {}
var _talking: Dictionary = {}

## 대화 종료 → 그 NPC 를 다시 배회시킨다(잠시 쉬었다 출발).
func _npc_stop_talking() -> void:
	if _talking.is_empty():
		return
	var r := _talking
	_talking = {}
	if not r.is_empty() and is_instance_valid(r.get("node")):
		r["talking"] = false
		r["t"] = randf_range(NPC_WAIT_MIN, NPC_WAIT_MAX)
		# 🔴 정지 NPC(annie)도 반드시 idle 로 되돌린다 — `still` 이면 건너뛰게 해 놨더니
		#    클릭 후 `happy`(눈 감은 포즈)에서 멈춰 있었다(사용자 검수 지적).
		_npc_play(r, String(r.get("idle_anim", "wait")))
func _on_npc_click(npc_id: String) -> void:
	var db: Dictionary = Data.npc_lines() if Data.has_method("npc_lines") else {}
	var info: Dictionary = db.get(npc_id, {})
	var lines: Array = info.get("lines", [])
	var who := String(info.get("name", ""))
	if lines.is_empty():
		return    # 대사가 없는 행인(aria/guy/grandma/nelson)은 무반응 — 원작도 쌍이 없다
	# 원작 showNpcText: 대사 번호 = `(arc4random() & 7) + 1` → 8줄 중 **무작위**.
	var i := randi() % lines.size()
	var rec := {}
	for r in _npcs:
		if String(r["id"]) == npc_id:
			rec = r; break
	# 대화가 끝날 때까지 그 자리에 선다 — 종전엔 상호작용 모션 그대로 배회를 이어가 어색했다.
	_npc_stop_talking()
	if not rec.is_empty():
		rec["talking"] = true
		rec["walking"] = false
		rec["dest"] = (rec["node"] as Node2D).position
		_talking = rec
		_npc_play(rec, "happy")   # 원작 happy 애니(있는 NPC만)
		rec["endt"] = 1.2
	_show_npc_balloon(rec, who, String(lines[i]))

## 말풍선 = 원작 `SpeechBalloonBox::init` 이식.
##   본체 `scene/town/elpis/txt_balloon2.png` 를 **CCScale9Sprite(capInsets 20,20,5,5)** 로 늘리고,
##   꼬리 `txt_balloon_bot.png`(앵커 0.5,1.0)를 아래에 붙인다. 글꼴은 getFontName_common(TTF).
## ⚠️ `txt_balloon.png` 는 대화 말풍선이 **아니라 퀘스트 마크**다(makeQuestMark 가 머리 위에 띄우고
##    보상 대기면 `common/alert3.png`) — 한 번 이걸 대화창으로 오인해 뭉갠 채 늘려 썼다.
const BALLOON_TYPE_DT := 0.05    # 원작 setString: schedule(showString, 0.05) — 글자당 0.05초
const BALLOON_WRAP_W := 250.0    # 대사 줄바꿈 폭(설계 pt)
const BALLOON_CAP := Rect2(20, 20, 16, 16)   # Cocos capInsets(20,20,5,5) → 41px 프레임의 좌/상/우/하
var _balloon: Node2D
var _balloon_lbl: Label
var _balloon_body: NinePatchRect
var _balloon_arrow: Sprite2D
var _balloon_full := ""
var _balloon_i := 0
var _balloon_t := 0.0
var _balloon_done := false
func _show_npc_balloon(rec: Dictionary, who: String, line: String) -> void:
	if _balloon != null and is_instance_valid(_balloon):
		_balloon.queue_free()
	var root := Node2D.new()
	root.z_index = 900
	root.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)   # 아틀라스 프레임은 4/3
	var pad := 14.0
	var lbl := Label.new()
	lbl.text = line
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.16, 0.12, 0.09))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var nm: Label = null
	if who != "":
		nm = Label.new()
		nm.text = who
		nm.add_theme_font_size_override("font_size", 14)
		nm.add_theme_color_override("font_color", Color(0.85, 0.45, 0.15))
	# 🔴 `get_combined_minimum_size()` 는 autowrap 라벨에서 **줄바꿈 후 높이를 안 준다**
	#    (한 줄 높이만 돌려줘서 2~3줄짜리 대사가 상자 아래로 삐져나왔다).
	#    폰트로 직접 다중행 크기를 재서 상자를 맞춘다.
	var fnt := lbl.get_theme_font("font")
	if fnt == null:
		fnt = ThemeDB.fallback_font
	var fsz := lbl.get_theme_font_size("font_size")
	if fsz <= 0:
		fsz = 15
	# 폭은 **줄바꿈 폭으로 고정**하고 높이만 잰다. 폭을 측정값으로 잡으면 한 줄이 살짝 넘칠 때
	# 상자가 안 늘어나고 글자만 삐져나온다(사용자 검수 지적).
	var wrap_w := BALLOON_WRAP_W
	var th := 20.0
	if fnt != null:
		th = fnt.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_CENTER, wrap_w, fsz).y
	var nh := 0.0
	if nm != null:
		var nf := nm.get_theme_font("font")
		if nf == null:
			nf = ThemeDB.fallback_font
		var ns := nm.get_theme_font_size("font_size")
		if ns <= 0:
			ns = 14
		nh = (nf.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, ns).y if nf != null else 18.0) + 3.0
	var w := wrap_w + pad * 2
	var h := th + nh + pad * 2
	var tsz := Vector2(wrap_w, th)
	lbl.custom_minimum_size = Vector2(wrap_w, th)
	lbl.clip_text = false
	var body := NinePatchRect.new()
	var tex := _atlas_tex("town_elpis", "scene_town_elpis_txt_balloon2")
	if tex != null:
		body.texture = tex
		body.patch_margin_left = int(BALLOON_CAP.position.x)
		body.patch_margin_top = int(BALLOON_CAP.position.y)
		body.patch_margin_right = int(BALLOON_CAP.size.x)
		body.patch_margin_bottom = int(BALLOON_CAP.size.y)
	body.size = Vector2(w, h)
	body.position = Vector2(-w * 0.5, -h)
	root.add_child(body)
	var y := pad
	if nm != null:
		nm.position = Vector2(pad, y); nm.size = Vector2(w - pad * 2, nh)
		body.add_child(nm); y += nh
	lbl.position = Vector2(pad, y); lbl.size = Vector2(w - pad * 2, tsz.y)
	body.add_child(lbl)
	# 꼬리(앵커 0.5,1.0 = 말풍선 하단 중앙에서 아래로)
	var tail := _atlas_sprite("town_elpis", "scene_town_elpis_txt_balloon_bot", _manifest, 1.0)
	if tail.texture != null:
		var tail_h := float(_manifest.get("scene_town_elpis_txt_balloon_bot", {}).get("h", 10))
		tail.position = Vector2(0, tail_h * 0.5)
		root.add_child(tail)
	add_child(root)
	_balloon = root
	_balloon.set_meta("npc", rec)
	_balloon_lbl = lbl
	_balloon_body = body
	_balloon_full = line
	_balloon_i = 0
	_balloon_t = 0.0
	_balloon_done = false
	lbl.text = ""
	_position_balloon()
	# 원작 setString 의 등장 연출: MoveBy(0.2, +y) EaseExponentialOut → MoveBy(0.1, −y) + ScaleTo(0.1, 1.0)
	var base_y := root.position.y
	root.position.y = base_y + 18.0
	root.scale = Vector2(Design.ASSET_SCALE * 0.8, Design.ASSET_SCALE * 0.8)
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(root, "position:y", base_y - 8.0, 0.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "scale", Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE), 0.2)
	tw.chain().tween_property(root, "position:y", base_y, 0.1)

## 타이프라이터 진행(원작 showString: 0.05s 마다 한 글자). 다 나오면 다음 화살표를 띄운다.
func _process_balloon(delta: float) -> void:
	if _balloon == null or not is_instance_valid(_balloon) or _balloon_done:
		return
	_balloon_t += delta
	while _balloon_t >= BALLOON_TYPE_DT and _balloon_i < _balloon_full.length():
		_balloon_t -= BALLOON_TYPE_DT
		_balloon_i += 1
		# 원작은 공백·개행을 건너뛰고 한 번에 넘긴다(showString 의 0x20/0x0a 분기).
		while _balloon_i < _balloon_full.length() and _balloon_full[_balloon_i] in [" ", "
"]:
			_balloon_i += 1
	if _balloon_lbl != null and is_instance_valid(_balloon_lbl):
		_balloon_lbl.text = _balloon_full.substr(0, _balloon_i)
	if _balloon_i >= _balloon_full.length():
		_balloon_show_all()

## 원작 showStringAll: 스케줄 해제 + 전문 표시 + 다음 화살표.
func _balloon_show_all() -> void:
	_balloon_done = true
	_balloon_i = _balloon_full.length()
	if _balloon_lbl != null and is_instance_valid(_balloon_lbl):
		_balloon_lbl.text = _balloon_full
	_balloon_next_arrow()

## 원작 showNextArrow: `common/btn_arrow2.png` 를 말풍선 우하단에 두고 ScaleTo(0.7) 을 무한 반복.
func _balloon_next_arrow() -> void:
	if _balloon == null or not is_instance_valid(_balloon) or _balloon_arrow != null:
		return
	var a := _atlas_sprite("common_ui", "common_btn_arrow2", {}, 1.0)
	if a.texture == null:
		return
	_balloon_arrow = a
	var bw := _balloon_body.size.x if _balloon_body != null else 160.0
	a.position = Vector2(bw * 0.5 - 12.0, -10.0)
	_balloon.add_child(a)
	var tw := a.create_tween().set_loops()
	tw.tween_property(a, "scale", Vector2(0.75, 0.75), 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(a, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)

## 원작 closeBox: MoveBy(0.1, +10) → MoveBy(0.1, −30) + ScaleTo(0.1) 후 제거.
func _balloon_close() -> void:
	if _balloon == null or not is_instance_valid(_balloon):
		return
	_npc_stop_talking()
	var b := _balloon
	_balloon = null
	_balloon_lbl = null
	_balloon_body = null
	_balloon_arrow = null
	var tw := b.create_tween()
	tw.tween_property(b, "position:y", b.position.y - 10.0, 0.1)
	tw.set_parallel(true)
	tw.tween_property(b, "position:y", b.position.y + 20.0, 0.1)
	tw.tween_property(b, "scale", b.scale * 0.6, 0.1)
	tw.chain().tween_callback(func(): if is_instance_valid(b): b.queue_free())

## 말풍선이 떠 있으면 클릭을 **먼저 소비**한다(원작 setPreventTouch: 대사 중 다른 입력 차단).
## 타이핑 중이면 전문 표시, 다 나왔으면 닫는다.
func _balloon_consume_click() -> bool:
	if _balloon == null or not is_instance_valid(_balloon):
		return false
	if _balloon_done:
		_balloon_close()
	else:
		_balloon_show_all()
	return true

## 말풍선을 소유 NPC 머리 위(화면좌표)로 옮긴다 — 섹션 시차를 반영해야 한다.
func _position_balloon() -> void:
	if _balloon == null or not is_instance_valid(_balloon):
		return
	var rec: Dictionary = _balloon.get_meta("npc", {})
	if rec.is_empty() or not is_instance_valid(rec.get("node")):
		return
	var node: Node2D = rec["node"]
	var m := 1.0
	for ha in _hit_areas:
		if ha.get("npc") == rec:
			m = float(ha.get("motion", 1.0)); break
	_balloon.position = Vector2(node.position.x - _scroll_x * m, node.position.y - 170.0)

## 원작 showCloud: 하늘에 구름 여러 개를 서로 다른 속도/높이로 배치 → _process에서 흐르게(래핑).
func _build_clouds(area: Dictionary) -> void:
	_clouds.clear()
	var vis := _vis()
	var cloud_node := Node2D.new(); cloud_node.name = "Clouds"
	add_child(cloud_node)
	var suffix := "_night" if _night else ""
	var rng := RandomNumberGenerator.new(); rng.seed = hash(_area_id) ^ (1 if _night else 0)
	for i in 5:
		var fr := "scene_town_elpis_town_cloud%d%s" % [(i % 5) + 1, suffix]
		var spr := _atlas_sprite(area["dir"], fr, _manifest, _sc * rng.randf_range(0.5, 0.85))
		if spr == null: continue
		var info: Dictionary = _manifest.get(fr, {})
		var w: float = float(info.get("w", 200)) * _sc
		# 상단 하늘 띠(전경 나무/건물에 안 가리도록). 낮은 y = 시야 확보.
		spr.position = Vector2(rng.randf_range(0.0, vis.x), 14.0 + float(i % 3) * 26.0 + rng.randf_range(-6, 6))
		spr.modulate.a = 0.9 if not _night else 0.7
		cloud_node.add_child(spr)
		_clouds.append({"node": spr, "speed": rng.randf_range(8.0, 22.0), "w": w})

func _process(delta: float) -> void:
	if not _npcs.is_empty():
		_process_npcs(delta)
		_position_balloon()
	_process_balloon(delta)
	if _clouds.is_empty(): return
	var vis := _vis()
	for c in _clouds:
		var spr: Sprite2D = c["node"]
		if not is_instance_valid(spr): continue
		spr.position.x += float(c["speed"]) * delta
		if spr.position.x - float(c["w"]) * 0.5 > vis.x:   # 오른쪽 밖 → 왼쪽서 재등장
			spr.position.x = -float(c["w"]) * 0.5

func _apply_scroll() -> void:
	for l in _layers:
		(l["node"] as Node2D).position.x = -_scroll_x * float(l["motion"])

# ---------- 입력(드래그 → 가로 스크롤 / 탭 → 건물). 원작 터치 → 마우스(CLAUDE.md 입력 규칙) ----------
var _press_pos := Vector2.ZERO
var _moved := false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_press_pos = event.position
			_moved = false
		elif not _moved:
			if not _balloon_consume_click():
				_try_click(event.position)
	elif event is InputEventMouseMotion and _dragging:
		if event.position.distance_to(_press_pos) > 6.0:
			_moved = true
		_scroll_x = clampf(_scroll_x - event.relative.x, 0.0, _max_scroll)
		_apply_scroll()

func _try_click(screen_pos: Vector2) -> void:
	# 섹션마다 시차가 달라 화면→월드 변환도 다르다: world_x = screen_x + _scroll_x·motion.
	for ha in _hit_areas:
		var m := float(ha.get("motion", 1.0))
		var world_pos := Vector2(screen_pos.x + _scroll_x * m, screen_pos.y)
		if (ha["rect"] as Rect2).has_point(world_pos):
			_on_object(ha["action"])
			return

func _on_object(action: String) -> void:
	if action.begins_with("npc:"):
		_on_npc_click(action.substr(4))
		return
	match action:
		"cave":
			# 원작 tag 0x208 둥지 표지판 → `CaveScene::scene(0)` + `pushScene`
			# (`onClickMenu` 의 람다 vtable 02958f40 → 0x19894f0 을 .so 에서 풀어 확인.
			#  근거·재현법 = `docs/ref/porting/TownMainMenuLayer.md` §0).
			Scenes.goto("cave")
		"worldmap":
			_on_worldmap()
		"shop":
			Scenes.goto("shop", {"area": _area_id})
		"lab":
			# 엘피스 연구소(애니) = 원작 LaboratoryScene — 알 강화/조합·드래곤 강화(장비칸)·크리스탈.
			# ⚠️ 마모루딕 연구소(우노)의 용광로/분해기(MakeSkillLayer/BreakDownSkillLayer)와 다른 곳이다.
			Scenes.goto("laboratory", {"area": _area_id})
		"fortune":
			# 점술집(유리아) = 원작 MagicShopScene(문자열 <TitleMagicShop>점술집).
			Scenes.goto("magicshop", {"area": _area_id})
		"daynight":
			# 엘피스 시계탑 — 유타칸 대륙의 밤/낮을 바꾼다(원작 확인창 → onClickChangeDayAndNight).
			_open_daynight_confirm()
		_:
			push_warning("[Town] '%s' 화면 미구현 — 스텁" % action)

## 원작 MakeSkillLayer 1:1: 마모루딕 랩 용광로(furnace) 스파인 룸 — 중앙 스파인 애니 + 좌상단 뒤로 + 스파인 탭→제작.
## 근거: MakeSkillLayer::init drawSpineCenter('scene/mamorudiclab/furnace/furnace_normal.spine_json' +
##   'furnace/normal_spine.img_plist') setAnimation("animation",loop) (MakeSkillLayer.c); leftTop back_btn setOnClickBack;
##   onClickSpine(스파인 탭 → 제작 진행). 스파인=오프라인 변환(scripts/tools/convert_lab_furnace.py → scenes/fx/lab_furnace.tscn).
func _open_lab_furnace() -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 60; add_child(layer)
	var bg := ColorRect.new(); bg.color = Color(0.05, 0.04, 0.08, 1.0); bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	# 용광로 스파인 중앙(원작 drawSpineCenter) + "animation" 루프.
	var sp := "res://scenes/fx/lab_furnace.tscn"
	if ResourceLoader.exists(sp):
		var spine := (load(sp) as PackedScene).instantiate()
		spine.position = Vector2(vis.x * 0.5, vis.y * 0.5 + 60.0)   # 중앙(약간 아래=바닥 정렬)
		layer.add_child(spine)
		var ap := spine.get_node_or_null("AnimationPlayer")
		if ap:
			ap.get_animation("animation").loop_mode = Animation.LOOP_LINEAR if ap.has_animation("animation") else 0
			ap.play("animation")
		# onClickSpine(원작): 스파인 탭 → 스킬 제작 팝업.
		var hit := Button.new(); hit.flat = true; hit.size = Vector2(320, 320)
		hit.position = Vector2(vis.x * 0.5 - 160, vis.y * 0.5 - 100)
		hit.pressed.connect(_open_lab_make_skill); layer.add_child(hit)
	var title := Label.new(); title.text = "마모루딕 연구소 — 스킬 제작"
	title.add_theme_font_size_override("font_size", 22); title.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.size = Vector2(vis.x, 30); title.position = Vector2(0, 24)
	layer.add_child(title)
	var hint := Label.new(); hint.text = "용광로를 눌러 스킬 스크롤을 제작하세요"
	hint.add_theme_font_size_override("font_size", 16); hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.7))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hint.size = Vector2(vis.x, 22); hint.position = Vector2(0, vis.y - 44)
	layer.add_child(hint)
	# 스킬 분해 룸(원작 BreakDownSkillLayer machine)로 전환.
	var brk := Button.new(); brk.text = "스킬 분해 →"; brk.size = Vector2(130, 40); brk.position = Vector2(vis.x - 150, 24)
	brk.pressed.connect(func():
		if is_instance_valid(layer): layer.queue_free()
		_open_lab_machine())
	layer.add_child(brk)
	# 좌상단 뒤로(원작 leftTop back_btn setOnClickBack).
	var back := _atlas_sprite("common_ui", "common_back_btn", _load_manifest("common_ui"), 0.8)
	var bb := Button.new(); bb.flat = true; bb.size = Vector2(64, 48); bb.position = Vector2(12, 12)
	bb.pressed.connect(func(): if is_instance_valid(layer): layer.queue_free()); layer.add_child(bb)
	if back: back.position = Vector2(40, 34); layer.add_child(back)

## 원작 BreakDownSkillLayer 1:1: 마모루딕 랩 분해기(machine) 스파인 룸 — 중앙 스파인 애니 + 좌상단 뒤로 + 스파인 탭→분해.
## 근거: BreakDownSkillLayer::drawSpineCenter (BreakDownSkillLayer.c:36) VisibleRect 중앙 CCSkeletonAnimation
##   'scene/mamorudiclab/machine/bg_black_island.spine_json'+'machine/normal_spine.img_plist' setAnimation("animation",true,0)(:81);
##   RoundedButton→onClickSpine(:87); common/back_btn.png @leftTop(:97). onClickSpine→BreakDownSkillPopupBox(:184, 별도 엔티티).
## 스파인=오프라인 변환(convert_lab_furnace.py→scenes/fx/lab_machine.tscn). ⚠️ 분해 결과(스킬→재료 환원)=서버 유실(원칙2).
func _open_lab_machine() -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 60; add_child(layer)
	var bg := ColorRect.new(); bg.color = Color(0.03, 0.03, 0.06, 1.0); bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var sp := "res://scenes/fx/lab_machine.tscn"
	if ResourceLoader.exists(sp):
		var spine := (load(sp) as PackedScene).instantiate()
		spine.position = Vector2(vis.x * 0.5, vis.y * 0.5 + 40.0)   # 원작 drawSpineCenter(VisibleRect 중앙)
		layer.add_child(spine)
		var ap := spine.get_node_or_null("AnimationPlayer")
		if ap and ap.has_animation("animation"):
			ap.get_animation("animation").loop_mode = Animation.LOOP_LINEAR
			ap.play("animation")
		# onClickSpine(원작 RoundedButton→BreakDownSkillPopupBox): 분해기 탭 → 분해 팝업(별도 엔티티, 결과=유실).
		var hit := Button.new(); hit.flat = true; hit.size = Vector2(320, 320)
		hit.position = Vector2(vis.x * 0.5 - 160, vis.y * 0.5 - 120)
		hit.pressed.connect(_open_lab_breakdown); layer.add_child(hit)
	var title := Label.new(); title.text = "마모루딕 연구소 — 스킬 분해"
	title.add_theme_font_size_override("font_size", 22); title.add_theme_color_override("font_color", Color(0.8, 0.9, 1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.size = Vector2(vis.x, 30); title.position = Vector2(0, 24)
	layer.add_child(title)
	var hint := Label.new(); hint.text = "분해기를 눌러 스킬 스크롤을 재료로 분해하세요"
	hint.add_theme_font_size_override("font_size", 16); hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hint.size = Vector2(vis.x, 22); hint.position = Vector2(0, vis.y - 44)
	layer.add_child(hint)
	var back := _atlas_sprite("common_ui", "common_back_btn", _load_manifest("common_ui"), 0.8)
	var bb := Button.new(); bb.flat = true; bb.size = Vector2(64, 48); bb.position = Vector2(12, 12)
	bb.pressed.connect(func(): if is_instance_valid(layer): layer.queue_free()); layer.add_child(bb)
	if back: back.position = Vector2(40, 34); layer.add_child(back)

## 원작 BreakDownSkillPopupBox(별도 엔티티) 최소 스텁: 스킬 분해 안내 팝업. ⚠️ 분해 결과(재료 환원표)=서버 유실(원칙2) →
## 지어내지 않고 안내만 표시. 결과표 복원 시 data/skill_breakdown.json + docs/input/review 사용자 시트로 외부화 예정.
func _open_lab_breakdown() -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 62; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.6); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: layer.queue_free()); layer.add_child(dim)
	const BW := 440.0
	const BH := 200.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2((vis.x - BW) * 0.5, (vis.y - BH) * 0.5); layer.add_child(win)
	var ml := Label.new()
	ml.text = "스킬 분해\n\n분해 결과(스킬→재료 환원표)는 원작 서버데이터라\n유실되었습니다. 복원 전까지 미구현(TODO)."
	ml.add_theme_font_size_override("font_size", 18); ml.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ml.position = Vector2(30, 40); ml.size = Vector2(BW - 60, BH - 90); win.add_child(ml)
	var ok := Button.new(); ok.text = "확인"; ok.size = Vector2(150, 44); ok.position = Vector2((BW - 150) * 0.5, BH - 58)
	ok.pressed.connect(func(): layer.queue_free()); win.add_child(ok)

## 원작 LabMakeSkillPop 1:1: 연구소 스킬 제작 — popup4 + pop_title_bg + backlight3 + coin/diamond + 제작(onClickOk)/취소.
## 근거: LabMakeSkillPop.c drawBase(9patch/popup4·pop_title_bg + common/backlight3 + coin_small1/diamond_small1) + onClick/
## setOnClickOk/onClickClose. ⚠️제작비용·결과 스킬확률=서버유실→오프라인(랜덤 skills.json, 골드 고정 ASSUMPTION).
const LAB_SKILL_COST := 3000
func _open_lab_make_skill() -> void:
	var vis := _vis()
	var man := _load_manifest("common_ui")
	var layer := CanvasLayer.new(); layer.layer = 40; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.6); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	const BW := 440.0
	const BH := 300.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(280, 52); tbar.position = Vector2((BW - 280) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = "스킬 제작"
	tl.add_theme_font_size_override("font_size", 26); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 58, 14); xb.pressed.connect(func(): layer.queue_free()); win.add_child(xb)
	var bl := _atlas_sprite("common_ui", "common_backlight3", man, 0.7)
	if bl: bl.position = Vector2(BW * 0.5, 130); bl.modulate = Color(1, 1, 1, 0.3); win.add_child(bl)
	var ml := Label.new(); ml.text = "연구소에서 무작위 스킬 스크롤을 제작합니다."
	ml.add_theme_font_size_override("font_size", 19); ml.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; ml.position = Vector2(40, 96); ml.size = Vector2(BW - 80, 60); win.add_child(ml)
	var mk := Button.new(); mk.size = Vector2(180, 52); mk.position = Vector2((BW - 180) * 0.5, BH - 82); win.add_child(mk)
	var mc := _atlas_sprite("common_ui", "common_coin_small1", man, 0.9)
	if mc: mc.position = Vector2(BW * 0.5 - 60, BH - 56); win.add_child(mc)
	var mgl := Label.new(); mgl.text = "제작  %d" % LAB_SKILL_COST; mgl.add_theme_font_size_override("font_size", 20)
	mgl.add_theme_color_override("font_color", Color.WHITE); mgl.position = Vector2(BW * 0.5 - 34, BH - 68); mgl.size = Vector2(140, 28); win.add_child(mgl)
	mk.pressed.connect(func():
		if not UserDB.spend("gold", LAB_SKILL_COST):
			return
		var names: Array = []
		for sv in Data.skills.values():
			if sv is Dictionary and sv.has("name"): names.append(String(sv["name"]))
		var made := "무작위 스킬"
		if not names.is_empty():
			var r := RandomNumberGenerator.new(); r.randomize()
			made = String(names[r.randi() % names.size()])
		var got: Array = UserDB.get_pmeta("made_skills", [])
		got.append(made); UserDB.set_pmeta("made_skills", got)
		layer.queue_free()
		_open_lab_result(made))

func _open_lab_result(skill_name: String) -> void:
	Bgm.sfx("effect_equip_success")
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 42; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	const BW := 420.0
	const BH := 240.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(260, 50); tbar.position = Vector2((BW - 260) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = "제작 완료"; tl.add_theme_font_size_override("font_size", 24)
	tl.add_theme_color_override("font_color", Color.WHITE); tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; tl.size = tbar.size; tbar.add_child(tl)
	var ml := Label.new(); ml.text = "[%s] 스킬 스크롤을 제작했습니다!" % skill_name
	ml.add_theme_font_size_override("font_size", 20); ml.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ml.position = Vector2(30, 80); ml.size = Vector2(BW - 60, 70); win.add_child(ml)
	var ok := Button.new(); ok.text = "확인"; ok.size = Vector2(150, 44); ok.position = Vector2((BW - 150) * 0.5, BH - 58)
	ok.pressed.connect(func(): layer.queue_free()); win.add_child(ok)

# ---------- HUD(스크롤 무관 고정 — CanvasLayer) ----------
func _build_hud(area: Dictionary) -> void:
	var hud := CanvasLayer.new()
	hud.layer = 10
	add_child(hud)
	# 원작 마을 HUD = `TownMainMenuLayer`(`TownElpisScene::initWidget:510` 이 `setMenu` 호출).
	# 구성은 **프로필(0x2bd→StatusLayer) · 재화+충전(0x2bf/0x2be) · 닫기(700→popScene) ·
	# 마을퀘스트(0x2c0/0x2c1→TownWorldPopUp)** 넷뿐이고, 그중 프로필·재화는 `main_hud.gd` 가
	# 이미 같은 클래스에서 1:1 이식해 두었다 ⇒ `MainHud` 를 **town 모드**로 재사용한다.
	# 상세 = `docs/ref/porting/TownMainMenuLayer.md`.
	#
	# 🔴 종전의 자작 3버튼(`← 둥지`·`월드맵`·`퀘스트`)과 `_build_menu_bar` 는 폐기했다(2026-07-31):
	#   · `← 둥지` = 원작 HUD 에 없다. 마을→동굴은 **둥지 표지판(tag 0x208)** 이 담당하고 우리도 있다.
	#   · `월드맵` = 경로는 원작에 있으나 형태가 우상단 `common/close_btn`(tag 700) 이다.
	#   · `퀘스트` = 원작은 `icon_townquest_scroll`(tag 0x2c1) 아이콘 + 진행도 라벨이다.
	_refresh_hud()
	# 🔴 종전의 자작 HUD "밤/낮" 버튼은 폐기했다(2026-07-29) — 원작에 그런 버튼은 없고,
	#    밤/낮 전환은 **엘피스 시계탑을 누르는 것**이다(원작 문자열 `NightTutorial_talk5`
	#    "저기 보이는 시계탑을 눌러봐!"). `objects` 의 `town_clockboard` 히트영역이 대신한다.
	var title := Label.new()
	title.text = String(area.get("title", ""))
	title.position = Vector2(22, FLOOR - 40.0)
	title.add_theme_font_size_override("font_size", 22)
	hud.add_child(title)
	_build_tips(hud)   # 원작 TownTipLayer: 하단 팁 말풍선(순환)

## 원작 TownTipLayer: 마을 하단에 도움말 팁이 말풍선으로 순환 표시(NPC 팁).
const _TIPS := [
	"드래곤은 '출전' 버튼으로 3마리까지 편성할 수 있어요.",
	"속성 상성을 이용하면 전투가 훨씬 쉬워져요. (강함 ×1.25)",
	"둥지에서 먹이를 주면 경험치와 애정이 올라요.",
	"잠재능력은 재설정으로 더 높은 등급을 노릴 수 있어요.",
	"연승할수록 던전 보상이 늘어나요!",
	"각성한 드래곤은 레벨 상한이 50까지 올라가요.",
	"젬과 장신구로 드래곤을 더 강하게 만들 수 있어요.",
]
var _tip_label: Label
var _tip_idx := 0
func _build_tips(hud: CanvasLayer) -> void:
	var vis := _vis()
	# 원작 TownTipLayer: 하단 팁 말풍선 = 9patch/dialogue_box2 프레임. 근거: TownTipLayer.c createWithSpriteFrameName('9patch/dialogue_box2.png').
	var bubble := NinePatchRect.new()
	bubble.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box2.tres")
	bubble.patch_margin_left = 14; bubble.patch_margin_top = 14; bubble.patch_margin_right = 14; bubble.patch_margin_bottom = 14
	bubble.size = Vector2(560, 44); bubble.position = Vector2(vis.x * 0.5 - 280, FLOOR - 54)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bubble)
	var icon := Label.new(); icon.text = "TIP"; icon.add_theme_font_size_override("font_size", 16)
	icon.add_theme_color_override("font_color", Color(1, 0.85, 0.4)); icon.position = Vector2(14, 10); bubble.add_child(icon)
	_tip_label = Label.new()
	_tip_label.add_theme_font_size_override("font_size", 15); _tip_label.add_theme_color_override("font_color", Color(1, 0.97, 0.85))
	_tip_label.position = Vector2(56, 10); _tip_label.size = Vector2(494, 22); bubble.add_child(_tip_label)
	_tip_idx = randi() % _TIPS.size()
	_show_tip()
	var timer := Timer.new(); timer.wait_time = 5.0; timer.autostart = true
	timer.timeout.connect(func(): _tip_idx = (_tip_idx + 1) % _TIPS.size(); _show_tip())
	bubble.add_child(timer)

func _show_tip() -> void:
	if not is_instance_valid(_tip_label): return
	_tip_label.text = _TIPS[_tip_idx]
	_tip_label.modulate.a = 0.0
	_tip_label.create_tween().tween_property(_tip_label, "modulate:a", 1.0, 0.4)

## 마을 일일 퀘스트(원작 TownQuestLayer): 전투 승리/부화 진행도 + 보상. 카운터=UserDB 일일리셋.
const _QUESTS := [
	{"key": "battles", "label": "전투 승리", "goal": 3, "gold": 300},
	{"key": "hatches", "label": "부화하기", "goal": 1, "gold": 200},
]
func _open_quests() -> void:
	var overlay := CanvasLayer.new(); overlay.layer = 30; add_child(overlay)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: overlay.queue_free())
	overlay.add_child(dim)
	var vis := _vis()
	# 원작 QuestPopup(TownQuestLayer가 위임) 1:1: popup4 + pop_title_bg + icon_quest{1-5} 퀘스트아이콘 + close_btn.
	# 근거: QuestPopup.c setContentSprite + scene/adventure/icon_quest1~5.png. TownQuestLayer.c initWidget=TownQuestPopUp::create 위임.
	var BW := 520.0; var BH := 320.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round(vis.x * 0.5 - BW * 0.5), round(vis.y * 0.5 - BH * 0.5))
	overlay.add_child(win)
	var tbar := NinePatchRect.new(); tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(BW * 0.9, 52); tbar.position = Vector2((BW - BW * 0.9) * 0.5, 12); win.add_child(tbar)
	var t := Label.new(); t.text = "마을 퀘스트 (일일)"
	t.add_theme_font_size_override("font_size", 22); t.add_theme_color_override("font_color", Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size = tbar.size; tbar.add_child(t)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 50 - 16, 14); xb.pressed.connect(func(): overlay.queue_free()); win.add_child(xb)
	# 원작 TownQuestPopUp::initRaonHelp: 라온 마스코트가 팝업 옆에서 퀘스트 안내(sd_raon "quest_start").
	if ResourceLoader.exists("res://scenes/fx/sd_raon.tscn"):
		var rh := Node2D.new(); rh.position = Vector2(-46, BH - 40); rh.scale = Vector2(0.6, 0.6); win.add_child(rh)
		var ri = load("res://scenes/fx/sd_raon.tscn").instantiate(); rh.add_child(ri)
		var rap: AnimationPlayer = ri.get_node_or_null("AnimationPlayer")
		if rap and rap.has_animation("quest_start"):
			rap.get_animation("quest_start").loop_mode = Animation.LOOP_LINEAR; rap.play("quest_start")
		elif rap and rap.has_animation("wait"):
			rap.play("wait")
	for i in _QUESTS.size():
		var qd: Dictionary = _QUESTS[i]
		var cnt := mini(UserDB.quest_count(String(qd["key"])), int(qd["goal"]))
		var done := cnt >= int(qd["goal"])
		var claimed := UserDB.quest_claimed(String(qd["key"]))
		var y := 80 + i * 82
		# 원작 퀘스트 아이콘(icon_quest1~5)
		var qic := load("res://assets/converted/adventure_ui/scene_adventure_icon_quest%d.tres" % (i + 1))
		if qic:
			var qi := TextureRect.new(); qi.texture = qic; qi.position = Vector2(24, y - 4); qi.size = Vector2(48, 48)
			qi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; win.add_child(qi)
		var nm := Label.new(); nm.text = "%s  %d/%d" % [qd["label"], cnt, qd["goal"]]
		nm.add_theme_font_size_override("font_size", 20); nm.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
		nm.position = Vector2(84, y); win.add_child(nm)
		var rw := Label.new(); rw.text = "보상: %d G" % qd["gold"]
		rw.add_theme_font_size_override("font_size", 14); rw.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6))
		rw.position = Vector2(84, y + 28); win.add_child(rw)
		var cb := Button.new(); cb.size = Vector2(120, 42); cb.position = Vector2(win.size.x - 148, y + 2)
		cb.text = "수령 완료" if claimed else ("보상 받기" if done else "진행 중")
		cb.disabled = claimed or not done
		var qk: String = qd["key"]; var qg: int = int(qd["gold"])
		# 보상 수령 → NPC 퀘스트 마크 + HUD(진행도 `%d/%d`·알림 뱃지·골드)를 함께 갱신.
		cb.pressed.connect(func(): UserDB.claim_quest(qk); UserDB.add_currency("gold", qg); overlay.queue_free(); _refresh_quest_marks(); _refresh_hud(); _open_town_reward(qg))
		win.add_child(cb)
	# 지역 진행도(원작 TownWorldPopUp) 진입.
	var prog := Button.new(); prog.text = "지역 진행도"; prog.size = Vector2(140, 40)
	prog.position = Vector2(win.size.x * 0.5 - 160, win.size.y - 50)
	prog.pressed.connect(func(): overlay.queue_free(); _open_region_progress()); win.add_child(prog)
	var close := Button.new(); close.text = "닫기"; close.size = Vector2(100, 40)
	close.position = Vector2(win.size.x * 0.5 + 20, win.size.y - 50)
	close.pressed.connect(func(): overlay.queue_free()); win.add_child(close)

## 원작 TownRewardPopUp 1:1(initValue_town): 보상 획득 팝업 — popup4 + pop_title_bg + backlight3(광배)
## + yongsin_ball spine(용신 볼 축하연출) + coin 보상. 근거: TownRewardPopUp.c(9patch/popup4·pop_title_bg,
## common/backlight3·coin·diamond, scene/worldmap/event_dragonball/yongsin_ball.spine_json setAnimation "animation").
## ⚠️보상수치=우리 오프라인 일일퀘스트(원작 이벤트 보상=서버유실), 내부좌표=obfuscated→중앙 배치(computed).
func _open_town_reward(gold: int) -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 40; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	const BW := 460.0
	const BH := 380.0
	var cx := vis.x * 0.5
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round(cx - BW * 0.5), round(vis.y * 0.5 - BH * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(300, 52); tbar.position = Vector2((BW - 300) * 0.5, 12); win.add_child(tbar)
	var title := Label.new(); title.text = "보상 획득"
	title.add_theme_font_size_override("font_size", 28); title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size = tbar.size; tbar.add_child(title)
	# backlight3 광배 + yongsin_ball spine(용신 볼) — 팝업 중앙.
	var center := Vector2(BW * 0.5, 168.0)
	var cm := _load_manifest("common_ui")
	var bl := _atlas_sprite("common_ui", "common_backlight3", cm, 0.85)
	if bl: bl.position = center; bl.modulate = Color(1, 1, 1, 0.28); win.add_child(bl)   # 은은한 광배(스파인 안 덮게)
	if ResourceLoader.exists("res://scenes/fx/yongsin_ball.tscn"):
		var holder := Node2D.new(); holder.position = center; holder.scale = Vector2(0.5, 0.5); win.add_child(holder)
		var inst = load("res://scenes/fx/yongsin_ball.tscn").instantiate(); holder.add_child(inst)
		var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		if ap and ap.has_animation("animation"):
			ap.get_animation("animation").loop_mode = Animation.LOOP_LINEAR
			ap.play("animation")
	# 보상: coin + 골드량.
	var coin := _atlas_sprite("common_ui", "common_coin_small1", cm, 1.1)
	if coin: coin.position = Vector2(BW * 0.5 - 44, 262); win.add_child(coin)
	var amt := Label.new(); amt.text = "%d G" % gold
	amt.add_theme_font_size_override("font_size", 26); amt.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	amt.position = Vector2(BW * 0.5 - 24, 248); amt.size = Vector2(120, 32); win.add_child(amt)
	var ok := Button.new(); ok.text = "확인"; ok.size = Vector2(160, 44); ok.position = Vector2((BW - 160) * 0.5, BH - 62)
	ok.pressed.connect(func():
		if is_instance_valid(layer): layer.queue_free()
		_open_quests())
	win.add_child(ok)

## 원작 TownWorldPopUp 1:1: 지역 진행도 팝업 — popup4 + pop_title_bg + common/gauge(클리어 진행)
## + clear_mark + icon_questgold/questbox(마일스톤 보상) + sd_raon spine(라온 마스코트). 근거: TownWorldPopUp.c
## init(setContentSprite 9patch/popup4,Rect130,190,40,58)+initWidget(gauge/gauge_bg·clear_mark·icon_quest*·sd_raon.spine_json).
## ⚠️마일스톤 보상수치=서버 유실→오프라인 큐레이션(ASSUMPTION), 내부좌표 obfuscated→중앙 배치(computed).
func _open_region_progress() -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 40; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	const BW := 520.0
	const BH := 380.0
	var cm := _load_manifest("common_ui")
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round(vis.x * 0.5 - BW * 0.5), round(vis.y * 0.5 - BH * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(320, 52); tbar.position = Vector2((BW - 320) * 0.5, 12); win.add_child(tbar)
	var title := Label.new(); title.text = "지역 진행도"
	title.add_theme_font_size_override("font_size", 28); title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size = tbar.size; tbar.add_child(title)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 58, 14); xb.pressed.connect(func(): if is_instance_valid(layer): layer.queue_free()); win.add_child(xb)
	# 라온 마스코트 spine(sd_raon, "happy"). 좌측.
	if ResourceLoader.exists("res://scenes/fx/sd_raon.tscn"):
		var holder := Node2D.new(); holder.position = Vector2(120, 210); holder.scale = Vector2(0.7, 0.7); win.add_child(holder)
		var inst = load("res://scenes/fx/sd_raon.tscn").instantiate(); holder.add_child(inst)
		var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		if ap and ap.has_animation("happy"):
			ap.get_animation("happy").loop_mode = Animation.LOOP_LINEAR; ap.play("happy")
		elif ap and ap.has_animation("wait"):
			ap.play("wait")
	# 진행도: 클리어한 던전 수 / 총 스테이지(UserDB progress "cleared_<id>").
	var sd: Dictionary = Data.stages.get("stages", {})
	var total: int = maxi(1, sd.size())
	var cleared := 0
	for sid in sd.keys():
		if bool(UserDB.get_progress("cleared_" + str(sid), false)):
			cleared += 1
	var ratio := clampf(float(cleared) / float(total), 0.0, 1.0)
	# gauge_bg + gauge(fill scale.x=ratio). 우측 상단.
	var gx := 230.0; var gy := 150.0
	var gbg := _atlas_sprite("common_ui", "common_gauge_bg", cm, 1.0)
	if gbg: gbg.position = Vector2(gx + 120, gy); gbg.centered = false; gbg.position = Vector2(gx, gy - 12); win.add_child(gbg)
	var gfill := _atlas_sprite("common_ui", "common_gauge", cm, 1.0)
	if gfill: gfill.centered = false; gfill.position = Vector2(gx, gy - 12); gfill.scale = Vector2(ratio, 1.0); win.add_child(gfill)
	var glab := Label.new(); glab.text = "%d / %d 클리어" % [cleared, total]
	glab.add_theme_font_size_override("font_size", 20); glab.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	glab.position = Vector2(gx, gy + 14); glab.size = Vector2(240, 26); win.add_child(glab)
	# 마일스톤 보상(원작 icon_questgold/questbox + clear_mark). 3단계(오프라인 큐레이션).
	var mile := [{"n": total / 3, "icon": "common_icon_questgold"}, {"n": total * 2 / 3, "icon": "common_icon_questbox"}, {"n": total, "icon": "common_icon_questgold"}]
	for i in mile.size():
		var m: Dictionary = mile[i]
		var mx := 240.0 + i * 90.0
		var ic := _atlas_sprite("common_ui", String(m["icon"]), cm, 0.9)
		if ic: ic.position = Vector2(mx, 250); win.add_child(ic)
		if cleared >= int(m["n"]):
			var cmk := _atlas_sprite("common_ui", "common_clear_mark_kr", cm, 0.7)
			if cmk: cmk.position = Vector2(mx, 250); win.add_child(cmk)
		var ml := Label.new(); ml.text = "%d" % int(m["n"])
		ml.add_theme_font_size_override("font_size", 15); ml.add_theme_color_override("font_color", Color(0.35, 0.24, 0.06))
		ml.position = Vector2(mx - 12, 286); ml.size = Vector2(40, 20); ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		win.add_child(ml)
	var ok := Button.new(); ok.text = "확인"; ok.size = Vector2(160, 44); ok.position = Vector2((BW - 160) * 0.5, BH - 60)
	ok.pressed.connect(func(): if is_instance_valid(layer): layer.queue_free()); win.add_child(ok)

## 밤 여부. **유타칸 월드맵과 같은 값**을 본다 — 원작은 마을·월드맵이 모두
## `GameManager::getDBYutakanNight()` 하나를 읽는다(TownObjectManager.c:738·973·1565·1626·1968
## / WorldMapYutakanLayer::changeNightAndDay). 그 DB 값은 서버 소유라 유실 → `UserDB` pmeta 로 대체.
## `params.night` 는 스크린샷 도구용 override.
func _resolve_night(params: Dictionary) -> bool:
	if params.has("night"):
		return bool(params.get("night"))
	return bool(UserDB.get_pmeta("yutakan_night", false))

## 원작 `TownObjectManager::onClickChangeDayAndNight` (@01a84628):
## `getDBYutakanNight()` 를 뒤집어 `setDBYutakanNight` 로 되쓴다 ⇒ 유타칸 월드맵도 함께 바뀐다.
## 짧은 안내 문구(원작 시계탑 전환 후 `ElpisTownDayAndNight3/4`). cave.gd 와 같은 형태.
var _toast_lbl: Label   # ⚪ 미사용(호환용) — 실제 표시는 Toast 헬퍼가 한다.

## 짧은 안내 문구 — 원작 `GameManager::showToast` @014c193c. 레시피는 `scripts/ui/toast.gd`.
## (2026-07-29 이전엔 배경 없는 노란 라벨을 자작해 쓰고 있었다 — 원작은 반투명 검정 상자 +
##  `font_common` BMFont 흰 글씨다. 전역 함수 하나가 소유하는 물건이라 공용 헬퍼로 모았다.)
func _toast(text: String) -> void:
	Toast.show(self, text)

## 엘피스 시계탑 확인창 — 원작 `TownObjectManager` 이 히트영역(tag 0x10) 클릭 시
## `PopupTypeLayer`(확인/취소)를 띄우고, 확인 리스너가 `onClickChangeDayAndNight` 다.
## 문구는 원작 문자열 그대로(stringsData_KR.xml):
##   `ElpisTownDayAndNight_Title` "엘피스 시계탑"
##   `ElpisTownDayAndNight1/2`    "현재 유타칸은 (낮/밤)입니다. … (밤/낮)으로 바꾸시겠습니까?"
##   `ElpisTownDayAndNight3/4`    "유타칸 대륙이 어두워졌습니다./밝아졌습니다."
## 강조색 `{#4641D9:…}` 도 원작 값.
##
## ⚪ 원작은 시나리오 진행도 47화 이상일 때만 반응한다(`ScenarioManager` +0x168 < 0x2f 이면 무시).
##    우리는 시나리오 진행도를 아직 추적하지 않아 게이트를 걸지 않았다.
const _CLOCK_HL := Color8(0x46, 0x41, 0xD9)

func _open_daynight_confirm() -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 40; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	const BW := 480.0
	const BH := 300.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round(vis.x * 0.5 - BW * 0.5), round(vis.y * 0.5 - BH * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(300, 52); tbar.position = Vector2((BW - 300) * 0.5, 12); win.add_child(tbar)
	var title := Label.new(); title.text = "엘피스 시계탑"
	title.add_theme_font_size_override("font_size", 26); title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size = tbar.size; tbar.add_child(title)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 58, 14)
	xb.pressed.connect(func(): if is_instance_valid(layer): layer.queue_free()); win.add_child(xb)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	var cur := "밤" if _night else "낮"
	var nxt := "낮" if _night else "밤"
	body.text = ("[center]현재 유타칸은 [color=#%s]%s[/color]입니다.

"
		+ "[color=#%s]%s[/color]으로 바꾸시겠습니까?[/center]") % [
		_CLOCK_HL.to_html(false), cur, _CLOCK_HL.to_html(false), nxt]
	body.add_theme_font_size_override("normal_font_size", 21)
	body.add_theme_color_override("default_color", Color(0.28, 0.19, 0.05))
	body.fit_content = true; body.scroll_active = false
	body.position = Vector2(40, 92); body.size = Vector2(BW - 80, 110)
	win.add_child(body)
	var ok := Button.new(); ok.text = "확인"; ok.size = Vector2(150, 46)
	ok.position = Vector2(BW * 0.5 - 160, BH - 66)
	# 확인 → 토글(=마을 재구성) 후에 안내 문구. `_rebuild` 가 자식을 전부 지우므로 순서가 중요하다.
	ok.pressed.connect(func():
		if is_instance_valid(layer): layer.queue_free()
		_toggle_night()
		_toast("유타칸 대륙이 " + ("어두워졌습니다." if _night else "밝아졌습니다.")))
	win.add_child(ok)
	var no := Button.new(); no.text = "취소"; no.size = Vector2(150, 46)
	no.position = Vector2(BW * 0.5 + 10, BH - 66)
	no.pressed.connect(func(): if is_instance_valid(layer): layer.queue_free())
	win.add_child(no)

func _toggle_night() -> void:
	_night = not _night
	UserDB.set_pmeta("yutakan_night", _night)
	_rebuild()

func _on_worldmap() -> void:
	if Scenes.REGISTRY.has("worldmap"):
		Scenes.goto("worldmap")
	else:
		push_warning("[Town] worldmap 미구현 — Phase 2에서 연결")

# ---------- helpers (cave.gd와 동일 규약) ----------
func _vis() -> Vector2:
	return get_viewport_rect().size

func _load_manifest(dir: String) -> Dictionary:
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func _atlas_tex(dir: String, name: String) -> Texture2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	return load(p) if ResourceLoader.exists(p) else null

func _atlas_sprite(dir: String, name: String, man: Dictionary, scale := 1.0) -> Sprite2D:
	var s := Sprite2D.new()
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if ResourceLoader.exists(p):
		s.texture = load(p)
	s.material = _pma
	# 회전 보정 불필요 — 변환 단계가 흡수(scripts/tools/fix_rotated_frames.py)
	s.scale = Vector2(scale, scale)
	return s
