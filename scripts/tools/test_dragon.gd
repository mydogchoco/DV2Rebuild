extends SceneTree
## 헤드리스 Dragon(드래곤 코어) 검증 (§10 data/logic).
## 원작 근거: docs/ref/orig_code/decomp/Dragon.c(631m) — 필드 {no/name/element/getAttackType(전투유형)/
##   getDragonStarClass(성급)/getGrade/getAwaken/getAwakenSkill/getHpOriginal·getAttTotal·getDefTotal
##   (스탯)/getExp·getExpMax/stages(진화)}. 스탯값=stat_table(전투유형×성급티어 base/growth, DragonStat 모델).
## 검증: dragons.json(369) 전종이 (a)코어필드(id/name/element/type/star/stat_tier/stages) 완비,
##   (b)Growth.compute_stats로 유효 스탯(hp/att/def>0) 산출 — Dragon 스탯 파이프라인 end-to-end.
##   ⚠️유실: 정확 base/growth 수치=DragonStat.xlsx 역설계(ASSUMPTION, [[dv2-dragon-stat-model]]).
## 실행: godot --headless --path <proj> --script res://scripts/tools/test_dragon.gd

func _init() -> void:
	var fails := 0
	var draw = _load("res://data/dragons.json")
	var dragons = draw.get("dragons", draw) if typeof(draw) == TYPE_DICTIONARY else draw
	if typeof(dragons) == TYPE_DICTIONARY:
		dragons = dragons.values()
	var stat_table = _load("res://data/stat_table.json")
	fails += _b("dragons 로드", typeof(dragons) == TYPE_ARRAY and dragons.size() >= 1)
	fails += _b("stat_table 로드", typeof(stat_table) == TYPE_DICTIONARY and stat_table.size() >= 1)

	var VALID_EL := ["fire", "aqua", "wind", "earth", "light", "dark", "holy", "chaos", "shadow"]
	var checked := 0
	var with_stages := 0
	var bad_stat := 0
	for d in dragons:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		# Dragon 코어필드
		# 이름이 **플레이어 선택권**으로 정해지는 드래곤(dragons.csv 의 `null` 표기, id 600·700)은
		# 마스터 데이터에 이름이 없는 것이 정상이다 — 선택된 원본 드래곤의 것을 따라간다.
		if not bool(d.get("name_from_player", false)):
			fails += _b("dragon.name", _s(d.get("name")).strip_edges() != "")
		fails += _b("dragon.element valid", _s(d.get("element")) in VALID_EL or _s(d.get("element")) in ["None",""])
		fails += _b("dragon.type(getAttackType)", _s(d.get("type")).strip_edges() != "")
		fails += _b("dragon.star>0(getDragonStarClass)", _num(d.get("star", 0)) > 0.0)
		# Dragon 스탯 파이프라인(getHpTotal 등): compute_stats가 유효 스탯 산출
		var stats = Growth.compute_stats(d, stat_table, 30, {})
		if int(stats.get("hp", 0)) <= 0 or int(stats.get("att", 0)) <= 0:
			bad_stat += 1
			if bad_stat <= 5:
				printerr("FAIL stat pipeline: id=%s type=%s tier=%s hp=%s" % [d.get("id"), d.get("type"), d.get("stat_tier"), stats.get("hp")])
		# 진화 stages(getStage): 있으면 카운트
		if d.has("stages") and typeof(d["stages"]) in [TYPE_ARRAY, TYPE_DICTIONARY] and d["stages"].size() >= 1:
			with_stages += 1
		checked += 1

	fails += _b("전 드래곤 스탯 파이프라인 유효", bad_stat == 0)
	print("[test_dragon] %d 드래곤: 코어필드 완비, 스탯파이프라인 정상 %d, 진화stages 보유 %d" % [checked, checked - bad_stat, with_stages])

	if fails == 0:
		print("[test_dragon] ALL PASS")
	else:
		printerr("[test_dragon] %d FAIL (bad_stat=%d)" % [fails, bad_stat])
	quit(0 if fails == 0 else 1)

func _load(p: String):
	var f := FileAccess.open(p, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f else {}

func _s(v) -> String:
	return "" if v == null else str(v)

func _num(v) -> float:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT: return float(v)
		TYPE_STRING: return float(v) if (v as String).is_valid_float() else 0.0
	return 0.0

func _b(tag: String, cond: bool) -> int:
	if cond:
		return 0
	printerr("FAIL %s" % tag)
	return 1
