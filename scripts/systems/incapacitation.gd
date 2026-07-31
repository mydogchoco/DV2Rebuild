class_name Incapacitation
extends RefCounted

## 드래곤 **행동불능**(원작 `Dragon::isStun` / `getCureTime` / `setCureTime`) — 순수 로직.
##
## 전투 중 스킬로 걸리는 '기절'(`AdventureSkillStop` "…행동불능 상태에 빠져 움직이지 못했다")과
## **다른 것**이다. 이쪽은 **던전에서 패배하고 나오면** 그 던전에 들어갔던 드래곤이 걸리는
## 지속 상태로, 회복 전까지 전투에 못 나간다.
##
## ## 근거
##
## · 원작 코드: `Dragon::isStun()` = `GameManager::getTime() < this->cureTime`
##     (docs/ref/orig_code/decomp/Dragon.c:11359) — **유닉스 시각 한 개**로 표현된다.
##     `setCureTime(0)` = 즉시 해제(CaveScene.c:8309·15889, CardMiniGameLayer.c:1248).
## · 다이아 즉시 회복 = **원작 공식 확정**. `CaveScene.c:8307`:
##     `if ((cureTime - now) / 0x708 < User::getCash())` → `setCureTime(0)`.
##     0x708 = 1800초 ⇒ **남은 30분당 다이아 1개, 최소 1개**(`instant_cost` 의 `+1` 근거 참조).
##     문자열 `Tip_35` "드래곤이 행동불능이 될 경우 다이아를 사용해 바로 회복시킬 수 있습니다."
## · 즉시 회복 **팝업**(월드맵 던전 입장 시) = `WorldMapScene::setDragonStun` →
##     `<CaveDiaBronMsg2>` "회복까지 %s남았습니다.\n드래곤을 즉시 부활시키겠습니까?" +
##     `setCash(0, …)`. 확인 = `onClickStun`(= `setCureTime(0)`), 취소 = `onClickCancel`.
## · 회복 대기시간 1시간 · 치료제 아이템 · 패배 시 발생 = **사용자 확정**(2026-07-29,
##     docs/input/sheets/open_questions.csv). 원작 값은 서버 소유라 유실됐다.
## · 부적(`cure`)의 재해석도 같은 줄에서 사용자가 확정했다 —
##     "부적 아이템은 패배했을때 행동불능 상태가 되지 않을 확률을 부여하는 것".
##     (원작 툴팁 `CaveItemEquipComent3` "행동불능 치유 확률 +%d%%" 은 이 확률을 가리킨다.)
##
## 표 = `data/incapacitation.json`. 화면·에셋을 모른다(§8.1 logic 층).

## 지금 행동불능인가. cure_time = 드래곤 레코드의 유닉스 시각(0 = 정상).
static func is_down(cure_time: int, now: int) -> bool:
	return cure_time > now

## 남은 회복 시간(초). 정상이면 0.
static func remain(cure_time: int, now: int) -> int:
	return maxi(0, cure_time - now)

## 패배 시 행동불능을 **피했는가**. cure_pct = 그 드래곤의 합계 `cure`(부적 등 장비 효과).
## 100 이상이면 항상 피한다.
static func avoids(cure_pct: int, rng: RandomNumberGenerator) -> bool:
	if cure_pct <= 0:
		return false
	return rng.randi_range(1, 100) <= cure_pct

## 패배로 걸리는 행동불능의 해제 시각.
static func down_until(cfg: Dictionary, now: int) -> int:
	return now + int(cfg.get("recover_seconds", 3600))

## 즉시 회복 다이아 비용 — 원작 `floor((cureTime - now) / 1800) + 1`. 남은 시간이 없으면 0.
##
## ⚠️ 2026-07-30 정정: 종전엔 `+1` 이 없어 30분 미만이면 **0다이아(공짜)** 였다.
## 🟢 2026-08-01 재확인 — `0x708` 을 전 디컴프에서 전수 조회해 **표시식과 검사식을 둘 다
## 리터럴로** 잡았다(종전 주석은 매직 곱셈 추정에 기대고 있었다):
##   · 표시 비용 `PopupTypeLayer::setCash(this, 0, (int)remain / 0x708 + 1, false)`
##       — `CaveScene.c:8218` · 같은 식이 `AdventureScene.c:76839` 에도 있다
##   · 지불 가능 검사 `(int)(cureTime - now) / 0x708 < User::getCash()`
##       — `CaveScene.c:8307` · `WorldMapScene.c:558`
## `floor(r/1800) < cash` ⟺ `floor(r/1800) + 1 <= cash` 이므로 **두 식이 같은 값**을 가리킨다.
## 즉 **최소 1다이아**이고 30분마다 1씩 는다(1시간 남았으면 3).
## 회귀 방지 = `test_kades_incap.gd` "원작 지불검사와 동일"(경계 7개 대조).
static func instant_cost(cfg: Dictionary, cure_time: int, now: int) -> int:
	var sec := int(cfg.get("instant_cure_seconds_per_dia", 1800))
	var left := remain(cure_time, now)
	if sec <= 0 or left <= 0:
		return 0
	return left / sec + 1

## 원작 팝업이 쓰는 남은 시간 표기 — `WorldMapScene::setDragonStun` 의
## `CCString::createWithFormat("%02d:%02d", …)`(1시간 미만) / `"%02d:%02d:%02d"`(이상).
static func remain_clock(cure_time: int, now: int) -> String:
	var s := remain(cure_time, now)
	if s <= 0:
		return ""
	if s < 3600:
		return "%02d:%02d" % [s / 60, s % 60]
	return "%02d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]

## 이 아이템으로 행동불능을 풀 수 있는가.
static func is_cure_item(cfg: Dictionary, key: String) -> bool:
	return key in (cfg.get("cure_items", []) as Array)

## 사람이 읽는 남은 시간 — "42분" / "1시간 3분".
static func remain_text(cure_time: int, now: int) -> String:
	var s := remain(cure_time, now)
	if s <= 0:
		return ""
	var h := s / 3600
	var m := (s % 3600) / 60
	if h > 0:
		return "%d시간 %d분" % [h, m]
	return "%d분" % maxi(1, m)
