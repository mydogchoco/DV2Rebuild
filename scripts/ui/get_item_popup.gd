class_name GetItemPopup
extends CanvasLayer
## 획득 아이템 공개 팝업 — 원작 `ShowGetItemDetailLayer` 이식. render 층(CLAUDE.md §8).
##
## 원작이 이걸 띄우는 자리(전부 `addItem`/`addEquip` **직후**):
##   · 상점 구매      `ItemDetailLayer.c:2041` · `:6887` · `:7265` · `:7291`
##   · 뽑기 결과      `Gacha_Box_Popup.c:533`
##   · 스킬 제작      `MakeSkillPop.c:1076`      (우리 진입점은 근거 부재 — 미배선)
##   · 탐험 보너스    `AdventureBonusSelect.c:2354`
##   · 장비 선택      `ItemEquipSelectPopup.c:2977` · 아이템 선택 `ItemSelectPopup.c:1829`
##   · 이벤트 상자    `ChristmasLuckBoxLayer.c:2918` 등 (⚫ 컷)
##
## ⚠️ 2026-07-30 재디컴프로 배치가 처음 드러났다 — 종전엔 배치 함수 `showAfterReward`(24,620B)가
##   `[skip>8000]` 으로 통째로 빠져 있어서(CLAUDE.md §7) "다건 배치를 모른다"고 미배선으로 뒀다.
##   `batch_decompile.py --classes ShowGetItemDetailLayer --max 25000` 로 복구(74메서드 · skip 0).
##
## 원작 구조(전부 디컴프 실측):
##   · `init` 은 `PopupLayer::init()` 만 부르고 **`setContentSprite` 를 부르지 않는다**
##     ⇒ 창(9patch) 프레임이 없다. 전체화면 딤 위에 아이템이 떠 있는 **공개 연출**이다.
##     (종전 우리 이식본은 `9patch/popup4` 창 + 제목바를 얹고 있었다 — 원작에 없는 물건이었다.)
##   · `show()` = `PopupLayer::show(this, 200.0)`(z=200) → `showBeforeEffect` → `Delay` ×2(0.25).
##   · `showAfterReward` 배치 — N개를 **원형**으로 놓는다:
##       마지막(index == N−1)  : 화면 중앙, `setScale(1.25)`
##       그 외 i               : 중앙 + ( sin(2πi/(N−1) − π/2) × (W×0.5 − 200),
##                                       cos(2πi/(N−1) − π/2) × (H×0.5 − 100) ), `setScale(0.85)`
##       reward type == 4      : y 를 +50, 반지름 계산에서 −30
##     항목별로 순차 FadeIn 하고, 하단 재화·버튼은 `Delay(N × 0.25) → FadeIn(0.3)` 뒤에 뜬다.
##   · 프레임: `common/backlight3`(아이템 뒤 발광) · `common/eggclass`(알 등급 마크 — ⚪미이식) ·
##     `common/coin`/`common/diamond`(+`diamond_small1`) · `common/check_btn`(확인) ·
##     `item/item_small/ele_*`(속성 결정) · `scene/magicshop/fortune_icon1~4`(점술 결과).
##   · 라벨 서식 `"%s X %d"` / `" x%d"` / `" +%d"`, 폰트 `getFontName_subtitle`.
##   · 확인 버튼 위치 = cocos `(W×0.9, H×0.95 − 50)`.
##   · SFX `music/effect_roulette.mp3`(:1291).
##
## ⚫ 미이식(원작에 있으나 우리 범위 밖): 상자별 개봉 스파인(`lucky_spine` · `worldcup_box_spine` ·
##   `childrenbox_spine` · `pocket_spine` — 이벤트/온라인 §2-1 컷이거나 에셋 부재) ·
##   `re_wish`(드래곤볼 재소원) · `onClickRetry`(연속 뽑기 재시도, 서버 왕복).

## 원작 리터럴 그대로.
const DIM_ALPHA := 127.0 / 255.0          # PopupLayer::show(…, 127) 계열 딤
const LAYER_Z := 200                      # PopupLayer::show(this, 200.0)
const SCALE_LAST := 1.25                  # 마지막(주 획득물) 배율
const SCALE_REST := 0.85
const RADIUS_X_PAD := 200.0               # (W×0.5 − 200)
const RADIUS_Y_PAD := 100.0               # (H×0.5 − 100)
const TYPE4_Y := 50.0                     # reward type 4 의 y 오프셋
const TYPE4_R := 30.0                     # reward type 4 의 반지름 보정
const STAGGER := 0.25                     # 항목 간 등장 간격 = 하단 대기 Delay(N × 0.25)
const FADE := 0.3                         # CCFadeIn::create(0.3)
const BTN_X_RATIO := 0.9                  # 확인 버튼 cocos x = W × 0.9
const BTN_Y_RATIO := 0.95                 # cocos y = H × 0.95 − 50
const BTN_Y_OFF := 50.0

signal closed

var _on_ok := Callable()
var _dim: ColorRect
var _root: Control

## `items` = 획득물 목록. 각 항목은 다음 중 하나:
##   {"key": "<인벤 키>", "count": N}          아이템·젬(`gem:`)·장비(`equip:`)·알(`egg:`)·스킬(`skill:`)
##   {"currency": "gold"|"diamond", "count": N} 재화
## 마지막 항목이 **중앙에 크게** 놓이므로, 주 획득물을 배열 끝에 둔다(원작과 같은 규약).
## `reward_type` = 원작 `ItemRewardType`. 4 만 배치가 다르다(y+50 · 반지름 −30).
static func open(host: Node, items: Array, on_ok := Callable(), reward_type := 0) -> GetItemPopup:
	var p := GetItemPopup.new()
	p._on_ok = on_ok
	host.add_child(p)
	p._build(items, reward_type)
	return p

func _build(items: Array, reward_type: int) -> void:
	layer = LAYER_Z
	var vis: Vector2 = get_viewport().get_visible_rect().size

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, DIM_ALPHA)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 원작 PopupLayer 는 뒤쪽 입력을 통째로 먹는다(CCLayerColor + swallowsTouches).
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	Bgm.sfx("effect_roulette")             # 원작 playEffect(ShowGetItemDetailLayer.c:1291)

	var n := items.size()
	var center := vis * 0.5
	for i in n:
		var e: Dictionary = items[i]
		var last := i == n - 1
		var pos := center
		if not last and n > 1:
			# 원작 각도: 2πi/(N−1) − π/2 (= 12시부터 시계방향).
			var a := TAU * float(i) / float(n - 1) - PI * 0.5
			var rx: float = vis.x * 0.5 - RADIUS_X_PAD
			var ry: float = vis.y * 0.5 - RADIUS_Y_PAD - (TYPE4_R if reward_type == 4 else 0.0)
			# cocos y-up → Godot y-down: cos 성분의 부호를 뒤집는다.
			pos = center + Vector2(sin(a) * rx, -cos(a) * ry)
		if reward_type == 4:
			pos.y -= TYPE4_Y                # 원작 fStack_13c + 50 (cocos y+ = 위)
		var node := _make_entry(e, SCALE_LAST if last else SCALE_REST)
		node.position = pos
		node.modulate.a = 0.0
		_root.add_child(node)
		# 항목별 순차 등장(원작은 항목마다 액션을 걸고 하단은 N×0.25 뒤에 뜬다).
		var tw := create_tween()
		tw.tween_interval(STAGGER * float(i))
		tw.tween_property(node, "modulate:a", 1.0, FADE)

	# ── 확인 버튼 — 원작 `common/check_btn` @ cocos (W×0.9, H×0.95 − 50) ──────
	var btn := _check_button()
	btn.position = Vector2(vis.x * BTN_X_RATIO,
		vis.y - (vis.y * BTN_Y_RATIO - BTN_Y_OFF))
	btn.modulate.a = 0.0
	_root.add_child(btn)
	var bt := create_tween()
	bt.tween_interval(STAGGER * float(maxi(1, n)))
	bt.tween_property(btn, "modulate:a", 1.0, FADE)
	# 딤을 눌러도 닫히지 않는다(원작도 확인 버튼/백키만) — 다만 백키는 받는다.
	_dim.gui_input.connect(func(_ev: InputEvent): pass)

func _unhandled_key_input(ev: InputEvent) -> void:
	# 원작 onBackKey → onClickClose.
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		_close()

## 항목 1개 = `common/backlight3` 발광 + 아이콘 + 이름(×수량).
func _make_entry(e: Dictionary, scale_f: float) -> Node2D:
	var holder := Node2D.new()
	holder.scale = Vector2(scale_f, scale_f)
	var info := resolve(e)

	var bl := AtlasUI.spr("common_ui", "common_backlight3", Design.ASSET_SCALE * 0.9)
	if bl != null:
		bl.modulate = Color(1, 1, 1, 0.45)
		holder.add_child(bl)
		# 원작 리빌의 회전 발광(진화·레벨업 연출과 같은 경로).
		var tw := create_tween().set_loops()
		tw.tween_property(bl, "rotation", TAU, 6.0).from(0.0)

	var tex: Texture2D = info.get("tex")
	if tex != null:
		var icon := Sprite2D.new()
		icon.texture = tex
		icon.material = AtlasUI.pma()     # 변환 아틀라스는 PMA(§4)
		icon.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
		holder.add_child(icon)
		# 원작 리빌 팝인.
		var tw2 := create_tween()
		tw2.tween_property(icon, "scale", icon.scale, 0.35) \
			.from(icon.scale * 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		# 바탕 위에 겹치는 그림 — 원작 setEventReward 의 스킬 보상은
		# `common/skill_sroll.png`(두루마리) 위에 스킬 아이콘을 (w/2+1, h/2+5) 로 얹는다.
		var ov: Texture2D = info.get("overlay")
		if ov != null:
			var ovs := Sprite2D.new()
			ovs.texture = ov
			ovs.material = AtlasUI.pma()
			ovs.position = (info.get("overlay_off", Vector2.ZERO) as Vector2)
			icon.add_child(ovs)

	# ⚪ 미이식 — `common/eggclass` 등급 마크. 원작은 알 분기에서 이 프레임을
	#    **여러 개 가로로 늘어놓는다**(anchor(0,0.5) · 기준점 +(0,65) · 개수 n 만큼
	#    `width × n × 0.5` 로 중앙 정렬, showAfterReward 리터럴).
	#    그 **n 이 무엇의 개수인지**(알 성급? 등급?)를 짚지 못해 붙이지 않았다 —
	#    개수를 지어내면 화면에 없는 정보를 그리는 셈이다(CLAUDE.md §3).

	# 이름(×수량) — 원작 서식 `"%s X %d"`, 폰트 getFontName_subtitle.
	var cnt := int(e.get("count", 1))
	var lb := Label.new()
	lb.text = "%s X %d" % [String(info.get("name", "")), cnt] if cnt > 1 \
		else String(info.get("name", ""))
	var f := _subtitle_font()
	if f != null:
		lb.add_theme_font_override("font", f)
	lb.add_theme_font_size_override("font_size", 20)
	lb.add_theme_color_override("font_color", Color.WHITE)
	lb.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.02, 0.9))
	lb.add_theme_constant_override("outline_size", 5)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.size = Vector2(260.0, 26.0)
	lb.position = Vector2(-130.0, 44.0)
	holder.add_child(lb)
	return holder

func _check_button() -> Control:
	var sz := AtlasUI.size_pt("common_ui", "common_check_btn")
	if sz == Vector2.ZERO:
		sz = Vector2(64.0, 64.0)
	var root := Control.new()
	root.size = sz
	root.pivot_offset = sz * 0.5
	var s := AtlasUI.spr("common_ui", "common_check_btn", Design.ASSET_SCALE)
	if s != null:
		s.position = sz * 0.5
		root.add_child(s)
	var b := Button.new()
	b.flat = true
	b.size = sz
	b.pressed.connect(_close)
	root.add_child(b)
	# 앵커 중앙(원작 CCMenuItem) — position 을 중심으로 받으려고 좌상단을 반만큼 당긴다.
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position -= sz * 0.5
	return root

func _close() -> void:
	closed.emit()
	if _on_ok.is_valid():
		_on_ok.call()
	queue_free()

# ---------------------------------------------------------------- 키 해석
## 인벤 키(또는 재화) → {name, tex, egg}. 아이콘 조회는 render 의 일이다(§8.4 에셋 카탈로그).
## 가상 키 파싱은 각 시스템의 공개 함수를 그대로 쓴다 — 정의를 여기 복제하지 않는다.
static func resolve(e: Dictionary) -> Dictionary:
	var cur := String(e.get("currency", ""))
	if cur != "":
		var cname := "골드" if cur == "gold" else "다이아"
		return {"name": cname,
			"tex": AtlasUI.tex("common_ui", "common_coin" if cur == "gold" else "common_diamond"),
			"egg": false}
	var key := String(e.get("key", ""))
	# 젬 — `gem:<이름>:<티어>`
	var g := Gem.parse_item_key(key)
	if not g.is_empty():
		var gd: Dictionary = Gem.gem_def(String(g["name"]), Data.gems)
		return {"name": Gem.display_name(String(g["name"]), int(g["tier"]), Data.gems),
			"tex": Icons.gem_texture(String(gd.get("code", "")), int(g["tier"])), "egg": false}
	# 장비 — `equip:<옵션>@<카탈로그키>`
	var ck := Equipment.parse_item_key(key)
	if ck != "":
		var it: Dictionary = Equipment.catalog(Data.equipment).get(ck, {})
		return {"name": String(it.get("name", ck)), "tex": Icons.equip_texture(it), "egg": false}
	# 알 — `egg:<드래곤id>`
	var eg := EggGacha.item_def(key, Data.dragons)
	if not eg.is_empty():
		var did := int(eg.get("dragon_id", 0))
		return {"name": String(eg.get("name", "알")),
			"tex": Icons.dragon_egg_texture(did), "egg": true}
	# 스킬 아이템 — `skill:<id>:<레벨>`
	var sk := Loadout.parse_item_key(key)
	if not sk.is_empty():
		var sd: Dictionary = Data.skills.get(str(int(sk["id"])), {})
		var sp := "res://assets/converted/skill/skill_%d.tres" % int(sk["id"])
		return {"name": "%s Lv.%d" % [String(sd.get("name", "스킬")), int(sk["level"])],
			"tex": AtlasUI.tex("common_ui", "common_skill_sroll"),
			"overlay": load(sp) if ResourceLoader.exists(sp) else null,
			"overlay_off": Vector2(1, 5), "egg": false}
	# 평범한 아이템
	var ip := Data.item_icon_path(key)
	var nm := Data.item_name(key)
	return {"name": nm if nm != "" else key,
		"tex": load(ip) if ResourceLoader.exists(ip) else null,
		"egg": String(Data.get_item(key).get("category", "")) == "egg"}

## 원작 `GameManager::getFontName_subtitle` = `font/font_subtitle.fnt`
## (한글 보강본 = `assets/converted/font_ui/`, CLAUDE.md §10).
static func _subtitle_font() -> Font:
	var p := "res://assets/converted/font_ui/font_subtitle.fnt"
	return load(p) if ResourceLoader.exists(p) else null
