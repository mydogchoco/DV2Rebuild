extends Node

const SAVE_NAME := "save_0.json"
const BACKUP_NAME := "save_0.bak.json"

const TEST_DIR := "user://test_save/"

const HARNESS_DIR := "user://harness_save/"

const ENV_REAL := "DV2_REAL_SAVE"
const ENV_TEST := "DV2_TEST_SAVE"

const VERIFY_DIR := "user://verify_save/"
const VERIFY_FEATURE := "verifybuild"

var SAVE_PATH := "user://" + SAVE_NAME
var BACKUP_PATH := "user://" + BACKUP_NAME

const PREFS_NAME := "prefs.json"
var PREFS_PATH := "user://" + PREFS_NAME

var save_dir := "user://"

var read_dir := "user://"

var mode := "normal"

var READ_PATH := "user://" + SAVE_NAME
var READ_BACKUP_PATH := "user://" + BACKUP_NAME
var READ_PREFS_PATH := "user://" + PREFS_NAME

static func classify(env_test: bool, env_real: bool, script_path: String,
		has_tool_autoload: bool) -> String:
	if env_test:
		return "test"
	if script_path.get_file().begins_with("test_"):
		return "test"
	if env_real:
		return "normal"
	if has_tool_autoload or _is_tool_script(script_path):
		return "harness"
	return "normal"

static func _is_tool_script(script_path: String) -> bool:
	return script_path.replace("\\", "/").find("scripts/tools/") >= 0

static func _script_arg() -> String:
	var args := OS.get_cmdline_args()
	for i in args.size():
		var a := String(args[i])
		if a == "--script" and i + 1 < args.size():
			return String(args[i + 1])
		if a.begins_with("--script="):
			return a.substr("--script=".length())
	return ""

const BASELINE_TOOL_AUTOLOADS := ["ShotHelper"]

static func _has_tool_autoload() -> bool:
	for p in ProjectSettings.get_property_list():
		var key := String(p.get("name", ""))
		if not key.begins_with("autoload/"):
			continue
		if key.substr("autoload/".length()) in BASELINE_TOOL_AUTOLOADS:
			continue
		var v := String(ProjectSettings.get_setting(key, ""))
		if v.replace("*", "").begins_with("res://scripts/tools/"):
			return true
	return false

static func _is_test_run() -> bool:
	return classify(OS.get_environment(ENV_TEST) == "1",
		OS.get_environment(ENV_REAL) == "1", _script_arg(), _has_tool_autoload()) == "test"

func _init() -> void:
	mode = classify(OS.get_environment(ENV_TEST) == "1",
		OS.get_environment(ENV_REAL) == "1", _script_arg(), _has_tool_autoload())
	if OS.has_feature(VERIFY_FEATURE):
		mode = "verify"
	if mode == "verify":
		save_dir = VERIFY_DIR
		read_dir = VERIFY_DIR
	elif mode == "test":
		save_dir = TEST_DIR
		read_dir = TEST_DIR
	elif mode == "harness":
		save_dir = HARNESS_DIR
		read_dir = "user://"
	if save_dir != "user://":
		DirAccess.make_dir_recursive_absolute(save_dir)
	SAVE_PATH = save_dir + SAVE_NAME
	BACKUP_PATH = save_dir + BACKUP_NAME
	PREFS_PATH = save_dir + PREFS_NAME
	READ_PATH = read_dir + SAVE_NAME
	READ_BACKUP_PATH = read_dir + BACKUP_NAME
	READ_PREFS_PATH = read_dir + PREFS_NAME
	if mode == "harness":
		print("[Save] 하네스 실행 — 실세이브는 **읽기 전용**, 쓰기는 %s 로 간다." % HARNESS_DIR)
		print("[Save]   일부러 실세이브를 고쳐야 하면 러너에서 %s=1 을 세운다." % ENV_REAL)
	elif mode == "verify":
		print("[Save] 검증 빌드 — 세이브는 %s 만 읽고 쓴다(기존 세이브는 열지 않는다)." % VERIFY_DIR)

func save(data: Dictionary) -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(SAVE_PATH, BACKUP_PATH)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[Save] cannot write " + SAVE_PATH); return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true

func load_or_backup() -> Variant:
	for p in [SAVE_PATH, READ_PATH]:
		var d = _read(p)
		if d != null:
			return d
	for p in [BACKUP_PATH, READ_BACKUP_PATH]:
		var b = _read(p)
		if b != null:
			push_warning("[Save] 메인 세이브 손상/부재 → 백업에서 복구")
			return b
	return null

func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[Save] corrupt JSON: " + path)
		return null
	return parsed

func clear() -> void:
	var dir := DirAccess.open(save_dir)
	if dir and dir.file_exists(SAVE_NAME):
		dir.remove(SAVE_NAME)

func load_prefs() -> Dictionary:
	var d = _read(PREFS_PATH)
	if not (d is Dictionary):
		d = _read(READ_PREFS_PATH)
	return d if d is Dictionary else {}

func save_prefs(prefs: Dictionary) -> bool:
	var f := FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[Save] cannot write " + PREFS_PATH); return false
	f.store_string(JSON.stringify(prefs, "\t"))
	f.close()
	return true
