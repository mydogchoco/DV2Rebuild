extends SceneTree
## 헤드리스 Field(던전 정의) 데이터-무결성 검증 (§10 data층).
## 원작 근거: docs/ref/orig_code/decomp/Field.c — 필드 {no, attribute, name, desc, levelMin, levelMax,
##   dragonArr, soundPath, openScenarioNum} (getAttribute/getName/getLevelMin/getLevelMax/
##   getDragonArr/getSoundPath/getOpenScenarioNum + setInfo). 원작 setInfo가 서버/DB에서 파싱.
## 검증: 우리 data/stages.json이 Field의 **오프라인 재현 대상 필드**(name/level/enemies)를 전 던전에
##   대해 완비하는지. ⚠️ 유실: soundPath(던전BGM)·dragonArr(등장드래곤)·field-attribute = 서버소실
##   ([[dv2-bgm-system]] getSoundPath, [[dv2-authored-data-files]]) → 데이터트랙/사용자 대상.
## 실행: godot --headless --path <proj> --script res://scripts/tools/test_field.gd

func _init() -> void:
	var fails := 0
	var f := FileAccess.open("res://data/stages.json", FileAccess.READ)
	var raw = JSON.parse_string(f.get_as_text()) if f else {}
	var stages: Dictionary = {}
	if typeof(raw) == TYPE_DICTIONARY:
		stages = raw.get("stages", raw)
	fails += _b("stages 로드", stages.size() >= 1)

	var checked := 0
	var lost_present := 0
	for sid in stages.keys():
		if String(sid).begins_with("_"):
			continue   # 메타키 스킵
		var st = stages[sid]
		if typeof(st) != TYPE_DICTIONARY:
			continue
		# Field.name(getName): 이름 필수·비어있지 않음
		fails += _b("st[%s].name" % sid, String(st.get("name", "")).strip_edges() != "")
		# Field.levelMin/Max(getLevelMin/Max): 레벨 유효(>0)
		fails += _b("st[%s].level>0" % sid, _num(st.get("level", 0)) > 0.0)
		# Field는 던전 조우(enemies) 정의를 가짐 — 최소 1 적, 각 적 유효(id/hp)
		var enemies = st.get("enemies", [])
		fails += _b("st[%s].enemies>=1" % sid, typeof(enemies) == TYPE_ARRAY and enemies.size() >= 1)
		if typeof(enemies) == TYPE_ARRAY:
			for e in enemies:
				if typeof(e) != TYPE_DICTIONARY:
					fails += _b("st[%s] enemy dict" % sid, false)
					continue
				fails += _b("st[%s] enemy id>0" % sid, _num(e.get("id", 0)) > 0.0)
				fails += _b("st[%s] enemy hp>0" % sid, _num(e.get("hp_max", 0)) > 0.0)
		if st.has("soundPath") or st.has("dragonArr"):
			lost_present += 1
		checked += 1

	print("[test_field] Field 오프라인필드 검증: %d 던전(name/level/enemies 완비). 유실필드(soundPath/dragonArr) 보유 %d(0 정상)" % [checked, lost_present])

	if fails == 0:
		print("[test_field] ALL PASS")
	else:
		printerr("[test_field] %d FAIL" % fails)
	quit(0 if fails == 0 else 1)

func _num(v) -> float:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT:
			return float(v)
		TYPE_STRING:
			return float(v) if (v as String).is_valid_float() else 0.0
	return 0.0

func _b(tag: String, cond: bool) -> int:
	if cond:
		return 0
	printerr("FAIL %s" % tag)
	return 1
