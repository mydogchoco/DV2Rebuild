class_name Icons
extends RefCounted

const ELEMENT_SMALL := {
	"all": "item_item_small_ele_all", "fire": "item_item_small_ele_fire",
	"aqua": "item_item_small_ele_water", "water": "item_item_small_ele_water",
	"earth": "item_item_small_ele_ground", "ground": "item_item_small_ele_ground",
	"wind": "item_item_small_ele_wind", "light": "item_item_small_ele_light",
	"dark": "item_item_small_ele_dark", "holy": "item_item_small_ele_holy",
	"chaos": "item_item_small_ele_chaos", "shadow": "item_item_small_ele_shadow"}

static func element_small_frame(element: String) -> String:
	return String(ELEMENT_SMALL.get(element, ""))

static func entry(section: String, key: String) -> Dictionary:
	var m: Dictionary = Data.icon_map
	return (m.get(section, {}) as Dictionary).get(key, {})

static func texture(section: String, key: String) -> Texture2D:
	return tex_of(entry(section, key))

static func gem_texture(code: String, tier: int) -> Texture2D:
	return texture("gem", "%s:%d" % [code, tier])

static func dragon_egg_texture(dragon_id: int) -> Texture2D:
	var art := species_art_id(dragon_id)
	var p := "res://assets/converted/portrait_%d/dragon_dragon_%d_egg.tres" % [art, art]
	return load(p) if ResourceLoader.exists(p) else null

static func art_id_of(inst: Dictionary) -> int:
	var id := int(inst.get("id", 0))
	var own := int(inst.get("art_id", 0))
	if own > 0:
		return own
	return species_art_id(id)

static func species_art_id(id: int) -> int:
	var sa := UserDB.species_art(id)
	var sid := int(sa.get("art_id", 0))
	return sid if sid > 0 else Data.art_id(id)

const SPINE_SUBSTITUTE_ID := 1
const SPINE_TEXTURE_MISSING := [4138, 4204, 4205, 4210]

const AWAKEN_SPINE_MISSING := [104, 4099]
const AWAKEN_FALLBACK_STAGE := {"e": "adult", "e_critical": "critical"}

static func spine_scene(art_id: int, stage: String) -> String:
	if art_id <= 0:
		return ""
	var p := "res://scenes/dragons/dragon_%d_%s.tscn" % [art_id, stage]
	if ResourceLoader.exists(p):
		return p
	if art_id in AWAKEN_SPINE_MISSING and AWAKEN_FALLBACK_STAGE.has(stage):
		var own := "res://scenes/dragons/dragon_%d_%s.tscn" % [art_id, AWAKEN_FALLBACK_STAGE[stage]]
		if ResourceLoader.exists(own):
			return own
	if art_id in SPINE_TEXTURE_MISSING:
		var sub := "res://scenes/dragons/dragon_%d_%s.tscn" % [SPINE_SUBSTITUTE_ID, stage]
		if ResourceLoader.exists(sub):
			return sub
	return ""

static func voice_row(dragon_id: int) -> Dictionary:
	var t: Dictionary = Data.dragon_voices.get("voices", {})
	var own = t.get(str(dragon_id), {})
	var src := int(UserDB.species_art(dragon_id).get("art_id", 0))
	if src > 0 and src != dragon_id:
		var r = t.get(str(src), {})
		if r is Dictionary and not (r as Dictionary).is_empty():
			return r
	return own if own is Dictionary else {}

static func egg_item_name(dragon_id: int) -> String:
	var nm := species_name(dragon_id)
	return "%s의 알" % (nm if nm != "" else "드래곤 %d" % dragon_id)

static func species_element(id: int) -> String:
	var sa := UserDB.species_art(id)
	var se := String(sa.get("element", ""))
	if se != "":
		return se
	var m = Data.get_dragon(id).get("element")
	return String(m) if typeof(m) == TYPE_STRING else ""

static func element_of(inst: Dictionary) -> String:
	var own = inst.get("element")
	if typeof(own) == TYPE_STRING and String(own) != "":
		return String(own)
	return species_element(int(inst.get("id", 0)))

static func species_name(id: int) -> String:
	var own := UserDB.species_name(id)
	if own != "":
		return own
	return String(Data.get_dragon(id).get("name", ""))

static func name_of(inst: Dictionary, fallback := "드래곤") -> String:
	var nick := String(inst.get("nickname", ""))
	if nick == "":
		nick = String(inst.get("nick", ""))
	if nick != "":
		return nick
	var nm := species_name(int(inst.get("id", 0)))
	return nm if nm != "" else fallback

static func equip_entry(item: Dictionary) -> Dictionary:
	var grp := String(item.get("group", ""))
	var parts := String(item.get("key", "")).split(":")
	if grp == "basic" and parts.size() >= 3:
		return entry("equipment_basic", "%s:%s" % [parts[1], parts[2]])
	if grp == "artifact" and parts.size() >= 3:
		return entry("artifact", "%s:%s" % [parts[1], parts[2]])
	if grp == "event":
		return entry("event", String(item.get("name", "")))
	if grp.begins_with("special") and parts.size() >= 3:
		return entry("special", "%s:%s" % [parts[1], parts[2]])
	if grp == "exclusive":
		return entry("exclusive", String(item.get("name", "")))
	return {}

static func equip_texture(item: Dictionary) -> Texture2D:
	return tex_of(equip_entry(item))

static func tex_of(e: Dictionary) -> Texture2D:
	if e.is_empty():
		return null
	var p := "res://assets/converted/%s/%s.tres" % [String(e["dir"]), String(e["frame"])]
	return load(p) if ResourceLoader.exists(p) else null

static func piece_texture(name: String) -> Texture2D:
	return texture("piece", name)

static func exclusive_texture(name: String) -> Texture2D:
	return texture("exclusive", name)

static func equip_bg_entry(item: Dictionary) -> Dictionary:
	var grp := String(item.get("group", ""))
	var parts := String(item.get("key", "")).split(":")
	if (grp == "basic" or grp == "artifact") and parts.size() >= 3:
		return entry("equipment_bg", "%s:%s" % [parts[1], parts[2]])
	if grp == "event":
		return entry("equipment_bg", String(item.get("name", "")))
	return {}

static func equip_bg_texture(item: Dictionary) -> Texture2D:
	return tex_of(equip_bg_entry(item))

static func rarity_color(grade: int) -> Color:
	var tbl: Array = Data.equipment.get("option", {}).get("rarity_colors", [])
	if grade < 0 or grade >= tbl.size() or tbl[grade] == null:
		return Color(0, 0, 0, 0)
	return Color(String(tbl[grade]))

static func rarity_text_color(grade: int) -> Color:
	var tbl: Array = Data.equipment.get("option", {}).get("rarity_text_colors", [])
	if grade < 0 or grade >= tbl.size() or typeof(tbl[grade]) != TYPE_STRING:
		return Color.WHITE
	return Color(String(tbl[grade]))

static func owned_texture(kind: String) -> Texture2D:
	var p := "res://assets/converted/cave_ui/scene_cave_%s.tres" % kind
	return load(p) if ResourceLoader.exists(p) else null

static func equip_rect(item: Dictionary, box: float = 40.0, grade: int = -1,
		belong: int = 0, viewer_uid: int = 0) -> Control:
	var e := equip_entry(item)
	if e.is_empty() and belong <= 0:
		return null
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(box, box)
	holder.size = Vector2(box, box)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if grade >= 0:
		var col := rarity_color(grade)
		var bg := equip_bg_entry(item)
		if not bg.is_empty() and col.a > 0.0:
			var br := frame_rect(bg, box)
			if br:
				br.modulate = col
				holder.add_child(br)
	var ir := frame_rect(e, box)
	if ir:
		holder.add_child(ir)
	if belong > 0:
		var bgb := owned_texture("owned_bg")
		if bgb:
			var r := rect(bgb, box * 0.45)
			if r:
				r.position = Vector2(box * 0.55, box * 0.55)
				holder.add_child(r)
		var mark := owned_texture("owned" if belong == viewer_uid else "owned2")
		if mark:
			var r2 := rect(mark, box * 0.45)
			if r2:
				r2.position = Vector2(box * 0.55, box * 0.55)
				holder.add_child(r2)
	return holder

static func frame_rect(e: Dictionary, box: float = 34.0) -> Control:
	var tex := tex_of(e)
	if tex == null:
		return null
	var info: Dictionary = AtlasUI.manifest(String(e["dir"])).get(String(e["frame"]), {})
	var w := float(info.get("w", tex.get_width()))
	var h := float(info.get("h", tex.get_height()))
	var src: Array = info.get("src", [w, h])
	var off: Array = info.get("off", [0, 0])
	var k := box / maxf(1.0, maxf(float(src[0]), float(src[1])))
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(box, box)
	holder.size = Vector2(box, box)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := _tex_rect(tex, Vector2(w, h) * k)
	tr.position = Vector2(box, box) * 0.5 \
		+ Vector2(float(off[0]), -float(off[1])) * k - tr.size * 0.5
	holder.add_child(tr)
	return holder

static func gem_rect(code: String, tier: int, box: float = 34.0) -> Control:
	return frame_rect(entry("gem", "%s:%d" % [code, tier]), box)

static func rect(tex: Texture2D, box: float = 34.0) -> TextureRect:
	if tex == null:
		return null
	var tr := _tex_rect(tex, Vector2(box, box))
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return tr

static func _tex_rect(tex: Texture2D, sz: Vector2) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.material = AtlasUI.pma()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.custom_minimum_size = sz
	tr.size = sz
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr
