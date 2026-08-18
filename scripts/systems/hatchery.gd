class_name Hatchery
extends RefCounted

const GRADE_MIN := 3.0
const GRADE_MAX := 7.0
const BLESSED_NEST_BONUS := 0.6

const SEC_AT_MIN := 600
const SEC_PER_GRADE := 750

static func roll_grade(u: float, blessed := false) -> float:
	var g := GRADE_MIN + clampf(u, 0.0, 0.9999) * (GRADE_MAX - GRADE_MIN)
	if blessed:
		g += BLESSED_NEST_BONUS
	return snappedf(g, 0.1)

static func grade_for(step: int, egg_cfg: Dictionary, u: float, blessed := false) -> float:
	var fixed := EggUpgrade.hatch_grade(maxi(0, step), egg_cfg)
	if fixed <= 0.0:
		return roll_grade(u, blessed)
	return snappedf(fixed + (BLESSED_NEST_BONUS if blessed else 0.0), 0.1)

static func bless(grade: float, blessed: bool) -> float:
	return snappedf(grade + (BLESSED_NEST_BONUS if blessed else 0.0), 0.1)

static func hatch_seconds(grade: float) -> int:
	return int(round(SEC_AT_MIN + maxf(0.0, grade - GRADE_MIN) * SEC_PER_GRADE))

static func format_remain(sec: int) -> String:
	sec = maxi(0, sec)
	if sec < 3600:
		return "%02d : %02d" % [sec / 60, sec % 60]
	return "%02d : %02d : %02d" % [sec / 3600, (sec % 3600) / 60, sec % 60]

static func format_remain_compact(sec: int) -> String:
	sec = maxi(0, sec)
	if sec < 3600:
		return "%02d:%02d" % [sec / 60, sec % 60]
	return "%02d:%02d:%02d" % [sec / 3600, (sec % 3600) / 60, sec % 60]

static func stat_bonus_for_grade(grade: float) -> Dictionary:
	var need := (grade - Growth.BASE_GRADE) / 0.1
	var per := need / 3.0
	return {
		"base": {"hp": snappedf(per * 4.0, 0.01), "att": snappedf(per, 0.01), "def": snappedf(per, 0.01)},
		"growth": {"hp": 0.0, "att": 0.0, "def": 0.0},
	}
