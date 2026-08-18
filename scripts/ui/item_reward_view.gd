class_name ItemRewardView
extends CanvasLayer

const DIM_ALPHA := 127.0 / 255.0
const LAYER_Z := 200
const SCALE_LAST := 1.25
const SCALE_REST := 0.85
const RADIUS_X_PAD := 200.0
const RADIUS_Y_PAD := 100.0
const TYPE4_Y := 50.0
const TYPE4_R := 30.0
const STAGGER := 0.25
const FADE := 0.3
const BTN_X_RATIO := 0.9
const BTN_Y_RATIO := 0.95
const BTN_Y_OFF := 50.0

signal closed

var _on_ok := Callable()
var _dim: ColorRect
var _root: Control

static func open(host: Node, items: Array, on_ok := Callable(), reward_type := 0) -> ItemRewardView:
	var p := ItemRewardView.new()
	p._on_ok = on_ok
	host.add_child(p)
	p._build(items, reward_type)
	return p

func _build(items: Array, reward_type: int) -> void:
	layer = LAYER_Z
	var vis: Vector2 = get_viewport().get_visible_rect().size

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, DIM_ALPHA)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	Bgm.sfx("effect_roulette")

	var n := items.size()
	var center := vis * 0.5
	for i in n:
		var e: Dictionary = items[i]
		var last := i == n - 1
		var pos := center
		if not last and n > 1:
			var a := TAU * float(i) / float(n - 1) - PI * 0.5
			var rx: float = vis.x * 0.5 - RADIUS_X_PAD
			var ry: float = vis.y * 0.5 - RADIUS_Y_PAD - (TYPE4_R if reward_type == 4 else 0.0)
			pos = center + Vector2(sin(a) * rx, -cos(a) * ry)
		if reward_type == 4:
			pos.y -= TYPE4_Y
		var node := _make_entry(e, SCALE_LAST if last else SCALE_REST)
		node.position = pos
		node.modulate.a = 0.0
		_root.add_child(node)
		var tw := create_tween()
		tw.tween_interval(STAGGER * float(i))
		tw.tween_property(node, "modulate:a", 1.0, FADE)

	var btn := _check_button()
	btn.position = Vector2(vis.x * BTN_X_RATIO,
		vis.y - (vis.y * BTN_Y_RATIO - BTN_Y_OFF))
	btn.modulate.a = 0.0
	_root.add_child(btn)
	var bt := create_tween()
	bt.tween_interval(STAGGER * float(maxi(1, n)))
	bt.tween_property(btn, "modulate:a", 1.0, FADE)
	_dim.gui_input.connect(func(_ev: InputEvent): pass)

func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		_close()

func _make_entry(e: Dictionary, scale_f: float) -> Node2D:
	var holder := Node2D.new()
	holder.scale = Vector2(scale_f, scale_f)
	var info := resolve(e)

	var bl := AtlasUI.spr("common_ui", "common_backlight3", Design.ASSET_SCALE * 0.9)
	if bl != null:
		bl.modulate = Color(1, 1, 1, 0.45)
		holder.add_child(bl)
		var tw := create_tween().set_loops()
		tw.tween_property(bl, "rotation", TAU, 6.0).from(0.0)

	var tex: Texture2D = info.get("tex")
	if tex != null:
		var icon := Sprite2D.new()
		icon.texture = tex
		icon.material = AtlasUI.pma()
		icon.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
		holder.add_child(icon)
		var tw2 := create_tween()
		tw2.tween_property(icon, "scale", icon.scale, 0.35) \
			.from(icon.scale * 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var ov: Texture2D = info.get("overlay")
		if ov != null:
			var ovs := Sprite2D.new()
			ovs.texture = ov
			ovs.material = AtlasUI.pma()
			ovs.position = (info.get("overlay_off", Vector2.ZERO) as Vector2)
			icon.add_child(ovs)

	var cnt := int(e.get("count", 1))
	var lb := Label.new()
	lb.text = "%s X %d" % [String(info.get("name", "")), cnt] if cnt > 1 \
		else String(info.get("name", ""))
	var f := _subtitle_font()
	if f != null:
		lb.add_theme_font_override("font", f)
	lb.add_theme_font_size_override("font_size", 20)
	lb.add_theme_color_override("font_color", Color.WHITE)
	lb.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.02, 0.9))
	lb.add_theme_constant_override("outline_size", 5)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.size = Vector2(260.0, 26.0)
	lb.position = Vector2(-130.0, 44.0)
	holder.add_child(lb)
	return holder

func _check_button() -> Control:
	var sz := AtlasUI.size_pt("common_ui", "common_check_btn")
	if sz == Vector2.ZERO:
		sz = Vector2(64.0, 64.0)
	var root := Control.new()
	root.size = sz
	root.pivot_offset = sz * 0.5
	var s := AtlasUI.spr("common_ui", "common_check_btn", Design.ASSET_SCALE)
	if s != null:
		s.position = sz * 0.5
		root.add_child(s)
	var b := Button.new()
	b.flat = true
	b.size = sz
	b.pressed.connect(_close)
	root.add_child(b)
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position -= sz * 0.5
	return root

func _close() -> void:
	closed.emit()
	if _on_ok.is_valid():
		_on_ok.call()
	queue_free()

static func resolve(e: Dictionary) -> Dictionary:
	var cur := String(e.get("currency", ""))
	if cur != "":
		var cname := "골드" if cur == "gold" else "다이아"
		return {"name": cname,
			"tex": AtlasUI.tex("common_ui", "common_coin" if cur == "gold" else "common_diamond"),
			"egg": false}
	var key := String(e.get("key", ""))
	var g := Gem.parse_item_key(key)
	if not g.is_empty():
		var gd: Dictionary = Gem.gem_def(String(g["name"]), Data.gems)
		return {"name": Gem.display_name(String(g["name"]), int(g["tier"]), Data.gems),
			"tex": Icons.gem_texture(String(gd.get("code", "")), int(g["tier"])), "egg": false}
	var ck := Equipment.parse_item_key(key)
	if ck != "":
		var it: Dictionary = Equipment.catalog(Data.equipment).get(ck, {})
		return {"name": String(it.get("name", ck)), "tex": Icons.equip_texture(it), "egg": false}
	var eg := EggGacha.item_def(key, Data.dragons)
	if not eg.is_empty():
		var did := int(eg.get("dragon_id", 0))
		return {"name": String(eg.get("name", "알")),
			"tex": Icons.dragon_egg_texture(did), "egg": true}
	var sk := Loadout.parse_item_key(key)
	if not sk.is_empty():
		var sd: Dictionary = Data.skills.get(str(int(sk["id"])), {})
		var sp := "res://assets/converted/skill/skill_%d.tres" % int(sk["id"])
		return {"name": "%s Lv.%d" % [String(sd.get("name", "스킬")), int(sk["level"])],
			"tex": AtlasUI.tex("common_ui", "common_skill_sroll"),
			"overlay": load(sp) if ResourceLoader.exists(sp) else null,
			"overlay_off": Vector2(1, 5), "egg": false}
	var ip := Data.item_icon_path(key)
	var nm := Data.item_name(key)
	return {"name": nm if nm != "" else key,
		"tex": load(ip) if ResourceLoader.exists(ip) else null,
		"egg": String(Data.get_item(key).get("category", "")) == "egg"}

static func _subtitle_font() -> Font:
	var p := "res://assets/converted/font_ui/font_subtitle.fnt"
	return load(p) if ResourceLoader.exists(p) else null
