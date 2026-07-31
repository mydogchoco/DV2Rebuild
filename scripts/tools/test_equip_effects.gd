extends SceneTree
## 헤드리스 장비 조건부 효과 테스트 (§8 — logic 만, 화면 없이).
## 실행: godot --headless --path . --script res://scripts/tools/test_equip_effects.gd --quit-after 3
##
## 표 = data/equip_effects.json (build_equip_effects.py). 번역=EquipEffect · 실행=Battle.

const B := preload("res://scripts/systems/battle.gd")
const EE := preload("res://scripts/systems/equip_effect.gd")

var _fails := 0

func _init() -> void:
	var tbl: Dictionary = _json("res://data/equip_effects.json")
	var eq: Dictionary = _json("res://data/equipment.json")
	var cfg: Dictionary = _json("res://data/combat.json")

	# 0) 표 자체 — 장비 전량이 표에 있고, 유령 항목이 없어야 한다.
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

	# 1) 스탯 상수 — 다크닉스의 구슬(관통 +50) · 고대신룡의 금관(받는 관통 50 무시)
	var a := _mk("A", "fire", {"att": 100, "def": 50}, ["exclusive:다크닉스의 구슬"])
	EE.apply_battle([a], [], tbl, {})
	_eq("관통 +50", B._eff(a, "pure"), 50)
	var d := _mk("D", "fire", {"hp": 9999, "def": 50}, ["exclusive:고대신룡의 금관"])
	EE.apply_battle([d], [], tbl, {})
	_eq("받는 관통 감소 +50", B._eff(d, "depure"), 50)

	# 2) 아가레스의 투구 — 체력 -10% 대신 공/방 +30%
	var g := _mk("G", "fire", {"hp": 1000, "att": 100, "def": 100}, ["exclusive:아가레스의 투구"])
	EE.apply_battle([g], [], tbl, {})
	_eq("공격력 +30%", B._eff(g, "att"), 130)
	_eq("방어력 +30%", B._eff(g, "def"), 130)

	# 3) 속성 지정 피해 — 빙하고룡의 칼날(불 속성에게 +50%)은 불 상대에만 걸린다.
	var rng := RandomNumberGenerator.new()
	var base_fire := _duel(tbl, cfg, rng, [], "fire")
	var buff_fire := _duel(tbl, cfg, rng, ["exclusive:빙하고룡의 칼날"], "fire")
	var buff_aqua := _duel(tbl, cfg, rng, ["exclusive:빙하고룡의 칼날"], "aqua")
	var base_aqua := _duel(tbl, cfg, rng, [], "aqua")
	_true("불 상대에게 피해 증가 (%d → %d)" % [base_fire, buff_fire], buff_fire > base_fire)
	_eq("물 상대에겐 변화 없음", buff_aqua, base_aqua)

	# 4) 각성기 전용 배수 — 발로드의 갈기(각성기 피해량 +30%)는 평타를 건드리지 않는다.
	var n0 := _duel(tbl, cfg, rng, [], "fire")
	var n1 := _duel(tbl, cfg, rng, ["exclusive:발로드의 갈기"], "fire")
	_eq("평타는 그대로", n1, n0)
	var w0 := _awaken_dmg(tbl, cfg, rng, [])
	var w1 := _awaken_dmg(tbl, cfg, rng, ["exclusive:발로드의 갈기"])
	_true("각성기 피해 증가 (%d → %d)" % [w0, w1], w1 > w0)

	# 5) 1회 생존 — 레드와이번의 뿔 / 카이저 발록의 팔찌
	for key: String in ["exclusive:레드와이번의뿔", "special:balrog:카이저 발록의 팔찌"]:
		var s := _mk("S", "fire", {"hp": 100, "def": 0}, [key])
		EE.apply_battle([s], [], tbl, {})
		var res := B._apply_dmg(s, 9999)
		_true("%s — 죽지 않고 생존" % key, not bool(res["dead"]) and int(s["hp"]) == 1)

	# 6) 피해 상한 — 노웨마의 갈기(받는 피해 최대 체력 30% 제한)
	var cap := _mk("C", "fire", {"hp": 1000, "def": 0}, ["exclusive:노웨마의 갈기"])
	EE.apply_battle([cap], [], tbl, {})
	var r2 := B._apply_dmg(cap, 900)
	_eq("한 번에 최대 체력 30% 까지만", int(r2["dmg"]), 300)

	# 7) 조건부 — 설리반의 가면은 아군에 신성 속성이 있어야 걸린다.
	var lone := _mk("L", "fire", {"hp": 1000}, ["exclusive:설리반의 가면"])
	EE.apply_battle([lone], [], tbl, {})
	_eq("신성 아군 없으면 상한 없음", int(B._apply_dmg(lone, 900)["dmg"]), 900)
	var withholy := _mk("W", "fire", {"hp": 1000}, ["exclusive:설리반의 가면"])
	var holy := _mk("H", "holy", {"hp": 1000}, [])
	EE.apply_battle([withholy, holy], [], tbl, {})
	_eq("신성 아군 있으면 30% 상한", int(B._apply_dmg(withholy, 900)["dmg"]), 300)

	# 8) 미구현 항목은 아무 일도 하지 않는다(반쪽 발동 금지).
	var noop := _mk("N", "fire", {"hp": 1000, "att": 100}, ["exclusive:청룡의 여의주"])
	var fired: Array = EE.apply_battle([noop], [], tbl, {})
	_eq("컷 콘텐츠는 효과 0", (noop["effects"] as Array).size(), 0)
	_eq("발동 목록에도 없음", fired.size(), 0)
	_true("상태 문구가 이유를 알려 준다",
		EE.status_text("exclusive:청룡의 여의주", tbl).contains("오프라인"))

	# 9) 반응 — 백룡의 보주(회피 시 스킬 사용 횟수 1회 회복).
	var sdb: Dictionary = _json("res://data/skills.json")
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
		# ⚠️ 회피는 확률 상한(`combat.json` judge.prob_cap, 기본 70%)에 걸려 회피율 100 이어도
		#    매번 나지 않는다 → 회피가 실제로 날 때까지 굴린다.
		var foe := _mk("F", "fire", {"hp": 999, "att": 50, "accuracy": 0}, [])
		var rr := RandomNumberGenerator.new()
		var evaded := false
		for t in 60:
			rr.seed = 100 + t
			ev["hp"] = 999                      # 맞아 죽지 않게 되돌린다
			if bool(B.resolve_attack(foe, ev, rr, cfg, sdb).get("miss", false)):
				evaded = true
				break
		_true("회피가 발생했다", evaded)
		if evaded:
			_eq("회피로 사용 횟수 1회 회복", int((ev["skill_uses"] as Dictionary).get(sid, 0)), full)
		# 가득 찬 상태에서 더 회피해도 한도를 넘지 않는다.
		for t2 in 60:
			rr.seed = 500 + t2
			ev["hp"] = 999
			B.resolve_attack(foe, ev, rr, cfg, sdb)
		_true("한도를 넘지 않는다", int((ev["skill_uses"] as Dictionary).get(sid, 0)) <= full)

	# 10) 전투 유형(해골요새 6종) — 앞 조항은 **방어자 유형**, 뒤 조항은 **착용자 유형**.
	_test_atk_type(tbl, cfg)
	# 11) 소규모 훅 — 크리 순서 · 연속공격 · 동적 · 각성기 상한 · 대상 속성.
	_test_c_hooks(tbl, cfg, sdb)
	# 12) 각성스킬 수정자 — 장비가 각성스킬의 표를 고쳐서 쓴다.
	_test_awaken_mod(tbl, cfg)
	# 13) 마지막 묶음 — 사망 트리거 · 관통 분배 · 스킬 지정 · PvE 조항만 살린 것.
	_test_d_batch(tbl, cfg)
	# 14) 커스텀 드래곤(666 샛별 · 777 한울)의 전용 장비 — 위키 밖, 사용자 정의.
	_test_custom(tbl, cfg)

	print("=== %s ===" % ("PASS" if _fails == 0 else "FAIL %d건" % _fails))
	quit(0 if _fails == 0 else 1)


## D 묶음 — 사망 트리거 · 관통 공통분배 · 스킬 지정 피해 · 컷 조항이 섞인 것의 PvE 조항.
func _test_d_batch(tbl: Dictionary, cfg: Dictionary) -> void:
	var awt: Dictionary = _json("res://data/skill_awaken.json")
	var rng := RandomNumberGenerator.new()

	# 쿠르파의 푸른갑주 — 아군 **그림자**가 쓰러지면 5턴간 공격력 50%.
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

	# 레지아나의 빛나는 깃털 — 자신이 죽으면 아군 각성기 피해 +50%.
	var rg := _mk("RG", "shadow", {"hp": 100}, ["exclusive:레지아나의 빛나는 깃털"])
	var ally := _mk("AL", "fire", {"att": 100}, [])
	EE.apply_battle([rg, ally], [], tbl, {})
	_eq("죽기 전에는 그대로", B._awaken_dmg_mult(ally), 1.0)
	rg["alive"] = false
	B._aw_on_death(rg)
	_eq("사망 후 아군 각성기 +50%", B._awaken_dmg_mult(ally), 1.5)

	# 엔젤 드래곤의티아라 — 자기 관통 0, 나머지 아군에게 1/N 씩.
	var an := _mk("AN", "light", {"pure": 60}, ["exclusive:엔젤 드래곤의티아라"])
	var m1 := _mk("M1", "light", {"pure": 0}, [])
	var m2 := _mk("M2", "light", {"pure": 0}, [])
	EE.apply_battle([an, m1, m2], [], tbl, {})
	_eq("자기 관통은 0", B._eff(an, "pure"), 0)
	_eq("아군 1 에게 30", B._eff(m1, "pure"), 30)
	_eq("아군 2 에게 30", B._eff(m2, "pure"), 30)

	# 번개고룡의 팬던트 — [심판의 날개](21) 을 쓸 때만 피해 200% 증가.
	var bg := _mk("BG", "fire", {"att": 100}, ["exclusive:번개고룡의 팬던트"])
	var tg := _mk("TG", "fire", {"hp": 999999, "def": 10}, [])
	EE.apply_battle([bg], [tg], tbl, {})
	bg["_cast_skill_id"] = 21
	_eq("심판의 날개면 3배", int(B._deal_attack(bg, tg, 1000, true, rng, cfg, {})["damage"]), 3000)
	bg["_cast_skill_id"] = 13
	_eq("다른 스킬은 그대로", int(B._deal_attack(bg, tg, 1000, true, rng, cfg, {})["damage"]), 1000)

	# 진의 나무비늘 — 아군 땅속성 수만큼 각성기 +20%, 최대 60%.
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

	# 멜로우 드래곤의 부메랑 — 아군에 자신 말고 바람이 있으면 공격하지 않는다.
	var me := _mk("ME", "wind", {"att": 100}, ["exclusive:멜로우 드래곤의 부메랑"])
	var w2 := _mk("W2", "wind", {}, [])
	EE.apply_battle([me, w2], [], tbl, {})
	_true("바람 아군이 있으면 공격 안 함", B._has_flag(me, "no_attack"))
	var solo := _mk("SO", "wind", {"att": 100}, ["exclusive:멜로우 드래곤의 부메랑"])
	EE.apply_battle([solo, _mk("F2", "fire", {}, [])], [], tbl, {})
	_true("혼자면 정상 공격", not B._has_flag(solo, "no_attack"))

	# 워든의 부유검 — 디버프를 받는 동안에만 누적, 상한 1000.
	var wd := _mk("WD", "wind", {"att": 100}, ["exclusive:워든의 부유검"])
	var big := _mk("BG2", "wind", {"hp": 5000}, [])
	EE.apply_battle([wd], [big], tbl, {})
	B._aw_on_attack_done(wd, big, rng, 10)
	_eq("디버프가 없으면 누적 없음", B._eff(wd, "att"), 100)
	(wd["effects"] as Array).append({"kind": "stat", "stat": "def", "mode": "flat",
		"value": -5.0, "turns": 3, "src": "test"})          # 디버프 하나
	B._aw_on_attack_done(wd, big, rng, 10)
	_eq("디버프 중이면 타겟 최대체력 10% 누적", B._eff(wd, "att"), 600)
	for i in 10:
		B._aw_on_attack_done(wd, big, rng, 10)
	_eq("누적 상한 1000", B._eff(wd, "att"), 1100)

	# 다크프로스티의 무늬 — 탐험 골드 증가량만큼 공격력%.
	var dp := _mk("DP", "dark", {"att": 100, "explore_gold_pct": 50},
		["exclusive:다크프로스티의 무늬"])
	EE.apply_battle([dp], [], tbl, {})
	_eq("골드 +50% → 공격력 +50%", B._eff(dp, "att"), 150)

	# 익시아의 왕관 — [각성된 바람의 힘](20%) 세 조항 모두 +30%p ⇒ 50%
	var ix := _mk_aw("IX", "wind", 7, {"hp": 1000, "att": 100, "def": 100},
		["exclusive:익시아의 왕관"])
	# ⚠️ [각성된 바람의 힘]은 "바람속성 지역" 조건이 붙어 있다 — ctx 를 줘야 발동한다.
	var wctx := {"field_element": "wind"}
	_fire([ix], tbl, awt, wctx)
	_eq("각성된 바람의 힘 20% → 50%", B._eff(ix, "att"), 150)
	var ix0 := _mk_aw("IX0", "wind", 7, {"hp": 1000, "att": 100, "def": 100}, [])
	_fire([ix0], tbl, awt, wctx)
	_eq("장비 없으면 20% 그대로", B._eff(ix0, "att"), 120)

	# 피오드의 부서진 낙인 — 스킬 효과 레벨 +1
	var fd := _mk("FD", "fire", {}, ["special:fiod:피오드의 부서진 낙인"])
	EE.apply_battle([fd], [], tbl, {})
	_eq("스킬 효과 레벨 +1", B._skill_level_bonus(fd), 1)

	# 세로님의 전쟁보닛 — 팀버프 [흑풍] 이 **활성일 때만** 공격하지 않는다.
	# ⚠️ 팀버프는 파티 구성으로 정해지므로 전투 시작 전에 확정된다 → ctx 로 넘어온다.
	var se := _mk("SE", "wind", {"att": 100}, ["exclusive:세로님의 전쟁보닛"])
	EE.apply_battle([se], [], tbl, {"team_buffs": ["흑풍"]})
	_true("흑풍 활성 → 공격 안 함", B._has_flag(se, "no_attack"))
	var se2 := _mk("SE2", "wind", {"att": 100}, ["exclusive:세로님의 전쟁보닛"])
	EE.apply_battle([se2], [], tbl, {"team_buffs": ["창궁"]})
	_true("다른 팀버프면 정상 공격", not B._has_flag(se2, "no_attack"))
	var se3 := _mk("SE3", "wind", {"att": 100}, ["exclusive:세로님의 전쟁보닛"])
	EE.apply_battle([se3], [], tbl, {})
	_true("팀버프 정보가 없으면 발동 안 함", not B._has_flag(se3, "no_attack"))

	# 불나래의 불꽃구슬 — 장착 스킬 레벨 합 × 4 만큼 받는 대미지 정액 감소.
	var bn := _mk("BN", "fire", {"hp": 9999, "skill_level_sum": 8},
		["exclusive:불나래의 불꽃구슬"])
	EE.apply_battle([bn], [], tbl, {})
	_eq("레벨합 8 → 32 감소", int(B._apply_dmg(bn, 500)["dmg"]), 468)
	# [철갑 방패](11) 와 중첩된다 — 같은 축이라 정액 감소가 합산된다.
	(bn["effects"] as Array).append({"kind": "dmg_taken_flat", "value": 35.0,
		"turns": -1, "src": "skill:11"})
	_eq("철갑 방패와 중첩(32+35)", int(B._apply_dmg(bn, 500)["dmg"]), 433)
	var bn0 := _mk("BN0", "fire", {"hp": 9999, "skill_level_sum": 0},
		["exclusive:불나래의 불꽃구슬"])
	EE.apply_battle([bn0], [], tbl, {})
	_eq("스킬을 안 꼈으면 감소 0", int(B._apply_dmg(bn0, 500)["dmg"]), 500)

	# 디기의 금빛장식 — [약점 공략](71) 추가대미지 상한 150 → 250
	var dg := _mk_aw("DG", "fire", 71, {"att": 500, "def": 500}, ["exclusive:디기의 금빛장식"])
	var weak := _mk_aw("WK", "fire", 0, {"hp": 9999, "att": 1, "def": 1}, [])
	_fire([dg], tbl, awt)
	_eq("약점 공략 상한 250", B._aw_on_attack_bonus(dg, weak, rng, 0), 250)
	var dg0 := _mk_aw("DG0", "fire", 71, {"att": 500, "def": 500}, [])
	_fire([dg0], tbl, awt)
	_eq("장비 없으면 150", B._aw_on_attack_bonus(dg0, weak, rng, 0), 150)

	# 레이어스의 반석 방패 — [타오르는 바위] 계수가 정확히 두 배
	var ly := _mk_aw("LY", "earth", 92, {"att": 100}, ["exclusive:레이어스의 반석 방패"])
	ly["grade"] = 5.0
	_fire([ly], tbl, awt)
	_eq("주는 피해 등급×4%", B._dmg_deal_mult(ly), 1.2)
	_eq("받는 피해 등급×2%", B._dmg_taken_mult(ly), 1.1)

	# 카일루스의 신성 방패 — [신성 방패] 누적량 5% → 10%
	var ky := _mk_aw("KY", "holy", 65, {"hp": 1000, "def": 200}, ["exclusive:카일루스의 신성 방패"])
	_fire([ky], tbl, awt)
	ky["hp"] = 500
	B._aw_on_block(ky, rng)
	B._aw_on_attack_bonus(ky, weak, rng, 0)
	_eq("막기 1회 → 방어력 10% 회복", int(ky["hp"]), 520)

	# 실러캔스의 물빛 투구 — 기본 방어력 +50% + [격류] 효과 2배
	var sc2 := _mk_aw("SC2", "aqua", 13, {"hp": 1000, "def": 100}, ["exclusive:실러캔스의 물빛 투구"])
	sc2["grade"] = 5.0
	var mate2 := _mk_aw("MT2", "aqua", 0, {"hp": 1000}, [])
	_fire([sc2, mate2], tbl, awt)
	_eq("방어력 +50%", B._eff(sc2, "def"), 150)
	B._aw_refresh_dynamic([sc2, mate2], [])
	_eq("격류 아군 받는 피해 등급×1%(2배)", B._dmg_taken_mult(mate2), 0.95)


## A 묶음 — 장비가 각성스킬 표를 고치는 통로(`EquipEffect.awaken_mods` → `AwakenSkill._patched`).
##
## ⚠️ 순서: 수정자를 먼저 찍고 그 다음에 각성스킬을 심어야 한다. 뒤집으면 아무 일도 안 난다 —
##    그 실수를 잡으려고 아래 마지막 항목에서 순서를 뒤집어 본다.
func _test_awaken_mod(tbl: Dictionary, cfg: Dictionary) -> void:
	var awt: Dictionary = _json("res://data/skill_awaken.json")

	# 발레포르의 고리 — [공격의 날개](16) 데미지 20% 증가 → +20%p ⇒ 40%
	var a := _mk_aw("A", "wind", 16, {"att": 100}, ["exclusive:발레포르의 고리"])
	_fire([a], tbl, awt)
	_eq("공격의 날개 20% → 40%", B._dmg_deal_mult(a), 1.4)
	var plain := _mk_aw("P", "wind", 16, {"att": 100}, [])
	_fire([plain], tbl, awt)
	_eq("장비 없으면 20% 그대로", B._dmg_deal_mult(plain), 1.2)

	# 프로스티의 무늬 — [보호의 날개](39) 받는 피해 10% 감소 → 20% 감소
	var pr := _mk_aw("PR", "wind", 39, {"hp": 1000}, ["exclusive:프로스티의 무늬"])
	_fire([pr], tbl, awt)
	_eq("보호의 날개 10% → 20% 감소", B._dmg_taken_mult(pr), 0.8)

	# 루시퍼의 날개장식 — [매의 눈](32) 방어무시 25 → 100
	var lu := _mk_aw("LU", "wind", 32, {"att": 100}, ["exclusive:루시퍼의 날개장식"])
	_fire([lu], tbl, awt)
	_eq("매의 눈 25 → 100", B._eff(lu, "pure"), 100)

	# 금오드래곤의고대목걸이 — [삼족오의 후예](56) 7% → 14% (세 조항 모두)
	var gm := _mk_aw("GM", "light", 56, {"hp": 1000, "att": 100, "accuracy": 0},
		["exclusive:금오드래곤의고대목걸이"])
	_fire([gm], tbl, awt)
	_eq("삼족오 체력 2배", int(gm["hp_max"]), 1140)
	_eq("삼족오 공격력 2배", B._eff(gm, "att"), 114)
	_eq("삼족오 명중률 2배", B._eff(gm, "accuracy"), 14)

	# 헤네스의 지성의 왕관 — [자격을 갖춘 자](81) 5회 → 8회
	var he := _mk_aw("HE", "wind", 81, {"hp": 100}, ["exclusive:헤네스의 지성의 왕관"])
	_fire([he], tbl, awt)
	_eq("자격을 갖춘 자 5 → 8회", _react_left(he, "skill_cast"), 8)

	# 푸르푸르의 혼돈의 번개 — [절망의 번개](85) 3회 → 5회
	var pu := _mk_aw("PU", "wind", 85, {"hp": 100}, ["exclusive:푸르푸르의 혼돈의 번개"])
	_fire([pu], tbl, awt)
	_eq("절망의 번개 3 → 5회", _react_left(pu, "skill_cast"), 5)

	# 루키르의 바람의 날개 — [신뢰의 힘](63) 누적 대상이 자신 → 아군 전체
	var lk := _mk_aw("LK", "wind", 63, {"att": 100}, ["exclusive:루키르의 바람의 날개"])
	var mate := _mk_aw("MT", "wind", 0, {"att": 100}, [])
	_fire([lk, mate], tbl, awt)
	var foe := _mk_aw("F", "wind", 0, {"hp": 999999, "att": 1, "def": 10}, [])
	var rr := RandomNumberGenerator.new()
	B._aw_on_attack_done(lk, foe, rr)
	_eq("신뢰의 힘이 아군에게도", B._eff(mate, "att"), 110)

	# 프리스트의 빛나는 날개 — [순백의 빛](62) 명중 25 → 40, 대상에 아군 신성/빛 추가
	var pf := _mk_aw("PF", "fire", 62, {"accuracy": 0}, ["exclusive:프리스트의 빛나는 날개"])
	var holy := _mk_aw("HO", "holy", 0, {"accuracy": 0}, [])
	var dark := _mk_aw("DK", "dark", 0, {"accuracy": 0}, [])
	_fire([pf, holy, dark], tbl, awt)
	_eq("자신 명중 25 → 40", B._eff(pf, "accuracy"), 40)
	_eq("아군 신성에게도 적용", B._eff(holy, "accuracy"), 40)
	_eq("그 밖의 속성엔 미적용", B._eff(dark, "accuracy"), 0)

	# 샤마쉬의 흉갑 — [정의집행](86) 의 **추가대미지(관통)** 만 아군 전체로. 관통무시는 자신만.
	var sh := _mk_aw("SH", "wind", 86, {"att": 200, "def": 300}, ["exclusive:샤마쉬의 흉갑"])
	var sm := _mk_aw("SM", "wind", 0, {"att": 100, "def": 100}, [])
	_fire([sh, sm], tbl, awt)
	_eq("아군도 추가대미지(관통)", B._eff(sm, "pure"), 20)
	_eq("관통 무시는 자신만", B._eff(sm, "depure"), 0)

	# 말덱의 흡수의서 — 흡수 기준이 기본 → 최종(버프 포함) 능력치.
	# 🟦 사용자 확정: 각성스킬은 기본, 이 장비가 최종으로 올린다.
	var base_absorb := _absorb_att([])
	var eff_absorb := _absorb_att(["exclusive:말덱의 흡수의서"])
	_true("흡수 기준이 최종으로 (%d → %d)" % [base_absorb, eff_absorb], eff_absorb > base_absorb)

	# 크로우 드래곤의 해골투구 — 막기 성공 시 [복수의 까마귀](40) 횟수 회복(최대 4).
	var cr := _mk_aw("CR", "wind", 40, {"hp": 1000}, ["exclusive:크로우 드래곤의 해골투구"])
	_fire([cr], tbl, awt)
	_eq("복수의 까마귀 기본 2회", _react_left(cr, "hit_unguarded"), 2)
	var attacker := _mk_aw("AK", "wind", 0, {"att": 10}, [])
	B._aw_on_hit_unguarded(cr, attacker, rr)        # 1회 소모 → 1
	_eq("한 번 썼다", _react_left(cr, "hit_unguarded"), 1)
	for i in 6:
		B._aw_on_block(cr, rr)                       # 회복 — 상한 4 에서 멈춘다
	_eq("막기로 회복하되 최대 4", _react_left(cr, "hit_unguarded"), 4)

	# 샤크곤의 물안경 — [구드라의 가호](17) 탐험 아티팩트 확률 50 → 100(덮어쓰기)
	var e0 := {"awaken_no": 17, "equip_keys": []}
	EE.awaken_mods([e0], tbl)
	_eq("장비 없으면 50%", int(AwakenSkill.explore_bonus([e0], awt)["artifact_chance_pct"]), 50)
	var e1 := {"awaken_no": 17, "equip_keys": ["exclusive:샤크곤의 물안경"]}
	EE.awaken_mods([e1], tbl)
	_eq("장비 끼면 100%", int(AwakenSkill.explore_bonus([e1], awt)["artifact_chance_pct"]), 100)

	# 다른 드래곤의 각성스킬에는 걸리지 않는다.
	var wrong := _mk_aw("WR", "wind", 39, {"att": 100}, ["exclusive:발레포르의 고리"])
	_fire([wrong], tbl, awt)
	_eq("각성스킬 번호가 다르면 무효", B._dmg_deal_mult(wrong), 1.0)

	# ⚠️ 순서 회귀 — 각성스킬을 먼저 심으면 수정자가 안 먹는다(배선 사고 감지).
	var late := _mk_aw("LT", "wind", 16, {"att": 100}, ["exclusive:발레포르의 고리"])
	AwakenSkill.apply_battle([late], [], awt, {})
	EE.awaken_mods([late], tbl)
	_eq("순서를 뒤집으면 20% 그대로(= awaken_mods 를 먼저 불러야 한다)",
		B._dmg_deal_mult(late), 1.2)


## 각성스킬 번호를 가진 전투원.
func _mk_aw(nm: String, el: String, awaken_no: int, stats: Dictionary, keys: Array) -> Dictionary:
	var st := stats.duplicate()
	st["equip_keys"] = keys
	st["awaken_no"] = awaken_no
	return B.make_combatant(nm, "ally", el, st)


## 실제 배선 순서 그대로 — 수정자 먼저, 각성스킬 다음, 장비 효과 마지막.
func _fire(party: Array, tbl: Dictionary, awt: Dictionary, ctx: Dictionary = {}) -> void:
	EE.awaken_mods(party, tbl)
	AwakenSkill.apply_battle(party, [], awt, ctx)
	EE.apply_battle(party, [], tbl, ctx)


## 그 사건에 걸린 반응의 남은 횟수(첫 항목).
func _react_left(c: Dictionary, on: String) -> int:
	for e in (c.get("effects", []) as Array):
		var d := e as Dictionary
		if String(d.get("kind", "")) == B.REACT and String(d.get("on", "")) == on:
			return int(d.get("left", -1))
	return -999


## [흡수의 힘](100) 이 흡수해 온 공격력 증가분. 최고 등급 아군에게 버프를 미리 얹어 두어
## '기본'과 '최종'이 갈리게 만든다.
func _absorb_att(keys: Array) -> int:
	var tbl: Dictionary = _json("res://data/equip_effects.json")
	var awt: Dictionary = _json("res://data/skill_awaken.json")
	var me := _mk_aw("ME", "wind", 100, {"hp": 100, "att": 10, "def": 10}, keys)
	me["grade"] = 1.0
	var top := _mk_aw("TP", "wind", 0, {"hp": 1000, "att": 1000, "def": 100}, [])
	top["grade"] = 9.0
	# 버프 — 기본(1000)과 최종(2000)이 갈린다.
	(top["effects"] as Array).append({"kind": "stat", "stat": "att", "mode": "pct",
		"value": 100.0, "turns": -1, "src": "test"})
	_fire([me, top], tbl, awt)
	return B._eff(me, "att")


## C 묶음 — 크리 판정 순서 · 연속공격 · 동적 항목 · 각성기 상한 · 아군 속성 대상.
func _test_c_hooks(tbl: Dictionary, cfg: Dictionary, sdb: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()

	# 홀리의 빛나는 양뿔 — 크리티컬 공격은 상대의 회피를 무시한다.
	# 회피율을 최대(상한 70%)로 준 상대를 여러 번 때려, 크리인데 miss 인 경우가 **한 번도**
	# 없어야 한다(플래그가 없으면 회피가 먼저라 크리 여부와 무관하게 빗나간다).
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

	# 글라시아의 왕관 — 상대 회피율이 0 이면 반드시 크리(크리 확률 0 이어도).
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

	# 엔투라스의 불꽃 주먹 — 크리일 때만 방어력 절반 무시.
	var e0 := _crit_dmg(tbl, cfg, [])
	var e1 := _crit_dmg(tbl, cfg, ["exclusive:엔투라스의 불꽃 주먹"])
	_true("크리 피해 증가 (%d → %d)" % [e0, e1], e1 > e0)
	var n0 := _duel(tbl, cfg, rng, [], "wind")
	var n1 := _duel(tbl, cfg, rng, ["exclusive:엔투라스의 불꽃 주먹"], "wind")
	_eq("논크리 평타는 그대로", n1, n0)

	# 일란의 영예의관 — 연속공격만 +50%, 평타는 그대로.
	var d0 := _double_dmg(tbl, cfg, [])
	var d1 := _double_dmg(tbl, cfg, ["exclusive:일란의 영예의관"])
	_true("연속공격 피해 증가 (%d → %d)" % [d0, d1], d1 > d0)
	_eq("평타는 그대로", _duel(tbl, cfg, rng, ["exclusive:일란의 영예의관"], "wind"), n0)

	# 세크라포의 어깨보호대 — 연속공격 시 준 피해만큼 회복, 전투 중 3회 한정.
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

	# 완숙이의 후라이팬 — 체력 20% 이하일 때만 회복 + 증뎀.
	var w := _mk("W", "wind", {"hp": 1000, "att": 200, "cri": 0, "evd": 0, "blk": 0},
		["exclusive:완숙이의 후라이팬"])
	var wv := _mk("WV", "wind", {"hp": 999999, "att": 1, "def": 10, "evd": 0, "blk": 0}, [])
	EE.apply_battle([w], [wv], tbl, {})
	w["hp"] = 1000
	rng.seed = 1
	B.resolve_attack(w, wv, rng, cfg, {})
	_eq("체력이 넉넉하면 회복 없음", int(w["hp"]), 1000)
	w["hp"] = 100                                   # 10% — 조건 충족
	rng.seed = 1
	B.resolve_attack(w, wv, rng, cfg, {})
	_eq("체력 20% 이하면 최대체력 1% 회복", int(w["hp"]), 110)
	B._aw_refresh_dynamic([w], [wv])                # 라운드 경계에서 동적 증뎀이 켜진다
	_true("체력 20% 이하면 주는 피해 증가", B._dmg_deal_mult(w) > 1.0)
	w["hp"] = 1000
	B._aw_refresh_dynamic([w], [wv])
	_eq("체력이 회복되면 증뎀이 꺼진다", B._dmg_deal_mult(w), 1.0)

	# 오울드라의 어둠갑옷 — 아군 **전원**에게 1회씩 '모든 피해를 1로'.
	var o := _mk("O", "wind", {"hp": 1000}, ["exclusive:오울드라의 어둠갑옷"])
	var mate := _mk("M", "wind", {"hp": 1000}, [])
	EE.apply_battle([o, mate], [], tbl, {})
	for who in [o, mate]:
		_eq("보호막 1회 — 첫 피해는 1", int(B._apply_dmg(who, B._aw_fix_damage(who, 500))["dmg"]), 1)
		_eq("두 번째 피해는 정상", int(B._apply_dmg(who, B._aw_fix_damage(who, 500))["dmg"]), 500)

	# 미르의 별빛방울 — 상대 팀 현재 체력의 10% 를 공격력에 (최대 1000).
	var mi := _mk("MI", "wind", {"att": 100}, ["exclusive:미르의 별빛방울"])
	var foe1 := _mk("F1", "wind", {"hp": 4000}, [])
	EE.apply_battle([mi], [foe1], tbl, {})
	B._aw_refresh_dynamic([mi], [foe1])
	_eq("상대 체력 4000 → 공격력 +400", B._eff(mi, "att"), 500)
	foe1["hp"] = 40000                              # 4000 초과분은 상한 1000 에서 멈춘다
	B._aw_refresh_dynamic([mi], [foe1])
	_eq("상한 1000", B._eff(mi, "att"), 1100)

	# 타로스의 용암구슬 — **스킬 피해만** 크리 확률만큼 증가.
	var ta := _mk("TA", "wind", {"att": 100, "cri": 40}, ["exclusive:타로스의 용암구슬"])
	var tv := _mk("TV", "wind", {"hp": 999999, "def": 10}, [])
	EE.apply_battle([ta], [tv], tbl, {})
	var sk := int(B._deal_attack(ta, tv, 1000, true, rng, cfg, {})["damage"])
	var nm := int(B._deal_attack(ta, tv, 1000, false, rng, cfg, {})["damage"])
	_eq("스킬 피해 +40%", sk, 1400)
	_eq("평타는 그대로", nm, 1000)

	# 카이저 발록의 투구 / 피오드의 모래시계 — 타겟 체력 비례 추가 피해, 상한 300.
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

	# 피오드의 빛을 잃은 마석 — 각성기에 받는 대미지 1000 제한.
	var boss := _mk("BS", "wind", {"att": 100000, "def": 1}, [])
	var prot := _mk("PR", "wind", {"hp": 999999, "def": 1},
		["special:fiod:피오드의 빛을 잃은 마석"])
	EE.apply_battle([prot], [boss], tbl, {})
	rng.seed = 5
	_eq("각성기 피해 1000 제한",
		int((B.resolve_awaken(boss, [prot], rng, cfg)[0] as Dictionary)["damage"]), 1000)

	# 운디네 / 현무 — 아군 **물속성만** 대상.
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


## 커스텀 드래곤(위키 밖)의 전용 장비 2벌 — 조항 4개가 전부 기존 어휘로 옮겨졌는지.
func _test_custom(tbl: Dictionary, cfg: Dictionary, sdb: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()

	# ── 샛별의 날개장식(666) ────────────────────────────────────────────────
	# 1) 장착 스킬 레벨 합 × 4 만큼 받는 대미지 **정액** 감소(불나래와 같은 축).
	var sb := _mk("SB", "chaos", {"hp": 9999, "skill_level_sum": 9},
		["exclusive:샛별의 날개장식"])
	var mate := _mk("MT", "fire", {"hp": 9999, "att": 100}, [])
	EE.apply_battle([sb, mate], [], tbl, {})
	_eq("샛별 — 레벨합 9 → 36 감소", int(B._apply_dmg(sb, 500)["dmg"]), 464)
	# 2) [철갑 방패](11)와 중첩 — 출처가 다르면 정액 감소가 합산된다.
	(sb["effects"] as Array).append({"kind": "dmg_taken_flat", "value": 35.0,
		"turns": -1, "src": "skill:11"})
	_eq("샛별 — 철갑 방패와 중첩(36+35)", int(B._apply_dmg(sb, 500)["dmg"]), 429)
	# 3) 아군이 주는 데미지 30% 증가 — 착용자 본인도 아군에 든다.
	_eq("샛별 — 아군 피해량 +30%", B._dmg_deal_mult(mate), 1.3)
	_eq("샛별 — 자신도 +30%", B._dmg_deal_mult(sb), 1.3)
	var solo := _mk("SO", "fire", {"hp": 9999, "att": 100}, [])
	EE.apply_battle([solo], [], tbl, {})
	_eq("장비가 없으면 그대로", B._dmg_deal_mult(solo), 1.0)

	# ── 한울의 불꽃(777) ───────────────────────────────────────────────────
	# 1) 스킬 발동 횟수 +2 (라 솔라의 불꽃과 같은 조항 — 같은 값이 나와야 한다).
	var sid := 11
	var base := _mk("HB", "fire", {"att": 100, "skills": [{"id": sid, "level": 1}]}, [])
	var han := _mk("HN", "fire", {"att": 100, "skills": [{"id": sid, "level": 1}]},
		["exclusive:한울의 불꽃"])
	var sol := _mk("LS", "fire", {"att": 100, "skills": [{"id": sid, "level": 1}]},
		["exclusive:라 솔라의 불꽃"])
	EE.apply_battle([base], [], tbl, {})
	EE.apply_battle([han], [], tbl, {})
	EE.apply_battle([sol], [], tbl, {})
	var n_base := int((base["skill_uses"] as Dictionary).get(sid, 0))
	_eq("한울 — 스킬 발동 횟수 +2", int((han["skill_uses"] as Dictionary).get(sid, 0)), n_base + 2)
	_eq("한울 — 라 솔라의 불꽃과 같은 값",
		int((han["skill_uses"] as Dictionary).get(sid, 0)),
		int((sol["skill_uses"] as Dictionary).get(sid, 0)))
	# 2) 크리티컬 발동 시 상대의 현재 방어력 절반 무시 — **크리일 때만** 걸린다.
	var c0 := _crit_dmg(tbl, cfg, [])
	var c1 := _crit_dmg(tbl, cfg, ["exclusive:한울의 불꽃"])
	_true("한울 — 크리 피해 증가 (%d → %d)" % [c0, c1], c1 > c0)
	_eq("한울 — 엔투라스와 같은 값", c1, _crit_dmg(tbl, cfg, ["exclusive:엔투라스의 불꽃 주먹"]))
	_eq("한울 — 논크리 평타는 그대로",
		_duel(tbl, cfg, rng, ["exclusive:한울의 불꽃"], "wind"),
		_duel(tbl, cfg, rng, [], "wind"))


## 크리 확정 상태에서의 피해 1회(고정 시드).
func _crit_dmg(tbl: Dictionary, cfg: Dictionary, keys: Array) -> int:
	var rng := RandomNumberGenerator.new()
	var a := _mk("A", "wind", {"att": 200, "def": 50, "cri": 100, "evd": 0, "blk": 0}, keys)
	var d := _mk("D", "wind", {"hp": 999999, "att": 1, "def": 300, "cri": 0, "evd": 0, "blk": 0}, [])
	EE.apply_battle([a], [d], tbl, {})
	rng.seed = 4242
	var ev := B.resolve_attack(a, d, rng, cfg, {})
	return int(ev["damage"]) if bool(ev["crit"]) else -1


## 연속공격 2타의 피해 합(고정 시드).
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


## 해골요새 장비 — `dmg_deal_vs_type`(방어자 유형) + cond `self_type`(착용자 유형).
func _test_atk_type(tbl: Dictionary, cfg: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	# 앞 조항: 엘더 블랙퀸의 스태프 = 체방형(hd) 을 공격할 때만 +25%
	var base_hd := _duel_type(tbl, cfg, rng, [], "hd")
	var buff_hd := _duel_type(tbl, cfg, rng, ["special:skull:엘더 블랙퀸의 스태프"], "hd")
	var buff_atk := _duel_type(tbl, cfg, rng, ["special:skull:엘더 블랙퀸의 스태프"], "atk")
	var base_atk := _duel_type(tbl, cfg, rng, [], "atk")
	_true("체방형 상대에게 피해 증가 (%d → %d)" % [base_hd, buff_hd], buff_hd > base_hd)
	_eq("다른 유형 상대엔 변화 없음", buff_atk, base_atk)
	# ⚠️ 몬스터는 전투 유형이 없다(monsters.json 에 열 자체가 없다) → PvE 에선 안 걸린다.
	var mon := _duel_type(tbl, cfg, rng, ["special:skull:엘더 블랙퀸의 스태프"], "")
	_eq("유형 없는 상대(몬스터)엔 변화 없음", mon, _duel_type(tbl, cfg, rng, [], ""))

	# 뒤 조항: 착용자 유형이 맞을 때만 걸린다.
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

	# G스컬의 영혼불길 — 체공형(ha) 장착 시 체력·공격력 15%
	var soul := _mk_type("SO", "ha", {"hp": 1000, "att": 100}, ["special:skull:G스컬의 영혼불길"])
	EE.apply_battle([soul], [], tbl, {})
	_eq("영혼불길 — 체력 +15%", int(soul["hp_max"]), 1150)
	_eq("영혼불길 — 공격력 +15%", B._eff(soul, "att"), 115)

	# 엘더 블랙퀸의 목도리 — 체방형(hd) 장착 시 **스킬 피해만** 10% 감소(평타는 그대로).
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


## 전투 유형을 가진 전투원.
func _mk_type(nm: String, ty: String, stats: Dictionary, keys: Array) -> Dictionary:
	var st := stats.duplicate()
	st["equip_keys"] = keys
	st["atk_type"] = ty
	return B.make_combatant(nm, "ally", "wind", st)


## 공격 1회의 피해 — 방어자 **전투 유형**만 바꿔 가며 비교(속성은 같게 고정).
func _duel_type(tbl: Dictionary, cfg: Dictionary, rng: RandomNumberGenerator,
		keys: Array, def_type: String) -> int:
	var a := _mk_type("A", "atk", {"att": 200, "def": 50, "cri": 0, "evd": 0, "blk": 0}, keys)
	var d := _mk_type("D", def_type,
		{"hp": 999999, "att": 1, "def": 100, "cri": 0, "evd": 0, "blk": 0}, [])
	EE.apply_battle([a], [d], tbl, {})
	rng.seed = 4242
	return int(B.resolve_attack(a, d, rng, cfg, {})["damage"])


## 전투원 하나 만들기(장착 키 포함).
func _mk(nm: String, el: String, stats: Dictionary, keys: Array) -> Dictionary:
	var st := stats.duplicate()
	st["equip_keys"] = keys
	return B.make_combatant(nm, "ally", el, st)


## 공격 1회의 피해(고정 시드) — 방어자 속성만 바꿔 가며 비교한다.
func _duel(tbl: Dictionary, cfg: Dictionary, rng: RandomNumberGenerator,
		keys: Array, def_el: String) -> int:
	var a := _mk("A", "wind", {"att": 200, "def": 50, "cri": 0, "evd": 0, "blk": 0}, keys)
	var d := _mk("D", def_el, {"hp": 999999, "att": 1, "def": 100, "cri": 0, "evd": 0, "blk": 0}, [])
	EE.apply_battle([a], [d], tbl, {})
	rng.seed = 4242
	return int(B.resolve_attack(a, d, rng, cfg, {})["damage"])


## 각성기 1회의 피해(고정 시드).
func _awaken_dmg(tbl: Dictionary, cfg: Dictionary, rng: RandomNumberGenerator,
		keys: Array) -> int:
	var a := _mk("A", "wind", {"att": 200, "def": 50}, keys)
	var d := _mk("D", "wind", {"hp": 999999, "att": 1, "def": 100}, [])
	EE.apply_battle([a], [d], tbl, {})
	rng.seed = 777
	var evs := B.resolve_awaken(a, [d], rng, cfg)
	return int((evs[0] as Dictionary)["damage"])


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
