class_name ArtifactMixView
extends Control

signal closed

const WIN_CAP := Rect2(130, 190, 40, 58)
const WIN_W := 900.0
const WIN_BOTTOM_CUT := 50.0
const DIM_ALPHA := 127.0 / 255.0

const DISC_COCOS := Vector2(52.5, -15.0)
const SLOT_COCOS := [Vector2(0.0, 199.0), Vector2(-157.5, -125.0), Vector2(159.5, -125.0)]
const DISC_ITEM_SCALE := 1.5

const LIST_BOX_AT := Vector2(513.0, 77.0)
const LIST_BOX := Vector2(365.0, 285.0)
const LIST_CAP := Rect2(65, 65, 6, 6)
const MAT_CENTERS := [Vector2(575.0, 148.0), Vector2(693.0, 148.0), Vector2(811.0, 148.0)]
const MAT_BOX := Vector2(102.0, 112.0)
const INFO_BOX_AT := Vector2(513.0, 374.0)
const INFO_BOX := Vector2(365.0, 165.0)
const INFO_CAP := Rect2(25, 25, 3, 3)
const BTN_SIZE := Vector2(180.0, 52.0)
const BTN_CAP := Rect2(20, 20, 4, 4)
const BTN_MIX_AT := Vector2(599.0, 573.0)
const BTN_CANCEL_AT := Vector2(787.0, 573.0)

const FLY_SECS := 0.5
const FLY_SCALE := 1.15
const SFX_ABSORB := "effect_element_match"
const SFX_SUCCESS := "effect_equip_success"

var _base_key: String = ""
var _mats: Array = ["", "", ""]
var _on_done: Callable = Callable()

var _win: Vector2 = Vector2.ZERO
var _body: Control
var _disc: Control
var _cost_lbl: Label
var _busy := false

static func open(parent: Node, base_key := "", on_done := Callable()) -> ArtifactMixView:
	var p := ArtifactMixView.new()
	p._base_key = base_key
	p._on_done = on_done
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
	_win = Vector2(WIN_W, vis.y - WIN_BOTTOM_CUT)
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

	if _base_key == "":
		var owned := _owned_artifacts(true)
		if owned.is_empty():
			_notice(Data.ui("#fd6f1262"))
			call_deferred("close")
			return
	_refresh()
	if _base_key == "":
		_open_picker(-1)

func _refresh() -> void:
	for c in _body.get_children():
		if c is NinePatchRect and c.get_index() == 0:
			continue
		c.queue_free()
		_body.remove_child(c)
	_build_title()
	_build_machine()
	_build_side()

func _build_title() -> void:
	var t := _bm_label(Data.ui("#8853302e"), 1.25)
	_center(t, Vector2(_win.x * 0.25 + 40.0, 45.0), 460.0)
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

func _build_machine() -> void:
	var S := Design.ASSET_SCALE
	var center := Vector2(_win.x * 0.25 + DISC_COCOS.x, _win.y * 0.5 - DISC_COCOS.y)
	_disc = Control.new()
	_disc.name = "disc"
	_disc.position = center
	_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_disc)

	for k in ["scene_mamorudiclab_circle_bg1", "scene_mamorudiclab_circle_bg2",
			"scene_mamorudiclab_main_circle_line2", "scene_mamorudiclab_main_circle"]:
		var s := AtlasUI.spr("mamorudiclab_ui", k, S)
		if s != null:
			s.name = k
			if k == "scene_mamorudiclab_main_circle_line2":
				s.modulate.a = 0.0
			_disc.add_child(s)

	if _base_key != "":
		var item := _catalog_of(_base_key)
		var bgt := Icons.equip_bg_texture(item)
		var col: Color = Icons.rarity_color(int(Equipment.item_key_meta(_base_key).get("rarity", 0)))
		if bgt != null and col.a > 0.0:
			var bs := Sprite2D.new()
			bs.texture = bgt
			bs.material = AtlasUI.pma()
			bs.scale = Vector2(S, S) * DISC_ITEM_SCALE
			bs.modulate = col
			_disc.add_child(bs)
		var it := Icons.equip_texture(item)
		if it != null:
			var sp := Sprite2D.new()
			sp.name = "target"
			sp.texture = it
			sp.material = AtlasUI.pma()
			sp.scale = Vector2(S, S) * DISC_ITEM_SCALE
			_disc.add_child(sp)

	for i in SLOT_COCOS.size():
		var off: Vector2 = SLOT_COCOS[i]
		var at := center + Vector2(off.x, -off.y)
		var psz := AtlasUI.size_pt("mamorudiclab_ui", "scene_mamorudiclab_small_pentagon")
		var root := Control.new()
		root.name = "mat%d" % i
		root.size = psz
		root.position = at - psz * 0.5
		_body.add_child(root)
		var pent := AtlasUI.spr("mamorudiclab_ui", "scene_mamorudiclab_small_pentagon", S)
		if pent != null:
			pent.position = psz * 0.5
			root.add_child(pent)
		var mk := String(_mats[i])
		if mk == "":
			var plus := AtlasUI.spr("mamorudiclab_ui", "scene_mamorudiclab_small_pentagon_plus", S)
			if plus != null:
				plus.position = psz * 0.5
				root.add_child(plus)
		else:
			var mt := Icons.equip_texture(_catalog_of(mk))
			if mt != null:
				var ms := Sprite2D.new()
				ms.texture = mt
				ms.material = AtlasUI.pma()
				ms.scale = Vector2(S, S) * 0.62
				ms.position = psz * 0.5
				root.add_child(ms)
		var idx := i
		_hit(root, psz, func(): _on_click_slot(idx))

	var coin := AtlasUI.spr("common_ui", "common_coin_big", S)
	var coin_x := _win.x * 0.25 - 15.0
	if coin != null:
		coin.position = Vector2(coin_x, _win.y - 57.5)
		_body.add_child(coin)
	_cost_lbl = _bm_label("x %d" % _cost(), 1.0)
	_cost_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cost_lbl.position = Vector2(coin_x + 25.0, _win.y - 60.0 - 20.0)
	_cost_lbl.size = Vector2(320.0, 40.0)
	_body.add_child(_cost_lbl)

func _build_side() -> void:
	var np := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", LIST_BOX, LIST_CAP)
	if np != null:
		np.position = LIST_BOX_AT
		_body.add_child(np)
	for i in MAT_CENTERS.size():
		var c: Vector2 = MAT_CENTERS[i]
		var cell := Panel.new()
		cell.size = MAT_BOX
		cell.position = c - MAT_BOX * 0.5
		var filled := String(_mats[i]) != ""
		cell.add_theme_stylebox_override("panel",
			_rounded_style(Color(0.20, 0.35, 0.13, 0.85) if filled else Color(0, 0, 0, 0.40)))
		_body.add_child(cell)
		if filled:
			var mt := Icons.equip_texture(_catalog_of(String(_mats[i])))
			if mt != null:
				var s := Sprite2D.new()
				s.texture = mt
				s.material = AtlasUI.pma()
				s.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 0.62
				s.position = MAT_BOX * 0.5
				cell.add_child(s)
		var idx := i
		_hit(cell, MAT_BOX, func(): _on_click_slot(idx))

	var tb := AtlasUI.nine("ninepatch_ui", "9patch_text_box", INFO_BOX, INFO_CAP)
	if tb != null:
		tb.position = INFO_BOX_AT
		_body.add_child(tb)
	var info := VBoxContainer.new()
	info.position = INFO_BOX_AT + Vector2(18.0, 14.0)
	info.size = INFO_BOX - Vector2(36.0, 28.0)
	info.add_theme_constant_override("separation", 8)
	_body.add_child(info)
	if _base_key == "":
		info.add_child(_desc_label(Data.ui("#987a375e"), Color8(0x81, 0x43, 0x1D)))
	else:
		var item := _catalog_of(_base_key)
		var rar := int(Equipment.item_key_meta(_base_key).get("rarity", 0))
		info.add_child(_desc_label(String(item.get("name", "")), Icons.rarity_text_color(rar)))
		info.add_child(_desc_label(String(item.get("artifact_effect", "")),
			Color8(0x81, 0x43, 0x1D)))
		var sk: Array = item.get("artifact_skills", [])
		if not sk.is_empty():
			info.add_child(_desc_label("대상 스킬 %d종" % sk.size(), Color8(0x81, 0x43, 0x1D)))

	_action_button("합성", BTN_MIX_AT, _on_click_mix)
	_action_button("취소", BTN_CANCEL_AT, close)

func _on_click_slot(i: int) -> void:
	if _busy:
		return
	if _base_key == "":
		_notice(Data.ui("#987a375e"))
		return
	if String(_mats[i]) != "":
		_mats[i] = ""
		_refresh()
		return
	_open_picker(i)

func _on_click_mix() -> void:
	if _busy:
		return
	if _base_key == "":
		_notice(Data.ui("#987a375e"))
		return
	if not Equipment.artifact_mix_upgradable(Data.equipment, _base_key):
		_notice("더 이상 합성할 수 없는 아티펙트입니다.")
		return
	for m in _mats:
		if String(m) == "":
			_notice(Data.ui("#32ecea85"))
			return
	var cost := _cost()
	if UserDB.gold() < cost:
		_notice(Data.ui("#f3aeeb0c"))
		return
	_busy = true
	_play_mix(cost)

func _play_mix(cost: int) -> void:
	Bgm.sfx(SFX_ABSORB)
	var center := _disc.position
	var tw := create_tween().set_parallel(true)
	for i in SLOT_COCOS.size():
		var node := _body.get_node_or_null("mat%d" % i) as Control
		if node == null:
			continue
		var to := center - node.size * 0.5
		tw.tween_property(node, "position", to, FLY_SECS).set_trans(Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_OUT)
		tw.tween_property(node, "scale", Vector2(FLY_SCALE, FLY_SCALE), FLY_SECS)
		tw.tween_property(node, "modulate:a", 0.0, 0.25).set_delay(FLY_SECS - 0.25)
	var arc := _disc.get_node_or_null("scene_mamorudiclab_main_circle_line2") as Node2D
	if arc != null:
		arc.modulate.a = 1.0
		create_tween().tween_property(arc, "rotation", TAU, FLY_SECS + 0.6)
	tw.chain().tween_property(_disc, "scale", Vector2(FLY_SCALE, FLY_SCALE), 0.3)
	await tw.finished

	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(flash)
	var ft := create_tween()
	ft.tween_property(flash, "color:a", 1.0, 0.25)
	ft.tween_property(flash, "color:a", 0.0, 0.35)
	await ft.finished
	flash.queue_free()

	_apply(cost)

func _apply(cost: int) -> void:
	var ok := RNG.chance(float(Equipment.artifact_mix_success_pct(Data.equipment, _base_key)) / 100.0)
	UserDB.add_currency("gold", -cost)
	for m in _mats:
		UserDB.add_item(String(m), -1)
	var new_key := ""
	if ok:
		new_key = Equipment.artifact_mix_result(Data.equipment, _base_key)
		UserDB.add_item(_base_key, -1)
		UserDB.add_item(new_key, 1)
		Bgm.sfx(SFX_SUCCESS)
	_mats = ["", "", ""]
	_busy = false
	if _on_done.is_valid():
		_on_done.call()
	_show_result(ok, new_key)

func _show_result(ok: bool, new_key: String) -> void:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var d := ColorRect.new()
	d.color = Color(0, 0, 0, 0.72)
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(d)

	var vis := get_viewport_rect().size
	var word := _bm_label("SUCCESS" if ok else "FAILED", 2.2,
		Color8(0xFF, 0xD1, 0x2A) if ok else Color8(0xC8, 0xC8, 0xC8))
	_center(word, Vector2(vis.x * 0.5, vis.y * 0.32), vis.x)
	layer.add_child(word)

	var key := new_key if ok else _base_key
	var item := _catalog_of(key)
	var t := Icons.equip_texture(item)
	if t != null:
		var s := Sprite2D.new()
		s.texture = t
		s.material = AtlasUI.pma()
		s.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 1.4
		s.position = Vector2(vis.x * 0.5, vis.y * 0.52)
		layer.add_child(s)
	var nm := _bm_label(String(item.get("name", "")), 1.05, Color8(0xE0, 0x3A, 0x2A))
	_center(nm, Vector2(vis.x * 0.5, vis.y * 0.68), vis.x)
	layer.add_child(nm)
	var ef := _bm_label(String(item.get("artifact_effect", "")), 0.85, Color.WHITE)
	_center(ef, Vector2(vis.x * 0.5, vis.y * 0.74), vis.x)
	layer.add_child(ef)

	var csz := AtlasUI.size_pt("common_ui", "common_check_btn")
	var root := Control.new()
	root.size = csz
	root.position = Vector2(vis.x * 0.5, vis.y * 0.87) - csz * 0.5
	layer.add_child(root)
	var cs := AtlasUI.spr("common_ui", "common_check_btn", Design.ASSET_SCALE)
	if cs != null:
		cs.position = csz * 0.5
		root.add_child(cs)
	_hit(root, csz, func():
		layer.queue_free()
		if ok:
			_base_key = new_key
		_refresh())

func _open_picker(slot: int) -> void:
	var layer := Control.new()
	layer.name = "picker"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var d := ColorRect.new()
	d.color = Color(0, 0, 0, 0.55)
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(d)

	var vis := get_viewport_rect().size
	var sz := Vector2(minf(WIN_W, vis.x - 20.0), vis.y - WIN_BOTTOM_CUT)
	var win := Control.new()
	win.size = sz
	win.position = ((vis - sz) * 0.5).round()
	layer.add_child(win)
	var fr := AtlasUI.nine("ninepatch_ui", "9patch_popup4", sz, WIN_CAP)
	if fr != null:
		win.add_child(fr)
	var t := _bm_label("아티펙트", 1.25)
	_center(t, Vector2(sz.x * 0.5, 45.0), 460.0)
	win.add_child(t)

	var box_sz := Vector2(sz.x - 100.0, sz.y - 190.0)
	var np := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", box_sz, LIST_CAP)
	if np != null:
		np.position = Vector2(50.0, 90.0)
		win.add_child(np)
	var sc := ScrollContainer.new()
	sc.position = Vector2(62.0, 102.0)
	sc.size = box_sz - Vector2(24.0, 24.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = maxi(1, int(sc.size.x / 106.0))
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	sc.add_child(grid)

	var owned := _owned_artifacts(slot < 0)
	if slot >= 0:
		var filtered: Array = []
		for e in owned:
			if Equipment.artifact_mix_material_ok(Data.equipment, _base_key,
					String((e as Dictionary)["key"])):
				filtered.append(e)
		owned = filtered
	if owned.is_empty():
		var msg := _bm_label(Data.ui("#fd6f1262") if slot < 0 \
			else "쓸 수 있는 재료가 없습니다.", 0.95)
		_center(msg, box_sz * 0.5 + Vector2(50.0, 90.0), box_sz.x)
		win.add_child(msg)
	for e in owned:
		grid.add_child(_picker_cell(e, layer, slot))

	var cancel := Control.new()
	cancel.size = BTN_SIZE
	cancel.position = Vector2(sz.x * 0.5 - BTN_SIZE.x * 0.5, sz.y - 80.0)
	win.add_child(cancel)
	var cnp := AtlasUI.nine("ninepatch_ui", "9patch_btn4", BTN_SIZE, BTN_CAP)
	if cnp != null:
		cancel.add_child(cnp)
	var cl := _bm_label("취소", 0.95)
	_center(cl, BTN_SIZE * 0.5, BTN_SIZE.x)
	cancel.add_child(cl)
	_hit(cancel, BTN_SIZE, func():
		layer.queue_free()
		if slot < 0 and _base_key == "":
			close())

func _picker_cell(entry: Dictionary, layer: Control, slot: int) -> Control:
	var key := String(entry["key"])
	var cell := Panel.new()
	cell.custom_minimum_size = Vector2(100.0, 112.0)
	cell.add_theme_stylebox_override("panel", _rounded_style(Color(0, 0, 0, 0.40)))
	var t := Icons.equip_texture(_catalog_of(key))
	if t != null:
		var s := Sprite2D.new()
		s.texture = t
		s.material = AtlasUI.pma()
		s.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 0.6
		s.position = Vector2(50.0, 48.0)
		cell.add_child(s)
	var n := _bm_label("×%d" % int(entry.get("count", 1)), 0.65)
	_center(n, Vector2(50.0, 96.0), 96.0)
	cell.add_child(n)
	_hit(cell, Vector2(100.0, 112.0), func():
		layer.queue_free()
		if slot < 0:
			_base_key = key
			_mats = ["", "", ""]
		else:
			_mats[slot] = key
		_refresh())
	return cell

func _owned_artifacts(upgradable_only: bool) -> Array:
	var out: Array = []
	for k in UserDB.inventory().keys():
		var key := String(k)
		if Equipment.artifact_of(key).is_empty():
			continue
		var n := UserDB.item_count(key)
		if key == _base_key:
			n -= 1
		for m in _mats:
			if String(m) == key:
				n -= 1
		if n <= 0:
			continue
		if upgradable_only and not Equipment.artifact_mix_upgradable(Data.equipment, key):
			continue
		out.append({"key": key, "count": n})
	out.sort_custom(func(a, b): return String(a["key"]) < String(b["key"]))
	return out

func _catalog_of(key: String) -> Dictionary:
	var cat := Equipment.parse_item_key(key)
	return Equipment.catalog(Data.equipment).get(cat, {})

func _cost() -> int:
	var n := 0
	for m in _mats:
		if String(m) != "":
			n += 1
	return Equipment.artifact_mix_cost(Data.equipment, _base_key, n)

func _notice(msg: String) -> void:
	MessageWindow.open(self, Data.ui("#8853302e"), msg, Callable(), "확인", "")

func close() -> void:
	closed.emit()
	queue_free()

func _action_button(text: String, center: Vector2, cb: Callable) -> void:
	var root := Control.new()
	root.size = BTN_SIZE
	root.position = center - BTN_SIZE * 0.5
	_body.add_child(root)
	var np := AtlasUI.nine("ninepatch_ui", "9patch_btn", BTN_SIZE, BTN_CAP)
	if np != null:
		root.add_child(np)
	var l := _bm_label(text, 0.95)
	_center(l, BTN_SIZE * 0.5, BTN_SIZE.x)
	root.add_child(l)
	_hit(root, BTN_SIZE, cb)

func _desc_label(txt: String, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(INFO_BOX.x - 40.0, 0)
	_bm_style(l, int(round(17.0 * Design.ASSET_SCALE * 0.8)), col, "font_common")
	return l

func _rounded_style(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
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
	l.size = Vector2(w, 48)
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
