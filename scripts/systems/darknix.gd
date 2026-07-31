# Darknix — 혼돈의 틈새 **보스 소환** 규칙 (순수 로직 계층 §8: render/에셋 의존 없음)
#
# ## 원작 구조 (docs/ref/porting/ChaosRiftDarknix.md)
# 혼돈의 틈새(필드 8)는 일반 탐험이 **아니다.** 원작
# `WorldMapPopupLayer::getIsExistSomething()`(:1866)이 입장 앞을 막고 서서,
#
#   · `getLimitTime_darknix() <= now`  (= 보스 미소환) → 소환 팝업만 띄우고 **입장 차단**
#       - 고대 포탈(아이템 no 0x196 = 406) 보유 → `onClickItemUse` → `delItem(406, 1)`
#       - 없으면 다이아 경로 `RequestSummonMonster`(`game_adventure/cash_darknix.hb`)
#   · `> now` (= 보스 상주) → 통과
#
# 소환된 보스는 `AccountManager::getDarkNixStatus()` 1/2/3 중 하나이고, 월드맵에
# `WorldMapYutakanLayer::showDarknix()`(:6263)가 그 status 에 맞는 스파인 변형을 띄운다.
# 처치는 **2단 대면**이다 — 1차 전투 승리 → 마무리 일격(`kill_darknix.hb`) → 그 승리에서만
# `setLimitTime_darknix(0)`(:61058) 로 월드맵에서 사라진다(일회성).
#
# ## 서버가 갖고 있던 것 (= 여기서 우리가 정한다)
# status 추첨 · 유지시간 · 다이아 가격. 전부 `data/stages.json` 8번 `summon` 블록에 있고
# 이 파일은 **그 값을 해석만** 한다(수치를 코드에 박지 않는다 — §2-6).
#
# ⚠️ 로직만: 노드/씬/스프라이트/사운드 참조 금지(§8.2 단방향 의존).
class_name Darknix
extends RefCounted

## 게이트 판정 결과 `action` 값.
const ENTER := "enter"           # 보스 상주 → 입장 허용
const USE_ITEM := "use_item"     # 고대 포탈 소모 팝업
const USE_CASH := "use_cash"     # 다이아 소모 팝업
const NO_CASH := "no_cash"       # 다이아 부족 → 캐시(환전) 안내

## 대면 단계(원작 `AdventureManager::getDarknixFace`).
const FACE_NONE := 0
const FACE_FIRST := 1            # 조우~1차 전투
const FACE_FINISH := 2           # 마무리 일격 대기~최종 판정

## 그 스테이지가 소환형인가. `summon` 블록이 있으면 그렇다.
static func is_summon_stage(stage: Dictionary) -> bool:
	var s = stage.get("summon", null)
	return typeof(s) == TYPE_DICTIONARY and not (s as Dictionary).is_empty()

## 지금 보스가 상주 중인가(원작 `getLimitTime_darknix() > getTime()`).
static func is_active(state: Dictionary, now: int) -> bool:
	return int(state.get("until", 0)) > now

## 남은 상주 시간(초). 만료·미소환이면 0.
static func remain(state: Dictionary, now: int) -> int:
	return maxi(0, int(state.get("until", 0)) - now)

## 입장 게이트 — 원작 `getIsExistSomething()` 의 분기를 그대로 옮긴 것.
## 반환 `{action, item, item_count, cash}`. render 는 action 만 보고 팝업을 고른다.
##
## ⚠️ 원작과 같이 **소환과 입장은 별개 클릭**이다. 소환에 성공해도 그 클릭으로는 들어가지
##    않는다(원작 return false). 다시 눌러야 입장한다.
static func gate(cfg: Dictionary, state: Dictionary, now: int,
		item_count: int, cash: int) -> Dictionary:
	if is_active(state, now):
		return {"action": ENTER}
	var item := String(cfg.get("item", ""))
	var need := maxi(1, int(cfg.get("item_count", 1)))
	if item != "" and item_count >= need:
		return {"action": USE_ITEM, "item": item, "item_count": need}
	var price := int(cfg.get("cash", 0))
	# 원작은 `getCash() >= 1` 만 확인하고 실제 차감은 서버가 했다(가격은 유실).
	# 우리는 가격을 알고 있으므로 그 값으로 검사한다.
	if price > 0 and cash >= price:
		return {"action": USE_CASH, "cash": price}
	return {"action": NO_CASH, "cash": price}

## 소환 추첨 — `summon.variants` 의 `weight` 로 status 1/2/3 중 하나.
## 반환 `{status, enemy, until}`. `enemy` = `stage.enemies` 인덱스(= 어느 보스인가).
static func roll(cfg: Dictionary, now: int, rng: RandomNumberGenerator) -> Dictionary:
	var vs: Array = cfg.get("variants", [])
	if vs.is_empty():
		return {}
	var total := 0.0
	for v in vs:
		total += maxf(0.0, float((v as Dictionary).get("weight", 1)))
	var pick: Dictionary = vs[0]
	if total > 0.0:
		var r := rng.randf() * total
		for v in vs:
			r -= maxf(0.0, float((v as Dictionary).get("weight", 1)))
			if r <= 0.0:
				pick = v
				break
	return {
		"status": int(pick.get("status", 1)),
		"enemy": int(pick.get("enemy", 0)),
		"until": now + maxi(1, int(cfg.get("duration", 3600))),
		"face": FACE_NONE,
	}

## status → 그 변형 정의(`{status, enemy, weight, anim}`). 없으면 빈 사전.
static func variant_of(cfg: Dictionary, status: int) -> Dictionary:
	for v in (cfg.get("variants", []) as Array):
		if int((v as Dictionary).get("status", 0)) == status:
			return v
	return {}

## status → 애니 이름. slot 0=appear 1=breath 2=touch (원작 showDarknix 의 3종).
static func anim_of(cfg: Dictionary, status: int, slot: int) -> String:
	var a: Array = variant_of(cfg, status).get("anim", [])
	return String(a[slot]) if slot >= 0 and slot < a.size() else ""

## 상주 중인 보스의 `enemies` 인덱스. 미소환이면 -1.
static func enemy_index(cfg: Dictionary, state: Dictionary, now: int) -> int:
	if not is_active(state, now):
		return -1
	return int(variant_of(cfg, int(state.get("status", 0))).get("enemy", -1))

## 2단 대면인가(원작 face 1→2). 데이터에서 끌 수 있게 해 둔다.
static func is_two_phase(cfg: Dictionary) -> bool:
	return bool(cfg.get("two_phase", false))

## 1차 전투 승리 후의 다음 단계. 2단이면 마무리 일격 대기, 아니면 곧바로 처치.
static func next_face(cfg: Dictionary, face: int) -> int:
	if not is_two_phase(cfg):
		return FACE_FINISH
	return FACE_FINISH if face == FACE_FIRST else FACE_FIRST
