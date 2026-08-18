extends SceneTree

func _init() -> void:
	var fails := 0
	var cfg := _load(_data_file("combat.json"))
	var sdb := _load(_data_file("skills.json"))
	var stages := _load(_data_file("stages.json"))

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
	fails += _eqf("dark~holy", Battle.element_mult("dark", "holy", cfg), 1.0)

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
	fails += _eq("dmg min1", Battle.damage(1, 9999, 0.0, 0.85, 1.0, 0.95, cfg), 1)

	var A := _dummy(400, 10)
	var B := _dummy(200, 100)
	var C := _dummy(800, 0)
	fails += _eq("target max", Battle.pick_target([A, B, C], cfg)["name"], C["name"])
	C["alive"] = false
	fails += _eq("target skip dead", Battle.pick_target([A, B, C], cfg)["name"], B["name"])

	var datk := Battle.make_combatant("ATK", "ally", "fire", {"hp": 1, "att": 100, "def": 1, "cri": 0, "evd": 0, "blk": 0})
	var ddef := Battle.make_combatant("DEF", "enemy", "wind", {"hp": 100000, "att": 1, "def": 50, "cri": 0, "evd": 0, "blk": 0})
	var dev := Battle.resolve_double(datk, ddef, _rng(5), cfg)
	fails += _eq("double 2hits", dev.size(), 2)
	fails += _eq("double h0 type", dev[0]["type"], "double")
	fails += _eq("double h0 nomiss", dev[0]["miss"], false)
	fails += _eq("double h1 nomiss", dev[1]["miss"], false)
	fails += _eq("double sum=loss", int(dev[0]["damage"]) + int(dev[1]["damage"]), 100000 - int(ddef["hp"]))

	var ls := Battle.make_combatant("LS", "ally", "fire",
		{"hp": 2000, "att": 100, "def": 1, "cri": 0, "evd": 0, "blk": 0})
	ls["hp"] = 1000
	ls["effects"].append({"kind": "lifesteal", "pct": 10, "turns": 2, "source": 14})
	var lst := Battle.make_combatant("LST", "enemy", "wind",
		{"hp": 100000, "att": 1, "def": 50, "cri": 0, "evd": 0, "blk": 0})
	var lsev := Battle.resolve_double(ls, lst, _rng(5), cfg)
	fails += _eq("blood thirst double hp", int(ls["hp"]), 1010)
	fails += _eq("blood thirst double once", int(lsev[1].get("lifesteal", 0)), 10)

	var caster := Battle.make_combatant("CAST", "ally", "fire", {"hp": 1, "att": 100, "def": 1, "cri": 0, "evd": 0, "blk": 0})
	var e1 := Battle.make_combatant("E1", "enemy", "wind", {"hp": 99999, "att": 1, "def": 50, "cri": 0, "evd": 70, "blk": 70})
	var e2 := Battle.make_combatant("E2", "enemy", "wind", {"hp": 99999, "att": 1, "def": 50, "cri": 0, "evd": 70, "blk": 70})
	var hp_a0 := int(e1["hp"]) + int(e2["hp"])
	var aev := Battle.resolve_awaken(caster, [e1, e2], _rng(5), cfg)
	var fire_hits := int((cfg.get("awaken", {}).get("hits_by_element", {})
		.get("fire", {}) as Dictionary).get("hits", 1))
	fails += _eq("awaken hits all", aev.size(), fire_hits * 2)
	fails += _eq("awaken type", aev[0]["type"], "awaken")
	fails += _eq("awaken ignore evade", aev[0]["miss"], false)
	var leads := 0
	var lasts := 0
	var per := {"E1": 0, "E2": 0}
	for e in aev:
		if bool((e as Dictionary).get("volley_lead", false)):
			leads += 1
		if bool((e as Dictionary).get("volley_last", false)):
			lasts += 1
		per[String((e as Dictionary)["defender"])] += int((e as Dictionary).get("damage", 0))
	fails += _eq("awaken lead once", leads, 1)
	fails += _eq("awaken lead is first", bool(aev[0].get("volley_lead", false)), true)
	fails += _eq("awaken last once", lasts, 1)
	fails += _eq("awaken last is final", bool(aev[aev.size() - 1].get("volley_last", false)), true)
	fails += _eq("awaken split sums to hp loss",
		int(per["E1"]) + int(per["E2"]), hp_a0 - (int(e1["hp"]) + int(e2["hp"])))
	var ad_lo := Battle.damage(100, 50, 0.0, 1.25, 2.0, 0.95, cfg)
	var ad_hi := Battle.damage(100, 50, 0.0, 1.25, 2.0, 1.05, cfg)
	fails += _eq("awaken x2 range", int(per["E1"]) >= ad_lo and int(per["E1"]) <= ad_hi, true)

	var pc := _cb("P", "ally", "fire", 100, 100, [{"id": 90, "level": 1}])
	Battle._init_combatant_skills(pc, sdb)
	fails += _eq("passive evd", Battle._eff(pc, "evd"), 18)
	var bc := _cb("B", "ally", "fire", 100, 100, [])
	Battle._apply_skill_effect(bc, {"id": 60, "level": 1}, [bc], [], _rng(1), cfg, sdb)
	fails += _eq("buff att", Battle._eff(bc, "att"), 120)
	var hc := _cb("H", "ally", "fire", 100, 100, [])
	hc["hp"] = 100
	Battle._apply_skill_effect(hc, {"id": 29, "level": 1}, [hc], [], _rng(1), cfg, sdb)
	fails += _eq("heal", int(hc["hp"]), 300)
	var en := _cb("E", "enemy", "wind", 100, 100, [])
	Battle._apply_skill_effect(_cb("C", "ally", "fire", 100, 100, []), {"id": 140, "level": 1}, [], [en], _rng(1), cfg, sdb)
	fails += _eq("debuff att", Battle._eff(en, "att"), 90)
	var en2 := _cb("E2", "enemy", "wind", 100, 100, [])
	Battle._apply_skill_effect(_cb("C2", "ally", "fire", 100, 100, []), {"id": 46, "level": 1}, [], [en2], _rng(1), cfg, sdb)
	fails += _eq("bone no_evade", Battle._has_flag(en2, "no_evade"), true)
	fails += _eq("bone no_block", Battle._has_flag(en2, "no_block"), true)
	fails += _eq("def reduce", int(Battle._defense_reduce(_cb("DF", "ally", "fire", 100, 100, []), {"id": 11, "level": 2}, 100, sdb)["dmg"]), 80)
	var ev21 := Battle._apply_skill_effect(_cb("A21", "ally", "fire", 100, 50, []), {"id": 21, "level": 1},
		[], [_cb("D21", "enemy", "wind", 100, 50, [])], _rng(3), cfg, sdb)
	var dmg21 := int(ev21[0]["damage"])
	var dmg21_lo := Battle.damage(100, 50, 0.0, 1.25, 6.0, 0.95, cfg)
	var dmg21_hi := Battle.damage(100, 50, 0.0, 1.25, 6.0, 1.05, cfg)
	fails += _eq("wing x6 range", dmg21 >= dmg21_lo and dmg21 <= dmg21_hi, true)

	var owner := _cb("O", "enemy", "wind", 100, 100, [{"id": 56, "level": 1}])
	Battle._init_combatant_skills(owner, sdb)
	var iev := Battle._oblivion_apply(_cb("CC", "ally", "fire", 100, 100, []), 36, owner, {"id": 56, "level": 1}, sdb)
	fails += _eq("oblivion interrupt", iev["interrupt"], true)
	fails += _eq("oblivion nullified", int(iev["nullified_id"]), 36)
	fails += _eq("oblivion use--", Battle._uses_left(owner, 56), 2)

	var gate := _cb("GATE", "ally", "fire", 100, 100,
		[{"id": 14, "level": 1}, {"id": 23, "level": 1}, {"id": 32, "level": 1}])
	Battle._init_combatant_skills(gate, sdb, cfg)
	gate["effects"].append({"kind": "lifesteal", "pct": 8, "turns": 2, "source": 14})
	var gated := Battle._eligible_attack(gate, sdb, cfg, [gate], [en])
	var gated_ids: Array = gated.map(func(s): return int((s as Dictionary)["id"]))
	fails += _eq("active buff no retry", 14 in gated_ids, false)
	fails += _eq("wound retry exception", 23 in gated_ids, true)
	fails += _eq("neurotoxin retry exception", 32 in gated_ids, true)

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

	var free_fired := 0
	var free_kept_turn := 0
	var free_healed := 0
	var free_turns_left := 0
	for fseed in range(1, 80):
		var fc := _cb("FC", "ally", "fire", 300, 100, [{"id": 14, "level": 1}])
		fc["hp"] = 1000
		fc["cri"] = 0
		Battle._init_combatant_skills(fc, sdb, cfg)
		var fe := _cb("FE", "enemy", "wind", 1, 10, [])
		fe["evd"] = 0
		fe["blk"] = 0
		Battle._mark_owner_effects(fc)
		var fatt := false
		var fcast := false
		for fev in Battle._act(fc, [fc], [fe], _rng(fseed), cfg, sdb):
			var fd := fev as Dictionary
			if String(fd.get("type", "")) == "skill" and int(fd.get("skill_id", 0)) == 14:
				fcast = true
			elif String(fd.get("type", "")) in ["normal", "double"] and String(fd.get("attacker", "")) == "FC":
				fatt = true
				if int(fd.get("lifesteal", 0)) > 0:
					free_healed += 1
		if fcast:
			free_fired += 1
			if fatt: free_kept_turn += 1
			Battle._tick_owner_effects(fc, [], 1)
			if Battle._lifesteal_pct(fc) > 0.0:
				free_turns_left += 1
	fails += _eq("free cast fires", free_fired > 0, true)
	fails += _eq("free cast keeps the turn", free_kept_turn, free_fired)
	fails += _eq("free cast buff applies same turn", free_healed > 0, true)
	fails += _eq("free cast spends a buff turn", free_turns_left, free_fired)

	var na_foe := _cb("NAF", "enemy", "wind", 300, 10, [])
	var na := _cb("NA", "ally", "fire", 100, 100, [{"id": 12, "level": 5}])
	Battle._init_combatant_skills(na, sdb, cfg)
	Battle._add_flag(na, "no_attack", -1, 0)
	fails += _eq("no_attack skips own turn", Battle._act(na, [na], [na_foe], _rng(3), cfg, sdb).size(), 0)
	var na_fired := 0
	for nseed in range(1, 60):
		var nd := _cb("ND", "ally", "fire", 100, 100, [{"id": 12, "level": 5}])
		Battle._init_combatant_skills(nd, sdb, cfg)
		Battle._add_flag(nd, "no_attack", -1, 0)
		nd["evd"] = 0
		nd["blk"] = 0
		var nev := Battle.resolve_attack(na_foe, nd, _rng(nseed), cfg, sdb)
		if String(nev.get("def_skill", "")) != "":
			na_fired += 1
			fails += _eq("aegis nullifies while no_attack", int(nev.get("damage", -1)) <= 1, true)
	fails += _eq("no_attack still casts defense skill on hit", na_fired > 0, true)

	var paid_fired := 0
	var paid_plus_attack := 0
	for pseed in range(1, 80):
		var pac := _cb("PC", "ally", "fire", 300, 100, [{"id": 21, "level": 1}])
		Battle._init_combatant_skills(pac, sdb, cfg)
		var pae := _cb("PE", "enemy", "wind", 1, 10, [])
		var pcast := false
		var patt := false
		for pev in Battle._act(pac, [pac], [pae], _rng(pseed), cfg, sdb):
			var pdd := pev as Dictionary
			if String(pdd.get("type", "")) == "skill" and int(pdd.get("skill_id", 0)) == 21:
				pcast = true
			elif String(pdd.get("type", "")) in ["normal", "double"] and String(pdd.get("attacker", "")) == "PC":
				patt = true
		if pcast:
			paid_fired += 1
			if patt: paid_plus_attack += 1
	fails += _eq("attack skill fires", paid_fired > 0, true)
	fails += _eq("attack skill still spends the turn", paid_plus_attack, 0)

	var hp_c := _cb("HPC", "ally", "fire", 100, 100, [])
	hp_c["hp_max"] = 1000
	for pair in [[1000, 20.0], [750, 31.5], [500, 43.0], [250, 54.5], [0, 66.0]]:
		hp_c["hp"] = int(pair[0])
		fails += _eqf("proc curve @hp %d" % int(pair[0]), Battle._hp_proc_pct(hp_c, cfg), float(pair[1]))
	fails += _eqf("proc base from cfg", float(cfg.get("skill_proc", {}).get("base_pct", -1)), 20.0)
	fails += _eqf("proc low from cfg", float(cfg.get("skill_proc", {}).get("low_hp_pct", -1)), 66.0)
	hp_c["hp"] = 1
	fails += _eqf("hammer keeps notes proc", Battle._proc_pct(hp_c, sdb.get("56", {}), 3, cfg), 55.0)
	var proc_full := 0
	var proc_low := 0
	for hseed in range(1, 200):
		for lowhp in [false, true]:
			var hpp_actor := _cb("HP%s" % str(lowhp), "ally", "fire", 300, 100, [{"id": 21, "level": 1}])
			Battle._init_combatant_skills(hpp_actor, sdb, cfg)
			hpp_actor["hp_max"] = 1000
			hpp_actor["hp"] = 30 if lowhp else 1000
			var hfoe := _cb("HPF", "enemy", "wind", 1, 10, [])
			for hev in Battle._act(hpp_actor, [hpp_actor], [hfoe], _rng(hseed), cfg, sdb):
				if int((hev as Dictionary).get("skill_id", 0)) == 21:
					if lowhp: proc_low += 1
					else: proc_full += 1
	fails += _eq("proc at full hp near 20%", proc_full > 20 and proc_full < 60, true)
	fails += _eq("proc at low hp rises", proc_low > proc_full * 2, true)

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

	var sa := [_cb("ally1", "ally", "fire", 150, 80, [{"id": 36, "level": 5}])]
	var sb := [_cb("enm1", "enemy", "wind", 150, 80, [{"id": 56, "level": 5}])]
	for c in [sa[0], sb[0]]:
		c["hp_max"] = 20000
		c["hp"] = 20000
		c["hp_base"] = 20000
	sa[0]["hp"] = 9000
	var sres := Battle.simulate(sa, sb, _rng(11), cfg, sdb)
	fails += _eq("sim winner valid", sres["winner"] in ["ally", "enemy", "draw"], true)
	var has_skill := false
	for ev in sres["events"]:
		if ev.get("type") == "skill": has_skill = true
	fails += _eq("sim skill event", has_skill, true)

	var dref := _cb("R", "ally", "fire", 100, 100, [])
	var r13 := Battle._defense_reduce(dref, {"id": 13, "level": 1}, 50, sdb)
	fails += _eq("mirror reflect", int(r13["reflect"]), 9)
	fails += _eq("mirror dmg keep", int(r13["dmg"]), 50)
	fails += _eq("aegis nullify", int(Battle._defense_reduce(_cb("Z","ally","fire",1,1,[]), {"id":12,"level":1}, 80, sdb)["dmg"]), 0)
	var vt := _cb("V", "enemy", "wind", 100, 100, [])
	var vev: Array = Battle._apply_skill_effect(_cb("VC","ally","fire",100,100,[]), {"id": 23, "level": 1}, [], [vt], _rng(1), cfg, sdb)
	fails += _eq("vuln dmg", int(Battle._apply_dmg(vt, 100)["dmg"]), 110)
	fails += _eq("vuln stacks 1", int((vev[0] as Dictionary).get("stacks", 0)), 1)
	var vev2: Array = Battle._apply_skill_effect(_cb("VC2","ally","water",100,100,[]), {"id": 23, "level": 1}, [], [vt], _rng(2), cfg, sdb)
	fails += _eq("vuln stack sum", int(Battle._apply_dmg(vt, 100)["dmg"]), 120)
	fails += _eq("vuln stacks 2", int((vev2[0] as Dictionary).get("stacks", 0)), 2)
	var dt := _cb("DT", "enemy", "wind", 100, 100, [])
	Battle._apply_skill_effect(_cb("DC","ally","fire",100,100,[]), {"id": 32, "level": 1}, [], [dt], _rng(1), cfg, sdb)
	var de: Array = []
	Battle._round_end([dt], [], de, 1)
	fails += _eq("dot dmg", 2000 - int(dt["hp"]), 80)
	var sv := _cb("SV", "ally", "fire", 100, 100, [])
	sv["hp"] = 500
	Battle._apply_skill_effect(sv, {"id": 50, "level": 1}, [sv], [], _rng(1), cfg, sdb)
	var sap := Battle._apply_dmg(sv, 99999)
	fails += _eq("survive hp1", int(sv["hp"]), 1)
	fails += _eq("survive not dead", bool(sap["dead"]), false)
	var cf := _cb("CF", "enemy", "wind", 100, 100, [])
	Battle._add_flag(cf, "confused", 2, 22)
	var cfev := Battle._act(cf, [_cb("X","ally","fire",100,100,[])], [cf], _rng(2), cfg, sdb)
	fails += _eq("confused self", cfev[0]["type"], "confused")
	fails += _eq("confused dmg>0", int(cfev[0]["damage"]) > 0, true)
	var ip := _cb("IP", "ally", "fire", 100, 100, [])
	ip["hp"] = 1000
	var ipt := _cb("IPT", "enemy", "wind", 100, 100, [])
	ipt["hp"] = 800
	Battle._apply_skill_effect(ip, {"id": 55, "level": 1}, [ip], [ipt], _rng(1), cfg, sdb)
	fails += _eq("ip self -50%", int(ip["hp"]), 500)
	fails += _eq("ip target -50%", int(ipt["hp"]), 400)
	var ipc := _cb("IPC", "ally", "fire", 100, 100, [])
	ipc["hp"] = 20000
	var ipct := _cb("IPCT", "enemy", "wind", 100, 100, [])
	ipct["hp"] = 20000
	var ipcev := Battle._apply_skill_effect(ipc, {"id": 55, "level": 1}, [ipc], [ipct], _rng(1), cfg, sdb)
	fails += _eq("ip target loss capped 2000", int(ipcev[0]["target_loss"]), 2000)
	fails += _eq("ip target hp after cap", int(ipct["hp"]), 18000)
	fails += _eq("ip self loss uncapped", int(ipcev[0]["self_loss"]), 10000)
	fails += _eq("ip self hp uncapped", int(ipc["hp"]), 10000)
	var ipd := _cb("IPD", "ally", "fire", 100, 100, [])
	ipd["hp"] = 1000
	var ipdt := _cb("IPDT", "enemy", "wind", 100, 100, [])
	ipdt["hp"] = 1000
	var ipdev := Battle._apply_skill_effect(ipd, {"id": 55, "level": 1, "dedicated": true}, [ipd], [ipdt], _rng(1), cfg, sdb)
	fails += _eq("ip dedicated 60% under cap", int(ipdev[0]["target_loss"]), 600)
	var cl := _cb("CL", "ally", "fire", 100, 100, [{"id": 26, "level": 1}])
	Battle._init_combatant_skills(cl, sdb)
	Battle._add_flag(cl, "no_evade", 3, 999)
	Battle._add_stat(cl, "att", "pct", -50, 3, 999)
	Battle._apply_skill_effect(cl, {"id": 26, "level": 1}, [cl], [], _rng(1), cfg, sdb)
	fails += _eq("cleanse flag", Battle._has_flag(cl, "no_evade"), false)
	fails += _eq("cleanse stat", Battle._eff(cl, "att"), 100)
	var aw_buff := _cb("AWB", "ally", "fire", 100, 100, [])
	aw_buff["effects"].append({"kind": "dmg_taken", "pct": -25, "turns": -1, "src": "aw:10"})
	aw_buff["effects"].append({"kind": "stat", "stat": "att", "mode": "pct", "value": -20, "turns": -1, "src": "aw:11"})
	fails += _eq("cleanse gate: 패시브만이면 후보 아님", Battle._any_debuffed([aw_buff]), false)
	Battle._cleanse(aw_buff)
	fails += _eq("cleanse: 상시 특성 보존", (aw_buff["effects"] as Array).size(), 2)
	var aw_hurt := _cb("AWH", "ally", "fire", 100, 100, [])
	aw_hurt["effects"].append({"kind": "dmg_taken", "pct": 10, "turns": -1, "source": 23})
	fails += _eq("cleanse gate: 진짜 디버프면 후보", Battle._any_debuffed([aw_hurt]), true)
	Battle._cleanse(aw_hurt)
	fails += _eq("cleanse: 진짜 디버프 제거", (aw_hurt["effects"] as Array).size(), 0)
	var healer := _cb("HL", "ally", "fire", 100, 100, [])
	var dying := _cb("DY", "ally", "fire", 100, 100, [])
	dying["hp"] = int(dying["hp_max"]) / 5
	var fine := _cb("FN", "ally", "fire", 100, 100, [])
	fails += _eq("heal gate: 빈사 아군 있으면 통과",
		Battle._hp_gate_ok(healer, 29, cfg, sdb["29"], [healer, dying]), true)
	fails += _eq("heal gate: 전원 멀쩡하면 차단",
		Battle._hp_gate_ok(healer, 29, cfg, sdb["29"], [healer, fine]), false)
	var low_self := _cb("LS", "ally", "fire", 100, 100, [])
	low_self["hp"] = int(low_self["hp_max"]) / 5
	fails += _eq("self gate(30): 시전자 체력만 본다",
		Battle._hp_gate_ok(low_self, 30, cfg, sdb["30"], [low_self, fine]), true)
	fails += _eq("self gate(30): 아군만 빈사면 차단",
		Battle._hp_gate_ok(healer, 30, cfg, sdb["30"], [healer, dying]), false)
	var st := _cb("ST", "enemy", "wind", 100, 100, [])
	Battle._apply_skill_effect(_cb("SC","ally","fire",100,100,[]), {"id": 15, "level": 1}, [], [st], _rng(1), cfg, sdb)
	fails += _eq("chain stun", Battle._has_flag(st, "stun"), true)

	fails += _eq("guard 50%", int(Battle._defense_reduce(_cb("G","ally","fire",100,100,[]), {"id": 20, "level": 1}, 100, sdb)["dmg"]), 50)
	var g20 := _cb("G20", "ally", "fire", 100, 100, [{"id": 20, "level": 1}])
	Battle._init_combatant_skills(g20, sdb)
	fails += _eq("guard skip skill", int(Battle._defense_skill_onhit(g20, _rng(1), 100, true, cfg, sdb)["dmg"]), 100)
	var as30 := Battle._apply_skill_effect(_cb("AS","ally","fire",100,100,[]), {"id": 30, "level": 1}, [], [_cb("AT","enemy","wind",100,80,[])], _rng(1), cfg, sdb)
	fails += _eq("asura def*1.5", int(as30[0]["damage"]), 120)
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
	var gi53 := Battle._apply_skill_effect(_cb("GI","ally","fire",100,100,[]), {"id": 53, "level": 1}, [], [_cb("GT","enemy","wind",100,50,[])], _rng(1), cfg, sdb)
	fails += _eq("giant rush", int(gi53[0]["damage"]), 238)
	var darkc := _cb("DK", "ally", "fire", 100, 100, [])
	var darke := _cb("DKE", "enemy", "wind", 100, 100, [{"id": 60, "level": 1}])
	var dk24 := Battle._apply_skill_effect(darkc, {"id": 24, "level": 1}, [darkc], [darke], _rng(1), cfg, sdb)
	fails += _eq("dark copied id", int(dk24[0]["copied_id"]), 60)
	fails += _eq("dark copied buff", Battle._eff(darkc, "att"), 120)
	var ipa := [_cb("IA", "ally", "fire", 100, 100, [])]
	var ipb := [_cb("IB", "enemy", "wind", 100, 100, [])]
	ipa[0]["effects"].append({"kind": "initiative", "side": "ally", "turns": 2})
	var iside := Battle._consume_initiative(ipa, ipb)
	fails += _eq("initiative side", iside, "ally")
	fails += _eq("initiative consumed", ipa[0]["effects"].size(), 0)
	fails += _eq("lead forced", Battle._decide_lead(_rng(1), "enemy", 2, "ally"), "ally")
	fails += _eq("lead streak guard", Battle._decide_lead(_rng(1), "ally", 4, ""), "enemy")

	var r1 := _sim_with_seed(42)
	var r2 := _sim_with_seed(42)
	fails += _eq("repro winner", r1["winner"], r2["winner"])
	fails += _eq("repro events", r1["events"].size(), r2["events"].size())
	fails += _eq("repro dmgsum", _dmg_sum(r1), _dmg_sum(r2))
	var r3 := _sim_with_seed(99)
	if r1["events"].size() == r3["events"].size() and _dmg_sum(r1) == _dmg_sum(r3):
		print("  WARN seed42 vs seed99 동일 — RNG 의심")

	fails += _eq("stomp winner", _stomp()["winner"], "ally")

	if fails == 0:
		print("[test_battle] ✅ ALL PASS")
	else:
		print("[test_battle] ❌ %d FAIL" % fails)
	quit(1 if fails > 0 else 0)

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
	var cfg := _load(_data_file("combat.json"))
	var a := _party("A", "ally", 3, 1000, 120, 60, "fire")
	var b := _party("B", "enemy", 3, 900, 110, 55, "wind")
	return Battle.simulate(a, b, _rng(seed), cfg)

func _stomp() -> Dictionary:
	var cfg := _load(_data_file("combat.json"))
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

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
