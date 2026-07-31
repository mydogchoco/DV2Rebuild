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

	print("=== %s ===" % ("PASS" if _fails == 0 else "FAIL %d건" % _fails))
	quit(0 if _fails == 0 else 1)


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
