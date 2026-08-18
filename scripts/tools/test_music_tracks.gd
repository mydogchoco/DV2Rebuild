extends SceneTree

const MUSIC := "res://assets/music/%s.mp3"
const LEGACY := "res://DV2/music/%s.mp3"
const LITERAL := r'Bgm\.(?:sfx|loop_sfx|play)\(\s*"([a-zA-Z0-9_]+)"'

func _init() -> void:
	var re := RegEx.new()
	re.compile(LITERAL)
	var keys := {}
	_scan("res://scripts", re, keys)
	var fails := 0
	fails += _true("스캔된 트랙 리터럴이 있다", keys.size() > 0)

	var missing: Array[String] = []
	var no_source: Array[String] = []
	for k: String in keys:
		if ResourceLoader.exists(MUSIC % k):
			continue
		if FileAccess.file_exists(LEGACY % k):
			missing.append(k)
		else:
			no_source.append(k)
	missing.sort()
	no_source.sort()
	if not missing.is_empty():
		printerr("  → assets/music 반입 누락(에디터만 나고 exe 에선 무음): ", ", ".join(missing))
		printerr("    고치는 법: python scripts/tools/build_music.py && godot --headless --import")
	if not no_source.is_empty():
		printerr("  → 원본(DV2/music)에도 없는 트랙: ", ", ".join(no_source))
	fails += _eq("반입 누락", missing.size(), 0)
	fails += _eq("원본 없는 트랙", no_source.size(), 0)

	print("[test_music_tracks] 리터럴 트랙 %d 종 검사" % keys.size())
	if fails == 0: print("[test_music_tracks] ALL PASS")
	else: printerr("[test_music_tracks] %d FAIL" % fails)
	quit(1 if fails > 0 else 0)

func _scan(dir_path: String, re: RegEx, keys: Dictionary) -> void:
	var d := DirAccess.open(dir_path)
	if d == null: return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var p := dir_path.path_join(name)
		if d.current_is_dir():
			_scan(p, re, keys)
		elif name.ends_with(".gd"):
			var f := FileAccess.open(p, FileAccess.READ)
			if f:
				for m in re.search_all(f.get_as_text()):
					keys[m.get_string(1)] = true
		name = d.get_next()
	d.list_dir_end()

func _eq(l: String, g, w) -> int:
	if g == w: return 0
	printerr("  FAIL %s: got=%s want=%s" % [l, str(g), str(w)]); return 1
func _true(l: String, c: bool) -> int:
	if c: return 0
	printerr("  FAIL %s" % l); return 1
