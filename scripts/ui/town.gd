extends Control

const FLOOR := 692.0

const AREAS := {
	"dwarf": {
		"dir": "town_dwarf",
		"title": "드워프 마을",
		"fill_h": 523.0,
		"seg_w": 1013.0,
		"layers": [
			{"frames": ["scene_town_dwarf_bg1_dwarf_back1", "scene_town_dwarf_bg2_dwarf_back2"], "motion": 0.85},
			{"frames": ["scene_town_dwarf_bg1_dwarf_front1", "scene_town_dwarf_bg2_dwarf_front2"], "motion": 1.0},
			{"frames": ["scene_town_dwarf_bg1_dwarf_rock1", "scene_town_dwarf_bg2_dwarf_rock2"], "motion": 1.05},
		],
	},
	"elpis": {
		"dir": "town_elpis",
		"title": "엘피스 마을",
		"asset_scale": true,
		"has_night": true,
		"sky_day": Color(0.62, 0.82, 0.95),
		"sky_night": Color(0.09, 0.11, 0.24),
		"sky_image": "res://assets/converted/town_elpis_sky/elpis_sky.jpg",
		"sky_image_night": "res://assets/converted/town_elpis_sky/elpis_sky_night.jpg",
		"sections": [
			{"id": 1, "seg_w": 1156.0, "bottom": 250.0,
			 "frames": ["scene_town_elpis_bg_elpis_mt", "scene_town_elpis_bg_elpis_mt"],
			 "night_frames": ["scene_town_elpis_bg_night_elpis_mt", "scene_town_elpis_bg_night_elpis_mt"]},
			{"id": 3, "seg_w": 1168.0, "bottom": 120.0,
			 "frames": ["scene_town_elpis_bg_u_village_bg_b01", "scene_town_elpis_bg_u_village_bg_b02"],
			 "night_frames": ["scene_town_elpis_bg_night_u_village_bg_b01", "scene_town_elpis_bg_night_u_village_bg_b02"],
			 "objects": [
				{"frame": "scene_town_elpis_u_village_shop", "night": "scene_town_elpis_u_village_shop_night",
				 "x": 1658.0, "y": 326.0, "anchor": "left", "action": "shop", "label": "상점"},
				{"frame": "scene_town_elpis_u_village_shopname", "x": 1843.0, "y": 496.0, "anchor": "left"},
				{"frame": "scene_town_elpis_u_village_shop_book", "x": 1664.0, "y": 166.0, "anchor": "left"},
				{"frame": "scene_town_elpis_u_village_labname", "x": 872.0, "y": 318.0, "anchor": "left"},
				{"frame": "scene_town_elpis_u_village_lab_book", "x": 611.0, "y": 165.0, "anchor": "left"},
				{"frame": "scene_town_elpis_u_village_fortune", "night": "scene_town_elpis_u_village_fortune_night",
				 "x": 2831.0, "y": 254.0, "anchor": "left", "action": "fortune", "label": "운세"},
				{"frame": "scene_town_elpis_u_village_fortune_book", "x": 2812.0, "y": 105.0, "anchor": "left"},
				{"frame": "scene_town_elpis_u_village_order", "x": 619.0, "y": 151.0, "anchor": "bottom"},
				{"frame": "scene_town_elpis_u_village_order_book", "x": 608.0, "y": 165.0},
				{"frame": "scene_town_elpis_town_flower", "x": 2784.0, "y": 189.0, "anchor": "topleft"},
			 ],
			 "ambient": [
				{"flip": "scene_town_elpis_lab_smog_lab_smog_%s0%d", "n": 10, "day_key": "a", "night_key": "n",
				 "dir": "town_elpis_smog", "x": 933.0, "y": 617.0,
				 "night_x": 959.0, "night_y": 577.0},
				{"spine": "u_village_lab", "anim": "nomal", "x": 903.0, "y": 330.0,
				 "action": "lab", "label": "연구소"},
				{"spine": "duck", "anim": "animation", "x": 2628.0, "y": 153.0},
				{"flip": "scene_town_elpis_f_star%d", "n": 4, "x": 2959.0, "y": 369.0},
				{"spine": "u_village_light_spine", "anim": "normal", "x": 530.0, "y": 341.0},
				{"spine": "u_village_light_spine", "anim": "normal", "x": 1111.0, "y": 341.0},
				{"spine": "u_village_light_spine", "anim": "normal", "x": 1653.0, "y": 338.0},
				{"spine": "u_village_light_spine", "anim": "normal", "x": 2229.0, "y": 343.0},
				{"spine": "u_village_light_spine", "anim": "normal", "x": 2797.0, "y": 344.0},
			 ],
			 "npcs": [
				{"id": "annie", "tag": 0x74, "x": 1003.0, "y": 135.0, "roam": [0.0, 0.0],
				 "scale": 0.4667, "still": true, "anim": "wait"},
			 ]},
			{"id": 2, "seg_w": 1360.0, "bottom": 0.0,
			 "frames": ["scene_town_elpis_bg_u_village_bg_a01", "scene_town_elpis_bg_u_village_bg_a02"],
			 "night_frames": ["scene_town_elpis_bg_night_u_village_bg_a01", "scene_town_elpis_bg_night_u_village_bg_a02"],
			 "objects": [
				{"frame": "scene_town_elpis_u_village_dingdong", "night": "scene_town_elpis_u_village_dingdong_night",
				 "x": 1430.0, "y": 270.0},
				{"frame": "scene_town_elpis_town_clockboard", "x": 1441.0, "y": 486.0,
				 "hit_size": [200.0, 350.0], "hit_offset": [0.0, -70.0],
				 "action": "daynight", "label": "시계탑"},
				{"frame": "scene_town_elpis_town_clockpoint", "x": 1441.0, "y": 535.0},
				{"frame": "scene_town_elpis_town_mailbox", "x": 1983.0, "y": 8.0, "anchor": "bottom"},
				{"frame": "scene_town_elpis_u_village_cave", "x": 3526.0, "y": 8.0, "anchor": "bottom",
				 "action": "cave", "label": "둥지"},
			 ],
			 "ambient": [
				{"spine": "fountain", "anim": "fountain", "x": 1806.0, "y": 184.0},
			 ],
			 "npcs": [
				{"id": "randolph", "tag": 0x65, "x": 3093.0, "y": 70.0,  "roam": [200.0, 70.0],  "scale": 0.533},
				{"id": "yuria",    "qslot": 0,  "tag": 0x66, "x": 3363.0, "y": 115.0, "roam": [75.0, 20.0],   "scale": 0.533},
				{"id": "kanggalo", "qslot": 1,  "tag": 0x67, "x": 353.0,  "y": 70.0,  "roam": [180.0, 25.0],  "scale": 0.533},
				{"id": "popo",     "tag": 0x68, "x": 2293.0, "y": 55.0,  "roam": [200.0, 35.0],  "scale": 0.533},
				{"id": "dilis",    "tag": 0x69, "x": 1449.0, "y": 90.0,  "roam": [150.0, 25.0],  "scale": 0.533},
				{"id": "pino",     "qslot": 2,  "tag": 0x6a, "x": 713.0,  "y": 120.0, "roam": [270.0, 20.0],  "scale": 0.533},
				{"id": "romini",   "qslot": 3,  "tag": 0x6b, "x": 2663.0, "y": 65.0,  "roam": [250.0, 100.0], "scale": 0.533},
				{"id": "baruseu",  "tag": 0x6c, "x": 1013.0, "y": 75.0,  "roam": [260.0, 55.0],  "scale": 0.533},
				{"id": "zumon",    "tag": 0x6d, "x": 1613.0, "y": 45.0,  "roam": [300.0, 50.0],  "scale": 0.556},
				{"id": "nuri",     "qslot": 4,  "tag": 0x6e, "x": 2083.0, "y": 107.0, "roam": [250.0, 25.0],  "scale": 0.667},
				{"id": "raon",     "qslot": 5,  "tag": 0x6f, "x": 1813.0, "y": 25.0,  "roam": [3000.0, 10.0], "scale": 0.533},
				{"id": "nelson",   "tag": 0x70, "x": 613.0,  "y": 135.0, "roam": [800.0, 15.0],  "scale": 0.533},
				{"id": "aria",     "tag": 0x71, "x": 3013.0, "y": 85.0,  "roam": [550.0, 30.0],  "scale": 0.533},
				{"id": "guy",      "tag": 0x72, "x": 2913.0, "y": 30.0,  "roam": [1500.0, 10.0], "scale": 0.533},
				{"id": "grandma",  "tag": 0x73, "x": 2513.0, "y": 135.0, "roam": [800.0, 15.0],  "scale": 0.533},
			 ]},
		],
	},
}

var _pma: CanvasItemMaterial
var _manifest: Dictionary = {}
var _area_id := "dwarf"
var _night := false
var _sky: ColorRect
var _world: Node2D
var _layers: Array = []
var _scroll_x := 0.0
var _max_scroll := 0.0
var _sc := 1.0
var _dragging := false
var _hit_areas: Array = []
var _clouds: Array = []
var _hud: MainHud

func town_quest_progress() -> Vector2i:
	var done := 0
	for qd in _QUESTS:
		if UserDB.quest_claimed(String(qd["key"])):
			done += 1
	return Vector2i(done, _QUESTS.size())

func town_quest_alert() -> bool:
	for qd in _QUESTS:
		if UserDB.quest_count(String(qd["key"])) >= int(qd["goal"]) and not UserDB.quest_claimed(String(qd["key"])):
			return true
	return false

func town_area_id() -> String:
	return _area_id

func _refresh_hud() -> void:
	_hud = MainHud.attach(self, false, "", "town")
	if not _hud.town_close.is_connected(_on_worldmap):
		_hud.town_close.connect(_on_worldmap)
	if not _hud.town_quest.is_connected(_open_quests):
		_hud.town_quest.connect(_open_quests)

func enter(params: Dictionary = {}) -> void:
	var a: String = params.get("area", "dwarf")
	_night = _resolve_night(params)
	if a != _area_id or _world == null:
		_area_id = a
	if _pma != null:
		_rebuild()

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_rebuild()

func _rebuild() -> void:
	Bgm.play("bg_town")
	for c in get_children():
		c.queue_free()
	_layers.clear()
	_hit_areas.clear()
	_npcs.clear()
	var area: Dictionary = AREAS.get(_area_id, AREAS["dwarf"])
	_manifest = _load_manifest(area["dir"])
	if area.get("asset_scale", false):
		_sc = Design.ASSET_SCALE
	else:
		_sc = FLOOR / float(area["fill_h"]) if area.has("fill_h") else float(area.get("scale", 1.0))

	if area.has("sky_day"):
		_sky = ColorRect.new()
		_sky.color = area["sky_night"] if _night else area["sky_day"]
		_sky.set_anchors_preset(Control.PRESET_FULL_RECT)
		_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_sky)
		var skp := String(area.get("sky_image_night" if _night else "sky_image", ""))
		if skp != "" and ResourceLoader.exists(skp):
			var sky_spr := Sprite2D.new()
			sky_spr.texture = load(skp)
			sky_spr.centered = false
			add_child(sky_spr)
		_build_clouds(area)

	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)

	if area.has("sections"):
		_build_sections(area)
	else:
		_build_legacy_layers(area)

	_scroll_x = 0.0
	_apply_scroll()
	_intro_zoom()
	_build_hud(area)

func _build_sections(area: Dictionary) -> void:
	var vis_x := _vis().x
	var widths: Array = []
	for sec in area["sections"]:
		widths.append(float(sec["seg_w"]) * _sc * (sec["frames"] as Array).size())
	var max_w: float = widths.max()
	_max_scroll = maxf(0.0, max_w - vis_x)
	for i in (area["sections"] as Array).size():
		var sec: Dictionary = area["sections"][i]
		var sec_w: float = widths[i]
		var motion := 0.0
		if _max_scroll > 0.0:
			motion = clampf((sec_w - vis_x) / _max_scroll, 0.0, 1.0)
		var layer := Node2D.new()
		layer.name = "Sec%d" % int(sec.get("id", i))
		_world.add_child(layer)
		var frames: Array = sec["frames"]
		var night_frames: Array = sec.get("night_frames", frames)
		var bottom := float(sec.get("bottom", 0.0))
		var lw: float = float(sec["seg_w"]) * _sc
		for k in frames.size():
			var fr: String = night_frames[k] if _night else frames[k]
			var spr := _atlas_sprite(area["dir"], fr, _manifest, _sc)
			var h: float = float(_manifest.get(fr, {}).get("h", 260)) * _sc
			spr.position = Vector2((k + 0.5) * lw, FLOOR - bottom - h * 0.5)
			layer.add_child(spr)
		for ob in sec.get("objects", []):
			_place_object(layer, area["dir"], ob, area, motion)
		for am in sec.get("ambient", []):
			_place_ambient(layer, area["dir"], am, area, motion)
		for np in sec.get("npcs", []):
			_place_npc(layer, np, motion)
		_layers.append({"node": layer, "motion": motion})

func _build_legacy_layers(area: Dictionary) -> void:
	var segw: float = float(area["seg_w"]) * _sc
	var town_w := segw * 2
	for ld in area["layers"]:
		var layer := Node2D.new()
		_world.add_child(layer)
		var frames: Array = ld["frames"]
		var night_frames: Array = ld.get("night_frames", frames)
		var bottom: float = float(ld.get("bottom", 0.0)) * _sc
		for i in frames.size():
			var fr: String = night_frames[i] if _night else frames[i]
			var spr := _atlas_sprite(area["dir"], fr, _manifest, _sc)
			var h: float = float(_manifest.get(fr, {}).get("h", area.get("fill_h", 260))) * _sc
			spr.position = Vector2((i + 0.5) * segw, FLOOR - bottom - h * 0.5)
			layer.add_child(spr)
		_layers.append({"node": layer, "motion": float(ld["motion"])})
	if area.has("objects"):
		var obj_layer := Node2D.new()
		_world.add_child(obj_layer)
		for ob in area["objects"]:
			_place_object(obj_layer, area["dir"], ob, area, 1.0)
		_layers.append({"node": obj_layer, "motion": 1.0})
	_max_scroll = maxf(0.0, town_w - _vis().x)

func _intro_zoom() -> void:
	if _world == null: return
	var c := _vis() * 0.5
	var s := 1.12
	_world.scale = Vector2(s, s)
	_world.position = c * (1.0 - s)
	var tw := _world.create_tween().set_parallel(true)
	tw.tween_property(_world, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_world, "position", Vector2.ZERO, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _place_object(layer: Node2D, dir: String, ob: Dictionary, area: Dictionary, motion := 1.0) -> void:
	var fr: String = ob.get("night", ob["frame"]) if (_night and ob.has("night")) else ob["frame"]
	var spr := _atlas_sprite(dir, fr, _manifest, _sc)
	var info: Dictionary = _manifest.get(fr, {})
	var w: float = float(info.get("w", 100)) * _sc
	var h: float = float(info.get("h", 100)) * _sc
	var c := _obj_center(ob, area, w, h)
	spr.position = c
	layer.add_child(spr)
	if String(ob.get("action", "")) != "":
		var hw := w
		var hh := h
		var hc := c
		if ob.has("hit_size"):
			var hs: Array = ob["hit_size"]
			hw = float(hs[0]) * _sc
			hh = float(hs[1]) * _sc
		if ob.has("hit_offset"):
			var ho: Array = ob["hit_offset"]
			hc = c + Vector2(float(ho[0]) * _sc, -float(ho[1]) * _sc)
		_hit_areas.append({"rect": Rect2(hc.x - hw * 0.5, hc.y - hh * 0.5, hw, hh), "motion": motion,
			"action": String(ob["action"]), "label": String(ob.get("label", ""))})

func _obj_center(ob: Dictionary, area: Dictionary, w: float, h: float) -> Vector2:
	if not area.get("asset_scale", false):
		var bottom: float = float(ob.get("bottom", 0.0)) * _sc
		return Vector2(float(ob["x"]) * _sc, FLOOR - bottom - h * 0.5)
	var x := float(ob["x"])
	var y := float(ob.get("y", 0.0))
	match String(ob.get("anchor", "center")):
		"left":   return Vector2(x + w * 0.5, FLOOR - y)
		"bottom": return Vector2(x, FLOOR - y - h * 0.5)
		"topleft": return Vector2(x + w * 0.5, FLOOR - y + h * 0.5)
		_:        return Vector2(x, FLOOR - y)

const _TOWN_FLIP_DELAY := 0.2
func _place_ambient(layer: Node2D, dir: String, am: Dictionary, area: Dictionary, motion := 1.0) -> void:
	var am2 := am
	if _night and (am.has("night_x") or am.has("night_y")):
		am2 = am.duplicate()
		am2["x"] = am.get("night_x", am.get("x", 0.0))
		am2["y"] = am.get("night_y", am.get("y", 0.0))
	var pos := _obj_center(am2, area, 0.0, 0.0)
	if am.has("spine"):
		var sp := "res://scenes/town_fx/%s.tscn" % String(am["spine"])
		if not ResourceLoader.exists(sp):
			return
		var inst := (load(sp) as PackedScene).instantiate() as Node2D
		if inst == null:
			return
		inst.position = pos
		layer.add_child(inst)
		var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap:
			var an := String(am.get("anim", ""))
			if an == "" or not ap.has_animation(an):
				an = ap.get_animation_list()[0] if ap.get_animation_list().size() > 0 else ""
			if an != "":
				var anim := ap.get_animation(an)
				if anim: anim.loop_mode = Animation.LOOP_LINEAR
				ap.play(an)
		if String(am.get("action", "")) != "":
			_hit_areas.append({"rect": Rect2(pos.x - 90.0, pos.y - 110.0, 180.0, 220.0), "motion": motion,
				"action": String(am["action"]), "label": String(am.get("label", ""))})
		return
	if not am.has("flip"):
		return
	var fdir := String(am.get("dir", dir))
	var fman: Dictionary = _load_manifest(fdir) if fdir != dir else _manifest
	var pat := String(am["flip"])
	var daynight: bool = am.has("day_key")
	var keys: Array = []
	for i in range(1, int(am.get("n", 1)) + 1):
		var k: String = (pat % [String(am["night_key"] if _night else am["day_key"]), i]) if daynight else (pat % i)
		if fman.has(k): keys.append(k)
	if keys.is_empty():
		return
	var spr := _atlas_sprite(fdir, String(keys[0]), fman, _sc)
	spr.z_index = int(am.get("z", 0))
	layer.add_child(spr)
	var frames_ta: Array = []
	for k in keys:
		var mi: Dictionary = fman.get(String(k), {})
		var o: Array = mi.get("off", [0, 0])
		frames_ta.append({"t": _atlas_tex(fdir, String(k)),
			"p": pos + Vector2(float(o[0]), -float(o[1])) * _sc})
	var tw := spr.create_tween().set_loops()
	for fr2 in frames_ta:
		var t2: Texture2D = fr2["t"]
		var p2: Vector2 = fr2["p"]
		tw.tween_callback(func():
			if t2:
				spr.texture = t2
				spr.position = p2)
		tw.tween_interval(_TOWN_FLIP_DELAY)

const NPC_WALK_SPEED := 42.0
const NPC_WAIT_MIN := 1.6
const NPC_WAIT_MAX := 4.5
const NPC_HITBOX := Vector2(100.0, 150.0)

var _npcs: Array = []

func _place_npc(layer: Node2D, np: Dictionary, motion: float) -> void:
	if bool(np.get("disabled", false)):
		return
	var sp := "res://scenes/npc_town/sd_%s.tscn" % String(np["id"])
	if not ResourceLoader.exists(sp):
		return
	var inst := (load(sp) as PackedScene).instantiate() as Node2D
	if inst == null:
		return
	var holder := Node2D.new()
	holder.name = "Npc_%s" % String(np["id"])
	holder.z_index = 300
	var sc := float(np.get("scale", 0.533))
	inst.scale = Vector2(sc, sc)
	holder.add_child(inst)
	layer.add_child(holder)
	var roam: Array = np.get("roam", [0.0, 0.0])
	var home := Vector2(float(np["x"]), float(np["y"]))
	var p0 := _npc_rand_point(home, roam)
	holder.position = Vector2(p0.x, FLOOR - p0.y)
	var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var rec := {"node": holder, "ap": ap, "spr": inst, "home": home, "roam": roam,
		"base_sx": sc, "facing": 1,
		"id": String(np["id"]), "still": bool(np.get("still", false)),
		"walking": false, "t": randf_range(NPC_WAIT_MIN, NPC_WAIT_MAX), "dest": holder.position}
	rec["idle_anim"] = String(np.get("anim", "wait"))
	_npcs.append(rec)
	_npc_play(rec, String(rec["idle_anim"]))
	rec["qslot"] = int(np.get("qslot", -1))
	_npc_face(rec)
	_npc_quest_mark(rec)
	_hit_areas.append({"rect": Rect2(holder.position.x - NPC_HITBOX.x * 0.5,
			holder.position.y - NPC_HITBOX.y, NPC_HITBOX.x, NPC_HITBOX.y),
		"motion": motion, "action": "npc:" + String(np["id"]), "label": "", "npc": rec})

func _npc_rand_point(home: Vector2, roam: Array) -> Vector2:
	var rx := float(roam[0]); var ry := float(roam[1])
	return Vector2(home.x + randf_range(-rx * 0.5, rx * 0.5),
		home.y + randf_range(-ry * 0.5, ry * 0.5))

const NPC_Z_BASE := 300
const NPC_Z_STEP := 64
func _sort_npc_z() -> void:
	var live: Array = []
	for rec in _npcs:
		var n: Node2D = rec.get("node")
		if n != null and is_instance_valid(n):
			live.append(rec)
	live.sort_custom(func(a, b):
		return (a["node"] as Node2D).position.y < (b["node"] as Node2D).position.y)
	for i in live.size():
		(live[i]["node"] as Node2D).z_index = NPC_Z_BASE + i * NPC_Z_STEP

const QMARK_TAG := 0x66
func _npc_quest_state(qslot: int) -> String:
	if qslot < 0 or qslot >= _QUESTS.size():
		return ""
	var qd: Dictionary = _QUESTS[qslot]
	var key := String(qd["key"])
	if UserDB.quest_claimed(key) or UserDB.quest_gaveup(key):
		return ""
	if not UserDB.quest_accepted(key):
		return "offer"
	if UserDB.quest_progress(key) >= int(qd["goal"]):
		return "reward"
	return "progress"

func _npc_quest_mark(rec: Dictionary) -> void:
	var node: Node2D = rec.get("node")
	if node == null or not is_instance_valid(node):
		return
	var old := node.get_node_or_null("QMark")
	if old != null:
		old.queue_free()
	var st := _npc_quest_state(int(rec.get("qslot", -1)))
	if st == "":
		return
	var dir_ := "common_ui" if st == "reward" else "town_elpis"
	var key := "common_alert3" if st == "reward" else "scene_town_elpis_txt_balloon"
	var sc := 1.3 if st == "reward" else 0.8
	var m := _atlas_sprite(dir_, key, _load_manifest(dir_), sc)
	if m.texture == null:
		return
	m.name = "QMark"
	m.position = Vector2(0.0, -(NPC_HITBOX.y + 23.0))
	m.z_index = 5
	node.add_child(m)
	var tw := m.create_tween().set_loops()
	var y0 := m.position.y
	for amp in [10.0, 7.0, 3.0]:
		tw.tween_property(m, "position:y", y0 - amp, 0.8).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "position:y", y0, 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

func _refresh_quest_marks() -> void:
	for rec in _npcs:
		_npc_quest_mark(rec)

const NPC_FACE_SIGN := -1
func _npc_face(rec: Dictionary) -> void:
	var spr: Node2D = rec.get("spr")
	if spr == null or not is_instance_valid(spr):
		return
	var b := float(rec.get("base_sx", 0.533))
	spr.scale.x = b * float(int(rec.get("facing", 1)) * NPC_FACE_SIGN)

func _npc_play(rec: Dictionary, an: String) -> void:
	var ap: AnimationPlayer = rec.get("ap")
	if ap == null or not ap.has_animation(an):
		return
	var a := ap.get_animation(an)
	if a: a.loop_mode = Animation.LOOP_LINEAR if an in ["wait", "walk"] else Animation.LOOP_NONE
	ap.play(an)

func _process_npcs(delta: float) -> void:
	_sort_npc_z()
	for rec in _npcs:
		var node: Node2D = rec["node"]
		if not is_instance_valid(node):
			continue
		if bool(rec["still"]) or bool(rec.get("talking", false)):
			continue
		if float(rec.get("endt", 0.0)) > 0.0:
			rec["endt"] = float(rec["endt"]) - delta
			if float(rec["endt"]) <= 0.0:
				_npc_play(rec, String(rec.get("idle_anim", "wait")))
		rec["t"] = float(rec["t"]) - delta
		if bool(rec["walking"]):
			var dest: Vector2 = rec["dest"]
			var d := dest - node.position
			if d.length() <= NPC_WALK_SPEED * delta:
				node.position = dest
				rec["walking"] = false
				rec["t"] = randf_range(NPC_WAIT_MIN, NPC_WAIT_MAX)
				_npc_play(rec, "walk_end")
				rec["endt"] = 0.4
			else:
				node.position += d.normalized() * NPC_WALK_SPEED * delta
		elif float(rec["t"]) <= 0.0:
			var np2 := _npc_rand_point(rec["home"], rec["roam"])
			var dest2 := Vector2(np2.x, FLOOR - np2.y)
			var dx := dest2.x - node.position.x
			if absf(dx) > 1.0:
				rec["facing"] = -1 if dx < 0.0 else 1
				_npc_face(rec)
			rec["dest"] = dest2
			rec["walking"] = true
			_npc_play(rec, "walk")
		for ha in _hit_areas:
			if ha.get("npc") == rec:
				ha["rect"] = Rect2(node.position.x - NPC_HITBOX.x * 0.5,
					node.position.y - NPC_HITBOX.y, NPC_HITBOX.x, NPC_HITBOX.y)

var _npc_line_idx := {}
var _talking: Dictionary = {}

func _npc_stop_talking() -> void:
	if _talking.is_empty():
		return
	var r := _talking
	_talking = {}
	if not r.is_empty() and is_instance_valid(r.get("node")):
		r["talking"] = false
		r["t"] = randf_range(NPC_WAIT_MIN, NPC_WAIT_MAX)
		_npc_play(r, String(r.get("idle_anim", "wait")))
func _on_npc_click(npc_id: String) -> void:
	var db: Dictionary = Data.npc_lines() if Data.has_method("npc_lines") else {}
	var info: Dictionary = db.get(npc_id, {})
	var lines_: Array = info.get("lines", [])
	var who := String(info.get("name", ""))
	if lines_.is_empty():
		return
	UserDB.bump_quest("talks")
	var rec := {}
	for r in _npcs:
		if String(r["id"]) == npc_id:
			rec = r; break
	_npc_stop_talking()
	if not rec.is_empty():
		rec["talking"] = true
		rec["walking"] = false
		rec["dest"] = (rec["node"] as Node2D).position
		_talking = rec
		_npc_play(rec, "happy")
		rec["endt"] = 1.2
	for qi in _QUESTS.size():
		if String((_QUESTS[qi] as Dictionary)["npc"]) != npc_id:
			continue
		if _npc_quest_talk(npc_id, qi, rec, who):
			return
		break
	_show_npc_balloon(rec, who, String(lines_[randi() % lines_.size()]))

const BALLOON_TYPE_DT := 0.05
const BALLOON_WRAP_W := 250.0
const BALLOON_CAP := Rect2(20, 20, 16, 16)
var _balloon: Node2D
var _balloon_lbl: Label
var _balloon_body: NinePatchRect
var _balloon_arrow: Sprite2D
var _balloon_full := ""
var _balloon_i := 0
var _balloon_t := 0.0
var _balloon_done := false
func _show_npc_balloon(rec: Dictionary, who: String, line: String) -> void:
	if _balloon != null and is_instance_valid(_balloon):
		_balloon.queue_free()
	var root := Node2D.new()
	root.z_index = 900
	root.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	var pad := 14.0
	var lbl := Label.new()
	lbl.text = line
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.16, 0.12, 0.09))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var nm: Label = null
	if who != "":
		nm = Label.new()
		nm.text = who
		nm.add_theme_font_size_override("font_size", 14)
		nm.add_theme_color_override("font_color", Color(0.85, 0.45, 0.15))
	var fnt := lbl.get_theme_font("font")
	if fnt == null:
		fnt = ThemeDB.fallback_font
	var fsz := lbl.get_theme_font_size("font_size")
	if fsz <= 0:
		fsz = 15
	var wrap_w := BALLOON_WRAP_W
	var th := 20.0
	if fnt != null:
		th = fnt.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_CENTER, wrap_w, fsz).y
	var nh := 0.0
	if nm != null:
		var nf := nm.get_theme_font("font")
		if nf == null:
			nf = ThemeDB.fallback_font
		var ns := nm.get_theme_font_size("font_size")
		if ns <= 0:
			ns = 14
		nh = (nf.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, ns).y if nf != null else 18.0) + 3.0
	var w := wrap_w + pad * 2
	var h := th + nh + pad * 2
	var tsz := Vector2(wrap_w, th)
	lbl.custom_minimum_size = Vector2(wrap_w, th)
	lbl.clip_text = false
	var body := NinePatchRect.new()
	var tex := _atlas_tex("town_elpis", "scene_town_elpis_txt_balloon2")
	if tex != null:
		body.texture = tex
		body.patch_margin_left = int(BALLOON_CAP.position.x)
		body.patch_margin_top = int(BALLOON_CAP.position.y)
		body.patch_margin_right = int(BALLOON_CAP.size.x)
		body.patch_margin_bottom = int(BALLOON_CAP.size.y)
	body.size = Vector2(w, h)
	body.position = Vector2(-w * 0.5, -h)
	root.add_child(body)
	var y := pad
	if nm != null:
		nm.position = Vector2(pad, y); nm.size = Vector2(w - pad * 2, nh)
		body.add_child(nm); y += nh
	lbl.position = Vector2(pad, y); lbl.size = Vector2(w - pad * 2, tsz.y)
	body.add_child(lbl)
	var tail := _atlas_sprite("town_elpis", "scene_town_elpis_txt_balloon_bot", _manifest, 1.0)
	if tail.texture != null:
		var tail_h := float(_manifest.get("scene_town_elpis_txt_balloon_bot", {}).get("h", 10))
		tail.position = Vector2(0, tail_h * 0.5)
		root.add_child(tail)
	add_child(root)
	_balloon = root
	_balloon.set_meta("npc", rec)
	_balloon_lbl = lbl
	_balloon_body = body
	_balloon_full = line
	_balloon_i = 0
	_balloon_t = 0.0
	_balloon_done = false
	lbl.text = ""
	_position_balloon()
	var base_y := root.position.y
	root.position.y = base_y + 18.0
	root.scale = Vector2(Design.ASSET_SCALE * 0.8, Design.ASSET_SCALE * 0.8)
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(root, "position:y", base_y - 8.0, 0.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "scale", Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE), 0.2)
	tw.chain().tween_property(root, "position:y", base_y, 0.1)

func _process_balloon(delta: float) -> void:
	if _balloon == null or not is_instance_valid(_balloon) or _balloon_done:
		return
	_balloon_t += delta
	while _balloon_t >= BALLOON_TYPE_DT and _balloon_i < _balloon_full.length():
		_balloon_t -= BALLOON_TYPE_DT
		_balloon_i += 1
		while _balloon_i < _balloon_full.length() and _balloon_full[_balloon_i] in [" ", "
"]:
			_balloon_i += 1
	if _balloon_lbl != null and is_instance_valid(_balloon_lbl):
		_balloon_lbl.text = _balloon_full.substr(0, _balloon_i)
	if _balloon_i >= _balloon_full.length():
		_balloon_show_all()

func _balloon_show_all() -> void:
	_balloon_done = true
	_balloon_i = _balloon_full.length()
	if _balloon_lbl != null and is_instance_valid(_balloon_lbl):
		_balloon_lbl.text = _balloon_full
	_balloon_next_arrow()

func _balloon_next_arrow() -> void:
	if _balloon == null or not is_instance_valid(_balloon) or _balloon_arrow != null:
		return
	var a := _atlas_sprite("common_ui", "common_btn_arrow2", {}, 1.0)
	if a.texture == null:
		return
	_balloon_arrow = a
	var bw := _balloon_body.size.x if _balloon_body != null else 160.0
	a.position = Vector2(bw * 0.5 - 12.0, -10.0)
	_balloon.add_child(a)
	var tw := a.create_tween().set_loops()
	tw.tween_property(a, "scale", Vector2(0.75, 0.75), 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(a, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)

func _balloon_close() -> void:
	if _balloon == null or not is_instance_valid(_balloon):
		return
	_npc_stop_talking()
	var b := _balloon
	_balloon = null
	_balloon_lbl = null
	_balloon_body = null
	_balloon_arrow = null
	var tw := b.create_tween()
	tw.tween_property(b, "position:y", b.position.y - 10.0, 0.1)
	tw.set_parallel(true)
	tw.tween_property(b, "position:y", b.position.y + 20.0, 0.1)
	tw.tween_property(b, "scale", b.scale * 0.6, 0.1)
	tw.chain().tween_callback(func(): if is_instance_valid(b): b.queue_free())

func _balloon_consume_click() -> bool:
	if _balloon == null or not is_instance_valid(_balloon):
		return false
	if _balloon_done:
		_balloon_close()
	else:
		_balloon_show_all()
	return true

func _position_balloon() -> void:
	if _balloon == null or not is_instance_valid(_balloon):
		return
	var rec: Dictionary = _balloon.get_meta("npc", {})
	if rec.is_empty() or not is_instance_valid(rec.get("node")):
		return
	var node: Node2D = rec["node"]
	var m := 1.0
	for ha in _hit_areas:
		if ha.get("npc") == rec:
			m = float(ha.get("motion", 1.0)); break
	_balloon.position = Vector2(node.position.x - _scroll_x * m, node.position.y - 170.0)

func _build_clouds(area: Dictionary) -> void:
	_clouds.clear()
	var vis := _vis()
	var cloud_node := Node2D.new(); cloud_node.name = "Clouds"
	add_child(cloud_node)
	var suffix := "_night" if _night else ""
	var rng := RandomNumberGenerator.new(); rng.seed = hash(_area_id) ^ (1 if _night else 0)
	for i in 5:
		var fr := "scene_town_elpis_town_cloud%d%s" % [(i % 5) + 1, suffix]
		var spr := _atlas_sprite(area["dir"], fr, _manifest, _sc * rng.randf_range(0.5, 0.85))
		if spr == null: continue
		var info: Dictionary = _manifest.get(fr, {})
		var w: float = float(info.get("w", 200)) * _sc
		spr.position = Vector2(rng.randf_range(0.0, vis.x), 14.0 + float(i % 3) * 26.0 + rng.randf_range(-6, 6))
		spr.modulate.a = 0.9 if not _night else 0.7
		cloud_node.add_child(spr)
		_clouds.append({"node": spr, "speed": rng.randf_range(8.0, 22.0), "w": w})

func _process(delta: float) -> void:
	if not _npcs.is_empty():
		_process_npcs(delta)
		_position_balloon()
	_process_balloon(delta)
	if _clouds.is_empty(): return
	var vis := _vis()
	for c in _clouds:
		var spr: Sprite2D = c["node"]
		if not is_instance_valid(spr): continue
		spr.position.x += float(c["speed"]) * delta
		if spr.position.x - float(c["w"]) * 0.5 > vis.x:
			spr.position.x = -float(c["w"]) * 0.5

func _apply_scroll() -> void:
	for l in _layers:
		(l["node"] as Node2D).position.x = -_scroll_x * float(l["motion"])

var _press_pos := Vector2.ZERO
var _moved := false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_press_pos = event.position
			_moved = false
		elif not _moved:
			if not _balloon_consume_click():
				_try_click(event.position)
	elif event is InputEventMouseMotion and _dragging:
		if event.position.distance_to(_press_pos) > 6.0:
			_moved = true
		_scroll_x = clampf(_scroll_x - event.relative.x, 0.0, _max_scroll)
		_apply_scroll()

func _try_click(screen_pos: Vector2) -> void:
	for ha in _hit_areas:
		var m := float(ha.get("motion", 1.0))
		var world_pos := Vector2(screen_pos.x + _scroll_x * m, screen_pos.y)
		if (ha["rect"] as Rect2).has_point(world_pos):
			_on_object(ha["action"])
			return

func _on_object(action: String) -> void:
	if action.begins_with("npc:"):
		_on_npc_click(action.substr(4))
		return
	match action:
		"cave":
			Scenes.goto("cave")
		"worldmap":
			_on_worldmap()
		"shop":
			Scenes.goto("shop", {"area": _area_id})
		"lab":
			Scenes.goto("laboratory", {"area": _area_id})
		"fortune":
			Scenes.goto("magicshop", {"area": _area_id})
		"daynight":
			_open_daynight_confirm()
		_:
			push_warning("[Town] '%s' 화면 미구현 — 스텁" % action)

func _open_lab_furnace() -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 60; add_child(layer)
	var bg := ColorRect.new(); bg.color = Color(0.05, 0.04, 0.08, 1.0); bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var sp := "res://scenes/fx/lab_furnace.tscn"
	if ResourceLoader.exists(sp):
		var spine := (load(sp) as PackedScene).instantiate()
		spine.position = Vector2(vis.x * 0.5, vis.y * 0.5 + 60.0)
		layer.add_child(spine)
		var ap := spine.get_node_or_null("AnimationPlayer")
		if ap:
			ap.get_animation("animation").loop_mode = Animation.LOOP_LINEAR if ap.has_animation("animation") else 0
			ap.play("animation")
		var hit := Button.new(); hit.flat = true; hit.size = Vector2(320, 320)
		hit.position = Vector2(vis.x * 0.5 - 160, vis.y * 0.5 - 100)
		hit.pressed.connect(_open_lab_make_skill); layer.add_child(hit)
	var title := Label.new(); title.text = "마모루딕 연구소 — 스킬 제작"
	title.add_theme_font_size_override("font_size", 22); title.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.size = Vector2(vis.x, 30); title.position = Vector2(0, 24)
	layer.add_child(title)
	var hint := Label.new(); hint.text = "용광로를 눌러 스킬 스크롤을 제작하세요"
	hint.add_theme_font_size_override("font_size", 16); hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.7))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hint.size = Vector2(vis.x, 22); hint.position = Vector2(0, vis.y - 44)
	layer.add_child(hint)
	var brk := Button.new(); brk.text = "스킬 분해 →"; brk.size = Vector2(130, 40); brk.position = Vector2(vis.x - 150, 24)
	brk.pressed.connect(func():
		if is_instance_valid(layer): layer.queue_free()
		_open_lab_machine())
	layer.add_child(brk)
	var back := _atlas_sprite("common_ui", "common_back_btn", _load_manifest("common_ui"), 0.8)
	var bb := Button.new(); bb.flat = true; bb.size = Vector2(64, 48); bb.position = Vector2(12, 12)
	bb.pressed.connect(func(): if is_instance_valid(layer): layer.queue_free()); layer.add_child(bb)
	if back: back.position = Vector2(40, 34); layer.add_child(back)

func _open_lab_machine() -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 60; add_child(layer)
	var bg := ColorRect.new(); bg.color = Color(0.03, 0.03, 0.06, 1.0); bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var sp := "res://scenes/fx/lab_machine.tscn"
	if ResourceLoader.exists(sp):
		var spine := (load(sp) as PackedScene).instantiate()
		spine.position = Vector2(vis.x * 0.5, vis.y * 0.5 + 40.0)
		layer.add_child(spine)
		var ap := spine.get_node_or_null("AnimationPlayer")
		if ap and ap.has_animation("animation"):
			ap.get_animation("animation").loop_mode = Animation.LOOP_LINEAR
			ap.play("animation")
		var hit := Button.new(); hit.flat = true; hit.size = Vector2(320, 320)
		hit.position = Vector2(vis.x * 0.5 - 160, vis.y * 0.5 - 120)
		hit.pressed.connect(_open_lab_breakdown); layer.add_child(hit)
	var title := Label.new(); title.text = "마모루딕 연구소 — 스킬 분해"
	title.add_theme_font_size_override("font_size", 22); title.add_theme_color_override("font_color", Color(0.8, 0.9, 1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.size = Vector2(vis.x, 30); title.position = Vector2(0, 24)
	layer.add_child(title)
	var hint := Label.new(); hint.text = "분해기를 눌러 스킬 스크롤을 재료로 분해하세요"
	hint.add_theme_font_size_override("font_size", 16); hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hint.size = Vector2(vis.x, 22); hint.position = Vector2(0, vis.y - 44)
	layer.add_child(hint)
	var back := _atlas_sprite("common_ui", "common_back_btn", _load_manifest("common_ui"), 0.8)
	var bb := Button.new(); bb.flat = true; bb.size = Vector2(64, 48); bb.position = Vector2(12, 12)
	bb.pressed.connect(func(): if is_instance_valid(layer): layer.queue_free()); layer.add_child(bb)
	if back: back.position = Vector2(40, 34); layer.add_child(back)

func _open_lab_breakdown() -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 62; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.6); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: layer.queue_free()); layer.add_child(dim)
	const BW := 440.0
	const BH := 200.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2((vis.x - BW) * 0.5, (vis.y - BH) * 0.5); layer.add_child(win)
	var ml := Label.new()
	ml.text = "스킬 분해\n\n분해 결과(스킬→재료 환원표)는 원작 서버데이터라\n유실되었습니다. 복원 전까지 미구현(TODO)."
	ml.add_theme_font_size_override("font_size", 18); ml.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ml.position = Vector2(30, 40); ml.size = Vector2(BW - 60, BH - 90); win.add_child(ml)
	var ok := Button.new(); ok.text = "확인"; ok.size = Vector2(150, 44); ok.position = Vector2((BW - 150) * 0.5, BH - 58)
	ok.pressed.connect(func(): layer.queue_free()); win.add_child(ok)

const LAB_SKILL_COST := 3000
func _open_lab_make_skill() -> void:
	var vis := _vis()
	var man := _load_manifest("common_ui")
	var layer := CanvasLayer.new(); layer.layer = 40; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.6); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	const BW := 440.0
	const BH := 300.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(280, 52); tbar.position = Vector2((BW - 280) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = "스킬 제작"
	tl.add_theme_font_size_override("font_size", 26); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 58, 14); xb.pressed.connect(func(): layer.queue_free()); win.add_child(xb)
	var bl := _atlas_sprite("common_ui", "common_backlight3", man, 0.7)
	if bl: bl.position = Vector2(BW * 0.5, 130); bl.modulate = Color(1, 1, 1, 0.3); win.add_child(bl)
	var ml := Label.new(); ml.text = "연구소에서 무작위 스킬 스크롤을 제작합니다."
	ml.add_theme_font_size_override("font_size", 19); ml.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; ml.position = Vector2(40, 96); ml.size = Vector2(BW - 80, 60); win.add_child(ml)
	var mk := Button.new(); mk.size = Vector2(180, 52); mk.position = Vector2((BW - 180) * 0.5, BH - 82); win.add_child(mk)
	var mc := _atlas_sprite("common_ui", "common_coin_small1", man, 0.9)
	if mc: mc.position = Vector2(BW * 0.5 - 60, BH - 56); win.add_child(mc)
	var mgl := Label.new(); mgl.text = "제작  %d" % LAB_SKILL_COST; mgl.add_theme_font_size_override("font_size", 20)
	mgl.add_theme_color_override("font_color", Color.WHITE); mgl.position = Vector2(BW * 0.5 - 34, BH - 68); mgl.size = Vector2(140, 28); win.add_child(mgl)
	mk.pressed.connect(func():
		if not UserDB.spend("gold", LAB_SKILL_COST):
			return
		var names: Array = []
		for sv in Data.skills.values():
			if sv is Dictionary and sv.has("name"): names.append(String(sv["name"]))
		var made := "무작위 스킬"
		if not names.is_empty():
			var r := RandomNumberGenerator.new(); r.randomize()
			made = String(names[r.randi() % names.size()])
		var got: Array = UserDB.get_pmeta("made_skills", [])
		got.append(made); UserDB.set_pmeta("made_skills", got)
		layer.queue_free()
		_open_lab_result(made))

func _open_lab_result(skill_name: String) -> void:
	Bgm.sfx("effect_equip_success")
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 42; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	const BW := 420.0
	const BH := 240.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(260, 50); tbar.position = Vector2((BW - 260) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = "제작 완료"; tl.add_theme_font_size_override("font_size", 24)
	tl.add_theme_color_override("font_color", Color.WHITE); tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; tl.size = tbar.size; tbar.add_child(tl)
	var ml := Label.new(); ml.text = "[%s] 스킬 스크롤을 제작했습니다!" % skill_name
	ml.add_theme_font_size_override("font_size", 20); ml.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ml.position = Vector2(30, 80); ml.size = Vector2(BW - 60, 70); win.add_child(ml)
	var ok := Button.new(); ok.text = "확인"; ok.size = Vector2(150, 44); ok.position = Vector2((BW - 150) * 0.5, BH - 58)
	ok.pressed.connect(func(): layer.queue_free()); win.add_child(ok)

func _build_hud(area: Dictionary) -> void:
	var hud := CanvasLayer.new()
	hud.layer = 10
	add_child(hud)
	_refresh_hud()
	var title := Label.new()
	title.text = String(area.get("title", ""))
	title.position = Vector2(22, FLOOR - 40.0)
	title.add_theme_font_size_override("font_size", 22)
	hud.add_child(title)
	_build_tips(hud)

const _TIPS := [
	"드래곤은 '출전' 버튼으로 3마리까지 편성할 수 있어요.",
	"속성 상성을 이용하면 전투가 훨씬 쉬워져요. (강함 ×1.25)",
	"둥지에서 먹이를 주면 경험치와 애정이 올라요.",
	"잠재능력은 재설정으로 더 높은 등급을 노릴 수 있어요.",
	"#aeed784a",
	"각성한 드래곤은 레벨 상한이 50까지 올라가요.",
	"젬과 장신구로 드래곤을 더 강하게 만들 수 있어요.",
]
var _tip_label: Label
var _tip_idx := 0
func _build_tips(hud: CanvasLayer) -> void:
	var vis := _vis()
	var bubble := NinePatchRect.new()
	bubble.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box2.tres")
	bubble.patch_margin_left = 14; bubble.patch_margin_top = 14; bubble.patch_margin_right = 14; bubble.patch_margin_bottom = 14
	bubble.size = Vector2(560, 44); bubble.position = Vector2(vis.x * 0.5 - 280, FLOOR - 54)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bubble)
	var icon := Label.new(); icon.text = "TIP"; icon.add_theme_font_size_override("font_size", 16)
	icon.add_theme_color_override("font_color", Color(1, 0.85, 0.4)); icon.position = Vector2(14, 10); bubble.add_child(icon)
	_tip_label = Label.new()
	_tip_label.add_theme_font_size_override("font_size", 15); _tip_label.add_theme_color_override("font_color", Color(1, 0.97, 0.85))
	_tip_label.position = Vector2(56, 10); _tip_label.size = Vector2(494, 22); bubble.add_child(_tip_label)
	_tip_idx = randi() % _TIPS.size()
	_show_tip()
	var timer := Timer.new(); timer.wait_time = 5.0; timer.autostart = true
	timer.timeout.connect(func(): _tip_idx = (_tip_idx + 1) % _TIPS.size(); _show_tip())
	bubble.add_child(timer)

func _show_tip() -> void:
	if not is_instance_valid(_tip_label): return
	_tip_label.text = _TIPS[_tip_idx]
	_tip_label.modulate.a = 0.0
	_tip_label.create_tween().tween_property(_tip_label, "modulate:a", 1.0, 0.4)

const _QUESTS := [
	{"npc": "yuria",    "icon": "yulia",    "key": "battles",  "label": "전투 승리",   "goal": 3, "lv": 5},
	{"npc": "kanggalo", "icon": "kanggalo", "key": "hatches",  "label": "알 부화",     "goal": 1},
	{"npc": "pino",     "icon": "pino",     "key": "feeds",    "label": "먹이 주기", "goal": 3},
	{"npc": "romini",   "icon": "romini",   "key": "levelups", "label": "레벨업", "goal": 1},
	{"npc": "nuri",     "icon": "nuri",     "key": "buys",     "label": "상점 구매", "goal": 1},
	{"npc": "raon",     "icon": "raon",     "key": "talks",    "label": "주민과 대화", "goal": 3},
]
const _QUEST_TOTAL_KEY := "town_total"

const _Q_TITLE := "#8ebbf2d8"
const _Q_COMMENT := "오늘 하루!! 당신이 진정한 테이머라면\n도움이 필요한 엘피스 마을 주민들을 도와주세요!!"
const _Q_COUNT := "해결한 미션 : %d/%d"

func _quest_done(qd: Dictionary) -> bool:
	return UserDB.quest_claimed(String(qd["key"]))

func _quest_cleared_count() -> int:
	var n := 0
	for qd in _QUESTS:
		if _quest_done(qd):
			n += 1
	return n

var _bmf_cache: Dictionary = {}
func _bmfont(name: String) -> Font:
	if _bmf_cache.has(name):
		return _bmf_cache[name]
	var p := "res://assets/converted/font_ui/%s.fnt" % name
	if not ResourceLoader.exists(p):
		return null
	var f := (load(p) as FontFile)
	if f != null:
		f = f.duplicate() as FontFile
		f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	_bmf_cache[name] = f
	return f

func _q_label(text: String, font: String, size: int, color: Color, center: Vector2,
		dim: Vector2, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	var f := _bmfont(font)
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size = dim
	l.position = center - dim * 0.5
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _rounded_button(text: String, center: Vector2, enabled: bool) -> Button:
	var b := Button.new()
	b.size = Vector2(220.0, 56.0)
	b.position = center - b.size * 0.5
	b.text = text
	b.disabled = not enabled
	var f := _bmfont("font_subtitle")
	if f != null:
		b.add_theme_font_override("font", f)
	b.add_theme_font_size_override("font_size", 20)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.36, 0.22, 0.09) if enabled else Color(0.45, 0.42, 0.38)
		if st == "hover":
			sb.bg_color = Color(0.46, 0.30, 0.13)
		elif st == "pressed":
			sb.bg_color = Color(0.28, 0.16, 0.06)
		sb.set_corner_radius_all(28)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.86, 0.72, 0.42, 0.9 if enabled else 0.4)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color(1, 0.95, 0.82))
	b.add_theme_color_override("font_disabled_color", Color(0.85, 0.83, 0.80, 0.7))
	return b

func _open_quests() -> void:
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var cm := _load_manifest("common_ui")
	var nm := _load_manifest("npc_icon")
	var wm := _load_manifest("worldmap_ui")
	var overlay := CanvasLayer.new(); overlay.layer = 30; add_child(overlay)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			overlay.queue_free())
	overlay.add_child(dim)

	const CW := 630.0
	const CH := 600.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190
	win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(CW, CH)
	win.position = Vector2(round(vis.x * 0.5 - CW * 0.5), round(vis.y * 0.5 - CH * 0.5))
	overlay.add_child(win)

	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20
	tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(CW * 0.9, 56.0)
	tbar.position = Vector2((CW - tbar.size.x) * 0.5, 50.0 - tbar.size.y * 0.5)
	win.add_child(tbar)
	win.add_child(_q_label(Data.ui(_Q_TITLE), "font_subtitle", 24, Color.WHITE,
		Vector2(CW * 0.5, 50.0), Vector2(tbar.size.x, 40.0)))

	var cmt := _q_label(_Q_COMMENT, "font_common", 17, Color8(130, 0, 0),
		Vector2(CW * 0.5, 120.0), Vector2(CW - 60.0, 56.0))
	win.add_child(cmt)

	for i in _QUESTS.size():
		var qd: Dictionary = _QUESTS[i]
		var col := i % 3
		var row := i / 3
		var c := Vector2(CW * 0.5 - 155.0 + col * 155.0, CH - (CH * 0.5 + 55.0) + row * 120.0)
		var done := _quest_done(qd)
		if done:
			var bl := _atlas_sprite("common_ui", "common_backlight3", cm, S * 0.4)
			if bl != null:
				bl.position = c
				win.add_child(bl)
				var rt := bl.create_tween().set_loops()
				rt.tween_property(bl, "rotation", -TAU, 36.0).from(0.0)
		var ic := _atlas_sprite("npc_icon", "npc_icon_icon_%s" % String(qd["icon"]), nm, S)
		if ic != null:
			ic.position = c
			if not done:
				ic.modulate = Color8(100, 100, 120)
			win.add_child(ic)
			var pf := _atlas_sprite("npc_icon", "npc_icon_profile_layer", nm, S)
			if pf != null:
				pf.position = c
				win.add_child(pf)
		if done:
			var mk := _atlas_sprite("common_ui", "common_clear_mark_kr", cm, S * 0.7)
			if mk != null:
				mk.position = c + Vector2(30.0, 30.0)
				mk.z_index = 3
				win.add_child(mk)
		var cap_w := 100.0
		var plate := Panel.new()
		var psb := StyleBoxFlat.new()
		psb.bg_color = Color(0, 0, 0, 0.55)
		plate.add_theme_stylebox_override("panel", psb)
		plate.size = Vector2(cap_w, 18.0)
		plate.position = c + Vector2(-cap_w * 0.5, -48.0)
		plate.z_index = 4
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		win.add_child(plate)
		var qkey := String(qd["key"])
		var st := ""
		if done:
			st = "완료"
		elif UserDB.quest_gaveup(qkey):
			st = "포기"
		elif not UserDB.quest_accepted(qkey):
			st = "미수락"
		else:
			st = "%d/%d" % [mini(UserDB.quest_progress(qkey), int(qd["goal"])), int(qd["goal"])]
		var cap := _q_label("%s %s" % [String(qd["label"]), st], "font_common", 12,
			Color(1, 0.95, 0.85) if done else Color(0.85, 0.84, 0.82),
			c + Vector2(0.0, -39.0), Vector2(cap_w, 18.0))
		cap.z_index = 5
		win.add_child(cap)

	var line := _atlas_sprite("worldmap_ui", "scene_worldmap_certificate_popup_line", wm, S * 1.2)
	if line != null:
		line.position = Vector2(CW * 0.5, CH - (CH * 0.5 - 130.0))
		win.add_child(line)

	var cleared := _quest_cleared_count()
	win.add_child(_q_label(_Q_COUNT % [cleared, _QUESTS.size()], "font_subtitle", 20,
		Color8(60, 40, 15), Vector2(CW * 0.5, CH - (CH * 0.5 - 150.0) + 12.0),
		Vector2(CW - 80.0, 28.0)))

	var all_done := cleared >= _QUESTS.size()
	var claimed := UserDB.quest_claimed(_QUEST_TOTAL_KEY)
	var reward := _rounded_button("보상 받기", Vector2(CW * 0.5 - 123.0, CH - 70.0),
		all_done and not claimed)
	reward.pressed.connect(func():
		if not (all_done and not UserDB.quest_claimed(_QUEST_TOTAL_KEY)):
			return
		UserDB.claim_quest(_QUEST_TOTAL_KEY)
		var total_pick := DailyQuest.roll_and_grant()
		overlay.queue_free()
		_refresh_hud()
		_open_town_reward(total_pick))
	win.add_child(reward)
	var cancel := _rounded_button("취소", Vector2(CW * 0.5 + 123.0, CH - 70.0), true)
	cancel.pressed.connect(func(): overlay.queue_free())
	win.add_child(cancel)

	if _raon_target() >= 0:
		_build_raon_call(win, Vector2(-58.0, 300.0),
			func(): overlay.queue_free(); _open_raon_help())

const RAON_HIT := Vector2(100.0, 150.0)
const RAON_SD_SCALE := 0.65
const RAON_BOB := [10.0, -10.0, 7.0, -7.0, 3.0, -3.0]
const RAON_BOB_T := 0.8
func _build_raon_call(parent: Node, center: Vector2, on_click: Callable) -> Control:
	var hit := Button.new()
	hit.flat = true
	hit.size = RAON_HIT
	hit.position = center - RAON_HIT * 0.5
	hit.name = "RaonCallButton"
	hit.pressed.connect(on_click)
	parent.add_child(hit)
	var sd := Node2D.new()
	sd.position = Vector2(RAON_HIT.x * 0.5, RAON_HIT.y)
	hit.add_child(sd)
	var sh := _atlas_sprite("common_ui", "common_shadow", _load_manifest("common_ui"),
		0.75 * Design.ASSET_SCALE)
	if sh.texture != null:
		sh.modulate.a = 200.0 / 255.0
		sh.z_index = -1
		sd.add_child(sh)
	if ResourceLoader.exists("res://scenes/npc_town/sd_raon.tscn"):
		var ri := (load("res://scenes/npc_town/sd_raon.tscn") as PackedScene).instantiate() as Node2D
		ri.scale = Vector2(RAON_SD_SCALE, RAON_SD_SCALE)
		sd.add_child(ri)
		var ap := ri.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap != null and ap.has_animation("quest_start") and ap.has_animation("wait"):
			var at := ri.create_tween().set_loops()
			at.tween_callback(func(): ap.play("quest_start"))
			at.tween_interval(ap.get_animation("quest_start").length)
			at.tween_callback(func(): ap.play("wait"))
			at.tween_interval(ap.get_animation("wait").length)
	var bal := _balloon_static(Data.ui(_RAON_TITLE), Data.ui(_RAON_MSG), 150.0)
	bal.position = Vector2(RAON_HIT.x * 0.5, -40.0)
	hit.add_child(bal)
	var y := bal.position.y
	var bt := bal.create_tween().set_loops()
	for dy: float in RAON_BOB:
		y += dy
		var step := bt.tween_property(bal, "position:y", y, RAON_BOB_T)
		step.set_trans(Tween.TRANS_EXPO if dy > 0.0 else Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	bt.tween_interval(RAON_BOB_T)
	bal.create_tween().tween_property(bal, "scale", bal.scale + Vector2(0.05, 0.05), RAON_BOB_T)
	return hit

func _balloon_static(who: String, line: String, wrap_w: float) -> Node2D:
	var root := Node2D.new()
	root.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	var pad := 14.0
	var lbl := Label.new()
	lbl.text = line
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.16, 0.12, 0.09))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var fnt := lbl.get_theme_font("font")
	if fnt == null:
		fnt = ThemeDB.fallback_font
	var th := fnt.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_CENTER, wrap_w, 15).y \
		if fnt != null else 20.0
	var nm: Label = null
	var nh := 0.0
	if who != "":
		nm = Label.new()
		nm.text = who
		nm.add_theme_font_size_override("font_size", 14)
		nm.add_theme_color_override("font_color", Color(0.85, 0.45, 0.15))
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nh = (fnt.get_string_size(who, HORIZONTAL_ALIGNMENT_CENTER, -1, 14).y if fnt != null else 18.0) + 3.0
	var w := wrap_w + pad * 2
	var h := th + nh + pad * 2
	var body := NinePatchRect.new()
	var tex := _atlas_tex("town_elpis", "scene_town_elpis_txt_balloon2")
	if tex != null:
		body.texture = tex
		body.patch_margin_left = int(BALLOON_CAP.position.x)
		body.patch_margin_top = int(BALLOON_CAP.position.y)
		body.patch_margin_right = int(BALLOON_CAP.size.x)
		body.patch_margin_bottom = int(BALLOON_CAP.size.y)
	body.size = Vector2(w, h)
	body.position = Vector2(-w * 0.5, -h)
	root.add_child(body)
	var y := pad
	if nm != null:
		nm.position = Vector2(pad, y); nm.size = Vector2(w - pad * 2, nh)
		body.add_child(nm); y += nh
	lbl.position = Vector2(pad, y); lbl.size = Vector2(w - pad * 2, th)
	body.add_child(lbl)
	var tail := _atlas_sprite("town_elpis", "scene_town_elpis_txt_balloon_bot", _manifest, 1.0)
	if tail.texture != null:
		tail.position = Vector2(0, float(_manifest.get("scene_town_elpis_txt_balloon_bot", {}).get("h", 10)) * 0.5)
		root.add_child(tail)
	return root

const _RAON_PRICE := [3, 3, 5, 5, 7, 7]
const _RAON_CNT_KEY := "dia_clear"
const _RAON_TITLE := "#fac99ec9"
const _RAON_MSG := "#4fd6aa54"
const _RAON_HELP := [
	"#81fe91fb",
	"#5f0af4f4",
	"#42e5a93e",
	"#ed1f1a5f",
	"#b14683e5",
]
const _RAON_CLEAR := [
	"#89fe4f96",
	"#4a22e99b",
	"#285df5c4",
	"#7d37bfa8",
]
const _RAON_CANCEL := [
	"#81eb66ec",
	"#f567d33c",
]

func _raon_price() -> int:
	var cnt := UserDB.quest_count(_RAON_CNT_KEY)
	return _RAON_PRICE[cnt] if cnt < _RAON_PRICE.size() else 3

func _raon_target() -> int:
	for i in _QUESTS.size():
		if String((_QUESTS[i] as Dictionary)["npc"]) == "raon":
			continue
		if _npc_quest_state(i) in ["progress", "reward"]:
			return i
	return -1

func _npc_display_name(npc_id: String) -> String:
	var db: Dictionary = Data.npc_lines() if Data.has_method("npc_lines") else {}
	return String((db.get(npc_id, {}) as Dictionary).get("name", npc_id))

const RAON_TALK_BODY := 1
const RAON_TALK_EMOTION := 1
const RAON_TALK_POS := NpcDialogue.POS_RIGHT
func _raon_talk(text: String, on_end: Callable) -> void:
	var tl := NpcDialogue.open(self, "raon", _npc_display_name("raon"), text,
		RAON_TALK_EMOTION, RAON_TALK_BODY, RAON_TALK_POS)
	tl.advanced.connect(func():
		tl.close()
		on_end.call())

func _open_raon_help() -> void:
	var idx := _raon_target()
	if idx < 0:
		return
	var qd: Dictionary = _QUESTS[idx]
	var cnt := UserDB.quest_count(_RAON_CNT_KEY)
	var say := (Data.ui(_RAON_HELP[0]) % _npc_display_name(String(qd["npc"]))) if cnt == 0 \
		else Data.ui(_RAON_HELP[mini(cnt, _RAON_HELP.size() - 1)])
	_raon_talk(say, func(): _open_raon_confirm(idx))

const RAON_POP := Vector2(570.0, 420.0)
const _RAON_POP_TITLE := "#76b724a1"
const _RAON_POP_MSG := "다이아를 사용하여 라온에게\n미션을 대신 해달라고 부탁하겠습니까?"
func _open_raon_confirm(idx: int) -> void:
	var qd: Dictionary = _QUESTS[idx]
	var price := _raon_price()
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var cm := _load_manifest("common_ui")
	var layer := CanvasLayer.new(); layer.layer = 45; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var BW := RAON_POP.x
	var BH := RAON_POP.y
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190
	win.patch_margin_right = 40; win.patch_margin_bottom = 58
	win.size = Vector2(BW, BH)
	var home := Vector2(round(vis.x * 0.5 - BW * 0.5), round(vis.y * 0.5 - BH * 0.5))
	win.position = home
	layer.add_child(win)
	win.position.y = home.y - vis.y
	win.create_tween().tween_property(win, "position:y", home.y, 0.5) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	var slide_out := func(after: Callable) -> void:
		var tw := win.create_tween()
		tw.tween_property(win, "position:y", home.y - vis.y, 0.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			layer.queue_free()
			after.call())

	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20
	tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(BW * 0.9, 52.0)
	tbar.position = Vector2((BW - tbar.size.x) * 0.5, 40.0 - tbar.size.y * 0.5)
	win.add_child(tbar)
	win.add_child(_q_label(Data.ui(_RAON_POP_TITLE), "font_subtitle", 22, Color.WHITE,
		Vector2(BW * 0.5, 40.0), Vector2(tbar.size.x, 36.0)))

	var msg := _q_label(_RAON_POP_MSG, "font_subtitle", 18, Color8(255, 245, 225),
		Vector2(BW * 0.5, BH - (BH * 0.5 + 40.0)), Vector2(BW - 80.0, 64.0))
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	win.add_child(msg)
	win.add_child(_q_label("[%s]" % String(qd["label"]), "font_common", 15,
		Color8(190, 170, 140), Vector2(BW * 0.5, BH - (BH * 0.5 - 4.0)), Vector2(BW - 80.0, 24.0)))

	var pay_y := BH - (BH * 0.5 - 60.0)
	var dia := _atlas_sprite("common_ui", "common_diamond_big", cm, S * 0.9)
	if dia.texture != null:
		dia.centered = false
		dia.offset.y = -float(cm.get("common_diamond_big", {}).get("h", 40)) * 0.5
		dia.position = Vector2(BW * 0.5 - 45.0, pay_y)
		win.add_child(dia)
	win.add_child(_q_label("X%d" % price, "font_subtitle", 22,
		Color.WHITE if UserDB.diamond() >= price else Color8(200, 60, 60),
		Vector2(BW * 0.5 + 5.0 + 45.0, pay_y), Vector2(90.0, 30.0), HORIZONTAL_ALIGNMENT_LEFT))

	var by := BH - BH * 0.15
	var ok := _rounded_button("확인", Vector2(BW * 0.5 - 120.0, by), true)
	var no := _rounded_button("취소", Vector2(BW * 0.5 + 120.0, by), true)
	for b: Button in [ok, no]:
		b.size = Vector2(220.0, 56.0)
		b.position = Vector2(BW * 0.5 + (-120.0 if b == ok else 120.0), by) - b.size * 0.5
		win.add_child(b)
	no.pressed.connect(func(): slide_out.call(func():
		_raon_talk(Data.ui(_RAON_CANCEL[randi() % _RAON_CANCEL.size()]), func(): pass)))
	ok.pressed.connect(func(): slide_out.call(func():
		if not UserDB.spend("diamond", price):
			_open_annonce(Data.ui("#76cd9cb3"))
			return
		UserDB.fill_quest(String(qd["key"]), int(qd["goal"]))
		UserDB.bump_quest(_RAON_CNT_KEY)
		_refresh_quest_marks()
		_refresh_hud()
		_raon_talk(Data.ui(_RAON_CLEAR[randi() % _RAON_CLEAR.size()]), func(): pass)))

func _quest_doc() -> Dictionary:
	var doc: Dictionary = Data.npc_lines_doc if "npc_lines_doc" in Data else {}
	return doc.get("town_quest", {})

func _quest_lines(npc_id: String) -> Dictionary:
	return (_quest_doc().get("npcs", {}) as Dictionary).get(npc_id, {})

func _quest_misc(key: String, fallback: String) -> String:
	return String((_quest_doc().get("misc", {}) as Dictionary).get(key, fallback))

func _quest_say(npc_id: String, kind: String) -> String:
	var arr: Array = _quest_lines(npc_id).get(kind, [])
	return String(arr[randi() % arr.size()]) if not arr.is_empty() else ""

func _npc_quest_talk(npc_id: String, qi: int, _rec: Dictionary, who: String) -> bool:
	var qd: Dictionary = _QUESTS[qi]
	var key := String(qd["key"])
	var st := _npc_quest_state(qi)
	if st == "":
		return false
	var tl := NpcDialogue.open(self, npc_id, who, "")
	match st:
		"reward":
			tl.set_text(_quest_say(npc_id, "clear"))
			tl.advanced.connect(func():
				tl.close()
				UserDB.claim_quest(key)
				var pick := DailyQuest.roll_and_grant()
				_refresh_quest_marks()
				_refresh_hud()
				_open_town_reward(pick))
		"offer":
			tl.set_text(_quest_say(npc_id, "offer"))
			tl.set_choices(["수락", "거절"])
			tl.chosen.connect(func(idx: int):
				tl.clear_choices()
				if idx == 0:
					var need := int(qd.get("lv", 0))
					var a := UserDB.active_dragon()
					if need > 0 and (a.is_empty() or int(a.get("level", 1)) < need):
						tl.close()
						_open_annonce(_quest_misc("level",
							Data.ui("#b962780e")))
						return
					UserDB.accept_quest(key)
					tl.set_text(_quest_say(npc_id, "ok"))
				else:
					UserDB.giveup_quest(key)
					tl.set_text(_quest_say(npc_id, "cancel"))
				_refresh_quest_marks()
				_refresh_hud())
			tl.advanced.connect(func(): tl.close())
		"progress":
			tl.set_text("%s  (%d/%d)" % [String(qd["label"]),
				UserDB.quest_progress(key), int(qd["goal"])])
			tl.set_choices(["포기하기", "계속하기"])
			tl.chosen.connect(func(idx: int):
				tl.close()
				if idx == 0:
					_open_giveup_confirm(key))
			tl.advanced.connect(func(): tl.close())
	return true

func _open_annonce(msg: String) -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 46; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT); layer.add_child(dim)
	const BW := 480.0
	const BH := 230.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190
	win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH)
	win.position = Vector2(round(vis.x * 0.5 - BW * 0.5), round(vis.y * 0.5 - BH * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20
	tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(BW * 0.8, 50.0)
	tbar.position = Vector2((BW - tbar.size.x) * 0.5, 38.0 - tbar.size.y * 0.5)
	win.add_child(tbar)
	win.add_child(_q_label(_quest_misc("annonce", "알림"), "font_subtitle", 21, Color.WHITE,
		Vector2(BW * 0.5, 38.0), Vector2(tbar.size.x, 34.0)))
	var m := _q_label(msg, "font_common", 16, Color8(90, 60, 25),
		Vector2(BW * 0.5, 118.0), Vector2(BW - 70.0, 60.0))
	m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	win.add_child(m)
	var ok := _rounded_button("확인", Vector2(BW * 0.5, BH - 48.0), true)
	ok.pressed.connect(func(): layer.queue_free())
	win.add_child(ok)

func _open_giveup_confirm(key: String) -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 46; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT); layer.add_child(dim)
	const BW := 520.0
	const BH := 250.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190
	win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH)
	win.position = Vector2(round(vis.x * 0.5 - BW * 0.5), round(vis.y * 0.5 - BH * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20
	tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(BW * 0.8, 50.0)
	tbar.position = Vector2((BW - tbar.size.x) * 0.5, 38.0 - tbar.size.y * 0.5)
	win.add_child(tbar)
	win.add_child(_q_label(_quest_misc("annonce", "알림"), "font_subtitle", 21, Color.WHITE,
		Vector2(BW * 0.5, 38.0), Vector2(tbar.size.x, 34.0)))
	var m := _q_label(_quest_misc("giveup", "현재 진행중인 퀘스트를 포기하시겠습니까?"),
		"font_common", 16, Color8(90, 60, 25), Vector2(BW * 0.5, 122.0), Vector2(BW - 70.0, 64.0))
	m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	win.add_child(m)
	var ok := _rounded_button("확인", Vector2(BW * 0.5 - 118.0, BH - 48.0), true)
	ok.pressed.connect(func():
		UserDB.giveup_quest(key)
		layer.queue_free()
		_refresh_quest_marks()
		_refresh_hud())
	win.add_child(ok)
	var no := _rounded_button("취소", Vector2(BW * 0.5 + 118.0, BH - 48.0), true)
	no.pressed.connect(func(): layer.queue_free())
	win.add_child(no)

func _open_town_reward(pick: Dictionary) -> void:
	Bgm.sfx("effect_equip_success")
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 40; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	const BW := 550.0
	const BH := 490.0
	var cx := vis.x * 0.5
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 40; win.patch_margin_bottom = 58
	win.size = Vector2(BW, BH); win.position = Vector2(round(cx - BW * 0.5), round(vis.y * 0.5 - BH * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(300, 52); tbar.position = Vector2((BW - 300) * 0.5, 50.0 - 26.0); win.add_child(tbar)
	var title := Label.new(); title.text = "보상 획득"
	title.add_theme_font_size_override("font_size", 28); title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size = tbar.size; tbar.add_child(title)

	var slot := Vector2(BW * 0.5, BH - (BH * 0.5 + 80.0))
	var cm := _load_manifest("common_ui")
	var S := Design.ASSET_SCALE
	var bl := _atlas_sprite("common_ui", "common_backlight3", cm, 0.5 * S)
	if bl != null:
		bl.position = slot
		bl.modulate = Color(1, 1, 1, 0)
		win.add_child(bl)
		var tw := bl.create_tween().set_parallel(true)
		tw.tween_property(bl, "scale", Vector2(0.4 * S, 0.4 * S), 0.25)
		tw.tween_property(bl, "modulate:a", 1.0, 0.25)
		tw.tween_property(bl, "rotation", -PI, 0.5)
	var kind := String(pick.get("kind", "currency"))
	var pkey := String(pick.get("key", "gold"))
	var icon_key := ""
	if kind == "currency":
		icon_key = "common_ui/common_diamond_small1" if pkey == "diamond" else "common_ui/common_coin_small1"
	else:
		icon_key = String((Data.items.get(pkey, {}) as Dictionary).get("icon", ""))
	if not icon_key.is_empty():
		var dir := icon_key.get_slice("/", 0)
		var frame := icon_key.get_slice("/", 1)
		var ico := _atlas_sprite(dir, frame, _load_manifest(dir), 1.0)
		if ico != null:
			var th := float(ico.texture.get_height()) if ico.texture != null else 0.0
			if th > 0.0:
				ico.scale = Vector2.ONE * clampf(56.0 / th, 0.8, 2.4)
			ico.position = slot
			win.add_child(ico)
	win.add_child(_q_label(DailyQuest.describe(pick), "font_common", 22,
		Color(0.3, 0.2, 0.05), slot + Vector2(0.0, 60.0), Vector2(340.0, 30.0)))
	var msg := RichTextLabel.new()
	msg.bbcode_enabled = true
	msg.text = "[center]퀘스트 보상으로 [color=#d11b00]%s[/color]\n아이템을 획득하였습니다.[/center]" \
		% DailyQuest.display_name(pick)
	var mf := _bmfont("font_common")
	if mf != null:
		msg.add_theme_font_override("normal_font", mf)
	msg.add_theme_font_size_override("normal_font_size", 21)
	msg.add_theme_color_override("default_color", Color(0.28, 0.19, 0.05))
	msg.fit_content = true; msg.scroll_active = false
	msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	msg.position = Vector2(BW * 0.5 - 220.0, BH - (BH * 0.5 - 20.0)); msg.size = Vector2(440.0, 80.0)
	win.add_child(msg)
	var ok := Button.new(); ok.text = "확인"; ok.size = Vector2(160, 46)
	ok.position = Vector2((BW - 160) * 0.5, BH - (46.0 * 0.5 + 40.0) - 23.0)
	ok.pressed.connect(func():
		if is_instance_valid(layer): layer.queue_free()
		_open_quests())
	win.add_child(ok)

func _resolve_night(params: Dictionary) -> bool:
	if params.has("night"):
		return bool(params.get("night"))
	return bool(UserDB.get_pmeta("yutakan_night", false))

var _toast_lbl: Label

func _toast(text: String) -> void:
	Toast.show(self, text)

const _CLOCK_HL := Color8(0x46, 0x41, 0xD9)

func _open_daynight_confirm() -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 40; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	const BW := 480.0
	const BH := 300.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round(vis.x * 0.5 - BW * 0.5), round(vis.y * 0.5 - BH * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(300, 52); tbar.position = Vector2((BW - 300) * 0.5, 12); win.add_child(tbar)
	var title := Label.new(); title.text = Data.ui("#e0cdf595")
	title.add_theme_font_size_override("font_size", 26); title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size = tbar.size; tbar.add_child(title)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 58, 14)
	xb.pressed.connect(func(): if is_instance_valid(layer): layer.queue_free()); win.add_child(xb)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	var cur := "밤" if _night else "낮"
	var nxt := "낮" if _night else "밤"
	body.text = ("[center]현재 유타칸은 [color=#%s]%s[/color]입니다.

"
		+ "[color=#%s]%s[/color]으로 바꾸시겠습니까?[/center]") % [
		_CLOCK_HL.to_html(false), cur, _CLOCK_HL.to_html(false), nxt]
	body.add_theme_font_size_override("normal_font_size", 21)
	body.add_theme_color_override("default_color", Color(0.28, 0.19, 0.05))
	body.fit_content = true; body.scroll_active = false
	body.position = Vector2(40, 92); body.size = Vector2(BW - 80, 110)
	win.add_child(body)
	var ok := Button.new(); ok.text = "확인"; ok.size = Vector2(150, 46)
	ok.position = Vector2(BW * 0.5 - 160, BH - 66)
	ok.pressed.connect(func():
		if is_instance_valid(layer): layer.queue_free()
		_toggle_night()
		_toast("유타칸 대륙이 " + ("어두워졌습니다." if _night else "밝아졌습니다.")))
	win.add_child(ok)
	var no := Button.new(); no.text = "취소"; no.size = Vector2(150, 46)
	no.position = Vector2(BW * 0.5 + 10, BH - 66)
	no.pressed.connect(func(): if is_instance_valid(layer): layer.queue_free())
	win.add_child(no)

func _toggle_night() -> void:
	_night = not _night
	UserDB.set_pmeta("yutakan_night", _night)
	_rebuild()

const _TOWN_REGION := {"elpis": "yutakan", "dwarf": "dwarf"}
func _on_worldmap() -> void:
	if Scenes.REGISTRY.has("worldmap"):
		Scenes.goto("worldmap", {"region": String(_TOWN_REGION.get(_area_id, "yutakan"))})
	else:
		push_warning("[Town] worldmap 미구현 — Phase 2에서 연결")

func _vis() -> Vector2:
	return get_viewport_rect().size

func _load_manifest(dir: String) -> Dictionary:
	return AtlasUI.manifest(dir)

func _atlas_tex(dir: String, name: String) -> Texture2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	return load(p) if ResourceLoader.exists(p) else null

func _atlas_sprite(dir: String, name: String, man: Dictionary, scale := 1.0) -> Sprite2D:
	var s := Sprite2D.new()
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if ResourceLoader.exists(p):
		s.texture = load(p)
	s.material = _pma
	s.scale = Vector2(scale, scale)
	return s
