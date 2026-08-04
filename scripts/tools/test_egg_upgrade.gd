extends Node
## 헤드리스 검증 — **연구소 알 강화**(원작 `LaboratoryEggLayer` mode 1 + `UpgradeEgg`)의 규칙 계약.
##
## 실행: project.godot `[autoload]` 에 `TestEggUpgrade="*res://scripts/tools/test_egg_upgrade.gd"`
##   를 임시로 한 줄 넣고 `godot --headless --path . --quit-after 5` → 검사 후 그 줄을 지운다.
##   (다른 테스트처럼 `--script` 로도 짜 봤지만 **이 환경에서 `--script` 모드가 멈춘다** — 8줄짜리
##    스크립트도 출력 없이 걸린다. 프로젝트 부팅 경로는 정상이라 오토로드 방식으로 돌린다.)
##
## JSON 을 직접 읽고 순수 로직(`EggUpgrade`)만 부른다 — UI 배치는 스크린샷으로 검수한다.
##
## 지키는 계약
##   ① 레시피가 **모든 알**에 해석된다 — 구체 알(mall_*)과 가챠 가상 알(`egg:<id>`) 둘 다
##      (막혀 있던 원인이 정확히 "가상 알에 레시피 없음"이었다)
##   ② 재료 3칸 = 정령석 · 스톤하트 · **그 알 속성의 결정**, 등급별 티어가 위키와 일치
##   ③ 등급 곁 테이블(개수 맵)의 강화/소비/구형 마이그레이션
##   ④ 확정 부화 등급(위키 1강 7.0 / 2강 7.2 / 3강 7.5)과 상한(3강)

const EU := preload("res://scripts/systems/egg_upgrade.gd")

func _ready() -> void:
	var fails := 0
	var items: Dictionary = _load("res://data/items.json")
	var up: Dictionary = _load("res://data/upgrade_egg.json")
	var lab: Dictionary = _load("res://data/laboratory.json")
	var ecfg: Dictionary = lab.get("egg_upgrade", {})

	# ── ① 모든 알 종류에 레시피가 해석된다 ──────────────────────────────
	var checked := 0
	for k in items:
		var it = items[k]
		if not (it is Dictionary) or String((it as Dictionary).get("category", "")) != "egg":
			continue
		# items.json 은 element 가 **명시적 null** 인 항목이 있다 → `String(null)` 은 4.7 에서
		# 런타임 에러("Invalid call 'String' constructor")다. 타입을 보고 읽는다.
		var ev = (it as Dictionary).get("element")
		var el: String = ev if typeof(ev) == TYPE_STRING else ""
		if el == "":
			continue          # 의문의 알 = 개봉 대상(강화 안 함)
		var r: Dictionary = EU.recipe_for(String(k), el, 0, up, ecfg)
		fails += _true("레시피 해석: %s" % k, not r.is_empty())
		fails += _eq("재료 3칸: %s" % k, (r.get("materials", []) as Array).size(), 3)
		checked += 1
	fails += _true("알 종류 20종 이상 검사", checked >= 20)

	# 가챠 가상 알(`egg:<드래곤id>`) — items.json 에 행이 없다 → 와일드카드 행이 받아야 한다
	var vr: Dictionary = EU.recipe_for("egg:37", "aqua", 0, up, ecfg)
	fails += _true("가상 알도 레시피가 있다", not vr.is_empty())
	fails += _eq("가상 알 결정 = 물의 결정", String((vr["materials"][2] as Dictionary)["item"]), "crystal_water")

	# ── ② 등급별 티어(위키 labwiki.pdf §2.1) + 결정 = 알 속성 ────────────
	var want := [["stone_spirit2", "stone_heart2"], ["stone_spirit3", "stone_heart3"],
		["stone_spirit4", "stone_heart4"]]
	for g in 3:
		var r2: Dictionary = EU.recipe_for("mall_back_egg", "light", g, up, ecfg)
		var mats: Array = r2.get("materials", [])
		fails += _eq("%d강 정령석" % (g + 1), String((mats[0] as Dictionary)["item"]), want[g][0])
		fails += _eq("%d강 스톤하트" % (g + 1), String((mats[1] as Dictionary)["item"]), want[g][1])
		fails += _eq("%d강 결정(빛)" % (g + 1), String((mats[2] as Dictionary)["item"]), "crystal_light")
		for m in mats:
			fails += _true("재료가 items.json 에 있다: %s" % (m as Dictionary)["item"],
				items.has(String((m as Dictionary)["item"])))
			fails += _eq("개수 10", int((m as Dictionary)["count"]), 10)

	# ── ③ 상한: 3강은 더 못 올린다 ───────────────────────────────────────
	fails += _eq("강화 상한", EU.max_step(ecfg), 3)
	fails += _true("3강은 레시피 없음", EU.recipe_for("mall_back_egg", "light", 3, up, ecfg).is_empty())

	# ── ④ 확정 부화 등급(위키) ───────────────────────────────────────────
	fails += _eq("1강 등급", EU.hatch_grade(1, ecfg), 7.0)
	fails += _eq("2강 등급", EU.hatch_grade(2, ecfg), 7.2)
	fails += _eq("3강 등급", EU.hatch_grade(3, ecfg), 7.5)
	fails += _eq("0강은 확정 등급 없음(랜덤 굴림)", EU.hatch_grade(0, ecfg), 0.0)

	# ── ⑤ 등급을 어디에 두는가 — v15 인벤 키 접미사 ──────────────────────
	# ⚠️ 2026-08-04 정정: 종전 이 절은 `EU.owned_at/owned_grades/after_upgrade/
	#    after_consume/to_save`(v14 곁 테이블 API)를 불렀는데, 그 5함수는 v15 재설계
	#    (커밋 6f2cb03, 2026-07-31)에서 **삭제됐다** — 테스트만 남아 파일 전체가
	#    파스 에러로 죽어 있었다. v15 는 등급을 인벤 키에 싣는다(`EggItem`).
	fails += _eq("0강은 접미사 없음", EggItem.key("egg:17", 0), "egg:17")
	fails += _eq("2강 키", EggItem.key("egg:17", 2), "egg:17#2")
	fails += _eq("키에서 등급 읽기", EggItem.grade_of("egg:17#2"), 2)
	fails += _eq("접미사 없으면 0강", EggItem.grade_of("egg:17"), 0)
	fails += _eq("키에서 알 종류 읽기", EggItem.base_of("egg:17#2"), "egg:17")
	fails += _true("강화된 알 판정", EggItem.is_upgraded("egg:17#2"))
	fails += _true("0강은 강화 아님", not EggItem.is_upgraded("egg:17"))
	fails += _true("같은 알의 변형", EggItem.is_variant_of("egg:17#2", "egg:17"))
	fails += _true("다른 알은 변형 아님", not EggItem.is_variant_of("egg:18#2", "egg:17"))

	# 구형 세이브(v14 이하 곁 테이블) 읽기 — 마이그레이션 전용으로 남은 `normalize`.
	fails += _eq("구형 값 = 2강 1개", str(EU.normalize(2)), str({2: 1}))
	fails += _eq("구형 테이블 정규화", str(EU.normalize({"2": 1})), str({2: 1}))

	# ── ⑥ 재료 수급: 환산 조합(위키 각주 12/6/3)이 데이터에 있다 ─────────
	var ci: Dictionary = _load("res://data/combine_item.json")
	var targets: Array = []
	for r3 in (ci.get("recipes", []) as Array):
		targets.append(String((r3 as Dictionary).get("target", "")))
	for t in ["stone_spirit2", "stone_spirit3", "stone_spirit4",
			"stone_heart2", "stone_heart3", "stone_heart4"]:
		fails += _true("환산 조합 있음: %s" % t, targets.has(t))

	print("[test_egg_upgrade] %s" % ("PASS" if fails == 0 else "FAIL(%d)" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("  ✗ 파일 없음: ", path)
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}


func _true(what: String, cond: bool) -> int:
	if cond:
		return 0
	print("  ✗ %s" % what)
	return 1


func _eq(what: String, got, want) -> int:
	if is_same(got, want) or str(got) == str(want):
		return 0
	print("  ✗ %s — got %s, want %s" % [what, str(got), str(want)])
	return 1
