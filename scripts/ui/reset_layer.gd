class_name ResetLayer
extends Node
## 젬/스킬 슬롯 재추첨 결과 화면 — 원작 `ResetLayer` 1:1 이식. render 층(CLAUDE.md §8.1).
##
## 원작은 팝업이 아니라 **러닝 씬 위 z=1000 에 얹는 전체화면 `CCLayerColor`** 다
## (`BagPopup::onClickConfirm` 꼬리 → `ResetLayer::create(type)`).
## 근거·좌표·타임라인 전부 `docs/ref/porting/SlotResetScreens.md` §2 에 표로 남겨 뒀다.
## 참조 영상 프레임: `docs/ref/slotchange/젬슬롯변경1~7.png` · `스킬슬롯변경1~5.png`.
##
## 좌표 규약: 원작 리터럴은 cocos(y-up, 화면 좌하단 원점) **포인트**다(§9 — ASSET_SCALE 을
## 다시 곱하지 않는다). 여기서는 `_gp()` 로 y 만 뒤집어 그대로 쓴다.
##
## 사용:
##   ResetLayer.open(host, uid, "gem")            # 샌즈의 비약
##   ResetLayer.open(host, uid, "skill", on_close) # 다이즈의 호신부

# ---------- 원작 리터럴 ----------

## `initWidget` 의 content 슬라이드 — 시작 y = +H, `MoveBy(0.5, (0, −50−H))` ⇒ 최종 cocos y = −50.
const CONTENT_END_Y := -50.0
const SLIDE_SECS := 0.5
## 딤 `CCFadeTo(0.5, 200)`.
const DIM_ALPHA := 200.0 / 255.0
## 롤 갱신 주기 `schedule(random*Effect, 0.05)`.
const ROLL_TICK := 0.05
## 롤 시작 `CCDelayTime(0.3)` · 확정 `CCDelayTime(1.8)`.
const ROLL_START := 0.3
const ROLL_END := 1.8
## 흰 섬광 `Delay(1.5) → FadeIn(0.3) → Spawn(Delay(0.5), removeParticleEffect) → FadeOut(0.3)`.
const FLASH_DELAY := 1.5
const FLASH_IN := 0.3
const FLASH_HOLD := 0.5
const FLASH_OUT := 0.3

## 젬 칸 = `9patch/gem_*_bg` Scale9 capInsets `CCRect(20,20,2,2)`, `setContentSize(70,70)`.
const GEM_CAP := Rect2(20, 20, 2, 2)
const GEM_BOX := Vector2(70.0, 70.0)
const GEM_PITCH := 76.0
const SKILL_PITCH := 84.0
## 슬롯 줄 전체가 화면 중앙에서 오른쪽으로 200pt 밀려 있다(원작 `+ 200.0`).
const SLOT_DX := 200.0

## `Dragon::getGemType` 0..3 → 프레임. 우리 타입 어휘(gems.json slot_types)와 같은 순서.
const GEM_FRAME := {"ATT": "9patch_gem_red_bg", "DEF": "9patch_gem_blue_bg",
	"HP": "9patch_gem_yellow_bg", "ALL": "9patch_gem_white_bg"}
## `Dragon::getSkillType` 0..3 → 프레임.
const SKILL_FRAME := {"tri": "common_skill_triangle_bg", "sq": "common_skill_square_bg",
	"cir": "common_skill_circle_bg", "star": "common_skill_star_bg"}

## `randomGemEffect` 의 **연출용** 가중치 — `arc4random()%10`: 0~2 blue · 3~5 red · 6~8 yellow · 9 white.
## (실제 결과는 이미 확정돼 있고 이 표는 굴러가는 그림에만 쓴다.)
const GEM_ROLL_WEIGHT := ["9patch_gem_blue_bg", "9patch_gem_blue_bg", "9patch_gem_blue_bg",
	"9patch_gem_red_bg", "9patch_gem_red_bg", "9patch_gem_red_bg",
	"9patch_gem_yellow_bg", "9patch_gem_yellow_bg", "9patch_gem_yellow_bg",
	"9patch_gem_white_bg"]
## `randomSkillEffect` 도 같은 규칙 — 0~2 circle · 3~5 square · 6~8 triangle · 9 star.
const SKILL_ROLL_WEIGHT := ["common_skill_circle_bg", "common_skill_circle_bg", "common_skill_circle_bg",
	"common_skill_square_bg", "common_skill_square_bg", "common_skill_square_bg",
	"common_skill_triangle_bg", "common_skill_triangle_bg", "common_skill_triangle_bg",
	"common_skill_star_bg"]

## 성장 단계별 보정(`initWidget` ⑥) — {스파인 y 가산, 단상 오프셋, 그림자 scale}.
## 원작 판정은 레벨 자체다: lv<10 / 10~24 / ≥25 (`Growth.stage_for_level` 과 같은 경계).
const STAGE_ADJ := {
	"baby":  {"dy": 40.0, "stand": 70.0, "shadow": 0.9},
	"child": {"dy": 35.0, "stand": 78.0, "shadow": 1.3},
	"adult": {"dy": 30.0, "stand": 78.0, "shadow": 1.5}}

## 동굴 받침대와 같은 1080 공간 클러스터 규약(cave.gd `_refresh_dragon` · levelup_screen.gd 와 동일).
const DRAGON_SCENE := "res://scenes/dragons/dragon_%d_%s.tscn"
const STAND_COUNT := 16
const S1080 := 692.0 / 1080.0

# ---------- 진입점 ----------

## `kind` = "gem"(원작 ResetType 1) | "skill"(0).
## `stage_node` = 열려 있는 동안 숨길 호스트 받침대 — 원작은 가방 팝업이 동굴을 가려서 문제가 없지만
## 우리는 이 화면이 동굴 위에 바로 뜰 수도 있어 드래곤이 둘로 보인다(LevelUpScreen 과 같은 처리).
static func open(host: Node, uid: int, kind: String, on_close := Callable(),
		stage_node: Node = null) -> ResetLayer:
	var s := ResetLayer.new()
	s._uid = uid
	s._kind = kind
	s._on_close = on_close
	s._host_stage = stage_node
	host.add_child(s)
	return s

var _uid := 0
var _kind := "gem"
var _on_close := Callable()
var _host_stage: Node = null

var _vis := Vector2.ZERO
var _layer: CanvasLayer
var _dim: ColorRect
## 원작 `this+0x218` — 슬라이드하는 내용 레이어. 모든 자식이 여기 붙는다.
var _content: Control
var _rollers: Array[Control] = []       # tag 0x78+i(젬) / 0x73+i(스킬)
var _finals: Array[Control] = []        # tag —(젬 bg) / 0x71+i(스킬 base)
var _particles: Array[CPUParticles2D] = []   # 젬 전용(원작 tag 0x7b+i, removeParticleEffect 가 지운다)
var _roll_accum := 0.0
var _rolling := false
var _msg: Label
var _closing := false

func _ready() -> void:
	_vis = get_viewport().get_visible_rect().size
	_build()

## cocos(y-up, 좌하단 원점) → content 로컬 Godot(y-down). content 자체가 −50 만큼 내려가 있으므로
## 여기서는 화면 좌표만 뒤집는다.
func _gp(cocos: Vector2) -> Vector2:
	return Vector2(cocos.x, _vis.y - cocos.y)

func _center() -> Vector2:
	return _vis * 0.5

# ---------- initWidget ----------

func _build() -> void:
	var d := UserDB.get_dragon(_uid)
	if d.is_empty():
		_finish(); return

	_layer = CanvasLayer.new()
	_layer.layer = 60                      # 원작 z=1000(러닝 씬 최상단)
	add_child(_layer)
	# 받침대 복구는 트리에서 빠질 때 무조건 건다(✔ 말고 다른 경로로 닫혀도 동굴이 안 비게).
	if is_instance_valid(_host_stage):
		_host_stage.visible = false
		_layer.tree_exited.connect(func():
			if is_instance_valid(_host_stage): _host_stage.visible = true)

	# ① 자기 자신(검정) CCFadeTo(0.5, 200)
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP     # 뒤 화면 입력 차단(CCLayerColor + swallowsTouches)
	_layer.add_child(_dim)
	_dim.create_tween().tween_property(_dim, "color:a", DIM_ALPHA, SLIDE_SECS)

	# ② content 를 위(+H)에서 아래(−50)로 EaseExponentialInOut MoveBy
	_content = Control.new()
	_content.size = _vis
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.position = Vector2(0, -_vis.y)            # cocos +H
	_layer.add_child(_content)
	var slide := _content.create_tween()
	slide.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
	slide.tween_property(_content, "position:y", -CONTENT_END_Y, SLIDE_SECS)

	_build_dragon(d)
	_build_name(d)
	_build_check_button()
	if _kind == "gem":
		_reset_gem_effect(d)
	else:
		_reset_skill_effect(d)
	_build_flash()

## ③~⑥ 드래곤 스파인 + 단상 + 그림자.
## ⚠️ 우리 드래곤 씬은 동굴에서 1080 공간(컨테이너 S1080 · 드래곤 1.9)으로 세워 크기를 맞춰 뒀다
##   (cave.gd `_refresh_dragon`). 원작의 `setScale(1.1)` 을 그대로 쓰면 우리 변환본에서는 크기가
##   어긋나므로 **클러스터 내부 비율은 동굴 그대로 두고, 클러스터를 원작 좌표에 앉힌다.**
func _build_dragon(d: Dictionary) -> void:
	var stage := Growth.stage_for_level(int(d.get("level", 1)))
	var adj: Dictionary = STAGE_ADJ.get(stage, STAGE_ADJ["adult"])
	# 원작: 스파인 (W×0.29, H×0.5+40) 에 단계 보정 dy 를 더하고, 단상은 그보다 stand 만큼 아래.
	var spine_c := Vector2(_vis.x * 0.29, _vis.y * 0.5 + 40.0 + float(adj["dy"]))
	var stand_c := spine_c - Vector2(0, float(adj["stand"]))
	var shadow_c := stand_c - Vector2(0, 30.0)

	# 그림자 — `common/shadow.png` tag 0x70
	var sh := AtlasUI.spr("common_ui", "common_shadow", Design.ASSET_SCALE * float(adj["shadow"]))
	if sh != null:
		sh.position = _gp(shadow_c)
		sh.modulate = Color(1, 1, 1, 0.55)
		_content.add_child(sh)

	# 단상 + 드래곤(1080 공간 클러스터). 클러스터 원점 = 단상 **중심**.
	var holder := Node2D.new()
	holder.scale = Vector2(S1080, S1080)
	holder.position = _gp(stand_c)
	_content.add_child(holder)
	var sman := AtlasUI.manifest("stand_ui")
	var si: int = UserDB.get_skin("stand_skin") % STAND_COUNT
	var skey := "stand_stand%d" % (si + 1)
	var info: Dictionary = sman.get(skey, {})
	var pw: float = maxf(1.0, float(info.get("w", 305)))
	var ph: float = maxf(1.0, float(info.get("h", 120)))
	var psc := 620.0 / pw
	var ped := AtlasUI.spr("stand_ui", skey, psc)
	if ped != null:
		holder.add_child(ped)                        # 단상 중심 = 클러스터 원점
	# 동굴 클러스터의 드래곤↔단상 상대 위치를 그대로 옮긴다(동굴: ped y=357−ph·psc/2, 드래곤 y=−7).
	var rel := -7.0 - (357.0 - ph * psc / 2.0)
	if UserDB.is_egg(d):
		return                                       # 알에는 쓸 수 없다(호출부가 막지만 방어)
	var path := DRAGON_SCENE % [int(d.get("id", 0)), stage]
	if not ResourceLoader.exists(path):
		return
	var d2 := Node2D.new()
	d2.scale = Vector2(1.9, 1.9)
	d2.position = Vector2(0, rel)
	holder.add_child(d2)
	var inst = load(path).instantiate()
	d2.add_child(inst)
	# 원작은 `translateSpineAnimationName("wait")` 를 루프로 건다(레벨업 화면의 love 와 다르다).
	var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
	if ap != null and ap.has_animation("wait"):
		ap.play("wait")
	# ④ `Dragon::getLevel() > 44` 이면 Aura::SetOn — 우리 오라성체 판정과 같은 경계.
	if Growth.is_aura_adult(int(d.get("level", 1))):
		_build_aura(holder, String(Data.get_dragon(int(d.get("id", 0))).get("element", "")), rel)

## 오라성체 발광(동굴 `_apply_aura` 와 같은 플립북 규칙 — `dragon/aura_<속성>/auraNN` 9프레임).
func _build_aura(holder: Node2D, element: String, rel: float) -> void:
	if element == "":
		return
	var frames: Array = []
	for i in range(1, 10):
		var p := "res://assets/converted/aura_ui/dragon_aura_%s_aura%02d.tres" % [element, i]
		if ResourceLoader.exists(p):
			frames.append(load(p))
	if frames.is_empty():
		return
	var spr := Sprite2D.new()
	var addmat := CanvasItemMaterial.new()
	addmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	spr.material = addmat
	spr.scale = Vector2(1.5, 1.5)                     # 1080 공간 안이라 동굴과 같은 배율
	spr.position = Vector2(0, rel)
	spr.z_index = -1
	holder.add_child(spr)
	var tw := spr.create_tween().set_loops()
	for t in frames:
		var ft: Texture2D = t
		tw.tween_callback(func(): spr.texture = ft)
		tw.tween_interval(0.1)

## ⑦⑧ 이름(TTF 30 scale 1.1) + 등급(font_rating).
## ⚠️ 원작은 스카우터(0x1b8) 미보유 시 등급을 숨긴다 — 그 아이템이 미구현이라 항상 표시한다
##   (참조 영상도 등급이 보이는 상태다). 상세 = SlotResetScreens.md §3.
func _build_name(d: Dictionary) -> void:
	var nm := Icons.name_of(d)
	var nl := Label.new()
	nl.text = nm
	nl.add_theme_font_size_override("font_size", 33)      # 30 × scale 1.1
	nl.add_theme_color_override("font_color", Color.WHITE)
	nl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	nl.add_theme_constant_override("outline_size", 5)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nw := nl.get_theme_font("font").get_string_size(
		nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 33).x
	var npos := _gp(_center() + Vector2(SLOT_DX, 175.0))
	nl.size = Vector2(nw, 40.0)
	nl.position = npos - nl.size * 0.5
	_content.add_child(nl)

	var rl := Label.new()
	rl.text = "%.1f" % _grade_of(d)
	_bm_style(rl, 30, Color(1, 0.68, 0.16), "font_rating")
	# 원작: anchor(0, 0.5) 로 이름 오른쪽 `+(이름폭/2 + 15, 5)`.
	rl.size = Vector2(90.0, 36.0)
	rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rl.position = npos + Vector2(nw * 0.5 + 15.0, -5.0 - 18.0)
	rl.modulate.a = 0.0
	_content.add_child(rl)
	rl.create_tween().tween_property(rl, "modulate:a", 1.0, 0.5)

## 원작 `Dragon::getRating()` — 우리 등급 계산은 레벨업 롤(gain_log)까지 포함한다(§K-10).
func _grade_of(d: Dictionary) -> float:
	return Growth.compute_grade(Data.get_dragon(int(d.get("id", 0))), Data.stat_table,
		d.get("stat_bonus", {}), d.get("gain_log", []), Data.level_curve.get("grade", {}))

## ⑨ 확인 `common/check_btn` scale 1.5 at (W×0.9, H×0.95), 투명 → Delay(1.8) → FadeIn(0.3).
func _build_check_button() -> void:
	var b := TextureButton.new()
	var t := AtlasUI.tex("common_ui", "common_check_btn")
	var sz := Vector2(66.0, 57.0)
	if t != null:
		b.texture_normal = t
		b.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * 1.5
		sz = AtlasUI.size_pt("common_ui", "common_check_btn") * 1.5
	b.position = _gp(Vector2(_vis.x * 0.9, _vis.y * 0.95)) - sz * 0.5
	b.modulate.a = 0.0
	b.disabled = true
	b.pressed.connect(_close)
	_content.add_child(b)
	var tw := b.create_tween()
	tw.tween_interval(ROLL_END)
	tw.tween_callback(func(): b.disabled = false)
	tw.tween_property(b, "modulate:a", 1.0, FLASH_IN)

# ---------- resetGemEffect / resetSkillEffect ----------

func _reset_gem_effect(d: Dictionary) -> void:
	# 제목 `<GemResetMsg>` — font_subtitle scale 1.2, YELLOW.
	_build_title("잼 슬롯 변경")
	# 결과문 `<CaveToastMsg21>` — font_common, 투명(확정 때 나타난다).
	_msg = _build_msg("드래곤의 젬 슬롯이 변경되었습니다.", 25)
	var types := Gem.types(d.get("gems", {}))
	for i in Gem.SLOTS:
		var c := Vector2(_vis.x * 0.5 + i * GEM_PITCH - GEM_PITCH + SLOT_DX, _vis.y * 0.5)
		var pos := _gp(c)
		# 확정 칸(원작 bg) — setVisible(false) 로 숨겨 두고 확정 때 켠다.
		var fin := _gem_box(String(types[i]))
		fin.position = pos - GEM_BOX * 0.5
		fin.visible = false
		_content.add_child(fin)
		_finals.append(fin)
		# 톱니 링(`common/skill_circle_bg`) — bg −(0,3), 투명 → Delay(0.3) 뒤 페이드인.
		var ring := AtlasUI.spr("common_ui", "common_skill_circle_bg", Design.ASSET_SCALE)
		if ring != null:
			ring.position = pos + Vector2(0, 3.0)
			ring.modulate.a = 0.0
			ring.z_index = -1
			_content.add_child(ring)
			var rt := ring.create_tween()
			rt.tween_interval(ROLL_START)
			rt.tween_property(ring, "modulate:a", 1.0, 0.2)
		# 롤러(원작 tag 0x78+i) — 0.05초마다 갈아끼운다.
		var roller := _gem_box(String(types[i]))
		roller.position = pos - GEM_BOX * 0.5
		_content.add_child(roller)
		_rollers.append(roller)
		# `particle/scene/common/reset_slot.plist` — 원작은 0.05초마다 다시 만드는 칸에 매번
		# 붙이므로(=끊김 없는 연속 방출) 여기서는 칸마다 **하나를 계속 돌린다**.
		# z: 원작은 칸 스프라이트 안의 −1 이지만, 그 칸이 매 틱 **마지막 자식으로 새로 붙어서**
		#   결과적으로 반짝임이 다른 칸들 위에 겹친다(참조 영상 젬슬롯변경2). 우리는 칸을 재생성하지
		#   않으므로 같은 그림이 되도록 z 를 칸 위로 올린다.
		var p := CocosParticle.spawn(_content, "reset_slot", pos - Vector2(0, 5.0), 1, 0.0, 90)
		if p != null:
			p.one_shot = false
			p.emitting = false
			p.scale = Vector2(1.07, 1.07)
			# 원작 파티클 텍스처(작은 반짝임)를 우리 절차생성 원형 점으로 대체하다 보니
			# plist 의 startParticleSize(30±30)를 그대로 쓰면 칸을 덮는 큰 뭉게구름이 된다 →
			# 참조 영상의 알갱이 크기(≈10px)에 맞춰 조인다.
			p.scale_amount_min = 0.06
			p.scale_amount_max = 0.40
			p.amount = 44
			_particles.append(p)
	_start_roll()

func _reset_skill_effect(d: Dictionary) -> void:
	_build_title("스킬 변경")
	_msg = _build_msg("드래곤의 스킬 슬롯이 변경되었습니다.", 25)
	var types := Loadout.slot_types(d)
	for i in Loadout.SKILL_SLOTS:
		var c := Vector2(_vis.x * 0.5 - 42.0 + i * SKILL_PITCH + SLOT_DX, _vis.y * 0.5)
		var pos := _gp(c)
		var fin := _skill_box(String(types[i]))
		fin.position = pos - fin.size * 0.5
		fin.visible = false
		_content.add_child(fin)
		_finals.append(fin)
		var roller := _skill_box(String(types[i]))
		roller.position = pos - roller.size * 0.5
		_content.add_child(roller)
		_rollers.append(roller)
	_start_roll()

## 젬 칸 한 개 — Scale9 `9patch/gem_*_bg` capInsets(20,20,2,2) 를 70×70 으로.
func _gem_box(ty: String) -> Control:
	var root := Control.new()
	root.size = GEM_BOX
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_meta("frame", String(GEM_FRAME.get(ty, "9patch_gem_white_bg")))
	var np := AtlasUI.nine("ninepatch_ui", String(root.get_meta("frame")), GEM_BOX, GEM_CAP)
	if np != null:
		np.name = "np"
		root.add_child(np)
	return root

## 스킬 칸 한 개 — `common/skill_*_bg` 스프라이트(9patch 아님).
func _skill_box(ty: String) -> Control:
	var key := String(SKILL_FRAME.get(ty, "common_skill_star_bg"))
	var root := Control.new()
	root.size = AtlasUI.size_pt("common_ui", key)
	if root.size == Vector2.ZERO:
		root.size = Vector2(86.0, 86.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := AtlasUI.spr("common_ui", key, Design.ASSET_SCALE)
	if s != null:
		s.name = "np"
		s.position = root.size * 0.5
		root.add_child(s)
	return root

## 굴러가는 칸의 그림만 바꾼다(원작 젬=노드 재생성 / 스킬=setDisplayFrame — 결과는 같다).
func _set_roll_frame(box: Control, key: String) -> void:
	var n := box.get_node_or_null("np")
	if n == null:
		return
	if n is NinePatchRect:
		var t := AtlasUI.tex("ninepatch_ui", key)
		if t != null: (n as NinePatchRect).texture = t
	elif n is Sprite2D:
		var t2 := AtlasUI.tex("common_ui", key)
		if t2 != null: (n as Sprite2D).texture = t2

func _build_title(text: String) -> void:
	var l := Label.new()
	l.text = text
	_bm_style(l, 34, Color(1, 0.93, 0.15))            # font_subtitle scale 1.2 + ccColor3B::YELLOW
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(420.0, 46.0)
	l.position = _gp(_center() + Vector2(SLOT_DX, 85.0)) - l.size * 0.5
	_content.add_child(l)

func _build_msg(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	_bm_style(l, size, Color(1, 1, 1), "font_common")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(720.0, 40.0)
	l.position = _gp(_center() + Vector2(SLOT_DX, -110.0)) - l.size * 0.5
	l.modulate.a = 0.0
	_content.add_child(l)
	return l

# ---------- 롤 · 섬광 ----------

func _start_roll() -> void:
	var t := get_tree().create_timer(ROLL_START)
	t.timeout.connect(func():
		if not is_instance_valid(self): return
		_rolling = true
		for p in _particles:
			if is_instance_valid(p): p.emitting = true)
	var e := get_tree().create_timer(ROLL_END)
	e.timeout.connect(_settle)

func _process(delta: float) -> void:
	if not _rolling:
		return
	_roll_accum += delta
	while _roll_accum >= ROLL_TICK:
		_roll_accum -= ROLL_TICK
		_roll_tick()

## `randomGemEffect` / `randomSkillEffect` — 0.05초마다 굴러가는 칸을 랜덤 그림으로.
func _roll_tick() -> void:
	var table := GEM_ROLL_WEIGHT if _kind == "gem" else SKILL_ROLL_WEIGHT
	for i in _rollers.size():
		var box := _rollers[i]
		if not is_instance_valid(box):
			continue
		_set_roll_frame(box, String(table[randi() % table.size()]))
		_shake(box)

## 원작 커스텀 `Shake::actionWithDuration(dur, 2.0)` 대체 — 진폭 2pt 의 1틱 흔들림.
func _shake(box: Control) -> void:
	var base: Vector2 = box.get_meta("home", box.position)
	box.set_meta("home", base)
	box.position = base + Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))

## t=1.8 — 롤 확정. 롤러를 지우고 최종 칸을 켠 뒤 결과문을 띄운다.
func _settle() -> void:
	if not is_instance_valid(self):
		return
	_rolling = false
	for r in _rollers:
		if is_instance_valid(r):
			r.queue_free()
	_rollers.clear()
	for f in _finals:
		if is_instance_valid(f):
			f.visible = true
	# 원작 `removeParticleEffect()` — 섬광이 덮고 있는 동안 파티클을 지운다.
	for p in _particles:
		if is_instance_valid(p):
			p.emitting = false
			p.queue_free()
	_particles.clear()
	if is_instance_valid(_msg):
		_msg.create_tween().tween_property(_msg, "modulate:a", 1.0, FLASH_IN)

## 흰 섬광 — 원작은 **content 가 아니라 자기 자신**(딤 레이어)에 z=1000 으로 얹는다.
func _build_flash() -> void:
	var f := ColorRect.new()
	f.color = Color(1, 1, 1, 0)
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(f)
	var tw := f.create_tween()
	tw.tween_interval(FLASH_DELAY)
	tw.tween_property(f, "color:a", 1.0, FLASH_IN)
	tw.tween_interval(FLASH_HOLD)
	tw.tween_property(f, "color:a", 0.0, FLASH_OUT)
	tw.tween_callback(f.queue_free)

# ---------- close ----------

## 원작 `close()` — `Spawn(FadeTo(0.5,0), EaseExponentialInOut(MoveBy(0.5, (0, H))))`.
func _close() -> void:
	if _closing:
		return
	_closing = true
	_rolling = false
	Bgm.sfx("effect_button")
	if is_instance_valid(_dim):
		_dim.create_tween().tween_property(_dim, "color:a", 0.0, SLIDE_SECS)
	if is_instance_valid(_content):
		var tw := _content.create_tween()
		tw.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(_content, "position:y", -CONTENT_END_Y - _vis.y, SLIDE_SECS)
		tw.tween_callback(_finish)
	else:
		_finish()

func _finish() -> void:
	if _on_close.is_valid():
		_on_close.call()
	queue_free()

# ---------- 공용 서식 ----------

## 원작 BMFont 라벨(`getFontName_subtitle` / `_common` / `font_rating`).
## 한글 보강본 = `assets/converted/font_ui/`(CLAUDE.md §10) — `fixed_size_scale_mode` 를 켜야
## `font_size` 가 먹는다. 폰트가 없으면 TTF + 외곽선으로 폴백.
static var _bmfonts: Dictionary = {}
func _bmfont(name: String) -> FontFile:
	if _bmfonts.has(name):
		return _bmfonts[name]
	var p := "res://assets/converted/font_ui/%s.fnt" % name
	if not ResourceLoader.exists(p):
		_bmfonts[name] = null
		return null
	var f: FontFile = load(p).duplicate()
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Gulim"])
	f.fallbacks = [fb]
	_bmfonts[name] = f
	return f

func _bm_style(l: Label, size: int, col: Color, font := "font_subtitle") -> void:
	var f := _bmfont(font)
	if f != null:
		l.add_theme_font_override("font", f)
	else:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 5 if size >= 24 else 4)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
