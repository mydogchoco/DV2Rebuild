extends Node

const GEM := preload("res://scripts/systems/gem.gd")
const EQ := preload("res://scripts/systems/equipment.gd")

var _fails := 0

func _ready() -> void:
	print("── 동굴 젬/장비 장착 통합 점검 ──")
	var uid := UserDB.active_uid()
	var d := UserDB.get_dragon(uid)
	if d.is_empty():
		printerr("활성 드래곤이 없음 — 점검 불가"); _done(); return
	var ddef := Data.get_dragon(int(d["id"]))
	var lvl := int(d.get("level", 1))
	print("대상: uid=%d  %s  Lv.%d" % [uid, String(ddef.get("name", "?")), lvl])

	var bak_gems = d.get("gems", {})
	var bak_equip = d.get("equip", {})
	var bak_slots = d.get("equip_slots", null)

	UserDB.set_dragon_field(uid, "gems", {})
	UserDB.set_dragon_field(uid, "equip", {})
	var base := _cave_stats(uid)
	print("기준 스탯(젬·장비 비움): HP %d / 공 %d / 방 %d / 크리 %d / 회피 %d / 막기 %d" % [
		int(base["hp"]), int(base["att"]), int(base["def"]),
		int(base.get("cri", 0)), int(base.get("evd", 0)), int(base.get("blk", 0))])

	_check_gem(uid, base)
	_check_equip(uid, base)
	_check_battle_parity(uid)
	_check_slot_gate(uid)

	UserDB.set_dragon_field(uid, "gems", bak_gems)
	UserDB.set_dragon_field(uid, "equip", bak_equip)
	if bak_slots != null:
		UserDB.set_dragon_field(uid, "equip_slots", bak_slots)
	print("(세이브 원상복구 완료)")
	_done()

func _cave_stats(uid: int) -> Dictionary:
	var a := UserDB.get_dragon(uid)
	var base_bonus: Dictionary = (a.get("stat_bonus", {}) as Dictionary).get("base", {})
	var st: Dictionary = Growth.main_stats(
		Data.get_dragon(int(a.get("id", 0))), Data.stat_table, a.get("gain_log", []), base_bonus)
	st = GEM.apply(st, a.get("gems", {}), Data.gems)
	var pot: Dictionary = a.get("potential", {})
	for pk: String in ["hp", "att", "def"]:
		st[pk] = int(st.get(pk, 0)) + int(pot.get(pk, 0))
	return EQ.apply(st, a.get("equip", {}), Data.equipment)

func _check_gem(uid: int, base: Dictionary) -> void:
	print("\n[1] 젬 장착 — 동굴 '젬 장착' 팝업과 같은 호출(Gem.equip → UserDB.set_dragon_field)")
	UserDB.set_dragon_field(uid, "gems", {})
	var n1 := GEM.equip(UserDB.get_dragon(uid).get("gems", {}), "체력의 젬", 18, Data.gems)
	if n1.is_empty(): _fail("체력의 젬 장착 실패"); return
	UserDB.set_dragon_field(uid, "gems", n1)
	var saved := GEM.slots(UserDB.get_dragon(uid).get("gems", {}))
	_eq("세이브에 슬롯 1개", saved.size(), 1)
	_eq("세이브된 젬 이름", String(saved[0]["name"]), "체력의 젬")
	var s1 := _cave_stats(uid)
	_eq("HP +120 반영", int(s1["hp"]) - int(base["hp"]), 120)
	print("    HP %d → %d" % [int(base["hp"]), int(s1["hp"])])

	var n2 := GEM.equip(UserDB.get_dragon(uid).get("gems", {}), "공격의 소울젬", 9, Data.gems)
	UserDB.set_dragon_field(uid, "gems", n2)
	var s2 := _cave_stats(uid)
	var pot_att := int((UserDB.get_dragon(uid).get("potential", {}) as Dictionary).get("att", 0))
	var growth_att := int(base["att"]) - pot_att
	var want_att := int(round(float(growth_att + 40) * 1.18)) + pot_att
	_eq("소울젬 공격력(flat+%, 잠재는 젬 %% 미적용)", int(s2["att"]), want_att)
	_eq("소울젬 크리 +5", int(s2.get("cri", 0)) - int(base.get("cri", 0)), 5)
	print("    공 %d → %d (+40 후 ×1.18) / 크리 %d → %d" % [
		int(base["att"]), int(s2["att"]), int(base.get("cri", 0)), int(s2.get("cri", 0))])

	var n3 := GEM.equip(UserDB.get_dragon(uid).get("gems", {}), "방어의 젬", 18, Data.gems)
	UserDB.set_dragon_field(uid, "gems", n3)
	var n4 := GEM.equip(UserDB.get_dragon(uid).get("gems", {}), "방어의 젬", 18, Data.gems)
	_ok("4번째 젬 거부(3슬롯)", n4.is_empty())
	_eq("최종 장착 수", GEM.slots(UserDB.get_dragon(uid).get("gems", {})).size(), 3)

func _check_equip(uid: int, base: Dictionary) -> void:
	print("\n[2] 장비 장착 — 동굴 '장비 관리 → 변경' 과 같은 호출(Equipment.equip → set_dragon_field)")
	UserDB.set_dragon_field(uid, "gems", {})
	UserDB.set_dragon_field(uid, "equip", {})
	UserDB.set_dragon_field(uid, "equip_slots", 4)
	var cat := EQ.catalog(Data.equipment)
	var key_evd := "special:balrog:카이저 발록의 팔찌"
	var key_pure := "special:balrog:카이저 발록의 투구"
	if not cat.has(key_evd) or not cat.has(key_pure):
		_fail("카탈로그에 발록 장비 없음"); return
	var e1 := EQ.equip(UserDB.get_dragon(uid).get("equip", {}), "all", key_evd, Data.equipment)
	if e1.is_empty(): _fail("팔찌(보조형)를 자유칸에 장착 실패"); return
	UserDB.set_dragon_field(uid, "equip", e1)
	var e2 := EQ.equip(UserDB.get_dragon(uid).get("equip", {}), "battle", key_pure, Data.equipment)
	if e2.is_empty(): _fail("투구(전투형)를 전투칸에 장착 실패"); return
	UserDB.set_dragon_field(uid, "equip", e2)
	var slots: Array = UserDB.get_dragon(uid).get("equip", {}).get("slots", [])
	_eq("세이브에 장비 2개", slots.size(), 2)
	var s := _cave_stats(uid)
	_eq("회피 +13 반영", int(s.get("evd", 0)) - int(base.get("evd", 0)), 13)
	_eq("관통(pure) 40 반영", int(s.get("pure", 0)), 40)
	print("    회피 %d → %d / 관통 0 → %d" % [
		int(base.get("evd", 0)), int(s.get("evd", 0)), int(s.get("pure", 0))])
	_ok("투구를 보조칸에 거부",
		EQ.equip({}, "support", key_pure, Data.equipment).is_empty())
	var eq_now: Dictionary = UserDB.get_dragon(uid).get("equip", {})
	(eq_now["slots"][0] as Dictionary)["options"] = [{"stat": "att", "value": 25}]
	UserDB.set_dragon_field(uid, "equip", eq_now)
	var s3 := _cave_stats(uid)
	var att_no_opt := int(s.get("att", 0))
	var want_att := int(round(float(att_no_opt) * 1.25))
	_eq("장비 옵션 공 +25%(배수) 반영", int(s3["att"]), want_att)
	print("    공 %d → %d (옵션 +25%%)" % [att_no_opt, int(s3["att"])])

func _check_battle_parity(uid: int) -> void:
	print("\n[3] 동굴 표시 스탯 == 전투 스탯 (battle.gd _setup_party 와 같은 순서인지)")
	var d := UserDB.get_dragon(uid)
	var ddef := Data.get_dragon(int(d["id"]))
	var base_bonus: Dictionary = (d.get("stat_bonus", {}) as Dictionary).get("base", {})
	var bs := Growth.main_stats(ddef, Data.stat_table, d.get("gain_log", []), base_bonus)
	bs = GEM.apply(bs, d.get("gems", {}), Data.gems)
	var potb: Dictionary = d.get("potential", {})
	for pk in ["hp", "att", "def"]:
		bs[pk] = int(bs.get(pk, 0)) + int(potb.get(pk, 0))
	bs = EQ.apply(bs, d.get("equip", {}), Data.equipment)
	var cs := _cave_stats(uid)
	for k: String in ["hp", "att", "def", "cri", "evd", "blk", "pure", "depure", "cri_pow", "accuracy", "cure"]:
		_eq("동굴==전투 '%s'" % k, int(cs.get(k, 0)), int(bs.get(k, 0)))
	print("    전투: HP %d 공 %d 방 %d 관통 %d / 동굴: HP %d 공 %d 방 %d 관통 %d" % [
		int(bs["hp"]), int(bs["att"]), int(bs["def"]), int(bs.get("pure", 0)),
		int(cs["hp"]), int(cs["att"]), int(cs["def"]), int(cs.get("pure", 0))])
	var c := Battle.make_combatant("T", "ally", "fire", bs)
	_eq("combatant.pure", int(c["pure"]), int(bs.get("pure", 0)))
	_eq("combatant.evd", int(c["evd"]), int(bs.get("evd", 0)))

func _check_slot_gate(uid: int) -> void:
	print("\n[4] 장비칸 해금 게이트 — 동굴 '장비 관리'가 보여주는 칸 수")
	for n in [1, 2, 3, 4]:
		UserDB.set_dragon_field(uid, "equip_slots", n)
		var unlocked := int(UserDB.get_dragon(uid).get("equip_slots", 1))
		var ids := EQ.slot_ids(unlocked)
		_eq("해금 %d칸 → 표시 칸 수" % n, ids.size(), n)
	UserDB.set_dragon_field(uid, "equip_slots", null)
	var d := UserDB.get_dragon(uid)
	d.erase("equip_slots")
	var def_unlocked := int(UserDB.get_dragon(uid).get("equip_slots", 1))
	print("    기본 해금 칸 수 = %d (자유칸만). 나머지는 연구소 '드래곤 강화'에서 해금." % def_unlocked)

func _eq(label: String, got, want) -> void:
	if got == want: return
	printerr("  ✗ %s: got=%s want=%s" % [label, str(got), str(want)]); _fails += 1

func _ok(label: String, cond: bool) -> void:
	if cond: return
	printerr("  ✗ %s" % label); _fails += 1

func _fail(msg: String) -> void:
	printerr("  ✗ %s" % msg); _fails += 1

func _done() -> void:
	if _fails == 0: print("\n[cave_equip] ALL PASS")
	else: printerr("\n[cave_equip] %d FAIL" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
