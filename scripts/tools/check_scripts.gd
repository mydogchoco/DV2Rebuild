extends SceneTree

const ROOTS := ["res://scripts/core", "res://scripts/systems", "res://scripts/ui"]
const TOOL_ROOT := "res://scripts/tools"

func _initialize() -> void:
	var files: Array[String] = []
	for r in ROOTS:
		_collect(r, files)
	var n_game := files.size()
	_collect(TOOL_ROOT, files)

	var live := {get_script().resource_path: true}
	for k in ProjectSettings.get_property_list():
		var pname := String((k as Dictionary).get("name", ""))
		if not pname.begins_with("autoload/"):
			continue
		var v := String(ProjectSettings.get_setting(pname, ""))
		live[v.trim_prefix("*")] = true

	var bad: Array[String] = []
	for i in files.size():
		var path := files[i]
		var sc := ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_REUSE) as GDScript
		if sc == null:
			bad.append(path)
			continue
		if live.has(path):
			continue
		if sc.reload() != OK:
			bad.append(path)

	print("게임 스크립트 %d개 · 도구 %d개 = 총 %d개 로드"
		% [n_game, files.size() - n_game, files.size()])
	if bad.is_empty():
		print("=== ALL PASS ===")
		quit(0)
		return
	print("컴파일 실패 %d개:" % bad.size())
	for b in bad:
		print("   ", b)
	print("=== %d FAIL ===" % bad.size())
	quit(1)

func _collect(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				_collect(full, out)
		elif name.ends_with(".gd"):
			if not name.begins_with("_tmp_"):
				out.append(full)
		name = d.get_next()
	d.list_dir_end()
