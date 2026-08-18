extends Control

const NPC_COL := 290.0
const PANEL_MARGIN := 30.0
const PANEL_TOP_GAP := 108.0
const PANEL_BOTTOM := 135.0
const CELL := Vector2(165.0, 196.0)

var _pma: CanvasItemMaterial
var _params: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _pending_line := ""
var _grid_host: Control

func enter(params: Dictionary = {}) -> void:
	_params = params
	if _pma != null:
		_rebuild()

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_rng.randomize()
	Bgm.play("bg_shop")
	_rebuild()

func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_npc = null
	_box = null
	var vis := _vis()

	var pw := vis.x - PANEL_MARGIN * 2.0 - NPC_COL
	var ph := vis.y - PANEL_TOP_GAP - PANEL_BOTTOM
	var panel := _nine9("scene_shop_shop_box_imp", Vector2(pw, ph), Rect2(40, 40, 4, 4), "shop_ui")
	if panel:
		panel.position = Vector2(PANEL_MARGIN, PANEL_TOP_GAP - 60.0)
		add_child(panel)
		var inner := ColorRect.new()
		inner.color = Color8(240, 241, 232)
		inner.size = Vector2(pw - 44.0, ph - 63.0)
		inner.position = panel.position + Vector2(22.0, 40.0)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(inner)

	_build_grid(vis, Rect2(PANEL_MARGIN + 22.0, PANEL_TOP_GAP - 20.0, pw - 44.0, ph - 63.0))
	_build_treasure_box(vis)
	_build_npc(vis)
	_build_back(vis)

func _build_treasure_box(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var cx := vis.x - NPC_COL * 0.5
	var cy := PANEL_TOP_GAP + 20.0
	var box := _spr("shop_ui", "scene_shop_bg_pong", S)
	if box:
		box.position = Vector2(cx, cy)
		add_child(box)
	var info := _spr("common_ui", "common_btn_info", S * 0.8)
	if info:
		info.position = Vector2(cx + 110.0, cy - 76.0)
		add_child(info)
	var curs := ImpShop.currencies(Data.imp_shop)
	for i in curs.size():
		var key := String(curs[i])
		var ox := cx - 78.0 + 96.0 * float(i % 2)
		var oy := cy - 36.0 + 62.0 * float(i / 2)
		var ic := _item_icon(key, 0.5)
		if ic:
			ic.position = Vector2(ox, oy)
			add_child(ic)
		var l := Label.new()
		l.text = "x%d" % UserDB.item_count(key)
		l.add_theme_font_size_override("font_size", 17)
		l.add_theme_color_override("font_color", Color.WHITE)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 4)
		l.position = Vector2(ox + 16.0, oy - 12.0)
		l.size = Vector2(70.0, 24.0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)

var _npc: NpcPortrait
var _box: BottomTextBox
func _build_npc(vis: Vector2) -> void:
	_npc = NpcPortrait.create("pong", _rng.randi_range(1, 4))
	if _npc != null:
		_npc.z_index = 5
		add_child(_npc)
		var bw := _npc.body_width()
		_npc.position = Vector2(vis.x - NPC_COL * 0.5, vis.y)
		var to_x := _npc.position.x
		_npc.position.x = vis.x + bw * 0.5
		var tw := create_tween()
		tw.tween_property(_npc, "position:x", to_x, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_box = BottomTextBox.new()
	_box.max_width = vis.x - NPC_COL
	_box.z_index = 12
	add_child(_box)
	if _pending_line != "":
		_say(_pending_line)
		_pending_line = ""
	else:
		_say(_welcome_line())

func _say(text: String) -> void:
	if is_instance_valid(_box) and text != "":
		_box.show_text(_npc_name(), text)

func _build_grid(_vis: Vector2, area: Rect2) -> void:
	var S := Design.ASSET_SCALE
	var rows := ImpShop.stock(Data.imp_shop)
	var cols := maxi(1, int(area.size.x / CELL.x))
	var scroll := ScrollContainer.new()
	scroll.position = area.position
	scroll.size = area.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(area.size.x,
		CELL.y * ceilf(float(rows.size()) / float(cols)) + 16.0)
	scroll.add_child(inner)
	_grid_host = inner
	var gx := (area.size.x - CELL.x * float(cols)) * 0.5
	var gy := 8.0
	for i in rows.size():
		var row: Dictionary = rows[i]
		var cx := gx + CELL.x * float(i % cols) + CELL.x * 0.5
		var cy := gy + CELL.y * float(i / cols) + CELL.y * 0.5
		var owned := {String(row["currency"]): UserDB.item_count(String(row["currency"]))}
		var afford := ImpShop.can_buy(row, owned)
		var glow := _spr("common_ui", "common_backlight3", S * 0.42)
		if glow and afford:
			glow.position = Vector2(cx, cy - 14.0)
			glow.modulate = Color(1, 0.95, 0.7, 0.30)
			_grid_host.add_child(glow)
		var cell := _spr("common_ui", "common_item_bg", S)
		if cell:
			cell.position = Vector2(cx, cy - 14.0)
			_grid_host.add_child(cell)
		var ic := _icon_spr(Icons.equip_texture(
			Equipment.catalog(Data.equipment).get(String(row["key"]), {})), 1.0)
		if ic:
			ic.position = Vector2(cx, cy - 14.0)
			_grid_host.add_child(ic)
		var nm := Label.new()
		nm.text = String(row["name"])
		nm.add_theme_font_size_override("font_size", 14)
		nm.add_theme_color_override("font_color", Color.WHITE)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.size = Vector2(CELL.x, 20.0)
		nm.position = Vector2(cx - CELL.x * 0.5, cy + 34.0)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid_host.add_child(nm)
		var pic := _item_icon(String(row["currency"]), 0.4)
		if pic:
			pic.position = Vector2(cx - 24.0, cy + 68.0)
			_grid_host.add_child(pic)
		var pl := Label.new()
		pl.text = str(int(row["price"]))
		pl.add_theme_font_size_override("font_size", 17)
		pl.add_theme_color_override("font_color", Color(1, 0.9, 0.5) if afford else Color(1, 0.45, 0.4))
		pl.size = Vector2(70.0, 22.0)
		pl.position = Vector2(cx - 8.0, cy + 57.0)
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid_host.add_child(pl)
		var hit := Button.new()
		hit.flat = true
		hit.size = Vector2(CELL.x - 10.0, CELL.y - 10.0)
		hit.position = Vector2(cx - CELL.x * 0.5 + 5.0, cy - CELL.y * 0.5 + 5.0)
		hit.pressed.connect(_confirm_buy.bind(row))
		_grid_host.add_child(hit)

func _confirm_buy(row: Dictionary) -> void:
	var cur := String(row["currency"])
	var owned := {cur: UserDB.item_count(cur)}
	var lack := ImpShop.shortfall(row, owned)
	if lack > 0:
		Toast.show(self, "%s이(가) %d개 부족합니다" % [Data.item_name(cur), lack])
		return
	MessageWindow.open(self, "구매",
		"%s\n\n%s %d개로 교환하시겠습니까?" % [String(row["name"]), Data.item_name(cur), int(row["price"])],
		func(): _do_buy(row))

func _do_buy(row: Dictionary) -> void:
	var cur := String(row["currency"])
	var res := ImpShop.buy(row, {cur: UserDB.item_count(cur)}, _rng, Data.equipment)
	if not bool(res.get("ok", false)):
		Toast.show(self, String(res.get("reason", "구매할 수 없습니다")))
		return
	if not UserDB.use_item(String(res["spend_key"]), int(res["spend_count"])):
		Toast.show(self, "보석이 부족합니다")
		return
	UserDB.add_item(String(res["give_key"]), 1)
	var rar := int(res.get("rarity", 0))
	if rar > 0:
		Toast.show(self, "%s %s 획득!" % [_rarity_name(rar), String(row["name"])])
	Bgm.sfx("effect_item_buy")
	_pending_line = _buy_line(String(row["name"]))
	_rebuild()

func _build_back(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var b := TextureButton.new()
	var t := _tex("common_ui", "common_back_btn")
	var bx := PANEL_MARGIN + 6.0
	var by := PANEL_TOP_GAP - 60.0 + 6.0
	if t:
		b.texture_normal = t
		b.scale = Vector2(S, S)
		b.position = Vector2(bx, by)
	else:
		b.position = Vector2(bx, by)
	b.pressed.connect(func():
		Bgm.sfx("effect_button")
		var cb = _params.get("on_close")
		if cb is Callable and (cb as Callable).is_valid():
			(cb as Callable).call()
			return
		Scenes.goto("worldmap", {"region": _params.get("region", "yutakan"),
			"night": bool(_params.get("night", true))}))
	add_child(b)

func _imp_block() -> Dictionary:
	return Data.npc_lines_doc.get("imp_shop", {})

func _welcome_line() -> String:
	var pool: Array = _imp_block().get("welcome", [])
	if pool.is_empty():
		return ""
	return String(pool[_rng.randi_range(0, mini(3, pool.size() - 1))])

func _buy_line(item_name: String) -> String:
	var pool: Array = _imp_block().get("buy", [])
	if pool.is_empty():
		return ""
	return String(pool[_rng.randi() % pool.size()]).replace("%1$s", item_name)

func _npc_name() -> String:
	return String(_imp_block().get("name", "임프 퐁"))

func _rarity_name(rarity: int) -> String:
	var gs: Array = Data.equipment.get("option", {}).get("grades", [])
	if rarity < 0 or rarity >= gs.size():
		return ""
	return String((gs[rarity] as Dictionary).get("name", ""))

func _item_icon(key: String, scale := 1.0) -> Sprite2D:
	var path := String(Data.item_icon_path(key))
	if path == "" or not ResourceLoader.exists(path):
		return null
	return _icon_spr(load(path), scale)

func _icon_spr(t: Texture2D, scale := 1.0) -> Sprite2D:
	if t == null:
		return null
	var s := Sprite2D.new()
	s.texture = t
	s.material = _pma
	s.scale = Vector2(scale, scale) * Design.ASSET_SCALE
	return s

func _vis() -> Vector2:
	return get_viewport_rect().size

func _man(dir: String) -> Dictionary:
	return AtlasUI.manifest(dir)

func _tex(dir: String, key: String) -> Texture2D:
	return AtlasUI.tex(dir, key)

func _spr(dir: String, key: String, scale := 1.0) -> Sprite2D:
	return AtlasUI.spr(dir, key, scale)

func _nine(key: String, sz_pt: Vector2, cap: Rect2) -> NinePatchRect:
	return _nine9(key, sz_pt, cap, "ninepatch_ui")

func _nine9(key: String, sz_pt: Vector2, cap: Rect2, dir: String) -> NinePatchRect:
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	if not ResourceLoader.exists(p):
		return null
	var tex: Texture2D = load(p)
	var inv := 1.0 / Design.ASSET_SCALE
	var l := tex.get_width() / 3.0
	var t := tex.get_height() / 3.0
	var cw := tex.get_width() / 3.0
	var ch := tex.get_height() / 3.0
	if cap.size != Vector2.ZERO:
		l = cap.position.x * inv; t = cap.position.y * inv
		cw = cap.size.x * inv; ch = cap.size.y * inv
	var np := NinePatchRect.new()
	np.texture = tex
	np.patch_margin_left = int(round(l))
	np.patch_margin_top = int(round(t))
	np.patch_margin_right = int(round(maxf(0.0, tex.get_width() - l - cw)))
	np.patch_margin_bottom = int(round(maxf(0.0, tex.get_height() - t - ch)))
	np.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	np.size = sz_pt * inv
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	np.material = _pma
	return np
