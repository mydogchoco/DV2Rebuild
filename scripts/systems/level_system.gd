class_name LevelSystem
## logic 층: 경험치 누적 → 레벨업 판정. (CLAUDE.md §10)
## 순수 정적 함수 — Node·render·에셋·autoload에 의존하지 않는다(헤드리스 테스트 가능).
## 원작 구조 대응: 원작은 서버가 exp 곡선/레벨업/스탯을 계산해 JSON(change1/2/3)으로 내려줬고
##   클라 AdventureMethod::CheckLevelUp은 그걸 "적용"만 했다(docs/ref/design/reverse_engineering.md §Tier2).
##   서버 소실 → 이 클래스가 그 계산을 대신한다. 결과값(이벤트)만 반환하고 연출은 render가 한다.
##
## 필요한 정의 데이터(exp 곡선·스탯 기준선표·드래곤 정의)는 인자로 받는다(data 층=Data가 제공).
## 개체 런타임값(level/exp/stat_bonus/awakened)도 인자로 받는다(세이브=UserDB가 제공).

## curve = data/level_curve.json = {cap, cap_awakened, req:[req_1, ...]} (req[L-1] = L→L+1 필요 exp).
## req(L): 레벨 L → L+1 필요 경험치. 곡선 밖이면 0(=더 못 오름).
static func exp_to_next(curve: Dictionary, level: int) -> int:
	var req: Array = curve.get("req", [])
	if level < 1 or level > req.size():
		return 0
	return int(req[level - 1])

static func cap_for(curve: Dictionary, awakened: bool) -> int:
	if awakened:
		return int(curve.get("cap_awakened", 50))
	return int(curve.get("cap", 45))

# ======================================================================
# 레벨업 스탯 롤 엔진 (레퍼런스: docs/ref/orig_image/levelup, 사용자 명세 2026-07-26)
# 매 레벨 각 스탯이 [1, max] 랜덤 상승. 낮은 확률로 초월맥스(max+가산, 보라). 트리플맥스=3스탯 전부 max.
# 리롤("능력치 다시뽑기")은 트리플맥스 확률을 리롤마다 누적(천장까지). 확률=ASSUMPTION(서버소실, data 노브).
# 순수 함수 — RNG를 주입받아 결정론적 테스트 가능(§5 시드 고정).
# ======================================================================
const STATS := ["hp", "att", "def"]

## 이번 롤의 강제 트리플맥스 확률 = base + step*리롤횟수 (천장 cap). 레퍼런스 "MAX 확률" 표기값.
static func pity_prob(roll_cfg: Dictionary, reroll_count: int) -> float:
	var base := float(roll_cfg.get("triple_max_base", 0.0))
	var step := float(roll_cfg.get("triple_max_step", 0.0))
	var cap := float(roll_cfg.get("triple_max_cap", 1.0))
	return minf(cap, base + step * maxi(0, reroll_count))

## 한 레벨의 스탯 롤. max_stats={hp,att,def}=stat_table growth(스탯별 최대 상승량). rng 주입.
## pity_p=이번 롤 강제 트리플맥스 확률(리롤 천장 반영). guarantee: ""|"max1"|"max2"|"triple"|"amor".
## 반환 {hp,att,def(실상승량), tmax:{hp,att,def=초월여부}, is_max:{...}, maxes:int, triple:bool}.
static func roll_level(roll_cfg: Dictionary, max_stats: Dictionary, rng: RandomNumberGenerator,
		pity_p := 0.0, guarantee := "") -> Dictionary:
	var extra: Dictionary = roll_cfg.get("transcend", {"hp": 4, "att": 1, "def": 1})
	var tc := float(roll_cfg.get("transcend_chance", 0.0))
	var force_triple := guarantee == "triple" or guarantee == "amor" or rng.randf() < pity_p
	var gain := {}
	var tmax := {}
	var is_max := {}
	for s in STATS:
		var mx := int(max_stats.get(s, 1))
		if mx < 1:
			mx = 1
		var trans := guarantee == "amor" or rng.randf() < tc
		var maxed := force_triple
		var r := mx
		if not force_triple:
			r = rng.randi_range(1, mx)
			maxed = r == mx
		if trans:
			gain[s] = mx + int(extra.get(s, 0)); maxed = true
		elif maxed:
			gain[s] = mx
		else:
			gain[s] = r
		tmax[s] = trans
		is_max[s] = maxed
	# 축복 보장(max1/max2): 자연 롤이 부족하면 비-맥스 스탯을 max로 승격(초월 아님).
	var need := 1 if guarantee == "max1" else (2 if guarantee == "max2" else 0)
	if need > 0:
		var cnt := 0
		for s in STATS:
			if is_max[s]:
				cnt += 1
		for s in STATS:
			if cnt >= need:
				break
			if not is_max[s]:
				gain[s] = int(max_stats.get(s, 1)); is_max[s] = true; cnt += 1
	var maxes := 0
	for s in STATS:
		if is_max[s]:
			maxes += 1
	return {"hp": int(gain["hp"]), "att": int(gain["att"]), "def": int(gain["def"]),
		"tmax": tmax, "is_max": is_max, "maxes": maxes, "triple": maxes == 3}

## 경험치 gained 를 더해 레벨업(랜덤 롤)을 처리하고 "결과 이벤트"를 돌려준다. 상태 저장 안 함(호출측 몫).
## 전투 자동 레벨업 = 리롤/보장 없음(pity 0, guarantee ""). rng 주입(§5 시드 고정 가능).
## max_stats = 티어 최대 상승량(Growth.tier_growth). roll_cfg = curve["roll"].
##
## 반환:
##   level        : 처리 후 레벨
##   exp/exp_now/exp_max : 게이지(잔여 exp / 현재레벨 필요 exp; 만렙 0/0)
##   levels_gained, capped
##   gains        : [roll_level 결과 …] 레벨업마다의 롤(hp/att/def/tmax/maxes/triple). 호출측이 gain_log에 누적 + 연출.
static func apply_exp(curve: Dictionary, roll_cfg: Dictionary, max_stats: Dictionary,
		level: int, exp: int, gained: int, rng: RandomNumberGenerator, awakened := false) -> Dictionary:
	var cap := cap_for(curve, awakened)
	level = clampi(level, 1, cap)
	exp = maxi(0, exp) + maxi(0, gained)
	var gains: Array = []

	while level < cap:
		var need := exp_to_next(curve, level)
		if need <= 0:
			break                       # 곡선 데이터 없음 → 더 못 오름(방어)
		if exp < need:
			break
		exp -= need
		level += 1
		gains.append(roll_level(roll_cfg, max_stats, rng, 0.0, ""))

	var capped := level >= cap
	var exp_max := 0 if capped else exp_to_next(curve, level)
	if capped:
		exp = 0                         # 만렙: 다음 레벨 없음 → 잉여 폐기
	return {
		"level": level,
		"exp": exp,
		"exp_now": exp,
		"exp_max": exp_max,
		"levels_gained": gains.size(),
		"capped": capped,
		"gained": maxi(0, gained),
		"gains": gains,
	}
