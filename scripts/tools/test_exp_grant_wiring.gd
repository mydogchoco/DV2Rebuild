extends SceneTree

const GRANT_SITES := {
	"res://scripts/ui/battle.gd": "전투 경험치",
	"res://scripts/ui/promote.gd": "육성 탭 훈련",
	"res://scripts/ui/cave.gd": "동굴 먹이주기",
}
const SRC_DIRS := ["res://scripts/core", "res://scripts/systems", "res://scripts/ui"]
const UDB := "res://scripts/core/user_db.gd"

var _fail := 0

func _ok(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
	else:
		print("  FAIL  ", label)
		_fail += 1

func _init() -> void:
	var udb := _read(UDB)

	print("=== 1) 지급 통로 ===")
	var gi := udb.find("func grant_exp(")
	_ok(gi >= 0, "UserDB.grant_exp 가 있다")
	if gi >= 0:
		var body := udb.substr(gi, udb.find("\nfunc ", gi + 1) - gi)
		_ok(body.contains("apply_levelups("), "grant_exp 안에서 apply_levelups 를 부른다")
		_ok(body.contains("LevelSystem.apply_exp("), "레벨 규칙은 LevelSystem 이 정한다")

	print("\n=== 2) 레벨 판정 없는 exp 가산이 없다 ===")
	_ok(not udb.contains("func add_exp("), "UserDB.add_exp(레벨 판정 없는 가산)가 없다")

	print("\n=== 3) 우회로가 없다 ===")
	for path in _sources():
		if path == UDB:
			continue
		var n := 0
		for line in _read(path).split("\n"):
			var t := line.strip_edges()
			if t.begins_with("#"):
				continue
			if t.contains("[\"exp\"] =") or (t.contains("set_dragon_field(") and t.contains("\"exp\"")):
				n += 1
		if n > 0:
			_ok(false, "%s 가 드래곤 exp 를 직접 쓴다 (%d곳)" % [path.get_file(), n])
	_ok(true, "게임 코드 %d개에 exp 직접 쓰기 없음" % _sources().size())

	print("\n=== 4) 지급 경로가 통로를 거친다 ===")
	for path: String in GRANT_SITES:
		_ok(_read(path).contains("grant_exp("), "%s → grant_exp" % GRANT_SITES[path])

	print("\n=== %s ===" % ("PASS" if _fail == 0 else "FAIL %d" % _fail))
	quit(1 if _fail > 0 else 0)

func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f else ""

func _sources() -> Array:
	var out: Array = []
	for d: String in SRC_DIRS:
		for n in DirAccess.get_files_at(d):
			if n.ends_with(".gd"):
				out.append("%s/%s" % [d, n])
	return out
