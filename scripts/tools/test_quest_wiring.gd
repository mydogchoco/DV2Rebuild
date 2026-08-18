extends SceneTree

const SRC_DIRS := ["res://scripts/core", "res://scripts/systems", "res://scripts/ui"]
const ENGINE_CB := ["_ready", "_init", "_process", "_physics_process", "_input",
	"_unhandled_input", "_gui_input", "_draw", "_notification", "_enter_tree", "_exit_tree"]

func _init() -> void:
	var fails := 0
	var sources := _read_sources()

	var town_keys := _quest_keys("res://scripts/ui/town.gd")
	if town_keys.size() != 6:
		print("  FAIL town.gd _QUESTS 키를 6개 못 읽었다: ", town_keys)
		fails += 1

	for key: String in town_keys:
		var sites := _bump_sites(sources, key)
		if sites.is_empty():
			print("  FAIL '%s' 를 세는 곳이 없다 (bump_quest(\"%s\") 0건)" % [key, key])
			fails += 1
			continue
		var live: Array = []
		for s: Dictionary in sites:
			if _reachable(sources, String(s["file"]), String(s["func"])):
				live.append("%s::%s" % [String(s["file"]).get_file(), String(s["func"])])
		if live.is_empty():
			var dead := []
			for s: Dictionary in sites:
				dead.append("%s::%s" % [String(s["file"]).get_file(), String(s["func"])])
			print("  FAIL '%s' 카운트가 죽은 함수에만 있다 → %s" % [key, ", ".join(dead)])
			print("       (실제 행동을 해도 미션이 안 오른다. 산 경로로 옮길 것.)")
			fails += 1
		else:
			print("  ok  %-9s ← %s" % [key, ", ".join(live)])

	for key: String in _quest_keys("res://scripts/ui/mission_board.gd"):
		if not town_keys.has(key):
			print("  FAIL mission_layer 의 '%s' 가 town.gd _QUESTS 에 없다(카운터 분기)" % key)
			fails += 1

	if fails == 0:
		print("[test_quest_wiring] ALL PASS")
	else:
		print("[test_quest_wiring] %d FAIL" % fails)
	quit(1 if fails > 0 else 0)

func _read_sources() -> Dictionary:
	var out := {}
	for d: String in SRC_DIRS:
		for f: String in _gd_files(d):
			out[f] = FileAccess.get_file_as_string(f)
	return out

func _gd_files(dir: String) -> Array:
	var out: Array = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		var p := dir + "/" + n
		if da.current_is_dir():
			out.append_array(_gd_files(p))
		elif n.ends_with(".gd"):
			out.append(p)
		n = da.get_next()
	da.list_dir_end()
	return out

func _quest_keys(path: String) -> Array:
	var keys: Array = []
	var inside := false
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		if not inside:
			if line.begins_with("const _QUESTS"):
				inside = true
			continue
		if line.begins_with("]"):
			break
		var i := line.find("\"key\":")
		if i < 0:
			continue
		var rest := line.substr(i + 6).strip_edges()
		var a := rest.find("\"")
		var b := rest.find("\"", a + 1)
		if a >= 0 and b > a:
			keys.append(rest.substr(a + 1, b - a - 1))
	return keys

func _bump_sites(sources: Dictionary, key: String) -> Array:
	var needle := "bump_quest(\"%s\")" % key
	var out: Array = []
	for f: String in sources:
		var cur := ""
		var ln := 0
		for line: String in String(sources[f]).split("\n"):
			ln += 1
			if line.begins_with("func ") or line.begins_with("static func "):
				var head := line.substr(line.find("func ") + 5)
				cur = head.substr(0, maxi(0, head.find("(")))
			if line.contains(needle) and not line.strip_edges().begins_with("#"):
				out.append({"file": f, "func": cur, "line": ln})
	return out

func _reachable(sources: Dictionary, owner: String, fname: String) -> bool:
	if fname == "" or ENGINE_CB.has(fname):
		return true
	for f: String in sources:
		for line: String in String(sources[f]).split("\n"):
			var t := line.strip_edges()
			if t.begins_with("#"):
				continue
			if t.begins_with("func %s(" % fname) or t.begins_with("static func %s(" % fname):
				continue
			if line.contains("%s(" % fname) or line.contains("connect(%s)" % fname) \
					or line.contains("\"%s\"" % fname):
				return true
	return false
