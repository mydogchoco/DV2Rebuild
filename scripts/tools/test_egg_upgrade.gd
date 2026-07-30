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

	# ── ⑤ 등급 곁 테이블 — 강화·소비·0강 계산 ───────────────────────────
	# 알 3개 보유, 아직 강화 없음 → 0강 3개
	var c: Dictionary = EU.normalize({})
	fails += _eq("0강 개수 = 인벤 수", EU.owned_at(0, 3, c), 3)
	c = EU.normalize(EU.after_upgrade(0, c))                  # 1개를 1강으로
	fails += _eq("1강 1개", EU.owned_at(1, 3, c), 1)
	fails += _eq("0강 2개로 줄었다", EU.owned_at(0, 3, c), 2)
	c = EU.normalize(EU.after_upgrade(1, c))                  # 그 1개를 2강으로
	fails += _eq("2강 1개", EU.owned_at(2, 3, c), 1)
	fails += _eq("1강 0개", EU.owned_at(1, 3, c), 0)
	fails += _eq("보유 등급 목록", str(EU.owned_grades(3, c)), str([0, 2]))
	c = EU.normalize(EU.after_consume(2, c))                  # 2강 알 부화
	fails += _eq("소비 후 2강 0개", EU.owned_at(2, 2, c), 0)
	fails += _true("소비 후 테이블 비었다", c.is_empty())

	# 구형(v12 이하) `{알키: 등급}` → 그 등급 1개
	var old: Dictionary = EU.normalize(2)
	fails += _eq("구형 값 = 2강 1개", EU.owned_at(2, 1, old), 1)
	fails += _eq("저장 형식은 문자열 키", str(EU.to_save(old)), str({"2": 1}))

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
