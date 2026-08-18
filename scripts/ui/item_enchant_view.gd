class_name ItemEnchantView
extends Control

signal closed

const WIN_CAP := Rect2(130, 190, 40, 58)
const WIN := Vector2(860.0, 520.0)
const DIM_ALPHA := 127.0 / 255.0

const SHADOW_OFF := Vector2(2.5, -2.5)
const SHADOW_LARGE := Vector2(100.0, -127.5)
const SHADOW_SMALL := Vector2(182.5, -75.0)
const ADD_SLOTS := [Vector2(0.0, 199.0), Vector2(-157.5, -125.0), Vector2(159.5, -125.0)]
const PIPE_AT := [Vector2(-20.0, 80.0), Vector2(-55.0, -10.0), Vector2(-100.0, 5.0),
	Vector2(-45.0, -25.0)]
const BTN := Vector2(150.0, 48.0)

const GRID_COLS := 3
const CELL_RATIO := 130.0 / 115.0
const CELL_GAP := 5.0
const LIST_BOX := Vector2(340.0, 200.0)
const CELL_BG := Color(0, 0, 0, 0x66 / 255.0)

var _target: Dictionary = {}
var _uid := 0
var _on_done: Callable = Callable()
var _win_root: Control
var _canvas: CanvasLayer
var _rng := RandomNumberGenerator.new()

var _pool: PackedStringArray = []
var _mats: Array[int] = [-1, -1, -1]
var _sel := -1
var _new_opt := -1

static func target_worn(uid: int, slot_id: String) -> Dictionary:
	return {"kind": "worn", "uid": uid, "slot": slot_id}

static func target_bag(inv_key: String, uid := 0) -> Dictionary:
	if inv_key == "" or Equipment.parse_item_key(inv_key) == "":
		return {}
	return {"kind": "bag", "uid": uid, "key": inv_key}

static func slot_view(target: Dictionary) -> Dictionary:
	if String(target.get("kind", "")) == "worn":
		var uid := int(target.get("uid", 0))
		var sid := String(target.get("slot", ""))
		for s in (UserDB.get_dragon(uid).get("equip", {}).get("slots", []) as Array):
			if String((s as Dictionary).get("slot", "")) == sid:
				return s
		return {}
	var key := String(target.get("key", ""))
	var ck := Equipment.parse_item_key(key)
	if ck == "":
		return {}
	var m := Equipment.item_key_meta(key)
	return {"slot": "", "key": ck, "grade": int(m.get("rarity", 0)),
		"enhance": int(m.get("enhance", 0)), "options": m.get("options", []),
		"belong": int(m.get("belong", 0))}

const CANVAS_LAYER := 68

static func open(parent: Node, target: Dictionary, on_done := Callable()) -> ItemEnchantView:
	var p := ItemEnchantView.new()
	p._target = target
	p._uid = int(target.get("uid", 0))
	p._on_done = on_done
	p._canvas = CanvasLayer.new()
	p._canvas.layer = CANVAS_LAYER
	parent.add_child(p._canvas)
	p._canvas.add_child(p)
	p._build()
	return p

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.randomize()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	create_tween().tween_property(dim, "color:a", DIM_ALPHA, 0.2)
	_reload_pool()
	_rebuild()

func _reload_pool() -> void:
	var free_first: PackedStringArray = []
	var bound: PackedStringArray = []
	var inv: Dictionary = UserDB.inventory()
	var keys: Array = inv.keys()
	keys.sort()
	var skip_key := String(_target.get("key", "")) if String(_target.get("kind", "")) == "bag" else ""
	for k in keys:
		var key := String(k)
		if Equipment.parse_item_key(key) == "":
			continue
		if not Equipment.catalog(Data.equipment).has(Equipment.parse_item_key(key)):
			continue
		var n_avail := int(inv[key])
		if key == skip_key:
			n_avail -= 1
		for _n in maxi(0, n_avail):
			if Equipment.item_key_belong(key) > 0:
				bound.append(key)
			else:
				free_first.append(key)
	_pool = free_first + bound
	_mats = [-1, -1, -1]
	_sel = -1

func _rebuild() -> void:
	if is_instance_valid(_win_root):
		_win_root.queue_free()
	var vis := get_viewport_rect().size
	_win_root = Control.new()
	_win_root.size = WIN
	_win_root.position = ((vis - WIN) * 0.5).round()
	add_child(_win_root)
	var fr := AtlasUI.nine("ninepatch_ui", "9patch_popup4", WIN, WIN_CAP)
	if fr:
		_win_root.add_child(fr)

	var t := _label("아이템 강화", 26, Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.position = Vector2(0, 26.0)
	t.size = Vector2(WIN.x, 40.0)
	_win_root.add_child(t)

	var cb := TextureButton.new()
	var ct := AtlasUI.tex("common_ui", "common_close_btn")
	if ct:
		cb.texture_normal = ct
		cb.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 1.3
	cb.position = Vector2(WIN.x - 74.0, 24.0)
	cb.pressed.connect(close)
	_win_root.add_child(cb)

	_build_machine()
	_build_side()

func _build_machine() -> void:
	var S := Design.ASSET_SCALE
	var c := Vector2(WIN.x * 0.30, WIN.y * 0.5 + 8.0)
	var root := Node2D.new()
	root.name = "machine"
	root.position = c
	_win_root.add_child(root)

	for spec in [["scene_cave_gear_shadow_large", SHADOW_LARGE], ["scene_cave_gear_shadow_small", SHADOW_SMALL]]:
		var s := AtlasUI.spr("cave_ui", String(spec[0]), S * 0.62)
		if s:
			var o: Vector2 = spec[1]
			s.position = Vector2(o.x, -o.y) * 0.62
			root.add_child(s)
	var gsh := AtlasUI.spr("cave_ui", "scene_cave_gear_shadow", S * 0.62)
	if gsh:
		gsh.position = Vector2(SHADOW_OFF.x, -SHADOW_OFF.y)
		root.add_child(gsh)
	var gear := AtlasUI.spr("cave_ui", "scene_cave_gear", S * 0.62)
	if gear:
		root.add_child(gear)
		gear.create_tween().set_loops().tween_property(gear, "rotation", TAU, 12.0).as_relative()
	var inside := AtlasUI.spr("cave_ui", "scene_cave_gear_inside", S * 0.62)
	if inside:
		root.add_child(inside)
	var line := AtlasUI.spr("cave_ui", "scene_cave_enchant_line", S * 0.62)
	if line:
		root.add_child(line)
		line.create_tween().set_loops().tween_property(line, "rotation", -TAU, 20.0).as_relative()

	var art := _item_sprite(1.1)
	if art:
		art.name = "target"
		root.add_child(art)

	for i in ADD_SLOTS.size():
		var off: Vector2 = ADD_SLOTS[i]
		var at := Vector2(off.x, -off.y) * 0.62
		var box := AtlasUI.spr("cave_ui", "scene_cave_itembox_add", S * 0.62)
		if box:
			box.position = at
			root.add_child(box)
		var mi := _mats[i]
		if mi < 0:
			var sign := AtlasUI.spr("cave_ui", "scene_cave_itembox_add_sign", S * 0.62)
			if sign:
				sign.position = at
				root.add_child(sign)
		else:
			var cell := _cell_visual(String(_pool[mi]), 52.0)
			cell.position = c + at - Vector2(26.0, 26.0)
			_win_root.add_child(cell)
		var hit := Button.new()
		hit.flat = true
		hit.size = Vector2(56.0, 56.0)
		hit.position = c + at - hit.size * 0.5
		hit.pressed.connect(_on_slot_click.bind(i))
		_win_root.add_child(hit)

	var pipes: Array[Sprite2D] = [
		AtlasUI.spr("cave_ui", "scene_cave_pipe1", S * 0.62),
		AtlasUI.spr("cave_ui", "scene_cave_pipe2", S * 0.62),
		AtlasUI.spr("cave_ui", "scene_cave_pipe3", S * 0.62),
		AtlasUI.spr("cave_ui", "scene_cave_pipe4", S * 0.62)]
	for pi in pipes.size():
		var p: Sprite2D = pipes[pi]
		if p == null:
			continue
		var o: Vector2 = PIPE_AT[pi]
		p.position = c + Vector2(o.x, -o.y) * 0.62 + Vector2(-WIN.x * 0.18, 0)
		_win_root.add_child(p)

	var cost := _cost()
	var coin := AtlasUI.spr("common_ui", "common_coin_big", S * 0.8)
	if coin:
		coin.position = Vector2(WIN.x / 3.0 + 15.0, WIN.y - 57.5)
		_win_root.add_child(coin)
	var short := UserDB.gold() < cost
	var cl := _label("x %s" % AtlasUI.comma(cost), 20,
		Color(1, 0.45, 0.38) if short else Color(1, 0.95, 0.72))
	cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cl.position = Vector2(WIN.x / 3.0 + 45.0, WIN.y - 78.0)
	cl.size = Vector2(240.0, 40.0)
	_win_root.add_child(cl)

	var pl := _label("성공 확률 %d%%" % _success_pct(), 19, Color(0.55, 1.0, 0.62))
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pl.position = Vector2(40.0, WIN.y - 78.0)
	pl.size = Vector2(220.0, 40.0)
	_win_root.add_child(pl)

func _build_side() -> void:
	var bx := WIN.x * 0.56
	var bw := WIN.x - bx - 44.0
	var box := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", Vector2(bw, LIST_BOX.y),
		Rect2(65, 65, 6, 6))
	if box:
		box.position = Vector2(bx, 84.0)
		_win_root.add_child(box)
	_build_grid(Vector2(bx, 84.0), Vector2(bw, LIST_BOX.y))

	var tb := AtlasUI.nine("ninepatch_ui", "9patch_text_box", Vector2(bw, 165.0),
		Rect2(25, 25, 3, 3))
	if tb:
		tb.position = Vector2(bx, 292.0)
		_win_root.add_child(tb)
	var clip := Control.new()
	clip.position = Vector2(bx + 16.0, 302.0)
	clip.size = Vector2(bw - 32.0, 145.0)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_win_root.add_child(clip)
	var col := VBoxContainer.new()
	col.size = clip.size
	col.add_theme_constant_override("separation", 3)
	clip.add_child(col)
	var desc_key := String(_pool[_sel]) if _sel >= 0 and _sel < _pool.size() else ""
	if desc_key == "":
		var sd := _slot_data()
		col.add_child(_label(_item_name(), 19, Color(0.72, 0.20, 0.10)))
		col.add_child(_label("강화 %d / %d" % [int(sd.get("enhance", 0)), _limit()], 16,
			Color(0.30, 0.17, 0.04)))
		var oi := 0
		for o in (sd.get("options", []) as Array):
			var ol := _opt_label(o as Dictionary)
			col.add_child(ol)
			if oi == _new_opt:
				var nb := AtlasUI.spr("cave_ui", "scene_cave_txt_new", Design.ASSET_SCALE * 0.7)
				if nb:
					nb.position = Vector2(bw - 60.0, 10.0)
					ol.add_child(nb)
			oi += 1
	else:
		var m := Equipment.item_key_meta(desc_key)
		var it: Dictionary = Equipment.catalog(Data.equipment).get(
			Equipment.parse_item_key(desc_key), {})
		col.add_child(_label(_key_name(desc_key), 19,
			Icons.rarity_text_color(int(m.get("rarity", 0)))))
		col.add_child(_label("무게 %d  ·  확률 가산 +%d%%" % [
			Equipment.enchant_weight_of_key(desc_key, Data.equipment),
			_bonus_of(desc_key)], 16, Color(0.30, 0.17, 0.04)))
		for o in (m.get("options", []) as Array):
			col.add_child(_opt_label(o as Dictionary))
		if String(it.get("bonus", "")) != "":
			var bl := _label(String(it["bonus"]), 13, Color(0.36, 0.28, 0.14))
			bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			bl.custom_minimum_size = Vector2(bw - 32.0, 0)
			col.add_child(bl)

	var pick_txt := "선택"
	if _sel >= 0 and _mats.has(_sel):
		pick_txt = "취소"
	_button("강화", Vector2(bx + bw * 0.5 - BTN.x - 8.0, WIN.y - 76.0), _on_enchant)
	_button(pick_txt, Vector2(bx + bw * 0.5 + 8.0, WIN.y - 76.0), _on_pick)

func _build_grid(at: Vector2, box: Vector2) -> void:
	var inner := box.x - 10.0
	var cw := inner / float(GRID_COLS) - CELL_GAP
	var ch := cw * CELL_RATIO
	var sc := ScrollContainer.new()
	sc.position = at + Vector2(5.0, 7.5)
	sc.size = Vector2(inner, box.y - 15.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_win_root.add_child(sc)
	var page := Control.new()
	var rows := int(ceil(float(_pool.size()) / float(GRID_COLS)))
	page.custom_minimum_size = Vector2(inner, (ch + CELL_GAP) * float(rows) + 2.5)
	sc.add_child(page)

	if _pool.is_empty():
		var none := _label("재료로 쓸 장비가 없습니다", 15, Color(0.45, 0.33, 0.20))
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.position = Vector2(0, 16.0)
		none.size = Vector2(inner, 30.0)
		page.add_child(none)
		return

	for i in _pool.size():
		var cell := Control.new()
		cell.size = Vector2(cw, ch)
		cell.position = Vector2(inner * float(i % GRID_COLS) / float(GRID_COLS) + CELL_GAP * 0.5,
			(ch + CELL_GAP) * float(i / GRID_COLS))
		page.add_child(cell)
		var bg := ColorRect.new()
		bg.color = CELL_BG
		bg.size = cell.size
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(bg)
		var vis := _cell_visual(String(_pool[i]), cw * 0.7)
		vis.position = (cell.size - vis.size) * 0.5
		cell.add_child(vis)
		if _mats.has(i):
			var used := ColorRect.new()
			used.color = CELL_BG
			used.size = cell.size
			used.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(used)
		if i == _sel:
			var mark := ReferenceRect.new()
			mark.border_color = Color(1.0, 0.86, 0.35)
			mark.border_width = 3.0
			mark.editor_only = false
			mark.size = cell.size
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(mark)
		var b := Button.new()
		b.flat = true
		b.size = cell.size
		b.pressed.connect(_on_cell_click.bind(i))
		cell.add_child(b)

func _cell_visual(key: String, box: float) -> Control:
	var m := Equipment.item_key_meta(key)
	var item: Dictionary = Equipment.catalog(Data.equipment).get(
		Equipment.parse_item_key(key), {})
	var holder: Control = Icons.equip_rect(item, box, int(m.get("rarity", 0)),
		int(m.get("belong", 0)), _uid)
	if holder == null:
		holder = Control.new()
		holder.custom_minimum_size = Vector2(box, box)
		holder.size = Vector2(box, box)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var up := int(m.get("enhance", 0))
	if up > 0:
		var l := _label("+%d" % up, 14, Color(1, 0.95, 0.72))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		l.size = Vector2(box, box)
		l.position = Vector2(-2.0, 0.0)
		holder.add_child(l)
	return holder

func _on_cell_click(i: int) -> void:
	Bgm.sfx("effect_element_match")
	_sel = i
	_rebuild()

func _on_pick() -> void:
	if _sel < 0:
		_notice("재료로 쓸 장비를 먼저 고르세요")
		return
	var at := _mats.find(_sel)
	if at >= 0:
		_mats[at] = -1
		_rebuild()
		return
	var free := _mats.find(-1)
	if free < 0:
		_notice("재료는 3개까지 넣을 수 있습니다")
		return
	_mats[free] = _sel
	Bgm.sfx("effect_element_match")
	_rebuild()

func _on_slot_click(i: int) -> void:
	if _mats[i] < 0:
		_notice("오른쪽 목록에서 재료로 쓸 장비를 고른 뒤 `선택`을 누르세요")
		return
	_mats[i] = -1
	_rebuild()

func _on_enchant() -> void:
	var sd := _slot_data()
	var why := Equipment.enchant_blocked(sd, Data.equipment)
	if why != "":
		_notice({
			"no_equip": Data.ui("#5769c4a4"),
			"min_grade": Data.ui("#e98ebbdf"),
			"grade_max": ItemWindow.S_ENHANCE_MAX,
			"option_max": Data.ui("#5bbe7dfd"),
		}.get(why, why))
		return
	if bool(Equipment.enchant_cfg(Data.equipment).get("require_material", true)) \
			and _filled().is_empty():
		_notice("보조 재료를 1개 이상 넣어야 합니다")
		return
	var cost := _cost()
	if not UserDB.spend("gold", cost):
		_notice("골드가 부족합니다")
		return

	for k in _filled():
		UserDB.add_item(k, -1)

	Bgm.sfx("effect_enchant")
	var was := _item_name()
	var before := (sd.get("options", []) as Array).size()
	var after := before
	var ok := _rng.randi() % 100 < _success_pct()
	if ok and _apply_success():
		after = (_slot_data().get("options", []) as Array).size()
	Bgm.sfx("effect_equip_success" if ok else "effect_equip_failed")
	_new_opt = (after - 1) if (ok and after > before) else -1
	if _on_done.is_valid():
		_on_done.call()
	_reload_pool()
	_rebuild()
	if not ok:
		_notice(Data.ui("#b1cdc514"))
	elif after > before:
		_notice(Data.ui("#04c9baea") + "
%s -> %s
새로운 옵션 %s" % [
			was, _item_name(), _opt_text(_slot_data(), after - 1)])
	else:
		_notice(Data.ui("#04c9baea") + "
%s -> %s" % [was, _item_name()])

func _apply_success() -> bool:
	if String(_target.get("kind", "")) == "worn":
		var uid := int(_target.get("uid", 0))
		var sid := String(_target.get("slot", ""))
		var next: Dictionary = Equipment.enhance(
			UserDB.get_dragon(uid).get("equip", {}), sid, _rng, Data.equipment)
		if next.is_empty():
			return false
		UserDB.set_dragon_field(uid, "equip", next)
		return true

	var old_key := String(_target.get("key", ""))
	var view := slot_view(_target)
	if view.is_empty() or UserDB.item_count(old_key) <= 0:
		return false
	view["slot"] = "_bag"
	var res: Dictionary = Equipment.enhance({"slots": [view]}, "_bag", _rng, Data.equipment)
	if res.is_empty():
		return false
	var new_key := Equipment.slot_to_item_key((res["slots"] as Array)[0] as Dictionary)
	UserDB.add_item(old_key, -1)
	UserDB.add_item(new_key, 1)
	_target["key"] = new_key
	return true

func _filled() -> PackedStringArray:
	var out: PackedStringArray = []
	for i in _mats:
		if i >= 0 and i < _pool.size():
			out.append(String(_pool[i]))
	return out

func _slot_data() -> Dictionary:
	return slot_view(_target)

func current_key() -> String:
	return String(_target.get("key", ""))

func _weight() -> int:
	return Equipment.enchant_weight_of_slot(_slot_data(), Data.equipment)

func _limit() -> int:
	return Equipment.enhance_cap_of_slot(_slot_data(), Data.equipment)

func _cost() -> int:
	return Equipment.enchant_gold(_weight(), Data.equipment)

func _success_pct() -> int:
	var ws: Array = []
	for k in _filled():
		ws.append(Equipment.enchant_weight_of_key(k, Data.equipment))
	return Equipment.enchant_pct(_weight(), ws, Data.equipment)

func _bonus_of(key: String) -> int:
	var w := _weight()
	if w <= 0:
		return 0
	return int(Equipment.enchant_weight_of_key(key, Data.equipment) * 100
		/ (w * int(Equipment.enchant_cfg(Data.equipment).get("material_denom", 5))))

func _item_name() -> String:
	var sd := _slot_data()
	var item: Dictionary = Equipment.catalog(Data.equipment).get(String(sd.get("key", "")), {})
	var nm := String(item.get("name", "장비"))
	var e := int(sd.get("enhance", 0))
	return "%s +%d" % [nm, e] if e > 0 else nm

func _key_name(key: String) -> String:
	var item: Dictionary = Equipment.catalog(Data.equipment).get(
		Equipment.parse_item_key(key), {})
	var nm := String(item.get("name", "장비"))
	var e := int(Equipment.item_key_meta(key).get("enhance", 0))
	return "%s +%d" % [nm, e] if e > 0 else nm

func _opt_text(sd: Dictionary, i: int) -> String:
	var opts: Array = sd.get("options", [])
	if i < 0 or i >= opts.size():
		return ""
	return EquipOptionView.opt_text(opts[i] as Dictionary, Data.equipment)

func _opt_label(od: Dictionary) -> Label:
	return _label(EquipOptionView.opt_text(od, Data.equipment), 16, Color(0.30, 0.17, 0.04))

func _item_sprite(mult: float) -> Sprite2D:
	var sd := _slot_data()
	var item: Dictionary = Equipment.catalog(Data.equipment).get(String(sd.get("key", "")), {})
	var t := Icons.equip_texture(item)
	if t == null:
		return null
	var s := Sprite2D.new()
	s.texture = t
	s.material = AtlasUI.pma()
	s.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * mult
	return s

func close() -> void:
	closed.emit()
	if is_instance_valid(_canvas):
		_canvas.queue_free()
	else:
		queue_free()

func _button(text: String, at: Vector2, cb: Callable) -> void:
	var root := Control.new()
	root.size = BTN
	root.position = at
	_win_root.add_child(root)
	var np := AtlasUI.nine("ninepatch_ui", "9patch_btn", BTN, Rect2(20, 20, 4, 4))
	if np:
		root.add_child(np)
	var l := _label(text, 20, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = BTN
	root.add_child(l)
	var b := Button.new()
	b.flat = true
	b.size = BTN
	b.pressed.connect(cb)
	root.add_child(b)

func _label(txt: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if col == Color.WHITE or col.v > 0.8:
		l.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.04, 0.9))
		l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _notice(msg: String) -> void:
	MessageWindow.open(self, "아이템 강화", msg, Callable(), "확인", "")
