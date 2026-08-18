class_name ItemWindow
extends Control

signal closed

const WIN_CAP := Rect2(130, 190, 40, 58)
const WIN_MARGIN := Vector4(10.0, 10.0, 10.0, 140.0)
const DIM_ALPHA := 127.0 / 255.0

const LIST_CAP := Rect2(65, 65, 6, 6)
const LIST_INSET_X := 430.0
const LIST_H := 420.0
const LIST_AT := Vector2(40.0, 40.0)
const TABLE_PAD := Vector2(10.0, 5.0)
const CELL_W := 120.0
const PER_CELL := 3
const SLOT_BOX := Vector2(115.0, 130.0)
const SLOT_COLOR := Color(0, 0, 0, 0.40)
const SLOT_COCOS_Y := [335.0, 205.0, 75.0]

const PANEL := Vector2(350.0, 420.0)
const PANEL_RIGHT_GAP := 30.0
const DESC_BOX := Vector2(340.0, 125.0)
const DESC_COCOS_Y := 120.0
const DESC_CAP := Rect2(25, 25, 3, 3)
const ART_COCOS := Vector2(PANEL.x * 0.5, PANEL.y * 0.5 + 80.0)
const ART_SCALE := 1.5
const ART_SRC := 95.0
const DESC_COLOR := Color8(0x81, 0x43, 0x1D)
const BTN_SIZE := Vector2(180.0, 56.0)
const BTN_CAP := Rect2(20, 20, 4, 4)

const S_TITLE := "아이템 장착"
const S_EQUIP := "장착"
const S_UNEQUIP := "해제"
const S_UPGRADE := "강화"
const S_LIFT := "귀속해제"
const S_GRADE_MIN := "#e98ebbdf"
const S_NO_MORE := "#5bbe7dfd"
const S_ENHANCE_MAX := "이미 최대 강화를 달성했습니다."
const S_BELONG_OTHER := "#198062e4"
const S_UNEQUIP_ASK := "#374ed2cf"
const S_NONE := "#5769c4a4"
const S_BIND_WARN := "\n*사용 후 다른 드래곤에게 장착 불가"
const S_FREE_WARN := "\n*사용 후 다른 드래곤에게 장착 가능"
const S_DUP_MAIN := "같은 메인 옵션의 아이템을 장착하시면\n최상위 메인 옵션이 적용됩니다."

var _uid: int = 0
var _slot_id: String = ""
var _on_change: Callable = Callable()

var _list: Array = []
var _sel: int = -1

var _win: Vector2 = Vector2.ZERO
var _body: Control
var _panel: Control
var _empty_lbl: Label
var _act_label: Label
var _upg_root: Control
var _lift_root: Control
var _slot_nodes: Array = []

static func open(parent: Node, uid: int, slot_id: String,
		on_change := Callable()) -> ItemWindow:
	var p := ItemWindow.new()
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

func _build_title() -> void:
	var t := _bm_label("%s — %s" % [Data.ui(S_TITLE), _slot_kr()], 1.2)
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

static func desc_top() -> float:
	return PANEL.y - DESC_COCOS_Y - DESC_BOX.y * 0.5

func _build_panel() -> void:
	_panel = Control.new()
	_panel.name = "detail"
	_panel.size = PANEL
	_panel.position = Vector2(_win.x - PANEL_RIGHT_GAP - PANEL.x, _win.y - LIST_AT.y - PANEL.y)
	_body.add_child(_panel)

	var dtop := desc_top()
	var tb := AtlasUI.nine("ninepatch_ui", "9patch_text_box", DESC_BOX, DESC_CAP)
	if tb != null:
		tb.position = Vector2(PANEL.x * 0.5 - DESC_BOX.x * 0.5, dtop)
		_panel.add_child(tb)
	var dsc := ScrollContainer.new()
	dsc.name = "desc"
	dsc.position = Vector2(PANEL.x * 0.5 - DESC_BOX.x * 0.5 + 10.0, dtop + 10.0)
	dsc.size = DESC_BOX - Vector2(20.0, 20.0)
	dsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(dsc)
	var dl := Label.new()
	dl.name = "desc_label"
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.custom_minimum_size = Vector2(DESC_BOX.x - 40.0, 0)
	_bm_style(dl, int(round(17.0 * Design.ASSET_SCALE * 0.8)), DESC_COLOR, "font_common")
	dsc.add_child(dl)

	_upg_root = _make_button(Vector2(PANEL.x * 0.5 - 95.0, PANEL.y), S_UPGRADE, _on_upgrade)
	var act := _make_button(Vector2(PANEL.x * 0.5 + 95.0, PANEL.y), S_EQUIP, _on_action)
	_act_label = act.get_node("label") as Label

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
	_list.append_array(rest)
	_list.sort_custom(Equipment.display_sort_less)

	if not _list.is_empty():
		_sel = 0
	_rebuild_cells()
	_refresh_panel()

func _worn_slot() -> Dictionary:
	for s in (UserDB.get_dragon(_uid).get("equip", {}).get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) == _slot_id:
			return s
	return {}

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

	var up := int(meta.get("enhance", 0))
	if up > 0:
		var ul := Label.new()
		ul.text = "+ %d" % up
		ul.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ul.size = Vector2(SLOT_BOX.x - 20.0, 20.0)
		ul.position = Vector2(10.0, SLOT_BOX.y - 10.0 - 20.0)
		_bm_style(ul, int(round(13.0 * Design.ASSET_SCALE)), Color(1, 0.92, 0.55))
		root.add_child(ul)

	var nl := Label.new()
	nl.text = String(it.get("name", ""))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.size = Vector2(SLOT_BOX.x - 8.0, 34.0)
	nl.position = Vector2(4.0, SLOT_BOX.y - 44.0)
	_bm_style(nl, int(round(11.0 * Design.ASSET_SCALE)),
		Icons.rarity_text_color(int(meta.get("rarity", 0))))
	root.add_child(nl)

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

func _on_click_item(index: int) -> void:
	if index == _sel:
		return
	_sel = index
	_refresh_slots()
	_refresh_panel()

func _refresh_panel() -> void:
	_clear_detail()

	if _sel < 0 or _sel >= _list.size():
		_act_label.text = S_EQUIP
		_upg_root.modulate = Color(0.6, 0.6, 0.6)
		_lift_root.visible = false
		return

	var r: Dictionary = _list[_sel]
	var meta: Dictionary = r["meta"]
	var rar := int(meta.get("rarity", 0))
	var bel := int(meta.get("belong", 0))
	var worn := bool(r.get("worn", false))

	_act_label.text = S_UNEQUIP if worn else S_EQUIP
	_upg_root.modulate = Color.WHITE if rar >= 2 else Color(0.6, 0.6, 0.6)
	_lift_root.visible = worn and bel > 0

	_paint_detail(r)

func _clear_detail() -> void:
	for nm in ["name", "shadow", "art"]:
		var old := _panel.get_node_or_null(nm)
		if old != null:
			_panel.remove_child(old)
			old.queue_free()
	var dl := _panel.get_node_or_null("desc/desc_label") as Label
	if dl != null:
		dl.text = ""

func _paint_detail(r: Dictionary) -> void:
	var it: Dictionary = r["it"]
	var meta: Dictionary = r["meta"]
	var rar := int(meta.get("rarity", 0))
	var dl := _panel.get_node_or_null("desc/desc_label") as Label

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

	var sh := AtlasUI.spr("common_ui", "common_shadow", Design.ASSET_SCALE)
	if sh != null:
		sh.name = "shadow"
		sh.position = Vector2(PANEL.x * 0.5, 210.0)
		_panel.add_child(sh)

	var abox := ART_SRC * ART_SCALE * Design.ASSET_SCALE
	var art := Icons.equip_rect(it, abox, rar, 0, _uid)
	if art != null:
		art.name = "art"
		art.position = Vector2(ART_COCOS.x, PANEL.y - ART_COCOS.y) - Vector2(abox, abox) * 0.5
		_panel.add_child(art)

	if dl != null:
		var body := _comment(r)
		dl.text = ("[%s]\n%s" % [gname, body]) if gname != "" else body

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
			var ost := String(od.get("stat", ""))
			ol.append(Equipment.option_text(_stat_kr(ost), ost,
				int(od.get("value", 0)), Data.equipment))
		out.append("부가 옵션 — " + " · ".join(ol))

	var up := int(meta.get("enhance", 0))
	var lim := Equipment.enhance_cap(int(meta.get("rarity", 0)), opts.size(), Data.equipment)
	out.append("강화 %d / %d" % [up, lim])

	if String(it.get("artifact_effect", "")) != "":
		out.append(String(it["artifact_effect"]))
	if String(it.get("bonus", "")) != "":
		out.append(String(it["bonus"]))
		var st_txt := EquipEffect.status_text(String(it.get("key", "")), Data.equip_effects)
		if st_txt != "":
			out.append(st_txt)
	var custom_desc := Data.equipment_description(String(r.get("cat", "")))
	if custom_desc != "":
		out.append(custom_desc)

	var bel := int(meta.get("belong", 0))
	if bel > 0:
		out.append("%s%s" % [_dragon_label(bel), " 의 귀속 아이템"])
	elif Equipment.binds_at(int(meta.get("rarity", 0)), Data.equipment):
		out.append(S_BIND_WARN)
	else:
		out.append(S_FREE_WARN)
	return "\n".join(out)

func _on_action() -> void:
	if _sel < 0 or _sel >= _list.size():
		return
	var r: Dictionary = _list[_sel]
	if bool(r.get("worn", false)):
		MessageWindow.open(self, Data.ui(S_TITLE), Data.ui(S_UNEQUIP_ASK), _do_unequip, "확인", "취소")
		return
	var bel := int((r["meta"] as Dictionary).get("belong", 0))
	if not Equipment.belong_allows(bel, _uid):
		MessageWindow.open(self, Data.ui(S_TITLE), Data.ui(S_BELONG_OTHER), Callable(), "확인", "")
		return
	_do_equip()

func _do_equip() -> void:
	var r: Dictionary = _list[_sel]
	var inv_key := String(r.get("inv", ""))
	if inv_key == "" or UserDB.item_count(inv_key) <= 0:
		MessageWindow.open(self, Data.ui(S_TITLE), "보유하지 않은 장비입니다.", Callable(), "확인", "")
		return
	var cur: Dictionary = UserDB.get_dragon(_uid).get("equip", {})
	var prev := _worn_slot()
	var species_id := int(UserDB.get_dragon(_uid).get("id", 0))
	var next: Dictionary = Equipment.equip(cur, _slot_id, String(r["cat"]), Data.equipment,
		Equipment.item_key_meta(inv_key), species_id)
	if next.is_empty():
		MessageWindow.open(self, Data.ui(S_TITLE), "이 칸에는 낄 수 없는 장비입니다.", Callable(), "확인", "")
		return
	UserDB.use_item(inv_key, 1)
	if not prev.is_empty():
		UserDB.add_item(Equipment.slot_to_item_key(prev), 1)
	UserDB.set_dragon_field(_uid, "equip", next)
	_after_change()
	if not _dup_main_stats().is_empty():
		MessageWindow.open(self, Data.ui(S_TITLE), S_DUP_MAIN, Callable(), "확인", "")

func _do_unequip() -> void:
	var cur: Dictionary = UserDB.get_dragon(_uid).get("equip", {})
	var off := _worn_slot()
	if off.is_empty():
		return
	UserDB.add_item(Equipment.slot_to_item_key(off), 1)
	UserDB.set_dragon_field(_uid, "equip", Equipment.unequip(cur, _slot_id))
	_after_change()

func _on_upgrade() -> void:
	if _sel < 0 or _sel >= _list.size():
		return
	var r: Dictionary = _list[_sel]
	var meta: Dictionary = r["meta"]
	if int(meta.get("rarity", 0)) < 2:
		MessageWindow.open(self, S_UPGRADE, Data.ui(S_GRADE_MIN), Callable(), "확인", "")
		return
	var target := ItemEnchantView.target_worn(_uid, _slot_id) if bool(r.get("worn", false)) \
		else ItemEnchantView.target_bag(String(r.get("inv", "")))
	if target.is_empty():
		MessageWindow.open(self, S_UPGRADE, Data.ui(S_NONE), Callable(), "확인", "")
		return
	var blocked := Equipment.enchant_blocked(ItemEnchantView.slot_view(target), Data.equipment)
	if blocked == "min_grade":
		MessageWindow.open(self, S_UPGRADE, Data.ui(S_GRADE_MIN), Callable(), "확인", "")
		return
	if blocked == "grade_max":
		MessageWindow.open(self, S_UPGRADE, S_ENHANCE_MAX, Callable(), "확인", "")
		return
	if blocked == "option_max":
		MessageWindow.open(self, S_UPGRADE, Data.ui(S_NO_MORE), Callable(), "확인", "")
		return
	ItemEnchantView.open(self, target, func(): _after_change())

func _on_lift() -> void:
	var key := String(Data.equipment.get("option", {}).get("unbind_item", "item_disconnect"))
	if UserDB.item_count(key) <= 0:
		MessageWindow.open(self, S_LIFT, "%s이(가) 없습니다." % Data.item_name(key),
			Callable(), "확인", "")
		return
	MessageWindow.open(self, S_LIFT,
		"귀속을 해제하시겠습니까?\n장비는 가방으로 돌아갑니다.\n\n%s X %d"
			% [Data.item_name(key), UserDB.item_count(key)],
		func():
			if not UserDB.use_item(key, 1):
				return
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

func _slot_kr() -> String:
	return {"all": "전체", "battle": "전투형", "support": "보조형",
		"artifact": "아티팩트"}.get(_slot_id, _slot_id)

func _stat_kr(key: String) -> String:
	return {
		"hp": "HP", "att": "공", "def": "방", "blk": "막기", "evd": "회피", "cri": "크리",
		"cri_pow": "크파", "pure": "관통", "depure": "관통감소", "accuracy": "명중",
		"cure": "치유", "awaken_rate": "각성", "gold": "골드", "exp": "경험",
	}.get(key, key)

func _dragon_label(uid: int) -> String:
	var d: Dictionary = UserDB.get_dragon(uid)
	return "다른 드래곤" if d.is_empty() else Icons.name_of(d)

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
