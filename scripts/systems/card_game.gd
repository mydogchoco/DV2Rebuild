class_name CardGame
extends RefCounted
## 탐험 카드 미니게임 규칙 — logic 층(CLAUDE.md §8). 화면·에셋을 모르고, 데이터는 **인자로 받는다**
## (`Drops` · `EggGacha` 와 같은 관례 — 화면 없이 테스트 가능).
##
## 원작: `CardMiniGameLayer`(31메서드) + `CardItem`(24메서드). 둘 다 디컴프 완전(skip 0).
## 규칙·보상 종류는 위키 확정, 가중치만 자작 — 근거 인용은 `data/card_game.json`,
## 포팅 카드는 `docs/ref/porting/CardMiniGame.md`.
##
##   A. match  카드 8장(4쌍), 기회 4번. 한 번의 기회 = 2장 뒤집기.
##             짝이면 그 카드의 보상을 받고 **성공으로 끝난다**(위키 "1번이라도 … 성공").
##   B. avoid  카드 3장 중 꽝 1~2장. 한 장을 골라 꽝이 아니면 성공.
##
## 이 클래스는 **결과만 만든다** — 뒤집기 연출·딤·하트 UI 는 render(§8.3) 몫이다.

## 덱 1벌 생성. 반환 = {"mode", "cards":[{id, kind, …}], "chances"}
##   cards[i] 는 그 자리의 **내용물**이다(앞면). 뒤집기 전 표시는 render 가 뒷면으로 가린다.
##   match 모드의 cards 는 짝이 맞도록 같은 보상이 2장씩 들어간다.
static func make_deck(mode: String, cfg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var g: Dictionary = (cfg.get("games", {}) as Dictionary).get(mode, {})
	if g.is_empty():
		return {}
	var n := int(g.get("cards", 8))
	var cards: Array = []
	if mode == "avoid":
		var lo := int(g.get("blanks_min", 1))
		var hi := int(g.get("blanks_max", 2))
		var blanks: int = clampi(lo + (rng.randi_range(0, maxi(0, hi - lo))), 1, n - 1)
		for i in blanks:
			cards.append(_blank(cfg))
		for i in (n - blanks):
			cards.append(roll_reward(cfg, rng))
	else:
		# 4쌍 — **서로 다른** 보상 4종을 뽑아 2장씩.
		# 🔴 2026-07-28: 독립 추첨 4번이면 같은 보상이 겹쳐 "8장 중 6장이 체력 회복" 같은 덱이 나온다.
		#    그러면 짝 맞추기가 성립하지 않는다(아무 두 장이나 짝이 된다) → 중복 없이 뽑는다.
		var pairs := int(n / 2)
		var picked: Array = []
		var guard := 0
		while picked.size() < pairs and guard < 200:
			guard += 1
			var r := roll_reward(cfg, rng)
			var sig := _signature(r)
			var dup := false
			for q in picked:
				if _signature(q) == sig:
					dup = true
					break
			if not dup:
				picked.append(r)
		# 보상 종류가 모자라면(가중치 0 등) 남는 자리는 꽝으로 채운다 — 덱 크기는 지킨다.
		while picked.size() < pairs:
			picked.append(_blank(cfg))
		for r2 in picked:
			cards.append(r2)
			cards.append((r2 as Dictionary).duplicate(true))
	_shuffle(cards, rng)
	for i in cards.size():
		(cards[i] as Dictionary)["id"] = i
	return {"mode": mode, "cards": cards, "chances": int(g.get("chances", 1))}

## 보상 1개 추첨(가중치). `data/card_game.json` rewards[].weight.
static func roll_reward(cfg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array = cfg.get("rewards", [])
	if pool.is_empty():
		return _blank(cfg)
	var total := 0.0
	for r in pool:
		total += maxf(0.0, float((r as Dictionary).get("weight", 0)))
	if total <= 0.0:
		return _blank(cfg)
	var x := rng.randf() * total
	for r in pool:
		x -= maxf(0.0, float((r as Dictionary).get("weight", 0)))
		if x <= 0.0:
			return _materialize(r as Dictionary, rng)
	return _materialize(pool[pool.size() - 1] as Dictionary, rng)

## 보상 정의 → **확정된 1건**(범위·풀을 굴려 값을 박는다). render 와 UserDB 는 이걸 그대로 쓴다.
static func _materialize(def: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var out := {
		"kind": String(def.get("kind", "none")),
		"label": String(def.get("label", "")),
		"frame": String(def.get("frame", "")),
	}
	match String(def.get("kind", "")):
		"gold", "diamond":
			var lo := int(def.get("min", 0))
			var hi := int(def.get("max", lo))
			out["amount"] = rng.randi_range(lo, maxi(lo, hi))
		"egg":
			var pool: Array = def.get("pool", [])
			if pool.is_empty():
				return _blank({})
			out["dragon_id"] = int(pool[rng.randi_range(0, pool.size() - 1)])
		"buff_att", "buff_def":
			out["tier"] = int(def.get("tier", 1))
	return out

static func _blank(cfg: Dictionary) -> Dictionary:
	var b: Dictionary = cfg.get("blank", {})
	return {"kind": "none", "label": String(b.get("label", "꽝")),
		"frame": String(b.get("frame", "fail"))}

## 보상 1건의 동일성 키(종류 + 굴린 값). 중복 없이 뽑기·짝 판정이 같은 기준을 쓴다.
static func _signature(r: Dictionary) -> String:
	return "%s:%d:%d:%d" % [String(r.get("kind", "")), int(r.get("amount", -1)),
		int(r.get("dragon_id", -1)), int(r.get("tier", -1))]

## 두 장이 짝인가 — 같은 보상이면 짝이다(꽝끼리는 짝으로 치지 않는다).
static func is_match(a: Dictionary, b: Dictionary) -> bool:
	if String(a.get("kind", "")) == "none" or String(b.get("kind", "")) == "none":
		return false
	if String(a.get("kind", "")) != String(b.get("kind", "")):
		return false
	# 같은 종류라도 내용이 다르면(골드 액수·알 종류) 다른 카드다.
	for k in ["amount", "dragon_id", "tier"]:
		if int(a.get(k, -1)) != int(b.get(k, -1)):
			return false
	return true

## Fisher–Yates. rng 를 그대로 쓰므로 시드 고정 시 재현된다(§4).
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
