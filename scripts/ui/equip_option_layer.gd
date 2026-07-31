class_name EquipOptionLayer
extends Control
## 장비 **제련**(부가 옵션 변경) 창 — 원작 `ItemEquipSelectPopup::requestRegenEquip`
## → `ItemEquipOptionLayer`(마법진 연출) → 제련 결과 두 카드. render 층(CLAUDE.md §8.1).
##
## 참조 프레임 = `docs/ref/equip/동전사용1~10.png` · `옵션클릭시.png` · `옵션선택클릭시.png` ·
## `재시도클릭시.png`(사용자 제공 연출 영상).
## 디컴프 = `docs/ref/orig_code/decomp/ItemEquipSelectPopup.c`(요청/응답) ·
## `ItemEquipOptionLayer.c`(연출 — `scene/magicshop/recall_magic_circle_1/2` +
## `music/effect_roulette.mp3` → `music/effect_upgrade.mp3` + `common/check_btn`).
##
## 흐름(참조 영상 그대로):
##   ① 가방에서 **기누의 동전**을 고르고 `선택`
##   ② `[등급] 장비 선택` 목록에서 대상 장비를 고른다      ← 호출부(cave.gd)가 담당
##   ③ 확인창 `<EquipeSelectMsg1>` "해당 장비의 부가 옵션을 변경하시겠습니까?" + 동전 수량
##   ④ **마법진 연출** — 이 클래스 `_play_circle()`
##   ⑤ 제련 창 — `기존 옵션` / `제련 옵션` 두 카드 + `선택` / `재시도`
##      · 카드 클릭 = 그 카드를 고른 상태(노란 테두리)
##      · `선택` → `<acc_msg_select_before>` / `<acc_msg_select_after>` 확인창 → 적용
##      · `재시도` → `<acc_msg_select_retry>` 확인창 → 동전 1개 더 쓰고 제련 옵션만 다시 굴린다
##      · 고른 카드 없이 `선택` → `<acc_msg_non_select>`

signal finished

# ---------- 원작 문자열(`DV2/string/stringsData_KR.xml`) ----------
const S_TITLE := "제련"                                  # <acc_smelting>
const S_RETRY := "재시도"                                # <acc_smelting_retry>
const S_BEFORE := "기존 옵션"                            # <acc_smelting_befor_option>
const S_AFTER := "제련 옵션"                             # <acc_smelting_after_option>
const S_NON_SELECT := "사용할 옵션을 선택해 주세요."       # <acc_msg_non_select>
const S_MSG_BEFORE := "기존 옵션을 사용하시겠습니까?"      # <acc_msg_select_before>
const S_MSG_AFTER := "제련 옵션을 사용하시겠습니까?"       # <acc_msg_select_after>
const S_MSG_RETRY := "아이템은 기존 옵션으로 유지되고 제련 옵션은 변경 됩니다.\n제련 재시도 하시겠습니까?"

# ---------- 연출 리터럴(ItemEquipOptionLayer) ----------
const DIM_ALPHA := 200.0 / 255.0        # `CCFadeTo(0.5, 200)`
const CIRCLE_SECS := 2.2
const SFX_ROLL := "effect_roulette"
const SFX_DONE := "effect_upgrade"

# ---------- 제련 창(참조 실측, 창 800×480 로컬) ----------
const WIN := Vector2(760.0, 460.0)
const CARD := Vector2(250.0, 300.0)
const CARD_L := Vector2(130.0, 92.0)     # 왼쪽 카드 좌상단
const CARD_R := Vector2(400.0, 92.0)
const BTN := Vector2(150.0, 48.0)

## 옵션 스탯 표기(원작 `info_item_acc` 컬럼 → 한글). `build_equip_sheet.py` 와 같은 어휘.
## 옵션 스탯 이름 — **원작 문자열 그대로**. `DV2/string/stringsData_KR.xml` 이 스탯 코드와
## 같은 이름의 키를 갖고 있다: `<hp>생명력` `<att>공격력` `<def>방어력` `<blkrate>방어율`
## `<evd>회피율` `<cri>치명타` `<gold>골드` `<exp>경험치` `<pure>관통` `<depure>관통 감소`
## `<accuracy>명중`. (2026-08-01 정정 — 종전 `pure=정화` / `depure=저주` 는 자작 오역이었다.
## 원작 `<CaveItemEquipComent5>` 도 "방어 관통 대미지"다.)
const STAT_KR := {"hp": "생명력", "att": "공격력", "def": "방어력", "blk": "방어율",
	"evd": "회피율", "cri": "치명타", "gold": "골드", "exp": "경험치",
	"pure": "관통", "depure": "관통 감소", "accuracy": "명중"}

var _uid := 0
var _slot := ""
var _coin_key := ""
var _grade := 0
var _on_done: Callable = Callable()

## 기존 옵션(제련 전) / 제련 옵션(새로 굴린 것) — 둘 다 [{stat, value}].
var _before: Array = []
var _after: Array = []
var _pick := -1                          # -1 없음, 0 기존, 1 제련
var _win_root: Control
var _rng := RandomNumberGenerator.new()


## `coin_key` = 소모한 기누의 동전 아이템 키, `grade` = 그 동전 등급(= 결과 등급).
## **동전 1개는 호출부가 이미 소모한 상태로 넘어온다**(원작도 확인창에서 차감한다).
static func open(parent: Node, uid: int, slot_id: String, coin_key: String, grade: int,
		on_done := Callable()) -> EquipOptionLayer:
	var l := EquipOptionLayer.new()
	l._uid = uid
	l._slot = slot_id
	l._coin_key = coin_key
	l._grade = grade
	l._on_done = on_done
	parent.add_child(l)
	l._start()
	return l


func _start() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 70
	_rng.randomize()

	var eqf: Dictionary = UserDB.get_dragon(_uid).get("equip", {})
	for s in (eqf.get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) == _slot:
			_before = ((s as Dictionary).get("options", []) as Array).duplicate(true)
			break
	_after = Equipment.roll_options(_grade, _rng, Data.equipment)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	create_tween().tween_property(dim, "color:a", DIM_ALPHA, 0.5)
	_play_circle()


# ------------------------------------------------------------ ④ 마법진 연출

## 원작 `ItemEquipOptionLayer` — `scene/magicshop/recall_magic_circle_1/2` 두 겹이
## 반대로 돌면서 커지고, 가운데 장비가 빛난다. 효과음 `effect_roulette` → `effect_upgrade`.
func _play_circle() -> void:
	var vis := get_viewport_rect().size
	var c := vis * 0.5
	var fx := Node2D.new()
	fx.position = c
	add_child(fx)
	Bgm.sfx(SFX_ROLL)

	for i in 2:
		var s := AtlasUI.spr("magicshop_ui", "scene_magicshop_recall_magic_circle_%d" % (i + 1),
			Design.ASSET_SCALE * 0.4)
		if s == null:
			continue
		s.modulate = Color(1, 1, 1, 0)
		fx.add_child(s)
		var t := s.create_tween().set_parallel(true)
		t.tween_property(s, "modulate:a", 1.0, 0.4)
		t.tween_property(s, "scale", Vector2.ONE * Design.ASSET_SCALE * 0.95, CIRCLE_SECS)
		t.tween_property(s, "rotation", TAU * (1.0 if i == 0 else -1.0), CIRCLE_SECS)

	var item := _item_sprite(1.4)
	if item != null:
		item.position = Vector2.ZERO
		fx.add_child(item)
		var it := item.create_tween()
		it.tween_property(item, "scale", item.scale * 1.25, CIRCLE_SECS * 0.5)
		it.tween_property(item, "scale", item.scale, CIRCLE_SECS * 0.5)

	var glow := ColorRect.new()
	glow.color = Color(1, 1, 1, 0)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(glow)
	var gt := create_tween()
	gt.tween_interval(CIRCLE_SECS - 0.35)
	gt.tween_property(glow, "color:a", 1.0, 0.25)
	gt.tween_property(glow, "color:a", 0.0, 0.3)
	await gt.finished
	glow.queue_free()
	fx.queue_free()
	Bgm.sfx(SFX_DONE)
	_build_result()


# ------------------------------------------------------------ ⑤ 제련 창

func _build_result() -> void:
	var vis := get_viewport_rect().size
	_win_root = Control.new()
	_win_root.size = WIN
	_win_root.position = ((vis - WIN) * 0.5).round()
	add_child(_win_root)
	var fr := AtlasUI.nine("ninepatch_ui", "9patch_popup4", WIN, Rect2(130, 190, 40, 58))
	if fr:
		_win_root.add_child(fr)

	# 제목바 — 참조의 주황 띠 = `9patch/pop_title_bg`.
	var th := AtlasUI.size_pt("ninepatch_ui", "9patch_pop_title_bg").y
	var tw := WIN.x * 0.42
	var tb := AtlasUI.nine("ninepatch_ui", "9patch_pop_title_bg", Vector2(tw, th))
	if tb:
		tb.position = Vector2(WIN.x * 0.5 - tw * 0.5, 44.0 - th * 0.5)
		_win_root.add_child(tb)
	var tl := _label(S_TITLE, 24, Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.position = Vector2(WIN.x * 0.5 - tw * 0.5, 44.0 - th * 0.5)
	tl.size = Vector2(tw, th)
	_win_root.add_child(tl)

	_build_card(0, CARD_L, "", _before)
	_build_card(1, CARD_R, S_AFTER, _after)

	# 카드 사이 ▶ (원작 `common/btn_fold` 90°)
	var fold := AtlasUI.spr("common_ui", "common_btn_fold", Design.ASSET_SCALE * 0.7)
	if fold:
		fold.rotation = deg_to_rad(90.0)
		fold.position = Vector2((CARD_L.x + CARD.x + CARD_R.x) * 0.5, CARD_L.y + CARD.y * 0.5)
		_win_root.add_child(fold)

	_button("선택", Vector2(WIN.x * 0.5 - 160.0, WIN.y - 74.0), _on_select)
	_button(S_RETRY, Vector2(WIN.x * 0.5 + 10.0, WIN.y - 74.0), _on_retry)


func _build_card(idx: int, at: Vector2, caption: String, opts: Array) -> void:
	var card := Panel.new()
	card.size = CARD
	card.position = at
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.83, 0.70, 0.50, 0.55)
	sb.corner_radius_top_left = 10; sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10; sb.corner_radius_bottom_right = 10
	if _pick == idx:
		sb.border_width_left = 4; sb.border_width_right = 4
		sb.border_width_top = 4; sb.border_width_bottom = 4
		sb.border_color = Color(1.0, 0.86, 0.25)
	card.add_theme_stylebox_override("panel", sb)
	_win_root.add_child(card)

	var art := _item_sprite(1.0)
	if art != null:
		art.position = Vector2(CARD.x * 0.5, 76.0)
		card.add_child(art)
	if caption != "":
		var cl := _label(caption, 18, Color(0.30, 0.17, 0.04))
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.position = Vector2(0, 132.0)
		cl.size = Vector2(CARD.x, 24.0)
		card.add_child(cl)

	var box := VBoxContainer.new()
	box.position = Vector2(16.0, 166.0)
	box.size = Vector2(CARD.x - 32.0, CARD.y - 180.0)
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	for o in opts:
		var od: Dictionary = o
		var l := _label("%s +%s" % [String(STAT_KR.get(String(od.get("stat", "")),
			String(od.get("stat", "")))), str(od.get("value", 0))], 16, Color(0.30, 0.17, 0.04))
		box.add_child(l)
	if opts.is_empty():
		box.add_child(_label("(옵션 없음)", 16, Color(0.45, 0.33, 0.20)))

	var b := Button.new()
	b.flat = true
	b.size = CARD
	var i := idx
	b.pressed.connect(func():
		_pick = i
		_rebuild_result())
	card.add_child(b)


func _rebuild_result() -> void:
	if is_instance_valid(_win_root):
		_win_root.queue_free()
	_build_result()


func _on_select() -> void:
	if _pick < 0:
		_notice(S_NON_SELECT)
		return
	_confirm(S_MSG_BEFORE if _pick == 0 else S_MSG_AFTER, func(): _apply(_pick == 1))


## 재시도 — 원작 문구대로 **기존 옵션은 유지되고 제련 옵션만 다시 굴린다**. 동전 1개 추가 소모.
func _on_retry() -> void:
	if UserDB.item_count(_coin_key) <= 0:
		_notice("기누의 동전이 없습니다")
		return
	_confirm(S_MSG_RETRY, func():
		if not UserDB.use_item(_coin_key, 1):
			return
		_after = Equipment.roll_options(_grade, _rng, Data.equipment)
		_pick = -1
		_rebuild_result())


func _apply(use_new: bool) -> void:
	if use_new:
		var next: Dictionary = Equipment.reroll(
			UserDB.get_dragon(_uid).get("equip", {}), _slot, _grade, _rng, Data.equipment, _uid)
		# `reroll` 이 굴린 값이 아니라 **화면에 보여 준 값**을 그대로 박는다.
		for s in (next.get("slots", []) as Array):
			if String((s as Dictionary).get("slot", "")) == _slot:
				(s as Dictionary)["options"] = _after.duplicate(true)
				break
		if not next.is_empty():
			UserDB.set_dragon_field(_uid, "equip", next)
	if _on_done.is_valid():
		_on_done.call(use_new)
	finished.emit()
	queue_free()


# ---------- 공용 ----------

func _item_sprite(mult: float) -> Sprite2D:
	var eqf: Dictionary = UserDB.get_dragon(_uid).get("equip", {})
	var key := ""
	for s in (eqf.get("slots", []) as Array):
		if String((s as Dictionary).get("slot", "")) == _slot:
			key = String((s as Dictionary).get("key", ""))
			break
	if key == "":
		return null
	var item: Dictionary = Equipment.catalog(Data.equipment).get(key, {})
	var t := Icons.equip_texture(item)
	if t == null:
		return null
	var s2 := Sprite2D.new()
	s2.texture = t
	s2.material = AtlasUI.pma()
	s2.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE) * mult
	return s2


func _button(text: String, at: Vector2, cb: Callable) -> void:
	var root := Control.new()
	root.size = BTN
	root.position = at
	_win_root.add_child(root)
	var np := AtlasUI.nine("ninepatch_ui", "9patch_btn", BTN, Rect2(20, 20, 4, 4))
	if np:
		root.add_child(np)
	var l := _label(text, 20, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = BTN
	root.add_child(l)
	var b := Button.new()
	b.flat = true
	b.size = BTN
	b.pressed.connect(cb)
	root.add_child(b)


func _label(txt: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if col == Color.WHITE:
		l.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.04, 0.9))
		l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _notice(msg: String) -> void:
	PopupType.open(self, "알림", msg, Callable(), "확인", "")


func _confirm(msg: String, on_ok: Callable) -> void:
	PopupType.open(self, "알림", msg, on_ok, "확인", "취소")
