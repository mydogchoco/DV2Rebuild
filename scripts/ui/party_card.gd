class_name PartyCardView
extends RefCounted

const HP_BAR := "res://assets/converted/battle_extra/hp_bar10.png"
const BMF_SUBTITLE := "res://assets/converted/font_ui/font_subtitle.fnt"

static func build_row(host: Node, parent: Node, party: Array, vis: Vector2,
		pma: CanvasItemMaterial) -> Array:
	if party.is_empty():
		return []
	var adv := _man("adventure_ui")
	var S := Design.ASSET_SCALE
	var cw := float((adv.get("scene_adventure_stat_box3", {}) as Dictionary).get("w", 220)) * S
	var ch := float((adv.get("scene_adventure_stat_box3", {}) as Dictionary).get("h", 79)) * S
	var card_y := vis.y - 128.0 - ch
	var xs: Array[float] = []
	match party.size():
		1: xs = [20.0]
		2: xs = [20.0, vis.x * 0.5 - cw * 0.5]
		_: xs = [20.0, vis.x * 0.5 - cw * 0.5, vis.x - 20.0 - cw]
	var out: Array = []
	for i in party.size():
		out.append(_card(parent, i, party[i], xs[mini(i, xs.size() - 1)], card_y, cw, ch, adv, pma))
	return out

static func _card(parent: Node, idx: int, pd: Dictionary, x: float, y: float,
		w: float, ch: float, adv: Dictionary, pma: CanvasItemMaterial) -> Control:
	var S := Design.ASSET_SCALE
	var card := Control.new()
	card.set_meta("party_card", true)
	card.z_index = 400
	card.position = Vector2(x, y)
	card.size = Vector2(w, ch)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(card)
	var C := func(cx: float, cy: float) -> Vector2: return Vector2(cx, ch - cy)
	var bg := _spr("adventure_ui", "scene_adventure_stat_box3", S, pma)
	if bg:
		bg.position = Vector2(w * 0.5, ch * 0.5); card.add_child(bg)
	var frame := _spr("adventure_ui", "scene_adventure_stat_box_frame%d" % (idx % 3 + 1), S, pma)
	if frame:
		frame.position = Vector2(w * 0.5, ch * 0.5); card.add_child(frame)
	var ppos: Vector2 = C.call(50.0, ch * 0.5 + 3.0)
	var pbg := _spr("common_ui", "common_profile_bg", S, pma)
	if pbg:
		pbg.position = ppos; card.add_child(pbg)
	var id := Icons.art_id_of(pd)
	var stage := Growth.portrait_stage(pd)
	var por := _spr("portrait_%d" % id, "dragon_dragon_%d_box_%s" % [id, stage], 0.63 * S, pma)
	if por == null and stage == "evolution":
		por = _spr("portrait_%d" % id, "dragon_dragon_%d_box_adult" % id, 0.63 * S, pma)
	if por:
		por.position = ppos; card.add_child(por)
	var lv_org: Vector2 = C.call(ppos.x + 40.0, ch * 0.5 + 22.0) - Vector2(0, 22.0)
	var lvk := Label.new()
	lvk.text = "레벨"
	lvk.add_theme_font_size_override("font_size", 15)
	lvk.add_theme_color_override("font_color", Color8(0x35, 0x35, 0x35))
	lvk.position = lv_org + Vector2(0, 4.0)
	card.add_child(lvk)
	var lv := _bmf(0.75 * S)
	lv.text = "%d" % int(pd.get("level", 1))
	lv.add_theme_color_override("font_color", Color8(0x35, 0x35, 0x35))
	lv.position = lv_org + Vector2(32.0, 0.0)
	card.add_child(lv)
	var nm := Label.new()
	nm.text = String(pd.get("name", ""))
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", Color8(0x35, 0x35, 0x35))
	nm.position = lv_org + Vector2(66.0, 3.0)
	card.add_child(nm)
	var bar_w := 177.0
	var bar_h := 30.0
	var bar_org: Vector2 = C.call(97.0, 40.0 + bar_h)
	var hbg := _spr("adventure_ui", "scene_adventure_stat_box3_bg", S, pma)
	if hbg:
		hbg.position = bar_org + Vector2(bar_w * 0.5, bar_h * 0.5)
		card.add_child(hbg)
	var hp_max := maxi(1, int(pd.get("hp_max", 1)))
	var hp_now := clampi(int(pd.get("hp", hp_max)), 0, hp_max)
	var fill_w := (bar_w - 10.0) * (float(hp_now) / float(hp_max))
	if fill_w > 0.0:
		var hfl := NinePatchRect.new()
		if ResourceLoader.exists(HP_BAR):
			hfl.texture = load(HP_BAR)
		hfl.patch_margin_left = 8; hfl.patch_margin_right = 8
		hfl.patch_margin_top = 3; hfl.patch_margin_bottom = 3
		hfl.size = Vector2(fill_w, bar_h - 14.0)
		hfl.position = bar_org + Vector2(5.0, 7.0)
		hfl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(hfl)
	var hp := _bmf(0.8 * S)
	hp.text = "%d / %d" % [hp_now, hp_max]
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp.size = Vector2(bar_w, bar_h); hp.position = bar_org
	card.add_child(hp)
	var stats: Dictionary = pd.get("stats", {})
	var ay := ch * 0.5 - 19.0
	_stat_icon(card, "scene_adventure_att_icon-hd", int(stats.get("att", 0)),
		C.call(w * 0.5 - 50.0, ay), S, adv, pma)
	_stat_icon(card, "scene_adventure_def_icon-hd", int(stats.get("def", 0)),
		C.call(w * 0.5 + 30.0, ay), S, adv, pma)
	return card

const CURE_PARTICLE := "particle/scene/adventure/skill_29.plist"

static func build_cure_button(card: Control, potion_key: String, count: int, dead: bool,
		pma: CanvasItemMaterial, on_pressed: Callable) -> Control:
	var S := Design.ASSET_SCALE
	var adv := _man("adventure_ui")
	var w := card.size.x
	var btn := Control.new()
	btn.set_meta("cure_button", true)
	var bw := 92.0
	var bh := 56.0
	btn.size = Vector2(bw, bh)
	btn.position = Vector2(w * 0.17 - bw * 0.5, -bh)
	card.add_child(btn)
	var box := _spr("common_ui", "common_box", 0.7 * S, pma)
	if box:
		box.position = Vector2(bw * 0.5, bh * 0.5)
		box.modulate.a = 0.55
		btn.add_child(box)
	var ikey := "scene_adventure_icon_resurrection" if dead else "scene_adventure_icon_greencross"
	var ic := _spr("adventure_ui", ikey, 0.75 * S, pma)
	if ic:
		ic.position = Vector2(bw * 0.22, bh * 0.28)
		btn.add_child(ic)
	var pot := _spr("item_food", "item_food_%s" % potion_key, 0.42 * S, pma)
	if pot:
		pot.position = Vector2(bw * 0.5, bh * 0.62)
		btn.add_child(pot)
	var cl := Label.new()
	cl.text = "x%d" % count
	cl.add_theme_font_size_override("font_size", 17)
	cl.add_theme_color_override("font_color", Color(1, 1, 1))
	cl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	cl.add_theme_constant_override("outline_size", 4)
	cl.position = Vector2(bw * 0.72, bh * 0.42)
	cl.size = Vector2(46, 22)
	cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	btn.add_child(cl)
	btn.set_meta("count_label", cl)
	if count <= 0:
		btn.modulate = Color(0.55, 0.55, 0.55, 0.85)
	var hit := Button.new()
	hit.flat = true
	hit.size = Vector2(bw, bh)
	hit.disabled = count <= 0
	hit.pressed.connect(on_pressed)
	btn.add_child(hit)
	btn.pivot_offset = Vector2(bw * 0.5, bh)
	btn.scale = Vector2(0.6, 0.6)
	var tw := btn.create_tween()
	tw.tween_property(btn, "scale", Vector2(1.08, 1.08), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "scale", Vector2.ONE, 0.15)
	return btn

static func _stat_icon(parent: Control, frame: String, value: int, gpos: Vector2,
		s: float, adv: Dictionary, pma: CanvasItemMaterial) -> void:
	var info: Dictionary = adv.get(frame, {})
	var iw := float(info.get("w", 21)) * 0.9 * s
	var ih := float(info.get("h", 21)) * 0.9 * s
	var ic := _spr("adventure_ui", frame, 0.9 * s, pma)
	if ic:
		ic.position = gpos + Vector2(iw * 0.5, ih * 0.5)
		parent.add_child(ic)
	var lb := _bmf(0.6 * s)
	lb.text = str(value)
	lb.position = gpos + Vector2(iw + 2.0, -1.0)
	lb.size = Vector2(80, ih + 6.0)
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(lb)

static var _bmf_cache: Font = null

static func _bmf(scale := 1.0) -> Label:
	var l := Label.new()
	if _bmf_cache == null and ResourceLoader.exists(BMF_SUBTITLE):
		_bmf_cache = load(BMF_SUBTITLE)
	if _bmf_cache:
		l.add_theme_font_override("font", _bmf_cache)
		var base: float = float(_bmf_cache.fixed_size) if _bmf_cache.fixed_size > 0 else 32.0
		l.add_theme_font_size_override("font_size", int(round(base * scale)))
	else:
		l.add_theme_font_size_override("font_size", int(round(24.0 * scale)))
		l.add_theme_color_override("font_color", Color.WHITE)
	return l

static func _man(dir: String) -> Dictionary:
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

static func _spr(dir: String, name: String, scale: float, pma: CanvasItemMaterial) -> Sprite2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if not ResourceLoader.exists(p):
		return null
	var s := Sprite2D.new()
	s.texture = load(p)
	s.material = pma
	s.scale = Vector2(scale, scale)
	return s
