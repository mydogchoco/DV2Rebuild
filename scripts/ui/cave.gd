extends Control

const DragonAwakenSkillInfoPopup := preload("res://scripts/ui/dragon_awaken_skill_info.gd")

const UI := "res://assets/converted/cave_ui/%s.tres"
const STAND := "res://assets/converted/stand_ui/stand_stand%d.tres"
const BG := "res://assets/converted/cave_bg/cavebg%d.jpg"
const DRAGON_SCENE := "res://scenes/dragons/dragon_%d_%s.tscn"
const SKIN_COUNT := 15
const STAND_COUNT := 16

const PED_WIDTH := 620.0
const PED_BOTTOM := 357.0
const PED_DRAGON_SCALE := 1.9
const PED_DRAGON_Y := -7.0

var _pma: CanvasItemMaterial
var _manifest: Dictionary = {}
var _stand_manifest: Dictionary = {}
var _battle_manifest: Dictionary = {}
var _status_manifest: Dictionary = {}
var _portrait_manifests: Dictionary = {}
var _item_small_manifest: Dictionary = {}
var _elem_icon: Sprite2D
var _dragon_ap: AnimationPlayer
var _bg: TextureRect
var _walls: Node2D
var _wall_left_spr: Sprite2D
var _wall_right_spr: Sprite2D
var _wall_left_x := 0.0
var _wall_right_x := 0.0
var _stage: Node2D
var _list_box: VBoxContainer
var _stat_plates: Dictionary = {}
var _slot_layer: Control
var _skill_fx_slot: int = -1
var _overlay: Control
var _overlay_layer: CanvasLayer
var _skill_modal: CanvasLayer
var _equip_pop: EquipSlotsPanel
var _params: Dictionary = {}

func enter(params: Dictionary = {}) -> void:
	_params = params

func _ready() -> void:
	Bgm.play("bg_cave")
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	var mf := FileAccess.open("res://assets/converted/cave_ui/_manifest.json", FileAccess.READ)
	if mf: _manifest = JSON.parse_string(mf.get_as_text())
	var sf := FileAccess.open("res://assets/converted/stand_ui/_manifest.json", FileAccess.READ)
	if sf: _stand_manifest = JSON.parse_string(sf.get_as_text())
	var bf := FileAccess.open("res://assets/converted/battle_ui/_manifest.json", FileAccess.READ)
	if bf: _battle_manifest = JSON.parse_string(bf.get_as_text())
	var stf := FileAccess.open("res://assets/converted/status_ui/_manifest.json", FileAccess.READ)
	if stf: _status_manifest = JSON.parse_string(stf.get_as_text())
	var isf := FileAccess.open("res://assets/converted/item_small_ui/_manifest.json", FileAccess.READ)
	if isf: _item_small_manifest = JSON.parse_string(isf.get_as_text())

	_build_background()
	_build_walls()
	_build_stage()
	_build_quick_panel()
	_build_dragon_list()
	_build_bottom_bar()
	_build_menu()
	_build_topbar()
	_refresh()
	_open_requested()

func _open_requested() -> void:
	var what := String(_params.get("open", ""))
	match what:
		"status": _open_dragon_detail()
		"dex": _open_dex()
		"bag": _open_inventory()
		"quests": _open_quests()
		"titles": _open_titles()
		"rename", "equip", "gem", "skill", "levelup", \
		"awaken_dex", "skin", "storage":
			_on_status_action(what, int(_params.get("arg", -1)))

func _ui_tex(name: String) -> AtlasTexture:
	var p := UI % name
	return load(p) if ResourceLoader.exists(p) else null

func _ui_sprite(name: String, scale := 1.0) -> Sprite2D:
	return _atlas_sprite("cave_ui", name, _manifest, scale)

func _atlas_sprite(dir: String, name: String, man: Dictionary, scale := 1.0) -> Sprite2D:
	var s := Sprite2D.new()
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if ResourceLoader.exists(p):
		s.texture = load(p)
	s.material = _pma
	s.scale = Vector2(scale, scale)
	return s

func _panel(col := Color(0, 0, 0, 0.55)) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.25)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _active() -> Dictionary:
	return UserDB.active_dragon()

func _vis() -> Vector2:
	return get_viewport_rect().size

const S1080 := 692.0 / 1080.0

func _build_background() -> void:
	_bg = TextureRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.z_index = -10
	add_child(_bg)

const WALL_SKINS := [1, 8, 9, 10, 11, 12, 13, 14, 15]

func _wall_number_for_theme() -> int:
	var theme_num := UserDB.get_skin("cave_skin") + 1
	return theme_num if theme_num in WALL_SKINS else 1

func _build_walls() -> void:
	if _walls == null:
		_walls = Node2D.new()
		add_child(_walls)
	for ch in _walls.get_children():
		ch.queue_free()
	var man := {}
	var f := FileAccess.open("res://assets/converted/wall_ui/_manifest.json", FileAccess.READ)
	if f: man = JSON.parse_string(f.get_as_text())
	const S := 692.0 / 519.0
	var vis := _vis()
	var dir := "res://assets/converted/wall_ui/%s.tres"
	var wn := _wall_number_for_theme()
	var ln := "scene_cave_wall_%d_wall_left" % wn
	var rn := "scene_cave_wall_%d_wall_right" % wn
	var bn := "scene_cave_wall_%d_wall_bottom" % wn
	_wall_left_spr = _wall(dir % ln, man.get(ln, {}), S, func(dw, _dh): return Vector2(dw / 2.0, vis.y / 2.0))
	_wall_right_spr = _wall(dir % rn, man.get(rn, {}), S, func(dw, _dh): return Vector2(vis.x - dw / 2.0, vis.y / 2.0))
	_wall(dir % bn, man.get(bn, {}), S, func(_dw, dh): return Vector2(vis.x / 2.0, vis.y - dh / 2.0))
	_wall_left_x = _wall_left_spr.position.x if is_instance_valid(_wall_left_spr) else 0.0
	_wall_right_x = _wall_right_spr.position.x if is_instance_valid(_wall_right_spr) else 0.0
	_apply_wall_shift(false)

func _wall(path: String, info: Dictionary, s: float, place: Callable) -> Sprite2D:
	if not ResourceLoader.exists(path): return null
	var spr := Sprite2D.new()
	spr.texture = load(path)
	spr.material = _pma
	spr.scale = Vector2(s, s)
	var dw: float = float(info.get("w", 0)) * s
	var dh: float = float(info.get("h", 0)) * s
	spr.position = place.call(dw, dh)
	_walls.add_child(spr)
	return spr

func _build_stage() -> void:
	var vis := _vis()
	_stage = Node2D.new()
	_stage.scale = Vector2(S1080, S1080)
	_stage.position = Vector2(vis.x / 2.0, vis.y / 2.0 - 8.0)
	add_child(_stage)
	_dragon_btn = Button.new()
	_dragon_btn.flat = true
	var bs := 320.0 * S1080
	_dragon_btn.size = Vector2(bs, bs)
	_dragon_btn.position = Vector2(vis.x / 2.0 - bs / 2.0, vis.y / 2.0 - bs / 2.0 - 26.0)
	_dragon_btn.pressed.connect(_on_dragon_clicked)
	add_child(_dragon_btn)
	_guide_targets["stand"] = _dragon_btn

const LIST_W := 110.0
const LIST_BOTTOM := 100.0
const LIST_TOP_PAD := 15.0
const SLOT_GAP := 5.0

func _build_dragon_list() -> void:
	var vis := _vis()
	var sc := ScrollContainer.new()
	sc.position = Vector2(0.0, LIST_TOP_PAD)
	sc.custom_minimum_size = Vector2(LIST_W, maxf(120.0, vis.y - LIST_BOTTOM - LIST_TOP_PAD))
	sc.size = sc.custom_minimum_size
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(sc)
	_left_wall = sc
	_guide_targets["dragon_list"] = sc
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", SLOT_GAP)
	sc.add_child(_list_box)

var _name_label: RichTextLabel
var _grade_label: Label
var _bottom_bar: Control

func _build_bottom_bar() -> void:
	var bar := Control.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vis := _vis()
	var bs := (vis.x - 24.0) / 1864.0
	bar.size = Vector2(1864, 150)
	bar.scale = Vector2(bs, bs)
	bar.position = Vector2(12, vis.y - 150.0 * bs - 6.0)
	add_child(bar)
	_bottom_bar = bar
	var barhit := Control.new()
	barhit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	barhit.position = bar.position
	barhit.size = bar.size * bs
	add_child(barhit)
	_guide_targets["bottom_bar"] = barhit

	var badge := Control.new()
	badge.position = Vector2(20, 40); badge.size = Vector2(84, 84)
	bar.add_child(badge)
	_grade_label = Label.new()
	_grade_label.size = Vector2(84, 84)
	_grade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_grade_label.add_theme_font_size_override("font_size", 34)
	_grade_label.add_theme_color_override("font_color", Color(1.0, 0.62, 0.12))
	_grade_label.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.0, 0.9))
	_grade_label.add_theme_constant_override("outline_size", 5)
	_grade_label.position = Vector2(0, 0)
	badge.add_child(_grade_label)
	var cm := _man_common()
	var star := _atlas_sprite("common_ui", "common_btn_star", cm, 0.7)
	if star: star.position = Vector2(42, 16); badge.add_child(star)
	var hit := Button.new(); hit.flat = true; hit.size = Vector2(84, 84)
	hit.pressed.connect(_open_dragon_detail); badge.add_child(hit)

	var ebg := _atlas_sprite("common_ui", "common_element_bg", cm, 0.62)
	if ebg: ebg.position = Vector2(146, 32); bar.add_child(ebg)
	_elem_icon = Sprite2D.new()
	_elem_icon.material = _pma
	_elem_icon.position = Vector2(146, 32)
	bar.add_child(_elem_icon)
	var ehit := Button.new(); ehit.flat = true; ehit.size = Vector2(56, 56)
	ehit.position = Vector2(118, 4); ehit.pressed.connect(_open_element_info)
	bar.add_child(ehit)
	var nplate := NinePatchRect.new()
	nplate.texture = load("res://assets/converted/ninepatch_ui/9patch_train_box3.tres")
	nplate.patch_margin_left = 30; nplate.patch_margin_right = 30
	nplate.patch_margin_top = 16; nplate.patch_margin_bottom = 16
	nplate.size = Vector2(452, 48); nplate.position = Vector2(180, 10)
	nplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(nplate)
	_name_label = RichTextLabel.new()
	_name_label.bbcode_enabled = true
	_name_label.fit_content = true
	_name_label.scroll_active = false
	_name_label.position = Vector2(180, 14)
	_name_label.size = Vector2(452, 44)
	_name_label.add_theme_font_size_override("normal_font_size", 30)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_name_label)
	var nhit := Button.new()
	nhit.flat = true
	nhit.position = Vector2(180, 10); nhit.size = Vector2(452, 48)
	nhit.tooltip_text = "이름 바꾸기"
	nhit.pressed.connect(_open_rename)
	bar.add_child(nhit)
	_guide_targets["name"] = nhit
	var stat_defs := [["hp", "생명력"], ["att", "공격력"], ["def", "방어력"]]
	for i in stat_defs.size():
		var key: String = stat_defs[i][0]
		var plate := NinePatchRect.new()
		plate.texture = load("res://assets/converted/ninepatch_ui/9patch_train_box4.tres")
		plate.patch_margin_left = 22; plate.patch_margin_right = 22
		plate.patch_margin_top = 16; plate.patch_margin_bottom = 16
		plate.size = Vector2(196, 84)
		plate.position = Vector2(112 + i * 206, 62)
		bar.add_child(plate)
		var cap := Label.new()
		cap.text = String(stat_defs[i][1])
		cap.add_theme_font_size_override("font_size", 19)
		cap.add_theme_color_override("font_color", Color(0.92, 0.90, 0.82))
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.size = Vector2(196, 24); cap.position = Vector2(0, 6)
		plate.add_child(cap)
		var val := Label.new()
		val.name = "val"
		val.add_theme_font_size_override("font_size", 26)
		val.add_theme_color_override("font_color", Color.WHITE)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.size = Vector2(196, 34); val.position = Vector2(0, 34)
		plate.add_child(val)
		_stat_plates[key] = val

	var lv := Button.new()
	lv.text = "훈련"
	lv.position = Vector2(1786, 10); lv.size = Vector2(64, 36)
	lv.pressed.connect(_open_training_select)
	bar.add_child(lv)

	_slot_layer = Control.new()
	_slot_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot_layer.size = bar.size
	bar.add_child(_slot_layer)
	_refresh_slots()

func _stats_with_gems(a: Dictionary, _level: int) -> Dictionary:
	var base_bonus: Dictionary = (a.get("stat_bonus", {}) as Dictionary).get("base", {})
	var st: Dictionary = Growth.main_stats(
		Data.get_dragon(int(a.get("id", 0))), Data.stat_table, a.get("gain_log", []), base_bonus)
	st = Gem.apply(st, a.get("gems", {}), Data.gems)
	st = Equipment.apply(st, a.get("equip", {}), Data.equipment)
	return EquipEffect.apply_static(st, a.get("equip", {}), Data.equip_effects)

func _gem_slots(a: Dictionary) -> Array:
	return Gem.slots(a.get("gems", {}))

func _equip_gem(uid: int, gem_name: String, tier: int, meta: Dictionary = {}) -> bool:
	var d := UserDB.get_dragon(uid)
	var next: Dictionary = Gem.equip(d.get("gems", {}), gem_name, tier, Data.gems, meta)
	if next.is_empty(): return false
	UserDB.set_dragon_field(uid, "gems", next)
	return true

func _equip_gem_from_bag(item_key: String) -> void:
	var g := Gem.parse_item_key(item_key)
	if g.is_empty(): return
	var a := _active()
	if a.is_empty():
		_toast("젬을 장착할 드래곤이 없습니다"); return
	var uid := int(a["uid"])
	if UserDB.item_count(item_key) <= 0:
		_toast("보유하지 않은 젬입니다"); return
	var gem_name := String(g["name"])
	var tier := int(g["tier"])
	if Gem.all_full(UserDB.get_dragon(uid).get("gems", {})):
		_toast("젬 슬롯이 모두 사용 중입니다"); return
	if not _equip_gem(uid, gem_name, tier, g):
		_open_popup_type("젬 장착", Data.ui("#774f4b10"), func(): pass, "확인", "")
		return
	UserDB.use_item(item_key, 1)
	_refresh_stats()
	_close_overlay()
	_refresh()
	_toast("젬을 장착하였습니다")

func _gem_line(gem_name: String, tier: int) -> String:
	return "%s  [%s]  %s" % [
		Gem.display_name(gem_name, tier, Data.gems),
		Gem.shape_label(gem_name, tier, Data.gems),
		Gem.effect_text(gem_name, tier, Data.gems)]

func _gold_str(g: int) -> String:
	if g >= 10000: return "%d만G" % int(g / 10000.0)
	return "%dG" % g

func _unequip_gem(uid: int, slot: int) -> void:
	var en := Gem.entries(UserDB.get_dragon(uid).get("gems", {}))
	if slot >= 0 and slot < Gem.SLOTS and en[slot] != null:
		UserDB.add_item(Gem.slot_to_item_key(en[slot]), 1)
	UserDB.set_dragon_field(uid, "gems", Gem.unequip_at(UserDB.get_dragon(uid).get("gems", {}), slot))

func _return_all_gems(uid: int, gems_field: Dictionary) -> int:
	var n := 0
	for e in Gem.entries(gems_field):
		if e != null:
			UserDB.add_item(Gem.slot_to_item_key(e), 1)
			n += 1
	if n > 0:
		UserDB.set_dragon_field(uid, "gems",
			{"types": Gem.types(gems_field), "slots": [null, null, null]})
	return n

func _open_gem_tab() -> void:
	if _active().is_empty(): return
	_inv_tab = "gem"
	_inv_selected = ""
	_open_inventory()

func _equip_enhance_limit(sd: Dictionary) -> int:
	return Equipment.enhance_cap_of_slot(sd, Data.equipment)

func _equip_stat_kr(key: String) -> String:
	return {
		"hp": "HP", "att": "공", "def": "방", "blk": "막기", "evd": "회피", "cri": "크리",
		"cri_pow": "크파", "pure": "관통", "depure": "관통감소", "accuracy": "명중",
		"cure": "치유", "awaken_rate": "각성", "gold": "골드", "exp": "경험",
	}.get(key, key)

func _open_equipment() -> void:
	var a := _active()
	if a.is_empty(): return
	var uid := int(a["uid"])
	if is_instance_valid(_equip_pop):
		_equip_pop.close()
	_equip_pop = EquipSlotsPanel.open(self, uid, "equip", func(sid: String, unlocked: bool):
		if not unlocked:
			_toast("%s  (연구소 '드래곤 강화')" % EquipSlotsPanel.S_LOCK)
			return
		_open_item_popup(sid))
	_equip_pop.closed.connect(func():
		_equip_pop = null
		_refresh_stats())

func _open_item_popup(slot_id: String) -> void:
	var a := _active()
	if a.is_empty(): return
	var refresh_equipment := func():
		_refresh_stats()
		if is_instance_valid(_equip_pop):
			_equip_pop.rebuild()
	var p := ItemWindow.open(self, int(a["uid"]), slot_id, refresh_equipment)
	p.closed.connect(refresh_equipment)

func _dup_main_stats(uid: int, slot_id: String) -> PackedStringArray:
	var cat := Equipment.catalog(Data.equipment)
	var eqf: Dictionary = UserDB.get_dragon(uid).get("equip", {})
	var mine: Dictionary = {}
	var others: Dictionary = {}
	for sl in (eqf.get("slots", []) as Array):
		var sd := sl as Dictionary
		var it: Dictionary = cat.get(String(sd.get("key", "")), {})
		for st in (it.get("stat_main", {}) as Dictionary):
			if String(sd.get("slot", "")) == slot_id:
				mine[st] = true
			else:
				others[st] = true
	var out: PackedStringArray = []
	for st in mine:
		if others.has(st):
			out.append(_equip_stat_kr(String(st)))
	return out

func _dragon_label(uid: int) -> String:
	var d: Dictionary = UserDB.get_dragon(uid)
	if d.is_empty():
		return "다른 드래곤"
	return Icons.name_of(d)

func _equip_slot_data(eqf: Dictionary, slot_id: String) -> Dictionary:
	for s in (eqf.get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) == slot_id:
			return s
	return {}

func _reroll_options(uid: int, slot_id: String) -> void:
	var sd := _equip_slot_data(UserDB.get_dragon(uid).get("equip", {}), slot_id)
	if sd.is_empty():
		_toast("장비가 없는 칸입니다"); return
	var grade := int(sd.get("grade", 0))
	var items: Dictionary = Data.equipment.get("option", {}).get("reroll_items", {})
	var used := String(items.get(str(grade), ""))
	var gname := ""
	var grades: Array = Data.equipment.get("option", {}).get("grades", [])
	if grade >= 0 and grade < grades.size():
		gname = String((grades[grade] as Dictionary).get("name", ""))
	if used == "":
		_toast("%s 등급은 옵션을 변경할 수 있는 장신구가 아닙니다" % gname); return
	if UserDB.item_count(used) <= 0:
		_toast("%s이(가) 없습니다" % Data.item_name(used)); return
	_open_popup_type("장비 선택",
		Data.ui("#e5a90c1a") + "

%s  X %d"
			% [Data.item_name(used), UserDB.item_count(used)],
		func():
			if not UserDB.use_item(used, 1):
				return
			EquipOptionView.open(self, uid, slot_id, used, grade,
				func(changed: bool):
					_refresh_stats()
					if changed:
						_toast("%s 옵션으로 변경했습니다" % gname)
					else:
						_toast("기존 옵션을 유지했습니다")),
		"확인", "취소")

func _unbind_equip(uid: int, slot_id: String) -> void:
	var key := String(Data.equipment.get("option", {}).get("unbind_item", "item_disconnect"))
	if UserDB.item_count(key) <= 0:
		_toast("구드라의 지혜가 없습니다"); return
	var cur: Dictionary = UserDB.get_dragon(uid).get("equip", {})
	var sd := _equip_slot_data(cur, slot_id)
	if sd.is_empty() or int(sd.get("belong", 0)) <= 0:
		_toast("귀속되지 않은 아이템입니다"); return
	if not UserDB.use_item(key, 1):
		return
	var freed := sd.duplicate(true)
	freed["belong"] = 0
	UserDB.add_item(Equipment.slot_to_item_key(freed), 1)
	UserDB.set_dragon_field(uid, "equip", Equipment.unequip(cur, slot_id))
	_refresh_stats()
	_toast("귀속을 해제했습니다 — 장비는 가방으로 돌아갑니다")

func _enhance_option(uid: int, slot_id: String) -> void:
	ItemEnchantView.open(self, ItemEnchantView.target_worn(uid, slot_id),
		func(): _refresh_stats())

var _acc_data: Dictionary = {}
func _acc_def(type_key: String) -> Dictionary:
	if _acc_data.is_empty():
		var f := FileAccess.open(Data.data_path("accessories.json"), FileAccess.READ)
		if f: _acc_data = JSON.parse_string(f.get_as_text())
	return _acc_data.get("types", {}).get(type_key, {})

func _equip_accessory(uid: int, type_key: String) -> void:
	var ad := _acc_def(type_key)
	if ad.is_empty(): return
	var lv := int(UserDB.get_dragon(uid).get("level", 1))
	var grade := clampi(lv / 8, 0, 6)
	var grades: Array = ad.get("grades", [])
	if grades.is_empty(): return
	var acc: Dictionary = UserDB.get_dragon(uid).get("accessory", {}).duplicate()
	acc[String(ad["stat"])] = int(grades[clampi(grade, 0, grades.size() - 1)])
	UserDB.set_dragon_field(uid, "accessory", acc)

func _unequip_accessory(uid: int) -> void:
	UserDB.set_dragon_field(uid, "accessory", {})

func _open_dragon_detail() -> void:
	var l := StatusPanel.open(self)
	l.action_requested.connect(_on_status_action)
	l.closed.connect(func():
		if is_inside_tree(): _refresh(); _refresh_stats())

func _on_status_action(action: String, arg: int) -> void:
	match action:
		"rename": _rename_gate()
		"equip": _open_equipment()
		"gem":
			var a := _active()
			var en := Gem.entries(a.get("gems", {})) if not a.is_empty() else []
			if arg >= 0 and arg < en.size() and en[arg] != null: _confirm_unequip_gem(arg)
			else: _open_gem_tab()
		"skill": _open_skill_select(maxi(arg, 0))
		"levelup": _open_levelup()
		"awaken_dex": _open_awaken_dex()
		"skin": _open_dragon_skin()
		"storage": _open_dragon_storage()

func _open_item_select(title: String, on_select: Callable, category := "") -> void:
	_open_backdrop(0.55)
	var vis := _vis()
	var BW := clampf(vis.x - 120.0, 640.0, 900.0)
	var BH := clampf(vis.y - 80.0, 480.0, 640.0)
	var cm := _man_common()
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	_overlay.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(320, 54); tbar.position = Vector2((BW - 320) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = title
	tl.add_theme_font_size_override("font_size", 26); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 66, 14); xb.pressed.connect(_close_overlay); win.add_child(xb)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 92); scroll.size = Vector2(BW - 80, BH - 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = maxi(4, int((BW - 80) / 130.0))
	grid.add_theme_constant_override("h_separation", 8); grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	var any := false
	for key in UserDB.inventory().keys():
		var k := String(key)
		if UserDB.item_count(k) <= 0: continue
		if category != "" and String(Data.get_item(k).get("category", "")) != category: continue
		any = true
		grid.add_child(_item_select_cell(k, cm, on_select))
	if not any:
		var em := Label.new(); em.text = "보유한 아이템이 없습니다."
		em.add_theme_font_size_override("font_size", 20); em.add_theme_color_override("font_color", Color(0.4, 0.3, 0.12))
		em.position = Vector2(60, 120); win.add_child(em)

func _item_select_cell(key: String, cm: Dictionary, on_select: Callable) -> Control:
	var cell := Control.new(); cell.custom_minimum_size = Vector2(120, 130)
	var bg := _atlas_sprite("common_ui", "common_item_bg", cm, 1.0)
	if bg: bg.position = Vector2(60, 56); cell.add_child(bg)
	var ip := Data.item_icon_path(key)
	if ResourceLoader.exists(ip):
		var icon := Sprite2D.new(); icon.texture = load(ip); icon.material = _pma; icon.scale = Vector2(0.6, 0.6)
		icon.position = Vector2(60, 56); cell.add_child(icon)
	var cnt := Label.new(); cnt.text = "×%d" % UserDB.item_count(key)
	cnt.add_theme_font_size_override("font_size", 15); cnt.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85))
	cnt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8)); cnt.add_theme_constant_override("outline_size", 3)
	cnt.position = Vector2(72, 74); cnt.size = Vector2(44, 22); cell.add_child(cnt)
	var nm := Label.new(); nm.text = Data.item_name(key)
	nm.add_theme_font_size_override("font_size", 13); nm.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.position = Vector2(2, 98); nm.size = Vector2(116, 30); cell.add_child(nm)
	var b := Button.new(); b.flat = true; b.size = Vector2(120, 96); b.position = Vector2(0, 4)
	b.pressed.connect(func(): _close_overlay(); on_select.call(key))
	cell.add_child(b)
	return cell

func _open_dragon_select(title: String, on_select: Callable, disable_filter := Callable()) -> void:
	_open_backdrop(0.55)
	var vis := _vis()
	var BW := clampf(vis.x - 80.0, 700.0, 1120.0)
	var BH := clampf(vis.y - 56.0, 520.0, 680.0)
	var cm := _man_common()
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	_overlay.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(340, 54); tbar.position = Vector2((BW - 340) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = title
	tl.add_theme_font_size_override("font_size", 28); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 66, 14); xb.pressed.connect(_close_overlay); win.add_child(xb)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 92); scroll.size = Vector2(BW - 80, BH - 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = maxi(4, int((BW - 80) / 160.0))
	grid.add_theme_constant_override("h_separation", 10); grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for d in UserDB.dragons():
		grid.add_child(_dragon_select_cell(d, cm, on_select, disable_filter))

func _dragon_select_cell(d: Dictionary, cm: Dictionary, on_select: Callable, disable_filter: Callable) -> Control:
	var cell := Control.new(); cell.custom_minimum_size = Vector2(150, 170)
	var disabled := disable_filter.is_valid() and bool(disable_filter.call(d))
	var por := _portrait_sprite(int(d["id"]), Growth.portrait_stage(d), 0.66, int(d.get("skin", 0)))
	if por:
		por.position = Vector2(75, 64)
		if disabled: por.modulate = Color(0.35, 0.35, 0.4, 1)
		cell.add_child(por)
	var slots: int = Loadout.slot_count(Data.get_dragon(int(d["id"])))
	var shapes := ["common_skill_triangle", "common_skill_square", "common_skill_circle", "common_skill_star"]
	for si in mini(slots, 4):
		var sh := _atlas_sprite("common_ui", shapes[si], cm, 0.5)
		if sh: sh.position = Vector2(40 + si * 24, 122); cell.add_child(sh)
	var nm := Label.new(); nm.text = "%s Lv.%d" % [Icons.species_name(int(d["id"])), int(d["level"])]
	nm.add_theme_font_size_override("font_size", 14); nm.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; nm.position = Vector2(0, 138); nm.size = Vector2(150, 22)
	cell.add_child(nm)
	if not disabled:
		var b := Button.new(); b.flat = true; b.size = Vector2(150, 130); b.position = Vector2(0, 4)
		var uid := int(d["uid"])
		b.pressed.connect(func(): _close_overlay(); on_select.call(uid))
		cell.add_child(b)
	return cell

const BAG_EXPAND_STEP := 20
const BAG_EXPAND_GOLD := 5000
const BAG_EXPAND_DIA := 10
func _bag_max() -> int:
	return int(UserDB.get_pmeta("bag_max", 240))
func _open_bag_expand() -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 72; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	const BW := 440.0
	const BH := 290.0
	var cm := _man_common()
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(280, 52); tbar.position = Vector2((BW - 280) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = "가방 확장"
	tl.add_theme_font_size_override("font_size", 26); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 58, 14); xb.pressed.connect(func(): layer.queue_free()); win.add_child(xb)
	var ml := Label.new(); ml.text = "가방 %d칸 → %d칸 (+%d)" % [_bag_max(), _bag_max() + BAG_EXPAND_STEP, BAG_EXPAND_STEP]
	ml.add_theme_font_size_override("font_size", 20); ml.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; ml.position = Vector2(40, 84); ml.size = Vector2(BW - 80, 28); win.add_child(ml)
	var do_expand := func(kind: String, cost: int):
		if UserDB.spend(kind, cost):
			UserDB.set_pmeta("bag_max", _bag_max() + BAG_EXPAND_STEP)
			layer.queue_free()
			_open_complete("가방 확장", "가방이 %d칸으로 늘었습니다!" % _bag_max())
	var gb := Button.new(); gb.size = Vector2(160, 50); gb.position = Vector2(BW * 0.5 - 174, BH - 84)
	gb.pressed.connect(func(): do_expand.call("gold", BAG_EXPAND_GOLD)); win.add_child(gb)
	var gc := _atlas_sprite("common_ui", "common_coin_small1", cm, 0.9)
	if gc: gc.position = Vector2(BW * 0.5 - 150, BH - 59); win.add_child(gc)
	var gl := Label.new(); gl.text = "%d" % BAG_EXPAND_GOLD; gl.add_theme_font_size_override("font_size", 20)
	gl.add_theme_color_override("font_color", Color.WHITE); gl.position = Vector2(BW * 0.5 - 128, BH - 72); gl.size = Vector2(120, 28); win.add_child(gl)
	var db := Button.new(); db.size = Vector2(160, 50); db.position = Vector2(BW * 0.5 + 14, BH - 84)
	db.pressed.connect(func(): do_expand.call("diamond", BAG_EXPAND_DIA)); win.add_child(db)
	var dc := _atlas_sprite("common_ui", "common_diamond_small1", cm, 0.9)
	if dc: dc.position = Vector2(BW * 0.5 + 38, BH - 59); win.add_child(dc)
	var dl := Label.new(); dl.text = "%d" % BAG_EXPAND_DIA; dl.add_theme_font_size_override("font_size", 20)
	dl.add_theme_color_override("font_color", Color.WHITE); dl.position = Vector2(BW * 0.5 + 60, BH - 72); dl.size = Vector2(100, 28); win.add_child(dl)

func _open_complete(title: String, msg: String, on_confirm := Callable()) -> void:
	Bgm.sfx("effect_equip_success")
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 72; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	const BW := 420.0
	const BH := 260.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(280, 52); tbar.position = Vector2((BW - 280) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = title
	tl.add_theme_font_size_override("font_size", 26); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	var ml := Label.new(); ml.text = msg
	ml.add_theme_font_size_override("font_size", 21); ml.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ml.position = Vector2(40, 80); ml.size = Vector2(BW - 80, 80); win.add_child(ml)
	var ok := Button.new(); ok.text = "확인"; ok.size = Vector2(160, 46); ok.position = Vector2((BW - 160) * 0.5, BH - 62)
	ok.pressed.connect(func():
		if is_instance_valid(layer): layer.queue_free()
		if on_confirm.is_valid(): on_confirm.call())
	win.add_child(ok)

func _open_popup_type(title: String, msg: String, on_confirm: Callable, confirm_text := "확인",
		cancel_text := "취소", item_key := "") -> void:
	var icon: Sprite2D = null
	var item_text := ""
	if item_key != "":
		icon = _popup_item_icon(item_key)
		item_text = _inventory_item_name(item_key)
	MessageWindow.open(self, title, msg, on_confirm, confirm_text, cancel_text,
		-1, 0, Callable(), icon, item_text)

func _popup_item_icon(key: String) -> Sprite2D:
	var s := _inventory_item_icon(key, 1.0)
	if s == null:
		return null
	s.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	return s

var _smelt_count := 1

func _open_smelt(source_key: String) -> void:
	var recipe: Dictionary = ItemSmelt.for_source(source_key, Data.combine_item)
	if recipe.is_empty():
		_toast("제련할 수 없는 아이템입니다"); return
	_smelt_count = 1
	_smelt_body(source_key, recipe)

func _smelt_body(source_key: String, recipe: Dictionary) -> void:
	_close_overlay()
	_open_backdrop(0.55)
	var vis := _vis()
	var BW := 700.0
	var BH := 470.0
	var cm := _man_common()
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190
	win.patch_margin_right = 40; win.patch_margin_bottom = 58
	win.size = Vector2(BW, BH)
	win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	_overlay.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20
	tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(300, 54); tbar.position = Vector2((BW - 300) * 0.5, 12)
	win.add_child(tbar)
	var title := Label.new(); title.text = "재료 제련"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size = tbar.size; tbar.add_child(title)
	var xb := TextureButton.new()
	xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 66, 14); xb.pressed.connect(_close_overlay)
	win.add_child(xb)
	var mats: Array = ItemSmelt.materials(recipe)
	var target := String(recipe.get("target", ""))
	var have: Dictionary = {}
	for m in mats:
		have[String((m as Dictionary)["item"])] = UserDB.item_count(String((m as Dictionary)["item"]))
	var slot_sz := Vector2(150, 200)
	var sy := 92.0
	var lx := 70.0
	var rx := BW - 70.0 - slot_sz.x
	_smelt_slot(win, Vector2(lx, sy), slot_sz, String((mats[0] as Dictionary)["item"]),
		"%d / %d" % [int(have.get(String((mats[0] as Dictionary)["item"]), 0)),
			int((mats[0] as Dictionary)["count"]) * _smelt_count], cm)
	_smelt_slot(win, Vector2(rx, sy), slot_sz, target, "×%d" % _smelt_count, cm)
	var midx := BW * 0.5 - 8.0
	if mats.size() > 1:
		var pl := _atlas_sprite("common_ui", "common_plus", cm, Design.ASSET_SCALE)
		if pl: pl.position = Vector2(midx, sy + 70.0); win.add_child(pl)
		_smelt_slot(win, Vector2(lx, sy + 210.0), Vector2(150, 96),
			String((mats[1] as Dictionary)["item"]),
			"%d / %d" % [int(have.get(String((mats[1] as Dictionary)["item"]), 0)),
				int((mats[1] as Dictionary)["count"]) * _smelt_count], cm)
	var fold := _atlas_sprite("common_ui", "common_btn_fold", cm, Design.ASSET_SCALE * 1.4)
	if fold:
		fold.rotation_degrees = 90.0
		fold.position = Vector2(midx, sy + 110.0)
		win.add_child(fold)
	var gold := UserDB.gold()
	var maxn := ItemSmelt.max_count(recipe, have, gold)
	_smelt_count = clampi(_smelt_count, 1, maxi(1, maxn))
	var cy := sy + 214.0
	var minus := _smelt_arrow(win, "common_btn_arrow1", Vector2(BW * 0.5 - 50.0, cy + 22.0), cm)
	minus.pressed.connect(func():
		_smelt_count = maxi(1, _smelt_count - 1)
		_smelt_body(source_key, recipe))
	var cnt := Label.new(); cnt.text = str(_smelt_count)
	cnt.add_theme_font_size_override("font_size", 30)
	cnt.add_theme_color_override("font_color", Color(0.3, 0.18, 0.03))
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cnt.position = Vector2(BW * 0.5 - 34.0, cy); cnt.size = Vector2(68, 44)
	win.add_child(cnt)
	var plusb := _smelt_arrow(win, "common_btn_arrow2", Vector2(BW * 0.5 + 50.0, cy + 22.0), cm)
	plusb.pressed.connect(func():
		_smelt_count = mini(maxi(1, maxn), _smelt_count + 1)
		_smelt_body(source_key, recipe))
	var cost := ItemSmelt.total_cost(recipe, _smelt_count)
	var coin := _atlas_sprite("common_ui", "common_coin_small1", cm, Design.ASSET_SCALE)
	if coin: coin.position = Vector2(BW * 0.5 - 60.0, cy + 62.0); win.add_child(coin)
	var cl := Label.new(); cl.text = str(cost)
	cl.add_theme_font_size_override("font_size", 24)
	cl.add_theme_color_override("font_color",
		Color(0.3, 0.18, 0.03) if gold >= cost else Color(0.72, 0.16, 0.10))
	cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cl.position = Vector2(BW * 0.5 - 40.0, cy + 44.0); cl.size = Vector2(160, 36)
	win.add_child(cl)
	var ok := ItemSmelt.affordable(recipe, _smelt_count, have, gold)
	var bg := NinePatchRect.new()
	bg.texture = load("res://assets/converted/ninepatch_ui/9patch_btn.tres")
	bg.patch_margin_left = 16; bg.patch_margin_right = 16
	bg.patch_margin_top = 16; bg.patch_margin_bottom = 16
	bg.size = Vector2(270, 56); bg.position = Vector2((BW - 270) * 0.5, BH - 78.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not ok: bg.modulate = Color(0.6, 0.6, 0.6)
	win.add_child(bg)
	var sb := Button.new(); sb.flat = true
	sb.text = "%d 제련" % _smelt_count
	sb.add_theme_font_size_override("font_size", 28)
	sb.add_theme_color_override("font_color", Color.WHITE)
	sb.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0, 0.9))
	sb.add_theme_constant_override("outline_size", 5)
	sb.size = Vector2(270, 56); sb.position = Vector2((BW - 270) * 0.5, BH - 78.0)
	sb.pressed.connect(func():
		if not ok:
			_toast("재료나 골드가 부족합니다"); return
		_open_popup_type("재료 제련", "%s을 제련하시겠습니까?" % Data.item_name(source_key),
			func(): _do_smelt(source_key, recipe, _smelt_count)))
	win.add_child(sb)

func _smelt_arrow(win: Control, frame: String, center: Vector2, cm: Dictionary) -> Button:
	var s := 1.05 * Design.ASSET_SCALE
	var spr := _atlas_sprite("common_ui", frame, cm, s)
	var sz := Vector2(44, 44)
	if spr:
		spr.position = center
		win.add_child(spr)
		if spr.texture != null:
			sz = spr.texture.get_size() * s
	var b := Button.new(); b.flat = true
	b.size = sz.max(Vector2(44, 44))
	b.position = center - b.size * 0.5
	win.add_child(b)
	return b

func _smelt_slot(win: Control, pos: Vector2, sz: Vector2, item_key: String,
		count_text: String, cm: Dictionary) -> void:
	var box := _panel(Color(0.18, 0.11, 0.05, 0.35))
	box.position = pos; box.size = sz
	win.add_child(box)
	var ip := Data.item_icon_path(item_key)
	if ip != "" and ResourceLoader.exists(ip):
		var ic := Sprite2D.new(); ic.texture = load(ip); ic.material = _pma
		ic.position = Vector2(sz.x * 0.5, sz.y * 0.42)
		ic.scale = Vector2(0.8, 0.8)
		box.add_child(ic)
	var nm := Label.new(); nm.text = Data.item_name(item_key)
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", Color(1, 0.96, 0.86))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.position = Vector2(4, sz.y - 62.0); nm.size = Vector2(sz.x - 8, 40)
	box.add_child(nm)
	var ct := Label.new(); ct.text = count_text
	ct.add_theme_font_size_override("font_size", 18)
	ct.add_theme_color_override("font_color", Color(1, 0.87, 0.5))
	ct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ct.position = Vector2(4, 6); ct.size = Vector2(sz.x - 8, 24)
	box.add_child(ct)

func _do_smelt(source_key: String, recipe: Dictionary, count: int) -> void:
	var have: Dictionary = {}
	for m in ItemSmelt.materials(recipe):
		have[String((m as Dictionary)["item"])] = UserDB.item_count(String((m as Dictionary)["item"]))
	if not ItemSmelt.affordable(recipe, count, have, UserDB.gold()):
		_toast("재료나 골드가 부족합니다"); return
	for m in ItemSmelt.materials(recipe):
		var md: Dictionary = m
		UserDB.use_item(String(md["item"]), int(md["count"]) * count)
	var cost := ItemSmelt.total_cost(recipe, count)
	if cost > 0 and not UserDB.spend("gold", cost):
		_toast("골드가 부족합니다"); return
	var target := String(recipe.get("target", ""))
	UserDB.add_item(target, count)
	_close_overlay()
	_inv_selected = target
	_open_inventory()
	_toast("아이템 %s를 %d개 얻었습니다." % [Data.item_name(target), count])

func _open_awaken_dex() -> void:
	_open_backdrop(0.55)
	var vis := _vis()
	var BW := clampf(vis.x - 80.0, 700.0, 1120.0)
	var BH := clampf(vis.y - 56.0, 520.0, 680.0)
	var cm := _man_common()
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	_overlay.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(340, 54); tbar.position = Vector2((BW - 340) * 0.5, 12); win.add_child(tbar)
	var title := Label.new(); title.text = "각성 드래곤"
	title.add_theme_font_size_override("font_size", 30); title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size = tbar.size; tbar.add_child(title)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 66, 14); xb.pressed.connect(_close_overlay); win.add_child(xb)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 92); scroll.size = Vector2(BW - 80, BH - 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = maxi(4, int((BW - 80) / 150.0))
	grid.add_theme_constant_override("h_separation", 10); grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for d in UserDB.dragons():
		grid.add_child(_awaken_cell(d, cm))

func _awaken_cell(d: Dictionary, cm: Dictionary) -> Control:
	var cell := Control.new(); cell.custom_minimum_size = Vector2(140, 158)
	var awk := bool(d.get("awakened", false))
	var ebg := _atlas_sprite("common_ui", "common_element_bg", cm, 0.66)
	if ebg: ebg.position = Vector2(70, 66); ebg.modulate = Color(1, 1, 1, 1) if awk else Color(0.6, 0.6, 0.65, 0.9); cell.add_child(ebg)
	var por := _portrait_sprite(int(d["id"]), Growth.portrait_stage(d), 0.62, int(d.get("skin", 0)))
	if por:
		por.position = Vector2(70, 62)
		if not awk:
			por.modulate = Color(0.45, 0.45, 0.5, 1)
		cell.add_child(por)
	if awk:
		var star := _atlas_sprite("common_ui", "common_btn_star", cm, 0.7)
		if star: star.position = Vector2(114, 30); cell.add_child(star)
	var nm := Label.new(); nm.text = "%s  Lv.%d" % [Icons.species_name(int(d["id"])), int(d["level"])]
	nm.add_theme_font_size_override("font_size", 14)
	nm.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05) if awk else Color(0.5, 0.44, 0.34))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; nm.position = Vector2(0, 126); nm.size = Vector2(140, 22)
	cell.add_child(nm)
	var uid := int(d["uid"])
	var b := Button.new(); b.flat = true; b.size = Vector2(140, 120); b.position = Vector2(0, 4)
	b.pressed.connect(func():
		UserDB.set_active(uid)
		_close_overlay(); _refresh())
	cell.add_child(b)
	return cell

func _open_skills() -> void:
	var a := _active()
	if a.is_empty(): return
	const BW := 650.0
	const BH := 480.0
	var overlay := CanvasLayer.new(); overlay.layer = 22; add_child(overlay)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: overlay.queue_free())
	overlay.add_child(dim)
	var vis := _vis()
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round(vis.x * 0.5 - BW * 0.5), round(vis.y * 0.5 - BH * 0.5))
	overlay.add_child(win)
	var t := Label.new(); t.text = "%s의 스킬" % Icons.species_name(int(a["id"]))
	t.add_theme_font_size_override("font_size", 24); t.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.position = Vector2(BW * 0.5 - 90, BH - 435 - 16); t.size = Vector2(180, 32); win.add_child(t)
	var info := TextureRect.new(); info.texture = load("res://assets/converted/common_ui/common_btn_info.tres")
	info.position = Vector2(BW * 0.5 + 52, BH - 435 - 12); win.add_child(info)
	var cb := TextureButton.new(); cb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	cb.position = Vector2(BW - 50 - 22, (BH - 430) - 22); win.add_child(cb)
	cb.pressed.connect(func(): overlay.queue_free())
	var box := NinePatchRect.new()
	box.texture = load("res://assets/converted/ninepatch_ui/9patch_scroll_box.tres")
	box.patch_margin_left = 65; box.patch_margin_top = 65; box.patch_margin_right = 31; box.patch_margin_bottom = 31
	box.size = Vector2(BW - 430, 420); box.position = Vector2(40, BH - 40 - 420); win.add_child(box)
	var scroll := ScrollContainer.new(); scroll.position = Vector2(10, 5); scroll.size = Vector2(BW - 430 - 20, 410); box.add_child(scroll)
	var vbox := VBoxContainer.new(); vbox.custom_minimum_size = Vector2(BW - 430 - 24, 0); scroll.add_child(vbox)
	var detail := Control.new(); detail.size = Vector2(350, 420); detail.position = Vector2(BW - 30 - 350, BH - 40 - 420); win.add_child(detail)
	var dlabel := Label.new(); dlabel.position = Vector2(16, 70); dlabel.size = Vector2(318, 300)
	dlabel.autowrap_mode = TextServer.AUTOWRAP_WORD; dlabel.add_theme_color_override("font_color", Color(0.92, 0.9, 0.82))
	dlabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; dlabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dlabel.text = "스킬을 선택하세요"; detail.add_child(dlabel)
	var cm := _man_common()
	var s2f := {"tri": "triangle", "sq": "square", "cir": "circle", "star": "star"}
	var sk := UserDB.dragon_skills(int(a["uid"]))
	if sk.is_empty():
		var em := Label.new(); em.text = "배운 스킬이 없습니다"
		em.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; em.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		em.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45))
		em.position = Vector2(10, 5); em.size = Vector2(BW - 430 - 20, 410); box.add_child(em)
		dlabel.text = ""
	for i in sk.size():
		var sid := int(sk[i].get("id", 0))
		var sdef: Dictionary = Data.skills.get(str(sid), {})
		var shp: String = s2f.get(String(sdef.get("slot", "")), "circle")
		var row := Button.new(); row.custom_minimum_size = Vector2(0, 42); row.flat = true
		var eq_at := Loadout.equipped_ids(a).find(sid)
		row.text = "  %s  %s Lv.%d%s" % [
			{"triangle": "△", "square": "□", "circle": "○", "star": "☆"}.get(shp, "○"),
			String(sdef.get("name", "스킬 %d" % sid)), int(sk[i].get("level", 1)),
			"   (%d번 칸)" % (eq_at + 1) if eq_at >= 0 else ""]
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
		var nm := String(sdef.get("name", "스킬"))
		var ef := String(sdef.get("effect_text", ""))
		var slv := int(sk[i].get("level", 1))
		row.pressed.connect(func():
			dlabel.text = "%s\n\n%s" % [nm,
				Loadout.skill_comment(sdef, ef if ef != "" else "(효과 정보 없음)")]
			_open_skill_info(sid, slv, sdef))
		vbox.add_child(row)

func _open_skill_info(sid: int, level: int, sdef: Dictionary) -> void:
	const BW := 620.0
	const BH := 466.0
	var vis := _vis()
	var ov := CanvasLayer.new(); ov.layer = 40; add_child(ov)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.5); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: ov.queue_free())
	ov.add_child(dim)
	var win := NinePatchRect.new(); win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5)); ov.add_child(win)
	var tbar := NinePatchRect.new(); tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(BW * 0.9, 52); tbar.position = Vector2((BW - BW * 0.9) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = String(sdef.get("name", "스킬")); tl.add_theme_font_size_override("font_size", 22)
	tl.add_theme_color_override("font_color", Color.WHITE); tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; tl.size = tbar.size; tbar.add_child(tl)
	var cb := TextureButton.new(); cb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	cb.position = Vector2(BW - 50 - 20, 14); win.add_child(cb); cb.pressed.connect(func(): ov.queue_free())
	var icx := BW * 0.5; var icy := 132.0
	var bl := load("res://assets/converted/common_ui/common_backlight3.tres")
	if bl:
		var blr := TextureRect.new(); blr.texture = bl; blr.position = Vector2(icx - 72, icy - 72); blr.size = Vector2(144, 144)
		blr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; win.add_child(blr)
	var icp := "res://assets/converted/skill/skill_%d.tres" % sid
	if ResourceLoader.exists(icp):
		var ic := TextureRect.new(); ic.texture = load(icp); ic.position = Vector2(icx - 48, icy - 48); ic.size = Vector2(96, 96)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; win.add_child(ic)
	var cmt := String(sdef.get("effect_text", ""))
	if cmt == "": cmt = String(sdef.get("notes", ""))
	cmt = Loadout.skill_comment(sdef, cmt)
	var cbox := ScrollContainer.new()
	cbox.position = Vector2(50, 212)
	cbox.size = Vector2(BW - 100, 124)
	cbox.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(cbox)
	var cm := Label.new()
	cm.autowrap_mode = TextServer.AUTOWRAP_WORD
	cm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cm.custom_minimum_size = Vector2(BW - 100 - 16, 0)
	cm.add_theme_font_size_override("font_size", 15)
	cm.add_theme_color_override("font_color", Color(0.25, 0.18, 0.1))
	cm.text = cmt
	cbox.add_child(cm)
	var maxlv := int(sdef.get("max_level", 5))
	var gy := 344.0
	var gbg := load("res://assets/converted/laboratory_ui/scene_laboratory_upgrade_gauge_bg.tres")
	if gbg:
		var g := NinePatchRect.new(); g.texture = gbg
		g.patch_margin_left = 8; g.patch_margin_right = 8; g.patch_margin_top = 6; g.patch_margin_bottom = 6
		g.size = Vector2(360, 28); g.position = Vector2((BW - 360) * 0.5, gy); win.add_child(g)
		var gbar := load("res://assets/converted/laboratory_ui/scene_laboratory_upgrade_gauge_bar.tres")
		if gbar:
			var frac := clampf(float(level) / float(maxi(1, maxlv)), 0.0, 1.0)
			var bar := NinePatchRect.new(); bar.texture = gbar
			bar.patch_margin_left = 6; bar.patch_margin_right = 6; bar.patch_margin_top = 4; bar.patch_margin_bottom = 4
			bar.size = Vector2(348.0 * frac, 20); bar.position = Vector2(6, 4); g.add_child(bar)
	var lv := Label.new(); lv.text = "Lv %d / %d" % [level, maxlv]; lv.add_theme_color_override("font_color", Color(0.3, 0.2, 0.1))
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lv.size = Vector2(BW, 24); lv.position = Vector2(0, gy + 34); win.add_child(lv)

const SLOT_BOX := 109.0
const SLOT_PITCH := 139.0
const SLOT_Y := 18.0
const SLOT_LABEL_Y := -12.0
const SLOT_X_ITEM := 770.0
const SLOT_X_GEM := 1000.0
const SLOT_X_AWAKEN := 1400.0
const SLOT_X_SKILL := 1520.0

func _refresh_slots() -> void:
	if _slot_layer == null or not is_instance_valid(_slot_layer):
		return
	for c in _slot_layer.get_children():
		c.queue_free()
		_slot_layer.remove_child(c)
	_build_slot_cluster(_slot_layer)

func _build_slot_cluster(bar: Control) -> void:
	var a := _active()
	_slot_label(bar, SLOT_X_ITEM, "아이템")
	_slot_label(bar, SLOT_X_GEM, "젬")
	_slot_label(bar, SLOT_X_SKILL, "스킬")
	_build_item_slot(bar, a)
	_build_gem_slots(bar, a)
	_build_skill_slots(bar, a)

func _slot_label(bar: Control, x: float, text: String) -> void:
	var lb := Label.new()
	lb.text = text
	lb.position = Vector2(x + 4, SLOT_LABEL_Y)
	lb.add_theme_font_size_override("font_size", 22)
	lb.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	lb.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.0, 0.9))
	lb.add_theme_constant_override("outline_size", 4)
	bar.add_child(_ignore_mouse(lb))
	
func _ignore_mouse(c: Control) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _slot_base(bar: Control, x: float, frame := "9patch_bg_common") -> NinePatchRect:
	var np := NinePatchRect.new()
	var p := "res://assets/converted/ninepatch_ui/%s.tres" % frame
	if ResourceLoader.exists(p):
		np.texture = load(p)
	np.patch_margin_left = 12; np.patch_margin_top = 12
	np.patch_margin_right = 10; np.patch_margin_bottom = 10
	np.size = Vector2(SLOT_BOX, SLOT_BOX)
	np.position = Vector2(x, SLOT_Y)
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(np)
	return np

const SLOT_UNIT := SLOT_BOX / 70.0

func _slot_icon(parent: Control, tex: Texture2D, scale: float) -> Sprite2D:
	if tex == null:
		return null
	var s := Sprite2D.new()
	s.texture = tex
	s.material = _pma
	s.scale = Vector2.ONE * scale * Design.ASSET_SCALE * SLOT_UNIT
	s.position = Vector2(SLOT_BOX * 0.5, SLOT_BOX * 0.5)
	parent.add_child(s)
	return s

func _slot_hit(bar: Control, x: float, cb: Callable, tip := "", guide := "") -> Button:
	var b := Button.new()
	b.flat = true
	b.position = Vector2(x, SLOT_Y)
	b.size = Vector2(SLOT_BOX, SLOT_BOX)
	if tip != "":
		b.tooltip_text = tip
	if cb.is_valid():
		b.pressed.connect(cb)
	bar.add_child(b)
	if guide != "":
		_guide_targets[guide] = b
	return b

func _build_item_slot(bar: Control, a: Dictionary) -> void:
	var base := _slot_base(bar, SLOT_X_ITEM)
	var eqf: Dictionary = a.get("equip", {})
	var unlocked = a.get("equip_slots", 1)
	var shown := 0
	for sid: String in Equipment.slot_ids(unlocked):
		var sd: Dictionary = Equipment.equipped(eqf, sid, Data.equipment)
		if sd.is_empty():
			continue
		if shown == 0:
			_slot_icon(base, Icons.equip_texture(sd), 0.42)
		shown += 1
	if shown > 1:
		var n := Label.new()
		n.text = "×%d" % shown
		n.add_theme_font_size_override("font_size", 20)
		n.add_theme_color_override("font_color", Color(1, 0.95, 0.75))
		n.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		n.add_theme_constant_override("outline_size", 4)
		n.position = Vector2(SLOT_BOX - 40, SLOT_BOX - 34)
		base.add_child(_ignore_mouse(n))
	_slot_hit(bar, SLOT_X_ITEM, _open_equipment, "장비 관리", "slot_item")

func _build_gem_slots(bar: Control, a: Dictionary) -> void:
	var gf: Dictionary = a.get("gems", {})
	var types := Gem.types(gf)
	var en := Gem.entries(gf)
	var frame_of := {"ATT": "9patch_gem_red_bg", "DEF": "9patch_gem_blue_bg",
		"HP": "9patch_gem_yellow_bg", "ALL": "9patch_gem_white_bg"}
	var kr: Dictionary = (Data.gems.get("slot_types", {}) as Dictionary).get("kr", {})
	for i in Gem.SLOTS:
		var x := SLOT_X_GEM + SLOT_PITCH * i
		var ty := String(types[i])
		var base := _slot_base(bar, x, String(frame_of.get(ty, "9patch_gem_white_bg")))
		var tip := "%d번 칸 (%s)" % [i + 1, String(kr.get(ty, ty))]
		if en[i] != null:
			var gname := String(en[i]["name"])
			var tier := int(en[i]["tier"])
			_slot_icon(base, Icons.gem_texture(
				String(Gem.gem_def(gname, Data.gems).get("code", "")), tier), 0.5)
			tip += "\n%s\n(클릭: 해제)" % _gem_line(gname, tier)
			var slot := i
			_slot_hit(bar, x, func(): _confirm_unequip_gem(slot), tip, "slot_gem" if i == 0 else "")
		else:
			tip += "\n비어 있음 (클릭: 가방 젬 탭)"
			_slot_hit(bar, x, _open_gem_tab, tip, "slot_gem" if i == 0 else "")

func _confirm_unequip_gem(slot: int) -> void:
	var a := _active()
	if a.is_empty(): return
	var uid := int(a["uid"])
	var en := Gem.entries(a.get("gems", {}))
	if en[slot] == null: return
	var nm := _gem_line(String(en[slot]["name"]), int(en[slot]["tier"]))
	_open_popup_type("젬 해제", "%s\n\n이 칸의 젬을 해제하시겠습니까?\n(해제한 젬은 가방으로 돌아갑니다)" % nm,
		func():
			_unequip_gem(uid, slot)
			_refresh_stats(); _refresh()
			_toast("젬을 해제했습니다"))

func _build_skill_slots(bar: Control, a: Dictionary) -> void:
	var level := int(a.get("level", 1))
	var uid := int(a.get("uid", 0))
	var stypes := Loadout.slot_types(a)
	var equipped := Loadout.equipped_ids(a)
	var bg_of := {"tri": "common_skill_triangle_bg", "sq": "common_skill_square_bg",
		"cir": "common_skill_circle_bg", "star": "common_skill_star_bg"}
	var mark_of := {"tri": "common_skill_triangle", "sq": "common_skill_square",
		"cir": "common_skill_circle", "star": "common_skill_star"}
	var fx_slot := _skill_fx_slot
	_skill_fx_slot = -1
	for i in Loadout.SKILL_SLOTS:
		var x := SLOT_X_SKILL + SLOT_PITCH * i
		var ty := String(stypes[i])
		var base := _slot_base(bar, x, "")
		_slot_icon(base, _common_tex(String(bg_of.get(ty, "common_skill_star_bg"))), 1.0)
		var tip := "%d번 칸 (%s)" % [i + 1, String(_SKILL_SLOT_MARK.get(ty, "?"))]
		if not Loadout.slot_unlocked(i, level):
			_slot_icon(base, _common_tex("common_lock"), 0.8)
			tip += "\nLv.%d 에 해금" % int(Loadout.SLOT_UNLOCK_LEVEL[i])
			_slot_hit(bar, x, func(): _toast("Lv.%d 부터 열립니다" % int(Loadout.SLOT_UNLOCK_LEVEL[i])),
				tip, "slot_skill" if i == 0 else "")
			continue
		if int(equipped[i]) > 0:
			var sid := int(equipped[i])
			var sdef: Dictionary = Data.skills.get(str(sid), {})
			var matched := Loadout.slot_matches(ty, sdef)
			var mark_key := String(mark_of.get(ty, "common_skill_circle"))
			var mark: Sprite2D = null
			if matched:
				mark = _slot_icon(base, _common_tex(mark_key), 1.0)
			var light: Sprite2D = null
			if fx_slot == i and mark != null:
				light = _slot_icon(base, _common_tex(mark_key + "_light"), 1.0)
			var icon := _slot_icon(base, _skill_tex(sid), 0.6)
			if fx_slot == i:
				_skill_equip_fx(mark, light, icon, matched,
					String(sdef.get("slot", "")) == ty)
			var ent := Loadout.equipped_entry(a, i)
			tip += "\n%s Lv.%d" % [String(sdef.get("name", "스킬")), int(ent.get("level", 1))]
			if Loadout.slot_matches(ty, sdef):
				tip += "  (타입 일치 · %s)" % Loadout.slot_match_label(sdef, Data.combat)
			tip += "\n(클릭: 스킬 교체)"
		else:
			tip += "\n비어 있음 (클릭: 장착)"
		var slot3 := i
		_slot_hit(bar, x, func(): _open_skill_select(slot3), tip, "slot_skill" if i == 0 else "")
	if bool(a.get("awakened", false)):
		var base2 := _slot_base(bar, SLOT_X_AWAKEN, "")
		_slot_icon(base2, _common_tex("common_skill_evolution_bg"), 1.0)
		var aw := int(a.get("awaken_skill", 0))
		var icon := Data.awaken_skill_icon(aw) if aw > 0 else 0
		if icon > 0:
			var p := "res://assets/converted/skill_evolution/skill_evolution_%d.tres" % icon
			if ResourceLoader.exists(p):
				_slot_icon(base2, load(p), 0.6)
		var tip_aw := "각성 스킬"
		var row_aw: Dictionary = Data.skill_awaken_for(aw) if aw > 0 else {}
		if not row_aw.is_empty():
			tip_aw += "\n%s" % String(row_aw.get("name", ""))
		var aw_hit := _slot_hit(bar, SLOT_X_AWAKEN, Callable(), tip_aw)
		aw_hit.pressed.connect(func(): _open_awaken_skill(aw_hit))

func _skill_equip_fx(mark: Sprite2D, light: Sprite2D, icon: Sprite2D,
		matched: bool, exact: bool) -> void:
	if matched and mark != null:
		mark.modulate.a = 0.0
		var tm := mark.create_tween()
		tm.tween_interval(0.4)
		tm.tween_callback(func(): Bgm.sfx("effect_skill_ok"))
		tm.tween_property(mark, "modulate:a", 1.0, 0.1)
		if light != null:
			light.modulate.a = 0.0
			var tl := light.create_tween()
			tl.tween_interval(0.4)
			tl.tween_property(light, "modulate:a", 1.0, 1.25)
			tl.tween_interval(0.5)
			tl.tween_property(light, "modulate:a", 0.0, 1.25)
	else:
		Bgm.sfx("effect_skill_ok2")
	if exact and icon != null:
		var to: Vector2 = icon.scale
		icon.scale = Vector2.ZERO
		var ti := icon.create_tween()
		ti.tween_interval(0.1)
		ti.tween_property(icon, "scale", to, 0.3)

func _common_tex(key: String) -> Texture2D:
	if key == "":
		return null
	var p := "res://assets/converted/common_ui/%s.tres" % key
	return load(p) if ResourceLoader.exists(p) else null

func _skill_tex(sid: int) -> Texture2D:
	var p := "res://assets/converted/skill/skill_%d.tres" % sid
	return load(p) if ResourceLoader.exists(p) else null

func _open_skill_select(slot: int) -> void:
	var a := _active()
	if a.is_empty(): return
	var before := int(Loadout.equipped_ids(a)[slot]) if slot < Loadout.SKILL_SLOTS else 0
	var p := SkillLoadoutWindow.open(self, int(a["uid"]), slot, func(): _refresh(); _refresh_stats())
	p.closed.connect(func():
		_refresh(); _refresh_stats()
		var now := _active()
		if slot < Loadout.SKILL_SLOTS and not now.is_empty():
			var eq := int(Loadout.equipped_ids(now)[slot])
			if eq > 0 and eq != before:
				_skill_fx_slot = slot
				_refresh_slots())

func _open_awaken_skill(anchor: Control) -> void:
	var a := _active()
	if a.is_empty(): return
	var no := int(a.get("awaken_skill", 0))
	var row: Dictionary = Data.skill_awaken_for(no) if no > 0 else {}
	if row.is_empty():
		_toast("각성 스킬 정보가 아직 없습니다 (docs/input/review/skill_awaken_sheet.md)")
		return
	DragonAwakenSkillInfoPopup.open(self, anchor, no)

func _build_menu() -> void:
	var vis := _vis()
	_right_wall = Control.new()
	_right_wall.position = Vector2.ZERO
	_right_wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_right_wall)
	var items := [
		{"icon": "book", "bg": "book_bg", "cy": 530.0, "dx": 0.0, "cb": _open_dex},
		{"icon": "skin", "bg": "skin_bg", "cy": 420.0, "dx": 6.0, "cb": _open_skin},
		{"icon": "bag", "bg": "bag_bg", "cy": 310.0, "dx": 0.0, "cb": _open_inventory},
		{"icon": "card", "bg": "card_bg", "cy": 200.0, "dx": 0.0, "cb": _open_cards},
	]
	for it in items:
		_menu_button(it, vis.x)
	var handle := Button.new()
	handle.text = "▶"
	handle.size = Vector2(28, 56); handle.position = Vector2(vis.x - 30.0, vis.y * 0.5 - 28.0)
	handle.add_theme_font_size_override("font_size", 18)
	handle.pressed.connect(_toggle_side_walls)
	add_child(handle)
	_wall_handle = handle
	var tb := Button.new()
	tb.text = "칭호"
	tb.size = Vector2(64, 30); tb.position = Vector2(vis.x - 100.0, 16.0)
	tb.add_theme_font_size_override("font_size", 15)
	tb.pressed.connect(_open_titles)
	add_child(tb)

var _left_wall: Control
var _right_wall: Control
var _wall_handle: Button
var _walls_open := true

const WALL_SHIFT_L := 110.0
const WALL_SHIFT_R := 100.0
const WALL_MOVE_TIME := 0.3

func _toggle_side_walls() -> void:
	_walls_open = not _walls_open
	Bgm.sfx("effect_stone_roll")
	_apply_wall_shift(true)
	_wall_rumble()
	if is_instance_valid(_wall_handle):
		_wall_handle.text = "▶" if _walls_open else "◀"

func _apply_wall_shift(animate: bool) -> void:
	var dl := 0.0 if _walls_open else -WALL_SHIFT_L
	var dr := 0.0 if _walls_open else WALL_SHIFT_R
	_shift_to(_wall_left_spr, _wall_left_x + dl, animate)
	_shift_to(_left_wall, dl, animate)
	_shift_to(_wall_right_spr, _wall_right_x + dr, animate)
	_shift_to(_right_wall, dr, animate)

func _shift_to(n, x: float, animate: bool) -> void:
	if not is_instance_valid(n): return
	if animate:
		n.create_tween().tween_property(n, "position:x", x, WALL_MOVE_TIME)
	else:
		n.position.x = x

func _wall_rumble() -> void:
	var base := position.y
	var t := create_tween()
	for dy in [-2.0, 2.0, -2.0, 2.0, -2.0, 0.0]:
		t.tween_property(self, "position:y", base + dy, 0.05)

var _guide_targets: Dictionary = {}
func guide_target(id: String) -> Control:
	var n = _guide_targets.get(id)
	return n if is_instance_valid(n) else null

func has_modal() -> bool:
	if is_instance_valid(_overlay) or is_instance_valid(_equip_pop):
		return true
	for c in get_children():
		if c is CanvasLayer:
			var cl := c as CanvasLayer
			if cl.layer >= 20 and cl.visible and cl.name != "ToastLayer":
				return true
		elif c is EquipSlotsPanel or c is SkillLoadoutWindow:
			return true
	return false

func _menu_button(it: Dictionary, screen_w: float) -> void:
	const SCALE := 1.2
	var icon: String = it["icon"]
	var bgw: float = float(_manifest.get("scene_cave_%s" % it["bg"], {}).get("w", 75)) * SCALE
	var cx := screen_w - 12.0 - bgw * 0.5 + float(it["dx"])
	var cy := 692.0 - float(it["cy"])
	var bg := _ui_sprite("scene_cave_%s" % it["bg"], SCALE)
	bg.position = Vector2(cx, cy)
	_right_wall.add_child(bg)
	var spr := _ui_sprite("scene_cave_%s" % icon, SCALE)
	spr.position = Vector2(cx, cy)
	_right_wall.add_child(spr)
	var b := Button.new()
	b.flat = true
	b.size = Vector2(bgw, bgw)
	b.position = Vector2(cx - bgw * 0.5, cy - bgw * 0.5)
	b.pressed.connect(it["cb"])
	_right_wall.add_child(b)
	_guide_targets[icon] = b

func _build_topbar() -> void:
	var vis := _vis()
	var x := TextureButton.new()
	var xt := "res://assets/converted/common_ui/common_close_btn.tres"
	if ResourceLoader.exists(xt):
		x.texture_normal = load(xt)
		x.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
		x.position = Vector2(vis.x - 24.0 - 48.0 * Design.ASSET_SCALE, 16.0)
	else:
		x.position = Vector2(vis.x - 44.0, 8.0)
	x.pressed.connect(func(): Scenes.goto("worldmap", {"region": "yutakan"}))
	add_child(x)

func _refresh() -> void:
	var skin_idx: int = UserDB.get_skin("cave_skin") % SKIN_COUNT
	_bg.texture = load(BG % (skin_idx + 1))
	_build_walls()
	_refresh_dragon()
	_refresh_quick()
	_refresh_list()
	_refresh_stats()
	_refresh_slots()

func _refresh_dragon() -> void:
	for ch in _stage.get_children():
		ch.queue_free()
	var si: int = UserDB.get_skin("stand_skin") % STAND_COUNT
	var info = _stand_manifest.get("stand_stand%d" % (si + 1), {})
	var w: float = maxf(1.0, float(info.get("w", 305)))
	var h: float = maxf(1.0, float(info.get("h", 120)))
	var sc := PED_WIDTH / w
	var ped := _atlas_sprite("stand_ui", "stand_stand%d" % (si + 1), _stand_manifest, sc)
	ped.position = Vector2(0, PED_BOTTOM - h * sc / 2.0)
	_stage.add_child(ped)
	var dust := CPUParticles2D.new()
	dust.amount = 12
	dust.lifetime = 3.2
	dust.position = Vector2(0, 210)
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(120, 8)
	dust.direction = Vector2(0, -1)
	dust.spread = 12.0
	dust.gravity = Vector2(0, -10)
	dust.initial_velocity_min = 10.0
	dust.initial_velocity_max = 26.0
	dust.scale_amount_min = 2.0
	dust.scale_amount_max = 5.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 0.97, 0.82, 0.55))
	grad.set_color(1, Color(1, 0.97, 0.82, 0.0))
	dust.color_ramp = grad
	_stage.add_child(dust)
	var a := _active()
	if is_instance_valid(_dragon_btn):
		_dragon_btn.visible = not (not a.is_empty() and UserDB.is_egg(a))
	if a.is_empty():
		_build_stamina_gauge()
		return
	if UserDB.is_egg(a):
		_build_egg_on_stand(a)
		return
	_build_stamina_gauge()
	var awakened := bool(a.get("awakened", false))
	var _el := Icons.element_of(a)
	var art := Icons.art_id_of(a)
	_apply_aura(_el if not awakened and Growth.is_aura_adult(int(a["level"])) else "")
	var stage_name := Growth.spine_stage(a)
	if not awakened and stage_name == "adult" and Growth.is_aura_adult(int(a["level"])):
		stage_name = _aura_spine_stage(art)
	var path := Icons.spine_scene(art, stage_name)
	if awakened and path == "":
		stage_name = Growth.stage_for_level(int(a["level"]))
		path = Icons.spine_scene(art, stage_name)
	if path != "":
		var holder := Node2D.new()
		holder.scale = Vector2(PED_DRAGON_SCALE, PED_DRAGON_SCALE)
		holder.position = Vector2(0, PED_DRAGON_Y)
		_stage.add_child(holder)
		var inst = load(path).instantiate()
		holder.add_child(inst)
		_dragon_ap = inst.get_node_or_null("AnimationPlayer")
		if _dragon_ap:
			if _dragon_ap.has_animation("love"):
				_dragon_ap.get_animation("love").loop_mode = Animation.LOOP_NONE
			_dragon_ap.animation_finished.connect(_on_dragon_anim_finished)
			if _dragon_ap.has_animation("wait"):
				_dragon_ap.play("wait")
	else:
		var por := _portrait_sprite(art, stage_name, 2.6, int(a.get("skin", 0)))
		if por:
			por.position = Vector2(0, -30)
			_stage.add_child(por)
		push_warning("[cave] dragon %d(%s) 스파인 씬 미빌드 → 초상 폴백. `spine_batch %d`+build_all 필요"
			% [art, stage_name, art])

var _name_balloon: Control
func _refresh_name_balloon() -> void:
	if is_instance_valid(_name_balloon): _name_balloon.queue_free()
	if not bool(UserDB.get_pmeta("name_balloon", true)): return
	var a := _active()
	if a.is_empty(): return
	var nick := String(a.get("nick", ""))
	var species := Icons.species_name(int(a["id"]))
	var txt := nick if nick != "" else species
	var vis := _vis()
	var font := ThemeDB.fallback_font
	var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var bw: float = maxf(96.0, tw + 56.0)
	var bh := 34.0
	var by := vis.y * 0.11
	_name_balloon = Control.new()
	_name_balloon.position = Vector2(vis.x * 0.5 - bw * 0.5, by)
	_name_balloon.size = Vector2(bw, bh + 12)
	add_child(_name_balloon)
	var panel := Panel.new()
	panel.size = Vector2(bw, bh)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.98, 0.9, 0.96)
	sb.set_border_width_all(2); sb.border_color = Color(0.85, 0.6, 0.25)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.28); sb.shadow_size = 4
	panel.add_theme_stylebox_override("panel", sb)
	_name_balloon.add_child(panel)
	var tail := Polygon2D.new()
	tail.polygon = PackedVector2Array([Vector2(bw * 0.5 - 9, bh - 1), Vector2(bw * 0.5 + 9, bh - 1), Vector2(bw * 0.5, bh + 11)])
	tail.color = Color(1, 0.98, 0.9, 0.96)
	_name_balloon.add_child(tail)
	var lbl := Label.new(); lbl.text = txt
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.16, 0.12, 0.06))
	lbl.size = Vector2(bw, bh); lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(lbl)
	var t := _name_balloon.create_tween().set_loops()
	t.tween_property(_name_balloon, "position:y", by - 6.0, 1.4).set_trans(Tween.TRANS_SINE)
	t.tween_property(_name_balloon, "position:y", by, 1.4).set_trans(Tween.TRANS_SINE)

const AURAS := {
	"": {"name": "없음", "col": Color(1, 1, 1)},
	"fire": {"name": "불꽃", "col": Color(1.0, 0.45, 0.2)},
	"holy": {"name": "신성", "col": Color(1.0, 0.9, 0.45)},
	"aqua": {"name": "바다", "col": Color(0.35, 0.7, 1.0)},
	"dark": {"name": "암흑", "col": Color(0.7, 0.4, 1.0)},
	"wind": {"name": "바람", "col": Color(0.5, 1.0, 0.6)},
}
var _aura_node: Node2D
func _apply_aura(key: String) -> void:
	if is_instance_valid(_aura_node): _aura_node.queue_free()
	if key == "" or not AURAS.has(key): return
	var frames: Array = []
	for i in range(1, 10):
		var fn := "dragon_aura_%s_aura%02d" % [key, i]
		var t := load("res://assets/converted/aura_ui/%s.tres" % fn) if ResourceLoader.exists("res://assets/converted/aura_ui/%s.tres" % fn) else null
		if t:
			frames.append({"tex": t, "rot": 0.0})
	if frames.is_empty(): return
	var vis := _vis()
	_aura_node = Node2D.new(); _aura_node.z_index = 1
	_aura_node.position = Vector2(vis.x * 0.5, vis.y * 0.5 + 30.0)
	add_child(_aura_node)
	var spr := Sprite2D.new()
	var addmat := CanvasItemMaterial.new(); addmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	spr.material = addmat; spr.scale = Vector2(1.5, 1.5)
	_aura_node.add_child(spr)
	var tw := spr.create_tween().set_loops()
	for fr in frames:
		var ftex: Texture2D = fr["tex"]; var frot: float = fr["rot"]
		tw.tween_callback(func(): spr.texture = ftex; spr.rotation = frot)
		tw.tween_interval(0.1)

var _aura_man: Dictionary = {}
func _aura_manifest() -> Dictionary:
	if _aura_man.is_empty():
		var f := FileAccess.open("res://assets/converted/aura_ui/_manifest.json", FileAccess.READ)
		if f: _aura_man = JSON.parse_string(f.get_as_text())
	return _aura_man

func _on_dragon_clicked() -> void:
	if is_instance_valid(_dragon_ap) and _dragon_ap.has_animation("love"):
		_dragon_ap.play("love")
		var a := _active()
		if not a.is_empty() and not UserDB.is_egg(a):
			_play_dragon_voice_delayed(int(a["id"]), int(a.get("level", 1)))

func _on_dragon_anim_finished(anim: StringName) -> void:
	if anim != "wait" and is_instance_valid(_dragon_ap) and _dragon_ap.has_animation("wait"):
		_dragon_ap.play("wait")

var _quick: Control

func _build_quick_panel() -> void:
	_quick = Control.new()
	_quick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_quick)

func _refresh_quick() -> void:
	if _quick == null: return
	for ch in _quick.get_children(): ch.queue_free()
	var a := _active()
	if a.is_empty(): return
	var uid := int(a["uid"])
	var vis := _vis()
	var cx := vis.x / 2.0 - 176.0
	var cy := vis.y / 2.0 + 78.0
	_quick_toggle(cx - 28.0, cy, "safety", UserDB.is_locked(uid), _on_toggle_safety)
	_quick_toggle(cx + 32.0, cy, "favorite", UserDB.is_favorite(uid), _on_toggle_favorite)

func _quick_toggle(cx: float, cy: float, kind: String, on: bool, cb: Callable) -> void:
	var frame := "scene_cave_bt_%s_%s" % [kind, "on" if on else "off"]
	var spr := _atlas_sprite("cave_ui", frame, _manifest, 1.15)
	spr.position = Vector2(cx, cy)
	if not on: spr.modulate = Color(1, 1, 1, 0.72)
	_quick.add_child(spr)
	var b := Button.new()
	b.flat = true
	b.size = Vector2(52, 54)
	b.position = Vector2(cx - 26.0, cy - 27.0)
	b.pressed.connect(cb)
	_quick.add_child(b)

func _use_food(key: String) -> void:
	var a := _active()
	if a.is_empty() or UserDB.item_count(key) <= 0: return
	var defs: Dictionary = Data.item_effects
	var drink := ItemEffect.drink_of(defs, key)
	if not drink.is_empty():
		var uid := int(a["uid"])
		var cur: Dictionary = UserDB.get_dragon(uid).get("drink_buffs", {})
		UserDB.set_dragon_field(uid, "drink_buffs", ItemEffect.apply_drink(cur, drink))
		UserDB.add_item(key, -1)
		Bgm.sfx("effect_button")
		const KR := {"att": "공격력", "def": "방어력", "hp": "생명력",
			"crit": "크리티컬", "dodge": "회피", "block": "방어확률"}
		_toast("%s +%d%%  (%d턴)" % [KR.get(String(drink["stat"]), String(drink["stat"])),
			int(drink["pct"]), int(drink["turns"])])
		_refresh_stats(); _inventory_refresh_grid(); _inventory_refresh_detail()
		return
	if key.begins_with("heal_potion"):
		var uid2 := int(a["uid"])
		var lv := int(a.get("level", 1))
		if not ItemEffect.heal_usable(defs, key, lv):
			_toast("이 드래곤 레벨(%d)에는 쓸 수 없는 물약입니다" % lv)
			return
		var stats := Growth.compute_stats(Data.get_dragon(int(a["id"])), Data.stat_table, lv,
			a.get("stat_bonus", {}))
		var hp_max := int(stats.get("hp", 1))
		var hp_now := int(a.get("hp", hp_max))
		var amt := ItemEffect.heal_amount(defs, hp_now, hp_max)
		if amt <= 0:
			_toast("이미 체력이 가득 찼습니다")
			return
		UserDB.set_dragon_field(uid2, "hp", mini(hp_max, hp_now + amt))
		UserDB.add_item(key, -1)
		Bgm.sfx("effect_button")
		_toast("체력 +%d 회복" % amt)
		_refresh_stats(); _inventory_refresh_grid(); _inventory_refresh_detail()
		return
	var idef: Dictionary = Data.get_item(key)
	var dragon_el := String(Data.get_dragon(int(a["id"])).get("element", ""))
	if ItemEffect.is_feed(idef) and not ItemEffect.feed_matches(idef, dragon_el):
		_toast("%s 속성 드래곤은 이 먹이를 먹지 않습니다" % _ELEM_KR.get(dragon_el, dragon_el))
		return
	var exp := 30
	if key.length() > 0 and key[key.length() - 1].is_valid_int():
		exp = 30 * int(key[key.length() - 1])
	UserDB.add_item(key, -1)
	var ev := UserDB.grant_exp(int(a["uid"]), exp)
	UserDB.bump_quest("feeds")
	var fed := ItemEffect.is_feed(idef)
	if fed:
		UserDB.set_dragon_field(int(a["uid"]), "food",
			ItemEffect.food_after_feed(defs, idef, key, dragon_el,
				int(a.get("food", ItemEffect.food_max(defs)))))
	if is_instance_valid(_dragon_ap) and _dragon_ap.has_animation("love"):
		_dragon_ap.play("love")
	_toast("드래곤이 맛있게 먹이를 먹었습니다." if fed else "냠냠!  +EXP %d" % exp)
	_refresh_quick()
	_refresh_stamina()
	_refresh_stats()
	_inventory_refresh_grid(); _inventory_refresh_detail()
	if int(ev.get("levels_gained", 0)) > 0:
		_open_levelup()

func _skills_learned_since(uid: int, before_size: int) -> Array:
	var pool: Array = UserDB.dragon_skills(uid)
	var out: Array = []
	for i in range(before_size, pool.size()):
		var sid := int((pool[i] as Dictionary).get("id", 0))
		out.append(String(Data.skills.get(str(sid), {}).get("name", "스킬")))
	return out

var _toast_lbl: Label

func _toast(text: String) -> void:
	Toast.show(self, text)

func _on_toggle_safety() -> void:
	var a := _active()
	if a.is_empty(): return
	UserDB.toggle_locked(int(a["uid"]))
	_refresh_quick()
	_refresh_list()

func _on_toggle_favorite() -> void:
	var a := _active()
	if a.is_empty(): return
	UserDB.toggle_favorite(int(a["uid"]))
	_refresh_quick()
	_refresh_list()

func _portrait_sprite(id: int, stage: String, scale := 1.0, skin := 0) -> Sprite2D:
	var dir := "portrait_%d" % id
	if not _portrait_manifests.has(dir):
		var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
		_portrait_manifests[dir] = JSON.parse_string(f.get_as_text()) if f else {}
	var frame := "dragon_dragon_%d_box_%s" % [id, stage]
	if skin > 0:
		var sframe := "%s_skin%d" % [frame, skin]
		if _portrait_manifests[dir].has(sframe): frame = sframe
	return _atlas_sprite(dir, frame, _portrait_manifests[dir], scale)

func _dragon_skin_count(id: int) -> int:
	var n := 0
	for s in range(1, 4):
		if ResourceLoader.exists("res://assets/converted/portrait_%d/dragon_dragon_%d_box_adult_skin%d.tres" % [id, id, s]):
			n = s
		else:
			break
	return n

func _refresh_list() -> void:
	for ch in _list_box.get_children():
		ch.queue_free()
	var owned: Array = UserDB.dragons()
	var active := UserDB.active_uid()
	for d in owned:
		_list_box.add_child(_dragon_slot(int(d["id"]), int(d["level"]), int(d["uid"]), int(d["uid"]) == active))
	var locked := maxi(0, mini(_NEST_SLOTS, owned.size() + 2) - owned.size())
	for i in locked:
		_list_box.add_child(_locked_slot())

const _NEST_SLOTS := 12
func _locked_slot() -> Control:
	var S := Design.ASSET_SCALE
	var cm := _man_common()
	var parts := _slot_cell()
	var slot: Control = parts[0]
	var cell: Node2D = parts[1]
	var bg := _atlas_sprite("common_ui", "common_dragon_bg2", cm, S)
	bg.modulate = Color(1, 1, 1, 225.0 / 255.0)
	cell.add_child(bg)
	var lk := _atlas_sprite("common_ui", "common_lock", cm, S)
	lk.position = Vector2(0, -5.0)
	lk.modulate = Color(1, 1, 1, 125.0 / 255.0)
	cell.add_child(lk)
	var cov := _atlas_sprite("common_ui", "common_dragon_cover2", cm, S)
	cov.modulate = Color(1, 1, 1, 125.0 / 255.0)
	cell.add_child(cov)
	return slot

const _SLOT_SCALE := 0.95
const _SLOT_PAD_X := 2.5
const _SLOT_BOX := 1.05

func _slot_side() -> float:
	return float(_man_common().get("common_dragon_bg2", {}).get("w", 81)) * Design.ASSET_SCALE

func _slot_cell() -> Array:
	var box := _slot_side() * _SLOT_BOX
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(LIST_W, box)
	var cell := Node2D.new()
	cell.position = Vector2(_SLOT_PAD_X + box * 0.5, box * 0.5)
	cell.scale = Vector2(_SLOT_SCALE, _SLOT_SCALE)
	slot.add_child(cell)
	return [slot, cell, box]

func _dragon_slot(id: int, level: int, uid: int, is_active: bool) -> Control:
	var S := Design.ASSET_SCALE
	var cm := _man_common()
	var parts := _slot_cell()
	var slot: Control = parts[0]
	var cell: Node2D = parts[1]
	var box: float = parts[2]
	var half := _slot_side() * 0.5
	cell.add_child(_atlas_sprite("common_ui",
		"common_dragon_bg1" if is_active else "common_dragon_bg2", cm, S))
	var slot_dragon := UserDB.get_dragon(uid)
	var por := _portrait_sprite(Icons.art_id_of(slot_dragon) if not slot_dragon.is_empty() else id,
		Growth.portrait_stage(slot_dragon) if not slot_dragon.is_empty() else Growth.stage_for_level(level),
		0.9 * S)
	por.position = Vector2(0, -7.5)
	cell.add_child(por)
	cell.add_child(_atlas_sprite("common_ui",
		"common_dragon_cover1" if is_active else "common_dragon_cover2", cm, S))
	if UserDB.is_locked(uid):
		var lk := _atlas_sprite("cave_ui", "scene_cave_bt_safety_on", _manifest, 0.5 * S)
		lk.position = Vector2(-half + 16.0, -half + 16.0)
		cell.add_child(lk)
	if UserDB.is_favorite(uid):
		var fv := _atlas_sprite("cave_ui", "scene_cave_bt_favorite_on", _manifest, 0.5 * S)
		fv.position = Vector2(half - 16.0, -half + 16.0)
		cell.add_child(fv)
	var lv := Label.new()
	lv.text = "레벨 %d" % level
	_lvup_bm_style(lv, int(round(19.0 * S * 0.8)), Color.WHITE, "font_subtitle")
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lv.size = Vector2(box, 26.0)
	lv.position = Vector2(-box * 0.5, box * 0.5 - 5.0 - 26.0)
	cell.add_child(lv)
	var b := Button.new()
	b.flat = true
	b.size = Vector2(LIST_W, box)
	b.pressed.connect(func():
		UserDB.set_active(uid)
		_refresh())
	slot.add_child(b)
	return slot

const EGG_LAYER_SIZE := Vector2(350, 300)
const EGG_STAND_DY := 80.0
const EGG_PLATE_DY := 137.0
const EGG_PLATE_SIZE := Vector2(180, 45)
const EGG_DIA_COST := 300
const EGG_NUDGE := Vector2(5.0, 20.0)
const EGG_BEAT_SFX := "effect_egg"
const EGG_BEAT_DELAYS := [0.05, 0.35, 0.29, 0.35, 0.25, 0.25, 0.22, 0.21, 0.12, 0.15, 0.11]

var _egg_layer: Node2D = null
var _egg_plate: Control = null
var _egg_time_label: Label = null
var _egg_dia_btn: Control = null
var _egg_body: Node2D = null
var _egg_ghosts: Array[Node2D] = []
var _egg_uid := 0
var _egg_done := false
var _egg_busy := false
var _egg_action_tw: Tween = null
var _dragon_btn: Button = null
var _egg_heartbeat: AudioStreamPlayer = null

func _egg_pt(ox: float, oy: float) -> Vector2:
	return Vector2(ox - EGG_LAYER_SIZE.x * 0.5, -oy)

func _egg_sprite(did: int, org_scale: float) -> Node2D:
	var S := Design.ASSET_SCALE
	var pdir := "portrait_%d" % did
	var key := _dex_stage_frame(did, "egg")
	var info: Dictionary = AtlasUI.manifest(pdir).get(key, {})
	var src: Array = info.get("src", [float(info.get("w", 0)), float(info.get("h", 0))])
	var holder := AtlasUI.spr_cocos(pdir, key, org_scale, Vector2(0.5, 0))
	if holder == null:
		holder = Node2D.new()
	holder.position = _egg_pt(EGG_LAYER_SIZE.x * 0.5, EGG_LAYER_SIZE.y * 0.5 - float(src[1]) * S)
	holder.set_meta("home", holder.position)
	return holder

func _build_egg_on_stand(a: Dictionary) -> void:
	var did := Icons.art_id_of(a)
	var blessed := bool(a.get("egg_blessed", false))
	_egg_uid = int(a["uid"])
	_egg_done = false
	_egg_busy = false
	_egg_ghosts.clear()

	_egg_layer = Node2D.new()
	_egg_layer.position = Vector2(EGG_NUDGE.x, EGG_STAND_DY + 8.0 + EGG_NUDGE.y) / S1080
	_egg_layer.scale = Vector2(1.0 / S1080, 1.0 / S1080)
	_stage.add_child(_egg_layer)

	var nest_pos := _egg_pt(175, EGG_LAYER_SIZE.y * 0.5 - 35.0)
	var sh := AtlasUI.spr_cocos("common_ui", "common_shadow", 1.75)
	if sh:
		sh.position = _egg_pt(175, EGG_LAYER_SIZE.y * 0.5 - 135.0)
		_egg_layer.add_child(sh)
	var nest_back := AtlasUI.spr_cocos("common_ui",
		"common_nest_holy2" if blessed else "common_nest2", 1.5)
	if nest_back:
		nest_back.position = nest_pos
		_egg_layer.add_child(nest_back)
	for g in [1.6, 1.7]:
		var ghost := _egg_sprite(did, g)
		ghost.modulate.a = 0.0
		_egg_layer.add_child(ghost)
		_egg_ghosts.append(ghost)
	_egg_body = _egg_sprite(did, 1.5)
	_egg_layer.add_child(_egg_body)
	if int(a.get("egg_enhance", 0)) > 0:
		_egg_enhance_aura()
	var nest_front := AtlasUI.spr_cocos("common_ui",
		"common_nest_holy1" if blessed else "common_nest1", 1.5)
	if nest_front:
		nest_front.position = nest_pos
		_egg_layer.add_child(nest_front)
		if blessed:
			var dust := CocosParticle.spawn(nest_front, "cave_dust", Vector2.ZERO, -2)
			if dust: dust.one_shot = false

	_egg_wait_anim()
	_build_egg_plate()
	_egg_heartbeat = Bgm.loop_sfx("effect_heart_beat")
	if _egg_heartbeat: _egg_layer.add_child(_egg_heartbeat)
	_tick_egg()

func _egg_wait_anim() -> void:
	if is_instance_valid(_egg_body):
		var t := _egg_body.create_tween().set_loops()
		t.tween_property(_egg_body, "scale", Vector2(1.7, 1.7), 2.0)
		t.tween_property(_egg_body, "scale", Vector2(1.5, 1.5), 1.5)
	var spec := [[0.9, 1.6, 0.6], [1.4, 1.7, 0.1]]
	for i in _egg_ghosts.size():
		var g := _egg_ghosts[i]
		var s: Array = spec[i]
		var t2 := g.create_tween().set_loops()
		t2.tween_interval(float(s[0]))
		t2.tween_property(g, "modulate:a", 100.0 / 255.0, 0.1)
		t2.tween_property(g, "scale", Vector2(2.3, 2.3), 0.9)
		t2.parallel().tween_property(g, "modulate:a", 0.0, 0.9)
		t2.tween_property(g, "scale", Vector2(float(s[1]), float(s[1])), float(s[2]))

const EGG_AURA_OY := 21.0
func _egg_enhance_aura() -> void:
	var frames: Array = []
	for i in 6:
		var t := AtlasUI.tex("common_ui", "common_ani_egg_up1_%d" % (i + 1))
		if t != null: frames.append(t)
	if frames.is_empty():
		return
	var holder := AtlasUI.spr_cocos("common_ui", "common_ani_egg_up1_1", 1.1 * 1.5, Vector2(0.5, 0))
	if holder == null:
		return
	holder.position = _egg_pt(175, EGG_AURA_OY)
	_egg_layer.add_child(holder)
	var fx: Sprite2D = holder.get_child(0)
	var idx := {"i": 0}
	var apply := func() -> void:
		var t: Texture2D = frames[int(idx["i"]) % frames.size()]
		var base: Texture2D = frames[0]
		fx.texture = t
		fx.offset = Vector2(0, (base.get_height() - t.get_height()) * 0.5)
		idx["i"] = int(idx["i"]) + 1
	apply.call()
	var tm := Timer.new(); tm.wait_time = 0.15; tm.autostart = true
	tm.timeout.connect(apply); holder.add_child(tm)

func _build_egg_plate() -> void:
	var host := Node2D.new()
	host.position = Vector2(EGG_NUDGE.x, EGG_PLATE_DY + 8.0 + EGG_NUDGE.y) / S1080
	host.scale = Vector2(1.0 / S1080, 1.0 / S1080)
	_stage.add_child(host)
	_egg_plate = Control.new()
	_egg_plate.size = EGG_PLATE_SIZE
	_egg_plate.position = -EGG_PLATE_SIZE * 0.5
	_egg_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(_egg_plate)
	var np := AtlasUI.nine("ninepatch_ui", "9patch_dialogue_box", EGG_PLATE_SIZE, Rect2(20, 20, 2, 2))
	if np: _egg_plate.add_child(np)
	_egg_time_label = Label.new()
	_lvup_bm_style(_egg_time_label, 23, Color(1, 1, 1), "font_subtitle")
	_egg_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_egg_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_egg_time_label.size = EGG_PLATE_SIZE
	_egg_time_label.position = Vector2(5, 0)
	_egg_plate.add_child(_egg_time_label)
	_egg_dia_btn = Control.new()
	_egg_dia_btn.size = Vector2(40, 40)
	_egg_dia_btn.position = Vector2(-20, EGG_PLATE_SIZE.y * 0.5 - 20.0 + 2.0)
	_egg_plate.add_child(_egg_dia_btn)
	var chg := AtlasUI.spr("common_ui", "common_charge", Design.ASSET_SCALE * 1.3)
	if chg:
		chg.position = _egg_dia_btn.size * 0.5
		_egg_dia_btn.add_child(chg)
	var db := Button.new()
	db.flat = true; db.size = _egg_dia_btn.size
	db.pressed.connect(_on_egg_dia)
	_egg_dia_btn.add_child(db)

func _tick_egg() -> void:
	if not is_instance_valid(_egg_layer) or _egg_uid == 0:
		return
	var d := UserDB.get_dragon(_egg_uid)
	if d.is_empty() or not UserDB.is_egg(d):
		return
	var remain := UserDB.hatch_remain(d)
	if remain <= 0:
		if not _egg_done:
			_egg_reach_complete()
		return
	if is_instance_valid(_egg_time_label):
		_egg_time_label.text = Hatchery.format_remain(remain)
	var tm := Timer.new(); tm.wait_time = 1.0; tm.one_shot = true; tm.autostart = true
	tm.timeout.connect(func():
		tm.queue_free()
		_tick_egg())
	_egg_layer.add_child(tm)

func _egg_reach_complete() -> void:
	_egg_done = true
	if is_instance_valid(_egg_time_label):
		_egg_time_label.text = "완료"
		_egg_time_label.position = Vector2.ZERO
	if is_instance_valid(_egg_dia_btn):
		_egg_dia_btn.queue_free(); _egg_dia_btn = null
	for g in _egg_ghosts:
		if is_instance_valid(g): g.queue_free()
	_egg_ghosts.clear()
	if not is_instance_valid(_egg_body):
		return
	var body := _egg_body
	var t := body.create_tween()
	t.tween_property(body, "scale", Vector2(1.5, 1.5), 0.5)
	t.tween_callback(func(): _egg_action_loop(body))
	var hit := Button.new()
	hit.flat = true
	hit.size = Vector2(250, 300)
	hit.position = _egg_pt(175, EGG_LAYER_SIZE.y * 0.5) - hit.size * 0.5
	hit.pressed.connect(_on_egg_tap)
	_egg_layer.add_child(hit)

func _egg_action_loop(n: Node2D) -> void:
	var home: Vector2 = n.get_meta("home", n.position)
	var s := Vector2(1.5, 1.5)
	var t := n.create_tween().set_loops()
	_egg_action_tw = t
	t.tween_interval(0.25)
	for _pass in 2:
		for v in [-2.0, 1.5, -1.0, 0.5, 0.0]:
			t.tween_property(n, "skew", deg_to_rad(v), 0.05)
		t.tween_interval(0.5)
	for v in [5.0, -5.0, 5.0, -5.0, 5.0, -5.0, 4.0, -3.0, 2.0, -1.0, 0.0]:
		t.tween_property(n, "skew", deg_to_rad(v), 0.05)
	t.tween_interval(0.5)
	for _jump in 2:
		s *= Vector2(1.1, 0.8)
		t.tween_property(n, "scale", s, 0.25)
		t.tween_callback(func(): Bgm.sfx(EGG_BEAT_SFX))
		s *= Vector2(0.81818175, 1.25)
		t.tween_property(n, "position:y", home.y - 100.0, 0.1).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(n, "scale", s, 0.1)
		s *= Vector2(1.1111112, 1.0)
		t.tween_property(n, "scale", s, 0.1)
		var s1 := s * Vector2(0.9, 1.1)
		var s2 := s1 * Vector2(1.1111112, 0.9090909)
		s = s2
		t.tween_property(n, "position:y", home.y, 0.25).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(n, "scale", s1, 0.15)
		t.parallel().tween_property(n, "scale", s2, 0.1).set_delay(0.15)
	for m in [Vector2(1.05, 0.9), Vector2(0.9047619, 1.1666666), Vector2(1.0526316, 0.952381)]:
		s *= m
		t.tween_property(n, "scale", s, 0.1)

func _on_egg_tap() -> void:
	if _egg_busy or not _egg_done or not is_instance_valid(_egg_body):
		return
	_egg_busy = true
	Bgm.sfx("effect_button")
	var n := _egg_body
	if _egg_action_tw != null and _egg_action_tw.is_valid():
		_egg_action_tw.kill()
	var tw := n.create_tween()
	var home: Vector2 = n.get_meta("home", n.position)
	var s := Vector2(1.5, 1.5) * Vector2(0.95, 1.05)
	tw.tween_property(n, "skew", 0.0, 0.2)
	tw.parallel().tween_property(n, "position", home, 0.2)
	tw.parallel().tween_property(n, "scale", s, 0.2)
	s *= Vector2(1.1052631, 0.9047619)
	tw.tween_property(n, "scale", s, 0.2)
	s *= Vector2(0.952381, 1.0526316)
	tw.tween_property(n, "scale", s, 0.2)
	tw.tween_callback(func(): _hatch_ceremony(_egg_uid))

func _on_egg_dia() -> void:
	if _egg_busy or _egg_done or _egg_uid == 0:
		return
	var d := UserDB.get_dragon(_egg_uid)
	if d.is_empty(): return
	var remain := UserDB.hatch_remain(d)
	var msg := "알 부화까지 %s 남았습니다.\n알을 즉시 부화시키겠습니까?\n\n다이아 %d개" % [
		Hatchery.format_remain_compact(remain), EGG_DIA_COST]
	_open_popup_type("즉시 부화", msg, func():
		if UserDB.currency("diamond") < EGG_DIA_COST:
			_toast("다이아가 부족합니다"); return
		UserDB.add_currency("diamond", -EGG_DIA_COST)
		UserDB.set_hatch_now(_egg_uid)
		_tick_egg())

func _hatch_ceremony(uid: int) -> void:
	var d := UserDB.get_dragon(uid)
	if d.is_empty():
		_egg_busy = false; return
	var grade := float(d.get("egg_grade", Growth.BASE_GRADE))
	var blessed := bool(d.get("egg_blessed", false))

	var beam_scale := 0.7 if int(d.get("id", 0)) == 23 else 0.93
	if is_instance_valid(_egg_layer) and ResourceLoader.exists("res://scenes/fx/egglight.tscn"):
		var holder := Node2D.new()
		holder.position = _egg_pt(EGG_LAYER_SIZE.x * 0.5 - 7.0, EGG_LAYER_SIZE.y * 0.5 - 100.0)
		holder.scale = Vector2(beam_scale, beam_scale)
		holder.z_index = 5
		_egg_layer.add_child(holder)
		var inst = load("res://scenes/fx/egglight.tscn").instantiate()
		holder.add_child(inst)
		var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		if ap and ap.has_animation("egglight"):
			ap.get_animation("egglight").loop_mode = Animation.LOOP_NONE
			ap.play("egglight")
		var ht := holder.create_tween()
		ht.tween_interval(4.5)
		ht.tween_property(holder, "modulate:a", 0.0, 0.5)
		ht.tween_callback(func(): if is_instance_valid(holder): holder.queue_free())
	var beat_t := 0.0
	for i in EGG_BEAT_DELAYS.size():
		beat_t += float(EGG_BEAT_DELAYS[i])
		if i < 2:
			continue
		var when := beat_t
		var bt := create_tween()
		bt.tween_interval(when)
		bt.tween_callback(func(): Bgm.sfx(EGG_BEAT_SFX))
	_egg_rating_counter(grade, blessed)
	var cl := CanvasLayer.new(); cl.layer = 80; add_child(cl)
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_STOP
	cl.add_child(flash)
	var ft := flash.create_tween()
	ft.tween_interval(3.0)
	ft.tween_property(flash, "color:a", 1.0, 0.5)
	ft.tween_callback(func():
		UserDB.hatch_egg(uid, Hatchery.stat_bonus_for_grade(grade))
		_egg_uid = 0
		_egg_busy = false
		_refresh())
	ft.tween_interval(0.5)
	ft.tween_property(flash, "color:a", 0.0, 1.0)
	ft.tween_callback(func():
		if is_instance_valid(cl): cl.queue_free()
		_open_rename())

func _egg_rating_counter(grade: float, blessed: bool) -> void:
	var vis := _vis()
	var base := grade - (Hatchery.BLESSED_NEST_BONUS if blessed else 0.0)
	var cl := CanvasLayer.new(); cl.layer = 70; add_child(cl)
	var lab := Label.new()
	_lvup_bm_style(lab, 124, Color(1, 1, 1), "font_total")
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.size = Vector2(400, 160)
	lab.pivot_offset = lab.size * 0.5
	lab.text = "0.0"
	lab.scale = Vector2.ZERO
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var start := Vector2(vis.x * 0.5, vis.y * 0.5) - lab.size * 0.5
	var mid := start - Vector2(0, vis.y * 0.25)
	var top := mid - Vector2(0, 50)
	lab.position = start
	cl.add_child(lab)

	var t := lab.create_tween()
	t.tween_property(lab, "position", mid, 0.1)
	t.parallel().tween_property(lab, "scale", Vector2(0.675, 0.825), 0.1)
	t.tween_property(lab, "scale", Vector2(0.825, 0.675), 0.1)
	t.tween_property(lab, "scale", Vector2(0.75, 0.75), 0.1)
	var steps := int(ceil(maxf(0.0, base) / 0.1))
	for i in steps:
		var v := minf(base, float(i + 1) * 0.1)
		t.tween_callback(func(): if is_instance_valid(lab): lab.text = "%.1f" % v)
		t.tween_interval(0.0125)
	t.tween_property(lab, "scale", Vector2(0.675, 0.825), 0.1)
	t.tween_property(lab, "scale", Vector2(0.825, 0.675), 0.1)
	t.tween_property(lab, "scale", Vector2(0.75, 0.75), 0.1)
	t.tween_property(lab, "position", top, 0.0)
	if blessed:
		t.tween_interval(0.8)
		t.tween_callback(func(): if is_instance_valid(lab): lab.text = "%.1f" % grade)
		t.tween_property(lab, "scale", Vector2(0.675, 0.825), 0.1)
		t.tween_property(lab, "scale", Vector2(0.825, 0.675), 0.1)
		t.tween_property(lab, "scale", Vector2(0.75, 0.75), 0.1)
	t.tween_interval(0.8)
	t.tween_property(lab, "position", top + Vector2(0, 10), 0.1)
	t.parallel().tween_property(lab, "modulate:a", 0.0, 0.2)
	t.tween_property(lab, "position", top - Vector2(0, 25), 0.1)
	t.tween_callback(func():
		if not is_instance_valid(cl): return
		var fin := Label.new()
		_lvup_bm_style(fin, 91, Color(1, 1, 1), "font_combine")
		fin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fin.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fin.size = lab.size
		fin.position = top
		fin.text = "%.1f" % grade
		fin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.add_child(fin))
	var kill := create_tween()
	kill.tween_interval(5.2)
	kill.tween_callback(func(): if is_instance_valid(cl): cl.queue_free())

func _set_name(bb: String) -> void:
	_name_label.text = "[center]%s[/center]" % bb

func _refresh_stats() -> void:
	_refresh_slots()
	var a := _active()
	if a.is_empty():
		_set_name("보유 드래곤 없음")
		for k in ["hp", "att", "def"]:
			if _stat_plates.get(k): (_stat_plates[k] as Label).text = "-"
		_grade_label.text = "-"
		return
	var d: Dictionary = Data.get_dragon(int(a["id"]))
	var lv := int(a["level"])
	var bonus: Dictionary = a.get("stat_bonus", {})
	var base_bonus: Dictionary = (bonus as Dictionary).get("base", {})
	var main := Growth.main_stats(d, Data.stat_table, a.get("gain_log", []), base_bonus)
	var s := _stats_with_gems(a, lv)
	_grade_label.text = "%.1f" % _grade_of(a, d)
	var nick := String(a.get("nick", ""))
	var species := Icons.species_name(int(a.get("id", 0)))
	if species == "":
		species = "?"
	if nick != "":
		_set_name("레벨 %d  %s  [color=#b8b0a0][font_size=18](%s)[/font_size][/color]" % [lv, nick, species])
	else:
		_set_name("레벨 %d  %s" % [lv, species])
	_update_elem_icon(Icons.element_of(a))
	if UserDB.is_egg(a):
		var enh := int(a.get("egg_enhance", 0))
		var pre := ("[color=#f0c040]+%d[/color] " % enh) if enh > 0 else ""
		_set_name("%s%s" % [pre, species])
		for k2 in ["hp", "att", "def"]:
			if _stat_plates.get(k2): (_stat_plates[k2] as Label).text = "???"
		_grade_label.text = "-"
		return
	for k in ["hp", "att", "def"]:
		var lab: Label = _stat_plates.get(k)
		if lab == null:
			continue
		var extra: int = int(s.get(k, 0)) - int(main.get(k, 0))
		lab.text = ("%d(+%d)" % [int(main[k]), extra]) if extra != 0 else str(int(main[k]))

func _grade_of(inst: Dictionary, ddef: Dictionary) -> float:
	return Growth.compute_grade(ddef, Data.stat_table, inst.get("stat_bonus", {}),
		inst.get("gain_log", []), Data.level_curve.get("grade", {}))

const _ELEM_KR := {"fire": "불", "aqua": "물", "wind": "바람", "earth": "땅", "light": "빛",
	"dark": "어둠", "holy": "신성", "chaos": "혼돈", "shadow": "그림자"}
func _open_element_info() -> void:
	var a := _active()
	if a.is_empty(): return
	var el := str(Data.get_dragon(int(a["id"])).get("element", ""))
	if el == "": return
	var ecfg: Dictionary = Data.combat.get("element", {})
	var good: Array = ecfg.get("good_vs", {}).get(el, [])
	var bad: Array = ecfg.get("bad_vs", {}).get(el, [])
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 50; add_child(layer)
	var pop := Control.new(); pop.set_anchors_preset(Control.PRESET_FULL_RECT); layer.add_child(pop)
	pop.tree_exiting.connect(func(): if is_instance_valid(layer): layer.queue_free())
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: pop.queue_free())
	pop.add_child(dim)
	var panel := _orig_popup(pop, Vector2(460, 330), "%s 속성 상성" % _ELEM_KR.get(el, el))
	var title := Label.new()
	title.text = ""
	title.size = Vector2(460, 36); title.position = Vector2(0, 18)
	panel.add_child(title)
	_elem_row(panel, "강함 (×1.25)", good, Color(0.5, 1, 0.5), 74)
	_elem_row(panel, "약함 (×0.85)", bad, Color(1, 0.6, 0.5), 170)
	var close := Button.new(); close.text = "닫기"; close.size = Vector2(120, 40)
	close.position = Vector2(170, 280); close.pressed.connect(func(): pop.queue_free()); panel.add_child(close)

const _QUESTS := [
	{"key": "battles", "label": "전투 승리", "goal": 3, "gold": 300},
	{"key": "hatches", "label": "부화하기", "goal": 1, "gold": 200},
]

func _title_progress() -> Dictionary:
	var maxlv := 0
	for d in UserDB.dragons():
		maxlv = maxi(maxlv, int((d as Dictionary).get("level", 1)))
	return {
		"dragons": UserDB.dragons().size(),
		"hatches": UserDB.quest_count("hatches"),
		"battles": UserDB.quest_count("battles"),
		"max_level": maxlv,
		"gold": UserDB.gold(),
	}

func _open_titles() -> void:
	var table: Dictionary = Data.titles
	if table.is_empty():
		_toast("칭호 데이터가 없습니다"); return
	var prog := _title_progress()
	var view := Titles.sorted_for_view(prog, table)
	var got := Titles.unlocked_nos(prog, table).size()
	const BW := 640.0
	const BH := 520.0
	var vis := _vis()
	var overlay := CanvasLayer.new(); overlay.layer = 30; add_child(overlay)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: overlay.queue_free())
	overlay.add_child(dim)
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	overlay.add_child(win)
	var tbar := NinePatchRect.new(); tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(BW * 0.9, 56); tbar.position = Vector2((BW - BW * 0.9) * 0.5, 14); win.add_child(tbar)
	var t := Label.new(); t.text = "칭호  %d / %d" % [got, (table.get("titles", []) as Array).size()]
	t.add_theme_font_size_override("font_size", 24); t.add_theme_color_override("font_color", Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size = tbar.size; tbar.add_child(t)
	var cb := TextureButton.new(); cb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	cb.position = Vector2(BW - 72, 8); win.add_child(cb)
	cb.pressed.connect(func(): overlay.queue_free())
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(36, 86); scroll.size = Vector2(BW - 72, BH - 130)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(scroll)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 4)
	col.custom_minimum_size.x = BW - 92; scroll.add_child(col)
	var adir := String(table.get("atlas_dir", "title_ui"))
	var cur := int(UserDB.get_pmeta("title_no", 0))
	for td: Dictionary in view:
		var no := int(td["title_no"])
		var unlocked := Titles.is_unlocked(td, prog)
		var row := Control.new(); row.custom_minimum_size = Vector2(0, 46)
		var tp := "res://assets/converted/%s/%s.tres" % [adir, String(td["frame"])]
		if ResourceLoader.exists(tp):
			var tr := TextureRect.new(); tr.texture = load(tp)
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.size = Vector2(190, 34); tr.position = Vector2(40, 6)
			tr.modulate = Color.WHITE if unlocked else Color(0.35, 0.33, 0.30)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(tr)
		if unlocked:
			var chk := "res://assets/converted/common_ui/common_checked.tres"
			if ResourceLoader.exists(chk):
				var cs := Sprite2D.new(); cs.texture = load(chk); cs.position = Vector2(20, 23)
				row.add_child(cs)
		var info := Label.new()
		info.text = String(td.get("comment", ""))
		if not unlocked:
			info.text += "   (%d%%)" % int(Titles.progress_ratio(td, prog) * 100.0)
		info.add_theme_font_size_override("font_size", 14)
		info.add_theme_color_override("font_color", Color(0.3, 0.22, 0.08) if unlocked else Color(0.5, 0.46, 0.4))
		info.position = Vector2(246, 14); info.size = Vector2(230, 20); row.add_child(info)
		if unlocked:
			var b := Button.new()
			b.text = "사용 중" if no == cur else "장착"
			b.disabled = (no == cur)
			b.size = Vector2(78, 34); b.position = Vector2(BW - 190, 6)
			var n2 := no
			b.pressed.connect(func():
				UserDB.set_pmeta("title_no", n2)
				_toast("칭호를 장착했습니다")
				overlay.queue_free(); _open_titles())
			row.add_child(b)
		col.add_child(row)

func _open_quests() -> void:
	var m := MissionBoard.open(self, 0, "cave", {})
	m.changed.connect(_refresh)

const _LVUP_GUARANTEE := {
	"bless_of_dragon": "max1", "bless_of_maia": "max2",
	"bless_of_dersa": "triple", "bless_of_amor": "amor",
}

func _dragon_voice_no(dragon_id: int, level: int) -> int:
	var e: Dictionary = Icons.voice_row(dragon_id)
	if e.is_empty():
		return 0
	return int(e.get(Growth.stage_for_level(level), 0))

func _play_dragon_voice(dragon_id: int, level: int) -> void:
	var n := _dragon_voice_no(dragon_id, level)
	if n > 0:
		Bgm.sfx("voice%d" % n)

func _play_dragon_voice_delayed(dragon_id: int, level: int) -> void:
	await get_tree().create_timer(0.5).timeout
	if is_inside_tree():
		_play_dragon_voice(dragon_id, level)

var _lvup_bmfonts := {}
func _lvup_bmfont(name: String) -> FontFile:
	if _lvup_bmfonts.has(name):
		return _lvup_bmfonts[name]
	var p := "res://assets/converted/font_ui/%s.fnt" % name
	if not ResourceLoader.exists(p):
		return null
	var f: FontFile = load(p).duplicate()
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Gulim"])
	f.fallbacks = [fb]
	_lvup_bmfonts[name] = f
	return f

func _lvup_bm_style(l: Label, size: int, col: Color, font := "font_subtitle") -> void:
	var f := _lvup_bmfont(font)
	if f:
		l.add_theme_font_override("font", f)
	else:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 5 if size >= 24 else 4)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _open_levelup() -> LevelUpScreen:
	var a := _active()
	if a.is_empty(): return null
	return LevelUpScreen.open(self, int(a["uid"]), {
		"stage_node": _stage,
		"on_evolved": func():
			_refresh_dragon()
			_refresh_list(),
		"on_changed": _refresh_stats,
	})

func _open_dragon_skin() -> void:
	var a := _active()
	if a.is_empty(): return
	var uid := int(a["uid"]); var id := int(a["id"])
	var cnt := _dragon_skin_count(id)
	var cur := int(a.get("skin", 0))
	var vis := _vis()
	var overlay := CanvasLayer.new(); overlay.layer = 30; add_child(overlay)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: overlay.queue_free())
	overlay.add_child(dim)
	const BW := 640.0
	const BH := 340.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	overlay.add_child(win)
	var tbar := NinePatchRect.new(); tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(BW * 0.9, 52); tbar.position = Vector2((BW - BW * 0.9) * 0.5, 12); win.add_child(tbar)
	var t := Label.new(); t.text = "드래곤 스킨"; t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color.WHITE); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; t.size = tbar.size; tbar.add_child(t)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 50 - 16, 14); xb.pressed.connect(func(): overlay.queue_free()); win.add_child(xb)
	var bl := load("res://assets/converted/common_ui/common_backlight3.tres")
	var opts := range(0, cnt + 1)
	var x0 := (BW - float(opts.size()) * 150.0) * 0.5 + 75.0
	for i in opts.size():
		var sk: int = opts[i]
		var cx := x0 + i * 150.0
		if sk == cur and bl:
			var blr := TextureRect.new(); blr.texture = bl; blr.position = Vector2(cx - 75, 88); blr.size = Vector2(150, 150)
			blr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; win.add_child(blr)
		var por := _portrait_sprite(id, "adult", 0.85, sk)
		if por: por.position = Vector2(cx, 162); win.add_child(por)
		var nl := Label.new(); nl.text = ("기본" if sk == 0 else "스킨%d" % sk) + ("  ✓" if sk == cur else "")
		nl.add_theme_font_size_override("font_size", 15)
		nl.add_theme_color_override("font_color", Color(0.85, 0.6, 0.15) if sk == cur else Color(0.25, 0.18, 0.1))
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; nl.size = Vector2(120, 22); nl.position = Vector2(cx - 60, 244); win.add_child(nl)
		var b := Button.new(); b.flat = true; b.size = Vector2(120, 172); b.position = Vector2(cx - 60, 88)
		b.pressed.connect(func(): UserDB.set_dragon_field(uid, "skin", sk); overlay.queue_free(); _refresh())
		win.add_child(b)

func _rename_gate() -> void:
	if _active().is_empty():
		return
	var have := UserDB.item_count(RENAME_ITEM)
	var nm := Data.item_name(RENAME_ITEM)
	if have > 0:
		_open_popup_type("이름 바꾸기",
			"%s 1개를 사용하여 이름을 바꿉니다.\n(보유 %d개)" % [nm, have],
			func():
				UserDB.use_item(RENAME_ITEM, 1)
				_refresh()
				_open_rename())
		return
	var price := _shop_price(RENAME_ITEM)
	if price.is_empty():
		_toast("%s 이(가) 필요합니다" % nm)
		return
	var cost := int(price["price"])
	var cur := String(price["cur"])
	var cur_kr := "다이아" if cur == "diamond" else "골드"
	_open_popup_type("%s 구매" % nm,
		"%s%s 없습니다.\n%d %s로 1개를 사시겠습니까?"
			% [nm, _josa_iga(nm), cost, cur_kr],
		func():
			if not UserDB.spend(cur, cost):
				_toast("%s 가 부족합니다" % cur_kr)
				return
			UserDB.add_item(RENAME_ITEM, 1)
			_refresh()
			_rename_gate(),
		"구매")

const RENAME_ITEM := "dragon_namechange"

func _josa_iga(word: String) -> String:
	if word.is_empty():
		return "가"
	var c := word.unicode_at(word.length() - 1)
	if c < 0xAC00 or c > 0xD7A3:
		return "가"
	return "이" if ((c - 0xAC00) % 28) != 0 else "가"

func _shop_price(key: String) -> Dictionary:
	for t in Data.shop.get("tabs", []):
		for it in (t as Dictionary).get("stock", []):
			var e: Dictionary = it
			if String(e.get("item", "")) == key and int(e.get("bundle", 1)) <= 1:
				return {"price": int(e.get("price", 0)), "cur": String(e.get("cur", "gold"))}
	return {}

func _open_rename() -> void:
	var a := _active()
	if a.is_empty(): return
	var uid := int(a["uid"])
	var species := Icons.species_name(int(a["id"]))
	const BW := 650.0
	const BH := 480.0
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 50; add_child(layer)
	var pop := Control.new(); pop.set_anchors_preset(Control.PRESET_FULL_RECT); layer.add_child(pop)
	pop.tree_exiting.connect(func(): if is_instance_valid(layer): layer.queue_free())
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pop.add_child(dim)
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5)); pop.add_child(win)
	var tbar := NinePatchRect.new(); tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(BW * 0.9, 56); tbar.position = Vector2((BW - BW * 0.9) * 0.5, 14); win.add_child(tbar)
	var title := Label.new(); title.text = "이름 짓기"
	title.add_theme_font_size_override("font_size", 24); title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size = tbar.size; tbar.add_child(title)
	var cls := TextureButton.new(); cls.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	cls.position = Vector2(BW - 50 - 22, (BH - 430) - 22); win.add_child(cls)
	cls.pressed.connect(func(): pop.queue_free())
	var tbox := NinePatchRect.new(); tbox.texture = load("res://assets/converted/ninepatch_ui/9patch_text_box.tres")
	tbox.patch_margin_left = 20; tbox.patch_margin_right = 20; tbox.patch_margin_top = 16; tbox.patch_margin_bottom = 16
	tbox.size = Vector2(400, 53); tbox.position = Vector2((BW - 400) * 0.5, 210); win.add_child(tbox)
	var le := LineEdit.new(); le.flat = true
	le.text = String(a.get("nick", "")); le.placeholder_text = species; le.max_length = 12
	le.add_theme_font_size_override("font_size", 22); le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	le.set_anchors_preset(Control.PRESET_FULL_RECT); le.add_theme_color_override("font_color", Color(0.15, 0.12, 0.08))
	tbox.add_child(le); le.grab_focus()
	var hint := Label.new(); hint.text = "원종: %s   (비우면 원종명 사용)" % species
	hint.add_theme_font_size_override("font_size", 15); hint.add_theme_color_override("font_color", Color(0.55, 0.5, 0.42))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hint.size = Vector2(BW, 22); hint.position = Vector2(0, 168); win.add_child(hint)
	var bchk := CheckBox.new(); bchk.text = "머리 위 이름 말풍선 표시"
	bchk.button_pressed = bool(UserDB.get_pmeta("name_balloon", true))
	bchk.add_theme_font_size_override("font_size", 16)
	bchk.position = Vector2((BW - 240) * 0.5, 290); win.add_child(bchk)
	var ok := Button.new(); ok.text = "확인"; ok.size = Vector2(220, 56); ok.position = Vector2(BW * 0.5 - 120 - 110, BH - 75 - 28)
	var apply := func():
		UserDB.set_dragon_field(uid, "nick", TextField.value(le))
		UserDB.set_pmeta("name_balloon", bchk.button_pressed)
		pop.queue_free(); _refresh_stats()
	ok.pressed.connect(apply); le.text_submitted.connect(func(_s): apply.call())
	win.add_child(ok)
	var cancel := Button.new(); cancel.text = "취소"; cancel.size = Vector2(220, 56); cancel.position = Vector2(BW * 0.5 + 120 - 110, BH - 75 - 28)
	cancel.pressed.connect(func(): pop.queue_free()); win.add_child(cancel)
	TextField.no_steal(pop)
	le.grab_focus()

func _elem_row(parent: Control, label: String, elems: Array, col: Color, y: float) -> void:
	var l := Label.new(); l.text = label; l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", col); l.position = Vector2(28, y); parent.add_child(l)
	if elems.is_empty():
		var n := Label.new(); n.text = "없음"; n.add_theme_font_size_override("font_size", 16)
		n.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7)); n.position = Vector2(28, y + 30); parent.add_child(n)
		return
	var x := 28.0
	for e in elems:
		var mk := _atlas_sprite("battle_ui", "battle_element_%s_mark" % str(e), _battle_manifest, 0.5)
		if mk:
			mk.position = Vector2(x + 18, y + 48); parent.add_child(mk)
		var nl := Label.new(); nl.text = _ELEM_KR.get(str(e), str(e)); nl.add_theme_font_size_override("font_size", 14)
		nl.add_theme_color_override("font_color", Color.WHITE); nl.position = Vector2(x, y + 68); parent.add_child(nl)
		x += 76.0

const ELE_SMALL := {
	"all": "item_item_small_ele_all", "fire": "item_item_small_ele_fire",
	"aqua": "item_item_small_ele_water", "earth": "item_item_small_ele_ground",
	"wind": "item_item_small_ele_wind", "light": "item_item_small_ele_light",
	"dark": "item_item_small_ele_dark", "holy": "item_item_small_ele_holy",
	"chaos": "item_item_small_ele_chaos", "shadow": "item_item_small_ele_shadow"}

func _update_elem_icon(element: String) -> void:
	var name := str(ELE_SMALL.get(element, ELE_SMALL["all"]))
	var p := "res://assets/converted/item_small_ui/%s.tres" % name
	if not ResourceLoader.exists(p):
		_elem_icon.visible = false
		return
	_elem_icon.visible = true
	_elem_icon.texture = load(p)
	var info: Dictionary = _item_small_manifest.get(name, {})
	_elem_icon.rotation = 0.0
	_elem_icon.flip_h = false
	var hh: float = maxf(1.0, float(info.get("h", 70)))
	_elem_icon.scale = Vector2(46.0 / hh, 46.0 / hh)

func _levelup_banner() -> void:
	var vis := _vis()
	_play_fx_spine("res://scenes/fx/dragon_enchant_lvup.tscn", "reset", Vector2(vis.x * 0.5, vis.y * 0.40), 70)

const MAGIC_STONE_COST := 2000
const MAGIC_STONE_ITEM := "stone_spirit1"
func _open_make_magic_stone() -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 72; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	const BW := 420.0
	const BH := 300.0
	var cm := _man_common()
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(280, 52); tbar.position = Vector2((BW - 280) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = "정령석 제작"
	tl.add_theme_font_size_override("font_size", 26); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	var bl := _atlas_sprite("common_ui", "common_backlight3", cm, 0.75)
	if bl: bl.position = Vector2(BW * 0.5, 140); bl.modulate = Color(1, 1, 1, 0.35); win.add_child(bl)
	var ipath := Data.item_icon_path(MAGIC_STONE_ITEM)
	if ResourceLoader.exists(ipath):
		var icon := Sprite2D.new(); icon.texture = load(ipath); icon.material = _pma
		icon.position = Vector2(BW * 0.5, 140); icon.scale = Vector2(0.9, 0.9); win.add_child(icon)
	var ml := Label.new(); ml.text = "정령석 잠재석을 제작합니다."
	ml.add_theme_font_size_override("font_size", 18); ml.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; ml.position = Vector2(0, 196); ml.size = Vector2(BW, 24); win.add_child(ml)
	var ok := Button.new(); ok.size = Vector2(180, 50); ok.position = Vector2((BW - 180) * 0.5, BH - 74); win.add_child(ok)
	var oc := _atlas_sprite("common_ui", "common_coin_small1", cm, 0.8)
	if oc: oc.position = Vector2(BW * 0.5 - 46, BH - 49); win.add_child(oc)
	var ol := Label.new(); ol.text = "제작  %d" % MAGIC_STONE_COST; ol.add_theme_font_size_override("font_size", 19)
	ol.add_theme_color_override("font_color", Color.WHITE); ol.position = Vector2(BW * 0.5 - 24, BH - 61); ol.size = Vector2(130, 26); win.add_child(ol)
	ok.pressed.connect(func():
		if not UserDB.spend("gold", MAGIC_STONE_COST): return
		UserDB.add_item(MAGIC_STONE_ITEM, 1)
		if is_instance_valid(layer): layer.queue_free()
		_open_complete("정령석 제작", "%s 1개를 제작했습니다!" % Data.item_name(MAGIC_STONE_ITEM)))

func _open_training_select() -> void:
	var a := _active()
	if a.is_empty(): return
	_open_backdrop(0.55)
	var vis := _vis()
	var BW := clampf(vis.x - 120.0, 640.0, 960.0)
	var BH := clampf(vis.y - 80.0, 480.0, 640.0)
	var pf := FileAccess.open("res://assets/converted/promote_ui/_manifest.json", FileAccess.READ)
	var pm: Dictionary = JSON.parse_string(pf.get_as_text()) if pf else {}
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	_overlay.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(300, 54); tbar.position = Vector2((BW - 300) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = "훈련"
	tl.add_theme_font_size_override("font_size", 26); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 66, 14); xb.pressed.connect(_close_overlay); win.add_child(xb)
	var cm := _man_common()
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 92); scroll.size = Vector2(BW - 80, BH - 130)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = maxi(3, int((BW - 80) / 200.0))
	grid.add_theme_constant_override("h_separation", 10); grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	var uid := int(a["uid"])
	for i in range(1, 11):
		var lv_gain := i
		var cost := 300 * i
		var cell := Control.new(); cell.custom_minimum_size = Vector2(190, 90)
		var slot := _atlas_sprite("promote_ui", "scene_promote_slot_bg", pm, 1.2)
		if slot: slot.position = Vector2(95, 30); cell.add_child(slot)
		var timg := _atlas_sprite("promote_ui", "scene_promote_train%d" % i, pm, 0.6)
		if timg: timg.position = Vector2(36, 30); cell.add_child(timg)
		var nm := Label.new(); nm.text = "훈련 %d  (+%dLv)" % [i, lv_gain]
		nm.add_theme_font_size_override("font_size", 15); nm.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05))
		nm.position = Vector2(64, 16); nm.size = Vector2(120, 22); cell.add_child(nm)
		var coin := _atlas_sprite("common_ui", "common_coin_small1", cm, 0.7)
		if coin: coin.position = Vector2(72, 46); cell.add_child(coin)
		var cl := Label.new(); cl.text = "%d" % cost
		cl.add_theme_font_size_override("font_size", 14); cl.add_theme_color_override("font_color", Color(0.35, 0.24, 0.06))
		cl.position = Vector2(88, 36); cl.size = Vector2(90, 22); cell.add_child(cl)
		var b := Button.new(); b.flat = true; b.size = Vector2(190, 62); b.position = Vector2(0, 0)
		b.pressed.connect(func():
			if not UserDB.spend("gold", cost): return
			var cur := UserDB.get_dragon(uid)
			var old_lv := int(cur.get("level", 1))
			var nl := old_lv
			for _s in lv_gain:
				nl = Growth.next_level(nl, bool(cur.get("awakened", false)))
			var sk_before := UserDB.dragon_skills(uid).size()
			UserDB.set_level(uid, nl)
			var got := _skills_learned_since(uid, sk_before)
			_close_overlay(); _refresh()
			_open_training_result(int(cur["id"]), old_lv, nl)
			if not got.is_empty():
				_toast("새 스킬 습득 — %s" % ", ".join(got)))
		cell.add_child(b)
		grid.add_child(cell)

func _open_training_result(dragon_id: int, before_lv: int, after_lv: int) -> void:
	Bgm.sfx("effect_level_updown")
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 72; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	const BW := 440.0
	const BH := 500.0
	var cm := _man_common()
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(280, 52); tbar.position = Vector2((BW - 280) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = "훈련 완료"
	tl.add_theme_font_size_override("font_size", 26); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = tbar.size; tbar.add_child(tl)
	var bl := _atlas_sprite("common_ui", "common_backlight3", cm, 0.9)
	if bl: bl.position = Vector2(BW * 0.5, 150); bl.modulate = Color(1, 1, 1, 0.4); win.add_child(bl)
	var por := _portrait_sprite(dragon_id, Growth.stage_for_level(after_lv), 0.8, 0)
	if por: por.position = Vector2(BW * 0.5, 150); win.add_child(por)
	var lup := TextureRect.new()
	lup.texture = load("res://assets/converted/lvup_ui/level_up.png")
	lup.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lup.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lup.size = Vector2(180, 96); lup.position = Vector2((BW - 180) * 0.5, 196)
	win.add_child(lup)
	var max_stats: Dictionary = Growth.tier_growth(Data.get_dragon(dragon_id), Data.stat_table)
	var rows := [["레벨", Color(1.0, 0.83, 0.25), str(before_lv), str(after_lv), "", false]]
	var sb: Dictionary = _active().get("stat_bonus", {})
	var maxed := 0
	for spec in [["hp", "생명력", Color(0.45, 0.95, 0.45)], ["att", "공격력", Color(1.0, 0.45, 0.4)],
			["def", "방어력", Color(0.45, 0.7, 1.0)]]:
		var st: Dictionary = Growth.compute_stats(Data.get_dragon(dragon_id), Data.stat_table, after_lv, sb)
		var pv: Dictionary = Growth.compute_stats(Data.get_dragon(dragon_id), Data.stat_table, before_lv, sb)
		var k: String = spec[0]
		var delta := int(st[k]) - int(pv[k])
		var mx := int(max_stats.get(k, 0))
		var is_max := mx > 0 and delta >= mx
		if is_max: maxed += 1
		rows.append([String(spec[1]), spec[2], str(int(pv[k])), str(int(st[k])),
			("(+%d/%d)" % [delta, mx]) if mx > 0 else "(+%d)" % delta, is_max])
	for i in rows.size():
		var y := 300.0 + i * 34.0
		var nm2 := Label.new(); nm2.text = String(rows[i][0])
		nm2.add_theme_font_size_override("font_size", 21); nm2.add_theme_color_override("font_color", rows[i][1])
		nm2.position = Vector2(48, y); nm2.size = Vector2(96, 28); win.add_child(nm2)
		var bv := Label.new(); bv.text = String(rows[i][2])
		bv.add_theme_font_size_override("font_size", 21); bv.add_theme_color_override("font_color", Color(0.35, 0.26, 0.12))
		bv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		bv.position = Vector2(140, y); bv.size = Vector2(78, 28); win.add_child(bv)
		var ar := _atlas_sprite("common_ui", "common_btn_arrow2", cm, 0.6)
		if ar:
			ar.position = Vector2(240, y + 14); win.add_child(ar)
		else:
			var art := Label.new(); art.text = "▶"
			art.add_theme_font_size_override("font_size", 20)
			art.add_theme_color_override("font_color", Color(1.0, 0.78, 0.15))
			art.position = Vector2(226, y); art.size = Vector2(28, 28); win.add_child(art)
		var av := Label.new(); av.text = String(rows[i][3])
		av.add_theme_font_size_override("font_size", 21); av.add_theme_color_override("font_color", Color(0.2, 0.14, 0.05))
		av.position = Vector2(262, y); av.size = Vector2(78, 28); win.add_child(av)
		if String(rows[i][4]) != "":
			var dl := Label.new(); dl.text = String(rows[i][4])

			dl.add_theme_font_size_override("font_size", 17)
			dl.add_theme_color_override("font_color",
				Color(1.0, 0.45, 0.85) if bool(rows[i][5]) else Color(0.45, 0.6, 0.35))
			dl.position = Vector2(338, y + 3); dl.size = Vector2(84, 24); win.add_child(dl)
	if maxed > 0:
		var mb := Label.new(); mb.text = "%dMAX" % maxed
		mb.add_theme_font_size_override("font_size", 22)
		mb.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
		mb.add_theme_color_override("font_outline_color", Color(0.5, 0.15, 0.4, 0.9))
		mb.add_theme_constant_override("outline_size", 4)
		mb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mb.position = Vector2(BW - 110, 268); mb.size = Vector2(90, 28); win.add_child(mb)
	var ok := Button.new(); ok.text = "확인"; ok.size = Vector2(160, 46); ok.position = Vector2((BW - 160) * 0.5, BH - 62)
	ok.pressed.connect(func(): if is_instance_valid(layer): layer.queue_free()); win.add_child(ok)

func _play_fx_spine(path: String, anim: String, center: Vector2, zidx: int, parent: Node = null,
		scale := 1.5) -> void:
	if not ResourceLoader.exists(path):
		return
	var holder := Node2D.new()
	holder.position = center; holder.z_index = zidx; holder.scale = Vector2(scale, scale)
	(parent if is_instance_valid(parent) else self).add_child(holder)
	var inst = load(path).instantiate()
	holder.add_child(inst)
	var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
	if ap and ap.has_animation(anim):
		ap.get_animation(anim).loop_mode = Animation.LOOP_NONE
		ap.play(anim)
		ap.animation_finished.connect(func(_a): if is_instance_valid(holder): holder.queue_free())
	else:
		get_tree().create_timer(2.0).timeout.connect(func(): if is_instance_valid(holder): holder.queue_free())

var _skin_tab := "theme"

func _skin_tab_def(tab_id: String) -> Dictionary:
	if tab_id == "stand":
		return {"key": "stand_skin", "count": STAND_COUNT, "title": "단상"}
	return {"key": "cave_skin", "count": SKIN_COUNT, "title": "테마"}

func _open_skin() -> void:
	_open_backdrop(0.5)
	var vis := _vis()
	var BW := clampf(vis.x - 40.0, 900.0, 1240.0)
	var BH := clampf(vis.y - 36.0, 600.0, 680.0)
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH)
	win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	_overlay.add_child(win)
	var tab := _skin_tab_def(_skin_tab)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(360, 56); tbar.position = Vector2((BW - 360) * 0.5, 12)
	win.add_child(tbar)
	var title := Label.new()
	title.text = String(tab["title"])
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.32, 0.2, 0.05))
	title.position = Vector2((BW - 360) * 0.5, 22); title.size = Vector2(360, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win.add_child(title)
	var xb := TextureButton.new()
	xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 66, 14)
	xb.pressed.connect(_close_overlay)
	win.add_child(xb)
	_skin_grid(win, tab, BW)
	_skin_preview(win, tab, BW, BH)
	_skin_tabs_bar(win, BW, BH)

func _skin_grid(win: Control, tab: Dictionary, bw: float) -> void:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 84)
	scroll.size = Vector2(bw - 320.0, 470.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	var cur := UserDB.get_skin(String(tab["key"]))
	for i in int(tab["count"]):
		grid.add_child(_skin_cell(tab, i, i == cur))

func _skin_cell(tab: Dictionary, index: int, selected: bool) -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(195, 132)
	var frame := _ui_sprite("scene_cave_skin_frame", 195.0 / 241.0)
	frame.position = Vector2(97, 66)
	cell.add_child(frame)
	var thumb := _skin_thumb(_skin_tab, index, 97, 66, 168, 96)
	if thumb: cell.add_child(thumb)
	if selected:
		var hl := NinePatchRect.new()
		hl.texture = load("res://assets/converted/ninepatch_ui/9patch_box_outline.tres")
		hl.patch_margin_left = 14; hl.patch_margin_right = 14
		hl.patch_margin_top = 14; hl.patch_margin_bottom = 14
		hl.modulate = Color(0.45, 1.0, 0.45)
		hl.position = Vector2(6, 6); hl.size = Vector2(183, 120)
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(hl)
	var b := Button.new(); b.flat = true; b.size = Vector2(195, 132)
	b.pressed.connect(func(): _skin_select(String(tab["key"]), index))
	cell.add_child(b)
	return cell

func _skin_thumb(tab_id: String, index: int, cx: float, cy: float, w: float, h: float) -> Node:
	if tab_id == "theme":
		var tr := TextureRect.new()
		var p := BG % (index + 1)
		if ResourceLoader.exists(p):
			tr.texture = load(p)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.clip_contents = true
		tr.size = Vector2(w, h)
		tr.position = Vector2(cx - w / 2.0, cy - h / 2.0)
		return tr
	var nm := "stand_stand%d" % (index + 1)
	var sw: float = maxf(1.0, float(_stand_manifest.get(nm, {}).get("w", 305)))
	var spr := _atlas_sprite("stand_ui", nm, _stand_manifest, w / sw)
	spr.position = Vector2(cx, cy)
	return spr

func _skin_preview(win: Control, tab: Dictionary, bw: float, bh: float) -> void:
	var cur := UserDB.get_skin(String(tab["key"]))
	var px := bw - 288.0
	var frame := _ui_sprite("scene_cave_skin_frame", 1.0)
	frame.position = Vector2(px + 128.0, 190.0)
	win.add_child(frame)
	var thumb := _skin_thumb(_skin_tab, cur, px + 128.0, 190.0, 224, 150)
	if thumb: win.add_child(thumb)
	var info := Label.new()
	info.text = "%s  %d / %d" % [String(tab["title"]), cur + 1, int(tab["count"])]
	info.add_theme_font_size_override("font_size", 24)
	info.add_theme_color_override("font_color", Color(0.32, 0.2, 0.05))
	info.position = Vector2(px, 300); info.size = Vector2(256, 32)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win.add_child(info)
	var desc := Label.new()
	desc.text = "선택하면 동굴에 바로 적용됩니다.\n(오프라인 — 전 스킨 사용 가능)"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 18)
	desc.add_theme_color_override("font_color", Color(0.4, 0.3, 0.12))
	desc.position = Vector2(px, 340); desc.size = Vector2(256, 90)
	win.add_child(desc)

func _skin_tabs_bar(win: Control, bw: float, bh: float) -> void:
	var defs := [["theme", "scene_cave_skin", "테마"], ["stand", "scene_cave_tap_button_stand", "단상"]]
	var spacing := 200
	var startx := int(bw * 0.5) - (defs.size() - 1) * spacing / 2
	var y := int(bh - 70.0)
	for i in defs.size():
		var d = defs[i]
		_skin_tab_button(win, String(d[0]), String(d[1]), String(d[2]), startx + i * spacing, y, String(d[0]) == _skin_tab)

func _skin_tab_button(win: Control, tab_id: String, icon: String, label: String, cx: int, y: int, active: bool) -> void:
	var spr := _ui_sprite(icon, 1.3)
	spr.position = Vector2(cx, y)
	if not active: spr.modulate = Color(0.55, 0.55, 0.55, 0.8)
	win.add_child(spr)
	var lbl := Label.new(); lbl.text = label
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(0.3, 0.18, 0.03) if active else Color(0.5, 0.44, 0.32))
	lbl.position = Vector2(cx - 50, y + 42); lbl.size = Vector2(100, 30)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win.add_child(lbl)
	var b := Button.new(); b.flat = true
	b.position = Vector2(cx - 55, y - 45); b.size = Vector2(110, 120)
	b.pressed.connect(func():
		if tab_id != _skin_tab:
			_skin_tab = tab_id
			_open_skin())
	win.add_child(b)

func _skin_select(key: String, index: int) -> void:
	UserDB.set_skin(key, index)
	_refresh()
	_open_skin()

func _close_overlay() -> void:
	if _overlay: _overlay.queue_free(); _overlay = null
	if _overlay_layer: _overlay_layer.queue_free(); _overlay_layer = null
	if is_instance_valid(_bottom_bar): _bottom_bar.visible = true
	if is_instance_valid(_left_wall): _left_wall.visible = true

func _overlay_canvas() -> CanvasLayer:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 10
	add_child(_overlay_layer)
	return _overlay_layer

func _open_backdrop(alpha: float) -> void:
	_close_overlay()
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0, 0, 0, alpha)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_canvas().add_child(_overlay)

func _center_win(win: Control, w1080: float, h1080: float) -> void:
	var vis := _vis()
	win.scale = Vector2(S1080, S1080)
	win.position = Vector2((vis.x - w1080 * S1080) / 2.0, (vis.y - h1080 * S1080) / 2.0)

func _make_overlay(title: String) -> VBoxContainer:
	_open_backdrop(0.78)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(1200, 920)
	_overlay.add_child(box)
	_center_win(box, 1200, 920)
	var head := HBoxContainer.new()
	var t := Label.new(); t.text = title; t.add_theme_font_size_override("font_size", 40)
	head.add_child(t)
	var close := Button.new(); close.text = "  닫기 ✕  "
	close.pressed.connect(_close_overlay)
	head.add_child(close)
	box.add_child(head)
	return box

const DEX_ELEMENTS := ["all", "fire", "aqua", "earth", "wind", "light", "dark", "holy", "chaos", "shadow"]
const DEX_ELE_ICON := {
	"all": "item_item_small_ele_all", "fire": "item_item_small_ele_fire", "aqua": "item_item_small_ele_water",
	"earth": "item_item_small_ele_ground", "wind": "item_item_small_ele_wind", "light": "item_item_small_ele_light",
	"dark": "item_item_small_ele_dark", "holy": "item_item_small_ele_holy", "chaos": "item_item_small_ele_chaos",
	"shadow": "item_item_small_ele_shadow"}
const DEX_ORDER := ["egg", "baby", "child", "adult", "aura", "awaken"]
const DEX_STEP_KR := ["알", "해치", "해츨링", "성체", "오라성체", "각성"]
const DEX_TYPE_KR := {"hp": "체력형", "atk": "공격형", "def": "방어형",
	"ha": "체공형", "hd": "체방형", "ad": "공방형"}

var _dex_element := "all"
var _dex_selected := -1
var _dex_step_sel := -1
var _dex_id_list: Array = []
var _dex_sc: ScrollContainer
var _dex_grid_node: Control
var _dex_cards := {}
var _dex_panel: Control
var _dex_count_lbl: Label
var _dex_ele_btns: Array = []
var _dex_ring: Node2D

func _open_collection_result() -> void:
	_close_overlay()
	var vis := _vis()
	var totals := {}; var owned := {}
	for k in Data.dragon_ids():
		var el := str((Data.get_dragon(k) as Dictionary).get("element", ""))
		if el == "": continue
		totals[el] = int(totals.get(el, 0)) + 1
	var seen_ids := {}
	for od in UserDB.dragons():
		var did := int((od as Dictionary).get("id", 0))
		if seen_ids.has(did): continue
		seen_ids[did] = true
		var el := str((Data.get_dragon(did)).get("element", ""))
		if el != "": owned[el] = int(owned.get(el, 0)) + 1
	var elems: Array = _ELEM_KR.keys().filter(func(e): return totals.has(e))
	var rewards: Dictionary = Data.collection_rewards() if Data.has_method("collection_rewards") else {}
	const BW := 660.0
	const BH := 540.0
	var layer := CanvasLayer.new(); layer.layer = 76; add_child(layer)
	var back := func():
		layer.queue_free()
		_open_dex()
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: back.call()); layer.add_child(dim)
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5)); layer.add_child(win)
	var tbar := NinePatchRect.new(); tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(300, 52); tbar.position = Vector2((BW - 300) * 0.5, 12); win.add_child(tbar)
	var tl := Label.new(); tl.text = "수집 도감"
	tl.add_theme_font_size_override("font_size", 26); tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; tl.size = tbar.size; tbar.add_child(tl)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 58, 14); xb.pressed.connect(back); win.add_child(xb)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(24, 76); scroll.size = Vector2(BW - 48, BH - 96)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; win.add_child(scroll)
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 8); vb.custom_minimum_size.x = BW - 66; scroll.add_child(vb)
	for el in elems:
		var ownc := int(owned.get(el, 0)); var totc := int(totals.get(el, 0))
		var done := ownc >= totc
		var row := NinePatchRect.new(); row.texture = load("res://assets/converted/ninepatch_ui/9patch_text_box.tres")
		row.patch_margin_left = 14; row.patch_margin_top = 14; row.patch_margin_right = 14; row.patch_margin_bottom = 14
		row.custom_minimum_size = Vector2(BW - 66, 78); vb.add_child(row)
		var nm := Label.new(); nm.text = "%s 속성" % _ELEM_KR.get(el, el)
		nm.add_theme_font_size_override("font_size", 20); nm.add_theme_color_override("font_color", Color(0.25, 0.18, 0.08))
		nm.position = Vector2(18, 10); row.add_child(nm)
		var pbg := ColorRect.new(); pbg.color = Color(0, 0, 0, 0.18); pbg.position = Vector2(18, 42); pbg.size = Vector2(300, 20); row.add_child(pbg)
		var pfill := ColorRect.new(); pfill.color = (Color(0.3, 0.8, 0.4) if done else Color(0.9, 0.7, 0.25))
		pfill.position = Vector2(18, 42); pfill.size = Vector2(300.0 * (float(ownc) / maxf(1.0, totc)), 20); row.add_child(pfill)
		var pl := Label.new(); pl.text = "%d / %d" % [ownc, totc]
		pl.add_theme_font_size_override("font_size", 15); pl.add_theme_color_override("font_color", Color.WHITE)
		pl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8)); pl.add_theme_constant_override("outline_size", 3)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; pl.position = Vector2(18, 44); pl.size = Vector2(300, 18); row.add_child(pl)
		var rw: Dictionary = rewards.get(el, {})
		var rlbl := Label.new()
		if rw.is_empty():
			rlbl.text = "보상 미정(유실)"
			rlbl.add_theme_color_override("font_color", Color(0.6, 0.5, 0.4))
		else:
			rlbl.text = "보상: %s ×%d" % [Data.item_name(str(rw.get("item", ""))), int(rw.get("count", 1))]
			rlbl.add_theme_color_override("font_color", Color(0.85, 0.55, 0.15) if done else Color(0.5, 0.45, 0.4))
		rlbl.add_theme_font_size_override("font_size", 16)
		rlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; rlbl.position = Vector2(BW - 66 - 220, 28); rlbl.size = Vector2(200, 22); row.add_child(rlbl)

const DEX_CELL_W := 120.0
const DEX_BTN := Vector2(115, 130)
const DEX_ROW_Y := [10.0, 140.0, 270.0]

func _open_dex() -> void:
	_close_overlay()
	_open_backdrop(0.0)
	if is_instance_valid(_bottom_bar): _bottom_bar.visible = false
	if is_instance_valid(_left_wall): _left_wall.visible = false
	var vis := _vis()
	var W := vis.x - 20.0
	var H := vis.y - 150.0
	var win := Control.new()
	win.position = Vector2(10, 10)
	win.size = Vector2(W, H)
	_overlay.add_child(win)
	var np := AtlasUI.nine("ninepatch_ui", "9patch_popup4", Vector2(W, H), Rect2(130, 190, 40, 58))
	if np: win.add_child(np)
	var title := _book_label("도감", 1.2)
	_book_center(title, Vector2(W * 0.5, 45.0))
	win.add_child(title)
	_dex_count_lbl = _book_label("", 0.9)
	_dex_count_lbl.position = Vector2(50, 58)
	win.add_child(_dex_count_lbl)
	var gw := W - 430.0
	var gbox := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box", Vector2(gw, 420), Rect2(65, 65, 6, 6))
	if gbox:
		gbox.position = Vector2(40, H - 460.0)
		win.add_child(gbox)
	_dex_build_grid(win, Vector2(50, H - 455.0), Vector2(gw - 20.0, 410.0))
	_dex_panel = Control.new()
	_dex_panel.position = Vector2(W - 380.0, H - 470.0)
	_dex_panel.size = Vector2(350, 430)
	win.add_child(_dex_panel)
	var xs := AtlasUI.spr("common_ui", "common_close_btn", Design.ASSET_SCALE * 1.5)
	xs.position = Vector2(W - 50.0, 50.0)
	win.add_child(xs)
	var xb := Button.new(); xb.flat = true
	xb.size = Vector2(64, 64); xb.position = Vector2(W - 82.0, 18.0)
	xb.pressed.connect(_close_overlay); win.add_child(xb)
	AtlasUI.frame_button(win, "수집 보상", Vector2(180.0, 44.0), Vector2(110, 40), _open_collection_result)
	_dex_build_element_row()
	_dex_refresh_count()
	_dex_reset_panel()

func _dex_ids() -> Array:
	var ids: Array = Data.dragon_ids()
	for hid in Data.dragon_ids_hidden():
		if UserDB.dex_step(int(hid)) > 0:
			ids.append(hid)
	ids.sort()
	var out := []
	for id in ids:
		if _dex_element == "all" or str(Data.get_dragon(id).get("element", "")) == _dex_element:
			out.append(id)
	return out

func _book_label(txt: String, scale: float, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = txt
	_lvup_bm_style(l, int(round(19.0 * Design.ASSET_SCALE * scale)), col, "font_subtitle")
	return l

func _book_center(l: Label, c: Vector2, w := 400.0) -> void:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(w, 40)
	l.position = c - l.size * 0.5

func _dex_refresh_count() -> void:
	if not is_instance_valid(_dex_count_lbl): return
	var done := 0
	for id in _dex_id_list:
		if UserDB.dex_step(int(id)) > 4:
			done += 1
	_dex_count_lbl.text = "%d / %d" % [done, _dex_id_list.size()]

func _dex_build_grid(win: Control, pos: Vector2, sz: Vector2) -> void:
	_dex_id_list = _dex_ids()
	_dex_cards = {}
	var sc := ScrollContainer.new()
	sc.position = pos
	sc.custom_minimum_size = sz; sc.size = sz
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.add_child(sc)
	_dex_sc = sc
	var grid := Control.new()
	var cols: int = int(ceil(_dex_id_list.size() / 3.0))
	grid.custom_minimum_size = Vector2(cols * DEX_CELL_W, sz.y)
	sc.add_child(grid)
	_dex_grid_node = grid
	sc.get_h_scroll_bar().value_changed.connect(func(_v): _dex_update_visible())
	sc.get_h_scroll_bar().modulate.a = 0.0
	_dex_update_visible()

func _dex_update_visible() -> void:
	if not is_instance_valid(_dex_grid_node) or not is_instance_valid(_dex_sc):
		return
	var scroll_x := float(_dex_sc.scroll_horizontal)
	var view_w := _dex_sc.size.x
	var first_col := maxi(0, int(scroll_x / DEX_CELL_W) - 2)
	var last_col := int((scroll_x + view_w) / DEX_CELL_W) + 2
	var to_free: Array = []
	for i in _dex_cards.keys():
		var col: int = i / 3
		if col < first_col or col > last_col:
			to_free.append(i)
	for i in to_free:
		var c = _dex_cards[i]
		if is_instance_valid(c): c.queue_free()
		_dex_cards.erase(i)
	for col in range(first_col, last_col + 1):
		for row in 3:
			var i: int = col * 3 + row
			if i >= _dex_id_list.size() or _dex_cards.has(i):
				continue
			var card := _dex_card(int(_dex_id_list[i]))
			card.position = Vector2(col * DEX_CELL_W + 2.5, DEX_ROW_Y[row])
			_dex_grid_node.add_child(card)
			_dex_cards[i] = card

func _dex_refresh_card(id: int) -> void:
	var i := _dex_id_list.find(id)
	if i < 0 or not _dex_cards.has(i):
		return
	var old = _dex_cards[i]
	var p: Vector2 = old.position
	if is_instance_valid(old): old.queue_free()
	var card := _dex_card(id)
	card.position = p
	_dex_grid_node.add_child(card)
	_dex_cards[i] = card

func _dex_card(id: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = DEX_BTN; c.size = DEX_BTN
	var step := UserDB.dex_step(id)
	var bgkey := "scene_cave_dragonbg_nomal"
	if id == _dex_selected: bgkey = "scene_cave_dragonbg_select"
	elif step >= 6: bgkey = "scene_cave_dragonbg_evolution"
	elif step == 5: bgkey = "scene_cave_dragonbg_master"
	var bg := AtlasUI.nine("cave_ui", bgkey, DEX_BTN)
	if bg: c.add_child(bg)
	var box := AtlasUI.nine("cave_ui", "scene_cave_dragon_box", Vector2(100, 100))
	if box:
		box.position = Vector2(7.5, 6)
		c.add_child(box)
	var stage := String(DEX_ORDER[clampi(step, 1, 6) - 1])
	var spr := _dex_stage_sprite_fit(id, stage, 96.0)
	if spr:
		spr.position = Vector2(57.5, 56)
		if step == 0:
			spr.modulate = Color(0.32, 0.32, 0.35, 1)
		c.add_child(spr)
	_dex_bulbs(c, id, step)
	var b := Button.new(); b.flat = true; b.size = DEX_BTN
	b.pressed.connect(func(): _dex_on_click_dragon(id))
	c.add_child(b)
	return c

func _dex_bulbs(c: Control, id: int, step: int) -> void:
	var has_awaken := bool(Data.dragon_dex_meta(id).get("evo", false))
	var bsz := AtlasUI.size_pt("cave_ui", "scene_cave_lightbulb_bg")
	var shift := 0.0 if has_awaken else 8.0
	var n := 6 if has_awaken else 5
	for i in n:
		var p := Vector2((bsz.x + 2.0) * i + bsz.x * 0.5 + 8.0 + shift,
			DEX_BTN.y - 11.0 - bsz.y * 0.5)
		var dot := AtlasUI.spr("cave_ui", "scene_cave_lightbulb_bg", Design.ASSET_SCALE)
		dot.position = p
		c.add_child(dot)
		if i < step:
			var on := AtlasUI.spr("cave_ui",
				"scene_cave_lightbulb2" if step >= 6 else "scene_cave_lightbulb", Design.ASSET_SCALE)
			on.position = p
			c.add_child(on)

func _dex_on_click_dragon(id: int) -> void:
	if _dex_selected == id:
		return
	var prev := _dex_selected
	_dex_selected = id
	if prev != -1: _dex_refresh_card(prev)
	_dex_refresh_card(id)
	_dex_fill_panel()

func _dex_reset_panel() -> void:
	_dex_step_sel = -1
	if not is_instance_valid(_dex_panel):
		return
	for ch in _dex_panel.get_children():
		_dex_panel.remove_child(ch)
		ch.queue_free()
	_dex_build_strip(-1, 0, 6)
	var tb := AtlasUI.nine("ninepatch_ui", "9patch_text_box", Vector2(340, 125), Rect2(25, 25, 3, 3))
	if tb:
		tb.position = Vector2(5, 305)
		_dex_panel.add_child(tb)

func _dex_fill_panel() -> void:
	_dex_step_sel = -1
	if not is_instance_valid(_dex_panel):
		return
	for pch in _dex_panel.get_children():
		_dex_panel.remove_child(pch)
		pch.queue_free()
	var id := _dex_selected
	if id < 0:
		return
	var d: Dictionary = Data.get_dragon(id)
	var step := UserDB.dex_step(id)
	var slots := 6 if bool(Data.dragon_dex_meta(id).get("evo", false)) else 5
	var nm := _book_label(String(d.get("name", "?")), 1.0)
	_book_center(nm, Vector2(175, 8), 340)
	_dex_panel.add_child(nm)
	var stars := Node2D.new(); stars.name = "stars"; stars.visible = false
	stars.position = Vector2(175, 40)
	var starn := int(d.get("star", 0))
	var ssz := AtlasUI.size_pt("common_ui", "common_eggclass")
	for i in starn:
		var st := AtlasUI.spr("common_ui", "common_eggclass", Design.ASSET_SCALE)
		st.position = Vector2((i - (starn - 1) * 0.5) * (ssz.x + 2.0), 0)
		stars.add_child(st)
	_dex_panel.add_child(stars)
	var el := str(d.get("element", ""))
	var ei := AtlasUI.spr("item_small_ui", String(DEX_ELE_ICON.get(el, "item_item_small_ele_all")),
		Design.ASSET_SCALE * 0.55)
	ei.position = Vector2(300, 50)
	_dex_panel.add_child(ei)
	var tname := String(DEX_TYPE_KR.get(str(d.get("type", "")), ""))
	if tname != "":
		var fs := int(round(19.0 * Design.ASSET_SCALE * 0.7))
		var tw := maxf(70.0, _lvup_bmfont("font_subtitle").get_string_size(
			tname, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10.0)
		var eih := AtlasUI.size_pt("item_small_ui", String(DEX_ELE_ICON.get(el, "item_item_small_ele_all"))).y * 0.55
		var tag := AtlasUI.nine("ninepatch_ui", "9patch_recall_del", Vector2(tw, 30))
		if tag:
			tag.position = Vector2(300 - tw * 0.5, 50 + eih * 0.5 + 3.0)
			_dex_panel.add_child(tag)
		var tl := _book_label(tname, 0.7)
		_book_center(tl, Vector2(300, 50 + eih * 0.5 + 3.0 + 15.0), 120)
		_dex_panel.add_child(tl)
	var sh := AtlasUI.spr("common_ui", "common_shadow", Design.ASSET_SCALE)
	sh.name = "shadow"
	sh.position = Vector2(175, 215)
	_dex_panel.add_child(sh)
	var subject := Node2D.new(); subject.name = "subject"
	subject.position = Vector2(175, 135)
	_dex_panel.add_child(subject)
	_dex_build_strip(id, step, slots)
	if step >= 1:
		var rf := AtlasUI.spr("common_ui", "common_refresh", Design.ASSET_SCALE)
		rf.position = Vector2(300, 215)
		_dex_panel.add_child(rf)
		var rb := Button.new(); rb.flat = true
		rb.size = Vector2(56, 56); rb.position = Vector2(272, 187)
		rb.pressed.connect(func(): _open_dragon_book_info(_dex_selected))
		_dex_panel.add_child(rb)
	var tb := AtlasUI.nine("ninepatch_ui", "9patch_text_box", Vector2(340, 125), Rect2(25, 25, 3, 3))
	if tb:
		tb.position = Vector2(5, 305)
		_dex_panel.add_child(tb)
	var tsc := ScrollContainer.new()
	tsc.position = Vector2(15, 315); tsc.size = Vector2(320, 105)
	tsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dex_panel.add_child(tsc)
	var com := Data.dragon_comment(id)
	var cl := Label.new()
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cl.custom_minimum_size = Vector2(300, 0)
	_lvup_bm_style(cl, int(round(17.0 * Design.ASSET_SCALE * 0.8)), Color8(129, 67, 29), "font_common")
	if com != "":
		cl.text = com
	else:
		cl.text = "(도감 설명 데이터 미복원: 서버 유실)"
	tsc.add_child(cl)
	_dex_pick_step(maxi(0, mini(step, slots) - 1))

func _dex_build_strip(id: int, step: int, slots: int) -> void:
	var view_w := 315.0 if (slots == 6 and id >= 0) else 343.0
	var clipbox := Control.new()
	clipbox.name = "strip"
	clipbox.position = Vector2(6, 231.5)
	clipbox.size = Vector2(view_w, 68.5)
	clipbox.clip_contents = true
	_dex_panel.add_child(clipbox)
	var inner := Control.new()
	inner.size = Vector2(415, 68.5)
	clipbox.add_child(inner)
	var bsz := AtlasUI.size_pt("cave_ui", "scene_cave_dragon_bg2")
	for i in slots:
		var cx := (bsz.x + 3.0) * i + (bsz.x + 6.0) * 0.5 - 4.0
		var boxroot := Node2D.new()
		boxroot.name = "slot%d" % i
		boxroot.position = Vector2(cx, 34.25)
		inner.add_child(boxroot)
		var bg := AtlasUI.spr("cave_ui", "scene_cave_dragon_bg2", Design.ASSET_SCALE)
		boxroot.add_child(bg)
		if id >= 0:
			var man := AtlasUI.manifest("portrait_%d" % id)
			var frame := _dex_stage_frame(id, String(DEX_ORDER[i]))
			if i == 0 and man.has("dragon_dragon_%d_egg_small" % id):
				frame = "dragon_dragon_%d_egg_small" % id
			var info: Dictionary = man.get(frame, {})
			var fw := maxf(1.0, float(info.get("w", 72)))
			var fh := maxf(1.0, float(info.get("h", 72)))
			var cap := (0.55 if i == 0 else 0.6) * Design.ASSET_SCALE
			var fit := minf(cap, minf((bsz.x - 8.0) / fw, (bsz.y - 8.0) / fh))
			var th := _atlas_sprite("portrait_%d" % id, frame, man, fit)
			th.position = Vector2(0, -2.0)
			if i >= step:
				th.modulate = Color(0.32, 0.32, 0.34, 1)
			boxroot.add_child(th)
		var cover := AtlasUI.spr("cave_ui", "scene_cave_dragon_cover2", Design.ASSET_SCALE)
		boxroot.add_child(cover)
		var fr := AtlasUI.spr("cave_ui", "scene_cave_dragon_frame2", Design.ASSET_SCALE)
		boxroot.add_child(fr)
		var light := AtlasUI.spr("cave_ui", "scene_cave_dragon_bg_light", Design.ASSET_SCALE)
		light.name = "light"
		light.position = Vector2(0, 1)
		light.visible = false
		boxroot.add_child(light)
		if i < step:
			var hb := Button.new(); hb.flat = true
			hb.size = bsz; hb.position = -bsz * 0.5
			var idx := i
			hb.pressed.connect(func(): _dex_pick_step(idx))
			boxroot.add_child(hb)
	if slots == 6 and id >= 0:
		var ar := AtlasUI.spr("common_ui", "common_btn_arrow2", Design.ASSET_SCALE * 1.2)
		ar.position = Vector2(333, 272)
		_dex_panel.add_child(ar)
		var ab := Button.new(); ab.flat = true
		ab.size = Vector2(40, 40); ab.position = Vector2(313, 252)
		ab.pressed.connect(func():
			var strip := _dex_panel.get_node_or_null("strip")
			if strip and strip.get_child_count() > 0:
				var inn: Control = strip.get_child(0)
				var t := create_tween()
				t.tween_property(inn, "position:x", -(415.0 - view_w), 0.25))
		_dex_panel.add_child(ab)

func _dex_pick_step(idx: int) -> void:
	_dex_step_sel = idx
	var id := _dex_selected
	if id < 0 or not is_instance_valid(_dex_panel):
		return
	var step := UserDB.dex_step(id)
	var strip := _dex_panel.get_node_or_null("strip")
	if strip and strip.get_child_count() > 0:
		var inner: Control = strip.get_child(0)
		for slot in inner.get_children():
			var l = slot.get_node_or_null("light")
			if l: l.visible = String(slot.name) == ("slot%d" % idx)
	var stars := _dex_panel.get_node_or_null("stars")
	if stars: stars.visible = (idx == 0 and step >= 1)
	var subject := _dex_panel.get_node_or_null("subject")
	if subject == null:
		return
	for ch in subject.get_children():
		subject.remove_child(ch)
		ch.queue_free()
	var stage := String(DEX_ORDER[clampi(idx, 0, 5)])
	if idx == 0 or step == 0:
		var man := AtlasUI.manifest("portrait_%d" % id)
		var egg := _atlas_sprite("portrait_%d" % id, _dex_stage_frame(id, "egg"), man, Design.ASSET_SCALE)
		if step == 0:
			egg.modulate = Color(0.32, 0.32, 0.35, 1)
		subject.add_child(egg)
	else:
		var sp := _dex_spawn_spine(id, stage, 0.7)
		sp.position = Vector2(0, 15)
		subject.add_child(sp)

func _dex_spawn_spine(id: int, stage: String, scale: float) -> Node2D:
	var suf := stage
	if stage == "aura":
		suf = _aura_spine_stage(id)
	elif stage == "awaken":
		suf = "e" if Icons.spine_scene(id, "e") != "" else "adult"
	var path := Icons.spine_scene(id, suf)
	var holder := Node2D.new()
	holder.scale = Vector2(scale, scale)
	if path != "":
		var inst = (load(path) as PackedScene).instantiate()
		holder.add_child(inst)
		var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		if ap:
			holder.set_meta("ap", ap)
			if ap.has_animation("love"):
				ap.get_animation("love").loop_mode = Animation.LOOP_NONE
			if ap.has_animation("wait"):
				ap.play("wait")
	else:
		var spr := _dex_stage_sprite_fit(id, stage, 180.0 / maxf(0.1, scale))
		if spr:
			spr.position = Vector2(0, -60)
			holder.add_child(spr)
	return holder

func _dex_stage_sprite_fit(id: int, stage: String, box: float) -> Sprite2D:
	if box <= 0.0:
		return null
	var dir := "portrait_%d" % id
	var man := AtlasUI.manifest(dir)
	var frame := _dex_stage_frame(id, stage)
	var info: Dictionary = man.get(frame, {})
	var w := maxf(1.0, float(info.get("w", 72)))
	var h := maxf(1.0, float(info.get("h", 72)))
	return _atlas_sprite(dir, frame, man, minf(box / w, box / h))

func _dex_build_element_row() -> void:
	_dex_ele_btns = []
	_dex_ring = null
	var vis := _vis()
	var bgw := AtlasUI.size_pt("common_ui", "common_element_bg").x
	for i in DEX_ELEMENTS.size():
		var el := String(DEX_ELEMENTS[i])
		var root := Node2D.new()
		root.position = Vector2((bgw * 1.2 + 10.0) * i + 190.0, vis.y - 70.0)
		_overlay.add_child(root)
		var bg := AtlasUI.spr("common_ui", "common_element_bg", Design.ASSET_SCALE * 1.3)
		root.add_child(bg)
		var ic := AtlasUI.spr("item_small_ui", String(DEX_ELE_ICON[el]),
			Design.ASSET_SCALE * 0.64 * 1.3)
		ic.position = Vector2(0, -2.6)
		root.add_child(ic)
		var hw := bgw * 1.3
		var hit := Button.new(); hit.flat = true
		hit.size = Vector2(hw, hw); hit.position = Vector2(-hw * 0.5, -hw * 0.5)
		hit.pressed.connect(func(): _dex_on_click_element(el, root))
		root.add_child(hit)
		_dex_ele_btns.append(root)
		if el == _dex_element:
			_dex_attach_ring(root)

func _dex_attach_ring(root: Node2D) -> void:
	if is_instance_valid(_dex_ring):
		_dex_ring.queue_free()
	_dex_ring = Node2D.new()
	_dex_ring.z_index = -1
	var s := AtlasUI.spr("cave_ui", "scene_cave_attribute_bg", Design.ASSET_SCALE * 0.86 * 1.3)
	_dex_ring.add_child(s)
	root.add_child(_dex_ring)

func _dex_on_click_element(el: String, root: Node2D) -> void:
	if _dex_element == el:
		return
	_dex_element = el
	_dex_attach_ring(root)
	_dex_selected = -1
	_dex_id_list = _dex_ids()
	for i in _dex_cards.keys():
		var c = _dex_cards[i]
		if is_instance_valid(c): c.queue_free()
	_dex_cards = {}
	if is_instance_valid(_dex_grid_node) and is_instance_valid(_dex_sc):
		var cols: int = int(ceil(_dex_id_list.size() / 3.0))
		_dex_grid_node.custom_minimum_size = Vector2(cols * DEX_CELL_W, _dex_sc.size.y)
		_dex_sc.scroll_horizontal = 0
	_dex_update_visible()
	_dex_refresh_count()
	_dex_reset_panel()

func _open_dragon_book_info(id: int) -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 45; add_child(layer)
	var ui := Control.new(); ui.size = vis; layer.add_child(ui)
	var bgt := TextureRect.new()
	bgt.texture = load(BG % (UserDB.get_skin("cave_skin") + 1))
	bgt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bgt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bgt.size = vis
	ui.add_child(bgt)
	var wman := AtlasUI.manifest("wall_ui")
	var wn := _wall_number_for_theme()
	var ws := 692.0 / 519.0
	var wroot := Node2D.new(); ui.add_child(wroot)
	var lw_i: Dictionary = wman.get("scene_cave_wall_%d_wall_left" % wn, {})
	var lw := _atlas_sprite("wall_ui", "scene_cave_wall_%d_wall_left" % wn, wman, ws)
	lw.position = Vector2(-110.0 + float(lw_i.get("w", 0)) * ws * 0.5, vis.y * 0.5 - 2.0)
	wroot.add_child(lw)
	var rw_i: Dictionary = wman.get("scene_cave_wall_%d_wall_right" % wn, {})
	var rw := _atlas_sprite("wall_ui", "scene_cave_wall_%d_wall_right" % wn, wman, ws)
	rw.position = Vector2(vis.x + 100.0 - float(rw_i.get("w", 0)) * ws * 0.5, vis.y * 0.5 - 2.0)
	wroot.add_child(rw)
	var bw_i: Dictionary = wman.get("scene_cave_wall_%d_wall_bottom" % wn, {})
	var bw := _atlas_sprite("wall_ui", "scene_cave_wall_%d_wall_bottom" % wn, wman, ws)
	bw.position = Vector2(vis.x * 0.5, vis.y + 2.0 - float(bw_i.get("h", 0)) * ws * 0.5)
	wroot.add_child(bw)
	var si: int = UserDB.get_skin("stand_skin") % STAND_COUNT
	var skey := "stand_stand%d" % (si + 1)
	var sinfo: Dictionary = _stand_manifest.get(skey, {})
	var stand := _atlas_sprite("stand_ui", skey, _stand_manifest, Design.ASSET_SCALE * 1.1)
	stand.position = Vector2(vis.x * 0.5,
		vis.y * 0.5 + 220.0 - float(sinfo.get("h", 0)) * Design.ASSET_SCALE * 1.1 * 0.5)
	ui.add_child(stand)
	var sh := AtlasUI.spr("common_ui", "common_shadow", Design.ASSET_SCALE * 1.75)
	sh.position = Vector2(vis.x * 0.5, vis.y * 0.5 + 65.0)
	ui.add_child(sh)
	var subject := Node2D.new(); subject.name = "subject"
	subject.position = Vector2(vis.x * 0.5, vis.y * 0.5 + 15.0)
	ui.add_child(subject)
	var tap := Button.new(); tap.flat = true
	tap.size = Vector2(360, 360)
	tap.position = Vector2(vis.x * 0.5 - 180.0, vis.y * 0.5 - 220.0)
	tap.pressed.connect(func(): _dbi_on_tap(subject))
	ui.add_child(tap)
	var step := UserDB.dex_step(id)
	var slots := 6 if bool(Data.dragon_dex_meta(id).get("evo", false)) else 5
	var b3 := AtlasUI.size_pt("common_ui", "common_box3") * 1.1
	for i in slots:
		var cx := vis.x * 0.5 + (b3.x + 40.0) * (i - 2)
		var cy := vis.y - 60.0
		var broot := Node2D.new()
		broot.position = Vector2(cx, cy)
		ui.add_child(broot)
		broot.add_child(AtlasUI.spr("common_ui", "common_box3", Design.ASSET_SCALE * 1.1))
		broot.add_child(AtlasUI.spr("common_ui", "common_box2", Design.ASSET_SCALE * 1.1))
		var th := _dex_stage_sprite_fit(id, String(DEX_ORDER[i]), b3.x - 14.0)
		if th:
			if i >= step:
				th.modulate = Color(0, 0, 0, 1)
			broot.add_child(th)
		var lb := _book_label(String(DEX_STEP_KR[i]), 0.6)
		_book_center(lb, Vector2(0, b3.y * 0.5), 120)
		broot.add_child(lb)
		if i < step:
			var hb := Button.new(); hb.flat = true
			hb.size = b3; hb.position = -b3 * 0.5
			var idx := i
			hb.pressed.connect(func(): _dbi_show(ui, id, idx))
			broot.add_child(hb)
	var xs := AtlasUI.spr("common_ui", "common_close_btn", Design.ASSET_SCALE * 1.05)
	xs.position = Vector2(vis.x - 50.0, 50.0)
	ui.add_child(xs)
	var xb := Button.new(); xb.flat = true
	xb.size = Vector2(64, 64); xb.position = Vector2(vis.x - 82.0, 18.0)
	xb.pressed.connect(func(): layer.queue_free())
	ui.add_child(xb)
	_dbi_show(ui, id, maxi(0, mini(step, slots) - 1))

func _dbi_show(ui: Control, id: int, idx: int) -> void:
	var subject: Node2D = ui.get_node_or_null("subject")
	if subject == null:
		return
	for ch in subject.get_children():
		subject.remove_child(ch)
		ch.queue_free()
	subject.set_meta("is_egg", idx == 0)
	if idx == 0:
		var man := AtlasUI.manifest("portrait_%d" % id)
		var egg := _atlas_sprite("portrait_%d" % id, _dex_stage_frame(id, "egg"), man,
			Design.ASSET_SCALE * 1.5)
		egg.position = Vector2(0, -80)
		subject.add_child(egg)
	else:
		subject.add_child(_dex_spawn_spine(id, String(DEX_ORDER[idx]), 1.1))

func _dbi_on_tap(subject: Node2D) -> void:
	if subject.get_child_count() == 0:
		return
	if bool(subject.get_meta("is_egg", false)):
		var egg: Node2D = subject.get_child(0)
		var base: Vector2 = egg.scale
		var t := create_tween()
		t.tween_property(egg, "scale", base * 1.15, 0.2).set_ease(Tween.EASE_OUT)
		for sk in [-0.05, 0.04, -0.03, 0.01, 0.0]:
			t.tween_property(egg, "skew", float(sk), 0.05)
		t.tween_property(egg, "position:y", egg.position.y - 40.0, 0.12).set_ease(Tween.EASE_OUT)
		t.tween_property(egg, "position:y", egg.position.y, 0.15).set_ease(Tween.EASE_IN)
		t.tween_property(egg, "scale", base, 0.15)
	else:
		var holder: Node2D = subject.get_child(0)
		var ap: AnimationPlayer = holder.get_meta("ap") if holder.has_meta("ap") else null
		if ap and ap.has_animation("love"):
			Bgm.sfx("effect_dragon_love")
			ap.play("love")
			if not ap.animation_finished.is_connected(_on_dragon_anim_finished):
				var cb := func(anim: StringName):
					if anim != "wait" and is_instance_valid(ap) and ap.has_animation("wait"):
						ap.play("wait")
				ap.animation_finished.connect(cb)

func _aura_spine_stage(id: int) -> String:
	return "aura" if ResourceLoader.exists(DRAGON_SCENE % [id, "aura"]) else "adult"

func _aura_frame_or_adult(id: int) -> String:
	var au := "dragon_dragon_%d_box_aura" % id
	return au if AtlasUI.manifest("portrait_%d" % id).has(au) else ("dragon_dragon_%d_box_adult" % id)

func _dex_stage_frame(id: int, stage: String) -> String:
	match stage:
		"egg": return "dragon_dragon_%d_egg" % id
		"baby": return "dragon_dragon_%d_box_baby" % id
		"child": return "dragon_dragon_%d_box_child" % id
		"adult": return "dragon_dragon_%d_box_adult" % id
		"aura":
			return _aura_frame_or_adult(id)
		"awaken":
			var man := AtlasUI.manifest("portrait_%d" % id)
			var ev := "dragon_dragon_%d_box_evolution" % id
			return ev if man.has(ev) else ("dragon_dragon_%d_box_adult" % id)
	return "dragon_dragon_%d_box_adult" % id

const INV_TABS := [
	{"id": "food", "icon": "scene_cave_tap_button_food", "label": "scene_cave_tap_food_KR"},
	{"id": "gear", "icon": "scene_cave_tap_button_item", "label": "scene_cave_tap_item_KR"},
	{"id": "gem", "icon": "scene_cave_tap_button_gem", "label": "scene_cave_tap_gem_KR"},
	{"id": "egg", "icon": "scene_cave_tap_button_egg", "label": "scene_cave_tap_egg_KR"},
	{"id": "skill", "icon": "scene_cave_tap_button_skill", "label": "scene_cave_tap_skill_KR"},
	{"id": "doc", "icon": "scene_cave_tap_button_doc", "label": "scene_cave_tap_doc_KR"},
	{"id": "mtr", "icon": "scene_cave_tap_button_mtr", "label": "scene_cave_tap_mtr_KR"},
	{"id": "etc", "icon": "scene_cave_tap_button_etc", "label": "scene_cave_tap_etc_KR"},
]
const INV_SLOT_W := 144
const INV_SLOT_H := 150
const INV_ROWS := 4
const INV_GRID_W := 1050.0
const INV_GRID_H := 636.0

var _inv_tab := "etc"
var _inv_selected := ""
var _item_manifests: Dictionary = {}
var _inv_detail_box: Control
var _inv_grid_box: Control
var _inv_grid_sc: ScrollContainer
var _inv_cells: Dictionary = {}

const INV_DETAIL_PANEL := Vector2(350, 420)
const INV_DETAIL_DESC_H := 250.0
const INV_DESC_COLOR := Color8(129, 67, 29)
const INV_SKILL_MARK := {
	"tri": "common_skill_triangle_mark",
	"sq": "common_skill_square_mark",
	"cir": "common_skill_circle_mark",
}
const EQUIP_MAIN_COMMENT := {
	"cri": "크리티컬 공격 확률 +%d%%",
	"evd": "상대공격 회피 확률 +%d%%",
	"cure": "행동불능 치유 확률 +%d%%",
	"cri_pow": "크리티컬 파워 증가 +%d%%",
	"pure": "방어 관통 대미지 +%d",
	"awaken_rate": "각성기 게이지 상승률 +%d%%",
	"depure": "방어 관통 대미지 감소 +%d",
	"accuracy": "명중률 +%d%%",
}

func _open_inventory() -> void:
	_open_backdrop(0.55)
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(1780, 930)
	_overlay.add_child(win)
	_center_win(win, 1780, 930)
	var tbar := NinePatchRect.new(); tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(560, 62); tbar.position = Vector2((1780 - 560) * 0.5, 12); win.add_child(tbar)
	var title := Label.new()
	title.text = "가방"
	title.size = tbar.size
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color.WHITE)
	tbar.add_child(title)

	var cap := Label.new()
	cap.text = "%d / %d" % [_inventory_total_count(), _bag_max()]
	cap.position = Vector2(940, 24)
	cap.add_theme_font_size_override("font_size", 24)
	cap.add_theme_color_override("font_color", Color(0.16, 0.12, 0.08))
	win.add_child(cap)
	var exb := Button.new(); exb.text = "확장 +"; exb.size = Vector2(90, 40); exb.position = Vector2(1140, 20)
	exb.pressed.connect(func(): _close_overlay(); _open_bag_expand()); win.add_child(exb)

	var close := TextureButton.new()
	close.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	close.scale = Vector2(1.6, 1.6); close.position = Vector2(1700, 20)
	close.pressed.connect(_close_overlay)
	win.add_child(close)

	_inv_grid_box = Control.new()
	_inv_grid_box.position = Vector2(46, 88)
	_inv_grid_box.size = Vector2(1060, 650)
	win.add_child(_inv_grid_box)

	_inv_detail_box = Control.new()
	_inv_detail_box.position = Vector2(1160, 90)
	_inv_detail_box.size = Vector2(560, 650)
	win.add_child(_inv_detail_box)

	_inventory_refresh_grid()
	_inventory_refresh_detail()
	_inventory_tabs(win)

func _inventory_total_count() -> int:
	var total := 0
	for amount in UserDB.inventory().values():
		total += int(amount)
	return total

func _inventory_refresh_grid() -> void:
	if _inv_grid_box == null:
		return
	var keep_x := int(_inv_grid_sc.scroll_horizontal) if is_instance_valid(_inv_grid_sc) else 0
	for ch in _inv_grid_box.get_children():
		ch.queue_free()
	_inv_cells = {}
	var items := _inventory_items_for_tab(_inv_tab)
	if (_inv_selected == "" or not _inventory_has_item(_inv_selected)) and not items.is_empty():
		_inv_selected = String(items[0])

	var back := AtlasUI.nine("ninepatch_ui", "9patch_scroll_box",
		Vector2(INV_GRID_W, INV_GRID_H), Rect2(65, 65, 6, 6))
	if back:
		back.position = Vector2.ZERO
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_inv_grid_box.add_child(back)

	if items.is_empty():
		var empty := Label.new()
		empty.text = "비어 있음"
		empty.position = Vector2(0, INV_GRID_H * 0.5 - 20.0)
		empty.size = Vector2(INV_GRID_W, 40)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 30)
		empty.add_theme_color_override("font_color", Color(0.95, 0.89, 0.76))
		_inv_grid_box.add_child(empty)
		return

	var sc := ScrollContainer.new()
	sc.position = Vector2(10, 12)
	sc.custom_minimum_size = Vector2(INV_GRID_W - 20.0, INV_ROWS * INV_SLOT_H)
	sc.size = sc.custom_minimum_size
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inv_grid_box.add_child(sc)
	_inv_grid_sc = sc
	sc.get_h_scroll_bar().modulate.a = 0.0

	var grid := Control.new()
	var cols: int = int(ceil(items.size() / float(INV_ROWS)))
	grid.custom_minimum_size = Vector2(cols * INV_SLOT_W, INV_ROWS * INV_SLOT_H)
	sc.add_child(grid)

	for i in items.size():
		var key := String(items[i])
		var cell := _inventory_cell(key)
		cell.position = Vector2((i / INV_ROWS) * INV_SLOT_W, (i % INV_ROWS) * INV_SLOT_H)
		grid.add_child(cell)
	sc.scroll_horizontal = keep_x

func _inventory_cell(key: String) -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(INV_SLOT_W, INV_SLOT_H)

	var frame := NinePatchRect.new()
	frame.texture = _inv_slot_frame(key == _inv_selected)
	frame.patch_margin_left = 22; frame.patch_margin_right = 22
	frame.patch_margin_top = 16; frame.patch_margin_bottom = 16
	frame.position = Vector2(4, 4)
	frame.size = Vector2(INV_SLOT_W - 18, 128)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(frame)
	_inv_cells[key] = frame

	var icon := _inventory_item_icon(key, 84.0)
	if icon:
		icon.position = Vector2((INV_SLOT_W - 18) * 0.5 + 4, 58)
		cell.add_child(icon)
		_inv_egg_grade_fx(key, icon)
		_inventory_grade_badge(cell, key)

	_inventory_master_badge(cell, key)

	var amount := Label.new()
	amount.text = "X %d" % int(UserDB.inventory().get(key, 0))
	amount.position = Vector2(10, 100)
	amount.size = Vector2(INV_SLOT_W - 30, 28)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.add_theme_font_size_override("font_size", 22)
	amount.add_theme_color_override("font_color", Color.WHITE)
	amount.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	amount.add_theme_constant_override("shadow_offset_x", 2)
	amount.add_theme_constant_override("shadow_offset_y", 2)
	cell.add_child(amount)

	var b := Button.new()
	b.flat = true
	b.size = Vector2(158, 136)
	b.pressed.connect(func(): _inventory_select(key))
	cell.add_child(b)
	return cell

func _inventory_grade_badge(cell: Control, key: String) -> void:
	var g := EggItem.grade_of(key)
	if g <= 0:
		return
	var l := Label.new()
	l.text = "+%d" % g
	l.size = Vector2(INV_SLOT_W - 18 - 12, 30)
	l.position = Vector2(4 + 6, 4 + 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", Color8(255, 176, 40))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.0))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(l)

func _inventory_master_badge(cell: Control, key: String) -> void:
	var item := _inventory_item_def(key)
	if String(item.get("category", "")) != "egg":
		return
	var did := int(item.get("dragon_id", 0))
	if did <= 0 or not UserDB.dex_master(did):
		return
	var m := Label.new()
	m.text = "M"
	m.size = Vector2(INV_SLOT_W - 18 - 12, 30)
	m.position = Vector2(4 + 6, 4 + 3)
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	m.add_theme_font_size_override("font_size", 24)
	m.add_theme_color_override("font_color", Color8(245, 222, 16))
	m.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.0))
	m.add_theme_constant_override("outline_size", 6)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(m)

func _inventory_refresh_detail() -> void:
	if _inv_detail_box == null:
		return
	for ch in _inv_detail_box.get_children():
		ch.queue_free()
	if _inv_selected == "" or not _inventory_has_item(_inv_selected):
		var none := Label.new()
		none.text = "아이템 없음"
		none.position = Vector2(0, 220)
		none.size = Vector2(560, 40)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.add_theme_font_size_override("font_size", 28)
		none.add_theme_color_override("font_color", Color(0.24, 0.16, 0.08))
		_inv_detail_box.add_child(none)
		return

	var item := _inventory_item_def(_inv_selected)
	var panel := _inv_detail_panel()
	var lines: Array = []
	match _inventory_tab_for_item(_inv_selected):
		"egg":   lines = _inv_detail_egg(panel, _inv_selected, item)
		"food":  lines = _inv_detail_food(panel, _inv_selected, item)
		"skill": lines = _inv_detail_skill(panel, _inv_selected, item)
		"gear":  lines = _inv_detail_equip(panel, _inv_selected, item)
		_:       lines = _inv_detail_plain(panel, _inv_selected, item)
	_inv_detail_desc(panel, lines)
	_inv_detail_actions(item)

func _inv_detail_panel() -> Control:
	var panel := Control.new()
	panel.name = "item_detail"
	panel.size = INV_DETAIL_PANEL
	panel.position = Vector2((_inv_detail_box.size.x - INV_DETAIL_PANEL.x) * 0.5, 20)
	_inv_detail_box.add_child(panel)
	var sh := AtlasUI.spr("common_ui", "common_shadow", Design.ASSET_SCALE)
	if sh:
		sh.position = Vector2(175, 210)
		panel.add_child(sh)
	return panel

func _inv_detail_name(panel: Control, text: String, col := Color.WHITE) -> void:
	var nm := _book_label(text, 0.8, col)
	_book_center(nm, Vector2(175, 10), 340)
	panel.add_child(nm)

func _inv_detail_art(key: String, mult := 1.0) -> Sprite2D:
	var spr := _inventory_item_icon(key, 100.0)
	if spr == null:
		return null
	var s := Design.ASSET_SCALE * mult
	spr.scale = Vector2(s, s)
	return spr

func _inv_detail_desc(panel: Control, lines: Array) -> void:
	var tb := AtlasUI.nine("ninepatch_ui", "9patch_text_box",
		Vector2(340, INV_DETAIL_DESC_H), Rect2(25, 25, 3, 3))
	if tb:
		tb.position = Vector2(5, 237.5)
		panel.add_child(tb)
	var tsc := ScrollContainer.new()
	tsc.position = Vector2(15, 247.5)
	tsc.size = Vector2(320, INV_DETAIL_DESC_H - 20.0)
	tsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(tsc)
	var tbox := VBoxContainer.new()
	tbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tbox.add_theme_constant_override("separation", 6)
	tsc.add_child(tbox)
	for line in lines:
		if typeof(line) == TYPE_ARRAY:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for part in (line as Array):
				var pl := _inv_desc_label(String((part as Dictionary).get("text", "")),
					(part as Dictionary).get("color", INV_DESC_COLOR), 0.0)
				row.add_child(pl)
			tbox.add_child(row)
			continue
		var txt := String(line.get("text", "")) if typeof(line) == TYPE_DICTIONARY else String(line)
		if txt == "":
			continue
		var col: Color = line.get("color", INV_DESC_COLOR) if typeof(line) == TYPE_DICTIONARY \
			else INV_DESC_COLOR
		tbox.add_child(_inv_desc_label(txt, col, 300.0))

func _inv_desc_label(txt: String, col: Color, wrap_w: float) -> Label:
	var l := Label.new()
	l.text = txt
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if wrap_w > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(wrap_w, 0)
	_lvup_bm_style(l, int(round(17.0 * Design.ASSET_SCALE * 0.8)), col, "font_common")
	return l

func _inv_detail_lines(key: String, item: Dictionary) -> Array:
	var out: Array = [_inventory_item_desc(key, item), String(item.get("desc", ""))]
	var eff := ItemEffect.reward_buff_of(Data.item_effects, key)
	if not eff.is_empty():
		var left := ItemEffect.reward_buff_left(UserDB.reward_buff(), String(eff["axis"]),
			int(Time.get_unix_time_from_system()))
		if left > 0:
			var cur := int(ItemEffect.reward_buff_mult(UserDB.reward_buff(), String(eff["axis"]),
				int(Time.get_unix_time_from_system())))
			out.append("적용 중: %d배 — 남은 시간 %s"
				% [cur, ItemEffect.reward_buff_left_text(left)])
	return out

func _inv_detail_plain(panel: Control, key: String, item: Dictionary) -> Array:
	_inv_detail_name(panel, _inventory_item_name(key))
	var icon := _inv_detail_art(key)
	if icon:
		icon.position = Vector2(175, 130)
		panel.add_child(icon)
	return _inv_detail_lines(key, item)

func _inv_detail_food(panel: Control, key: String, item: Dictionary) -> Array:
	_inv_detail_name(panel, _inventory_item_name(key))
	var icon := _inv_detail_art(key)
	if icon:
		icon.position = Vector2(175, 130)
		panel.add_child(icon)
	var ev = item.get("element")
	var ekey := String(DEX_ELE_ICON.get(String(ev) if typeof(ev) == TYPE_STRING else "", ""))
	if ekey != "":
		var ei := AtlasUI.spr("item_small_ui", ekey, Design.ASSET_SCALE * 0.55)
		if ei:
			ei.position = Vector2(60, 50)
			panel.add_child(ei)
	return _inv_detail_lines(key, item)

func _inv_detail_skill(panel: Control, key: String, item: Dictionary) -> Array:
	_inv_detail_name(panel, _inventory_item_name(key))
	var icon := _inv_detail_art(key, 1.3)
	if icon:
		icon.position = Vector2(175, 130)
		panel.add_child(icon)
	var mark := String(INV_SKILL_MARK.get(String(item.get("subcategory", "")), "common_element_bg"))
	var mk := AtlasUI.spr("common_ui", mark, Design.ASSET_SCALE)
	if mk:
		mk.position = Vector2(60, 50)
		panel.add_child(mk)
	return _inv_detail_lines(key, item)

func _inv_detail_equip(panel: Control, key: String, item: Dictionary) -> Array:
	var S := Design.ASSET_SCALE
	var meta: Dictionary = Equipment.item_key_meta(key)
	var rar := int(meta.get("rarity", 0))
	var col: Color = Icons.rarity_color(rar)
	var bgt := Icons.equip_bg_texture(item)
	if bgt != null and col.a > 0.0:
		var bs := Sprite2D.new()
		bs.texture = bgt
		bs.material = _pma
		bs.scale = Vector2(S * 1.3, S * 1.3)
		bs.modulate = col
		bs.position = Vector2(175, 130)
		panel.add_child(bs)
	var icon := _inv_detail_art(key, 1.3)
	if icon:
		icon.position = Vector2(175, 130)
		panel.add_child(icon)
	var nm := _inventory_item_name(key)
	var enh := int(meta.get("enhance", 0))
	if enh > 0:
		nm += " +%d" % enh
	_inv_detail_name(panel, nm, col if col.a > 0.0 else Color.WHITE)

	var lines: Array = []
	var head: Array = []
	var grades: Array = Data.equipment.get("option", {}).get("grades", [])
	if rar > 0 and rar < grades.size():
		head.append({"text": "[%s]" % String((grades[rar] as Dictionary).get("name", "")),
			"color": col if col.a > 0.0 else INV_DESC_COLOR})
	var bel := int(meta.get("belong", 0))
	if bel > 0:
		head.append({"text": "-%s의 귀속 아이템" % _dragon_label(bel), "color": Color8(255, 67, 29)})
	if not head.is_empty():
		lines.append(head)
	for st: String in (item.get("stat_main", {}) as Dictionary):
		var fmt := String(EQUIP_MAIN_COMMENT.get(st, ""))
		lines.append(fmt % int(item["stat_main"][st]) if fmt != "" \
			else "%s +%d" % [_equip_stat_kr(st), int(item["stat_main"][st])])
	var opts: Array = meta.get("options", [])
	if not opts.is_empty():
		var op: PackedStringArray = []
		for o in opts:
			var ost := String((o as Dictionary).get("stat", ""))
			op.append(Equipment.option_text(_equip_stat_kr(ost), ost,
				int((o as Dictionary).get("value", 0)), Data.equipment, ""))
		lines.append("부가옵션: %s" % " ".join(op))
	if String(item.get("artifact_effect", "")) != "":
		lines.append(String(item["artifact_effect"]))
	if String(item.get("bonus", "")) != "":
		lines.append(String(item["bonus"]))
	var custom_desc := Data.equipment_description(Equipment.parse_item_key(key))
	if custom_desc != "":
		lines.append(custom_desc)
	lines.append(String(item.get("desc", "")))
	return lines

func _starclass_layer(star: int, animate := true) -> Node2D:
	var root := Node2D.new()
	root.name = "starclass"
	if star <= 0:
		return root
	var S := Design.ASSET_SCALE
	var sw := AtlasUI.size_pt("common_ui", "common_eggclass").x
	for i in star:
		var st := AtlasUI.spr("common_ui", "common_eggclass", S)
		if st == null:
			break
		st.position = Vector2(sw * (i - (star - 1) * 0.5), 0)
		root.add_child(st)
		if not animate:
			continue
		st.scale = Vector2.ZERO
		var tw := st.create_tween()
		tw.tween_interval(0.1 * i)
		tw.tween_property(st, "rotation_degrees", 180.0, 0.25).as_relative()
		tw.parallel().tween_property(st, "scale", Vector2(S, S), 0.25)
		tw.tween_property(st, "scale", Vector2(S * 0.9, S * 1.1), 0.1)
		tw.tween_property(st, "scale", Vector2(S * 1.1, S * 0.9), 0.1)
		tw.tween_property(st, "scale", Vector2(S, S), 0.1)
	return root

func _inv_detail_egg(panel: Control, key: String, item: Dictionary) -> Array:
	var S := Design.ASSET_SCALE

	var did := int(item.get("dragon_id", 0))
	var d: Dictionary = Data.get_dragon(did) if did > 0 else {}

	_inv_detail_name(panel, _inventory_item_name(key))

	var star := int(d.get("star", 0))
	if star > 0:
		var sc := _starclass_layer(star)
		sc.position = Vector2(175, 45)
		panel.add_child(sc)

	var egg: Sprite2D = null
	var etex: Texture2D = Icons.dragon_egg_texture(did) if did > 0 else null
	if etex != null:
		egg = Sprite2D.new()
		egg.texture = etex
		egg.material = _pma
		egg.scale = Vector2(S, S)
	else:
		var ipath := String(item.get("icon", ""))
		var islash := ipath.find("/")
		var iw := 0.0
		if islash > 0:
			iw = float(_item_manifest(ipath.substr(0, islash))
				.get(ipath.substr(islash + 1), {}).get("w", 0))
		egg = _inventory_item_icon(key, (iw if iw > 0.0 else 110.0) * S)
	if egg:
		egg.position = Vector2(175, 130)
		panel.add_child(egg)
		_inv_egg_grade_fx(key, egg)

	var el := String(item.get("element", "")) if typeof(item.get("element")) == TYPE_STRING else ""
	var ekey := String(DEX_ELE_ICON.get(el, ""))
	var eih := 0.0
	if ekey != "":
		var ei := AtlasUI.spr("item_small_ui", ekey, S * 0.55)
		if ei:
			ei.position = Vector2(60, 50)
			panel.add_child(ei)
			eih = AtlasUI.size_pt("item_small_ui", ekey).y * 0.55

	var tname := String(DEX_TYPE_KR.get(String(d.get("type", "")), ""))
	if eih > 0.0 and tname != "":
		var fs := int(round(19.0 * S * 0.7))
		var tw := maxf(70.0, _lvup_bmfont("font_subtitle").get_string_size(
			tname, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10.0)
		var tag := AtlasUI.nine("ninepatch_ui", "9patch_recall_del", Vector2(tw, 30))
		if tag:
			tag.position = Vector2(60 - tw * 0.5, 50 + eih * 0.5 + 3.0)
			panel.add_child(tag)
		var tl := _book_label(tname, 0.7)
		_book_center(tl, Vector2(60, 50 + eih * 0.5 + 3.0 + 15.0), 120)
		panel.add_child(tl)

	var lines: Array = []
	if did > 0:
		lines.append(Data.dragon_comment(did))
	else:
		lines.append_array(_inv_detail_lines(key, item))
	lines.append(_inv_egg_grade_text(key))

	return lines

const EGG_GRADE_FX_FRAMES := 6
const EGG_GRADE_FX_DELAY := 0.15

func _inv_egg_grade_fx(key: String, egg: Sprite2D) -> void:
	if EggItem.grade_of(key) <= 0 or egg.texture == null:
		return
	var fx := Sprite2D.new()
	fx.material = _pma
	fx.scale = Vector2(1.2, 1.2)
	fx.z_index = 1
	fx.position = Vector2(0, egg.texture.get_height() * 0.5 - 5.0 / Design.ASSET_SCALE)
	egg.add_child(fx)
	var frames: Array = []
	for i in EGG_GRADE_FX_FRAMES:
		var t := AtlasUI.tex("common_ui", "common_ani_egg_up1_%d" % (i + 1))
		if t != null:
			frames.append(t)
	if frames.is_empty():
		fx.queue_free()
		return
	var idx := {"i": 0}
	var apply := func() -> void:
		var t: Texture2D = frames[int(idx["i"]) % frames.size()]
		fx.texture = t
		fx.offset = Vector2(0, -t.get_height() * 0.5)
		idx["i"] = int(idx["i"]) + 1
	apply.call()
	var tm := Timer.new()
	tm.wait_time = EGG_GRADE_FX_DELAY
	tm.autostart = true
	tm.timeout.connect(apply)
	fx.add_child(tm)

func _inv_egg_grade_text(key: String) -> String:
	var g := EggItem.grade_of(key)
	if g <= 0:
		return ""
	var hg := EggUpgrade.hatch_grade(g, Data.laboratory.get("egg_upgrade", {}))
	if hg <= 0.0:
		return "+%d강" % g
	return "+%d강 — 부화 등급 %.1f 확정" % [g, hg]

func _inv_detail_actions(item: Dictionary) -> void:
	var is_scroll := Loadout.is_skill_scroll(String(item.get("subcategory", "")))
	var is_skill_item := String(item.get("category", "")) == "skill"
	var is_food := String(item.get("category", "")) == "food" \
		and String(item.get("offline", "")) == "impl"
	var use_kind := _consumable_action(_inv_selected, item)
	var is_gear := String(item.get("category", "")) == "gem"
	var is_equip := String(item.get("category", "")) == "equipment"
	var is_egg := String(item.get("category", "")) == "egg"
	var is_gacha_egg := is_egg and EggGacha.is_gacha_egg(item)
	var is_smelt := ItemSmelt.can_smelt(_inv_selected, Data.combine_item)
	if is_equip:
		_build_bag_equip_buttons(_inv_selected)
		return

	var selbg := NinePatchRect.new()
	selbg.texture = load("res://assets/converted/ninepatch_ui/9patch_btn.tres")
	selbg.patch_margin_left = 16; selbg.patch_margin_right = 16
	selbg.patch_margin_top = 16; selbg.patch_margin_bottom = 16
	selbg.position = Vector2(170, 520); selbg.size = Vector2(220, 58)
	selbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inv_detail_box.add_child(selbg)
	var select := Button.new()
	select.flat = true
	if is_gacha_egg:
		select.text = "사용"
	elif is_egg:
		select.text = "부화"
	elif is_smelt:
		select.text = "제련"
	elif is_gear:
		select.text = "장착"
	elif use_kind == "equipopt":
		select.text = "선택"
	elif is_scroll or is_skill_item or is_food or use_kind != "":
		select.text = "사용"
	else:
		select.text = "선택"
	select.position = Vector2(170, 520)
	select.size = Vector2(220, 58)
	select.add_theme_font_size_override("font_size", 28)
	select.add_theme_color_override("font_color", Color.WHITE)
	select.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0, 0.9))
	select.add_theme_constant_override("outline_size", 5)
	if is_gacha_egg:
		var gk2 := _inv_selected
		select.pressed.connect(func(): _open_gacha_egg(gk2))
	elif is_egg:
		var ek := _inv_selected
		select.pressed.connect(func(): _start_hatch(ek))
	elif is_smelt:
		var sk0 := _inv_selected
		select.pressed.connect(func(): _open_smelt(sk0))
	elif is_gear:
		var ik0 := _inv_selected
		select.pressed.connect(func(): _equip_gem_from_bag(ik0))
	elif is_scroll:
		var sk := _inv_selected
		select.pressed.connect(func(): _use_skill_scroll(sk))
	elif is_skill_item:
		var sik := _inv_selected
		select.pressed.connect(func(): _use_skill_item(sik))
	elif is_food:
		var fk := _inv_selected
		select.pressed.connect(func(): _use_food(fk))
	elif use_kind != "":
		var ck := _inv_selected
		var kind := use_kind
		select.pressed.connect(func(): _use_consumable(ck, kind))
	else:
		select.disabled = String(item.get("offline", "")) in ["todo", "stub", "cut", "dummy"]
		select.pressed.connect(func(): _inventory_select(_inv_selected))
	_inv_detail_box.add_child(select)

	var batch_kind := _batch_use_kind(_inv_selected, item)
	if batch_kind != "" and UserDB.item_count(_inv_selected) >= BATCH_USE_N:
		var bbg := NinePatchRect.new()
		bbg.texture = load("res://assets/converted/ninepatch_ui/9patch_btn2.tres")
		bbg.patch_margin_left = 16; bbg.patch_margin_right = 16
		bbg.patch_margin_top = 16; bbg.patch_margin_bottom = 16
		bbg.position = Vector2(170, 586); bbg.size = Vector2(220, 52)
		bbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_inv_detail_box.add_child(bbg)
		var bb := Button.new()
		bb.flat = true
		bb.text = "%d회 사용" % BATCH_USE_N
		bb.position = Vector2(170, 586)
		bb.size = Vector2(220, 52)
		bb.add_theme_font_size_override("font_size", 24)
		bb.add_theme_color_override("font_color", Color.WHITE)
		bb.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0, 0.9))
		bb.add_theme_constant_override("outline_size", 5)
		var bk := _inv_selected
		var bkind := batch_kind
		bb.pressed.connect(func(): _use_batch(bk, bkind, BATCH_USE_N))
		_inv_detail_box.add_child(bb)

func _build_bag_equip_buttons(inv_key: String) -> void:
	var meta := Equipment.item_key_meta(inv_key)
	var rar := int(meta.get("rarity", 0))
	var specs := [
		["강화", Vector2(40, 520), func(): _bag_enhance(inv_key)],
		["옵션 변경", Vector2(300, 520), func(): _bag_reroll(inv_key)],
	]
	for sp in specs:
		var nm := String((sp as Array)[0])
		var at: Vector2 = (sp as Array)[1]
		var bg := NinePatchRect.new()
		bg.texture = load("res://assets/converted/ninepatch_ui/9patch_btn.tres")
		bg.patch_margin_left = 16; bg.patch_margin_right = 16
		bg.patch_margin_top = 16; bg.patch_margin_bottom = 16
		bg.position = at; bg.size = Vector2(220, 58)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if rar < 2:
			bg.modulate = Color(0.62, 0.62, 0.62)
		_inv_detail_box.add_child(bg)
		var b := Button.new()
		b.flat = true
		b.text = nm
		b.position = at
		b.size = Vector2(220, 58)
		b.add_theme_font_size_override("font_size", 26)
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0, 0.9))
		b.add_theme_constant_override("outline_size", 5)
		b.pressed.connect((sp as Array)[2])
		_inv_detail_box.add_child(b)

func _bag_enhance(inv_key: String) -> void:
	var target := ItemEnchantView.target_bag(inv_key, int(_active().get("uid", 0)))
	if target.is_empty():
		_toast("장비가 아닙니다"); return
	var sd := ItemEnchantView.slot_view(target)
	if int(sd.get("grade", 0)) < 2:
		_open_popup_type("강화", Data.ui(ItemWindow.S_GRADE_MIN), func(): pass, "확인", "")
		return
	var why := Equipment.enchant_blocked(sd, Data.equipment)
	if why == "option_max" or why == "grade_max" or why == "min_grade":
		var msg := Data.ui(ItemWindow.S_NO_MORE) if why == "option_max" \
			else (Data.ui(ItemWindow.S_GRADE_MIN) if why == "min_grade" else ItemWindow.S_ENHANCE_MAX)
		_open_popup_type("강화", msg, func(): pass, "확인", "")
		return
	var pop := ItemEnchantView.open(self, target)
	pop.closed.connect(func(): _bag_equip_changed(pop.current_key()))

func _bag_equip_changed(new_key: String) -> void:
	if new_key != "" and UserDB.item_count(new_key) > 0:
		_inv_selected = new_key
	_inventory_refresh_grid()
	_inventory_refresh_detail()
	_refresh_stats()

func _bag_reroll(inv_key: String) -> void:
	var meta := Equipment.item_key_meta(inv_key)
	var grade := int(meta.get("rarity", 0))
	var items: Dictionary = Data.equipment.get("option", {}).get("reroll_items", {})
	var coin := String(items.get(str(grade), ""))
	if coin == "":
		_open_popup_type("옵션 변경", "이 등급의 장신구에 쓸 수 있는 동전이 없습니다.",
			func(): pass, "확인", "")
		return
	if UserDB.item_count(coin) <= 0:
		_open_popup_type("옵션 변경", "%s이(가) 없습니다." % Data.item_name(coin),
			func(): pass, "확인", "")
		return
	_open_popup_type("장비 선택",
		"해당 장비의 부가 옵션을 변경하시겠습니까?\n\n%s  X %d"
			% [Data.item_name(coin), UserDB.item_count(coin)],
		func():
			if not UserDB.use_item(coin, 1):
				return
			var lay := EquipOptionView.open_bag(self, inv_key, coin, grade,
				func(changed: bool):
					_toast("옵션을 변경했습니다" if changed else "기존 옵션을 유지했습니다"))
			lay.finished.connect(func(): _bag_equip_changed(lay.current_key())),
		"확인", "취소")

func _consumable_action(key: String, item: Dictionary) -> String:
	if String(item.get("offline", "")) != "impl":
		return ""
	if Incapacitation.is_cure_item(Data.incapacitation, key):
		return "cure"
	match String(item.get("subcategory", "")):
		"blessing":
			return "levelup"
		"level":
			return "levelup" if key == "level_up" else ("leveldown" if key == "level_down" else "")
		"nest":
			match key:
				"holynest": return "holynest"
				"ascension": return "ascension"
				"bridle": return "bridle"
			return ""
		"qol":
			if key == "dragon_namechange":
				return "rename"
			if key == "namechange":
				return "usernick"
			return ""
		"box":
			if key == "jem_random":
				return "gembox"
			return "lootbox" if BoxLoot.is_box(Data.box_loot, key) else ""
		"key":
			return "lootkey" if BoxLoot.is_key(Data.box_loot, key) else ""
		"buff":
			return "rewardbuff" if not ItemEffect.reward_buff_of(Data.item_effects, key).is_empty() else ""
		"drink":
			return "colosseum_ticket" if key == "drink" else ""
		"slot":
			if EquipPickWindow.reroll_grade_of(key) >= 0:
				return "equipopt"
			match key:
				"gemslot_change": return "gemslot"
				"skillslot_change": return "skillslot"
				"gem_init": return "geminit"
			return ""
	return ""

const S_ANNONCE := "알림"
const S_BAG_MSG3 := "#b05b0596"
const S_BAG_MSG25 := "#fe083355"
const S_SYSTEM_MSG2 := "다이아 %d개를 얻었습니다."

func _bound_equip_count(uid: int) -> int:
	var n := 0
	for k in UserDB.inventory().keys():
		var key := String(k)
		if not key.begins_with(Equipment.ITEM_PREFIX):
			continue
		if Equipment.item_key_belong(key) == uid:
			n += UserDB.item_count(key)
	for s in (UserDB.get_dragon(uid).get("equip", {}).get("slots", []) as Array):
		if int((s as Dictionary).get("belong", 0)) == uid:
			n += 1
	return n

func _purge_bound_equip(uid: int) -> int:
	var doomed: Array[String] = []
	for k in UserDB.inventory().keys():
		var key := String(k)
		if key.begins_with(Equipment.ITEM_PREFIX) and Equipment.item_key_belong(key) == uid:
			doomed.append(key)
	var n := 0
	for key in doomed:
		n += UserDB.item_count(key)
		UserDB.use_item(key, UserDB.item_count(key))
	return n

func _use_consumable(key: String, kind: String) -> void:
	if UserDB.item_count(key) <= 0:
		_toast("보유하지 않은 아이템입니다"); return
	match kind:
		"levelup", "leveldown":
			var d := _active()
			if d.is_empty() or UserDB.is_egg(d):
				_toast("사용할 수 없는 대상입니다")
				return
			_apply_consumable(key, kind, int(d["uid"]))
		"holynest":
			if bool(UserDB.get_pmeta("blessed_nest", false)):
				_toast("이미 둥지에 축복이 걸려 있습니다"); return
			UserDB.use_item(key, 1)
			UserDB.set_pmeta("blessed_nest", true)
			_close_overlay(); _refresh()
			_toast("둥지에 축복을 걸었습니다 — 이후 모든 부화 등급 +0.6 (영구)")
		"gembox":
			var rng := RandomNumberGenerator.new(); rng.randomize()
			var gk := Drops.roll_gem_box(Data.drops, Data.gems, rng)
			if gk == "":
				_toast("젬 데이터가 비어 있습니다"); return
			UserDB.use_item(key, 1)
			UserDB.add_item(gk, 1)
			_inv_tab = "gem"; _inv_selected = gk
			_close_overlay(); _open_inventory()
			_toast("%s 을(를) 얻었습니다!" % Drops.display_name(gk, Data.gems, Data.equipment))
		"lootbox":
			_open_loot_box(key)
		"lootkey":
			_use_loot_key(key)
		"colosseum_ticket":
			var got: Dictionary = Colosseum.add_ticket(1)
			if got.is_empty():
				_toast("이미 입장권이 가득 찼습니다"); return
			UserDB.use_item(key, 1)
			_refresh()
			var parts: PackedStringArray = []
			for m in (Data.colosseum.get("modes", {}) as Dictionary):
				parts.append("%s %d/%d" % [
					String(Colosseum.mode_cfg(String(m)).get("label", "")),
					Colosseum.ticket_of(String(m)), Colosseum.ticket_max()])
			_toast("콜로세움 입장권 +1  (%s)" % " / ".join(parts))
		"usernick":
			_close_overlay()
			RenameDialog.open(self, false, func(nick: String):
				UserDB.use_item(key, 1)
				_refresh()
				_toast("닉네임을 '%s' 으로 바꿨습니다" % nick))
		"gemslot", "skillslot":
			var d := _active()
			if d.is_empty() or UserDB.is_egg(d):
				_toast("사용할 수 없는 대상입니다")
				return
			_apply_consumable(key, kind, int(d["uid"]))
		"rewardbuff":
			var now := int(Time.get_unix_time_from_system())
			var eff := ItemEffect.reward_buff_of(Data.item_effects, key)
			var res := ItemEffect.apply_reward_buff(UserDB.reward_buff(), eff, now)
			if not bool(res.get("ok", false)):
				_toast(String(res.get("reason", "사용할 수 없습니다")))
				return
			UserDB.use_item(key, 1)
			UserDB.set_reward_buff(res["active"])
			var axis := String(eff["axis"])
			var left := ItemEffect.reward_buff_left(res["active"], axis, now)
			_close_overlay(); _open_inventory()
			_toast("%s %d배 — 남은 시간 %s" % ["탐험 경험치" if axis == "exp" else "탐험 골드",
				int(eff["mult"]), ItemEffect.reward_buff_left_text(left)])
		"ascension":
			var ad := _active()
			if ad.is_empty() or UserDB.is_egg(ad):
				_open_popup_type(S_ANNONCE, Data.ui(S_BAG_MSG3), func(): pass, "확인", "")
				return
			if bool(ad.get("locked", false)):
				_open_popup_type(S_ANNONCE, Data.ui(S_BAG_MSG25), func(): pass, "확인", "")
				return
			if UserDB.dragon_count() <= 1:
				_open_popup_type(S_ANNONCE, Data.ui(S_BAG_MSG3), func(): pass, "확인", "")
				return
			var auid := int(ad["uid"])
			ItemDetailView.open_ascension(self, ad, key, _bound_equip_count(auid),
				func(): _apply_consumable(key, "ascension", auid))
		"equipopt":
			EquipPickWindow.create(self, key, func():
				_inventory_refresh_grid()
				_inventory_refresh_detail()
				_refresh_stats())
		"bridle", "rename", "geminit":
			_open_consumable_target(key, kind)

func _open_consumable_target(key: String, kind: String) -> void:
	_close_skill_modal()
	_ensure_skill_modal()
	var titles := {"bridle": "보관할 드래곤",
		"rename": "이름을 바꿀 드래곤",
		"gemslot": "젬 슬롯을 변경할 드래곤", "skillslot": "스킬 슬롯을 변경할 드래곤",
		"geminit": "젬 슬롯을 초기화할 드래곤", "cure": "행동불능을 풀 드래곤"}
	var panel := _skill_modal_panel("%s — %s" % [String(titles.get(kind, "대상")),
		_inventory_item_name(key)])
	var body := _skill_modal_list(panel)
	var owned: Array = UserDB.dragons()
	if owned.is_empty():
		body.add_child(_skill_list_button("(보유 드래곤 없음)", _close_skill_modal))
		return
	for d in owned:
		var uid := int(d["uid"])
		if UserDB.is_egg(d):
			continue
		var ddef := Data.get_dragon(int(d["id"]))
		var txt := "Lv.%d %s" % [int(d["level"]), Icons.name_of(d)]
		if kind in ["gemslot", "geminit"]:
			txt += "   현재 [%s]" % _gem_slot_type_line(d)
		elif kind == "skillslot":
			txt += "   현재 [%s]" % _skill_slot_type_line(d)
		elif kind == "cure":
			if not UserDB.is_down(uid):
				continue
			txt += "   남은 %s" % Incapacitation.remain_text(UserDB.cure_time(uid),
				int(Time.get_unix_time_from_system()))
		if bool(d.get("locked", false)) and kind == "bridle":
			txt += "   (잠김)"
		body.add_child(_skill_list_button(txt, func(): _apply_consumable(key, kind, uid)))
	if kind == "cure" and body.get_child_count() == 0:
		body.add_child(_skill_list_button("(행동불능인 드래곤이 없습니다)", _close_skill_modal))

func _gem_slot_type_line(d: Dictionary) -> String:
	var kr: Dictionary = (Data.gems.get("slot_types", {}) as Dictionary).get("kr", {})
	var out: PackedStringArray = []
	for t in Gem.types(d.get("gems", {})):
		out.append(String(kr.get(String(t), String(t))))
	return "/".join(out)

const _SKILL_SLOT_MARK := {"tri": "△", "sq": "□", "cir": "○", "star": "☆"}

func _skill_slot_type_line(d: Dictionary) -> String:
	var out: PackedStringArray = []
	for t in Loadout.slot_types(d):
		out.append(String(_SKILL_SLOT_MARK.get(String(t), "?")))
	return "/".join(out)

func _ascension_diamond(level: int) -> int:
	return 5 * (1 + int(level / 5.0))

func _open_dragon_storage() -> void:
	_close_skill_modal()
	_ensure_skill_modal()
	var panel := _skill_modal_panel("드래곤 보관소")
	var body := _skill_modal_list(panel)
	var st: Array = UserDB.storage_dragons()
	if st.is_empty():
		body.add_child(_skill_list_button("(보관된 드래곤 없음)", _close_skill_modal))
		return
	for d in st:
		var uid := int(d["uid"])
		var nm := Icons.name_of(d)
		body.add_child(_skill_list_button("Lv.%d %s   → 동굴로 꺼내기" % [int(d["level"]), nm],
			func():
				if UserDB.unstore_dragon(uid):
					UserDB.set_active(uid)
					_close_skill_modal(); _refresh(); _toast("%s 을(를) 꺼냈습니다" % nm)
				else:
					_toast("꺼낼 수 없습니다")))

func _apply_consumable(key: String, kind: String, uid: int) -> void:
	if UserDB.item_count(key) <= 0:
		_close_skill_modal(); _toast("보유하지 않은 아이템입니다"); return
	var d := UserDB.get_dragon(uid)
	if d.is_empty():
		_close_skill_modal(); return
	match kind:
		"cure":
			if not UserDB.is_down(uid):
				_toast("기절 상태가 아닙니다"); return
			UserDB.use_item(key, 1)
			UserDB.set_cure_time(uid, 0)
			_close_skill_modal(); _close_overlay(); _refresh()
			_toast("%s 이(가) 회복했습니다" % Icons.name_of(d))
		"levelup":
			var ddef := Data.get_dragon(int(d["id"]))
			var cap := Growth.level_cap(bool(d.get("awakened", false)))
			if int(d.get("level", 1)) >= cap:
				_toast("이미 최대 레벨입니다 (%d)" % cap); return
			var guarantee := String(_LVUP_GUARANTEE.get(key, ""))
			var roll_cfg: Dictionary = Data.level_curve.get("roll", {})
			var rng := RandomNumberGenerator.new(); rng.randomize()
			var roll := LevelSystem.roll_level(roll_cfg, Growth.tier_growth(ddef, Data.stat_table),
				rng, 0.0, guarantee)
			var old_lv := int(d.get("level", 1))
			var sk_before := UserDB.dragon_skills(uid).size()
			UserDB.level_up_with(uid, roll)
			UserDB.bump_quest("levelups")
			var sk_got := _skills_learned_since(uid, sk_before)
			UserDB.use_item(key, 1)
			UserDB.set_active(uid)
			_close_skill_modal(); _close_overlay(); _refresh_stats(); _refresh()
			var scr := _open_levelup()
			var new_lv := int(UserDB.get_dragon(uid).get("level", 1))
			var slot_new := -1
			for si in Loadout.SLOT_UNLOCK_LEVEL.size():
				if old_lv < int(Loadout.SLOT_UNLOCK_LEVEL[si]) and new_lv >= int(Loadout.SLOT_UNLOCK_LEVEL[si]):
					slot_new = si
			if scr:
				scr.play_fx({"kind": "up", "sp": 1.0, "stage_changed": false,
					"slot_new": slot_new, "triple": bool(roll.get("triple", false))})
			if not sk_got.is_empty():
				_toast("새 스킬 습득 — %s" % ", ".join(sk_got))
		"leveldown":
			if int(d.get("level", 1)) <= 1:
				_toast("레벨 1 미만으로 내릴 수 없습니다"); return
			if not UserDB.level_down(uid):
				_toast("레벨을 내릴 수 없습니다"); return
			UserDB.use_item(key, 1)
			UserDB.set_active(uid)
			_close_skill_modal(); _close_overlay(); _refresh_stats(); _refresh()
			var dscr := _open_levelup()
			Bgm.sfx("effect_level_updown")
			if dscr:
				dscr.word_banner("LEVEL DOWN", 1.4, Color(0.86, 0.66, 1.0), Color(0.24, 0.05, 0.34, 1.0))
		"ascension":
			if bool(d.get("locked", false)) or UserDB.dragon_count() <= 1:
				_open_popup_type(S_ANNONCE,
					Data.ui(S_BAG_MSG25) if bool(d.get("locked", false)) else Data.ui(S_BAG_MSG3),
					func(): pass, "확인", "")
				return
			var dia := _ascension_diamond(int(d.get("level", 1)))
			var nm := Icons.name_of(d)
			var sold := _purge_bound_equip(uid)
			if not UserDB.release_dragon(uid):
				_open_popup_type(S_ANNONCE, Data.ui(S_BAG_MSG3), func(): pass, "확인", "")
				return
			UserDB.use_item(key, 1)
			UserDB.add_currency("diamond", dia)
			_close_skill_modal(); _close_overlay(); _refresh()
			print("[승천] %s(Lv%d) — 다이아 %d · 귀속 장비 %d개 처분"
				% [nm, int(d.get("level", 1)), dia, sold])
			MessageWindow.open(self, S_ANNONCE, S_SYSTEM_MSG2 % dia, func(): pass, "확인", "", 0, dia)
		"bridle":
			if bool(d.get("locked", false)):
				_toast("잠긴 드래곤은 보관할 수 없습니다"); return
			if not UserDB.store_dragon(uid):
				_toast("보관할 수 없습니다 (마지막 드래곤)"); return
			UserDB.use_item(key, 1)
			_close_skill_modal(); _close_overlay(); _refresh()
			_toast("보관소에 넣었습니다 — 동굴 슬롯이 비었습니다")
		"rename":
			UserDB.use_item(key, 1)
			UserDB.set_active(uid)
			_close_skill_modal(); _close_overlay(); _refresh()
			_open_rename()
		"gemslot", "skillslot":
			_close_skill_modal()
			ItemDetailView.open_slot_reset(self,
				"gem" if kind == "gemslot" else "skill", d, key,
				func(): _apply_slot_reset(key, kind, uid))
		"geminit":
			var gf2: Dictionary = d.get("gems", {})
			var n := _return_all_gems(uid, gf2)
			if n <= 0:
				_toast("장착된 젬이 없습니다"); return
			UserDB.use_item(key, 1)
			UserDB.set_active(uid)
			_close_skill_modal(); _close_overlay(); _refresh_stats(); _refresh()
			_toast("드래곤의 젬 슬롯이 초기화되었습니다 — 젬 %d개 반환" % n)

func _apply_slot_reset(key: String, kind: String, uid: int) -> void:
	if UserDB.item_count(key) <= 0:
		_toast("보유하지 않은 아이템입니다"); return
	var d := UserDB.get_dragon(uid)
	if d.is_empty():
		return
	var returned := 0
	if kind == "gemslot":
		returned = _return_all_gems(uid, d.get("gems", {}))
		var nt: Array = Gem.random_types(Data.gems)
		UserDB.set_dragon_field(uid, "gems", Gem.set_types({"types": nt, "slots": []}, nt))
	else:
		UserDB.set_dragon_field(uid, "skill_slots", Loadout.random_slot_types())
		UserDB.set_dragon_field(uid, "skill_equip", [0, 0])
	UserDB.use_item(key, 1)
	UserDB.set_active(uid)
	_refresh_stats(); _refresh()
	var back := func():
		_refresh()
		if is_instance_valid(_overlay):
			_open_inventory()
		if returned > 0:
			_toast("젬 %d개를 가방으로 돌려받았습니다" % returned)
	StatResetView.open(self, uid, "gem" if kind == "gemslot" else "skill", back, _stage)

func _start_hatch(item_key: String) -> void:
	if item_key == "" or UserDB.item_count(item_key) <= 0:
		_toast("알이 없습니다"); return
	var did := _egg_item_to_dragon(item_key)
	if did <= 0:
		_toast("이 알의 부화 대상이 정해지지 않았습니다"); return
	var blessed := bool(UserDB.get_pmeta("blessed_nest", false))
	var ecfg: Dictionary = Data.laboratory.get("egg_upgrade", {})
	var step := EggItem.grade_of(item_key)
	var grade := Hatchery.grade_for(step, ecfg, RNG.randf(), blessed)
	var secs := Hatchery.hatch_seconds(grade)
	UserDB.use_item(item_key, 1)
	var egg := UserDB.add_egg(did, grade, secs, step, {}, blessed)
	UserDB.set_active(int(egg["uid"]))
	_close_overlay()
	_refresh()
	_toast("부화 시작 — 남은 시간 %s%s%s" % [Hatchery.format_remain(secs),
		"  (+%d강 · 등급 %.1f 확정)" % [step, grade] if step > 0 else "",
		"  (둥지 축복 적용)" if blessed else ""])

func _egg_item_to_dragon(item_key: String) -> int:
	return int(_inventory_item_def(item_key).get("dragon_id", 0))

func _open_gacha_egg(item_key: String) -> void:
	if item_key == "" or UserDB.item_count(item_key) <= 0:
		_toast("알이 없습니다"); return
	_confirm_gacha_egg(item_key, func():
		var item: Dictionary = Data.items.get(item_key, {})
		var did := EggGacha.roll(item_key, item, Data.gacha_eggs, Data.dragons, null)
		if did <= 0:
			_toast("이 알의 결과 풀이 비어 있습니다 (data/gacha_eggs.json)"); return
		UserDB.use_item(item_key, 1)
		UserDB.add_item(EggGacha.key_for(did), 1)
		Bgm.sfx("effect_box_peong")
		_show_egg_result(did, item_key))

const BATCH_USE_N := 10

func _batch_use_kind(item_key: String, item: Dictionary) -> String:
	if item_key == "" or item.is_empty():
		return ""
	if String(item.get("category", "")) == "egg" and EggGacha.is_gacha_egg(item):
		return "gacha_egg"
	if _consumable_action(item_key, item) == "gembox":
		return "gembox"
	if _LVUP_GUARANTEE.has(item_key) and _consumable_action(item_key, item) == "levelup":
		return "blessing"
	return ""

func _use_batch(item_key: String, kind: String, n: int) -> void:
	var have := UserDB.item_count(item_key)
	if have < n:
		_toast("%d개 이상 보유해야 %d회 사용할 수 있습니다" % [n, n]); return
	var name := Data.item_name(item_key)
	match kind:
		"gacha_egg":
			_confirm_gacha_egg(item_key, func(): _do_gacha_egg_batch(item_key, n), n)
		"gembox":
			_open_popup_type(name, "상자를 열어보시겠습니까?\n\n%s %d개를 사용합니다." % [name, n],
				func(): _do_gembox_batch(item_key, n))
		"blessing":
			var bd := _active()
			if bd.is_empty() or UserDB.is_egg(bd):
				_toast("사용할 수 없는 대상입니다")
				return
			var bcap := Growth.level_cap(bool(bd.get("awakened", false)))
			var blv := int(bd.get("level", 1))
			if blv >= bcap:
				_toast("이미 최대 레벨입니다 (%d)" % bcap); return
			var bn := mini(n, bcap - blv)
			_open_popup_type(name,
				"선택한 아이템을 사용하시겠습니까?\n\n%s %d개를 사용합니다." % [name, bn],
				func(): _do_blessing_batch(item_key, bn))

func _do_gacha_egg_batch(item_key: String, n: int) -> void:
	if UserDB.item_count(item_key) < n:
		_toast("알이 부족합니다"); return
	var item: Dictionary = Data.items.get(item_key, {})
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var ids: Array = EggGacha.roll_many(item_key, item, Data.gacha_eggs, Data.dragons, rng, n)
	if ids.is_empty():
		_toast("이 알의 결과 풀이 비어 있습니다 (data/gacha_eggs.json)"); return
	UserDB.use_item(item_key, ids.size())
	var agg := {}
	for did in ids:
		var k := EggGacha.key_for(int(did))
		agg[k] = int(agg.get(k, 0)) + 1
		UserDB.add_item(k, 1)
	Bgm.sfx("effect_box_peong")
	var last_key := _highest_star_egg_key(agg.keys())
	_show_batch_result(agg, last_key, "egg", last_key)

func _do_gembox_batch(item_key: String, n: int) -> void:
	if UserDB.item_count(item_key) < n:
		_toast("상자가 부족합니다"); return
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var keys: Array = Drops.roll_gem_box_many(Data.drops, Data.gems, rng, n)
	if keys.is_empty():
		_toast("젬 데이터가 비어 있습니다"); return
	UserDB.use_item(item_key, keys.size())
	var agg := {}
	for k in keys:
		agg[k] = int(agg.get(k, 0)) + 1
		UserDB.add_item(String(k), 1)
	Bgm.sfx("effect_box_peong")
	_show_batch_result(agg, String(keys[keys.size() - 1]), "gem", String(keys[keys.size() - 1]))

func _do_blessing_batch(key: String, n: int) -> void:
	var d := _active()
	if d.is_empty() or UserDB.is_egg(d):
		_toast("사용할 수 없는 대상입니다"); return
	var uid := int(d["uid"])
	var cap := Growth.level_cap(bool(d.get("awakened", false)))
	var old_lv := int(d.get("level", 1))
	var used := mini(mini(n, cap - old_lv), UserDB.item_count(key))
	if used <= 0:
		_toast("이미 최대 레벨입니다 (%d)" % cap); return
	var ddef := Data.get_dragon(int(d["id"]))
	var guarantee := String(_LVUP_GUARANTEE.get(key, ""))
	var roll_cfg: Dictionary = Data.level_curve.get("roll", {})
	var max_stats := Growth.tier_growth(ddef, Data.stat_table)
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var sk_before := UserDB.dragon_skills(uid).size()
	var triple := false
	var done := 0
	for i in used:
		var roll := LevelSystem.roll_level(roll_cfg, max_stats, rng, 0.0, guarantee)
		if not UserDB.level_up_with(uid, roll):
			break
		done += 1
		UserDB.bump_quest("levelups")
		if bool(roll.get("triple", false)):
			triple = true
	if done <= 0:
		_toast("레벨을 올릴 수 없습니다"); return
	var sk_got := _skills_learned_since(uid, sk_before)
	UserDB.use_item(key, done)
	UserDB.set_active(uid)
	_close_overlay(); _refresh_stats(); _refresh()
	var new_lv := int(UserDB.get_dragon(uid).get("level", 1))
	var slot_new := -1
	for si in Loadout.SLOT_UNLOCK_LEVEL.size():
		if old_lv < int(Loadout.SLOT_UNLOCK_LEVEL[si]) and new_lv >= int(Loadout.SLOT_UNLOCK_LEVEL[si]):
			slot_new = si
	var scr := _open_levelup()
	if scr:
		scr.play_fx({"kind": "up", "sp": 1.0, "stage_changed": false,
			"slot_new": slot_new, "triple": triple, "batch": done})
	if done < n:
		_toast("레벨 상한(%d)에 닿아 %d회만 사용했습니다" % [cap, done])
	if not sk_got.is_empty():
		_toast("새 스킬 습득 — %s" % ", ".join(sk_got))

func _show_batch_result(agg: Dictionary, last_key: String, tab: String, select_key: String) -> void:
	var entries: Array = []
	for k in agg.keys():
		if String(k) == last_key:
			continue
		entries.append({"key": String(k), "count": int(agg[k])})
	if agg.has(last_key):
		entries.append({"key": last_key, "count": int(agg[last_key])})
	_close_overlay()
	ItemRewardView.open(self, entries, func():
		_inv_tab = tab
		_inv_selected = select_key
		_open_inventory())

func _highest_star_egg_key(keys: Array) -> String:
	var best := ""
	var best_star := -1
	for k in keys:
		var did := EggGacha.dragon_of(String(k))
		var st := int(Data.get_dragon(did).get("star", 0))
		if st > best_star:
			best_star = st
			best = String(k)
	return best

func _loot_owned() -> Dictionary:
	var out: Dictionary = {}
	for section in ["boxes", "keys"]:
		for k in (Data.box_loot.get(section, {}) as Dictionary):
			out[String(k)] = UserDB.item_count(String(k))
	return out

func _loot_fail_text(reason: String, box_key: String) -> String:
	match reason:
		"no_box":
			return "%s 이(가) 없습니다" % Data.item_name(box_key)
		"no_key", "wrong_key":
			var names: Array = []
			for k in BoxLoot.keys_for(Data.box_loot, box_key):
				names.append(Data.item_name(String(k)))
			return "%s 이(가) 필요합니다" % " 또는 ".join(names)
		"empty_pool":
			return "개봉표가 비어 있습니다"
	return "열 수 없습니다"

func _open_loot_box(box_key: String, key_item := "") -> void:
	var owned := _loot_owned()
	var probe_rng := RandomNumberGenerator.new()
	var probe := BoxLoot.open(Data.box_loot, box_key, owned, probe_rng, key_item)
	if not bool(probe.get("ok", false)):
		_toast(_loot_fail_text(String(probe.get("reason", "")), box_key)); return

	var used := String(probe.get("key_used", ""))
	var body := "무엇이 나올지는 열어 봐야 압니다.\n사용하시겠습니까?"
	if used != "":
		body = "%s 을(를) 사용해 엽니다.\n(열쇠는 사용하면 사라집니다)" % Data.item_name(used)
	_open_popup_type(Data.item_name(box_key), body,
		func(): _do_loot_open(box_key, used))

func _use_loot_key(key_item: String) -> void:
	var boxes := BoxLoot.openable_boxes(Data.box_loot, key_item, _loot_owned())
	if boxes.is_empty():
		var names: Array = []
		for b in (BoxLoot.key_of(Data.box_loot, key_item).get("opens", []) as Array):
			names.append(Data.item_name(String(b)))
		_toast("%s 이(가) 없습니다" % " 또는 ".join(names)); return
	_open_loot_box(String(boxes[0]), key_item)

func _do_loot_open(box_key: String, key_item: String) -> void:
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var r := BoxLoot.open(Data.box_loot, box_key, _loot_owned(), rng, key_item)
	if not bool(r.get("ok", false)):
		_toast(_loot_fail_text(String(r.get("reason", "")), box_key)); return
	for c in (r["consumed"] as Array):
		UserDB.use_item(String((c as Dictionary)["key"]), int((c as Dictionary)["count"]))
	var shown: Array = []
	var last := ""
	for g in (r["gained"] as Array):
		var gk := String((g as Dictionary)["key"])
		var gn := int((g as Dictionary)["count"])
		UserDB.add_item(gk, gn)
		shown.append({"key": gk, "count": gn})
		last = gk
	_close_overlay()
	ItemRewardView.open(self, shown, func():
		if last != "":
			_inv_tab = _inventory_tab_for_item(last)
			_inv_selected = last
		_open_inventory())

func _confirm_gacha_egg(item_key: String, on_ok: Callable, count := 1) -> void:
	var body := "무작위로 선택된 드래곤의 알이 나옵니다.\n사용하시겠습니까?"
	if item_key == "mall_question_egg2":
		body = "무작위로 선택된 4성 이상의 드래곤의 알이 나옵니다.\n사용하시겠습니까?"
	else:
		var pct := EggGacha.star_chance_pct(item_key,
			Data.items.get(item_key, {}), Data.gacha_eggs, 5, Data.dragons)
		if pct > 0.0:
			body += "\n\n* 5성 드래곤의 알이 나올 확률 : %s%%" % _pct_text(pct)
	if count > 1:
		body += "\n\n%s %d개를 사용합니다." % [Data.item_name(item_key), count]
	_open_popup_type(Data.item_name(item_key), body, on_ok)

func _pct_text(p: float) -> String:
	return str(int(round(p))) if absf(p - round(p)) < 0.05 else ("%.1f" % p)

func _show_egg_result(did: int, used_key := "") -> void:
	var pop := EggResultView.open(self, did, used_key)
	pop.closed.connect(func():
		_inv_tab = "egg"
		_inv_selected = EggGacha.key_for(did)
		_open_inventory())

func _inventory_tabs(win: Control) -> void:
	var shelf := NinePatchRect.new()
	shelf.texture = load("res://assets/converted/ninepatch_ui/9patch_menu_bg.tres")
	shelf.patch_margin_left = 24; shelf.patch_margin_right = 24
	shelf.patch_margin_top = 20; shelf.patch_margin_bottom = 20
	shelf.position = Vector2(50, 760)
	shelf.size = Vector2(1680, 142)
	win.add_child(shelf)
	var spacing := 200
	var startx := 140
	for i in INV_TABS.size():
		var tab: Dictionary = INV_TABS[i]
		_inventory_tab_button(shelf, tab, startx + i * spacing, 28)

func _inventory_tab_button(parent: Control, tab: Dictionary, x: int, y: int) -> void:
	var id := String(tab["id"])
	var icon := _ui_sprite(String(tab["icon"]), 1.45)
	icon.position = Vector2(x, y + 42)
	if id != _inv_tab:
		icon.modulate = Color(0.78, 0.78, 0.78, 0.9)
	parent.add_child(icon)

	var label := _ui_sprite(String(tab["label"]), 1.5)
	label.position = Vector2(x, y + 98)
	if id != _inv_tab:
		label.modulate = Color(0.72, 0.72, 0.72, 0.85)
	parent.add_child(label)

	var b := Button.new()
	b.flat = true
	b.position = Vector2(x - 58, y - 6)
	b.size = Vector2(116, 128)
	b.pressed.connect(func(): _inventory_set_tab(id))
	parent.add_child(b)

func _inventory_set_tab(tab_id: String) -> void:
	if tab_id == _inv_tab:
		return
	_inv_tab = tab_id
	var items := _inventory_items_for_tab(_inv_tab)
	_inv_selected = String(items[0]) if not items.is_empty() else ""
	_open_inventory()

func _inventory_select(key: String) -> void:
	var prev := _inv_selected
	_inv_selected = key
	for k in [prev, key]:
		var f = _inv_cells.get(String(k))
		if f is NinePatchRect and is_instance_valid(f):
			(f as NinePatchRect).texture = _inv_slot_frame(String(k) == key)
	_inventory_refresh_detail()

func _inv_slot_frame(selected: bool) -> Texture2D:
	return load("res://assets/converted/ninepatch_ui/%s.tres"
		% ("9patch_bt_itembox_on" if selected else "9patch_train_box4"))

func _inventory_items_for_tab(tab_id: String) -> Array:
	var out := []
	for key in UserDB.inventory().keys():
		if _inventory_tab_for_item(String(key)) == tab_id:
			out.append(String(key))
	if tab_id == "gear":
		var cat := Equipment.catalog(Data.equipment)
		var rows: Array = []
		for key in out:
			var ck := Equipment.parse_item_key(String(key))
			rows.append({"inv": String(key), "cat": ck, "it": cat.get(ck, {}),
				"meta": Equipment.item_key_meta(String(key)), "worn": false})
		rows.sort_custom(Equipment.display_sort_less)
		out.clear()
		for row in rows:
			out.append(String((row as Dictionary).get("inv", "")))
	else:
		out.sort()
	return out

func _inventory_tab_for_item(key: String) -> String:
	if key.begins_with(Gem.ITEM_PREFIX):
		return "gem"
	if key.begins_with(Equipment.ITEM_PREFIX):
		return "gear"
	if key.begins_with(Loadout.ITEM_PREFIX):
		return "skill"
	var item := _inventory_item_def(key)
	var category := String(item.get("category", ""))
	match category:
		"food":
			return "food"
		"egg":
			return "egg"
		"document":
			return "doc"
		"skill":
			return "skill"
		"material":
			return "mtr"
	return "etc"

func _inventory_has_item(key: String) -> bool:
	return int(UserDB.inventory().get(key, 0)) > 0

func _inventory_item_def(key: String) -> Dictionary:
	var g := Gem.parse_item_key(key)
	if not g.is_empty():
		var gd: Dictionary = Gem.gem_def(String(g["name"]), Data.gems)
		if gd.is_empty():
			return {}
		return {"name": String(g["name"]), "category": "gem",
			"subcategory": String(gd.get("category", "")),
			"gem_name": String(g["name"]), "gem_tier": int(g["tier"]),
			"gem_code": String(gd.get("code", "")), "offline": "impl"}
	var sk := Loadout.parse_item_key(key)
	if not sk.is_empty():
		var sd: Dictionary = Data.skills.get(str(int(sk["id"])), {})
		if sd.is_empty():
			return {}
		return {"name": "%s Lv.%d" % [String(sd.get("name", "스킬")), int(sk["level"])],
			"category": "skill", "subcategory": String(sd.get("slot", "")),
			"skill_id": int(sk["id"]), "skill_level": int(sk["level"]),
			"offline": "impl",
			"use": "현재 선택 중인 드래곤이 이 스킬을 배운다",
			"desc": Loadout.skill_comment(sd, String(sd.get("effect_text", "")))}
	var eg := EggGacha.item_def(key, Data.dragons)
	if not eg.is_empty():
		var egid := int(eg.get("dragon_id", 0))
		if String(Data.get_dragon(egid).get("name", "")) == "":
			eg["name"] = Icons.egg_item_name(egid)
			eg["element"] = Icons.species_element(egid)
		return eg
	var ck := Equipment.parse_item_key(key)
	if ck != "":
		var it: Dictionary = Equipment.catalog(Data.equipment).get(ck, {})
		if it.is_empty():
			return {}
		var out := it.duplicate(true)
		out["category"] = "equipment"
		out["subcategory"] = String(it.get("slot_class", "all"))
		out["offline"] = "impl"
		return out
	if Data.items.has(key):
		return Data.get_item(key)
	var eb := EggItem.base_of(key)
	if eb != key and Data.items.has(eb):
		var bi := Data.get_item(eb).duplicate(true)
		bi["egg_grade"] = EggItem.grade_of(key)
		return bi
	var found := _inventory_key_from_display_name(key)
	return Data.get_item(found) if found != "" else {}

func _inventory_key_from_display_name(raw_name: String) -> String:
	for k in Data.items.keys():
		if String(Data.items[k].get("name", "")) == raw_name:
			return String(k)
	for k in Data.items.keys():
		var item_name := String(Data.items[k].get("name", ""))
		if item_name.begins_with(raw_name) or raw_name.begins_with(item_name):
			return String(k)
	return ""

func _use_skill_scroll(scroll_key: String) -> void:
	var table: Dictionary = Data.skill_scrolls.get("scrolls", {})
	if not table.has(scroll_key):
		_toast("이 스크롤의 정보가 없습니다")
		return
	if Loadout.scroll_is_select(scroll_key, table):
		_open_skill_book_pick(scroll_key)
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var got := Loadout.roll_scroll(scroll_key, table, Data.skills, rng)
	if got.is_empty():
		_toast("얻을 수 있는 스킬이 없습니다")
		return
	_open_popup_type("아이템 사용", Data.ui("#b2e04eff"),
		func(): _grant_skill_item(scroll_key, int(got["id"]), int(got["level"])),
		"확인", "취소", scroll_key)

func _open_skill_book_pick(scroll_key: String) -> void:
	var table: Dictionary = Data.skill_scrolls.get("scrolls", {})
	var cand := Loadout.scroll_candidates(scroll_key, table, Data.skills)
	_close_skill_modal()
	_ensure_skill_modal()
	var panel := _skill_modal_panel("스킬 선택")
	var body := _skill_modal_list(panel)
	if cand.is_empty():
		body.add_child(_skill_list_button("(고를 수 있는 스킬이 없습니다)", _close_skill_modal))
		return
	for c in cand:
		var sid := int(c["id"])
		var lv := int(c["level"])
		var sdef: Dictionary = Data.skills.get(str(sid), {})
		var mark := String(_SKILL_SLOT_MARK.get(String(sdef.get("slot", "")), "?"))
		body.add_child(_skill_list_button("%s %s Lv.%d" % [mark, String(sdef.get("name", "스킬")), lv],
			func(): _confirm_skill_book_pick(scroll_key, sid, lv)))

func _confirm_skill_book_pick(scroll_key: String, sid: int, level: int) -> void:
	_open_popup_type(Data.ui("#dd1a9ebd"), Data.ui("#9cb2c692"),
		func(): _grant_skill_item(scroll_key, sid, level),
		"확인", "취소", Loadout.item_key(sid, level))

func _grant_skill_item(scroll_key: String, sid: int, level: int) -> void:
	if not UserDB.use_item(scroll_key, 1):
		_toast("스크롤이 없습니다")
		return
	_close_skill_modal()
	UserDB.add_item(Loadout.item_key(sid, level), 1)
	var nm := String(Data.skills.get(str(sid), {}).get("name", "스킬"))
	_inventory_refresh_grid()
	_inventory_refresh_detail()
	var table: Dictionary = Data.skill_scrolls.get("scrolls", {})
	var msg := "봉인된 스크롤을 사용하여 %s의 스킬을 획득하였습니다." % nm
	if Loadout.scroll_is_select(scroll_key, table):
		msg = "에자녹의 권능을 사용하여 %s의 스킬을 획득하였습니다." % nm
	_open_popup_type(Data.ui("#e28bf315"), msg, func(): pass,
		"확인", "", Loadout.item_key(sid, level))

func _use_skill_item(item_key: String) -> void:
	var parsed := Loadout.parse_item_key(item_key)
	if parsed.is_empty():
		return
	var a := _active()
	if a.is_empty():
		_toast("선택된 드래곤이 없습니다")
		return
	if int(a.get("level", 1)) < 10:
		_toast(Data.ui("#969b74a8"))
		return
	var pool: Array = UserDB.dragon_skills(int(a["uid"]))
	if not Loadout.can_learn(pool, int(parsed["id"]), int(parsed["level"])):
		_toast(Loadout.LEARN_BLOCKED_MSG)
		return
	_open_popup_type("스킬 배우기", Data.ui("#dd9f2701"),
		func(): _do_learn_skill_item(item_key, parsed),
		"확인", "취소", item_key)

func _do_learn_skill_item(item_key: String, parsed: Dictionary) -> void:
	var a := _active()
	if a.is_empty():
		return
	var uid := int(a["uid"])
	var res := Loadout.learn_from_item(UserDB.dragon_skills(uid),
		int(parsed["id"]), int(parsed["level"]), Data.skills)
	if not bool(res.get("ok", false)):
		_toast(String(res.get("msg", "습득 실패")))
		return
	if not UserDB.use_item(item_key, 1):
		_toast("아이템이 없습니다")
		return
	UserDB.set_dragon_skills(uid, res["skills"])
	_inventory_refresh_grid()
	_inventory_refresh_detail()
	_refresh(); _refresh_stats()
	_toast(Data.ui("#0beb0841"))

func _close_skill_modal() -> void:
	if is_instance_valid(_skill_modal):
		_skill_modal.queue_free()
	_skill_modal = null

func _ensure_skill_modal() -> void:
	if is_instance_valid(_skill_modal):
		return
	_skill_modal = CanvasLayer.new()
	_skill_modal.layer = 20
	add_child(_skill_modal)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_skill_modal.add_child(dim)

func _skill_modal_panel(title: String) -> Panel:
	_ensure_skill_modal()
	for c in _skill_modal.get_children():
		if c is Panel:
			c.queue_free()
	var vis := _vis()
	var panel := _panel(Color(0.14, 0.09, 0.05, 0.98))
	panel.size = Vector2(520, 600)
	panel.position = (vis - panel.size) / 2.0
	_skill_modal.add_child(panel)
	var t := Label.new()
	t.text = title
	t.position = Vector2(20, 16)
	t.size = Vector2(480, 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	panel.add_child(t)
	var close := Button.new()
	close.text = "닫기"
	close.position = Vector2(210, 540)
	close.size = Vector2(100, 44)
	close.pressed.connect(_close_skill_modal)
	panel.add_child(close)
	return panel

func _skill_modal_list(panel: Panel) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.position = Vector2(40, 64)
	sc.size = Vector2(440, 460)
	panel.add_child(sc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.custom_minimum_size = Vector2(440, 0)
	sc.add_child(vb)
	return vb

func _skill_list_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(430, 52)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b

func _inventory_item_name(key: String) -> String:
	var item := _inventory_item_def(key)
	if String(item.get("category", "")) == "gem":
		return Gem.display_name(String(item.get("gem_name", "")),
			int(item.get("gem_tier", 0)), Data.gems)
	return String(item.get("name", key))

const _SUBCAT_KR := {
	"blessing": "축복", "level": "레벨", "nest": "둥지", "slot": "슬롯", "box": "상자",
	"qol": "편의", "key": "열쇠", "buff": "버프", "story": "시나리오", "ticket": "입장권",
	"drink": "드링크", "feed": "먹이", "heal": "회복", "revive": "부활",
	"dragon_egg": "드래곤 알", "element_egg": "속성 알", "gacha_egg": "뽑기 알",
	"map": "지도", "recipe": "레시피", "mix_book": "조합서",
	"memory_random": "기억의 결정", "memory_select": "기억의 판단",
	"shard": "파편", "alchemy": "연금 재료", "crystal": "결정", "crystal_ex": "전용 결정",
	"jewel": "보석", "powder": "마법가루", "awaken_stone": "각성석", "awaken_mat": "각성 재료",
	"stone_heart": "심장석", "spirit_stone": "정령석", "craft": "제작 재료",
	"essence": "에센스", "raid_shard": "레이드 조각",
	"normal": "일반 젬", "hybrid": "혼성 젬", "soul": "소울 젬",
	"all": "모든 장비칸", "battle": "전투형", "support": "보조형", "artifact": "아티팩트",
	"tri": "△ 스킬", "sq": "□ 스킬", "cir": "○ 스킬", "star": "☆ 스킬",
}

func _inventory_item_desc(key: String, item: Dictionary) -> String:
	if item.is_empty():
		return "%s\n분류: 기타" % key
	var parts := []
	if String(item.get("category", "")) == "gem":
		var gn2 := String(item.get("gem_name", ""))
		var gt2 := int(item.get("gem_tier", 0))
		parts.append("효과: %s" % Gem.effect_text(gn2, gt2, Data.gems))
		var gem_desc := Data.gem_description(Gem.description_category(gn2, Data.gems))
		if gem_desc != "":
			parts.append(gem_desc)
	elif String(item.get("category", "")) == "equipment":
		var mparts: PackedStringArray = []
		for st: String in (item.get("stat_main", {}) as Dictionary):
			mparts.append("%s+%d" % [_equip_stat_kr(st), int(item["stat_main"][st])])
		if not mparts.is_empty():
			parts.append("주 능력: %s" % " ".join(mparts))
		if String(item.get("artifact_effect", "")) != "":
			parts.append("효과: %s" % String(item["artifact_effect"]))
		if String(item.get("bonus", "")) != "":
			parts.append("부가: %s" % String(item["bonus"]))
		var equip_desc := Data.equipment_description(Equipment.parse_item_key(key))
		if equip_desc != "":
			parts.append(equip_desc)
	if item.has("dragon_id"):
		parts.append("드래곤 ID: %d" % int(item["dragon_id"]))
	match String(item.get("offline", "")):
		"dummy":
			parts.append("(더미 데이터입니다)")
		"cut":
			parts.append("(오프라인 재구현에서 빠진 기능의 아이템입니다)")
		"todo", "stub":
			parts.append("(해당 기능이 아직 구현되지 않았습니다)")
	return "\n".join(parts)

func _inventory_item_icon(key: String, target: float) -> Sprite2D:
	var item := _inventory_item_def(key)
	var vt: Texture2D = null
	if String(item.get("category", "")) == "gem":
		vt = Icons.gem_texture(String(item.get("gem_code", "")), int(item.get("gem_tier", 0)))
	elif String(item.get("category", "")) == "equipment":
		vt = Icons.equip_texture(item)
	elif EggGacha.dragon_of(key) > 0:
		vt = Icons.dragon_egg_texture(EggGacha.dragon_of(key))
	elif String(item.get("category", "")) == "skill":
		vt = _skill_tex(int(item.get("skill_id", 0)))
	if vt != null:
		var vs := Sprite2D.new()
		vs.texture = vt
		vs.material = _pma
		var vw: float = maxf(1.0, float(vt.get_width()))
		vs.scale = Vector2(target / vw, target / vw)
		return vs
	var icon_path := String(item.get("icon", ""))
	if icon_path == "":
		return null
	var slash := icon_path.find("/")
	if slash < 0:
		return null
	var dir := icon_path.substr(0, slash)
	var frame := icon_path.substr(slash + 1)
	var man := _item_manifest(dir)
	var w: float = maxf(1.0, float(man.get(frame, {}).get("w", target)))
	return _atlas_sprite(dir, frame, man, target / w)

func _item_manifest(dir: String) -> Dictionary:
	if not _item_manifests.has(dir):
		var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
		_item_manifests[dir] = JSON.parse_string(f.get_as_text()) if f else {}
	return _item_manifests[dir]

func _open_cards() -> void:
	var box := _make_overlay("카드")
	var l := Label.new(); l.text = "카드 시스템 (추후 구현)"; l.add_theme_font_size_override("font_size", 28)
	box.add_child(l)

var _food_fill: NinePatchRect
var _food_label: Label
func _build_stamina_gauge() -> void:
	var S := Design.ASSET_SCALE
	var plate := NinePatchRect.new()
	plate.texture = load("res://assets/converted/ninepatch_ui/9patch_train_box4.tres")
	plate.patch_margin_left = 22; plate.patch_margin_right = 22
	plate.patch_margin_top = 16; plate.patch_margin_bottom = 16
	plate.size = Vector2(230, 56)
	plate.position = Vector2(-115, 268)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(plate)
	var bub := _atlas_sprite("common_ui", "common_bubble_food", _man_common(), 1.0)
	if bub:
		bub.position = Vector2(32, 28); plate.add_child(bub)
	var gw := 162.0 * S * 0.72
	var gh := 11.0 * S
	var gx := 60.0
	var gy := 28.0 - gh * 0.5
	var track := NinePatchRect.new()
	track.texture = load("res://assets/converted/common_ui/common_bar_bg2.tres")
	track.patch_margin_left = 5; track.patch_margin_right = 5
	track.size = Vector2(gw, gh); track.position = Vector2(gx, gy)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(track)
	_food_fill = NinePatchRect.new()
	_food_fill.texture = load("res://assets/converted/common_ui/common_bar_food.tres")
	_food_fill.patch_margin_left = 5; _food_fill.patch_margin_right = 5
	_food_fill.size = Vector2(gw, gh); _food_fill.position = Vector2(gx, gy)
	_food_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(_food_fill)
	_food_label = Label.new()
	_food_label.add_theme_font_size_override("font_size", 17)
	_food_label.add_theme_color_override("font_color", Color.WHITE)
	_food_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_food_label.add_theme_constant_override("outline_size", 4)
	_food_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_food_label.size = Vector2(gw, 20); _food_label.position = Vector2(gx, gy + gh + 1)
	plate.add_child(_food_label)
	_refresh_stamina()

func _refresh_stamina() -> void:
	if not is_instance_valid(_food_fill) or not is_instance_valid(_food_label): return
	var a := _active()
	var fmax := ItemEffect.food_max(Data.item_effects)
	var food := clampi(int(a.get("food", fmax)) if not a.is_empty() else fmax, 0, fmax)
	var full := 162.0 * Design.ASSET_SCALE * 0.72
	_food_fill.size.x = full * (float(food) / float(maxi(1, fmax)))
	_food_fill.visible = food > 0
	_food_label.text = "%d / %d" % [food, fmax]
	_food_label.add_theme_color_override("font_color",
		Color(1, 0.45, 0.4) if food <= 0 else Color.WHITE)

func _man_common() -> Dictionary:
	return AtlasUI.manifest("common_ui")

func _josa_c(word: String, with_batchim: String, without: String) -> String:
	if word.is_empty(): return without
	var c := word.unicode_at(word.length() - 1)
	if c < 0xAC00 or c > 0xD7A3: return without
	return with_batchim if ((c - 0xAC00) % 28) != 0 else without

func _man_adventure() -> Dictionary:
	return AtlasUI.manifest("adventure_ui")

func _orig_popup(parent: Node, size: Vector2, title_text: String) -> Control:
	var vis := _vis()
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190
	win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = size
	win.position = Vector2(round((vis.x - size.x) * 0.5), round((vis.y - size.y) * 0.5))
	parent.add_child(win)
	if title_text != "":
		var tw := minf(size.x - 80.0, 300.0)
		var tbar := NinePatchRect.new()
		tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
		tbar.patch_margin_left = 20; tbar.patch_margin_right = 20
		tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
		tbar.size = Vector2(tw, 52); tbar.position = Vector2((size.x - tw) * 0.5, 10)
		tbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		win.add_child(tbar)
		var tl := Label.new(); tl.text = title_text
		tl.add_theme_font_size_override("font_size", 26)
		tl.add_theme_color_override("font_color", Color.WHITE)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tl.size = tbar.size; tbar.add_child(tl)
	return win
