extends Control

const FLOOR := 692.0

var _pma: CanvasItemMaterial
var _adv: Dictionary = {}
var _bat: Dictionary = {}
var _portrait_man: Dictionary = {}
var _params: Dictionary = {}
var _enemy: Dictionary = {}
var _party: Array = []
var _drink_users: Array = []
var _levelup_queue: Array = []

var _views: Dictionary = {}
var _events: Array = []
var _winner := ""
var _speed := 1.0
var _skip := false
var _playing := false
var _finished := false
var _log_label: Label
var _speed_btn: Button
var _speed_spr: Sprite2D

const SPEEDS := [1.0, 2.0, 4.0]
const SPEED_KEY := "adv_speed"

func enter(params: Dictionary = {}) -> void:
	_params = params
	if _pma != null:
		_rebuild()

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_adv = _man("adventure_ui")
	_bat = _man("battle_ui")
	_rebuild()

func _rebuild() -> void:
	_gen += 1
	for c in get_children():
		c.queue_free()
	_views.clear()
	_events.clear()
	_winner = ""
	_skip = false
	_speed = _saved_speed()
	_setup_enemy()
	_setup_party()
	Bgm.play("bg_battle_boss" if _is_boss() else "bg_colosseum_battle_2")
	_build_bg()
	_build_enemy()
	_build_enemy_hpbar()
	_build_party_cards()
	_build_field_buff()
	_build_textbox()
	_build_hud()
	_maybe_team_buff_intro()

func _setup_enemy() -> void:
	var st: Dictionary = _stage_rec()
	if st.get("bg") != null and not _params.has("bg"):
		_params["bg"] = int(st["bg"])
	var enemies: Array = st.get("enemies", [])
	var pinned: bool = _params.has("enemy_index") or _params.has("enc")
	var ei := clampi(int(_params.get("enemy_index", _params.get("enc", 0))),
		0, maxi(0, enemies.size() - 1))
	if bool(st.get("random_boss", false)) and not enemies.is_empty():
		if not pinned:
			var rr := RandomNumberGenerator.new(); rr.randomize()
			ei = rr.randi() % enemies.size()
	if Darknix.is_summon_stage(st):
		var dkp := Darknix.enemy_index(st["summon"], UserDB.darknix(),
			int(Time.get_unix_time_from_system()))
		if dkp >= 0 and dkp < enemies.size():
			ei = dkp
	var wd_map: Dictionary = st.get("boss_by_weekday", {})
	if not wd_map.is_empty() and not enemies.is_empty() and not pinned:
		var g := int(Time.get_datetime_dict_from_system().get("weekday", 0))
		var key := str(7 if g == 0 else g)
		var idx := int(wd_map.get(key, -1))
		if idx < 0 or idx >= enemies.size():
			var wr := RandomNumberGenerator.new(); wr.randomize()
			idx = wr.randi() % enemies.size()
		ei = idx
	var e: Dictionary = (enemies[ei] if not enemies.is_empty() else _params.get("enemy", {}))
	var eid: Variant = e.get("id", 1)
	_enemy = {
		"id": int(eid) if eid != null else 1,
		"asset_id": int(e.get("asset_id", eid)) if eid != null else 1,
		"name": String(e.get("name", "분홍 몬스터")),
		"level": int(e.get("level", 15)),
		"element": String(e.get("element", "grass")),
		"hp_max": int(e.get("hp_max", 520)),
		"hp": int(e.get("hp", e.get("hp_max", 520))),
		"att": int(e.get("att", 60)),
		"def": int(e.get("def", 40)),
		"boss": bool(e.get("boss", false)),
		"skills": (e.get("skills", []) as Array).duplicate(),
	}
	if bool(_params.get("hero", false)):
		for hs in (e.get("skills_hero", []) as Array):
			if not (_enemy["skills"] as Array).has(int(hs)):
				(_enemy["skills"] as Array).append(int(hs))
		var hmult := Battle.hero_stat_multipliers(st,
			Data.stages.get("_variant_rules", {}) as Dictionary)
		var hp_mult := float(hmult.get("hp", 1.0))
		var att_mult := float(hmult.get("att", 1.0))
		var def_mult := float(hmult.get("def", 1.0))
		_enemy["hp_max"] = maxi(1, int(round(float(int(_enemy["hp_max"])) * hp_mult)))
		_enemy["hp"] = maxi(1, int(round(float(int(_enemy["hp"])) * hp_mult)))
		_enemy["att"] = maxi(1, int(round(float(int(_enemy["att"])) * att_mult)))
		_enemy["def"] = maxi(1, int(round(float(int(_enemy["def"])) * def_mult)))
	var pc: Dictionary = st.get("scale_by_party_count", {})
	if not pc.is_empty():
		_apply_party_count_scaling(pc)
	else:
		var sc: Dictionary = st.get("scale_to_party", {})
		if not sc.is_empty():
			_apply_party_scaling(sc)
	if bool(_params.get("elite", false)):
		_enemy["hp_max"] = int(_enemy["hp_max"] * 1.5)
		_enemy["hp"] = _enemy["hp_max"]
		_enemy["att"] = int(_enemy["att"] * 1.4)
		_enemy["def"] = int(_enemy["def"] * 1.3)
	if _is_kades():
		_apply_kades_enemy(bool(e.get("boss", false)))

const FOOD_PER_BATTLE := 15

const ENEMY_SKILL_LEVEL := 1
func _enemy_skills() -> Array:
	var out: Array = []
	for sid in (_enemy.get("skills", []) as Array):
		out.append({"id": int(sid), "level": ENEMY_SKILL_LEVEL})
	return out

func _apply_kades_enemy(boss: bool) -> void:
	var lv0 := maxi(1, int(_enemy.get("level", 1)))
	if boss:
		var r := RandomNumberGenerator.new()
		r.seed = hash("kades_boss_%s_%d" % [String(_params.get("stage", "")),
			int(_params.get("enc", 0))])
		var lv := Kades.boss_level(Data.kades, r)
		if lv > 0:
			_enemy["level"] = lv
			_enemy["hp_max"] = maxi(1, int(round(float(_enemy["hp_max"])
				* Kades.boss_stat_mult(Data.kades, "hp", lv, lv0))))
			_enemy["hp"] = _enemy["hp_max"]
			_enemy["att"] = maxi(1, int(round(float(_enemy["att"])
				* Kades.boss_stat_mult(Data.kades, "att", lv, lv0))))
			_enemy["def"] = maxi(0, int(round(float(_enemy["def"])
				* Kades.boss_stat_mult(Data.kades, "def", lv, lv0))))
		_enemy["name"] = "%s [전설]" % String(_enemy["name"])
	else:
		var m := float(Data.kades.get("monster_mult", 2.0))
		_enemy["hp_max"] = maxi(1, int(round(float(_enemy["hp_max"]) * m)))
		_enemy["hp"] = _enemy["hp_max"]
		_enemy["att"] = maxi(1, int(round(float(_enemy["att"]) * m)))
		_enemy["def"] = maxi(0, int(round(float(_enemy["def"]) * m)))

func _drop_display_name(key: String) -> String:
	var sk := Loadout.parse_item_key(key)
	if not sk.is_empty():
		return "%s Lv.%d 스크롤" % [
			String(Data.skills.get(str(int(sk["id"])), {}).get("name", "스킬")), int(sk["level"])]
	if key.begins_with(EggGacha.KEY_PREFIX):
		return String(EggGacha.item_def(key, Data.dragons).get("name", "알"))
	var gn := Drops.display_name(key, Data.gems, Data.equipment)
	return gn if gn != key else Data.item_name(key)

func _variant_mode() -> String:
	return Drops.mode_of(bool(_params.get("hero", false)),
		bool(_params.get("night", false)), bool(_params.get("kades", false)))

func _stage_rec() -> Dictionary:
	if not _params.has("stage"):
		return {}
	return Field.apply_variant(Data.stage(str(_params.get("stage", ""))), _variant_mode())

func _is_kades() -> bool:
	if _params.has("kades"):
		return bool(_params.get("kades"))
	var st: Dictionary = _stage_rec()
	return String(st.get("variant", "")) == "kades"

func _base_field() -> int:
	if _params.has("field"):
		return int(_params.get("field"))
	var st: Dictionary = _stage_rec()
	return DungeonBG.base_field(DungeonBG.field_id(st))

func _story_event(kind: String, st: Dictionary, extra: Dictionary = {}) -> void:
	var ev := {
		"kind": kind,
		"field": DungeonBG.base_field(DungeonBG.field_id(st)),
		"region": String(st.get("region", "")),
		"night": bool(UserDB.get_pmeta("yutakan_night", false)),
		"kades": 1 if _is_kades() else 0,
	}
	ev.merge(extra, true)
	var done := StoryProgress.note_event(ev)
	if done > 0:
		Toast.show(self, "서브미션 완료! %d화의 이야기가 이어집니다." % done)

func _note_story_quest(st: Dictionary) -> void:
	var sp := StoryProgress.spec(StoryProgress.pending_episode())
	if sp.is_empty() or String(sp.get("type", "")) != "GATHER":
		return
	var key := String(sp.get("item", ""))
	var fld := DungeonBG.base_field(DungeonBG.field_id(st))
	if key == "" or not sp.has("field") or int(sp["field"]) != fld:
		return
	UserDB.add_item(key, 1)
	_log("%s을(를) 찾았다!" % Data.item_name(key))
	_story_event("GATHER", st, {"item": key})

func _apply_party_count_scaling(pc: Dictionary) -> void:
	var n := 0
	for u in _party_uids_for_scaling():
		var d: Dictionary = UserDB.get_dragon(int(u))
		if d.is_empty() or UserDB.is_egg(d):
			continue
		n += 1
	if n <= 1:
		return
	var mult := pow(float(n), float(pc.get("power", 2)))
	_enemy["att"] = maxi(1, int(round(float(_enemy["att"]) * mult)))
	_enemy["def"] = maxi(0, int(round(float(_enemy["def"]) * mult)))
	_enemy["hp_max"] = maxi(1, int(round(float(_enemy["hp_max"]) * mult)))
	_enemy["hp"] = _enemy["hp_max"]

func _party_uids_for_scaling() -> Array:
	var uids: Array = _params.get("party_uids", [])
	if uids.is_empty():
		var au := UserDB.active_uid()
		if au > 0:
			uids = [au]
	return uids

func _apply_party_scaling(sc: Dictionary) -> void:
	var uids: Array = _party_uids_for_scaling()
	if uids.is_empty():
		return
	var n := 0
	var sum_att := 0.0
	var sum_def := 0.0
	var sum_hp := 0.0
	for u in uids:
		var d: Dictionary = UserDB.get_dragon(int(u))
		if d.is_empty() or UserDB.is_egg(d):
			continue
		var s: Dictionary = Growth.compute_stats(Data.get_dragon(int(d.get("id", 1))),
			Data.stat_table, int(d.get("level", 1)))
		sum_att += float(s.get("att", 0))
		sum_def += float(s.get("def", 0))
		sum_hp += float(s.get("hp", 0))
		n += 1
	if n == 0:
		return
	var crowd := 1.0 + 0.5 * float(n - 1)
	_enemy["att"] = maxi(1, int(round(sum_att / n * float(sc.get("att", 1.0)) * crowd)))
	_enemy["def"] = maxi(0, int(round(sum_def / n * float(sc.get("def", 1.0)) * crowd)))
	_enemy["hp_max"] = maxi(1, int(round(sum_hp / n * float(sc.get("hp", 1.0)) * crowd)))
	_enemy["hp"] = _enemy["hp_max"]

func _setup_party() -> void:
	_party.clear()
	_drink_users.clear()
	var owned: Array = UserDB.dragons()
	var active := UserDB.active_uid()
	var ordered: Array = []
	var chosen: Array = _params.get("party_uids", [])
	if chosen.is_empty():
		chosen = UserDB.party()
	if not chosen.is_empty():
		for uid in chosen:
			var d := UserDB.get_dragon(int(uid))
			if not d.is_empty(): ordered.append(d)
	else:
		for d in owned:
			if int(d["uid"]) == active:
				ordered.push_front(d)
			else:
				ordered.append(d)
	var party3: Array = ordered.slice(0, 3)
	var team_delta := _team_buff_delta(party3)
	_active_team_buffs = _team_buff_list(party3)
	_team_races = _party_race_keys(party3)

	for i in mini(3, ordered.size()):
		var d: Dictionary = ordered[i]
		var id := int(d["id"])
		var ddef := Data.get_dragon(id)
		var level := int(d.get("level", 1))
		var stats := PartyStats.resolve(d, ddef, team_delta, _is_kades(), _field_element())
		if PartyStats.uses_drink(d):
			_drink_users.append(int(d["uid"]))
		var hpmax := int(stats.get("hp", 1))
		var carried: Dictionary = _params.get("hp_state", {})
		var hp0 := int(carried.get(str(int(d["uid"])), hpmax)) if not carried.is_empty() else hpmax
		var eq: Dictionary = _resolve_skills(int(d["uid"]), ddef)
		_party.append({
			"id": id, "uid": int(d["uid"]), "level": level,
			"name": Icons.name_of(d),
			"element": String(ddef.get("element", "")),
			"stats": stats,
			"hp": clampi(hp0, 0, hpmax), "hp_max": hpmax,
			"skills": eq["skills"],
			"skill_slots": eq["slot_types"],
			"awakened": bool(d.get("awakened", false)),
			"voice_critical": _critical_voice_no(id, ddef),
			"critical_hit": int(ddef.get("critical_hit", 0)),
			"awaken_skill": int(d.get("awaken_skill", 0)) if bool(d.get("awakened", false)) else 0,
			"grade": Growth.compute_grade(ddef, Data.stat_table, d.get("stat_bonus", {}),
				d.get("gain_log", []), Data.level_curve.get("grade", {})),
			"atk_type": String(ddef.get("type", "")),
		})
	_apply_awaken_skills()

var _awaken_fired: Array = []
var _equip_fired: Array = []

func _awaken_explore() -> Dictionary:
	var lst: Array = []
	for p in _party:
		var e := {"awaken_no": int((p as Dictionary).get("awaken_skill", 0)),
			"equip_keys": EquipEffect.keys_of((p as Dictionary).get("equip", {}))}
		EquipEffect.awaken_mods([e], Data.equip_effects)
		lst.append(e)
	return AwakenSkill.explore_bonus(lst, Data.skill_awaken)

func _equip_reward_mult(stat: String, who: Dictionary = {}) -> float:
	var pct := 0.0
	for p in ([who] if not who.is_empty() else _party):
		pct += float(((p as Dictionary).get("stats", {}) as Dictionary).get(stat, 0))
	return 1.0 + pct / 100.0

func _exp_for(pv: Dictionary, exp_r: int) -> int:
	return int(round(float(exp_r) * _equip_reward_mult("exp", pv)))

func _apply_awaken_skills() -> void:
	_awaken_fired = []
	_equip_fired = []
	var tbnames: Array = []
	for b in _active_team_buffs:
		tbnames.append(String((b as Dictionary).get("name", "")))
	var fired := PartyStats.apply_passives(_party,
		{"element": String(_enemy.get("element", "")), "hp": int(_enemy.get("hp_max", 1))},
		{"field_element": _field_element(), "enemy_boss": _is_boss(), "team_buffs": tbnames,
			"explore_gold_pct": int(_awaken_explore().get("gold_pct", 0))})
	_awaken_fired = fired["awaken_fired"]
	_equip_fired = fired["equip_fired"]

var _active_team_buffs: Array = []
var _team_races: Array = []

func _party_race_keys(party: Array) -> Array:
	var table: Dictionary = Data.team_buffs
	var race_dim := String(table.get("race_dim", "element"))
	var race_keys: Array = []
	for d in party:
		race_keys.append(String(Data.get_dragon(int(d["id"])).get(race_dim, "")))
	return race_keys

func _team_buff_list(party: Array) -> Array:
	var table: Dictionary = Data.team_buffs
	if table.is_empty() or (table.get("buffs", []) as Array).is_empty():
		return []
	return TeamBuff.active_buffs(_party_race_keys(party), table)

func _team_buff_delta(party: Array) -> Dictionary:
	var table: Dictionary = Data.team_buffs
	if table.is_empty() or (table.get("buffs", []) as Array).is_empty():
		return {}
	return TeamBuff.typed_for_party(_party_race_keys(party), table)

func _maybe_team_buff_intro() -> void:
	var gen := _gen
	var buff: Dictionary = _active_team_buffs[0] if not _active_team_buffs.is_empty() else {}
	var run_key := "%s:%d" % [String(_params.get("stage", "")), int(_params.get("run_seed", 0))]
	if buff.is_empty() or not CombineElements.can_play(run_key, _team_races.size(), buff):
		_run_and_replay()
		return
	var layer := CombineElements.play(self, _team_races, buff, Data.team_buffs)
	if layer == null:
		_run_and_replay()
		return
	CombineElements.mark_played(run_key)
	await get_tree().create_timer(CombineElements.DURATION).timeout
	if gen != _gen or not is_inside_tree():
		return
	_run_and_replay()

func _resolve_skills(uid: int, ddef: Dictionary) -> Dictionary:
	if (UserDB.dragon_skills(uid) as Array).is_empty():
		UserDB.ensure_dragon_skills(uid,
			Loadout.default_skills(ddef, Data.skills, Data.dragon_skill_overrides()))
	UserDB.sync_skill_grants(uid)
	return UserDB.dragon_battle_skills(uid)

func _build_bg() -> void:
	var st: Dictionary = _stage_rec()
	if st.is_empty() and _params.has("bg_stage"):
		var f0 := int(_params.get("bg_stage", 0))
		var mode := ""
		if f0 > 600:
			f0 -= 600; mode = "kades"
		elif f0 > 500:
			f0 -= 500; mode = "night"
		var bst: Dictionary = Field.apply_variant(Data.stage(str(f0)), mode)
		if not bst.is_empty() and DungeonBG.build(self, bst) != null:
			return
	if not st.is_empty() and DungeonBG.build(self, st) != null:
		return
	var bg := TextureRect.new()
	var p := "res://assets/converted/battle_bg/bg_%d.jpg" % int(_params.get("bg", 1))
	if ResourceLoader.exists(p):
		bg.texture = load(p)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

func _build_field_buff() -> void:
	var fel := _field_element()
	if fel == "" or fel == "none":
		return
	var path := "res://scenes/buffs/stage_buff_%s.tscn" % fel
	if not ResourceLoader.exists(path):
		return
	for i in _party.size():
		if String(_party[i].get("element", "")) != fel:
			continue
		var v: Dictionary = _views.get("A%d" % i, {})
		var card = v.get("node", null)
		if not (card is Control):
			continue
		var c := card as Control
		var holder := Node2D.new()
		holder.position = c.size * 0.5
		holder.z_index = 1
		holder.scale = Vector2(1.5, 1.5)
		c.add_child(holder)
		var inst = (load(path) as PackedScene).instantiate()
		holder.add_child(inst)
		var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			var anims := ap.get_animation_list()
			if anims.size() > 0:
				ap.get_animation(anims[0]).loop_mode = Animation.LOOP_NONE
				ap.play(anims[0])

func _field_element() -> String:
	var st: Dictionary = _stage_rec()
	var authored := Drops.normalize_element(st.get("field_element", ""))
	if authored == "":
		authored = Drops.normalize_element(st.get("element", ""))
	if authored != "" and authored != "none":
		return authored
	var tally: Dictionary = {}
	for e in st.get("enemies", []):
		var el := Drops.normalize_element((e as Dictionary).get("element", ""))
		if el == "" or el == "none":
			continue
		tally[el] = int(tally.get(el, 0)) + 1
	var best := ""
	var best_n := 0
	for k in tally:
		if int(tally[k]) > best_n:
			best_n = int(tally[k]); best = String(k)
	return best

func _build_enemy() -> void:
	var vis := _vis()
	var cx := vis.x * 0.5
	var boss := _is_boss()
	var ey := 360.0 if boss else 300.0
	var e_scale := 0.66 if boss else 0.85
	var sh := _spr("adventure_ui", "scene_adventure_shadow", _adv, 1.6 if boss else 1.4)
	if sh: sh.position = Vector2(cx, ey + 130.0); add_child(sh)
	if bool(_params.get("elite", false)):
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 0.85, 0.3, 0.55)); grad.set_color(1, Color(1.0, 0.8, 0.2, 0.0))
		var gtex := GradientTexture2D.new(); gtex.gradient = grad
		gtex.fill = GradientTexture2D.FILL_RADIAL; gtex.fill_from = Vector2(0.5, 0.5); gtex.fill_to = Vector2(1.0, 0.5)
		gtex.width = 420; gtex.height = 420
		var glow := Sprite2D.new(); glow.texture = gtex; glow.position = Vector2(cx, ey)
		var am := CanvasItemMaterial.new(); am.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = am; glow.z_index = -1
		add_child(glow)
		var gt := glow.create_tween().set_loops()
		gt.tween_property(glow, "scale", Vector2(1.15, 1.15), 1.0).set_trans(Tween.TRANS_SINE)
		gt.tween_property(glow, "scale", Vector2.ONE, 1.0).set_trans(Tween.TRANS_SINE)
	var mid := int(_enemy.get("asset_id", _enemy["id"]))
	var mspr: Node2D = null
	var att_spr: Sprite2D = null
	var hit_spr: Sprite2D = null
	var mdir := "monster_%d" % mid
	var mman := _man(mdir)
	att_spr = _spr(mdir, "monster_%d_%d_image_att" % [mid, mid], mman, 1.6)
	hit_spr = _spr(mdir, "monster_%d_%d_image_hit" % [mid, mid], mman, 1.6)
	var mscn_path := "res://scenes/monsters/monster_%d.tscn" % mid
	if ResourceLoader.exists(mscn_path):
		var group := CanvasGroup.new()
		var inst = (load(mscn_path) as PackedScene).instantiate()
		group.add_child(inst)
		mspr = group
		mspr.scale = Vector2(e_scale, e_scale)
		var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.has_animation("wait"):
			ap.play("wait")
	else:
		mspr = att_spr
		att_spr = null
	if mspr:
		mspr.position = Vector2(cx, ey)
		add_child(mspr)
	if att_spr:
		att_spr.position = Vector2(cx, ey)
		att_spr.visible = false
		add_child(att_spr)
	if hit_spr:
		hit_spr.position = Vector2(cx, ey)
		hit_spr.visible = false
		add_child(hit_spr)
	_views["E0"] = {"kind": "enemy", "node": mspr, "att_node": att_spr, "hit_node": hit_spr,
		"center": Vector2(cx, ey), "base_pos": Vector2(cx, ey), "alive": true,
		"bicon_origin": Vector2(cx - float(_adv.get(
			"scene_adventure_monster_box2" if boss else "scene_adventure_monster_box", {}).get("w", 476))
			* Design.ASSET_SCALE * 0.5 + 18.0, 81.0),
		"anim": (mspr.find_child("AnimationPlayer", true, false) if mspr else null),
		"groggy": false, "base_scale": (mspr.scale if mspr else Vector2.ONE),
		"element": String(_enemy.get("element", ""))}
	_monster_income(mspr)

func _build_enemy_hpbar() -> void:
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var boss := _is_boss()
	var bg_key := "scene_adventure_monster_box2_bg" if boss else "scene_adventure_monster_box_bg"
	var plate_key := "scene_adventure_monster_box2" if boss else "scene_adventure_monster_box"
	var bgi: Dictionary = _adv.get(bg_key, {})
	var pli: Dictionary = _adv.get(plate_key, {})
	var pw := float(pli.get("w", 476)) * S
	var ph := float(pli.get("h", 55)) * S
	var w := float(bgi.get("w", 392)) * S
	var h := float(bgi.get("h", 21)) * S
	var root := Node2D.new()
	root.position = Vector2(vis.x * 0.5 - pw * 0.5, 0.0)
	add_child(root)
	var plate := _spr("adventure_ui", plate_key, _adv, S)
	if plate:
		plate.position = Vector2(pw * 0.5, ph * 0.5)
		root.add_child(plate)
	var trk_org := Vector2((pw - w) * 0.5, (ph - h) * 0.5)
	var track := _spr("adventure_ui", bg_key, _adv, S)
	if track:
		track.position = trk_org + Vector2(w * 0.5, h * 0.5)
		root.add_child(track)
	var pad := 2.0 * S
	var bar_w := w - pad * 2.0
	var bar_h := h - pad * 2.0
	var fill := _hp_fill(bar_w, bar_h, true)
	fill.position = trk_org + Vector2(pad, pad)
	root.add_child(fill)
	var nm := Label.new()
	nm.text = "레벨 %d  %s" % [int(_enemy["level"]), String(_enemy["name"])]
	nm.add_theme_font_size_override("font_size", 22)
	nm.add_theme_color_override("font_color", Color.WHITE)
	nm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	nm.add_theme_constant_override("outline_size", 4)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.size = Vector2(pw, trk_org.y); nm.position = Vector2(0, 0)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(nm)
	var hp := _bmf_label("subtitle", 0.8 * S)
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp.size = Vector2(w, h); hp.position = trk_org
	root.add_child(hp)
	var sy := ph - (ph * 0.5 + 30.0)
	_stat_icon(root, "scene_adventure_att_icon-hd", int(_enemy.get("att", 0)),
		Vector2(pw - 150.0, sy), S)
	_stat_icon(root, "scene_adventure_def_icon-hd", int(_enemy.get("def", 0)),
		Vector2(pw - 70.0, sy), S)
	var elem := String(_enemy.get("element", ""))
	var ekey := Icons.element_small_frame(elem)
	if ekey != "":
		var esz := AtlasUI.size_pt("item_small_ui", ekey) * 0.5
		var ei := AtlasUI.spr("item_small_ui", ekey, 0.5 * S)
		if ei != null:
			ei.position = Vector2(10.0 + esz.x * 0.5, 5.0 + esz.y * 0.5)
			ei.z_index = 2
			root.add_child(ei)
	var v: Dictionary = _views["E0"]
	v["hp"] = int(_enemy["hp"]); v["hp_max"] = int(_enemy["hp_max"])
	v["hp_fill"] = fill; v["hp_label"] = hp; v["bar_w"] = bar_w; v["bar_x"] = pad
	v["bar_local"] = true
	_refresh_bar(v)
	root.position.y = -ph * 2.0
	create_tween().tween_property(root, "position:y", 0.0, 0.7)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)

func _stat_icon(parent: Node2D, frame: String, value: int, gpos: Vector2, s: float) -> void:
	var info: Dictionary = _adv.get(frame, {})
	var iw := float(info.get("w", 21)) * 0.9 * s
	var ih := float(info.get("h", 21)) * 0.9 * s
	var ic := _spr("adventure_ui", frame, _adv, 0.9 * s)
	if ic:
		ic.position = gpos + Vector2(iw * 0.5, ih * 0.5)
		parent.add_child(ic)
	var lb := _bmf_label("subtitle", 0.6 * s)
	lb.text = str(value)
	lb.position = gpos + Vector2(iw + 2.0, -2.0)
	lb.size = Vector2(90, ih + 6.0)
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(lb)

const _BMF := {
	"subtitle": "res://assets/480/font/font_subtitle.fnt",
	"common": "res://assets/480/font/font_common.fnt",
	"total": "res://assets/480/font/font_total.fnt",
	"heal": "res://assets/480/font/font_heal.fnt",
}
var _bmf_cache: Dictionary = {}
func _bmf_font(kind: String) -> Font:
	if not _bmf_cache.has(kind):
		var p: String = _BMF.get(kind, _BMF["subtitle"])
		_bmf_cache[kind] = load(p) if ResourceLoader.exists(p) else null
	return _bmf_cache[kind]

func _bmf_label(kind: String, scale := 1.0) -> Label:
	var l := Label.new()
	var f := _bmf_font(kind)
	if f:
		l.add_theme_font_override("font", f)
		var base: float = float(f.fixed_size) if f.fixed_size > 0 else 32.0
		l.add_theme_font_size_override("font_size", int(round(base * scale)))
	else:
		l.add_theme_font_size_override("font_size", int(round(24.0 * scale)))
		l.add_theme_color_override("font_color", Color.WHITE)
	return l

func _build_party_cards() -> void:
	var vis := _vis()
	var n := _party.size()
	if n == 0:
		return
	var S := Design.ASSET_SCALE
	var cw := float(_adv.get("scene_adventure_stat_box3", {}).get("w", 220)) * S
	var ch := float(_adv.get("scene_adventure_stat_box3", {}).get("h", 79)) * S
	var cardY := vis.y - 128.0 - ch
	var xs: Array[float] = []
	match n:
		1: xs = [20.0]
		2: xs = [20.0, vis.x * 0.5 - cw * 0.5]
		_: xs = [20.0, vis.x * 0.5 - cw * 0.5, vis.x - 20.0 - cw]
	for i in n:
		_party_card(i, _party[i], xs[mini(i, xs.size() - 1)], cardY, cw, ch)

func _party_card(idx: int, pd: Dictionary, x: float, y: float, w: float, ch: float) -> void:
	var S := Design.ASSET_SCALE
	var card := Control.new()
	card.set_meta("party_card", true)
	card.z_index = 400
	card.position = Vector2(x, y)
	card.size = Vector2(w, ch)
	card.pivot_offset = Vector2(w * 0.5, ch * 0.5)
	add_child(card)
	var C := func(cx: float, cy: float) -> Vector2: return Vector2(cx, ch - cy)
	var bg := _spr("adventure_ui", "scene_adventure_stat_box3", _adv, S)
	if bg: bg.position = Vector2(w * 0.5, ch * 0.5); card.add_child(bg)
	var frame := _spr("adventure_ui", "scene_adventure_stat_box_frame%d" % (idx % 3 + 1), _adv, S)
	if frame: frame.position = Vector2(w * 0.5, ch * 0.5); card.add_child(frame)
	var stage := Growth.portrait_stage(pd)
	var ppos: Vector2 = C.call(50.0, ch * 0.5 + 3.0)
	var pbg := _spr("common_ui", "common_profile_bg", _man("common_ui"), S)
	if pbg: pbg.position = ppos; card.add_child(pbg)
	var por := _portrait(int(pd["id"]), stage, 0.63 * S)
	if por: por.position = ppos; card.add_child(por)
	var lv_org: Vector2 = C.call(ppos.x + 40.0, ch * 0.5 + 22.0) - Vector2(0, 22.0)
	var lvk := Label.new()
	lvk.text = "레벨"
	lvk.add_theme_font_size_override("font_size", 15)
	lvk.add_theme_color_override("font_color", Color8(0x35, 0x35, 0x35))
	lvk.position = lv_org + Vector2(0, 4.0)
	card.add_child(lvk)
	var lv := _bmf_label("subtitle", 0.75 * S)
	lv.text = "%d" % int(pd["level"])
	lv.add_theme_color_override("font_color", Color8(0x35, 0x35, 0x35))
	lv.position = lv_org + Vector2(32.0, 0.0)
	card.add_child(lv)
	var nm := Label.new()
	nm.text = String(pd["name"])
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", Color8(0x35, 0x35, 0x35))
	nm.position = lv_org + Vector2(66.0, 3.0)
	card.add_child(nm)
	var bar_w := 177.0
	var bar_h := 30.0
	var bar_org: Vector2 = C.call(97.0, 40.0 + bar_h)
	var hbg := _spr("adventure_ui", "scene_adventure_stat_box3_bg", _adv, S)
	if hbg:
		hbg.position = bar_org + Vector2(bar_w * 0.5, bar_h * 0.5)
		card.add_child(hbg)
	var hfl := _hp_fill(bar_w - 10.0, bar_h - 14.0)
	hfl.position = bar_org + Vector2(5.0, 7.0)
	card.add_child(hfl)
	var hp := _bmf_label("subtitle", 0.8 * S)
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp.size = Vector2(bar_w, bar_h); hp.position = bar_org
	card.add_child(hp)
	var ay := ch * 0.5 - 19.0
	_stat_icon_ui(card, "scene_adventure_att_icon-hd", int(pd["stats"].get("att", 0)),
		C.call(w * 0.5 - 50.0, ay), S)
	_stat_icon_ui(card, "scene_adventure_def_icon-hd", int(pd["stats"].get("def", 0)),
		C.call(w * 0.5 + 30.0, ay), S)
	var gauge_w := w - 100.0
	var gfl := ColorRect.new(); gfl.color = Color(1, 0.8, 0.25)
	gfl.size = Vector2(0, 5); gfl.position = Vector2(97.0, ch - 12.0)
	gfl.visible = false
	card.add_child(gfl)
	var v := {"kind": "party", "node": card, "center": Vector2(x + w * 0.5, y - 10),
		"base_pos": Vector2(x, y), "alive": true, "element": String(pd.get("element", "")),
		"bicon_origin": Vector2(x + 42.0, y - 26.0),
		"id": int(pd.get("id", 0)), "awakened": bool(pd.get("awakened", false)),
		"voice_critical": int(pd.get("voice_critical", 0)),
		"critical_hit": int(pd.get("critical_hit", 0)),
		"hp": int(pd["hp"]), "hp_max": int(pd["hp_max"]),
		"hp_fill": hfl, "hp_label": hp, "bar_w": bar_w - 8.0, "bar_x": bar_org.x, "bar_local": true,
		"gauge": 0.0, "gauge_fill": gfl, "gauge_w": gauge_w}
	_views["A%d" % idx] = v
	_refresh_bar(v)
	card.position.y = y + ch * 3.0
	create_tween().tween_property(card, "position:y", y, 0.7)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)

func _stat_icon_ui(parent: Control, frame: String, value: int, gpos: Vector2, s: float) -> void:
	var info: Dictionary = _adv.get(frame, {})
	var iw := float(info.get("w", 21)) * 0.9 * s
	var ih := float(info.get("h", 21)) * 0.9 * s
	var ic := _spr("adventure_ui", frame, _adv, 0.9 * s)
	if ic:
		ic.position = gpos + Vector2(iw * 0.5, ih * 0.5)
		parent.add_child(ic)
	var lb := _bmf_label("subtitle", 0.6 * s)
	lb.text = str(value)
	lb.position = gpos + Vector2(iw + 2.0, -1.0)
	lb.size = Vector2(80, ih + 6.0)
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(lb)

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.layer = 10
	add_child(hud)
	var vis := _vis()
	var autob := _img_button("scene_adventure_auto", Vector2(74, 30))
	autob.position = Vector2(16, 12); autob.toggle_mode = true; autob.button_pressed = true
	hud.add_child(autob)
	var S := Design.ASSET_SCALE
	var fw := 74.0 * S
	var fh := 40.0 * S
	_speed_btn = _img_button("scene_adventure_speed_0", Vector2(fw, fh), S)
	_speed_btn.position = Vector2(vis.x - 100.0 - fw * 0.5, vis.y * 0.5 - fh * 0.5)
	_speed_btn.pressed.connect(_cycle_speed)
	if _speed_btn.get_child_count() > 0: _speed_spr = _speed_btn.get_child(0) as Sprite2D
	hud.add_child(_speed_btn)
	_apply_speed_icon()
	var skip := _img_button("scene_adventure_bt_skip_kr", Vector2(74, 32))
	skip.position = Vector2(vis.x - 90, vis.y * 0.5 + fh)
	skip.pressed.connect(func(): _skip = true)
	hud.add_child(skip)
	var sw: Dictionary = _man("common_ui")
	var sword := _img_button_from("common_ui", "common_icon_sword1", sw, 1.5 * S)
	if sword:
		sword.position = Vector2(vis.x - 150.0 - sword.size.x * 0.5,
			Design.flip_y(vis.y * 0.75, vis.y) - sword.size.y * 0.5)
		sword.pressed.connect(_open_battle_settings)
		hud.add_child(sword)
	_build_exp_panel(hud)
	_build_mission_labels(hud)
	_log("%s 이(가) 나타났다!" % String(_enemy["name"]))

const _EXP_PANEL := Vector2(190.0, 30.0)
var _exp_label: Label
var _exp_gained := 0
func _build_exp_panel(hud: CanvasLayer) -> void:
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var w := _EXP_PANEL.x
	var h := _EXP_PANEL.y
	var root := Control.new()
	root.position = Vector2(vis.x * 0.03, vis.y * 0.15 - h * 0.5)
	root.size = Vector2(w, h)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)
	var bg := NinePatchRect.new()
	bg.texture = load("res://assets/converted/colosseum_ui/scene_colosseum_week_time_bg.tres")
	bg.patch_margin_left = 10; bg.patch_margin_right = 10
	bg.patch_margin_top = 6; bg.patch_margin_bottom = 6
	bg.size = Vector2(w, h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	for key in ["scene_adventure_bonus_exp_mini2", "scene_adventure_bonus_exp_mini"]:
		var wing := _spr("adventure_ui", key, _adv, S)
		if wing == null:
			continue
		var wi: Dictionary = _adv.get(key, {})
		wing.position = Vector2(-10.0 + float(wi.get("w", 64)) * S * 0.5, h * 0.5 - 5.0)
		root.add_child(wing)
	_exp_label = _bmf_label("subtitle", S)
	_exp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_exp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_exp_label.size = Vector2(w - 10.0, h); _exp_label.position = Vector2(0, -2.0)
	_exp_label.text = "0"
	root.add_child(_exp_label)

var _mission_rows: Array = []
var _missions: Array = []
const _MISSION_ROW_H := 60.0
func _build_mission_labels(hud: CanvasLayer) -> void:
	var defs: Dictionary = Data.battle_missions
	if defs.is_empty(): return
	var rng := RandomNumberGenerator.new(); rng.randomize()
	_missions = BattleMission.pick(defs, rng)
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var top := vis.y * 0.15 + 22.0
	var bw := 400.0
	for i in _missions.size():
		var m: Dictionary = _missions[i]
		var y := top + i * _MISSION_ROW_H
		var row := NinePatchRect.new()
		row.texture = load("res://assets/converted/adventure_ui/scene_adventure_quest_shadow.tres")
		row.patch_margin_left = 10; row.patch_margin_right = 10
		row.patch_margin_top = 4; row.patch_margin_bottom = 4
		row.size = Vector2(bw, _MISSION_ROW_H)
		row.position = Vector2(vis.x * 0.03, y)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(row)
		var pbg := _spr("common_ui", "common_profile_bg", _man("common_ui"), 0.5 * S)
		if pbg: pbg.position = Vector2(40, _MISSION_ROW_H * 0.5); row.add_child(pbg)
		var chk := _spr("common_ui", "common_checked", _man("common_ui"), 0.9 * S)
		if chk:
			chk.position = Vector2(40, _MISSION_ROW_H * 0.5); chk.visible = false
			row.add_child(chk)
		var t := Label.new()
		t.text = String(m.get("text", ""))
		t.add_theme_font_size_override("font_size", 22)
		t.add_theme_color_override("font_color", Color8(0xf6, 0xf6, 0xf6))
		t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		t.position = Vector2(80, 0); t.size = Vector2(200, _MISSION_ROW_H)
		row.add_child(t)
		var cnt := _bmf_label("subtitle", 0.8 * S)
		cnt.text = "[0/%d]" % int(m.get("goal", 1))
		cnt.add_theme_color_override("font_color", Color8(0xd6, 0x5f, 0x5f))
		cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cnt.position = Vector2(250, 0); cnt.size = Vector2(90, _MISSION_ROW_H)
		row.add_child(cnt)
		var ico := _spr("adventure_ui", "scene_adventure_bonus_exp_mini", _adv, 0.85 * S)
		if ico: ico.position = Vector2(bw - 110, _MISSION_ROW_H * 0.5); row.add_child(ico)
		var rw := Label.new()
		rw.text = "+%d%%" % int(round(float(m.get("exp_bonus", 0.0)) * 100.0))
		rw.add_theme_font_size_override("font_size", 22)
		rw.add_theme_color_override("font_color", Color8(0xf6, 0xf6, 0xf6))
		rw.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rw.position = Vector2(bw - 76, 0); rw.size = Vector2(70, _MISSION_ROW_H)
		row.add_child(rw)
		_mission_rows.append({"def": m, "cnt": cnt, "check": chk})
		row.position.y = y - vis.y * 0.5
		create_tween().tween_property(row, "position:y", y, 0.5)\
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)

func _update_missions(played: Array) -> void:
	if _mission_rows.is_empty(): return
	var names: Array = []
	for p in _party: names.append(String(p.get("name", "")))
	var prog: Array = BattleMission.evaluate(_missions, played, names)
	for i in mini(prog.size(), _mission_rows.size()):
		var r: Dictionary = _mission_rows[i]
		var p: Dictionary = prog[i]
		var cl = r.get("cnt")
		if is_instance_valid(cl):
			(cl as Label).text = "[%d/%d]" % [int(p["count"]), int((p["mission"] as Dictionary).get("goal", 1))]
		var ck = r.get("check")
		if is_instance_valid(ck):
			(ck as Sprite2D).visible = bool(p["done"])

var _auto := true
var _settings_layer: CanvasLayer
func _open_battle_settings() -> void:
	if is_instance_valid(_settings_layer):
		return
	var vis := _vis()
	_settings_layer = CanvasLayer.new(); _settings_layer.layer = 70; add_child(_settings_layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.6); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_layer.add_child(dim)
	const BW := 460.0
	const BH := 330.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	_settings_layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(300, 52); tbar.position = Vector2((BW - 300) * 0.5, 12); win.add_child(tbar)
	var title := Label.new(); title.text = "자동 설정"
	title.add_theme_font_size_override("font_size", 28); title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size = tbar.size; tbar.add_child(title)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 58, 14); xb.pressed.connect(_close_battle_settings); win.add_child(xb)
	_setting_row(win, "자동 전투", 88, func() -> String: return "켜짐" if _auto else "꺼짐",
		func(): _auto = not _auto)
	_setting_arrow_row(win, "전투 속도", 148, func() -> String: return "x%d" % int(_speed),
		func(d: int): _cycle_speed())
	_setting_arrow_row(win, "반복 횟수", 208, func() -> String: return "%d회" % int(UserDB.get_pmeta("adv_repeat", 1)),
		func(d: int): UserDB.set_pmeta("adv_repeat", clampi(int(UserDB.get_pmeta("adv_repeat", 1)) + d, 1, 50)))
	var ok := Button.new(); ok.text = "확인"; ok.size = Vector2(160, 44); ok.position = Vector2((BW - 160) * 0.5, BH - 62)
	ok.pressed.connect(_close_battle_settings); win.add_child(ok)

func _close_battle_settings() -> void:
	if is_instance_valid(_settings_layer): _settings_layer.queue_free(); _settings_layer = null

func _setting_row(win: Control, label: String, y: float, val: Callable, toggle: Callable) -> void:
	var lb := Label.new(); lb.text = label; lb.add_theme_font_size_override("font_size", 22)
	lb.add_theme_color_override("font_color", Color(0.28, 0.18, 0.05)); lb.position = Vector2(150, y); lb.size = Vector2(160, 30)
	win.add_child(lb)
	var b := Button.new(); b.size = Vector2(96, 34); b.position = Vector2(300, y - 2); b.text = String(val.call())
	b.pressed.connect(func(): toggle.call(); b.text = String(val.call())); win.add_child(b)

func _setting_arrow_row(win: Control, label: String, y: float, val: Callable, adj: Callable) -> void:
	var lb := Label.new(); lb.text = label; lb.add_theme_font_size_override("font_size", 22)
	lb.add_theme_color_override("font_color", Color(0.28, 0.18, 0.05)); lb.position = Vector2(150, y); lb.size = Vector2(150, 30)
	win.add_child(lb)
	var vlb := Label.new(); vlb.add_theme_font_size_override("font_size", 22)
	vlb.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05)); vlb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vlb.position = Vector2(316, y); vlb.size = Vector2(70, 30)
	var upd := func(): vlb.text = String(val.call())
	upd.call()
	var la := TextureButton.new(); la.texture_normal = load("res://assets/converted/common_ui/common_btn_arrow1.tres")
	la.position = Vector2(300, y - 2); la.pressed.connect(func(): adj.call(-1); upd.call()); win.add_child(la)
	var ra := TextureButton.new(); ra.texture_normal = load("res://assets/converted/common_ui/common_btn_arrow2.tres")
	ra.position = Vector2(388, y - 2); ra.pressed.connect(func(): adj.call(1); upd.call()); win.add_child(ra)
	win.add_child(vlb)

func _saved_speed() -> float:
	var v := float(UserDB.get_pmeta(SPEED_KEY, 1.0))
	return v if SPEEDS.has(v) else 1.0

func _cycle_speed() -> void:
	_speed = SPEEDS[(SPEEDS.find(_speed) + 1) % SPEEDS.size()]
	UserDB.set_pmeta(SPEED_KEY, _speed)
	_apply_speed_icon()

func _apply_speed_icon() -> void:
	var idx := maxi(0, SPEEDS.find(_speed))
	if is_instance_valid(_speed_spr):
		var p := "res://assets/converted/adventure_ui/scene_adventure_speed_%d.tres" % idx
		if ResourceLoader.exists(p): _speed_spr.texture = load(p)
	elif is_instance_valid(_speed_btn):
		_speed_btn.text = "▶ x%d" % int(_speed)

const _TEXTBOX_H := 120.0
func _build_textbox() -> void:
	var vis := _vis()
	var lay := CanvasLayer.new(); lay.layer = 8
	add_child(lay)
	var box := NinePatchRect.new()
	box.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres")
	box.patch_margin_left = 10; box.patch_margin_right = 10
	box.patch_margin_top = 4; box.patch_margin_bottom = 4
	box.size = Vector2(vis.x - 10.0, _TEXTBOX_H)
	box.position = Vector2(5.0, vis.y - _TEXTBOX_H)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lay.add_child(box)
	_log_label = Label.new()
	_log_label.add_theme_font_size_override("font_size", 28)
	_log_label.add_theme_color_override("font_color", Color.WHITE)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_log_label.size = Vector2(box.size.x - 20.0, _TEXTBOX_H - 8.0)
	_log_label.position = Vector2(10.0, 4.0)
	_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_log_label)
	if _pending_log != "":
		_log_label.text = _pending_log

const _L := preload("res://scripts/ui/battle_log_text.gd").L
var _pending_log := ""
func _log(msg: String) -> void:
	_pending_log = msg
	if _log_label:
		_log_label.text = msg

func _attack_line(ev: Dictionary, is_crit: bool) -> String:
	var a := _disp(ev.get("attacker", ""))
	var d := _disp(ev.get("defender", ""))
	var dmg := int(ev.get("damage", 0))
	if bool(ev.get("block", false)):
		return _L["block"] % [d, a, dmg]
	if is_crit:
		return _L["crit"] % [a, d, dmg]
	if String(ev.get("type", "")) == "double":
		return _L["double"] % [a, d, dmg]
	return _L["atk"] % [a, d, dmg]

func _skill_name_of(sid: int) -> String:
	if sid <= 0: return ""
	return String(Data.skills.get(str(sid), {}).get("name", ""))

func _show_finish_arrow(region: String) -> void:
	if not is_instance_valid(_log_label):
		Scenes.goto("worldmap", {"region": region})
		return
	var box := _log_label.get_parent() as Control
	if box == null:
		Scenes.goto("worldmap", {"region": region})
		return
	var arrow := TextureButton.new()
	arrow.texture_normal = load("res://assets/converted/common_ui/common_btn_arrow2.tres")
	arrow.position = Vector2(box.size.x - 62.0, box.size.y - 58.0)
	arrow.pressed.connect(func(): Scenes.goto("worldmap", {"region": region}))
	box.add_child(arrow)
	var tap_layer := CanvasLayer.new()
	tap_layer.layer = 9
	tap_layer.set_meta("finish_click_catcher", true)
	add_child(tap_layer)
	var tap := Button.new()
	tap.flat = true
	tap.focus_mode = Control.FOCUS_NONE
	tap.position = Vector2.ZERO
	tap.size = _vis()
	tap.pressed.connect(func(): Scenes.goto("worldmap", {"region": region}))
	tap_layer.add_child(tap)

func _run_and_replay() -> void:
	var pa: Array = []
	for i in _party.size():
		var pd: Dictionary = _party[i]
		var c := Battle.make_combatant("A%d" % i, "ally", String(pd["element"]),
			pd["stats"], 0.0, pd.get("skills", []))
		c["hp"] = int(pd["hp"]); c["hp_max"] = int(pd["hp_max"])
		c["awaken_no"] = int(pd.get("awaken_skill", 0))
		c["grade"] = float(pd.get("grade", 0.0))
		c["dragon_id"] = int(pd.get("id", 0))
		c["atk_type"] = String(pd.get("atk_type", ""))
		c["awaken_gauge"] = float(pd.get("awaken_gauge", 0.0))
		for e in (pd.get("awaken_effects", []) as Array):
			(c["effects"] as Array).append((e as Dictionary).duplicate())
		pa.append(c)
	var eb := Battle.make_combatant("E0", "enemy", String(_enemy["element"]),
		{"hp": int(_enemy["hp_max"]), "att": int(_enemy["att"]), "def": int(_enemy["def"]), "cri": 8, "evd": 6, "blk": 8},
		0.0, _enemy_skills())
	_apply_boss_phase(eb)
	var pb: Array = [eb]
	if pa.is_empty():
		_log("출전할 드래곤이 없습니다."); return
	var st_now: Dictionary = _stage_rec()
	var skills_db: Dictionary = {} if bool(st_now.get("no_skills", false)) else Data.skills
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var res := Battle.simulate(pa, pb, rng, Data.combat, skills_db)
	_events = res.get("events", [])
	_winner = String(res.get("winner", "draw"))
	_play_events()

var _gen := 0
func _play_events() -> void:
	var gen := _gen
	_playing = true
	_battle_opening()
	await _wait(1.0)
	if gen != _gen: return
	var played: Array = []
	for ev in _events:
		_play_event(ev)
		played.append(ev)
		_update_missions(played)
		await _wait(_evt_delay(ev))
		if gen != _gen: return
	await _wait(0.3)
	if gen != _gen: return
	_finish()
	_playing = false

func _evt_delay(ev: Dictionary) -> float:
	var t := String(ev.get("type", ""))
	if t == "effect_tick":
		return 0.01
	if t == "status_skip":
		return 0.35
	if t == "awaken":
		return 1.2 / maxf(1.0, float(ev.get("volley", 1)))
	if bool(ev.get("crit", false)):
		return 1.3
	return 0.6

var _cur_round := 0

func _play_event(ev: Dictionary) -> void:
	if ev.has("round") and int(ev["round"]) != _cur_round:
		_cur_round = int(ev["round"])
	match String(ev.get("type", "")):
		"normal", "double", "awaken":
			var atk: Dictionary = _find(String(ev.get("attacker", "")))
			var dfn: Dictionary = _find(String(ev.get("defender", "")))
			if String(ev.get("type", "")) == "awaken":
				if bool(ev.get("volley_lead", false)):
					_super_attack_fx(atk)
			_sync_gauge(ev)
			var is_crit := bool(ev.get("crit", false)) and int(ev.get("damage", 0)) > 0
			if not atk.is_empty(): _cue(atk, is_crit)
			if bool(ev.get("miss", false)):
				Bgm.sfx("effect_evade")
				_fx_text(dfn, "battle_miss_kr", "MISS", Color(0.8, 0.8, 0.8), "scene_adventure_txt_miss")
				_log(_L["miss"] % [_disp(ev.get("defender", "")), _disp(ev.get("attacker", ""))])
			else:
				if int(ev.get("damage", 0)) > 0:
					if is_crit and String(atk.get("kind", "")) == "party":
						await _critical_sequence(atk, dfn)
					elif not (is_crit and String(atk.get("kind", "")) == "enemy"):
						_strike(dfn, false, 1)
					if String(dfn.get("kind", "")) == "enemy":
						_hit_talk()
					_hurt(dfn, int(ev["damage"]), is_crit)
					_attr_particles(dfn, String(atk.get("element", "")), is_crit, int(atk.get("voice_critical", 0)))
				if bool(ev.get("block", false)):
					_fx_text(dfn, "battle_block_kr", "BLOCK", Color(0.6, 0.8, 1.0)); Bgm.sfx("effect_block")
				_shield_impact(dfn, int(ev.get("def_skill_id", 0)))
				if bool(ev.get("dead", false)): _kill(dfn)
				if int(ev.get("lifesteal", 0)) > 0:
					_vamp_impact(dfn, atk)
					_heal(atk, int(ev["lifesteal"]))
				if int(ev.get("reflect", 0)) > 0:
					_hurt(atk, int(ev["reflect"]), false)
					if bool(ev.get("reflect_dead", false)): _kill(atk)
				if not bool(ev.get("dead", false)):
					_log(_attack_line(ev, is_crit))
				if int(ev.get("lifesteal", 0)) > 0:
					_log(_L["vamp"] % [_disp(ev.get("attacker", "")),
						_disp(ev.get("defender", "")), int(ev["lifesteal"])])
				if int(ev.get("reflect", 0)) > 0:
					_log(_L["reflect"] % [_disp(ev.get("defender", "")),
						_disp(ev.get("attacker", "")), _skill_name_of(int(ev.get("def_skill_id", 0))),
						int(ev["reflect"])])
		"skill":
			_play_skill(ev)
		"confused":
			var a: Dictionary = _find(String(ev.get("actor", "")))
			_hurt(a, int(ev.get("damage", 0)), false)
			if bool(ev.get("dead", false)): _kill(a)
			_log(_L["confuse"] % [_disp(ev.get("actor", "")), "혼란", int(ev.get("damage", 0))])
		"dot", "timed":
			var tg: Dictionary = _find(String(ev.get("target", "")))
			_hurt(tg, int(ev.get("damage", 0)), false)
			_bicon_add(tg, int(ev.get("source", 0)), false, int(ev.get("turns", 0)))
			_burning_fx(tg)
			if bool(ev.get("dead", false)): _kill(tg)
			if String(ev.get("type", "")) == "timed":
				_log(_L["pass"] % [_disp(ev.get("target", "")), int(ev.get("damage", 0))])
			else:
				_log(_L["dot"] % [_disp(ev.get("target", "")), int(ev.get("damage", 0))])
		"status_skip":
			_bicon_add(_find(String(ev.get("actor", ""))), int(ev.get("source", 0)), false, int(ev.get("turns", 0)))
			_log(_L["stop"] % _disp(ev.get("actor", "")))
		"effect_tick":
			_bicon_tick(_find(String(ev.get("target", ""))), int(ev.get("source", 0)),
				int(ev.get("turns", 0)))

func _play_skill(ev: Dictionary) -> void:
	var caster: Dictionary = _find(String(ev.get("caster", "")))
	_sync_gauge(ev)
	if not caster.is_empty(): _cue(caster)
	var sname := String(ev.get("skill_name", "스킬"))
	_skill_banner(sname)
	var tgt: Dictionary = _find(String(ev.get("target", "")))
	var immune := bool(ev.get("immune", false))
	_skill_fx(ev, caster, tgt, immune)
	if immune:
		_fx_text(tgt, "", "면역", Color(0.75, 0.9, 1.0))
		_log("%s! %s — 상태이상 면역" % [sname, _disp(ev.get("target", ""))])
		return
	if bool(ev.get("interrupt", false)):
		_log(_L["skill_blk"] % [_disp(ev.get("caster", "")), _disp(ev.get("target", "")),
			String(ev.get("nullified_name", sname))])
		return
	if int(ev.get("damage", 0)) > 0:
		_hurt(tgt, int(ev["damage"]), false)
		if bool(ev.get("dead", false)): _kill(tgt)
	if int(ev.get("heal", 0)) > 0:
		_heal(tgt, int(ev["heal"]))
	if int(ev.get("target_loss", 0)) > 0:
		_hurt(tgt, int(ev["target_loss"]), false)
	if int(ev.get("self_loss", 0)) > 0:
		_hurt(caster, int(ev["self_loss"]), false)
	if ev.has("debuff"):
		_fx_text(tgt, "", String(ev["debuff"]), Color(0.9, 0.6, 1.0))
		_bicon_add(tgt, int(ev.get("skill_id", 0)), false, int(ev.get("turns", 0)),
			int(ev.get("stacks", 0)))
	if bool(ev.get("cleanse", false)):
		_fx_text(tgt, "", "정화", Color(0.7, 1.0, 0.8))
	var scat := String(Data.skills.get(str(int(ev.get("skill_id", 0))), {}).get("category", ""))
	if scat == "buff" or scat == "defense":
		_bicon_add(caster, int(ev.get("skill_id", 0)), true, int(ev.get("turns", 0)))
	if ev.has("timed_turns"):
		_log(_L["bomb"] % [_disp(ev.get("caster", "")), sname])
	elif int(ev.get("damage", 0)) > 0:
		_log(_L["skill_atk"] % [_disp(ev.get("caster", "")), sname,
			_disp(ev.get("target", "")), int(ev.get("damage", 0))])
	else:
		_log(_L["dot_on"] % [_disp(ev.get("caster", "")), _disp(ev.get("target", "")), sname])

const _SKILL_SPINE_SEC := 0.7

const _SKILL_FX := {
	"attack":    {"col": Color(1.0, 0.5, 0.2), "on": "target"},
	"debuff":    {"col": Color(0.85, 0.4, 1.0), "on": "target"},
	"heal":      {"col": Color(0.4, 1.0, 0.5), "on": "target"},
	"buff":      {"col": Color(1.0, 0.85, 0.3), "on": "caster"},
	"defense":   {"col": Color(0.4, 0.7, 1.0), "on": "caster"},
	"cleanse":   {"col": Color(0.8, 1.0, 0.9), "on": "target"},
	"interrupt": {"col": Color(1.0, 0.9, 0.4), "on": "target"},
}
const _SKILL_SFX := {
	"attack": "effect_bite", "heal": "effect_blink", "debuff": "effect_dark_clap",
	"buff": "effect_buildup", "defense": "effect_block", "cleanse": "effect_blink",
	"dot": "effect_burn", "reflect": "effect_bomb",
}
const _ELEM_SFX := {"fire": "effect_burn", "chaos": "effect_bomb", "dark": "effect_dark_clap"}
func _skill_fx(ev: Dictionary, caster: Dictionary, target: Dictionary, immune := false) -> void:
	var sid := int(ev.get("skill_id", 0))
	var sdef: Dictionary = Data.skills.get(str(sid), {})
	var cat := String(sdef.get("category", "attack"))
	var sel := String(sdef.get("element", ""))
	var own := "effect_skill_%d" % sid
	if sid > 0 and ResourceLoader.exists("res://assets/music/%s.mp3" % own):
		Bgm.sfx(own)
	else:
		Bgm.sfx(_ELEM_SFX.get(sel, _SKILL_SFX.get(cat, "effect_cut_in")))
	if immune:
		return
	if sid > 0 and _play_skill_spine(sid, (target if not target.is_empty() else caster)):
		return
	var spec: Dictionary = _SKILL_FX.get(cat, _SKILL_FX["attack"])
	var v: Dictionary = caster if String(spec["on"]) == "caster" else target
	if v.is_empty(): v = caster
	if v.is_empty() or not v.has("center"): return
	var center: Vector2 = v["center"]
	_fx_ring(center, spec["col"])
	var icon_p := "res://assets/converted/skill/skill_%d.tres" % sid
	if ResourceLoader.exists(icon_p):
		var ic := Sprite2D.new(); ic.texture = load(icon_p); ic.material = _pma
		ic.position = center + Vector2(0, -8); ic.z_index = 101; ic.scale = Vector2(0.3, 0.3)
		add_child(ic)
		var t := create_tween()
		t.tween_property(ic, "scale", Vector2(1.05, 1.05), 0.16).set_trans(Tween.TRANS_BACK)
		t.tween_interval(0.14)
		t.tween_property(ic, "modulate:a", 0.0, 0.22)
		t.parallel().tween_property(ic, "scale", Vector2(1.35, 1.35), 0.22)
		t.tween_callback(ic.queue_free)

func _fx_ring(center: Vector2, col: Color) -> void:
	var ring := Line2D.new()
	ring.width = 5.0; ring.default_color = col; ring.closed = true; ring.antialiased = true
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		pts.append(Vector2(cos(a), sin(a)) * 42.0)
	ring.points = pts
	ring.position = center; ring.z_index = 100; ring.scale = Vector2(0.25, 0.25)
	add_child(ring)
	var t := create_tween()
	t.tween_property(ring, "scale", Vector2(1.7, 1.7), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(ring, "modulate:a", 0.0, 0.4)
	t.tween_callback(ring.queue_free)

const _HP_BAR := "res://assets/converted/battle_extra/hp_bar10.png"
const _HP_BAR_MONSTER := "res://assets/converted/battle_extra/hp_bar9.png"
func _hp_fill(w: float, h: float, monster := false) -> NinePatchRect:
	var np := NinePatchRect.new()
	var tex_path := _HP_BAR_MONSTER if monster else _HP_BAR
	if not ResourceLoader.exists(tex_path): tex_path = _HP_BAR
	if ResourceLoader.exists(tex_path):
		np.texture = load(tex_path)
	np.patch_margin_left = 8; np.patch_margin_right = 8
	np.patch_margin_top = 3; np.patch_margin_bottom = 3
	np.size = Vector2(w, h); np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return np

func _refresh_bar(v: Dictionary) -> void:
	var frac := clampf(float(v["hp"]) / maxf(1.0, float(v["hp_max"])), 0.0, 1.0)
	var fill: Control = v["hp_fill"]
	fill.size.x = maxf(0.0, float(v["bar_w"]) * frac)
	(v["hp_label"] as Label).text = "%d / %d" % [int(v["hp"]), int(v["hp_max"])]

func _hurt(v: Dictionary, dmg: int, crit: bool) -> void:
	if v.is_empty(): return
	if String(v.get("kind", "")) == "party":
		Bgm.sfx("effect_dragon_damaged_%d" % (1 + (randi() & 1)))
	v["hp"] = maxi(0, int(v["hp"]) - dmg)
	var fill: Control = v["hp_fill"]
	var frac := clampf(float(v["hp"]) / maxf(1.0, float(v["hp_max"])), 0.0, 1.0)
	create_tween().tween_property(fill, "size:x", maxf(0.0, float(v["bar_w"]) * frac), 0.25)
	(v["hp_label"] as Label).text = "%d / %d" % [int(v["hp"]), int(v["hp_max"])]
	_dmg_number(v["center"], dmg, crit)
	if String(v.get("kind", "")) == "enemy":
		_monster_hit_motion(v)
	else:
		var node: Node = v["node"]
		if node is CanvasItem:
			var ci := node as CanvasItem
			var t := create_tween()
			t.tween_property(ci, "modulate", Color(1.4, 0.5, 0.5), 0.06)
			t.tween_property(ci, "modulate", Color.WHITE, 0.14)
		_screen_shake(8.0 if crit else 4.0)
	_check_groggy(v)

const _GROGGY_HP_RATIO := 0.25
func _check_groggy(v: Dictionary) -> void:
	if v.is_empty() or String(v.get("kind", "")) != "enemy": return
	if bool(v.get("groggy", false)) or not bool(v.get("alive", true)): return
	if float(v["hp"]) > float(v["hp_max"]) * _GROGGY_HP_RATIO: return
	var ap = v.get("anim")
	if ap is AnimationPlayer and (ap as AnimationPlayer).has_animation("groggy"):
		(ap as AnimationPlayer).play("groggy")
		v["groggy"] = true

var _shake_cam: Camera2D
var _shake_tw: Tween
func _screen_shake(intensity: float = 6.0) -> void:
	if not is_instance_valid(_shake_cam):
		_shake_cam = Camera2D.new()
		_shake_cam.position = _vis() * 0.5
		add_child(_shake_cam)
		_shake_cam.make_current()
	if is_instance_valid(_shake_tw): _shake_tw.kill()
	_shake_tw = create_tween()
	var amt := intensity
	for i in 5:
		var off := Vector2(randf_range(-amt, amt), randf_range(-amt, amt))
		_shake_tw.tween_property(_shake_cam, "offset", off, 0.03)
		amt *= 0.68
	_shake_tw.tween_property(_shake_cam, "offset", Vector2.ZERO, 0.05)

const _ELEM_COL := {
	"fire": Color(1.0, 0.45, 0.2), "aqua": Color(0.35, 0.7, 1.0), "wind": Color(0.5, 1.0, 0.6),
	"earth": Color(0.8, 0.6, 0.35), "light": Color(1.0, 0.95, 0.5), "dark": Color(0.7, 0.4, 1.0),
	"holy": Color(1.0, 0.9, 0.45), "chaos": Color(1.0, 0.4, 0.85), "shadow": Color(0.6, 0.55, 0.8),
}
const _CRIT_SFX := {
	"fire": "effect_critical_fire_1", "aqua": "effect_critical_ice_1",
	"wind": "effect_critical_lightning_1", "light": "effect_critical_lightning_1",
}
func _attr_particles(v: Dictionary, element: String, crit: bool, crit_voice := 0) -> void:
	if v.is_empty(): return
	var col: Color = _ELEM_COL.get(element, Color(1, 1, 1))
	var p := CPUParticles2D.new()
	p.position = v["center"]
	p.z_index = 95
	p.one_shot = true; p.explosiveness = 1.0
	p.amount = 18 if crit else 11
	p.lifetime = 0.5
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 12.0
	p.direction = Vector2(-1, -0.4); p.spread = 130.0
	p.initial_velocity_min = 80.0; p.initial_velocity_max = (240.0 if crit else 170.0)
	p.gravity = Vector2(0, 180.0)
	p.scale_amount_min = 2.0; p.scale_amount_max = (5.0 if crit else 3.5)
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.95)); g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = g
	var mat := CanvasItemMaterial.new(); mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	add_child(p)
	p.emitting = true
	get_tree().create_timer(0.9).timeout.connect(func(): if is_instance_valid(p): p.queue_free())

func _burning_fx(v: Dictionary) -> void:
	if v.is_empty() or not v.has("center"): return
	var p := CPUParticles2D.new()
	p.position = (v["center"] as Vector2) + Vector2(0, 10)
	p.z_index = 96
	p.one_shot = true; p.explosiveness = 0.4
	p.amount = 14
	p.lifetime = 0.6
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(28, 6)
	p.direction = Vector2(0, -1); p.spread = 24.0
	p.initial_velocity_min = 60.0; p.initial_velocity_max = 130.0
	p.gravity = Vector2(0, -40.0)
	p.scale_amount_min = 2.5; p.scale_amount_max = 5.0
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.3, 0.95))
	g.add_point(0.5, Color(1.0, 0.5, 0.15, 0.7))
	g.set_color(1, Color(0.8, 0.2, 0.1, 0.0))
	p.color_ramp = g
	var mat := CanvasItemMaterial.new(); mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	add_child(p); p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(func(): if is_instance_valid(p): p.queue_free())

func _heal(v: Dictionary, amt: int) -> void:
	if v.is_empty(): return
	v["hp"] = mini(int(v["hp_max"]), int(v["hp"]) + amt)
	var fill: Control = v["hp_fill"]
	var frac := clampf(float(v["hp"]) / maxf(1.0, float(v["hp_max"])), 0.0, 1.0)
	create_tween().tween_property(fill, "size:x", float(v["bar_w"]) * frac, 0.25)
	(v["hp_label"] as Label).text = "%d / %d" % [int(v["hp"]), int(v["hp_max"])]
	_heal_number(v["center"], amt)

const _HEAL_FONT := "res://assets/480/font/font_heal.fnt"
var _heal_font_cache: Font = null
func _heal_number(pos: Vector2, amt: int) -> void:
	var l := Label.new()
	l.text = str(amt)
	if _heal_font_cache == null and ResourceLoader.exists(_HEAL_FONT):
		_heal_font_cache = load(_HEAL_FONT)
	if _heal_font_cache != null:
		l.add_theme_font_override("font", _heal_font_cache)
	else:
		l.text = "+%d" % amt
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
	l.add_theme_color_override("font_outline_color", Color(0, 0.25, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.z_index = 101
	l.position = pos + Vector2(-10, -16)
	add_child(l)
	var t := create_tween()
	t.tween_property(l, "position:y", l.position.y - 44, 0.6)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)

func _kill(v: Dictionary) -> void:
	if v.is_empty() or not bool(v.get("alive", true)): return
	v["alive"] = false
	_bicon_clear(v)
	Bgm.sfx("effect_dead")
	if v.has("center"):
		CocosParticle.spawn(self, "pt_monster_dead_2_2", v["center"], 98, 0.9)
	var node: Node = v["node"]
	if node is CanvasItem:
		create_tween().tween_property(node, "modulate:a", 0.25 if v["kind"] == "party" else 0.0, 0.4)
	if String(v.get("kind", "")) == "enemy":
		var mn := String(_enemy.get("name", "몬스터"))
		_log("%s%s 힘없이 비틀거리다가 쓰러졌다." % [mn, _josa(mn, "은", "는")])
		_story_event("KILL", _stage_rec(), {"monster": int(_enemy.get("id", -1))})
		if node is Node2D:
			var n2 := node as Node2D
			var t := n2.create_tween()
			t.tween_property(n2, "rotation", 0.12, 0.18).set_trans(Tween.TRANS_SINE)
			t.tween_property(n2, "rotation", -0.14, 0.20).set_trans(Tween.TRANS_SINE)
			t.tween_property(n2, "rotation", 0.5, 0.35).set_trans(Tween.TRANS_BACK)
			t.parallel().tween_property(n2, "position:y", n2.position.y + 60.0, 0.35)

func _josa(word: String, with_batchim: String, without: String) -> String:
	if word.is_empty(): return without
	var c := word.unicode_at(word.length() - 1)
	if c < 0xAC00 or c > 0xD7A3: return without
	return with_batchim if ((c - 0xAC00) % 28) != 0 else without

func _cue(v: Dictionary, critical := false) -> void:
	if v.is_empty() or not bool(v.get("alive", true)): return
	var node: Node = v["node"]
	if v["kind"] == "enemy" and node is Node2D:
		if critical:
			_monster_critical_attack(v)
		else:
			_monster_attack(v)
	elif v["kind"] == "party" and node is Control:
		var base: Vector2 = v["base_pos"]
		var center: Vector2 = v["center"]
		var enemy_c: Vector2 = _views.get("E0", {}).get("center", center + Vector2(0, -80))
		var dir: Vector2 = (enemy_c - center).normalized()
		var t := create_tween()
		t.tween_property(node, "position", base + dir * 34.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(node, "scale", Vector2(1.08, 1.08), 0.1)
		t.tween_property(node, "position", base, 0.16).set_trans(Tween.TRANS_QUAD)
		t.parallel().tween_property(node, "scale", Vector2.ONE, 0.16)

func _monster_income(node: Node2D) -> void:
	var vis := _vis()
	var boss := _is_boss()
	var flash := ColorRect.new()
	flash.color = Color(0.8, 0.24, 0.24, 0.0) if boss else Color(0.918, 0.918, 0.918, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fl := CanvasLayer.new(); fl.layer = 90; add_child(fl); fl.add_child(flash)
	var ft := flash.create_tween()
	if boss:
		ft.tween_interval(0.3)
		ft.tween_property(flash, "color:a", 1.0, 0.2)
	else:
		ft.tween_property(flash, "color:a", 200.0 / 255.0, 0.2)
	ft.tween_property(flash, "color:a", 0.0, 0.7)
	ft.tween_callback(fl.queue_free)
	_levelup_particle("pt_monster_income_1", vis.x * 0.5, 40.0)
	Bgm.sfx("effect_monster_in")
	if node == null or not is_instance_valid(node):
		return
	var base: Vector2 = node.scale
	var pos: Vector2 = node.position
	node.scale = base
	var t := node.create_tween()
	t.tween_property(node, "scale", base * 1.2, 0.3)
	t.parallel().tween_property(node, "position", pos + Vector2(0, -130), 0.3)
	t.tween_property(node, "scale", Vector2(base.x * 0.9, base.y * 0.8), 0.15)
	t.parallel().tween_property(node, "position", pos + Vector2(0, -10), 0.15)
	t.tween_callback(func(): _screen_shake(10.0))
	t.tween_property(node, "scale", base, 0.2)
	t.parallel().tween_property(node, "position", pos, 0.2)

const _MON_ATK_JITTER := 4.0
const _MON_ATK_REPEAT := 8
func _monster_attack(v: Dictionary) -> void:
	var node: Node2D = v["node"]
	var base_pos: Vector2 = v["base_pos"]
	var att: Sprite2D = v.get("att_node")
	var sp := maxf(0.5, _speed)
	var target: Node2D = node
	if att != null and is_instance_valid(att):
		att.position = base_pos
		att.scale = Vector2.ONE * 1.6
		node.visible = false; att.visible = true
		target = att
	var base_scale: Vector2 = target.scale
	var t := target.create_tween()
	t.tween_property(target, "scale", base_scale * 2.2, 0.15 / sp)
	t.tween_property(target, "scale", base_scale * 2.0, 0.05 / sp)
	var d := _MON_ATK_JITTER
	for i in _MON_ATK_REPEAT:
		for off in [Vector2(d, d), Vector2(-d, -d), Vector2(-d, d), Vector2(d, -d), Vector2.ZERO]:
			t.tween_property(target, "position", base_pos + off, 0.02 / sp)
	t.tween_property(target, "scale", base_scale, 0.1 / sp)
	t.tween_callback(func():
		if is_instance_valid(node): node.visible = true
		if att != null and is_instance_valid(att): att.visible = false)

const _MON_CRIT_EFFECT_START_SCALE := 1.7
const _MON_CRIT_EFFECT_PEAK_SCALE := 2.3
const _MON_CRIT_EFFECT_END_SCALE := 2.1
const _MON_CRIT_EFFECT_JITTER := 12.0
const _MON_CRIT_EFFECT_REPEAT := 8
const _MON_CRIT_POSE_REPEAT := 10
func _monster_critical_attack(v: Dictionary) -> void:
	var node := v.get("node") as Node2D
	if node == null or not is_instance_valid(node):
		return
	var sp := maxf(0.5, _speed)
	var base_pos: Vector2 = v.get("base_pos", node.position)
	var boss := _is_boss()
	var mid := int(_enemy.get("id", 0))
	var mdir := "monster_%d" % mid
	var mman := _man(mdir)

	var pose: Node2D = null
	var owns_pose := false
	if boss:
		pose = _spr(mdir, "monster_%d_%d_image_att_cri" % [mid, mid], mman, 1.6)
		if pose != null:
			pose.position = base_pos
			pose.visible = true
			pose.z_index = node.z_index
			add_child(pose)
			owns_pose = true
	if pose == null:
		pose = v.get("att_node") as Sprite2D
		if pose != null and is_instance_valid(pose):
			pose.scale = Vector2.ONE * 1.6
	if pose == null or not is_instance_valid(pose):
		pose = node
	if pose != node:
		node.visible = false
		pose.visible = true
		pose.position = base_pos
	var pose_scale := pose.scale
	var pt := pose.create_tween()
	pt.tween_property(pose, "scale", pose_scale * 2.15, 0.1 / sp)
	var pd := 3.0
	for i in _MON_CRIT_POSE_REPEAT:
		for off in [Vector2(pd, pd), Vector2(-pd, -pd), Vector2(-pd, pd), Vector2(pd, -pd), Vector2.ZERO]:
			pt.tween_property(pose, "position", base_pos + off, 0.02 / sp)
	pt.tween_property(pose, "scale", pose_scale * 2.0, 0.05 / sp)
	pt.tween_callback(func():
		if is_instance_valid(node): node.visible = true
		if owns_pose and is_instance_valid(pose):
			pose.queue_free()
		elif is_instance_valid(pose):
			pose.scale = pose_scale
			if pose != node:
				pose.visible = false)

	Bgm.sfx("effect_critical_ice_2")
	var effect_key := ("monster_%d_%d_image_att_effect_cri" % [mid, mid] if boss
		else "monster_%d_%d_image_att_effect" % [mid, mid])
	var effect := _spr(mdir, effect_key, mman,
		Design.ASSET_SCALE * _MON_CRIT_EFFECT_START_SCALE)
	if effect == null:
		return
	var center := _vis() * 0.5
	effect.position = center
	effect.modulate.a = 0.0
	effect.z_index = 120
	var lay := CanvasLayer.new()
	lay.layer = 35
	add_child(lay)
	lay.add_child(effect)
	var et := effect.create_tween()
	et.tween_interval(0.15 / sp)
	et.tween_property(effect, "modulate:a", 1.0, 0.3 / sp)
	et.parallel().tween_property(effect, "scale",
		Vector2.ONE * Design.ASSET_SCALE * _MON_CRIT_EFFECT_PEAK_SCALE, 0.3 / sp)
	var ed := _MON_CRIT_EFFECT_JITTER
	for i in _MON_CRIT_EFFECT_REPEAT:
		for off in [Vector2(ed, -ed), Vector2(-ed, ed), Vector2(-ed, -ed), Vector2(ed, ed), Vector2.ZERO]:
			et.tween_property(effect, "position", center + off, 0.02 / sp)
	et.tween_property(effect, "scale",
		Vector2.ONE * Design.ASSET_SCALE * _MON_CRIT_EFFECT_END_SCALE, 0.05 / sp)
	et.parallel().tween_property(effect, "modulate:a", 0.0, 0.05 / sp)
	et.tween_callback(func(): if is_instance_valid(lay): lay.queue_free())

func _monster_hit_motion(v: Dictionary) -> void:
	var node: Node2D = v.get("node")
	if node == null or not is_instance_valid(node): return
	var sp := maxf(0.5, _speed)
	var hit: Sprite2D = v.get("hit_node")
	var target: CanvasItem = node
	if hit != null and is_instance_valid(hit):
		hit.position = v["base_pos"]
		node.visible = false; hit.visible = true
		target = hit
	var red := Color(1, 0, 0)
	var white := Color.WHITE
	var t := target.create_tween()
	for i in 2:
		t.tween_callback(func(): if is_instance_valid(target): target.modulate = red)
		t.tween_interval(0.025 / sp)
		t.tween_callback(func(): if is_instance_valid(target): target.modulate = white)
		t.tween_interval(0.05 / sp)
	t.tween_callback(func():
		if is_instance_valid(target): target.modulate = white
		if hit != null and is_instance_valid(hit): hit.visible = false
		if is_instance_valid(node): node.visible = true)
	_screen_shake(10.0)

func _crit_hits(caster: Dictionary) -> int:
	var n := int(caster.get("critical_hit", 0))
	if n <= 0:
		n = int((Data.combat.get("judge", {}) as Dictionary).get("crit_hits", 1))
	return maxi(1, n)

func _strike(target: Dictionary, crit: bool, hits: int) -> void:
	var n := maxi(1, hits)
	for i in n:
		if i > 0:
			await get_tree().create_timer(0.1 / maxf(0.5, _speed)).timeout
			if not is_inside_tree() or target.is_empty():
				return
		var attack_sfx_played := _normal_attack_fx(target, _CRIT_FX if crit else {})
		if attack_sfx_played and String(target.get("kind", "")) == "enemy":
			_queue_monster_hit_sfx()
		_normal_impact(target, crit and i == n - 1)
		if i == n - 1:
			_hit_crack(target, crit)

const _MONSTER_HIT_SFX_DELAY := 0.2
func _queue_monster_hit_sfx() -> void:
	var timer := get_tree().create_timer(_MONSTER_HIT_SFX_DELAY / maxf(0.5, _speed))
	timer.timeout.connect(func():
		if is_instance_valid(self) and is_inside_tree():
			Bgm.sfx("effect_dragon_damaged_%d" % (1 + (randi() & 1))))

func _critical_sequence(caster: Dictionary, target: Dictionary) -> void:
	_start_critical_audio(caster)
	await get_tree().create_timer(_CUTIN_TOTAL / maxf(0.5, _speed)).timeout
	if not is_inside_tree():
		return
	var n := _crit_hits(caster)
	await _strike(target, true, n)
	if not is_inside_tree():
		return
	await get_tree().create_timer(_HIT_FX_DUR / maxf(0.5, _speed)).timeout
	if not is_inside_tree():
		return
	if not _critical_art(caster):
		_critical_fx_band(caster)

func _start_critical_audio(caster: Dictionary) -> void:
	_critical_cutin(caster)
	var voice_delay := CritCutin.VOICE_DELAY / maxf(0.5, _speed)
	get_tree().create_timer(voice_delay).timeout.connect(_crit_voice.bind(caster))

func _critical_voice_no(dragon_id: int, ddef: Dictionary) -> int:
	var direct := int(ddef.get("voice_critical", 0))
	if direct > 0:
		return direct
	return int(Icons.voice_row(dragon_id).get("critical", 0))

func _crit_voice(caster: Dictionary) -> void:
	var v := int(caster.get("voice_critical", 0))
	if v > 0:
		Bgm.sfx("voice%d" % v)
	else:
		Bgm.sfx(_CRIT_SFX.get(String(caster.get("element", "")), "effect_critical"))

func _critical_art(caster: Dictionary) -> bool:
	var cid := int(caster.get("id", 0))
	var dir := "critical_%d" % cid
	var man := _man(dir)
	if man.is_empty():
		return false
	var key := "dragon_dragon_%d_critical_critical" % cid
	if bool(caster.get("awakened", false)):
		var ekey := "dragon_dragon_%d_critical_e_critical" % cid
		if man.has(ekey):
			key = ekey
	var ent: Dictionary = man.get(key, {})
	var src: Array = ent.get("src", [ent.get("w", 0), ent.get("h", 0)])
	var sw := float(src[0])
	if sw <= 0.0:
		return false
	var vis := _vis()
	var s := vis.x / sw
	var spr := _spr(dir, key, man, s)
	if spr == null:
		return false
	var off: Array = ent.get("off", [0, 0])
	spr.position = vis * 0.5 + Vector2(float(off[0]), -float(off[1])) * s
	spr.z_index = 120
	var lay := CanvasLayer.new()
	lay.layer = 41
	add_child(lay)
	lay.add_child(spr)
	var t := spr.create_tween()
	t.tween_interval(0.45 / maxf(0.5, _speed))
	t.tween_property(spr, "modulate:a", 0.0, 0.18)
	t.tween_callback(func(): if is_instance_valid(lay): lay.queue_free())
	return true

func _critical_fx_band(caster: Dictionary) -> bool:
	var cid := int(caster.get("id", 0))
	var dir := "dragon_%d_fx" % cid
	var man := _man(dir)
	if man.is_empty():
		return false
	var keys: Array = []
	for k in man:
		if String(k).begins_with("dragon_%d_adv_action" % cid):
			keys.append(String(k))
	if keys.is_empty():
		return false
	keys.sort()
	var key: String = keys[randi() % keys.size()]
	var ent: Dictionary = man.get(key, {})
	var w := float(ent.get("w", 0))
	if w <= 0.0:
		return false
	var vis := _vis()
	var spr := _spr(dir, key, man, vis.x / w)
	if spr == null:
		return false
	spr.position = vis * 0.5
	spr.z_index = 120
	var lay := CanvasLayer.new()
	lay.layer = 41
	add_child(lay)
	lay.add_child(spr)
	var t := spr.create_tween()
	t.tween_interval(0.45 / maxf(0.5, _speed))
	t.tween_property(spr, "modulate:a", 0.0, 0.18)
	t.tween_callback(func(): if is_instance_valid(lay): lay.queue_free())
	return true

const _ATK_FX := [
	{"scene": "skill_1_bite_spine", "sfx": "effect_bite", "scale": 1.0, "flip": false},
	{"scene": "skill_1_scratch_spine", "sfx": "effect_scratch", "scale": 1.0, "flip": true},
]

const _CRIT_FX := {"scene": "skill_1_hit_spine", "sfx": "effect_headbutt", "scale": 2.5, "flip": false}
const _HIT_FX_DUR := 0.2
func _normal_attack_fx(target: Dictionary, entry := {}) -> bool:
	if target.is_empty(): return false
	var pick: Dictionary = entry if not entry.is_empty() else _ATK_FX[randi() % _ATK_FX.size()]
	var path := "res://scenes/fx/%s.tscn" % pick["scene"]
	if not ResourceLoader.exists(path):
		return false
	var holder := Node2D.new()
	holder.z_index = 10
	add_child(holder)
	holder.position = target.get("center", _vis() * 0.5)
	var bs: Vector2 = target.get("base_scale", Vector2.ONE)
	var s := float(pick["scale"])
	holder.scale = Vector2(-s if bool(pick["flip"]) else s, s) * bs
	var inst = (load(path) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
	if ap == null or not ap.has_animation("animation"):
		holder.queue_free()
		return false
	ap.get_animation("animation").loop_mode = Animation.LOOP_NONE
	ap.play("animation")
	Bgm.sfx(String(pick["sfx"]))
	var t := holder.create_tween()
	t.tween_interval(ap.get_animation("animation").length / maxf(0.5, _speed))
	t.tween_callback(holder.queue_free)
	return true

func _normal_impact(v: Dictionary, crit: bool) -> void:
	if v.is_empty(): return
	var c: Vector2 = v.get("center", _vis() * 0.5)
	var b := _spr("adventure_ui", "scene_adventure_effect_bullet", _adv, 1.0)
	if b:
		b.position = c
		b.z_index = 95
		b.scale = Vector2(0.35, 0.35) * (1.25 if crit else 1.0)
		var am := CanvasItemMaterial.new(); am.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		b.material = am
		add_child(b)
		var tb := b.create_tween()
		tb.tween_property(b, "scale", Vector2(0.72, 0.72) * (1.25 if crit else 1.0), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tb.parallel().tween_property(b, "rotation", randf_range(-0.3, 0.3), 0.12)
		tb.tween_property(b, "modulate:a", 0.0, 0.16)
		tb.tween_callback(b.queue_free)

func _hit_crack(v: Dictionary, crit: bool) -> void:
	if v.is_empty(): return
	var man := _man("hit_effect")
	var f1 := _spr("hit_effect", "monster_hit_effect_hit_effect_1", man, Design.ASSET_SCALE)
	if f1 == null: return
	var c: Vector2 = v.get("center", _vis() * 0.5)
	f1.position = c
	f1.z_index = 97
	f1.scale *= (1.25 if crit else 1.0)
	f1.rotation += randf_range(-0.25, 0.25)
	add_child(f1)
	var f2 := _spr("hit_effect", "monster_hit_effect_hit_effect_2", man, Design.ASSET_SCALE)
	if f2:
		f2.position = c; f2.z_index = 97; f2.visible = false
		f2.scale = f1.scale; f2.rotation = f1.rotation
		add_child(f2)
	var t := create_tween()
	t.tween_interval(0.07)
	t.tween_callback(func():
		if is_instance_valid(f1): f1.visible = false
		if is_instance_valid(f2): f2.visible = true)
	t.tween_interval(0.10)
	t.tween_callback(func():
		for n: Sprite2D in [f1, f2]:
			if not is_instance_valid(n): continue
			var ft: Tween = n.create_tween()
			ft.tween_property(n, "modulate:a", 0.0, 0.18)
			ft.parallel().tween_property(n, "scale", n.scale * 1.15, 0.18)
			ft.tween_callback(n.queue_free))

var _hit_talk_keys: Array = []
var _hit_talk_node: Node2D = null
const _HIT_TALK_W := 0.293
const _HIT_TALK_CX := 0.696
const _HIT_TALK_CY := 0.174

func _hit_talk() -> void:
	if _hit_talk_keys.is_empty():
		var man := _man("hit_talk")
		for k in man.keys():
			if String(k).ends_with("_KR"): _hit_talk_keys.append(String(k))
		_hit_talk_keys.sort()
	if _hit_talk_keys.is_empty(): return
	if is_instance_valid(_hit_talk_node):
		_hit_talk_node.queue_free()
		_hit_talk_node = null
	var key: String = _hit_talk_keys[randi() % _hit_talk_keys.size()]
	var man2 := _man("hit_talk")
	var info: Dictionary = man2.get(key, {})
	var w := maxf(1.0, float(info.get("w", 180)))
	var vis := _vis()
	var sp := _spr("hit_talk", key, man2, (vis.x * _HIT_TALK_W) / w)
	if sp == null: return
	sp.position = Vector2(vis.x * _HIT_TALK_CX, vis.y * _HIT_TALK_CY)
	_hit_talk_node = sp
	sp.rotation = randf_range(-0.12, 0.12)
	sp.z_index = 99
	add_child(sp)
	sp.scale *= 0.5
	var target := sp.scale * 2.0
	var t := sp.create_tween()
	t.tween_property(sp, "scale", target, 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.30)
	t.tween_property(sp, "modulate:a", 0.0, 0.20)
	t.tween_callback(sp.queue_free)

const _CUTIN_TOTAL := CritCutin.TOTAL

func _critical_cutin(caster: Dictionary) -> void:
	CritCutin.show(self, caster, _speed)

func _critical_spine(caster: Dictionary, target: Dictionary) -> bool:
	var cid := int(caster.get("art_id", caster.get("id", 0)))
	var stage := "e_critical" if bool(caster.get("awakened", false)) else "critical"
	var path := Icons.spine_scene(cid, stage)
	if path == "":
		path = Icons.spine_scene(cid, "critical")
		if path == "":
			return false
	var holder := Node2D.new()
	holder.z_index = 8
	var node = target.get("node")
	if node is Node2D and is_instance_valid(node):
		node.add_child(holder)
	else:
		add_child(holder)
		holder.position = target.get("center", _vis() * 0.5)
	holder.scale = Vector2(-1.0, 1.0)
	var inst = (load(path) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
	if ap == null:
		holder.queue_free()
		return false
	var pick := ""
	for cand in ["animation", "critical"]:
		if ap.has_animation(cand):
			pick = cand
			break
	if pick == "":
		holder.queue_free()
		return false
	ap.get_animation(pick).loop_mode = Animation.LOOP_NONE
	ap.play(pick)
	var t := holder.create_tween()
	t.tween_interval(ap.get_animation(pick).length / maxf(0.5, _speed))
	t.tween_callback(holder.queue_free)
	return true

const _NUM_FONT := "res://assets/480/font/font_normal.fnt"
var _num_font_cache: Font = null
func _dmg_number(pos: Vector2, dmg: int, crit: bool) -> void:
	var l := Label.new()
	l.text = str(dmg)
	if _num_font_cache == null and ResourceLoader.exists(_NUM_FONT):
		_num_font_cache = load(_NUM_FONT)
	if _num_font_cache != null:
		l.add_theme_font_override("font", _num_font_cache)
	var base := 56.0
	var s := 2.0 if crit else 1.5
	l.add_theme_font_size_override("font_size", int(round(base * s)))
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2) if crit else Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0.4, 0.1, 0.0, 0.9) if crit else Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6 if crit else 5)
	l.z_index = 101
	l.position = pos + Vector2(-24 if crit else -18, -60)
	add_child(l)
	const DUR := 0.9
	var dx := (112.5 if crit else 75.0) * (1.0 if (dmg % 2) == 0 else -1.0)
	l.pivot_offset = Vector2(20, 20)
	var jt := create_tween()
	jt.tween_property(l, "position:x", l.position.x + dx, DUR * 0.5).set_trans(Tween.TRANS_SINE)
	var jy := create_tween()
	jy.tween_property(l, "position:y", l.position.y - 150.0, DUR * 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	jy.tween_property(l, "position:y", l.position.y, DUR * 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var st := create_tween()
	st.tween_property(l, "scale", Vector2(1.1, 1.1), DUR * 0.05)
	st.tween_property(l, "scale", Vector2.ONE, DUR * 0.05)
	st.tween_property(l, "scale", Vector2(0.8, 0.8), DUR * 0.4)
	var ft := create_tween()
	ft.tween_interval(DUR * 0.25)
	ft.tween_property(l, "modulate:a", 0.0, DUR * 0.25).set_ease(Tween.EASE_OUT)
	ft.tween_callback(l.queue_free)

func _float(pos: Vector2, text: String, color: Color, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.position = pos + Vector2(-10, -10)
	l.z_index = 100
	add_child(l)
	var t := create_tween()
	t.tween_property(l, "position:y", l.position.y - 46, 0.6)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)

func _fx_text(v: Dictionary, frame: String, fallback: String, col: Color, adv_frame := "") -> void:
	if v.is_empty(): return
	var s: Sprite2D = null
	if frame != "":
		s = _spr("battle_ui", frame, _bat, 0.9)
	if s == null and adv_frame != "":
		s = _spr("adventure_ui", adv_frame, _adv, 0.9)
	if s:
		s.position = v["center"] + Vector2(0, -30)
		s.z_index = 100
		add_child(s)
		var t := create_tween()
		t.tween_property(s, "position:y", s.position.y - 30, 0.5)
		t.parallel().tween_property(s, "modulate:a", 0.0, 0.5)
		t.tween_callback(s.queue_free)
		return
	_float(v["center"] + Vector2(0, -20), fallback, col, 20)

func _sync_gauge(ev: Dictionary) -> void:
	if not ev.has("gauge_ally"):
		return
	var val := float(ev.get("gauge_ally", 0.0))
	for v in _views.values():
		if v is Dictionary and (v as Dictionary).get("kind") == "party":
			_set_gauge(v, val)

func _set_gauge(v: Dictionary, val: float) -> void:
	if v.is_empty() or v.get("kind") != "party": return
	v["gauge"] = val
	var fill = v.get("gauge_fill", null)
	if fill != null and is_instance_valid(fill):
		var w := float(v.get("gauge_w", 100)) * clampf(val / 100.0, 0.0, 1.0)
		create_tween().tween_property(fill, "size:x", w, 0.2)
		(fill as ColorRect).color = Color(1, 0.95, 0.5) if val >= 100.0 else Color(1, 0.8, 0.25)

const _SMALLEXP_SIZE := Vector2(250.0, 60.0)
func _small_exp_layer(uid: int, gained: int, slot: int) -> void:
	if gained <= 0:
		return
	var d := UserDB.get_dragon(uid)
	if d.is_empty():
		return
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var w := _SMALLEXP_SIZE.x
	var h := _SMALLEXP_SIZE.y
	var col := vis.x * (0.18 + 0.32 * float(clampi(slot, 0, 2)))
	var lay := CanvasLayer.new(); lay.layer = 62; add_child(lay)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.position = Vector2(col - w * 0.5 * S, vis.y - 150.0)
	root.scale = Vector2(S, S)
	root.modulate.a = 0.0
	lay.add_child(root)
	var box := NinePatchRect.new()
	box.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres")
	box.patch_margin_left = 10; box.patch_margin_right = 10
	box.patch_margin_top = 4; box.patch_margin_bottom = 4
	box.size = Vector2(w, h)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	var cm := _man("common_ui")
	var bg := _spr("common_ui", "common_bar_bg2", cm, 1.0)
	if bg:
		bg.position = Vector2(w * 0.5, h * 0.5 - 5.0)
		root.add_child(bg)
		var fill := _spr("common_ui", "common_bar_exp", cm, 1.0)
		if fill:
			var fw := float((cm.get("common_bar_exp", {}) as Dictionary).get("w", 1))
			var fh := float((cm.get("common_bar_exp", {}) as Dictionary).get("h", 1))
			fill.centered = false
			fill.position = Vector2(-fw * 0.5, -fh * 0.5)
			bg.add_child(fill)
			var lv := int(d.get("level", 1))
			var need := maxi(1, LevelSystem.exp_to_next(Data.level_curve, lv))
			var ratio: float = clampf(float(int(d.get("exp", 0)) + gained) / float(need), 0.0, 1.0)
			fill.scale = Vector2(0.0, 1.0)
			var tf := fill.create_tween()
			tf.tween_interval(0.5)
			tf.tween_property(fill, "scale", Vector2(ratio, 1.0), 0.6)
	var ic := _spr("adventure_ui", "scene_adventure_icon_exp", _adv, 1.0)
	if ic:
		ic.position = Vector2(18.0, h * 0.5 + 16.0)
		root.add_child(ic)
	var lb := _bmf_label("subtitle", 1.0)
	lb.text = "+%d" % gained
	lb.position = Vector2(36.0, h * 0.5 + 4.0)
	root.add_child(lb)
	var t := root.create_tween()
	t.tween_interval(0.3)
	t.tween_property(root, "modulate:a", 1.0, 0.25)
	t.parallel().tween_property(root, "position:y", root.position.y - 135.0, 0.25) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(root, "scale", Vector2(S + 0.2, S + 0.2), 0.25)
	t.tween_property(root, "scale", Vector2(S, S), 0.25)
	t.tween_interval(1.2)
	t.tween_property(root, "modulate:a", 0.0, 0.3)
	t.tween_callback(lay.queue_free)

const _SHIELD_SKILL := 11
func _shield_impact(v: Dictionary, fired_skill_id: int) -> void:
	if v.is_empty() or fired_skill_id != _SHIELD_SKILL:
		return
	_play_fx_spine_scene("res://scenes/worldmap_fx/skill_adbloking_spine.tscn", v)
	if v.has("center"):
		CocosParticle.spawn(self, "pt_shild", v["center"], 99, 0.4)

func _vamp_impact(victim: Dictionary, attacker: Dictionary) -> void:
	if victim.is_empty() or not victim.has("center"):
		return
	CocosParticle.spawn(self, "pt_skill_14_vamp", victim["center"], 131, 0.6)

const _BICON_STEP_ORIG := 270.0
const _BICON_BASE_PX := 85.0
const _BICON_SCALE := 0.42
const _BICON_MAX := 4

func _bicon_add(v: Dictionary, skill_id: int, is_buff := false, turns := 0, stacks := 0) -> void:
	if v.is_empty() or not v.has("center") or skill_id <= 0:
		return
	var icon_path := "res://assets/converted/skill/skill_%d.tres" % skill_id
	if not ResourceLoader.exists(icon_path):
		return
	var sm := _man("skill")
	var num := stacks if stacks > 0 else turns
	var row: Array = v.get("bicons", [])
	for existing in row:
		if is_instance_valid(existing) and int(existing.get_meta("skill_id", 0)) == skill_id:
			if turns == 0:
				row.erase(existing)
				existing.queue_free()
				v["bicons"] = row
				_bicon_positioning(v)
			else:
				_bicon_set_turn(existing as Sprite2D, num)
			return
	if turns == 0:
		return
	if row.size() >= _BICON_MAX:
		var old: Sprite2D = row.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var c: Vector2 = v.get("bicon_origin", v["center"])
	var base := _spr("skill", "skill_buff" if is_buff else "skill_debuff", sm, _BICON_SCALE * 0.5)
	if base == null:
		return
	base.z_index = 96
	base.set_meta("skill_id", skill_id)
	base.set_meta("is_buff", is_buff)
	add_child(base)
	base.position = c
	var ico := Sprite2D.new()
	ico.texture = load(icon_path)
	ico.material = _pma
	ico.scale = Vector2.ONE * 0.9
	base.add_child(ico)
	if num > 0:
		base.add_child(_bicon_number_label(is_buff, num))
	row.append(base)
	v["bicons"] = row
	var t := base.create_tween()
	t.tween_property(base, "scale", Vector2.ONE * _BICON_SCALE * 0.5, 0.4) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(base, "scale", Vector2.ONE * _BICON_SCALE * 1.8, 0.4)
	t.tween_property(base, "scale", Vector2.ONE * _BICON_SCALE * 1.5, 0.4)
	t.tween_property(base, "scale", Vector2.ONE * _BICON_SCALE * 1.7, 0.2)
	t.tween_property(base, "scale", Vector2.ONE * _BICON_SCALE * 0.7, 0.2)
	t.tween_callback(_bicon_positioning.bind(v))
	_bicon_positioning(v)

func _bicon_number_label(is_buff: bool, num: int) -> Label:
	var lb := _bmf_label("heal" if is_buff else "total", 1.5 if is_buff else 1.0)
	lb.name = "TurnCount"
	lb.text = str(num)
	lb.position = Vector2(0, -_BICON_BASE_PX * 0.2)
	return lb

func _bicon_set_turn(base: Sprite2D, num: int) -> void:
	if num <= 0:
		return
	var lb := base.get_node_or_null("TurnCount") as Label
	if lb != null:
		lb.text = str(num)
	else:
		base.add_child(_bicon_number_label(bool(base.get_meta("is_buff", false)), num))

func _bicon_tick(v: Dictionary, skill_id: int, turns: int) -> void:
	if v.is_empty() or skill_id <= 0:
		return
	var row: Array = v.get("bicons", [])
	for existing in row.duplicate():
		if not is_instance_valid(existing) or int(existing.get_meta("skill_id", 0)) != skill_id:
			continue
		if turns > 0:
			_bicon_set_turn(existing as Sprite2D, turns)
		else:
			row.erase(existing)
			existing.queue_free()
	v["bicons"] = row
	_bicon_positioning(v)

func _bicon_clear(v: Dictionary) -> void:
	for s in (v.get("bicons", []) as Array):
		if is_instance_valid(s):
			s.queue_free()
	v["bicons"] = []

func _bicon_positioning(v: Dictionary) -> void:
	var row: Array = v.get("bicons", [])
	var live: Array = []
	for s in row:
		if is_instance_valid(s):
			live.append(s)
	v["bicons"] = live
	if live.is_empty() or not v.has("center"):
		return
	var c: Vector2 = v.get("bicon_origin", v["center"])
	var step := _BICON_BASE_PX * _BICON_SCALE * (_BICON_STEP_ORIG / 256.0)
	var x0 := c.x
	for i in live.size():
		var s: Sprite2D = live[i]
		var tw := s.create_tween()
		tw.tween_property(s, "position", Vector2(x0 + step * i, c.y), 0.2)
		tw.parallel().tween_property(s, "scale", Vector2.ONE * _BICON_SCALE, 0.2)

func _skill_banner(name: String) -> void:
	if name == "":
		return
	var vis := _vis()
	var holder := Control.new()
	holder.z_index = 110
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var l := Label.new()
	l.text = name
	l.add_theme_font_size_override("font_size", 23)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(l)
	l.reset_size()
	var box := NinePatchRect.new()
	box.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres")
	box.patch_margin_left = 10; box.patch_margin_right = 10
	box.patch_margin_top = 4; box.patch_margin_bottom = 4
	box.size = l.size + Vector2(20, 20)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(box)
	holder.move_child(box, 0)
	box.position = Vector2(vis.x * 0.5 - box.size.x * 0.5, vis.y * 0.22)
	l.position = box.position + Vector2(10, 10)
	var t := holder.create_tween()
	t.tween_interval(0.7)
	t.tween_property(holder, "modulate:a", 0.0, 0.2).from(1.0)
	t.tween_callback(holder.queue_free)

func _is_boss() -> bool:
	if _params.has("boss"): return bool(_params["boss"])
	if bool(_enemy.get("boss", false)): return true
	if not _params.has("stage"): return false
	var st: Dictionary = _stage_rec()
	var total := int((st.get("enemies", []) as Array).size())
	var enc := int(_params.get("enc", 0))
	return total > 0 and enc + 1 >= total

func _battle_opening() -> void:
	pass

const _BOSS_GLYPH_DELAY: Array[float] = [0.6, 0.9, 1.2, 1.5]
const _BOSS_GLYPH_DX: Array[float] = [-260.0, -110.0, 110.0, 260.0]
func _boss_show_effect() -> void:
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var cx := vis.x * 0.5
	var y := Design.flip_y(vis.y * 0.75, vis.y)
	var layer := Node2D.new()
	layer.z_index = 130
	add_child(layer)
	Bgm.sfx("effect_cut_in")
	var starts := [
		Vector2(-300.0 - vis.x, y),
		Vector2(vis.x * 0.35, y - 300.0),
		Vector2(vis.x * 0.7, y - 300.0),
		Vector2(vis.x + 300.0, y),
	]
	for i in 4:
		var g := _spr("adventure_ui", "scene_adventure_txt_boss%d_kr" % (i + 1), _adv, 2.0 * S)
		if g == null:
			continue
		g.position = starts[i]
		layer.add_child(g)
		var t := g.create_tween()
		t.tween_interval(_BOSS_GLYPH_DELAY[i])
		t.tween_property(g, "scale", Vector2.ONE * S, 0.75)
		t.parallel().tween_property(g, "position", Vector2(cx + _BOSS_GLYPH_DX[i], y), 0.8) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	var tl := layer.create_tween()
	tl.tween_interval(2.3 + 0.4)
	tl.tween_callback(layer.queue_free)

func _super_attack_fx(caster: Dictionary) -> void:
	var vis := _vis()
	_screen_shake(14.0)
	Bgm.sfx("effect_bigbang")
	var flash := ColorRect.new(); flash.color = Color(1, 0.92, 0.6, 0.0); flash.z_index = 118
	flash.set_anchors_preset(Control.PRESET_FULL_RECT); flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	var tf := flash.create_tween()
	tf.tween_property(flash, "color:a", 0.6, 0.1)
	tf.tween_property(flash, "color:a", 0.0, 0.4)
	tf.tween_callback(flash.queue_free)
	var banner := Label.new(); banner.text = "각성기!"
	banner.add_theme_font_size_override("font_size", 48)
	banner.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	banner.add_theme_color_override("font_outline_color", Color(0.4, 0.15, 0, 0.9))
	banner.add_theme_constant_override("outline_size", 7)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.size = Vector2(vis.x, 60); banner.position = Vector2(0, vis.y * 0.2)
	banner.z_index = 119; banner.pivot_offset = Vector2(vis.x * 0.5, 30); banner.scale = Vector2(0.4, 0.4)
	add_child(banner)
	var bt := banner.create_tween()
	bt.tween_property(banner, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
	bt.tween_interval(0.5)
	bt.tween_property(banner, "modulate:a", 0.0, 0.3)
	bt.tween_callback(banner.queue_free)
	if not caster.is_empty() and caster.has("center"):
		var c: Vector2 = caster["center"]
		var burst := CPUParticles2D.new()
		burst.position = c; burst.z_index = 117; burst.emitting = true; burst.one_shot = true
		burst.amount = 28; burst.lifetime = 0.6; burst.explosiveness = 0.95
		burst.direction = Vector2(0, -1); burst.spread = 180.0
		burst.initial_velocity_min = 120.0; burst.initial_velocity_max = 280.0
		burst.gravity = Vector2(0, 60.0); burst.scale_amount_min = 3.0; burst.scale_amount_max = 7.0
		burst.color = Color(1, 0.9, 0.45)
		add_child(burst)
		get_tree().create_timer(0.9).timeout.connect(func(): if is_instance_valid(burst): burst.queue_free())
		var node = caster.get("node", null)
		if node is CanvasItem:
			var ci := node as CanvasItem
			var t := create_tween()
			t.tween_property(ci, "modulate", Color(1.6, 1.4, 0.8), 0.12)
			t.tween_property(ci, "modulate", Color.WHITE, 0.3)

func _reward_fx(gold: int, _exp: int) -> void:
	Bgm.sfx("effect_coin")
	var vis := _vis()
	var origin := Vector2(vis.x * 0.5, vis.y * 0.46)
	var cman := _man("common_ui")
	var n := clampi(6 + gold / 40, 6, 14)
	for i in n:
		var cname: String = ["common_coin_small1", "common_coin_small2", "common_coin"][i % 3]
		var coin := _spr("common_ui", cname, cman, 0.7)
		if coin == null: continue
		coin.position = origin; coin.z_index = 120
		add_child(coin)
		var ang := randf_range(-PI * 0.82, -PI * 0.18)
		var peak := origin + Vector2(cos(ang), sin(ang)) * randf_range(70.0, 175.0)
		var t := coin.create_tween()
		t.tween_property(coin, "position", peak, 0.33).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(coin, "position", peak + Vector2(randf_range(-24, 24), 130.0), 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(coin, "modulate:a", 0.0, 0.42)
		t.tween_callback(coin.queue_free)

func _grant_exp(uid: int, amount: int) -> Dictionary:
	return UserDB.grant_exp(uid, amount)

const _STAT_KR := {"hp": "생명력", "att": "공격력", "def": "방어력"}
func _levelup_fx(events: Array) -> void:
	var vis := _vis()
	var iman := _man("item_etc")
	for i in events.size():
		var nm := String(events[i]["name"])
		var ev: Dictionary = events[i]["ev"]
		var gains: Array = ev.get("gains", [])
		if gains.is_empty():
			continue
		var max_stats: Dictionary = ev.get("max_stats", {})
		var agg := {}
		for k in ["hp", "att", "def"]:
			agg[k] = {"gain": 0, "maxn": 0, "trans": false}
		var triples := 0
		for g in gains:
			if bool(g.get("triple", false)):
				triples += 1
			var ismax: Dictionary = g.get("is_max", {})
			var tm: Dictionary = g.get("tmax", {})
			for k in ["hp", "att", "def"]:
				agg[k]["gain"] = int(agg[k]["gain"]) + int(g.get(k, 0))
				if bool(ismax.get(k, false)):
					agg[k]["maxn"] = int(agg[k]["maxn"]) + 1
				if bool(tm.get(k, false)):
					agg[k]["trans"] = true
		var final_lv := int(ev.get("level", 0))
		var from_lv := final_lv - int(ev.get("levels_gained", gains.size()))
		_levelup_panel(iman, nm, from_lv, final_lv, agg, max_stats, gains.size(), triples,
			vis, i, 0.3 + i * 0.6, ev.get("learned_skills", []))

func _levelup_panel(iman: Dictionary, nm: String, from_lv: int, to_lv: int,
		agg: Dictionary, max_stats: Dictionary, levels: int, triples: int,
		vis: Vector2, idx: int, delay: float, learned: Array = []) -> void:
	var w := 424.0
	var row_h := 26.0
	var head_h := 32.0
	var h := head_h + row_h * (3.0 + (1.0 if not learned.is_empty() else 0.0)) + 12.0
	var any_trans := bool(agg["hp"]["trans"]) or bool(agg["att"]["trans"]) or bool(agg["def"]["trans"])
	var accent := Color(1.0, 0.82, 0.32)
	if triples > 0:
		accent = Color(1.0, 0.9, 0.42)
	elif any_trans:
		accent = Color(0.78, 0.58, 1.0)
	var cx_w := vis.x
	var y := vis.y * 0.06 + idx * (h + 8.0)
	var root := Control.new()
	root.z_index = 132
	root.position = Vector2(0, y)
	root.modulate.a = 0.0
	root.pivot_offset = Vector2(cx_w * 0.5, h * 0.5)
	root.scale = Vector2(0.62, 0.62)
	add_child(root)
	var panel := NinePatchRect.new()
	panel.texture = load("res://assets/converted/ninepatch_ui/9patch_train_box4.tres")
	panel.patch_margin_left = 22; panel.patch_margin_right = 22
	panel.patch_margin_top = 16; panel.patch_margin_bottom = 16
	panel.size = Vector2(w, h)
	panel.position = Vector2((cx_w - w) * 0.5, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if triples > 0 or any_trans:
		panel.modulate = accent.lerp(Color.WHITE, 0.55)
	root.add_child(panel)
	var icon := _spr("item_etc", "item_etc_level_up", iman, 0.6)
	if icon:
		icon.position = Vector2(28, head_h * 0.5 + 2)
		panel.add_child(icon)
	var hd := Label.new()
	hd.text = "%s      Lv.%d ▶ %d" % [nm, from_lv, to_lv]
	hd.add_theme_font_size_override("font_size", 19)
	hd.add_theme_color_override("font_color", Color(1, 0.92, 0.55))
	hd.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0, 0.9))
	hd.add_theme_constant_override("outline_size", 3)
	hd.position = Vector2(58, 5)
	panel.add_child(hd)
	var ry := head_h + 2.0
	for k in ["hp", "att", "def"]:
		var a: Dictionary = agg[k]
		var gain := int(a["gain"])
		var maxn := int(a["maxn"])
		var trans := bool(a["trans"])
		var lab := Label.new()
		lab.text = String(_STAT_KR[k])
		lab.add_theme_font_size_override("font_size", 16)
		lab.add_theme_color_override("font_color", Color(0.86, 0.6, 0.28))
		lab.position = Vector2(26, ry)
		panel.add_child(lab)
		var val := Label.new()
		if levels == 1 and max_stats.has(k):
			var denom := int(max_stats[k]) + (int({"hp": 4, "att": 1, "def": 1}[k]) if trans else 0)
			val.text = "+%d / %d" % [gain, denom]
		else:
			val.text = "+%d" % gain
		val.add_theme_font_size_override("font_size", 16)
		val.add_theme_color_override("font_color", accent if trans else Color(0.7, 1.0, 0.76))
		val.position = Vector2(150, ry)
		panel.add_child(val)
		if maxn > 0:
			var badge := Label.new()
			var btxt := "MAX+" if trans else "MAX"
			if levels > 1:
				btxt += "×%d" % maxn
			badge.text = btxt
			badge.add_theme_font_size_override("font_size", 15)
			badge.add_theme_color_override("font_color", Color(0.85, 0.6, 1.0) if trans else Color(1.0, 0.85, 0.3))
			badge.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0, 0.9))
			badge.add_theme_constant_override("outline_size", 3)
			badge.position = Vector2(300, ry)
			panel.add_child(badge)
		ry += row_h
	if not learned.is_empty():
		var sl := Label.new()
		sl.text = "새 스킬  %s" % ", ".join(learned)
		sl.add_theme_font_size_override("font_size", 16)
		sl.add_theme_color_override("font_color", Color(0.72, 0.92, 1.0))
		sl.add_theme_color_override("font_outline_color", Color(0.1, 0.14, 0.25, 0.9))
		sl.add_theme_constant_override("outline_size", 3)
		sl.position = Vector2(26, ry)
		panel.add_child(sl)
	var tw := root.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		if triples > 0:
			Bgm.sfx("effect_max_fun")
			_levelup_particle("pt_3max1", cx_w * 0.5, y + h * 0.5)
			_levelup_particle("pt_3max2", cx_w * 0.5, y + h * 0.5)
		else:
			Bgm.sfx("effect_level_updown" if _has_sfx("effect_level_updown") else "effect_coin")
			_levelup_particle("pt_levelup_light", cx_w * 0.5, y + h - 6.0))
	tw.tween_property(root, "modulate:a", 1.0, 0.22)
	tw.parallel().tween_property(root, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.7 if triples > 0 else 1.35)
	tw.tween_property(root, "position:y", y - 34.0, 0.45)
	tw.parallel().tween_property(root, "modulate:a", 0.0, 0.45)
	tw.tween_callback(root.queue_free)

func _has_sfx(name: String) -> bool:
	return ResourceLoader.exists("res://assets/music/%s.mp3" % name)

func _levelup_particle(name: String, x: float, y: float) -> void:
	CocosParticle.spawn(self, name, Vector2(x, y), 131,
		0.9 if name.begins_with("pt_3max") else 0.5)

func _attach_retry_cure_buttons() -> void:
	for i in _party.size():
		var v: Dictionary = _views.get("A%d" % i, {})
		var card = v.get("node")
		if card == null or not is_instance_valid(card):
			continue
		for c in card.get_children():
			if c is Control and c.has_meta("cure_button"):
				c.queue_free()
		var lv := int(_party[i].get("level", 1))
		var key := ""
		for t in (Data.item_effects.get("heal_potion", {}).get("tiers", []) as Array):
			var k := String((t as Dictionary).get("key", ""))
			if ItemEffect.heal_usable(Data.item_effects, k, lv):
				key = k
				break
		if key == "" or UserDB.item_count(key) <= 0:
			continue
		var dead := int(v.get("hp", 1)) <= 0
		PartyCardView.build_cure_button(card, key, UserDB.item_count(key), dead, _pma,
			_retry_use_potion.bind(i, key))

func _retry_use_potion(idx: int, key: String) -> void:
	var v: Dictionary = _views.get("A%d" % idx, {})
	if v.is_empty() or int(v.get("hp", 0)) <= 0:
		return
	var hp := int(v.get("hp", 0))
	var hp_max := int(v.get("hp_max", 1))
	var healed := ItemEffect.heal_amount(Data.item_effects, hp, hp_max)
	if healed <= 0 or not UserDB.use_item(key, 1):
		return
	v["hp"] = clampi(hp + healed, 0, hp_max)
	_views["A%d" % idx] = v
	_refresh_bar(v)
	if v.has("center"):
		CocosParticle.spawn(self, "skill_29", v["center"], 132, 0.9)
	Bgm.sfx("effect_skill_29")
	_attach_retry_cure_buttons()

func _party_hp_state() -> Dictionary:
	var out := {}
	for i in _party.size():
		var v: Dictionary = _views.get("A%d" % i, {})
		var uid := int(_party[i]["uid"])
		out[str(uid)] = int(v.get("hp", _party[i].get("hp", 0)))
	return out

func _finish() -> void:
	_finished = true
	for uid in _drink_users:
		var db: Dictionary = UserDB.get_dragon(int(uid)).get("drink_buffs", {})
		for _r in maxi(1, _cur_round):
			db = ItemEffect.tick(db)
		UserDB.set_dragon_field(int(uid), "drink_buffs", db)
	var fmax := ItemEffect.food_max(Data.item_effects)
	for pv in _party:
		var uid := int(pv["uid"])
		var fd := maxi(0, int(UserDB.get_dragon(uid).get("food", fmax)) - FOOD_PER_BATTLE)
		UserDB.set_dragon_field(uid, "food", fd)
	var vis := _vis()
	var win := _winner == "ally"
	if not win and _winner == "enemy" and not _params.has("story_return"):
		_apply_defeat_incapacitation()
	if win: Bgm.sfx("bg_ad_win_short")
	if not win:
		_log(Data.ui("#b66704b6") if _winner == "enemy" else "무승부")
	var st: Dictionary = _stage_rec()
	var total := int((st.get("enemies", []) as Array).size())
	var enc := int(_params.get("enc", 0))
	var region := String(_params.get("region", "yutakan"))
	var night_run := bool(_params.get("night", false))
	var more := win and total > 0 and enc + 1 < total \
		and not bool(st.get("random_boss", false)) and not night_run
	var dk_cfg: Dictionary = (st.get("summon", {}) as Dictionary) if Darknix.is_summon_stage(st) else {}
	var dk_live := not dk_cfg.is_empty() \
		and Darknix.is_active(UserDB.darknix(), int(Time.get_unix_time_from_system()))
	var dk_pending := false
	var dk_kill := win and dk_live
	var reward_txt := ""
	var phases: Array = []
	if win:
		UserDB.bump_quest("battles")
		var rlv := maxi(1, int(_enemy.get("level", 1)))
		var boss := (not more) and total > 0 and _is_boss()
		var elite := bool(_params.get("elite", false))
		var exp_r := BattleReward.amount(BattleReward.EXP, rlv, boss, elite, Data.drops, st)
		var gold_r := BattleReward.amount(BattleReward.GOLD, rlv, boss, elite, Data.drops, st)
		var gold_base := gold_r
		gold_r = int(round(float(gold_r) * AwakenSkill.mult_of(_awaken_explore(), "gold_pct")))
		gold_r = int(round(float(gold_r) * _equip_reward_mult("gold")))
		var _now := int(Time.get_unix_time_from_system())
		var _rb: Dictionary = UserDB.reward_buff()
		var gold_mult := ItemEffect.reward_buff_mult(_rb, "gold", _now)
		if gold_mult > 1.0:
			gold_r = int(round(float(gold_r) * gold_mult))
		phases.append({"kind": "gold", "total": gold_r, "base": gold_base,
			"bonus": gold_r - gold_base})
		var names: Array = []
		for p in _party: names.append(String(p.get("name", "")))
		var mbonus := BattleMission.exp_bonus(BattleMission.evaluate(_missions, _events, names))
		if mbonus > 0.0:
			exp_r = int(exp_r * (1.0 + mbonus))
		var exp_mult := ItemEffect.reward_buff_mult(_rb, "exp", _now)
		if exp_mult > 1.0:
			exp_r = int(round(float(exp_r) * exp_mult))
		_exp_gained += exp_r
		if is_instance_valid(_exp_label): _exp_label.text = str(_exp_gained)
		UserDB.add_currency("gold", gold_r)
		var levelups: Array = []
		for pv in _party:
			var exp_i := _exp_for(pv, exp_r)
			_small_exp_layer(int(pv["uid"]), exp_i, int(_party.find(pv)))
			var lev := _grant_exp(int(pv["uid"]), exp_i)
			if int(lev.get("levels_gained", 0)) > 0:
				levelups.append({"name": String(pv["name"]), "ev": lev})
				var lv_to := int(lev.get("level", 1))
				_levelup_queue.append({
					"uid": int(pv["uid"]), "name": String(pv["name"]),
					"from_lv": lv_to - int(lev.get("levels_gained", 1)), "to_lv": lv_to,
					"gains": lev.get("gains", []), "max_stats": lev.get("max_stats", {})})
				_log("%s이(가) 경험치를 %d 얻고 레벨업 했습니다." % [String(pv["name"]), exp_r])
			else:
				_log("%s이(가) 경험치를 %d 얻었습니다." % [String(pv["name"]), exp_r])
		_reward_fx(gold_r, exp_r)
		reward_txt = "  +EXP %d / +골드 %d" % [exp_r, gold_r]
		var fsrc := Drops.SOURCE_BOSS if boss else Drops.SOURCE_NORMAL
		var frng := RandomNumberGenerator.new(); frng.randomize()
		var hero_mode := bool(_params.get("hero", false))
		var dmode := Drops.mode_of(hero_mode, bool(_params.get("night", false)), _is_kades())
		for sd in (Drops.roll_special(st, frng, dmode, boss) if not dk_live else []):
			var skey := String((sd as Dictionary)["key"])
			var sqty := int((sd as Dictionary)["count"])
			UserDB.add_item(skey, sqty)
			reward_txt += " / %s x%d" % [_drop_display_name(skey), sqty]
			phases.append({"key": skey, "count": sqty})
		if frng.randf() < float((Data.drops.get("food", {}).get("chance", {}) as Dictionary).get(fsrc, 0.0)):
			var fkey := Drops.roll_food(Data.items, st.get("element", ""), frng)
			if fkey != "":
				var fc: Dictionary = Data.drops.get("food", {}).get("count", {})
				var fqty := frng.randi_range(int(fc.get("min", 1)), maxi(int(fc.get("min", 1)), int(fc.get("max", 1))))
				UserDB.add_item(fkey, fqty)
				reward_txt += " / %s x%d" % [Data.item_name(fkey), fqty]
				phases.append({"key": fkey, "count": fqty})
		for md in (Drops.roll_monster(Data.monster_drops, int(_enemy.get("id", 0)), frng) if not dk_live else []):
			var mrow: Dictionary = md
			var mqty := int(mrow["count"])
			if String(mrow.get("kind", "item")) == "currency":
				UserDB.add_currency(String(mrow["currency"]), mqty)
				reward_txt += " / 다이아 x%d" % mqty
				phases.append({"kind": "dia", "count": mqty})
				continue
			var mkey := String(mrow["key"])
			UserDB.add_item(mkey, mqty)
			reward_txt += " / %s x%d" % [_drop_display_name(mkey), mqty]
			phases.append({"key": mkey, "count": mqty})
		if dk_kill:
			reward_txt += _darknix_kill(st, phases)
		var ess := Drops.roll_essence(Data.drops, Data.items, st.get("element", ""), fsrc, frng)
		if not ess.is_empty():
			UserDB.add_item(String(ess["key"]), int(ess["count"]))
			reward_txt += " / %s x%d" % [Data.item_name(String(ess["key"])), int(ess["count"])]
			phases.append({"key": String(ess["key"]), "count": int(ess["count"])})
		var rare := Drops.roll_rare_element(Data.drops, dmode, boss, frng)
		if not rare.is_empty():
			UserDB.add_item(String(rare["key"]), int(rare["count"]))
			reward_txt += " / %s x%d" % [Data.item_name(String(rare["key"])), int(rare["count"])]
			phases.append({"key": String(rare["key"]), "count": int(rare["count"])})
		var drk := Drops.roll_drink(Data.drops, Data.items, frng)
		if not drk.is_empty():
			UserDB.add_item(String(drk["key"]), int(drk["count"]))
			reward_txt += " / %s x%d" % [Data.item_name(String(drk["key"])), int(drk["count"])]
			phases.append({"key": String(drk["key"]), "count": int(drk["count"])})
		var ekey := Drops.roll_egg(Data.drops, st, fsrc, frng, bool(_params.get("hero", false)))
		if ekey != "":
			UserDB.add_item(ekey, 1)
			reward_txt += " / %s x1" % String(EggGacha.item_def(ekey, Data.dragons).get("name", "알"))
			phases.append({"key": ekey, "count": 1})
		var grng := RandomNumberGenerator.new(); grng.randomize()
		var gkey := Drops.roll_exploration(Data.drops, rlv,
			Drops.SOURCE_BOSS if boss else Drops.SOURCE_NORMAL, Data.equipment, grng,
			_is_kades(), _base_field(),
			AwakenSkill.mult_of(_awaken_explore(), "artifact_chance_pct"))
		if gkey != "":
			UserDB.add_item(gkey, 1)
			reward_txt += " / %s x1" % Drops.display_name(gkey, Data.gems, Data.equipment)
			phases.append({"key": gkey, "count": 1})
	if win and not more:
		var sid := str(_params.get("stage", ""))
		if sid != "":
			UserDB.set_progress("cleared_" + sid, true)
		_note_story_quest(st)
	var after_rewards := func() -> void:
		if more:
			_log(Data.ui("#754f76f2"))
			var lvq := _levelup_queue.duplicate()
			_levelup_queue.clear()
			_attach_retry_cure_buttons()
			_retry_buttons(
				func(): Scenes.goto("worldmap", {"region": region}),
				func(): Scenes.goto("adventure",
					{"stage": _params.get("stage", ""), "region": region, "enc": enc + 1,
					"hp_state": _party_hp_state(),
					"hero": bool(_params.get("hero", false)), "night": bool(_params.get("night", false)),
					"run_seed": int(_params.get("run_seed", 0)),
					"party_uids": _params.get("party_uids", []).duplicate(), "party_ready": true,
					"levelups": lvq}))
		else:
			if win:
				_log(Data.ui("#0262e102"))
			var q := _levelup_queue.duplicate()
			_levelup_queue.clear()
			if not q.is_empty():
				LevelUpScreen.open_queue(self, q, Callable(),
					{"auto_close": AdvAuto.LVUP_CLOSE_SECS} if AdvAuto.enabled() else {})
			if win:
				_show_finish_arrow(region)
			else:
				_big_button("월드맵으로", "9patch_btn2", Vector2(vis.x * 0.5 + 20.0, vis.y * 0.38),
					func(): Scenes.goto("worldmap", {"region": region}))
			AdvAuto.arm(self,
				AdvAuto.FINISH_SECS + AdvAuto.LVUP_CLOSE_SECS * float(q.size()),
				func(): Scenes.goto("worldmap", {"region": region}))
	if _params.has("story_return"):
		var sr: Dictionary = _params["story_return"]
		_big_button("이야기 계속", "9patch_btn2", Vector2(vis.x * 0.5 - 140.0, vis.y * 0.38),
			func() -> void:
				Scenes.goto("story", {"no": int(sr.get("no", 1)), "part": int(sr.get("part", 0)),
					"resume_flow": int(sr.get("resume_flow", 0)),
					"back": sr.get("back", "worldmap"),
					"back_params": sr.get("back_params", {})}))
		return
	if win and not phases.is_empty():
		_play_reward_phases(phases, after_rewards)
	else:
		after_rewards.call()
	var btn_y := vis.y * 0.38
	if not win and _winner == "enemy":
		const RETRY_COST := 100
		_big_button("재도전 (%dG)" % RETRY_COST, "9patch_btn3",
			Vector2(vis.x * 0.5 - 300.0, btn_y), func():
				if not UserDB.spend("gold", RETRY_COST): return
				_undo_defeat_incapacitation()
				Scenes.goto("adventure", {"stage": _params.get("stage", ""), "region": region, "enc": enc,
					"hero": bool(_params.get("hero", false)),
					"night": bool(_params.get("night", false)),
					"run_seed": int(_params.get("run_seed", 0)),
					"party_uids": _params.get("party_uids", []).duplicate(), "party_ready": true}))

func _apply_defeat_incapacitation() -> void:
	var cfg: Dictionary = Data.incapacitation
	if cfg.is_empty():
		return
	var now := int(Time.get_unix_time_from_system())
	var until := Incapacitation.down_until(cfg, now)
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var avoid_stat := String(cfg.get("avoid_stat", "cure"))
	_downed_uids.clear()
	for pv in _party:
		var uid := int(pv["uid"])
		var cure := int((pv.get("stats", {}) as Dictionary).get(avoid_stat, 0))
		if Incapacitation.avoids(cure, rng):
			continue
		UserDB.set_cure_time(uid, until)
		_downed_uids.append(uid)

var _downed_uids: Array = []

func _undo_defeat_incapacitation() -> void:
	for uid in _downed_uids:
		UserDB.set_cure_time(int(uid), 0)
	_downed_uids.clear()

const _RETRY_BTN := Vector2(262.0, 94.0)

func _retry_buttons(on_stop: Callable, on_continue: Callable) -> void:
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var w := _RETRY_BTN.x * S
	var y := vis.y * 0.5 - 20.0
	var man := _man("adventure_ui")
	_retry_button("scene_adventure_btn1", "scene_adventure_choice_stop_KR", man,
		Vector2(vis.x * 0.5 - (w * 0.5 + 50.0), y), Vector2(-50.0 - w, y), on_stop)
	var to := Vector2(vis.x * 0.5 + (w * 0.5 + 50.0), y)
	var from := Vector2(vis.x + 50.0 + w, y)
	if AdvAuto.enabled():
		var b := CounterButton.make("scene_adventure_choice_continue_KR", true)
		b.position = from
		b.z_index = 124
		b.name = "AutoRetryButton"
		b.fired.connect(on_continue)
		b.cancelled.connect(AdvAuto.off)
		add_child(b)
		var tw := b.create_tween()
		tw.tween_property(b, "position", to, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
		return
	_retry_button("scene_adventure_btn2", "scene_adventure_choice_continue_KR", man,
		to, from, on_continue)

func _retry_button(bg_key: String, label_key: String, man: Dictionary,
		to: Vector2, from: Vector2, cb: Callable) -> void:
	var S := Design.ASSET_SCALE
	var holder := Node2D.new()
	holder.position = from
	holder.z_index = 124
	add_child(holder)
	var bg := _spr("adventure_ui", bg_key, man, S)
	if bg:
		holder.add_child(bg)
	var lb := _spr("adventure_ui", label_key, man, S)
	if lb:
		holder.add_child(lb)
	var hit := Button.new()
	hit.flat = true
	hit.size = _RETRY_BTN * S
	hit.position = -_RETRY_BTN * S * 0.5
	hit.pressed.connect(cb)
	holder.add_child(hit)
	var tw := holder.create_tween()
	tw.tween_property(holder, "position", to, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)

var _phase_dim: ColorRect
var _phase_box: Node2D
var _phase_run := 0
func _play_reward_phases(phases: Array, done: Callable) -> void:
	_phase_run += 1
	if is_instance_valid(_phase_dim):
		_phase_dim.queue_free()
	if is_instance_valid(_phase_box):
		_phase_box.queue_free()
	var vis := _vis()
	_phase_dim = ColorRect.new()
	_phase_dim.color = Color(0, 0, 0, 0)
	_phase_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_phase_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_phase_dim.z_index = 120
	add_child(_phase_dim)
	_phase_dim.create_tween().tween_property(_phase_dim, "color:a", 200.0 / 255.0, 0.5)
	Bgm.sfx("effect_holy_wing")
	_run_reward_phase(phases, 0, done, _phase_run)

func _run_reward_phase(phases: Array, i: int, done: Callable, run_id: int) -> void:
	if run_id != _phase_run:
		return
	if i >= phases.size():
		if is_instance_valid(_phase_dim):
			var d := _phase_dim
			_phase_dim = null
			var t := d.create_tween()
			t.tween_property(d, "color:a", 0.0, 0.3)
			t.tween_callback(d.queue_free)
		done.call()
		return
	var ph: Dictionary = phases[i]
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var box := Node2D.new()
	box.z_index = 122
	add_child(box)
	_phase_box = box
	CocosParticle.spawn(box, "pt_monster_income_1", Vector2(vis.x * 0.5, 40.0), 123, 1.4)
	var kind := String(ph.get("kind", "item"))
	match kind:
		"gold":
			WordArt.burst(box, "골드 획득!", vis, 125, 60.0)
			var man := _man("common_ui")
			var coin := _spr("common_ui", "common_coin_big", man, 1.5 * S)
			if coin:
				coin.position = Vector2(vis.x * 0.5 - 110.0 + 80.0, vis.y * 0.5)
				coin.modulate.a = 0.0
				box.add_child(coin)
				var ct := coin.create_tween()
				ct.tween_interval(0.5)
				ct.tween_property(coin, "modulate:a", 1.0, 0.15)
				ct.parallel().tween_property(coin, "position:x", vis.x * 0.5 - 110.0, 0.5) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
			var cnt := _bmfont_label("", "font_common", 30)
			cnt.position = Vector2(vis.x * 0.5 + 20.0, vis.y * 0.5 - 20.0)
			cnt.size = Vector2(260, 40)
			cnt.scale = Vector2(1.2, 1.2)
			cnt.modulate.a = 0.0
			box.add_child(cnt)
			var total := int(ph.get("total", 0))
			var nt := cnt.create_tween()
			nt.tween_interval(0.5)
			nt.tween_property(cnt, "modulate:a", 1.0, 0.15)
			nt.tween_method(func(v: float): cnt.text = "X %d" % int(round(v)),
				0.0, float(total), 0.8)
			var bonus := int(ph.get("bonus", 0))
			_log(("%d(+%d) 골드를 얻었습니다." % [int(ph.get("base", total)), bonus]) if bonus > 0
				else "%d 골드를 얻었습니다." % total)
		"dia":
			WordArt.burst(box, Data.ui("#d9df3040"), vis, 125, 60.0)
			var man := _man("common_ui")
			var dia := _spr("common_ui", "common_diamond_small1", man, 1.5 * S)
			if dia:
				dia.position = Vector2(vis.x * 0.5 - 110.0, vis.y * 0.5)
				box.add_child(dia)
			var cnt := _bmfont_label("X %d" % int(ph.get("count", 0)), "font_common", 30)
			cnt.position = Vector2(vis.x * 0.5 + 20.0, vis.y * 0.5 - 20.0)
			cnt.size = Vector2(260, 40)
			cnt.scale = Vector2(1.2, 1.2)
			box.add_child(cnt)
			_log("다이아를 %d개 얻었습니다." % int(ph.get("count", 0)))
		_:
			var key := String(ph.get("key", ""))
			var count := int(ph.get("count", 1))
			WordArt.burst(box, _reward_title_for(key), vis, 125, 100.0)
			var icon_end := Vector2(vis.x * 0.38, vis.y * 0.47)
			var bl := _spr("common_ui", "common_backlight3", _man("common_ui"), 1.3 * S)
			if bl:
				bl.position = icon_end
				bl.modulate = Color(1, 0.95, 0.65, 0.0)
				box.add_child(bl)
				var brot := bl.create_tween().set_loops()
				brot.tween_property(bl, "rotation_degrees", 360.0, 54.0).from(0.0)
				var bt := bl.create_tween()
				bt.tween_interval(0.8)
				bt.tween_property(bl, "modulate:a", 0.9, 0.2)
				bt.parallel().tween_property(bl, "scale", Vector2(1.1 * S, 1.1 * S), 0.2) \
					.from(Vector2(1.3 * S, 1.3 * S))
			var tex := _reward_icon_texture(key)
			if tex:
				var icon := Sprite2D.new()
				icon.texture = tex
				icon.material = _pma
				icon.position = Vector2(vis.x * 0.5, vis.y * 0.47)
				icon.modulate.a = 0.0
				icon.scale = Vector2.ZERO
				box.add_child(icon)
				var it := icon.create_tween()
				it.tween_interval(0.8)
				it.tween_property(icon, "modulate:a", 1.0, 0.2)
				it.parallel().tween_property(icon, "scale", Vector2(1.6 * S, 1.6 * S), 0.2)
				it.parallel().tween_property(icon, "rotation_degrees", 720.0, 0.2).from(0.0)
				it.tween_property(icon, "scale", Vector2(1.4 * S, 1.4 * S), 0.2)
				it.tween_property(icon, "position", icon_end, 0.2) \
					.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
			var nm := _drop_display_name(key)
			var blk := Control.new()
			blk.position = Vector2(vis.x * 0.55, vis.y * 0.3)
			blk.modulate.a = 0.0
			box.add_child(blk)
			var name_l := _bmfont_rich("%s  -  [color=#4374d9]%d개[/color]" % [nm, count], 24)
			name_l.position = Vector2(0, 0); name_l.size = Vector2(vis.x * 0.42, 36)
			blk.add_child(name_l)
			var desc := String(Data.get_item(key).get("desc", ""))
			var dy := 48.0
			if desc != "":
				var desc_l := _bmfont_rich(desc, 20)
				desc_l.position = Vector2(0, dy); desc_l.size = Vector2(vis.x * 0.36, 130)
				blk.add_child(desc_l)
				dy += minf(130.0, 30.0 * ceilf(desc.length() / 18.0)) + 12.0
			var owned := UserDB.item_count(key)
			if owned > 0:
				var own_l := _bmfont_rich("[color=#bdbdbd](보유 수량 : %d개)[/color]" % owned, 18)
				own_l.position = Vector2(0, dy); own_l.size = Vector2(vis.x * 0.36, 30)
				blk.add_child(own_l)
			var kt := blk.create_tween()
			kt.tween_interval(1.2)
			kt.tween_property(blk, "modulate:a", 1.0, 0.25)
			_log("%s%s 획득하였습니다." % [nm, "을" if _has_batchim(nm) else "를"])
	var adv_done := [false]
	var advance := func() -> void:
		if adv_done[0] or not is_instance_valid(box):
			return
		adv_done[0] = true
		var ft := box.create_tween()
		ft.tween_property(box, "modulate:a", 0.0, 0.15)
		ft.tween_callback(box.queue_free)
		ft.tween_callback(func(): _run_reward_phase(phases, i + 1, done, run_id))
	var tap := Button.new()
	tap.flat = true
	tap.position = Vector2.ZERO
	tap.size = vis
	tap.pressed.connect(advance)
	box.add_child(tap)
	get_tree().create_timer(3.4 / maxf(_speed, 1.0)).timeout.connect(advance)

func _reward_title_for(key: String) -> String:
	if Gem.parse_item_key(key).size() > 0 or Equipment.parse_item_key(key) != "":
		return Data.ui("#19d14093")
	if key.begins_with(EggGacha.KEY_PREFIX):
		return Data.ui("#31520ed3")
	if not Loadout.parse_item_key(key).is_empty():
		return Data.ui("#e28bf315")
	return Data.ui("#39f82deb")

func _reward_icon_texture(key: String) -> Texture2D:
	var g := Gem.parse_item_key(key)
	if not g.is_empty():
		return Icons.gem_texture(
			String(Gem.gem_def(String(g["name"]), Data.gems).get("code", "")), int(g["tier"]))
	var ck := Equipment.parse_item_key(key)
	if ck != "":
		return Icons.equip_texture(Equipment.catalog(Data.equipment).get(ck, {}))
	if key.begins_with(EggGacha.KEY_PREFIX):
		var did := int(key.get_slice(":", 1))
		return Icons.dragon_egg_texture(did)
	var path := String(Data.item_icon_path(key))
	if path != "" and ResourceLoader.exists(path):
		return load(path)
	return null

func _bmfont_label(text: String, fnt_name: String, size: int) -> Label:
	var lb := Label.new()
	lb.text = text
	var fp := "res://assets/converted/font_ui/%s.fnt" % fnt_name
	if ResourceLoader.exists(fp):
		lb.add_theme_font_override("font", load(fp))
	lb.add_theme_font_size_override("font_size", size)
	return lb

func _bmfont_rich(bb: String, size: int) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.text = bb
	rt.fit_content = true
	rt.scroll_active = false
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fp := "res://assets/converted/font_ui/font_common.fnt"
	if ResourceLoader.exists(fp):
		rt.add_theme_font_override("normal_font", load(fp))
		rt.add_theme_font_size_override("normal_font_size", size)
	else:
		rt.add_theme_font_size_override("normal_font_size", size)
	return rt

func _has_batchim(word: String) -> bool:
	if word.is_empty(): return false
	var c := word.unicode_at(word.length() - 1)
	if c < 0xAC00 or c > 0xD7A3: return false
	return ((c - 0xAC00) % 28) != 0

func _apply_boss_phase(eb: Dictionary) -> void:
	var st := _stage_rec()
	if not Darknix.is_summon_stage(st):
		return
	var p: Dictionary = (st["summon"] as Dictionary).get("phase2", {})
	if p.is_empty():
		return
	eb["phase"] = 1
	eb["phase2_at"] = float(p.get("hp_threshold", 0.0))
	eb["phase2_taken_mult"] = float(p.get("damage_taken_mult", 1.0))

func _darknix_kill(st: Dictionary, phases: Array) -> String:
	var frng := RandomNumberGenerator.new(); frng.randomize()
	var dmode := Drops.mode_of(bool(_params.get("hero", false)),
		bool(_params.get("night", false)), _is_kades())
	var txt := ""
	for sd in Drops.roll_special(st, frng, dmode, true):
		var skey := String((sd as Dictionary)["key"])
		var sqty := int((sd as Dictionary)["count"])
		UserDB.add_item(skey, sqty)
		txt += " / %s x%d" % [_drop_display_name(skey), sqty]
		phases.append({"key": skey, "count": sqty})
	for md in Drops.roll_monster(Data.monster_drops, int(_enemy.get("id", 0)), frng):
		var mrow: Dictionary = md
		var mqty := int(mrow["count"])
		if String(mrow.get("kind", "item")) == "currency":
			UserDB.add_currency(String(mrow["currency"]), mqty)
			txt += " / 다이아 x%d" % mqty
			phases.append({"kind": "dia", "count": mqty})
			continue
		var mkey := String(mrow["key"])
		UserDB.add_item(mkey, mqty)
		txt += " / %s x%d" % [_drop_display_name(mkey), mqty]
		phases.append({"key": mkey, "count": mqty})
	UserDB.darknix_clear()
	return txt

func _big_button(text: String, frame: String, pos: Vector2, cb: Callable) -> void:
	var np := NinePatchRect.new()
	np.texture = load("res://assets/converted/ninepatch_ui/%s.tres" % frame)
	np.patch_margin_left = 16; np.patch_margin_right = 16
	np.patch_margin_top = 16; np.patch_margin_bottom = 16
	np.size = Vector2(280, 86); np.position = pos
	np.z_index = 124
	add_child(np)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = np.size; l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	np.add_child(l)
	var b := Button.new()
	b.flat = true; b.size = np.size
	b.pressed.connect(cb)
	np.add_child(b)

func _find(internal_name: String) -> Dictionary:
	return _views.get(internal_name, {})

func _disp(internal_name) -> String:
	var n := String(internal_name)
	if n == "E0":
		return String(_enemy.get("name", "적"))
	if n.begins_with("A") and n.substr(1).is_valid_int():
		var i := int(n.substr(1))
		if i < _party.size():
			return String(_party[i].get("name", "드래곤"))
	return n

func _wait(base: float) -> void:
	var t := 0.03 if _skip else base / _speed
	await get_tree().create_timer(t).timeout

func _vis() -> Vector2:
	return get_viewport_rect().size

func _man(dir: String) -> Dictionary:
	return AtlasUI.manifest(dir)

func _portrait(id: int, stage: String, scale := 1.0) -> Sprite2D:
	var dir := "portrait_%d" % id
	if not _portrait_man.has(dir):
		_portrait_man[dir] = _man(dir)
	var frame := "dragon_dragon_%d_box_%s" % [id, stage]
	if not (_portrait_man[dir] as Dictionary).has(frame) and stage == "evolution":
		frame = "dragon_dragon_%d_box_adult" % id
	return _spr(dir, frame, _portrait_man[dir], scale)

func _img_button(frame: String, size: Vector2, scale := 1.0) -> Button:
	var b := Button.new()
	b.size = size
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	var sp := _spr("adventure_ui", frame, _adv, scale)
	if sp:
		sp.position = size * 0.5
		b.add_child(sp)
	else:
		b.text = frame.get_slice("_", -1)
	return b

func _img_button_from(dir: String, frame: String, man: Dictionary, scale := 1.0) -> Button:
	var sp := _spr(dir, frame, man, scale)
	if sp == null:
		return null
	var fi: Dictionary = man.get(frame, {})
	var b := Button.new()
	b.size = Vector2(float(fi.get("w", 32)), float(fi.get("h", 32))) * scale
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	sp.position = b.size * 0.5
	b.add_child(sp)
	return b

func _spr(dir: String, name: String, man: Dictionary, scale := 1.0) -> Sprite2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if not ResourceLoader.exists(p):
		return null
	var s := Sprite2D.new()
	s.texture = load(p)
	s.material = _pma
	s.scale = Vector2(scale, scale)
	return s

func _play_fx_spine_scene(path: String, v: Dictionary) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var holder := Node2D.new()
	holder.z_index = 100
	add_child(holder)
	holder.position = v.get("center", _vis() * 0.5)
	holder.scale = v.get("base_scale", Vector2(0.85, 0.85))
	var inst = (load(path) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
	if ap and ap.has_animation("animation"):
		ap.get_animation("animation").loop_mode = Animation.LOOP_NONE
		ap.play("animation")
	var t2 := holder.create_tween()
	t2.tween_interval(_SKILL_SPINE_SEC)
	t2.tween_callback(holder.queue_free)
	return true

func _play_skill_spine(sid: int, v: Dictionary) -> bool:
	var path := "res://scenes/fx/skill_%d_spine.tscn" % sid
	if not ResourceLoader.exists(path):
		return false
	var holder := Node2D.new()
	holder.z_index = 100
	add_child(holder)
	holder.position = v.get("center", _vis() * 0.5)
	holder.scale = v.get("base_scale", Vector2(0.85, 0.85))
	var inst = (load(path) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
	if ap:
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
	t.tween_interval(_SKILL_SPINE_SEC)
	t.tween_callback(holder.queue_free)
	return true
