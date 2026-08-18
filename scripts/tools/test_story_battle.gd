extends SceneTree

const EXPECT := {
	26: ["심해 상어전사", 99],
	27: ["관문의 수호자", 99],
	28: ["관문의 수호자", 100],
	29: ["다크프로스티", 50],
	11: ["기계 만드라고낙", 50],
	12: ["정령 스파이크젤", 50],
	14: ["다크프로스티", 50],
	15: ["다크프로스티", 50],
	5: ["심벌 몽키", 22],
	6: ["모프된 가고일", 22],
	7: ["G스컬", 22],
	8: ["데스웜", 30],
	9: ["아이즈 데몬", 30],
	10: ["커터 크랩", 30],
	13: ["포사이트", 38],
	16: ["라이트 오브", 55],
	21: ["지반 다지기 기계", 25],
	22: ["타락한 불의 정령", 25],
	24: ["포마스", 50],
	25: ["고가", 50],
}

const WIRED := {
	19: [5, 6, 7], 22: [8], 24: [9, 10], 27: [11], 28: [12], 29: [13],
	32: [14], 33: [15], 46: [16], 48: [21], 53: [22], 59: [24], 62: [25],
	88: [26], 90: [27], 91: [28], 92: [29],
}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var fails := 0
	var sq: Dictionary = _json(_data_file("story_subquest.json"))
	var sb: Dictionary = _json(_data_file("story_battles.json"))
	var sm: Dictionary = _json(_data_file("story_monsters.json"))
	var st: Dictionary = _json(_data_file("stages.json")).get("stages", {})
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

	var dp: Dictionary = _resolve(15, sq, sb, sm, st)
	if int((dp.get("enemy", {}) as Dictionary).get("pure", 0)) != 1000:
		print("FAIL: 다크프로스티 pure 1000 이 안 실렸다"); fails += 1

	for pair in [[26, 602], [27, 24], [29, 601]]:
		var got := int(_resolve(int(pair[0]), sq, sb, sm, st).get("field", 0))
		if got != int(pair[1]):
			print("FAIL battle %d: 필드 %d != %d" % [pair[0], got, pair[1]]); fails += 1

	for bno in [11, 12, 14, 15, 5, 6, 7, 8, 9, 10, 13, 16, 21, 22, 24, 25]:
		if int(_resolve(int(bno), sq, sb, sm, st).get("field", 0)) <= 0:
			print("FAIL battle %d: 배경 던전(field) 이 비었다" % bno); fails += 1

	var flows: Dictionary = _json(_data_file("scenario_flow.json")).get("flows", {})
	var n_wired := 0
	for ep in WIRED.keys():
		var ops: Array = flows.get(str(ep), [])
		if ops.is_empty():
			print("FAIL ep%d: 흐름이 없다" % ep); fails += 1; continue
		var got: Array = []
		for o in ops:
			if String((o as Dictionary).get("op", "")) == "battle":
				got.append(int((o as Dictionary).get("battle", -1)))
		if got != Array(WIRED[ep]):
			print("FAIL ep%d: 배선 전투 %s != %s" % [ep, got, WIRED[ep]]); fails += 1
		n_wired += got.size()

	for c in sb.get("scene_calls", []):
		var cd: Dictionary = c
		if not cd.has("episode"):
			continue
		var ops2: Array = flows.get(str(int(cd["episode"])), [])
		var found := false
		for o in ops2:
			var od: Dictionary = o
			if String(od.get("op", "")) == "battle" and int(od.get("battle", -1)) == int(cd.get("battle_no", -1)):
				found = true; break
		if not found:
			print("FAIL: 전투 %d 이 %d화 흐름에 없다(scene_calls 는 그렇게 말한다)"
				% [int(cd.get("battle_no", -1)), int(cd["episode"])]); fails += 1

	var data := root.get_node_or_null("/root/Data")
	if data == null:
		print("FAIL: Data 오토로드 없음"); fails += 1
	else:
		for ep2 in WIRED.keys():
			for bno2 in WIRED[ep2]:
				var mine: Dictionary = _resolve(int(bno2), sq, sb, sm, st)
				var real: Dictionary = data.call("story_battle", int(bno2))
				if real.is_empty():
					print("FAIL battle %d: Data.story_battle 이 빈 값" % bno2); fails += 1
				elif int(real.get("field", -1)) != int(mine.get("field", -2)):
					print("FAIL battle %d: 필드 불일치 Data=%d 복제=%d"
						% [bno2, int(real.get("field", -1)), int(mine.get("field", -2))]); fails += 1
				elif String((real.get("enemy", {}) as Dictionary).get("name", "")) \
						!= String((mine.get("enemy", {}) as Dictionary).get("name", "")):
					print("FAIL battle %d: 몬스터 불일치" % bno2); fails += 1
				elif (real.get("enemy", {}) as Dictionary).has("_stage"):
					print("FAIL battle %d: 내부 채널 _stage 가 적 레코드에 샜다" % bno2); fails += 1

	print("[story_battle] 편성 %d건 · 흐름 배선 %d건(%d회차) 검증"
		% [EXPECT.size(), n_wired, WIRED.size()])
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit(0 if fails == 0 else 1)

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
		e0.erase("_stage")
		return {"enemy": e0, "field": int(ev.get("field_no", 0))}
	for tbl in ["monster_by_battle_event", "monster_by_battle"]:
		var rec: Dictionary = sb.get(tbl, {}).get(key, {})
		if rec.is_empty():
			continue
		var e1: Dictionary = _enemy(int(rec.get("monster_no", 0)), int(rec.get("level", 0)), sm, st)
		if not e1.is_empty():
			var fld: int = int(e1.get("_stage", 0))
			e1.erase("_stage")
			return {"enemy": e1, "field": fld}
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
		if int(d.get("stage", 0)) > 0:
			out["_stage"] = int(d.get("stage", 0))
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
				if int(sid) > 0:
					cp["_stage"] = int(sid)
				return cp
	return {}

func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
