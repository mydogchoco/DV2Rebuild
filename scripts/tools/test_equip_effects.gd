extends SceneTree

const B := preload("res://scripts/systems/battle.gd")
const EE := preload("res://scripts/systems/equip_effect.gd")

var _fails := 0

func _init() -> void:
	var tbl: Dictionary = _json(_data_file("equip_effects.json"))
	var eq: Dictionary = _json(_data_file("equipment.json"))
	var cfg: Dictionary = _json(_data_file("combat.json"))

	var names: Array = []
	for x in (eq["exclusive"]["list"] as Array):
		names.append(String((x as Dictionary)["name"]))
	var miss := 0
	for n: String in names:
		if not (tbl["exclusive"] as Dictionary).has(n):
			miss += 1
			print("  ✗ 표에 없는 전용 장비: %s" % n)
	_eq("전용 장비 표 누락", miss, 0)
	_eq("전용 표 항목 수", (tbl["exclusive"] as Dictionary).size(), names.size())

	var a := _mk("A", "fire", {"att": 100, "def": 50}, ["exclusive:다크닉스의 구슬"])
	EE.apply_battle([a], [], tbl, {})
	_eq("관통 +50", B._eff(a, "pure"), 50)
	var d := _mk("D", "fire", {"hp": 9999, "def": 50}, ["exclusive:고대신룡의 금관"])
	EE.apply_battle([d], [], tbl, {})
	_eq("받는 관통 감소 +50", B._eff(d, "depure"), 50)

	var g := _mk("G", "fire", {"hp": 1000, "att": 100, "def": 100}, ["exclusive:아가레스의 투구"])
	EE.apply_battle([g], [], tbl, {})
	_eq("공격력 +30%", B._eff(g, "att"), 130)
	_eq("방어력 +30%", B._eff(g, "def"), 130)

	var rng := RandomNumberGenerator.new()
	var base_fire := _duel(tbl, cfg, rng, [], "fire")
	var buff_fire := _duel(tbl, cfg, rng, ["exclusive:빙하고룡의 칼날"], "fire")
	var buff_aqua := _duel(tbl, cfg, rng, ["exclusive:빙하고룡의 칼날"], "aqua")
	var base_aqua := _duel(tbl, cfg, rng, [], "aqua")
	_true("불 상대에게 피해 증가 (%d → %d)" % [base_fire, buff_fire], buff_fire > base_fire)
	_eq("물 상대에겐 변화 없음", buff_aqua, base_aqua)

	var n0 := _duel(tbl, cfg, rng, [], "fire")
	var n1 := _duel(tbl, cfg, rng, ["exclusive:발로드의 갈기"], "fire")
	_eq("평타는 그대로", n1, n0)
	var w0 := _awaken_dmg(tbl, cfg, rng, [])
	var w1 := _awaken_dmg(tbl, cfg, rng, ["exclusive:발로드의 갈기"])
	_true("각성기 피해 증가 (%d → %d)" % [w0, w1], w1 > w0)

	for key: String in ["exclusive:레드와이번의뿔", "special:balrog:카이저 발록의 팔찌"]:
		var s := _mk("S", "fire", {"hp": 100, "def": 0}, [key])
		EE.apply_battle([s], [], tbl, {})
		var res := B._apply_dmg(s, 9999)
		_true("%s — 죽지 않고 생존" % key, not bool(res["dead"]) and int(s["hp"]) == 1)

	var cap := _mk("C", "fire", {"hp": 1000, "def": 0}, ["exclusive:노웨마의 갈기"])
	EE.apply_battle([cap], [], tbl, {})
	var r2 := B._apply_dmg(cap, 900)
	_eq("한 번에 최대 체력 30% 까지만", int(r2["dmg"]), 300)

	var lone := _mk("L", "fire", {"hp": 1000}, ["exclusive:설리반의 가면"])
	EE.apply_battle([lone], [], tbl, {})
	_eq("신성 아군 없으면 상한 없음", int(B._apply_dmg(lone, 900)["dmg"]), 900)
	var withholy := _mk("W", "fire", {"hp": 1000}, ["exclusive:설리반의 가면"])
	var holy := _mk("H", "holy", {"hp": 1000}, [])
	EE.apply_battle([withholy, holy], [], tbl, {})
	_eq("신성 아군 있으면 30% 상한", int(B._apply_dmg(withholy, 900)["dmg"]), 300)

	var noop := _mk("N", "fire", {"hp": 1000, "att": 100}, ["exclusive:청룡의 여의주"])
	var fired: Array = EE.apply_battle([noop], [], tbl, {})
	_eq("컷 콘텐츠는 효과 0", (noop["effects"] as Array).size(), 0)
	_eq("발동 목록에도 없음", fired.size(), 0)
	_true("상태 문구가 이유를 알려 준다",
		EE.status_text("exclusive:청룡의 여의주", tbl).contains("오프라인"))

	var sdb: Dictionary = _json(_data_file("skills.json"))
	var sid := 0
	for k: String in sdb:
		if typeof(sdb[k]) == TYPE_DICTIONARY and bool((sdb[k] as Dictionary).get("active", true)):
			sid = int(k)
			break
	if sid > 0:
		var ev := _mk("EV", "fire", {"hp": 999, "def": 10, "evd": 100}, ["exclusive:백룡의 보주"])
		ev["skills"] = [{"id": sid, "level": 1}]
		B._init_combatant_skills(ev, sdb, cfg)
		EE.apply_battle([ev], [], tbl, {})
		var full := int((ev["skill_uses"] as Dictionary).get(sid, 0))
		_true("스킬 한도가 잡혔다 (%d)" % full, full > 0)
		B._use(ev, sid)
		_eq("한 번 썼다", int((ev["skill_uses"] as Dictionary).get(sid, 0)), full - 1)
		var foe := _mk("F", "fire", {"hp": 999, "att": 50, "accuracy": 0}, [])
		var rr := RandomNumberGenerator.new()
		var evaded := false
		for t in 60:
			rr.seed = 100 + t
			ev["hp"] = 999
			if bool(B.resolve_attack(foe, ev, rr, cfg, sdb).get("miss", false)):
				evaded = true
				break
		_true("회피가 발생했다", evaded)
		if evaded:
			_eq("회피로 사용 횟수 1회 회복", int((ev["skill_uses"] as Dictionary).get(sid, 0)), full)
		for t2 in 60:
			rr.seed = 500 + t2
			ev["hp"] = 999
			B.resolve_attack(foe, ev, rr, cfg, sdb)
		_true("한도를 넘지 않는다", int((ev["skill_uses"] as Dictionary).get(sid, 0)) <= full)

	_test_atk_type(tbl, cfg)
	_test_c_hooks(tbl, cfg, sdb)
	_test_awaken_mod(tbl, cfg)
	_test_d_batch(tbl, cfg)
	_test_custom(tbl, cfg, sdb)
	_test_static_display(tbl)

	print("=== %s ===" % ("PASS" if _fails == 0 else "FAIL %d건" % _fails))
	quit(0 if _fails == 0 else 1)

func _test_d_batch(tbl: Dictionary, cfg: Dictionary) -> void:
	var awt: Dictionary = _json(_data_file("skill_awaken.json"))
	var rng := RandomNumberGenerator.new()

	var ku := _mk("KU", "light", {"att": 100}, ["exclusive:쿠르파의 푸른갑주"])
	var sh := _mk("SH", "shadow", {"hp": 100}, [])
	EE.apply_battle([ku, sh], [], tbl, {})
	_eq("사망 전에는 그대로", B._eff(ku, "att"), 100)
	sh["alive"] = false
	B._aw_on_death(sh)
	_eq("그림자 아군 사망 → 공격력 +50%", B._eff(ku, "att"), 150)
	var ku2 := _mk("KU2", "light", {"att": 100}, ["exclusive:쿠르파의 푸른갑주"])
	var fi := _mk("FI", "fire", {"hp": 100}, [])
	EE.apply_battle([ku2, fi], [], tbl, {})
	fi["alive"] = false
	B._aw_on_death(fi)
	_eq("다른 속성 아군 사망은 무효", B._eff(ku2, "att"), 100)

	var rg := _mk("RG", "shadow", {"hp": 100}, ["exclusive:레지아나의 빛나는 깃털"])
	var ally := _mk("AL", "fire", {"att": 100}, [])
	EE.apply_battle([rg, ally], [], tbl, {})
	_eq("죽기 전에는 그대로", B._awaken_dmg_mult(ally), 1.0)
	rg["alive"] = false
	B._aw_on_death(rg)
	_eq("사망 후 아군 각성기 +50%", B._awaken_dmg_mult(ally), 1.5)

	var an := _mk("AN", "light", {"pure": 60}, ["exclusive:엔젤 드래곤의티아라"])
	var m1 := _mk("M1", "light", {"pure": 0}, [])
	var m2 := _mk("M2", "light", {"pure": 0}, [])
	EE.apply_battle([an, m1, m2], [], tbl, {})
	_eq("자기 관통은 0", B._eff(an, "pure"), 0)
	_eq("아군 1 에게 30", B._eff(m1, "pure"), 30)
	_eq("아군 2 에게 30", B._eff(m2, "pure"), 30)

	var bg := _mk("BG", "fire", {"att": 100}, ["exclusive:번개고룡의 팬던트"])
	var tg := _mk("TG", "fire", {"hp": 999999, "def": 10, "cri": 0, "evd": 0, "blk": 0}, [])
	EE.apply_battle([bg], [tg], tbl, {})
	bg["_cast_skill_id"] = 21
	_eq("심판의 날개면 3배", int(B._deal_attack(bg, tg, 1000, true, rng, cfg, {})["damage"]), 3000)
	bg["_cast_skill_id"] = 13
	_eq("다른 스킬은 그대로", int(B._deal_attack(bg, tg, 1000, true, rng, cfg, {})["damage"]), 1000)

	var jin := _mk("JN", "earth", {"att": 100}, ["exclusive:진의 나무비늘"])
	var e1 := _mk("E1", "earth", {}, [])
	EE.apply_battle([jin, e1], [], tbl, {})
	_eq("땅 2마리 → 각성기 +40%", B._awaken_dmg_mult(jin), 1.4)
	var jin2 := _mk("JN2", "earth", {"att": 100}, ["exclusive:진의 나무비늘"])
	var many := [jin2]
	for i in 5:
		many.append(_mk("E%d" % i, "earth", {}, []))
	EE.apply_battle(many, [], tbl, {})
	_eq("상한 60%", B._awaken_dmg_mult(jin2), 1.6)

	var me := _mk("ME", "wind", {"att": 100}, ["exclusive:멜로우 드래곤의 부메랑"])
	var w2 := _mk("W2", "wind", {}, [])
	EE.apply_battle([me, w2], [], tbl, {})
	_true("바람 아군이 있으면 공격 안 함", B._has_flag(me, "no_attack"))
	var solo := _mk("SO", "wind", {"att": 100}, ["exclusive:멜로우 드래곤의 부메랑"])
	EE.apply_battle([solo, _mk("F2", "fire", {}, [])], [], tbl, {})
	_true("혼자면 정상 공격", not B._has_flag(solo, "no_attack"))

	var wd := _mk("WD", "wind", {"att": 100}, ["exclusive:워든의 부유검"])
	var big := _mk("BG2", "wind", {"hp": 5000}, [])
	EE.apply_battle([wd], [big], tbl, {})
	B._aw_on_attack_done(wd, big, rng, 10)
	_eq("디버프가 없으면 누적 없음", B._eff(wd, "att"), 100)
	(wd["effects"] as Array).append({"kind": "stat", "stat": "def", "mode": "flat",
		"value": -5.0, "turns": 3, "src": "test"})
	B._aw_on_attack_done(wd, big, rng, 10)
	_eq("디버프 중이면 타겟 최대체력 10% 누적", B._eff(wd, "att"), 600)
	for i in 10:
		B._aw_on_attack_done(wd, big, rng, 10)
	_eq("누적 상한 1000", B._eff(wd, "att"), 1100)

	var dp := _mk("DP", "dark", {"att": 100, "explore_gold_pct": 50},
		["exclusive:다크프로스티의 무늬"])
	EE.apply_battle([dp], [], tbl, {})
	_eq("골드 +50% → 공격력 +50%", B._eff(dp, "att"), 150)

	var ix := _mk_aw("IX", "wind", 7, {"hp": 1000, "att": 100, "def": 100},
		["exclusive:익시아의 왕관"])
	var wctx := {"field_element": "wind"}
	_fire([ix], tbl, awt, wctx)
	_eq("각성된 바람의 힘 20% → 50%", B._eff(ix, "att"), 150)
	var ix0 := _mk_aw("IX0", "wind", 7, {"hp": 1000, "att": 100, "def": 100}, [])
	_fire([ix0], tbl, awt, wctx)
	_eq("장비 없으면 20% 그대로", B._eff(ix0, "att"), 120)

	var fd := _mk("FD", "fire", {}, ["special:fiod:피오드의 부서진 낙인"])
	EE.apply_battle([fd], [], tbl, {})
	_eq("스킬 효과 레벨 +1", B._skill_level_bonus(fd), 1)

	var se := _mk("SE", "wind", {"att": 100}, ["exclusive:세로님의 전쟁보닛"])
	EE.apply_battle([se], [], tbl, {"team_buffs": ["흑풍"]})
	_true("흑풍 활성 → 공격 안 함", B._has_flag(se, "no_attack"))
	var se2 := _mk("SE2", "wind", {"att": 100}, ["exclusive:세로님의 전쟁보닛"])
	EE.apply_battle([se2], [], tbl, {"team_buffs": ["창궁"]})
	_true("다른 팀버프면 정상 공격", not B._has_flag(se2, "no_attack"))
	var se3 := _mk("SE3", "wind", {"att": 100}, ["exclusive:세로님의 전쟁보닛"])
	EE.apply_battle([se3], [], tbl, {})
	_true("팀버프 정보가 없으면 발동 안 함", not B._has_flag(se3, "no_attack"))

	var bn := _mk("BN", "fire", {"hp": 9999, "skill_level_sum": 8},
		["exclusive:불나래의 불꽃구슬"])
	EE.apply_battle([bn], [], tbl, {})
	_eq("레벨합 8 → 32 감소", int(B._apply_dmg(bn, 500)["dmg"]), 468)
	(bn["effects"] as Array).append({"kind": "dmg_taken_flat", "value": 35.0,
		"turns": -1, "src": "skill:11"})
	_eq("철갑 방패와 중첩(32+35)", int(B._apply_dmg(bn, 500)["dmg"]), 433)
	var bn0 := _mk("BN0", "fire", {"hp": 9999, "skill_level_sum": 0},
		["exclusive:불나래의 불꽃구슬"])
	EE.apply_battle([bn0], [], tbl, {})
	_eq("스킬을 안 꼈으면 감소 0", int(B._apply_dmg(bn0, 500)["dmg"]), 500)

	var dg := _mk_aw("DG", "fire", 71, {"att": 500, "def": 500}, ["exclusive:디기의 금빛장식"])
	var weak := _mk_aw("WK", "fire", 0, {"hp": 9999, "att": 1, "def": 1}, [])
	_fire([dg], tbl, awt)
	_eq("약점 공략 상한 250", B._aw_on_attack_bonus(dg, weak, rng, 0), 250)
	var dg0 := _mk_aw("DG0", "fire", 71, {"att": 500, "def": 500}, [])
	_fire([dg0], tbl, awt)
	_eq("장비 없으면 150", B._aw_on_attack_bonus(dg0, weak, rng, 0), 150)

	var ly := _mk_aw("LY", "earth", 92, {"att": 100}, ["exclusive:레이어스의 반석 방패"])
	ly["grade"] = 5.0
	_fire([ly], tbl, awt)
	_eq("주는 피해 등급×4%", B._dmg_deal_mult(ly), 1.2)
	_eq("받는 피해 등급×2%", B._dmg_taken_mult(ly), 1.1)

	var ky := _mk_aw("KY", "holy", 65, {"hp": 1000, "def": 200}, ["exclusive:카일루스의 신성 방패"])
	_fire([ky], tbl, awt)
	ky["hp"] = 500
	B._aw_on_block(ky, rng)
	B._aw_on_attack_bonus(ky, weak, rng, 0)
	_eq("막기 1회 → 방어력 10% 회복", int(ky["hp"]), 520)

	var sc2 := _mk_aw("SC2", "aqua", 13, {"hp": 1000, "def": 100}, ["exclusive:실러캔스의 물빛 투구"])
	sc2["grade"] = 5.0
	var mate2 := _mk_aw("MT2", "aqua", 0, {"hp": 1000}, [])
	_fire([sc2, mate2], tbl, awt)
	_eq("방어력 +50%", B._eff(sc2, "def"), 150)
	B._aw_refresh_dynamic([sc2, mate2], [])
	_eq("격류 아군 받는 피해 등급×1%(2배)", B._dmg_taken_mult(mate2), 0.95)

func _test_awaken_mod(tbl: Dictionary, cfg: Dictionary) -> void:
	var awt: Dictionary = _json(_data_file("skill_awaken.json"))

	var a := _mk_aw("A", "wind", 16, {"att": 100}, ["exclusive:발레포르의 고리"])
	_fire([a], tbl, awt)
	_eq("공격의 날개 20% → 40%", B._dmg_deal_mult(a), 1.4)
	var plain := _mk_aw("P", "wind", 16, {"att": 100}, [])
	_fire([plain], tbl, awt)
	_eq("장비 없으면 20% 그대로", B._dmg_deal_mult(plain), 1.2)

	var pr := _mk_aw("PR", "wind", 39, {"hp": 1000}, ["exclusive:프로스티의 무늬"])
	_fire([pr], tbl, awt)
	_eq("보호의 날개 10% → 20% 감소", B._dmg_taken_mult(pr), 0.8)

	var lu := _mk_aw("LU", "wind", 32, {"att": 100}, ["exclusive:루시퍼의 날개장식"])
	_fire([lu], tbl, awt)
	_eq("매의 눈 25 → 100", B._eff(lu, "pure"), 100)

	var gm := _mk_aw("GM", "light", 56, {"hp": 1000, "att": 100, "accuracy": 0},
		["exclusive:금오드래곤의고대목걸이"])
	_fire([gm], tbl, awt)
	_eq("삼족오 체력 2배", int(gm["hp_max"]), 1140)
	_eq("삼족오 공격력 2배", B._eff(gm, "att"), 114)
	_eq("삼족오 명중률 2배", B._eff(gm, "accuracy"), 14)

	var he := _mk_aw("HE", "wind", 81, {"hp": 100}, ["exclusive:헤네스의 지성의 왕관"])
	_fire([he], tbl, awt)
	_eq("자격을 갖춘 자 5 → 8회", _react_left(he, "skill_cast"), 8)

	var pu := _mk_aw("PU", "wind", 85, {"hp": 100}, ["exclusive:푸르푸르의 혼돈의 번개"])
	_fire([pu], tbl, awt)
	_eq("절망의 번개 3 → 5회", _react_left(pu, "skill_cast"), 5)

	var lk := _mk_aw("LK", "wind", 63, {"att": 100}, ["exclusive:루키르의 바람의 날개"])
	var mate := _mk_aw("MT", "wind", 0, {"att": 100}, [])
	_fire([lk, mate], tbl, awt)
	var foe := _mk_aw("F", "wind", 0, {"hp": 999999, "att": 1, "def": 10}, [])
	var rr := RandomNumberGenerator.new()
	B._aw_on_attack_done(lk, foe, rr)
	_eq("신뢰의 힘이 아군에게도", B._eff(mate, "att"), 110)

	var pf := _mk_aw("PF", "fire", 62, {"accuracy": 0}, ["exclusive:프리스트의 빛나는 날개"])
	var holy := _mk_aw("HO", "holy", 0, {"accuracy": 0}, [])
	var dark := _mk_aw("DK", "dark", 0, {"accuracy": 0}, [])
	_fire([pf, holy, dark], tbl, awt)
	_eq("자신 명중 25 → 40", B._eff(pf, "accuracy"), 40)
	_eq("아군 신성에게도 적용", B._eff(holy, "accuracy"), 40)
	_eq("그 밖의 속성엔 미적용", B._eff(dark, "accuracy"), 0)

	var sh := _mk_aw("SH", "wind", 86, {"att": 200, "def": 300}, ["exclusive:샤마쉬의 흉갑"])
	var sm := _mk_aw("SM", "wind", 0, {"att": 100, "def": 100}, [])
	_fire([sh, sm], tbl, awt)
	_eq("아군도 추가대미지(관통)", B._eff(sm, "pure"), 20)
	_eq("관통 무시는 자신만", B._eff(sm, "depure"), 0)

	var base_absorb := _absorb_att([])
	var eff_absorb := _absorb_att(["exclusive:말덱의 흡수의서"])
	_true("흡수 기준이 최종으로 (%d → %d)" % [base_absorb, eff_absorb], eff_absorb > base_absorb)

	var cr := _mk_aw("CR", "wind", 40, {"hp": 1000}, ["exclusive:크로우 드래곤의 해골투구"])
	_fire([cr], tbl, awt)
	_eq("복수의 까마귀 기본 2회", _react_left(cr, "hit_unguarded"), 2)
	var attacker := _mk_aw("AK", "wind", 0, {"att": 10}, [])
	B._aw_on_hit_unguarded(cr, attacker, rr)
	_eq("한 번 썼다", _react_left(cr, "hit_unguarded"), 1)
	for i in 6:
		B._aw_on_block(cr, rr)
	_eq("막기로 회복하되 최대 4", _react_left(cr, "hit_unguarded"), 4)

	var e0 := {"awaken_no": 17, "equip_keys": []}
	EE.awaken_mods([e0], tbl)
	_eq("장비 없으면 50%", int(AwakenSkill.explore_bonus([e0], awt)["artifact_chance_pct"]), 50)
	var e1 := {"awaken_no": 17, "equip_keys": ["exclusive:샤크곤의 물안경"]}
	EE.awaken_mods([e1], tbl)
	_eq("장비 끼면 100%", int(AwakenSkill.explore_bonus([e1], awt)["artifact_chance_pct"]), 100)

	var wrong := _mk_aw("WR", "wind", 39, {"att": 100}, ["exclusive:발레포르의 고리"])
	_fire([wrong], tbl, awt)
	_eq("각성스킬 번호가 다르면 무효", B._dmg_deal_mult(wrong), 1.0)

	var late := _mk_aw("LT", "wind", 16, {"att": 100}, ["exclusive:발레포르의 고리"])
	AwakenSkill.apply_battle([late], [], awt, {})
	EE.awaken_mods([late], tbl)
	_eq("순서를 뒤집으면 20% 그대로(= awaken_mods 를 먼저 불러야 한다)",
		B._dmg_deal_mult(late), 1.2)

func _mk_aw(nm: String, el: String, awaken_no: int, stats: Dictionary, keys: Array) -> Dictionary:
	var st := stats.duplicate()
	st["equip_keys"] = keys
	st["awaken_no"] = awaken_no
	return B.make_combatant(nm, "ally", el, st)

func _fire(party: Array, tbl: Dictionary, awt: Dictionary, ctx: Dictionary = {}) -> void:
	EE.awaken_mods(party, tbl)
	AwakenSkill.apply_battle(party, [], awt, ctx)
	EE.apply_battle(party, [], tbl, ctx)

func _react_left(c: Dictionary, on: String) -> int:
	for e in (c.get("effects", []) as Array):
		var d := e as Dictionary
		if String(d.get("kind", "")) == B.REACT and String(d.get("on", "")) == on:
			return int(d.get("left", -1))
	return -999

func _absorb_att(keys: Array) -> int:
	var tbl: Dictionary = _json(_data_file("equip_effects.json"))
	var awt: Dictionary = _json(_data_file("skill_awaken.json"))
	var me := _mk_aw("ME", "wind", 100, {"hp": 100, "att": 10, "def": 10}, keys)
	me["grade"] = 1.0
	var top := _mk_aw("TP", "wind", 0, {"hp": 1000, "att": 1000, "def": 100}, [])
	top["grade"] = 9.0
	(top["effects"] as Array).append({"kind": "stat", "stat": "att", "mode": "pct",
		"value": 100.0, "turns": -1, "src": "test"})
	_fire([me, top], tbl, awt)
	return B._eff(me, "att")

func _test_c_hooks(tbl: Dictionary, cfg: Dictionary, sdb: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()

	var bad := 0
	var crits := 0
	for t in 200:
		var a := _mk("A", "wind", {"att": 100, "def": 10, "cri": 100},
			["exclusive:홀리의 빛나는양뿔"])
		var d := _mk("D", "wind", {"hp": 999999, "att": 1, "def": 10, "evd": 100}, [])
		EE.apply_battle([a], [d], tbl, {})
		rng.seed = 900 + t
		var ev := B.resolve_attack(a, d, rng, cfg, {})
		if bool(ev.get("crit", false)):
			crits += 1
			if bool(ev.get("miss", false)):
				bad += 1
	_true("크리가 실제로 났다 (%d/200)" % crits, crits > 0)
	_eq("크리 공격은 회피당하지 않는다", bad, 0)

	var g := _mk("G", "wind", {"att": 100, "cri": 0}, ["exclusive:글라시아의 왕관"])
	var noevd := _mk("N", "wind", {"hp": 999999, "att": 1, "def": 10, "evd": 0}, [])
	EE.apply_battle([g], [noevd], tbl, {})
	rng.seed = 11
	_true("회피율 0 상대에겐 확정 크리", bool(B.resolve_attack(g, noevd, rng, cfg, {})["crit"]))
	var g2 := _mk("G2", "wind", {"att": 100, "cri": 0}, ["exclusive:글라시아의 왕관"])
	var hasevd := _mk("H", "wind", {"hp": 999999, "att": 1, "def": 10, "evd": 30}, [])
	EE.apply_battle([g2], [hasevd], tbl, {})
	var anycrit := false
	for t2 in 30:
		rng.seed = 300 + t2
		hasevd["hp"] = 999999
		if bool(B.resolve_attack(g2, hasevd, rng, cfg, {}).get("crit", false)):
			anycrit = true
	_true("회피율이 있으면 확정 크리가 아니다", not anycrit)

	var e0 := _crit_dmg(tbl, cfg, [])
	var e1 := _crit_dmg(tbl, cfg, ["exclusive:엔투라스의 불꽃 주먹"])
	_true("크리 피해 증가 (%d → %d)" % [e0, e1], e1 > e0)
	var n0 := _duel(tbl, cfg, rng, [], "wind")
	var n1 := _duel(tbl, cfg, rng, ["exclusive:엔투라스의 불꽃 주먹"], "wind")
	_eq("논크리 평타는 그대로", n1, n0)

	var d0 := _double_dmg(tbl, cfg, [])
	var d1 := _double_dmg(tbl, cfg, ["exclusive:일란의 영예의관"])
	_true("연속공격 피해 증가 (%d → %d)" % [d0, d1], d1 > d0)
	_eq("평타는 그대로", _duel(tbl, cfg, rng, ["exclusive:일란의 영예의관"], "wind"), n0)

	var s := _mk("S", "wind", {"hp": 100000, "att": 300, "cri": 0, "evd": 0, "blk": 0},
		["exclusive:세크라포의 어깨보호대"])
	var sv := _mk("V", "wind", {"hp": 999999, "att": 1, "def": 10, "evd": 0, "blk": 0}, [])
	EE.apply_battle([s], [sv], tbl, {})
	s["hp"] = 1
	var healed := 0
	for t3 in 5:
		rng.seed = 700 + t3
		var before := int(s["hp"])
		B.resolve_double(s, sv, rng, cfg, {})
		if int(s["hp"]) > before:
			healed += 1
	_eq("연속공격 회복은 3회까지", healed, 3)

	var w := _mk("W", "wind", {"hp": 1000, "att": 200, "cri": 0, "evd": 0, "blk": 0},
		["exclusive:완숙이의 후라이팬"])
	var wv := _mk("WV", "wind", {"hp": 999999, "att": 1, "def": 10, "evd": 0, "blk": 0}, [])
	EE.apply_battle([w], [wv], tbl, {})
	w["hp"] = 1000
	rng.seed = 1
	B.resolve_attack(w, wv, rng, cfg, {})
	_eq("체력이 넉넉하면 회복 없음", int(w["hp"]), 1000)
	w["hp"] = 100
	rng.seed = 1
	B.resolve_attack(w, wv, rng, cfg, {})
	_eq("체력 20% 이하면 최대체력 1% 회복", int(w["hp"]), 110)
	B._aw_refresh_dynamic([w], [wv])
	_true("체력 20% 이하면 주는 피해 증가", B._dmg_deal_mult(w) > 1.0)
	w["hp"] = 1000
	B._aw_refresh_dynamic([w], [wv])
	_eq("체력이 회복되면 증뎀이 꺼진다", B._dmg_deal_mult(w), 1.0)

	var o := _mk("O", "wind", {"hp": 1000}, ["exclusive:오울드라의 어둠갑옷"])
	var mate := _mk("M", "wind", {"hp": 1000}, [])
	EE.apply_battle([o, mate], [], tbl, {})
	for who in [o, mate]:
		_eq("보호막 1회 — 첫 피해는 1", int(B._apply_dmg(who, B._aw_fix_damage(who, 500))["dmg"]), 1)
		_eq("두 번째 피해는 정상", int(B._apply_dmg(who, B._aw_fix_damage(who, 500))["dmg"]), 500)

	var mi := _mk("MI", "wind", {"att": 100}, ["exclusive:미르의 별빛방울"])
	var foe1 := _mk("F1", "wind", {"hp": 4000}, [])
	EE.apply_battle([mi], [foe1], tbl, {})
	B._aw_refresh_dynamic([mi], [foe1])
	_eq("상대 체력 4000 → 공격력 +400", B._eff(mi, "att"), 500)
	foe1["hp"] = 40000
	B._aw_refresh_dynamic([mi], [foe1])
	_eq("상한 1000", B._eff(mi, "att"), 1100)

	var ta := _mk("TA", "wind", {"att": 100, "cri": 40}, ["exclusive:타로스의 용암구슬"])
	var tv := _mk("TV", "wind", {"hp": 999999, "def": 10}, [])
	EE.apply_battle([ta], [tv], tbl, {})
	var sk := int(B._deal_attack(ta, tv, 1000, true, rng, cfg, {})["damage"])
	var nm := int(B._deal_attack(ta, tv, 1000, false, rng, cfg, {})["damage"])
	_eq("스킬 피해 +40%", sk, 1400)
	_eq("평타는 그대로", nm, 1000)

	for row in [["special:balrog:카이저 발록의 투구", 5000, 250],
			["special:fiod:피오드의 텅 빈 모래시계", 3000, 180]]:
		var key := String(row[0])
		var thp := int(row[1])
		var want := int(row[2])
		var at := _mk("AT", "wind", {"att": 100}, [key])
		var tg := _mk("TG", "wind", {"hp": thp, "def": 10}, [])
		EE.apply_battle([at], [tg], tbl, {})
		_eq("%s — 추가 피해" % key, B._aw_on_attack_bonus(at, tg, rng, 0), want)
	var cap := _mk("CP", "wind", {"att": 100}, ["special:balrog:카이저 발록의 투구"])
	var big := _mk("BG", "wind", {"hp": 100000, "def": 10}, [])
	EE.apply_battle([cap], [big], tbl, {})
	_eq("추가 피해 상한 300", B._aw_on_attack_bonus(cap, big, rng, 0), 300)

	var boss := _mk("BS", "wind", {"att": 100000, "def": 1}, [])
	var prot := _mk("PR", "wind", {"hp": 999999, "def": 1},
		["special:fiod:피오드의 빛을 잃은 마석"])
	EE.apply_battle([prot], [boss], tbl, {})
	rng.seed = 5
	_eq("각성기 피해 1000 제한",
		_awaken_total(B.resolve_awaken(boss, [prot], rng, cfg)), 1000)

	var un := _mk("UN", "fire", {"hp": 1000, "blk": 20}, ["exclusive:운디네의 물방울"])
	var aqua := _mk("AQ", "aqua", {"hp": 1000}, [])
	var fire := _mk("FI", "fire", {"hp": 1000}, [])
	EE.apply_battle([un, aqua, fire], [], tbl, {})
	_eq("물속성 아군 체력 +20%", int(aqua["hp_max"]), 1200)
	_eq("다른 속성은 그대로", int(fire["hp_max"]), 1000)
	var hy := _mk("HY", "fire", {"hp": 1000}, ["exclusive:현무드래곤의동방갑옷"])
	var aqua2 := _mk("AQ2", "aqua", {"hp": 1000}, [])
	var fire2 := _mk("FI2", "fire", {"hp": 1000}, [])
	EE.apply_battle([hy, aqua2, fire2], [], tbl, {})
	_eq("물속성 아군 피해량 +10%", B._dmg_deal_mult(aqua2), 1.1)
	_eq("다른 속성은 그대로", B._dmg_deal_mult(fire2), 1.0)

func _test_custom(tbl: Dictionary, cfg: Dictionary, sdb: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()

	var sb := _mk("SB", "chaos", {"hp": 9999, "evd": 0, "skill_level_sum": 9},
		["exclusive:샛별의 날개장식"])
	var mate := _mk("MT", "fire", {"hp": 9999, "att": 100}, [])
	EE.apply_battle([sb, mate], [], tbl, {})
	_eq("샛별 — 회피율 +33%p", B._eff(sb, "evd"), 33)
	_eq("샛별 — 레벨합 9 → 36 감소", int(B._apply_dmg(sb, 500)["dmg"]), 464)
	(sb["effects"] as Array).append({"kind": "dmg_taken_flat", "value": 35.0,
		"turns": -1, "src": "skill:11"})
	_eq("샛별 — 철갑 방패와 중첩(36+35)", int(B._apply_dmg(sb, 500)["dmg"]), 429)
	_eq("샛별 — 아군 피해량 +30%", B._dmg_deal_mult(mate), 1.3)
	_eq("샛별 — 자신도 +30%", B._dmg_deal_mult(sb), 1.3)
	var solo := _mk("SO", "fire", {"hp": 9999, "att": 100}, [])
	EE.apply_battle([solo], [], tbl, {})
	_eq("장비가 없으면 그대로", B._dmg_deal_mult(solo), 1.0)

	var hc := _mk("HC", "wind", {"cri": 12, "evd": 7}, ["exclusive:한울의 불꽃"])
	EE.apply_battle([hc], [], tbl, {})
	_eq("한울 — 크리티컬 확률 +75%p", B._eff(hc, "cri"), 87)
	_eq("한울 — 회피율 +25%p", B._eff(hc, "evd"), 32)
	var sid := 0
	for k: String in sdb:
		if typeof(sdb[k]) == TYPE_DICTIONARY and bool((sdb[k] as Dictionary).get("active", true)):
			sid = int(k)
			break
	var uses: Array = []
	for keys: Array in [[], ["exclusive:한울의 불꽃"], ["exclusive:라 솔라의 불꽃"]]:
		var c := _mk("HU", "fire", {"att": 100}, keys)
		c["skills"] = [{"id": sid, "level": 1}]
		EE.apply_battle([c], [], tbl, {})
		B._init_combatant_skills(c, sdb, cfg)
		uses.append(int((c["skill_uses"] as Dictionary).get(sid, 0)))
	_true("스킬 한도가 잡혔다 (%d)" % int(uses[0]), sid > 0 and int(uses[0]) > 0)
	_eq("한울 — 스킬 발동 횟수 +2", int(uses[1]), int(uses[0]) + 2)
	_eq("한울 — 라 솔라의 불꽃과 같은 값", int(uses[1]), int(uses[2]))
	var c0 := _crit_dmg(tbl, cfg, [])
	var c1 := _crit_dmg(tbl, cfg, ["exclusive:한울의 불꽃"])
	_true("한울 — 크리 피해 증가 (%d → %d)" % [c0, c1], c1 > c0)
	_eq("한울 — 엔투라스와 같은 값", c1, _crit_dmg(tbl, cfg, ["exclusive:엔투라스의 불꽃 주먹"]))
	_eq("한울 — 논크리 평타는 그대로",
		_forced_noncrit_dmg(tbl, cfg, ["exclusive:한울의 불꽃"]),
		_forced_noncrit_dmg(tbl, cfg, []))

func _crit_dmg(tbl: Dictionary, cfg: Dictionary, keys: Array) -> int:
	var rng := RandomNumberGenerator.new()
	var a := _mk("A", "wind", {"att": 200, "def": 50, "cri": 100, "evd": 0, "blk": 0}, keys)
	var d := _mk("D", "wind", {"hp": 999999, "att": 1, "def": 300, "cri": 0, "evd": 0, "blk": 0}, [])
	EE.apply_battle([a], [d], tbl, {})
	rng.seed = 4242
	var ev := B.resolve_attack(a, d, rng, cfg, {})
	return int(ev["damage"]) if bool(ev["crit"]) else -1

func _forced_noncrit_dmg(tbl: Dictionary, cfg: Dictionary, keys: Array) -> int:
	var rng := RandomNumberGenerator.new()
	var a := _mk("A", "wind", {"att": 200, "def": 50, "cri": 0, "evd": 0, "blk": 0}, keys)
	var d := _mk("D", "wind", {"hp": 999999, "att": 1, "def": 300, "cri": 0, "evd": 0, "blk": 0}, [])
	EE.apply_battle([a], [d], tbl, {})
	rng.seed = 4242
	return B._hit_damage(a, d, false, false, rng, cfg)

func _double_dmg(tbl: Dictionary, cfg: Dictionary, keys: Array) -> int:
	var rng := RandomNumberGenerator.new()
	var a := _mk("A", "wind", {"att": 200, "def": 50, "cri": 0, "evd": 0, "blk": 0}, keys)
	var d := _mk("D", "wind", {"hp": 999999, "att": 1, "def": 100, "cri": 0, "evd": 0, "blk": 0}, [])
	EE.apply_battle([a], [d], tbl, {})
	rng.seed = 4242
	var total := 0
	for e in B.resolve_double(a, d, rng, cfg, {}):
		total += int((e as Dictionary)["damage"])
	return total

func _test_atk_type(tbl: Dictionary, cfg: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	var base_hd := _duel_type(tbl, cfg, rng, [], "hd")
	var buff_hd := _duel_type(tbl, cfg, rng, ["special:skull:엘더 블랙퀸의 스태프"], "hd")
	var buff_atk := _duel_type(tbl, cfg, rng, ["special:skull:엘더 블랙퀸의 스태프"], "atk")
	var base_atk := _duel_type(tbl, cfg, rng, [], "atk")
	_true("체방형 상대에게 피해 증가 (%d → %d)" % [base_hd, buff_hd], buff_hd > base_hd)
	_eq("다른 유형 상대엔 변화 없음", buff_atk, base_atk)
	var mon := _duel_type(tbl, cfg, rng, ["special:skull:엘더 블랙퀸의 스태프"], "")
	_eq("유형 없는 상대(몬스터)엔 변화 없음", mon, _duel_type(tbl, cfg, rng, [], ""))

	for row in [
		["special:skull:엘더 블랙퀸의 스태프", "def", "evd", 10],
		["special:skull:G스컬의 붉은장갑", "atk", "cri_pow", 100],
	]:
		var key := String(row[0])
		var need := String(row[1])
		var stat := String(row[2])
		var want := int(row[3])
		var ok := _mk_type("OK", need, {"evd": 0, "cri_pow": 0}, [key])
		EE.apply_battle([ok], [], tbl, {})
		_eq("%s — %s형이 장착: %s +%d" % [key, need, stat, want], B._eff(ok, stat), want)
		var no := _mk_type("NO", "hp", {"evd": 0, "cri_pow": 0}, [key])
		EE.apply_battle([no], [], tbl, {})
		_eq("%s — 다른 유형이면 무효" % key, B._eff(no, stat), 0)

	var soul := _mk_type("SO", "ha", {"hp": 1000, "att": 100}, ["special:skull:G스컬의 영혼불길"])
	EE.apply_battle([soul], [], tbl, {})
	_eq("영혼불길 — 체력 +15%", int(soul["hp_max"]), 1150)
	_eq("영혼불길 — 공격력 +15%", B._eff(soul, "att"), 115)

	var sc := _mk_type("SC", "hd", {"hp": 100000, "def": 0}, ["special:skull:엘더 블랙퀸의 목도리"])
	EE.apply_battle([sc], [], tbl, {})
	var foe := _mk_type("F", "atk", {"att": 100}, [])
	var plain := _mk_type("PL", "hd", {"hp": 100000, "def": 0}, [])
	var d_skill := int(B._deal_attack(foe, sc, 1000, true, rng, cfg, {})["damage"])
	var d_skill0 := int(B._deal_attack(foe, plain, 1000, true, rng, cfg, {})["damage"])
	var d_norm := int(B._deal_attack(foe, sc, 1000, false, rng, cfg, {})["damage"])
	var d_norm0 := int(B._deal_attack(foe, plain, 1000, false, rng, cfg, {})["damage"])
	_true("스킬 피해 감소 (%d → %d)" % [d_skill0, d_skill], d_skill < d_skill0)
	_eq("평타 피해는 그대로", d_norm, d_norm0)

func _mk_type(nm: String, ty: String, stats: Dictionary, keys: Array) -> Dictionary:
	var st := stats.duplicate()
	st["equip_keys"] = keys
	st["atk_type"] = ty
	return B.make_combatant(nm, "ally", "wind", st)

func _duel_type(tbl: Dictionary, cfg: Dictionary, rng: RandomNumberGenerator,
		keys: Array, def_type: String) -> int:
	var a := _mk_type("A", "atk", {"att": 200, "def": 50, "cri": 0, "evd": 0, "blk": 0}, keys)
	var d := _mk_type("D", def_type,
		{"hp": 999999, "att": 1, "def": 100, "cri": 0, "evd": 0, "blk": 0}, [])
	EE.apply_battle([a], [d], tbl, {})
	rng.seed = 4242
	return int(B.resolve_attack(a, d, rng, cfg, {})["damage"])

func _mk(nm: String, el: String, stats: Dictionary, keys: Array) -> Dictionary:
	var st := stats.duplicate()
	st["equip_keys"] = keys
	return B.make_combatant(nm, "ally", el, st)

func _duel(tbl: Dictionary, cfg: Dictionary, rng: RandomNumberGenerator,
		keys: Array, def_el: String) -> int:
	var a := _mk("A", "wind", {"att": 200, "def": 50, "cri": 0, "evd": 0, "blk": 0}, keys)
	var d := _mk("D", def_el, {"hp": 999999, "att": 1, "def": 100, "cri": 0, "evd": 0, "blk": 0}, [])
	EE.apply_battle([a], [d], tbl, {})
	rng.seed = 4242
	return int(B.resolve_attack(a, d, rng, cfg, {})["damage"])

func _awaken_dmg(tbl: Dictionary, cfg: Dictionary, rng: RandomNumberGenerator,
		keys: Array) -> int:
	var a := _mk("A", "wind", {"att": 200, "def": 50}, keys)
	var d := _mk("D", "wind", {"hp": 999999, "att": 1, "def": 100}, [])
	EE.apply_battle([a], [d], tbl, {})
	rng.seed = 777
	return _awaken_total(B.resolve_awaken(a, [d], rng, cfg))

func _awaken_total(evs: Array) -> int:
	var total := 0
	for e in evs:
		total += int((e as Dictionary).get("damage", 0))
	return total

func _test_static_display(tbl: Dictionary) -> void:
	var eqf := {"slots": [{"key": "exclusive:한울의 불꽃"}]}
	var shown := EE.apply_static({"cri": 25, "evd": 10, "hp": 1000}, eqf, tbl)
	_eq("상태창 크리 = 25 + 75%p", int(shown["cri"]), 100)
	_eq("상태창 회피 = 10 + 25%p", int(shown["evd"]), 35)
	_eq("건드리지 않는 스탯은 그대로", int(shown["hp"]), 1000)
	var c := _mk("DS", "fire", {"cri": 25, "evd": 10}, ["exclusive:한울의 불꽃"])
	EE.apply_battle([c], [], tbl, {})
	_eq("전투 값과 일치(크리)", B._eff(c, "cri"), int(shown["cri"]))
	_eq("전투 값과 일치(회피)", B._eff(c, "evd"), int(shown["evd"]))

	var ag := {"slots": [{"key": "exclusive:아가레스의 투구"}]}
	var s2 := EE.apply_static({"hp": 1000, "att": 100, "def": 100}, ag, tbl)
	_eq("체력 -10%", int(s2["hp"]), 900)
	_eq("공격력 +30%", int(s2["att"]), 130)

	_true("조건부 장비는 표시 몫 없음",
		EE.static_stats({"slots": [{"key": "exclusive:설리반의 가면"}]}, tbl).is_empty())
	_true("미구현 장비는 표시 몫 없음",
		EE.static_stats({"slots": [{"key": "exclusive:청룡의 여의주"}]}, tbl).is_empty())
	_true("장비가 없으면 아무 일도 없음", EE.static_stats({}, tbl).is_empty())

func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text()) as Dictionary

func _eq(label: String, got, want) -> void:
	if got == want:
		return
	print("  ✗ %s: %s (기대 %s)" % [label, got, want])
	_fails += 1

func _true(label: String, ok: bool) -> void:
	if ok:
		return
	print("  ✗ %s" % label)
	_fails += 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
