class_name Kades
extends RefCounted

## 카데스의 공간(유타칸 전설 모드) 규칙 — 순수 로직(§8.1 logic 층).
##
## 원작에서 카데스는 **새 지역이 아니라 유타칸 전 지역이 전설 난이도로 바뀌는 모드**다.
## 진입은 필드 id 를 600 번대로 바꾸는 것으로 표현된다(`DungeonBG.variant_field`,
## 원작 `WorldMapPopupLayer::init`). 이 클래스는 그 모드에서만 걸리는 규칙을 계산한다.
##
## 규칙 표 = `data/kades.json`(위키 dungeon_1.pdf §2 확정 + BGM 은 원작 디컴프 확정).
## 화면·에셋을 일절 모른다.

## 미각성 드래곤이 카데스에서 받는 능력치 감소율(%). 각성했으면 0.
##
## 위키 dungeon_1.pdf §2: "드래곤들이 각성을 하지 않은 상태에서 카데스의 공간에 진입할 경우
##   혼돈, 신성 속성은 35%, 탐험하고자 하는 던전의 속성이 드래곤의 속성과 같은 경우 25%,
##   그 이외의 드래곤은 50% 나 능력치가 깎여 나간다."
##
##   dragon_element = 드래곤 속성(dragons.json element)
##   field_element  = 그 던전의 속성(stages.json field_element, 없으면 몬스터 최빈 속성)
static func penalty_pct(cfg: Dictionary, awakened: bool, dragon_element: String,
		field_element: String) -> int:
	if awakened:
		return 0
	var p: Dictionary = cfg.get("unawakened_penalty_pct", {})
	if p.is_empty():
		return 0
	# 우선순위는 위키 서술 순서 그대로 — 혼돈/신성이 먼저다(속성이 같아도 35%).
	if p.has(dragon_element):
		return int(p[dragon_element])
	if dragon_element != "" and dragon_element == field_element:
		return int(p.get("same_element", 0))
	return int(p.get("other", 0))

## 감소율을 스탯 딕셔너리에 적용한 새 딕셔너리. hp/att/def 만 줄인다.
## (위키는 "능력치"라고만 적는다 — 크리/회피 같은 확률까지 깎으면 % 를 두 번 해석하게 된다.
##  적용 대상을 hp/att/def 로 한정한 것은 우리 해석이다 — data/kades.json `_penalty_note`.)
const PENALIZED := ["hp", "att", "def"]

static func apply_penalty(stats: Dictionary, pct: int) -> Dictionary:
	if pct <= 0:
		return stats
	var out := stats.duplicate()
	var mult := float(100 - clampi(pct, 0, 99)) / 100.0
	for k in PENALIZED:
		out[k] = maxi(1, int(round(float(int(out.get(k, 0))) * mult)))
	return out

## 카데스 보스 레벨 — 위키 확정 "120~200 사이로 랜덤". 표가 비면 0(=기존 레벨 유지).
static func boss_level(cfg: Dictionary, rng: RandomNumberGenerator) -> int:
	var b: Dictionary = cfg.get("boss_level", {})
	if b.is_empty():
		return 0
	return rng.randi_range(int(b.get("min", 0)), int(b.get("max", 0)))

## 카데스 보스 스탯 배수 — 낮 보스 스탯을 굴린 레벨까지 끌어올리는 비율.
##
## 원작 스탯표는 서버 유실이라 **낮 보스 12종의 레벨↔스탯 직선**(`boss_stat_curve`)을 그대로
## 연장해 쓴다: mult = f(lv) / f(lv0). 단순 레벨비(lv/lv0)를 쓰면 Lv.1 던전이 ×120~200,
## Lv.45 던전이 ×2.7~4.4 가 돼 던전 간 난이도가 뒤집힌다.
## stat 키는 "hp"/"att"/"def". 표에 없는 키는 1.0(변화 없음).
static func boss_stat_mult(cfg: Dictionary, stat: String, lv: int, lv0: int) -> float:
	var c: Array = cfg.get("boss_stat_curve", {}).get(stat, [])
	if c.size() < 2 or lv <= 0 or lv0 <= 0:
		return 1.0
	var a := float(c[0])
	var b := float(c[1])
	var base := a * float(lv0) + b
	if base <= 0.0:
		return 1.0
	return maxf(1.0, (a * float(lv) + b) / base)

## 카데스에서는 탐험 걸음마다 반드시 전투가 붙는다(위키 "탐험 시마다 몬스터를 만나서 전투").
static func always_battle(cfg: Dictionary) -> bool:
	return bool(cfg.get("always_battle", false))

## 카데스에서는 보물지도를 쓸 수 없다(위키 "지도 역시 사용 불가능하다").
static func map_disabled(cfg: Dictionary) -> bool:
	return bool(cfg.get("map_disabled", false))
