class_name ItemEffect
## 소모 아이템(드링크 버프 · 회복 물약) 효과 판정 — **순수 로직**.
##
## 계층(CLAUDE.md §8): logic. 노드·씬·에셋을 모른다. 정의는 data/item_effects.json.
## 규칙 출처 = docs/ref/wiki/item.pdf §2.2/§2.3, 수치 = 사용자 확정(2026-07-26).
##   · 드링크: 능력치 +5%/단계, 지속 10턴, **중복 복용 시 지속시간만 연장**(효력 고정)
##   · 회복물약: 최대 체력의 30% 회복, 단계는 사용 가능 레벨대만 가름

## 아이템 키(`att_drink2` 등)를 해석. 드링크가 아니면 {}.
## 반환: {stat: "att", tier: 2, pct: 10, turns: 10}
static func drink_of(defs: Dictionary, key: String) -> Dictionary:
	var d: Dictionary = defs.get("drink", {})
	var stats: Dictionary = d.get("stats", {})
	for prefix in stats.keys():
		if not key.begins_with(String(prefix)):
			continue
		var tail := key.substr(String(prefix).length())
		if not tail.is_valid_int():
			continue
		var tier := int(tail)
		if tier < 1:
			continue
		return {
			"stat": String(stats[prefix]),
			"tier": tier,
			"pct": int(d.get("pct_per_tier", 5)) * tier,
			"turns": int(d.get("duration_turns", 10)),
		}
	return {}

## 이미 걸린 버프에 새 드링크를 얹는다(위키 규칙: 지속시간만 연장, 효력은 더 강한 쪽 유지).
## active = {stat: {"pct": int, "turns": int}} 를 **새 Dictionary로** 돌려준다(입력 불변).
static func apply_drink(active: Dictionary, eff: Dictionary) -> Dictionary:
	if eff.is_empty():
		return active.duplicate(true)
	var out := active.duplicate(true)
	var s := String(eff["stat"])
	var cur: Dictionary = out.get(s, {"pct": 0, "turns": 0})
	# "중복 복용할 경우 효과의 지속시간만 증가하고 효력은 증가하지 않는다" (item.pdf §2.3)
	# → 같은 효력이면 턴만 누적. 더 센 단계를 마시면 효력은 그 단계로 갱신(하향은 안 함).
	out[s] = {
		"pct": maxi(int(cur.get("pct", 0)), int(eff["pct"])),
		"turns": int(cur.get("turns", 0)) + int(eff["turns"]),
	}
	return out

## 턴 경과: 모든 버프의 남은 턴 -1, 0 이하는 제거.
static func tick(active: Dictionary) -> Dictionary:
	var out := {}
	for s in active.keys():
		var b: Dictionary = active[s]
		var t := int(b.get("turns", 0)) - 1
		if t > 0:
			out[s] = {"pct": int(b.get("pct", 0)), "turns": t}
	return out

## 스탯에 걸린 버프 배수(1.0 = 무버프).
static func mult(active: Dictionary, stat: String) -> float:
	var b: Dictionary = active.get(stat, {})
	return 1.0 + float(int(b.get("pct", 0))) / 100.0

# -------------------------------------------------------- 탐험 보상 배수권(경험치·골드 N배)
#
# 원작 설명문 + 위키 item.pdf §9.6 이 규칙을 확정한다: **1시간 동안 탐험에서 얻는
# 경험치/골드를 N배**. 🟦 사용자 확정 2026-08-04: **게임을 꺼도 시간이 흐른다** →
# 만료를 **실시간 unix 초**로 들고 있고(UserDB pmeta `reward_buff`), 턴·전투 수와 무관하다.
# 수치·중복 규칙은 `data/item_effects.json` `reward_buff`.
#
# 상태 형식(그대로 세이브에 들어간다):
#   {"exp": {"mult": 2, "until": 1785200000}, "gold": {...}}   — 축마다 하나씩, 없으면 무버프.

## 이 아이템이 보상 배수권인가 → {axis: "exp"|"gold", mult: 2, seconds: 3600}. 아니면 {}.
static func reward_buff_of(defs: Dictionary, key: String) -> Dictionary:
	var cfg: Dictionary = defs.get("reward_buff", {})
	var row = (cfg.get("items", {}) as Dictionary).get(key, null)
	if not (row is Dictionary):
		return {}
	return {
		"axis": String((row as Dictionary).get("axis", "")),
		"mult": int((row as Dictionary).get("mult", 1)),
		"seconds": int(cfg.get("duration_sec", 3600)),
	}

## 지금 이 축에 걸린 배수(1.0 = 무버프). 만료된 항목은 없는 것으로 본다.
static func reward_buff_mult(active: Dictionary, axis: String, now: int) -> float:
	var b = active.get(axis, null)
	if not (b is Dictionary):
		return 1.0
	if int((b as Dictionary).get("until", 0)) <= now:
		return 1.0
	return maxf(1.0, float(int((b as Dictionary).get("mult", 1))))

## 남은 시간(초). 0 = 안 걸려 있음.
static func reward_buff_left(active: Dictionary, axis: String, now: int) -> int:
	var b = active.get(axis, null)
	if not (b is Dictionary):
		return 0
	return maxi(0, int((b as Dictionary).get("until", 0)) - now)

## 배수권 사용 → {ok, active, reason}.
##   ok=false 면 **아이템을 소모하지 않는다**(더 낮은 배수를 덧쓰려 한 경우).
## 규칙(ASSUMPTION, 드링크 선례 §2.3): 같은 배수 = 시간 누적 / 더 높은 배수 = 배수 갱신 +
##   남은 시간 유지(최소 지속시간 보장) / 더 낮은 배수 = 거부.
static func apply_reward_buff(active: Dictionary, eff: Dictionary, now: int) -> Dictionary:
	if eff.is_empty():
		return {"ok": false, "active": active.duplicate(true), "reason": "배수권이 아닙니다"}
	var axis := String(eff["axis"])
	var mult := int(eff["mult"])
	var secs := int(eff["seconds"])
	var out := active.duplicate(true)
	var left := reward_buff_left(active, axis, now)
	var cur := int(reward_buff_mult(active, axis, now))
	if left <= 0:
		out[axis] = {"mult": mult, "until": now + secs}
		return {"ok": true, "active": out, "reason": ""}
	if mult < cur:
		return {"ok": false, "active": out,
			"reason": "이미 %d배 버프가 걸려 있습니다 (남은 시간 %d분)" % [cur, int(ceil(float(left) / 60.0))]}
	if mult == cur:
		out[axis] = {"mult": cur, "until": now + left + secs}     # 시간 누적
	else:
		out[axis] = {"mult": mult, "until": now + maxi(left, secs)}  # 배수 갱신
	return {"ok": true, "active": out, "reason": ""}

## 만료분을 걷어낸 상태(세이브 정리용). 바뀐 게 없으면 같은 내용을 돌려준다.
static func prune_reward_buff(active: Dictionary, now: int) -> Dictionary:
	var out := {}
	for a in active.keys():
		var b = active[a]
		if b is Dictionary and int((b as Dictionary).get("until", 0)) > now:
			out[a] = (b as Dictionary).duplicate()
	return out

## "42분" / "1시간 3분" — 남은 시간 표시용(render 가 문자열만 받아 쓴다).
static func reward_buff_left_text(sec: int) -> String:
	if sec <= 0:
		return ""
	var m := int(ceil(float(sec) / 60.0))
	if m < 60:
		return "%d분" % m
	return "%d시간 %d분" % [m / 60, m % 60]

# ------------------------------------------------------------------ 회복 물약

## 회복 물약을 이 레벨의 드래곤에게 쓸 수 있는가(위키 §2.2 레벨대).
static func heal_usable(defs: Dictionary, key: String, level: int) -> bool:
	for t in (defs.get("heal_potion", {}).get("tiers", []) as Array):
		if String((t as Dictionary).get("key", "")) == key:
			return level >= int(t.get("level_min", 1)) and level <= int(t.get("level_max", 50))
	return false

## 회복량 = 최대 체력의 heal_pct_of_max %. 남은 체력을 넘지 않게 잘라서 반환.
static func heal_amount(defs: Dictionary, hp: int, hp_max: int) -> int:
	var pct := int(defs.get("heal_potion", {}).get("heal_pct_of_max", 30))
	return mini(maxi(0, hp_max - hp), int(round(float(hp_max) * float(pct) / 100.0)))

# ------------------------------------------------------------------ 허기(FOOD · 먹이)

## 원작의 **허기 시스템** 판정 — 순수 로직.
##
## 사용자 확정(2026-07-30): 원작 초기엔 **피로도 5칸**(탐험 1회마다 1칸 소모 + 시간 회복)이
## 있었으나 후기 버전에서 **피로도는 삭제되고 허기만 남았다**. 우리는 피로도를 구현하지 않고
## 허기만 쓴다.
##
## 눈금은 원작 용어(`Dragon::isFood` · `common/bar_food` · `StatusLayer::onClickFood`)를 따라
## **FOOD** 로 센다 — **`food_max` = 배부름 … 0 = 굶음**. 사용자 표현 "허기가 소진됐다" = food 0.
##
## 규칙:
##   · 전투 1회당 food 감소(`battle.gd FOOD_PER_BATTLE`).
##   · **속성이 맞는 먹이**만 먹는다. 먹이는 속성당 2종이고 회복량이 다르다 —
##     하나는 **절반**, 하나는 **전량**. 어느 쪽이 절반인지는 원작 파일명이 말해 준다:
##     `food_ground_paopao_half` 가 literally "half" 이고 나머지 8속성도 같은 축
##     (piece · leg · small · tadpole · fly(치어) · branch = 작은 쪽).
##     목록은 접미사 추론이 아니라 **데이터**다 → `data/item_effects.json` `feed.half`/`feed.full`.
##   · food 가 0이면 **탐험 입장 불가**이고, 탐험 중 0이 되면 **즉시 종료**된다
##     (사용자 확정 2026-07-30 — 원작 `checkNightHungry` → `onClickCantPlay` 계열의 오프라인 대응).
##
## 원작 근거: `Dragon::isFood` + `AdventureScene::checkNightHungry`(:12712) →
## `<AdventureFoodByGold>`(골드로 먹이 구매) / `onClickServeFoodAsGold` / `onClickCantPlay`.
## 데이터 근거: `data/items.json` 의 `subcategory=feed` **18종** = 정확히 9속성 × 2단.
##
## ⚠️ # ASSUMPTION 1건 — **눈금과 소모 속도**는 서버 유실이다(우리 눈금 100 · 전투당 −15).
##   튜닝 노브는 `item_effects.json feed.food_max` 와 `battle.gd FOOD_PER_BATTLE` 둘뿐이다.
const FOOD_MAX := 100

## FOOD 눈금 상한(데이터 우선, 없으면 상수).
static func food_max(defs: Dictionary) -> int:
	return int(defs.get("feed", {}).get("food_max", FOOD_MAX))

## 굶었는가 — 이 상태에서는 탐험에 들어갈 수 없고, 탐험 중이면 즉시 종료된다.
static func is_starving(defs: Dictionary, food: int) -> bool:
	return clampi(food, 0, food_max(defs)) <= 0

## 이 아이템이 '먹이'인가(드링크·회복물약·부활약 제외).
static func is_feed(item_def: Dictionary) -> bool:
	return String(item_def.get("category", "")) == "food" \
		and String(item_def.get("subcategory", "")) == "feed"

## 이 먹이를 그 속성의 드래곤이 먹을 수 있는가.
## 먹이에 속성이 없으면(범용) 누구나 먹는다 — 현 데이터에는 그런 먹이가 없지만
## 원본이 추가돼도 규칙이 깨지지 않게 열어 둔다.
static func feed_matches(item_def: Dictionary, dragon_element: String) -> bool:
	var el := String(item_def.get("element", ""))
	if el == "" or el == "null":
		return true
	return el == dragon_element

## 이 먹이가 채워 주는 비율(%). 목록에 없으면 안전하게 절반으로 본다
## (지어낸 100%로 후하게 주지 않는다).
static func feed_restore_pct(defs: Dictionary, key: String) -> int:
	var f: Dictionary = defs.get("feed", {})
	var pct: Dictionary = f.get("restore_pct", {})
	if (f.get("full", []) as Array).has(key):
		return int(pct.get("full", 100))
	return int(pct.get("half", 50))

## 먹이를 먹인 뒤의 FOOD. 속성이 맞을 때만 오르고, 회복 비율은 먹이 종류가 정한다
## (전량 = 상한까지 · 절반 = 상한의 절반만큼 증가, 상한에서 잘린다).
static func food_after_feed(defs: Dictionary, item_def: Dictionary, key: String,
		dragon_element: String, food: int) -> int:
	var fmax := food_max(defs)
	var cur := clampi(food, 0, fmax)
	if not (is_feed(item_def) and feed_matches(item_def, dragon_element)):
		return cur
	var pct := feed_restore_pct(defs, key)
	if pct >= 100:
		return fmax
	return mini(fmax, cur + int(round(float(fmax) * float(pct) / 100.0)))

## 굶은 드래곤 uid 목록. 파티(uid 배열)와 세이브 레코드 조회 콜러블을 받아 **순수하게** 판정한다
## (logic 층이라 UserDB 를 직접 모른다 — 호출부가 조회 함수를 넘긴다).
static func starving_uids(defs: Dictionary, uids: Array, get_dragon: Callable) -> Array:
	var out: Array = []
	var fmax := food_max(defs)
	for uid in uids:
		var d: Dictionary = get_dragon.call(int(uid))
		if is_starving(defs, int(d.get("food", fmax))):
			out.append(int(uid))
	return out

## 이 드래곤이 먹을 수 있는 먹이 중 **가방에서 처음 찾은 것**의 키. 없으면 "".
## 원작 `WorldMapScene::setDragonFood`(@01b1d0c4) 과 같은 방식 — `getRace()` 로 속성 글자
## ("E"/"A"/"F"/"W"/"L"/"D"/"H"/"C"/"S")를 정하고 인벤토리를 앞에서부터 훑어
## `getType()==0`(먹이) && `getTypeDetail()==그 글자` && `getCount()>0` 인 첫 항목을 집는다.
## items = {아이템키: 수량} · item_defs = {아이템키: 정의}
static func find_matching_feed(items: Dictionary, item_defs: Dictionary,
		dragon_element: String) -> String:
	for k in items:
		if int(items[k]) <= 0:
			continue
		var idef: Dictionary = item_defs.get(k, {})
		if is_feed(idef) and feed_matches(idef, dragon_element):
			return String(k)
	return ""

## 이 드래곤이 먹을 수 있는 먹이를 가방에 갖고 있는가.
static func has_matching_feed(items: Dictionary, item_defs: Dictionary,
		dragon_element: String) -> bool:
	return find_matching_feed(items, item_defs, dragon_element) != ""

## 이 먹이가 '상당히'(전량) 채우는가 — 원작 `Item::getTypeParam() < 0xb` 분기가 고르는
## `<CaveDragonFoodMsg1>`("상당히") / `<CaveDragonFoodMsg2>`("약간") 에 대응한다.
static func feed_is_full(defs: Dictionary, key: String) -> bool:
	return feed_restore_pct(defs, key) >= 100
