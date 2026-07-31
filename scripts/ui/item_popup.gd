class_name ItemPopup
extends Control
## 칸별 장비 선택 창 — 원작 `cocos2d::ItemPopup` 1:1 이식. render 층(CLAUDE.md §8.1).
##
## 포팅 카드 = `docs/ref/porting/ItemPopup.md`.
## 디컴프 = `docs/ref/orig_code/decomp/ItemPopup.c`(11,600줄, `[skip>` 0건) ·
##          `ItemTableViewCell.c`(셀) · `MultyEquipPop.c`(호출부).
##
## ## 진입 데이터 (원작과 나란히)
##
## | 원작 | 우리 |
## |---|---|
## | `ItemPopup::create(Dragon*, int slotIdx)` | `open(parent, uid, slot_id, on_change)` |
## | `setEquipList()` = `AccountManager::getEquip()` 중 `equip+0x11c == slot+1` | 인벤 `equip:` 키 중 `Equipment.can_equip(it, slot_id)` |
## | 정렬 `Equip::getSortNo` | 희귀도 내림차순 → 이름 (sortNo 는 서버 값이라 유실) |
##
## 원작은 **낀 장비도 같은 목록에 들어 있다**(`getDragonTag()` 로 구분) — 우리 모델은
## 낀 것이 인벤이 아니라 `dragon["equip"].slots` 에 있으므로, 그 한 개를 index 0 에
## 합성해 넣어 원작과 같은 그림(고르면 버튼이 '해제'로 바뀜)을 만든다.
##
## ## 원작 화면 (`init` + `initWidget` 리터럴 그대로)
##
## · 창 `9patch/popup4` cap `CCRect(130,190,40,58)`, 화면 여백 (10,10,10,140)
## · 제목 `<CaveItemEquip>`("아이템 장착") BMFont `getFontName_subtitle` @ `(w/2, h−45)`
## · 목록 `9patch/scroll_box` `(w−430)×420` @ `(40,40)` anchor(0,0) + `CCTableView`(가로)
##   └ `cellSizeForTable` = `(120, 표높이)`, 셀 하나가 **세로 3칸**
##   └ 칸 = `RoundedLayer(115, 130, 0x66000000)` @ cocos y `335 / 205 / 75`
##       (`ItemTableViewCell::initWithSize` — `SkillsTableViewCell` 과 같은 규격이다)
## · 상세 `CCLayer 350×420` @ `(w−30, 40)` anchor(1,0)
##   └ 이름 라벨 @ `(175, 410)` · `common/shadow` @ `(175, 210)` · 아이콘
##   └ `9patch/text_box 340×125` + `ScrollViewEx` + `CCLabelBMFontEx`
## · `RoundedButton 180×56` **2개** @ `(panelW/2 ∓ 95, 0)` anchor(0.5,0)
##   └ **tag 1 = 강화**(`onClickListener` → `getRarity() < 2` 면 `<CaveItemEquipMsg7>`,
##      아니면 `NewItemEnchantPopup::create(equip)`)
##   └ **tag 0 = 장착/해제**(라벨이 `this+0x2e0` 로 바뀐다 —
##      `onClickItem` 이 `getItemEquip(slot)` 과 태그를 비교해 `<CaveUnEquip>`/`<CaveEquip>`)
##
## 좌표 규약: 원작 리터럴은 창 로컬 cocos(y-up, 좌하단 원점) **포인트**다(§9 — ASSET_SCALE 을
## 다시 곱하지 않는다). 여기서는 `높이 − cocos y` 로 뒤집어 적는다.

signal closed

# ---------- 원작 리터럴 ----------

const WIN_CAP := Rect2(130, 190, 40, 58)
const WIN_MARGIN := Vector4(10.0, 10.0, 10.0, 140.0)   # left, right, bottom, top
const DIM_ALPHA := 127.0 / 255.0

const LIST_CAP := Rect2(65, 65, 6, 6)
const LIST_INSET_X := 430.0
const LIST_H := 420.0
const LIST_AT := Vector2(40.0, 40.0)
const TABLE_PAD := Vector2(10.0, 5.0)
const CELL_W := 120.0
const PER_CELL := 3
## `RoundedLayer(115, 130, 0x66000000)` — 0x42e60000=115.0 · 0x43020000=130.0.
const SLOT_BOX := Vector2(115.0, 130.0)
const SLOT_COLOR := Color(0, 0, 0, 0.40)
const SLOT_COCOS_Y := [335.0, 205.0, 75.0]

const PANEL := Vector2(350.0, 420.0)
const PANEL_RIGHT_GAP := 30.0
const DESC_BOX := Vector2(340.0, 125.0)
const DESC_CAP := Rect2(25, 25, 3, 3)
const DESC_COLOR := Color8(0x81, 0x43, 0x1D)
const BTN_SIZE := Vector2(180.0, 56.0)
const BTN_CAP := Rect2(20, 20, 4, 4)

## 원작 문자열(`DV2/string/stringsData_KR.xml`).
const S_TITLE := "아이템 장착"                                     # <CaveItemEquip>
const S_EQUIP := "장착"                                            # <CaveEquip>
const S_UNEQUIP := "해제"                                          # <CaveUnEquip>
const S_UPGRADE := "강화"                                          # <CaveUpgrade>
const S_LIFT := "귀속해제"                                         # <CaveEquip_Lift>
const S_GRADE_MIN := "가장 낮은 등급의 아이템은 강화가 불가능합니다."   # <CaveItemEquipMsg7>
const S_NO_MORE := "더 이상 강화할 수 없습니다."                     # <CaveItemEquipMsg8>
const S_BELONG_OTHER := "다른 드래곤에게 귀속된 아이템입니다."         # <CaveItemEquipMsg5>
const S_UNEQUIP_ASK := "선택된 장비를 해제시키겠습니까?"              # <CaveItemEquipMsg10>
const S_NONE := "착용 중인 장비가 없습니다."                         # <CaveItemEquipMsg11>
const S_BIND_WARN := "\n*사용 후 다른 드래곤에게 장착 불가"           # <CaveItemEquipMsg1>
const S_FREE_WARN := "\n*사용 후 다른 드래곤에게 장착 가능"           # <CaveItemEquipMsg2>
## <MultyEquip_Slot_Warring_2>
const S_DUP_MAIN := "같은 메인 옵션의 아이템을 장착하시면\n최상위 메인 옵션이 적용됩니다."

# ---------- 상태 ----------

var _uid: int = 0
var _slot_id: String = ""
var _on_change: Callable = Callable()

## 원작 `this+0x290`(목록) / `this+0x298`(선택 index) / `this+0x2a0`(선택 Equip).
## row = {cat, it, meta, inv, worn, n}
var _list: Array = []
var _sel: int = -1

var _win: Vector2 = Vector2.ZERO
var _body: Control
var _panel: Control
var _empty_lbl: Label
var _act_label: Label            # 원작 this+0x2e0 — 장착/해제로 바뀌는 라벨
var _upg_root: Control
var _lift_root: Control
var _slot_nodes: Array = []


## 원작 `MultyEquipPop::onClickItemBox` → `ItemPopup::create(dragon, tag)` + `show()`.
static func open(parent: Node, uid: int, slot_id: String,
		on_change := Callable()) -> ItemPopup:
	var p := ItemPopup.new()
	p._uid = uid
	p._slot_id = slot_id
	p._on_change = on_change
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
	create_tween().tween_property(dim, "color:a", DIM_ALPHA, 0.2)

	var vis := get_viewport_rect().size
	_win = Vector2(vis.x - (WIN_MARGIN.x + WIN_MARGIN.y), vis.y - (WIN_MARGIN.z + WIN_MARGIN.w))
	_body = Control.new()
	_body.size = _win
	_body.position = ((vis - _win) * 0.5).round()
	_body.pivot_offset = _win * 0.5
	add_child(_body)
	var frame := AtlasUI.nine("ninepatch_ui", "9patch_popup4", _win, WIN_CAP)
	if frame != null:
		_body.add_child(frame)
	var tw := _body.create_tween()
	tw.tween_property(_body, "scale", Vector2(1.2, 1.2), 0.1)
	tw.tween_property(_body, "scale", Vector2.ONE, 0.1)

	_build_title()
	_build_list_box()
	_build_panel()
	_reload()


# ------------------------------------------------------------ 껍데기

func _build_title() -> void:
	var t := _bm_label("%s — %s" % [S_TITLE, _slot_kr()], 1.2)
	_center(t, Vector2(_win.x * 0.5, 45.0), 520.0)
	_body.add_child(t)

	var csz := AtlasUI.size_pt("common_ui", "common_close_btn") * 1.5
	var x := TextureButton.new()
	var ct := AtlasUI.tex("common_ui", "common_close_btn")
	if ct != null:
		x.texture_normal = ct
		x.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 1.5
	x.position = Vector2(_win.x - 50.0, 50.0) - csz * 0.5
	x.pressed.connect(close)
	_body.add_child(x)


func _build_list_box() -> void:
	var sz := Vector2(_win.x - LIST_INSET_X, LIST_H)
	var box := Control.new()
	box.name = "list_box"
	box.size = sz
	box.position = Vector2(LIST_AT.x, _win.y - LIST_AT.y - sz.y)
	_body.add_child(box)
	var np := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", sz, LIST_CAP)
	if np != null:
		box.add_child(np)

	_empty_lbl = _bm_label("이 칸에 낄 수 있는 보유 장비가 없습니다.", 0.85)
	_center(_empty_lbl, sz * 0.5, sz.x)
	box.add_child(_empty_lbl)

	var sc := ScrollContainer.new()
	sc.name = "table"
	sc.position = TABLE_PAD
	sc.size = sz - Vector2(20.0, 10.0)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(sc)
	var strip := Control.new()
	strip.name = "cells"
	strip.custom_minimum_size = Vector2(0, sc.size.y)
	sc.add_child(strip)


func _build_panel() -> void:
	_panel = Control.new()
	_panel.name = "detail"
	_panel.size = PANEL
	_panel.position = Vector2(_win.x - PANEL_RIGHT_GAP - PANEL.x, _win.y - LIST_AT.y - PANEL.y)
	_body.add_child(_panel)

	var tb := AtlasUI.nine("ninepatch_ui", "9patch_text_box", DESC_BOX, DESC_CAP)
	if tb != null:
		tb.position = Vector2(PANEL.x * 0.5 - DESC_BOX.x * 0.5, PANEL.y - 130.0 - DESC_BOX.y * 0.5)
		_panel.add_child(tb)
	var dsc := ScrollContainer.new()
	dsc.name = "desc"
	dsc.position = Vector2(PANEL.x * 0.5 - DESC_BOX.x * 0.5 + 10.0,
		PANEL.y - 130.0 - DESC_BOX.y * 0.5 + 10.0)
	dsc.size = DESC_BOX - Vector2(20.0, 20.0)
	dsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(dsc)
	var dl := Label.new()
	dl.name = "desc_label"
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.custom_minimum_size = Vector2(DESC_BOX.x - 40.0, 0)
	_bm_style(dl, int(round(17.0 * Design.ASSET_SCALE * 0.8)), DESC_COLOR, "font_common")
	dsc.add_child(dl)

	# 원작 버튼 2개 — 왼쪽 tag 1 = 강화, 오른쪽 tag 0 = 장착/해제.
	_upg_root = _make_button(Vector2(PANEL.x * 0.5 - 95.0, PANEL.y), S_UPGRADE, _on_upgrade)
	var act := _make_button(Vector2(PANEL.x * 0.5 + 95.0, PANEL.y), S_EQUIP, _on_action)
	_act_label = act.get_node("label") as Label

	# 🟦 오프라인 배선(원작 근거 없음): 귀속해제.
	#   원작은 이 창이 아니라 **가방에서 '구드라의 지혜'를 소모하는 경로**가 푼다
	#   (`BagPopup.c:19446` `setBelong(-1)` · 라벨 `<CaveEquip_Lift>`). 그 소모품 경로를
	#   아직 이식하지 않아 기능이 닿지 않으므로, 귀속된 장비를 고른 동안만 보이는
	#   작은 보조 버튼으로 남긴다. 소모품 경로를 이식하면 이 블록만 지우면 된다.
	_lift_root = Control.new()
	_lift_root.size = Vector2(120.0, 30.0)
	_lift_root.position = Vector2(PANEL.x * 0.5 - 60.0, PANEL.y - BTN_SIZE.y - 34.0)
	_lift_root.visible = false
	_panel.add_child(_lift_root)
	var ll := Label.new()
	ll.text = S_LIFT
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ll.size = _lift_root.size
	_bm_style(ll, int(round(14.0 * Design.ASSET_SCALE)), Color(0.95, 0.86, 0.55))
	_lift_root.add_child(ll)
	_hit(_lift_root, _lift_root.size, _on_lift)


## `RoundedButton(1.1, CCSize(180,56), …)` 한 개. `center_bottom` = cocos anchor(0.5,0) 자리.
func _make_button(center_bottom: Vector2, text: String, cb: Callable) -> Control:
	var root := Control.new()
	root.size = BTN_SIZE
	root.position = Vector2(center_bottom.x - BTN_SIZE.x * 0.5, center_bottom.y - BTN_SIZE.y)
	_panel.add_child(root)
	var np := AtlasUI.nine("ninepatch_ui", "9patch_btn", BTN_SIZE, BTN_CAP)
	if np != null:
		root.add_child(np)
	var l := Label.new()
	l.name = "label"
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = BTN_SIZE
	_bm_style(l, int(round(19.0 * Design.ASSET_SCALE * 0.95)), Color.WHITE)
	root.add_child(l)
	_hit(root, BTN_SIZE, cb)
	return root


# ------------------------------------------------------------ 목록 (원작 setEquipList)

## 원작 `setEquipList` — 그 칸에 맞는 장비 전량 + `getSortNo` 정렬.
## 우리는 **낀 장비 1개를 index 0 에 합성**하고(원작은 같은 배열에 이미 들어 있다),
## 나머지는 보유 인벤에서 희귀도 내림차순 → 이름으로 세운다(sortNo 는 서버 유실).
func _reload() -> void:
	_list = []
	_sel = -1
	var cat := Equipment.catalog(Data.equipment)
	var dr: Dictionary = UserDB.get_dragon(_uid)
	var species_id := int(dr.get("id", 0))

	var worn := _worn_slot()
	if not worn.is_empty():
		var wit: Dictionary = cat.get(String(worn.get("key", "")), {})
		if not wit.is_empty():
			_list.append({"cat": String(worn["key"]), "it": wit, "worn": true, "inv": "", "n": 1,
				"meta": {"belong": int(worn.get("belong", 0)),
					"rarity": int(worn.get("grade", 0)),
					"enhance": int(worn.get("enhance", 0)),
					"options": worn.get("options", [])}})

	var rest: Array = []
	var inv: Dictionary = UserDB.inventory()
	for ik in inv.keys():
		var ck := Equipment.parse_item_key(String(ik))
		var n := int(inv[ik])
		if ck == "" or n <= 0 or not cat.has(ck):
			continue
		var it0: Dictionary = cat[ck]
		if not Equipment.can_equip(it0, _slot_id):
			continue
		if not Equipment.species_allows(it0, species_id):
			continue
		rest.append({"cat": ck, "it": it0, "worn": false, "inv": String(ik), "n": n,
			"meta": Equipment.item_key_meta(String(ik))})
	rest.sort_custom(func(a, b):
		var ra := int((a["meta"] as Dictionary).get("rarity", 0))
		var rb := int((b["meta"] as Dictionary).get("rarity", 0))
		if ra != rb:
			return ra > rb
		return String((a["it"] as Dictionary)["name"]) < String((b["it"] as Dictionary)["name"]))
	_list.append_array(rest)

	if not _list.is_empty():
		_sel = 0
	_rebuild_cells()
	_refresh_panel()


## 지금 이 칸에 끼어 있는 슬롯 dict. 없으면 {}.
func _worn_slot() -> Dictionary:
	for s in (UserDB.get_dragon(_uid).get("equip", {}).get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) == _slot_id:
			return s
	return {}


## 원작 `tableCellAtIndex` — 셀 = 세로 3칸(120 폭), 가로로 늘어선다.
func _rebuild_cells() -> void:
	var strip := _body.get_node_or_null("list_box/table/cells") as Control
	if strip == null:
		return
	for c in strip.get_children():
		strip.remove_child(c)
		c.queue_free()
	_slot_nodes.clear()

	var cells := int(ceil(float(_list.size()) / float(PER_CELL)))
	_empty_lbl.visible = cells == 0
	var table_h: float = LIST_H - 10.0
	strip.custom_minimum_size = Vector2(maxf(CELL_W * cells, 1.0), table_h)

	for i in _list.size():
		var col := i / PER_CELL
		var row := i % PER_CELL
		var center := Vector2(col * CELL_W + CELL_W * 0.5, table_h - float(SLOT_COCOS_Y[row]))
		_slot_nodes.append(_make_slot(strip, center, i))
	_refresh_slots()


## 원작 `ItemTableViewCell::initWithSize` + `updateItemBtn` 한 칸.
##   `RoundedLayer(115,130)` + 희귀도 실루엣 + 아이콘 + `"+ %d"`(우하단 anchor(1,0), (w−10,10))
##   + 귀속 마크(`owned_bg` 위에 `owned`/`owned2`, 우상단 anchor(1,1), (w−5,h−5)).
## 실루엣·아이콘·귀속 3겹은 `Icons.equip_rect` 가 이미 원작 규칙대로 그린다.
func _make_slot(parent: Control, center: Vector2, index: int) -> Dictionary:
	var r: Dictionary = _list[index]
	var it: Dictionary = r["it"]
	var meta: Dictionary = r["meta"]

	var root := Control.new()
	root.size = SLOT_BOX
	root.position = center - SLOT_BOX * 0.5
	parent.add_child(root)

	var bg := Panel.new()
	bg.size = SLOT_BOX
	bg.add_theme_stylebox_override("panel", _rounded_style(SLOT_COLOR))
	root.add_child(bg)

	var icon := Icons.equip_rect(it, 84.0, int(meta.get("rarity", 0)),
		int(meta.get("belong", 0)), _uid)
	if icon != null:
		icon.position = SLOT_BOX * 0.5 - Vector2(42.0, 42.0) - Vector2(0.0, 8.0)
		root.add_child(icon)

	# `getUpGrade() > 0` → `"+ %d"` 우하단.
	var up := int(meta.get("enhance", 0))
	if up > 0:
		var ul := Label.new()
		ul.text = "+ %d" % up
		ul.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ul.size = Vector2(SLOT_BOX.x - 20.0, 20.0)
		ul.position = Vector2(10.0, SLOT_BOX.y - 10.0 - 20.0)
		_bm_style(ul, int(round(13.0 * Design.ASSET_SCALE)), Color(1, 0.92, 0.55))
		root.add_child(ul)

	# 이름(원작도 칸 안에 라벨을 하나 더 놓는다).
	var nl := Label.new()
	nl.text = String(it.get("name", ""))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.size = Vector2(SLOT_BOX.x - 8.0, 34.0)
	nl.position = Vector2(4.0, SLOT_BOX.y - 44.0)
	_bm_style(nl, int(round(11.0 * Design.ASSET_SCALE)),
		Icons.rarity_text_color(int(meta.get("rarity", 0))))
	root.add_child(nl)

	# 착용 중 표시 — 원작 `updateItemBtn` 4번째 인자(getDragonTag != 0) 자리.
	var ov := Panel.new()
	ov.size = SLOT_BOX
	ov.add_theme_stylebox_override("panel", _rounded_style(SLOT_COLOR))
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.visible = bool(r.get("worn", false))
	root.add_child(ov)

	_hit(root, SLOT_BOX, func(): _on_click_item(index))
	return {"root": root, "index": index}


func _refresh_slots() -> void:
	for n in _slot_nodes:
		var d: Dictionary = n
		var root: Control = d["root"]
		root.modulate = Color(1.18, 1.18, 1.05) if int(d["index"]) == _sel else Color.WHITE


## 원작 `onClickItem`(:1842) — 선택을 옮기고 버튼 라벨을 다시 정한다.
func _on_click_item(index: int) -> void:
	if index == _sel:
		return
	_sel = index
	_refresh_slots()
	_refresh_panel()


# ------------------------------------------------------------ 상세 (원작 setExplain)

func _refresh_panel() -> void:
	for nm in ["name", "shadow", "art", "grade"]:
		var old := _panel.get_node_or_null(nm)
		if old != null:
			_panel.remove_child(old)
			old.queue_free()
	var dl := _panel.get_node_or_null("desc/desc_label") as Label
	if dl != null:
		dl.text = ""

	if _sel < 0 or _sel >= _list.size():
		_act_label.text = S_EQUIP
		_upg_root.modulate = Color(0.6, 0.6, 0.6)
		_lift_root.visible = false
		return

	var r: Dictionary = _list[_sel]
	var it: Dictionary = r["it"]
	var meta: Dictionary = r["meta"]
	var rar := int(meta.get("rarity", 0))
	var bel := int(meta.get("belong", 0))
	var worn := bool(r.get("worn", false))

	# 원작: 이 칸에 낀 것을 고르면 '해제', 아니면 '장착'.
	_act_label.text = S_UNEQUIP if worn else S_EQUIP
	# 강화 버튼 — 원작은 항상 눌리고 rarity<2 면 모달로 막는다. 눌리는 것 자체는 유지하되
	# 막힐 상황을 흐리게 보여 준다(PC 는 커서 피드백이 없어 그대로면 왜 안 되는지 모른다).
	_upg_root.modulate = Color.WHITE if rar >= 2 else Color(0.6, 0.6, 0.6)
	_lift_root.visible = worn and bel > 0

	var grades: Array = Data.equipment.get("option", {}).get("grades", [])
	var gname := ""
	if rar > 0 and rar < grades.size():
		gname = String((grades[rar] as Dictionary).get("name", ""))
	var up := int(meta.get("enhance", 0))

	var nm2 := "%s%s" % [String(it.get("name", "?")), (" +%d" % up) if up > 0 else ""]
	var nl := _bm_label(nm2, 0.85, Icons.rarity_text_color(rar))
	nl.name = "name"
	_center(nl, Vector2(PANEL.x * 0.5, 10.0), 340.0)
	_panel.add_child(nl)

	if gname != "":
		var gl := _bm_label(gname, 0.7, Icons.rarity_text_color(rar))
		gl.name = "grade"
		_center(gl, Vector2(PANEL.x * 0.5, 46.0), 340.0)
		_panel.add_child(gl)

	var sh := AtlasUI.spr("common_ui", "common_shadow", Design.ASSET_SCALE)
	if sh != null:
		sh.name = "shadow"
		sh.position = Vector2(PANEL.x * 0.5, 210.0)
		_panel.add_child(sh)

	var art := Icons.equip_rect(it, 128.0, rar, bel, _uid)
	if art != null:
		art.name = "art"
		art.position = Vector2(PANEL.x * 0.5 - 64.0, 210.0 - 74.0)
		_panel.add_child(art)

	if dl != null:
		dl.text = _comment(r)


## 상세 본문 — 원작 `setExplain` 은 `Item::getComment()` + 옵션 줄(`CaveItemEquipComent*`)을
## 쌓는다. 우리 대응 = 주 능력 + 부가 옵션 + 귀속 안내(같은 원작 문구 키).
func _comment(r: Dictionary) -> String:
	var it: Dictionary = r["it"]
	var meta: Dictionary = r["meta"]
	var out: Array[String] = []

	var mains: PackedStringArray = []
	for st: String in (it.get("stat_main", {}) as Dictionary):
		mains.append("%s +%d" % [_stat_kr(st), int(it["stat_main"][st])])
	if not mains.is_empty():
		out.append(" · ".join(mains))

	var opts: Array = meta.get("options", [])
	if not opts.is_empty():
		var ol: PackedStringArray = []
		for o in opts:
			var od := o as Dictionary
			ol.append("%s +%d%s" % [_stat_kr(String(od.get("stat", ""))),
				int(od.get("value", 0)), _stat_unit(String(od.get("stat", "")))])
		out.append("부가 옵션 — " + " · ".join(ol))

	var up := int(meta.get("enhance", 0))
	var lim := opts.size() * int(Data.equipment.get("option", {}).get("enhance_per_option", 5))
	out.append("강화 %d / %d" % [up, lim])

	if String(it.get("artifact_effect", "")) != "":
		out.append(String(it["artifact_effect"]))
	if String(it.get("bonus", "")) != "":
		out.append(String(it["bonus"]))
		var st_txt := EquipEffect.status_text(String(it.get("key", "")), Data.equip_effects)
		if st_txt != "":
			out.append(st_txt)

	# 원작 <CaveItemEquipMsg1>/<Msg2> — 장착하면 귀속되는가.
	var bel := int(meta.get("belong", 0))
	if bel > 0:
		out.append("%s%s" % [_dragon_label(bel), " 의 귀속 아이템"])   # <CaveItemEquipBeing>
	elif Equipment.binds_at(int(meta.get("rarity", 0)), Data.equipment):
		out.append(S_BIND_WARN)
	else:
		out.append(S_FREE_WARN)
	return "\n".join(out)


# ------------------------------------------------------------ 실행 (원작 onClickListener)

## tag 0 — 장착/해제.
func _on_action() -> void:
	if _sel < 0 or _sel >= _list.size():
		return
	var r: Dictionary = _list[_sel]
	if bool(r.get("worn", false)):
		PopupType.open(self, S_TITLE, S_UNEQUIP_ASK, _do_unequip, "확인", "취소")
		return
	var bel := int((r["meta"] as Dictionary).get("belong", 0))
	if not Equipment.belong_allows(bel, _uid):
		PopupType.open(self, S_TITLE, S_BELONG_OTHER, Callable(), "확인", "")
		return
	_do_equip()


## 원작 `onClickConfirm` — 확인 후 요청. 오프라인이라 그 자리에서 확정한다.
func _do_equip() -> void:
	var r: Dictionary = _list[_sel]
	var inv_key := String(r.get("inv", ""))
	if inv_key == "" or UserDB.item_count(inv_key) <= 0:
		PopupType.open(self, S_TITLE, "보유하지 않은 장비입니다.", Callable(), "확인", "")
		return
	var cur: Dictionary = UserDB.get_dragon(_uid).get("equip", {})
	var prev := _worn_slot()
	var species_id := int(UserDB.get_dragon(_uid).get("id", 0))
	var next: Dictionary = Equipment.equip(cur, _slot_id, String(r["cat"]), Data.equipment,
		Equipment.item_key_meta(inv_key), species_id)
	if next.is_empty():
		PopupType.open(self, S_TITLE, "이 칸에는 낄 수 없는 장비입니다.", Callable(), "확인", "")
		return
	UserDB.use_item(inv_key, 1)
	if not prev.is_empty():
		UserDB.add_item(Equipment.slot_to_item_key(prev), 1)
	UserDB.set_dragon_field(_uid, "equip", next)
	_after_change()
	if not _dup_main_stats().is_empty():
		PopupType.open(self, S_TITLE, S_DUP_MAIN, Callable(), "확인", "")


func _do_unequip() -> void:
	var cur: Dictionary = UserDB.get_dragon(_uid).get("equip", {})
	var off := _worn_slot()
	if off.is_empty():
		return
	UserDB.add_item(Equipment.slot_to_item_key(off), 1)
	UserDB.set_dragon_field(_uid, "equip", Equipment.unequip(cur, _slot_id))
	_after_change()


## tag 1 — 강화. 원작: `getRarity() < 2` 면 `<CaveItemEquipMsg7>`, 아니면 강화 창.
func _on_upgrade() -> void:
	if _sel < 0 or _sel >= _list.size():
		return
	var r: Dictionary = _list[_sel]
	var meta: Dictionary = r["meta"]
	if int(meta.get("rarity", 0)) < 2:
		PopupType.open(self, S_UPGRADE, S_GRADE_MIN, Callable(), "확인", "")
		return
	var target := ItemEnchantPopup.target_worn(_uid, _slot_id) if bool(r.get("worn", false)) \
		else ItemEnchantPopup.target_bag(String(r.get("inv", "")))
	if target.is_empty():
		PopupType.open(self, S_UPGRADE, S_NONE, Callable(), "확인", "")
		return
	var blocked := Equipment.enchant_blocked(ItemEnchantPopup.slot_view(target), Data.equipment)
	if blocked == "grade_max":
		PopupType.open(self, S_UPGRADE, S_GRADE_MIN, Callable(), "확인", "")
		return
	if blocked == "option_max":
		PopupType.open(self, S_UPGRADE, S_NO_MORE, Callable(), "확인", "")
		return
	ItemEnchantPopup.open(self, target, func(): _after_change())


## 🟦 오프라인 배선 — 위 `_build_panel` 주석 참조.
func _on_lift() -> void:
	var key := String(Data.equipment.get("option", {}).get("unbind_item", "item_disconnect"))
	if UserDB.item_count(key) <= 0:
		PopupType.open(self, S_LIFT, "%s이(가) 없습니다." % Data.item_name(key),
			Callable(), "확인", "")
		return
	PopupType.open(self, S_LIFT,
		"귀속을 해제하시겠습니까?\n장비는 가방으로 돌아갑니다.\n\n%s X %d"
			% [Data.item_name(key), UserDB.item_count(key)],
		func():
			if not UserDB.use_item(key, 1):
				return
			# 원작 `BagPopup.c:22262~` — 귀속을 풀면 장착도 벗기고 슬롯 위치를 −1 로 되돌린다.
			var cur: Dictionary = UserDB.get_dragon(_uid).get("equip", {})
			var sd := _worn_slot()
			if sd.is_empty():
				return
			var freed := sd.duplicate(true)
			freed["belong"] = 0
			UserDB.add_item(Equipment.slot_to_item_key(freed), 1)
			UserDB.set_dragon_field(_uid, "equip", Equipment.unequip(cur, _slot_id))
			_after_change(),
		"확인", "취소")


func _after_change() -> void:
	if _on_change.is_valid():
		_on_change.call()
	_reload()


## 이 칸의 주 능력 중 다른 칸과 겹치는 것이 있는가(원작 <MultyEquip_Slot_Warring_2>).
func _dup_main_stats() -> PackedStringArray:
	var cat := Equipment.catalog(Data.equipment)
	var eqf: Dictionary = UserDB.get_dragon(_uid).get("equip", {})
	var mine: Dictionary = {}
	var others: Dictionary = {}
	for sl in (eqf.get("slots", []) as Array):
		var sd := sl as Dictionary
		var it: Dictionary = cat.get(String(sd.get("key", "")), {})
		for st in (it.get("stat_main", {}) as Dictionary):
			if String(sd.get("slot", "")) == _slot_id:
				mine[st] = true
			else:
				others[st] = true
	var out: PackedStringArray = []
	for st in mine:
		if others.has(st):
			out.append(_stat_kr(String(st)))
	return out


func close() -> void:
	closed.emit()
	queue_free()


# ---------- 표기 ----------

func _slot_kr() -> String:
	return {"all": "전체", "battle": "전투형", "support": "보조형",
		"artifact": "아티팩트"}.get(_slot_id, _slot_id)


func _stat_kr(key: String) -> String:
	return {
		"hp": "HP", "att": "공", "def": "방", "blk": "막기", "evd": "회피", "cri": "크리",
		"cri_pow": "크파", "pure": "관통", "depure": "관통감소", "accuracy": "명중",
		"cure": "치유", "awaken_rate": "각성", "gold": "골드", "exp": "경험",
	}.get(key, key)


## hp/att/def 는 배수(%)다 — `Dragon::getAttAdd` 가 `/100.0` 한다(EquipBelongOption.md §2-2).
func _stat_unit(key: String) -> String:
	var pct: Array = Data.equipment.get("option", {}).get("pct_stats", [])
	if key in pct or key in ["blk", "gold", "exp", "accuracy"]:
		return "%"
	return ""


func _dragon_label(uid: int) -> String:
	var d: Dictionary = UserDB.get_dragon(uid)
	return "다른 드래곤" if d.is_empty() else Icons.name_of(d)


# ---------- 공용 서식 (skills_popup.gd 와 같은 규약) ----------

func _rounded_style(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	return sb


func _hit(root: Control, sz: Vector2, cb: Callable) -> void:
	var b := Button.new()
	b.flat = true
	b.size = sz
	b.pressed.connect(cb)
	root.add_child(b)


func _center(l: Label, c: Vector2, w := 400.0) -> void:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(w, 40)
	l.position = c - l.size * 0.5


func _bm_label(txt: String, scale := 1.0, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = txt
	_bm_style(l, int(round(19.0 * Design.ASSET_SCALE * scale)), col)
	return l


static var _bmfonts: Dictionary = {}
func _bmfont(name: String) -> FontFile:
	if _bmfonts.has(name):
		return _bmfonts[name]
	var p := "res://assets/converted/font_ui/%s.fnt" % name
	if not ResourceLoader.exists(p):
		_bmfonts[name] = null
		return null
	var f: FontFile = load(p).duplicate()
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Gulim"])
	f.fallbacks = [fb]
	_bmfonts[name] = f
	return f


func _bm_style(l: Label, size: int, col: Color, font := "font_subtitle") -> void:
	var f := _bmfont(font)
	if f != null:
		l.add_theme_font_override("font", f)
	else:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 4)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
