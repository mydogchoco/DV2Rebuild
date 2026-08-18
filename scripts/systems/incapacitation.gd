class_name Incapacitation
extends RefCounted

static func is_down(cure_time: int, now: int) -> bool:
	return cure_time > now

static func remain(cure_time: int, now: int) -> int:
	return maxi(0, cure_time - now)

static func avoids(cure_pct: int, rng: RandomNumberGenerator) -> bool:
	if cure_pct <= 0:
		return false
	return rng.randi_range(1, 100) <= cure_pct

static func down_until(cfg: Dictionary, now: int) -> int:
	return now + int(cfg.get("recover_seconds", 3600))

static func instant_cost(cfg: Dictionary, cure_time: int, now: int) -> int:
	var sec := int(cfg.get("instant_cure_seconds_per_dia", 1800))
	var left := remain(cure_time, now)
	if sec <= 0 or left <= 0:
		return 0
	return left / sec + 1

static func remain_clock(cure_time: int, now: int) -> String:
	var s := remain(cure_time, now)
	if s <= 0:
		return ""
	if s < 3600:
		return "%02d:%02d" % [s / 60, s % 60]
	return "%02d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]

static func is_cure_item(cfg: Dictionary, key: String) -> bool:
	return key in (cfg.get("cure_items", []) as Array)

static func remain_text(cure_time: int, now: int) -> String:
	var s := remain(cure_time, now)
	if s <= 0:
		return ""
	var h := s / 3600
	var m := (s % 3600) / 60
	if h > 0:
		return "%d시간 %d분" % [h, m]
	return "%d분" % maxi(1, m)
