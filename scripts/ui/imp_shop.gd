extends Control
## 임프상인 — 원작 `ImpShopScene` 이식. render 층(§8).
##
## ## 원작 구조와 우리가 남긴 것
## `docs/ref/orig_code/decomp/ImpShopScene.c`(5,401줄, `[skip>` 없음).
## 서버 랭킹 + 클라 상점이 **한 씬에 섞여** 있었다:
##   · 클라(살아 있음) `initWidget` `setSeller*` `setTreasureView` `showItem`/`showItemBuy`/
##     `onClickItemBuy`/`CallbackItemBuy` `onClickTab`/`setCurrentView` `tableCellAtIndex`
##   · 서버(유실)     `requestRankCave`/`responseRankCave` `onClickRanker` `requestShopInfo`
##     API `game_treasure/get_treasurehunter_data.hb` · `game_social/visit_cave.hb`
##     JSON `my_rank` `my_week_rank` `treasure_total_rank` `treasure_week_rank` `week_reward`
## ⚫ **주간 트레저헌터 랭킹은 통째로 CUT**(사용자 확정 2026-07-31, CLAUDE.md §2-1 온라인 삭제).
##    원작이 콜로세움 주간 타이머(`ColosseumWeekReset` + `scene/colosseum/week_time`)를
##    재사용하던 줄도 함께 뺐다. 남긴 것은 **보석 ↔ 장비 교환**뿐이다.
##
## ## 자산
## 보유: `scene/shop/bg_pong`(판매원) · `bt_pong_shop1~4`(탭 on/off) · `npc/pong/body_1` ·
##       `common/item_bg` · `common/backlight3` · `common/btn_info` · `common/back_btn` ·
##       `9patch/box_shadow`
## 🔴 2026-07-31 정정: 처음에 `shop_box_imp` 계열을 "미보유"로 적고 `9patch/popup4`(양피지)로
##    대체했는데 **오진이었다.** `asset_index.py --grep "a\|b"` 가 OR 로 안 먹어 0건이 나온
##    것이고, 실제로는 `shop_ui` 에 전부 변환돼 있다:
##      `scene_shop_shop_box_imp`(71×83) `shop_boxline_imp`(14×10) `shop_box_impBtn1~3`
##      `shop_box_impinfo`(209×161) `scene_shop_bg_pong`(203×141)
##    → 배경은 원작대로 `shop_box_imp` **9-slice**(capInsets 40,40,4,4)다.
##
## ## 규칙
## 화폐 = **보석**(골드 아님 — 원작 `<ShopWelcomeImp7>` "나는 금화 따윈 받지 않아").
## 판정·표는 logic(`ImpShop` + `data/imp_shop.json`). 여기서는 그리고 누르기만 한다(§8.3).

## 원작 `initWidget` 배치(리터럴 그대로):
##   · 목록 패널 = `CCScale9Sprite("scene/shop/shop_box_imp.png", capInsets(40,40,4,4))`
##     rect = (left+30, bottom+135, visW-60-290, visH-108-135)  ← 오른쪽 **290pt** 는 비운다
##   · 그 안쪽에 `CCLayerColor(0xffe8f1f0)` 을 (-44, -63) 만큼 줄여 깐다
##   · 오른쪽 290pt 열 = `setTreasureView` 의 `bg_pong`(보석 보유량) + 판매원 NPC
##   · 하단 = `BottomTextBox`(+ `NpcManager` 로 눈·입·이모티콘)
const NPC_COL := 290.0                  # 오른쪽 비워 두는 열(원작 -290)
const PANEL_MARGIN := 30.0              # 원작 left+30 / right-30
const PANEL_TOP_GAP := 108.0            # 원작 visH-108-…
const PANEL_BOTTOM := 135.0             # 원작 bottom+135 (대사창 자리)
const CELL := Vector2(165.0, 196.0)     # 원작 showItem 의 열 간격 165 + 이름·가격 두 줄

var _pma: CanvasItemMaterial
var _mans: Dictionary = {}
var _params: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _pending_line := ""   # 구매 직후 판매원이 할 말(재빌드 뒤 표시)
var _grid_host: Control   # 스크롤 안쪽 셀 컨테이너

func enter(params: Dictionary = {}) -> void:
	_params = params
	if _pma != null:
		_rebuild()

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_rng.randomize()
	Bgm.play("bg_shop")                 # 원작 상점 BGM(DungeonShopScene.c:1378 과 같은 곡)
	# ⚠️ 오버레이(월드맵 위)로 열릴 때는 딤을 **호스트가** 깐다(원작 CCLayerColor 0x64000000).
	#    여기서 또 깔면 두 번 어두워진다.
	_rebuild()

func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_npc = null
	_box = null
	var vis := _vis()

	# 목록 패널 — 원작 `shop_box_imp` 9-slice. 양피지(popup4)가 아니다.
	var pw := vis.x - PANEL_MARGIN * 2.0 - NPC_COL
	var ph := vis.y - PANEL_TOP_GAP - PANEL_BOTTOM
	var panel := _nine9("scene_shop_shop_box_imp", Vector2(pw, ph), Rect2(40, 40, 4, 4), "shop_ui")
	if panel:
		panel.position = Vector2(PANEL_MARGIN, PANEL_TOP_GAP - 60.0)
		add_child(panel)
		# 원작이 패널 안쪽에 까는 밝은 판(CCLayerColor 0xffe8f1f0 = r240 g241 b232).
		var inner := ColorRect.new()
		inner.color = Color8(240, 241, 232)
		inner.size = Vector2(pw - 44.0, ph - 63.0)
		inner.position = panel.position + Vector2(22.0, 40.0)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(inner)

	_build_grid(vis, Rect2(PANEL_MARGIN + 22.0, PANEL_TOP_GAP - 20.0, pw - 44.0, ph - 63.0))
	_build_treasure_box(vis)
	_build_npc(vis)
	_build_back(vis)

## 보유 보석 창 — 원작 `setTreasureView`: `scene/shop/bg_pong.png` 판 + `common/btn_info` +
## 종류별 `"x%d"`. **오른쪽 열**에 있다(사용자 지적 2026-07-31 — 종전엔 좌상단에 뿌렸다).
func _build_treasure_box(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var cx := vis.x - NPC_COL * 0.5
	var cy := PANEL_TOP_GAP + 20.0
	var box := _spr("shop_ui", "scene_shop_bg_pong", S)
	if box:
		box.position = Vector2(cx, cy)
		add_child(box)
	var info := _spr("common_ui", "common_btn_info", S * 0.8)
	if info:
		info.position = Vector2(cx + 110.0, cy - 76.0)
		add_child(info)
	# 보석 4종을 2×2 로(원작도 한 줄에 2개씩 — `(h*0.5-15)*(i&1)` 오프셋).
	var curs := ImpShop.currencies(Data.imp_shop)
	for i in curs.size():
		var key := String(curs[i])
		var ox := cx - 78.0 + 96.0 * float(i % 2)
		var oy := cy - 36.0 + 62.0 * float(i / 2)
		var ic := _item_icon(key, 0.5)
		if ic:
			ic.position = Vector2(ox, oy)
			add_child(ic)
		var l := Label.new()
		l.text = "x%d" % UserDB.item_count(key)
		l.add_theme_font_size_override("font_size", 17)
		l.add_theme_color_override("font_color", Color.WHITE)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 4)
		l.position = Vector2(ox + 16.0, oy - 12.0)
		l.size = Vector2(70.0, 24.0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)

## 판매원 + 대사창 — 원작 `setSellerShow`(NpcManager::create → setTarget("pong") →
## `setNpcEye`/`setNpcMouse`/`setEmoticon`) + `BottomTextBox::setNpcManager`.
## 인사말은 `setSellerInto` 가 `ShopWelcomeImp%d` 를 세 갈래로 고른다:
##   `(r%3)+7` → 7~9 · `(r&1)+5` → 5·6 · `(r&3)+1` → 1~4
## 어느 갈래인지는 서버 상태(보유 보석/주간 랭킹)로 갈렸다 — 랭킹이 ⚫CUT 이라 1~4 를 쓴다.
var _npc: NpcPortrait
var _box: BottomTextBox
func _build_npc(vis: Vector2) -> void:
	_npc = NpcPortrait.create("pong", _rng.randi_range(1, 4))
	if _npc != null:
		_npc.z_index = 5
		add_child(_npc)
		var bw := _npc.body_width()
		_npc.position = Vector2(vis.x - NPC_COL * 0.5, vis.y)
		# 원작 등장 — 오른쪽에서 밀려 들어온다(EaseBackOut 0.4s).
		var to_x := _npc.position.x
		_npc.position.x = vis.x + bw * 0.5
		var tw := create_tween()
		tw.tween_property(_npc, "position:x", to_x, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_box = BottomTextBox.new()
	_box.max_width = vis.x - NPC_COL      # 대사창은 NPC 열을 침범하지 않는다
	_box.z_index = 12
	add_child(_box)
	# 구매 직후면 그 대사를(원작 `ShopBuyImpPong_%d`), 아니면 인사말(`ShopWelcomeImp%d`).
	if _pending_line != "":
		_say(_pending_line)
		_pending_line = ""
	else:
		_say(_welcome_line())

## 대사 한 줄. 문자열이 없으면 창을 비워 둔다(지어내지 않는다).
func _say(text: String) -> void:
	if is_instance_valid(_box) and text != "":
		_box.show_text(_npc_name(), text)      # 원작 <NPC_pong>임프 퐁

# ⛔ 계열 탭(묘안석/흑요석/백금석)은 **원작에 없다**(사용자 지적 2026-07-31).
#    원작 `onClickTab` 이 갈아 끼우는 `bt_pong_shop2`/`bt_pong_shop4` 버튼은 계열 탭이 아니라
#    `Item::create(0x204)` 처럼 **아이템 아이콘을 단 메뉴**였다(상점/레시피/랭킹 계열).
#    우리는 랭킹을 ⚫CUT 했고 레시피도 없으므로 **한 화면에 18품목 전부** 진열한다.

## 진열 격자 — 원작 `showItem` 셀(`common/item_bg` + `backlight3` + 가격).
## `area` = 목록 패널 안쪽 사각형. 열 수는 폭에서 유도한다(원작도 패널 폭에 맞춰 채운다).
## 원작은 `CCTableView` 라 목록이 **스크롤**된다 — 18품목이 패널을 넘치므로 우리도 스크롤한다.
func _build_grid(_vis: Vector2, area: Rect2) -> void:
	var S := Design.ASSET_SCALE
	var rows := ImpShop.stock(Data.imp_shop)      # 계열 탭 없이 **전부** 한 목록에
	var cols := maxi(1, int(area.size.x / CELL.x))
	var scroll := ScrollContainer.new()
	scroll.position = area.position
	scroll.size = area.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(area.size.x,
		CELL.y * ceilf(float(rows.size()) / float(cols)) + 16.0)
	scroll.add_child(inner)
	_grid_host = inner
	var gx := (area.size.x - CELL.x * float(cols)) * 0.5
	var gy := 8.0
	for i in rows.size():
		var row: Dictionary = rows[i]
		var cx := gx + CELL.x * float(i % cols) + CELL.x * 0.5
		var cy := gy + CELL.y * float(i / cols) + CELL.y * 0.5
		var owned := {String(row["currency"]): UserDB.item_count(String(row["currency"]))}
		var afford := ImpShop.can_buy(row, owned)
		# 원작 showItem 은 셀 **뒤**에 backlight3 를 깐다. 크게 그리면 화면을 덮으므로
		# 셀 크기에 맞춰 줄이고 옅게 둔다(2026-07-31 실측 수정).
		var glow := _spr("common_ui", "common_backlight3", S * 0.42)
		if glow and afford:
			glow.position = Vector2(cx, cy - 14.0)
			glow.modulate = Color(1, 0.95, 0.7, 0.30)
			_grid_host.add_child(glow)
		var cell := _spr("common_ui", "common_item_bg", S)
		if cell:
			cell.position = Vector2(cx, cy - 14.0)
			_grid_host.add_child(cell)
		var ic := _icon_spr(Icons.equip_texture(
			Equipment.catalog(Data.equipment).get(String(row["key"]), {})), 1.0)
		if ic:
			ic.position = Vector2(cx, cy - 14.0)
			_grid_host.add_child(ic)
		var nm := Label.new()
		nm.text = String(row["name"])
		nm.add_theme_font_size_override("font_size", 14)
		nm.add_theme_color_override("font_color", Color.WHITE)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.size = Vector2(CELL.x, 20.0)
		nm.position = Vector2(cx - CELL.x * 0.5, cy + 34.0)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid_host.add_child(nm)
		# 가격 = 보석 아이콘 + 개수(한 종류만 — 사용자 확정).
		var pic := _item_icon(String(row["currency"]), 0.4)
		if pic:
			pic.position = Vector2(cx - 24.0, cy + 68.0)
			_grid_host.add_child(pic)
		var pl := Label.new()
		pl.text = str(int(row["price"]))
		pl.add_theme_font_size_override("font_size", 17)
		pl.add_theme_color_override("font_color", Color(1, 0.9, 0.5) if afford else Color(1, 0.45, 0.4))
		pl.size = Vector2(70.0, 22.0)
		pl.position = Vector2(cx - 8.0, cy + 57.0)
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid_host.add_child(pl)
		var hit := Button.new()
		hit.flat = true
		hit.size = Vector2(CELL.x - 10.0, CELL.y - 10.0)
		hit.position = Vector2(cx - CELL.x * 0.5 + 5.0, cy - CELL.y * 0.5 + 5.0)
		hit.pressed.connect(_confirm_buy.bind(row))
		_grid_host.add_child(hit)

## 원작 `showItemBuy` → `onClickItemBuy` → `CallbackItemBuy`.
func _confirm_buy(row: Dictionary) -> void:
	var cur := String(row["currency"])
	var owned := {cur: UserDB.item_count(cur)}
	var lack := ImpShop.shortfall(row, owned)
	if lack > 0:
		Toast.show(self, "%s이(가) %d개 부족합니다" % [Data.item_name(cur), lack])
		return
	PopupType.open(self, "구매",
		"%s\n\n%s %d개로 교환하시겠습니까?" % [String(row["name"]), Data.item_name(cur), int(row["price"])],
		func(): _do_buy(row))

func _do_buy(row: Dictionary) -> void:
	# 판정은 logic 이 하고(§8.3) 인벤 반영만 여기서.
	var cur := String(row["currency"])
	var res := ImpShop.buy(row, {cur: UserDB.item_count(cur)})
	if not bool(res.get("ok", false)):
		Toast.show(self, String(res.get("reason", "구매할 수 없습니다")))
		return
	if not UserDB.use_item(String(res["spend_key"]), int(res["spend_count"])):
		Toast.show(self, "보석이 부족합니다")
		return
	UserDB.add_item(String(res["give_key"]), 1)
	Bgm.sfx("effect_item_buy")           # 원작 music/effect_item_buy.mp3
	# 원작도 구매 뒤 setSeller 를 다시 불러 판매원을 재등장시키고 구매 대사를 띄운다.
	_pending_line = _buy_line(String(row["name"]))
	_rebuild()

func _build_back(vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var b := TextureButton.new()
	var t := _tex("common_ui", "common_back_btn")
	# 🟦 사용자 지시 2026-07-31: 하단(대사창 밑)이라 잘 안 보였다 → **목록 패널 좌상단**으로.
	#   패널은 `_rebuild` 와 같은 식으로 잡는다(left+30, top).
	var bx := PANEL_MARGIN + 6.0
	var by := PANEL_TOP_GAP - 60.0 + 6.0
	if t:
		b.texture_normal = t
		b.scale = Vector2(S, S)
		b.position = Vector2(bx, by)
	else:
		b.position = Vector2(bx, by)
	b.pressed.connect(func():
		Bgm.sfx("effect_button")
		# 오버레이로 열렸으면 호스트(월드맵)가 닫는다 — 씬을 갈아 끼우지 않는다.
		var cb = _params.get("on_close")
		if cb is Callable and (cb as Callable).is_valid():
			(cb as Callable).call()
			return
		Scenes.goto("worldmap", {"region": _params.get("region", "yutakan"),
			"night": bool(_params.get("night", true))}))
	add_child(b)

## 원작 문자열 — `data/npc_lines.json` `imp_shop`(build_npc_lines.py 가 stringsData_KR.xml 에서
## 뽑는다. 유실이 아니다). welcome = `ShopWelcomeImp1~9`, buy = `ShopBuyImpPong_1~4`.
## ⚠️ 원작 `setSellerInto` 는 랭킹 상태에 따라 7~9 갈래도 썼는데 랭킹이 ⚫CUT 이라 **1~4** 만 쓴다.
func _imp_block() -> Dictionary:
	return Data.npc_lines_doc.get("imp_shop", {})

func _welcome_line() -> String:
	var pool: Array = _imp_block().get("welcome", [])
	if pool.is_empty():
		return ""
	return String(pool[_rng.randi_range(0, mini(3, pool.size() - 1))])

func _buy_line(item_name: String) -> String:
	var pool: Array = _imp_block().get("buy", [])
	if pool.is_empty():
		return ""
	return String(pool[_rng.randi() % pool.size()]).replace("%1$s", item_name)

func _npc_name() -> String:
	return String(_imp_block().get("name", "임프 퐁"))

## 일반 아이템(보석) 아이콘 — `icon_map` 에는 `item` 섹션이 없다. items.json 의 `icon` 경로를 쓴다.
func _item_icon(key: String, scale := 1.0) -> Sprite2D:
	var path := String(Data.item_icon_path(key))
	if path == "" or not ResourceLoader.exists(path):
		return null
	return _icon_spr(load(path), scale)

## 논리키 아이콘 텍스처 → Sprite2D(PMA). 텍스처가 없으면 null 이라 호출부가 건너뛴다.
func _icon_spr(t: Texture2D, scale := 1.0) -> Sprite2D:
	if t == null:
		return null
	var s := Sprite2D.new()
	s.texture = t
	s.material = _pma
	s.scale = Vector2(scale, scale) * Design.ASSET_SCALE
	return s

# ---------- 헬퍼 ----------
func _vis() -> Vector2:
	return get_viewport_rect().size

func _man(dir: String) -> Dictionary:
	if _mans.has(dir):
		return _mans[dir]
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text()) if f else {}
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

func _nine(key: String, sz_pt: Vector2, cap: Rect2) -> NinePatchRect:
	return _nine9(key, sz_pt, cap, "ninepatch_ui")

## 원작 `CCScale9Sprite::createWithSpriteFrameName(frame, capInsets)`.
## capInsets 는 **포인트**, Godot patch_margin 은 **텍스처 픽셀** → ×0.75 환산(§9).
func _nine9(key: String, sz_pt: Vector2, cap: Rect2, dir: String) -> NinePatchRect:
	var p := "res://assets/converted/%s/%s.tres" % [dir, key]
	if not ResourceLoader.exists(p):
		return null
	var tex: Texture2D = load(p)
	var inv := 1.0 / Design.ASSET_SCALE
	var l := tex.get_width() / 3.0
	var t := tex.get_height() / 3.0
	var cw := tex.get_width() / 3.0
	var ch := tex.get_height() / 3.0
	if cap.size != Vector2.ZERO:
		l = cap.position.x * inv; t = cap.position.y * inv
		cw = cap.size.x * inv; ch = cap.size.y * inv
	var np := NinePatchRect.new()
	np.texture = tex
	np.patch_margin_left = int(round(l))
	np.patch_margin_top = int(round(t))
	np.patch_margin_right = int(round(maxf(0.0, tex.get_width() - l - cw)))
	np.patch_margin_bottom = int(round(maxf(0.0, tex.get_height() - t - ch)))
	np.scale = Vector2(Design.ASSET_SCALE, Design.ASSET_SCALE)
	np.size = sz_pt * inv
	np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	np.material = _pma
	return np
