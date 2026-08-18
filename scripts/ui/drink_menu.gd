class_name DrinkMenu
extends CanvasLayer

const NP := "ninepatch_ui"
const CM := "common_ui"
const PANEL := Vector2(560.0, 460.0)
const POPUP4_CAP := Rect2(130, 190, 40, 58)
const ROW_H := 64.0
const ROW_GAP := 6.0

var _uid := -1
var _on_used := Callable()

static func open(host: Node, uid: int, on_used := Callable()) -> DrinkMenu:
	var p := DrinkMenu.new()
	p.layer = 40
	p._uid = uid
	p._on_used = on_used
	host.add_child(p)
	return p

func _ready() -> void:
	var vis := get_viewport().get_visible_rect().size
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = vis
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			queue_free())
	add_child(dim)

	var root := Control.new()
	root.size = PANEL
	root.position = (vis - PANEL) * 0.5
	add_child(root)

	var bg := AtlasUI.nine(NP, "9patch_popup4", PANEL, POPUP4_CAP)
	if bg != null:
		root.add_child(bg)

	var title := AtlasUI.nine(NP, "9patch_pop_title_bg", Vector2(300.0, 44.0), Rect2())
	if title != null:
		title.position = Vector2((PANEL.x - 300.0) * 0.5, 2.0)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(title)
	var tl := Label.new()
	tl.text = "드링크"
	tl.size = Vector2(300.0, 44.0)
	tl.position = Vector2((PANEL.x - 300.0) * 0.5, 2.0)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.add_theme_font_size_override("font_size", 24)
	tl.add_theme_color_override("font_color", Color.WHITE)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tl)

	var xt := "res://assets/converted/common_ui/common_close_btn.tres"
	if ResourceLoader.exists(xt):
		var xb := TextureButton.new()
		xb.texture_normal = load(xt)
		xb.position = Vector2(PANEL.x - 58.0, 8.0)
		xb.pressed.connect(func(): queue_free())
		root.add_child(xb)

	var list_size := Vector2(PANEL.x - 60.0, PANEL.y - 110.0)
	var box := AtlasUI.nine(NP, "9patch_scroll_box", list_size, Rect2())
	if box != null:
		box.position = Vector2(30.0, 66.0)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(box)
	var sc := ScrollContainer.new()
	sc.position = Vector2(38.0, 74.0)
	sc.size = list_size - Vector2(16.0, 16.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(ROW_GAP))
	col.custom_minimum_size.x = sc.size.x
	sc.add_child(col)

	var rows := _owned()
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "가진 드링크가 없습니다.\n(상점 · 전투 보상에서 얻습니다)"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(sc.size.x, 120.0)
		empty.add_theme_font_size_override("font_size", 20)
		col.add_child(empty)
		return
	for row: Dictionary in rows:
		col.add_child(_row(String(row["key"]), row["def"], int(row["count"]),
			row["eff"], sc.size.x))

func _owned() -> Array:
	var out: Array = []
	var defs: Dictionary = Data.item_effects
	var keys: Array = Data.items.keys() if Data.items is Dictionary else []
	keys.sort()
	for k in keys:
		var key := String(k)
		var eff := ItemEffect.drink_of(defs, key)
		if eff.is_empty():
			continue
		var n := UserDB.item_count(key)
		if n <= 0:
			continue
		out.append({"key": key, "def": Data.items[key], "count": n, "eff": eff})
	return out

const STAT_KR := {"att": "공격력", "def": "방어력", "hp": "생명력",
	"crit": "크리티컬", "dodge": "회피", "block": "방어확률"}

func _row(key: String, idef: Dictionary, count: int, eff: Dictionary, w: float) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(w, ROW_H)
	var rb := AtlasUI.nine(NP, "9patch_text_box", Vector2(w, ROW_H), Rect2())
	if rb != null:
		rb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(rb)

	var ip := Data.item_icon_path(key)
	if ip != "" and ResourceLoader.exists(ip):
		var ic := TextureRect.new()
		ic.texture = load(ip)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size = Vector2(52.0, 52.0)
		ic.position = Vector2(8.0, 6.0)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ic)

	var nm := Label.new()
	nm.text = "%s  ×%d" % [String(idef.get("name", key)), count]
	nm.position = Vector2(70.0, 6.0)
	nm.size = Vector2(w - 190.0, 26.0)
	nm.add_theme_font_size_override("font_size", 19)
	nm.add_theme_color_override("font_color", Color(0.24, 0.2, 0.14))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nm)

	var ds := Label.new()
	ds.text = "%s +%d%%  ·  %d턴" % [
		String(STAT_KR.get(String(eff["stat"]), String(eff["stat"]))),
		int(eff["pct"]), int(eff["turns"])]
	ds.position = Vector2(70.0, 32.0)
	ds.size = Vector2(w - 190.0, 24.0)
	ds.add_theme_font_size_override("font_size", 17)
	ds.add_theme_color_override("font_color", Color(0.45, 0.33, 0.18))
	ds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ds)

	AtlasUI.frame_button(row, "먹이기", Vector2(w - 112.0, 12.0), Vector2(100.0, 40.0),
		func() -> void: _use(key, eff), 0, false, 18)
	return row

func _use(key: String, eff: Dictionary) -> void:
	if UserDB.item_count(key) <= 0 or _uid < 0:
		return
	var cur: Dictionary = UserDB.get_dragon(_uid).get("drink_buffs", {})
	UserDB.set_dragon_field(_uid, "drink_buffs", ItemEffect.apply_drink(cur, eff))
	UserDB.add_item(key, -1)
	Bgm.sfx("effect_button")
	Toast.show(get_tree().root, "%s +%d%%  (%d턴)" % [
		String(STAT_KR.get(String(eff["stat"]), String(eff["stat"]))),
		int(eff["pct"]), int(eff["turns"])])
	var cb := _on_used
	queue_free()
	if cb.is_valid():
		cb.call()
