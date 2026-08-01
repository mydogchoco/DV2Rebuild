extends Object
## 원작 탐험 이벤트 워드아트 — `AdventureScene::setEventHealArea` · `setEventTreasure` ·
## `setEventReward` 가 전부 **같은 안무**를 쓴다(디컴프 리터럴):
##   `CCLabelBMFont::create(text, getFontName_title(), -1.0)` @ (w*0.5, h*0.7)
##   ScaleTo(0.4, 1.7) ∥ [RotateBy(0.2, 380°) → RotateBy(0.1333, −30) → RotateBy(0.1333, 15)]
##   → RotateBy(0.1333, −5) → ScaleTo(0.1, 1.2) → (0.7 대기) → MoveBy(0.2, (0, +100|60))
## 탐험(회복샘)과 전투 보상 페이즈가 씬이 갈려 있어도 숫자가 어긋나지 않도록 여기 한 곳에 둔다
## (party_card.gd 와 같은 추출 이유 — docs/ref/porting/AdventureScene.md §3).
##
## ⚠️ 검은 오버레이(CCLayerColor FadeTo(0.5, 200), tag 0x75)는 **호출측**이 관리한다 —
##   원작도 레이어는 이벤트 수명, 워드아트는 페이즈 수명으로 서로 다르다.
##   (종전 `adventure.gd::_wordart_burst` 의 **흰색 플래시는 자작 오류**였다 — 원작은 검은 막이다.)
class_name WordArt

## 안무 총 길이(초): 0.4 + 0.13333×3 + 0.1 + 0.7 + 0.2 = 1.8999…
const SECS := 1.9
const FONT := "res://assets/converted/font_ui/font_title.fnt"

## 워드아트 라벨을 만들어 안무를 걸고 돌려준다(정리는 호출측 몫 — 페이즈/이벤트와 함께 지운다).
## rise = 0.7초 대기 후 위로 오르는 픽셀(원작 100, 골드/다이아 페이즈만 60).
## fade_out = 오른 뒤 사라질지(회복샘처럼 이벤트 막이 따로 없을 때만 true).
static func burst(host: Node, text: String, vis: Vector2, z := 195,
		rise := 100.0, fade_out := false) -> Label:
	var lb := Label.new()
	lb.text = text
	if ResourceLoader.exists(FONT):
		var fnt: FontFile = load(FONT)
		lb.add_theme_font_override("font", fnt)
		# 비트맵 폰트라 fixed_size_scale_mode 없이는 font_size 가 안 먹는다(CLAUDE.md §10 표).
		lb.add_theme_font_size_override("font_size",
			int(fnt.fixed_size) if fnt.fixed_size > 0 else 39)
	else:
		lb.add_theme_font_size_override("font_size", 34)
		lb.add_theme_color_override("font_color", Color(1, 0.9, 0.45))
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.size = Vector2(vis.x, 60)
	# 원작 @(w*0.5, h*0.7) — Cocos y-up 이므로 Godot y = vis.y*(1−0.7).
	lb.position = Vector2(0, vis.y * 0.3 - 30.0)
	lb.pivot_offset = Vector2(vis.x * 0.5, 30.0)
	lb.z_index = z
	lb.scale = Vector2.ZERO
	host.add_child(lb)
	var t := lb.create_tween()
	t.tween_property(lb, "scale", Vector2(1.7, 1.7), 0.4)
	t.parallel().tween_property(lb, "rotation_degrees", 380.0, 0.2)
	t.tween_property(lb, "rotation_degrees", -30.0, 0.13333334)
	t.tween_property(lb, "rotation_degrees", 15.0, 0.13333334)
	t.tween_property(lb, "rotation_degrees", -5.0, 0.13333334)
	t.tween_property(lb, "scale", Vector2(1.2, 1.2), 0.1)
	t.parallel().tween_property(lb, "rotation_degrees", 0.0, 0.1)
	t.tween_interval(0.7)
	t.tween_property(lb, "position", lb.position - Vector2(0, rise), 0.2)
	if fade_out:
		t.parallel().tween_property(lb, "modulate:a", 0.0, 0.2)
		t.tween_callback(lb.queue_free)
	return lb
