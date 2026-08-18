extends SceneTree

const S := preload("res://scripts/core/save_system.gd")

func _init() -> void:
	var fails := 0
	fails += _eq("env DV2_TEST_SAVE", S.classify(true, false, "", false), "test")
	fails += _eq("--script test_*.gd",
		S.classify(false, false, "res://scripts/tools/test_growth.gd", false), "test")
	fails += _eq("test + 도구 오토로드", S.classify(true, false, "", true), "test")
	fails += _eq("test + REAL 플래그", S.classify(true, true, "", false), "test")

	fails += _eq("도구 오토로드", S.classify(false, false, "", true), "harness")
	for f in ["shot_story_mark.gd", "dev_story_battle.gd", "probe_tutorial_boot.gd",
			"check_scripts.gd", "grant_items.gd", "skill_test_mode.gd"]:
		fails += _eq("--script scripts/tools/%s" % f,
			S.classify(false, false, "res://scripts/tools/" + f, false), "harness")
	fails += _eq("역슬래시 경로도 같다",
		S.classify(false, false, "C:\\repo\\scripts\\tools\\shot_x.gd", false), "harness")
	fails += _eq("scripts/ui 는 하네스 아님",
		S.classify(false, false, "res://scripts/ui/story.gd", false), "normal")

	fails += _eq("REAL 플래그가 하네스를 이긴다", S.classify(false, true, "", true), "normal")

	fails += _eq("일반 실행", S.classify(false, false, "", false), "normal")
	fails += _eq("게임 스크립트는 하네스 아님", S.classify(false, false, "main.gd", false), "normal")

	fails += _true("ShotHelper 가 기준선 목록에 있다",
		"ShotHelper" in S.BASELINE_TOOL_AUTOLOADS)
	var committed := _committed_autoloads()
	for name in committed:
		if not (name in S.BASELINE_TOOL_AUTOLOADS):
			fails += _eq("커밋된 도구 오토로드 '%s' 가 기준선에 없다" % name, false, true)

	print("=== test_save_guard: %s ===" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(1 if fails else 0)

func _committed_autoloads() -> Array:
	var out: Array = []
	var f := FileAccess.open("res://project.godot", FileAccess.READ)
	if f == null:
		return out
	var in_block := false
	while not f.eof_reached():
		var ln := f.get_line().strip_edges()
		if ln.begins_with("["):
			in_block = ln == "[autoload]"
			continue
		if not in_block or ln.find("=") < 0:
			continue
		var name := ln.substr(0, ln.find("=")).strip_edges()
		var path := ln.substr(ln.find("=") + 1).strip_edges().replace("\"", "").replace("*", "")
		if path.begins_with("res://scripts/tools/"):
			out.append(name)
	return out

func _true(what: String, ok: bool) -> int:
	return 0 if ok else _eq(what, false, true)

func _eq(what: String, got, want) -> int:
	if got == want:
		return 0
	print("  FAIL %s: got=%s want=%s" % [what, str(got), str(want)])
	return 1
