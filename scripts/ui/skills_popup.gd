class_name SkillsPopup
extends Control
## 드래곤 스킬 장착/해제 창 — 원작 `cocos2d::SkillsPopup` 1:1 이식. render 층(CLAUDE.md §8.1).
##
## 포팅 카드 = `docs/ref/porting/SkillsPopup.md`(좌표·동작 표 전부).
## 참조 스크린샷 = `docs/ref/드래곤_스킬장착탭.png`.
## 디컴프 = `docs/ref/orig_code/decomp/SkillsPopup.c` · `SkillsTableViewCell.c`.
##
## 진입 데이터는 원작과 나란하다 — 원작 `create(Dragon*)` + `setSelectTag(slot)`,
## 우리 `open(parent, uid, slot, on_change)`.
##
## 좌표 규약: 원작 리터럴은 cocos(y-up, 창 좌하단 원점) **포인트**다(§9 — ASSET_SCALE 을
## 다시 곱하지 않는다). 여기서는 `창높이 − cocos y` 로 뒤집어 적는다.

signal closed

# ---------- 원작 리터럴 (SkillsPopup.c) ----------

## `setContentSprite("9patch/popup4.png", CCRect(130,190,40,58), 10,10,10,140)` —
## 마지막 4인자는 **화면에서 뺄 여백**(left,right,bottom,top)이다(PopupLayer.c:011f709c).
const WIN_CAP := Rect2(130, 190, 40, 58)
const WIN_MARGIN := Vector4(10.0, 10.0, 10.0, 140.0)   # left, right, bottom, top
## `PopupLayer::show(..., 127.0)` 딤 + `CCScaleTo` 팝 연출.
const DIM_ALPHA := 127.0 / 255.0

## 목록 상자 `9patch/scroll_box` cap(65,65,6,6) — `(w−430) × 420` @ (40,40) anchor(0,0).
const LIST_CAP := Rect2(65, 65, 6, 6)
const LIST_INSET_X := 430.0
const LIST_H := 420.0
const LIST_AT := Vector2(40.0, 40.0)
## `CCTableView` 는 상자보다 (20,10) 작고 (10,5) 안쪽이다.
const TABLE_PAD := Vector2(10.0, 5.0)
## `cellSizeForTable` = (120, 표높이). 셀 하나가 **세로 3칸**.
const CELL_W := 120.0
const PER_CELL := 3
## `RoundedLayer(115,130, 0x66000000)` — 프레임이 아니라 색+라운드로 그리는 레이어.
const SLOT_BOX := Vector2(115.0, 130.0)
const SLOT_COLOR := Color(0, 0, 0, 0.40)
## 셀 로컬 cocos y (`initWithSize`: h*2+h/2+10 / h+h/2+10 / h/2+10).
const SLOT_COCOS_Y := [335.0, 205.0, 75.0]

## 우측 상세 패널 `CCLayer 350×420` @ (w−30, 40) anchor(1,0).
const PANEL := Vector2(350.0, 420.0)
const PANEL_RIGHT_GAP := 30.0
## 패널 안쪽 — BagPopup 상세 패널과 같은 규격(cave.gd `_inv_detail_*` 와 좌표 일치).
const DESC_BOX := Vector2(340.0, 125.0)
const DESC_CAP := Rect2(25, 25, 3, 3)
const DESC_COLOR := Color8(0x81, 0x43, 0x1D)
## `RoundedButton(CCSize(180,56), type 0)` @ (175, 0) anchor(0.5, 0).
const BTN_SIZE := Vector2(180.0, 56.0)
const BTN_CAP := Rect2(20, 20, 4, 4)

## `Skill::getSkillType()` → 모양 마크 프레임. ☆(그 외)는 원작도 `common/element_bg` 로 떨어진다.
const TYPE_MARK := {"cir": "common_skill_circle_mark", "sq": "common_skill_square_mark",
	"tri": "common_skill_triangle_mark"}
## `Skill::getAttribute()` 첫 글자 → `item/item_small/ele_*` (onClickSkill 의 switch 그대로).
const ATTR_ICON := {"A": "ele_water", "C": "ele_chaos", "D": "ele_dark", "E": "ele_ground",
	"F": "ele_fire", "H": "ele_holy", "L": "ele_light", "S": "ele_shadow", "W": "ele_wind"}

# ---------- 상태 ----------

var _uid: int = 0
var _slot: int = 0
var _on_change: Callable = Callable()

## 원작 `this+0x278` — 학습 풀 목록([{id, level}]). 장착 중인 스킬이 index 0 으로 스왑된다.
var _list: Array = []
## 원작 `this+0x280` 선택 인덱스 / `this+0x288` 선택 스킬.
var _sel: int = -1

var _win: Vector2 = Vector2.ZERO
var _body: Control
var _panel: Control
var _empty_lbl: Label
var _btn_label: Label
var _slot_nodes: Array = []      # [{root, overlay, index}]


## 원작 `SkillsPopup::create(dragon)` + `setSelectTag(slot)` + `show()`.
static func open(parent: Node, uid: int, slot: int, on_change := Callable()) -> SkillsPopup:
	var p := SkillsPopup.new()
	p._uid = uid
	p._slot = slot
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
	_body.position = ((vis - _win) * 0.5).round()     # VisibleRect::center()
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

## 제목(`<skill>`) + 도움말(`common/btn_info`) + 닫기(`common/close_btn`).
## 원작에 **제목바 프레임이 없다** — 맨 라벨이다(참조 스크린샷과 일치).
func _build_title() -> void:
	var t := _bm_label("스킬", 1.2)
	_center(t, Vector2(_win.x * 0.5, 45.0), 400.0)
	_body.add_child(t)

	var isz := AtlasUI.size_pt("common_ui", "common_btn_info") * 1.05
	var iroot := Control.new()
	iroot.size = isz
	iroot.position = Vector2(_win.x * 0.5 + 60.0, 45.0) - isz * 0.5
	_body.add_child(iroot)
	var ispr := AtlasUI.spr("common_ui", "common_btn_info", Design.ASSET_SCALE * 1.05)
	if ispr != null:
		ispr.position = isz * 0.5
		iroot.add_child(ispr)
	_hit(iroot, isz, _on_info)

	var csz := AtlasUI.size_pt("common_ui", "common_close_btn") * 1.5
	var x := TextureButton.new()
	var ct := AtlasUI.tex("common_ui", "common_close_btn")
	if ct != null:
		x.texture_normal = ct
		x.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 1.5
	x.position = Vector2(_win.x - 50.0, 50.0) - csz * 0.5
	x.pressed.connect(close)
	_body.add_child(x)


## 목록 상자 + 가로 스크롤 표.
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

	# 빈 목록 라벨 `<noskill>` — 원작 numberOfCellsInTableView 가 setVisible(cells==0).
	_empty_lbl = _bm_label("스킬이 없습니다.", 0.9)
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


## 우측 상세 패널(원작 `CCLayer 350×420` anchor(1,0)).
func _build_panel() -> void:
	_panel = Control.new()
	_panel.name = "detail"
	_panel.size = PANEL
	_panel.position = Vector2(_win.x - PANEL_RIGHT_GAP - PANEL.x, _win.y - LIST_AT.y - PANEL.y)
	_body.add_child(_panel)

	# 설명 상자 + 스크롤 — 값이 바뀌어도 그릇은 남는다.
	var tb := AtlasUI.nine("ninepatch_ui", "9patch_text_box", DESC_BOX, DESC_CAP)
	if tb != null:
		tb.position = Vector2(PANEL.x * 0.5 - DESC_BOX.x * 0.5, PANEL.y - 120.0 - DESC_BOX.y * 0.5)
		_panel.add_child(tb)
	var dsc := ScrollContainer.new()
	dsc.name = "desc"
	dsc.position = Vector2(PANEL.x * 0.5 - DESC_BOX.x * 0.5 + 10.0,
		PANEL.y - 120.0 - DESC_BOX.y * 0.5 + 10.0)
	dsc.size = DESC_BOX - Vector2(20.0, 20.0)
	dsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(dsc)
	var dl := Label.new()
	dl.name = "desc_label"
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.custom_minimum_size = Vector2(DESC_BOX.x - 40.0, 0)
	_bm_style(dl, int(round(17.0 * Design.ASSET_SCALE * 0.8)), DESC_COLOR, "font_common")
	dsc.add_child(dl)

	# 실행 버튼 — cocos (175,0) anchor(0.5,0) ⇒ 패널 바닥에 붙는다.
	var broot := Control.new()
	broot.name = "action"
	broot.size = BTN_SIZE
	broot.position = Vector2(PANEL.x * 0.5 - BTN_SIZE.x * 0.5, PANEL.y - BTN_SIZE.y)
	_panel.add_child(broot)
	var bnp := AtlasUI.nine("ninepatch_ui", "9patch_btn", BTN_SIZE, BTN_CAP)
	if bnp != null:
		broot.add_child(bnp)
	_btn_label = Label.new()
	_btn_label.text = "장착"
	_btn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_btn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_btn_label.size = BTN_SIZE
	_bm_style(_btn_label, int(round(19.0 * Design.ASSET_SCALE * 0.95)), Color.WHITE)
	broot.add_child(_btn_label)
	_hit(broot, BTN_SIZE, _on_action)


# ------------------------------------------------------------ 목록/선택 (원작 setSKillsList)

## 원작 `setSKillsList`(:2740) — 학습 풀 전체를 깔고, 이 칸에 꽂힌 스킬을 index 0 으로 스왑한다.
func _reload() -> void:
	_list = []
	for e in UserDB.dragon_skills(_uid):
		_list.append({"id": int((e as Dictionary).get("id", 0)),
			"level": int((e as Dictionary).get("level", 1))})
	_sel = -1
	var here := _equipped_id(_slot)
	if here > 0:
		for i in _list.size():
			if int((_list[i] as Dictionary)["id"]) == here:
				var tmp = _list[0]
				_list[0] = _list[i]
				_list[i] = tmp
				_sel = 0
				break
	_rebuild_cells()
	_refresh_panel()


## 원작 `tableCellAtIndex` — 셀 = 세로 3칸, 가로로 늘어선다(direction 0 = 가로).
## 우리 학습 풀은 최대 수십 개라 dequeue 재활용 없이 전부 만든다(보이는 모양은 같다).
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
		var center := Vector2(col * CELL_W + CELL_W * 0.5,
			table_h - float(SLOT_COCOS_Y[row]))
		_slot_nodes.append(_make_slot(strip, center, i))
	_refresh_slots()


## 원작 `SkillsTableViewCell::initWithSize` 의 한 칸 —
## `RoundedLayer(115,130, 0x66000000)` + 스킬 그림, 그 위 z=1 tag=100 오버레이.
func _make_slot(parent: Control, center: Vector2, index: int) -> Dictionary:
	var e: Dictionary = _list[index]
	var sid := int(e.get("id", 0))
	var root := Control.new()
	root.size = SLOT_BOX
	root.position = center - SLOT_BOX * 0.5
	parent.add_child(root)

	var bg := Panel.new()
	bg.size = SLOT_BOX
	bg.add_theme_stylebox_override("panel", _rounded_style(SLOT_COLOR))
	root.add_child(bg)

	var art := _skill_sprite(sid, int(e.get("level", 1)), 1.0)
	if art != null:
		art.position = SLOT_BOX * 0.5
		root.add_child(art)

	# tag=100 오버레이 — `updateSkillBtn` 4번째 인자(다른 칸 포함 **이미 장착 중**)일 때만.
	var ov := Panel.new()
	ov.size = SLOT_BOX
	ov.add_theme_stylebox_override("panel", _rounded_style(SLOT_COLOR))
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.visible = false
	root.add_child(ov)

	_hit(root, SLOT_BOX, func(): _on_click_skill(index))
	return {"root": root, "overlay": ov, "index": index}


## 원작 `Skill::getImageSprite()` — 스킬 그림 + **등급 뱃지**(좌상단 파란 원 안의 로마숫자).
## 뱃지 프레임 = `skill/skill_lv1`~`lv5`(원본 `DV2/480/skill.img_plist` 실재, 26×26px).
## `Skill` 클래스는 디컴프 대상 밖이라 좌표 리터럴이 없다 →
## 참조 스크린샷 실측(뱃지 중심 = 그림 좌상단 모서리에서 안쪽으로 약 (7,4)pt)으로 맞췄다.
func _skill_sprite(sid: int, level: int, mult: float) -> Node2D:
	var tex := AtlasUI.tex("skill", "skill_%d" % sid)
	if tex == null:
		return null
	var S := Design.ASSET_SCALE * mult
	var root := Node2D.new()
	var s := Sprite2D.new()
	s.texture = tex
	s.material = AtlasUI.pma()
	s.scale = Vector2(S, S)
	root.add_child(s)
	var bt := AtlasUI.tex("skill", "skill_skill_lv%d" % clampi(level, 1, 5))
	if bt != null:
		var b := Sprite2D.new()
		b.texture = bt
		b.material = AtlasUI.pma()
		b.scale = Vector2(S, S)
		var half := tex.get_size() * 0.5 * S
		b.position = Vector2(-half.x + 7.0 * mult, -half.y + 4.0 * mult)
		root.add_child(b)
	return root


## 원작 `updateCellSkillBtn`(:3053) — selected / equippedAnywhere 두 상태만 반영한다.
func _refresh_slots() -> void:
	var eq0 := _equipped_id(0)
	var eq1 := _equipped_id(1)
	for n in _slot_nodes:
		var d: Dictionary = n
		var i := int(d["index"])
		var sid := int((_list[i] as Dictionary)["id"])
		var root: Control = d["root"]
		var ov: Panel = d["overlay"]
		ov.visible = sid > 0 and (sid == eq0 or sid == eq1)
		# ASSUMPTION: 원작 `updateSkillBtn` 의 선택 표시는 `setColor({0,100,0} / BLACK)` 인데,
		#   `CCMenuItemImageEx` 의 cascadeColor 가 꺼져 있어 **화면에 아무 변화가 없다**
		#   (참조 스크린샷에서도 선택 칸에 색 변화가 없다 — 픽셀 실측: 딤 1겹 = 장착분 뿐).
		#   PC 는 클릭 피드백이 필요해 아주 옅은 밝기만 더한다. 원작 근거는 없다.
		root.modulate = Color(1.18, 1.18, 1.05) if i == _sel else Color.WHITE


## 원작 `onClickSkill`(:1814).
func _on_click_skill(index: int) -> void:
	if index == _sel:
		return
	_sel = index
	_refresh_slots()
	_refresh_panel()


# ------------------------------------------------------------ 상세 패널 (원작 setExplain)

func _refresh_panel() -> void:
	# 값이 바뀌는 것만 지운다 — 설명 상자·버튼 그릇은 남긴다.
	for nm in ["name", "shadow", "art", "mark", "attr"]:
		var old := _panel.get_node_or_null(nm)
		if old != null:
			_panel.remove_child(old)
			old.queue_free()
	var dl := _panel.get_node_or_null("desc/desc_label") as Label
	if dl != null:
		dl.text = ""

	if _sel < 0 or _sel >= _list.size():
		_btn_label.text = "장착"
		return

	var e: Dictionary = _list[_sel]
	var sid := int(e.get("id", 0))
	var sd: Dictionary = Data.skills.get(str(sid), {})

	# 버튼 라벨 — 원작: 선택이 index 0(= 이 칸 장착분)이면 해제, 아니면 장착.
	_btn_label.text = "해제" if sid == _equipped_id(_slot) and sid > 0 else "장착"

	var nm := _bm_label("%s Lv.%d" % [String(sd.get("name", "스킬 %d" % sid)),
		int(e.get("level", 1))], 0.8)
	nm.name = "name"
	_center(nm, Vector2(175.0, 10.0), 340.0)
	_panel.add_child(nm)

	var sh := AtlasUI.spr("common_ui", "common_shadow", Design.ASSET_SCALE)
	if sh != null:
		sh.name = "shadow"
		sh.position = Vector2(175.0, 210.0)
		_panel.add_child(sh)

	var art := _skill_sprite(sid, int(e.get("level", 1)), 1.3)   # 원작 setScale(1.3)
	if art != null:
		art.name = "art"
		art.position = Vector2(175.0, 130.0)
		_panel.add_child(art)

	var mk := AtlasUI.spr("common_ui",
		String(TYPE_MARK.get(String(sd.get("slot", "")), "common_element_bg")),
		Design.ASSET_SCALE)
	if mk != null:
		mk.name = "mark"
		mk.position = Vector2(60.0, 50.0)
		_panel.add_child(mk)

	# 속성 아이콘 — data/skills.json 39종에 속성 열이 없다(전부 빈 값).
	# 원작도 `getAttribute()` 가 비면 안 그린다(같은 분기) → 값이 생기면 자동으로 켜진다.
	var attr := String(sd.get("attribute", "")).to_upper()
	if attr != "" and ATTR_ICON.has(attr.substr(0, 1)):
		var ai := AtlasUI.spr("item_small_ui",
			"item_item_small_%s" % String(ATTR_ICON[attr.substr(0, 1)]),
			Design.ASSET_SCALE * 0.55)
		if ai != null:
			ai.name = "attr"
			ai.position = Vector2(60.0, 110.0)
			_panel.add_child(ai)

	if dl != null:
		dl.text = _comment(sd)


## 원작 본문 = `Item::getComment() + "   "`. 우리 대응 = skills.json `effect_text`
## (+ 사용횟수·칸일치 안내는 우리 요약 — 원작 그릇 안에 유지, cave.gd `_inv_detail_lines` 와 같은 원칙).
func _comment(sd: Dictionary) -> String:
	var out: Array[String] = []
	var eff := String(sd.get("effect_text", ""))
	if eff != "":
		out.append(eff)
	var lim := String(sd.get("number_limit_raw", ""))
	if lim != "":
		out.append("사용 횟수 %s" % lim)
	var dr := UserDB.get_dragon(_uid)
	var ty := String(Loadout.slot_types(dr)[_slot]) if _slot < Loadout.SKILL_SLOTS else "star"
	if Loadout.slot_matches(ty, sd):
		out.append("칸 타입 일치 — 추가효과 발생")
	var notes := String(sd.get("notes", ""))
	if notes != "":
		out.append(notes)
	return "\n".join(out)


# ------------------------------------------------------------ 실행 (원작 onClickListener)

## 원작 `onClickListener`(:1461) 의 4분기 그대로.
func _on_action() -> void:
	if _sel < 0 or _sel >= _list.size():
		return
	var sid := int((_list[_sel] as Dictionary)["id"])
	if sid <= 0:
		return
	var other := 1 - _slot
	# ② 반대 칸에 이미 장착 중 → 원작은 **교환하지 않고** 안내만 한다.
	if other >= 0 and other < Loadout.SKILL_SLOTS and _equipped_id(other) == sid:
		_notice("이미 장착 중인 스킬입니다.\n장착 슬롯을 바꾸려면 해당 스킬을 장착 해제 해주세요.")
		return
	# ③ 이 칸에 장착 중 → disarmament (ns=0)
	if _equipped_id(_slot) == sid:
		_apply(0)
		return
	# ④ 장착
	_apply(sid)


func _apply(skill_id: int) -> void:
	UserDB.set_dragon_skill_equip(_uid, _slot, skill_id)
	if _on_change.is_valid():
		_on_change.call()
	_reload()


func _equipped_id(slot: int) -> int:
	if slot < 0 or slot >= Loadout.SKILL_SLOTS:
		return 0
	var ids: Array = Loadout.equipped_ids(UserDB.get_dragon(_uid))
	return int(ids[slot]) if slot < ids.size() else 0


## 원작 `onClickInfo` → `ToolTipLayer(ToolTipObject(30), 640×440)`.
## 문구는 원작 문자열 그대로(`<ToolTipDragonSkill>` / `<ToolTipDragonSkillExplain>`).
func _on_info() -> void:
	_notice("드래곤 스킬은 드래곤이 전투에서 사용하는 스킬입니다.\n"
		+ "드래곤빌리지2의 모든 드래곤들은 \n전투에서 최대 2개의 스킬을 사용하고 있습니다.\n"
		+ "새로운 스킬을 배우기 위해서는 스킬 스크롤이 필요합니다.\n\n"
		+ "같은 스킬이라도 스킬과 슬롯의 타입이 일치하는 경우 \n추가 효과가 발생합니다.\n"
		+ "스킬 타입은 동그라미, 네모, 세모 세가지 타입이 있습니다.\n\n"
		+ "스킬 슬롯에는 별 타입의 특수 슬롯이 존재하는데 \n모든 스킬의 추가 효과를 발생 시킵니다.\n"
		+ "또한 같은 스킬이라도 스킬 등급이 높을수록 \n더 뛰어난 성능을 발휘합니다.", "드래곤 스킬")


func _notice(msg: String, title := "알림") -> void:
	PopupType.open(self, title, msg, Callable(), "확인", "")


func close() -> void:
	closed.emit()
	queue_free()


# ---------- 공용 서식 ----------

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


## 원작 BMFont(`getFontName_subtitle` / `_common`). 한글 보강본 = `assets/converted/font_ui/`
## (CLAUDE.md §10) — 비트맵이라 `fixed_size_scale_mode` 를 켜야 `font_size` 가 먹는다.
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
