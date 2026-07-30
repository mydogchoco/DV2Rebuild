class_name DungeonBG
extends RefCounted
## 던전(필드) 배경 리졸버 — 원작 경로 `scene/adventure/bg/<필드id>/`.
##
## 원작은 던전 배경을 필드 id로 포맷해 부른다: `scene/adventure/bg/%d/bg.jpg`
##   (WorldMapPopupLayer.c:9066 · SeekScene.c:2948 · WeeklyMainScene.c:851 ·
##    WorldAreaOpenLayer.c:348 · RaidMonsterDetailLayer.c:4381 — 동일 포맷 문자열)
## 배경은 2겹이다:
##   bg.jpg                       768×519 원경 = 디자인 화면(1024×692)에 정확히 꽉 참(×4/3, CLAUDE.md §9)
##   item.img_plist `bg_item.png` 384×260 전경 오버레이 → 원작은 배경의 자식으로
##                                중앙정렬 + setScale(2.0), z=2 (WorldMapPopupLayer.c:9216/:9222)
##
## 필드 id = `data/stages.json` 의 스테이지 키 = 원작 `AdventureField_<id>` 문자열 id.
##   (stringsData_KR.xml:2019~ 1=희망의 숲 2=난파선 … 23=화룡의 둥지 — 우리 23스테이지와 1:1)
## 변형 배경: **500+id = 유타칸 밤**, **600+id = 카데스의 공간**(오염된 보라 하늘).
## 규칙은 `variant_field()` 참조 — 원작 `WorldMapPopupLayer::init` 축자.
##
## ⚠️ 2026-07-27 이전 판은 `assets/converted/cave_bg/cavebg%d.jpg`(=둥지 내부 배경 15종)를
##    키워드 리졸버로 배정해 썼다 — 경로 오판(CLAUDE.md §3). 필드 배경 51종이 원본에 실재한다.

const DIR := "res://assets/converted/adventure_bg"
## 오버레이 원본 캔버스(cocos sourceSize {384,260}) × setScale(2.0).
const OVL_CANVAS := Vector2(768.0, 520.0)
const OVL_SCALE := 2.0

static var _man: Dictionary = {}

static func _manifest() -> Dictionary:
	if _man.is_empty():
		var f := FileAccess.open(DIR + "/_manifest.json", FileAccess.READ)
		if f:
			var j = JSON.parse_string(f.get_as_text())
			if typeof(j) == TYPE_DICTIONARY:
				_man = j
	return _man

## 유타칸 밤 / 카데스의 공간 변형 필드 id — 원작 `WorldMapPopupLayer::init`
## (WorldMapPopupLayer.c:2136-2148) 축자 이식.
##
##   kades = GameManager::getDBYutakanKades()
##   if (field == 8 || field == 6 || (field - 1) > 13 || kades == 0):
##        night = GameManager::getDBYutakanNight()
##        offset = 500;  if (night == 0 || (field-1) > 13 || field == 6 || field == 8): offset = 0
##   else: offset = 600
##   this->fieldNo = offset + field
##
## ⇒ 변형이 있는 필드는 **1~14 중 6·8을 뺀 12종**뿐이다. 추출 에셋도 정확히 그것뿐:
##    `DV2/480/scene/adventure/bg/` = 501~505·507·509~514 / 601~605·607·609~614 (506·508 없음).
## ⇒ **카데스가 밤보다 우선**한다(둘 다 켜져 있으면 600번대).
static func variant_field(base: int, night: bool, kades: bool) -> int:
	if base < 1 or base > 14 or base == 6 or base == 8:
		return base            # 빛의 탑(15)·해적 소굴(6)·혼돈의 틈새(8)·엘프/드워프 필드엔 변형이 없다
	if kades:
		return 600 + base
	if night:
		return 500 + base
	return base

## 변형 필드 id → 기본 필드 id (501→1, 613→13, 그 외 그대로).
static func base_field(fid: int) -> int:
	if fid >= 600 and fid < 700:
		return fid - 600
	if fid >= 500 and fid < 600:
		return fid - 500
	return fid

## 변형 종류: "" (기본) / "night" / "kades".
static func variant_of(fid: int) -> String:
	if fid >= 600 and fid < 700:
		return "kades"
	if fid >= 500 and fid < 600:
		return "night"
	return ""

## 스테이지 dict → 필드 id. `bg`(명시) 우선, 없으면 `id`. 0 = 미상.
static func field_id(stage: Dictionary) -> int:
	for k in ["bg", "id"]:
		var v = stage.get(k, null)
		if v != null and int(v) > 0:
			return int(v)
	return 0

## 원경 bg.jpg 경로. 필드 id를 못 정하거나 파일이 없으면 "".
static func path_for(stage: Dictionary) -> String:
	var fid := field_id(stage)
	if fid <= 0:
		return ""
	var p := "%s/bg_%d.jpg" % [DIR, fid]
	return p if ResourceLoader.exists(p) else ""

## 전경 오버레이 AtlasTexture 경로. 없는 필드도 있다 → "".
static func overlay_path_for(stage: Dictionary) -> String:
	var fid := field_id(stage)
	if fid <= 0:
		return ""
	var p := "%s/bg_%d_item.tres" % [DIR, fid]
	return p if ResourceLoader.exists(p) else ""

## 배경 2겹을 parent에 붙인다(전체화면 Control 전제). 반환 = 원경 TextureRect(없으면 null).
## 오버레이는 원경의 자식 + 앵커 비율 배치 → 해상도가 바뀌어도 원작 상대위치를 유지한다.
static func build(parent: Node, stage: Dictionary) -> TextureRect:
	var p := path_for(stage)
	if p == "":
		return null
	var bg := TextureRect.new()
	bg.texture = load(p)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	add_overlay(bg, stage)
	return bg

## 전경 오버레이만 기존 배경 Control 위에 얹는다(월드맵 미리보기 등 축소 배치에도 그대로 통함).
static func add_overlay(bg: Control, stage: Dictionary) -> void:
	var op := overlay_path_for(stage)
	if op == "":
		return
	var key := "bg_%d_item" % field_id(stage)
	var e: Dictionary = _manifest().get(key, {})
	if e.is_empty():
		return
	# cocos offset = (트림중심 - 원본캔버스중심), y-up. 캔버스 대비 정규화해 앵커로 준다.
	var off: Array = e.get("off", [0, 0])
	var w := float(e.get("w", 0)) * OVL_SCALE
	var h := float(e.get("h", 0)) * OVL_SCALE
	if w <= 0.0 or h <= 0.0:
		return
	var cx := 0.5 + float(off[0]) * OVL_SCALE / OVL_CANVAS.x
	var cy := 0.5 - float(off[1]) * OVL_SCALE / OVL_CANVAS.y
	var ovl := TextureRect.new()
	ovl.texture = load(op)
	ovl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ovl.stretch_mode = TextureRect.STRETCH_SCALE
	ovl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ovl.anchor_left = cx - w * 0.5 / OVL_CANVAS.x
	ovl.anchor_right = cx + w * 0.5 / OVL_CANVAS.x
	ovl.anchor_top = cy - h * 0.5 / OVL_CANVAS.y
	ovl.anchor_bottom = cy + h * 0.5 / OVL_CANVAS.y
	ovl.offset_left = 0.0; ovl.offset_right = 0.0
	ovl.offset_top = 0.0; ovl.offset_bottom = 0.0
	bg.add_child(ovl)
