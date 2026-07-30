class_name Growth
## logic 층: 드래곤 성장/스탯 규칙. (CLAUDE.md §10)
## 순수 정적 함수 — Node·render·에셋·autoload에 의존하지 않는다(헤드리스 테스트 가능).
## 필요한 정의 데이터(드래곤 정의·스탯 기준선표)는 인자로 받는다(data 층=Data가 제공).
## 개체 런타임값(stat_bonus)도 인자로 받는다(세이브=UserDB가 제공).
## 결과값만 반환하고 연출(애니/사운드)은 하지 않는다.

const BASE_GRADE := 7.0                          # 기준선표 = grade 7.0 (§K-10)
## 성장 단계 경계 — **원작 실측값**. 예전엔 완전체를 20으로 잡았으나(근거 없는 값) 원작은 25다.
## 근거(서로 독립된 두 경로가 같은 임계값을 쓴다):
##   · `Dragon::getImagePathSpineJson` (Dragon.c:9285/9298) — `level < 10` baby / `< 0x19(25)` child / else adult
##   · 초상 경로 `box_baby|box_child|box_adult` (Dragon.c:8235/8248/8264) — 같은 10 / 0x19 분기
## (두 경로 모두 그 위에 `< 0x2d(45)` 로 성체↔각성체 스파인을 한 번 더 가른다 = level_cap 45/50과 일치)
const STAGE_BREAKS := {"baby": 9, "child": 24}   # <=9 baby, <=24 child, else adult

## **오라성체** 임계 레벨 = 45(= 일반 만렙). 사용자 확정(2026-07-30) + 클라 근거 일치:
##   · `Dragon.c:8265` 초상 경로가 성체 위에 `level < 0x2d(45)` 분기를 한 번 더 둔다
##     (45 미만 = `box_adult` / 45+ 는 플래그에 따라 갈린다) — `getImagePathSpineJson` 도 같다.
##   · `data/items.json` 의 회복물약 3단 `use`(사용자 기입)가 레벨대를 직접 적는다:
##     1단 Lv.1~24(해치~해츨링) · 2단 Lv.25~44(**성체**) · 3단 Lv.45~50(**오라 성체**).
## ⚠️ 오라성체는 **아트가 바뀌는 단계가 아니다** — 스파인은 성체 그대로이고 **오라 이펙트가 붙는
##   것**이 차이다(사용자 확정). 그래서 `stage_for_level`(에셋 단계 키)은 adult 를 계속 돌려준다.
const AURA_ADULT_LEVEL := 45

## 오라성체인가 — 오라 발광 이펙트를 그릴 조건이고, 도감 단계 5(오라성체)의 기록 조건이다.
static func is_aura_adult(level: int) -> bool:
	return level >= AURA_ADULT_LEVEL

## 레벨 상한: 일반 45, 각성 시 50 (§B).
static func level_cap(awakened := false) -> int:
	return 50 if awakened else 45

## 레벨 → 성장 단계(에셋 단계 키와 동일: baby/child/adult).
static func stage_for_level(level: int) -> String:
	if level <= STAGE_BREAKS["baby"]:
		return "baby"
	if level <= STAGE_BREAKS["child"]:
		return "child"
	return "adult"

## (전투유형 × 티어) 기준선 base/growth 행을 표에서 룩업. 없으면 {}.
static func _tier_row(dragon_def: Dictionary, stat_table: Dictionary) -> Dictionary:
	var typ = dragon_def.get("type")
	var tier = dragon_def.get("stat_tier")
	var row = stat_table.get(typ, {}).get(tier)
	return row if row != null else {}

## 티어 최대 상승량(레벨당 각 스탯 max) = 표의 growth 행. 롤 엔진(LevelSystem.roll_level) 입력. 없으면 0.
static func tier_growth(dragon_def: Dictionary, stat_table: Dictionary) -> Dictionary:
	var row := _tier_row(dragon_def, stat_table)
	if row.is_empty():
		return {"hp": 0, "att": 0, "def": 0}
	var g: Dictionary = row["growth"]
	return {"hp": int(g["hp"]), "att": int(g["att"]), "def": int(g["def"])}

## 티어 base(레벨1 기준 스탯) = 표의 base 행. 없으면 0.
static func tier_base(dragon_def: Dictionary, stat_table: Dictionary) -> Dictionary:
	var row := _tier_row(dragon_def, stat_table)
	if row.is_empty():
		return {"hp": 0, "att": 0, "def": 0}
	var b: Dictionary = row["base"]
	return {"hp": int(b["hp"]), "att": int(b["att"]), "def": int(b["def"])}

## 개체 실효 주스탯(랜덤롤 모델, §K-1 정정) = base(티어) + 영구base보정 + Σ(레벨업 롤 gain_log).
## gain_log = [{hp,att,def} …] 레벨업마다 누적된 실상승량(UserDB 저장, 불변식 level==1+size).
## base_bonus = 영구 base 보정(축복받은 둥지 등, stat_bonus.base). cri/evd/blk=10 고정(§K-1).
## 결정론적 compute_stats(아래)를 대체하는 실 스탯 산출. 레벨을 인자로 받지 않음(gain_log 크기가 곧 레벨-1).
static func main_stats(dragon_def: Dictionary, stat_table: Dictionary, gain_log: Array,
		base_bonus: Dictionary = {}) -> Dictionary:
	var row := _tier_row(dragon_def, stat_table)
	if row.is_empty():
		return {"hp": 0, "att": 0, "def": 0, "cri": 10, "evd": 10, "blk": 10}
	var out := {"cri": 10, "evd": 10, "blk": 10}
	for k in ["hp", "att", "def"]:
		var g := 0
		for e in gain_log:
			g += int((e as Dictionary).get(k, 0))
		out[k] = int(row["base"][k]) + int(base_bonus.get(k, 0)) + g
	return out

## 개체 실효 base/growth = 기준선 + 개체 편차(stat_bonus). 둘 다 {hp,att,def}.
## stat_bonus = {"base": {hp,att,def}, "growth": {hp,att,def}} (없는 키는 0 취급).
static func _effective(row: Dictionary, stat_bonus: Dictionary) -> Dictionary:
	var bb: Dictionary = stat_bonus.get("base", {})
	var gb: Dictionary = stat_bonus.get("growth", {})
	var base := {}
	var growth := {}
	for k in ["hp", "att", "def"]:
		base[k] = float(row["base"][k]) + float(bb.get(k, 0))
		growth[k] = float(row["growth"][k]) + float(gb.get(k, 0))
	return {"base": base, "growth": growth}

## 최종 스탯 = base + growth*(L-1). cri/evd/blk 고정 10 (§K-1).
## stat_bonus(개체 편차) 생략 시 grade 7.0 기준선으로 동작(하위호환).
static func compute_stats(dragon_def: Dictionary, stat_table: Dictionary, level: int,
		stat_bonus: Dictionary = {}) -> Dictionary:
	var row := _tier_row(dragon_def, stat_table)
	if row.is_empty():
		return {"hp": 0, "att": 0, "def": 0, "cri": 10, "evd": 10, "blk": 10}
	var eff := _effective(row, stat_bonus)
	var lv := maxi(1, level) - 1
	var out := {"cri": 10, "evd": 10, "blk": 10}
	for k in ["hp", "att", "def"]:
		out[k] = int(eff["base"][k] + eff["growth"][k] * lv)
	return out

## 개체 등급(grade) = 7.0 + 0.1*[Δhp/4 + Δatt + Δdef] (§K-10).
## grade는 출력(스탯의 요약 점수)이지 입력이 아니다 — 세이브엔 편차(stat_bonus)+롤 이력(gain_log)만 둔다.
##
## Δ = ① 부화 개체편차(stat_bonus, 기준선 대비 차이) + ② 레벨업 롤 편차 Σ(gain − 기준선).
## 🔴 2026-07-27 수정: ②가 통째로 빠져 있어 **아모르의 축복(전 스탯 초월맥스)이 등급에 0 기여**했다.
##    (사용자 보고: hp +4/att +1/def +1 초과 = +0.3 이어야 하는데 훨씬 덜 올랐음)
##    초과분 4/1/1 → 0.1*(4/4 + 1 + 1) = 0.3 ✓
##
## 기준선(baseline)은 밸런스 노브다 — `data/level_curve.json` 의 `grade` 블록에서 온다.
##   "max"(기본, 사용자 확정 2026-07-27) : gain − max        → 미달도 감점
##   "excess_only"                      : max(0, gain − max) → 초과분만 가산
##   "avg"                              : gain − (1+max)/2   → 기댓값 대비
## ⚠️ 원작에선 등급이 서버 계산값이었다(BagPopup::leveldownserverResult 가 응답의 "grade" 를 읽는다)
##    → 공식 자체가 유실. 위 세 모드는 재구성이며 노브로 바꿀 수 있게 열어 둔다.
static func compute_grade(dragon_def: Dictionary, stat_table: Dictionary,
		stat_bonus: Dictionary = {}, gain_log: Array = [], grade_cfg: Dictionary = {}) -> float:
	var bb: Dictionary = stat_bonus.get("base", {})
	var gb: Dictionary = stat_bonus.get("growth", {})
	var d := {"hp": 0.0, "att": 0.0, "def": 0.0}
	for k in ["hp", "att", "def"]:
		d[k] = float(bb.get(k, 0)) + float(gb.get(k, 0))
	if not gain_log.is_empty():
		var mx := tier_growth(dragon_def, stat_table)
		var mode := String(grade_cfg.get("baseline", "max"))
		for e in gain_log:
			var ed: Dictionary = e
			for k in ["hp", "att", "def"]:
				var m := float(mx.get(k, 0))
				if m <= 0.0:
					continue          # 기준선 표에 없는 종 → 롤 편차 산정 불가(중립 처리)
				var g := float(ed.get(k, 0))
				match mode:
					"excess_only": d[k] = float(d[k]) + maxf(0.0, g - m)
					"avg": d[k] = float(d[k]) + (g - (1.0 + m) * 0.5)
					_: d[k] = float(d[k]) + (g - m)
	var div := float(grade_cfg.get("hp_divisor", 4))
	if is_zero_approx(div):
		div = 4.0
	return BASE_GRADE + 0.1 * (float(d["hp"]) / div + float(d["att"]) + float(d["def"]))

## 레벨업 1회 후 레벨(상한 적용). 결과만 반환 — 경험치/재화 소비는 호출측/별도 규칙(§E,§K).
static func next_level(level: int, awakened := false) -> int:
	return mini(level_cap(awakened), level + 1)
