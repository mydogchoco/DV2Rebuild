extends SceneTree
## 헤드리스 검증 — **획득 공개 팝업**(원작 `ShowGetItemDetailLayer`)이 의지하는 계약.
## 실행: godot --headless --path <proj> --script res://scripts/tools/test_get_item_popup.gd
##
## `GetItemPopup.resolve()` 자체는 `Data`/`Icons`(오토로드·render)를 쓰므로 `--script` 단독
## 모드에서 부를 수 없다(다른 테스트들도 같은 이유로 JSON 을 직접 읽는다). 그래서 여기서는
##   ① resolve 가 분기 근거로 삼는 **가상 키 파서 계약**(gem/equip/egg/skill)
##   ② 각성마석 성공 팝업이 그릴 **마석 아이콘의 실재**
## 를 지킨다. 배치·연출·아이콘 표시는 스크린샷으로 검수했다
## (`scratch_shots/getitem1.png` 단건 · `getitem3.png` 3건 원형 · `getitem_all.png` 키 5종).

const GEM := preload("res://scripts/systems/gem.gd")
const EQ := preload("res://scripts/systems/equipment.gd")
const EGG := preload("res://scripts/systems/egg_gacha.gd")
const LO := preload("res://scripts/systems/loadout.gd")
const AWS := preload("res://scripts/systems/awaken_stone.gd")

func _init() -> void:
	var fails := 0
	var items: Dictionary = _load("res://data/items.json")
	var gems: Dictionary = _load("res://data/gems.json")
	var equip: Dictionary = _load("res://data/equipment.json")
	var dragons_raw = _load_any("res://data/dragons.json")

	# ── ① 가상 키 파서 — resolve 의 분기 순서가 서로 겹치지 않아야 한다 ──────
	var gname := _first_key(gems.get("gems", {}))
	fails += _true("젬 표 있음", gname != "")
	var gk := "gem:%s:6" % gname
	fails += _true("젬 키를 젬으로 인식", not GEM.parse_item_key(gk).is_empty())
	fails += _eq("젬 키는 장비가 아니다", EQ.parse_item_key(gk), "")
	fails += _true("젬 키는 스킬이 아니다", LO.parse_item_key(gk).is_empty())
	fails += _eq("젬 이름이 키가 아니다에 필요한 표",
		GEM.display_name(gname, 6, gems).is_empty(), false)

	var ck := _first_key(EQ.catalog(equip))
	fails += _true("장비 카탈로그 있음", ck != "")
	var ek := EQ.item_key(ck)
	fails += _eq("장비 키 왕복", EQ.parse_item_key(ek), ck)
	fails += _true("장비 키는 젬이 아니다", GEM.parse_item_key(ek).is_empty())

	fails += _eq("알 키 → 드래곤 id", EGG.dragon_of("egg:1"), 1)
	fails += _eq("알이 아닌 키는 0", EGG.dragon_of("heal_potion1"), 0)

	var sk := LO.parse_item_key("skill:11:1")
	fails += _true("스킬 키 파싱", not sk.is_empty())
	fails += _eq("스킬 id", int(sk.get("id", 0)), 11)
	fails += _eq("스킬 레벨", int(sk.get("level", 0)), 1)
	fails += _true("평범한 아이템은 가상 키가 아니다",
		GEM.parse_item_key("heal_potion1").is_empty()
		and EQ.parse_item_key("heal_potion1") == ""
		and LO.parse_item_key("heal_potion1").is_empty()
		and EGG.dragon_of("heal_potion1") == 0)
	fails += _true("평범한 아이템은 items.json 에 있다", items.has("heal_potion1"))

	# ── ② 각성마석 성공 팝업이 그리는 마석 아이콘 ──────────────────────────
	#     원작 `MakeMasicStonePopup` 은 만든 마석을 창 중앙에 그린다 — 아이콘이 없으면 빈 창.
	for star in [3, 4, 5, 6]:
		var key: String = AWS.reward_key(star)
		fails += _true("%d성 마석 키" % star, key != "")
		fails += _true("%d성 마석이 items.json 에 있다(%s)" % [star, key], items.has(key))
		var ico := String((items.get(key, {}) as Dictionary).get("icon", ""))
		fails += _true("%d성 마석 아이콘 키(%s)" % [star, ico], ico != "")
		var p := "res://assets/converted/%s.tres" % ico
		fails += _true("%d성 마석 아이콘 실존(%s)" % [star, p], ResourceLoader.exists(p))

	# ── ③ 팝업이 쓰는 원작 프레임이 변환돼 있나 ───────────────────────────
	# (`common_eggclass` 는 개수 근거가 없어 미이식 — 프레임 검사도 빼 둔다.)
	for f in ["common_backlight3", "common_check_btn", "common_coin", "common_diamond"]:
		fails += _true("프레임 %s" % f,
			ResourceLoader.exists("res://assets/converted/common_ui/%s.tres" % f))

	if dragons_raw == null:
		fails += _true("dragons.json 로드", false)

	if fails == 0:
		print("[test_get_item_popup] ✅ ALL PASS")
	else:
		print("[test_get_item_popup] ❌ %d FAIL" % fails)
	quit(1 if fails > 0 else 0)

func _first_key(d: Dictionary) -> String:
	for k in d:
		return String(k)
	return ""

func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}

func _load_any(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())

func _eq(label: String, got, want) -> int:
	if got == want:
		return 0
	print("  FAIL %s: got %s want %s" % [label, str(got), str(want)])
	return 1

func _true(label: String, ok: bool) -> int:
	if ok:
		return 0
	print("  FAIL %s" % label)
	return 1
