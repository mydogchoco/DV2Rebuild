extends Node

var dragons: Dictionary = {}
var stat_table: Dictionary = {}
var new_game: Dictionary = {}
var dex_meta: Dictionary = {}
var items: Dictionary = {}
var items_meta: Dictionary = {}
var combat: Dictionary = {}
var skills: Dictionary = {}
var worldmap: Dictionary = {}
var dragon_skills: Dictionary = {}
var stages: Dictionary = {}
var scenario: Dictionary = {}
var ui_text: Dictionary = {}
var scenario_flow: Dictionary = {}
var tutorial_flow: Dictionary = {}
var story_battles: Dictionary = {}
var story_monsters: Dictionary = {}
var story: Dictionary = {}
var story_subquest: Dictionary = {}
var item_effects: Dictionary = {}
var battle_missions: Dictionary = {}
var egg_fragments: Dictionary = {}
var team_buffs: Dictionary = {}
var combine_egg: Dictionary = {}
var combine_item: Dictionary = {}
var box_loot: Dictionary = {}
var upgrade_egg: Dictionary = {}
var equip_effects: Dictionary = {}
var skill_awaken: Dictionary = {}
var level_curve: Dictionary = {}
var dragon_voices: Dictionary = {}
var gems: Dictionary = {}
var titles: Dictionary = {}
var icon_map: Dictionary = {}
var equipment: Dictionary = {}
var item_descriptions: Dictionary = {}
var npc_lines_doc: Dictionary = {}
var drops: Dictionary = {}
var shop: Dictionary = {}
var laboratory: Dictionary = {}
var promote: Dictionary = {}
var npc_talk: Dictionary = {}
var npc_face: Dictionary = {}
var admin_story: Dictionary = {}
var card_game: Dictionary = {}
var imp_shop: Dictionary = {}
var monster_drops: Dictionary = {}
var adventure_events: Dictionary = {}
var awaken: Dictionary = {}
var gacha_eggs: Dictionary = {}
var kades: Dictionary = {}
var colosseum: Dictionary = {}
var skill_scrolls: Dictionary = {}
var incapacitation: Dictionary = {}
var card_codes: Dictionary = {}
var dex_comments: Dictionary = {}

func _ready() -> void:
	_load_dragons("res://data/dragons.json")
	stat_table = _load_json("res://data/stat_table.json")
	new_game = _load_json("res://data/new_game.json")
	dex_meta = _load_json("res://data/dex_meta.json")
	items = _load_json("res://data/items.json")
	items_meta = {}
	for k in items.keys():
		if String(k).begins_with("_"):
			items_meta[k] = items[k]
			items.erase(k)
	combat = _load_json("res://data/combat.json")
	skills = _load_json("res://data/skills.json")
	worldmap = _load_json("res://data/worldmap.json")
	dragon_skills = _load_json("res://data/dragon_skills.json")
	stages = _load_json("res://data/stages.json")
	egg_fragments = _load_json("res://data/egg_fragments.json")
	team_buffs = _load_json("res://data/team_buffs.json")
	combine_egg = _load_json("res://data/combine_egg.json")
	combine_item = _load_json("res://data/combine_item.json")
	box_loot = _load_json("res://data/box_loot.json")
	upgrade_egg = _load_json("res://data/upgrade_egg.json")
	skill_awaken = _load_json("res://data/skill_awaken.json")
	equip_effects = _load_json("res://data/equip_effects.json")
	level_curve = _load_json("res://data/level_curve.json")
	dragon_voices = _load_json("res://data/dragon_voices.json")
	battle_missions = _load_json("res://data/battle_missions.json")
	item_effects = _load_json("res://data/item_effects.json")
	npc_lines_doc = _load_json("res://data/npc_lines.json")
	gems = _load_json("res://data/gems.json")
	equipment = _load_json("res://data/equipment.json")
	item_descriptions = _load_json("res://data/item_descriptions.json")
	drops = _load_json("res://data/drops.json")
	icon_map = _load_json("res://data/icon_map.json")
	titles = _load_json("res://data/titles.json")
	scenario = _load_json("res://data/scenario.json")
	ui_text = _load_json("res://data/ui_text.json")
	scenario_flow = _load_json("res://data/scenario_flow.json")
	tutorial_flow = _load_json("res://data/tutorial_flow.json")
	story = _load_json("res://data/story.json")
	story_subquest = _load_json("res://data/story_subquest.json")
	story_battles = _load_json("res://data/story_battles.json")
	story_monsters = _load_json("res://data/story_monsters.json")
	shop = _load_json("res://data/shop.json")
	npc_face = _load_json("res://data/npc_face.json")
	admin_story = _load_json("res://data/admin_story.json")
	promote = _load_json("res://data/promote.json")
	laboratory = _load_json("res://data/laboratory.json")
	npc_talk = _load_json("res://data/npc_talk.json")
	gacha_eggs = _load_json("res://data/gacha_eggs.json")
	kades = _load_json("res://data/kades.json")
	colosseum = _load_json("res://data/colosseum.json")
	incapacitation = _load_json("res://data/incapacitation.json")
	card_codes = _load_json("res://data/card_codes.json")
	skill_scrolls = _load_json("res://data/skill_scrolls.json")
	awaken = _load_json("res://data/awaken.json")
	card_game = _load_json("res://data/card_game.json")
	adventure_events = _load_json("res://data/adventure_events.json")
	imp_shop = _load_json("res://data/imp_shop.json")
	if FileAccess.file_exists("res://data/monster_drops.json"):
		monster_drops = _load_json("res://data/monster_drops.json")
	if FileAccess.file_exists("res://data/dex_comments.json"):
		dex_comments = _load_json("res://data/dex_comments.json")
	print("[Data] %d dragons, %d items, stat types=%s" % [
		dragons.size(), items.size(), str(stat_table.keys())])

func ui(key: String) -> String:
	return UiText.get_text(key)

func data_path(file_name: String) -> String:
	var side := "res://data/text/" + file_name
	return side if FileAccess.file_exists(side) else "res://data/" + file_name

func _load_json(path: String):
	var f := FileAccess.open(data_path(path.get_file()), FileAccess.READ)
	if f == null:
		push_error("[Data] missing " + path); return {}
	return JSON.parse_string(f.get_as_text())

func equipment_description(catalog_key: String) -> String:
	return String((item_descriptions.get("equipment", {}) as Dictionary).get(catalog_key, ""))

func gem_description(category_key: String) -> String:
	return String((item_descriptions.get("gem_categories", {}) as Dictionary).get(category_key, ""))

func _load_dragons(path: String) -> void:
	var arr = _load_json(path)
	for d in arr:
		if d.has("element") and typeof(d["element"]) != TYPE_STRING:
			d["element"] = ""
		dragons[int(d["id"])] = d

func get_dragon(id: int) -> Dictionary:
	return dragons.get(id, {})

func new_game_def() -> Dictionary:
	return new_game

func dragon_dex_meta(id: int) -> Dictionary:
	return dex_meta.get(str(id), {})

func dragon_comment(id: int) -> String:
	var over := String(dex_comments.get(str(id), ""))
	if over != "":
		return over
	return String(get_dragon(id).get("desc", ""))

func dragon_ids() -> Array:
	var ids := []
	for k in dragons:
		if not bool((dragons[k] as Dictionary).get("dex_hidden", false)):
			ids.append(k)
	ids.sort()
	return ids

func dragon_ids_hidden() -> Array:
	var ids := []
	for k in dragons:
		if bool((dragons[k] as Dictionary).get("dex_hidden", false)):
			ids.append(k)
	ids.sort()
	return ids

func dragon_hidden(id: int) -> bool:
	return bool(dragons.get(id, {}).get("dex_hidden", false))

func dragon_ids_random() -> Array:
	var ids := []
	for k in dragons:
		var d: Dictionary = dragons[k]
		if bool(d.get("dex_hidden", false)) or bool(d.get("acquire_locked", false)):
			continue
		ids.append(k)
	ids.sort()
	return ids

func dragon_acquire_locked(id: int) -> bool:
	return bool(dragons.get(id, {}).get("acquire_locked", false))

func get_item(key: String) -> Dictionary:
	return items.get(key, {})

func item_name(key: String) -> String:
	return items.get(key, {}).get("name", key)

func item_icon_path(key: String) -> String:
	var ic: String = items.get(key, {}).get("icon", "")
	return "res://assets/converted/%s.tres" % ic if ic != "" else ""

func worldmap_regions() -> Array:
	return worldmap.get("regions", [])

func dragon_skill_overrides() -> Dictionary:
	return dragon_skills.get("overrides", {})

func stage(id: String) -> Dictionary:
	var s: Dictionary = stages.get("stages", {}).get(id, {})
	if s.is_empty():
		s = _variant_stage(id)
		if s.is_empty():
			return s
	if s.has("id"):
		return s
	var out := s.duplicate()
	out["id"] = int(id) if id.is_valid_int() else id
	return out

func stage_display_name(st: Dictionary, short := false) -> String:
	var nm := String(st.get("name", "던전"))
	var v := String(st.get("variant_label", ""))
	if v == "":
		return nm
	if short and v == "카데스의 공간":
		v = "카데스"
	return "%s(%s)" % [nm, v]

const _VARIANT_SUFFIX := {"night": "밤", "kades": "카데스의 공간"}
func _variant_stage(id: String) -> Dictionary:
	if not id.is_valid_int():
		return {}
	var fid := int(id)
	var kind := DungeonBG.variant_of(fid)
	if kind == "":
		return {}
	var base := DungeonBG.base_field(fid)
	if DungeonBG.variant_field(base, kind == "night", kind == "kades") != fid:
		return {}
	var src: Dictionary = stages.get("stages", {}).get(str(base), {})
	if src.is_empty():
		return {}
	var out := src.duplicate(true)
	out["id"] = fid
	out["bg"] = fid
	out["variant_label"] = String(_VARIANT_SUFFIX[kind])
	out["party3"] = true
	out["variant"] = kind
	out["base_field"] = base
	var vv: Dictionary = src.get(kind, {})
	if kind == "night":
		for k in ["level", "desc", "dragons"]:
			if vv.has(k):
				out[k] = vv[k]
			else:
				out.erase(k)
	elif kind == "kades":
		out.erase("dragons")
		out.erase("desc")
	if vv.has("enemies"):
		out["enemies"] = vv["enemies"]
		out["boss"] = _boss_name(vv["enemies"])
		out["random_boss"] = bool(vv.get("random_boss", false))
	else:
		out["_inherited"] = true
	out.erase("night")
	out.erase("kades")
	return out

func _boss_name(enemies: Array) -> String:
	for e in enemies:
		if bool((e as Dictionary).get("boss", false)):
			return String((e as Dictionary).get("name", ""))
	if enemies.is_empty():
		return ""
	return String((enemies[-1] as Dictionary).get("name", ""))

func combine_egg_recipes() -> Array:
	return combine_egg.get("recipes", [])

func combine_egg_match(material_keys: Array) -> Dictionary:
	var want := material_keys.duplicate(); want.sort()
	for r in combine_egg_recipes():
		var mats: Array = (r as Dictionary).get("materials", [])
		var have := mats.duplicate(); have.sort()
		if have == want:
			return r
	return {}

func combine_item_recipes() -> Array:
	return combine_item.get("recipes", [])

func combine_item_for(target_key: String) -> Dictionary:
	for r in combine_item_recipes():
		if String((r as Dictionary).get("target", "")) == target_key:
			return r
	return {}

func upgrade_egg_recipes() -> Array:
	return upgrade_egg.get("recipes", [])

func upgrade_egg_for(type_key: String, grade: int) -> Dictionary:
	return EggUpgrade.row_for(type_key, grade, upgrade_egg)

func skill_awaken_list() -> Array:
	return skill_awaken.get("skills", [])

func skill_awaken_for(no: int) -> Dictionary:
	for r in skill_awaken_list():
		if int((r as Dictionary).get("no", -1)) == no:
			return r
	return {}

func awaken_skill_of(dragon_id: int) -> int:
	var own := int(get_dragon(dragon_id).get("awaken_skill", 0))
	if own > 0:
		return own
	var by: Dictionary = skill_awaken.get("by_dragon", {})
	var lst: Array = by.get(str(dragon_id), [])
	return int(lst[0]) if not lst.is_empty() else 0

func art_id(dragon_id: int) -> int:
	return int(get_dragon(dragon_id).get("art_id", dragon_id))

func awaken_skill_icon(no: int) -> int:
	return int(skill_awaken_for(no).get("icon", 0))

func exp_to_next(level: int) -> int:
	var req: Array = level_curve.get("req", [])
	if level < 1 or level > req.size():
		return 0
	return int(req[level - 1])

func level_cap(_awakened := false) -> int:
	return int(level_curve.get("cap", 50))

func items_by(category := "", subcategory := "", offline := "") -> Array:
	var out: Array = []
	for k in items:
		var v: Dictionary = items[k]
		if category != "" and v.get("category", "") != category:
			continue
		if subcategory != "" and v.get("subcategory", "") != subcategory:
			continue
		if offline != "" and v.get("offline", "") != offline:
			continue
		out.append(k)
	out.sort()
	return out

func scenario_def(no: String) -> Dictionary:
	return scenario.get("scenarios", {}).get(no, {})

func scenario_flow_of(no: int) -> Array:
	return scenario_flow.get("flows", {}).get(str(no), [])

func admin_story_line(no: int, line_key: String) -> Dictionary:
	var ep: Dictionary = admin_story.get("episodes", {}).get(str(no), {})
	return ep.get(line_key, {})

func story_speaker(no: int, line_key: String) -> Dictionary:
	var ep: Dictionary = admin_story.get("speakers", {}).get(str(no), {})
	return ep.get(line_key, {})

func admin_story_default(key: String, fallback: Variant) -> Variant:
	return admin_story.get("_default_%s" % key, fallback)

func scenario_npc_folder(npc_no: int) -> String:
	return String(scenario_flow.get("npc_names", {}).get(str(npc_no), ""))

func scenario_bg_paths(bg_no: int) -> Array:
	return scenario_flow.get("backgrounds", {}).get(str(bg_no), [])

func scenario_initial_bg(no: int) -> String:
	return String(scenario_flow.get("initial_bg", {}).get(str(no), ""))

func scenario_bgm(field: int) -> String:
	return String(scenario_flow.get("bgm", {}).get(str(field), ""))

func story_battle(battle_no: int) -> Dictionary:
	var key := str(battle_no)
	var ev: Dictionary = story_subquest.get("event_battle", {}).get(key, {})
	if not ev.is_empty():
		var e0 := _story_enemy(int(ev.get("monster_no", 0)), int(ev.get("lv", 1)))
		if e0.is_empty():
			return {}
		e0["hp_max"] = int(ev.get("hp", e0.get("hp_max", 1)))
		e0["att"] = int(ev.get("att", e0.get("att", 1)))
		e0["def"] = int(ev.get("def", e0.get("def", 1)))
		e0.erase("_stage")
		return {"enemy": e0, "field": int(ev.get("field_no", 0))}
	for tbl in ["monster_by_battle_event", "monster_by_battle"]:
		var rec: Dictionary = story_battles.get(tbl, {}).get(key, {})
		if rec.is_empty():
			continue
		var e1 := _story_enemy(int(rec.get("monster_no", 0)), int(rec.get("level", 0)))
		if not e1.is_empty():
			var fld: int = int(e1.get("_stage", 0))
			e1.erase("_stage")
			return {"enemy": e1, "field": fld}
	return {}

func story_enemy_of(no: int, level: int) -> Dictionary:
	var e := _story_enemy(no, level)
	e.erase("_stage")
	return e

func _story_enemy(no: int, level: int) -> Dictionary:
	if no <= 0:
		return {}
	for m in story_monsters.get("monsters", []):
		var d: Dictionary = m
		if int(d.get("id", -1)) != no:
			continue
		var out := {"id": no, "name": String(d.get("name", "")),
			"level": level if level > 0 else int(d.get("level", 50)),
			"element": "none", "boss": true,
			"hp_max": int(d.get("hp_max", 1)), "att": int(d.get("att", 1)),
			"def": int(d.get("def", 1))}
		if int(d.get("pure", 0)) > 0:
			out["pure"] = int(d.get("pure", 0))
		if int(d.get("stage", 0)) > 0:
			out["_stage"] = int(d.get("stage", 0))
		return out
	for sid in stages.get("stages", {}).keys():
		var st: Dictionary = stages["stages"][sid]
		for blk in [st, st.get("night"), st.get("kades")]:
			if typeof(blk) != TYPE_DICTIONARY:
				continue
			for e in (blk as Dictionary).get("enemies", []):
				var er: Dictionary = e
				if int(er.get("id", -1)) != no:
					continue
				var cp := er.duplicate(true)
				if level > 0:
					cp["level"] = level
				cp["boss"] = true
				if int(sid) > 0:
					cp["_stage"] = int(sid)
				return cp
	return {}

func scenario_monster_path(no: int) -> String:
	var t: Dictionary = scenario_flow.get("monster_npc", {})
	return String(t.get(str(no), "scenario/monster_npc/goblin.png" if not t.is_empty() else ""))

func scenario_item_path(no: int) -> String:
	return String(scenario_flow.get("sc_items", {}).get(str(no), ""))

func prologue_lines() -> Array[String]:
	var out: Array[String] = []
	for v in scenario.get("prologue", []):
		out.append(String(v))
	return out

func scenario_title(no: int) -> String:
	return String(scenario.get("titles", {}).get(str(no), ""))

func scenario_chapters() -> Array:
	return scenario.get("chapters", [])

func scenario_chapter_of(no: int) -> Dictionary:
	for c in scenario_chapters():
		var d: Dictionary = c
		if no >= int(d.get("from", 0)) and no <= int(d.get("to", 0)):
			return d
	return {}

func npc_name(folder: String) -> String:
	if folder == "":
		return ""
	return String(scenario.get("npc_names", {}).get(folder, folder))

func story_cut_from() -> int:
	return int((story.get("_cut", {}) as Dictionary).get("from", 0))

func story_is_cut(no: int) -> bool:
	var c := story_cut_from()
	return c > 0 and no >= c

func story_episode(no: int) -> Dictionary:
	if story_is_cut(no):
		return {}
	return story.get("episodes", {}).get(str(no), {})

func story_episodes() -> Array:
	var out: Array = []
	for k in story.get("episodes", {}).keys():
		var n := int(k)
		if not story_is_cut(n):
			out.append(n)
	out.sort()
	return out

func story_chapters() -> Array:
	var out: Array = []
	for c in (story.get("chapters", []) as Array):
		if not story_is_cut(int((c as Dictionary).get("from", 0))):
			out.append(c)
	return out

func story_subquest_field(no: int) -> Dictionary:
	return story_subquest.get("subquest_field", {}).get(str(no), {})

func story_click_count(no: int) -> int:
	return int(story_subquest.get("click_count", {}).get(str(no), 0))

func story_battle_click_count(no: int) -> int:
	var t: Dictionary = story_subquest.get("battle_click_count", {})
	return int(t.get(str(no), 0))

func story_notify_field(no: int) -> int:
	return int(story_subquest.get("notify_field", {}).get(str(no), 0))

func story_mark_pos(field: int):
	return story_subquest.get("mark_pos", {}).get(str(field))

func story_notify_pos(field: int):
	return story_subquest.get("notify_pos", {}).get(str(field))

func story_notify_conditional(no: int) -> Dictionary:
	var v = story_subquest.get("notify_conditional", {}).get(str(no), {})
	return v if v is Dictionary else {}

func story_mark_field(no: int) -> int:
	return int(story_subquest.get("mark_field", {}).get(str(no), 0))

func story_scenario_mark(no: int) -> Dictionary:
	var v = story_subquest.get("scenario_mark", {}).get(str(no), {})
	return v if v is Dictionary else {}

func story_event_battle(event_no: int) -> Dictionary:
	return story_subquest.get("event_battle", {}).get(str(event_no), {})

func story_special_reward(no: int) -> Dictionary:
	return story_subquest.get("special_reward", {}).get(str(no), {})

func story_special_reward_episodes() -> Array:
	var out: Array = []
	for k in story_subquest.get("special_reward", {}).keys():
		out.append(int(k))
	out.sort()
	return out

func scenario_numbers() -> Array:
	var out: Array = []
	for k in scenario.get("scenarios", {}).keys():
		out.append(int(k))
	out.sort()
	return out

func npc_lines() -> Dictionary:
	return npc_lines_doc.get("npcs", {})
