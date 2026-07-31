extends Node
## 헤드리스 검증 — **입수 경로 제한** 두 건(사용자 확정 2026-07-30).
##
##   ① 아이콘 프레임이 없는 장비는 구현에서 제외한다 — **카탈로그 전 항목이 텍스처를 가져야** 한다.
##      🟢 2026-07-31: 이벤트 19 · 특수 12 의 원본 아이콘을 위키 PDF 에서 복원해
##      (`extract_equip_icons.py`) 이제 이벤트 25/25 · 특수 12/12 가 전부 카탈로그에 있다.
##      규칙은 그대로 두고 기대값만 올렸다 — 아이콘을 잃으면 다시 빨간불이 켜진다.
##   ② 커스텀 세대(600·700·666·777)는 지정 획득처 전용
##      (소환·카드 코드로만 — 가챠·부화·조합 등 **무작위 풀에는 절대** 들어가면 안 된다)
##
## `--script` 모드가 이 환경에서 멈추므로([[dv2-godot-runtime-and-validation]]) 오토로드로 붙여
## 부팅 경로에서 돌린다:
##   project.godot [autoload] 에 `TestAcquireLocks="*res://scripts/tools/test_acquire_locks.gd"`
##   → Godot --path . --headless --quit-after 20 → 확인 후 그 줄 삭제.

const EQ := preload("res://scripts/systems/equipment.gd")
const DR := preload("res://scripts/systems/drops.gd")
const EG := preload("res://scripts/systems/egg_gacha.gd")

const LOCKED := [600, 700, 666, 777]

var _log: FileAccess = null

func _ready() -> void:
	_log = FileAccess.open("user://test_acquire_locks.txt", FileAccess.WRITE)
	var fails := 0
	fails += _compiles()
	fails += _equipment_icons()
	fails += _dragon_locks()
	_say("")
	_say("=== %s ===" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	if _log:
		_log.flush()

# ── ⓪ 이 변경이 건드린 화면 스크립트가 실제로 컴파일되는가 ───────────────────
## `--check-only --script` 단독 모드는 오토로드(UserDB/Data/Bgm)를 모르고 가짜 에러를 낸다
## ([[dv2-godot-runtime-and-validation]]). 부팅 경로에서 load() 하면 진짜 판정이 나온다.
func _compiles() -> int:
	var fails := 0
	_say("[컴파일] 수정한 화면 스크립트")
	for p in ["res://scripts/ui/shop.gd", "res://scripts/ui/breeding.gd",
			"res://scripts/ui/cave.gd", "res://scripts/tools/test_equipment.gd"]:
		fails += _true(String(p).get_file(), load(String(p)) != null)
	return fails

# ── ① 아이콘 없는 장비 = 구현 제외 ───────────────────────────────────────────
func _equipment_icons() -> int:
	var fails := 0
	_say("[장비] 아이콘 미보유분 제외")
	var cat: Dictionary = EQ.catalog(Data.equipment)
	var ev_all: int = (Data.equipment.get("event", []) as Array).size()
	var ev_on: int = EQ.event_pool(Data.equipment).size()
	fails += _eq("이벤트 장비 원본 25종", ev_all, 25)
	# 🟢 2026-07-31: 위키 PDF 에서 원본 아이콘을 복원해 25종 전부 구현 대상이 됐다
	#    (2026-07-30 에는 6종이었다 — `extract_equip_icons.py`).
	fails += _eq("그중 구현 25종(아이콘 보유분)", ev_on, 25)
	fails += _true("특수 장비 계열도 복원됨", cat.has("special:balrog:카이저 발록의 팔찌"))

	# 카탈로그 **전 항목**이 실제 텍스처를 갖는지 — 유령 장비가 하나도 없어야 한다.
	var noicon: Array = []
	for k in cat:
		if Icons.equip_texture(cat[k]) == null:
			noicon.append(String(k))
	fails += _eq("카탈로그 전체가 아이콘 보유", noicon.size(), 0)
	if not noicon.is_empty():
		_say("      아이콘 없음: %s" % str(noicon.slice(0, 8)))

	# 가챠가 뽑아 오는 것도 전부 카탈로그 안이어야 한다(= 아이콘 보유).
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260730
	var ghost := 0
	for _i in 3000:
		var key := DR.roll_equip_gacha(Data.drops, Data.equipment, rng)
		var ck := EQ.parse_item_key(key)
		if ck == "" or not cat.has(ck):
			ghost += 1
	fails += _eq("장신구 뽑기 3000회 중 카탈로그 밖 = 0", ghost, 0)
	# 전용 장신구 뽑기(30다이아) — 🟢 2026-07-31 복구. 결과는 **전용 장비만** 나와야 하고,
	# 반대로 일반/고급 상품에는 전용 장비가 섞이면 안 된다(풀이 갈려 있다).
	var only_bad := 0
	var only_ok := 0
	for _i in 500:
		var ck2 := EQ.parse_item_key(DR.roll_equip_gacha(Data.drops, Data.equipment, rng, "only"))
		var it2: Dictionary = cat.get(ck2, {})
		if String(it2.get("group", "")) == "exclusive":
			only_ok += 1
		else:
			only_bad += 1
	fails += _eq("전용 뽑기 500회가 전부 전용 장비", only_bad, 0)
	fails += _true("전용 뽑기가 실제로 나온다 (%d건)" % only_ok, only_ok > 0)
	var leak := 0
	for _i in 1000:
		for gid in ["normal", "high"]:
			var ck3 := EQ.parse_item_key(DR.roll_equip_gacha(Data.drops, Data.equipment, rng, gid))
			if String((cat.get(ck3, {}) as Dictionary).get("group", "")) == "exclusive":
				leak += 1
	fails += _eq("일반·고급 뽑기에 전용 장비 누출 = 0", leak, 0)
	fails += _grade_split(cat, rng)
	return fails

## 🔴 상품 등급별 풀 분리 — 종전엔 shop.json 의 `grade` 를 안 읽어 셋이 같은 결과였다.
##   일반(5000골드) = 하위 등급 일반 장비만 · 희귀도 일반 100%
##   고급(15다이아) = 상위 등급 일반 장비 + 이벤트 장비 · 레어~에픽
func _grade_split(cat: Dictionary, rng: RandomNumberGenerator) -> int:
	var fails := 0
	_say("[장신구 뽑기] 상품 등급별 풀")
	var stat := {"normal": {"ev": 0, "gmax": -1, "rar": 0}, "high": {"ev": 0, "gmin": 99, "rar_lo": 0}}
	for _i in 3000:
		for gid in ["normal", "high"]:
			var key := DR.roll_equip_gacha(Data.drops, Data.equipment, rng, String(gid))
			var ck := EQ.parse_item_key(key)
			if ck == "":
				continue
			var meta := EQ.item_key_meta(key)
			var grade := int((cat.get(ck, {}) as Dictionary).get("grade", -1))
			var s: Dictionary = stat[gid]
			if ck.begins_with("event:"):
				s["ev"] = int(s["ev"]) + 1
			if gid == "normal":
				s["gmax"] = maxi(int(s["gmax"]), grade)
				if int(meta.get("rarity", 0)) != 0:
					s["rar"] = int(s["rar"]) + 1
			else:
				if grade >= 0:
					s["gmin"] = mini(int(s["gmin"]), grade)
				if int(meta.get("rarity", 0)) < 2:
					s["rar_lo"] = int(s["rar_lo"]) + 1
	fails += _eq("일반: 이벤트 장비 0건", int(stat["normal"]["ev"]), 0)
	fails += _eq("일반: 최고 등급 3 이하", int(stat["normal"]["gmax"]), 3)
	fails += _eq("일반: 희귀도는 전부 일반", int(stat["normal"]["rar"]), 0)
	fails += _true("고급: 이벤트 장비가 나온다 (%d건)" % int(stat["high"]["ev"]),
		int(stat["high"]["ev"]) > 0)
	fails += _true("고급: 일반 장비 최저 등급 4 이상 (실측 %d)" % int(stat["high"]["gmin"]),
		int(stat["high"]["gmin"]) >= 4)
	fails += _eq("고급: 레어 미만 0건", int(stat["high"]["rar_lo"]), 0)
	# 🟢 2026-07-31 복구: '전용' 등급은 이제 실제로 전용 장비를 준다(빈 결과면 재화만 빠진다).
	fails += _true("only 등급이 결과를 준다",
		DR.roll_equip_gacha(Data.drops, Data.equipment, rng, "only").length() > 0)
	# 상점 진열에도 전용 상품 2줄(1회·x10)이 있어야 한다.
	var only_left := 0
	for t in (Data.shop.get("tabs", []) as Array):
		for g in ((t as Dictionary).get("gacha", []) as Array):
			if String((g as Dictionary).get("grade", "")) == "only":
				only_left += 1
	fails += _eq("상점에 전용 뽑기 상품 2개", only_left, 2)
	return fails

# ── ② 커스텀 세대 = 지정 획득처 전용 ─────────────────────────────────────────
func _dragon_locks() -> int:
	var fails := 0
	_say("[드래곤] 커스텀 세대 무작위 입수 차단")
	for id in LOCKED:
		fails += _true("%d 은 acquire_locked" % id, Data.dragon_acquire_locked(int(id)))

	var pool: Array = Data.dragon_ids_random()
	var leak: Array = []
	for id in LOCKED:
		if pool.has(int(id)):
			leak.append(int(id))
	fails += _eq("dragon_ids_random() 누출 = 0", leak.size(), 0)
	fails += _true("도감 목록엔 666·777 이 남아 있다",
		Data.dragon_ids().has(666) and Data.dragon_ids().has(777))

	# 가챠 알 후보(성급·속성 전 조합)에 하나라도 있으면 안 된다.
	var cand_leak: Array = []
	for star in [2, 3, 4, 5, 6]:
		for el in ["", "fire", "aqua", "wind", "earth", "light", "dark", "holy", "chaos"]:
			for id in EG.candidates(Data.dragons, int(star), String(el), {}, []):
				if LOCKED.has(int(id)):
					cand_leak.append(int(id))
	fails += _eq("EggGacha.candidates 누출 = 0", cand_leak.size(), 0)

	# 실제 개봉 표본 — 빛문알(4~6성)은 종전에 666·777 이 나오던 경로다.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260730
	var hit := 0
	var rolled := 0
	for key in ["mall_question_egg", "mall_question_egg2"]:
		var item: Dictionary = Data.items.get(key, {})
		for _i in 3000:
			var did := EG.roll(key, item, Data.gacha_eggs, Data.dragons, rng)
			if did > 0:
				rolled += 1
			if LOCKED.has(did):
				hit += 1
	fails += _true("개봉 표본 %d회 정상" % rolled, rolled > 5000)
	fails += _eq("의문의 알/빛문알 개봉에서 커스텀 종 = 0", hit, 0)
	return fails

# ── 보조 ────────────────────────────────────────────────────────────────────
func _eq(label: String, got: int, want: int) -> int:
	var ok := got == want
	_say("  %s %s: %d (기대 %d)" % ["OK " if ok else "FAIL", label, got, want])
	return 0 if ok else 1

func _true(label: String, ok: bool) -> int:
	_say("  %s %s" % ["OK " if ok else "FAIL", label])
	return 0 if ok else 1

func _say(s: String) -> void:
	print(s)
	if _log:
		_log.store_line(s)
