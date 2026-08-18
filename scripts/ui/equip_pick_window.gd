class_name EquipPickWindow
extends ItemWindow

const S_SELECT_TITLE := "장비 선택"
const S_SELECT := "선택"
const S_ASK_REGEN := "#e5a90c1a"
const S_EQUIPPING := "장착 중"
const S_NOT_ENOUGH := "#76c58d45"
const S_NO_TARGET := "이 등급의 장비를 갖고 있지 않습니다."

const GRADE_TAG := ["일반", "매직", "레어", "유니크", "에픽", "초월"]

const CANVAS_LAYER := 66

var _coin_key: String = ""
var _req_grade: int = -1
var _canvas: CanvasLayer
var _on_done: Callable = Callable()

static func create(parent: Node, coin_key: String,
		on_done := Callable()) -> EquipPickWindow:
	var p := EquipPickWindow.new()
	p._coin_key = coin_key
	p._req_grade = reroll_grade_of(coin_key)
	p._on_done = on_done
	p._uid = int(UserDB.active_dragon().get("uid", 0))
	p._canvas = CanvasLayer.new()
	p._canvas.layer = CANVAS_LAYER
	parent.add_child(p._canvas)
	p._canvas.add_child(p)
	p._build()
	return p

static func reroll_grade_of(item_key: String) -> int:
	var items: Dictionary = Data.equipment.get("option", {}).get("reroll_items", {})
	for g in items:
		if String(items[g]) == item_key:
			return int(String(g))
	return -1

func close() -> void:
	closed.emit()
	if is_instance_valid(_canvas):
		_canvas.queue_free()
	else:
		queue_free()

func _build_title() -> void:
	var t := _bm_label(S_SELECT_TITLE, 1.2)
	_center(t, Vector2(_win.x * 0.5, 45.0), 520.0)
	_body.add_child(t)

	if _req_grade >= 0 and _req_grade < GRADE_TAG.size():
		var tag := _bm_label("[%s]" % GRADE_TAG[_req_grade], 1.2,
			Icons.rarity_text_color(_req_grade))
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag.size = Vector2(220.0, 40.0)
		tag.position = Vector2(_win.x * 0.5 - t.get_minimum_size().x * 0.5 - 25.0 - tag.size.x,
			45.0 - tag.size.y * 0.5)
		_body.add_child(tag)

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
	super()
	_empty_lbl.text = S_NO_TARGET

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

	_make_button(Vector2(PANEL.x * 0.5, PANEL.y), S_SELECT, _on_select)

func _reload() -> void:
	_list = []
	_sel = -1
	if _req_grade < 0:
		_rebuild_cells()
		_refresh_panel()
		return
	var cat := Equipment.catalog(Data.equipment)

	for d in UserDB.dragons():
		var dd := d as Dictionary
		var duid := int(dd.get("uid", 0))
		for s in (dd.get("equip", {}).get("slots", []) as Array):
			var sd := s as Dictionary
			if int(sd.get("grade", 0)) != _req_grade:
				continue
			var wit: Dictionary = cat.get(String(sd.get("key", "")), {})
			if wit.is_empty():
				continue
			_list.append({"cat": String(sd["key"]), "it": wit, "worn": true,
				"inv": "", "n": 1, "uid": duid, "slot": String(sd.get("slot", "")),
				"meta": {"belong": int(sd.get("belong", 0)),
					"rarity": int(sd.get("grade", 0)),
					"enhance": int(sd.get("enhance", 0)),
					"options": sd.get("options", [])}})

	var inv: Dictionary = UserDB.inventory()
	for ik in inv.keys():
		var ck := Equipment.parse_item_key(String(ik))
		if ck == "" or int(inv[ik]) <= 0 or not cat.has(ck):
			continue
		var meta := Equipment.item_key_meta(String(ik))
		if int(meta.get("rarity", 0)) != _req_grade:
			continue
		_list.append({"cat": ck, "it": cat[ck], "worn": false, "inv": String(ik),
			"n": int(inv[ik]), "uid": 0, "slot": "", "meta": meta})

	_list.sort_custom(Equipment.display_sort_less)

	for i in _list.size():
		var r: Dictionary = _list[i]
		if bool(r.get("worn", false)) and int(r.get("uid", 0)) == _uid:
			_sel = i
			break

	_rebuild_cells()
	_refresh_panel()

func _make_slot(parent: Control, center: Vector2, index: int) -> Dictionary:
	var d := super(parent, center, index)
	if bool((_list[index] as Dictionary).get("worn", false)):
		var root: Control = d["root"]
		var l := Label.new()
		l.text = S_EQUIPPING
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size = SLOT_BOX
		_bm_style(l, int(round(14.0 * Design.ASSET_SCALE)), Color(0.92, 0.92, 0.92))
		root.add_child(l)
	return d

func _refresh_panel() -> void:
	_clear_detail()
	if _sel >= 0 and _sel < _list.size():
		_paint_detail(_list[_sel])

func _on_select() -> void:
	if _sel < 0 or _sel >= _list.size():
		return
	var have := UserDB.item_count(_coin_key)
	if have <= 0:
		MessageWindow.open(self, S_SELECT_TITLE, Data.ui(S_NOT_ENOUGH), Callable(), "확인", "")
		return
	var r: Dictionary = _list[_sel]
	var it: Dictionary = r["it"]
	var meta: Dictionary = r["meta"]
	var up := int(meta.get("enhance", 0))
	var opts: PackedStringArray = []
	for o in (meta.get("options", []) as Array):
		opts.append(EquipOptionView.opt_text(o as Dictionary, Data.equipment))
	var head := "%s%s" % [String(it.get("name", "?")), (" +%d" % up) if up > 0 else ""]
	var msg := "%s\n%s\n\n%s\n\n%s  X %d" % [head, " · ".join(opts), Data.ui(S_ASK_REGEN),
		Data.item_name(_coin_key), have]
	MessageWindow.open(self, S_SELECT_TITLE, msg, func(): _do_regen(r), "확인", "취소")

func _do_regen(r: Dictionary) -> void:
	if not UserDB.use_item(_coin_key, 1):
		MessageWindow.open(self, S_SELECT_TITLE, Data.ui(S_NOT_ENOUGH), Callable(), "확인", "")
		return
	var lay: EquipOptionView
	if bool(r.get("worn", false)):
		lay = EquipOptionView.open(self, int(r.get("uid", 0)), String(r.get("slot", "")),
			_coin_key, _req_grade)
	else:
		lay = EquipOptionView.open_bag(self, String(r.get("inv", "")), _coin_key, _req_grade)
	lay.finished.connect(func(): _after_regen(lay.current_key(), r))

func _after_regen(new_key: String, prev: Dictionary) -> void:
	_reload()
	var want_worn := bool(prev.get("worn", false))
	for i in _list.size():
		var r: Dictionary = _list[i]
		if want_worn:
			if bool(r.get("worn", false)) and int(r.get("uid", 0)) == int(prev.get("uid", 0)) \
					and String(r.get("slot", "")) == String(prev.get("slot", "")):
				_sel = i
				break
		elif String(r.get("inv", "")) == new_key:
			_sel = i
			break
	_refresh_slots()
	_refresh_panel()
	if _on_done.is_valid():
		_on_done.call()
