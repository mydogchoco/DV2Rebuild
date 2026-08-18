class_name AdvAuto

const KEY := "adv_auto"

const LVUP_CLOSE_SECS := 2.5
const FINISH_SECS := 2.0
const CARD_PICK_SECS := 1.0

static func enabled() -> bool:
	return bool(UserDB.get_pmeta(KEY, false))

static func set_enabled(on: bool) -> void:
	UserDB.set_pmeta(KEY, on)

static func off() -> void:
	set_enabled(false)

static func toggle() -> bool:
	var v := not enabled()
	set_enabled(v)
	return v

static func arm(host: Node, secs: float, cb: Callable) -> void:
	if not enabled() or not is_instance_valid(host) or not host.is_inside_tree():
		return
	var t := host.get_tree().create_timer(secs)
	t.timeout.connect(func() -> void:
		if not is_instance_valid(host) or not enabled():
			return
		if cb.is_valid():
			cb.call())
