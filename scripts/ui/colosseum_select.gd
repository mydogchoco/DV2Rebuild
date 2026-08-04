class_name ColosseumSelect
extends CanvasLayer
## 콜로세움 **전용 편성창** — 원작 `Select3vs3Layer`(3vs3) · `Select1vs1Layer`(1vs1) 이식.
## render 층(§8). 판정은 전부 `Colosseum`/`UserDB`, 여기서는 그리고 누르기만 한다.
##
## 🟠 2026-08-05 신설(사용자 지적) — 종전에는 모험용 `PartySelect`(카드 가로 스크롤)를
## 재사용했는데, 원작 PvP 편성창은 **형태가 아예 다른 별도 클래스**다.
## 레퍼런스 `docs/ref/pvp/드래곤편성창.png` = 단상 위 드래곤 + 우측 상세 패널 + 하단 후보 띠.
##
## ## 원작 근거 (전부 디컴프 리터럴 — `[skip>` 0건, 추측 없음)
##   · `Select3vs3Layer::init` @00fcb4c8
##       `PopupLayer::init` → CCLayerColor **알파 0**(가림막 없음)
##       `PopupLayer::setContentSprite(visH-20, this, "9patch/popup5.png", CCRect(100,105,75,135))`
##       ⇒ 화면을 거의 채우는 popup5 판이 이 화면의 배경이다(레퍼런스의 양피지 판).
##   · `Select3vs3Layer::initWidget` @00fcba34 (17,084B)
##       장식띠 `scene/colosseum/dragon_select_deco.png` anchor(0.5,1) @ (W/2, H),
##               setScaleX((W+5)/띠폭)
##       제목   `<ColosseumSelectTitle>` font_title, 화면중앙 + (0, 305), scale 0.75
##       닫기   `common/close_btn.png` scale 1.5 @ (W-55, H-40+10)
##       확정   RoundedButton(200×120) 오른쪽중앙 + (-27-w/2, -240),
##               라벨 `<ColosseumSelectButton>` subtitle anchor(0.5,0.45)
##       무대   CCLayer 465×425(1vs1 은 465×380) 왼쪽중앙 + (465/2+42-15, 100 | 55)
##       슬롯   무대 + (110,-40) · (-90,75) · (-125,-115)   [1vs1 = 무대 + (0,40)]
##       단상   `Stand::getImagePath()` @ 슬롯 - (0,35), **scale 0.6**
##               (1vs1 은 무대 - (0,20), setScale 호출 없음 = 1.0)
##               └ `common/backlight3` 투명도 0 · scale 0.75 · RotateBy(2s, 90°) 무한
##                 `common/backlight4` 투명도 255 · scale 0.75 · RotateBy(2s, 10°) 무한
##                 `common/shadow`     투명도 0 · scale 1.75 @ 단상중심 - (0,32.5)
##               ⇒ **빈 슬롯 = backlight4 만 보인다.** 차면 backlight3+그림자가 켜진다
##                 (`changeSelect` 의 FadeTo 0.25 세 줄이 이 상태를 되돌린다)
##       드래곤 `ColosseumManager::getSpine(i)` setScaleX(**-0.6**) / setScaleY(**0.6**)
##               애니 `wait`, 슬롯 위치에 그대로
##       띠판   `9patch/selection_box.png` cap(15,15,94,95) contentSize(W-268.5, 135)
##               왼쪽중앙 + (판폭/2 + 22, -240)
##       스크롤 `ScrollViewEx(판폭-7.1, 135)` @ (4.1, 0), 내용폭 = 칸수×122 + 11.2
##       칸    `common/dragon_bg2` + `common/dragon_cover2`, CCMenuItemImageEx scale 1.05
##               pos = ((칸폭+10)×i + 칸폭/2 + 10, 칸높이/2 + 10)
##               초상 `Dragon::getImagePathBox` @ 칸중심 + (0,7.5) scale 0.9 (skinSide 로 flipX)
##               라벨 `<level>` "레벨 %d" subtitle scale 0.8, 칸 아래
##               부화중(Lv1+isBreed) 은 초상 대신 `common/breed_egg_small`
##               선택 불가 칸엔 `common/dragon_cover4`(검정, 투명도 0x66) 를 덮는다
##   · `changeSelect` @00fd65b8
##       `music/effect_tab.mp3` (playEffect vol 0.5)
##       `CharacterInfoPopup` scale 0.95 @ (W-199.5-42.5, H/2+55), 오른쪽에서 MoveBy 0.1s
##       로 밀려 들어오고 ±10 로 한 번 튕긴다
##
## ## ⚫ 컷 (§2-1 온라인/결제)
##   · `initWithCash`/`onClickCashConfirm`/`onClickToShop`/`onClickShopDrink`/
##     `Request·ResponseEnerygeDrink` — 다이아 결제(피로도 회복 드링크)
##   · `responseDeck` — 서버 덱 동기화
##   · `drawSkipTap`/`onclicSkipTap`/`onclickSkipOk` — 전투 스킵권(서버 대기 전제)
##   · `makeMagneticDummy(_Swap)` 드래그 재정렬 — **순서가 결과에 영향을 주지 않는다**
##     (우리 `Battle.simulate` 는 파티 순서를 그대로 쓴다. 원작도 서버가 정렬했다)
##   · 빈 드래곤 슬롯 + `common/lock` — 슬롯 확장은 캐시 상품이라 우리에겐 없다
##   · 무대 `skill/ultimate/earth.pvr.ccz` 배치노드 + `createDust` 먼지 연출 —
##     각각 스킬 아틀라스/전용 파티클이라 이 화면 밖에서 다룬다
##
## 사용:
##   `ColosseumSelect.open(host, mode, seed_party, func(picked: Array) -> void: ...)`

const CO := "colosseum_ui"
const CM := "common_ui"
const NP := "ninepatch_ui"
const ST := "stand_ui"

# ── 원작 initWidget 리터럴(전부 cocos 포인트) ─────────────────────────────────
const PANEL_INSET := 20.0                      # PopupLayer::setContentSprite(visH-20 …)
const POPUP5_CAP := Rect2(100, 105, 75, 135)
const TITLE_UP := 305.0                        # 화면중앙 + (0, 305)
const TITLE_SCALE := 0.75
const CLOSE_SCALE := 1.5
const CLOSE_RIGHT := 55.0                      # (W-55, H-40+10)
const CLOSE_TOP := 30.0
const CONFIRM_SIZE := Vector2(200.0, 120.0)
const CONFIRM_DX := -27.0                      # 오른쪽중앙 + (-27 - w/2, -240)
const CONFIRM_DY := -240.0
const STAGE_W := 465.0
const STAGE_DX := STAGE_W * 0.5 + 42.0 - 15.0  # 왼쪽중앙 + (…, 100|55)
const STAGE_DY_3 := 100.0
const STAGE_DY_1 := 55.0
const SLOTS_3 := [Vector2(110.0, -40.0), Vector2(-90.0, 75.0), Vector2(-125.0, -115.0)]
const SLOT_1 := Vector2(0.0, 40.0)
const STAND_DOWN_3 := 35.0                     # 단상 = 슬롯 - (0,35)
const STAND_DOWN_1 := 20.0                     # 1vs1 은 무대 - (0,20)
const STAND_SCALE_3 := 0.6
const STAND_SCALE_1 := 1.0
const GLOW_UP_3 := 21.0                        # 단상중심 + (0,21)
const GLOW_UP_1 := 20.0
const GLOW_SCALE := 0.75
const SHADOW_DOWN := 32.5
const SHADOW_SCALE := 1.75
const SPIN3_DEG := 90.0                        # backlight3 RotateBy(2, 90)
const SPIN4_DEG := 10.0                        # backlight4 RotateBy(2, 10)
const SPIN_SEC := 2.0
const FADE_SEC := 0.25                         # changeSelect 의 FadeTo
const DRAGON_SCALE := 0.6                      # setScaleX(-0.6)/setScaleY(0.6)
const LIST_INSET := 268.5                      # contentSize(W-268.5, 135)
const LIST_H := 135.0
const LIST_LEFT := 22.0                        # 왼쪽중앙 + (판폭/2 + 22, -240)
const LIST_DY := -240.0
const SEL_MARGIN := 11                         # cap 15pt = 11px 균일 테두리
const SCROLL_PAD := Vector2(4.1, 0.0)
const SCROLL_TRIM := 7.1                       # ScrollViewEx(판폭 - 7.1, …)
const CELL_GAP := 10.0
const CELL_MARGIN := 10.0                      # pos = (…×i + w/2 + 10, h/2 + 10)
const CELL_SCALE := 1.05
const PORTRAIT_SCALE := 0.9
const PORTRAIT_UP := 7.5
const LV_SCALE := 0.8
const DIM_OPACITY := 0x66 / 255.0              # dragon_cover4 투명도
# CharacterInfoPopup — changeSelect 가 놓는 자리.
const INFO_RIGHT := 199.5 + 42.5               # pos.x = W - 242
const INFO_UP := 55.0                          # pos.y = H/2 + 55
const INFO_SLIDE := 0.1
const HIT_BOX := 120.0                         # 단상 위 드래곤 해제 히트박스

var _mode := "team"
var _need := 3
var _picked: Array = []
var _on_confirm := Callable()
var _pma: CanvasItemMaterial
var _vis: Vector2
var _slots: Array = []          # {stand, glow3, glow4, shadow, pos: Vector2}
var _cells: Dictionary = {}     # uid -> {root, dim, pickable}
var _dragon_layer: Node2D = null   # 단상 위 드래곤 + 해제용 히트박스
var _panel: StatusLayer = null
var _panel_uid := -1
var _confirm: Control = null


## `mode` = "single" | "team" (원작 FightManager::setType 0|1).
## `seed_party` = 미리 골라 둘 uid 들. `on_confirm(picked: Array)` 로 확정을 알린다.
static func open(host: Node, mode: String, seed_party: Array,
		on_confirm: Callable) -> ColosseumSelect:
	var l := ColosseumSelect.new()
	l.layer = 30
	l._mode = mode
	l._on_confirm = on_confirm
	l._need = Colosseum.party_size(mode)
	for u in seed_party:
		if l._picked.size() < l._need and Colosseum.eligible(int(u)) \
				and not UserDB.is_down(int(u)):
			l._picked.append(int(u))
	host.add_child(l)
	return l


func _ready() -> void:
	_pma = AtlasUI.pma()
	_vis = get_viewport().get_visible_rect().size
	_build()


# ============================================================ 골격
func _build() -> void:
	# 입력 차단 — 원작도 PopupLayer 라 아래 씬이 눌리지 않는다(색은 알파 0).
	var catcher := Control.new()
	catcher.size = _vis
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(catcher)

	# 배경 = `9patch/popup5` 를 화면 -20 만큼 채운다(원작 setContentSprite).
	var bg := AtlasUI.nine(NP, "9patch_popup5",
		Vector2(_vis.x - PANEL_INSET * 2.0, _vis.y - PANEL_INSET), POPUP5_CAP)
	if bg != null:
		bg.position = Vector2(PANEL_INSET, PANEL_INSET * 0.5)
		add_child(bg)

	_build_deco()
	_build_title()
	_build_close()
	_build_stage()
	_build_list()
	_build_confirm()
	_refresh_slots()
	# 원작도 진입 시점에 이미 고른 덱이 단상에 서 있고 `changeSelect` 가 마지막 대상의
	# `CharacterInfoPopup` 을 띄운 상태다(레퍼런스에도 패널이 열려 있다).
	if not _picked.is_empty():
		_open_panel(int(_picked[_picked.size() - 1]))


## 상단 장식 띠 — anchor(0.5,1) @ (W/2, H), 폭을 화면+5 로 늘린다.
func _build_deco() -> void:
	var deco := AtlasUI.spr_cocos(CO, "scene_colosseum_dragon_select_deco", 1.0,
		Vector2(0.5, 1.0))
	if deco == null:
		return
	var w := AtlasUI.size_pt(CO, "scene_colosseum_dragon_select_deco").x
	if w > 1.0:
		deco.scale = Vector2((_vis.x + 5.0) / w, 1.0)
	deco.position = Vector2(_vis.x * 0.5, 0.0)
	add_child(deco)


func _build_title() -> void:
	var l := _bm_label(_string("ColosseumSelectTitle", "드래곤 선택"), 39, "font_title")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(_vis.x, 48.0)
	# 원작: 화면중앙 + (0, 305) — BMFont scale 0.75 는 폰트 크기에 이미 녹여 넣었다.
	l.position = Vector2(0.0, _vis.y * 0.5 - TITLE_UP - 24.0)
	add_child(l)


func _build_close() -> void:
	var t := AtlasUI.tex(CM, "common_close_btn")
	if t == null:
		return
	var b := TextureButton.new()
	b.texture_normal = t
	b.scale = Vector2.ONE * (CLOSE_SCALE * Design.ASSET_SCALE)
	var sz := t.get_size() * b.scale
	b.position = Vector2(_vis.x - CLOSE_RIGHT, CLOSE_TOP) - sz * 0.5
	b.pressed.connect(func() -> void:
		Bgm.sfx("effect_button")
		_dismiss())
	add_child(b)


# ============================================================ 무대(단상 슬롯)
func _build_stage() -> void:
	var S := Design.ASSET_SCALE
	var three := _need >= 3
	var stage := Vector2(STAGE_DX, _vis.y * 0.5 - (STAGE_DY_3 if three else STAGE_DY_1))
	var offs: Array = SLOTS_3 if three else [SLOT_1]
	var st_scale := (STAND_SCALE_3 if three else STAND_SCALE_1) * S
	var glow_up := GLOW_UP_3 if three else GLOW_UP_1
	var st_key := "stand_stand%d" % ((UserDB.get_skin("stand_skin") % _stand_count()) + 1)

	_dragon_layer = Node2D.new()
	add_child(_dragon_layer)

	for i in mini(_need, offs.size()):
		var o: Vector2 = offs[i]
		# cocos → godot: x 그대로, y 부호 반전.
		var slot := stage + Vector2(o.x, -o.y)
		# 3vs3 은 단상이 **슬롯** 기준(-35), 1vs1 은 **무대** 기준(-20)이다.
		var stand_pos := slot + Vector2(0.0, STAND_DOWN_3) if three \
			else stage + Vector2(0.0, STAND_DOWN_1)

		var stand := AtlasUI.spr(ST, st_key, st_scale)
		if stand == null:
			continue
		stand.position = stand_pos
		add_child(stand)

		# 후광 2종 + 그림자는 원작처럼 **단상의 자식**이다(단상 배율이 함께 먹는다).
		var glow3 := AtlasUI.spr(CM, "common_backlight3", GLOW_SCALE)
		var glow4 := AtlasUI.spr(CM, "common_backlight4", GLOW_SCALE)
		var sh := AtlasUI.spr(CM, "common_shadow", SHADOW_SCALE)
		if glow3 == null or glow4 == null or sh == null:
			continue
		glow3.position = Vector2(0.0, -glow_up)
		glow3.modulate.a = 0.0
		glow3.z_index = -1
		stand.add_child(glow3)
		_spin(glow3, SPIN3_DEG)

		glow4.position = Vector2(0.0, -glow_up)
		glow4.z_index = -1
		stand.add_child(glow4)
		_spin(glow4, SPIN4_DEG)

		sh.position = Vector2(0.0, SHADOW_DOWN)
		sh.modulate.a = 0.0
		stand.add_child(sh)

		_slots.append({"stand": stand, "glow3": glow3, "glow4": glow4, "shadow": sh,
			"pos": slot})


func _spin(n: Node2D, deg: float) -> void:
	var t := n.create_tween().set_loops()
	t.tween_property(n, "rotation", deg_to_rad(deg), SPIN_SEC).as_relative() \
		.set_trans(Tween.TRANS_LINEAR)


func _stand_count() -> int:
	var m := AtlasUI.manifest(ST)
	var n := 0
	while m.has("stand_stand%d" % (n + 1)):
		n += 1
	return maxi(1, n)


## 슬롯을 현재 선택에 맞춰 다시 그린다(원작 `changeSelect`/`cancelSelect` 가 하던 일).
func _refresh_slots() -> void:
	if not is_instance_valid(_dragon_layer):
		return
	for c in _dragon_layer.get_children():
		c.queue_free()
	for i in _slots.size():
		var s: Dictionary = _slots[i]
		var filled := i < _picked.size()
		_fade(s["glow3"], 1.0 if filled else 0.0)
		_fade(s["shadow"], 1.0 if filled else 0.0)
		_fade(s["glow4"], 0.0 if filled else 1.0)
		if not filled:
			continue
		var uid := int(_picked[i])
		var d := UserDB.get_dragon(uid)
		if d.is_empty():
			continue
		var node := _dragon_spine(d)
		if node == null:
			continue
		node.position = s["pos"]
		_dragon_layer.add_child(node)
		# 단상 위 드래곤을 누르면 선택 해제(원작 `cancelSelect` — 원작은 드래그로 뺐다).
		var hit := Button.new()
		hit.flat = true
		hit.size = Vector2(HIT_BOX, HIT_BOX)
		hit.position = Vector2(s["pos"]) - hit.size * 0.5
		hit.pressed.connect(func() -> void: _toggle(uid))
		_dragon_layer.add_child(hit)


func _fade(n: CanvasItem, a: float) -> void:
	var t := n.create_tween()
	t.tween_property(n, "modulate:a", a, FADE_SEC)


## 원작 `ColosseumManager::getSpine(i)` — setScaleX(-0.6)/setScaleY(0.6), 애니 `wait`.
func _dragon_spine(d: Dictionary) -> Node2D:
	var id := int(d.get("id", 0))
	var S := Design.ASSET_SCALE
	for st in [Growth.spine_stage(d), "adult", "child", "baby"]:
		var p := "res://scenes/dragons/dragon_%d_%s.tscn" % [id, st]
		if not ResourceLoader.exists(p):
			continue
		var holder := Node2D.new()
		# 원작 그대로 x 를 뒤집는다 — 후보 띠의 초상과 같은 방향(왼쪽)을 본다.
		holder.scale = Vector2(-DRAGON_SCALE * S, DRAGON_SCALE * S)
		var inst := (load(p) as PackedScene).instantiate()
		holder.add_child(inst)
		var ap := inst.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if ap != null:
			for cand in ["wait", "animation", "idle"]:
				if ap.has_animation(cand):
					ap.get_animation(cand).loop_mode = Animation.LOOP_LINEAR
					ap.play(cand)
					break
		return holder
	return null


# ============================================================ 하단 후보 띠
func _build_list() -> void:
	var S := Design.ASSET_SCALE
	var box_w: float = _vis.x - LIST_INSET
	var top: float = _vis.y * 0.5 - LIST_DY - LIST_H * 0.5

	var box := NinePatchRect.new()
	box.texture = AtlasUI.tex(NP, "9patch_selection_box")
	box.patch_margin_left = SEL_MARGIN
	box.patch_margin_right = SEL_MARGIN
	box.patch_margin_top = SEL_MARGIN
	box.patch_margin_bottom = SEL_MARGIN
	box.size = Vector2(box_w, LIST_H)
	box.position = Vector2(LIST_LEFT, top)
	add_child(box)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(SCROLL_PAD.x, SCROLL_PAD.y)
	scroll.size = Vector2(box_w - SCROLL_TRIM, LIST_H)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(scroll)

	var strip := Control.new()
	scroll.add_child(strip)

	# 칸 크기 = 원작 CCSprite contentSize = 프레임 **원본 캔버스**(트림 전) 크기.
	var src: Array = AtlasUI.manifest(CM).get("common_dragon_bg2", {}).get("src", [83, 85])
	var cw := float(src[0]) * S
	var ch := float(src[1]) * S
	var pitch := cw + CELL_GAP

	var list := UserDB.dragons()
	for i in list.size():
		var d: Dictionary = list[i]
		var cx := pitch * float(i) + cw * 0.5 + CELL_MARGIN
		var cy := LIST_H - (ch * 0.5 + CELL_MARGIN)
		strip.add_child(_cell(d, Vector2(cx, cy), Vector2(cw, ch)))
	strip.custom_minimum_size = Vector2(pitch * float(list.size()) + 11.2, LIST_H)


## 후보 칸 1개. `center` 는 띠 안 좌표(godot), `sz` 는 프레임 원본 크기(포인트).
func _cell(d: Dictionary, center: Vector2, sz: Vector2) -> Control:
	var S := Design.ASSET_SCALE
	var uid := int(d.get("uid", 0))
	var id := int(d.get("id", 0))
	var lv := int(d.get("level", 1))
	var pickable := Colosseum.eligible(uid) and not UserDB.is_down(uid)

	var root := Control.new()
	root.size = sz * CELL_SCALE
	root.position = center - root.size * 0.5
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mid := root.size * 0.5

	var bg := AtlasUI.spr(CM, "common_dragon_bg2", S * CELL_SCALE)
	if bg != null:
		bg.position = mid
		root.add_child(bg)

	# 초상 — 부화 중이면 알(원작 `getLevel()==1 && isBreed()` → breed_egg_small).
	if UserDB.is_egg(d):
		var egg := AtlasUI.spr(CM, "common_breed_egg_small", S * CELL_SCALE)
		if egg != null:
			egg.position = mid + Vector2(0.0, -5.0)
			root.add_child(egg)
	else:
		var por := _portrait(id, Growth.portrait_stage(d),
			PORTRAIT_SCALE * S * CELL_SCALE, int(d.get("skin", 0)))
		if por != null:
			por.position = mid + Vector2(0.0, -PORTRAIT_UP)
			root.add_child(por)

	var cover := AtlasUI.spr(CM, "common_dragon_cover2", S * CELL_SCALE)
	if cover != null:
		cover.position = mid
		root.add_child(cover)

	# 선택 불가 = `common/dragon_cover4` 검정 0x66(원작 그대로).
	var dim := AtlasUI.spr(CM, "common_dragon_cover4", S * CELL_SCALE)
	if dim != null:
		dim.position = mid
		dim.modulate = Color(0, 0, 0, DIM_OPACITY)
		dim.visible = not pickable
		root.add_child(dim)

	var lvl := _bm_label(_string("level", "레벨 %d") % lv, 17)
	lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl.size = Vector2(root.size.x + 20.0, 22.0)
	lvl.position = Vector2(-10.0, root.size.y - 26.0)
	root.add_child(lvl)

	var btn := Button.new()
	btn.flat = true
	btn.size = root.size
	btn.pressed.connect(func() -> void: _toggle(uid))
	root.add_child(btn)

	_cells[uid] = {"root": root, "dim": dim, "pickable": pickable}
	_paint_cell(uid)
	return root


func _paint_cell(uid: int) -> void:
	var c: Dictionary = _cells.get(uid, {})
	if c.is_empty():
		return
	var root: Control = c["root"]
	# 이미 단상에 오른 드래곤은 띠에서 눌린 것으로 보인다(원작도 목록에 남는다).
	root.modulate = Color(0.6, 0.6, 0.6) if _picked.has(uid) else Color.WHITE


# ============================================================ 선택 / 확정
func _toggle(uid: int) -> void:
	var c: Dictionary = _cells.get(uid, {})
	if not c.is_empty() and not bool(c.get("pickable", false)):
		if UserDB.is_down(uid):
			Toast.show(self, "행동불능 상태입니다.")
		else:
			Toast.show(self, "레벨 %d 이상만 출전할 수 있습니다." % Colosseum.min_level())
		return
	Bgm.sfx("effect_tab", 0.5)      # 원작 changeSelect: playEffect(music/effect_tab.mp3, 0.5)
	var at := _picked.find(uid)
	if at >= 0:
		_picked.remove_at(at)
		_close_panel()
	elif _picked.size() < _need:
		_picked.append(uid)
		_open_panel(uid)
	else:
		# 자리가 없으면 마지막 자리를 갈아 끼운다(원작은 드래그 교체 — 우리는 클릭만).
		_picked[_need - 1] = uid
		_open_panel(uid)
	for k in _cells.keys():
		_paint_cell(int(k))
	_refresh_slots()
	_update_confirm()


## 원작 `changeSelect` — `CharacterInfoPopup` 을 오른쪽에서 밀어 넣는다.
func _open_panel(uid: int) -> void:
	if _panel_uid == uid and is_instance_valid(_panel):
		return
	_close_panel()
	var d := UserDB.get_dragon(uid)
	if d.is_empty():
		return
	var pw: float = StatusLayer.PANEL.x * StatusLayer.PANEL_SCALE
	var ph: float = StatusLayer.PANEL.y * StatusLayer.PANEL_SCALE
	var pos := Vector2(_vis.x - INFO_RIGHT - pw * 0.5,
		_vis.y * 0.5 - INFO_UP - ph * 0.5)
	# `dismiss=false` — 이 패널은 편성창의 **구성물**이라 바깥을 눌러도 닫히지 않는다.
	# (전투 팝업만 원작 `removeDragonInfo` 처럼 빈 곳 터치로 닫힌다.)
	_panel = StatusLayer.open_panel(self, d, false, pos, false)
	_panel.layer = layer + 1
	_panel_uid = uid
	# 밀려 들어오기 + ±10 튕김(원작 MoveBy(0.1, -center.x) → +10 → -10).
	_panel.offset = Vector2(_vis.x - pos.x, 0.0)
	var t := _panel.create_tween()
	t.tween_property(_panel, "offset", Vector2(10.0, 0.0), INFO_SLIDE)
	t.tween_property(_panel, "offset", Vector2.ZERO, INFO_SLIDE)


func _close_panel() -> void:
	if is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
	_panel_uid = -1


func _build_confirm() -> void:
	var w := CONFIRM_SIZE.x
	var pos := Vector2(_vis.x + CONFIRM_DX - w * 0.5,
		_vis.y * 0.5 - CONFIRM_DY) - CONFIRM_SIZE * 0.5
	_confirm = AtlasUI.frame_button(self, _string("ColosseumSelectButton", "선택 완료"),
		pos, CONFIRM_SIZE, func() -> void: _commit(), 0, false, 24)
	_update_confirm()


func _update_confirm() -> void:
	if not is_instance_valid(_confirm):
		return
	var ok := _picked.size() >= _need
	_confirm.modulate = Color.WHITE if ok else Color(0.62, 0.62, 0.62)
	for c in _confirm.get_children():
		if c is Button:
			(c as Button).disabled = not ok


func _commit() -> void:
	if _picked.size() < _need:
		return
	Bgm.sfx("effect_button")
	var picked := _picked.duplicate()
	# 원작도 확정 시 덱이 저장된다(`setSelectedColo3vs3`) — 우리는 UserDB 파티에 반영.
	UserDB.clear_party()
	for u in picked:
		UserDB.toggle_party(int(u))
	var cb := _on_confirm
	queue_free()
	if cb.is_valid():
		cb.call(picked)


func _dismiss() -> void:
	_close_panel()
	queue_free()


# ============================================================ helpers
static var _bmfonts: Dictionary = {}

func _bmfont(name: String) -> FontFile:
	if _bmfonts.has(name):
		return _bmfonts[name]
	var p := "res://assets/converted/font_ui/%s.fnt" % name
	var f: FontFile = load(p) if ResourceLoader.exists(p) else null
	if f != null:
		f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	_bmfonts[name] = f
	return f


func _bm_label(text: String, size: int, font := "font_subtitle") -> Label:
	var l := Label.new()
	l.text = text
	var f := _bmfont(font)
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 원작 문자열 번들 `DV2/string/stringsData_KR.xml` 에서 그대로 옮긴 문구.
##   <ColosseumSelectTitle>드래곤 선택 · <ColosseumSelectButton>선택 완료 · <level>레벨 %1$d
const STR := {
	"ColosseumSelectTitle": "드래곤 선택",
	"ColosseumSelectButton": "선택 완료",
	"level": "레벨 %d",
}

func _string(key: String, fallback: String) -> String:
	return String(STR.get(key, fallback))


func _portrait(id: int, stage: String, scale: float, skin: int) -> Sprite2D:
	var dir := "portrait_%d" % id
	var man := AtlasUI.manifest(dir)
	var frame := "dragon_dragon_%d_box_%s" % [id, stage]
	if not man.has(frame) and stage == "evolution":
		frame = "dragon_dragon_%d_box_adult" % id
	if skin > 0 and man.has("%s_skin%d" % [frame, skin]):
		frame = "%s_skin%d" % [frame, skin]
	return AtlasUI.spr(dir, frame, scale)
