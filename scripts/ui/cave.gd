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
## `meta` = 가방 키가 들고 온 연금술 진행도({points, potions, broken}).
func _equip_gem(uid: int, gem_name: String, tier: int, meta: Dictionary = {}) -> bool:
	var d := UserDB.get_dragon(uid)
	var next: Dictionary = Gem.equip(d.get("gems", {}), gem_name, tier, Data.gems, meta)
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
	if not _equip_gem(uid, gem_name, tier, g):      # g 에 진행도가 실려 온다
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
		# 연금술 진행도(포인트·투입 횟수·파손)를 가방 키에 실어 돌려준다 — 안 그러면
		# 해제 한 번에 강화 진행이 조용히 사라진다(`Gem.slot_to_item_key`).
		UserDB.add_item(Gem.slot_to_item_key(en[slot]), 1)
	UserDB.set_dragon_field(uid, "gems", Gem.unequip_at(UserDB.get_dragon(uid).get("gems", {}), slot))

## 장착 젬 전량 해제 후 인벤 반환. 반환 개수를 돌려준다('샌즈의 비약'·'젬슬롯 초기화'용).
func _return_all_gems(uid: int, gems_field: Dictionary) -> int:
	var n := 0
	for e in Gem.entries(gems_field):
		if e != null:
			UserDB.add_item(Gem.slot_to_item_key(e), 1)      # 진행도 보존(위와 같은 이유)
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

## 그 칸의 강화 한도 = **붙어 있는 옵션 수** × 5(위키 §2.6). 등급 기준이 아니라 옵션 기준인
## 이유는 강화 도중 추가 옵션이 붙어 옵션 수가 늘 수 있어서다(Equipment.enhance 주석).
func _equip_enhance_limit(sd: Dictionary) -> int:
	var per := int(Data.equipment.get("option", {}).get("enhance_per_option", 5))
	return (sd.get("options", []) as Array).size() * per


## 장비 스탯키 → 한글 라벨(원작 위키 §2.1 효과표 표기).
func _equip_stat_kr(key: String) -> String:
	return {
		"hp": "HP", "att": "공", "def": "방", "blk": "막기", "evd": "회피", "cri": "크리",
		"cri_pow": "크파", "pure": "관통", "depure": "관통감소", "accuracy": "명중",
		"cure": "치유", "awaken_rate": "각성", "gold": "골드", "exp": "경험",
	}.get(key, key)

## 장비 관리 — **원작 `MultyEquipPop` 이식**(제목 <MultyEquip_Title> "장비 슬롯 확장").
## 종전엔 680×64 짜리 자작 행에 변경/옵션/강화/해제 버튼을 늘어놓았는데, 참조 두 장
## (`docs/ref/equip/cave_장비칸클릭시팝업1,2.png` · `docs/ref/orig_image/lab/드래곤강화4.png`)이
## 보여 주듯 원작은 **125px 짜리 4행**(아이콘 칸 + 이름·옵션 칸)이고 버튼이 없다 —
## 행을 누르면 그 칸의 장비 선택창(`ItemEquipSelectPopup`)이 열린다. 그림은 `MultyEquipPop`
## 이 그리고(연구소 화면과 같은 클래스) 여기선 클릭만 배선한다.
## 칸 해금은 연구소(scripts/ui/laboratory.gd 「드래곤 강화」)에서 한다 — 위키 etc.pdf §2.1.1.
## 드래곤별 해금 칸 = UserDB dragon["equip_slots"](기본 all 1칸).
func _open_equipment() -> void:
	var a := _active()
	if a.is_empty(): return
	var uid := int(a["uid"])
	var pop := MultyEquipPop.open(self, uid, "equip", func(sid: String, unlocked: bool):
		if not unlocked:
			# 원작 <MultyEquip_Lock>. 확장은 연구소 '드래곤 강화'에서 한다.
			_toast("%s  (연구소 '드래곤 강화')" % MultyEquipPop.S_LOCK)
			return
		_open_item_popup(sid))
	pop.closed.connect(_refresh_stats)


## 칸 클릭 → 원작 `MultyEquipPop::onClickItemBox` → `ItemPopup::create(dragon, slotIdx)`.
## 🔀 2026-08-01: 이 자리에 있던 자작 목록창 `_open_equip_select` 를 폐기하고 원작
##   `ItemPopup` 이식본(`scripts/ui/item_popup.gd`)으로 갈았다. 젬의 `GemsPopup` 과
##   같은 2단 구성이고, 하단 버튼도 원작대로 **강화 / 장착·해제 두 개**다.
##   상세 = `docs/ref/porting/ItemPopup.md`.
func _open_item_popup(slot_id: String) -> void:
	var a := _active()
	if a.is_empty(): return
	var p := ItemPopup.open(self, int(a["uid"]), slot_id, func(): _refresh_stats())
	p.closed.connect(func(): _refresh_stats(); _open_equipment())


## `slot_id` 칸의 주 능력 중 **다른 칸과 겹치는** 것들의 한글 이름.
## 겹치면 원작은 최상위 하나만 먹는다(<MultyEquip_Slot_Warring_2>, Equipment.aggregate).
func _dup_main_stats(uid: int, slot_id: String) -> PackedStringArray:
	var cat := Equipment.catalog(Data.equipment)
	var eqf: Dictionary = UserDB.get_dragon(uid).get("equip", {})
	var mine: Dictionary = {}
	var others: Dictionary = {}
	for sl in (eqf.get("slots", []) as Array):
		var sd := sl as Dictionary
		var it: Dictionary = cat.get(String(sd.get("key", "")), {})
		for st in (it.get("stat_main", {}) as Dictionary):
			if String(sd.get("slot", "")) == slot_id:
				mine[st] = true
			else:
				others[st] = true
	var out: PackedStringArray = []
	for st in mine:
		if others.has(st):
			out.append(_equip_stat_kr(String(st)))
	return out



## 귀속 표기에 쓸 드래곤 이름(닉네임 우선, 없으면 종 이름). 없는 uid 면 "다른 드래곤".
func _dragon_label(uid: int) -> String:
	var d: Dictionary = UserDB.get_dragon(uid)
	if d.is_empty():
		return "다른 드래곤"
	# 커스텀 종(600·700)은 종 이름이 세이브에 있다(소환 재료를 따름) → Icons 가 푼다.
	return Icons.name_of(d)

## slot_id 칸의 저장 슬롯 dict(옵션·등급·강화횟수 보관). 없으면 {}.
func _equip_slot_data(eqf: Dictionary, slot_id: String) -> Dictionary:
	for s in (eqf.get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) == slot_id:
			return s
	return {}

## 옵션 재설정 — 원작 `ItemEquipSelectPopup::requestRegenEquip`(문구 `EquipeSelectMsg1`
## "해당 장비의 부가 옵션을 변경하시겠습니까?"). 소모품은 **기누의 동전**이다.
##
## 🔴 2026-08-01 정정 — 동전은 **등급을 바꾸지 않는다.**
##   원작 `ItemEquipSelectPopup::create(itemNo)` → `init(itemNo)` 이 아이템 번호로 요구
##   희귀도를 박고(485→레어 · 486→유니크 · 487→에픽 · 596/597→초월 · 903/905→…),
##   `initData` @00ea7338 이 `getRarity(equip) == 그 값` 인 장비만 목록에 올린다.
##   ⇒ **동전 등급 == 장비 등급**일 때만 쓸 수 있고, 결과 등급은 그대로다.
##   종전 구현은 "보유한 가장 높은 등급의 동전"을 자동으로 골라 등급을 덮어썼다 —
##   일반 장비에 에동을 써서 에픽으로 만들 수 있었다(원작에 없는 등급 상승 경로).
##   희귀도는 이제 **획득 시점에만** 정해진다(`Equipment.roll_instance`).
##   · 초월 동전은 추출 아이템 목록에 없어 초월 재설정은 불가(없는 아이템은 만들지 않는다).
##   · 레어(bind_grade) 이상이면 장착 상태이므로 이미 귀속돼 있다.
func _reroll_options(uid: int, slot_id: String) -> void:
	var sd := _equip_slot_data(UserDB.get_dragon(uid).get("equip", {}), slot_id)
	if sd.is_empty():
		_toast("장비가 없는 칸입니다"); return
	var grade := int(sd.get("grade", 0))
	var items: Dictionary = Data.equipment.get("option", {}).get("reroll_items", {})
	var used := String(items.get(str(grade), ""))
	var gname := ""
	var grades: Array = Data.equipment.get("option", {}).get("grades", [])
	if grade >= 0 and grade < grades.size():
		gname = String((grades[grade] as Dictionary).get("name", ""))
	if used == "":
		# 원작 <EnchantError2> "옵션을 변경할 수 있는 장신구가 아닙니다."
		_toast("%s 등급은 옵션을 변경할 수 있는 장신구가 아닙니다" % gname); return
	if UserDB.item_count(used) <= 0:
		_toast("%s이(가) 없습니다" % Data.item_name(used)); return
	# 🔀 2026-07-31: 종전엔 동전을 쓰면 **즉시** 옵션이 바뀌었다. 원작은 확인창 →
	#   마법진 연출 → `제련` 두 카드(기존/제련 옵션) 중 고르기다
	#   (참조 `docs/ref/equip/동전사용1~10.png` · `옵션클릭시` · `재시도클릭시`).
	# 원작 확인창 `<EquipeSelectMsg1>` + 소모 동전 표기.
	_open_popup_type("장비 선택",
		"해당 장비의 부가 옵션을 변경하시겠습니까?

%s  X %d"
			% [Data.item_name(used), UserDB.item_count(used)],
		func():
			if not UserDB.use_item(used, 1):
				return
			EquipOptionLayer.open(self, uid, slot_id, used, grade,
				func(changed: bool):
					_refresh_stats()
					if changed:
						_toast("%s 옵션으로 변경했습니다" % gname)
					else:
						_toast("기존 옵션을 유지했습니다")),
		"확인", "취소")

## 귀속해제(원작 `CaveEquip_Lift`) — '구드라의 지혜' 1개 소모. 위키 item.pdf: 상점 20다이아,
## "사용 시 귀속 아이템을 1회 해제시킬 수 있다".
func _unbind_equip(uid: int, slot_id: String) -> void:
	var key := String(Data.equipment.get("option", {}).get("unbind_item", "item_disconnect"))
	if UserDB.item_count(key) <= 0:
		_toast("구드라의 지혜가 없습니다"); return
	var cur: Dictionary = UserDB.get_dragon(uid).get("equip", {})
	var sd := _equip_slot_data(cur, slot_id)
	if sd.is_empty() or int(sd.get("belong", 0)) <= 0:
		_toast("귀속되지 않은 아이템입니다"); return      # 원작 문구 CaveItemEquipMsg12
	if not UserDB.use_item(key, 1):
		return
	# 🟢 원작은 귀속을 풀면서 **장착도 벗긴다** — `BagPopup.c:22262~22284`:
	#   getDragonTag() >= 1 이면 `Dragon::unSetEquip(pos)` → `setDragonTag(0)` → `setBelong(0)`
	#   → `equip+0x130 = -1`(슬롯 위치 초기화). 애초에 다른 드래곤에게 옮기려고 푸는 것이라
	#   그대로 끼워 두지 않는다. 종전 구현은 낀 채로 belong 만 0 으로 만들었다.
	var freed := sd.duplicate(true)
	freed["belong"] = 0
	UserDB.add_item(Equipment.slot_to_item_key(freed), 1)
	UserDB.set_dragon_field(uid, "equip", Equipment.unequip(cur, slot_id))
	_refresh_stats()
	_toast("귀속을 해제했습니다 — 장비는 가방으로 돌아갑니다")

## 장비 강화 — 원작 `ItemEnchantPopup`(톱니 기계 화면)을 연다.
## 🔀 2026-07-31: 종전엔 버튼 한 번에 즉시 강화됐다. 원작 화면은 톱니 기계 + 보조 재료 3칸 +
##   성공 확률 + 비용이고, 참조 `docs/ref/equip/장비강화1.png` 가 그 모양을 보여 준다.
##   창 = `scripts/ui/item_enchant_popup.gd`.
func _enhance_option(uid: int, slot_id: String) -> void:
	ItemEnchantPopup.open(self, ItemEnchantPopup.target_worn(uid, slot_id),
		func(): _refresh_stats())

## 🔴 제거(2026-08-01): `_open_equip_select`(자작 장비 선택창) + 그 하단 버튼 줄.
##   원작은 칸별 전용 팝업 `ItemPopup`(`MultyEquipPop::onClickItemBox` → `ItemPopup::create`)
##   을 갖고 있고, 버튼도 **강화/장착·해제 두 개**뿐이다. 이식본 = `scripts/ui/item_popup.gd`,
##   진입 = `_open_item_popup`. 옵션 재설정·귀속해제는 그 창과 가방으로 옮겼다.

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
		"rename": _rename_gate()
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
	var nm := Label.new(); nm.text = "%s Lv.%d" % [Icons.species_name(int(d["id"])), int(d["level"])]
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
	var nm := Label.new(); nm.text = "%s  Lv.%d" % [Icons.species_name(int(d["id"])), int(d["level"])]
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
	var t := Label.new(); t.text = "%s의 스킬" % Icons.species_name(int(a["id"]))
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

## 스킬 칸 클릭 — 원작 `CaveScene::onClickSkill` → `SkillsPopup::create(dragon)` +
## `setSelectTag(slot)`. 창 전체를 `scripts/ui/skills_popup.gd` 로 1:1 이식했다.
## 좌표·동작 표 = `docs/ref/porting/SkillsPopup.md`, 참조 = `docs/ref/드래곤_스킬장착탭.png`.
##
## 🔀 2026-07-31: 종전 이 자리의 **자작 리스트 모달**(`_skill_modal_*` 재사용)을 걷어냈다.
##   원작 창은 좌측 가로 스크롤 표(셀=세로 3칸) + 우측 350×420 상세 패널 + 장착/해제 버튼이고,
##   "다른 칸에 장착 중인 스킬"은 **교환하지 않고 `<CaveSkillMsg>` 로 거절**한다.
func _open_skill_select(slot: int) -> void:
	var a := _active()
	if a.is_empty(): return
	var p := SkillsPopup.open(self, int(a["uid"]), slot, func(): _refresh(); _refresh_stats())
	p.closed.connect(func(): _refresh(); _refresh_stats())

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
	var a := _active()
	if a.is_empty():
		_build_stamina_gauge()
		return
	# 원작: 부화 대기 중인 **알도 둥지 슬롯을 차지**한다(Dragon::setHatchTime).
	# 알이면 받침대 앞 정보 판이 **허기 게이지 대신 부화 타이머**가 된다 — 원작도 같은 판
	# (`CaveScene` this+0x258)을 알/드래곤이 나눠 쓴다. 종전엔 둘을 겹쳐 그리고 있었다.
	if UserDB.is_egg(a):
		_build_egg_on_stand(a)
		return
	_build_stamina_gauge()
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
	var species := Icons.species_name(int(a["id"]))
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
	UserDB.bump_quest("feeds")   # 마을 미션: 먹이 주기 카운트
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

# ═══════════════════════════════════════════════════════════════════════════
# 알(부화) — 원작 `CaveScene` 의 알 분기 1:1 이식.
#   대기: setDragonInfo(알 분기) + countDownFatigue
#   완료: countDownFatigue 완료 분기 + setActionEgg
#   부화: onClickFatigue → sResultEgg (+ increaseRating)
#   즉시: onClickFatigue(tag5) → onClickEggDia
# 포팅 카드 = docs/ref/porting/EggHatch.md, 레퍼런스 = docs/ref/egg/*.png
#
# **좌표계**: 원작 주역 레이어(`this+0x3a0`)는 `CCLayer 350×300, anchor(0.5,0),
# pos=(visW*0.5, visH*0.5-80)` 이고 그 안은 **디자인 포인트**다. 우리 `_stage` 는 1080 공간
# (scale=S1080)이라 단위가 다르므로, `_stage` 안에 **역스케일 노드**(`_egg_layer`)를 하나 두고
# 그 안은 원작 포인트를 그대로 쓴다. 레이어 로컬 (ox,oy) → 노드 좌표는 `_egg_pt()`.
# 이 대응은 레퍼런스 스크린샷과 대조해 검증했다(포팅 카드 §2 표 — 월계관·정보판·알 전부 일치).
# ═══════════════════════════════════════════════════════════════════════════

const EGG_LAYER_SIZE := Vector2(350, 300)   # 원작 CCSize(350,300)
const EGG_STAND_DY := 80.0                  # 원작 pos y = visH*0.5 − 80
const EGG_PLATE_DY := 137.0                 # 정보 판 pos y = visH*0.5 − 137
const EGG_PLATE_SIZE := Vector2(180, 45)    # 9patch/dialogue_box CCSize(180,45)
const EGG_DIA_COST := 300                   # onClickFatigue: isMEC ? 1500 : 300
## ⚠️ ASSUMPTION: 빛기둥 8발의 타격음. 원작은 `sResultEgg` 안의 **익명 람다**가 내는데
## 람다 본문은 디컴프 산출물(클래스 단위)에 없다 → 덤프에 남은 유일한 미사용 알 효과음을 쓴다.
## 원본이 특정되면 이 상수 한 줄만 고치면 된다.
const EGG_BEAT_SFX := "effect_egg"
## sResultEgg 의 CCCallFunc 간격(초) — 앞의 2개(A/B)를 뺀 타격음 8발의 상대 시각.
const EGG_BEAT_DELAYS := [0.05, 0.35, 0.29, 0.35, 0.25, 0.25, 0.22, 0.21, 0.12, 0.15, 0.11]

var _egg_layer: Node2D = null       # 원작 this+0x3a0 (주역 레이어)
var _egg_plate: Control = null      # 원작 this+0x258 (9patch/dialogue_box)
var _egg_time_label: Label = null   # 원작 this+0x260
var _egg_dia_btn: Control = null    # 원작 정보 판의 tag 5 (common/charge)
var _egg_body: Node2D = null        # 원작 주역 레이어의 tag 0 (알 본체)
var _egg_ghosts: Array[Node2D] = [] # 원작 tag 1 · tag 2 (반투명 펄스)
var _egg_uid := 0
var _egg_done := false              # 타이머 만료(= "완료" 상태)
var _egg_busy := false              # 부화 연출 진행 중(중복 탭 차단)
var _egg_action_tw: Tween = null    # setActionEgg 루프(탭 시 stopAllActions 로 죽인다)
var _egg_heartbeat: AudioStreamPlayer = null   # 원작 music/effect_heart_beat.mp3 루프

## 레이어 로컬(원작 cocos, y-up, 원점=좌하단) → `_egg_layer` 노드 좌표(y-down, 원점=anchor).
func _egg_pt(ox: float, oy: float) -> Vector2:
	return Vector2(ox - EGG_LAYER_SIZE.x * 0.5, -oy)

## 알 그림 1장. 원작은 같은 `Egg::getImage()`(= `dragon/dragon_%d/egg.png`)를 **3번** 쓴다.
## 원작 위치 = `(w/2, h/2 − 알높이)` + `anchor(0.5,0)`(밑변 기준). 여기서 "알높이"는
## `getContentSize()` = 트림 전 **원본 캔버스** 높이다(CCSprite 는 트림해도 contentSize 가
## originalSize 다) → `_manifest.json` 의 `src` 를 쓴다.
func _egg_sprite(did: int, org_scale: float) -> Node2D:
	var S := Design.ASSET_SCALE
	var pdir := "portrait_%d" % did
	var key := _dex_stage_frame(did, "egg")
	var info: Dictionary = AtlasUI.manifest(pdir).get(key, {})
	var src: Array = info.get("src", [float(info.get("w", 0)), float(info.get("h", 0))])
	var holder := AtlasUI.spr_cocos(pdir, key, org_scale, Vector2(0.5, 0))
	if holder == null:
		holder = Node2D.new()
	holder.position = _egg_pt(EGG_LAYER_SIZE.x * 0.5, EGG_LAYER_SIZE.y * 0.5 - float(src[1]) * S)
	holder.set_meta("home", holder.position)
	return holder

## 원작 `setDragonInfo` 알 분기 — 받침대 위 알 + 둥지 + 정보 판.
func _build_egg_on_stand(a: Dictionary) -> void:
	var did := int(a["id"])
	var blessed := bool(a.get("egg_blessed", false))
	_egg_uid = int(a["uid"])
	_egg_done = false
	_egg_busy = false
	_egg_ghosts.clear()

	_egg_layer = Node2D.new()
	# 원작 주역 레이어 원점은 화면 (visW*0.5, visH*0.5−80) — 우리 `_stage` 원점보다
	# 88pt 아래다(_stage 는 visH*0.5−8). 1080 공간에서 그만큼 내리고 역스케일한다.
	_egg_layer.position = Vector2(0, (EGG_STAND_DY + 8.0) / S1080)
	_egg_layer.scale = Vector2(1.0 / S1080, 1.0 / S1080)
	_stage.add_child(_egg_layer)

	# ⚠️ 둥지 4프레임은 전부 `sourceSize {184,184}` 에 크게 트림돼 있다(`nest1` 은 offset y −47)
	#    → 반드시 `spr_cocos`(트림 되돌림)로 놓는다. 트림을 무시하면 짚더미가 알 중턱에 뜬다.
	var nest_pos := _egg_pt(175, EGG_LAYER_SIZE.y * 0.5 - 35.0)
	# 그림자(원작 common/shadow ×1.75 @ (w/2, h/2−135))
	var sh := AtlasUI.spr_cocos("common_ui", "common_shadow", 1.75)
	if sh:
		sh.position = _egg_pt(175, EGG_LAYER_SIZE.y * 0.5 - 135.0)
		_egg_layer.add_child(sh)
	# 둥지 뒤(nest2 / nest_holy2) ×1.5 @ (w/2, h/2−35)
	var nest_back := AtlasUI.spr_cocos("common_ui",
		"common_nest_holy2" if blessed else "common_nest2", 1.5)
	if nest_back:
		nest_back.position = nest_pos
		_egg_layer.add_child(nest_back)
	# 알 3겹 — tag1(×1.6, 투명) · tag2(×1.7, 투명) 펄스 유령, tag0(×1.5) 본체.
	for g in [1.6, 1.7]:
		var ghost := _egg_sprite(did, g)
		ghost.modulate.a = 0.0
		_egg_layer.add_child(ghost)
		_egg_ghosts.append(ghost)
	_egg_body = _egg_sprite(did, 1.5)
	_egg_layer.add_child(_egg_body)
	# 강화알(+N) 오라 — 원작은 nest1 의 자식(z=−1)이라 **둥지 앞판보다 뒤, 알보다 앞**이다.
	if int(a.get("egg_enhance", 0)) > 0:
		_egg_enhance_aura()
	# 둥지 앞(nest1 / nest_holy1) ×1.5 — 알보다 앞
	var nest_front := AtlasUI.spr_cocos("common_ui",
		"common_nest_holy1" if blessed else "common_nest1", 1.5)
	if nest_front:
		nest_front.position = nest_pos
		_egg_layer.add_child(nest_front)
		# 축복 둥지 먼지 — 원작은 getNestLevel()==1 일 때만 nest1 중심에 붙인다.
		if blessed:
			var dust := CocosParticle.spawn(nest_front, "cave_dust", Vector2.ZERO, -2)
			if dust: dust.one_shot = false

	_egg_wait_anim()
	_build_egg_plate()
	# 원작 setDragonInfo 알 분기: stopEffectAll() 후 심장박동을 **루프**로 깐다.
	# 플레이어를 `_egg_layer` 에 붙여 두면 화면이 바뀔 때(=레이어 소멸) 같이 멈춘다.
	_egg_heartbeat = Bgm.loop_sfx("effect_heart_beat")
	if _egg_heartbeat: _egg_layer.add_child(_egg_heartbeat)
	_tick_egg()

## 대기 중 알 고유 애니메이션(원작 setDragonInfo 끝의 3개 RepeatForever).
##   본체 = 숨쉬기(1.5↔1.7) · 유령 2겹 = 시차를 두고 부풀며 사라지는 파동.
func _egg_wait_anim() -> void:
	if is_instance_valid(_egg_body):
		var t := _egg_body.create_tween().set_loops()
		t.tween_property(_egg_body, "scale", Vector2(1.7, 1.7), 2.0)
		t.tween_property(_egg_body, "scale", Vector2(1.5, 1.5), 1.5)
	# (지연, 되돌아갈 배율, 되돌리는 시간) = 원작 tag1 / tag2
	var spec := [[0.9, 1.6, 0.6], [1.4, 1.7, 0.1]]
	for i in _egg_ghosts.size():
		var g := _egg_ghosts[i]
		var s: Array = spec[i]
		var t2 := g.create_tween().set_loops()
		t2.tween_interval(float(s[0]))
		t2.tween_property(g, "modulate:a", 100.0 / 255.0, 0.1)
		t2.tween_property(g, "scale", Vector2(2.3, 2.3), 0.9)
		t2.parallel().tween_property(g, "modulate:a", 0.0, 0.9)
		t2.tween_property(g, "scale", Vector2(float(s[1]), float(s[1])), float(s[2]))

## 강화알(+N) 오라 — 원작 `common/ani_egg_up1_1~6` 6프레임 × 0.15s.
##
## 원작은 이걸 **nest1 의 자식**으로 `anchor(0.5,0)`, `position(nestW/2, 60)`, `setScale(1.1)`,
## `z=-1` 에 붙인다. nest1 은 `contentSize 184px = 245.3pt`(트림 전 캔버스) 에 배율 1.5 이므로
## 레이어 좌표로 풀면 y = 115 + (60 − 245.3/2)×1.5 = **21** — 즉 짚더미 위치다.
## 배율도 1.1 × 1.5 = 1.65. 부모를 거치지 않고 레이어에 직접 놓아 같은 결과를 낸다.
##
## ⚠️ 원작은 강화 단계별로 `setColor(DAT_029ec7b4/7cc/7c0)` 틴트를 건다. 그 상수는 **.bss**
## (런타임 초기화)라 libgame.so 에서 정적으로 못 읽는다 → 틴트 없이 그린다
## (가방의 같은 오라 `_inv_egg_grade_fx` 도 같은 이유로 틴트가 없다).
const EGG_AURA_OY := 21.0      # 115 + (60 − 245.33/2) × 1.5
func _egg_enhance_aura() -> void:
	var frames: Array = []
	for i in 6:
		var t := AtlasUI.tex("common_ui", "common_ani_egg_up1_%d" % (i + 1))
		if t != null: frames.append(t)
	if frames.is_empty():
		return
	var holder := AtlasUI.spr_cocos("common_ui", "common_ani_egg_up1_1", 1.1 * 1.5, Vector2(0.5, 0))
	if holder == null:
		return
	holder.position = _egg_pt(175, EGG_AURA_OY)
	_egg_layer.add_child(holder)
	var fx: Sprite2D = holder.get_child(0)
	var idx := {"i": 0}
	var apply := func() -> void:
		# 프레임마다 높이가 다르다(62·62·66·68·66·62) — 밑변 정렬을 유지하려면 offset 도 같이 고친다.
		var t: Texture2D = frames[int(idx["i"]) % frames.size()]
		var base: Texture2D = frames[0]
		fx.texture = t
		fx.offset = Vector2(0, (base.get_height() - t.get_height()) * 0.5)
		idx["i"] = int(idx["i"]) + 1
	apply.call()
	var tm := Timer.new(); tm.wait_time = 0.15; tm.autostart = true
	tm.timeout.connect(apply); holder.add_child(tm)

## 원작 `CaveScene::init` 의 정보 판(this+0x258) — 알일 때는 부화 타이머가 들어간다.
## 9patch/dialogue_box(capInsets 20,20,2,2) 180×45 @ (visW*0.5, visH*0.5−137).
func _build_egg_plate() -> void:
	var host := Node2D.new()
	host.position = Vector2(0, (EGG_PLATE_DY + 8.0) / S1080)
	host.scale = Vector2(1.0 / S1080, 1.0 / S1080)
	_stage.add_child(host)
	_egg_plate = Control.new()
	_egg_plate.size = EGG_PLATE_SIZE
	_egg_plate.position = -EGG_PLATE_SIZE * 0.5
	_egg_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(_egg_plate)
	var np := AtlasUI.nine("ninepatch_ui", "9patch_dialogue_box", EGG_PLATE_SIZE, Rect2(20, 20, 2, 2))
	if np: _egg_plate.add_child(np)
	_egg_time_label = Label.new()
	# 원작 this+0x260 = font_subtitle BMFont ×0.9 → 19px 비트맵 ×4/3×0.9 ≈ 23pt.
	_lvup_bm_style(_egg_time_label, 23, Color(1, 1, 1), "font_subtitle")
	_egg_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_egg_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_egg_time_label.size = EGG_PLATE_SIZE
	# 원작 라벨 x = boxW/2 + 5 — 왼쪽 다이아 버튼 자리만큼 밀려 있다(완료 시 정중앙으로 돌아온다).
	_egg_time_label.position = Vector2(5, 0)
	_egg_plate.add_child(_egg_time_label)
	# tag5 = common/charge(다이아 즉시 부화) ×1.3 @ 판 좌변 중앙.
	_egg_dia_btn = Control.new()
	_egg_dia_btn.size = Vector2(40, 40)
	_egg_dia_btn.position = Vector2(-20, EGG_PLATE_SIZE.y * 0.5 - 20.0 + 2.0)
	_egg_plate.add_child(_egg_dia_btn)
	var chg := AtlasUI.spr("common_ui", "common_charge", Design.ASSET_SCALE * 1.3)
	if chg:
		chg.position = _egg_dia_btn.size * 0.5
		_egg_dia_btn.add_child(chg)
	var db := Button.new()
	db.flat = true; db.size = _egg_dia_btn.size
	db.pressed.connect(_on_egg_dia)
	_egg_dia_btn.add_child(db)

## 원작 `countDownFatigue` — 매 초 남은 시간 갱신. 0 이 되면 "완료" 상태로 전환한다.
## (⚠️ 원작은 여기서 부화시키지 않는다 — **탭해야** 부화한다. 종전 구현은 자동 부화였다.)
func _tick_egg() -> void:
	if not is_instance_valid(_egg_layer) or _egg_uid == 0:
		return
	var d := UserDB.get_dragon(_egg_uid)
	if d.is_empty() or not UserDB.is_egg(d):
		return
	var remain := UserDB.hatch_remain(d)
	if remain <= 0:
		if not _egg_done:
			_egg_reach_complete()
		return
	if is_instance_valid(_egg_time_label):
		_egg_time_label.text = Hatchery.format_remain(remain)
	var tm := Timer.new(); tm.wait_time = 1.0; tm.one_shot = true; tm.autostart = true
	tm.timeout.connect(func():
		tm.queue_free()
		_tick_egg())
	_egg_layer.add_child(tm)

## 원작 `countDownFatigue` 의 완료 분기 — 라벨을 "완료"로, 다이아 버튼과 펄스 유령을 제거하고
## 알을 ScaleTo(0.5, 1.5) 로 키운 뒤 `setActionEgg` 루프에 넘긴다. 그리고 탭 영역을 연다.
func _egg_reach_complete() -> void:
	_egg_done = true
	if is_instance_valid(_egg_time_label):
		_egg_time_label.text = "완료"                  # 원작 문자열 키 `complete`
		_egg_time_label.position = Vector2.ZERO       # 원작: 판 정중앙으로 되돌린다
	if is_instance_valid(_egg_dia_btn):
		_egg_dia_btn.queue_free(); _egg_dia_btn = null
	for g in _egg_ghosts:
		if is_instance_valid(g): g.queue_free()
	_egg_ghosts.clear()
	if not is_instance_valid(_egg_body):
		return
	var body := _egg_body
	var t := body.create_tween()
	t.tween_property(body, "scale", Vector2(1.5, 1.5), 0.5)
	t.tween_callback(func(): _egg_action_loop(body))
	# 원작 CCMenuItem CCSize(250,300) @ 레이어 중앙 → onClickFatigue.
	var hit := Button.new()
	hit.flat = true
	hit.size = Vector2(250, 300)
	hit.position = _egg_pt(175, EGG_LAYER_SIZE.y * 0.5) - hit.size * 0.5
	hit.pressed.connect(_on_egg_tap)
	_egg_layer.add_child(hit)

## 원작 `CaveScene::setActionEgg` — 완료 상태 알의 고유 애니메이션(무한 반복).
## 스큐 진동 2회 → 큰 흔들림+감쇠 → 웅크렸다 뛰는 점프 2회 → 착지 여진.
## ScaleBy 누적곱이 x·y 모두 정확히 1.0, MoveBy 합이 0 이라 닫힌 루프다.
func _egg_action_loop(n: Node2D) -> void:
	var home: Vector2 = n.get_meta("home", n.position)
	var s := Vector2(1.5, 1.5)                 # ScaleTo(0.5, 1.5) 직후 상태
	var t := n.create_tween().set_loops()
	_egg_action_tw = t
	t.tween_interval(0.25)
	for _pass in 2:
		for v in [-2.0, 1.5, -1.0, 0.5, 0.0]:
			t.tween_property(n, "skew", deg_to_rad(v), 0.05)
		t.tween_interval(0.5)
	for v in [5.0, -5.0, 5.0, -5.0, 5.0, -5.0, 4.0, -3.0, 2.0, -1.0, 0.0]:
		t.tween_property(n, "skew", deg_to_rad(v), 0.05)
	t.tween_interval(0.5)
	for _jump in 2:
		s *= Vector2(1.1, 0.8)                                  # 웅크림
		t.tween_property(n, "scale", s, 0.25)
		t.tween_callback(func(): Bgm.sfx(EGG_BEAT_SFX))
		s *= Vector2(0.81818175, 1.25)                          # 도약(위로 100 + 늘어남)
		t.tween_property(n, "position:y", home.y - 100.0, 0.1).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(n, "scale", s, 0.1)
		s *= Vector2(1.1111112, 1.0)
		t.tween_property(n, "scale", s, 0.1)
		var s1 := s * Vector2(0.9, 1.1)                         # 낙하(아래로 100)
		var s2 := s1 * Vector2(1.1111112, 0.9090909)
		s = s2
		t.tween_property(n, "position:y", home.y, 0.25).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(n, "scale", s1, 0.15)
		t.parallel().tween_property(n, "scale", s2, 0.1).set_delay(0.15)
	for m in [Vector2(1.05, 0.9), Vector2(0.9047619, 1.1666666), Vector2(1.0526316, 0.952381)]:
		s *= m
		t.tween_property(n, "scale", s, 0.1)

## 원작 `onClickFatigue`(tag≠5) — 완료 상태의 알을 탭했다. 정렬 모션 후 부화 연출로 넘어간다.
func _on_egg_tap() -> void:
	if _egg_busy or not _egg_done or not is_instance_valid(_egg_body):
		return
	_egg_busy = true
	Bgm.sfx("effect_button")
	var n := _egg_body
	# 원작 `stopAllActions()` — Godot 트윈은 노드에 새 트윈을 붙여도 기존 것이 계속 돈다.
	if _egg_action_tw != null and _egg_action_tw.is_valid():
		_egg_action_tw.kill()
	var tw := n.create_tween()
	var home: Vector2 = n.get_meta("home", n.position)
	# Spawn(SkewTo .2 → 0, ScaleTo .2 → 1.5, MoveTo .2 → 제자리, ScaleBy .2 (0.95,1.05))
	var s := Vector2(1.5, 1.5) * Vector2(0.95, 1.05)
	tw.tween_property(n, "skew", 0.0, 0.2)
	tw.parallel().tween_property(n, "position", home, 0.2)
	tw.parallel().tween_property(n, "scale", s, 0.2)
	s *= Vector2(1.1052631, 0.9047619)
	tw.tween_property(n, "scale", s, 0.2)
	s *= Vector2(0.952381, 1.0526316)      # → 정확히 (1.5, 1.5)
	tw.tween_property(n, "scale", s, 0.2)
	tw.tween_callback(func(): _hatch_ceremony(_egg_uid))

## 원작 `onClickFatigue`(tag==5) → `onClickEggDia` — 다이아로 즉시 부화.
## 문구는 원작 문자열 키 `CaveDiaBronMsg1` 그대로(`%1$s` = 공백 없는 남은 시간 표기).
func _on_egg_dia() -> void:
	if _egg_busy or _egg_done or _egg_uid == 0:
		return
	var d := UserDB.get_dragon(_egg_uid)
	if d.is_empty(): return
	var remain := UserDB.hatch_remain(d)
	var msg := "알 부화까지 %s 남았습니다.\n알을 즉시 부화시키겠습니까?\n\n다이아 %d개" % [
		Hatchery.format_remain_compact(remain), EGG_DIA_COST]
	_open_popup_type("즉시 부화", msg, func():
		if UserDB.currency("diamond") < EGG_DIA_COST:
			_toast("다이아가 부족합니다"); return
		UserDB.add_currency("diamond", -EGG_DIA_COST)
		UserDB.set_hatch_now(_egg_uid)
		_tick_egg())

# ---------- 부화 연출(원작 sResultEgg) ----------

## 원작 `CaveScene::sResultEgg` 1:1. 빛기둥 스파인 + 성급 카운트업 + 화이트아웃 + 닉네임 팝업.
## 데이터 확정(UserDB.hatch_egg)은 **화면이 완전히 흰 순간**에 한다 — 원작도 스크롤 목록 갱신을
## 3.5초(=흰 화면 아래)에 건다. 그래야 `_refresh()` 가 연출 노드를 지워도 보이지 않는다.
func _hatch_ceremony(uid: int) -> void:
	var d := UserDB.get_dragon(uid)
	if d.is_empty():
		_egg_busy = false; return
	var grade := float(d.get("egg_grade", Growth.BASE_GRADE))
	var blessed := bool(d.get("egg_blessed", false))

	# ① 빛기둥 스파인 — 원작 리터럴 그대로. ⚠️ 이 스켈레톤은 **이미 포인트 단위**라
	#    Design.ASSET_SCALE 을 또 곱하지 않는다(포팅 카드 §6.2).
	var beam_scale := 0.7 if int(d.get("id", 0)) == 23 else 0.93
	if is_instance_valid(_egg_layer) and ResourceLoader.exists("res://scenes/fx/egglight.tscn"):
		var holder := Node2D.new()
		holder.position = _egg_pt(EGG_LAYER_SIZE.x * 0.5 - 7.0, EGG_LAYER_SIZE.y * 0.5 - 100.0)
		holder.scale = Vector2(beam_scale, beam_scale)
		holder.z_index = 5
		_egg_layer.add_child(holder)
		var inst = load("res://scenes/fx/egglight.tscn").instantiate()
		holder.add_child(inst)
		var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		if ap and ap.has_animation("egglight"):
			ap.get_animation("egglight").loop_mode = Animation.LOOP_NONE
			ap.play("egglight")
		var ht := holder.create_tween()
		ht.tween_interval(4.5)
		ht.tween_property(holder, "modulate:a", 0.0, 0.5)
		ht.tween_callback(func(): if is_instance_valid(holder): holder.queue_free())
	# ② 타격음 8발(원작 CCCallFunc 시퀀스의 간격 그대로)
	var beat_t := 0.0
	for i in EGG_BEAT_DELAYS.size():
		beat_t += float(EGG_BEAT_DELAYS[i])
		if i < 2:
			continue          # 앞 2개는 다른 람다(A/B) — 타격음은 3번째부터 8발
		var when := beat_t
		var bt := create_tween()
		bt.tween_interval(when)
		bt.tween_callback(func(): Bgm.sfx(EGG_BEAT_SFX))
	# ③ 성급 카운트업
	_egg_rating_counter(grade, blessed)
	# ④ 화이트아웃 → 데이터 확정 → 닉네임 팝업
	var cl := CanvasLayer.new(); cl.layer = 80; add_child(cl)
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_STOP     # 원작 disableAllTouchesWithoutCurrentLayer
	cl.add_child(flash)
	var ft := flash.create_tween()
	ft.tween_interval(3.0)
	ft.tween_property(flash, "color:a", 1.0, 0.5)
	ft.tween_callback(func():
		UserDB.hatch_egg(uid, Hatchery.stat_bonus_for_grade(grade))
		_egg_uid = 0
		_egg_busy = false
		_refresh())
	ft.tween_interval(0.5)
	ft.tween_property(flash, "color:a", 0.0, 1.0)
	ft.tween_callback(func():
		if is_instance_valid(cl): cl.queue_free()
		_open_rename())

## 원작 `CaveScene::increaseRating` + `sResultEgg` 의 카운터 라벨.
##   font_total BMFont, 화면 중앙에서 scale 0 → 팝인 바운스 → 0.1 씩 0.0125초 간격으로 증가.
##   축복 둥지면 **기본치까지만 세고**(원작 rating−0.6) 보너스를 뒤에 한 번 더 튕겨 보여준다.
##   마지막에 font_combine 로 같은 수치를 한 번 더 띄운다(원작 pVVar39).
func _egg_rating_counter(grade: float, blessed: bool) -> void:
	var vis := _vis()
	var base := grade - (Hatchery.BLESSED_NEST_BONUS if blessed else 0.0)
	var cl := CanvasLayer.new(); cl.layer = 70; add_child(cl)
	var lab := Label.new()
	# font_total 은 `size=93` 비트맵 → 배율 1.0 의 포인트 크기 = 93×4/3 = 124.
	# 원작의 최종 `setScale(0.75)` 은 아래 트윈이 노드 배율로 건다(팝인 바운스와 같은 축).
	_lvup_bm_style(lab, 124, Color(1, 1, 1), "font_total")
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.size = Vector2(400, 160)
	lab.pivot_offset = lab.size * 0.5
	lab.text = "0.0"
	lab.scale = Vector2.ZERO
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 원작: 화면 중앙에서 시작해 center + (0, visH*0.25) 로 이동, 카운트 후 다시 50 위로.
	var start := Vector2(vis.x * 0.5, vis.y * 0.5) - lab.size * 0.5
	var mid := start - Vector2(0, vis.y * 0.25)
	var top := mid - Vector2(0, 50)
	lab.position = start
	cl.add_child(lab)

	var t := lab.create_tween()
	t.tween_property(lab, "position", mid, 0.1)
	t.parallel().tween_property(lab, "scale", Vector2(0.675, 0.825), 0.1)
	t.tween_property(lab, "scale", Vector2(0.825, 0.675), 0.1)
	t.tween_property(lab, "scale", Vector2(0.75, 0.75), 0.1)
	# increaseRating: 0.1 씩 0.0125초. 목표 도달 시 바운스로 마무리.
	var steps := int(ceil(maxf(0.0, base) / 0.1))
	for i in steps:
		var v := minf(base, float(i + 1) * 0.1)
		t.tween_callback(func(): if is_instance_valid(lab): lab.text = "%.1f" % v)
		t.tween_interval(0.0125)
	t.tween_property(lab, "scale", Vector2(0.675, 0.825), 0.1)
	t.tween_property(lab, "scale", Vector2(0.825, 0.675), 0.1)
	t.tween_property(lab, "scale", Vector2(0.75, 0.75), 0.1)
	t.tween_property(lab, "position", top, 0.0)
	if blessed:
		# 원작 nestLevel==1 분기: 잠시 뒤 전체 성급으로 갱신 + 바운스(둥지 보너스 연출).
		t.tween_interval(0.8)
		t.tween_callback(func(): if is_instance_valid(lab): lab.text = "%.1f" % grade)
		t.tween_property(lab, "scale", Vector2(0.675, 0.825), 0.1)
		t.tween_property(lab, "scale", Vector2(0.825, 0.675), 0.1)
		t.tween_property(lab, "scale", Vector2(0.75, 0.75), 0.1)
	t.tween_interval(0.8)
	# 퇴장: 10 내렸다 35 올리며 0.2 초에 페이드아웃 → 그 자리에 font_combine 최종 라벨.
	t.tween_property(lab, "position", top + Vector2(0, 10), 0.1)
	t.parallel().tween_property(lab, "modulate:a", 0.0, 0.2)
	t.tween_property(lab, "position", top - Vector2(0, 25), 0.1)
	t.tween_callback(func():
		if not is_instance_valid(cl): return
		var fin := Label.new()
		# 원작: font_combine 을 **카운터와 같은 높이**로 키운다 —
		#   setScale( h(font_total) / h(font_combine) × 0.75 ) = (112/32)×0.75 = 2.625
		#   ⇒ 포인트 크기 = 26×4/3×2.625 ≈ 91.
		_lvup_bm_style(fin, 91, Color(1, 1, 1), "font_combine")
		fin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fin.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fin.size = lab.size
		fin.position = top
		fin.text = "%.1f" % grade
		fin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.add_child(fin))
	# 화이트아웃이 걷힌 뒤 정리(원작은 흰 레이어와 함께 사라진다).
	var kill := create_tween()
	kill.tween_interval(5.2)
	kill.tween_callback(func(): if is_instance_valid(cl): cl.queue_free())

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

# ---------- 레벨업 화면과 함께 옮겼지만 동굴에도 남는 것 ----------
# 드래곤 음성은 동굴 받침대 클릭(onClickDragon)도 쓰고, 보장 롤 표는 가방 아이템 사용 경로가 쓴다.

const _LVUP_GUARANTEE := {
	"bless_of_dragon": "max1", "bless_of_maia": "max2",
	"bless_of_dersa": "triple", "bless_of_amor": "amor",
}

## 드래곤 보이스 — 성장 단계(baby/child/adult)에 맞는 번호를 `data/dragon_voices.json` 에서 찾는다.
## 원작 표는 유실됐고(`info_dragon_v2` 의 voice 컬럼, Dragon.c:13478-13526),
## **2026-07-31 부터 값은 사용자가 `docs/input/dragons/dragons.csv` 의 voice_해치/해츨링/성체
## 열에 직접 적은 검수분**이다(종전의 블록순차+시드난수 임시배정은 대체됨).
## 반영 도구 = `scripts/tools/build_dragon_voice_sheet.py --apply`. 빈 칸 = 그 단계 소리 없음.
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


# ---------- 원작 BMFont 라벨(레벨업 화면에서 함께 옮겨온 뒤 동굴에도 남긴 공용 서식) ----------
# LevelUpScreen 으로 본체를 뽑아냈지만 이 두 헬퍼는 동굴 카드·목록·이름표도 쓴다.

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


## 원작 레벨업 화면 — **전체화면 오버레이**(팝업 아님). 랜덤롤 §K-1.
##
## 🔀 2026-07-31: 이 화면의 본체(1,127줄, `_open_levelup` + `_lvup_*` 전부)를
##   `scripts/ui/levelup_screen.gd`(`LevelUpScreen`)로 **뽑아냈다.**
##   이유 = 사용자 지시 "탐험 레벨업 팝업이 여전히 자작 기반이야. 축복류 아이템과 똑같은
##   레벨업 팝업을 공유해야 해." 종전엔 탐험/전투가 자작 모달(`LevelUpResult`)을 따로 썼다.
##   원작 근거(ExpLayer 안무·프레임·문자열)는 전부 그 파일로 옮겨 갔다 —
##   docs/ref/porting/LevelUpScreen.md.
## 화면 인스턴스를 돌려준다 — 아이템 사용 경로가 곧바로 연출을 태울 수 있게(`play_fx`).
func _open_levelup() -> LevelUpScreen:
	var a := _active()
	if a.is_empty(): return null
	return LevelUpScreen.open(self, int(a["uid"]), {
		# 열려 있는 동안 동굴 받침대를 숨긴다 — 안 그러면 가운데 드래곤과 화면 좌측 드래곤이
		# **둘 다** 보인다(복구도 LevelUpScreen 이 트리에서 빠질 때 스스로 한다).
		"stage_node": _stage,
		# 성장 단계가 바뀌면(진화) 동굴 받침대와 목록도 새 단계로 다시 그린다.
		"on_evolved": func():
			_refresh_dragon()
			_refresh_list(),
		# 스탯이 바뀌면 동굴 스탯 표시를 갱신한다.
		"on_changed": _refresh_stats,
	})

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
## 이름 바꾸기 **관문** — 상태창 이름판의 깃펜(`common/namepen` → `StatusLayer` 의 "rename")이
## 여기로 온다. 이름 변경은 **드래곤 포스 1개를 소비**한다(사용자 확정 2026-07-31).
##
## 원작 근거 — 이름 변경은 원작에도 있었고, **아이템으로 여는 것**이 원작 방식이다:
##   `BagPopup::onClickDragonNickNameBtn @00e0cc6c` → `DragonNickNamePopup`  = 드래곤 별명
##   `BagPopup::onClickNickNameBtn      @00e0c9f4` → `NickNameLayer`        = 유저 닉네임
##   `BagPopup.c:7243` `case 0x195` 은 **아이템 번호 분기**로 그 레이어를 띄운다(= 아이템 소비 경로).
## 우리 `dragon_namechange`("드래곤 포스", `items.json`)가 그 아이템이다.
##
## ⚠️ 소비는 **여기서만** 한다. 가방에서 드래곤 포스를 쓰는 경로(`_use_item` 의 "rename")는
##    이미 자기가 `use_item` 하고 `_open_rename()` 을 직접 부른다 — 이 관문을 거치지 않으므로
##    이중 차감이 없다. 두 경로 모두 최종 화면은 같은 `_open_rename()`(원작 팝업 이식본)이다.
func _rename_gate() -> void:
	if _active().is_empty():
		return
	var have := UserDB.item_count(RENAME_ITEM)
	var nm := Data.item_name(RENAME_ITEM)
	if have > 0:
		_open_popup_type("이름 바꾸기",
			"%s 1개를 사용하여 이름을 바꿉니다.\n(보유 %d개)" % [nm, have],
			func():
				UserDB.use_item(RENAME_ITEM, 1)
				_refresh()
				_open_rename())
		return
	# 미보유 → 구매 팝업. 가격의 단일 출처는 상점표(`data/shop.json` 만물상 탭)다.
	var price := _shop_price(RENAME_ITEM)
	if price.is_empty():
		_toast("%s 이(가) 필요합니다" % nm)
		return
	var cost := int(price["price"])
	var cur := String(price["cur"])
	var cur_kr := "다이아" if cur == "diamond" else "골드"
	_open_popup_type("%s 구매" % nm,
		"%s%s 없습니다.\n%d %s로 1개를 사시겠습니까?"
			% [nm, _josa_iga(nm), cost, cur_kr],
		func():
			if not UserDB.spend(cur, cost):
				_toast("%s 가 부족합니다" % cur_kr)
				return
			UserDB.add_item(RENAME_ITEM, 1)
			_refresh()
			# 산 김에 바로 이어서 진행한다 — 관문을 다시 타므로 확인 팝업이 한 번 더 뜬다.
			_rename_gate(),
		"구매")


## 이름 변경에 쓰는 아이템(원작 `dragon_namechange` = "드래곤 포스").
const RENAME_ITEM := "dragon_namechange"

## 받침 유무로 이/가. (`adventure.gd::_josa` 와 같은 규칙 — 아이템 이름이 들어가는 문구용)
func _josa_iga(word: String) -> String:
	if word.is_empty():
		return "가"
	var c := word.unicode_at(word.length() - 1)
	if c < 0xAC00 or c > 0xD7A3:
		return "가"
	return "이" if ((c - 0xAC00) % 28) != 0 else "가"

## 상점표에서 아이템 1개 가격을 찾는다 → {price, cur}. 없으면 빈 사전.
## 가격을 코드에 박지 않기 위한 조회다(§8.1 — 수치는 data 소유).
func _shop_price(key: String) -> Dictionary:
	for t in Data.shop.get("tabs", []):
		for it in (t as Dictionary).get("stock", []):
			var e: Dictionary = it
			if String(e.get("item", "")) == key and int(e.get("bundle", 1)) <= 1:
				return {"price": int(e.get("price", 0)), "cur": String(e.get("cur", "gold"))}
	return {}


## 원작 이름표(onClickNicName): 활성 드래곤 별명 설정 팝업. 별명=UserDB에 영속(dragon.nick).
func _open_rename() -> void:
	var a := _active()
	if a.is_empty(): return
	var uid := int(a["uid"])
	var species := Icons.species_name(int(a["id"]))
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
		# 🔴 한글 IME 조합 함정 — `le.text` 를 그냥 읽으면 마지막 글자가 빠진다(TextField 주석).
		UserDB.set_dragon_field(uid, "nick", TextField.value(le))
		UserDB.set_pmeta("name_balloon", bchk.button_pressed)
		pop.queue_free(); _refresh_stats()
	ok.pressed.connect(apply); le.text_submitted.connect(func(_s): apply.call())
	win.add_child(ok)
	var cancel := Button.new(); cancel.text = "취소"; cancel.size = Vector2(220, 56); cancel.position = Vector2(BW * 0.5 + 120 - 110, BH - 75 - 28)
	cancel.pressed.connect(func(): pop.queue_free()); win.add_child(cancel)
	# 버튼이 포커스를 뺏으면 조합이 취소되므로 창 전체를 FOCUS_NONE 으로 만든 뒤 입력칸에 포커스.
	TextField.no_steal(pop)
	le.grab_focus()

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
## **행 수 고정 + 넘치면 가로 스크롤**이 원작 CCTableView 방식이다
## (셀 하나 = 세로 N칸짜리 한 열, `_inventory_refresh_grid` 주석의 근거 3줄).
## 🟦사용자 확정 2026-07-31: **행 수는 4** — 원작 리터럴은 3이지만(`슬롯수/3+1`) 우리 팝업이
##   PC용으로 커서(1780×930) 3행이면 그리드 아래가 휑하다. 3으로 되돌리려면 이 상수만 바꾸면 된다
##   (배경 높이 `INV_GRID_H` 도 같이 = 12 + 행수×150 + 24).
## 7열은 "한 번에 보이는 열 수"일 뿐이라 상수로 두지 않는다(뷰포트 폭 ÷ 칸 폭).
const INV_ROWS := 4
## 그리드 배경(`9patch/scroll_box`) 크기. 세로는 4행이 딱 들어가는 값(12 + 4×150 + 24).
## 바닥 88+636=724 < 탭 스트립 y=760.
const INV_GRID_W := 1050.0
const INV_GRID_H := 636.0

var _inv_tab := "etc"
var _inv_selected := ""
var _item_manifests: Dictionary = {}
var _inv_detail_box: Control
var _inv_grid_box: Control
var _inv_grid_sc: ScrollContainer          # 가로 스크롤(원작 CCTableView 자리)
var _inv_cells: Dictionary = {}            # 인벤키 → 칸 테두리 NinePatch(선택 표시만 바꿔 끼우려고)

# ---------- 상세창(우측) 공통 상수 — 원작 BagPopup 상세 레이어 ----------
## 원작 상세 레이어 크기(`initWidget` BagPopup.c:1794 `CCSize(350, 420)`). 전 탭 공통.
const INV_DETAIL_PANEL := Vector2(350, 420)
## 설명 상자 세로. **원작은 125**(BagPopup.c:1854 = 도감과 같은 340×125)인데, 원작 상세 레이어가
## 우리 상세 상자(560×650)보다 작아 아래가 휑하다 → 🟦사용자 확정(2026-07-31) **2배(250)**.
## 상자 윗변(y=237.5)은 원작 그대로 두고 아래로만 늘린다 — 바닥 487.5 < 실행 버튼 y=520.
## 원작 치수로 되돌리려면 이 상수만 125 로 바꾸면 된다.
const INV_DETAIL_DESC_H := 250.0
## 본문 라벨 색 — 원작 `initWidget` :1916 `setColor(0x1d4381)` = ccColor3B(0x81,0x43,0x1d).
const INV_DESC_COLOR := Color8(129, 67, 29)
## 스킬 모양 → 마크 프레임(원작 `Skill::getSkillType()` 0△ 1□ 2○). ☆(3)는 표에 없어
## `common/element_bg` 로 떨어진다 — 원작이 그렇다(BagPopup.c:12296~12301).
const INV_SKILL_MARK := {
	"tri": "common_skill_triangle_mark",
	"sq": "common_skill_square_mark",
	"cir": "common_skill_circle_mark",
}
## 장비 **주 능력** → 원작 부가효과 문구. 원작은 `Item::getTypeDetail()` 로 `CaveItemEquipComentN`
## (stringsData_KR.xml)을 고르는데, 그 typeDetail 9종이 우리 `equipment.json` stat_keys 와
## 그대로 겹친다. 문구는 원작 문자열 원문 그대로다(`%1$d` → `%d`).
## 표·근거 = docs/ref/porting/BagPopupItemDetail.md §5-1.
const EQUIP_MAIN_COMMENT := {
	"cri": "크리티컬 공격 확률 +%d%%",             # CaveItemEquipComent1
	"evd": "상대공격 회피 확률 +%d%%",             # Coment2
	"cure": "행동불능 치유 확률 +%d%%",            # Coment3
	"cri_pow": "크리티컬 파워 증가 +%d%%",         # Coment4
	"pure": "방어 관통 대미지 +%d",                # Coment5
	"awaken_rate": "각성기 게이지 상승률 +%d%%",   # Coment6
	"depure": "방어 관통 대미지 감소 +%d",         # Coment14
	"accuracy": "명중률 +%d%%",                    # Coment15
}

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

## 그리드 = **3행 고정 · 가로 스크롤**. 원작 그대로다(BagPopup.c):
##   `numberOfCellsInTableView` :2926 → `슬롯수 / 3 + 1`   ⇒ **셀 하나 = 세로 3칸짜리 한 열**
##   `cellSizeForTable`         :1312 → `CCSize(120, 표높이)` ⇒ 셀은 세로로 긴 열
##   `initWidget`               :1774 → `setVerticalFillOrder(0)` + `(vt+0x3d8)(0)` = 가로 방향
## 그래서 아이템이 아래로 무한히 쌓이지 않고 **옆으로 넘어간다**(도감 `_dex_build_grid` 와 같은 꼴).
## 배경도 원작 프레임으로 — `9patch/scroll_box` cap(65,65,6,6) @ (40,40) 크기 (팝업폭−430)×420
## (BagPopup.c:1659~1672). 종전엔 자작 `_panel(ColorRect)` 이었다.
func _inventory_refresh_grid() -> void:
	if _inv_grid_box == null:
		return
	# 다시 그려도 보던 열을 잃지 않게 가로 스크롤 위치를 물려준다.
	var keep_x := int(_inv_grid_sc.scroll_horizontal) if is_instance_valid(_inv_grid_sc) else 0
	for ch in _inv_grid_box.get_children():
		ch.queue_free()
	_inv_cells = {}
	var items := _inventory_items_for_tab(_inv_tab)
	if (_inv_selected == "" or not _inventory_has_item(_inv_selected)) and not items.is_empty():
		_inv_selected = String(items[0])

	var back := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box",
		Vector2(INV_GRID_W, INV_GRID_H), Rect2(65, 65, 6, 6))
	if back:
		back.position = Vector2.ZERO
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_inv_grid_box.add_child(back)

	if items.is_empty():
		var empty := Label.new()
		empty.text = "비어 있음"
		empty.position = Vector2(0, INV_GRID_H * 0.5 - 20.0)
		empty.size = Vector2(INV_GRID_W, 40)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 30)
		empty.add_theme_color_override("font_color", Color(0.95, 0.89, 0.76))
		_inv_grid_box.add_child(empty)
		return

	# 원작 CCTableView 자리 — 배경 안쪽 (10, 5) · 크기 (배경−20, 배경−10)(BagPopup.c:1763~1773).
	var sc := ScrollContainer.new()
	sc.position = Vector2(10, 12)
	sc.custom_minimum_size = Vector2(INV_GRID_W - 20.0, INV_ROWS * INV_SLOT_H)
	sc.size = sc.custom_minimum_size
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inv_grid_box.add_child(sc)
	_inv_grid_sc = sc
	sc.get_h_scroll_bar().modulate.a = 0.0   # 원작 CCTableView 는 스크롤바가 없다(드래그 스크롤)

	var grid := Control.new()
	var cols: int = int(ceil(items.size() / float(INV_ROWS)))
	grid.custom_minimum_size = Vector2(cols * INV_SLOT_W, INV_ROWS * INV_SLOT_H)
	sc.add_child(grid)

	# i번째 아이템 → 열 i/3, 행 i%3 (원작 셀 = 한 열, 그 안에서 위→아래).
	for i in items.size():
		var key := String(items[i])
		var cell := _inventory_cell(key)
		cell.position = Vector2((i / INV_ROWS) * INV_SLOT_W, (i % INV_ROWS) * INV_SLOT_H)
		grid.add_child(cell)
	sc.scroll_horizontal = keep_x

func _inventory_cell(key: String) -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(INV_SLOT_W, INV_SLOT_H)

	# 🟠 2026-07-26 정정: 칸 배경이 자작 `_panel(ColorRect)` 이었다.
	#   원작 가방(docs/ref/orig_image/cave/inven/Cave_inventory.jpg)의 칸은 **어두운 라운드 슬롯**이다 —
	#   레퍼런스 슬롯 내부 픽셀 실측 RGB(58,56,57). 후보 9patch를 뽑아 비교한 결과
	#   `9patch/train_box4`(어두운 라운드)가 일치하고, `bt_itembox_off`는 크림색이라 맞지 않았다.
	#   선택 칸은 `9patch/bt_itembox_on`(노란 하이라이트, 🟠 미사용이던 원본).
	var frame := NinePatchRect.new()
	frame.texture = _inv_slot_frame(key == _inv_selected)
	frame.patch_margin_left = 22; frame.patch_margin_right = 22
	frame.patch_margin_top = 16; frame.patch_margin_bottom = 16
	frame.position = Vector2(4, 4)
	frame.size = Vector2(INV_SLOT_W - 18, 128)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(frame)
	_inv_cells[key] = frame

	var icon := _inventory_item_icon(key, 84.0)
	if icon:
		icon.position = Vector2((INV_SLOT_W - 18) * 0.5 + 4, 58)
		cell.add_child(icon)
		# 강화된 알은 **셀에서부터** 구분된다 — 원작 `BagTableViewCell` 이 같은 `ani_egg_up1` 애니를
		# 셀에 붙인다(BagTableViewCell.c:760~793). 등급별로 칸이 갈리므로(EggItem) 한눈에 보인다.
		_inv_egg_grade_fx(key, icon)
		_inventory_grade_badge(cell, key)

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

## 강화된 알 칸의 `+N` 배지(좌상단).
##
## ⚠️ 원작에 없다 — 원작은 `ani_egg_up1` 애니와 grade 2/3 **색 틴트**만으로 구분한다
##   (BagTableViewCell.c:786~793). 우리는 그 틴트 상수를 못 구했고(.rodata, `_inv_egg_grade_fx` 주석)
##   애니만으로는 1강/2강/3강이 같아 보인다 → 등급 숫자를 글자로 보탠다.
##   틴트 값을 확보하면 이 함수를 지우고 원작대로 색만 입히면 된다.
## 표기는 둥지 배지·연구소 목록과 같은 `+N`(hatchery.gd / laboratory.gd `_owned_egg_grade_entries`).
func _inventory_grade_badge(cell: Control, key: String) -> void:
	var g := EggItem.grade_of(key)
	if g <= 0:
		return
	var l := Label.new()
	l.text = "+%d" % g
	l.size = Vector2(INV_SLOT_W - 18 - 12, 30)
	l.position = Vector2(4 + 6, 4 + 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", Color8(255, 176, 40))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.0))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(l)

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
	# ── 상세창은 **원작 레시피 그대로** 그린다(`BagPopup::onClickItem` 의 탭 switch).
	#    원작 상세 레이어는 도감(`BookPopup` 350×430)과 같은 부품으로 짠 350×420 이고,
	#    **그릇(레이어·이름·그림자·text_box+스크롤)은 전 탭 공통**이다. 그 위에 무엇을 얹는지만
	#    탭마다 갈리며, 갈래는 원작 case 구성과 1:1이다:
	#      case 0 FOOD · case 1 EQUIP · case 2·5·6·7 GEM/DOC/MTR/ETC(원작도 한 덩어리)
	#      case 3 EGG · default(=case 4) SKILL
	#    상세 = docs/ref/porting/BagPopupItemDetail.md (알 탭만 BagPopupEggDetail.md)
	#    🔴 2026-07-31 정정: 알 탭 말고는 전부 자작이었다 — 210px 아이콘·"보유 X n" 배지·
	#      원형 속성판·★ tier·배경 없는 스크롤. 원작엔 어느 탭에도 없는 것들이다.
	var panel := _inv_detail_panel()
	var lines: Array = []
	match _inventory_tab_for_item(_inv_selected):
		"egg":   lines = _inv_detail_egg(panel, _inv_selected, item)
		"food":  lines = _inv_detail_food(panel, _inv_selected, item)
		"skill": lines = _inv_detail_skill(panel, _inv_selected, item)
		"gear":  lines = _inv_detail_equip(panel, _inv_selected, item)
		_:       lines = _inv_detail_plain(panel, _inv_selected, item)
	_inv_detail_desc(panel, lines)
	_inv_detail_actions(item)


## 상세 레이어 = **전 탭 공통 그릇**(원작 `BagPopup::initWidget`, BagPopup.c:1792~1892).
## 원작은 `CCLayer` 350×420 anchor(1,0) @ (팝업우변−30, 40) 이고, 그 안 좌표를 리터럴로 쓴다
## (아래 `(x, y)c` = cocos 좌표, 코드값은 `godot y = 420 − cocos y`).
## 우리 상세 상자(`_inv_detail_box`)는 560×650 이라 그 안에 가로 중앙 정렬해 얹는다
## (하단 실행 버튼 y=520 과 겹치지 않는다 — 패널 바닥은 20+420=440).
func _inv_detail_panel() -> Control:
	var panel := Control.new()
	panel.name = "item_detail"
	panel.size = INV_DETAIL_PANEL
	panel.position = Vector2((_inv_detail_box.size.x - INV_DETAIL_PANEL.x) * 0.5, 20)
	_inv_detail_box.add_child(panel)
	# 그림자 — `common/shadow` @ (175, 210)c, z=0 tag=7 (아이템 그림보다 뒤)
	var sh := AtlasUI.spr("common_ui", "common_shadow", Design.ASSET_SCALE)
	if sh:
		sh.position = Vector2(175, 210)
		panel.add_child(sh)
	return panel


## 이름 라벨 — 원작 `this+0x300` CCLabelBMFontEx(font_subtitle) ×0.8 @ (175, 410)c.
## 색은 기본 흰색이고 **EQUIP 탭만** 희귀도 색으로 물들인다(BagPopup.c:11446).
func _inv_detail_name(panel: Control, text: String, col := Color.WHITE) -> void:
	var nm := _book_label(text, 0.8, col)
	_book_center(nm, Vector2(175, 10), 340)
	panel.add_child(nm)


## 아이템 그림 — 원작 `CCSprite::createWithSpriteFrameName(Item::getImage())`.
## 아틀라스 프레임은 디자인 공간에서 **원래 크기**(×`Design.ASSET_SCALE`, §9)로 그려야 하고,
## `mult` 는 그 위에 곱하는 원작 `setScale`(EQUIP·SKILL 은 1.3).
func _inv_detail_art(key: String, mult := 1.0) -> Sprite2D:
	var spr := _inventory_item_icon(key, 100.0)   # 폭은 아래에서 덮어쓴다
	if spr == null:
		return null
	var s := Design.ASSET_SCALE * mult
	spr.scale = Vector2(s, s)
	return spr


## 설명 상자 — 원작 `9patch/text_box` cap(25,25,3,3) **340×125** @ (175, 120)c +
## 그 안 `ScrollViewEx` 320×105 (BagPopup.c:1850~1906). 본문 라벨은 `this+0x310`
## CCLabelBMFontEx ×0.8 · 색 `#81431D`(:1916 `0x1d4381` = R81 G43 B1D).
##
## `lines` 항목은 세 가지다:
##   String                      → 본문 스타일 한 줄
##   {"text":…, "color":…}       → 색 지정 한 줄(희귀도 라벨 등)
##   [{"text":…,"color":…}, …]   → 한 줄에 나란히(원작 등급 라벨 옆 귀속 라벨)
func _inv_detail_desc(panel: Control, lines: Array) -> void:
	var tb := AtlasUI.nine("ninepatch_ui", "9patch_text_box",
		Vector2(340, INV_DETAIL_DESC_H), Rect2(25, 25, 3, 3))
	if tb:
		tb.position = Vector2(5, 237.5)
		panel.add_child(tb)
	var tsc := ScrollContainer.new()
	tsc.position = Vector2(15, 247.5)
	tsc.size = Vector2(320, INV_DETAIL_DESC_H - 20.0)
	tsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(tsc)
	var tbox := VBoxContainer.new()
	tbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tbox.add_theme_constant_override("separation", 6)
	tsc.add_child(tbox)
	for line in lines:
		if typeof(line) == TYPE_ARRAY:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for part in (line as Array):
				var pl := _inv_desc_label(String((part as Dictionary).get("text", "")),
					(part as Dictionary).get("color", INV_DESC_COLOR), 0.0)
				row.add_child(pl)
			tbox.add_child(row)
			continue
		var txt := String(line.get("text", "")) if typeof(line) == TYPE_DICTIONARY else String(line)
		if txt == "":
			continue
		var col: Color = line.get("color", INV_DESC_COLOR) if typeof(line) == TYPE_DICTIONARY \
			else INV_DESC_COLOR
		tbox.add_child(_inv_desc_label(txt, col, 300.0))


## 본문 서체·색은 도감 설명과 같게 맞춘다(`_dex_refresh_panel` 참조 — subtitle 로 그리면
## 원작보다 획이 두껍다는 사용자 보고 2026-07-30 이후 `font_common`).
func _inv_desc_label(txt: String, col: Color, wrap_w: float) -> Label:
	var l := Label.new()
	l.text = txt
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if wrap_w > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(wrap_w, 0)
	_lvup_bm_style(l, int(round(17.0 * Design.ASSET_SCALE * 0.8)), col, "font_common")
	return l


## 본문 기본 줄 — [우리 요약(`_inventory_item_desc`)] → [`Item::getComment()` = items.json `desc`].
## 원작은 comment 한 줄만 넣지만, 우리 요약(젬 효과·장비 주능력·용도·미구현 표시)은
## **원작 그릇 안에 유지**한다(🟦사용자 확정 2026-07-31).
func _inv_detail_lines(key: String, item: Dictionary) -> Array:
	return [_inventory_item_desc(key, item), String(item.get("desc", ""))]


## 원작 `onClickItem` **case 2·5·6·7**(젬 / 문서 / 재료 / 기타) — BagPopup.c:11556~11710.
## 원작에서도 네 탭이 **같은 case 블록**이고, 그리는 것은 **그림 + 이름 + 설명뿐**이다.
## 속성 아이콘·★ 등급·유형 명찰은 이 탭들에 **없다**(그건 알 탭 전용). 🟦사용자 확정 2026-07-31.
func _inv_detail_plain(panel: Control, key: String, item: Dictionary) -> Array:
	_inv_detail_name(panel, _inventory_item_name(key))
	var icon := _inv_detail_art(key)
	if icon:
		icon.position = Vector2(175, 130)      # cocos (w/2, h/2+80) = (175, 290)
		panel.add_child(icon)
	# ⚪ 조합서 뱃지(원작: `getTypeDetail()=="RECIPE"` 면 대상 알의 `getImageSmall()` 을
	#   아이템 그림의 자식으로 ×0.8, BagPopup.c:11624~11645)는 미구현 —
	#   `Item::getTypeParam()` = 서버 `info_item` 이라 조합서 5종이 어느 알인지 모른다.
	return _inv_detail_lines(key, item)


## 원작 `onClickItem` **case 0(FOOD)** — BagPopup.c:9966~10370.
## 그림 + **속성 아이콘** + 이름 + 설명. 별·유형 명찰·등급 라벨은 없다.
func _inv_detail_food(panel: Control, key: String, item: Dictionary) -> Array:
	_inv_detail_name(panel, _inventory_item_name(key))
	var icon := _inv_detail_art(key)
	if icon:
		icon.position = Vector2(175, 130)
		panel.add_child(icon)
	# 속성 아이콘 @ (60, h−50)c = (60, 50) · ×0.55 · z=1 tag=4.
	# 원작 조건 = `Item::getTypeDetail()` 이 `RECOVER_<속성>`(9자)이거나 속성 한 글자일 때만
	# (BagPopup.c:10004~10295). 우리 대응은 items.json `element` 유무(= 속성 먹이 18종).
	var ev = item.get("element")
	var ekey := String(DEX_ELE_ICON.get(String(ev) if typeof(ev) == TYPE_STRING else "", ""))
	if ekey != "":
		var ei := AtlasUI.spr("item_small_ui", ekey, Design.ASSET_SCALE * 0.55)
		if ei:
			ei.position = Vector2(60, 50)
			panel.add_child(ei)
	return _inv_detail_lines(key, item)


## 원작 `onClickItem` **default(= case 4 SKILL)** — BagPopup.c:12253~12436.
## 스킬 그림 ×1.3 + **모양 마크** + 이름 + 설명.
func _inv_detail_skill(panel: Control, key: String, item: Dictionary) -> Array:
	_inv_detail_name(panel, _inventory_item_name(key))
	var icon := _inv_detail_art(key, 1.3)      # 원작 setScale(1.3)
	if icon:
		icon.position = Vector2(175, 130)
		panel.add_child(icon)
	# 모양 마크 @ (60, h−50)c · z=1 tag=5. 원작은 ○□△만 전용 프레임을 쓰고
	# **☆(type 3)는 `common/element_bg`** 로 떨어진다 — `common/skill_star_mark` 를
	# 보유하고 있는데도 그렇다(BagPopup.c:12286~12303). 원작 그대로 둔다.
	var mark := String(INV_SKILL_MARK.get(String(item.get("subcategory", "")), "common_element_bg"))
	var mk := AtlasUI.spr("common_ui", mark, Design.ASSET_SCALE)
	if mk:
		mk.position = Vector2(60, 50)
		panel.add_child(mk)
	# ⚪ 속성 아이콘(원작: `Skill::getAttribute()` 첫 글자 → `ele_*` ×0.55 @ (60, h−110)c)은
	#   미구현 — data/skills.json 39종에 속성 열이 없다(전부 null).
	return _inv_detail_lines(key, item)


## 원작 `onClickItem` **case 1(EQUIP)** — BagPopup.c:10371~11555.
## 희귀도 실루엣 + 장비 그림(둘 다 ×1.3) + 이름(+강화) + [등급] · 귀속 · 부가효과 줄.
## 개체 정보(귀속·희귀도·강화·옵션)는 인벤 키에 실려 있다(`Equipment.item_key_meta`).
func _inv_detail_equip(panel: Control, key: String, item: Dictionary) -> Array:
	var S := Design.ASSET_SCALE
	var meta: Dictionary = Equipment.item_key_meta(key)
	var rar := int(meta.get("rarity", 0))
	var col: Color = Icons.rarity_color(rar)
	# 희귀도 실루엣 — 원작 `Equip::getGradeImageSprite(0)` = `<아이콘>_bg.png` + 희귀도 색
	# (Equip.c:2653~2732). ×1.3 · z=0 **tag=3**(장비 그림보다 뒤). 일반(1)은 안 그린다.
	var bgt := Icons.equip_bg_texture(item)
	if bgt != null and col.a > 0.0:
		var bs := Sprite2D.new()
		bs.texture = bgt
		bs.material = _pma
		bs.scale = Vector2(S * 1.3, S * 1.3)
		bs.modulate = col
		bs.position = Vector2(175, 130)
		panel.add_child(bs)
	var icon := _inv_detail_art(key, 1.3)
	if icon:
		icon.position = Vector2(175, 130)
		panel.add_child(icon)
	# 이름 = `Item::getName()` + 강화 횟수 `" +%d"`(`Equip::getUpGrade`, BagPopup.c:10454~10464),
	# 라벨 색은 희귀도 색(:11446).
	var nm := _inventory_item_name(key)
	var enh := int(meta.get("enhance", 0))
	if enh > 0:
		nm += " +%d" % enh
	_inv_detail_name(panel, nm, col if col.a > 0.0 else Color.WHITE)

	var lines: Array = []
	# 등급 라벨(`this+0x308` "[  ]")과 귀속 라벨(`this+0x2f8` TTF, 색 #FF431D)은 원작에서
	# 스크롤 안 **본문 위 같은 줄**에 나란히 놓인다(BagPopup.c:1936~1967) → HBox 한 줄로.
	var head: Array = []
	var grades: Array = Data.equipment.get("option", {}).get("grades", [])
	if rar > 0 and rar < grades.size():
		head.append({"text": "[%s]" % String((grades[rar] as Dictionary).get("name", "")),
			"color": col if col.a > 0.0 else INV_DESC_COLOR})
	# 귀속 문구는 원작 문자열 그대로 — `CaveItemEquipBeing` = "~의 귀속 아이템".
	var bel := int(meta.get("belong", 0))
	if bel > 0:
		head.append({"text": "-%s의 귀속 아이템" % _dragon_label(bel), "color": Color8(255, 67, 29)})
	if not head.is_empty():
		lines.append(head)
	# 부가효과 줄 — 원작은 `Item::getTypeDetail()` 로 `CaveItemEquipComentN` 을 고른다.
	# 우리 대응 키는 **주 능력 스탯**이다(equipment.json stat_keys 가 원작 typeDetail 과 겹친다).
	for st: String in (item.get("stat_main", {}) as Dictionary):
		var fmt := String(EQUIP_MAIN_COMMENT.get(st, ""))
		lines.append(fmt % int(item["stat_main"][st]) if fmt != "" \
			else "%s +%d" % [_equip_stat_kr(st), int(item["stat_main"][st])])
	# 부가옵션 줄 — 원작 `Equip::getOption()` 요약(BagPopup.c:11130~11196).
	var opts: Array = meta.get("options", [])
	if not opts.is_empty():
		var op: PackedStringArray = []
		for o in opts:
			op.append("%s+%d" % [_equip_stat_kr(String((o as Dictionary).get("stat", ""))),
				int((o as Dictionary).get("value", 0))])
		lines.append("부가옵션: %s" % " ".join(op))
	if String(item.get("artifact_effect", "")) != "":
		lines.append(String(item["artifact_effect"]))
	if String(item.get("bonus", "")) != "":
		lines.append(String(item["bonus"]))
	lines.append(String(item.get("desc", "")))
	return lines


## 원작 `StarclassLayer` 1:1(StarclassLayer.c 전문 해독) — 성급 별 나열 + 등장 연출.
##
## 원작: 레이어 **175×25** anchor(0.5,0.5) 에 7행(성급 1~7)을 전부 만들어 두고 `on(n,…)` 이
##   n−1 행만 켠다. r행 i번째 별 = `common/eggclass`, `x = w/2 − starW/2·r + starW·i` · `y = h/2`
##   ⇒ 레이어 중심 기준 `x_i = starW·(i − r/2)`. 우리는 필요한 행만 만든다(보이는 결과는 동치).
## 등장(`on(n, true)`): 별마다 `Delay(0.1·i)` → `[RotateBy 180° 0.25s + ScaleTo(0.25, 1.0)]`
##   → `ScaleTo(0.1, 0.9/1.1)` → `(0.1, 1.1/0.9)` → `(0.1, 1.0)`.
##
## 반환 노드의 원점 = 레이어 **중심**(원작 anchor 0.5,0.5 와 같게 두려고).
func _starclass_layer(star: int, animate := true) -> Node2D:
	var root := Node2D.new()
	root.name = "starclass"
	if star <= 0:
		return root
	var S := Design.ASSET_SCALE
	var sw := AtlasUI.size_pt("common_ui", "common_eggclass").x
	for i in star:
		var st := AtlasUI.spr("common_ui", "common_eggclass", S)
		if st == null:
			break
		st.position = Vector2(sw * (i - (star - 1) * 0.5), 0)
		root.add_child(st)
		if not animate:
			continue
		st.scale = Vector2.ZERO
		var tw := st.create_tween()
		tw.tween_interval(0.1 * i)
		tw.tween_property(st, "rotation_degrees", 180.0, 0.25).as_relative()
		tw.parallel().tween_property(st, "scale", Vector2(S, S), 0.25)
		tw.tween_property(st, "scale", Vector2(S * 0.9, S * 1.1), 0.1)
		tw.tween_property(st, "scale", Vector2(S * 1.1, S * 0.9), 0.1)
		tw.tween_property(st, "scale", Vector2(S, S), 0.1)
	return root


## 원작 `BagPopup::onClickItem` **case 3(EGG 탭)** 이식 — 가방 알 상세창.
##
## 원작 상세 레이어는 **350×420**(`initWidget` BagPopup.c:1793~1890)이고, 도감 `BookPopup`
## (350×430, BookPopup.c:1197)과 **같은 부품**(StarclassLayer · common/shadow · 9patch/text_box
## 340×125 · item_small/ele_* · 9patch/recall_del)으로 짜여 있다. 그래서 좌표 리터럴을 원작
## 그대로 쓴다 — 아래 주석의 `(x, y)c` 는 cocos 좌표, 코드값은 `godot y = 420 − cocos y`.
## 근거·좌표표 전문 = `docs/ref/porting/BagPopupEggDetail.md`.
##
## 그릇(레이어 350×420 · 이름 · 그림자 · 설명 상자)은 `_inv_detail_panel`/`_inv_detail_desc` 가
## 전 탭 공통으로 만든다 — 이 함수는 **알 전용 표시물**(별·알 그림·강화 이펙트·속성·유형 명찰)만 얹고
## 설명 줄을 돌려준다. 다른 탭 갈래는 `docs/ref/porting/BagPopupItemDetail.md`.
func _inv_detail_egg(panel: Control, key: String, item: Dictionary) -> Array:
	var S := Design.ASSET_SCALE

	# 원작은 `Egg::create(itemNo)` 로 알 객체를, 성급·유형은 `Dragon::create(itemNo)` 로 얻는다.
	# 우리 알은 가상 키 `egg:<드래곤id>`(EggGacha) 또는 items.json 알 아이템이다.
	var did := int(item.get("dragon_id", 0))
	var d: Dictionary = Data.get_dragon(did) if did > 0 else {}

	# ① 이름 — `Egg::getName()` → this+0x300 라벨 @ (175, 410)c · font_subtitle ×0.8
	_inv_detail_name(panel, _inventory_item_name(key))

	# ② 별 — `Dragon::getDragonStarClass()` → `StarclassLayer::on(n, true)`, 이름 −(0,35).
	#    ⚠️ 원작은 드래곤이 정해지지 않은 특수 알(itemNo 1001·1008·1020 = 의문의 알 계열)에서
	#    `StarclassLayer::off(0)` 로 **별을 끈다**(BagPopup.c:11894/11950/12005). 우리도 같다 —
	#    뽑기 알은 `dragon_id` 가 없어 자연히 이 분기로 떨어진다.
	var star := int(d.get("star", 0))
	if star > 0:
		var sc := _starclass_layer(star)
		sc.position = Vector2(175, 45)
		panel.add_child(sc)

	# ④ 알 그림 — `Egg::getImage()` = `dragon/dragon_<id>/egg.png` @ (175, 290)c, z=0 tag=2
	var egg: Sprite2D = null
	var etex: Texture2D = Icons.dragon_egg_texture(did) if did > 0 else null
	if etex != null:
		egg = Sprite2D.new()
		egg.texture = etex
		egg.material = _pma
		egg.scale = Vector2(S, S)
	else:
		# 드래곤이 정해지지 않은 알(의문의 알·속성알) — 원작도 Item 아이콘을 그린다.
		# 원작과 같이 **원래 크기**(×ASSET_SCALE)로 그리려고 프레임 폭을 매니페스트에서 읽는다
		# (`_inventory_item_icon` 은 목표 폭을 받는다 → 폭×S 를 넘기면 배율이 정확히 S 가 된다).
		var ipath := String(item.get("icon", ""))
		var islash := ipath.find("/")
		var iw := 0.0
		if islash > 0:
			iw = float(_item_manifest(ipath.substr(0, islash))
				.get(ipath.substr(islash + 1), {}).get("w", 0))
		egg = _inventory_item_icon(key, (iw if iw > 0.0 else 110.0) * S)
	if egg:
		egg.position = Vector2(175, 130)
		panel.add_child(egg)
		_inv_egg_grade_fx(key, egg)

	# ⑥ 속성 아이콘 — `Egg::getGroup()` 첫 글자 → `item/item_small/ele_*` ×0.55 @ (60, h−50)c.
	#    ⚠️ 원작에는 `common/element_bg` 원판이 **없다**(종전 자작). 아이콘 단독이다.
	var el := String(item.get("element", "")) if typeof(item.get("element")) == TYPE_STRING else ""
	var ekey := String(DEX_ELE_ICON.get(el, ""))
	var eih := 0.0
	if ekey != "":
		var ei := AtlasUI.spr("item_small_ui", ekey, S * 0.55)
		if ei:
			ei.position = Vector2(60, 50)
			panel.add_child(ei)
			eih = AtlasUI.size_pt("item_small_ui", ekey).y * 0.55

	# ⑦ 유형 명찰 — `9patch/recall_del` 70×30 anchor(0.5,1) 아이콘 바로 아래 + 라벨 ×0.7.
	#    원작 조건: **속성 아이콘을 실제로 그렸고** `Dragon::getType() != -1` 일 때만(BagPopup.c:12106).
	var tname := String(DEX_TYPE_KR.get(String(d.get("type", "")), ""))
	if eih > 0.0 and tname != "":
		var fs := int(round(19.0 * S * 0.7))
		var tw := maxf(70.0, _lvup_bmfont("font_subtitle").get_string_size(
			tname, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10.0)
		var tag := AtlasUI.nine("ninepatch_ui", "9patch_recall_del", Vector2(tw, 30))
		if tag:
			tag.position = Vector2(60 - tw * 0.5, 50 + eih * 0.5 + 3.0)
			panel.add_child(tag)
		var tl := _book_label(tname, 0.7)
		_book_center(tl, Vector2(60, 50 + eih * 0.5 + 3.0 + 15.0), 120)
		panel.add_child(tl)

	# ⑧ 설명 — 상자·스크롤은 `_inv_detail_desc`(전 탭 공통)가 그린다. 원작은 여기에
	#    `Item::getComment()`(서버 info_item.comment) 한 줄을 넣는데 우리 알은 두 갈래다:
	#   · 가상 키 `egg:<드래곤id>` — items.json 항목이 아니라 comment 자체가 없다 →
	#     **도감과 같은 종 설명**(`Data.dragon_comment`)을 쓴다. 도감도 같은 text_box 에 이걸 넣는다.
	#     (종전엔 `_inventory_item_desc` 가 "드래곤 ID: 1" 을 찍었다 — 이름·그림·별로 이미 아는 것이다.)
	#   · items.json 알 아이템(의문의 알 등) — `desc`(= 원작 comment)와 용도 요약을 그대로.
	var lines: Array = []
	if did > 0:
		lines.append(Data.dragon_comment(did))
	else:
		lines.append_array(_inv_detail_lines(key, item))
	lines.append(_inv_egg_grade_text(key))

	# 보유 수량 — 원작 상세 레이어에는 없다(원작은 셀 우하단 배지로 보여 준다). 우리 가방 셀에도
	# 같은 배지가 있으므로 상세엔 두지 않는다(종전의 "보유 X n" 배지 제거).
	return lines


## 알 강화 이펙트 — 원작 `BagPopup::onClickItem` case 3 (BagPopup.c:11772~11818):
##   `Egg::getGrade() > 0` 이면 `common/ani_egg_up1_1~6` 6프레임을 **0.15s 간격 무한 반복**하고
##   알 스프라이트의 **자식**(z=1)으로 anchor(0.5, 0) · scale 1.2 · `(eggW/2, 5)` 에 붙인다.
##
## 같은 애니를 **가방 그리드 셀**도 쓴다(원작 `BagTableViewCell` — 거기서도 grade 2/3 에 색을 입힌다,
## BagTableViewCell.c:760~793). 그래서 이 함수는 상세창·셀 양쪽에서 호출한다.
##
## ⚠️ 원작과 다른 1건(근거 있음): grade 2 → `setColor(DAT_029ec234)`, 3 → `DAT_029ec228` 색 틴트가
##    붙는데 **.rodata 상수라 디컴프에 값이 없다** → 틴트 없이 애니만 재생한다(HARD RULE 6).
## (종전의 "우리 알은 스택이라 최고 등급으로 켠다"는 ASSUMPTION 은 v15 에서 사라졌다 —
##  등급이 인벤 키에 실려 **칸마다 등급이 하나**다, `EggItem`.)
const EGG_GRADE_FX_FRAMES := 6
const EGG_GRADE_FX_DELAY := 0.15

func _inv_egg_grade_fx(key: String, egg: Sprite2D) -> void:
	if EggItem.grade_of(key) <= 0 or egg.texture == null:
		return
	var fx := Sprite2D.new()
	fx.material = _pma
	# ⚠️ **알 스프라이트의 자식**이라 부모 배율을 물려받는다 → 여기에 ASSET_SCALE 을 또 곱하면 안 된다
	#    (원작 `setScale(1.2)` 도 알과 같은 좌표계에서의 1.2 다). 이 규칙 덕에 같은 함수가
	#    상세창(알 ×4/3)과 그리드 셀(알을 84px 로 축소)에서 **둘 다 비율이 맞는다**.
	fx.scale = Vector2(1.2, 1.2)
	fx.z_index = 1
	# 원작 anchor(0.5, 0) = 밑변 기준 → Godot 은 offset.y = −h/2 로 밑변을 position 에 맞춘다.
	# 프레임마다 높이가 달라(62·62·66·68·66·62) 텍스처를 갈아끼울 때 offset 도 같이 고친다.
	# 위치도 부모 로컬(텍스처 픽셀)이다 → 원작의 5pt 를 픽셀로 환산(5 ÷ ASSET_SCALE = 3.75px).
	fx.position = Vector2(0, egg.texture.get_height() * 0.5 - 5.0 / Design.ASSET_SCALE)
	egg.add_child(fx)
	var frames: Array = []
	for i in EGG_GRADE_FX_FRAMES:
		var t := AtlasUI.tex("common_ui", "common_ani_egg_up1_%d" % (i + 1))
		if t != null:
			frames.append(t)
	if frames.is_empty():
		fx.queue_free()
		return
	var idx := {"i": 0}
	var apply := func() -> void:
		var t: Texture2D = frames[int(idx["i"]) % frames.size()]
		fx.texture = t
		fx.offset = Vector2(0, -t.get_height() * 0.5)
		idx["i"] = int(idx["i"]) + 1
	apply.call()
	var tm := Timer.new()
	tm.wait_time = EGG_GRADE_FX_DELAY
	tm.autostart = true
	tm.timeout.connect(apply)
	fx.add_child(tm)


## 강화 등급 한 줄. v15 부터 **칸이 곧 등급**이라 목록이 아니라 이 칸의 등급 하나만 적는다.
## 확정 부화 등급은 자작이 아니라 위키 확정치다(labwiki.pdf §2.1 → data/laboratory.json).
func _inv_egg_grade_text(key: String) -> String:
	var g := EggItem.grade_of(key)
	if g <= 0:
		return ""
	var hg := EggUpgrade.hatch_grade(g, Data.laboratory.get("egg_upgrade", {}))
	if hg <= 0.0:
		return "+%d강" % g
	return "+%d강 — 부화 등급 %.1f 확정" % [g, hg]


## 상세창 하단 실행 버튼(선택/부화/개봉/장착/제련/사용 + 10회 사용).
## 원작 `BagPopup::onClickSelect` → `onClickSelect_Confirm` 대응. 표시부와 분리해 둔 이유는
## 알 탭이 **원작 레시피의 다른 표시부**(`_inv_detail_egg`)를 쓰면서 이 버튼들은 공유하기 때문.
func _inv_detail_actions(item: Dictionary) -> void:
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
	# 🔀 2026-08-01: 종전 `is_gear`(젬+장비 한 묶음)를 갈랐다. 원작 가방은 탭마다 버튼이 다르다 —
	#   젬 탭(category 2)의 확인은 **장착**이지만(`BagPopup::onClickConfirm` case 2),
	#   장비 탭(category 1)에는 장착 버튼이 아예 없고 **강화 / 옵션 변경 두 개**다
	#   (`BagPopup::onClickSelect` tag1 → `NewItemEnchantPopup` @BagPopup.c:14008 ·
	#    tag0 → `onClickSelect_Confirm` case 1 → `ItemCommentPopup::setResetItem` @14967).
	var is_gear := String(item.get("category", "")) == "gem"
	var is_equip := String(item.get("category", "")) == "equipment"
	# 원작: 부화는 **인벤토리 '알' 탭에서 알을 골라 부화**시킨다(둥지 상단 버튼이 아니다).
	# ⚠️ 원작 부화 메커니즘은 현 breeding 씬(랜덤 부화/조합)과 다르다 — 재구현은 별도 과제.
	var is_egg := String(item.get("category", "")) == "egg"
	# 뽑기 알(의문의 알·빛문알·속성알)은 **부화가 아니라 개봉**이다 — 위키 item.pdf §5.
	# 개봉하면 정해진 풀에서 드래곤 알이 하나 무작위로 나온다(EggGacha). 규칙은 logic 층에.
	var is_gacha_egg := is_egg and EggGacha.is_gacha_egg(item)
	# 제련(원작 `BagPopup::onClickConfirm` case 6 → `ItemSmeltPopup`) — 하위 티어 정령석·스톤하트.
	# 원작도 **확인 버튼 자체가 제련 창을 연다**(별도 버튼이 아니다).
	var is_smelt := ItemSmelt.can_smelt(_inv_selected, Data.combine_item)
	# 장비 탭 — 원작 그대로 버튼 2개(강화 / 옵션 변경). 장착은 동굴 장비 칸 → `ItemPopup` 이 한다.
	if is_equip:
		_build_bag_equip_buttons(_inv_selected)
		return

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
		var ik0 := _inv_selected
		select.pressed.connect(func(): _equip_gem_from_bag(ik0))
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

## 가방 '장비' 탭의 버튼 2개 — **원작 `BagPopup` 그대로**(2026-08-01).
##
## | 원작 | 대상 | 우리 |
## |---|---|---|
## | tag 1 (왼쪽) `onClickSelect` case 1 | 선택 장비 | 강화 → `ItemEnchantPopup`(가방 개체 대상) |
## | tag 0 (오른쪽) `onClickSelect_Confirm` case 1 | 선택 장비 | 옵션 변경 → `EquipOptionLayer` |
##
## 원작 왼쪽은 `getRarity() < 2` 면 `<CaveItemEquipMsg7>` 로 막고(= 일반 등급 강화 불가),
## 오른쪽은 `ItemCommentPopup` + `setResetItem(equip)` + `Item::create(0x1bd)`(장신구 옵션 초기화)
## 확인창을 띄운다. 우리는 확인 문구를 원작 `<EquipeSelectMsg1>` 으로 맞춘다.
##
## ⚠️ **장착 버튼은 원작에 없다** — 장착은 동굴 하단 장비 칸 → `MultyEquipPop` → `ItemPopup` 이다.
func _build_bag_equip_buttons(inv_key: String) -> void:
	var meta := Equipment.item_key_meta(inv_key)
	var rar := int(meta.get("rarity", 0))
	var specs := [
		["강화", Vector2(40, 520), func(): _bag_enhance(inv_key)],
		["옵션 변경", Vector2(300, 520), func(): _bag_reroll(inv_key)],
	]
	for sp in specs:
		var nm := String((sp as Array)[0])
		var at: Vector2 = (sp as Array)[1]
		var bg := NinePatchRect.new()
		bg.texture = load("res://assets/converted/ninepatch_ui/9patch_btn.tres")
		bg.patch_margin_left = 16; bg.patch_margin_right = 16
		bg.patch_margin_top = 16; bg.patch_margin_bottom = 16
		bg.position = at; bg.size = Vector2(220, 58)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 일반 등급은 강화도 옵션 변경도 대상이 아니다 — 눌리지만 흐리게 보여 준다.
		if rar < 2:
			bg.modulate = Color(0.62, 0.62, 0.62)
		_inv_detail_box.add_child(bg)
		var b := Button.new()
		b.flat = true
		b.text = nm
		b.position = at
		b.size = Vector2(220, 58)
		b.add_theme_font_size_override("font_size", 26)
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0, 0.9))
		b.add_theme_constant_override("outline_size", 5)
		b.pressed.connect((sp as Array)[2])
		_inv_detail_box.add_child(b)


## 가방 → 강화(원작 `BagPopup::onClickSelect` case 1 → `NewItemEnchantPopup::create(equip)`).
func _bag_enhance(inv_key: String) -> void:
	var target := ItemEnchantPopup.target_bag(inv_key, int(_active().get("uid", 0)))
	if target.is_empty():
		_toast("장비가 아닙니다"); return
	var sd := ItemEnchantPopup.slot_view(target)
	if int(sd.get("grade", 0)) < 2:
		# 원작 <CaveItemEquipMsg7>
		_open_popup_type("강화", ItemPopup.S_GRADE_MIN, func(): pass, "확인", "")
		return
	var why := Equipment.enchant_blocked(sd, Data.equipment)
	if why == "option_max" or why == "grade_max":
		_open_popup_type("강화", ItemPopup.S_NO_MORE if why == "option_max"
			else ItemPopup.S_GRADE_MIN, func(): pass, "확인", "")
		return
	# ⚠️ 강화에 성공하면 **인벤 키가 바뀐다**(키가 곧 개체다) → 선택을 새 키로 옮긴다.
	#   람다는 생성 시점 값을 캡처하므로 `pop` 을 **먼저 대입한 뒤** 연결한다
	#   (memory: GDScript 람다 자기참조 함정).
	var pop := ItemEnchantPopup.open(self, target)
	pop.closed.connect(func(): _bag_equip_changed(pop.current_key()))


## 가방에서 장비 개체가 바뀐 뒤(강화·옵션 변경) 선택 키를 옮기고 다시 그린다.
func _bag_equip_changed(new_key: String) -> void:
	if new_key != "" and UserDB.item_count(new_key) > 0:
		_inv_selected = new_key
	_inventory_refresh_grid()
	_inventory_refresh_detail()
	_refresh_stats()


## 가방 → 옵션 변경(원작 오른쪽 버튼). 소모품은 **기누의 동전**이고 동전 등급 == 장비 등급이어야
## 한다(원작 `ItemEquipSelectPopup::init(itemNo)` 이 요구 희귀도를 박고 `initData` 가
## `getRarity(equip) == 그 값`인 장비만 목록에 올린다 — 동전은 등급을 **바꾸지 않는다**).
func _bag_reroll(inv_key: String) -> void:
	var meta := Equipment.item_key_meta(inv_key)
	var grade := int(meta.get("rarity", 0))
	var items: Dictionary = Data.equipment.get("option", {}).get("reroll_items", {})
	var coin := String(items.get(str(grade), ""))
	if coin == "":
		_open_popup_type("옵션 변경", "이 등급의 장신구에 쓸 수 있는 동전이 없습니다.",
			func(): pass, "확인", "")
		return
	if UserDB.item_count(coin) <= 0:
		_open_popup_type("옵션 변경", "%s이(가) 없습니다." % Data.item_name(coin),
			func(): pass, "확인", "")
		return
	# 원작 확인창 <EquipeSelectMsg1> + 소모 동전 표기.
	_open_popup_type("장비 선택",
		"해당 장비의 부가 옵션을 변경하시겠습니까?\n\n%s  X %d"
			% [Data.item_name(coin), UserDB.item_count(coin)],
		func():
			if not UserDB.use_item(coin, 1):
				return
			var lay := EquipOptionLayer.open_bag(self, inv_key, coin, grade,
				func(changed: bool):
					_toast("옵션을 변경했습니다" if changed else "기존 옵션을 유지했습니다"))
			lay.finished.connect(func(): _bag_equip_changed(lay.current_key())),
		"확인", "취소")


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
		var txt := "Lv.%d %s" % [int(d["level"]), Icons.name_of(d)]
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
		var nm := Icons.name_of(d)
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
			_toast("%s 이(가) 회복했습니다" % Icons.name_of(d))
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
			UserDB.bump_quest("levelups")   # 마을 미션: 레벨업 카운트
			var sk_got := _skills_learned_since(uid, sk_before)
			UserDB.use_item(key, 1)
			UserDB.set_active(uid)
			# 성장 단계 교체는 아래 `_refresh()` 가 이미 처리(새 단계 스파인이 서 있다).
			_close_skill_modal(); _close_overlay(); _refresh_stats(); _refresh()
			var scr := _open_levelup()   # 원작 흐름: 적용 → 레벨업 화면(ExpLayer 대응) 위에서 연출
			# 🔴 2026-07-27: 이 경로(가방 → 대상 선택)는 연출을 안 태웠던 사고가 있었다.
			#   2026-07-29: 원작 안무 타임라인으로 통합 — 컨텍스트가 필요하므로 화면을 연 **뒤**.
			var new_lv := int(UserDB.get_dragon(uid).get("level", 1))
			var slot_new := -1
			for si in Loadout.SLOT_UNLOCK_LEVEL.size():
				if old_lv < int(Loadout.SLOT_UNLOCK_LEVEL[si]) and new_lv >= int(Loadout.SLOT_UNLOCK_LEVEL[si]):
					slot_new = si
			if scr:
				scr.play_fx({"kind": "up", "sp": 1.0, "stage_changed": false,
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
			var dscr := _open_levelup()
			Bgm.sfx("effect_level_updown")
			if dscr:
				dscr.word_banner("LEVEL DOWN", 1.4, Color(0.86, 0.66, 1.0), Color(0.24, 0.05, 0.34, 1.0))
		"ascension":
			# 사용자 확정: 동굴 슬롯의 드래곤을 삭제하고 다이아를 지급한다.
			if bool(d.get("locked", false)):
				_toast("잠긴 드래곤은 승천시킬 수 없습니다"); return
			if UserDB.dragon_count() <= 1:
				_toast("마지막 드래곤은 승천시킬 수 없습니다"); return
			var dia := _ascension_diamond(int(d.get("level", 1)))
			var nm := Icons.name_of(d)
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
		"gemslot", "skillslot":
			# 원작 흐름(`BagPopup`): 아이템 선택 → **`ItemCommentPopup` 확인창**(현재 슬롯 미리보기
			# + `CaveBagMsg19/20`) → 확인 → 적용 → **`ResetLayer` 전체화면 결과 연출**.
			# 좌표·타임라인 = `docs/ref/porting/SlotResetScreens.md`.
			# 가방 오버레이는 닫지 않는다 — 원작도 결과 화면이 가방 위에 얹힌다(참조 영상).
			_close_skill_modal()
			ItemCommentPopup.open_slot_reset(self,
				"gem" if kind == "gemslot" else "skill", d, key,
				func(): _apply_slot_reset(key, kind, uid))
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

## `ItemCommentPopup` 확인 후의 실제 적용 + 결과 연출(`ResetLayer`).
## 원작 대응 = `BagPopup::onClickConfirm` 의 서버 응답 처리(`BagPopup.c:29735`/`:29816`) →
## 꼬리에서 `ResetLayer::create(1=젬 / 0=스킬)` 을 러닝 씬 z=1000 에 얹는다.
func _apply_slot_reset(key: String, kind: String, uid: int) -> void:
	if UserDB.item_count(key) <= 0:
		_toast("보유하지 않은 아이템입니다"); return
	var d := UserDB.get_dragon(uid)
	if d.is_empty():
		return
	var returned := 0
	if kind == "gemslot":
		# 원작: `setGemType(i, 새 타입)` + **`setItemGem(i, 0)`** — 착용 젬 3칸을 전부 뗀다.
		# 원작 문구(`CaveBagMsg21`)는 "파괴"라고 하지만 우리는 가방으로 돌려준다
		# (🟦 오프라인 완화 — 되돌릴 수 없는 소실을 만들지 않는다. 종전 동작 유지).
		returned = _return_all_gems(uid, d.get("gems", {}))
		var nt: Array = Gem.random_types(Data.gems)
		UserDB.set_dragon_field(uid, "gems", Gem.set_types({"types": nt, "slots": []}, nt))
	else:
		# 원작: `setSkillType(i, 새 타입)` + **`setSkill(i, "0")`** — 장착 스킬 2칸도 함께 비운다.
		# 학습 풀(`skills`)은 그대로라 스킬을 잃지는 않는다(다시 꽂으면 된다).
		UserDB.set_dragon_field(uid, "skill_slots", Loadout.random_slot_types())
		UserDB.set_dragon_field(uid, "skill_equip", [0, 0])
	UserDB.use_item(key, 1)
	UserDB.set_active(uid)
	_refresh_stats(); _refresh()
	var back := func():
		_refresh()
		if is_instance_valid(_overlay):
			_open_inventory()          # 결과창을 닫으면 가방으로 돌아간다(원작과 같은 자리)
		if returned > 0:
			_toast("젬 %d개를 가방으로 돌려받았습니다" % returned)
	ResetLayer.open(self, uid, "gem" if kind == "gemslot" else "skill", back, _stage)

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
	# v15: 강화 등급은 **고른 칸이 곧 등급**이다(`egg:17#2`) — 원작이 알 개체를 고르는 것과 같다.
	# 종전엔 한 칸에 등급이 섞여 있어 "높은 등급부터"라는 자작 규칙이 필요했다(EggItem 참조).
	var step := EggItem.grade_of(item_key)
	var grade := Hatchery.grade_for(step, ecfg, RNG.randf(), blessed)
	var secs := Hatchery.hatch_seconds(grade)
	UserDB.use_item(item_key, 1)
	if blessed:
		UserDB.set_pmeta("blessed_nest", false)   # 축복받은 둥지는 1회성 — 이 부화에 썼다
	# 축복은 1회성이라 **알 개체에 기록**한다 — 둥지 그림(황금 월계관)과 부화 연출의
	# 보너스 성급 분리 표시가 그 값을 읽는다(원작은 계정의 `User::getNestLevel()` 이었다).
	var egg := UserDB.add_egg(did, grade, secs, step, {}, blessed)
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


## (`_inventory_badge` 는 자작 "보유 X n" 배지 전용이었다 — 원작 상세 레이어에 없어서
##  2026-07-31 상세창을 원작 레시피로 되돌리며 함께 삭제했다.)

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

## 칸 클릭 = 선택만 바뀐다. **그리드를 다시 만들지 않는다** — 다시 만들면 가로 스크롤이
## 튀고(3행 고정·가로 스크롤로 바뀐 뒤로는 눈에 띈다) 매번 수백 노드를 새로 짓는다.
## 바뀌는 것은 이전/새 칸의 테두리 프레임 두 장뿐이다.
func _inventory_select(key: String) -> void:
	var prev := _inv_selected
	_inv_selected = key
	for k in [prev, key]:
		var f = _inv_cells.get(String(k))
		if f is NinePatchRect and is_instance_valid(f):
			(f as NinePatchRect).texture = _inv_slot_frame(String(k) == key)
	_inventory_refresh_detail()


## 칸 테두리 — 선택 칸은 `9patch/bt_itembox_on`(노란 하이라이트), 그 외는 `9patch/train_box4`.
## 근거는 `_inventory_cell` 주석(레퍼런스 슬롯 픽셀 실측).
func _inv_slot_frame(selected: bool) -> Texture2D:
	return load("res://assets/converted/ninepatch_ui/%s.tres"
		% ("9patch_bt_itembox_on" if selected else "9patch_train_box4"))

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
	# 강화된 알(`mall_back_egg#1`) — 등급 접미사를 떼고 기본 정의를 찾아 등급만 실어 준다.
	# (가상 알 키 `egg:17#2` 는 위 `EggGacha.item_def` 가 이미 처리한다.)
	var eb := EggItem.base_of(key)
	if eb != key and Data.items.has(eb):
		var bi := Data.get_item(eb).duplicate(true)
		bi["egg_grade"] = EggItem.grade_of(key)
		return bi
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

## 스킬 아이템 사용 — 원작 `BagPopup::onClickSelect_Confirm` case 4 → `onClickConfirm` → `serverResult` case 4.
## 대상은 언제나 **현재 선택 중인 드래곤**. 게이트가 둘이다:
##   ① 레벨 — `if (9 < Dragon::getLevel(선택드래곤))`(BagPopup.c:15410). Lv.10 미만이면 토스트만.
##   ② 순차 학습 — `Dragon::checkSkillList(no, level)`(onClickConfirm 0xdf5650). Lv.1 은 미보유일 때만,
##      Lv.N 은 그 스킬을 **Lv.N-1** 로 갖고 있을 때만. 막히면 `CaveSkillUseMsg1` 문구만 띄운다.
##      (원작은 확인 팝업을 **누른 뒤** 이 문구를 띄우지만, 우리는 헛클릭을 줄이려고 확인 전에 막는다.
##       판정·문구는 동일 — 통과 여부가 달라지는 곳은 없다.)
## 원작에는 셋째 게이트 **속성 제한**(`Skill::getAttribute()` 1글자 ↔ `Dragon::getRace()`)도 있으나
## 🟦 **컷**(사용자 확정 2026-07-31) — 슬롯 변경 아이템 이전의 구 시스템 잔재로 보고 구현하지 않는다.
## 지금의 습득 제약은 슬롯 타입(△□○☆)이 담당한다. 상세 = `docs/ref/porting/SkillScroll.md` §1-4.
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
	var dname := Icons.species_name(int(a["id"]))
	var pool: Array = UserDB.dragon_skills(int(a["uid"]))
	# 순차 학습 게이트 — 원작 `Dragon::checkSkillList`. 막히면 원작 문구(`CaveSkillUseMsg1`)만 띄운다.
	if not Loadout.can_learn(pool, int(parsed["id"]), int(parsed["level"])):
		_toast(Loadout.LEARN_BLOCKED_MSG)
		return
	var already := ""
	if int(parsed["level"]) > 1:
		already = "\n\n(Lv.%d → Lv.%d 강화)" % [int(parsed["level"]) - 1, int(parsed["level"])]
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
		# ⚠️ '강화 단계' 줄은 빼 두었다(🟦사용자 확정 2026-07-31) — 이름이 이미 `… +3` 이라
		#   같은 말을 두 번 하는 자작 줄이었다. 원작 상세창엔 comment 한 줄뿐이다.
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
	# ⚠️ `use`(용도) 는 **표시하지 않는다** — 원작 상세창엔 `Item::getComment()` 한 줄뿐이고,
	#   items.json 의 `use` 열은 사용자가 우리에게 구현 대상을 알려주려고 적은 작업용 메모다
	#   (🟦사용자 확정 2026-07-31). 데이터는 그대로 두고 화면에만 안 낸다.
	match String(item.get("offline", "")):
		"dummy":
			# 우리가 못 만든 게 아니라 **원작에도 사용처가 없던** 아이템.
			parts.append("(원작에서도 쓰이지 않던 아이템입니다)")
		"cut":
			parts.append("(오프라인 재구현에서 빠진 기능의 아이템입니다)")
		"todo", "stub":
			# 종전엔 `use` 가 비면 "용도 확인 필요"를 찍었다 — 그것도 우리 작업 메모라 뺀다.
			parts.append("(해당 기능이 아직 구현되지 않았습니다)")
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
