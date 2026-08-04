extends Node2D
## 각성기(궁극기) 연출 확인 창 — **PvP(콜로세움)에서 실제로 뜨는 것**을 속성별로 본다.
##
## 재생은 `UltimateFx.play()` 를 그대로 부른다 = `fight.gd::_awaken_fx` 와 **같은 코드**다.
## 여기서 본 그림이 곧 대전에서 뜨는 그림이고, 안 뜨면 대전에서도 안 뜬다.
##
## 실행: godot --path . res://scenes/dev_ultimate_fx.tscn
##   1~9 / ←→ = 속성 선택+재생 · SPACE = 재생 · A = 자동순환 · ESC = 종료
##
## ## 표의 근거 (docs/ref/orig_code/decomp/UltimateLayer.c)
## 원작은 속성마다 세 벌을 갖는다:
##   `setElement(el)`  → `init<El>()`     (@15382~ 전체판 자산 로드)
##   `setColosseum()`  → `init<El>_C()`   (@15830~ **콜로세움 추가분** — 바닥 링 circle1~3 등)
##   `runUltimate(t)`  → `run<El>()` + `action<El>_C()`  (@28742 안무)
## ⇒ 대전에서 뜨는 것은 **전체판 + _C 추가분**이다. 아래 ORIG 는 두 init 의 프레임 리터럴을
##   전수로 뽑은 것이고(`%d` 는 번호 시퀀스), 우리가 그중 무엇을 쓰는지 런타임에 대조한다.
##
## ⚠️ 이 창은 **자산 대조**까지만 판정한다. 원작 `run<El>`(속성당 800~1,200줄)의 안무 자체가
##   이식됐는지는 코드를 봐야 안다 — 현재는 9속성 **전부 미이식**이고 공통 골격
##   (바닥 링 + 가장 긴 프레임 시퀀스)만 돈다. 그래서 아래 판정의 상한이 🟠골격이다.

const ELEMENTS := ["fire", "aqua", "earth", "wind", "light", "dark", "holy", "chaos", "shadow"]
const KR := {
	"fire": "불", "aqua": "물", "earth": "땅", "wind": "바람", "light": "빛",
	"dark": "어둠", "holy": "신성", "chaos": "혼돈", "shadow": "그림자",
}

## 원작 `init<El>` / `init<El>_C` 가 부르는 리터럴(2026-08-05 전수 추출).
##   frames  = 전체판 `init<El>` 의 프레임(`%d` = 번호 시퀀스)
##   colo    = 콜로세움 추가분 `init<El>_C`
##   spine   = 그 속성이 쓰는 스파인(있으면)
##   extra   = 프레임 아틀라스 밖의 자산(합체 외곽선·먼지 등) — 이식하려면 따로 변환해야 한다
const ORIG := {
	"fire": {
		"frames": ["fire_explosion%d", "fire_fillar%d", "fire_earthquake", "fire_stone"],
		"colo": ["fire_circle1", "fire_circle2", "fire_fireball%d"],
		"spine": "", "extra": [],
	},
	"aqua": {
		"frames": ["aqua_surface%d", "aqua_shark%d", "aqua_fish1~5", "aqua_bubble"],
		"colo": ["aqua_circle1~3", "aqua_bubble"],
		"spine": "", "extra": [],
	},
	"earth": {
		"frames": ["earth_mountain%d", "earth_mountain", "earth_earthquake1/2",
			"earth_dust1/2", "earth_stone", "earth_light"],
		"colo": ["earth_circle1~3", "earth_earthquake1", "earth_dust1/2", "earth_stone"],
		"spine": "", "extra": [],
	},
	"wind": {
		"frames": ["wind_whirl%d", "wind_zmoon", "wind_wood", "wind_leaf"],
		"colo": ["wind_circle1~3"],
		"spine": "",
		"extra": ["battle/hurricane/combine_outline", "battle/combine_outline_white",
			"scene/colosseum/dust", "scene/colosseum/dust_cover"],
	},
	"light": {
		"frames": ["light_star", "light_earth", "light_saturn", "light_flash",
			"light_flashwing", "light_bomb", "light_sun", "light_sunlight", "light_sunwing"],
		"colo": ["light_circle1~3"],
		"spine": "", "extra": [],
	},
	"dark": {
		"frames": ["dark_hand%d", "dark_explosion%d", "dark_punch", "dark_ball"],
		"colo": ["dark_circle1~3", "dark_shade"],
		"spine": "",
		"extra": ["battle/dark/combine_outline", "battle/combine_outline_white"],
	},
	"holy": {
		"frames": ["holy_well", "holy_spear"],
		"colo": ["holy_circle1~3"],
		"spine": "skill/ultimate/holy/holy_wing_spine",
		"extra": [],
	},
	"chaos": {
		"frames": ["chaos_dust1~3", "chaos_meteo1/2"],
		"colo": ["chaos_circle1~3"],
		"spine": "",
		"extra": ["battle/amagethon/combine_outline", "battle/combine_outline_white",
			"scene/colosseum/dust", "scene/colosseum/dust_cover"],
	},
	"shadow": {
		"frames": [],
		"colo": ["shadow_circle1/2", "shadow_marsh1~3", "shadow_twist"],
		"spine": "skill/ultimate/shadow/shadow_spine",
		"extra": ["battle/blackwind/combine_outline", "battle/combine_outline_white"],
	},
}

## 스파인 변환본이 있는지 확인할 자리(spine_export → build_spine_scene 산출).
const FX_SCENE := "res://scenes/fx/%s.tscn"

const AUTO_SEC := 2.0

var _sel := 0
var _auto := false
var _t := 0.0
var _stage: Node2D
var _list: Array[Label] = []
var _detail: Label
var _hint: Label
var _pma: CanvasItemMaterial
var _last_dur := 0.0        # 마지막 재생의 원작 길이(getDuration 콜로세움 표)


func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA

	var vis := get_viewport_rect().size
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12)
	bg.size = vis
	add_child(bg)

	var title := Label.new()
	title.text = "각성기(UltimateLayer) 연출 확인 — fight.gd 가 부르는 UltimateFx.play() 를 그대로 재생"
	title.position = Vector2(20, 12)
	title.add_theme_font_size_override("font_size", 17)
	add_child(title)

	# 왼쪽 = 속성 목록 + 한 줄 판정
	var panel := ColorRect.new()
	panel.color = Color(0.12, 0.13, 0.17)
	panel.position = Vector2(16, 44)
	panel.size = Vector2(430, vis.y - 60)
	add_child(panel)
	for i in ELEMENTS.size():
		var l := Label.new()
		l.position = Vector2(28, 56 + i * 30)
		l.size = Vector2(410, 28)
		l.add_theme_font_size_override("font_size", 15)
		add_child(l)
		_list.append(l)

	# 아래 = 선택 속성 상세(원작 리터럴 ↔ 우리가 쓰는 것)
	_detail = Label.new()
	_detail.position = Vector2(28, 56 + ELEMENTS.size() * 30 + 14)
	_detail.size = Vector2(408, 300)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_theme_font_size_override("font_size", 13)
	_detail.modulate = Color(0.78, 0.86, 1.0)
	add_child(_detail)

	# 오른쪽 = 재생 무대. 바닥선을 그려 링이 어디 깔리는지 보이게 한다.
	var stage_x := 470.0
	var ground := Line2D.new()
	ground.width = 1.0
	ground.default_color = Color(1, 1, 1, 0.18)
	ground.add_point(Vector2(stage_x, vis.y * 0.62))
	ground.add_point(Vector2(vis.x - 20.0, vis.y * 0.62))
	add_child(ground)

	_stage = Node2D.new()
	_stage.position = Vector2((stage_x + vis.x - 20.0) * 0.5, vis.y * 0.62)
	add_child(_stage)

	_hint = Label.new()
	_hint.position = Vector2(stage_x, vis.y - 34)
	_hint.add_theme_font_size_override("font_size", 14)
	add_child(_hint)

	_refresh()
	_play()
	_maybe_shot()


## 육안 확인을 사람 손 없이 남길 때 —
##   godot --path . res://scenes/dev_ultimate_fx.tscn -- --el=fire --shot=scratch_shots/x.png
## (헤드리스 아님 — 렌더가 필요하다.)
func _maybe_shot() -> void:
	var out := ""
	var delay := 6
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			out = a.substr(7)
		elif a.begins_with("--el="):
			var i := ELEMENTS.find(a.substr(5))
			if i >= 0:
				_sel = i
		elif a.begins_with("--frame="):
			delay = int(a.substr(8))
	if out == "":
		return
	_refresh()
	_play()
	for i in delay:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()


func _process(delta: float) -> void:
	if not _auto:
		return
	_t -= delta
	if _t <= 0.0:
		# 각성기는 원작 기준 9~12초다 — 다 보고 넘어간다(종전 2초는 앞부분만 보였다).
		_t = maxf(AUTO_SEC, _last_dur + 0.5)
		_sel = (_sel + 1) % ELEMENTS.size()
		_refresh()
		_play()


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	var k := (e as InputEventKey).keycode
	if k >= KEY_1 and k <= KEY_9:
		_sel = k - KEY_1
		_refresh()
		_play()
		return
	match k:
		KEY_LEFT:
			_sel = posmod(_sel - 1, ELEMENTS.size()); _refresh(); _play()
		KEY_RIGHT:
			_sel = posmod(_sel + 1, ELEMENTS.size()); _refresh(); _play()
		KEY_SPACE:
			_play()
		KEY_A:
			_auto = not _auto
			_t = AUTO_SEC
			_refresh()
		KEY_ESCAPE:
			get_tree().quit()


## 대전과 같은 호출. 여기가 `fight.gd::_awaken_fx` 와 다르면 이 창은 의미가 없다.
func _play() -> void:
	for c in _stage.get_children():
		c.queue_free()
	var el: String = ELEMENTS[_sel]
	Bgm.sfx("effect_bigbang")
	# 대전과 같은 인자 모양으로 부른다 — 다르면 이 창이 대전을 대변하지 못한다.
	# 1vs1 기준(scale 1.0), 시전자는 왼쪽에 선 것으로 본다(dir +1).
	_last_dur = UltimateFx.play(_stage, {
		"element": el, "at": Vector2.ZERO, "scale": 1.0, "dir": 1.0,
		"speed": 1.0, "mat": _pma,
	})


# ── 판정 ────────────────────────────────────────────────────────────────────
## 속성별 실측 = 변환본 매니페스트 ↔ `UltimateFx` 가 실제로 고르는 키.
func _survey(el: String) -> Dictionary:
	var man := UltimateFx.manifest(el)
	var pfx := UltimateFx.prefix(el)
	var fams := UltimateFx.families(man, pfx)
	var used: Array = []
	if man.has(pfx + "circle1"):
		used.append(pfx + "circle1")
	var seq: Array = []
	if not fams.is_empty():
		seq = (fams[0]["frames"] as Array)
		used.append_array(seq)
	var idle: Array = []
	for f in fams:
		if fams.is_empty() or f == fams[0]:
			continue
		idle.append("%s(%d)" % [f["name"], (f["frames"] as Array).size()])
	# 계열에 안 잡히는 단품(번호 없는 프레임) — circle 제외
	var singles: Array = []
	for k in man:
		var s := String(k)
		if not s.begins_with(pfx) or s.begins_with(pfx + "circle"):
			continue
		var tail := s.substr(pfx.length())
		if tail.rstrip("0123456789") == tail:
			singles.append(tail)
	singles.sort()
	var o: Dictionary = ORIG.get(el, {})
	var spine := String(o.get("spine", ""))
	var spine_ok := false
	if spine != "":
		# 변환본 씬 이름은 `build_ultimate_fx.py` 가 정한 논리 이름이다(원본 basename 이 아니다).
		var sc: Dictionary = UltimateFx.RING_SPINE.get(el, {})
		spine_ok = not sc.is_empty() and ResourceLoader.exists(String(sc.get("scene", "")))
	return {
		"total": man.size(), "used": used.size(),
		"seq_name": String(fams[0]["name"]) if not fams.is_empty() else "",
		"seq_len": seq.size(),
		"ring": man.has(pfx + "circle1"),
		"idle": idle, "singles": singles,
		"spine": spine, "spine_ok": spine_ok,
		"extra": o.get("extra", []),
	}


## 한 줄 판정. ⚠️ 이모지는 쓰지 않는다 — 이 창의 폰트가 컬러 이모지를 못 그려
## 갈색 원으로만 나온다(2026-08-05 캡처 확인). 색으로 구분하고 글자는 태그로 쓴다.
##   [이식] = 원작 `run<El>` 안무를 옮겼다   [골격] = 링은 원작, 본체는 임시 자리표시자
## 판정 근거는 **`UltimateFx` 가 실제로 어느 분기를 타는가**다(추측이 아니다).
const PORTED := ["fire", "earth", "aqua", "wind", "dark", "light", "holy", "chaos", "shadow"]
## ↑ UltimateFx.play() 의 match 에 **분기가 있는** 속성. 손으로 적지 말고 그 match 와 맞출 것.

func _verdict(el: String, s: Dictionary) -> Array:
	var dur := float(UltimateFx.DURATION.get(el, 0.0))
	if el in PORTED:
		return ["[이식] 원작 안무 %.2f초" % dur, Color(0.55, 1.0, 0.7)]
	return ["[골격] 링만 원작 · 본체 임시(%s %d프레임)" % [s["seq_name"], int(s["seq_len"])],
		Color(1.0, 0.78, 0.35)]


func _refresh() -> void:
	for i in ELEMENTS.size():
		var el: String = ELEMENTS[i]
		var s := _survey(el)
		var v := _verdict(el, s)
		var mark := "▶" if i == _sel else "   "
		_list[i].text = "%s %d %s  %s  (자산 %d/%d)" % [
			mark, i + 1, KR[el], v[0], int(s["used"]), int(s["total"])]
		_list[i].modulate = v[1] if i == _sel else Color(v[1], 0.55)

	var el2: String = ELEMENTS[_sel]
	var s2 := _survey(el2)
	var o: Dictionary = ORIG.get(el2, {})
	var lines: Array = []
	lines.append("[ %s (%s) ]" % [KR[el2], el2])
	lines.append("원작 init%s      : %s" % [el2.capitalize(),
		", ".join(o.get("frames", []) as Array) if not (o.get("frames", []) as Array).is_empty() else "(프레임 없음 — 스파인만)"])
	lines.append("원작 init%s_C(대전): %s" % [el2.capitalize(), ", ".join(o.get("colo", []) as Array)])
	if String(s2["spine"]) != "":
		lines.append("원작 스파인       : %s  → 변환본 %s" % [s2["spine"],
			("있음" if bool(s2["spine_ok"]) else "없음 (spine_export 미실행 — 원본은 DV2/ 에 실재)")])
	if not (s2["extra"] as Array).is_empty():
		lines.append("원작 부가자산     : %s" % ", ".join(s2["extra"] as Array))
	lines.append("")
	lines.append("우리가 쓰는 것    : %s%s" % [
		("바닥 링 circle1 + " if bool(s2["ring"]) else ""),
		("%s %d프레임" % [s2["seq_name"], int(s2["seq_len"])]) if int(s2["seq_len"]) > 0 else "(시퀀스 없음)"])
	if not (s2["idle"] as Array).is_empty():
		lines.append("안 쓰는 계열      : %s" % ", ".join(s2["idle"] as Array))
	if not (s2["singles"] as Array).is_empty():
		lines.append("안 쓰는 단품      : %s" % ", ".join(s2["singles"] as Array))
	lines.append("")
	if el2 in PORTED:
		lines.append("원작 run%s 안무 이식 완료 — 길이 %.2f초 · 피해 표시 %.2f초" % [
			el2.capitalize(), float(UltimateFx.DURATION.get(el2, 0.0)),
			float(UltimateFx.DMG_TIME.get(el2, 0.0))])
	else:
		lines.append("원작 run%s 안무 **미이식** — 바닥 링만 원작이고 본체는 임시 자리표시자다." % el2.capitalize())
		lines.append("원작 길이 %.2f초 · 피해 표시 %.2f초 (docs/ref/porting/UltimateLayer.md §5)" % [
			float(UltimateFx.DURATION.get(el2, 0.0)), float(UltimateFx.DMG_TIME.get(el2, 0.0))])
	_detail.text = "\n".join(lines)

	_hint.text = "1~9 / ←→ 속성 · SPACE 재생 · A 자동순환 %s · ESC 종료" % ("ON" if _auto else "OFF")
