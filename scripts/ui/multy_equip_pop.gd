class_name MultyEquipPop
extends Control
## 장비 슬롯 4칸 창 — 원작 `cocos2d::MultyEquipPop` 이식. render 층(CLAUDE.md §8.1).
##
## 참조 프레임(사용자 제공):
##   · `docs/ref/equip/cave_장비칸클릭시팝업1.png` / `2.png` — 동굴에서 연 모습(4칸 다 열림 + 장비)
##   · `docs/ref/orig_image/lab/드래곤강화4.png`            — 연구소에서 연 모습(1칸 열림 + 자물쇠 3)
## 둘은 **같은 클래스**다(제목이 둘 다 `<MultyEquip_Title>` "장비 슬롯 확장").
## 원작도 행마다 갈린다 — 잠긴 칸은 `getSlotInfoLayer`(자물쇠 + 칸 설명 → `onClickSlotOpen`),
## 열린 칸은 `getItemInfoLayer`(장비 아이콘 + 이름 + 옵션 → `onClickItemBox`).
##
## ## 실측 레이아웃 (`MultyEquipPop::getItemInfoLayer` 리터럴)
##   · 아이콘 칸 = `9patch/scale_streng_gearon|off` cap(13,13,13,13) **125×125**
##   · 정보 칸  = `9patch/scale_streng_gearliston|off` cap(15,15,30,30) **400×125** @ x=125
##   · 행 전체 = **550×125**
##   · 장비 아이콘 scale 1.2 · 이름 라벨 scale 0.8 앵커(0,1) @ (10, h−10) 색 = `getRarityColor`
##   · 옵션 라벨 scale 0.65 앵커(0,1) @ (10, y−15)
##   · 빈 칸 = `<MultyEquip_Empty>` "등록된 장비가 없습니다." 가운데
##
## ## 미보유 프레임 (CLAUDE.md §10 '동굴 하단 장비 4칸' 행)
## `9patch/scale_streng_gear{on,off,liston,listoff}` · `frame_streng_gearbg` ·
## `newCommon/Item_selection_tab1,2` 가 추출 아틀라스에 통째로 없다(후기 업데이트 UI 세트).
## 참조 두 장이 보여 주는 모양(회색 둥근 아이콘 칸 + 밝은 둥근 정보 칸)에 가장 가까운
## **보유 9patch** 로 대체한다 — 아이콘 칸 `9patch/list_bg2`(회색 둥근 사각),
## 정보 칸 `9patch/bt_itembox_off`(밝은 크림 둥근 사각). 원본을 확보하면 `_BOX`/`_ROW`
## 상수 두 줄만 바꾸면 된다. `common/lock` · `common/close_btn` 은 원본 그대로 쓴다.

signal closed

## 원작 문자열(`DV2/string/stringsData_KR.xml`).
const S_TITLE := "장비 슬롯 확장"                     # <MultyEquip_Title>
const S_EMPTY := "등록된 장비가 없습니다."             # <MultyEquip_Empty>
const S_LOCK := "슬롯 해제후 이용가능합니다."           # <MultyEquip_Lock>
const S_ALREADY := "이미 개방된 슬롯입니다."            # <MultyEquip_Slot_alread>
## <MultyEquip_Slot_All/Att/Def/Art> — 원작 표기 그대로("아티펙트").
const SLOT_CAN := {
	"all": "모든 장비 장착 가능", "battle": "전투형 장비 장착 가능",
	"support": "보조형 장비 장착 가능", "artifact": "아티펙트 장비 장착 가능"}
## 아이콘 칸 안의 짧은 이름. 원작 아이콘(`addimg/intension/icon_streng_*`)은 덤프에 없어
## 원작 All 칸처럼 **글자**로 그린다(연구소 화면과 같은 규약).
const SLOT_TAG := {"all": "All", "battle": "전투", "support": "보조", "artifact": "아티"}

const ICON_BOX := 125.0
const ROW_H := 125.0
const ROW_GAP := 3.0
const ROW_W := 525.0
const WIN_CAP := Rect2(130, 190, 55, 81)
const DIM_ALPHA := 140.0 / 255.0

## 대체 프레임(위 주석 참조). 원본 확보 시 여기만 교체한다.
const BOX_KEY := "9patch_list_bg2"
const BOX_CAP := Rect2(24, 24, 24, 24)
const ROW_KEY := "9patch_bt_itembox_off"
const ROW_CAP := Rect2(16, 16, 9, 24)

var _uid := 0
var _mode := "equip"
var _on_row: Callable = Callable()
var _win_root: Control


## `mode` = "equip"(동굴 — 열린 칸에 장착 장비를 보여 준다) / "expand"(연구소 — 칸 설명만).
## `on_row(slot_id: String, unlocked: bool)` 로 클릭을 넘긴다.
static func open(parent: Node, uid: int, mode: String, on_row: Callable) -> MultyEquipPop:
	var p := MultyEquipPop.new()
	p._uid = uid
	p._mode = mode
	p._on_row = on_row
	parent.add_child(p)
	p._build()
	return p


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 60
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	create_tween().tween_property(dim, "color:a", DIM_ALPHA, 0.15)
	rebuild()


func rebuild() -> void:
	if is_instance_valid(_win_root):
		_win_root.queue_free()
	var n := Equipment.SLOT_ORDER.size()
	var win := Vector2(ROW_W + 56.0, 96.0 + float(n) * (ROW_H + ROW_GAP) + 24.0)
	var vis := get_viewport_rect().size
	_win_root = Control.new()
	_win_root.size = win
	_win_root.position = ((vis - win) * 0.5).round()
	add_child(_win_root)
	var fr := AtlasUI.nine("ninepatch_ui", "9patch_popup4", win, WIN_CAP)
	if fr:
		_win_root.add_child(fr)
	var tbar := AtlasUI.nine("ninepatch_ui", "9patch_pop_title_bg", Vector2(win.x * 0.86, 56.0),
		Rect2(20, 12, 20, 12))
	if tbar:
		tbar.position = Vector2(win.x * 0.07, 16.0)
		_win_root.add_child(tbar)
	var t := _label(S_TITLE, 25, Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.position = Vector2(0, 16.0)
	t.size = Vector2(win.x, 56.0)
	_win_root.add_child(t)
	var cb := TextureButton.new()
	var ct := AtlasUI.tex("common_ui", "common_close_btn")
	if ct:
		cb.texture_normal = ct
		cb.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 1.2
	cb.position = Vector2(win.x - 68.0, 12.0)
	cb.pressed.connect(close)
	_win_root.add_child(cb)

	build_rows(_win_root, _uid, _mode, ROW_W, Vector2(28.0, 96.0), _on_row)


## 4행을 `parent` 에 그린다. 연구소 화면도 같은 그림을 쓰도록 밖에서 부를 수 있게 뺐다.
## 돌려주는 값 = 그린 높이.
static func build_rows(parent: Control, uid: int, mode: String, row_w: float, at: Vector2,
		on_row: Callable) -> float:
	var d := UserDB.get_dragon(uid)
	var open_ids := Equipment.slot_ids(d.get("equip_slots", 1))
	var eqf: Dictionary = d.get("equip", {})
	var y := at.y
	for sid_v in Equipment.SLOT_ORDER:
		var sid := String(sid_v)
		var unlocked: bool = open_ids.has(sid)
		var row := Control.new()
		row.position = Vector2(at.x, y)
		row.size = Vector2(row_w, ROW_H)
		parent.add_child(row)
		_draw_row(row, sid, unlocked, mode, eqf, uid)
		var b := Button.new()
		b.flat = true
		b.size = row.size
		var s2 := sid
		var u2 := unlocked
		if on_row.is_valid():
			b.pressed.connect(func(): on_row.call(s2, u2))
		row.add_child(b)
		y += ROW_H + ROW_GAP
	return y - at.y


static func _draw_row(row: Control, sid: String, unlocked: bool, mode: String,
		eqf: Dictionary, uid: int) -> void:
	# ① 아이콘 칸 125×125 — 원작 `scale_streng_gearon|off`.
	var box := AtlasUI.nine("ninepatch_ui", BOX_KEY, Vector2(ICON_BOX, ROW_H), BOX_CAP)
	if box:
		row.add_child(box)
	# ② 정보 칸 — 원작 `scale_streng_gearliston|off`(400×125). 폭만 창에 맞춘다.
	var iw := row.size.x - ICON_BOX
	var info := AtlasUI.nine("ninepatch_ui", ROW_KEY, Vector2(iw, ROW_H), ROW_CAP)
	if info:
		info.position = Vector2(ICON_BOX, 0.0)
		if not unlocked:
			info.modulate = Color(1, 1, 1)          # 잠긴 칸이 오히려 밝다(참조 드래곤강화4.png)
		row.add_child(info)

	var slot_dict := _slot_of(eqf, sid)
	var item: Dictionary = Equipment.catalog(Data.equipment).get(
		String(slot_dict.get("key", "")), {})
	var show_item := unlocked and mode == "equip" and not item.is_empty()

	if not unlocked:
		var lk := AtlasUI.spr("common_ui", "common_lock", Design.ASSET_SCALE)
		if lk:
			lk.position = Vector2(ICON_BOX * 0.5, ROW_H * 0.5)
			row.add_child(lk)
	elif show_item:
		# 원작 `getItemInfoLayer` 는 등급 실루엣 + 아이콘만 얹는다(귀속 뱃지는 안 붙인다 —
		# 귀속 여부는 아래 글자로 낸다). 그래서 belong 을 0 으로 넘겨 뱃지를 끈다.
		var ic: Control = Icons.equip_rect(item, 104.0, int(slot_dict.get("grade", 0)), 0, uid)
		if ic:
			ic.position = Vector2((ICON_BOX - 104.0) * 0.5, (ROW_H - 104.0) * 0.5)
			row.add_child(ic)
	else:
		var tag := _mk_label(String(SLOT_TAG.get(sid, sid)), 24, Color(0.42, 0.38, 0.34))
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag.size = Vector2(ICON_BOX, ROW_H)
		row.add_child(tag)

	if not show_item:
		# 잠긴 칸 = 그 칸의 성격(<MultyEquip_Slot_*>), 열린 빈 칸 = <MultyEquip_Empty>.
		var txt := String(SLOT_CAN.get(sid, sid)) if (not unlocked or mode == "expand") else S_EMPTY
		var l := _mk_label(txt, 21,
			Color(0.22, 0.15, 0.08) if unlocked else Color(0.34, 0.28, 0.22))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.position = Vector2(ICON_BOX, 0.0)
		l.size = Vector2(iw, ROW_H)
		row.add_child(l)
		return

	# ③ 이름 "%s +%d" — 색은 원작 `Equip::getRarityColor` 표 그대로(실루엣 표와 다르다).
	var up := int(slot_dict.get("enhance", 0))
	var rar := int(slot_dict.get("grade", 0))
	var rc := Icons.rarity_text_color(rar)
	var nm := _mk_label("%s +%d" % [String(item.get("name", "")), up] if up > 0
		else String(item.get("name", "")), 20, rc)
	nm.position = Vector2(ICON_BOX + 10.0, 8.0)
	nm.size = Vector2(iw - 20.0, 26.0)
	row.add_child(nm)

	# ④ 주 능력 한 줄 + 옵션 2열(참조 두 장 모두 이 배치다).
	var lines: PackedStringArray = []
	for st in (item.get("stat_main", {}) as Dictionary):
		lines.append("%s +%d" % [_stat_kr(String(st)),
			int((item["stat_main"] as Dictionary)[st])])
	var opts: Array = slot_dict.get("options", [])
	var oy := 38.0
	for s in lines:
		var ml := _mk_label(s, 15, Color(0.30, 0.17, 0.04))
		ml.position = Vector2(ICON_BOX + 10.0, oy)
		ml.size = Vector2(iw - 20.0, 20.0)
		row.add_child(ml)
		oy += 20.0
	var colw := (iw - 20.0) * 0.5
	for i in opts.size():
		var od := opts[i] as Dictionary
		var ol := _mk_label("%s +%s" % [_stat_kr(String(od.get("stat", ""))),
			str(od.get("value", 0))], 15, Color(0.30, 0.17, 0.04))
		ol.position = Vector2(ICON_BOX + 10.0 + float(i % 2) * colw, oy + float(i / 2) * 20.0)
		ol.size = Vector2(colw, 20.0)
		row.add_child(ol)
	# ⑤ 귀속 표기(원작 <CaveItemEquipSky>/<CaveItemEquipBeing>).
	var bel := int(slot_dict.get("belong", 0))
	if bel > 0:
		var bl := _mk_label("귀속됨" if bel == uid else "다른 드래곤의 귀속 아이템", 13,
			Color(0.45, 0.38, 0.30))
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		bl.position = Vector2(ICON_BOX + 10.0, ROW_H - 24.0)
		bl.size = Vector2(iw - 20.0, 18.0)
		row.add_child(bl)


static func _slot_of(eqf: Dictionary, sid: String) -> Dictionary:
	for s in (eqf.get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) == sid:
			return s
	return {}


static func _stat_kr(key: String) -> String:
	# 옵션 9종은 원작 문자열(EquipOptionLayer.STAT_KR), 주 능력의 나머지는 위키 §2.1 표기.
	if EquipOptionLayer.STAT_KR.has(key):
		return String(EquipOptionLayer.STAT_KR[key])
	return {"cri_pow": "크리티컬 파워", "cure": "행동불능 치유 확률",
		"awaken_rate": "각성기 게이지 상승률"}.get(key, key)


static func _mk_label(txt: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _label(txt: String, size: int, col: Color) -> Label:
	var l := _mk_label(txt, size, col)
	if col.v > 0.8:
		l.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.04, 0.9))
		l.add_theme_constant_override("outline_size", 5)
	return l


func close() -> void:
	closed.emit()
	queue_free()
