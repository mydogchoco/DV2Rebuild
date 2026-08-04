extends SceneTree
## 헤드리스 Battle 단위 테스트 (§10 — logic은 화면 없이 검증).
## 실행: godot --headless --path <proj> --script res://scripts/tools/test_battle.gd

func _init() -> void:
	var fails := 0
	var cfg := _load("res://data/combat.json")
	var sdb := _load("res://data/skills.json")
	var stages := _load("res://data/stages.json")

	# 1) 속성 상성 배수(§K-3, §B)
	fails += _eqf("aqua>fire", Battle.element_mult("aqua", "fire", cfg), 1.25)
	fails += _eqf("fire<aqua", Battle.element_mult("fire", "aqua", cfg), 0.85)
	fails += _eqf("aqua~wind", Battle.element_mult("aqua", "wind", cfg), 1.0)
	fails += _eqf("shadow att", Battle.element_mult("shadow", "fire", cfg), 1.0)
	fails += _eqf("shadow def", Battle.element_mult("fire", "shadow", cfg), 1.0)
	fails += _eqf("holy>chaos", Battle.element_mult("holy", "chaos", cfg), 1.25)
	fails += _eqf("chaos>holy", Battle.element_mult("chaos", "holy", cfg), 1.25)
	fails += _eqf("holy~shadow", Battle.element_mult("holy", "shadow", cfg), 1.0)
	fails += _eqf("light<fire", Battle.element_mult("light", "fire", cfg), 0.85)
	fails += _eqf("light>dark", Battle.element_mult("light", "dark", cfg), 1.25)
	fails += _eqf("dark>aqua", Battle.element_mult("dark", "aqua", cfg), 1.25)
	fails += _eqf("dark~holy", Battle.element_mult("dark", "holy", cfg), 1.0)   # 문헌상 dark는 holy에 무상성

	# 1b) 영웅 난이도 스탯 배율 — 원작 영상 실측: 체력×3, 공격/방어×1.5.
	var variant_rules: Dictionary = stages.get("_variant_rules", {})
	var hero_mult := Battle.hero_stat_multipliers({}, variant_rules)
	fails += _eqf("hero hp x3", float(hero_mult["hp"]), 3.0)
	fails += _eqf("hero att x1.5", float(hero_mult["att"]), 1.5)
	fails += _eqf("hero def x1.5", float(hero_mult["def"]), 1.5)
	var black_island: Dictionary = (stages.get("stages", {}) as Dictionary).get("24", {})
	var hero_override := Battle.hero_stat_multipliers(black_island, variant_rules)
	fails += _eqf("hero stage scalar hp override", float(hero_override["hp"]), 1.0)
	fails += _eqf("hero stage scalar att override", float(hero_override["att"]), 1.0)
	fails += _eqf("hero stage scalar def override", float(hero_override["def"]), 1.0)

	# 2) 데미지식(§K-2): 원작 영상 실측에 맞춘 공격×방어 포화 감쇠.
	fails += _eq("dmg 100v100 anchor", Battle.damage(100, 100, 0.0, 1.0, 1.0, 1.0, cfg), 47)
	fails += _eq("dmg 100v50", Battle.damage(100, 50, 0.0, 1.0, 1.0, 1.0, cfg), 64)
	fails += _eq("dmg crit", Battle.damage(100, 50, 0.0, 1.0, 1.5, 1.0, cfg), 96)
	fails += _eq("dmg elem", Battle.damage(100, 50, 0.0, 1.25, 1.0, 1.0, cfg), 80)
	fails += _eq("dmg pen", Battle.damage(100, 50, 0.5, 1.0, 1.0, 1.0, cfg), 77)
	fails += _eq("dmg def0", Battle.damage(100, 0, 0.0, 1.0, 1.0, 1.0, cfg), 94)
	var low_ratio := Battle.damage(100, 50, 0.0, 1.0, 1.0, 1.0, cfg)
	var high_ratio := Battle.damage(1000, 500, 0.0, 1.0, 1.0, 1.0, cfg)
	var scale_ratio := float(high_ratio) / float(maxi(1, low_ratio))
	fails += _eq("same ratio grows sublinearly", scale_ratio > 2.0 and scale_ratio < 3.0, true)
	fails += _eq("measured 214v117", Battle.damage(214, 117, 0.0, 1.0, 1.0, 1.0, cfg), 93)
	fails += _eq("measured 723v91", Battle.damage(723, 91, 0.0, 1.0, 1.0, 1.0, cfg), 360)
	fails += _eq("def 117 to 126 delta under 10",
		Battle.damage(214, 117, 0.0, 1.0, 1.0, 1.0, cfg) -
		Battle.damage(214, 126, 0.0, 1.0, 1.0, 1.0, cfg) < 10, true)
	fails += _eq("1300 atk over 864 def exceeds old sub-100", Battle.damage(1300, 864, 0.0, 1.0, 1.0, 1.0, cfg) > 100, true)
	fails += _eq("dmg min1", Battle.damage(1, 9999, 0.0, 0.85, 1.0, 0.95, cfg), 1)       # 0 미만 → 1

	# 3) 타겟팅(§K-6): (hp_max/4)+def 최대
	var A := _dummy(400, 10)   # 110
	var B := _dummy(200, 100)  # 150
	var C := _dummy(800, 0)    # 200
	fails += _eq("target max", Battle.pick_target([A, B, C], cfg)["name"], C["name"])
	C["alive"] = false
	fails += _eq("target skip dead", Battle.pick_target([A, B, C], cfg)["name"], B["name"])

	# 3b) 더블공격: 회피0/방어0/크리0 → 정확히 2타, 둘 다 명중, 합 = 감소량(공유 판정)
	var datk := Battle.make_combatant("ATK", "ally", "fire", {"hp": 1, "att": 100, "def": 1, "cri": 0, "evd": 0, "blk": 0})
	var ddef := Battle.make_combatant("DEF", "enemy", "wind", {"hp": 100000, "att": 1, "def": 50, "cri": 0, "evd": 0, "blk": 0})
	var dev := Battle.resolve_double(datk, ddef, _rng(5), cfg)
	fails += _eq("double 2hits", dev.size(), 2)
	fails += _eq("double h0 type", dev[0]["type"], "double")
	fails += _eq("double h0 nomiss", dev[0]["miss"], false)
	fails += _eq("double h1 nomiss", dev[1]["miss"], false)
	fails += _eq("double sum=loss", int(dev[0]["damage"]) + int(dev[1]["damage"]), 100000 - int(ddef["hp"]))

	# 3b-1) 피의 갈증(14): 연속공격에서도 행동당 1회, 실제 회복량을 이벤트에 기록한다.
	var ls := Battle.make_combatant("LS", "ally", "fire",
		{"hp": 2000, "att": 100, "def": 1, "cri": 0, "evd": 0, "blk": 0})
	ls["hp"] = 1000
	ls["effects"].append({"kind": "lifesteal", "pct": 10, "turns": 2, "source": 14})
	var lst := Battle.make_combatant("LST", "enemy", "wind",
		{"hp": 100000, "att": 1, "def": 50, "cri": 0, "evd": 0, "blk": 0})
	var lsev := Battle.resolve_double(ls, lst, _rng(5), cfg)
	fails += _eq("blood thirst double hp", int(ls["hp"]), 1010)
	fails += _eq("blood thirst double once", int(lsev[1].get("lifesteal", 0)), 10)

	# 3c) 각성기: 회피70%여도 무시하고 전체 타격, ×2.
	var caster := Battle.make_combatant("CAST", "ally", "fire", {"hp": 1, "att": 100, "def": 1, "cri": 0, "evd": 0, "blk": 0})
	var e1 := Battle.make_combatant("E1", "enemy", "wind", {"hp": 99999, "att": 1, "def": 50, "cri": 0, "evd": 70, "blk": 70})
	var e2 := Battle.make_combatant("E2", "enemy", "wind", {"hp": 99999, "att": 1, "def": 50, "cri": 0, "evd": 70, "blk": 70})
	var aev := Battle.resolve_awaken(caster, [e1, e2], _rng(5), cfg)
	fails += _eq("awaken hits all", aev.size(), 2)
	fails += _eq("awaken type", aev[0]["type"], "awaken")
	fails += _eq("awaken ignore evade", aev[0]["miss"], false)
	var ad := int(aev[0]["damage"])
	var ad_lo := Battle.damage(100, 50, 0.0, 1.25, 2.0, 0.95, cfg)
	var ad_hi := Battle.damage(100, 50, 0.0, 1.25, 2.0, 1.05, cfg)
	fails += _eq("awaken x2 range", ad >= ad_lo and ad <= ad_hi, true)

	# === 스킬 엔진 (효과는 발동 확정 후 결정적 → 직접 호출로 검증) ===
	# 패시브(90 신속이동 lv1): 회피 +7+1 상시
	var pc := _cb("P", "ally", "fire", 100, 100, [{"id": 90, "level": 1}])
	Battle._init_combatant_skills(pc, sdb)
	fails += _eq("passive evd", Battle._eff(pc, "evd"), 18)            # 10+7+1
	# 액티브 자버프(60 야수의본능 lv1): 공 +20%
	var bc := _cb("B", "ally", "fire", 100, 100, [])
	Battle._apply_skill_effect(bc, {"id": 60, "level": 1}, [bc], [], _rng(1), cfg, sdb)
	fails += _eq("buff att", Battle._eff(bc, "att"), 120)             # 100*1.2
	# 회복(29 치유의빛 lv1): 60+maxhp*0.07
	var hc := _cb("H", "ally", "fire", 100, 100, [])
	hc["hp"] = 100
	Battle._apply_skill_effect(hc, {"id": 29, "level": 1}, [hc], [], _rng(1), cfg, sdb)
	fails += _eq("heal", int(hc["hp"]), 300)                          # 100 + (60+2000*0.07=200)
	# 디버프(140 살기표출 lv1): 적 공 -10%
	var en := _cb("E", "enemy", "wind", 100, 100, [])
	Battle._apply_skill_effect(_cb("C", "ally", "fire", 100, 100, []), {"id": 140, "level": 1}, [], [en], _rng(1), cfg, sdb)
	fails += _eq("debuff att", Battle._eff(en, "att"), 90)            # 100*0.9
	# 뼈부수기(46): 방어·회피 불가
	var en2 := _cb("E2", "enemy", "wind", 100, 100, [])
	Battle._apply_skill_effect(_cb("C2", "ally", "fire", 100, 100, []), {"id": 46, "level": 1}, [], [en2], _rng(1), cfg, sdb)
	fails += _eq("bone no_evade", Battle._has_flag(en2, "no_evade"), true)
	fails += _eq("bone no_block", Battle._has_flag(en2, "no_block"), true)
	# 방어 스킬(11 철갑방패 lv2): 피해 -20
	fails += _eq("def reduce", int(Battle._defense_reduce(_cb("DF", "ally", "fire", 100, 100, []), {"id": 11, "level": 2}, 100, sdb)["dmg"]), 80)
	# 공격 스킬(21 심판의날개): 평타식 ×6.
	var ev21 := Battle._apply_skill_effect(_cb("A21", "ally", "fire", 100, 50, []), {"id": 21, "level": 1},
		[], [_cb("D21", "enemy", "wind", 100, 50, [])], _rng(3), cfg, sdb)
	var dmg21 := int(ev21[0]["damage"])
	var dmg21_lo := Battle.damage(100, 50, 0.0, 1.25, 6.0, 0.95, cfg)
	var dmg21_hi := Battle.damage(100, 50, 0.0, 1.25, 6.0, 1.05, cfg)
	fails += _eq("wing x6 range", dmg21 >= dmg21_lo and dmg21 <= dmg21_hi, true)

	# 망각의 망치(56): 무효화 + 보유자 횟수 차감
	var owner := _cb("O", "enemy", "wind", 100, 100, [{"id": 56, "level": 1}])
	Battle._init_combatant_skills(owner, sdb)
	var iev := Battle._oblivion_apply(_cb("CC", "ally", "fire", 100, 100, []), 36, owner, {"id": 56, "level": 1}, sdb)
	fails += _eq("oblivion interrupt", iev["interrupt"], true)
	fails += _eq("oblivion nullified", int(iev["nullified_id"]), 36)
	fails += _eq("oblivion use--", Battle._uses_left(owner, 56), 2)   # 3-1

	# 같은 지속효과가 활성화된 동안에는 재발동 후보 자체에서 제외한다.
	# 상처 파악(23)·신경독소(32)만 중첩/재시도 예외다.
	var gate := _cb("GATE", "ally", "fire", 100, 100,
		[{"id": 14, "level": 1}, {"id": 23, "level": 1}, {"id": 32, "level": 1}])
	Battle._init_combatant_skills(gate, sdb, cfg)
	gate["effects"].append({"kind": "lifesteal", "pct": 8, "turns": 2, "source": 14})
	var gated := Battle._eligible_attack(gate, sdb, cfg, [gate], [en])
	var gated_ids: Array = gated.map(func(s): return int((s as Dictionary)["id"]))
	fails += _eq("active buff no retry", 14 in gated_ids, false)
	fails += _eq("wound retry exception", 23 in gated_ids, true)
	fails += _eq("neurotoxin retry exception", 32 in gated_ids, true)

	# 피의 갈증 지속턴은 전역 라운드가 아니라 소유자의 행동 기준이다.
	# 발동한 그 행동에서는 차감하지 않고, 다음 두 번의 자신 공격에서 회복한 뒤 사라진다.
	var owner_turn := _cb("OWNER_TURN", "ally", "fire", 100, 100, [])
	owner_turn["hp"] = 1000
	var owner_foe := _cb("OWNER_FOE", "enemy", "wind", 1, 100, [])
	owner_turn["cri"] = 0
	owner_foe["evd"] = 0
	owner_foe["blk"] = 0
	Battle._mark_owner_effects(owner_turn)
	Battle._apply_skill_effect(owner_turn, {"id": 14, "level": 1}, [owner_turn], [owner_foe], _rng(1), cfg, sdb)
	var tick_events: Array = []
	Battle._tick_owner_effects(owner_turn, tick_events, 1)
	fails += _eq("blood thirst fresh keeps 2", int((owner_turn["effects"][0] as Dictionary)["turns"]), 2)
	for turn in [2, 3]:
		Battle._mark_owner_effects(owner_turn)
		Battle.resolve_attack(owner_turn, owner_foe, _rng(turn), cfg, sdb)
		Battle._tick_owner_effects(owner_turn, tick_events, turn)
	fails += _eq("blood thirst heals two attacks", int(owner_turn["hp"]), 1016)
	fails += _eq("blood thirst expires", Battle._lifesteal_pct(owner_turn), 0.0)
	fails += _eq("blood thirst ui tick remove", int((tick_events[-1] as Dictionary).get("turns", -1)), 0)

	# 망각의 망치(56)는 상대가 스킬을 고르고 발동 판정을 통과한 경로에서만 반응한다.
	# 상대가 스킬 없는 평타를 치면 사용 횟수와 이벤트가 모두 그대로다.
	var normal_actor := _cb("NORMAL", "ally", "fire", 100, 100, [])
	var hammer_owner := _cb("HAMMER", "enemy", "wind", 100, 100, [{"id": 56, "level": 1}])
	Battle._init_combatant_skills(normal_actor, sdb, cfg)
	Battle._init_combatant_skills(hammer_owner, sdb, cfg)
	var hammer_before := Battle._uses_left(hammer_owner, 56)
	var normal_ev := Battle._act(normal_actor, [normal_actor], [hammer_owner], _rng(4), cfg, sdb)
	var hammer_on_normal := false
	for nev in normal_ev:
		if int((nev as Dictionary).get("skill_id", 0)) == 56:
			hammer_on_normal = true
	fails += _eq("hammer skips normal attack", hammer_on_normal, false)
	fails += _eq("hammer normal keeps uses", Battle._uses_left(hammer_owner, 56), hammer_before)

	# 통합 시뮬: ally 신의분노(36) vs enemy 망각(56) — 크래시 없음 + 스킬 이벤트 발생
	var sa := [_cb("ally1", "ally", "fire", 150, 80, [{"id": 36, "level": 5}])]
	var sb := [_cb("enm1", "enemy", "wind", 150, 80, [{"id": 56, "level": 5}])]
	# 상향된 평타 계수에서도 체력 조건 스킬(36)이 열릴 때까지 전투가 이어지게 한다.
	for c in [sa[0], sb[0]]:
		c["hp_max"] = 20000
		c["hp"] = 20000
		c["hp_base"] = 20000
	# 신의 분노(36)는 원작 근거의 체력 조건 스킬이다. 저피해 공식에서도
	# 통합 테스트가 발동 경로를 실제로 타도록 시전자만 50% 아래에서 시작한다.
	sa[0]["hp"] = 9000
	var sres := Battle.simulate(sa, sb, _rng(11), cfg, sdb)
	fails += _eq("sim winner valid", sres["winner"] in ["ally", "enemy", "draw"], true)
	var has_skill := false
	for ev in sres["events"]:
		if ev.get("type") == "skill": has_skill = true
	fails += _eq("sim skill event", has_skill, true)

	# === 추가 효과(카테고리별) — 직접 호출 결정적 검증 ===
	# 복수의 거울(13): 방어 100 → 반사 9%(=9), 피해는 그대로
	var dref := _cb("R", "ally", "fire", 100, 100, [])
	var r13 := Battle._defense_reduce(dref, {"id": 13, "level": 1}, 50, sdb)
	fails += _eq("mirror reflect", int(r13["reflect"]), 9)        # min(50, 100*9%)
	fails += _eq("mirror dmg keep", int(r13["dmg"]), 50)
	# 신의 결계(12): 무효화
	fails += _eq("aegis nullify", int(Battle._defense_reduce(_cb("Z","ally","fire",1,1,[]), {"id":12,"level":1}, 80, sdb)["dmg"]), 0)
	# 상처 파악(23): 취약 +10% → _apply_dmg 100 → 110
	var vt := _cb("V", "enemy", "wind", 100, 100, [])
	Battle._apply_skill_effect(_cb("VC","ally","fire",100,100,[]), {"id": 23, "level": 1}, [], [vt], _rng(1), cfg, sdb)
	fails += _eq("vuln dmg", int(Battle._apply_dmg(vt, 100)["dmg"]), 110)
	# 신경독소(32): DoT 4%(=40) at round_end
	var dt := _cb("DT", "enemy", "wind", 100, 100, [])
	Battle._apply_skill_effect(_cb("DC","ally","fire",100,100,[]), {"id": 32, "level": 1}, [], [dt], _rng(1), cfg, sdb)
	var de: Array = []
	Battle._round_end([dt], [], de, 1)
	fails += _eq("dot dmg", 2000 - int(dt["hp"]), 80)             # hp_max 2000 * (3+1)%
	# 필살 방어(50): 1회 생존 → 치명타에도 hp 1
	var sv := _cb("SV", "ally", "fire", 100, 100, [])
	sv["hp"] = 500
	Battle._apply_skill_effect(sv, {"id": 50, "level": 1}, [sv], [], _rng(1), cfg, sdb)
	var sap := Battle._apply_dmg(sv, 99999)
	fails += _eq("survive hp1", int(sv["hp"]), 1)
	fails += _eq("survive not dead", bool(sap["dead"]), false)
	# 환각(22): _act에서 자해
	var cf := _cb("CF", "enemy", "wind", 100, 100, [])
	Battle._add_flag(cf, "confused", 2, 22)
	var cfev := Battle._act(cf, [_cb("X","ally","fire",100,100,[])], [cf], _rng(2), cfg, sdb)
	fails += _eq("confused self", cfev[0]["type"], "confused")
	fails += _eq("confused dmg>0", int(cfev[0]["damage"]) > 0, true)
	# 이판사판(55): 양측 현재 체력 50% 감소
	var ip := _cb("IP", "ally", "fire", 100, 100, [])
	ip["hp"] = 1000
	var ipt := _cb("IPT", "enemy", "wind", 100, 100, [])
	ipt["hp"] = 800
	Battle._apply_skill_effect(ip, {"id": 55, "level": 1}, [ip], [ipt], _rng(1), cfg, sdb)
	fails += _eq("ip self -50%", int(ip["hp"]), 500)
	fails += _eq("ip target -50%", int(ipt["hp"]), 400)
	# 빛의 정화(26): 해로운 효과 제거
	var cl := _cb("CL", "ally", "fire", 100, 100, [{"id": 26, "level": 1}])
	Battle._init_combatant_skills(cl, sdb)
	Battle._add_flag(cl, "no_evade", 3, 999)
	Battle._add_stat(cl, "att", "pct", -50, 3, 999)
	Battle._apply_skill_effect(cl, {"id": 26, "level": 1}, [cl], [], _rng(1), cfg, sdb)
	fails += _eq("cleanse flag", Battle._has_flag(cl, "no_evade"), false)
	fails += _eq("cleanse stat", Battle._eff(cl, "att"), 100)     # -50% 제거 → base
	# 암흑의 사슬(15): stun
	var st := _cb("ST", "enemy", "wind", 100, 100, [])
	Battle._apply_skill_effect(_cb("SC","ally","fire",100,100,[]), {"id": 15, "level": 1}, [], [st], _rng(1), cfg, sdb)
	fails += _eq("chain stun", Battle._has_flag(st, "stun"), true)

	# === 추가 스펙(사용자 보강): 20/30/53/24/150 ===
	# 보호의 장막(20): 평타 피해 50% / 스킬 피해엔 미적용
	fails += _eq("guard 50%", int(Battle._defense_reduce(_cb("G","ally","fire",100,100,[]), {"id": 20, "level": 1}, 100, sdb)["dmg"]), 50)
	var g20 := _cb("G20", "ally", "fire", 100, 100, [{"id": 20, "level": 1}])
	Battle._init_combatant_skills(g20, sdb)
	fails += _eq("guard skip skill", int(Battle._defense_skill_onhit(g20, _rng(1), 100, true, cfg, sdb)["dmg"]), 100)
	# 아수라일섬(30): 상대 base 방어 80 × 1.5 = 120 고정
	var as30 := Battle._apply_skill_effect(_cb("AS","ally","fire",100,100,[]), {"id": 30, "level": 1}, [], [_cb("AT","enemy","wind",100,80,[])], _rng(1), cfg, sdb)
	fails += _eq("asura def*1.5", int(as30[0]["damage"]), 120)
	# 히든 밸런스 규칙: 모든 피해 보정 후에도 아수라일섬은 대상 최대 HP의 70%까지만 피해를 준다.
	var as30_cap_caster := _cb("ASC", "ally", "fire", 100, 100, [])
	as30_cap_caster["effects"].append({"kind": "dmg_deal", "pct": 200, "turns": -1})
	var as30_cap_target := _cb("ATC", "enemy", "wind", 100, 80, [])
	as30_cap_target["hp"] = 100
	as30_cap_target["hp_max"] = 100
	as30_cap_target["blk"] = 0
	var as30_cap := Battle._apply_skill_effect(as30_cap_caster, {"id": 30, "level": 1}, [], [as30_cap_target], _rng(1), cfg, sdb)
	fails += _eq("asura hidden max-hp 70% cap", int(as30_cap[0]["damage"]), 70)
	var uncapped_target := _cb("UTC", "enemy", "wind", 100, 80, [])
	uncapped_target["hp"] = 100
	uncapped_target["hp_max"] = 100
	uncapped_target["blk"] = 0
	var uncapped := Battle._deal_attack(_cb("UAC", "ally", "fire", 100, 100, []), uncapped_target, 100, true, _rng(1), cfg, sdb)
	fails += _eq("non-asura remains uncapped", int(uncapped["damage"]), 100)
	# 거신의 돌격(53): caster hp 2000 × 17% × 0.7 = 238
	var gi53 := Battle._apply_skill_effect(_cb("GI","ally","fire",100,100,[]), {"id": 53, "level": 1}, [], [_cb("GT","enemy","wind",100,50,[])], _rng(1), cfg, sdb)
	fails += _eq("giant rush", int(gi53[0]["damage"]), 238)
	# 어둠의 손길(24): 적 스킬(60 야수의본능) 복사 → caster 공 +20%
	var darkc := _cb("DK", "ally", "fire", 100, 100, [])
	var darke := _cb("DKE", "enemy", "wind", 100, 100, [{"id": 60, "level": 1}])
	var dk24 := Battle._apply_skill_effect(darkc, {"id": 24, "level": 1}, [darkc], [darke], _rng(1), cfg, sdb)
	fails += _eq("dark copied id", int(dk24[0]["copied_id"]), 60)
	fails += _eq("dark copied buff", Battle._eff(darkc, "att"), 120)
	# 빙결의 표식(150): 주도권 마커 → 다음 라운드 아군 우선
	var ipa := [_cb("IA", "ally", "fire", 100, 100, [])]
	var ipb := [_cb("IB", "enemy", "wind", 100, 100, [])]
	ipa[0]["effects"].append({"kind": "initiative", "side": "ally", "turns": 2})
	var iside := Battle._consume_initiative(ipa, ipb)
	fails += _eq("initiative side", iside, "ally")
	fails += _eq("initiative consumed", ipa[0]["effects"].size(), 0)
	# 주도권 결정(기본 메커니즘): forced(150) 우선, 같은 진영 4연속이면 강제 교체
	fails += _eq("lead forced", Battle._decide_lead(_rng(1), "enemy", 2, "ally"), "ally")
	fails += _eq("lead streak guard", Battle._decide_lead(_rng(1), "ally", 4, ""), "enemy")

	# 4) 시뮬레이션 재현성(같은 시드 → 동일 결과)
	var r1 := _sim_with_seed(42)
	var r2 := _sim_with_seed(42)
	fails += _eq("repro winner", r1["winner"], r2["winner"])
	fails += _eq("repro events", r1["events"].size(), r2["events"].size())
	fails += _eq("repro dmgsum", _dmg_sum(r1), _dmg_sum(r2))
	var r3 := _sim_with_seed(99)
	# 다른 시드는 보통 다른 전개(이벤트 수 다름) — 동일하면 의심. (약한 단언)
	if r1["events"].size() == r3["events"].size() and _dmg_sum(r1) == _dmg_sum(r3):
		print("  WARN seed42 vs seed99 동일 — RNG 의심")

	# 5) 압도적 우위 → ally 승
	fails += _eq("stomp winner", _stomp()["winner"], "ally")

	if fails == 0:
		print("[test_battle] ✅ ALL PASS")
	else:
		print("[test_battle] ❌ %d FAIL" % fails)
	quit(1 if fails > 0 else 0)

# ---- helpers ----
func _dummy(hp_max: int, def: int) -> Dictionary:
	return {"name": "h%dd%d" % [hp_max, def], "alive": true, "hp_max": hp_max, "def": def}

func _cb(name: String, side: String, el: String, att: int, def: int, skills: Array) -> Dictionary:
	return Battle.make_combatant(name, side, el, {"hp": 2000, "att": att, "def": def, "cri": 10, "evd": 10, "blk": 10}, 0.0, skills)

func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r

func _party(prefix: String, side: String, n: int, hp: int, att: int, def: int, el := "fire") -> Array:
	var out: Array = []
	for i in n:
		out.append(Battle.make_combatant("%s%d" % [prefix, i], side, el,
			{"hp": hp, "att": att, "def": def, "cri": 10, "evd": 10, "blk": 10}))
	return out

func _sim_with_seed(seed: int) -> Dictionary:
	var cfg := _load("res://data/combat.json")
	var a := _party("A", "ally", 3, 1000, 120, 60, "fire")
	var b := _party("B", "enemy", 3, 900, 110, 55, "wind")
	return Battle.simulate(a, b, _rng(seed), cfg)

func _stomp() -> Dictionary:
	var cfg := _load("res://data/combat.json")
	var a := _party("S", "ally", 3, 5000, 500, 200, "fire")
	var b := _party("W", "enemy", 1, 100, 10, 1, "wind")
	return Battle.simulate(a, b, _rng(7), cfg)

func _dmg_sum(res: Dictionary) -> int:
	var s := 0
	for ev in res["events"]:
		s += int(ev["damage"])
	return s

func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())

func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	print("  FAIL %s: got %s want %s" % [label, str(got), str(want)])
	return 1

func _eqf(label: String, got: float, want: float) -> int:
	if absf(got - want) < 0.0001:
		return 0
	print("  FAIL %s: got %s want %s" % [label, str(got), str(want)])
	return 1
