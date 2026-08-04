extends SceneTree
## 헤드리스 검증 — **로키(도감 800) 드빌1 에셋 이식**.
## 실행: godot --headless --path <proj> --script res://scripts/tools/test_loki800.gd
##
## 무엇을 지키나 (전부 이번 이식에서 실제로 한 번씩 깨졌던 것들이다):
##   ① 스파인 씬 5단계가 **텍스처를 물고** 있나 — 절대경로를 넘겨 `res://C:/…` 가 박히는 바람에
##      ext_resource 0개짜리 씬이 만들어져 화면에 아무것도 안 그려진 적이 있다.
##   ② 우리 렌더가 부르는 애니(`wait`/`love`/`attack`)가 다섯 단계에 다 있나.
##   ③ 초상 7키(알·알소·해치·해츨링·성체·**오라**·각성) + 도감 6칸 판정.
##   ④ 크리티컬 컷인 2키 — `cutin.gd` 가 이름으로만 찾으므로 키가 곧 배선이다.
##   ⑤ 이펙트 30프레임 + **트림 오프셋**이 실려 있나(전부 0 이면 재생 중 중심이 흔들린다).
##   ⑥ 데이터 — 드래곤 레코드·각성스킬 800(트릭스터)·배정표.
const DID := 800
## `advent`(강림) 은 성장 단계가 아니라 **레이드용 일러**다(`계획 및 아이디어.txt:2`).
## 우리 레이드 화면이 아직 없어 읽는 곳은 없지만, 구워 둔 것이 성장 단계와 같은 규약
## (텍스처 물림 + wait/love/attack)을 지키는지는 여기서 같이 못박는다.
const STAGES := ["baby", "child", "adult", "aura", "e", "advent"]

func _init() -> void:
	var fails := 0

	# ── ① 스파인 씬 5단계 + 텍스처 참조 ────────────────────────────────────
	for st in STAGES:
		var p := "res://scenes/dragons/dragon_%d_%s.tscn" % [DID, st]
		if not _true("씬 존재 %s" % st, ResourceLoader.exists(p)) == 0:
			fails += 1
			continue
		var ps := load(p) as PackedScene
		if ps == null:
			fails += _true("씬 로드 %s" % st, false)
			continue
		var inst := ps.instantiate()
		var spr := _count_textured(inst)
		fails += _true("%s 텍스처 물린 스프라이트 > 0 (실제 %d)" % [st, spr], spr > 0)
		inst.queue_free()

	# ── ② 우리 렌더가 부르는 애니가 다 있나 ────────────────────────────────
	#   `wait`  = 어디서나 기본 · `love` = 동굴 터치(cave.gd) · `attack` = 콜로세움(fight.gd)
	for st in STAGES:
		var p := "res://scenes/dragons/dragon_%d_%s.tscn" % [DID, st]
		if not ResourceLoader.exists(p):
			continue
		var inst := (load(p) as PackedScene).instantiate()
		var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		if ap == null:
			fails += _true("%s AnimationPlayer" % st, false)
			inst.queue_free()
			continue
		for an in ["wait", "love", "attack"]:
			fails += _true("%s 애니 '%s'" % [st, an], ap.has_animation(an))
		# 저작 모션은 길이가 있어야 한다(0 이면 키가 안 들어간 것)
		for an in ["love", "attack"]:
			if ap.has_animation(an):
				fails += _true("%s '%s' 길이>0" % [st, an], ap.get_animation(an).length > 0.1)
		inst.queue_free()

	# ── ③ 초상 + 도감 단계 ─────────────────────────────────────────────────
	var por := _load("res://assets/converted/portrait_%d/_manifest.json" % DID)
	for k in ["egg", "egg_small", "box_baby", "box_child", "box_adult", "box_aura",
			"box_evolution"]:
		fails += _true("초상 키 %s" % k, por.has("dragon_dragon_%d_%s" % [DID, k]))
	var meta := _load("res://data/dex_meta.json")
	var m800: Dictionary = meta.get(str(DID), {})
	fails += _true("dex_meta 800 존재", not m800.is_empty())
	fails += _true("도감 6칸(evo=true)", bool(m800.get("evo", false)))

	# ── ④ 크리티컬 컷인 — `cutin.gd::show` ③ 이 이 키로 찾는다 ─────────────
	var cri := _load("res://assets/converted/critical_%d/_manifest.json" % DID)
	for k in ["cut_in", "e_cut_in"]:
		fails += _true("컷인 키 %s" % k, cri.has("dragon_dragon_%d_critical_%s" % [DID, k]))

	# ── ⑤ 이펙트 프레임 + 트림 오프셋 ──────────────────────────────────────
	var fx := _load("res://assets/converted/dragon_%d_fx/_manifest.json" % DID)
	var adv := 0
	var col1 := 0
	var col2 := 0
	var nonzero_off := 0
	for k in fx:
		var s := String(k)
		if s.begins_with("dragon_%d_adv_action" % DID): adv += 1
		elif s.begins_with("dragon_%d_col_action1_" % DID): col1 += 1
		elif s.begins_with("dragon_%d_col_action2_" % DID): col2 += 1
		var off: Array = (fx[k] as Dictionary).get("off", [0, 0])
		if int(off[0]) != 0 or int(off[1]) != 0:
			nonzero_off += 1
	fails += _eq("탐험 이펙트(adv_action)", adv, 2)
	fails += _eq("콜로세움 평타(col_action1)", col1, 12)
	fails += _eq("콜로세움 크리(col_action2)", col2, 16)
	# 🔴 회귀 방지: plist 키가 `spriteOffset` 인데 `offset` 으로 읽어 **전부 0** 이었다.
	fails += _true("트림 오프셋이 실렸다(0 아닌 프레임 %d개)" % nonzero_off, nonzero_off > 10)
	# col_action 은 원본 캔버스 800×480 을 유지해야 정렬이 맞는다.
	# ⚠️ JSON 수치는 float 로 파싱된다 — 문자열로 비교하면 "[800.0, 480.0]" 이 되어 헛통과/헛실패한다.
	var any_col := fx.get("dragon_%d_col_action2_00" % DID, {}) as Dictionary
	var src: Array = any_col.get("src", [])
	fails += _eq("col_action 원본 캔버스 W", int(src[0]) if src.size() > 0 else 0, 800)
	fails += _eq("col_action 원본 캔버스 H", int(src[1]) if src.size() > 1 else 0, 480)

	# ── ⑥ 데이터 ───────────────────────────────────────────────────────────
	var dragons := _load_arr("res://data/dragons.json")
	var d800 := {}
	for d in dragons:
		if int((d as Dictionary).get("id", 0)) == DID:
			d800 = d
	fails += _true("dragons.json 800 존재", not d800.is_empty())
	if not d800.is_empty():
		fails += _eq("이름", String(d800.get("name", "")), "로키")
		fails += _eq("속성", String(d800.get("element", "")), "chaos")
		fails += _eq("전투유형", String(d800.get("type", "")), "def")
		fails += _eq("스탯티어(6성 4세대)", String(d800.get("stat_tier", "")), "6b")
		fails += _eq("각성스킬", int(d800.get("awaken_skill", 0)), 800)
	var aw := _load("res://data/skill_awaken.json")
	var s800 := {}
	for s in (aw.get("skills", []) as Array):
		if int((s as Dictionary).get("no", 0)) == DID:
			s800 = s
	fails += _true("각성스킬 800 존재", not s800.is_empty())
	if not s800.is_empty():
		fails += _eq("각성스킬 이름", String(s800.get("name", "")), "트릭스터")
		var eff: Dictionary = s800.get("effect", {})
		fails += _true("각성스킬 효과 구현됨", bool(eff.get("impl", false)))
		fails += _eq("효과 연산 수", (eff.get("ops", []) as Array).size(), 6)
	var by800: Array = (aw.get("by_dragon", {}) as Dictionary).get("800", [])
	fails += _eq("배정표 by_dragon[800] 개수", by800.size(), 1)
	fails += _eq("배정표 by_dragon[800][0]", int(by800[0]) if by800.size() > 0 else 0, 800)

	# ── ⑦ 오라성체 전용 아트 게이트 ────────────────────────────────────────
	# 🟦 사용자 확정 2026-08-04: 로키는 오라성체가 **별도 아트**(드빌1 `transcended`)다.
	# 원작 규칙(오라성체 = 성체 그림 + 오라 이펙트)은 **건드리지 않았다** — `Growth` 는 그대로고,
	# 렌더가 `dragon_<id>_aura.tscn` 이 **있을 때만** 갈아탄다(`cave.gd::_aura_spine_stage`).
	# 여기서 지키는 것 = 그 게이트가 로키에게만 열리고 나머지 종은 예전 경로 그대로라는 것.
	fails += _eq("원작 규칙 불변: Lv45 도 stage_for_level 은 adult",
			Growth.stage_for_level(45), "adult")
	fails += _true("Lv45 = 오라성체 판정", Growth.is_aura_adult(45))
	fails += _true("로키는 오라 전용 씬 보유(게이트 열림)",
			ResourceLoader.exists("res://scenes/dragons/dragon_800_aura.tscn"))
	var other_aura := 0
	for did in [1, 10, 100, 3001, 4000]:
		if ResourceLoader.exists("res://scenes/dragons/dragon_%d_aura.tscn" % did):
			other_aura += 1
	fails += _eq("다른 종은 오라 전용 씬 없음(경로 불변)", other_aura, 0)
	fails += _true("로키 오라 초상 보유", por.has("dragon_dragon_%d_box_aura" % DID))

	# ── ⑧ 저작 모션은 눈을 감는다 (🟦 사용자 확정 2026-08-04) ──────────────────
	# `love`/`attack` 은 감은 눈 파츠로 간다. 원본 `wait` 은 깜빡임이라 **뜬 눈이 정상**이고,
	# 원본 `att` 포즈도 눈을 뜨고 있다 — 즉 이건 의도적 변경이라 여기서 고정해 둔다.
	# 눈 파츠 이름 규약(원본 아틀라스 실측): eye1=뜬 눈 · eye2=반쯤 · eye3(child/adult=eye4)=감은 눈.
	var eyes := {
		"baby": ["eye1__eye1", "eye1__eye3"],
		"child": ["eye1__eye1", "eye1__eye4"],
		"adult": ["eye1__eye1", "eye1__eye4"],
		"aura": ["eye1__eye1", "eye1__eye3"],
		"advent": ["eye1__eye1", "eye1__eye3"],
		"e": ["eye1_slot", "eye3"],
	}
	for st in STAGES:
		var p := "res://scenes/dragons/dragon_%d_%s.tscn" % [DID, st]
		if not ResourceLoader.exists(p):
			continue
		var pair: Array = eyes[st]
		for an in ["love", "attack"]:
			var inst := (load(p) as PackedScene).instantiate()
			var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
			if ap == null or not ap.has_animation(an):
				inst.queue_free()
				continue
			# 애니를 실제로 재생해 슬롯 트랙이 적용된 뒤의 상태를 본다.
			ap.play(an)
			ap.advance(ap.get_animation(an).length * 0.5)
			var opened := _find(inst, String(pair[0]))
			var closed := _find(inst, String(pair[1]))
			fails += _true("%s/%s 뜬 눈 스프라이트 존재" % [st, an], opened != null)
			fails += _true("%s/%s 감은 눈 스프라이트 존재" % [st, an], closed != null)
			if opened != null:
				fails += _true("%s/%s 뜬 눈 꺼짐" % [st, an], not opened.visible)
			if closed != null:
				fails += _true("%s/%s 감은 눈 켜짐" % [st, an], closed.visible)
				# 288 의 감은 눈은 셋업 색이 alpha 0 이라 visible 만으론 안 보인다.
				fails += _true("%s/%s 감은 눈 불투명" % [st, an], closed.modulate.a > 0.9)
			inst.queue_free()
		# `wait` 은 원본 깜빡임 그대로 — t=0 에서 눈을 뜨고 있어야 한다(회귀 감시).
		var iw := (load(p) as PackedScene).instantiate()
		var apw: AnimationPlayer = iw.get_node_or_null("AnimationPlayer")
		if apw != null and apw.has_animation("wait"):
			apw.play("wait")
			apw.advance(0.0)
			var ow := _find(iw, String(pair[0]))
			if ow != null:
				fails += _true("%s wait 은 원본대로 눈 뜸(t=0)" % st, ow.visible)
		iw.queue_free()

	print("\n=== test_loki800: %s ===" % ("PASS" if fails == 0 else "FAIL(%d)" % fails))
	quit(1 if fails > 0 else 0)


## 씬 안에서 **실제 텍스처가 물린** Sprite2D 개수(ext_resource 유실 회귀 감시).
func _count_textured(n: Node) -> int:
	var c := 0
	if n is Sprite2D:
		var t := (n as Sprite2D).texture
		if t is AtlasTexture and (t as AtlasTexture).atlas != null:
			c += 1
		elif t != null and not (t is AtlasTexture):
			c += 1
	for ch in n.get_children():
		c += _count_textured(ch)
	return c


## 이름으로 CanvasItem 하나 찾기(스프라이트는 본 노드 밑에 흩어져 있다).
func _find(n: Node, name: String) -> CanvasItem:
	if n.name == name and n is CanvasItem:
		return n as CanvasItem
	for ch in n.get_children():
		var r := _find(ch, name)
		if r != null:
			return r
	return null


func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _load_arr(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Array else []


func _true(label: String, ok: bool) -> int:
	print("  %s %s" % ["OK  " if ok else "FAIL", label])
	return 0 if ok else 1


func _eq(label: String, got, want) -> int:
	var ok: bool = got == want
	print("  %s %s (got %s, want %s)" % ["OK  " if ok else "FAIL", label, str(got), str(want)])
	return 0 if ok else 1
