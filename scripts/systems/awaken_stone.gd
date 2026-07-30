class_name AwakenStone
extends RefCounted
## 각성의 마석 제작 — 규칙만. logic 층(CLAUDE.md §8.1): 화면·에셋·노드를 일절 모른다.
##
## 원작 흐름 (`DragonAwaken` kind=1):
##   화로 클릭 → `PopupMasicStone`(3~6성 중 만들 마석 선택)
##            → `MasicStoneMakeLayer`(보유한 **알**을 재료로 골라 '강화' → 포인트 누적)
##            → 목표 포인트 도달 시 `makeMasicStoneComplete` → 그 성급의 마석 1개 획득.
##
## 진행도는 원작에서 계정(서버) 값이었다 —
##   `AccountManager+0xf4` 현재 포인트 · `+0xf8` 목표 포인트 · `+0xfc` 선택한 마석 등급
##   (`DragonAwaken::init` 이 이 셋을 읽어 `refreshStoneInfo` 에 넘긴다).
## 유실이므로 우리는 `UserDB` pmeta `awaken_stone` = {"star": N, "points": P} 로 대체한다.
##
## 수치 출처: `data/awaken.json` `stone_craft`
##   · 목표 포인트 3성 5000 / 4성 10000 / 5성 20000 / 6성 40000 — **위키 item.pdf 각주 [44] 확정**
##   · 알 1개당 포인트 — 위키에 없다. 레퍼런스 관측 2점(920·1200)을 4·5성으로 고정한 자작표.

const STARS := [3, 4, 5, 6]

## 이 성급 마석을 만드는 데 필요한 총 포인트. 표에 없으면 0.
static func need(cfg: Dictionary, star: int) -> int:
	return int(_sc(cfg).get("points_needed", {}).get(str(star), 0))

## 알 1개가 주는 포인트(그 알이 될 드래곤의 성급 기준).
static func egg_points(cfg: Dictionary, star: int) -> int:
	return int(_sc(cfg).get("egg_points_by_star", {}).get(str(star), 0))

## 한 번에 넣을 수 있는 알 **종류** 수 상한(원작 `MasicStoneErroMsg_4`).
static func max_kinds(cfg: Dictionary) -> int:
	return int(_sc(cfg).get("max_egg_kinds_per_batch", 5))

## 이번 배치가 주는 포인트 합. entries = [{"star": int, "count": int}, …]
static func batch_points(cfg: Dictionary, entries: Array) -> int:
	var sum := 0
	for e in entries:
		sum += egg_points(cfg, int((e as Dictionary).get("star", 0))) * int(e.get("count", 0))
	return sum

## 배치 투입 가능 여부. 반환 "" = 통과, 그 외에는 원작 `MasicStoneErroMsg_*` 에 대응하는 사유.
## 원작 대응: _3 선택된 마석 없음 · _4 종류 초과 · _6 1개 이상 선택.
##
## ⚠️ 포인트 초과(_5 "각성에 필요한 포인트를 초과했습니다.")는 **여기서 막지 않는다** —
##   사용자 확정(2026-07-30): 초과분 때문에 목표 포인트를 정확히 맞춰야만 제작이 되던 것은
##   너무 불편하다. 초과는 `overflow()` 로 알려 주고 호출자가 **경고 한 번**만 띄운 뒤
##   제작을 진행한다(초과분은 버려진다 — `apply()` 가 완성 시 포인트를 0 으로 되돌린다).
##   원작 문자열은 남아 있지만 그 판정은 서버 소유였고(에러 코드는 서버 응답의 `rs` 값 →
##   `MasicStoneErroMsg_%d`, `MasicStoneMakeLayer.c:3561`) 우리 규칙으로 대체한다.
static func check_batch(cfg: Dictionary, star: int, have_points: int, entries: Array) -> String:
	if not STARS.has(star):
		return "선택된 각성의 마석이 없습니다."
	var kinds := 0
	var total := 0
	for e in entries:
		var c := int((e as Dictionary).get("count", 0))
		if c > 0:
			kinds += 1
			total += c
	if total <= 0:
		return "재료로 사용할 알을 1개 이상 선택해 주세요"
	if kinds > max_kinds(cfg):
		return "한번에 넣을수 있는 알의 종류를 초과했습니다."
	return ""

## 이 배치가 목표를 얼마나 넘기는가(포인트). 0 = 초과 없음.
static func overflow(cfg: Dictionary, star: int, have_points: int, entries: Array) -> int:
	var n := need(cfg, star)
	if n <= 0:
		return 0
	return maxi(0, have_points + batch_points(cfg, entries) - n)

## 배치 반영 결과(순수 계산). 반환 {points, complete}.
## `complete` 면 호출자가 마석 1개를 지급하고 포인트를 0 으로 되돌린다(초과분은 버려진다).
static func apply(cfg: Dictionary, star: int, have_points: int, entries: Array) -> Dictionary:
	var p := have_points + batch_points(cfg, entries)
	var n := need(cfg, star)
	var done := n > 0 and p >= n
	return {"points": 0 if done else p, "complete": done}

## 완성 시 받는 아이템 키. `data/items.json` 의 `evol_jewel_<성급>` 과 같은 규약.
static func reward_key(star: int) -> String:
	return "evol_jewel_%d" % star

static func _sc(cfg: Dictionary) -> Dictionary:
	return cfg.get("stone_craft", {})
