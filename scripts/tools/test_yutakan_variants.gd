extends SceneTree

const NIGHT_FIELDS := [1, 2, 3, 4, 5, 7, 9, 10, 11, 12, 13, 14]
const NIGHT_RANDOM_IDS := [160, 161, 162, 175]
var Data: Node

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	Data = get_root().get_node_or_null("/root/Data")
	if Data == null:
		print("FAIL: /root/Data 오토로드 없음"); quit(1); return
	var fail := 0
	print("── 변형 필드 매핑 (원작 동작 대조) ──")
	for f in range(1, 16):
		var n := DungeonBG.variant_field(f, true, false)
		var k := DungeonBG.variant_field(f, false, true)
		var want := f in NIGHT_FIELDS
		if want != (n == 500 + f) or want != (k == 600 + f):
			print("  ✗ field %d: night=%d kades=%d (변형 %s)" % [f, n, k, want]); fail += 1
	print("  변형 있는 필드 %d종 (기대 12)" % NIGHT_FIELDS.size())

	print("── 밤 던전 ──")
	for i in NIGHT_FIELDS.size():
		var f: int = NIGHT_FIELDS[i]
		var st: Dictionary = Data.stage(str(500 + f))
		var boss_id := 163 + i
		var ids: Array = []
		for e in st.get("enemies", []):
			ids.append(int((e as Dictionary).get("id", 0)))
		var ok_boss: bool = ids.size() > 0 and ids[0] == boss_id
		var ok_pool := true
		for r in NIGHT_RANDOM_IDS:
			if not ids.has(r):
				ok_pool = false
		var bgp := "res://assets/converted/adventure_bg/bg_%d.jpg" % (500 + f)
		var ok_bg := ResourceLoader.exists(bgp)
		var lv := int(st.get("level", 0))
		if not (ok_boss and ok_pool and ok_bg and lv == 50 and bool(st.get("random_boss", false))):
			fail += 1
		print("  %d %-14s bg=%s lv=%d 보스#%d=%s 랜덤4=%s 편성%s" % [500 + f,
			String(st.get("name", "?")), "O" if ok_bg else "X", lv, boss_id,
			"O" if ok_boss else "X(%s)" % str(ids), "O" if ok_pool else "X",
			" ⚠상속" if st.has("_inherited") else ""])
	var kibo: Dictionary = Data.stage("510").get("enemies", [])[0]
	var tubaro: Dictionary = Data.stage("511").get("enemies", [])[0]
	if int(kibo.get("id", 0)) != 170 or int(kibo.get("asset_id", 0)) != 171:
		print("  ✗ 키보 논리#170 → 스파인#171 매핑 실패"); fail += 1
	if int(tubaro.get("id", 0)) != 171 or int(tubaro.get("asset_id", 0)) != 170:
		print("  ✗ 투바로 논리#171 → 스파인#170 매핑 실패"); fail += 1

	print("── 카데스 던전 ──")
	var rng := RandomNumberGenerator.new()
	for i in NIGHT_FIELDS.size():
		var f: int = NIGHT_FIELDS[i]
		var st: Dictionary = Data.stage(str(600 + f))
		var want_id := 182 + i
		var es: Array = st.get("enemies", [])
		var ok := es.size() == 1 and int((es[0] as Dictionary).get("id", 0)) == want_id \
			and bool((es[0] as Dictionary).get("boss", false))
		var ok_bg := ResourceLoader.exists("res://assets/converted/adventure_bg/bg_%d.jpg" % (600 + f))
		if not (ok and ok_bg):
			fail += 1
		var lv0: int = int((es[0] as Dictionary).get("level", 1)) if not es.is_empty() else 1
		var hp0: int = int((es[0] as Dictionary).get("hp_max", 0)) if not es.is_empty() else 0
		var m := Kades.boss_stat_mult(Data.kades, "hp", 120, lv0)
		print("  %d %-14s bg=%s 보스#%d=%s  낮 Lv%d hp%d → Lv120 hp%d (×%.2f)" % [600 + f,
			String(st.get("name", "?")), "O" if ok_bg else "X", want_id, "O" if ok else "X",
			lv0, hp0, int(round(hp0 * m)), m])

	print("── 던전 속성 상속 · 정규화 ──")
	const CANON := ["earth", "aqua", "fire", "wind", "light", "dark", "holy", "chaos", "shadow"]
	for f in NIGHT_FIELDS:
		var day := Drops.normalize_element(Data.stage(str(f)).get("element", ""))
		var ni := Drops.normalize_element(Data.stage(str(500 + f)).get("element", ""))
		var ka := Drops.normalize_element(Data.stage(str(600 + f)).get("element", ""))
		var ok_same: bool = day == ni and day == ka
		var ok_canon: bool = CANON.has(day)
		if not (ok_same and ok_canon):
			fail += 1
		print("  %-3d %-14s %s (밤 %s / 카데스 %s)%s" % [f, String(Data.stage(str(f)).get("name", "?")),
			day, ni, ka, "" if (ok_same and ok_canon) else "  ✗"])

	print("── 변형 없는 필드(6·8·15)는 500/600 대를 만들지 않는다 ──")
	for f in [6, 8, 15]:
		for off in [500, 600]:
			var st: Dictionary = Data.stage(str(off + f))
			if not st.is_empty():
				print("  ✗ %d 이 생성됨" % (off + f)); fail += 1
	print("  ok" if fail == 0 else "  ✗ (위 실패 포함)")

	print("\n%s (실패 %d)" % ["PASS" if fail == 0 else "FAIL", fail])
	quit(0 if fail == 0 else 1)
