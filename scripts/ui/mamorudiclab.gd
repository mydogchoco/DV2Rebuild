extends Control

const DIR_UI := "mamorudiclab_ui"
const BG := "res://assets/converted/mamorudiclab_bg/mamorudic_bg.jpg"

const KIND_AWAKEN := 0
const KIND_STONE := 1
const KIND_MENU := -1

const TABS := [
	{"kind": KIND_AWAKEN, "frame": "txt_dragon_evolution1_kr", "text": "드래곤 각성"},
	{"kind": KIND_STONE, "frame": "txt_evolution_make2_kr", "text": "각성마석 제작"},
]

var _params: Dictionary = {}
var _kind := KIND_AWAKEN
var _pma: CanvasItemMaterial
var _man: Dictionary = {}
var _npc: NpcPortrait
var _box: BottomTextBox
var _gauge: ProgressBar
var _gauge_lbl: Label

func enter(params: Dictionary = {}) -> void:
	Bgm.play("bg_laboratory")
	_params = params
	_kind = int(params.get("tab", KIND_MENU))
	if _pma != null: _rebuild()

func _ready() -> void:
	_pma = AtlasUI.pma()
	_rebuild()

func _vis() -> Vector2:
	return get_viewport_rect().size

func _zoom() -> float:
	return _vis().x / 1024.0

func _load_man() -> void:
	if not _man.is_empty(): return
	var p := "res://assets/converted/%s/_manifest.json" % DIR_UI
	if FileAccess.file_exists(p):
		var d = JSON.parse_string(FileAccess.open(p, FileAccess.READ).get_as_text())
		if d is Dictionary: _man = d

func _spr(name: String, scale := 1.0) -> Sprite2D:
	return AtlasUI.spr(DIR_UI, "scene_mamorudiclab_%s" % name, scale)

func _rebuild() -> void:
	for c in get_children(): c.queue_free()
	_npc = null; _box = null; _gauge = null; _gauge_lbl = null
	_load_man()
	var vis := _vis()
	if ResourceLoader.exists(BG):
		var full := TextureRect.new(); full.texture = load(BG)
		full.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		full.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		full.set_anchors_preset(Control.PRESET_FULL_RECT)
		full.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(full)
	else:
		var bg := ColorRect.new(); bg.color = Color(0.06, 0.05, 0.10)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
	if _kind == KIND_MENU:
		_build_menu(vis)
	elif _kind == KIND_STONE:
		_build_brazier(vis)
		_build_stone_info(vis)
	else:
		_build_stand(vis)
	_build_npc(vis)
	_build_base(vis)

func _build_base(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var tb := _spr("mamo_top_title_bg", S)
	if tb: tb.position = Vector2(vis.x * 0.5, 40.0); tb.z_index = 20; add_child(tb)
	var t1 := Label.new(); t1.text = Data.ui("#e62e8e56")
	t1.add_theme_font_size_override("font_size", 32)
	t1.add_theme_color_override("font_color", Color(1.0, 0.83, 0.30))
	t1.add_theme_color_override("font_outline_color", Color(0.20, 0.09, 0.02, 0.95))
	t1.add_theme_constant_override("outline_size", 6)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t1.size = Vector2(vis.x, 42); t1.position = Vector2(0, 18); t1.z_index = 21
	add_child(t1)
	var xb := TextureButton.new()
	xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.scale = Vector2(S, S)
	var xw: float = xb.texture_normal.get_width() * S
	var xh: float = xb.texture_normal.get_height() * S
	xb.position = Vector2(vis.x * 0.932 - xw * 0.5, vis.y * 0.056 - xh * 0.5); xb.z_index = 22
	xb.pressed.connect(func(): Scenes.goto("worldmap", {"region": "uno"}))
	add_child(xb)
	if _kind != KIND_MENU:
		var back := TextureButton.new()
		back.texture_normal = load("res://assets/converted/common_ui/common_back_btn.tres")
		back.scale = Vector2(1.2 * S, 1.2 * S)
		var bw: float = back.texture_normal.get_width() * 1.2 * S
		var bh: float = back.texture_normal.get_height() * 1.2 * S
		back.position = Vector2(50.0 - bw * 0.5, 35.0 - bh * 0.5); back.z_index = 22
		back.pressed.connect(func():
			_kind = KIND_MENU
			_rebuild())
		add_child(back)
		_build_tabs(vis)
	_build_money(vis)

func _build_tabs(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var x := 50.0
	for t in TABS:
		var kind := int(t["kind"])
		var on := kind == _kind
		var tab := Control.new()
		tab.z_index = 23
		tab.position = Vector2(x, 66.0 + (0.0 if on else 10.0))
		add_child(tab)
		var bgs := AtlasUI.spr("common_ui", "common_tab_bg", S)
		var tw := 120.0 * S
		var th := 64.0 * S
		if bgs:
			tw = bgs.texture.get_width() * S
			th = bgs.texture.get_height() * S
			bgs.position = Vector2(tw * 0.5, th * 0.5)
			bgs.modulate = Color(1, 1, 1) if on else Color(0.68, 0.62, 0.55)
			tab.add_child(bgs)
		var lab := _spr(String(t["frame"]), S)
		if lab:
			lab.position = Vector2(tw * 0.5, th * 0.5)
			lab.modulate = Color(1, 1, 1) if on else Color(0.72, 0.68, 0.62)
			tab.add_child(lab)
		else:
			var l := Label.new(); l.text = String(t["text"])
			l.add_theme_font_size_override("font_size", 17)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.size = Vector2(tw, 22); l.position = Vector2(0, th * 0.5 - 11)
			tab.add_child(l)
		tab.size = Vector2(tw, th)
		if not on:
			var b := Button.new(); b.flat = true; b.size = Vector2(tw, th)
			b.pressed.connect(func():
				_kind = kind
				_rebuild())
			tab.add_child(b)
		x += tw + 6.0

func _build_money(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var sz := AtlasUI.size_pt(DIR_UI, "scene_mamorudiclab_money_bg_mamo")
	if sz == Vector2.ZERO: sz = Vector2(300.0, 120.0)
	var root := Control.new()
	root.size = sz
	root.position = Vector2(vis.x * 0.983 - sz.x, vis.y * 0.111)
	root.z_index = 24
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var bg := _spr("money_bg_mamo", S)
	if bg: bg.position = sz * 0.5; root.add_child(bg)
	for r in [["common_coin_small1", AtlasUI.comma(UserDB.gold()), 85.0],
			["common_diamond_small1", AtlasUI.comma(UserDB.diamond()), 45.0]]:
		var cy: float = sz.y - float(r[2])
		var ic := AtlasUI.spr("common_ui", String(r[0]), S)
		if ic: ic.position = Vector2(40.0, cy); root.add_child(ic)
		var l := Label.new(); l.text = String(r[1])
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		l.add_theme_color_override("font_outline_color", Color(0.15, 0.09, 0.03))
		l.add_theme_constant_override("outline_size", 5)
		l.position = Vector2(65.0, cy - 15.0)
		l.size = Vector2(sz.x - 90.0, 30.0)
		root.add_child(l)
	var ch := TextureButton.new()
	ch.texture_normal = load("res://assets/converted/common_ui/common_charge.tres")
	ch.scale = Vector2(S, S)
	var cw: float = ch.texture_normal.get_width() * S
	ch.position = Vector2(sz.x - 20.0 - cw, sz.y - 45.0 - ch.texture_normal.get_height() * S * 0.5)
	ch.pressed.connect(func(): Scenes.goto("shop", {"tab": "exchange"}))
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(ch)

func _build_npc(vis: Vector2) -> void:
	_npc = NpcPortrait.create("mamorudic", 1)
	if _npc != null:
		_npc.z_index = 5
		add_child(_npc)
		_npc.position = Vector2(vis.x - 150.0, vis.y)
	_box = BottomTextBox.new()
	_box.max_width = vis.x - 300.0
	_box.z_index = 12
	add_child(_box)
	_box.clicked.connect(func(): _say(_talk("mamorudic.idle")))
	_say(_talk("mamorudic.idle"))

func _talk(key: String) -> String:
	var pool: Array = (Data.npc_talk.get("screen", {}) as Dictionary).get(key, {}).get("lines", [])
	return String(pool[randi() % pool.size()]) if not pool.is_empty() else ""

func _talk_fmt(key: String, arg: String) -> String:
	return _talk(key).replace("%1$s", arg)

func _say(line: String) -> void:
	if not is_instance_valid(_box) or line == "":
		return
	_box.show_text("마모루딕", line)
	if is_instance_valid(_npc):
		_npc.set_talking(true)
		if not _box.finished.is_connected(_stop_talk):
			_box.finished.connect(_stop_talk)

func _stop_talk() -> void:
	if is_instance_valid(_npc):
		_npc.set_talking(false)

const MENU_CARDS := [
	{"title": "드래곤 각성", "icon": "icon_dragon_evolution", "kind": KIND_AWAKEN},
	{"title": "아티펙트 합성", "icon": "icon_artifact_mix", "kind": -2, "popup": "artifact_mix"},
	{"title": "각성의마석 제작", "icon": "icon_evolution_make", "kind": KIND_STONE},
	{"title": "마공학 대장간", "icon": "", "kind": -2},
	{"title": "아티펙트 제련", "icon": "", "kind": -2, "popup": "artifact_smelt"},
]

func _build_menu(_vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var k := 0.8 * S
	var cw := 129.0 * k
	var ch := 169.0 * k
	var centers := [
		Vector2(360.0, 205.0), Vector2(507.0, 205.0), Vector2(654.0, 205.0),
		Vector2(432.0, 414.0), Vector2(578.0, 414.0),
	]
	for i in MENU_CARDS.size():
		var ent: Dictionary = MENU_CARDS[i]
		var c: Vector2 = centers[i]
		var impl := int(ent["kind"]) >= 0 or String(ent.get("popup", "")) != ""
		var card := Control.new()
		card.position = c - Vector2(cw, ch) * 0.5
		card.size = Vector2(cw, ch)
		card.z_index = 6
		if not impl: card.modulate = Color(0.58, 0.55, 0.52)
		add_child(card)
		var bgs := _spr("mamo_sub_title_bg", k)
		if bgs: bgs.position = Vector2(cw, ch) * 0.5; card.add_child(bgs)
		var tl := Label.new()
		tl.text = String(ent["title"])
		tl.add_theme_font_size_override("font_size", 16)
		tl.add_theme_color_override("font_color", Color(0.32, 0.19, 0.07))
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.position = Vector2(0, 16.0); tl.size = Vector2(cw, 22.0)
		card.add_child(tl)
		if String(ent["icon"]) != "":
			var ic := _spr(String(ent["icon"]), 0.75 * S)
			if ic:
				ic.position = Vector2(cw * 0.5, ch * 0.58)
				card.add_child(ic)
		var b := Button.new(); b.flat = true; b.size = Vector2(cw, ch)
		b.pressed.connect(func():
			if String(ent.get("popup", "")) == "artifact_mix":
				_open_artifact_mix()
			elif String(ent.get("popup", "")) == "artifact_smelt":
				_open_artifact_smelt()
			elif impl:
				_kind = int(ent["kind"])
				_rebuild()
			else:
				_say("(%s — 아직 구현되지 않은 기능입니다.)" % String(ent["title"])))
		card.add_child(b)

func _open_artifact_mix() -> void:
	var p := ArtifactMixView.open(self)
	p.closed.connect(func(): _say("좋은 아티펙트가 나왔길 바라네."))

func _open_artifact_smelt() -> void:
	var cfg := Equipment.artifact_smelt_cfg(Data.equipment)
	var cost: Dictionary = cfg.get("items", {})
	var rows: Array = []
	for k in UserDB.inventory().keys():
		var key := String(k)
		if Equipment.artifact_of(key).is_empty():
			continue
		if UserDB.item_count(key) <= 0:
			continue
		if int(Equipment.item_key_meta(key).get("rarity", 0)) < 2:
			continue
		rows.append(key)
	rows.sort()

	var pop := FramedWindow.open(self, Data.ui("#eb0446a8"), Vector2(720.0, 520.0))
	var cost_txt: PackedStringArray = []
	for k in cost:
		cost_txt.append("%s %d" % [Data.item_name(String(k)), int(cost[k])])
	var head := Label.new()
	head.text = "옵션을 다시 굴릴 아티펙트를 고르게.  (1회 %s)" % " · ".join(cost_txt)
	head.add_theme_font_size_override("font_size", 16)
	head.add_theme_color_override("font_color", Color(0.30, 0.18, 0.06))
	head.position = Vector2(40.0, 84.0); head.size = Vector2(640.0, 24.0)
	pop.content.add_child(head)

	var sc := ScrollContainer.new()
	sc.position = Vector2(40.0, 116.0)
	sc.size = Vector2(640.0, 330.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pop.content.add_child(sc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.custom_minimum_size.x = 620.0
	sc.add_child(col)

	if rows.is_empty():
		var none := Label.new()
		none.text = "제련할 아티펙트가 없다네. (레어 등급 이상, 장착은 먼저 벗기게)"
		none.add_theme_font_size_override("font_size", 17)
		none.add_theme_color_override("font_color", Color(0.45, 0.34, 0.22))
		col.add_child(none)
		return

	for key: String in rows:
		var meta: Dictionary = Equipment.item_key_meta(key)
		var it: Dictionary = Equipment.catalog(Data.equipment).get(
			Equipment.parse_item_key(key), {})
		var parts: PackedStringArray = []
		for o in (meta.get("options", []) as Array):
			var od := o as Dictionary
			parts.append(EquipOptionView.opt_text(od, Data.equipment, ""))
		var b := Button.new()
		b.text = "  %s   %s   ×%d" % [String(it.get("name", key)),
			" ".join(parts) if not parts.is_empty() else "(옵션 없음)",
			UserDB.item_count(key)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(func(): _artifact_smelt_confirm(key, pop))
		col.add_child(b)

func _artifact_smelt_confirm(inv_key: String, list_pop: FramedWindow) -> void:
	var cfg := Equipment.artifact_smelt_cfg(Data.equipment)
	var cost: Dictionary = cfg.get("items", {})
	var lack: PackedStringArray = []
	for k in cost:
		if UserDB.item_count(String(k)) < int(cost[k]):
			lack.append("%s %d/%d" % [Data.item_name(String(k)),
				UserDB.item_count(String(k)), int(cost[k])])
	if not lack.is_empty():
		_notice(Data.ui("#eb0446a8"), "재료가 부족합니다.\n%s" % " · ".join(lack))
		return
	var grade := int(Equipment.item_key_meta(inv_key).get("rarity", 0))
	var txt: PackedStringArray = []
	for k in cost:
		txt.append("%s X %d" % [Data.item_name(String(k)), int(cost[k])])
	_confirm(Data.ui("#eb0446a8"),
		"해당 장비의 부가 옵션을 변경하시겠습니까?\n\n%s" % " · ".join(txt),
		func():
			for k in cost:
				if not UserDB.use_item(String(k), int(cost[k])):
					return
			if is_instance_valid(list_pop):
				list_pop.queue_free()
			var lay := EquipOptionView.open_artifact(self, inv_key, grade)
			lay.finished.connect(func(): _say("관통이 잘 붙었으면 좋겠군.")))

func _build_stand(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var z := _zoom()
	var at := Vector2(vis.x * 0.5 - 90.0 * z, vis.y * 0.5 + 75.0 * z)
	for i in 2:
		var sp := _spine("res://scenes/fx/lab_machine.tscn", at, S)
		if sp == null: continue
		var t := sp.create_tween()
		t.tween_property(sp, "position", at - Vector2(0, 15.0), 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
		t.tween_property(sp, "position", at, 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	var hit := Button.new(); hit.flat = true
	hit.size = Vector2(240.0, 200.0)
	hit.position = at - hit.size * 0.5
	hit.pressed.connect(_open_dragon_select)
	add_child(hit)
	var plate_pos := Vector2(24.0, vis.y - BottomTextBox.BOX_H * Design.ASSET_SCALE - 60.0)
	var plate := AtlasUI.nine("ninepatch_ui", "9patch_recall_del", Vector2(150.0, 44.0))
	if plate:
		plate.position = plate_pos
		plate.z_index = 6
		add_child(plate)
		var pl := Label.new(); pl.text = "각성 도감"
		pl.add_theme_font_size_override("font_size", 21)
		pl.add_theme_color_override("font_color", Color(1, 1, 1))
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pl.size = plate.size
		plate.add_child(pl)
	var book := _spr("bt_e_book", 1.05 * S)
	if book:
		book.position = plate_pos + Vector2(75.0, -book.texture.get_height() * 1.05 * S * 0.5)
		book.z_index = 6
		add_child(book)
	var bb := Button.new(); bb.flat = true
	bb.size = Vector2(150.0, 130.0)
	bb.position = plate_pos + Vector2(0, -86.0)
	bb.pressed.connect(_open_awaken_dex)
	add_child(bb)

func _build_brazier(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var z := _zoom()
	var at := Vector2(vis.x * 0.5 - 110.0 * z, vis.y * 0.5 + 40.0 * z)
	var sp := _spine("res://scenes/fx/lab_furnace.tscn", at, S)
	var bone := at
	if sp != null:
		var bn := sp.get_node_or_null("root/furnace_b1")
		if bn != null:
			bone = at + (bn as Node2D).position * S
	var hit := Button.new(); hit.flat = true
	hit.size = Vector2(200.0, 200.0)
	hit.position = bone - hit.size * 0.5
	hit.pressed.connect(_on_click_furnace)
	add_child(hit)
	var fin := AtlasUI.spr("common_ui", "common_finger", S)
	if fin:
		fin.position = bone + Vector2(50.0, 0)
		fin.z_index = 7
		add_child(fin)
		var ft := fin.create_tween().set_loops()
		ft.tween_property(fin, "scale", Vector2(1.2 * S, 1.2 * S), 0.6)
		ft.tween_property(fin, "scale", Vector2(0.9 * S, 0.9 * S), 0.6)

func _on_click_furnace() -> void:
	if int(_stone_state().get("star", 0)) > 0:
		_open_stone_make()
	else:
		_open_stone_select()

func _build_stone_info(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var W := 450.0
	var H := 40.0
	var st := _stone_state()
	var star := int(st.get("star", 0))
	var pts := int(st.get("points", 0))
	var need := AwakenStone.need(Data.awaken, star)
	var root := Control.new()
	root.size = Vector2(W, H)
	root.position = Vector2(vis.x * 0.5 - W * 0.5, vis.y - 170.0 - H)
	root.z_index = 14
	add_child(root)
	var bg := AtlasUI.nine("laboratory_ui", "scene_laboratory_lv_bg", Vector2(W, H), Rect2(20, 20, 4, 4))
	if bg: root.add_child(bg)
	if star > 0:
		var jk := "item_item_small_evol_evol_jewel_%d" % star
		var jt := AtlasUI.tex("item_small_evol", jk)
		if jt != null:
			var jc := Vector2(-jt.get_width() * 0.7 * S * 0.5, H * 0.5)
			var bl := AtlasUI.spr("common_ui", "common_backlight3", 0.3 * S)
			if bl:
				bl.position = jc
				bl.z_index = 1
				root.add_child(bl)
				var bt := bl.create_tween().set_loops()
				bt.tween_property(bl, "scale", Vector2(0.2 * S, 0.2 * S), 0.5)
				bt.tween_property(bl, "scale", Vector2(0.3 * S, 0.3 * S), 0.5)
				var br := bl.create_tween().set_loops()
				br.tween_property(bl, "rotation_degrees", 90.0, 1.0).as_relative()
			var ji := AtlasUI.spr("item_small_evol", jk, 0.7 * S)
			if ji:
				ji.position = jc
				ji.z_index = 2
				root.add_child(ji)
				var jw := jt.get_width() * 0.7 * S
				var jh := jt.get_height() * 0.7 * S
				var jb := Button.new(); jb.flat = true
				jb.size = Vector2(jw, jh)
				jb.position = jc - jb.size * 0.5
				jb.z_index = 3
				jb.pressed.connect(_open_stone_select)
				root.add_child(jb)
	var lab := Label.new()
	lab.text = "제작중" if star > 0 else "미선택"
	lab.add_theme_font_size_override("font_size", 17)
	lab.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.position = Vector2(10.0, 0); lab.size = Vector2(60.0, H)
	root.add_child(lab)
	var gx := 76.0
	var gw := 240.0
	var gbg := AtlasUI.spr("common_ui", "common_bar_bg2", 1.0)
	if gbg:
		gbg.position = Vector2(gx + gw * 0.5, H * 0.5)
		gbg.scale = Vector2(gw / maxf(1.0, gbg.texture.get_width()), 1.0)
		root.add_child(gbg)
	var fill := TextureProgressBar.new()
	fill.texture_progress = load("res://assets/converted/common_ui/common_bar_exp.tres")
	fill.nine_patch_stretch = true
	fill.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	fill.min_value = 0; fill.max_value = maxi(1, need)
	fill.value = clampi(pts, 0, maxi(1, need))
	fill.position = Vector2(gx, H * 0.5 - 7.0)
	fill.size = Vector2(gw, 14.0)
	root.add_child(fill)
	_gauge_lbl = Label.new()
	_gauge_lbl.text = "%d/%d" % [pts, need] if star > 0 else "-"
	_gauge_lbl.add_theme_font_size_override("font_size", 15)
	_gauge_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	_gauge_lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02))
	_gauge_lbl.add_theme_constant_override("outline_size", 4)
	_gauge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gauge_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gauge_lbl.position = Vector2(gx, 0); _gauge_lbl.size = Vector2(gw, H)
	root.add_child(_gauge_lbl)
	AtlasUI.frame_button(root, "변경", Vector2(gx + gw + 10.0, H * 0.5 - 19.0),
		Vector2(100.0, 38.0), _open_stone_select, 0)

func _stone_state() -> Dictionary:
	var m = UserDB.get_pmeta("awaken_stone", {})
	return m if m is Dictionary else {}

func _set_stone_state(star: int, points: int) -> void:
	UserDB.set_pmeta("awaken_stone", {"star": star, "points": points})

func _open_stone_select() -> void:
	var cur := int(_stone_state().get("star", 0))
	var pop := FramedWindow.open(self, Data.ui("#5e65f72e"), Vector2(680.0, 340.0))
	var picked := {"star": cur if cur > 0 else 0}
	var cells: Array = []
	var n := AwakenStone.STARS.size()
	var cell_w := 120.0
	var gap := 14.0
	var x0 := (pop.win_size.x - (cell_w * n + gap * (n - 1))) * 0.5
	for i in n:
		var star: int = AwakenStone.STARS[i]
		var cell := Control.new()
		cell.position = Vector2(x0 + float(i) * (cell_w + gap), 96.0)
		cell.size = Vector2(cell_w, 150.0)
		pop.content.add_child(cell)
		var mt := AtlasUI.tex("item_mtr", "item_mtr_evol_jewel_%d" % star)
		if mt != null:
			var s := Sprite2D.new(); s.texture = mt; s.material = _pma
			var k := 100.0 / maxf(1.0, float(mt.get_width()))
			s.scale = Vector2(k, k)
			s.position = Vector2(cell_w * 0.5, 52.0)
			cell.add_child(s)
		var nl := Label.new()
		nl.text = "%d성 마석" % star
		nl.add_theme_font_size_override("font_size", 18)
		nl.add_theme_color_override("font_color", Color(0.25, 0.15, 0.05))
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.size = Vector2(cell_w, 24.0); nl.position = Vector2(0, 108.0)
		cell.add_child(nl)
		var sel := ColorRect.new()
		sel.color = Color(1.0, 0.85, 0.35, 0.0)
		sel.size = Vector2(cell_w, 138.0)
		sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(sel)
		cells.append({"star": star, "hi": sel})
		var b := Button.new(); b.flat = true; b.size = Vector2(cell_w, 150.0)
		b.pressed.connect(func():
			picked["star"] = star
			for c in cells:
				(c["hi"] as ColorRect).color.a = 0.22 if int(c["star"]) == star else 0.0)
		cell.add_child(b)
	for c in cells:
		(c["hi"] as ColorRect).color.a = 0.22 if int(c["star"]) == picked["star"] else 0.0
	pop.add_action_button("선택", func():
		var star := int(picked["star"])
		if star <= 0:
			_say("제작할 각성 마석이 없습니다. 제작할 각성 마석을 선택하세요.")
			return
		if star == cur:
			pop.close()
			_open_stone_make()
			return
		var keep := int(_stone_state().get("points", 0))
		if cur > 0 and keep > 0:
			pop.close()
			_confirm("각성의 마석 변경",
				"각성의 마석을 변경하시겠습니까?\n변경시 기존에 누적된 포인트는 초기화 됩니다.",
				func():
					_set_stone_state(star, 0)
					_rebuild()
					_open_stone_make())
			return
		_set_stone_state(star, keep if cur == star else 0)
		pop.close()
		_rebuild()
		_open_stone_make())

func _open_stone_make() -> void:
	var st := _stone_state()
	var star := int(st.get("star", 0))
	if star <= 0:
		_open_stone_select()
		return
	var pts := int(st.get("points", 0))
	var need := AwakenStone.need(Data.awaken, star)
	var vis := _vis()
	var pop := FramedWindow.open(self, Data.ui("#778a2c54"), Vector2(vis.x - 50.0, 600.0))
	var W := pop.win_size.x
	var H := pop.win_size.y
	var picks := {}
	var state := {"sel": 0}
	var head := Label.new()
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", Color(0.30, 0.18, 0.06))
	head.position = Vector2(55.0, 56.0); head.size = Vector2(400.0, 26.0)
	pop.content.add_child(head)
	var hint := Label.new()
	hint.text = Data.ui("#72d8954b")
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.42, 0.30, 0.16))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(40.0, H - 42.0); hint.size = Vector2(W - 80.0, 22.0)
	pop.content.add_child(hint)
	var box_sz := Vector2(W * 0.5 + 100.0, 420.0)
	var box_pos := Vector2(48.0, 90.0)
	var box := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", box_sz, Rect2(65, 65, 6, 6))
	if box:
		box.position = box_pos
		pop.content.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.position = box_pos + Vector2(12.0, 8.0)
	scroll.size = box_sz - Vector2(24.0, 16.0)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pop.content.add_child(scroll)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 4)
	scroll.add_child(cols)
	var rx := box_pos.x + box_sz.x + 24.0
	var rw := W - rx - 45.0
	var right := Control.new()
	right.position = Vector2(rx, box_pos.y)
	right.size = Vector2(rw, box_sz.y)
	pop.content.add_child(right)
	var eggs: Array = []
	for key in UserDB.inventory().keys():
		var did := EggGacha.dragon_of(String(key))
		if did <= 0: continue
		var have := UserDB.item_count(String(key))
		if have <= 0: continue
		var info: Dictionary = Data.get_dragon(did)
		eggs.append({"id": did, "key": String(key), "have": have,
			"star": int(info.get("star", 0)), "name": String(info.get("name", "드래곤"))})
	eggs.sort_custom(func(a, b): return int(a["star"]) > int(b["star"]))
	if not eggs.is_empty():
		state["sel"] = int(eggs[0]["id"])
	var filt := {"elem": ""}
	var refresh := func():
		var entries: Array = []
		for did in picks.keys():
			var s := int(Data.get_dragon(int(did)).get("star", 0))
			entries.append({"star": s, "count": int(picks[did])})
		var add := AwakenStone.batch_points(Data.awaken, entries)
		head.text = "%d + %d / %d" % [pts, add, need]
	var fns := {}
	var changed := func():
		refresh.call()
		(fns["list"] as Callable).call()
		(fns["right"] as Callable).call()
	fns["right"] = func():
		for c in right.get_children(): c.queue_free()
		var e := {}
		for e0 in eggs:
			if int(e0["id"]) == int(state["sel"]): e = e0; break
		if e.is_empty(): return
		_stone_make_right(right, e, picks, changed)
	fns["list"] = func():
		for c in cols.get_children(): c.queue_free()
		var want := String(filt["elem"])
		var shown: Array = eggs.filter(func(e):
			if want == "": return true
			return String(Data.get_dragon(int(e["id"])).get("element", "")) == want)
		if shown.is_empty():
			var none := Label.new()
			none.text = "재료로 쓸 알이 없습니다.\n뽑기·상점에서 알을 구하면 여기 나옵니다."
			none.add_theme_font_size_override("font_size", 17)
			none.add_theme_color_override("font_color", Color(0.42, 0.30, 0.16))
			cols.add_child(none)
			return
		var per_col := 3
		var vb: VBoxContainer = null
		for i in shown.size():
			if i % per_col == 0:
				vb = VBoxContainer.new()
				vb.add_theme_constant_override("separation", 2)
				cols.add_child(vb)
			vb.add_child(_egg_cell(shown[i], picks, state, changed))
	var tabs: Array = []
	var fx := W * 0.5 - (DEX_ELEMENTS.size() * 58.0 - 6.0) * 0.5
	for ent in DEX_ELEMENTS:
		var el := String(ent["key"])
		var holder := Control.new()
		holder.position = Vector2(fx, H - 100.0); holder.size = Vector2(52.0, 52.0)
		pop.content.add_child(holder)
		var eb := AtlasUI.spr("common_ui", "common_element_bg", 0.54)
		if eb: eb.position = Vector2(26.0, 26.0); holder.add_child(eb)
		var ei := AtlasUI.spr("item_small_ui", String(ent["icon"]), 0.54)
		if ei: ei.position = Vector2(26.0, 26.0); holder.add_child(ei)
		if el != "": holder.modulate = Color(0.62, 0.62, 0.66)
		tabs.append(holder)
		var fb := Button.new(); fb.flat = true; fb.size = Vector2(52.0, 52.0)
		fb.pressed.connect(func():
			filt["elem"] = el
			for h in tabs:
				(h as Control).modulate = Color(1, 1, 1) if h == holder else Color(0.62, 0.62, 0.66)
			(fns["list"] as Callable).call())
		holder.add_child(fb)
		fx += 58.0
	(fns["list"] as Callable).call()
	(fns["right"] as Callable).call()
	refresh.call()
	var warned := {"over": false}
	var commit := func(entries: Array):
		for did in picks.keys():
			var n := int(picks[did])
			if n > 0:
				UserDB.use_item(EggGacha.key_for(int(did)), n)
		var res := AwakenStone.apply(Data.awaken, star, pts, entries)
		_set_stone_state(star, int(res["points"]))
		pop.close()
		var done := bool(res["complete"])
		var key := AwakenStone.reward_key(star) if done else ""
		if done:
			UserDB.add_item(key, 1)
		_rebuild()
		if done:
			_say(_talk_fmt("mamorudic.success", Data.item_name(key)))
			_make_stone_complete_popup(star, key)
	var on_enchant := func():
		var entries: Array = []
		for did in picks.keys():
			if int(picks[did]) <= 0: continue
			entries.append({"star": int(Data.get_dragon(int(did)).get("star", 0)),
				"count": int(picks[did])})
		var err := AwakenStone.check_batch(Data.awaken, star, pts, entries)
		if err != "":
			_say(err)
			return
		var over := AwakenStone.overflow(Data.awaken, star, pts, entries)
		if over > 0 and not bool(warned["over"]):
			warned["over"] = true
			_confirm("각성의 마석 제작",
				"각성에 필요한 포인트를 초과했습니다.\n초과된 %d 포인트는 사라집니다.\n제작을 진행하시겠습니까?" % over,
				func(): commit.call(entries))
			return
		commit.call(entries)
	pop.add_action_button("강화", on_enchant, 0, Vector2(220.0, 56.0),
		Vector2(rx + rw * 0.5, 505.0))

func _egg_cell(e: Dictionary, picks: Dictionary, state: Dictionary, changed: Callable) -> Control:
	var did := int(e["id"])
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(120.0, 132.0)
	if int(state["sel"]) == did:
		var hi := ColorRect.new()
		hi.color = Color(1.0, 0.85, 0.35, 0.20)
		hi.size = Vector2(116.0, 130.0); hi.position = Vector2(2.0, 0)
		hi.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(hi)
	var plate := AtlasUI.spr("cave_ui", "scene_cave_enchant_txt_bg", 1.0)
	if plate:
		plate.scale = Vector2(76.0 / maxf(1.0, plate.texture.get_width()), 1.0)
		plate.position = Vector2(44.0, 14.0)
		cell.add_child(plate)
	var pl := Label.new()
	pl.text = str(AwakenStone.egg_points(Data.awaken, int(e["star"])))
	pl.add_theme_font_size_override("font_size", 15)
	pl.add_theme_color_override("font_color", Color(1.0, 0.83, 0.30))
	pl.add_theme_color_override("font_outline_color", Color(0.2, 0.1, 0.02))
	pl.add_theme_constant_override("outline_size", 4)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.position = Vector2(6.0, 2.0); pl.size = Vector2(76.0, 24.0)
	cell.add_child(pl)
	var sh := AtlasUI.spr("common_ui", "common_shadow", 0.7 * Design.ASSET_SCALE)
	if sh: sh.position = Vector2(60.0, 92.0); cell.add_child(sh)
	var tex := Icons.dragon_egg_texture(did)
	if tex != null:
		var s := Sprite2D.new(); s.texture = tex; s.material = _pma
		var k := 56.0 / maxf(1.0, float(tex.get_width()))
		s.scale = Vector2(k, k); s.position = Vector2(60.0, 62.0)
		cell.add_child(s)
	var rp := AtlasUI.nine("ninepatch_ui", "9patch_recall_del", Vector2(70.0, 30.0))
	if rp:
		rp.position = Vector2(25.0, 100.0)
		cell.add_child(rp)
	var cnt := Label.new()
	cnt.text = "%d/%d" % [int(picks.get(did, 0)), int(e["have"])]
	cnt.add_theme_font_size_override("font_size", 15)
	cnt.add_theme_color_override("font_color", Color(1, 1, 1))
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cnt.position = Vector2(25.0, 100.0); cnt.size = Vector2(70.0, 30.0)
	cell.add_child(cnt)
	var b := Button.new(); b.flat = true; b.size = Vector2(120.0, 132.0)
	b.pressed.connect(func():
		state["sel"] = did
		changed.call())
	cell.add_child(b)
	return cell

func _stone_make_right(host: Control, e: Dictionary, picks: Dictionary, changed: Callable) -> void:
	var S := Design.ASSET_SCALE
	var did := int(e["id"])
	var have := int(e["have"])
	var rw := host.size.x
	var nl := Label.new()
	nl.text = String(e["name"])
	nl.add_theme_font_size_override("font_size", 20)
	nl.add_theme_color_override("font_color", Color(0.25, 0.15, 0.05))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.position = Vector2(0, 0); nl.size = Vector2(rw, 26.0)
	host.add_child(nl)
	var sl := Label.new()
	sl.text = "★".repeat(maxi(1, int(e["star"])))
	sl.add_theme_font_size_override("font_size", 16)
	sl.add_theme_color_override("font_color", Color(1.0, 0.80, 0.16))
	sl.add_theme_color_override("font_outline_color", Color(0.32, 0.18, 0.02))
	sl.add_theme_constant_override("outline_size", 4)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.position = Vector2(0, 26.0); sl.size = Vector2(rw, 22.0)
	host.add_child(sl)
	var ax := rw * 0.28
	var up := TextureButton.new()
	var ut := AtlasUI.tex("common_ui", "common_btn_arrow2")
	if ut != null:
		up.texture_normal = ut
		up.scale = Vector2(S, S)
		up.pivot_offset = Vector2.ZERO
	up.rotation_degrees = -90.0
	up.position = Vector2(ax - 14.0, 116.0)
	up.pressed.connect(func():
		var current := int(picks.get(did, 0))
		if current <= 0 and picks.size() >= AwakenStone.max_kinds(Data.awaken):
			_say(Data.ui("#304284d5"))
			return
		picks[did] = mini(have, current + 1)
		changed.call())
	host.add_child(up)
	var cnt := Label.new()
	cnt.text = str(int(picks.get(did, 0)))
	cnt.add_theme_font_size_override("font_size", 22)
	cnt.add_theme_color_override("font_color", Color(0.25, 0.15, 0.05))
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cnt.position = Vector2(ax - 34.0, 132.0); cnt.size = Vector2(56.0, 30.0)
	host.add_child(cnt)
	var dn := TextureButton.new()
	var dt := AtlasUI.tex("common_ui", "common_btn_arrow1")
	if dt != null:
		dn.texture_normal = dt
		dn.scale = Vector2(S, S)
		dn.pivot_offset = Vector2.ZERO
	dn.rotation_degrees = -90.0
	dn.position = Vector2(ax - 14.0, 214.0)
	dn.pressed.connect(func():
		picks[did] = maxi(0, int(picks.get(did, 0)) - 1)
		if int(picks[did]) == 0: picks.erase(did)
		changed.call())
	host.add_child(dn)
	var ec := Vector2(rw * 0.62, 160.0)
	var sh := AtlasUI.spr("common_ui", "common_shadow", 1.1 * S)
	if sh: sh.position = ec + Vector2(0, 52.0); host.add_child(sh)
	var tex := Icons.dragon_egg_texture(did)
	if tex != null:
		var s := Sprite2D.new(); s.texture = tex; s.material = _pma
		var k := 96.0 / maxf(1.0, float(tex.get_width()))
		s.scale = Vector2(k, k); s.position = ec
		host.add_child(s)
	var tb_sz := Vector2(minf(290.0, rw), 125.0)
	var tb := AtlasUI.nine("ninepatch_ui", "9patch_text_box", tb_sz, Rect2(25, 25, 3, 3))
	if tb:
		tb.position = Vector2((rw - tb_sz.x) * 0.5, 250.0)
		host.add_child(tb)
	var info := Label.new()
	info.text = "%s의 알\n개당 %d 포인트\n보유 %d개" % [String(e["name"]),
		AwakenStone.egg_points(Data.awaken, int(e["star"])), have]
	info.add_theme_font_size_override("font_size", 15)
	info.add_theme_color_override("font_color", Color(0.42, 0.30, 0.16))
	info.position = Vector2((rw - tb_sz.x) * 0.5 + 18.0, 264.0)
	info.size = Vector2(tb_sz.x - 36.0, 100.0)
	host.add_child(info)

func _open_dragon_select() -> void:
	var cfg: Dictionary = Data.awaken
	var min_lv := int(cfg.get("min_level", 50))
	var owned: Array = UserDB.dragons().filter(func(d):
		return not UserDB.is_egg(d) and not bool(d.get("awakened", false)))
	if owned.is_empty():
		_say(Data.ui("#fbaa127d"))
		return
	var vis := _vis()
	var pop := FramedWindow.open(self, "", Vector2(vis.x - 50.0, 600.0))
	var W := pop.win_size.x
	var tt := Label.new()
	tt.text = "드래곤 선택"
	tt.add_theme_font_size_override("font_size", 24)
	tt.add_theme_color_override("font_color", Color(0.25, 0.15, 0.05))
	tt.position = Vector2(55.0, 12.0); tt.size = Vector2(300.0, 30.0)
	pop.content.add_child(tt)
	var cm := Label.new()
	cm.text = "* 드래곤 레벨 %d, 각성 재료가 있는 드래곤만 선택 할 수 있습니다." % min_lv
	cm.add_theme_font_size_override("font_size", 15)
	cm.add_theme_color_override("font_color", Color(0.42, 0.30, 0.16))
	cm.position = Vector2(55.0, 44.0); cm.size = Vector2(700.0, 22.0)
	pop.content.add_child(cm)
	var box := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", Vector2(W - 100.0, 481.0),
		Rect2(65, 65, 6, 6))
	if box:
		box.position = Vector2(50.0, 600.0 - 40.0 - 481.0)
		pop.content.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(60.0, 89.0); scroll.size = Vector2(W - 120.0, 465.0)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pop.content.add_child(scroll)
	var rowbox := HBoxContainer.new()
	rowbox.add_theme_constant_override("separation", 8)
	scroll.add_child(rowbox)
	for d in owned:
		rowbox.add_child(_awaken_card(d, min_lv, pop))

func _awaken_card(d: Dictionary, min_lv: int, pop: FramedWindow) -> Control:
	const CW := 320.0
	const CH := 461.0
	var S := Design.ASSET_SCALE
	var cfg: Dictionary = Data.awaken
	var did := int(d.get("id", 1))
	var info: Dictionary = Data.get_dragon(did)
	var star := int(info.get("star", 0))
	var lv := int(d.get("level", 1))
	var mats: Array = (cfg.get("materials_by_star", {}) as Dictionary).get(str(star), [])
	var ok := lv >= min_lv and not mats.is_empty()
	for m in mats:
		if UserDB.item_count(String(m[0])) < int(m[1]): ok = false
	var card := Control.new()
	card.custom_minimum_size = Vector2(CW, CH)
	var bg := AtlasUI.nine("ninepatch_ui", "9patch_train_box4", Vector2(CW, CH), Rect2(20, 20, 4, 4))
	if bg:
		if not ok: bg.modulate = Color(0.39, 0.39, 0.39)
		card.add_child(bg)
	var el := String(info.get("element", ""))
	for ent in DEX_ELEMENTS:
		if String(ent["key"]) == el:
			var ei := AtlasUI.spr("item_small_ui", String(ent["icon"]), 0.6 * S)
			if ei:
				ei.position = Vector2(10.0 + ei.texture.get_width() * 0.3 * S,
					10.0 + ei.texture.get_height() * 0.3 * S)
				ei.z_index = 100
				card.add_child(ei)
			break
	var feet := Vector2(CW * 0.5, CH * 0.47)
	var sh := AtlasUI.spr("common_ui", "common_shadow", S)
	if sh: sh.position = feet + Vector2(0, 4.0); card.add_child(sh)
	var sp := _dragon_node(did, Growth.stage_for_level(lv), 0.45 * S)
	sp.position = feet
	card.add_child(sp)
	var gr := Label.new()
	gr.text = "%.1f" % Growth.compute_grade(info, Data.stat_table, d.get("stat_bonus", {}),
		d.get("gain_log", []), Data.level_curve.get("grade", {}))
	gr.add_theme_font_size_override("font_size", 26)
	gr.add_theme_color_override("font_color", Color(1.0, 0.83, 0.30))
	gr.add_theme_color_override("font_outline_color", Color(0.25, 0.12, 0.02, 0.95))
	gr.add_theme_constant_override("outline_size", 5)
	gr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gr.position = Vector2(CW - 240.0, CH * 0.5 - 35.0); gr.size = Vector2(220.0, 30.0)
	gr.z_index = 100
	card.add_child(gr)
	var pill_c := Vector2(CW * 0.5, CH * 0.5 + 30.0)
	var pill_w := 280.0
	var pill := AtlasUI.spr("promote_ui", "scene_promote_train_box1", S)
	if pill:
		pill.position = pill_c
		pill_w = pill.texture.get_width() * S
		pill.z_index = 100
		card.add_child(pill)
	var nl := Label.new()
	nl.text = "레벨 %d %s" % [lv, String(d.get("name", info.get("name", "드래곤")))]
	nl.add_theme_font_size_override("font_size", 17)
	nl.add_theme_color_override("font_color", Color(1, 1, 1))
	nl.add_theme_color_override("font_outline_color", Color(0.16, 0.10, 0.04, 0.9))
	nl.add_theme_constant_override("outline_size", 4)
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.position = Vector2(pill_c.x - pill_w * 0.5 + 20.0, pill_c.y - 14.0)
	nl.size = Vector2(pill_w - 40.0, 28.0)
	nl.z_index = 101
	card.add_child(nl)
	var order := mats.duplicate()
	order.sort_custom(func(a, b):
		return _mat_rank(String(a[0])) < _mat_rank(String(b[0])))
	var left := pill_c.x - pill_w * 0.5
	var right := pill_c.x + pill_w * 0.5
	var y := pill_c.y + 32.0
	for m in order:
		var key := String(m[0])
		var have := UserDB.item_count(key)
		var need := int(m[1])
		var icp := Data.item_icon_path(key)
		if icp != "" and ResourceLoader.exists(icp):
			var t: Texture2D = load(icp)
			var si := Sprite2D.new(); si.texture = t; si.material = _pma
			var ik := 34.0 / maxf(1.0, float(t.get_height()))
			si.scale = Vector2(ik, ik)
			si.position = Vector2(left + 18.0, y + 19.0)
			si.z_index = 100
			card.add_child(si)
		var ml := Label.new()
		ml.text = "%s :" % Data.item_name(key)
		ml.add_theme_font_size_override("font_size", 16)
		ml.add_theme_color_override("font_color", Color(1, 1, 1))
		ml.add_theme_color_override("font_outline_color", Color(0.16, 0.10, 0.04, 0.9))
		ml.add_theme_constant_override("outline_size", 4)
		ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ml.position = Vector2(left + 46.0, y + 6.0); ml.size = Vector2(180.0, 26.0)
		ml.z_index = 100
		card.add_child(ml)
		var cl := Label.new()
		cl.text = "%d / %d" % [have, need]
		cl.add_theme_font_size_override("font_size", 15)
		cl.add_theme_color_override("font_color",
			Color(1, 1, 1) if have >= need else Color(0.96, 0.28, 0.22))
		cl.add_theme_color_override("font_outline_color", Color(0.16, 0.10, 0.04, 0.9))
		cl.add_theme_constant_override("outline_size", 4)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cl.position = Vector2(right - 150.0, y + 6.0); cl.size = Vector2(150.0, 26.0)
		cl.z_index = 100
		card.add_child(cl)
		y += 38.0
	if ok:
		var b := Button.new(); b.flat = true; b.size = Vector2(CW, CH)
		b.pressed.connect(func():
			pop.close()
			_open_awaken_confirm(d))
		card.add_child(b)
	return card

func _mat_rank(key: String) -> int:
	if key.begins_with("evol_jewel"): return 0
	if key == "bonner": return 1
	return 2

func _dragon_node(did: int, stage: String, scale: float) -> Node2D:
	var path := Icons.spine_scene(did, stage)
	if path != "":
		var n := (load(path) as PackedScene).instantiate() as Node2D
		n.scale = Vector2(scale, scale)
		var ap := n.get_node_or_null("AnimationPlayer")
		if ap and ap.has_animation("wait"):
			ap.get_animation("wait").loop_mode = Animation.LOOP_LINEAR
			ap.play("wait")
		return n
	var holder := Node2D.new()
	var tex := _portrait(did, stage)
	if tex != null:
		var s := Sprite2D.new(); s.texture = tex; s.material = _pma
		var k := 160.0 / maxf(1.0, float(tex.get_width()))
		s.scale = Vector2(k, k)
		s.position = Vector2(0, -tex.get_height() * k * 0.5)
		holder.add_child(s)
	return holder

func _open_awaken_confirm(d: Dictionary) -> void:
	var S := Design.ASSET_SCALE
	var cfg: Dictionary = Data.awaken
	var did := int(d.get("id", 1))
	var info: Dictionary = Data.get_dragon(did)
	var star := int(info.get("star", 0))
	var name := String(info.get("name", "드래곤"))
	var mats: Array = (cfg.get("materials_by_star", {}) as Dictionary).get(str(star), [])
	var gold := int((cfg.get("gold_by_star", {}) as Dictionary).get(str(star), 0))
	var aw_no := Data.awaken_skill_of(did)
	var sk: Dictionary = Data.skill_awaken_for(aw_no) if aw_no > 0 else {}
	var pop := FramedWindow.open(self, "드래곤 각성", Vector2(650.0, 440.0))
	var col_x := 100.0
	var txt_x := 175.0
	var y := 88.0
	var wb := AtlasUI.nine("ninepatch_ui", "9patch_box_worldbook", Vector2(110.0, 110.0),
		Rect2(10, 10, 10, 10))
	if wb:
		wb.position = Vector2(col_x - 55.0, y)
		pop.content.add_child(wb)
	var pc := Vector2(col_x, y + 55.0)
	var dbg := AtlasUI.spr("common_ui", "common_dragon_bg1", S)
	if dbg:
		dbg.scale = Vector2(96.0 / maxf(1.0, dbg.texture.get_width()),
			96.0 / maxf(1.0, dbg.texture.get_height()))
		dbg.position = pc
		pop.content.add_child(dbg)
	var dpor := _portrait(did, Growth.stage_for_level(int(d.get("level", 1))))
	if dpor != null:
		var ds := Sprite2D.new(); ds.texture = dpor; ds.material = _pma
		var dk: float = minf(88.0 / maxf(1.0, float(dpor.get_width())),
			88.0 / maxf(1.0, float(dpor.get_height())))
		ds.scale = Vector2(dk, dk); ds.position = pc
		pop.content.add_child(ds)
	var dcv := AtlasUI.spr("common_ui", "common_dragon_cover1", S)
	if dcv:
		dcv.scale = Vector2(100.0 / maxf(1.0, dcv.texture.get_width()),
			100.0 / maxf(1.0, dcv.texture.get_height()))
		dcv.position = pc
		pop.content.add_child(dcv)
	var l1 := _rich(txt_x, y + 8.0, 430.0,
		"각성시 [ [color=#c22015]체력, 공격력, 방어력[/color] ] 이 증가합니다", 18)
	pop.content.add_child(l1)
	var ln1 := AtlasUI.nine("ninepatch_ui", "9patch_menu_txt_line", Vector2(440.0, 6.0))
	if ln1:
		ln1.position = Vector2(txt_x, y + 42.0)
		pop.content.add_child(ln1)
	if not sk.is_empty():
		var l2 := _rich(txt_x, y + 56.0, 430.0,
			"각성전용스킬 : [[color=#c22015]%s[/color]] 획득" % String(sk.get("name", "")), 18)
		pop.content.add_child(l2)
		y += 132.0
		var sbg := AtlasUI.spr("common_ui", "common_skill_evolution_bg", 0.8 * S)
		if sbg:
			sbg.position = Vector2(col_x, y + 40.0)
			pop.content.add_child(sbg)
		var sico := int(sk.get("icon", 0))
		if sico > 0:
			var sip := "res://assets/converted/skill_evolution/skill_evolution_%d.tres" % sico
			if ResourceLoader.exists(sip):
				var sit: Texture2D = load(sip)
				var ss := Sprite2D.new(); ss.texture = sit; ss.material = _pma
				ss.scale = Vector2(0.8 * S, 0.8 * S)
				ss.position = Vector2(col_x, y + 40.0)
				pop.content.add_child(ss)
		var pill := AtlasUI.nine("ninepatch_ui", "9patch_menu_txt_line", Vector2(440.0, 38.0))
		if pill:
			pill.position = Vector2(txt_x, y + 22.0)
			pop.content.add_child(pill)
		var eff := Label.new()
		eff.text = String(sk.get("comment", ""))
		eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		eff.add_theme_font_size_override("font_size", 15)
		eff.add_theme_color_override("font_color", Color(0.30, 0.18, 0.06))
		eff.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		eff.position = Vector2(txt_x + 12.0, y + 22.0); eff.size = Vector2(416.0, 38.0)
		pop.content.add_child(eff)
		y += 84.0
	else:
		y += 100.0
		var l2b := Label.new()
		l2b.text = "이 종족의 각성 전용 스킬은 아직 배정되지 않았습니다(data/skill_awaken.json)."
		l2b.add_theme_font_size_override("font_size", 15)
		l2b.add_theme_color_override("font_color", Color(0.55, 0.40, 0.22))
		l2b.position = Vector2(txt_x, y); l2b.size = Vector2(430.0, 24.0)
		pop.content.add_child(l2b)
		y += 40.0
	var ask := _rich(40.0, y + 14.0, 570.0,
		"[center][ [color=#c22015]%s[/color] ] 드래곤을 각성시키겠습니까?[/center]" % name, 19)
	pop.content.add_child(ask)
	var on_ok := func():
		if UserDB.gold() < gold:
			_say(Data.ui("#6d912d92"))
			return
		for m in mats:
			if UserDB.item_count(String(m[0])) < int(m[1]):
				_say(Data.ui("#bc4c8d36"))
				return
		pop.close()
		_do_awaken(d, mats, gold)
	var btn := pop.add_action_button("     x%s" % AtlasUI.comma(gold), on_ok, 0, Vector2(230.0, 56.0))
	var coin := AtlasUI.spr("common_ui", "common_coin_small1", S)
	if coin:
		coin.position = Vector2(38.0, 28.0)
		btn.add_child(coin)

func _rich(x: float, y: float, w: float, bbcode: String, fs: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", fs)
	r.add_theme_color_override("default_color", Color(0.30, 0.18, 0.06))
	r.text = bbcode
	r.position = Vector2(x, y); r.size = Vector2(w, 30.0)
	return r

func _do_awaken(d: Dictionary, mats: Array, gold: int) -> void:
	var uid := int(d.get("uid", 0))
	for m in mats:
		UserDB.use_item(String(m[0]), int(m[1]))
	if gold > 0:
		UserDB.spend("gold", gold)
	UserDB.set_dragon_field(uid, "awakened", true)
	var did := int(d.get("id", 1))
	var aw_no := Data.awaken_skill_of(did)
	if aw_no > 0:
		UserDB.set_dragon_field(uid, "awaken_skill", aw_no)
	_say(_talk("mamorudic.awake"))
	var vis := _vis()
	var z := _zoom()
	AwakenSequence.open(self, uid, Vector2(vis.x * 0.5 - 90.0 * z, vis.y * 0.5 + 75.0 * z),
		func(): _rebuild())

const DEX_ELEMENTS := [
	{"key": "", "icon": "item_item_small_ele_all"},
	{"key": "fire", "icon": "item_item_small_ele_fire"},
	{"key": "aqua", "icon": "item_item_small_ele_water"},
	{"key": "earth", "icon": "item_item_small_ele_ground"},
	{"key": "wind", "icon": "item_item_small_ele_wind"},
	{"key": "light", "icon": "item_item_small_ele_light"},
	{"key": "dark", "icon": "item_item_small_ele_dark"},
	{"key": "holy", "icon": "item_item_small_ele_holy"},
	{"key": "chaos", "icon": "item_item_small_ele_chaos"},
	{"key": "shadow", "icon": "item_item_small_ele_shadow"},
]

func _open_awaken_dex() -> void:
	var vis := _vis()
	var pop := FramedWindow.open(self, "", Vector2(vis.x - 20.0, vis.y - 20.0))
	pop.body.position.y = 10.0
	var W := pop.win_size.x
	var H := pop.win_size.y
	var tt := Label.new()
	tt.text = "각성 도감"
	tt.add_theme_font_size_override("font_size", 26)
	tt.add_theme_color_override("font_color", Color(0.25, 0.15, 0.05))
	tt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tt.position = Vector2(0, 16.0); tt.size = Vector2(W, 32.0)
	pop.content.add_child(tt)
	var species: Array = []
	for did in Data.dragons.keys():
		if Data.awaken_skill_of(int(did)) > 0 and UserDB.dex_seen(int(did)):
			species.append(int(did))
	species.sort()
	var state := {"elem": "", "sel": (species[0] if not species.is_empty() else -1)}
	var box_sz := Vector2(W * 0.5, 420.0)
	var box_pos := Vector2(48.0, H - 150.0 - 420.0)
	var box := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", box_sz, Rect2(65, 65, 6, 6))
	if box:
		box.position = box_pos
		pop.content.add_child(box)
	var grid_host := Control.new()
	grid_host.position = box_pos + Vector2(14.0, 12.0)
	grid_host.size = box_sz - Vector2(28.0, 24.0)
	pop.content.add_child(grid_host)
	var detail := Control.new()
	detail.position = Vector2(box_pos.x + box_sz.x + 24.0, box_pos.y)
	detail.size = Vector2(W - (box_pos.x + box_sz.x) - 64.0, box_sz.y)
	pop.content.add_child(detail)
	var fns := {}
	var redraw := func(): (fns["redraw"] as Callable).call()
	fns["redraw"] = func():
		for c in grid_host.get_children(): c.queue_free()
		for c in detail.get_children(): c.queue_free()
		var scroll := ScrollContainer.new()
		scroll.size = grid_host.size
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		grid_host.add_child(scroll)
		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		scroll.add_child(grid)
		for did in species:
			var el := String(Data.get_dragon(int(did)).get("element", ""))
			if String(state["elem"]) != "" and el != String(state["elem"]): continue
			grid.add_child(_dex_cell(int(did), state, redraw))
		if int(state["sel"]) > 0:
			_dex_detail(detail, int(state["sel"]))
	var fx := W * 0.5 - (DEX_ELEMENTS.size() * 66.0 - 6.0) * 0.5
	for ent in DEX_ELEMENTS:
		var el := String(ent["key"])
		var holder := Control.new()
		holder.position = Vector2(fx, H - 110.0)
		holder.size = Vector2(60.0, 60.0)
		pop.content.add_child(holder)
		var eb := AtlasUI.spr("common_ui", "common_element_bg", 0.62)
		if eb: eb.position = Vector2(30.0, 30.0); holder.add_child(eb)
		var ei := AtlasUI.spr("item_small_ui", String(ent["icon"]), 0.62)
		if ei: ei.position = Vector2(30.0, 30.0); holder.add_child(ei)
		if String(state["elem"]) != el:
			holder.modulate = Color(0.62, 0.62, 0.66)
		var b := Button.new(); b.flat = true; b.size = Vector2(60.0, 60.0)
		b.pressed.connect(func():
			state["elem"] = el
			redraw.call())
		holder.add_child(b)
		fx += 66.0
	redraw.call()

func _dex_cell(did: int, state: Dictionary, redraw: Callable) -> Control:
	var awk := UserDB.dex_awakened(did)
	var sel := int(state["sel"]) == did
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(100.0, 100.0)
	var bgk := "scene_cave_dragonbg_master" if sel else "scene_cave_dragonbg_nomal"
	var bg := AtlasUI.spr("cave_ui", bgk, 1.0)
	if bg:
		bg.position = Vector2(50.0, 50.0)
		bg.scale = Vector2(100.0 / maxf(1.0, bg.texture.get_width()),
			100.0 / maxf(1.0, bg.texture.get_height()))
		cell.add_child(bg)
	var box := AtlasUI.spr("cave_ui", "scene_cave_dragon_box", 1.0)
	if box:
		box.position = Vector2(50.0, 50.0)
		box.scale = Vector2(100.0 / maxf(1.0, box.texture.get_width()),
			100.0 / maxf(1.0, box.texture.get_height()))
		cell.add_child(box)
	var tex := _portrait(did, "adult")
	if tex != null:
		var s := Sprite2D.new(); s.texture = tex; s.material = _pma
		var k: float = minf(76.0 / maxf(1.0, float(tex.get_width())),
			76.0 / maxf(1.0, float(tex.get_height())))
		s.scale = Vector2(k, k); s.position = Vector2(50.0, 50.0)
		if not awk: s.modulate = Color(0.40, 0.40, 0.46)
		cell.add_child(s)
	var b := Button.new(); b.flat = true; b.size = Vector2(100.0, 100.0)
	b.pressed.connect(func():
		state["sel"] = did
		redraw.call())
	cell.add_child(b)
	return cell

func _dex_detail(host: Control, did: int) -> void:
	var S := Design.ASSET_SCALE
	var info: Dictionary = Data.get_dragon(did)
	var pw := host.size.x
	var nl := Label.new()
	nl.text = String(info.get("name", "드래곤"))
	nl.add_theme_font_size_override("font_size", 22)
	nl.add_theme_color_override("font_color", Color(0.25, 0.15, 0.05))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.position = Vector2(0, 0); nl.size = Vector2(pw, 30.0)
	host.add_child(nl)
	var sym := _spr("e_symbol", 0.8)
	if sym:
		sym.position = Vector2(pw * 0.5, 130.0)
		sym.modulate = Color(1, 1, 1, 0.55)
		host.add_child(sym)
	var sp := _dragon_node(did, "adult", 0.55 * S)
	sp.position = Vector2(pw * 0.5, 212.0)
	host.add_child(sp)
	var aw_no := Data.awaken_skill_of(did)
	if aw_no <= 0:
		return
	var sk: Dictionary = Data.skill_awaken_for(aw_no)
	var tb_sz := Vector2(pw - 10.0, 150.0)
	var tb := AtlasUI.nine("ninepatch_ui", "9patch_text_box", tb_sz, Rect2(25, 25, 3, 3))
	if tb:
		tb.position = Vector2(5.0, host.size.y - tb_sz.y)
		host.add_child(tb)
	var ty := host.size.y - tb_sz.y
	var fr := AtlasUI.spr("common_ui", "common_skill_evolution", 0.7 * S)
	if fr: fr.position = Vector2(36.0, ty + 30.0); host.add_child(fr)
	var ico := int(sk.get("icon", 0))
	if ico > 0:
		var ip := "res://assets/converted/skill_evolution/skill_evolution_%d.tres" % ico
		if ResourceLoader.exists(ip):
			var it: Texture2D = load(ip)
			var si := Sprite2D.new(); si.texture = it; si.material = _pma
			var ik := 34.0 / maxf(1.0, float(it.get_width()))
			si.scale = Vector2(ik, ik); si.position = Vector2(36.0, ty + 30.0)
			host.add_child(si)
	var sn := Label.new()
	sn.text = String(sk.get("name", ""))
	sn.add_theme_font_size_override("font_size", 17)
	sn.add_theme_color_override("font_color", Color(0.86, 0.16, 0.12))
	sn.position = Vector2(84.0, ty + 14.0); sn.size = Vector2(pw - 100.0, 24.0)
	host.add_child(sn)
	var se := Label.new()
	se.text = String(sk.get("comment", ""))
	se.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	se.add_theme_font_size_override("font_size", 15)
	se.add_theme_color_override("font_color", Color(0.51, 0.26, 0.11))
	se.position = Vector2(84.0, ty + 40.0); se.size = Vector2(pw - 100.0, 100.0)
	host.add_child(se)

func _portrait(did: int, stage: String) -> Texture2D:
	for st in [stage, "adult", "child", "baby"]:
		var p := "res://assets/converted/portrait_%d/dragon_dragon_%d_box_%s.tres" % [did, did, st]
		if ResourceLoader.exists(p):
			return load(p)
	return Icons.dragon_egg_texture(did)

func _spine(path: String, at: Vector2, scale: float) -> Node2D:
	if not ResourceLoader.exists(path):
		return null
	var n := (load(path) as PackedScene).instantiate() as Node2D
	n.position = at
	n.scale = Vector2(scale, scale)
	add_child(n)
	var ap := n.get_node_or_null("AnimationPlayer")
	if ap and ap.has_animation("animation"):
		ap.get_animation("animation").loop_mode = Animation.LOOP_LINEAR
		ap.play("animation")
	return n

func _confirm(title: String, body: String, on_ok: Callable) -> void:
	var pop := FramedWindow.open(self, title, Vector2(560.0, 300.0))
	var l := Label.new(); l.text = body
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.30, 0.18, 0.06))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(50.0, 90.0); l.size = Vector2(460.0, 100.0)
	pop.content.add_child(l)
	pop.add_action_button("확인", func():
		pop.close()
		on_ok.call())

func _make_stone_complete_popup(star: int, key: String) -> void:
	Bgm.sfx("effect_equip_success")
	var S := Design.ASSET_SCALE
	var pop := FramedWindow.open(self, "%d성마석 제작 성공" % star, Vector2(560.0, 520.0))
	var W := pop.win_size.x
	var H := pop.win_size.y
	var cy := H * 0.5
	if pop.close_btn != null:
		pop.close_btn.visible = false
	var bl := AtlasUI.spr("common_ui", "common_backlight3", 0.7 * S)
	if bl != null:
		bl.position = Vector2(W * 0.5, cy - 105.0)
		bl.modulate.a = 0.0
		pop.content.add_child(bl)
		var tb := create_tween()
		tb.tween_interval(2.7)
		tb.tween_property(bl, "modulate:a", 1.0, 0.3)
	var ip := Data.item_icon_path(key)
	if ResourceLoader.exists(ip):
		var icon := Sprite2D.new()
		icon.texture = load(ip)
		icon.material = AtlasUI.pma()
		icon.position = Vector2(W * 0.5, cy - 10.0)
		icon.scale = Vector2(1.5 * S, 1.5 * S)
		icon.modulate.a = 0.0
		pop.content.add_child(icon)
		var ti := create_tween()
		ti.tween_interval(0.4)
		ti.tween_property(icon, "modulate:a", 1.0, 0.1)
		ti.tween_property(icon, "scale", Vector2(1.7 * S, 1.7 * S), 0.2)
		ti.tween_property(icon, "scale", Vector2(1.5 * S, 1.5 * S), 0.1)
		var tm := create_tween()
		tm.tween_interval(1.6)
		tm.tween_property(icon, "position:y", icon.position.y - 100.0, 0.5)
	var l1 := RichTextLabel.new()
	l1.bbcode_enabled = true
	l1.fit_content = true
	l1.scroll_active = false
	l1.text = "[center]%s  -  [color=#4374D9]%d개[/color][/center]" % [Data.item_name(key), 1]
	l1.add_theme_font_size_override("normal_font_size", 21)
	l1.add_theme_color_override("default_color", Color(0.30, 0.18, 0.06))
	l1.position = Vector2(50.0, cy + 68.0); l1.size = Vector2(W - 100.0, 30.0)
	l1.modulate.a = 0.0
	pop.content.add_child(l1)
	var l3 := RichTextLabel.new()
	l3.bbcode_enabled = true
	l3.fit_content = true
	l3.scroll_active = false
	l3.text = "[center]%s[/center]" % String(Data.get_item(key).get("desc", ""))
	l3.add_theme_font_size_override("normal_font_size", 16)
	l3.add_theme_color_override("default_color", Color(0.42, 0.30, 0.16))
	l3.position = Vector2(50.0, cy + 108.0); l3.size = Vector2(W - 100.0, 52.0)
	l3.modulate.a = 0.0
	pop.content.add_child(l3)
	var l2 := RichTextLabel.new()
	l2.bbcode_enabled = true
	l2.fit_content = true
	l2.scroll_active = false
	l2.text = "[center][color=#BDBDBD](보유 수량 : %d개)[/color][/center]" % UserDB.item_count(key)
	l2.add_theme_font_size_override("normal_font_size", 15)
	l2.position = Vector2(50.0, cy + 160.0); l2.size = Vector2(W - 100.0, 24.0)
	l2.modulate.a = 0.0
	pop.content.add_child(l2)
	for pair in [[l1, 2.8], [l3, 2.85], [l2, 2.85]]:
		var tl := create_tween()
		tl.tween_interval(float(pair[1]))
		tl.tween_property(pair[0], "modulate:a", 1.0, 0.3)
	var okr := Control.new()
	var oks := AtlasUI.size_pt("common_ui", "common_check_btn") * 1.5
	if oks == Vector2.ZERO:
		oks = Vector2(64.0, 64.0)
	okr.size = oks
	okr.position = Vector2(W * 0.9, H * 0.1) - oks * 0.5
	okr.visible = false
	pop.content.add_child(okr)
	var okspr := AtlasUI.spr("common_ui", "common_check_btn", 1.5 * S)
	if okspr != null:
		okspr.position = oks * 0.5
		okr.add_child(okspr)
	var okb := Button.new()
	okb.flat = true
	okb.size = oks
	okb.pressed.connect(func(): pop.close())
	okr.add_child(okb)
	var tk := create_tween()
	tk.tween_interval(2.0)
	tk.tween_callback(func(): okr.visible = true)

func _notice(title: String, body: String) -> void:
	var pop := FramedWindow.open(self, title, Vector2(560.0, 280.0))
	var l := Label.new(); l.text = body
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.30, 0.18, 0.06))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(50.0, 88.0); l.size = Vector2(460.0, 100.0)
	pop.content.add_child(l)
	pop.add_action_button("확인", func(): pop.close())
