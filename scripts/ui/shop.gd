extends Control
## 상점 — 원작 `ShopScene` 이식. render 층(CLAUDE.md §8.1).
##
## ⚠️ 판본 주의: 이 화면은 **`music/bg_shop.mp3`** 를 쓰는 원작 `ShopScene` 이다.
##   `bg_china.mp3` 는 임프상점(`ImpShopScene`, 방랑상인)의 BGM이고 배치도 전혀 다르다 —
##   2026-07-28 이전 구현이 그쪽을 베끼고 있어 통째로 다시 이식했다.
##   근거: ShopScene.c:3413~3421 playBackground 바이트디코드 = "music/bg_shop.mp3",
##         ImpShopScene.c:1492~1500 = "music/bg_china.mp3".
##
## 원작 구조(docs/ref/orig_code/decomp/ShopScene.c :: initWidget, docs/ref/audit/ShopScene.md):
##   1. 아틀라스 4종 로드: common · 9patch · scene/shop · item/item_small
##   2. 배경 `scene/shop/shop_bg.jpg` 를 VisibleRect::center 에, 폭 부족하면 확대
##   3. 진열장 rect = (left+30, bottom+115, W-30-290, H-128-115)
##      · 위 칸 `9patch/shop_box_top`   capInsets(40,40,4,4), 앵커(0,1) @ (x, y+h+2), size(w, h/2+11)
##      · 아래 칸 `9patch/shop_box_bottom` capInsets(40,12,4,4), 앵커(0,0) @ (x, y), size(w, h/2+3)
##      · 네 귀퉁이 `9patch/box_shadow` ×4 (scale 0.97, flipX/flipY 조합)
##   4. 가로 스크롤(ScrollViewEx, direction=0) size(w-46, h-46) @ (x+23, y+23)
##   5. `common/money_bg` 우상단(right-5, top-15, 앵커(1,1)) + 탭별 지갑
##   6. TitleLayer(`common/bg/title_bar_curtain.png`, 제목, X=`common/close_btn`)
##   7. 탭 = TabImage(배경프레임, `scene/shop/tab_*_%s.png`) 7개 + SELL 은 별도 CCMenuItem
##   8. NpcManager + BottomTextBox(z=101)
##
## 상품 카드(showItem): `common/item_bg` 를 CCMenuItemImageEx(1.05) 로,
##   위치 = (열 × 165 + 92, 윗줄 299 / 아랫줄 99), 앵커 중앙.
##   카드 자식 = `common/backlight3`(scale 0.35) @ (w/2, 90) · 아이콘 @ (w/2, 90) · 이름 @ (w/2, 155).
##   스크롤 내용 폭 = 열수 × 165 + 20.
##
## 판매 목록·가격·NPC 대사 = `data/shop.json` (docs/ref/orig_image/shop/*.webp 실측). logic/data 분리(§8.2).

const CARD_DX := 165.0          # 카드 가로 간격(포인트) — showItem
const CARD_ROW_TOP := 299.0     # 윗줄 y (스크롤 콘텐츠 로컬, Cocos y-up)
const CARD_ROW_BOTTOM := 99.0   # 아랫줄 y
const CARD_X0 := 92.0           # 첫 열 중심 x
const CARD_PAD := 20.0          # 콘텐츠 오른쪽 여백
## 제목 배너 높이(포인트). 원작은 `common/bg/title_bar_curtain` 커튼이라 탭 상단을 가린다 —
## 그 프레임이 우리 덤프에 없어(CLAUDE.md §10) `9patch/pop_title_bg` 로 같은 높이를 만든다.
const TITLE_H := 90.0
## NPC 가 서는 오른쪽 열 폭(포인트). 원작 getItemBoxRect 가 진열장에서 빼 두는 값과 같다.
const NPC_COL := 290.0

var _params: Dictionary = {}
var _pma: CanvasItemMaterial
var _tab := 0
var _mans: Dictionary = {}       # dir -> manifest
var _wallet_root: Control
var _npc: NpcPortrait
var _box: BottomTextBox
## 원작 ShopScene +0x280 — "직전에 사고 팔았다" 플래그. 값 = 품목명(`ShopBuy*` 의 %1$s).
## 비어 있으면 입장 대사. `_seller_line` 이 읽고 지운다.
var _react := ""

# ── 진입 ─────────────────────────────────────────────────────────────────
func enter(params: Dictionary = {}) -> void:
	# 원작 ShopScene::onEnter → SoundManager::playBackground("music/bg_shop.mp3", loop)
	Bgm.play("bg_shop")
	_params = params
	# 진입 지정 탭. `cash`(메인 HUD ⊞ 충전 버튼)는 환전 행을 품은 ETC 탭으로 보낸다.
	var want := String(params.get("tab", ""))
	if want == "cash":
		want = "etc"
	if want != "":
		for i in _tabs().size():
			if String(_tabs()[i].get("id", "")) == want:
				_tab = i
				break
	if _pma != null:
		_rebuild()

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_rebuild()

func _tabs() -> Array:
	return Data.shop.get("tabs", [])

func _cur() -> Dictionary:
	var t := _tabs()
	return t[_tab] if _tab >= 0 and _tab < t.size() else {}

# ── 화면 구성 ────────────────────────────────────────────────────────────
func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_npc = null
	_box = null
	var vis := _vis()
	_build_bg()
	var rect := _item_box_rect(vis)      # Cocos 좌표(원점 좌하단)
	_build_shelf(rect, vis)
	_build_scroll(rect, vis)
	_build_npc(vis)
	_build_wallet(vis)
	_build_title(vis)
	_build_tabs(vis)

## 원작 getItemBoxRect: CCRect(left+30, bottom+115, W-30-290, H-128-115).
func _item_box_rect(vis: Vector2) -> Rect2:
	return Rect2(30.0, 115.0, vis.x - 30.0 - 290.0, vis.y - 128.0 - 115.0)

func _build_bg() -> void:
	var p := "res://assets/converted/shop_bg/shop_bg.jpg"
	if ResourceLoader.exists(p):
		var full := TextureRect.new()
		full.texture = load(p)
		full.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		full.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		full.set_anchors_preset(Control.PRESET_FULL_RECT)
		full.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(full)
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.16, 0.11, 0.08)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

## 진열장 2단 + 귀퉁이 그림자. rect 는 Cocos 좌표.
func _build_shelf(rect: Rect2, vis: Vector2) -> void:
	var top_h := rect.size.y * 0.5 + 11.0
	var bot_h := rect.size.y * 0.5 + 3.0
	# 위 칸 — 앵커(0,1) @ (x, y+h+2) ⇒ Godot 좌상단 = (x, H-(y+h+2))
	var top := _nine("9patch_shop_box_top", Vector2(rect.size.x, top_h), Rect2(40, 40, 4, 4))
	if top != null:
		top.position = Vector2(rect.position.x, vis.y - (rect.position.y + rect.size.y + 2.0))
		add_child(top)
	# 아래 칸 — 앵커(0,0) @ (x, y) ⇒ Godot 좌상단 = (x, H-y-bot_h)
	var bot := _nine("9patch_shop_box_bottom", Vector2(rect.size.x, bot_h), Rect2(40, 12, 4, 4))
	if bot != null:
		bot.position = Vector2(rect.position.x, vis.y - rect.position.y - bot_h)
		add_child(bot)
	# 네 귀퉁이 그림자(원작 루프 4회, scale 0.97, 좌/우는 flipX, 상/하는 flipY).
	for i in 4:
		var s := _spr("ninepatch_ui", "9patch_box_shadow", 0.97)
		if s == null:
			break
		var right_side := (i & 2) != 0
		var top_side := (i & 1) == 0
		var cx: float = rect.position.x + rect.size.x - 23.0 + 1.0 if right_side else rect.position.x + 23.0 - 1.0
		var cy: float = rect.position.y + rect.size.y - 23.0 - 8.0 if top_side else rect.position.y + 23.0 + 4.0
		s.flip_h = right_side
		# 원작 앵커: 좌우는 (0|1, ...) — Godot 중앙앵커라 폭/높이 절반만큼 밀어준다.
		var w: float = s.texture.get_width() * 0.97
		var h: float = s.texture.get_height() * 0.97
		s.position = Vector2(cx + (-w * 0.5 if right_side else w * 0.5),
			vis.y - cy - (h * 0.5 if top_side else -h * 0.5))
		s.z_index = 1
		add_child(s)

## 가로 스크롤 상품 진열. 원작 ScrollViewEx(direction 0 = 가로).
func _build_scroll(rect: Rect2, vis: Vector2) -> void:
	var sw := rect.size.x - 46.0
	var sh := rect.size.y - 46.0
	var scroll := ScrollContainer.new()
	scroll.size = Vector2(sw, sh)
	scroll.position = Vector2(rect.position.x + 23.0, vis.y - rect.position.y - 23.0 - sh)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.z_index = 2
	add_child(scroll)

	var entries := _entries()
	var per_row := int(ceil(entries.size() / 2.0))
	var content := Control.new()
	content.custom_minimum_size = Vector2(maxf(sw, per_row * CARD_DX + CARD_PAD), sh)
	scroll.add_child(content)

	for i in entries.size():
		var col := i if i < per_row else i - per_row
		var cocos_y := CARD_ROW_TOP if i < per_row else CARD_ROW_BOTTOM
		var card := _build_card(entries[i])
		# 원작은 앵커 중앙 @ (col*165+92, cocos_y) — Godot Control 은 좌상단 기준이라 반만큼 뺀다.
		card.position = Vector2(col * CARD_DX + CARD_X0, sh - cocos_y) - card.size * 0.5
		content.add_child(card)

	if entries.is_empty():
		var none := Label.new()
		none.text = "판매 중인 물건이 없습니다."
		none.add_theme_color_override("font_color", Color(0.42, 0.33, 0.2))
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.size = Vector2(sw, 30)
		none.position = Vector2(0, sh * 0.5 - 15)
		content.add_child(none)

## 상품 카드 1장 — `common/item_bg` + 백라이트 + 아이콘 + 이름 + 가격.
func _build_card(e: Dictionary) -> Control:
	var S := Design.ASSET_SCALE
	var bg_info: Dictionary = _man("common_ui").get("common_item_bg", {})
	var cw: float = float(bg_info.get("w", 109)) * S
	var ch: float = float(bg_info.get("h", 138)) * S
	var card := Control.new()
	card.size = Vector2(cw, ch)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var frame := _spr("common_ui", "common_item_bg", S)
	if frame != null:
		frame.position = Vector2(cw * 0.5, ch * 0.5)
		card.add_child(frame)

	# 백라이트 — 원작 scale 0x3eb33333 = 0.35, 위치 (w/2, 90) [Cocos y-up, 카드 로컬]
	var back := _spr("common_ui", "common_backlight3", 0.35 * S)
	if back != null:
		back.position = Vector2(cw * 0.5, ch - 90.0)
		back.modulate = Color(1, 1, 1, 0.85)
		card.add_child(back)

	# 아이템 아이콘 @ (w/2, 90)
	var tex := _entry_icon(e)
	if tex != null:
		var ic := Sprite2D.new()
		ic.texture = tex
		ic.material = _pma
		var iw: float = maxf(1.0, float(tex.get_width()))
		ic.scale = Vector2(56.0 / iw, 56.0 / iw)
		ic.position = Vector2(cw * 0.5, ch - 90.0)
		card.add_child(ic)

	# 이름 @ (w/2, 155) — 원작은 BMFontEx(폭 제한 + 2줄). 한글이라 TTF(§10).
	var nm := Label.new()
	nm.text = String(e.get("label", ""))
	nm.add_theme_font_size_override("font_size", 13)
	nm.add_theme_color_override("font_color", Color(0.26, 0.16, 0.05))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.size = Vector2(cw - 10.0, 36.0)
	nm.position = Vector2(5.0, ch - 155.0 - 18.0)
	card.add_child(nm)

	# 가격 — 재화 아이콘 + 숫자(카드 하단).
	var price := int(e.get("price", 0))
	var sale := int(e.get("sale", 0))
	var cur := String(e.get("cur", "gold"))
	var cur_tex := _currency_icon(cur)
	var py := ch - 26.0
	if cur_tex != null:
		# `common/coin_small1`(28px) 기준으로 크기를 맞춘다 — 정기(ele_*)는 일반 아이템
		# 아이콘이라 원본 그대로 그리면 카드를 덮는다.
		var ci := Sprite2D.new()
		ci.texture = cur_tex
		ci.material = _pma
		var cs: float = 34.0 / maxf(1.0, float(maxi(cur_tex.get_width(), cur_tex.get_height())))
		ci.scale = Vector2(cs, cs)
		ci.position = Vector2(24.0, py)
		card.add_child(ci)
	var pl := Label.new()
	pl.text = _comma(sale if sale > 0 else price)
	pl.add_theme_font_size_override("font_size", 15)
	pl.add_theme_color_override("font_color", Color(0.9, 0.25, 0.1) if sale > 0 else Color(0.2, 0.14, 0.05))
	pl.position = Vector2(40.0, py - 12.0)
	pl.size = Vector2(cw - 44.0, 24.0)
	card.add_child(pl)

	if sale > 0:
		# 원작 `scene/shop/sale_en.png` 배지(showItem 의 setItemSale 경로).
		var badge := _spr("shop_ui", "scene_shop_sale_en", S * 0.8)
		if badge != null:
			badge.position = Vector2(cw - 24.0, 30.0)
			card.add_child(badge)

	var btn := Button.new()
	btn.flat = true
	btn.size = Vector2(cw, ch)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.pressed.connect(func(): _on_card(e))
	card.add_child(btn)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	return card

# ── 지갑 ─────────────────────────────────────────────────────────────────
## `common/money_bg` 우상단(앵커 (1,1) @ right-5, top-15). 내용은 탭이 정한다:
##   money   → showWalletMoney  (골드 + 다이아)
##   element → showWalletElement(정기 6종, 2열×3행)
func _build_wallet(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var info: Dictionary = _man("common_ui").get("common_money_bg", {})
	var w: float = float(info.get("w", 207)) * S
	var h: float = float(info.get("h", 146)) * S
	_wallet_root = Control.new()
	_wallet_root.size = Vector2(w, h)
	_wallet_root.position = Vector2(vis.x - 5.0 - w, 15.0)
	_wallet_root.z_index = 8
	_wallet_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wallet_root)
	var bgs := _spr("common_ui", "common_money_bg", S)
	if bgs != null:
		bgs.position = Vector2(w * 0.5, h * 0.5)
		_wallet_root.add_child(bgs)

	var kind := String(_cur().get("wallet", "money"))
	if kind == "element":
		var order: Array = Data.shop.get("_wallet", {}).get("element", [])
		# 원작 좌표(Cocos, money_bg 로컬): 아이콘 (40,100)(40,70)(40,40)(150,…), 숫자는 x+15
		var slots := [Vector2(40, 100), Vector2(40, 70), Vector2(40, 40),
			Vector2(150, 100), Vector2(150, 70), Vector2(150, 40)]
		for i in mini(order.size(), slots.size()):
			var key := String(order[i])
			var p: Vector2 = slots[i]
			var it := _item_texture(key)
			if it != null:
				var s := Sprite2D.new()
				s.texture = it
				s.material = _pma
				var iw: float = maxf(1.0, float(it.get_width()))
				s.scale = Vector2(26.0 / iw, 26.0 / iw)
				s.position = Vector2(p.x, h - p.y)
				_wallet_root.add_child(s)
			var l := Label.new()
			l.text = _comma(UserDB.item_count(key))
			l.add_theme_font_size_override("font_size", 15)
			l.add_theme_color_override("font_color", Color(1, 1, 1))
			l.add_theme_color_override("font_outline_color", Color(0.25, 0.14, 0.05))
			l.add_theme_constant_override("outline_size", 4)
			l.position = Vector2(p.x + 15.0, h - p.y - 11.0)
			l.size = Vector2(80, 22)
			_wallet_root.add_child(l)
	else:
		_wallet_line(0, "common_coin_small1", _comma(UserDB.gold()), h, 100.0)
		_wallet_line(1, "common_diamond_small1", _comma(UserDB.diamond()), h, 62.0)

func _wallet_line(_i: int, icon_key: String, text: String, h: float, cocos_y: float) -> void:
	var S := Design.ASSET_SCALE
	var s := _spr("common_ui", icon_key, S)
	if s != null:
		s.position = Vector2(40.0, h - cocos_y)
		_wallet_root.add_child(s)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0.25, 0.14, 0.05))
	l.add_theme_constant_override("outline_size", 4)
	l.position = Vector2(62.0, h - cocos_y - 14.0)
	l.size = Vector2(190, 26)
	_wallet_root.add_child(l)

# ── 타이틀 / 탭 ──────────────────────────────────────────────────────────
## 원작 TitleLayer("common/bg/title_bar_curtain.png", 제목, X="common/close_btn").
## ⚠️ `common/bg/` 하위 프레임은 우리 구판 덤프에 통째로 없다(CLAUDE.md §10 표) →
##    보유한 `9patch/pop_title_bg` 로 대체한다. X 버튼은 원본 프레임 그대로.
func _build_title(vis: Vector2) -> void:
	# 원작은 `9patch/pop_title_bg` 를 capInsets 없이 만든다(=Cocos 기본 1/3 분할).
	var bar := _nine("9patch_pop_title_bg", Vector2(vis.x, TITLE_H), Rect2())
	if bar != null:
		bar.position = Vector2(0, 0)
		bar.z_index = 9
		add_child(bar)
	var t := Label.new()
	t.text = "상점"
	t.add_theme_font_size_override("font_size", 32)
	t.add_theme_color_override("font_color", Color(1, 0.85, 0.35))
	t.add_theme_color_override("font_outline_color", Color(0.3, 0.13, 0.03))
	t.add_theme_constant_override("outline_size", 6)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size = Vector2(vis.x, TITLE_H)
	t.z_index = 10
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)

	var x := _spr("common_ui", "common_close_btn", Design.ASSET_SCALE)
	if x != null:
		x.position = Vector2(vis.x - 42, TITLE_H * 0.5)
		x.z_index = 11
		add_child(x)
	var xb := Button.new()
	xb.flat = true
	xb.size = Vector2(56, 56)
	xb.position = Vector2(vis.x - 70, TITLE_H * 0.5 - 28)
	xb.z_index = 11
	xb.pressed.connect(_close)
	add_child(xb)

## 원작 TabMenu: i번째 탭 = 앵커(0,1) @ ((tabW+5)*i + 70, top), 아이콘은 탭 로컬 (tabW/2, 50).
## SELL 만 별도 CCMenuItem 으로 마지막 탭 오른쪽(maxX+5)에 붙는다(ShopScene.c:2899~2941).
func _build_tabs(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var tabs := _tabs()
	var info: Dictionary = _man("common_ui").get("common_tab_bg", {})
	var tw: float = float(info.get("w", 78)) * S
	var th: float = float(info.get("h", 122)) * S
	# 화면 비율이 1.6 미만이면 원작은 메뉴를 -90 밀고 0.86배로 줄인다(initWidget 끝부분).
	var narrow := (vis.x / vis.y) < 1.6
	var k := 0.86 if narrow else 1.0
	var x0 := (70.0 - 90.0) if narrow else 70.0
	var idx := 0
	for i in tabs.size():
		var td: Dictionary = tabs[i]
		var is_sell := String(td.get("id", "")) == "sell"
		var tx := x0 + (tw + 5.0) * k * idx
		if not is_sell:
			idx += 1
		var holder := Control.new()
		holder.position = Vector2(tx, 0)
		holder.z_index = 6
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(holder)
		var bg := _spr("common_ui", "common_%s" % String(td.get("tab_bg", "tab_bg")), S * k)
		if bg != null:
			bg.position = Vector2(tw * k * 0.5, th * k * 0.5)
			# 선택되지 않은 탭은 살짝 내려가 커튼 뒤로 들어간다(원작 TabMenu 선택 표현).
			if i != _tab:
				bg.position.y -= 10
				bg.modulate = Color(0.86, 0.82, 0.78)
			holder.add_child(bg)
		var ic := _spr("shop_ui", "scene_shop_%s" % String(td.get("icon", "")), S * k)
		if ic != null:
			# 원작 아이콘 위치 = 탭 로컬 (tabW/2, 50) [Cocos y-up]
			ic.position = Vector2(tw * k * 0.5, th * k - 50.0 * k)
			if i != _tab:
				ic.position.y -= 10
				ic.modulate = Color(0.9, 0.88, 0.85)
			holder.add_child(ic)
		var b := Button.new()
		b.flat = true
		b.size = Vector2(tw * k, th * k - 40.0)
		b.position = Vector2(tx, 30)
		b.z_index = 7
		var ti := i
		b.pressed.connect(func(): _on_tab(ti))
		add_child(b)

## 원작 onClickTab: 탭 인덱스를 바꾸고 → setSeller(NPC 교체 + 등장 연출) → showItem.
func _on_tab(i: int) -> void:
	if i == _tab:
		return
	_tab = i
	_rebuild()

# ── NPC + 대사창 ─────────────────────────────────────────────────────────
## 원작 setSeller: 탭 index → NPC 이름 고정 매핑(ShopScene.c:4674~4734).
##   0/2=pino · 1=raon · 3=randolph · 4/6=popo · 5=baruseu · 그 외(7=SELL)=romini
## 배치는 getDefaultNpcPos(2) = **화면 오른쪽** (visW - bodyW/2 - offset).
func _build_npc(vis: Vector2) -> void:
	var td := _cur()
	var name := String(td.get("npc", ""))
	if name == "":
		return
	var greet := _seller_line(name, String(td.get("id", "")))
	var emo: int = greet["emo"]
	_npc = NpcPortrait.create(name, emo)
	if _npc == null:
		return
	_npc.z_index = 5
	add_child(_npc)
	var bw := _npc.body_width()
	# 원작 getDefaultNpcPos(2) = 오른쪽. 진열장이 비워 둔 290pt 열의 가운데에, 발은 화면 바닥.
	_npc.position = Vector2(vis.x - NPC_COL * 0.5, vis.y)
	# 등장: 원작 setSellerShow — 오른쪽에서 밀려 들어오고(EaseBackOut 0.4s) 살짝 튄다.
	var to_x := _npc.position.x
	_npc.position.x = vis.x + bw * 0.5
	var tw := create_tween()
	tw.tween_property(_npc, "position:x", to_x, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 대사창은 NPC 열을 침범하지 않는다 — 원작 스크린샷에서도 진열장 오른쪽 끝과 딱 맞는다
	# (docs/ref/orig_image/shop/상점_음식.webp: 박스 오른쪽 모서리 = visW-290).
	_box = BottomTextBox.new()
	_box.max_width = vis.x - NPC_COL
	_box.z_index = 12
	add_child(_box)
	_say(String(greet["line"]))

## 원작 setSeller 의 대사·표정 선택(ShopScene.c:4655~4767). 두 갈래를 플래그로 나눈다.
##   · 입장/탭 전환(+0x281) → idx = rand()%3 + 1 → `ShopWelcome<npc>_<idx>`
##   · 구매·판매 직후(+0x280) → idx = rand()%2 + 1 → `ShopBuy<npc>_<idx>`
##     (판매 탭은 `ShopSellromini_<idx>`). `[%1$s]` 자리에 품목명이 들어간다.
##   · 어느 쪽이든 **그 idx 가 표정 index 로도 그대로** 넘어간다
##     (`setSellerShow(…, 1, idx, …)` @:4767) — 대사와 표정이 짝이다.
##   · ETC(바루스)는 idx 를 1 로 고정(:4720), HOT 탭은 NPC 대사 대신 탭 고정 문구(:4938).
##   · 원작도 구매 후 setSeller 를 다시 불러 판매원을 재등장시킨다 → 우리 `_rebuild()` 와 같다.
## 문자열은 유실이 아니라 원작 stringsData_KR.xml 에 있다 → build_npc_lines.py 가 뽑아 둔
## data/npc_lines.json `shop` 블록이 1차 출처. 없으면 data/shop.json 의 `line` 으로 폴백.
## ⚠️ 원작은 randolph/popo 에 한해 특정 아이템(id 219·220·4000 / 카테고리 1)이면 idx+2(_3/_4)를
##   쓴다(:146~202). 우리 탭 구성엔 그 분류가 없어 _1/_2 만 쓴다 — data/npc_lines.json `_note` 참조.
func _seller_line(npc: String, tab_id: String) -> Dictionary:
	var shop: Dictionary = Data.npc_lines_doc.get("shop", {})
	if _react != "":
		var key := "sell" if tab_id == "sell" else "buy"
		var pool: Array = (shop.get(key, {}) as Dictionary).get(npc, [])
		var label := _react
		_react = ""
		if not pool.is_empty():
			var i: int = mini((randi() % 2) + 1, pool.size())
			return {"line": String(pool[i - 1]).replace("%1$s", label), "emo": i}
	var idx := 1 if npc == "baruseu" else (randi() % 3) + 1
	if tab_id == "hot":
		var fixed := String((shop.get("tab", {}) as Dictionary).get("hot", ""))
		if fixed != "":
			return {"line": fixed, "emo": idx}
	var lines: Array = (shop.get("welcome", {}) as Dictionary).get(npc, [])
	if idx <= lines.size():
		return {"line": String(lines[idx - 1]), "emo": idx}
	return {"line": String(_cur().get("line", "")), "emo": idx}

## 대사창에 한 줄 띄우고, 읽는 동안 입을 움직인다(원작 setMouseAction/setStopMouse).
func _say(line: String) -> void:
	if _box == null:
		return
	_box.show_text(_npc_display_name(String(_cur().get("npc", ""))), line)
	if _npc != null:
		_npc.set_talking(true)
	_box.finished.connect(func(): if is_instance_valid(_npc): _npc.set_talking(false),
		CONNECT_ONE_SHOT)

## NPC 표시 이름 — 원작 문자열(stringsData_KR)에서 뽑아 둔 data/npc_lines.json 이 1차 출처.
const NPC_KR := {
	"pino": "피노", "raon": "라온", "randolph": "란돌프",
	"popo": "포포", "baruseu": "바루스", "romini": "루미니",
}
func _npc_display_name(key: String) -> String:
	var per = Data.npc_lines().get(key, null)
	if per is Dictionary and String(per.get("name", "")) != "":
		return String(per["name"])
	return String(NPC_KR.get(key, key))

# ── 상품 목록 / 구매 ─────────────────────────────────────────────────────
## 현재 탭이 진열할 항목 목록. `{label, price, cur, item|gacha, sale}` 로 정규화한다.
func _entries() -> Array:
	var td := _cur()
	var out: Array = []
	if String(td.get("id", "")) == "sell":
		return _sell_entries()
	for g in td.get("gacha", []):
		var ge: Dictionary = (g as Dictionary).duplicate()
		ge["kind"] = "gacha"
		out.append(ge)
	for s in td.get("stock", []):
		var e: Dictionary = (s as Dictionary).duplicate()
		var key := String(e.get("item", ""))
		var it: Dictionary = Data.items.get(key, {})
		if it.is_empty():
			continue                      # 아이템 DB에 없는 후기판 상품은 조용히 건너뛴다
		e["kind"] = "item"
		if not e.has("label"):
			e["label"] = String(it.get("name", key))
		out.append(e)
	out.append_array(_extra_entries(td))
	return out

## 오프라인 재설계분(젬·장비 상점 / 젬 뽑기 / 환전)을 원작 탭 안에 얹는다.
## 근거는 data/shop.json 의 `_extra_note` — 원작에 없던 항목이라 출처를 데이터에 남겨 둔다.
func _extra_entries(td: Dictionary) -> Array:
	var out: Array = []
	for tag in td.get("extra", []):
		match String(tag):
			"gem_shop":
				for g in Drops.shop_gems(Data.drops):
					out.append({"kind": "gear", "gear": String(g["key"]),
						"label": Drops.display_name(String(g["key"]), Data.gems, Data.equipment),
						"price": int(g["price"]), "cur": "gold"})
			"equip_shop":
				for q in Drops.shop_equips(Data.drops):
					out.append({"kind": "gear", "gear": String(q["key"]),
						"label": Drops.display_name(String(q["key"]), Data.gems, Data.equipment),
						"price": int(q["price"]), "cur": "gold"})
			"gem_gacha":
				var gc: Dictionary = Data.drops.get("gacha", {}).get("gem", {})
				out.append({"kind": "gacha", "pool": "gem", "label": "젬 뽑기",
					"price": int(gc.get("price_single", 15)), "cur": "diamond", "n": 1})
				out.append({"kind": "gacha", "pool": "gem",
					"label": "젬 뽑기 %d연속" % int(gc.get("ten_count", 10)),
					"price": int(gc.get("price_ten", 125)), "cur": "diamond",
					"n": int(gc.get("ten_count", 10))})
			"cash":
				out.append_array(_cash_entries())
	return out

## 환전 상품 — 원작 `PremiumShopScene` 자리의 오프라인 대체(§2-1).
## 아이콘은 보유 원본 프레임 `scene/shop/cash_gold1~6` · `cash_diamond1~6`.
func _cash_entries() -> Array:
	var cash: Dictionary = Data.drops.get("cash", {})
	var out: Array = []
	var gp: Dictionary = cash.get("gold_pack", {})
	var per := int(gp.get("gold_per_dia", 1000))
	var bonus: Array = gp.get("bonus_pct", [])
	var tiers: Array = gp.get("dia_tiers", [])
	for i in tiers.size():
		var dia := int(tiers[i])
		var b := int(bonus[i]) if i < bonus.size() else 0
		var gold := int(dia * per * (100 + b) / 100.0)
		out.append({"kind": "exchange", "give": "diamond", "give_n": dia,
			"get": "gold", "get_n": gold, "bonus": b,
			"label": "골드 %s" % _comma(gold), "price": dia, "cur": "diamond",
			"icon_frame": "scene_shop_cash_gold%d" % mini(i + 1, 6)})
	var dp: Dictionary = cash.get("dia_pack", {})
	var dper := int(dp.get("gold_per_dia", 2500))
	for j in dp.get("dia_tiers", []).size():
		var d2 := int(dp["dia_tiers"][j])
		var cost := d2 * dper
		out.append({"kind": "exchange", "give": "gold", "give_n": cost,
			"get": "diamond", "get_n": d2, "bonus": 0,
			"label": "다이아 %d" % d2, "price": cost, "cur": "gold",
			"icon_frame": "scene_shop_cash_diamond%d" % mini(j + 1, 6)})
	return out

## SELL 탭 — 보유 중인 아이템만. 가격 = 구매가 × _sell_ratio(원작 실측 10%).
func _sell_entries() -> Array:
	var ratio := float(Data.shop.get("_sell_ratio", 0.1))
	var buy := _buy_price_index()
	var out: Array = []
	for key in UserDB.inventory().keys():
		var k := String(key)
		if UserDB.item_count(k) <= 0:
			continue
		var it: Dictionary = Data.items.get(k, {})
		if it.is_empty():
			continue
		if String(it.get("category", "")) == "currency":
			continue                       # 정기는 팔 수 없다(재화)
		var base := int(buy.get(k, int(it.get("price", 0))))
		var price := int(round(base * ratio)) if base > 0 else 0
		if price <= 0:
			continue
		out.append({"kind": "sell", "item": k, "label": String(it.get("name", k)),
			"price": price, "cur": "gold"})
	out.sort_custom(func(a, b): return String(a["item"]) < String(b["item"]))
	return out

## 구매가 색인(골드 상품만) — SELL 가격 산출용.
func _buy_price_index() -> Dictionary:
	var idx := {}
	for td in _tabs():
		for s in td.get("stock", []):
			if String(s.get("cur", "gold")) == "gold":
				idx[String(s.get("item", ""))] = int(s.get("price", 0))
	return idx

func _on_card(e: Dictionary) -> void:
	match String(e.get("kind", "item")):
		"gacha": _confirm_gacha(e)
		"sell": _confirm_sell(e)
		"gear": _confirm_gear(e)
		"exchange": _confirm_exchange(e)
		_: _confirm_buy(e)

## 젬·장비(가상 인벤 키 gem:/equip:) 골드 구매.
## 원작은 **장비(Equip)면 수량판을 만들지 않는다**(ItemDetailLayer.c:14868 게이트) —
## 장비는 1개씩, 젬은 재화가 닿는 만큼.
func _confirm_gear(e: Dictionary) -> void:
	var key := String(e.get("gear", ""))
	var price := int(e.get("price", 0))
	var glabel := String(e.get("label", key))
	var is_equip := Equipment.parse_item_key(key) != ""
	_detail_popup({
		"title": glabel, "desc": _item_desc(key), "icon": _entry_icon(e),
		"price": price, "cur": "gold", "action": "구매",
		"max": 1 if is_equip else _afford_max("gold", price),
		"on_ok": func(n: int):
			if not UserDB.spend("gold", price * n):
				_toast("골드가 부족합니다.")
				return
			UserDB.add_item(key, n)
			_react = glabel
			_rebuild()
			# 원작도 장비/젬 구매 직후 획득물을 공개한다
			# (`ItemDetailLayer.c:6887`·`:7265`·`:7291` = EQUIP 분기).
			_toast("%s 구매 완료%s" % [glabel, ("  ×%d" % n) if n > 1 else ""])
			GetItemPopup.open(self, [{"key": key, "count": n}]),
	})

## 골드↔다이아 환전. 원작에 없는 우리 재설계(캐시상점 대체, CLAUDE.md §10)라
## 아이템이 아니지만 같은 상세 팝업 틀을 쓴다 — 지불 재화가 곧 가격이다.
func _confirm_exchange(e: Dictionary) -> void:
	var give := String(e.get("give", "gold"))
	var give_n := int(e.get("give_n", 0))
	var get_kind := String(e.get("get", "gold"))
	var get_n := int(e.get("get_n", 0))
	_detail_popup({
		"title": "환전", "icon": _currency_icon(get_kind), "action": "환전",
		"desc": "%s %s 를 %s %s 로 바꿉니다." % [_comma(give_n), _cur_name(give),
			_comma(get_n), _cur_name(get_kind)],
		"price": give_n, "cur": give, "max": 1,
		"on_ok": func(_n: int):
			if not UserDB.spend(give, give_n):
				_toast("재화가 부족합니다.")
				return
			UserDB.add_currency(get_kind, get_n)
			_toast("환전 완료")
			_rebuild(),
	})

func _confirm_buy(e: Dictionary) -> void:
	var key := String(e.get("item", ""))
	var price := int(e.get("sale", 0)) if int(e.get("sale", 0)) > 0 else int(e.get("price", 0))
	var cur := String(e.get("cur", "gold"))
	var bundle := int(e.get("bundle", 1))     # 1회 구매로 들어오는 개수(묶음 상품)
	var label := String(e.get("label", key))
	_detail_popup({
		"title": label, "desc": _item_desc(key), "icon": _entry_icon(e),
		"note": ("1회 구매 시 %d개" % bundle) if bundle > 1 else "",
		"price": price, "cur": cur, "action": "구매", "max": _afford_max(cur, price),
		"on_ok": func(n: int):
			if not _pay(cur, price * n):
				_toast("재화가 부족합니다.")
				return
			UserDB.add_item(key, bundle * n)
			_react = label
			_rebuild()
			# 원작은 `addItem` 직후 `ShowGetItemDetailLayer` 로 획득물을 공개한다
			# (`ItemDetailLayer.c:2041`). 대사창 안내는 그대로 남긴다(원작 setText 경로).
			_toast("%s 구매 완료%s" % [label, ("  ×%d" % (bundle * n)) if bundle * n > 1 else ""])
			GetItemPopup.open(self, [{"key": key, "count": bundle * n}]),
	})

## 지금 재화로 몇 개까지 살 수 있나.
## 상한 **99 = 원작 구매한도**(사용자 확정 2026-07-30: "구매한도는 회당 99개").
##
## ⚠️ 원작 상세창의 한도 게이지(`9patch/bar_bg1` + `shop_limit_title_%d`,
##    ItemDetailLayer.c:14959)는 **이 99와 다른 것**이다 — 2026-07-30 정정:
##    `stringsData_KR.xml` 의 `shop_limit_title_1~3` = 일간/주간/월간,
##    `shop_limit_soldout_1~3` = "내일/다음 주/다음 달 재입고" ⇒ **재입고 재고 쿼터**이고
##    값은 `ShopScene::getLimit`(ShopScene.c:1662)이 서버가 내려준 목록에서 찾는다 = 유실.
##    ⇒ 게이지는 이식하지 않는다(docs/ref/porting/ItemDetailLayer.md §4).
const PURCHASE_LIMIT := 99
func _afford_max(cur: String, price: int) -> int:
	if price <= 0:
		return PURCHASE_LIMIT
	var have := 0
	if cur == "gold" or cur == "diamond":
		have = UserDB.currency(cur)
	else:
		have = UserDB.item_count(cur)
	return clampi(have / price, 1, PURCHASE_LIMIT)

## 판매. 원작도 판매에 수량 카운터가 붙는다(`ShopScene.c:3200` = `create(item, 1, 1, …)`)
## — 상한은 보유 개수(회당 한도 99 이내).
func _confirm_sell(e: Dictionary) -> void:
	var key := String(e.get("item", ""))
	var price := int(e.get("price", 0))
	var label := String(e.get("label", key))
	_detail_popup({
		"title": label, "desc": _item_desc(key), "icon": _entry_icon(e),
		"price": price, "cur": "gold", "action": "판매",
		"max": clampi(UserDB.item_count(key), 1, PURCHASE_LIMIT),
		"on_ok": func(n: int):
			if not UserDB.use_item(key, n):
				return
			UserDB.add_currency("gold", price * n)
			_toast("%s 판매%s" % [label, ("  ×%d" % n) if n > 1 else ""])
			_react = label
			_rebuild(),
	})

## 장신구 뽑기 — 원작 ITEM 탭 상품(일반/고급/전용 ×1/×10). 등급별 풀은 data/drops.json.
func _confirm_gacha(e: Dictionary) -> void:
	var price := int(e.get("price", 0))
	var cur := String(e.get("cur", "diamond"))
	var n := int(e.get("n", 1))
	_detail_popup({
		"title": String(e.get("label", "")), "icon": _entry_icon(e), "action": "뽑기",
		"desc": "%d회 뽑습니다." % n if n > 1 else "1회 뽑습니다.",
		"price": price, "cur": cur, "max": 1,
		"on_ok": func(_n: int):
			if not _pay(cur, price):
				_toast("재화가 부족합니다.")
				return
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			var pool := String(e.get("pool", "equip"))
			var got: Array = []
			for _i in n:
				var k := Drops.roll_gem_gacha(Data.drops, Data.gems, rng) if pool == "gem" \
					else Drops.roll_equip_gacha(Data.drops, Data.equipment, rng)
				if k == "":
					continue
				UserDB.add_item(k, 1)
				got.append(k)
			_rebuild()
			_show_result(got),
	})

## 재화 지불. gold/diamond 는 UserDB 재화, 그 외(ele_* 정기)는 인벤 아이템.
func _pay(cur: String, amount: int) -> bool:
	if amount <= 0:
		return true
	if cur == "gold" or cur == "diamond":
		return UserDB.spend(cur, amount)
	return UserDB.use_item(cur, amount)

## 아이템 설명(원작 `Item::getComment()`). 출처 = data/items.json `desc`
## (docs/input/items/items.csv `설명` 열 → scripts/tools/build_item_descs.py).
## 없으면 "" — 지어내지 않는다(HARD RULE 6).
func _item_desc(key: String) -> String:
	var it: Dictionary = Data.items.get(key, {})
	return String(it.get("desc", ""))

func _cur_name(cur: String) -> String:
	if cur == "gold":
		return "골드"
	if cur == "diamond":
		return "다이아"
	var it: Dictionary = Data.items.get(cur, {})
	return String(it.get("name", cur))

func _currency_icon(cur: String) -> Texture2D:
	if cur == "gold":
		return _tex("common_ui", "common_coin_small1")
	if cur == "diamond":
		return _tex("common_ui", "common_diamond_small1")
	return _item_texture(cur)

func _entry_icon(e: Dictionary) -> Texture2D:
	if e.has("icon_frame"):
		return _tex("shop_ui", String(e["icon_frame"]))
	match String(e.get("kind", "")):
		"gacha":
			# 장비 가챠는 원작 아이콘이 있다(사용자 확정 2026-07-29):
			#   `item/accessory/gooddeco` = 다이아 가챠 · `olddeco` = 골드 가챠.
			# 젬 가챠는 여전히 전용 아이콘이 없어 보석 상자로 대신한다.
			if String(e.get("pool", "")) != "gem":
				var t := Icons.texture("shop",
					"equip_gacha_gold" if String(e.get("cur", "")) == "gold" else "equip_gacha_diamond")
				if t != null:
					return t
			return _item_texture("jem_random")
		"gear":
			return _gear_texture(String(e.get("gear", "")))
	return _item_texture(String(e.get("item", "")))

## 젬/장비 가상 인벤 키 → 아이콘(§8.4 에셋 카탈로그). 젬/장비가 아니면 null.
func _gear_texture(key: String) -> Texture2D:
	var g := Gem.parse_item_key(key)
	if not g.is_empty():
		return Icons.gem_texture(
			String(Gem.gem_def(String(g["name"]), Data.gems).get("code", "")), int(g["tier"]))
	var ck := Equipment.parse_item_key(key)
	if ck != "":
		return Icons.equip_texture(Equipment.catalog(Data.equipment).get(ck, {}))
	return null

func _item_texture(key: String) -> Texture2D:
	var p := Data.item_icon_path(key)
	if p != "" and ResourceLoader.exists(p):
		return load(p)
	return null

# ── 구매 상세 팝업 — 원작 `ItemDetailLayer` 이식 ─────────────────────────
# 상세 = docs/ref/porting/ItemDetailLayer.md (좌표·프레임·근거 줄번호 전부 거기)
#
# 원작은 상품 칸 클릭이 `ShopScene::onClickItemBuy`(ShopScene.c:5875 에서 배선) 에 직결돼
# 그 자리에서 `ItemDetailLayer::create(item, isSell, showQty, …)` → `setShopType(1)` →
# `PopupLayer::show(scene, 99, 127.0)` 를 띄운다. 하단 대사창은 **구매/판매 후 NPC 멘트**
# (`ShopBuypopo_%d`·`ShopSellromini_%d`, ShopScene.c:243/316) 전용이지 설명창이 아니다.

## 원작 `setContentSpriteSize(650, 400)` (ItemDetailLayer.c:11732).
const DETAIL_PANEL := Vector2(650.0, 400.0)
## 원작 `setContentSprite("9patch/popup4.png", CCRect(130,190,40,58))` (:11731).
const DETAIL_CAP := Rect2(130, 190, 40, 58)

## 패널 로컬 Cocos 좌표(원점 좌하단, y-up) → Godot 좌표. `initWidget` 의 리터럴을 그대로
## 쓰기 위한 유일한 변환 지점이다 — 원작 좌표를 손으로 뒤집어 적지 않는다.
func _pg(x: float, y: float) -> Vector2:
	return Vector2(x, DETAIL_PANEL.y - y)

## 구매/판매/뽑기 상세 팝업.
## cfg = {
##   title  : 제목바 문구(원작 = 아이템 이름 `Item::getName()`)
##   desc   : 설명(원작 `Item::getComment()`) — 오른쪽 단
##   note   : 설명 아래 한 줄(묶음 수량 등 우리 부가 정보). 없으면 생략
##   icon   : Texture2D — 왼쪽 후광 위 아이콘
##   price  : 단가(0이면 가격·재화 표시 없음)
##   cur    : 재화 키(gold/diamond/아이템키)
##   max    : 수량 상한(1이면 수량판을 만들지 않는다 = 원작 showQty=0)
##   action : 실행 버튼 문구("구매"/"판매"/"환전"/"뽑기")
##   on_ok  : Callable(n) — 고른 개수를 받는다
## }
func _detail_popup(cfg: Dictionary) -> void:
	var S := Design.ASSET_SCALE
	var vis := _vis()
	var maxn: int = maxi(1, int(cfg.get("max", 1)))
	var price := int(cfg.get("price", 0))
	var cur := String(cfg.get("cur", "gold"))
	var on_ok: Callable = cfg.get("on_ok", Callable())

	var lay := CanvasLayer.new()
	lay.layer = 40
	add_child(lay)
	# 원작 PopupLayer 는 검은 CCLayerColor(alpha 0)를 깔고 `show(…, 127.0)` 으로
	# CCFadeTo(0.2초, 127) 한다(PopupLayer.c:296·1211). 127/255 = 0.498.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 127.0 / 255.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.modulate = Color(1, 1, 1, 0)
	lay.add_child(dim)
	dim.create_tween().tween_property(dim, "modulate:a", 1.0, 0.2)

	# 위치 = `setContentSpritePosition(진열장.x + 진열장.w*0.5, 화면중앙.y)` (ShopScene.c:3143).
	# ⇒ NPC·하단 대사창·지갑을 가리지 않는다. 종전 자작 팝업은 화면 정중앙이라 이게 어긋났다.
	var box := _item_box_rect(vis)
	var center := Vector2(box.position.x + box.size.x * 0.5, vis.y * 0.5)
	var panel := Control.new()
	panel.size = DETAIL_PANEL
	panel.position = (center - DETAIL_PANEL * 0.5).round()
	panel.pivot_offset = DETAIL_PANEL * 0.5
	lay.add_child(panel)
	# 등장 = CCScaleTo(0.1, 1.2) → CCScaleTo(0.1, 1.0) (PopupLayer.c:1214).
	var tw := panel.create_tween()
	tw.tween_property(panel, "scale", Vector2(1.2, 1.2), 0.1)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.1)

	var bg := _nine("9patch_popup4", DETAIL_PANEL, DETAIL_CAP)
	if bg != null:
		panel.add_child(bg)

	_detail_title(panel, String(cfg.get("title", "")), func(): lay.queue_free())
	_detail_item(panel, cfg.get("icon") as Texture2D, S)
	_detail_text(panel, String(cfg.get("desc", "")), String(cfg.get("note", "")))

	var count := [1]                 # 배열로 감싸 람다가 값을 공유한다(§GDScript 캡처 함정)
	var total := Label.new()         # 버튼 위의 총액 — 수량이 바뀌면 여기만 다시 쓴다
	var step := func(d: int):
		var v: int = clampi(int(count[0]) + d, 1, maxn)
		if v == int(count[0]):
			return
		count[0] = v
		total.text = _comma(price * v)
	if maxn > 1:
		_detail_qty(panel, maxn, count, step, S)
	_detail_action(panel, cfg, total, price, cur, count, S, func():
		lay.queue_free()
		if on_ok.is_valid():
			on_ok.call(int(count[0])))

## 제목바(폭 = 패널×0.9) + 아이템 이름 + 우상단 X. 원작 :12546·:12607·:12622.
func _detail_title(panel: Control, title: String, on_close: Callable) -> void:
	var S := Design.ASSET_SCALE
	var bar_h: float = float(_man("ninepatch_ui").get("9patch_pop_title_bg", {}).get("h", 33)) * S
	var bar_w := DETAIL_PANEL.x * 0.9
	# 원작은 capInsets 없이 만든다 = Cocos 기본 1/3 분할.
	var bar := _nine("9patch_pop_title_bg", Vector2(bar_w, bar_h), Rect2())
	if bar != null:
		bar.position = _pg(DETAIL_PANEL.x * 0.5, 350.0) - Vector2(bar_w, bar_h) * 0.5
		panel.add_child(bar)
	var tl := Label.new()
	tl.text = title
	var f := _orig_font()
	if f != null:
		tl.add_theme_font_override("font", f)      # 원작 getFontName_subtitle scale 1.1
	tl.add_theme_font_size_override("font_size", 22)
	tl.add_theme_color_override("font_color", Color.WHITE)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tl.size = Vector2(bar_w, bar_h)
	tl.position = _pg(DETAIL_PANEL.x * 0.5, 350.0) - Vector2(bar_w, bar_h) * 0.5
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(tl)

	var x := _spr("common_ui", "common_close_btn", 1.5 * S)   # 원작 scale 1.5
	if x != null:
		x.position = _pg(600.0, 350.0)
		panel.add_child(x)
	var xb := Button.new()
	xb.flat = true
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		xb.add_theme_stylebox_override(st, empty)
	xb.size = Vector2(64, 64)
	xb.position = _pg(600.0, 350.0) - Vector2(32, 32)
	xb.pressed.connect(on_close)
	panel.add_child(xb)

## 왼쪽 단 — 회전하는 후광 + 아이템 아이콘. 둘 다 원작 (150, 220). :12039·:12106.
func _detail_item(panel: Control, icon: Texture2D, S: float) -> void:
	var back := _spr("common_ui", "common_backlight3", 0.6 * S)   # 원작 scale 0.6
	if back != null:
		back.position = _pg(150.0, 220.0)
		back.modulate = Color(1, 1, 1, 0.85)
		panel.add_child(back)
		# 원작 CCRepeatForever(CCRotateBy(5.0, 60.0)) — 5초에 60°.
		var rot := back.create_tween().set_loops()
		rot.tween_property(back, "rotation", back.rotation + deg_to_rad(60.0), 5.0)\
			.as_relative().from_current()
	if icon == null:
		return
	var ic := Sprite2D.new()
	ic.texture = icon
	ic.material = _pma
	# 원작은 아이콘을 원본 크기(=디자인공간 ×4/3)로 그린다. 다만 아틀라스마다 원본 크기가
	# 제각각이라(알 200px대 · 소모품 60px대) 왼쪽 단(약 150pt)을 넘으면 그만큼만 줄인다.
	var long_side: float = maxf(1.0, float(maxi(icon.get_width(), icon.get_height())))
	ic.scale = Vector2.ONE * minf(S, 150.0 / long_side)
	ic.position = _pg(150.0, 220.0)
	panel.add_child(ic)

## 오른쪽 단 — 설명(원작 `Item::getComment()`)과 부가 한 줄.
## 원작 :12722 = `CCLabelBMFontEx(폭 300)` 앵커(0,1) @ (300,280), 색 (129,67,29),
## 길이 0xf0(240)자 초과 시 scale 0.8.
func _detail_text(panel: Control, desc: String, note: String) -> void:
	const COL_W := 300.0
	var f := _orig_font()
	var y := 280.0
	if desc != "":
		var dl := Label.new()
		dl.text = desc
		if f != null:
			dl.add_theme_font_override("font", f)
		dl.add_theme_font_size_override("font_size", 16 if desc.length() > 240 else 20)
		# 원작 setColor(0x1d4381 리틀엔디안 = R129 G67 B29) — 갈색.
		# ⚠️ `Color(129,67,29) / 255.0` 로 쓰면 **알파까지 나눠져**(1→0.004) 글자가 사라진다.
		dl.add_theme_color_override("font_color", Color(129.0 / 255.0, 67.0 / 255.0, 29.0 / 255.0))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.size = Vector2(COL_W, 150.0)
		dl.position = _pg(300.0, y)
		dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(dl)
		y -= 150.0
	if note == "":
		return
	var nl := Label.new()
	nl.text = note
	if f != null:
		nl.add_theme_font_override("font", f)
	nl.add_theme_font_size_override("font_size", 18)
	nl.add_theme_color_override("font_color", Color(0.24, 0.16, 0.08))
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.size = Vector2(COL_W, 60.0)
	nl.position = _pg(300.0, y)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(nl)

## 수량판 ◀ N ▶ — 원작 :14871.
##   · 수량판  `RoundedLayer::create(100.0, 60.0, 0x66000000, 1, 0)` @ (150, 70)
##             안에 `CCLabelBMFont(getFontName_subtitle)` scale 1.2 를 가운데
##   · 감소    `common/btn_arrow1` scale 1.05, 수량판 **왼쪽 바깥** (minX − w/2 − 10, 70)
##   · 증가    `common/btn_arrow2`, 오른쪽 바깥 (maxX + w/2 + 10, 70)
##   · 표시 조건(:14868) = showQty && 장비 아님 && `getPriceType != 6`
##     → 우리는 호출부가 `max` 로 판단한다(장비 = max 1).
func _detail_qty(panel: Control, maxn: int, count: Array, step: Callable, S: float) -> void:
	const BOX := Vector2(100.0, 60.0)
	var box := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0x66 / 255.0)     # 원작 0x66000000 = 40%
	sb.set_corner_radius_all(10)
	box.add_theme_stylebox_override("panel", sb)
	box.size = BOX
	box.position = _pg(150.0, 70.0) - BOX * 0.5
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	var num := Label.new()
	num.text = "1"
	# 원작은 이 숫자를 getFontName_subtitle BMFont scale 1.2 로 낸다 — 우리도 그 폰트를 쓴다
	# (CLAUDE.md §10 'unicode=0' 정정, scripts/tools/build_fonts.py).
	var f := _orig_font()
	if f != null:
		num.add_theme_font_override("font", f)
	num.add_theme_font_size_override("font_size", 24)
	num.add_theme_color_override("font_color", Color.WHITE)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.size = BOX
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(num)

	# 화살표는 총액뿐 아니라 이 숫자도 갱신해야 한다 — step 을 감싼다.
	var bump := func(d: int):
		step.call(d)
		num.text = str(int(count[0]))
	# 원작: 수량판 바깥으로 (화살표폭/2 + 10) 만큼.
	var aw: float = float(_man("common_ui").get("common_btn_arrow1", {}).get("w", 26)) * S * 1.05
	_arrow_button(panel, "common_btn_arrow1", _pg(150.0 - BOX.x * 0.5 - aw * 0.5 - 10.0, 70.0),
		bump, -1)
	_arrow_button(panel, "common_btn_arrow2", _pg(150.0 + BOX.x * 0.5 + aw * 0.5 + 10.0, 70.0),
		bump, 1)

	# 🟠 원작에 없는 우리 추가 — 99개를 연타로 맞추긴 번거롭다. 한도 게이지가 있던 자리
	# (150, 109)는 비워 두고(§미이식) ▶ 오른쪽 빈 칸에 둔다.
	var maxb := Button.new()
	maxb.text = "MAX"
	maxb.size = Vector2(56, 30)
	maxb.position = _pg(150.0 + BOX.x * 0.5 + aw + 40.0, 70.0) - Vector2(28, 15)
	maxb.add_theme_font_size_override("font_size", 15)
	maxb.pressed.connect(func(): bump.call(maxn))
	panel.add_child(maxb)

## 실행 버튼 — 원작 :14533 `RoundedButton(type 0 = 9patch/btn, 270×56, scale 1.1)` @ (450,70).
## 버튼 안: 재화 아이콘 앵커(1,.5) @ x=55 · 총액 앵커(0,.5) @ x=55 · 문구 앵커(1,.5) @ 폭−20.
func _detail_action(panel: Control, cfg: Dictionary, total: Label, price: int, cur: String,
		count: Array, S: float, on_ok: Callable) -> void:
	const BTN := Vector2(270.0, 56.0)
	var root := Control.new()
	root.size = BTN
	root.position = _pg(450.0, 70.0) - BTN * 0.5
	panel.add_child(root)
	# 원작 RoundedButtonType 0 = `9patch/btn`(RoundedButton.c:147), capInsets(20,20,4,4).
	var frame := _nine("9patch_btn", BTN, Rect2(20, 20, 4, 4))
	if frame != null:
		root.add_child(frame)

	var f := _orig_font()
	if price > 0:
		var ci := _currency_icon(cur)
		if ci != null:
			var sp := Sprite2D.new()
			sp.texture = ci
			sp.material = _pma
			# 원작은 재화 아이콘을 원본 크기로 쓰지만, 정기(ele_*)는 일반 아이템 아이콘이라
			# 그대로 두면 버튼을 덮는다 — `common/coin_small1`(28px) 기준으로 맞춘다.
			var cs: float = 34.0 / maxf(1.0, float(maxi(ci.get_width(), ci.get_height())))
			sp.scale = Vector2(cs, cs)
			sp.position = Vector2(55.0 - ci.get_width() * cs * 0.5, BTN.y * 0.5)
			root.add_child(sp)
		total.text = _comma(price * int(count[0]))
		if f != null:
			total.add_theme_font_override("font", f)
		total.add_theme_font_size_override("font_size", 18)
		total.add_theme_color_override("font_color", Color.WHITE)
		total.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		total.size = Vector2(120, BTN.y)
		total.position = Vector2(58.0, 2.0)
		total.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		# 가격 없는 팝업이라도 수량 콜백이 이 라벨을 만지므로 숨겨서 트리에 붙인다
		# (안 붙이면 고아 노드로 남고, free 하면 콜백이 죽은 객체를 건드린다).
		total.visible = false
	root.add_child(total)

	var word := Label.new()
	word.text = String(cfg.get("action", "확인"))
	if f != null:
		word.add_theme_font_override("font", f)
	word.add_theme_font_size_override("font_size", 20)
	word.add_theme_color_override("font_color", Color.WHITE)
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	word.size = Vector2(110, BTN.y)
	word.position = Vector2(BTN.x - 20.0 - 110.0, 2.0)
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(word)

	var b := Button.new()
	b.flat = true
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	b.size = BTN
	b.pressed.connect(on_ok)
	root.add_child(b)

## ◀ / ▶ 버튼 하나. 원작 `setLongSelected(true)` + `setScheduleTimer(0.2, 0.025)`
## = 꾹 누르면 0.2초 뒤부터 0.025초 간격 연타. 그대로 옮긴다.
func _arrow_button(win: Control, frame: String, center: Vector2, step: Callable, d: int) -> void:
	const HOLD_DELAY := 0.2
	const HOLD_TICK := 0.025
	var t := _tex("common_ui", frame)
	var size := Vector2(44, 44)
	if t != null:
		var s := Sprite2D.new()
		s.texture = t
		s.material = _pma
		var sc := Design.ASSET_SCALE * 1.05      # 원작 createWithSpriteFrameName(…, 1.05)
		s.scale = Vector2(sc, sc)
		s.position = center
		win.add_child(s)
		size = Vector2(t.get_width(), t.get_height()) * sc
	var b := Button.new()
	b.flat = true
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	b.size = size
	b.position = center - size * 0.5
	win.add_child(b)
	var held := [false]
	b.button_down.connect(func():
		step.call(d)
		held[0] = true
		# 원작 스케줄러와 같은 타이밍. 버튼이 사라지면(팝업 닫힘) 루프도 끝난다.
		await get_tree().create_timer(HOLD_DELAY).timeout
		while held[0] and is_instance_valid(b):
			step.call(d)
			await get_tree().create_timer(HOLD_TICK).timeout)
	b.button_up.connect(func(): held[0] = false)
	b.mouse_exited.connect(func(): held[0] = false)

## 원작 BMFont(한글 포함). 비트맵이라 fixed_size_scale_mode 를 켜야 font_size 가 먹는다.
var _orig_font_cache: Font = null
func _orig_font() -> Font:
	if _orig_font_cache != null:
		return _orig_font_cache
	var p := "res://assets/converted/font_ui/font_subtitle.fnt"
	if not ResourceLoader.exists(p):
		return null
	var f := (load(p) as FontFile)
	if f == null:
		return null
	f = f.duplicate() as FontFile
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	_orig_font_cache = f
	return f

## 뽑기 결과 공개 — 원작 `Gacha_Box_Popup.c:533` 이 `ShowGetItemDetailLayer` 를 띄우는 자리.
## 여러 개면 원작대로 **원형 배치**로 한 번에 보여준다(마지막 항목이 중앙·크게 → 주 획득물을
## 배열 끝에 둔다). 대사창 안내는 원작 setText 경로라 함께 남긴다.
func _show_result(keys: Array) -> void:
	if keys.is_empty():
		_toast("아무것도 나오지 않았습니다.")
		return
	var names: Array = []
	var entries: Array = []
	for k in keys:
		names.append(Drops.display_name(String(k), Data.gems, Data.equipment))
		entries.append({"key": String(k), "count": 1})
	_toast("획득: " + ", ".join(names))
	GetItemPopup.open(self, entries)

## NPC 대사창을 그대로 안내판으로 쓴다(원작 setText → BottomTextBox::setString).
func _toast(msg: String) -> void:
	if is_instance_valid(_box):
		_box.show_text(_npc_display_name(String(_cur().get("npc", ""))), msg)
		if is_instance_valid(_npc):
			_npc.set_talking(true)

# ── 나가기 ───────────────────────────────────────────────────────────────
## 원작 ShopScene 의 유일한 퇴장 경로는 TitleLayer 의 X(`onClickClose`) 다 —
## 별도의 "← 마을" 버튼을 두지 않는다(대사창을 가려서 원작과도 어긋났다).
func _close() -> void:
	var from := String(_params.get("from", "town"))
	if from == "worldmap":
		Scenes.goto("worldmap", {"region": "yutakan"})
	else:
		Scenes.goto("town", {"area": _params.get("area", "elpis")})

# ── 에셋 유틸 ────────────────────────────────────────────────────────────
func _man(dir: String) -> Dictionary:
	if _mans.has(dir):
		return _mans[dir]
	var p := "res://assets/converted/%s/_manifest.json" % dir
	var d := {}
	if FileAccess.file_exists(p):
		var f := FileAccess.open(p, FileAccess.READ)
		var j = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			d = j
	_mans[dir] = d
	return d

func _tex(dir: String, key: String) -> Texture2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	return load(p) if ResourceLoader.exists(p) else null

func _spr(dir: String, key: String, scale := 1.0) -> Sprite2D:
	var t := _tex(dir, key)
	if t == null:
		return null
	var s := Sprite2D.new()
	s.texture = t
	s.material = _pma
	s.scale = Vector2(scale, scale)
	return s

## 원작 `CCScale9Sprite::createWithSpriteFrameName(frame, capInsets)` 대응.
##
## ⚠️ 단위 함정: Cocos capInsets 는 **포인트**(=화면 좌표)이고, Godot NinePatchRect 의
##   patch_margin 은 **텍스처 픽셀**이다. 원작 리소스는 픽셀→포인트가 ×4/3 이므로
##   (CLAUDE.md §9) 픽셀 여백 = 포인트 여백 × 0.75 로 환산해야 한다.
##   예) `9patch/shop_box_top` 60×42px, capInsets(40,40,4,4)pt
##       → L=30 T=30 중앙 3×3, R=60-30-3=27, B=42-30-3=9  (합이 프레임 크기와 정확히 맞는다)
##   포인트로 곧이곧대로 넣으면 R/B 가 음수가 되어 테두리가 뭉개진다.
##
## 그리고 텍스처 픽셀 1개는 디자인공간에서 4/3 포인트로 보여야 하므로,
##   node.scale = ASSET_SCALE, node.size = 원하는 포인트 크기 / ASSET_SCALE 로 둔다.
func _nine(key: String, sz_pt: Vector2, cap: Rect2, dir := "ninepatch_ui") -> NinePatchRect:
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	if not ResourceLoader.exists(p):
		return null
	var tex: Texture2D = load(p)
	var inv := 1.0 / Design.ASSET_SCALE            # 포인트 → 텍스처 픽셀 (=0.75)
	var l := cap.position.x * inv
	var t := cap.position.y * inv
	var cwid := cap.size.x * inv
	var chei := cap.size.y * inv
	if cap.size == Vector2.ZERO:
		# capInsets 를 안 준 원작 호출 = Cocos 기본값(가로·세로 1/3 분할).
		l = tex.get_width() / 3.0
		t = tex.get_height() / 3.0
		cwid = tex.get_width() / 3.0
		chei = tex.get_height() / 3.0
	var np := NinePatchRect.new()
	np.texture = tex
	np.patch_margin_left = int(round(l))
	np.patch_margin_top = int(round(t))
	np.patch_margin_right = int(round(maxf(0.0, tex.get_width() - l - cwid)))
	np.patch_margin_bottom = int(round(maxf(0.0, tex.get_height() - t - chei)))
	np.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	np.size = sz_pt * inv
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 🔴 2026-07-30: 변환 아틀라스는 **프리멀티플라이드 알파**다(§4 파이프라인). Sprite2D 는
	# `_spr` 에서 `_pma` 를 달아 왔는데 NinePatchRect 에는 안 달려 있어서, 알파 그라데이션이
	# 있는 프레임(`9patch/pop_title_bg` 는 양끝이 alpha 8까지 페이드)이 **검게** 합성됐다.
	# 증상 = 제목바 왼쪽 끝의 회색 띠.
	np.material = _pma
	return np

## 천 단위 콤마(원작 Util::util_add_comma_to_num).
func _comma(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out

func _vis() -> Vector2:
	return get_viewport_rect().size
