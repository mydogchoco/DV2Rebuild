extends Node
## 헤드리스 검증 — 점술집 '드래곤 소환'(보유 드래곤 → 커스텀 종 600/700 알).
##
## 실행: project.godot [autoload] 에 임시 등록 → `Godot --path . --headless --quit-after 40`
##       결과는 scratch_shots/test_summon.txt
##
## ⚠️ 뒷부분은 **실제 세이브를 건드린다** — 만든 것을 전부 되돌리고 해금 플래그도 원상복구한다
##    (test_cave_equip_integration 과 같은 관례).

const OUT := "res://scratch_shots/test_summon.txt"

var _log: FileAccess = null
var _fails := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://scratch_shots")
	_log = FileAccess.open(OUT, FileAccess.WRITE)
	_say("=== Summon 검증 ===")

	_logic()
	_integration()

	_say("실패 %d 건" % _fails)
	if _log: _log.close()
	get_tree().quit(0 if _fails == 0 else 1)


# ── A. 순수 로직 (세이브를 건드리지 않는다) ────────────────────────────────────
func _logic() -> void:
	_say("[A] 규칙")
	# ⚠️ 재료 자격 하한(레벨 45 · 등급 10.0)을 넘는 개체로 잡는다 — 하한 자체는 4) 에서 잰다.
	var mat := {"uid": 1, "id": 101, "level": 45, "nickname": "치코"}
	var G := Summon.MATERIAL_MIN_GRADE
	var master := {"id": 101, "element": "fire", "art_id": 101}

	# 1) 기본 잠김 — 플래그가 없으면 무조건 불가
	_true("잠김이면 불가", Summon.plan(600, mat, master, false, 0, G).is_empty())

	# 2) 해금되면 계획이 나온다. 등급=최고 고정, 시간=그 등급의 표준 부화 시간
	var p := Summon.plan(600, mat, master, true, 0, G)
	_true("해금이면 가능", not p.is_empty())
	if not p.is_empty():
		_eq("종", str(int(p["species"])), "600")
		_eq("등급=최고 고정", str(float(p["grade"])), str(Hatchery.GRADE_MAX))
		_eq("부화 시간", str(int(p["seconds"])), str(Hatchery.hatch_seconds(Hatchery.GRADE_MAX)))
		var inh: Dictionary = p["inherit"]
		_eq("상속 art_id", str(int(inh["art_id"])), "101")
		_eq("상속 속성", String(inh["element"]), "fire")
		_eq("상속 별명", String(inh["nickname"]), "치코")

	# 3) 세이브당 1마리 상한 — 이미 가진(도감 단계>0) 종은 불가
	_true("이미 보유한 종 불가", Summon.plan(600, mat, master, true, 4, G).is_empty())
	_eq("둘 다 없으면 후보 2", str(Summon.available_species({600: 0, 700: 0}).size()), "2")
	_eq("하나 있으면 후보 1", str(Summon.available_species({600: 2, 700: 0}).size()), "1")
	_eq("둘 다 있으면 후보 0", str(Summon.available_species({600: 4, 700: 6}).size()), "0")

	# 4) 재료 자격 — 알·잠금·커스텀 종은 바칠 수 없다
	var LV := Summon.MATERIAL_MIN_LEVEL
	_true("일반 개체 OK", Summon.can_be_material(mat, G))
	_true("알 거부", not Summon.can_be_material({"id": 101, "level": LV, "egg": true}, G))
	_true("잠금 거부", not Summon.can_be_material({"id": 101, "level": LV, "locked": true}, G))
	_true("커스텀 600 거부", not Summon.can_be_material({"id": 600, "level": LV}, G))
	_true("커스텀 700 거부", not Summon.can_be_material({"id": 700, "level": LV}, G))
	_true("빈 개체 거부", not Summon.can_be_material({}, G))

	# 4-1) 자격 하한(🟦 사용자 확정 2026-07-30) — 레벨 45 · 등급 10.0. 경계에서 갈린다.
	_true("레벨 1 모자라면 거부",
		not Summon.can_be_material({"id": 101, "level": LV - 1}, G))
	_true("등급이 조금 모자라면 거부",
		not Summon.can_be_material({"id": 101, "level": LV}, G - 0.1))
	_true("경계값은 통과", Summon.can_be_material({"id": 101, "level": LV}, G))
	_true("등급을 안 넘기면 거부(닫힌 실패)", not Summon.can_be_material({"id": 101, "level": LV}))
	_true("자격 미달이면 plan 도 빈다",
		Summon.plan(600, {"uid": 1, "id": 101, "level": LV - 1}, master, true, 0, G).is_empty())

	# 5) 커스텀 종은 마스터에 그림·속성이 없다 — 상속이 유일한 출처임을 고정
	for sp in Summon.SPECIES:
		var d := Data.get_dragon(int(sp))
		_true("종 %d 존재" % sp, not d.is_empty())
		_true("종 %d 도감 기본숨김" % sp, Data.dragon_hidden(int(sp)))
		_true("종 %d stages 비어있음" % sp, (d.get("stages", {}) as Dictionary).is_empty())


# ── B. 통합 (세이브 왕복 — 끝에 전부 되돌린다) ──────────────────────────────
func _integration() -> void:
	_say("[B] 세이브 왕복")
	var flag_bak = UserDB.get_pmeta(Summon.FLAG_UNLOCK, false)
	var target := Summon.SPECIES_DEF
	if UserDB.dex_step(target) > 0:
		_say("  ⏭ 이미 %d 종을 보유 중이라 통합 검증 생략" % target)
		return

	# 재료용 임시 드래곤(끝에 정리한다). 자격 하한을 넘겨야 재료가 된다(레벨 45 · 등급 10.0).
	var mat_inst := UserDB.add_dragon(101, Summon.MATERIAL_MIN_LEVEL)
	var mg := Summon.MATERIAL_MIN_GRADE
	var mat_uid := int(mat_inst["uid"])
	mat_inst["nickname"] = "테스트재료"
	var before := UserDB.dragons().size()
	var sky_before: int = (UserDB.get_pmeta("sky_nest", []) as Array).size()

	# 잠긴 상태에서는 아무 일도 없어야 한다
	UserDB.set_pmeta(Summon.FLAG_UNLOCK, false)
	_true("잠김이면 계획 없음",
		Summon.plan(target, mat_inst, Data.get_dragon(101), false, UserDB.dex_step(target), mg).is_empty())

	# 해금 후 실행
	UserDB.set_pmeta(Summon.FLAG_UNLOCK, true)
	var p := Summon.plan(target, mat_inst, Data.get_dragon(101), true, UserDB.dex_step(target), mg)
	_true("계획 산출", not p.is_empty())
	var egg_uid := 0
	if not p.is_empty():
		var egg := UserDB.add_egg(int(p["species"]), float(p["grade"]), int(p["seconds"]),
			0, p.get("inherit", {}))
		egg_uid = int(egg["uid"])
		UserDB.consume_dragon(mat_uid)
		UserDB.set_pmeta(Summon.FLAG_UNLOCK, false)

		var got := UserDB.get_dragon(egg_uid)
		_true("알 생성됨", not got.is_empty() and UserDB.is_egg(got))
		_eq("알의 종", str(int(got.get("id", 0))), str(target))
		_eq("상속 art_id 기록", str(int(got.get("art_id", 0))), "101")
		_eq("상속 별명 기록", String(got.get("nickname", "")), "테스트재료")
		_true("남은 부화 시간 있음", UserDB.hatch_remain(got) > 0)
		_true("재료 소멸", UserDB.get_dragon(mat_uid).is_empty())
		_eq("개체 수 유지(재료↔알 교환)", str(UserDB.dragons().size()), str(before))
		_true("플래그 소비됨", not bool(UserDB.get_pmeta(Summon.FLAG_UNLOCK, false)))
		_true("도감에 노출됨", UserDB.dex_step(target) > 0)
		# 하늘둥지에 기록이 남으면 되살려 상한을 우회할 수 있다 — 남지 않아야 한다
		_eq("하늘둥지 기록 없음",
			str((UserDB.get_pmeta("sky_nest", []) as Array).size()), str(sky_before))
		# 이제 같은 종은 더 못 만든다
		_true("상한 적용", Summon.plan(target,
			{"uid": 9, "id": 101, "level": Summon.MATERIAL_MIN_LEVEL},
			Data.get_dragon(101), true, UserDB.dex_step(target), mg).is_empty())

	# 정리 — 만든 알 제거, 플래그 복구
	if egg_uid > 0:
		UserDB.consume_dragon(egg_uid)
	if UserDB.get_dragon(mat_uid).size() > 0:
		UserDB.consume_dragon(mat_uid)
	UserDB.set_pmeta(Summon.FLAG_UNLOCK, flag_bak)
	_eq("정리 후 개체 수 원복", str(UserDB.dragons().size()), str(before - 1))
	_true("정리 후 도감 원복", UserDB.dex_step(target) == 0)


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
