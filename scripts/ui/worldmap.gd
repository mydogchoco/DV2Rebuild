extends Control

const FLOOR := 692.0

const WORLDMAP_LABEL_COLORS := [
	Color8(116, 206, 44),
	Color8(42, 152, 213),
	Color8(255, 198, 60),
	Color8(165, 0, 85),
	Color8(86, 66, 61),
	Color8(112, 69, 161),
]

func worldmap_label_color(index: int) -> Color:
	if index >= 1 and index <= WORLDMAP_LABEL_COLORS.size():
		return WORLDMAP_LABEL_COLORS[index - 1]
	return Color.WHITE

var _pma: CanvasItemMaterial
var _manifest: Dictionary = {}
var _mode := "overview"
var _params: Dictionary = {}
var _content: Node2D
var _scroll := 0.0
var _horizontal := false
var _max_scroll := 0.0
var _dragging := false
var _scroll_vel := 0.0
var _press_pos := Vector2.ZERO
var _moved := false
var _busy := false
var _hits: Array = []
var _clouds: Array = []

func enter(params: Dictionary = {}) -> void:
	_params = params
	_mode = params.get("region", "overview")
	if _pma != null:
		_rebuild()

func _region_bgm(region_id: String) -> String:
	if region_id == "yutakan" and _is_kades_space(_region("yutakan").get("native", {})):
		var kb := String(Data.kades.get("bgm_worldmap", ""))
		if kb != "":
			return kb
	if region_id != "" and region_id != "overview":
		for r in Data.worldmap_regions():
			if String(r.get("id", "")) == region_id:
				var b := String(r.get("bgm", ""))
				if b != "": return b
	return "bg_yutakan"

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_manifest = _load_manifest("worldmap_maps")
	_rebuild()
	_launch_scenario_if_available()

func _launch_scenario_if_available() -> void:
	if _mode != "overview" and _mode != "":
		return
	var dr := UserDB.active_dragon()
	if dr.is_empty() or int(dr.get("level", 0)) <= 0:
		return
	var ep := StoryProgress.next_episode()
	if ep <= 0 or StoryProgress.seen(ep) or not StoryProgress.unlocked(ep):
		return
	if StoryProgress.pending_episode() > 0:
		return
	var mark := StoryProgress.mark_field()
	if mark > 0 and mark != 999:
		return
	if StoryProgress.mark_pending_phase() != "":
		return
	if Data.scenario_flow_of(ep).is_empty():
		return
	Scenes.goto("story", {"no": ep, "part": 0, "back": "worldmap",
		"back_params": {"region": _mode}})

func _rebuild() -> void:
	Bgm.play(_region_bgm(_mode))
	Bgm.area_clear()
	for c in get_children():
		c.queue_free()
	_hits.clear()
	_clouds.clear()
	var bg := ColorRect.new()
	bg.color = Color(1, 0, 1) if Engine.has_meta("wm_no_ocean") else Color(0.86, 0.78, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = _BACKDROP_Z - 100
	add_child(bg)

	_content = Node2D.new()
	add_child(_content)
	_horizontal = false
	_busy = false
	if _mode == "overview":
		_build_overview()
	else:
		_build_region(_mode)
	_scroll = 0.0
	_apply_scroll()
	_build_hud()
	if _imp_pending:
		_imp_pending = false
		_add_imp_shop()

var _guide_topic := 0
var _guide_page := 0
func _guide_map() -> Array:
	var groups := {}
	var d := DirAccess.open("res://assets/converted/guide_ui")
	if d:
		for f in d.get_files():
			if f.begins_with("guide_") and f.ends_with("_KR.jpg"):
				var parts := f.replace("_KR.jpg", "").split("_")
				if parts.size() >= 4:
					var key := "%s_%s" % [parts[1], parts[2]]
					if not groups.has(key): groups[key] = []
					groups[key].append(f)
	var out: Array = []
	for k in groups.keys():
		var arr: Array = groups[k]; arr.sort()
		out.append({"key": k, "pages": arr})
	out.sort_custom(func(a, b): return String(a["key"]) < String(b["key"]))
	return out

func _open_guide() -> void:
	var vis := _vis()
	var topics := _guide_map()
	if topics.is_empty():
		return
	_guide_topic = clampi(_guide_topic, 0, topics.size() - 1)
	var layer := CanvasLayer.new(); layer.layer = 46; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.7); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var BW := clampf(vis.x - 80.0, 800.0, 1180.0)
	var BH := clampf(vis.y - 56.0, 540.0, 680.0)
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(320, 54); tbar.position = Vector2((BW - 320) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = "게임 가이드"
	tl.add_theme_font_size_override("font_size", 28); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 66, 14); xb.pressed.connect(func(): layer.queue_free()); win.add_child(xb)
	var menu := VBoxContainer.new(); menu.position = Vector2(30, 88); menu.add_theme_constant_override("separation", 6)
	win.add_child(menu)
	for i in topics.size():
		var tb := Button.new(); tb.text = "가이드 %s" % String(topics[i]["key"]).replace("_", "-")
		tb.size = Vector2(170, 40); tb.custom_minimum_size = Vector2(170, 40)
		tb.add_theme_font_size_override("font_size", 16)
		if i == _guide_topic: tb.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		var idx := i
		tb.pressed.connect(func(): _guide_topic = idx; _guide_page = 0; layer.queue_free(); _open_guide())
		menu.add_child(tb)
	var pages: Array = topics[_guide_topic]["pages"]
	_guide_page = clampi(_guide_page, 0, pages.size() - 1)
	var p := "res://assets/converted/guide_ui/%s" % String(pages[_guide_page])
	if ResourceLoader.exists(p):
		var tr := TextureRect.new(); tr.texture = load(p)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.position = Vector2(220, 90); tr.size = Vector2(BW - 260, BH - 170)
		win.add_child(tr)
	var pg := Label.new(); pg.text = "%d / %d" % [_guide_page + 1, pages.size()]
	pg.add_theme_font_size_override("font_size", 18); pg.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	pg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; pg.position = Vector2(BW * 0.5, BH - 62); pg.size = Vector2(200, 26)
	win.add_child(pg)
	if _guide_page > 0:
		var pv := Button.new(); pv.text = "◀ 이전"; pv.size = Vector2(120, 42); pv.position = Vector2(240, BH - 66)
		pv.pressed.connect(func(): _guide_page -= 1; layer.queue_free(); _open_guide()); win.add_child(pv)
	if _guide_page < pages.size() - 1:
		var nx := Button.new(); nx.text = "다음 ▶"; nx.size = Vector2(120, 42); nx.position = Vector2(BW - 160, BH - 66)
		nx.pressed.connect(func(): _guide_page += 1; layer.queue_free(); _open_guide()); win.add_child(nx)

const _OV_W := 1408.0
const _OV_H := 890.0
const _OVERVIEW := [
	{"id": "elf", "island": "scene_worldmap_map_world_map_elf", "ic": [249, 297],
		"banner": "scene_worldmap_map_world_label_elf_kr", "bc": [360, 250]},
	{"id": "yutakan", "island": "scene_worldmap_map_world_map_yukatan", "ic": [458, 312],
		"banner": "scene_worldmap_map_world_label_yukatan_kr", "bc": [640, 280]},
	{"id": "dwarf", "island": "scene_worldmap_map_world_map_dwarf", "ic": [772, 258],
		"banner": "scene_worldmap_map_world_label_dwarf_kr", "bc": [880, 200]},
	{"id": "uno", "island": "scene_worldmap_map_world_map_uno", "ic": [1090, 226],
		"banner": "scene_worldmap_map_world_label_uno_kr", "bc": [1208, 194]},
]
const _OV_BANNER_LOCKED := "scene_worldmap_map_world_label_question"
func _build_overview() -> void:
	var vis := _vis()
	var S := vis.x / _OV_W
	var off := Vector2(0.0, (vis.y - _OV_H * S) * 0.5)
	var man := _load_manifest("worldmap_world")
	var conv := func(cx: float, cy: float) -> Vector2:
		return off + Vector2(cx * S, (_OV_H - cy) * S)
	var bgp := "res://assets/converted/worldmap_world/bg.jpg"
	if ResourceLoader.exists(bgp):
		var bg := Sprite2D.new()
		bg.texture = load(bgp)
		bg.centered = true
		var t: Texture2D = bg.texture
		var bs := maxf(_OV_W / float(t.get_width()), _OV_H / float(t.get_height())) * S
		bg.scale = Vector2(bs, bs)
		bg.position = conv.call(_OV_W * 0.5, _OV_H * 0.5)
		_content.add_child(bg)
	for r in _OVERVIEW:
		var locked := not bool(_region(String(r["id"])).get("unlocked", false))
		var ic: Array = r["ic"]
		var isl := _sprite_native(String(r["island"]), "worldmap_world", man, S)
		if isl:
			isl.position = conv.call(float(ic[0]), float(ic[1]))
			if locked:
				isl.modulate = Color(0.55, 0.55, 0.6, 1)
			_content.add_child(isl)
		var bc: Array = r["bc"]
		var bframe := _OV_BANNER_LOCKED if locked else String(r["banner"])
		var banner := _sprite_native(bframe, "worldmap_world", man, S)
		if banner:
			banner.position = conv.call(float(bc[0]), float(bc[1]))
			_content.add_child(banner)
		if not locked:
			var iw := float(man.get(String(r["island"]), {}).get("w", 160)) * S
			var ih := float(man.get(String(r["island"]), {}).get("h", 120)) * S
			var ip: Vector2 = conv.call(float(ic[0]), float(ic[1]))
			_add_hit(Rect2(ip.x - iw * 0.5, ip.y - ih * 0.5, iw, ih + 40 * S), "region", String(r["id"]))
	var title := _sprite_native("scene_worldmap_map_world_label_worldmap", "worldmap_world", man, S)
	if title:
		title.position = conv.call(_OV_W * 0.5, 790.0)
		_content.add_child(title)
	_horizontal = false
	_set_content_height(vis.y)

func _build_region(region_id: String) -> void:
	var region := _region(region_id)
	if region.has("native"):
		_build_region_native(region)
		return
	var nodes: Array = region.get("nodes", [])
	if not nodes.is_empty() and nodes[0].has("pos"):
		_build_region_map(region, nodes)
	else:
		_build_region_list(region_id, region, nodes)

func _build_region_native(region: Dictionary) -> void:
	_horizontal = true
	var nat: Dictionary = region["native"]
	var dir := String(nat.get("atlas_dir", ""))
	var man := _load_manifest(dir)
	var coord: Dictionary = nat.get("coord", {})
	var S: float = float(coord.get("scale", 0.72))
	var tc: Array = coord.get("bg_tex_center", [735, 467.5])
	var bg_tex := Vector2(float(tc[0]), float(tc[1]))
	var map_w: float = maxf(float(nat.get("content_w", 0.0)), _vis().x)
	var bd: Array = coord.get("bg_design", [map_w * 0.5, FLOOR * 0.5])
	var bg_design := Vector2(float(bd[0]), float(bd[1]))
	if bool(coord.get("center_x", false)):
		bg_design.x = map_w * 0.5
	_tintables.clear()
	_ambient_by_id.clear()
	_backdrop = Node2D.new()
	_backdrop.z_index = _BACKDROP_Z
	_content.add_child(_backdrop)
	var bgname := String(nat.get("background", ""))
	var bgp := "res://assets/converted/worldmap_maps/%s.jpg" % bgname
	if bgname != "" and ResourceLoader.exists(bgp) and not Engine.has_meta("wm_no_ocean"):
		var bg := Sprite2D.new()
		bg.texture = load(bgp)
		bg.centered = false
		var tex: Texture2D = bg.texture
		bg.scale = Vector2(map_w / float(tex.get_width()), FLOOR / float(tex.get_height()))
		bg.z_index = _Z_SEA_BG
		_backdrop.add_child(bg)
		_build_sea_layers(coord, S, map_w)
	var bgd: Dictionary = nat.get("bg", {})
	if bgd.has("frame"):
		var bspr := _sprite_native(String(bgd["frame"]), dir, man, S)
		if bspr:
			bspr.position = bg_design
			_content.add_child(bspr)
			_tintables.append(bspr)
	var labels: Array = []
	var battle_nodes: Array = []
	_plate_pos.clear()
	for p in region.get("pieces", []):
		var pos: Array = p["pos"]
		var d := bg_design + (Vector2(float(pos[0]), float(pos[1])) - bg_tex) * S
		if p.has("design_offset"):
			var pd: Array = p["design_offset"]
			d += Vector2(float(pd[0]), float(pd[1]))
		var frame := String(p.get("frame", ""))
		if String(p.get("frame_from", "")) == "light_tower":
			frame = _light_tower_frame(nat, frame)
		var spr := _sprite_native(frame, dir, man, S)
		if spr:
			spr.position = d
			spr.z_index = int(p.get("z_index", 0))
			_content.add_child(spr)
			_tintables.append(spr)
		var lbl := String(p.get("label", ""))
		if lbl != "" and not bool(p.get("label_hidden", false)):
			labels.append({"text": lbl, "d": d, "frame": frame, "piece": p})
		var tgt := String(p.get("target", ""))
		var w := float(man.get(frame, {}).get("w", 100)) * S
		var h := float(man.get(frame, {}).get("h", 100)) * S
		var rect := Rect2(d.x - w * 0.5, d.y - h * 0.5, w, h)
		if String(p.get("type", "")) != "deco" and tgt != "":
			_add_hit_node(rect, tgt, Vector2(d.x, d.y), spr)
		if tgt.begins_with("battle:"):
			battle_nodes.append({"d": d, "stage": tgt.substr(7), "h": h, "rect": rect, "spr": spr,
				"target": tgt,
				"field": DungeonBG.base_field(DungeonBG.field_id(Data.stage(tgt.substr(7)))),
				"ld": _label_design_pos(p, coord, bg_design, bg_tex, S),
				"at_label": bool(p.get("mark_at_label", false))})
		elif int(p.get("field", 0)) >= 1000:
			battle_nodes.append({"d": d, "h": h, "rect": rect, "spr": spr,
				"field": int(p["field"]), "target": tgt, "at_label": bool(p.get("mark_at_label", false)),
				"ld": _label_design_pos(p, coord, bg_design, bg_tex, S)})
	_tintables.append_array(
		_add_ambient(nat.get("ambient", []), nat, dir, man, bg_design, bg_tex, S))
	_field_fx_ctx = {"nat": nat, "dir": dir, "man": man,
		"bg_design": bg_design, "bg_tex": bg_tex, "S": S}
	_field_fx.clear()
	for e in nat.get("field_fx", []):
		_field_fx[int(e.get("field", -1))] = e
	_add_facility(nat, bg_design, bg_tex, S)
	_add_summoned_boss(region, bg_design, bg_tex, S)
	if _yutakan_phase(nat) == "day":
		_build_clouds(coord, bg_design, bg_tex, S, map_w)
	for it in labels:
		var d: Vector2 = it["d"]
		if not _field_label(it["piece"], coord, bg_design, bg_tex, S):
			_map_label(String(it["text"]), d.x, d.y, String(it["frame"]), S, man)
	_mark_coord = {"L": coord.get("label", {}), "bg_design": bg_design, "bg_tex": bg_tex, "S": S}
	_mark_objective(battle_nodes, S)
	match _yutakan_phase(nat):
		"night":
			_apply_yutakan_night(nat, coord, dir, man, bg_design, bg_tex, S, map_w)
		"kades":
			_apply_kades_space(nat, coord, dir, man, bg_design, bg_tex, S, map_w)
	_variant_toggles = (dir == _YUTAKAN_DIR)
	_max_scroll = maxf(0.0, map_w - _vis().x)
	_setup_area_sounds(nat, bg_design, bg_tex, S)

func _setup_area_sounds(nat: Dictionary, bg_design: Vector2, bg_tex: Vector2, S: float) -> void:
	var areas: Array = []
	for s in nat.get("sounds", []):
		var r: Array = s.get("rect", [])
		if r.size() < 4:
			continue
		var tl := bg_design + (Vector2(float(r[0]), float(r[1])) - bg_tex) * S
		areas.append({"track": String(s.get("track", "")),
			"rect": Rect2(tl, Vector2(float(r[2]), float(r[3])) * S)})
	Bgm.area_setup(areas)
	_update_area_sounds()

func _update_area_sounds() -> void:
	var vis := _vis()
	var c := Vector2(vis.x * 0.5, vis.y * 0.5)
	if _horizontal:
		c.x += _scroll
	else:
		c.y += _scroll
	Bgm.area_update(c)

func _is_yutakan_night(nat: Dictionary) -> bool:
	if _params.has("night"):
		return bool(_params.get("night"))
	if UserDB.get_pmeta("yutakan_night", null) != null:
		return bool(UserDB.get_pmeta("yutakan_night", false))
	return bool(nat.get("night", false))

var _ambient_by_id: Dictionary = {}
var _field_fx: Dictionary = {}
var _field_fx_ctx: Dictionary = {}
var _field_fx_nodes: Array = []

func _play_field_fx(field: int) -> void:
	_clear_field_fx()
	var e: Dictionary = _field_fx.get(field, {})
	if e.is_empty() or _field_fx_ctx.is_empty():
		return
	var sounds: Array = e.get("sounds", [])
	if sounds.is_empty():
		var snd := String(e.get("sound", ""))
		if snd != "":
			sounds = [snd]
	for snd in sounds:
		if String(snd) != "":
			Bgm.sfx(String(snd))
	var touch_id := String(e.get("ambient_touch", ""))
	if touch_id == "veti":
		_veti_touch()
	elif touch_id != "":
		_play_ambient_touch(touch_id, String(e.get("anim", "")))
		return
	if String(e.get("kind", "")) == "sound":
		return
	var entry := (e as Dictionary).duplicate(true)
	if bool(e.get("anim_by_light_tower", false)):
		var nat: Dictionary = _field_fx_ctx["nat"]
		var lt: Dictionary = nat.get("light_tower", {})
		var tmap: Dictionary = lt.get("touch_anims", {})
		entry["anim"] = String(tmap.get(_light_tower_element(nat), "appear"))
	_field_fx_nodes = _add_ambient([entry], _field_fx_ctx["nat"], _field_fx_ctx["dir"],
		_field_fx_ctx["man"], _field_fx_ctx["bg_design"], _field_fx_ctx["bg_tex"],
		_field_fx_ctx["S"])

func _clear_field_fx() -> void:
	for n in _field_fx_nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_field_fx_nodes.clear()

func _play_ambient_touch(id: String, anim: String) -> void:
	var inst := _ambient_by_id.get(id) as Node2D
	if inst == null or not is_instance_valid(inst):
		return
	var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or anim == "" or not ap.has_animation(anim):
		return
	var token := int(inst.get_meta("touch_token", 0)) + 1
	inst.set_meta("touch_token", token)
	var clip := ap.get_animation(anim)
	if clip:
		clip.loop_mode = Animation.LOOP_NONE
	ap.stop()
	ap.play(anim)
	ap.animation_finished.connect(func(done: StringName):
		if is_instance_valid(inst) and int(inst.get_meta("touch_token", 0)) == token \
				and String(done) == anim:
			ap.stop()
			ap.seek(0.0, true), CONNECT_ONE_SHOT)

func _light_tower_element(nat: Dictionary) -> String:
	var lt: Dictionary = nat.get("light_tower", {})
	var cycle: Array = lt.get("hour_cycle", [])
	if cycle.is_empty():
		return "normal"
	var hour := int(Time.get_datetime_dict_from_system().get("hour", 0))
	return String(cycle[hour % cycle.size()])

func _light_tower_frame(nat: Dictionary, fallback: String) -> String:
	var lt: Dictionary = nat.get("light_tower", {})
	var frames: Dictionary = lt.get("frames", {})
	return String(frames.get(_light_tower_element(nat), fallback))

func _is_kades_space(nat: Dictionary) -> bool:
	if _params.has("kades"):
		return bool(_params.get("kades"))
	if UserDB.get_pmeta("kades_space", null) != null:
		return bool(UserDB.get_pmeta("kades_space", false))
	return bool(nat.get("kades", false))

const _KADES_CLOUDS := [
	{"i": 1, "pos": [424.0, 723.0]},
	{"i": 2, "pos": [82.0, 431.0]},
	{"i": 3, "pos": [733.0, 273.0]},
	{"i": 4, "pos": [1313.0, 420.0]},
	{"i": 5, "pos": [990.0, 652.0]},
	{"i": 6, "pos": [1810.0, 630.0]},
	{"i": 7, "pos": [1426.0, 1126.0]},
]
const _KADES_CLOUD_SCALE := 2.0
const _KADES_TINT := Color8(0xbf, 0x80, 0xf2)

var _tintables: Array = []

const _BACKDROP_Z := -1000
const _Z_SEA_BG := 0
const _Z_SEA_NEST := 100
const _Z_SEA_TRANS := 200
const _Z_SEA_DUST := 300
const _Z_VARIANT_SKY := 400
const _Z_CLOUD := 500
var _backdrop: Node2D

func _layer_to_design(coord: Dictionary, bg_design: Vector2, bg_tex: Vector2, S: float,
		pt: Vector2) -> Array:
	var L: Dictionary = coord.get("layer", {})
	if L.is_empty():
		return [Vector2.ZERO, false]
	var ls := float(L.get("s", 0.0))
	var bgpx := Vector2(ls * pt.x + float(L.get("tx", 0.0)),
		-ls * pt.y + float(L.get("ty", 0.0)))
	return [bg_design + (bgpx - bg_tex) * S, true]

const _YUTAKAN_DIR := "worldmap_yutakan_new"

func _yutakan_phase(nat: Dictionary) -> String:
	if String(nat.get("atlas_dir", "")) != _YUTAKAN_DIR:
		return "day"
	if _is_kades_space(nat):
		return "kades"
	if _is_yutakan_night(nat):
		return "night"
	return "day"

const _SEA_SPINE := "res://scenes/worldmap_fx/ani_sea_spine.tscn"
const _SEA_TRANS := "res://assets/converted/worldmap_sea/worldmap_sea_trans.png"
const _SEA_SPINE_SCALE := 4.0
const _SEA_TUNE_SCALE := 1.3
const _SEA_TUNE_SPEED := 0.75
const _SEA_OFFSET_PT := 140.0
const _SEA_TRANS_W_PT := 2328.0
const _SEA_TRANS_H_PT := 1385.1
const _SEA_TRANS_CANVAS := Vector2(1350.0, 913.0)
const _SEA_TRANS_TRIM_DY := 81.0

const _LAYER_PT_TO_BGPX := 0.75
func _layer_scale(coord: Dictionary, S: float) -> float:
	return float((coord.get("layer", {}) as Dictionary).get("s", _LAYER_PT_TO_BGPX)) * S

func _build_sea_layers(coord: Dictionary, S: float, map_w: float) -> void:
	var ld := _layer_scale(coord, S)
	if ld <= 0.0:
		return
	var center := Vector2(map_w * 0.5 + _SEA_OFFSET_PT * ld, FLOOR * 0.5)
	_add_sea_spine("nest", center, ld, _Z_SEA_NEST)
	_add_sea_trans(map_w, ld)
	_add_sea_spine("dustwave", center, ld, _Z_SEA_DUST)

func _add_sea_spine(anim: String, center: Vector2, ld: float, z: int) -> void:
	if not ResourceLoader.exists(_SEA_SPINE):
		return
	var inst := (load(_SEA_SPINE) as PackedScene).instantiate() as Node2D
	if inst == null:
		return
	inst.position = center
	var sc := _SEA_SPINE_SCALE * _SEA_TUNE_SCALE * ld
	inst.scale = Vector2(sc, sc)
	inst.z_index = z
	_backdrop.add_child(inst)
	var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap and ap.has_animation(anim):
		var a := ap.get_animation(anim)
		if a:
			a.loop_mode = Animation.LOOP_LINEAR
		ap.speed_scale = _SEA_TUNE_SPEED
		ap.play(anim)

func _add_sea_trans(map_w: float, ld: float) -> void:
	if not ResourceLoader.exists(_SEA_TRANS):
		return
	var spr := Sprite2D.new()
	spr.texture = load(_SEA_TRANS)
	spr.material = _pma
	var tex: Texture2D = spr.texture
	var fw := float(tex.get_width())
	var fh := float(tex.get_height())
	if fw <= 0.0 or fh <= 0.0:
		spr.queue_free()
		return
	var sx := maxf(_SEA_TRANS_W_PT * ld, map_w) / _SEA_TRANS_CANVAS.x
	var sy := _SEA_TRANS_H_PT * ld / _SEA_TRANS_CANVAS.y
	spr.scale = Vector2(sx, sy)
	spr.position = Vector2(map_w * 0.5, FLOOR * 0.5 + _SEA_TRANS_TRIM_DY * sy)
	spr.z_index = _Z_SEA_TRANS
	_backdrop.add_child(spr)

const _SKY_LAYER_W := 2328.0
const _IMP_DESIGN_POS := Vector2(600.0, 300.0)
const _IMP_SCALE := 1.05
var _imp_spine: Node2D
var _imp_pending := false

func _add_imp_shop() -> void:
	var sp := "res://scenes/worldmap_fx/worldmap_imp_spine.tscn"
	if not ResourceLoader.exists(sp) or not is_instance_valid(_content):
		return
	var inst := (load(sp) as PackedScene).instantiate() as Node2D
	if inst == null:
		return
	inst.position = _IMP_DESIGN_POS
	var co: Dictionary = _region_native().get("coord", {})
	var lay_s := float((co.get("layer", {}) as Dictionary).get("s", 0.75))
	var k := float(co.get("scale", 0.72)) * lay_s * _IMP_SCALE
	inst.scale = Vector2(k, k)
	inst.z_index = 30
	_content.add_child(inst)
	_imp_spine = inst
	var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap and ap.has_animation("normal"):
		ap.get_animation("normal").loop_mode = Animation.LOOP_LINEAR
		ap.play("normal")
	var btn := Button.new()
	btn.flat = true
	btn.size = Vector2(56.0, 56.0)
	btn.tooltip_text = "임프상인"
	btn.pressed.connect(_open_imp_shop)
	_imp_hit = btn
	_imp_hit_target = inst
	add_child(btn)
	_sync_imp_hit()

var _imp_hit: Button
var _imp_hit_target: Node2D

func _sync_imp_hit() -> void:
	if not is_instance_valid(_imp_hit) or not is_instance_valid(_imp_hit_target):
		return
	var sc := _imp_hit_target.get_global_transform_with_canvas().origin
	_imp_hit.position = sc - _imp_hit.size * 0.5

func _open_imp_shop() -> void:
	if is_instance_valid(_imp_layer):
		return
	Bgm.sfx("effect_button")
	var lay := CanvasLayer.new()
	lay.layer = 40
	add_child(lay)
	_imp_layer = lay
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 100.0 / 255.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	lay.add_child(dim)
	var scn := load("res://scenes/imp_shop.tscn") as PackedScene
	if scn == null:
		lay.queue_free()
		_imp_layer = null
		return
	var ui := scn.instantiate()
	lay.add_child(ui)
	if ui.has_method("enter"):
		ui.call("enter", {"region": _mode, "night": true, "overlay": true,
			"on_close": Callable(self, "_close_imp_shop")})

func _close_imp_shop() -> void:
	if is_instance_valid(_imp_layer):
		_imp_layer.queue_free()
	_imp_layer = null
	Bgm.play(_region_bgm(_mode))

var _imp_layer: CanvasLayer

func _add_variant_sky(key: String, coord: Dictionary, dir: String, man: Dictionary,
		bg_design: Vector2, S: float, map_w: float) -> void:
	var sky := _sprite_native(key, dir, man, S)
	if sky == null:
		return
	var tex: Texture2D = sky.texture
	var fw := float(tex.get_width())
	var fh := float(tex.get_height())
	if fw <= 0.0 or fh <= 0.0:
		sky.queue_free()
		return
	var ld := float((coord.get("layer", {}) as Dictionary).get("s", 0.0)) * S
	var sc0 := (_SKY_LAYER_W * ld / fw) if ld > 0.0 else (map_w / fw)
	sky.scale = Vector2(maxf(sc0, map_w / fw), sc0)
	sky.position = Vector2(map_w * 0.5, bg_design.y)
	sky.z_index = _Z_VARIANT_SKY
	_backdrop.add_child(sky)

func _apply_kades_space(nat: Dictionary, coord: Dictionary, dir: String, man: Dictionary,
		bg_design: Vector2, bg_tex: Vector2, S: float, map_w: float) -> void:
	_add_variant_sky("scene_worldmap_map_yutakan_new_kades_w_curse_sky", coord, dir, man,
		bg_design, S, map_w)
	for n in _tintables:
		if n is CanvasItem:
			(n as CanvasItem).modulate = _KADES_TINT
	var rng := RandomNumberGenerator.new(); rng.randomize()
	for c in _KADES_CLOUDS:
		var key := "scene_worldmap_map_yutakan_new_kades_w_cloud%02d" % int(c["i"])
		var spr := _sprite_native(key, dir, man, S * _KADES_CLOUD_SCALE)
		if spr == null:
			continue
		var p: Array = c["pos"]
		var r := _layer_to_design(coord, bg_design, bg_tex, S, Vector2(float(p[0]), float(p[1])))
		if not bool(r[1]):
			continue
		spr.position = r[0]
		spr.z_index = 13
		spr.modulate.a = 0.0
		_content.add_child(spr)
		var t := spr.create_tween()
		t.tween_interval(float(rng.randi() % 50) * 0.01)
		t.tween_property(spr, "modulate:a", 1.0, 0.0)
		var drift := spr.create_tween().set_loops()
		var x0 := spr.position.x
		drift.tween_property(spr, "position:x", x0 + 40.0, 6.0).set_trans(Tween.TRANS_SINE)
		drift.tween_property(spr, "position:x", x0, 6.0).set_trans(Tween.TRANS_SINE)

var _variant_toggles := false

func _apply_yutakan_night(nat: Dictionary, coord: Dictionary, dir: String, man: Dictionary,
		bg_design: Vector2, bg_tex: Vector2, S: float, map_w: float) -> void:
	_add_variant_sky("scene_worldmap_map_yutakan_new_night_night", coord, dir, man,
		bg_design, S, map_w)
	_imp_pending = true
	var lc: Dictionary = nat.get("night_fx", {}).get("light2", {})
	var lp: Array = lc.get("layer_pos", [1566.0, 994.0])
	var lo: Array = lc.get("design_offset", [0.0, 0.0])
	var light := _sprite_native("scene_worldmap_map_yutakan_new_night_night_light2", dir, man, S)
	if light:
		var r := _layer_to_design(coord, bg_design, bg_tex, S,
			Vector2(float(lp[0]), float(lp[1])))
		if bool(r[1]):
			light.position = (r[0] as Vector2) + Vector2(float(lo[0]), float(lo[1]))
			light.z_index = 13
			_content.add_child(light)
		else:
			light.queue_free()
	_max_scroll = maxf(0.0, map_w - _vis().x)

func _sprite_native(name: String, dir: String, man: Dictionary, scale := 1.0) -> Sprite2D:
	if name == "":
		return null
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if not ResourceLoader.exists(p):
		return null
	var s := Sprite2D.new()
	s.texture = load(p)
	s.material = _pma
	s.scale = Vector2(scale, scale)
	return s

func _add_facility(nat: Dictionary, bg_design: Vector2, bg_tex: Vector2, S: float) -> void:
	var f: Dictionary = nat.get("facility", {})
	if f.is_empty():
		return
	var pos: Array = f.get("pos", [0, 0])
	var d := bg_design + (Vector2(float(pos[0]), float(pos[1])) - bg_tex) * S
	var sp := "res://scenes/worldmap_fx/%s.tscn" % String(f.get("scene", ""))
	if ResourceLoader.exists(sp):
		var inst := (load(sp) as PackedScene).instantiate() as Node2D
		if inst != null:
			inst.position = d
			var fs := float(f.get("scale", 1.0))
			inst.scale = Vector2(S * fs, S * fs)
			_content.add_child(inst)
			var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if ap:
				var an := String(f.get("anim", ""))
				if an == "" or not ap.has_animation(an):
					an = ap.get_animation_list()[0] if ap.get_animation_list().size() > 0 else ""
				if an != "":
					var anim := ap.get_animation(an)
					if anim: anim.loop_mode = Animation.LOOP_LINEAR
					ap.play(an)
	var hit: Array = f.get("hit", [140, 180])
	var hw := float(hit[0]) * S
	var hh := float(hit[1]) * S
	_add_hit_node(Rect2(d.x - hw * 0.5, d.y - hh * 0.5, hw, hh), String(f.get("target", "")), d)
	var lbl := String(f.get("label", ""))
	if lbl != "":
		_map_label(lbl, d.x, d.y - hh * 0.5 + 50.0, "", 1.0, {})

var _boss_spine: Node2D = null
var _boss_cfg: Dictionary = {}
func _add_summoned_boss(region: Dictionary, bg_design: Vector2, bg_tex: Vector2, S: float) -> void:
	_boss_spine = null
	_boss_cfg = {}
	var now := int(Time.get_unix_time_from_system())
	var state := UserDB.darknix()
	if not Darknix.is_active(state, now):
		return
	var cfg: Dictionary = {}
	var anchor := -1
	for p in region.get("pieces", []):
		var tgt := String(p.get("target", ""))
		if not tgt.begins_with("battle:"):
			continue
		var stg := Data.stage(tgt.substr(7))
		if Darknix.is_summon_stage(stg):
			cfg = stg["summon"]
			anchor = int(p.get("field", -1))
			break
	if cfg.is_empty():
		return
	var sp := "res://scenes/worldmap_fx/%s.tscn" % String(cfg.get("spine", ""))
	if not ResourceLoader.exists(sp):
		return
	var d := Vector2.ZERO
	for p in region.get("pieces", []):
		if int(p.get("field", -2)) != int(cfg.get("anchor_piece", anchor)):
			continue
		var pos: Array = p["pos"]
		d = bg_design + (Vector2(float(pos[0]), float(pos[1])) - bg_tex) * S
		if p.has("design_offset"):
			var pd: Array = p["design_offset"]
			d += Vector2(float(pd[0]), float(pd[1]))
		break
	if cfg.has("design_offset"):
		var od: Array = cfg["design_offset"]
		d += Vector2(float(od[0]), float(od[1])) * S
	var inst := (load(sp) as PackedScene).instantiate() as Node2D
	if inst == null:
		return
	inst.position = d
	var lay_s := float((region.get("native", {}) as Dictionary).get("coord", {}).get("layer", {}).get("s", 1.0))
	inst.scale = Vector2(S * lay_s, S * lay_s)
	_content.add_child(inst)
	_boss_spine = inst
	_boss_cfg = cfg
	var status := int(state.get("status", 1))
	var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		return
	var seen := UserDB.darknix_seen()
	var breath := Darknix.anim_of(cfg, status, 1)
	var appear := Darknix.anim_of(cfg, status, 0)
	if not seen and ap.has_animation(appear):
		UserDB.darknix_mark_seen()
		var a := ap.get_animation(appear)
		if a: a.loop_mode = Animation.LOOP_NONE
		ap.play(appear)
		ap.animation_finished.connect(func(_n): _boss_loop_breath(ap, breath), CONNECT_ONE_SHOT)
	else:
		_boss_loop_breath(ap, breath)
	var touch := Darknix.anim_of(cfg, status, 2)
	var hit := Button.new(); hit.flat = true
	var hw := 150.0 * S
	var hh := 170.0 * S
	hit.size = Vector2(hw, hh)
	hit.position = d - Vector2(hw * 0.5, hh * 0.75)
	hit.pressed.connect(func(): _boss_touch(ap, touch, breath))
	_content.add_child(hit)

func _boss_loop_breath(ap: AnimationPlayer, breath: String) -> void:
	if not is_instance_valid(ap) or breath == "" or not ap.has_animation(breath):
		return
	var a := ap.get_animation(breath)
	if a: a.loop_mode = Animation.LOOP_LINEAR
	ap.play(breath)

func _boss_touch(ap: AnimationPlayer, touch: String, breath: String) -> void:
	if not is_instance_valid(ap) or touch == "" or not ap.has_animation(touch):
		return
	var a := ap.get_animation(touch)
	if a: a.loop_mode = Animation.LOOP_NONE
	ap.play(touch)
	ap.animation_finished.connect(func(_n): _boss_loop_breath(ap, breath), CONNECT_ONE_SHOT)

const _AMBIENT_DELAY := 0.2
func _add_ambient(entries: Array, nat: Dictionary, dir: String, man: Dictionary,
		bg_design: Vector2, bg_tex: Vector2, S: float) -> Array:
	var made: Array = []
	var prefix := String(nat.get("ambient_prefix", ""))
	var coord: Dictionary = nat.get("coord", {})
	for a in entries:
		if not bool(a.get("enabled", true)):
			continue
		var d := Vector2.ZERO
		if a.has("layer_pos"):
			var lp: Array = a["layer_pos"]
			var A: Dictionary = coord.get("ambient", {})
			if lp.size() < 2 or A.is_empty():
				continue
			var ascale := float(A.get("s", 0.75))
			var bgpx := Vector2(ascale * float(lp[0]) + float(A.get("tx", 0.0)),
				-ascale * float(lp[1]) + float(A.get("ty", 0.0)))
			d = bg_design + (bgpx - bg_tex) * S
		else:
			var pos: Array = a.get("pos", [])
			if pos.size() < 2:
				continue
			d = bg_design + (Vector2(float(pos[0]), float(pos[1])) - bg_tex) * S
		if a.has("design_offset"):
			var od: Array = a["design_offset"]
			d += Vector2(float(od[0]), float(od[1]))
		var kind := String(a.get("kind", ""))
		var base := prefix + String(a.get("base", ""))
		if kind == "spine":
			var sp := "res://scenes/worldmap_fx/%s.tscn" % String(a.get("scene", ""))
			if not ResourceLoader.exists(sp):
				continue
			var inst := (load(sp) as PackedScene).instantiate() as Node2D
			if inst == null:
				continue
			inst.position = d
			var lay_s := float(coord.get("layer", {}).get("s", 1.0))
			var a_scale := float(a.get("scale", lay_s))
			inst.scale = Vector2(S * a_scale, S * a_scale)
			for hs in a.get("hide_slots", []):
				var hn := inst.find_child(String(hs), true, false)
				if hn is CanvasItem:
					(hn as CanvasItem).visible = false
			_content.add_child(inst)
			made.append(inst)
			var aid := String(a.get("id", ""))
			if aid != "":
				_ambient_by_id[aid] = inst
				inst.set_meta("veti_home", d)
			var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if ap:
				if not bool(a.get("autoplay", true)):
					ap.stop()
					ap.seek(0.0, true)
					continue
				match String(a.get("cycle", "")):
					"flash":
						_spine_flash_cycle(inst, ap, a)
						continue
					"veti":
						inst.set_meta("veti_span", _VETI_WALK_SPAN * 0.75 * S)
						_veti_cycle(inst, ap, d)
						continue
				var an := String(a.get("anim", ""))
				if an == "" or not ap.has_animation(an):
					an = ap.get_animation_list()[0] if ap.get_animation_list().size() > 0 else ""
				if an != "":
					var anim := ap.get_animation(an)
					var loop := bool(a.get("loop", true))
					if anim:
						anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
					ap.play(an)
					var remove_after := float(a.get("remove_after", 0.0))
					if remove_after > 0.0:
						var cleanup := inst.create_tween()
						cleanup.tween_interval(remove_after)
						cleanup.tween_property(inst, "modulate:a", 0.0, 0.5)
						cleanup.tween_callback(inst.queue_free)
			continue
		if kind == "sprite":
			var spr := _sprite_native(prefix + String(a.get("base", "")), dir, man, S)
			if spr == null:
				continue
			spr.position = d
			_content.add_child(spr)
			made.append(spr)
			spr.modulate.a = 0.0
			var tw := spr.create_tween()
			var fade_in := float(a.get("fade_in", 0.5))
			var fade_out := float(a.get("fade_out", 0.5))
			var pulses := maxi(1, int(a.get("pulses", 1)))
			for _i in range(pulses):
				tw.tween_property(spr, "modulate:a", 1.0, fade_in)
				if pulses == 1:
					tw.tween_interval(float(a.get("hold", 0.0)))
				tw.tween_property(spr, "modulate:a", 0.0, fade_out)
			tw.tween_callback(spr.queue_free)
			continue
		if kind == "flip":
			var n := int(a.get("n", 1))
			var use_off := not bool(a.get("no_offset", false))
			var off01: Array = man.get("%s01" % base, {}).get("off", [0, 0])
			var frames: Array = []
			for i in range(1, n + 1):
				var fname := "%s%02d" % [base, i]
				var t := _tex_native(fname, dir)
				if t:
					var mi: Dictionary = man.get(fname, {})
					var frot := 0.0
					var offi: Array = mi.get("off", off01)
					var od := Vector2.ZERO
					if use_off:
						od = Vector2(float(offi[0]) - float(off01[0]), -(float(offi[1]) - float(off01[1]))) * S
					frames.append({"tex": t, "rot": frot, "off": od})
			if frames.is_empty():
				continue
			var s := _sprite_native("%s01" % base, dir, man, S)
			if not s:
				continue
			s.position = d
			_content.add_child(s)
			made.append(s)
			var tw := s.create_tween().set_loops()
			for fr in frames:
				var ftex: Texture2D = fr["tex"]
				var frot2: float = fr["rot"]
				var foff: Vector2 = fr["off"]
				tw.tween_callback(func():
					s.texture = ftex
					s.rotation = frot2
					s.position = d + foff)
				tw.tween_interval(_AMBIENT_DELAY)
			continue
		var spr := _sprite_native(base, dir, man, S)
		if not spr:
			continue
		spr.position = d
		_content.add_child(spr)
		made.append(spr)
		match kind:
			"spin":
				var per := float(a.get("period", 2.0))
				var t2 := spr.create_tween().set_loops()
				t2.tween_property(spr, "rotation", spr.rotation + PI, per).as_relative()
			"pulse":
				var to := float(a.get("to", 1.2))
				var per2 := float(a.get("period", 2.0))
				var t3 := spr.create_tween().set_loops()
				t3.tween_property(spr, "scale", Vector2(S * to, S * to), per2)
				t3.tween_interval(0.5)
				t3.tween_property(spr, "scale", Vector2(S, S), per2)
			"bob":
				var t4 := spr.create_tween().set_loops()
				for mv in [[0, -5, 1.0], [0, 5, 1.5], [-2, -2, 1.0], [2, 2, 1.5], [-10, 0, 2.0], [10, -5, 2.0], [0, 5, 1.0]]:
					t4.tween_property(spr, "position", Vector2(mv[0] * S, mv[1] * S), mv[2]).as_relative()
			"sway":
				var t5 := spr.create_tween().set_loops()
				t5.tween_property(spr, "position", Vector2(10 * S, 0), 3.5).as_relative()
				t5.tween_property(spr, "position", Vector2(-10 * S, 0), 3.5).as_relative()
	return made

func _spine_flash_cycle(inst: Node2D, ap: AnimationPlayer, a: Dictionary) -> void:
	var an := String(a.get("anim", ""))
	if not ap.has_animation(an):
		return
	var lo := float(a.get("gap_min", 10.0))
	var hi := float(a.get("gap_max", 19.0))
	var dur: float = ap.get_animation(an).length
	inst.visible = false
	var rng := RandomNumberGenerator.new(); rng.randomize()
	while is_instance_valid(inst) and inst.is_inside_tree():
		await get_tree().create_timer(rng.randf_range(lo, hi)).timeout
		if not (is_instance_valid(inst) and inst.is_inside_tree()):
			return
		inst.visible = true
		ap.play(an)
		await get_tree().create_timer(dur).timeout
		if not is_instance_valid(inst):
			return
		inst.visible = false

const _VETI_ACTS := [
	["breath", 2.83, 3], ["walk", 6.12, 2], ["scratch", 4.79, 2],
	["sleep", 19.2, 1], ["snowman", 19.2, 1],
]
const _VETI_WALK_MOVE := 5.0
const _VETI_WALK_SPAN := 130.0
const _VETI_TOUCH_BACK := 14.3

func _veti_cycle(inst: Node2D, ap: AnimationPlayer, home: Vector2) -> void:
	var gen := int(inst.get_meta("veti_gen", 0))
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var span := float(inst.get_meta("veti_span", 70.0))
	while is_instance_valid(inst) and inst.is_inside_tree():
		if int(inst.get_meta("veti_gen", 0)) != gen:
			return
		var pick := rng.randi_range(0, 8)
		var act: Array = _VETI_ACTS[0]
		var acc := 0
		for e in _VETI_ACTS:
			acc += int(e[2])
			if pick < acc:
				act = e
				break
		var an := String(act[0])
		var dur := float(act[1])
		if ap.has_animation(an):
			ap.get_animation(an).loop_mode = Animation.LOOP_NONE
			ap.play(an)
		if an == "walk":
			var at_home := absf(inst.position.x - home.x) < 1.0
			var tgt := home.x + (span if at_home else 0.0)
			inst.scale.x = -absf(inst.scale.x) if at_home else absf(inst.scale.x)
			var tw := inst.create_tween()
			tw.tween_property(inst, "position:x", tgt, _VETI_WALK_MOVE)
		await get_tree().create_timer(dur).timeout

func _veti_touch() -> void:
	var inst := _ambient_by_id.get("veti") as Node2D
	if inst == null or not is_instance_valid(inst):
		return
	var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null or not ap.has_animation("embarrassed"):
		return
	inst.set_meta("veti_gen", int(inst.get_meta("veti_gen", 0)) + 1)
	var home: Vector2 = inst.get_meta("veti_home", inst.position)
	ap.get_animation("embarrassed").loop_mode = Animation.LOOP_NONE
	ap.play("embarrassed")
	await get_tree().create_timer(_VETI_TOUCH_BACK).timeout
	if is_instance_valid(inst) and inst.is_inside_tree():
		_veti_cycle(inst, ap, home)

func _tex_native(name: String, dir: String) -> Texture2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	return load(p) if ResourceLoader.exists(p) else null

func _build_region_map(region: Dictionary, nodes: Array) -> void:
	_horizontal = true
	var pscale: float = float(region.get("piece_scale", 0.5))
	var map_w: float = float(region.get("map_w", _vis().x))
	var bgname := String(region.get("background", ""))
	var bgp := "res://assets/converted/worldmap_maps/%s.jpg" % bgname
	if bgname != "" and ResourceLoader.exists(bgp) and not Engine.has_meta("wm_no_ocean"):
		var bg := Sprite2D.new()
		bg.texture = load(bgp)
		bg.centered = false
		var tex: Texture2D = bg.texture
		bg.scale = Vector2(map_w / float(tex.get_width()), FLOOR / float(tex.get_height()))
		_content.add_child(bg)
	var island := String(region.get("island", ""))
	var ipath := "res://assets/converted/worldmap_maps/%s.png" % island
	if island != "" and ResourceLoader.exists(ipath):
		var isp := Sprite2D.new()
		isp.texture = load(ipath)
		isp.centered = false
		var iscale: float = float(region.get("island_scale", 1.0))
		isp.scale = Vector2(iscale, iscale)
		var ipos: Array = region.get("island_pos", [0, 0])
		isp.position = Vector2(float(ipos[0]), float(ipos[1]))
		_content.add_child(isp)
	var items: Array = []
	for d in region.get("decorations", []):
		items.append({"nd": d, "is_node": false})
	for nd in nodes:
		items.append({"nd": nd, "is_node": true})
	items.sort_custom(func(a, b): return float(a["nd"]["pos"][1]) < float(b["nd"]["pos"][1]))
	for it in items:
		var nd: Dictionary = it["nd"]
		var px: float = float(nd["pos"][0])
		var py: float = float(nd["pos"][1])
		var frame := String(nd.get("frame", ""))
		var iscale2: float = float(nd.get("scale", pscale))
		var piece := _sprite(frame, iscale2)
		if piece:
			piece.position = Vector2(px, py)
			_content.add_child(piece)
		_map_label(String(nd.get("label", "")), px, py, frame, iscale2)
		if it["is_node"]:
			var w := _fw(frame) * iscale2
			var h := _fh(frame) * iscale2
			_add_hit_node(Rect2(px - w * 0.5, py - h * 0.5, w, h), String(nd.get("target", "")), Vector2(px, py))
	_max_scroll = maxf(0.0, map_w - _vis().x)

const _LBL_PLATE_H := 33.6
const _LBL_MIN_W := 105.6
const _LBL_PAD_W := 12.8
const _LBL_PLATE_ALPHA := 0.6
const _LBL_Z := 40
const _LBL_TEXT_DX := 2.0
const _LBL_LINE_GAP := 22.5
const _LBL_FONT := "common"
const _LBL_FONT_SCALE := 0.80
const _LBL_OUTLINE := 3
const _LBL_LV_SCALE := 1.15
const _LBL_LV_OUTLINE := 5

func _field_plate(name: String, level: int, color: Color, special: bool,
		anchor: Vector2, align := 0) -> Vector2:
	if name == "":
		return anchor
	var lv := _bmf_ui(_LBL_FONT_SCALE * _LBL_LV_SCALE, _LBL_FONT) if level > 0 else null
	var nm := _bmf_ui(_LBL_FONT_SCALE, _LBL_FONT)
	nm.text = name
	var text_w: float = nm.get_theme_font("font").get_string_size(
		name, HORIZONTAL_ALIGNMENT_LEFT, -1, nm.get_theme_font_size("font_size")).x
	var pw := maxf(text_w, _LBL_MIN_W) + _LBL_PAD_W
	var root := Node2D.new()
	root.position = anchor + (Vector2(-pw * 0.5, _LBL_PLATE_H * 0.5) if align == 1 else Vector2.ZERO)
	root.z_index = _LBL_Z
	_content.add_child(root)
	var sz := Vector2(pw, _LBL_PLATE_H)
	var bg := AtlasUI.nine("ninepatch_ui", "9patch_label_bg", sz)
	if bg != null:
		bg.modulate = Color(color.r, color.g, color.b, _LBL_PLATE_ALPHA)
		bg.position = -sz * 0.5
		root.add_child(bg)
	var fr := AtlasUI.nine("worldmap_ui", "scene_worldmap_label_frame_special", sz) if special \
		else AtlasUI.nine("ninepatch_ui", "9patch_label_frame", sz)
	if fr != null:
		fr.modulate.a = _LBL_PLATE_ALPHA
		fr.position = -sz * 0.5
		root.add_child(fr)
	for l in [lv, nm]:
		if l == null:
			continue
		if l == lv:
			l.text = "LV%d" % level
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size",
			_LBL_LV_OUTLINE if l == lv else _LBL_OUTLINE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size = sz
		l.position = Vector2(-pw * 0.5 + _LBL_TEXT_DX,
			-_LBL_PLATE_H * 0.5 - _LBL_TEXT_DX - (_LBL_LINE_GAP if l == lv else 0.0))
		root.add_child(l)
	var top := -_LBL_PLATE_H * 0.5
	if lv != null:
		top = minf(top, -_LBL_PLATE_H * 0.5 - _LBL_TEXT_DX - _LBL_LINE_GAP)
	return root.position + Vector2(0.0, top)

func _label_design_pos(p: Dictionary, coord: Dictionary, bg_design: Vector2, bg_tex: Vector2,
		S: float):
	if not p.has("label_pos"):
		return null
	var L: Dictionary = coord.get("label", {})
	if L.is_empty():
		return null
	var lp: Array = p["label_pos"]
	var ls := float(L.get("s", 0.75))
	var bgpx := Vector2(ls * float(lp[0]) + float(L.get("tx", 0.0)),
		-ls * float(lp[1]) + float(L.get("ty", 0.0)))
	var d := bg_design + (bgpx - bg_tex) * S
	var off: Array = p.get("label_offset", [0.0, 0.0])
	return d + Vector2(float(off[0]), float(off[1]))

func _field_label(p: Dictionary, coord: Dictionary, bg_design: Vector2, bg_tex: Vector2,
		S: float) -> bool:
	var dv = _label_design_pos(p, coord, bg_design, bg_tex, S)
	if dv == null:
		return false
	var d: Vector2 = dv
	var c = p.get("label_color", 0)
	var col := Color(String(c)) if typeof(c) == TYPE_STRING else worldmap_label_color(int(c))
	var center := _field_plate(String(p.get("label", "")), int(p.get("label_level", 0)), col,
		bool(p.get("label_special", false)), d, int(p.get("label_align", 0)))
	var tg := String(p.get("target", ""))
	if tg != "":
		_plate_pos[tg] = center
	return true

func _map_label(text: String, px: float, py: float, frame: String, pscale: float, man := {}) -> void:
	if text == "":
		return
	var fh: float = float(man.get(frame, {}).get("h", 100)) if not man.is_empty() else _fh(frame)
	_field_plate(text, 0, Color.WHITE, false,
		Vector2(px, maxf(_LBL_PLATE_H * 0.5 + 6.0, py - fh * pscale * 0.5 - 22.0)))

func _build_region_list(region_id: String, region: Dictionary, nodes: Array) -> void:
	var vis := _vis()
	var cx := vis.x * 0.5
	var y := 150.0
	var step := 200.0
	var i := 0
	for nd in nodes:
		var zig := 120.0 if (i % 2 == 0) else -120.0
		var thumb := _sprite(String(nd.get("frame", "")), 0.8)
		if thumb:
			thumb.position = Vector2(cx + zig, y)
			_content.add_child(thumb)
		var lbl := Label.new()
		lbl.text = "%d. %s" % [i + 1, String(nd.get("label", ""))]
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.add_theme_color_override("font_color", Color(0.25, 0.18, 0.08))
		lbl.position = Vector2(cx + zig - 70, y + 60)
		_content.add_child(lbl)
		var fw := _fw(String(nd.get("frame", "")))
		var fh := _fh(String(nd.get("frame", ""))) * 0.8
		_add_hit(Rect2(cx + zig - fw * 0.4, y - fh * 0.5, fw * 0.8, fh + 30), "node", String(nd.get("target", "")))
		y += step
		i += 1
	if nodes.is_empty():
		var note := Label.new()
		note.text = "(노드 데이터 미작성 — %s)" % region_id
		note.add_theme_color_override("font_color", Color(0.3, 0.2, 0.1))
		note.position = Vector2(cx - 200, 300)
		_content.add_child(note)
	_max_scroll = maxf(0.0, y - _vis().y + 60.0)

func _set_content_height(h: float) -> void:
	_max_scroll = maxf(0.0, h - _vis().y + 60.0)

func _apply_scroll() -> void:
	if not _content: return
	_content.position = Vector2(-_scroll, 0) if _horizontal else Vector2(0, -_scroll)
	_update_area_sounds()

func _gui_input(event: InputEvent) -> void:
	if _busy:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_press_pos = event.position; _moved = false
			_scroll_vel = 0.0
		elif not _moved:
			_try_click(event.position)
	elif event is InputEventMouseMotion and _dragging:
		if event.position.distance_to(_press_pos) > 6.0: _moved = true
		var delta: float = event.relative.x if _horizontal else event.relative.y
		_scroll = clampf(_scroll - delta, 0.0, _max_scroll)
		_scroll_vel = delta
		_apply_scroll()

func _process(dt: float) -> void:
	if not _clouds.is_empty():
		for c in _clouds:
			var n = c["node"]
			if not is_instance_valid(n): continue
			n.position.x += float(c["speed"]) * dt
			var cw := float(c["w"])
			if n.position.x - cw * 0.5 > float(c["wrap"]):
				n.position.x = -cw * 0.5
	if _dragging or _busy or absf(_scroll_vel) < 1.0:
		return
	_scroll = clampf(_scroll - _scroll_vel, 0.0, _max_scroll)
	_apply_scroll()
	_scroll_vel *= 0.90
	if _scroll <= 0.0 or _scroll >= _max_scroll:
		_scroll_vel = 0.0

func _story_objective_active() -> bool:
	var no := StoryProgress.next_episode()
	if no <= 0 or StoryProgress.seen(no):
		return false
	return StoryProgress.unlocked(no) or StoryProgress.spec(no).size() > 0

const ARROW_UP := 105.0

var _mark_coord: Dictionary = {}

func _mark_design_pos(pos, up := 0.0):
	if pos == null or (pos as Array).size() < 2 or _mark_coord.is_empty():
		return null
	var L: Dictionary = _mark_coord["L"]
	if L.is_empty():
		return null
	var ls := float(L.get("s", 0.75))
	var x := float((pos as Array)[0])
	var y := float((pos as Array)[1]) + up
	var bgpx := Vector2(ls * x + float(L.get("tx", 0.0)), -ls * y + float(L.get("ty", 0.0)))
	return _mark_coord["bg_design"] + (bgpx - _mark_coord["bg_tex"]) * float(_mark_coord["S"])

func _mark_objective(battle_nodes: Array, S := 0.72) -> void:
	if not _story_objective_active():
		return
	var best: Dictionary = _story_field_node(battle_nodes)
	if best.is_empty():
		return
	var d: Vector2 = best["d"]
	var mh := float(best.get("h", 100.0))
	var by := -(mh * 0.5 + 45.0)
	var ls := 0.75 * S
	var field := int(best.get("field", 0))
	if String(best.get("target", "")) == "" and best.has("rect"):
		_add_hit_node(best["rect"], "story", best["d"], best.get("spr"))
	var mp = null
	if not bool(best.get("at_label", false)):
		mp = _mark_design_pos(Data.story_mark_pos(field))
	if mp != null:
		d = mp
		by = 0.0
	elif best.get("ld") != null:
		d = best["ld"]
		by = 0.0

	var mk := AtlasUI.spr("common_ui", "common_event", _MARK_SCALE * Design.ASSET_SCALE * ls)
	if mk == null:
		return
	mk.position = d + Vector2(0, by)
	mk.z_index = 41
	_content.add_child(mk)
	_mark_bounce(mk, d.y + by, ls)
	var ar := AtlasUI.spr("worldmap_ui", "scene_worldmap_event_arrow",
		_ARROW_SCALE * Design.ASSET_SCALE * ls)
	if ar != null:
		var afield := field
		var anode: Dictionary = _story_field_node(battle_nodes, StoryProgress.notify_field())
		if not anode.is_empty():
			afield = int(anode.get("field", afield))
		var apos = _mark_design_pos(Data.story_notify_pos(afield), ARROW_UP)
		var ay := d.y + by
		var ax := d.x
		if apos != null:
			ax = (apos as Vector2).x
			ay = (apos as Vector2).y
		else:
			var mk_h := AtlasUI.size_pt("common_ui", "common_event").y * _MARK_SCALE * ls
			var ar_h := AtlasUI.size_pt("worldmap_ui", "scene_worldmap_event_arrow").y * _ARROW_SCALE * ls
			ay -= (mk_h + ar_h) * 0.5 + (40.0 + 20.0 + 4.0) * ls
		ar.position = Vector2(ax, ay)
		ar.z_index = 42
		_content.add_child(ar)
		_arrow_bounce(ar, ay, ls)

func _story_field_node(battle_nodes: Array, want := -1) -> Dictionary:
	if want < 0:
		want = StoryProgress.mark_field()
	if want <= 0:
		return {}
	for bn in battle_nodes:
		if int(bn.get("field", 0)) == want:
			return bn
	return {}

var _plate_pos: Dictionary = {}

const _MARK_SCALE := 1.5
const _MARK_STEPS := [
	[-40.0, 0.3, true], [0.0, 0.0, false],
	[-20.0, 0.2, true], [0.0, 0.0, false],
	[-10.0, 0.1, true], [0.0, 0.0, false],
]
func _mark_bounce(spr: Sprite2D, base_y: float, ls := 0.54) -> void:
	var s0 := _MARK_SCALE * Design.ASSET_SCALE * ls
	var tw := spr.create_tween().set_loops()
	for st in _MARK_STEPS:
		var up: bool = bool(st[2])
		var mv := tw.tween_property(spr, "position:y", base_y + float(st[0]) * ls, 0.5)
		mv.set_trans(Tween.TRANS_EXPO if up else Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		var sc := s0 * (1.0 + float(st[1]) / _MARK_SCALE)
		tw.parallel().tween_property(spr, "scale", Vector2(sc, sc), 0.5)
	tw.tween_interval(0.5)

const _ARROW_SCALE := 2.0
const _ARROW_DIP := 20.0
const _ARROW_DIP_SCALE := 1.8
func _arrow_bounce(spr: Sprite2D, base_y: float, ls := 0.54) -> void:
	var s0 := _ARROW_SCALE * Design.ASSET_SCALE * ls
	var s1 := _ARROW_DIP_SCALE * Design.ASSET_SCALE * ls
	var tw := spr.create_tween().set_loops()
	tw.tween_property(spr, "position:y", base_y + _ARROW_DIP * ls, 0.7)
	tw.parallel().tween_property(spr, "scale", Vector2(s1, s1), 0.7)
	tw.tween_property(spr, "position:y", base_y, 0.7)
	tw.parallel().tween_property(spr, "scale", Vector2(s0, s0), 0.7)

func _build_wander_wonder() -> void:
	if not ResourceLoader.exists("res://scenes/npc/wonder.tscn"):
		return
	var vis := _vis()
	var y := FLOOR * 0.56
	var x0 := vis.x * 0.55
	var x1 := vis.x * 0.80
	var holder := Node2D.new()
	holder.position = Vector2(x0, y)
	holder.scale = Vector2(0.5, 0.5)
	holder.z_index = 5
	_content.add_child(holder)
	var inst = (load("res://scenes/npc/wonder.tscn") as PackedScene).instantiate()
	holder.add_child(inst)
	var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap:
		var anims := ap.get_animation_list()
		if anims.size() > 0:
			ap.get_animation(anims[0]).loop_mode = Animation.LOOP_LINEAR
			ap.play(anims[0])
	var sx: float = absf(holder.scale.x)
	var tw := holder.create_tween().set_loops()
	tw.tween_property(holder, "position:x", x1, 5.0)
	tw.tween_callback(func(): if is_instance_valid(holder): holder.scale.x = -sx)
	tw.tween_interval(0.4)
	tw.tween_property(holder, "position:x", x0, 5.0)
	tw.tween_callback(func(): if is_instance_valid(holder): holder.scale.x = sx)
	tw.tween_interval(0.4)

func _build_wander_imp() -> void:
	var man := _load_manifest("adventure_ui")
	if not man.has("scene_adventure_imp_pack"):
		return
	var imp := _sprite_native("scene_adventure_imp_pack", "adventure_ui", man, 0.55)
	if not imp:
		return
	var vis := _vis()
	var y := FLOOR * 0.7
	var x0 := vis.x * 0.36
	var x1 := vis.x * 0.60
	imp.position = Vector2(x0, y)
	imp.z_index = 6
	_content.add_child(imp)
	var sx: float = absf(imp.scale.x)
	var tw := imp.create_tween().set_loops()
	tw.tween_property(imp, "position:x", x1, 3.2)
	tw.tween_callback(func(): if is_instance_valid(imp): imp.scale.x = -sx)
	tw.tween_interval(0.3)
	tw.tween_property(imp, "position:x", x0, 3.2)
	tw.tween_callback(func(): if is_instance_valid(imp): imp.scale.x = sx)
	tw.tween_interval(0.3)
	var tb := imp.create_tween().set_loops()
	tb.tween_property(imp, "position:y", y - 5.0, 0.35).set_trans(Tween.TRANS_SINE)
	tb.tween_property(imp, "position:y", y, 0.35).set_trans(Tween.TRANS_SINE)

const _CLOUD_POS := [
	[100.0, 1020.0], [1500.0, 1050.0], [400.0, 1080.0], [1200.0, 1100.0], [300.0, 1120.0],
]

func _build_clouds(coord: Dictionary, bg_design: Vector2, bg_tex: Vector2, S: float,
		map_w: float) -> void:
	var man := _load_manifest("worldmap_ui")
	if man.is_empty():
		return
	var rng := RandomNumberGenerator.new(); rng.randomize()
	for i in _CLOUD_POS.size():
		var nm := "scene_worldmap_ani_cloud%02d" % (1 + i)
		if not man.has(nm):
			continue
		var spr := _sprite_native(nm, "worldmap_ui", man, S)
		if spr == null:
			continue
		var p: Array = _CLOUD_POS[i]
		var r := _layer_to_design(coord, bg_design, bg_tex, S,
			Vector2(float(p[0]), float(p[1])))
		if not bool(r[1]):
			spr.queue_free()
			continue
		spr.position = r[0]
		spr.modulate.a = 0.85
		spr.z_index = _Z_CLOUD
		_backdrop.add_child(spr)
		_clouds.append({"node": spr, "speed": rng.randf_range(7.0, 18.0),
			"w": float(man.get(nm, {}).get("w", 120)) * S, "wrap": map_w})

func _try_click(screen_pos: Vector2) -> void:
	var content_pos := (Vector2(screen_pos.x + _scroll, screen_pos.y) if _horizontal
		else Vector2(screen_pos.x, screen_pos.y + _scroll))
	var pick := _resolve_click(content_pos)
	if pick.is_empty():
		return
	if _horizontal and pick.has("center"):
		_closeup_then_goto(String(pick["arg"]), pick["center"])
	else:
		_on_hit(String(pick["kind"]), String(pick["arg"]))

func _resolve_click(content_pos: Vector2) -> Dictionary:
	var cands: Array = []
	for h in _hits:
		if (h["rect"] as Rect2).has_point(content_pos):
			cands.append(h)
	if cands.is_empty():
		return {}
	var pick: Dictionary = {}
	if cands.size() > 1:
		for h in cands:
			if _opaque_at(h, content_pos):
				pick = h
		if pick.is_empty():
			var best := INF
			for h in cands:
				var c: Vector2 = h.get("center", (h["rect"] as Rect2).get_center())
				var dd := c.distance_squared_to(content_pos)
				if dd < best:
					best = dd; pick = h
	else:
		pick = cands[0]
	return pick

const _ALPHA_HIT := 0.35
var _img_cache: Dictionary = {}
func _opaque_at(h: Dictionary, content_pos: Vector2) -> bool:
	var spr = h.get("spr")
	if not (spr is Sprite2D) or not is_instance_valid(spr):
		return false
	var s := spr as Sprite2D
	var tex := s.texture
	if tex == null:
		return false
	var sc: float = maxf(0.0001, s.scale.x)
	var local := (content_pos - s.position) / sc
	var size := tex.get_size()
	var px := local + size * 0.5
	if px.x < 0.0 or px.y < 0.0 or px.x >= size.x or px.y >= size.y:
		return false
	var at := tex as AtlasTexture
	var base: Texture2D = at.atlas if at != null else tex
	if base == null:
		return false
	var key := base.get_rid()
	if not _img_cache.has(key):
		var im := base.get_image()
		if im == null:
			return false
		if im.is_compressed():
			im.decompress()
		_img_cache[key] = im
	var img: Image = _img_cache[key]
	if at != null:
		px += at.region.position
	var ix := int(px.x)
	var iy := int(px.y)
	if ix < 0 or iy < 0 or ix >= img.get_width() or iy >= img.get_height():
		return false
	return img.get_pixel(ix, iy).a >= _ALPHA_HIT

func _on_hit(kind: String, arg: String) -> void:
	if kind == "region":
		_mode = arg; _rebuild()
	elif kind == "node":
		_goto_target(arg)

func _closeup_then_goto(target: String, center: Vector2) -> void:
	if _busy:
		return
	_busy = true
	_dragging = false
	var sx := center.x - (_scroll if _horizontal else 0.0)
	_popup_side = "right" if sx < _vis().x * 0.5 else "left"
	var is_battle := target.begins_with("battle:")
	if is_battle:
		_play_field_fx(int(target.substr(7)))
		if not _goto_target(target):
			return
	var vis := _vis()
	var zoom := 2.2
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_content, "scale", Vector2(zoom, zoom), 0.55)
	tw.parallel().tween_property(_content, "position", vis * 0.5 - center * zoom, 0.55)
	if not is_battle:
		tw.tween_interval(0.5)
		tw.tween_callback(func(): _goto_target(target))

func _goto_target(target: String) -> bool:
	if target == "story":
		if _open_marked_story_field(StoryProgress.mark_field()):
			return true
		_busy = false
		return false
	if target.begins_with("town:"):
		if _open_marked_story_field(_piece_field(target)):
			return true
		if _mode == "yutakan" and _yutakan_phase(_region_native()) == "kades":
			_notice("카데스의 공간에서는 마을에 들어갈 수 없습니다.")
			_busy = false
			return false
		Scenes.goto("town", {"area": target.substr(5)})
	elif target == "cave":
		Scenes.goto("cave")
	elif target.begins_with("battle:"):
		var sid := target.substr(7)
		if _open_marked_story(sid):
			return true
		if _mode == "yutakan" and sid == "15" and _yutakan_phase(_region_native()) == "night":
			_notice(Data.ui("#4e3a39fd"))
			_busy = false
			return false
		if _mode == "yutakan" and sid == "15" \
				and bool(Data.kades.get("light_tower_blocked", false)) \
				and _yutakan_phase(_region_native()) == "kades":
			_notice(Data.ui("#3a9f4fe8"))
			_busy = false
			return false
		_open_dungeon_popup(_variant_stage_id(sid))
	elif target == "battle":
		Scenes.goto("battle", {})
	elif target == "colosseum":
		Scenes.goto("colosseum", {"from": "worldmap"})
	elif target == "mamorudiclab":
		Scenes.goto("mamorudiclab", {"from": "worldmap"})
	else:
		push_warning("[WorldMap] 미지원 타깃: " + target)
		return false
	return true

func _open_marked_story(stage_id: String) -> bool:
	var st: Dictionary = Data.stage(stage_id)
	if st.is_empty():
		return false
	return _open_marked_story_field(DungeonBG.base_field(DungeonBG.field_id(st)))

func _open_marked_story_field(field: int) -> bool:
	if field <= 0 or field == 999:
		return false
	if StoryProgress.pending_episode() > 0:
		return false
	var no := StoryProgress.active_episode()
	if no <= 0 or StoryProgress.seen(no) or not StoryProgress.unlocked(no):
		return false
	if Data.scenario_flow_of(no).is_empty():
		return false
	if StoryProgress.mark_field() != field:
		return false
	Scenes.goto("story", {"no": no, "part": 0, "back": "worldmap",
		"back_params": {"region": _mode}})
	return true

func _piece_field(target: String) -> int:
	for p in _region(_mode).get("pieces", []):
		if String((p as Dictionary).get("target", "")) == target:
			return int((p as Dictionary).get("field", 0))
	return 0

func _build_hud() -> void:
	MainHud.attach(self, _variant_toggles, _yutakan_phase(_region_native()))
	var hud := CanvasLayer.new()
	hud.layer = 11
	add_child(hud)
	if _mode != "overview":
		var back := Button.new()
		back.text = "← 월드맵"
		back.position = Vector2(20, _vis().y * 0.5 - 20.0)
		back.pressed.connect(func(): _mode = "overview"; _rebuild())
		hud.add_child(back)
	var gd := Button.new(); gd.text = "가이드"; gd.size = Vector2(72, 34)
	gd.position = Vector2(_vis().x - 90, 70)
	gd.pressed.connect(_open_guide); hud.add_child(gd)

func _region_native() -> Dictionary:
	if _mode == "overview":
		return {}
	return _region(_mode).get("native", {})

func _variant_stage_id(stage_id: String) -> String:
	if _mode != "yutakan" or not stage_id.is_valid_int():
		return stage_id
	var nat := _region_native()
	return str(DungeonBG.variant_field(int(stage_id),
		_is_yutakan_night(nat), _is_kades_space(nat)))

const DAILY_EXTRA_DIA := 50

func _today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]

func _daily_ok(stage_id: String) -> bool:
	var m = UserDB.get_pmeta("daily_dungeon", {})
	if not (m is Dictionary):
		return true
	return String((m as Dictionary).get(stage_id, "")) != _today()

func _daily_stamp(stage_id: String) -> void:
	var m = UserDB.get_pmeta("daily_dungeon", {})
	var d: Dictionary = (m as Dictionary).duplicate() if m is Dictionary else {}
	d[stage_id] = _today()
	UserDB.set_pmeta("daily_dungeon", d)

func _confirm_daily_extra(enter: Callable, hero: bool) -> void:
	var vis := _vis()
	var lay := CanvasLayer.new(); lay.layer = 42; add_child(lay)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT); lay.add_child(dim)
	const BW := 480.0
	const BH := 250.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190
	win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH)
	win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	lay.add_child(win)
	var l := Label.new()
	l.text = "오늘은 이미 다녀왔습니다.\n다이아 %d 개를 지불하고\n한 번 더 들어가시겠습니까?" % DAILY_EXTRA_DIA
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(0.3, 0.2, 0.06))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(BW - 60, 100); l.position = Vector2(30, 62)
	win.add_child(l)
	var ok := Button.new(); ok.text = "입장"; ok.size = Vector2(140, 42)
	ok.position = Vector2(BW * 0.5 - 150, BH - 60)
	ok.pressed.connect(func():
		if not UserDB.spend("diamond", DAILY_EXTRA_DIA):
			l.text = Data.ui("#76cd9cb3")
			return
		lay.queue_free()
		enter.call(hero))
	win.add_child(ok)
	var no := Button.new(); no.text = "취소"; no.size = Vector2(140, 42)
	no.position = Vector2(BW * 0.5 + 10, BH - 60)
	no.pressed.connect(func(): lay.queue_free()); win.add_child(no)

func _darknix_gate(st: Dictionary, layer: CanvasLayer) -> bool:
	if not Darknix.is_summon_stage(st):
		return true
	var cfg: Dictionary = st["summon"]
	var now := int(Time.get_unix_time_from_system())
	var g := Darknix.gate(cfg, UserDB.darknix(), now,
		UserDB.item_count(String(cfg.get("item", ""))), UserDB.diamond())
	if String(g.get("action", "")) == Darknix.ENTER:
		return true
	_popup_darknix_summon(cfg, g, layer)
	return false

func _popup_darknix_summon(cfg: Dictionary, g: Dictionary, src_layer: CanvasLayer) -> void:
	var act := String(g.get("action", ""))
	var vis := _vis()
	var lay := CanvasLayer.new(); lay.layer = 43; add_child(lay)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT); lay.add_child(dim)
	const BW := 500.0
	const BH := 280.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190
	win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH)
	win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	lay.add_child(win)
	var item_key := String(cfg.get("item", ""))
	var price := int(g.get("cash", 0))
	var msg := ""
	if act == Darknix.USE_ITEM:
		msg = "%s 아이템을 사용하시겠습니까?" % Data.item_name(item_key)
	elif act == Darknix.USE_CASH:
		msg = "다이아 %d 개를 사용해서\n혼돈의 틈새를 여시겠습니까?" % price
	else:
		msg = "혼돈의 틈새를 소환하는데\n%d 개의 다이아가 필요합니다.\n환전소로 가시겠습니까?" % price
	var l := Label.new()
	l.text = msg
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(0.3, 0.2, 0.06))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(BW - 60, 90); l.position = Vector2(30, 108)
	win.add_child(l)
	var icon: Node2D = null
	if act == Darknix.USE_ITEM:
		icon = _item_icon(item_key, 56.0)
	else:
		icon = AtlasUI.spr("common_ui", "common_diamond_small1", 1.0)
	if icon != null:
		icon.position = Vector2(BW * 0.5, 84.0)
		win.add_child(icon)
	var confirm := Button.new(); confirm.size = Vector2(150, 44)
	confirm.text = "소환" if act != Darknix.NO_CASH else "환전소"
	confirm.position = Vector2(BW * 0.5 - 160, BH - 62)
	confirm.pressed.connect(func():
		lay.queue_free()
		if act == Darknix.USE_ITEM:
			if not UserDB.use_item(item_key, int(g.get("item_count", 1))):
				_notice("고대 포탈이 부족합니다.")
				return
			_do_darknix_summon(cfg, src_layer)
		elif act == Darknix.USE_CASH:
			if not UserDB.spend("diamond", price):
				_notice(Data.ui("#76cd9cb3"))
				return
			_do_darknix_summon(cfg, src_layer)
		else:
			Scenes.goto("shop", {"tab": "cash", "from": "worldmap"}))
	win.add_child(confirm)
	var no := Button.new(); no.text = "취소"; no.size = Vector2(150, 44)
	no.position = Vector2(BW * 0.5 + 10, BH - 62)
	no.pressed.connect(func(): lay.queue_free()); win.add_child(no)

func _do_darknix_summon(cfg: Dictionary, src_layer: CanvasLayer) -> void:
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var v := Darknix.roll(cfg, int(Time.get_unix_time_from_system()), rng)
	if v.is_empty():
		_notice("소환에 실패했습니다.")
		return
	UserDB.darknix_summon(v)
	if is_instance_valid(src_layer):
		src_layer.queue_free()
	_notice(Data.ui("#d8bbdeb8"))
	_rebuild()

func _selected_dragon() -> Dictionary:
	return UserDB.get_dragon(UserDB.active_uid())

func _selected_gate() -> bool:
	var uid := UserDB.active_uid()
	var d := _selected_dragon()
	if uid <= 0 or d.is_empty():
		_notice("출전할 드래곤을 먼저 선택하세요.")
		return false
	if UserDB.is_down(uid):
		_popup_dragon_stun(uid)
		return false
	if _is_starving(d):
		_popup_dragon_food(uid, d)
		return false
	return true

func _popup_dragon_stun(uid: int) -> void:
	var now := int(Time.get_unix_time_from_system())
	var ct := UserDB.cure_time(uid)
	var cost := Incapacitation.instant_cost(Data.incapacitation, ct, now)
	var msg := "회복까지 %s 남았습니다.\n드래곤을 즉시 부활시키겠습니까?" \
		% Incapacitation.remain_clock(ct, now)
	MessageWindow.open(self, "행동불능", msg,
		func():
			if not UserDB.spend("diamond", cost):
				_notice(Data.ui("#76cd9cb3"))
				return
			UserDB.set_cure_time(uid, 0)
			Bgm.sfx("effect_button")
			_notice("드래곤이 회복되었습니다."),
		"확인", "취소", 0, cost)

func _popup_dragon_food(uid: int, d: Dictionary) -> void:
	var el := String(Data.get_dragon(int(d.get("id", 0))).get("element", ""))
	var key := ItemEffect.find_matching_feed(UserDB.inventory(), Data.items, el)
	if key == "":
		MessageWindow.open(self, "먹이", "해당 드래곤이 먹을 수 있는 음식이 없습니다.\n\n상점으로 이동하시겠습니까?",
			func(): Scenes.goto("shop", {"area": "elpis"}), "확인", "취소")
		return
	var nm := Data.item_name(key)
	var much := "상당히" if ItemEffect.feed_is_full(Data.item_effects, key) else "약간"
	MessageWindow.open(self, "먹이", "%s 아이템을 사용하면\n해당 드래곤의 배고픔이 %s 채워집니다.\n사용하시겠습니까?"
			% [nm, much],
		func(): _feed_dragon(uid, key), "확인", "취소")

func _feed_dragon(uid: int, key: String) -> void:
	var d := UserDB.get_dragon(uid)
	if d.is_empty() or int(UserDB.inventory().get(key, 0)) <= 0:
		return
	var el := String(Data.get_dragon(int(d.get("id", 0))).get("element", ""))
	var defs: Dictionary = Data.item_effects
	UserDB.add_item(key, -1)
	UserDB.set_dragon_field(uid, "food",
		ItemEffect.food_after_feed(defs, Data.get_item(key), key, el,
			int(d.get("food", ItemEffect.food_max(defs)))))
	UserDB.bump_quest("feeds")
	Bgm.sfx("effect_button")
	_notice("드래곤이 맛있게 먹이를 먹었습니다.")

func _is_starving(d: Dictionary) -> bool:
	return ItemEffect.is_starving(Data.item_effects,
		int(d.get("food", ItemEffect.food_max(Data.item_effects))))

func _night() -> bool:
	return _mode == "yutakan" and _is_yutakan_night(_region_native())

func _night_level_ok() -> bool:
	if not _night():
		return true
	var need := int((Data.stages.get("_variant_rules", {}) as Dictionary).get("night_min_level", 0))
	if need <= 0:
		return true
	need = mini(need, LevelSystem.cap_for(Data.level_curve, false))
	var d := _selected_dragon()
	if d.is_empty():
		return false
	return int(d.get("level", 1)) >= need

func _notice(text: String) -> void:
	Toast.show(self, text)

func _region(id: String) -> Dictionary:
	for r in Data.worldmap_regions():
		if String(r.get("id", "")) == id:
			return r
	return {}

func _add_hit(rect: Rect2, kind: String, arg: String) -> void:
	_hits.append({"rect": rect, "kind": kind, "arg": arg})

func _add_hit_node(rect: Rect2, target: String, center: Vector2, spr: Sprite2D = null) -> void:
	_hits.append({"rect": rect, "kind": "node", "arg": target, "center": center, "spr": spr})

func _vis() -> Vector2:
	return get_viewport_rect().size

func _fw(frame: String) -> float:
	return float(_manifest.get(frame, {}).get("w", 100))

func _fh(frame: String) -> float:
	return float(_manifest.get(frame, {}).get("h", 100))

func _load_manifest(dir: String) -> Dictionary:
	return AtlasUI.manifest(dir)

func _sprite(name: String, scale := 1.0) -> Sprite2D:
	if name == "": return null
	var p := "res://assets/converted/worldmap_maps/%s.tres" % name
	if not ResourceLoader.exists(p): return null
	var s := Sprite2D.new()
	s.texture = load(p)
	s.material = _pma
	s.scale = Vector2(scale, scale)
	return s

var _popup_side := "right"

func _open_dungeon_popup(stage_id: String) -> void:
	var st: Dictionary = Field.apply_variant(Data.stage(stage_id),
		Drops.MODE_NIGHT if _night() else Drops.MODE_NORMAL)
	var wman := _load_manifest("worldmap_ui")
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 26
	add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var S := Design.ASSET_SCALE
	var fid := int(st.get("id", 0))
	var kades := fid >= 600 and fid < 700
	var special := fid == 6 or fid == 8
	var pw := 409.0 * S
	var ph := 491.0 * S
	var right := _popup_side == "right"
	var root := Node2D.new()
	root.position = Vector2(vis.x - pw if right else 0.0, vis.y * 0.5 - ph * 0.5)
	layer.add_child(root)
	var dock_x := root.position.x
	var bg := _sprite_native("scene_worldmap_info_bg2" if kades else "scene_worldmap_info_bg",
		"worldmap_ui", wman, S)
	if bg:
		bg.position = Vector2(pw * 0.5, ph * 0.5)
		bg.flip_h = not right
		root.add_child(bg)
	var cw := pw - 80.0
	var ch := ph - 20.0
	var pcx := pw * 0.5 + 30.0 if right else (pw - 60.0) * 0.5
	var px0 := pcx - cw * 0.5
	var py0 := ph * 0.5 - ch * 0.5
	var tname := Data.stage_display_name(st, true)
	var title := _bmf_ui(1.0)
	title.text = tname if special else "레벨 %d %s" % [int(st.get("level", 1)), tname]
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(cw, 34); title.position = Vector2(px0, py0 + 23.0 - 17.0)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(title)
	var fw := 242.0 * S
	var fh := 160.0 * S
	var fcx := px0 + cw * 0.5
	var fcy := py0 + 40.0 + fh * 0.5
	var iw := 226.0 * S
	var ih := 144.0 * S
	var clip: Control = null
	var bgp := DungeonBG.path_for(st)
	if bgp != "":
		var prev := TextureRect.new()
		prev.texture = load(bgp)
		prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		prev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		prev.size = Vector2(iw, ih)
		prev.position = Vector2(fcx - iw * 0.5, fcy - ih * 0.5)
		prev.mouse_filter = Control.MOUSE_FILTER_IGNORE
		prev.clip_contents = true
		root.add_child(prev)
		DungeonBG.add_overlay(prev, st)
		clip = prev
	var fr := _sprite_native("scene_worldmap_info_img_frame2" if kades
		else "scene_worldmap_info_img_frame", "worldmap_ui", wman, S)
	if fr: fr.position = Vector2(fcx, fcy); root.add_child(fr)
	var frame_holder := Node2D.new()
	frame_holder.position = Vector2(fcx - fw * 0.5, fcy - fh * 0.5)
	root.add_child(frame_holder)
	if special:
		var bar := _sprite_native("scene_worldmap_info_bar", "worldmap_ui", wman, S)
		if bar:
			var bh := float(wman.get("scene_worldmap_info_bar", {}).get("h", 17)) * S
			bar.position = Vector2(fw * 0.5, 15.0 + bh * 0.5)
			frame_holder.add_child(bar)
			var bl := _bmf_ui((bh - 8.75 * S) / bh)
			bl.text = "특수 지역"
			bl.add_theme_color_override("font_color", Color.WHITE)
			bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			bl.size = Vector2(140.0, bh)
			bl.position = bar.position - bl.size * 0.5
			frame_holder.add_child(bl)
	var elem := String(st.get("element", ""))
	if elem != "":
		var eman := _load_manifest("item_small_ui")
		var ei := _sprite_native("item_item_small_ele_%s" % elem, "item_small_ui", eman, 0.56 * S)
		if ei:
			var ew := float(eman.get("item_item_small_ele_%s" % elem, {}).get("w", 64)) * 0.56 * S
			var eh := float(eman.get("item_item_small_ele_%s" % elem, {}).get("h", 64)) * 0.56 * S
			ei.position = Vector2(fw - 4.0 - ew * 0.5, fh - 6.0 - eh * 0.5)
			frame_holder.add_child(ei)
	var row_w := cw - 100.0
	var row_top := py0 + 40.0 + fh + 2.0
	var row_cy := row_top + 65.0 - (30.0 if fid == 24 or fid == 25 else 0.0)
	var dragons: Array = st.get("dragons", [])
	if kades:
		_build_artifact_row(root, layer, st, wman, Vector2(px0 + cw * 0.5, row_cy), row_w, S)
	elif not dragons.is_empty():
		_build_dragon_row(root, layer, st, wman, dragons,
			Vector2(px0 + cw * 0.5, row_cy), row_w, clip, frame_holder, Vector2(fw, fh), S)
	elif st.has("drops"):
		_build_reward_row(root, layer, st, wman, (px0 + cw * 0.5) * 2.0, row_cy, S)
	var desc := String(st.get("desc", ""))
	if desc != "":
		var dl := _bmf_ui(0.9, "common")
		dl.text = desc
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.add_theme_color_override("font_color",
			Color8(202, 182, 207) if kades else Color8(129, 67, 29))
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var dw := pw - 100.0
		dl.size = Vector2(dw, 160.0)
		dl.position = Vector2(px0 + cw * 0.5 - dw * 0.5,
			row_top + 130.0 - (35.0 if fid == 24 or fid == 25 else 5.0))
		root.add_child(dl)
	if bool(st.get("once_per_day", false)):
		_build_try_field(root, layer, stage_id, wman, pw, ph - 116.0 * S, S)
	_build_popup_buttons(root, layer, st, stage_id, Vector2(px0, py0), Vector2(cw, ch), fid, kades, S)
	var xb := TextureButton.new()
	var xt := "res://assets/converted/common_ui/common_close_btn.tres"
	if ResourceLoader.exists(xt):
		xb.texture_normal = load(xt)
		xb.scale = Vector2(S, S)
		xb.pivot_offset = Vector2(19, 19)
	var xc := Vector2(pw - 50.0 if right else 50.0, 45.0)
	xb.position = Vector2(dock_x, root.position.y) + xc - Vector2(19.0 * S, 19.0 * S)
	var close_popup := func():
		if is_instance_valid(layer):
			layer.queue_free()
		_reset_zoom()
	xb.pressed.connect(close_popup)
	layer.add_child(xb)
	var panel := Rect2(Vector2(dock_x, root.position.y), Vector2(pw, ph))
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and not panel.has_point(e.position):
			close_popup.call())
	root.position.x = dock_x + (pw if right else -pw)
	var stw := create_tween()
	stw.tween_interval(0.15)
	stw.tween_property(root, "position:x", dock_x, 0.07)

var _popup_bmf: Dictionary = {}
func _bmf_ui(scale: float, kind := "subtitle") -> Label:
	if not _popup_bmf.has(kind):
		var p := "res://assets/converted/font_ui/font_%s.fnt" % kind
		var f: FontFile = load(p) if ResourceLoader.exists(p) else null
		if f:
			f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
		_popup_bmf[kind] = f
	var l := Label.new()
	var fnt: FontFile = _popup_bmf[kind]
	if fnt:
		l.add_theme_font_override("font", fnt)
		var base: float = float(fnt.fixed_size) if fnt.fixed_size > 0 else 19.0
		l.add_theme_font_size_override("font_size", int(round(base * Design.ASSET_SCALE * scale)))
	else:
		l.add_theme_font_size_override("font_size", int(round(25.0 * scale)))
	l.add_theme_color_override("font_color", Color8(129, 67, 29))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _dragon_slot_offsets(n: int, row_w: float, k: float) -> Array:
	var step_x := (row_w / 5.0 + 3.0) * k
	var step_y := 70.0 * k
	var out: Array = []
	if n <= 1:
		out.append(Vector2.ZERO)
		return out
	var top_n: int = n if n <= 4 else int(ceil(n / 2.0))
	var bot_n := n - top_n
	for i in top_n:
		var x := (float(i) - (float(top_n) - 1.0) * 0.5) * step_x
		out.append(Vector2(x, -step_y * 0.5 if bot_n > 0 else 0.0))
	for i in bot_n:
		var x := (float(i) - (float(bot_n) - 1.0) * 0.5) * step_x
		out.append(Vector2(x, step_y * 0.5))
	return out

func _build_dragon_row(root: Node2D, layer: CanvasLayer, st: Dictionary, wman: Dictionary,
		dragons: Array, center: Vector2, row_w: float, clip: Control,
		frame_holder: Node2D, fsize: Vector2, S: float) -> void:
	var fid := int(st.get("id", 0))
	var special := fid == 6 or fid == 8
	var k := 1.0 if dragons.size() >= 5 else 1.1
	var offs := _dragon_slot_offsets(dragons.size(), row_w, k)
	for i in dragons.size():
		var d: Dictionary = dragons[i]
		var did := int(d.get("id", 0))
		var hero := bool(d.get("hero", false)) and not special
		var seen := UserDB.dex_seen(did)
		var pos := center + (offs[i] as Vector2)
		var bg := _sprite_native("scene_worldmap_info_dragon_bg", "worldmap_ui", wman, S * k)
		if bg: bg.position = pos; root.add_child(bg)
		var thumb := _dragon_box_sprite(did, 0.6 * S * k)
		if thumb: thumb.position = pos; root.add_child(thumb)
		var fr_name: String
		if seen:
			fr_name = "scene_worldmap_info_hero_dragon_frame" if hero \
				else "scene_worldmap_info_dragon_frame"
		else:
			fr_name = "scene_worldmap_info_no_hero_dragon_frame" if hero \
				else "scene_worldmap_info_no_dragon_frame"
		var fr := _sprite_native(fr_name, "worldmap_ui", wman, S * k)
		if fr: fr.position = pos; root.add_child(fr)
		var hit := Button.new(); hit.flat = true
		hit.size = Vector2(56.0, 50.0) * S * k
		hit.position = root.position + pos - hit.size * 0.5
		hit.pressed.connect(func():
			if is_instance_valid(frame_holder):
				_popup_dragon_preview(did, clip, frame_holder, fsize, S))
		layer.add_child(hit)

func _build_artifact_row(root: Node2D, layer: CanvasLayer, st: Dictionary, wman: Dictionary,
		center: Vector2, row_w: float, S: float) -> void:
	var base_f := str(int(st.get("base_field", st.get("id", 0))))
	var types: Array = Data.drops.get("kades", {}).get("artifact_by_dungeon", {}).get(base_f, [])
	if types.is_empty():
		return
	var k := 1.1
	var offs := _dragon_slot_offsets(types.size(), row_w, k)
	for i in types.size():
		var tname := String(types[i])
		var pos := center + (offs[i] as Vector2)
		var bg := _sprite_native("scene_worldmap_info_dragon_bg", "worldmap_ui", wman, S * k)
		if bg: bg.position = pos; root.add_child(bg)
		var tex := Icons.texture("artifact", "%s:0" % tname)
		if tex:
			var ic := Sprite2D.new()
			ic.texture = tex
			ic.material = _pma
			var tw_px: float = maxf(1.0, float(tex.get_width()))
			ic.scale = Vector2.ONE * (34.0 * S * k / tw_px)
			ic.position = pos
			root.add_child(ic)
		var fr := _sprite_native("scene_worldmap_info_dragon_frame2", "worldmap_ui", wman, S * k)
		if fr: fr.position = pos; root.add_child(fr)
		var hit := Button.new(); hit.flat = true
		hit.size = Vector2(56.0, 50.0) * S * k
		hit.position = root.position + pos - hit.size * 0.5
		hit.pressed.connect(func(): _reward_tip(layer, root.position + pos, tname, S))
		layer.add_child(hit)

func _dragon_box_sprite(id: int, scale: float) -> Sprite2D:
	for stg in ["adult", "child", "baby"]:
		var p := "res://assets/converted/portrait_%d/dragon_dragon_%d_box_%s.tres" % [id, id, stg]
		if ResourceLoader.exists(p):
			var s := Sprite2D.new()
			s.texture = load(p)
			s.material = _pma
			s.scale = Vector2(scale, scale)
			return s
	return null

func _popup_dragon_preview(did: int, clip: Control, frame_holder: Node2D,
		fsize: Vector2, S: float) -> void:
	var info := Data.get_dragon(did)
	for key in ["prev_spine", "prev_stars"]:
		if clip and clip.has_meta(key):
			var old = clip.get_meta(key)
			if is_instance_valid(old) and old is Node:
				(old as Node).queue_free()
			clip.remove_meta(key)
	if frame_holder != null and is_instance_valid(frame_holder) \
			and frame_holder.has_meta("prev_name"):
		var oldn = frame_holder.get_meta("prev_name")
		if is_instance_valid(oldn) and oldn is Node:
			(oldn as Node).queue_free()
		frame_holder.remove_meta("prev_name")
	if clip == null or not is_instance_valid(clip):
		return
	var cwid := clip.size.x
	var chgt := clip.size.y
	var K := 0.29
	var yf := chgt / (692.0 * K)
	var sp := Icons.spine_scene(did, "adult")
	if sp != "":
		var base_s := 1.7 * K
		var holder := Node2D.new()
		holder.position = Vector2(cwid * 0.5, chgt - 256.0 * K * yf)
		holder.scale = Vector2(base_s, base_s)
		holder.modulate.a = 0.0
		clip.add_child(holder)
		clip.set_meta("prev_spine", holder)
		var inst = (load(sp) as PackedScene).instantiate()
		holder.add_child(inst)
		var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		if ap:
			for cand in ["love", "wait", "animation"]:
				if ap.has_animation(cand):
					ap.get_animation(cand).loop_mode = Animation.LOOP_LINEAR
					ap.play(cand)
					break
		var tw := holder.create_tween()
		tw.tween_property(holder, "modulate:a", 1.0, 0.5)
		tw.parallel().tween_property(holder, "scale", Vector2.ONE * base_s * (1.9 / 1.7), 0.5)
		tw.tween_property(holder, "scale", Vector2.ONE * base_s, 0.25)
		tw.tween_interval(6.5)
		tw.tween_property(holder, "modulate:a", 0.0, 1.0)
		tw.tween_callback(holder.queue_free)
	var stars := int(info.get("star", 0))
	if stars > 0:
		var srow := Node2D.new()
		srow.position = Vector2(cwid * 0.5, 100.0 * K * yf)
		srow.scale = Vector2(2.5 * K, 2.5 * K)
		srow.z_index = 200
		clip.add_child(srow)
		clip.set_meta("prev_stars", srow)
		var man := _load_manifest("common_ui")
		var sw := float(man.get("common_eggclass", {}).get("w", 19)) * S
		for i in stars:
			var s := _sprite_native("common_eggclass", "common_ui", man, S)
			if s == null: break
			s.position = Vector2((float(i) - (float(stars) - 1.0) * 0.5) * sw, 0)
			s.scale = Vector2.ZERO
			srow.add_child(s)
			var stw := s.create_tween()
			stw.tween_interval(0.1 * i)
			stw.tween_property(s, "rotation_degrees", 180.0, 0.25)
			stw.parallel().tween_property(s, "scale", Vector2.ONE * S, 0.25)
			stw.tween_property(s, "scale", Vector2(0.9, 1.1) * S, 0.1)
			stw.tween_property(s, "scale", Vector2(1.1, 0.9) * S, 0.1)
			stw.tween_property(s, "scale", Vector2.ONE * S, 0.1)
		var rtw := srow.create_tween()
		rtw.tween_interval(1.5)
		rtw.tween_property(srow, "scale", Vector2(1.25, 1.25), 0.15)
		rtw.tween_interval(1.0)
		rtw.tween_callback(srow.queue_free)
	var nm := String(info.get("name", ""))
	if nm != "":
		var tip := NinePatchRect.new()
		tip.z_index = 200
		tip.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres")
		tip.patch_margin_left = 20; tip.patch_margin_top = 20
		tip.patch_margin_right = 20; tip.patch_margin_bottom = 4
		var l := _bmf_ui(1.0, "common")
		l.text = nm
		l.add_theme_color_override("font_color", Color.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var lw := 26.0 * nm.length()
		tip.size = Vector2(lw + 25.0, 44.0)
		tip.pivot_offset = Vector2(tip.size.x * 0.5, tip.size.y)
		tip.position = Vector2(fsize.x * 0.5 - tip.size.x * 0.5, fsize.y - 20.0 - tip.size.y)
		tip.modulate.a = 0.0
		tip.scale = Vector2(0.1, 0.1)
		frame_holder.add_child(tip)
		frame_holder.set_meta("prev_name", tip)
		l.size = tip.size
		tip.add_child(l)
		var btw := tip.create_tween()
		btw.tween_property(tip, "modulate:a", 1.0, 0.25)
		btw.parallel().tween_property(tip, "scale", Vector2(1.2, 1.2), 0.25)
		btw.parallel().tween_property(tip, "position:y", tip.position.y - 30.0, 0.25)
		btw.tween_property(tip, "scale", Vector2(1.05, 1.05), 0.5)
		btw.parallel().tween_property(tip, "position:y", tip.position.y, 0.5) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		btw.tween_interval(1.0)
		btw.tween_property(tip, "modulate:a", 0.0, 1.0)
		btw.tween_callback(tip.queue_free)

func _build_popup_buttons(root: Node2D, layer: CanvasLayer, st: Dictionary, stage_id: String,
		porg: Vector2, psize: Vector2, fid: int, kades: bool, S: float) -> void:
	var region := _mode
	var daily := bool(st.get("once_per_day", false))
	var enter := func(hero: bool):
		if daily:
			_daily_stamp(stage_id)
		if is_instance_valid(layer):
			layer.queue_free()
		Scenes.goto("adventure", {"stage": stage_id, "region": region, "hero": hero,
			"night": _night(), "run_seed": randi()})
	var go := func(hero: bool):
		if not _darknix_gate(st, layer):
			return
		if not _selected_gate():
			return
		if not _night_level_ok():
			_notice(Data.ui("#475fb317"))
			return
		if daily and not _daily_ok(stage_id):
			_confirm_daily_extra(enter, hero)
			return
		enter.call(hero)
	var cx := porg.x + psize.x * 0.5
	var by := porg.y + psize.y - 60.0
	var bw := 160.0
	var bh := 65.0
	if fid == 6:
		_popup_button(root, Data.ui("#e479dc52"), "9patch_btn",
			Vector2(cx - 110.0, by - bh * 0.5), Vector2(220.0, bh), func(): go.call(false))
		return
	if kades:
		var kb := _popup_button(root, "일반", "9patch_btn10",
			Vector2(cx - bw * 0.5, by - bh * 0.5), Vector2(bw, bh), func(): go.call(false))
		var kman := _load_manifest("worldmap_ui")
		var ki := _sprite_native("scene_worldmap_icon_kades", "worldmap_ui", kman, S)
		if ki and kb:
			ki.position = Vector2(32.0, bh * 0.5)
			kb.add_child(ki)
		return
	var no_auto := fid == 8 or fid == 24 or fid == 25
	var nx := cx - bw * 0.5 - (10.0 if no_auto else 20.0)
	var hx := cx + bw * 0.5 + (10.0 if no_auto else -10.0)
	_popup_button(root, "일반", "9patch_btn",
		Vector2(nx - bw * 0.5, by - bh * 0.5), Vector2(bw, bh), func(): go.call(false))
	var hero_btn := _popup_button(root, "영웅", "9patch_btn6",
		Vector2(hx - bw * 0.5, by - bh * 0.5), Vector2(bw, bh), func(): go.call(true))
	if hero_btn:
		var lab := hero_btn.get_node_or_null("label")
		if lab is Label:
			(lab as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			(lab as Label).position.x = bw * 0.5 - 25.0
		var cman := _load_manifest("common_ui")
		var skull := _sprite_native("common_mode_skull", "common_ui", cman, S)
		if skull:
			var sw := float(cman.get("common_mode_skull", {}).get("w", 30)) * S
			skull.position = Vector2(15.0 + sw * 0.5, bh * 0.5)
			hero_btn.add_child(skull)
	if not no_auto:
		var aman := _load_manifest("adventure_ui")
		var aic := _sprite_native("scene_adventure_auto", "adventure_ui", aman, 0.5 * S)
		var ab := _popup_button(root, "", "9patch_btn4",
			Vector2(hx + bw * 0.5 + 40.0 - 30.0, by - 27.0), Vector2(60.0, 54.0), func():
				var on := AdvAuto.toggle()
				Bgm.sfx("effect_button")
				if is_instance_valid(aic):
					aic.visible = on)
		var abg := _sprite_native("scene_adventure_auto_bg", "adventure_ui", aman, 0.5 * S)
		if abg and ab: abg.position = Vector2(30.0, 27.0); ab.add_child(abg)
		if aic and ab:
			aic.position = Vector2(30.0, 27.0)
			aic.visible = AdvAuto.enabled()
			ab.add_child(aic)

func _item_icon(key: String, target: float) -> Sprite2D:
	var p := Data.item_icon_path(key)
	if p == "" or not ResourceLoader.exists(p):
		return null
	var tex: Texture2D = load(p)
	var s := Sprite2D.new()
	s.texture = tex
	s.material = _pma
	var w: float = maxf(1.0, float(tex.get_width()))
	s.scale = Vector2(target / w, target / w)
	return s

func _build_reward_row(root: Node2D, layer: CanvasLayer, st: Dictionary, wman: Dictionary,
		pw: float, y: float, S: float) -> void:
	var cells: Array = []
	var raw = st.get("drops", [])
	var legacy := typeof(raw) == TYPE_ARRAY
	var tables: Array = []
	if legacy:
		tables.append([raw, false])
	elif raw is Dictionary:
		tables.append([raw.get("normal", []), false])
		tables.append([raw.get("hero", []), true])
	for t in tables:
		for dp in (t[0] as Array):
			var d: Dictionary = dp
			var key := String(d.get("item", d.get("key", "")))
			if key == "": continue
			var lo := int(d.get("min", 1))
			var hi := int(d.get("max", lo))
			cells.append({"item": key, "count": lo, "hero": bool(t[1])})
			if hi != lo:
				cells.append({"item": key, "count": hi, "hero": bool(t[1])})
			if legacy and d.has("hero_min"):
				cells.append({"item": key, "count": int(d["hero_min"]), "hero": true})
				var hhi := int(d.get("hero_max", d["hero_min"]))
				if hhi != int(d["hero_min"]):
					cells.append({"item": key, "count": hhi, "hero": true})
	if cells.is_empty():
		return
	var n: int = mini(cells.size(), 5)
	for i in n:
		var c: Dictionary = cells[i]
		var frame := "scene_worldmap_info_hero_dragon_frame" if bool(c["hero"]) \
			else "scene_worldmap_info_dragon_frame"
		var cx := pw * 0.5 + (float(i) - (float(n) - 1.0) * 0.5) * 62.0 * S
		var bg := _sprite_native("scene_worldmap_info_dragon_bg", "worldmap_ui", wman, S)
		if bg: bg.position = Vector2(cx, y); root.add_child(bg)
		var ic := _item_icon(String(c["item"]), 38.0 * S)
		if ic: ic.position = Vector2(cx, y); root.add_child(ic)
		var fr := _sprite_native(frame, "worldmap_ui", wman, S)
		if fr: fr.position = Vector2(cx, y); root.add_child(fr)
		var cl := Label.new()
		cl.text = str(int(c["count"]))
		cl.add_theme_font_size_override("font_size", 17)
		cl.add_theme_color_override("font_color", Color(0.25, 0.15, 0.04))
		cl.add_theme_color_override("font_outline_color", Color(1, 0.97, 0.88, 0.9))
		cl.add_theme_constant_override("outline_size", 4)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cl.size = Vector2(46.0 * S, 22.0)
		cl.position = Vector2(cx - 44.0 * S * 0.5, y + 6.0 * S)
		root.add_child(cl)
		var hit := Button.new(); hit.flat = true
		hit.size = Vector2(52.0 * S, 52.0 * S)
		hit.position = root.position + Vector2(cx, y) - hit.size * 0.5
		var nm := Data.item_name(String(c["item"]))
		hit.pressed.connect(func(): _reward_tip(layer, root.position + Vector2(cx, y), nm, S))
		layer.add_child(hit)

func _reward_tip(layer: CanvasLayer, at: Vector2, text: String, S: float) -> void:
	var tip := NinePatchRect.new()
	tip.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres")
	tip.patch_margin_left = 15; tip.patch_margin_top = 15
	tip.patch_margin_right = 15; tip.patch_margin_bottom = 15
	var w: float = maxf(90.0, float(text.length()) * 22.0)
	tip.size = Vector2(w, 44.0)
	tip.position = at + Vector2(26.0 * S, -46.0 * S)
	layer.add_child(tip)
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(1, 0.97, 0.9))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = tip.size
	tip.add_child(l)
	var t := tip.create_tween()
	t.tween_interval(1.1)
	t.tween_property(tip, "modulate:a", 0.0, 0.3)
	t.tween_callback(tip.queue_free)

const UNO_TRY_PER_DAY := 1

func _build_try_field(root: Node2D, layer: CanvasLayer, stage_id: String, wman: Dictionary,
		pw: float, y: float, S: float) -> void:
	var left := _daily_ok(stage_id)
	var cman := _load_manifest("common_ui")
	var bw := 150.0 * S
	var bh := 30.0 * S
	var bx := pw * 0.5 - bw * 0.5
	var bar := ColorRect.new()
	bar.color = Color(0.40, 0.33, 0.24, 0.85)
	bar.size = Vector2(bw, bh)
	bar.position = Vector2(bx, y - bh * 0.5)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	var ic := _sprite_native("scene_worldmap_icon_unocount", "worldmap_ui", wman, S)
	if ic: ic.position = Vector2(bx, y); root.add_child(ic)
	var cnt := Label.new()
	cnt.text = str(1 if left else 0)
	cnt.add_theme_font_size_override("font_size", 20)
	cnt.add_theme_color_override("font_color", Color(1, 1, 1))
	cnt.add_theme_color_override("font_outline_color", Color(0.18, 0.12, 0.05))
	cnt.add_theme_constant_override("outline_size", 4)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cnt.size = Vector2(bw, bh); cnt.position = Vector2(bx, y - bh * 0.5)
	root.add_child(cnt)
	var note := Label.new()
	note.text = "(1일 최대 %d회 입장가능 / 매일 0시에 초기화 됩니다)" % UNO_TRY_PER_DAY
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.42, 0.30, 0.16))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.size = Vector2(pw - 40.0, 20.0)
	note.position = Vector2(20.0, y + 16.0 * S)
	root.add_child(note)
	var chg := _sprite_native("common_charge", "common_ui", cman, S)
	if chg:
		chg.position = Vector2(bx + bw, y)
		root.add_child(chg)
		var cb := Button.new(); cb.flat = true
		cb.size = Vector2(40.0 * S, 40.0 * S)
		cb.position = root.position + Vector2(bx + bw, y) - cb.size * 0.5
		cb.pressed.connect(func():
			if left:
				return
			_confirm_daily_recharge(stage_id, layer))
		layer.add_child(cb)

func _confirm_daily_recharge(stage_id: String, popup_layer: CanvasLayer) -> void:
	var msg := "다이아 %d개를 소모하여" % DAILY_EXTRA_DIA
	msg += "
입장 횟수 1회를 충전할 수 있습니다.
충전하시겠습니까?"
	_confirm_dialog(msg,
		func():
			if not UserDB.spend("diamond", DAILY_EXTRA_DIA):
				_notice(Data.ui("#76cd9cb3"))
				return
			var m = UserDB.get_pmeta("daily_dungeon", {})
			var dd: Dictionary = (m as Dictionary).duplicate() if m is Dictionary else {}
			dd.erase(stage_id)
			UserDB.set_pmeta("daily_dungeon", dd)
			if is_instance_valid(popup_layer):
				popup_layer.queue_free()
			_open_dungeon_popup(stage_id))

func _confirm_dialog(text: String, on_ok: Callable) -> void:
	var vis := _vis()
	var lay := CanvasLayer.new(); lay.layer = 44; add_child(lay)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT); lay.add_child(dim)
	const BW := 480.0
	const BH := 250.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190
	win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH)
	win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	lay.add_child(win)
	var l := Label.new(); l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(0.3, 0.2, 0.06))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(BW - 60, 100); l.position = Vector2(30, 62)
	win.add_child(l)
	var ok := Button.new(); ok.text = "확인"; ok.size = Vector2(140, 42)
	ok.position = Vector2(BW * 0.5 - 150, BH - 60)
	ok.pressed.connect(func():
		lay.queue_free()
		on_ok.call())
	win.add_child(ok)
	var no := Button.new(); no.text = "취소"; no.size = Vector2(140, 42)
	no.position = Vector2(BW * 0.5 + 10, BH - 60)
	no.pressed.connect(func(): lay.queue_free()); win.add_child(no)

func _popup_button(parent: Node2D, text: String, frame: String, pos: Vector2, size: Vector2,
		cb: Callable) -> Control:
	var np := NinePatchRect.new()
	var tex: Texture2D = load("res://assets/converted/ninepatch_ui/%s.tres" % frame)
	np.texture = tex
	np.patch_margin_left = 20; np.patch_margin_top = 20
	np.patch_margin_right = maxi(1, tex.get_width() - 24) if tex else 20
	np.patch_margin_bottom = maxi(1, tex.get_height() - 24) if tex else 20
	np.size = size; np.position = pos
	parent.add_child(np)
	var l := _bmf_ui(1.0)
	l.name = "label"
	l.text = text
	l.add_theme_color_override("font_color", Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = size
	np.add_child(l)
	var b := Button.new(); b.flat = true; b.size = size
	b.pressed.connect(cb)
	np.add_child(b)
	return np

func _reset_zoom() -> void:
	_busy = false
	_clear_field_fx()
	if not is_instance_valid(_content): return
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_content, "scale", Vector2.ONE, 0.4)
	tw.parallel().tween_property(_content, "position", Vector2.ZERO, 0.4)
