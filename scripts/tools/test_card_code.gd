extends Node
## 헤드리스 CardCode 검증 — GDScript 복호가 `build_card_codes.py` 암호화와 **바이트 단위로 맞는가**.
##
## 실행(프로젝트 부팅 경로 — `--script` 모드는 이 환경에서 멈춘다, [[dv2-godot-runtime-and-validation]]):
##   project.godot [autoload] 에 `TestCardCode="*res://scripts/tools/test_card_code.gd"` 임시 등록
##   → `Godot --path . --headless --quit-after 20` → 결과는 scratch_shots/test_card_code.txt
##
## 대상은 사용자의 실제 코드표(`data/card_codes.json`)가 **아니라** 고정 픽스처다 —
## 실제 표는 gitignore 된 평문 CSV 에서 나오므로 세션마다 내용이 다르고, 검증이 거기 매이면 안 된다.
## ⚠️ 픽스처의 플래그 이름은 **일부러 더미**(`TestOnlyFlag`)다 — 이 파일과 픽스처 CSV 는
##    공개 레포에 올라가므로 실제 해금 플래그 이름을 여기 적으면 트리거가 노출된다.
## 픽스처 재생성:
##   python scripts/tools/build_card_codes.py --csv scripts/tools/fixtures/card_codes_test.csv \
##       --out scripts/tools/fixtures/card_codes_test.json --verify

const OUT := "res://scratch_shots/test_card_code.txt"
const FIXTURE := "res://scripts/tools/fixtures/card_codes_test.json"

var _log: FileAccess = null
var _fails := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://scratch_shots")
	_log = FileAccess.open(OUT, FileAccess.WRITE)
	_say("=== CardCode 검증 ===")

	var f := FileAccess.open(FIXTURE, FileAccess.READ)
	if f == null:
		_say("❌ 픽스처 없음: " + FIXTURE); _done(); return
	var table = JSON.parse_string(f.get_as_text())
	if not (table is Dictionary):
		_say("❌ 파싱 실패"); _done(); return
	_say("항목 수: %d / iter=%d" % [(table.get("entries", []) as Array).size(),
		int(table.get("iter", 0))])

	# 1) 정규화 — 하이픈·공백·소문자를 흡수하는가
	_eq("정규화(하이픈)", CardCode.normalize("test-1234-abcd-5678"), "TEST1234ABCD5678")
	_eq("정규화(공백)", CardCode.normalize("ZZZZ 9999 QQQQ 0000"), "ZZZZ9999QQQQ0000")

	# 2) 조회·복호 — 파이썬이 넣은 페이로드가 그대로 나오는가
	var t0 := Time.get_ticks_msec()
	var a := CardCode.lookup("TEST-1234-ABCD-5678", table)
	var dt := Time.get_ticks_msec() - t0
	_say("조회 1회 소요: %d ms" % dt)
	_true("코드A 인식", not a.is_empty())
	if not a.is_empty():
		_eq("코드A 문구", String(a.get("msg", "")), "테스트 코드입니다!")
		_true("코드A 1회성", bool(a.get("once", false)))
		var rw: Array = a.get("rewards", [])
		_eq("코드A 보상 수", str(rw.size()), "2")
		if rw.size() == 2:
			_eq("보상1 종류", String((rw[0] as Dictionary).get("t", "")), "gold")
			_eq("보상1 수량", str(int((rw[0] as Dictionary).get("n", 0))), "50000")
			_eq("보상2 종류", String((rw[1] as Dictionary).get("t", "")), "item")
			_eq("보상2 키", String((rw[1] as Dictionary).get("k", "")), "potion_hp")

	# 3) 플래그 보상 — 빌드에는 **해시만** 실려야 한다
	var b := CardCode.lookup("zzzz9999qqqq0000", table)   # 소문자·구분자 없이도 같아야 한다
	_true("코드B 인식(소문자)", not b.is_empty())
	if not b.is_empty():
		var rb: Array = b.get("rewards", [])
		if rb.size() == 1:
			var r0: Dictionary = rb[0]
			_eq("보상 종류", String(r0.get("t", "")), "flag")
			_eq("플래그 해시", String(r0.get("k", "")), "2dd1ed83e85463f9e512d3f31402686c")
			_true("평문 이름 미포함", not String(r0.get("k", "")).contains("Flag"))

	# 4) 틀린 코드는 빈 사전
	_true("없는 코드 거부", CardCode.lookup("AAAA-BBBB-CCCC-DDDD", table).is_empty())
	_true("빈 입력 거부", CardCode.lookup("", table).is_empty())

	# 5) 원문이 파일에 남지 않는가 — 암호문에서 평문 조각이 보이면 실패
	var raw := FileAccess.open(FIXTURE, FileAccess.READ).get_as_text()
	_true("파일에 코드 평문 없음", not raw.contains("TEST1234") and not raw.to_lower().contains("test-1234"))
	_true("파일에 보상 평문 없음", not raw.contains("potion_hp"))
	_true("파일에 플래그명 없음", not raw.contains("TestOnlyFlag"))

	# 6) 실제 표(사용자 코드)도 형식은 맞아야 한다 — 내용은 보지 않는다
	var live := FileAccess.open("res://data/card_codes.json", FileAccess.READ)
	_true("실제 표 존재", live != null)
	if live != null:
		var lt = JSON.parse_string(live.get_as_text())
		_true("실제 표 파싱", lt is Dictionary and (lt as Dictionary).has("entries"))
		if lt is Dictionary:
			var bad := false
			for e in (lt as Dictionary).get("entries", []):
				for k in (e as Dictionary).keys():
					if not ["id", "n", "d", "t"].has(String(k)):
						bad = true
			_true("실제 표에 암호문 외 필드 없음", not bad)

	_done()


func _say(s: String) -> void:
	print(s)
	if _log: _log.store_line(s); _log.flush()

func _true(name: String, ok: bool) -> void:
	if not ok: _fails += 1
	_say(("  ✅ " if ok else "  ❌ ") + name)

func _eq(name: String, got: String, want: String) -> void:
	var ok := got == want
	if not ok: _fails += 1
	_say(("  ✅ " if ok else "  ❌ ") + name + ("" if ok else "  got=%s want=%s" % [got, want]))

func _done() -> void:
	_say("실패 %d 건" % _fails)
	if _log: _log.close()
	get_tree().quit(0 if _fails == 0 else 1)
