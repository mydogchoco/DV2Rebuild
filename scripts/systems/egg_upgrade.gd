# EggUpgrade(알 강화) — 순수 로직 계층 (§8: render/에셋 의존 없음, 헤드리스 검증 가능)
#
# 원작 근거(구조):
#   · 재료는 **3칸**이고 종류가 정해져 있다 — `LaboratoryEggLayer::setEgg` 가 빈 슬롯에 그리는 아이콘이
#     순서대로 `icon_element`(정령석) · `icon_stoneheart` · `icon_crystal`(결정)
#     (decomp/LaboratoryEggLayer.c:4767 / :4761 / :4754, 스크린샷 docs/ref/orig_image/lab/알강화.png).
#   · 레시피 조회 = `UpgradeEgg::create(Egg::getGroup(), Egg::getGrade()+1)` → SQL
#     `select upgrade_no, item1, item2, item3, cost from info_upgrade_egg where type='%s' and grade=%d`
#     (UpgradeEgg.c:401). item1..3 은 **(아이템번호, 개수) 쌍**이고 setEgg :4995-5000 이 갈라 읽는다.
#   · 판정 = `isPosibleUpgrade` :1120 — 슬롯 3칸 각각 "보유수 ≥ 요구수". 그 외 조건 없음.
#   · 재료 **행 값(번호·개수·골드)은 서버 소유라 유실** → data/upgrade_egg.json (자작, §HARD RULE 6 예외).
#
# 효과(위키 labwiki.pdf §2.1, 사용자 확정 2026-07-30):
#   1강 = 부화 등급 7.0 확정 · 2강 = 7.2 · 3강 = 7.5. (4강 8.0 은 이벤트 전용이라 강화 불가.)
#   즉 강화한 알은 둥지의 **랜덤 등급 굴림(3.0~7.0)을 대체**한다 → Hatchery.grade_for_step.
#
# ⚠️ 원작과 우리의 차이(문서화된 ASSUMPTION):
#   원작의 알은 서버 객체(`Egg`)라 **개체마다** grade 를 들고 다녔다. 우리 알은 인벤토리의 스택
#   아이템이라 개체가 없다 → 세이브에 "알키 → {등급: 개수}" 곁 테이블을 둔다(UserDB.egg_grade_counts).
#   0강 개수 = 인벤 보유수 − 강화된 개수 합.
#
# ⚠️ 이 파일은 로직만: 노드/씬/스프라이트/사운드/UserDB 참조 금지(§8.2 단방향 의존).
class_name EggUpgrade
extends RefCounted

## data/upgrade_egg.json 의 와일드카드 행이 쓰는 결정 토큰. 가챠로 얻는 가상 알 키
## (`egg:<드래곤id>`, EggGacha)는 items.json 에 행이 없어 속성 결정을 런타임에 고른다.
const CRYSTAL_TOKEN := "@element_crystal"


## 강화 상한(단계). cfg = data/laboratory.json 의 `egg_upgrade` 블록.
static func max_step(cfg: Dictionary) -> int:
	return int(cfg.get("max_step", 3))


## step 강(1..max_step) 알의 **확정 부화 등급**. cfg.grades = {"1": 7.0, …}.
## 정의가 없으면 0.0 — 호출측이 "확정 등급 없음"으로 보고 기존 랜덤 굴림을 쓴다.
static func hatch_grade(step: int, cfg: Dictionary) -> float:
	var g: Dictionary = cfg.get("grades", {})
	return float(g.get(str(step), 0.0))


## (알 종류, 현재 등급) → 레시피. 재료의 `@element_crystal` 토큰은 그 알 속성의 결정으로 해석한다.
##   egg_key  : 인벤 키(`mall_back_egg` 또는 가상 `egg:<id>`)
##   element  : 그 알의 속성("fire"/"aqua"/…). 토큰 해석에만 쓴다
##   grade    : 현재 강화 등급(0=미강화)
##   up_data  : data/upgrade_egg.json 전체(recipes + _element_crystal)
##   lab_cfg  : data/laboratory.json 의 egg_upgrade 블록(상한 검사)
## 상한 초과·레시피 없음·결정 해석 실패면 {}.
static func recipe_for(egg_key: String, element: String, grade: int,
		up_data: Dictionary, lab_cfg: Dictionary = {}) -> Dictionary:
	if grade < 0 or grade >= max_step(lab_cfg):
		return {}
	var row := row_for(egg_key, grade, up_data)
	if row.is_empty():
		return {}
	var mats: Array = []
	for m in (row.get("materials", []) as Array):
		var md: Dictionary = m
		var key := String(md.get("item", ""))
		if key == CRYSTAL_TOKEN:
			key = element_crystal(element, up_data)
			if key == "":
				return {}        # 속성을 모르는 알 = 강화 대상 아님(의문의 알 등)
		mats.append({"item": key, "count": int(md.get("count", 1))})
	var out := row.duplicate()
	out["materials"] = mats
	out["target_grade"] = grade + 1
	return out


## 그 속성의 일반 결정 아이템 키(위키 "속성 결정"). 매핑은 데이터에 있다(코드에 박지 않는다).
static func element_crystal(element: String, up_data: Dictionary) -> String:
	var m: Dictionary = up_data.get("_element_crystal", {})
	return String(m.get(element, ""))


## 원작 where type='%s' and grade=%d — 정확 매칭 우선, 없으면 와일드카드 행(type='*').
static func row_for(egg_key: String, grade: int, up_data: Dictionary) -> Dictionary:
	var fallback: Dictionary = {}
	for r in (up_data.get("recipes", []) as Array):
		var d: Dictionary = r
		if int(d.get("grade", -1)) != grade:
			continue
		var t := String(d.get("type", ""))
		if t == egg_key:
			return d
		if t == "*":
			fallback = d
	return fallback


# ── 등급별 보유 개수(세이브 곁 테이블) ────────────────────────────────────────
## 세이브에 든 값을 {등급(int) → 개수(int)} 로 정규화. 0 이하 등급/개수는 버린다.
## 구형(v12 이하)은 `{알키: 등급(int)}` 이었다 → 그 등급 1개로 읽는다.
static func normalize(entry) -> Dictionary:
	var out: Dictionary = {}
	if entry is Dictionary:
		for k in (entry as Dictionary):
			var g := int(String(k)) if not (k is int or k is float) else int(k)
			var n := int((entry as Dictionary)[k])
			if g > 0 and n > 0:
				out[g] = int(out.get(g, 0)) + n
	elif entry is int or entry is float:
		var g2 := int(entry)
		if g2 > 0:
			out[g2] = 1
	return out


## 강화된 알 총 개수(등급 1 이상).
static func upgraded_total(counts: Dictionary) -> int:
	var n := 0
	for g in counts:
		n += int(counts[g])
	return n


## 그 등급의 보유 개수. 0강 = 인벤 보유수 − 강화된 개수 합(음수는 0으로 자른다).
static func owned_at(grade: int, inv_count: int, counts: Dictionary) -> int:
	if grade <= 0:
		return maxi(0, inv_count - upgraded_total(counts))
	return maxi(0, int(counts.get(grade, 0)))


## 보유한 등급 목록(0 포함, 개수>0 인 것만). 오름차순.
static func owned_grades(inv_count: int, counts: Dictionary) -> Array:
	var out: Array = []
	if owned_at(0, inv_count, counts) > 0:
		out.append(0)
	var gs: Array = counts.keys()
	gs.sort()
	for g in gs:
		if int(counts[g]) > 0:
			out.append(int(g))
	return out


## grade 알 1개를 grade+1 로 올린 새 counts. 저장 형식(문자열 키)으로 돌려준다.
static func after_upgrade(grade: int, counts: Dictionary) -> Dictionary:
	var d := counts.duplicate()
	if grade > 0:
		var left := int(d.get(grade, 0)) - 1
		if left > 0: d[grade] = left
		else: d.erase(grade)
	d[grade + 1] = int(d.get(grade + 1, 0)) + 1
	return to_save(d)


## grade 알 1개를 소비(부화)한 새 counts. 0강 소비는 곁 테이블을 건드리지 않는다.
static func after_consume(grade: int, counts: Dictionary) -> Dictionary:
	var d := counts.duplicate()
	if grade > 0:
		var left := int(d.get(grade, 0)) - 1
		if left > 0: d[grade] = left
		else: d.erase(grade)
	return to_save(d)


## {int → int} → 세이브용 {문자열 → int}. JSON 왕복에서 키 타입이 흔들리지 않게 한다.
static func to_save(counts: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for g in counts:
		var n := int(counts[g])
		if int(g) > 0 and n > 0:
			out[str(int(g))] = n
	return out
