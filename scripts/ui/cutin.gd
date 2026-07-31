class_name DragonCutin
extends RefCounted
## render 층 공용 — 원작 `Cutin` 클래스(드래곤 얼굴 컷인) 재현.
##
## 원래 `battle.gd :: _critical_cutin` 에만 있었는데 레벨업 화면의 **트리플맥스 연출**도
## 같은 컷인을 쓰므로(사용자 확인 2026-07-27) 여기로 뽑아 둘이 공유한다.
## CLAUDE.md §3 "같은 일을 하는 헬퍼가 이미 있는지 grep" — 새로 짜지 말고 이걸 부를 것.

## 원작 `cocos2d::Cutin::show()` 를 그대로 옮긴 것.
## 근거: `docs/ref/orig_code/decomp/Cutin.c:443-845`(이번 세션 디컴파일). 호출 경로는
##   `MakeInterface::showCutIn`(MakeInterface.c:34101) → `Cutin::show(delay, 1.0, bg, face, ..., flip)`.
##   ⇒ 아래 시간값은 param_2 = **1.0** 기준이다: t = param_2*0.1 = **0.1초**, t2 = param_2*0.05 = **0.05초**.
##
## 원작이 세 겹을 동시에 굴린다 — 그냥 이미지 한 장이 아니다:
##  ① 어두운 막 `CCLayerColor` (z=999)
##       Sequence(Delay, FadeTo(0.1, **150**), Delay(param_2*0.4 = 0.4), FadeTo(0.1, 0))
##  ② 스피드라인 밴드 `dragon/cut_in_{속성}/bg_cut{1,2,3}.png`
##       · `CCAnimation` 3프레임 + `CCRepeatForever` — 무한 루프
##       · `Spawn( CCEaseOut(CCScaleTo(0.1, s, s*1.05), 0.25),
##                 Sequence(Delay(0.5), FadeTo(0.05, **100**),
##                          Spawn(FadeTo(0.1, 0), MoveBy(0.1, (-폭, 0)))) )`
##         ⇒ **EaseOut 으로 확 펼쳐지고**(세로만 1.05배 더), 0.5초 뒤 흐려졌다가 옆으로 빠지며 사라진다
##  ③ 드래곤 얼굴 `dragon/dragon_{N}_critical/cut_in.png`
##       시작 위치 `(중앙 + 방향*얼굴폭*0.5, 중앙)` → `Spawn(FadeTo(0.1, 255), MoveTo(0.1, 중앙))`
##       ⇒ 화면 밖에서 **밀고 들어오며 페이드인**. 방향은 `Cutin::show` 의 마지막 bool 인자.
##       원본에 얼굴이 없으면 `dragon/dragon_1_critical/cut_in.png` 로 폴백한다(Cutin.c:699).
## 사운드 `music/effect_cut_in.mp3`(Cutin 생성자 Cutin.c:415).
##
## 밴드 letter 는 race 스위치(`Dragon::getImagePathCutBg`, Dragon.c:8790-8851):
##   0=e 1=a 2=f 3=w 4=l 5=d 6=h 7=c 8=s
const LETTER := {
	"earth": "e", "aqua": "a", "fire": "f", "wind": "w", "light": "l",
	"dark": "d", "holy": "h", "chaos": "c", "shadow": "s",
}
const T := 0.1          # 원작 param_2 * 0.1
const T2 := 0.05        # 원작 param_2 * 0.05
const HOLD := 0.4       # 막 유지 = param_2 * 0.4
const BAND_HOLD := 0.5  # 밴드 퇴장 시작 = param_2 * 0.5
## 컷인이 화면에서 완전히 걷히는 시각(= 레이어 정리 시각).
const TOTAL := T + HOLD + T + 0.05
## 배너 문구의 세로 위치(화면 높이 비율, 위에서부터).
## 원작 `ExpLayer::set3MaxParticle` 의 `CCPoint(…, H*0.7)` 을 y-flip 한 값 = 밴드 위.
const BANNER_Y := 0.3

static func _man(dir: String) -> Dictionary:
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

static func _spr(dir: String, name: String, scale := 1.0) -> Sprite2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if not ResourceLoader.exists(p):
		return null
	var s := Sprite2D.new()
	s.texture = load(p)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	s.material = m
	# 회전 보정 불필요 — 변환 단계가 흡수(scripts/tools/fix_rotated_frames.py)
	s.scale = Vector2(scale, scale)
	return s

## 컷인 재생. caster = {id, element, awakened}. speed = 배속(전투 배속 반영, 1.0 = 등속).
## banner 를 주면 컷인 위에 그 문구를 크게 얹는다(트리플맥스 = 원작 문자열 `tripleMax` "트리플 맥스").
## 반환 = 컷인이 걷히는 데 걸리는 초(호출측이 후속 연출 타이밍을 맞출 때 쓴다).
## ⚠️ 레벨업 트리플맥스는 원작이 `Cutin::show(0, **3.0**, …)` 로 부른다(ExpLayer::set3MaxParticle)
##    = 모든 시간값 ×3 슬로우. 우리 speed 의미로는 1/3 → 하한을 1/3 로 둔다.
static func show(host: Node, caster: Dictionary, speed := 1.0, banner := "", layer_idx := 40) -> float:
	if not is_instance_valid(host) or not host.is_inside_tree():
		return 0.0
	var elem := String(caster.get("element", ""))
	var letter: String = LETTER.get(elem, "f")
	var bdir := "cut_in_%s" % letter
	# ⚠️ `host.get_viewport_rect()` 를 쓰면 안 된다 — 그건 **CanvasItem** 의 메서드다.
	#   호스트는 Control 일 수도(battle.gd), 순수 Node 일 수도(levelup_screen.gd) 있다.
	#   2026-07-31 실제 사고: 레벨업 화면을 cave.gd(Control)에서 별도 파일(extends Node)로
	#   뽑아낸 커밋(6f2cb03) 이후 트리플맥스 컷인이 여기서 조용히 죽었다
	#   ("Nonexistent function 'get_viewport_rect'" — 연출만 사라지고 게임은 계속 굴러갔다).
	#   `get_viewport()` 는 Node 의 메서드라 어느 호스트에서도 같은 값을 준다.
	var vis: Vector2 = host.get_viewport().get_visible_rect().size
	var sp := 1.0 / maxf(1.0 / 3.0, speed)
	var lay := CanvasLayer.new(); lay.layer = layer_idx
	host.add_child(lay)
	var center := vis * 0.5

	# ① 어두운 막
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.size = vis
	dim.z_index = -1
	lay.add_child(dim)
	var dt := dim.create_tween()
	dt.tween_property(dim, "color:a", 150.0 / 255.0, T * sp)
	dt.tween_interval(HOLD * sp)
	dt.tween_property(dim, "color:a", 0.0, T * sp)

	# ② 밴드
	var band := Sprite2D.new()
	var bp := "res://assets/converted/%s/dragon_cut_in_%s_bg_cut1.tres" % [bdir, letter]
	if ResourceLoader.exists(bp):
		band.texture = load(bp)
		band.position = center
		var s := vis.x / 576.0
		band.scale = Vector2.ONE          # 원작도 기본 배율에서 ScaleTo 로 커진다
		lay.add_child(band)
		var frame := 1
		var ticker := Timer.new(); ticker.wait_time = 0.07 * sp; ticker.autostart = true
		ticker.timeout.connect(func():
			frame = frame % 3 + 1
			var fp := "res://assets/converted/%s/dragon_cut_in_%s_bg_cut%d.tres" % [bdir, letter, frame]
			if is_instance_valid(band) and ResourceLoader.exists(fp): band.texture = load(fp))
		lay.add_child(ticker)
		var bs := band.create_tween()
		bs.tween_property(band, "scale", Vector2(s, s * 1.05), T * sp)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var bf := band.create_tween()
		bf.tween_interval(BAND_HOLD * sp)
		bf.tween_property(band, "modulate:a", 100.0 / 255.0, T2 * sp)
		bf.tween_property(band, "modulate:a", 0.0, T * sp)
		bf.parallel().tween_property(band, "position:x", center.x - vis.x, T * sp)

	# ③ 얼굴
	var cid := int(caster.get("id", 0))
	var cman := _man("critical_%d" % cid)
	var key := "dragon_dragon_%d_critical_cut_in" % cid
	if bool(caster.get("awakened", false)):
		var ekey := "dragon_dragon_%d_critical_e_cut_in" % cid
		if cman.has(ekey):
			key = ekey
	var cs := vis.x / 576.0
	var face := _spr("critical_%d" % cid, key, cs)
	if face == null:
		# 원작 폴백(Cutin.c:699) — 얼굴이 없으면 1번 드래곤 것을 쓴다.
		face = _spr("critical_1", "dragon_dragon_1_critical_cut_in", cs)
	if face:
		var fw: float = face.texture.get_width() * cs if face.texture else vis.x * 0.5
		face.position = Vector2(center.x + fw * 0.5, center.y)
		face.modulate.a = 0.0
		face.z_index = 5
		lay.add_child(face)
		var ft := face.create_tween().set_parallel(true)
		ft.tween_property(face, "modulate:a", 1.0, T * sp)
		ft.tween_property(face, "position", center, T * sp)

	# ④ 문구(선택) — 원작 문자열을 그대로 받는다. 워드아트가 아니라 **문자열**이고,
	#    폰트는 원작 BMFont `font_title`(ExpLayer::set3MaxParticle → getFontName_title, scale 1.3.
	#    "트리플 맥스" 글리프 5자 전부 실재 — 619자 폰트라 다른 문구는 두부 주의 → 폴백 TTF).
	if banner != "":
		var bl := Label.new()
		bl.text = banner
		var fpath := "res://assets/converted/font_ui/font_title.fnt"
		if ResourceLoader.exists(fpath):
			var bf: FontFile = load(fpath).duplicate()
			bf.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
			var ok := true
			for ch in banner:
				if ch != " " and not bf.has_char(ch.unicode_at(0)):
					ok = false
					break
			if ok:
				bl.add_theme_font_override("font", bf)
		bl.add_theme_font_size_override("font_size", 48)   # 원작 37px × 1.3
		bl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.4))
		bl.add_theme_color_override("font_outline_color", Color(0.45, 0.1, 0.35, 1.0))
		bl.add_theme_constant_override("outline_size", 12)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bl.size = Vector2(vis.x, 90.0)
		# 세로 위치 = 원작 리터럴. `set3MaxParticle` 이 라벨을 `CCPoint(W*0.5 - x, H*0.7)` 에 놓는데
		# cocos 는 y-up 이므로 **위에서 30%**(= 밴드 위)다. 종전엔 화면 정중앙이라 컷인 얼굴을
		# 가로질러 덮고 있었다(사용자 신고 2026-07-31 → 원작 좌표로 정정).
		# ⚠️ 가로는 원작 x 오프셋(`local_108`)을 Ghidra 가 못 살려서 화면 중앙 정렬로 둔다.
		bl.position = Vector2(0.0, vis.y * BANNER_Y - bl.size.y * 0.5)
		bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bl.z_index = 10
		bl.modulate.a = 0.0
		bl.scale = Vector2(0.6, 0.6)
		bl.pivot_offset = bl.size * 0.5
		lay.add_child(bl)
		var lt := bl.create_tween().set_parallel(true)
		lt.tween_property(bl, "modulate:a", 1.0, T * 2.0 * sp)
		lt.tween_property(bl, "scale", Vector2.ONE, T * 2.5 * sp)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	Bgm.sfx("effect_cut_in")
	var done := lay.create_tween()
	done.tween_interval(TOTAL * sp)
	done.tween_callback(func(): if is_instance_valid(lay): lay.queue_free())
	return TOTAL * sp
