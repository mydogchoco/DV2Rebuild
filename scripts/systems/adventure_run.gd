class_name AdventureRun
extends RefCounted

const NOTHING := "nothing"
const MONSTER := "monster"
const HEAL_HOLY := "heal_holy"
const HEAL_PLAIN := "heal_plain"
const TREASURE := "treasure"
const QUEST := "quest"
const SHOP := "shop"
const CHOICE := "choice"
const CARDGAME := "cardgame"

const ORIG_EVENT_ID := {
	NOTHING: 0x01, MONSTER: 0x02, HEAL_HOLY: 0x13, HEAL_PLAIN: 0x14,
	TREASURE: 0x15, QUEST: 0x16, CARDGAME: 0x18, SHOP: 0x1a, CHOICE: 0x1b,
}

static func build_steps(stage: Dictionary, cfg: Dictionary, enc: int,
		opts: Dictionary, rng: RandomNumberGenerator) -> Array:
	if bool(opts.get("night", false)):
		return night_steps(stage, cfg, rng)
	if bool(opts.get("single_boss", false)):
		return [{"type": MONSTER, "boss": true, "final": true}]
	var out: Array = []
	var total := int((stage.get("enemies", []) as Array).size())
	var is_boss := (total > 0 and enc + 1 >= total) or bool(opts.get("random_boss", false))
	if not is_boss:
		var steps: Dictionary = cfg.get("steps", {})
		var n := int(steps.get("max_events_per_step", 1))
		var picked: Dictionary = {}
		for _i in maxi(0, n):
			var ev := _pick_event(steps, enc, opts, picked, rng)
			if ev == "":
				break
			picked[ev] = true
			out.append({"type": ev})
	var mon := {"type": MONSTER, "boss": is_boss}
	if not is_boss:
		var idx := _pick_encounter(stage.get("enemies", []), rng)
		if idx >= 0:
			mon["enemy_index"] = idx
	out.append(mon)
	return out

static func _pick_encounter(enemies: Array, rng: RandomNumberGenerator) -> int:
	if enemies.is_empty():
		return -1
	var tagged := false
	for e in enemies:
		if (e as Dictionary).has("boss"):
			tagged = true
			break
	var pool: Array = []
	for i in enemies.size():
		var is_boss := bool((enemies[i] as Dictionary).get("boss", false)) if tagged \
			else i == enemies.size() - 1
		if not is_boss:
			pool.append(i)
	if pool.is_empty():
		return -1
	return int(pool[_weighted_pick_of(enemies, pool, rng)])

static func night_steps(stage: Dictionary, cfg: Dictionary,
		rng: RandomNumberGenerator) -> Array:
	var enemies: Array = stage.get("enemies", [])
	var w: Dictionary = (cfg.get("night", {}) as Dictionary).get("weights", {})
	var commons: Array = []
	var bosses: Array = []
	var tagged := false
	for e in enemies:
		if bool((e as Dictionary).get("encounter", false)):
			tagged = true
			break
	for i in enemies.size():
		var e2: Dictionary = enemies[i]
		var is_common := bool(e2.get("encounter", false)) if tagged \
			else not bool(e2.get("boss", false))
		if is_common:
			commons.append(i)
		else:
			bosses.append(i)
	var w_nothing := maxf(0.0, float(w.get("nothing", 0)))
	var w_common := maxf(0.0, float(w.get("encounter", 0))) if not commons.is_empty() else 0.0
	var w_boss := maxf(0.0, float(w.get("boss", 0))) if not bosses.is_empty() else 0.0
	var total := w_nothing + w_common + w_boss
	if total <= 0.0:
		return [{"type": NOTHING, "final": true}]
	var x := rng.randf() * total
	if x < w_nothing:
		return [{"type": NOTHING, "final": true}]
	var pool := commons if x < w_nothing + w_common else bosses
	var idx := int(pool[_weighted_pick_of(enemies, pool, rng)])
	return [{"type": MONSTER, "final": true, "enemy_index": idx,
		"boss": bool((enemies[idx] as Dictionary).get("boss", false))}]

static func _weighted_pick_of(enemies: Array, pool: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for i in pool:
		total += maxf(0.0, float((enemies[int(i)] as Dictionary).get("weight", 1)))
	if total <= 0.0:
		return rng.randi() % pool.size()
	var x := rng.randf() * total
	for j in pool.size():
		x -= maxf(0.0, float((enemies[int(pool[j])] as Dictionary).get("weight", 1)))
		if x <= 0.0:
			return j
	return pool.size() - 1

static func _weighted_pick(rows: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for r in rows:
		total += maxf(0.0, float((r as Dictionary).get("weight", 1)))
	if total <= 0.0:
		return rng.randi() % rows.size()
	var x := rng.randf() * total
	for i in rows.size():
		x -= maxf(0.0, float((rows[i] as Dictionary).get("weight", 1)))
		if x <= 0.0:
			return i
	return rows.size() - 1

static func is_final(step: Dictionary) -> bool:
	return bool(step.get("final", false))

static func _pick_event(steps: Dictionary, enc: int, opts: Dictionary,
		already: Dictionary, rng: RandomNumberGenerator) -> String:
	var cands: Array = []
	var total := maxf(0.0, float(steps.get("nothing_weight", 0)))
	for e in (steps.get("events", []) as Array):
		var d: Dictionary = e
		var t := String(d.get("type", ""))
		if t == "" or already.has(t):
			continue
		if not is_available(d, enc, opts):
			continue
		var w := maxf(0.0, float(d.get("weight", 0)))
		if w <= 0.0:
			continue
		cands.append({"type": t, "weight": w})
		total += w
	if cands.is_empty() or total <= 0.0:
		return ""
	var r := rng.randf() * total
	for c in cands:
		r -= float((c as Dictionary)["weight"])
		if r <= 0.0:
			return String((c as Dictionary)["type"])
	return ""

static func is_available(ev: Dictionary, enc: int, opts: Dictionary) -> bool:
	if bool(ev.get("fortress_only", false)) and not bool(opts.get("fortress", false)):
		return false
	if bool(ev.get("needs_hurt", false)) and not bool(opts.get("hurt", false)):
		return false
	if enc < int(ev.get("min_enc", 0)):
		return false
	return true

static func is_heal(event_type: String) -> bool:
	return event_type == HEAL_HOLY or event_type == HEAL_PLAIN

static func offers_escape(_is_boss: bool) -> bool:
	return true

static func escape_frame(fortress: bool) -> String:
	return "scene_adventure_choice_giveup_KR" if fortress else "scene_adventure_choice_run_KR"

static func run_succeeds(_cfg: Dictionary, _is_boss: bool, _rng: RandomNumberGenerator) -> bool:
	return true
