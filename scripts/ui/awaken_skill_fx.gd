class_name AwakenSkillFx
extends RefCounted

const DIR_PREFIX := "ultimate_"

const DURATION := {
	"aqua": 11.0, "chaos": 10.65, "dark": 11.0, "earth": 9.0, "fire": 12.0,
	"holy": 11.25, "light": 11.25, "wind": 11.0, "shadow": 9.25,
}
const DURATION_ADV := {
	"aqua": 9.75, "chaos": 9.65, "dark": 9.75, "earth": 7.85, "fire": 9.25,
	"holy": 10.0, "light": 10.25, "wind": 9.4, "shadow": 9.25,
}
const DMG_TIME := {
	"aqua": 8.05, "chaos": 8.2, "dark": 8.65, "earth": 5.5, "fire": 7.8,
	"holy": 8.5, "light": 7.75, "wind": 8.0, "shadow": 8.0,
}

const LEAD := 1.0
const POS_RET := 0.5
const ACT_AT := LEAD + POS_RET + 0.75
const RUN_AT := ACT_AT + 0.5

const ELEMENT_DELAY := {
	"aqua": 1.25, "chaos": 1.4, "dark": 1.4, "earth": 1.25, "fire": 1.0,
	"holy": 0.75, "light": 1.4, "wind": 1.4, "shadow": 1.25,
}
const ELEMENT_DELAY_ON := ["fire", "aqua", "light", "wind", "earth", "dark", "shadow"]

static func elem_delay(el: String) -> float:
	return float(ELEMENT_DELAY.get(el, 0.0)) if ELEMENT_DELAY_ON.has(el) else 0.0

const VEIL_A := 200.0 / 255.0
const VEIL := {
	"aqua":   [["tint", 1.0, Color8(194, 255, 255)], ["wait", 3.0], ["tint", 1.0, Color8(25, 60, 125)],
		["wait", 0.75], ["fade", 0.5, 0.0]],
	"chaos":  [["tint", 3.0, Color8(200, 50, 25)], ["wait", 2.0], ["fade", 1.0, 0.0]],
	"dark":   [["wait", 1.0], ["tint", 3.3, Color8(23, 36, 74)], ["wait", 2.0], ["fade", 1.0, 0.0]],
	"earth":  [["wait", 5.75], ["fade", 0.25, 0.0]],
	"fire":   [["wait", 6.5], ["fade", 0.25, 0.0]],
	"holy":   [["wait", 6.75], ["fade", 0.25, 0.0]],
	"light":  [["wait", 6.75], ["fade", 0.25, 0.0]],
	"wind":   [["wait", 5.05], ["fade", 0.27, 0.0]],
	"shadow": [["tint", 0.2, Color8(0, 185, 205)], ["wait", 0.2], ["tint", 1.0, Color8(0, 70, 80)],
		["wait", 2.0], ["tint", 0.2, Color8(255, 255, 255)], ["wait", 0.2], ["fade", 0.5, 0.0]],
}

const Z_ACTOR := 10
const Z_VEIL := 0
const Z_FLASH := 250
const Z_WIND_WHIRL := 81
const Z_WIND_DEBRIS := 96
const Z_WIND_ZMOON := 99

static func _master_veil(host: CanvasItem, el: String, at: Vector2, sp: float) -> void:
	var r := _screen_veil(host, at, Color(0, 0, 0), Z_VEIL)
	var t := r.create_tween()
	t.tween_interval(LEAD / sp)
	t.tween_property(r, "color:a", VEIL_A, 1.0 / sp)
	t.tween_interval((RUN_AT - LEAD - 1.0) / sp)
	t.tween_interval(elem_delay(el) / sp)
	for step in VEIL.get(el, []):
		match String(step[0]):
			"wait":
				t.tween_interval(float(step[1]) / sp)
			"tint":
				var c: Color = step[2]
				t.tween_property(r, "color", Color(c.r, c.g, c.b, VEIL_A), float(step[1]) / sp)
			"fade":
				t.tween_property(r, "color:a", float(step[2]), float(step[1]) / sp)
	t.tween_callback(r.queue_free)

const SFX_ACT := {
	"chaos":  [[1.15, "effect_skill_21"], [6.1, "effect_cut_in"]],
	"dark":   [[0.75, "effect_skill_110"], [8.5, "effect_skill_110"]],
	"holy":   [[6.35, "effect_holy_wing"]],
	"light":  [[0.90, "effect_blink"], [1.80, "effect_blink"]],
	"shadow": [[0.75, "effect_skill_110"], [8.5, "effect_skill_110"]],
	"wind":   [[2.15, "effect_dragon_detach"], [2.9, "effect_dragon_detach"]],
}
const SFX_RUN_C := {
	"shadow": [[0.5, "effect_generate"]],
}
const SFX_RUN := {
	"aqua":   [[0.0, "effect_water_fill"], [1.0, "effect_water_in"],
		[5.45, "effect_bite"], [5.45, "effect_chaos_drop_2"], [6.25, "effect_water_in"]],
	"earth":  [[2.5, "effect_bomb"], [2.5, "effect_skill_50_destroy"],
		[3.05, "effect_bomb"], [3.05, "effect_bomb"],
		[3.15, "effect_skill_50_destroy"], [3.25, "effect_skill_50_destroy"],
		[3.35, "effect_skill_50_destroy"], [3.45, "effect_skill_50_destroy"]],
	"wind":   [[0.9, "effect_wind"], [1.4, "effect_wind"],
		[2.9, "effect_wind"], [3.15, "effect_wind"]],
	"light":  [[0.5, "effect_flash"], [1.6, "effect_bigbang"],
		[3.35, "effect_burn"], [5.35, "effect_bigbang"]],
	"dark":   [[0.0, "effect_circle"], [1.0, "effect_skill_110"], [1.0, "effect_skill_110"],
		[1.5, "effect_blackhall_2"], [4.75, "effect_blackhall_2"], [4.8, "effect_dark_clap"],
		[4.9, "effect_blackhall_1"], [5.9, "effect_blackhall_1"],
		[5.94, "effect_dark_explosion"], [5.94, "effect_bomb"]],
	"holy":   [[0.1, "effect_holy_well_1"], [0.95, "effect_holy_well_1"],
		[3.405, "effect_critical_ice_2"], [4.355, "effect_holy_fade"],
		[5.455, "effect_holy_well_1"], [5.455, "effect_holy_well_2"],
		[5.905, "effect_holy_well_2"], [6.155, "effect_holy_well_2"]],
	"chaos":  [[0.0, "effect_circle"], [0.0, "effect_chaos_drop_1"], [1.0, "effect_chaos_dust"],
		[4.0, "effect_chaos_drop_2"], [5.0, "effect_chaos_dust"],
		[5.5, "effect_chaos_explosion"], [5.5, "effect_circle"]],
	"shadow": [[0.0, "effect_circle"], [1.0, "effect_buildup"], [1.0, "effect_buildup"],
		[1.0, "effect_buildup"], [1.0, "effect_buildup"]],
}

static func sfx_at(host: CanvasItem, at_sec: float, track: String, sp: float,
		vol := 1.0) -> void:
	var tm := Timer.new()
	tm.one_shot = true
	tm.wait_time = maxf(0.01, at_sec / sp)
	tm.autostart = true
	tm.timeout.connect(func() -> void: Bgm.sfx(track, vol))
	host.add_child(tm)

static func _schedule_sfx(host: CanvasItem, el: String, sp: float) -> void:
	var d := elem_delay(el)
	for row in [[SFX_ACT, ACT_AT, 0.0], [SFX_RUN_C, RUN_AT, 0.0], [SFX_RUN, RUN_AT, d]]:
		var base: float = float(row[1]) + float(row[2])
		for e in (row[0] as Dictionary).get(el, []):
			sfx_at(host, base + float(e[0]), String(e[1]), sp)

const RING := {
	"aqua":   {"base": "circle1", "nest": "circle2", "sib": ["circle3", "circle3"]},
	"chaos":  {"base": "circle1", "nest": "circle2", "sib": ["circle3", "circle3"]},
	"dark":   {"base": "circle1", "nest": "circle2", "sib": ["circle3", "circle3"]},
	"earth":  {"base": "circle1", "nest": "circle2", "sib": ["circle3", "circle3"]},
	"fire":   {"base": "circle1", "nest": "",        "sib": ["circle2", "circle2"]},
	"holy":   {"base": "circle1", "nest": "circle2", "sib": ["circle3", "circle3"]},
	"light":  {"base": "circle1", "nest": "circle2", "sib": ["circle3", "circle3"]},
	"wind":   {"base": "circle1", "nest": "circle2", "sib": ["circle3", "circle3"]},
	"shadow": {"base": "marsh1",  "nest": "",        "sib": ["circle1", "circle2", "circle2"]},
}
const RING_EXTRA := {"dark": "shade", "shadow": "twist"}
const RING_SPINE := {
	"holy": {"scene": "res://scenes/fx/ultimate_holy_wing.tscn", "anim": "animation"},
}
const SHADOW_SPINE_SCENE := "res://scenes/fx/ultimate_shadow.tscn"
const RING_DY := 87.5

const RING_FADE_IN := 0.25
const RING_LEAD := 0.15
const RING_HOLD := 0.25
const RING_BURST := 0.25
const RING_BURST_MUL := 10.0
const RING_DIM := 0.1
const RING_OUT := 0.15
const SIB_LEAD := 0.4
const SIB_MID := 125.0 / 255.0
const FIRE_BOB := 2.5
const FIRE_BOB_SEC := 0.25
const FIRE_SHRINK_SEC := 4.1
const FIRE_SHRINK := 0.85
const FIRE_DIM_SEC := 3.85
const FIRE_DIM := 100.0 / 255.0
const SHADOW_LEAD := 0.5
const SHADOW_HOLD := 0.5
const SHADOW_SIB_LEAD := 1.5
const SHADOW_SIB_POP := 1.125
const SHADOW_SIB_BURST := 3.25

const RING_AT := {"chaos": LEAD}
const RING_BURST_CAP := {"chaos": 2.5, "earth": 3.0}

static func ring_at_sec(el: String) -> float:
	return float(RING_AT.get(el, RUN_AT))

const FIRE_POINTS := [
	[0.25, 0.0, -110.0], [-0.25, 0.0, -80.0], [0.0, 0.0, -130.0],
	[0.25, -50.0, -70.0], [-0.25, 25.0, -90.0], [0.25, 30.0, -145.0],
	[0.0, -30.0, -150.0], [0.0, -60.0, -140.0], [0.25, -75.0, -77.5],
	[-0.25, -25.0, -120.0], [0.25, 5.0, -160.0], [-0.25, 10.0, -70.0],
	[0.0, 10.0, -160.0], [0.25, -45.0, -70.0], [-0.25, 30.0, -60.0],
	[0.25, 0.0, -170.0], [0.0, -17.5, -110.0], [-0.25, 0.0, -175.0],
	[0.25, -55.0, -80.0], [0.0, 90.0, -200.0],
]
const FIRE_DELAYS := [
	0.25, 1.0, 1.65, 2.15, 2.6, 3.0, 3.3, 3.55, 3.7, 3.85,
	4.0, 4.125, 4.25, 4.375, 4.5, 4.625, 4.75, 4.875, 5.0, 5.1,
]
const FIRE_Z := [5, 2, 7, 1, 4, 9, 10, 8, 3, 6, 11, 2, 13, 3, 1, 16, 1, 18, 4, 20]
const FIRE_EXPL_SEC := 0.06
const FIRE_PILLAR_SEC := 0.03
const FIRE_STONE_MIN := 14
const FIRE_START_SX := 0.5
const FIRE_LAG := 0.225
const FIRE_FLASH_AT := 4.25
const FIRE_FLASH_IN := 1.0
const FIRE_FLASH_HOLD := 1.0
const FIRE_FLASH_OUT := 0.5

const FB_LEAD := 0.5
const FB_FRAME_SEC := 0.06
const FB_POP_SEC := 0.1
const FB_POP_MUL := 1.25
const FB_DRIFT_SEC := 0.2
const FB_DRIFT_K := 0.01
const FB_DASH_SEC := 0.1
const FB_FADE_AT := 0.05
const FB_FADE_SEC := 0.05
const FB_SPREAD := 301
const FB_UP_MIN := 100.0
const FB_UP_RAND := 75
const FB_CASTER_W := 170.0

const DUST_EL := "earth"
const FIRE_DUST_AT := [0.0, 4.3, 5.3]
const DUST_UP := 80.0

const FALLBACK_FRAME_SEC := 0.08

const BASE_EDGE := {"earth": 225.0, "fire": 225.0, "shadow": 225.0, "aqua": 335.0}

static func base_at(host: CanvasItem, el: String, mine: bool) -> Vector2:
	var vis: Vector2 = host.get_viewport().get_visible_rect().size
	var p: Vector2
	match el:
		"earth", "fire", "shadow":
			p = Vector2((vis.x - BASE_EDGE[el]) if mine else BASE_EDGE[el],
				vis.y * 0.5 + 50.0)
		"aqua":
			p = Vector2((vis.x - BASE_EDGE[el]) if mine else BASE_EDGE[el],
				vis.y - 262.5)
		"wind", "dark", "chaos":
			p = Vector2(vis.x * 0.5, vis.y - 167.5)
		"holy":
			p = Vector2(vis.x * 0.5, vis.y - 262.5)
		_:
			p = vis * 0.5
	return host.get_global_transform_with_canvas().affine_inverse() * p

static func play(host: CanvasItem, ctx: Dictionary) -> float:
	if not is_instance_valid(host) or not host.is_inside_tree():
		return 0.0
	var el := String(ctx.get("element", ""))
	var man := manifest(el)
	if man.is_empty():
		return 0.0
	var mine := bool(ctx.get("mine", true))
	var at := base_at(host, el, mine)
	var ring_at: Vector2 = ctx.get("ring_at", at)
	var foes: Array = ctx.get("foes", [])
	var caster_w := float(ctx.get("caster_w", 0.0))
	var s := float(ctx.get("scale", 1.0))
	var ctr := _screen_center(host)
	var dir := 1.0 if at.x <= ctr.x else -1.0
	var sp := maxf(0.05, float(ctx.get("speed", 1.0)))
	var alive: Callable = ctx.get("alive", Callable())
	var mat: CanvasItemMaterial = ctx.get("mat", null)
	if mat == null:
		mat = CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA

	_master_veil(host, el, at, sp)
	_schedule_sfx(host, el, sp)
	var vis_c: Vector2 = host.get_viewport().get_visible_rect().size
	var combine_at: Vector2 = host.get_global_transform_with_canvas().affine_inverse() \
		* Vector2(vis_c.x * 0.5, vis_c.y - 167.5)
	var run_body := func() -> void:
		if alive.is_valid() and not bool(alive.call()):
			return
		if not is_instance_valid(host) or not host.is_inside_tree():
			return
		_combine_outline(host, el, combine_at, sp)
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		match el:
			"fire":   _run_fire(host, at, ring_at, s, dir, sp, mat, alive, caster_w)
			"earth":  _run_earth(host, at, dir, sp, rng)
			"aqua":   _run_aqua(host, at, ring_at, dir, sp, rng)
			"wind":   _run_wind(host, at, dir, sp, rng)
			"dark":   _run_dark(host, at, dir, sp, rng)
			"light":  _run_light(host, at, dir, sp, rng)
			"holy":   _run_holy(host, at, dir, sp, rng)
			"chaos":  _run_chaos(host, at, dir, sp, rng)
			"shadow": _run_shadow(host, at, sp, foes)
			_:        _run_fallback(host, el, at, sp, mat, alive)
	var start := Timer.new()
	start.one_shot = true
	start.wait_time = RUN_AT / sp
	start.autostart = true
	start.timeout.connect(run_body)
	host.add_child(start)

	var ring_body := func() -> void:
		if alive.is_valid() and not bool(alive.call()):
			return
		if not is_instance_valid(host) or not host.is_inside_tree():
			return
		_build_ring(host, el, ring_at, s, sp, mat)
	var rt := Timer.new()
	rt.one_shot = true
	rt.wait_time = maxf(0.01, ring_at_sec(el) / sp)
	rt.autostart = true
	rt.timeout.connect(ring_body)
	host.add_child(rt)
	return float(DURATION.get(el, 9.0)) / sp

static func damage_at(element: String, speed := 1.0) -> float:
	return float(DMG_TIME.get(element, 8.0)) / maxf(0.05, speed)

static func _build_ring(host: CanvasItem, el: String, at: Vector2, s: float,
		sp: float, mat: CanvasItemMaterial) -> void:
	var cfg: Dictionary = RING.get(el, {})
	if cfg.is_empty():
		return
	var pfx := prefix(el)
	var pos := at + Vector2(0.0, s * RING_DY)

	var base := _spr(el, pfx + String(cfg["base"]))
	if base != null:
		base.position = pos
		base.z_index = 90
		base.modulate.a = 0.0
		var nat := base.scale
		if el == "shadow":
			base.scale = Vector2.ZERO
		else:
			base.scale *= (s + 0.25)
		host.add_child(base)
		if String(cfg.get("nest", "")) != "":
			var nest := _spr(el, pfx + String(cfg["nest"]))
			if nest != null:
				nest.z_index = -1
				nest.modulate.a = 0.0
				base.add_child(nest)
		if el == "shadow":
			_play_frames(base, el, pfx + "marsh%d", 1, 3, 0.2 / sp, false, true)
		_anim_ring_base(base, el, s, sp, nat)

	var sibs: Array = cfg.get("sib", [])
	for i in sibs.size():
		var sib := _spr(el, pfx + String(sibs[i]))
		if sib == null:
			continue
		sib.position = pos
		sib.z_index = 89
		sib.modulate.a = 0.0
		host.add_child(sib)
		_anim_ring_sib(sib, el, sp, i, s)

	var ex := String(RING_EXTRA.get(el, ""))
	if ex != "":
		var e := _spr(el, pfx + ex)
		if e != null:
			e.z_index = 95
			e.modulate.a = 0.0
			host.add_child(e)
			_ring_flash(e, at, sp, el)

	if el == "earth":
		var qoff := [Vector2(-100, -100), Vector2(-50, -70), Vector2(-10, -120),
			Vector2(-10, -95), Vector2(0, -100)]
		for i in qoff.size():
			var q := _spr(el, pfx + "earthquake1")
			if q == null:
				break
			q.position = pos + (qoff[i] as Vector2) * s
			q.scale *= s * 1.25
			q.z_index = 94
			q.modulate.a = 0.0
			host.add_child(q)
			var qt := q.create_tween()
			qt.tween_interval(EARTH_WAVES[i % EARTH_WAVES.size()] / sp)
			qt.tween_property(q, "modulate:a", 1.0, 0.2 / sp)
			qt.tween_interval(2.2 / sp)
			qt.tween_property(q, "modulate:a", 0.0, 0.75 / sp)
			qt.tween_callback(q.queue_free)
		for k in 2:
			var du := _spr(el, pfx + ("dust1" if k == 0 else "dust2"))
			if du == null:
				break
			du.position = pos + Vector2(-40.0 + 80.0 * float(k), -30.0)
			du.z_index = 96
			du.modulate.a = 0.0
			host.add_child(du)
			var dt := du.create_tween()
			dt.tween_interval(0.4 / sp)
			dt.tween_property(du, "modulate:a", 1.0, 0.3 / sp)
			dt.parallel().tween_property(du, "scale", du.scale * 1.35, 4.0 / sp)
			dt.tween_interval(3.2 / sp)
			dt.tween_property(du, "modulate:a", 0.0, 0.75 / sp)
			dt.tween_callback(du.queue_free)
		var rng2 := RandomNumberGenerator.new()
		rng2.randomize()
		for k in 8:
			var st := _spr(el, pfx + "stone")
			if st == null:
				break
			st.position = pos + Vector2(rng2.randf_range(-90.0, 90.0),
				rng2.randf_range(-70.0, 10.0))
			st.scale *= s * (float(rng2.randi() % 0x4c + 0x19) / 100.0)
			st.z_index = 95
			st.modulate.a = 0.0
			host.add_child(st)
			var stt := st.create_tween()
			stt.tween_interval((EARTH_WAVES[k % EARTH_WAVES.size()]
				+ float(rng2.randi() % 3) * 0.05) / sp)
			stt.tween_property(st, "modulate:a", 1.0, 0.2 / sp)
			stt.tween_interval(2.2 / sp)
			stt.tween_property(st, "modulate:a", 0.0, 0.6 / sp)
			stt.tween_callback(st.queue_free)

	var spn: Dictionary = RING_SPINE.get(el, {})
	if not spn.is_empty() and ResourceLoader.exists(String(spn["scene"])):
		var holder := Node2D.new()
		holder.position = pos
		holder.z_index = 96
		host.add_child(holder)
		var inst = (load(String(spn["scene"])) as PackedScene).instantiate()
		holder.add_child(inst)
		var ap := _find_anim_player(inst)
		if ap != null and ap.has_animation(String(spn["anim"])):
			ap.play(String(spn["anim"]))
		var life := holder.create_tween()
		life.tween_interval(maxf(1.0, (float(DURATION.get(el, 9.0)) - RUN_AT - 0.75)) / sp)
		life.tween_property(holder, "modulate:a", 0.0, 0.75 / sp)
		life.tween_callback(holder.queue_free)

static func _anim_ring_base(n: Node2D, el: String, s: float, sp: float,
		nat := Vector2.ONE) -> void:
	var t := n.create_tween()
	match el:
		"fire":
			var bob := n.create_tween().set_loops()
			bob.tween_property(n, "position:y", n.position.y - FIRE_BOB, FIRE_BOB_SEC / sp)
			bob.tween_property(n, "position:y", n.position.y, FIRE_BOB_SEC / sp)
			t.tween_interval(RING_LEAD / sp)
			t.tween_property(n, "modulate:a", 1.0, RING_FADE_IN / sp)
			t.parallel().tween_property(n, "scale", n.scale * FIRE_SHRINK, FIRE_SHRINK_SEC / sp)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t.tween_property(n, "modulate:a", FIRE_DIM, FIRE_DIM_SEC / sp)
		"shadow":
			t.tween_interval(SHADOW_LEAD / sp)
			_fade_pma(t, n, 1.0, RING_FADE_IN / sp)
			t.parallel().tween_property(n, "scale", nat * (s + 0.25), RING_BURST / sp)
			t.tween_interval(SHADOW_HOLD / sp)
			_fade_pma(t, n, 0.0, RING_FADE_IN / sp)
		_:
			t.tween_interval(RING_LEAD / sp)
			t.tween_property(n, "modulate:a", 1.0, RING_FADE_IN / sp)
			t.tween_interval(RING_HOLD / sp)
			t.tween_property(n, "scale",
				n.scale * float(RING_BURST_CAP.get(el, RING_BURST_MUL)), RING_BURST / sp)
			t.parallel().tween_property(n, "modulate:a", 25.0 / 255.0, RING_DIM / sp)
			t.tween_property(n, "modulate:a", 0.0, RING_OUT / sp)
	t.tween_callback(n.queue_free)

const DARK_SHADE_AT := ACT_AT + 0.75
const DARK_SHADE_GAP := 7.25
const DARK_SHADE_S := 1.75
const SHADOW_TWIST_DROP := 50.0

static func _ring_flash(e: Node2D, at: Vector2, sp: float, el: String) -> void:
	e.position = at
	var base := e.scale
	e.scale = Vector2.ZERO
	var first := maxf(0.01, DARK_SHADE_AT - ring_at_sec(el))
	var t := e.create_tween()
	for pass_i in 2:
		t.tween_interval((first if pass_i == 0 else DARK_SHADE_GAP) / sp)
		t.tween_property(e, "scale", base * DARK_SHADE_S, 0.25 / sp)
		t.parallel().tween_property(e, "modulate:a", 1.0, 0.25 / sp)
		t.parallel().tween_property(e, "rotation_degrees", 360.0, 0.25 / sp).as_relative()
		if pass_i == 0:
			t.tween_property(e, "scale", Vector2.ZERO, 0.25 / sp)
			t.parallel().tween_property(e, "modulate:a", 0.0, 0.25 / sp)
		else:
			t.tween_property(e, "modulate:a", 0.0, 0.25 / sp)
			if el == "shadow":
				t.parallel().tween_property(e, "position",
					Vector2(0.0, SHADOW_TWIST_DROP), 0.25 / sp).as_relative()
		t.parallel().tween_property(e, "rotation_degrees", 360.0, 0.25 / sp).as_relative()
	t.tween_callback(e.queue_free)

static func _anim_ring_sib(n: Node2D, el: String, sp: float, idx: int, s := 1.0) -> void:
	var t := n.create_tween()
	if el == "earth":
		t.tween_interval(1.05 / sp)
		t.tween_property(n, "modulate:a", 1.0, 4.25 / sp)
		t.tween_property(n, "modulate:a", 0.0, 0.25 / sp)
	elif el == "chaos":
		t.tween_interval(0.05 * float(idx) / sp)
		t.tween_property(n, "modulate:a", 1.0, 0.1 / sp)
		t.tween_property(n, "scale", n.scale * 6.0, 0.15 / sp)
		t.parallel().tween_property(n, "modulate:a", 0.0, 0.15 / sp)
	elif el == "shadow":
		var nat := n.scale
		if idx == 0:
			_set_alpha(n, 0.0)
		else:
			_set_alpha(n, 1.0)
			n.scale = Vector2.ZERO
		t.tween_interval(SHADOW_SIB_LEAD / sp)
		if idx == 0:
			_fade_pma(t, n, 1.0, RING_FADE_IN / sp)
			_fade_pma(t, n, SIB_MID, 0.01 / sp)
			_fade_pma(t, n, 0.0, RING_OUT / sp)
		else:
			t.tween_property(n, "scale", nat * (s + 0.25) * SHADOW_SIB_POP, 0.1 / sp)
			if idx == 1:
				t.tween_property(n, "scale", nat * (s + 0.25), 0.05 / sp)
				_fade_pma(t, n, 0.0, RING_FADE_IN / sp)
			else:
				t.tween_property(n, "scale",
					nat * (s + 0.25) * SHADOW_SIB_BURST, RING_FADE_IN / sp)
				_fade_pma(t.parallel(), n, 0.0, RING_FADE_IN / sp)
	else:
		t.tween_interval((SIB_LEAD + 0.1 * float(idx)) / sp)
		t.tween_property(n, "modulate:a", 1.0, RING_FADE_IN / sp)
		t.tween_property(n, "modulate:a", SIB_MID, 0.01 / sp)
		t.tween_property(n, "modulate:a", 0.0, RING_OUT / sp)
	t.tween_callback(n.queue_free)

static func _run_fire(host: CanvasItem, at: Vector2, ring_at: Vector2, s: float, dir: float,
		sp: float, mat: CanvasItemMaterial, alive: Callable, caster_w: float) -> void:
	var pfx := prefix("fire")
	var vis: Vector2 = host.get_viewport().get_visible_rect().size
	var w_half := vis.x * 0.5
	dir = -dir
	var ed := elem_delay("fire")
	var k := 1.0 if at.x >= ring_at.x else -1.0
	var flip := -k
	var cw := caster_w if caster_w > 1.0 else FB_CASTER_W
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in FIRE_POINTS.size():
		var p: Array = FIRE_POINTS[i]
		var pos := at + Vector2(dir * (w_half * float(p[0]) + float(p[1])), -float(p[2]))
		var z := 90 + int(FIRE_Z[i]) * 5
		_fire_burst(host, pfx, pos, z, (ed + float(FIRE_DELAYS[i])) / sp,
			rng.randi() % 6 + FIRE_STONE_MIN, s, sp, mat, alive, rng)
		var from := ring_at + Vector2(k * (-0.5 * cw + float(rng.randi() % FB_SPREAD)),
			-(FB_UP_MIN + float(rng.randi() % FB_UP_RAND)))
		_fire_ball(host, pfx, from, pos, z, (ed + float(FIRE_DELAYS[i]) - FB_LEAD) / sp,
			flip, s, sp, alive)

	var dust_at := ring_at + Vector2(0.0, s * RING_DY - DUST_UP)
	for d in FIRE_DUST_AT:
		_ring_dust(host, dust_at, float(d) / sp, s, sp, rng, alive)

	var flash := _screen_veil(host, at, Color(1, 1, 1), Z_FLASH)
	var ft := flash.create_tween()
	ft.tween_interval((ed + FIRE_FLASH_AT) / sp)
	ft.tween_property(flash, "color:a", 1.0, FIRE_FLASH_IN / sp)
	ft.tween_interval(FIRE_FLASH_HOLD / sp)
	ft.tween_property(flash, "color:a", 0.0, FIRE_FLASH_OUT / sp)
	ft.tween_callback(flash.queue_free)

static func _fire_ball(host: CanvasItem, pfx: String, from: Vector2, to: Vector2,
		z: int, delay: float, flip: float, s: float, sp: float, alive: Callable) -> void:
	var n := _spr("fire", pfx + "fireball1")
	if n == null:
		return
	n.position = from
	n.z_index = z
	n.scale = Vector2.ZERO
	host.add_child(n)
	var drift: Vector2 = (from + to) * FB_DRIFT_K
	var t := n.create_tween()
	t.tween_interval(maxf(0.01, delay))
	t.tween_callback(func() -> void:
		if not is_instance_valid(n):
			return
		if alive.is_valid() and not bool(alive.call()):
			n.queue_free()
			return
		_loop_frames(n, "fire", pfx + "fireball%d", 1, 4, FB_FRAME_SEC / sp))
	t.tween_property(n, "scale", Vector2(flip * s * FB_POP_MUL, s * FB_POP_MUL), FB_POP_SEC / sp)
	t.tween_callback(func() -> void: Bgm.sfx("effect_critical_fire_1", 0.5))
	t.tween_property(n, "scale", Vector2(flip * s, s), FB_POP_SEC / sp)
	t.tween_property(n, "position", drift, FB_DRIFT_SEC / sp).as_relative()
	t.tween_callback(func() -> void:
		if not is_instance_valid(n):
			return
		var f := n.create_tween()
		f.tween_interval(FB_FADE_AT / sp)
		f.tween_property(n, "modulate:a", 0.0, FB_FADE_SEC / sp))
	t.tween_property(n, "position", to, FB_DASH_SEC / sp)
	t.tween_callback(n.queue_free)

static func _ring_dust(host: CanvasItem, at: Vector2, delay: float, s: float,
		sp: float, rng: RandomNumberGenerator, alive: Callable) -> void:
	var dpfx := prefix(DUST_EL)
	var d1 := _spr(DUST_EL, dpfx + "dust1")
	if d1 == null:
		return
	var b1: Vector2 = d1.scale
	d1.position = at + Vector2(0.0, DUST_UP * s)
	d1.z_index = 92
	d1.scale = b1 * 0.2
	d1.visible = false
	host.add_child(d1)

	var show := func(n: Node2D) -> void:
		if not is_instance_valid(n):
			return
		if alive.is_valid() and not bool(alive.call()):
			n.queue_free()
			return
		n.visible = true

	var t1 := d1.create_tween()
	t1.tween_interval(maxf(0.01, delay))
	t1.tween_callback(show.bind(d1))
	t1.tween_property(d1, "scale", b1 * 0.5, 0.25 / sp)
	t1.tween_property(d1, "scale", Vector2(b1.x * 0.75, b1.y * 0.5), 1.5 / sp)
	t1.tween_callback(d1.queue_free)
	var f1 := d1.create_tween()
	f1.tween_interval(maxf(0.01, delay) + 0.75 / sp)
	f1.tween_property(d1, "modulate:a", 0.0, 1.0 / sp)

	var d2 := _spr(DUST_EL, dpfx + "dust2")
	if d2 == null:
		return
	var b2: Vector2 = d2.scale
	d2.position = d1.position + Vector2(float(rng.randi() % 200) - 100.0, -75.0)
	d2.z_index = d1.z_index + 10
	d2.scale = b2 * 0.5
	d2.visible = false
	host.add_child(d2)

	var t2 := d2.create_tween()
	t2.tween_interval(maxf(0.01, delay))
	t2.tween_callback(show.bind(d2))
	t2.tween_property(d2, "position",
		Vector2(float(rng.randi() % 150) - 75.0, -50.0), 1.85 / sp).as_relative()
	t2.parallel().tween_property(d2, "scale", b2 * 0.75, 1.85 / sp)
	t2.tween_callback(d2.queue_free)
	var f2 := d2.create_tween()
	f2.tween_interval(maxf(0.01, delay) + 0.75 / sp)
	f2.tween_property(d2, "modulate:a", 0.0, 1.1 / sp)

static func _fire_burst(host: CanvasItem, pfx: String, pos: Vector2, zbase: int,
		delay: float, n_stone: int, s: float, sp: float, mat: CanvasItemMaterial,
		alive: Callable, rng: RandomNumberGenerator) -> void:
	var pillar := _spr_a("fire", pfx + "fillar1", BOTTOM)
	var expl := _spr_a("fire", pfx + "explosion1", BOTTOM)
	var quake := _spr_a("fire", pfx + "earthquake", BOTTOM)
	for pair in [[pillar, zbase], [expl, zbase + 1], [quake, zbase + 2]]:
		var n: Node2D = pair[0]
		if n == null:
			continue
		n.position = pos + (Vector2(0.0, 5.0) if n == quake else Vector2.ZERO)
		n.z_index = int(pair[1])
		n.scale = Vector2(FIRE_START_SX, 0.0)
		host.add_child(n)

	var stones: Array = []
	if quake != null:
		for k in n_stone:
			var st := _spr("fire", pfx + "stone")
			if st == null:
				break
			st.position = Vector2(-100.0 + float(rng.randi() % 3) * 100.0, 0.0)
			st.scale *= float(rng.randi() % 8) * 0.1 + 0.25
			st.rotation_degrees = float(rng.randi() % 361)
			st.z_index = -1
			st.visible = false
			quake.add_child(st)
			stones.append(st)
			if k > rng.randi() % 3:
				continue
			var st2 := _spr("fire", pfx + "stone")
			if st2 == null:
				continue
			st2.position = Vector2(-75.0 + float(rng.randi() % 31) * 5.0, -25.0)
			st2.scale *= float(rng.randi() % 4) * 0.25 + 0.5
			st2.rotation_degrees = float(rng.randi() % 360)
			st2.z_index = -1
			st2.visible = false
			quake.add_child(st2)
			stones.append(st2)

	var go := func() -> void:
		if alive.is_valid() and not bool(alive.call()):
			return
		sfx_at(host, 0.1, "effect_bomb", sp, 0.5)
		sfx_at(host, FIRE_LAG + 0.1, "effect_fire_fillar", sp, 0.5)
		if is_instance_valid(expl):
			var et := expl.create_tween()
			et.tween_property(expl, "scale", Vector2.ONE, 0.1 / sp)
			et.tween_callback(func() -> void:
				_play_frames(expl, "fire", pfx + "explosion%d", 2, 6, FIRE_EXPL_SEC / sp))
			et.tween_interval(FIRE_EXPL_SEC * 5.0 / sp)
			et.tween_property(expl, "modulate:a", 0.0, 0.1 / sp)
			et.parallel().tween_property(expl, "scale", Vector2.ONE * 1.25, 0.1 / sp)
			et.tween_callback(expl.queue_free)
		if is_instance_valid(pillar):
			var fh := 323.0 * Design.ASSET_SCALE
			var sy := maxf(1.25, (pos.y + 40.0) / fh)
			var lt := pillar.create_tween()
			lt.tween_interval(FIRE_LAG / sp)
			lt.tween_property(pillar, "scale", Vector2(1.25, sy), 0.1 / sp)
			lt.tween_callback(func() -> void:
				_play_frames(pillar, "fire", pfx + "fillar%d", 3, 7, FIRE_PILLAR_SEC / sp))
			lt.tween_interval(FIRE_PILLAR_SEC * 5.0 / sp)
			lt.tween_property(pillar, "modulate:a", 0.0, 0.25 / sp)
			lt.tween_callback(pillar.queue_free)
		if is_instance_valid(quake):
			var qt := quake.create_tween()
			qt.tween_interval(FIRE_LAG / sp)
			qt.tween_property(quake, "scale", Vector2(1.1, 1.1), 0.1 / sp)
			qt.tween_property(quake, "scale", Vector2.ONE, 0.05 / sp)
			qt.tween_interval(0.75 / sp)
			qt.tween_property(quake, "modulate:a", 0.0, 1.0 / sp)
			qt.tween_callback(quake.queue_free)
		for st in stones:
			if not is_instance_valid(st):
				continue
			st.visible = true
			var dx: float = st.position.x
			var d := Vector2(dx * float(rng.randi() % 3 + 1) + float(rng.randi() % 90),
				float(rng.randi() % 8) * 10.0 - 25.0)
			var jt := float(rng.randi() % 4) * 0.125 + 0.125
			var sgn := 1.0 if d.x >= 0.0 else -1.0
			var t2: Tween = st.create_tween()
			t2.tween_interval(FIRE_LAG / sp)
			_jump_by(t2, st, d, float(rng.randi() % 400) + 150.0, 1, jt / sp, jt + jt)
			t2.parallel().tween_property(st, "rotation_degrees",
				sgn * (float(rng.randi() % 1080) + 1080.0), jt / sp).as_relative()
			_jump_by(t2, st, d / 5.0, float(rng.randi() % 50) + 100.0, 1, jt * 0.75 / sp, jt + jt)
			t2.parallel().tween_property(st, "rotation_degrees",
				sgn * (float(rng.randi() % 720) + 720.0), jt * 0.75 / sp).as_relative()
			_jump_by(t2, st, d / 10.0, float(rng.randi() % 75) + 25.0, 1, jt * 0.5 / sp, jt + jt)
			t2.parallel().tween_property(st, "rotation_degrees",
				sgn * (float(rng.randi() % 360) + 360.0), jt * 0.5 / sp).as_relative()
			t2.tween_property(st, "position", Vector2(d.x * 0.1, 0.0), jt / sp).as_relative()
			t2.parallel().tween_property(st, "rotation_degrees", d.x * 0.1 * 7.5, jt / sp)				.as_relative()
			t2.tween_interval(0.25 / sp)
			t2.tween_property(st, "modulate:a", 0.0, 0.75 / sp)
			t2.tween_callback(st.queue_free)

	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = maxf(0.01, delay)
	timer.autostart = true
	timer.timeout.connect(go)
	host.add_child(timer)

const COMBINE := {
	"dark":   {"dir": "battle_combine_dark",      "key": "battle_dark_combine_outline"},
	"shadow": {"dir": "battle_combine_blackwind", "key": "battle_blackwind_combine_outline"},
	"wind":   {"dir": "battle_combine_hurricane", "key": "battle_hurricane_combine_outline"},
	"chaos":  {"dir": "battle_combine_amagethon", "key": "battle_amagethon_combine_outline"},
}
const COMBINE_WHITE_DIR := "battle_ui"
const COMBINE_WHITE_KEY := "battle_combine_outline_white"
const COMBINE_SCALE := 2.25
const COMBINE_SCALE_Y := 0.375
const COMBINE_SPIN_SEC := 4.5
const COMBINE_SPIN_DEG := 720.0
const COMBINE_HOLD := {"wind": 4.15, "dark": 3.5}
const COMBINE_OUT := {"wind": 0.1, "dark": 0.25}
const COMBINE_HOLD_DEF := 3.5
const COMBINE_OUT_DEF := 0.5
const COMBINE_SPIN := {"wind": 5.25}
const COMBINE_GROW := {"dark": Vector2(1.5, 1.1)}
const COMBINE_GROW_SEC := 4.5

static func _combine_outline(host: CanvasItem, el: String, at: Vector2, sp: float) -> void:
	var c: Dictionary = COMBINE.get(el, {})
	if c.is_empty():
		return
	var ed := elem_delay(el)
	var hold := float(COMBINE_HOLD.get(el, COMBINE_HOLD_DEF))
	var out := float(COMBINE_OUT.get(el, COMBINE_OUT_DEF))
	var holder := Node2D.new()
	holder.position = at
	holder.z_index = 85
	holder.scale = Vector2(COMBINE_SCALE, COMBINE_SCALE_Y)
	host.add_child(holder)
	var w := AtlasUI.spr_cocos(COMBINE_WHITE_DIR, COMBINE_WHITE_KEY)
	if w != null:
		w.z_index = 1
		w.scale = Vector2.ZERO
		holder.add_child(w)
		var wt := w.create_tween()
		wt.tween_interval(maxf(0.01, ed) / sp)
		wt.tween_property(w, "scale", Vector2.ONE, 0.25 / sp).set_ease(Tween.EASE_IN)
		wt.tween_property(w, "modulate:a", 0.0, 0.75 / sp)
		wt.tween_callback(w.queue_free)
	var o := AtlasUI.spr_cocos(String(c["dir"]), String(c["key"]))
	if o != null:
		o.z_index = 2
		o.modulate.a = 0.0
		holder.add_child(o)
		var ot := o.create_tween()
		ot.tween_interval((ed + 0.25) / sp)
		ot.tween_property(o, "modulate:a", 200.0 / 255.0, 0.75 / sp)
		ot.tween_interval(hold / sp)
		ot.tween_property(o, "modulate:a", 0.0, out / sp)
	if holder.get_child_count() == 0:
		holder.queue_free()
		return
	if COMBINE_GROW.has(el):
		var g: Vector2 = COMBINE_GROW[el]
		var gt := holder.create_tween()
		gt.tween_interval(maxf(0.01, ed) / sp)
		gt.tween_property(holder, "scale",
			Vector2(holder.scale.x * g.x, holder.scale.y * g.y), COMBINE_GROW_SEC / sp)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var spin := float(COMBINE_SPIN.get(el, COMBINE_SPIN_SEC))
	for ch in holder.get_children():
		var n2 := ch as Node2D
		var st: Tween = n2.create_tween()
		st.tween_interval(maxf(0.01, ed) / sp)
		st.tween_property(n2, "rotation_degrees", COMBINE_SPIN_DEG, spin / sp)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var ht: Tween = holder.create_tween()
	ht.tween_interval((ed + maxf(spin, 0.25 + 0.75 + hold + out) + 0.1) / sp)
	ht.tween_callback(holder.queue_free)

static func _swarm(host: CanvasItem, el: String, key: String, n: int, at: Vector2,
		spread: Vector2, z: int, rng: RandomNumberGenerator, each: Callable) -> void:
	for i in n:
		var s := _spr(el, key)
		if s == null:
			return
		s.position = at + Vector2(
			rng.randf_range(-spread.x, spread.x), rng.randf_range(-spread.y, spread.y))
		s.z_index = z
		host.add_child(s)
		each.call(s, i, rng)

static func _screen_veil(host: CanvasItem, at: Vector2, col: Color, z: int) -> ColorRect:
	var vis: Vector2 = host.get_viewport().get_visible_rect().size
	var r := ColorRect.new()
	r.color = Color(col.r, col.g, col.b, 0.0)
	r.position = at - vis
	r.size = vis * 2.0
	r.z_index = z
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(r)
	return r

const EARTH_BASE_DY := 37.5
const EARTH_QUAKE_POS := [Vector2(-130.0, -50.0), Vector2(120.0, -20.0),
	Vector2(-30.0, -140.0), Vector2(60.0, -120.0)]
const EARTH_QUAKE_Z := [1, 1, 4, 3]
const EARTH_STONE_SPIN_DEG := 3600.0
const EARTH_QUAKE_SHAKE_SEC := 0.3
const EARTH_QUAKE_SHAKE_AMP := 10.0
const EARTH_LIGHT_SCALE := 1.5
const EARTH_STONES := 49
const EARTH_DEBRIS_DEST := [
	Vector2(1100.0, 100.0), Vector2(1200.0, 40.0), Vector2(-1100.0, 100.0),
	Vector2(-800.0, 60.0), Vector2(1200.0, 20.0), Vector2(600.0, 200.0),
	Vector2(900.0, 240.0), Vector2(750.0, 340.0), Vector2(-200.0, 600.0),
	Vector2(-180.0, 500.0), Vector2(-700.0, 200.0), Vector2(-800.0, 100.0),
	Vector2(-550.0, 600.0), Vector2(40.0, 800.0), Vector2(-900.0, 40.0),
]
const EARTH_DEBRIS_DY := 90.0
const EARTH_DEBRIS_JITTER := 40.0
const EARTH_WAVES := [1.45, 1.95, 2.45, 2.95, 3.65, 4.15]

static func _run_earth(host: CanvasItem, at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "earth"
	var pfx := prefix(el)
	var base := at - Vector2(0.0, EARTH_BASE_DY)
	var ed := elem_delay(el)

	var mt := _spr_a(el, pfx + "mountain", BOTTOM)
	if mt != null:
		mt.position = base + Vector2(0.0, 210.0)
		mt.z_index = 92
		mt.scale = Vector2(1.0, 0.0)
		host.add_child(mt)
		var t := mt.create_tween()
		t.tween_interval((ed + 2.3) / sp)
		t.tween_property(mt, "scale", Vector2(1.0, 1.1), 0.2 / sp)
		t.tween_property(mt, "scale", Vector2.ONE, 0.05 / sp)
		t.tween_callback(mt.queue_free)

	for i in EARTH_DEBRIS_DEST.size():
		var db := _spr(el, pfx + "mountain%d" % (i + 1))
		if db == null:
			break
		db.position = base - Vector2(0.0, EARTH_DEBRIS_DY)
		db.z_index = 92
		db.visible = false
		host.add_child(db)
		var dt := db.create_tween()
		dt.tween_interval((ed + 2.55) / sp)
		dt.tween_callback(func() -> void:
			if is_instance_valid(db):
				db.visible = true)
		for k in 8:
			var dy := -EARTH_DEBRIS_JITTER if k % 2 == 0 else EARTH_DEBRIS_JITTER
			dt.tween_property(db, "position", Vector2(0.0, dy), 0.025 / sp).as_relative()
		var bt := db.create_tween()
		bt.tween_interval((ed + 3.05) / sp)
		var dest: Vector2 = EARTH_DEBRIS_DEST[i]
		bt.tween_property(db, "position",
			Vector2(dir * dest.x, -dest.y), 0.25 / sp).as_relative()
		_fade_pma(bt.parallel(), db, 0.0, 0.25 / sp)
		bt.tween_callback(db.queue_free)

	for i in 4:
		var lg := _spr_a(el, pfx + "light", BOTTOM)
		if lg == null:
			break
		lg.position = base
		lg.scale = Vector2.ONE * EARTH_LIGHT_SCALE
		lg.rotation_degrees = float(i) * 90.0
		lg.z_index = 92
		_set_alpha(lg, 0.0)
		host.add_child(lg)
		var lt := lg.create_tween()
		lt.tween_interval((ed + 3.0) / sp)
		lt.tween_property(lg, "scale", lg.scale * 3.0, 0.1 / sp)
		lt.parallel().tween_property(lg, "rotation_degrees", 360.0, 0.1 / sp).as_relative()
		_fade_pma(lt.parallel(), lg, 1.0, 0.05 / sp)
		_fade_pma(lt, lg, 0.0, 0.05 / sp)
		lt.tween_callback(lg.queue_free)

	for i in EARTH_QUAKE_POS.size():
		var q := _spr(el, pfx + "earthquake1")
		if q == null:
			break
		var p: Vector2 = EARTH_QUAKE_POS[i]
		q.position = base + Vector2(dir * p.x, -p.y)
		q.z_index = 90 + int(EARTH_QUAKE_Z[i])
		q.visible = false
		host.add_child(q)
		var t2 := q.create_tween()
		t2.tween_interval((ed + float(i) * 0.5) / sp)
		t2.tween_callback(func() -> void:
			if is_instance_valid(q):
				q.visible = true
			Bgm.sfx("effect_bomb", 0.6)
			Bgm.sfx("effect_skill_50_destroy", 0.6))
		_shake(t2, q, EARTH_QUAKE_SHAKE_SEC / sp, EARTH_QUAKE_SHAKE_AMP, rng)
		t2.tween_interval(1.5 / sp)
		_fade_pma(t2, q, 0.0, 1.0 / sp)
		t2.tween_callback(q.queue_free)
		var show_at := ed + float(i) * 0.5
		_earth_quake_dust(host, el, q, pfx + "earthquake1",
			ed + float(i) * 0.25, show_at, sp, rng, 2.0, 1.5, 0.5)
		_earth_stones(host, el, q, pfx + "earthquake1", int(rng.randi() % 3 + 4),
			show_at, show_at, 0.05,
			[0.5, 2.0], [0.25, 0.75], [0.125, 0.25], 0.875, 0.75, sp, rng)

	var q2 := _spr(el, pfx + "earthquake2")
	if q2 != null:
		q2.position = base + Vector2(0.0, 100.0)
		q2.z_index = 92
		q2.visible = false
		host.add_child(q2)
		var t4 := q2.create_tween()
		t4.tween_interval((ed + 2.5) / sp)
		t4.tween_callback(func() -> void:
			if is_instance_valid(q2):
				q2.visible = true)
		_shake(t4, q2, EARTH_QUAKE_SHAKE_SEC / sp, EARTH_QUAKE_SHAKE_AMP, rng)
		t4.tween_interval(3.15 / sp)
		_fade_pma(t4, q2, 0.0, 0.75 / sp)
		t4.tween_callback(q2.queue_free)
		_earth_quake_dust(host, el, q2, pfx + "earthquake2",
			ed + 2.0, ed + 2.5, sp, rng, 4.0, 3.25, 0.75)
		_earth_stones(host, el, q2, pfx + "earthquake2", EARTH_STONES + int(rng.randi() % 26),
			ed + 2.5, ed + 2.5, 0.05,
			[0.8, 6.0], [0.3, 1.5], [0.15, 0.5], 1.25, 1.0, sp, rng)

	for i in int(rng.randi() % 3 + 4):
		var du := _spr(el, pfx + "dust2")
		if du == null:
			break
		du.position = base + Vector2(-150.0 + float(rng.randi() % 300),
			-(float(rng.randi() % 300) - 150.0))
		du.z_index = 88
		du.visible = false
		host.add_child(du)
		var t5 := du.create_tween()
		t5.tween_interval((ed + 3.0) / sp)
		t5.tween_callback(func() -> void:
			if is_instance_valid(du):
				du.visible = true)
		t5.tween_property(du, "position", Vector2(150.0 - float(rng.randi() % 300),
			-(float(rng.randi() % 100) + 50.0)), 3.5 / sp).as_relative()
		t5.parallel().tween_property(du, "scale", du.scale * 1.5, 3.5 / sp)
		var t6 := du.create_tween()
		t6.tween_interval((ed + 3.0 + 2.5) / sp)
		_fade_pma(t6, du, 0.0, 1.0 / sp)
		t6.tween_callback(du.queue_free)

static func _shake(t: Tween, n: Node2D, sec: float, amp: float,
		rng: RandomNumberGenerator) -> void:
	var home := n.position
	var seed_v := rng.randf() * TAU
	t.tween_method(func(x: float) -> void:
		if not is_instance_valid(n):
			return
		var decay := 1.0 - x
		n.position = home + Vector2(0.0, sin(seed_v + x * 40.0) * amp * decay),
		0.0, 1.0, maxf(0.01, sec))

static func _earth_quake_dust(host: CanvasItem, el: String, q: Node2D, qkey: String,
		at_sec: float, show_at: float, sp: float, rng: RandomNumberGenerator,
		grow: float, hold: float, out: float) -> void:
	var pfx := prefix(el)
	var qs := AtlasUI.size_pt(DIR_PREFIX + el, qkey)
	if qs == Vector2.ZERO:
		qs = Vector2(240.0, 110.0)
	var to_local := func(c: Vector2) -> Vector2:
		return Vector2(c.x - qs.x * 0.5, qs.y * 0.5 - c.y)
	var specs := [
		[pfx + "dust1", to_local.call(Vector2(qs.x * 0.5, qs.y / 3.0)), 0.5, false],
		[pfx + "dust2", to_local.call(Vector2(qs.x * 0.5 - 50.0 + float(rng.randi() % 100),
			qs.y * 0.25 + float(rng.randi() % 75))), 1.0, true],
	]
	for spec in specs:
		var du := _spr(el, String(spec[0]))
		if du == null:
			continue
		du.position = q.position + (spec[1] as Vector2)
		du.z_index = q.z_index - 1
		var base_scale: Vector2 = du.scale
		du.scale = base_scale * 0.2
		du.visible = false
		host.add_child(du)
		var sh := du.create_tween()
		sh.tween_interval(show_at / sp)
		sh.tween_callback(func() -> void:
			if is_instance_valid(du):
				du.visible = true)
		var t := du.create_tween()
		t.tween_interval(at_sec / sp)
		t.tween_property(du, "scale", base_scale * float(spec[2]), grow / sp)
		if bool(spec[3]):
			t.parallel().tween_property(du, "position",
				Vector2(75.0 - float(rng.randi() % 150),
					-(float(rng.randi() % 50) + 25.0)), grow / sp).as_relative()
		var t2 := du.create_tween()
		t2.tween_interval((at_sec + hold) / sp)
		_fade_pma(t2, du, 0.0, out / sp)
		t2.tween_callback(du.queue_free)

static func _earth_stones(host: CanvasItem, el: String, q: Node2D, qkey: String, n: int,
		at_sec: float, show_at: float, jitter: float, j0: Array, j1: Array, j2: Array,
		spin: float, out: float, sp: float, rng: RandomNumberGenerator) -> void:
	var pfx := prefix(el)
	var qs := AtlasUI.size_pt(DIR_PREFIX + el, qkey)
	if qs == Vector2.ZERO:
		qs = Vector2(240.0, 110.0)
	for i in n:
		var s := _spr(el, pfx + "stone")
		if s == null:
			return
		var cx := qs.x * 0.25 + float(rng.randi() % maxi(1, int(qs.x * 0.5)))
		var dx := cx - qs.x * 0.5
		s.position = q.position + Vector2(cx - qs.x * 0.5, qs.y * 0.5 - qs.y / 3.0)
		s.scale *= float(rng.randi() % 0x4c + 0x19) / 100.0
		s.z_index = q.z_index + 1
		s.visible = false
		host.add_child(s)
		var sh := s.create_tween()
		sh.tween_interval(show_at / sp)
		sh.tween_callback(func() -> void:
			if is_instance_valid(s):
				s.visible = true)
		var lag := (at_sec + float(rng.randi() % 4) * jitter) / sp
		var t := s.create_tween()
		t.tween_interval(lag)
		t.tween_property(s, "rotation_degrees", EARTH_STONE_SPIN_DEG, spin / sp).as_relative()
		var t2 := s.create_tween()
		t2.tween_interval(lag)
		_jump_by(t2, s, Vector2(dx * 2.0, -20.0), qs.y * float(j0[1]), 1, float(j0[0]) / sp, 1.0)
		_jump_by(t2, s, Vector2(dx * 2.0, 0.0), qs.y * float(j1[1]), 1, float(j1[0]) / sp, 0.5)
		_jump_by(t2, s, Vector2(dx * 2.0, 0.0), qs.y * float(j2[1]), 1, float(j2[0]) / sp, 0.25)
		_fade_pma(t2, s, 0.0, out / sp)
		t2.tween_callback(s.queue_free)

const AQUA_BUBBLES := 49
const AQUA_FISH := 40
const AQUA_SHARK_S := 1.75
const AQUA_WATER := Color8(194, 255, 255, 100)
const AQUA_SURF_A := 100.0 / 255.0
const AQUA_FADE_AT := 6.25
const AQUA_FISH_AT := 2.5
const AQUA_SHARK_AT := 5.0
const AQUA_JAW_OPEN := 0.03
const AQUA_JAW_BITE := 0.05
const AQUA_JAW_AT1 := 0.27
const AQUA_JAW_AT2 := 0.42
const AQUA_BITE_IN := 0.25
const AQUA_BITE_UP := 66.0

static func _run_aqua(host: CanvasItem, at: Vector2, ring_at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "aqua"
	var pfx := prefix(el)
	var ed := elem_delay(el)
	var vis: Vector2 = host.get_viewport().get_visible_rect().size
	var ctr := _screen_center(host)
	var prey_x := 2.0 * ctr.x - ring_at.x

	var water := Node2D.new()
	water.z_index = 85
	host.add_child(water)
	var band := _spr_a(el, pfx + "surface1", Vector2(0.5, 0.5))
	if band != null:
		var man0 := manifest(el)
		var info: Dictionary = man0.get(pfx + "surface1", {})
		var fw := float(info.get("w", 1.0)) * Design.ASSET_SCALE
		var fh := float(info.get("src", [480, 102])[1]) * Design.ASSET_SCALE
		band.scale = Vector2((vis.x / fw) if fw > 1.0 else 1.0, 1.0)
		band.z_index = 1
		_set_alpha(band, AQUA_SURF_A)
		water.add_child(band)
		_loop_frames(band, el, pfx + "surface%d", 1, 4, 0.1 / sp, (ed + AQUA_FADE_AT + 0.5) / sp)

		var body := ColorRect.new()
		body.color = AQUA_WATER
		body.size = Vector2(vis.x * 1.2, vis.y * 1.5)
		body.position = Vector2(-vis.x * 0.6, fh * 0.5 - 2.0)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		water.add_child(body)

		var y0 := ctr.y + vis.y * 0.42
		var y1 := ctr.y - vis.y * 0.28
		water.position = Vector2(ctr.x, y0)
		var t := water.create_tween()
		t.tween_interval(ed / sp)
		_arc(t, water, Vector2(ctr.x, lerpf(y0, y1, 0.4)), 75.0, 0.25 / sp)
		t.tween_property(water, "position", Vector2(ctr.x, lerpf(y0, y1, 0.75)), 0.5 / sp)
		_arc(t, water, Vector2(ctr.x, y1), 50.0, 0.25 / sp)
		var tb := band.create_tween()
		tb.tween_interval((ed + AQUA_FADE_AT) / sp)
		_fade_pma(tb, band, 0.0, 0.5 / sp)
		var tw := body.create_tween()
		tw.tween_interval((ed + AQUA_FADE_AT) / sp)
		tw.tween_property(body, "color:a", 0.0, 0.5 / sp)
		tw.tween_callback(water.queue_free)

	var shark := _spr(el, pfx + "shark1")
	if shark != null:
		var man1 := manifest(el)
		var sk_w := float(man1.get(pfx + "shark1", {}).get("w", 200.0)) \
			* Design.ASSET_SCALE * AQUA_SHARK_S
		shark.position = ctr + Vector2(dir * (vis.x * 0.5 + sk_w * 1.5), 80.0)
		shark.z_index = Z_ACTOR - 1
		shark.scale = Vector2(dir * AQUA_SHARK_S, AQUA_SHARK_S)
		shark.rotation_degrees = dir * 15.0
		host.add_child(shark)
		var bite := Vector2(prey_x + dir * sk_w * AQUA_BITE_IN, ctr.y - AQUA_BITE_UP)
		var jaw := shark.create_tween()
		jaw.tween_interval((ed + AQUA_SHARK_AT + AQUA_JAW_AT1) / sp)
		jaw.tween_callback(func() -> void:
			if is_instance_valid(shark):
				_play_frames(shark, el, pfx + "shark%d", 2, 5, AQUA_JAW_OPEN / sp))
		jaw.tween_interval((AQUA_JAW_AT2 - AQUA_JAW_AT1) / sp)
		jaw.tween_callback(func() -> void:
			if is_instance_valid(shark):
				_play_frames(shark, el, pfx + "shark%d", 6, 8, AQUA_JAW_BITE / sp))
		var kt := shark.create_tween()
		kt.tween_interval((ed + AQUA_SHARK_AT) / sp)
		kt.tween_property(shark, "position", bite, 0.42 / sp)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		kt.parallel().tween_property(shark, "rotation_degrees", dir * 4.0, 0.42 / sp)
		kt.parallel().tween_property(shark, "scale",
			Vector2(dir * 1.8, 1.825), 0.15 / sp).set_delay(0.27 / sp)
		kt.tween_property(shark, "scale", Vector2(dir * AQUA_SHARK_S, 1.7), 0.05 / sp)
		kt.tween_property(shark, "scale", Vector2(dir * AQUA_SHARK_S, AQUA_SHARK_S), 0.05 / sp)
		kt.tween_property(shark, "position", Vector2(-dir * 320.0, 10.0), 0.5 / sp)\
			.as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		kt.parallel().tween_property(shark, "rotation_degrees", -dir * 8.0, 0.5 / sp)
		kt.tween_property(shark, "position", Vector2(-dir * 260.0, 0.0), 0.5 / sp).as_relative()
		_fade_pma(kt.parallel(), shark, 0.0, 0.5 / sp)
		kt.tween_callback(shark.queue_free)

	_swarm(host, el, pfx + "bubble", AQUA_BUBBLES,
		Vector2(ctr.x, ctr.y + vis.y * 0.5), Vector2(vis.x * 0.5, 0.0), 98, rng,
		func(n: Node2D, i: int, r: RandomNumberGenerator) -> void:
			n.scale *= float(i % 5) * 0.25 + 0.25
			_set_alpha(n, 0.0)
			var rise := r.randf_range(vis.y * 0.45, vis.y * 0.95)
			var t: Tween = n.create_tween()
			t.tween_interval((ed + float(i % 12) * 0.3) / sp)
			_fade_pma(t, n, 1.0, 0.2 / sp)
			t.tween_property(n, "position",
				n.position + Vector2(r.randf_range(-40.0, 40.0), -rise),
				r.randf_range(2.0, 4.0) / sp)
			t.parallel().tween_property(n, "scale", n.scale * 1.3, 2.0 / sp)
			_fade_pma(t, n, 0.0, 0.3 / sp)
			t.tween_callback(n.queue_free))

	var enter := ctr.x + dir * (vis.x * 0.5 + 120.0)
	var exit_x := ctr.x - dir * (vis.x * 0.5 + 220.0)
	for i in AQUA_FISH:
		var f := _spr(el, pfx + "fish%d" % (rng.randi() % 5 + 1))
		if f == null:
			break
		var y := ctr.y + rng.randf_range(-vis.y * 0.34, vis.y * 0.3)
		var sc := float(rng.randi() % 6) * 0.1 + 0.5
		f.position = Vector2(enter + dir * float(i % 8) * 90.0, y)
		f.z_index = 97
		f.scale *= sc
		if dir < 0.0:
			f.scale.x = -f.scale.x
		host.add_child(f)
		var wob := f.create_tween().set_loops()
		wob.tween_property(f, "scale", f.scale * 1.1, 0.1 / sp)
		wob.tween_property(f, "scale", f.scale, 0.1 / sp)
		var t6 := f.create_tween()
		t6.tween_interval((ed + AQUA_FISH_AT + float(i % 10) * 0.07) / sp)
		var legs := [[0.3, float(i % 4) * 0.1 + 0.1], [0.65, 0.75], [0.9, 0.75],
			[0.98, 0.15], [1.0, 0.05]]
		for leg in legs:
			t6.tween_property(f, "position", Vector2(lerpf(enter, exit_x, float(leg[0])),
				y + rng.randf_range(-40.0, 40.0)), float(leg[1]) / sp)
		t6.tween_callback(f.queue_free)

const WIND_FADE_IN_AT := 0.9
const WIND_BODY_LIFE := 5.25
const WIND_GROW_SEC := 3.8375
const WIND_WHIRL_SEC := [0.035, 0.025]
const WIND_DEBRIS_LEAD := 0.15

static func _run_wind(host: CanvasItem, at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "wind"
	var pfx := prefix(el)
	var ed := elem_delay(el)
	var vis: Vector2 = host.get_viewport().get_visible_rect().size

	_wind_whirl(host, el, pfx, at, ed, sp, vis)
	_wind_debris(host, el, pfx, at, dir, ed, sp, vis, rng)
	_wind_zmoon(host, el, pfx, sp, vis, rng)

static func _wind_whirl(host: CanvasItem, el: String, pfx: String, at: Vector2,
		ed: float, sp: float, vis: Vector2) -> void:
	var mn: Dictionary = manifest(el).get(pfx + "whirl1", {})
	var bw := float(mn.get("w", 1.0)) * Design.ASSET_SCALE
	var bh := float(mn.get("h", 1.0)) * Design.ASSET_SCALE
	if bw <= 1.0 or bh <= 1.0:
		return
	var sy := vis.y / bh
	for k in 2:
		var anchor := BOTTOM if k == 0 else Vector2(0.4, 1.0)
		var body := _spr_a(el, pfx + ("whirl1" if k == 0 else "whirl4"), anchor)
		if body == null:
			break
		if k == 0:
			body.scale = Vector2(vis.x / bw, sy)
			body.position = Vector2(vis.x * 0.5, vis.y)
		else:
			body.scale = Vector2(vis.x / (bw * 0.8), -sy * 0.75)
			body.position = at + Vector2(0.0, -10.0)
		body.z_index = Z_WIND_WHIRL + k
		body.modulate.a = 0.0
		host.add_child(body)
		if k == 0:
			_loop_frames(body, el, pfx + "whirl%d", 1, 4, WIND_WHIRL_SEC[0] / sp,
				(ed + WIND_BODY_LIFE) / sp)
		else:
			_loop_frames_rev(body, el, pfx + "whirl%d", 4, 1, WIND_WHIRL_SEC[1] / sp,
				(ed + WIND_BODY_LIFE) / sp)
		var s0 := body.scale
		var grow := body.create_tween()
		grow.tween_interval(ed / sp)
		grow.tween_property(body, "scale", Vector2(s0.x * 1.25, s0.y), WIND_GROW_SEC / sp)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		grow.tween_property(body, "scale", Vector2(s0.x * 1.25 * 1.15, s0.y * 1.05),
			(WIND_BODY_LIFE - WIND_GROW_SEC) / sp)
		var t := body.create_tween()
		t.tween_interval((ed + WIND_FADE_IN_AT) / sp)
		t.tween_property(body, "modulate:a", 1.0 if k == 0 else 175.0 / 255.0, 0.5 / sp)
		t.tween_interval((WIND_BODY_LIFE - WIND_FADE_IN_AT - 0.5 - 0.25) / sp)
		t.tween_property(body, "modulate:a", 0.0, 0.25 / sp)
		t.tween_callback(body.queue_free)

static func _wind_debris(host: CanvasItem, el: String, pfx: String, at: Vector2, dir: float,
		ed: float, sp: float, vis: Vector2, rng: RandomNumberGenerator) -> void:
	var n_wood := int(rng.randi() % 3)
	var n_leaf := int(rng.randi() % 8 + 12)
	for i in n_wood + n_leaf:
		var is_wood := i < n_wood
		var seg := _spr(el, pfx + ("wood" if is_wood else "leaf"))
		if seg == null:
			return
		var s0 := 0.75 + float(rng.randi() % 6) * 0.1 * (1.0 if rng.randi() % 2 == 1 else -1.0)
		var home := Vector2(at.x + dir * (vis.x * 0.55 + rng.randf_range(0.0, 220.0)),
			at.y - vis.y * (0.10 + 0.60 * rng.randf()))
		seg.position = home
		seg.scale *= s0 if is_wood else rng.randf_range(0.7, 1.1)
		seg.z_index = Z_WIND_DEBRIS + (i % 3)
		seg.rotation_degrees = float(rng.randi() % 181) - 90.0
		var base_scale := seg.scale
		var cross := Vector2(-dir * (vis.x + 320.0), rng.randf_range(-70.0, 70.0))
		host.add_child(seg)
		var lead := ed + WIND_DEBRIS_LEAD + rng.randf() * 1.6
		var t := seg.create_tween()
		t.tween_interval(lead / sp)
		for pass_i in 2:
			var move_sec := 1.0 if pass_i == 0 else 1.5
			if pass_i == 1:
				t.tween_callback(func() -> void:
					if is_instance_valid(seg):
						seg.position = home
						seg.scale = base_scale
						seg.modulate.a = 200.0 / 255.0)
				var slack := ed + WIND_BODY_LIFE - 1.75 - 1.25 - lead
				t.tween_interval(clampf(rng.randf_range(0.6, 2.2), 0.2, maxf(0.2, slack)) / sp)
			t.tween_property(seg, "position", cross, move_sec / sp).as_relative()
			t.parallel().tween_property(seg, "scale", base_scale * 1.25,
				(0.9 if pass_i == 0 else 1.4) / sp)
			t.parallel().tween_property(seg, "rotation_degrees",
				(float(rng.randi() % 181) - 90.0) * 3.0, move_sec / sp).as_relative()
			t.tween_property(seg, "scale",
				Vector2(base_scale.x * 1.25 * 3.0, base_scale.y * 1.25 * 0.5), 0.25 / sp)
			t.parallel().tween_property(seg, "modulate:a", 0.0, 0.25 / sp)
		t.tween_callback(seg.queue_free)

const WIND_ZMOON_PASS := [[0, 2.7], [1, 3.85], [0, 5.5]]
const WIND_ZMOON_SEC := 0.75

static func _wind_zmoon(host: CanvasItem, el: String, pfx: String,
		sp: float, vis: Vector2, rng: RandomNumberGenerator) -> void:
	for k in 2:
		var cow := _spr(el, pfx + "zmoon")
		if cow == null:
			return
		if k == 1:
			cow.scale *= 0.75
		cow.z_index = Z_WIND_ZMOON
		cow.modulate.a = 0.0
		host.add_child(cow)
		var t := cow.create_tween()
		var prev := 0.0
		var used := false
		for row in WIND_ZMOON_PASS:
			if int(row[0]) != k:
				continue
			used = true
			var when := float(row[1])
			t.tween_interval(maxf(0.01, when - prev) / sp)
			prev = when + WIND_ZMOON_SEC
			var y := vis.y * rng.randf_range(0.18, 0.48)
			t.tween_callback(func() -> void:
				if is_instance_valid(cow):
					cow.position = Vector2(vis.x + 140.0, y)
					cow.rotation_degrees = float(rng.randi() % 61) - 30.0
					cow.modulate.a = 1.0)
			t.tween_property(cow, "position",
				Vector2(-240.0, y - vis.y * 0.12), WIND_ZMOON_SEC / sp)\
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			t.parallel().tween_property(cow, "rotation_degrees", -180.0,
				WIND_ZMOON_SEC / sp).as_relative()
			t.tween_callback(func() -> void:
				if is_instance_valid(cow):
					cow.modulate.a = 0.0)
		if not used:
			cow.queue_free()
			continue
		t.tween_callback(cow.queue_free)

const DARK_PUNCH_S := 1.75
const DARK_HAND_SEC := 0.025
const DARK_HAND_IN := [13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
const DARK_HAND_HOLD := 3
const DARK_HAND_ROT_L := -45.0
const DARK_HAND_ROT_R := -25.0
const DARK_HAND_DRIFT := Vector2(50.0, -55.0)

static func _run_dark(host: CanvasItem, at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "dark"
	var pfx := prefix(el)
	var ed := elem_delay(el)
	var dk := Vector2(at.x, _screen_center(host).y)

	var ball := _spr(el, pfx + "ball")
	if ball != null:
		ball.position = dk
		ball.scale = Vector2.ZERO
		ball.z_index = 96
		host.add_child(ball)
		var bt: Tween = ball.create_tween()
		bt.tween_interval((ed + 1.5) / sp)
		bt.tween_property(ball, "scale", Vector2.ONE, 0.25 / sp)
		bt.parallel().tween_property(ball, "rotation_degrees", -30.0, 0.25 / sp)\
			.as_relative().set_ease(Tween.EASE_IN)
		bt.tween_property(ball, "scale", Vector2.ONE * 2.5, 3.0 / sp)
		bt.parallel().tween_property(ball, "rotation_degrees", -3600.0, 3.0 / sp)\
			.as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		bt.tween_property(ball, "scale", Vector2.ZERO, 0.075 / sp)
		bt.tween_callback(ball.queue_free)

	for i in 2:
		var hd := _spr(el, pfx + "hand1")
		if hd == null:
			break
		var sgn := -1.0 if i == 0 else 1.0
		hd.position = dk + Vector2(sgn * 300.0, -40.0)
		hd.z_index = 99
		if i == 0:
			hd.scale = Vector2(-hd.scale.x, hd.scale.y)
		hd.visible = false
		host.add_child(hd)
		var ht: Tween = hd.create_tween()
		ht.tween_interval((ed + 1.0) / sp)
		var in_seq: Array = DARK_HAND_IN.duplicate()
		in_seq[in_seq.size() - 1] = DARK_HAND_HOLD
		ht.tween_callback(func() -> void:
			if not is_instance_valid(hd):
				return
			hd.visible = true
			_play_frame_seq(hd, el, pfx + "hand%d", in_seq, DARK_HAND_SEC / sp))
		ht.tween_property(hd, "scale", hd.scale * 2.0, 0.35 / sp)
		ht.parallel().tween_property(hd, "position", Vector2(sgn * 60.0, 0.0), 0.35 / sp)\
			.as_relative()
		ht.parallel().tween_property(hd, "rotation_degrees",
			DARK_HAND_ROT_L if i == 0 else DARK_HAND_ROT_R, 0.35 / sp).as_relative()
		ht.tween_property(hd, "scale", hd.scale * 2.0 * 1.05, 0.025 / sp)
		ht.tween_property(hd, "scale", hd.scale * 2.0, 0.025 / sp)
		ht.tween_property(hd, "position", DARK_HAND_DRIFT * Vector2(sgn, 1.0), 2.95 / sp)\
			.as_relative().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		ht.tween_property(hd, "scale", hd.scale * 2.0 * 1.5, 0.25 / sp)
		ht.tween_property(hd, "modulate:a", 0.0, 0.1 / sp)
		ht.tween_callback(hd.queue_free)

	var punch := _spr(el, pfx + "punch")
	if punch != null:
		punch.position = dk
		punch.scale = Vector2.ONE * DARK_PUNCH_S
		punch.z_index = 100
		punch.visible = false
		host.add_child(punch)
		var pt: Tween = punch.create_tween()
		pt.tween_interval((ed + 4.8) / sp)
		pt.tween_callback(func() -> void:
			if is_instance_valid(punch):
				punch.visible = true)
		pt.tween_property(punch, "position", Vector2(dir * 40.0, 0.0), 0.1 / sp).as_relative()
		pt.parallel().tween_property(punch, "scale",
			Vector2(DARK_PUNCH_S, DARK_PUNCH_S * 1.1), 0.05 / sp)
		pt.tween_property(punch, "scale", Vector2.ONE * DARK_PUNCH_S, 0.05 / sp)
		pt.tween_property(punch, "scale", Vector2.ONE * DARK_PUNCH_S * 0.8, 1.0 / sp)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		pt.parallel().tween_property(punch, "rotation_degrees", -45.0, 1.0 / sp).as_relative()
		pt.tween_callback(punch.queue_free)

	var e1 := _spr(el, pfx + "explosion1")
	if e1 != null:
		e1.position = dk
		e1.z_index = 101
		e1.scale = Vector2.ZERO
		host.add_child(e1)
		var t2: Tween = e1.create_tween()
		t2.tween_interval((ed + 5.9) / sp)
		t2.tween_callback(func() -> void:
			_play_frames(e1, el, pfx + "explosion%d", 1, 7, 0.04 / sp))
		t2.tween_property(e1, "scale", Vector2.ONE * 3.75, 0.04 / sp)
		t2.tween_interval((0.2 + 0.04 * 6.0) / sp)
		t2.tween_property(e1, "scale", Vector2.ZERO, 0.05 / sp)
		t2.parallel().tween_property(e1, "rotation_degrees", 360.0, 0.05 / sp).as_relative()
		t2.parallel().tween_property(e1, "modulate:a", 0.0, 0.05 / sp)
		t2.tween_callback(e1.queue_free)

	var e2 := _spr(el, pfx + "explosion8")
	if e2 != null:
		e2.position = dk
		e2.z_index = 102
		e2.scale = Vector2.ZERO
		e2.rotation_degrees = 90.0
		host.add_child(e2)
		var t3: Tween = e2.create_tween()
		t3.tween_interval((ed + 5.9) / sp)
		t3.tween_property(e2, "scale", Vector2.ONE * 3.0, 0.075 / sp)
		t3.parallel().tween_property(e2, "rotation_degrees", 360.0, 0.05 / sp).as_relative()
		t3.tween_property(e2, "scale", Vector2.ONE * 3.0 * 1.1, 0.1 / sp)
		t3.parallel().tween_property(e2, "modulate:a", 0.0, 0.1 / sp)
		t3.tween_callback(e2.queue_free)

const LIGHT_FLASHWING_SX := 10.0
const LIGHT_STARS_IN := 30
const LIGHT_STARS_OUT := 720
const LIGHT_STARS := LIGHT_STARS_IN + LIGHT_STARS_OUT
const LIGHT_STAR_SCALE_MIN := 0.125
const LIGHT_STAR_SCALE_STEP := 0.0125
const LIGHT_STAR_SCALE_N := 21
const LIGHT_STAR_A_MIN := 155.0 / 255.0
const LIGHT_SATURN_OFF := Vector2(60.0, -60.0)
const LIGHT_PLANET_P0 := Vector2(0.724, -0.432)
const LIGHT_PLANET_P1 := Vector2(0.088, 0.117)
const Z_LIGHT_PLANET := -1
const Z_LIGHT_STARS := 98
const Z_LIGHT_BOMB := 99
const Z_LIGHT_SUNWING := 100
const Z_LIGHT_SUN := 101
const Z_LIGHT_HALO := 102
const Z_LIGHT_FLASH := 103

static func _run_light(host: CanvasItem, at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "light"
	var pfx := prefix(el)
	var vis: Vector2 = host.get_viewport().get_visible_rect().size

	var d := elem_delay(el)

	var flash_v := _screen_veil(host, at, Color(1, 1, 1), Z_FLASH)
	var fl := flash_v.create_tween()
	fl.tween_interval((d + 0.5) / sp)
	fl.tween_property(flash_v, "color:a", 1.0, 0.1 / sp)
	fl.tween_interval(0.75 / sp)
	fl.tween_property(flash_v, "color:a", 0.0, 0.1 / sp)
	fl.tween_interval(3.65 / sp)
	fl.tween_property(flash_v, "color:a", 1.0, 0.1 / sp)
	fl.tween_interval(0.75 / sp)
	fl.tween_property(flash_v, "color:a", 0.0, 0.75 / sp)
	fl.tween_callback(flash_v.queue_free)

	var field := Node2D.new()
	field.z_index = Z_LIGHT_STARS
	field.position = at
	_set_alpha(field, 0.0)
	host.add_child(field)
	var ctr := _screen_center(host)
	var half := vis * 0.5
	for i in LIGHT_STARS:
		var st := _spr(el, pfx + "star")
		if st == null:
			break
		st.position = Vector2.ZERO
		st.scale = Vector2.ONE * (float(rng.randi() % LIGHT_STAR_SCALE_N)
			* LIGHT_STAR_SCALE_STEP + LIGHT_STAR_SCALE_MIN)
		_set_alpha(st, float(rng.randi() % 11) * (10.0 / 255.0) + LIGHT_STAR_A_MIN)
		st.visible = false
		field.add_child(st)
		var spot := ctr + Vector2(rng.randf_range(-half.x, half.x),
			rng.randf_range(-half.y, half.y))
		var t: Tween = st.create_tween()
		if i < LIGHT_STARS_IN:
			t.tween_interval((d + 0.75) / sp)
			t.tween_callback(func() -> void: st.visible = true)
			t.tween_property(st, "position", spot - at,
				(float(rng.randi() % 11) * 0.025 + 1.75) / sp)\
				.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		else:
			t.tween_interval((d + 1.75) / sp)
			t.tween_callback(func() -> void: st.visible = true)
			t.tween_property(st, "position",
				(spot - ctr) * (float(rng.randi() % 9) * 0.25 + 1.0),
				(float(rng.randi() % 45) * 0.025 + 0.75) / sp)\
				.as_relative().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	var ft := field.create_tween()
	ft.tween_interval((d + 0.6) / sp)
	ft.tween_callback(func() -> void: _set_alpha(field, 1.0))
	ft.tween_property(field, "scale", Vector2(1.1, 1.1), 4.75 / sp)
	ft.tween_interval(0.5 / sp)
	ft.tween_callback(field.queue_free)

	var p0 := ctr - at + Vector2(vis.x * LIGHT_PLANET_P0.x, vis.y * LIGHT_PLANET_P0.y)
	var p1 := ctr - at + Vector2(vis.x * LIGHT_PLANET_P1.x, vis.y * LIGHT_PLANET_P1.y)
	var p2 := ctr - at
	_light_planet(field, el, pfx + "earth", [p0, p1, p2], 0.4, d + 1.45, sp,
		[[2.0, 3.0], [1.0, 2.0]])
	_light_planet(field, el, pfx + "saturn",
		[p0 + LIGHT_SATURN_OFF, p1 + LIGHT_SATURN_OFF, p2], 1.0, d + 2.45, sp,
		[[2.5, 5.0]])

	var sun_at := at

	var flash := _spr_a(el, pfx + "flash", Vector2(0.54, 0.5))
	if flash != null:
		flash.position = sun_at
		flash.scale = Vector2.ZERO
		flash.z_index = Z_LIGHT_FLASH
		host.add_child(flash)
		var wing := _spr(el, pfx + "flashwing")
		if wing != null:
			wing.position = Vector2((0.5 - 0.54)
				* AtlasUI.size_pt(DIR_PREFIX + el, pfx + "flash").x, 0.0)
			wing.scale = Vector2(LIGHT_FLASHWING_SX, 1.0)
			wing.z_index = -1
			flash.add_child(wing)
			var wt := wing.create_tween()
			wt.tween_interval(d / sp)
			wt.tween_property(wing, "scale", Vector2.ONE, 0.5 / sp)\
				.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
			wt.tween_interval(1.0 / sp)
			_fade_pma(wt, wing, 0.0, 0.25 / sp)
			wt.tween_callback(wing.queue_free)
		var t := flash.create_tween()
		t.tween_interval(d / sp)
		t.tween_property(flash, "scale", Vector2(0.15, 0.15), 0.5 / sp)
		t.tween_property(flash, "scale", Vector2(5.0, 5.0), 0.1 / sp)
		t.tween_interval(0.75 / sp)
		t.tween_callback(func() -> void: flash.scale = Vector2(7.5, 7.5))
		t.tween_property(flash, "scale", Vector2(2.0, 2.0), 0.25 / sp)
		t.tween_property(flash, "scale", Vector2(1.75, 1.75), 0.5 / sp)
		_fade_pma(t.parallel(), flash, 0.0, 0.5 / sp)
		t.tween_callback(flash.queue_free)

	var bomb := _spr(el, pfx + "bomb")
	if bomb != null:
		bomb.position = sun_at
		bomb.scale = Vector2.ZERO
		bomb.z_index = Z_LIGHT_BOMB
		host.add_child(bomb)
		var bt := bomb.create_tween()
		bt.tween_interval((d + 1.6) / sp)
		bt.tween_property(bomb, "scale", Vector2(7.5, 7.5), 0.5 / sp)
		bt.tween_callback(bomb.queue_free)

	var sun := _spr(el, pfx + "sun")
	if sun != null:
		sun.position = sun_at
		_set_alpha(sun, 0.0)
		sun.z_index = Z_LIGHT_SUN
		host.add_child(sun)
		var t := sun.create_tween()
		t.tween_interval((d + 1.6) / sp)
		t.tween_property(sun, "rotation_degrees", -1260.0, 3.5 / sp).as_relative()\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_fade_pma(t.parallel(), sun, 1.0, 0.25 / sp)
		t.parallel().tween_property(sun, "scale", Vector2(0.75, 0.75), 1.0 / sp)
		t.parallel().tween_property(sun, "scale", Vector2(2.0, 2.0), 2.5 / sp)\
			.set_delay(1.0 / sp)
		t.tween_interval(0.75 / sp)
		t.tween_property(sun, "scale", Vector2.ZERO, 0.75 / sp)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(sun, "rotation_degrees", -360.0, 0.75 / sp).as_relative()
		t.tween_callback(sun.queue_free)

	var halo := _spr(el, pfx + "sunlight")
	if halo != null:
		halo.position = sun_at
		_set_alpha(halo, 0.0)
		halo.z_index = Z_LIGHT_HALO
		host.add_child(halo)
		var t := halo.create_tween()
		t.tween_interval((d + 1.6) / sp)
		t.tween_property(halo, "scale", Vector2(0.75, 0.75), 1.0 / sp)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_fade_pma(t.parallel(), halo, 1.0, 0.25 / sp)
		t.tween_property(halo, "scale", Vector2(2.0, 2.0), 2.5 / sp)\
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		t.tween_interval(0.75 / sp)
		t.tween_property(halo, "scale", Vector2.ZERO, 0.75 / sp)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		t.tween_callback(halo.queue_free)

	var swing := _spr(el, pfx + "sunwing")
	if swing != null:
		swing.position = sun_at
		_set_alpha(swing, 0.0)
		swing.z_index = Z_LIGHT_SUNWING
		host.add_child(swing)
		var twin := _spr(el, pfx + "sunwing")
		if twin != null:
			twin.rotation_degrees = 90.0
			twin.scale = Vector2.ZERO
			_set_alpha(twin, 0.0)
			twin.z_index = -1
			swing.add_child(twin)
			var tt := twin.create_tween()
			tt.tween_interval((d + 4.0) / sp)
			tt.tween_property(twin, "scale", Vector2.ONE, 1.0 / sp)
			_fade_pma(tt.parallel(), twin, 1.0, 1.0 / sp)
		var t := swing.create_tween()
		t.tween_interval((d + 1.75) / sp)
		t.tween_property(swing, "scale", Vector2(0.75, 0.75), 1.0 / sp)
		_fade_pma(t.parallel(), swing, 1.0, 0.1 / sp)
		t.tween_property(swing, "scale", Vector2(2.0, 2.0), 2.5 / sp)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(swing, "rotation_degrees", 720.0, 0.75 / sp)\
			.as_relative().set_delay(1.75 / sp)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		t.tween_callback(swing.queue_free)

static func _light_planet(host: CanvasItem, el: String, key: String, pts: Array,
		scale0: float, at_sec: float, sp: float, passes: Array) -> void:
	var n := _spr(el, key)
	if n == null:
		return
	n.position = pts[0]
	n.scale = Vector2.ONE * scale0
	n.visible = false
	n.z_index = Z_LIGHT_PLANET
	host.add_child(n)
	var p0: Vector2 = pts[0]
	var p1: Vector2 = pts[1]
	var p2: Vector2 = pts[2]
	var t := n.create_tween()
	t.tween_interval(at_sec / sp)
	t.tween_callback(func() -> void: n.visible = true)
	for i in passes.size():
		if i > 0:
			t.tween_callback(func() -> void:
				n.position = p0
				n.scale = Vector2.ONE * scale0
				_set_alpha(n, 1.0))
		var bez := float(passes[i][0])
		var sec := float(passes[i][1])
		t.tween_method(func(x: float) -> void:
			if is_instance_valid(n):
				var q := 1.0 - x
				n.position = p0 * (q * q) + p1 * (2.0 * q * x) + p2 * (x * x),
			0.0, 1.0, bez / sp)
		t.parallel().tween_property(n, "scale", Vector2(8.0, 8.0), sec / sp)\
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		_fade_pma(t.parallel(), n, 0.0, 3.0 / sp)
	t.tween_callback(n.queue_free)

const HOLY_SPEARS := 31
const HOLY_ROUNDS := 3
const HOLY_BASE_DY := 62.5
const HOLY_WELL_AT := 0.75
const HOLY_WELL_OUT := 3.9
const HOLY_SPEAR_GAP := 24.166666
const HOLY_SPEAR_RATE := 0.3

static func _run_holy(host: CanvasItem, at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "holy"
	var pfx := prefix(el)
	var base := at - Vector2(0.0, HOLY_BASE_DY)
	var vis: Vector2 = host.get_viewport().get_visible_rect().size

	var flash := _screen_veil(host, at, Color(1, 1, 1), Z_FLASH)
	var fl := flash.create_tween()
	fl.tween_interval(3.775 / sp)
	fl.tween_property(flash, "color:a", 1.0, 0.75 / sp)
	fl.tween_interval(0.1 / sp)
	fl.tween_property(flash, "color:a", 0.0, 0.25 / sp)
	fl.tween_callback(flash.queue_free)

	var pool := base + Vector2(0.0, HOLY_BASE_DY * 2.0)
	var well := _spr(el, pfx + "well")
	if well != null:
		well.position = pool
		well.z_index = 88
		well.scale = Vector2.ONE * 0.35
		host.add_child(well)
		var wt := well.create_tween()
		wt.tween_interval(0.2 / sp)
		wt.tween_property(well, "scale", Vector2.ONE, 0.3 / sp)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		wt.tween_property(well, "scale", Vector2.ONE * 1.35,
			maxf(0.1, HOLY_WELL_OUT - 0.5) / sp)
		wt.tween_property(well, "modulate:a", 0.0, 0.25 / sp)
		wt.tween_callback(well.queue_free)

	for r in HOLY_ROUNDS:
		sfx_at(host, elem_delay(el) + float(r) * 0.2 + 0.4 + 0.25, "effect_critical_ice_1", sp)
		for i in HOLY_SPEARS:
			for layer in 2:
				var s := _spr_a(el, pfx + "spear", Vector2(0.5, 0.1))
				if s == null:
					return
				s.position = pool + Vector2(rng.randf_range(-50.0, 50.0),
					rng.randf_range(-14.0, 6.0))
				var ang := deg_to_rad(lerpf(-160.0, -20.0, float(i) / float(HOLY_SPEARS - 1))
					+ float(r) * 7.0 + rng.randf_range(-4.0, 4.0))
				var v := Vector2(cos(ang), sin(ang))
				s.rotation = atan2(v.x, -v.y)
				s.z_index = (95 + i) if layer == 0 else (84 - i / 8)
				s.visible = false
				s.modulate.a = 0.0
				host.add_child(s)
				var fly := maxf(0.1, 1.775 - 0.1 * float(r) - 0.0125 * float(i))
				var reach := rng.randf_range(170.0, 260.0)
				var sc0 := s.scale
				var t: Tween = s.create_tween()
				t.tween_interval((float(r) * 0.2 + float(i) * 0.0125 + 0.4) / sp)
				t.tween_callback(func() -> void: s.visible = true)
				t.tween_property(s, "modulate:a", 200.0 / 255.0, 0.25 / sp)
				_ease_in_by(t, s, v * reach, fly / sp, HOLY_SPEAR_RATE)
				t.tween_property(s, "scale", sc0 * 1.2, 0.1 / sp)
				t.parallel().tween_property(s, "modulate:a", 100.0 / 255.0, 0.1 / sp)
				t.tween_property(s, "position", v * (reach * 0.08), 0.75 / sp).as_relative()
				t.parallel().tween_property(s, "modulate:a", 0.0, 0.5 / sp)
				t.tween_callback(s.queue_free)

	for i in 24:
		var fe := AtlasUI.spr_cocos("common_ui", "common_feather%d" % (1 + i % 6))
		if fe == null:
			break
		var ctr_h := _screen_center(host)
		fe.position = ctr_h + Vector2(rng.randf_range(-vis.x * 0.5, vis.x * 0.5),
			rng.randf_range(-vis.y * 0.55, -vis.y * 0.1))
		fe.scale = Vector2.ONE * rng.randf_range(0.7, 1.2)
		fe.z_index = Z_FLASH + 1
		fe.modulate.a = 0.0
		fe.rotation_degrees = rng.randf_range(-40.0, 40.0)
		host.add_child(fe)
		var ft2 := fe.create_tween()
		ft2.tween_interval((3.9 + float(i % 8) * 0.08) / sp)
		ft2.tween_property(fe, "modulate:a", 1.0, 0.2 / sp)
		ft2.tween_property(fe, "position",
			Vector2(rng.randf_range(-70.0, 70.0), vis.y * rng.randf_range(0.35, 0.6)),
			rng.randf_range(1.2, 2.0) / sp).as_relative()\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		ft2.parallel().tween_property(fe, "rotation_degrees",
			rng.randf_range(-90.0, 90.0), 1.6 / sp).as_relative()
		ft2.tween_property(fe, "modulate:a", 0.0, 0.4 / sp)
		ft2.tween_callback(fe.queue_free)

const CHAOS_DUST_AT := 0.0
const CHAOS_DUST_LIVE := 2.75
const CHAOS_COVER_AT := 5.75
const CHAOS_DUST_SEC := 0.05
const CHAOS_COVERS := 18
const CHAOS_METEO_ANCHOR_Y := 0.049295776
const CHAOS_METEO_IN := 0.75
const CHAOS_METEO_FALL := 2.95
const CHAOS_METEO_REST := 0.22

static func _run_chaos(host: CanvasItem, at: Vector2, dir: float, sp: float,
		rng: RandomNumberGenerator) -> void:
	var el := "chaos"
	var pfx := prefix(el)
	var vis: Vector2 = host.get_viewport().get_visible_rect().size
	var s_ring := RING_DY

	var mw := float(manifest(el).get(pfx + "meteo1", {}).get("w", 1.0)) * Design.ASSET_SCALE
	var mh := float(manifest(el).get(pfx + "meteo1", {}).get("h", 1.0)) * Design.ASSET_SCALE
	var ctrx := _screen_center(host).x
	var m := _spr_a(el, pfx + "meteo1", Vector2(0.5, CHAOS_METEO_ANCHOR_Y))
	if m != null:
		var sc := (vis.x / mw) if mw > 1.0 else 1.0
		m.scale = Vector2.ONE * sc
		var top := _screen_center(host).y - vis.y * 0.5
		m.position = Vector2(ctrx, top - 30.0)
		m.z_index = Z_VEIL + 1
		m.modulate.a = 0.0
		host.add_child(m)
		var t: Tween = m.create_tween()
		t.tween_interval(CHAOS_METEO_IN / sp)
		t.tween_property(m, "position:y", top + vis.y * CHAOS_METEO_REST,
			CHAOS_METEO_FALL / sp).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.parallel().tween_property(m, "modulate:a", 1.0, 0.75 / sp)
		t.tween_property(m, "modulate:a", 0.0, 0.75 / sp)
		t.tween_callback(m.queue_free)
		_loop_frames(m, el, pfx + "meteo%d", 1, 2, 0.1 / sp,
			(CHAOS_METEO_IN + CHAOS_METEO_FALL + 0.75) / sp)

	var bang := _screen_veil(host, at, Color8(200, 50, 25), Z_FLASH)
	var bt := bang.create_tween()
	bt.tween_interval(2.5 / sp)
	bt.tween_property(bang, "color:a", 175.0 / 255.0, 1.0 / sp)
	bt.tween_property(bang, "color", Color(1, 1, 1, 1), 1.0 / sp)
	bt.tween_interval(0.5 / sp)
	bt.tween_property(bang, "color:a", 0.0, 1.0 / sp)
	bt.tween_callback(bang.queue_free)

	var du := _spr_a(el, pfx + "dust1", BOTTOM)
	if du != null:
		var dw := float(manifest(el).get(pfx + "dust1", {}).get("w", 1.0)) * Design.ASSET_SCALE
		var kx := maxf(1.0, vis.x / dw) if dw > 1.0 else 1.0
		du.position = Vector2(ctrx, at.y + s_ring)
		du.z_index = Z_VEIL + 2
		du.scale = Vector2(kx, 0.0)
		host.add_child(du)
		var dg := du.create_tween()
		dg.tween_interval(CHAOS_DUST_AT / sp)
		dg.tween_property(du, "scale", Vector2(kx, 1.0), 0.4 / sp)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_loop_frames(du, el, pfx + "dust%d", 1, 3, CHAOS_DUST_SEC / sp,
			(CHAOS_DUST_AT + CHAOS_DUST_LIVE + 1.0) / sp)
		var t2 := du.create_tween()
		t2.tween_interval((CHAOS_DUST_AT + CHAOS_DUST_LIVE) / sp)
		t2.tween_property(du, "modulate:a", 0.0, 1.0 / sp)
		t2.tween_callback(du.queue_free)

	var ground_y := _screen_center(host).y + vis.y * 0.5
	for i in CHAOS_COVERS:
		var c := AtlasUI.spr_cocos("colosseum_ui",
			"scene_colosseum_dust_cover" if i % 2 == 0 else "scene_colosseum_dust")
		if c == null:
			break
		c.position = Vector2(ctrx + rng.randf_range(-vis.x * 0.45, vis.x * 0.45),
			ground_y - rng.randf_range(15.0, 70.0))
		c.z_index = 90
		c.modulate.a = 0.0
		host.add_child(c)
		var t3 := c.create_tween()
		t3.tween_interval((CHAOS_COVER_AT + float(i) * 0.05) / sp)
		t3.tween_property(c, "modulate:a", 1.0, 0.25 / sp)
		t3.tween_property(c, "position", c.position + Vector2(dir * 110.0, -20.0), 2.0 / sp)
		t3.parallel().tween_property(c, "modulate:a", 0.0, 2.0 / sp)
		t3.tween_callback(c.queue_free)

const SHADOW_SPINE_Z := 100
const SHADOW_SPINE_AT := 1.0
const SHADOW_SPINE_MAX := 3
const SHADOW_S2_SEC := 5.0

static func _run_shadow(host: CanvasItem, at: Vector2, sp: float, foes: Array) -> void:
	var el := "shadow"
	if not ResourceLoader.exists(SHADOW_SPINE_SCENE):
		return
	var ps := load(SHADOW_SPINE_SCENE) as PackedScene
	if ps == null:
		return
	var spots: Array = []
	for f in foes:
		if f is Vector2:
			spots.append(f)
	if spots.is_empty():
		spots.append(at)
	for i in mini(spots.size(), SHADOW_SPINE_MAX):
		var holder := Node2D.new()
		holder.position = spots[i]
		holder.z_index = SHADOW_SPINE_Z
		holder.visible = false
		host.add_child(holder)
		var inst = ps.instantiate()
		holder.add_child(inst)
		var ap := _find_anim_player(inst)
		var life := SHADOW_S2_SEC
		if ap != null and ap.has_animation("s2"):
			life = ap.get_animation("s2").length
			ap.stop()
		var t := holder.create_tween()
		t.tween_interval((elem_delay(el) + SHADOW_SPINE_AT) / sp)
		t.tween_callback(func() -> void:
			if not is_instance_valid(holder):
				return
			holder.visible = true
			if ap != null and is_instance_valid(ap) and ap.has_animation("s2"):
				ap.play("s2"))
		t.tween_interval(life / sp)
		t.tween_callback(holder.queue_free)

const TGT_PRE_POSE := {
	"aqua": [[3.25, "down"], [4.05, "love"]],
}

const TGT_FX_ON := ["chaos", "wind", "dark"]
const CH_TGT_AT := 1.95
const CH_TGT_RIDE := 6.0
const CH_TGT_HOP := 35.0
const CH_TGT_DRIFT := 25.0
const CH_TGT_LEAN := 40.0
const CH_TGT_FLAT := Vector2(1.25, 0.35)
const CH_TGT_HOLD := 1.0
const CH_TGT_SQUASH := 0.1

const WD_LEAD := 2.0
const WD_IN := 0.25
const WD_GAPS := [0.75, 0.5, 0.3, 0.15]
const WD_MOVES := [0.5, 0.5, 0.5, 0.5, 0.5]
const WD_OUT_X := 250.0
const WD_OUT_X2 := 300.0
const WD_LAND := 0.25

static func _wind_tumble(n: Node2D, a: Dictionary, sp: float) -> float:
	var vis: Vector2 = n.get_viewport().get_visible_rect().size
	var home: Vector2 = a.get("home", n.position)
	var bs := n.scale
	var mine := bool(a.get("mine", true))
	var ap = a.get("anim")
	var play := func(anim_name: String) -> void:
		play_pose(ap, anim_name)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var base_y := vis.y * 0.5 + 95.0
	var ys: Array[float] = []
	for i in 5:
		ys.append(float(rng.randi() % int(maxf(1.0, vis.y - 150.0))) + 75.0)
	var mx := func(x: float) -> float: return (vis.x - x) if mine else x
	var lo := func(off: float) -> float: return mx.call(-off)
	var hi := func(off: float) -> float: return mx.call(vis.x + off)
	var side_y := func(i: int) -> float: return base_y - 100.0 - ys[i] * 0.5
	var pts := [
		[Vector2(lo.call(WD_OUT_X), side_y.call(0)),
			Vector2(hi.call(WD_OUT_X2), side_y.call(1)), 0],
		[Vector2(hi.call(WD_OUT_X), vis.y - ys[1]),
			Vector2(lo.call(WD_OUT_X2), vis.y - ys[2]), 1],
		[Vector2(lo.call(WD_OUT_X), side_y.call(2)),
			Vector2(hi.call(WD_OUT_X2), side_y.call(3)), 0],
		[Vector2(hi.call(WD_OUT_X), vis.y - ys[3]),
			Vector2(lo.call(WD_OUT_X2), vis.y - ys[4]), 1],
		[Vector2(lo.call(WD_OUT_X), side_y.call(4)),
			Vector2(vis.x * 0.5 + float(rng.randi() % int(maxf(1.0, vis.x * 0.5))),
				-vis.y * 0.5), 0],
	]
	var lead := ACT_AT + WD_LEAD + float(rng.randi() % 6) * 0.005
	var t := _atw(n)
	t.tween_interval(lead / sp)
	t.tween_callback(func() -> void: play.call("damaged"))
	t.tween_property(n, "position", (pts[0][0] as Vector2), WD_IN / sp)
	t.tween_interval((float(rng.randi() % 6) * 0.005 + 0.5) / sp)
	var when := lead + WD_IN + 0.5
	for i in pts.size():
		var row: Array = pts[i]
		var dst: Vector2 = row[1]
		var small := int(row[2]) == 0
		var f := (float(rng.randi() % 6) * 0.05 + 0.5) if small \
			else (float(rng.randi() % 11) * 0.05 + 1.5)
		t.tween_callback(func() -> void:
			if is_instance_valid(n):
				n.position = (row[0] as Vector2))
		var mv := float(WD_MOVES[i])
		t.tween_property(n, "position", dst, mv / sp)
		var st := _atw(n)
		st.tween_interval(when / sp)
		st.tween_property(n, "scale", bs * f, mv * 0.5 / sp)
		st.tween_property(n, "scale", bs, mv * 0.5 / sp)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		when += mv
		if i < WD_GAPS.size():
			t.tween_interval(float(WD_GAPS[i]) / sp)
			when += float(WD_GAPS[i])
	t.tween_callback(func() -> void:
		if is_instance_valid(n):
			n.scale = bs
			n.position = home + Vector2(0.0, -vis.y * 0.35)
		play.call("down"))
	t.tween_property(n, "position", home, WD_LAND / sp)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(n, "position", home - Vector2(0.0, 60.0), WD_LAND / sp)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(n, "position", home, WD_LAND / sp)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void: play.call("wait"))
	return when + WD_LAND * 3.0

const DK_TGT_AT := 2.75
const DK_TGT_PULL := 2.5
const DK_TGT_HOLD := 1.25
const DK_TGT_GONE := 1.4
const DK_TGT_HITS := [4.75, 5.05, 5.35, 5.55, 5.75]
const DK_TGT_JUMP := 0.25

static func _dark_swallow(n: Node2D, a: Dictionary, sp := 1.0) -> float:
	var ap = a.get("anim")
	var home: Vector2 = a.get("home", n.position)
	var s := float(a.get("scale", 1.0))
	var away := -1.0 if bool(a.get("mine", true)) else 1.0
	var vis: Vector2 = n.get_viewport().get_visible_rect().size
	var vortex := Vector2(vis.x * 0.5, vis.y * 0.5)
	var play := func(anim_name: String) -> void:
		play_pose(ap, anim_name)

	for at_sec in DK_TGT_HITS:
		var pt := _atw(n)
		pt.tween_interval((ACT_AT + float(at_sec)) / sp)
		pt.tween_callback(func() -> void:
			Bgm.sfx("effect_dragon_damaged_%d" % (1 + (randi() & 1)), 0.35)
			play.call("damaged"))

	var t := _atw(n)
	t.tween_interval((ACT_AT + DK_TGT_AT) / sp)
	t.tween_callback(func() -> void: play.call("damaged"))
	t.tween_property(n, "position", vortex, DK_TGT_PULL / sp)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_interval(DK_TGT_HOLD / sp)
	t.tween_callback(func() -> void:
		if is_instance_valid(n):
			n.visible = false
		play.call("down"))
	t.tween_interval(DK_TGT_GONE / sp)
	t.tween_callback(func() -> void:
		if is_instance_valid(n):
			n.position = home + Vector2(away * 60.0, 0.0)
			n.visible = true)
	_jump_by(t, n, Vector2(-away * 60.0, 0.0), s * 100.0, 1, DK_TGT_JUMP / sp)
	_jump_by(t, n, Vector2.ZERO, s * 300.0, 1, DK_TGT_JUMP / sp)
	t.tween_callback(func() -> void:
		if is_instance_valid(n):
			n.position = home
		play.call("wait"))
	return ACT_AT + DK_TGT_AT + DK_TGT_PULL + DK_TGT_HOLD + DK_TGT_GONE + DK_TGT_JUMP * 2.0

const TGT_STEPS := {
	"aqua": [
		["wait", 1.0], ["pull", 0.25, 150.0], ["wait", 0.5],
		["drift", 3.0, 60.0], ["drift", 2.5, 40.0],
		["wait", 0.25 + 0.75 + 0.5],
		["home", 0.25, 175.0],
	],
	"earth": [
		["wait", 1.0], ["pull", 0.25, 150.0], ["wait", 0.5],
		["hop", 0.2, 150.0], ["wait", 0.3],
		["hop", 0.2, 150.0], ["wait", 0.3],
		["hop", 0.2, 150.0], ["wait", 0.3],
		["hop", 0.2, 150.0], ["wait", 0.7],
		["big", 0.5, 800.0],
		["wait", 0.5],
		["home", 0.25, 100.0],
	],
	"fire": [
		["wait", 1.0], ["pull", 0.25, 150.0], ["wait", 0.5 + 0.15],
		["hop", 0.5, 200.0], ["wait", 0.25],
		["hop", 0.5, 175.0], ["wait", 0.15],
		["hop", 0.5, 150.0],
		["hop", 0.45, 140.0], ["hop", 0.4, 140.0], ["hop", 0.3, 100.0], ["hop", 0.25, 90.0],
		["hop", 0.15, 70.0], ["hop", 0.15, 70.0], ["hop", 0.15, 70.0],
		["hop", 0.125, 60.0], ["hop", 0.125, 60.0], ["hop", 0.125, 60.0], ["hop", 0.125, 60.0],
		["hop", 0.125, 60.0], ["hop", 0.125, 60.0], ["hop", 0.125, 60.0], ["hop", 0.125, 60.0],
		["hop", 0.1, 50.0],
		["wait", 0.5],
		["big", 0.4, 150.0], ["hop", 0.2, 50.0],
		["wait", 1.75],
		["home", 0.25, 150.0],
	],
	"holy": [
		["wait", 1.25 + 3.25],
		["hop", 0.95, 100.0],
		["wait", 1.25 + 0.2],
		["hide", 1.25 + 0.25],
		["home", 0.0, 0.0],
	],
	"light": [
		["wait", 2.5],
		["drift", 4.75, 80.0],
		["wait", 1.5],
		["drift", 0.1, 20.0],
		["hop", 0.1, 75.0], ["hop", 0.05, 20.0],
		["wait", 0.75],
		["home", 0.25, 150.0],
	],
	"shadow": [
		["wait", 3.0], ["pull", 0.2, 150.0], ["wait", 0.2],
		["hop", 0.2, 150.0], ["wait", 0.2],
		["hop", 0.2, 150.0], ["wait", 0.2],
		["hop", 0.2, 150.0], ["wait", 0.2],
		["hop", 0.2, 150.0], ["wait", 0.2],
		["big", 0.5, 1000.0],
		["wait", 1.2],
		["home", 0.25, 100.0],
	],
}
const TGT_HOP_DX := 20.0

const TGT_BODY := {
	"earth":  {"hit_rot": 25.0, "hit_flat": 0.75, "hit_sec": 0.2, "spin": [0.9, 1800.0]},
	"shadow": {"hit_rot": 22.0, "hit_flat": 0.75, "hit_sec": 0.15, "spin": [0.8, 1800.0]},
	"fire":   {"land": true},
	"aqua":   {"land": true},
	"holy":   {"blink": 1.4, "land": true},
	"light":  {"scorch": 3.5, "land": true},
}
const TGT_LAND_SEC := 0.1
const TGT_SCORCH_RED := Color8(255, 50, 0)
const TGT_SCORCH_ROT := 45.0

static func _tgt_land(t: Tween, n: Node2D, bs: Vector2, sp: float) -> void:
	t.tween_property(n, "scale", Vector2(bs.x * 0.95, bs.y * 1.05), TGT_LAND_SEC / sp)
	t.tween_property(n, "scale", Vector2(bs.x * 1.05, bs.y * 0.95), TGT_LAND_SEC / sp)
	t.tween_property(n, "scale", bs, TGT_LAND_SEC / sp)

static func _tgt_body(n: Node2D, el: String, away: float, sp: float) -> void:
	var cfg: Dictionary = TGT_BODY.get(el, {})
	if cfg.is_empty():
		return
	var bs := n.scale
	if cfg.has("blink"):
		var b := _atw(n)
		b.tween_interval((ACT_AT + float(cfg["blink"])) / sp)
		b.tween_property(n, "modulate:a", 150.0 / 255.0, 0.3 / sp)
		b.tween_property(n, "modulate:a", 1.0, 0.25 / sp)
		b.tween_interval(0.15 / sp)
		b.tween_property(n, "modulate:a", 150.0 / 255.0, 0.25 / sp)
		b.tween_property(n, "modulate:a", 1.0, 0.25 / sp)
	if cfg.has("scorch"):
		var s := _atw(n)
		s.tween_interval((ACT_AT + float(cfg["scorch"])) / sp)
		s.tween_property(n, "rotation_degrees", away * TGT_SCORCH_ROT, 3.75 / sp)
		s.parallel().tween_property(n, "modulate", TGT_SCORCH_RED, 3.75 / sp)
		s.tween_property(n, "modulate", Color(0, 0, 0, 1), 0.75 / sp)
		s.tween_interval(0.75 / sp)
		s.tween_property(n, "rotation_degrees", 0.0, 0.1 / sp)
		s.tween_interval(0.15 / sp)
		s.tween_property(n, "modulate", Color(1, 1, 1, 1), 0.75 / sp)
		_tgt_land(s, n, bs, sp)

static func _target_knock(n: Node2D, a: Dictionary, el: String, sp: float) -> float:
	var steps: Array = TGT_STEPS.get(el, [])
	if steps.is_empty():
		return -1.0
	var ap = a.get("anim")
	var home: Vector2 = a.get("home", n.position)
	var stage: Vector2 = a.get("stage", home)
	var s := float(a.get("scale", 1.0))
	var away := -1.0 if bool(a.get("mine", true)) else 1.0
	var bs := n.scale
	_tgt_body(n, el, away, sp)
	var play := func(anim_name: String) -> void:
		play_pose(ap, anim_name)
	for pre: Array in TGT_PRE_POSE.get(el, []):
		var pt := _atw(n)
		pt.tween_interval(maxf(0.01, float(pre[0]) / sp))
		var pname := String(pre[1])
		pt.tween_callback(func() -> void: play.call(pname))
	var t := _atw(n)
	t.tween_interval(ACT_AT / sp)
	var total := ACT_AT
	var hits := 0
	for row: Array in steps:
		var kind := String(row[0])
		match kind:
			"wait":
				t.tween_interval(float(row[1]) / sp)
				total += float(row[1])
			"pull":
				_arc(t, n, stage, float(row[2]) * s, float(row[1]) / sp)
				total += float(row[1])
			"hop", "big":
				var is_big := kind == "big"
				var idx := hits
				hits += 1
				t.tween_callback(func() -> void:
					if is_big:
						play.call("down")
					else:
						play.call("damaged")
					Bgm.sfx("effect_dragon_damaged_%d" % (1 + idx % 2),
						float(randi() % 6) * 0.05 + 0.25))
				var bcfg: Dictionary = TGT_BODY.get(el, {})
				if is_big and bcfg.has("spin"):
					var spn: Array = bcfg["spin"]
					var rt := _atw(n)
					rt.tween_interval(total / sp)
					rt.tween_property(n, "rotation_degrees",
						away * float(spn[1]), float(spn[0]) / sp).as_relative()
					rt.tween_callback(func() -> void:
						if is_instance_valid(n):
							n.rotation_degrees = 0.0)
				elif not is_big and bcfg.has("hit_rot"):
					var hs := float(bcfg.get("hit_sec", 0.15))
					var rt2 := _atw(n)
					rt2.tween_interval(total / sp)
					rt2.tween_property(n, "rotation_degrees",
						away * float(bcfg["hit_rot"]), hs / sp).as_relative()
					if bcfg.has("hit_flat"):
						var fl := float(bcfg["hit_flat"])
						var ft := _atw(n)
						ft.tween_interval(total / sp)
						ft.tween_property(n, "scale",
							Vector2(bs.x, bs.y * fl), 0.05 / sp)
						ft.tween_property(n, "scale", bs, 0.05 / sp)
				_jump_by(t, n, Vector2(away * TGT_HOP_DX * s, 0.0), float(row[2]) * s, 1,
					float(row[1]) / sp)
				total += float(row[1])
			"drift":
				_jump_by(t, n, Vector2(away * float(row[2]) * s, 0.0), 0.0, 1,
					float(row[1]) / sp)
				total += float(row[1])
			"hide":
				t.tween_callback(func() -> void:
					if is_instance_valid(n):
						n.visible = false)
				t.tween_interval(float(row[1]) / sp)
				t.tween_callback(func() -> void:
					if is_instance_valid(n):
						n.position = home
						n.visible = true)
				total += float(row[1])
			"home":
				if float(row[1]) > 0.0:
					_arc(t, n, home, float(row[2]) * s, float(row[1]) / sp)
					total += float(row[1])
				t.tween_callback(func() -> void:
					if is_instance_valid(n):
						n.position = home
						n.rotation_degrees = 0.0
					play.call("wait"))
				if bool(TGT_BODY.get(el, {}).get("land", false)):
					var lt := _atw(n)
					lt.tween_interval(total / sp)
					_tgt_land(lt, n, bs, sp)
					total += TGT_LAND_SEC * 3.0
	return total

static func play_pose(ap, anim_name: String) -> void:
	if not (ap is AnimationPlayer) or not is_instance_valid(ap):
		return
	var p := ap as AnimationPlayer
	if not p.has_animation(anim_name):
		return
	p.get_animation(anim_name).loop_mode = \
		Animation.LOOP_LINEAR if anim_name == "wait" else Animation.LOOP_NONE
	p.play(anim_name)

static func _atw(n: Node2D) -> Tween:
	var t := n.create_tween()
	var arr: Array = n.get_meta("ufx_tw", [])
	arr.append(t)
	n.set_meta("ufx_tw", arr)
	return t

static func reset_actor(n: Node2D, home := Vector2.INF) -> void:
	if not is_instance_valid(n):
		return
	for t in n.get_meta("ufx_tw", []):
		if t is Tween and (t as Tween).is_valid():
			(t as Tween).kill()
	n.set_meta("ufx_tw", [])
	if not n.has_meta("ufx_base_scale"):
		n.set_meta("ufx_base_scale", n.scale)
	n.scale = n.get_meta("ufx_base_scale")
	n.rotation_degrees = 0.0
	n.modulate = Color(1, 1, 1, 1)
	n.visible = true
	if home != Vector2.INF:
		n.position = home

static func target_fx(a: Dictionary, el: String, sp := 1.0) -> float:
	var node = a.get("node")
	if not (node is Node2D) or not is_instance_valid(node):
		return -1.0
	var n := node as Node2D
	reset_actor(n, a.get("home", Vector2.INF))
	if not TGT_FX_ON.has(el):
		return _target_knock(n, a, el, sp)
	if el == "wind":
		return _wind_tumble(n, a, sp)
	if el == "dark":
		return _dark_swallow(n, a, sp)
	var ap = a.get("anim")
	var home: Vector2 = a.get("home", n.position)
	var bs := n.scale
	var play := func(anim_name: String) -> void:
		play_pose(ap, anim_name)
	var away := -1.0 if bool(a.get("mine", true)) else 1.0
	var s := float(a.get("scale", 1.0))

	var t := _atw(n)
	t.tween_interval(CH_TGT_AT / sp)
	_jump_by(t, n, Vector2(away * CH_TGT_DRIFT * s, 0.0), CH_TGT_HOP * s, 1,
		CH_TGT_RIDE / sp)
	t.tween_callback(func() -> void:
		if is_instance_valid(n):
			n.position = home)

	var b := _atw(n)
	b.tween_interval(CH_TGT_AT / sp)
	b.tween_callback(func() -> void: play.call("damaged"))
	b.tween_property(n, "rotation_degrees", away * CH_TGT_LEAN, CH_TGT_RIDE / sp)
	b.tween_callback(func() -> void:
		if is_instance_valid(n):
			n.rotation_degrees = 0.0
			n.scale = Vector2(bs.x * CH_TGT_FLAT.x, bs.y * CH_TGT_FLAT.y)
		play.call("down"))
	b.tween_interval(CH_TGT_HOLD / sp)
	b.tween_callback(func() -> void:
		if is_instance_valid(n):
			n.scale = bs
			n.position = home
		play.call("wait"))
	b.tween_property(n, "scale", Vector2(bs.x * 0.95, bs.y * 1.05), CH_TGT_SQUASH / sp)
	b.tween_property(n, "scale", Vector2(bs.x * 1.05, bs.y * 0.95), CH_TGT_SQUASH / sp)
	b.tween_property(n, "scale", bs, CH_TGT_SQUASH / sp)

	return (CH_TGT_AT + CH_TGT_RIDE + CH_TGT_HOLD + CH_TGT_SQUASH * 3.0) / sp

static func caster_fx(a: Dictionary, el: String, sp := 1.0) -> float:
	var node = a.get("node")
	if not (node is Node2D) or not is_instance_valid(node):
		return 0.0
	var n := node as Node2D
	reset_actor(n, a.get("home", Vector2.INF))
	var ap = a.get("anim")
	var shadow = a.get("shadow")
	var home: Vector2 = a.get("home", n.position)
	var stage: Vector2 = a.get("stage", n.position)
	var s := float(a.get("scale", 1.0))
	var host = a.get("host")
	var ctr := _screen_center(host) if host is CanvasItem else stage
	var dirc := 1.0 if stage.x <= ctr.x else -1.0
	var play := func(anim_name: String) -> void:
		play_pose(ap, anim_name)
	var anim_at := func(t: float, anim_name: String) -> void:
		var tw: Tween = _atw(n)
		tw.tween_interval(maxf(0.01, t) / sp)
		tw.tween_callback(func() -> void: play.call(anim_name))
	var back := 0.0

	match el:
		"fire":
			var t := _atw(n)
			t.tween_interval((ACT_AT + 0.25) / sp)
			_jump_by(t, n, Vector2(0.0, s * 75.0), 50.0, 1, 0.15 / sp)
			t.tween_property(n, "position", Vector2(0.0, -50.0), 4.35 / sp).as_relative()\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t.tween_interval(3.0 / sp)
			t.tween_property(n, "position", home, 0.15 / sp)
			anim_at.call(ACT_AT + 0.4, "ultimate1")
			anim_at.call(ACT_AT + 4.2, "ultimate2")
			back = ACT_AT + 0.25 + 0.15 + 4.35 + 3.0 + 0.15
		"shadow":
			var t := _atw(n)
			t.tween_interval((ACT_AT + 0.5) / sp)
			t.tween_property(n, "modulate", Color(0, 0, 0, 1), 0.5 / sp)
			t.tween_callback(func() -> void:
				if is_instance_valid(n):
					n.modulate = Color(0, 0, 0, 0))
			t.tween_interval(7.75 / sp)
			t.tween_callback(func() -> void:
				if is_instance_valid(n):
					n.position = home
					n.modulate = Color(0, 0, 0, 1))
			t.tween_property(n, "modulate", Color(1, 1, 1, 1), 0.5 / sp)
			if shadow is Node2D and is_instance_valid(shadow):
				var sh2 := shadow as Node2D
				var sb2 := sh2.scale
				var st3 := sh2.create_tween()
				st3.tween_interval((ACT_AT + 1.0) / sp)
				st3.tween_property(sh2, "scale", Vector2.ZERO, 0.25 / sp)
				st3.tween_interval(6.9 / sp)
				st3.tween_property(sh2, "scale", sb2, 0.25 / sp)
			anim_at.call(ACT_AT + 0.25, "ultimate1")
			back = ACT_AT + 9.25
		"dark":
			var t := _atw(n)
			t.tween_interval((ACT_AT + 0.5) / sp)
			t.tween_property(n, "modulate", Color(0, 0, 0, 1), 0.5 / sp)
			t.tween_callback(func() -> void:
				if is_instance_valid(n):
					n.modulate = Color(0, 0, 0, 0))
			t.tween_interval(7.75 / sp)
			t.tween_callback(func() -> void:
				if is_instance_valid(n):
					n.position = home
					n.modulate = Color(0, 0, 0, 1))
			t.tween_property(n, "modulate", Color(1, 1, 1, 1), 0.5 / sp)
			if shadow is Node2D and is_instance_valid(shadow):
				var sh := shadow as Node2D
				var sb := sh.scale
				var st2 := sh.create_tween()
				st2.tween_interval((ACT_AT + 1.0) / sp)
				st2.tween_property(sh, "scale", Vector2.ZERO, 0.25 / sp)
				st2.tween_interval(7.25 / sp)
				st2.tween_property(sh, "scale", sb, 0.25 / sp)
			anim_at.call(ACT_AT + 0.25, "ultimate1")
			back = ACT_AT + 9.25
		"aqua":
			var t := _atw(n)
			t.tween_interval((ACT_AT + 2.75) / sp)
			t.tween_property(n, "position", Vector2(dirc * 40.0, -30.0), 0.5 / sp)\
				.as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t.tween_property(n, "position", Vector2(dirc * 90.0, -25.0), 2.0 / sp)\
				.as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			t.tween_property(n, "position", Vector2(dirc * -30.0, 25.0), 2.5 / sp)\
				.as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			t.tween_interval(1.0 / sp)
			_jump_by(t, n, Vector2(home.x - n.position.x, 0.0), s * 150.0, 1, 0.25 / sp)
			t.tween_callback(func() -> void:
				if is_instance_valid(n):
					n.position = home)
			anim_at.call(ACT_AT + 2.0, "ultimate1")
			back = ACT_AT + 2.75 + 5.0 + 1.0 + 0.25
			if shadow is CanvasItem and is_instance_valid(shadow):
				var st: Tween = (shadow as CanvasItem).create_tween()
				st.tween_interval((ACT_AT + 1.25) / sp)
				st.tween_property(shadow, "modulate:a", 0.0, 0.5 / sp)
				st.tween_interval(7.0 / sp)
				st.tween_property(shadow, "modulate:a", 1.0, 0.25 / sp)
		"earth":
			var hops := [[0.3, 150.0, 50.0], [0.3, 200.0, 40.0], [0.3, 250.0, 30.0],
				[0.3, 300.0, -30.0], [0.5, 400.0, -40.0], [0.3, 350.0, -50.0]]
			var t := _atw(n)
			t.tween_interval((ACT_AT + 1.45) / sp)
			for h_e in hops:
				t.tween_interval(0.2 / sp)
				_jump_by(t, n, Vector2(dirc * float(h_e[2]), 0.0), s * float(h_e[1]), 1,
					float(h_e[0]) / sp)
			t.tween_interval(0.2 / sp)
			t.tween_property(n, "position", stage, 0.1 / sp)
			t.tween_interval(1.65 / sp)
			_jump_by(t, n, Vector2(home.x - stage.x, home.y - stage.y), s * 200.0, 1,
				0.25 / sp)
			t.tween_callback(func() -> void:
				if is_instance_valid(n):
					n.position = home)
			anim_at.call(ACT_AT + 0.2, "ultimate1")
			anim_at.call(ACT_AT + 3.5, "ultimate2")
			back = ACT_AT + 1.45 + (0.2 + 0.3) * 5.0 + 0.2 + 0.5 + 0.2 + 0.1 + 1.65 + 0.25
		"wind":
			var t := _atw(n)
			t.tween_interval((ACT_AT + 2.0) / sp)
			t.tween_property(n, "position", Vector2(0.0, -140.0), 0.15 / sp).as_relative()
			t.tween_property(n, "position", Vector2(dirc * 60.0, -60.0), 0.5 / sp).as_relative()
			t.tween_property(n, "position", Vector2(dirc * -80.0, -35.0), 0.25 / sp).as_relative()
			t.tween_property(n, "position", Vector2(dirc * 20.0, -15.0), 0.1 / sp).as_relative()
			t.tween_interval(4.15 / sp)
			t.tween_property(n, "position", home, 0.15 / sp)
			anim_at.call(ACT_AT + 1.8, "ultimate1")
			back = ACT_AT + 2.0 + 1.0 + 4.15 + 0.15
			if shadow is Node2D and is_instance_valid(shadow):
				var sn := shadow as Node2D
				var bs := sn.scale
				var st: Tween = sn.create_tween()
				st.tween_interval((ACT_AT + 2.0) / sp)
				st.tween_property(sn, "scale", bs * (s + 0.75), 0.15 / sp)
				st.tween_interval(0.5 / sp)
				st.tween_property(sn, "scale", bs * (s + 0.9), 0.25 / sp)
				st.tween_property(sn, "scale", Vector2.ZERO, 0.1 / sp)
				st.tween_interval(4.15 / sp)
				st.tween_property(sn, "scale", bs, 0.15 / sp)
		"light":
			var t := _atw(n)
			t.tween_interval((ACT_AT + 1.55) / sp)
			t.tween_property(n, "position", Vector2(ctr.x, stage.y), 0.2 / sp)
			t.tween_interval(0.75 / sp)
			t.tween_property(n, "modulate:a", 0.0, 0.15 / sp)
			t.tween_interval(5.0 / sp)
			t.tween_property(n, "modulate:a", 1.0, 0.25 / sp)
			t.tween_interval(1.0 / sp)
			_jump_by(t, n, Vector2(home.x - ctr.x, 0.0), s * 150.0, 1, 0.25 / sp)
			t.tween_callback(func() -> void:
				if is_instance_valid(n):
					n.position = home)
			anim_at.call(ACT_AT + 0.25, "ultimate1")
			back = ACT_AT + 1.55 + 0.2 + 0.75 + 0.15 + 5.0 + 0.25 + 1.0 + 0.25
		"chaos":
			var CHAOS_GONE := 1.6
			var CHAOS_BEAM := 0.18
			var CHAOS_BURN := 6.5
			var CHAOS_HOME := 8.6
			var bs := n.scale
			var t := _atw(n)
			t.tween_interval(CHAOS_GONE / sp)
			t.tween_property(n, "scale", Vector2(bs.x * 1.15, bs.y * 0.7), 0.1 / sp)
			t.tween_property(n, "scale", Vector2(bs.x * 0.15, bs.y * 1.35), 0.12 / sp)
			t.parallel().tween_property(n, "modulate:a", 0.0, 0.12 / sp)
			t.tween_interval((ACT_AT - CHAOS_GONE - 0.22) / sp)
			t.tween_callback(func() -> void:
				if is_instance_valid(n):
					n.position = Vector2(ctr.x, stage.y)
					n.scale = Vector2(bs.x * 0.04, bs.y * 1.3)
					n.modulate = Color(0.85, 0.05, 0.05, 1.0))
			t.tween_interval(CHAOS_BEAM / sp)
			t.tween_property(n, "scale", bs, 0.12 / sp)
			t.parallel().tween_property(n, "modulate", Color(0.32, 0.05, 0.06, 1.0), 0.12 / sp)
			t.tween_interval((CHAOS_BURN - ACT_AT - CHAOS_BEAM - 0.12) / sp)
			t.tween_property(n, "modulate:a", 0.0, 0.3 / sp)
			t.tween_interval((CHAOS_HOME - CHAOS_BURN - 0.3) / sp)
			t.tween_callback(func() -> void:
				if is_instance_valid(n):
					n.modulate = Color(1, 1, 1, 0)
					n.scale = bs
					n.position = home)
			t.tween_property(n, "modulate:a", 1.0, 0.3 / sp)
			anim_at.call(ACT_AT + 0.4, "ultimate1")
			back = CHAOS_HOME + 0.3
		"holy":
			var t := _atw(n)
			t.tween_interval((ACT_AT + 2.25) / sp)
			t.tween_property(n, "modulate:a", 0.0, 1.0 / sp)
			t.tween_interval(2.0 / sp)
			t.tween_property(n, "modulate:a", 1.0, 1.0 / sp)
			anim_at.call(ACT_AT + 0.4, "ultimate1")
			back = ACT_AT + 2.25 + 1.0 + 2.0 + 1.0
		_:
			back = ACT_AT + 7.0
	anim_at.call(back + 0.1, "wait")
	return back / sp

static func _ease_io(x: float, rate: float) -> float:
	var t := x * 2.0
	if t < 1.0:
		return 0.5 * pow(t, rate)
	return 1.0 - 0.5 * pow(2.0 - t, rate)

static func _jump_by(t: Tween, n: Node2D, delta: Vector2, h: float, jumps: int,
		sec: float, rate := 0.0) -> void:
	var from := [Vector2.ZERO, false]
	var j := maxi(1, jumps)
	t.tween_method(func(x: float) -> void:
		if not is_instance_valid(n):
			return
		if not bool(from[1]):
			from[0] = n.position
			from[1] = true
		var u := x if rate <= 0.0 else _ease_io(x, rate)
		var frac := fmod(u * float(j), 1.0)
		var hop := h * 4.0 * frac * (1.0 - frac)
		n.position = (from[0] as Vector2) + Vector2(delta.x * u, -(delta.y * u + hop)),
		0.0, 1.0, maxf(0.01, sec))

static func _screen_center(host: CanvasItem) -> Vector2:
	var vis: Vector2 = host.get_viewport().get_visible_rect().size
	return host.get_global_transform_with_canvas().affine_inverse() * (vis * 0.5)

static func _ease_in_by(t: Tween, n: Node2D, delta: Vector2, sec: float, rate: float) -> void:
	var from := [Vector2.ZERO, false]
	t.tween_method(func(x: float) -> void:
		if not is_instance_valid(n):
			return
		if not bool(from[1]):
			from[0] = n.position
			from[1] = true
		n.position = (from[0] as Vector2) + delta * pow(x, rate),
		0.0, 1.0, maxf(0.01, sec))

static func _arc(t: Tween, n: Node2D, to: Vector2, h: float, sec: float) -> void:
	var from := [Vector2.ZERO, false]
	t.tween_method(func(x: float) -> void:
		if not is_instance_valid(n):
			return
		if not bool(from[1]):
			from[0] = n.position
			from[1] = true
		var p := (from[0] as Vector2).lerp(to, x)
		p.y -= h * 4.0 * x * (1.0 - x)
		n.position = p,
		0.0, 1.0, sec)

static func _run_fallback(host: CanvasItem, el: String, at: Vector2,
		sp: float, mat: CanvasItemMaterial, alive: Callable) -> void:
	var man := manifest(el)
	var fam := longest_family(man, prefix(el))
	if fam.is_empty():
		return
	var spr := _spr(el, fam[0])
	if spr == null:
		return
	spr.position = at
	spr.z_index = 101
	host.add_child(spr)
	var i := 0
	var t := Timer.new()
	t.wait_time = FALLBACK_FRAME_SEC / sp
	t.autostart = true
	spr.add_child(t)
	t.timeout.connect(func() -> void:
		i += 1
		var ok := true if not alive.is_valid() else bool(alive.call())
		if not ok or i >= fam.size():
			if is_instance_valid(spr):
				spr.queue_free()
			return
		_set_frame(spr, el, String(fam[i])))

static func _play_frames(spr: Node2D, el: String, fmt: String, lo: int, hi: int,
		sec: float, free_at_end := false, loop := false) -> void:
	var n := [lo]
	var t := Timer.new()
	t.wait_time = maxf(0.01, sec)
	t.autostart = true
	spr.add_child(t)
	t.timeout.connect(func() -> void:
		if not is_instance_valid(spr):
			return
		if n[0] > hi:
			if loop:
				n[0] = lo
			elif free_at_end:
				spr.queue_free()
				return
			else:
				t.stop()
				return
		_set_frame(spr, el, fmt % n[0])
		n[0] += 1)

static func _loop_frames(spr: Node2D, el: String, fmt: String, lo: int, hi: int,
		sec: float, total := 0.0) -> void:
	var n := [lo]
	var t := Timer.new()
	t.wait_time = maxf(0.01, sec)
	t.autostart = true
	spr.add_child(t)
	var elapsed := [0.0]
	t.timeout.connect(func() -> void:
		if not is_instance_valid(spr):
			return
		elapsed[0] += t.wait_time
		if total > 0.0 and elapsed[0] >= total:
			t.stop()
			return
		_set_frame(spr, el, fmt % n[0])
		n[0] = lo if n[0] >= hi else n[0] + 1)

static func _play_frame_seq(spr: Node2D, el: String, fmt: String, nums: Array,
		sec: float, loop_from := -1) -> Timer:
	var i := [0]
	var t := Timer.new()
	t.wait_time = maxf(0.01, sec)
	t.autostart = true
	spr.add_child(t)
	t.timeout.connect(func() -> void:
		if not is_instance_valid(spr):
			return
		if i[0] >= nums.size():
			if loop_from < 0 or loop_from >= nums.size():
				t.stop()
				return
			i[0] = loop_from
		_set_frame(spr, el, fmt % int(nums[i[0]]))
		i[0] += 1)
	return t

static func _loop_frames_rev(spr: Node2D, el: String, fmt: String, hi: int, lo: int,
		sec: float, total := 0.0) -> void:
	var n := [hi]
	var t := Timer.new()
	t.wait_time = maxf(0.01, sec)
	t.autostart = true
	spr.add_child(t)
	var elapsed := [0.0]
	t.timeout.connect(func() -> void:
		if not is_instance_valid(spr):
			return
		elapsed[0] += t.wait_time
		if total > 0.0 and elapsed[0] >= total:
			t.stop()
			return
		_set_frame(spr, el, fmt % n[0])
		n[0] = hi if n[0] <= lo else n[0] - 1)

static func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null

static func longest_family(man: Dictionary, pfx: String) -> Array:
	for b in families(man, pfx):
		return b["frames"]
	return []

static func families(man: Dictionary, pfx: String) -> Array:
	var groups := {}
	for k in man:
		var s := String(k)
		if not s.begins_with(pfx) or s.begins_with(pfx + "circle"):
			continue
		var tail := s.substr(pfx.length())
		var base := tail.rstrip("0123456789")
		if base == tail:
			continue
		if not groups.has(base):
			groups[base] = []
		(groups[base] as Array).append(s)
	var out: Array = []
	for b in groups:
		var arr: Array = groups[b]
		arr.sort_custom(func(x, y): return _frame_no(String(x)) < _frame_no(String(y)))
		out.append({"name": String(b), "frames": arr})
	out.sort_custom(func(x, y): return x["frames"].size() > y["frames"].size())
	return out

static func _frame_no(key: String) -> int:
	var digits := ""
	for i in range(key.length() - 1, -1, -1):
		var c := key[i]
		if c < "0" or c > "9":
			break
		digits = c + digits
	return int(digits) if digits != "" else 0

static func manifest(element: String) -> Dictionary:
	return _man(DIR_PREFIX + element)

static func prefix(element: String) -> String:
	return "skill_ultimate_%s_%s_" % [element, element]

static func _man(dir: String) -> Dictionary:
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

static func _tex(element: String, key: String) -> Texture2D:
	return AtlasUI.tex(DIR_PREFIX + element, key)

static var used_keys := {}

const BOTTOM := Vector2(0.5, 0.0)

static func _spr_a(element: String, key: String, anchor: Vector2) -> Node2D:
	used_keys[element + "/" + key] = true
	var n := AtlasUI.spr_cocos(DIR_PREFIX + element, key, 1.0, anchor)
	if n != null:
		n.set_meta("anchor", anchor)
	return n

static func _spr(element: String, key: String) -> Node2D:
	used_keys[element + "/" + key] = true
	return AtlasUI.spr_cocos(DIR_PREFIX + element, key)

static func _set_alpha(n: CanvasItem, a: float) -> void:
	n.modulate = Color(a, a, a, a)

static func _fade_pma(t: Tween, n: CanvasItem, a: float, sec: float) -> PropertyTweener:
	return t.tween_property(n, "modulate", Color(a, a, a, a), sec)

static func _set_frame(holder: Node2D, element: String, key: String) -> bool:
	if not is_instance_valid(holder) or holder.get_child_count() == 0:
		return false
	var dir := DIR_PREFIX + element
	var t := AtlasUI.tex(dir, key)
	if t == null:
		return false
	used_keys[element + "/" + key] = true
	var s := holder.get_child(0) as Sprite2D
	if s == null:
		return false
	var S := Design.ASSET_SCALE
	var info: Dictionary = AtlasUI.manifest(dir).get(key, {})
	var src: Array = info.get("src", [float(info.get("w", t.get_width())),
		float(info.get("h", t.get_height()))])
	var off: Array = info.get("off", [0, 0])
	var anchor: Vector2 = holder.get_meta("anchor", Vector2(0.5, 0.5))
	s.texture = t
	s.position = Vector2(
		(0.5 - anchor.x) * float(src[0]) * S + float(off[0]) * S,
		(anchor.y - 0.5) * float(src[1]) * S - float(off[1]) * S)
	return true
