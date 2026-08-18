extends SceneTree

var STAGES := _data_file("stages.json")
const NO_ORIGINAL := ["24", "25"]

var _fails := 0

func _initialize() -> void:
	var f := FileAccess.open(STAGES, FileAccess.READ)
	if f == null:
		print("stages.json 을 못 읽었다"); quit(1); return
	var doc: Dictionary = JSON.parse_string(f.get_as_text())
	var stages: Dictionary = doc.get("stages", {})
	_check(not stages.is_empty(), "스테이지 목록 로드")

	var with_text := 0
	for sid in stages:
		var st: Dictionary = stages[sid]
		var nm := String(st.get("name", sid))
		_check(not st.has("intro"),
			"%s %s: 자작 intro 잔존 없음" % [sid, nm])
		var text := String(st.get("field_text", ""))
		if sid in NO_ORIGINAL:
			_check(text == "", "%s %s: 원작에 없는 필드는 비어 있다" % [sid, nm])
			continue
		if not _check(text != "", "%s %s: field_text 존재" % [sid, nm]):
			continue
		with_text += 1
		var lines := text.split("\n")
		_check(lines.size() == 2, "%s %s: 2줄 (실제 %d)" % [sid, nm, lines.size()])
		if lines.size() < 2:
			continue
		_check(lines[0].begins_with("당신은 ") and lines[0].contains("모험을 떠"),
			"%s %s: 1줄 = 진입 문장" % [sid, nm])
		_check(lines[1].strip_edges() != "", "%s %s: 2줄 = 지역 설명문" % [sid, nm])

	_check(with_text == stages.size() - NO_ORIGINAL.size(),
		"원작 복원 %d / %d" % [with_text, stages.size() - NO_ORIGINAL.size()])

	if _fails == 0:
		print("=== ALL PASS ===")
	else:
		print("=== %d FAIL ===" % _fails)
	quit(1 if _fails > 0 else 0)

func _check(ok: bool, what: String) -> bool:
	if not ok:
		_fails += 1
		print("FAIL  %s" % what)
	return ok

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
