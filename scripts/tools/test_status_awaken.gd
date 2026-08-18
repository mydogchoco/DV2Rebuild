extends Node

const DRAGON_ID := 4132
const EVD_ADD := 40.0

var _fail := 0

func _ready() -> void:
	await get_tree().process_frame
	var uid := _inject(true)
	var d := UserDB.get_dragon(uid)

	var shown: Dictionary = StatusPanel.display_stats(d)
	var base: Dictionary = shown["base"]
	var total: Dictionary = shown["total"]
	var want := float(base.get("evd", 0.0)) + EVD_ADD
	_check("상태창 회피 표기 = 기본 + 40%p", absf(float(total.get("evd", 0.0)) - want) < 0.001,
		"표기 %.1f / 기대 %.1f" % [float(total.get("evd", 0.0)), want])
	_check("보너스 표기가 40", int(total.get("evd", 0.0)) - int(base.get("evd", 0.0)) == 40,
		"%d" % (int(total.get("evd", 0.0)) - int(base.get("evd", 0.0))))
	_check("치명·방어율은 그대로",
		int(total.get("cri", 0)) == int(base.get("cri", 0))
		and int(total.get("blk", 0)) == int(base.get("blk", 0)),
		"cri=%d blk=%d" % [int(total.get("cri", 0)), int(total.get("blk", 0))])

	var party: Array = PartyStats.summary([uid], false, "")
	PartyStats.apply_passives(party, {"element": "fire", "hp": 1000}, {})
	var pd: Dictionary = party[0]
	var c := Battle.make_combatant("A0", "ally", String(pd["element"]), pd["stats"])
	for e in (pd.get("awaken_effects", []) as Array):
		(c["effects"] as Array).append((e as Dictionary).duplicate())
	var fought := Battle._eff_f(c, "evd")
	_check("전투 값과 일치", absf(fought - float(total.get("evd", 0.0))) < 0.001,
		"전투 %.1f / 표기 %.1f" % [fought, float(total.get("evd", 0.0))])

	var uid2 := _inject(false)
	var shown2: Dictionary = StatusPanel.display_stats(UserDB.get_dragon(uid2))
	_check("미각성은 기본값 그대로",
		is_equal_approx(float((shown2["total"] as Dictionary).get("evd", 0.0)),
			float((shown2["base"] as Dictionary).get("evd", 0.0))),
		"%.1f" % float((shown2["total"] as Dictionary).get("evd", 0.0)))

	if _fail == 0:
		print("[test_status_awaken] ALL PASS")
	else:
		printerr("[test_status_awaken] %d FAIL" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

func _inject(awakened: bool) -> int:
	var raw: Dictionary = UserDB.raw()
	var d: Dictionary = UserDB._new_dragon(DRAGON_ID, 30, UserDB._zero_bonus())
	var log: Array = []
	for i in int(d["level"]) - 1:
		log.append({"hp": 0, "att": 0, "def": 0})
	d["gain_log"] = log
	if awakened:
		d["awakened"] = true
		d["awaken_skill"] = Data.awaken_skill_of(DRAGON_ID)
	(raw["dragons"] as Array).append(d)
	return int(d["uid"])

func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		return
	_fail += 1
	printerr("  FAIL %s%s" % [label, ("  ― " + detail) if detail != "" else ""])
