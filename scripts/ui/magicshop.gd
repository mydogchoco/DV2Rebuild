extends Control

const DIR_UI := "magicshop_ui"
const DIR_BG := "res://assets/converted/magicshop_bg/%s"

const ITEMS := [
	[
		{"key": "drink", "label": "드링크 강화", "icon": "icon_drink", "dir": "ui", "orig": "DrinkCraftLayer"},
		{"key": "gem", "label": "젬 강화", "icon": "icon_gem", "dir": "ui", "orig": "GemCraftLayer"},
		{"key": "slot", "label": "뽑기", "icon": "icon_slot", "dir": "ui", "orig": "SlotLayer"},
		{"key": "code", "label": "카드 코드", "icon": "icon_code", "dir": "ui", "orig": "CodeLayer"},
		{"key": "trans", "label": "드래곤 소환", "icon": "icon_summon", "dir": "ui", "orig": "TransDragonLayer"},
		{"key": "alchemy_enter", "label": "연금술", "icon": "icon_alchemy", "dir": "al", "orig": "changeFloor(+1)"},
	],
	[
		{"key": "hybrid_up", "label": "혼성젬 강화", "icon": "icon_alchemy_01", "dir": "al", "orig": "AlchemyLayer"},
		{"key": "alchemy", "label": "혼성젬 제작", "icon": "icon_alchemy_02", "dir": "al", "orig": "UpgradeGemLayer(1)"},
		{"key": "disassemble", "label": "젬 분해", "icon": "icon_alchemy_04", "dir": "al", "orig": "UpgradeGemLayer(2)"},
		{"key": "potion_make", "label": "용액 제작", "icon": "icon_alchemy_03", "dir": "al", "orig": "PotionLayer(1)"},
		{"key": "potion_shop", "label": "용액 상점", "icon": "icon_alchemy_05", "dir": "al", "orig": "구판 전용(후기판 코드에 없음)"},
		{"key": "soul", "label": "소울젬 승급/강화", "icon": "", "alt_icon": "gem_soul_att9",
			"dir": "al", "orig": "UpgradeSoulGemLayer"},
	],
]
const FLOOR_COLS := [3, 3]
const DIR_AL := "magicshop_alchemy"

var _params: Dictionary = {}
var _pma: CanvasItemMaterial
var _man: Dictionary = {}
var _man_al: Dictionary = {}
var _tab := -1
var _floor := 0
var _npc: NpcPortrait
var _box: BottomTextBox
var _popup: FramedWindow
var _money_root: Control
var _dis_slots: Array = ["", "", "", "", "", ""]
var _soul_key := ""
var _hybrid_key := ""
var _alchemy_spine: Node2D = null

const ALCHEMY_SPINE := "res://scenes/worldmap_fx/magicshop_alchemist.tscn"
const ALCHEMY_SPINE_SCALE := 0.67

const RESULT_SPINE := "res://scenes/worldmap_fx/buildup_result_spine.tscn"
const RESULT_SPINE_SCALE := 0.87
const RESULT_SPINE_TIMESCALE := 1.5

const POTION_ANIM := {
	"alchemy_moderation": "resection",
	"alchemy_wisdom": "wisdom",
	"alchemy_courage": "brave",
	"alchemy_justice": "justice",
	"alchemy_glory": "glory",
	"alchemy_legend": "legend",
}
var _summon_uid := 0
var _summon_species := Summon.SPECIES_DEF
var _egg_reveal: Array = []
const SPECIES_LABEL := {Summon.SPECIES_DEF: "수비형", Summon.SPECIES_ATK: "공격형"}

func _items() -> Array:
	return ITEMS[clampi(_floor, 0, ITEMS.size() - 1)]

func enter(params: Dictionary = {}) -> void:
	Bgm.play("bg_magicshop")
	_params = params
	if _pma != null: _rebuild()

func _ready() -> void:
	_pma = CanvasItemMaterial.new(); _pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_rebuild()

func _vis() -> Vector2:
	return get_viewport_rect().size

func _load_man() -> void:
	if not _man.is_empty(): return
	var p := "res://assets/converted/%s/_manifest.json" % DIR_UI
	if FileAccess.file_exists(p):
		var d = JSON.parse_string(FileAccess.open(p, FileAccess.READ).get_as_text())
		if d is Dictionary: _man = d

func _spr(name: String, scale := 1.0, dir := "ui") -> Sprite2D:
	var tex := _tex(name, dir)
	if tex == null: return null
	var s := Sprite2D.new(); s.texture = tex; s.material = _pma
	s.scale = Vector2(scale, scale)
	return s

func _tex(name: String, dir := "ui") -> Texture2D:
	var p := "res://assets/converted/%s/scene_magicshop_%s.tres" % [DIR_UI, name] if dir == "ui" \
		else "res://assets/converted/%s/scene_magicshop_alchemy_%s.tres" % [DIR_AL, name]
	return load(p) if ResourceLoader.exists(p) else null

func _rebuild() -> void:
	for c in get_children(): c.queue_free()
	_load_man()
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var bgfile := "magicshop_bg2.jpg" if _floor == 1 else "magicshop_bg.jpg"
	var bgp := DIR_BG % bgfile
	if ResourceLoader.exists(bgp):
		var full := TextureRect.new(); full.texture = load(bgp)
		full.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		full.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		full.set_anchors_preset(Control.PRESET_FULL_RECT)
		full.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(full)
	else:
		var bg := ColorRect.new(); bg.color = Color(0.10, 0.07, 0.16)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
	var table := _spr("table", S)
	if table:
		table.centered = false
		var tw := table.texture.get_width() * S
		var th := table.texture.get_height() * S
		table.position = Vector2(vis.x - tw, vis.y - th); add_child(table)
	var ball := _spr("crystalball", S)
	if ball:
		ball.position = Vector2(vis.x - 280.0, Design.flip_y(235.0)); add_child(ball)
		_ball_particle(ball)
		var t := ball.create_tween().set_loops()
		t.tween_property(ball, "scale", Vector2(S * 1.06, S * 1.06), 1.4).set_trans(Tween.TRANS_SINE)
		t.tween_property(ball, "scale", Vector2(S, S), 1.4).set_trans(Tween.TRANS_SINE)
	_build_menu(vis)
	_build_npc(vis)
	_build_money(vis)
	_build_title(vis)

func _ball_particle(ball: Sprite2D) -> void:
	var f := FileAccess.open("res://assets/converted/particles/crystalball.json", FileAccess.READ)
	if f == null: return
	var c = JSON.parse_string(f.get_as_text())
	if typeof(c) != TYPE_DICTIONARY: return
	var p := CPUParticles2D.new()
	p.texture = _dot_tex()
	p.amount = int(c.get("amount", 60))
	p.lifetime = float(c.get("lifetime", 2.0))
	p.lifetime_randomness = float(c.get("lifetime_randomness", 0.0))
	p.direction = Vector2(float(c["direction"][0]), float(c["direction"][1]))
	p.spread = float(c.get("spread", 20.0))
	p.initial_velocity_min = maxf(0.0, float(c.get("vmin", 0.0)))
	p.initial_velocity_max = maxf(0.0, float(c.get("vmax", 10.0)))
	p.gravity = Vector2(float(c["gravity"][0]), float(c["gravity"][1]))
	p.scale_amount_min = float(c.get("scale_min", 0.2))
	p.scale_amount_max = float(c.get("scale_max", 0.5))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(float(c["emit_rect"][0]), float(c["emit_rect"][1]))
	var g := Gradient.new()
	g.set_color(0, Color(float(c["color_start"][0]), float(c["color_start"][1]),
		float(c["color_start"][2]), float(c["color_start"][3])))
	g.set_color(1, Color(float(c["color_end"][0]), float(c["color_end"][1]),
		float(c["color_end"][2]), float(c["color_end"][3])))
	p.color_ramp = g
	if bool(c.get("additive", false)):
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = m
	ball.add_child(p)

func _dot_tex() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

func _build_title(vis: Vector2) -> void:
	var t := Label.new()
	t.text = "점술집 지하" if _floor == 1 else "점술집"
	t.add_theme_font_size_override("font_size", 32)
	t.add_theme_color_override("font_color", Color(1, 0.72, 0.85))
	t.add_theme_color_override("font_outline_color", Color(0.28, 0.06, 0.2, 0.95))
	t.add_theme_constant_override("outline_size", 6)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size = Vector2(vis.x, 48)
	t.position = Vector2(0, 12)
	t.z_index = 10
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)

	var x := AtlasUI.spr("common_ui", "common_close_btn", Design.ASSET_SCALE)
	if x != null:
		x.position = Vector2(vis.x - 42, 36)
		x.z_index = 11
		add_child(x)
	var xb := Button.new()
	xb.flat = true
	xb.size = Vector2(56, 56)
	xb.position = Vector2(vis.x - 70, 8)
	xb.z_index = 11
	xb.pressed.connect(_leave)
	add_child(xb)

	if _floor > 0:
		var ba := AtlasUI.spr("common_ui", "common_back_btn", Design.ASSET_SCALE)
		if ba != null:
			ba.position = Vector2(46, 36)
			ba.z_index = 11
			add_child(ba)
		var bb := Button.new()
		bb.flat = true
		bb.size = Vector2(64, 56)
		bb.position = Vector2(14, 8)
		bb.z_index = 11
		bb.pressed.connect(func(): _set_floor(0))
		add_child(bb)

func _set_floor(f: int) -> void:
	if f == _floor or is_instance_valid(_popup):
		return
	_floor = f
	_tab = -1
	_rebuild()

func _leave() -> void:
	var from := String(_params.get("from", "town"))
	if from == "worldmap":
		Scenes.goto("worldmap", {"region": "yutakan"})
	else:
		Scenes.goto("town", {"area": _params.get("area", "elpis")})

const MENU_ROW0_TOP_COCOS := 572.0
const MENU_LEFT_FRAC := 0.158

func _build_menu(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var cw := AtlasUI.size_pt("common_ui", "common_item_bg").x
	var ch := AtlasUI.size_pt("common_ui", "common_item_bg").y
	var items := _items()
	var n := items.size()
	var cols: int = FLOOR_COLS[clampi(_floor, 0, FLOOR_COLS.size() - 1)]
	var gx := cw + 15.0 + 25.0
	var gy := ch + 15.0 + 25.0
	var x0: float = round(vis.x * MENU_LEFT_FRAC)
	var y0 := Design.flip_y(MENU_ROW0_TOP_COCOS)
	for i in n:
		var it: Dictionary = items[i]
		var col := i % cols
		var row := i / cols
		var dx := 0.0
		if n % cols != 0 and (n - n % cols) <= i:
			dx = gx * float(cols - n % cols) * 0.5
		var card := Control.new()
		card.size = Vector2(cw, ch)
		card.position = Vector2(x0 + col * gx + dx, y0 + row * gy)
		card.z_index = 2
		add_child(card)
		var frame := AtlasUI.spr("common_ui", "common_item_bg", S)
		if frame != null:
			frame.position = Vector2(cw, ch) * 0.5
			card.add_child(frame)
		var back := AtlasUI.spr("common_ui", "common_backlight3", 0.35 * S)
		if back != null:
			back.position = Vector2(cw * 0.5, ch * 0.5 + 10.0)
			card.add_child(back)
			var rt := back.create_tween().set_loops()
			rt.tween_property(back, "rotation", TAU / 6.0, 3.0).as_relative()
		var ic := _spr(String(it["icon"]), S, String(it.get("dir", "ui")))
		if ic == null and String(it.get("alt_icon", "")) != "":
			ic = AtlasUI.spr("gem_soul", String(it["alt_icon"]), S * 0.62)
		if ic != null:
			ic.position = Vector2(cw * 0.5, ch * 0.5 + 10.0)
			card.add_child(ic)
		var l := Label.new()
		l.text = String(it["label"])
		l.add_theme_font_size_override("font_size", 19)
		l.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size = Vector2(cw, 26.0)
		l.position = Vector2(0, 15.0 - 13.0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(l)
		var b := Button.new()
		b.flat = true
		b.size = Vector2(cw, ch)
		var idx := i
		b.pressed.connect(func(): _on_menu(idx))
		card.add_child(b)

func _on_menu(idx: int) -> void:
	if String((_items()[idx] as Dictionary)["key"]) == "alchemy_enter":
		_set_floor(1)
		return
	_open_feature(idx)

func _open_feature(idx: int) -> void:
	if is_instance_valid(_popup):
		return
	_tab = idx
	_popup = FramedWindow.open(self, String((_items()[idx] as Dictionary)["label"]))
	_popup.closed.connect(func():
		_tab = -1
		_say(_magic_talk()))
	_build_body(_popup)
	_say(_magic_talk())

func _refresh_feature() -> void:
	if not is_instance_valid(_popup):
		_rebuild()
		return
	_popup.clear_content()
	_build_body(_popup)
	if is_instance_valid(_money_root):
		_money_root.queue_free()
	_build_money(_vis())

func _build_npc(vis: Vector2) -> void:
	_npc = NpcPortrait.create("yulia", _pick_emotion("yulia"))
	if _npc != null:
		_npc.z_index = 5
		add_child(_npc)
		_npc.position = Vector2(vis.x - 150.0, vis.y)
	_box = BottomTextBox.new()
	_box.max_width = vis.x - 300.0
	_box.z_index = 12
	add_child(_box)
	_box.clicked.connect(func(): _say(_magic_talk()))
	_say(_magic_talk())

const NPC_EMOTIONS := [1, 2]

func _pick_emotion(npc: String) -> int:
	var nums := AtlasUI.npc_emotions_for(npc, NPC_EMOTIONS)
	return int(nums[randi() % nums.size()]) if not nums.is_empty() else 1

func _npc_kr() -> String:
	var per = Data.npc_lines_doc.get("yulia", null)
	if per is Dictionary and per.has("name"):
		return String(per["name"])
	return "유리아"

const MAGIC_TALK_KEY := {
	"gem": "magic.gem", "hybrid_up": "magic.gem",
	"alchemy": "magic.alchemy_make",
	"disassemble": "magic.disassemble",
	"potion_make": "magic.potion_make",
	"potion_shop": "magic.potion_shop",
	"drink": "magic.drink",
	"code": "magic.code",
	"slot": "magic.slot", "egg": "magic.egg",
}

func _magic_talk() -> String:
	var screen: Dictionary = Data.npc_talk.get("screen", {})
	var pool: Array = []
	if _tab >= 0:
		var key := String(MAGIC_TALK_KEY.get(String((_items()[_tab] as Dictionary)["key"]), ""))
		if key != "":
			pool = (screen.get(key, {}) as Dictionary).get("lines", [])
	if pool.is_empty():
		if _floor == 1:
			pool = (screen.get("magic.alchemy_talk", {}) as Dictionary).get("lines", [])
		else:
			pool = Data.npc_talk.get("idle", {}).get("yulia", [])
	if pool.is_empty():
		pool = (screen.get("magic.welcome", {}) as Dictionary).get("lines", [])
	return String(pool[randi() % pool.size()]) if not pool.is_empty() else ""

const REACTION_EMOTIONS := [4]

func _say(line: String, emo := 0) -> void:
	if not is_instance_valid(_box):
		return
	if is_instance_valid(_npc):
		if emo > 0:
			_npc.set_emotion(emo)
		elif REACTION_EMOTIONS.has(_npc.emotion):
			_npc.set_emotion(1)
	_box.show_text(_npc_kr(), line)
	if is_instance_valid(_npc):
		_npc.set_talking(true)
		if not _box.finished.is_connected(_stop_talk):
			_box.finished.connect(_stop_talk)

func _stop_talk() -> void:
	if is_instance_valid(_npc):
		_npc.set_talking(false)

func _body_code(pop: FramedWindow) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var back := AtlasUI.spr("common_ui", "common_backlight4", Design.ASSET_SCALE * 0.62)
	if back != null:
		back.position = Vector2(W * 0.5, 210.0)
		back.modulate = Color(1, 1, 1, 0.55)
		pop.content.add_child(back)
		back.create_tween().set_loops().tween_property(back, "rotation", TAU, 24.0).as_relative()
	var card := _spr("card", Design.ASSET_SCALE * 1.15)
	if card != null:
		card.position = Vector2(W * 0.5, 210.0)
		pop.content.add_child(card)
	var head := _note("0과 1로 재구축된 세계의 비밀은 선형대수학에 있습니다.")
	head.position = Vector2(60.0, 92.0); head.size = Vector2(W - 120.0, 26.0)
	head.custom_minimum_size = Vector2(W - 120.0, 0)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pop.content.add_child(head)
	var box := AtlasUI.nine("ninepatch_ui", "9patch_train_box3", Vector2(440.0, 52.0),
		Rect2(30, 16, 62, 8))
	if box != null:
		box.position = Vector2(W * 0.5 - 220.0, 318.0)
		pop.content.add_child(box)
	var edit := LineEdit.new()
	edit.placeholder_text = "코드"
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.max_length = 0
	edit.flat = true
	edit.add_theme_font_size_override("font_size", 22)
	edit.add_theme_color_override("font_color", Color(1, 0.97, 0.88))
	edit.add_theme_color_override("font_placeholder_color", Color(0.72, 0.66, 0.56))
	edit.size = Vector2(420.0, 44.0)
	edit.position = Vector2(W * 0.5 - 210.0, 322.0)
	pop.content.add_child(edit)
	var msg := Label.new()
	msg.add_theme_font_size_override("font_size", 17)
	msg.add_theme_color_override("font_color", Color(0.72, 0.16, 0.10))
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.size = Vector2(W - 120.0, 24.0); msg.position = Vector2(60.0, 378.0)
	pop.content.add_child(msg)
	pop.add_action_button("확인", func():
		var code := CardCode.normalize(TextField.value(edit))
		if code.is_empty():
			msg.text = "코드를 입력해 주세요."
			return
		var res := _redeem_code(code)
		if res.is_empty():
			msg.text = Data.ui("#fc0fe200")
			return
		msg.text = ""
		_toast(String(res.get("msg", "")) if String(res.get("msg", "")) != "" else "코드를 사용했습니다!")
		_reveal_eggs("코드에 응답하여 %s의 알이 나타났습니다."),
		0, Vector2(220.0, 52.0))
	TextField.no_steal(pop)
	edit.grab_focus()

func _redeem_code(code: String) -> Dictionary:
	var res := CardCode.lookup(code, Data.card_codes)
	if res.is_empty():
		return {}
	var mark := CardCode.used_key(code, Data.card_codes)
	var used: Array = UserDB.get_pmeta("used_card_codes", [])
	var uses := int(res.get("uses", 1 if bool(res.get("once", true)) else 0))
	if uses > 0:
		var spent := 0
		for m in used:
			if String(m) == mark:
				spent += 1
		if spent >= uses:
			return {}
	_egg_reveal.clear()
	for r in res.get("rewards", []):
		_grant_card_reward(r)
	if uses > 0:
		var arr: Array = (used as Array).duplicate()
		arr.append(mark)
		UserDB.set_pmeta("used_card_codes", arr)
	return res

func _grant_card_reward(r: Dictionary) -> void:
	var n := maxi(1, int(r.get("n", 1)))
	match String(r.get("t", "")):
		"item":
			UserDB.add_item(String(r.get("k", "")), n)
		"equipment":
			var rarity := clampi(int(r.get("r", 0)), 0, 5)
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			for i in n:
				var meta := {"rarity": rarity,
					"options": Equipment.roll_options(rarity, rng, Data.equipment)}
				UserDB.add_item(Equipment.item_key(String(r.get("k", "")), meta), 1)
		"gold":
			UserDB.add_currency("gold", n)
		"dia":
			UserDB.add_currency("diamond", n)
		"egg":
			var did := int(r.get("k", 0))
			var grade := maxi(0, int(r.get("g", 0)))
			UserDB.add_item(EggItem.key("egg:%d" % did, grade), n)
			for i in n:
				_egg_reveal.append({"did": did, "grade": grade, "opts": {}})
		"dragon":
			for i in n:
				UserDB.add_dragon(int(r.get("k", 0)))
		"flag":
			UserDB.set_pmeta(String(r.get("k", "")), true)

func _reveal_eggs(msg_fmt: String) -> void:
	if _egg_reveal.is_empty():
		_refresh_feature()
		return
	var e: Dictionary = _egg_reveal.pop_front()
	var did := int(e.get("did", 0))
	var opts: Dictionary = e.get("opts", {})
	var grade := maxi(0, int(e.get("grade", 0)))
	var nm := String(opts.get("name", ""))
	if nm == "":
		var mn = Data.get_dragon(did).get("name")
		nm = String(mn) if typeof(mn) == TYPE_STRING and String(mn) != "" else "새로운 알"
	var shown_name := "+%d %s" % [grade, nm] if grade > 0 else nm
	var shown_opts := opts.duplicate()
	if grade > 0:
		shown_opts["name"] = shown_name
	var pop := EggResultView.open(self, did, "", msg_fmt % shown_name, shown_opts)
	pop.closed.connect(func(): _reveal_eggs(msg_fmt))

var _drink_key := ""
var _drink_ess := ""
var _drink_cnt := 1

func _drink_candidates() -> Array:
	var out: Array = []
	for k in UserDB.inventory().keys():
		var key := String(k)
		if UserDB.item_count(key) > 0 and DrinkCraft.can_upgrade(Data.item_effects, key):
			out.append(key)
	out.sort()
	return out

func _essence_candidates() -> Array:
	var out: Array = []
	for k in UserDB.inventory().keys():
		var key := String(k)
		if UserDB.item_count(key) > 0 and DrinkCraft.is_essence(Data.get_item(key)):
			out.append(key)
	out.sort()
	return out

func _body_drink_craft(pop: FramedWindow) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var S := Design.ASSET_SCALE
	var defs := Data.item_effects
	if _drink_key != "" and (UserDB.item_count(_drink_key) <= 0
			or not DrinkCraft.can_upgrade(defs, _drink_key)):
		_drink_key = ""
		_drink_ess = ""
	if _drink_ess != "" and UserDB.item_count(_drink_ess) <= 0:
		_drink_ess = ""

	var each_ess := DrinkCraft.essence_each(defs)
	var gold_each := DrinkCraft.gold_each(defs, _drink_key) if _drink_key != "" else 0
	var max_cnt := 0
	if _drink_key != "" and _drink_ess != "":
		max_cnt = DrinkCraft.max_count(defs, _drink_key, UserDB.item_count(_drink_key),
			UserDB.item_count(_drink_ess), UserDB.gold())
	_drink_cnt = clampi(_drink_cnt, 1, maxi(1, max_cnt))
	var result_key := ""
	if _drink_key != "" and _drink_ess != "":
		result_key = DrinkCraft.result_key(defs, _drink_key, Data.get_item(_drink_ess))

	var bw := (W - 110.0) / 3.0
	var bh := ((H - 110.0) / 3.0) * 1.35
	var cy := H * 0.5 + 6.0
	var frames := ["drink_bg", "element_bg"]
	var keys := [_drink_key, _drink_ess]
	var caps := ["물약", "정기"]
	for i in 2:
		var cx := W * 0.5 - bw * 0.5 - 50.0 + (bw + 100.0) * float(i)
		var box := Panel.new()
		box.size = Vector2(bw, bh)
		box.position = Vector2(cx - bw * 0.5, cy - bh * 0.5)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.40)
		sb.corner_radius_top_left = 14; sb.corner_radius_top_right = 14
		sb.corner_radius_bottom_left = 14; sb.corner_radius_bottom_right = 14
		box.add_theme_stylebox_override("panel", sb)
		pop.content.add_child(box)
		var key := String(keys[i])
		if key == "":
			var ph := _spr(String(frames[i]), S * 1.1)
			if ph:
				ph.position = Vector2(bw * 0.5, bh * 0.5 - 6.0)
				ph.modulate = Color(1, 1, 1, 0.85)
				box.add_child(ph)
			var hint := Label.new()
			hint.text = String(caps[i])
			hint.add_theme_font_size_override("font_size", 17)
			hint.add_theme_color_override("font_color", Color(1, 0.94, 0.80))
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hint.size = Vector2(bw, 24.0)
			hint.position = Vector2(0, bh * 0.5 - 6.0)
			hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(hint)
		else:
			var ip := Data.item_icon_path(key)
			if ip != "" and ResourceLoader.exists(ip):
				var ic := Sprite2D.new()
				ic.texture = load(ip); ic.material = AtlasUI.pma()
				ic.position = Vector2(bw * 0.5, bh * 0.5 - 10.0)
				ic.scale = Vector2(0.62, 0.62)
				box.add_child(ic)
			var nl := Label.new()
			nl.text = Data.item_name(key)
			nl.add_theme_font_size_override("font_size", 16)
			nl.add_theme_color_override("font_color", Color(1, 0.96, 0.86))
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			nl.size = Vector2(bw - 8.0, 40.0)
			nl.position = Vector2(4.0, 8.0)
			nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(nl)
		var b := Button.new()
		b.flat = true
		b.size = Vector2(bw, bh)
		if i == 0:
			b.pressed.connect(func(): _open_item_picker("물약", _drink_candidates(),
				func(k: String):
					_drink_key = k
					_drink_ess = ""
					_drink_cnt = 1
					_refresh_feature()))
		else:
			b.pressed.connect(func(): _open_item_picker("정기", _essence_candidates(),
				func(k: String):
					_drink_ess = k
					_drink_cnt = 1
					_refresh_feature()))
		box.add_child(b)

	var plus := AtlasUI.spr("common_ui", "common_plus", S * 1.1)
	if plus:
		plus.position = Vector2(W * 0.5, cy)
		pop.content.add_child(plus)

	var qx := W * 0.5 - bw * 0.5 - 50.0
	var qy := cy + bh * 0.5 - 35.0
	var qpanel := Panel.new()
	qpanel.size = Vector2(80.0, 44.0)
	qpanel.position = Vector2(qx - 40.0, qy - 22.0)
	var qsb := StyleBoxFlat.new()
	qsb.bg_color = Color(0, 0, 0, 0.55)
	qsb.corner_radius_top_left = 10; qsb.corner_radius_top_right = 10
	qsb.corner_radius_bottom_left = 10; qsb.corner_radius_bottom_right = 10
	qpanel.add_theme_stylebox_override("panel", qsb)
	pop.content.add_child(qpanel)
	var qlbl := Label.new()
	qlbl.text = str(_drink_cnt if max_cnt > 0 else 0)
	qlbl.add_theme_font_size_override("font_size", 24)
	qlbl.add_theme_color_override("font_color", Color(1, 1, 1))
	qlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qlbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	qlbl.size = qpanel.size
	qlbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	qpanel.add_child(qlbl)
	var mc := max_cnt
	_pick_arrow(pop.content, "common_btn_arrow1", Vector2(qx - 60.0, qy),
		func(): _drink_set_cnt(DrinkCraft.cycle_count(_drink_cnt, -1, mc)))
	_pick_arrow(pop.content, "common_btn_arrow2", Vector2(qx + 60.0, qy),
		func(): _drink_set_cnt(DrinkCraft.cycle_count(_drink_cnt, 1, mc)))

	var need_ess := each_ess * (_drink_cnt if max_cnt > 0 else 1)
	var ex := W * 0.5 - bw * 0.5 - 50.0 + (bw + 100.0)
	var el := Label.new()
	el.text = "x%d" % need_ess
	el.add_theme_font_size_override("font_size", 22)
	el.add_theme_color_override("font_color", Color(1, 1, 1) if _drink_ess != ""
		and UserDB.item_count(_drink_ess) >= need_ess else Color(1.0, 0.52, 0.44))
	el.add_theme_color_override("font_outline_color", Color(0.16, 0.09, 0.03))
	el.add_theme_constant_override("outline_size", 5)
	el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	el.size = Vector2(bw, 28.0)
	el.position = Vector2(ex - bw * 0.5, qy - 14.0)
	pop.content.add_child(el)

	var head := _note("물약에 정기를 넣어 다음 단계로 올립니다."
		+ "\n물약은 1→2→3단계로 오르고, 단계마다 효과가 5%p 씩 커집니다.")
	head.position = Vector2(60.0, 92.0); head.size = Vector2(W - 120.0, 48.0)
	head.custom_minimum_size = Vector2(W - 120.0, 0)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pop.content.add_child(head)

	var rl := Label.new()
	if result_key != "":
		rl.text = "→  %s  ×%d" % [Data.item_name(result_key), maxi(1, _drink_cnt)]
		rl.add_theme_color_override("font_color", Color(1, 0.95, 0.75))
	elif _drink_key == "":
		rl.text = "강화할 물약을 고르세요."
		rl.add_theme_color_override("font_color", Color(0.62, 0.58, 0.52))
	elif _drink_ess == "":
		rl.text = "넣을 정기를 고르세요."
		rl.add_theme_color_override("font_color", Color(0.62, 0.58, 0.52))
	else:
		rl.text = "이 정기로는 만들 수 없습니다."
		rl.add_theme_color_override("font_color", Color(1.0, 0.52, 0.44))
	rl.add_theme_font_size_override("font_size", 20)
	rl.add_theme_color_override("font_outline_color", Color(0.16, 0.09, 0.03))
	rl.add_theme_constant_override("outline_size", 5)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.size = Vector2(W, 28.0)
	rl.position = Vector2(0, H - 132.0)
	pop.content.add_child(rl)

	var total := gold_each * maxi(1, _drink_cnt)
	var can := result_key != "" and max_cnt > 0 and UserDB.gold() >= total
	var btn := _frame_button(pop.content, ("  " + _comma(total)) if can else "강화",
		Vector2(W * 0.5 - 135.0, H - 88.0), Vector2(270.0, 56.0), _run_drink_craft, 0, not can)
	if can:
		var coin := AtlasUI.spr("common_ui", "common_coin_small1", S * 0.9)
		if coin:
			coin.position = Vector2(40.0, 28.0)
			btn.add_child(coin)

func _drink_set_cnt(n: int) -> void:
	_drink_cnt = maxi(1, n)
	_refresh_feature()

func _run_drink_craft() -> void:
	var defs := Data.item_effects
	if _drink_key == "" or _drink_ess == "":
		_toast("물약과 정기를 모두 고르세요."); return
	var result_key := DrinkCraft.result_key(defs, _drink_key, Data.get_item(_drink_ess))
	if result_key == "":
		_toast("이 정기로는 만들 수 없습니다."); return
	var n := clampi(_drink_cnt, 1, DrinkCraft.max_count(defs, _drink_key,
		UserDB.item_count(_drink_key), UserDB.item_count(_drink_ess), UserDB.gold()))
	if n <= 0:
		_toast("재료가 모자라요."); return
	var gold := DrinkCraft.gold_each(defs, _drink_key) * n
	if not UserDB.spend("gold", gold):
		_toast("골드가 부족하네요"); return
	UserDB.use_item(_drink_key, n)
	UserDB.use_item(_drink_ess, DrinkCraft.essence_each(defs) * n)
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var res := DrinkCraft.roll(defs, n, rng)
	var ok_n := int(res["ok_n"])
	if ok_n > 0:
		UserDB.add_item(result_key, ok_n)
	if int(res["fail_n"]) == 0:
		_toast(Data.ui("#04c9baea"))
		ItemRewardView.open(self, [{"key": result_key, "count": ok_n}])
	elif ok_n == 0:
		_toast(Data.ui("#b1cdc514"), 4)
	else:
		_toast("%d개 성공, %d개 실패했습니다." % [ok_n, int(res["fail_n"])], 4)
		ItemRewardView.open(self, [{"key": result_key, "count": ok_n}])
	_drink_cnt = 1
	_refresh_feature()

func _build_money(vis: Vector2) -> void:
	var sz := AtlasUI.size_pt("common_ui", "common_money_bg")
	var root := Control.new()
	_money_root = root
	root.size = sz
	root.position = Vector2(vis.x - 5.0 - sz.x, 8.0)
	root.z_index = 8
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var bg := AtlasUI.spr("common_ui", "common_money_bg", Design.ASSET_SCALE)
	if bg != null:
		bg.position = sz * 0.5
		root.add_child(bg)
	for r in [["common_coin_small1", AtlasUI.comma(UserDB.gold()), 85.0],
			["common_diamond_small1", AtlasUI.comma(UserDB.diamond()), 45.0]]:
		var ic := AtlasUI.spr("common_ui", String(r[0]), Design.ASSET_SCALE)
		if ic != null:
			ic.position = Vector2(40.0, sz.y - float(r[2]))
			root.add_child(ic)
		var l := Label.new()
		l.text = String(r[1])
		l.add_theme_font_size_override("font_size", 19)
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		l.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0.04))
		l.add_theme_constant_override("outline_size", 5)
		l.position = Vector2(62.0, sz.y - float(r[2]) - 13.0)
		l.size = Vector2(sz.x - 70.0, 26.0)
		root.add_child(l)

func _body_panel(pop: FramedWindow) -> VBoxContainer:
	var pw: float = pop.win_size.x - 80.0
	var ph: float = pop.win_size.y - 86.0 - 40.0
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40.0, 86.0); scroll.size = Vector2(pw, ph)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pop.content.add_child(scroll)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size = Vector2(pw - 20, 0); scroll.add_child(col)
	return col

func _row_bg(w: float, h: float) -> NinePatchRect:
	var np := NinePatchRect.new()
	var p := "res://assets/converted/%s/scene_magicshop_list_bg.tres" % DIR_UI
	if not ResourceLoader.exists(p):
		p = "res://assets/converted/common_ui/common_item_bg.tres"
	if not ResourceLoader.exists(p): return null
	np.texture = load(p)
	np.patch_margin_left = 24; np.patch_margin_right = 24
	np.patch_margin_top = 20; np.patch_margin_bottom = 20
	np.size = Vector2(w, h); np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return np

func _build_body(pop: FramedWindow) -> void:
	var items := _items()
	if _tab < 0 or _tab >= items.size():
		return
	match String((items[_tab] as Dictionary)["key"]):
		"gem": _body_gem(pop)
		"hybrid_up": _body_hybrid_upgrade(pop)
		"alchemy": _body_alchemy(pop)
		"potion_make": _body_drink(pop)
		"drink": _body_drink_craft(pop)
		"potion_shop": _body_potion_shop(pop)
		"disassemble": _body_disassemble(pop)
		"soul": _body_soul(pop)
		"egg": _body_egg(pop)
		"slot": _body_slot(pop)
		"trans": _body_trans(pop)
		"code": _body_code(pop)

const POWDERS := {"hp_powder": "노란 마법가루", "att_powder": "붉은 마법가루", "def_powder": "푸른 마법가루"}
const ALCHEMY_COST := 20

const ALCHEMY_GOLD := 1000

func _body_alchemy(pop: FramedWindow) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var have_all := true
	var y0 := 108.0
	var n := 0
	for k: String in POWDERS:
		var have := UserDB.item_count(k)
		var enough := have >= ALCHEMY_COST
		have_all = have_all and enough
		var row := Panel.new()
		row.size = Vector2(280.0, 90.0)
		row.position = Vector2(56.0, y0 + n * 100.0)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.40)
		sb.corner_radius_top_left = 14; sb.corner_radius_top_right = 14
		sb.corner_radius_bottom_left = 14; sb.corner_radius_bottom_right = 14
		row.add_theme_stylebox_override("panel", sb)
		pop.content.add_child(row)
		var ip := Data.item_icon_path(k)
		if ip != "" and ResourceLoader.exists(ip):
			var ic := Sprite2D.new()
			ic.texture = load(ip); ic.material = AtlasUI.pma()
			ic.position = Vector2(50.0, 45.0); ic.scale = Vector2(0.52, 0.52)
			row.add_child(ic)
		var l := Label.new()
		l.text = String(POWDERS[k])
		l.add_theme_font_size_override("font_size", 19)
		l.add_theme_color_override("font_color", Color(1, 0.96, 0.86))
		l.position = Vector2(96.0, 16.0); l.size = Vector2(170.0, 26.0)
		row.add_child(l)
		var c := Label.new()
		c.text = "%s / %d" % [AtlasUI.comma(have), ALCHEMY_COST]
		c.add_theme_font_size_override("font_size", 21)
		c.add_theme_color_override("font_color", Color(0.62, 1.0, 0.66) if enough else Color(1.0, 0.46, 0.40))
		c.position = Vector2(96.0, 48.0); c.size = Vector2(170.0, 28.0)
		row.add_child(c)
		n += 1
	var plus := AtlasUI.spr("common_ui", "common_plus", Design.ASSET_SCALE * 1.2)
	if plus != null:
		plus.position = Vector2(376.0, y0 + 145.0)
		pop.content.add_child(plus)
	var rib := Label.new()
	rib.text = "샌즈의 젬 확률  %d%%" % Gem.sands_chance(Data.gems, _sands_bonus_pct())
	rib.add_theme_font_size_override("font_size", 18)
	rib.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	rib.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rib.position = Vector2(435.0, y0); rib.size = Vector2(180.0, 26.0)
	pop.content.add_child(rib)
	_alchemy_sands_slot(pop, y0)
	var box := Panel.new()
	box.size = Vector2(180.0, 210.0)
	box.position = Vector2(435.0, y0 + 40.0)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0, 0, 0, 0.28)
	bs.corner_radius_top_left = 14; bs.corner_radius_top_right = 14
	bs.corner_radius_bottom_left = 14; bs.corner_radius_bottom_right = 14
	box.add_theme_stylebox_override("panel", bs)
	pop.content.add_child(box)
	var bl := Label.new()
	bl.text = "혼성젬\n(무작위)"
	bl.add_theme_font_size_override("font_size", 20)
	bl.add_theme_color_override("font_color", Color(1, 0.96, 0.86))
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bl.size = box.size
	box.add_child(bl)
	var coin := AtlasUI.spr("common_ui", "common_coin_small1", Design.ASSET_SCALE)
	if coin != null:
		coin.position = Vector2(466.0, H - 52.0)
		pop.content.add_child(coin)
	var gl := Label.new()
	gl.text = AtlasUI.comma(ALCHEMY_GOLD)
	gl.add_theme_font_size_override("font_size", 21)
	gl.add_theme_color_override("font_color", Color(1, 1, 1) if UserDB.gold() >= ALCHEMY_GOLD
		else Color(1.0, 0.46, 0.40))
	gl.add_theme_color_override("font_outline_color", Color(0.16, 0.09, 0.03))
	gl.add_theme_constant_override("outline_size", 5)
	gl.position = Vector2(486.0, H - 66.0); gl.size = Vector2(140.0, 28.0)
	pop.content.add_child(gl)
	pop.add_action_button("제작", _craft_hybrid_gem, 0, Vector2(180.0, 50.0),
		Vector2(W * 0.5 + 170.0, H - 52.0))
	if not have_all:
		var w2 := _note("마법가루는 젬 분해·탐험 보상으로 모읍니다.")
		w2.position = Vector2(56.0, H - 52.0); w2.size = Vector2(380.0, 24.0)
		pop.content.add_child(w2)

var _sands_key := ""

func _sands_bonus_pct() -> int:
	if _sands_key == "" or UserDB.item_count(_sands_key) <= 0:
		return 0
	return Gem.sands_bonus(_sands_key, Data.gems)

func _alchemy_sands_slot(pop: FramedWindow, y0: float) -> void:
	var tears: Array = (Data.gems.get("craft", {}) as Dictionary).get("sands_tear_items", [])
	if tears.is_empty():
		return
	var slot := Control.new()
	slot.position = Vector2(635.0, y0 + 40.0)
	slot.size = Vector2(150.0, 160.0)
	pop.content.add_child(slot)
	var band := AtlasUI.nine("ninepatch_ui", "9patch_train_box3", Vector2(150.0, 34.0))
	if band:
		band.position = Vector2(0, -40.0)
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(band)
	var bl := Label.new()
	bl.text = "샌즈의 눈물"
	bl.add_theme_font_size_override("font_size", 17)
	bl.add_theme_color_override("font_color", Color(1, 0.96, 0.86))
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.position = Vector2(0, -36.0); bl.size = Vector2(150.0, 26.0)
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(bl)
	var pbg := AtlasUI.spr("magicshop_alchemy", "scene_magicshop_alchemy_posion_bg",
		Design.ASSET_SCALE * 0.9)
	if pbg:
		pbg.position = Vector2(75.0, 62.0)
		slot.add_child(pbg)
	var cur := _sands_bonus_pct()
	if _sands_key != "" and cur > 0:
		var ip := Data.item_icon_path(_sands_key)
		if ip != "" and ResourceLoader.exists(ip):
			var ic := Sprite2D.new()
			ic.texture = load(ip); ic.material = AtlasUI.pma()
			ic.position = Vector2(75.0, 58.0); ic.scale = Vector2(0.5, 0.5)
			slot.add_child(ic)
	var sl := Label.new()
	sl.text = ("+%d%%  (%d개)" % [cur, UserDB.item_count(_sands_key)]) if cur > 0 else "넣지 않음"
	sl.add_theme_font_size_override("font_size", 16)
	sl.add_theme_color_override("font_color", Color(1, 0.96, 0.86) if cur > 0
		else Color(0.85, 0.80, 0.72))
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.position = Vector2(0, 120.0); sl.size = Vector2(150.0, 24.0)
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(sl)
	var b := Button.new()
	b.flat = true
	b.size = Vector2(150.0, 148.0)
	b.tooltip_text = "혼성젬 제작에 넣으면 샌즈의 젬이 나올 확률이 오릅니다 (클릭해서 바꾸기)"
	b.pressed.connect(_cycle_sands)
	slot.add_child(b)

func _cycle_sands() -> void:
	var tears: Array = (Data.gems.get("craft", {}) as Dictionary).get("sands_tear_items", [])
	var owned: Array = []
	for t in tears:
		var k := String((t as Dictionary).get("item", ""))
		if UserDB.item_count(k) > 0:
			owned.append(k)
	if owned.is_empty():
		_toast("샌즈의 눈물이 없습니다 (용액 상점에서 살 수 있어요)")
		return
	var i := owned.find(_sands_key)
	_sands_key = "" if i == owned.size() - 1 else String(owned[i + 1] if i >= 0 else owned[0])
	_refresh_feature()

func _craft_hybrid_gem() -> void:
	for k: String in POWDERS:
		if UserDB.item_count(k) < ALCHEMY_COST:
			_toast("마법가루가 모자라요."); return
	var bonus := _sands_bonus_pct()
	if not UserDB.spend("gold", ALCHEMY_GOLD):
		_toast("골드가 부족합니다"); return
	for k: String in POWDERS:
		UserDB.use_item(k, ALCHEMY_COST)
	if bonus > 0:
		UserDB.use_item(_sands_key, 1)
	var r := RandomNumberGenerator.new(); r.randomize()
	var got := Gem.craft_hybrid(Data.gems, bonus, r)
	if got == "":
		_toast("젬 데이터가 비어 있습니다"); return
	UserDB.add_item(Gem.item_key(got, 0), 1)
	if bonus > 0 and UserDB.item_count(_sands_key) <= 0:
		_sands_key = ""
	_toast("%s 을(를) 제작했습니다! (가방 젬 탭)" % got)
	_refresh_feature()

var _gem_key := ""
var _gem_fodder := ""

func _body_gem(pop: FramedWindow) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var S := Design.ASSET_SCALE
	var target := _ref_inst(_gem_key)
	if target.is_empty():
		_gem_key = ""
		_gem_fodder = ""
	var fodder := _ref_inst(_gem_fodder)
	if fodder.is_empty():
		_gem_fodder = ""

	var cy := 236.0
	var hex := AtlasUI.size_pt("magicshop_ui", "scene_magicshop_gem_bg") * 0.9
	var xs := [W * 0.5 - 165.0, W * 0.5 + 165.0]
	var caps := ["강화할 젬", "재료 젬"]
	var insts := [target, fodder]
	var modes := ["normal", "fodder"]
	var refs := [_gem_key, _gem_fodder]
	for i in 2:
		var cx := float(xs[i])
		var slot := Control.new()
		slot.size = hex
		slot.position = Vector2(cx, cy) - hex * 0.5
		pop.content.add_child(slot)
		var bg := _spr("gem_bg", S * 0.9)
		if bg:
			bg.position = hex * 0.5
			slot.add_child(bg)
		var inst: Dictionary = insts[i]
		if inst.is_empty():
			var hint := Label.new()
			hint.text = "젬"
			hint.add_theme_font_size_override("font_size", 20)
			hint.add_theme_color_override("font_color", Color(0.42, 0.30, 0.18))
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			hint.size = hex
			hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(hint)
		else:
			var gi := Icons.gem_rect(
				String(Gem.gem_def(String(inst["name"]), Data.gems).get("code", "")),
				int(inst["tier"]), hex.x * 0.62)
			if gi:
				gi.position = (hex - gi.size) * 0.5
				slot.add_child(gi)
			if Gem.is_broken(inst):
				var fx := _spr("gem_fail", S * 0.6)
				if fx:
					fx.position = hex * 0.5
					slot.add_child(fx)
		var sb := Button.new()
		sb.flat = true
		sb.size = hex
		var mi := String(modes[i])
		sb.pressed.connect(func(): _open_gem_picker(mi, func(k: String):
			if mi == "normal":
				_gem_key = k
				_gem_fodder = ""
			else:
				_gem_fodder = k
			_refresh_feature()))
		slot.add_child(sb)
		var cl := Label.new()
		cl.text = String(caps[i])
		cl.add_theme_font_size_override("font_size", 18)
		cl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.size = Vector2(240.0, 24.0)
		cl.position = Vector2(cx - 120.0, cy - hex.y * 0.5 - 30.0)
		pop.content.add_child(cl)
		var nl := Label.new()
		if inst.is_empty():
			nl.text = "칸을 눌러 고르세요"
		else:
			nl.text = Gem.display_name(String(inst["name"]), int(inst["tier"]), Data.gems)
			if Gem.is_broken(inst):
				nl.text += "  (파손)"
			var wh := _ref_where(String(refs[i]))
			if wh != "":
				nl.text += "\n[%s]" % wh
		nl.add_theme_font_size_override("font_size", 17)
		nl.add_theme_color_override("font_color", Color(1, 0.96, 0.82))
		nl.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.02))
		nl.add_theme_constant_override("outline_size", 5)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.size = Vector2(260.0, 46.0)
		nl.position = Vector2(cx - 130.0, cy + hex.y * 0.5 + 6.0)
		pop.content.add_child(nl)

	var plus := AtlasUI.spr("common_ui", "common_plus", S)
	if plus:
		plus.position = Vector2(W * 0.5, cy)
		pop.content.add_child(plus)

	var head := _note("일반 젬(체력·공격·방어)을 재료 젬과 함께 넣어 강화합니다."
		+ "\n재료 젬의 등급이 높을수록 성공률이 오릅니다. 실패하면 파손되고 다이아로 복구합니다.")
	head.position = Vector2(60.0, 92.0); head.size = Vector2(W - 120.0, 48.0)
	head.custom_minimum_size = Vector2(W - 120.0, 0)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pop.content.add_child(head)

	if not target.is_empty() and Gem.is_broken(target):
		var dia := Gem.repair_cost(int(target["tier"]), Data.gems)
		var rb := _frame_button(pop.content, "   복구  %d" % dia,
			Vector2(W * 0.5 - 102.0, H - 88.0), Vector2(205.0, 56.0),
			func(): _repair_bag_gem(_gem_key, dia), 1, UserDB.diamond() < dia)
		var ri := _spr("btn_gemrepair", S * 0.42)
		if ri:
			ri.position = Vector2(30.0, 28.0)
			rb.add_child(ri)
		return

	var ready := not target.is_empty() and not fodder.is_empty()
	var gold := Gem.normal_upgrade_gold(int(target.get("tier", 0)), Data.gems) if ready else 0
	var pct := Gem.normal_success_pct(int(target.get("tier", 0)), int(fodder.get("tier", 0)),
		Data.gems) if ready else 0
	var rate := Label.new()
	rate.text = ("성공률  %d%%" % pct) if ready else "성공률  —"
	rate.add_theme_font_size_override("font_size", 22)
	rate.add_theme_color_override("font_color",
		Color(1, 0.95, 0.75) if ready else Color(0.62, 0.58, 0.52))
	rate.add_theme_color_override("font_outline_color", Color(0.16, 0.09, 0.03))
	rate.add_theme_constant_override("outline_size", 5)
	rate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rate.size = Vector2(W, 30.0)
	rate.position = Vector2(0, H - 132.0)
	pop.content.add_child(rate)

	var can := ready and UserDB.gold() >= gold
	var btn := _frame_button(pop.content, ("  " + _comma(gold)) if ready else "강화",
		Vector2(W * 0.5 - 135.0, H - 88.0), Vector2(270.0, 56.0), _gem_upgrade, 0, not can)
	if ready:
		var coin := AtlasUI.spr("common_ui", "common_coin_small1", S * 0.9)
		if coin:
			coin.position = Vector2(40.0, 28.0)
			btn.add_child(coin)

func _gem_upgrade() -> void:
	var target := _ref_inst(_gem_key)
	var fodder := _ref_inst(_gem_fodder)
	if target.is_empty() or fodder.is_empty():
		_toast("강화할 젬과 재료 젬을 모두 고르세요.")
		return
	if Gem.is_broken(target):
		_toast("파손된 젬입니다 — 먼저 복구하세요."); return
	var gold := Gem.normal_upgrade_gold(int(target["tier"]), Data.gems)
	if UserDB.gold() < gold:
		_toast("골드가 부족하네요"); return
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var res: Dictionary = Gem.roll_normal_upgrade(target, int(fodder["tier"]), Data.gems, rng)
	if res.is_empty():
		_toast("이미 최대 등급입니다"); return
	if not UserDB.spend("gold", gold):
		return
	_ref_remove(_gem_fodder)
	_gem_fodder = ""
	var before := _gem_result_line(target)
	var after_inst: Dictionary = res["inst"]
	_retarget(_gem_key, _ref_write(_gem_key, after_inst))
	var ok := bool(res.get("ok", false))
	if ok:
		_toast(Data.ui("#04c9baea"))
	else:
		_toast("아쉽게 실패했네요. 다음을 기약하죠. (성공률 %d%% — 파손)"
			% int(res.get("chance_pct", 0)), 4)
	_show_upgrade_result(ok, before, _gem_result_line(after_inst), after_inst,
		"" if ok else _gem_key)
	_refresh_feature()

func _body_w(pop: FramedWindow) -> float:
	return pop.win_size.x - 80.0 - 20.0

func _gem_result_line(e) -> String:
	if e == null:
		return ""
	var d: Dictionary = e
	var nm := String(d["name"])
	var tier := int(d["tier"])
	return "%s  %s" % [Gem.display_name(nm, tier, Data.gems),
		Gem.effect_text(nm, tier, Data.gems)]

func _show_upgrade_result(ok: bool, before: String, after: String, entry,
		broken_key := "") -> void:
	var vis := _vis()
	var lay := Control.new()
	lay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lay.mouse_filter = Control.MOUSE_FILTER_STOP
	lay.z_index = 80
	add_child(lay)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lay.add_child(bg)
	var cx := vis.x * 0.5
	var anim := "success_type" if ok else "failed_type"
	if ResourceLoader.exists(RESULT_SPINE):
		var sp := (load(RESULT_SPINE) as PackedScene).instantiate() as Node2D
		if sp != null:
			sp.position = Vector2(cx, vis.y * 0.5)
			sp.scale = Vector2(RESULT_SPINE_SCALE, RESULT_SPINE_SCALE)
			sp.visible = false
			lay.add_child(sp)
			var ap := sp.get_node_or_null("AnimationPlayer") as AnimationPlayer
			get_tree().create_timer(0.2).timeout.connect(func():
				if not is_instance_valid(sp):
					return
				sp.visible = true
				Bgm.sfx("effect_equip_success" if ok else "effect_equip_failed")
				if ap != null and ap.has_animation(anim):
					ap.get_animation(anim).loop_mode = Animation.LOOP_NONE
					ap.speed_scale = RESULT_SPINE_TIMESCALE
					ap.play(anim))
	if entry != null:
		var e: Dictionary = entry
		var gi := Icons.gem_rect(
			String(Gem.gem_def(String(e["name"]), Data.gems).get("code", "")), int(e["tier"]), 84.0)
		if gi != null:
			gi.position = Vector2(cx - 42.0, vis.y * 0.5 - 42.0)
			lay.add_child(gi)
	var pw := 300.0
	var y := vis.y - 130.0
	var xs := [cx - pw - 30.0, cx + 30.0]
	var txt := [before, after]
	for i in 2:
		if String(txt[i]) == "":
			continue
		var pill := AtlasUI.nine("ninepatch_ui", "9patch_chat_black", Vector2(pw, 44.0), Rect2(9, 9, 9, 9))
		if pill != null:
			pill.position = Vector2(float(xs[i]), y)
			lay.add_child(pill)
		var l := Label.new()
		l.text = String(txt[i])
		l.add_theme_font_size_override("font_size", 17)
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.clip_text = true
		l.position = Vector2(float(xs[i]), y); l.size = Vector2(pw, 44.0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lay.add_child(l)
	if before != "" and after != "":
		var ar := AtlasUI.spr("common_ui", "common_btn_arrow2", Design.ASSET_SCALE)
		if ar != null:
			ar.position = Vector2(cx, y + 22.0)
			lay.add_child(ar)
	var hit := Button.new()
	hit.flat = true
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lay.add_child(hit)

	var chose := [false]
	if broken_key != "":
		var rb := Button.new()
		rb.flat = true
		rb.size = Vector2(96.0, 96.0)
		rb.position = Vector2(vis.x - 130.0, vis.y - 150.0)
		lay.add_child(rb)
		var ri := AtlasUI.spr("magicshop_ui", "scene_magicshop_btn_gemrepair", Design.ASSET_SCALE)
		if ri != null:
			ri.position = Vector2(48.0, 40.0)
			rb.add_child(ri)
		var rl := Label.new()
		rl.text = "복구"
		rl.add_theme_font_size_override("font_size", 17)
		rl.add_theme_color_override("font_color", Color(1, 1, 1))
		rl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		rl.add_theme_constant_override("outline_size", 4)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rl.position = Vector2(0, 76.0); rl.size = Vector2(96.0, 22.0)
		rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rb.add_child(rl)
		rb.pressed.connect(func():
			chose[0] = true
			lay.queue_free()
			_offer_repair(broken_key, before))
	hit.pressed.connect(func():
		lay.queue_free()
		if broken_key != "" and not chose[0]:
			_destroy_broken_gem(broken_key))

func _body_hybrid_upgrade(pop: FramedWindow) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var inst := _ref_inst(_hybrid_key)
	if inst.is_empty():
		_hybrid_key = ""
	var has := not inst.is_empty()
	var slot_cx := 210.0
	var panel := Control.new()
	panel.size = Vector2(300.0, 268.0)
	panel.position = Vector2(slot_cx - 150.0, 128.0)
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pop.content.add_child(panel)
	var pbg := AtlasUI.spr("magicshop_alchemy", "scene_magicshop_alchemy_box_bg",
		Design.ASSET_SCALE * 0.70)
	if pbg != null:
		pbg.position = panel.size * 0.5
		panel.add_child(pbg)
	_alchemy_spine = null
	if ResourceLoader.exists(ALCHEMY_SPINE):
		var sp := (load(ALCHEMY_SPINE) as PackedScene).instantiate() as Node2D
		if sp != null:
			var k := Design.ASSET_SCALE * 0.70 * ALCHEMY_SPINE_SCALE
			sp.scale = Vector2(k, k)
			sp.position = Vector2(panel.size.x * 0.5, panel.size.y)
			panel.add_child(sp)
			_alchemy_spine = sp
			_alchemy_play("normal")
	var slot_sz := AtlasUI.size_pt("magicshop_alchemy",
		"scene_magicshop_alchemy_alchemy_gem_slot") * 0.8
	var cap := Label.new()
	cap.text = Data.ui("#07ce6070")
	cap.add_theme_font_size_override("font_size", 19)
	cap.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.size = Vector2(190.0, slot_sz.y)
	cap.position = Vector2(slot_cx - 150.0, 94.0)
	pop.content.add_child(cap)
	var gslot := AtlasUI.spr("magicshop_alchemy", "scene_magicshop_alchemy_alchemy_gem_slot",
		Design.ASSET_SCALE * 0.8)
	var gs_c := Vector2(slot_cx - 150.0 + 190.0 + 12.0 + slot_sz.x * 0.5, 94.0 + slot_sz.y * 0.5)
	if gslot != null:
		gslot.position = gs_c
		pop.content.add_child(gslot)
	if has:
		var e: Dictionary = inst
		var si := Icons.gem_rect(
			String(Gem.gem_def(String(e["name"]), Data.gems).get("code", "")), int(e["tier"]),
			slot_sz.x * 0.72)
		if si != null:
			si.position = gs_c - si.size * 0.5
			pop.content.add_child(si)
		var nl := Label.new()
		nl.text = Gem.display_name(String(e["name"]), int(e["tier"]), Data.gems)
		if Gem.is_broken(e):
			nl.text += "  (파손)"
		var wl := _ref_where(_hybrid_key)
		if wl != "":
			nl.text += "  [%s]" % wl
		nl.add_theme_font_size_override("font_size", 19)
		nl.add_theme_color_override("font_color",
			Color(1.0, 0.62, 0.55) if Gem.is_broken(e) else Color(1, 0.96, 0.82))
		nl.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.02))
		nl.add_theme_constant_override("outline_size", 5)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.size = Vector2(300.0, 26.0); nl.position = Vector2(slot_cx - 150.0, 402.0)
		pop.content.add_child(nl)
	else:
		var nl2 := Label.new()
		nl2.text = "[혼성젬 선택] 으로\n강화할 젬을 고르세요."
		nl2.add_theme_font_size_override("font_size", 17)
		nl2.add_theme_color_override("font_color", Color(1, 0.94, 0.80))
		nl2.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.02))
		nl2.add_theme_constant_override("outline_size", 5)
		nl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl2.size = Vector2(300.0, 56.0); nl2.position = Vector2(slot_cx - 150.0, 398.0)
		pop.content.add_child(nl2)
	var lx := 380.0
	var lw := W - lx - 40.0
	var list := ScrollContainer.new()
	list.position = Vector2(lx, 88.0)
	list.size = Vector2(lw, 196.0)
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.clip_contents = true
	list.follow_focus = false
	pop.content.add_child(list)
	list.ready.connect(func(): list.scroll_vertical = 0)
	var holder := Control.new()
	list.add_child(holder)
	var owned: Array = []
	for p0 in (Data.gems.get("upgrade", {}) as Dictionary).get("potions", []):
		var p: Dictionary = p0
		var ik := String(POTION_ITEM.get(String(p.get("name", "")), ""))
		if ik != "" and UserDB.item_count(ik) > 0:
			owned.append(p)
	holder.custom_minimum_size = Vector2(lw - 16.0, maxf(1.0, owned.size() * 70.0))
	for i in owned.size():
		var p: Dictionary = owned[i]
		var nm := String(p.get("name", ""))
		var ik := String(POTION_ITEM[nm])
		var row := Control.new()
		row.size = Vector2(lw - 16.0, 62.0)
		row.position = Vector2(0, i * 70.0)
		holder.add_child(row)
		var bgn := AtlasUI.nine("magicshop_ui", "scene_magicshop_list_bg", row.size)
		if bgn != null:
			row.add_child(bgn)
		var ip := Data.item_icon_path(ik)
		if ip != "" and ResourceLoader.exists(ip):
			var ic := Sprite2D.new()
			ic.texture = load(ip); ic.material = AtlasUI.pma()
			ic.position = Vector2(36.0, 31.0); ic.scale = Vector2(0.46, 0.46)
			row.add_child(ic)
		var l := Label.new()
		l.text = nm
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		l.position = Vector2(70.0, 6.0); l.size = Vector2(160.0, 24.0)
		row.add_child(l)
		var badge := AtlasUI.spr("magicshop_alchemy",
			"scene_magicshop_alchemy_alchemy_point_%d" % clampi(i + 1, 1, 5), Design.ASSET_SCALE * 0.85)
		var bsz := AtlasUI.size_pt("magicshop_alchemy", "scene_magicshop_alchemy_alchemy_point_1") * 0.85
		if badge != null:
			badge.position = Vector2(70.0 + bsz.x * 0.5, 42.0)
			row.add_child(badge)
		var pts: Array = p.get("points", [0, 0])
		var pl := Label.new()
		pl.text = ("%d ~ %d" % [int(pts[0]), int(pts[1])]) if p.has("points") \
			else "성공률 %d%%" % int(p.get("success_pct", 0))
		pl.add_theme_font_size_override("font_size", 15)
		pl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		pl.position = Vector2(74.0 + bsz.x, 32.0); pl.size = Vector2(110.0, 22.0)
		row.add_child(pl)
		var cl := Label.new()
		cl.text = "%d개" % UserDB.item_count(ik)
		cl.add_theme_font_size_override("font_size", 19)
		cl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cl.position = Vector2(row.size.x - 110.0, 20.0); cl.size = Vector2(90.0, 24.0)
		row.add_child(cl)
		var b := Button.new(); b.flat = true; b.size = row.size
		b.disabled = not has or Gem.is_broken(inst)
		var pp := p
		var pk := ik
		b.pressed.connect(func(): _confirm_potion(pp, pk))
		row.add_child(b)
	if owned.is_empty():
		var nn := _note("보유한 용액이 없습니다.\n'용액 제작'에서 만드세요.")
		nn.position = Vector2(10, 10)
		holder.add_child(nn)
	var info := AtlasUI.nine("ninepatch_ui", "9patch_chat_black", Vector2(lw, 104.0), Rect2(9, 9, 9, 9))
	if info != null:
		info.position = Vector2(lx, 292.0)
		pop.content.add_child(info)
	var pnt := int(inst.get("points", 0)) if has else 0
	var used := int(inst.get("potions", 0)) if has else 0
	var pmax := int((Data.gems.get("upgrade", {}) as Dictionary).get("potion_max_per_try", 5))
	var rate := Gem.inst_success_chance(inst, Data.gems) if has else 0
	var rows := [[Data.ui("#ce7c5c62"), "%d /100" % pnt], [Data.ui("#46c2b222"), "%d회" % maxi(0, pmax - used)],
		["성공률", "%d%%" % rate]]
	for i in rows.size():
		var kl := Label.new()
		kl.text = String((rows[i] as Array)[0])
		kl.add_theme_font_size_override("font_size", 17)
		kl.add_theme_color_override("font_color", Color(0.98, 0.92, 0.62))
		kl.position = Vector2(lx + 16.0, 312.0 + i * 24.0); kl.size = Vector2(200.0, 22.0)
		pop.content.add_child(kl)
		var vl := Label.new()
		vl.text = String((rows[i] as Array)[1])
		vl.add_theme_font_size_override("font_size", 17)
		vl.add_theme_color_override("font_color", Color(1, 1, 1))
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vl.position = Vector2(lx + lw - 190.0, 312.0 + i * 24.0); vl.size = Vector2(174.0, 22.0)
		pop.content.add_child(vl)
	var warn := Label.new()
	warn.text = Data.ui("#d45ced09")
	warn.add_theme_font_size_override("font_size", 15)
	warn.add_theme_color_override("font_color", Color(0.36, 0.22, 0.10))
	warn.position = Vector2(lx, 402.0); warn.size = Vector2(lw, 22.0)
	pop.content.add_child(warn)
	pop.add_action_button("혼성젬 선택", func(): _open_gem_picker("hybrid", func(k: String):
			_hybrid_key = k
			_refresh_feature()),
		2, Vector2(190.0, 50.0), Vector2(lx + 100.0, H - 30.0))
	pop.add_action_button("강화", _hybrid_upgrade,
		0, Vector2(190.0, 50.0), Vector2(lx + 300.0, H - 30.0))

func _alchemy_play(anim: String, loop := true) -> void:
	if not is_instance_valid(_alchemy_spine):
		return
	var ap := _alchemy_spine.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation(anim):
		return
	ap.get_animation(anim).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	ap.play(anim)
	if not loop:
		ap.animation_finished.connect(func(_a):
			if is_instance_valid(_alchemy_spine):
				_alchemy_play("normal"), CONNECT_ONE_SHOT)

func _rekey_gem(old_key: String, new_inst: Dictionary) -> String:
	var nk := Gem.slot_to_item_key(new_inst)
	if nk == "" or UserDB.item_count(old_key) <= 0:
		return old_key
	UserDB.use_item(old_key, 1)
	UserDB.add_item(nk, 1)
	return nk

func _confirm_potion(potion: Dictionary, item_key: String) -> void:
	if _hybrid_key == "":
		_toast("먼저 혼성젬을 고르세요."); return
	if UserDB.item_count(item_key) <= 0:
		_toast("용액이 없습니다"); return
	var nm := String(potion.get("name", ""))
	var body := ""
	var warn := "\n\n*100포인트 초과시 확률이 초기화됩니다."
	if potion.has("points"):
		var lo := int((potion["points"] as Array)[0])
		var hi := int((potion["points"] as Array)[1])
		body = ("[혼성젬 %d 연금포인트 증가]" % hi) if lo == hi \
			else ("[혼성젬 1~%d 연금포인트 증가]" % hi)
	else:
		body = "[혼성젬 %d 강화 성공확률 증가]" % int(potion.get("success_pct", 0))
		warn = ""
	MessageWindow.open(self, "알림", "%s을 사용하시겠습니까?\n%s%s" % [nm, body, warn],
		func(): _pour_potion(potion, item_key), "확인", "취소")

func _pour_potion(potion: Dictionary, item_key: String) -> void:
	if _hybrid_key == "":
		return
	var inst := _ref_inst(_hybrid_key)
	var rng2 := RandomNumberGenerator.new(); rng2.randomize()
	var res: Dictionary = Gem.inst_add_potion(inst, potion, Data.gems, rng2)
	if res.is_empty():
		_toast("더 투입할 수 없습니다"); return
	if UserDB.item_count(item_key) <= 0:
		_toast("용액이 없습니다"); return
	UserDB.use_item(item_key, 1)
	_hybrid_key = _ref_write(_hybrid_key, res["inst"])
	if bool(res.get("reset", false)):
		_toast("연금포인트가 100을 넘어 초기화됐습니다 (+%d)" % int(res["gained"]))
	else:
		_toast("연금포인트 +%d → %d" % [int(res["gained"]), int(res["points"])])
	_refresh_feature()
	_alchemy_play(String(POTION_ANIM.get(item_key, "")), false)

func _hybrid_upgrade() -> void:
	if _hybrid_key == "":
		_toast("강화할 혼성젬을 먼저 고르세요."); return
	var inst := _ref_inst(_hybrid_key)
	if inst.is_empty():
		return
	if Gem.is_broken(inst):
		_toast("파손된 젬입니다 — 먼저 복구하세요."); return
	var cost := _gem_cost(String(inst["name"]), int(inst["tier"]))
	if UserDB.gold() < cost:
		_toast("골드가 부족하네요"); return
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var res: Dictionary = Gem.inst_roll_upgrade(inst, Data.gems, rng)
	if res.is_empty():
		_toast("이미 최대 등급입니다"); return
	if not UserDB.spend("gold", cost):
		return
	var before := _gem_result_line(inst)
	var after_inst: Dictionary = res["inst"]
	_hybrid_key = _ref_write(_hybrid_key, after_inst)
	var ok := bool(res.get("ok", false))
	if ok:
		_toast(Data.ui("#04c9baea"))
	else:
		_toast("아쉽게 실패했네요. 다음을 기약하죠. (성공률 %d%% — 파손)"
			% int(res.get("chance", 0)), 4)
	_show_upgrade_result(ok, before, _gem_result_line(after_inst), after_inst,
		"" if ok else _hybrid_key)
	_refresh_feature()

func _offer_repair(broken_key: String, label: String) -> void:
	var inst := _ref_inst(broken_key)
	if inst.is_empty() or not Gem.is_broken(inst):
		return
	var dia := Gem.repair_cost(int(inst["tier"]), Data.gems)
	MessageWindow.open(self, "젬 복구",
		"%s\n다이아를 사용하여 해당 젬을 복구하시겠습니까?" % label,
		func(): _repair_bag_gem(broken_key, dia),
		"확인", "취소", 0, dia,
		func(): _destroy_broken_gem(broken_key))

func _repair_bag_gem(broken_key: String, dia: int) -> void:
	var inst := _ref_inst(broken_key)
	var fixed := Gem.inst_repair(inst)
	if fixed.is_empty():
		return
	if not UserDB.spend("diamond", dia):
		_toast("다이아가 부족합니다 — 젬이 소멸했습니다")
		_destroy_broken_gem(broken_key)
		return
	_retarget(broken_key, _ref_write(broken_key, fixed))
	_toast("젬을 복구했습니다.")
	_refresh_feature()

func _retarget(old_ref: String, new_ref: String) -> void:
	if old_ref == "" or old_ref == new_ref:
		return
	if _hybrid_key == old_ref:
		_hybrid_key = new_ref
	if _gem_key == old_ref:
		_gem_key = new_ref
	if _soul_key == old_ref:
		_soul_key = new_ref

func _destroy_broken_gem(broken_key: String, msg := Data.ui("#08d70c49")) -> void:
	if broken_key == "" or _ref_inst(broken_key).is_empty():
		return
	_ref_remove(broken_key)
	if _hybrid_key == broken_key:
		_hybrid_key = ""
	if _gem_key == broken_key:
		_gem_key = ""
	if _soul_key == broken_key:
		_soul_key = ""
	_toast(msg)
	_refresh_feature()

const DIS_SLOTS := 6
const DIS_COLS := 3

const DUST_ROWS := [
	{"key": "att_powder", "label": "붉은 마법가루"},
	{"key": "def_powder", "label": "푸른 마법가루"},
	{"key": "hp_powder", "label": "노란 마법가루"},
]

func _dis_gold_per_gem() -> int:
	return int((Data.gems.get("disassemble", {}) as Dictionary).get("gold_per_gem", 500))

func _body_disassemble(pop: FramedWindow) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var S := Design.ASSET_SCALE
	while _dis_slots.size() < DIS_SLOTS:
		_dis_slots.append("")

	var hex := AtlasUI.size_pt("magicshop_ui", "scene_magicshop_gem_bg") * 0.62
	var gx := hex.x + 14.0
	var gy := hex.y + 12.0
	var x0 := 70.0 + hex.x * 0.5
	var y0 := 130.0 + hex.y * 0.5
	for i in DIS_SLOTS:
		var c := Vector2(x0 + float(i % DIS_COLS) * gx, y0 + float(i / DIS_COLS) * gy)
		var root := Control.new()
		root.size = hex
		root.position = c - hex * 0.5
		pop.content.add_child(root)
		var bg := _spr("gem_bg", S * 0.62)
		if bg:
			bg.position = hex * 0.5
			root.add_child(bg)
		var ik := _dis_key(i)
		if ik == "":
			var l := Label.new()
			l.text = "젬"
			l.add_theme_font_size_override("font_size", 17)
			l.add_theme_color_override("font_color", Color(0.42, 0.30, 0.18))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.size = hex
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(l)
		else:
			var g := Gem.parse_item_key(ik)
			var gi := Icons.gem_rect(
				String(Gem.gem_def(String(g["name"]), Data.gems).get("code", "")),
				int(g["tier"]), hex.x * 0.62)
			if gi:
				gi.position = (hex - gi.size) * 0.5
				root.add_child(gi)
			var n := Label.new()
			n.text = "x%d" % _dis_cnt(i)
			n.add_theme_font_size_override("font_size", 15)
			n.add_theme_color_override("font_color", Color(1, 1, 1))
			n.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			n.add_theme_constant_override("outline_size", 4)
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			n.position = Vector2(0, hex.y - 24.0)
			n.size = Vector2(hex.x, 22.0)
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(n)
		var idx := i
		var b := Button.new()
		b.flat = true
		b.size = hex
		b.pressed.connect(func(): _dis_click_slot(idx))
		root.add_child(b)

	var arrow := AtlasUI.spr("common_ui", "common_btn_fold", S * 0.8)
	if arrow:
		arrow.rotation = deg_to_rad(90.0)
		arrow.position = Vector2(x0 + 2.0 * gx + hex.x * 0.5 + 26.0, y0 + gy * 0.5)
		pop.content.add_child(arrow)

	var yields := _dis_yields()
	var px := x0 + 2.0 * gx + hex.x * 0.5 + 56.0
	var pw := W - px - 50.0
	for r in DUST_ROWS.size():
		var d: Dictionary = DUST_ROWS[r]
		var ry := 118.0 + float(r) * 64.0
		var row := AtlasUI.nine("ninepatch_ui", "9patch_train_box3",
			Vector2(pw, 56.0), Rect2(20, 20, 4, 4))
		if row:
			row.position = Vector2(px, ry)
			pop.content.add_child(row)
		var ip := Data.item_icon_path(String(d["key"]))
		if ip != "" and ResourceLoader.exists(ip):
			var ic := Sprite2D.new()
			ic.texture = load(ip)
			ic.material = _pma
			ic.scale = Vector2(0.34, 0.34)
			ic.position = Vector2(px + 32.0, ry + 28.0)
			pop.content.add_child(ic)
		var nl := Label.new()
		nl.text = String(d["label"])
		nl.add_theme_font_size_override("font_size", 16)
		nl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nl.position = Vector2(px + 62.0, ry + 17.0)
		nl.size = Vector2(pw - 200.0, 22.0)
		pop.content.add_child(nl)
		var have := int(yields.get(String(d["key"]), 0))
		var vl := Label.new()
		vl.text = "%s개" % _comma(have)
		vl.add_theme_font_size_override("font_size", 18)
		vl.add_theme_color_override("font_color",
			Color(0.10, 0.42, 0.16) if have > 0 else Color(0.45, 0.33, 0.20))
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		vl.position = Vector2(px, ry + 16.0)
		vl.size = Vector2(pw - 22.0, 24.0)
		pop.content.add_child(vl)

	var cost := _dis_cost()
	var btn := _frame_button(pop.content, _comma(cost),
		Vector2(W * 0.5 - 110.0, H - 84.0), Vector2(220.0, 52.0), _dis_confirm, 0, cost <= 0)
	var coin := AtlasUI.spr("common_ui", "common_coin_small1", S * 0.9)
	if coin:
		coin.position = Vector2(30.0, 26.0)
		btn.add_child(coin)

func _dis_key(i: int) -> String:
	var s = _dis_slots[i]
	if s is Dictionary:
		return String((s as Dictionary).get("key", ""))
	return String(s)

func _dis_cnt(i: int) -> int:
	var key := _dis_key(i)
	if key == "":
		return 0
	var s = _dis_slots[i]
	var n := int((s as Dictionary).get("cnt", 1)) if s is Dictionary else UserDB.item_count(key)
	return clampi(n, 0, UserDB.item_count(key))

func _dis_used_elsewhere(key: String, except_slot: int) -> int:
	var n := 0
	for i in _dis_slots.size():
		if i != except_slot and _dis_key(i) == key:
			n += _dis_cnt(i)
	return n

func _dis_yields() -> Dictionary:
	var out := {"att_powder": 0, "def_powder": 0, "hp_powder": 0}
	for i in _dis_slots.size():
		var key := _dis_key(i)
		if key == "":
			continue
		var g := Gem.parse_item_key(key)
		if g.is_empty():
			continue
		var dk := Gem.dust_key_for(String(g["name"]))
		out[dk] = int(out[dk]) + Gem.disassemble_dust(int(g["tier"]), Data.gems) * _dis_cnt(i)
	return out

func _dis_special() -> int:
	var sp := 0
	for i in _dis_slots.size():
		var key := _dis_key(i)
		if key == "":
			continue
		var g := Gem.parse_item_key(key)
		if g.is_empty():
			continue
		sp += Gem.disassemble_special(int(g["tier"]), Data.gems) * _dis_cnt(i)
	return sp

func _dis_count() -> int:
	var n := 0
	for i in _dis_slots.size():
		n += _dis_cnt(i)
	return n

func _dis_cost() -> int:
	return Gem.disassemble_gold(_dis_count(), Data.gems)

func _dis_click_slot(i: int) -> void:
	if _dis_key(i) != "":
		_dis_slots[i] = ""
		_refresh_feature()
		return
	_open_gem_picker("", func(key: String, cnt: int):
		_dis_slots[i] = {"key": key, "cnt": maxi(1, cnt)}
		_refresh_feature(), i)

func _dis_confirm() -> void:
	var cost := _dis_cost()
	if cost <= 0:
		return
	if UserDB.gold() < cost:
		_toast("골드가 부족합니다")
		return
	MessageWindow.open(self, "알림",
		"젬을 분해할 경우 선택한 젬은 사라집니다.\n분해하시겠습니까?", _dis_run, "확인", "취소")

func _dis_run() -> void:
	var cost := _dis_cost()
	if cost <= 0 or not UserDB.spend("gold", cost):
		return
	var yields := _dis_yields()
	var sp := _dis_special()
	for i in _dis_slots.size():
		var key := _dis_key(i)
		if key != "":
			UserDB.use_item(key, _dis_cnt(i))
	var got: Array = []
	for k in yields.keys():
		var n := int(yields[k])
		if n > 0:
			UserDB.add_item(String(k), n)
			got.append({"key": String(k), "count": n})
	if sp > 0:
		UserDB.add_item("alchemy_special", sp)
		got.append({"key": "alchemy_special", "count": sp})
	_dis_slots = ["", "", "", "", "", ""]
	_refresh_feature()
	if not got.is_empty():
		ItemRewardView.open(self, got)
	if sp > 0:
		MessageWindow.open(self, "알림",
			"젬분해 추가 보상으로 초월의 용액 %d개를 받았습니다." % sp, Callable(), "확인", "")
	_toast(Data.ui("#cd2b97cd"))

func _disassemble(item_key: String, gem_name: String, tier: int) -> void:
	if UserDB.item_count(item_key) <= 0:
		return
	UserDB.use_item(item_key, 1)
	var dust := Gem.disassemble_dust(tier, Data.gems)
	var sp := Gem.disassemble_special(tier, Data.gems)
	UserDB.add_item(Gem.dust_key_for(gem_name), dust)
	if sp > 0:
		UserDB.add_item("alchemy_special", sp)
	_toast("분해했습니다 — 가루 %d개%s" % [dust, ("" if sp <= 0 else " · 초월의 용액 %d개" % sp)])
	_refresh_feature()

func _body_potion_shop(pop: FramedWindow) -> void:
	var W: float = pop.win_size.x
	var items: Array = (Data.gems.get("potion_shop", {}) as Dictionary).get("items", [])
	var cw := AtlasUI.size_pt("common_ui", "common_item_bg").x
	var ch := AtlasUI.size_pt("common_ui", "common_item_bg").y
	const K := 0.78
	var cols := 2
	var gx := cw * K + 40.0
	var gy := ch * K + 18.0
	var x0: float = round((W - ((cols - 1) * gx + cw * K)) * 0.5)
	for i in items.size():
		var e: Dictionary = items[i]
		var key := String(e.get("item", ""))
		var price := int(e.get("price", 0))
		var cur := String(e.get("cur", "gold"))
		var card := Control.new()
		card.size = Vector2(cw, ch)
		card.scale = Vector2(K, K)
		card.position = Vector2(x0 + (i % cols) * gx, 100.0 + (i / cols) * gy)
		pop.content.add_child(card)
		var frame := AtlasUI.spr("common_ui", "common_item_bg", Design.ASSET_SCALE)
		if frame != null:
			frame.position = Vector2(cw, ch) * 0.5
			card.add_child(frame)
		var back := AtlasUI.spr("common_ui", "common_backlight3", 0.35 * Design.ASSET_SCALE)
		if back != null:
			back.position = Vector2(cw * 0.5, ch * 0.5 + 6.0)
			card.add_child(back)
		var ip := Data.item_icon_path(key)
		if ip != "" and ResourceLoader.exists(ip):
			var ic := Sprite2D.new()
			ic.texture = load(ip); ic.material = AtlasUI.pma()
			ic.position = Vector2(cw * 0.5, ch * 0.5 + 6.0); ic.scale = Vector2(0.62, 0.62)
			card.add_child(ic)
		var l := Label.new()
		l.text = Data.item_name(key)
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(cw, 22.0); l.position = Vector2(0, 12.0)
		card.add_child(l)
		var cicon := AtlasUI.spr("common_ui",
			"common_diamond_small1" if cur == "diamond" else "common_coin_small1", Design.ASSET_SCALE)
		if cicon != null:
			cicon.position = Vector2(cw * 0.5 - 26.0, ch - 22.0)
			card.add_child(cicon)
		var pl := Label.new()
		pl.text = AtlasUI.comma(price)
		pl.add_theme_font_size_override("font_size", 18)
		pl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		pl.position = Vector2(cw * 0.5 - 6.0, ch - 34.0); pl.size = Vector2(70.0, 24.0)
		card.add_child(pl)
		var b := Button.new(); b.flat = true; b.size = Vector2(cw, ch)
		var k2 := key
		var p2 := price
		var c2 := cur
		b.pressed.connect(func(): _open_potion_buy(k2, p2, c2))
		card.add_child(b)
	if items.is_empty():
		var nn := _note("파는 용액이 없습니다.")
		nn.position = Vector2(60.0, 140.0)
		pop.content.add_child(nn)
	var warn := _note("⚠️ 판매 가격은 원작 서버 데이터라 유실 — data/gems.json `potion_shop` 자작값")
	warn.position = Vector2(50.0, pop.win_size.y - 56.0)
	warn.size = Vector2(W - 100.0, 24.0)
	pop.content.add_child(warn)

func _open_potion_buy(key: String, price: int, cur: String) -> void:
	var sub := FramedWindow.open(self, Data.item_name(key), Vector2(560.0, 340.0))
	var W: float = sub.win_size.x
	var H: float = sub.win_size.y
	var qty := [1]
	var ip := Data.item_icon_path(key)
	if ip != "" and ResourceLoader.exists(ip):
		var ic := Sprite2D.new()
		ic.texture = load(ip); ic.material = AtlasUI.pma()
		ic.position = Vector2(120.0, 170.0)
		sub.content.add_child(ic)
	var line := ""
	for p0 in (Data.gems.get("upgrade", {}) as Dictionary).get("potions", []):
		var pd: Dictionary = p0
		if String(POTION_ITEM.get(String(pd.get("name", "")), "")) != key:
			continue
		if pd.has("points"):
			var lo := int((pd["points"] as Array)[0])
			var hi := int((pd["points"] as Array)[1])
			line = ("젬 강화에 투입하면 연금포인트를 %d 올려 줍니다." % lo) if lo == hi 				else "젬 강화에 투입하면 연금포인트를 %d~%d 올려 줍니다." % [lo, hi]
		else:
			line = "젬 강화 성공률을 %d%% 로 고정합니다." % int(pd.get("success_pct", 0))
		break
	var desc := Label.new()
	desc.text = "%s

보유 %d개" % [line, UserDB.item_count(key)]
	desc.add_theme_font_size_override("font_size", 17)
	desc.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.position = Vector2(215.0, 100.0); desc.size = Vector2(300.0, 130.0)
	sub.content.add_child(desc)
	var qlabel := Label.new()
	qlabel.text = "1"
	qlabel.add_theme_font_size_override("font_size", 24)
	qlabel.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	qlabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qlabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	qlabel.position = Vector2(96.0, H - 116.0); qlabel.size = Vector2(70.0, 40.0)
	sub.content.add_child(qlabel)
	var total := Label.new()
	total.add_theme_font_size_override("font_size", 21)
	total.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	total.position = Vector2(250.0, H - 110.0); total.size = Vector2(220.0, 28.0)
	sub.content.add_child(total)
	var sync := func():
		qlabel.text = str(qty[0])
		total.text = "%s %s" % [AtlasUI.comma(price * qty[0]), "다이아" if cur == "diamond" else "골드"]
	sync.call()
	for d: int in [-1, 1]:
		var ab := AtlasUI.spr("common_ui", "common_btn_arrow2", Design.ASSET_SCALE)
		var ax := 62.0 if d < 0 else 200.0
		if ab != null:
			ab.position = Vector2(ax, H - 96.0)
			ab.flip_h = d < 0
			sub.content.add_child(ab)
		var bb := Button.new(); bb.flat = true; bb.size = Vector2(44.0, 54.0)
		bb.position = Vector2(ax - 22.0, H - 123.0)
		var dd: int = d
		bb.pressed.connect(func():
			qty[0] = clampi(qty[0] + dd, 1, 99)
			sync.call())
		sub.content.add_child(bb)
	sub.add_action_button("구입", func():
		var n: int = qty[0]
		if not UserDB.spend(cur, price * n):
			_toast("재화가 부족합니다"); return
		UserDB.add_item(key, n)
		_toast("%s %d개를 구매했습니다" % [Data.item_name(key), n])
		sub.close()
		_refresh_feature(),
		0, Vector2(170.0, 50.0), Vector2(W - 130.0, H - 96.0))

func _body_egg(pop: FramedWindow) -> void:
	var col := _body_panel(pop)
	col.add_child(_note("서로 다른 알을 조합하여 새로운 알을 얻을 수 있습니다.\n(원작 <MagicWelcomeEgg>)"))
	var recipes := 0
	if Data.combine_egg is Dictionary:
		recipes = (Data.combine_egg.get("recipes", []) as Array).size()
	if recipes == 0:
		col.add_child(_note("⚠️ 알 조합 레시피가 아직 비어 있습니다.\ndocs/input/review/combine_egg_sheet.md 를 채우면 조합할 수 있습니다."))
	var b := Button.new(); b.text = "연구소로 이동 (알 조합)"; b.custom_minimum_size = Vector2(0, 46)
	b.pressed.connect(func(): Scenes.goto("laboratory", {"area": _params.get("area", "elpis")}))
	col.add_child(b)

const SLOT_STOP_BASE := 2.0
const SLOT_STOP_STEP := 0.5
const SLOT_TICK := 0.06
var _reels: Array = []
var _slot_faces: Array = []
var _slot_btns: Array = []
var _slot_spin := false

func _body_slot(pop: FramedWindow) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var cfg: Dictionary = Data.drops.get("slot", {})
	var price := int(cfg.get("price_gold", 1000))
	var cy := H * 0.5 + 14.0
	_slot_faces = Drops.slot_faces(Data.drops, Data.gems)
	_reels = []
	_slot_btns = []
	_slot_spin = false
	for i in 3:
		var bgspr := AtlasUI.spr("magicshop_ui", "scene_magicshop_slotBG", Design.ASSET_SCALE)
		if bgspr != null:
			bgspr.position = Vector2(W * 0.5 - 158.0 + 158.0 * i, cy)
			pop.content.add_child(bgspr)
		var reel := Control.new()
		reel.size = Vector2(150.0, 250.0)
		reel.position = Vector2(W * 0.5 - 157.0 + 157.0 * i - 75.0, cy - 125.0)
		reel.clip_contents = true
		reel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pop.content.add_child(reel)
		var face := Sprite2D.new()
		face.material = AtlasUI.pma()
		face.position = Vector2(75.0, 125.0)
		reel.add_child(face)
		_reels.append(face)
		if not _slot_faces.is_empty():
			_slot_set_face(face, int(round(float(i) * float(_slot_faces.size() - 1) / 2.0)))
	var frame := AtlasUI.spr("magicshop_ui", "scene_magicshop_slot_frame", Design.ASSET_SCALE)
	if frame != null:
		frame.position = Vector2(W * 0.5, cy)
		frame.z_index = 1
		pop.content.add_child(frame)
	_slot_btns.append(pop.add_action_button("   %s" % AtlasUI.comma(price),
		func(): _pull_slot(price), 0, Vector2(200.0, 56.0), Vector2(W * 0.25, H - 46.0)))
	_slot_btns.append(pop.add_action_button("10연속", func(): _pull_slot(price, 10), 2,
		Vector2(200.0, 56.0), Vector2(W * 0.75, H - 46.0)))
	var coin := AtlasUI.spr("common_ui", "common_coin_small1", Design.ASSET_SCALE)
	if coin != null:
		coin.position = Vector2(W * 0.25 - 46.0, H - 46.0)
		pop.content.add_child(coin)

func _slot_face_tex(face: Dictionary) -> Texture2D:
	var key := String(face.get("key", ""))
	if String(face.get("kind", "")) == "item":
		var p := "res://assets/converted/slot_item/item_item_small_slot_item_%s.tres" % key
		if ResourceLoader.exists(p):
			return load(p)
		var ip := Data.item_icon_path(key)
		return load(ip) if ip != "" and ResourceLoader.exists(ip) else null
	var nm := String(face.get("gem_name", ""))
	return Icons.gem_texture(String(Gem.gem_def(nm, Data.gems).get("code", "")),
		int(face.get("tier", 0)))

func _slot_set_face(face: Sprite2D, idx: int) -> void:
	if not is_instance_valid(face) or _slot_faces.is_empty():
		return
	var f: Dictionary = _slot_faces[posmod(idx, _slot_faces.size())]
	var t := _slot_face_tex(f)
	face.texture = t
	if t != null:
		var h := float(t.get_height())
		face.scale = Vector2.ONE * (1.0 if h <= 0.0 else clampf(96.0 / h, 0.8, 2.0))

func _slot_roll(reels: Array, on_done: Callable) -> void:
	if _reels.is_empty() or _slot_faces.is_empty():
		on_done.call(); return
	_slot_spin = true
	_slot_lock(true)
	var n := _slot_faces.size()
	var last := _reels.size() - 1
	for i in _reels.size():
		var face: Sprite2D = _reels[i]
		if not is_instance_valid(face):
			continue
		face.modulate.a = 1.0
		var steps := int((SLOT_STOP_BASE + SLOT_STOP_STEP * i) / SLOT_TICK)
		var tw := face.create_tween()
		for s in steps:
			var idx := (i * 3 + s + 1) % n
			tw.tween_callback(func(): _slot_set_face(face, idx))
			tw.tween_interval(SLOT_TICK)
		var res_idx := int(reels[i]) if i < reels.size() else 0
		tw.tween_callback(func(): _slot_set_face(face, res_idx))
		if i == last:
			tw.tween_callback(func():
				_slot_spin = false
				_slot_lock(false)
				on_done.call())

func _slot_blink() -> void:
	for f in _reels:
		var face: Sprite2D = f
		if not is_instance_valid(face):
			continue
		var tw := face.create_tween()
		for _r in 2:
			tw.tween_property(face, "modulate:a", 0.0, 0.25)
			tw.tween_property(face, "modulate:a", 1.0, 0.25)

func _slot_lock(on: bool) -> void:
	for b in _slot_btns:
		if not is_instance_valid(b):
			continue
		var root: Control = b
		root.modulate.a = 0.5 if on else 1.0
		for c in root.get_children():
			if c is Button:
				(c as Button).disabled = on

func _pull_slot(price: int, count := 1) -> void:
	if _slot_spin:
		return
	if _slot_faces.is_empty():
		_toast("뽑기 품목표가 비어 있습니다"); return
	if not UserDB.spend("gold", price * count):
		_toast("골드가 부족하네요"); return
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var results := Drops.roll_slot_many(Data.drops, Data.gems, rng, count)
	var got: Dictionary = {}
	for r in results:
		var res: Dictionary = r
		if not bool(res.get("win", false)):
			continue
		var k := String(res.get("key", ""))
		var c := int(res.get("count", 1))
		if k == "" or c <= 0:
			continue
		UserDB.add_item(k, c)
		got[k] = int(got.get(k, 0)) + c
	if is_instance_valid(_money_root):
		_money_root.queue_free()
	_build_money(_vis())
	var last: Dictionary = results[results.size() - 1]
	var win := bool(last.get("win", false))
	_slot_roll(last.get("reels", [0, 0, 0]), func(): _slot_result(got, win, count))

func _slot_result(got: Dictionary, last_win: bool, count: int) -> void:
	if last_win:
		_slot_blink()
	if got.is_empty():
		Bgm.sfx("effect_item_failed")
		_toast(Data.ui("#c425535b"), 4)
		return
	Bgm.sfx("effect_dragon_incubation")
	var names: PackedStringArray = []
	var entries: Array = []
	for k in got:
		names.append(_slot_prize_name(String(k)))
		entries.append({"key": String(k), "count": int(got[k])})
	if count <= 1:
		_toast("축하드려요!\n뽑기에 성공하여 %s을(를) 획득하셨어요~ 오늘은 운이 좋으시네요!"
			% ", ".join(names), 4)
	else:
		var wins := 0
		for k in got:
			wins += int(got[k])
		_toast("%d회 중 %d번 당첨! %s을(를) 획득하셨어요~" % [count, wins, ", ".join(names)], 4)
	ItemRewardView.open(self, entries)

func _slot_prize_name(key: String) -> String:
	if key.begins_with("gem:"):
		var g := Gem.parse_item_key(key)
		return Gem.display_name(String(g["name"]), int(g["tier"]), Data.gems)
	return Data.item_name(key)

func _comma(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out

func _gem_cost(gem_name: String, tier: int) -> int:
	var gd: Dictionary = Gem.gem_def(gem_name, Data.gems)
	if String(gd.get("category", "")) == "soul":
		var steps: Array = Data.gems.get("upgrade", {}).get("soul_steps", [])
		var i := clampi(tier, 0, steps.size() - 1)
		if i < steps.size(): return int((steps[i] as Dictionary).get("gold", 0))
	return Gem.upgrade_cost(tier, Data.gems)

const POTION_ITEM := {
	"절제의 용액": "alchemy_moderation",
	"지혜의 용액": "alchemy_wisdom",
	"용기의 용액": "alchemy_courage",
	"정의의 용액": "alchemy_justice",
	"영광의 용액": "alchemy_glory",
	"전설의 용액": "alchemy_legend",
	"초월의 용액": "alchemy_special",
}

const POTION_ROW_H := 96.0

var _potion_pick := ""

func _body_drink(pop: FramedWindow) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var rw := W - 80.0
	var rows: Array = []
	for p in (Data.gems.get("upgrade", {}).get("potions", []) as Array):
		var pd: Dictionary = p
		var nm := String(pd.get("name", ""))
		if not POTION_ITEM.has(nm) or bool(pd.get("shop_only", false)) or not pd.has("points"):
			continue
		rows.append(pd)
	var list := ScrollContainer.new()
	list.position = Vector2(40.0, 88.0)
	list.size = Vector2(rw, H - 88.0 - 92.0)
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.clip_contents = true
	list.follow_focus = false
	pop.content.add_child(list)
	list.ready.connect(func(): list.scroll_vertical = 0)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(rw - 16.0, rows.size() * POTION_ROW_H)
	list.add_child(holder)
	for i in rows.size():
		var pd: Dictionary = rows[i]
		var nm := String(pd.get("name", ""))
		var each := int(pd.get("cost_dust_each", 0))
		var mgold := int(pd.get("make_gold", 1000))
		var key := String(POTION_ITEM[nm])
		var ok := UserDB.gold() >= mgold
		for k: String in POWDERS:
			ok = ok and UserDB.item_count(k) >= each
		var row := Control.new()
		row.size = Vector2(rw - 16.0, POTION_ROW_H - 8.0)
		row.position = Vector2(0.0, i * POTION_ROW_H)
		holder.add_child(row)
		var bgn := AtlasUI.nine("magicshop_ui", "scene_magicshop_list_bg", row.size)
		if bgn != null:
			row.add_child(bgn)
		if key == _potion_pick:
			var sel := AtlasUI.nine("ninepatch_ui", "9patch_alchemy_list_sel", row.size,
				Rect2(15, 15, 1, 1))
			if sel != null:
				row.add_child(sel)
		var plate := AtlasUI.spr("magicshop_ui", "scene_magicshop_drink_bg", Design.ASSET_SCALE * 0.75)
		if plate != null:
			plate.position = Vector2(56.0, row.size.y * 0.5)
			row.add_child(plate)
		var ip := Data.item_icon_path(key)
		if ip != "" and ResourceLoader.exists(ip):
			var ic := Sprite2D.new()
			ic.texture = load(ip)
			ic.material = AtlasUI.pma()
			ic.position = Vector2(56.0, row.size.y * 0.5)
			ic.scale = Vector2(0.62, 0.62)
			row.add_child(ic)
		var l := Label.new()
		l.text = nm
		l.add_theme_font_size_override("font_size", 21)
		l.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		l.position = Vector2(108.0, 12.0); l.size = Vector2(190.0, 26.0)
		row.add_child(l)
		var pts: Array = pd.get("points", [0, 0])
		var badge := AtlasUI.spr("magicshop_alchemy",
			"scene_magicshop_alchemy_alchemy_point_%d" % clampi(i + 1, 1, 5), Design.ASSET_SCALE)
		var bsz := AtlasUI.size_pt("magicshop_alchemy", "scene_magicshop_alchemy_alchemy_point_1")
		if badge != null:
			badge.position = Vector2(108.0 + bsz.x * 0.5, 56.0)
			row.add_child(badge)
		var pl := Label.new()
		pl.text = "%d ~ %d" % [int(pts[0]), int(pts[1])]
		pl.add_theme_font_size_override("font_size", 17)
		pl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		pl.position = Vector2(112.0 + bsz.x, 44.0); pl.size = Vector2(90.0, 24.0)
		row.add_child(pl)
		var need := Label.new()
		need.text = "필요가루 :"
		need.add_theme_font_size_override("font_size", 18)
		need.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
		need.position = Vector2(300.0, 28.0); need.size = Vector2(110.0, 26.0)
		row.add_child(need)
		var n := 0
		for k: String in POWDERS:
			var px := 410.0 + n * 66.0
			var pip := Data.item_icon_path(k)
			if pip != "" and ResourceLoader.exists(pip):
				var pic := Sprite2D.new()
				pic.texture = load(pip)
				pic.material = AtlasUI.pma()
				pic.position = Vector2(px, row.size.y * 0.5)
				pic.scale = Vector2(0.42, 0.42)
				row.add_child(pic)
			var cl := Label.new()
			cl.text = "x%d" % each
			cl.add_theme_font_size_override("font_size", 18)
			cl.add_theme_color_override("font_color",
				Color(0.30, 0.17, 0.04) if UserDB.item_count(k) >= each else Color(0.72, 0.16, 0.10))
			cl.position = Vector2(px + 14.0, row.size.y * 0.5 - 4.0); cl.size = Vector2(48.0, 24.0)
			row.add_child(cl)
			n += 1
		var b := Button.new()
		b.flat = true
		b.size = row.size
		var k2 := key
		b.pressed.connect(func():
			_potion_pick = k2
			_refresh_feature())
		row.add_child(b)
		if not ok:
			row.modulate = Color(0.72, 0.72, 0.72)
	var bar := AtlasUI.nine("ninepatch_ui", "9patch_train_box3", Vector2(rw - 250.0, 46.0),
		Rect2(30, 16, 62, 8))
	if bar != null:
		bar.position = Vector2(40.0, H - 76.0)
		pop.content.add_child(bar)
	var m := 0
	for k: String in POWDERS:
		var px := 70.0 + m * 150.0
		var pip := Data.item_icon_path(k)
		if pip != "" and ResourceLoader.exists(pip):
			var pic := Sprite2D.new()
			pic.texture = load(pip)
			pic.material = AtlasUI.pma()
			pic.position = Vector2(px, H - 53.0)
			pic.scale = Vector2(0.42, 0.42)
			pop.content.add_child(pic)
		var cl := Label.new()
		cl.text = "x%d" % UserDB.item_count(k)
		cl.add_theme_font_size_override("font_size", 19)
		cl.add_theme_color_override("font_color", Color(0.95, 0.93, 0.85))
		cl.add_theme_color_override("font_outline_color", Color(0.16, 0.09, 0.03))
		cl.add_theme_constant_override("outline_size", 4)
		cl.position = Vector2(px + 16.0, H - 66.0); cl.size = Vector2(120.0, 26.0)
		pop.content.add_child(cl)
		m += 1
	pop.add_action_button("조합하기", func(): _confirm_potion_craft(rows),
		0, Vector2(200.0, 52.0), Vector2(W - 150.0, H - 53.0))

func _confirm_potion_craft(rows: Array) -> void:
	if _potion_pick == "":
		_toast(Data.ui("#4bad1fe7"))
		return
	var pd := {}
	for r in rows:
		var d: Dictionary = r
		if String(POTION_ITEM.get(String(d.get("name", "")), "")) == _potion_pick:
			pd = d
			break
	if pd.is_empty():
		_potion_pick = ""
		return
	var each := int(pd.get("cost_dust_each", 0))
	var gold := int(pd.get("make_gold", 1000))
	for k: String in POWDERS:
		if UserDB.item_count(k) < each:
			_toast(Data.ui("#ae11dc64"))
			return
	if UserDB.gold() < gold:
		_toast("골드가 부족하네요")
		return
	var nm := String(pd.get("name", ""))
	var pts: Array = pd.get("points", [0, 0])
	var key := _potion_pick
	MessageWindow.open(self, "용액 제작",
		"%s을 조합하시겠습니까?\n[혼성젬 강화 1~%d 연금포인트 증가]\n*사용된 재료는 사라집니다."
			% [nm, int(pts[1]) if pts.size() > 1 else 0],
		func(): _craft_potion(key, each, gold), "확인", "취소", 1, gold)

func _craft_potion(item_key: String, each: int, gold: int) -> void:
	for k: String in POWDERS:
		if UserDB.item_count(k) < each: return
	if not UserDB.spend("gold", gold):
		_toast("골드가 부족합니다"); return
	for k: String in POWDERS:
		UserDB.use_item(k, each)
	UserDB.add_item(item_key, 1)
	_toast("%s 1개를 제작했습니다" % Data.item_name(item_key))
	_refresh_feature()

func _body_trans(pop: FramedWindow) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var S := Design.ASSET_SCALE
	var cx := W * 0.5
	var cy := H * 0.56
	var unlocked := bool(UserDB.get_pmeta(Summon.FLAG_UNLOCK, false))
	const C1_PIVOT := Vector2(0.8, -29.8)
	var c1 := _spr("recall_magic_circle_1", S * 0.62)
	if c1 != null:
		c1.position = Vector2(cx, cy)
		c1.offset = C1_PIVOT
		c1.modulate = Color(1, 1, 1, 0.55)
		pop.content.add_child(c1)
		c1.create_tween().set_loops().tween_property(c1, "rotation", TAU, 24.0).as_relative()
	var c2 := _spr("recall_magic_circle_2", S * 0.62)
	if c2 != null:
		c2.position = Vector2(cx, cy)
		c2.modulate = Color(1, 1, 1, 0.8)
		pop.content.add_child(c2)
		c2.create_tween().set_loops().tween_property(c2, "rotation", -TAU, 14.0).as_relative()
	var shadow := AtlasUI.spr("common_ui", "common_shadow", S * 0.8)
	if shadow != null:
		shadow.position = Vector2(cx, cy + 44.0)
		shadow.modulate = Color(1, 1, 1, 0.55)
		pop.content.add_child(shadow)
	var stand := _spr("recall_stand", S * 0.8)
	if stand != null:
		stand.position = Vector2(cx, cy + 52.0)
		pop.content.add_child(stand)
	if not unlocked:
		var lk := _note("소환진이 깊이 잠들어 있습니다.\n아직 이곳의 힘을 깨울 때가 아닙니다.")
		lk.position = Vector2(60.0, 92.0)
		lk.size = Vector2(W - 120.0, 60.0)
		lk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pop.content.add_child(lk)
		var lb := pop.add_action_button("소환", func(): _toast("소환진이 응답하지 않습니다."),
			0, Vector2(243.0, 50.0))
		lb.modulate = Color(0.72, 0.72, 0.72)
		return

	var steps := {}
	for s in Summon.SPECIES:
		steps[s] = _summon_owned_step(int(s))
	var avail: Array = Summon.available_species(steps)
	if avail.is_empty():
		var dn := _note("소환진의 부름에 응답할 존재가 더는 남아 있지 않습니다.")
		dn.position = Vector2(60.0, 92.0); dn.size = Vector2(W - 120.0, 60.0)
		dn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pop.content.add_child(dn)
		return
	if not avail.has(_summon_species):
		_summon_species = int(avail[0])

	var mat := UserDB.get_dragon(_summon_uid)
	if not Summon.can_be_material(mat, _grade_of(mat)):
		mat = {}
		_summon_uid = 0
	if not mat.is_empty():
		_add_stand_dragon(pop.content, mat, Vector2(cx, cy + STAND_FOOT_Y))

	const NAMEPLATE_Z := 50
	var nb := AtlasUI.spr("common_ui", "common_name_bg", S)
	var nbs := AtlasUI.size_pt("common_ui", "common_name_bg")
	if nb != null:
		nb.position = Vector2(cx, cy + 92.0)
		nb.z_index = NAMEPLATE_Z
		pop.content.add_child(nb)
	var nl := Label.new()
	nl.text = _dragon_label(mat) if not mat.is_empty() else "드래곤을 골라주세요"
	nl.add_theme_font_size_override("font_size", 19)
	nl.add_theme_color_override("font_color",
		Color(0.36, 0.22, 0.08) if not mat.is_empty() else Color(0.55, 0.44, 0.30))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.size = Vector2(nbs.x, nbs.y)
	nl.position = Vector2(cx - nbs.x * 0.5, cy + 92.0 - nbs.y * 0.5)
	nl.z_index = NAMEPLATE_Z
	pop.content.add_child(nl)

	var head := _note("가장 소중한 드래곤을 골라주세요.\n"
		+ "선택된 드래곤은 강력한 힘을 받고 다시 태어납니다.")
	head.position = Vector2(60.0, 84.0); head.size = Vector2(W - 120.0, 48.0)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pop.content.add_child(head)

	var names := SPECIES_LABEL
	var bw := 150.0
	var gap := 12.0
	var n := avail.size() + 1
	var x0 := cx - (float(n) * bw + float(n - 1) * gap) * 0.5
	for i in avail.size():
		var sp := int(avail[i])
		var on := sp == _summon_species
		_frame_button(pop.content, String(names[sp]),
			Vector2(x0 + float(i) * (bw + gap), 140.0), Vector2(bw, 46.0),
			func():
				_summon_species = sp
				_refresh_feature(),
			1 if on else 0)
	_frame_button(pop.content, "드래곤 선택",
		Vector2(x0 + float(avail.size()) * (bw + gap), 140.0), Vector2(bw, 46.0),
		func(): _open_summon_picker())

	var ready := not mat.is_empty()
	var btn := pop.add_action_button("소환", func():
		if not ready:
			_toast("먼저 드래곤을 골라주세요.")
			return
		_do_summon(), 0, Vector2(243.0, 50.0))
	if not ready:
		btn.modulate = Color(0.72, 0.72, 0.72)

const STAND_SPINE_SCALE := 0.55
const STAND_FOOT_Y := 6.0

func _add_stand_dragon(parent: Node, mat: Dictionary, foot: Vector2) -> void:
	var art := Icons.art_id_of(mat)
	var stage_name := Growth.stage_for_level(int(mat.get("level", 1)))
	var path := Icons.spine_scene(art, stage_name)
	if path != "":
		var holder := Node2D.new()
		holder.scale = Vector2(STAND_SPINE_SCALE, STAND_SPINE_SCALE)
		holder.position = foot
		parent.add_child(holder)
		holder.add_child(load(path).instantiate())
		var ap := holder.get_child(0).get_node_or_null("AnimationPlayer")
		if ap and ap.has_animation("wait"):
			ap.play("wait")
		return
	var por := _dragon_portrait(mat, 110.0)
	if por != null:
		por.position = foot - Vector2(0, 54.0)
		parent.add_child(por)

func _grade_of(inst: Dictionary) -> float:
	if inst.is_empty():
		return -1.0
	return Growth.compute_grade(Data.get_dragon(int(inst.get("id", 0))), Data.stat_table,
		inst.get("stat_bonus", {}), inst.get("gain_log", []), Data.level_curve.get("grade", {}))

func _open_summon_picker() -> void:
	if not is_instance_valid(_popup):
		return
	_popup.clear_content()
	var col := _body_panel(_popup)
	var scroll := col.get_parent() as Control
	if scroll != null:
		scroll.size.y = maxf(80.0, scroll.size.y - 72.0)
	var cands := []
	for d in UserDB.dragons():
		if Summon.can_be_material(d, _grade_of(d)):
			cands.append(d)
	var req := _note("재료 자격: 레벨 %d 이상 · 등급 %.1f 이상\n(알·잠긴 드래곤과 소환으로 얻은 드래곤은 제외)"
		% [Summon.MATERIAL_MIN_LEVEL, Summon.MATERIAL_MIN_GRADE])
	req.custom_minimum_size = Vector2(0, 46)
	req.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(req)
	if cands.is_empty():
		var e := _note("자격을 갖춘 드래곤이 없습니다.")
		e.custom_minimum_size = Vector2(0, 40)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(e)
	var rw: float = _popup.win_size.x - 100.0
	for d in cands:
		var row := Control.new()
		row.custom_minimum_size = Vector2(rw, 64)
		col.add_child(row)
		var bgn := _row_bg(rw, 64)
		if bgn != null: row.add_child(bgn)
		var por := _dragon_portrait(d, 52.0)
		if por != null:
			por.position = Vector2(44.0, 32.0)
			row.add_child(por)
		var l := Label.new()
		l.text = "%s   Lv.%d" % [_dragon_label(d), int(d.get("level", 1))]
		l.add_theme_font_size_override("font_size", 19)
		l.add_theme_color_override("font_color", Color(0.36, 0.22, 0.08))
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.position = Vector2(84.0, 0.0); l.size = Vector2(rw - 230.0, 64.0)
		row.add_child(l)
		var uid := int(d.get("uid", 0))
		_frame_button(row, "선택", Vector2(rw - 130.0, 10.0), Vector2(110.0, 44.0),
			func():
				_summon_uid = uid
				_refresh_feature())
	_popup.add_action_button("돌아가기", func(): _refresh_feature(), 0, Vector2(220.0, 52.0))

func _summon_owned_step(sp: int) -> int:
	var step := UserDB.dex_step(sp)
	if step > 0:
		return step
	for k in UserDB.inventory().keys():
		if EggGacha.dragon_of(String(k)) == sp and UserDB.item_count(String(k)) > 0:
			return 1
	return 0

func _do_summon() -> void:
	var mat := UserDB.get_dragon(_summon_uid)
	var plan := Summon.plan(_summon_species, mat,
		Data.get_dragon(int(mat.get("id", 0))),
		bool(UserDB.get_pmeta(Summon.FLAG_UNLOCK, false)),
		_summon_owned_step(_summon_species), _grade_of(mat))
	if plan.is_empty():
		_toast("지금은 소환할 수 없습니다.")
		return
	var inh0: Dictionary = plan.get("inherit", {})
	var sp0 := int(plan["species"])
	UserDB.set_species_art(sp0, int(inh0.get("art_id", sp0)),
		String(inh0.get("element", "")) if typeof(inh0.get("element")) == TYPE_STRING else "")
	UserDB.add_item(EggItem.key(EggGacha.key_for(sp0), Summon.EGG_ENHANCE_STEP), 1)
	UserDB.consume_dragon(_summon_uid)
	UserDB.set_pmeta(Summon.FLAG_UNLOCK, false)
	_summon_uid = 0
	Bgm.sfx("effect_combine")
	var inh: Dictionary = inh0
	var sp := sp0
	var sname := String(inh.get("name", ""))
	if sname != "":
		UserDB.set_species_name(sp, sname)
	_egg_reveal = [{"did": sp, "opts": {
		"name": sname if sname != "" else String(SPECIES_LABEL.get(sp, "")),
		"art_id": int(inh.get("art_id", sp)),
		"element": inh.get("element", null),
	}}]
	_reveal_eggs("소환진이 빛나고, %s의 알이 되어 가방에 담겼습니다.")

func _dragon_label(d: Dictionary) -> String:
	if d.is_empty():
		return ""
	var nick := String(d.get("nickname", ""))
	if nick != "":
		return nick
	var nm := String(Data.get_dragon(int(d.get("id", 0))).get("name", ""))
	return nm if nm != "" else "이름 없는 드래곤"

func _dragon_portrait(d: Dictionary, box: float) -> Control:
	if d.is_empty():
		return null
	var aid := Icons.art_id_of(d)
	var stage := "egg" if UserDB.is_egg(d) else Growth.stage_for_level(int(d.get("level", 1)))
	var frame := ("dragon_dragon_%d_egg" % aid) if stage == "egg" \
		else ("dragon_dragon_%d_box_%s" % [aid, stage])
	var p := "res://assets/converted/portrait_%d/%s.tres" % [aid, frame]
	if not ResourceLoader.exists(p):
		p = "res://assets/converted/portrait_%d/dragon_dragon_%d_box_adult.tres" % [aid, aid]
	if not ResourceLoader.exists(p):
		return null
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.texture = load(p)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.size = Vector2(box, box)
	tr.position = Vector2(-box * 0.5, -box * 0.5)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tr)
	return holder

func _frame_button(parent: Control, text: String, pos: Vector2, sz: Vector2, cb: Callable,
		kind := 0, disabled := false) -> Control:
	return AtlasUI.frame_button(parent, text, pos, sz, cb, kind, disabled)

func _soul_mat_item(code: String) -> String:
	return String((Data.gems.get("upgrade", {}) as Dictionary)
		.get("soul_mat_items", {}).get(code, ""))

func _body_soul(pop: FramedWindow) -> void:
	var W: float = pop.win_size.x
	var H: float = pop.win_size.y
	var S := Design.ASSET_SCALE
	var midy := H * 0.5

	var bw := W * 0.9
	var bh := H * 0.5
	var box := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", Vector2(bw, bh), Rect2(65, 65, 6, 6))
	if box:
		box.position = Vector2(W * 0.5 - bw * 0.5, midy - bh * 0.5)
		pop.content.add_child(box)

	var hex := AtlasUI.size_pt("magicshop_ui", "scene_magicshop_gem_bg") * 0.72
	var slot := Control.new()
	slot.size = hex
	slot.position = Vector2(W * 0.13, midy) - hex * 0.5
	pop.content.add_child(slot)
	var hbg := _spr("gem_bg", S * 0.72)
	if hbg:
		hbg.position = hex * 0.5
		slot.add_child(hbg)
	var cur := _ref_inst(_soul_key)
	if cur.is_empty():
		_soul_key = ""
		var hint := Label.new()
		hint.text = "젬"
		hint.add_theme_font_size_override("font_size", 18)
		hint.add_theme_color_override("font_color", Color(0.42, 0.30, 0.18))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hint.size = hex
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(hint)
	else:
		var gi := Icons.gem_rect(
			String(Gem.gem_def(String(cur["name"]), Data.gems).get("code", "")),
			int(cur["tier"]), hex.x * 0.66)
		if gi:
			gi.position = (hex - gi.size) * 0.5
			slot.add_child(gi)
		var wl := _ref_where(_soul_key)
		if wl != "":
			var wlb := Label.new()
			wlb.text = wl
			wlb.add_theme_font_size_override("font_size", 14)
			wlb.add_theme_color_override("font_color", Color(0.72, 0.92, 1.0))
			wlb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			wlb.add_theme_constant_override("outline_size", 4)
			wlb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			wlb.clip_text = true
			wlb.size = Vector2(160.0, 20.0)
			wlb.position = Vector2(W * 0.13 - 80.0, midy + hex.y * 0.5 + 2.0)
			pop.content.add_child(wlb)
	var sb := Button.new()
	sb.flat = true
	sb.size = hex
	sb.pressed.connect(func(): _open_gem_picker("soul", func(k: String):
		_soul_key = k
		_refresh_feature()))
	slot.add_child(sb)

	var plus := AtlasUI.spr("common_ui", "common_plus", S * 0.8)
	if plus:
		plus.position = Vector2(W * 0.5 - 183.0, midy)
		pop.content.add_child(plus)
	var fold := AtlasUI.spr("common_ui", "common_btn_fold", S * 0.8)
	if fold:
		fold.rotation = deg_to_rad(90.0)
		fold.position = Vector2(W * 0.5 + 183.0, midy)
		pop.content.add_child(fold)

	var plan := _soul_plan()
	var mats: Array = plan.get("mats", [])
	for i in mats.size():
		var m: Dictionary = mats[i]
		var c := Vector2(W * 0.5 + (float(i) - (float(mats.size()) - 1.0) * 0.5) * 100.0, midy)
		var cell := Panel.new()
		cell.size = Vector2(86.0, 92.0)
		cell.position = c - cell.size * 0.5
		var sbf := StyleBoxFlat.new()
		sbf.bg_color = Color(0, 0, 0, 0.32)
		sbf.corner_radius_top_left = 12; sbf.corner_radius_top_right = 12
		sbf.corner_radius_bottom_left = 12; sbf.corner_radius_bottom_right = 12
		cell.add_theme_stylebox_override("panel", sbf)
		pop.content.add_child(cell)
		var ip := Data.item_icon_path(String(m["key"]))
		if ip != "" and ResourceLoader.exists(ip):
			var ic := Sprite2D.new()
			ic.texture = load(ip)
			ic.material = _pma
			ic.scale = Vector2(0.36, 0.36)
			ic.position = Vector2(43.0, 38.0)
			cell.add_child(ic)
		var nl := Label.new()
		var have := UserDB.item_count(String(m["key"]))
		var need := int(m["need"])
		nl.text = "%d/%d" % [mini(have, need), need]
		nl.add_theme_font_size_override("font_size", 15)
		nl.add_theme_color_override("font_color",
			Color(0.85, 1.0, 0.85) if have >= need else Color(1.0, 0.62, 0.55))
		nl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		nl.add_theme_constant_override("outline_size", 4)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.position = Vector2(0, 68.0)
		nl.size = Vector2(86.0, 22.0)
		cell.add_child(nl)

	var ebg := _spr("element_bg", S * 0.85)
	if ebg:
		ebg.position = Vector2(W * 0.87, midy)
		pop.content.add_child(ebg)
	var res_name := String(plan.get("result_name", ""))
	if res_name != "":
		var rg := Icons.gem_rect(String(plan.get("result_code", "")),
			int(plan.get("result_tier", 0)), 66.0)
		if rg:
			rg.position = Vector2(W * 0.87, midy) - rg.size * 0.5
			pop.content.add_child(rg)
	var rl := Label.new()
	rl.text = res_name if res_name != "" else "소울젬"
	rl.add_theme_font_size_override("font_size", 15)
	rl.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.position = Vector2(W * 0.87 - 110.0, midy + bh * 0.5 - 34.0)
	rl.size = Vector2(220.0, 22.0)
	pop.content.add_child(rl)

	var msg := String(plan.get("msg", ""))
	if msg != "":
		var ml := Label.new()
		ml.text = msg
		ml.add_theme_font_size_override("font_size", 15)
		ml.add_theme_color_override("font_color", Color(0.82, 0.78, 0.92))
		ml.add_theme_color_override("font_outline_color", Color(0.06, 0.03, 0.12, 0.9))
		ml.add_theme_constant_override("outline_size", 4)
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ml.position = Vector2(60.0, midy + bh * 0.5 + 6.0)
		ml.size = Vector2(W - 120.0, 44.0)
		pop.content.add_child(ml)

	var gold := int(plan.get("gold", 0))
	var can := bool(plan.get("ok", false))
	var btn := _frame_button(pop.content, _comma(gold) if gold > 0 else "승급/강화",
		Vector2(W * 0.5 - 102.0, H - 84.0), Vector2(205.0, 56.0), _soul_run, 0, not can)
	if gold > 0:
		var coin := AtlasUI.spr("common_ui", "common_coin_small1", S * 0.9)
		if coin:
			coin.position = Vector2(28.0, 28.0)
			btn.add_child(coin)

func _soul_plan() -> Dictionary:
	var out := {"ok": false, "gold": 0, "mats": [], "result_name": "", "result_code": "",
		"result_tier": 0, "msg": "승급할 19등급 혼성젬이나 강화할 소울젬을 고르세요."}
	if _soul_key == "":
		return out
	var g := _ref_inst(_soul_key)
	if g.is_empty():
		return out
	var nm := String(g["name"])
	var tier := int(g["tier"])
	var gd: Dictionary = Gem.gem_def(nm, Data.gems)
	var up: Dictionary = Data.gems.get("upgrade", {})
	if String(gd.get("category", "")) == "soul":
		var steps: Array = up.get("soul_steps", [])
		if tier + 1 >= steps.size():
			out["msg"] = "이미 최대 단계입니다."
			out["result_name"] = Gem.display_name(nm, tier, Data.gems)
			out["result_code"] = String(gd.get("code", ""))
			out["result_tier"] = tier
			return out
		var st: Dictionary = steps[tier + 1]
		out["gold"] = int(st.get("gold", 0))
		out["mats"] = _soul_mats(st, nm)
		out["result_name"] = Gem.display_name(nm, tier + 1, Data.gems)
		out["result_code"] = String(gd.get("code", ""))
		out["result_tier"] = tier + 1
		out["msg"] = "소울젬 강화는 실패하지 않습니다."
		out["ok"] = _soul_afford(int(out["gold"]), out["mats"])
		return out
	var to_code := String(gd.get("promote_to", ""))
	if to_code == "" or tier < Gem.max_tier(nm, Data.gems):
		out["msg"] = "최대 등급(19)의 혼성젬만 소울젬으로 승급할 수 있습니다."
		return out
	var to_name := Gem.name_of_code(to_code, Data.gems)
	out["gold"] = int((up.get("promote", {}) as Dictionary).get("gold", 1000000))
	out["mats"] = _soul_mats((up.get("soul_steps", [{}]) as Array)[0], to_name)
	out["result_name"] = Gem.display_name(to_name, 0, Data.gems)
	out["result_code"] = to_code
	out["result_tier"] = 0
	out["msg"] = "19등급 혼성젬을 소울젬으로 승급합니다."
	out["ok"] = _soul_afford(int(out["gold"]), out["mats"])
	return out

func _soul_mats(step: Dictionary, gem_name: String) -> Array:
	var order: Array = []
	var need: Dictionary = {}
	for row in [[Gem.dust_key_for(gem_name), int(step.get("dust", 0))],
			[_soul_mat_item("mat"), int(step.get("mat", 0))],
			[_soul_mat_item("core"), int(step.get("core", 0))]]:
		var k := String((row as Array)[0])
		var n := int((row as Array)[1])
		if k == "" or n <= 0:
			continue
		if not need.has(k):
			order.append(k)
			need[k] = 0
		need[k] = int(need[k]) + n
	var out: Array = []
	for k in order:
		out.append({"key": k, "need": int(need[k])})
	return out

func _soul_afford(gold: int, mats: Array) -> bool:
	if UserDB.gold() < gold:
		return false
	for m in mats:
		if UserDB.item_count(String((m as Dictionary)["key"])) < int((m as Dictionary)["need"]):
			return false
	return true

func _soul_run() -> void:
	var plan := _soul_plan()
	if not bool(plan.get("ok", false)) or _soul_key == "":
		return
	if not UserDB.spend("gold", int(plan["gold"])):
		return
	for m in (plan["mats"] as Array):
		UserDB.use_item(String((m as Dictionary)["key"]), int((m as Dictionary)["need"]))
	var g := _ref_inst(_soul_key)
	var new_name := Gem.name_of_code(String(plan["result_code"]), Data.gems)
	if new_name == "":
		new_name = String(g.get("name", ""))
	var new_inst := {"name": new_name, "tier": int(plan["result_tier"])}
	var new_key := Gem.item_key(new_name, int(plan["result_tier"]))
	if _ref_is_equipped(_soul_key):
		var pp := _ref_eq_parts(_soul_key)
		var gf: Dictionary = UserDB.get_dragon(int(pp[0])).get("gems", {})
		var slot_ty := String(Gem.types(gf)[int(pp[1])])
		if Gem.accepts(slot_ty, new_name, Data.gems):
			_ref_write(_soul_key, new_inst)
			_refresh_feature()
			_toast("%s!" % String(plan["result_name"]), 4)
			return
		_ref_remove(_soul_key)
		var ty_kr := String((Data.gems.get("slot_types", {}) as Dictionary)
			.get("kr", {}).get(slot_ty, slot_ty))
		_toast("젬 칸(%s)이 받지 않아 가방으로 옮겼습니다." % ty_kr)
	else:
		_ref_remove(_soul_key)
	UserDB.add_item(new_key, 1)
	_soul_key = new_key
	_refresh_feature()
	ItemRewardView.open(self, [{"key": new_key, "count": 1}])
	_toast("%s!" % String(plan["result_name"]), 4)

func _picker_shell(title: String, with_detail: bool) -> Dictionary:
	var vis := _vis()
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.z_index = 80
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)

	var sz := Vector2(minf(880.0, vis.x - 40.0), vis.y - 80.0)
	var win := Control.new()
	win.size = sz
	win.position = ((vis - sz) * 0.5).round()
	layer.add_child(win)
	var fr := AtlasUI.nine("ninepatch_ui", "9patch_popup4", sz, Rect2(130, 190, 40, 58))
	if fr:
		win.add_child(fr)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 26)
	t.add_theme_color_override("font_color", Color.WHITE)
	t.add_theme_color_override("font_outline_color", Color(0.35, 0.14, 0.03, 0.95))
	t.add_theme_constant_override("outline_size", 5)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.position = Vector2(0, 26.0)
	t.size = Vector2(sz.x, 40.0)
	win.add_child(t)
	var cb := TextureButton.new()
	var ct := AtlasUI.tex("common_ui", "common_close_btn")
	if ct:
		cb.texture_normal = ct
		cb.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 1.3
	cb.position = Vector2(sz.x - 76.0, 24.0)
	cb.pressed.connect(func(): layer.queue_free())
	win.add_child(cb)

	var det_w := 330.0
	var box_sz := Vector2(sz.x - 90.0 - (det_w + 20.0 if with_detail else 0.0), sz.y - 160.0)
	var np := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", box_sz, Rect2(65, 65, 6, 6))
	if np:
		np.position = Vector2(45.0, 80.0)
		win.add_child(np)
	var sc := ScrollContainer.new()
	sc.position = Vector2(58.0, 92.0)
	sc.size = box_sz - Vector2(26.0, 26.0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = maxi(1, int(sc.size.x / 104.0))
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	sc.add_child(grid)

	var det: Control = null
	if with_detail:
		det = Control.new()
		det.size = Vector2(det_w, box_sz.y)
		det.position = Vector2(sz.x - 45.0 - det_w, 80.0)
		win.add_child(det)
	return {"layer": layer, "win": win, "grid": grid, "det": det, "box_sz": box_sz, "size": sz}

func _picker_empty(shell: Dictionary, text: String) -> void:
	var box_sz: Vector2 = shell["box_sz"]
	var e := Label.new()
	e.text = text
	e.add_theme_font_size_override("font_size", 18)
	e.add_theme_color_override("font_color", Color(0.42, 0.30, 0.18))
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.position = Vector2(45.0, 80.0 + box_sz.y * 0.5 - 14.0)
	e.size = Vector2(box_sz.x, 28.0)
	(shell["win"] as Control).add_child(e)

func _open_item_picker(title: String, keys: Array, on_pick: Callable) -> void:
	var shell := _picker_shell(title, false)
	var layer: Control = shell["layer"]
	var grid: GridContainer = shell["grid"]
	for k in keys:
		var key := String(k)
		grid.add_child(_item_pick_cell(key, layer, on_pick))
	if keys.is_empty():
		_picker_empty(shell, "고를 수 있는 아이템이 가방에 없습니다.")

func _item_pick_cell(key: String, layer: Control, on_pick: Callable) -> Control:
	var cell := Panel.new()
	cell.custom_minimum_size = Vector2(98.0, 104.0)
	var sbf := StyleBoxFlat.new()
	sbf.bg_color = Color(0, 0, 0, 0.32)
	sbf.corner_radius_top_left = 12; sbf.corner_radius_top_right = 12
	sbf.corner_radius_bottom_left = 12; sbf.corner_radius_bottom_right = 12
	cell.add_theme_stylebox_override("panel", sbf)
	var ip := Data.item_icon_path(key)
	if ip != "" and ResourceLoader.exists(ip):
		var ic := Sprite2D.new()
		ic.texture = load(ip)
		ic.material = AtlasUI.pma()
		ic.position = Vector2(49.0, 40.0)
		ic.scale = Vector2(0.55, 0.55)
		cell.add_child(ic)
	var n := Label.new()
	n.text = "X %d" % UserDB.item_count(key)
	n.add_theme_font_size_override("font_size", 15)
	n.add_theme_color_override("font_color", Color(1, 1, 1))
	n.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	n.add_theme_constant_override("outline_size", 4)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.position = Vector2(0, 76.0)
	n.size = Vector2(98.0, 22.0)
	cell.add_child(n)
	cell.tooltip_text = Data.item_name(key)
	var b := Button.new()
	b.flat = true
	b.size = Vector2(98.0, 104.0)
	b.pressed.connect(func():
		layer.queue_free()
		on_pick.call(key))
	cell.add_child(b)
	return cell

const EQ_PREFIX := "eq:"

func _ref_is_equipped(ref: String) -> bool:
	return ref.begins_with(EQ_PREFIX)

func _ref_eq_parts(ref: String) -> Array:
	if not _ref_is_equipped(ref):
		return [0, -1]
	var p := ref.substr(EQ_PREFIX.length()).split(":")
	if p.size() != 2:
		return [0, -1]
	return [int(p[0]), int(p[1])]

func _ref_inst(ref: String) -> Dictionary:
	if ref == "":
		return {}
	if _ref_is_equipped(ref):
		var pp := _ref_eq_parts(ref)
		var d := UserDB.get_dragon(int(pp[0]))
		if d.is_empty():
			return {}
		var en := Gem.entries(d.get("gems", {}))
		var s := int(pp[1])
		if s < 0 or s >= Gem.SLOTS or en[s] == null:
			return {}
		return en[s]
	if UserDB.item_count(ref) <= 0:
		return {}
	return Gem.item_key_to_slot(ref)

func _ref_where(ref: String) -> String:
	if not _ref_is_equipped(ref):
		return ""
	var pp := _ref_eq_parts(ref)
	var d := UserDB.get_dragon(int(pp[0]))
	if d.is_empty():
		return ""
	var nm := String(Data.get_dragon(int(d.get("id", 0))).get("name", ""))
	if String(d.get("nickname", "")) != "":
		nm = String(d["nickname"])
	return "장착: %s" % (nm if nm != "" else "드래곤")

func _ref_write(ref: String, inst: Dictionary) -> String:
	if inst.is_empty():
		return ref
	if _ref_is_equipped(ref):
		var pp := _ref_eq_parts(ref)
		var uid := int(pp[0])
		var slot := int(pp[1])
		var gf: Dictionary = UserDB.get_dragon(uid).get("gems", {})
		var en := Gem.entries(gf)
		if slot < 0 or slot >= Gem.SLOTS:
			return ref
		en[slot] = inst
		UserDB.set_dragon_field(uid, "gems", {"types": Gem.types(gf), "slots": en})
		return ref
	return _rekey_gem(ref, inst)

func _ref_remove(ref: String) -> void:
	if ref == "":
		return
	if _ref_is_equipped(ref):
		var pp := _ref_eq_parts(ref)
		var uid := int(pp[0])
		var gf: Dictionary = UserDB.get_dragon(uid).get("gems", {})
		UserDB.set_dragon_field(uid, "gems", Gem.unequip_at(gf, int(pp[1])))
		return
	if UserDB.item_count(ref) > 0:
		UserDB.use_item(ref, 1)

func _equipped_gem_refs(filter: Callable) -> Array:
	var out: Array = []
	for d0 in UserDB.dragons():
		var d: Dictionary = d0
		var uid := int(d.get("uid", 0))
		var en := Gem.entries(d.get("gems", {}))
		for i in Gem.SLOTS:
			if en[i] == null:
				continue
			var inst: Dictionary = en[i]
			if not filter.call(inst):
				continue
			out.append({"ref": "%s%d:%d" % [EQ_PREFIX, uid, i], "inst": inst})
	return out

func _open_gem_picker(mode: String, on_pick: Callable, dis_slot := -1) -> void:
	var pick_qty := mode == ""
	var shell := _picker_shell("젬", pick_qty)
	var layer: Control = shell["layer"]
	var grid: GridContainer = shell["grid"]
	var det: Control = shell["det"]
	var state := {"key": "", "cnt": 1, "max": 1}

	var with_equipped := mode in ["normal", "hybrid", "soul"]
	var rows := 0
	for k in UserDB.inventory().keys():
		var key := String(k)
		var g := Gem.parse_item_key(key)
		if g.is_empty() or UserDB.item_count(key) <= 0:
			continue
		if not _gem_mode_allows(mode, g):
			continue
		if pick_qty and dis_slot >= 0 \
				and UserDB.item_count(key) - _dis_used_elsewhere(key, dis_slot) <= 0:
			continue
		rows += 1
		grid.add_child(_gem_pick_cell(key, g, layer, on_pick, det, state, dis_slot))
	if with_equipped:
		for e0 in _equipped_gem_refs(func(inst: Dictionary) -> bool:
				return _gem_mode_allows(mode, inst)):
			var e: Dictionary = e0
			rows += 1
			grid.add_child(_gem_pick_cell(String(e["ref"]), e["inst"], layer, on_pick,
				det, state, dis_slot))
	if rows == 0:
		_picker_empty(shell, "고를 수 있는 젬이 없습니다.")

func _gem_mode_allows(mode: String, g: Dictionary) -> bool:
	var nm := String(g.get("name", ""))
	var tier := int(g.get("tier", 0))
	var gd: Dictionary = Gem.gem_def(nm, Data.gems)
	var cat := String(gd.get("category", ""))
	var maxt := Gem.max_tier(nm, Data.gems)
	var broken := bool(g.get("broken", false))
	match mode:
		"normal":
			return cat == "normal" and (tier < maxt or broken)
		"fodder":
			return cat == "normal" and not broken
		"hybrid":
			return cat == "hybrid" and (tier < maxt or broken)
		"soul":
			if cat == "soul":
				return tier < maxt
			return cat == "hybrid" and String(gd.get("promote_to", "")) != "" and tier >= maxt
		_:
			return true

func _gem_pick_cell(key: String, g: Dictionary, layer: Control, on_pick: Callable,
		det: Control = null, state: Dictionary = {}, dis_slot := -1) -> Control:
	var cell := Panel.new()
	cell.custom_minimum_size = Vector2(98.0, 104.0)
	var sbf := StyleBoxFlat.new()
	sbf.bg_color = Color(0, 0, 0, 0.32)
	sbf.corner_radius_top_left = 12; sbf.corner_radius_top_right = 12
	sbf.corner_radius_bottom_left = 12; sbf.corner_radius_bottom_right = 12
	cell.add_theme_stylebox_override("panel", sbf)
	var nm := String(g["name"])
	var gi := Icons.gem_rect(
		String(Gem.gem_def(nm, Data.gems).get("code", "")), int(g["tier"]), 58.0)
	if gi:
		gi.position = Vector2(20.0, 10.0)
		cell.add_child(gi)
	var equipped := _ref_is_equipped(key)
	if bool(g.get("broken", false)):
		var fx := _spr("gem_fail", Design.ASSET_SCALE * 0.34)
		if fx:
			fx.position = Vector2(49.0, 39.0)
			cell.add_child(fx)
	var n := Label.new()
	n.text = _ref_where(key) if equipped else "X %d" % UserDB.item_count(key)
	n.add_theme_font_size_override("font_size", 13 if equipped else 15)
	n.add_theme_color_override("font_color", Color(0.72, 0.92, 1.0) if equipped else Color(1, 1, 1))
	n.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	n.add_theme_constant_override("outline_size", 4)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.clip_text = true
	n.position = Vector2(0, 76.0)
	n.size = Vector2(98.0, 22.0)
	cell.add_child(n)
	cell.tooltip_text = Gem.display_name(nm, int(g["tier"]), Data.gems)
	if equipped:
		cell.tooltip_text += "  (%s)" % _ref_where(key)
	var b := Button.new()
	b.flat = true
	b.size = Vector2(98.0, 104.0)
	if det == null:
		b.pressed.connect(func():
			layer.queue_free()
			on_pick.call(key))
	else:
		b.pressed.connect(func():
			var cap := UserDB.item_count(key)
			if dis_slot >= 0:
				cap -= _dis_used_elsewhere(key, dis_slot)
			state["key"] = key
			state["max"] = maxi(1, cap)
			state["cnt"] = 1
			_gem_pick_detail(det, layer, state, on_pick))
	cell.add_child(b)
	return cell

func _gem_pick_detail(det: Control, layer: Control, state: Dictionary, on_pick: Callable) -> void:
	for c in det.get_children():
		c.queue_free()
	var key := String(state.get("key", ""))
	if key == "":
		return
	var g := Gem.parse_item_key(key)
	if g.is_empty():
		return
	var nm := String(g["name"])
	var tier := int(g["tier"])
	var S := Design.ASSET_SCALE
	var W := det.size.x
	var cnt := clampi(int(state.get("cnt", 1)), 1, int(state.get("max", 1)))
	state["cnt"] = cnt

	var t := Label.new()
	t.text = Gem.display_name(nm, tier, Data.gems)
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", Color.WHITE)
	t.add_theme_color_override("font_outline_color", Color(0.35, 0.14, 0.03, 0.95))
	t.add_theme_constant_override("outline_size", 5)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.position = Vector2(0, 6.0)
	t.size = Vector2(W, 34.0)
	det.add_child(t)

	var cx := W * 0.62
	var cy := 130.0
	var sh := AtlasUI.spr("common_ui", "common_shadow", S)
	if sh:
		sh.position = Vector2(cx, cy + 58.0)
		det.add_child(sh)
	var big := Icons.gem_rect(
		String(Gem.gem_def(nm, Data.gems).get("code", "")), tier, 132.0)
	if big:
		big.position = Vector2(cx, cy) - big.size * 0.5
		det.add_child(big)

	var mx := int(state.get("max", 1))
	var ax := W * 0.16
	var up := _pick_arrow(det, "common_btn_up", Vector2(ax, cy - 62.0), func():
		state["cnt"] = 1 if cnt == mx else cnt + 1
		_gem_pick_detail(det, layer, state, on_pick))
	var dn := _pick_arrow(det, "common_btn_down", Vector2(ax, cy + 62.0), func():
		state["cnt"] = mx if cnt == 1 else cnt - 1
		_gem_pick_detail(det, layer, state, on_pick))
	up.disabled = mx <= 1
	dn.disabled = mx <= 1
	var num := Label.new()
	num.text = str(cnt)
	num.add_theme_font_size_override("font_size", 26)
	num.add_theme_color_override("font_color", Color(1.0, 0.83, 0.20))
	num.add_theme_color_override("font_outline_color", Color(0.25, 0.10, 0.02, 0.95))
	num.add_theme_constant_override("outline_size", 5)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.position = Vector2(ax - 50.0, cy - 18.0)
	num.size = Vector2(100.0, 36.0)
	det.add_child(num)

	var tb := AtlasUI.nine("ninepatch_ui", "9patch_text_box",
		Vector2(W - 10.0, 118.0), Rect2(25, 25, 3, 3))
	if tb:
		tb.position = Vector2(5.0, cy + 108.0)
		det.add_child(tb)
	var cm := Label.new()
	cm.text = "%s\n%s" % [Gem.effect_text(nm, tier, Data.gems),
		Gem.shape_label(nm, tier, Data.gems)]
	cm.add_theme_font_size_override("font_size", 15)
	cm.add_theme_color_override("font_color", Color(0.30, 0.17, 0.04))
	cm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cm.position = Vector2(20.0, cy + 120.0)
	cm.size = Vector2(W - 40.0, 96.0)
	det.add_child(cm)

	_frame_button(det, "선택", Vector2(W * 0.5 - 92.0, det.size.y - 74.0),
		Vector2(184.0, 54.0), func():
			layer.queue_free()
			on_pick.call(key, int(state["cnt"])), 0, false)

func _pick_arrow(parent: Control, frame: String, center: Vector2, cb: Callable) -> TextureButton:
	var b := TextureButton.new()
	var tx := AtlasUI.tex("common_ui", frame)
	if tx:
		b.texture_normal = tx
		b.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
		b.position = center - tx.get_size() * Design.ASSET_SCALE * 0.5
	else:
		b.position = center - Vector2(20, 14)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _note(text: String) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.82, 0.78, 0.92))
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.03, 0.12, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(500, 0)
	return l

func _kv_row(name: String, value: String, ok: bool) -> Control:
	var row := Control.new(); row.custom_minimum_size = Vector2(0, 44)
	var bgn := _row_bg(520, 44)
	if bgn: row.add_child(bgn)
	var l := Label.new(); l.text = name
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.95, 0.92, 1.0))
	l.position = Vector2(18, 11); row.add_child(l)
	var v := Label.new(); v.text = value
	v.add_theme_font_size_override("font_size", 16)
	v.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if ok else Color(1.0, 0.6, 0.55))
	v.position = Vector2(380, 11); row.add_child(v)
	return row

func _toast(msg: String, emo := 0) -> void:
	_say(msg, emo)
