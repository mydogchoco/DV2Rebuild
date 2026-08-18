class_name BattleReward
extends RefCounted

const GOLD := "gold"
const EXP := "exp"

static func amount(kind: String, level: int, boss: bool, elite: bool,
		table: Dictionary, stage: Dictionary = {}) -> int:
	var cfg: Dictionary = (table.get("battle_reward", {}) as Dictionary).get(kind, {})
	var v := float(base_amount(kind, level, table, stage))
	if boss:
		v *= float(cfg.get("boss_mult", 1.0))
	if elite:
		v *= float(cfg.get("elite_mult", 1.0))
	return maxi(0, int(round(v)))

static func base_amount(kind: String, level: int, table: Dictionary,
		stage: Dictionary = {}) -> int:
	var ov := stage_override(kind, stage)
	if ov >= 0:
		return ov
	var cfg: Dictionary = (table.get("battle_reward", {}) as Dictionary).get(kind, {})
	return maxi(0, int(cfg.get("per_level", 0)) * maxi(1, level) + int(cfg.get("base", 0)))

static func stage_override(kind: String, stage: Dictionary) -> int:
	var rw = (stage.get("rewards", {}) as Dictionary).get(kind, null)
	if rw == null:
		return -1
	var n := int(rw)
	return n if n >= 0 else -1
