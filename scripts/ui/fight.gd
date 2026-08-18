extends Control

const CO := "colosseum_ui"
const NP := "ninepatch_ui"
const CM := "common_ui"
const ST := "stand_ui"
const BG_DIR := "res://assets/converted/colosseum_bg"

const SLOT_OFF := [Vector2(335.0, 262.5), Vector2(200.0, 350.0), Vector2(135.0, 175.0)]
const DRAGON_SCALE_TEAM := 0.75
const DRAGON_SCALE_SOLO := 1.0

const SOLO_SLOT := Vector2(225.0, -50.0)
const BAR_DY := 12.0
const BAR_W := 168.0
const BAR_H := 16.0

var _pma: CanvasItemMaterial
var _params: Dictionary = {}
var _rng := RandomNumberGenerator.new()

var _mode := "team"
var _foe: Dictionary = {}
var _my: Array = []
var _fo: Array = []
var _views: Dictionary = {}
var _events: Array = []
var _winner := ""
var _gen := 0
var _log: Label
var _stage: Dictionary = {}

func enter(params: Dictionary = {}) -> void:
	_params = params
	if _pma != null:
		_rebuild()

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_rng.randomize()
	Bgm.play(Colosseum.battle_bgm(_rng))
	_rebuild()

func _rebuild() -> void:
	_gen += 1
	for c in get_children():
		c.queue_free()
	_views.clear()
	_log_lines.clear()
	_skipped = false
	_folded = true
	_speed = _saved_speed()

	_mode = String(_params.get("mode", "team"))
	_foe = _params.get("opponent", {})
	var uids: Array = _params.get("party", [])
	if uids.is_empty():
		uids = UserDB.party()
	var n := Colosseum.party_size(_mode)

	var forced := String(_params.get("stage_element", ""))
	_stage = Colosseum.stage_of(forced) if forced != "" else {}
	if _stage.is_empty():
		_stage = Colosseum.roll_stage(_rng)
	var sel := String(_stage.get("element", ""))

	_my = PartyStats.summary(uids.slice(0, n), false, "", {}, sel)
	_fo = PartyStats.summary_of((_foe.get("dragons", []) as Array).slice(0, n), false, "", {}, sel)
	_apply_passives()

	var vis := _vis()
	_build_bg(vis)
	var my_recs: Array = []
	for u in uids.slice(0, n):
		my_recs.append(UserDB.get_dragon(int(u)))
	_build_team(_my, true, vis, my_recs)
	_build_team(_fo, false, vis, (_foe.get("dragons", []) as Array).slice(0, n))
	_align_ground()
	_build_top(vis)
	_build_log(vis)
	_start(maxf(_build_stage_roulette(vis), _appear_intro(vis)))

func _build_bg(vis: Vector2) -> void:
	var tr := TextureRect.new()
	tr.texture = _stage_bg_tex(String(_stage.get("element", "")))
	tr.size = vis
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.z_index = BG_Z
	add_child(tr)
	_bg = tr

var _bg: TextureRect
var _bg_cache: Dictionary = {}
func _stage_bg_tex(element: String) -> Texture2D:
	var map: Dictionary = Colosseum.stage_cfg().get("bg", {})
	var n := int(map.get(element, 3))
	if _bg_cache.has(n):
		return _bg_cache[n]
	var p := "%s/stage_%d.jpg" % [BG_DIR, n]
	if not ResourceLoader.exists(p):
		p = "%s/stage_3.jpg" % BG_DIR
	var t: Texture2D = load(p) if ResourceLoader.exists(p) else null
	_bg_cache[n] = t
	return t

const ELE_FRAME := {
	"earth": "ground", "aqua": "water", "fire": "fire", "wind": "wind",
	"light": "light", "dark": "dark", "holy": "holy", "chaos": "chaos", "shadow": "shadow",
}
const STAGE_ANCHOR := Vector2(10.0, 50.0)

func _build_stage_roulette(vis: Vector2) -> float:
	if _stage.is_empty():
		return 0.0
	var A: Dictionary = Colosseum.stage_cfg().get("anim", {})
	var step_sec := float(A.get("step_sec", 0.1))
	var step_px := float(A.get("step_px", 150.0))
	var base_steps := int(A.get("base_steps", 11))
	var window := int(A.get("window", 3))
	var fade := float(A.get("fade_sec", 0.3))
	var icon_s := float(A.get("icon_scale", 0.825))
	var lead := float(A.get("lead_sec", 1.0))
	var idx := int(_stage.get("index", 0))
	var wheel := Colosseum.stage_wheel()
	if wheel.is_empty():
		return 0.0
	var total := base_steps + idx

	var bar := _spr(CO, "scene_colosseum_stage_bg")
	if bar == null:
		return 0.0
	var bw := float(bar.texture.get_width())
	var bh := float(bar.texture.get_height())
	var k := vis.x / bw
	bar.scale = Vector2(k, k)
	bar.centered = false
	bar.position = Vector2(0.0, vis.y - bh * k)
	bar.z_index = 15
	add_child(bar)

	var org := Vector2(bw * 0.5 + STAGE_ANCHOR.x, bh - (bh * 0.5 + STAGE_ANCHOR.y))

	var phase := base_steps
	var gen := _gen
	for j in range(window, total + 1):
		var el := String(wheel[posmod(j - phase, wheel.size())])
		var ic := _spr("item_etc", "item_etc_ele_%s" % ELE_FRAME.get(el, "ground"))
		if ic == null:
			continue
		ic.position = org + Vector2(float(j) * step_px, 0.0)
		ic.scale = Vector2.ZERO
		ic.modulate.a = 0.0
		bar.add_child(ic)
		var mv := ic.create_tween()
		mv.tween_interval(lead)
		mv.tween_property(ic, "position:x", org.x + float(j - total) * step_px,
			float(total) * step_sec).set_trans(Tween.TRANS_LINEAR)
		var tin := ic.create_tween()
		tin.tween_interval(lead + float(j - window) * step_sec)
		tin.tween_property(ic, "modulate:a", 1.0, fade)
		tin.parallel().tween_property(ic, "scale", Vector2(icon_s, icon_s), fade)
		if j == total:
			var pop := ic.create_tween()
			pop.tween_interval(lead + float(total) * step_sec)
			pop.tween_property(ic, "scale", Vector2(0.9, 0.9), 0.1)
			pop.tween_property(ic, "scale", Vector2(icon_s, icon_s), 0.05)
		else:
			var out := ic.create_tween()
			out.tween_interval(lead + float(j) * step_sec)
			out.tween_property(ic, "modulate:a", 0.0, fade)
			out.parallel().tween_property(ic, "scale", Vector2.ZERO, fade)
			out.tween_callback(ic.queue_free)

	if _bg != null:
		_bg.texture = _stage_bg_tex(String(wheel[posmod(-phase, wheel.size())]))
		for t in range(1, total + 1):
			var bel := String(wheel[posmod(t - phase, wheel.size())])
			var at := lead + float(t) * step_sec
			get_tree().create_timer(at).timeout.connect(func() -> void:
				if gen != _gen:
					return
				Bgm.sfx("effect_element_match")
				if is_instance_valid(_bg):
					_bg.texture = _stage_bg_tex(bel))

	var stamp := _spr("item_etc",
		"item_etc_ele_%s" % ELE_FRAME.get(String(_stage.get("element", "")), "ground"))
	if stamp != null:
		var ss := float(A.get("stamp_scale", 2.5))
		stamp.position = org
		stamp.scale = Vector2(ss, ss)
		stamp.modulate.a = 0.0
		bar.add_child(stamp)
		var st := stamp.create_tween()
		st.tween_interval(lead + float(idx) * step_sec + lead)
		st.tween_property(stamp, "modulate:a",
			float(A.get("stamp_alpha", 200)) / 255.0, float(A.get("stamp_sec", 0.25)))
		st.parallel().tween_property(stamp, "scale", Vector2(icon_s, icon_s),
			float(A.get("stamp_sec", 0.25)))
		st.tween_callback(stamp.queue_free)

	var life := bar.create_tween()
	life.tween_interval(lead + float(total) * step_sec + float(A.get("hold_sec", 1.0)))
	life.tween_property(bar, "modulate:a", 0.0, float(A.get("out_sec", 0.5)))
	life.tween_callback(bar.queue_free)

	get_tree().create_timer(lead + float(total) * step_sec).timeout.connect(func() -> void:
		if gen == _gen:
			_stage_buff_fx())

	return lead + float(total) * step_sec + float(A.get("stamp_sec", 0.25))

func _stage_buff_fx() -> void:
	var el := String(_stage.get("element", ""))
	if el == "":
		return
	var path := "res://scenes/buffs/stage_buff_%s.tscn" % el
	if not ResourceLoader.exists(path):
		return
	var bs := float((Colosseum.stage_cfg().get("anim", {}) as Dictionary).get("buff_scale", 1.5))
	for tag in _views:
		var v: Dictionary = _views[tag]
		if not bool(v.get("stage_buff", false)) or bool(v.get("dead", false)):
			continue
		var node = v.get("node")
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		var holder := Node2D.new()
		holder.position = Vector2(0.0, -float(v.get("dragon_h", DRAGON_H)) * 0.5)
		holder.scale = Vector2(bs, bs)
		holder.z_index = 10
		(node as Node2D).add_child(holder)
		var inst = (load(path) as PackedScene).instantiate()
		holder.add_child(inst)
		var ap := _find_anim_player(inst)
		if ap != null:
			var anims := ap.get_animation_list()
			if anims.size() > 0:
				ap.get_animation(anims[0]).loop_mode = Animation.LOOP_NONE
				ap.play(anims[0])
				var t := holder.create_tween()
				t.tween_interval(ap.get_animation(anims[0]).length)
				t.tween_callback(holder.queue_free)

func _slot_pos(mine: bool, slot: int, vis: Vector2) -> Vector2:
	if _mode != "team":
		return Vector2(SOLO_SLOT.x if mine else vis.x - SOLO_SLOT.x,
			vis.y * 0.5 - SOLO_SLOT.y)
	var off: Vector2 = SLOT_OFF[slot % SLOT_OFF.size()]
	return Vector2(off.x if mine else vis.x - off.x, vis.y - off.y)

func _build_team(team: Array, mine: bool, vis: Vector2, recs: Array = []) -> void:
	for i in team.size():
		var p: Dictionary = team[i]
		var tag := ("A%d" if mine else "E%d") % i
		var slot := _slot_pos(mine, i, vis)
		var x := slot.x
		var y := slot.y

		var holder := Node2D.new()
		holder.position = Vector2(x, y)
		add_child(holder)

		var sh := _spr(CM, "common_shadow", Design.ASSET_SCALE)
		if sh != null:
			sh.scale *= (DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO)
			sh.z_index = -1
			holder.add_child(sh)

		var sp := _dragon_spine(int(p.get("art_id", p.get("id", 0))),
			"e" if bool(p.get("awakened", false)) else "adult")
		var ap: AnimationPlayer = null
		if sp != null:
			var ds := DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO
			sp.scale *= ds
			if mine:
				sp.scale = Vector2(-absf(sp.scale.x), sp.scale.y)
			holder.add_child(sp)
			ap = _find_anim_player(sp)

		var dh := DRAGON_H
		var dw := DRAGON_H
		if sp != null:
			var rb := PartySelect._bounds(sp, Transform2D.IDENTITY)
			if rb.size.y > 1.0:
				dh = rb.size.y
				dw = rb.size.x
		var need := 0.0
		if _mode != "team":
			need = HUD_TOP_MIN + ICON_ROW_UP + HUD_LIFT + dh
		var hud := _make_hud(p, Vector2(x, y), dh)
		add_child(hud["root"])

		_views[tag] = {
			"node": holder, "bar": hud["fill"], "barh": hud["root"],
			"dname": String(p.get("name", "")), "icons": hud["icons"],
			"hp_label": hud["hp_label"], "anim": ap, "id": int(p.get("id", 0)),
			"art_id": int(p.get("art_id", p.get("id", 0))),
			"element": String(p.get("element", "")),
			"awakened": bool(p.get("awakened", false)),
			"stage_buff": bool(p.get("stage_buff", false)),
			"hp": int(p.get("hp_max", 1)), "hp_max": maxi(1, int(p.get("hp_max", 1))),
			"dead": false, "pos": Vector2(x, y), "mine": mine, "slot": i,
			"home": Vector2(x, y),
			"dragon_h": dh,
			"dragon_w": dw,
			"need": need,
			"rec": (recs[i] as Dictionary) if i < recs.size() else {},
			"spine": sp, "shadow": sh,
		}
	_apply_depth()

func _align_ground() -> void:
	if _mode == "team" or _views.is_empty():
		return
	var ground := 0.0
	for tag: String in _views:
		var v: Dictionary = _views[tag]
		ground = maxf(ground, maxf(float((v["pos"] as Vector2).y), float(v.get("need", 0.0))))
	for tag: String in _views:
		var v: Dictionary = _views[tag]
		var pos: Vector2 = v["pos"]
		if is_equal_approx(pos.y, ground):
			continue
		var moved := Vector2(pos.x, ground)
		v["pos"] = moved
		v["home"] = moved
		var n = v.get("node")
		if n is Node2D and is_instance_valid(n):
			(n as Node2D).position = moved
		var barh = v.get("barh")
		if barh is Node2D and is_instance_valid(barh):
			(barh as Node2D).position = Vector2(moved.x,
				ground - (float(v.get("dragon_h", DRAGON_H)) + HUD_LIFT))
	_apply_depth()

const DEPTH_STRIDE := 256
const DEPTH_BASE := -1600
const STAND_Z := -1800
const BG_Z := -2000

func _apply_depth() -> void:
	var tags: Array = []
	for tag: String in _views:
		var v: Dictionary = _views[tag]
		var n = v.get("node")
		if n is Node2D and is_instance_valid(n):
			tags.append(tag)
	tags.sort_custom(func(a: String, b: String) -> bool:
		var ya := _depth_y(_views[a])
		var yb := _depth_y(_views[b])
		return (a < b) if is_equal_approx(ya, yb) else (ya < yb))
	for i in tags.size():
		var v: Dictionary = _views[tags[i]]
		var z := DEPTH_BASE + i * DEPTH_STRIDE
		(v["node"] as Node2D).z_index = z
		var barh = v.get("barh")
		if barh is CanvasItem and is_instance_valid(barh):
			(barh as CanvasItem).z_index = z + DEPTH_STRIDE - 1

const DEPTH_LUNGE_BIAS := 1.0

func _depth_y(v: Dictionary) -> float:
	if v.has("depth_y"):
		return float(v["depth_y"])
	var h = v.get("home", v.get("pos", Vector2.ZERO))
	return (h as Vector2).y if h is Vector2 else 0.0

func _process(_dt: float) -> void:
	_apply_depth()

const APPEAR_LEAD := 1.5
const APPEAR_STAGGER := 0.05
const APPEAR_SLIDE := 0.1
const APPEAR_BOUNCE := 0.05
const APPEAR_BOUNCE_PX := 10.0
const STAND_HOLD := 2.6
const STAND_FADE := 0.25
const DROP_HOLD := 2.85
const DROP_SEC := 0.1
const LAND_AT := 4.65
const SQUASH := [Vector2(1.1, 0.9), Vector2(0.9, 1.1), Vector2(1.0, 1.0)]
const SQUASH_SEC := [0.1, 0.05, 0.05]
const SHADOW_DROP := 35.0
const STAND_FEET := 27.5

const STAND_GUARD := {"nuri": 5, "raon": 4, "sundaegun": 4}
const STAND_GRADE := {"novice": 1, "ranker": 15}

func _stand_key(mine: bool) -> String:
	var sman := AtlasUI.manifest(ST)
	var n := maxi(1, sman.size())
	var idx := 1
	if mine:
		idx = posmod(int(UserDB.get_skin("stand_skin")), n) + 1
	else:
		var gk := String(_foe.get("guard_key", ""))
		if STAND_GUARD.has(gk):
			idx = int(STAND_GUARD[gk])
		else:
			var grade := String(_foe.get("grade", "novice"))
			if bool(_foe.get("ranker", false)):
				grade = "ranker"
			if STAND_GRADE.has(grade):
				idx = int(STAND_GRADE[grade])
			else:
				idx = _rng.randi_range(1, n)
	var key := "stand_stand%d" % idx
	return key if sman.has(key) else "stand_stand1"

func _appear_intro(vis: Vector2) -> float:
	if _views.is_empty():
		return 0.0
	var ds := DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO
	var slide := vis.x * 0.5
	var keys: Array = _views.keys()
	keys.sort()
	var i := -1
	for k in keys:
		i += 1
		var v: Dictionary = _views[k]
		var holder = v.get("node")
		if not (holder is Node2D) or not is_instance_valid(holder):
			continue
		var slot: Vector2 = v.get("pos", (holder as Node2D).position)
		var dir := 1.0 if bool(v.get("mine", false)) else -1.0
		var enter := APPEAR_LEAD + float(i) * APPEAR_STAGGER

		var skey := _stand_key(bool(v.get("mine", false)))
		var stand := AtlasUI.spr_cocos(ST, skey, ds, Vector2(0.5, 0.0))
		var lift := 0.0
		if stand != null:
			var sh_h := AtlasUI.src_pt(ST, skey).y * ds
			lift = maxf(0.0, sh_h * 0.5 - STAND_FEET * ds)
			stand.position = Vector2(slot.x - dir * slide, slot.y)
			stand.z_index = STAND_Z
			add_child(stand)
			var stw := stand.create_tween()
			stw.tween_interval(enter)
			stw.tween_property(stand, "position:x", slot.x, APPEAR_SLIDE)
			stw.tween_property(stand, "position:x", slot.x - dir * APPEAR_BOUNCE_PX, APPEAR_BOUNCE)
			stw.tween_property(stand, "position:x", slot.x, APPEAR_BOUNCE)
			stw.tween_interval(STAND_HOLD - float(i) * APPEAR_STAGGER)
			stw.tween_property(stand, "modulate:a", 0.0, STAND_FADE)
			stw.tween_callback(stand.queue_free)

		var air := Vector2(slot.x - dir * slide, slot.y - lift)
		(holder as Node2D).position = air
		var tw := (holder as Node2D).create_tween()
		tw.tween_interval(enter)
		tw.tween_property(holder, "position:x", slot.x, APPEAR_SLIDE)
		tw.tween_property(holder, "position:x", slot.x - dir * APPEAR_BOUNCE_PX, APPEAR_BOUNCE)
		tw.tween_property(holder, "position:x", slot.x, APPEAR_BOUNCE)
		tw.tween_interval(DROP_HOLD - float(i) * APPEAR_STAGGER)
		tw.tween_property(holder, "position:y", slot.y, DROP_SEC)

		var shadow = v.get("shadow")
		if shadow is Node2D and is_instance_valid(shadow):
			var base_s: Vector2 = (shadow as Node2D).scale
			(shadow as Node2D).modulate.a = 0.0
			var sw := (shadow as Node2D).create_tween()
			sw.tween_interval(LAND_AT)
			sw.tween_callback(func() -> void:
				if is_instance_valid(shadow):
					(shadow as Node2D).scale = Vector2.ZERO)
			sw.tween_property(shadow, "modulate:a", 1.0, STAND_FADE)
			sw.parallel().tween_property(shadow, "scale", base_s, STAND_FADE)

		var barh = v.get("barh")
		if barh is CanvasItem and is_instance_valid(barh):
			(barh as CanvasItem).modulate.a = 0.0
			var hw := (barh as CanvasItem).create_tween()
			hw.tween_interval(LAND_AT)
			hw.tween_property(barh, "modulate:a", 1.0, STAND_FADE)

		var sp = v.get("spine")
		if sp is Node2D and is_instance_valid(sp):
			var bs: Vector2 = (sp as Node2D).scale
			var qw := (sp as Node2D).create_tween()
			qw.tween_interval(LAND_AT)
			for q in SQUASH.size():
				var f: Vector2 = SQUASH[q]
				qw.tween_property(sp, "scale",
					Vector2(bs.x * f.x, bs.y * f.y), float(SQUASH_SEC[q]))
	return LAND_AT + SQUASH_SEC[0] + SQUASH_SEC[1] + SQUASH_SEC[2]

const DRAGON_H := 170.0
const HUD_LIFT := 18.0
const HUD_TOP_MIN := 155.0
const ICON_ROW_UP := 48.0
const HUD_ELEM_POS := Vector2(17.5 + 25.0, 19.75)
const HUD_ELEM_W := 28.5

func _make_hud(p: Dictionary, at: Vector2, dragon_h := DRAGON_H) -> Dictionary:
	var S := Design.ASSET_SCALE
	var root := Node2D.new()
	root.position = at + Vector2(0.0, -(dragon_h + HUD_LIFT))
	root.position.y = maxf(root.position.y, HUD_TOP_MIN + ICON_ROW_UP)

	var cover_bg := _spr(CO, "scene_colosseum_bar_cover_bg", S)
	if cover_bg != null:
		root.add_child(cover_bg)
	var cover := _spr(CO, "scene_colosseum_bar_cover", S)
	if cover != null:
		root.add_child(cover)
	var cover_w := 156.0 * S
	var cover_h := 29.0 * S

	var es := _element_sprite(String(p.get("element", "")))
	if es != null and cover != null:
		es.position = Vector2(HUD_ELEM_POS.x - cover_w * 0.5,
			cover_h * 0.5 - HUD_ELEM_POS.y)
		var iw := float(es.texture.get_width())
		if iw > 0.0:
			es.scale = Vector2.ONE * (HUD_ELEM_W / iw)
		cover.add_child(es)

	var bar_w := 119.0 * S
	var bar_h := 17.0 * S
	var bar_left := Vector2(15.0 - bar_w * 0.5, -1.0 - bar_h * 0.5)
	var bg := _spr(CO, "scene_colosseum_bar_bg", S)
	if bg != null:
		bg.centered = false
		bg.position = bar_left
		root.add_child(bg)
	var fill := _spr(CO, "scene_colosseum_bar", S)
	if fill != null:
		fill.centered = false
		fill.position = bar_left
		fill.region_enabled = true
		fill.region_rect = Rect2(0, 0, 119, 17)
		root.add_child(fill)

	var nm := Label.new()
	nm.text = String(Data.colosseum.get("log", {}).get("level", "레벨"))
	nm.position = Vector2(-cover_w * 0.5, -cover_h * 0.5 - 21.0)
	_bm_style(nm, 16, Color.WHITE)
	root.add_child(nm)

	var lv := Label.new()
	lv.text = "%d" % int(p.get("level", 1))
	lv.size = Vector2(cover_w, 22.0)
	lv.position = Vector2(-cover_w * 0.5 + 42.0, -cover_h * 0.5 - 24.0)
	_bm_style(lv, 21, Color.WHITE)
	root.add_child(lv)

	var icons := Node2D.new()
	icons.position = Vector2(-cover_w * 0.5 + 22.0, -cover_h * 0.5 - ICON_ROW_UP)
	root.add_child(icons)

	var hp := Label.new()
	var hpm := maxi(1, int(p.get("hp_max", 1)))
	hp.text = "%d / %d" % [hpm, hpm]
	hp.size = Vector2(bar_w, 18.0)
	hp.position = Vector2(17.5 - bar_w * 0.5, -1.5 - 9.0)
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bm_style(hp, 13, Color.WHITE)
	root.add_child(hp)

	return {"root": root, "fill": fill, "hp_label": hp, "name_label": nm, "icons": icons}

func _element_sprite(element: String) -> Sprite2D:
	if element == "":
		return null
	var key: String = String(ELE_FRAME.get(element, "shadow"))
	return _spr("item_small_ui", "item_item_small_ele_%s" % key, 1.0)

var _bmfonts := {}
func _bmfont(name: String) -> FontFile:
	if _bmfonts.has(name):
		return _bmfonts[name]
	var path := "res://assets/converted/font_ui/%s.fnt" % name
	if not ResourceLoader.exists(path):
		_bmfonts[name] = null
		return null
	var f: FontFile = load(path).duplicate()
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Gulim"])
	f.fallbacks = [fb]
	_bmfonts[name] = f
	return f

func _bm_style(l: Label, size: int, col: Color, font := "font_subtitle") -> void:
	var f := _bmfont(font)
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE

const PLATE_EDGE := 20.0
const PLATE_AVATAR_X := 35.0
const PLATE_AVATAR_DY := 7.5
const PLATE_RANK_GAP := 5.0
const PLATE_RANK_MAX := 60.0
const PLATE_TEXT := Vector2(195.0, 62.0)
const PLATE_TITLE_MAX := 220.0
const PLATE_DROP_DELAY := 3.85

func _build_top(vis: Vector2) -> void:
	_side_plate(true, UserDB.user_nickname(), Colosseum.rating_of(_mode), vis)
	_side_plate(false, String(_foe.get("nick", "")), int(_foe.get("rating", 0)), vis)

	var cx := vis.x * 0.5
	var vb := _spr(CO, "scene_colosseum_vs_bg", Design.ASSET_SCALE)
	if vb != null:
		vb.position = Vector2(cx, 56.0)
		add_child(vb)
	var v := _spr(CO, "scene_colosseum_vs", Design.ASSET_SCALE)
	if v != null:
		v.position = Vector2(cx, 56.0)
		add_child(v)

const FIGHT_SPINE := "res://scenes/fx/colosseum_fight.tscn"
const USE_SPINE := false

func _vs_intro() -> void:
	var vis := _vis()
	if USE_SPINE and ResourceLoader.exists(FIGHT_SPINE):
		var holder := Node2D.new()
		holder.z_index = 100
		holder.position = vis * 0.5
		add_child(holder)
		var inst = (load(FIGHT_SPINE) as PackedScene).instantiate()
		holder.add_child(inst)
		var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		if ap and ap.has_animation("animation"):
			ap.get_animation("animation").loop_mode = Animation.LOOP_NONE
			ap.play("animation")
		var tw := holder.create_tween()
		tw.tween_interval(1.4)
		tw.tween_property(holder, "modulate:a", 0.0, 0.3)
		tw.tween_callback(holder.queue_free)
		return
	var v := _spr(CO, "scene_colosseum_vs", Design.ASSET_SCALE * 1.6)
	if v != null:
		v.z_index = 100
		v.position = vis * 0.5
		add_child(v)
		var tw2 := create_tween()
		tw2.tween_interval(1.2)
		tw2.tween_property(v, "modulate:a", 0.0, 0.3)
		tw2.tween_callback(v.queue_free)

func _side_plate(mine: bool, nick: String, rating: int, vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var pw := 338.0 * S
	var ph := 77.0 * S
	var plate := Node2D.new()
	plate.position = Vector2(-PLATE_EDGE if mine else vis.x + PLATE_EDGE - pw, 0.0)
	add_child(plate)

	var bg := _spr(CO, "scene_colosseum_profilebox", S)
	if bg != null:
		bg.centered = false
		if not mine:
			bg.scale.x = -bg.scale.x
			bg.position.x = pw
		plate.add_child(bg)

	var P := func(x: float, y: float) -> Vector2:
		return Vector2(x if mine else pw - x, ph - y)

	var bw := 50.0 * S
	var av: Vector2 = P.call(bw * 0.5 + PLATE_AVATAR_X, ph - bw * 0.5 - PLATE_AVATAR_DY)
	var box := _spr(CM, "common_box1", S)
	if box != null:
		box.position = av
		plate.add_child(box)
	var por := _plate_portrait(mine)
	if por != null:
		var tw := maxf(1.0, float(por.texture.get_width()))
		var th := maxf(1.0, float(por.texture.get_height()))
		por.scale = Vector2.ONE * minf(bw / tw, bw / th)
		por.position = av
		plate.add_child(por)
	var bf := Colosseum.tier_frame(rating, "dragon")
	if bf != "":
		var bs := _spr(CM, _frame_key(bf), S)
		if bs != null:
			bs.position = av
			plate.add_child(bs)

	var tf := Colosseum.tier_frame(rating, "icon")
	if tf != "":
		var ts := _spr(CM, _frame_key(tf), S)
		if ts != null:
			var iw := float(ts.texture.get_width()) * S
			if iw > PLATE_RANK_MAX:
				ts.scale *= PLATE_RANK_MAX / iw
			ts.position = av + Vector2((bw + PLATE_RANK_GAP + iw * 0.5) * (1.0 if mine else -1.0),
				0.0)
			plate.add_child(ts)

	var anchor: Vector2 = P.call(PLATE_TEXT.x, PLATE_TEXT.y)
	var tno := UserDB.user_title_no() if mine else 0
	var tpath := "res://assets/converted/%s/title_%d_kr.tres" % [
		String(Data.titles.get("atlas_dir", "title_ui")), tno]
	if tno > 0 and ResourceLoader.exists(tpath):
		var tt: Texture2D = load(tpath)
		var tr := Sprite2D.new()
		tr.texture = tt
		tr.centered = false
		tr.material = _pma
		var tws := float(tt.get_width()) * S
		var tsc := S * (PLATE_TITLE_MAX / tws if tws > PLATE_TITLE_MAX else 1.0)
		tr.scale = Vector2(tsc, tsc)
		var thh := float(tt.get_height()) * tsc
		tr.position = Vector2(anchor.x if mine else anchor.x - float(tt.get_width()) * tsc,
			anchor.y - thh)
		plate.add_child(tr)

	var l := Label.new()
	l.text = nick
	l.size = Vector2(pw - PLATE_TEXT.x - 24.0, 28.0)
	l.position = Vector2(anchor.x if mine else anchor.x - l.size.x, anchor.y)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if mine else HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 20)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(l)

	var home := plate.position
	plate.position = home - Vector2(0.0, ph)
	var tw2 := plate.create_tween()
	tw2.tween_interval(PLATE_DROP_DELAY)
	tw2.tween_property(plate, "position", home, 0.1)
	tw2.tween_property(plate, "position", home - Vector2(0.0, 10.0), 0.05)
	tw2.tween_property(plate, "position", home, 0.05)

func _frame_key(path: String) -> String:
	return path.replace("/", "_").replace(".png", "")

func _plate_portrait(mine: bool) -> Sprite2D:
	var did := 0
	if mine:
		var a := UserDB.active_dragon()
		did = Icons.art_id_of(a) if not a.is_empty() else 0
	elif not _fo.is_empty():
		did = Icons.art_id_of(_fo[0] as Dictionary)
	if did <= 0:
		return null
	var dir := "portrait_%d" % did
	var man := _man(dir)
	for stage in ["evolution", "adult"]:
		var k := "dragon_dragon_%d_box_%s" % [did, stage]
		if man.has(k):
			return _spr(dir, k, 1.0)
	return null

const LOG_H := 90.0
const LOG_MARGIN := 20.0
const LOG_BOTTOM := 10.0
const LOG_BTN_LIFT := 30.0
const LOG_FOLD_INSET := 50.0
const LOG_TEXT_PAD := Vector2(25.0, 20.0)
const LOG_TEXT_TRIM := Vector2(125.0, 22.5)
const SPEEDS := [1, 2, 3]
const SPEED_KEY := "pvp_speed"
const LOG_LINES := 2

var _log_host: Control
var _log_box: NinePatchRect
var _log_lines: Array[String] = []
var _speed_label: Label
var _speed := 1
var _folded := true
var _skipped := false

func _build_log(vis: Vector2) -> void:
	var bw := vis.x - LOG_MARGIN
	var host := Control.new()
	host.position = Vector2(LOG_MARGIN * 0.5, vis.y - LOG_BOTTOM - LOG_H)
	host.size = Vector2(bw, LOG_H)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)
	_log_host = host

	_log_box = _nine("9patch_dialogue_box", host.size, Rect2(10, 10, 4, 4))
	if _log_box != null:
		host.add_child(_log_box)

	_log = Label.new()
	_log.position = LOG_TEXT_PAD
	_log.size = host.size - LOG_TEXT_TRIM
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.add_theme_font_size_override("font_size", 19)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(_log)

	var up := _btn(CM, "common_btn_up", host,
		Vector2(bw - LOG_FOLD_INSET, LOG_H * 0.5), _toggle_fold)
	if up != null:
		up.rotation = 0.0

	var sk: Dictionary = _man("adventure_ui").get("scene_adventure_bt_skip_kr", {})
	var skw := float(sk.get("w", 71)) * Design.ASSET_SCALE
	_btn("adventure_ui", "scene_adventure_bt_skip_kr", host,
		Vector2(bw - skw * 0.5, -LOG_BTN_LIFT), _on_skip)

	var fw := float((_man(CO).get("scene_colosseum_btn_forward", {}) as Dictionary).get("w", 81))
	var fwp := fw * Design.ASSET_SCALE
	var fb := _btn(CO, "scene_colosseum_btn_forward", host,
		Vector2(fwp * 0.5, -LOG_BTN_LIFT), _cycle_speed)
	_speed_label = Label.new()
	_speed_label.text = "x%d" % _speed
	_speed_label.size = Vector2(60.0, 24.0)
	_speed_label.position = Vector2(fwp * 0.5 - 15.0 - 30.0, -LOG_BTN_LIFT - 12.5 - 12.0)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bm_style(_speed_label, 17, Color(0.25, 0.2, 0.15))
	_speed_label.scale = Vector2.ONE * 1.25
	if fb != null:
		host.add_child(_speed_label)

func _btn(dir: String, key: String, host: Control, at: Vector2, cb: Callable) -> TextureButton:
	var t := _tex(dir, key)
	if t == null:
		return null
	var b := TextureButton.new()
	b.texture_normal = t
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = Vector2(t.get_width(), t.get_height()) * Design.ASSET_SCALE
	b.position = at - b.size * 0.5
	b.material = _pma
	b.pressed.connect(cb)
	host.add_child(b)
	return b

func _toggle_fold() -> void:
	_folded = not _folded
	var vis := _vis()
	var h := LOG_H if _folded else LOG_H * 2.2
	_log_host.position.y = vis.y - LOG_BOTTOM - h
	_log_host.size.y = h
	if _log_box != null:
		_log_box.size.y = h
	if _log != null:
		_log.size.y = h - LOG_TEXT_TRIM.y
	_render_log()

func _saved_speed() -> int:
	var v := int(UserDB.get_pmeta(SPEED_KEY, 1))
	return v if SPEEDS.has(v) else 1

func _cycle_speed() -> void:
	_speed = SPEEDS[(SPEEDS.find(_speed) + 1) % SPEEDS.size()]
	UserDB.set_pmeta(SPEED_KEY, _speed)
	if _speed_label != null:
		_speed_label.text = "x%d" % _speed

func _on_skip() -> void:
	_skipped = true

func _say(t: String) -> void:
	_log_lines.append(t)
	if _log_lines.size() > 12:
		_log_lines = _log_lines.slice(_log_lines.size() - 12)
	_render_log()

func _render_log() -> void:
	if _log == null:
		return
	var n := LOG_LINES if _folded else 6
	var take: Array = _log_lines.slice(maxi(0, _log_lines.size() - n))
	_log.text = "\n".join(PackedStringArray(take))

func _start(intro_delay := 0.0) -> void:
	var cfg := _json(Data.data_path("combat.json"))
	var skills := _json(Data.data_path("skills.json"))
	var pa := _combatants(_my, "ally")
	var pb := _combatants(_fo, "enemy")
	var res: Dictionary = Battle.simulate(pa, pb, _rng, cfg, skills)
	_events = res.get("events", [])
	_winner = String(res.get("winner", ""))
	if intro_delay > 0.0:
		var gen := _gen
		await get_tree().create_timer(intro_delay).timeout
		if gen != _gen:
			return
	_play()

func _combatants(team: Array, side: String) -> Array:
	var out: Array = []
	for i in team.size():
		var p: Dictionary = team[i]
		var c := Battle.make_combatant(("A%d" if side == "ally" else "E%d") % i,
			side, String(p.get("element", "")), p.get("stats", {}), 0.0,
			p.get("skills", []), p.get("skill_slots", []))
		c["hp_max"] = int(p.get("hp_max", c["hp_max"]))
		c["hp"] = int(p.get("hp", c["hp_max"]))
		c["awaken_no"] = int(p.get("awaken_skill", 0))
		c["grade"] = float(p.get("grade", 0.0))
		c["dragon_id"] = int(p.get("id", 0))
		c["atk_type"] = String(p.get("atk_type", ""))
		c["awaken_gauge"] = float(p.get("awaken_gauge", 0.0))
		for e in (p.get("awaken_effects", []) as Array):
			(c["effects"] as Array).append((e as Dictionary).duplicate())
		out.append(c)
	return out

func _apply_passives() -> void:
	var mine_head: Dictionary = _my[0] if not _my.is_empty() else {}
	var foe_head: Dictionary = _fo[0] if not _fo.is_empty() else {}
	var ctx := {"field_element": String(_stage.get("element", "")), "enemy_boss": false}
	if not _my.is_empty():
		PartyStats.apply_passives(_my, {"element": String(foe_head.get("element", "")),
			"hp": int(foe_head.get("hp_max", 1))}, ctx)
	if not _fo.is_empty():
		PartyStats.apply_passives(_fo, {"element": String(mine_head.get("element", "")),
			"hp": int(mine_head.get("hp_max", 1))}, ctx)

func _guard_talk() -> void:
	var gen := _gen
	var lines: Array = _foe.get("lines", [])
	var firsts: Array = _foe.get("lines_first", [])
	if bool(_foe.get("first_meet", false)) and not firsts.is_empty():
		lines = firsts
	if lines.is_empty():
		return
	var nick := String(_foe.get("nick", ""))
	var fallback_npc := String(_foe.get("guard_key", ""))
	var tl: NpcDialogue = null
	for ln in lines:
		if _skipped or gen != _gen or (tl != null and not is_instance_valid(tl)):
			break
		var d: Dictionary = ln if ln is Dictionary else {"text": String(ln)}
		var npc := String(d.get("npc", fallback_npc))
		if not NpcPortrait.has_art(npc):
			npc = ""
		var who := String(d.get("name", ""))
		if who == "":
			who = nick
		var pos := int(d.get("pos", NpcDialogue.POS_CENTER))
		var emo := int(d.get("emotion", 1))
		var body := int(d.get("body", 1))
		var first_show := bool(d.get("first_show", true))
		var small := bool(d.get("small", false))
		if tl == null:
			tl = NpcDialogue.open(self, npc, who, "", emo, body, pos)
		else:
			tl.set_talker(npc, who, pos, emo, body, first_show, small)
		tl.set_text(String(d.get("text", "")))
		await tl.advanced
		await get_tree().process_frame
	if tl != null and is_instance_valid(tl):
		tl.close()

func _play() -> void:
	var gen := _gen
	await _guard_talk()
	if gen != _gen: return
	_say("%s 와(과)의 대전!" % String(_foe.get("nick", "")))
	_vs_intro()
	await _wait(1.8)
	if gen != _gen: return
	for ev in _events:
		if _skipped:
			_apply_silent(ev)
			continue
		_apply(ev)
		await _wait(_evt_delay(ev))
		if gen != _gen: return
	await _wait(0.5)
	if gen != _gen: return
	_finish()

func _evt_delay(ev: Dictionary) -> float:
	match String(ev.get("type", "")):
		"awaken":
			if not bool(ev.get("volley_last", false)):
				return 0.0
			var av: Dictionary = _views.get(_actor_tag(ev), {})
			var el := String(av.get("element", ""))
			return maxf(float(AwakenSkillFx.DURATION.get(el, 2.0)),
				AwakenSkillFx.ACT_AT + float(_ult_dmg_plan(el)[2]))
		"normal", "double":
			var base := 2.1 if bool(ev.get("crit", false)) else 1.15
			return maxf(base, _motion_dur + MOTION_TAIL)
		"dot", "effect_tick":
			return 0.35
	return 0.7

func _apply(ev: Dictionary) -> void:
	var t := String(ev.get("type", ""))
	var dfn := String(ev.get("defender", ev.get("target", "")))
	if dfn == "" and t in ["confused", "status_skip"]:
		dfn = String(ev.get("actor", ""))
	var dmg := int(ev.get("damage", 0))
	_motion_dur = 0.0
	if dfn == "" or not _views.has(dfn):
		return
	var v: Dictionary = _views[dfn]

	if t == "effect_tick":
		_tick_icon(v, int(ev.get("source", 0)), int(ev.get("turns", 0)))
		return
	if bool(ev.get("cleanse", false)):
		_clear_debuff_icons(v)

	_motion(ev, t, _actor_tag(ev), dfn)
	if bool(ev.get("miss", false)):
		_log_line(ev, t, dfn, 0, 0)
		return
	if t == "awaken":
		var atk_v: Dictionary = _views.get(_actor_tag(ev), {})
		if bool(ev.get("volley_lead", false)):
			var LU: Dictionary = Data.colosseum.get("log", {})
			if not LU.is_empty():
				_say(String(LU.get("ultimate", "")) % _who(_actor_tag(ev)))
		_ultimate_damage(ev, t, dfn, v, String(atk_v.get("element", "")))
		return
	_apply_hit(ev, t, dfn, v)

static func _ult_dmg_plan(element: String) -> Array:
	match element:
		"aqua":
			var a: Array = []
			for i in 10:
				a.append(4.6 + float(i) * 0.1)
			return [a, -1.0, 7.3]
		"chaos":
			return [[], 0.0, 7.45]
		"dark":
			var step := [0.0, 0.2, 0.2, 0.2, 0.15, 0.1, 0.1, 0.1, 0.1, 0.1,
				0.1, 0.1, 0.1, 0.1, 0.1]
			var a: Array = []
			var t := 4.75
			for s: float in step:
				t += s
				a.append(t)
			return [a, 1.0 / 30.0, 7.9]
		"earth":
			return [[1.75, 2.25, 2.75, 3.25, 4.15], 1.0 / 10.0, 4.75]
		"shadow":
			return [[2.75, 3.25, 3.75, 4.25, 5.15], 1.0 / 10.0, 5.25]
		"fire":
			var a: Array = []
			for i in 19:
				a.append(float(AwakenSkillFx.FIRE_DELAYS[i]) + 1.5)
			return [a, 1.0 / 20.0, float(AwakenSkillFx.FIRE_DELAYS[19]) + 1.5]
		"holy":
			return [[7.0, 7.25], 1.0 / 3.0, 7.5]
		"light":
			var a: Array = []
			var t := 3.25
			for i in 30:
				t += 0.27 - 0.009 * float(i + 1)
				a.append(t)
			var last: float = a.pop_back()
			a.push_front(2.5)
			return [a, 1.0 / 31.0, last]
		"wind":
			var a: Array = [2.1]
			for i in 44:
				a.append(2.75 + float(i) * 0.1)
			return [a, 1.0 / 46.0, 2.75 + 44.0 * 0.1]
	return [[], 0.0, 8.0]

func _ultimate_damage(ev: Dictionary, t: String, dfn: String, v: Dictionary, element: String) -> void:
	var plan := _ult_dmg_plan(element)
	var chips: Array = plan[0]
	var last := float(plan[2]) / maxf(0.05, float(_speed))
	var hit := int(ev.get("hit", 0))
	var hits := int(ev.get("hits", 1))
	var at := last
	if hit < chips.size() and hit < hits - 1:
		at = float(chips[hit]) / maxf(0.05, float(_speed))
	var dmg_at0 := AwakenSkillFx.ACT_AT / maxf(0.05, float(_speed))
	if hit == 0:
		_ultimate_knockback(v, element)
	var gen := _gen
	var ev2 := ev.duplicate(true)
	get_tree().create_timer(dmg_at0 + at).timeout.connect(func() -> void:
		if is_instance_valid(self) and gen == _gen:
			_apply_hit(ev2, t, dfn, v))

func _ultimate_knockback(v: Dictionary, element := "") -> void:
	var n = v.get("node")
	if not (n is Node2D) or not is_instance_valid(n) or bool(v.get("dead", false)):
		return
	var node := n as Node2D
	var s := DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO
	var home: Vector2 = v.get("home", node.position)
	var vis := _vis()
	var mine := bool(v.get("mine", false))
	var stage := Vector2(ULT_DX if mine else vis.x - ULT_DX, vis.y * 0.5 + ULT_DROP)
	var old = v.get("move_tw")
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	AwakenSkillFx.target_fx({
		"node": node, "anim": v.get("anim"), "shadow": v.get("shadow"),
		"home": home, "stage": stage, "scale": s, "mine": mine,
	}, element)
	var ap = v.get("anim")
	if ap is AnimationPlayer and is_instance_valid(ap) \
			and (ap as AnimationPlayer).has_animation("wait"):
		(ap as AnimationPlayer).get_animation("wait").loop_mode = Animation.LOOP_LINEAR

func _apply_hit(ev: Dictionary, t: String, dfn: String, v: Dictionary) -> void:
	var dmg := int(ev.get("damage", 0))
	if dmg > 0:
		v["hp"] = maxi(0, int(v["hp"]) - dmg)
		_set_bar(v)
		_hit_number(v, str(dmg))
		_total_number(v, dmg, true, bool(ev.get("crit", false)) or t == "awaken")
	_defense_fired(v, ev)

	var heal := int(ev.get("heal", 0))
	if heal > 0:
		v["hp"] = mini(int(v["hp_max"]), int(v["hp"]) + heal)
		_set_bar(v)
		_hit_number(v, "+%d" % heal, true)
	var t_loss := int(ev.get("target_loss", 0))
	if t_loss > 0:
		v["hp"] = maxi(0, int(v["hp"]) - t_loss)
		_set_bar(v)
		_hit_number(v, str(t_loss))
	var s_loss := int(ev.get("self_loss", 0))
	if s_loss > 0:
		var cv: Dictionary = _views.get(_actor_tag(ev), {})
		if not cv.is_empty():
			cv["hp"] = maxi(0, int(cv["hp"]) - s_loss)
			_set_bar(cv)
			_hit_number(cv, str(s_loss))
	if bool(ev.get("dead", false)) and not bool(v["dead"]):
		_dead_fx(v)
		var d0 := _play_anim(v, "damaged")
		var gen0 := _gen
		get_tree().create_timer(maxf(0.15, d0)).timeout.connect(func() -> void:
			if gen0 == _gen:
				_play_anim(v, "down"))
		v["dead"] = true
		for k in ["node", "barh"]:
			var n = v.get(k)
			if n != null and is_instance_valid(n):
				var tw := create_tween()
				tw.tween_interval(1.4)
				tw.tween_property(n, "modulate:a", 0.0, 0.45)
	_log_line(ev, t, dfn, dmg, heal)

func _apply_silent(ev: Dictionary) -> void:
	var dfn := String(ev.get("defender", ev.get("target", "")))
	if dfn == "" or not _views.has(dfn):
		return
	var v: Dictionary = _views[dfn]
	if not bool(ev.get("miss", false)):
		var dmg := int(ev.get("damage", 0))
		if dmg > 0:
			v["hp"] = maxi(0, int(v["hp"]) - dmg)
		var heal := int(ev.get("heal", 0))
		if heal > 0:
			v["hp"] = mini(int(v["hp_max"]), int(v["hp"]) + heal)
		var t_loss := int(ev.get("target_loss", 0))
		if t_loss > 0:
			v["hp"] = maxi(0, int(v["hp"]) - t_loss)
		var s_loss := int(ev.get("self_loss", 0))
		if s_loss > 0:
			var cv: Dictionary = _views.get(_actor_tag(ev), {})
			if not cv.is_empty():
				cv["hp"] = maxi(0, int(cv["hp"]) - s_loss)
				_set_bar(cv)
		_set_bar(v)
	if bool(ev.get("dead", false)) and not bool(v["dead"]):
		v["dead"] = true
		for k in ["node", "barh"]:
			var n = v.get(k)
			if n != null and is_instance_valid(n):
				(n as CanvasItem).modulate.a = 0.0

func _log_line(ev: Dictionary, t: String, dfn: String, dmg: int, heal: int) -> void:
	var L: Dictionary = Data.colosseum.get("log", {})
	if L.is_empty():
		return
	var an := _who(_actor_tag(ev))
	var dn := _who(dfn)
	match t:
		"normal", "double":
			var kind := String(L.get("atk_critical", "")) if bool(ev.get("crit", false)) \
				else String(L.get("atk_double" if t == "double" else "atk_normal", ""))
			if bool(ev.get("miss", false)):
				_say(String(L.get("evade", "")) % [dn, an, kind])
			elif bool(ev.get("block", false)):
				_say(String(L.get("defend", "")) % [dn, an, kind, dmg])
			else:
				_say(String(L.get("attack", "")) % [an, dn, kind, dmg])
		"awaken":
			if dmg > 0:
				_say(String(L.get("ultimate_damage", "")) % [dn, dmg])
		"skill":
			var sn := String(ev.get("skill_name", ""))
			if sn != "":
				_say(String(L.get("skill", "")) % [an, dn, sn])
			if bool(ev.get("immune", false)) and sn != "":
				_say(String(L.get("immune", "")) % [dn, sn])
			var t_loss := int(ev.get("target_loss", 0))
			if t_loss > 0 and sn != "":
				_say(String(L.get("attack", "")) % [an, dn, sn, t_loss])
			var s_loss := int(ev.get("self_loss", 0))
			if s_loss > 0 and an != "":
				_say(String(L.get("confuse", "")) % [an, s_loss])
		"dot":
			_say(String(L.get("poison", "")) % [dn, dmg])
	if heal > 0:
		_say(String(L.get("recover", "")) % [dn, heal])
	if bool(ev.get("dead", false)):
		_say(String(L.get("stun", "")) % dn)

const SHIELD_SKILL := 11
const SHIELD_SPINE := "res://scenes/worldmap_fx/skill_adbloking_spine.tscn"

func _defense_fired(v: Dictionary, ev: Dictionary) -> void:
	var nm := String(ev.get("def_skill", ""))
	if nm == "":
		return
	var L: Dictionary = Data.colosseum.get("log", {})
	_say(String(L.get("buff", "%s / %s")) % [String(v.get("dname", "")), nm])
	if int(ev.get("def_skill_id", 0)) != SHIELD_SKILL:
		return
	if not ResourceLoader.exists(SHIELD_SPINE):
		return
	var holder := Node2D.new()
	holder.z_index = 60
	holder.position = _body_pos(v)
	add_child(holder)
	var inst = (load(SHIELD_SPINE) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap := _find_anim_player(inst)
	if ap != null and ap.get_animation_list().size() > 0:
		var a0 := ap.get_animation_list()[0]
		ap.get_animation(a0).loop_mode = Animation.LOOP_NONE
		ap.play(a0)
	var tw := holder.create_tween()
	tw.tween_interval(0.7)
	tw.tween_callback(holder.queue_free)

func _actor_tag(ev: Dictionary) -> String:
	for k in ["attacker", "caster", "actor"]:
		var s := String(ev.get(k, ""))
		if s != "" and _views.has(s):
			return s
	return ""

func _who(tag: String) -> String:
	if tag == "" or not _views.has(tag):
		return ""
	return String((_views[tag] as Dictionary).get("dname", tag))

func _set_bar(v: Dictionary) -> void:
	var r := clampf(float(v["hp"]) / float(v["hp_max"]), 0.0, 1.0)
	var b = v.get("bar")
	if b is Sprite2D and is_instance_valid(b):
		var s := b as Sprite2D
		var t := s.texture
		if t != null:
			s.region_rect = Rect2(0, 0, float(t.get_width()) * r, t.get_height())
	var hl = v.get("hp_label")
	if hl is Label and is_instance_valid(hl):
		(hl as Label).text = "%d / %d" % [maxi(0, int(v["hp"])), int(v["hp_max"])]

const ATK_ANIM_SPEED := 1.125
const CRIT_ANIM_SPEED := ATK_ANIM_SPEED
const ATK_FPS := 30.0
const ATK_PULSE_SEC := 0.05
const ATK_PULSE := [Vector2(1.25, 1.05), Vector2(0.90, 0.95), Vector2(1.00, 1.00)]
const ATK_TAIL := 0.1
const ATK_LEAD := 0.05
const MOVE_SEC := 0.18

const ANIM_IDLE := "wait"

static func _dragon_spine(id: int, stage := "adult") -> Node2D:
	var path := Icons.spine_scene(id, stage)
	if path == "":
		path = Icons.spine_scene(id, "adult")
	if path == "":
		return null
	var holder := Node2D.new()
	var inst = (load(path) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap := _find_anim_player(inst)
	if ap != null and ap.has_animation(ANIM_IDLE):
		ap.get_animation(ANIM_IDLE).loop_mode = Animation.LOOP_LINEAR
		ap.play(ANIM_IDLE)
	var r := PartySelect._bounds(inst, Transform2D.IDENTITY)
	if r.size.y > 1.0:
		inst.position -= Vector2(0.0, r.position.y + r.size.y)
	return holder

func _has_anim(v: Dictionary, name: String) -> bool:
	var ap = v.get("anim")
	return ap is AnimationPlayer and is_instance_valid(ap) \
		and (ap as AnimationPlayer).has_animation(name)

static func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null

func _play_anim(v: Dictionary, name: String) -> float:
	var ap = v.get("anim")
	if not (ap is AnimationPlayer) or not is_instance_valid(ap):
		return 0.0
	var p := ap as AnimationPlayer
	if not p.has_animation(name):
		return 0.0
	var a := p.get_animation(name)
	a.loop_mode = Animation.LOOP_NONE
	var speed := ATK_ANIM_SPEED if name == "attack" else 1.0
	if name == "critical":
		speed = CRIT_ANIM_SPEED
	var play := speed * _spd()
	p.play(name, -1.0, play)
	_note_motion(a.length / speed)
	var dur := a.length / play
	var gen := _gen
	get_tree().create_timer(maxf(0.1, dur - ATK_TAIL)).timeout.connect(func() -> void:
		if gen != _gen or not is_instance_valid(p) or bool(v.get("dead", false)):
			return
		if p.has_animation(ANIM_IDLE):
			p.get_animation(ANIM_IDLE).loop_mode = Animation.LOOP_LINEAR
			p.play(ANIM_IDLE))
	return dur

const HIT_BLINK_ALPHA := 0.35
const HIT_BLINK_BACK := 0.1
const HIT_SFX_VOL_BASE := 0.25
const HIT_SFX_VOL_STEP := 0.05
const HIT_SFX_VOL_N := 6

func _hit_sfx() -> void:
	Bgm.sfx("effect_dragon_damaged_%d" % (1 + (_rng.randi() & 1)),
		HIT_SFX_VOL_BASE + float(_rng.randi() % HIT_SFX_VOL_N) * HIT_SFX_VOL_STEP)

func _damaged_color(v: Dictionary) -> void:
	var n = v.get("node")
	if not (n is Node2D) or not is_instance_valid(n):
		return
	var node := n as Node2D
	var hold := 0.3
	var ap = v.get("anim")
	if ap is AnimationPlayer and is_instance_valid(ap) and (ap as AnimationPlayer).has_animation("damaged"):
		hold = (ap as AnimationPlayer).get_animation("damaged").length
	var tw := node.create_tween()
	tw.tween_property(node, "modulate:a", HIT_BLINK_ALPHA, 0.0)
	tw.tween_interval(maxf(0.05, hold - HIT_BLINK_BACK))
	tw.tween_property(node, "modulate:a", 1.0, HIT_BLINK_BACK)

const HIT_SHAKE := [20.0, -35.0, 25.0, -10.0]
const HIT_SHAKE_SEC := 0.05

func _shake_horizontal(v: Dictionary, dir: float) -> void:
	var n = v.get("node")
	if not (n is Node2D) or not is_instance_valid(n):
		return
	var node := n as Node2D
	var base := node.position
	var tw := node.create_tween()
	for d: float in HIT_SHAKE:
		tw.tween_property(node, "position:x",
			node.position.x + d * dir, HIT_SHAKE_SEC).as_relative()
	tw.tween_property(node, "position", base, 0.0)

func _attack_pulse(v: Dictionary, target: Dictionary, anim_dur: float,
		snap_back := false) -> void:
	var n = v.get("node")
	if not (n is Node2D) or not is_instance_valid(n):
		return
	var node := n as Node2D
	var base := _base_scale(v)
	var hit := clampf(anim_dur * 0.5, 0.05, 1.2)

	var tw := create_tween()
	tw.tween_interval(hit)
	for f: Vector2 in ATK_PULSE:
		tw.tween_property(node, "scale",
			Vector2(base.x * f.x, absf(base.y) * f.y), ATK_PULSE_SEC)
	tw.tween_property(node, "scale", base, 0.0)

	_attack_jump(v, target, hit, anim_dur, snap_back)

const ATK_JUMP1_DX := 175.0
const ATK_JUMP1_H := 100.0
const ATK_JUMP2_DX := 100.0
const ATK_JUMP2_H := 50.0
const ATK_JUMP1_EASE := 0.5
const ATK_JUMP2_EASE := 0.125
const ATK_JUMP_GAP := 0.1

const CONTACT_OVERLAP := 0.8

func _attack_jump(v: Dictionary, target: Dictionary, hit: float, anim_dur: float,
		snap_back := false) -> void:
	if target.is_empty() or _mode == "":
		return
	var n = v.get("node")
	if not (n is Node2D) or not is_instance_valid(n):
		return
	var node := n as Node2D
	var home: Vector2 = v.get("home", node.position)
	var tp: Vector2 = target.get("home", target.get("pos", home))
	var dir := signf(tp.x - home.x)
	if is_zero_approx(dir):
		return
	var s := DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO
	var reach := (float(v.get("dragon_w", DRAGON_H)) + float(target.get("dragon_w", DRAGON_H))) \
		* 0.5 * CONTACT_OVERLAP
	var p2 := Vector2(tp.x - dir * reach, tp.y)
	if (p2.x - home.x) * dir < ATK_JUMP2_DX * s:
		p2.x = home.x + dir * ATK_JUMP2_DX * s
	var p1 := p2 + Vector2(dir * (ATK_JUMP1_DX - ATK_JUMP2_DX) * s, 0.0)
	var gen := _gen
	var old = v.get("move_tw")
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	v["depth_y"] = p2.y + DEPTH_LUNGE_BIAS
	var tail := 0.0 if snap_back else maxf(0.0, anim_dur - hit) + ATK_JUMP_GAP
	var t := create_tween()
	v["move_tw"] = t
	_tween_jump(t, node, home, p1, ATK_JUMP1_H * s, hit, ATK_JUMP1_EASE)
	t.tween_interval(ATK_JUMP_GAP)
	_tween_jump(t, node, p1, p2, ATK_JUMP2_H * s, hit, ATK_JUMP2_EASE)
	if tail > 0.0:
		t.tween_interval(tail)
	t.tween_property(node, "position", home, MOVE_SEC)
	t.tween_callback(func() -> void:
		v.erase("depth_y")
		if gen == _gen and is_instance_valid(node):
			node.position = v.get("home", home))
	_note_motion((hit * 2.0 + ATK_JUMP_GAP + tail + MOVE_SEC) * _spd())

func _tween_jump(t: Tween, node: Node2D, from: Vector2, to: Vector2,
		height: float, sec: float, ease_rate: float) -> void:
	var dur := maxf(0.05, sec)
	var inv := 1.0 / maxf(0.001, ease_rate)
	t.tween_method(func(x: float) -> void:
		if not is_instance_valid(node):
			return
		var e: float = pow(clampf(x, 0.0, 1.0), inv)
		var pos: Vector2 = from.lerp(to, e)
		pos.y -= height * 4.0 * e * (1.0 - e)
		node.position = pos,
		0.0, 1.0, dur)

func _base_scale(v: Dictionary) -> Vector2:
	if not v.has("base_scale"):
		var n = v.get("node")
		v["base_scale"] = (n as Node2D).scale if n is Node2D else Vector2.ONE
	return v["base_scale"]

const AC_HIT := 0
const AC_CONFUSE := 1
const AC_DOUBLE := 2
const AC_EVADE := 3
const AC_CUTIN := 4
const AC_CRIT_FX := 41
const AC_CRIT_ANIM := 43
const AC_SWAP := 42
const AC_STUN := -15
const AC_POISON := -32
const AC_BIGHIT := -54

func _action_code(ev: Dictionary, t: String) -> int:
	if bool(ev.get("miss", false)):
		return AC_EVADE
	match t:
		"confused":
			return AC_CONFUSE
		"double":
			return AC_DOUBLE
		"status_skip":
			return AC_STUN
		"dot":
			return AC_POISON
		"skill":
			return int(ev.get("skill_id", 0))
		"awaken":
			return AC_CUTIN
	if bool(ev.get("crit", false)):
		return AC_CRIT_FX
	return AC_HIT

func _body_pos(v: Dictionary) -> Vector2:
	if v.is_empty():
		return _vis() * 0.5
	var p: Vector2 = v.get("pos", _vis() * 0.5)
	return p - Vector2(0.0, float(v.get("dragon_h", DRAGON_H)) * 0.5)

var _motion_dur := 0.0
const MOTION_TAIL := 0.2

func _note_motion(sec_at_x1: float) -> void:
	_motion_dur = maxf(_motion_dur, sec_at_x1)

func _motion(ev: Dictionary, t: String, atk_tag: String, dfn_tag: String) -> void:
	var atk: Dictionary = _views.get(atk_tag, {})
	var dfn: Dictionary = _views.get(dfn_tag, {})
	var code := _action_code(ev, t)
	_motion_dur = 0.0

	if t == "awaken" and not bool(ev.get("volley_lead", false)):
		return

	if code == AC_STUN:
		var st: Dictionary = _views.get(String(ev.get("actor", "")), {})
		if not st.is_empty():
			_shake_horizontal(st, 1.0 if bool(st.get("mine", false)) else -1.0)
			_status_icon(st, int(ev.get("source", 0)), false, int(ev.get("turns", 0)))
		return

	if code == AC_CONFUSE:
		var me: Dictionary = _views.get(String(ev.get("actor", "")), {})
		if not me.is_empty():
			_swap_position(me, 0.8)
			var d0 := _play_anim(me, "attack")
			_attack_pulse(me, me, d0)
			_damaged_color(me)
			_shake_horizontal(me, 1.0 if bool(me.get("mine", false)) else -1.0)
		return

	if not atk.is_empty() and not bool(atk.get("dead", false)):
		var anim := "attack"
		if t == "awaken" and _has_anim(atk, "ultimate1"):
			anim = "ultimate1"
		elif code == AC_CRIT_FX and _has_anim(atk, "critical"):
			anim = "critical"
		var dur := _play_anim(atk, anim)
		if t != "awaken":
			_attack_pulse(atk, dfn, dur, code == AC_CRIT_FX)
		if code == AC_DOUBLE:
			var gen2 := _gen
			get_tree().create_timer(maxf(0.1, dur * 0.5)).timeout.connect(func() -> void:
				if gen2 == _gen and not bool(atk.get("dead", false)):
					_attack_pulse(atk, dfn, dur * 0.6))

	if code == AC_EVADE:
		if not dfn.is_empty():
			_evade_back(dfn)
			_evade_effect(dfn)
		return

	if not dfn.is_empty() and not bool(dfn.get("dead", false)) \
			and int(ev.get("damage", 0)) > 0:
		_damaged_color(dfn)
		_hit_sfx()
		_damaged_particle(dfn)
		if code == AC_POISON or code == AC_CRIT_FX:
			_shake_horizontal(dfn, 1.0 if bool(dfn.get("mine", false)) else -1.0)
		if code == AC_BIGHIT:
			_shake_screen(0.4, 1.0)

	var buff := String(ev.get("buff", ""))
	var debuff := String(ev.get("debuff", ""))
	if buff != "" and not atk.is_empty():
		_status_icon(atk, int(ev.get("skill_id", 0)), true, int(ev.get("turns", 0)))
	if debuff != "" and not dfn.is_empty():
		_status_icon(dfn, int(ev.get("skill_id", 0)), false, int(ev.get("turns", 0)),
			int(ev.get("stacks", 0)))

	var at: Vector2 = _body_pos(dfn)
	match t:
		"skill":
			_skill_banner(String(ev.get("skill_name", "")), int(ev.get("skill_id", 0)))
			_skill_sfx(int(ev.get("skill_id", 0)))
			_skill_spine(int(ev.get("skill_id", 0)), at)
			_skill_particle(int(ev.get("skill_id", 0)), at)
		"awaken":
			_cutin(atk)
			_crit_voice(atk)
			_awaken_fx(atk, at)
		_:
			if atk.is_empty():
				pass
			elif code == AC_CRIT_FX:
				_critical_effect(atk, dfn)
				_cutin(atk)
				_crit_voice(atk)
				_dragon_fx_seq(int(atk.get("art_id", atk.get("id", 0))), "col_action2", at)
			else:
				_dragon_fx_seq(int(atk.get("art_id", atk.get("id", 0))), "col_action1", at)

const SWAP_STEP := 210.0
const SWAP_SEC := 0.05
const SWAP_TAIL := 0.15

func _swap_position(actor: Dictionary, hold: float) -> void:
	if _mode != "team" or actor.is_empty():
		return
	if int(actor.get("slot", 0)) == 0:
		return
	var mine := bool(actor.get("mine", false))
	var front: Dictionary = _views.get(("A0" if mine else "E0"), {})
	if front.is_empty() or bool(front.get("dead", false)):
		return
	var sign := -1.0 if mine else 1.0
	var fhome: Vector2 = front.get("pos", Vector2.ZERO)
	var ahome: Vector2 = actor.get("pos", Vector2.ZERO)
	var aside := Vector2(fhome.x + sign * SWAP_STEP, fhome.y)

	for k in ["node", "barh"]:
		var fn = front.get(k)
		if fn is Node2D and is_instance_valid(fn):
			var d: Vector2 = (fn as Node2D).position - fhome
			var t1 := (fn as Node2D).create_tween()
			t1.tween_property(fn, "position", aside + d, SWAP_SEC)
			t1.tween_interval(hold + 0.1)
			t1.tween_property(fn, "position", fhome + d, SWAP_SEC)
	for k2 in ["node", "barh"]:
		var an = actor.get(k2)
		if an is Node2D and is_instance_valid(an):
			var d2: Vector2 = (an as Node2D).position - ahome
			var t2 := (an as Node2D).create_tween()
			t2.tween_interval(SWAP_SEC)
			t2.tween_property(an, "position", fhome + d2, SWAP_SEC)
			t2.tween_interval(hold)
			t2.tween_property(an, "position", ahome + d2, SWAP_SEC)
	front["home"] = aside
	actor["home"] = fhome
	var gen := _gen
	get_tree().create_timer(SWAP_SEC * 2.0 + hold + 0.1).timeout.connect(func() -> void:
		if gen != _gen:
			return
		front["home"] = front.get("pos", fhome)
		actor["home"] = actor.get("pos", ahome))

const EVADE_LIFT := 75.0
const EVADE_POP := 2.0

const EVADE_BACK_PX := 45.0
const EVADE_BACK_SEC := 0.08
const EVADE_HOLD := 0.12

func _evade_back(v: Dictionary) -> void:
	var n = v.get("node")
	if not (n is Node2D) or not is_instance_valid(n):
		return
	var node := n as Node2D
	var home: Vector2 = v.get("home", node.position)
	var back := -1.0 if bool(v.get("mine", false)) else 1.0
	var old = v.get("move_tw")
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var t := node.create_tween()
	v["move_tw"] = t
	t.tween_property(node, "position",
		home + Vector2(back * EVADE_BACK_PX, 0.0), EVADE_BACK_SEC)
	t.tween_interval(EVADE_HOLD)
	t.tween_property(node, "position", home, EVADE_BACK_SEC)

func _evade_effect(dfn: Dictionary) -> void:
	Bgm.sfx("effect_evade")
	var at: Vector2 = dfn.get("pos", _vis() * 0.5)
	var s := _spr("battle_ui", "battle_miss_kr", Design.ASSET_SCALE)
	if s == null:
		return
	s.position = at - Vector2(0.0, TOTAL_LIFT * 0.5)
	s.z_index = 100
	s.scale *= EVADE_POP
	add_child(s)
	var base := Design.ASSET_SCALE
	var tw := s.create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(s, "scale", Vector2(base, base), 0.25)
	tw.tween_interval(0.25)
	tw.tween_property(s, "position", s.position - Vector2(0.0, EVADE_LIFT), 0.5)
	tw.parallel().tween_property(s, "modulate:a", 0.0, 0.5)
	tw.tween_callback(s.queue_free)

const ICON_BASE := 0.375
const ICON_PULSE := 0.1
const ICON_STEP := 40.0
const ICON_MAX := 4

func _status_icon(v: Dictionary, skill_id: int, is_buff: bool, turns: int, stacks := 0) -> void:
	var host = v.get("icons")
	if not (host is Node2D) or not is_instance_valid(host):
		return
	var box := host as Node2D
	var num := stacks if stacks > 0 else turns
	var name_key := "ic%d" % skill_id
	var old := box.get_node_or_null(NodePath(name_key))
	if old != null:
		_icon_pulse(old as Node2D)
		var lb := old.get_node_or_null("t")
		if lb is Label:
			(lb as Label).text = str(maxi(0, num))
		elif num > 0:
			(old as Node2D).add_child(_icon_number_label(num))
		return
	if box.get_child_count() >= ICON_MAX:
		return
	_zzing(v)

	var holder := Node2D.new()
	holder.name = name_key
	holder.position = Vector2(box.get_child_count() * ICON_STEP, 0.0)
	holder.scale = Vector2.ONE * ICON_BASE
	box.add_child(holder)

	var ring := _spr("skill_ui", "skill_buff" if is_buff else "skill_debuff", Design.ASSET_SCALE)
	if ring != null:
		holder.add_child(ring)
	var ic := _spr("skill_ui", "skill_%d" % skill_id, Design.ASSET_SCALE)
	if ic != null:
		holder.add_child(ic)
	if num > 0:
		holder.add_child(_icon_number_label(num))
	holder.set_meta("buff", is_buff)
	_icon_pulse(holder)

func _icon_number_label(num: int) -> Label:
	var l := Label.new()
	l.name = "t"
	l.text = str(num)
	l.size = Vector2(80.0, 40.0)
	l.position = Vector2(-4.0, -66.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bm_style(l, 36, Color.WHITE, "font_normal")
	return l

func _tick_icon(v: Dictionary, skill_id: int, turns: int) -> void:
	var host = v.get("icons")
	if not (host is Node2D) or not is_instance_valid(host) or skill_id <= 0:
		return
	var box := host as Node2D
	var n := box.get_node_or_null(NodePath("ic%d" % skill_id))
	if n == null:
		return
	if turns <= 0:
		box.remove_child(n)
		n.queue_free()
		_relayout_icons(box)
		return
	var lb = n.get_node_or_null("t")
	if lb is Label:
		(lb as Label).text = str(turns)

func _clear_debuff_icons(v: Dictionary) -> void:
	var host = v.get("icons")
	if not (host is Node2D) or not is_instance_valid(host):
		return
	var box := host as Node2D
	for c in box.get_children():
		if not bool((c as Node).get_meta("buff", false)):
			box.remove_child(c)
			c.queue_free()
	_relayout_icons(box)

func _relayout_icons(box: Node2D) -> void:
	var i := 0
	for c in box.get_children():
		if c is Node2D:
			(c as Node2D).position = Vector2(float(i) * ICON_STEP, 0.0)
		i += 1

const ZZING_SCENE := "res://scenes/fx/skill_zzing_spine.tscn"
const ZZING_DELAY := 0.5
const ZZING_HOLD := 1.0

func _zzing(v: Dictionary) -> void:
	if not ResourceLoader.exists(ZZING_SCENE):
		return
	var holder := Node2D.new()
	holder.z_index = 101
	holder.position = _body_pos(v)
	holder.visible = false
	add_child(holder)
	var inst = (load(ZZING_SCENE) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap := _find_anim_player(inst)
	var gen := _gen
	get_tree().create_timer(ZZING_DELAY).timeout.connect(func() -> void:
		if gen != _gen or not is_instance_valid(holder):
			return
		holder.visible = true
		if ap != null and ap.has_animation("animation"):
			ap.get_animation("animation").loop_mode = Animation.LOOP_NONE
			ap.play("animation"))
	var tw := holder.create_tween()
	tw.tween_interval(ZZING_DELAY + ZZING_HOLD)
	tw.tween_callback(holder.queue_free)

func _icon_pulse(n: Node2D) -> void:
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector2(0.5, 0.3), ICON_PULSE)
	tw.tween_property(n, "scale", Vector2(0.3, 0.5), ICON_PULSE)
	tw.tween_property(n, "scale", Vector2.ONE * ICON_BASE, ICON_PULSE)

const BANNER_Y := 150.0
const BANNER_SUB_Y := 200.0
const BANNER_IN := 0.15
const BANNER_HOLD := 1.15
const BANNER_OUT := 0.1

func _skill_banner(sname: String, skill_id: int) -> void:
	if sname == "":
		return
	var vis := _vis()
	var root := Node2D.new()
	root.z_index = 120
	root.modulate.a = 0.0
	add_child(root)

	var bg := _spr(CO, "scene_colosseum_skill_txt_bg", Design.ASSET_SCALE)
	if bg != null:
		bg.position = Vector2(vis.x * 0.5, BANNER_Y)
		root.add_child(bg)

	var nm := Label.new()
	nm.text = sname
	nm.size = Vector2(vis.x, 40.0)
	nm.position = Vector2(0.0, BANNER_Y - 20.0)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bm_style(nm, 30, Color.WHITE)
	root.add_child(nm)

	var short := String((Data.skills.get(str(skill_id), {}) as Dictionary).get("effect_text", ""))
	if short != "":
		var sl := Label.new()
		sl.text = short
		sl.size = Vector2(vis.x, 32.0)
		sl.position = Vector2(0.0, BANNER_SUB_Y - 16.0)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_bm_style(sl, 21, Color.WHITE)
		root.add_child(sl)

	var tw := root.create_tween()
	tw.tween_property(root, "modulate:a", 1.0, BANNER_IN)
	tw.tween_interval(BANNER_HOLD)
	tw.tween_property(root, "modulate:a", 0.0, BANNER_OUT)
	tw.tween_callback(root.queue_free)

const SKILL_SPINE_SEC := 0.7

func _skill_sfx(sid: int) -> void:
	if sid <= 0:
		return
	var own := "effect_skill_%d" % sid
	if ResourceLoader.exists("res://assets/music/%s.mp3" % own):
		Bgm.sfx(own)

const DAMAGED_LIFE := 0.15
const DAMAGED_SPEED := 1000.0
const DAMAGED_SPEED_VAR := 40.0

func _damaged_particle(v: Dictionary) -> void:
	var n = v.get("node")
	if not (n is Node2D) or not is_instance_valid(n):
		return
	var p := CocosParticle.spawn(n as Node2D, "colosseum_damaged",
		Vector2(0.0, -float(v.get("dragon_h", DRAGON_H)) * 0.5), 6, 0.9)
	if p == null:
		return
	p.lifetime = DAMAGED_LIFE
	p.initial_velocity_min = DAMAGED_SPEED - DAMAGED_SPEED_VAR
	p.initial_velocity_max = DAMAGED_SPEED + DAMAGED_SPEED_VAR
	p.scale = Vector2.ONE * (DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO)

const DEAD_SFX_VOL := 0.5

func _dead_fx(v: Dictionary) -> void:
	Bgm.sfx("effect_dead", DEAD_SFX_VOL)
	var n = v.get("node")
	if n is Node2D and is_instance_valid(n):
		CocosParticle.spawn(n as Node2D, "colosseum_dead",
			Vector2(0.0, -float(v.get("dragon_h", DRAGON_H)) * 0.5), 7, 0.9)

func _skill_particle(sid: int, at: Vector2) -> void:
	if sid <= 0:
		return
	for name in ["skill_%d" % sid, "skill_%d_effect" % sid]:
		if CocosParticle.spawn(self, name, at, 101, 0.9) != null:
			return

func _skill_spine(sid: int, at: Vector2) -> bool:
	var path := "res://scenes/fx/skill_%d_spine.tscn" % sid
	if sid <= 0 or not ResourceLoader.exists(path):
		return false
	var holder := Node2D.new()
	holder.z_index = 100
	holder.position = at
	add_child(holder)
	var inst = (load(path) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap := _find_anim_player(inst)
	if ap != null:
		var pick := ""
		for cand in ["animation", "work", "destroy"]:
			if ap.has_animation(cand):
				pick = cand
				break
		if pick == "":
			holder.queue_free()
			return false
		ap.get_animation(pick).loop_mode = Animation.LOOP_NONE
		ap.play(pick)
	var t := holder.create_tween()
	t.tween_interval(SKILL_SPINE_SEC)
	t.tween_callback(holder.queue_free)
	return true

const FX_SEQ_FPS := 24.0

func _dragon_fx_seq(did: int, prefix: String, at: Vector2) -> bool:
	if did <= 0:
		return false
	var dir := "dragon_%d_fx" % did
	var man := _man(dir)
	if man.is_empty():
		return false
	var keys: Array = []
	for k in man:
		if String(k).begins_with("dragon_%d_%s_" % [did, prefix]):
			keys.append(String(k))
	if keys.is_empty():
		return false
	keys.sort()
	var holder := Node2D.new()
	holder.z_index = 100
	holder.position = at
	add_child(holder)
	var shown: Array[Sprite2D] = []
	for k in keys:
		var ent: Dictionary = man.get(k, {})
		var spr := _spr(dir, k, Design.ASSET_SCALE)
		if spr == null:
			continue
		var off: Array = ent.get("off", [0, 0])
		spr.position = Vector2(float(off[0]), -float(off[1])) * Design.ASSET_SCALE
		spr.visible = false
		holder.add_child(spr)
		shown.append(spr)
	if shown.is_empty():
		holder.queue_free()
		return false
	var step := 1.0 / (FX_SEQ_FPS * _spd())
	_note_motion(float(shown.size()) / FX_SEQ_FPS)
	var tw := holder.create_tween()
	for i in shown.size():
		var s: Sprite2D = shown[i]
		var prev: Sprite2D = shown[i - 1] if i > 0 else null
		tw.tween_callback(func() -> void:
			if prev != null and is_instance_valid(prev):
				prev.visible = false
			if is_instance_valid(s):
				s.visible = true)
		tw.tween_interval(step)
	tw.tween_callback(holder.queue_free)
	return true

func _critical_effect(atk: Dictionary, dfn: Dictionary) -> bool:
	var cid := int(atk.get("art_id", atk.get("id", 0)))
	var path := Icons.spine_scene(cid, "critical")
	if bool(atk.get("awakened", false)):
		var ep := Icons.spine_scene(cid, "e_critical")
		if ep != "":
			path = ep
	if path == "":
		return false
	var holder := Node2D.new()
	holder.z_index = 8
	var node = dfn.get("node")
	if node is Node2D and is_instance_valid(node):
		(node as Node2D).add_child(holder)
		holder.position = Vector2(0.0, -float(dfn.get("dragon_h", DRAGON_H)) * 0.5)
	else:
		add_child(holder)
		holder.position = _body_pos(dfn)
	holder.scale = Vector2(-1.0 if bool(atk.get("mine", false)) else 1.0, 1.0)
	var inst = (load(path) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap := _find_anim_player(inst)
	var pick := ""
	if ap != null:
		for cand in ["animation", "critical"]:
			if ap.has_animation(cand):
				pick = cand
				break
	if pick == "":
		holder.queue_free()
		return false
	ap.get_animation(pick).loop_mode = Animation.LOOP_NONE
	var csp := CRIT_ANIM_SPEED * _spd()
	ap.play(pick, -1.0, csp)
	var clen := ap.get_animation(pick).length
	_note_motion(clen / CRIT_ANIM_SPEED)
	var t := holder.create_tween()
	t.tween_interval(clen / csp)
	t.tween_callback(holder.queue_free)
	return true

func _crit_voice(atk: Dictionary) -> void:
	var id := int(atk.get("id", 0))
	var v := int(Icons.voice_row(id).get("critical", 0))
	if v > 0:
		Bgm.sfx("voice%d" % v)

func _shake_screen(sec: float, amp: float) -> void:
	var base := position
	var tw := create_tween()
	var steps := maxi(2, int(sec / 0.05))
	for k in steps:
		var d := amp * 18.0 * (1.0 - float(k) / float(steps))
		tw.tween_property(self, "position",
			base + Vector2(0.0, d if k % 2 == 0 else -d), 0.05)
	tw.tween_property(self, "position", base, 0.05)

const ULT_DX := 225.0
const ULT_DROP := 50.0
const ULT_JUMP_SEC := 0.25
const ULT_JUMP_H := 150.0
const ULT_LAND_LAG := 0.5
const ULT_SQUASH := [Vector2(1.0, 0.95), Vector2(1.0, 1.05), Vector2(1.0, 1.0)]
const ULT_SQUASH_SEC := 0.1
const ULT_TAKEOFF_LAG := 0.2
const ULT_SHADOW_PULSE := [1.75, 2.0]
const ULT_SHADOW_SEC := 0.125
const ULT_HOLD_ORIG := {"aqua": 9.75, "chaos": 9.65, "dark": 9.75, "earth": 7.85,
	"fire": 9.25, "holy": 10.0, "light": 10.25, "shadow": 9.4, "wind": 9.4}

func _ult_stage_y(dragon_h: float) -> float:
	return _vis().y * 0.5 + ULT_DROP + dragon_h * 0.5

func _ultimate_position(atk: Dictionary) -> float:
	var n = atk.get("node")
	if not (n is Node2D) or not is_instance_valid(n):
		return 0.0
	var node := n as Node2D
	var home: Vector2 = atk.get("home", node.position)
	var mine := bool(atk.get("mine", false))
	var s := DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO
	var vis := _vis()
	var stage := Vector2(ULT_DX if mine else vis.x - ULT_DX,
		_ult_stage_y(float(atk.get("dragon_h", DRAGON_H))))
	var el := String(atk.get("element", ""))
	var hold := float(ULT_HOLD_ORIG.get(el, 9.0))

	var old = atk.get("move_tw")
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var t := create_tween()
	atk["move_tw"] = t
	t.tween_interval(AwakenSkillFx.LEAD)
	_tween_jump(t, node, home, stage, ULT_JUMP_H * s, ULT_JUMP_SEC, 1.0)
	var total := AwakenSkillFx.caster_fx({
		"node": node, "anim": atk.get("anim"), "shadow": atk.get("shadow"),
		"home": home, "stage": stage, "scale": s, "host": self,
	}, el)
	atk["home"] = stage
	var gen := _gen
	get_tree().create_timer(total).timeout.connect(func() -> void:
		if gen == _gen:
			atk["home"] = atk.get("pos", home))

	var shadow = atk.get("shadow")
	if shadow is Node2D and is_instance_valid(shadow) and not (el in ["aqua", "wind"]):
		var bs: Vector2 = (shadow as Node2D).scale
		var sw := (shadow as Node2D).create_tween()
		sw.tween_interval(AwakenSkillFx.LEAD)
		for m: float in ULT_SHADOW_PULSE:
			sw.tween_property(shadow, "scale", bs * m, ULT_SHADOW_SEC)
		sw.tween_interval(maxf(0.0, total - AwakenSkillFx.LEAD - ULT_SHADOW_SEC * 2.0))
		sw.tween_property(shadow, "scale", bs, ULT_JUMP_SEC)

	var sp0 = atk.get("spine")
	if sp0 is Node2D and is_instance_valid(sp0):
		var b0: Vector2 = (sp0 as Node2D).scale
		var tk := (sp0 as Node2D).create_tween()
		tk.tween_interval(AwakenSkillFx.LEAD + ULT_TAKEOFF_LAG)
		tk.tween_property(sp0, "scale", Vector2(b0.x * 1.05, b0.y * 0.95), ULT_SQUASH_SEC)
		tk.tween_property(sp0, "scale", Vector2(b0.x * 0.95, b0.y * 1.05), ULT_SQUASH_SEC)
		tk.tween_property(sp0, "scale", b0, ULT_SQUASH_SEC)

	var hb = atk.get("barh")
	if hb is CanvasItem and is_instance_valid(hb):
		var hbn := hb as CanvasItem
		var hd: Vector2 = (hbn as Node2D).position - home
		var ht := (hbn as Node2D).create_tween()
		ht.tween_interval(AwakenSkillFx.LEAD)
		ht.tween_property(hbn, "position", stage + hd, ULT_JUMP_SEC)
		ht.tween_interval(total - AwakenSkillFx.LEAD - ULT_JUMP_SEC * 2.0)
		ht.tween_property(hbn, "position", home + hd, ULT_JUMP_SEC)
		var back := float(ULT_ACTOR_BACK.get(el, 7.0))
		hbn.modulate.a = 1.0
		var ft := hbn.create_tween()
		ft.tween_interval(AwakenSkillFx.ACT_AT)
		ft.tween_property(hbn, "modulate:a", 0.0, 1.0)
		ft.tween_interval(back)
		ft.tween_property(hbn, "modulate:a", 1.0, 1.0)

	_ultimate_hide_others(atk, hold)
	return total

const ULT_HIDE_TAIL := 0.5
const ULT_ACTOR_BACK := {
	"aqua": 7.75, "chaos": 7.65, "dark": 7.75, "earth": 5.8, "fire": 6.75,
	"holy": 7.5, "light": 8.35, "wind": 6.15, "shadow": 7.75,
}

func _ultimate_hide_others(atk: Dictionary, hold: float) -> void:
	var s := DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO
	var mine := bool(atk.get("mine", false))
	var vis := _vis()
	var gen := _gen
	for k in _views.keys():
		var v: Dictionary = _views[k]
		if v == atk:
			continue
		var node = v.get("node")
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		if bool(v.get("dead", false)):
			for key in ["node", "barh"]:
				var o = v.get(key)
				if o is CanvasItem and is_instance_valid(o) and (o as CanvasItem).visible:
					(o as CanvasItem).visible = false
					get_tree().create_timer(AwakenSkillFx.LEAD + hold + 0.5).timeout.connect(
						func() -> void:
							if is_instance_valid(self) and gen == _gen \
									and is_instance_valid(o):
								(o as CanvasItem).visible = true)
			continue
		if bool(v.get("mine", false)) != mine:
			continue
		var nd := node as Node2D
		var home: Vector2 = v.get("home", nd.position)
		var off := home + Vector2((-vis.x * 0.5) if mine else (vis.x * 0.5), 0.0)
		for pair in [["node", nd], ["barh", v.get("barh")]]:
			var o2 = pair[1]
			if not (o2 is Node2D) or not is_instance_valid(o2):
				continue
			var n2 := o2 as Node2D
			var p0: Vector2 = n2.position
			var d := off - home
			var t := n2.create_tween()
			t.tween_interval(AwakenSkillFx.LEAD)
			_tween_jump(t, n2, p0, p0 + d, ULT_JUMP_H * s, ULT_JUMP_SEC, 1.0)
			t.tween_interval(hold)
			_tween_jump(t, n2, p0 + d, p0, ULT_JUMP_H * s, ULT_JUMP_SEC, 1.0)

func _awaken_fx(atk: Dictionary, at: Vector2) -> void:
	var gen := _gen
	_ultimate_position(atk)
	var caster: Vector2 = _body_pos(atk) if not atk.is_empty() else at
	if not atk.is_empty():
		var vis := _vis()
		caster = Vector2(ULT_DX if bool(atk.get("mine", false)) else vis.x - ULT_DX,
			vis.y * 0.5 + ULT_DROP)
	var foes: Array = []
	for v in _views.values():
		if not (v is Dictionary):
			continue
		var vd: Dictionary = v
		if bool(vd.get("mine", false)) == bool(atk.get("mine", false)):
			continue
		if bool(vd.get("dead", false)):
			continue
		foes.append(_body_pos(vd))
	if foes.is_empty():
		foes.append(at)
	AwakenSkillFx.play(self, {
		"element": String(atk.get("element", "")),
		"mine": bool(atk.get("mine", false)),
		"ring_at": caster,
		"foes": foes,
		"caster_w": float(atk.get("dragon_w", DRAGON_H)),
		"scale": DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO,
		"speed": _speed,
		"mat": _pma,
		"alive": func() -> bool: return is_instance_valid(self) and gen == _gen,
	})
	_ultimate_hitstop(String(atk.get("element", "")))

const ULT_SLOW := 0.2 / 1.35
const ULT_HITSTOP := {
	"aqua":   [[5.27, 0.15]],
	"dark":   [[10.15, 0.04]],
	"shadow": [[7.90, 0.04]],
	"earth":  [[5.85, 0.10], [6.80, 0.10], [7.00, 0.05]],
}

func _ultimate_hitstop(element: String) -> void:
	if _speed != 1:
		return
	var wins: Array = ULT_HITSTOP.get(element, [])
	if wins.is_empty():
		return
	var gen := _gen
	for w: Array in wins:
		var onset := float(w[0])
		var span := float(w[1]) / ULT_SLOW
		get_tree().create_timer(onset).timeout.connect(func() -> void:
			if not is_instance_valid(self) or gen != _gen:
				return
			Engine.time_scale = ULT_SLOW
			get_tree().create_timer(span, true, false, true).timeout.connect(func() -> void:
				Engine.time_scale = 1.0))

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func _cutin(atk: Dictionary) -> void:
	var caster := {
		"id": int(atk.get("art_id", atk.get("id", 0))),
		"element": String(atk.get("element", "")),
		"awakened": bool(atk.get("awakened", false)),
	}
	_note_motion(CritCutin.show(self, caster, _speed) * _spd())

func _man(dir: String) -> Dictionary:
	return AtlasUI.manifest(dir)

const DMG_SIZE_HIT := 56
const DMG_SIZE_TOTAL := 93
const DMG_SCATTER := Vector2(100.0, 30.0)
const DMG_POP := 2.0
const DMG_POP_SEC := 0.25
const DMG_HOLD := 0.25
const DMG_RISE := 75.0
const DMG_RISE_SEC := 0.5
const TOTAL_LIFT := 235.0
const TOTAL_POP := 1.75
const TOTAL_FADE_WAIT := 0.5
const TOTAL_FADE_SEC := 0.5

func _num_label(at: Vector2, text: String, size: int, font: String) -> Label:
	var l := Label.new()
	l.text = text
	l.size = Vector2(360.0, 140.0)
	l.pivot_offset = l.size * 0.5
	l.position = at - l.pivot_offset
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bm_style(l, size, Color.WHITE, font)
	add_child(l)
	return l

func _hit_number(v: Dictionary, text: String, heal := false) -> void:
	var at := _body_pos(v) + Vector2(
		randf_range(-DMG_SCATTER.x, DMG_SCATTER.x),
		randf_range(-DMG_SCATTER.y, DMG_SCATTER.y))
	var l := _num_label(at, text, DMG_SIZE_HIT, "font_heal" if heal else "font_normal")
	l.z_index = 12
	l.scale = Vector2.ONE * DMG_POP
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, DMG_POP_SEC)
	tw.tween_interval(DMG_HOLD)
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - DMG_RISE, DMG_RISE_SEC)
	tw.tween_property(l, "modulate:a", 0.0, DMG_RISE_SEC)
	tw.set_parallel(false)
	tw.tween_callback(l.queue_free)

func _total_number(v: Dictionary, amount: int, final: bool, solo := false) -> void:
	if amount <= 0:
		return
	var l = v.get("total_lbl")
	if not (l is Label and is_instance_valid(l)):
		if final and not solo:
			return
		var ds := DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO
		l = _num_label(v.get("pos", _vis() * 0.5) - Vector2(0.0, TOTAL_LIFT * ds),
			str(amount), DMG_SIZE_TOTAL, "font_total")
		(l as Label).z_index = 13
		v["total_lbl"] = l
		v["total_val"] = amount
	else:
		v["total_val"] = int(v.get("total_val", 0)) + amount
		(l as Label).text = str(v["total_val"])
	var tw := create_tween()
	(l as Label).scale = Vector2.ONE * TOTAL_POP
	tw.tween_property(l, "scale", Vector2.ONE, DMG_POP_SEC)
	if final:
		v["total_lbl"] = null
		tw.tween_interval(TOTAL_FADE_WAIT)
		tw.tween_property(l, "modulate:a", 0.0, TOTAL_FADE_SEC)
		tw.tween_callback((l as Label).queue_free)

const RESULT_DELAY := 1.0
const RESULT_PANEL_SCALE := 0.9

func _finish() -> void:
	var win := _winner == "ally"
	var r := Colosseum.apply_result(_mode, win, String(_foe.get("nick", "")), _foe)

	var sub_done := StoryProgress.note_event({"kind": "COLOSSEUM", "win": win})
	if sub_done > 0:
		Toast.show(self, "서브미션 완료! %d화의 이야기가 이어집니다." % sub_done)

	for k in _views.keys():
		var v: Dictionary = _views[k]
		if not bool(v.get("dead", false)) and _has_anim(v, "wait"):
			_play_anim(v, "wait")
	await _wait(RESULT_DELAY)
	if not is_instance_valid(self):
		return

	var vis := _vis()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = vis
	add_child(dim)

	var bgk := "scene_colosseum_popup_win_bg_kr" if win else "scene_colosseum_popup_lose_bg_kr"
	var fgk := "scene_colosseum_popup_win_kr" if win else "scene_colosseum_popup_lose_kr"
	var b := _spr(CO, bgk, Design.ASSET_SCALE)
	if b != null:
		b.position = Vector2(vis.x * 0.5, vis.y * 0.42)
		add_child(b)
	var f := _spr(CO, fgk, Design.ASSET_SCALE)
	if f != null:
		f.position = Vector2(vis.x * 0.5, vis.y * 0.42)
		add_child(f)

	var streak := int(r.get("streak", 0))
	if streak > 0:
		var fist := _spr(CO, "scene_colosseum_icon_fist%d" % (2 if _mode == "team" else 1),
			Design.ASSET_SCALE)
		if fist != null:
			fist.position = Vector2(vis.x * 0.5 - 40.0, vis.y * 0.42 + 165.0)
			add_child(fist)
		var sl := Label.new()
		sl.text = "X%d" % streak
		sl.size = Vector2(120.0, 34.0)
		sl.position = Vector2(vis.x * 0.5 + 2.0, vis.y * 0.42 + 149.0)
		_bm_style(sl, 26, Color.WHITE)
		add_child(sl)

	var info := Label.new()
	var d := int(r.get("delta", 0))
	info.text = "%s%d점  →  %d점 (%s)" % [
		"+" if d >= 0 else "", d, int(r.get("rating_after", 0)),
		String((r.get("tier_after", {}) as Dictionary).get("name", ""))]
	info.size = Vector2(vis.x, 60.0)
	info.position = Vector2(0.0, vis.y * 0.42 + 90.0)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 24)
	add_child(info)

	if bool(r.get("tier_up", false)) or bool(r.get("tier_down", false)):
		ColosseumTierupView.open(self, r)

	AtlasUI.frame_button(self, "확인", Vector2(vis.x * 0.5 - 90.0, vis.y - 130.0),
		Vector2(180.0, 48.0), func() -> void:
			Scenes.goto("colosseum", {"from": "fight"}))

func _wait(sec: float) -> void:
	await get_tree().create_timer(maxf(0.01, sec / _spd())).timeout

func _spd() -> float:
	return float(maxi(1, _speed))

func _vis() -> Vector2:
	return get_viewport_rect().size

func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var j = JSON.parse_string(f.get_as_text())
	return j if typeof(j) == TYPE_DICTIONARY else {}

func _tex(dir: String, key: String) -> Texture2D:
	return AtlasUI.tex(dir, key)

func _spr(dir: String, key: String, scale := 1.0) -> Sprite2D:
	return AtlasUI.spr(dir, key, scale)

func _nine(key: String, sz_pt: Vector2, cap: Rect2) -> NinePatchRect:
	return _nine9(key, sz_pt, cap, NP)

func _nine9(key: String, sz_pt: Vector2, cap: Rect2, dir: String) -> NinePatchRect:
	var tex := _tex(dir, key)
	if tex == null:
		return null
	var inv := 1.0 / Design.ASSET_SCALE
	var l := cap.position.x * inv
	var t := cap.position.y * inv
	var cw := cap.size.x * inv
	var ch := cap.size.y * inv
	var np := NinePatchRect.new()
	np.texture = tex
	np.patch_margin_left = int(round(l))
	np.patch_margin_top = int(round(t))
	np.patch_margin_right = int(round(maxf(0.0, tex.get_width() - l - cw)))
	np.patch_margin_bottom = int(round(maxf(0.0, tex.get_height() - t - ch)))
	np.size = sz_pt
	np.material = _pma
	return np

const TOUCH_BOX := 0.75

var _info_panel: StatusPanel = null

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _info_panel != null and is_instance_valid(_info_panel):
		return
	var hit := _dragon_at(mb.position)
	if hit.is_empty():
		return
	var rec: Dictionary = hit.get("rec", {})
	if rec.is_empty():
		return
	accept_event()
	_info_panel = StatusPanel.open_panel(self, rec, bool(hit.get("mine", false)))

func _dragon_at(p: Vector2) -> Dictionary:
	for tag in _views:
		var v: Dictionary = _views[tag]
		if bool(v.get("dead", false)):
			continue
		var n = v.get("node")
		if not (n is Node2D) or not is_instance_valid(n):
			continue
		var pos: Vector2 = (n as Node2D).position
		var w := float(v.get("dragon_w", DRAGON_H)) * TOUCH_BOX
		var h := float(v.get("dragon_h", DRAGON_H)) * TOUCH_BOX
		var s := DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO
		w *= s
		h *= s
		if Rect2(pos - Vector2(w * 0.5, h), Vector2(w, h)).has_point(p):
			return v
	return {}
