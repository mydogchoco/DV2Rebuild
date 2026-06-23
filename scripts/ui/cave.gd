extends Control
## Cave (메인 로비). 참고: docs/OldRef_image/Cave.png
## 기능: 드래곤 육성·관리, 인벤토리 확인/사용, 도감 열람, 배경 스킨 변경.

const UI := "res://assets/converted/cave_ui/%s.tres"
const BG := "res://assets/converted/cave_bg/cavebg%d.jpg"
const DRAGON_SCENE := "res://scenes/dragons/dragon_%d_%s.tscn"
const SEED_OWNED := [{"id": 1, "level": 5}, {"id": 5, "level": 12}, {"id": 10, "level": 25}]
const SKIN_COUNT := 15

var _pma: CanvasItemMaterial
var _manifest: Dictionary = {}
var _bg: TextureRect
var _stage: Node2D
var _list_box: VBoxContainer
var _stat_label: RichTextLabel
var _overlay: Control

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	var mf := FileAccess.open("res://assets/converted/cave_ui/_manifest.json", FileAccess.READ)
	if mf: _manifest = JSON.parse_string(mf.get_as_text())

	if SaveSystem.state["owned_dragons"].is_empty():
		for o in SEED_OWNED:
			SaveSystem.add_dragon(o["id"], o["level"])
		SaveSystem.state["currency"] = {"gold": 125000, "diamond": 980}
		SaveSystem.state["inventory"] = {"에너지 드링크": 3, "레벨업 물약": 12, "각성의 마석": 2, "문장": 47}
		SaveSystem.save_game()

	_build_background()
	_build_stage()
	_build_dragon_list()
	_build_stat_panel()
	_build_bottom_slots()
	_build_menu()
	_build_topbar()
	_refresh()

# ---------- helpers ----------
func _ui_tex(name: String) -> AtlasTexture:
	var p := UI % name
	return load(p) if ResourceLoader.exists(p) else null

func _ui_sprite(name: String, scale := 1.0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _ui_tex(name)
	s.material = _pma
	var info = _manifest.get(name, {})
	if info.get("rotated", false):
		s.rotation = PI / 2.0
	s.scale = Vector2(scale, scale)
	return s

func _panel(col := Color(0, 0, 0, 0.55)) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.25)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _active() -> Dictionary:
	var owned: Array = SaveSystem.state["owned_dragons"]
	if owned.is_empty(): return {}
	var i: int = clampi(int(SaveSystem.state.get("active_dragon", 0)), 0, owned.size() - 1)
	return owned[i]

# ---------- build ----------
func _build_background() -> void:
	_bg = TextureRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_bg)

func _build_stage() -> void:
	_stage = Node2D.new()
	_stage.position = Vector2(980, 600)
	add_child(_stage)

func _build_dragon_list() -> void:
	var sc := ScrollContainer.new()
	sc.position = Vector2(24, 120)
	sc.custom_minimum_size = Vector2(150, 600)
	sc.size = Vector2(150, 600)
	add_child(sc)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 10)
	sc.add_child(_list_box)

func _build_stat_panel() -> void:
	var p := _panel()
	p.position = Vector2(24, 770)
	p.size = Vector2(440, 286)
	add_child(p)
	_stat_label = RichTextLabel.new()
	_stat_label.bbcode_enabled = true
	_stat_label.position = Vector2(20, 16)
	_stat_label.size = Vector2(400, 220)
	_stat_label.add_theme_font_size_override("normal_font_size", 26)
	p.add_child(_stat_label)
	var lv := Button.new()
	lv.text = "레벨 업 (+1)"
	lv.position = Vector2(20, 234)
	lv.size = Vector2(180, 40)
	lv.pressed.connect(_on_levelup)
	p.add_child(lv)

func _build_bottom_slots() -> void:
	var labels := ["아이템", "젬", "스킬"]
	var x := 560
	for cat in labels:
		var l := Label.new()
		l.text = cat
		l.position = Vector2(x, 952)
		l.add_theme_font_size_override("font_size", 24)
		add_child(l)
		for i in 3:
			var slot := _panel(Color(0.2, 0.3, 0.5, 0.7))
			slot.position = Vector2(x + 110 + i * 66, 948)
			slot.size = Vector2(58, 58)
			add_child(slot)
		x += 340

func _build_menu() -> void:
	var items := [["book", "도감", _open_dex], ["bag", "인벤토리", _open_inventory],
				  ["card", "카드", _open_cards]]
	var y := 120
	for it in items:
		_menu_button(it[0], it[1], y, it[2])
		y += 130
	# 배경 스킨 변경
	var skin := Button.new()
	skin.text = "스킨 변경"
	skin.position = Vector2(1740, y)
	skin.size = Vector2(150, 56)
	skin.pressed.connect(_cycle_skin)
	add_child(skin)

func _menu_button(icon: String, label: String, y: int, cb: Callable) -> void:
	var b := TextureButton.new()
	b.texture_normal = _ui_tex("scene_cave_%s" % icon)
	b.material = _pma
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.position = Vector2(1770, y)
	b.size = Vector2(96, 96)
	b.pressed.connect(cb)
	add_child(b)
	var l := Label.new()
	l.text = label
	l.position = Vector2(1740, y + 96)
	l.add_theme_font_size_override("font_size", 20)
	add_child(l)

func _build_topbar() -> void:
	var top := Label.new()
	top.name = "TopCurrency"
	top.position = Vector2(960, 24)
	top.add_theme_font_size_override("font_size", 28)
	add_child(top)
	var x := Button.new()
	x.text = "✕"
	x.position = Vector2(1850, 16)
	x.size = Vector2(54, 54)
	x.pressed.connect(func(): get_tree().quit())
	add_child(x)

# ---------- refresh ----------
func _refresh() -> void:
	var skin_idx: int = int(SaveSystem.state.get("cave_skin", 0)) % SKIN_COUNT
	_bg.texture = load(BG % (skin_idx + 1))
	_refresh_dragon()
	_refresh_list()
	_refresh_stats()
	var c: Dictionary = SaveSystem.state["currency"]
	get_node("TopCurrency").text = "골드 %d    다이아 %d" % [int(c.get("gold", 0)), int(c.get("diamond", 0))]

func _refresh_dragon() -> void:
	for ch in _stage.get_children():
		ch.queue_free()
	# 받침대: 타원형 발판 (참고 이미지의 회색 디스크)
	var ped := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 40:
		var ang := TAU * i / 40.0
		pts.append(Vector2(cos(ang) * 210, sin(ang) * 62))
	ped.polygon = pts
	ped.color = Color(0.74, 0.76, 0.82, 0.85)
	ped.position = Vector2(0, 190)
	_stage.add_child(ped)
	var a := _active()
	if a.is_empty(): return
	var stage_name := Data.stage_for_level(int(a["level"]))
	var path := DRAGON_SCENE % [int(a["id"]), stage_name]
	if ResourceLoader.exists(path):
		var holder := Node2D.new()
		holder.scale = Vector2(2.6, 2.6)
		holder.position = Vector2(0, 175)
		_stage.add_child(holder)
		var inst = load(path).instantiate()
		holder.add_child(inst)
		var ap = inst.get_node_or_null("AnimationPlayer")
		if ap and ap.has_animation("wait"):
			ap.play("wait")

func _refresh_list() -> void:
	for ch in _list_box.get_children():
		ch.queue_free()
	var owned: Array = SaveSystem.state["owned_dragons"]
	for i in owned.size():
		var d: Dictionary = Data.get_dragon(int(owned[i]["id"]))
		var b := Button.new()
		b.custom_minimum_size = Vector2(132, 84)
		b.text = "%s\nLv.%d" % [str(d.get("name", "?")), int(owned[i]["level"])]
		b.add_theme_font_size_override("font_size", 18)
		var idx := i
		b.pressed.connect(func():
			SaveSystem.state["active_dragon"] = idx
			SaveSystem.save_game()
			_refresh())
		_list_box.add_child(b)

func _refresh_stats() -> void:
	var a := _active()
	if a.is_empty():
		_stat_label.text = "보유 드래곤 없음"
		return
	var d: Dictionary = Data.get_dragon(int(a["id"]))
	var lv := int(a["level"])
	var s := Data.compute_stats(int(a["id"]), lv)
	_stat_label.text = "[b]%s[/b]   [color=#9cf]%s · %s · %s성[/color]\nLv.%d  [%s]  등급 %.1f\n\n[color=#f88]생명력[/color] %d\n[color=#fc8]공격력[/color] %d\n[color=#8cf]방어력[/color] %d\nCRI %d%%  EVD %d%%  BLK %d%%" % [
		str(d.get("name", "?")), str(d.get("element", "?")), str(d.get("type", "?")), str(d.get("star", "?")),
		lv, Data.stage_for_level(lv), float(a.get("grade", 8.0)),
		s["hp"], s["att"], s["def"], s["cri"], s["evd"], s["blk"]]

# ---------- actions ----------
func _on_levelup() -> void:
	var owned: Array = SaveSystem.state["owned_dragons"]
	var i := int(SaveSystem.state.get("active_dragon", 0))
	if i < owned.size():
		owned[i]["level"] = mini(45, int(owned[i]["level"]) + 1)  # TODO: 경험치/아이템 소비(§E,§K)
		SaveSystem.save_game()
		_refresh()

func _cycle_skin() -> void:
	SaveSystem.state["cave_skin"] = (int(SaveSystem.state.get("cave_skin", 0)) + 1) % SKIN_COUNT
	SaveSystem.save_game()
	_refresh()

func _close_overlay() -> void:
	if _overlay: _overlay.queue_free(); _overlay = null

func _make_overlay(title: String) -> VBoxContainer:
	_close_overlay()
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0, 0, 0, 0.78)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var box := VBoxContainer.new()
	box.position = Vector2(360, 80)
	box.custom_minimum_size = Vector2(1200, 920)
	_overlay.add_child(box)
	var head := HBoxContainer.new()
	var t := Label.new(); t.text = title; t.add_theme_font_size_override("font_size", 40)
	head.add_child(t)
	var close := Button.new(); close.text = "  닫기 ✕  "
	close.pressed.connect(_close_overlay)
	head.add_child(close)
	box.add_child(head)
	return box

func _open_dex() -> void:
	var box := _make_overlay("도감")
	var owned_ids := {}
	for o in SaveSystem.state["owned_dragons"]:
		owned_ids[int(o["id"])] = true
	var il := ItemList.new()
	il.custom_minimum_size = Vector2(1180, 840)
	il.max_columns = 3
	il.fixed_column_width = 380
	for id in Data.dragon_ids():
		var d: Dictionary = Data.get_dragon(id)
		var mark := "★" if owned_ids.has(id) else "·"
		il.add_item("%s #%d %s [%s/%s]" % [mark, id, str(d.get("name", "?")), str(d.get("element", "")), str(d.get("type", ""))])
	box.add_child(il)

func _open_inventory() -> void:
	var box := _make_overlay("인벤토리")
	var inv: Dictionary = SaveSystem.state.get("inventory", {})
	if inv.is_empty():
		var e := Label.new(); e.text = "보유 아이템 없음"; box.add_child(e); return
	for item_name in inv.keys():
		var row := HBoxContainer.new()
		var l := Label.new(); l.text = "%s  ×%d" % [str(item_name), int(inv[item_name])]
		l.custom_minimum_size = Vector2(400, 0)
		l.add_theme_font_size_override("font_size", 28)
		row.add_child(l)
		var use := Button.new(); use.text = "사용"
		use.pressed.connect(func():
			inv[item_name] = maxi(0, int(inv[item_name]) - 1)  # TODO: 효과 적용(§E)
			if inv[item_name] == 0: inv.erase(item_name)
			SaveSystem.save_game(); _open_inventory())
		row.add_child(use)
		box.add_child(row)

func _open_cards() -> void:
	var box := _make_overlay("카드")
	var l := Label.new(); l.text = "카드 시스템 (추후 구현)"; l.add_theme_font_size_override("font_size", 28)
	box.add_child(l)
