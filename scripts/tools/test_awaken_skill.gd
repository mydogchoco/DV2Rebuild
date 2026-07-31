extends SceneTree
## 헤드리스 단위 테스트 — 각성 스킬 효과(A 탐험 · B 정적).
##
## 검증 관점: **설명대로 동작하는가**. 각 케이스에 원문 설명을 주석으로 달아 둔다.
## 표 = data/skill_awaken.json `skills[].effect` (빌드: build_awaken_effects.py)
## 로직 = scripts/systems/awaken_skill.gd
##
## 실행: godot --headless --path <proj> --script res://scripts/tools/test_awaken_skill.gd --quit-after 3

const A := preload("res://scripts/systems/awaken_skill.gd")
const B := preload("res://scripts/systems/battle.gd")
# ⚠️ 두 스크립트가 서로를 참조하므로(Battle 이 사건 지점에서 AwakenSkill 을 부르고,
#   AwakenSkill 이 Battle._eff 를 읽는다) preload 경유 정적 추론이 약해진다.
#   → 이 파일에서는 `:=` 대신 반환형을 명시한다. 런타임 동작에는 영향이 없다.

var _table: Dictionary = {}
var _combat: Dictionary = {}

func _init() -> void:
	var fails := 0
	_table = _json("res://data/skill_awaken.json")
	_combat = _json("res://data/combat.json")

	fails += _schema_checks()
	fails += _static_checks()
	fails += _condition_checks()
	fails += _explore_checks()
	fails += _damage_pipeline_checks()
	fails += _derived_checks()
	fails += _system_checks()
	fails += _custom_dragon_checks()
	fails += _dynamic_checks()
	fails += _react_checks()
	fails += _late_batch_checks()

	if fails == 0:
		var p: Dictionary = _table.get("_effect_progress", {})
		print("[test_awaken_skill] ALL PASS  (이식 %d / %d)" % [
			int(p.get("_impl", 0)), int(p.get("_total", 0))])
		quit(0)
	else:
		printerr("[test_awaken_skill] %d FAIL" % fails)
		quit(1)


## 표 자체의 무결성 — 102종 전부 분류돼 있고, impl:true 는 실제로 할 일이 있어야 한다.
func _schema_checks() -> int:
	var f := 0
	var skills: Array = _table.get("skills", [])
	# 개수는 시트가 늘 수 있다(자작 드래곤 추가 등) → 하드코딩하지 않고 진행도와 맞춘다.
	f += _eq("각성스킬 수 = _effect_progress._total", skills.size(),
		int((_table.get("_effect_progress", {}) as Dictionary).get("_total", -1)))
	f += _true("적어도 원작 102종은 있다", skills.size() >= 102)
	var n_impl := 0
	for s in skills:
		var no := int((s as Dictionary).get("no", 0))
		var e: Dictionary = (s as Dictionary).get("effect", {})
		f += _true("no=%d 에 effect 가 있다" % no, not e.is_empty())
		f += _true("no=%d tier 표기" % no, String(e.get("tier", "")) in ["A", "B", "C", "D"])
		if bool(e.get("impl", false)):
			n_impl += 1
			# 이식했다면 전투 op 든 탐험 보너스든 **실제로 하는 일**이 있어야 한다.
			# 정적(ops) · 동적(dyn) · 반응(react) · 탐험(explore) 중 하나라도 있어야 한다.
			var has_work := not (e.get("ops", []) as Array).is_empty() \
				or not (e.get("dyn", []) as Array).is_empty() \
				or not (e.get("react", []) as Array).is_empty() \
				or not (e.get("explore", {}) as Dictionary).is_empty()
			f += _true("no=%d impl 인데 하는 일이 없다" % no, has_work)
		else:
			# 미이식이면 **왜 못 하는지**가 남아 있어야 한다(다음 작업의 입력).
			f += _true("no=%d why 기록" % no, String(e.get("why", "")) != "")
	f += _eq("impl 개수 = _effect_progress", n_impl,
		int((_table.get("_effect_progress", {}) as Dictionary).get("_impl", -1)))
	return f


## B 정적 — 조건 없는 것들.
func _static_checks() -> int:
	var f := 0
	# 1 각성된 드래곤의 감각: "해당 드래곤의 크리티컬 확률 10% 증가"
	var p1 := _party([[1, "fire"], [0, "fire"]])
	A.apply_battle(p1, [_enemy("aqua")], _table, {})
	f += _eq("1 자기 크리 +10", B._eff(p1[0], "cri") - B._eff(p1[1], "cri"), 10)
	f += _eq("1 은 아군에게 안 걸린다", B._eff(p1[1], "cri"), 10)

	# 3 각성된 드래곤의 힘: "크리티컬 파워 50% 증가"
	var p3 := _party([[3, "fire"]])
	A.apply_battle(p3, [_enemy("aqua")], _table, {})
	f += _eq("3 크리파워 +50", B._eff(p3[0], "cri_pow"), 50)

	# 67 심연의 마수: "자신의 방어력이 50% 증가합니다" — pct 는 곱이다
	var p67 := _party([[67, "dark"]])
	A.apply_battle(p67, [_enemy("light")], _table, {})
	f += _eq("67 방어력 ×1.5", B._eff(p67[0], "def"), 150)

	# 15 공격의 기운: "모든 아군 드래곤의 공격력 10% 증가"
	var p15 := _party([[15, "fire"], [0, "aqua"], [0, "light"]])
	A.apply_battle(p15, [_enemy("dark")], _table, {})
	for i in 3:
		f += _eq("15 아군 %d 공격력 ×1.1" % i, B._eff(p15[i], "att"), 110)

	# 57 생명의 기운: "모든 아군 드래곤의 체력이 10% 증가" — hp 는 효과가 아니라 hp_max 를 고친다
	var p57 := _party([[57, "wind"], [0, "fire"]])
	var hp0 := int(p57[1]["hp_max"])
	A.apply_battle(p57, [_enemy("dark")], _table, {})
	f += _eq("57 아군 hp_max ×1.1", int(p57[1]["hp_max"]), int(round(float(hp0) * 1.1)))
	f += _eq("57 현재 체력도 함께", int(p57[1]["hp"]), int(p57[1]["hp_max"]))

	# 53 사대신룡-땅: "모든 아군 땅속성 드래곤의 방어력 15% 증가" — 속성이 다르면 안 걸린다
	var p53 := _party([[53, "earth"], [0, "earth"], [0, "fire"]])
	A.apply_battle(p53, [_enemy("dark")], _table, {})
	f += _eq("53 땅 아군 방어 ×1.15", B._eff(p53[1], "def"), 115)
	f += _eq("53 불 아군은 그대로", B._eff(p53[2], "def"), 100)

	# 88 지옥의 악귀: "아군에 불속성 드래곤 1마리 당, 아군 드래곤 크리티컬 확률 8%씩 증가"
	var p88 := _party([[88, "dark"], [0, "fire"], [0, "fire"]])
	A.apply_battle(p88, [_enemy("light")], _table, {})
	f += _eq("88 불 2마리 → 크리 +16", B._eff(p88[0], "cri") - 10, 16)

	# 30 돌풍 포식자: "모든 아군 드래곤이 받는 방어 관통 데미지 30 감소"
	var p30 := _party([[30, "wind"], [0, "fire"]])
	A.apply_battle(p30, [_enemy("dark")], _table, {})
	f += _eq("30 아군 depure +30", B._eff(p30[1], "depure"), 30)
	return f


## 조건부 — 파티/적 구성, 던전 속성, 보스 여부.
func _condition_checks() -> int:
	var f := 0
	# 19 그림자 분신: "파티 내에 그림자 속성 드래곤이 있을 시 해당 드래곤의 공격력 60% 상승"
	var yes := _party([[19, "dark"], [0, "shadow"]])
	A.apply_battle(yes, [_enemy("fire")], _table, {})
	f += _eq("19 그림자 있음 → 공격 ×1.6", B._eff(yes[0], "att"), 160)
	var no := _party([[19, "dark"], [0, "fire"]])
	A.apply_battle(no, [_enemy("fire")], _table, {})
	f += _eq("19 그림자 없음 → 무효", B._eff(no[0], "att"), 100)

	# 94 파괴의 힘: "아군에 어둠속성 드래곤이 2명인 경우, 자신의 공격력을 50% 증가"
	var d2 := _party([[94, "dark"], [0, "dark"], [0, "fire"]])
	A.apply_battle(d2, [_enemy("fire")], _table, {})
	f += _eq("94 어둠 2 → 공격 ×1.5", B._eff(d2[0], "att"), 150)
	var d1 := _party([[94, "dark"], [0, "fire"], [0, "fire"]])
	A.apply_battle(d1, [_enemy("fire")], _table, {})
	f += _eq("94 어둠 1 → 무효", B._eff(d1[0], "att"), 100)

	# 20 그림자 수호신: "혼자인 경우 적용되지 않는다"
	var solo := _party([[20, "shadow"]])
	A.apply_battle(solo, [_enemy("fire")], _table, {})
	f += _eq("20 혼자면 무효", B._dmg_taken_mult(solo[0]), 1.0)
	var duo := _party([[20, "shadow"], [0, "fire"]])
	A.apply_battle(duo, [_enemy("fire")], _table, {})
	f += _true("20 둘이면 자신 받는 피해 +20%", is_equal_approx(B._dmg_taken_mult(duo[0]), 1.2))
	f += _true("20 아군 주는 피해 +10%", is_equal_approx(B._dmg_deal_mult(duo[1]), 1.1))

	# 82 자외선 차단 30: "아군 전체 방어율 15% 증가, 상대 팀에 빛속성이 있는 경우 효과가 30%로"
	var nolight := _party([[82, "light"], [0, "fire"]])
	A.apply_battle(nolight, [_enemy("dark")], _table, {})
	f += _eq("82 상대에 빛 없음 → blk +15", B._eff(nolight[1], "blk") - 10, 15)
	var withlight := _party([[82, "light"], [0, "fire"]])
	A.apply_battle(withlight, [_enemy("light")], _table, {})
	f += _eq("82 상대에 빛 있음 → blk +30", B._eff(withlight[1], "blk") - 10, 30)

	# 4 각성된 땅의 힘: "땅속성 지역 탐험 시 … 능력치 20% 상승" — 던전 속성이 맞을 때만
	var onfield := _party([[4, "earth"]])
	A.apply_battle(onfield, [_enemy("fire")], _table, {"field_element": "earth"})
	f += _eq("4 땅 지역 → 공격 ×1.2", B._eff(onfield[0], "att"), 120)
	var offfield := _party([[4, "earth"]])
	A.apply_battle(offfield, [_enemy("fire")], _table, {"field_element": "fire"})
	f += _eq("4 다른 지역 → 무효", B._eff(offfield[0], "att"), 100)

	# 33 몬스터 헌터: "보스 및 레이드 몬스터에게 추가 대미지 100%"
	var vsboss := _party([[33, "light"]])
	A.apply_battle(vsboss, [_enemy("dark")], _table, {"enemy_boss": true})
	f += _true("33 보스전 → 주는 피해 ×2", is_equal_approx(B._dmg_deal_mult(vsboss[0]), 2.0))
	var vsmob := _party([[33, "light"]])
	A.apply_battle(vsmob, [_enemy("dark")], _table, {"enemy_boss": false})
	f += _true("33 일반몹 → 무효", is_equal_approx(B._dmg_deal_mult(vsmob[0]), 1.0))
	return f


## A 탐험 — 전투 밖 보너스.
func _explore_checks() -> int:
	var f := 0
	# 42 부유한 기운: "탐험시 골드 획득량 50% 증가"
	var b1 := A.explore_bonus([{"awaken_no": 42}], _table)
	f += _eq("42 골드 +50%", int(b1["gold_pct"]), 50)
	f += _true("42 배수 1.5", is_equal_approx(A.mult_of(b1, "gold_pct"), 1.5))
	# 17 구드라의 가호: "전설 난이도 지역에서 아티펙트 장신구 획득 확률 50% 증가"
	var b2 := A.explore_bonus([{"awaken_no": 17}], _table)
	f += _eq("17 아티팩트 확률 +50%", int(b2["artifact_chance_pct"]), 50)
	# 둘 다 가진 파티는 합산된다
	var b3 := A.explore_bonus([{"awaken_no": 42}, {"awaken_no": 17}], _table)
	f += _eq("합산 골드", int(b3["gold_pct"]), 50)
	f += _eq("합산 아티팩트", int(b3["artifact_chance_pct"]), 50)
	# 각성스킬이 없으면 0
	var b4 := A.explore_bonus([{"awaken_no": 0}], _table)
	f += _eq("미각성 → 0", int(b4["gold_pct"]), 0)
	f += _true("배수 1.0", is_equal_approx(A.mult_of(b4, "gold_pct"), 1.0))
	# 미이식(C/D) 스킬은 탐험 보너스를 주지 않는다
	var b5 := A.explore_bonus([{"awaken_no": 2}], _table)
	f += _eq("미이식은 무효", int(b5["gold_pct"]), 0)
	return f


## 새로 넣은 피해 파이프라인 — dmg_deal(주는 배수) · dmg_taken_flat(정액 감소).
func _damage_pipeline_checks() -> int:
	var f := 0
	# 16 공격의 날개: "해당 드래곤이 공격 시 입히는 데미지 20% 증가"
	var atk: Dictionary = B.make_combatant("A", "ally", "fire",
		{"hp": 10, "att": 100, "def": 10, "cri": 0, "evd": 0, "blk": 0, "awaken_no": 16})
	var plain: Dictionary = B.make_combatant("P", "ally", "fire",
		{"hp": 10, "att": 100, "def": 10, "cri": 0, "evd": 0, "blk": 0})
	A.apply_battle([atk, plain], [_enemy("aqua")], _table, {})
	f += _true("16 주는 피해 ×1.2", is_equal_approx(B._dmg_deal_mult(atk), 1.2))
	f += _true("16 은 옆 드래곤에 안 걸린다", is_equal_approx(B._dmg_deal_mult(plain), 1.0))

	var d1: Dictionary = B.make_combatant("D1", "enemy", "wind", {"hp": 100000, "att": 1, "def": 1})
	var d2: Dictionary = B.make_combatant("D2", "enemy", "wind", {"hp": 100000, "att": 1, "def": 1})
	var rng := RandomNumberGenerator.new(); rng.seed = 3
	var boost: Dictionary = B._deal_attack(atk, d1, 1000, false, rng, _combat, {})
	var base: Dictionary = B._deal_attack(plain, d2, 1000, false, rng, _combat, {})
	f += _eq("16 실제 피해 1200 vs 1000", [int(boost["damage"]), int(base["damage"])], [1200, 1000])

	# 14 고요한 바람: "받는 피해량 15 감소 (최소 피해량 1)"
	var tank: Dictionary = B.make_combatant("T", "ally", "wind",
		{"hp": 100000, "att": 1, "def": 1, "awaken_no": 14})
	A.apply_battle([tank], [_enemy("fire")], _table, {})
	f += _eq("14 100 피해 → 85", int(B._apply_dmg(tank, 100)["dmg"]), 85)
	f += _eq("14 10 피해 → 최소 1", int(B._apply_dmg(tank, 10)["dmg"]), 1)

	# 39 보호의 날개: "받는 데미지 10% 감소" — 배수와 정액은 배수 먼저, 정액 나중
	var soft: Dictionary = B.make_combatant("S", "ally", "light",
		{"hp": 100000, "att": 1, "def": 1, "awaken_no": 39})
	A.apply_battle([soft], [_enemy("dark")], _table, {})
	f += _eq("39 100 피해 → 90", int(B._apply_dmg(soft, 100)["dmg"]), 90)
	return f


## C 파생 — 자기/아군 스탯에서 값을 끌어오는 것들(2차 패스).
func _derived_checks() -> int:
	var f := 0
	# 24 달의 비밀: "자신의 크리티컬 확률만큼 공격력 증가 (최대 100%)"
	#   기준 크리 10 → 공격력 +10%. 파생은 **1차 패스가 끝난 뒤**의 크리를 읽어야 한다.
	var p24 := _party([[24, "light"]])
	A.apply_battle(p24, [_enemy("dark")], _table, {})
	f += _eq("24 크리 10 → 공격 110", B._eff(p24[0], "att"), 110)
	# 같은 파티에 크리를 올려 주는 스킬(88)이 있으면 **올라간 값**을 읽어야 한다.
	var p24b := _party([[24, "light"], [88, "dark"], [0, "fire"]])
	A.apply_battle(p24b, [_enemy("dark")], _table, {})
	f += _eq("24 는 88 이 올린 크리(10+8)를 본다", B._eff(p24b[0], "att"), 118)

	# 48 빛의 기사: "자신의 방어력에 비례하여 체력이 증가(방어력 500에서 최대치 50% 적용)"
	var p48 := _party([[48, "light"]])   # 기준 방어 100 → 10%
	var hp48 := int(p48[0]["hp_max"])
	A.apply_battle(p48, [_enemy("dark")], _table, {})
	f += _eq("48 방어 100 → 체력 +10%", int(p48[0]["hp_max"]), int(round(float(hp48) * 1.1)))

	# 86 정의집행: "합계 방어력의 10% 관통 무시, 합계 공격력의 10% 추가데미지 증가"
	var p86 := _party([[86, "holy"]])
	A.apply_battle(p86, [_enemy("dark")], _table, {})
	f += _eq("86 depure = 방어 100 × 0.1", B._eff(p86[0], "depure"), 10)
	f += _eq("86 pure = 공격 100 × 0.1", B._eff(p86[0], "pure"), 10)

	# 18 권위의 팔라곤: "아군 중 자신의 등급이 가장 높으면 방어력의 50%를 공격력에 추가"
	var top := _party([[18, "light"], [0, "fire"]])
	top[0]["grade"] = 8.0; top[1]["grade"] = 5.0
	A.apply_battle(top, [_enemy("dark")], _table, {})
	f += _eq("18 최고등급 → 공격 +방어50%", B._eff(top[0], "att"), 150)
	var low := _party([[18, "light"], [0, "fire"]])
	low[0]["grade"] = 3.0; low[1]["grade"] = 9.0
	A.apply_battle(low, [_enemy("dark")], _table, {})
	f += _eq("18 아니면 무효", B._eff(low[0], "att"), 100)
	var alone := _party([[18, "light"]])
	A.apply_battle(alone, [_enemy("dark")], _table, {})
	f += _eq("18 1대1이면 무조건 발동", B._eff(alone[0], "att"), 150)

	# 61 수호의 거목: "아군 땅 속성 마릿수만큼 10% 상승 (최대 30%)" — 상한 확인
	var g4 := _party([[61, "earth"], [0, "earth"], [0, "earth"]])
	A.apply_battle(g4, [_enemy("dark")], _table, {})
	f += _eq("61 땅 3마리 → +30%(상한)", B._eff(g4[0], "att"), 130)
	return f


## C 시스템 훅 — 각성 게이지 · 스킬 사용횟수/레벨.
func _system_checks() -> int:
	var f := 0
	# 22 냉철한 암흑: "자신의 각성게이지 상승률 15% 증가"
	var p22 := _party([[22, "dark"], [0, "fire"]])
	A.apply_battle(p22, [_enemy("light")], _table, {})
	f += _true("22 충전율 1.15", is_equal_approx(B._gauge_rate(p22[0]), 1.15))
	f += _true("22 는 아군에 안 걸린다", is_equal_approx(B._gauge_rate(p22[1]), 1.0))

	# 27 대지의 기둥: "자신의 방어력이 500 이상이면 아군 땅·빛 드래곤의 게이지 회복량 30% 증가"
	var weak := _party([[27, "earth"], [0, "earth"]])          # 기준 방어 100 → 조건 미달
	A.apply_battle(weak, [_enemy("dark")], _table, {})
	f += _true("27 방어 100 → 무효", is_equal_approx(B._gauge_rate(weak[1]), 1.0))
	var strong := _party([[27, "earth"], [0, "earth"], [0, "fire"]])
	strong[0]["def"] = 600
	A.apply_battle(strong, [_enemy("dark")], _table, {})
	f += _true("27 방어 600 → 땅 아군 1.3", is_equal_approx(B._gauge_rate(strong[1]), 1.3))
	f += _true("27 불 아군은 그대로", is_equal_approx(B._gauge_rate(strong[2]), 1.0))

	# 77 영원의 불길: "자신의 각성 게이지 최소값이 15%로 변경"
	var p77 := _party([[77, "fire"]])
	A.apply_battle(p77, [_enemy("aqua")], _table, {})
	f += _true("77 게이지 바닥 15", is_equal_approx(B._gauge_min(p77[0]), 15.0))

	# 97 하얀매의 친구: "전투 시작 시, 아군 각성 게이지 30% 회복 (중첩 불가)"
	var p97 := _party([[97, "light"], [0, "fire"]])
	A.apply_battle(p97, [_enemy("dark")], _table, {})
	f += _true("97 아군 시작 게이지 30", is_equal_approx(float(p97[1]["awaken_gauge"]), 30.0))
	# 두 마리가 같이 가져도 30 (중첩 불가 = stack:once)
	var p97b := _party([[97, "light"], [97, "light"]])
	A.apply_battle(p97b, [_enemy("dark")], _table, {})
	f += _true("97 중첩 불가", is_equal_approx(float(p97b[0]["awaken_gauge"]), 30.0))

	# 23 다이즈의 가호: "모든 아군 드래곤의 스킬 사용횟수 +1"
	var p23 := _party([[23, "light"], [0, "fire"]])
	A.apply_battle(p23, [_enemy("dark")], _table, {})
	f += _eq("23 아군 사용횟수 +1", B._skill_uses_bonus(p23[1]), 1)

	# 98 혼돈의 절대자: "아군 혼돈 드래곤 숫자에 따라 1회씩 증가 (최대 3회)"
	var p98 := _party([[98, "chaos"], [0, "chaos"], [0, "chaos"], ])
	A.apply_battle(p98, [_enemy("dark")], _table, {})
	f += _eq("98 혼돈 3마리 → +3", B._skill_uses_bonus(p98[0]), 3)

	# 89 지혜의 별빛: "아군의 스킬이 1레벨 더 높은 효과로 적용"
	var p89 := _party([[89, "light"], [0, "fire"]])
	A.apply_battle(p89, [_enemy("dark")], _table, {})
	f += _eq("89 아군 효과레벨 +1", B._skill_level_bonus(p89[1]), 1)
	return f


## 자작 드래곤 전용 각성스킬 — 조항이 여러 개다. 되는 조항을 하나씩 확인한다.
func _custom_dragon_checks() -> int:
	var f := 0
	var by := {}
	for s in (_table.get("skills", []) as Array):
		by[int((s as Dictionary).get("no", 0))] = s

	# 표에 실제로 들어 있나(dragons.csv/skill_awaken.csv 사용자 추가분)
	f += _true("666 새벽을 가져오는 자 있음", by.has(666))
	f += _true("777 성좌의 주권자 있음", by.has(777))
	if not (by.has(666) and by.has(777)):
		return f
	# 666 은 6조항 전부 이식됐다(회피 시 혼란까지 react 로 처리) → partial 이 없어야 한다.
	f += _true("666 은 전 조항 이식(partial 없음)",
		(by[666]["effect"].get("partial", []) as Array).is_empty())
	# 777 도 2026-08-01 로 전 조항이 이식됐다 — 마지막까지 남았던 '크리 시 방어·회피 절반
	# 무시' 를 93 태양의 불꽃이 연 `crit_halves_guard` 통로로 처리했다(아래 행동 검증).
	f += _true("777 은 전 조항 이식(partial 없음)",
		(by[777]["effect"].get("partial", []) as Array).is_empty())

	# ── 666 샛별 ────────────────────────────────────────────────────────────
	var p666 := _party([[666, "chaos"], [0, "fire"]])
	A.apply_battle(p666, [_enemy("light")], _table, {})
	f += _eq("666 자신 pure +25", B._eff(p666[0], "pure"), 25)
	f += _eq("666 자신 depure_pct 66", B._eff(p666[0], "depure_pct"), 66)
	f += _eq("666 아군 공격력 +6%", B._eff(p666[1], "att"), 106)
	f += _true("666 아군 받는 피해 −6%", is_equal_approx(B._dmg_taken_mult(p666[1]), 0.94))
	f += _true("666 아군 주는 피해 +36%", is_equal_approx(B._dmg_deal_mult(p666[1]), 1.36))
	# '받는 추가 데미지 66% 감소' 가 실제 관통 피해에 걸리는가
	var piercer: Dictionary = B.make_combatant("P", "enemy", "fire",
		{"hp": 999, "att": 1, "def": 1, "pure": 100})
	f += _eq("666 관통 100 → 34", B._pure_damage(piercer, p666[0]), 34)
	# '자신이 공격을 회피하면 상대는 혼란' — 회피 사건 반응(전투당 6회)
	var foe666: Dictionary = _enemy("light")
	B._aw_on_evade(p666[0], foe666, RandomNumberGenerator.new())
	f += _eq("666 회피 → 상대 혼란", B._has_flag(foe666, "confused"), true)

	# ── 777 한울 ────────────────────────────────────────────────────────────
	var p777 := _party([[777, "fire"]])
	A.apply_battle(p777, [_enemy("aqua")], _table, {})
	f += _eq("777 크리파워 +50", B._eff(p777[0], "cri_pow"), 50)
	f += _eq("777 pure_pct 50", B._eff(p777[0], "pure_pct"), 50)
	# 주는 추가 데미지 50% 증가
	var hanul: Dictionary = B.make_combatant("H", "ally", "fire",
		{"hp": 999, "att": 1, "def": 1, "pure": 100, "awaken_no": 777})
	A.apply_battle([hanul], [_enemy("aqua")], _table, {})
	var dummy: Dictionary = B.make_combatant("D", "enemy", "aqua", {"hp": 999, "att": 1, "def": 1})
	f += _eq("777 관통 100 → 150", B._pure_damage(hanul, dummy), 150)
	# 피해 상한 = 최대 체력의 25%
	f += _true("777 피해 상한 25%", is_equal_approx(B._dmg_cap_pct(p777[0]), 25.0))
	var cap_hp := int(p777[0]["hp_max"])
	f += _eq("777 큰 피해가 hp_max 25% 로 잘린다",
		int(B._apply_dmg(p777[0], cap_hp * 10)["dmg"]), int(round(float(cap_hp) * 0.25)))
	# 모든 상태이상 무시 — **해로운 플래그 5종**만 막는다(Battle.DEBUFF_FLAGS)
	var p777b := _party([[777, "fire"]])
	A.apply_battle(p777b, [_enemy("aqua")], _table, {})
	for bad in B.DEBUFF_FLAGS:
		B._add_flag(p777b[0], String(bad), 3, 15)
		f += _eq("777 %s 무시" % bad, B._has_flag(p777b[0], String(bad)), false)
	var plain2 := _party([[0, "fire"]])
	B._add_flag(plain2[0], "stun", 3, 15)
	f += _eq("면역 없으면 기절이 걸린다", B._has_flag(plain2[0], "stun"), true)
	# 🔴 이로운 플래그는 막으면 안 된다 — 종전에 면역이 자기 버프까지 지웠다.
	#    (50 필살 방어의 survive_once · 81 자격을 갖춘 자의 evade_sure)
	B._add_flag(p777b[0], "survive_once", -1, 50)
	f += _eq("777 자기 버프(survive_once)는 유지", B._has_flag(p777b[0], "survive_once"), true)
	B._add_flag(p777b[0], "evade_sure", -1, 81)
	f += _eq("777 자기 버프(evade_sure)는 유지", B._has_flag(p777b[0], "evade_sure"), true)
	# 면역이 막지 **않는** 것 — 지속피해·능력치 감소는 플래그가 아니라 다른 효과 종류다.
	(p777b[0]["effects"] as Array).append({"kind": "dot", "pct": 5, "turns": 2, "source": 32})
	f += _true("777 지속피해(dot)는 안 막는다(경계 확인)",
		B._has_flag(p777b[0], "status_immune"))
	# 크리티컬 발동 시 상대 방어율·회피율의 절반 무시 (93 태양의 불꽃과 같은 통로).
	#
	# ⚠️ 시드를 맞춘 1:1 비교는 성립하지 않는다 — 이 플래그는 크리를 **먼저** 굴리므로
	#    난수 소비 순서가 달라진다. 그래서 충분한 표본의 **비율**로 본다.
	# ⚠️ 막기는 횟수로 보면 안 된다 — 회피가 줄어든 만큼 막기 판정 기회가 늘어 상쇄된다.
	#    회피를 통과한 공격 중의 비율로 봐야 절반 무시가 드러난다.
	var p777c := _party([[777, "fire"]])
	A.apply_battle(p777c, [_enemy("aqua")], _table, {})
	p777c[0]["cri"] = 100
	var plain777: Dictionary = _party([[0, "fire"]])[0]
	plain777["cri"] = 100
	var guard777: Dictionary = B.make_combatant("G7", "enemy", "aqua",
		{"hp": 999999, "att": 1, "def": 1, "evd": 60, "blk": 60})
	var rng777 := RandomNumberGenerator.new()
	var n777 := 600
	var miss := [0, 0]
	var blkn := [0, 0]
	for side in 2:
		var atk: Dictionary = plain777 if side == 0 else p777c[0]
		for i in n777:
			rng777.seed = 3000 + i
			var r: Dictionary = B.resolve_attack(atk, guard777, rng777, _combat, {})
			if bool(r.get("miss", false)):
				miss[side] += 1
			elif bool(r.get("block", false)):
				blkn[side] += 1
	var rate0 := float(blkn[0]) / float(n777 - miss[0])
	var rate7 := float(blkn[1]) / float(n777 - miss[1])
	f += _true("777 크리 시 회피가 줄어든다 (%d → %d / %d)" % [miss[0], miss[1], n777],
		miss[1] < miss[0])
	f += _true("777 크리 시 막기 비율이 줄어든다 (%.2f → %.2f)" % [rate0, rate7], rate7 < rate0)

	# ── 50·70 ('추가 데미지' 해석으로 풀린 것들) ────────────────────────────
	var p50 := _party([[50, "light"], [0, "fire"]])
	A.apply_battle(p50, [_enemy("dark")], _table, {})
	f += _eq("50 자신 depure_pct 50", B._eff(p50[0], "depure_pct"), 50)
	f += _eq("50 아군 체력 +10%", int(p50[1]["hp_max"]), 1100)
	var p70 := _party([[70, "dark"], [0, "fire"]])
	A.apply_battle(p70, [_enemy("light")], _table, {})
	f += _eq("70 아군 depure_pct 50", B._eff(p70[1], "depure_pct"), 50)
	f += _eq("70 자신 pure_pct 50", B._eff(p70[0], "pure_pct"), 50)
	return f


## D-1 동적 — 라운드마다 다시 계산되는 조건.
func _dynamic_checks() -> int:
	var f := 0
	# 99 혼돈의 힘: "자신의 남은 체력이 50% 이하일 때, 피해량이 50% 증가"
	var p99 := _party([[99, "chaos"]])
	A.apply_battle(p99, [_enemy("light")], _table, {})
	B._aw_refresh_dynamic(p99, [_enemy("light")])
	f += _true("99 만피면 무효", is_equal_approx(B._dmg_deal_mult(p99[0]), 1.0))
	p99[0]["hp"] = int(p99[0]["hp_max"]) / 2          # 50% 로 내린다
	B._aw_refresh_dynamic(p99, [_enemy("light")])
	f += _true("99 체력 50% → 주는 피해 ×1.5", is_equal_approx(B._dmg_deal_mult(p99[0]), 1.5))
	p99[0]["hp"] = int(p99[0]["hp_max"])              # 회복하면 다시 꺼져야 한다
	B._aw_refresh_dynamic(p99, [_enemy("light")])
	f += _true("99 회복하면 다시 무효", is_equal_approx(B._dmg_deal_mult(p99[0]), 1.0))

	# 5 각성된 맹수의 발톱: "체력이 50% 이하일때 크리티컬 확률 100% 고정"
	var p5 := _party([[5, "fire"]])
	A.apply_battle(p5, [_enemy("aqua")], _table, {})
	B._aw_refresh_dynamic(p5, [_enemy("aqua")])
	f += _eq("5 만피면 확정크리 아님", B._has_flag(p5[0], "crit_sure"), false)
	p5[0]["hp"] = int(p5[0]["hp_max"]) / 4
	B._aw_refresh_dynamic(p5, [_enemy("aqua")])
	f += _eq("5 체력 25% → 확정크리", B._has_flag(p5[0], "crit_sure"), true)

	# 12 게으름의 화신: 공격력 −20%(정적) + 잃은 체력 비례 증가(동적)
	var p12 := _party([[12, "earth"]])
	var hp12 := int(p12[0]["hp_max"])
	A.apply_battle(p12, [_enemy("fire")], _table, {})
	f += _eq("12 최대 체력 +50%", int(p12[0]["hp_max"]), int(round(float(hp12) * 1.5)))
	B._aw_refresh_dynamic(p12, [_enemy("fire")])
	f += _eq("12 만피면 공격 −20%", B._eff(p12[0], "att"), 80)
	p12[0]["hp"] = int(p12[0]["hp_max"]) / 2          # 절반 잃음 → +100%p
	B._aw_refresh_dynamic(p12, [_enemy("fire")])
	f += _eq("12 절반 잃으면 −20+100 = +80%", B._eff(p12[0], "att"), 180)
	# ⚠️ 동적이 hp 를 건드리면 라운드마다 최대체력이 불어난다 — 그럴 일이 없어야 한다.
	var before12 := int(p12[0]["hp_max"])
	B._aw_refresh_dynamic(p12, [_enemy("fire")])
	B._aw_refresh_dynamic(p12, [_enemy("fire")])
	f += _eq("12 반복 갱신해도 최대체력 불변", int(p12[0]["hp_max"]), before12)

	# 58 생명의 빛: "생존한 아군 빛 속성 드래곤 1마리마다 공격력 20% 증가 (최대 60%)"
	var p58 := _party([[58, "light"], [0, "light"], [0, "light"]])
	A.apply_battle(p58, [_enemy("dark")], _table, {})
	B._aw_refresh_dynamic(p58, [_enemy("dark")])
	f += _eq("58 빛 3마리 → +60%(상한)", B._eff(p58[0], "att"), 160)
	p58[1]["alive"] = false                            # 하나 쓰러지면 줄어든다
	B._aw_refresh_dynamic(p58, [_enemy("dark")])
	f += _eq("58 2마리 → +40%", B._eff(p58[0], "att"), 140)

	# 72 어둠 속의 빛: 살아 있으면 −10%, 자신이 사망하면 2배(−20%)
	var p72 := _party([[72, "dark"], [0, "fire"]])
	A.apply_battle(p72, [_enemy("light")], _table, {})
	B._aw_refresh_dynamic(p72, [_enemy("light")])
	f += _true("72 생존 중 아군 피해 −10%", is_equal_approx(B._dmg_taken_mult(p72[1]), 0.9))
	p72[0]["alive"] = false
	B._aw_refresh_dynamic(p72, [_enemy("light")])
	f += _true("72 사망 시 −20%", is_equal_approx(B._dmg_taken_mult(p72[1]), 0.8))

	# 37 반항심: "파티의 드래곤 체력이 0이 되면 자신 공격력 30%, 회피율 10% 증가"
	var p37 := _party([[37, "dark"], [0, "fire"]])
	A.apply_battle(p37, [_enemy("light")], _table, {})
	B._aw_refresh_dynamic(p37, [_enemy("light")])
	f += _eq("37 아군 무사하면 무효", B._eff(p37[0], "att"), 100)
	p37[1]["alive"] = false
	B._aw_refresh_dynamic(p37, [_enemy("light")])
	f += _eq("37 아군 사망 → 공격 +30%", B._eff(p37[0], "att"), 130)
	f += _eq("37 회피 +10", B._eff(p37[0], "evd"), 20)
	return f


## D-2 반응 — 전투 중 사건에 붙는 것.
func _react_checks() -> int:
	var f := 0
	var rng := RandomNumberGenerator.new(); rng.seed = 5

	# 21 깨어난 방어 감각: "1회 피격 시 마다 방어력 5% 증가 (누적 50%까지)"
	var p21 := _party([[21, "earth"]])
	A.apply_battle(p21, [_enemy("fire")], _table, {})
	f += _eq("21 시작은 그대로", B._eff(p21[0], "def"), 100)
	for i in 3:
		B._aw_on_hit_taken(p21[0], _enemy("fire"), 10, rng)
	f += _eq("21 3회 피격 → +15%", B._eff(p21[0], "def"), 115)
	for i in 30:                                       # 상한(50%)에서 멈춰야 한다
		B._aw_on_hit_taken(p21[0], _enemy("fire"), 10, rng)
	f += _eq("21 누적 상한 50%", B._eff(p21[0], "def"), 150)

	# 63 신뢰의 힘: "자신이 공격할 때 마다 공격력 10%씩 (최대 100%)"
	var p63 := _party([[63, "light"]])
	A.apply_battle(p63, [_enemy("dark")], _table, {})
	for i in 4:
		B._aw_on_attack_done(p63[0], _enemy("dark"), rng)
	f += _eq("63 4회 공격 → +40%", B._eff(p63[0], "att"), 140)

	# 64 신비한 보호: "막기 발동시 아군 공격력·방어력 2% (최대 30%)"
	var p64 := _party([[64, "aqua"], [0, "fire"]])
	A.apply_battle(p64, [_enemy("dark")], _table, {})
	for i in 3:
		B._aw_on_block(p64[0], rng)
	f += _eq("64 아군 공격 +6%", B._eff(p64[1], "att"), 106)
	f += _eq("64 아군 방어 +6%", B._eff(p64[1], "def"), 106)

	# 2 각성된 드래곤의 영혼: "크리티컬 공격 시 상대 최대 체력의 5% 추가 피해"
	var p2 := _party([[2, "dark"]])
	A.apply_battle(p2, [_enemy("light")], _table, {})
	var foe2: Dictionary = _enemy("light")             # hp_max 1000
	f += _eq("2 크리 추가피해 = 상대 최대체력 5%", B._aw_on_crit_bonus(p2[0], foe2), 50)

	# 96 하얀 번개: "회피하면 상대는 혼란 (전투당 4회)" — 횟수 소진 확인
	var p96 := _party([[96, "wind"]])
	A.apply_battle(p96, [_enemy("fire")], _table, {})
	var hit := 0
	for i in 6:
		var foe: Dictionary = _enemy("fire")
		B._aw_on_evade(p96[0], foe, rng)
		if B._has_flag(foe, "confused"):
			hit += 1
	f += _eq("96 전투당 4회까지만", hit, 4)

	# 81 자격을 갖춘 자: "공격 스킬 발동 시, 다음 공격 무조건 회피 (전투 당 최대 5회)"
	var p81 := _party([[81, "wind"]])
	A.apply_battle(p81, [_enemy("fire")], _table, {})
	B._aw_on_skill_cast(p81[0], [])
	f += _eq("81 스킬 발동 → 확정 회피 플래그", B._has_flag(p81[0], "evade_sure"), true)

	# 45 불타는 날개: 받은 피해를 방어력만큼 누적 → 공격 시 1/3 을 얹고 초기화
	var p45 := _party([[45, "fire"]])                  # 기준 방어 100
	A.apply_battle(p45, [_enemy("aqua")], _table, {})
	B._aw_on_hit_taken(p45[0], _enemy("aqua"), 60, rng)
	B._aw_on_hit_taken(p45[0], _enemy("aqua"), 60, rng)   # 120 → 방어력 100 에서 잘림
	f += _eq("45 누적분 1/3 방출", B._aw_on_attack_bonus(p45[0], _enemy("aqua"), rng), 33)
	f += _eq("45 방출 뒤 초기화", B._aw_on_attack_bonus(p45[0], _enemy("aqua"), rng), 0)

	# 101 희생과 복수: "사망 시 아군 각성기 게이지를 50% 회복"
	var p101 := _party([[101, "light"], [0, "fire"]])
	A.apply_battle(p101, [_enemy("dark")], _table, {})
	B._aw_on_death(p101[0])
	f += _true("101 아군 게이지 +50", is_equal_approx(float(p101[1]["awaken_gauge"]), 50.0))
	return f


# ── helpers ─────────────────────────────────────────────────────────────────
## [[각성no, 속성], …] → 전투원 배열. 기준 스탯을 100 으로 둬서 % 검증이 눈에 보이게 한다.
## 2026-07-31 에 이식한 14종(종전 C_WHY/D_WHY). 각각 **훅이 실제로 도는지** 본다.
func _late_batch_checks() -> int:
	var f := 0
	var rng := RandomNumberGenerator.new()

	# 25 대양의 분노 — 적중마다 상대 방어율 -7 · 자신 크리 +7, 3회까지.
	var p25 := _party([[25, "aqua"]])
	var e25 := _enemy("fire")
	AwakenSkill.apply_battle(p25, [e25], _table, {})
	for i in 5:
		B._aw_on_attack_done(p25[0], e25, rng, 10)
	# 5번 때려도 3회까지만 — `_enemy` 의 기본 방어율은 10 이다.
	f += _eq("25 상대 방어율 -21(3회에서 멈춤)", B._eff(e25, "blk"), 10 - 21)
	f += _eq("25 자신 크리 +21", B._eff(p25[0], "cri"), 10 + 21)

	# 26 대장군 완숙이 — 체력 20% 이하일 때만 피해 1, 3회.
	var p26 := _party([[26, "fire"]])
	AwakenSkill.apply_battle(p26, [], _table, {})
	f += _eq("26 체력이 넉넉하면 그대로", B._aw_fix_damage(p26[0], 500), 500)
	p26[0]["hp"] = 100                                   # 10%
	f += _eq("26 체력 20% 이하면 1", B._aw_fix_damage(p26[0], 500), 1)

	# 35 물의 보호막 — 사망 시 아군 물속성에게 '3회 피해 1' 을 심는다.
	var p35 := _party([[35, "aqua"], [0, "aqua"], [0, "fire"]])
	AwakenSkill.apply_battle(p35, [], _table, {})
	p35[0]["alive"] = false
	B._aw_on_death(p35[0])
	f += _eq("35 물속성 아군에 보호막", B._aw_fix_damage(p35[1], 500), 1)
	f += _eq("35 다른 속성엔 미적용", B._aw_fix_damage(p35[2], 500), 500)

	# 41 봉인의 힘 — 스킬 시전 시 상대에게 셋 중 하나가 걸린다.
	var p41 := _party([[41, "dark"]])
	var e41 := _enemy("light")
	AwakenSkill.apply_battle(p41, [e41], _table, {})
	e41["awaken_gauge"] = 50.0
	rng.seed = 7
	B._aw_on_skill_cast(p41[0], [e41], rng)
	var changed := B._eff(e41, "def") < 100 or B._eff(e41, "att") < 100 			or float(e41["awaken_gauge"]) < 50.0
	f += _true("41 상대에게 무작위 디버프", changed)

	# 46 블랙홀의 마력 — 체력 50% 이하일 때만 흡혈 + 공격력 누적, 5회.
	var p46 := _party([[46, "dark"]])
	var e46 := _enemy("light")
	AwakenSkill.apply_battle(p46, [e46], _table, {})
	p46[0]["hp"] = 900                                   # 90% — 조건 미충족
	B._aw_on_attack_done(p46[0], e46, rng, 100)
	f += _eq("46 체력이 넉넉하면 회복 없음", int(p46[0]["hp"]), 900)
	p46[0]["hp"] = 400                                   # 40%
	B._aw_on_attack_done(p46[0], e46, rng, 100)
	f += _eq("46 준 피해의 50% 회복", int(p46[0]["hp"]), 450)
	f += _eq("46 공격력 +10%", B._eff(p46[0], "att"), 110)

	# 52 뼈갑옷 — 정액 40 감소(바닥 30) + 피격마다 다음 피해 +10%, 공격 시 초기화.
	var p52 := _party([[52, "earth"]])
	AwakenSkill.apply_battle(p52, [], _table, {})
	f += _eq("52 정액 40 감소", int(B._apply_dmg(p52[0], 500)["dmg"]), 460)
	f += _eq("52 바닥 30 아래로는 안 깎인다", int(B._apply_dmg(p52[0], 50)["dmg"]), 30)
	B._aw_on_hit_taken(p52[0], _enemy("fire"), 10, rng)
	f += _true("52 피격 후 받는 피해 증가", B._dmg_taken_mult(p52[0]) > 1.0)
	B._aw_on_attack_done(p52[0], _enemy("fire"), rng, 10)
	f += _eq("52 공격하면 초기화", B._dmg_taken_mult(p52[0]), 1.0)

	# 60 선제 공격 — 한쪽만 가지면 그 진영이 선공, 양쪽 다 가지면 무효.
	var a60 := _party([[60, "wind"]])
	var b60 := [_enemy("fire")]
	AwakenSkill.apply_battle(a60, b60, _table, {})
	f += _eq("60 한쪽만이면 아군 선공", B._consume_initiative(a60, b60), "ally")
	AwakenSkill.apply_battle(b60, a60, _table, {})        # 상대도 갖게 한다
	b60[0]["awaken_no"] = 60
	AwakenSkill.apply_battle(b60, a60, _table, {})
	f += _eq("60 양쪽 다면 무효", B._consume_initiative(a60, b60), "")

	# 65 신성 방패 — 막기마다 방어력 5% 누적 → 공격 시 회복.
	var p65 := _party([[65, "holy"]])
	AwakenSkill.apply_battle(p65, [], _table, {})
	p65[0]["hp"] = 500
	for i in 3:
		B._aw_on_block(p65[0], rng)
	B._aw_on_attack_bonus(p65[0], _enemy("dark"), rng, 0)
	f += _true("65 막기 누적분만큼 회복 (%d)" % int(p65[0]["hp"]), int(p65[0]["hp"]) > 500)

	# 69 암흑 마법 — 상대가 죽을수록 아군 증뎀 배율이 커진다(최대 3).
	var p69 := _party([[69, "dark"]])
	p69[0]["grade"] = 5.0
	var foes := [_enemy("light"), _enemy("light"), _enemy("light")]
	AwakenSkill.apply_battle(p69, foes, _table, {})
	B._aw_refresh_dynamic(p69, foes)
	var m1 := B._dmg_deal_mult(p69[0])
	foes[0]["alive"] = false
	foes[1]["alive"] = false
	B._aw_refresh_dynamic(p69, foes)
	f += _true("69 상대 사망마다 배율 증가 (%.2f → %.2f)" % [m1, B._dmg_deal_mult(p69[0])],
		B._dmg_deal_mult(p69[0]) > m1)

	# 75 얼어붙은 날개 — 준 피해의 1/3 누적 → 방어 시 방출.
	var p75 := _party([[75, "aqua"]])
	AwakenSkill.apply_battle(p75, [], _table, {})
	B._aw_on_attack_bonus(p75[0], _enemy("fire"), rng, 90)   # 30 누적
	f += _true("75 방어 시 누적분 감소", B._aw_fix_damage(p75[0], 500) < 500)

	# 78 용암의 노련함 — 스킬 공격이 막히지 않는다(다른 드래곤은 막힌다).
	var p78 := _party([[78, "fire"]])
	AwakenSkill.apply_battle(p78, [], _table, {})
	var wall := B.make_combatant("W", "enemy", "aqua",
		{"hp": 999999, "att": 1, "def": 1, "blk": 100})
	var blocked := 0
	var free := 0
	var plain: Dictionary = _party([[0, "fire"]])[0]
	for i in 40:
		rng.seed = 1000 + i
		if int(B._deal_attack(plain, wall, 1000, true, rng, _combat, {})["damage"]) < 1000:
			blocked += 1
		rng.seed = 1000 + i
		if int(B._deal_attack(p78[0], wall, 1000, true, rng, _combat, {})["damage"]) < 1000:
			free += 1
	f += _true("78 보통은 스킬도 막힌다 (%d/40)" % blocked, blocked > 0)
	f += _eq("78 용암의 노련함은 안 막힌다", free, 0)

	# 79 우아한 날개짓 — 모든 공격이 연속공격 + 바람 아군 증뎀.
	var p79 := _party([[79, "wind"]])
	var w79: Dictionary = _party([[0, "wind"]])[0]
	p79.append(w79)
	AwakenSkill.apply_battle(p79, [], _table, {})
	f += _true("79 always_double 플래그", B._has_flag(p79[0], "always_double"))
	f += _eq("79 바람 아군 증뎀 10%", B._dmg_deal_mult(w79), 1.1)

	# 91 타락한 드래곤 — 기본 체력 15% 증가.
	var p91 := _party([[91, "dark"]])
	AwakenSkill.apply_battle(p91, [], _table, {})
	f += _eq("91 체력 +15%", int(p91[0]["hp_max"]), 1150)

	# 93 태양의 불꽃 — 크리일 때 회피·방어율을 절반으로 본다.
	var p93 := _party([[93, "fire"]])
	AwakenSkill.apply_battle(p93, [], _table, {})
	p93[0]["cri"] = 100
	var guard := B.make_combatant("G", "enemy", "aqua",
		{"hp": 999999, "att": 1, "def": 1, "evd": 60, "blk": 60})
	var plain2: Dictionary = _party([[0, "fire"]])[0]
	plain2["cri"] = 100
	var miss_plain := 0
	var miss_sun := 0
	for i in 60:
		rng.seed = 2000 + i
		if bool(B.resolve_attack(plain2, guard, rng, _combat, {}).get("miss", false)):
			miss_plain += 1
		rng.seed = 2000 + i
		if bool(B.resolve_attack(p93[0], guard, rng, _combat, {}).get("miss", false)):
			miss_sun += 1
	f += _true("93 크리 시 회피가 줄어든다 (%d → %d)" % [miss_plain, miss_sun],
		miss_sun < miss_plain)
	return f


func _party(spec: Array) -> Array:
	var out: Array = []
	for i in spec.size():
		var e: Array = spec[i]
		out.append(B.make_combatant("A%d" % i, "ally", String(e[1]), {
			"hp": 1000, "att": 100, "def": 100, "cri": 10, "evd": 10, "blk": 10,
			"awaken_no": int(e[0]),
		}))
	return out

func _enemy(el: String) -> Dictionary:
	return B.make_combatant("E0", "enemy", el, {"hp": 1000, "att": 100, "def": 100})

func _json(path: String):
	return JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())

func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	printerr("  FAIL %s: got=%s want=%s" % [label, str(got), str(want)])
	return 1

func _true(label: String, cond: bool) -> int:
	if cond:
		return 0
	printerr("  FAIL %s" % label)
	return 1
