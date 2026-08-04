extends Control
## WorldMap(월드맵) 씬 — 지역 개요 ↔ 지역 노드 목록. render 층. (CLAUDE.md §10)
## 구조: map_world(지역 섬 썸네일+이름배너) 개요 → 지역맵(map_<region> 필드노드) → Scenes.goto.
## 데이터: data/worldmap.json (Data.worldmap_regions()). 배치·연결은 자작(ASSUMPTION) — 서버데이터 유실.
## 좌표: 692 고정높이(design.gd). 세로 드래그 스크롤. 전환은 Scenes.goto()만(§10.4).
##
## ⚠️ libgame.so 추출 결과 월드맵 UI는 대부분 온라인/이벤트 크롬(2020이벤트·기념일 등 = 컷 대상)이라
##    충실 이식 실익 낮음. 핵심(지역·노드 배치)은 유실 서버데이터 → 자작. [[dv2-render-recipes]]

const FLOOR := 692.0   # = Design.DESIGN_HEIGHT

## 원작 `WorldMapLabel::GetColor(WorldMapColor)` 팔레트 — 필드 네임택 판 색.
##
## 🔴 2026-07-29 정정 — 종전 값은 **전부 틀렸다**. Ghidra 가 붙인 `DAT_022bf070` 을 그대로 읽었는데
##    그 파일의 이미지베이스가 **0x100000 밀려** 있어 실제로는 `.eh_frame_hdr`(예외처리 메타)를
##    바이트로 긁고 있었다. `libgame.so` 를 직접 디스어셈해 확정:
##      `GetColor`(dynsym `_ZN7cocos2d13WorldMapLabel8GetColorENS_13WorldMapColorE` @0x19d27fc)
##      → `adrp x8,#0x21bf000` + `#0x70/#0xa0/#0xd0`, stride 8, 6엔트리.
##      팩값 = `B<<16 | G<<8 | R` (ccColor3B{r,g,b} 를 레지스터로 넘기는 리틀엔디안 배치 —
##      else 분기의 `ldrb [x8],[x8,#1],[x8,#2]` + shift 로 확인).
##    검증: 6개 전부 `docs/ref/orig_image/old_screenshots/main.png` 의 판 색 실측과 일치
##    (예 enum2 #2A98D5 ↔ 원혼의 폭포 실측 (35,138,203)).
## 인덱스 = `GetColor(enum) - 1` (`uVar2 = param_1 - 1`), 범위 밖은 WHITE.
const WORLDMAP_LABEL_COLORS := [
	Color8(116, 206, 44),   # enum1 #74CE2C (연두)   — 희망의 숲 · 바람의 신전 · 엘피스
	Color8(42, 152, 213),   # enum2 #2A98D5 (파랑)   — 칼바람의 산맥 · 원혼의 폭포 · 오색호수 …
	Color8(255, 198, 60),   # enum3 #FFC63C (노랑)   — 하늘의 신전
	Color8(165, 0, 85),     # enum4 #A50055 (자주)   — 해골 요새 · 혼돈의 틈새(특수 지역)
	Color8(86, 66, 61),     # enum5 #56423D (갈색)   — 수목신의 묘지 · 콜로세움
	Color8(112, 69, 161),   # enum6 #7045A1 (보라)   — 수중동굴 · 몽환의 수정터
]

## 원작 `WorldMapLabel::GetColor`: enum 1~6은 팔레트, 그 외는 WHITE.
func worldmap_label_color(index: int) -> Color:
	if index >= 1 and index <= WORLDMAP_LABEL_COLORS.size():
		return WORLDMAP_LABEL_COLORS[index - 1]
	return Color.WHITE

var _pma: CanvasItemMaterial
var _manifest: Dictionary = {}
var _mode := "overview"          # "overview" 또는 지역 id
var _params: Dictionary = {}     # 진입 params(밤 플래그 등)
var _content: Node2D
var _scroll := 0.0
var _horizontal := false          # 지역맵=가로 스크롤, 개요/리스트=세로
var _max_scroll := 0.0
var _dragging := false
var _scroll_vel := 0.0            # 원작 deaccelerateScrolling: 플릭 후 관성 스크롤 속도
var _press_pos := Vector2.ZERO
var _moved := false
var _busy := false               # 클로즈업 전환 중 입력 차단
var _hits: Array = []            # [{rect(content좌표), kind, arg, [center]}]
var _clouds: Array = []          # 원작 showCloud: [{node, speed, w}] 하늘 흐르는 구름

func enter(params: Dictionary = {}) -> void:
	_params = params
	_mode = params.get("region", "overview")
	if _pma != null:
		_rebuild()

## 지역 BGM 조회(data/worldmap.json). overview/미지정은 yutakan 기본.
func _region_bgm(region_id: String) -> String:
	# 카데스의 공간이 켜진 유타칸은 **전용 곡**이다 — 원작 확정:
	#   `WorldMapScene::setBackground`(decomp :17170)
	#     `if (GameManager::getDBYutakanKades() == 1) "music/utakan_worldmap_bgm.mp3"`
	#     `else "music/bg_yutakan.mp3"`
	#   (위키 dungeon_1.pdf §2 의 "브금이 무섭게 바뀌고" 가 이것이다.)
	if region_id == "yutakan" and _is_kades_space(_region("yutakan").get("native", {})):
		var kb := String(Data.kades.get("bgm_worldmap", ""))
		if kb != "":
			return kb
	if region_id != "" and region_id != "overview":
		for r in Data.worldmap_regions():
			if String(r.get("id", "")) == region_id:
				var b := String(r.get("bgm", ""))
				if b != "": return b
	return "bg_yutakan"

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_manifest = _load_manifest("worldmap_maps")
	_rebuild()
	_launch_scenario_if_available()

## 시나리오 자동 발동 — 원작 `WorldMapScene.c:21999` 가 메인 화면에서
## `ScenarioManager::launchScenarioIfAvailable()` 를 부르고, 참이면 그 회차를 바로 재생한다.
## 게이트(원작 `launchScenarioIfAvailable` @014db794):
##   · sn > 0 이면 **선택 드래곤이 있고 그 레벨 > 0** 이어야 한다
##   · 회차 자체의 해금(레벨·서브퀘스트)은 `StoryProgress.unlocked` 가 본다
##   · 이미 본 회차는 다시 열리지 않는다(원작은 sn 이 진행돼 있어 같은 효과)
## ⚠️ 우리 흐름 데이터(`data/scenario_flow.json`)가 있는 회차만 자동 재생한다 —
##    흐름이 없으면 화자·배경 없이 텍스트만 나와서 자동으로 띄울 물건이 못 된다.
func _launch_scenario_if_available() -> void:
	if _mode != "overview" and _mode != "":
		return                                   # 지역 안에서는 안 띄운다(원작도 메인 화면)
	var dr := UserDB.active_dragon()
	if dr.is_empty() or int(dr.get("level", 0)) <= 0:
		return
	var ep := StoryProgress.next_episode()
	if ep <= 0 or StoryProgress.seen(ep) or not StoryProgress.unlocked(ep):
		return
	# 정확한 던전 필드가 있는 회차는 원작 ! 마커를 눌러 진입한다.
	# 즉시/마을/특수 회차는 복구된 표에 던전 필드가 없으므로
	# launchScenarioIfAvailable 경로를 유지한다.
	var mark := StoryProgress.mark_field()
	if mark > 0 and mark < 999:
		return
	if Data.scenario_flow_of(ep).is_empty():
		return
	Scenes.goto("story", {"no": ep, "part": 0, "back": "worldmap",
		"back_params": {"region": _mode}})

func _rebuild() -> void:
	# 원작 worldmap BGM = 지역별(data/worldmap.json bgm). yutakan=bg_yutakan / elf=bg_elysium / dwarf=bg_metal_tower.
	# (bg_worldraid는 월드레이드 전용 — 오배정 금지.)
	Bgm.play(_region_bgm(_mode))
	# 구역 앰비언트(원작 setWorldMapSound)는 지역맵을 지을 때 등록한다(`_build_region_native`).
	# 개요/리스트 화면에는 구역이 없으므로 여기서 비운다. Scenes.goto 도 매 전환마다 지운다.
	Bgm.area_clear()
	for c in get_children():
		c.queue_free()
	_hits.clear()
	_clouds.clear()   # 이전 구름(자식과 함께 free됨) 참조 정리
	# 배경(양피지 톤). 원작 map_world는 아틀라스라 전체 배경 프레임이 없음 → 단색 톤. ASSUMPTION
	var bg := ColorRect.new()
	bg.color = Color(1, 0, 1) if Engine.has_meta("wm_no_ocean") else Color(0.86, 0.78, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 🔴 이 판은 **가장 뒤**여야 한다. 바다·하늘 층이 `_backdrop`(음수 z)로 내려간 뒤로는
	#    z_index 0 인 이 판이 그 위를 덮어 바다가 통째로 사라졌다(2026-07-29).
	bg.z_index = _BACKDROP_Z - 100
	add_child(bg)

	_content = Node2D.new()
	add_child(_content)
	_horizontal = false
	_busy = false
	if _mode == "overview":
		_build_overview()
	else:
		_build_region(_mode)
	_scroll = 0.0
	_apply_scroll()
	_build_hud()
	# 임프상인 스파인은 **지도 빌드가 끝난 뒤** 붙인다.
	# 🔴 종전엔 `_apply_yutakan_night` 안에서 붙였는데, 그 시점의 `_content` 는 곧 교체되는
	#   임시 노드라 스파인이 **트리에서 떨어져 나가** 화면에 안 나왔다(2026-07-31 실측:
	#   parent 가 익명 `@Node2D@…`, global 이 로컬과 같음 = 부모가 이미 분리된 상태).
	if _imp_pending:
		_imp_pending = false
		_add_imp_shop()
	# 원작 WorldMapDailyReward: 메인 화면 첫 진입 시 하루 1회. 메인 화면이 유타칸 지역뷰로
	# 바뀌었으므로(main.gd) overview 한정이던 조건을 풀었다 — 하루 1회 가드가 중복을 막는다.
	_maybe_daily_reward()

## 원작 GuideLayer 1:1: 게임 가이드 — popup4 + 좌 주제메뉴(initScorllMenu) + 우 이미지페이지(guide_C_T_P_KR.jpg)
## + prev/next(onClickArrow). 근거: GuideLayer.c initWidget(popup4+text_box+close_btn+btn_next/prev+guide_%d_%d_%d_%s.jpg)
## +initScorllMenu(주제)+onClickMenu/onClickArrow. ⚠️btn_guide/arrow 프레임=worldmap/guide 미변환→텍스트버튼 대체.
var _guide_topic := 0
var _guide_page := 0
func _guide_map() -> Array:
	# guide_ui의 guide_C_T_P_KR.jpg → (C,T)별 그룹, 페이지 정렬. [{key:"C_T", pages:[fname...]}]
	var groups := {}
	var d := DirAccess.open("res://assets/converted/guide_ui")
	if d:
		for f in d.get_files():
			if f.begins_with("guide_") and f.ends_with("_KR.jpg"):
				var parts := f.replace("_KR.jpg", "").split("_")   # ["guide","C","T","P"]
				if parts.size() >= 4:
					var key := "%s_%s" % [parts[1], parts[2]]
					if not groups.has(key): groups[key] = []
					groups[key].append(f)
	var out: Array = []
	for k in groups.keys():
		var arr: Array = groups[k]; arr.sort()
		out.append({"key": k, "pages": arr})
	out.sort_custom(func(a, b): return String(a["key"]) < String(b["key"]))
	return out

func _open_guide() -> void:
	var vis := _vis()
	var topics := _guide_map()
	if topics.is_empty():
		return
	_guide_topic = clampi(_guide_topic, 0, topics.size() - 1)
	var layer := CanvasLayer.new(); layer.layer = 46; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.7); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var BW := clampf(vis.x - 80.0, 800.0, 1180.0)
	var BH := clampf(vis.y - 56.0, 540.0, 680.0)
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(320, 54); tbar.position = Vector2((BW - 320) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = "게임 가이드"
	tl.add_theme_font_size_override("font_size", 28); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 66, 14); xb.pressed.connect(func(): layer.queue_free()); win.add_child(xb)
	# 좌: 주제 메뉴(initScorllMenu).
	var menu := VBoxContainer.new(); menu.position = Vector2(30, 88); menu.add_theme_constant_override("separation", 6)
	win.add_child(menu)
	for i in topics.size():
		var tb := Button.new(); tb.text = "가이드 %s" % String(topics[i]["key"]).replace("_", "-")
		tb.size = Vector2(170, 40); tb.custom_minimum_size = Vector2(170, 40)
		tb.add_theme_font_size_override("font_size", 16)
		if i == _guide_topic: tb.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		var idx := i
		tb.pressed.connect(func(): _guide_topic = idx; _guide_page = 0; layer.queue_free(); _open_guide())
		menu.add_child(tb)
	# 우: 이미지 페이지 + prev/next.
	var pages: Array = topics[_guide_topic]["pages"]
	_guide_page = clampi(_guide_page, 0, pages.size() - 1)
	var p := "res://assets/converted/guide_ui/%s" % String(pages[_guide_page])
	if ResourceLoader.exists(p):
		var tr := TextureRect.new(); tr.texture = load(p)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.position = Vector2(220, 90); tr.size = Vector2(BW - 260, BH - 170)
		win.add_child(tr)
	var pg := Label.new(); pg.text = "%d / %d" % [_guide_page + 1, pages.size()]
	pg.add_theme_font_size_override("font_size", 18); pg.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	pg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; pg.position = Vector2(BW * 0.5, BH - 62); pg.size = Vector2(200, 26)
	win.add_child(pg)
	if _guide_page > 0:
		var pv := Button.new(); pv.text = "◀ 이전"; pv.size = Vector2(120, 42); pv.position = Vector2(240, BH - 66)
		pv.pressed.connect(func(): _guide_page -= 1; layer.queue_free(); _open_guide()); win.add_child(pv)
	if _guide_page < pages.size() - 1:
		var nx := Button.new(); nx.text = "다음 ▶"; nx.size = Vector2(120, 42); nx.position = Vector2(BW - 160, BH - 66)
		nx.pressed.connect(func(): _guide_page += 1; layer.queue_free(); _open_guide()); win.add_child(nx)

## 원작 WorldMapDailyReward: 월드맵(개요) 첫 진입 시 하루 1회 일일 보상. 근거: WorldMapDailyReward.c
## init/initWidget(9patch/popup4+pop_title_bg + common/backlight3 + coin_big/diamond_big + scene/worldmap/light
## + return_event_mark_%s + onClickConfirm). ⚠️보상수치·출석스케줄=서버유실→오프라인 고정(ASSUMPTION).
func _maybe_daily_reward() -> void:
	var today := Time.get_date_string_from_system()
	if String(UserDB.get_pmeta("daily_login", "")) == today:
		return
	UserDB.set_pmeta("daily_login", today)
	_open_daily_reward(500, 5)

func _open_daily_reward(gold: int, dia: int) -> void:
	var vis := _vis()
	var man := _load_manifest("common_ui")
	var wman := _load_manifest("worldmap_ui")
	var layer := CanvasLayer.new(); layer.layer = 45; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.6); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var BW := 460.0
	var BH := 400.0
	var cx := vis.x * 0.5
	var cyw := vis.y * 0.5
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round(cx - BW * 0.5), round(cyw - BH * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(320, 54); tbar.position = Vector2((BW - 320) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = "일일 보상"
	tl.add_theme_font_size_override("font_size", 28); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	# 광배(backlight3) + light 회전.
	var center := Vector2(BW * 0.5, 170.0)
	var bl := _sprite_native("common_backlight3", "common_ui", man, 1.1)
	if bl: bl.position = center; bl.modulate = Color(1, 1, 1, 0.45); win.add_child(bl)
	var lt := _sprite_native("scene_worldmap_light", "worldmap_ui", wman, 1.0)
	if lt:
		lt.position = center; win.add_child(lt)
		lt.create_tween().set_loops().tween_property(lt, "rotation", TAU, 8.0).as_relative()
	# 출석 마크(return_event_mark_kr).
	var mk := _sprite_native("scene_worldmap_return_event_mark_kr", "worldmap_ui", wman, 0.9)
	if mk: mk.position = center; win.add_child(mk)
	# 보상: coin_big + gold, diamond_big + dia.
	var coin := _sprite_native("common_coin_big", "common_ui", man, 0.7)
	if coin: coin.position = Vector2(BW * 0.5 - 70, 268); win.add_child(coin)
	var gl := Label.new(); gl.text = "%d" % gold
	gl.add_theme_font_size_override("font_size", 24); gl.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	gl.position = Vector2(BW * 0.5 - 40, 254); gl.size = Vector2(80, 30); win.add_child(gl)
	var dm := _sprite_native("common_diamond_big", "common_ui", man, 0.7)
	if dm: dm.position = Vector2(BW * 0.5 + 30, 268); win.add_child(dm)
	var dl := Label.new(); dl.text = "%d" % dia
	dl.add_theme_font_size_override("font_size", 24); dl.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	dl.position = Vector2(BW * 0.5 + 60, 254); dl.size = Vector2(60, 30); win.add_child(dl)
	# 확인(onClickConfirm) → 지급 + 닫기.
	var ok := Button.new(); ok.text = "받기"; ok.size = Vector2(160, 46); ok.position = Vector2((BW - 160) * 0.5, BH - 64)
	ok.pressed.connect(func():
		UserDB.add_currency("gold", gold); UserDB.add_currency("diamond", dia)
		if is_instance_valid(layer): layer.queue_free())
	win.add_child(ok)

# ---------- 개요: 양피지 월드맵 (원작 WorldMapFullLayer::initWidget 1:1) ----------
# 근거: WorldMapFullLayer.c:2394 initWidget — bg.jpg 양피지 + label_worldmap 타이틀 +
#   섬(map_*, z11+) + 이름배너(label_*_kr). 설계공간 1408×890(cocos y-up).
#   berna=아틀라스 부재→CUT. 원작은 우노를 label_question(잠금 물음표)로 가렸지만,
#   우리는 해금 트리거(스토리 '지도 복원')가 유실이라 상시 해금이다
#   (data/worldmap.json uno `_unlock_basis`, 사용자 확정 2026-07-28).
#   ⇒ 잠금 여부는 여기 하드코딩하지 말고 **데이터의 `unlocked`** 를 읽는다.
const _OV_W := 1408.0   # 원작 content 폭(setViewSize/최소 1408)
const _OV_H := 890.0    # 원작 content 높이
# 원작 좌표(cocos y-up). island_pos / banner_pos = initWidget WorldMapBG::create 인자.
const _OVERVIEW := [
	{"id": "elf", "island": "scene_worldmap_map_world_map_elf", "ic": [249, 297],
		"banner": "scene_worldmap_map_world_label_elf_kr", "bc": [360, 250]},
	{"id": "yutakan", "island": "scene_worldmap_map_world_map_yukatan", "ic": [458, 312],
		"banner": "scene_worldmap_map_world_label_yukatan_kr", "bc": [640, 280]},
	{"id": "dwarf", "island": "scene_worldmap_map_world_map_dwarf", "ic": [772, 258],
		"banner": "scene_worldmap_map_world_label_dwarf_kr", "bc": [880, 200]},
	{"id": "uno", "island": "scene_worldmap_map_world_map_uno", "ic": [1090, 226],
		"banner": "scene_worldmap_map_world_label_uno_kr", "bc": [1208, 194]},
]
## 잠금 지역의 이름배너(원작 WorldMapFullLayer 가 미해금 섬에 쓰는 물음표 프레임).
const _OV_BANNER_LOCKED := "scene_worldmap_map_world_label_question"
func _build_overview() -> void:
	var vis := _vis()
	# PC 적응: 원작은 스크롤뷰(1408×890>화면). 양피지가 화면 가로를 꽉 채우도록 fit-width로
	# 스케일하고 세로 중앙정렬(상하 약간 크롭 — 원작 스크롤뷰와 동일 성격). ASSUMPTION
	var S := vis.x / _OV_W
	var off := Vector2(0.0, (vis.y - _OV_H * S) * 0.5)
	var man := _load_manifest("worldmap_world")
	# cocos(y-up, 1408×890) → 화면좌표.
	var conv := func(cx: float, cy: float) -> Vector2:
		return off + Vector2(cx * S, (_OV_H - cy) * S)
	# 양피지 배경(bg.jpg). 원작 z=10. 섬과 동일 캔버스(1408×890)에 정렬해 섬이 양피지
	# 초록 바다 위에 얹히게 한다(cover-화면 독립스케일이면 섬 좌표와 어긋남).
	var bgp := "res://assets/converted/worldmap_world/bg.jpg"
	if ResourceLoader.exists(bgp):
		var bg := Sprite2D.new()
		bg.texture = load(bgp)
		bg.centered = true
		var t: Texture2D = bg.texture
		var bs := maxf(_OV_W / float(t.get_width()), _OV_H / float(t.get_height())) * S
		bg.scale = Vector2(bs, bs)
		bg.position = conv.call(_OV_W * 0.5, _OV_H * 0.5)
		_content.add_child(bg)
	# 섬(z=11+i) + 이름배너 + 히트영역.
	for r in _OVERVIEW:
		# 잠금 여부는 data/worldmap.json 의 `unlocked` 가 유일한 기준이다(§8.1 data 계층).
		var locked := not bool(_region(String(r["id"])).get("unlocked", false))
		var ic: Array = r["ic"]
		var isl := _sprite_native(String(r["island"]), "worldmap_world", man, S)
		if isl:
			isl.position = conv.call(float(ic[0]), float(ic[1]))
			if locked:
				isl.modulate = Color(0.55, 0.55, 0.6, 1)   # 잠금=흐리게
			_content.add_child(isl)
		var bc: Array = r["bc"]
		var bframe := _OV_BANNER_LOCKED if locked else String(r["banner"])
		var banner := _sprite_native(bframe, "worldmap_world", man, S)
		if banner:
			banner.position = conv.call(float(bc[0]), float(bc[1]))
			_content.add_child(banner)
		# 히트영역(해금만): 섬 중심 기준 박스 → 지역 이동.
		if not locked:
			var iw := float(man.get(String(r["island"]), {}).get("w", 160)) * S
			var ih := float(man.get(String(r["island"]), {}).get("h", 120)) * S
			var ip: Vector2 = conv.call(float(ic[0]), float(ic[1]))
			_add_hit(Rect2(ip.x - iw * 0.5, ip.y - ih * 0.5, iw, ih + 40 * S), "region", String(r["id"]))
	# 타이틀(label_worldmap): 원작 center X, top-100 → (704, 790).
	var title := _sprite_native("scene_worldmap_map_world_label_worldmap", "worldmap_world", man, S)
	if title:
		title.position = conv.call(_OV_W * 0.5, 790.0)
		_content.add_child(title)
	_horizontal = false
	_set_content_height(vis.y)

# ---------- 지역 ----------
## 노드에 pos가 있으면 지도 배치(배경+조각), 없으면 기존 세로 리스트로 폴백.
func _build_region(region_id: String) -> void:
	var region := _region(region_id)
	if region.has("native"):
		_build_region_native(region)
		return
	var nodes: Array = region.get("nodes", [])
	if not nodes.is_empty() and nodes[0].has("pos"):
		_build_region_map(region, nodes)
	else:
		_build_region_list(region_id, region, nodes)

## 원작 이식형(libgame WorldMapYutakanLayer). 배치 기준 = 원작 background1의 슬롯(빈칸).
## 각 조각을 자기 슬롯 중심(bg-atlas px)에 두고, bg와 동일 배율 S로 균일 변환 → 정확히 채움.
## pos = bg-atlas 픽셀좌표. design = bg_design + (pos - bg_tex_center)*S. pieces 배열순=z순서.
func _build_region_native(region: Dictionary) -> void:
	_horizontal = true
	var nat: Dictionary = region["native"]
	var dir := String(nat.get("atlas_dir", ""))
	var man := _load_manifest(dir)
	var coord: Dictionary = nat.get("coord", {})
	var S: float = float(coord.get("scale", 0.72))
	var tc: Array = coord.get("bg_tex_center", [735, 467.5])
	var bg_tex := Vector2(float(tc[0]), float(tc[1]))
	# 콘텐츠 폭은 **화면폭 미만이 될 수 없다** — 미만이면 바다 배경이 안 깔린 띠가 우측에 남는다
	# (🔴 2026-07-28: elf/dwarf content_w=1010 인데 창 1366×768 의 가시폭은 1231 이었다).
	var map_w: float = maxf(float(nat.get("content_w", 0.0)), _vis().x)
	var bd: Array = coord.get("bg_design", [map_w * 0.5, FLOOR * 0.5])
	var bg_design := Vector2(float(bd[0]), float(bd[1]))
	# center_x: 섬을 콘텐츠 가로 중앙에 둔다(해상도가 바뀌어도 좌우 여백이 균등).
	if bool(coord.get("center_x", false)):
		bg_design.x = map_w * 0.5
	# 바다 배경(worldmap_maps의 background.jpg, 스크롤 전체 덮음).
	# 하늘/바다 층은 원작에서 전부 z=0 이고 섬·조각은 z=10 이다 ⇒ **섬 뒤**에 깔린다.
	# 우리는 전용 컨테이너 `_backdrop`(z_index 매우 낮음)에 모아 넣는다 — 스파인 슬롯이
	# 자체 z_index(1~21)를 쓰기 때문에 형제 순서만으로는 위로 튀어나온다.
	_tintables.clear()
	_ambient_by_id.clear()
	_backdrop = Node2D.new()
	_backdrop.z_index = _BACKDROP_Z
	_content.add_child(_backdrop)
	var bgname := String(nat.get("background", ""))
	var bgp := "res://assets/converted/worldmap_maps/%s.jpg" % bgname
	# 디버그: 바다층을 생략하면 최하단의 마젠타 판이 투명 슬롯을 그대로 드러낸다.
	if bgname != "" and ResourceLoader.exists(bgp) and not Engine.has_meta("wm_no_ocean"):
		var bg := Sprite2D.new()
		bg.texture = load(bgp)
		bg.centered = false
		var tex: Texture2D = bg.texture
		bg.scale = Vector2(map_w / float(tex.get_width()), FLOOR / float(tex.get_height()))
		bg.z_index = _Z_SEA_BG
		_backdrop.add_child(bg)
		# 원작 initWidget 의 나머지 바다 3겹(거품망·비네트·물보라).
		_build_sea_layers(coord, S, map_w)
	# 베이스 지형(background1/bg) = 슬롯 뚫린 대륙. 조각들이 슬롯을 채움.
	var bgd: Dictionary = nat.get("bg", {})
	if bgd.has("frame"):
		var bspr := _sprite_native(String(bgd["frame"]), dir, man, S)
		if bspr:
			bspr.position = bg_design
			_content.add_child(bspr)
			_tintables.append(bspr)
	# 조각: pos(bg-atlas px)를 design으로 균일 변환해 슬롯 중심에 배치. z=배열순.
	# 라벨은 별도 수집 후 조각/배경 위에 일괄 배치(뒤 조각이 앞 라벨을 가리지 않게).
	var labels: Array = []
	var battle_nodes: Array = []   # setScenarioMark용: {d, stage_id}
	for p in region.get("pieces", []):
		var pos: Array = p["pos"]
		var d := bg_design + (Vector2(float(pos[0]), float(pos[1])) - bg_tex) * S
		# `design_offset` = 눈으로 맞추는 보정(디자인 px). 슬롯이 아니라 지형 위에 덧얹은
		# 오버레이 조각(빛의 탑·콜로세움·불의 산)은 슬롯 실측 기준이 없어 잔차가 남는다 —
		# `pos` 는 추출값 그대로 두고 여기만 만진다. 히트영역·라벨도 이 값을 함께 쓴다.
		if p.has("design_offset"):
			var pd: Array = p["design_offset"]
			d += Vector2(float(pd[0]), float(pd[1]))
		var frame := String(p.get("frame", ""))
		# 시각에 따라 프레임이 바뀌는 조각(빛의 탑). frame 은 폴백으로 남긴다.
		if String(p.get("frame_from", "")) == "light_tower":
			frame = _light_tower_frame(nat, frame)
		var spr := _sprite_native(frame, dir, man, S)
		if spr:
			spr.position = d
			# 특정 지형 조각이 내부 슬롯 z를 가진 Spine까지 가려야 할 때 쓰는 데이터 주도 순서.
			# 기본값 0은 기존 배열/형제 순서를 그대로 보존한다.
			spr.z_index = int(p.get("z_index", 0))
			_content.add_child(spr)
			_tintables.append(spr)
		var lbl := String(p.get("label", ""))
		# label_hidden = 원작 initLabel 에 그 필드가 없다(= 네임택을 안 단다). 이름은 데이터에 남긴다.
		if lbl != "" and not bool(p.get("label_hidden", false)):
			labels.append({"text": lbl, "d": d, "frame": frame, "piece": p})
		var tgt := String(p.get("target", ""))
		if String(p.get("type", "")) != "deco" and tgt != "":
			var w := float(man.get(frame, {}).get("w", 100)) * S
			var h := float(man.get(frame, {}).get("h", 100)) * S
			_add_hit_node(Rect2(d.x - w * 0.5, d.y - h * 0.5, w, h), tgt, Vector2(d.x, d.y), spr)
			if tgt.begins_with("battle:"):
				# h = 조각 아트 높이. 목표 마커를 **그 조각 위로** 띄우는 데 쓴다.
				battle_nodes.append({"d": d, "stage": tgt.substr(7), "h": h})
	# 앰비언트 애니(조각 위·라벨 아래). 원작 initAnimation 재현.
	_tintables.append_array(
		_add_ambient(nat.get("ambient", []), nat, dir, man, bg_design, bg_tex, S))
	# 필드 터치 연출(원작 setMapAnimation)은 여기서 만들지 않는다 — 필드를 눌렀을 때 띄운다.
	_field_fx_ctx = {"nat": nat, "dir": dir, "man": man,
		"bg_design": bg_design, "bg_tex": bg_tex, "S": S}
	_field_fx.clear()
	for e in nat.get("field_fx", []):
		_field_fx[int(e.get("field", -1))] = e
	_add_facility(nat, bg_design, bg_tex, S)
	# 소환된 혼돈의 틈새 보스(원작 WorldMapYutakanLayer::showDarknix). 조각 위·라벨 아래.
	_add_summoned_boss(region, bg_design, bg_tex, S)
	_mark_objective(battle_nodes, S)   # 원작 setScenarioMark: 다음 목표 던전 마커
	# 🔴 제거(2026-07-25): 배회 상인(showWonder)·임프(showImp)는 원작에서 서버 이벤트/알림 게이트다 —
	# WorldMapYutakanLayer.c:5055-5089 showWonder는 getAlarm_wonder/getEventWonder(이벤트 상인)/count 조건,
	# showImp도 상태 게이트. 평상시엔 등장하지 않음. 기존엔 이를 무조건 호출해 상시 배회(오연출)였음.
	# 오프라인엔 서버 이벤트/알림이 없으므로(§1·§2 유실) 상시 표시하지 않는다.
	# _build_wander_imp() / _build_wander_wonder()  ← 이벤트 게이트라 미호출(함수는 이벤트 훅용으로 보존).
	# 원작 showCloud: 하늘에 흐르는 구름. **낮에만** 띄운다 — 밤에도 카데스의 공간에도 없다
	# (사용자 원작 확인 2026-07-29). 카데스는 자체 보라 구름 7장이 따로 있다.
	if _yutakan_phase(nat) == "day":
		_build_clouds(coord, bg_design, bg_tex, S, map_w)
	# 필드 네임택(조각·배경보다 위). _content의 마지막 자식들 → 최상단 렌더.
	for it in labels:
		var d: Vector2 = it["d"]
		if not _field_label(it["piece"], coord, bg_design, bg_tex, S):
			_map_label(String(it["text"]), d.x, d.y, String(it["frame"]), S, man)
	# 유타칸은 **낮 / 밤 / 카데스의 공간 셋 중 하나**다(사용자 확정 2026-07-29).
	# 카데스에는 낮·밤 구분이 없다 → 밤 하늘을 겹쳐 깔지 않는다.
	match _yutakan_phase(nat):
		"night":
			# 원작 WorldMapYutakanLayer::changeNightAndDay.
			_apply_yutakan_night(nat, coord, dir, man, bg_design, bg_tex, S, map_w)
		"kades":
			# 원작 changeKadesAndAmorru — 저주 하늘 + 보라 착색 + 보라 구름 7장.
			_apply_kades_space(nat, coord, dir, man, bg_design, bg_tex, S, map_w)
	# 낮/밤 · 카데스 토글(유타칸 전용 — 해당 프레임이 이 아틀라스에만 있다).
	# 토글 자체는 MainHud 가 그린다(원작 아모르/카데스 tag 0x67·0x68 이 메인 메뉴 소속이라).
	_variant_toggles = (dir == _YUTAKAN_DIR)
	_max_scroll = maxf(0.0, map_w - _vis().x)
	_setup_area_sounds(nat, bg_design, bg_tex, S)

## 원작 `WorldMap*Layer::initSound` — 지역별 구역 앰비언트 3개를 등록한다.
## `native.sounds[].rect` = bg-아틀라스 px(y-down) → 콘텐츠(design) 좌표로 변환해 Bgm 에 넘긴다.
## 판정(구역 진입/이탈·볼륨·팬)은 `audio.gd::area_update` 가 원작 공식대로 한다.
func _setup_area_sounds(nat: Dictionary, bg_design: Vector2, bg_tex: Vector2, S: float) -> void:
	var areas: Array = []
	for s in nat.get("sounds", []):
		var r: Array = s.get("rect", [])
		if r.size() < 4:
			continue
		var tl := bg_design + (Vector2(float(r[0]), float(r[1])) - bg_tex) * S
		areas.append({"track": String(s.get("track", "")),
			"rect": Rect2(tl, Vector2(float(r[2]), float(r[3])) * S)})
	Bgm.area_setup(areas)
	_update_area_sounds()

## 화면 중앙을 콘텐츠 좌표로 바꿔 Bgm 에 알린다(원작은 스크롤 콜백마다 setWorldMapSound 호출).
func _update_area_sounds() -> void:
	var vis := _vis()
	var c := Vector2(vis.x * 0.5, vis.y * 0.5)
	if _horizontal:
		c.x += _scroll
	else:
		c.y += _scroll
	Bgm.area_update(c)

## 밤 상태 판정. ASSUMPTION: 원작 밤 플래그(getDBYutakanNight)는 서버 DB값(카데스 레이드/
## 스토리 진행으로 세팅) → 유실. 로컬 플래그로 대체(진입 params.night 우선, 없으면 native.night).
func _is_yutakan_night(nat: Dictionary) -> bool:
	if _params.has("night"):
		return bool(_params.get("night"))
	if UserDB.get_pmeta("yutakan_night", null) != null:
		return bool(UserDB.get_pmeta("yutakan_night", false))
	return bool(nat.get("night", false))

# ── 필드 터치 연출 (원작 setMapAnimation / setMapAnimationRemove) ─────────────
# 원작 `WorldMap*Layer::setMapAnimation(int field)` 는 필드를 누르면 그 필드 노드 밑에
# z=12·tag=10 으로 연출을 붙이고, `WorldMapLayer::setMapAnimationRemove` (@01af22ac) 가
# tag 10 자식을 지운다. **상시 앰비언트가 아니다** — 누르는 동안만 나온다.
# 우리 흐름: 조각 클릭 → `_closeup_then_goto`(줌인) 에서 재생 → 팝업을 닫는 `_reset_zoom` 에서 제거.
var _ambient_by_id: Dictionary = {}   # ambient[].id → 그 스파인 노드(터치 연출이 되찾아 쓴다)
var _field_fx: Dictionary = {}        # field(int) → data/worldmap.json 의 field_fx 항목
var _field_fx_ctx: Dictionary = {}    # 생성에 필요한 좌표계 컨텍스트(지역 빌드 시 채움)
var _field_fx_nodes: Array = []       # 지금 떠 있는 연출 노드(제거 대상)

## 필드 연출 재생. 이미 떠 있던 것은 원작처럼 먼저 뗀다.
func _play_field_fx(field: int) -> void:
	_clear_field_fx()
	var e: Dictionary = _field_fx.get(field, {})
	if e.is_empty() or _field_fx_ctx.is_empty():
		return
	var sounds: Array = e.get("sounds", [])
	if sounds.is_empty():
		var snd := String(e.get("sound", ""))
		if snd != "":
			sounds = [snd]
	for snd in sounds:
		if String(snd) != "":
			Bgm.sfx(String(snd))
	# 원작 case 0xd 처럼 **이미 떠 있는 앰비언트 스파인의 동작을 바꾸는** 연출.
	# 새 노드를 띄우는 게 아니라서 _field_fx_nodes 에도 넣지 않는다(제거 대상이 아니다).
	var touch_id := String(e.get("ambient_touch", ""))
	if touch_id == "veti":
		_veti_touch()
	elif touch_id != "":
		_play_ambient_touch(touch_id, String(e.get("anim", "")))
		return
	if String(e.get("kind", "")) == "sound":
		return
	# 빛의 탑은 애니 이름이 지금 속성을 따른다(원작 setMapAnimation case 15 의 중첩 switch).
	# ⚠️ 이름이 속성명과 1:1이 아니다 — light→touch_right, normal→touch_wind(케이스 흘러내림).
	#    그래서 문자열 조립이 아니라 data 의 touch_anims 표를 쓴다.
	var entry := (e as Dictionary).duplicate(true)
	if bool(e.get("anim_by_light_tower", false)):
		var nat: Dictionary = _field_fx_ctx["nat"]
		var lt: Dictionary = nat.get("light_tower", {})
		var tmap: Dictionary = lt.get("touch_anims", {})
		entry["anim"] = String(tmap.get(_light_tower_element(nat), "appear"))
	_field_fx_nodes = _add_ambient([entry], _field_fx_ctx["nat"], _field_fx_ctx["dir"],
		_field_fx_ctx["man"], _field_fx_ctx["bg_design"], _field_fx_ctx["bg_tex"],
		_field_fx_ctx["S"])

## 원작 setMapAnimationRemove.
func _clear_field_fx() -> void:
	for n in _field_fx_nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_field_fx_nodes.clear()

## 원작의 getChildByTag 경로처럼 상시 스파인을 직접 재생하고, 종료 뒤 setup 포즈로 돌린다.
func _play_ambient_touch(id: String, anim: String) -> void:
	var inst := _ambient_by_id.get(id) as Node2D
	if inst == null or not is_instance_valid(inst):
		return
	var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or anim == "" or not ap.has_animation(anim):
		return
	var token := int(inst.get_meta("touch_token", 0)) + 1
	inst.set_meta("touch_token", token)
	var clip := ap.get_animation(anim)
	if clip:
		clip.loop_mode = Animation.LOOP_NONE
	ap.stop()
	ap.play(anim)
	ap.animation_finished.connect(func(done: StringName):
		if is_instance_valid(inst) and int(inst.get_meta("touch_token", 0)) == token \
				and String(done) == anim:
			ap.stop()
			ap.seek(0.0, true), CONNECT_ONE_SHOT)

# ── 빛의 탑 속성 회전 ─────────────────────────────────────────────────────────
# 원작 `WorldMapYutakanLayer::showLightTower` @01b3a710. 흔치 않게 **유실분이 없다** —
# 속성이 서버값이 아니라 단말 시각에서 나온다:
#   localtime(GameManager::getTime()).tm_hour % 8 → 속성코드(:6990~7042)
#     0=A(물) 1=C(혼돈) 2=D(암흑) 3=E(대지) 4=F(불) 5=H(신성) 6=L(빛) 7=W(바람)
#   → GameManager::setDBLightTowerType(코드)  ← DB 저장은 캐시일 뿐(터치 연출이 되읽는다)
#   → 두 번째 switch(:7100~)가 코드→`map_yutakan_new/map_tower_*.png`
#   → 저장해 둔 위치에 addChild(z=9, tag=0x3f7)
# 우리는 조각을 만들 때 프레임만 고르면 된다(위치는 pieces 의 pos 가 이미 원작 슬롯).
# 표(속성↔프레임·순환)는 data/worldmap.json `native.light_tower` — §8.1 정적 정의라 data 계층.
# 원작 1글자 코드는 그 표의 `_codes` 에 남겼다(우리 키는 속성명).
## 지금 시각의 빛의 탑 속성. fallback 은 원작 첫 switch 에 없는 기본형 "normal".
func _light_tower_element(nat: Dictionary) -> String:
	var lt: Dictionary = nat.get("light_tower", {})
	var cycle: Array = lt.get("hour_cycle", [])
	if cycle.is_empty():
		return "normal"
	# 원작 tm_hour = 단말 로컬시각. Godot Time.get_datetime_dict_from_system() 도 로컬.
	var hour := int(Time.get_datetime_dict_from_system().get("hour", 0))
	return String(cycle[hour % cycle.size()])

## 빛의 탑 조각 프레임. 표에 없으면 조각의 원래 frame 을 그대로 쓴다.
func _light_tower_frame(nat: Dictionary, fallback: String) -> String:
	var lt: Dictionary = nat.get("light_tower", {})
	var frames: Dictionary = lt.get("frames", {})
	return String(frames.get(_light_tower_element(nat), fallback))

## 카데스의 공간 활성 여부. 원작은 카데스 레이드 이벤트 상태(서버) → 유실 → 로컬 토글.
func _is_kades_space(nat: Dictionary) -> bool:
	if _params.has("kades"):
		return bool(_params.get("kades"))
	if UserDB.get_pmeta("kades_space", null) != null:
		return bool(UserDB.get_pmeta("kades_space", false))
	return bool(nat.get("kades", false))

# ─────────────────────────────────────────────────────────────────────────────
# 유타칸 변형(밤 · 카데스의 공간) — 원작 `WorldMapYutakanLayer`
#   `changeNightAndDay(bool)`      @01b34268 (WorldMapYutakanLayer.c:1264~)
#   `changeKadesAndAmorru(bool,bool)` @01b34ae0 (:710~)
#
# 🔴 2026-07-29 전면 재이식. 종전 판의 두 가지 오독을 고쳤다.
#  (1) **z순서** — `night.png`(tag 0x1771) 와 `w_curse_sky.png`(tag 7000) 은 둘 다
#      `addChild(node)`(vtable +0x188, z 기본값 0)로 붙는다. 맵 배경·조각은 `addChild(node,10)`
#      (+0x190) 이다 ⇒ **변형 하늘은 맵 위 덮개가 아니라 섬 뒤 배경**이다. 종전엔 z=12 로
#      맵 위에 덮어 화면이 하얗게 날아갔다.
#  (2) **카데스의 보라색은 하늘이 아니라 착색** — `changeKadesAndAmorru` 는 배열(this+0x2a0)의
#      모든 `CCNodeRGBA` 에 `CCTintTo(0.5, 0xbf,0x80,0xf2)` 를 건다(:923~932). 배열에는
#      배경 bg(:3728) · 조각 스프라이트(:3823) · 앰비언트(:2373~2605) 가 들어 있다.
#      해제(아모르)는 같은 자리에서 `ccColor3B::WHITE` 로 되돌린다(:864~874).
#
# 구름 좌표는 원작에 **두 벌**이 있다 — 전환 애니(param_2=true)와 즉시 적용(false).
# 우리는 지역을 새로 그리므로 **즉시 적용 분기**(`changeKadesAndAmorru` else 절, :1032~1062)를 쓴다.
#   01 (424,723) 02 (82,431) 03 (733,273) 04 (1313,420) 05 (990,652) 06 (1810,630) 07 (1426,1126)
# ✅ 종전에 "디컴프 미복원 ASSUMPTION" 으로 뒀던 05.y / 07.x 는 원작 값으로 확정됐다
#    (`local_140 = 652.0` :866 · `local_17c = 1426.0` :869). 추정값 아니다.
# 구름은 `setScale(2.0)`(:947, 0x40000000 = 2.0f) · z=13 · tag 0x1b5a+i 다.
const _KADES_CLOUDS := [
	{"i": 1, "pos": [424.0, 723.0]},
	{"i": 2, "pos": [82.0, 431.0]},
	{"i": 3, "pos": [733.0, 273.0]},
	{"i": 4, "pos": [1313.0, 420.0]},
	{"i": 5, "pos": [990.0, 652.0]},
	{"i": 6, "pos": [1810.0, 630.0]},
	{"i": 7, "pos": [1426.0, 1126.0]},
]
const _KADES_CLOUD_SCALE := 2.0                  # 원작 setScale(2.0)
const _KADES_TINT := Color8(0xbf, 0x80, 0xf2)    # 원작 CCTintTo(0.5, 0xbf, 0x80, 0xf2)

## 착색 대상(원작 배열 this+0x2a0) — 섬 배경 · 조각 · 앰비언트. `_build_region_native` 가 채운다.
var _tintables: Array = []

## 하늘·바다 층 컨테이너. 원작에서 이 층들은 전부 z=0 이고 섬·조각이 z=10 이다.
## 컨테이너 z 를 크게 낮춰 두면 안에 든 스파인 슬롯의 z_index(1~21, 상대값)까지 전부 섬 아래에 남는다.
const _BACKDROP_Z := -1000
const _Z_SEA_BG := 0        # 1 background.jpg
const _Z_SEA_NEST := 100    # 2 ani_sea_spine "nest"
const _Z_SEA_TRANS := 200   # 3 background_trans/bg.png
const _Z_SEA_DUST := 300    # 4 ani_sea_spine "dustwave"
const _Z_VARIANT_SKY := 400 # changeNightAndDay / changeKadesAndAmorru 의 하늘
const _Z_CLOUD := 500       # showCloud
var _backdrop: Node2D

## 원작 레이어 좌표(포인트, y-up) → 우리 디자인 좌표.
## 어파인 계수는 `data/worldmap.json` 의 `native.coord.layer`(원작 initBG 좌표 ↔ background1
## 투명 슬롯 실측중심 최소제곱). 없으면 변환 불가 → false 를 함께 돌려준다.
func _layer_to_design(coord: Dictionary, bg_design: Vector2, bg_tex: Vector2, S: float,
		pt: Vector2) -> Array:
	var L: Dictionary = coord.get("layer", {})
	if L.is_empty():
		return [Vector2.ZERO, false]
	var ls := float(L.get("s", 0.0))
	var bgpx := Vector2(ls * pt.x + float(L.get("tx", 0.0)),
		-ls * pt.y + float(L.get("ty", 0.0)))
	return [bg_design + (bgpx - bg_tex) * S, true]

## 밤·카데스 변형을 가진 유일한 지역의 아틀라스 폴더(해당 프레임이 이 아틀라스에만 있다).
const _YUTAKAN_DIR := "worldmap_yutakan_new"

## 유타칸의 시각 위상 — **"day" / "night" / "kades" 셋 중 하나**(사용자 확정 2026-07-29:
## "카데스의 공간은 낮/밤 구분이 없음. 유타칸은 (낮), (밤), (카데스) 세 개").
##
## 저장은 원작 구조 그대로 독립 플래그 두 개(`getDBYutakanNight` / `getDBYutakanKades`)를 쓰고,
## **카데스가 우선**한다 — 원작 `WorldMapPopupLayer::init` 의 필드 번호 분기와 같은 우선순위다
## (카데스면 600번대, 아니면 밤일 때 500번대).
##
## 🔴 2026-07-31: **유타칸 전용**임을 여기서 못 박는다. 밤·카데스 플래그는 `UserDB` 전역
##   (`yutakan_night` / `kades_space`)이라 지역과 무관하게 참이 되는데, `_build_region_native`
##   는 우노·엘리시움·메탈타워에서도 이 함수를 부른다 ⇒ 밤을 켠 채 다른 지역으로 가면
##   `_apply_yutakan_night` 이 돌아 **임프상인이 따라다녔다**(사용자 지적). 밤하늘·발광점은
##   유타칸 전용 프레임 키라 조용히 누락돼 증상이 임프 하나로만 보였다. 카데스도 같은 구멍
##   (보라 착색이 남의 지역에 걸린다)이라 게이트를 이 한 곳에 둔다.
func _yutakan_phase(nat: Dictionary) -> String:
	if String(nat.get("atlas_dir", "")) != _YUTAKAN_DIR:
		return "day"
	if _is_kades_space(nat):
		return "kades"
	if _is_yutakan_night(nat):
		return "night"
	return "day"

# ── 바다 층 — 원작 `WorldMapLayer::initWidget` @01af12xx ─────────────────────
#
# **전 지역 공통 기반 클래스**라 유타칸·엘리시움·메탈타워·우노에 모두 걸린다. 네 겹이다:
#   1 `scene/worldmap/background.jpg`                       `setScaleX((280+2048)/w)`
#   2 `ani_sea_spine` anim `nest`      `setScale(4.0)`      하얀 거품망
#   3 `scene/worldmap/background_trans/bg.png`              `setScale(2048/w)` → `setScaleX((280+2048)/w)`
#   4 `ani_sea_spine` anim `dustwave`  `setScale(4.0)`      흩날리는 물보라
# 넷 다 `addChild(node)`(vtable +0x188) = **z 기본값 0**. 스파인 위치는
# `background.contentSize*0.5 + CCSize(280,0)*0.5` = 바다 중심 + (140,0) 레이어 포인트.
#
# 🔴 우리는 1번만 그리고 있어 바다가 단색이었다(사용자 지적 2026-07-29).
# 자산 변환 = `scripts/tools/build_worldmap_sea.py` → `build_worldmap_fx_scenes.gd`.
const _SEA_SPINE := "res://scenes/worldmap_fx/ani_sea_spine.tscn"
const _SEA_TRANS := "res://assets/converted/worldmap_sea/worldmap_sea_trans.png"
const _SEA_SPINE_SCALE := 4.0        # 원작 setScale(4.0)
# 사용자 검수 조정(2026-07-29) — 원작 값에서 벗어난 튜닝 노브다. 원작 기준은 위 4.0 / 속도 1.0.
#   우리 맵은 원작보다 훨씬 축소돼 보이므로(레이어 2234pt → 콘텐츠 1360px, 약 0.54배)
#   같은 거품망이라도 셀이 잘고 흐름이 빨라 보인다. 눈으로 맞춘 값.
const _SEA_TUNE_SCALE := 1.3         # 물결 레이어 크기 ×1.3
const _SEA_TUNE_SPEED := 0.75        # 물결 흐름 속도 −25%
const _SEA_OFFSET_PT := 140.0        # 원작 CCSize(280,0)*0.5 의 x
# 비네트 최종 크기(레이어 포인트). 원작은 `setScale(2048/w)` 로 **균일** 확대한 뒤
# `setScaleX((280+2048)/w)` 로 가로만 다시 잡는다. contentSize = 1350×913 px ÷ 0.75 = 1800×1217.3 pt
# ⇒ 폭 1800×(2328/1800) = 2328 pt · 높이 1217.3×(2048/1800) = 1385.1 pt.
# 🔴 종전엔 높이에 분자 2048 을 그대로 써서 **48% 너무 크게** 그렸다 — 그래서 위쪽 파란 띠가
#    화면 밖으로 밀려나 물결이 위까지 선명하게 보였다(사용자 지적 2026-07-29).
const _SEA_TRANS_W_PT := 2328.0
const _SEA_TRANS_H_PT := 1385.1
# 원본 캔버스(sourceSize)와 트림 오프셋. plist: sourceSize {1350,913} ·
# sourceColorRect {{0,162},{1350,751}} · offset {0,-81} ⇒ 잘린 조각의 중심이 캔버스 중심보다
# 81 캔버스px **아래**다. 변환본은 조각만 남으므로 그만큼 내려 줘야 원작 위치가 된다.
const _SEA_TRANS_CANVAS := Vector2(1350.0, 913.0)
const _SEA_TRANS_TRIM_DY := 81.0

## 레이어 포인트 → 우리 디자인 px 배율.
##
## 원작 레이어 좌표는 cocos 포인트고, 아틀라스 px → 포인트 = 4/3 (CLAUDE.md §9,
## `contentScaleFactor` 0.75) 이다. bg-아틀라스 px → 우리 디자인 = `S`(지역별 `coord.scale`)
## 이므로 **레이어 포인트 → bg-아틀라스 px = 0.75 로 지역과 무관하게 고정**이고,
## 레이어 포인트 → 디자인 = `0.75 × S` 다. `coord.layer.s` 는 그 값을 명시한 것뿐이라
## 없으면 이론값으로 대체한다(바다 층은 위치 어파인 tx/ty 가 필요 없어 이것만으로 충분하다).
const _LAYER_PT_TO_BGPX := 0.75
func _layer_scale(coord: Dictionary, S: float) -> float:
	return float((coord.get("layer", {}) as Dictionary).get("s", _LAYER_PT_TO_BGPX)) * S

## 바다 거품/비네트 3겹. 바다 배경 바로 위에 순서대로 끼우고 `_backdrop_at` 을 그 뒤로 민다
## (변형 하늘·구름이 이 층들보다 위에 오게 — 원작도 initWidget 다음에 붙는다).
func _build_sea_layers(coord: Dictionary, S: float, map_w: float) -> void:
	var ld := _layer_scale(coord, S)
	if ld <= 0.0:
		return                       # 어파인이 없는 지역은 배율 기준이 없어 건너뛴다
	var center := Vector2(map_w * 0.5 + _SEA_OFFSET_PT * ld, FLOOR * 0.5)
	_add_sea_spine("nest", center, ld, _Z_SEA_NEST)
	_add_sea_trans(map_w, ld)
	_add_sea_spine("dustwave", center, ld, _Z_SEA_DUST)

func _add_sea_spine(anim: String, center: Vector2, ld: float, z: int) -> void:
	if not ResourceLoader.exists(_SEA_SPINE):
		return
	var inst := (load(_SEA_SPINE) as PackedScene).instantiate() as Node2D
	if inst == null:
		return
	inst.position = center
	# 스파인은 원작 레이어 공간 저작 → 디자인 배율(ld)을 곱한 뒤 원작 setScale(4.0)
	# (거기에 사용자 검수 배수 `_SEA_TUNE_SCALE`).
	var sc := _SEA_SPINE_SCALE * _SEA_TUNE_SCALE * ld
	inst.scale = Vector2(sc, sc)
	inst.z_index = z
	_backdrop.add_child(inst)
	var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap and ap.has_animation(anim):
		var a := ap.get_animation(anim)
		if a:
			a.loop_mode = Animation.LOOP_LINEAR
		ap.speed_scale = _SEA_TUNE_SPEED
		ap.play(anim)

## 반투명 비네트. 원작 크기는 2328×2048 레이어포인트인데 우리 콘텐츠 폭이 더 넓어
## 변형 하늘과 같은 방식으로 **가로만** 콘텐츠까지 늘린다(`_add_variant_sky` 참조). # ASSUMPTION
func _add_sea_trans(map_w: float, ld: float) -> void:
	if not ResourceLoader.exists(_SEA_TRANS):
		return
	var spr := Sprite2D.new()
	spr.texture = load(_SEA_TRANS)
	spr.material = _pma
	var tex: Texture2D = spr.texture
	var fw := float(tex.get_width())
	var fh := float(tex.get_height())
	if fw <= 0.0 or fh <= 0.0:
		spr.queue_free()
		return
	# 배율은 **원본 캔버스** 기준이다(잘린 조각 크기가 아니라). 가로만 콘텐츠까지 늘린다.
	var sx := maxf(_SEA_TRANS_W_PT * ld, map_w) / _SEA_TRANS_CANVAS.x
	var sy := _SEA_TRANS_H_PT * ld / _SEA_TRANS_CANVAS.y
	spr.scale = Vector2(sx, sy)
	spr.position = Vector2(map_w * 0.5, FLOOR * 0.5 + _SEA_TRANS_TRIM_DY * sy)
	spr.z_index = _Z_SEA_TRANS
	_backdrop.add_child(spr)

## 변형 하늘(밤/카데스 공통). 원작은 둘 다 `setScale((280 + 2048) / contentSize.width)` 로
## **레이어 폭 2328pt** 를 채우고 `addChild(node)`(z=0) 로 붙인다 ⇒ 섬(z=10) 뒤 배경이다.
##
## 세로는 원작 크기(2328pt 폭 · 그 비율의 높이)를 **섬 중심에 맞춘다** — 그래야 프레임 가운데의
## 투명 영역이 섬 자리에 얹히고(섬은 밝게 남고 주변 바다만 어두워진다) 달·별이 하늘에 온다.
## 우리 콘텐츠 폭(`content_w`)은 화면을 채우려고 원작 맵보다 넓게 잡아 뒀으므로 그대로 두면
## 좌우에 낮 바다 띠가 남는다(스크롤 끝에서 세로 이음매로 보인다) → **가로만** 콘텐츠 폭까지
## 늘린다. 프레임 좌우 끝은 균일한 남색/보라색 면이라 가로 신축이 눈에 띄지 않는다. # ASSUMPTION
##
## ⚪ 아래쪽 바다가 밤에도 밝은 것은 **프레임 자체가 그렇다** — `night.png` 의 투명 영역은
##    y 28.3%~99.8% 로 프레임 아래끝까지 뚫려 있다(실측: alpha<40 최대 연결성분 bbox
##    (72,147)-(702,519)/768×520). 아래를 어둡게 하려면 없는 아트를 지어내야 한다.
const _SKY_LAYER_W := 2328.0   # 원작 setScale 분자 = CCSize(280,0).width + 2048
## 임프상인 — 원작 `WorldMapLayer::showImp` 축자 이식.
##
##   CCSkeletonAnimation::createWithFile("scene/worldmap/worldmap_imp_spine.spine_json",
##                                       "scene/worldmap/ani_imp_spine.img_plist", 1.0)
##   setScale(0x3f866666 = 1.05);  CCPoint(1370.0, 615.0);  addChild(..., tag 0x21)
##
## 탭하면 `iVar5 == 0x21` 분기로 `ImpShopScene::scene()` 이 열린다(WorldMapLayer.c:914).
## **밤에만** 선다 — `<NightTutorial_talk12>` "낮에는 방랑상인이 가끔 서 있던 곳에 밤에는
## 임프상인이 항상 서 있어." (낮의 그 자리는 `WonderShopScene` = 방랑상인, tag 0xc.)
##
## 좌표는 원작 **레이어 포인트**라 `_layer_to_design` 어파인으로 옮긴다. `worldmap.json`
## `coord.layer._note` 대로 원작의 +(140,0) 은 tx 에 흡수돼 있으므로 원좌표를 그대로 넣는다.
## 임프상인 아이콘 — 원작 `WorldMapLayer::showImp`.
##   크기 = `setScale(0x3f866666)` = **1.05**. 다른 월드맵 스파인과 같은 규칙으로
##   지역 축척(`coord.layer.s`)과 디자인 배율 S 를 함께 곱한다 → 화면에서 약 34px.
##   🔴 2026-07-31: 한때 150px 로 키웠는데 **오판이었다.** 안 보이던 진짜 원인은 크기가 아니라
##      부모 유실(아래 `_rebuild` 꼬리 주석)이었고, 사용자 확인으로도 "지금의 20% 정도"
##      = 원작 1.05 계산값과 일치한다.
##   위치 = 엘피스 마을 조각 근처(사용자 확인 2026-07-31). 원작 리터럴 `CCPoint(1370,615)` 는
##      레이어 공간 값인데 우리 어파인으로 옮기면 바다 위로 떨어져 그대로 못 쓴다.
const _IMP_DESIGN_POS := Vector2(600.0, 300.0)
const _IMP_SCALE := 1.05
var _imp_spine: Node2D
var _imp_pending := false

func _add_imp_shop() -> void:
	var sp := "res://scenes/worldmap_fx/worldmap_imp_spine.tscn"
	if not ResourceLoader.exists(sp) or not is_instance_valid(_content):
		return
	var inst := (load(sp) as PackedScene).instantiate() as Node2D
	if inst == null:
		return
	inst.position = _IMP_DESIGN_POS
	# 원작 setScale(1.05) × 지역 축척 × 디자인 배율(다른 월드맵 스파인과 같은 규칙).
	var co: Dictionary = _region_native().get("coord", {})
	var lay_s := float((co.get("layer", {}) as Dictionary).get("s", 0.75))
	var k := float(co.get("scale", 0.72)) * lay_s * _IMP_SCALE
	inst.scale = Vector2(k, k)
	inst.z_index = 30
	_content.add_child(inst)
	_imp_spine = inst
	var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap and ap.has_animation("normal"):
		ap.get_animation("normal").loop_mode = Animation.LOOP_LINEAR
		ap.play("normal")
	# 클릭 판정 — 스파인엔 히트박스가 없으므로 화면 좌표에 버튼을 얹는다.
	var btn := Button.new()
	btn.flat = true
	btn.size = Vector2(56.0, 56.0)   # 작은 아이콘이라 히트박스는 넉넉히
	btn.tooltip_text = "임프상인"
	btn.pressed.connect(_open_imp_shop)
	_imp_hit = btn
	_imp_hit_target = inst
	add_child(btn)
	_sync_imp_hit()

var _imp_hit: Button
var _imp_hit_target: Node2D

## 지도가 줌/이동하면 히트박스도 따라가야 한다 — 스파인의 **화면 좌표**로 매 프레임 맞춘다.
func _sync_imp_hit() -> void:
	if not is_instance_valid(_imp_hit) or not is_instance_valid(_imp_hit_target):
		return
	var sc := _imp_hit_target.get_global_transform_with_canvas().origin
	_imp_hit.position = sc - _imp_hit.size * 0.5

## 임프상점을 **월드맵 위 오버레이**로 연다(사용자 확정 2026-07-31).
##
## 원작은 `ImpShopScene::scene()` 으로 씬을 갈아 끼우지만, `initWidget` 첫 줄이
## `CCLayerColor(0x64000000)` = **검정 알파 100/255(≈39%)** 딤이다 — 뒤에 아무것도 없다면
## 반투명 딤을 깔 이유가 없다. 사용자 기억("유타칸 월드맵 위에 팝업 형식")과도 맞아
## 오프라인에서는 월드맵을 그대로 두고 그 위에 얹는다. 회색 허공이던 것을 고친다.
func _open_imp_shop() -> void:
	if is_instance_valid(_imp_layer):
		return
	Bgm.sfx("effect_button")
	var lay := CanvasLayer.new()
	lay.layer = 40
	add_child(lay)
	_imp_layer = lay
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 100.0 / 255.0)   # 원작 CCLayerColor(0x64000000)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # 뒤 지도 클릭 차단
	lay.add_child(dim)
	var scn := load("res://scenes/imp_shop.tscn") as PackedScene
	if scn == null:
		lay.queue_free()
		_imp_layer = null
		return
	var ui := scn.instantiate()
	lay.add_child(ui)
	if ui.has_method("enter"):
		ui.call("enter", {"region": _mode, "night": true, "overlay": true,
			"on_close": Callable(self, "_close_imp_shop")})

func _close_imp_shop() -> void:
	if is_instance_valid(_imp_layer):
		_imp_layer.queue_free()
	_imp_layer = null
	Bgm.play(_region_bgm(_mode))   # 상점 BGM → 지역 BGM 복귀

var _imp_layer: CanvasLayer

func _add_variant_sky(key: String, coord: Dictionary, dir: String, man: Dictionary,
		bg_design: Vector2, S: float, map_w: float) -> void:
	var sky := _sprite_native(key, dir, man, S)
	if sky == null:
		return
	var tex: Texture2D = sky.texture
	var fw := float(tex.get_width())
	var fh := float(tex.get_height())
	if fw <= 0.0 or fh <= 0.0:
		sky.queue_free()
		return
	# 레이어 포인트 → 디자인 px 배율(어파인 선형항 × 배경 배율).
	var ld := float((coord.get("layer", {}) as Dictionary).get("s", 0.0)) * S
	var sc0 := (_SKY_LAYER_W * ld / fw) if ld > 0.0 else (map_w / fw)   # 원작 배율
	sky.scale = Vector2(maxf(sc0, map_w / fw), sc0)                     # 가로만 콘텐츠 커버
	sky.position = Vector2(map_w * 0.5, bg_design.y)
	sky.z_index = _Z_VARIANT_SKY
	_backdrop.add_child(sky)

## 카데스의 공간 — 저주 하늘(배경) + 보라 착색 + 구름 7장(z13).
func _apply_kades_space(nat: Dictionary, coord: Dictionary, dir: String, man: Dictionary,
		bg_design: Vector2, bg_tex: Vector2, S: float, map_w: float) -> void:
	_add_variant_sky("scene_worldmap_map_yutakan_new_kades_w_curse_sky", coord, dir, man,
		bg_design, S, map_w)
	# 맵 전 요소를 보라로 물들인다(원작 CCTintTo 0.5초). 지역 진입은 이미 전환된 상태라 즉시 적용.
	for n in _tintables:
		if n is CanvasItem:
			(n as CanvasItem).modulate = _KADES_TINT
	# 구름 7장 — 원작 즉시 분기는 rand()%50×0.01 초 지연 뒤 등장(페이드 없음).
	var rng := RandomNumberGenerator.new(); rng.randomize()
	for c in _KADES_CLOUDS:
		var key := "scene_worldmap_map_yutakan_new_kades_w_cloud%02d" % int(c["i"])
		var spr := _sprite_native(key, dir, man, S * _KADES_CLOUD_SCALE)
		if spr == null:
			continue
		var p: Array = c["pos"]
		var r := _layer_to_design(coord, bg_design, bg_tex, S, Vector2(float(p[0]), float(p[1])))
		if not bool(r[1]):
			continue
		spr.position = r[0]
		spr.z_index = 13
		spr.modulate.a = 0.0
		_content.add_child(spr)
		var t := spr.create_tween()
		t.tween_interval(float(rng.randi() % 50) * 0.01)
		t.tween_property(spr, "modulate:a", 1.0, 0.0)
		# 저주 구름이 천천히 흐른다. # ASSUMPTION — 원작 즉시 분기엔 이동이 없다(전환 분기에만 있다).
		var drift := spr.create_tween().set_loops()
		var x0 := spr.position.x
		drift.tween_property(spr, "position:x", x0 + 40.0, 6.0).set_trans(Tween.TRANS_SINE)
		drift.tween_property(spr, "position:x", x0, 6.0).set_trans(Tween.TRANS_SINE)

## 유타칸 지역 뷰의 낮/밤 · 카데스 토글이 뜨는 화면인가.
## 원작은 마을 중앙 시계탑(낮/밤)과 레이드 이벤트(카데스)로 바뀌지만 그 상태값은
## 서버 DB(getDBYutakanNight 등)라 유실 → 로컬 토글 + UserDB 영속.
## 근거: 위키 map.pdf §3 "중앙 시계탑으로 낮/밤을 바꿀 수 있다 … 현재는 월드맵으로도 바꿀 수 있어".
## 🔴 종전에는 여기서 자작 `Button` 2개를 직접 그렸다 — 원작 아모르/카데스는 **메인 메뉴 소속**
##   (tag 0x67·0x68, `WorldMapScene::onClickChangeKades`)이라 MainHud 로 옮겼다.
var _variant_toggles := false

## 밤 — 밤하늘(배경, tag 0x1771) + 발광점(tag 0x1773, z13, 원작 pos (1566,994)).
## ⚪ tag 0x1772 는 `getChildByTag` 호출만 남고 **생성 블록이 디컴프에 없다**(:1490).
##    `night/night_light.png`(171×75) · `night_light1.png`(416×246) 프레임은 실재하지만
##    좌표 근거가 없어 배치하지 않는다 — 지어내지 않는다(CLAUDE.md §3). 원본 확보 시 여기부터.
func _apply_yutakan_night(nat: Dictionary, coord: Dictionary, dir: String, man: Dictionary,
		bg_design: Vector2, bg_tex: Vector2, S: float, map_w: float) -> void:
	_add_variant_sky("scene_worldmap_map_yutakan_new_night_night", coord, dir, man,
		bg_design, S, map_w)
	# tag 0x1773: night_light2 발광점. 원작은 `pos − ½boundingBox + (140,0)` 로 놓는데
	# 앞의 −½bbox 는 cocos 기본앵커(0.5,0.5) 를 좌하단 기준으로 되돌리는 관용구이므로
	# 중심앵커인 우리 스프라이트에는 pos 를 그대로 준다. (+140,0) 은 어파인 tx 에 흡수돼 있다.
	_imp_pending = true   # 실제 배치는 지도 빌드가 끝난 뒤(_rebuild 꼬리)
	var lc: Dictionary = nat.get("night_fx", {}).get("light2", {})
	var lp: Array = lc.get("layer_pos", [1566.0, 994.0])
	var lo: Array = lc.get("design_offset", [0.0, 0.0])
	var light := _sprite_native("scene_worldmap_map_yutakan_new_night_night_light2", dir, man, S)
	if light:
		var r := _layer_to_design(coord, bg_design, bg_tex, S,
			Vector2(float(lp[0]), float(lp[1])))
		if bool(r[1]):
			# design_offset = 어파인 잔차를 눈으로 메우는 보정(데이터 노브, 원작 좌표는 layer_pos).
			light.position = (r[0] as Vector2) + Vector2(float(lo[0]), float(lo[1]))
			light.z_index = 13
			_content.add_child(light)
		else:
			light.queue_free()
	_max_scroll = maxf(0.0, map_w - _vis().x)

## native 조각 스프라이트(지정 dir/manifest에서 로드, 회전복원, 중심앵커).
func _sprite_native(name: String, dir: String, man: Dictionary, scale := 1.0) -> Sprite2D:
	if name == "":
		return null
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if not ResourceLoader.exists(p):
		return null
	var s := Sprite2D.new()
	s.texture = load(p)
	s.material = _pma
	# 회전 보정 불필요 — 변환 단계가 흡수(scripts/tools/fix_rotated_frames.py)
	s.scale = Vector2(scale, scale)
	return s

## 지역 시설 스파인 + 진입 히트박스.
## 원작 `WorldMapUnoLayer::showMamorudic` — `worldmap_mamorudik.spine_json` 을 setAnimation("normal",
## loop) 로 z=13 tag=0x22 에 붙이고, `ccTouchOne` 이 tag 0x22 의 boundingBox 안이면
## `hidePopup()` 후 `MamorudicLab::scene()` 을 pushScene 한다(WorldMapUnoLayer.c:50~72).
## 마을이 조각(town 노드)인 다른 지역과 달리 우노의 시설은 **스파인**이라 별도 경로가 필요하다.
func _add_facility(nat: Dictionary, bg_design: Vector2, bg_tex: Vector2, S: float) -> void:
	var f: Dictionary = nat.get("facility", {})
	if f.is_empty():
		return
	var pos: Array = f.get("pos", [0, 0])
	var d := bg_design + (Vector2(float(pos[0]), float(pos[1])) - bg_tex) * S
	var sp := "res://scenes/worldmap_fx/%s.tscn" % String(f.get("scene", ""))
	if ResourceLoader.exists(sp):
		var inst := (load(sp) as PackedScene).instantiate() as Node2D
		if inst != null:
			inst.position = d
			# 앰비언트와 같은 이유로 지역 축척을 함께 곱한다(스파인은 원작 레이어 공간 저작).
			var fs := float(f.get("scale", 1.0))
			inst.scale = Vector2(S * fs, S * fs)
			_content.add_child(inst)
			var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if ap:
				var an := String(f.get("anim", ""))
				if an == "" or not ap.has_animation(an):
					an = ap.get_animation_list()[0] if ap.get_animation_list().size() > 0 else ""
				if an != "":
					var anim := ap.get_animation(an)
					if anim: anim.loop_mode = Animation.LOOP_LINEAR
					ap.play(an)
	var hit: Array = f.get("hit", [140, 180])
	var hw := float(hit[0]) * S
	var hh := float(hit[1]) * S
	_add_hit_node(Rect2(d.x - hw * 0.5, d.y - hh * 0.5, hw, hh), String(f.get("target", "")), d)
	var lbl := String(f.get("label", ""))
	if lbl != "":
		# 조각 라벨과 같은 모양. frame 을 안 주면 높이 폴백(100)으로 조금 위에 앉는다 →
		# 스파인 히트박스 높이를 넘겨 그 위로 올린다.
		_map_label(lbl, d.x, d.y - hh * 0.5 + 50.0, "", 1.0, {})

## 소환된 보스 스파인 — 원작 `WorldMapYutakanLayer::showDarknix(bool)`(:6263).
##
## 원작은 `getDarkNixStatus()` 1/2/3 으로 **같은 스켈레톤의 다른 변형**을 튼다
## (appear/breath/touch · appear2/… · appear3/…). 변형마다 켜지는 리그가 다르다
## (`dragon_darknix_adult_*` / `dragon_gri_*` / `ba_*`) — 즉 소환된 보스가 그대로 그려진다.
## 자산 `scene/worldmap/w_darknix.spine_json` + `ani_darknix_spine.img_plist` 는 둘 다 보유.
##
## 안무도 원작대로: 갓 소환됐으면 `appear`(논루프) → 끝나면 `breath` 루프, 아니면 곧바로
## `breath` 루프. 탭하면 `touch` 1회 후 다시 `breath`.
##
## # ASSUMPTION(좌표): 원작 절대좌표 (665.5,360)+(140,0) 등을 우리 bg-아틀라스 공간으로 옮기는
##   검증된 어파인이 없다 — yutakan `pieces[].pos` 는 원작 A점이 아니라 아틀라스 슬롯 실측이고,
##   A/B점 19쌍으로 적합하면 rms 82px 로 맞지 않는다(자기참조 함정). 그래서 다른 유타칸
##   스파인과 같은 규칙으로 **대응 조각(map020, field 8)의 검증된 슬롯 위치에 앵커**하고
##   `summon.design_offset` 으로 미세조정한다. 상세 = docs/ref/porting/ChaosRiftDarknix.md §3.
var _boss_spine: Node2D = null
var _boss_cfg: Dictionary = {}
func _add_summoned_boss(region: Dictionary, bg_design: Vector2, bg_tex: Vector2, S: float) -> void:
	_boss_spine = null
	_boss_cfg = {}
	var now := int(Time.get_unix_time_from_system())
	var state := UserDB.darknix()
	if not Darknix.is_active(state, now):
		return
	# 이 지역에 소환형 던전이 있나(= 그 스테이지의 summon 블록).
	var cfg: Dictionary = {}
	var anchor := -1
	for p in region.get("pieces", []):
		var tgt := String(p.get("target", ""))
		if not tgt.begins_with("battle:"):
			continue
		var stg := Data.stage(tgt.substr(7))
		if Darknix.is_summon_stage(stg):
			cfg = stg["summon"]
			anchor = int(p.get("field", -1))
			break
	if cfg.is_empty():
		return
	var sp := "res://scenes/worldmap_fx/%s.tscn" % String(cfg.get("spine", ""))
	if not ResourceLoader.exists(sp):
		return
	# 앵커 조각의 좌표를 그대로 다시 계산한다(조각 루프와 같은 식).
	var d := Vector2.ZERO
	for p in region.get("pieces", []):
		if int(p.get("field", -2)) != int(cfg.get("anchor_piece", anchor)):
			continue
		var pos: Array = p["pos"]
		d = bg_design + (Vector2(float(pos[0]), float(pos[1])) - bg_tex) * S
		if p.has("design_offset"):
			var pd: Array = p["design_offset"]
			d += Vector2(float(pd[0]), float(pd[1]))
		break
	if cfg.has("design_offset"):
		var od: Array = cfg["design_offset"]
		d += Vector2(float(od[0]), float(od[1])) * S
	var inst := (load(sp) as PackedScene).instantiate() as Node2D
	if inst == null:
		return
	inst.position = d
	# 다른 유타칸 스파인과 같은 이유로 지역 레이어 축척을 함께 곱한다(원작 레이어 공간 저작).
	var lay_s := float((region.get("native", {}) as Dictionary).get("coord", {}).get("layer", {}).get("s", 1.0))
	inst.scale = Vector2(S * lay_s, S * lay_s)
	_content.add_child(inst)
	_boss_spine = inst
	_boss_cfg = cfg
	var status := int(state.get("status", 1))
	var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		return
	# 갓 소환됐으면(등장 연출을 아직 안 봤으면) appear 부터. 원작 showDarknix(param_1=true) 대응.
	# 🔴 2026-07-31: "이미 봤나"를 **씬 지역변수로** 들고 있어서 월드맵을 떠났다 오면 초기화됐다
	#    → 매번 5.2초짜리 appear 가 다시 돌고, 그동안 드래곤 슬롯이 꺼져 있어 사용자에게는
	#    "보스가 사라지고 이펙트만 뜬다"로 보였다. 원작처럼 **계정 상태에 기억**한다
	#    (`AccountManager::getAlarm_darknix()==2`).
	var seen := UserDB.darknix_seen()
	var breath := Darknix.anim_of(cfg, status, 1)
	var appear := Darknix.anim_of(cfg, status, 0)
	if not seen and ap.has_animation(appear):
		UserDB.darknix_mark_seen()
		var a := ap.get_animation(appear)
		if a: a.loop_mode = Animation.LOOP_NONE
		ap.play(appear)
		ap.animation_finished.connect(func(_n): _boss_loop_breath(ap, breath), CONNECT_ONE_SHOT)
	else:
		_boss_loop_breath(ap, breath)
	# 탭 반응(원작 onClickIconMenu case 8: touch 1회 → 끝나면 breath 복귀).
	var touch := Darknix.anim_of(cfg, status, 2)
	var hit := Button.new(); hit.flat = true
	var hw := 150.0 * S
	var hh := 170.0 * S
	hit.size = Vector2(hw, hh)
	hit.position = d - Vector2(hw * 0.5, hh * 0.75)
	hit.pressed.connect(func(): _boss_touch(ap, touch, breath))
	_content.add_child(hit)

func _boss_loop_breath(ap: AnimationPlayer, breath: String) -> void:
	if not is_instance_valid(ap) or breath == "" or not ap.has_animation(breath):
		return
	var a := ap.get_animation(breath)
	if a: a.loop_mode = Animation.LOOP_LINEAR
	ap.play(breath)

## 원작 `onClickIconMenu` case 8 의 **보스 있음** 가지. 효과음
## (`music/effect_yutakan_8_chaos.mp3`)은 반대 가지 — 보스가 **없을 때** 나는 소리라
## 여기서는 울리지 않는다(원작 :5602 `spine == NULL || limitTime <= now` 조건).
func _boss_touch(ap: AnimationPlayer, touch: String, breath: String) -> void:
	if not is_instance_valid(ap) or touch == "" or not ap.has_animation(touch):
		return
	var a := ap.get_animation(touch)
	if a: a.loop_mode = Animation.LOOP_NONE
	ap.play(touch)
	ap.animation_finished.connect(func(_n): _boss_loop_breath(ap, breath), CONNECT_ONE_SHOT)

## 앰비언트 애니(원작 WorldMapYutakanLayer::initAnimation 재현). 프레임딜레이 0.2s.
## kind: flip(플립북 n프레임) / spin(연속회전) / pulse(스케일맥동) / bob(부유) / sway(좌우흔들) / spine.
## `entries` 를 받는 이유: 같은 생성 규칙을 **상시 앰비언트(initAnimation)** 와
## **필드 터치 연출(setMapAnimation)** 이 함께 쓴다. 만든 노드를 돌려줘 후자가 나중에 뗄 수 있게 한다.
const _AMBIENT_DELAY := 0.2  # 원작 CCAnimation::createWithSpriteFrames(frames, 0.2)
func _add_ambient(entries: Array, nat: Dictionary, dir: String, man: Dictionary,
		bg_design: Vector2, bg_tex: Vector2, S: float) -> Array:
	var made: Array = []
	var prefix := String(nat.get("ambient_prefix", ""))
	var coord: Dictionary = nat.get("coord", {})
	for a in entries:
		if not bool(a.get("enabled", true)):
			continue
		var d := Vector2.ZERO
		# 엘리시움·메탈타워 initAnimation 좌표는 배경과 같은 원작 레이어의 절대좌표다.
		# 종전에는 initBG bbox의 최소corner를 조각 중심으로 오인한 어파인으로 pos를 미리 구워
		# 모든 효과가 우하단으로 밀렸다. layer_pos는 원작 값을 보존하고, bbox 중심으로 검증한
		# coord.ambient 변환(contentScaleFactor 이론축척 0.75)을 런타임에 한 번만 적용한다.
		if a.has("layer_pos"):
			var lp: Array = a["layer_pos"]
			var A: Dictionary = coord.get("ambient", {})
			if lp.size() < 2 or A.is_empty():
				continue
			var ascale := float(A.get("s", 0.75))
			var bgpx := Vector2(ascale * float(lp[0]) + float(A.get("tx", 0.0)),
				-ascale * float(lp[1]) + float(A.get("ty", 0.0)))
			d = bg_design + (bgpx - bg_tex) * S
		else:
			var pos: Array = a.get("pos", [])
			if pos.size() < 2:
				continue
			d = bg_design + (Vector2(float(pos[0]), float(pos[1])) - bg_tex) * S
		# `design_offset` = 원작 유도값을 보존한 채 눈으로 맞추는 보정(디자인 px). 잔차가 큰
		# 오버레이 조각(빛의 탑 등)용 — `pos` 는 원작 근거 그대로 두고 여기만 만진다.
		if a.has("design_offset"):
			var od: Array = a["design_offset"]
			d += Vector2(float(od[0]), float(od[1]))
		var kind := String(a.get("kind", ""))
		var base := prefix + String(a.get("base", ""))
		if kind == "spine":
			# 원작 WorldMapYutakanLayer/ElfLayer/DwarfLayer::initAnimation은 이 앰비언트들을
			# CCSkeletonAnimation(스파인)으로 띄운다. spine_export --scene 으로 변환
			# → scenes/worldmap_fx/*.tscn.
			# 좌표: elf/dwarf 는 원작 절대좌표(layer_pos)를 bbox 중심으로 검증한
			# coord.ambient 어파인으로 옮긴다(docs/ref/porting/WorldMapAmbient_ElfDwarf.md).
			# yutakan 은 아직 ASSUMPTION(대응 던전 조각 위치).
			var sp := "res://scenes/worldmap_fx/%s.tscn" % String(a.get("scene", ""))
			if not ResourceLoader.exists(sp):
				continue
			var inst := (load(sp) as PackedScene).instantiate() as Node2D
			if inst == null:
				continue
			inst.position = d
			# 🔴 스파인은 **원작 레이어 공간**에서 저작됐다 — 우리 bg-아틀라스 공간은
			# contentScaleFactor 519/692 = 0.75배이므로 지역 축척을 함께 곱해야 한다.
			# 빠뜨리면 맵과 정확히 겹치도록 만들어진 바닥판 슬롯
			# (예 ani_cart_new 의 `w_dwarf_mine_book` = 페이지 전체 283×275)이 어긋나
			# **불투명 사각형으로 드러난다**(2026-07-27 실측으로 확인).
			# 기본값 = 그 지역의 **레이어 포인트 → bg-아틀라스 px** 배율(`coord.layer.s`, 이론값 0.75).
			# elf/dwarf 는 올바른 이론값 0.75를 항목마다 명시한다(기본값 1.0 경로).
			# 🔴 유타칸은 이 곱이 빠져 스파인이 **33% 크게** 그려지고 있었다(2026-07-29 사용자 지적:
			#    빛의 탑 터치 연출이 조각과 안 맞음).
			var lay_s := float(coord.get("layer", {}).get("s", 1.0))
			var a_scale := float(a.get("scale", lay_s))
			inst.scale = Vector2(S * a_scale, S * a_scale)
			# 🟡 배경판(`*_book`) 슬롯 숨김 — 원작 대비 의도적 이탈, 근거를 남긴다.
			# 이 슬롯들은 **맵 지형을 그대로 복제한 판**이다(cart 283×275 · elevator 105×282
			# · elf_tree 401×244). 원작은 풀해상도 맵 위에 픽셀단위로 겹쳐 움직이는 부품이
			# 지형에 가려지게 하는 용도로 쓴다. 우리 배경(background1/bg.png + 조각)이 이미
			# 같은 아트를 그리므로 한 번 더 그리면 **이중 렌더 + 축척 잔차로 사각형이 드러난다**
			# (2026-07-27 스크린샷으로 확인). 움직이는 부품은 그대로 두고 판만 숨긴다.
			for hs in a.get("hide_slots", []):
				var hn := inst.find_child(String(hs), true, false)
				if hn is CanvasItem:
					(hn as CanvasItem).visible = false
			_content.add_child(inst)
			made.append(inst)
			# id 가 붙은 앰비언트는 나중에 터치 연출이 **그 노드를 되찾아** 쓴다
			# (원작 setMapAnimation case 0xd 가 tag 11 을 getChildByTag 로 찾는 것과 같다).
			var aid := String(a.get("id", ""))
			if aid != "":
				_ambient_by_id[aid] = inst
				inst.set_meta("veti_home", d)
			var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if ap:
				if not bool(a.get("autoplay", true)):
					ap.stop()
					ap.seek(0.0, true)
					continue
				# `cycle` = 원작이 이 스파인에만 붙여 둔 전용 안무. 없으면 종전대로 무한루프 1종.
				match String(a.get("cycle", "")):
					"flash":
						_spine_flash_cycle(inst, ap, a)
						continue
					"veti":
						# 왕복 폭은 레이어pt → 디자인 px 로 환산해 노드에 새겨 둔다(터치 복귀 때 재사용).
						inst.set_meta("veti_span", _VETI_WALK_SPAN * 0.75 * S)
						_veti_cycle(inst, ap, d)
						continue
				var an := String(a.get("anim", ""))
				if an == "" or not ap.has_animation(an):
					an = ap.get_animation_list()[0] if ap.get_animation_list().size() > 0 else ""
				if an != "":
					# 원작 `setAnimation(name, loop, 0)` 의 loop 인자. **필드마다 다르다** —
					# `setMapAnimation` 은 shiptouch/wind/treee/waterfall/lighttower 를 `false`,
					# worldmap_lake·kal 만 `true` 로 준다(WorldMapYutakanLayer.c 축자).
					# 상시 앰비언트(`initAnimation`)는 loop=true 라 기본값이 true 다.
					var anim := ap.get_animation(an)
					var loop := bool(a.get("loop", true))
					if anim:
						anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
					ap.play(an)
					var remove_after := float(a.get("remove_after", 0.0))
					if remove_after > 0.0:
						var cleanup := inst.create_tween()
						cleanup.tween_interval(remove_after)
						cleanup.tween_property(inst, "modulate:a", 0.0, 0.5)
						cleanup.tween_callback(inst.queue_free)
			continue
		if kind == "sprite":
			var spr := _sprite_native(prefix + String(a.get("base", "")), dir, man, S)
			if spr == null:
				continue
			spr.position = d
			_content.add_child(spr)
			made.append(spr)
			spr.modulate.a = 0.0
			var tw := spr.create_tween()
			var fade_in := float(a.get("fade_in", 0.5))
			var fade_out := float(a.get("fade_out", 0.5))
			var pulses := maxi(1, int(a.get("pulses", 1)))
			for _i in range(pulses):
				tw.tween_property(spr, "modulate:a", 1.0, fade_in)
				if pulses == 1:
					tw.tween_interval(float(a.get("hold", 0.0)))
				tw.tween_property(spr, "modulate:a", 0.0, fade_out)
			tw.tween_callback(spr.queue_free)
			continue
		if kind == "flip":
			var n := int(a.get("n", 1))
			# 🔴버그수정(2026-07-27, 뿌리 수정): Cocos plist는 프레임을 90° 회전 패킹 → 시퀀스 내
			# 프레임마다 rotated 플래그가 혼재(예 ani_cow=[F,T,F,T…])해서 플립북이 90° 튀었다.
			# 프레임별 회전을 여기서 섞던 땜질을 걷고 **변환 단계에서 세운다**
			# (scripts/tools/fix_rotated_frames.py → 회전 프레임은 세운 낱장 PNG).
			# 🔴드리프트수정(2026-07-25): 프레임마다 트림 크기/오프셋이 달라(중심정렬 시 미세 이동) →
			# plist offset(트림중심-원본캔버스중심, cocos y-up)을 프레임01 기준 상대로 적용해 정렬.
			# (cocos_export가 매니페스트 off/src 방출하도록 수정 → 전 지역 앰비언트 재추출 필요.)
			# no_offset: 오프셋 보정 비활성(각 프레임 중심정렬). 상승형 애니(연기 등)는 오프셋을 적용하면
			# 프레임마다 위로 상승 → 루프시 프레임1로 아래로 순간이동(튐). 중심정렬하면 제자리 billow로 튐 제거.
			var use_off := not bool(a.get("no_offset", false))
			var off01: Array = man.get("%s01" % base, {}).get("off", [0, 0])
			var frames: Array = []  # [{tex, rot, off}]
			for i in range(1, n + 1):
				var fname := "%s%02d" % [base, i]
				var t := _tex_native(fname, dir)
				if t:
					var mi: Dictionary = man.get(fname, {})
					var frot := 0.0   # 회전은 변환 단계가 흡수 — 프레임별 보정 없음
					var offi: Array = mi.get("off", off01)
					var od := Vector2.ZERO
					if use_off:
						od = Vector2(float(offi[0]) - float(off01[0]), -(float(offi[1]) - float(off01[1]))) * S
					frames.append({"tex": t, "rot": frot, "off": od})
			if frames.is_empty():
				continue
			var s := _sprite_native("%s01" % base, dir, man, S)
			if not s:
				continue
			s.position = d
			_content.add_child(s)
			made.append(s)
			var tw := s.create_tween().set_loops()
			for fr in frames:
				var ftex: Texture2D = fr["tex"]
				var frot2: float = fr["rot"]
				var foff: Vector2 = fr["off"]
				tw.tween_callback(func():
					s.texture = ftex
					s.rotation = frot2
					s.position = d + foff)
				tw.tween_interval(_AMBIENT_DELAY)
			continue
		var spr := _sprite_native(base, dir, man, S)
		if not spr:
			continue
		spr.position = d
		_content.add_child(spr)
		made.append(spr)
		match kind:
			"spin":
				var per := float(a.get("period", 2.0))
				var t2 := spr.create_tween().set_loops()
				t2.tween_property(spr, "rotation", spr.rotation + PI, per).as_relative()
			"pulse":
				var to := float(a.get("to", 1.2))
				var per2 := float(a.get("period", 2.0))
				var t3 := spr.create_tween().set_loops()
				t3.tween_property(spr, "scale", Vector2(S * to, S * to), per2)
				t3.tween_interval(0.5)
				t3.tween_property(spr, "scale", Vector2(S, S), per2)
			"bob":
				# 원작 MoveBy 시퀀스(cocos y-up→design y-flip, 진폭*S). 잔잔한 부유.
				var t4 := spr.create_tween().set_loops()
				for mv in [[0, -5, 1.0], [0, 5, 1.5], [-2, -2, 1.0], [2, 2, 1.5], [-10, 0, 2.0], [10, -5, 2.0], [0, 5, 1.0]]:
					t4.tween_property(spr, "position", Vector2(mv[0] * S, mv[1] * S), mv[2]).as_relative()
			"sway":
				var t5 := spr.create_tween().set_loops()
				t5.tween_property(spr, "position", Vector2(10 * S, 0), 3.5).as_relative()
				t5.tween_property(spr, "position", Vector2(-10 * S, 0), 3.5).as_relative()
	return made

# ── 전용 안무 스파인 2종 (원작 initAnimation 안에 하드코딩된 것) ──────────────────
#
# 🔴 2026-07-29 사용자 지적 "수중동굴 박쥐가 계속 돈다 / 예티가 너무 위에 있고 터치 모션이 있었다".
#    둘 다 **원작이 무한루프가 아니었다.** `WorldMapYutakanLayer::initAnimation` 실측:
#
#  · ani_cave(수중동굴 박쥐) :5213~
#      setVisible(false) 로 **숨긴 채** 시작하고
#      CCRepeatForever( CCDelayTime(rand()%10 + 10) → 보이기+setAnimation("bat")
#                       → CCDelayTime(getDuration("bat")) → 숨기기 )
#      ⇒ 평소엔 꺼져 있고 10~19초에 한 번 한 사이클만 지나간다. 클릭과는 무관하다
#        (`setMapAnimation` case 9 는 **사운드뿐** — 박쥐를 건드리지 않는다).
#
#  · ani_veti(도적의 이글루) :5047~ + `animationVeti` @01b38da8
#      setAnimation("breath", loop=false) 로 시작, tag=11 로 붙이고
#      animationVeti 가 rand()%9 로 다음 동작을 뽑아 **한 번씩만** 재생하고 스스로 다시 부른다:
#        0~2 breath(2.83) · 3~4 walk(6.12) · 5~6 scratch(4.79) · 7 sleep(19.2) · 8 snowman(19.2)
#      "walk" 일 때만 CCMoveTo(5.0) 로 x 380↔510(레이어pt) 사이를 오가며 scaleX 를 뒤집는다.
#      ⇒ 왕복 구간 y=930 은 최초 배치 y=980 보다 50pt **아래**다 — 사용자가 "50픽셀 내려라"라고
#        본 것이 이 정착 위치다.

## 원작 박쥐 사이클. 숨김 → 10~19초 대기 → 한 번 재생 → 다시 숨김(무한).
func _spine_flash_cycle(inst: Node2D, ap: AnimationPlayer, a: Dictionary) -> void:
	var an := String(a.get("anim", ""))
	if not ap.has_animation(an):
		return
	var lo := float(a.get("gap_min", 10.0))     # 원작 rand()%10 + 10
	var hi := float(a.get("gap_max", 19.0))
	var dur: float = ap.get_animation(an).length
	inst.visible = false
	var rng := RandomNumberGenerator.new(); rng.randomize()
	while is_instance_valid(inst) and inst.is_inside_tree():
		await get_tree().create_timer(rng.randf_range(lo, hi)).timeout
		if not (is_instance_valid(inst) and inst.is_inside_tree()):
			return
		inst.visible = true
		ap.play(an)
		await get_tree().create_timer(dur).timeout
		if not is_instance_valid(inst):
			return
		inst.visible = false

## 원작 `animationVeti` — 동작을 뽑아 한 번 재생하고 스스로 다음 동작을 부른다.
## rand()%9 분포·재생시간은 원작 리터럴 그대로. `walk` 만 좌우 왕복 + 좌우반전이 붙는다.
const _VETI_ACTS := [                     # [애니, 지속(초), 뽑기 가중치]
	["breath", 2.83, 3], ["walk", 6.12, 2], ["scratch", 4.79, 2],
	["sleep", 19.2, 1], ["snowman", 19.2, 1],
]
const _VETI_WALK_MOVE := 5.0              # 원작 CCMoveTo(5.0, …)
## 왕복 폭 — 원작 레이어 x 380↔510 = 130pt. 레이어pt → 디자인 px = 0.75(어파인) × S(지역축척).
const _VETI_WALK_SPAN := 130.0
## 터치 모션 뒤 기본 사이클로 돌아가기까지. 원작 `CCDelayTime(14.3)` + CCCallFuncN(animationVeti).
const _VETI_TOUCH_BACK := 14.3

func _veti_cycle(inst: Node2D, ap: AnimationPlayer, home: Vector2) -> void:
	var gen := int(inst.get_meta("veti_gen", 0))
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var span := float(inst.get_meta("veti_span", 70.0))
	while is_instance_valid(inst) and inst.is_inside_tree():
		# 세대가 바뀌었으면(터치가 끼어들었으면) 이 루프는 물러난다.
		if int(inst.get_meta("veti_gen", 0)) != gen:
			return
		var pick := rng.randi_range(0, 8)          # 원작 rand() % 9
		var act: Array = _VETI_ACTS[0]
		var acc := 0
		for e in _VETI_ACTS:
			acc += int(e[2])
			if pick < acc:
				act = e
				break
		var an := String(act[0])
		var dur := float(act[1])
		if ap.has_animation(an):
			ap.get_animation(an).loop_mode = Animation.LOOP_NONE
			ap.play(an)
		if an == "walk":
			# 원작: 지금 위치가 왼쪽 끝이면 오른쪽으로(scaleX −1), 아니면 왼쪽으로(+1).
			var at_home := absf(inst.position.x - home.x) < 1.0
			var tgt := home.x + (span if at_home else 0.0)
			inst.scale.x = -absf(inst.scale.x) if at_home else absf(inst.scale.x)
			var tw := inst.create_tween()
			tw.tween_property(inst, "position:x", tgt, _VETI_WALK_MOVE)
		await get_tree().create_timer(dur).timeout

## 원작 `setMapAnimation` case 0xd — 이글루를 누르면 tag 11(예티)의 동작을 끊고
## "embarrassed" 를 한 번 재생한 뒤 14.3초 후 기본 사이클로 복귀한다.
func _veti_touch() -> void:
	var inst := _ambient_by_id.get("veti") as Node2D
	if inst == null or not is_instance_valid(inst):
		return
	var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation("embarrassed"):
		return
	# 세대 증가 = 돌고 있던 기본 사이클에 "물러나라" 신호(원작 stopAllActions).
	inst.set_meta("veti_gen", int(inst.get_meta("veti_gen", 0)) + 1)
	var home: Vector2 = inst.get_meta("veti_home", inst.position)
	ap.get_animation("embarrassed").loop_mode = Animation.LOOP_NONE
	ap.play("embarrassed")
	await get_tree().create_timer(_VETI_TOUCH_BACK).timeout
	if is_instance_valid(inst) and inst.is_inside_tree():
		_veti_cycle(inst, ap, home)

## 프레임명 → AtlasTexture(.tres) 로드(없으면 null).
func _tex_native(name: String, dir: String) -> Texture2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	return load(p) if ResourceLoader.exists(p) else null

## 지도형: background(바다) 위에 각 조각을 pos 좌표에 배치 + 라벨 + 핫스팟. 가로 스크롤.
func _build_region_map(region: Dictionary, nodes: Array) -> void:
	_horizontal = true
	var pscale: float = float(region.get("piece_scale", 0.5))
	var map_w: float = float(region.get("map_w", _vis().x))
	# 바다 배경(지도 전체 덮음, 스크롤 동반). 디버그: wm_no_ocean 메타 시 생략(빈 슬롯 확인용).
	var bgname := String(region.get("background", ""))
	var bgp := "res://assets/converted/worldmap_maps/%s.jpg" % bgname
	if bgname != "" and ResourceLoader.exists(bgp) and not Engine.has_meta("wm_no_ocean"):
		var bg := Sprite2D.new()
		bg.texture = load(bgp)
		bg.centered = false
		var tex: Texture2D = bg.texture
		bg.scale = Vector2(map_w / float(tex.get_width()), FLOOR / float(tex.get_height()))
		_content.add_child(bg)
	# 베이스 섬(background1: 지형+연결다리+던전 슬롯구멍). 조각들이 이 구멍을 채움.
	var island := String(region.get("island", ""))
	var ipath := "res://assets/converted/worldmap_maps/%s.png" % island
	if island != "" and ResourceLoader.exists(ipath):
		var isp := Sprite2D.new()
		isp.texture = load(ipath)
		isp.centered = false
		var iscale: float = float(region.get("island_scale", 1.0))
		isp.scale = Vector2(iscale, iscale)
		var ipos: Array = region.get("island_pos", [0, 0])
		isp.position = Vector2(float(ipos[0]), float(ipos[1]))
		_content.add_child(isp)
	# 장식(비클릭 배경 조각: 콜로세움/마을회관/밭 등) + 노드(클릭 던전)를 하나로 합쳐 y순 z정렬.
	var items: Array = []
	for d in region.get("decorations", []):
		items.append({"nd": d, "is_node": false})
	for nd in nodes:
		items.append({"nd": nd, "is_node": true})
	items.sort_custom(func(a, b): return float(a["nd"]["pos"][1]) < float(b["nd"]["pos"][1]))
	for it in items:
		var nd: Dictionary = it["nd"]
		var px: float = float(nd["pos"][0])
		var py: float = float(nd["pos"][1])
		var frame := String(nd.get("frame", ""))
		# 오버레이 조각(콜로세움 등)은 홀채움이 아니라 지형 위에 얹혀서, 개별 scale로 인접 지형에 맞물리게 함.
		var iscale2: float = float(nd.get("scale", pscale))
		var piece := _sprite(frame, iscale2)
		if piece:
			piece.position = Vector2(px, py)
			_content.add_child(piece)
		_map_label(String(nd.get("label", "")), px, py, frame, iscale2)
		if it["is_node"]:
			var w := _fw(frame) * iscale2
			var h := _fh(frame) * iscale2
			_add_hit_node(Rect2(px - w * 0.5, py - h * 0.5, w, h), String(nd.get("target", "")), Vector2(px, py))
	_max_scroll = maxf(0.0, map_w - _vis().x)

## ---------- 필드 네임택 (원작 `WorldMapLayer::setWorldMapLabel` 이식) ----------
##
## 상세 = `docs/ref/porting/WorldMapLabel.md`. 요약:
##   판   = `CCScale9Sprite(new9patch/ma_box_level)` `setContentSize(max(labelW,140)+20, 36)`
##   글자 = `CCLabelBMFontEx("LV%d " + name)` 판 자식 · `setScale(0.8)` · 외곽선 BLACK
##   배율 = `max(0.8/zoom, 0.7)` ⇒ 줌과 무관하게 **화면상 크기가 일정**(판 36×0.8 = 28.8pt)
##   위치 = align 1 이면 `pos − ½판`(판 우상단이 pos), 0 이면 판 중심이 pos
##
## 🟠 후기판 `new9patch/ma_box_level.png` 은 우리 덤프에 없다(`new9patch/` 통째 부재).
##    대신 **구판 2겹 원본**을 쓴다 — `9patch/label_bg`(흰 물결판, 필드색 틴트) +
##    `9patch/label_frame`(어두운 물결 테두리) / 특수 지역은 `scene/worldmap/label_frame_special`
##    (금테). 같은 105×38 물결 프레임이고 `BattleScene`·`FightScene` 도 bg+frame 2겹으로 쓴다
##    (`BattleScene.c:1108/1156`). capInsets 미지정 = Cocos 기본 1/3 분할 → `AtlasUI.nine(cap=Rect2())`.
## 판 크기 — 원작은 `setContentSize(max(labelW,140)+20, 36)` × 노드배율 0.8 이라 (하한 128, 높이 28.8)pt.
## 🟡 사용자 조정(2026-07-29): "좀 더 가로로 길고 세로로 짧게" → 하한을 늘리고 높이를 줄였다.
##    원작 수치는 위 주석에 남긴다(되돌릴 때 이 값들만 128/28.8 로).
const _LBL_PLATE_H := 33.6           # 사용자 조정: 24 × 1.4
const _LBL_MIN_W := 105.6            # 사용자 조정: 132 × 0.8
const _LBL_PAD_W := 12.8             # 원작 +20 × 0.8, 다시 × 0.8
## 판 불투명도(글자는 제외 — 글자는 또렷해야 읽힌다). 사용자 조정 2026-07-29.
const _LBL_PLATE_ALPHA := 0.6
## 네임택 z. 원작은 `addChild(this, plate, 0x10, …)` = **16**(앰비언트 z11 위)인데, Cocos 의 자식 z 는
## 부모의 형제 순서로 **새지 않는다**. Godot 의 `z_index` 는 기본이 상대값이라 스파인 내부 슬롯 z
## (`ani_veti_spine` 최대 **19**)가 그대로 더해져 예티 팔이 네임택 위로 올라온다(사용자 지적).
## ⇒ 원작의 "라벨이 앰비언트보다 위" 의도만 지키고 숫자는 스파인 슬롯 범위 위로 올린다.
const _LBL_Z := 40
const _LBL_TEXT_DX := 2.0            # 원작 라벨 위치 (w/2+2, h/2+2) 의 +2
## Lv 줄과 이름 줄의 중심 간격. 원작은 2줄 한 라벨의 행높이지만 우리 폰트와 행높이가 달라
## 그대로 두면 이름 줄이 판 밖으로 내려간다 → **이름 줄을 판 중앙에 고정**하고 Lv 줄을 이
## 간격만큼 위에 얹는다. 값 = main.png 실측(줄 중심 27.5 화면px / 1.176 = 23.4pt).
const _LBL_LINE_GAP := 22.5
## 네임택 글꼴 — **`font_common`(HCR Dotum, 가는체)**. `font_subtitle`(Noto Sans CJK) 로 그렸더니
## 원작보다 굵고 컸다(2026-07-29 사용자 지적). main.png 실측 대조:
##   원작 글자 h 16.2 / w 84.2 (혼돈의 틈새) ↔ font_subtitle 1.0 은 h 22.5 / w 145.1
##   ⇒ 높이 1.39배·**폭 1.72배** — 폭이 더 벌어지는 건 자소가 넓은 폰트라는 뜻이라 글꼴부터 바꾼다.
## 배율은 원작 글자 높이 16.2pt 에 맞춘 값(HCR Dotum 17 × 4/3 × scale).
const _LBL_FONT := "common"
const _LBL_FONT_SCALE := 0.80
const _LBL_OUTLINE := 3        # 원작 외곽선은 얇다 — 종전 5는 자소를 먹어 더 굵어 보였다
## 🟡 LV 줄만 크고 굵게 — **원작 대비 의도적 이탈**(사용자 요청 2026-07-29).
## 원작은 `"LV%d " + name` 을 **CCLabelBMFontEx 하나로** 만든다(BMFont 라벨 = 글리프 아틀라스 1개)
## ⇒ 줄마다 굵기를 달리하는 것이 **구조적으로 불가능**했다. 그런데도 main.png 에서 LV 줄이 굵고
## 커 보이는 건 그 폰트의 라틴·숫자 글리프가 한글 글리프보다 크고 두껍게 그려져 있기 때문이다.
## 우리 `font_common` 은 그렇지 않아서, 같은 인상을 내려면 LV 줄만 따로 키우고 외곽선을 두껍게 한다.
const _LBL_LV_SCALE := 1.15    # 이름 줄 대비 배율
const _LBL_LV_OUTLINE := 5

## `9patch/label_bg` 를 필드색으로 물들인 판 + 테두리 + 1~2줄 글자.
## `anchor` = align 0 이면 판 **중심**, align 1 이면 판 **우상단**(원작 `pos − ½boundingBox`).
## `level` 0 이면 Lv 줄 없음(원작: level_min==0 또는 field 6·8).
func _field_plate(name: String, level: int, color: Color, special: bool,
		anchor: Vector2, align := 0) -> void:
	if name == "":
		return
	var lv := _bmf_ui(_LBL_FONT_SCALE * _LBL_LV_SCALE, _LBL_FONT) if level > 0 else null
	var nm := _bmf_ui(_LBL_FONT_SCALE, _LBL_FONT)
	nm.text = name
	var text_w: float = nm.get_theme_font("font").get_string_size(
		name, HORIZONTAL_ALIGNMENT_LEFT, -1, nm.get_theme_font_size("font_size")).x
	var pw := maxf(text_w, _LBL_MIN_W) + _LBL_PAD_W
	var root := Node2D.new()
	# cocos y-up 에서 −½h 는 디자인(y-down)에서 +½h 다.
	root.position = anchor + (Vector2(-pw * 0.5, _LBL_PLATE_H * 0.5) if align == 1 else Vector2.ZERO)
	root.z_index = _LBL_Z
	_content.add_child(root)
	var sz := Vector2(pw, _LBL_PLATE_H)
	var bg := AtlasUI.nine("ninepatch_ui", "9patch_label_bg", sz)
	if bg != null:
		bg.modulate = Color(color.r, color.g, color.b, _LBL_PLATE_ALPHA)
		bg.position = -sz * 0.5
		root.add_child(bg)
	var fr := AtlasUI.nine("worldmap_ui", "scene_worldmap_label_frame_special", sz) if special \
		else AtlasUI.nine("ninepatch_ui", "9patch_label_frame", sz)
	if fr != null:
		fr.modulate.a = _LBL_PLATE_ALPHA
		fr.position = -sz * 0.5
		root.add_child(fr)
	for l in [lv, nm]:
		if l == null:
			continue
		if l == lv:
			l.text = "LV%d" % level      # 원작 CCString::createWithFormat("LV%d ", level_min)
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))   # 원작 setColor(BLACK)
		l.add_theme_constant_override("outline_size",
			_LBL_LV_OUTLINE if l == lv else _LBL_OUTLINE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size = sz
		l.position = Vector2(-pw * 0.5 + _LBL_TEXT_DX,
			-_LBL_PLATE_H * 0.5 - _LBL_TEXT_DX - (_LBL_LINE_GAP if l == lv else 0.0))
		root.add_child(l)

## 조각 데이터의 원작 네임택 필드(`label_pos`/`label_align`/`label_color`/`label_special`)로
## 판을 그린다. 좌표가 없거나(동굴 등 원작 미표시 항목) 지역에 `coord.label` 어파인이 없으면
## `false` 를 돌려줘 호출부가 조각 기준 폴백을 쓰게 한다.
##
## `coord.label` 은 `coord.layer` 와 **별도 어파인**이다 — layer 쪽은 initBG 의 bbox **최소corner**
## 를 조각 중심으로 오인해 맞춘 값이고(구름·발광점이 그 값 + design_offset 으로 눈맞춤 완료라
## 건드리지 않는다), label 쪽은 bbox **중심**으로 다시 맞췄다. 근거·잔차 = 데이터의 `_basis`.
func _field_label(p: Dictionary, coord: Dictionary, bg_design: Vector2, bg_tex: Vector2,
		S: float) -> bool:
	if not p.has("label_pos"):
		return false
	var L: Dictionary = coord.get("label", {})
	if L.is_empty():
		return false
	var lp: Array = p["label_pos"]
	var ls := float(L.get("s", 0.75))
	var bgpx := Vector2(ls * float(lp[0]) + float(L.get("tx", 0.0)),
		-ls * float(lp[1]) + float(L.get("ty", 0.0)))
	var d := bg_design + (bgpx - bg_tex) * S
	# 어파인 잔차(조각 실측중심 ↔ 원작 bbox 중심이 강체 대응이 아니다)를 눈으로 메우는 데이터 노브.
	var off: Array = p.get("label_offset", [0.0, 0.0])
	d += Vector2(float(off[0]), float(off[1]))
	# 원작 색 인자는 두 형태다 — 유타칸은 `GetColor(enum)`, 엘프/드워프/우노는 리터럴 ccColor3B.
	var c = p.get("label_color", 0)
	var col := Color(String(c)) if typeof(c) == TYPE_STRING else worldmap_label_color(int(c))
	_field_plate(String(p.get("label", "")), int(p.get("label_level", 0)), col,
		bool(p.get("label_special", false)), d, int(p.get("label_align", 0)))
	return true

## 조각 기준 폴백 라벨(원작 절대좌표가 없는 항목 = 동굴·시설·자작 지역맵).
## 판은 같은 원본 프레임으로 그리고 위치만 조각 위로 올린다.
func _map_label(text: String, px: float, py: float, frame: String, pscale: float, man := {}) -> void:
	if text == "":
		return
	var fh: float = float(man.get(frame, {}).get("h", 100)) if not man.is_empty() else _fh(frame)
	_field_plate(text, 0, Color.WHITE, false,
		Vector2(px, maxf(_LBL_PLATE_H * 0.5 + 6.0, py - fh * pscale * 0.5 - 22.0)))

## 리스트형(pos 없는 지역 폴백): 세로 지그재그.
func _build_region_list(region_id: String, region: Dictionary, nodes: Array) -> void:
	var vis := _vis()
	var cx := vis.x * 0.5
	var y := 150.0
	var step := 200.0
	var i := 0
	for nd in nodes:
		var zig := 120.0 if (i % 2 == 0) else -120.0
		var thumb := _sprite(String(nd.get("frame", "")), 0.8)
		if thumb:
			thumb.position = Vector2(cx + zig, y)
			_content.add_child(thumb)
		var lbl := Label.new()
		lbl.text = "%d. %s" % [i + 1, String(nd.get("label", ""))]
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.add_theme_color_override("font_color", Color(0.25, 0.18, 0.08))
		lbl.position = Vector2(cx + zig - 70, y + 60)
		_content.add_child(lbl)
		var fw := _fw(String(nd.get("frame", "")))
		var fh := _fh(String(nd.get("frame", ""))) * 0.8
		_add_hit(Rect2(cx + zig - fw * 0.4, y - fh * 0.5, fw * 0.8, fh + 30), "node", String(nd.get("target", "")))
		y += step
		i += 1
	if nodes.is_empty():
		var note := Label.new()
		note.text = "(노드 데이터 미작성 — %s)" % region_id
		note.add_theme_color_override("font_color", Color(0.3, 0.2, 0.1))
		note.position = Vector2(cx - 200, 300)
		_content.add_child(note)
	_max_scroll = maxf(0.0, y - _vis().y + 60.0)

# ---------- 스크롤/입력 (지역맵=가로, 개요/리스트=세로) ----------
func _set_content_height(h: float) -> void:
	_max_scroll = maxf(0.0, h - _vis().y + 60.0)

func _apply_scroll() -> void:
	if not _content: return
	_content.position = Vector2(-_scroll, 0) if _horizontal else Vector2(0, -_scroll)
	# 원작 `WorldMapLayer::callbackMapMove` 도 스크롤이 끝날 때마다 setWorldMapSound 를 부른다.
	_update_area_sounds()

func _gui_input(event: InputEvent) -> void:
	if _busy:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_press_pos = event.position; _moved = false
			_scroll_vel = 0.0   # 새 드래그 시작 → 관성 정지
		elif not _moved:
			_try_click(event.position)
	elif event is InputEventMouseMotion and _dragging:
		if event.position.distance_to(_press_pos) > 6.0: _moved = true
		var delta: float = event.relative.x if _horizontal else event.relative.y
		_scroll = clampf(_scroll - delta, 0.0, _max_scroll)
		_scroll_vel = delta   # 마지막 이동량=놓을 때의 관성 속도
		_apply_scroll()

## 원작 deaccelerateScrolling(관성 스크롤) + showCloud(구름 드리프트).
func _process(dt: float) -> void:
	# 구름 흐름 — 원작 `CCMoveBy(dur, (10,0))` + RepeatForever = **콘텐츠 안에서 오른쪽으로** 흐른다.
	# (종전엔 화면 고정 CanvasLayer 위를 흘렀다 — 스크롤해도 구름이 따라와 맵을 가렸다.)
	if not _clouds.is_empty():
		for c in _clouds:
			var n = c["node"]
			if not is_instance_valid(n): continue
			n.position.x += float(c["speed"]) * dt
			var cw := float(c["w"])
			if n.position.x - cw * 0.5 > float(c["wrap"]):
				n.position.x = -cw * 0.5
	# 관성 스크롤 감속
	if _dragging or _busy or absf(_scroll_vel) < 1.0:
		return
	_scroll = clampf(_scroll - _scroll_vel, 0.0, _max_scroll)
	_apply_scroll()
	_scroll_vel *= 0.90   # 프레임당 감쇠
	if _scroll <= 0.0 or _scroll >= _max_scroll:
		_scroll_vel = 0.0   # 끝에 닿으면 정지(바운스 없음)

## 원작 setScenarioMark(오프라인 재해석): 온라인 시나리오 대신 **진행도 기반 "다음 목표" 마커**.
## 현 지역 battle 던전 중 미클리어(get_progress "cleared_<id>")면서 레벨 최저인 던전에 펄스 "!" 마커.
## 🔴 표시 조건(2026-07-29 사용자 지적 "스토리 전용 마커인데 상시 뜨고 있다").
##
## 원작은 `WorldMapScene::getScenarioMark` 이 **시나리오 단계 → 필드번호**를 돌려주고
## 0 이면 마커를 아예 안 만든다(`WorldMapLayer.c:2639` 호출부 6곳 전부 `if (iVar != 0)`).
## 그 매핑은 `ScenarioManager` 의 진행 상태(+0x168 회차 / +0x16c 서브단계)로 100줄 넘게
## 분기하는 표인데, **그 흐름데이터가 서버 유실분**이다([[dv2-story-scenario-recovery]] —
## 대사 5,029줄은 살아 있고 ScenarioScript 흐름만 없다). 회차↔필드 연결도 복원 불가다:
## `data/story.json` 의 `submission` 16건 중 던전 이름을 담은 건 2건뿐이라 매칭 근거가 안 된다.
##
## ⇒ **오프라인 재해석(ASSUMPTION)**: "지금 볼 수 있는 스토리 회차가 남아 있다" = 진행 중인
##    스토리 목표가 있다고 보고, 그때만 마커를 띄운다. 가리키는 곳은 종전대로 미클리어 최저레벨
##    던전. 전부 봤거나 다음 회차가 아직 안 열렸으면 **마커 없음**(원작의 `iVar == 0` 자리).
##    해금 규칙은 logic 층(`StoryQuest`)이 갖는다 — 여기선 판정만 쓴다.
##
## 🔴 2026-07-30 정정: 위 "회차↔필드 연결 복원 불가"는 **오진이었다.** 원작
##    `ScenarioSubQuestData::getScenarioSubQuestFiled` 가 회차별 던전을 하드코딩으로 들고 있고
##    (회차 79~145, 32건) 추출해 `data/story_subquest.json` 에 넣었다. 그 회차가 진행 중이면
##    **정확한 던전**을 가리킬 수 있다(아래 `_mark_story_field`). 표에 없는 회차만 종전 추정이다.
func _story_objective_active() -> bool:
	var no := StoryProgress.next_episode()
	if no <= 0 or StoryProgress.seen(no):
		return false   # 구현된 전 회차 관람 완료 → 목표 없음
	return StoryProgress.unlocked(no) or StoryProgress.spec(no).size() > 0

func _mark_objective(battle_nodes: Array, S := 0.72) -> void:
	if not _story_objective_active():
		return   # 원작 getScenarioMark == 0 자리 — 진행 중인 스토리 목표가 없다
	# 목표 조각은 원작 `getScenarioMark(false)`가 반환한 정확한 field만 쓴다.
	var best: Dictionary = _story_field_node(battle_nodes)
	if best.is_empty():
		return
	var d: Vector2 = best["d"]
	# 조각 **아트 위쪽**에 띄운다. 종전엔 조각 중심에서 고정 −54 라 큰 조각(불의 산 172px)에서는
	# 마커가 산 한가운데 얹혀 네임택까지 가렸다(사용자 지적 2026-07-29).
	var mh := float(best.get("h", 100.0))
	var by := -(mh * 0.5 + 45.0)
	# 🟠→✅ 원본 프레임으로 교체(2026-07-29). 종전엔 Polygon2D 원·삼각형 + "!" 라벨 **자작**이었다.
	# 원작 `WorldMapLayer::setScenarioMark`(:2682) = `CCSprite("common/event.png")` · setScale(1.5) ·
	# anchor(0.5,0.5) · addChild(z=0x11=17).
	# 🔴 마커는 **원작 레이어 공간**에서 저작됐다 — 스파인 앰비언트와 같은 이유로 지역 축척을
	#    함께 곱해야 우리 축소된 맵에서 비율이 맞는다. 레이어pt → 디자인 px = 0.75 × S.
	var ls := 0.75 * S
	var mk := AtlasUI.spr("common_ui", "common_event", _MARK_SCALE * Design.ASSET_SCALE * ls)
	if mk == null:
		return
	mk.position = d + Vector2(0, by)
	mk.z_index = 20   # 조각·네임택(z40)보다는 아래, 지형보다는 위
	_content.add_child(mk)
	_mark_bounce(mk, d.y + by, ls)
	# ② 원작 `WorldMapLayer::setScenarioNotification`(:3494) 의 안내 화살표(z=0x12, tag 0x1d2).
	#
	# 🟦 프레임은 **황금색 `scene/worldmap/event_arrow`**(17×14, #EEBB22 — 사용자 확정 2026-07-31).
	#    디컴프가 부르는 것은 빨간 `storyguide_arrow`(13×10, 순수 #FF0000)지만, `event_arrow` 도
	#    같은 아틀라스에 실재하고 디컴프 397클래스 전수 grep 에 **호출자가 없다**(바이너리
	#    문자열로만 존재) ⇒ 코드 근거로는 어느 쪽도 확정 불가라 사용자 원작 기억을 따른다.
	#    ! 배지(`common/event.png`)도 금색이라 색이 맞는다. 근거가 생기면 이 키 한 줄만 되돌린다.
	#
	# 크기·안무는 원작 리터럴 그대로 — `setScale(2.0)` 뒤 무한반복:
	#    Spawn(ScaleTo 0.7→1.8, MoveBy 0.7 (0,−20))  →  Spawn(ScaleTo 0.7→2.0, MoveBy 0.7 (0,+20))
	# cocos y-up 의 −20 은 디자인(y-down)에서 +20 ⇒ **쉬는 자리가 궤적의 맨 위**다.
	#
	# ⚠️ 위치만 원작 리터럴(필드 좌표 +105)을 못 쓴다 — 우리 지역맵은 0.72 로 축소돼 있어
	#    그대로 넣으면 배지 **안**으로 파고든다(2026-07-31 이전 판의 실제 증상: 배지에 겹쳐
	#    자작 UI 처럼 보였다). 배지·화살표의 실측 높이와 **양쪽 바운스 진폭**에서 여유를 만든다.
	var ar := AtlasUI.spr("worldmap_ui", "scene_worldmap_event_arrow",
		_ARROW_SCALE * Design.ASSET_SCALE * ls)
	if ar != null:
		# 배지 윗변(제 바운스로 최대 40pt 더 올라간다) ↔ 화살표 아랫변(제 바운스로 20pt 내려간다).
		var mk_h := AtlasUI.size_pt("common_ui", "common_event").y * _MARK_SCALE * ls
		var ar_h := AtlasUI.size_pt("worldmap_ui", "scene_worldmap_event_arrow").y * _ARROW_SCALE * ls
		var gap := (mk_h + ar_h) * 0.5 + (40.0 + 20.0 + 4.0) * ls   # 4pt = 눈으로 남기는 여백
		var ay := d.y + by - gap
		ar.position = Vector2(d.x, ay)
		ar.z_index = 21
		_content.add_child(ar)
		_arrow_bounce(ar, ay, ls)

## 진행 회차의 서브퀘스트 던전에 해당하는 조각 — 원작
## `WorldMapLayer::setScenarioNotification`(:3164) 이 `getScenarioSubQuestFiled(sn_s, isNight)` 로
## 고르는 그 필드다. 이 지역에 없거나 표에 없는 회차면 {}.
func _story_field_node(battle_nodes: Array) -> Dictionary:
	var want := StoryProgress.mark_field()
	if want <= 0:
		return {}
	for bn in battle_nodes:
		var st: Dictionary = Data.stage(String(bn["stage"]))
		if DungeonBG.base_field(DungeonBG.field_id(st)) == want:
			return bn
	return {}

## 원작 마커 안무 — `setScenarioMark` :2696~2738 그대로.
## `CCRepeatForever(CCSequence(...))`, 각 단계 0.5초, 이동과 확대가 **동시**(`CCSpawn`):
##   +40 EaseExponentialOut / ScaleTo 1.5+0.3   →  −40 EaseBounceOut / ScaleTo 1.5
##   +20 EaseExponentialOut / ScaleTo 1.5+0.2   →  −20 EaseBounceOut / ScaleTo 1.5
##   +10 EaseExponentialOut / ScaleTo 1.5+0.1   →  −10 EaseBounceOut / ScaleTo 1.5
##   → CCDelayTime(0.5)
## `MoveBy` 는 상대·누적이라 +40/−40 이 원위치로 돌아온다 ⇒ 절대 목표로 풀어 쓴다.
## cocos y-up 의 +40 은 디자인(y-down)에서 −40.
const _MARK_SCALE := 1.5      # 원작 setScale(0x3fc00000)
const _MARK_STEPS := [        # [디자인 y 오프셋, 배율 가산, 올라가는 단계인가]
	[-40.0, 0.3, true], [0.0, 0.0, false],
	[-20.0, 0.2, true], [0.0, 0.0, false],
	[-10.0, 0.1, true], [0.0, 0.0, false],
]
func _mark_bounce(spr: Sprite2D, base_y: float, ls := 0.54) -> void:
	var s0 := _MARK_SCALE * Design.ASSET_SCALE * ls
	var tw := spr.create_tween().set_loops()
	for st in _MARK_STEPS:
		var up: bool = bool(st[2])
		# 이동량도 레이어 pt 라 같은 배율을 곱한다.
		var mv := tw.tween_property(spr, "position:y", base_y + float(st[0]) * ls, 0.5)
		mv.set_trans(Tween.TRANS_EXPO if up else Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		var sc := s0 * (1.0 + float(st[1]) / _MARK_SCALE)
		tw.parallel().tween_property(spr, "scale", Vector2(sc, sc), 0.5)
	tw.tween_interval(0.5)

## 안내 화살표 안무 — 원작 `setScenarioNotification` :3496~3506 그대로.
##   RepeatForever(Sequence(
##     Spawn(ScaleTo(0.7, 1.8), MoveBy(0.7, (0,−20))),
##     Spawn(ScaleTo(0.7, 2.0), MoveBy(0.7, (0,+20)))))
## `setScale(2.0)` 이 기본이라 1.8 로 **줄면서 내려갔다가** 2.0 으로 돌아온다.
## `_mark_bounce` 와 달리 이징 지정이 없다 = cocos 기본 선형.
const _ARROW_SCALE := 2.0     # 원작 setScale(0x40000000)
const _ARROW_DIP := 20.0      # MoveBy (0,−20) → 디자인 y-down 에서 +20
const _ARROW_DIP_SCALE := 1.8
func _arrow_bounce(spr: Sprite2D, base_y: float, ls := 0.54) -> void:
	var s0 := _ARROW_SCALE * Design.ASSET_SCALE * ls
	var s1 := _ARROW_DIP_SCALE * Design.ASSET_SCALE * ls
	var tw := spr.create_tween().set_loops()
	tw.tween_property(spr, "position:y", base_y + _ARROW_DIP * ls, 0.7)
	tw.parallel().tween_property(spr, "scale", Vector2(s1, s1), 0.7)
	tw.tween_property(spr, "position:y", base_y, 0.7)
	tw.parallel().tween_property(spr, "scale", Vector2(s0, s0), 0.7)

## 원작 showImp: 맵을 배회하는 임프(golden imp). adventure_ui/imp_pack 스프라이트 재활용.
## 좌우로 걸으며 방향전환 시 좌우반전, 잔잔한 상하 바운스. amanta/aida는 전용 스프라이트 부재 → 임프만.
## 원작 ani_wonder: 월드맵 배회 상인 NPC(스파인, DV2/480서 변환). 좌우 왕복 보행.
func _build_wander_wonder() -> void:
	if not ResourceLoader.exists("res://scenes/npc/wonder.tscn"):
		return
	var vis := _vis()
	var y := FLOOR * 0.56
	var x0 := vis.x * 0.55
	var x1 := vis.x * 0.80
	var holder := Node2D.new()
	holder.position = Vector2(x0, y)
	holder.scale = Vector2(0.5, 0.5)
	holder.z_index = 5
	_content.add_child(holder)
	var inst = (load("res://scenes/npc/wonder.tscn") as PackedScene).instantiate()
	holder.add_child(inst)
	var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap:
		var anims := ap.get_animation_list()
		if anims.size() > 0:
			ap.get_animation(anims[0]).loop_mode = Animation.LOOP_LINEAR
			ap.play(anims[0])
	var sx: float = absf(holder.scale.x)
	var tw := holder.create_tween().set_loops()
	tw.tween_property(holder, "position:x", x1, 5.0)
	tw.tween_callback(func(): if is_instance_valid(holder): holder.scale.x = -sx)
	tw.tween_interval(0.4)
	tw.tween_property(holder, "position:x", x0, 5.0)
	tw.tween_callback(func(): if is_instance_valid(holder): holder.scale.x = sx)
	tw.tween_interval(0.4)

func _build_wander_imp() -> void:
	var man := _load_manifest("adventure_ui")
	if not man.has("scene_adventure_imp_pack"):
		return
	var imp := _sprite_native("scene_adventure_imp_pack", "adventure_ui", man, 0.55)
	if not imp:
		return
	var vis := _vis()
	var y := FLOOR * 0.7
	var x0 := vis.x * 0.36
	var x1 := vis.x * 0.60
	imp.position = Vector2(x0, y)
	imp.z_index = 6
	_content.add_child(imp)
	var sx: float = absf(imp.scale.x)
	# 좌우 왕복 보행(끝에서 좌우반전)
	var tw := imp.create_tween().set_loops()
	tw.tween_property(imp, "position:x", x1, 3.2)
	tw.tween_callback(func(): if is_instance_valid(imp): imp.scale.x = -sx)
	tw.tween_interval(0.3)
	tw.tween_property(imp, "position:x", x0, 3.2)
	tw.tween_callback(func(): if is_instance_valid(imp): imp.scale.x = sx)
	tw.tween_interval(0.3)
	# 걷는 느낌의 상하 바운스(병렬)
	var tb := imp.create_tween().set_loops()
	tb.tween_property(imp, "position:y", y - 5.0, 0.35).set_trans(Tween.TRANS_SINE)
	tb.tween_property(imp, "position:y", y, 0.35).set_trans(Tween.TRANS_SINE)

# ── 하늘 구름 — 원작 `WorldMapLayer::showCloud` @01af5824 ────────────────────
#
# 🔴 2026-07-29 재이식. 종전엔 화면 고정 `CanvasLayer(layer=1)` 에 랜덤 위치로 띄웠다 —
#    그래서 구름이 **맵·던전 조각 위를 지나며 화면을 가렸다.** 원작은
#    `addChild(node)`(vtable +0x188) = **z 기본값 0** 으로 붙이는데, 맵 배경과 조각은
#    `addChild(node, 10)` 이다 ⇒ 구름은 **섬 뒤(하늘)** 를 지나간다.
#
# 좌표도 랜덤이 아니라 고정 5개다(원작 리터럴, 레이어 포인트 y-up):
#   (100,1020) (1500,1050) (400,1080) (1200,1100) (300,1120)
# ⚪ 프레임 번호(`ani_cloud%02d`)와 이동 시간은 데이터 테이블(`DAT_022c4cf0`/`DAT_022c4d04`)에
#    들어 있어 디컴프에 값이 안 잡혔다 → 번호는 01~05 순차, 속도는 우리 값. # ASSUMPTION
# ⚪ 밤에는 아예 만들지 않는다(사용자 원작 확인 2026-07-29). 호출부에서 건다.
const _CLOUD_POS := [
	[100.0, 1020.0], [1500.0, 1050.0], [400.0, 1080.0], [1200.0, 1100.0], [300.0, 1120.0],
]

func _build_clouds(coord: Dictionary, bg_design: Vector2, bg_tex: Vector2, S: float,
		map_w: float) -> void:
	var man := _load_manifest("worldmap_ui")
	if man.is_empty():
		return
	var rng := RandomNumberGenerator.new(); rng.randomize()
	for i in _CLOUD_POS.size():
		var nm := "scene_worldmap_ani_cloud%02d" % (1 + i)
		if not man.has(nm):
			continue
		var spr := _sprite_native(nm, "worldmap_ui", man, S)
		if spr == null:
			continue
		var p: Array = _CLOUD_POS[i]
		var r := _layer_to_design(coord, bg_design, bg_tex, S,
			Vector2(float(p[0]), float(p[1])))
		if not bool(r[1]):
			spr.queue_free()
			continue
		spr.position = r[0]
		spr.modulate.a = 0.85
		spr.z_index = _Z_CLOUD
		_backdrop.add_child(spr)   # 섬(배경·조각)보다 뒤 — 변형 하늘 위, 지형 아래
		_clouds.append({"node": spr, "speed": rng.randf_range(7.0, 18.0),
			"w": float(man.get(nm, {}).get("w", 120)) * S, "wrap": map_w})

## 🔴 2026-07-31 (사용자 지적: "눈에 보이는 조각을 눌러도 무반응이거나 해골 요새로 간다").
##
## 원인은 이번 기능이 아니라 **히트 판정 방식 자체**였다. 조각 히트박스가 프레임의 통짜
## 바운딩박스(투명 여백 포함)라 유타칸에서만 **19쌍이 겹치고**, 겹치면 `_hits` 배열에서
## 먼저 나오는 것이 무조건 이겼다 — 혼돈의 틈새(8)는 해골 요새(6)가 18%, 수중동굴(9)이 15%를
## 덮고 둘 다 배열에서 앞이라 그쪽으로 끌려갔다. 반대로 여백을 누르면 아무 데도 안 맞았다.
##
## 원작은 이렇게 하지 않는다 — `WorldMapBG::create(fieldNo, frame, A, B)` 가 조각마다
## **명시적 터치 사각형(A=좌하, B=우상)** 을 들고 있고, 그 14개는 서로 **거의 안 겹친다**
## (실측: 91조합 중 2건, 그나마 17×75 / 158×28px). 우리는 그 좌표계를 우리 배경 아틀라스
## 공간으로 옮길 검증된 어파인이 없어(자기참조 함정) 사각형을 그대로 못 쓴다.
##
## ⇒ 같은 결과를 **더 튼튼하게** 얻는 방식으로 바꿨다:
##   1. 사각형은 후보를 추리는 데만 쓴다(값싼 프리필터).
##   2. 후보 중 **그 지점에 실제로 불투명 픽셀이 있는** 조각을 고른다 = "보이는 것을 누른다".
##      여러 개면 **나중에 그려진 것**(위에 있는 것)이 이긴다.
##   3. 불투명한 게 하나도 없으면(여백을 눌렀다) 중심이 **가장 가까운** 후보로 폴백한다 —
##      무반응보다 낫고, 겹침 순서와 무관하게 결정적이다.
## 드래그 보정은 원래부터 정상이다(`content = screen + _scroll`, `_content.position.x = -_scroll`).
func _try_click(screen_pos: Vector2) -> void:
	var content_pos := (Vector2(screen_pos.x + _scroll, screen_pos.y) if _horizontal
		else Vector2(screen_pos.x, screen_pos.y + _scroll))
	var pick := _resolve_click(content_pos)
	if pick.is_empty():
		return
	# 지역맵 던전은 입장 전 클로즈업 연출. 그 외(개요 지역 선택 등)는 즉시.
	if _horizontal and pick.has("center"):
		_closeup_then_goto(String(pick["arg"]), pick["center"])
	else:
		_on_hit(String(pick["kind"]), String(pick["arg"]))

## content 좌표 → 어느 히트 항목인가. **부작용 없음**(검수 도구가 이 함수만 부른다).
func _resolve_click(content_pos: Vector2) -> Dictionary:
	var cands: Array = []
	for h in _hits:
		if (h["rect"] as Rect2).has_point(content_pos):
			cands.append(h)
	if cands.is_empty():
		return {}
	var pick: Dictionary = {}
	if cands.size() > 1:
		# (2) 불투명 픽셀이 있는 것 중 **마지막**(= 가장 위에 그려진 것).
		for h in cands:
			if _opaque_at(h, content_pos):
				pick = h
		if pick.is_empty():
			# (3) 폴백 — 중심이 가장 가까운 것.
			var best := INF
			for h in cands:
				var c: Vector2 = h.get("center", (h["rect"] as Rect2).get_center())
				var dd := c.distance_squared_to(content_pos)
				if dd < best:
					best = dd; pick = h
	else:
		pick = cands[0]
	return pick

## 그 히트 항목의 조각 스프라이트가 `content_pos` 에서 불투명한가.
## 스프라이트를 안 들고 있는 항목(리스트 뷰·시설 등)은 판정 대상이 아니므로 false.
const _ALPHA_HIT := 0.35
var _img_cache: Dictionary = {}      # 텍스처 RID → Image (조각마다 매번 굽지 않게)
func _opaque_at(h: Dictionary, content_pos: Vector2) -> bool:
	var spr = h.get("spr")
	if not (spr is Sprite2D) or not is_instance_valid(spr):
		return false
	var s := spr as Sprite2D
	var tex := s.texture
	if tex == null:
		return false
	# content → 스프라이트 로컬 → 텍스처 픽셀(중앙 정렬 + 균일 스케일 전제).
	var sc: float = maxf(0.0001, s.scale.x)
	var local := (content_pos - s.position) / sc
	var size := tex.get_size()
	var px := local + size * 0.5
	if px.x < 0.0 or px.y < 0.0 or px.x >= size.x or px.y >= size.y:
		return false
	var at := tex as AtlasTexture
	var base: Texture2D = at.atlas if at != null else tex
	if base == null:
		return false
	var key := base.get_rid()
	if not _img_cache.has(key):
		var im := base.get_image()
		if im == null:
			return false
		if im.is_compressed():
			im.decompress()
		_img_cache[key] = im
	var img: Image = _img_cache[key]
	if at != null:
		px += at.region.position
	var ix := int(px.x)
	var iy := int(px.y)
	if ix < 0 or iy < 0 or ix >= img.get_width() or iy >= img.get_height():
		return false
	return img.get_pixel(ix, iy).a >= _ALPHA_HIT

func _on_hit(kind: String, arg: String) -> void:
	if kind == "region":
		_mode = arg; _rebuild()
	elif kind == "node":
		_goto_target(arg)

## 던전 클릭 → 해당 조각으로 줌인(클로즈업). center=content(로컬) 좌표.
## 던전(battle:)은 원작처럼 **클릭 즉시** 팝업이 뜬다 — 필드 연출(setMapAnimation)·효과음·
## 줌·팝업 슬라이드가 동시에 시작한다(2026-07-29 사용자 검수: 종전 1.05초 지연은 자작).
## 마을/시설 등 씬 전환 타깃만 줌이 끝난 뒤 이동한다.
func _closeup_then_goto(target: String, center: Vector2) -> void:
	if _busy:
		return
	_busy = true
	_dragging = false
	# 던전 노드가 화면 왼쪽 절반이면 팝업은 오른쪽에 도킹(원작 getDirection → show(bool)).
	var sx := center.x - (_scroll if _horizontal else 0.0)
	_popup_side = "right" if sx < _vis().x * 0.5 else "left"
	var is_battle := target.begins_with("battle:")
	if is_battle:
		# 원작 setMapAnimation — 필드를 누른 그 순간 연출+효과음이 뜬다.
		_play_field_fx(int(target.substr(7)))
		# 진입 불가(밤의 빛의 탑 등)면 줌하지 않는다.
		if not _goto_target(target):
			return
	var vis := _vis()
	var zoom := 2.2
	# 클릭한 조각을 화면 중앙에 두고 zoom배 확대(배경·이웃 조각 함께 줌).
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_content, "scale", Vector2(zoom, zoom), 0.55)
	tw.parallel().tween_property(_content, "position", vis * 0.5 - center * zoom, 0.55)
	if not is_battle:
		tw.tween_interval(0.5)
		tw.tween_callback(func(): _goto_target(target))

## 반환 = 실제로 이동/팝업이 열렸는가(false = 진입 불가 안내만 하고 끝 — 호출자가 줌을 접는다).
func _goto_target(target: String) -> bool:
	if target.begins_with("town:"):
		# 카데스의 공간에서는 마을에 들어갈 수 없다(사용자 확정 2026-07-29 — 빛의 탑과 같은 취급).
		# ⚠️ 원작 문자열이 없다(`WorldmapAdventureMsg1/2` 는 빛의 탑 전용) → 문구는 우리 작문이다.
		#    실제로 마을엔 카데스 아트가 없어 들어가면 낮/밤 마을이 그대로 나온다.
		if _mode == "yutakan" and _yutakan_phase(_region_native()) == "kades":
			_notice("카데스의 공간에서는 마을에 들어갈 수 없습니다.")
			_busy = false
			return false
		Scenes.goto("town", {"area": target.substr(5)})
	elif target == "cave":
		Scenes.goto("cave")
	elif target.begins_with("battle:"):
		# 던전 입장: 원작은 클릭 시 **던전 정보 팝업**(WorldMapPopupLayer)이 뜬다.
		# 거기서 일반/영웅을 고르면 출전 드래곤 선택(Select3DragonsLayer) → adventure.
		var sid := target.substr(7)
		if _open_marked_story(sid):
			return true
		# 밤에는 빛의 탑(필드 15) 진입 불가 — 원작 문자열 `WorldmapAdventureMsg1`.
		if _mode == "yutakan" and sid == "15" and _yutakan_phase(_region_native()) == "night":
			_notice("밤에는 빛의 탑에 진입할 수 없습니다.")
			_busy = false
			return false
		# 카데스의 공간에서도 빛의 탑은 막힌다 — 위키 dungeon_1.pdf §2
		# "카오스 피어 레이드 할 때 제외하고 빛의 탑에 진입할 수 없다."
		# (카오스 피어 = 월드레이드 = ⚫오프라인 CUT 이므로 우리는 항상 막는다.)
		if _mode == "yutakan" and sid == "15" \
				and bool(Data.kades.get("light_tower_blocked", false)) \
				and _yutakan_phase(_region_native()) == "kades":
			_notice("카데스의 공간에서는 빛의 탑에 진입할 수 없습니다.")
			_busy = false
			return false
		_open_dungeon_popup(_variant_stage_id(sid))
	elif target == "battle":
		Scenes.goto("battle", {})   # 기본 스텁 전투(탐험 없이)
	elif target == "mamorudiclab":
		# 원작 WorldMapUnoLayer::ccTouchOne — tag 0x22(마모루딕 스파인) 안이면
		# hidePopup() 후 MamorudicLab::scene() 을 pushScene.
		Scenes.goto("mamorudiclab", {"from": "worldmap"})
	else:
		push_warning("[WorldMap] 미지원 타깃: " + target)
		return false
	return true

## 원작 WorldMapScene::setScenario는 마커 필드를 선택하면 makeScenarioLayer(-1,false)를
## 표시한다. 999/1002+는 던전이 아닌 특수 이벤트 코드이므로 여기서 처리하지 않는다.
func _open_marked_story(stage_id: String) -> bool:
	var no := StoryProgress.active_episode()
	if no <= 0 or StoryProgress.seen(no) or not StoryProgress.unlocked(no):
		return false
	if Data.scenario_flow_of(no).is_empty():
		return false
	var want := StoryProgress.mark_field()
	if want <= 0 or want >= 999:
		return false
	var st: Dictionary = Data.stage(stage_id)
	if st.is_empty() or DungeonBG.base_field(DungeonBG.field_id(st)) != want:
		return false
	Scenes.goto("story", {"no": no, "part": 0, "back": "worldmap",
		"back_params": {"region": _mode}})
	return true

# ---------- HUD ----------
## 메인 화면 상시 HUD = `MainHud`(원작 `TownMainMenuLayer::setMenu` 이식 — 좌상단 프로필/상태창,
## 우상단 재화 + 충전, 하단 구판 아이콘 메뉴바). 여기서는 월드맵 고유분만 얹는다:
##   · 지역 뷰 → 개요로 돌아가는 back
##   · 원작 GuideLayer 진입
## 🔴 종전에는 이 함수가 자작 `Button` 3개(둥지/가이드/제목)로 전부를 대신했다.
func _build_hud() -> void:
	MainHud.attach(self, _variant_toggles, _yutakan_phase(_region_native()))
	var hud := CanvasLayer.new()
	hud.layer = 11
	add_child(hud)
	if _mode != "overview":
		var back := Button.new()
		back.text = "← 월드맵"
		back.position = Vector2(20, _vis().y * 0.5 - 20.0)
		back.pressed.connect(func(): _mode = "overview"; _rebuild())
		hud.add_child(back)
	# 원작 GuideLayer 진입(게임 가이드). 재화 표시(우상단)를 피해 그 아래에 둔다.
	var gd := Button.new(); gd.text = "가이드"; gd.size = Vector2(72, 34)
	gd.position = Vector2(_vis().x - 90, 70)
	gd.pressed.connect(_open_guide); hud.add_child(gd)
	# (임프상인 진입은 HUD 버튼이 아니라 **지도 위 스파인**이다 — `_add_imp_shop`,
	#  원작 `WorldMapLayer::showImp` tag 0x21.)

# ---------- helpers ----------
## 현재 지역의 native 배치 dict(밤/카데스 판정용). 개요 화면이면 {}.
func _region_native() -> Dictionary:
	if _mode == "overview":
		return {}
	return _region(_mode).get("native", {})

## 유타칸 밤/카데스가 켜져 있으면 던전 필드 id 를 변형본(500+/600+)으로 바꾼다.
## 규칙은 `DungeonBG.variant_field` = 원작 `WorldMapPopupLayer::init` 축자.
## 변형이 없는 필드(해적 소굴 6 · 혼돈의 틈새 8 · 15 이상 · 엘프/드워프)는 그대로 둔다.
func _variant_stage_id(stage_id: String) -> String:
	if _mode != "yutakan" or not stage_id.is_valid_int():
		return stage_id
	var nat := _region_native()
	return str(DungeonBG.variant_field(int(stage_id),
		_is_yutakan_night(nat), _is_kades_space(nat)))

## 간단 안내 배너(원작 GameManager::showToast 대체). 2초 뒤 사라진다.
# ---------- 하루 1회 던전 ----------
## 원작 우노 던전(검은 섬·미지의 터)은 **하루 1회**이고, 초과 입장은 다이아 50 이다
## (위키 dungeon_4.pdf §4: "하루에 한번씩 할 수 있으며, 이를 무시하고 한 번 더하려면
##  50 다이아를 지불해야 한다"). 횟수는 원작에서 서버가 셌다 — 유실이라 **로컬 날짜 도장**으로
## 대체한다(`UserDB` pmeta `daily_dungeon` = {스테이지id: "YYYY-MM-DD"}).
## 가격 50 은 위키 확정값이다(자작 아님).
const DAILY_EXTRA_DIA := 50

func _today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]

## 오늘 아직 안 들어갔으면 true.
func _daily_ok(stage_id: String) -> bool:
	var m = UserDB.get_pmeta("daily_dungeon", {})
	if not (m is Dictionary):
		return true
	return String((m as Dictionary).get(stage_id, "")) != _today()

func _daily_stamp(stage_id: String) -> void:
	var m = UserDB.get_pmeta("daily_dungeon", {})
	var d: Dictionary = (m as Dictionary).duplicate() if m is Dictionary else {}
	d[stage_id] = _today()
	UserDB.set_pmeta("daily_dungeon", d)

## 초과 입장 확인 — 다이아를 지불하면 그대로 들어간다(도장은 이미 오늘 자라 다시 찍어도 무의미).
func _confirm_daily_extra(enter: Callable, hero: bool) -> void:
	var vis := _vis()
	var lay := CanvasLayer.new(); lay.layer = 42; add_child(lay)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT); lay.add_child(dim)
	const BW := 480.0
	const BH := 250.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190
	win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH)
	win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	lay.add_child(win)
	var l := Label.new()
	l.text = "오늘은 이미 다녀왔습니다.\n다이아 %d 개를 지불하고\n한 번 더 들어가시겠습니까?" % DAILY_EXTRA_DIA
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(0.3, 0.2, 0.06))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(BW - 60, 100); l.position = Vector2(30, 62)
	win.add_child(l)
	var ok := Button.new(); ok.text = "입장"; ok.size = Vector2(140, 42)
	ok.position = Vector2(BW * 0.5 - 150, BH - 60)
	ok.pressed.connect(func():
		if not UserDB.spend("diamond", DAILY_EXTRA_DIA):
			l.text = "다이아가 부족합니다."
			return
		lay.queue_free()
		enter.call(hero))
	win.add_child(ok)
	var no := Button.new(); no.text = "취소"; no.size = Vector2(140, 42)
	no.position = Vector2(BW * 0.5 + 10, BH - 60)
	no.pressed.connect(func(): lay.queue_free()); win.add_child(no)

## ── 혼돈의 틈새 소환 게이트 ────────────────────────────────────────────────────
## 원작 `WorldMapPopupLayer::getIsExistSomething()`(:1866) 축자 이식.
## 보스가 상주 중이면 true(입장), 아니면 **소환 팝업만 띄우고 false**(원작 return false —
## 소환에 성공해도 그 클릭으로는 들어가지 않는다. 다시 눌러야 입장한다).
## 소환형이 아닌 던전은 항상 true.
## 판정 = `Darknix`(logic). 여기는 팝업·소모·토스트만 한다(§8.2).
func _darknix_gate(st: Dictionary, layer: CanvasLayer) -> bool:
	if not Darknix.is_summon_stage(st):
		return true
	var cfg: Dictionary = st["summon"]
	var now := int(Time.get_unix_time_from_system())
	var g := Darknix.gate(cfg, UserDB.darknix(), now,
		UserDB.item_count(String(cfg.get("item", ""))), UserDB.diamond())
	if String(g.get("action", "")) == Darknix.ENTER:
		return true
	_popup_darknix_summon(cfg, g, layer)
	return false

## 소환 확인 팝업. 원작이 쓰는 문자열 키를 그대로 옮긴다:
##   포탈 보유 → `AdventurePopupUseItem` "{아이템} 아이템을 사용하시겠습니까?" (+ 아이템 아이콘)
##   미보유   → `AdventureChaosDungeonDia` "다이아 N개를 사용해서 혼돈의 틈새를 여시겠습니까?"
##   부족     → `AdventureChaosDungeonNoDia` + 환전(캐시) 탭 안내
## 성공 토스트도 원작 `CaveToastMsg10` 그대로.
func _popup_darknix_summon(cfg: Dictionary, g: Dictionary, src_layer: CanvasLayer) -> void:
	var act := String(g.get("action", ""))
	var vis := _vis()
	var lay := CanvasLayer.new(); lay.layer = 43; add_child(lay)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT); lay.add_child(dim)
	const BW := 500.0
	const BH := 280.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190
	win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH)
	win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	lay.add_child(win)
	var item_key := String(cfg.get("item", ""))
	var price := int(g.get("cash", 0))
	# (match 는 못 쓴다 — GDScript 의 match 패턴은 다른 클래스의 const 를 상수식으로 받지 않는다.)
	var msg := ""
	if act == Darknix.USE_ITEM:
		msg = "%s 아이템을 사용하시겠습니까?" % Data.item_name(item_key)
	elif act == Darknix.USE_CASH:
		msg = "다이아 %d 개를 사용해서\n혼돈의 틈새를 여시겠습니까?" % price
	else:
		msg = "혼돈의 틈새를 소환하는데\n%d 개의 다이아가 필요합니다.\n환전소로 가시겠습니까?" % price
	var l := Label.new()
	l.text = msg
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(0.3, 0.2, 0.06))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(BW - 60, 90); l.position = Vector2(30, 108)
	win.add_child(l)
	# 원작 `PopupTypeLayer::setItem` 자리 — 아이템 경로엔 아이콘, 다이아 경로엔 다이아 프레임.
	var icon: Node2D = null
	if act == Darknix.USE_ITEM:
		icon = _item_icon(item_key, 56.0)
	else:
		icon = AtlasUI.spr("common_ui", "common_diamond_small1", 1.0)
	if icon != null:
		icon.position = Vector2(BW * 0.5, 84.0)
		win.add_child(icon)
	var confirm := Button.new(); confirm.size = Vector2(150, 44)
	confirm.text = "소환" if act != Darknix.NO_CASH else "환전소"
	confirm.position = Vector2(BW * 0.5 - 160, BH - 62)
	confirm.pressed.connect(func():
		lay.queue_free()
		if act == Darknix.USE_ITEM:
			if not UserDB.use_item(item_key, int(g.get("item_count", 1))):
				_notice("고대 포탈이 부족합니다.")
				return
			_do_darknix_summon(cfg, src_layer)
		elif act == Darknix.USE_CASH:
			if not UserDB.spend("diamond", price):
				_notice("다이아가 부족합니다.")
				return
			_do_darknix_summon(cfg, src_layer)
		else:
			Scenes.goto("shop", {"tab": "cash", "from": "worldmap"}))
	win.add_child(confirm)
	var no := Button.new(); no.text = "취소"; no.size = Vector2(150, 44)
	no.position = Vector2(BW * 0.5 + 10, BH - 62)
	no.pressed.connect(func(): lay.queue_free()); win.add_child(no)

## 소환 확정 — 추첨(logic) → 세이브 → 팝업 닫고 맵을 다시 그려 스파인을 띄운다.
## 원작도 `ResponseItemUse`(:732)가 소모 직후 맵 레이어를 갱신해 `showDarknix` 로 들어간다.
func _do_darknix_summon(cfg: Dictionary, src_layer: CanvasLayer) -> void:
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var v := Darknix.roll(cfg, int(Time.get_unix_time_from_system()), rng)
	if v.is_empty():
		_notice("소환에 실패했습니다.")
		return
	UserDB.darknix_summon(v)
	if is_instance_valid(src_layer):
		src_layer.queue_free()          # 던전 팝업을 닫아 스파인이 보이게 한다
	_notice("고대포탈을 사용하여 혼돈의 틈새를 열었습니다.")   # 원작 CaveToastMsg10
	_rebuild()

## 출전할 드래곤 = **동굴에서 선택 중인 그 한 마리**(원작 `AccountManager::getDragonSelected`).
## 다른 드래곤으로 대체하지 않는다 — 원작도 그렇다(아래 `_selected_gate` 근거 참조).
func _selected_dragon() -> Dictionary:
	return UserDB.get_dragon(UserDB.active_uid())

## 선택 중인 드래곤의 출전 검사. 통과면 true, 막히면 **원작 팝업을 띄우고** false.
##
## 원작 `WorldMapPopupLayer::getDragonStatus`(@01b01e34) 축자 — `getDragonSelected()`
## **한 마리만** 검사하고, 0 이 아니면 호출부(:4436)가 `LoadingLayer`/`setAdventure` 를
## 건너뛰고 빠져나간다(= 입장 취소, 다른 드래곤으로 대체하지 않는다).
##
## | 원작 판정 | 반환 | 원작이 부르는 것 |
## |---|---|---|
## | `Dragon::isStun` (회복시각 > 현재) | 1 | `WorldMapScene::setDragonStun` → 다이아 즉시부활 팝업 |
## | `!Dragon::isEnergy` (피로도 0) | 2 | `setDragonEnergy` — **후기판에서 삭제된 시스템**이라 미구현 |
## | `Dragon::isFood` (`food < 1`) | 3 | `setDragonFood` → 먹이 사용 / 상점 이동 팝업 |
## | `Dragon::isBreed` (교배 점유) | 4 | 말풍선 — 우리에 교배 점유 상태가 없다 |
##
## 우리 대응: isStun=`UserDB.is_down` · isFood=`_is_starving`.
## 🔴 2026-07-30: 잠깐 토스트로 막았다가 **원작대로 팝업으로 되돌렸다**(사용자 지시).
func _selected_gate() -> bool:
	var uid := UserDB.active_uid()
	var d := _selected_dragon()
	if uid <= 0 or d.is_empty():
		# 원작도 이 경우만 토스트다 — `WorldMapPopupLayer` :4402 `getLevel(selected) < 1`
		# → `GameManager::showToast(...)` 후 입장 중단(팝업이 아니다).
		_notice("출전할 드래곤을 먼저 선택하세요.")
		return false
	if UserDB.is_down(uid):
		_popup_dragon_stun(uid)
		return false
	if _is_starving(d):
		_popup_dragon_food(uid, d)
		return false
	return true

## 원작 `WorldMapScene::setDragonStun`(@01b1cbec) — 다이아 즉시부활 확인창.
##   메시지 `<CaveDiaBronMsg2>` "회복까지 %1$s남았습니다.\n드래곤을 즉시 부활시키겠습니까?"
##     %1$s = 남은 시간 `%02d:%02d`(1시간 미만) / `%02d:%02d:%02d` → `Incapacitation.remain_clock`
##   `setCash(0, remain/1800 + 1, false)` = 다이아 아이콘 + 소모량 → `Incapacitation.instant_cost`
##   확인 `onClickStun` = 다이아 지불 후 `Dragon::setCureTime(0)` · 취소 `onClickCancel`
## 지불 가능 검사는 원작 `CaveScene.c:8307` · `WorldMapScene.c:558`
## (`remain/0x708 < getCash()`)와 같은 뜻이다 — 표시식 `remain/0x708 + 1`(`CaveScene.c:8218`)과
## 맞물려 `cost <= cash` 를 뜻한다.
func _popup_dragon_stun(uid: int) -> void:
	var now := int(Time.get_unix_time_from_system())
	var ct := UserDB.cure_time(uid)
	var cost := Incapacitation.instant_cost(Data.incapacitation, ct, now)
	var msg := "회복까지 %s 남았습니다.\n드래곤을 즉시 부활시키겠습니까?" \
		% Incapacitation.remain_clock(ct, now)
	PopupType.open(self, "행동불능", msg,
		func():
			if not UserDB.spend("diamond", cost):
				_notice("다이아가 부족합니다.")
				return
			UserDB.set_cure_time(uid, 0)          # 원작 setCureTime(0)
			Bgm.sfx("effect_button")
			_notice("드래곤이 회복되었습니다."),
		"확인", "취소", 0, cost)

## 원작 `WorldMapScene::setDragonFood`(@01b1d0c4) — 먹이 사용 / 상점 이동 확인창.
##   ① `getRace()` 로 속성을 정하고 가방에서 그 속성 먹이(`getType()==0`, `getCount()>0`)를 찾는다
##      → `ItemEffect.find_matching_feed`(logic 층).
##   ② 있으면 `getTypeParam() < 0xb` 로 문구가 갈린다 —
##        `<CaveDragonFoodMsg1>` "…배고픔이 상당히 채워집니다" (전량)
##        `<CaveDragonFoodMsg2>` "…배고픔이 약간 채워집니다"   (절반)
##      확인 `onClickFood` = 그 아이템 사용.
##   ③ 없으면 `<CaveDragonFoodMsg3>` "해당 드래곤이 먹을 수 있는 음식이 없습니다.\n\n
##      상점으로 이동하시겠습니까?" · 확인 `onClickShop` = 상점 이동.
## ⚠️ 원작의 `_Ad_` 변형(드래곤 이름을 넣는 판)은 **탐험 중**(`getAdventureSceneOn`)일 때만
##    쓰인다 — 월드맵에서 뜨는 이 팝업은 이름 없는 기본 판이 맞다.
##    `…11`/`…21`(주황색) 변형은 `getDBYutakanKades()` 분기의 **색만 다른 같은 문구**라 무시한다.
func _popup_dragon_food(uid: int, d: Dictionary) -> void:
	var el := String(Data.get_dragon(int(d.get("id", 0))).get("element", ""))
	var key := ItemEffect.find_matching_feed(UserDB.inventory(), Data.items, el)
	if key == "":
		PopupType.open(self, "먹이", "해당 드래곤이 먹을 수 있는 음식이 없습니다.\n\n상점으로 이동하시겠습니까?",
			func(): Scenes.goto("shop", {"area": "elpis"}), "확인", "취소")
		return
	var nm := Data.item_name(key)
	var much := "상당히" if ItemEffect.feed_is_full(Data.item_effects, key) else "약간"
	PopupType.open(self, "먹이", "%s 아이템을 사용하면\n해당 드래곤의 배고픔이 %s 채워집니다.\n사용하시겠습니까?"
			% [nm, much],
		func(): _feed_dragon(uid, key), "확인", "취소")

## 원작 `onClickFood` — 고른 먹이 1개를 소모해 그 드래곤의 FOOD 를 채운다.
## 회복량 규칙은 `ItemEffect.food_after_feed`(logic 층) — `cave.gd::_use_food` ③ 분기와 같다.
func _feed_dragon(uid: int, key: String) -> void:
	var d := UserDB.get_dragon(uid)
	if d.is_empty() or int(UserDB.inventory().get(key, 0)) <= 0:
		return
	var el := String(Data.get_dragon(int(d.get("id", 0))).get("element", ""))
	var defs: Dictionary = Data.item_effects
	UserDB.add_item(key, -1)
	UserDB.set_dragon_field(uid, "food",
		ItemEffect.food_after_feed(defs, Data.get_item(key), key, el,
			int(d.get("food", ItemEffect.food_max(defs)))))
	Bgm.sfx("effect_button")
	_notice("드래곤이 맛있게 먹이를 먹었습니다.")

## 허기(FOOD)가 0인가 — 원작 `Dragon::isFood`(`food < 1`). 판정은 `ItemEffect`(logic 층).
func _is_starving(d: Dictionary) -> bool:
	return ItemEffect.is_starving(Data.item_effects,
		int(d.get("food", ItemEffect.food_max(Data.item_effects))))

## 지금 들어가려는 곳이 **유타칸 밤 변형**인가. 던전 팝업의 입장 버튼이 이 값을 런에 실어
## 보낸다(`Scenes.goto("adventure", {... "night": _night()})`) — 드랍 풀이 난이도마다 다르다.
## 유타칸이 아닌 지역엔 밤 변형이 없으므로 항상 false(`_variant_stage_id`·`_night_level_ok` 와
## 같은 판정식이다 — 세 곳이 갈라지지 않게 여기 한 곳으로 모은다).
func _night() -> bool:
	return _mode == "yutakan" and _is_yutakan_night(_region_native())

## 유타칸 밤이면 **선택한 드래곤**이 최소 레벨(50)을 만족하는가. 밤이 아니면 항상 참.
## 근거·값 = `data/stages.json` `_variant_rules.night_min_level`(위키 §1.2 + 사용자 확정).
## 대상이 선택 드래곤인 근거 = 원작 문구 `<AdventureNightMinLv>` "**선택한 드래곤의** 레벨이
## 부족하여 진입할 수 없습니다."(보유 전체가 아니다).
##
## 🔴 2026-07-31 (사용자 지적): 요구치 50 을 그대로 쓰면 **밤 던전 12곳이 영구 진입 불가**였다.
##   드래곤 만렙이 45 이기 때문이다(`data/level_curve.json` `cap`). 위키가 적은 "50레벨"은
##   원작 후기판(각성 확장으로 상한이 올라간 뒤)의 값이라 우리 상한과 어긋난다.
##   ⇒ **입장 요구 레벨은 만렙을 넘지 못하게 잘라 쓴다**(사용자 확정: "45레벨 이상의 레벨
##   제한을 가진 던전은 45레벨 이상만 충족하면 입장 가능"). 데이터의 50 은 원작 근거라
##   그대로 두고 여기서만 clamp 한다 — 상한이 올라가면 자동으로 원래 요구치로 돌아간다.
##   각성 상한(50)이 아니라 **기본 상한(45)** 으로 자르는 이유도 같다: 각성 여부와 무관하게
##   45 면 들어갈 수 있어야 한다.
func _night_level_ok() -> bool:
	if not _night():
		return true
	var need := int((Data.stages.get("_variant_rules", {}) as Dictionary).get("night_min_level", 0))
	if need <= 0:
		return true
	need = mini(need, LevelSystem.cap_for(Data.level_curve, false))
	var d := _selected_dragon()
	if d.is_empty():
		return false
	return int(d.get("level", 1)) >= need

## 안내 토스트 — 원작 `GameManager::showToast` @014c193c. 레시피는 `scripts/ui/toast.gd`.
## (2026-07-29 이전엔 여기서 `9patch/popup4` + 갈색 TTF 로 자작했다 — 원작과 다른 물건이었다.)
func _notice(text: String) -> void:
	Toast.show(self, text)

func _region(id: String) -> Dictionary:
	for r in Data.worldmap_regions():
		if String(r.get("id", "")) == id:
			return r
	return {}

func _add_hit(rect: Rect2, kind: String, arg: String) -> void:
	_hits.append({"rect": rect, "kind": kind, "arg": arg})

## 지역맵 던전 히트(클로즈업용 조각 중심 저장).
## `spr` = 그 조각의 스프라이트. 겹친 후보를 가릴 때 **알파로** 판정하는 데 쓴다(`_opaque_at`).
func _add_hit_node(rect: Rect2, target: String, center: Vector2, spr: Sprite2D = null) -> void:
	_hits.append({"rect": rect, "kind": "node", "arg": target, "center": center, "spr": spr})

func _vis() -> Vector2:
	return get_viewport_rect().size

func _fw(frame: String) -> float:
	return float(_manifest.get(frame, {}).get("w", 100))

func _fh(frame: String) -> float:
	return float(_manifest.get(frame, {}).get("h", 100))

func _load_manifest(dir: String) -> Dictionary:
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func _sprite(name: String, scale := 1.0) -> Sprite2D:
	if name == "": return null
	var p := "res://assets/converted/worldmap_maps/%s.tres" % name
	if not ResourceLoader.exists(p): return null
	var s := Sprite2D.new()
	s.texture = load(p)
	s.material = _pma
	# 회전 보정 불필요 — 변환 단계가 흡수(scripts/tools/fix_rotated_frames.py)
	s.scale = Vector2(scale, scale)
	return s

# ---------- 던전 정보 팝업(원작 WorldMapPopupLayer) ----------
## 포팅 카드 = docs/ref/porting/WorldMapPopupLayer.md (원작 좌표·프레임·연출 전부 그 표대로).
## 레퍼런스 = docs/ref/adventure_popup/*.png (2016 방송 캡처 26장).
## 구조: 양피지 `info_bg`(카데스 `info_bg2`) 좌/우 도킹 + 슬라이드 인 → 패널(양피지-80,-20) 위에
##   제목(BMFont subtitle) / 필드 이미지 틀 `info_img_frame(2)` + bg.jpg + 속성 아이콘 /
##   등장 드래곤 줄(`setDragonImage` — 클릭하면 틀 안에 스파인+성급+이름표 미리보기) 또는
##   보상 줄(`setRewardImage` — 우노) / 설명문(`setDesc`) / 입장 버튼(`setCheckOpenField`).
## 데이터: 등장 드래곤·속성·설명문 = data/stages.json `dragons`/`element`/`desc`(`_popup_basis`).
var _popup_side := "right"   # 던전 노드가 화면 왼쪽이면 팝업은 오른쪽(원작 getDirection/show)

func _open_dungeon_popup(stage_id: String) -> void:
	# 밤 위상이면 **밤 필드 레코드**를 보여준다 — 등장 드래곤·설명문·레벨이 낮과 다르다
	# (`stages.json` 의 `night` 블록, 원작에선 no=500+기본필드인 별도 레코드).
	# ⚠️ 이게 맞아야 "팝업에 등재된 드래곤만 알이 드랍된다"(사용자 확정 2026-07-30)가 성립한다 —
	#   런은 같은 `Field.apply_variant` 결과를 쓴다(adventure.gd/battle.gd).
	var st: Dictionary = Field.apply_variant(Data.stage(stage_id),
		Drops.MODE_NIGHT if _night() else Drops.MODE_NORMAL)
	var wman := _load_manifest("worldmap_ui")
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 26
	add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var S := Design.ASSET_SCALE
	var fid := int(st.get("id", 0))                    # 변형 반영 필드번호(밤 5xx/카데스 6xx)
	var kades := fid >= 600 and fid < 700
	var special := fid == 6 or fid == 8                # 해골요새·혼돈의틈새(특수 지역)
	var pw := 409.0 * S
	var ph := 491.0 * S
	var right := _popup_side == "right"
	var root := Node2D.new()
	root.position = Vector2(vis.x - pw if right else 0.0, vis.y * 0.5 - ph * 0.5)
	layer.add_child(root)
	var dock_x := root.position.x
	var bg := _sprite_native("scene_worldmap_info_bg2" if kades else "scene_worldmap_info_bg",
		"worldmap_ui", wman, S)
	if bg:
		bg.position = Vector2(pw * 0.5, ph * 0.5)
		bg.flip_h = not right                          # show(false)=setFlipX(true) — 찢긴 단이 바깥쪽
		root.add_child(bg)
	# 패널(투명층) — 파치먼트-80×-20. 도킹 방향에 따라 중심이 30pt 안쪽으로 밀린다.
	var cw := pw - 80.0
	var ch := ph - 20.0
	var pcx := pw * 0.5 + 30.0 if right else (pw - 60.0) * 0.5
	var px0 := pcx - cw * 0.5
	var py0 := ph * 0.5 - ch * 0.5
	# 제목 — BMFont subtitle. 특수 지역(6·8)은 이름만, 그 외 "레벨 N 이름". 변형은 "(밤)" 붙임.
	var tname := String(st.get("name", "던전"))
	var vlab := String(st.get("variant_label", ""))
	if vlab == "카데스의 공간": vlab = "카데스"   # 제목이 ✖ 를 침범하지 않게 팝업만 축약
	if vlab != "": tname += "(%s)" % vlab
	var title := _bmf_ui(1.0)
	title.text = tname if special else "레벨 %d %s" % [int(st.get("level", 1)), tname]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(cw, 34); title.position = Vector2(px0, py0 + 23.0 - 17.0)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(title)
	# 필드 이미지 틀(카데스 `info_img_frame2`) — 중심 (cw/2, 40+틀h/2).
	var fw := 242.0 * S
	var fh := 160.0 * S
	var fcx := px0 + cw * 0.5
	var fcy := py0 + 40.0 + fh * 0.5
	var iw := 226.0 * S                                # 틀 안쪽(테두리 8px 제외)
	var ih := 144.0 * S
	var clip: Control = null                           # 원작 ClippingLayer(tag 0x68) — 미리보기 무대
	var bgp := DungeonBG.path_for(st)
	if bgp != "":
		var prev := TextureRect.new()
		prev.texture = load(bgp)
		prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		prev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		prev.size = Vector2(iw, ih)
		prev.position = Vector2(fcx - iw * 0.5, fcy - ih * 0.5)
		prev.mouse_filter = Control.MOUSE_FILTER_IGNORE
		prev.clip_contents = true
		root.add_child(prev)
		DungeonBG.add_overlay(prev, st)                # bg_item(원작 z2, scale 2.0)
		clip = prev
	var fr := _sprite_native("scene_worldmap_info_img_frame2" if kades
		else "scene_worldmap_info_img_frame", "worldmap_ui", wman, S)
	if fr: fr.position = Vector2(fcx, fcy); root.add_child(fr)
	# 이름표(0x309)·리본·속성 아이콘이 붙는 원작 0x260(틀 스프라이트) 대응 — 틀 **위**에 그린다.
	var frame_holder := Node2D.new()
	frame_holder.position = Vector2(fcx - fw * 0.5, fcy - fh * 0.5)
	root.add_child(frame_holder)
	# `특수 지역` 리본 — 6·8만. `info_bar` anchor(0.5,1) (틀w/2, 틀h-15) + 라벨.
	if special:
		var bar := _sprite_native("scene_worldmap_info_bar", "worldmap_ui", wman, S)
		if bar:
			var bh := float(wman.get("scene_worldmap_info_bar", {}).get("h", 17)) * S
			bar.position = Vector2(fw * 0.5, 15.0 + bh * 0.5)
			frame_holder.add_child(bar)
			var bl := _bmf_ui((bh - 8.75 * S) / bh)    # 원작 라벨 배율 (barH-8.75)/labelH
			bl.text = "특수 지역"
			bl.add_theme_color_override("font_color", Color.WHITE)
			bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			bl.size = Vector2(140.0, bh)
			bl.position = bar.position - bl.size * 0.5
			frame_holder.add_child(bl)
	# 속성 아이콘 — `item/item_small/ele_*` anchor(1,0) scale 0.56, (틀w-4, 6).
	var elem := String(st.get("element", ""))
	if elem != "":
		var eman := _load_manifest("item_small_ui")
		var ei := _sprite_native("item_item_small_ele_%s" % elem, "item_small_ui", eman, 0.56 * S)
		if ei:
			var ew := float(eman.get("item_item_small_ele_%s" % elem, {}).get("w", 64)) * 0.56 * S
			var eh := float(eman.get("item_item_small_ele_%s" % elem, {}).get("h", 64)) * 0.56 * S
			ei.position = Vector2(fw - 4.0 - ew * 0.5, fh - 6.0 - eh * 0.5)
			frame_holder.add_child(ei)
	# 슬롯 줄 — 원작은 같은 층(0x248)에 드래곤 또는(우노) 보상 아이템을 깐다.
	#   층 = (cw-100)×130, 틀 바닥에서 2pt 아래. 24·25는 슬롯 y+30(cocos) = godot -30.
	var row_w := cw - 100.0
	var row_top := py0 + 40.0 + fh + 2.0
	var row_cy := row_top + 65.0 - (30.0 if fid == 24 or fid == 25 else 0.0)
	var dragons: Array = st.get("dragons", [])
	if kades:
		# 카데스 = 그 지역에서 드랍하는 **아티팩트** 슬롯(사용자 확정 2026-07-29 — 원작
		# setRewardImage 카데스 분기 = info_dragon_bg2/frame2 에 보상 아이템).
		_build_artifact_row(root, layer, st, wman, Vector2(px0 + cw * 0.5, row_cy), row_w, S)
	elif not dragons.is_empty():
		_build_dragon_row(root, layer, st, wman, dragons,
			Vector2(px0 + cw * 0.5, row_cy), row_w, clip, frame_holder, Vector2(fw, fh), S)
	elif st.has("drops"):
		_build_reward_row(root, layer, st, wman, (px0 + cw * 0.5) * 2.0, row_cy, S)
	# 설명문 — `setDesc`: 폭 cw-100, scale 0.9, anchor(0.5,1) 층 바닥 +5 (24·25는 +35).
	#   색 = 일반 (129,67,29) / 카데스 (202,182,207).
	var desc := String(st.get("desc", ""))
	if desc != "":
		var dl := _bmf_ui(0.9, "common")
		dl.text = desc
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.add_theme_color_override("font_color",
			Color8(202, 182, 207) if kades else Color8(129, 67, 29))
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dl.size = Vector2(cw - 100.0, 160.0)
		dl.position = Vector2(px0 + 50.0,
			row_top + 130.0 - (35.0 if fid == 24 or fid == 25 else 5.0))
		root.add_child(dl)
	# 하루 1회 던전의 입장 횟수 줄 — 원작 `setTryField`(24·25).
	if bool(st.get("once_per_day", false)):
		_build_try_field(root, layer, stage_id, wman, pw, ph - 116.0 * S, S)
	# 입장 버튼 — `setCheckOpenField`. RoundedButton y=60(중심), 원작 프레임/좌표 그대로.
	_build_popup_buttons(root, layer, st, stage_id, Vector2(px0, py0), Vector2(cw, ch), fid, kades, S)
	# ✖ (`common/close_btn`, 눌림 1.5배) — 파치먼트 바깥쪽 모서리 (w-50, 45) / (50, 45).
	var xb := TextureButton.new()
	var xt := "res://assets/converted/common_ui/common_close_btn.tres"
	if ResourceLoader.exists(xt):
		xb.texture_normal = load(xt)
		xb.scale = Vector2(S, S)
		xb.pivot_offset = Vector2(19, 19)
	var xc := Vector2(pw - 50.0 if right else 50.0, 45.0)
	xb.position = Vector2(dock_x, root.position.y) + xc - Vector2(19.0 * S, 19.0 * S)
	var close_popup := func():
		if is_instance_valid(layer):
			layer.queue_free()
		_reset_zoom()
	xb.pressed.connect(close_popup)
	layer.add_child(xb)
	# 패널 **바깥**을 누르면 ✖ 와 똑같이 닫고 줌을 되돌린다(양피지 위는 제외).
	var panel := Rect2(Vector2(dock_x, root.position.y), Vector2(pw, ph))
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and not panel.has_point(e.position):
			close_popup.call())
	# 등장 슬라이드 — 원작 show(): 0.15 지연 후 0.07초에 화면 밖 → 도킹.
	# (히트박스 좌표는 위에서 도킹 위치 기준으로 이미 계산했으므로 마지막에 민다.)
	root.position.x = dock_x + (pw if right else -pw)
	var stw := create_tween()
	stw.tween_interval(0.15)
	stw.tween_property(root, "position:x", dock_x, 0.07)

## 원작 BMFont 라벨 — 한글 포함 보정본(`assets/converted/font_ui`, §10 CLAUDE.md).
## kind: "subtitle"(제목·버튼 — CCLabelBMFont+getFontName_subtitle, 굵다) /
##       "common"(설명문·이름표 — CCLabelBMFontEx 기본 폰트, HCR Dotum 17 가는체.
##                원작 setDesc/onClickDragon 이름표가 전부 BMFontEx 다).
## scale 은 원작 setScale 대응(포인트 환산 ×4/3 포함).
var _popup_bmf: Dictionary = {}
func _bmf_ui(scale: float, kind := "subtitle") -> Label:
	if not _popup_bmf.has(kind):
		var p := "res://assets/converted/font_ui/font_%s.fnt" % kind
		var f: FontFile = load(p) if ResourceLoader.exists(p) else null
		if f:
			f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
		_popup_bmf[kind] = f
	var l := Label.new()
	var fnt: FontFile = _popup_bmf[kind]
	if fnt:
		l.add_theme_font_override("font", fnt)
		var base: float = float(fnt.fixed_size) if fnt.fixed_size > 0 else 19.0
		l.add_theme_font_size_override("font_size", int(round(base * Design.ASSET_SCALE * scale)))
	else:
		l.add_theme_font_size_override("font_size", int(round(25.0 * scale)))
	l.add_theme_color_override("font_color", Color8(129, 67, 29))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## 등장 드래곤 슬롯 배치 — 원작 `getDragonImagePos` 축자.
## step_x=(층w/5+3)·k, step_y=(층h/2+5)·k. ≤4칸은 한 줄 중앙정렬, 5~10칸은 두 줄(위 ceil(n/2))
## — case 5 가 이미 3+2 다(레퍼런스 빛의 탑도 3+2). 개수 ≥5 면 k=1.0.
## 반환 = 줄 중심 기준 오프셋(godot y-down).
func _dragon_slot_offsets(n: int, row_w: float, k: float) -> Array:
	var step_x := (row_w / 5.0 + 3.0) * k
	var step_y := 70.0 * k
	var out: Array = []
	if n <= 1:
		out.append(Vector2.ZERO)
		return out
	var top_n: int = n if n <= 4 else int(ceil(n / 2.0))
	var bot_n := n - top_n
	for i in top_n:
		var x := (float(i) - (float(top_n) - 1.0) * 0.5) * step_x
		out.append(Vector2(x, -step_y * 0.5 if bot_n > 0 else 0.0))
	for i in bot_n:
		var x := (float(i) - (float(bot_n) - 1.0) * 0.5) * step_x
		out.append(Vector2(x, step_y * 0.5))
	return out

## 등장 드래곤 줄 — 원작 `setDragonImage`.
## 슬롯 = `info_dragon_bg`(k배) + 썸네일(`Dragon::getImagePathBox`, 0.6배) + 덮개
##   (도감 발견 여부 × hero) `info_(no_)(hero_)dragon_frame`. 특수 지역(6·8)은 hero 뱃지 강제 해제.
## 클릭 = `onClickDragon` 미리보기(틀 안 스파인 + 성급 + 이름표).
func _build_dragon_row(root: Node2D, layer: CanvasLayer, st: Dictionary, wman: Dictionary,
		dragons: Array, center: Vector2, row_w: float, clip: Control,
		frame_holder: Node2D, fsize: Vector2, S: float) -> void:
	var fid := int(st.get("id", 0))
	var special := fid == 6 or fid == 8
	# 슬롯 배율 — 개수 ≥5 는 1.0(원작 getDragonImagePos), 1~4 는 원작 DAT 테이블(덤프 밖).
	# ASSUMPTION: 1~4 는 기본값 1.1 로 통일(레퍼런스 실측과 크기 일치).
	var k := 1.0 if dragons.size() >= 5 else 1.1
	var offs := _dragon_slot_offsets(dragons.size(), row_w, k)
	for i in dragons.size():
		var d: Dictionary = dragons[i]
		var did := int(d.get("id", 0))
		var hero := bool(d.get("hero", false)) and not special
		var seen := UserDB.dex_seen(did)
		var pos := center + (offs[i] as Vector2)
		var bg := _sprite_native("scene_worldmap_info_dragon_bg", "worldmap_ui", wman, S * k)
		if bg: bg.position = pos; root.add_child(bg)
		# 썸네일 — 도감·둥지와 같은 box 프레임(성체 우선).
		var thumb := _dragon_box_sprite(did, 0.6 * S * k)
		if thumb: thumb.position = pos; root.add_child(thumb)
		var fr_name: String
		if seen:
			fr_name = "scene_worldmap_info_hero_dragon_frame" if hero \
				else "scene_worldmap_info_dragon_frame"
		else:
			fr_name = "scene_worldmap_info_no_hero_dragon_frame" if hero \
				else "scene_worldmap_info_no_dragon_frame"
		var fr := _sprite_native(fr_name, "worldmap_ui", wman, S * k)
		if fr: fr.position = pos; root.add_child(fr)
		var hit := Button.new(); hit.flat = true
		hit.size = Vector2(56.0, 50.0) * S * k
		hit.position = root.position + pos - hit.size * 0.5
		# 팝업이 닫히는 프레임에 눌리면 캡처가 해제돼 null 이 온다 → 유효할 때만.
		hit.pressed.connect(func():
			if is_instance_valid(frame_holder):
				_popup_dragon_preview(did, clip, frame_holder, fsize, S))
		layer.add_child(hit)

## 카데스 아티팩트 슬롯 줄 — 원작 `setRewardImage` 카데스 분기(`info_dragon_bg2` +
## `info_dragon_frame2`). 내용 = 그 기본 필드의 아티팩트 드랍 4종
## (`data/drops.json` kades.artifact_by_dungeon, 사용자 확정 2026-07-29).
## 아이콘은 최저 등급(파손된, 드랍 가중치 최다)으로 그린다. 클릭 = 이름 말풍선(onClickReward).
func _build_artifact_row(root: Node2D, layer: CanvasLayer, st: Dictionary, wman: Dictionary,
		center: Vector2, row_w: float, S: float) -> void:
	var base_f := str(int(st.get("base_field", st.get("id", 0))))
	var types: Array = Data.drops.get("kades", {}).get("artifact_by_dungeon", {}).get(base_f, [])
	if types.is_empty():
		return
	var k := 1.1
	var offs := _dragon_slot_offsets(types.size(), row_w, k)
	for i in types.size():
		var tname := String(types[i])
		var pos := center + (offs[i] as Vector2)
		# 원작은 `info_dragon_bg2` 인데 추출 아틀라스에 없다(후기 추가분, CLAUDE.md §10 표)
		# → 보유한 `info_dragon_bg` 로 대체. frame2 는 실재해서 원본 그대로.
		var bg := _sprite_native("scene_worldmap_info_dragon_bg", "worldmap_ui", wman, S * k)
		if bg: bg.position = pos; root.add_child(bg)
		var tex := Icons.texture("artifact", "%s:0" % tname)
		if tex:
			var ic := Sprite2D.new()
			ic.texture = tex
			ic.material = _pma
			var tw_px: float = maxf(1.0, float(tex.get_width()))
			ic.scale = Vector2.ONE * (34.0 * S * k / tw_px)
			ic.position = pos
			root.add_child(ic)
		var fr := _sprite_native("scene_worldmap_info_dragon_frame2", "worldmap_ui", wman, S * k)
		if fr: fr.position = pos; root.add_child(fr)
		var hit := Button.new(); hit.flat = true
		hit.size = Vector2(56.0, 50.0) * S * k
		hit.position = root.position + pos - hit.size * 0.5
		hit.pressed.connect(func(): _reward_tip(layer, root.position + pos, tname, S))
		layer.add_child(hit)

## 드래곤 box 썸네일(원작 Dragon::getImagePathBox = portrait 아틀라스 box_* 프레임).
func _dragon_box_sprite(id: int, scale: float) -> Sprite2D:
	for stg in ["adult", "child", "baby"]:
		var p := "res://assets/converted/portrait_%d/dragon_dragon_%d_box_%s.tres" % [id, id, stg]
		if ResourceLoader.exists(p):
			var s := Sprite2D.new()
			s.texture = load(p)
			s.material = _pma
			s.scale = Vector2(scale, scale)
			return s
	return null

## 슬롯 클릭 미리보기 — 원작 `onClickDragon`.
## 틀 안(클리핑)에 성체 스파인 "love" 루프 + 성급(StarclassLayer) + 이름표(9patch/dialogue_box).
func _popup_dragon_preview(did: int, clip: Control, frame_holder: Node2D,
		fsize: Vector2, S: float) -> void:
	var info := Data.get_dragon(did)
	# 이전 미리보기 제거(원작 tag 0x66/0x6c/0x309 removeFromParent).
	# ⚠️ 노드 이름으로 찾으면 안 된다 — queue_free 는 프레임 끝에 지워져서 같은 이름을
	#   바로 다시 붙이면 새 노드가 자동 개명되고, 다음 클릭이 옛 노드를 못 찾아 겹쳐 남는다.
	#   (2026-07-29 사용자 검수: "기존 모션이 사라지지 않고 남는다") → meta 참조로 관리.
	# ⚠️ 연출이 스스로 사라진(자기 queue_free) 뒤에는 meta 에 **해제된 참조**가 남는다 —
	#   `is_instance_valid` 를 먼저(freed 안전), `is Node` 는 그 뒤에(freed 에 쓰면 에러).
	for key in ["prev_spine", "prev_stars"]:
		if clip and clip.has_meta(key):
			var old = clip.get_meta(key)
			if is_instance_valid(old) and old is Node:
				(old as Node).queue_free()
			clip.remove_meta(key)
	if frame_holder != null and is_instance_valid(frame_holder) \
			and frame_holder.has_meta("prev_name"):
		var oldn = frame_holder.get_meta("prev_name")
		if is_instance_valid(oldn) and oldn is Node:
			(oldn as Node).queue_free()
		frame_holder.remove_meta("prev_name")
	if clip == null or not is_instance_valid(clip):
		return
	var cwid := clip.size.x
	var chgt := clip.size.y
	# 원작 클리핑층은 bg.jpg 스프라이트(1024×692pt, setScale 0.29)의 **자식**이라 리터럴 좌표가
	# 그 원시 좌표계다. 화면 환산: 배율 ×0.29, y 는 692pt 기준 → 우리 클립 높이로 사상.
	var K := 0.29                                      # 원작 bg setScale(0.29)
	var yf := chgt / (692.0 * K)                       # bg 화면높이(692·0.29pt) → 우리 클립 높이
	# ① 스파인 — pos (w/2, h/2-90) = 바닥에서 256pt(원시) ≈ 74pt(화면), setScale 1.7×0.29.
	var sp := "res://scenes/dragons/dragon_%d_adult.tscn" % did
	if ResourceLoader.exists(sp):
		var base_s := 1.7 * K
		var holder := Node2D.new()
		holder.position = Vector2(cwid * 0.5, chgt - 256.0 * K * yf)
		holder.scale = Vector2(base_s, base_s)
		holder.modulate.a = 0.0
		clip.add_child(holder)
		clip.set_meta("prev_spine", holder)
		var inst = (load(sp) as PackedScene).instantiate()
		holder.add_child(inst)
		var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		if ap:
			for cand in ["love", "wait", "animation"]:
				if ap.has_animation(cand):
					ap.get_animation(cand).loop_mode = Animation.LOOP_LINEAR
					ap.play(cand)
					break
		# [FadeIn 0.5 ∥ Scale→(1.7+0.2)/1.7배] → Scale→기본(0.25) → 6.5s → FadeOut 1.0
		var tw := holder.create_tween()
		tw.tween_property(holder, "modulate:a", 1.0, 0.5)
		tw.parallel().tween_property(holder, "scale", Vector2.ONE * base_s * (1.9 / 1.7), 0.5)
		tw.tween_property(holder, "scale", Vector2.ONE * base_s, 0.25)
		tw.tween_interval(6.5)
		tw.tween_property(holder, "modulate:a", 0.0, 1.0)
		tw.tween_callback(holder.queue_free)
	# ② 성급 — StarclassLayer(common/eggclass ×N) setScale 2.5×0.29, 위에서 100pt(원시)≈29pt.
	var stars := int(info.get("star", 0))
	if stars > 0:
		var srow := Node2D.new()
		srow.position = Vector2(cwid * 0.5, 100.0 * K * yf)
		srow.scale = Vector2(2.5 * K, 2.5 * K)
		srow.z_index = 200                             # 변환 스파인 씬의 슬롯 z_index 위로
		clip.add_child(srow)
		clip.set_meta("prev_stars", srow)
		var man := _load_manifest("common_ui")
		var sw := float(man.get("common_eggclass", {}).get("w", 19)) * S
		for i in stars:
			var s := _sprite_native("common_eggclass", "common_ui", man, S)
			if s == null: break
			s.position = Vector2((float(i) - (float(stars) - 1.0) * 0.5) * sw, 0)
			s.scale = Vector2.ZERO
			srow.add_child(s)
			# 별마다 0.1i 지연 + [RotateBy 180° ∥ ScaleTo 1] → 스쿼시(0.9,1.1)→(1.1,0.9)→(1,1)
			var stw := s.create_tween()
			stw.tween_interval(0.1 * i)
			stw.tween_property(s, "rotation_degrees", 180.0, 0.25)
			stw.parallel().tween_property(s, "scale", Vector2.ONE * S, 0.25)
			stw.tween_property(s, "scale", Vector2(0.9, 1.1) * S, 0.1)
			stw.tween_property(s, "scale", Vector2(1.1, 0.9) * S, 0.1)
			stw.tween_property(s, "scale", Vector2.ONE * S, 0.1)
		# 1.5s 뒤 절반 크기 → 1s 뒤 제거(원작 CallFunc(scale 0.5)+Delay+RemoveSelf)
		var rtw := srow.create_tween()
		rtw.tween_interval(1.5)
		rtw.tween_property(srow, "scale", Vector2(1.25, 1.25), 0.15)
		rtw.tween_interval(1.0)
		rtw.tween_callback(srow.queue_free)
	# ③ 이름표 — 9patch/dialogue_box, 틀 하단 중앙(anchor(0.5,0) y=20). 바운스 등장 후 페이드.
	var nm := String(info.get("name", ""))
	if nm != "":
		var tip := NinePatchRect.new()
		tip.z_index = 200                              # 변환 스파인 씬의 슬롯 z_index 위로
		tip.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres")
		tip.patch_margin_left = 20; tip.patch_margin_top = 20
		tip.patch_margin_right = 20; tip.patch_margin_bottom = 4
		var l := _bmf_ui(1.0, "common")                # 원작 이름표 = CCLabelBMFontEx(가는체)
		l.text = nm
		l.add_theme_color_override("font_color", Color.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var lw := 26.0 * nm.length()
		tip.size = Vector2(lw + 25.0, 44.0)
		tip.pivot_offset = Vector2(tip.size.x * 0.5, tip.size.y)
		tip.position = Vector2(fsize.x * 0.5 - tip.size.x * 0.5, fsize.y - 20.0 - tip.size.y)
		tip.modulate.a = 0.0
		tip.scale = Vector2(0.1, 0.1)
		frame_holder.add_child(tip)
		frame_holder.set_meta("prev_name", tip)
		l.size = tip.size
		tip.add_child(l)
		# 박스: [FadeIn 0.25 ∥ Scale→1.2 ∥ +30 위로] → [Scale→1.05 ∥ 바운스 -30] → 1s → FadeOut
		var btw := tip.create_tween()
		btw.tween_property(tip, "modulate:a", 1.0, 0.25)
		btw.parallel().tween_property(tip, "scale", Vector2(1.2, 1.2), 0.25)
		btw.parallel().tween_property(tip, "position:y", tip.position.y - 30.0, 0.25)
		btw.tween_property(tip, "scale", Vector2(1.05, 1.05), 0.5)
		btw.parallel().tween_property(tip, "position:y", tip.position.y, 0.5) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		btw.tween_interval(1.0)
		btw.tween_property(tip, "modulate:a", 0.0, 1.0)
		btw.tween_callback(tip.queue_free)

## 입장 버튼들 — 원작 `setCheckOpenField` 축자.
##   일반(160×65, `9patch/btn`) + 영웅(160×65, `9patch/btn6`+`common/mode_skull`) + AUTO(60×54,
##   `9patch/btn4`+`scene/adventure/auto*`). 8·24·25 는 AUTO 없음(원작 비트마스크 0x3000100).
##   6 = 단일 "해골요새 입장". 카데스 = 영웅 숨김·일반 중앙(`9patch/btn10`)+`icon_kades`.
##   영웅 개방 검사(`setCheckHardMode` — User::getHardStatus)는 서버 유실 → 미게이팅(TODO).
func _build_popup_buttons(root: Node2D, layer: CanvasLayer, st: Dictionary, stage_id: String,
		porg: Vector2, psize: Vector2, fid: int, kades: bool, S: float) -> void:
	var region := _mode
	var daily := bool(st.get("once_per_day", false))
	# 원작 `setAdventure` 는 난이도 선택 즉시 AdventureScene 으로(파티 선택 없음, 2026-07-27 확인).
	var enter := func(hero: bool):
		if daily:
			_daily_stamp(stage_id)
		if is_instance_valid(layer):
			layer.queue_free()
		# `night` = 유타칸 밤 변형인가. 드랍 풀이 난이도(일반/영웅/밤)마다 다르므로
		# 런에 실어 보낸다(사용자 확정 2026-07-31, `Drops.mode_of`).
		# ⚠️ 아직 **드랍 판정에만** 쓴다 — 밤 블록의 적/등장드래곤 교체는 미배선(별도 갭).
		# `run_seed` = **이번 진입** 고유 난수. 이벤트 큐 시드에 섞는다 —
		# 없으면 (지역, 조우번호)만으로 시드가 정해져 **같은 지역에 다시 들어가도 결과가 똑같다**.
		# 밤은 1회 조우로 끝나므로 이게 없으면 그 지역의 밤 결과가 영영 고정된다(2026-07-31 발견).
		Scenes.goto("adventure", {"stage": stage_id, "region": region, "hero": hero,
			"night": _night(), "run_seed": randi()})
	var go := func(hero: bool):
		# 🔒 소환형 던전(혼돈의 틈새) — 원작 `WorldMapPopupLayer::getIsExistSomething()` 이
		#    출전 검사보다 **먼저** 막는다(:1866 은 `setAdventure` 경로 진입 전에 호출된다).
		#    보스가 상주 중이 아니면 소환 팝업만 띄우고 이번 클릭은 입장하지 않는다.
		if not _darknix_gate(st, layer):
			return
		# 출전 검사(원작 `getDragonStatus`) — **선택 중인 드래곤 한 마리만** 본다.
		# 불능이면 다른 드래곤으로 대체하지 않고 입장을 막고, 원작 팝업(즉시부활/먹이)을 띄운다.
		if not _selected_gate():
			return
		# 유타칸 **밤** 최소 레벨(원작 `<AdventureNightMinLv>`). 위키 dungeon_1.pdf §1.2.1~1.2.12 가
		# 밤 던전 12종을 전부 Lv.50 으로 적고, 사용자도 "일괄 50레벨"로 확정했다(2026-07-30).
		# 값 = `stages.json _variant_rules.night_min_level`.
		if not _night_level_ok():
			_notice("선택한 드래곤의 레벨이 부족하여 진입할 수 없습니다.")
			return
		if daily and not _daily_ok(stage_id):
			_confirm_daily_extra(enter, hero)
			return
		enter.call(hero)
	var cx := porg.x + psize.x * 0.5
	var by := porg.y + psize.y - 60.0                  # cocos y=60(중심) → godot 바닥-60
	var bw := 160.0
	var bh := 65.0
	if fid == 6:
		# 해골요새 — 단일 입장 버튼(원작 DungeonScene 진입. 층 시스템은 ⚪ 미이식 → adventure 로).
		_popup_button(root, "해골요새 입장", "9patch_btn",
			Vector2(cx - 110.0, by - bh * 0.5), Vector2(220.0, bh), func(): go.call(false))
		return
	if kades:
		# 카데스 — 일반만 중앙, `9patch/btn10` + 라벨 왼쪽에 `icon_kades`.
		var kb := _popup_button(root, "일반", "9patch_btn10",
			Vector2(cx - bw * 0.5, by - bh * 0.5), Vector2(bw, bh), func(): go.call(false))
		var kman := _load_manifest("worldmap_ui")
		var ki := _sprite_native("scene_worldmap_icon_kades", "worldmap_ui", kman, S)
		if ki and kb:
			ki.position = Vector2(32.0, bh * 0.5)
			kb.add_child(ki)
		return
	var no_auto := fid == 8 or fid == 24 or fid == 25
	# AUTO 있으면 -20/-10, 없으면 ±10(원작 좌표).
	var nx := cx - bw * 0.5 - (10.0 if no_auto else 20.0)
	var hx := cx + bw * 0.5 + (10.0 if no_auto else -10.0)
	_popup_button(root, "일반", "9patch_btn",
		Vector2(nx - bw * 0.5, by - bh * 0.5), Vector2(bw, bh), func(): go.call(false))
	var hero_btn := _popup_button(root, "영웅", "9patch_btn6",
		Vector2(hx - bw * 0.5, by - bh * 0.5), Vector2(bw, bh), func(): go.call(true))
	if hero_btn:
		# 원작: 라벨 anchor(0,0.5) 좌단 = w/2-25, 해골 아이콘 anchor(0,0.5) 좌단 = 15.
		var lab := hero_btn.get_node_or_null("label")
		if lab is Label:
			(lab as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			(lab as Label).position.x = bw * 0.5 - 25.0
		var cman := _load_manifest("common_ui")
		var skull := _sprite_native("common_mode_skull", "common_ui", cman, S)
		if skull:
			var sw := float(cman.get("common_mode_skull", {}).get("w", 30)) * S
			skull.position = Vector2(15.0 + sw * 0.5, bh * 0.5)
			hero_btn.add_child(skull)
	if not no_auto:
		# AUTO — 원작은 매크로 감지/부스트용 자동사냥. 우리는 자동사냥 미구현 → 표시만(눌림 무동작).
		var ab := _popup_button(root, "", "9patch_btn4",
			Vector2(hx + bw * 0.5 + 40.0 - 30.0, by - 27.0), Vector2(60.0, 54.0), func(): pass)
		var aman := _load_manifest("adventure_ui")
		var abg := _sprite_native("scene_adventure_auto_bg", "adventure_ui", aman, 0.5 * S)
		if abg and ab: abg.position = Vector2(30.0, 27.0); ab.add_child(abg)
		var aic := _sprite_native("scene_adventure_auto", "adventure_ui", aman, 0.5 * S)
		if aic and ab: aic.position = Vector2(30.0, 27.0); ab.add_child(aic)

## 아이템 논리키 → 아이콘 스프라이트. `data/items.json` 의 `icon` 은 `<변환폴더>/<프레임>` 형식이다
## (§8.4 에셋 카탈로그 — logic 은 경로를 모르고 render 만 안다).
func _item_icon(key: String, target: float) -> Sprite2D:
	var p := Data.item_icon_path(key)
	if p == "" or not ResourceLoader.exists(p):
		return null
	var tex: Texture2D = load(p)
	var s := Sprite2D.new()
	s.texture = tex
	s.material = _pma
	var w: float = maxf(1.0, float(tex.get_width()))
	s.scale = Vector2(target / w, target / w)
	return s

## 보상 아이템 줄 — 원작 `WorldMapPopupLayer::setRewardImage`.
## 한 드롭 항목이 **칸 여러 개**로 펼쳐진다(개수 min·중간·max, 그리고 영웅 전용 수량).
## 근거: 레퍼런스 `docs/ref/uno/던전1.png` 이 아니마 1/2/3/6 을 나란히 놓고 3·4번째에만
## `info_hero_dragon_frame`(보라 H 뱃지)를 쓴다 — 즉 앞 둘이 일반 범위, 뒤 둘이 영웅 범위다.
func _build_reward_row(root: Node2D, layer: CanvasLayer, st: Dictionary, wman: Dictionary,
		pw: float, y: float, S: float) -> void:
	var cells: Array = []      # [{item, count, hero}]
	for dp in (st.get("drops", []) as Array):
		var d: Dictionary = dp
		var key := String(d.get("item", ""))
		if key == "": continue
		var lo := int(d.get("min", 1))
		var hi := int(d.get("max", lo))
		cells.append({"item": key, "count": lo, "hero": false})
		if hi != lo:
			cells.append({"item": key, "count": hi, "hero": false})
		if d.has("hero_min"):
			cells.append({"item": key, "count": int(d["hero_min"]), "hero": true})
			var hhi := int(d.get("hero_max", d["hero_min"]))
			if hhi != int(d["hero_min"]):
				cells.append({"item": key, "count": hhi, "hero": true})
	if cells.is_empty():
		return
	var n: int = mini(cells.size(), 5)
	for i in n:
		var c: Dictionary = cells[i]
		var frame := "scene_worldmap_info_hero_dragon_frame" if bool(c["hero"]) \
			else "scene_worldmap_info_dragon_frame"
		var cx := pw * 0.5 + (float(i) - (float(n) - 1.0) * 0.5) * 62.0 * S
		var bg := _sprite_native("scene_worldmap_info_dragon_bg", "worldmap_ui", wman, S)
		if bg: bg.position = Vector2(cx, y); root.add_child(bg)
		var ic := _item_icon(String(c["item"]), 38.0 * S)
		if ic: ic.position = Vector2(cx, y); root.add_child(ic)
		var fr := _sprite_native(frame, "worldmap_ui", wman, S)
		if fr: fr.position = Vector2(cx, y); root.add_child(fr)
		var cl := Label.new()
		cl.text = str(int(c["count"]))
		cl.add_theme_font_size_override("font_size", 17)
		cl.add_theme_color_override("font_color", Color(0.25, 0.15, 0.04))
		cl.add_theme_color_override("font_outline_color", Color(1, 0.97, 0.88, 0.9))
		cl.add_theme_constant_override("outline_size", 4)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cl.size = Vector2(46.0 * S, 22.0)
		cl.position = Vector2(cx - 44.0 * S * 0.5, y + 6.0 * S)
		root.add_child(cl)
		# 눌러 이름 확인 — 원작 `onClickReward` 는 `9patch/dialogue_box` 말풍선을 띄우고
		# 페이드로 지운다. 우리도 같은 프레임을 쓴다.
		var hit := Button.new(); hit.flat = true
		hit.size = Vector2(52.0 * S, 52.0 * S)
		hit.position = root.position + Vector2(cx, y) - hit.size * 0.5
		var nm := Data.item_name(String(c["item"]))
		hit.pressed.connect(func(): _reward_tip(layer, root.position + Vector2(cx, y), nm, S))
		layer.add_child(hit)

## 보상 아이콘 이름 말풍선(원작 `onClickReward`: `9patch/dialogue_box` + 페이드아웃).
func _reward_tip(layer: CanvasLayer, at: Vector2, text: String, S: float) -> void:
	var tip := NinePatchRect.new()
	tip.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres")
	tip.patch_margin_left = 15; tip.patch_margin_top = 15
	tip.patch_margin_right = 15; tip.patch_margin_bottom = 15
	var w: float = maxf(90.0, float(text.length()) * 22.0)
	tip.size = Vector2(w, 44.0)
	tip.position = at + Vector2(26.0 * S, -46.0 * S)
	layer.add_child(tip)
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(1, 0.97, 0.9))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = tip.size
	tip.add_child(l)
	var t := tip.create_tween()
	t.tween_interval(1.1)
	t.tween_property(tip, "modulate:a", 0.0, 0.3)
	t.tween_callback(tip.queue_free)

## 하루 1회 던전의 입장 횟수 줄 — 원작 `WorldMapPopupLayer::setTryField`.
##   `scene/worldmap/icon_unocount` + 남은/쓴 횟수를 `common/charge`(남음) ·
##   `common/charge_gray`(소진)로 찍고, 오른쪽에 `common/charge` 충전 버튼.
##   그 아래 안내문 = 원작 문자열 `AdventureUnoNotice1`
##   "(1일 최대 %1$d회 입장가능 / 매일 0시에 초기화 됩니다)" — **XML 원문 그대로**다
##   (레퍼런스 스크린샷의 "매일 4시"는 그보다 이전 판본이다).
const UNO_TRY_PER_DAY := 1

func _build_try_field(root: Node2D, layer: CanvasLayer, stage_id: String, wman: Dictionary,
		pw: float, y: float, S: float) -> void:
	var left := _daily_ok(stage_id)
	var cman := _load_manifest("common_ui")
	# 원작 `RoundedLayer` — 레퍼런스(`docs/ref/uno/던전1.png`)에서 어두운 둥근 막대다.
	# 왼쪽에 ⚡(`icon_unocount`), 가운데 남은 횟수, 오른쪽에 초록 `common/charge` 충전 버튼.
	var bw := 150.0 * S
	var bh := 30.0 * S
	var bx := pw * 0.5 - bw * 0.5
	var bar := ColorRect.new()
	bar.color = Color(0.40, 0.33, 0.24, 0.85)
	bar.size = Vector2(bw, bh)
	bar.position = Vector2(bx, y - bh * 0.5)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	var ic := _sprite_native("scene_worldmap_icon_unocount", "worldmap_ui", wman, S)
	if ic: ic.position = Vector2(bx, y); root.add_child(ic)
	var cnt := Label.new()
	cnt.text = str(1 if left else 0)
	cnt.add_theme_font_size_override("font_size", 20)
	cnt.add_theme_color_override("font_color", Color(1, 1, 1))
	cnt.add_theme_color_override("font_outline_color", Color(0.18, 0.12, 0.05))
	cnt.add_theme_constant_override("outline_size", 4)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cnt.size = Vector2(bw, bh); cnt.position = Vector2(bx, y - bh * 0.5)
	root.add_child(cnt)
	var note := Label.new()
	note.text = "(1일 최대 %d회 입장가능 / 매일 0시에 초기화 됩니다)" % UNO_TRY_PER_DAY
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.42, 0.30, 0.16))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.size = Vector2(pw - 40.0, 20.0)
	note.position = Vector2(20.0, y + 16.0 * S)
	root.add_child(note)
	# 충전 버튼 — 원작 `onClickFatigueUno`: `<AdventureUnoResetNotice>`
	# "다이아 %1$d개를 소모하여 입장 횟수 1회를 충전할 수 있습니다. 충전하시겠습니까?"
	# 레퍼런스(`던전1.png`)는 남은 횟수가 있어도 초록 `common/charge` 다 — 회색
	# `charge_gray` 는 원작이 소진된 **횟수 칩**에 쓰는 프레임이지 버튼이 아니다.
	var chg := _sprite_native("common_charge", "common_ui", cman, S)
	if chg:
		chg.position = Vector2(bx + bw, y)
		root.add_child(chg)
		var cb := Button.new(); cb.flat = true
		cb.size = Vector2(40.0 * S, 40.0 * S)
		cb.position = root.position + Vector2(bx + bw, y) - cb.size * 0.5
		cb.pressed.connect(func():
			if left:
				return          # 아직 오늘 안 다녀왔다 — 충전할 게 없다
			_confirm_daily_recharge(stage_id, layer))
		layer.add_child(cb)

## 입장 횟수 충전 — 원작 `onClickFatigueUno` → `PopupTypeLayer` + `setCash`.
## 문구는 원작 문자열 `<AdventureUnoResetNotice>` 그대로.
## 원작은 서버가 횟수를 셌지만 우리는 날짜 도장이라, 충전 = **오늘 도장 지우기**다.
func _confirm_daily_recharge(stage_id: String, popup_layer: CanvasLayer) -> void:
	var msg := "다이아 %d개를 소모하여" % DAILY_EXTRA_DIA
	msg += "
입장 횟수 1회를 충전할 수 있습니다.
충전하시겠습니까?"
	_confirm_dialog(msg,
		func():
			if not UserDB.spend("diamond", DAILY_EXTRA_DIA):
				_notice("다이아가 부족합니다.")
				return
			var m = UserDB.get_pmeta("daily_dungeon", {})
			var dd: Dictionary = (m as Dictionary).duplicate() if m is Dictionary else {}
			dd.erase(stage_id)
			UserDB.set_pmeta("daily_dungeon", dd)
			if is_instance_valid(popup_layer):
				popup_layer.queue_free()
			_open_dungeon_popup(stage_id))

## 예/아니오 확인창(9patch/popup4). `_confirm_daily_extra` 와 같은 틀.
func _confirm_dialog(text: String, on_ok: Callable) -> void:
	var vis := _vis()
	var lay := CanvasLayer.new(); lay.layer = 44; add_child(lay)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT); lay.add_child(dim)
	const BW := 480.0
	const BH := 250.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190
	win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH)
	win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	lay.add_child(win)
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(0.3, 0.2, 0.06))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(BW - 60, 100); l.position = Vector2(30, 62)
	win.add_child(l)
	var ok := Button.new(); ok.text = "확인"; ok.size = Vector2(140, 42)
	ok.position = Vector2(BW * 0.5 - 150, BH - 60)
	ok.pressed.connect(func():
		lay.queue_free()
		on_ok.call())
	win.add_child(ok)
	var no := Button.new(); no.text = "취소"; no.size = Vector2(140, 42)
	no.position = Vector2(BW * 0.5 + 10, BH - 60)
	no.pressed.connect(func(): lay.queue_free()); win.add_child(no)

## 팝업용 9patch 버튼(원작 `RoundedButton` — `9patch/btn*`, capInsets (20,20,4,4)).
## 라벨은 BMFont subtitle 흰색(원작). 반환 = 버튼 컨테이너(아이콘 부착용, 라벨명 "label").
func _popup_button(parent: Node2D, text: String, frame: String, pos: Vector2, size: Vector2,
		cb: Callable) -> Control:
	var np := NinePatchRect.new()
	var tex: Texture2D = load("res://assets/converted/ninepatch_ui/%s.tres" % frame)
	np.texture = tex
	# 원작 CCRect(20,20,4,4) = 늘어나는 중심부 (20,20)~(24,24).
	np.patch_margin_left = 20; np.patch_margin_top = 20
	np.patch_margin_right = maxi(1, tex.get_width() - 24) if tex else 20
	np.patch_margin_bottom = maxi(1, tex.get_height() - 24) if tex else 20
	np.size = size; np.position = pos
	parent.add_child(np)
	var l := _bmf_ui(1.0)
	l.name = "label"
	l.text = text
	l.add_theme_color_override("font_color", Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = size
	np.add_child(l)
	var b := Button.new(); b.flat = true; b.size = size
	b.pressed.connect(cb)
	np.add_child(b)
	return np

## 팝업을 닫으면 줌을 원래대로 되돌린다(원작도 팝업 X → 지도 복귀).
func _reset_zoom() -> void:
	_busy = false
	_clear_field_fx()   # 원작 setMapAnimationRemove — 필드에서 벗어나면 연출도 걷는다
	if not is_instance_valid(_content): return
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_content, "scale", Vector2.ONE, 0.4)
	tw.parallel().tween_property(_content, "position", Vector2.ZERO, 0.4)
