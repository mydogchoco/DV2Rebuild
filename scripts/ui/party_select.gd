class_name PartySelect
extends RefCounted

const LIST_BG := "res://assets/converted/ninepatch_ui/9patch_list_bg2.tres"
const BAR1 := "res://assets/converted/ninepatch_ui/9patch_bar1.tres"
const CLOSE_BTN := "res://assets/converted/common_ui/common_close_btn.tres"
const FONT_SUB := "res://assets/converted/font_ui/font_subtitle.fnt"
const FONT_RATING := "res://assets/converted/font_ui/font_rating.fnt"

const MAX_PARTY := 3
const CARD_W := 250.0
const CARD_H := 400.0

static func open_run(host: Node, current: Array, on_confirm: Callable) -> void:
	_build(host, current, on_confirm, true)

static func _man(dir: String) -> Dictionary:
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

static func _tex(dir: String, key: String) -> Texture2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	return load(p) if ResourceLoader.exists(p) else null

static func _spr(dir: String, key: String, scale: float, pma: CanvasItemMaterial) -> Sprite2D:
	var t := _tex(dir, key)
	if t == null:
		return null
	var s := Sprite2D.new()
	s.texture = t
	s.material = pma
	s.scale = Vector2(scale, scale)
	return s

static func _bmf(text: String, size: int, font_path := FONT_SUB) -> Label:
	var l := Label.new()
	l.text = text
	if ResourceLoader.exists(font_path):
		l.add_theme_font_override("font", load(font_path))
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func _ttf(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func _spine_node(id: int, stage: String, box_h: float) -> Node2D:
	for st in [stage, "adult", "child", "baby"]:
		var p := Icons.spine_scene(id, st)
		if p != "":
			var holder := Node2D.new()
			var inst = (load(p) as PackedScene).instantiate()
			holder.add_child(inst)
			var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
			if ap:
				for cand in ["wait", "animation", "idle"]:
					if ap.has_animation(cand):
						ap.get_animation(cand).loop_mode = Animation.LOOP_LINEAR
						ap.play(cand)
						break
			var r := _bounds(inst, Transform2D.IDENTITY)
			if r.size.y > 1.0:
				var k := minf(box_h / r.size.y, (box_h * 1.45) / maxf(r.size.x, 1.0))
				holder.scale = Vector2.ONE * k
				inst.position -= Vector2(r.get_center().x, r.position.y + r.size.y)
			else:
				holder.scale = Vector2.ONE * (box_h / 260.0)
			return holder
	return null

static func _bounds(n: Node, xf: Transform2D) -> Rect2:
	var out := Rect2()
	var has := false
	var my := xf
	if n is Node2D:
		my = xf * (n as Node2D).transform
	if n is Sprite2D:
		var s := n as Sprite2D
		if s.texture != null and s.visible:
			var sz: Vector2 = s.texture.get_size()
			var org: Vector2 = (-sz * 0.5 + s.offset) if s.centered else s.offset
			for cx in [0.0, sz.x]:
				for cy in [0.0, sz.y]:
					var pt: Vector2 = my * (org + Vector2(cx, cy))
					if has:
						out = out.expand(pt)
					else:
						out = Rect2(pt, Vector2.ZERO)
						has = true
	for c in n.get_children():
		var r := _bounds(c, my)
		if r.size != Vector2.ZERO or r.position != Vector2.ZERO:
			out = out.merge(r) if has else r
			has = true
	return out

static func _stage_of(d: Dictionary) -> String:
	return Growth.spine_stage(d)

static func _build(host: Node, current: Array, on_confirm: Callable,
		require_confirm: bool) -> void:
	var vis: Vector2 = host.get_viewport().get_visible_rect().size
	var pma := CanvasItemMaterial.new()
	pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	var overlay := CanvasLayer.new()
	overlay.layer = 30
	host.add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.size = vis
	overlay.add_child(dim)

	var picked: Array = []
	for u in current:
		if not UserDB.get_dragon(int(u)).is_empty() and picked.size() < MAX_PARTY:
			picked.append(int(u))

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(10.0, vis.y * 0.155)
	scroll.size = Vector2(vis.x - 20.0, CARD_H + 20.0)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	overlay.add_child(scroll)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 14)
	scroll.add_child(strip)

	var selected_state: Array = [[]]
	var go_state: Array = [null, null]
	var refresh_selected := func():
		var selected_cards: Array = selected_state[0]
		for old in selected_cards:
			if is_instance_valid(old):
				if old.get_parent() == overlay:
					overlay.remove_child(old)
				old.queue_free()
		selected_cards.clear()
		if not picked.is_empty():
			var party := PartyStats.summary(picked, false, "", {})
			selected_cards = PartyCardView.build_row(host, overlay, party, vis, pma)
		selected_state[0] = selected_cards
		for pc in selected_cards:
			if is_instance_valid(pc):
				pc.z_index = 20
		var gb = go_state[0]
		var gp = go_state[1]
		if gb is Button:
			(gb as Button).disabled = picked.is_empty()
		if gp is NinePatchRect:
			(gp as NinePatchRect).modulate = Color(0.24, 0.22, 0.22, 0.92) \
				if picked.is_empty() else Color.WHITE

	var repaint_all := func():
		for c in strip.get_children():
			if c.has_meta("paint"):
				(c.get_meta("paint") as Callable).call()
		refresh_selected.call()

	for d in UserDB.dragons():
		strip.add_child(_card(host, d, picked, pma, repaint_all))

	var dismiss := func(commit: bool):
		if commit:
			UserDB.clear_party()
			for u in picked:
				UserDB.toggle_party(int(u))
		if is_instance_valid(overlay):
			overlay.queue_free()
		if commit and on_confirm.is_valid():
			on_confirm.call(picked.duplicate())

	var go := Button.new()
	go.flat = true
	var go_np := NinePatchRect.new()
	if ResourceLoader.exists(BAR1):
		go_np.texture = load(BAR1)
	go_np.patch_margin_left = 12; go_np.patch_margin_right = 12
	go_np.patch_margin_top = 8; go_np.patch_margin_bottom = 8
	go_np.size = Vector2(150.0, 60.0)
	go_np.position = Vector2(vis.x * 0.72, vis.y * 0.075)
	overlay.add_child(go_np)
	var gl := _ttf("전투 시작", 28, Color.WHITE)
	gl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	gl.add_theme_constant_override("outline_size", 5)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gl.size = go_np.size
	go_np.add_child(gl)
	go.size = go_np.size
	go.pressed.connect(func(): dismiss.call(true))
	go_np.add_child(go)
	go_state[0] = go
	go_state[1] = go_np
	repaint_all.call()

	var close := TextureButton.new()
	if ResourceLoader.exists(CLOSE_BTN):
		close.texture_normal = load(CLOSE_BTN)
	close.position = Vector2(vis.x - 64.0, 12.0)
	close.pressed.connect(func(): dismiss.call(require_confirm))
	overlay.add_child(close)

static func _card(host: Node, d: Dictionary, picked: Array, pma: CanvasItemMaterial,
		repaint_all: Callable) -> Control:
	var S := Design.ASSET_SCALE
	var uid := int(d["uid"])
	var id := int(d["id"])
	var ddef: Dictionary = Data.get_dragon(id)
	var lv := int(d.get("level", 1))
	var down := UserDB.is_down(uid)

	var cell := Button.new()
	cell.flat = true
	cell.custom_minimum_size = Vector2(CARD_W, CARD_H)
	var bg := NinePatchRect.new()
	if ResourceLoader.exists(LIST_BG):
		bg.texture = load(LIST_BG)
	bg.patch_margin_left = 14; bg.patch_margin_right = 14
	bg.patch_margin_top = 14; bg.patch_margin_bottom = 14
	bg.size = Vector2(CARD_W, CARD_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(bg)

	var grade := Growth.compute_grade(ddef, Data.stat_table, d.get("stat_bonus", {}),
		d.get("gain_log", []), Data.level_curve.get("grade", {}))
	var rating := _bmf("%.1f" % grade, 27, FONT_RATING)
	rating.add_theme_color_override("font_color", Color(1.0, 0.62, 0.10))
	rating.add_theme_color_override("font_outline_color", Color(0.20, 0.10, 0.0, 0.9))
	rating.add_theme_constant_override("outline_size", 3)
	rating.position = Vector2(16.0, 6.0)
	rating.size = Vector2(62.0, 32.0)
	cell.add_child(rating)

	var nm := _ttf(Icons.name_of(d), 21, Color(0.2, 0.14, 0.05))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.position = Vector2(74.0, 10.0)
	nm.size = Vector2(CARD_W - 84.0, 26.0)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cell.add_child(nm)

	var boxc := Vector2(CARD_W * 0.5, 130.0)
	var dbg := _spr("adventure_ui", "scene_adventure_dragon_bg", S, pma)
	if dbg: dbg.position = boxc; cell.add_child(dbg)
	var box_h := 117.0 * S
	var lvl := _bmf("LV %d" % lv, 17)
	lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl.position = Vector2(10.0, boxc.y - box_h * 0.5 + 4.0)
	lvl.size = Vector2(CARD_W - 20.0, 20.0)
	cell.add_child(lvl)
	var elk := Icons.element_small_frame(Icons.element_of(d))
	if elk != "":
		var eb := _spr("item_small_ui", elk, 0.62 * S, pma)
		if eb:
			eb.position = Vector2(CARD_W - 44.0, boxc.y - box_h * 0.5 + 12.0)
			cell.add_child(eb)
	var feet := boxc + Vector2(0.0, box_h * 0.5 - 10.0)
	var sh := _spr("common_ui", "common_shadow", S, pma)
	if sh:
		sh.position = feet + Vector2(0.0, -4.0)
		cell.add_child(sh)
	var sp := _spine_node(Icons.art_id_of(d), _stage_of(d), box_h * 0.86)
	if sp:
		sp.position = feet
		cell.add_child(sp)
	var dfr := _spr("adventure_ui", "scene_adventure_dragon_frame", S, pma)
	if dfr: dfr.position = boxc; cell.add_child(dfr)

	var base := Growth.main_stats(ddef, Data.stat_table, d.get("gain_log", []),
		(d.get("stat_bonus", {}) as Dictionary).get("base", {}))
	var fin := PartyStats.with_awaken(d, EquipEffect.apply_static(
		PartyStats.resolve(d, ddef, {}, false, ""),
		d.get("equip", {}), Data.equip_effects))
	var rows := [
		["생명력", Color(0.32, 0.30, 0.78), "hp"],
		["공격력", Color(0.80, 0.22, 0.16), "att"],
		["방어력", Color(0.16, 0.38, 0.78), "def"]]
	var prows := [
		["치명타", "cri"], ["방어율", "blk"], ["회피율", "evd"]]
	for i in 3:
		var y := 222.0 + 27.0 * float(i)
		var lab := _ttf(String(rows[i][0]) + " :", 16, rows[i][1])
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lab.position = Vector2(0.0, y)
		lab.size = Vector2(72.0, 20.0)
		cell.add_child(lab)
		var k := String(rows[i][2])
		var b := int(base.get(k, 0))
		var extra := int(fin.get(k, b)) - b
		var val := _ttf("%d" % b, 16, Color(0.16, 0.16, 0.35))
		val.position = Vector2(76.0, y)
		val.size = Vector2(70.0, 20.0)
		cell.add_child(val)
		if extra != 0:
			var ex := _ttf("%+d" % extra, 15, Color(0.18, 0.62, 0.20))
			ex.position = Vector2(76.0 + 9.6 * float(("%d" % b).length()), y)
			ex.size = Vector2(60.0, 20.0)
			cell.add_child(ex)
		var pk := String(prows[i][1])
		var plab := _ttf(String(prows[i][0]) + " :", 16, Color(0.16, 0.38, 0.78))
		plab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		plab.position = Vector2(CARD_W * 0.55, y)
		plab.size = Vector2(58.0, 20.0)
		cell.add_child(plab)
		var pextra := int(fin.get(pk, 0)) - int(base.get(pk, 0))
		var pval := _ttf("%d%%" % pextra, 16, Color(0.16, 0.16, 0.35))
		pval.position = Vector2(CARD_W * 0.55 + 62.0, y)
		pval.size = Vector2(50.0, 20.0)
		cell.add_child(pval)

	var slot_y := CARD_H - 62.0
	var slot_types := Loadout.slot_types(d)
	var slot_frame := {"tri": "triangle", "sq": "square", "cir": "circle", "star": "star"}
	var awakened := bool(d.get("awakened", false))
	var shown_slots := Loadout.SKILL_SLOTS + (1 if awakened else 0)
	var slot_x := func(i: int) -> float:
		return CARD_W * 0.5 + (float(i) - float(shown_slots - 1) * 0.5) * 92.0
	if awakened:
		var ax: float = slot_x.call(0)
		var abg := _spr("common_ui", "common_skill_evolution_bg", 0.62 * S, pma)
		if abg:
			abg.position = Vector2(ax, slot_y)
			cell.add_child(abg)
		var awaken_no := int(d.get("awaken_skill", ddef.get("awaken_skill", 0)))
		var awaken_icon := Data.awaken_skill_icon(awaken_no) if awaken_no > 0 else 0
		var atex := _tex("skill_evolution", "skill_evolution_%d" % awaken_icon) \
			if awaken_icon > 0 else null
		if atex:
			var aic := Sprite2D.new()
			aic.texture = atex
			aic.material = pma
			aic.scale = Vector2.ONE * (0.5 * S)
			aic.position = Vector2(ax, slot_y)
			cell.add_child(aic)
	for si in Loadout.SKILL_SLOTS:
		var sx: float = slot_x.call(si + (1 if awakened else 0))
		var stype := String(slot_types[si]) if si < slot_types.size() else "star"
		var shape := String(slot_frame.get(stype, "star"))
		var e := Loadout.equipped_entry(d, si)
		var matched := not e.is_empty() and Loadout.slot_matches(stype,
			Data.skills.get(str(int(e.get("id", 0))), {}))
		var fkey := "common_skill_%s" % shape if matched else "common_skill_%s_bg" % shape
		var sbg := _spr("common_ui", fkey, 0.62 * S, pma)
		if sbg:
			sbg.position = Vector2(sx, slot_y)
			cell.add_child(sbg)
		if not Loadout.slot_unlocked(si, lv):
			var lk := _spr("common_ui", "common_lock", 0.7 * S, pma)
			if lk:
				lk.position = Vector2(sx, slot_y)
				cell.add_child(lk)
			continue
		if e.is_empty():
			continue
		var sid := int(e.get("id", 0))
		var stex := _tex("skill", "skill_%d" % sid)
		if stex:
			var ic := Sprite2D.new()
			ic.texture = stex
			ic.material = pma
			ic.scale = Vector2.ONE * (0.62 * S * 0.62 / 0.85)
			ic.position = Vector2(sx, slot_y)
			cell.add_child(ic)
		var slv := _ttf("%d" % int(e.get("level", 1)), 13, Color.WHITE)
		slv.add_theme_color_override("font_outline_color", Color(0.1, 0.35, 0.1, 0.95))
		slv.add_theme_constant_override("outline_size", 4)
		slv.position = Vector2(sx - 34.0, slot_y - 34.0)
		slv.size = Vector2(24.0, 18.0)
		cell.add_child(slv)

	var paint := func():
		if UserDB.is_down(uid):
			cell.modulate = Color.WHITE
			bg.modulate = Color.WHITE
			return
		var at := picked.find(uid)
		cell.modulate = Color(1, 1, 1)
		bg.modulate = Color(0.72, 0.84, 1.0) if at >= 0 else Color.WHITE
	cell.set_meta("paint", paint)

	if down:
		picked.erase(uid)

	cell.pressed.connect(func():
		if UserDB.is_down(uid):
			_open_recover_popup(host, uid, repaint_all)
			return
		var at := picked.find(uid)
		if at >= 0:
			picked.remove_at(at)
		elif picked.size() < MAX_PARTY:
			picked.append(uid)
		repaint_all.call())
	return cell

static func _open_recover_popup(host: Node, uid: int, repaint_all: Callable) -> void:
	var now := int(Time.get_unix_time_from_system())
	var ct := UserDB.cure_time(uid)
	var cost := Incapacitation.instant_cost(Data.incapacitation, ct, now)
	var msg := "회복까지 %s 남았습니다.\n드래곤을 즉시 부활시키겠습니까?" \
		% Incapacitation.remain_clock(ct, now)
	MessageWindow.open(host, "행동불능", msg,
		func():
			if not UserDB.spend("diamond", cost):
				MessageWindow.open(host, "행동불능", _ui("#76cd9cb3"), func(): pass,
					"확인", "")
				return
			UserDB.set_cure_time(uid, 0)
			Bgm.sfx("effect_button")
			repaint_all.call(),
		"확인", "취소", 0, cost)

static func _ui(key: String) -> String:
	return UiText.get_text(key)
