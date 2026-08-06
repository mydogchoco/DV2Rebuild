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


# ── B. 통합 (세이브 왕복 — 끝에 전부 되돌린다) ──────────────
## 🟦 2026-08-07 — 지급처가 **둥지 → 가방 알 탭** 으로 바뀌었다(사용자 확정).
## 이 절은 `magicshop.gd::_do_summon` 이 실제로 하는 상태 반영을 같은 순서로 따라 한다.
func _integration() -> void:
	_say("[B] 세이브 왕복")
	var flag_bak = UserDB.get_pmeta(Summon.FLAG_UNLOCK, false)
	# 아직 안 만든 종을 고른다 — 검증용 세이브에 한 쪽이 이미 있어도 나머지로 돈다.
	var target := 0
	var bag_key := ""
	for sp in Summon.SPECIES:
		var k := EggItem.key(EggGacha.key_for(int(sp)), Summon.EGG_ENHANCE_STEP)
		if UserDB.dex_step(int(sp)) <= 0 and UserDB.item_count(k) <= 0:
			target = int(sp)
			bag_key = k
			break
	if target == 0:
		_say("  ⏭ 커스텀 종 둘 다 이미 있어 통합 검증 생략")
		return

	# 재료용 임시 드래곤(끝에 정리한다). 자격 하한을 넘겨야 재료가 된다(레벨 45 · 등급 10.0).
	var mat_inst := UserDB.add_dragon(101, Summon.MATERIAL_MIN_LEVEL)
	var mg := Summon.MATERIAL_MIN_GRADE
	var mat_uid := int(mat_inst["uid"])
	mat_inst["nickname"] = "테스트재료"
	var before := UserDB.dragons().size()
	# ⚠️ `get_pmeta` 는 저장된 **그 사전 자체**를 돌려준다 — 그대로 들고 있으면
	#   아래 set_species_* 가 백업본까지 같이 고쳐 복원이 무의미해진다(2026-08-07 실제 사고).
	var name_bak: Dictionary = (UserDB.get_pmeta("species_names", {}) as Dictionary).duplicate(true)
	var art_bak: Dictionary = (UserDB.get_pmeta("species_art", {}) as Dictionary).duplicate(true)

	# 잠긴 상태에서는 아무 일도 없어야 한다
	UserDB.set_pmeta(Summon.FLAG_UNLOCK, false)
	_true("잠김이면 계획 없음",
		Summon.plan(target, mat_inst, Data.get_dragon(101), false, UserDB.dex_step(target), mg).is_empty())

	# 해금 후 실행 — `_do_summon` 과 같은 순서
	UserDB.set_pmeta(Summon.FLAG_UNLOCK, true)
	var p := Summon.plan(target, mat_inst, Data.get_dragon(101), true, UserDB.dex_step(target), mg)
	_true("계획 산출", not p.is_empty())
	if not p.is_empty():
		var inh: Dictionary = p["inherit"]
		UserDB.set_species_art(target, int(inh["art_id"]), String(inh["element"]))
		UserDB.set_species_name(target, String(inh["name"]))
		UserDB.add_item(bag_key, 1)
		UserDB.consume_dragon(mat_uid)
		UserDB.set_pmeta(Summon.FLAG_UNLOCK, false)

		_eq("가방 알 키", bag_key, "egg:%d#%d" % [target, Summon.EGG_ENHANCE_STEP])
		_eq("가방에 1개", str(UserDB.item_count(bag_key)), "1")
		_true("둥지에는 안 생긴다", UserDB.dragons().size() == before - 1)
		_true("재료 소멸", UserDB.get_dragon(mat_uid).is_empty())
		_true("플래그 소비됨", not bool(UserDB.get_pmeta(Summon.FLAG_UNLOCK, false)))
		# 상속값이 **종**에 붙어 인벤을 거쳐도 살아남는가(스택 아이템은 개체 필드가 없다)
		_eq("종 art_id 기록", str(Icons.species_art_id(target)), "101")
		_eq("종 속성 기록", Icons.species_element(target), String(Data.get_dragon(101).get("element", "")))
		_eq("종 이름 기록", Icons.species_name(target), "테스트재료")
		_true("알 그림 해석됨", Icons.dragon_egg_texture(target) != null)
		# 가방 알 하나가 상한을 막는가(도감 단계는 아직 0 이다)
		_eq("도감 단계는 아직 0", str(UserDB.dex_step(target)), "0")
		# 부화 규칙 — 1강 = 등급 7.0 확정 · 그 등급의 표준 부화 시간
		var ecfg: Dictionary = Data.laboratory.get("egg_upgrade", {})
		var g := Hatchery.grade_for(EggItem.grade_of(bag_key), ecfg, 0.0, false)
		_eq("부화 등급 확정", str(g), str(Hatchery.GRADE_MAX))
		_eq("부화 시간", str(Hatchery.hatch_seconds(g)), str(int(p["seconds"])))

	# 정리
	UserDB.use_item(bag_key, UserDB.item_count(bag_key))
	if UserDB.get_dragon(mat_uid).size() > 0:
		UserDB.consume_dragon(mat_uid)
	UserDB.set_pmeta(Summon.FLAG_UNLOCK, flag_bak)
	UserDB.set_pmeta("species_names", name_bak)
	UserDB.set_pmeta("species_art", art_bak)
	_eq("정리 후 개체 수 원복", str(UserDB.dragons().size()), str(before - 1))
	_eq("정리 후 가방 빈", str(UserDB.item_count(bag_key)), "0")


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
