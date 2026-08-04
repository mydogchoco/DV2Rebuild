extends SceneTree
## 메탈타워/엘리시움 던전 클릭 연출 데이터와 필수 자산 회귀 검사.

var _fails := 0

func _initialize() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/worldmap.json"))
	_check(parsed is Dictionary, "worldmap.json parses")
	if not parsed is Dictionary:
		quit(1)
		return
	var regions: Array = parsed.get("regions", [])
	var elf := _region(regions, "elf")
	var dwarf := _region(regions, "dwarf")
	_check(not elf.is_empty() and not dwarf.is_empty(), "elf/dwarf regions exist")

	var ea: Array = elf.get("native", {}).get("ambient", [])
	_check(_offset_is(_ambient(ea, "ani_elf_waterflow_spine"), Vector2(40, 200)),
		"river waterflow offset")
	_check(_offset_is(_ambient(ea, "ani_elf_wave_new_spine"), Vector2(40, 200)),
		"river highlight offset")
	_check(_offset_is(_ambient(ea, "ani_elf_tree_spine"), Vector2(-44.7, 42.3)),
		"world tree offset")

	var da: Array = dwarf.get("native", {}).get("ambient", [])
	_check(_ambient(da, "ani_cart_new_spine").is_empty(), "cart ambient removed")
	var statue := _ambient(da, "ani_dwarfstatue_new_spine")
	_check(String(statue.get("id", "")) == "dwarf_statue" and not bool(statue.get("autoplay", true)),
		"statue stays in setup pose")

	var dfx: Array = dwarf.get("native", {}).get("field_fx", [])
	var efx: Array = elf.get("native", {}).get("field_fx", [])
	_check(_fields(dfx) == [20, 21, 22], "metal click fields exclude raid-only fire-dragon touch")
	_check(_fields(efx) == [16, 17, 18, 19], "elysium click fields")
	_check(String(_field(dfx, 22).get("ambient_touch", "")) == "dwarf_statue", "statue click route")

	for fx in dfx + efx:
		for sound in fx.get("sounds", []):
			var name := String(sound)
			_check(FileAccess.file_exists("res://assets/music/%s.mp3" % name) \
				or FileAccess.file_exists("res://DV2/music/%s.mp3" % name), "sound %s" % name)
		var scene := String(fx.get("scene", ""))
		if scene != "":
			var path := "res://scenes/worldmap_fx/%s.tscn" % scene
			_check(ResourceLoader.exists(path), "scene %s" % scene)
			if ResourceLoader.exists(path):
				var packed := load(path) as PackedScene
				var inst := packed.instantiate() if packed else null
				var player := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer if inst else null
				_check(player != null and player.has_animation(String(fx.get("anim", ""))),
					"animation %s:%s" % [scene, String(fx.get("anim", ""))])
				if inst:
					inst.free()

	print("[test_worldmap_click_fx] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
	quit(0 if _fails == 0 else 1)

func _region(regions: Array, id: String) -> Dictionary:
	for region in regions:
		if String(region.get("id", "")) == id:
			return region
	return {}

func _ambient(entries: Array, base: String) -> Dictionary:
	for entry in entries:
		if String(entry.get("base", "")) == base:
			return entry
	return {}

func _field(entries: Array, field: int) -> Dictionary:
	for entry in entries:
		if int(entry.get("field", -1)) == field:
			return entry
	return {}

func _fields(entries: Array) -> Array:
	var out: Array = []
	for entry in entries:
		out.append(int(entry.get("field", -1)))
	out.sort()
	return out

func _offset_is(entry: Dictionary, expected: Vector2) -> bool:
	var value: Array = entry.get("design_offset", [])
	return value.size() == 2 and Vector2(float(value[0]), float(value[1])).is_equal_approx(expected)

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS ", label)
	else:
		_fails += 1
		push_error("FAIL " + label)
