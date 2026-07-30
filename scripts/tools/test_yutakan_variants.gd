extends SceneTree
## 유타칸 변형 던전(밤 501~514 · 카데스 601~614) 스모크.
##   godot --path . --headless --script res://scripts/tools/test_yutakan_variants.gd
## 검증: 변형 필드 12+12 존재 · 배경 파일 존재 · 전용 몬스터만 등장 · 카데스 보스 레벨/스탯 곡선.

const NIGHT_FIELDS := [1, 2, 3, 4, 5, 7, 9, 10, 11, 12, 13, 14]
const NIGHT_RANDOM_IDS := [160, 161, 162, 175]
## `--script` 실행에선 오토로드가 **컴파일 시점에 이름으로 안 보인다**(런타임엔 붙어 있다)
## → 첫 프레임에 `/root/Data` 를 잡아 쓴다.
var Data: Node

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	Data = get_root().get_node_or_null("/root/Data")
	if Data == null:
		print("FAIL: /root/Data 오토로드 없음"); quit(1); return
	var fail := 0
	print("── 변형 필드 매핑 (원작 WorldMapPopupLayer::init) ──")
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
		# 레벨곡선 검증 — Lv.120 에서의 hp 배수를 낮 스탯에 적용한 값
		var lv0: int = int((es[0] as Dictionary).get("level", 1)) if not es.is_empty() else 1
		var hp0: int = int((es[0] as Dictionary).get("hp_max", 0)) if not es.is_empty() else 0
		var m := Kades.boss_stat_mult(Data.kades, "hp", 120, lv0)
		print("  %d %-14s bg=%s 보스#%d=%s  낮 Lv%d hp%d → Lv120 hp%d (×%.2f)" % [600 + f,
			String(st.get("name", "?")), "O" if ok_bg else "X", want_id, "O" if ok else "X",
			lv0, hp0, int(round(hp0 * m)), m])

	print("── 변형 없는 필드(6·8·15)는 500/600 대를 만들지 않는다 ──")
	for f in [6, 8, 15]:
		for off in [500, 600]:
			var st: Dictionary = Data.stage(str(off + f))
			if not st.is_empty():
				print("  ✗ %d 이 생성됨" % (off + f)); fail += 1
	print("  ok" if fail == 0 else "  ✗ (위 실패 포함)")

	print("\n%s (실패 %d)" % ["PASS" if fail == 0 else "FAIL", fail])
	quit(0 if fail == 0 else 1)
