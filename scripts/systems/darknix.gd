class_name Darknix
extends RefCounted

const ENTER := "enter"
const USE_ITEM := "use_item"
const USE_CASH := "use_cash"
const NO_CASH := "no_cash"

const FACE_NONE := 0
const FACE_FIRST := 1
const FACE_FINISH := 2

static func is_summon_stage(stage: Dictionary) -> bool:
	var s = stage.get("summon", null)
	return typeof(s) == TYPE_DICTIONARY and not (s as Dictionary).is_empty()

static func is_active(state: Dictionary, now: int) -> bool:
	return int(state.get("until", 0)) > now

static func remain(state: Dictionary, now: int) -> int:
	return maxi(0, int(state.get("until", 0)) - now)

static func gate(cfg: Dictionary, state: Dictionary, now: int,
		item_count: int, cash: int) -> Dictionary:
	if is_active(state, now):
		return {"action": ENTER}
	var item := String(cfg.get("item", ""))
	var need := maxi(1, int(cfg.get("item_count", 1)))
	if item != "" and item_count >= need:
		return {"action": USE_ITEM, "item": item, "item_count": need}
	var price := int(cfg.get("cash", 0))
	if price > 0 and cash >= price:
		return {"action": USE_CASH, "cash": price}
	return {"action": NO_CASH, "cash": price}

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

static func variant_of(cfg: Dictionary, status: int) -> Dictionary:
	for v in (cfg.get("variants", []) as Array):
		if int((v as Dictionary).get("status", 0)) == status:
			return v
	return {}

static func anim_of(cfg: Dictionary, status: int, slot: int) -> String:
	var a: Array = variant_of(cfg, status).get("anim", [])
	return String(a[slot]) if slot >= 0 and slot < a.size() else ""

static func enemy_index(cfg: Dictionary, state: Dictionary, now: int) -> int:
	if not is_active(state, now):
		return -1
	return int(variant_of(cfg, int(state.get("status", 0))).get("enemy", -1))

static func is_two_phase(cfg: Dictionary) -> bool:
	return bool(cfg.get("two_phase", false))

static func next_face(cfg: Dictionary, face: int) -> int:
	if not is_two_phase(cfg):
		return FACE_FINISH
	return FACE_FINISH if face == FACE_FIRST else FACE_FIRST
