extends Node

const L := preload("res://scripts/systems/loadout.gd")

var _log: FileAccess = null

func _ready() -> void:
	_log = FileAccess.open("user://test_skill_learn.txt", FileAccess.WRITE)
	var fails := 0
	fails += _compiles()
	fails += _can_learn()
	fails += _learn_flow()
	fails += _grants()
	_say("")
	_say("=== %s ===" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	if _log:
		_log.flush()

func _compiles() -> int:
	var fails := 0
	_say("[컴파일] 수정한 스크립트")
	for p in ["res://scripts/systems/loadout.gd", "res://scripts/ui/cave.gd",
			"res://scripts/tools/shot_helper.gd"]:
		fails += _true(String(p).get_file(), load(String(p)) != null)
	return fails

func _can_learn() -> int:
	var fails := 0
	_say("[게이트] 순차 학습")
	var sid := 11
	fails += _true("테스트 스킬 %d 존재" % sid, Data.skills.has(str(sid)))
	fails += _eq("최대 레벨", int(Data.skills[str(sid)].get("max_level", 0)), 5)

	fails += _true("미보유 → Lv.1 가능", L.can_learn([], sid, 1))
	fails += _true("미보유 → Lv.2 불가", not L.can_learn([], sid, 2))
	fails += _true("미보유 → Lv.3 불가", not L.can_learn([], sid, 3))

	var lv1 := [{"id": sid, "level": 1, "dedicated": false}]
	fails += _true("Lv.1 보유 → Lv.1 재습득 불가", not L.can_learn(lv1, sid, 1))
	fails += _true("Lv.1 보유 → Lv.2 가능", L.can_learn(lv1, sid, 2))
	fails += _true("Lv.1 보유 → Lv.3 불가(건너뛰기)", not L.can_learn(lv1, sid, 3))

	var lv3 := [{"id": sid, "level": 3, "dedicated": false}]
	fails += _true("Lv.3 보유 → Lv.4 가능", L.can_learn(lv3, sid, 4))
	fails += _true("Lv.3 보유 → Lv.2 불가(다운그레이드)", not L.can_learn(lv3, sid, 2))
	fails += _true("다른 번호는 영향 없음", L.can_learn(lv3, 12, 1))
	return fails

func _learn_flow() -> int:
	var fails := 0
	_say("[습득] 스킬 아이템 사용")
	var sid := 11
	var pool: Array = []
	var blocked: Dictionary = L.learn_from_item(pool, sid, 3, Data.skills)
	fails += _true("Lv.3 스크롤 선사용 거부", not bool(blocked.get("ok", true)))
	fails += _true("거부 문구 = 원작 CaveSkillUseMsg1",
		String(blocked.get("msg", "")) == L.LEARN_BLOCKED_MSG)
	fails += _eq("거부 시 풀 불변", (blocked["skills"] as Array).size(), 0)

	for lv in range(1, 6):
		var r: Dictionary = L.learn_from_item(pool, sid, lv, Data.skills)
		fails += _true("Lv.%d 순차 습득" % lv, bool(r.get("ok", false)))
		pool = r["skills"]
		fails += _eq("풀 크기(같은 번호는 1개)", pool.size(), 1)
		fails += _eq("현재 레벨", int((pool[0] as Dictionary)["level"]), lv)
		fails += _true("Lv.1 만 신규 표기", bool(r.get("is_new", false)) == (lv == 1))

	var over: Dictionary = L.learn_from_item(pool, sid, 6, Data.skills)
	fails += _true("만렙 초과 거부", not bool(over.get("ok", true)))
	fails += _eq("만렙 유지", int((pool[0] as Dictionary)["level"]), 5)

	var other: Dictionary = L.learn_from_item(pool, 12, 1, Data.skills)
	fails += _true("다른 스킬 Lv.1 습득", bool(other.get("ok", false)))
	fails += _eq("학습 풀 2종", (other["skills"] as Array).size(), 2)
	return fails

func _grants() -> int:
	var fails := 0
	_say("[자동습득] Lv.10·25·45")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260731
	var pool: Array = []
	for _i in 20:
		var g: Dictionary = L.roll_grant(pool, Data.skills, rng)
		if g.is_empty():
			break
		fails += _eq("자동 습득은 Lv.1", int(g["level"]), 1)
		fails += _true("게이트 통과", L.can_learn(pool, int(g["id"]), int(g["level"])))
		var r: Dictionary = L.learn_from_item(pool, int(g["id"]), int(g["level"]), Data.skills)
		fails += _true("자동 습득분 반영", bool(r.get("ok", false)))
		pool = r["skills"]
	return fails

func _eq(label: String, got: int, want: int) -> int:
	var ok := got == want
	_say("  %s %s: %d (기대 %d)" % ["OK " if ok else "FAIL", label, got, want])
	return 0 if ok else 1

func _true(label: String, ok: bool) -> int:
	_say("  %s %s" % ["OK " if ok else "FAIL", label])
	return 0 if ok else 1

func _say(s: String) -> void:
	print(s)
	if _log:
		_log.store_line(s)
