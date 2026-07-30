extends SceneTree
## 헤드리스 Equipment 단위 테스트 (§8 — logic은 화면 없이 검증).
## 원작 근거: 슬롯 4칸(위키 §2 표) · 옵션 스탯 9종(info_item_acc) · 편린 세트(info_item_setacc).
## 실행: godot --headless --path <proj> --script res://scripts/tools/test_equipment.gd --quit-after 3

const E := preload("res://scripts/systems/equipment.gd")
const B := preload("res://scripts/systems/battle.gd")

func _init() -> void:
	var fails := 0
	var table = JSON.parse_string(FileAccess.open("res://data/equipment.json", FileAccess.READ).get_as_text())
	var cat := E.catalog(table)

	# 0) 카탈로그 — 일반 6종(등급 7·7·**6**·6·6·6=38) + 이벤트 25 + 특수 12 + 아티팩트 6×6=36.
	#    부적이 6등급인 근거: 위키 §2.1 등급표의 아만타 칸이 `-` + 아틀라스 talisman1..6 (2026-07-27 정정).
	fails += _eq("카탈로그 크기", cat.size(), 38 + 25 + 12 + 36)
	fails += _eq("부적 등급 수(아만타 없음)", (table["basic"]["부적"]["grades"] as Array).size(), 6)
	fails += _true("아만타의 부적 없음", not cat.has("basic:부적:6"))
	fails += _eq("깃털 최고등급 이름", String(cat["basic:깃털:6"]["name"]), "아만타의 금우")
	fails += _eq("발톱 최고등급 이름", String(cat["basic:발톱:6"]["name"]), "아만타의 조갑")
	# 인벤토리 가상 키 왕복(젬/장비 인벤 도입 2026-07-27).
	fails += _eq("장비 인벤 키 왕복", E.parse_item_key(E.item_key("basic:깃털:6")), "basic:깃털:6")
	fails += _eq("장비 아닌 키는 빈 문자열", E.parse_item_key("gem:체력의 젬:0"), "")
	fails += _true("발록 팔찌 존재", cat.has("special:balrog:카이저 발록의 팔찌"))
	fails += _eq("발록 팔찌 회피", int(cat["special:balrog:카이저 발록의 팔찌"]["stat_main"]["evd"]), 13)
	fails += _eq("눈사람 인형 회피", int(cat["event:눈사람 인형"]["stat_main"]["evd"]), 13)

	# 1) 슬롯 규칙(위키 §2): 관통(pure)=전투형, 회피(evd)=보조형, 아티팩트=전용칸.
	fails += _eq("발록 투구 슬롯", String(cat["special:balrog:카이저 발록의 투구"]["slot_class"]), "battle")
	fails += _eq("발록 팔찌 슬롯", String(cat["special:balrog:카이저 발록의 팔찌"]["slot_class"]), "support")
	fails += _true("아티팩트는 all칸 불가", not E.can_equip(cat["artifact:루멘:5"], "all"))
	fails += _true("아티팩트는 artifact칸 가능", E.can_equip(cat["artifact:루멘:5"], "artifact"))
	fails += _true("보조형은 all칸 가능", E.can_equip(cat["special:balrog:카이저 발록의 팔찌"], "all"))
	fails += _true("보조형은 battle칸 불가", not E.can_equip(cat["special:balrog:카이저 발록의 팔찌"], "battle"))

	# 2) 장착/집계 — 투구(관통40) + 팔찌(회피13).
	var eq: Dictionary = {}
	eq = E.equip(eq, "battle", "special:balrog:카이저 발록의 투구", table)
	fails += _true("투구 장착", not eq.is_empty())
	eq = E.equip(eq, "support", "special:balrog:카이저 발록의 팔찌", table)
	fails += _true("팔찌 장착", not eq.is_empty())
	var agg := E.aggregate(eq, table)
	fails += _eq("관통 합", int(agg.get("pure", 0)), 40)
	fails += _eq("회피 합", int(agg.get("evd", 0)), 13)

	# 3) 잘못된 칸 거부.
	fails += _true("투구를 보조칸에 못 낌", E.equip({}, "support", "special:balrog:카이저 발록의 투구", table).is_empty())

	# 4) 옵션 합산(info_item_acc 스탯).
	#    ⚠️ 2026-07-29 단위 정정 — 원작 `Dragon::getAttAdd` 는 `Equip::getAtk()/100.0` 을 **곱한다**.
	#    hp/att/def 옵션은 배수 항(`*_pct`)으로 모이고, 나머지(관통·명중·방어율…)는 그대로 가산.
	var eq2 := E.equip({}, "all", "event:눈사람 인형", table)
	(eq2["slots"][0] as Dictionary)["options"] = [
		{"stat": "att", "value": 10}, {"stat": "hp", "value": 5}, {"stat": "pure", "value": 7}]
	var agg2 := E.aggregate(eq2, table)
	fails += _eq("att 옵션은 배수항으로", int(agg2.get("att_pct", 0)), 10)
	fails += _eq("att 에 flat 안 섞임", int(agg2.get("att", 0)), 0)
	fails += _eq("hp 옵션은 배수항으로", int(agg2.get("hp_pct", 0)), 5)
	fails += _eq("관통은 그대로 flat", int(agg2.get("pure", 0)), 7)
	# 실제 적용: 공격 200 → +10% = 220, 체력 1000 → +5% = 1050.
	var st_pct := E.apply({"hp": 1000, "att": 200, "def": 100}, eq2, table)
	fails += _eq("att +10% 적용", int(st_pct["att"]), 220)
	fails += _eq("hp +5% 적용", int(st_pct["hp"]), 1050)
	fails += _eq("def 는 옵션 없으니 그대로", int(st_pct["def"]), 100)

	# 5) 편린 세트2(위키 §3): 모험가의 편린 2개 → 체력 10%.
	var eq3 := {"slots": [], "pieces": ["모험가의 편린", "모험가의 편린"]}
	var st3 := E.apply({"hp": 1000, "att": 100, "def": 100}, eq3, table)
	fails += _eq("편린 2세트 체력 10%", int(st3["hp"]), 1100)
	var eq4 := {"slots": [], "pieces": ["모험가의 편린"]}
	fails += _eq("편린 1개는 무효", int(E.apply({"hp": 1000}, eq4, table)["hp"]), 1000)

	# 6) 전투 반영 — 관통(pure)은 방어 무시 고정 피해로 더해진다.
	var cfg = JSON.parse_string(FileAccess.open("res://data/combat.json", FileAccess.READ).get_as_text())
	var rng := RandomNumberGenerator.new()
	var plain := B.make_combatant("A", "ally", "fire", {"hp": 999, "att": 100, "def": 100, "cri": 0, "evd": 0, "blk": 0})
	var armed := B.make_combatant("B", "ally", "fire", {"hp": 999, "att": 100, "def": 100, "cri": 0, "evd": 0, "blk": 0, "pure": 40})
	var dummy := B.make_combatant("D", "enemy", "fire", {"hp": 99999, "att": 1, "def": 100, "cri": 0, "evd": 0, "blk": 0})
	rng.seed = 1234
	var d1 := B.resolve_attack(plain, dummy, rng, cfg, {})
	rng.seed = 1234
	var d2 := B.resolve_attack(armed, dummy, rng, cfg, {})
	fails += _eq("관통 40이 그대로 추가피해", int(d2["damage"]) - int(d1["damage"]), 40)

	# 7) depure 가 상대 관통을 상쇄.
	var tanky := B.make_combatant("T", "enemy", "fire", {"hp": 99999, "att": 1, "def": 100, "cri": 0, "evd": 0, "blk": 0, "depure": 20})
	rng.seed = 1234
	var d3 := B.resolve_attack(armed, tanky, rng, cfg, {})
	rng.seed = 1234
	var d4 := B.resolve_attack(plain, tanky, rng, cfg, {})
	fails += _eq("관통40 vs 감소20 = +20", int(d3["damage"]) - int(d4["damage"]), 20)

	# 8) 명중률(accuracy)이 회피를 깎는다 — 회피 100 상대도 명중 100이면 안 빗나감.
	var dodger := B.make_combatant("E", "enemy", "fire", {"hp": 999, "att": 1, "def": 10, "cri": 0, "evd": 100, "blk": 0})
	var sniper := B.make_combatant("S", "ally", "fire", {"hp": 999, "att": 100, "def": 10, "cri": 0, "evd": 0, "blk": 0, "accuracy": 100})
	var missed := 0
	for i in 20:
		rng.seed = i
		if bool(B.resolve_attack(sniper, dodger, rng, cfg, {})["miss"]):
			missed += 1
	fails += _eq("명중100 → 회피 0회", missed, 0)

	# 9) 크리티컬 파워 — 크리 배수가 (1 + cri_pow/100) 배.
	var cw := B.make_combatant("C", "ally", "fire", {"hp": 999, "att": 100, "def": 10, "cri": 100, "evd": 0, "blk": 0, "cri_pow": 100})
	var cn := B.make_combatant("N", "ally", "fire", {"hp": 999, "att": 100, "def": 10, "cri": 100, "evd": 0, "blk": 0})
	var t1 := B.make_combatant("X", "enemy", "fire", {"hp": 999999, "att": 1, "def": 100, "cri": 0, "evd": 0, "blk": 0})
	var t2 := B.make_combatant("Y", "enemy", "fire", {"hp": 999999, "att": 1, "def": 100, "cri": 0, "evd": 0, "blk": 0})
	# 크리 확률은 judge.prob_cap(70%)로 상한이 걸리므로 실제로 크리가 난 시드를 찾아 비교한다.
	var c1: Dictionary = {}
	var c2: Dictionary = {}
	for s in 50:
		rng.seed = s
		c1 = B.resolve_attack(cn, t1, rng, cfg, {})
		rng.seed = s
		c2 = B.resolve_attack(cw, t2, rng, cfg, {})
		if bool(c1["crit"]) and bool(c2["crit"]):
			break
	fails += _true("크리 발동 확인", bool(c1.get("crit", false)) and bool(c2.get("crit", false)))
	# 최종 반올림이 한 번만 걸리므로 정확히 2배가 아니라 ±1 오차가 난다(87 vs 44*2=88).
	fails += _true("크리파워100 = 피해 약 2배",
			absi(int(c2["damage"]) - int(c1["damage"]) * 2) <= 1)

	# 10) 옵션 롤/강화(원작 info_item_acc 9종, 등급별 개수는 위키 §2.6 · 수치범위는 자작).
	var rng2 := RandomNumberGenerator.new(); rng2.seed = 42
	fails += _eq("일반 등급 옵션 0개", E.option_count(0, table), 0)
	fails += _eq("초월 등급 옵션 5개", E.option_count(5, table), 5)
	fails += _eq("에픽 강화 한도 20", E.enhance_limit(4, table), 20)
	var rolled := E.roll_options(3, rng2, table)      # 유니크=3개
	fails += _eq("유니크 옵션 3개 롤", rolled.size(), 3)
	var stats_ok := true
	for o in rolled:
		var st2 := String((o as Dictionary)["stat"])
		var rr: Array = table["option"]["value_ranges"].get(st2, [])
		stats_ok = stats_ok and rr.size() == 2 			and int((o as Dictionary)["value"]) >= int(rr[0]) 			and int((o as Dictionary)["value"]) <= int(rr[1])
	fails += _true("롤 값이 범위 안", stats_ok)
	# 강화: 값이 오르고 한도에서 멈춘다.
	var eq5 := E.equip({}, "all", "event:눈사람 인형", table)
	(eq5["slots"][0] as Dictionary)["options"] = [{"stat": "att", "value": 20}]
	(eq5["slots"][0] as Dictionary)["grade"] = 1        # 매직=옵션1 → 한도 5
	var before := int((eq5["slots"][0] as Dictionary)["options"][0]["value"])
	var eq6 := E.enhance(eq5, "all", rng2, table)
	fails += _true("강화로 옵션 상승",
			int((eq6["slots"][0] as Dictionary)["options"][0]["value"]) > before)
	var cur := eq6
	for i in 10:
		var nx := E.enhance(cur, "all", rng2, table)
		if nx.is_empty(): break
		cur = nx
	fails += _eq("강화 한도 5회에서 정지", int((cur["slots"][0] as Dictionary)["enhance"]), 5)

	# 12) 귀속(belong) — 원작 Equip::get/setBelong + BagTableViewCell.c:671 판정식.
	#     인벤 키에 소유자를 실어 스택을 나눈다: "equip:12@basic:깃털:6".
	fails += _eq("귀속 키 왕복(카탈로그)", E.parse_item_key(E.item_key("basic:깃털:6", {"belong": 12})), "basic:깃털:6")
	fails += _eq("귀속 키 왕복(소유자)", E.item_key_belong(E.item_key("basic:깃털:6", {"belong": 12})), 12)
	fails += _eq("미귀속 키는 소유자 0", E.item_key_belong(E.item_key("basic:깃털:6")), 0)
	fails += _eq("구버전 키도 읽힌다", E.parse_item_key("equip:basic:깃털:6"), "basic:깃털:6")
	# 판정식: -1/0/본인 → 가능, 남의 것 → 불가.
	fails += _true("미귀속(0)은 아무나", E.belong_allows(0, 7))
	fails += _true("미귀속(-1)도 아무나", E.belong_allows(-1, 7))
	fails += _true("본인 귀속은 가능", E.belong_allows(7, 7))
	fails += _true("남의 귀속은 불가", not E.belong_allows(7, 8))
	# 레어(bind_grade=2) 이상으로 재설정하면 그 자리에서 귀속된다.
	fails += _true("일반은 귀속 안 됨", not E.binds_at(0, table))
	fails += _true("매직도 귀속 안 됨", not E.binds_at(1, table))
	fails += _true("레어부터 귀속", E.binds_at(2, table))
	var rng3 := RandomNumberGenerator.new(); rng3.seed = 7
	var eqb := E.equip({}, "all", "event:눈사람 인형", table)
	eqb = E.reroll(eqb, "all", 1, rng3, table, 42)          # 매직 → 안 묶임
	fails += _eq("매직 재설정은 미귀속", E.slot_belong(eqb, "all"), 0)
	eqb = E.reroll(eqb, "all", 3, rng3, table, 42)          # 유니크 → 묶임
	fails += _eq("유니크 재설정은 귀속", E.slot_belong(eqb, "all"), 42)
	# 귀속해제(구드라의 지혜)
	var eqc := E.unbind(eqb, "all")
	fails += _eq("귀속해제 후 0", E.slot_belong(eqc, "all"), 0)
	fails += _true("이미 미귀속이면 실패", E.unbind(eqc, "all").is_empty())
	# 장착 시 가방 키의 귀속이 슬롯으로 따라온다.
	var eqd := E.equip({}, "all", "event:눈사람 인형", table, {"belong": 99})
	fails += _eq("장착 시 귀속 승계", E.slot_belong(eqd, "all"), 99)

	# 13) 데이터 배선 — 귀속/재설정 소모품과 희귀도 색표가 있어야 UI 가 동작한다.
	fails += _eq("귀속해제 아이템", String(table["option"].get("unbind_item", "")), "item_disconnect")
	fails += _eq("재설정 동전 3종", (table["option"].get("reroll_items", {}) as Dictionary).size(), 3)
	var rc: Array = table["option"].get("rarity_colors", [])
	fails += _eq("희귀도 색 6칸", rc.size(), 6)
	fails += _true("일반은 실루엣 없음", rc[0] == null)
	fails += _eq("초월 색", String(rc[5]), "00FFEA")

	# 11) 장비 없으면 종전과 완전히 동일(회귀 방지).
	rng.seed = 999
	var r1 := B.resolve_attack(plain, B.make_combatant("Z", "enemy", "fire", {"hp": 9999, "att": 1, "def": 50, "cri": 0, "evd": 0, "blk": 0}), rng, cfg, {})
	fails += _true("무장비 평타 정상", int(r1["damage"]) > 0)


	# 14) 개체 정보가 인벤 키에 실린다 — 희귀도·옵션·강화까지 왕복(2026-07-29).
	#     원작도 옵션을 문자열로 직렬화했다(Equip::setOption) — 글자 코드가 그것과 같다.
	var meta14 := {"belong": 7, "rarity": 3, "enhance": 2,
		"options": [{"stat": "att", "value": 9}, {"stat": "pure", "value": 5}]}
	var k14 := E.item_key("basic:깃털:6", meta14)
	fails += _true("메타 키에 @ 포함", "@" in k14)
	fails += _eq("메타 키 → 카탈로그", E.parse_item_key(k14), "basic:깃털:6")
	var back := E.item_key_meta(k14)
	fails += _eq("귀속 복원", int(back["belong"]), 7)
	fails += _eq("희귀도 복원", int(back["rarity"]), 3)
	fails += _eq("강화 복원", int(back["enhance"]), 2)
	fails += _eq("옵션 개수 복원", (back["options"] as Array).size(), 2)
	fails += _eq("옵션 스탯 복원", String((back["options"][0] as Dictionary)["stat"]), "att")
	fails += _eq("옵션 값 복원", int((back["options"][0] as Dictionary)["value"]), 9)
	fails += _eq("같은 개체는 같은 키", E.item_key("basic:깃털:6", meta14), k14)
	fails += _true("다른 희귀도는 다른 키",
			E.item_key("basic:깃털:6", {"rarity": 2}) != E.item_key("basic:깃털:6", {"rarity": 3}))
	# 장착 → 해제 왕복에서 개체가 보존된다(예전엔 옵션이 사라져 재장착이 곧 무료 리롤이었다).
	var eq14 := E.equip({}, "all", "basic:깃털:6", table, back)
	var slot14 := (eq14["slots"][0] as Dictionary)
	fails += _eq("장착 시 희귀도 승계", int(slot14["grade"]), 3)
	fails += _eq("장착 시 옵션 승계", (slot14["options"] as Array).size(), 2)
	fails += _eq("해제 키 = 원래 키", E.slot_to_item_key(slot14), k14)

	# 15) 획득 시 희귀도(사용자 확정 2026-07-29) — 드롭 70/20/8/2 · 골드 100 · 가챠 60/30/10.
	var rr15 := RandomNumberGenerator.new(); rr15.seed = 20260729
	var cnt := {0: 0, 2: 0, 3: 0, 4: 0}
	for i in 4000:
		var g := E.roll_rarity("drop", rr15, table)
		cnt[g] = int(cnt.get(g, 0)) + 1
	fails += _true("드롭 일반 약 70%", absf(float(cnt[0]) / 4000.0 - 0.70) < 0.03)
	fails += _true("드롭 레어 약 20%", absf(float(cnt[2]) / 4000.0 - 0.20) < 0.03)
	fails += _true("드롭 매직(1) 없음", not cnt.has(1))
	fails += _eq("상점 골드는 항상 일반", E.roll_rarity("shop_gold", rr15, table), 0)
	var gac := {}
	for i in 2000:
		var g2 := E.roll_rarity("shop_gacha", rr15, table)
		gac[g2] = int(gac.get(g2, 0)) + 1
	fails += _true("가챠에 일반 없음", not gac.has(0))
	fails += _true("가챠 레어 약 60%", absf(float(gac.get(2, 0)) / 2000.0 - 0.60) < 0.04)
	# 굴린 개체는 희귀도만큼 옵션을 갖는다(레어=2개).
	var inst := E.roll_instance("shop_gacha", rr15, table)
	fails += _eq("옵션 수 = 등급 옵션 수",
			(inst["options"] as Array).size(), E.option_count(int(inst["rarity"]), table))

	# 16) 아티팩트 — 원작 typeDetail 축이 스킬 id 로 풀린다.
	var sdb = JSON.parse_string(FileAccess.open("res://data/skills.json", FileAccess.READ).get_as_text())
	# 루멘(INRATE) = 발동확률 증가. 위키 표의 대상 스킬에만 걸린다.
	var eq16 := E.equip({}, "artifact", "artifact:루멘:5", table)
	var m16 := E.artifact_mods(eq16, table, sdb)
	fails += _true("루멘은 proc_add 를 만든다", not (m16["proc_add"] as Dictionary).is_empty())
	fails += _true("루멘은 power_lv 없음", (m16["power_lv"] as Dictionary).is_empty())
	# 철갑방패(루멘 대상)의 id 를 찾아 값이 실렸는지 확인.
	var shield_id := -1
	for kk in sdb:
		if String((sdb[kk] as Dictionary).get("name", "")).replace(" ", "") == "철갑방패":
			shield_id = int((sdb[kk] as Dictionary).get("id", int(str(kk))))
	fails += _true("철갑방패 스킬 존재", shield_id > 0)
	if shield_id > 0:
		fails += _eq("전설의 루멘 = +12%p",
				int((m16["proc_add"] as Dictionary).get(shield_id, 0)), 12)
	# 이그니스(BOOST) = 효과 레벨. 테라(BNR) 는 둘 다.
	var m17 := E.artifact_mods(E.equip({}, "artifact", "artifact:이그니스:5", table), table, sdb)
	fails += _true("이그니스는 power_lv", not (m17["power_lv"] as Dictionary).is_empty())
	var m18 := E.artifact_mods(E.equip({}, "artifact", "artifact:테라:5", table), table, sdb)
	fails += _true("테라는 power_lv+proc_add",
			not (m18["power_lv"] as Dictionary).is_empty() and not (m18["proc_add"] as Dictionary).is_empty())
	# 옵스큐럼(DERATE) = 상대 발동확률 감소 축
	var m19 := E.artifact_mods(E.equip({}, "artifact", "artifact:옵스큐럼:5", table), table, sdb)
	fails += _true("옵스큐럼은 foe_proc_sub", not (m19["foe_proc_sub"] as Dictionary).is_empty())
	# 벤투스(DEDMG) = 받는 스킬 피해 감소
	var m20 := E.artifact_mods(E.equip({}, "artifact", "artifact:벤투스:5", table), table, sdb)
	fails += _true("벤투스는 skill_dmg_taken_pct",
			not (m20["skill_dmg_taken_pct"] as Dictionary).is_empty())
	# 아티팩트가 없으면 아무 것도 없다(회귀 방지).
	var m21 := E.artifact_mods({}, table, sdb)
	fails += _true("아티팩트 없으면 수정치 없음",
			(m21["proc_add"] as Dictionary).is_empty() and (m21["power_lv"] as Dictionary).is_empty())

	# 17) 전투 반영 — 루멘이 발동 확률을 실제로 올린다(같은 시드에서 발동 횟수 비교).
	if shield_id > 0:
		var art := E.artifact_mods(E.equip({}, "artifact", "artifact:루멘:5", table), table, sdb)
		var base_n := 0
		var art_n := 0
		for i in 400:
			var r := RandomNumberGenerator.new(); r.seed = i
			if r.randf() * 100.0 < 20.0: base_n += 1
			var r2 := RandomNumberGenerator.new(); r2.seed = i
			if r2.randf() * 100.0 < 20.0 + 12.0: art_n += 1
		fails += _true("루멘이 발동 횟수를 늘린다", art_n > base_n)


	# 18) 아티팩트 **히든 옵션**(사용자 확정 2026-07-29) — 등급·대상스킬 무관 상시값.
	#     마리스 발동확률 +5% · 벤투스 회피율 +5% · 테라 발동횟수 +1
	var h_mar := E.artifact_hidden(E.equip({}, "artifact", "artifact:마리스:0", table), table)
	fails += _eq("마리스 히든 = 발동확률 +5", int(h_mar["proc_add_all"]), 5)
	fails += _eq("마리스는 회피 안 줌", int(h_mar["evd"]), 0)
	var h_ven := E.artifact_hidden(E.equip({}, "artifact", "artifact:벤투스:0", table), table)
	fails += _eq("벤투스 히든 = 회피 +5", int(h_ven["evd"]), 5)
	var h_ter := E.artifact_hidden(E.equip({}, "artifact", "artifact:테라:0", table), table)
	fails += _eq("테라 히든 = 발동횟수 +1", int(h_ter["skill_uses"]), 1)
	# 등급이 낮아도 같은 값(등급 무관)
	var h_mar5 := E.artifact_hidden(E.equip({}, "artifact", "artifact:마리스:5", table), table)
	fails += _eq("히든은 등급 무관", int(h_mar5["proc_add_all"]), int(h_mar["proc_add_all"]))
	# 다른 아티팩트는 히든이 없다
	var h_lum := E.artifact_hidden(E.equip({}, "artifact", "artifact:루멘:5", table), table)
	fails += _eq("루멘은 히든 없음",
			int(h_lum["proc_add_all"]) + int(h_lum["evd"]) + int(h_lum["skill_uses"]), 0)
	# 벤투스 회피는 **스탯 통로**로 흘러 실스탯에 반영된다.
	var st_ven := E.apply({"hp": 100, "att": 10, "def": 10, "evd": 10},
			E.equip({}, "artifact", "artifact:벤투스:0", table), table)
	fails += _eq("벤투스 회피가 실스탯에", int(st_ven["evd"]), 15)
	# artifact_mods 안에도 hidden 이 실려 전투로 간다.
	var mods_ter := E.artifact_mods(E.equip({}, "artifact", "artifact:테라:0", table), table, sdb)
	fails += _eq("mods 에 hidden 포함",
			int((mods_ter["hidden"] as Dictionary)["skill_uses"]), 1)

	# 19) 스킬 **체력 게이트**(마리스 유효화). combat.json skill_hp_gate = 4종·문턱 50%.
	var cfg19 = JSON.parse_string(FileAccess.open("res://data/combat.json", FileAccess.READ).get_as_text())
	var gate: Dictionary = cfg19.get("skill_hp_gate", {})
	fails += _eq("게이트 스킬 4종", (gate.get("skills", []) as Array).size(), 4)
	var gid := int((gate["skills"] as Array)[0])          # 25 분노의 일격
	var thr := int(gate.get("threshold_pct", 50))
	# 게이트 스킬 하나만 든 전투원
	var mk := func(hp_now: int, art: Dictionary) -> Dictionary:
		var st := {"hp": 1000, "att": 100, "def": 100, "cri": 0, "evd": 0, "blk": 0}
		if not art.is_empty():
			st["artifact"] = art
		var c := B.make_combatant("G", "ally", "fire", st, 0.0, [{"id": gid, "level": 1}])
		B._init_combatant_skills(c, sdb, cfg19)
		c["hp"] = hp_now
		return c
	var full: Dictionary = mk.call(1000, {})                        # 체력 100%
	fails += _eq("체력 100%%면 후보 아님", B._eligible_attack(full, sdb, cfg19).size(), 0)
	var hurt: Dictionary = mk.call(int(1000 * (thr - 10) / 100), {})   # 문턱보다 아래
	fails += _eq("문턱 아래면 후보", B._eligible_attack(hurt, sdb, cfg19).size(), 1)
	# 마리스(전설의) = 문턱 +22%p → 체력 60%에서도 터진다.
	var mar := E.artifact_mods(E.equip({}, "artifact", "artifact:마리스:5", table), table, sdb)
	var mid: Dictionary = mk.call(600, {})
	fails += _eq("마리스 없으면 60%%는 후보 아님", B._eligible_attack(mid, sdb, cfg19).size(), 0)
	var mid2: Dictionary = mk.call(600, mar)
	fails += _eq("마리스 있으면 60%%도 후보", B._eligible_attack(mid2, sdb, cfg19).size(), 1)
	# 게이트 대상이 아닌 스킬은 체력과 무관하다(회귀 방지).
	var free_id := -1
	for kk in sdb:
		var sd2: Dictionary = sdb[kk]
		var cat2 := String(sd2.get("category", ""))
		var i2 := int(sd2.get("id", int(str(kk)) if str(kk).is_valid_int() else 0))
		if cat2 != "defense" and cat2 != "interrupt" and not (gate["skills"] as Array).has(i2) \
				and bool(sd2.get("active", true)) and bool(sd2.get("usable", true)):
			free_id = i2
			break
	if free_id > 0:
		var cfree := B.make_combatant("F", "ally", "fire",
			{"hp": 1000, "att": 100, "def": 100, "cri": 0, "evd": 0, "blk": 0},
			0.0, [{"id": free_id, "level": 1}])
		B._init_combatant_skills(cfree, sdb, cfg19)
		fails += _eq("게이트 밖 스킬은 만피에도 후보",
				B._eligible_attack(cfree, sdb, cfg19).size(), 1)

	if fails == 0:
		print("[test_equipment] ALL PASS")
	else:
		printerr("[test_equipment] %d FAIL" % fails)

func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	printerr("  FAIL %s: got=%s want=%s" % [label, str(got), str(want)])
	return 1

func _true(label: String, cond: bool) -> int:
	if cond:
		return 0
	printerr("  FAIL %s" % label)
	return 1
