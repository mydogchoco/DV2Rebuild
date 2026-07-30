extends Control
## Cave (메인 로비). 참고: docs/ref/orig_image/old_screenshots/Cave.png
## 기능: 드래곤 육성·관리, 인벤토리 확인/사용, 도감 열람, 배경 스킨 변경.

const UI := "res://assets/converted/cave_ui/%s.tres"
const STAND := "res://assets/converted/stand_ui/stand_stand%d.tres"
const BG := "res://assets/converted/cave_bg/cavebg%d.jpg"
const DRAGON_SCENE := "res://scenes/dragons/dragon_%d_%s.tscn"
const SKIN_COUNT := 15
const STAND_COUNT := 16

var _pma: CanvasItemMaterial
var _manifest: Dictionary = {}
var _stand_manifest: Dictionary = {}
var _battle_manifest: Dictionary = {}
var _status_manifest: Dictionary = {}
var _portrait_manifests: Dictionary = {}   # dir -> manifest (캐시)
var _item_small_manifest: Dictionary = {}  # item_small_ui(원작 속성 아이콘 ele_*)
var _elem_icon: Sprite2D
var _dragon_ap: AnimationPlayer            # 현재 활성 드래곤의 AnimationPlayer
var _bg: TextureRect
var _walls: Node2D                          # 벽 프레임 컨테이너(테마 변경 시 재빌드)
var _stage: Node2D
var _list_box: VBoxContainer
var _stat_plates: Dictionary = {}   # 원작 하단 스탯 플레이트(hp/att/def → 값 Label)
var _slot_layer: Control            # 하단 장착 슬롯(아이템·젬·스킬) — _refresh 마다 재구성
var _overlay: Control
var _overlay_layer: CanvasLayer   # 오버레이를 드래곤 spine보다 위에 그리기 위한 레이어
var _skill_modal: CanvasLayer     # 스킬 스크롤 습득 모달(인벤토리 위 layer 20)
var _params: Dictionary = {}      # 진입 params — `open` 이 있으면 빌드 후 해당 팝업을 연다

## 씬 전환 진입점. ⚠️ `Scenes.goto` 는 **트리 편입 전에** 이걸 부른다
## (scene_manager.gd 주석 참조) — 트리 의존 API 금지. params 만 받아 두고 실제 동작은 `_ready`.
##
## `open` = 메인 화면(MainHud) 하단 메뉴에서 넘어온 팝업 지정. 원작에서는 이것들이 전부
## 월드맵 위의 독립 레이어였지만(StatusLayer / WorldDragonBookLayer / BagPopup / MissionLayer /
## AchievementLayer) 우리 구현이 cave.gd 안에 있어 씬을 거쳐 연다.
func enter(params: Dictionary = {}) -> void:
	_params = params

func _ready() -> void:
	Bgm.play("bg_cave")
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	var mf := FileAccess.open("res://assets/converted/cave_ui/_manifest.json", FileAccess.READ)
	if mf: _manifest = JSON.parse_string(mf.get_as_text())
	var sf := FileAccess.open("res://assets/converted/stand_ui/_manifest.json", FileAccess.READ)
	if sf: _stand_manifest = JSON.parse_string(sf.get_as_text())
	var bf := FileAccess.open("res://assets/converted/battle_ui/_manifest.json", FileAccess.READ)
	if bf: _battle_manifest = JSON.parse_string(bf.get_as_text())
	var stf := FileAccess.open("res://assets/converted/status_ui/_manifest.json", FileAccess.READ)
	if stf: _status_manifest = JSON.parse_string(stf.get_as_text())
	var isf := FileAccess.open("res://assets/converted/item_small_ui/_manifest.json", FileAccess.READ)
	if isf: _item_small_manifest = JSON.parse_string(isf.get_as_text())

	# 초기 상태(새 게임)는 진입점(main.gd → NewGame)이 보장. 여기선 표시만 한다.
	_build_background()
	_build_walls()
	_build_stage()
	_build_quick_panel()
	_build_dragon_list()
	_build_bottom_bar()
	_build_menu()
	_build_topbar()
	_refresh()
	_maybe_tutorial()   # 원작 TutorialLayer: 최초 1회 온보딩 안내
	_open_requested()   # 메인 화면 메뉴에서 지정한 팝업(params.open)

## params.open → 대응 팝업. 없거나 모르는 값이면 아무것도 안 한다.
## `status` 외의 육성 팝업들은 **메인 화면 상태창**(`StatusLayer`)이 넘겨 준 것이다 —
## 상태창은 어느 씬에서든 뜨지만 그 안의 심화 편집은 여기 cave.gd 에만 있다(사용자 확정 2026-07-28).
func _open_requested() -> void:
	var what := String(_params.get("open", ""))
	match what:
		"status": _open_dragon_detail()
		"dex": _open_dex()
		"bag": _open_inventory()
		"quests": _open_quests()
		"titles": _open_titles()
		"rename", "equip", "gem", "skill", "awaken_skill", "levelup", \
		"awaken_dex", "skin", "storage":
			_on_status_action(what, int(_params.get("arg", -1)))

# ---------- helpers ----------
func _ui_tex(name: String) -> AtlasTexture:
	var p := UI % name
	return load(p) if ResourceLoader.exists(p) else null

func _ui_sprite(name: String, scale := 1.0) -> Sprite2D:
	return _atlas_sprite("cave_ui", name, _manifest, scale)

## 임의 변환 아틀라스의 스프라이트 생성(회전/PMA 보정). 없으면 텍스처 없는 스프라이트 반환.
func _atlas_sprite(dir: String, name: String, man: Dictionary, scale := 1.0) -> Sprite2D:
	var s := Sprite2D.new()
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if ResourceLoader.exists(p):
		s.texture = load(p)
	s.material = _pma
	# 회전 패킹 보정은 이제 변환 단계가 흡수한다(fix_rotated_frames.py / cocos_export.py):
	# 회전 프레임은 세운 낱장 PNG 로 떼어내므로 매니페스트 rotated=false 다. 여기서 돌리지 않는다.
	s.scale = Vector2(scale, scale)
	return s

func _panel(col := Color(0, 0, 0, 0.55)) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.25)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _active() -> Dictionary:
	return UserDB.active_dragon()

## 현재 가시영역 크기(692 고정높이 + keep_height → 너비 가변). design.gd 앵커의 입력.
func _vis() -> Vector2:
	return get_viewport_rect().size

# 1080-공간으로 작성된 복잡한 클러스터(하단바 자식들·받침대+드래곤·오버레이)를 692공간에
# 그대로 얹기 위한 컨테이너 스케일. 내부 좌표는 안 건드리고 컨테이너만 스케일한다.
const S1080 := 692.0 / 1080.0   # ≈0.6407

# ---------- build ----------
func _build_background() -> void:
	_bg = TextureRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.z_index = -10   # 오라 발광(z=-1)이 배경 위·드래곤 아래에 오도록 배경을 뒤로.
	add_child(_bg)

# 존재하는 wall 스킨 번호(480/scene/cave/wall). 2~7은 에셋 없음 → 기본 1로 폴백.
const WALL_SKINS := [1, 8, 9, 10, 11, 12, 13, 14, 15]

## 테마(cave_skin) 인덱스와 같은 번호의 wall을 쓴다. 없으면 기본 wall 1.
func _wall_number_for_theme() -> int:
	var theme_num := UserDB.get_skin("cave_skin") + 1   # cavebg{N}
	return theme_num if theme_num in WALL_SKINS else 1

func _build_walls() -> void:
	# 동굴 벽 프레임 (480/scene/cave/wall). 테마와 같은 번호의 wall을 적용. 원작 768x519 기준 → 높이맞춤.
	if _walls == null:
		_walls = Node2D.new()
		add_child(_walls)
	for ch in _walls.get_children():
		ch.queue_free()
	var man := {}
	var f := FileAccess.open("res://assets/converted/wall_ui/_manifest.json", FileAccess.READ)
	if f: man = JSON.parse_string(f.get_as_text())
	const S := 692.0 / 519.0   # 원작 wall 원본높이(519) → 692 고정높이에 맞춤
	var vis := _vis()
	var dir := "res://assets/converted/wall_ui/%s.tres"
	var wn := _wall_number_for_theme()
	var ln := "scene_cave_wall_%d_wall_left" % wn
	var rn := "scene_cave_wall_%d_wall_right" % wn
	var bn := "scene_cave_wall_%d_wall_bottom" % wn
	# 레시피 §1b: 벽을 화면 가장자리에 앵커 → 어떤 폭에서도 테두리를 감싼다(절대좌표 금지).
	_wall(dir % ln, man.get(ln, {}), S, func(dw, _dh): return Vector2(dw / 2.0, vis.y / 2.0))
	_wall(dir % rn, man.get(rn, {}), S, func(dw, _dh): return Vector2(vis.x - dw / 2.0, vis.y / 2.0))
	_wall(dir % bn, man.get(bn, {}), S, func(_dw, dh): return Vector2(vis.x / 2.0, vis.y - dh / 2.0))

func _wall(path: String, info: Dictionary, s: float, place: Callable) -> void:
	if not ResourceLoader.exists(path): return
	var spr := Sprite2D.new()
	spr.texture = load(path)
	spr.material = _pma
	spr.scale = Vector2(s, s)   # 회전 보정 불필요 — 변환 단계가 흡수(fix_rotated_frames.py)
	var dw: float = float(info.get("w", 0)) * s
	var dh: float = float(info.get("h", 0)) * s
	spr.position = place.call(dw, dh)
	_walls.add_child(spr)

func _build_stage() -> void:
	var vis := _vis()
	_stage = Node2D.new()
	# 받침대+드래곤 내부는 1080공간 그대로 두고 컨테이너만 스케일(내부 좌표 무변경).
	_stage.scale = Vector2(S1080, S1080)
	# 레시피 §1: 받침대 위 큰 드래곤이 화면 중앙 주역. ASSUMPTION: 미세 y는 F5로 보정.
	_stage.position = Vector2(vis.x / 2.0, vis.y / 2.0 - 8.0)
	add_child(_stage)
	# 드래곤 클릭 영역(투명) — 클릭 시 love(터치) 모션 재생 후 wait 복귀
	var btn := Button.new()
	btn.flat = true
	var bs := 320.0 * S1080
	btn.size = Vector2(bs, bs)
	btn.position = Vector2(vis.x / 2.0 - bs / 2.0, vis.y / 2.0 - bs / 2.0 - 26.0)   # ASSUMPTION: 드래곤 몸통 위치에 맞춰 F5 보정
	btn.pressed.connect(_on_dragon_clicked)
	add_child(btn)

## 좌측 둥지 목록 — 원작 `CaveScene::setLeftWallLayer` + `addScroll` 1:1.
##
## 원작 구조: 목록 스크롤뷰는 **좌측 벽 스프라이트의 자식**이다
## (`setLeftWallLayer`: `leftWall->addChild(scrollView)`) — 그래서 초상이 항상 벽보다 앞에 그려지고,
## 하단 벽(`init` 에서 `addChild(bottomWall, z=1)`)만 목록의 아래쪽을 덮는다.
## 우리는 `_build_walls()` 를 먼저 붙이고 이 목록을 뒤에 붙여 같은 그리기 순서를 만든다
## (Godot 형제 노드는 트리 순서대로 그린다). 벽 테마를 바꿔도 `_walls` 노드는 재사용되므로 순서 유지.
##
## 뷰 크기 = `CCSize(110, leftWall.h - 100*bottomWall.scale)`, 위치 = `(0, 100*bottomWall.scale)`
## → 폭 **110pt**, 화면 왼쪽 끝에서 시작해 **바닥에서 100pt** 위까지. (우리 하단 벽은 4/3 고정 배율
## 이라 원작의 `100*scale` 이 그대로 100pt 에 해당한다: 원작 100/148 × 벽높이 = 0.676×148 = 100)
const LIST_W := 110.0        # 원작 setLeftWallLayer: CCSize(110, …)
const LIST_BOTTOM := 100.0   # 원작: 하단 벽 위 100pt 부터
const LIST_TOP_PAD := 15.0   # 원작 addScroll: 첫 셀은 뷰 상단 -15pt
const SLOT_GAP := 5.0        # 원작 addScroll: 셀 간격 (h + 5.0)

func _build_dragon_list() -> void:
	var vis := _vis()
	var sc := ScrollContainer.new()
	# ⚠️ 종전엔 슬롯을 1080공간으로 그리고 컨테이너를 150×S1080(=96pt)으로 잡아, **176단위(=113pt)
	#    슬롯이 96pt 뷰에 잘려** 초상 오른쪽이 벽에 파묻힌 것처럼 보였다(사용자 보고 2026-07-30).
	#    원작 수치(110pt 뷰 / 113pt 셀박스 · 액자 108pt×0.95)로 옮겨 잘림을 없앤다 — 슬롯도 디자인 포인트로 작성.
	sc.position = Vector2(0.0, LIST_TOP_PAD)
	sc.custom_minimum_size = Vector2(LIST_W, maxf(120.0, vis.y - LIST_BOTTOM - LIST_TOP_PAD))
	sc.size = sc.custom_minimum_size
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER   # 원작 CCScrollView 는 막대 없음
	add_child(sc)
	_left_wall = sc   # toggleSideWalls: 좌측 벽(드래곤 목록) 슬라이드 대상
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", SLOT_GAP)
	sc.add_child(_list_box)

var _name_label: RichTextLabel
var _grade_label: Label
var _bottom_bar: Control            # 하단바 컨테이너 — 도감이 열려 있는 동안 숨김(원작 setBottomElement)

func _build_bottom_bar() -> void:
	# 🟠 2026-07-26 정정: 여기 있던 **황금색 StyleBoxFlat 배너는 자작**이었다
	#   (주석도 "cave.png에 전용 에셋이 없어 직접 제작"이라고 인정하고 있었다).
	#   원작(docs/ref/orig_image/cave/Cave.png)의 하단 바 배경은 별도 패널이 아니라 **동굴 돌벽**이다 —
	#   `scene/cave/wall/{N}/wall_bottom.png`(우리도 이미 _build_walls에서 그리고 있다).
	#   그 위에 어두운 라운드 9patch 판들(이름칸/스탯칸/슬롯)만 얹힌다.
	#   → 배너를 투명 Control로 바꿔 돌벽이 그대로 보이게 한다.
	var bar := Control.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 하단바 자식들(등급/이름/스탯/탭)은 1864폭 공간으로 작성 → 화면 폭에 맞춰 컨테이너째 스케일.
	var vis := _vis()
	var bs := (vis.x - 24.0) / 1864.0
	bar.size = Vector2(1864, 150)
	bar.scale = Vector2(bs, bs)
	bar.position = Vector2(12, vis.y - 150.0 * bs - 6.0)
	add_child(bar)
	_bottom_bar = bar   # 도감(setBottomElement)이 하단을 교체하는 동안 통째로 숨긴다

	# 등급 수치 — 원작 Cave.png 좌하단은 **원형 배지 없이 주황 숫자("6.9")만** 있다.
	# 자작 원형 Panel(StyleBoxFlat)을 제거하고 텍스트만 남긴다.
	var badge := Control.new()
	badge.position = Vector2(20, 40); badge.size = Vector2(84, 84)
	bar.add_child(badge)
	_grade_label = Label.new()
	_grade_label.size = Vector2(84, 84)
	_grade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_grade_label.add_theme_font_size_override("font_size", 34)
	_grade_label.add_theme_color_override("font_color", Color(1.0, 0.62, 0.12))
	_grade_label.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.0, 0.9))
	_grade_label.add_theme_constant_override("outline_size", 5)
	_grade_label.position = Vector2(0, 0)
	badge.add_child(_grade_label)
	# 원작 성급 별 아이콘(common/btn_star, CCZ복호로 확보) — 배지 상단.
	var cf := FileAccess.open("res://assets/converted/common_ui/_manifest.json", FileAccess.READ)
	var cm: Dictionary = JSON.parse_string(cf.get_as_text()) if cf else {}
	var star := _atlas_sprite("common_ui", "common_btn_star", cm, 0.7)
	if star: star.position = Vector2(42, 16); badge.add_child(star)
	# 배지 클릭 → 진화 상세(baby/child/adult).
	var hit := Button.new(); hit.flat = true; hit.size = Vector2(84, 84)
	hit.pressed.connect(_open_dragon_detail); badge.add_child(hit)

	# 속성 아이콘 (별 대신) + 이름/레벨 — 원작 setBottomElement(element_bg 배경 + 상성 클릭).
	var ebg := _atlas_sprite("common_ui", "common_element_bg", cm, 0.62)
	if ebg: ebg.position = Vector2(146, 32); bar.add_child(ebg)
	_elem_icon = Sprite2D.new()
	_elem_icon.material = _pma
	_elem_icon.position = Vector2(146, 32)
	bar.add_child(_elem_icon)
	var ehit := Button.new(); ehit.flat = true; ehit.size = Vector2(56, 56)
	ehit.position = Vector2(118, 4); ehit.pressed.connect(_open_element_info)
	bar.add_child(ehit)
	# 이름 칸 배경 — 원작 Cave.png 의 어두운 라운드 바(9patch/train_box3).
	var nplate := NinePatchRect.new()
	nplate.texture = load("res://assets/converted/ninepatch_ui/9patch_train_box3.tres")
	nplate.patch_margin_left = 30; nplate.patch_margin_right = 30
	nplate.patch_margin_top = 16; nplate.patch_margin_bottom = 16
	nplate.size = Vector2(452, 48); nplate.position = Vector2(180, 10)
	nplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(nplate)
	_name_label = RichTextLabel.new()
	_name_label.bbcode_enabled = true
	_name_label.fit_content = true
	_name_label.scroll_active = false
	# 이름 문자열은 이름 칸(nplate) **정중앙**에 온다 — 좌우는 판과 같은 폭 + [center],
	# 상하는 판 중심(10+48/2=34)에 글자 높이(≈40)의 절반을 뺀 y=14 에서 시작한다.
	# (RichTextLabel 에는 수직 정렬 속성이 없어 시작 y 로 맞춘다.)
	_name_label.position = Vector2(180, 14)
	_name_label.size = Vector2(452, 44)
	_name_label.add_theme_font_size_override("normal_font_size", 30)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 클릭은 아래 히트박스가 받는다
	bar.add_child(_name_label)
	# 원작 onClickNicName: **하단 이름 칸을 터치**하면 이름 재설정(상단에 별도 버튼 없음).
	var nhit := Button.new()
	nhit.flat = true
	nhit.position = Vector2(180, 10); nhit.size = Vector2(452, 48)
	nhit.tooltip_text = "이름 바꾸기"
	nhit.pressed.connect(_open_rename)
	bar.add_child(nhit)
	# 원작(docs/ref/orig_image/cave/Cave.png): 생명력/공격력/방어력이 **각각 라운드 플레이트**에 들어가고
	# 라벨이 위, 값이 아래에 온다(인라인 텍스트 한 줄이 아니다).
	# 프레임 = 원작 `9patch/train_box4`(어두운 라운드 판 + 옅은 테두리). 돌벽 위에 얹히므로
	# 밝은 `box1`이 아니라 어두운 판이어야 레퍼런스와 같다(Cave.png의 생명력/공격력/방어력 칸).
	var stat_defs := [["hp", "생명력"], ["att", "공격력"], ["def", "방어력"]]
	for i in stat_defs.size():
		var key: String = stat_defs[i][0]
		var plate := NinePatchRect.new()
		plate.texture = load("res://assets/converted/ninepatch_ui/9patch_train_box4.tres")
		plate.patch_margin_left = 22; plate.patch_margin_right = 22
		plate.patch_margin_top = 16; plate.patch_margin_bottom = 16
		plate.size = Vector2(196, 84)
		plate.position = Vector2(112 + i * 206, 62)
		bar.add_child(plate)
		var cap := Label.new()
		cap.text = String(stat_defs[i][1])
		cap.add_theme_font_size_override("font_size", 19)
		cap.add_theme_color_override("font_color", Color(0.92, 0.90, 0.82))
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.size = Vector2(196, 24); cap.position = Vector2(0, 6)
		plate.add_child(cap)
		var val := Label.new()
		val.name = "val"
		val.add_theme_font_size_override("font_size", 26)
		val.add_theme_color_override("font_color", Color.WHITE)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.size = Vector2(196, 34); val.position = Vector2(0, 34)
		plate.add_child(val)
		_stat_plates[key] = val

	var lv := Button.new()
	lv.text = "훈련"
	lv.position = Vector2(1786, 10); lv.size = Vector2(64, 36)
	lv.pressed.connect(_open_training_select)   # 원작 TrainingSelectLayer
	bar.add_child(lv)


	# 장착 슬롯 — 원작 `CaveScene::setDragonInfo` 복원(2026-07-27).
	# 상세 근거·좌표·클릭동작 = docs/ref/porting/CaveBottomSlots.md
	# ⚠️ 원작은 드래곤이 바뀌거나 장착이 변할 때마다 `setDragonInfo()` **전체를 다시 부른다**
	#    (changeDragon·onClickDragon·setClosedGem/SkillPopup·sResult* 등 12곳에서 호출).
	#    그래서 슬롯은 전용 레이어에 담고 `_refresh()` 마다 통째로 다시 그린다 —
	#    한 번만 그리면 해제/장착·드래곤 변경이 씬을 나갔다 와야 반영된다(사용자 보고 2026-07-27).
	_slot_layer = Control.new()
	_slot_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot_layer.size = bar.size
	bar.add_child(_slot_layer)
	_refresh_slots()

## 실스탯 = 성장 누적치 + 장착 젬(flat → % → 부가확률) + 장비(4칸 + 편린 세트).
## **battle.gd `_setup_party` 와 같은 산출식·같은 순서**여야 표시값과 전투값이 일치한다.
## 젬/장비 집계는 로직 계층(Gem/Equipment)이 하고 여기선 표시만 한다(§8.2).
##
## ⚠️ 구현정정 (2026-07-27) 두 건:
##  1) 이전 `_bonus_with_gems` 는 젬을 stat_bonus 최상위 키에 더했는데 Growth._effective 는
##     stat_bonus["base"]/["growth"] 만 읽어서 **젬이 전혀 반영되지 않았다**.
##  2) 기준 성장치를 `Growth.compute_stats`(선형 base+growth×(L−1))로 뽑고 있었는데,
##     그 모델은 game_design.md §K-1 정정(2026-07-26)에서 **부정확**으로 폐기됐다
##     (growth 는 레벨당 고정치가 아니라 **최대 상승량**, 실제 상승은 [1,max] 랜덤 롤).
##     같은 화면의 HUD 스탯판(_refresh_stats)과 전투(battle.gd)는 이미 `main_stats`
##     (= base + 영구base보정 + Σgain_log)를 쓰고 있어서, **상세창만 다른 숫자**를 보여 줬다.
##     (실측: 치킨헤드 Lv.7 → 상세창 HP 277 / 전투 237)  ⇒ main_stats 로 통일.
## level 인자는 이제 기준치 산출에 쓰지 않는다(gain_log 가 레벨 이력을 담는다) — 호출부 호환용.
func _stats_with_gems(a: Dictionary, _level: int) -> Dictionary:
	var base_bonus: Dictionary = (a.get("stat_bonus", {}) as Dictionary).get("base", {})
	var st: Dictionary = Growth.main_stats(
		Data.get_dragon(int(a.get("id", 0))), Data.stat_table, a.get("gain_log", []), base_bonus)
	st = Gem.apply(st, a.get("gems", {}), Data.gems)
	return Equipment.apply(st, a.get("equip", {}), Data.equipment)

## 장착 젬 슬롯 목록(구형 저장분 자동 정규화). [{name, tier}, …]
func _gem_slots(a: Dictionary) -> Array:
	return Gem.slots(a.get("gems", {}))

## 젬 장착: 타입이 맞는 빈 칸을 찾아 장착. 실패 시 false.
## 원작에도 두 경로가 있다 — 칸을 먼저 누르면 그 칸(`onClickGem` → `equip_at`),
## 가방에서 고르면 맞는 칸을 찾는다(여기).
func _equip_gem(uid: int, gem_name: String, tier: int) -> bool:
	var d := UserDB.get_dragon(uid)
	var next: Dictionary = Gem.equip(d.get("gems", {}), gem_name, tier, Data.gems)
	if next.is_empty(): return false
	UserDB.set_dragon_field(uid, "gems", next)
	return true

## 🔴 제거(2026-07-30): `_equip_gem_at`(칸 지정 장착). 칸을 먼저 고르는 UI(자작 젬선택 팝업)를
##   폐기하면서 호출부가 사라졌다. 칸 지정 규칙 자체는 `Gem.equip_at`(logic, 단위테스트 있음)에
##   그대로 있으니 원작 `GemsPopup` 을 제대로 이식할 때 다시 감으면 된다.

## 가방 젬 탭의 "장착" — 원작 `BagPopup::onClickConfirm` case 2(= 젬 탭) 1:1.
## 포팅 카드 = `docs/ref/porting/GemEquipFlow.md`.
##
## 원작은 **여기서 장착을 끝낸다** — 젬 목록을 다시 띄우지 않는다. 슬롯 0→2 를 훑어
## 빈 칸(`Dragon::getItemGem(i)==0`) 중 젬 계열이 칸 타입(`getGemType(i)`)과 맞는(또는 칸이
## ALL=3) 첫 칸에 넣고(= `Gem.fit_slot`), 성공하면 젬을 1개 소모한 뒤 토스트를 띄우고
## 가방을 닫는다(`serverResult` case 2 @BagPopup.c:22292 — delItem → setItemGem → showToast →
## 이벤트 리스너 → `PopupLayer::close`).
##
## 실패 안내는 원작 그대로 **모달**이다(`PopupTypeLayer` + `CaveGemEuqipMsg2`). 단 원작은
## 3칸이 다 차 있으면 빈 칸 조건에 전부 걸려 **아무 반응도 없다** — 문자열 `CaveGemEuqipMsg3`
## 이 남아 있는데도 쓰이지 않는다. 그 침묵은 버그로 보고 토스트로 알린다(사용자 확정 2026-07-30).
func _equip_gem_from_bag(item_key: String) -> void:
	var g := Gem.parse_item_key(item_key)
	if g.is_empty(): return
	var a := _active()
	if a.is_empty():
		_toast("젬을 장착할 드래곤이 없습니다"); return
	var uid := int(a["uid"])
	if UserDB.item_count(item_key) <= 0:
		_toast("보유하지 않은 젬입니다"); return
	var gem_name := String(g["name"])
	var tier := int(g["tier"])
	if Gem.all_full(UserDB.get_dragon(uid).get("gems", {})):
		_toast("젬 슬롯이 모두 사용 중입니다"); return
	if not _equip_gem(uid, gem_name, tier):
		# 원작 CaveGemEuqipMsg2 — 빈 칸은 있는데 계열이 안 맞는 경우.
		_open_popup_type("젬 장착", "선택한 젬과 맞는 슬롯이 없습니다.", func(): pass, "확인", "")
		return
	UserDB.use_item(item_key, 1)
	_refresh_stats()
	_close_overlay()      # 원작 PopupLayer::close — 장착하면 가방이 닫힌다
	_refresh()
	_toast("젬을 장착하였습니다")   # 원작 CaveToastMsg5

## ⚠️ 젬 **강화·승급·복구·연금술은 점술집(MagicShopScene) 전용**이다 — 사용자 확정 2026-07-27.
##   원작 동굴 젬 칸(`onClickGem`)은 **장착/해제만** 한다. 강화 레이어들(GemCraftLayer ·
##   UpgradeGemLayer · UpgradeSoulGemLayer · AlchemyLayer)은 전부 MagicShopScene 이 만든다
##   (`MagicShopScene::onClickAlchemyItem`). 여기 있던 `_open_gem_craft` / `_open_potion_select` /
##   `_craft_gem` / `_repair_gem` / `_add_potion` / `_promote_gem` 는 `scripts/ui/magicshop.gd` 로
##   옮겼다(로직은 그대로 `Gem` 이 소유하므로 계산은 한 곳뿐이다).

## 젬 1줄 표기 = **원작 이름** + 강화 단계 + 위키 툴팁 효과.
##   예) `체력의 젬 +28  [자갈]  체력 +28`
##       `공격의 소울젬 +3  [3단계]  공격력 +30, 공격력 +7%, 크리티컬 확률 +1%`
## 이름 양식·효과 문구는 Gem(logic)이 소유한다 — 화면마다 다르게 찍지 않는다.
func _gem_line(gem_name: String, tier: int) -> String:
	return "%s  [%s]  %s" % [
		Gem.display_name(gem_name, tier, Data.gems),
		Gem.shape_label(gem_name, tier, Data.gems),
		Gem.effect_text(gem_name, tier, Data.gems)]

func _gold_str(g: int) -> String:
	if g >= 10000: return "%d만G" % int(g / 10000.0)
	return "%dG" % g

## 젬 해제 → **인벤토리로 돌려준다**(현재 티어 그대로). slot = 칸 index(0..2).
## 원작은 `CaveGemUnEuqipMsg` 대로 [우편함]으로 지급하는데 우편함은 온라인이라 §1 CUT → 인벤.
func _unequip_gem(uid: int, slot: int) -> void:
	var en := Gem.entries(UserDB.get_dragon(uid).get("gems", {}))
	if slot >= 0 and slot < Gem.SLOTS and en[slot] != null:
		UserDB.add_item(Gem.item_key(String(en[slot]["name"]), int(en[slot]["tier"])), 1)
	UserDB.set_dragon_field(uid, "gems", Gem.unequip_at(UserDB.get_dragon(uid).get("gems", {}), slot))

## 장착 젬 전량 해제 후 인벤 반환. 반환 개수를 돌려준다('샌즈의 비약'·'젬슬롯 초기화'용).
func _return_all_gems(uid: int, gems_field: Dictionary) -> int:
	var n := 0
	for e in Gem.entries(gems_field):
		if e != null:
			UserDB.add_item(Gem.item_key(String(e["name"]), int(e["tier"])), 1)
			n += 1
	if n > 0:
		UserDB.set_dragon_field(uid, "gems",
			{"types": Gem.types(gems_field), "slots": [null, null, null]})
	return n

## 동굴 하단 **빈 젬 칸** 클릭 → 가방 '젬' 탭. 사용자 확정 2026-07-30 (2차 지적).
##
## ⚠️ 디컴프한 후기판 클라는 다르다: `CaveScene::setBottomWallLayer` 가 3칸(`9patch/bg_common`
##   70×70, tag=0..2)에 `onClickGem` 을 달고, 그 핸들러가 칸 타입으로 필터한 **`GemsPopup`**
##   (`create("ATT"|"DEF"|"HP"|"ALL")` + `setSelectTag(slot)`)을 띄운다. 그런데 우리가 그 자리에
##   갖고 있던 것은 `GemsPopup` 이 아니라 **평범한 버튼 목록 자작본**이었다(원작은 `9patch/scroll_box`
##   + `CCTableView` 좌측 목록 / 우측 350×420 상세 패널 + `9patch/text_box` + `RoundedButton` 2단 구성).
##   사용자 기억은 "젬 선택 창이 따로 없고 가방 젬 탭으로 연동" 이고, 반복 확정했다 ⇒ 자작 팝업을
##   지우고 **가방 젬 탭 하나로 통일**한다. 젬 UI 진입점이 이제 하나뿐이다.
##   원작 GemsPopup 을 제대로 이식하려면 레시피는 `docs/ref/porting/GemEquipFlow.md` §2 에 남겨 뒀다.
func _open_gem_tab() -> void:
	if _active().is_empty(): return
	_inv_tab = "gem"
	_inv_selected = ""
	_open_inventory()

## 장비 스탯키 → 한글 라벨(원작 위키 §2.1 효과표 표기).
func _equip_stat_kr(key: String) -> String:
	return {
		"hp": "HP", "att": "공", "def": "방", "blk": "막기", "evd": "회피", "cri": "크리",
		"cri_pow": "크파", "pure": "관통", "depure": "관통감소", "accuracy": "명중",
		"cure": "치유", "awaken_rate": "각성", "gold": "골드", "exp": "경험",
	}.get(key, key)

## 장비 관리 — 원작 4칸(전체/전투형/보조형/아티팩트) + 편린 3칸.
## 원작 근거: 슬롯 종류=위키 §2 표, 칸 해금=연구소 '드래곤 강화'(위키 §2.1.1).
## ⚠️ 원작은 인벤토리의 실제 장비 아이템을 낀다(MultyEquipPop/ItemEquipSelectPopup). 우리는 장비 인벤토리가
##    아직 없어 카탈로그에서 바로 장착한다 — 인벤토리 도입 시 이 함수가 교체 지점.
## 칸 해금은 연구소(scripts/ui/laboratory.gd 「드래곤 강화」)에서 한다 — 위키 etc.pdf §2.1.1.
## 드래곤별 해금 칸 수 = UserDB dragon["equip_slots"](기본 1칸).
func _open_equipment() -> void:
	var a := _active()
	if a.is_empty(): return
	var uid := int(a["uid"])
	const BW := 780.0
	const BH := 560.0
	var vis := _vis()
	var overlay := CanvasLayer.new(); overlay.layer = 30; add_child(overlay)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: overlay.queue_free())
	overlay.add_child(dim)
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5)); overlay.add_child(win)
	var tbar := NinePatchRect.new(); tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(BW * 0.9, 56); tbar.position = Vector2((BW - BW * 0.9) * 0.5, 14); win.add_child(tbar)
	var t := Label.new(); t.text = "장비"; t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", Color.WHITE); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; t.size = tbar.size; tbar.add_child(t)
	var cbtn := TextureButton.new(); cbtn.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	cbtn.position = Vector2(BW - 72, 8); win.add_child(cbtn)
	cbtn.pressed.connect(func(): overlay.queue_free())
	var eqf: Dictionary = UserDB.get_dragon(uid).get("equip", {})
	var slot_kr := {"all": "전체", "battle": "전투형", "support": "보조형", "artifact": "아티팩트"}
	var y := 96.0
	var unlocked = UserDB.get_dragon(uid).get("equip_slots", 1)   # v11: 배열(구세이브는 int)
	for slot_id: String in Equipment.slot_ids(unlocked):
		var box := NinePatchRect.new(); box.texture = load("res://assets/converted/ninepatch_ui/9patch_train_box3.tres")
		box.patch_margin_left = 30; box.patch_margin_right = 30; box.patch_margin_top = 12; box.patch_margin_bottom = 12
		box.size = Vector2(680, 64); box.position = Vector2((BW - 680) * 0.5, y); win.add_child(box)
		var it: Dictionary = Equipment.equipped(eqf, slot_id, Data.equipment)
		var sdata := _equip_slot_data(eqf, slot_id)
		# 원작 장비 아이콘(item/accessory — 종류·등급별). 논리키 조회는 Icons(§8.4).
		# 희귀도 실루엣 + 귀속 뱃지까지 원작 BagTableViewCell 순서로 겹쳐 그린다.
		var eicon := Icons.equip_rect(it, 40.0, int(sdata.get("grade", 0)),
				int(sdata.get("belong", 0)), uid) if not it.is_empty() else null
		if eicon: eicon.position = Vector2(14, 8); box.add_child(eicon)
		var lbl := Label.new()
		lbl.position = Vector2(62 if eicon else 20, 15)
		lbl.add_theme_font_size_override("font_size", 17)
		lbl.add_theme_color_override("font_color", Color(0.2, 0.15, 0.08))
		if it.is_empty():
			lbl.text = "[%s] 비어 있음" % slot_kr[slot_id]
		else:
			var mparts: PackedStringArray = []
			for st: String in (it.get("stat_main", {}) as Dictionary):
				mparts.append("%s+%d" % [_equip_stat_kr(st), int(it["stat_main"][st])])
			lbl.text = "[%s] %s  %s" % [slot_kr[slot_id], String(it["name"]), " ".join(mparts)]
		box.add_child(lbl)
		var sid := slot_id
		var chg := Button.new(); chg.text = "변경"; chg.size = Vector2(70, 38); chg.position = Vector2(390, 9)
		chg.pressed.connect(func(): overlay.queue_free(); _open_equip_select(sid))
		box.add_child(chg)
		if not it.is_empty():
			# 옵션(원작 info_item_acc 9종) — 현재 붙은 옵션 표시 + 재설정/강화.
			var sd := _equip_slot_data(eqf, sid)
			var opts: Array = sd.get("options", [])
			var ol := Label.new()
			var oparts: PackedStringArray = []
			for o in opts:
				oparts.append("%s+%d" % [_equip_stat_kr(String((o as Dictionary).get("stat", ""))),
						int((o as Dictionary).get("value", 0))])
			var eg := int(sd.get("grade", 0))
			var gname: String = String((Data.equipment.get("option", {}).get("grades", [])[eg] as Dictionary).get("name", "일반")) if eg < (Data.equipment.get("option", {}).get("grades", []) as Array).size() else "일반"
			# 귀속 표기 — 원작 문구 `CaveItemEquipSky`(귀속됨) / `CaveItemEquipBeing`(~의 귀속 아이템).
			var bel := int(sd.get("belong", 0))
			var btxt := ""
			if bel > 0:
				btxt = "  귀속됨" if bel == uid else "  %s의 귀속 아이템" % _dragon_label(bel)
			ol.text = "  %s  %s  [강화 %d/%d]%s" % [gname,
					("옵션 없음" if oparts.is_empty() else " ".join(oparts)),
					int(sd.get("enhance", 0)), Equipment.enhance_limit(eg, Data.equipment), btxt]
			ol.add_theme_font_size_override("font_size", 13)
			ol.add_theme_color_override("font_color", Color(0.36, 0.28, 0.14))
			ol.position = Vector2(62, 34); box.add_child(ol)
			var rr := Button.new(); rr.text = "옵션"; rr.size = Vector2(66, 38); rr.position = Vector2(464, 9)
			rr.pressed.connect(func(): _reroll_options(uid, sid); overlay.queue_free(); _open_equipment())
			box.add_child(rr)
			var en := Button.new(); en.text = "강화"; en.size = Vector2(66, 38); en.position = Vector2(534, 9)
			en.disabled = int(sd.get("enhance", 0)) >= Equipment.enhance_limit(eg, Data.equipment)
			en.pressed.connect(func(): _enhance_option(uid, sid); overlay.queue_free(); _open_equipment())
			box.add_child(en)
			var rm := Button.new(); rm.text = "해제"; rm.size = Vector2(66, 38); rm.position = Vector2(604, 9)
			rm.pressed.connect(func():
				# 해제 → 인벤토리로 돌려준다. 귀속·희귀도·옵션·강화는 **개체에 남는다** →
				# 슬롯 상태를 그대로 실은 키로 돌려보낸다(§Equipment slot_to_item_key).
				var cur: Dictionary = UserDB.get_dragon(uid).get("equip", {})
				var off := _equip_slot_data(cur, sid)
				if not off.is_empty():
					UserDB.add_item(Equipment.slot_to_item_key(off), 1)
				UserDB.set_dragon_field(uid, "equip", Equipment.unequip(cur, sid))
				_refresh_stats(); overlay.queue_free(); _open_equipment())
			box.add_child(rm)
			# 귀속해제(원작 `CaveEquip_Lift`) — 구드라의 지혜 1개를 쓴다. 귀속돼 있을 때만 보인다.
			if int(sd.get("belong", 0)) > 0:
				var ub := Button.new(); ub.text = "귀속해제"; ub.size = Vector2(96, 30)
				ub.position = Vector2(464, 30)
				ub.add_theme_font_size_override("font_size", 13)
				ub.pressed.connect(func(): _unbind_equip(uid, sid); overlay.queue_free(); _open_equipment())
				box.add_child(ub)
		y += 72.0
	# 부가 효과(특수 장비 bonus) 안내 — 조건부 효과라 전투 미반영임을 명시한다.
	var note := Label.new()
	note.text = "※ 특수 장비의 부가 효과와 전용 장비는 데이터만 보유(전투 미반영) — docs/input/review/equipment_sheet.md"
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.5, 0.44, 0.36))
	note.position = Vector2(40, BH - 74); note.size = Vector2(BW - 80, 40); note.autowrap_mode = TextServer.AUTOWRAP_WORD
	win.add_child(note)

## 귀속 표기에 쓸 드래곤 이름(닉네임 우선, 없으면 종 이름). 없는 uid 면 "다른 드래곤".
func _dragon_label(uid: int) -> String:
	var d: Dictionary = UserDB.get_dragon(uid)
	if d.is_empty():
		return "다른 드래곤"
	var nick := String(d.get("nickname", ""))
	if nick != "":
		return nick
	return String(Data.get_dragon(int(d.get("id", 0))).get("name", "드래곤"))

## slot_id 칸의 저장 슬롯 dict(옵션·등급·강화횟수 보관). 없으면 {}.
func _equip_slot_data(eqf: Dictionary, slot_id: String) -> Dictionary:
	for s in (eqf.get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) == slot_id:
			return s
	return {}

## 옵션 재설정 — 원작 `ItemEquipSelectPopup::requestRegenEquip`(문구 `EquipeSelectMsg1`
## "해당 장비의 부가 옵션을 변경하시겠습니까?"). 소모품은 **기누의 동전**이고, 위키 item.pdf 대로
## **동전 등급이 곧 결과 등급**이다(레동/유동/에동). 표 = data/equipment.json option.reroll_items.
##   · 보유한 동전 중 가장 높은 등급을 쓴다(원작은 사용자가 고르지만 칸이 하나뿐이라 단순화).
##   · 초월 동전은 추출 아이템 목록에 없어 초월 재설정은 불가(없는 아이템은 만들지 않는다).
##   · 결과가 레어(bind_grade) 이상이면 그 자리에서 귀속된다.
## ⚠️ 2026-07-29 이전에는 골드 20,000 을 받고 등급을 랜덤으로 굴렸다 — 원작과 달라서 교체했다.
func _reroll_options(uid: int, slot_id: String) -> void:
	var items: Dictionary = Data.equipment.get("option", {}).get("reroll_items", {})
	var grade := -1
	var used := ""
	for g in items:
		if UserDB.item_count(String(items[g])) > 0 and int(g) > grade:
			grade = int(g)
			used = String(items[g])
	if grade < 0:
		_toast("기누의 동전이 없습니다"); return
	if not UserDB.use_item(used, 1):
		return
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var next: Dictionary = Equipment.reroll(
		UserDB.get_dragon(uid).get("equip", {}), slot_id, grade, rng, Data.equipment, uid)
	if next.is_empty():
		UserDB.add_item(used, 1)      # 슬롯이 비어 있는 등 실패 — 동전을 돌려준다
		return
	UserDB.set_dragon_field(uid, "equip", next)
	_refresh_stats()
	var gname := String((Data.equipment.get("option", {}).get("grades", [])[grade] as Dictionary).get("name", ""))
	_toast("%s 옵션으로 변경했습니다" % gname)

## 귀속해제(원작 `CaveEquip_Lift`) — '구드라의 지혜' 1개 소모. 위키 item.pdf: 상점 20다이아,
## "사용 시 귀속 아이템을 1회 해제시킬 수 있다".
func _unbind_equip(uid: int, slot_id: String) -> void:
	var key := String(Data.equipment.get("option", {}).get("unbind_item", "item_disconnect"))
	if UserDB.item_count(key) <= 0:
		_toast("구드라의 지혜가 없습니다"); return
	var next: Dictionary = Equipment.unbind(UserDB.get_dragon(uid).get("equip", {}), slot_id)
	if next.is_empty():
		_toast("귀속되지 않은 아이템입니다"); return      # 원작 문구 CaveItemEquipMsg12
	if not UserDB.use_item(key, 1):
		return
	UserDB.set_dragon_field(uid, "equip", next)
	_toast("귀속을 해제했습니다")

const ENHANCE_COST := 8000
func _enhance_option(uid: int, slot_id: String) -> void:
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var next: Dictionary = Equipment.enhance(
		UserDB.get_dragon(uid).get("equip", {}), slot_id, rng, Data.equipment)
	if next.is_empty():
		_toast("더 강화할 수 없습니다"); return
	if not UserDB.spend("gold", ENHANCE_COST):
		_toast("골드가 부족합니다 (%d)" % ENHANCE_COST); return
	UserDB.set_dragon_field(uid, "equip", next)
	_refresh_stats()

## 장비 선택 — 원작 EQUIP 탭/MultyEquipPop 대응: **보유 장비**(인벤 `equip:` 키) 중
## 그 칸에 낄 수 있는 것만 나열. 장착하면 인벤에서 1개 빠지고, 해제하면 돌아온다.
## (2026-07-27 이전엔 카탈로그 111종을 공짜로 골라 끼웠다 — 보유 개념이 없었다.)
func _open_equip_select(slot_id: String) -> void:
	var a := _active()
	if a.is_empty(): return
	var uid := int(a["uid"])
	const BW := 720.0
	const BH := 560.0
	var vis := _vis()
	var overlay := CanvasLayer.new(); overlay.layer = 31; add_child(overlay)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: overlay.queue_free(); _open_equipment())
	overlay.add_child(dim)
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5)); overlay.add_child(win)
	var tbar := NinePatchRect.new(); tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(BW * 0.9, 56); tbar.position = Vector2((BW - BW * 0.9) * 0.5, 14); win.add_child(tbar)
	var slot_kr := {"all": "전체", "battle": "전투형", "support": "보조형", "artifact": "아티팩트"}
	var t := Label.new(); t.text = "%s 칸 장비 선택" % slot_kr.get(slot_id, slot_id)
	t.add_theme_font_size_override("font_size", 23); t.add_theme_color_override("font_color", Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size = tbar.size; tbar.add_child(t)
	var cbtn := TextureButton.new(); cbtn.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	cbtn.position = Vector2(BW - 72, 8); win.add_child(cbtn)
	cbtn.pressed.connect(func(): overlay.queue_free(); _open_equipment())
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 86); scroll.size = Vector2(BW - 80, BH - 130); win.add_child(scroll)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 3)
	col.custom_minimum_size.x = BW - 100; scroll.add_child(col)
	var cat: Dictionary = Equipment.catalog(Data.equipment)
	var group_kr := {"basic": "일반 장비", "event": "이벤트 장비", "artifact": "아티팩트",
		"special:skull": "해골요새 장비", "special:balrog": "발록 장비", "special:fiod": "피오드 장비"}
	# 보유 장비만 후보다. ⚠️ 이제 **개체 단위**로 나열한다 — 같은 깃털이라도 희귀도·옵션·귀속이
	# 다르면 인벤 키가 다르고 성능도 다르기 때문이다(§Equipment 인벤 키 규약).
	var rows_all: Array = []        # [{ik, n, cat_item, meta}]
	for ik in UserDB.inventory().keys():
		var ck := Equipment.parse_item_key(String(ik))
		var n := int(UserDB.inventory()[ik])
		if ck == "" or n <= 0 or not cat.has(ck):
			continue
		var it0: Dictionary = cat[ck]
		if not Equipment.can_equip(it0, slot_id):
			continue
		rows_all.append({"ik": String(ik), "n": n, "it": it0,
			"meta": Equipment.item_key_meta(String(ik))})
	# 좋은 것부터: 희귀도 내림차순 → 이름
	rows_all.sort_custom(func(a, b):
		var ra := int((a["meta"] as Dictionary).get("rarity", 0))
		var rb := int((b["meta"] as Dictionary).get("rarity", 0))
		if ra != rb:
			return ra > rb
		return String((a["it"] as Dictionary)["name"]) < String((b["it"] as Dictionary)["name"]))
	var grades: Array = Data.equipment.get("option", {}).get("grades", [])
	var listed := 0
	for grp: String in ["basic", "special:balrog", "special:fiod", "special:skull", "event", "artifact"]:
		var rows: Array = []
		for r in rows_all:
			if String(((r as Dictionary)["it"] as Dictionary).get("group", "")) == grp:
				rows.append(r)
		if rows.is_empty(): continue
		listed += rows.size()
		var hdr := Label.new(); hdr.text = String(group_kr.get(grp, grp))
		hdr.add_theme_font_size_override("font_size", 17)
		hdr.add_theme_color_override("font_color", Color(0.35, 0.28, 0.12)); col.add_child(hdr)
		for r: Dictionary in rows:
			var it: Dictionary = r["it"]
			var meta: Dictionary = r["meta"]
			var bel := int(meta.get("belong", 0))
			var rar := int(meta.get("rarity", 0))
			var mparts: PackedStringArray = []
			if rar > 0 and rar < grades.size():
				mparts.append(String((grades[rar] as Dictionary).get("name", "")))
			for st: String in (it.get("stat_main", {}) as Dictionary):
				mparts.append("%s+%d" % [_equip_stat_kr(st), int(it["stat_main"][st])])
			for o in (meta.get("options", []) as Array):
				mparts.append("%s+%d" % [_equip_stat_kr(String((o as Dictionary).get("stat", ""))),
					int((o as Dictionary).get("value", 0))])
			if String(it.get("artifact_effect", "")) != "":
				mparts.append(String(it["artifact_effect"]))
			var usable := Equipment.belong_allows(bel, uid)
			var tail := "×%d" % int(r["n"])
			if not usable:
				# 원작 CaveItemEquipMsg5 "다른 드래곤에게 귀속된 아이템입니다"
				tail += "  (%s 귀속)" % _dragon_label(bel)
			var b := Button.new()
			b.text = "        %s   %s   %s" % [String(it["name"]), " ".join(mparts), tail]
			b.custom_minimum_size = Vector2(0, 38); b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.disabled = not usable
			var licon := Icons.equip_rect(it, 32.0, rar, bel, uid)
			if licon: licon.position = Vector2(3, 3); b.add_child(licon)
			var k := String(it["key"])
			var inst_key := String(r["ik"])
			b.pressed.connect(func():
				# 같은 장비라도 개체(귀속·희귀도·옵션)가 다르면 **다른 인벤 키**다.
				# 이 줄은 그 개체 하나를 가리킨다.
				var use_key := inst_key
				if UserDB.item_count(use_key) <= 0:
					_toast("보유하지 않은 장비입니다"); return
				# 그 칸에 이미 끼어 있던 장비는 인벤으로 되돌린다(교체 = 스왑). 개체 정보는 따라간다.
				var cur: Dictionary = UserDB.get_dragon(uid).get("equip", {})
				var prev := _equip_slot_data(cur, slot_id)
				var next: Dictionary = Equipment.equip(
					cur, slot_id, k, Data.equipment, Equipment.item_key_meta(use_key))
				if next.is_empty():
					_toast("이 칸에는 낄 수 없는 장비입니다")
					return
				UserDB.use_item(use_key, 1)
				if not prev.is_empty():
					UserDB.add_item(Equipment.slot_to_item_key(prev), 1)
				UserDB.set_dragon_field(uid, "equip", next)
				_refresh_stats(); overlay.queue_free(); _open_equipment())
			col.add_child(b)
	if listed == 0:
		var none := Label.new()
		none.text = "이 칸에 낄 수 있는 보유 장비가 없습니다."
		none.add_theme_font_size_override("font_size", 18)
		none.add_theme_color_override("font_color", Color(0.45, 0.38, 0.28))
		col.add_child(none)

## 장신구(data/accessories.json): 깃털/발톱/부적 → cri/evd/blk. 등급=드래곤 등급 근사.
## ⚠️ 구형 — Equipment(data/equipment.json)로 대체됐다. 기존 세이브 호환용으로만 남긴다.
var _acc_data: Dictionary = {}
func _acc_def(type_key: String) -> Dictionary:
	if _acc_data.is_empty():
		var f := FileAccess.open("res://data/accessories.json", FileAccess.READ)
		if f: _acc_data = JSON.parse_string(f.get_as_text())
	return _acc_data.get("types", {}).get(type_key, {})

func _equip_accessory(uid: int, type_key: String) -> void:
	var ad := _acc_def(type_key)
	if ad.is_empty(): return
	var lv := int(UserDB.get_dragon(uid).get("level", 1))
	var grade := clampi(lv / 8, 0, 6)   # 레벨→등급 근사(7등급)
	var grades: Array = ad.get("grades", [])
	if grades.is_empty(): return
	var acc: Dictionary = UserDB.get_dragon(uid).get("accessory", {}).duplicate()
	acc[String(ad["stat"])] = int(grades[clampi(grade, 0, grades.size() - 1)])
	UserDB.set_dragon_field(uid, "accessory", acc)

func _unequip_accessory(uid: int) -> void:
	UserDB.set_dragon_field(uid, "accessory", {})

## 상태창 — 원작 `StatusLayer` 이식. 구현체는 `scripts/ui/status_layer.gd`(어느 씬에서든 뜨는
## 독립 CanvasLayer)로 뽑아냈다. 포팅 카드 = `docs/ref/porting/StatusLayer.md`.
##
## 🔴 원작 진입점은 **메인 화면(월드맵/마을)의 프로필 버튼**이다 — `CaveScene` 은 상태창을 열지
##   않는다(`WorldMapScene::onClickMenu` tag 0xb · `TownMainMenuLayer::onClickMenu` tag 0x2bd).
##   종전에는 팝업이 여기 박혀 있어서 **동굴로 이동해야만** 열렸다. 이제 `MainHud` 가 제자리에서
##   띄우고, 동굴은 아래처럼 같은 컴포넌트를 쓰되 심화 편집을 제자리에서 처리한다.
func _open_dragon_detail() -> void:
	var l := StatusLayer.open(self)
	l.action_requested.connect(_on_status_action)
	l.closed.connect(func():
		if is_inside_tree(): _refresh(); _refresh_stats())

## 상태창의 슬롯/버튼 → 동굴이 이미 가진 팝업으로 연결(원작 `setClickInfo` 자리).
func _on_status_action(action: String, arg: int) -> void:
	match action:
		"rename": _open_rename()
		"equip": _open_equipment()
		"gem":
			# 빈 칸이면 가방 '젬' 탭, 찬 칸이면 해제 확인(원작 onClickGemDelete).
			var a := _active()
			var en := Gem.entries(a.get("gems", {})) if not a.is_empty() else []
			if arg >= 0 and arg < en.size() and en[arg] != null: _confirm_unequip_gem(arg)
			else: _open_gem_tab()
		"skill": _open_skill_select(maxi(arg, 0))
		"awaken_skill": _open_awaken_skill()
		"levelup": _open_levelup()
		"awaken_dex": _open_awaken_dex()
		"skin": _open_dragon_skin()
		"storage": _open_dragon_storage()


## 원작 ItemSelectLayer 1:1: 아이템 선택 picker — popup4 + scroll_box + text_box(설명) + 아이템 셀(item_bg + 아이콘 + 수량)
## + onClickItem(선택)/onClickOk. 근거: ItemSelectLayer.c init(popup4)+initWidget(scroll_box+text_box+CCTableView)
## +onClickItem/setSelectedItem/setExplainInfo/onClickOk. 재사용 컴포넌트(제작 재료·사용 대상 아이템 선택).
## category="": 전체. on_select(key) 콜백.
func _open_item_select(title: String, on_select: Callable, category := "") -> void:
	_open_backdrop(0.55)
	var vis := _vis()
	var BW := clampf(vis.x - 120.0, 640.0, 900.0)
	var BH := clampf(vis.y - 80.0, 480.0, 640.0)
	var cf := FileAccess.open("res://assets/converted/common_ui/_manifest.json", FileAccess.READ)
	var cm: Dictionary = JSON.parse_string(cf.get_as_text()) if cf else {}
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	_overlay.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(320, 54); tbar.position = Vector2((BW - 320) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = title
	tl.add_theme_font_size_override("font_size", 26); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 66, 14); xb.pressed.connect(_close_overlay); win.add_child(xb)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 92); scroll.size = Vector2(BW - 80, BH - 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = maxi(4, int((BW - 80) / 130.0))
	grid.add_theme_constant_override("h_separation", 8); grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	var any := false
	for key in UserDB.inventory().keys():
		var k := String(key)
		if UserDB.item_count(k) <= 0: continue
		if category != "" and String(Data.get_item(k).get("category", "")) != category: continue
		any = true
		grid.add_child(_item_select_cell(k, cm, on_select))
	if not any:
		var em := Label.new(); em.text = "보유한 아이템이 없습니다."
		em.add_theme_font_size_override("font_size", 20); em.add_theme_color_override("font_color", Color(0.4, 0.3, 0.12))
		em.position = Vector2(60, 120); win.add_child(em)

func _item_select_cell(key: String, cm: Dictionary, on_select: Callable) -> Control:
	var cell := Control.new(); cell.custom_minimum_size = Vector2(120, 130)
	var bg := _atlas_sprite("common_ui", "common_item_bg", cm, 1.0)
	if bg: bg.position = Vector2(60, 56); cell.add_child(bg)
	var ip := Data.item_icon_path(key)
	if ResourceLoader.exists(ip):
		var icon := Sprite2D.new(); icon.texture = load(ip); icon.material = _pma; icon.scale = Vector2(0.6, 0.6)
		icon.position = Vector2(60, 56); cell.add_child(icon)
	var cnt := Label.new(); cnt.text = "×%d" % UserDB.item_count(key)
	cnt.add_theme_font_size_override("font_size", 15); cnt.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))
	cnt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8)); cnt.add_theme_constant_override("outline_size", 3)
	cnt.position = Vector2(72, 74); cnt.size = Vector2(44, 22); cell.add_child(cnt)
	var nm := Label.new(); nm.text = Data.item_name(key)
	nm.add_theme_font_size_override("font_size", 13); nm.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.position = Vector2(2, 98); nm.size = Vector2(116, 30); cell.add_child(nm)
	var b := Button.new(); b.flat = true; b.size = Vector2(120, 96); b.position = Vector2(0, 4)
	b.pressed.connect(func(): _close_overlay(); on_select.call(key))
	cell.add_child(b)
	return cell

## 원작 DragonSelectLayer 1:1: 드래곤 선택 picker — popup4 + scroll_box + 드래곤 셀(초상 + 스킬슬롯 모양
## common/skill_triangle/square/circle/star) + onClickCell(선택 콜백). 근거: DragonSelectLayer.c init(popup4)+initWidget
## (scroll_box+CCTableView+skill_*_bg)+onClickCell/checkDisableDragon. 재사용 컴포넌트(스킬/재료/대상 선택).
## disable_filter(dd)->bool: true면 선택불가(흐림). on_select(uid) 콜백.
func _open_dragon_select(title: String, on_select: Callable, disable_filter := Callable()) -> void:
	_open_backdrop(0.55)
	var vis := _vis()
	var BW := clampf(vis.x - 80.0, 700.0, 1120.0)
	var BH := clampf(vis.y - 56.0, 520.0, 680.0)
	var cf := FileAccess.open("res://assets/converted/common_ui/_manifest.json", FileAccess.READ)
	var cm: Dictionary = JSON.parse_string(cf.get_as_text()) if cf else {}
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	_overlay.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(340, 54); tbar.position = Vector2((BW - 340) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = title
	tl.add_theme_font_size_override("font_size", 28); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 66, 14); xb.pressed.connect(_close_overlay); win.add_child(xb)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 92); scroll.size = Vector2(BW - 80, BH - 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = maxi(4, int((BW - 80) / 160.0))
	grid.add_theme_constant_override("h_separation", 10); grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for d in UserDB.dragons():
		grid.add_child(_dragon_select_cell(d, cm, on_select, disable_filter))

func _dragon_select_cell(d: Dictionary, cm: Dictionary, on_select: Callable, disable_filter: Callable) -> Control:
	var cell := Control.new(); cell.custom_minimum_size = Vector2(150, 170)
	var disabled := disable_filter.is_valid() and bool(disable_filter.call(d))
	var por := _portrait_sprite(int(d["id"]), Growth.stage_for_level(int(d["level"])), 0.66, int(d.get("skin", 0)))
	if por:
		por.position = Vector2(75, 64)
		if disabled: por.modulate = Color(0.35, 0.35, 0.4, 1)
		cell.add_child(por)
	# 스킬 슬롯 모양(원작 common/skill_*): 등급 기반 슬롯 수(Loadout 규칙).
	var slots: int = Loadout.slot_count(Data.get_dragon(int(d["id"])))
	var shapes := ["common_skill_triangle", "common_skill_square", "common_skill_circle", "common_skill_star"]
	for si in mini(slots, 4):
		var sh := _atlas_sprite("common_ui", shapes[si], cm, 0.5)
		if sh: sh.position = Vector2(40 + si * 24, 122); cell.add_child(sh)
	var nm := Label.new(); nm.text = "%s Lv.%d" % [String(Data.get_dragon(int(d["id"])).get("name", d["id"])), int(d["level"])]
	nm.add_theme_font_size_override("font_size", 14); nm.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; nm.position = Vector2(0, 138); nm.size = Vector2(150, 22)
	cell.add_child(nm)
	if not disabled:
		var b := Button.new(); b.flat = true; b.size = Vector2(150, 130); b.position = Vector2(0, 4)
		var uid := int(d["uid"])
		b.pressed.connect(func(): _close_overlay(); on_select.call(uid))
		cell.add_child(b)
	return cell

## 원작 BagExpandLayer 1:1: 가방 확장 — popup4 + pop_title_bg + close_btn + 골드(onClickGold)/다이아(onClickCash) 확장 버튼.
## 근거: BagExpandLayer.c initWidget(9patch/popup4·pop_title_bg + common/close_btn + coin_small1/diamond_small1)
## + onClickGold/onClickCash + setGoldListener/setCashListener. ⚠️확장량·비용=서버유실→오프라인 고정(+20칸, 5000G/10다이아 ASSUMPTION).
const BAG_EXPAND_STEP := 20
const BAG_EXPAND_GOLD := 5000
const BAG_EXPAND_DIA := 10
func _bag_max() -> int:
	return int(UserDB.get_pmeta("bag_max", 240))
func _open_bag_expand() -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 72; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	const BW := 440.0
	const BH := 290.0
	var cf := FileAccess.open("res://assets/converted/common_ui/_manifest.json", FileAccess.READ)
	var cm: Dictionary = JSON.parse_string(cf.get_as_text()) if cf else {}
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(280, 52); tbar.position = Vector2((BW - 280) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = "가방 확장"
	tl.add_theme_font_size_override("font_size", 26); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 58, 14); xb.pressed.connect(func(): layer.queue_free()); win.add_child(xb)
	var ml := Label.new(); ml.text = "가방 %d칸 → %d칸 (+%d)" % [_bag_max(), _bag_max() + BAG_EXPAND_STEP, BAG_EXPAND_STEP]
	ml.add_theme_font_size_override("font_size", 20); ml.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; ml.position = Vector2(40, 84); ml.size = Vector2(BW - 80, 28); win.add_child(ml)
	var do_expand := func(kind: String, cost: int):
		if UserDB.spend(kind, cost):
			UserDB.set_pmeta("bag_max", _bag_max() + BAG_EXPAND_STEP)
			layer.queue_free()
			_open_complete("가방 확장", "가방이 %d칸으로 늘었습니다!" % _bag_max())
	# 골드 확장(onClickGold).
	var gb := Button.new(); gb.size = Vector2(160, 50); gb.position = Vector2(BW * 0.5 - 174, BH - 84)
	gb.pressed.connect(func(): do_expand.call("gold", BAG_EXPAND_GOLD)); win.add_child(gb)
	var gc := _atlas_sprite("common_ui", "common_coin_small1", cm, 0.9)
	if gc: gc.position = Vector2(BW * 0.5 - 150, BH - 59); win.add_child(gc)
	var gl := Label.new(); gl.text = "%d" % BAG_EXPAND_GOLD; gl.add_theme_font_size_override("font_size", 20)
	gl.add_theme_color_override("font_color", Color.WHITE); gl.position = Vector2(BW * 0.5 - 128, BH - 72); gl.size = Vector2(120, 28); win.add_child(gl)
	# 다이아 확장(onClickCash).
	var db := Button.new(); db.size = Vector2(160, 50); db.position = Vector2(BW * 0.5 + 14, BH - 84)
	db.pressed.connect(func(): do_expand.call("diamond", BAG_EXPAND_DIA)); win.add_child(db)
	var dc := _atlas_sprite("common_ui", "common_diamond_small1", cm, 0.9)
	if dc: dc.position = Vector2(BW * 0.5 + 38, BH - 59); win.add_child(dc)
	var dl := Label.new(); dl.text = "%d" % BAG_EXPAND_DIA; dl.add_theme_font_size_override("font_size", 20)
	dl.add_theme_color_override("font_color", Color.WHITE); dl.position = Vector2(BW * 0.5 + 60, BH - 72); dl.size = Vector2(100, 28); win.add_child(dl)

## 원작 CompleteLayer 1:1: 완료(성공) 알림 팝업 — popup4 + pop_title_bg + 단일 확인 + effect_equip_success 사운드.
## 근거: CompleteLayer.c initWidget(9patch/popup4·pop_title_bg + common/diamond) + playEffect(music/effect_equip_success.mp3,
## CompleteLayer.c:63/1084) + setConfirmListener/onClickConfirm. 장착/업그레이드 완료 알림.
func _open_complete(title: String, msg: String, on_confirm := Callable()) -> void:
	Bgm.sfx("effect_equip_success")   # 원작 playEffect(CompleteLayer.c:1084)
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 72; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	const BW := 420.0
	const BH := 260.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(280, 52); tbar.position = Vector2((BW - 280) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = title
	tl.add_theme_font_size_override("font_size", 26); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	var ml := Label.new(); ml.text = msg
	ml.add_theme_font_size_override("font_size", 21); ml.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ml.position = Vector2(40, 80); ml.size = Vector2(BW - 80, 80); win.add_child(ml)
	var ok := Button.new(); ok.text = "확인"; ok.size = Vector2(160, 46); ok.position = Vector2((BW - 160) * 0.5, BH - 62)
	ok.pressed.connect(func():
		if is_instance_valid(layer): layer.queue_free()
		if on_confirm.is_valid(): on_confirm.call())
	win.add_child(ok)

## 🔴 제거(2026-07-30): `_show_get_item`(popup4 창 + 제목바 자작본).
##   재디컴프로 원작 `ShowGetItemDetailLayer::init` 이 **`setContentSprite` 를 부르지 않는다**는 것이
##   드러났다 — 창 프레임도 제목바도 없는 **전체화면 딤 + 원형 공개 연출**이다. 종전 이식본은
##   그 두 개를 얹은 자작이었고, 호출부도 없었다.
##   → 원작 배치대로 다시 짠 공용 컴포넌트 `scripts/ui/get_item_popup.gd`(`GetItemPopup`) 를 쓴다.
##   배선된 원작 호출 지점: 상점 구매·장비/젬 구매·뽑기 결과(`shop.gd`).

## 원작 PopupTypeLayer 1:1: 범용 확인/메시지 다이얼로그 — popup4 + pop_title_bg + close_btn + 좌(취소)/우(확인) 버튼.
## 근거: PopupTypeLayer.c(9patch/popup4·pop_title_bg + common/close_btn + onClickLeft/onClickRight/onClickClose +
## setConfirmListener/setCancelListener + getStringLine 메시지). ⚠️setImg/setItem/setCash 변형은 오버로드로 미반영(기본형).
##
## `cancel_text == ""` = **안내 전용 1버튼** 모드. 원작도 `setCancelListener` 를 부르지 않으면
## 취소 버튼(`this+0x390`)과 그 짝(`0x388`)을 `setVisible(false)` 하고 확인 버튼을 창 중앙
## `(0,0)` 으로 옮긴다(`PopupTypeLayer::showCostItem` @01200200 분기). 젬 장착 실패 안내가 이 형태다.
## 🔴 2026-07-30: 본체를 `scripts/ui/popup_type.gd`(`PopupType`)로 올렸다 — 월드맵의
## 행동불능/허기 팝업이 같은 원작 클래스를 필요로 해서 두 벌이 될 뻔했다. 여기는 얇은 위임.
func _open_popup_type(title: String, msg: String, on_confirm: Callable, confirm_text := "확인", cancel_text := "취소") -> void:
	PopupType.open(self, title, msg, on_confirm, confirm_text, cancel_text)

## 원작 `ItemSmeltPopup` 이식 — 재료 제련(하위 티어 → 상위 티어). 가방에서 열린다
## (`BagPopup::onClickConfirm` case 6 → `ItemSmeltPopup::create(item)`, BagPopup.c:15703).
## 원작 리터럴 그대로: `9patch/popup4`(내용 700×470, 패치 130/190/40/58) + `9patch/pop_title_bg`
## + 재료/결과 슬롯 `RoundedLayer(150×200)` + `common/plus`(w/2−37, +20) + `common/btn_fold`
## (w/2−37, −20) + `common/coin_small1` 비용 + `RoundedButton(270×56)` = `onClickSmelt`.
## 개수 스테퍼 = `onClickCount`(기본 1). 문구 = SmeltTitle/SmeltMsg/SmeltBtn/SystemMsg5.
## 규칙·레시피 = `ItemSmelt`(logic) + data/combine_item.json.
var _smelt_count := 1

func _open_smelt(source_key: String) -> void:
	var recipe: Dictionary = ItemSmelt.for_source(source_key, Data.combine_item)
	if recipe.is_empty():
		_toast("제련할 수 없는 아이템입니다"); return
	_smelt_count = 1
	_smelt_body(source_key, recipe)

func _smelt_body(source_key: String, recipe: Dictionary) -> void:
	_close_overlay()
	_open_backdrop(0.55)
	var vis := _vis()
	var BW := 700.0
	var BH := 470.0
	var cm := _man_common()
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190
	win.patch_margin_right = 40; win.patch_margin_bottom = 58
	win.size = Vector2(BW, BH)
	win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	_overlay.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20
	tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(300, 54); tbar.position = Vector2((BW - 300) * 0.5, 12)
	win.add_child(tbar)
	var title := Label.new(); title.text = "재료 제련"          # 원작 <SmeltTitle>
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size = tbar.size; tbar.add_child(title)
	var xb := TextureButton.new()
	xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 66, 14); xb.pressed.connect(_close_overlay)
	win.add_child(xb)
	# 재료 슬롯(왼쪽) → ▶ → 결과 슬롯(오른쪽). 원작 슬롯 크기 150×200.
	var mats: Array = ItemSmelt.materials(recipe)
	var target := String(recipe.get("target", ""))
	var have: Dictionary = {}
	for m in mats:
		have[String((m as Dictionary)["item"])] = UserDB.item_count(String((m as Dictionary)["item"]))
	var slot_sz := Vector2(150, 200)
	var sy := 92.0
	var lx := 70.0
	var rx := BW - 70.0 - slot_sz.x
	_smelt_slot(win, Vector2(lx, sy), slot_sz, String((mats[0] as Dictionary)["item"]),
		"%d / %d" % [int(have.get(String((mats[0] as Dictionary)["item"]), 0)),
			int((mats[0] as Dictionary)["count"]) * _smelt_count], cm)
	_smelt_slot(win, Vector2(rx, sy), slot_sz, target, "×%d" % _smelt_count, cm)
	# 원작: plus(+20) 와 btn_fold(−20) 를 슬롯 사이에 세로로 둔다. 재료가 1종이면 ▶만 보인다.
	var midx := BW * 0.5 - 8.0
	if mats.size() > 1:
		var pl := _atlas_sprite("common_ui", "common_plus", cm, Design.ASSET_SCALE)
		if pl: pl.position = Vector2(midx, sy + 70.0); win.add_child(pl)
		_smelt_slot(win, Vector2(lx, sy + 210.0), Vector2(150, 96),
			String((mats[1] as Dictionary)["item"]),
			"%d / %d" % [int(have.get(String((mats[1] as Dictionary)["item"]), 0)),
				int((mats[1] as Dictionary)["count"]) * _smelt_count], cm)
	var fold := _atlas_sprite("common_ui", "common_btn_fold", cm, Design.ASSET_SCALE * 1.4)
	if fold:
		fold.rotation_degrees = 90.0                      # 원작 ▶ 표현(세로 화살표를 눕힌다)
		fold.position = Vector2(midx, sy + 110.0)
		win.add_child(fold)
	# 개수 스테퍼(원작 onClickCount) — 재료·골드가 허용하는 최대까지.
	var gold := UserDB.gold()
	var maxn := ItemSmelt.max_count(recipe, have, gold)
	_smelt_count = clampi(_smelt_count, 1, maxi(1, maxn))
	# 원작 배치: `common/btn_arrow1`(◀) = 중앙−50, `common/btn_arrow2`(▶) = 중앙+50, 개수 라벨은
	# 그 사이(ItemSmeltPopup.c:473-495, scale 1.05).
	var cy := sy + 214.0
	var minus := _smelt_arrow(win, "common_btn_arrow1", Vector2(BW * 0.5 - 50.0, cy + 22.0), cm)
	minus.pressed.connect(func():
		_smelt_count = maxi(1, _smelt_count - 1)
		_smelt_body(source_key, recipe))
	var cnt := Label.new(); cnt.text = str(_smelt_count)
	cnt.add_theme_font_size_override("font_size", 30)
	cnt.add_theme_color_override("font_color", Color(0.3, 0.18, 0.03))
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cnt.position = Vector2(BW * 0.5 - 34.0, cy); cnt.size = Vector2(68, 44)
	win.add_child(cnt)
	var plusb := _smelt_arrow(win, "common_btn_arrow2", Vector2(BW * 0.5 + 50.0, cy + 22.0), cm)
	plusb.pressed.connect(func():
		_smelt_count = mini(maxi(1, maxn), _smelt_count + 1)
		_smelt_body(source_key, recipe))
	# 비용(원작 common/coin_small1 + 개수×cost).
	var cost := ItemSmelt.total_cost(recipe, _smelt_count)
	var coin := _atlas_sprite("common_ui", "common_coin_small1", cm, Design.ASSET_SCALE)
	if coin: coin.position = Vector2(BW * 0.5 - 60.0, cy + 62.0); win.add_child(coin)
	var cl := Label.new(); cl.text = str(cost)
	cl.add_theme_font_size_override("font_size", 24)
	cl.add_theme_color_override("font_color",
		Color(0.3, 0.18, 0.03) if gold >= cost else Color(0.72, 0.16, 0.10))
	cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cl.position = Vector2(BW * 0.5 - 40.0, cy + 44.0); cl.size = Vector2(160, 36)
	win.add_child(cl)
	# 제련 버튼(원작 RoundedButton 270×56, 라벨 <SmeltBtn> "%1$d 제련").
	var ok := ItemSmelt.affordable(recipe, _smelt_count, have, gold)
	var bg := NinePatchRect.new()
	bg.texture = load("res://assets/converted/ninepatch_ui/9patch_btn.tres")
	bg.patch_margin_left = 16; bg.patch_margin_right = 16
	bg.patch_margin_top = 16; bg.patch_margin_bottom = 16
	bg.size = Vector2(270, 56); bg.position = Vector2((BW - 270) * 0.5, BH - 78.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not ok: bg.modulate = Color(0.6, 0.6, 0.6)
	win.add_child(bg)
	var sb := Button.new(); sb.flat = true
	sb.text = "%d 제련" % _smelt_count
	sb.add_theme_font_size_override("font_size", 28)
	sb.add_theme_color_override("font_color", Color.WHITE)
	sb.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0, 0.9))
	sb.add_theme_constant_override("outline_size", 5)
	sb.size = Vector2(270, 56); sb.position = Vector2((BW - 270) * 0.5, BH - 78.0)
	sb.pressed.connect(func():
		if not ok:
			_toast("재료나 골드가 부족합니다"); return
		# 원작 확인 문구 <SmeltMsg> "%1$s을 제련하시겠습니까?"
		_open_popup_type("재료 제련", "%s을 제련하시겠습니까?" % Data.item_name(source_key),
			func(): _do_smelt(source_key, recipe, _smelt_count)))
	win.add_child(sb)

## 개수 스테퍼 화살표 1개(원작 `CCMenuItemImageEx` + `common/btn_arrow1/2`, scale 1.05).
## 중심 좌표를 받아 프레임을 깔고 그 위에 투명 Button 을 올린다.
func _smelt_arrow(win: Control, frame: String, center: Vector2, cm: Dictionary) -> Button:
	var s := 1.05 * Design.ASSET_SCALE
	var spr := _atlas_sprite("common_ui", frame, cm, s)
	var sz := Vector2(44, 44)
	if spr:
		spr.position = center
		win.add_child(spr)
		if spr.texture != null:
			sz = spr.texture.get_size() * s
	var b := Button.new(); b.flat = true
	b.size = sz.max(Vector2(44, 44))
	b.position = center - b.size * 0.5
	win.add_child(b)
	return b

## 재료/결과 한 칸(원작 RoundedLayer 안에 아이콘 + 이름 + 개수).
func _smelt_slot(win: Control, pos: Vector2, sz: Vector2, item_key: String,
		count_text: String, cm: Dictionary) -> void:
	var box := _panel(Color(0.18, 0.11, 0.05, 0.35))
	box.position = pos; box.size = sz
	win.add_child(box)
	var ip := Data.item_icon_path(item_key)
	if ip != "" and ResourceLoader.exists(ip):
		var ic := Sprite2D.new(); ic.texture = load(ip); ic.material = _pma
		ic.position = Vector2(sz.x * 0.5, sz.y * 0.42)
		ic.scale = Vector2(0.8, 0.8)
		box.add_child(ic)
	var nm := Label.new(); nm.text = Data.item_name(item_key)
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", Color(1, 0.96, 0.86))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.position = Vector2(4, sz.y - 62.0); nm.size = Vector2(sz.x - 8, 40)
	box.add_child(nm)
	var ct := Label.new(); ct.text = count_text
	ct.add_theme_font_size_override("font_size", 18)
	ct.add_theme_color_override("font_color", Color(1, 0.87, 0.5))
	ct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ct.position = Vector2(4, 6); ct.size = Vector2(sz.x - 8, 24)
	box.add_child(ct)

## 원작 `onClickSmelt` → `requestSmelt`(서버) → `responseSmelt`. 오프라인은 즉시 처리:
## 재료·골드를 소비하고 결과 아이템을 count 개 준다(`addItem(target, count)`, :1533).
func _do_smelt(source_key: String, recipe: Dictionary, count: int) -> void:
	var have: Dictionary = {}
	for m in ItemSmelt.materials(recipe):
		have[String((m as Dictionary)["item"])] = UserDB.item_count(String((m as Dictionary)["item"]))
	if not ItemSmelt.affordable(recipe, count, have, UserDB.gold()):
		_toast("재료나 골드가 부족합니다"); return
	for m in ItemSmelt.materials(recipe):
		var md: Dictionary = m
		UserDB.use_item(String(md["item"]), int(md["count"]) * count)
	var cost := ItemSmelt.total_cost(recipe, count)
	if cost > 0 and not UserDB.spend("gold", cost):
		_toast("골드가 부족합니다"); return
	var target := String(recipe.get("target", ""))
	UserDB.add_item(target, count)
	_close_overlay()
	_inv_selected = target
	_open_inventory()
	# 원작 <SystemMsg5> "아이템 %1$s를 %2$d개 얻었습니다."
	_toast("아이템 %s를 %d개 얻었습니다." % [Data.item_name(target), count])

## 원작 AwakenDragonLayer 1:1: 각성 드래곤 목록 — popup4 + pop_title_bg + scroll_box + 드래곤 셀
## (common/element_bg + 초상 + 각성 상태). 근거: AwakenDragonLayer.c init(popup4)+initWidget(scroll_box+CCTableView
## +element_bg+skill_evolution+e_symbol)+onClickDragon/Tap. ⚠️e_symbol(scene/mamorudiclab)=에셋부재→★(btn_star) 대체.
func _open_awaken_dex() -> void:
	_open_backdrop(0.55)
	var vis := _vis()
	var BW := clampf(vis.x - 80.0, 700.0, 1120.0)
	var BH := clampf(vis.y - 56.0, 520.0, 680.0)
	var cf := FileAccess.open("res://assets/converted/common_ui/_manifest.json", FileAccess.READ)
	var cm: Dictionary = JSON.parse_string(cf.get_as_text()) if cf else {}
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	_overlay.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(340, 54); tbar.position = Vector2((BW - 340) * 0.5, 12); win.add_child(tbar)
	var title := Label.new(); title.text = "각성 드래곤"
	title.add_theme_font_size_override("font_size", 30); title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size = tbar.size; tbar.add_child(title)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 66, 14); xb.pressed.connect(_close_overlay); win.add_child(xb)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 92); scroll.size = Vector2(BW - 80, BH - 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = maxi(4, int((BW - 80) / 150.0))
	grid.add_theme_constant_override("h_separation", 10); grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for d in UserDB.dragons():
		grid.add_child(_awaken_cell(d, cm))

func _awaken_cell(d: Dictionary, cm: Dictionary) -> Control:
	var cell := Control.new(); cell.custom_minimum_size = Vector2(140, 158)
	var awk := bool(d.get("awakened", false))
	# common/element_bg(속성 배경틀). 각성=선명, 미각성=흐림.
	var ebg := _atlas_sprite("common_ui", "common_element_bg", cm, 0.66)
	if ebg: ebg.position = Vector2(70, 66); ebg.modulate = Color(1, 1, 1, 1) if awk else Color(0.6, 0.6, 0.65, 0.9); cell.add_child(ebg)
	var por := _portrait_sprite(int(d["id"]), Growth.stage_for_level(int(d["level"])), 0.62, int(d.get("skin", 0)))
	if por:
		por.position = Vector2(70, 62)
		if not awk:
			por.modulate = Color(0.45, 0.45, 0.5, 1)
		cell.add_child(por)
	# e_symbol(에셋부재)→★ btn_star: 각성 배지.
	if awk:
		var star := _atlas_sprite("common_ui", "common_btn_star", cm, 0.7)
		if star: star.position = Vector2(114, 30); cell.add_child(star)
	var nm := Label.new(); nm.text = "%s  Lv.%d" % [String(Data.get_dragon(int(d["id"])).get("name", d["id"])), int(d["level"])]
	nm.add_theme_font_size_override("font_size", 14)
	nm.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05) if awk else Color(0.5, 0.44, 0.34))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; nm.position = Vector2(0, 126); nm.size = Vector2(140, 22)
	cell.add_child(nm)
	# onClickDragon: 활성 드래곤 전환(원작) — UserDB 활성 설정 후 닫기(cave 새로고침).
	var uid := int(d["uid"])
	var b := Button.new(); b.flat = true; b.size = Vector2(140, 120); b.position = Vector2(0, 4)
	b.pressed.connect(func():
		UserDB.set_active(uid)
		_close_overlay(); _refresh())
	cell.add_child(b)
	return cell

## 🔴 2026-07-28 이동: `_open_awaken`(원작 AwakenPopup 이식) + `_awaken_material` 을
## **연구소**(scripts/ui/mamorudiclab.gd)로 옮겼다. 원작에서 `AwakenPopup::create` 를 부르는 곳은
## `DragonAwaken.c:1833` 뿐이다 — 각성은 우노의 마모루딕 연구소 전용 절차다(사용자 확인).
## 동굴은 각성 **상태 표시**만 한다(위 `_open_dragon_detail` 의 상태 라벨).

## 🔴 2026-07-30 삭제 — **오라 선택**(자작).
## 원작 기능은 실재했다: `AuraSelectPopLayer`(makeUI/initDataWithDB/equipAura/effectUnlock) +
## `Aura`(SetOn/GetZOrder/GetOffsetPositionY/IsSpineAura/getName/getDesc) 가 디컴프에 온전히 있다.
## 그런데 **고를 대상이 하나도 안 남았다**:
##   · 에셋 `aura_skin/aura_<N>.img_plist` · `aura_skin/aura_<N>/aura01~NN.png`
##     · `aura_skin/aura_<N>_spine.spine_json` → `aura_skin/` 폴더가 레포·APK·OBB 전수 **0건**
##   · 오라별 메타 `select type/pos from info_dragon_aura where aura_no=%d` → 로컬 SQLite **DB 파일 없음**
##   · 목록·보유·해금·선택 = 서버 API `game_cave/{check_aura_list,choose_dragon_aura,unlock_dragon_aura}.hb` **유실**
## 게다가 우리가 붙였던 "원소 오라 10종 중 선택"은 원작 동작이 아니다 — 원작이 고르는 건
## `aura_skin` 이고, `dragon/aura_<element>` 는 **오라성체 단계 연출**이다(선택 대상이 아니다).
## ⇒ 선택 기능은 걷어내고, 오라성체 이펙트는 **드래곤 자기 속성**으로 고정한다(아래 `_apply_aura`).
## 참고: `dragon/aura_special/*` 17종은 이벤트 장신구에 딸린 오라라 이 시스템과 무관하다
## (디컴프 참조 0건, CLAUDE.md §10 이벤트 장비 행).
## 스킬 팝업(원작 SkillsPopup): 활성 드래곤 장착 스킬을 △□○☆ 슬롯 + 이름 + 효과로 표시.
func _open_skills() -> void:
	var a := _active()
	if a.is_empty(): return
	# 원작 SkillsPopup 1:1 레시피: data/recipes/SkillsPopup.json (popup4 650×480, 2-pane).
	# 근거: docs/ref/orig_code/decomp/SkillsPopup.c init@00eeba10/initWidget@00eebbc8, PopupLayer.c setContentSprite@011f709c.
	# 좌표 환산: 레시피는 bg 로컬 cocos(y-up 좌하단원점) → Godot(y-down) y' = BH - y.
	const BW := 650.0
	const BH := 480.0
	var overlay := CanvasLayer.new(); overlay.layer = 22; add_child(overlay)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: overlay.queue_free())
	overlay.add_child(dim)
	var vis := _vis()
	# 팝업 배경 = 원작 9patch/popup4 (NinePatch, capInsets130,190,40,58 → 여백 L130/T190/R55/B81)
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round(vis.x * 0.5 - BW * 0.5), round(vis.y * 0.5 - BH * 0.5))
	overlay.add_child(win)
	# 타이틀(상단중앙 cocos(bgW*0.5,bgH-45)) + info(우측 +60)
	var t := Label.new(); t.text = "%s의 스킬" % String(Data.get_dragon(int(a["id"])).get("name", "드래곤"))
	t.add_theme_font_size_override("font_size", 24); t.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.position = Vector2(BW * 0.5 - 90, BH - 435 - 16); t.size = Vector2(180, 32); win.add_child(t)
	var info := TextureRect.new(); info.texture = load("res://assets/converted/common_ui/common_btn_info.tres")  # cocos(bgW*0.5+60,bgH-45)
	info.position = Vector2(BW * 0.5 + 52, BH - 435 - 12); win.add_child(info)
	# 닫기(우상단 cocos(bgW-50,bgH-50))
	var cb := TextureButton.new(); cb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	cb.position = Vector2(BW - 50 - 22, (BH - 430) - 22); win.add_child(cb)
	cb.pressed.connect(func(): overlay.queue_free())
	# 좌 리스트 상자 = 원작 9patch/scroll_box (cocos size(bgW-430,420) pos(40,40)anchor(0,0))
	var box := NinePatchRect.new()
	box.texture = load("res://assets/converted/ninepatch_ui/9patch_scroll_box.tres")
	box.patch_margin_left = 65; box.patch_margin_top = 65; box.patch_margin_right = 31; box.patch_margin_bottom = 31
	box.size = Vector2(BW - 430, 420); box.position = Vector2(40, BH - 40 - 420); win.add_child(box)
	var scroll := ScrollContainer.new(); scroll.position = Vector2(10, 5); scroll.size = Vector2(BW - 430 - 20, 410); box.add_child(scroll)
	var vbox := VBoxContainer.new(); vbox.custom_minimum_size = Vector2(BW - 430 - 24, 0); scroll.add_child(vbox)
	# 우 상세 패널(원작 CCLayer 350×420, cocos pos(bgW-30,40)anchor(1,0) → 좌하단(bgW-30-350,40))
	var detail := Control.new(); detail.size = Vector2(350, 420); detail.position = Vector2(BW - 30 - 350, BH - 40 - 420); win.add_child(detail)
	var dlabel := Label.new(); dlabel.position = Vector2(16, 70); dlabel.size = Vector2(318, 300)
	dlabel.autowrap_mode = TextServer.AUTOWRAP_WORD; dlabel.add_theme_color_override("font_color", Color(0.92, 0.9, 0.82))
	dlabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; dlabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dlabel.text = "스킬을 선택하세요"; detail.add_child(dlabel)
	# 스킬 행(좌 리스트) — 클릭 시 우 상세 갱신(원작 onClickSkill: 리스트→상세)
	var cf := FileAccess.open("res://assets/converted/common_ui/_manifest.json", FileAccess.READ)
	var cm: Dictionary = JSON.parse_string(cf.get_as_text()) if cf else {}
	var s2f := {"tri": "triangle", "sq": "square", "cir": "circle", "star": "star"}
	var sk := UserDB.dragon_skills(int(a["uid"]))
	if sk.is_empty():
		# 원작: scroll_box 중앙 라벨(SkillsPopup.c:979-994). 빈 상태 메시지를 좌 상자 중앙에.
		var em := Label.new(); em.text = "배운 스킬이 없습니다"
		em.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; em.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		em.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45))
		em.position = Vector2(10, 5); em.size = Vector2(BW - 430 - 20, 410); box.add_child(em)
		dlabel.text = ""
	for i in sk.size():
		var sid := int(sk[i].get("id", 0))
		var sdef: Dictionary = Data.skills.get(str(sid), {})
		var shp: String = s2f.get(String(sdef.get("slot", "")), "circle")
		var row := Button.new(); row.custom_minimum_size = Vector2(0, 42); row.flat = true
		# 학습 풀 목록이므로 어느 칸에 꽂혀 있는지도 같이 보여준다(원작 setSKillsList 는 장착분을
		# 목록 맨 앞으로 exchange 한다 — 우리는 표기로 대신).
		var eq_at := Loadout.equipped_ids(a).find(sid)
		row.text = "  %s  %s Lv.%d%s" % [
			{"triangle": "△", "square": "□", "circle": "○", "star": "☆"}.get(shp, "○"),
			String(sdef.get("name", "스킬 %d" % sid)), int(sk[i].get("level", 1)),
			"   (%d번 칸)" % (eq_at + 1) if eq_at >= 0 else ""]
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
		var nm := String(sdef.get("name", "스킬"))
		var ef := String(sdef.get("effect_text", ""))
		var slv := int(sk[i].get("level", 1))
		# 원작 onClickSkill: 스킬 선택 → SkillInfoPopup(상세). 인라인 미리보기도 갱신.
		row.pressed.connect(func():
			dlabel.text = "%s\n\n%s" % [nm, ef if ef != "" else "(효과 정보 없음)"]
			_open_skill_info(sid, slv, sdef))
		vbox.add_child(row)
	# ⚠️ 여기 있던 "스킬 교체(오프라인)" 버튼(자작 `_reroll_skill` — 배운 스킬 1개를 무작위로
	#   갈아치움)은 폐기했다(2026-07-29). 스킬을 바꾸는 원작 수단은 **스킬 스크롤 습득 + 칸 장착**
	#   이고(docs/ref/porting/SkillScroll.md), 그게 이제 제대로 돌아간다. 자작 난수 교체는
	#   배운 스킬을 파괴하는 데다 원작에 없는 규칙이었다.

## 원작 SkillInfoPopup 1:1: data/recipes/SkillInfoPopup.json. popup4 604×466 + pop_title_bg(이름)
## + backlight3+스킬아이콘(skill_{id}) + comment + upgrade_gauge(레벨). 근거: SkillInfoPopup.c init@01413bXX/initWidget@01413df4.
## ⚠️강화(requestSkillUpgrade)=서버유실 → 게이지는 레벨 표시(display), 강화 액션 없음(오프라인).
func _open_skill_info(sid: int, level: int, sdef: Dictionary) -> void:
	const BW := 620.0
	const BH := 466.0
	var vis := _vis()
	var ov := CanvasLayer.new(); ov.layer = 40; add_child(ov)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.5); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: ov.queue_free())
	ov.add_child(dim)
	var win := NinePatchRect.new(); win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5)); ov.add_child(win)
	var tbar := NinePatchRect.new(); tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(BW * 0.9, 52); tbar.position = Vector2((BW - BW * 0.9) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = String(sdef.get("name", "스킬")); tl.add_theme_font_size_override("font_size", 22)
	tl.add_theme_color_override("font_color", Color.WHITE); tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; tl.size = tbar.size; tbar.add_child(tl)
	var cb := TextureButton.new(); cb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	cb.position = Vector2(BW - 50 - 20, 14); win.add_child(cb); cb.pressed.connect(func(): ov.queue_free())
	# backlight3 + 스킬 아이콘(중앙 상단)
	var icx := BW * 0.5; var icy := 132.0
	var bl := load("res://assets/converted/common_ui/common_backlight3.tres")
	if bl:
		var blr := TextureRect.new(); blr.texture = bl; blr.position = Vector2(icx - 72, icy - 72); blr.size = Vector2(144, 144)
		blr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; win.add_child(blr)
	var icp := "res://assets/converted/skill/skill_%d.tres" % sid
	if ResourceLoader.exists(icp):
		var ic := TextureRect.new(); ic.texture = load(icp); ic.position = Vector2(icx - 48, icy - 48); ic.size = Vector2(96, 96)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; win.add_child(ic)
	# comment(중앙)
	var cmt := String(sdef.get("effect_text", ""))
	if cmt == "": cmt = String(sdef.get("notes", ""))
	var cm := Label.new(); cm.text = cmt; cm.add_theme_color_override("font_color", Color(0.25, 0.18, 0.1))
	cm.position = Vector2(50, 228); cm.size = Vector2(BW - 100, 96); cm.autowrap_mode = TextServer.AUTOWRAP_WORD
	cm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; win.add_child(cm)
	# 원작 upgrade_gauge(레벨 N/max) — 강화액션은 서버유실이라 표시 전용
	var maxlv := int(sdef.get("max_level", 5))
	var gy := 344.0
	var gbg := load("res://assets/converted/laboratory_ui/scene_laboratory_upgrade_gauge_bg.tres")
	if gbg:
		var g := NinePatchRect.new(); g.texture = gbg
		g.patch_margin_left = 8; g.patch_margin_right = 8; g.patch_margin_top = 6; g.patch_margin_bottom = 6
		g.size = Vector2(360, 28); g.position = Vector2((BW - 360) * 0.5, gy); win.add_child(g)
		var gbar := load("res://assets/converted/laboratory_ui/scene_laboratory_upgrade_gauge_bar.tres")
		if gbar:
			var frac := clampf(float(level) / float(maxi(1, maxlv)), 0.0, 1.0)
			var bar := NinePatchRect.new(); bar.texture = gbar
			bar.patch_margin_left = 6; bar.patch_margin_right = 6; bar.patch_margin_top = 4; bar.patch_margin_bottom = 4
			bar.size = Vector2(348.0 * frac, 20); bar.position = Vector2(6, 4); g.add_child(bar)
	var lv := Label.new(); lv.text = "Lv %d / %d" % [level, maxlv]; lv.add_theme_color_override("font_color", Color(0.3, 0.2, 0.1))
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lv.size = Vector2(BW, 24); lv.position = Vector2(0, gy + 34); win.add_child(lv)

## ============================ 하단 장착 슬롯 (원작 CaveScene::setDragonInfo) ==========
##
## 사용자 보고(2026-07-27): "동굴 하단 UI에서 장착하고 있는 젬/스킬/아이템이 각 칸에 보이지 않아.
## 원작은 해당 칸에 장착 중인 아이템들을 확인 가능하고, 칸 클릭 시 바로 장착도 할 수 있어."
## → 원작 로직이 남아 있었다. 근거·좌표·클릭동작 전문 = `docs/ref/porting/CaveBottomSlots.md`.
##   ⚠️ 근거가 된 `setDragonInfo`(17,508바이트)는 기존 디컴프 덤프에서 `[skip>6000]` 으로 **잘려**
##      있었다 — `batch_decompile.py --classes CaveScene --max 20000 --force` 로 재생성했다.
##
## 이전 구현(`_tab_group`)은 **빈 `9patch/box1` 사각칸만** 그렸다. 실제 원작은:
##   · 칸 배경 = `9patch/bg_common`(어두운 라운드) 위에 종류별 프레임을 덮는다
##   · 젬 3칸 = 슬롯 타입별 `9patch/gem_{red,blue,yellow,white}_bg`  ← 레퍼런스의 파랑·노랑·파랑
##   · 스킬 2칸 = `common/skill_{triangle,square,circle,star}_bg` + Lv10/Lv35 해금
##   · 각성스킬 1칸 = `common/skill_evolution_bg` + `skill/evolution/<N>.png` (각성 시에만)
##   · 아이템 1칸 = `9patch/bg_common` 단독(레퍼런스 `docs/ref/orig_image/cave/Cave.png` 실측)
##
## 크기: 원작 `setContentSize(70,70)` 포인트. 하단바는 1864폭 공간이라 70pt ≈ 109 단위.
## 간격: 레퍼런스 실측 89pt(≈139단위). 디컴프의 `w+5`(75pt)는 후기판 값으로 프레임 글로우가
##   겹친다 — 눈에 보이는 쪽(레퍼런스)을 따른다.
const SLOT_BOX := 109.0
const SLOT_PITCH := 139.0
const SLOT_Y := 18.0        # 바 상단에서 칸 상단까지(바 높이 150 → 아래 여백 23)
const SLOT_LABEL_Y := -12.0
const SLOT_X_ITEM := 770.0
const SLOT_X_GEM := 1000.0
const SLOT_X_AWAKEN := 1400.0
const SLOT_X_SKILL := 1520.0

## 슬롯 레이어 재구성 — 원작 `setDragonInfo()` 재호출 대응.
func _refresh_slots() -> void:
	if _slot_layer == null or not is_instance_valid(_slot_layer):
		return
	for c in _slot_layer.get_children():
		c.queue_free()
		_slot_layer.remove_child(c)      # queue_free 는 다음 프레임이라 즉시 떼어낸다
	_build_slot_cluster(_slot_layer)

func _build_slot_cluster(bar: Control) -> void:
	var a := _active()
	_slot_label(bar, SLOT_X_ITEM, "아이템")
	_slot_label(bar, SLOT_X_GEM, "젬")
	_slot_label(bar, SLOT_X_SKILL, "스킬")
	_build_item_slot(bar, a)
	_build_gem_slots(bar, a)
	_build_skill_slots(bar, a)

func _slot_label(bar: Control, x: float, text: String) -> void:
	var lb := Label.new()
	lb.text = text
	lb.position = Vector2(x + 4, SLOT_LABEL_Y)
	lb.add_theme_font_size_override("font_size", 22)
	lb.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	lb.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.0, 0.9))
	lb.add_theme_constant_override("outline_size", 4)
	bar.add_child(_ignore_mouse(lb))
	
## 라벨/장식은 클릭을 먹지 않게 한다(칸 히트박스가 받아야 하므로).
func _ignore_mouse(c: Control) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## 칸 1개 = `9patch/bg_common`(어두운 라운드) 70×70. 원작 capInsets(20,20,2,2).
## 프레임은 32×32라 9patch margin 은 원작 인셋을 32px 기준으로 그대로 쓴다(l20 t20 r10 b10).
func _slot_base(bar: Control, x: float, frame := "9patch_bg_common") -> NinePatchRect:
	var np := NinePatchRect.new()
	var p := "res://assets/converted/ninepatch_ui/%s.tres" % frame
	if ResourceLoader.exists(p):
		np.texture = load(p)
	np.patch_margin_left = 12; np.patch_margin_top = 12
	np.patch_margin_right = 10; np.patch_margin_bottom = 10
	np.size = Vector2(SLOT_BOX, SLOT_BOX)
	np.position = Vector2(x, SLOT_Y)
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(np)
	return np

## 칸 위에 얹는 스프라이트(중앙 정렬). scale 은 원작 setScale 값을 그대로 받는다.
## 원작이 프레임 픽셀을 그대로 쓰므로 §9 ASSET_SCALE(4/3)을 곱하고, 칸(1864폭 공간)이
## 디자인 대비 1/0.647 배 크므로 그 비도 함께 곱한다 — 칸이 70pt 이니 109/70 이다.
const SLOT_UNIT := SLOT_BOX / 70.0

func _slot_icon(parent: Control, tex: Texture2D, scale: float) -> void:
	if tex == null:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.material = _pma
	s.scale = Vector2.ONE * scale * Design.ASSET_SCALE * SLOT_UNIT
	s.position = Vector2(SLOT_BOX * 0.5, SLOT_BOX * 0.5)
	parent.add_child(s)

## 칸 클릭 히트박스(원작 CCMenuItemImageEx 자리).
func _slot_hit(bar: Control, x: float, cb: Callable, tip := "") -> void:
	var b := Button.new()
	b.flat = true
	b.position = Vector2(x, SLOT_Y)
	b.size = Vector2(SLOT_BOX, SLOT_BOX)
	if tip != "":
		b.tooltip_text = tip
	b.pressed.connect(cb)
	bar.add_child(b)

## 아이템(장비) 칸 — 원작 `onClickItem` → `MultyEquipPop`.
## ⚠️ 후기판은 `MultyEquipView`(140×140, 앵커로 2×2 4칸)를 쓰는데 그 배경 프레임
##   `9patch/scale_streng_gear{on,off}` 가 **추출 아틀라스에 없다**(`--grep scale_streng` → 0건).
##   레퍼런스(구판)도 이 자리에 어두운 칸 **1개**뿐이다 → 1칸으로 그리고 클릭 시 장비 관리로 간다.
func _build_item_slot(bar: Control, a: Dictionary) -> void:
	var base := _slot_base(bar, SLOT_X_ITEM)
	var eqf: Dictionary = a.get("equip", {})
	var unlocked = a.get("equip_slots", 1)   # v11: 해금 칸 id 배열(구세이브는 개수 int)
	var shown := 0
	for sid: String in Equipment.slot_ids(unlocked):
		var sd: Dictionary = Equipment.equipped(eqf, sid, Data.equipment)
		if sd.is_empty():
			continue
		# 장착 장비가 있으면 첫 칸 아이콘을 대표로 보여 준다(원작 4칸 프레임 부재 대체).
		if shown == 0:
			_slot_icon(base, Icons.equip_texture(sd), 0.42)
		shown += 1
	if shown > 1:
		var n := Label.new()
		n.text = "×%d" % shown
		n.add_theme_font_size_override("font_size", 20)
		n.add_theme_color_override("font_color", Color(1, 0.95, 0.75))
		n.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		n.add_theme_constant_override("outline_size", 4)
		n.position = Vector2(SLOT_BOX - 40, SLOT_BOX - 34)
		base.add_child(_ignore_mouse(n))
	_slot_hit(bar, SLOT_X_ITEM, _open_equipment, "장비 관리")

## 젬 3칸 — 원작 setDragonInfo 젬 루프 + `onClickGem`.
##   빈 칸 클릭 → **가방 '젬' 탭**(`_open_gem_tab`, 사용자 확정 — 그 자리의 자작 젬선택 팝업 폐기)
##   찬 칸 클릭 → 해제 확인(원작 PopupTypeLayer → onClickGemDelete)
func _build_gem_slots(bar: Control, a: Dictionary) -> void:
	var gf: Dictionary = a.get("gems", {})
	var types := Gem.types(gf)
	var en := Gem.entries(gf)
	var frame_of := {"ATT": "9patch_gem_red_bg", "DEF": "9patch_gem_blue_bg",
		"HP": "9patch_gem_yellow_bg", "ALL": "9patch_gem_white_bg"}
	var kr: Dictionary = (Data.gems.get("slot_types", {}) as Dictionary).get("kr", {})
	for i in Gem.SLOTS:
		var x := SLOT_X_GEM + SLOT_PITCH * i
		# ⚠️ `9patch/bg_common` 3+2개는 원작에서 **드래곤 선택 전 플레이스홀더**다(setDragonInfo 의
		#    다른 분기). 젬/스킬 칸은 타입 프레임 자체가 칸이므로 아래에 깔지 않는다.
		var ty := String(types[i])
		var base := _slot_base(bar, x, String(frame_of.get(ty, "9patch_gem_white_bg")))
		var tip := "%d번 칸 (%s)" % [i + 1, String(kr.get(ty, ty))]
		if en[i] != null:
			var gname := String(en[i]["name"])
			var tier := int(en[i]["tier"])
			# 원작: 장착 젬 아이콘을 칸 중앙에 setScale(0.5).
			_slot_icon(base, Icons.gem_texture(
				String(Gem.gem_def(gname, Data.gems).get("code", "")), tier), 0.5)
			tip += "\n%s\n(클릭: 해제)" % _gem_line(gname, tier)
			var slot := i
			_slot_hit(bar, x, func(): _confirm_unequip_gem(slot), tip)
		else:
			# 칸 index 는 넘기지 않는다 — 가방 '젬' 탭의 "장착"이 맞는 빈 칸을 스스로 찾는다
			# (원작 BagPopup::onClickConfirm case 2 = `Gem.fit_slot`).
			tip += "\n비어 있음 (클릭: 가방 젬 탭)"
			_slot_hit(bar, x, _open_gem_tab, tip)

## 젬 해제 확인 — 원작은 `PopupTypeLayer` 확인창을 띄우고 confirm 에서 지운다.
## 원작은 해제 비용(isMEC 2/10)이 있으나 단위 표기가 없어 무료로 둔다(문서화: CaveBottomSlots.md §7).
func _confirm_unequip_gem(slot: int) -> void:
	var a := _active()
	if a.is_empty(): return
	var uid := int(a["uid"])
	var en := Gem.entries(a.get("gems", {}))
	if en[slot] == null: return
	var nm := _gem_line(String(en[slot]["name"]), int(en[slot]["tier"]))
	_open_popup_type("젬 해제", "%s\n\n이 칸의 젬을 해제하시겠습니까?\n(해제한 젬은 가방으로 돌아갑니다)" % nm,
		func():
			_unequip_gem(uid, slot)
			_refresh_stats(); _refresh()
			_toast("젬을 해제했습니다"))

## 스킬 2칸 + 각성스킬 1칸 — 원작 setDragonInfo 스킬 루프 + `onClickSkill`.
##   칸 배경 = 슬롯 타입(△□○☆), Lv10/Lv35 미달이면 `common/lock.png`(원작 scale 0.8).
##   장착 스킬이 슬롯 타입과 **일치하면** 모양 프레임, 아니면 스킬 아이콘(원작 scale 0.6).
func _build_skill_slots(bar: Control, a: Dictionary) -> void:
	var level := int(a.get("level", 1))
	var uid := int(a.get("uid", 0))
	var stypes := Loadout.slot_types(a)
	# 칸에 그리는 건 **장착분**(원작 `Dragon::getSkill(slot)`)이다. 학습 풀(`dragon_skills`)은
	# 가지고만 있는 목록이고, 이 칸에 꽂힌 것만 전투에 나간다.
	var equipped := Loadout.equipped_ids(a)
	var bg_of := {"tri": "common_skill_triangle_bg", "sq": "common_skill_square_bg",
		"cir": "common_skill_circle_bg", "star": "common_skill_star_bg"}
	var mark_of := {"tri": "common_skill_triangle", "sq": "common_skill_square",
		"cir": "common_skill_circle", "star": "common_skill_star"}
	for i in Loadout.SKILL_SLOTS:
		var x := SLOT_X_SKILL + SLOT_PITCH * i
		var ty := String(stypes[i])
		var base := _slot_base(bar, x, "")     # 빈 컨테이너 — 배경은 common_ui 프레임이다
		_slot_icon(base, _common_tex(String(bg_of.get(ty, "common_skill_star_bg"))), 1.0)
		var tip := "%d번 칸 (%s)" % [i + 1, String(_SKILL_SLOT_MARK.get(ty, "?"))]
		if not Loadout.slot_unlocked(i, level):
			_slot_icon(base, _common_tex("common_lock"), 0.8)
			tip += "\nLv.%d 에 해금" % int(Loadout.SLOT_UNLOCK_LEVEL[i])
			_slot_hit(bar, x, func(): _toast("Lv.%d 부터 열립니다" % int(Loadout.SLOT_UNLOCK_LEVEL[i])), tip)
			continue
		if int(equipped[i]) > 0:
			var sid := int(equipped[i])
			var sdef: Dictionary = Data.skills.get(str(sid), {})
			# 원작 setDragonInfo 의 실제 순서(2026-07-27 버그수정):
			#   ① `getSkillType(i) == Skill::getSkillType()` 이면 모양 프레임
			#      (`common/skill_{모양}.png`, scale 1.0)을 **먼저** 얹는다
			#   ② 그 다음 `Skill::getImageSprite()` 를 **조건 없이** scale 0.6 으로 얹는다
			#      (디컴프에서 모양 체인 뒤에 goto 로 합류한 뒤 그대로 실행된다)
			#   ⇒ 일치할 때는 **모양 테두리 + 스킬 아이콘이 함께** 보인다.
			# ⚠️ 이걸 if/else 로 배타 처리해서 "일치하는 칸에 끼우면 아이콘이 사라지는" 버그가 났다.
			# ☆칸은 스킬 타입(△□○)과 같아질 수 없으므로 모양 프레임 없이 아이콘만 나온다 — 원작 그대로.
			if String(sdef.get("slot", "")) == ty:
				_slot_icon(base, _common_tex(String(mark_of.get(ty, "common_skill_circle"))), 1.0)
			_slot_icon(base, _skill_tex(sid), 0.6)
			var ent := Loadout.equipped_entry(a, i)
			tip += "\n%s Lv.%d" % [String(sdef.get("name", "스킬")), int(ent.get("level", 1))]
			# 타입 일치(☆칸 포함) = 추가효과 발생 — `<ToolTipDragonSkillExplain>`.
			# 추가효과 수치는 서버 유실 → data/combat.json `skill_slot_match`:
			#   기본 = 스킬 피해 +power_pct%, **회복 계열은 최대 사용횟수 +1**(사용자 확정 2026-07-29).
			if Loadout.slot_matches(ty, sdef):
				tip += "  (타입 일치 · %s)" % Loadout.slot_match_label(sdef, Data.combat)
			tip += "\n(클릭: 스킬 교체)"
		else:
			tip += "\n비어 있음 (클릭: 장착)"
		var slot3 := i
		_slot_hit(bar, x, func(): _open_skill_select(slot3), tip)
	# 각성스킬 칸 — 원작은 각성했을 때만 `skill_evolution_bg` + `skill/evolution/<N>.png` 를 얹는다.
	if bool(a.get("awakened", false)):
		var base2 := _slot_base(bar, SLOT_X_AWAKEN, "")
		_slot_icon(base2, _common_tex("common_skill_evolution_bg"), 1.0)
		var aw := int(a.get("awaken_skill", 0))
		# ⚠️ 아이콘 번호는 각성스킬 번호와 다른 축이다 — 서로 다른 스킬이 같은 아이콘을 쓴다
		# (사용자 확인 2026-07-29, `docs/input/sheets/skill_awaken.csv` 의 `아이콘 id` 열).
		var icon := Data.awaken_skill_icon(aw) if aw > 0 else 0
		if icon > 0:
			var p := "res://assets/converted/skill_evolution/skill_evolution_%d.tres" % icon
			if ResourceLoader.exists(p):
				_slot_icon(base2, load(p), 0.6)
		var tip_aw := "각성 스킬"
		var row_aw: Dictionary = Data.skill_awaken_for(aw) if aw > 0 else {}
		if not row_aw.is_empty():
			tip_aw += "\n%s" % String(row_aw.get("name", ""))
		_slot_hit(bar, SLOT_X_AWAKEN, _open_awaken_skill, tip_aw)

## common_ui 아틀라스 텍스처(논리키). 없으면 null.
func _common_tex(key: String) -> Texture2D:
	if key == "":
		return null
	var p := "res://assets/converted/common_ui/%s.tres" % key
	return load(p) if ResourceLoader.exists(p) else null

## 스킬 아이콘(원작 `Skill::getImageSprite`). `_open_skills` 와 같은 경로를 쓴다.
func _skill_tex(sid: int) -> Texture2D:
	var p := "res://assets/converted/skill/skill_%d.tres" % sid
	return load(p) if ResourceLoader.exists(p) else null

## 스킬 칸 클릭 — 원작 `onClickSkill` → `SkillsPopup::setSelectTag(slot)` → 닫힐 때
## `setClosedSkillPopup` 이 `Dragon::setSkill(slot, skill)` 로 장착한다.
## 원작 `SkillsPopup::setSKillsList`(SkillsPopup.c:2757)는 **그 드래곤의 학습 풀**
## (`Dragon::getSkillList()`)을 목록으로 깔고, 선택 시 `equip_skill.hb`(dn/ns/level/slot),
## 해제(`disarmament`)는 같은 엔드포인트에 ns=0 을 보낸다. 우리도 같은 구조다.
## ⚠️ 종전엔 학습 풀이 없어서 "칸 간 교체"만 제공했다(2026-07-29 정정).
func _open_skill_select(slot: int) -> void:
	var a := _active()
	if a.is_empty(): return
	var uid := int(a["uid"])
	var pool: Array = UserDB.dragon_skills(uid)
	var equipped := Loadout.equipped_ids(a)
	var ty := String(Loadout.slot_types(a)[slot])
	_close_skill_modal()
	_skill_modal = CanvasLayer.new()
	_skill_modal.layer = 20
	add_child(_skill_modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_skill_modal.add_child(dim)
	var panel := _skill_modal_panel("%d번 스킬 칸 (%s)" % [slot + 1, String(_SKILL_SLOT_MARK.get(ty, "?"))])
	var body := _skill_modal_list(panel)
	if int(equipped[slot]) > 0:
		body.add_child(_skill_list_button("이 칸 비우기 (해제)",
			func(): _equip_skill(uid, slot, 0)))
	if pool.is_empty():
		body.add_child(_skill_list_button("(배운 스킬 없음 — 스킬 스크롤로 습득)", _close_skill_modal))
		return
	# 원작은 장착 제약이 없다(사용자 확인 2026-07-27) — 안 맞는 모양도 꽂히고 추가효과만 없다.
	for e in pool:
		var sid := int((e as Dictionary).get("id", 0))
		var lv := int((e as Dictionary).get("level", 1))
		var sdef: Dictionary = Data.skills.get(str(sid), {})
		var nm := String(sdef.get("name", "스킬 %d" % sid))
		var mark := String(_SKILL_SLOT_MARK.get(String(sdef.get("slot", "")), "?"))
		var tag := ""
		if sid == int(equipped[slot]):
			tag = "   (장착 중)"
		elif equipped.has(sid):
			tag = "   (다른 칸 → 교환)"
		elif Loadout.slot_matches(ty, sdef):
			tag = "   (타입 일치)"
		body.add_child(_skill_list_button("%s %s Lv.%d%s" % [mark, nm, lv, tag],
			func(): _equip_skill(uid, slot, sid)))
	body.add_child(_skill_list_button("스킬 목록 전체 보기", func(): _close_skill_modal(); _open_skills()))

## 칸에 장착/해제(원작 equip_skill.hb). skill_id=0 = 해제.
func _equip_skill(uid: int, slot: int, skill_id: int) -> void:
	UserDB.set_dragon_skill_equip(uid, slot, skill_id)
	_close_skill_modal(); _refresh(); _refresh_stats()
	if skill_id <= 0:
		_toast("스킬을 해제했습니다")
	else:
		_toast("%s 장착" % String(Data.skills.get(str(skill_id), {}).get("name", "스킬")))

## 각성스킬 칸 클릭 — 표시정보는 `data/skill_awaken.json`(원작 info_skill_awaken).
## 행값이 서버 유실이라 비어 있을 수 있다 → 그때는 안내만 한다(docs/input/review/skill_awaken_sheet.md).
func _open_awaken_skill() -> void:
	var a := _active()
	if a.is_empty(): return
	var no := int(a.get("awaken_skill", 0))
	var row: Dictionary = Data.skill_awaken_for(no) if no > 0 else {}
	if row.is_empty():
		_toast("각성 스킬 정보가 아직 없습니다 (docs/input/review/skill_awaken_sheet.md)")
		return
	# 효과가 실제로 전투에 실리는지 정직하게 알린다 — 설명만 있고 안 도는 것이 아직 많다
	# (data/skill_awaken.json `effect.impl`, 진행도는 같은 파일 `_effect_progress`).
	var eff: Dictionary = row.get("effect", {})
	var tail := ""
	if not bool(eff.get("impl", false)):
		tail = "\n\n(효과 미이식 — 표시만 됩니다)"
	else:
		# 조항이 여러 개인 스킬은 일부만 도는 수가 있다 — 무엇이 아직인지 그대로 알린다.
		var partial: Array = eff.get("partial", [])
		if not partial.is_empty():
			tail = "\n\n(아직 적용되지 않는 부분)"
			for line in partial:
				tail += "\n· %s" % String(line)
	_open_popup_type("각성 스킬", "%s\n\n%s%s" % [String(row.get("name", "")),
		String(row.get("comment", "")), tail], Callable(), "확인", "")

func _build_menu() -> void:
	# 우측 메뉴 — 원작 CaveScene::init 1:1 (근거 CaveScene.c:18894-19013):
	#   CCMenu(q_cave, book, skin, bag), 우측정렬 anchor(1.0,0.5), scale 1.2, 각 아이콘 + _bg.
	#   cocos 좌표(y-up): book(maxX,420) skin(maxX+6,310) bag(maxX,200) → 692공간 y-flip.
	#   ⚠️ q_cave_icon.png=추출 에셋 부재(asset-blocked) → 생략. card=원작 우측메뉴에 없음(onClickCard는
	#   별도 진입) → 제외. skin=onClickSkin→SkinPopup(테마/단상 스킨 선택, CaveScene.c:8622·8668)
	#   → _open_skin(테마/단상 2탭). (드래곤 body 스킨 makeAllSkinMenu는 드래곤 클릭 진입 — 별도.)
	var vis := _vis()
	_right_wall = Control.new()   # toggleSideWalls: 우측 벽(메뉴) 슬라이드 대상(position:x 슬라이드)
	_right_wall.position = Vector2.ZERO
	_right_wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_right_wall)
	# 원작 Cave.png 우측 벽은 아이콘 **4개**(사진/도감/카드/가방)다. 카드칸이 빠져 있었다(🟡).
	# `scene/cave/card.png` + `card_bg.png` 는 추출 에셋에 실재(DV2/480/scene/cave.img_plist 확인).
	# 원작 진입점 = CaveScene::onClickCard → CardsPopup(수집 카드). 우리는 도감의 카드 탭으로 잇는다.
	# 🟡 2026-07-28 정정(사용자 검수: "우측 아이콘이 밑으로 몰려 있다"):
	#   원작 사다리는 **110pt 등간격 530/420/310/200** 이다 (CaveScene.c:23927 q_cave 530 ·
	#   :23958 book 420 · :23997 skin 310 · :24037 bag 200 — 화면비 2.1 미만 분기).
	#   우리는 q_cave(프레임 부재) 자리를 비운 채 book 420 부터 시작하고 bag 만 112 로 내려
	#   4개가 아래쪽 272~580 에 몰려 있었다(간격도 110/110/88 로 불균등).
	#   → 아이콘 4개를 원작 사다리 그대로 530/420/310/200 에 놓는다(간격 110 균등).
	#   card 는 원작 우측메뉴에 없던 칸이라 비어 있던 q_cave 자리(530)가 아니라 원작 순서
	#   book→skin→bag 을 유지한 채 마지막에 붙인다.
	var items := [
		{"icon": "book", "bg": "book_bg", "cy": 530.0, "dx": 0.0, "cb": _open_dex},
		{"icon": "skin", "bg": "skin_bg", "cy": 420.0, "dx": 6.0, "cb": _open_skin},
		{"icon": "bag", "bg": "bag_bg", "cy": 310.0, "dx": 0.0, "cb": _open_inventory},
		{"icon": "card", "bg": "card_bg", "cy": 200.0, "dx": 0.0, "cb": _open_cards},
	]
	for it in items:
		_menu_button(it, vis.x)
	# 원작 toggleSideWalls: 드래곤을 가리지 않게 좌/우 UI 접기. 우측 가장자리 세로 중앙에 손잡이.
	var handle := Button.new()
	handle.text = "▶"
	handle.size = Vector2(28, 56); handle.position = Vector2(vis.x - 30.0, vis.y * 0.5 - 28.0)
	handle.add_theme_font_size_override("font_size", 18)
	handle.pressed.connect(_toggle_side_walls)
	add_child(handle)
	_wall_handle = handle
	# 칭호(원작 AchieveTitleLayer) 진입. 원작 우측 벽 아이콘은 4개(사진/도감/카드/가방)가 정답이라
	# 거기엔 끼우지 않고, 별도 작은 버튼으로 연다.
	var tb := Button.new()
	tb.text = "칭호"
	tb.size = Vector2(64, 30); tb.position = Vector2(vis.x - 100.0, 16.0)
	tb.add_theme_font_size_override("font_size", 15)
	tb.pressed.connect(_open_titles)
	add_child(tb)

var _left_wall: Control
var _right_wall: Control
var _wall_handle: Button
var _walls_open := true
func _toggle_side_walls() -> void:
	_walls_open = not _walls_open
	var vis := _vis()
	var lx := 0.0 if _walls_open else -(LIST_W + 20.0)   # 열림 = 화면 왼쪽 끝(원작 목록 x=0)
	var rx := 0.0 if _walls_open else 190.0
	if is_instance_valid(_left_wall):
		_left_wall.create_tween().tween_property(_left_wall, "position:x", lx, 0.3).set_trans(Tween.TRANS_CUBIC)
	if is_instance_valid(_right_wall):
		_right_wall.create_tween().tween_property(_right_wall, "position:x", rx, 0.3).set_trans(Tween.TRANS_CUBIC)
	if is_instance_valid(_wall_handle):
		_wall_handle.text = "▶" if _walls_open else "◀"

func _menu_button(it: Dictionary, screen_w: float) -> void:
	# 원작 우측메뉴 버튼: _bg(뒤) + 아이콘(앞), scale 1.2, 우측정렬. it={icon,bg,cy(cocos),dx,cb}.
	const SCALE := 1.2
	var icon: String = it["icon"]
	var bgw: float = float(_manifest.get("scene_cave_%s" % it["bg"], {}).get("w", 75)) * SCALE
	var cx := screen_w - 12.0 - bgw * 0.5 + float(it["dx"])   # 우측 가장자리 앵커(anchor 1.0)
	var cy := 692.0 - float(it["cy"])                          # cocos y-up → 692공간 y-flip
	var bg := _ui_sprite("scene_cave_%s" % it["bg"], SCALE)
	bg.position = Vector2(cx, cy)
	_right_wall.add_child(bg)
	var spr := _ui_sprite("scene_cave_%s" % icon, SCALE)
	spr.position = Vector2(cx, cy)
	_right_wall.add_child(spr)
	var b := Button.new()
	b.flat = true
	b.size = Vector2(bgw, bgw)
	b.position = Vector2(cx - bgw * 0.5, cy - bgw * 0.5)
	b.pressed.connect(it["cb"])
	_right_wall.add_child(b)

func _build_topbar() -> void:
	var vis := _vis()
	# 원작 동굴에는 좌상단 재화 표시가 없다(docs/ref/orig_image/cave/Cave.png) → 제거.
	# 골드/다이아는 마을 상단 메뉴바(TownMainMenuLayer)에서 확인한다.
	# 원작 동굴 상단은 **우상단 X 하나뿐**이고, 누르면 바로 유타칸 월드맵으로 나간다
	# (docs/ref/orig_image/cave/Cave.png + 사용자 확인 2026-07-26). 이전의 출전/퀘스트/이름/부화/외출
	# 텍스트 버튼 5개는 우리가 붙인 것 → 제거. 각 기능은 아래로 재배치:
	# 재배치(사용자 확인 2026-07-26 — 전부 원작에 제자리가 따로 있다):
	#   · 이름  → 하단 이름 칸 터치(원작 onClickNicName)
	#   · 퀘스트 → 마을 / 던전 탐험 중 (원작 위치, 이미 구현됨)
	#   · 출전  → 던전 입장 시 드래곤 선택 (원작 흐름)
	#   · 부화  → 인벤토리 '알' 탭에서 선택 (⚠️원작 메커니즘은 현 breeding 씬과 다름 — 별도 과제)
	# 🟠 2026-07-26 정정: 회색 사각 Button + "✕" 텍스트 자작이었다. 원작(docs/ref/orig_image/cave/Cave.png)은
	#   우상단에 큰 **빨간 ✖ 스프라이트** — `common/close_btn.png`(우리도 팝업들에서 이미 쓰는 프레임).
	var x := TextureButton.new()
	var xt := "res://assets/converted/common_ui/common_close_btn.tres"
	if ResourceLoader.exists(xt):
		x.texture_normal = load(xt)
		x.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
		x.position = Vector2(vis.x - 24.0 - 48.0 * Design.ASSET_SCALE, 16.0)
	else:
		x.position = Vector2(vis.x - 44.0, 8.0)
	x.pressed.connect(func(): Scenes.goto("worldmap", {"region": "yutakan"}))
	add_child(x)

# ---------- refresh ----------
func _refresh() -> void:
	var skin_idx: int = UserDB.get_skin("cave_skin") % SKIN_COUNT
	_bg.texture = load(BG % (skin_idx + 1))
	_build_walls()   # 테마와 같은 번호의 wall 적용(테마 변경 시 함께 갱신)
	_refresh_dragon()
	_refresh_quick()
	_refresh_list()
	_refresh_stats()
	_refresh_slots()   # 원작 setDragonInfo: 드래곤·장착이 바뀌면 슬롯도 다시 그린다

func _refresh_dragon() -> void:
	for ch in _stage.get_children():
		ch.queue_free()
	# 받침대: stand 스킨 (480/stand.png). 폭을 일정하게(620) 정규화하고, 받침대 '바닥'을
	# 고정 y(357)에 맞춰 하단 정렬 → 단상마다 높이가 달라도 디스크 위치가 일정하고
	# 키 큰 장식 단상이 하단 메뉴를 가리지 않음(장식은 위로 뻗음). stand1은 기존과 동일.
	var si: int = UserDB.get_skin("stand_skin") % STAND_COUNT
	var info = _stand_manifest.get("stand_stand%d" % (si + 1), {})
	var w: float = maxf(1.0, float(info.get("w", 305)))
	var h: float = maxf(1.0, float(info.get("h", 120)))
	var sc := 620.0 / w
	var ped := _atlas_sprite("stand_ui", "stand_stand%d" % (si + 1), _stand_manifest, sc)
	ped.position = Vector2(0, 357.0 - h * sc / 2.0)
	_stage.add_child(ped)
	# 먼지 파티클(레시피 §7: 받침대 주변에서 은은히 피어오름). 원본 earth_dust1 스프라이트가
	# 변환본에 없어 절차적 대체(포인트 모트). ASSUMPTION: 위치/톤은 F5로 보정. _stage와 함께 스케일.
	var dust := CPUParticles2D.new()
	dust.amount = 12
	dust.lifetime = 3.2
	dust.position = Vector2(0, 210)   # _stage local(1080공간) — 받침대 발치 근처
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(120, 8)
	dust.direction = Vector2(0, -1)
	dust.spread = 12.0
	dust.gravity = Vector2(0, -10)
	dust.initial_velocity_min = 10.0
	dust.initial_velocity_max = 26.0
	dust.scale_amount_min = 2.0
	dust.scale_amount_max = 5.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 0.97, 0.82, 0.55))
	grad.set_color(1, Color(1, 0.97, 0.82, 0.0))
	dust.color_ramp = grad
	_stage.add_child(dust)
	_build_stamina_gauge()
	var a := _active()
	if a.is_empty(): return
	# 원작: 부화 대기 중인 **알도 둥지 슬롯을 차지**한다(Dragon::setHatchTime).
	# 받침대 위에 알 초상 + 남은 시간(countDownBreed) 표시.
	# 참조: docs/ref/orig_image/cave/Screenshot_2016-05-22-02-24-05.png
	if UserDB.is_egg(a):
		_build_egg_on_stand(a)
		return
	# 원작 오라(발광 이펙트) — 드래곤 뒤에 렌더.
	# 🔴 2026-07-30 게이트 추가(사용자 지적): 종전엔 오라를 고르기만 하면 **성체에도** 구형 번개
	#   이펙트가 붙었다. 원작은 **오라성체(Lv.45 = 만렙)** 만 이펙트를 갖고, 성체는 스파인만이다.
	#   근거 = `Growth.AURA_ADULT_LEVEL`(클라 `Dragon.c:8265` 의 `level < 0x2d` 분기 + 회복물약
	#   레벨대 표기 "Lv.45~50(오라 성체)").
	# 오라성체 이펙트 = **그 드래곤의 속성 오라**(선택 기능은 위 주석대로 삭제됨).
	var _el := String(Data.get_dragon(int(a["id"])).get("element", ""))
	_apply_aura(_el if Growth.is_aura_adult(int(a["level"])) else "")
	var stage_name := Growth.stage_for_level(int(a["level"]))
	var path := DRAGON_SCENE % [int(a["id"]), stage_name]
	if ResourceLoader.exists(path):
		var holder := Node2D.new()
		holder.scale = Vector2(1.9, 1.9)
		holder.position = Vector2(0, -7)   # 발이 스탠드 중앙쯤(사용자 조정: 위로 30 screen px, _stage local -47)
		_stage.add_child(holder)
		var inst = load(path).instantiate()
		holder.add_child(inst)
		_dragon_ap = inst.get_node_or_null("AnimationPlayer")
		if _dragon_ap:
			if _dragon_ap.has_animation("love"):
				_dragon_ap.get_animation("love").loop_mode = Animation.LOOP_NONE  # 1회 재생
			_dragon_ap.animation_finished.connect(_on_dragon_anim_finished)
			if _dragon_ap.has_animation("wait"):
				_dragon_ap.play("wait")
	else:
		# 🔴재발방지(2026-07-26): 스파인 씬 미빌드 드래곤은 조용히 안 그려졌음(원인: 스파인 씬은
		# 저작권상 gitignore라 각 머신서 build 필요한데 일부만 빌드됨). 폴백으로 초상(박스 썸네일)을
		# 단상 위에 크게 표시 → 어떤 드래곤도 '안 보이는' 일이 없게. 경고로그로 미빌드 종을 표면화.
		var por := _portrait_sprite(int(a["id"]), stage_name, 2.6, int(a.get("skin", 0)))
		if por:
			por.position = Vector2(0, -30)
			_stage.add_child(por)
		push_warning("[cave] dragon %d(%s) 스파인 씬 미빌드 → 초상 폴백. `spine_batch %d`+build_all 필요"
			% [int(a["id"]), stage_name, int(a["id"])])
	# 🔴제거(2026-07-26): 머리 위 이름 말풍선은 원작에 없던 기능(사용자 확인) → 미표시.

## 원작 showBalloon(name_on/off): 활성 드래곤 머리 위 이름 말풍선(별명 우선, 없으면 원종명).
## 토글(pmeta "name_balloon", 기본 on)은 이름짓기 팝업에서 켜고 끈다. 시각 전용(스탯 무관).
var _name_balloon: Control
func _refresh_name_balloon() -> void:
	if is_instance_valid(_name_balloon): _name_balloon.queue_free()
	if not bool(UserDB.get_pmeta("name_balloon", true)): return
	var a := _active()
	if a.is_empty(): return
	var nick := String(a.get("nick", ""))
	var species := str(Data.get_dragon(int(a["id"])).get("name", "드래곤"))
	var txt := nick if nick != "" else species
	var vis := _vis()
	var font := ThemeDB.fallback_font
	var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var bw: float = maxf(96.0, tw + 56.0)
	var bh := 34.0
	var by := vis.y * 0.11
	_name_balloon = Control.new()
	_name_balloon.position = Vector2(vis.x * 0.5 - bw * 0.5, by)
	_name_balloon.size = Vector2(bw, bh + 12)
	add_child(_name_balloon)
	var panel := Panel.new()
	panel.size = Vector2(bw, bh)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.98, 0.9, 0.96)
	sb.set_border_width_all(2); sb.border_color = Color(0.85, 0.6, 0.25)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.28); sb.shadow_size = 4
	panel.add_theme_stylebox_override("panel", sb)
	_name_balloon.add_child(panel)
	var tail := Polygon2D.new()
	tail.polygon = PackedVector2Array([Vector2(bw * 0.5 - 9, bh - 1), Vector2(bw * 0.5 + 9, bh - 1), Vector2(bw * 0.5, bh + 11)])
	tail.color = Color(1, 0.98, 0.9, 0.96)
	_name_balloon.add_child(tail)
	var lbl := Label.new(); lbl.text = txt
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.16, 0.12, 0.06))
	lbl.size = Vector2(bw, bh); lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(lbl)
	var t := _name_balloon.create_tween().set_loops()
	t.tween_property(_name_balloon, "position:y", by - 6.0, 1.4).set_trans(Tween.TRANS_SINE)
	t.tween_property(_name_balloon, "position:y", by, 1.4).set_trans(Tween.TRANS_SINE)

## 원작 오라(AuraSelectPopLayer): 드래곤 주위 선택형 발광. per-드래곤 aura 키 → 색.
## 시각 전용(스탯 무관). scene_cave_dragon_bg_light(배경광) 틴트 + 상승 파티클을 드래곤 뒤에.
const AURAS := {
	"": {"name": "없음", "col": Color(1, 1, 1)},
	"fire": {"name": "불꽃", "col": Color(1.0, 0.45, 0.2)},
	"holy": {"name": "신성", "col": Color(1.0, 0.9, 0.45)},
	"aqua": {"name": "바다", "col": Color(0.35, 0.7, 1.0)},
	"dark": {"name": "암흑", "col": Color(0.7, 0.4, 1.0)},
	"wind": {"name": "바람", "col": Color(0.5, 1.0, 0.6)},
}
var _aura_node: Node2D
func _apply_aura(key: String) -> void:
	if is_instance_valid(_aura_node): _aura_node.queue_free()
	if key == "" or not AURAS.has(key): return
	# 원작 오라 애니: DV2/480/dragon/aura_{element} 플립북(9프레임). 색발광 대체.
	# 근거: Aura::getAuraImage → dragon/aura_{element}/auraNN.
	# 회전 패킹된 프레임은 변환 단계가 세워서 낱장 PNG 로 뽑는다(fix_rotated_frames.py) →
	# 여기서 프레임별 회전을 섞지 않는다(예전엔 프레임마다 -PI/2 를 걸어 플립북이 튀었다).
	var frames: Array = []
	for i in range(1, 10):
		var fn := "dragon_aura_%s_aura%02d" % [key, i]
		var t := load("res://assets/converted/aura_ui/%s.tres" % fn) if ResourceLoader.exists("res://assets/converted/aura_ui/%s.tres" % fn) else null
		if t:
			frames.append({"tex": t, "rot": 0.0})
	if frames.is_empty(): return
	var vis := _vis()
	_aura_node = Node2D.new(); _aura_node.z_index = 1
	_aura_node.position = Vector2(vis.x * 0.5, vis.y * 0.5 + 30.0)
	add_child(_aura_node)
	var spr := Sprite2D.new()
	var addmat := CanvasItemMaterial.new(); addmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	spr.material = addmat; spr.scale = Vector2(1.5, 1.5)
	_aura_node.add_child(spr)
	var tw := spr.create_tween().set_loops()
	for fr in frames:
		var ftex: Texture2D = fr["tex"]; var frot: float = fr["rot"]
		tw.tween_callback(func(): spr.texture = ftex; spr.rotation = frot)
		tw.tween_interval(0.1)

var _aura_man: Dictionary = {}
func _aura_manifest() -> Dictionary:
	if _aura_man.is_empty():
		var f := FileAccess.open("res://assets/converted/aura_ui/_manifest.json", FileAccess.READ)
		if f: _aura_man = JSON.parse_string(f.get_as_text())
	return _aura_man

func _on_dragon_clicked() -> void:
	if is_instance_valid(_dragon_ap) and _dragon_ap.has_animation("love"):
		_dragon_ap.play("love")   # 터치 반응
		# 원작도 터치 시 모션 + 보이스다(`CaveScene::onClickDragon` → `Dragon::getDragonVoiceDelay`).
		var a := _active()
		if not a.is_empty() and not UserDB.is_egg(a):
			_play_dragon_voice(int(a["id"]), int(a.get("level", 1)))

func _on_dragon_anim_finished(anim: StringName) -> void:
	# love 등 1회성 모션이 끝나면 대기로 복귀
	if anim != "wait" and is_instance_valid(_dragon_ap) and _dragon_ap.has_animation("wait"):
		_dragon_ap.play("wait")

# ---------- 퀵패널 (레시피 §6: 안전잠금 / 즐겨찾기) ----------
## 원작 makeQuickButton은 bt_quick으로 여닫는 9patch 세로패널이나, bt_quick/quick_bg 변환본이
## 없어 오프라인은 **받침대 옆 상시 세로 토글 2개**로 재설계(기능=Dragon lock/favorite 동일).
var _quick: Control

func _build_quick_panel() -> void:
	_quick = Control.new()
	_quick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_quick)

func _refresh_quick() -> void:
	if _quick == null: return
	for ch in _quick.get_children(): ch.queue_free()
	var a := _active()
	if a.is_empty(): return
	var uid := int(a["uid"])
	var vis := _vis()
	# 🟡 2026-07-26 정정: 받침대 **왼쪽**이다. 원작 docs/ref/orig_image/cave/Cave.png 에서 두 개의 소형 토글이
	#   받침대 좌측(드래곤 기준 왼쪽 아래)에 가로로 나란히 놓인다. 우리는 오른쪽 세로로 두고 있었다.
	var cx := vis.x / 2.0 - 176.0
	var cy := vis.y / 2.0 + 78.0
	_quick_toggle(cx - 28.0, cy, "safety", UserDB.is_locked(uid), _on_toggle_safety)
	_quick_toggle(cx + 32.0, cy, "favorite", UserDB.is_favorite(uid), _on_toggle_favorite)
	# 🔴제거(2026-07-26): 동굴 내 '음식' 버튼/텍스트 + 음식·피로 게이지 표시 미노출(원작 동굴에서 확인 불가, 사용자 확인).
	# 먹이주기 로직(_on_feed/_use_food)·피로 시스템/값은 유지(인벤 등 다른 경로에서 사용).

func _quick_toggle(cx: float, cy: float, kind: String, on: bool, cb: Callable) -> void:
	var frame := "scene_cave_bt_%s_%s" % [kind, "on" if on else "off"]
	var spr := _atlas_sprite("cave_ui", frame, _manifest, 1.15)
	spr.position = Vector2(cx, cy)
	if not on: spr.modulate = Color(1, 1, 1, 0.72)   # off는 살짝 흐리게
	_quick.add_child(spr)
	var b := Button.new()
	b.flat = true
	b.size = Vector2(52, 54)
	b.position = Vector2(cx - 26.0, cy - 27.0)
	b.pressed.connect(cb)
	_quick.add_child(b)

## 먹이주기: 활성 드래곤 exp +30(ASSUMPTION: 정확 급양량 유실) + love 모션 + 토스트.
func _on_feed() -> void:
	var a := _active()
	if a.is_empty(): return
	UserDB.add_exp(int(a["uid"]), 30)
	if is_instance_valid(_dragon_ap) and _dragon_ap.has_animation("love"):
		_dragon_ap.play("love")
	_toast("냠냠!  +EXP 30")

## 인벤 food 아이템 사용: 1개 소비 → 드링크 버프 / 회복물약 / 일반 먹이(+EXP)로 분기.
## 드링크·회복물약 수치 = data/item_effects.json (규칙 출처 docs/ref/wiki/item.pdf §2.2/§2.3,
## 수치는 사용자 확정 2026-07-26). 판정은 ItemEffect(logic 층).
func _use_food(key: String) -> void:
	var a := _active()
	if a.is_empty() or UserDB.item_count(key) <= 0: return
	var defs: Dictionary = Data.item_effects
	# ① 드링크(버프 물약) — 능력치 %상승, 중복 복용 시 지속시간만 연장(위키 규칙).
	var drink := ItemEffect.drink_of(defs, key)
	if not drink.is_empty():
		var uid := int(a["uid"])
		var cur: Dictionary = UserDB.get_dragon(uid).get("drink_buffs", {})
		UserDB.set_dragon_field(uid, "drink_buffs", ItemEffect.apply_drink(cur, drink))
		UserDB.add_item(key, -1)
		Bgm.sfx("effect_button")
		const KR := {"att": "공격력", "def": "방어력", "hp": "생명력",
			"crit": "크리티컬", "dodge": "회피", "block": "방어확률"}
		_toast("%s +%d%%  (%d턴)" % [KR.get(String(drink["stat"]), String(drink["stat"])),
			int(drink["pct"]), int(drink["turns"])])
		_refresh_stats(); _inventory_refresh_grid(); _inventory_refresh_detail()
		return
	# ② 회복 물약 — 최대 체력의 N% 회복. 단계별 사용 가능 레벨대는 위키 §2.2.
	if key.begins_with("heal_potion"):
		var uid2 := int(a["uid"])
		var lv := int(a.get("level", 1))
		if not ItemEffect.heal_usable(defs, key, lv):
			_toast("이 드래곤 레벨(%d)에는 쓸 수 없는 물약입니다" % lv)
			return
		var stats := Growth.compute_stats(Data.get_dragon(int(a["id"])), Data.stat_table, lv,
			a.get("stat_bonus", {}))
		var hp_max := int(stats.get("hp", 1))
		var hp_now := int(a.get("hp", hp_max))
		var amt := ItemEffect.heal_amount(defs, hp_now, hp_max)
		if amt <= 0:
			_toast("이미 체력이 가득 찼습니다")
			return
		UserDB.set_dragon_field(uid2, "hp", mini(hp_max, hp_now + amt))
		UserDB.add_item(key, -1)
		Bgm.sfx("effect_button")
		_toast("체력 +%d 회복" % amt)
		_refresh_stats(); _inventory_refresh_grid(); _inventory_refresh_detail()
		return
	# ③ 먹이(subcategory=feed) — **속성이 맞아야** 먹고, 먹으면 허기(FOOD)가 회복된다.
	#    사용자 확정(2026-07-30): 원작 후기판은 피로도가 삭제되고 허기만 남았고, 회복 수단은
	#    그 드래곤 속성에 맞는 먹이다. **속성당 2종 중 하나는 절반, 하나는 전량** 회복.
	#    판정 = `ItemEffect`(logic 층) · 데이터 = items.json `subcategory=feed` 18종의 `element`
	#    + item_effects.json `feed.half`/`feed.full`.
	var idef: Dictionary = Data.get_item(key)
	var dragon_el := String(Data.get_dragon(int(a["id"])).get("element", ""))
	if ItemEffect.is_feed(idef) and not ItemEffect.feed_matches(idef, dragon_el):
		# 안 맞는 먹이는 **소비하지 않는다** — 원작도 속성 먹이만 받는다.
		_toast("%s 속성 드래곤은 이 먹이를 먹지 않습니다" % _ELEM_KR.get(dragon_el, dragon_el))
		return
	# 그 외 먹이 — 등급 접미사(1~3) 있으면 그만큼 EXP↑. 없으면 기본 30.
	var exp := 30
	if key.length() > 0 and key[key.length() - 1].is_valid_int():
		exp = 30 * int(key[key.length() - 1])
	UserDB.add_item(key, -1)
	UserDB.add_exp(int(a["uid"]), exp)
	var fed := ItemEffect.is_feed(idef)
	if fed:
		# 회복량은 먹이 종류가 정한다 — 속성당 2종 중 작은 쪽(조각/치어/다리…)은 절반만.
		UserDB.set_dragon_field(int(a["uid"]), "food",
			ItemEffect.food_after_feed(defs, idef, key, dragon_el,
				int(a.get("food", ItemEffect.food_max(defs)))))
	if is_instance_valid(_dragon_ap) and _dragon_ap.has_animation("love"):
		_dragon_ap.play("love")
	# 먹이 문구는 사용자 확정(2026-07-30). 먹이가 아닌 음식(과자 등)은 종전 표기를 쓴다.
	_toast("드래곤이 맛있게 먹이를 먹었습니다." if fed else "냠냠!  +EXP %d" % exp)
	_refresh_quick()
	_refresh_stamina()
	_refresh_stats()
	_inventory_refresh_grid(); _inventory_refresh_detail()

## 레벨 자동 습득(10·25·45)으로 방금 늘어난 스킬 이름들. `UserDB.sync_skill_grants` 는
## 학습 풀 **끝에** 덧붙이므로 이전 크기 뒤쪽만 보면 된다.
func _skills_learned_since(uid: int, before_size: int) -> Array:
	var pool: Array = UserDB.dragon_skills(uid)
	var out: Array = []
	for i in range(before_size, pool.size()):
		var sid := int((pool[i] as Dictionary).get("id", 0))
		out.append(String(Data.skills.get(str(sid), {}).get("name", "스킬")))
	return out

var _toast_lbl: Label   # ⚪ 미사용(호환용) — 실제 표시는 Toast 헬퍼가 한다.

## 짧은 안내 문구 — 원작 `GameManager::showToast` @014c193c. 레시피는 `scripts/ui/toast.gd`.
## (2026-07-29 이전엔 배경 없는 노란 라벨을 자작해 쓰고 있었다 — 원작은 반투명 검정 상자 +
##  `font_common` BMFont 흰 글씨다. 전역 함수 하나가 소유하는 물건이라 공용 헬퍼로 모았다.)
func _toast(text: String) -> void:
	Toast.show(self, text)

## 🔴 제거(2026-07-30): `_on_rest`(휴식 → 피로도 0). 사용자 확정 —
##   원작 초기의 **피로도 5칸(시간 회복)은 후기판에서 삭제**됐고 우리는 구현하지 않는다.
##   지금 소모되는 것은 **허기(FOOD)** 이고 회복 수단은 속성이 맞는 먹이뿐이다
##   (`_use_food` ③ 분기 · 규칙 = `ItemEffect`). 호출부도 없던 죽은 코드였다.

func _on_toggle_safety() -> void:
	var a := _active()
	if a.is_empty(): return
	UserDB.toggle_locked(int(a["uid"]))
	_refresh_quick()
	_refresh_list()   # 슬롯 잠금 뱃지 갱신

func _on_toggle_favorite() -> void:
	var a := _active()
	if a.is_empty(): return
	UserDB.toggle_favorite(int(a["uid"]))
	_refresh_quick()
	_refresh_list()   # 슬롯 즐겨찾기 뱃지 갱신

## 드래곤 단계 박스 썸네일(480/dragon/dragon_{N}.png의 box_<stage>). 도감에서도 재사용.
func _portrait_sprite(id: int, stage: String, scale := 1.0, skin := 0) -> Sprite2D:
	var dir := "portrait_%d" % id
	if not _portrait_manifests.has(dir):
		var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
		_portrait_manifests[dir] = JSON.parse_string(f.get_as_text()) if f else {}
	# 원작 드래곤 스킨(requestDragonSkin): skin>0이고 변형 초상이 있으면 그걸로.
	var frame := "dragon_dragon_%d_box_%s" % [id, stage]
	if skin > 0:
		var sframe := "%s_skin%d" % [frame, skin]
		if _portrait_manifests[dir].has(sframe): frame = sframe
	return _atlas_sprite(dir, frame, _portrait_manifests[dir], scale)

## 드래곤이 스킨 변형 초상을 보유하는지(현 에셋: skin1만, 소수 드래곤). 없으면 스킨 메뉴 미표시.
func _dragon_skin_count(id: int) -> int:
	var n := 0
	for s in range(1, 4):
		if ResourceLoader.exists("res://assets/converted/portrait_%d/dragon_dragon_%d_box_adult_skin%d.tres" % [id, id, s]):
			n = s
		else:
			break
	return n

func _refresh_list() -> void:
	for ch in _list_box.get_children():
		ch.queue_free()
	var owned: Array = UserDB.dragons()
	var active := UserDB.active_uid()
	for d in owned:
		_list_box.add_child(_dragon_slot(int(d["id"]), int(d["level"]), int(d["uid"]), int(d["uid"]) == active))
	# 원작 Cave.png: 보유 드래곤 아래로 **잠긴 둥지 슬롯**이 자물쇠 아이콘으로 이어진다
	# (CaveScene::addDragonSlot + 리터럴 프레임 `common/lock.png`, docs/ref/audit/CaveScene.md).
	# 슬롯 총량은 서버(둥지 확장 상품) 데이터라 유실 → 보유수+2를 상한으로 둔다(# ASSUMPTION).
	var locked := maxi(0, mini(_NEST_SLOTS, owned.size() + 2) - owned.size())
	for i in locked:
		_list_box.add_child(_locked_slot())

const _NEST_SLOTS := 12
## 잠긴 둥지 슬롯 — 원작 `addScroll` 꼬리(보유수 초과분):
##   `common/dragon_bg2`(불투명도 225) + `common/lock`(중심 +5pt 위, 불투명도 125) + `dragon_cover2`(125).
func _locked_slot() -> Control:
	var S := Design.ASSET_SCALE
	var cm := _man_common()
	var parts := _slot_cell()
	var slot: Control = parts[0]
	var cell: Node2D = parts[1]
	var bg := _atlas_sprite("common_ui", "common_dragon_bg2", cm, S)
	bg.modulate = Color(1, 1, 1, 225.0 / 255.0)   # 원작 setOpacity(0xe1)
	cell.add_child(bg)
	var lk := _atlas_sprite("common_ui", "common_lock", cm, S)
	lk.position = Vector2(0, -5.0)               # 원작 (w/2, h/2 + 5)
	lk.modulate = Color(1, 1, 1, 125.0 / 255.0)  # 원작 setOpacity(0x7d)
	cell.add_child(lk)
	var cov := _atlas_sprite("common_ui", "common_dragon_cover2", cm, S)
	cov.modulate = Color(1, 1, 1, 125.0 / 255.0)
	cell.add_child(cov)
	return slot

## 좌측 둥지 슬롯 1칸 — 원작 `CaveScene::addScroll` 의 `CCMenuItemImageEx` 하나를 그대로 옮긴 것.
##
## 원작 레시피(리터럴 그대로):
##   프레임 = 활성 `common/dragon_bg1` + `common/dragon_cover1`(금테) /
##            비활성 `common/dragon_bg2` + `common/dragon_cover2`  (bg 81×81px → 108pt)
##   초상   = `Dragon::getImagePathBox` ×**0.9**, 셀 중심 **+(0, 7.5)**
##   레벨   = `getString("level", lv)` · `font_subtitle` BMFont ×**0.8**, (셀폭/2, 라벨높이/2 + 5) = 셀 하단
##   셀 전체 `setScale(0.95)`, 셀 중심 x = **셀폭/2 + 2.5**, 세로 간격 = 셀높이 + 5
##
## 셀 "폭/높이"는 프레임(108pt)이 아니라 **`CCMenuItemImageEx::create(..., 1.05)` 가 키운 박스**
## = 108 × 1.05 = **113.4pt** 다. 근거 두 가지:
##   ① 원작 `setLeftWallLayer` 의 스크롤 콘텐츠 높이 = `N*103 + (N+1)*15 + 30` → 칸당 **118pt**
##      (= 113.4 + 5). 프레임 그대로(108+5=113)면 이 식과 안 맞는다.
##   ② 레퍼런스 실측(`docs/ref/orig_image/cave/Cave.png`, 1582×894 → 1pt=1.292px):
##      잠긴 슬롯 4·5 의 액자 상단 = y 478 / 630 → 간격 152px = **117.6pt** ✓,
##      선택 슬롯(금테) 가로 중심 = x 78px = 60.4pt ≈ 113.4/2 + 2.5 = **59.2pt** ✓
## 🔴 2026-07-30 정정: 종전엔 `scene/worldmap/status_currentdragon_bg`(월드맵 HUD의 현재드래곤 액자)를
##   쓰고 크기도 1080공간 132×124(=113pt)로 잡아, 110pt 뷰에서 오른쪽이 잘렸다. 프레임·수치 모두 원작으로.
## 🟠 우리 추가분: 안전잠금/즐겨찾기 뱃지(원작 목록엔 없다 — 원작은 받침대 옆 `bt_safety`/`bt_favorite` 버튼으로만 표시).
const _SLOT_SCALE := 0.95   # 원작 addScroll: item->setScale(0.95)
const _SLOT_PAD_X := 2.5    # 원작: 셀 중심 x = 셀박스/2 + 2.5
const _SLOT_BOX := 1.05     # 원작 CCMenuItemImageEx::create(..., 1.05) 가 키운 박스 배수

## 액자 프레임 한 변(= `common/dragon_bg2` 81px × 4/3 = 108pt).
func _slot_side() -> float:
	return float(_man_common().get("common_dragon_bg2", {}).get("w", 81)) * Design.ASSET_SCALE

## 셀 컨테이너(Control) + 원작 좌표계(중심 원점, 0.95 배)를 갖는 내부 Node2D 를 만든다.
## 반환 = [slot(Control), cell(Node2D, 원점=셀 중심), box(셀 박스 한 변)]
func _slot_cell() -> Array:
	var box := _slot_side() * _SLOT_BOX
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(LIST_W, box)
	var cell := Node2D.new()
	cell.position = Vector2(_SLOT_PAD_X + box * 0.5, box * 0.5)
	cell.scale = Vector2(_SLOT_SCALE, _SLOT_SCALE)
	slot.add_child(cell)
	return [slot, cell, box]

func _dragon_slot(id: int, level: int, uid: int, is_active: bool) -> Control:
	var S := Design.ASSET_SCALE
	var cm := _man_common()
	var parts := _slot_cell()
	var slot: Control = parts[0]
	var cell: Node2D = parts[1]
	var box: float = parts[2]
	var half := _slot_side() * 0.5   # 액자 프레임 반지름(뱃지를 액자 안쪽에 두기 위한 기준)
	# 프레임(common.img_plist) — 활성만 금테(bg1/cover1)
	cell.add_child(_atlas_sprite("common_ui",
		"common_dragon_bg1" if is_active else "common_dragon_bg2", cm, S))
	# 단계 썸네일 ×0.9, 중심에서 7.5pt 위(원작 +(0,7.5) → Godot 은 y 반대)
	var por := _portrait_sprite(id, Growth.stage_for_level(level), 0.9 * S)
	por.position = Vector2(0, -7.5)
	cell.add_child(por)
	# 액자 테두리(초상 위) — 원작 addChild(cover, z=1, tag=6)
	cell.add_child(_atlas_sprite("common_ui",
		"common_dragon_cover1" if is_active else "common_dragon_cover2", cm, S))
	# 🟠 상태 뱃지(우리 추가분): 안전잠금=좌상, 즐겨찾기=우상 — 액자 안쪽에 얹는다.
	if UserDB.is_locked(uid):
		var lk := _atlas_sprite("cave_ui", "scene_cave_bt_safety_on", _manifest, 0.5 * S)
		lk.position = Vector2(-half + 16.0, -half + 16.0)
		cell.add_child(lk)
	if UserDB.is_favorite(uid):
		var fv := _atlas_sprite("cave_ui", "scene_cave_bt_favorite_on", _manifest, 0.5 * S)
		fv.position = Vector2(half - 16.0, -half + 16.0)
		cell.add_child(fv)
	# 레벨 — 원작 문자열 "레벨 %d"(`level`), font_subtitle ×0.8, 셀 박스 하단에서 5pt 위
	var lv := Label.new()
	lv.text = "레벨 %d" % level
	_lvup_bm_style(lv, int(round(19.0 * S * 0.8)), Color.WHITE, "font_subtitle")
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lv.size = Vector2(box, 26.0)
	lv.position = Vector2(-box * 0.5, box * 0.5 - 5.0 - 26.0)
	cell.add_child(lv)
	# 클릭(투명) — 원작 changeDragon
	var b := Button.new()
	b.flat = true
	b.size = Vector2(LIST_W, box)
	b.pressed.connect(func():
		UserDB.set_active(uid)
		_refresh())
	slot.add_child(b)
	return slot

## 부화 대기 알을 받침대 위에 표시(원작 CaveScene countDownBreed + Dragon::getHatchTime).
## 알 초상 = `dragon/dragon_<id>/egg.png`. 타이머 표기 = Hatchery.format_remain(원작 포맷).
var _egg_timer_label: Label = null
var _egg_uid := 0
func _build_egg_on_stand(a: Dictionary) -> void:
	# 알 프레임은 `dragon_dragon_<id>_egg`(box_ 접두 없음) — 도감과 같은 규약을 쓴다.
	var did := int(a["id"])
	var pdir := "portrait_%d" % did
	if not _portrait_manifests.has(pdir):
		var pf := FileAccess.open("res://assets/converted/%s/_manifest.json" % pdir, FileAccess.READ)
		_portrait_manifests[pdir] = JSON.parse_string(pf.get_as_text()) if pf else {}
	var egg := _atlas_sprite(pdir, _dex_stage_frame(did, "egg"), _portrait_manifests[pdir], 1.35)
	if egg:
		egg.position = Vector2(0, 120)
		_stage.add_child(egg)
		# 은은한 흔들림(원작 setActionEgg 계열 — 부화 대기 중 알이 살짝 움직인다).
		var tw := egg.create_tween().set_loops()
		tw.tween_property(egg, "rotation_degrees", 3.0, 1.1).set_trans(Tween.TRANS_SINE)
		tw.tween_property(egg, "rotation_degrees", -3.0, 1.1).set_trans(Tween.TRANS_SINE)
	# 받침대 앞 남은시간 패널(원작: 받침대 전면에 타이머).
	var plate := NinePatchRect.new()
	plate.texture = load("res://assets/converted/ninepatch_ui/9patch_box1.tres")
	plate.patch_margin_left = 18; plate.patch_margin_right = 18
	plate.patch_margin_top = 14; plate.patch_margin_bottom = 14
	plate.size = Vector2(240, 62); plate.position = Vector2(-120, 262)
	_stage.add_child(plate)
	_egg_timer_label = Label.new()
	_egg_timer_label.add_theme_font_size_override("font_size", 30)
	_egg_timer_label.add_theme_color_override("font_color", Color(0.18, 0.12, 0.05))
	_egg_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_egg_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_egg_timer_label.size = plate.size
	plate.add_child(_egg_timer_label)
	_egg_uid = int(a["uid"])
	_tick_egg()

## 매초 남은 시간 갱신(원작 countDownBreed). 0이 되면 레벨1로 부화.
func _tick_egg() -> void:
	if _egg_uid == 0 or not is_instance_valid(_egg_timer_label):
		return
	var d := UserDB.get_dragon(_egg_uid)
	if d.is_empty() or not UserDB.is_egg(d):
		return
	var remain := UserDB.hatch_remain(d)
	_egg_timer_label.text = Hatchery.format_remain(remain)
	if remain <= 0:
		_hatch_now(_egg_uid)
		return
	var t := get_tree().create_timer(1.0)
	t.timeout.connect(_tick_egg)

## 부화 완료: 초기 등급을 stat_bonus로 환산해 레벨1 드래곤이 된다.
func _hatch_now(uid: int) -> void:
	var d := UserDB.get_dragon(uid)
	if d.is_empty(): return
	var grade := float(d.get("egg_grade", Growth.BASE_GRADE))
	if UserDB.hatch_egg(uid, Hatchery.stat_bonus_for_grade(grade)):
		_egg_uid = 0
		_refresh()
		_toast("부화 완료!  등급 %.1f" % grade)

## 하단 이름/등급/스탯판 갱신. 젬·장비 변경도 스탯에 반영되므로 **슬롯도 같이** 다시 그린다
## (원작 setDragonInfo 는 둘을 한 함수에서 그린다 — 따로 갱신하면 어긋난다).
## 이름 칸 문자열은 **칸 정중앙**에 온다(사용자 검수 2026-07-28). 대입은 전부 여기를 거친다 —
## 한 곳이라도 `_name_label.text` 를 직접 쓰면 그 줄만 좌측 정렬로 돌아간다.
func _set_name(bb: String) -> void:
	_name_label.text = "[center]%s[/center]" % bb

func _refresh_stats() -> void:
	_refresh_slots()
	var a := _active()
	if a.is_empty():
		_set_name("보유 드래곤 없음")
		for k in ["hp", "att", "def"]:
			if _stat_plates.get(k): (_stat_plates[k] as Label).text = "-"
		_grade_label.text = "-"
		return
	var d: Dictionary = Data.get_dragon(int(a["id"]))
	var lv := int(a["level"])
	var bonus: Dictionary = a.get("stat_bonus", {})
	# 실 스탯 = base + 영구base보정 + Σ레벨업 롤(gain_log). §K-1 정정(랜덤롤 모델).
	var base_bonus: Dictionary = (bonus as Dictionary).get("base", {})
	var main := Growth.main_stats(d, Data.stat_table, a.get("gain_log", []), base_bonus)
	var s := main.duplicate()
	# 장착 젬 = 실 스탯 위에 플랫 가산(교체 가능한 장비 계층).
	var g: Dictionary = a.get("gems", {})
	for gk in ["hp", "att", "def"]:
		s[gk] = int(s[gk]) + int(g.get(gk, 0))
	_grade_label.text = "%.1f" % _grade_of(a, d)
	# 원작 이름표(onClickNicName): 별명이 있으면 별명 우선, 원종명은 작게 병기.
	var nick := String(a.get("nick", ""))
	var species := str(d.get("name", "?"))
	if nick != "":
		_set_name("레벨 %d  %s  [color=#b8b0a0][font_size=18](%s)[/font_size][/color]" % [lv, nick, species])
	else:
		_set_name("레벨 %d  %s" % [lv, species])
	_update_elem_icon(str(d.get("element", "")))
	# 원작 알 상태(ref/orig_image/cave/Screenshot_2016-05-22-02-24-05.png): 스탯은 ???로 가려지고
	# 이름 앞에 "+N"(연구소 알 강화 단계) 배지가 붙는다. 단계는 `_start_hatch` 가 심어 준다.
	if UserDB.is_egg(a):
		var enh := int(a.get("egg_enhance", 0))
		var pre := ("[color=#f0c040]+%d[/color] " % enh) if enh > 0 else ""
		_set_name("%s%s" % [pre, species])
		for k2 in ["hp", "att", "def"]:
			if _stat_plates.get(k2): (_stat_plates[k2] as Label).text = "???"
		_grade_label.text = "-"
		return
	# 표시: 실 스탯(레벨업 롤 누적 포함) + (+젬·잠재 장비 보정). 장비를 바꾸면 괄호값이 변동.
	# 원작 Cave.png: 스탯 3종을 각각 플레이트에 표시(라벨 위·값 아래). 보정치는 값 옆 작게.
	for k in ["hp", "att", "def"]:
		var lab: Label = _stat_plates.get(k)
		if lab == null:
			continue
		var extra: int = int(s[k]) - int(main[k])
		lab.text = ("%d (+%d)" % [int(main[k]), extra]) if extra != 0 else str(int(main[k]))

## 파생 등급(§K-10). 부화 편차(stat_bonus) + 레벨업 롤 편차(gain_log)를 **둘 다** 넘긴다.
## 🔴 2026-07-27: gain_log 를 안 넘겨 아모르의 축복(초월맥스)이 등급에 반영되지 않던 버그.
## 기준선 모드는 data 노브(`level_curve.json` 의 `grade`) — logic 이 파일을 모르게 여기서 주입한다(§8.2).
func _grade_of(inst: Dictionary, ddef: Dictionary) -> float:
	return Growth.compute_grade(ddef, Data.stat_table, inst.get("stat_bonus", {}),
		inst.get("gain_log", []), Data.level_curve.get("grade", {}))

## 원작 onClickElement: 활성 드래곤 속성의 상성표(강함/약함) 팝업. 배수=전투 상성(1.25/0.85).
const _ELEM_KR := {"fire": "불", "aqua": "물", "wind": "바람", "earth": "땅", "light": "빛",
	"dark": "어둠", "holy": "신성", "chaos": "혼돈", "shadow": "그림자"}
func _open_element_info() -> void:
	var a := _active()
	if a.is_empty(): return
	var el := str(Data.get_dragon(int(a["id"])).get("element", ""))
	if el == "": return
	var ecfg: Dictionary = Data.combat.get("element", {})
	var good: Array = ecfg.get("good_vs", {}).get(el, [])
	var bad: Array = ecfg.get("bad_vs", {}).get(el, [])
	var vis := _vis()
	# 드래곤 spine이 별도 CanvasLayer(상위)라 팝업도 높은 레이어에 올려야 위로 나온다.
	var layer := CanvasLayer.new(); layer.layer = 50; add_child(layer)
	var pop := Control.new(); pop.set_anchors_preset(Control.PRESET_FULL_RECT); layer.add_child(pop)
	pop.tree_exiting.connect(func(): if is_instance_valid(layer): layer.queue_free())
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: pop.queue_free())
	pop.add_child(dim)
	var panel := _orig_popup(pop, Vector2(460, 330), "%s 속성 상성" % _ELEM_KR.get(el, el))
	var title := Label.new()
	title.text = ""
	title.size = Vector2(460, 36); title.position = Vector2(0, 18)
	panel.add_child(title)
	_elem_row(panel, "강함 (×1.25)", good, Color(0.5, 1, 0.5), 74)
	_elem_row(panel, "약함 (×0.85)", bad, Color(1, 0.6, 0.5), 170)
	var close := Button.new(); close.text = "닫기"; close.size = Vector2(120, 40)
	close.position = Vector2(170, 280); close.pressed.connect(func(): pop.queue_free()); panel.add_child(close)

## 원작 TutorialLayer: 최초 1회 온보딩 안내(단계형 카드). UserDB.pmeta("tutorial_seen")로 1회 제어.
const _TUTORIAL := [
	{"title": "드래곤 빌리지에 오신 걸 환영합니다!", "body": "이곳은 '둥지' — 드래곤을 키우고 관리하는 공간입니다.\n좌측 목록에서 드래곤을 선택할 수 있어요."},
	{"title": "드래곤 강화", "body": "왼쪽 위 등급 배지를 누르면 상세 창이 열립니다.\n진화 · 젬 · 장신구 · 잠재능력 · 각성 · 오라 · 축복으로\n드래곤을 강하게 키우세요."},
	{"title": "전투 & 던전", "body": "상단 '출전'으로 파티(최대 3)를 짜고,\n'외출' → 월드맵 → 던전에서 전투하세요.\n속성 상성(강함 ×1.25)을 활용하면 유리합니다!"},
	{"title": "수집 & 성장", "body": "'부화'로 새 드래곤을 얻고,\n'퀘스트'와 마을 상점으로 골드·아이템을 모으세요.\n즐거운 모험 되세요!"},
]
func _maybe_tutorial() -> void:
	if bool(UserDB.get_pmeta("tutorial_seen", false)): return
	_show_tutorial_step(0)

func _show_tutorial_step(idx: int) -> void:
	if idx >= _TUTORIAL.size():
		UserDB.set_pmeta("tutorial_seen", true)
		return
	var step: Dictionary = _TUTORIAL[idx]
	var vis := _vis()
	var overlay := CanvasLayer.new(); overlay.layer = 40; add_child(overlay)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.62); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var win := _orig_popup(overlay, Vector2(600, 300), "")
	var t := Label.new(); t.text = String(step["title"])
	t.add_theme_font_size_override("font_size", 26); t.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; t.size = Vector2(600, 36); t.position = Vector2(0, 26); win.add_child(t)
	var b := Label.new(); b.text = String(step["body"])
	b.add_theme_font_size_override("font_size", 18); b.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; b.size = Vector2(560, 130); b.position = Vector2(20, 84); win.add_child(b)
	# 단계 표시 점
	var dots := Label.new()
	var ds := ""
	for i in _TUTORIAL.size(): ds += ("●" if i == idx else "○")
	dots.text = ds; dots.add_theme_font_size_override("font_size", 18); dots.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; dots.size = Vector2(600, 24); dots.position = Vector2(0, 214); win.add_child(dots)
	var last := idx >= _TUTORIAL.size() - 1
	var nextb := Button.new(); nextb.text = "시작하기" if last else "다음"
	nextb.size = Vector2(150, 46); nextb.position = Vector2(win.size.x - 180, win.size.y - 62)
	nextb.pressed.connect(func(): overlay.queue_free(); _show_tutorial_step(idx + 1))
	win.add_child(nextb)
	if not last:
		var skip := Button.new(); skip.text = "건너뛰기"; skip.size = Vector2(120, 46); skip.position = Vector2(30, win.size.y - 62)
		skip.pressed.connect(func(): UserDB.set_pmeta("tutorial_seen", true); overlay.queue_free())
		win.add_child(skip)

## 일일 퀘스트(둥지에서 확인/수령). town과 동일 데이터/일일 카운터(UserDB quest_count/claim_quest).
const _QUESTS := [
	{"key": "battles", "label": "전투 승리", "goal": 3, "gold": 300},
	{"key": "hatches", "label": "부화하기", "goal": 1, "gold": 200},
]

## 칭호 — 원작 `AchieveTitleLayer` 1:1 구조.
## 근거(docs/ref/audit/AchieveTitleLayer.md): 9patch/popup4 창 + CCTableView 목록 +
##   획득 표시 `common/checked.png` + 상세 `PopupTypeLayer`. 칭호 아트 = title/<no>_kr.png(149종).
## ⚠️ 획득 조건은 원작이 서버 소유(RequestTitle/ResponseTitle)라 유실 → 자작
##    (사용자 승인 2026-07-27). data/titles.json unlock, 노브 = scripts/tools/build_titles.py.
func _title_progress() -> Dictionary:
	var maxlv := 0
	for d in UserDB.dragons():
		maxlv = maxi(maxlv, int((d as Dictionary).get("level", 1)))
	return {
		"dragons": UserDB.dragons().size(),
		"hatches": UserDB.quest_count("hatches"),
		"battles": UserDB.quest_count("battles"),
		"max_level": maxlv,
		"gold": UserDB.gold(),
	}

func _open_titles() -> void:
	var table: Dictionary = Data.titles
	if table.is_empty():
		_toast("칭호 데이터가 없습니다"); return
	var prog := _title_progress()
	var view := Titles.sorted_for_view(prog, table)
	var got := Titles.unlocked_nos(prog, table).size()
	const BW := 640.0
	const BH := 520.0
	var vis := _vis()
	var overlay := CanvasLayer.new(); overlay.layer = 30; add_child(overlay)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: overlay.queue_free())
	overlay.add_child(dim)
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	overlay.add_child(win)
	var tbar := NinePatchRect.new(); tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(BW * 0.9, 56); tbar.position = Vector2((BW - BW * 0.9) * 0.5, 14); win.add_child(tbar)
	var t := Label.new(); t.text = "칭호  %d / %d" % [got, (table.get("titles", []) as Array).size()]
	t.add_theme_font_size_override("font_size", 24); t.add_theme_color_override("font_color", Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size = tbar.size; tbar.add_child(t)
	var cb := TextureButton.new(); cb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	cb.position = Vector2(BW - 72, 8); win.add_child(cb)
	cb.pressed.connect(func(): overlay.queue_free())
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(36, 86); scroll.size = Vector2(BW - 72, BH - 130)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(scroll)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 4)
	col.custom_minimum_size.x = BW - 92; scroll.add_child(col)
	var adir := String(table.get("atlas_dir", "title_ui"))
	var cur := int(UserDB.get_pmeta("title_no", 0))
	for td: Dictionary in view:
		var no := int(td["title_no"])
		var unlocked := Titles.is_unlocked(td, prog)
		var row := Control.new(); row.custom_minimum_size = Vector2(0, 46)
		# 칭호 아트(원작 title/<no>_kr.png) — 칭호 텍스트가 곧 이미지다.
		var tp := "res://assets/converted/%s/%s.tres" % [adir, String(td["frame"])]
		if ResourceLoader.exists(tp):
			var tr := TextureRect.new(); tr.texture = load(tp)
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.size = Vector2(190, 34); tr.position = Vector2(40, 6)
			tr.modulate = Color.WHITE if unlocked else Color(0.35, 0.33, 0.30)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(tr)
		# 획득 체크(원작 common/checked.png)
		if unlocked:
			var chk := "res://assets/converted/common_ui/common_checked.tres"
			if ResourceLoader.exists(chk):
				var cs := Sprite2D.new(); cs.texture = load(chk); cs.position = Vector2(20, 23)
				row.add_child(cs)
		var info := Label.new()
		info.text = String(td.get("comment", ""))
		if not unlocked:
			info.text += "   (%d%%)" % int(Titles.progress_ratio(td, prog) * 100.0)
		info.add_theme_font_size_override("font_size", 14)
		info.add_theme_color_override("font_color", Color(0.3, 0.22, 0.08) if unlocked else Color(0.5, 0.46, 0.4))
		info.position = Vector2(246, 14); info.size = Vector2(230, 20); row.add_child(info)
		if unlocked:
			var b := Button.new()
			b.text = "사용 중" if no == cur else "장착"
			b.disabled = (no == cur)
			b.size = Vector2(78, 34); b.position = Vector2(BW - 190, 6)
			var n2 := no
			b.pressed.connect(func():
				UserDB.set_pmeta("title_no", n2)
				_toast("칭호를 장착했습니다")
				overlay.queue_free(); _open_titles())
			row.add_child(b)
		col.add_child(row)

## 미션 창 = `scripts/ui/mission_layer.gd` (`class_name MissionLayer`).
## 원작에서 이 창은 **메인 화면(월드맵) 위의 독립 레이어**다(`WorldMapScene.c:13371`
## `MissionLayer::create(4)`), 그래서 2026-07-30 에 cave.gd 밖으로 뺐다. 여기 남은 것은
## `params.open == "quests"` 진입(스모크 테스트·구 경로 호환)뿐이다.
func _open_quests() -> void:
	var m := MissionLayer.open(self, 0, "cave", {})
	m.changed.connect(_refresh)

## 원작 출전 파티 선택(Select3DragonsLayer/setAddDragonPopupLayer): 보유 드래곤 그리드에서 최대 3마리 선택.
## 선택 순서=출전 슬롯. 비면 전투가 활성+보유순 폴백. UserDB.party 영속.
## 출전 파티 선택 — 원작 Select3DragonsLayer. 원작은 **던전 입장 시** 고르므로 공용
## 컴포넌트(scripts/ui/party_select.gd)로 분리했다. 둥지에서는 더 이상 진입점이 없다.
func _open_party() -> void:
	PartySelect.open(self)

## 원작 레벨업 화면 — **전체화면 오버레이**(팝업 아님). 랜덤롤 §K-1.
## 참조: docs/ref/orig_image/levelup/Screenshot_2016-06-23-12-18-13.png(배치) ·
##       docs/ref/orig_image/levelup/Screenshot_2017-02-27-11-12-03-1.png(리롤 블록: 회전화살표+"능력치 다시뽑기"+💎x2)
##
## ⚠️ 소유 클래스 미특정(2026-07-27). libgame.so 심볼 1,181개를 훑었으나 이 화면을 만드는 클래스가
##    디컴파일된 397개 안에 없다 — StatusLayer=먹이/치료/피로, ResetLayer=젬·스킬 리셋,
##    DragonEnchantResultLayer=마석 인챈트(MasicStoneGaugeText + dragon_enchant.spine_json)로 전부 다르다.
##    CLAUDE.md §3 "자산 이름으로 담당 클래스를 추측하는 것 금지"에 따라 **클래스를 지목하지 않는다.**
##    ⇒ 배치 근거 = 참조 스크린샷의 비율(ASSUMPTION, 원작 좌표 리터럴 아님)
##      자산 근거 = asset_index.py 조회(아래 프레임은 전부 원본 — 자작 도형 없음)
##
## 사용 원본 프레임: common/backlight3 · common/item_box · common/lock · common/refresh ·
##   common/refresh_bg1 · common/bt_levelupauto_off|on · common/diamond_small1 · common/check_btn ·
##   common/btn_arrow2 · scene/cave/enchant_bar_bg2 · scene/cave/enchant_bar2 · scene/cave/gear ·
##   scene/cave/gear_inside · scene/cave/gear_shadow · item/item_small/{level_up,level_down,bless_of_*}
##
## 문자열은 원작 stringsData_KR.xml 그대로:
##   DragonReset "능력치 다시뽑기" · DragonResetMax1+2 "(MAX 확률 %s%%)" ·
##   DragonResetConfirm "다이아를 소모하여 능력치를 다시 뽑으시겠습니까?" · DragonResetAuto "다시뽑기 자동"
const _LVUP_GUARANTEE := {
	"bless_of_dragon": "max1", "bless_of_maia": "max2",
	"bless_of_dersa": "triple", "bless_of_amor": "amor",
}
const _STAT_KR := {"hp": "생명력", "att": "공격력", "def": "방어력"}
## 아이템 슬롯 순서. 원작 참조 스크린샷엔 슬롯이 2칸뿐이지만 우리 레벨 아이템은 6종이라
## **보유한 종류를 모두** 노출하고 빈 칸만 lock 으로 채운다(ASSUMPTION: 슬롯 해금 규칙은 유실).
const _LVUP_ITEMS := ["level_up", "bless_of_dragon", "bless_of_maia", "bless_of_dersa",
	"bless_of_amor", "level_down"]
const _LVUP_MIN_SLOTS := 2
# (종전 _LVUP_AUTO_DELAY 는 폐기 — 자동 다시뽑기는 이제 연출 완료를 기다린다. 원작 timeScale 2.0 = sp 0.5)
## UI 레이어 z. 드래곤 스파인은 슬롯마다 z_index 를 갖고 있어 기본 0 이면 UI 를 덮는다.
const _LVUP_UI_Z := 40

## 레벨업 화면 상태(한 번에 하나만 열린다).
## 🔴 2026-07-27 회귀방지: 예전엔 `var redraw: Callable` 자기참조 람다로 갱신했다. GDScript 람다는
##    **생성 시점의 값**을 캡처하므로 바깥 람다가 캡처한 `redraw` 는 대입 전의 *빈 Callable* 이었고,
##    리롤·Lv±1·축복을 눌러도 화면이 전혀 갱신되지 않았다(골드와 gain_log 는 실제로 바뀌는데 표시만 그대로
##    → "버튼이 안 먹는다"로 보였다). 재현: `shot_helper --shot=lvreroll`.
##    **다시 람다로 되돌리지 말 것** — 갱신은 메서드(`_lvup_redraw`)로 둔다.
var _lvup_ctx: Dictionary = {}
## 레벨업 화면 좌측 드래곤의 holder — 진화(성장 단계 변경) 때 통째로 다시 세운다.
var _lvup_dragon_holder: Node2D
## 레벨업 연출(원작 ExpLayer 안무) 재생 중 플래그 — 재생 중 입력 차단·자동 루프 대기.
var _lvup_fx_busy := false

## 원작 BMFont 로더(레벨업 화면용). `fixed_size` 가 박혀 있어 기본값으로는 font_size 를 무시
## → `fixed_size_scale_mode = ENABLED` 복제본을 캐시(main_hud.gd 와 같은 패턴).
## 폰트 근거 = ExpLayer 디컴프(docs/ref/porting/LevelUpScreen.md "원작 폰트" 표):
##   스탯/값/롤/(+n/m)/MAX 뱃지/추가슬롯 = font_subtitle · EXP 카운터 = font_common ·
##   등급 = font_rating · 트리플맥스 = font_title(cutin.gd).
var _lvup_bmfonts := {}
func _lvup_bmfont(name: String) -> FontFile:
	if _lvup_bmfonts.has(name):
		return _lvup_bmfonts[name]
	var p := "res://assets/converted/font_ui/%s.fnt" % name
	if not ResourceLoader.exists(p):
		return null
	var f: FontFile = load(p).duplicate()
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	# 원작 비트맵은 한글 1271자 부분집합이라 "샛"·"팬" 같은 글자가 빠져 있다(원작 문자열에 안 쓰인
	# 조합) → 도감의 드래곤 이름이 깨짐(사용자 보고 2026-07-30). 없는 글리프만 시스템 한글 폰트로
	# 폴백해 그린다(있는 글자는 계속 원작 비트맵).
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Gulim"])
	f.fallbacks = [fb]
	_lvup_bmfonts[name] = f
	return f

## 원작 BMFont 라벨 서식. 비트맵 자체에 외곽선이 구워져 있어 outline 오버라이드는 걸지 않는다.
func _lvup_bm_style(l: Label, size: int, col: Color, font := "font_subtitle") -> void:
	var f := _lvup_bmfont(font)
	if f:
		l.add_theme_font_override("font", f)
	else:
		# 폰트 미보유 폴백 — TTF + 외곽선(종전 서식)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 5 if size >= 24 else 4)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _open_levelup() -> void:
	var a := _active()
	if a.is_empty(): return
	var uid := int(a["uid"])
	var ddef: Dictionary = Data.get_dragon(int(a["id"]))
	var vis := _vis()
	# 레이어를 둘로 나눈다 — 드래곤 **스파인은 슬롯마다 z_index 를 갖고** 있어서 같은 레이어에 두면
	# z_index 를 아무리 올려도 UI 를 덮는 경우가 생긴다. CanvasLayer 순서는 z_index 를 항상 이긴다.
	var overlay := CanvasLayer.new(); overlay.layer = 30; add_child(overlay)   # 딤 + 드래곤
	var uilay := CanvasLayer.new(); uilay.layer = 31; add_child(uilay)         # 그 위의 모든 UI
	# 원작도 뒤 동굴이 어둡게 깔린다(참조: 좌측 드래곤 슬롯 스트립이 어둡게 비침).
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.45); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var win := Control.new()
	win.size = vis
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	uilay.add_child(win)

	# ── 좌측: 드래곤(스파인) — 딤 위에 밝게 선다. 원작 참조에서 화면 좌측 1/5 지점.
	# 동굴 본체의 받침대(_stage)는 숨긴다 — 안 그러면 가운데 드래곤과 좌측 드래곤이 **둘 다** 보인다.
	# 복구는 오버레이가 트리에서 빠질 때 무조건 걸어 둔다(✔ 말고 다른 경로로 닫혀도 동굴이 안 비게).
	# ⚠️ 이 처리는 `_lvup_build_dragon` 이 아니라 **여기**에 있어야 한다 — 진화 때 좌측 드래곤만
	#    다시 세우므로(_lvup_refresh_dragon) 빌더는 화면당 여러 번 불린다.
	if is_instance_valid(_stage): _stage.visible = false
	overlay.tree_exited.connect(func():
		if is_instance_valid(_stage): _stage.visible = true)
	var dragon_ap := _lvup_build_dragon(overlay, a, vis)

	# ── LEVEL UP 아트(좌상단)
	# ⚠️ `assets/converted/lvup_ui/level_up.png` 는 추출 아틀라스에 없는 자작본이다(CLAUDE.md §10 표 참조).
	#    원본 워드아트를 확보하면 여기만 교체하면 된다.
	var lup := TextureRect.new()
	lup.texture = load("res://assets/converted/lvup_ui/level_up.png")
	lup.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lup.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lup.size = Vector2(vis.x * 0.30, vis.y * 0.20)
	lup.position = Vector2(vis.x * 0.03, vis.y * 0.03)
	lup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lup.z_index = _LVUP_UI_Z        # 드래곤 스파인(슬롯별 z_index)이 UI 를 덮지 않게
	win.add_child(lup)

	# ── 하단 전폭 텍스트박스(원작 BattleTextBox 사양)
	# 프레임 자체가 반투명이라 동굴 하단 메뉴(아이템/젬/스킬)가 비친다 → 뒤에 불투명 판을 깐다.
	# 원작 참조에서도 이 박스는 불투명하다.
	var tback := ColorRect.new()
	tback.color = Color(0.05, 0.04, 0.03, 1.0)
	tback.size = Vector2(vis.x, 120.0)
	tback.position = Vector2(0.0, vis.y - 120.0)
	tback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tback.z_index = _LVUP_UI_Z
	win.add_child(tback)
	var tbox := NinePatchRect.new()
	tbox.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres")
	tbox.patch_margin_left = 10; tbox.patch_margin_right = 10
	tbox.patch_margin_top = 4; tbox.patch_margin_bottom = 4
	tbox.size = Vector2(vis.x - 10.0, 120.0)
	tbox.position = Vector2(5.0, vis.y - 120.0)
	tbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tbox.z_index = _LVUP_UI_Z
	win.add_child(tbox)
	var tlabel := Label.new()
	tlabel.add_theme_font_size_override("font_size", 28)
	tlabel.add_theme_color_override("font_color", Color.WHITE)
	tlabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tlabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tlabel.size = Vector2(tbox.size.x - 20.0, 112.0); tlabel.position = Vector2(10.0, 4.0)
	tbox.add_child(tlabel)

	# ── 우상단 빨간 ✔ — 원작 `common/check_btn`(닫기 X 가 아니라 확인 체크다).
	var okb := TextureButton.new()
	var okt := "res://assets/converted/common_ui/common_check_btn.tres"
	if ResourceLoader.exists(okt):
		okb.texture_normal = load(okt)
		okb.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
		okb.position = Vector2(vis.x - 30.0 - 44.0 * Design.ASSET_SCALE, 20.0)
	else:
		okb.position = Vector2(vis.x - 60.0, 20.0)
	okb.pressed.connect(func():
		Bgm.sfx("effect_button")
		_lvup_ctx = {}
		_lvup_dragon_holder = null
		if is_instance_valid(_stage): _stage.visible = true   # 숨겼던 동굴 받침대 복구
		if is_instance_valid(overlay): overlay.queue_free()
		if is_instance_valid(uilay): uilay.queue_free())
	uilay.add_child(okb)

	var body := Control.new()
	body.size = vis
	body.position = Vector2.ZERO
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 배경이 클릭을 먹지 않게(자식 버튼만 받는다)
	body.z_index = _LVUP_UI_Z
	win.add_child(body)

	_lvup_ctx = {"uid": uid, "ddef": ddef, "vis": vis, "body": body, "tlabel": tlabel,
		"overlay": overlay, "reroll": 0, "art": lup, "win": win, "dragon_ap": dragon_ap}
	_lvup_redraw()

## 상단 워드아트를 잠시 다른 문구로 바꾼다 — 리롤 = "LEVEL RESET"(참조 스크린샷).
## ⚠️ RESET/DOWN 워드아트는 추출 에셋에 없다(CLAUDE.md §10) → **TTF 문구**로 낸다.
##    LEVEL UP 아트조차 스크린샷에서 잘라낸 자작본이라, 원본 확보 시 둘 다 여기서 교체한다.
func _lvup_word_banner(text: String, secs := 1.6, col := Color(0.72, 0.94, 1.0),
		outline := Color(0.06, 0.24, 0.42, 1.0)) -> void:
	if _lvup_ctx.is_empty(): return
	var win: Control = _lvup_ctx.get("win")
	var art: TextureRect = _lvup_ctx.get("art")
	if not is_instance_valid(win) or not is_instance_valid(art): return
	if is_instance_valid(_lvup_ctx.get("word")):
		(_lvup_ctx["word"] as Node).queue_free()
	art.visible = false
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 52)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size = art.size
	l.position = art.position
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(0.7, 0.7)
	l.z_index = _LVUP_UI_Z
	win.add_child(l)
	_lvup_ctx["word"] = l
	var t := l.create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(secs)
	t.tween_callback(func():
		if is_instance_valid(art): art.visible = true
		if is_instance_valid(l): l.queue_free())

## 좌측 드래곤 — 원작 참조에선 딤 위에 드래곤이 밝게 서 있고 뒤에서 후광이 돈다.
## 동굴 받침대의 드래곤은 딤 아래로 어두워지므로 오버레이에 같은 스파인 씬을 한 번 더 세운다.
## 후광 = `common/backlight3` + 6초 1회전(원작 DragonEnchantResultLayer.c:640 `CCRotateBy::create(6.0, 360.0)`
##   — 다른 화면이지만 같은 프레임을 쓰는 원작 회전 파라미터라 그대로 따른다).
## (딤/받침대 숨김은 `_open_levelup` 담당 — 이 함수는 진화 때 다시 불린다.)
func _lvup_build_dragon(parent: Node, a: Dictionary, vis: Vector2) -> AnimationPlayer:
	# 내부는 동굴과 같은 1080 공간을 그대로 쓴다(받침대/드래곤 좌표를 재계산하지 않게).
	var holder := Node2D.new()
	_lvup_dragon_holder = holder   # 진화 시 통째로 갈아끼우기 위해 보관
	holder.scale = Vector2(S1080, S1080)
	# 동굴 받침대(_stage)는 `vis.y/2 - 8` 인데, 여기선 **love 모션이 크게 일어서서** 머리가
	# 화면 위로 잘린다 → 그만큼 아래로 내린다(받침대는 하단 텍스트박스 위에 그대로 들어간다).
	holder.position = Vector2(vis.x * 0.22, vis.y / 2.0 + 34.0)
	parent.add_child(holder)
	var bl := _atlas_sprite("common_ui", "common_backlight3", _man_common(), 1.35)
	if bl and bl.texture:
		bl.position = Vector2(0, 40)
		bl.modulate = Color(1, 1, 1, 0.5)
		holder.add_child(bl)
		bl.create_tween().set_loops().tween_property(bl, "rotation", TAU, 6.0).from(0.0)
	# 받침대 = 동굴과 같은 stand 스킨/정규화 규칙(_refresh_dragon 과 동일).
	var si: int = UserDB.get_skin("stand_skin") % STAND_COUNT
	var info = _stand_manifest.get("stand_stand%d" % (si + 1), {})
	var pw: float = maxf(1.0, float(info.get("w", 305)))
	var ph: float = maxf(1.0, float(info.get("h", 120)))
	var psc := 620.0 / pw
	var ped := _atlas_sprite("stand_ui", "stand_stand%d" % (si + 1), _stand_manifest, psc)
	if ped:
		ped.position = Vector2(0, 357.0 - ph * psc / 2.0)
		holder.add_child(ped)
	var stage_name := Growth.stage_for_level(int(a["level"]))
	var path := DRAGON_SCENE % [int(a["id"]), stage_name]
	if ResourceLoader.exists(path):
		var d2 := Node2D.new()
		d2.scale = Vector2(1.9, 1.9)      # 동굴 받침대와 동일(1080 공간 기준)
		d2.position = Vector2(0, -7)
		holder.add_child(d2)
		var inst = load(path).instantiate()
		d2.add_child(inst)
		# 원작은 **대기(wait)가 아니라 상호작용(love) 모션**을 반복한다(사용자 확인 2026-07-27) —
		# 동굴에서 드래곤을 눌렀을 때와 같은 모션이다(CaveScene::onClickDragon 이 "love" 재생).
		# 보이스도 함께 반복한다(원작 `Dragon::getDragonVoiceDelay` 만큼 늦춰 재생).
		# ⚠️ Animation 리소스는 동굴 받침대 인스턴스와 **공유**될 수 있다 → `loop_mode` 를 건드리면
		#    동굴 쪽 love 까지 무한루프가 된다. 리소스를 고치지 말고 끝날 때마다 다시 재생한다.
		var dap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		if dap:
			if dap.has_animation("love"):
				dap.animation_finished.connect(_lvup_loop_love.bind(dap))
				_lvup_play_love(dap)
			elif dap.has_animation("wait"):
				dap.play("wait")
			return dap
	else:
		# 스파인 미빌드 종은 초상 폴백(동굴 받침대와 같은 규칙 — 어떤 드래곤도 안 보이지 않게).
		var por := _portrait_sprite(int(a["id"]), stage_name, 2.6, int(a.get("skin", 0)))
		if por:
			por.position = Vector2(0, -30)
			holder.add_child(por)
	return null

## 진화(성장 단계 변경)로 다른 스파인을 세워야 할 때 좌측 드래곤만 갈아끼운다.
## 🔴 2026-07-28 회귀방지: 예전엔 레벨업 화면이 열릴 때 세운 스파인을 그대로 뒀다 →
##    레벨 10/20 을 넘겨도 해치 모습 그대로였고, **동굴을 나갔다 들어와야**(=_refresh) 바뀌었다.
func _lvup_refresh_dragon() -> void:
	if _lvup_ctx.is_empty(): return
	var overlay = _lvup_ctx.get("overlay")
	if not is_instance_valid(overlay): return
	var d := UserDB.get_dragon(int(_lvup_ctx["uid"]))
	if d.is_empty(): return
	if is_instance_valid(_lvup_dragon_holder):
		# remove_child 를 함께 해야 같은 프레임에 옛 드래곤이 남아 겹치지 않는다(queue_free 는 프레임 끝).
		var old := _lvup_dragon_holder
		if old.get_parent(): old.get_parent().remove_child(old)
		old.queue_free()
	_lvup_dragon_holder = null
	_lvup_ctx["dragon_ap"] = _lvup_build_dragon(overlay, d, _lvup_ctx["vis"])

## 레벨업 화면의 드래곤 상호작용 모션 — love 를 **보이스와 함께 반복**한다.
## 원작: `CaveScene::onClickDragon` 이 love 재생 + `Dragon::getDragonVoiceDelay` 만큼 늦춰 보이스.
func _lvup_play_love(dap: AnimationPlayer) -> void:
	if not is_instance_valid(dap): return
	dap.play("love")
	_lvup_dragon_voice()

## love 1회가 끝나면 다시 재생(리소스 loop_mode 를 건드리지 않는 반복 방식).
func _lvup_loop_love(anim: StringName, dap: AnimationPlayer) -> void:
	if _lvup_ctx.is_empty() or not is_instance_valid(dap): return
	if anim != &"love": return
	_lvup_play_love(dap)

## 드래곤 보이스 — 성장 단계(baby/child/adult)에 맞는 번호를 `data/dragon_voices.json` 에서 찾는다.
## ⚠️ 그 표는 **유실 데이터의 재구성**이다(원작 `info_dragon_v2` 의 voice 컬럼, Dragon.c:13478-13526).
##    성체는 사용자 앵커 2개(라 솔라=voice4 · 루시퍼=voice2)로 맞춘 블록 순차,
##    해치/해츨링은 시드 난수 = **추후 수정 대상**. 규칙은 `scripts/tools/build_dragon_voices.py` 참조.
func _dragon_voice_no(dragon_id: int, level: int) -> int:
	var tbl: Dictionary = Data.dragon_voices.get("voices", {})
	var e: Dictionary = tbl.get(str(dragon_id), {})
	if e.is_empty():
		return 0
	return int(e.get(Growth.stage_for_level(level), 0))

func _play_dragon_voice(dragon_id: int, level: int) -> void:
	var n := _dragon_voice_no(dragon_id, level)
	if n > 0:
		Bgm.sfx("voice%d" % n)

func _lvup_dragon_voice() -> void:
	if _lvup_ctx.is_empty(): return
	var ddef: Dictionary = _lvup_ctx.get("ddef", {})
	var d := UserDB.get_dragon(int(_lvup_ctx["uid"]))
	_play_dragon_voice(int(ddef.get("id", 0)), int(d.get("level", 1)))

## 아틀라스 프레임을 지정 크기로 늘려 그리는 TextureRect(게이지처럼 가로로 늘리는 프레임용).
func _lvup_stretch(name: String, dir: String, size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if ResourceLoader.exists(p): t.texture = load(p)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.material = _pma
	t.size = size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

## 리롤 비용(원작 관찰: 다이아 x2). data 노브 = level_curve.json roll.reroll_cost.
func _lvup_reroll_cost() -> Dictionary:
	var rc: Dictionary = (Data.level_curve.get("roll", {}) as Dictionary).get("reroll_cost", {})
	return {"kind": String(rc.get("kind", "diamond")), "amount": int(rc.get("amount", 2))}

## 화면 갱신(레벨/스탯/아이템/리롤 확률). 람다가 아니라 **메서드**다 — 위 _lvup_ctx 주석 참조.
## fx 를 주면(레벨업/리롤 직후) 우측 열(▶·새 값·(+n/m)·MAX 뱃지)을 숨긴 채 그려 두고
## `_lvup_fx_timeline` 이 원작 ExpLayer 안무로 순차 공개한다(docs/ref/porting/LevelUpScreen.md).
func _lvup_redraw(fx: Dictionary = {}) -> void:
	if _lvup_ctx.is_empty(): return
	var body: Control = _lvup_ctx.get("body")
	var tlabel: Label = _lvup_ctx.get("tlabel")
	if not is_instance_valid(body) or not is_instance_valid(tlabel):
		_lvup_ctx = {}
		return
	# remove_child 를 함께 해야 같은 프레임에 옛 노드가 남아 겹치지 않는다(queue_free 는 프레임 끝에 처리).
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()

	var uid := int(_lvup_ctx["uid"])
	var ddef: Dictionary = _lvup_ctx["ddef"]
	var vis: Vector2 = _lvup_ctx["vis"]
	var d := UserDB.get_dragon(uid)
	if d.is_empty(): return
	var level := int(d.get("level", 1))
	var awakened := bool(d.get("awakened", false))
	var cap := Growth.level_cap(awakened)
	var max_stats := Growth.tier_growth(ddef, Data.stat_table)
	var gain_log: Array = d.get("gain_log", [])
	var roll_cfg: Dictionary = Data.level_curve.get("roll", {})
	var COL_X := vis.x * 0.45      # 우측 스탯 열 시작(참조 405/900 = 0.45)

	# ── 헤더: 이름 + 등급(원작 "말근달님은혜♡    7.1")
	var nick := String(d.get("nickname", ""))
	if nick == "": nick = String(d.get("nick", ""))
	var t := Label.new()
	t.text = nick if nick != "" else String(ddef.get("name", "드래곤"))
	_lvup_style(t, 26, Color.WHITE)
	t.position = Vector2(COL_X, vis.y * 0.13); body.add_child(t)
	var gr := Label.new()
	gr.text = "%.1f" % _grade_of(d, ddef)      # 🔴 레벨업 롤(gain_log) 포함 — §K-10
	# 등급 숫자 = 원작 `font/font_rating.fnt`(ExpLayer::setExpStart, 22pt 숫자 전용)
	_lvup_bm_style(gr, 30, Color(1.0, 0.62, 0.12), "font_rating")
	gr.position = Vector2(COL_X + 250, vis.y * 0.13); body.add_child(gr)

	# ── EXP 게이지 — 원작 EXP 게이지 3종 세트 `common/bar_bg2` + `common/bar_exp` + `common/bar_cover`.
	#    근거: EvolLayer.c:1232/1251/1277 이 세 프레임을 그대로 겹쳐 쓴다(DragonAwaken·LaboratoryScene 도 bg2+exp).
	#    (예전엔 9patch/bar1+bar_bg1 자작 조합이었다. `scene/cave/enchant_bar2` 는 마석 인챈트 게이지라 다른 것)
	var ey := vis.y * 0.21
	var expw := _atlas_sprite("adventure_ui", "scene_adventure_bonus_exp_mini",
		_man_adventure(), 0.8 * Design.ASSET_SCALE)
	if expw: expw.position = Vector2(COL_X + 26, ey + 12); body.add_child(expw)
	var bar_size := Vector2(300.0, 18.0)
	var bar_pos := Vector2(COL_X + 60, ey + 3)
	var ebg := _lvup_stretch("common_bar_bg2", "common_ui", bar_size)
	ebg.position = bar_pos; body.add_child(ebg)
	var need := LevelSystem.exp_to_next(Data.level_curve, level)
	var cur := int(d.get("exp", 0))
	var pct := clampf(float(cur) / maxf(1.0, float(need)), 0.0, 1.0)
	var clip := Control.new()                       # 채움은 클리핑으로(프레임을 늘리지 않고 그대로 쓰기 위해)
	clip.position = bar_pos
	clip.size = Vector2(bar_size.x * pct, bar_size.y)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(clip)
	var efill := _lvup_stretch("common_bar_exp", "common_ui", bar_size)
	clip.add_child(efill)
	var ecov := _lvup_stretch("common_bar_cover", "common_ui", bar_size)   # 광택 오버레이
	ecov.position = bar_pos; body.add_child(ecov)
	var etx := Label.new()
	etx.text = "%d / %d" % [cur, need]
	# EXP 카운터 = 원작 font_common(ExpLayer::setExpGageUpShow → NumberingNoneActLabel)
	_lvup_bm_style(etx, 18, Color.WHITE, "font_common")
	etx.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	etx.size = bar_size; etx.position = bar_pos
	body.add_child(etx)

	# ── 스탯표: `이름  before ▶ after (+d/m)` — 원작 형식 그대로.
	# 실 스탯 = base + 영구base보정 + Σgain_log (Growth.main_stats). 🔴 예전엔 결정론 compute_stats 를
	# 썼는데 그건 gain_log 를 안 봐서 **리롤해도 좌우 수치가 안 바뀌었다**(캐릭터 시트와도 불일치).
	var sb2: Dictionary = d.get("stat_bonus", {})
	var base_bonus: Dictionary = sb2.get("base", {})
	var last: Dictionary = gain_log[gain_log.size() - 1] if not gain_log.is_empty() else {}
	var now_st := Growth.main_stats(ddef, Data.stat_table, gain_log, base_bonus)
	var prev_log := gain_log.slice(0, maxi(0, gain_log.size() - 1))
	var prev_st := Growth.main_stats(ddef, Data.stat_table, prev_log, base_bonus)
	var prev_lv := maxi(1, level - 1)
	var rows := [["레벨", Color(1.0, 0.83, 0.25), str(prev_lv), str(level), "", false, false]]
	var maxed_n := 0
	for spec in [["hp", "생명력", Color(0.55, 1.0, 0.55)], ["att", "공격력", Color(1.0, 0.5, 0.45)],
			["def", "방어력", Color(0.5, 0.75, 1.0)]]:
		var k: String = spec[0]
		var mx := int(max_stats.get(k, 1))
		var gain := int(last.get(k, int(now_st[k]) - int(prev_st[k])))
		var trans := gain > mx
		var maxed := gain >= mx
		if maxed: maxed_n += 1
		rows.append([String(spec[1]), spec[2], str(int(prev_st[k])), str(int(now_st[k])),
			"(+%d/%d)" % [gain, mx], maxed, trans])
	var yy := vis.y * 0.29
	# MAX 배지는 **최대치에 도달한 그 스탯 줄**에 붙인다(사용자 지적 2026-07-27).
	# 예전엔 배지를 위에서부터 순서대로 쌓아서, 공격이 미달인데 두 번째 배지가 공격 줄에 떠 헷갈렸다.
	# 서체 = 원작 font_subtitle(ExpLayer 전반), MAX 뱃지 글자 = 흰색·초월만 #EE33FF(ExplayerMaxBonus).
	var fx_on := not fx.is_empty()
	var fx_rows: Array = []
	var badge_no := 0
	for i in rows.size():
		var ry := yy + i * 44.0
		var nm2 := Label.new(); nm2.text = String(rows[i][0])
		_lvup_bm_style(nm2, 26, rows[i][1])
		nm2.position = Vector2(COL_X, ry); body.add_child(nm2)
		var bv := Label.new(); bv.text = String(rows[i][2])
		_lvup_bm_style(bv, 26, Color.WHITE)
		bv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		bv.size = Vector2(96, 32); bv.position = Vector2(COL_X + 100, ry); body.add_child(bv)
		var ar := _atlas_sprite("common_ui", "common_btn_arrow2", _man_common(), 0.75)   # ▶
		if ar: ar.position = Vector2(COL_X + 224, ry + 16); body.add_child(ar)
		var av := Label.new(); av.text = String(rows[i][3])
		_lvup_bm_style(av, 26, Color.WHITE)
		av.position = Vector2(COL_X + 252, ry); body.add_child(av)
		av.pivot_offset = Vector2(0.0, 20.0)    # 롤 확정 팝의 축 = 왼쪽 세로중앙(원작 anchor(0,0.5))
		var dl: Label = null
		if String(rows[i][4]) != "":
			dl = Label.new(); dl.text = String(rows[i][4])
			# 원작 ExplayerValuesUp 계열: 기본 흰색, 초월(Bonus)만 #EE33FF
			_lvup_bm_style(dl, 20, Color("EE33FF") if bool(rows[i][6]) else Color.WHITE)
			dl.position = Vector2(COL_X + 340, ry + 5); body.add_child(dl)
			dl.pivot_offset = Vector2(0.0, 15.0)
		# ── MAX 배지 — 원작 `common/max_bg` + `%dMAX(+)`(ExpLayer::setFullStatus).
		#    맥스를 찍은 **그 스탯 줄**에 붙고, 번호는 찍은 순서(1MAX/2MAX/3MAX). 초월이면 `+`.
		#    스프라이트+라벨을 Node2D 로 묶는다 — 연출(중앙 10배 → 줄로 비행)이 통째로 움직이게.
		var bd: Node2D = null
		if bool(rows[i][5]):
			badge_no += 1
			bd = Node2D.new()
			bd.position = Vector2(COL_X + 470.0, ry + 16.0)
			body.add_child(bd)
			var gbg := _atlas_sprite("common_ui", "common_max_bg", _man_common(), Design.ASSET_SCALE * 0.8)
			if gbg: bd.add_child(gbg)
			var mb := Label.new()
			mb.text = "%dMAX%s" % [badge_no, "+" if bool(rows[i][6]) else ""]
			_lvup_bm_style(mb, 17, Color("EE33FF") if bool(rows[i][6]) else Color.WHITE)
			mb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			mb.size = Vector2(110, 28); mb.position = Vector2(-55, -14)
			bd.add_child(mb)
		if fx_on:
			# 우측 열은 숨긴 채 시작 — 타임라인이 원작 순서(레벨→0.4s→생명→공격→방어)로 공개
			if ar: ar.modulate.a = 0.0
			av.modulate.a = 0.0
			if dl: dl.modulate.a = 0.0
			if bd: bd.visible = false
			fx_rows.append({"is_level": i == 0, "arrow": ar, "av": av,
				"final": String(rows[i][3]), "dl": dl, "maxed": bool(rows[i][5]),
				"trans": bool(rows[i][6]), "badge": bd,
				"badge_pos": Vector2(COL_X + 470.0, ry + 16.0), "ry": ry})

	# ── 스탯표 아래 아이템 슬롯(원작: 아이콘 슬롯 + 잠긴 칸은 자물쇠)
	var can_up := level < cap
	var slot_y := vis.y * 0.575
	var slots := 0
	for key in _LVUP_ITEMS:
		if UserDB.item_count(key) <= 0:
			continue
		_lvup_item_slot(body, key, Vector2(COL_X + 6 + slots * 86.0, slot_y), can_up, level)
		slots += 1
	for i in maxi(0, _LVUP_MIN_SLOTS - slots):
		_lvup_locked_slot(body, Vector2(COL_X + 6 + (slots + i) * 86.0, slot_y))

	# ── 하단 안내 문장
	if gain_log.is_empty():
		tlabel.text = "레벨업 이력이 없습니다.  레벨 아이템으로 레벨을 올리세요."
	else:
		var dn2 := String(ddef.get("name", "드래곤"))
		tlabel.text = "%s%s 레벨 %d%s 되었습니다.  (MAX %d)" % [dn2,
			_josa_c(dn2, "은", "는"), level, _josa_c(str(level), "이", "가"), maxed_n]

	# ── 우하단: AUTO + 능력치 다시뽑기(원작 참조 11-12-03-1)
	_lvup_build_reroll(body, vis, roll_cfg, gain_log.is_empty())

	# ── 연출 모드면 타임라인 시작(원작 ExpLayer 안무 — 포팅 카드 "연출 안무" 절)
	if fx_on:
		fx["rows"] = fx_rows
		_lvup_fx_timeline(fx)

## 라벨 공통 서식(원작처럼 굵은 외곽선). 원작 BMFont 는 숫자 전용이라 한글은 TTF(CLAUDE.md §10).
func _lvup_style(l: Label, size: int, col: Color, outline := Color(0, 0, 0, 0.9)) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", 5 if size >= 24 else 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE

# ═════════ 레벨업 연출 타임라인 — 원작 ExpLayer 안무 이식 ═════════
# 근거: docs/ref/porting/LevelUpScreen.md "연출 안무"(ExpLayer.c 디컴프 리터럴, 2026-07-29).
# 대조 영상: docs/ref/LVupEffect/1~22.png(트리플맥스 1회). 시간·배율은 원작 값 그대로,
# sp = 시간 배율(자동 다시뽑기 = 0.5 — 원작은 CCDirector timeScale 2.0).

func _lvt(secs: float) -> void:
	await get_tree().create_timer(maxf(0.01, secs)).timeout

func _lvup_fx_timeline(fx: Dictionary) -> void:
	_lvup_fx_busy = true
	var sp := float(fx.get("sp", 1.0))
	var win: Control = _lvup_ctx.get("win")
	var vis: Vector2 = _lvup_ctx["vis"]
	# 원작도 연출 중 터치를 막는다(ExpLayer 는 TouchController 로 전체 차단).
	# ✔ 닫기 버튼은 win 이 아니라 uilay 소속이라 차단막도 uilay(맨 위)에 얹는다.
	var blocker := Control.new()
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.z_index = _LVUP_UI_Z + 20
	if is_instance_valid(win) and win.get_parent() != null:
		win.get_parent().add_child(blocker)
	fx["blocker"] = blocker
	fx["maxn"] = 0
	match String(fx.get("kind", "up")):
		"up":
			# 사운드는 워드아트 등장과 동시(setExpOrLevelUpValueLabel)
			Bgm.sfx("effect_level_updown")
			await _lvup_wordart_flight(sp)
		"reset":
			# 원작 effect_reset_spine "reset" 워드아트 — 스파인 미보유 → TTF 배너(CLAUDE.md §10)
			Bgm.sfx("effect_level_updown")
			_lvup_word_banner("LEVEL RESET", 1.4)
			await _lvt(0.6 * sp)
		_:
			await _lvt(0.1 * sp)
	if _lvup_ctx.is_empty(): return
	# 성장 단계 경계(10/25) 통과 — 원작 setLevelWithRevolution: upeffect 스파인(미보유) 대신
	# pt_rev_up 파티클 → 1.0s 후 드래곤 교체 → 1.0s 대기. (종전 "원작에 연출 없음" 주석은 오판)
	if bool(fx.get("stage_changed", false)):
		CocosParticle.spawn(self, "pt_rev_up", Vector2(vis.x * 0.20, vis.y * 0.55), 135, 0.6)
		await _lvt(1.0 * sp)
		if _lvup_ctx.is_empty(): return
		_lvup_refresh_dragon()
		_refresh_dragon()   # 동굴 받침대(숨김 상태)도 새 단계로
		_refresh_list()
		await _lvt(1.0 * sp)
	if _lvup_ctx.is_empty(): return
	# 행 공개(setShowStatus): 레벨 → 0.4s → 생명력 → 0.4s → 공격력 → 0.4s → 방어력
	var rows: Array = fx.get("rows", [])
	fx["pending"] = rows.size()
	for i in rows.size():
		if i > 0:
			await _lvt(0.4 * sp)
			if _lvup_ctx.is_empty(): return
		_lvup_fx_row(fx, i)
	# 행들은 병렬 코루틴 — 전부 확정(배지·컷인 포함)될 때까지 대기
	while int(fx.get("pending", 0)) > 0:
		if _lvup_ctx.is_empty(): return
		await _lvt(0.1)
	# 마지막 행 확정 +2.0s → 슬롯 개방 체크 → +0.3s → 마무리(setSkillSlotCheck/FullStatusFinish)
	await _lvt(2.0 * sp)
	if _lvup_ctx.is_empty():
		_lvup_fx_busy = false
		return
	_lvup_fx_slot_open(fx)
	await _lvt(0.3 * sp)
	# 마무리 — 재-redraw 는 하지 않는다: 연출이 남긴 상태(맥동 ▶/뱃지, 부유 워드아트)가
	# 곧 원작의 잔류 상태다(setArrowForever/setMaxForever/setFeatherForever 전부 무한 루프).
	_lvup_fx_busy = false
	var blk = fx.get("blocker")
	if is_instance_valid(blk): blk.queue_free()

## LEVEL UP 워드아트 비행 — 원작 effect_levelupdown_spine "up"(스파인 미보유 → 자작 크롭).
## 경로 = setExpOrLevelUpValueLabel 리터럴. 원작 정착 scale 0.27 = 우리 정적 크기 1.0 ⇒ ×1/0.27.
func _lvup_wordart_flight(sp: float) -> void:
	var art: TextureRect = _lvup_ctx.get("art")
	var vis: Vector2 = _lvup_ctx["vis"]
	if not is_instance_valid(art):
		await _lvt(0.5 * sp)
		return
	# 직전 비행/부유 트윈 정리(중첩 방지)
	if _lvup_ctx.get("art_tweens") is Array:
		for t in _lvup_ctx["art_tweens"]:
			if t is Tween and t.is_valid(): t.kill()
	var tws: Array = []
	_lvup_ctx["art_tweens"] = tws
	art.pivot_offset = art.size * 0.5
	var home: Vector2 = Vector2(vis.x * 0.03, vis.y * 0.03)   # _open_levelup 의 정위치
	var K := 1.0 / 0.27
	art.position = Vector2(vis.x * 0.5 - art.size.x * 0.5, vis.y + 60.0)   # 원작 y=-160(화면 밖 아래)
	art.scale = Vector2.ONE * (0.5 * K)
	var y1 := art.position.y - (vis.y / 3.0 + 200.0)
	var y2 := y1 - vis.y / 3.0
	var tw := art.create_tween()
	tws.append(tw)
	tw.tween_property(art, "position:y", y1, 0.5 * sp)              # ① 상승
	tw.parallel().tween_property(art, "scale", Vector2.ONE * (0.45 * K), 0.5 * sp)
	tw.tween_property(art, "scale", Vector2.ONE * (0.4 * K), 0.5 * sp)   # ② 숨고르기
	# ③ 정점 확대 — 원작은 이 시점 CCCallFuncN 로 FeatherLayer(깃털 12장)를 얹는다
	tw.tween_callback(func():
		if not _lvup_ctx.is_empty() and is_instance_valid(art):
			_lvup_feather_burst(art.position + art.size * 0.5))
	tw.tween_property(art, "position:y", y2, 0.5 * sp)
	tw.parallel().tween_property(art, "scale", Vector2.ONE * (0.85 * K), 0.5 * sp)
	tw.tween_property(art, "scale", Vector2.ONE * (0.7 * K), 0.25 * sp)  # ④ 수축
	tw.tween_interval(0.25 * sp)
	await tw.finished
	if not is_instance_valid(art) or _lvup_ctx.is_empty(): return
	# ⑤ 좌상단 정위치로 점프(원작 JumpTo 높이 100) + 원래 크기 → ⑥ 바운스
	var from := art.position
	var jump := func(t: float):
		if is_instance_valid(art):
			var p := from.lerp(home, t)
			p.y -= 100.0 * sin(PI * t)
			art.position = p
	var jt := art.create_tween()
	tws.append(jt)
	jt.tween_method(jump, 0.0, 1.0, 0.5 * sp)
	jt.parallel().tween_property(art, "scale", Vector2.ONE, 0.5 * sp)
	jt.tween_property(art, "position:y", home.y + 10.0, sp / 6.0)
	jt.parallel().tween_property(art, "scale", Vector2.ONE * 0.93, sp / 6.0)
	jt.tween_property(art, "position:y", home.y, sp / 6.0)
	jt.parallel().tween_property(art, "scale", Vector2.ONE, sp / 6.0)
	await jt.finished
	if not is_instance_valid(art) or _lvup_ctx.is_empty(): return
	# ⑦ 부유 루프(setFeatherForever: 1s +20px·+0.03 ↔ 1s 복귀)
	var fl := art.create_tween().set_loops()
	tws.append(fl)
	fl.tween_property(art, "position:y", home.y - 20.0, 1.0)
	fl.parallel().tween_property(art, "scale", Vector2.ONE * 1.03, 1.0)
	fl.tween_property(art, "position:y", home.y, 1.0)
	fl.parallel().tween_property(art, "scale", Vector2.ONE, 1.0)

## 깃털 버스트 — 원작 FeatherLayer::initWiget 1:1(완전 디컴프): 컬러 깃털 feather1~3 ×4 = 12장.
## 각: Spawn(MoveBy 0.25 Δ, RotateBy Δx°, ScaleTo 1.7) → Spawn(EaseExpOut(MoveBy 0.5 2Δ),
## RotateBy, ScaleTo 1.5) → FadeOut 0.5 → 제거. 파티클 = particle/scenario/pt_feature_c.
## Δ 쌍의 정확한 배정은 디컴프 지역변수 압축으로 불확실 → 계수(±20~±120)만 살린 산포.
## # ASSUMPTION: Δ 12쌍의 x·y 짝짓기(원작 FeatherLayer.c:346-375 재구성 불확실)
func _lvup_feather_burst(center: Vector2) -> void:
	if _lvup_ctx.is_empty(): return
	var win: Control = _lvup_ctx.get("win")
	if not is_instance_valid(win): return
	CocosParticle.spawn(win, "pt_feature_c", center + Vector2(0, 30), _LVUP_UI_Z + 6, 0.8)
	var offs := [Vector2(-70, -30), Vector2(-100, 20), Vector2(-120, 50), Vector2(-20, 5),
		Vector2(70, 25), Vector2(50, 100), Vector2(90, 60), Vector2(100, 20),
		Vector2(60, -25), Vector2(-50, 80), Vector2(30, -60), Vector2(110, -45)]
	var cman := _man_common()
	for i in offs.size():
		var s := _atlas_sprite("common_ui", "common_feather%d" % (1 + (i % 3)), cman, Design.ASSET_SCALE)
		if s == null: continue
		s.position = center
		s.z_index = _LVUP_UI_Z + 6
		win.add_child(s)
		var d: Vector2 = offs[i] * Design.ASSET_SCALE
		d.y = -d.y                     # cocos y-up → godot y-down
		var base: Vector2 = s.scale
		var tw := s.create_tween()
		tw.tween_property(s, "position", center + d, 0.25)
		tw.parallel().tween_property(s, "rotation_degrees", offs[i].x, 0.25)
		tw.parallel().tween_property(s, "scale", base * 1.7, 0.25)
		tw.tween_property(s, "position", center + d * 3.0, 0.5)\
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(s, "rotation_degrees", offs[i].x * 2.0, 0.5)
		tw.parallel().tween_property(s, "scale", base * 1.5, 0.5)
		tw.tween_property(s, "modulate:a", 0.0, 0.5)
		tw.tween_callback(s.queue_free)

## 행 하나의 공개+롤+확정 코루틴(fire-and-forget — 타임라인이 pending 으로 합류).
func _lvup_fx_row(fx: Dictionary, idx: int) -> void:
	var sp := float(fx.get("sp", 1.0))
	var rows: Array = fx["rows"]
	var row: Dictionary = rows[idx]
	# ▶ FadeIn 0.15 + setArrowForever(0.5s 단계 ±0.035 맥동 루프)
	var ar: Node2D = row.get("arrow")
	if is_instance_valid(ar):
		ar.create_tween().tween_property(ar, "modulate:a", 1.0, 0.15 * sp)
		var abase: Vector2 = ar.scale
		var al := ar.create_tween().set_loops()
		al.tween_property(ar, "scale", abase * 1.047, 0.5)
		al.tween_property(ar, "scale", abase, 0.5)
		al.tween_property(ar, "scale", abase * 0.953, 0.5)
		al.tween_property(ar, "scale", abase, 0.5)
	var av: Label = row.get("av")
	if not is_instance_valid(av):
		fx["pending"] = int(fx["pending"]) - 1
		return
	if bool(row.get("is_level", false)):
		# 레벨 값 팝(setUpLabelValues 0x6a): FadeIn 0.1 + ScaleTo(0.15, 2.0) → ScaleTo(0.1, 1.1)
		av.scale = Vector2.ONE * 0.5
		var lt := av.create_tween()
		lt.tween_property(av, "modulate:a", 1.0, 0.1 * sp)
		lt.parallel().tween_property(av, "scale", Vector2.ONE * 2.0, 0.15 * sp)
		lt.tween_property(av, "scale", Vector2.ONE * 1.1, 0.1 * sp)
		fx["pending"] = int(fx["pending"]) - 1
		return
	await _lvup_digit_roll(av, String(row.get("final", "")), sp)
	if _lvup_ctx.is_empty(): return
	# (+n/m) 팝(FinishNumbering: 0.15s +0.1 → 0.1s 복귀)
	var dl: Label = row.get("dl")
	if is_instance_valid(dl):
		dl.modulate.a = 1.0
		dl.scale = Vector2.ONE * 0.8
		var dt := dl.create_tween()
		dt.tween_property(dl, "scale", Vector2.ONE * 1.1, 0.15 * sp)
		dt.tween_property(dl, "scale", Vector2.ONE, 0.1 * sp)
	# 확정 반짝이 — # ASSUMPTION: 영상의 금색 별의 소유 이펙트 미특정 → pt_levelup_light 근사
	var body: Control = _lvup_ctx.get("body")
	if is_instance_valid(body):
		CocosParticle.spawn(body, "pt_levelup_light", av.position + Vector2(50, 16), 8, 0.9, 60)
	await _lvt(0.3 * sp)         # confirm 지연(원작 scheduleOnce 0.3)
	if _lvup_ctx.is_empty(): return
	if bool(row.get("maxed", false)):
		await _lvup_fx_badge(fx, row)
	fx["pending"] = int(fx["pending"]) - 1

## 슬롯머신 숫자 롤 — 원작 NumberingLabel: 자릿수별 순환(tick 0.07s), 좌→우 0.2s 간격 확정,
## 확정 팝(0.1s −0.25 → 0.2s +0.25 → 0.1s 복귀). 확정 시작 시점(0.8s)은 # ASSUMPTION
## (원작은 외부 스케줄이 ShowNumber 를 쏜다 — 영상 체감 길이에 맞춤).
func _lvup_digit_roll(av: Label, final_text: String, sp: float) -> void:
	av.modulate.a = 1.0
	var n := final_text.length()
	if n == 0: return
	var counters: Array = []
	for i in n:
		counters.append((i * 3) % 10)     # 자리마다 다른 시작값(원작 0.1s 시차의 근사)
	var t := 0.0
	var lock_start := 0.8
	while true:
		if not is_instance_valid(av) or _lvup_ctx.is_empty(): return
		var locked := 0
		if t >= lock_start:
			locked = clampi(1 + int(floor((t - lock_start) / 0.2)), 0, n)
		if locked >= n: break
		var s := ""
		for i in n:
			s += final_text[i] if i < locked else str(counters[i])
			if i >= locked:
				counters[i] = (int(counters[i]) + 1) % 10
		av.text = s
		await _lvt(0.07 * sp)
		t += 0.07
	av.text = final_text
	var tw := av.create_tween()
	tw.tween_property(av, "scale", Vector2.ONE * 0.75, 0.1 * sp)
	tw.tween_property(av, "scale", Vector2.ONE * 1.25, 0.2 * sp)
	tw.tween_property(av, "scale", Vector2.ONE, 0.1 * sp)
	await tw.finished

## MAX 뱃지 플라이인 — 원작 setFullStatus. 착지 scale 0.5 = 우리 정적 1.0 ⇒ 환산 ×2.
## 1·2MAX: 중앙 scale 10(=20) 투명 → 0.2s 비행·0.3(=0.6) 착지 → 0.2s 팝 0.5(=1.0) → 맥동.
## 3MAX: FadeIn 0.1·2.0(=4) → 0.2s 3.0(=6) → 0.5s 유지 → 비행 + 트리플맥스 연출.
func _lvup_fx_badge(fx: Dictionary, row: Dictionary) -> void:
	var sp := float(fx.get("sp", 1.0))
	var bd: Node2D = row.get("badge")
	if not is_instance_valid(bd) or _lvup_ctx.is_empty(): return
	var vis: Vector2 = _lvup_ctx["vis"]
	var n := int(fx.get("maxn", 0)) + 1
	fx["maxn"] = n
	var target: Vector2 = row["badge_pos"]
	bd.visible = true
	bd.z_index = 10
	bd.position = vis * 0.5
	bd.modulate.a = 0.0
	if n < 3:
		bd.scale = Vector2.ONE * 20.0
		var tw := bd.create_tween()
		tw.set_parallel(true)
		tw.tween_property(bd, "modulate:a", 1.0, 0.2 * sp)
		tw.tween_property(bd, "position", target, 0.2 * sp)
		tw.tween_property(bd, "scale", Vector2.ONE * 0.6, 0.2 * sp)
		await tw.finished
		if not is_instance_valid(bd): return
		_lvup_shake()          # 원작 +0.3s setShakeView — 착지 직후로 근사
		var tw2 := bd.create_tween()
		tw2.tween_property(bd, "scale", Vector2.ONE, 0.2 * sp)
		await tw2.finished
	else:
		bd.scale = Vector2.ONE * 2.0
		var tw := bd.create_tween()
		tw.tween_property(bd, "modulate:a", 1.0, 0.1 * sp)
		tw.parallel().tween_property(bd, "scale", Vector2.ONE * 4.0, 0.2 * sp)
		tw.tween_property(bd, "scale", Vector2.ONE * 6.0, 0.2 * sp)
		tw.tween_interval(0.5 * sp)
		tw.tween_property(bd, "position", target, 0.2 * sp)\
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(bd, "scale", Vector2.ONE * 0.6, 0.2 * sp)
		await tw.finished
		if not is_instance_valid(bd) or _lvup_ctx.is_empty(): return
		_lvup_fx_triple()
		_lvup_shake()
		var tw2 := bd.create_tween()
		tw2.tween_property(bd, "scale", Vector2.ONE, 0.2 * sp)
		await tw2.finished
	if not is_instance_valid(bd): return
	# setMaxForever: 0.2s +0.05(=+0.1) ↔ 0.2s 복귀, 0.3s 쉼 — 무한 맥동
	var ml := bd.create_tween().set_loops()
	ml.tween_property(bd, "scale", Vector2.ONE * 1.1, 0.2)
	ml.tween_property(bd, "scale", Vector2.ONE, 0.2)
	ml.tween_interval(0.3)

## 트리플맥스 — 원작 set3MaxParticle: 컷인(Cutin::show speed=3.0 슬로우) + 크리티컬 보이스 +
## "트리플 맥스"(font_title — cutin.gd 배너) + pt_3max1/2 아치 스윕(JumpBy 0.5s, 높이 H×0.4).
## 사운드 effect_max_fun 은 사용자 확정(2026-07-27) — 원작 뱃지 사운드명은 람다에 묻혀 미특정.
func _lvup_fx_triple() -> void:
	if _lvup_ctx.is_empty(): return
	var ddef: Dictionary = _lvup_ctx.get("ddef", {})
	var d := UserDB.get_dragon(int(_lvup_ctx["uid"]))
	Bgm.sfx("effect_max_fun")
	_lvup_dragon_voice()      # 원작은 크리티컬 보이스 — 보이스표 유실로 단계 보이스 근사
	DragonCutin.show(self, {
		"id": int(ddef.get("id", 0)),
		"element": String(ddef.get("element", "")),
		"awakened": bool(d.get("awakened", false)),
	}, 1.0 / 3.0, "트리플 맥스", 60)          # speed 1/3 = 원작 param_2 3.0 슬로우
	var vis: Vector2 = _lvup_ctx["vis"]
	var lay := CanvasLayer.new(); lay.layer = 61   # 컷인(60) 위
	add_child(lay)
	for pname in ["pt_3max1", "pt_3max2"]:
		var p := CocosParticle.spawn(lay, pname, Vector2(-60.0, vis.y * 0.5), 1, 0.3)
		if p:
			var base_y := vis.y * 0.5
			var arc := func(t: float):
				if is_instance_valid(p):
					p.position = Vector2(-60.0 + (vis.x + 120.0) * t,
						base_y - vis.y * 0.4 * sin(PI * t))
			p.create_tween().tween_method(arc, 0.0, 1.0, 0.5 * 3.0)
	get_tree().create_timer(3.5).timeout.connect(func():
		if is_instance_valid(lay): lay.queue_free())

## 화면 셰이크 — 원작 setShakeView. win 을 ±수 px 흔들고 복귀.
func _lvup_shake() -> void:
	var win: Control = _lvup_ctx.get("win")
	if not is_instance_valid(win): return
	var orig: Vector2 = win.position
	var tw := win.create_tween()
	for off in [Vector2(6, 4), Vector2(-5, -3), Vector2(4, 2), Vector2(-2, -2)]:
		tw.tween_property(win, "position", orig + off, 0.04)
	tw.tween_property(win, "position", orig, 0.04)

## Lv10/35 도달 → "추가 슬롯 개방!!"(원작 <NewSlotOpen>, setChangeNewSlot):
## 스킬 슬롯 모양 bg FadeIn 0.7 + ScaleTo(1.0, +0.1) → ScaleTo(0.3, 복귀) + 라벨 FadeIn 0.5
## + pt_take_skill. 위치는 스탯표와 아이템 슬롯 사이(# ASSUMPTION: 원작은 패널 내 슬롯 자리).
func _lvup_fx_slot_open(fx: Dictionary) -> void:
	var slot := int(fx.get("slot_new", -1))
	if slot < 0 or _lvup_ctx.is_empty(): return
	var vis: Vector2 = _lvup_ctx["vis"]
	var win: Control = _lvup_ctx.get("win")
	if not is_instance_valid(win): return
	var d := UserDB.get_dragon(int(_lvup_ctx["uid"]))
	var types: Array = d.get("skill_slots", [])
	var shape := String(types[slot]) if slot < types.size() else "star"
	var holder := Node2D.new()
	holder.position = Vector2(vis.x * 0.47, vis.y * 0.52)
	holder.z_index = _LVUP_UI_Z + 10
	win.add_child(holder)
	var bg := _atlas_sprite("common_ui", "common_skill_%s_bg" % shape, _man_common(), Design.ASSET_SCALE)
	if bg:
		bg.modulate.a = 0.0
		holder.add_child(bg)
		var bbase: Vector2 = bg.scale
		var tw := bg.create_tween()
		tw.tween_property(bg, "modulate:a", 1.0, 0.7)
		tw.parallel().tween_property(bg, "scale", bbase * 1.2, 1.0)
		tw.tween_property(bg, "scale", bbase, 0.3)
	var l := Label.new()
	l.text = "추가 슬롯 개방!!"
	_lvup_bm_style(l, 24, Color.WHITE)
	l.position = Vector2(42, -16)
	l.modulate.a = 0.0
	holder.add_child(l)
	l.create_tween().tween_property(l, "modulate:a", 1.0, 0.5)
	CocosParticle.spawn(holder, "pt_take_skill", Vector2.ZERO, 1, 0.8, 80)
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(holder): holder.queue_free())

## 레벨 아이템 슬롯 1칸 — `common/item_box` 틀 + `item/item_small/<key>` 아이콘 + 보유수 배지.
func _lvup_item_slot(body: Control, key: String, pos: Vector2, can_up: bool, level: int) -> void:
	var cman := _man_common()
	var bx := _atlas_sprite("common_ui", "common_item_box", cman, Design.ASSET_SCALE)
	if bx: bx.position = pos + Vector2(38, 38); body.add_child(bx)
	var icon := _atlas_sprite("item_small_ui", "item_item_small_%s" % key, _item_small_manifest, 0.86)
	if icon: icon.position = pos + Vector2(38, 38); body.add_child(icon)
	var cnt := UserDB.item_count(key)
	var badge := Label.new()
	badge.text = "%d" % cnt
	_lvup_style(badge, 18, Color(1, 1, 1))
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.size = Vector2(66, 22); badge.position = pos + Vector2(4, 52)
	body.add_child(badge)
	# 투명 버튼을 슬롯 위에 덮는다(원작도 슬롯 자체가 버튼).
	var b := Button.new()
	b.flat = true
	b.size = Vector2(76, 76); b.position = pos
	b.tooltip_text = "%s%s" % [Data.item_name(key),
		{"": "", "max1": " (맥스 1 보장)", "max2": " (맥스 2 보장)",
		 "triple": " (트리플맥스)", "amor": " (전 스탯 초월맥스)"}.get(String(_LVUP_GUARANTEE.get(key, "")), "")]
	var usable := (key != "level_down" and can_up) or (key == "level_down" and level > 1)
	b.disabled = not usable
	b.pressed.connect(_lvup_use_item.bind(key))
	body.add_child(b)

## 잠긴 슬롯 — 원작 `common/lock`.
func _lvup_locked_slot(body: Control, pos: Vector2) -> void:
	var bx := _atlas_sprite("common_ui", "common_item_box", _man_common(), Design.ASSET_SCALE)
	if bx:
		bx.position = pos + Vector2(38, 38); bx.modulate = Color(0.6, 0.6, 0.6, 1.0)
		body.add_child(bx)
	var lk := _atlas_sprite("common_ui", "common_lock", _man_common(), Design.ASSET_SCALE * 0.8)
	if lk: lk.position = pos + Vector2(38, 38); body.add_child(lk)

## 레벨 아이템 사용. 축복=맥스 보장 롤, Lv+1=일반 롤, Lv-1=직전 롤 무효.
## 레벨업/축복은 원작 ExpLayer 안무(_lvup_fx_timeline)를 태운다 — 사운드·컷인·진화 반영 전부
## 타임라인 소관. 레벨다운만 종전 즉시 갱신(원작 "down" 워드아트 스파인 미보유 → TTF 배너).
func _lvup_use_item(key: String) -> void:
	if _lvup_ctx.is_empty() or _lvup_fx_busy: return
	var uid := int(_lvup_ctx["uid"])
	var ddef: Dictionary = _lvup_ctx["ddef"]
	if UserDB.item_count(key) <= 0: return
	var d := UserDB.get_dragon(uid)
	var level := int(d.get("level", 1))
	var old_stage := Growth.stage_for_level(level)
	if key == "level_down":
		if level <= 1 or not UserDB.level_down(uid): return
		UserDB.add_item("level_down", -1)
		Bgm.sfx("effect_level_updown")
		_lvup_word_banner("LEVEL DOWN", 1.4, Color(0.86, 0.66, 1.0), Color(0.24, 0.05, 0.34, 1.0))
		_lvup_ctx["reroll"] = 0
		_refresh_stats()
		_lvup_redraw()
		var down_stage := Growth.stage_for_level(int(UserDB.get_dragon(uid).get("level", 1)))
		if down_stage != old_stage:
			_lvup_refresh_dragon()
			_refresh_dragon()
			_refresh_list()
		return
	if level >= Growth.level_cap(bool(d.get("awakened", false))): return
	var max_stats := Growth.tier_growth(ddef, Data.stat_table)
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var roll := LevelSystem.roll_level(Data.level_curve.get("roll", {}), max_stats, rng,
		0.0, String(_LVUP_GUARANTEE.get(key, "")))
	# level_up_with 안에서 레벨 10·25·45 자동 습득(sync_skill_grants)이 함께 돈다 → 증분을 알린다.
	var sk_before := UserDB.dragon_skills(uid).size()
	UserDB.level_up_with(uid, roll)
	var sk_new := _skills_learned_since(uid, sk_before)
	if not sk_new.is_empty():
		_toast("새 스킬 습득 — %s" % ", ".join(sk_new))
	UserDB.add_item(key, -1)
	_lvup_ctx["reroll"] = 0        # 새 레벨 → 리롤 천장 리셋
	var new_level := int(UserDB.get_dragon(uid).get("level", 1))
	# Lv10/35 스킬 슬롯 해금 경계 통과 감지(원작 setSkillSlotCheck → "추가 슬롯 개방!!")
	var slot_new := -1
	for si in Loadout.SLOT_UNLOCK_LEVEL.size():
		var lreq := int(Loadout.SLOT_UNLOCK_LEVEL[si])
		if level < lreq and new_level >= lreq:
			slot_new = si
	_refresh_stats()
	_lvup_redraw({"kind": "up", "sp": 1.0,
		"stage_changed": Growth.stage_for_level(new_level) != old_stage,
		"slot_new": slot_new, "triple": bool(roll.get("triple", false))})

## 우하단 리롤 블록 — AUTO 버튼 + 회전화살표 + "능력치 다시뽑기" + 다이아 비용.
## 참조: docs/ref/orig_image/levelup/Screenshot_2017-02-27-11-12-03-1.png
func _lvup_build_reroll(body: Control, vis: Vector2, roll_cfg: Dictionary, no_history: bool) -> void:
	var cman := _man_common()
	var cost := _lvup_reroll_cost()
	var have := UserDB.currency(String(cost["kind"]))
	var affordable := have >= int(cost["amount"])
	var bx := vis.x * 0.60
	var by := vis.y * 0.70   # 블록 전체가 하단 텍스트박스(위쪽 경계 = vis.y-120) 위에 오도록

	# AUTO(원작 common/bt_levelupauto_on|off, 문자열 DragonResetAuto "다시뽑기 자동").
	# ⚠️ 자동 반복은 다이아를 크게 소모한다(원작 DragonResetAutoConfirm 경고) → 확인 후 트리플맥스까지 반복.
	var auto_on := bool(_lvup_ctx.get("auto", false))
	var ab := TextureButton.new()
	var ap := "res://assets/converted/common_ui/common_bt_levelupauto_%s.tres" % ("on" if auto_on else "off")
	if ResourceLoader.exists(ap):
		ab.texture_normal = load(ap)
		ab.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	ab.position = Vector2(bx, by + 6)
	ab.disabled = no_history
	ab.tooltip_text = "다시뽑기 자동"
	ab.pressed.connect(_lvup_toggle_auto)
	body.add_child(ab)

	# 회전화살표 아이콘 = 원작 `common/stat_reflash`("stat refresh" — 능력치 다시뽑기 전용 아이콘).
	# ⚠️ `common/refresh` 는 돋보기다(BookPopup/SkinPopup 의 목록 갱신용) — 혼동 금지.
	var ix := bx + 110.0
	var iy := by + 34.0
	var ric := _atlas_sprite("common_ui", "common_stat_reflash", cman, Design.ASSET_SCALE * 0.72)
	if ric:
		ric.position = Vector2(ix, iy)
		if not affordable or no_history: ric.modulate = Color(0.55, 0.55, 0.55)
		body.add_child(ric)

	# "(MAX 확률 x% ▲)" — 원작 DragonResetMax1 + `common/maxpercent_arrow` + DragonResetMax2
	var pity := LevelSystem.pity_prob(roll_cfg, int(_lvup_ctx.get("reroll", 0)))
	var mp := Label.new()
	mp.text = "(MAX 확률 %.1f%%" % (pity * 100.0)
	_lvup_style(mp, 17, Color(1, 0.78, 0.2))
	mp.position = Vector2(ix + 46, by - 2); body.add_child(mp)
	var mpa := _atlas_sprite("common_ui", "common_maxpercent_arrow", cman, Design.ASSET_SCALE)
	var mpw: float = ThemeDB.fallback_font.get_string_size(mp.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	if mpa: mpa.position = Vector2(ix + 56 + mpw, by + 10); body.add_child(mpa)
	var mpc := Label.new()
	mpc.text = ")"
	_lvup_style(mpc, 17, Color(1, 0.78, 0.2))
	mpc.position = Vector2(ix + 66 + mpw, by - 2); body.add_child(mpc)

	# "능력치 다시뽑기" — 원작 DragonReset
	var lb := Label.new()
	lb.text = "능력치 다시뽑기"
	_lvup_style(lb, 23, Color.WHITE if affordable else Color(0.65, 0.65, 0.65))
	lb.position = Vector2(ix + 46, by + 20); body.add_child(lb)

	# 비용: 다이아 아이콘 + "x N"
	var di := _atlas_sprite("common_ui", "common_diamond_small1", cman, Design.ASSET_SCALE * 0.9)
	if di: di.position = Vector2(ix + 62, by + 66); body.add_child(di)
	var cl := Label.new()
	cl.text = "x %d" % int(cost["amount"])
	_lvup_style(cl, 22, Color.WHITE if affordable else Color(1.0, 0.45, 0.45))
	cl.position = Vector2(ix + 84, by + 52); body.add_child(cl)

	# 클릭 영역(아이콘+문구 전체)
	var hit := Button.new()
	hit.flat = true
	hit.name = "RerollButton"        # 스모크 테스트(shot_helper --shot=lvreroll)가 이름으로 찾는다
	hit.size = Vector2(240, 96); hit.position = Vector2(ix - 34, by - 6)
	hit.disabled = no_history or not affordable
	hit.tooltip_text = ("보유 %s %d" % [String(cost["kind"]), have]) if not affordable else ""
	hit.pressed.connect(_lvup_ask_reroll)
	body.add_child(hit)

## 원작 DragonResetConfirm — "다이아를 소모하여 능력치를 다시 뽑으시겠습니까?"
func _lvup_ask_reroll() -> void:
	_open_popup_type("능력치 다시뽑기", "다이아를 소모하여 능력치를 다시 뽑으시겠습니까?",
		func(): _lvup_do_reroll_once())

## 원작 DragonResetAutoConfirm — 자동은 다이아를 크게 소모하므로 확인을 받는다.
func _lvup_toggle_auto() -> void:
	if _lvup_ctx.is_empty(): return
	if bool(_lvup_ctx.get("auto", false)):
		_lvup_ctx["auto"] = false
		_lvup_redraw()
		return
	_open_popup_type("다시뽑기 자동", "다시뽑기를 자동으로 하시겠습니까?\n이 경우, 다이아가 많이 소모될 수 있습니다.",
		func():
			if _lvup_ctx.is_empty(): return
			_lvup_ctx["auto"] = true
			_lvup_redraw()
			_lvup_auto_loop())

## 자동 다시뽑기: 트리플맥스가 나오거나 다이아가 떨어질 때까지 반복(오프라인 재구성).
func _lvup_auto_loop() -> void:
	while not _lvup_ctx.is_empty() and bool(_lvup_ctx.get("auto", false)):
		if not _lvup_do_reroll_once():
			break
		# 연출(원작 안무, 자동은 2배속 = sp 0.5)이 끝날 때까지 대기 — 원작도 연출 완료 후 반복.
		while _lvup_fx_busy:
			await get_tree().create_timer(0.1).timeout
			if _lvup_ctx.is_empty(): return
		var d := UserDB.get_dragon(int(_lvup_ctx["uid"]))
		var gl: Array = d.get("gain_log", [])
		var mx := Growth.tier_growth(_lvup_ctx["ddef"], Data.stat_table)
		if not gl.is_empty():
			var lastg: Dictionary = gl[gl.size() - 1]
			var all_max := true
			for k in ["hp", "att", "def"]:
				if int(lastg.get(k, 0)) < int(mx.get(k, 1)): all_max = false
			if all_max: break
		await get_tree().create_timer(0.3).timeout
	if not _lvup_ctx.is_empty():
		_lvup_ctx["auto"] = false
		_lvup_redraw()

## 능력치 다시뽑기 1회: 다이아 소비 → 직전 레벨 롤 교체(리롤 천장 pity 반영). 반환=성공.
## 트리플맥스가 나오면 천장 리셋. 비용은 data 노브(원작 관찰: 다이아 2).
## 연출은 원작 ExpLayer 리셋 안무(_lvup_fx_timeline kind="reset") — 배너·사운드·컷인 전부 타임라인.
func _lvup_do_reroll_once() -> bool:
	if _lvup_ctx.is_empty() or _lvup_fx_busy: return false
	var uid := int(_lvup_ctx["uid"])
	var ddef: Dictionary = _lvup_ctx["ddef"]
	var cost := _lvup_reroll_cost()
	var kind := String(cost["kind"])
	var amount := int(cost["amount"])
	if UserDB.currency(kind) < amount: return false
	if (UserDB.get_dragon(uid).get("gain_log", []) as Array).is_empty(): return false
	var roll_cfg: Dictionary = Data.level_curve.get("roll", {})
	var max_stats := Growth.tier_growth(ddef, Data.stat_table)
	var pity := LevelSystem.pity_prob(roll_cfg, int(_lvup_ctx.get("reroll", 0)))
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var roll := LevelSystem.roll_level(roll_cfg, max_stats, rng, pity, "")
	if not UserDB.spend(kind, amount): return false
	if not UserDB.replace_last_gain(uid, roll): return false
	_lvup_ctx["reroll"] = 0 if bool(roll.get("triple", false)) else int(_lvup_ctx.get("reroll", 0)) + 1
	_refresh_stats()
	_lvup_redraw({"kind": "reset", "sp": 0.5 if bool(_lvup_ctx.get("auto", false)) else 1.0,
		"stage_changed": false, "slot_new": -1, "triple": bool(roll.get("triple", false))})
	return true

## 원작 드래곤 스킨(makeAllSkinMenu/requestDragonSkin): 기본/스킨 변형 선택 → 초상 교체.
## ⚠️ 현 에셋: skin1 초상만(소수 드래곤), 스킨 스파인 변형 미변환 → 받침대 드래곤(spine)은 기본 유지, 초상만 스킨 반영.
func _open_dragon_skin() -> void:
	var a := _active()
	if a.is_empty(): return
	var uid := int(a["uid"]); var id := int(a["id"])
	var cnt := _dragon_skin_count(id)
	var cur := int(a.get("skin", 0))
	var vis := _vis()
	var overlay := CanvasLayer.new(); overlay.layer = 30; add_child(overlay)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: overlay.queue_free())
	overlay.add_child(dim)
	# 원작 DragonSkinInfoPopup 1:1: popup4(capInsets130,190,40,58) + pop_title_bg + backlight3(스킨 발광) + close_btn.
	# 근거: DragonSkinInfoPopup.c setContentSprite(9patch/popup4)+pop_title_bg+common/backlight3.
	const BW := 640.0
	const BH := 340.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	overlay.add_child(win)
	var tbar := NinePatchRect.new(); tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(BW * 0.9, 52); tbar.position = Vector2((BW - BW * 0.9) * 0.5, 12); win.add_child(tbar)
	var t := Label.new(); t.text = "드래곤 스킨"; t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color.WHITE); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; t.size = tbar.size; tbar.add_child(t)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 50 - 16, 14); xb.pressed.connect(func(): overlay.queue_free()); win.add_child(xb)
	var bl := load("res://assets/converted/common_ui/common_backlight3.tres")
	var opts := range(0, cnt + 1)
	var x0 := (BW - float(opts.size()) * 150.0) * 0.5 + 75.0
	for i in opts.size():
		var sk: int = opts[i]
		var cx := x0 + i * 150.0
		if sk == cur and bl:  # 원작 backlight3 발광(선택 스킨 뒤)
			var blr := TextureRect.new(); blr.texture = bl; blr.position = Vector2(cx - 75, 88); blr.size = Vector2(150, 150)
			blr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; win.add_child(blr)
		var por := _portrait_sprite(id, "adult", 0.85, sk)
		if por: por.position = Vector2(cx, 162); win.add_child(por)
		var nl := Label.new(); nl.text = ("기본" if sk == 0 else "스킨%d" % sk) + ("  ✓" if sk == cur else "")
		nl.add_theme_font_size_override("font_size", 15)
		nl.add_theme_color_override("font_color", Color(0.85, 0.6, 0.15) if sk == cur else Color(0.25, 0.18, 0.1))
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; nl.size = Vector2(120, 22); nl.position = Vector2(cx - 60, 244); win.add_child(nl)
		var b := Button.new(); b.flat = true; b.size = Vector2(120, 172); b.position = Vector2(cx - 60, 88)
		b.pressed.connect(func(): UserDB.set_dragon_field(uid, "skin", sk); overlay.queue_free(); _refresh())
		win.add_child(b)

## 🔴 2026-07-30 삭제 — **잠재능력**(자작 등급 리롤).
## 원작 근거로 삼았던 `CaveScene::makePotentialButton` → `PotentialPopup` 은
##   ① 버전 게이트 안에서만 생성되고(`init`: `GameManager+0x6c > 0x1eb(491)`),
##   ② 전용 문자열 번들 `string/potential/strings.xml` · 데이터 `game_data/update_dragon_stats.hb`
##      · 프레임 `scene/cave/nurture/nurture_title_%s` · 버튼 `bt_rank` 이 **전부 우리 덤프에 없다**
## ⇒ 우리 에셋 스냅샷 이후의 후기 업데이트분이고, 원작 팝업의 실제 내용은 복원 불가다.
## 우리가 붙였던 D~S 등급 리롤은 원작과 무관한 자작이라 기능째 걷어냈다(사용자 확정).
## 세이브의 `potential` 필드는 남아 있어도 이제 어디서도 읽지 않는다.
## 원작 이름표(onClickNicName): 활성 드래곤 별명 설정 팝업. 별명=UserDB에 영속(dragon.nick).
func _open_rename() -> void:
	var a := _active()
	if a.is_empty(): return
	var uid := int(a["uid"])
	var species := str(Data.get_dragon(int(a["id"])).get("name", "드래곤"))
	# 원작 DragonNickNamePopup 1:1: docs/ref/orig_code/decomp/DragonNickNamePopup.c init@00e84ab8/initWidget@00e84f54.
	# popup4 650×480(capInsets130,190,40,58) + pop_title_bg 타이틀바 + 9patch/text_box 입력(400×53)
	# + 버튼2(220×56 @ cocos(bgW*0.5±120,75)). 좌표 cocos y-up→Godot y'=BH-y. 서버제출(NetworkManager)=오프라인 로컬 대체.
	const BW := 650.0
	const BH := 480.0
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 50; add_child(layer)
	var pop := Control.new(); pop.set_anchors_preset(Control.PRESET_FULL_RECT); layer.add_child(pop)
	pop.tree_exiting.connect(func(): if is_instance_valid(layer): layer.queue_free())
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pop.add_child(dim)
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5)); pop.add_child(win)
	# 타이틀 바(pop_title_bg, size bgW*0.9, 상단중앙)
	var tbar := NinePatchRect.new(); tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(BW * 0.9, 56); tbar.position = Vector2((BW - BW * 0.9) * 0.5, 14); win.add_child(tbar)
	var title := Label.new(); title.text = "이름 짓기"
	title.add_theme_font_size_override("font_size", 24); title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size = tbar.size; tbar.add_child(title)
	# 닫기(우상단 cocos(bgW-50,bgH-50))
	var cls := TextureButton.new(); cls.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	cls.position = Vector2(BW - 50 - 22, (BH - 430) - 22); win.add_child(cls)
	cls.pressed.connect(func(): pop.queue_free())
	# 입력 필드(9patch/text_box 400×53, 중앙). ⚠️정확 y는 initWidget 계산값 → 중앙 근사.
	var tbox := NinePatchRect.new(); tbox.texture = load("res://assets/converted/ninepatch_ui/9patch_text_box.tres")
	tbox.patch_margin_left = 20; tbox.patch_margin_right = 20; tbox.patch_margin_top = 16; tbox.patch_margin_bottom = 16
	tbox.size = Vector2(400, 53); tbox.position = Vector2((BW - 400) * 0.5, 210); win.add_child(tbox)
	var le := LineEdit.new(); le.flat = true
	le.text = String(a.get("nick", "")); le.placeholder_text = species; le.max_length = 12
	le.add_theme_font_size_override("font_size", 22); le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	le.set_anchors_preset(Control.PRESET_FULL_RECT); le.add_theme_color_override("font_color", Color(0.15, 0.12, 0.08))
	tbox.add_child(le); le.grab_focus()
	var hint := Label.new(); hint.text = "원종: %s   (비우면 원종명 사용)" % species
	hint.add_theme_font_size_override("font_size", 15); hint.add_theme_color_override("font_color", Color(0.55, 0.5, 0.42))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hint.size = Vector2(BW, 22); hint.position = Vector2(0, 168); win.add_child(hint)
	# name_on/off(원작 showBalloon 토글): 머리 위 이름 말풍선 — 오프라인 유지.
	var bchk := CheckBox.new(); bchk.text = "머리 위 이름 말풍선 표시"
	bchk.button_pressed = bool(UserDB.get_pmeta("name_balloon", true))
	bchk.add_theme_font_size_override("font_size", 16)
	bchk.position = Vector2((BW - 240) * 0.5, 290); win.add_child(bchk)
	# 확인/취소 버튼(cocos(bgW*0.5-120,75)&(+120,75), 220×56 → Godot y'=BH-75 중심)
	var ok := Button.new(); ok.text = "확인"; ok.size = Vector2(220, 56); ok.position = Vector2(BW * 0.5 - 120 - 110, BH - 75 - 28)
	var apply := func():
		UserDB.set_dragon_field(uid, "nick", le.text.strip_edges())
		UserDB.set_pmeta("name_balloon", bchk.button_pressed)
		pop.queue_free(); _refresh_stats()
	ok.pressed.connect(apply); le.text_submitted.connect(func(_s): apply.call())
	win.add_child(ok)
	var cancel := Button.new(); cancel.text = "취소"; cancel.size = Vector2(220, 56); cancel.position = Vector2(BW * 0.5 + 120 - 110, BH - 75 - 28)
	cancel.pressed.connect(func(): pop.queue_free()); win.add_child(cancel)

func _elem_row(parent: Control, label: String, elems: Array, col: Color, y: float) -> void:
	var l := Label.new(); l.text = label; l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", col); l.position = Vector2(28, y); parent.add_child(l)
	if elems.is_empty():
		var n := Label.new(); n.text = "없음"; n.add_theme_font_size_override("font_size", 16)
		n.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7)); n.position = Vector2(28, y + 30); parent.add_child(n)
		return
	var x := 28.0
	for e in elems:
		var mk := _atlas_sprite("battle_ui", "battle_element_%s_mark" % str(e), _battle_manifest, 0.5)
		if mk:
			# 회전 보정 불필요(변환 단계 흡수). 예전 `PI/2 + flip_h` 는 거울상이라 잘못된 땜질이었다.
			mk.position = Vector2(x + 18, y + 48); parent.add_child(mk)
		var nl := Label.new(); nl.text = _ELEM_KR.get(str(e), str(e)); nl.add_theme_font_size_override("font_size", 14)
		nl.add_theme_color_override("font_color", Color.WHITE); nl.position = Vector2(x, y + 68); parent.add_child(nl)
		x += 76.0

## 둥지 상단바 속성 아이콘. 원작 CaveScene은 `item/item_small/ele_*.png` 11종을 쓴다
## (CaveScene.c:15651~ 문자열 테이블: ele_all/fire/water/wind/ground/light/dark/holy/chaos/shadow).
## 이전 구현은 `battle_element_*_mark`(다른 팝업용 마크)를 썼다 — 원작과 다른 자산이었다.
## ⚠️ 프레임명은 **완성형 키로** 적는다. 접두사 + 포맷 자리표시자로 조립하면
## asset_index가 같은 아틀라스의 아이템 아이콘 수백 개까지 사용 중으로 오집계한다(거짓 커버리지).
## 주석에도 그 조립 문자열을 인용해 적지 말 것 — 색인기는 주석 속 리터럴도 토큰으로 읽는다.
const ELE_SMALL := {
	"all": "item_item_small_ele_all", "fire": "item_item_small_ele_fire",
	"aqua": "item_item_small_ele_water", "earth": "item_item_small_ele_ground",
	"wind": "item_item_small_ele_wind", "light": "item_item_small_ele_light",
	"dark": "item_item_small_ele_dark", "holy": "item_item_small_ele_holy",
	"chaos": "item_item_small_ele_chaos", "shadow": "item_item_small_ele_shadow"}

func _update_elem_icon(element: String) -> void:
	var name := str(ELE_SMALL.get(element, ELE_SMALL["all"]))
	var p := "res://assets/converted/item_small_ui/%s.tres" % name
	if not ResourceLoader.exists(p):
		_elem_icon.visible = false
		return
	_elem_icon.visible = true
	_elem_icon.texture = load(p)
	var info: Dictionary = _item_small_manifest.get(name, {})
	# 회전 보정 불필요(변환 단계 흡수). 예전 `PI/2 + flip_h` 는 거울상이라 잘못된 땜질이었다.
	_elem_icon.rotation = 0.0
	_elem_icon.flip_h = false
	var hh: float = maxf(1.0, float(info.get("h", 70)))
	_elem_icon.scale = Vector2(46.0 / hh, 46.0 / hh)

# ---------- actions ----------
# 🔴 2026-07-28 제거: `_on_levelup` (호출자 없는 죽은 코드). 성장단계 경계에서 `_evolution_ceremony`
#    를 태우던 유일한 곳이었는데, 그 연출은 각성용이었다 → scripts/ui/evol_layer.gd 로 옮겼다.
#    실제 레벨업 경로는 `_open_levelup` → `_lvup_use_item` 이다.

## 원작 레벨업 날개 연출. `scene/cave/dragon_enchant_lvup.spine_json`을 DragonEnchantResultLayer가 쓴다.
## 슬롯: enchant_upwing1~6(날개 프레임 토글) + **skill_resetp = 금색 "LEVEL UP" 텍스트**.
## 애니 "reset" 2.0s. 아틀라스명이 스켈레톤명과 달라(enchant_lvup_spine) --atlas 로 변환.
## 참조: docs/ref/orig_image/levelup/Screenshot_2016-05-01-23-07-40.png.
## 진화 연출과 같은 검증된 경로(_play_fx_spine)를 쓴다.
func _levelup_banner() -> void:
	var vis := _vis()
	_play_fx_spine("res://scenes/fx/dragon_enchant_lvup.tscn", "reset", Vector2(vis.x * 0.5, vis.y * 0.40), 70)

## 원작 MakeMasicStonePopup 1:1: 정령석 제작 — popup4 + pop_title_bg + backlight3 + check_btn(확인).
## 근거: MakeMasicStonePopup.c init(9patch/popup4 + common/backlight3 + common/check_btn)+onclose. ⚠️제작 재료·확률=서버유실→
## 오프라인(골드 → 정령석 잠재석 stone_spirit1, 비용 2000 ASSUMPTION). 정령석=드래곤 잠재/강화 재료(PopupMasicStone 적용은 별도).
const MAGIC_STONE_COST := 2000
const MAGIC_STONE_ITEM := "stone_spirit1"
func _open_make_magic_stone() -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 72; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	const BW := 420.0
	const BH := 300.0
	var cf := FileAccess.open("res://assets/converted/common_ui/_manifest.json", FileAccess.READ)
	var cm: Dictionary = JSON.parse_string(cf.get_as_text()) if cf else {}
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(280, 52); tbar.position = Vector2((BW - 280) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = "정령석 제작"
	tl.add_theme_font_size_override("font_size", 26); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	var bl := _atlas_sprite("common_ui", "common_backlight3", cm, 0.75)
	if bl: bl.position = Vector2(BW * 0.5, 140); bl.modulate = Color(1, 1, 1, 0.35); win.add_child(bl)
	var ipath := Data.item_icon_path(MAGIC_STONE_ITEM)
	if ResourceLoader.exists(ipath):
		var icon := Sprite2D.new(); icon.texture = load(ipath); icon.material = _pma
		icon.position = Vector2(BW * 0.5, 140); icon.scale = Vector2(0.9, 0.9); win.add_child(icon)
	var ml := Label.new(); ml.text = "정령석 잠재석을 제작합니다."
	ml.add_theme_font_size_override("font_size", 18); ml.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; ml.position = Vector2(0, 196); ml.size = Vector2(BW, 24); win.add_child(ml)
	# 확인(원작 check_btn) + 골드 비용.
	var ok := Button.new(); ok.size = Vector2(180, 50); ok.position = Vector2((BW - 180) * 0.5, BH - 74); win.add_child(ok)
	var oc := _atlas_sprite("common_ui", "common_coin_small1", cm, 0.8)
	if oc: oc.position = Vector2(BW * 0.5 - 46, BH - 49); win.add_child(oc)
	var ol := Label.new(); ol.text = "제작  %d" % MAGIC_STONE_COST; ol.add_theme_font_size_override("font_size", 19)
	ol.add_theme_color_override("font_color", Color.WHITE); ol.position = Vector2(BW * 0.5 - 24, BH - 61); ol.size = Vector2(130, 26); win.add_child(ol)
	ok.pressed.connect(func():
		if not UserDB.spend("gold", MAGIC_STONE_COST): return
		UserDB.add_item(MAGIC_STONE_ITEM, 1)
		if is_instance_valid(layer): layer.queue_free()
		_open_complete("정령석 제작", "%s 1개를 제작했습니다!" % Data.item_name(MAGIC_STONE_ITEM)))

## 원작 TrainingSelectLayer 1:1: 훈련 선택(Latea 훈련탭) — popup4 + pop_title_bg + scene/promote/train%d(10옵션) + slot_bg + cash_box.
## 근거: TrainingSelectLayer.c initWidget(scene/promote.img_plist + train%d.png + slot_bg + cash_box)+onClickCell/getLevel
## + 타이머("(%02ld:%02ld:%02d)"). ⚠️훈련 레벨효과·비용·소요시간=서버유실→오프라인 즉시(train%d=+%d레벨, 비용 300*d ASSUMPTION).
func _open_training_select() -> void:
	var a := _active()
	if a.is_empty(): return
	_open_backdrop(0.55)
	var vis := _vis()
	var BW := clampf(vis.x - 120.0, 640.0, 960.0)
	var BH := clampf(vis.y - 80.0, 480.0, 640.0)
	var pf := FileAccess.open("res://assets/converted/promote_ui/_manifest.json", FileAccess.READ)
	var pm: Dictionary = JSON.parse_string(pf.get_as_text()) if pf else {}
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	_overlay.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(300, 54); tbar.position = Vector2((BW - 300) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = "훈련"
	tl.add_theme_font_size_override("font_size", 26); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 66, 14); xb.pressed.connect(_close_overlay); win.add_child(xb)
	var cf := FileAccess.open("res://assets/converted/common_ui/_manifest.json", FileAccess.READ)
	var cm: Dictionary = JSON.parse_string(cf.get_as_text()) if cf else {}
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 92); scroll.size = Vector2(BW - 80, BH - 130)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = maxi(3, int((BW - 80) / 200.0))
	grid.add_theme_constant_override("h_separation", 10); grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	var uid := int(a["uid"])
	for i in range(1, 11):
		var lv_gain := i
		var cost := 300 * i
		var cell := Control.new(); cell.custom_minimum_size = Vector2(190, 90)
		var slot := _atlas_sprite("promote_ui", "scene_promote_slot_bg", pm, 1.2)
		if slot: slot.position = Vector2(95, 30); cell.add_child(slot)
		var timg := _atlas_sprite("promote_ui", "scene_promote_train%d" % i, pm, 0.6)
		if timg: timg.position = Vector2(36, 30); cell.add_child(timg)
		var nm := Label.new(); nm.text = "훈련 %d  (+%dLv)" % [i, lv_gain]
		nm.add_theme_font_size_override("font_size", 15); nm.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
		nm.position = Vector2(64, 16); nm.size = Vector2(120, 22); cell.add_child(nm)
		var coin := _atlas_sprite("common_ui", "common_coin_small1", cm, 0.7)
		if coin: coin.position = Vector2(72, 46); cell.add_child(coin)
		var cl := Label.new(); cl.text = "%d" % cost
		cl.add_theme_font_size_override("font_size", 14); cl.add_theme_color_override("font_color", Color(0.35, 0.24, 0.06))
		cl.position = Vector2(88, 36); cl.size = Vector2(90, 22); cell.add_child(cl)
		var b := Button.new(); b.flat = true; b.size = Vector2(190, 62); b.position = Vector2(0, 0)
		b.pressed.connect(func():
			if not UserDB.spend("gold", cost): return
			var cur := UserDB.get_dragon(uid)
			var old_lv := int(cur.get("level", 1))
			var nl := old_lv
			for _s in lv_gain:
				nl = Growth.next_level(nl, bool(cur.get("awakened", false)))
			# set_level 안에서 레벨 10·25·45 자동 습득이 함께 돈다.
			var sk_before := UserDB.dragon_skills(uid).size()
			UserDB.set_level(uid, nl)
			var got := _skills_learned_since(uid, sk_before)
			_close_overlay(); _refresh()
			_open_training_result(int(cur["id"]), old_lv, nl)
			if not got.is_empty():
				_toast("새 스킬 습득 — %s" % ", ".join(got)))
		cell.add_child(b)
		grid.add_child(cell)

## 원작 TrainingResultLayer 1:1: 훈련/레벨 결과 — popup4 + pop_title_bg + backlight3 + 드래곤초상 + 레벨(getLevel) + 확인.
## 근거: TrainingResultLayer.c initWidget(9patch/popup4 + common/backlight3 + coin_small1/diamond_small1 + btn_arrow2)
## + getLevel(info_exp 커브)/getLevelExp + onClickOk/onClickClose. ⚠️훈련 EXP·비용=서버유실→우리 Growth 레벨규칙 사용.
func _open_training_result(dragon_id: int, before_lv: int, after_lv: int) -> void:
	Bgm.sfx("effect_level_updown")   # 원작 레벨 사운드
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 72; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	const BW := 440.0
	const BH := 500.0
	var cf := FileAccess.open("res://assets/converted/common_ui/_manifest.json", FileAccess.READ)
	var cm: Dictionary = JSON.parse_string(cf.get_as_text()) if cf else {}
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(280, 52); tbar.position = Vector2((BW - 280) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = "훈련 완료"
	tl.add_theme_font_size_override("font_size", 26); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	var bl := _atlas_sprite("common_ui", "common_backlight3", cm, 0.9)
	if bl: bl.position = Vector2(BW * 0.5, 150); bl.modulate = Color(1, 1, 1, 0.4); win.add_child(bl)
	var por := _portrait_sprite(dragon_id, Growth.stage_for_level(after_lv), 0.8, 0)
	if por: por.position = Vector2(BW * 0.5, 150); win.add_child(por)
	# 원작 레벨업 결과(docs/ref/orig_image/levelup/Screenshot_2016-05-01-23-07-40.png):
	# 금색 "LEVEL UP" + `레벨 10 ▶ 11` / `생명력 322 ▶ 335 (+13)` 형식의 before▶after 표.
	# 라벨 색: 레벨=노랑 · 생명력=초록 · 공격력=빨강 · 방어력=파랑(원작 스크린샷).
	# "LEVEL UP" 이미지 = enchant_lvup 스파인의 skill_resetp 리전을 표준 PNG로 추출한 것.
	var lup := TextureRect.new()
	lup.texture = load("res://assets/converted/lvup_ui/level_up.png")
	lup.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # 기본값은 텍스처 원본 크기 → 축소 안 됨
	lup.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lup.size = Vector2(180, 96); lup.position = Vector2((BW - 180) * 0.5, 196)
	win.add_child(lup)
	# 스탯 행. 원작 레퍼런스(docs/ref/orig_image/levelup/Screenshot_2016-06-23-12-18-13.png)는 증가분을
	# **`(+13/9)` = (실제상승 / 티어최대)** 로 적고, 최대치가 나온 스탯 수만큼 `1MAX/2MAX/3MAX`
	# 배지를 우측에 띄운다. 분모 = Growth.tier_growth(= LevelSystem.roll_level 의 max_stats).
	var max_stats: Dictionary = Growth.tier_growth(Data.get_dragon(dragon_id), Data.stat_table)
	var rows := [["레벨", Color(1.0, 0.83, 0.25), str(before_lv), str(after_lv), "", false]]
	var sb: Dictionary = _active().get("stat_bonus", {})
	var maxed := 0
	for spec in [["hp", "생명력", Color(0.45, 0.95, 0.45)], ["att", "공격력", Color(1.0, 0.45, 0.4)],
			["def", "방어력", Color(0.45, 0.7, 1.0)]]:
		var st: Dictionary = Growth.compute_stats(Data.get_dragon(dragon_id), Data.stat_table, after_lv, sb)
		var pv: Dictionary = Growth.compute_stats(Data.get_dragon(dragon_id), Data.stat_table, before_lv, sb)
		var k: String = spec[0]
		var delta := int(st[k]) - int(pv[k])
		var mx := int(max_stats.get(k, 0))
		var is_max := mx > 0 and delta >= mx
		if is_max: maxed += 1
		rows.append([String(spec[1]), spec[2], str(int(pv[k])), str(int(st[k])),
			("(+%d/%d)" % [delta, mx]) if mx > 0 else "(+%d)" % delta, is_max])
	# ⚠️ 원작 TrainingResultLayer는 `font/font_heal.fnt`를 쓰지만, 그 BMFont는 글리프가
	#    `.0123456789` **12자뿐**(assets/480/font/font_heal.fnt `chars count=12`)이라
	#    `(+13/9)` 형태의 괄호·부호·슬래시를 못 낸다(두부 렌더 확인). 증가분 표기는 TTF로 낸다.
	#    → 순수 숫자만 나오는 곳(전투 힐 수치)에서는 계속 font_heal을 쓴다.
	for i in rows.size():
		var y := 300.0 + i * 34.0
		var nm2 := Label.new(); nm2.text = String(rows[i][0])
		nm2.add_theme_font_size_override("font_size", 21); nm2.add_theme_color_override("font_color", rows[i][1])
		nm2.position = Vector2(48, y); nm2.size = Vector2(96, 28); win.add_child(nm2)
		var bv := Label.new(); bv.text = String(rows[i][2])
		bv.add_theme_font_size_override("font_size", 21); bv.add_theme_color_override("font_color", Color(0.35, 0.26, 0.12))
		bv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		bv.position = Vector2(140, y); bv.size = Vector2(78, 28); win.add_child(bv)
		# ▶ = 원작 `common/btn_arrow2` 스프라이트(이전엔 텍스트 "▶" 자작).
		var ar := _atlas_sprite("common_ui", "common_btn_arrow2", cm, 0.6)
		if ar:
			ar.position = Vector2(240, y + 14); win.add_child(ar)
		else:
			var art := Label.new(); art.text = "▶"
			art.add_theme_font_size_override("font_size", 20)
			art.add_theme_color_override("font_color", Color(1.0, 0.78, 0.15))
			art.position = Vector2(226, y); art.size = Vector2(28, 28); win.add_child(art)
		var av := Label.new(); av.text = String(rows[i][3])
		av.add_theme_font_size_override("font_size", 21); av.add_theme_color_override("font_color", Color(0.2, 0.14, 0.05))
		av.position = Vector2(262, y); av.size = Vector2(78, 28); win.add_child(av)
		if String(rows[i][4]) != "":
			var dl := Label.new(); dl.text = String(rows[i][4])

			dl.add_theme_font_size_override("font_size", 17)
			dl.add_theme_color_override("font_color",
				Color(1.0, 0.45, 0.85) if bool(rows[i][5]) else Color(0.45, 0.6, 0.35))
			dl.position = Vector2(338, y + 3); dl.size = Vector2(84, 24); win.add_child(dl)
	# 1MAX/2MAX/3MAX 배지(원작 우측 톱니 아이콘 옆 표기). 최대 상승이 나온 스탯 수.
	if maxed > 0:
		var mb := Label.new(); mb.text = "%dMAX" % maxed
		mb.add_theme_font_size_override("font_size", 22)
		mb.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
		mb.add_theme_color_override("font_outline_color", Color(0.5, 0.15, 0.4, 0.9))
		mb.add_theme_constant_override("outline_size", 4)
		mb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mb.position = Vector2(BW - 110, 268); mb.size = Vector2(90, 28); win.add_child(mb)
	var ok := Button.new(); ok.text = "확인"; ok.size = Vector2(160, 46); ok.position = Vector2((BW - 160) * 0.5, BH - 62)
	ok.pressed.connect(func(): if is_instance_valid(layer): layer.queue_free()); win.add_child(ok)

## 🔴 2026-07-28 제거: `_evolution_ceremony`.
## `evolution_wing`/`evolution_effect2` 는 성장단계 연출이 아니라 **각성(원작 메뉴명 "진화")**
## 연출이다 — `EvolLayer::create` 호출자는 `DragonAwaken.c:2859` 하나뿐이고
## `EvolLayer::setEvolDragon` 이 `Dragon::setAwaken(true)` 를 호출한다.
## 원작 시퀀스 전체는 `scripts/ui/evol_layer.gd`(EvolLayer 이식)로 옮겼고, 각성 성공 시 탄다.
## 이펙트 spine 재생 헬퍼(변환된 fx tscn을 center에 인스턴스화, 애니 1회 후 자동 제거).
func _play_fx_spine(path: String, anim: String, center: Vector2, zidx: int, parent: Node = null,
		scale := 1.5) -> void:
	if not ResourceLoader.exists(path):
		return
	var holder := Node2D.new()
	holder.position = center; holder.z_index = zidx; holder.scale = Vector2(scale, scale)
	(parent if is_instance_valid(parent) else self).add_child(holder)
	var inst = load(path).instantiate()
	holder.add_child(inst)
	var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
	if ap and ap.has_animation(anim):
		ap.get_animation(anim).loop_mode = Animation.LOOP_NONE
		ap.play(anim)
		ap.animation_finished.connect(func(_a): if is_instance_valid(holder): holder.queue_free())
	else:
		get_tree().create_timer(2.0).timeout.connect(func(): if is_instance_valid(holder): holder.queue_free())

## 각성/승급 세리머니 — 원작 CaveScene 1:1(ascension_event_spine). 근거: CaveScene.c:17707
## createWithFile("scene/cave/ascension_event_spine.spine_json") + setAnimation("animation") @ 드래곤 중앙,
## DelayTime(1.0) + 터치잠금(disable/restoreAllTouchesWithoutCurrentLayer). + 금빛 플래시 + 드래곤 펄스 + 배너.
func _ascension_ceremony() -> void:
	var vis := _vis()
	var center := Vector2(vis.x * 0.5, vis.y * 0.46)
	# 원작 각성 이펙트 spine(ascension_event_spine "animation") @ 드래곤 중앙.
	_play_fx_spine("res://scenes/fx/ascension_event.tscn", "animation", center, 57)
	# 전체 금빛 플래시(강)
	var flash := ColorRect.new(); flash.color = Color(1, 0.92, 0.55, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT); flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 60; add_child(flash)
	var ft := flash.create_tween()
	ft.tween_property(flash, "color:a", 0.9, 0.18)
	ft.tween_property(flash, "color:a", 0.0, 0.7)
	ft.tween_callback(func(): if is_instance_valid(flash): flash.queue_free())
	# 드래곤 확대 펄스(진화보다 크게)
	if is_instance_valid(_stage):
		var s0: Vector2 = _stage.scale
		var st := _stage.create_tween()
		st.tween_property(_stage, "scale", s0 * 1.28, 0.35).set_trans(Tween.TRANS_BACK)
		st.tween_property(_stage, "scale", s0, 0.5)
	# 배너
	var banner := Label.new(); banner.text = "★ 각성 완료! ★"
	banner.add_theme_font_size_override("font_size", 48)
	banner.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	banner.add_theme_color_override("font_outline_color", Color(0.4, 0.2, 0, 0.9))
	banner.add_theme_constant_override("outline_size", 7)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.size = Vector2(vis.x, 60); banner.position = Vector2(0, vis.y * 0.24)
	banner.z_index = 61; banner.modulate.a = 0.0; add_child(banner)
	var bt := banner.create_tween()
	bt.tween_property(banner, "modulate:a", 1.0, 0.25)
	bt.tween_interval(1.0)
	bt.tween_property(banner, "modulate:a", 0.0, 0.5)
	bt.tween_callback(banner.queue_free)

## 현재 스킨 메뉴 탭("theme"=동굴 배경 / "stand"=받침대). 모범답안: OldRef_image/Cave_skinmenu.jpg
var _skin_tab := "theme"

func _skin_tab_def(tab_id: String) -> Dictionary:
	if tab_id == "stand":
		return {"key": "stand_skin", "count": STAND_COUNT, "title": "단상"}
	return {"key": "cave_skin", "count": SKIN_COUNT, "title": "테마"}

func _open_skin() -> void:
	# 스킨 메뉴 — 원작 SkinPopup 1:1(근거: CaveScene.c:8622 onClickSkin→SkinPopup::show;
	#   SkinPopup.c=9patch/popup4 + scroll_box + CCTableView + skin_frame + close_btn, 테마/단상 탭).
	# 그리드 선택 + 우측 미리보기 + 하단 탭. 변경은 실시간 반영.
	# ASSUMPTION: 오프라인 전용이라 잠금(자물쇠 common/lock) 없이 전 스킨 선택 가능(원작은 획득제).
	_open_backdrop(0.5)
	var vis := _vis()
	# 뷰포트에 맞춤(원작 SkinPopup은 visibleRect 중앙 배치). 692공간이라 화면보다 크지 않게.
	var BW := clampf(vis.x - 40.0, 900.0, 1240.0)
	var BH := clampf(vis.y - 36.0, 600.0, 680.0)
	var win := NinePatchRect.new()   # 원작 9patch/popup4
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH)
	win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	_overlay.add_child(win)
	var tab := _skin_tab_def(_skin_tab)
	# 타이틀바(원작 pop_title_bg) + 제목
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(360, 56); tbar.position = Vector2((BW - 360) * 0.5, 12)
	win.add_child(tbar)
	var title := Label.new()
	title.text = String(tab["title"])
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.32, 0.2, 0.05))
	title.position = Vector2((BW - 360) * 0.5, 22); title.size = Vector2(360, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win.add_child(title)
	# 닫기(원작 common/close_btn)
	var xb := TextureButton.new()
	xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 66, 14)
	xb.pressed.connect(_close_overlay)
	win.add_child(xb)
	_skin_grid(win, tab, BW)
	_skin_preview(win, tab, BW, BH)
	_skin_tabs_bar(win, BW, BH)

func _skin_grid(win: Control, tab: Dictionary, bw: float) -> void:
	# 좌측 그리드(우측 미리보기 패널 영역 제외). 스크롤 컨테이너로 넘치면 스크롤(원작 CCTableView).
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 84)
	scroll.size = Vector2(bw - 320.0, 470.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	var cur := UserDB.get_skin(String(tab["key"]))
	for i in int(tab["count"]):
		grid.add_child(_skin_cell(tab, i, i == cur))

func _skin_cell(tab: Dictionary, index: int, selected: bool) -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(195, 132)
	var frame := _ui_sprite("scene_cave_skin_frame", 195.0 / 241.0)
	frame.position = Vector2(97, 66)
	cell.add_child(frame)
	var thumb := _skin_thumb(_skin_tab, index, 97, 66, 168, 96)
	if thumb: cell.add_child(thumb)
	if selected:
		# 🟠 정정: 선택 하이라이트가 자작 StyleBoxFlat 테두리였다.
		#   원작 선택 표시는 `9patch/box_outline`(테두리만 있는 9patch) 이다
		#   (`asset_index.py --grep box_outline` → 원작 사용/우리 미사용이었다).
		var hl := NinePatchRect.new()
		hl.texture = load("res://assets/converted/ninepatch_ui/9patch_box_outline.tres")
		hl.patch_margin_left = 14; hl.patch_margin_right = 14
		hl.patch_margin_top = 14; hl.patch_margin_bottom = 14
		hl.modulate = Color(0.45, 1.0, 0.45)
		hl.position = Vector2(6, 6); hl.size = Vector2(183, 120)
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(hl)
	var b := Button.new(); b.flat = true; b.size = Vector2(195, 132)
	b.pressed.connect(func(): _skin_select(String(tab["key"]), index))
	cell.add_child(b)
	return cell

## 스킨 썸네일: 테마=cavebg 이미지, 단상=stand 스프라이트. (cx,cy)=부모 기준 중심.
func _skin_thumb(tab_id: String, index: int, cx: float, cy: float, w: float, h: float) -> Node:
	if tab_id == "theme":
		var tr := TextureRect.new()
		var p := BG % (index + 1)
		if ResourceLoader.exists(p):
			tr.texture = load(p)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.clip_contents = true
		tr.size = Vector2(w, h)
		tr.position = Vector2(cx - w / 2.0, cy - h / 2.0)
		return tr
	var nm := "stand_stand%d" % (index + 1)
	var sw: float = maxf(1.0, float(_stand_manifest.get(nm, {}).get("w", 305)))
	var spr := _atlas_sprite("stand_ui", nm, _stand_manifest, w / sw)
	spr.position = Vector2(cx, cy)
	return spr

func _skin_preview(win: Control, tab: Dictionary, bw: float, bh: float) -> void:
	var cur := UserDB.get_skin(String(tab["key"]))
	var px := bw - 288.0
	# 원작 skin_frame 미리보기 프레임.
	var frame := _ui_sprite("scene_cave_skin_frame", 1.0)
	frame.position = Vector2(px + 128.0, 190.0)
	win.add_child(frame)
	var thumb := _skin_thumb(_skin_tab, cur, px + 128.0, 190.0, 224, 150)
	if thumb: win.add_child(thumb)
	var info := Label.new()
	info.text = "%s  %d / %d" % [String(tab["title"]), cur + 1, int(tab["count"])]
	info.add_theme_font_size_override("font_size", 24)
	info.add_theme_color_override("font_color", Color(0.32, 0.2, 0.05))
	info.position = Vector2(px, 300); info.size = Vector2(256, 32)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win.add_child(info)
	var desc := Label.new()
	desc.text = "선택하면 동굴에 바로 적용됩니다.\n(오프라인 — 전 스킨 사용 가능)"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 18)
	desc.add_theme_color_override("font_color", Color(0.4, 0.3, 0.12))
	desc.position = Vector2(px, 340); desc.size = Vector2(256, 90)
	win.add_child(desc)

func _skin_tabs_bar(win: Control, bw: float, bh: float) -> void:
	var defs := [["theme", "scene_cave_skin", "테마"], ["stand", "scene_cave_tap_button_stand", "단상"]]
	var spacing := 200
	var startx := int(bw * 0.5) - (defs.size() - 1) * spacing / 2
	var y := int(bh - 70.0)
	for i in defs.size():
		var d = defs[i]
		_skin_tab_button(win, String(d[0]), String(d[1]), String(d[2]), startx + i * spacing, y, String(d[0]) == _skin_tab)

func _skin_tab_button(win: Control, tab_id: String, icon: String, label: String, cx: int, y: int, active: bool) -> void:
	var spr := _ui_sprite(icon, 1.3)
	spr.position = Vector2(cx, y)
	if not active: spr.modulate = Color(0.55, 0.55, 0.55, 0.8)
	win.add_child(spr)
	var lbl := Label.new(); lbl.text = label
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(0.3, 0.18, 0.03) if active else Color(0.5, 0.44, 0.32))
	lbl.position = Vector2(cx - 50, y + 42); lbl.size = Vector2(100, 30)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win.add_child(lbl)
	var b := Button.new(); b.flat = true
	b.position = Vector2(cx - 55, y - 45); b.size = Vector2(110, 120)
	b.pressed.connect(func():
		if tab_id != _skin_tab:
			_skin_tab = tab_id
			_open_skin())
	win.add_child(b)

func _skin_select(key: String, index: int) -> void:
	UserDB.set_skin(key, index)
	_refresh()      # 뒤 동굴에 라이브 반영
	_open_skin()    # 메뉴 갱신(선택 하이라이트 + 미리보기)

func _close_overlay() -> void:
	if _overlay: _overlay.queue_free(); _overlay = null
	if _overlay_layer: _overlay_layer.queue_free(); _overlay_layer = null
	# 도감이 숨겼던 하단바·좌측 리스트 복원(원작 도감 닫힘 시 setBottomSkin/Dragons 복귀 대응).
	if is_instance_valid(_bottom_bar): _bottom_bar.visible = true
	if is_instance_valid(_left_wall): _left_wall.visible = true

## 오버레이 전용 CanvasLayer(드래곤 spine 위에 그려지도록). 호출 시 새로 만든다.
func _overlay_canvas() -> CanvasLayer:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 10
	add_child(_overlay_layer)
	return _overlay_layer

## 전체화면 딤 백드롭(692 vis를 네이티브 full-rect로 덮음 — 폭 무관). _overlay에 저장.
func _open_backdrop(alpha: float) -> void:
	_close_overlay()
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0, 0, 0, alpha)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_canvas().add_child(_overlay)

## 1920공간으로 작성된 오버레이 창(win)을 692공간에 컨테이너째 스케일·중앙배치.
## 내부 자식 좌표(그리드/탭 등)는 1920공간 그대로 두고 창만 스케일한다(증분1 하단바와 동일 기법).
func _center_win(win: Control, w1080: float, h1080: float) -> void:
	var vis := _vis()
	win.scale = Vector2(S1080, S1080)
	win.position = Vector2((vis.x - w1080 * S1080) / 2.0, (vis.y - h1080 * S1080) / 2.0)

func _make_overlay(title: String) -> VBoxContainer:
	_open_backdrop(0.78)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(1200, 920)
	_overlay.add_child(box)
	_center_win(box, 1200, 920)   # 1920공간 유지 + 692 중앙배치
	var head := HBoxContainer.new()
	var t := Label.new(); t.text = title; t.add_theme_font_size_override("font_size", 40)
	head.add_child(t)
	var close := Button.new(); close.text = "  닫기 ✕  "
	close.pressed.connect(_close_overlay)
	head.add_child(close)
	box.add_child(head)
	return box

# ---------- 도감 (원작 BookPopup — 포팅 카드 docs/ref/porting/BookPopup.md) ----------
# 원작 구성: BookPopup(팝업 본체) + BookTableViewCell(그리드 셀, 세로 3버튼/셀 가로 스크롤)
#   + CaveScene::setBottomElement(팝업 밖 하단 속성 필터) + DragonBookInfoLayer(돋보기 전체화면).
# 레퍼런스: docs/ref/book/{main,드래곤클릭,단계클릭_알,돋보기클릭}.png
# ⚠️ 종전 WorldDragonBookLayer 기반 구현(제목바+box_worldbook)은 클래스 오진이라 폐기 —
#   WorldDragonBookLayer 는 월드별 "도감 미션" 화면이다(worldbook_utakhan/dwarp/elf/raid 버튼).
const DEX_ELEMENTS := ["all", "fire", "aqua", "earth", "wind", "light", "dark", "holy", "chaos", "shadow"]
const DEX_ELE_ICON := {   # 원작 setBottomElement/onClickDragon: item/item_small/ele_*.png
	"all": "item_item_small_ele_all", "fire": "item_item_small_ele_fire", "aqua": "item_item_small_ele_water",
	"earth": "item_item_small_ele_ground", "wind": "item_item_small_ele_wind", "light": "item_item_small_ele_light",
	"dark": "item_item_small_ele_dark", "holy": "item_item_small_ele_holy", "chaos": "item_item_small_ele_chaos",
	"shadow": "item_item_small_ele_shadow"}
const DEX_ORDER := ["egg", "baby", "child", "adult", "aura", "awaken"]   # step-1 → 단계 키 (Book::getStep 1~6)
const DEX_STEP_KR := ["알", "해치", "해츨링", "성체", "오라성체", "각성"]   # CaveDragonBookRevolution_0~5
const DEX_TYPE_KR := {"hp": "체력형", "atk": "공격형", "def": "방어형",   # Dragon_H/A/D/HA/HD/AD
	"ha": "체공형", "hd": "체방형", "ad": "공방형"}

var _dex_element := "all"
var _dex_selected := -1            # 선택된 종 id (원작 this+0x274 dragonNo). -1=없음
var _dex_step_sel := -1            # 우측 패널 선택 단계 박스(원작 this+0x270)
# 원작 CCTableView dequeueCell(셀 재활용) 대응 — 도감 그리드 가상화(보이는 열만 카드 생성).
var _dex_id_list: Array = []
var _dex_sc: ScrollContainer
var _dex_grid_node: Control
var _dex_cards := {}               # 인덱스 i -> 카드(Control). 스크롤에 따라 생성/해제.
var _dex_panel: Control            # 우측 상세 패널(원작 this+0x2d0, 350×430)
var _dex_count_lbl: Label          # "완성/전체" 카운트(원작 this+0x2f8)
var _dex_ele_btns: Array = []      # 하단 속성 버튼 루트(Node2D)
var _dex_ring: Node2D              # scene/cave/attribute_bg 선택 링(선택 버튼 밑으로 이동)

## 원작 CollectionStepResultLayer 1:1: 수집 도감 단계 보상 목록 — 큰 팝업(746×554) + 넓은 보상행(672×101) 리스트 + close.
## 근거: CollectionStepResultLayer.c init CCSize(746,554)(:164) + common/close_btn(:185) + 타이틀 BMFont(:205/232) +
##   컨텐츠 CCSize(panelW-76,448)(:247) + 행 Scale9 CCSize(672,101)(:463) + 배지 Scale9(73,23)(:497) + coin/diamond(:827/858).
## ⚠️ 단계 목록·진행도는 우리 드래곤 속성 데이터로 파생(근거). 각 단계 보상표(coin/diamond/item)=서버 유실(원칙2) →
##   data/collection_rewards.json(사용자/자체 정의) 있을 때만 표시, 없으면 "보상 미정" — 지어내지 않음.
func _open_collection_result() -> void:
	# 🔴 2026-07-30 수정: 종전엔 여기서 _open_backdrop(0.55)로 별도 딤을 깔았는데, 이 창의 X는
	# 자기 layer(76)만 지워서 그 딤이 남아 화면이 잠겼다(사용자 보고). 창 자체 dim 만 쓰고,
	# 도감에서 들어온 창이므로 닫으면 도감으로 복귀한다.
	_close_overlay()
	var vis := _vis()
	# 속성별 수집 집계(파생): total=Data.dragons 속성별, owned=UserDB 보유 고유 def-id 속성별.
	var totals := {}; var owned := {}
	# `Data.dragon_ids()` = 기본 숨김 종(600·700 미구현 더미)을 뺀 목록 — 수집률 분모가
	# 도달 불가능한 종 때문에 영원히 안 채워지지 않게 한다(사용자 확정 2026-07-30).
	for k in Data.dragon_ids():
		var el := str((Data.get_dragon(k) as Dictionary).get("element", ""))
		if el == "": continue
		totals[el] = int(totals.get(el, 0)) + 1
	var seen_ids := {}
	for od in UserDB.dragons():
		var did := int((od as Dictionary).get("id", 0))
		if seen_ids.has(did): continue
		seen_ids[did] = true
		var el := str((Data.get_dragon(did)).get("element", ""))
		if el != "": owned[el] = int(owned.get(el, 0)) + 1
	var elems: Array = _ELEM_KR.keys().filter(func(e): return totals.has(e))
	# 보상표(유실→외부 데이터). 없으면 빈 딕셔너리.
	var rewards: Dictionary = Data.collection_rewards() if Data.has_method("collection_rewards") else {}
	# popup4 패널(우리 692 공간에 맞춰 스케일).
	const BW := 660.0
	const BH := 540.0
	var layer := CanvasLayer.new(); layer.layer = 76; add_child(layer)
	var back := func():
		layer.queue_free()
		_open_dex()
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: back.call()); layer.add_child(dim)
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5)); layer.add_child(win)
	var tbar := NinePatchRect.new(); tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(300, 52); tbar.position = Vector2((BW - 300) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = "수집 도감"
	tl.add_theme_font_size_override("font_size", 26); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; tl.size = tbar.size; tbar.add_child(tl)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 58, 14); xb.pressed.connect(back); win.add_child(xb)
	# 스크롤 컨텐츠(원작 CCSize(panelW-76,448)) — 속성별 보상행(원작 672×101, 우리 폭 맞춤).
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(24, 76); scroll.size = Vector2(BW - 48, BH - 96)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; win.add_child(scroll)
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 8); vb.custom_minimum_size.x = BW - 66; scroll.add_child(vb)
	for el in elems:
		var ownc := int(owned.get(el, 0)); var totc := int(totals.get(el, 0))
		var done := ownc >= totc
		var row := NinePatchRect.new(); row.texture = load("res://assets/converted/ninepatch_ui/9patch_text_box.tres")
		row.patch_margin_left = 14; row.patch_margin_top = 14; row.patch_margin_right = 14; row.patch_margin_bottom = 14
		row.custom_minimum_size = Vector2(BW - 66, 78); vb.add_child(row)
		var nm := Label.new(); nm.text = "%s 속성" % _ELEM_KR.get(el, el)
		nm.add_theme_font_size_override("font_size", 20); nm.add_theme_color_override("font_color", Color(0.25, 0.18, 0.08))
		nm.position = Vector2(18, 10); row.add_child(nm)
		# 진행도 바 + N/M(파생, 근거).
		var pbg := ColorRect.new(); pbg.color = Color(0, 0, 0, 0.18); pbg.position = Vector2(18, 42); pbg.size = Vector2(300, 20); row.add_child(pbg)
		var pfill := ColorRect.new(); pfill.color = (Color(0.3, 0.8, 0.4) if done else Color(0.9, 0.7, 0.25))
		pfill.position = Vector2(18, 42); pfill.size = Vector2(300.0 * (float(ownc) / maxf(1.0, totc)), 20); row.add_child(pfill)
		var pl := Label.new(); pl.text = "%d / %d" % [ownc, totc]
		pl.add_theme_font_size_override("font_size", 15); pl.add_theme_color_override("font_color", Color.WHITE)
		pl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8)); pl.add_theme_constant_override("outline_size", 3)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; pl.position = Vector2(18, 44); pl.size = Vector2(300, 18); row.add_child(pl)
		# 보상 슬롯(원작 coin/diamond/item). 유실 → 외부 데이터 있을때만, 없으면 미정.
		var rw: Dictionary = rewards.get(el, {})
		var rlbl := Label.new()
		if rw.is_empty():
			rlbl.text = "보상 미정(유실)"
			rlbl.add_theme_color_override("font_color", Color(0.6, 0.5, 0.4))
		else:
			rlbl.text = "보상: %s ×%d" % [Data.item_name(str(rw.get("item", ""))), int(rw.get("count", 1))]
			rlbl.add_theme_color_override("font_color", Color(0.85, 0.55, 0.15) if done else Color(0.5, 0.45, 0.4))
		rlbl.add_theme_font_size_override("font_size", 16)
		rlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; rlbl.position = Vector2(BW - 66 - 220, 28); rlbl.size = Vector2(200, 22); row.add_child(rlbl)

const DEX_CELL_W := 120.0            # 원작 cellSizeForTable = CCSize(120, 테이블높이)
const DEX_BTN := Vector2(115, 130)   # BookTableViewCell 버튼 크기
const DEX_ROW_Y := [10.0, 140.0, 270.0]   # 버튼 상단 y(godot) — cocos y중심 335/205/75 의 플립

func _open_dex() -> void:
	_close_overlay()
	# 원작 BookPopup 은 딤이 없다(레퍼런스: 팝업 밖 동굴 벽이 그대로 밝다) — 투명 백드롭으로
	# 클릭만 막는다. 하단 메뉴는 setBottomElement 가 속성 필터로 교체 → 우리는 숨김/복원.
	_open_backdrop(0.0)
	if is_instance_valid(_bottom_bar): _bottom_bar.visible = false
	if is_instance_valid(_left_wall): _left_wall.visible = false
	var vis := _vis()
	# 원작 BookPopup: PopupLayer::setContentSprite(10,10,10,140, "9patch/popup4", cap 130,190,40,58)
	# — 화면 여백 좌/우/상 10pt, 하단 140pt(하단은 setBottomElement 속성 필터 자리).
	var W := vis.x - 20.0
	var H := vis.y - 150.0
	var win := Control.new()
	win.position = Vector2(10, 10)
	win.size = Vector2(W, H)
	_overlay.add_child(win)
	var np := AtlasUI.nine("ninepatch_ui", "9patch_popup4", Vector2(W, H), Rect2(130, 190, 40, 58))
	if np: win.add_child(np)
	# 제목 "도감"(문자열 CaveBook) — font_subtitle ×1.2, (W/2, H-45). 제목바 프레임 없음(원작).
	var title := _book_label("도감", 1.2)
	_book_center(title, Vector2(W * 0.5, 45.0))
	win.add_child(title)
	# 카운트 "완성(step>4) / 목록" — ×0.9 anchor(0,0) (50, H-80).
	_dex_count_lbl = _book_label("", 0.9)
	_dex_count_lbl.position = Vector2(50, 58)
	win.add_child(_dex_count_lbl)
	# 그리드 컨테이너 9patch/scroll_box cap(65,65,6,6) — (W-430)×420, (40,40).
	var gw := W - 430.0
	var gbox := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", Vector2(gw, 420), Rect2(65, 65, 6, 6))
	if gbox:
		gbox.position = Vector2(40, H - 460.0)
		win.add_child(gbox)
	# 테이블(그리드): 컨테이너 내부 (10,5), (gw-20)×410.
	_dex_build_grid(win, Vector2(50, H - 455.0), Vector2(gw - 20.0, 410.0))
	# 우측 상세 패널 350×430 anchor(1,0) (W-30, 40).
	_dex_panel = Control.new()
	_dex_panel.position = Vector2(W - 380.0, H - 470.0)
	_dex_panel.size = Vector2(350, 430)
	win.add_child(_dex_panel)
	# close_btn ×1.5 (W-50, H-50).
	var xs := AtlasUI.spr("common_ui", "common_close_btn", Design.ASSET_SCALE * 1.5)
	xs.position = Vector2(W - 50.0, 50.0)
	win.add_child(xs)
	var xb := Button.new(); xb.flat = true
	xb.size = Vector2(64, 64); xb.position = Vector2(W - 82.0, 18.0)
	xb.pressed.connect(_close_overlay); win.add_child(xb)
	# 수집 보상(CollectionStepResultLayer) 진입 — 원작 BookPopup에는 없는 오프라인 변형 진입점
	# (포팅 카드 §미보유). 카운트 오른쪽 빈 파치먼트에 둔다(제목·패널·close 침범 금지).
	AtlasUI.frame_button(win, "수집 보상", Vector2(180.0, 44.0), Vector2(110, 40), _open_collection_result)
	_dex_build_element_row()
	_dex_refresh_count()
	_dex_reset_panel()   # 원작 초기 상태 = 선택 없음(레퍼런스 main.png 빈 패널)

## 도감 목록. `Data.dragon_ids()` 는 **기본 숨김 종(600·700)을 이미 뺀** 목록이고,
## 여기서 **특수 트리거가 걸린 것만 다시 덧붙인다**(사용자 확정 2026-07-30).
## # ASSUMPTION: 트리거 = **그 종을 얻은 이력**(`UserDB.dex_step > 0`). 600·700 은 플레이어
##   선택권으로만 들어오는 종이라(이름·디자인도 선택된 원본을 따른다) 받기 전에는 도감에
##   존재를 노출하지 않는 것이 자연스럽다. 다른 트리거(퀘스트 플래그 등)로 바꾸려면 이 한 줄만 고친다.
func _dex_ids() -> Array:
	var ids: Array = Data.dragon_ids()
	for hid in Data.dragon_ids_hidden():
		if UserDB.dex_step(int(hid)) > 0:
			ids.append(hid)
	ids.sort()
	var out := []
	for id in ids:
		if _dex_element == "all" or str(Data.get_dragon(id).get("element", "")) == _dex_element:
			out.append(id)
	return out

## 원작 BMFont(font_subtitle 19px) 라벨. scale = 원작 setScale → 포인트 크기 19×4/3×scale.
func _book_label(txt: String, scale: float, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = txt
	_lvup_bm_style(l, int(round(19.0 * Design.ASSET_SCALE * scale)), col, "font_subtitle")
	return l

func _book_center(l: Label, c: Vector2, w := 400.0) -> void:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(w, 40)
	l.position = c - l.size * 0.5

## 카운트(원작 resetDragonsList "%d / %d" = 오라성체 이상 완성 수 / 필터 목록 수).
func _dex_refresh_count() -> void:
	if not is_instance_valid(_dex_count_lbl): return
	var done := 0
	for id in _dex_id_list:
		if UserDB.dex_step(int(id)) > 4:
			done += 1
	_dex_count_lbl.text = "%d / %d" % [done, _dex_id_list.size()]

## 원작 CCTableView 1:1(dequeueCell 셀 재활용): 전 카드를 만들지 않고 보이는 열(+버퍼)만 생성/해제.
## 열 = i/3, 행 = i%3 (가로 스크롤, 셀 = 세로 3버튼).
func _dex_build_grid(win: Control, pos: Vector2, sz: Vector2) -> void:
	_dex_id_list = _dex_ids()
	_dex_cards = {}
	var sc := ScrollContainer.new()
	sc.position = pos
	sc.custom_minimum_size = sz; sc.size = sz
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(sc)
	_dex_sc = sc
	var grid := Control.new()
	var cols: int = int(ceil(_dex_id_list.size() / 3.0))
	grid.custom_minimum_size = Vector2(cols * DEX_CELL_W, sz.y)
	sc.add_child(grid)
	_dex_grid_node = grid
	sc.get_h_scroll_bar().value_changed.connect(func(_v): _dex_update_visible())
	sc.get_h_scroll_bar().modulate.a = 0.0   # 원작 CCTableView 는 스크롤바가 없다(드래그 스크롤)
	_dex_update_visible()

## 보이는 열(+버퍼 2)만 카드 유지: 범위 밖은 queue_free, 범위 내 미생성분만 새로 생성(dequeueCell 대응).
func _dex_update_visible() -> void:
	if not is_instance_valid(_dex_grid_node) or not is_instance_valid(_dex_sc):
		return
	var scroll_x := float(_dex_sc.scroll_horizontal)
	var view_w := _dex_sc.size.x
	var first_col := maxi(0, int(scroll_x / DEX_CELL_W) - 2)
	var last_col := int((scroll_x + view_w) / DEX_CELL_W) + 2
	var to_free: Array = []
	for i in _dex_cards.keys():
		var col: int = i / 3
		if col < first_col or col > last_col:
			to_free.append(i)
	for i in to_free:
		var c = _dex_cards[i]
		if is_instance_valid(c): c.queue_free()
		_dex_cards.erase(i)
	for col in range(first_col, last_col + 1):
		for row in 3:
			var i: int = col * 3 + row
			if i >= _dex_id_list.size() or _dex_cards.has(i):
				continue
			var card := _dex_card(int(_dex_id_list[i]))
			card.position = Vector2(col * DEX_CELL_W + 2.5, DEX_ROW_Y[row])
			_dex_grid_node.add_child(card)
			_dex_cards[i] = card

## 선택 변경 등으로 특정 종의 카드만 다시 그린다(가상화 딕셔너리 유지).
func _dex_refresh_card(id: int) -> void:
	var i := _dex_id_list.find(id)
	if i < 0 or not _dex_cards.has(i):
		return
	var old = _dex_cards[i]
	var p: Vector2 = old.position
	if is_instance_valid(old): old.queue_free()
	var card := _dex_card(id)
	card.position = p
	_dex_grid_node.add_child(card)
	_dex_cards[i] = card

## 원작 BookTableViewCell::updateDragonBtn 1:1 — 버튼 115×130:
##   배경 dragonbg_{select|evolution(step6)|master(step5)|nomal} Scale9
##   → dragon_box 9patch 100×100(상단 -6, anchor 0.5,1) → 도달 최고 단계 box_* 썸네일(안 맞춤)
##   → 전구 5~6개(진행 점등). NEW 뱃지(Book::isNew)는 서버 플래그라 미이식.
func _dex_card(id: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = DEX_BTN; c.size = DEX_BTN
	var step := UserDB.dex_step(id)
	var bgkey := "scene_cave_dragonbg_nomal"
	if id == _dex_selected: bgkey = "scene_cave_dragonbg_select"
	elif step >= 6: bgkey = "scene_cave_dragonbg_evolution"
	elif step == 5: bgkey = "scene_cave_dragonbg_master"
	var bg := AtlasUI.nine("cave_ui", bgkey, DEX_BTN)
	if bg: c.add_child(bg)
	var box := AtlasUI.nine("cave_ui", "scene_cave_dragon_box", Vector2(100, 100))
	if box:
		box.position = Vector2(7.5, 6)
		c.add_child(box)
	# 썸네일: 도달 최고 단계. step0(미등록)은 원작 표현 미상(디컴프 switch 매핑 불명)
	# → ASSUMPTION: 알 프레임 실루엣으로 표시(전종 표시+총계는 카운트 표기로 확실).
	var stage := String(DEX_ORDER[clampi(step, 1, 6) - 1])
	var spr := _dex_stage_sprite_fit(id, stage, 96.0)
	if spr:
		spr.position = Vector2(57.5, 56)
		if step == 0:
			# 미등록 실루엣 — 형태가 보일 정도의 음영(사용자 보정 2026-07-30: 종전 0.1은 너무 진함).
			spr.modulate = Color(0.32, 0.32, 0.35, 1)
		c.add_child(spr)
	_dex_bulbs(c, id, step)
	var b := Button.new(); b.flat = true; b.size = DEX_BTN
	b.pressed.connect(func(): _dex_on_click_dragon(id))
	c.add_child(b)
	return c

## 전구 행(updateDragonBtn 후반): 각성스킬 있는 종=6개/없으면 5개(전체 +8pt 우측).
## 바탕 lightbulb_bg, i<step 점등 — step6(각성)이면 빨강 lightbulb2, 그 외 초록 lightbulb.
func _dex_bulbs(c: Control, id: int, step: int) -> void:
	# 🔴 2026-07-30 정정(사용자 지적: "네시 빼고 전부 원이 5개"): 여기도 `awaken`
	#   (= `box_s01` **13종**)을 보고 있어서 그 13종만 6개였다. 각성 보유 판별은
	#   `evo`(= 각성체 초상 `box_evolution` **137종**)다 — `slots`·`_dex_stage_frame` 과 같은 축.
	var has_awaken := bool(Data.dragon_dex_meta(id).get("evo", false))
	var bsz := AtlasUI.size_pt("cave_ui", "scene_cave_lightbulb_bg")
	var shift := 0.0 if has_awaken else 8.0
	var n := 6 if has_awaken else 5
	for i in n:
		var p := Vector2((bsz.x + 2.0) * i + bsz.x * 0.5 + 8.0 + shift,
			DEX_BTN.y - 11.0 - bsz.y * 0.5)
		var dot := AtlasUI.spr("cave_ui", "scene_cave_lightbulb_bg", Design.ASSET_SCALE)
		dot.position = p
		c.add_child(dot)
		if i < step:
			var on := AtlasUI.spr("cave_ui",
				"scene_cave_lightbulb2" if step >= 6 else "scene_cave_lightbulb", Design.ASSET_SCALE)
			on.position = p
			c.add_child(on)

## 원작 BookPopup::onClickDragon — 선택 종 교체 + 우측 패널 채움(그리드 셀 테두리 갱신 포함).
func _dex_on_click_dragon(id: int) -> void:
	if _dex_selected == id:
		return
	var prev := _dex_selected
	_dex_selected = id
	if prev != -1: _dex_refresh_card(prev)
	_dex_refresh_card(id)
	_dex_fill_panel()

## 우측 패널 초기화(원작 resetDragonsList: 선택 없음 — 빈 단계 박스와 빈 설명 상자만 남는다.
## initWidget 이 만들어 둔 뼈대가 유지되는 상태. 레퍼런스 main.png).
func _dex_reset_panel() -> void:
	_dex_step_sel = -1
	if not is_instance_valid(_dex_panel):
		return
	for ch in _dex_panel.get_children():
		_dex_panel.remove_child(ch)   # queue_free 는 다음 프레임 — 이름 중복 잔존 방지(즉시 분리)
		ch.queue_free()
	_dex_build_strip(-1, 0, 6)
	var tb := AtlasUI.nine("ninepatch_ui", "9patch_text_box", Vector2(340, 125), Rect2(25, 25, 3, 3))
	if tb:
		tb.position = Vector2(5, 305)
		_dex_panel.add_child(tb)

## 우측 패널 채움(원작 onClickDragon 후반 1:1). 패널 좌표계 = 350×430, 원작 cocos y는 플립해 적는다.
func _dex_fill_panel() -> void:
	_dex_step_sel = -1
	if not is_instance_valid(_dex_panel):
		return
	# 🔴 간헐 버그 수정(사용자 보고 2026-07-30): queue_free 만 하면 이전 "subject"/"strip" 노드가
	# 다음 프레임까지 트리에 남아 get_node 가 죽어가는 쪽을 잡는다 → 새 스파인이 그 노드에 붙어
	# 프레임 끝에 함께 삭제(스파인이 안 뜸). 즉시 remove_child 로 분리한다.
	for pch in _dex_panel.get_children():
		_dex_panel.remove_child(pch)
		pch.queue_free()
	var id := _dex_selected
	if id < 0:
		return
	var d: Dictionary = Data.get_dragon(id)
	var step := UserDB.dex_step(id)
	# 단계 칸 수 — **각성이 있는 종만 6칸**(…오라성체·각성), 없으면 5칸까지다(사용자 확정 2026-07-30).
	# 판별 = 각성체 초상 `box_evolution` 보유(`dex_meta.evo` **137종** = `dragons.csv has_e`
	# = 원본 `_e_spine` 135종 포함). ⚠️ 종전엔 `awaken`(= `box_s01` **13종**)을 봐서 거의 모든
	# 종이 5칸으로 굳었고 그 5번째 칸이 각성 그림을 그렸다(`_dex_stage_frame` 정정과 한 쌍).
	var slots := 6 if bool(Data.dragon_dex_meta(id).get("evo", false)) else 5
	# 이름 (175, 425cocos → 5)
	var nm := _book_label(String(d.get("name", "?")), 1.0)
	_book_center(nm, Vector2(175, 8), 340)
	_dex_panel.add_child(nm)
	# 별(StarclassLayer=common/eggclass 나열, 이름 -35) — 알 슬롯 선택 시만 보임(onClickStepBox case0).
	var stars := Node2D.new(); stars.name = "stars"; stars.visible = false
	stars.position = Vector2(175, 40)
	var starn := int(d.get("star", 0))
	var ssz := AtlasUI.size_pt("common_ui", "common_eggclass")
	for i in starn:
		var st := AtlasUI.spr("common_ui", "common_eggclass", Design.ASSET_SCALE)
		st.position = Vector2((i - (starn - 1) * 0.5) * (ssz.x + 2.0), 0)
		stars.add_child(st)
	_dex_panel.add_child(stars)
	# 속성 아이콘(300, 380cocos → 50) ×0.55 + 유형 명찰 recall_del(아이콘 아래).
	var el := str(d.get("element", ""))
	var ei := AtlasUI.spr("item_small_ui", String(DEX_ELE_ICON.get(el, "item_item_small_ele_all")),
		Design.ASSET_SCALE * 0.55)
	ei.position = Vector2(300, 50)
	_dex_panel.add_child(ei)
	var tname := String(DEX_TYPE_KR.get(str(d.get("type", "")), ""))
	if tname != "":
		var fs := int(round(19.0 * Design.ASSET_SCALE * 0.7))
		var tw := maxf(70.0, _lvup_bmfont("font_subtitle").get_string_size(
			tname, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10.0)
		var eih := AtlasUI.size_pt("item_small_ui", String(DEX_ELE_ICON.get(el, "item_item_small_ele_all"))).y * 0.55
		var tag := AtlasUI.nine("ninepatch_ui", "9patch_recall_del", Vector2(tw, 30))
		if tag:
			tag.position = Vector2(300 - tw * 0.5, 50 + eih * 0.5 + 3.0)
			_dex_panel.add_child(tag)
		var tl := _book_label(tname, 0.7)
		_book_center(tl, Vector2(300, 50 + eih * 0.5 + 3.0 + 15.0), 120)
		_dex_panel.add_child(tl)
	# 그림자(175, 215cocos → 215).
	var sh := AtlasUI.spr("common_ui", "common_shadow", Design.ASSET_SCALE)
	sh.name = "shadow"
	sh.position = Vector2(175, 215)
	_dex_panel.add_child(sh)
	# 알/스파인 표시 자리(step 박스 클릭이 갈아끼운다).
	var subject := Node2D.new(); subject.name = "subject"
	subject.position = Vector2(175, 135)   # cocos (w/2, h/2+80)
	_dex_panel.add_child(subject)
	# 단계 스트립(뷰 343×68.5 @ (6,130cocos) — 각성종은 315 + btn_arrow2 표시).
	_dex_build_strip(id, step, slots)
	# 돋보기(common/refresh, (300,215cocos→215)) — step≥1 일 때만(원작 iVar6>0).
	if step >= 1:
		var rf := AtlasUI.spr("common_ui", "common_refresh", Design.ASSET_SCALE)
		rf.position = Vector2(300, 215)
		_dex_panel.add_child(rf)
		var rb := Button.new(); rb.flat = true
		rb.size = Vector2(56, 56); rb.position = Vector2(272, 187)
		rb.pressed.connect(func(): _open_dragon_book_info(_dex_selected))
		_dex_panel.add_child(rb)
	# 설명 상자 9patch/text_box cap(25,25,3,3) 340×125, 중심 (175, 62.5cocos → 367.5).
	var tb := AtlasUI.nine("ninepatch_ui", "9patch_text_box", Vector2(340, 125), Rect2(25, 25, 3, 3))
	if tb:
		tb.position = Vector2(5, 305)
		_dex_panel.add_child(tb)
	var tsc := ScrollContainer.new()
	tsc.position = Vector2(15, 315); tsc.size = Vector2(320, 105)
	tsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dex_panel.add_child(tsc)
	var com := Data.dragon_comment(id)
	var cl := Label.new()
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cl.custom_minimum_size = Vector2(300, 0)
	# 원작 CCLabelBMFontEx setColor(129,67,29) ×0.8. 서체는 **가는 본문체 font_common**(HCR Dotum 17)
	# — subtitle(Noto)로 그리면 원작보다 획이 두껍고 색이 연해 보인다(사용자 보고 2026-07-30).
	_lvup_bm_style(cl, int(round(17.0 * Design.ASSET_SCALE * 0.8)), Color8(129, 67, 29), "font_common")
	if com != "":
		cl.text = com
	else:
		# ⚠ 비트맵 폰트에 없는 문자(—·특수기호)는 피한다. 색은 본문과 동일(연하게 빼지 않는다).
		cl.text = "(도감 설명 데이터 미복원: 서버 유실)"
	tsc.add_child(cl)
	# 초기 표시 = 마지막 도달 단계(원작 onClickDragon 말미 onClickStepBox 호출). step0=알 실루엣.
	_dex_pick_step(maxi(0, mini(step, slots) - 1))

## 단계 스트립(원작 onClickDragon 중반): dragon_bg2+cover2+frame2 박스 6(5)개, 도달 단계만 썸네일.
## id<0 = 선택 없음 스켈레톤(빈 박스 6개, 화살표 없음 — resetDragonsList 상태).
func _dex_build_strip(id: int, step: int, slots: int) -> void:
	var view_w := 315.0 if (slots == 6 and id >= 0) else 343.0
	var clipbox := Control.new()
	clipbox.name = "strip"
	clipbox.position = Vector2(6, 231.5)
	clipbox.size = Vector2(view_w, 68.5)
	clipbox.clip_contents = true
	_dex_panel.add_child(clipbox)
	var inner := Control.new()
	inner.size = Vector2(415, 68.5)
	clipbox.add_child(inner)
	var bsz := AtlasUI.size_pt("cave_ui", "scene_cave_dragon_bg2")
	for i in slots:
		var cx := (bsz.x + 3.0) * i + (bsz.x + 6.0) * 0.5 - 4.0
		var boxroot := Node2D.new()
		boxroot.name = "slot%d" % i
		boxroot.position = Vector2(cx, 34.25)
		inner.add_child(boxroot)
		var bg := AtlasUI.spr("cave_ui", "scene_cave_dragon_bg2", Design.ASSET_SCALE)
		boxroot.add_child(bg)
		if id >= 0:
			# 단계 썸네일 — 원작 스케일(알 0.55/그 외 0.6)을 상한으로 박스 내부에 맞춘다
			# (프레임 크기가 종마다 달라 고정 스케일은 테두리를 벗어난다 — 사용자 보고 2026-07-30).
			# 알은 소형 프레임(egg_small) 우선 — 큰 egg 프레임은 박스를 넘친다.
			# 미해금 단계도 이미지는 보이되 음영 처리(원작 동작 — 사용자 확인 2026-07-30).
			var man := AtlasUI.manifest("portrait_%d" % id)
			var frame := _dex_stage_frame(id, String(DEX_ORDER[i]))
			if i == 0 and man.has("dragon_dragon_%d_egg_small" % id):
				frame = "dragon_dragon_%d_egg_small" % id
			var info: Dictionary = man.get(frame, {})
			var fw := maxf(1.0, float(info.get("w", 72)))
			var fh := maxf(1.0, float(info.get("h", 72)))
			var cap := (0.55 if i == 0 else 0.6) * Design.ASSET_SCALE
			var fit := minf(cap, minf((bsz.x - 8.0) / fw, (bsz.y - 8.0) / fh))
			var th := _atlas_sprite("portrait_%d" % id, frame, man, fit)
			th.position = Vector2(0, -2.0)   # 사용자 보정 2026-07-30: 테두리 대비 아래 쏠림 → 5pt 위로
			if i >= step:
				th.modulate = Color(0.32, 0.32, 0.34, 1)
			boxroot.add_child(th)
		var cover := AtlasUI.spr("cave_ui", "scene_cave_dragon_cover2", Design.ASSET_SCALE)
		boxroot.add_child(cover)
		var fr := AtlasUI.spr("cave_ui", "scene_cave_dragon_frame2", Design.ASSET_SCALE)
		boxroot.add_child(fr)
		var light := AtlasUI.spr("cave_ui", "scene_cave_dragon_bg_light", Design.ASSET_SCALE)
		light.name = "light"
		light.position = Vector2(0, 1)   # 사용자 보정 2026-07-30: 썸네일과 함께 5pt 위로
		light.visible = false
		boxroot.add_child(light)
		if i < step:
			var hb := Button.new(); hb.flat = true
			hb.size = bsz; hb.position = -bsz * 0.5
			var idx := i
			hb.pressed.connect(func(): _dex_pick_step(idx))
			boxroot.add_child(hb)
	# 각성종(6칸)만 노랑 화살표(원작 btn_arrow2, (333,158cocos→272) ×1.2) — 스크롤 힌트 표시물.
	if slots == 6 and id >= 0:
		var ar := AtlasUI.spr("common_ui", "common_btn_arrow2", Design.ASSET_SCALE * 1.2)
		ar.position = Vector2(333, 272)
		_dex_panel.add_child(ar)
		# 클릭하면 스트립을 끝까지 밀어준다(원작은 ScrollViewEx 드래그 — PC 마우스 보조).
		var ab := Button.new(); ab.flat = true
		ab.size = Vector2(40, 40); ab.position = Vector2(313, 252)
		ab.pressed.connect(func():
			var strip := _dex_panel.get_node_or_null("strip")
			if strip and strip.get_child_count() > 0:
				var inn: Control = strip.get_child(0)
				var t := create_tween()
				t.tween_property(inn, "position:x", -(415.0 - view_w), 0.25))
		_dex_panel.add_child(ab)

## 원작 onClickStepBox — 선택 단계 하이라이트(dragon_bg_light) + 표시 대상 교체.
## 알 = 알 프레임(원작 Egg::getImagePath = dragon/dragon_%d/egg.png), 그 외 = 단계 스파인 wait 루프
## ×0.7. 별은 알 슬롯에서만 표시(StarclassLayer on/off). 각성/오라 오라FX는 ⚪미이식.
func _dex_pick_step(idx: int) -> void:
	_dex_step_sel = idx
	var id := _dex_selected
	if id < 0 or not is_instance_valid(_dex_panel):
		return
	var step := UserDB.dex_step(id)
	var strip := _dex_panel.get_node_or_null("strip")
	if strip and strip.get_child_count() > 0:
		var inner: Control = strip.get_child(0)
		for slot in inner.get_children():
			var l = slot.get_node_or_null("light")
			if l: l.visible = String(slot.name) == ("slot%d" % idx)
	var stars := _dex_panel.get_node_or_null("stars")
	if stars: stars.visible = (idx == 0 and step >= 1)
	var subject := _dex_panel.get_node_or_null("subject")
	if subject == null:
		return
	for ch in subject.get_children():
		subject.remove_child(ch)
		ch.queue_free()
	var stage := String(DEX_ORDER[clampi(idx, 0, 5)])
	if idx == 0 or step == 0:
		var man := AtlasUI.manifest("portrait_%d" % id)
		var egg := _atlas_sprite("portrait_%d" % id, _dex_stage_frame(id, "egg"), man, Design.ASSET_SCALE)
		if step == 0:
			egg.modulate = Color(0.32, 0.32, 0.35, 1)   # 형태가 보이는 음영(사용자 보정)
		subject.add_child(egg)
	else:
		var sp := _dex_spawn_spine(id, stage, 0.7)
		# ASSUMPTION: 변환 스파인 씬의 원점은 몸통 부근 — 패널 중단(그림자 위)에 오도록 소폭 보정.
		sp.position = Vector2(0, 15)
		subject.add_child(sp)

## 도감 표시용 스파인. **오라성체는 성체 스파인**이고, 각성만 각성체("e") 스파인이다.
##
## 🔴 2026-07-30 정정(사용자 지적: "오라성체 단계의 스파인 위치에 각성 단계 스파인이 와 있어"):
##   종전엔 `aura` 와 `awaken` 을 **둘 다** "e" 로 보냈다.
## 원작 근거 — `Dragon::getImagePathSpineJson`(Dragon.c:9295~9317):
##     level < 0x19(25)        → `_child_spine`
##     else (각성플래그 & 1)==0 → `_adult_spine`      ← 45+ 여도 각성 안 했으면 성체 그림
##     else                    → `_e_spine`           ← 각성했을 때만
##   초상 경로도 같은 축이다(:8265 `level < 0x2d(45)` → `box_adult` / 각성플래그면 `box_evolution` :8301).
##   ⇒ 오라성체는 **아트가 성체와 같고 오라 이펙트만 다르다**(docs/game_design.md 성장 단계 표).
## 각성체 씬이 없으면 성체로 폴백한다(자작 드래곤 666·777 은 art_id 로 아트를 빌려 쓴다).
func _dex_spawn_spine(id: int, stage: String, scale: float) -> Node2D:
	var suf := stage
	if stage == "aura":
		suf = "adult"
	elif stage == "awaken":
		suf = "e" if ResourceLoader.exists(DRAGON_SCENE % [id, "e"]) else "adult"
	var path := DRAGON_SCENE % [id, suf]
	var holder := Node2D.new()
	holder.scale = Vector2(scale, scale)
	if ResourceLoader.exists(path):
		var inst = (load(path) as PackedScene).instantiate()
		holder.add_child(inst)
		var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		if ap:
			holder.set_meta("ap", ap)
			if ap.has_animation("love"):
				ap.get_animation("love").loop_mode = Animation.LOOP_NONE
			if ap.has_animation("wait"):
				ap.play("wait")
	else:
		# 스파인 씬 미빌드(gitignore) → 초상 박스 폴백(cave 본단과 같은 방침).
		var spr := _dex_stage_sprite_fit(id, stage, 180.0 / maxf(0.1, scale))
		if spr:
			spr.position = Vector2(0, -60)
			holder.add_child(spr)
	return holder

## 프레임을 box×box pt 안에 맞춰(min fit) 그린 스프라이트. box=0 이면 null 반환용 프리체크.
func _dex_stage_sprite_fit(id: int, stage: String, box: float) -> Sprite2D:
	if box <= 0.0:
		return null
	var dir := "portrait_%d" % id
	var man := AtlasUI.manifest(dir)
	var frame := _dex_stage_frame(id, stage)
	var info: Dictionary = man.get(frame, {})
	var w := maxf(1.0, float(info.get("w", 72)))
	var h := maxf(1.0, float(info.get("h", 72)))
	return _atlas_sprite(dir, frame, man, minf(box / w, box / h))

## 하단 속성 필터(원작 CaveScene::setBottomElement 1:1) — 팝업 밖 화면 하단 y=70(cocos).
## element_bg 원판 ×1.3, x중심=(폭×1.2+10)×i+90 · 속성 아이콘 ×0.64(+2pt 위) ·
## 선택 링 scene/cave/attribute_bg ×0.86 은 선택 버튼 밑(z-1)으로 이동(onClickElement).
func _dex_build_element_row() -> void:
	_dex_ele_btns = []
	_dex_ring = null
	var vis := _vis()
	var bgw := AtlasUI.size_pt("common_ui", "common_element_bg").x
	for i in DEX_ELEMENTS.size():
		var el := String(DEX_ELEMENTS[i])
		var root := Node2D.new()
		# 원작 x=(폭×1.2+10)×i+90. PC 화면(1230pt)이 원작 기기보다 넓어 좌측으로 쏠려 보인다
		# → 시작 오프셋 +100(사용자 보정 2026-07-30).
		root.position = Vector2((bgw * 1.2 + 10.0) * i + 190.0, vis.y - 70.0)
		_overlay.add_child(root)
		var bg := AtlasUI.spr("common_ui", "common_element_bg", Design.ASSET_SCALE * 1.3)
		root.add_child(bg)
		var ic := AtlasUI.spr("item_small_ui", String(DEX_ELE_ICON[el]),
			Design.ASSET_SCALE * 0.64 * 1.3)
		ic.position = Vector2(0, -2.6)
		root.add_child(ic)
		var hw := bgw * 1.3
		var hit := Button.new(); hit.flat = true
		hit.size = Vector2(hw, hw); hit.position = Vector2(-hw * 0.5, -hw * 0.5)
		hit.pressed.connect(func(): _dex_on_click_element(el, root))
		root.add_child(hit)
		_dex_ele_btns.append(root)
		if el == _dex_element:
			_dex_attach_ring(root)

func _dex_attach_ring(root: Node2D) -> void:
	if is_instance_valid(_dex_ring):
		_dex_ring.queue_free()
	_dex_ring = Node2D.new()
	_dex_ring.z_index = -1
	var s := AtlasUI.spr("cave_ui", "scene_cave_attribute_bg", Design.ASSET_SCALE * 0.86 * 1.3)
	_dex_ring.add_child(s)
	root.add_child(_dex_ring)

## 원작 CaveScene::onClickElement + BookPopup::resetDragonsList — 필터 교체·선택 해제·그리드 리로드.
func _dex_on_click_element(el: String, root: Node2D) -> void:
	if _dex_element == el:
		return
	_dex_element = el
	_dex_attach_ring(root)
	_dex_selected = -1
	_dex_id_list = _dex_ids()
	for i in _dex_cards.keys():
		var c = _dex_cards[i]
		if is_instance_valid(c): c.queue_free()
	_dex_cards = {}
	if is_instance_valid(_dex_grid_node) and is_instance_valid(_dex_sc):
		var cols: int = int(ceil(_dex_id_list.size() / 3.0))
		_dex_grid_node.custom_minimum_size = Vector2(cols * DEX_CELL_W, _dex_sc.size.y)
		_dex_sc.scroll_horizontal = 0
	_dex_update_visible()
	_dex_refresh_count()
	_dex_reset_panel()

## 원작 DragonBookInfoLayer 1:1(돋보기 전체화면): 동굴 테마 배경+벽 가장자리, 받침대 위 알/스파인,
## 하단 box3+box2 단계 박스(알~각성, 미달=검정 실루엣+잠금). 근거: DragonBookInfoLayer.c
## initWidget(테마 배경/벽/close) + initValue(box3×1.1+box2×1.1+CaveDragonBookRevolution_%d, y=60,
## 간격 (박스폭+40)×(i-2)) + onClickDragonBox(받침대 ×1.1·그림자 ×1.75·알 ×1.5/스파인 wait ×1.1).
func _open_dragon_book_info(id: int) -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 45; add_child(layer)
	var ui := Control.new(); ui.size = vis; layer.add_child(ui)
	# 배경 = 현재 동굴 테마(원작 Theme::getImagePath = getThemeSelected).
	var bgt := TextureRect.new()
	bgt.texture = load(BG % (UserDB.get_skin("cave_skin") + 1))
	bgt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bgt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bgt.size = vis
	ui.add_child(bgt)
	# 벽 — 원작: bottom(-2) / left(좌측끝-110) / right(우측끝+100): 가장자리만 걸치게.
	var wman := AtlasUI.manifest("wall_ui")
	var wn := _wall_number_for_theme()
	var ws := 692.0 / 519.0
	var wroot := Node2D.new(); ui.add_child(wroot)
	var lw_i: Dictionary = wman.get("scene_cave_wall_%d_wall_left" % wn, {})
	var lw := _atlas_sprite("wall_ui", "scene_cave_wall_%d_wall_left" % wn, wman, ws)
	lw.position = Vector2(-110.0 + float(lw_i.get("w", 0)) * ws * 0.5, vis.y * 0.5 - 2.0)
	wroot.add_child(lw)
	var rw_i: Dictionary = wman.get("scene_cave_wall_%d_wall_right" % wn, {})
	var rw := _atlas_sprite("wall_ui", "scene_cave_wall_%d_wall_right" % wn, wman, ws)
	rw.position = Vector2(vis.x + 100.0 - float(rw_i.get("w", 0)) * ws * 0.5, vis.y * 0.5 - 2.0)
	wroot.add_child(rw)
	var bw_i: Dictionary = wman.get("scene_cave_wall_%d_wall_bottom" % wn, {})
	var bw := _atlas_sprite("wall_ui", "scene_cave_wall_%d_wall_bottom" % wn, wman, ws)
	bw.position = Vector2(vis.x * 0.5, vis.y + 2.0 - float(bw_i.get("h", 0)) * ws * 0.5)
	wroot.add_child(bw)
	# 받침대(현재 stand 스킨, ×1.1, anchor 0.5,0 — 바닥이 화면중앙+220cocos 아래).
	var si: int = UserDB.get_skin("stand_skin") % STAND_COUNT
	var skey := "stand_stand%d" % (si + 1)
	var sinfo: Dictionary = _stand_manifest.get(skey, {})
	var stand := _atlas_sprite("stand_ui", skey, _stand_manifest, Design.ASSET_SCALE * 1.1)
	stand.position = Vector2(vis.x * 0.5,
		vis.y * 0.5 + 220.0 - float(sinfo.get("h", 0)) * Design.ASSET_SCALE * 1.1 * 0.5)
	ui.add_child(stand)
	# 그림자 ×1.75 (중앙+65cocos 아래).
	var sh := AtlasUI.spr("common_ui", "common_shadow", Design.ASSET_SCALE * 1.75)
	sh.position = Vector2(vis.x * 0.5, vis.y * 0.5 + 65.0)
	ui.add_child(sh)
	# 표시 대상(알/스파인) — 단계 박스가 갈아끼운다.
	var subject := Node2D.new(); subject.name = "subject"
	# 스파인 발이 받침대 윗면에 오도록 — +100 은 단상보다 아래였다(사용자 보정 2026-07-30 위로 조정).
	subject.position = Vector2(vis.x * 0.5, vis.y * 0.5 + 15.0)   # ASSUMPTION: F5 검수로 미세조정
	ui.add_child(subject)
	# 클릭 = 원작 onClickDragon: 알=댄스 연출 / 드래곤=love 모션+effect_dragon_love.
	var tap := Button.new(); tap.flat = true
	tap.size = Vector2(360, 360)
	tap.position = Vector2(vis.x * 0.5 - 180.0, vis.y * 0.5 - 220.0)
	tap.pressed.connect(func(): _dbi_on_tap(subject))
	ui.add_child(tap)
	# 하단 단계 박스.
	var step := UserDB.dex_step(id)
	# 단계 칸 수 — **각성이 있는 종만 6칸**(…오라성체·각성), 없으면 5칸까지다(사용자 확정 2026-07-30).
	# 판별 = 각성체 초상 `box_evolution` 보유(`dex_meta.evo` **137종** = `dragons.csv has_e`
	# = 원본 `_e_spine` 135종 포함). ⚠️ 종전엔 `awaken`(= `box_s01` **13종**)을 봐서 거의 모든
	# 종이 5칸으로 굳었고 그 5번째 칸이 각성 그림을 그렸다(`_dex_stage_frame` 정정과 한 쌍).
	var slots := 6 if bool(Data.dragon_dex_meta(id).get("evo", false)) else 5
	var b3 := AtlasUI.size_pt("common_ui", "common_box3") * 1.1
	for i in slots:
		var cx := vis.x * 0.5 + (b3.x + 40.0) * (i - 2)
		var cy := vis.y - 60.0
		var broot := Node2D.new()
		broot.position = Vector2(cx, cy)
		ui.add_child(broot)
		broot.add_child(AtlasUI.spr("common_ui", "common_box3", Design.ASSET_SCALE * 1.1))
		broot.add_child(AtlasUI.spr("common_ui", "common_box2", Design.ASSET_SCALE * 1.1))
		var th := _dex_stage_sprite_fit(id, String(DEX_ORDER[i]), b3.x - 14.0)
		if th:
			if i >= step:
				th.modulate = Color(0, 0, 0, 1)   # 원작 setColor(BLACK) 실루엣
			broot.add_child(th)
		var lb := _book_label(String(DEX_STEP_KR[i]), 0.6)
		_book_center(lb, Vector2(0, b3.y * 0.5), 120)
		broot.add_child(lb)
		if i < step:
			var hb := Button.new(); hb.flat = true
			hb.size = b3; hb.position = -b3 * 0.5
			var idx := i
			hb.pressed.connect(func(): _dbi_show(ui, id, idx))
			broot.add_child(hb)
	# close(우상단 -50,-50 ×1.05).
	var xs := AtlasUI.spr("common_ui", "common_close_btn", Design.ASSET_SCALE * 1.05)
	xs.position = Vector2(vis.x - 50.0, 50.0)
	ui.add_child(xs)
	var xb := Button.new(); xb.flat = true
	xb.size = Vector2(64, 64); xb.position = Vector2(vis.x - 82.0, 18.0)
	xb.pressed.connect(func(): layer.queue_free())
	ui.add_child(xb)
	# 초기 표시 = 마지막 도달 단계(원작 initValue).
	_dbi_show(ui, id, maxi(0, mini(step, slots) - 1))

## 전체화면 표시 대상 교체(원작 onClickDragonBox): 알=egg 프레임 ×1.5 / 그 외=스파인 wait ×1.1.
func _dbi_show(ui: Control, id: int, idx: int) -> void:
	var subject: Node2D = ui.get_node_or_null("subject")
	if subject == null:
		return
	for ch in subject.get_children():
		subject.remove_child(ch)
		ch.queue_free()
	subject.set_meta("is_egg", idx == 0)
	if idx == 0:
		var man := AtlasUI.manifest("portrait_%d" % id)
		var egg := _atlas_sprite("portrait_%d" % id, _dex_stage_frame(id, "egg"), man,
			Design.ASSET_SCALE * 1.5)
		egg.position = Vector2(0, -80)
		subject.add_child(egg)
	else:
		subject.add_child(_dex_spawn_spine(id, String(DEX_ORDER[idx]), 1.1))

## 원작 DragonBookInfoLayer::onClickDragon — 알: 스케일/스큐 댄스(디컴프 타임라인 근사),
## 드래곤: 스파인 "love" 1회 + effect_dragon_love (보이스는 ⚪미이식).
func _dbi_on_tap(subject: Node2D) -> void:
	if subject.get_child_count() == 0:
		return
	if bool(subject.get_meta("is_egg", false)):
		var egg: Node2D = subject.get_child(0)
		var base: Vector2 = egg.scale
		var t := create_tween()
		t.tween_property(egg, "scale", base * 1.15, 0.2).set_ease(Tween.EASE_OUT)
		for sk in [-0.05, 0.04, -0.03, 0.01, 0.0]:
			t.tween_property(egg, "skew", float(sk), 0.05)
		t.tween_property(egg, "position:y", egg.position.y - 40.0, 0.12).set_ease(Tween.EASE_OUT)
		t.tween_property(egg, "position:y", egg.position.y, 0.15).set_ease(Tween.EASE_IN)
		t.tween_property(egg, "scale", base, 0.15)
	else:
		var holder: Node2D = subject.get_child(0)
		var ap: AnimationPlayer = holder.get_meta("ap") if holder.has_meta("ap") else null
		if ap and ap.has_animation("love"):
			Bgm.sfx("effect_dragon_love")
			ap.play("love")
			if not ap.animation_finished.is_connected(_on_dragon_anim_finished):
				var cb := func(anim: StringName):
					if anim != "wait" and is_instance_valid(ap) and ap.has_animation("wait"):
						ap.play("wait")
				ap.animation_finished.connect(cb)


func _dex_stage_frame(id: int, stage: String) -> String:
	match stage:
		"egg": return "dragon_dragon_%d_egg" % id
		"baby": return "dragon_dragon_%d_box_baby" % id
		"child": return "dragon_dragon_%d_box_child" % id
		"adult": return "dragon_dragon_%d_box_adult" % id
		"aura":
			# 🔴 2026-07-30 정정(사용자 지적): 여기서 `box_evolution`(=**각성체 초상**)을 쓰고 있어
			#   각성이 있는 종은 오라성체 칸에 각성 그림이 떴다.
			#   오라성체는 **아트가 성체와 같다** — 다른 것은 오라 이펙트뿐이다
			#   (`Growth.AURA_ADULT_LEVEL`, docs/game_design.md 성장 단계 표).
			return "dragon_dragon_%d_box_adult" % id
		"awaken":
			# 각성체 초상 = `box_evolution`. 실측으로 네 신호가 전부 일치한다:
			#   `box_evolution` 보유 **137**종 = `dragons.csv has_e=Y` 137종(+600/700 은 초상 없음)
			#   ⊇ 원본 각성체 스파인 `dragon_<id>_e_spine` **135**종.
			# ⚠️ 종전엔 `box_s01` 을 각성으로 봤는데 그건 **13종만** 가진 별개 프레임이다
			#   (그래서 슬롯이 사실상 항상 5칸이었다).
			var man := AtlasUI.manifest("portrait_%d" % id)
			var ev := "dragon_dragon_%d_box_evolution" % id
			return ev if man.has(ev) else ("dragon_dragon_%d_box_adult" % id)
	return "dragon_dragon_%d_box_adult" % id

# ---------- 인벤토리 (참고: docs/Ref/Cave_inventory.jpg) ----------
const INV_TABS := [
	{"id": "food", "icon": "scene_cave_tap_button_food", "label": "scene_cave_tap_food_KR"},
	{"id": "gear", "icon": "scene_cave_tap_button_item", "label": "scene_cave_tap_item_KR"},
	{"id": "gem", "icon": "scene_cave_tap_button_gem", "label": "scene_cave_tap_gem_KR"},
	{"id": "egg", "icon": "scene_cave_tap_button_egg", "label": "scene_cave_tap_egg_KR"},
	{"id": "skill", "icon": "scene_cave_tap_button_skill", "label": "scene_cave_tap_skill_KR"},
	{"id": "doc", "icon": "scene_cave_tap_button_doc", "label": "scene_cave_tap_doc_KR"},
	{"id": "mtr", "icon": "scene_cave_tap_button_mtr", "label": "scene_cave_tap_mtr_KR"},
	{"id": "etc", "icon": "scene_cave_tap_button_etc", "label": "scene_cave_tap_etc_KR"},
]
# 원작 가방 그리드는 **7열 × 3행**이다(docs/ref/orig_image/cave/inven/Cave_inventory.jpg 실측).
# 6열이었던 것을 7열로 맞추고 칸 폭을 그만큼 줄인다(168×6/7 = 144).
const INV_SLOT_W := 144
const INV_SLOT_H := 150
const INV_COLS := 7

var _inv_tab := "etc"
var _inv_selected := ""
var _item_manifests: Dictionary = {}
var _inv_detail_box: Control
var _inv_grid_box: Control

func _open_inventory() -> void:
	_open_backdrop(0.55)
	# 원작 BagPopup: popup4 + pop_title_bg + close_btn. 근거: BagPopup.c setContentSprite(9patch/popup4,Rect130,190,40,58).
	# PC 스케일 적용(NinePatch 스트레치, PC타깃). ⚠️buildup 크래프트(buildup_spine)=서버구동(유실)→미반영.
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(1780, 930)
	_overlay.add_child(win)
	_center_win(win, 1780, 930)
	var tbar := NinePatchRect.new(); tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(560, 62); tbar.position = Vector2((1780 - 560) * 0.5, 12); win.add_child(tbar)
	var title := Label.new()
	title.text = "가방"
	title.size = tbar.size
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color.WHITE)
	tbar.add_child(title)

	var cap := Label.new()
	# 가방 최대치=UserDB pmeta bag_max(기본 240, BagExpandLayer로 확장).
	cap.text = "%d / %d" % [_inventory_total_count(), _bag_max()]
	cap.position = Vector2(940, 24)
	cap.add_theme_font_size_override("font_size", 24)
	cap.add_theme_color_override("font_color", Color(0.16, 0.12, 0.08))
	win.add_child(cap)
	# 원작 BagExpandLayer 진입(가방 확장 +).
	var exb := Button.new(); exb.text = "확장 +"; exb.size = Vector2(90, 40); exb.position = Vector2(1140, 20)
	exb.pressed.connect(func(): _close_overlay(); _open_bag_expand()); win.add_child(exb)

	var close := TextureButton.new()  # 원작 common/close_btn
	close.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	close.scale = Vector2(1.6, 1.6); close.position = Vector2(1700, 20)
	close.pressed.connect(_close_overlay)
	win.add_child(close)

	_inv_grid_box = Control.new()
	_inv_grid_box.position = Vector2(46, 88)
	_inv_grid_box.size = Vector2(1060, 650)
	win.add_child(_inv_grid_box)

	_inv_detail_box = Control.new()
	_inv_detail_box.position = Vector2(1160, 90)
	_inv_detail_box.size = Vector2(560, 650)
	win.add_child(_inv_detail_box)

	_inventory_refresh_grid()
	_inventory_refresh_detail()
	_inventory_tabs(win)

func _inventory_total_count() -> int:
	var total := 0
	for amount in UserDB.inventory().values():
		total += int(amount)
	return total

func _inventory_refresh_grid() -> void:
	if _inv_grid_box == null:
		return
	for ch in _inv_grid_box.get_children():
		ch.queue_free()
	var items := _inventory_items_for_tab(_inv_tab)
	if (_inv_selected == "" or not _inventory_has_item(_inv_selected)) and not items.is_empty():
		_inv_selected = String(items[0])

	var back := _panel(Color(0.47, 0.39, 0.28, 0.94))
	back.position = Vector2(0, 0)
	back.size = Vector2(1050, 560)
	_inv_grid_box.add_child(back)

	if items.is_empty():
		var empty := Label.new()
		empty.text = "비어 있음"
		empty.position = Vector2(0, 220)
		empty.size = Vector2(1050, 40)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 30)
		empty.add_theme_color_override("font_color", Color(0.95, 0.89, 0.76))
		_inv_grid_box.add_child(empty)
		return

	for i in items.size():
		var key := String(items[i])
		var cell := _inventory_cell(key)
		cell.position = Vector2(18 + (i % INV_COLS) * INV_SLOT_W, 18 + (i / INV_COLS) * INV_SLOT_H)
		_inv_grid_box.add_child(cell)

func _inventory_cell(key: String) -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(INV_SLOT_W, INV_SLOT_H)

	# 🟠 2026-07-26 정정: 칸 배경이 자작 `_panel(ColorRect)` 이었다.
	#   원작 가방(docs/ref/orig_image/cave/inven/Cave_inventory.jpg)의 칸은 **어두운 라운드 슬롯**이다 —
	#   레퍼런스 슬롯 내부 픽셀 실측 RGB(58,56,57). 후보 9patch를 뽑아 비교한 결과
	#   `9patch/train_box4`(어두운 라운드)가 일치하고, `bt_itembox_off`는 크림색이라 맞지 않았다.
	#   선택 칸은 `9patch/bt_itembox_on`(노란 하이라이트, 🟠 미사용이던 원본).
	var frame := NinePatchRect.new()
	frame.texture = load("res://assets/converted/ninepatch_ui/%s.tres"
		% ("9patch_bt_itembox_on" if key == _inv_selected else "9patch_train_box4"))
	frame.patch_margin_left = 22; frame.patch_margin_right = 22
	frame.patch_margin_top = 16; frame.patch_margin_bottom = 16
	frame.position = Vector2(4, 4)
	frame.size = Vector2(INV_SLOT_W - 18, 128)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(frame)

	var icon := _inventory_item_icon(key, 84.0)
	if icon:
		icon.position = Vector2((INV_SLOT_W - 18) * 0.5 + 4, 58)
		cell.add_child(icon)

	_inventory_master_badge(cell, key)

	var amount := Label.new()
	amount.text = "X %d" % int(UserDB.inventory().get(key, 0))
	amount.position = Vector2(10, 100)
	amount.size = Vector2(INV_SLOT_W - 30, 28)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.add_theme_font_size_override("font_size", 22)
	amount.add_theme_color_override("font_color", Color.WHITE)
	amount.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	amount.add_theme_constant_override("shadow_offset_x", 2)
	amount.add_theme_constant_override("shadow_offset_y", 2)
	cell.add_child(amount)

	var b := Button.new()
	b.flat = true
	b.size = Vector2(158, 136)
	b.pressed.connect(func(): _inventory_select(key))
	cell.add_child(b)
	return cell

## 가방 알 칸 우상단의 노란 `M` 배지.
##   의미 = **같은 종을 오라성체까지 키운 전적이 있어 도감에 등록된 알**(사용자 확인, lost_text_sheet.md §3).
##   알에만 붙고, `M` 외의 글자는 없다.
## 원본 프레임이 아니라 **텍스트**다 — 3종 조회로 확인했다:
##   `asset_index.py --grep master|_m.|rank_m` → 배지 프레임 없음(dragon_frame_master 등은 전투/랭킹용)
##   `audit_scene.py BagPopup` 리터럴 프레임 13종에도 없음
##   레퍼런스 확대(docs/ref/orig_image/cave/inven/Cave_inventory.jpg 850px 기준, 크롭 x150-230/y60-110)
##     → 판때기 없이 **검은 외곽선 두른 굵은 노란 글자** 한 자
## 배치 실측(같은 크롭): 슬롯 우상단 안쪽 여백 ≈ 3px, 글자 높이 ≈ 11px (슬롯폭 145 기준 0.076).
##   우리 칸 폭은 126이라 비례상 9.6px지만, 이 화면은 수량 라벨도 레퍼런스의 약 1.8배로 그리고 있어
##   같은 배율(font_size 24)로 맞춘다. # ASSUMPTION: 우리 가방 전체 배율에 종속(원작 폰트 크기 미상)
func _inventory_master_badge(cell: Control, key: String) -> void:
	var item := _inventory_item_def(key)
	if String(item.get("category", "")) != "egg":
		return
	var did := int(item.get("dragon_id", 0))     # 속성알(랜덤)은 dragon_id 가 없다 → 배지 대상 아님
	if did <= 0 or not UserDB.dex_master(did):
		return
	var m := Label.new()
	m.text = "M"
	m.size = Vector2(INV_SLOT_W - 18 - 12, 30)
	m.position = Vector2(4 + 6, 4 + 3)
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	m.add_theme_font_size_override("font_size", 24)
	m.add_theme_color_override("font_color", Color8(245, 222, 16))      # 레퍼런스 글자 최빈색 실측(≈245,222,16)
	m.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.0))
	m.add_theme_constant_override("outline_size", 6)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(m)

func _inventory_refresh_detail() -> void:
	if _inv_detail_box == null:
		return
	for ch in _inv_detail_box.get_children():
		ch.queue_free()
	if _inv_selected == "" or not _inventory_has_item(_inv_selected):
		var none := Label.new()
		none.text = "아이템 없음"
		none.position = Vector2(0, 220)
		none.size = Vector2(560, 40)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.add_theme_font_size_override("font_size", 28)
		none.add_theme_color_override("font_color", Color(0.24, 0.16, 0.08))
		_inv_detail_box.add_child(none)
		return

	var item := _inventory_item_def(_inv_selected)
	var name := Label.new()
	name.text = _inventory_item_name(_inv_selected)
	name.position = Vector2(0, 0)
	name.size = Vector2(560, 44)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.add_theme_font_size_override("font_size", 30)
	name.add_theme_color_override("font_color", Color(0.19, 0.11, 0.04))
	_inv_detail_box.add_child(name)

	var icon := _inventory_item_icon(_inv_selected, 210.0)
	if icon:
		icon.position = Vector2(280, 170)
		_inv_detail_box.add_child(icon)

	var owned := _inventory_badge("보유", "X %d" % int(UserDB.inventory().get(_inv_selected, 0)))
	owned.position = Vector2(174, 300)
	_inv_detail_box.add_child(owned)

	# ── 원작 가방 상세(docs/ref/orig_image/cave/inven/Cave_inventory.jpg): 이름 아래에
	#    ① 원형 속성 아이콘 + 그 밑 유형 라벨,  ② 금색 ★ 등급
	#    원본 프레임: `common/element_bg`(원형 판) + `item/item_small/ele_*`(속성) + `common/eggclass`(별)
	#    (`asset_index.py --grep eggclass` → 🟠 미사용이었다)
	var cman3 := _man_common()
	# items.json 은 element/subcategory 가 명시적 null 인 항목이 있다 → String(null) 방지.
	var ev = item.get("element")
	var elem: String = String(ev) if typeof(ev) == TYPE_STRING else ""
	if elem != "":
		var ebg2 := _atlas_sprite("common_ui", "common_element_bg", cman3, 0.62)
		if ebg2: ebg2.position = Vector2(70, 300); _inv_detail_box.add_child(ebg2)
		var eic := _atlas_sprite("item_small", "item_item_small_ele_%s" % elem,
			_item_manifest("item_small"), 0.62)
		if eic: eic.position = Vector2(70, 300); _inv_detail_box.add_child(eic)
	var sv = item.get("subcategory")
	var tkind: String = String(sv) if typeof(sv) == TYPE_STRING else ""
	if tkind != "":
		var tp := Label.new(); tp.text = String(_SUBCAT_KR.get(tkind, tkind))   # 영문 코드 그대로 찍지 않는다
		tp.add_theme_font_size_override("font_size", 18)
		tp.add_theme_color_override("font_color", Color(0.31, 0.22, 0.12))
		tp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tp.size = Vector2(120, 24); tp.position = Vector2(10, 330)
		_inv_detail_box.add_child(tp)
	# ★ 등급 — data 의 tier(1~3)가 있으면 그만큼, 없으면 표시하지 않는다(지어내지 않음).
	var tier := int(item.get("tier", 0))
	for si in tier:
		var star := _atlas_sprite("common_ui", "common_eggclass", cman3, 0.9)
		if star:
			star.position = Vector2(170 + si * 26, 300)
			_inv_detail_box.add_child(star)
	# ── 상세 텍스트 — 원작 `BagPopup::resetString`(BagPopup.c:11254) 그대로의 순서:
	#    [분류·효과 줄들] → [아이템 설명(`Item::getComment()`)].
	#    원작은 이 문자열을 **CCScrollView(높이 105)** 안 라벨에 넣어 길면 스크롤시킨다
	#    (BagPopup.c:11360 `CCScrollView::getContainer` + `setContentSize`) → 우리도 스크롤 박스로.
	#    ⚠️ 아래 '선택' 버튼이 y=520 이라 라벨을 그냥 늘리면 겹친다 — 스크롤이 원작 해법이다.
	var dscroll := ScrollContainer.new()
	dscroll.position = Vector2(40, 352)
	dscroll.size = Vector2(480, 158)      # 아래 '선택/사용' 버튼(y=520) 바로 위까지
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inv_detail_box.add_child(dscroll)
	var dbox := VBoxContainer.new()
	dbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dbox.add_theme_constant_override("separation", 8)
	dscroll.add_child(dbox)
	var desc := Label.new()
	desc.text = _inventory_item_desc(_inv_selected, item)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.custom_minimum_size = Vector2(462, 0)
	desc.add_theme_font_size_override("font_size", 22)
	desc.add_theme_color_override("font_color", Color(0.31, 0.22, 0.12))
	dbox.add_child(desc)
	# 연구소에서 강화해 둔 알이 있으면 등급별 개수를 적는다(원작은 알 개체마다 grade 가 붙어
	# 셀에 배지가 보였다 — 우리 알은 스택이라 곁 테이블을 문장으로 보여 준다, EggUpgrade 참조).
	if String(item.get("category", "")) == "egg":
		var ecnt := UserDB.egg_grade_counts(_inv_selected)
		if not ecnt.is_empty():
			var parts: PackedStringArray = []
			var gs: Array = ecnt.keys(); gs.sort()
			for g in gs:
				parts.append("+%d강 %d개" % [int(g), int(ecnt[g])])
			var gl := Label.new()
			gl.text = "강화: %s  (부화 시 높은 등급부터 사용)" % ", ".join(parts)
			gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			gl.custom_minimum_size = Vector2(462, 0)
			gl.add_theme_font_size_override("font_size", 20)
			gl.add_theme_color_override("font_color", Color(0.72, 0.45, 0.10))
			dbox.add_child(gl)
	# 원작 아이템 설명문(`Item::getComment()` = 서버 info_item.comment). 우리 출처는
	# data/items.json `desc` — docs/input/items/items.csv `설명` 열(사용자 복원)에서 온다.
	# 원작은 comment 를 한 단계 작은 크기로 붙인다(ItemDetailLayer 도 240자 초과 시 0.8배).
	var comment := String(item.get("desc", ""))
	if comment != "":
		var cl := Label.new()
		cl.text = comment
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cl.custom_minimum_size = Vector2(462, 0)
		cl.add_theme_font_size_override("font_size", 19)
		cl.add_theme_color_override("font_color", Color(0.42, 0.31, 0.18))
		dbox.add_child(cl)

	# 에자녹 스크롤 = "사용" → 스킬 아이템 획득(대상 드래곤을 고르지 않는다).
	# 스킬 아이템 = "사용" → **현재 선택 중인 드래곤**이 습득. 상세 = docs/ref/porting/SkillScroll.md
	var is_scroll := Loadout.is_skill_scroll(String(item.get("subcategory", "")))
	var is_skill_item := String(item.get("category", "")) == "skill"
	# ⚠️ `offline` 이 impl 이 아닌 음식은 '사용' 흐름을 태우지 않는다. 특히 `dummy`(원작에도
	#   사용처가 없던 아이템 — 에너지 드링크 등)가 category=food 라서 `_use_food` 로 흘러
	#   먹이 EXP 를 주고 있었다(2026-07-29 수정).
	var is_food := String(item.get("category", "")) == "food" \
		and String(item.get("offline", "")) == "impl"
	# 🔴버그수정(2026-07-27): 축복 4종(`consumable/blessing`)처럼 **효과는 이미 구현됐는데
	#   가방에서 도달할 수 없던** 소모품이 10종 있었다(전부 items.json offline="impl").
	#   위 3분기(알/스크롤/음식)에 안 걸리면 전부 `_inventory_select`(하이라이트)로 떨어져
	#   버튼을 눌러도 아무 일도 없었다. → `_consumable_action` 라우터로 배선한다.
	var use_kind := _consumable_action(_inv_selected, item)
	var is_gear := String(item.get("category", "")) in ["gem", "equipment"]
	# 원작: 부화는 **인벤토리 '알' 탭에서 알을 골라 부화**시킨다(둥지 상단 버튼이 아니다).
	# ⚠️ 원작 부화 메커니즘은 현 breeding 씬(랜덤 부화/조합)과 다르다 — 재구현은 별도 과제.
	var is_egg := String(item.get("category", "")) == "egg"
	# 뽑기 알(의문의 알·빛문알·속성알)은 **부화가 아니라 개봉**이다 — 위키 item.pdf §5.
	# 개봉하면 정해진 풀에서 드래곤 알이 하나 무작위로 나온다(EggGacha). 규칙은 logic 층에.
	var is_gacha_egg := is_egg and EggGacha.is_gacha_egg(item)
	# 제련(원작 `BagPopup::onClickConfirm` case 6 → `ItemSmeltPopup`) — 하위 티어 정령석·스톤하트.
	# 원작도 **확인 버튼 자체가 제련 창을 연다**(별도 버튼이 아니다).
	var is_smelt := ItemSmelt.can_smelt(_inv_selected, Data.combine_item)
	# 원작 가방(docs/ref/orig_image/cave/inven/Cave_inventory.jpg)의 선택 버튼은 **붉은 라운드 버튼**이다
	# → 자작 회색 Button 대신 원본 `9patch/btn` 프레임을 깐다.
	var selbg := NinePatchRect.new()
	selbg.texture = load("res://assets/converted/ninepatch_ui/9patch_btn.tres")
	selbg.patch_margin_left = 16; selbg.patch_margin_right = 16
	selbg.patch_margin_top = 16; selbg.patch_margin_bottom = 16
	selbg.position = Vector2(170, 520); selbg.size = Vector2(220, 58)
	selbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inv_detail_box.add_child(selbg)
	var select := Button.new()
	select.flat = true
	if is_gacha_egg:
		select.text = "사용"
	elif is_egg:
		select.text = "부화"
	elif is_smelt:
		select.text = "제련"
	elif is_gear:
		select.text = "장착"
	elif is_scroll or is_skill_item or is_food or use_kind != "":
		select.text = "사용"
	else:
		select.text = "선택"
	select.position = Vector2(170, 520)
	select.size = Vector2(220, 58)
	select.add_theme_font_size_override("font_size", 28)
	select.add_theme_color_override("font_color", Color.WHITE)
	select.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0, 0.9))
	select.add_theme_constant_override("outline_size", 5)
	if is_gacha_egg:
		var gk2 := _inv_selected
		select.pressed.connect(func(): _open_gacha_egg(gk2))
	elif is_egg:
		var ek := _inv_selected
		select.pressed.connect(func(): _start_hatch(ek))
	elif is_smelt:
		var sk0 := _inv_selected
		select.pressed.connect(func(): _open_smelt(sk0))
	elif is_gear:
		# 젬 = 원작 `BagPopup::onClickConfirm` case 2 — **여기서 바로 장착한다**(맞는 칸을 클라가
		#   찾고 토스트/모달로 결과를 알린다). 종전엔 가방을 닫고 `_open_gem_select()` 를 열어
		#   같은 젬을 한 번 더 고르게 했다 — 원작에 없는 단계였다(2026-07-30 수정).
		#   ⚠️ 장비는 다르다: 원작 가방 장비 탭(case 1)의 확인은 장착이 아니라 `unlock_equip` 요청이고
		#   실제 장착은 `MultyEquipPop` 이 한다 → 우리도 장비 관리 화면으로 보낸다(현행 유지).
		var gk := String(item.get("category", ""))
		var ik0 := _inv_selected
		select.pressed.connect(func():
			if gk == "gem":
				_equip_gem_from_bag(ik0)
			else:
				_close_overlay()
				_open_equipment())
	elif is_scroll:
		var sk := _inv_selected
		select.pressed.connect(func(): _use_skill_scroll(sk))
	elif is_skill_item:
		var sik := _inv_selected
		select.pressed.connect(func(): _use_skill_item(sik))
	elif is_food:
		var fk := _inv_selected
		select.pressed.connect(func(): _use_food(fk))
	elif use_kind != "":
		var ck := _inv_selected
		var kind := use_kind
		select.pressed.connect(func(): _use_consumable(ck, kind))
	else:
		# 재료·재화·미구현(stub/todo)·컷(cut)·원작 더미(dummy) — 누를 게 없다는 것을 버튼으로도 알린다.
		select.disabled = String(item.get("offline", "")) in ["todo", "stub", "cut", "dummy"]
		select.pressed.connect(func(): _inventory_select(_inv_selected))
	_inv_detail_box.add_child(select)

	# ── '10회 사용' — 가챠 계열(뽑기 알·젬 상자)을 10개 이상 들고 있을 때만 ──────────
	# ⚠️ 원작 로직이 아니다(사용자 요청 2026-07-30, 조회 근거는 `_batch_use_kind` 주석).
	var batch_kind := _batch_use_kind(_inv_selected, item)
	if batch_kind != "" and UserDB.item_count(_inv_selected) >= BATCH_USE_N:
		var bbg := NinePatchRect.new()
		bbg.texture = load("res://assets/converted/ninepatch_ui/9patch_btn2.tres")
		bbg.patch_margin_left = 16; bbg.patch_margin_right = 16
		bbg.patch_margin_top = 16; bbg.patch_margin_bottom = 16
		bbg.position = Vector2(170, 586); bbg.size = Vector2(220, 52)
		bbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_inv_detail_box.add_child(bbg)
		var bb := Button.new()
		bb.flat = true
		bb.text = "%d회 사용" % BATCH_USE_N
		bb.position = Vector2(170, 586)
		bb.size = Vector2(220, 52)
		bb.add_theme_font_size_override("font_size", 24)
		bb.add_theme_color_override("font_color", Color.WHITE)
		bb.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0, 0.9))
		bb.add_theme_constant_override("outline_size", 5)
		var bk := _inv_selected
		var bkind := batch_kind
		bb.pressed.connect(func(): _use_batch(bk, bkind, BATCH_USE_N))
		_inv_detail_box.add_child(bb)

# ========================= 가방 소모품 사용 =========================
## 이 아이템이 가방에서 어떤 사용 흐름을 갖는가. ""=사용 흐름 없음(선택만).
##
## 원작 근거: 축복·레벨 아이템은 가방이 아니라 **훈련/레벨업 화면에서 대상 드래곤을 받아** 쓴다
##   (`TrainingSelectLayer` = `setTarget` + `setItem` + CCTableView + `item/item_small.img_plist`).
##   우리도 대상 드래곤을 고르게 한 뒤 기존 레벨업 롤(`LevelSystem.roll_level`)을 그대로 태운다.
## ⚠️ items.json 의 `offline` 이 "impl" 인 것만 배선한다 — stub/todo 는 규칙이 유실됐거나
##   미설계라 여기서 지어내지 않는다(HARD RULE 6).
func _consumable_action(key: String, item: Dictionary) -> String:
	if String(item.get("offline", "")) != "impl":
		return ""
	# 행동불능 치료제 — data/incapacitation.json `cure_items`.
	# ⚠️ 이 배열은 **현재 비어 있다**(사용자 정정 2026-07-29: 그런 아이템은 없었다. 회복은
	#   1시간 경과 또는 다이아 즉시회복뿐). 즉 이 분기는 지금 절대 타지 않는다.
	#   흐름 자체는 남겨 둔다 — 원작 `setCureTime(0)`(CaveScene.c:8309·15889)에 대응하고,
	#   해당 아이템이 확인되면 `cure_items` 에 키만 넣으면 되살아난다.
	if Incapacitation.is_cure_item(Data.incapacitation, key):
		return "cure"
	match String(item.get("subcategory", "")):
		"blessing":
			return "levelup"
		"level":
			return "levelup" if key == "level_up" else ("leveldown" if key == "level_down" else "")
		"nest":
			match key:
				"holynest": return "holynest"
				"ascension": return "ascension"
				"bridle": return "bridle"
			return ""
		"qol":
			# 🔴 원작은 두 아이템이 **다른 화면**을 연다 —
			#   `BagPopup::onClickNickNameBtn @00e0c9f4`       → `NickNameLayer`      = **유저 닉네임**
			#   `BagPopup::onClickDragonNickNameBtn @00e0cc6c` → `DragonNickNamePopup` = 드래곤 별명
			#   종전에는 둘 다 "rename"(드래곤)으로 보내 유저 닉네임 변경이 동작하지 않았다.
			if key == "dragon_namechange":
				return "rename"
			if key == "namechange":
				return "usernick"
			return ""
		"box":
			# 진귀한 보석 상자 = 젬 뽑기 상자(위키 item.pdf §9.3 "바루스에게 개당 15다이아 …
			# 높은 등급의 일반 젬"). 나머지 상자류는 개봉표가 유실이라 손대지 않는다.
			return "gembox" if key == "jem_random" else ""
		"slot":
			# 슬롯 재부여 아이템 — 원작 문자열이 동작을 못박아 준다:
			#   `CaveBagMsg19` "현재의 잼 슬롯이 랜덤으로 변경 됩니다."   → gemslot_change(샌즈의 비약)
			#   `CaveBagMsg20` "현재의 스킬 슬롯이 랜덤으로 변경 됩니다." → skillslot_change(다이즈의 호신부)
			#   `CaveToastMsg8` "드래곤의 젬 슬롯이 초기화되었습니다."     → gem_init
			# `slot_reset`(슬롯 초기화)은 무엇을 초기화하는지 근거가 없어 손대지 않는다(todo 유지).
			match key:
				"gemslot_change": return "gemslot"
				"skillslot_change": return "skillslot"
				"gem_init": return "geminit"
			return ""
	return ""

## 가방에서 소모품 사용. kind = _consumable_action() 결과.
func _use_consumable(key: String, kind: String) -> void:
	if UserDB.item_count(key) <= 0:
		_toast("보유하지 않은 아이템입니다"); return
	match kind:
		"levelup", "leveldown":
			_open_consumable_target(key, kind)
		"holynest":
			# 사용자 확정: 다음 부화의 초기 등급 +1.0. 판정은 Hatchery.roll_grade(blessed=true).
			if bool(UserDB.get_pmeta("blessed_nest", false)):
				_toast("이미 둥지에 축복이 걸려 있습니다"); return
			UserDB.use_item(key, 1)
			UserDB.set_pmeta("blessed_nest", true)
			_close_overlay(); _refresh()
			_toast("둥지에 축복을 걸었습니다 — 다음 부화 등급 +1.0")
		"gembox":
			# 진귀한 보석 상자 개봉 → **높은 등급의 일반 젬** 1개(위키 item.pdf §9.3).
			# ⚠️ 다이아 가챠와 표가 다르다(가챠=혼성·소울 전티어) → 전용 표 box.jem_random.
			var rng := RandomNumberGenerator.new(); rng.randomize()
			var gk := Drops.roll_gem_box(Data.drops, Data.gems, rng)
			if gk == "":
				_toast("젬 데이터가 비어 있습니다"); return
			UserDB.use_item(key, 1)
			UserDB.add_item(gk, 1)
			_inv_tab = "gem"; _inv_selected = gk
			_close_overlay(); _open_inventory()
			_toast("%s 을(를) 얻었습니다!" % Drops.display_name(gk, Data.gems, Data.equipment))
		"usernick":
			# 원작 BagPopup: `NickNameLayer::create(false)` + `setConfirmListener` + `show()`.
			# 대상 드래곤을 고르지 않는다 — 유저 계정의 닉네임이다.
			_close_overlay()
			NickNamePopup.open(self, false, func(nick: String):
				UserDB.use_item(key, 1)
				_refresh()
				_toast("닉네임을 '%s' 으로 바꿨습니다" % nick))
		"ascension", "bridle", "rename", "gemslot", "skillslot", "geminit":
			_open_consumable_target(key, kind)

## 대상 드래곤 선택 → 아이템 적용. 원작 TrainingSelectLayer 의 `setTarget` 자리.
## 스킬 스크롤 모달(_skill_modal_*)을 그대로 재사용한다 — 같은 "대상 고르기" UI다.
func _open_consumable_target(key: String, kind: String) -> void:
	_close_skill_modal()
	_skill_modal = CanvasLayer.new()
	_skill_modal.layer = 20
	add_child(_skill_modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_skill_modal.add_child(dim)
	var titles := {"levelup": "레벨을 올릴 드래곤", "leveldown": "레벨을 내릴 드래곤",
		"ascension": "승천시킬 드래곤 (삭제)", "bridle": "보관할 드래곤",
		"rename": "이름을 바꿀 드래곤",
		"gemslot": "젬 슬롯을 변경할 드래곤", "skillslot": "스킬 슬롯을 변경할 드래곤",
		"geminit": "젬 슬롯을 초기화할 드래곤", "cure": "행동불능을 풀 드래곤"}
	var panel := _skill_modal_panel("%s — %s" % [String(titles.get(kind, "대상")),
		_inventory_item_name(key)])
	var body := _skill_modal_list(panel)
	var owned: Array = UserDB.dragons()
	if owned.is_empty():
		body.add_child(_skill_list_button("(보유 드래곤 없음)", _close_skill_modal))
		return
	for d in owned:
		var uid := int(d["uid"])
		if UserDB.is_egg(d):
			continue                     # 알에는 쓸 수 없다
		var ddef := Data.get_dragon(int(d["id"]))
		var txt := "Lv.%d %s" % [int(d["level"]), ddef.get("name", "드래곤")]
		if kind == "ascension":
			txt += "   → 다이아 %d개" % _ascension_diamond(int(d["level"]))
		elif kind in ["gemslot", "geminit"]:
			txt += "   현재 [%s]" % _gem_slot_type_line(d)
		elif kind == "skillslot":
			txt += "   현재 [%s]" % _skill_slot_type_line(d)
		elif kind == "cure":
			# 행동불능이 아닌 드래곤에게는 쓸 수 없다(원작 `AdventureAlert_7` "기절 상태가 아닙니다.").
			if not UserDB.is_down(uid):
				continue
			txt += "   남은 %s" % Incapacitation.remain_text(UserDB.cure_time(uid),
				int(Time.get_unix_time_from_system()))
		if bool(d.get("locked", false)) and kind in ["ascension", "bridle"]:
			txt += "   (잠김)"
		body.add_child(_skill_list_button(txt, func(): _apply_consumable(key, kind, uid)))
	if kind == "cure" and body.get_child_count() == 0:
		body.add_child(_skill_list_button("(행동불능인 드래곤이 없습니다)", _close_skill_modal))

## 젬 슬롯 타입 3칸을 한글 약칭으로("공/방/체"). 표기명은 data/gems.json slot_types.kr.
func _gem_slot_type_line(d: Dictionary) -> String:
	var kr: Dictionary = (Data.gems.get("slot_types", {}) as Dictionary).get("kr", {})
	var out: PackedStringArray = []
	for t in Gem.types(d.get("gems", {})):
		out.append(String(kr.get(String(t), String(t))))
	return "/".join(out)

## 스킬 슬롯 타입 2칸을 기호로("○/☆"). 원작 △□○☆.
const _SKILL_SLOT_MARK := {"tri": "△", "sq": "□", "cir": "○", "star": "☆"}

func _skill_slot_type_line(d: Dictionary) -> String:
	var out: PackedStringArray = []
	for t in Loadout.slot_types(d):
		out.append(String(_SKILL_SLOT_MARK.get(String(t), "?")))
	return "/".join(out)

## 원작 '드래곤의 승천' 보상(사용자 확정 2026-07-27): 기본 5개, 5레벨당 5개씩 증가.
func _ascension_diamond(level: int) -> int:
	return 5 * (1 + int(level / 5.0))

## 드래곤 보관소 — '드래곤의 고삐'로 넣어 둔 개체 목록. 여기서 동굴 슬롯으로 되돌린다.
## 사용자 확정: 보관 중에는 편성·관리 불가(그래서 UserDB.dragons() 에서 빠져 있다).
func _open_dragon_storage() -> void:
	_close_skill_modal()
	_skill_modal = CanvasLayer.new()
	_skill_modal.layer = 20
	add_child(_skill_modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_skill_modal.add_child(dim)
	var panel := _skill_modal_panel("드래곤 보관소")
	var body := _skill_modal_list(panel)
	var st: Array = UserDB.storage_dragons()
	if st.is_empty():
		body.add_child(_skill_list_button("(보관된 드래곤 없음)", _close_skill_modal))
		return
	for d in st:
		var uid := int(d["uid"])
		var nm := String(Data.get_dragon(int(d["id"])).get("name", "드래곤"))
		body.add_child(_skill_list_button("Lv.%d %s   → 동굴로 꺼내기" % [int(d["level"]), nm],
			func():
				if UserDB.unstore_dragon(uid):
					UserDB.set_active(uid)
					_close_skill_modal(); _refresh(); _toast("%s 을(를) 꺼냈습니다" % nm)
				else:
					_toast("꺼낼 수 없습니다")))

func _apply_consumable(key: String, kind: String, uid: int) -> void:
	if UserDB.item_count(key) <= 0:
		_close_skill_modal(); _toast("보유하지 않은 아이템입니다"); return
	var d := UserDB.get_dragon(uid)
	if d.is_empty():
		_close_skill_modal(); return
	match kind:
		"cure":
			# 행동불능 해제 — 원작 `Dragon::setCureTime(0)`(CaveScene.c:8309).
			if not UserDB.is_down(uid):
				_toast("기절 상태가 아닙니다"); return      # 원작 `AdventureAlert_7`
			UserDB.use_item(key, 1)
			UserDB.set_cure_time(uid, 0)
			_close_skill_modal(); _close_overlay(); _refresh()
			_toast("%s 이(가) 회복했습니다" % String(Data.get_dragon(int(d["id"])).get("name", "드래곤")))
		"levelup":
			var ddef := Data.get_dragon(int(d["id"]))
			var cap := Growth.level_cap(bool(d.get("awakened", false)))
			if int(d.get("level", 1)) >= cap:
				_toast("이미 최대 레벨입니다 (%d)" % cap); return
			# 축복이면 맥스 보장 롤, Lv+1 이면 일반 롤 — 레벨업 화면과 같은 규칙(_LVUP_GUARANTEE).
			var guarantee := String(_LVUP_GUARANTEE.get(key, ""))
			var roll_cfg: Dictionary = Data.level_curve.get("roll", {})
			var rng := RandomNumberGenerator.new(); rng.randomize()
			var roll := LevelSystem.roll_level(roll_cfg, Growth.tier_growth(ddef, Data.stat_table),
				rng, 0.0, guarantee)
			var old_lv := int(d.get("level", 1))
			var sk_before := UserDB.dragon_skills(uid).size()   # 레벨 10·25·45 자동 습득 감지
			UserDB.level_up_with(uid, roll)
			var sk_got := _skills_learned_since(uid, sk_before)
			UserDB.use_item(key, 1)
			UserDB.set_active(uid)
			# 성장 단계 교체는 아래 `_refresh()` 가 이미 처리(새 단계 스파인이 서 있다).
			_close_skill_modal(); _close_overlay(); _refresh_stats(); _refresh()
			_open_levelup()          # 원작 흐름: 적용 → 레벨업 화면(ExpLayer 대응) 위에서 연출
			# 🔴 2026-07-27: 이 경로(가방 → 대상 선택)는 연출을 안 태웠던 사고가 있었다.
			#   2026-07-29: 원작 안무 타임라인으로 통합 — `_lvup_ctx` 를 읽으므로 `_open_levelup()` 뒤.
			var new_lv := int(UserDB.get_dragon(uid).get("level", 1))
			var slot_new := -1
			for si in Loadout.SLOT_UNLOCK_LEVEL.size():
				if old_lv < int(Loadout.SLOT_UNLOCK_LEVEL[si]) and new_lv >= int(Loadout.SLOT_UNLOCK_LEVEL[si]):
					slot_new = si
			_lvup_redraw({"kind": "up", "sp": 1.0, "stage_changed": false,
				"slot_new": slot_new, "triple": bool(roll.get("triple", false))})
			if not sk_got.is_empty():
				_toast("새 스킬 습득 — %s" % ", ".join(sk_got))
		"leveldown":
			if int(d.get("level", 1)) <= 1:
				_toast("레벨 1 미만으로 내릴 수 없습니다"); return
			if not UserDB.level_down(uid):
				_toast("레벨을 내릴 수 없습니다"); return
			UserDB.use_item(key, 1)
			UserDB.set_active(uid)
			_close_skill_modal(); _close_overlay(); _refresh_stats(); _refresh()
			_open_levelup()
			Bgm.sfx("effect_level_updown")
			_lvup_word_banner("LEVEL DOWN", 1.4, Color(0.86, 0.66, 1.0), Color(0.24, 0.05, 0.34, 1.0))
		"ascension":
			# 사용자 확정: 동굴 슬롯의 드래곤을 삭제하고 다이아를 지급한다.
			if bool(d.get("locked", false)):
				_toast("잠긴 드래곤은 승천시킬 수 없습니다"); return
			if UserDB.dragon_count() <= 1:
				_toast("마지막 드래곤은 승천시킬 수 없습니다"); return
			var dia := _ascension_diamond(int(d.get("level", 1)))
			var nm := String(Data.get_dragon(int(d["id"])).get("name", "드래곤"))
			if not UserDB.release_dragon(uid):
				_toast("승천시킬 수 없습니다"); return
			UserDB.use_item(key, 1)
			UserDB.add_currency("diamond", dia)
			_close_skill_modal(); _close_overlay(); _refresh()
			_ascension_ceremony()    # 원작 CaveScene ascension_event_spine
			_toast("%s 이(가) 승천했습니다 — 다이아 %d개" % [nm, dia])
		"bridle":
			# 사용자 확정: 동굴 슬롯을 비우기 위해 보관소로 넣는다(편성·관리 불가).
			if bool(d.get("locked", false)):
				_toast("잠긴 드래곤은 보관할 수 없습니다"); return
			if not UserDB.store_dragon(uid):
				_toast("보관할 수 없습니다 (마지막 드래곤)"); return
			UserDB.use_item(key, 1)
			_close_skill_modal(); _close_overlay(); _refresh()
			_toast("보관소에 넣었습니다 — 동굴 슬롯이 비었습니다")
		"rename":
			UserDB.use_item(key, 1)
			UserDB.set_active(uid)
			_close_skill_modal(); _close_overlay(); _refresh()
			_open_rename()
		"gemslot":
			# 원작 `CaveBagMsg19`: "현재의 잼 슬롯이 랜덤으로 변경 됩니다." → 3칸 전부 재추첨.
			# 장착 중인 젬은 먼저 인벤으로 돌려준다 — 새 타입에 안 맞을 수 있으므로.
			var gf: Dictionary = d.get("gems", {})
			var returned := _return_all_gems(uid, gf)
			var nt: Array = Gem.random_types(Data.gems)
			UserDB.set_dragon_field(uid, "gems", Gem.set_types({"types": nt, "slots": []}, nt))
			UserDB.use_item(key, 1)
			UserDB.set_active(uid)
			_close_skill_modal(); _close_overlay(); _refresh_stats(); _refresh()
			_toast("드래곤의 젬 슬롯이 변경되었습니다 — [%s]%s" % [
				_gem_slot_type_line(UserDB.get_dragon(uid)),
				("  (젬 %d개 반환)" % returned) if returned > 0 else ""])
		"skillslot":
			# 원작 `CaveBagMsg20`: "현재의 스킬 슬롯이 랜덤으로 변경 됩니다."
			# 스킬은 칸 타입과 무관하게 장착되므로(일치 시 추가효과만) 빼지 않는다.
			UserDB.set_dragon_field(uid, "skill_slots", Loadout.random_slot_types())
			UserDB.use_item(key, 1)
			UserDB.set_active(uid)
			_close_skill_modal(); _close_overlay(); _refresh()
			_toast("드래곤의 스킬 슬롯이 변경되었습니다 — [%s]" % _skill_slot_type_line(UserDB.get_dragon(uid)))
		"geminit":
			# 원작 `CaveToastMsg8`: "드래곤의 젬 슬롯이 초기화되었습니다."
			# ASSUMPTION: '초기화' = 장착 젬 전량 해제(칸 타입은 유지). 변경은 샌즈의 비약 담당이고
			#   원작 토스트가 변경(Msg21)과 초기화(Msg8)를 나눠 두었으므로 이렇게 해석한다.
			var gf2: Dictionary = d.get("gems", {})
			var n := _return_all_gems(uid, gf2)
			if n <= 0:
				_toast("장착된 젬이 없습니다"); return
			UserDB.use_item(key, 1)
			UserDB.set_active(uid)
			_close_skill_modal(); _close_overlay(); _refresh_stats(); _refresh()
			_toast("드래곤의 젬 슬롯이 초기화되었습니다 — 젬 %d개 반환" % n)

## 원작 부화: 인벤 '알' 탭에서 알을 골라 부화시키면 **둥지 슬롯에 알이 올라가고** 타이머가 돈다
## (Dragon::setHatchTime/setEggGrade). 초기 등급 3.0~7.0 랜덤 + 축복받은 둥지 +1.0(사용자 확정).
## **연구소에서 강화한 알**(EggUpgrade)이면 랜덤 대신 확정 등급이 붙는다 — 위키 labwiki.pdf §2.1
## (1강 7.0 / 2강 7.2 / 3강 7.5). 강화분은 그 알 1개를 소비하며 함께 사라진다(1회성).
## 규칙=Hatchery/EggUpgrade(logic), 상태=UserDB, 연출=여기(render).
func _start_hatch(item_key: String) -> void:
	if item_key == "" or UserDB.item_count(item_key) <= 0:
		_toast("알이 없습니다"); return
	var did := _egg_item_to_dragon(item_key)
	if did <= 0:
		_toast("이 알의 부화 대상이 정해지지 않았습니다"); return
	var blessed := bool(UserDB.get_pmeta("blessed_nest", false))
	var ecfg: Dictionary = Data.laboratory.get("egg_upgrade", {})
	# 강화된 알이 있으면 **높은 등급부터** 쓴다(원작은 알 개체를 골랐지만 우리 알은 스택 아이템 —
	# ASSUMPTION: 플레이어가 애써 올린 등급을 먼저 쓰는 것이 의도에 가깝다).
	var counts := UserDB.egg_grade_counts(item_key)
	var owned := EggUpgrade.owned_grades(UserDB.item_count(item_key), counts)
	var step := int(owned[-1]) if not owned.is_empty() else 0
	var grade := Hatchery.grade_for(step, ecfg, RNG.randf(), blessed)
	var secs := Hatchery.hatch_seconds(grade)
	UserDB.use_item(item_key, 1)
	if step > 0:
		UserDB.set_egg_grade_counts(item_key, EggUpgrade.after_consume(step, counts))
	if blessed:
		UserDB.set_pmeta("blessed_nest", false)   # 축복받은 둥지는 1회성 — 이 부화에 썼다
	var egg := UserDB.add_egg(did, grade, secs, step)
	UserDB.set_active(int(egg["uid"]))
	_close_overlay()
	_refresh()
	_toast("부화 시작 — 남은 시간 %s%s%s" % [Hatchery.format_remain(secs),
		"  (+%d강 · 등급 %.1f 확정)" % [step, grade] if step > 0 else "",
		"  (둥지 축복 적용)" if blessed else ""])

## 알 아이템 → 부화할 드래곤 id.
## 종(種)이 정해진 알만 부화 대상이다 — items.json 의 `dragon_id`, 또는 뽑기 알 개봉으로 얻은
## 가상 키 `egg:<id>`. 뽑기 알 자체(의문의 알·빛문알·속성알)는 여기로 오지 않는다
## (`_open_gacha_egg` 가 개봉해서 알 아이템으로 바꿔 가방에 넣는다).
func _egg_item_to_dragon(item_key: String) -> int:
	return int(_inventory_item_def(item_key).get("dragon_id", 0))

## ── 뽑기 알 개봉(원작 `ItemDetailLayer::checkEgg` → `showResultEgg`) ──────────
## 위키 item.pdf §5: 의문의 알·빛문알·속성알은 **부화가 아니라 개봉**이고, 정해진 성급 풀에서
## 드래곤 알이 하나 무작위로 나온다. 풀·가중치 = `data/gacha_eggs.json`, 규칙 = `EggGacha`(logic).
##
## 개봉 결과는 **가방에 들어가는 알 아이템**이다 — 여기서 부화시키지 않는다
## (사용자 확정 2026-07-28). 언제 부화할지는 플레이어가 알 탭에서 고른다.
## items.json 에 369마리분 알 아이템이 없으므로 가상 키 `egg:<id>` 를 쓴다(EggGacha 소유).
## ⚠️ 원작은 **먼저 묻는다** — `stringsData_KR.xml` 의 `CaveEggBron*` 계열이 그 문구다.
##   `CaveEggBronMsg4`  "무작위로 선택된 드래곤의 알이 나옵니다.\n사용하시겠습니까?
##                       {#002940:* 5성 드래곤의 알이 나올 확률 : %1$s%% }"   ← 의문의 알
##   `CaveEggBronMsg11` "무작위로 선택된 4성 이상의 드래곤의 알이 나옵니다.\n사용하시겠습니까?" ← 빛문알
##   결과는 `CaveEggBronMsg7`(의문의 알) · `Msg9`(정기=속성알) · `Msg13`(일반형)
##   "…을 사용하여 <이름>의 **알을 획득**하였습니다." — 부화가 아니라 알 획득이 맞다는 원작 확인.
func _open_gacha_egg(item_key: String) -> void:
	if item_key == "" or UserDB.item_count(item_key) <= 0:
		_toast("알이 없습니다"); return
	_confirm_gacha_egg(item_key, func():
		var item: Dictionary = Data.items.get(item_key, {})
		var did := EggGacha.roll(item_key, item, Data.gacha_eggs, Data.dragons, null)
		if did <= 0:
			_toast("이 알의 결과 풀이 비어 있습니다 (data/gacha_eggs.json)"); return
		UserDB.use_item(item_key, 1)
		UserDB.add_item(EggGacha.key_for(did), 1)
		Bgm.sfx("effect_box_peong")
		_show_egg_result(did, item_key))

# ── 가챠 계열 10회 사용 ───────────────────────────────────────────────────────
## ⚠️ **원작에 없는 기능이다**(사용자 요청 2026-07-30). 조회 근거:
##   · 문자열 — `DV2/string/stringsData_KR.xml` 에 "10회 사용"·"10개 사용"·"연속 사용"·
##     "모두 사용"(아이템) 항목 없음. 사용 확인문은 1개 단위뿐(`CaveBagMsg28`·`CaveEggBronMsg4/11`).
##   · 프레임 — 전 아틀라스 `<key>` 스캔에 `x10`/`_ten`/`btn_use*` 0건.
##   · 심볼 — `docs/ref/orig_code/symbol_map.md` 의 use/open 계열에 Ten·Multi·All 0건.
##     `Gacha_Box_Popup`(후기판 마라뽑기)의 `onClickRestart` 도 **1회 재시도**라 배치가 아니다.
##   ⇒ 후기 업데이트분으로 보이며, 규칙은 "1회 개봉을 독립 시행으로 10번"으로 우리가 정한다.
##     결과창은 원작 다건 획득 팝업 `GetItemPopup`(=`ShowGetItemDetailLayer`)을 그대로 쓴다.
const BATCH_USE_N := 10

## 이 아이템이 '10회 사용' 대상인가. ""=아님.
##   "gacha_egg" = 의문의 알·빛나는 의문의 알·속성알(EggGacha 풀)
##   "gembox"    = 진귀한 보석 상자(Drops box 표)
## 나머지 상자류(구드라·금/은상자 등)는 개봉표가 유실(offline=todo)이라 1회도 못 열므로 제외한다.
func _batch_use_kind(item_key: String, item: Dictionary) -> String:
	if item_key == "" or item.is_empty():
		return ""
	if String(item.get("category", "")) == "egg" and EggGacha.is_gacha_egg(item):
		return "gacha_egg"
	if _consumable_action(item_key, item) == "gembox":
		return "gembox"
	return ""

## 10회 사용 — 확인 → n 회 개봉 → 결과를 원작 다건 팝업으로 한 번에 공개.
func _use_batch(item_key: String, kind: String, n: int) -> void:
	var have := UserDB.item_count(item_key)
	if have < n:
		_toast("%d개 이상 보유해야 %d회 사용할 수 있습니다" % [n, n]); return
	var name := Data.item_name(item_key)
	match kind:
		"gacha_egg":
			# 확인문 = 1회 사용의 원작 문구 + 회차만 덧붙인다(문구 자체는 원작 유지).
			_confirm_gacha_egg(item_key, func(): _do_gacha_egg_batch(item_key, n), n)
		"gembox":
			# `CaveBagMsg28` "상자를 열어보시겠습니까?" — 열쇠가 필요 없는 상자의 원작 문구.
			_open_popup_type(name, "상자를 열어보시겠습니까?\n\n%s %d개를 사용합니다." % [name, n],
				func(): _do_gembox_batch(item_key, n))

func _do_gacha_egg_batch(item_key: String, n: int) -> void:
	if UserDB.item_count(item_key) < n:
		_toast("알이 부족합니다"); return
	var item: Dictionary = Data.items.get(item_key, {})
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var ids: Array = EggGacha.roll_many(item_key, item, Data.gacha_eggs, Data.dragons, rng, n)
	if ids.is_empty():
		_toast("이 알의 결과 풀이 비어 있습니다 (data/gacha_eggs.json)"); return
	UserDB.use_item(item_key, ids.size())
	# 같은 종은 합쳐서 보여 준다(가방에는 어차피 같은 키로 쌓인다).
	var agg := {}
	for did in ids:
		var k := EggGacha.key_for(int(did))
		agg[k] = int(agg.get(k, 0)) + 1
		UserDB.add_item(k, 1)
	Bgm.sfx("effect_box_peong")
	# 원작 규약: **마지막 항목이 중앙에 크게** 놓인다 → 가장 높은 성급을 끝에 둔다.
	var last_key := _highest_star_egg_key(agg.keys())
	_show_batch_result(agg, last_key, "egg", last_key)

func _do_gembox_batch(item_key: String, n: int) -> void:
	if UserDB.item_count(item_key) < n:
		_toast("상자가 부족합니다"); return
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var keys: Array = Drops.roll_gem_box_many(Data.drops, Data.gems, rng, n)
	if keys.is_empty():
		_toast("젬 데이터가 비어 있습니다"); return
	UserDB.use_item(item_key, keys.size())
	var agg := {}
	for k in keys:
		agg[k] = int(agg.get(k, 0)) + 1
		UserDB.add_item(String(k), 1)
	Bgm.sfx("effect_box_peong")
	_show_batch_result(agg, String(keys[keys.size() - 1]), "gem", String(keys[keys.size() - 1]))

## 다건 결과 공개 — 원작 `ShowGetItemDetailLayer` 이식본(GetItemPopup)에 그대로 넘긴다.
## 확인하면 결과가 들어간 가방 탭으로 돌아간다(1회 사용 흐름과 같은 마무리).
func _show_batch_result(agg: Dictionary, last_key: String, tab: String, select_key: String) -> void:
	var entries: Array = []
	for k in agg.keys():
		if String(k) == last_key:
			continue
		entries.append({"key": String(k), "count": int(agg[k])})
	if agg.has(last_key):
		entries.append({"key": last_key, "count": int(agg[last_key])})
	_close_overlay()
	GetItemPopup.open(self, entries, func():
		_inv_tab = tab
		_inv_selected = select_key
		_open_inventory())

## 가상 알 키 목록 중 성급이 가장 높은 것(동급이면 먼저 나온 것).
func _highest_star_egg_key(keys: Array) -> String:
	var best := ""
	var best_star := -1
	for k in keys:
		var did := EggGacha.dragon_of(String(k))
		var st := int(Data.get_dragon(did).get("star", 0))
		if st > best_star:
			best_star = st
			best = String(k)
	return best

## 사용 전 확인 — 원작 문구 그대로. 의문의 알은 **5성 확률까지 보여 준다**(Msg4 의 %1$s).
## `count` > 1 이면 몇 개를 쓰는지 한 줄 덧붙인다(10회 사용 — 원작에 없는 우리 확장).
func _confirm_gacha_egg(item_key: String, on_ok: Callable, count := 1) -> void:
	var body := "무작위로 선택된 드래곤의 알이 나옵니다.\n사용하시겠습니까?"
	if item_key == "mall_question_egg2":
		body = "무작위로 선택된 4성 이상의 드래곤의 알이 나옵니다.\n사용하시겠습니까?"   # Msg11
	else:
		var pct := EggGacha.star_chance_pct(item_key,
			Data.items.get(item_key, {}), Data.gacha_eggs, 5, Data.dragons)
		if pct > 0.0:
			body += "\n\n* 5성 드래곤의 알이 나올 확률 : %s%%" % _pct_text(pct)          # Msg4
	if count > 1:
		body += "\n\n%s %d개를 사용합니다." % [Data.item_name(item_key), count]
	_open_popup_type(Data.item_name(item_key), body, on_ok)

## 확률 표기 — 정수면 소수점 없이(원작 %s 포맷).
func _pct_text(p: float) -> String:
	return str(int(round(p))) if absf(p - round(p)) < 0.05 else ("%.1f" % p)

## 개봉 결과창 — 원작 `ItemDetailLayer::showResultEgg` 가 쓰는 프레임 그대로:
##   패널 `9patch/recall_del` · 후광 `common/backlight3`(알 뒤) · 성급 `common/eggclass`
##   속성 `item/item_small/ele_<속성>` · 확인 `common/check_btn`.
##
## 연출 본체는 `EggResultPopup`(scripts/ui/egg_result_popup.gd) 로 옮겼다(2026-07-30) —
## 카드 코드 보상·드래곤 소환도 같은 창을 쓰기 때문이다. 여기 남은 것은 **가방 복귀**뿐이다.
func _show_egg_result(did: int, used_key := "") -> void:
	var pop := EggResultPopup.open(self, did, used_key)
	# 확인하면 가방으로 돌아간다 — 방금 얻은 알이 '알' 탭에 들어와 있다(부화는 거기서).
	pop.closed.connect(func():
		_inv_tab = "egg"
		_inv_selected = EggGacha.key_for(did)
		_open_inventory())


func _inventory_badge(left: String, right: String) -> Control:
	var box := _panel(Color(0.95, 0.86, 0.65, 0.96))
	box.size = Vector2(220, 48)
	var l := Label.new()
	l.text = left
	l.position = Vector2(12, 8)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(0.32, 0.22, 0.12))
	box.add_child(l)
	var r := Label.new()
	r.text = right
	r.position = Vector2(80, 8)
	r.size = Vector2(128, 28)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.add_theme_font_size_override("font_size", 22)
	r.add_theme_color_override("font_color", Color(0.32, 0.22, 0.12))
	box.add_child(r)
	return box

func _inventory_tabs(win: Control) -> void:
	# 🟠 정정: 하단 탭 스트립 배경이 자작 `_panel(파란 ColorRect)` 이었다.
	#   원작 가방(docs/ref/orig_image/cave/inven/Cave_inventory.jpg)의 스트립은 금속 질감 9patch 다.
	#   보유 원본 중 `9patch/menu_bg`(orig=MultyEquipPop, `asset_index.py --grep menu_bg` → 🟠 미사용)
	#   가 같은 용도(메뉴 스트립)라 이걸 쓴다.
	var shelf := NinePatchRect.new()
	shelf.texture = load("res://assets/converted/ninepatch_ui/9patch_menu_bg.tres")
	shelf.patch_margin_left = 24; shelf.patch_margin_right = 24
	shelf.patch_margin_top = 20; shelf.patch_margin_bottom = 20
	shelf.position = Vector2(50, 760)
	shelf.size = Vector2(1680, 142)
	win.add_child(shelf)
	var spacing := 200
	var startx := 140
	for i in INV_TABS.size():
		var tab: Dictionary = INV_TABS[i]
		_inventory_tab_button(shelf, tab, startx + i * spacing, 28)

func _inventory_tab_button(parent: Control, tab: Dictionary, x: int, y: int) -> void:
	var id := String(tab["id"])
	var icon := _ui_sprite(String(tab["icon"]), 1.45)
	icon.position = Vector2(x, y + 42)
	if id != _inv_tab:
		icon.modulate = Color(0.78, 0.78, 0.78, 0.9)
	parent.add_child(icon)

	var label := _ui_sprite(String(tab["label"]), 1.5)
	label.position = Vector2(x, y + 98)
	if id != _inv_tab:
		label.modulate = Color(0.72, 0.72, 0.72, 0.85)
	parent.add_child(label)

	var b := Button.new()
	b.flat = true
	b.position = Vector2(x - 58, y - 6)
	b.size = Vector2(116, 128)
	b.pressed.connect(func(): _inventory_set_tab(id))
	parent.add_child(b)

func _inventory_set_tab(tab_id: String) -> void:
	if tab_id == _inv_tab:
		return
	_inv_tab = tab_id
	var items := _inventory_items_for_tab(_inv_tab)
	_inv_selected = String(items[0]) if not items.is_empty() else ""
	_open_inventory()

func _inventory_select(key: String) -> void:
	_inv_selected = key
	_inventory_refresh_grid()
	_inventory_refresh_detail()

func _inventory_items_for_tab(tab_id: String) -> Array:
	var out := []
	for key in UserDB.inventory().keys():
		if _inventory_tab_for_item(String(key)) == tab_id:
			out.append(String(key))
	out.sort()
	return out

## 아이템 → 가방 탭. 원작 BagPopup 탭 코드와 1:1
## (`FOOD`/`EQUIP`/`GEM`/`EGG`/`SKILL`/`DOC`/`MTR`/`ETC`/`SETACC`; BagPopup.c:9179-9233).
##
## 🔴버그수정(2026-07-27): 젬 탭에 **재료**(결정 17종·보석 4종 = `item_mtr/*`)가, 장비 탭에
##   **슬롯 아이템**(젬슬롯 초기화·기누의 동전 등)이 들어가 있었다. 둘 다 젬/장비가 아니다.
##   진짜 젬·장비는 items.json 이 아니라 gems.json/equipment.json 소유이고 가상 인벤 키
##   (`gem:<코드>:<티어>` / `equip:<카탈로그키>`)로 보유한다 — 그것만 이 두 탭에 온다.
##   `category == "equipment"` 는 items.json 에 **0건**이라 장비 탭이 늘 비어 있었다.
func _inventory_tab_for_item(key: String) -> String:
	if key.begins_with(Gem.ITEM_PREFIX):
		return "gem"
	if key.begins_with(Equipment.ITEM_PREFIX):
		return "gear"
	# 스킬 아이템(에자녹 스크롤로 얻는 것) — 원작도 `AccountManager::getSkill()` 이 가방의
	# SKILL 탭 소스다(BagPopup.c:22848). `Skill` 은 `Item` 상속이라 아이템으로 취급된다.
	if key.begins_with(Loadout.ITEM_PREFIX):
		return "skill"
	var item := _inventory_item_def(key)
	var category := String(item.get("category", ""))
	match category:
		"food":
			return "food"
		"egg":
			return "egg"
		"document":
			return "doc"
		"skill":
			return "skill"
		"material":
			return "mtr"      # 결정/보석/가루/각성석 전부 재료다(원작 MTR)
	return "etc"

func _inventory_has_item(key: String) -> bool:
	return int(UserDB.inventory().get(key, 0)) > 0

## 인벤 키 → 아이템 정의. items.json 항목 외에 **젬/장비 가상 키**도 여기서 정의를 합성한다
## (정의 출처는 data/gems.json · data/equipment.json — items.json 에 복제하지 않는다, §8.1).
func _inventory_item_def(key: String) -> Dictionary:
	var g := Gem.parse_item_key(key)
	if not g.is_empty():
		var gd: Dictionary = Gem.gem_def(String(g["name"]), Data.gems)
		if gd.is_empty():
			return {}
		return {"name": String(g["name"]), "category": "gem",
			"subcategory": String(gd.get("category", "")),
			"gem_name": String(g["name"]), "gem_tier": int(g["tier"]),
			"gem_code": String(gd.get("code", "")), "offline": "impl"}
	# 스킬 아이템 — 가상 키 `skill:<id>:<level>`. 정의 출처는 data/skills.json(§8.1).
	var sk := Loadout.parse_item_key(key)
	if not sk.is_empty():
		var sd: Dictionary = Data.skills.get(str(int(sk["id"])), {})
		if sd.is_empty():
			return {}
		return {"name": "%s Lv.%d" % [String(sd.get("name", "스킬")), int(sk["level"])],
			"category": "skill", "subcategory": String(sd.get("slot", "")),
			"skill_id": int(sk["id"]), "skill_level": int(sk["level"]),
			"offline": "impl",
			"use": "현재 선택 중인 드래곤이 이 스킬을 배운다",
			"desc": String(sd.get("effect_text", ""))}
	# 뽑기 알 개봉으로 얻은 알 — 가상 키 `egg:<드래곤id>`(정의 합성은 EggGacha 소유).
	var eg := EggGacha.item_def(key, Data.dragons)
	if not eg.is_empty():
		return eg
	var ck := Equipment.parse_item_key(key)
	if ck != "":
		var it: Dictionary = Equipment.catalog(Data.equipment).get(ck, {})
		if it.is_empty():
			return {}
		var out := it.duplicate(true)
		out["category"] = "equipment"
		out["subcategory"] = String(it.get("slot_class", "all"))
		out["offline"] = "impl"
		return out
	if Data.items.has(key):
		return Data.get_item(key)
	var found := _inventory_key_from_display_name(key)
	return Data.get_item(found) if found != "" else {}

func _inventory_key_from_display_name(raw_name: String) -> String:
	for k in Data.items.keys():
		if String(Data.items[k].get("name", "")) == raw_name:
			return String(k)
	for k in Data.items.keys():
		var item_name := String(Data.items[k].get("name", ""))
		if item_name.begins_with(raw_name) or raw_name.begins_with(item_name):
			return String(k)
	return ""

# ========================= 에자녹 스크롤 → 스킬 아이템 → 습득 =========================
## 원작 3단 구조와 근거는 `docs/ref/porting/SkillScroll.md`. 요약:
##   ① 에자녹의 기억(무작위)/권능(선택)을 쓰면 **스킬 아이템**이 가방 '스킬' 탭에 들어온다.
##      이 시점에 대상 드래곤을 고르지 않는다(`ItemSkillSelectPopup::init` 은 아이템 번호만 받는다).
##   ② 스킬 아이템을 쓰면 **현재 선택 중인 드래곤**(`getDragonSelected`)이 학습 풀에 넣는다.
##   ③ 장착은 별도 — 스킬 칸 클릭(`_open_skill_select`, 원작 SkillsPopup).
## 원작 `BagPopup::onClickSelect_Confirm` case 5(DOC 탭, BagPopup.c:15409~):
##   · 무작위 스크롤(아이템번호 444·446~451)  → **확인 팝업** → 서버 사용
##   · 선택 스크롤(454~458 = `iVar6-0x1c6U < 5`) → 확인 없이 `ItemSkillSelectPopup` 바로 열기
##   어느 쪽도 드래곤을 고르지 않고, 레벨 조건도 없다.
func _use_skill_scroll(scroll_key: String) -> void:
	var table: Dictionary = Data.skill_scrolls.get("scrolls", {})
	if not table.has(scroll_key):
		_toast("이 스크롤의 정보가 없습니다")
		return
	if Loadout.scroll_is_select(scroll_key, table):
		_open_skill_book_pick(scroll_key)
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var got := Loadout.roll_scroll(scroll_key, table, Data.skills, rng)
	if got.is_empty():
		_toast("얻을 수 있는 스킬이 없습니다")
		return
	_open_popup_type("스크롤 사용", "%s\n\n사용하시겠습니까?" % _inventory_item_name(scroll_key),
		func(): _grant_skill_item(scroll_key, int(got["id"]), int(got["level"])))

## 선택형(에자녹의 권능) — 원작 `ItemSkillSelectPopup`. 목록은 `Skill::getSkillAll()` 이라
## **드래곤과 무관한 전체 스킬**이고, 확정하면 그 스킬 아이템을 받는다.
func _open_skill_book_pick(scroll_key: String) -> void:
	var table: Dictionary = Data.skill_scrolls.get("scrolls", {})
	var cand := Loadout.scroll_candidates(scroll_key, table, Data.skills)
	_close_skill_modal()
	_skill_modal = CanvasLayer.new()
	_skill_modal.layer = 20
	add_child(_skill_modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_skill_modal.add_child(dim)
	var panel := _skill_modal_panel("스킬 선택 — %s" % _inventory_item_name(scroll_key))
	var body := _skill_modal_list(panel)
	if cand.is_empty():
		body.add_child(_skill_list_button("(고를 수 있는 스킬이 없습니다)", _close_skill_modal))
		return
	for c in cand:
		var sid := int(c["id"])
		var lv := int(c["level"])
		var sdef: Dictionary = Data.skills.get(str(sid), {})
		var mark := String(_SKILL_SLOT_MARK.get(String(sdef.get("slot", "")), "?"))
		body.add_child(_skill_list_button("%s %s Lv.%d" % [mark, String(sdef.get("name", "스킬")), lv],
			func(): _grant_skill_item(scroll_key, sid, lv)))

## 스크롤 1개를 소모하고 스킬 아이템 1개를 가방에 넣는다(원작 delItem + addSkill).
func _grant_skill_item(scroll_key: String, sid: int, level: int) -> void:
	if not UserDB.use_item(scroll_key, 1):
		_toast("스크롤이 없습니다")
		return
	UserDB.add_item(Loadout.item_key(sid, level), 1)
	var nm := String(Data.skills.get(str(sid), {}).get("name", "스킬"))
	_inventory_refresh_grid()
	_inventory_refresh_detail()
	_skill_learn_result("%s Lv.%d 스크롤을 얻었습니다\n\n(가방 '스킬' 탭에서 사용하면\n지금 선택 중인 드래곤이 배웁니다)"
		% [nm, level], true)

## 스킬 아이템 사용 — 원작 `BagPopup::onClickSelect_Confirm` case 4 → `serverResult` case 4.
## 대상은 언제나 **현재 선택 중인 드래곤**이고, 같은 스킬을 이미 배웠으면 그 레벨로 **교체**된다.
## 원작 게이트: `if (9 < Dragon::getLevel(선택드래곤))` — **Lv.10 미만이면 토스트만 띄우고 끝**
## (BagPopup.c:15410). 0번 스킬 칸 해금 레벨과 같은 값이다.
func _use_skill_item(item_key: String) -> void:
	var parsed := Loadout.parse_item_key(item_key)
	if parsed.is_empty():
		return
	var a := _active()
	if a.is_empty():
		_toast("선택된 드래곤이 없습니다")
		return
	if int(a.get("level", 1)) < 10:
		_toast("Lv.10 부터 스킬을 배울 수 있습니다")
		return
	# 원작도 여기서 확인 팝업을 한 번 받는다(setCancelListener + setConfirmListener → onClickConfirm).
	var dname := String(Data.get_dragon(int(a["id"])).get("name", "드래곤"))
	var already := ""
	for s in UserDB.dragon_skills(int(a["uid"])):
		if int((s as Dictionary).get("id", 0)) == int(parsed["id"]):
			already = "\n\n(이미 배운 스킬입니다 — Lv.%d 로 바뀝니다)" % int(parsed["level"])
	_open_popup_type("스킬 습득", "%s 이(가) %s 을(를) 배웁니다.%s" % [
		dname, _inventory_item_name(item_key), already],
		func(): _do_learn_skill_item(item_key, parsed))

func _do_learn_skill_item(item_key: String, parsed: Dictionary) -> void:
	var a := _active()
	if a.is_empty():
		return
	var uid := int(a["uid"])
	var res := Loadout.learn_from_item(UserDB.dragon_skills(uid),
		int(parsed["id"]), int(parsed["level"]), Data.skills)
	if not bool(res.get("ok", false)):
		_toast(String(res.get("msg", "습득 실패")))
		return
	if not UserDB.use_item(item_key, 1):
		_toast("아이템이 없습니다")
		return
	UserDB.set_dragon_skills(uid, res["skills"])
	_inventory_refresh_grid()
	_inventory_refresh_detail()
	_refresh(); _refresh_stats()
	_skill_learn_result("%s\n\n%s" % [String(res.get("msg", "습득")),
		"(스킬 칸을 눌러 장착하세요)"], true)

func _close_skill_modal() -> void:
	if is_instance_valid(_skill_modal):
		_skill_modal.queue_free()
	_skill_modal = null

## 모달 패널(제목+닫기)만 재구성하고 반환. 단계 전환 시 호출(기존 패널 교체, dim 유지).
func _skill_modal_panel(title: String) -> Panel:
	for c in _skill_modal.get_children():
		if c is Panel:
			c.queue_free()
	var vis := _vis()
	var panel := _panel(Color(0.14, 0.09, 0.05, 0.98))
	panel.size = Vector2(520, 600)
	panel.position = (vis - panel.size) / 2.0
	_skill_modal.add_child(panel)
	var t := Label.new()
	t.text = title
	t.position = Vector2(20, 16)
	t.size = Vector2(480, 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	panel.add_child(t)
	var close := Button.new()
	close.text = "닫기"
	close.position = Vector2(210, 540)
	close.size = Vector2(100, 44)
	close.pressed.connect(_close_skill_modal)
	panel.add_child(close)
	return panel

func _skill_modal_list(panel: Panel) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.position = Vector2(40, 64)
	sc.size = Vector2(440, 460)
	panel.add_child(sc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.custom_minimum_size = Vector2(440, 0)
	sc.add_child(vb)
	return vb

func _skill_list_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(430, 52)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b

func _skill_learn_result(msg: String, ok: bool) -> void:
	var panel := _skill_modal_panel("결과")
	var l := Label.new()
	l.text = msg
	l.position = Vector2(40, 240)
	l.size = Vector2(440, 80)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color(1, 0.95, 0.6) if ok else Color(1, 0.6, 0.6))
	panel.add_child(l)

func _inventory_item_name(key: String) -> String:
	var item := _inventory_item_def(key)
	# 젬 이름은 원작 양식(사용자 확정 2026-07-27) — 일반·혼성 "<종류> +<상승량>",
	# 소울젬 "<종류>의 소울젬 +<단계>". 양식은 Gem(logic)이 소유한다.
	if String(item.get("category", "")) == "gem":
		return Gem.display_name(String(item.get("gem_name", "")),
			int(item.get("gem_tier", 0)), Data.gems)
	return String(item.get("name", key))

## 가방 상세의 하위분류 라벨. 예전엔 items.json 의 영문 subcategory(`blessing` 등)를
## 그대로 찍고 있었다 — 한글 표기로 바꾼다.
const _SUBCAT_KR := {
	"blessing": "축복", "level": "레벨", "nest": "둥지", "slot": "슬롯", "box": "상자",
	"qol": "편의", "key": "열쇠", "buff": "버프", "story": "시나리오", "ticket": "입장권",
	"drink": "드링크", "feed": "먹이", "heal": "회복", "revive": "부활",
	"dragon_egg": "드래곤 알", "element_egg": "속성 알", "gacha_egg": "뽑기 알",
	"map": "지도", "recipe": "레시피", "mix_book": "조합서",
	"memory_random": "기억의 결정", "memory_select": "기억의 판단",
	"shard": "파편", "alchemy": "연금 재료", "crystal": "결정", "crystal_ex": "전용 결정",
	"jewel": "보석", "powder": "마법가루", "awaken_stone": "각성석", "awaken_mat": "각성 재료",
	"stone_heart": "심장석", "spirit_stone": "정령석", "craft": "제작 재료",
	"essence": "에센스", "raid_shard": "레이드 조각",
	"normal": "일반 젬", "hybrid": "혼성 젬", "soul": "소울 젬",
	"all": "모든 장비칸", "battle": "전투형", "support": "보조형", "artifact": "아티팩트",
	# 스킬 아이템의 유형 = 그 스킬의 모양(원작 Skill::getSkillType 0△1□2○3☆).
	"tri": "△ 스킬", "sq": "□ 스킬", "cir": "○ 스킬", "star": "☆ 스킬",
}

func _inventory_item_desc(key: String, item: Dictionary) -> String:
	if item.is_empty():
		return "%s\n분류: 기타" % key
	var parts := []
	# ⚠️ 분류·종류·속성은 **이미 그림으로** 나와 있다(탭 / 아이콘 밑 유형 라벨 / 원형 속성 아이콘).
	#    원작 `BagPopup::resetString` 도 이 자리에 [장비효과]·[유형 문자열]·[설명]만 넣는다 —
	#    글로 한 번 더 찍으면 스크롤 박스가 설명을 밀어낸다(2026-07-29).
	# 젬/장비는 수치가 곧 아이템의 내용이다 → 효과를 함께 보여준다.
	if String(item.get("category", "")) == "gem":
		var gn2 := String(item.get("gem_name", ""))
		var gt2 := int(item.get("gem_tier", 0))
		parts.append("강화 단계: %s" % Gem.shape_label(gn2, gt2, Data.gems))
		# 위키 gems.pdf 툴팁 그대로. 전 티어 수치가 data/gems.json 에 들어 있다.
		parts.append("효과: %s" % Gem.effect_text(gn2, gt2, Data.gems))
	elif String(item.get("category", "")) == "equipment":
		var mparts: PackedStringArray = []
		for st: String in (item.get("stat_main", {}) as Dictionary):
			mparts.append("%s+%d" % [_equip_stat_kr(st), int(item["stat_main"][st])])
		if not mparts.is_empty():
			parts.append("주 능력: %s" % " ".join(mparts))
		if String(item.get("artifact_effect", "")) != "":
			parts.append("효과: %s" % String(item["artifact_effect"]))
		if String(item.get("bonus", "")) != "":
			parts.append("부가: %s" % String(item["bonus"]))
	if item.has("dragon_id"):
		parts.append("드래곤 ID: %d" % int(item["dragon_id"]))
	# 용도 — 사용자 시트(docs/input/items/groups.csv 39분류)에서 온 한 줄 설명.
	# 종전에는 미구현 아이템이면 무조건 "용도 확인 필요"만 찍었다. 이제 **용도는 알고**
	# 기능만 없는 경우를 구분해서 보여준다(2026-07-29).
	var use := String(item.get("use", ""))
	if use != "":
		parts.append("용도: %s" % use)
	match String(item.get("offline", "")):
		"dummy":
			# 우리가 못 만든 게 아니라 **원작에도 사용처가 없던** 아이템.
			parts.append("(원작에서도 쓰이지 않던 아이템입니다)")
		"cut":
			parts.append("(오프라인 재구현에서 빠진 기능의 아이템입니다)")
		"todo", "stub":
			parts.append("(해당 기능이 아직 구현되지 않았습니다)" if use != "" else "용도 확인 필요")
	return "\n".join(parts)

func _inventory_item_icon(key: String, target: float) -> Sprite2D:
	var item := _inventory_item_def(key)
	# 젬/장비는 파일 경로가 아니라 **논리키**로 아이콘을 찾는다(Icons = 에셋 카탈로그 계층 §8.4).
	var vt: Texture2D = null
	if String(item.get("category", "")) == "gem":
		vt = Icons.gem_texture(String(item.get("gem_code", "")), int(item.get("gem_tier", 0)))
	elif String(item.get("category", "")) == "equipment":
		vt = Icons.equip_texture(item)
	elif EggGacha.dragon_of(key) > 0:
		vt = Icons.dragon_egg_texture(EggGacha.dragon_of(key))
	elif String(item.get("category", "")) == "skill":
		# 원작 `Skill::getImageSprite()` 와 같은 프레임(`skill/skill_<번호>`).
		vt = _skill_tex(int(item.get("skill_id", 0)))
	if vt != null:
		var vs := Sprite2D.new()
		vs.texture = vt
		vs.material = _pma
		var vw: float = maxf(1.0, float(vt.get_width()))
		vs.scale = Vector2(target / vw, target / vw)
		return vs
	var icon_path := String(item.get("icon", ""))
	if icon_path == "":
		return null
	var slash := icon_path.find("/")
	if slash < 0:
		return null
	var dir := icon_path.substr(0, slash)
	var frame := icon_path.substr(slash + 1)
	var man := _item_manifest(dir)
	var w: float = maxf(1.0, float(man.get(frame, {}).get("w", target)))
	return _atlas_sprite(dir, frame, man, target / w)

func _item_manifest(dir: String) -> Dictionary:
	if not _item_manifests.has(dir):
		var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
		_item_manifests[dir] = JSON.parse_string(f.get_as_text()) if f else {}
	return _item_manifests[dir]

func _open_cards() -> void:
	var box := _make_overlay("카드")
	var l := Label.new(); l.text = "카드 시스템 (추후 구현)"; l.add_theme_font_size_override("font_size", 28)
	box.add_child(l)

## 받침대 앞 **FOOD(허기) 게이지**.
##
## 🔴 2026-07-30 교체 — 종전엔 `⚡ 5 / 5` 피로도 게이지였다(`common/fatigue`). 사용자 확정:
##   원작 초기의 **피로도 5칸은 후기판에서 삭제**되고 **허기만** 남았으므로 우리는 피로도를
##   구현하지 않는다. 같은 자리를 원작 허기 자산으로 다시 짰다.
## 자산(둘 다 지금까지 🟠 미사용이었다):
##   · `common/bubble_food`(37×40) — `asset_index.py --grep food` 가 **orig=CaveScene** 으로 찍는다.
##     즉 원작 동굴이 쓰는 허기 아이콘이 이것이다.
##   · `common/bar_food`(162×11) + 트랙 `common/bar_bg2`(같은 규격) — 원작 `StatusLayer::onClickFood`
##     계열이 쓰는 FOOD 게이지(§7-e). 판은 종전과 같은 `9patch/train_box4`.
## 눈금: **100 = 배부름 … 0 = 굶음**(원작 용어 `Dragon::isFood` 를 따라 저장 필드도 `food`).
##   전투 1회당 −15(`battle.gd FOOD_PER_BATTLE`), 먹이로 회복(전량/절반은 먹이 종류가 정한다).
var _food_fill: NinePatchRect
var _food_label: Label
func _build_stamina_gauge() -> void:
	var S := Design.ASSET_SCALE
	var plate := NinePatchRect.new()
	plate.texture = load("res://assets/converted/ninepatch_ui/9patch_train_box4.tres")
	plate.patch_margin_left = 22; plate.patch_margin_right = 22
	plate.patch_margin_top = 16; plate.patch_margin_bottom = 16
	plate.size = Vector2(230, 56)
	plate.position = Vector2(-115, 268)          # _stage local(1080공간) — 받침대 앞면
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(plate)
	var bub := _atlas_sprite("common_ui", "common_bubble_food", _man_common(), 1.0)
	if bub:
		bub.position = Vector2(32, 28); plate.add_child(bub)
	# 게이지 트랙 + 채움(원작 프레임 그대로, 4/3 스케일).
	var gw := 162.0 * S * 0.72
	var gh := 11.0 * S
	var gx := 60.0
	var gy := 28.0 - gh * 0.5
	var track := NinePatchRect.new()
	track.texture = load("res://assets/converted/common_ui/common_bar_bg2.tres")
	track.patch_margin_left = 5; track.patch_margin_right = 5
	track.size = Vector2(gw, gh); track.position = Vector2(gx, gy)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(track)
	_food_fill = NinePatchRect.new()
	_food_fill.texture = load("res://assets/converted/common_ui/common_bar_food.tres")
	_food_fill.patch_margin_left = 5; _food_fill.patch_margin_right = 5
	_food_fill.size = Vector2(gw, gh); _food_fill.position = Vector2(gx, gy)
	_food_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(_food_fill)
	_food_label = Label.new()
	_food_label.add_theme_font_size_override("font_size", 17)
	_food_label.add_theme_color_override("font_color", Color.WHITE)
	_food_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_food_label.add_theme_constant_override("outline_size", 4)
	_food_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_food_label.size = Vector2(gw, 20); _food_label.position = Vector2(gx, gy + gh + 1)
	plate.add_child(_food_label)
	_refresh_stamina()

## FOOD 게이지 갱신. 0이면 채움을 숨기고 라벨을 붉게 — 그 상태에서는 탐험 입장이 막힌다.
func _refresh_stamina() -> void:
	if not is_instance_valid(_food_fill) or not is_instance_valid(_food_label): return
	var a := _active()
	var fmax := ItemEffect.food_max(Data.item_effects)
	var food := clampi(int(a.get("food", fmax)) if not a.is_empty() else fmax, 0, fmax)
	var full := 162.0 * Design.ASSET_SCALE * 0.72   # _build_stamina_gauge 의 gw 와 같은 식
	_food_fill.size.x = full * (float(food) / float(maxi(1, fmax)))
	_food_fill.visible = food > 0
	_food_label.text = "%d / %d" % [food, fmax]
	_food_label.add_theme_color_override("font_color",
		Color(1, 0.45, 0.4) if food <= 0 else Color.WHITE)

var _common_man_cache: Dictionary = {}
func _man_common() -> Dictionary:
	if _common_man_cache.is_empty():
		var f := FileAccess.open("res://assets/converted/common_ui/_manifest.json", FileAccess.READ)
		if f: _common_man_cache = JSON.parse_string(f.get_as_text())
	return _common_man_cache

## 한글 조사 선택(받침 유무) — 원작 문장 표기용.
func _josa_c(word: String, with_batchim: String, without: String) -> String:
	if word.is_empty(): return without
	var c := word.unicode_at(word.length() - 1)
	if c < 0xAC00 or c > 0xD7A3: return without
	return with_batchim if ((c - 0xAC00) % 28) != 0 else without

## adventure_ui 매니페스트 캐시(레벨업 EXP 아트용).
var _adv_man_cache: Dictionary = {}
func _man_adventure() -> Dictionary:
	if _adv_man_cache.is_empty():
		var f := FileAccess.open("res://assets/converted/adventure_ui/_manifest.json", FileAccess.READ)
		if f: _adv_man_cache = JSON.parse_string(f.get_as_text())
	return _adv_man_cache

## 원작 팝업 프레임(PopupTypeLayer 계열) — `9patch/popup4` 창 + `9patch/pop_title_bg` 제목바.
## 🟠 정정: 아래 오버레이들이 자작 StyleBoxFlat 이었다. 원작은 팝업을 전부 이 두 프레임으로 만든다
##   (`audit_scene.py PopupTypeLayer` / BagPopup / BagExpandLayer 등 — 우리도 인벤·훈련결과에서 이미 사용).
## 반환 = 창 Control(자식 좌표는 창 로컬).
func _orig_popup(parent: Node, size: Vector2, title_text: String) -> Control:
	var vis := _vis()
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190
	win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = size
	win.position = Vector2(round((vis.x - size.x) * 0.5), round((vis.y - size.y) * 0.5))
	parent.add_child(win)
	if title_text != "":
		var tw := minf(size.x - 80.0, 300.0)
		var tbar := NinePatchRect.new()
		tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
		tbar.patch_margin_left = 20; tbar.patch_margin_right = 20
		tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
		tbar.size = Vector2(tw, 52); tbar.position = Vector2((size.x - tw) * 0.5, 10)
		tbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		win.add_child(tbar)
		var tl := Label.new(); tl.text = title_text
		tl.add_theme_font_size_override("font_size", 26)
		tl.add_theme_color_override("font_color", Color.WHITE)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tl.size = tbar.size; tbar.add_child(tl)
	return win
