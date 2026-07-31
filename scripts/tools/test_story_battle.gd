extends SceneTree
## 스토리 전투 편성 해석 검증 (§8 — data 층은 화면 없이 검증).
##
## 원작 세 경로가 우선순위대로 풀리는지 본다:
##   ① getEventBattleData  26·27·29 (스탯·필드까지 리터럴)
##   ② initEventBattle     4·5~14·19~24 (몬스터만)
##   ③ AdventureScene switch 15·16·17~27·28 (몬스터 + 레벨)
##
## 실행: godot --headless --path . --script res://scripts/tools/test_story_battle.gd

## 전투번호 → (몬스터 이름 일부, 레벨). 원작 축자.
const EXPECT := {
	26: ["심해 상어전사", 99],      # 이벤트 — hp/att/def 90000, 필드 602
	27: ["관문의 수호자", 99],      # 이벤트 — 필드 24
	28: ["관문의 수호자", 100],     # switch  — 91화
	29: ["다크프로스티", 50],       # 이벤트 — 필드 601
	11: ["기계 만드라고낙", 50],    # initEventBattle — 27화
	12: ["정령 스파이크젤", 50],    # initEventBattle — 28화
	14: ["다크프로스티", 50],       # initEventBattle — 32화
	15: ["다크프로스티", 50],       # switch          — 33화
}

func _init() -> void:
	var fails := 0
	var sq: Dictionary = _json("res://data/story_subquest.json")
	var sb: Dictionary = _json("res://data/story_battles.json")
	var sm: Dictionary = _json("res://data/story_monsters.json")
	var st: Dictionary = _json("res://data/stages.json").get("stages", {})
	if sq.is_empty() or sb.is_empty() or sm.is_empty():
		print("FAIL: data 로드 실패"); quit(1); return

	for bno in EXPECT.keys():
		var want: Array = EXPECT[bno]
		var spec: Dictionary = _resolve(int(bno), sq, sb, sm, st)
		if spec.is_empty():
			print("FAIL battle %d: 편성 못 찾음" % bno); fails += 1; continue
		var e: Dictionary = spec["enemy"]
		if not String(e.get("name", "")).contains(String(want[0])):
			print("FAIL battle %d: 몬스터 %s != %s" % [bno, e.get("name"), want[0]]); fails += 1
		if int(e.get("level", 0)) != int(want[1]):
			print("FAIL battle %d: 레벨 %d != %d" % [bno, int(e.get("level", 0)), int(want[1])])
			fails += 1
		if int(e.get("hp_max", 0)) <= 0 or int(e.get("att", 0)) <= 0:
			print("FAIL battle %d: 스탯 비어 있음 %s" % [bno, e]); fails += 1

	# 다크프로스티의 고정 피해(=pure)가 실려야 한다 — 사용자 확정 "공격 시 고정 데미지 1000".
	var dp: Dictionary = _resolve(15, sq, sb, sm, st)
	if int((dp.get("enemy", {}) as Dictionary).get("pure", 0)) != 1000:
		print("FAIL: 다크프로스티 pure 1000 이 안 실렸다"); fails += 1

	# 이벤트 전투는 원작이 필드를 지정한다(602 · 24 · 601).
	for pair in [[26, 602], [27, 24], [29, 601]]:
		var got := int(_resolve(int(pair[0]), sq, sb, sm, st).get("field", 0))
		if got != int(pair[1]):
			print("FAIL battle %d: 필드 %d != %d" % [pair[0], got, pair[1]]); fails += 1

	print("[story_battle] 전투 %d건 검증" % EXPECT.size())
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit(0 if fails == 0 else 1)


## data_loader.story_battle 과 **같은 규칙**(오토로드 없이 도는 테스트라 여기 복제).
func _resolve(bno: int, sq: Dictionary, sb: Dictionary, sm: Dictionary,
		st: Dictionary) -> Dictionary:
	var key := str(bno)
	var ev: Dictionary = sq.get("event_battle", {}).get(key, {})
	if not ev.is_empty():
		var e0: Dictionary = _enemy(int(ev.get("monster_no", 0)), int(ev.get("lv", 1)), sm, st)
		if e0.is_empty():
			return {}
		e0["hp_max"] = int(ev.get("hp", 1))
		e0["att"] = int(ev.get("att", 1))
		e0["def"] = int(ev.get("def", 1))
		return {"enemy": e0, "field": int(ev.get("field_no", 0))}
	for tbl in ["monster_by_battle_event", "monster_by_battle"]:
		var rec: Dictionary = sb.get(tbl, {}).get(key, {})
		if rec.is_empty():
			continue
		var e1: Dictionary = _enemy(int(rec.get("monster_no", 0)), int(rec.get("level", 0)), sm, st)
		if not e1.is_empty():
			return {"enemy": e1, "field": 0}
	return {}


func _enemy(no: int, level: int, sm: Dictionary, st: Dictionary) -> Dictionary:
	if no <= 0:
		return {}
	for m in sm.get("monsters", []):
		var d: Dictionary = m
		if int(d.get("id", -1)) != no:
			continue
		var out := {"id": no, "name": String(d.get("name", "")),
			"level": level if level > 0 else int(d.get("level", 50)),
			"element": "none", "boss": true,
			"hp_max": int(d.get("hp_max", 1)), "att": int(d.get("att", 1)),
			"def": int(d.get("def", 1))}
		if int(d.get("pure", 0)) > 0:
			out["pure"] = int(d.get("pure", 0))
		return out
	for sid in st.keys():
		var s: Dictionary = st[sid]
		for blk in [s, s.get("night"), s.get("kades")]:
			if typeof(blk) != TYPE_DICTIONARY:
				continue
			for e in (blk as Dictionary).get("enemies", []):
				var er: Dictionary = e
				if int(er.get("id", -1)) != no:
					continue
				var cp: Dictionary = er.duplicate(true)
				if level > 0:
					cp["level"] = level
				cp["boss"] = true
				return cp
	return {}


func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}
