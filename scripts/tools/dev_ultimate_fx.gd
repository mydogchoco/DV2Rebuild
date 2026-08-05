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

# ── 무대에 세우는 드래곤 (사용자 지정 2026-08-05) ────────────────────────────
## 시전자 = 한울(777, 불) · 피격자 = 샛별(666, 혼돈). 둘 다 커스텀 6성 성체다.
## 스파인 로드는 **`fight.gd::_dragon_spine` 을 그대로** 부른다 — 대전과 같은 코드여야
## 이 창이 대전을 대변한다(정규화하는 `PartySelect._spine_node` 는 편성 카드용이라 안 쓴다).
const FightScene := preload("res://scripts/ui/fight.gd")
const CASTER_ID := 777
const TARGET_ID := 666
const CASTER_NAME := "한울"
const TARGET_NAME := "샛별"
const CM := "common_ui"

var _caster: Node2D
var _target: Node2D
var _caster_h := 240.0
var _target_h := 240.0
var _gy := 0.0                     # 무대 바닥 y = vis.y*0.5 + ULT_DROP (인게임과 동일)
var _ui: Node2D                    # 정보 패널 오버레이(TAB 토글)
var _caster_home := Vector2.ZERO   # 배우 초기 자리 — 재생마다 여기로 리셋(드리프트 방지)
var _target_home := Vector2.ZERO
var _actor_tweens: Array[Tween] = []   # 재생 중 배우에 건 트윈 — 다음 재생 때 전부 죽인다


func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA

	# 🔴 2026-08-05 재배치 — 무대가 창 오른쪽 절반에 욱여넣어져 인게임과 비율이 달랐다.
	#   이제 무대 = **화면 전체**(인게임과 같은 1024×692 캔버스), 배우 = 원작 각성 무대 좌표
	#   (`initPosition` 의 ±225, H/2−50 — fight.gd `ULT_DX`/`ULT_DROP` 와 동일).
	#   정보 패널은 TAB 토글 오버레이로 뺐다.
	var vis := get_viewport_rect().size
	_gy = vis.y * 0.5 + FightScene.ULT_DROP
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12)
	bg.size = vis
	add_child(bg)

	var ground := Line2D.new()
	ground.width = 1.0
	ground.default_color = Color(1, 1, 1, 0.18)
	ground.add_point(Vector2(0.0, _gy))
	ground.add_point(Vector2(vis.x, _gy))
	add_child(ground)

	_stage = Node2D.new()                 # 원점 = 화면 원점(대전의 씬 Control 과 같은 사정)
	add_child(_stage)

	# 드래곤 두 마리는 **재생마다 지워지지 않게** _stage 바깥(별도 노드)에 세운다.
	# 자리 = 각성 무대점(내 진영 225 · 상대 vis.x−225). 시전자는 어차피 그 자리로 뛰므로
	# 처음부터 무대점에 세워 두면 연출-배우 정합을 눈으로 확인할 수 있다.
	var actors := Node2D.new()
	add_child(actors)
	_caster = _make_actor(CASTER_ID, FightScene.ULT_DX, true)
	_target = _make_actor(TARGET_ID, vis.x - FightScene.ULT_DX, false)
	for a in [_caster, _target]:
		if a != null:
			actors.add_child(a)
	_caster_home = _caster.position if _caster != null else Vector2.ZERO
	_target_home = _target.position if _target != null else Vector2.ZERO

	# ── 오버레이 UI(TAB 토글) ──
	_ui = Node2D.new()
	_ui.z_index = 200
	add_child(_ui)
	var title := Label.new()
	title.text = "각성기(UltimateLayer) 연출 확인 — fight.gd 가 부르는 UltimateFx.play() 를 그대로 재생"
	title.position = Vector2(20, 12)
	title.add_theme_font_size_override("font_size", 17)
	_ui.add_child(title)
	var panel := ColorRect.new()
	panel.color = Color(0.12, 0.13, 0.17, 0.88)
	panel.position = Vector2(16, 44)
	panel.size = Vector2(430, vis.y - 60)
	_ui.add_child(panel)
	for i in ELEMENTS.size():
		var l := Label.new()
		l.position = Vector2(28, 56 + i * 30)
		l.size = Vector2(410, 28)
		l.add_theme_font_size_override("font_size", 15)
		_ui.add_child(l)
		_list.append(l)
	_detail = Label.new()
	_detail.position = Vector2(28, 56 + ELEMENTS.size() * 30 + 14)
	_detail.size = Vector2(408, 300)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_theme_font_size_override("font_size", 13)
	_detail.modulate = Color(0.78, 0.86, 1.0)
	_ui.add_child(_detail)
	_ui.visible = false                   # 연출을 가리지 않게 기본은 숨김 — TAB 으로 연다

	var who := Label.new()
	who.text = "시전 %s(%d) ▶   ◀ 피격 %s(%d)" % [CASTER_NAME, CASTER_ID, TARGET_NAME, TARGET_ID]
	who.position = Vector2(20, vis.y - 56)
	who.add_theme_font_size_override("font_size", 14)
	who.modulate = Color(0.8, 0.88, 1.0)
	who.z_index = 200
	add_child(who)

	_hint = Label.new()
	_hint.position = Vector2(20, vis.y - 34)
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.z_index = 200
	add_child(_hint)

	# 자산 사용량은 **재생하면서** 쌓이므로(`UltimateFx.used_keys`) 패널을 주기적으로 다시 그린다.
	var tick := Timer.new()
	tick.wait_time = 0.5
	tick.autostart = true
	tick.timeout.connect(_refresh)
	add_child(tick)

	_refresh()
	_play()
	_maybe_shot()


## 육안 확인을 사람 손 없이 남길 때 —
##   godot --path . res://scenes/dev_ultimate_fx.tscn -- --el=fire --cap=scratch_shots/x.png
##   연속 캡처(레퍼런스 영상 대조용): --el=fire --cap=scratch_shots/f.png --series=0.5
##     → f_t0.00.png, f_t0.50.png … 재생 길이(+1초)까지. --dur=N 으로 상한 지정 가능.
## ⚠️ 인자 이름이 `--cap=` 인 이유: `--shot=` 은 ShotHelper 오토로드가 가로채
##   자기 스케줄로 스크린샷을 찍고 **트리를 닫아 버린다**(2026-08-05 실측 — 8장에서 끊겼다).
## (헤드리스 아님 — 렌더가 필요하다.)
func _maybe_shot() -> void:
	var out := ""
	var delay := 6
	var series := 0.0
	var dur_cap := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cap="):
			out = a.substr(6)
		elif a.begins_with("--el="):
			var i := ELEMENTS.find(a.substr(5))
			if i >= 0:
				_sel = i
		elif a.begins_with("--frame="):
			delay = int(a.substr(8))
		elif a.begins_with("--series="):
			series = float(a.substr(9))
		elif a.begins_with("--dur="):
			dur_cap = float(a.substr(6))
	if out == "":
		return
	_refresh()
	_play()
	if series <= 0.0:
		for i in delay:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out)
		get_tree().quit()
		return
	# 연속 캡처 — 재생 시작 시각 기준으로 series 간격. 파일명 = <stem>_t<초>.png
	var total := dur_cap if dur_cap > 0.0 else _last_dur + 1.0
	var stem := out.get_basename()
	var ext := out.get_extension()
	var t0 := Time.get_ticks_msec()
	var t := 0.0
	while t <= total + 1e-4:
		var wait := t - float(Time.get_ticks_msec() - t0) / 1000.0
		if wait > 0.0:
			await get_tree().create_timer(wait).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_t%05.2f.%s" % [stem, t, ext])
		t += series
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
		KEY_TAB:
			if _ui != null:
				_ui.visible = not _ui.visible
		KEY_ESCAPE:
			get_tree().quit()


## 대전과 같은 호출. 여기가 `fight.gd::_awaken_fx` 와 다르면 이 창은 의미가 없다.
## 무대 배우 한 마리 — 대전(`fight.gd::_build_side`)과 같은 구성:
## 발밑 `common/shadow` + 성체 스파인(정규화 없음, 1vs1 배율 1.0) + 왼쪽 진영만 flipX.
func _make_actor(id: int, x: float, mine: bool) -> Node2D:
	var holder := Node2D.new()
	holder.position = Vector2(x, _gy)
	var sh := AtlasUI.spr_cocos(CM, "common_shadow")
	if sh != null:
		sh.z_index = -1
		holder.add_child(sh)
	var sp := FightScene._dragon_spine(id, "adult")
	if sp == null:
		return holder
	if mine:
		sp.scale = Vector2(-absf(sp.scale.x), sp.scale.y)
	holder.add_child(sp)
	var r := PartySelect._bounds(sp, Transform2D.IDENTITY)
	var h := r.size.y if r.size.y > 1.0 else 240.0
	if mine:
		_caster_h = h
	else:
		_target_h = h
	return holder


func _play() -> void:
	for c in _stage.get_children():
		c.queue_free()
	# 이전 재생의 배우 트윈을 전부 끊고 제자리로 — 안 끊으면 상대 이동이 누적돼
	# 재생할수록 드래곤이 떠오른다(2026-08-05 사용자 실측).
	for tw in _actor_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_actor_tweens.clear()
	if _caster != null:
		_caster.position = _caster_home
		_caster.modulate.a = 1.0
	if _target != null:
		_target.position = _target_home
		_target.modulate.a = 1.0
	var el: String = ELEMENTS[_sel]
	# ⚫ 종전의 `effect_bigbang` 은 원작에 없던 자작 배정이라 제거(사용자 확정 2026-08-05).
	#   효과음은 UltimateFx.SFX(원작 리터럴) + 타격음 배선이 낸다.
	var dur := float(UltimateFx.DURATION.get(el, 9.0))

	# 시전자 — 속성별 무대 안무 + 스파인 3단계(ultimate1→ultimate2→wait)는
	# `UltimateFx.caster_fx`(action<El>_C 실측)가 낸다. 대전(fight.gd)과 같은 코드.
	if _caster != null:
		var ap := FightScene._find_anim_player(_caster)
		_caster.modulate = Color(1, 1, 1, 1)
		_caster.scale = Vector2.ONE
		var b0: Vector2 = _caster.scale
		var tk := _caster.create_tween()
		tk.tween_interval(UltimateFx.LEAD + 0.2)
		tk.tween_property(_caster, "scale", Vector2(b0.x * 1.05, b0.y * 0.95), 0.1)
		tk.tween_property(_caster, "scale", Vector2(b0.x * 0.95, b0.y * 1.05), 0.1)
		tk.tween_property(_caster, "scale", b0, 0.1)
		_actor_tweens.append(tk)
		UltimateFx.caster_fx({
			"node": _caster, "anim": ap, "shadow": null,
			"home": _caster_home, "stage": _caster_home, "scale": 1.0, "host": _stage,
		}, el)
	if _target != null:
		# 피격 반응 — 대전의 `_ultimate_knockback`(원작 `damage<El>_C` 실측 표)을 그대로 흉내:
		# 저글링 n회 + 마무리 큰 띄우기, 그동안 스파인은 **damaged** 모션(원작
		# `runSpineWithAnimationName`), 끝나면 wait 복귀.
		# 높이는 원작 그대로(S×) — 종전 ×0.35 축소는 영상(화면 절반까지 던져진다)과 달랐다.
		var home := _target_home
		var k: Array = FightScene.ULT_KNOCK.get(el, [1.0, 4, 0.2, 0.3, 150.0, 800.0])
		var n_j := int(k[1])
		var jsec := float(k[2])
		var gap := float(k[3])
		var hop := float(k[4])
		var big := float(k[5])
		var at_sec := UltimateFx.damage_at(el, 1.0)
		var lead := maxf(float(k[0]), at_sec - (jsec + gap) * float(n_j) - 0.6)
		var tap := FightScene._find_anim_player(_target)
		var tt := _target.create_tween()
		tt.tween_interval(lead)
		tt.tween_callback(func() -> void:
			if tap != null and tap.has_animation("damaged"):
				tap.play("damaged"))
		for i in n_j:
			# 타격음 — 매 타마다(원작 배선). 두 음원을 번갈아, 볼륨 (rand%6)*0.05+0.25.
			var hit_track := "effect_dragon_damaged_%d" % (1 + i % 2)
			tt.tween_callback(func() -> void:
				Bgm.sfx(hit_track, float(randi() % 6) * 0.05 + 0.25))
			var d := Vector2(20.0 * float(i + 1), 0.0)      # 상대 진영은 +x 로 밀린다
			tt.tween_property(_target, "position", home + d - Vector2(0.0, hop), jsec * 0.5)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tt.tween_property(_target, "position", home + d, jsec * 0.5)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tt.tween_interval(gap)
		tt.tween_property(_target, "position", home - Vector2(0.0, big), 0.3)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tt.tween_property(_target, "position", home, 0.3)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tt.tween_callback(func() -> void:
			if tap != null and tap.has_animation("wait"):
				tap.play("wait"))
		_actor_tweens.append(tt)

	# 대전과 같은 인자 모양으로 부른다 — 다르면 이 창이 대전을 대변하지 못한다.
	# 1vs1 기준(scale 1.0), 시전자는 왼쪽(내) 진영. 기준점·방향은 UltimateFx 가
	# 원작 `initWithDragon` 대로 계산한다(불·땅 등은 시전자 **반대편**에 선다).
	_last_dur = UltimateFx.play(_stage, {
		"element": el,
		"mine": true,
		"ring_at": Vector2(FightScene.ULT_DX, _gy - _caster_h * 0.5),
		"scale": 1.0, "speed": 1.0, "mat": _pma,
	})


# ── 판정 ────────────────────────────────────────────────────────────────────
## 속성별 실측 = 변환본 매니페스트 ↔ `UltimateFx` 가 실제로 고르는 키.
func _survey(el: String) -> Dictionary:
	var man := UltimateFx.manifest(el)
	var pfx := UltimateFx.prefix(el)
	var fams := UltimateFx.families(man, pfx)
	# 🔵 2026-08-05 — 종전엔 "가장 긴 계열 + circle1" 을 우리가 쓰는 것으로 **추측**했다.
	#   그래서 이식을 마친 뒤에도 `spear`·`well`·`stone` 이 "안 쓰는 단품" 으로 남았다.
	#   이제 `UltimateFx.used_keys`(실제 요청 기록)를 읽어 **사실**을 낸다.
	var used: Array = []
	var unused: Array = []
	for k in man:
		var key := String(k)
		if not key.begins_with(pfx):
			continue
		if UltimateFx.used_keys.has(el + "/" + key):
			used.append(key)
		else:
			unused.append(key)
	unused.sort()
	var seq: Array = (fams[0]["frames"] as Array) if not fams.is_empty() else []
	# 미사용은 계열로 접어서 보여 준다(낱개 수백 줄이 되지 않게).
	var by_fam := {}
	for key in unused:
		var tail := String(key).substr(pfx.length())
		var stem := tail.rstrip("0123456789")
		by_fam[stem] = int(by_fam.get(stem, 0)) + 1
	var idle: Array = []
	var singles: Array = []
	for stem in by_fam:
		if int(by_fam[stem]) > 1:
			idle.append("%s(%d)" % [stem, int(by_fam[stem])])
		else:
			singles.append(String(stem))
	idle.sort()
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
		# 사용량은 **재생해 봐야** 나온다(`UltimateFx.used_keys`) — 아직 안 돈 속성은 `?` 로.
		var cnt := "%d/%d" % [int(s["used"]), int(s["total"])] if int(s["used"]) > 0 \
			else "?/%d" % int(s["total"])
		_list[i].text = "%s %d %s  %s  (자산 %s)" % [mark, i + 1, KR[el], v[0], cnt]
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
	lines.append("우리가 쓰는 것    : %d / %d 프레임 (재생하면서 실측 — SPACE 로 갱신)" % [
		int(s2["used"]), int(s2["total"])])
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

	_hint.text = "1~9 / ←→ 속성 · SPACE 재생 · A 자동순환 %s · TAB 정보 패널 · ESC 종료" \
		% ("ON" if _auto else "OFF")
