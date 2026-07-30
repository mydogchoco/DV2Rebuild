extends SceneTree
## 헤드리스 Battle 단위 테스트 (§10 — logic은 화면 없이 검증).
## 실행: godot --headless --path <proj> --script res://scripts/tools/test_battle.gd

func _init() -> void:
	var fails := 0
	var cfg := _load("res://data/combat.json")
	var sdb := _load("res://data/skills.json")

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

	# 2) 데미지식(§K-2): base 30
	fails += _eq("dmg base", Battle.damage(100, 50, 0.0, 1.0, 1.0, 1.0, cfg), 60)        # 30*100/50
	fails += _eq("dmg crit", Battle.damage(100, 50, 0.0, 1.0, 1.5, 1.0, cfg), 90)        # *1.5
	fails += _eq("dmg elem", Battle.damage(100, 50, 0.0, 1.25, 1.0, 1.0, cfg), 75)       # *1.25
	fails += _eq("dmg pen", Battle.damage(100, 50, 0.5, 1.0, 1.0, 1.0, cfg), 120)        # def_eff 25
	fails += _eq("dmg def0", Battle.damage(100, 0, 0.0, 1.0, 1.0, 1.0, cfg), 3000)       # def_eff max(1,0)=1
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

	# 3c) 각성기: 회피70%여도 무시하고 전체 타격, ×2 (fire>wind 1.25: 30*100/50*1.25*2*rand → 142~158)
	var caster := Battle.make_combatant("CAST", "ally", "fire", {"hp": 1, "att": 100, "def": 1, "cri": 0, "evd": 0, "blk": 0})
	var e1 := Battle.make_combatant("E1", "enemy", "wind", {"hp": 99999, "att": 1, "def": 50, "cri": 0, "evd": 70, "blk": 70})
	var e2 := Battle.make_combatant("E2", "enemy", "wind", {"hp": 99999, "att": 1, "def": 50, "cri": 0, "evd": 70, "blk": 70})
	var aev := Battle.resolve_awaken(caster, [e1, e2], _rng(5), cfg)
	fails += _eq("awaken hits all", aev.size(), 2)
	fails += _eq("awaken type", aev[0]["type"], "awaken")
	fails += _eq("awaken ignore evade", aev[0]["miss"], false)
	var ad := int(aev[0]["damage"])
	fails += _eq("awaken x2 range", ad >= 142 and ad <= 158, true)

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
	# 공격 스킬(21 심판의날개): 평타식 ×6 (30*100/50*1.25*6*rand = 427~473)
	var ev21 := Battle._apply_skill_effect(_cb("A21", "ally", "fire", 100, 50, []), {"id": 21, "level": 1},
		[], [_cb("D21", "enemy", "wind", 100, 50, [])], _rng(3), cfg, sdb)
	var dmg21 := int(ev21[0]["damage"])
	fails += _eq("wing x6 range", dmg21 >= 427 and dmg21 <= 473, true)

	# 망각의 망치(56): 무효화 + 보유자 횟수 차감
	var owner := _cb("O", "enemy", "wind", 100, 100, [{"id": 56, "level": 1}])
	Battle._init_combatant_skills(owner, sdb)
	var iev := Battle._oblivion_apply(_cb("CC", "ally", "fire", 100, 100, []), 36, owner, {"id": 56, "level": 1}, sdb)
	fails += _eq("oblivion interrupt", iev["interrupt"], true)
	fails += _eq("oblivion nullified", int(iev["nullified_id"]), 36)
	fails += _eq("oblivion use--", Battle._uses_left(owner, 56), 2)   # 3-1

	# 통합 시뮬: ally 신의분노(36) vs enemy 망각(56) — 크래시 없음 + 스킬 이벤트 발생
	var sa := [_cb("ally1", "ally", "fire", 150, 80, [{"id": 36, "level": 5}])]
	var sb := [_cb("enm1", "enemy", "wind", 150, 80, [{"id": 56, "level": 5}])]
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
