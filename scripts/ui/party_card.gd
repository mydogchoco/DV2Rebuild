class_name PartyCardView
extends RefCounted

## 탐험 하단 **파티 카드**(원작 `AdventureScene::setInterfaceDragon` → `InterFace::UI_InterFace`)의
## 정적 렌더러. 조우·선택지·보상 구간에서 읽기 전용으로 그린다.
##
## 원작에서 이 카드는 탐험과 전투가 **같은 씬**이라 하나로 이어진다 —
## 레퍼런스 `docs/ref/adventure/4_전투시작.png`(탐험 시작) · `전투4.png`(싸운다/도망간다 선택) ·
## `승리9.png`(계속하기/그만하기) 가 전부 같은 카드다. 배회(전진 애니) 중에만 숨는다
## (`setAllHideUiButton` / `setAllUiButton`, 레퍼런스 `배회1~5.png` 에 카드가 없다).
##
## ⚠️ 전투 중 HP 가 **깎이는** 애니메이션 버전은 `scripts/ui/battle.gd::_party_card` 에 따로 있다
##   (게이지 트윈·데미지 숫자·사망 처리용 노드 참조를 들고 있어야 해서 정적화가 안 된다).
##   **좌표·프레임 규약은 둘이 같아야 한다** — 아래 원작 근거를 둘 다 따른다.
##   숫자(능력치)는 `PartyStats`(logic) 한 곳에서 나오므로 두 화면이 어긋나지 않는다.
##
## 원작 근거 — `docs/ref/orig_code/decomp/AdventureScene.c:50024-50110` (배치):
##   1번째 = VisibleRect::leftBottom()  + (20, 128)
##   2번째 = VisibleRect::bottom()      + (-cardW*0.5, 128)      ← 화면 하단 중앙
##   3번째 = VisibleRect::rightBottom() + (-20 - cardW, 128)
##   z=400, tag 0xbc0/1/2.
## `docs/ref/orig_code/decomp/InterFace.c:238-243, 745-1010` (카드 내부):
##   backSprite = `scene/adventure/stat_box3_bg`(136×21) 앵커(0,0),
##     자식으로 카드 아트 `scene/adventure/stat_box3`(220×79) 앵커(0,0) @(0,0) z=2 tag=100.
##   · profile_bg  @ (50, h*0.5+3)
##   · 레벨 BMFont(subtitle, scale 0.75) 앵커(0,0) @ (profile_bg.x+40, h*0.5+22)
##   · 이름 TTF 17 #353535, 레벨 라벨 오른쪽
##   · HP게이지 Scale9 hp_bar10 contentSize(177,30) @ (97, 40)
##   · att_icon-hd 앵커(0,1) scale0.9 @ (w*0.5-50, h*0.5-19) / def_icon-hd @ (w*0.5+30, ")
## ⚠️ 원작 리터럴(50/40/22/97/30/-50/-19…)은 **이미 포인트 단위** → ASSET_SCALE 을 곱하지 않는다(§9-2).
##    스프라이트 "그림 크기"만 ASSET_SCALE 배로 커진다.

const HP_BAR := "res://assets/converted/battle_extra/hp_bar10.png"
const BMF_SUBTITLE := "res://assets/converted/font_ui/font_subtitle.fnt"


## 파티 카드 3장을 `host` 아래 `parent` 에 그린다. 반환 = 만든 카드 Control 배열.
##
## `party` = `PartyStats.summary()` 결과 · `vis` = 가시영역 크기.
static func build_row(host: Node, parent: Node, party: Array, vis: Vector2,
		pma: CanvasItemMaterial) -> Array:
	if party.is_empty():
		return []
	var adv := _man("adventure_ui")
	var S := Design.ASSET_SCALE
	var cw := float((adv.get("scene_adventure_stat_box3", {}) as Dictionary).get("w", 220)) * S
	var ch := float((adv.get("scene_adventure_stat_box3", {}) as Dictionary).get("h", 79)) * S
	# Cocos y=128 = 카드 좌하단 → Godot 좌상단 y = 화면높이 − 128 − ch.
	var card_y := vis.y - 128.0 - ch
	var xs: Array[float] = []
	match party.size():
		1: xs = [20.0]
		2: xs = [20.0, vis.x * 0.5 - cw * 0.5]
		_: xs = [20.0, vis.x * 0.5 - cw * 0.5, vis.x - 20.0 - cw]
	var out: Array = []
	for i in party.size():
		out.append(_card(parent, i, party[i], xs[mini(i, xs.size() - 1)], card_y, cw, ch, adv, pma))
	return out


static func _card(parent: Node, idx: int, pd: Dictionary, x: float, y: float,
		w: float, ch: float, adv: Dictionary, pma: CanvasItemMaterial) -> Control:
	var S := Design.ASSET_SCALE
	var card := Control.new()
	card.set_meta("party_card", true)
	card.position = Vector2(x, y)
	card.size = Vector2(w, ch)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(card)
	# Cocos(y-up, 원점=카드 좌하단) → Godot(y-down, 원점=카드 좌상단): gy = ch − cy.
	var C := func(cx: float, cy: float) -> Vector2: return Vector2(cx, ch - cy)
	var bg := _spr("adventure_ui", "scene_adventure_stat_box3", S, pma)
	if bg:
		bg.position = Vector2(w * 0.5, ch * 0.5); card.add_child(bg)
	# 슬롯별 테두리 프레임(stat_box_frame1/2/3, 227×85).
	var frame := _spr("adventure_ui", "scene_adventure_stat_box_frame%d" % (idx % 3 + 1), S, pma)
	if frame:
		frame.position = Vector2(w * 0.5, ch * 0.5); card.add_child(frame)
	# 초상 — 원작 profile_bg @ (50, h*0.5+3), 앵커 중앙.
	var ppos: Vector2 = C.call(50.0, ch * 0.5 + 3.0)
	var pbg := _spr("common_ui", "common_profile_bg", S, pma)
	if pbg:
		pbg.position = ppos; card.add_child(pbg)
	# 초상(box 이미지) — 원작 setScale(0x3f2147ae = 0.63), InterFace.c:535.
	var id := int(pd.get("id", 0))
	var stage := Growth.stage_for_level(int(pd.get("level", 1)))
	var por := _spr("portrait_%d" % id, "dragon_dragon_%d_box_%s" % [id, stage], 0.63 * S, pma)
	if por:
		por.position = ppos; card.add_child(por)
	# 레벨 — BMFont(subtitle, 0.75) 앵커(0,0) @ (profile_bg.x+40, h*0.5+22).
	# "레벨" 접두는 원작도 같은 폰트지만 우리 카드는 battle.gd 와 동일하게 TTF+BMFont 조합을 쓴다.
	var lv_org: Vector2 = C.call(ppos.x + 40.0, ch * 0.5 + 22.0) - Vector2(0, 22.0)
	var lvk := Label.new()
	lvk.text = "레벨"
	lvk.add_theme_font_size_override("font_size", 15)
	lvk.add_theme_color_override("font_color", Color8(0x35, 0x35, 0x35))
	lvk.position = lv_org + Vector2(0, 4.0)
	card.add_child(lvk)
	var lv := _bmf(0.75 * S)
	lv.text = "%d" % int(pd.get("level", 1))
	lv.add_theme_color_override("font_color", Color8(0x35, 0x35, 0x35))
	lv.position = lv_org + Vector2(32.0, 0.0)
	card.add_child(lv)
	# 이름 TTF 17 #353535 — 레벨 라벨 오른쪽.
	var nm := Label.new()
	nm.text = String(pd.get("name", ""))
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", Color8(0x35, 0x35, 0x35))
	nm.position = lv_org + Vector2(66.0, 3.0)
	card.add_child(nm)
	# HP 게이지 — Scale9 hp_bar10 contentSize(177,30) 앵커(0,0) @ (97,40).
	var bar_w := 177.0
	var bar_h := 30.0
	var bar_org: Vector2 = C.call(97.0, 40.0 + bar_h)
	var hbg := _spr("adventure_ui", "scene_adventure_stat_box3_bg", S, pma)
	if hbg:
		hbg.position = bar_org + Vector2(bar_w * 0.5, bar_h * 0.5)
		card.add_child(hbg)
	var hp_max := maxi(1, int(pd.get("hp_max", 1)))
	var hp_now := clampi(int(pd.get("hp", hp_max)), 0, hp_max)
	var fill_w := (bar_w - 10.0) * (float(hp_now) / float(hp_max))
	if fill_w > 0.0:
		var hfl := NinePatchRect.new()
		if ResourceLoader.exists(HP_BAR):
			hfl.texture = load(HP_BAR)
		hfl.patch_margin_left = 8; hfl.patch_margin_right = 8
		hfl.patch_margin_top = 3; hfl.patch_margin_bottom = 3
		hfl.size = Vector2(fill_w, bar_h - 14.0)
		hfl.position = bar_org + Vector2(5.0, 7.0)
		hfl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(hfl)
	var hp := _bmf(0.8 * S)
	hp.text = "%d / %d" % [hp_now, hp_max]
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp.size = Vector2(bar_w, bar_h); hp.position = bar_org
	card.add_child(hp)
	# 공/방 — att @ (w*0.5-50, h*0.5-19), def @ (w*0.5+30, h*0.5-19), 앵커(0,1).
	var stats: Dictionary = pd.get("stats", {})
	var ay := ch * 0.5 - 19.0
	_stat_icon(card, "scene_adventure_att_icon-hd", int(stats.get("att", 0)),
		C.call(w * 0.5 - 50.0, ay), S, adv, pma)
	_stat_icon(card, "scene_adventure_def_icon-hd", int(stats.get("def", 0)),
		C.call(w * 0.5 + 30.0, ay), S, adv, pma)
	return card


# ---------- 회복 물약 버튼 (원작 InterFace::setUiButton + setUiButtonInfo) ----------
#
# 레퍼런스 `docs/ref/adventure/전투4.png` · `전투5.png` · `승리9/10.png`:
#   카드 **위쪽**에 초록 십자 + 분홍 물약잔 + `x31`(보유 수량)이 떠 있다.
#
# 원작 근거(디컴프 리터럴):
#   · `InterFace::setUiButton` @00d3dec8 — `common/box.png` 로 `CCMenuItemImageEx::create(…,1.05)`,
#     앵커 **(0.5, 0.0)**, 위치 **(cardW*0.17, cardH)** ⇒ 버튼 아랫변이 카드 윗변에 붙고
#     x 는 카드 폭의 17% 지점. 등장 = ScaleTo(0.3,1.7)+MoveTo(0.3,(0,h)) → ScaleTo(0.5,1.5)+MoveTo(0.5,(0,−h)).
#   · `InterFace::setUiButtonInfo` @00d3d500 — 아이콘 `scene/adventure/icon_greencross.png`(회복) /
#     `scene/adventure/icon_resurrection.png`(**사망 시 부활**) / `common/diamond_small2.png`(다이아 표기),
#     메인 아이콘 @(w*0.5, h*0.5), 배지 @(w*0.2, h*0.8), 수량 라벨 @(iconW*1.1+25, 25) 앵커(0,0.4).
#   · 사용 연출 `InterFace::setRecoverItemHeal` @00d3eb88 —
#     `particle/scene/adventure/skill_29.plist` + `music/effect_skill_29.mp3` + HP바 ScaleTo(0.1).
#
# ⚠️ 원작의 다이아 결제 갈래(`onClickHealByCash`/`setReviveCashEvent`)는 §2-1(결제 삭제)라 ⚫CUT —
#    보유 물약으로만 회복한다. 그래서 `diamond_small2` 는 쓰지 않는다.
const CURE_PARTICLE := "particle/scene/adventure/skill_29.plist"

## 카드 위 회복 버튼 1개. `count` = 보유 수량(0이면 회색). `on_pressed` = 눌렀을 때.
## 반환 = 버튼 루트(수량 갱신용으로 `count_label` 메타를 달아 둔다).
static func build_cure_button(card: Control, potion_key: String, count: int, dead: bool,
		pma: CanvasItemMaterial, on_pressed: Callable) -> Control:
	var S := Design.ASSET_SCALE
	var adv := _man("adventure_ui")
	var w := card.size.x
	var btn := Control.new()
	btn.set_meta("cure_button", true)
	# 원작 앵커(0.5,0.0) @ (w*0.17, cardH) — 카드 좌표계에서 버튼 아랫변이 카드 윗변에 닿는다.
	var bw := 92.0
	var bh := 56.0
	btn.size = Vector2(bw, bh)
	btn.position = Vector2(w * 0.17 - bw * 0.5, -bh)
	card.add_child(btn)
	# 버튼 배경 — 원작 common/box.png(CCMenuItemImageEx). 레퍼런스에선 배경이 거의 안 보일 만큼
	# 옅어서 눈에 띄지 않는다 → 원본 프레임 그대로 쓰되 확대는 하지 않는다.
	var box := _spr("common_ui", "common_box", 0.7 * S, pma)
	if box:
		box.position = Vector2(bw * 0.5, bh * 0.5)
		box.modulate.a = 0.55
		btn.add_child(box)
	# 메인 아이콘 — 사망이면 부활(icon_resurrection), 아니면 회복(icon_greencross).
	var ikey := "scene_adventure_icon_resurrection" if dead else "scene_adventure_icon_greencross"
	var ic := _spr("adventure_ui", ikey, 0.75 * S, pma)
	if ic:
		# 원작 배지 위치 @(w*0.2, h*0.8) — 좌상단.
		ic.position = Vector2(bw * 0.22, bh * 0.28)
		btn.add_child(ic)
	# 물약 아이콘 — 우리 인벤의 실제 아이템 아이콘(item/food/heal_potion1~3).
	var pot := _spr("item_food", "item_food_%s" % potion_key, 0.42 * S, pma)
	if pot:
		pot.position = Vector2(bw * 0.5, bh * 0.62)
		btn.add_child(pot)
	# 수량 `x<N>` — 원작 라벨 @(iconW*1.1+25, 25) 앵커(0,0.4).
	var cl := Label.new()
	cl.text = "x%d" % count
	cl.add_theme_font_size_override("font_size", 17)
	cl.add_theme_color_override("font_color", Color(1, 1, 1))
	cl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	cl.add_theme_constant_override("outline_size", 4)
	cl.position = Vector2(bw * 0.72, bh * 0.42)
	cl.size = Vector2(46, 22)
	cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	btn.add_child(cl)
	btn.set_meta("count_label", cl)
	if count <= 0:
		btn.modulate = Color(0.55, 0.55, 0.55, 0.85)
	var hit := Button.new()
	hit.flat = true
	hit.size = Vector2(bw, bh)
	hit.disabled = count <= 0
	hit.pressed.connect(on_pressed)
	btn.add_child(hit)
	# 등장 — 원작 ScaleTo/MoveTo 2단을 축약(아래에서 튀어오르며 커진다).
	btn.pivot_offset = Vector2(bw * 0.5, bh)
	btn.scale = Vector2(0.6, 0.6)
	var tw := btn.create_tween()
	tw.tween_property(btn, "scale", Vector2(1.08, 1.08), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "scale", Vector2.ONE, 0.15)
	return btn


static func _stat_icon(parent: Control, frame: String, value: int, gpos: Vector2,
		s: float, adv: Dictionary, pma: CanvasItemMaterial) -> void:
	var info: Dictionary = adv.get(frame, {})
	var iw := float(info.get("w", 21)) * 0.9 * s
	var ih := float(info.get("h", 21)) * 0.9 * s
	var ic := _spr("adventure_ui", frame, 0.9 * s, pma)
	if ic:
		ic.position = gpos + Vector2(iw * 0.5, ih * 0.5)
		parent.add_child(ic)
	var lb := _bmf(0.6 * s)
	lb.text = str(value)
	lb.position = gpos + Vector2(iw + 2.0, -1.0)
	lb.size = Vector2(80, ih + 6.0)
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(lb)


static var _bmf_cache: Font = null

static func _bmf(scale := 1.0) -> Label:
	var l := Label.new()
	if _bmf_cache == null and ResourceLoader.exists(BMF_SUBTITLE):
		_bmf_cache = load(BMF_SUBTITLE)
	if _bmf_cache:
		l.add_theme_font_override("font", _bmf_cache)
		var base: float = float(_bmf_cache.fixed_size) if _bmf_cache.fixed_size > 0 else 32.0
		l.add_theme_font_size_override("font_size", int(round(base * scale)))
	else:
		l.add_theme_font_size_override("font_size", int(round(24.0 * scale)))
		l.add_theme_color_override("font_color", Color.WHITE)
	return l


static func _man(dir: String) -> Dictionary:
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


static func _spr(dir: String, name: String, scale: float, pma: CanvasItemMaterial) -> Sprite2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if not ResourceLoader.exists(p):
		return null
	var s := Sprite2D.new()
	s.texture = load(p)
	s.material = pma
	s.scale = Vector2(scale, scale)
	return s
