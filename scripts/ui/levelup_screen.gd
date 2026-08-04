class_name LevelUpScreen
extends Node
## 레벨업 화면 — 원작 **전체화면 오버레이**(팝업 아님) + `ExpLayer` 연출 안무.
##
## 2026-07-31 `cave.gd` 에서 통째로 뽑아낸 공용 화면이다. 사용자 지시:
##   "탐험 레벨업 팝업이 여전히 자작 기반이야. 축복류 아이템과 똑같은 레벨업 팝업을 공유해야 해."
## 종전엔 두 경로가 **다른 화면**을 썼다 —
##   · 동굴에서 축복 아이템 사용 → 이 화면(원작 ExpLayer 안무 이식본)
##   · 탐험/전투에서 EXP 로 레벨업 → `LevelUpResult`(자작 모달, 2026-07-31 삭제)
## 이제 둘 다 이 화면 하나를 쓴다. 상호작용(레벨업 아이템 슬롯 · 능력치 다시뽑기 · AUTO)도
## **완전히 동일**하다(사용자 확정 2026-07-31).
##
## 원작 근거는 아래 원래 주석에 그대로 남아 있다(ExpLayer 안무 = docs/ref/porting/LevelUpScreen.md).
##
## 사용:
##   LevelUpScreen.open(host, uid)                                  # 탐험·전투
##   LevelUpScreen.open(host, uid, {                                # 동굴
##       "stage_node": _stage,                 # 열려 있는 동안 숨길 호스트 받침대
##       "on_evolved": func(): …,              # 성장 단계가 바뀌었다(받침대·목록 다시 그리기)
##       "on_changed": func(): …,              # 스탯이 바뀌었다(스탯 표시 갱신)
##       "on_close":   func(): …,              # 닫혔다
##   })
##
## ⚠️ 호스트는 이 노드를 **자식으로 붙인다**(오버레이 CanvasLayer 를 자기 밑에 만든다).
##   닫히면 스스로 `queue_free()` 한다.

# ---------- 진입점 ----------

## 화면을 연다. host 에 자식으로 붙고, 닫힐 때 스스로 사라진다.
static func open(host: Node, uid: int, opts: Dictionary = {}) -> LevelUpScreen:
	var s := LevelUpScreen.new()
	s._uid = uid
	s._host_stage = opts.get("stage_node")
	s._opts = opts
	host.add_child(s)
	return s

## 여러 마리가 동시에 올랐으면 **한 마리씩 차례로** 띄운다(원작에도 동시 표시는 없다).
## entries = [{uid: int, …}] — uid 만 쓴다(나머지 필드는 무시, 화면이 UserDB 를 직접 읽는다).
static func open_queue(host: Node, entries: Array, on_all_closed := Callable()) -> void:
	if entries.is_empty():
		if on_all_closed.is_valid(): on_all_closed.call()
		return
	var rest := entries.slice(1)
	open(host, int((entries[0] as Dictionary).get("uid", 0)), {
		"on_close": func(): open_queue(host, rest, on_all_closed)})

var _uid := 0
var _host_stage                      # 열려 있는 동안 숨길 호스트 노드(동굴 받침대). 없으면 null.
var _opts: Dictionary = {}
var _pma: CanvasItemMaterial

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	var sf := FileAccess.open("res://assets/converted/stand_ui/_manifest.json", FileAccess.READ)
	if sf: _stand_manifest = JSON.parse_string(sf.get_as_text())
	var isf := FileAccess.open("res://assets/converted/item_small_ui/_manifest.json", FileAccess.READ)
	if isf: _item_small_manifest = JSON.parse_string(isf.get_as_text())
	_build()

## 호스트 훅 호출(없으면 아무 일도 안 한다).
func _notify(key: String) -> void:
	var c = _opts.get(key)
	if c is Callable and (c as Callable).is_valid():
		(c as Callable).call()

## 화면이 닫혔다 — 호스트에 알리고 스스로 사라진다.
func _close_self() -> void:
	_notify("on_close")
	queue_free()

# ---------- 공개 API (호스트가 연출을 태울 때) ----------

## 레벨업 연출 타임라인을 태운다(원작 ExpLayer 안무).
## fx = {kind:"up"|"reset", sp: float, stage_changed: bool, slot_new: int, triple: bool}
## 가방 → 대상 선택 → 레벨업 아이템 사용 경로가 `open()` 직후에 부른다:
## `open()` 은 `add_child` 로 `_ready`(=`_build`)가 **동기 실행**된 뒤 돌아오므로 컨텍스트가 이미 있다.
func play_fx(fx: Dictionary) -> void:
	_lvup_redraw(fx)

## 상단 워드아트를 잠시 다른 문구로(LEVEL DOWN / LEVEL RESET). 스파인 미보유분은 TTF 배너다.
func word_banner(text: String, secs := 1.6, col := Color(0.72, 0.94, 1.0),
		outline := Color(0, 0, 0, 0.9)) -> void:
	_lvup_word_banner(text, secs, col, outline)

# ---------- cave.gd 에서 함께 가져온 공용 헬퍼 ----------
# (동굴에도 같은 이름의 것이 남아 있다 — 그쪽은 동굴 화면이 계속 쓴다.)

# 아래 3개는 cave.gd 와 같은 값이다(드래곤 씬 경로 · 받침대 스킨 수 · 1080→692 컨테이너 배율).
const DRAGON_SCENE := "res://scenes/dragons/dragon_%d_%s.tscn"
const STAND_COUNT := 16
## 1080-공간으로 작성된 클러스터(받침대+드래곤)를 692공간에 얹기 위한 컨테이너 스케일.
const S1080 := 692.0 / 1080.0   # ≈0.6407

var _stand_manifest: Dictionary = {}
var _item_small_manifest: Dictionary = {}   # item_small_ui(원작 속성 아이콘 ele_*)
var _portrait_manifests: Dictionary = {}    # dir -> manifest (캐시)
var _adv_man_cache: Dictionary = {}
var _common_man_cache: Dictionary = {}

func _vis() -> Vector2:
	return get_viewport().get_visible_rect().size

func _atlas_sprite(dir: String, name: String, _man: Dictionary, scale := 1.0) -> Sprite2D:
	var s := Sprite2D.new()
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if ResourceLoader.exists(p):
		s.texture = load(p)
	s.material = _pma
	# 회전 패킹 보정은 변환 단계가 흡수한다(fix_rotated_frames.py / cocos_export.py).
	s.scale = Vector2(scale, scale)
	return s

func _portrait_sprite(id: int, stage: String, scale := 1.0, skin := 0) -> Sprite2D:
	var dir := "portrait_%d" % id
	if not _portrait_manifests.has(dir):
		var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
		_portrait_manifests[dir] = JSON.parse_string(f.get_as_text()) if f else {}
	var frame := "dragon_dragon_%d_box_%s" % [id, stage]
	if skin > 0:
		var sframe := "dragon_dragon_%d_box_%s_skin%d" % [id, stage, skin]
		if _portrait_manifests[dir].has(sframe): frame = sframe
	return _atlas_sprite(dir, frame, _portrait_manifests[dir], scale)

func _man_adventure() -> Dictionary:
	if _adv_man_cache.is_empty():
		var f := FileAccess.open("res://assets/converted/adventure_ui/_manifest.json", FileAccess.READ)
		if f: _adv_man_cache = JSON.parse_string(f.get_as_text())
	return _adv_man_cache

func _man_common() -> Dictionary:
	if _common_man_cache.is_empty():
		var f := FileAccess.open("res://assets/converted/common_ui/_manifest.json", FileAccess.READ)
		if f: _common_man_cache = JSON.parse_string(f.get_as_text())
	return _common_man_cache

## 한글 조사 선택(받침 유무) — 원작 문장 표기용.
func _josa_c(word: String, with_batchim: String, without: String) -> String:
	if word.is_empty(): return without
	var c := word.unicode_at(word.length() - 1)
	if c < 0xAC00 or c > 0xD7A3: return without
	return with_batchim if ((c - 0xAC00) % 28) != 0 else without

func _grade_of(inst: Dictionary, ddef: Dictionary) -> float:
	return Growth.compute_grade(ddef, Data.stat_table, inst.get("stat_bonus", {}),
		inst.get("gain_log", []), Data.level_curve.get("grade", {}))

func _skills_learned_since(uid: int, before_size: int) -> Array:
	var pool: Array = UserDB.dragon_skills(uid)
	var out: Array = []
	for i in range(before_size, pool.size()):
		var sid := int((pool[i] as Dictionary).get("id", 0))
		out.append(String(Data.skills.get(str(sid), {}).get("name", "스킬")))
	return out

# ══════════════════════════════════════════════════════════════════════════════
# 아래는 cave.gd 2772~3898 에서 그대로 옮겨온 원작 이식본이다(의존 심볼만 위로 치환).
# ══════════════════════════════════════════════════════════════════════════════

## 원작 레벨업 화면 — **전체화면 오버레이**(팝업 아님). 랜덤롤 §K-1.
## 참조: docs/ref/orig_image/levelup/Screenshot_2016-06-23-12-18-13.png(배치) ·
##       docs/ref/orig_image/levelup/Screenshot_2017-02-27-11-12-03-1.png(리롤 블록: 회전화살표+"능력치 다시뽑기"+💎x2)
##
## ⚠️ 소유 클래스 미특정(2026-07-27). libgame.so 심볼 1,181개를 훑었으나 이 화면을 만드는 클래스가
##    디컴파일된 397개 안에 없다 — StatusLayer=먹이/치료/피로, ResetLayer=젬·스킬 리셋,
##    DragonEnchantResultLayer=마석 인챈트(MasicStoneGaugeText + dragon_enchant.spine_json)로 전부 다르다.
##    CLAUDE.md §3 "자산 이름으로 담당 클래스를 추측하는 것 금지"에 따라 **클래스를 지목하지 않는다.**
##    ⇒ 배치 근거 = 참조 스크린샷의 비율(ASSUMPTION, 원작 좌표 리터럴 아님)
##      자산 근거 = asset_index.py 조회(아래 프레임은 전부 원본 — 자작 도형 없음)
##
## 사용 원본 프레임: common/backlight3 · common/item_box · common/lock · common/refresh ·
##   common/refresh_bg1 · common/bt_levelupauto_off|on · common/diamond_small1 · common/check_btn ·
##   common/btn_arrow2 · scene/cave/enchant_bar_bg2 · scene/cave/enchant_bar2 · scene/cave/gear ·
##   scene/cave/gear_inside · scene/cave/gear_shadow · item/item_small/{level_up,level_down,bless_of_*}
##
## 문자열은 원작 stringsData_KR.xml 그대로:
##   DragonReset "능력치 다시뽑기" · DragonResetMax1+2 "(MAX 확률 %s%%)" ·
##   DragonResetConfirm "다이아를 소모하여 능력치를 다시 뽑으시겠습니까?" · DragonResetAuto "다시뽑기 자동"
const _LVUP_GUARANTEE := {
	"bless_of_dragon": "max1", "bless_of_maia": "max2",
	"bless_of_dersa": "triple", "bless_of_amor": "amor",
}
const _STAT_KR := {"hp": "생명력", "att": "공격력", "def": "방어력"}
## 아이템 슬롯 순서. 원작 참조 스크린샷엔 슬롯이 2칸뿐이지만 우리 레벨 아이템은 6종이라
## **보유한 종류를 모두** 노출하고 빈 칸만 lock 으로 채운다(ASSUMPTION: 슬롯 해금 규칙은 유실).
const _LVUP_ITEMS := ["level_up", "bless_of_dragon", "bless_of_maia", "bless_of_dersa",
	"bless_of_amor", "level_down"]
const _LVUP_MIN_SLOTS := 2
# (종전 _LVUP_AUTO_DELAY 는 폐기 — 자동 다시뽑기는 이제 연출 완료를 기다린다. 원작 timeScale 2.0 = sp 0.5)
## UI 레이어 z. 드래곤 스파인은 슬롯마다 z_index 를 갖고 있어 기본 0 이면 UI 를 덮는다.
const _LVUP_UI_Z := 40

## 레벨업 화면 상태(한 번에 하나만 열린다).
## 🔴 2026-07-27 회귀방지: 예전엔 `var redraw: Callable` 자기참조 람다로 갱신했다. GDScript 람다는
##    **생성 시점의 값**을 캡처하므로 바깥 람다가 캡처한 `redraw` 는 대입 전의 *빈 Callable* 이었고,
##    리롤·Lv±1·축복을 눌러도 화면이 전혀 갱신되지 않았다(골드와 gain_log 는 실제로 바뀌는데 표시만 그대로
##    → "버튼이 안 먹는다"로 보였다). 재현: `shot_helper --shot=lvreroll`.
##    **다시 람다로 되돌리지 말 것** — 갱신은 메서드(`_lvup_redraw`)로 둔다.
var _lvup_ctx: Dictionary = {}
## 레벨업 화면 좌측 드래곤의 holder — 진화(성장 단계 변경) 때 통째로 다시 세운다.
var _lvup_dragon_holder: Node2D
## 레벨업 연출(원작 ExpLayer 안무) 재생 중 플래그 — 재생 중 입력 차단·자동 루프 대기.
var _lvup_fx_busy := false

## 원작 BMFont 로더(레벨업 화면용). `fixed_size` 가 박혀 있어 기본값으로는 font_size 를 무시
## → `fixed_size_scale_mode = ENABLED` 복제본을 캐시(main_hud.gd 와 같은 패턴).
## 폰트 근거 = ExpLayer 디컴프(docs/ref/porting/LevelUpScreen.md "원작 폰트" 표):
##   스탯/값/롤/(+n/m)/MAX 뱃지/추가슬롯 = font_subtitle · EXP 카운터 = font_common ·
##   등급 = font_rating · 트리플맥스 = font_title(cutin.gd).
var _lvup_bmfonts := {}
func _lvup_bmfont(name: String) -> FontFile:
	if _lvup_bmfonts.has(name):
		return _lvup_bmfonts[name]
	var p := "res://assets/converted/font_ui/%s.fnt" % name
	if not ResourceLoader.exists(p):
		return null
	var f: FontFile = load(p).duplicate()
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	# 원작 비트맵은 한글 1271자 부분집합이라 "샛"·"팬" 같은 글자가 빠져 있다(원작 문자열에 안 쓰인
	# 조합) → 도감의 드래곤 이름이 깨짐(사용자 보고 2026-07-30). 없는 글리프만 시스템 한글 폰트로
	# 폴백해 그린다(있는 글자는 계속 원작 비트맵).
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Gulim"])
	f.fallbacks = [fb]
	_lvup_bmfonts[name] = f
	return f

## 원작 BMFont 라벨 서식. 비트맵 자체에 외곽선이 구워져 있어 outline 오버라이드는 걸지 않는다.
func _lvup_bm_style(l: Label, size: int, col: Color, font := "font_subtitle") -> void:
	var f := _lvup_bmfont(font)
	if f:
		l.add_theme_font_override("font", f)
	else:
		# 폰트 미보유 폴백 — TTF + 외곽선(종전 서식)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 5 if size >= 24 else 4)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _build() -> void:
	var a := UserDB.get_dragon(_uid)
	if a.is_empty():
		_close_self(); return
	a = a.duplicate()
	a["uid"] = _uid
	var uid := _uid
	var ddef: Dictionary = Data.get_dragon(int(a.get("id", 0)))
	var vis := _vis()
	# 레이어를 둘로 나눈다 — 드래곤 **스파인은 슬롯마다 z_index 를 갖고** 있어서 같은 레이어에 두면
	# z_index 를 아무리 올려도 UI 를 덮는 경우가 생긴다. CanvasLayer 순서는 z_index 를 항상 이긴다.
	var overlay := CanvasLayer.new(); overlay.layer = 30; add_child(overlay)   # 딤 + 드래곤
	var uilay := CanvasLayer.new(); uilay.layer = 31; add_child(uilay)         # 그 위의 모든 UI
	# 원작도 뒤 동굴이 어둡게 깔린다(참조: 좌측 드래곤 슬롯 스트립이 어둡게 비침).
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.45); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var win := Control.new()
	win.size = vis
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	uilay.add_child(win)

	# ── 좌측: 드래곤(스파인) — 딤 위에 밝게 선다. 원작 참조에서 화면 좌측 1/5 지점.
	# 동굴 본체의 받침대(_stage)는 숨긴다 — 안 그러면 가운데 드래곤과 좌측 드래곤이 **둘 다** 보인다.
	# 복구는 오버레이가 트리에서 빠질 때 무조건 걸어 둔다(✔ 말고 다른 경로로 닫혀도 동굴이 안 비게).
	# ⚠️ 이 처리는 `_lvup_build_dragon` 이 아니라 **여기**에 있어야 한다 — 진화 때 좌측 드래곤만
	#    다시 세우므로(_lvup_refresh_dragon) 빌더는 화면당 여러 번 불린다.
	if is_instance_valid(_host_stage): _host_stage.visible = false
	overlay.tree_exited.connect(func():
		if is_instance_valid(_host_stage): _host_stage.visible = true)
	var dragon_ap := _lvup_build_dragon(overlay, a, vis)

	# ── LEVEL UP 아트(좌상단)
	# ⚠️ `assets/converted/lvup_ui/level_up.png` 는 추출 아틀라스에 없는 자작본이다(CLAUDE.md §10 표 참조).
	#    원본 워드아트를 확보하면 여기만 교체하면 된다.
	var lup := TextureRect.new()
	lup.texture = load("res://assets/converted/lvup_ui/level_up.png")
	lup.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lup.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lup.size = Vector2(vis.x * 0.30, vis.y * 0.20)
	lup.position = _lvup_art_home(vis, lup.size)
	lup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lup.z_index = _LVUP_UI_Z        # 드래곤 스파인(슬롯별 z_index)이 UI 를 덮지 않게
	win.add_child(lup)

	# ── 하단 전폭 텍스트박스(원작 BattleTextBox 사양)
	# 프레임 자체가 반투명이라 동굴 하단 메뉴(아이템/젬/스킬)가 비친다 → 뒤에 불투명 판을 깐다.
	# 원작 참조에서도 이 박스는 불투명하다.
	var tback := ColorRect.new()
	tback.color = Color(0.05, 0.04, 0.03, 1.0)
	tback.size = Vector2(vis.x, 120.0)
	tback.position = Vector2(0.0, vis.y - 120.0)
	tback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tback.z_index = _LVUP_UI_Z
	win.add_child(tback)
	var tbox := NinePatchRect.new()
	tbox.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres")
	tbox.patch_margin_left = 10; tbox.patch_margin_right = 10
	tbox.patch_margin_top = 4; tbox.patch_margin_bottom = 4
	tbox.size = Vector2(vis.x - 10.0, 120.0)
	tbox.position = Vector2(5.0, vis.y - 120.0)
	tbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tbox.z_index = _LVUP_UI_Z
	win.add_child(tbox)
	var tlabel := Label.new()
	tlabel.add_theme_font_size_override("font_size", 28)
	tlabel.add_theme_color_override("font_color", Color.WHITE)
	tlabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tlabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tlabel.size = Vector2(tbox.size.x - 20.0, 112.0); tlabel.position = Vector2(10.0, 4.0)
	tbox.add_child(tlabel)

	# ── 우상단 빨간 ✔ — 원작 `common/check_btn`(닫기 X 가 아니라 확인 체크다).
	var okb := TextureButton.new()
	var okt := "res://assets/converted/common_ui/common_check_btn.tres"
	if ResourceLoader.exists(okt):
		okb.texture_normal = load(okt)
		okb.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
		okb.position = Vector2(vis.x - 30.0 - 44.0 * Design.ASSET_SCALE, 20.0)
	else:
		okb.position = Vector2(vis.x - 60.0, 20.0)
	okb.pressed.connect(func():
		Bgm.sfx("effect_button")
		_lvup_ctx = {}
		_lvup_dragon_holder = null
		if is_instance_valid(_host_stage): _host_stage.visible = true   # 숨겼던 받침대 복구
		if is_instance_valid(overlay): overlay.queue_free()
		if is_instance_valid(uilay): uilay.queue_free()
		_close_self())
	uilay.add_child(okb)

	var body := Control.new()
	body.size = vis
	body.position = Vector2.ZERO
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 배경이 클릭을 먹지 않게(자식 버튼만 받는다)
	body.z_index = _LVUP_UI_Z
	win.add_child(body)

	_lvup_ctx = {"uid": uid, "ddef": ddef, "vis": vis, "body": body, "tlabel": tlabel,
		"overlay": overlay, "reroll": 0, "art": lup, "win": win, "dragon_ap": dragon_ap}
	_lvup_redraw()

## 상단 워드아트를 잠시 다른 문구로 바꾼다 — 리롤 = "LEVEL RESET"(참조 스크린샷).
## ⚠️ RESET/DOWN 워드아트는 추출 에셋에 없다(CLAUDE.md §10) → **TTF 문구**로 낸다.
##    LEVEL UP 아트조차 스크린샷에서 잘라낸 자작본이라, 원본 확보 시 둘 다 여기서 교체한다.
func _lvup_word_banner(text: String, secs := 1.6, col := Color(0.72, 0.94, 1.0),
		outline := Color(0.06, 0.24, 0.42, 1.0)) -> void:
	if _lvup_ctx.is_empty(): return
	var win: Control = _lvup_ctx.get("win")
	var art: TextureRect = _lvup_ctx.get("art")
	if not is_instance_valid(win) or not is_instance_valid(art): return
	if is_instance_valid(_lvup_ctx.get("word")):
		(_lvup_ctx["word"] as Node).queue_free()
	art.visible = false
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 52)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size = art.size
	l.position = art.position
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(0.7, 0.7)
	l.z_index = _LVUP_UI_Z
	win.add_child(l)
	_lvup_ctx["word"] = l
	var t := l.create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(secs)
	t.tween_callback(func():
		if is_instance_valid(art): art.visible = true
		if is_instance_valid(l): l.queue_free())

## 좌측 드래곤 — 원작 참조에선 딤 위에 드래곤이 밝게 서 있고 뒤에서 후광이 돈다.
## 동굴 받침대의 드래곤은 딤 아래로 어두워지므로 오버레이에 같은 스파인 씬을 한 번 더 세운다.
## 후광 = `common/backlight3` + 6초 1회전(원작 DragonEnchantResultLayer.c:640 `CCRotateBy::create(6.0, 360.0)`
##   — 다른 화면이지만 같은 프레임을 쓰는 원작 회전 파라미터라 그대로 따른다).
## (딤/받침대 숨김은 `_open_levelup` 담당 — 이 함수는 진화 때 다시 불린다.)
## 좌측 드래곤·받침대의 가로 중심(화면 폭 비율). 워드아트도 이 선에 맞춘다.
const DRAGON_CX := 0.22

## LEVEL UP 워드아트의 정위치(TextureRect 좌상단). 가로 중심을 **드래곤·받침대와 같은
## 수직선**에 맞춘다(🟦 사용자 확정 2026-07-31 — 종전 0.03W 는 그보다 왼쪽에 떠 있었다).
## 원작 좌표는 `ExpLayer` 가 스파인(`effect_levelupdown_spine`, 미보유)에 걸던 것이라 유실 —
## 우리 자작 PNG 의 자리는 화면 구성으로 정한다(CLAUDE.md §10 워드아트 행).
func _lvup_art_home(vis: Vector2, art_size: Vector2) -> Vector2:
	return Vector2(vis.x * DRAGON_CX - art_size.x * 0.5, vis.y * 0.03)

func _lvup_build_dragon(parent: Node, a: Dictionary, vis: Vector2) -> AnimationPlayer:
	# 내부는 동굴과 같은 1080 공간을 그대로 쓴다(받침대/드래곤 좌표를 재계산하지 않게).
	var holder := Node2D.new()
	_lvup_dragon_holder = holder   # 진화 시 통째로 갈아끼우기 위해 보관
	holder.scale = Vector2(S1080, S1080)
	# 동굴 받침대(_stage)는 `vis.y/2 - 8` 인데, 여기선 **love 모션이 크게 일어서서** 머리가
	# 화면 위로 잘린다 → 그만큼 아래로 내린다(받침대는 하단 텍스트박스 위에 그대로 들어간다).
	holder.position = Vector2(vis.x * DRAGON_CX, vis.y / 2.0 + 34.0)
	parent.add_child(holder)
	var bl := _atlas_sprite("common_ui", "common_backlight3", _man_common(), 1.35)
	if bl and bl.texture:
		bl.position = Vector2(0, 40)
		bl.modulate = Color(1, 1, 1, 0.5)
		holder.add_child(bl)
		bl.create_tween().set_loops().tween_property(bl, "rotation", TAU, 6.0).from(0.0)
	# 받침대 = 동굴과 같은 stand 스킨/정규화 규칙(_refresh_dragon 과 동일).
	var si: int = UserDB.get_skin("stand_skin") % STAND_COUNT
	var info = _stand_manifest.get("stand_stand%d" % (si + 1), {})
	var pw: float = maxf(1.0, float(info.get("w", 305)))
	var ph: float = maxf(1.0, float(info.get("h", 120)))
	var psc := 620.0 / pw
	var ped := _atlas_sprite("stand_ui", "stand_stand%d" % (si + 1), _stand_manifest, psc)
	if ped:
		ped.position = Vector2(0, 357.0 - ph * psc / 2.0)
		holder.add_child(ped)
	var stage_name := Growth.stage_for_level(int(a["level"]))
	var path := DRAGON_SCENE % [int(a["id"]), stage_name]
	if ResourceLoader.exists(path):
		var d2 := Node2D.new()
		d2.scale = Vector2(1.9, 1.9)      # 동굴 받침대와 동일(1080 공간 기준)
		d2.position = Vector2(0, -7)
		holder.add_child(d2)
		var inst = load(path).instantiate()
		d2.add_child(inst)
		# 원작은 **대기(wait)가 아니라 상호작용(love) 모션**을 반복한다(사용자 확인 2026-07-27) —
		# 동굴에서 드래곤을 눌렀을 때와 같은 모션이다(CaveScene::onClickDragon 이 "love" 재생).
		# 보이스도 함께 반복한다(원작 `Dragon::getDragonVoiceDelay` 만큼 늦춰 재생).
		# ⚠️ Animation 리소스는 동굴 받침대 인스턴스와 **공유**될 수 있다 → `loop_mode` 를 건드리면
		#    동굴 쪽 love 까지 무한루프가 된다. 리소스를 고치지 말고 끝날 때마다 다시 재생한다.
		var dap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		if dap:
			if dap.has_animation("love"):
				dap.animation_finished.connect(_lvup_loop_love.bind(dap))
				_lvup_play_love(dap)
			elif dap.has_animation("wait"):
				dap.play("wait")
			return dap
	else:
		# 스파인 미빌드 종은 초상 폴백(동굴 받침대와 같은 규칙 — 어떤 드래곤도 안 보이지 않게).
		var por := _portrait_sprite(int(a["id"]), stage_name, 2.6, int(a.get("skin", 0)))
		if por:
			por.position = Vector2(0, -30)
			holder.add_child(por)
	return null

## 진화(성장 단계 변경)로 다른 스파인을 세워야 할 때 좌측 드래곤만 갈아끼운다.
## 🔴 2026-07-28 회귀방지: 예전엔 레벨업 화면이 열릴 때 세운 스파인을 그대로 뒀다 →
##    레벨 10/20 을 넘겨도 해치 모습 그대로였고, **동굴을 나갔다 들어와야**(=_refresh) 바뀌었다.
func _lvup_refresh_dragon() -> void:
	if _lvup_ctx.is_empty(): return
	var overlay = _lvup_ctx.get("overlay")
	if not is_instance_valid(overlay): return
	var d := UserDB.get_dragon(int(_lvup_ctx["uid"]))
	if d.is_empty(): return
	if is_instance_valid(_lvup_dragon_holder):
		# remove_child 를 함께 해야 같은 프레임에 옛 드래곤이 남아 겹치지 않는다(queue_free 는 프레임 끝).
		var old := _lvup_dragon_holder
		if old.get_parent(): old.get_parent().remove_child(old)
		old.queue_free()
	_lvup_dragon_holder = null
	_lvup_ctx["dragon_ap"] = _lvup_build_dragon(overlay, d, _lvup_ctx["vis"])

## 레벨업 화면의 드래곤 상호작용 모션 — love 를 **보이스와 함께 반복**한다.
## 원작: `CaveScene::onClickDragon` 이 love 재생 + `Dragon::getDragonVoiceDelay` 만큼 늦춰 보이스.
func _lvup_play_love(dap: AnimationPlayer) -> void:
	if not is_instance_valid(dap): return
	dap.play("love")
	_lvup_dragon_voice()

## love 1회가 끝나면 다시 재생(리소스 loop_mode 를 건드리지 않는 반복 방식).
func _lvup_loop_love(anim: StringName, dap: AnimationPlayer) -> void:
	if _lvup_ctx.is_empty() or not is_instance_valid(dap): return
	if anim != &"love": return
	_lvup_play_love(dap)

## 드래곤 보이스 — 성장 단계(baby/child/adult)에 맞는 번호를 `data/dragon_voices.json` 에서 찾는다.
## 원작 표는 유실됐고(`info_dragon_v2` 의 voice 컬럼, Dragon.c:13478-13526),
## **2026-07-31 부터 값은 사용자가 `docs/input/dragons/dragons.csv` 의 voice_해치/해츨링/성체
## 열에 직접 적은 검수분**이다. 반영 = `scripts/tools/build_dragon_voice_sheet.py --apply`.
func _dragon_voice_no(dragon_id: int, level: int) -> int:
	var tbl: Dictionary = Data.dragon_voices.get("voices", {})
	var e: Dictionary = tbl.get(str(dragon_id), {})
	if e.is_empty():
		return 0
	return int(e.get(Growth.stage_for_level(level), 0))

func _play_dragon_voice(dragon_id: int, level: int) -> void:
	var n := _dragon_voice_no(dragon_id, level)
	if n > 0:
		Bgm.sfx("voice%d" % n)

func _lvup_dragon_voice() -> void:
	if _lvup_ctx.is_empty(): return
	var ddef: Dictionary = _lvup_ctx.get("ddef", {})
	var d := UserDB.get_dragon(int(_lvup_ctx["uid"]))
	_play_dragon_voice(int(ddef.get("id", 0)), int(d.get("level", 1)))

## 아틀라스 프레임을 지정 크기로 늘려 그리는 TextureRect(게이지처럼 가로로 늘리는 프레임용).
func _lvup_stretch(name: String, dir: String, size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if ResourceLoader.exists(p): t.texture = load(p)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.material = _pma
	t.size = size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

## 리롤 비용(원작 관찰: 다이아 x2). data 노브 = level_curve.json roll.reroll_cost.
func _lvup_reroll_cost() -> Dictionary:
	var rc: Dictionary = (Data.level_curve.get("roll", {}) as Dictionary).get("reroll_cost", {})
	return {"kind": String(rc.get("kind", "diamond")), "amount": int(rc.get("amount", 2))}

## 화면 갱신(레벨/스탯/아이템/리롤 확률). 람다가 아니라 **메서드**다 — 위 _lvup_ctx 주석 참조.
## fx 를 주면(레벨업/리롤 직후) 우측 열(▶·새 값·(+n/m)·MAX 뱃지)을 숨긴 채 그려 두고
## `_lvup_fx_timeline` 이 원작 ExpLayer 안무로 순차 공개한다(docs/ref/porting/LevelUpScreen.md).
func _lvup_redraw(fx: Dictionary = {}) -> void:
	if _lvup_ctx.is_empty(): return
	var body: Control = _lvup_ctx.get("body")
	var tlabel: Label = _lvup_ctx.get("tlabel")
	if not is_instance_valid(body) or not is_instance_valid(tlabel):
		_lvup_ctx = {}
		return
	# remove_child 를 함께 해야 같은 프레임에 옛 노드가 남아 겹치지 않는다(queue_free 는 프레임 끝에 처리).
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()

	var uid := int(_lvup_ctx["uid"])
	var ddef: Dictionary = _lvup_ctx["ddef"]
	var vis: Vector2 = _lvup_ctx["vis"]
	var d := UserDB.get_dragon(uid)
	if d.is_empty(): return
	var level := int(d.get("level", 1))
	var awakened := bool(d.get("awakened", false))
	var cap := Growth.level_cap(awakened)
	var max_stats := Growth.tier_growth(ddef, Data.stat_table)
	var gain_log: Array = d.get("gain_log", [])
	var roll_cfg: Dictionary = Data.level_curve.get("roll", {})
	var COL_X := vis.x * 0.45      # 우측 스탯 열 시작(참조 405/900 = 0.45)

	# ── 헤더: 이름 + 등급(원작 "말근달님은혜♡    7.1")
	var t := Label.new()
	t.text = Icons.name_of(d)
	_lvup_style(t, 26, Color.WHITE)
	t.position = Vector2(COL_X, vis.y * 0.13); body.add_child(t)
	var gr := Label.new()
	gr.text = "%.1f" % _grade_of(d, ddef)      # 🔴 레벨업 롤(gain_log) 포함 — §K-10
	# 등급 숫자 = 원작 `font/font_rating.fnt`(ExpLayer::setExpStart, 22pt 숫자 전용)
	_lvup_bm_style(gr, 30, Color(1.0, 0.62, 0.12), "font_rating")
	gr.position = Vector2(COL_X + 250, vis.y * 0.13); body.add_child(gr)

	# ── EXP 게이지 — 원작 EXP 게이지 3종 세트 `common/bar_bg2` + `common/bar_exp` + `common/bar_cover`.
	#    근거: EvolLayer.c:1232/1251/1277 이 세 프레임을 그대로 겹쳐 쓴다(DragonAwaken·LaboratoryScene 도 bg2+exp).
	#    (예전엔 9patch/bar1+bar_bg1 자작 조합이었다. `scene/cave/enchant_bar2` 는 마석 인챈트 게이지라 다른 것)
	var ey := vis.y * 0.21
	var expw := _atlas_sprite("adventure_ui", "scene_adventure_bonus_exp_mini",
		_man_adventure(), 0.8 * Design.ASSET_SCALE)
	if expw: expw.position = Vector2(COL_X + 26, ey + 12); body.add_child(expw)
	var bar_size := Vector2(300.0, 18.0)
	var bar_pos := Vector2(COL_X + 60, ey + 3)
	var ebg := _lvup_stretch("common_bar_bg2", "common_ui", bar_size)
	ebg.position = bar_pos; body.add_child(ebg)
	var need := LevelSystem.exp_to_next(Data.level_curve, level)
	var cur := int(d.get("exp", 0))
	var pct := clampf(float(cur) / maxf(1.0, float(need)), 0.0, 1.0)
	var clip := Control.new()                       # 채움은 클리핑으로(프레임을 늘리지 않고 그대로 쓰기 위해)
	clip.position = bar_pos
	clip.size = Vector2(bar_size.x * pct, bar_size.y)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(clip)
	var efill := _lvup_stretch("common_bar_exp", "common_ui", bar_size)
	clip.add_child(efill)
	var ecov := _lvup_stretch("common_bar_cover", "common_ui", bar_size)   # 광택 오버레이
	ecov.position = bar_pos; body.add_child(ecov)
	var etx := Label.new()
	etx.text = "%d / %d" % [cur, need]
	# EXP 카운터 = 원작 font_common(ExpLayer::setExpGageUpShow → NumberingNoneActLabel)
	_lvup_bm_style(etx, 18, Color.WHITE, "font_common")
	etx.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	etx.size = bar_size; etx.position = bar_pos
	body.add_child(etx)

	# ── 스탯표: `이름  before ▶ after (+d/m)` — 원작 형식 그대로.
	# 실 스탯 = base + 영구base보정 + Σgain_log (Growth.main_stats). 🔴 예전엔 결정론 compute_stats 를
	# 썼는데 그건 gain_log 를 안 봐서 **리롤해도 좌우 수치가 안 바뀌었다**(캐릭터 시트와도 불일치).
	var sb2: Dictionary = d.get("stat_bonus", {})
	var base_bonus: Dictionary = sb2.get("base", {})
	var last: Dictionary = gain_log[gain_log.size() - 1] if not gain_log.is_empty() else {}
	var now_st := Growth.main_stats(ddef, Data.stat_table, gain_log, base_bonus)
	var prev_log := gain_log.slice(0, maxi(0, gain_log.size() - 1))
	var prev_st := Growth.main_stats(ddef, Data.stat_table, prev_log, base_bonus)
	var prev_lv := maxi(1, level - 1)
	var rows := [["레벨", Color(1.0, 0.83, 0.25), str(prev_lv), str(level), "", false, false]]
	var maxed_n := 0
	for spec in [["hp", "생명력", Color(0.55, 1.0, 0.55)], ["att", "공격력", Color(1.0, 0.5, 0.45)],
			["def", "방어력", Color(0.5, 0.75, 1.0)]]:
		var k: String = spec[0]
		var mx := int(max_stats.get(k, 1))
		var gain := int(last.get(k, int(now_st[k]) - int(prev_st[k])))
		var trans := gain > mx
		var maxed := gain >= mx
		if maxed: maxed_n += 1
		rows.append([String(spec[1]), spec[2], str(int(prev_st[k])), str(int(now_st[k])),
			"(+%d/%d)" % [gain, mx], maxed, trans])
	var yy := vis.y * 0.29
	# MAX 배지는 **최대치에 도달한 그 스탯 줄**에 붙인다(사용자 지적 2026-07-27).
	# 예전엔 배지를 위에서부터 순서대로 쌓아서, 공격이 미달인데 두 번째 배지가 공격 줄에 떠 헷갈렸다.
	# 서체 = 원작 font_subtitle(ExpLayer 전반), MAX 뱃지 글자 = 흰색·초월만 #EE33FF(ExplayerMaxBonus).
	var fx_on := not fx.is_empty()
	var fx_rows: Array = []
	var badge_no := 0
	for i in rows.size():
		var ry := yy + i * 44.0
		var nm2 := Label.new(); nm2.text = String(rows[i][0])
		_lvup_bm_style(nm2, 26, rows[i][1])
		nm2.position = Vector2(COL_X, ry); body.add_child(nm2)
		var bv := Label.new(); bv.text = String(rows[i][2])
		_lvup_bm_style(bv, 26, Color.WHITE)
		bv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		bv.size = Vector2(96, 32); bv.position = Vector2(COL_X + 100, ry); body.add_child(bv)
		var ar := _atlas_sprite("common_ui", "common_btn_arrow2", _man_common(), 0.75)   # ▶
		if ar: ar.position = Vector2(COL_X + 224, ry + 16); body.add_child(ar)
		var av := Label.new(); av.text = String(rows[i][3])
		_lvup_bm_style(av, 26, Color.WHITE)
		av.position = Vector2(COL_X + 252, ry); body.add_child(av)
		av.pivot_offset = Vector2(0.0, 20.0)    # 롤 확정 팝의 축 = 왼쪽 세로중앙(원작 anchor(0,0.5))
		var dl: Label = null
		if String(rows[i][4]) != "":
			dl = Label.new(); dl.text = String(rows[i][4])
			# 원작 ExplayerValuesUp 계열: 기본 흰색, 초월(Bonus)만 #EE33FF
			_lvup_bm_style(dl, 20, Color("EE33FF") if bool(rows[i][6]) else Color.WHITE)
			dl.position = Vector2(COL_X + 340, ry + 5); body.add_child(dl)
			dl.pivot_offset = Vector2(0.0, 15.0)
		# ── MAX 배지 — 원작 `common/max_bg` + `%dMAX(+)`(ExpLayer::setFullStatus).
		#    맥스를 찍은 **그 스탯 줄**에 붙고, 번호는 찍은 순서(1MAX/2MAX/3MAX). 초월이면 `+`.
		#    스프라이트+라벨을 Node2D 로 묶는다 — 연출(중앙 10배 → 줄로 비행)이 통째로 움직이게.
		var bd: Node2D = null
		if bool(rows[i][5]):
			badge_no += 1
			bd = Node2D.new()
			bd.position = Vector2(COL_X + 470.0, ry + 16.0)
			body.add_child(bd)
			var gbg := _atlas_sprite("common_ui", "common_max_bg", _man_common(), Design.ASSET_SCALE * 0.8)
			if gbg: bd.add_child(gbg)
			var mb := Label.new()
			mb.text = "%dMAX%s" % [badge_no, "+" if bool(rows[i][6]) else ""]
			_lvup_bm_style(mb, 17, Color("EE33FF") if bool(rows[i][6]) else Color.WHITE)
			mb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			mb.size = Vector2(110, 28); mb.position = Vector2(-55, -14)
			bd.add_child(mb)
		if fx_on:
			# 우측 열은 숨긴 채 시작 — 타임라인이 원작 순서(레벨→0.4s→생명→공격→방어)로 공개
			if ar: ar.modulate.a = 0.0
			av.modulate.a = 0.0
			if dl: dl.modulate.a = 0.0
			if bd: bd.visible = false
			fx_rows.append({"is_level": i == 0, "arrow": ar, "av": av,
				"final": String(rows[i][3]), "dl": dl, "maxed": bool(rows[i][5]),
				"trans": bool(rows[i][6]), "badge": bd,
				"badge_pos": Vector2(COL_X + 470.0, ry + 16.0), "ry": ry})

	# ── 스탯표 아래 아이템 슬롯(원작: 아이콘 슬롯 + 잠긴 칸은 자물쇠)
	var can_up := level < cap
	var slot_y := vis.y * 0.575
	var slots := 0
	for key in _LVUP_ITEMS:
		if UserDB.item_count(key) <= 0:
			continue
		_lvup_item_slot(body, key, Vector2(COL_X + 6 + slots * 86.0, slot_y), can_up, level)
		slots += 1
	for i in maxi(0, _LVUP_MIN_SLOTS - slots):
		_lvup_locked_slot(body, Vector2(COL_X + 6 + (slots + i) * 86.0, slot_y))

	# ── 하단 안내 문장
	if gain_log.is_empty():
		tlabel.text = "레벨업 이력이 없습니다.  레벨 아이템으로 레벨을 올리세요."
	else:
		var dn2 := Icons.species_name(int(d["id"]))
		tlabel.text = "%s%s 레벨 %d%s 되었습니다.  (MAX %d)" % [dn2,
			_josa_c(dn2, "은", "는"), level, _josa_c(str(level), "이", "가"), maxed_n]

	# ── 우하단: AUTO + 능력치 다시뽑기(원작 참조 11-12-03-1)
	_lvup_build_reroll(body, vis, roll_cfg, gain_log.is_empty())

	# ── 연출 모드면 타임라인 시작(원작 ExpLayer 안무 — 포팅 카드 "연출 안무" 절)
	if fx_on:
		fx["rows"] = fx_rows
		_lvup_fx_timeline(fx)

## 라벨 공통 서식(원작처럼 굵은 외곽선). 원작 BMFont 는 숫자 전용이라 한글은 TTF(CLAUDE.md §10).
func _lvup_style(l: Label, size: int, col: Color, outline := Color(0, 0, 0, 0.9)) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", 5 if size >= 24 else 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE

# ═════════ 레벨업 연출 타임라인 — 원작 ExpLayer 안무 이식 ═════════
# 근거: docs/ref/porting/LevelUpScreen.md "연출 안무"(ExpLayer.c 디컴프 리터럴, 2026-07-29).
# 대조 영상: docs/ref/LVupEffect/1~22.png(트리플맥스 1회). 시간·배율은 원작 값 그대로,
# sp = 시간 배율(자동 다시뽑기 = 0.5 — 원작은 CCDirector timeScale 2.0).

func _lvt(secs: float) -> void:
	await get_tree().create_timer(maxf(0.01, secs)).timeout

func _lvup_fx_timeline(fx: Dictionary) -> void:
	_lvup_fx_busy = true
	var sp := float(fx.get("sp", 1.0))
	var win: Control = _lvup_ctx.get("win")
	var vis: Vector2 = _lvup_ctx["vis"]
	# 원작도 연출 중 터치를 막는다(ExpLayer 는 TouchController 로 전체 차단).
	# ✔ 닫기 버튼은 win 이 아니라 uilay 소속이라 차단막도 uilay(맨 위)에 얹는다.
	var blocker := Control.new()
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.z_index = _LVUP_UI_Z + 20
	if is_instance_valid(win) and win.get_parent() != null:
		win.get_parent().add_child(blocker)
	fx["blocker"] = blocker
	fx["maxn"] = 0
	match String(fx.get("kind", "up")):
		"up":
			# 사운드는 워드아트 등장과 동시(setExpOrLevelUpValueLabel)
			Bgm.sfx("effect_level_updown")
			await _lvup_wordart_flight(sp)
		"reset":
			# 원작 effect_reset_spine "reset" 워드아트 — 스파인 미보유 → TTF 배너(CLAUDE.md §10)
			Bgm.sfx("effect_level_updown")
			_lvup_word_banner("LEVEL RESET", 1.4)
			await _lvt(0.6 * sp)
		_:
			await _lvt(0.1 * sp)
	if _lvup_ctx.is_empty(): return
	# 성장 단계 경계(10/25) 통과 — 원작 setLevelWithRevolution: upeffect 스파인(미보유) 대신
	# pt_rev_up 파티클 → 1.0s 후 드래곤 교체 → 1.0s 대기. (종전 "원작에 연출 없음" 주석은 오판)
	if bool(fx.get("stage_changed", false)):
		CocosParticle.spawn(self, "pt_rev_up", Vector2(vis.x * 0.20, vis.y * 0.55), 135, 0.6)
		await _lvt(1.0 * sp)
		if _lvup_ctx.is_empty(): return
		_lvup_refresh_dragon()
		_notify("on_evolved")   # 호스트(동굴)의 받침대·목록 갱신 훅
		_notify("on_evolved")
		await _lvt(1.0 * sp)
	if _lvup_ctx.is_empty(): return
	# 행 공개(setShowStatus): 레벨 → 0.4s → 생명력 → 0.4s → 공격력 → 0.4s → 방어력
	var rows: Array = fx.get("rows", [])
	fx["pending"] = rows.size()
	for i in rows.size():
		if i > 0:
			await _lvt(0.4 * sp)
			if _lvup_ctx.is_empty(): return
		_lvup_fx_row(fx, i)
	# 행들은 병렬 코루틴 — 전부 확정(배지·컷인 포함)될 때까지 대기
	while int(fx.get("pending", 0)) > 0:
		if _lvup_ctx.is_empty(): return
		await _lvt(0.1)
	# 마지막 행 확정 +2.0s → 슬롯 개방 체크 → +0.3s → 마무리(setSkillSlotCheck/FullStatusFinish)
	await _lvt(2.0 * sp)
	if _lvup_ctx.is_empty():
		_lvup_fx_busy = false
		return
	_lvup_fx_slot_open(fx)
	await _lvt(0.3 * sp)
	# 마무리 — 재-redraw 는 하지 않는다: 연출이 남긴 상태(맥동 ▶/뱃지, 부유 워드아트)가
	# 곧 원작의 잔류 상태다(setArrowForever/setMaxForever/setFeatherForever 전부 무한 루프).
	_lvup_fx_busy = false
	var blk = fx.get("blocker")
	if is_instance_valid(blk): blk.queue_free()

## LEVEL UP 워드아트 비행 — 원작 effect_levelupdown_spine "up"(스파인 미보유 → 자작 크롭).
## 경로 = setExpOrLevelUpValueLabel 리터럴. 원작 정착 scale 0.27 = 우리 정적 크기 1.0 ⇒ ×1/0.27.
func _lvup_wordart_flight(sp: float) -> void:
	var art: TextureRect = _lvup_ctx.get("art")
	var vis: Vector2 = _lvup_ctx["vis"]
	if not is_instance_valid(art):
		await _lvt(0.5 * sp)
		return
	# 직전 비행/부유 트윈 정리(중첩 방지)
	if _lvup_ctx.get("art_tweens") is Array:
		for t in _lvup_ctx["art_tweens"]:
			if t is Tween and t.is_valid(): t.kill()
	var tws: Array = []
	_lvup_ctx["art_tweens"] = tws
	art.pivot_offset = art.size * 0.5
	var home: Vector2 = _lvup_art_home(vis, art.size)         # _open_levelup 의 정위치
	var K := 1.0 / 0.27
	art.position = Vector2(vis.x * 0.5 - art.size.x * 0.5, vis.y + 60.0)   # 원작 y=-160(화면 밖 아래)
	art.scale = Vector2.ONE * (0.5 * K)
	var y1 := art.position.y - (vis.y / 3.0 + 200.0)
	var y2 := y1 - vis.y / 3.0
	var tw := art.create_tween()
	tws.append(tw)
	tw.tween_property(art, "position:y", y1, 0.5 * sp)              # ① 상승
	tw.parallel().tween_property(art, "scale", Vector2.ONE * (0.45 * K), 0.5 * sp)
	tw.tween_property(art, "scale", Vector2.ONE * (0.4 * K), 0.5 * sp)   # ② 숨고르기
	# ③ 정점 확대 — 원작은 이 시점 CCCallFuncN 로 FeatherLayer(깃털 12장)를 얹는다
	tw.tween_callback(func():
		if not _lvup_ctx.is_empty() and is_instance_valid(art):
			_lvup_feather_burst(art.position + art.size * 0.5))
	tw.tween_property(art, "position:y", y2, 0.5 * sp)
	tw.parallel().tween_property(art, "scale", Vector2.ONE * (0.85 * K), 0.5 * sp)
	tw.tween_property(art, "scale", Vector2.ONE * (0.7 * K), 0.25 * sp)  # ④ 수축
	tw.tween_interval(0.25 * sp)
	await tw.finished
	if not is_instance_valid(art) or _lvup_ctx.is_empty(): return
	# ⑤ 좌상단 정위치로 점프(원작 JumpTo 높이 100) + 원래 크기 → ⑥ 바운스
	var from := art.position
	var jump := func(t: float):
		if is_instance_valid(art):
			var p := from.lerp(home, t)
			p.y -= 100.0 * sin(PI * t)
			art.position = p
	var jt := art.create_tween()
	tws.append(jt)
	jt.tween_method(jump, 0.0, 1.0, 0.5 * sp)
	jt.parallel().tween_property(art, "scale", Vector2.ONE, 0.5 * sp)
	jt.tween_property(art, "position:y", home.y + 10.0, sp / 6.0)
	jt.parallel().tween_property(art, "scale", Vector2.ONE * 0.93, sp / 6.0)
	jt.tween_property(art, "position:y", home.y, sp / 6.0)
	jt.parallel().tween_property(art, "scale", Vector2.ONE, sp / 6.0)
	await jt.finished
	if not is_instance_valid(art) or _lvup_ctx.is_empty(): return
	# ⑦ 부유 루프(setFeatherForever: 1s +20px·+0.03 ↔ 1s 복귀)
	var fl := art.create_tween().set_loops()
	tws.append(fl)
	fl.tween_property(art, "position:y", home.y - 20.0, 1.0)
	fl.parallel().tween_property(art, "scale", Vector2.ONE * 1.03, 1.0)
	fl.tween_property(art, "position:y", home.y, 1.0)
	fl.parallel().tween_property(art, "scale", Vector2.ONE, 1.0)

## 깃털 버스트 — 원작 FeatherLayer::initWiget 1:1(완전 디컴프): 컬러 깃털 feather1~3 ×4 = 12장.
## 각: Spawn(MoveBy 0.25 Δ, RotateBy Δx°, ScaleTo 1.7) → Spawn(EaseExpOut(MoveBy 0.5 2Δ),
## RotateBy, ScaleTo 1.5) → FadeOut 0.5 → 제거. 파티클 = particle/scenario/pt_feature_c.
## Δ 쌍의 정확한 배정은 디컴프 지역변수 압축으로 불확실 → 계수(±20~±120)만 살린 산포.
## # ASSUMPTION: Δ 12쌍의 x·y 짝짓기(원작 FeatherLayer.c:346-375 재구성 불확실)
func _lvup_feather_burst(center: Vector2) -> void:
	if _lvup_ctx.is_empty(): return
	var win: Control = _lvup_ctx.get("win")
	if not is_instance_valid(win): return
	CocosParticle.spawn(win, "pt_feature_c", center + Vector2(0, 30), _LVUP_UI_Z + 6, 0.8)
	var offs := [Vector2(-70, -30), Vector2(-100, 20), Vector2(-120, 50), Vector2(-20, 5),
		Vector2(70, 25), Vector2(50, 100), Vector2(90, 60), Vector2(100, 20),
		Vector2(60, -25), Vector2(-50, 80), Vector2(30, -60), Vector2(110, -45)]
	var cman := _man_common()
	for i in offs.size():
		var s := _atlas_sprite("common_ui", "common_feather%d" % (1 + (i % 3)), cman, Design.ASSET_SCALE)
		if s == null: continue
		s.position = center
		s.z_index = _LVUP_UI_Z + 6
		win.add_child(s)
		var d: Vector2 = offs[i] * Design.ASSET_SCALE
		d.y = -d.y                     # cocos y-up → godot y-down
		var base: Vector2 = s.scale
		var tw := s.create_tween()
		tw.tween_property(s, "position", center + d, 0.25)
		tw.parallel().tween_property(s, "rotation_degrees", offs[i].x, 0.25)
		tw.parallel().tween_property(s, "scale", base * 1.7, 0.25)
		tw.tween_property(s, "position", center + d * 3.0, 0.5)\
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(s, "rotation_degrees", offs[i].x * 2.0, 0.5)
		tw.parallel().tween_property(s, "scale", base * 1.5, 0.5)
		tw.tween_property(s, "modulate:a", 0.0, 0.5)
		tw.tween_callback(s.queue_free)

## 행 하나의 공개+롤+확정 코루틴(fire-and-forget — 타임라인이 pending 으로 합류).
func _lvup_fx_row(fx: Dictionary, idx: int) -> void:
	var sp := float(fx.get("sp", 1.0))
	var rows: Array = fx["rows"]
	var row: Dictionary = rows[idx]
	# ▶ FadeIn 0.15 + setArrowForever(0.5s 단계 ±0.035 맥동 루프)
	var ar: Node2D = row.get("arrow")
	if is_instance_valid(ar):
		ar.create_tween().tween_property(ar, "modulate:a", 1.0, 0.15 * sp)
		var abase: Vector2 = ar.scale
		var al := ar.create_tween().set_loops()
		al.tween_property(ar, "scale", abase * 1.047, 0.5)
		al.tween_property(ar, "scale", abase, 0.5)
		al.tween_property(ar, "scale", abase * 0.953, 0.5)
		al.tween_property(ar, "scale", abase, 0.5)
	var av: Label = row.get("av")
	if not is_instance_valid(av):
		fx["pending"] = int(fx["pending"]) - 1
		return
	if bool(row.get("is_level", false)):
		# 레벨 값 팝(setUpLabelValues 0x6a): FadeIn 0.1 + ScaleTo(0.15, 2.0) → ScaleTo(0.1, 1.1)
		av.scale = Vector2.ONE * 0.5
		var lt := av.create_tween()
		lt.tween_property(av, "modulate:a", 1.0, 0.1 * sp)
		lt.parallel().tween_property(av, "scale", Vector2.ONE * 2.0, 0.15 * sp)
		lt.tween_property(av, "scale", Vector2.ONE * 1.1, 0.1 * sp)
		fx["pending"] = int(fx["pending"]) - 1
		return
	await _lvup_digit_roll(av, String(row.get("final", "")), sp)
	if _lvup_ctx.is_empty(): return
	# (+n/m) 팝(FinishNumbering: 0.15s +0.1 → 0.1s 복귀)
	var dl: Label = row.get("dl")
	if is_instance_valid(dl):
		dl.modulate.a = 1.0
		dl.scale = Vector2.ONE * 0.8
		var dt := dl.create_tween()
		dt.tween_property(dl, "scale", Vector2.ONE * 1.1, 0.15 * sp)
		dt.tween_property(dl, "scale", Vector2.ONE, 0.1 * sp)
	# 확정 반짝이 — # ASSUMPTION: 영상의 금색 별의 소유 이펙트 미특정 → pt_levelup_light 근사
	var body: Control = _lvup_ctx.get("body")
	if is_instance_valid(body):
		CocosParticle.spawn(body, "pt_levelup_light", av.position + Vector2(50, 16), 8, 0.9, 60)
	await _lvt(0.3 * sp)         # confirm 지연(원작 scheduleOnce 0.3)
	if _lvup_ctx.is_empty(): return
	if bool(row.get("maxed", false)):
		await _lvup_fx_badge(fx, row)
	fx["pending"] = int(fx["pending"]) - 1

## 슬롯머신 숫자 롤 — 원작 NumberingLabel: 자릿수별 순환(tick 0.07s), 좌→우 0.2s 간격 확정,
## 확정 팝(0.1s −0.25 → 0.2s +0.25 → 0.1s 복귀). 확정 시작 시점(0.8s)은 # ASSUMPTION
## (원작은 외부 스케줄이 ShowNumber 를 쏜다 — 영상 체감 길이에 맞춤).
func _lvup_digit_roll(av: Label, final_text: String, sp: float) -> void:
	av.modulate.a = 1.0
	var n := final_text.length()
	if n == 0: return
	var counters: Array = []
	for i in n:
		counters.append((i * 3) % 10)     # 자리마다 다른 시작값(원작 0.1s 시차의 근사)
	var t := 0.0
	var lock_start := 0.8
	while true:
		if not is_instance_valid(av) or _lvup_ctx.is_empty(): return
		var locked := 0
		if t >= lock_start:
			locked = clampi(1 + int(floor((t - lock_start) / 0.2)), 0, n)
		if locked >= n: break
		var s := ""
		for i in n:
			s += final_text[i] if i < locked else str(counters[i])
			if i >= locked:
				counters[i] = (int(counters[i]) + 1) % 10
		av.text = s
		await _lvt(0.07 * sp)
		t += 0.07
	av.text = final_text
	var tw := av.create_tween()
	tw.tween_property(av, "scale", Vector2.ONE * 0.75, 0.1 * sp)
	tw.tween_property(av, "scale", Vector2.ONE * 1.25, 0.2 * sp)
	tw.tween_property(av, "scale", Vector2.ONE, 0.1 * sp)
	await tw.finished

## MAX 뱃지 플라이인 — 원작 setFullStatus. 착지 scale 0.5 = 우리 정적 1.0 ⇒ 환산 ×2.
## 1·2MAX: 중앙 scale 10(=20) 투명 → 0.2s 비행·0.3(=0.6) 착지 → 0.2s 팝 0.5(=1.0) → 맥동.
## 3MAX: FadeIn 0.1·2.0(=4) → 0.2s 3.0(=6) → 0.5s 유지 → 비행 + 트리플맥스 연출.
func _lvup_fx_badge(fx: Dictionary, row: Dictionary) -> void:
	var sp := float(fx.get("sp", 1.0))
	var bd: Node2D = row.get("badge")
	if not is_instance_valid(bd) or _lvup_ctx.is_empty(): return
	var vis: Vector2 = _lvup_ctx["vis"]
	var n := int(fx.get("maxn", 0)) + 1
	fx["maxn"] = n
	var target: Vector2 = row["badge_pos"]
	bd.visible = true
	bd.z_index = 10
	bd.position = vis * 0.5
	bd.modulate.a = 0.0
	if n < 3:
		bd.scale = Vector2.ONE * 20.0
		var tw := bd.create_tween()
		tw.set_parallel(true)
		tw.tween_property(bd, "modulate:a", 1.0, 0.2 * sp)
		tw.tween_property(bd, "position", target, 0.2 * sp)
		tw.tween_property(bd, "scale", Vector2.ONE * 0.6, 0.2 * sp)
		await tw.finished
		if not is_instance_valid(bd): return
		# 보유 원본 MAX 효과음. 배지가 능력치 옆 목표점에 닿는 바로 그 프레임에 재생한다.
		Bgm.sfx("effect_max_fun")
		_lvup_shake()          # 원작 +0.3s setShakeView — 착지 직후로 근사
		var tw2 := bd.create_tween()
		tw2.tween_property(bd, "scale", Vector2.ONE, 0.2 * sp)
		await tw2.finished
	else:
		bd.scale = Vector2.ONE * 2.0
		var tw := bd.create_tween()
		tw.tween_property(bd, "modulate:a", 1.0, 0.1 * sp)
		tw.parallel().tween_property(bd, "scale", Vector2.ONE * 4.0, 0.2 * sp)
		tw.tween_property(bd, "scale", Vector2.ONE * 6.0, 0.2 * sp)
		tw.tween_interval(0.5 * sp)
		tw.tween_property(bd, "position", target, 0.2 * sp)\
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(bd, "scale", Vector2.ONE * 0.6, 0.2 * sp)
		await tw.finished
		if not is_instance_valid(bd) or _lvup_ctx.is_empty(): return
		Bgm.sfx("effect_max_fun")
		_lvup_fx_triple()
		_lvup_shake()
		var tw2 := bd.create_tween()
		tw2.tween_property(bd, "scale", Vector2.ONE, 0.2 * sp)
		await tw2.finished
	if not is_instance_valid(bd): return
	# setMaxForever: 0.2s +0.05(=+0.1) ↔ 0.2s 복귀, 0.3s 쉼 — 무한 맥동
	var ml := bd.create_tween().set_loops()
	ml.tween_property(bd, "scale", Vector2.ONE * 1.1, 0.2)
	ml.tween_property(bd, "scale", Vector2.ONE, 0.2)
	ml.tween_interval(0.3)

## 트리플맥스 — 원작 set3MaxParticle: 컷인(Cutin::show speed=3.0 슬로우) + 크리티컬 보이스 +
## "트리플 맥스"(font_title — cutin.gd 배너) + pt_3max1/2 아치 스윕(JumpBy 0.5s, 높이 H×0.4).
## 사운드 effect_max_fun 은 사용자 확정(2026-07-27) — 원작 뱃지 사운드명은 람다에 묻혀 미특정.
func _lvup_fx_triple() -> void:
	if _lvup_ctx.is_empty(): return
	var ddef: Dictionary = _lvup_ctx.get("ddef", {})
	var d := UserDB.get_dragon(int(_lvup_ctx["uid"]))
	_lvup_dragon_voice()      # 원작은 크리티컬 보이스 — 보이스표 유실로 단계 보이스 근사
	DragonCutin.show(self, {
		"id": int(ddef.get("id", 0)),
		"element": String(ddef.get("element", "")),
		"awakened": bool(d.get("awakened", false)),
	}, 1.0 / 3.0, "트리플 맥스", 60)          # speed 1/3 = 원작 param_2 3.0 슬로우
	var vis: Vector2 = _lvup_ctx["vis"]
	var lay := CanvasLayer.new(); lay.layer = 61   # 컷인(60) 위
	add_child(lay)
	for pname in ["pt_3max1", "pt_3max2"]:
		var p := CocosParticle.spawn(lay, pname, Vector2(-60.0, vis.y * 0.5), 1, 0.3)
		if p:
			var base_y := vis.y * 0.5
			var arc := func(t: float):
				if is_instance_valid(p):
					p.position = Vector2(-60.0 + (vis.x + 120.0) * t,
						base_y - vis.y * 0.4 * sin(PI * t))
			p.create_tween().tween_method(arc, 0.0, 1.0, 0.5 * 3.0)
	get_tree().create_timer(3.5).timeout.connect(func():
		if is_instance_valid(lay): lay.queue_free())

## 화면 셰이크 — 원작 setShakeView. win 을 ±수 px 흔들고 복귀.
func _lvup_shake() -> void:
	var win: Control = _lvup_ctx.get("win")
	if not is_instance_valid(win): return
	var orig: Vector2 = win.position
	var tw := win.create_tween()
	for off in [Vector2(6, 4), Vector2(-5, -3), Vector2(4, 2), Vector2(-2, -2)]:
		tw.tween_property(win, "position", orig + off, 0.04)
	tw.tween_property(win, "position", orig, 0.04)

## Lv10/35 도달 → "추가 슬롯 개방!!"(원작 <NewSlotOpen>, setChangeNewSlot):
## 스킬 슬롯 모양 bg FadeIn 0.7 + ScaleTo(1.0, +0.1) → ScaleTo(0.3, 복귀) + 라벨 FadeIn 0.5
## + pt_take_skill. 위치는 스탯표와 아이템 슬롯 사이(# ASSUMPTION: 원작은 패널 내 슬롯 자리).
func _lvup_fx_slot_open(fx: Dictionary) -> void:
	var slot := int(fx.get("slot_new", -1))
	if slot < 0 or _lvup_ctx.is_empty(): return
	var vis: Vector2 = _lvup_ctx["vis"]
	var win: Control = _lvup_ctx.get("win")
	if not is_instance_valid(win): return
	var d := UserDB.get_dragon(int(_lvup_ctx["uid"]))
	var types: Array = d.get("skill_slots", [])
	var shape := String(types[slot]) if slot < types.size() else "star"
	var holder := Node2D.new()
	holder.position = Vector2(vis.x * 0.47, vis.y * 0.52)
	holder.z_index = _LVUP_UI_Z + 10
	win.add_child(holder)
	var bg := _atlas_sprite("common_ui", "common_skill_%s_bg" % shape, _man_common(), Design.ASSET_SCALE)
	if bg:
		bg.modulate.a = 0.0
		holder.add_child(bg)
		var bbase: Vector2 = bg.scale
		var tw := bg.create_tween()
		tw.tween_property(bg, "modulate:a", 1.0, 0.7)
		tw.parallel().tween_property(bg, "scale", bbase * 1.2, 1.0)
		tw.tween_property(bg, "scale", bbase, 0.3)
	var l := Label.new()
	l.text = "추가 슬롯 개방!!"
	_lvup_bm_style(l, 24, Color.WHITE)
	l.position = Vector2(42, -16)
	l.modulate.a = 0.0
	holder.add_child(l)
	l.create_tween().tween_property(l, "modulate:a", 1.0, 0.5)
	CocosParticle.spawn(holder, "pt_take_skill", Vector2.ZERO, 1, 0.8, 80)
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(holder): holder.queue_free())

## 레벨 아이템 슬롯 1칸 — `common/item_box` 틀 + `item/item_small/<key>` 아이콘 + 보유수 배지.
func _lvup_item_slot(body: Control, key: String, pos: Vector2, can_up: bool, level: int) -> void:
	var cman := _man_common()
	var bx := _atlas_sprite("common_ui", "common_item_box", cman, Design.ASSET_SCALE)
	if bx: bx.position = pos + Vector2(38, 38); body.add_child(bx)
	var icon := _atlas_sprite("item_small_ui", "item_item_small_%s" % key, _item_small_manifest, 0.86)
	if icon: icon.position = pos + Vector2(38, 38); body.add_child(icon)
	var cnt := UserDB.item_count(key)
	var badge := Label.new()
	badge.text = "%d" % cnt
	_lvup_style(badge, 18, Color(1, 1, 1))
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.size = Vector2(66, 22); badge.position = pos + Vector2(4, 52)
	body.add_child(badge)
	# 투명 버튼을 슬롯 위에 덮는다(원작도 슬롯 자체가 버튼).
	var b := Button.new()
	b.flat = true
	b.size = Vector2(76, 76); b.position = pos
	b.tooltip_text = "%s%s" % [Data.item_name(key),
		{"": "", "max1": " (맥스 1 보장)", "max2": " (맥스 2 보장)",
		 "triple": " (트리플맥스)", "amor": " (전 스탯 초월맥스)"}.get(String(_LVUP_GUARANTEE.get(key, "")), "")]
	var usable := (key != "level_down" and can_up) or (key == "level_down" and level > 1)
	b.disabled = not usable
	b.pressed.connect(_lvup_use_item.bind(key))
	body.add_child(b)

## 잠긴 슬롯 — 원작 `common/lock`.
func _lvup_locked_slot(body: Control, pos: Vector2) -> void:
	var bx := _atlas_sprite("common_ui", "common_item_box", _man_common(), Design.ASSET_SCALE)
	if bx:
		bx.position = pos + Vector2(38, 38); bx.modulate = Color(0.6, 0.6, 0.6, 1.0)
		body.add_child(bx)
	var lk := _atlas_sprite("common_ui", "common_lock", _man_common(), Design.ASSET_SCALE * 0.8)
	if lk: lk.position = pos + Vector2(38, 38); body.add_child(lk)

## 레벨 아이템 사용. 축복=맥스 보장 롤, Lv+1=일반 롤, Lv-1=직전 롤 무효.
## 레벨업/축복은 원작 ExpLayer 안무(_lvup_fx_timeline)를 태운다 — 사운드·컷인·진화 반영 전부
## 타임라인 소관. 레벨다운만 종전 즉시 갱신(원작 "down" 워드아트 스파인 미보유 → TTF 배너).
func _lvup_use_item(key: String) -> void:
	if _lvup_ctx.is_empty() or _lvup_fx_busy: return
	var uid := int(_lvup_ctx["uid"])
	var ddef: Dictionary = _lvup_ctx["ddef"]
	if UserDB.item_count(key) <= 0: return
	var d := UserDB.get_dragon(uid)
	var level := int(d.get("level", 1))
	var old_stage := Growth.stage_for_level(level)
	if key == "level_down":
		if level <= 1 or not UserDB.level_down(uid): return
		UserDB.add_item("level_down", -1)
		Bgm.sfx("effect_level_updown")
		_lvup_word_banner("LEVEL DOWN", 1.4, Color(0.86, 0.66, 1.0), Color(0.24, 0.05, 0.34, 1.0))
		_lvup_ctx["reroll"] = 0
		_notify("on_changed")
		_lvup_redraw()
		var down_stage := Growth.stage_for_level(int(UserDB.get_dragon(uid).get("level", 1)))
		if down_stage != old_stage:
			_lvup_refresh_dragon()
			_notify("on_evolved")
			_notify("on_evolved")
		return
	if level >= Growth.level_cap(bool(d.get("awakened", false))): return
	var max_stats := Growth.tier_growth(ddef, Data.stat_table)
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var roll := LevelSystem.roll_level(Data.level_curve.get("roll", {}), max_stats, rng,
		0.0, String(_LVUP_GUARANTEE.get(key, "")))
	# level_up_with 안에서 레벨 10·25·45 자동 습득(sync_skill_grants)이 함께 돈다 → 증분을 알린다.
	var sk_before := UserDB.dragon_skills(uid).size()
	UserDB.level_up_with(uid, roll)
	var sk_new := _skills_learned_since(uid, sk_before)
	if not sk_new.is_empty():
		Toast.show(self, "새 스킬 습득 — %s" % ", ".join(sk_new))
	UserDB.add_item(key, -1)
	_lvup_ctx["reroll"] = 0        # 새 레벨 → 리롤 천장 리셋
	var new_level := int(UserDB.get_dragon(uid).get("level", 1))
	# Lv10/35 스킬 슬롯 해금 경계 통과 감지(원작 setSkillSlotCheck → "추가 슬롯 개방!!")
	var slot_new := -1
	for si in Loadout.SLOT_UNLOCK_LEVEL.size():
		var lreq := int(Loadout.SLOT_UNLOCK_LEVEL[si])
		if level < lreq and new_level >= lreq:
			slot_new = si
	_notify("on_changed")
	_lvup_redraw({"kind": "up", "sp": 1.0,
		"stage_changed": Growth.stage_for_level(new_level) != old_stage,
		"slot_new": slot_new, "triple": bool(roll.get("triple", false))})

## 우하단 리롤 블록 — AUTO 버튼 + 회전화살표 + "능력치 다시뽑기" + 다이아 비용.
## 참조: docs/ref/orig_image/levelup/Screenshot_2017-02-27-11-12-03-1.png
func _lvup_build_reroll(body: Control, vis: Vector2, roll_cfg: Dictionary, no_history: bool) -> void:
	var cman := _man_common()
	var cost := _lvup_reroll_cost()
	var have := UserDB.currency(String(cost["kind"]))
	var affordable := have >= int(cost["amount"])
	var bx := vis.x * 0.60
	var by := vis.y * 0.70   # 블록 전체가 하단 텍스트박스(위쪽 경계 = vis.y-120) 위에 오도록

	# AUTO(원작 common/bt_levelupauto_on|off, 문자열 DragonResetAuto "다시뽑기 자동").
	# ⚠️ 자동 반복은 다이아를 크게 소모한다(원작 DragonResetAutoConfirm 경고) → 확인 후 트리플맥스까지 반복.
	var auto_on := bool(_lvup_ctx.get("auto", false))
	var ab := TextureButton.new()
	var ap := "res://assets/converted/common_ui/common_bt_levelupauto_%s.tres" % ("on" if auto_on else "off")
	if ResourceLoader.exists(ap):
		ab.texture_normal = load(ap)
		ab.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	ab.position = Vector2(bx, by + 6)
	ab.disabled = no_history
	ab.tooltip_text = "다시뽑기 자동"
	ab.pressed.connect(_lvup_toggle_auto)
	body.add_child(ab)

	# 회전화살표 아이콘 = 원작 `common/stat_reflash`("stat refresh" — 능력치 다시뽑기 전용 아이콘).
	# ⚠️ `common/refresh` 는 돋보기다(BookPopup/SkinPopup 의 목록 갱신용) — 혼동 금지.
	var ix := bx + 110.0
	var iy := by + 34.0
	var ric := _atlas_sprite("common_ui", "common_stat_reflash", cman, Design.ASSET_SCALE * 0.72)
	if ric:
		ric.position = Vector2(ix, iy)
		if not affordable or no_history: ric.modulate = Color(0.55, 0.55, 0.55)
		body.add_child(ric)

	# "(MAX 확률 x% ▲)" — 원작 DragonResetMax1 + `common/maxpercent_arrow` + DragonResetMax2
	var pity := LevelSystem.pity_prob(roll_cfg, int(_lvup_ctx.get("reroll", 0)))
	var mp := Label.new()
	mp.text = "(MAX 확률 %.1f%%" % (pity * 100.0)
	_lvup_style(mp, 17, Color(1, 0.78, 0.2))
	mp.position = Vector2(ix + 46, by - 2); body.add_child(mp)
	var mpa := _atlas_sprite("common_ui", "common_maxpercent_arrow", cman, Design.ASSET_SCALE)
	var mpw: float = ThemeDB.fallback_font.get_string_size(mp.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	if mpa: mpa.position = Vector2(ix + 56 + mpw, by + 10); body.add_child(mpa)
	var mpc := Label.new()
	mpc.text = ")"
	_lvup_style(mpc, 17, Color(1, 0.78, 0.2))
	mpc.position = Vector2(ix + 66 + mpw, by - 2); body.add_child(mpc)

	# "능력치 다시뽑기" — 원작 DragonReset
	var lb := Label.new()
	lb.text = "능력치 다시뽑기"
	_lvup_style(lb, 23, Color.WHITE if affordable else Color(0.65, 0.65, 0.65))
	lb.position = Vector2(ix + 46, by + 20); body.add_child(lb)

	# 비용: 다이아 아이콘 + "x N"
	var di := _atlas_sprite("common_ui", "common_diamond_small1", cman, Design.ASSET_SCALE * 0.9)
	if di: di.position = Vector2(ix + 62, by + 66); body.add_child(di)
	var cl := Label.new()
	cl.text = "x %d" % int(cost["amount"])
	_lvup_style(cl, 22, Color.WHITE if affordable else Color(1.0, 0.45, 0.45))
	cl.position = Vector2(ix + 84, by + 52); body.add_child(cl)

	# 클릭 영역(아이콘+문구 전체)
	var hit := Button.new()
	hit.flat = true
	hit.name = "RerollButton"        # 스모크 테스트(shot_helper --shot=lvreroll)가 이름으로 찾는다
	hit.size = Vector2(240, 96); hit.position = Vector2(ix - 34, by - 6)
	hit.disabled = no_history or not affordable
	hit.tooltip_text = ("보유 %s %d" % [String(cost["kind"]), have]) if not affordable else ""
	hit.pressed.connect(_lvup_ask_reroll)
	body.add_child(hit)

## 원작 DragonResetConfirm — "다이아를 소모하여 능력치를 다시 뽑으시겠습니까?"
func _lvup_ask_reroll() -> void:
	PopupType.open(self, "능력치 다시뽑기", "다이아를 소모하여 능력치를 다시 뽑으시겠습니까?",
		func(): _lvup_do_reroll_once())

## 원작 DragonResetAutoConfirm — 자동은 다이아를 크게 소모하므로 확인을 받는다.
func _lvup_toggle_auto() -> void:
	if _lvup_ctx.is_empty(): return
	if bool(_lvup_ctx.get("auto", false)):
		_lvup_ctx["auto"] = false
		_lvup_redraw()
		return
	PopupType.open(self, "다시뽑기 자동", "다시뽑기를 자동으로 하시겠습니까?\n이 경우, 다이아가 많이 소모될 수 있습니다.",
		func():
			if _lvup_ctx.is_empty(): return
			_lvup_ctx["auto"] = true
			_lvup_redraw()
			_lvup_auto_loop())

## 자동 다시뽑기: 트리플맥스가 나오거나 다이아가 떨어질 때까지 반복(오프라인 재구성).
func _lvup_auto_loop() -> void:
	while not _lvup_ctx.is_empty() and bool(_lvup_ctx.get("auto", false)):
		if not _lvup_do_reroll_once():
			break
		# 연출(원작 안무, 자동은 2배속 = sp 0.5)이 끝날 때까지 대기 — 원작도 연출 완료 후 반복.
		while _lvup_fx_busy:
			await get_tree().create_timer(0.1).timeout
			if _lvup_ctx.is_empty(): return
		var d := UserDB.get_dragon(int(_lvup_ctx["uid"]))
		var gl: Array = d.get("gain_log", [])
		var mx := Growth.tier_growth(_lvup_ctx["ddef"], Data.stat_table)
		if not gl.is_empty():
			var lastg: Dictionary = gl[gl.size() - 1]
			var all_max := true
			for k in ["hp", "att", "def"]:
				if int(lastg.get(k, 0)) < int(mx.get(k, 1)): all_max = false
			if all_max: break
		await get_tree().create_timer(0.3).timeout
	if not _lvup_ctx.is_empty():
		_lvup_ctx["auto"] = false
		_lvup_redraw()

## 능력치 다시뽑기 1회: 다이아 소비 → 직전 레벨 롤 교체(리롤 천장 pity 반영). 반환=성공.
## 트리플맥스가 나오면 천장 리셋. 비용은 data 노브(원작 관찰: 다이아 2).
## 연출은 원작 ExpLayer 리셋 안무(_lvup_fx_timeline kind="reset") — 배너·사운드·컷인 전부 타임라인.
func _lvup_do_reroll_once() -> bool:
	if _lvup_ctx.is_empty() or _lvup_fx_busy: return false
	var uid := int(_lvup_ctx["uid"])
	var ddef: Dictionary = _lvup_ctx["ddef"]
	var cost := _lvup_reroll_cost()
	var kind := String(cost["kind"])
	var amount := int(cost["amount"])
	if UserDB.currency(kind) < amount: return false
	if (UserDB.get_dragon(uid).get("gain_log", []) as Array).is_empty(): return false
	var roll_cfg: Dictionary = Data.level_curve.get("roll", {})
	var max_stats := Growth.tier_growth(ddef, Data.stat_table)
	var pity := LevelSystem.pity_prob(roll_cfg, int(_lvup_ctx.get("reroll", 0)))
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var roll := LevelSystem.roll_level(roll_cfg, max_stats, rng, pity, "")
	if not UserDB.spend(kind, amount): return false
	if not UserDB.replace_last_gain(uid, roll): return false
	_lvup_ctx["reroll"] = 0 if bool(roll.get("triple", false)) else int(_lvup_ctx.get("reroll", 0)) + 1
	_notify("on_changed")
	_lvup_redraw({"kind": "reset", "sp": 0.5 if bool(_lvup_ctx.get("auto", false)) else 1.0,
		"stage_changed": false, "slot_new": -1, "triple": bool(roll.get("triple", false))})
	return true
