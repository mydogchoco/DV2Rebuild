class_name AwakenSequence
extends RefCounted

const AWAKEN_LEVEL := 50
const AWAKEN_JEWELS := ["evol_jewel_6", "evol_jewel_5", "evol_jewel_4", "evol_jewel_3"]

const DRAGON_SCENE := "res://scenes/dragons/dragon_%d_%s.tscn"
const FX_AWAKE := "res://scenes/fx/evolution_effect.tscn"
const FX_WING := "res://scenes/fx/evolution_wing.tscn"
const FX_EFFECT2 := "res://scenes/fx/evolution_effect2.tscn"

const Z_BASE := 1
const Z_EVOL := 2
const Z_PRE := 1000
const Z_EFFECT2 := 3000
const Z_BURST := 4000
const Z_WING := 4090

const WING_SCALE := 0.5
const EFFECT2_SCALE := 0.5
const AWAKE_SCALE := 1.0
const AWAKE_TIMESCALE := 2.0
const DRAGON_START_SCALE := 0.9
const EVOL_DRAGON_SCALE := 1.1

static func open(host: Node, uid: int, start: Vector2, on_close := Callable()) -> void:
	var d: Dictionary = UserDB.get_dragon(uid)
	if d.is_empty() or not is_instance_valid(host):
		if on_close.is_valid(): on_close.call()
		return
	var ctx := {
		"host": host, "uid": uid, "on_close": on_close,
		"vis": host.get_viewport_rect().size,
	}
	_build(ctx, start)

static func _build(ctx: Dictionary, start: Vector2) -> void:
	var host: Node = ctx["host"]
	var vis: Vector2 = ctx["vis"]
	var layer := CanvasLayer.new()
	layer.layer = 95
	host.add_child(layer)
	ctx["layer"] = layer
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 100.0 / 255.0)
	back.position = Vector2.ZERO
	back.size = vis
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(back)
	var cont := Node2D.new()
	cont.position = Vector2(0, 50)
	layer.add_child(cont)
	ctx["cont"] = cont
	Bgm.sfx("effect_upgrade")
	_act_evol(ctx, start)

static func _cy(ctx: Dictionary, y: float) -> float:
	return float(ctx["vis"].y) - y

static func _dragon_scene(did: int, stage: String) -> String:
	var p := Icons.spine_scene(did, stage)
	return p if p != "" else DRAGON_SCENE % [did, stage]

static func _spine(path: String, anim: String, loop: bool, scale: float, pos: Vector2,
		z: int, parent: Node) -> Node2D:
	if not ResourceLoader.exists(path):
		push_warning("[AwakenSequence] 스파인 미빌드: %s" % path)
		return null
	var holder := Node2D.new()
	holder.position = pos
	holder.z_index = z
	holder.scale = Vector2(scale, scale)
	parent.add_child(holder)
	var inst = (load(path) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
	if ap and ap.has_animation(anim):
		ap.get_animation(anim).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		ap.play(anim)
		ap.advance(0.0)
	holder.set_meta("ap", ap)
	return holder

static func _visible_bounds(holder: Node2D) -> Rect2:
	var found := false
	var out := Rect2()
	var stack: Array[Node] = [holder]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.push_back(child)
		if node == holder or not (node is Sprite2D):
			continue
		var sprite := node as Sprite2D
		if not sprite.is_visible_in_tree() or sprite.texture == null:
			continue
		var r := sprite.get_rect()
		var rel := holder.global_transform.affine_inverse() * sprite.global_transform
		for corner in [r.position, Vector2(r.end.x, r.position.y), r.end,
				Vector2(r.position.x, r.end.y)]:
			var p: Vector2 = rel * corner
			if not found:
				out = Rect2(p, Vector2.ZERO)
				found = true
			else:
				out = out.expand(p)
	return out if found else Rect2()

static func _center_visible_at(holder: Node2D, target: Vector2) -> void:
	var bounds := _visible_bounds(holder)
	if bounds.size == Vector2.ZERO:
		holder.position = target
		return
	holder.position = target - holder.transform.basis_xform(bounds.get_center())

static func _dur(holder: Node2D, anim: String, fallback := 1.0) -> float:
	if not is_instance_valid(holder): return fallback
	var ap = holder.get_meta("ap")
	if ap is AnimationPlayer and (ap as AnimationPlayer).has_animation(anim):
		return (ap as AnimationPlayer).get_animation(anim).length
	return fallback

static func _act_evol(ctx: Dictionary, start: Vector2) -> void:
	var cont: Node2D = ctx["cont"]
	var d: Dictionary = UserDB.get_dragon(int(ctx["uid"]))
	var did := Icons.art_id_of(d)
	var stage := Growth.stage_for_level(int(d.get("level", 1)))
	var S := Design.ASSET_SCALE
	var pre := _spine(_dragon_scene(did, stage), "wait", true, DRAGON_START_SCALE * S,
		start - cont.position, Z_PRE, cont)
	ctx["pre"] = pre
	var burst := _spine(FX_AWAKE, "animation", false, AWAKE_SCALE * S,
		(start - cont.position) + Vector2(0, -60), Z_BURST, cont)
	if burst:
		var bap = burst.get_meta("ap")
		if bap is AnimationPlayer: (bap as AnimationPlayer).speed_scale = AWAKE_TIMESCALE
	var dur := _dur(burst, "animation", 1.2) / AWAKE_TIMESCALE
	var host: Node = ctx["host"]
	var t := cont.create_tween()
	t.tween_interval(0.1)
	t.tween_callback(func(): _draw_base(ctx))
	t.tween_interval(maxf(0.1, dur * 0.5))
	t.tween_callback(func(): _set_evol_dragon(ctx))
	t.tween_interval(0.3)
	t.tween_callback(func():
		if is_instance_valid(burst): burst.queue_free()
		if is_instance_valid(pre): pre.queue_free()
		_act_evol_wing(ctx))

static func _set_evol_dragon(ctx: Dictionary) -> void:
	var cont: Node2D = ctx["cont"]
	if not is_instance_valid(cont): return
	var vis: Vector2 = ctx["vis"]
	var uid := int(ctx["uid"])
	var d: Dictionary = UserDB.get_dragon(uid)
	var did := Icons.art_id_of(d)
	var S := Design.ASSET_SCALE
	var path := _dragon_scene(did, "e")
	if not ResourceLoader.exists(path):
		path = _dragon_scene(did, Growth.stage_for_level(int(d.get("level", 1))))
	var center := Vector2(vis.x * 0.23, _cy(ctx, vis.y * 0.5))
	var evol := _spine(path, "love", true, EVOL_DRAGON_SCALE * S, center, Z_EVOL, cont)
	if evol:
		_center_visible_at(evol, center)
	ctx["evol"] = evol
	ctx["evol_pos"] = evol.position if evol else center
	ctx["evol_center"] = center
	var btn := TextureButton.new()
	var bp := "res://assets/converted/common_ui/common_check_btn.tres"
	if ResourceLoader.exists(bp):
		btn.texture_normal = load(bp)
	btn.scale = Vector2(1.5 * S, 1.5 * S)
	btn.modulate.a = 0.0
	btn.pressed.connect(func(): _close(ctx))
	var bl: CanvasLayer = ctx["layer"]
	bl.add_child(btn)
	var bsz := (btn.texture_normal.get_size() if btn.texture_normal else Vector2(44, 44)) * btn.scale
	btn.position = Vector2(vis.x * 0.9, _cy(ctx, vis.y * 0.95)) - bsz * 0.5
	btn.create_tween().tween_property(btn, "modulate:a", 1.0, 0.5)
	ctx["btn"] = btn

static func _act_evol_wing(ctx: Dictionary) -> void:
	var cont: Node2D = ctx["cont"]
	if not is_instance_valid(cont): return
	var vis: Vector2 = ctx["vis"]
	var S := Design.ASSET_SCALE
	var h := vis.y
	var wing := _spine(FX_WING, "evolution", true, WING_SCALE * S,
		Vector2(vis.x * 0.5, _cy(ctx, -160.0)), Z_WING, cont)
	if wing == null:
		return
	var land := Vector2(float((ctx.get("evol_center", Vector2(vis.x * 0.23, 0)) as Vector2).x),
		_cy(ctx, vis.y - 90.0))
	var y0 := wing.position.y
	var y1 := y0 - (h / 3.0 + 200.0)
	var y3 := y1 - h / 3.0
	var t := wing.create_tween()
	t.tween_property(wing, "position:y", y1, 0.5)
	t.parallel().tween_property(wing, "scale", Vector2.ONE * (0.45 * S), 0.5)
	t.tween_property(wing, "scale", Vector2.ONE * (0.4 * S), 0.5)
	t.tween_property(wing, "position:y", y3, 0.5)
	t.parallel().tween_property(wing, "scale", Vector2.ONE * (0.85 * S), 0.5)
	t.tween_property(wing, "scale", Vector2.ONE * (0.7 * S), 0.25)
	t.tween_interval(0.25)
	var jump_from := Vector2(wing.position.x, y3)
	t.tween_property(wing, "scale", Vector2.ONE * (0.27 * S), 0.5)
	t.parallel().tween_method(
		func(p: float):
			if not is_instance_valid(wing): return
			wing.position = jump_from.lerp(land, p) + Vector2(0.0, -100.0 * sin(PI * p)),
		0.0, 1.0, 0.5)
	t.tween_callback(func(): _act_evol_effect(ctx))
	t.tween_property(wing, "scale", Vector2.ONE * (0.25 * S), 1.0 / 6.0)
	t.parallel().tween_property(wing, "position:y", land.y + 10.0, 1.0 / 6.0)
	t.tween_property(wing, "scale", Vector2.ONE * (0.27 * S), 1.0 / 6.0)
	t.parallel().tween_property(wing, "position:y", land.y, 1.0 / 6.0)

static func _act_evol_effect(ctx: Dictionary) -> void:
	var cont: Node2D = ctx["cont"]
	if not is_instance_valid(cont): return
	var S := Design.ASSET_SCALE
	var at: Vector2 = ctx.get("evol_center", Vector2(float(ctx["vis"].x) * 0.23, 0))
	var fx := _spine(FX_EFFECT2, "evolution_effect", false, EFFECT2_SCALE * S, at, Z_EFFECT2, cont)
	Bgm.sfx("effect_level_updown")
	if fx:
		var d := _dur(fx, "evolution_effect", 1.5)
		fx.create_tween().tween_interval(d).finished.connect(func():
			if is_instance_valid(fx): fx.queue_free())

static func _draw_base(ctx: Dictionary) -> void:
	var cont: Node2D = ctx["cont"]
	if not is_instance_valid(cont): return
	var vis: Vector2 = ctx["vis"]
	var S := Design.ASSET_SCALE
	var d: Dictionary = UserDB.get_dragon(int(ctx["uid"]))
	var ddef: Dictionary = Data.get_dragon(int(d.get("id", 0)))
	var base := Node2D.new()
	base.z_index = Z_BASE
	cont.add_child(base)
	ctx["base"] = base
	var dx := vis.x * 0.23
	var dy := _cy(ctx, vis.y * 0.5)
	var bl := _frame("common_ui", "common_backlight3", S)
	if bl:
		bl.position = Vector2(dx, dy - 40.0)
		base.add_child(bl)
		var s0 := bl.scale
		var bt := bl.create_tween().set_loops()
		bt.tween_property(bl, "scale", s0 + Vector2(0.2, 0.2), 6.0)
		bt.tween_property(bl, "scale", s0, 6.0)
	var sh := _frame("common_ui", "common_shadow", S)
	if sh:
		sh.position = Vector2(dx, dy + 30.0)
		base.add_child(sh)
	var nm := Label.new()
	nm.text = Icons.name_of(d)
	nm.add_theme_font_size_override("font_size", 24)
	nm.add_theme_color_override("font_color", Color.WHITE)
	nm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	nm.add_theme_constant_override("outline_size", 5)
	nm.position = Vector2(dx + 30.0, dy - 15.0)
	base.add_child(nm)
	var gr := Label.new()
	gr.text = "등급  %.1f" % _grade(d, ddef)
	gr.add_theme_font_size_override("font_size", 22)
	gr.add_theme_color_override("font_color", Color(1.0, 0.62, 0.12))
	gr.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	gr.add_theme_constant_override("outline_size", 5)
	gr.position = Vector2(vis.x * 0.55, _cy(ctx, vis.y * 0.72))
	base.add_child(gr)
	var bar_pos := Vector2(vis.x * 0.55, _cy(ctx, vis.y * 0.62))
	var bar_size := Vector2(300.0, 18.0)
	var need := LevelSystem.exp_to_next(Data.level_curve, int(d.get("level", 1)))
	var cur := int(d.get("exp", 0))
	var pct := clampf(float(cur) / maxf(1.0, float(need)), 0.0, 1.0)
	_gauge(base, bar_pos, bar_size, pct)
	var ic := _frame("adventure_ui", "scene_adventure_icon_exp", S * 0.8)
	if ic:
		ic.position = bar_pos + Vector2(-24, 9)
		base.add_child(ic)
	var sb: Dictionary = d.get("stat_bonus", {})
	var st := Growth.main_stats(ddef, Data.stat_table, d.get("gain_log", []), sb.get("base", {}))
	var rows := [
		["레벨", Color8(0x00, 0xe4, 0xff), str(int(d.get("level", 1)))],
		["생명력", Color8(0x7d, 0xed, 0xfa), str(int(st.get("hp", 0)))],
		["공격력", Color8(0x5f, 0x5f, 0xf1), str(int(st.get("att", 0)))],
		["방어력", Color8(0xff, 0x99, 0x67), str(int(st.get("def", 0)))],
	]
	for i in rows.size():
		var y := _cy(ctx, vis.y * 0.52) + i * 34.0
		var l := Label.new(); l.text = String(rows[i][0])
		l.add_theme_font_size_override("font_size", 21)
		l.add_theme_color_override("font_color", rows[i][1])
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 5)
		l.position = Vector2(vis.x * 0.55, y); base.add_child(l)
		var v := Label.new(); v.text = String(rows[i][2])
		v.add_theme_font_size_override("font_size", 21)
		v.add_theme_color_override("font_color", Color.WHITE)
		v.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		v.add_theme_constant_override("outline_size", 5)
		v.position = Vector2(vis.x * 0.55 + 120.0, y); base.add_child(v)
	var tt := Label.new(); tt.text = "각성 완료"
	tt.add_theme_font_size_override("font_size", 18)
	tt.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	tt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	tt.add_theme_constant_override("outline_size", 5)
	tt.position = Vector2(vis.x * 0.55, _cy(ctx, vis.y * 0.78)); base.add_child(tt)

static func _gauge(parent: Node2D, pos: Vector2, size: Vector2, pct: float) -> void:
	var bg := _stretch("common_ui", "common_bar_bg2", size)
	if bg: bg.position = pos; parent.add_child(bg)
	var clip := Control.new()
	clip.position = pos
	clip.size = Vector2(size.x * pct, size.y)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(clip)
	var fill := _stretch("common_ui", "common_bar_exp", size)
	if fill: clip.add_child(fill)
	var cov := _stretch("common_ui", "common_bar_cover", size)
	if cov: cov.position = pos; parent.add_child(cov)

static func _frame(dir: String, key: String, scale := 1.0) -> Sprite2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	if not ResourceLoader.exists(p): return null
	var s := Sprite2D.new()
	s.texture = load(p)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	s.material = m
	s.scale = Vector2(scale, scale)
	return s

static func _stretch(dir: String, key: String, size: Vector2) -> TextureRect:
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	if not ResourceLoader.exists(p): return null
	var t := TextureRect.new()
	t.texture = load(p)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.size = size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	t.material = m
	return t

static func _grade(d: Dictionary, ddef: Dictionary) -> float:
	return Growth.compute_grade(ddef, Data.stat_table, d.get("stat_bonus", {}),
		d.get("gain_log", []), Data.level_curve.get("grade", {}))

static func _close(ctx: Dictionary) -> void:
	var layer = ctx.get("layer")
	if is_instance_valid(layer): (layer as Node).queue_free()
	Bgm.sfx("effect_button")
	var cb = ctx.get("on_close")
	if cb is Callable and (cb as Callable).is_valid(): (cb as Callable).call()
