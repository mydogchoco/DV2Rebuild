extends Control
## 콜로세움 대전 씬 — 원작 `FightScene` + `MakeInterface::ColosseumFightInitWidget` 이식.
## render 층(§8). 🟦 사용자 확정 2026-08-04(솔로 재설계).
##
## ## 왜 battle.gd 가 아니라 새 파일인가
## 우리 `scripts/ui/battle.gd` 는 `AdventureScene` 계열 = **파티 카드 vs 중앙 몬스터 1마리**다.
## 콜로세움은 **양쪽 다 드래곤 스파인**이고 상단 UI(프로필·티어·연승)도 다르다.
## 원작도 `BattleScene`(탐험)과 `FightScene`(콜로세움)이 **별개 클래스**다 → 우리도 나눈다.
## 공유하는 것은 **로직층뿐**: `Battle.simulate(party_a, party_b, …)`.
##
## ## 원작이 서버에서 받던 것 → 우리가 채우는 것
## `FightScene::setActionParam` @00f8c93c(7,676B)은 `FightManager::getActor()` /
## `getActorAction()` / `getActorSkillNumber()` 를 읽어 **연출만 재생**하는 리플레이 플레이어다.
## 그 큐를 서버가 채웠다 → 우리는 `Battle.simulate()` 의 이벤트 배열로 채운다.
## 이게 이번 이식의 **유일한 배선 교체 지점**이다(docs/ref/porting/Colosseum.md §0·§2).
##
## ## 자산
## 보유: `scene/colosseum/{vs, vs_bg, mini_vs, profilebox, stage_0~7.jpg,
##   popup_win_kr, popup_win_bg_kr, popup_lose_kr, popup_lose_bg_kr, tag_win_kr, tag_lose_kr}`
##   · `common/tier_icon_*`(5티어) · `9patch/{bar1~4, bar_bg1~2, dialogue_box}`
## 미보유(§10 판본 불일치): `new9patch/du_*` `newCommon/{du_frame_dragon_02, tm_point}`
##   — 전부 **Dual(방어덱) 분기**라 우리가 컷한 모드의 프레임이다. 콜로세움 분기는 전부 보유.
## ⚪ 미변환: `scene/colosseum/fight_spine`(VS 연출 스파인) — spine_export 미실행.
##   지금은 보유 프레임 `vs` + `vs_bg` 로 낸다. 변환하면 `_vs_intro()` 한 곳만 교체.

const CO := "colosseum_ui"
const NP := "ninepatch_ui"
const CM := "common_ui"
const ST := "stand_ui"
const BG_DIR := "res://assets/converted/colosseum_bg"

# 원작 3v3 배치 — **화면 비율이 아니라 좌·우 바닥 모서리 기준 절대 오프셋**이다.
#
# 🔴 2026-08-04 정정(사용자 지적 "원작 로직을 그대로 계승하지 않았다") — 종전 비율 배치는 자작이었다.
# 근거: `FightScene::init` @00f88fac 이 슬롯 태그로 위치를 잡는다 —
#   내 팀 = 태그 11·13·15 (`iVar3 = 0xb`, +2), 상대 = 태그 10·12·14 (`iVar3 = 10`, +2).
#   위치는 `FUN_00f8ad70(layer, sceneType)` 가 태그로 분기해 준다(probe/fight_slot_probe.c):
#     tag 11 → `FUN_00f8f65c`  = leftBottom  + (335, 262.5)
#     tag 13 →                   leftBottom  + (200, 350)
#     tag 15 →                   leftBottom  + (135, 175)
#     tag 10 → `FUN_00f8f738`  = rightBottom + (-335, 262.5)
#     tag 12 →                   rightBottom + (-200, 350)
#     tag 14 →                   rightBottom + (-135, 175)
#   (probe/fight_slot0_probe.c — 콜로세움 씬 타입은 `0xbf2` 마스크에 드는 분기다.)
# Cocos y 는 바닥 기준이라 Godot 은 `visH - y` 로 뒤집는다(§Design).
#
# 스케일도 원작대로 — `makeDragonLayer` @0105072c 끝: **3v3 = 0.75, 1v1 = 1.0**.
# 뒤집기도 원작대로 — 같은 함수의 `1 << tag & 0xa800`(= 태그 11·13·15) 만 flipX 한다 = **내 팀**.
const SLOT_OFF := [Vector2(335.0, 262.5), Vector2(200.0, 350.0), Vector2(135.0, 175.0)]
const DRAGON_SCALE_TEAM := 0.75     # 원작 makeDragonLayer: type 3(3v3)
const DRAGON_SCALE_SOLO := 1.0      # 원작 makeDragonLayer: type 1(1v1)

# ✅ 2026-08-05 재확인 — 위 3v3 좌표를 **두 번째 경로로 교차검증**했다.
#   `FUN_0105564c(out, layer, sceneType)` @0105564c 는 "그 드래곤 레이어의 **최종 슬롯 좌표**"를
#   주는 원작 헬퍼다(`duelDragonAppear` 의 착지 MoveTo · `swapPosition` 의 복귀 MoveTo 가 쓴다).
#   ASM + 점프테이블(0x21b0642, 6엔트리) + `.rodata` 실측:
#     tag 10 → `FUN_010b21a0(sceneType)` · tag 11 → `FUN_010b20c4(sceneType)`
#     tag 12 → rightBottom + (**−200, 350**) · tag 13 → leftBottom + (**200, 350**)
#     tag 14 → rightBottom + (**−135, 175**) · tag 15 → leftBottom + (**135, 175**)
#   PLT 심볼 실명 확인(.rela.plt): `VisibleRect::leftBottom/rightBottom/left/right`.
#
# 🔴 **1vs1 은 좌표가 다르다**(사용자 지적 "위치가 원작과 다르다"의 한 원인).
#   앞줄 좌표 함수가 `FightManager::getType()` 으로 갈라진다 —
#   콜로세움은 `ColosseumScene` 이 **1VS1 = setType(0) · 3VS3 = setType(1)** 로 넣는다.
#     `FUN_010b20c4`(내 앞줄): `type<=11 && (1<<type)&**0xbf2**` → leftBottom + (335, 262.5)
#         ⇒ type 1(3v3) ✅ 해당 / type 0(1v1) ✗ ⇒ else 가지 = **`VisibleRect::left() + (225, −50)`**
#     `FUN_010b21a0`(상대 앞줄): 점프테이블(0x21b0c1b, index = type−1)
#         ⇒ type 1 → rightBottom + (−335, 262.5) / type 0 은 표 밖 ⇒ **`right() + (−225, −50)`**
#   `left()`/`right()` 는 화면 **세로 중앙**의 좌·우 모서리다(바닥이 아니다).
const SOLO_SLOT := Vector2(225.0, -50.0)   # 1vs1 — left()/right() 기준 (원작 type 0 가지)
# ⚠️ 드래곤 스파인의 **기본 방향은 왼쪽**이다(실측 2026-08-04 — 처음엔 반대로 알고
#   상대만 뒤집었더니 우리 팀이 등을 보였다). 그래서 **왼쪽에 서는 내 팀**을 뒤집는다.
# `PartySelect._spine_node` 는 **holder 원점 = 스프라이트 바닥 중앙**으로 맞춘다
# (party_select.gd:115 `inst.position -= …`). 그래서 바는 원점 바로 아래에 둔다.
const BAR_DY := 12.0
const BAR_W := 168.0
const BAR_H := 16.0

var _pma: CanvasItemMaterial
var _params: Dictionary = {}
var _mans: Dictionary = {}
var _rng := RandomNumberGenerator.new()

var _mode := "team"
var _foe: Dictionary = {}
var _my: Array = []          # PartyStats.summary_of 결과
var _fo: Array = []
var _views: Dictionary = {}  # 내부이름(A0/E0) → {node, bar, hp, hp_max, dead}
var _events: Array = []
var _winner := ""
var _gen := 0
var _log: Label
var _stage: Dictionary = {}  # Colosseum.roll_stage() 결과 {index, element, bg}


func enter(params: Dictionary = {}) -> void:
	_params = params
	if _pma != null:
		_rebuild()


func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_rng.randomize()
	# 🟦 대전 BGM 은 **매 판 랜덤**(사용자 확정 2026-08-05). 곡 목록 = data/colosseum.json `bgm.battle`.
	#   ⚠️ 클라(`FightScene`·`FightManager`·`MakeInterface`)에는 전투 BGM 재생 호출이 **하나도 없다**
	#     (전수 grep) — 로비만 `ColosseumScene::onEnterTransitionDidFinish` @00f41e00 이 낸다.
	#     그래서 곡 목록은 원작 대조로 확정할 수 없고, 이름이 용도를 말하는 보유 음원으로 시작한다.
	Bgm.play(Colosseum.battle_bgm(_rng))
	_rebuild()


func _rebuild() -> void:
	_gen += 1
	for c in get_children():
		c.queue_free()
	_views.clear()
	_log_lines.clear()
	_skipped = false
	_folded = true
	_speed = 1

	_mode = String(_params.get("mode", "team"))
	_foe = _params.get("opponent", {})
	var uids: Array = _params.get("party", [])
	if uids.is_empty():
		uids = UserDB.party()
	var n := Colosseum.party_size(_mode)

	# 무대 속성 추첨 — 원작은 전투 시작 룰렛으로 정한다(`createElement`).
	# **스탯보다 먼저** 뽑아야 한다: 무대와 같은 속성의 드래곤이 보정을 받으므로
	# `PartyStats` 가 이 값을 알아야 한다(양 진영 모두 — 원작 `checkStageBuff` 도 그렇다).
	# `stage_element` 를 넘기면 그 무대로 고정한다(원작에선 서버가 정해 줬다 — 검수·재현용).
	var forced := String(_params.get("stage_element", ""))
	_stage = Colosseum.stage_of(forced) if forced != "" else {}
	if _stage.is_empty():
		_stage = Colosseum.roll_stage(_rng)
	var sel := String(_stage.get("element", ""))

	# 양 팀 스탯 — **같은 함수**로 만든다(봇 전용 계산 없음, §Colosseum 설계).
	_my = PartyStats.summary(uids.slice(0, n), false, "", {}, sel)
	_fo = PartyStats.summary_of((_foe.get("dragons", []) as Array).slice(0, n), false, "", {}, sel)
	# 각성 스킬·장비 조건부 효과 — **HUD 를 만들기 전에** 얹는다(최대 체력을 바꾼다).
	_apply_passives()

	var vis := _vis()
	_build_bg(vis)
	# 원본 레코드도 같이 넘긴다 — 드래곤을 누르면 뜨는 상태창(`CharacterInfoPopup`)이
	# 젬·장비·스킬을 **레코드에서** 읽는다(요약본에는 그 원본이 없다).
	var my_recs: Array = []
	for u in uids.slice(0, n):
		my_recs.append(UserDB.get_dragon(int(u)))
	_build_team(_my, true, vis, my_recs)
	_build_team(_fo, false, vis, (_foe.get("dragons", []) as Array).slice(0, n))
	_build_top(vis)
	_build_log(vis)
	# 무대 룰렛이 끝나야 전투가 시작된다(원작 initInterface 의 지연 누적과 같은 자리).
	# 등장 연출(단상→착지)도 같은 자리에서 병렬로 돌고, 둘 중 **늦게 끝나는 쪽**을 기다린다.
	_start(maxf(_build_stage_roulette(vis), _appear_intro(vis)))


# ---------- 배경 ----------

func _build_bg(vis: Vector2) -> void:
	# 🔴 2026-08-05 정정 — 종전엔 배경을 **독립적으로** 랜덤 뽑았다(무대 속성과 무관).
	#   원작은 `DualManager::getAttributeBgImage` @00f88b28 가 **무대 속성 → stage_N.jpg** 로
	#   가른다. 룰렛이 고른 속성과 배경이 반드시 같아야 한다.
	#
	# ## 속성 → 배경 번호 (2026-08-05 재확인, 사용자 요청 "배선이 어떻게 되어 있는지 확인")
	#   같은 표가 **두 곳**에서 확인된다:
	#     · `MakeInterface::DuelFightInitWidget` @01056218 — `getStageElement()` 가 8 미만이면
	#       그대로 `"scene/colosseum/stage_%d.jpg"`, 8(그림자)이면 `stage_ballok_n.jpg`.
	#     · `DualManager::getAttributeBgImage` @00f88b28 — 0→3 · 1→0 · 2→4 · 3→7 · 4→6 ·
	#       5→2 · 6→5 · 7→1 (방어덱 화면용. **순서 배열이 다를 뿐 같은 8장**을 쓴다.)
	#   우리 표 = `data/colosseum.json` `stage.bg` 이고 휠 순서(aqua·chaos·dark·earth·fire·
	#   holy·light·wind·shadow) 그대로 0~7 + shadow 는 `stage_ballok_n` 미보유라 3 으로 폴백.
	var tr := TextureRect.new()
	tr.texture = _stage_bg_tex(String(_stage.get("element", "")))
	tr.size = vis
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	# 🔴 2026-08-05(사용자 지적 "단상 없이 허공에서 착지한다") — **배경 z 가 0 이었다.**
	#   Godot 은 z 가 같으면 트리 순서로 그리므로 배경(z=0, 먼저 붙음)보다 **z 가 낮은 것**은
	#   전부 배경 뒤로 숨는다 ⇒ 단상(z=−2)도 발밑 그림자(z=−1)도 한 번도 안 보였다.
	#   배경을 확실히 맨 뒤로 내린다.
	tr.z_index = -10
	add_child(tr)
	_bg = tr


## 속성 → 배경 텍스처(없으면 기본 stage_3). 룰렛이 매 스텝 이 함수로 배경을 갈아 끼운다.
var _bg: TextureRect
var _bg_cache: Dictionary = {}
func _stage_bg_tex(element: String) -> Texture2D:
	var map: Dictionary = Colosseum.stage_cfg().get("bg", {})
	var n := int(map.get(element, 3))
	if _bg_cache.has(n):
		return _bg_cache[n]
	var p := "%s/stage_%d.jpg" % [BG_DIR, n]
	if not ResourceLoader.exists(p):
		p = "%s/stage_3.jpg" % BG_DIR
	var t: Texture2D = load(p) if ResourceLoader.exists(p) else null
	_bg_cache[n] = t
	return t


# ---------- 무대 속성 룰렛 — 원작 `MakeInterface::addBottomPropertyUI` @01055d28 ----------
#
# 원작이 하는 일(디컴프 그대로):
#   `scene/colosseum/stage_bg.png` 를 anchor(0.5, 0)·화면 바닥에 놓고 **가로를 꽉 채우도록**
#   `setScale(화면오른쪽 / 프레임폭)` 한 뒤 z=15 로 붙인다. 그 스프라이트가 시퀀스를 돈다:
#     Delay(1.0) → createElement → Delay((idx+11)×0.1) → FadeTo(0,255) → … →
#     Delay(1.0) → FadeTo(0.5, 0) → remove
#
#   `createElement` @0105daf0 — 룰렛 본체. 기준점 = 바 로컬 (w×0.5 + 10, h×0.5 + 50).
#     `item/etc/ele_*.png` 9칸을 (i+3)×150pt 오른쪽에 alpha 0 · scale 0 으로 깔고,
#     0.1초마다 −150 씩 민다. `checkElementMatch` @0105f010 가 매 칸마다:
#       x == 기준+450 → FadeTo(0.3, 255) + ScaleTo(0.3, 0.825)   (창 안으로 등장)
#       x == 기준     → FadeTo(0.3, 0)   + ScaleTo(0.3, 0)       (창 밖으로 소멸)
#       x == 기준−600 → setPositionX(기준+600)                    (되돌리기)
#     당첨 칸만 (idx+1) 스텝을 더 가 기준점에 멈추고 ScaleTo(0.1,0.9)→ScaleTo(0.05,0.825) 로 튄다.
#     그와 별개로 **큰 도장** 한 장(같은 아이콘, scale 2.5 · alpha 0)이 기준점에 있다가
#     Delay(idx×0.1 + 1.0) 뒤 FadeTo(0.25, 200) + ScaleTo(0.25, 0.825) 로 내려앉고 사라진다.
#
# 우리 구현이 원작과 다른 **한 가지**: 되돌리기(wrap) 대신 **위상을 민 긴 띠**를 만든다.
#   원작은 아이콘 9장을 −600 에서 +600 으로 순간이동시켜 재사용하는데, 그러면 같은 노드가
#   중앙을 여러 번 지나며 `checkElementMatch` 의 소멸 분기에 다시 걸린다. 결과 위치는
#   같으므로(주기 8칸) 띠를 `wheel[(j−8) mod 9]` 로 깔면 **당첨 칸이 정확히 마지막 스텝에
#   기준점**에 오고 중간에 소멸 분기를 타지 않는다. 간격·시간·배율·알파는 전부 원작 값이다.
const ELE_FRAME := {
	"earth": "ground", "aqua": "water", "fire": "fire", "wind": "wind",
	"light": "light", "dark": "dark", "holy": "holy", "chaos": "chaos", "shadow": "shadow",
}
const STAGE_ANCHOR := Vector2(10.0, 50.0)   # 원작 (w*0.5 + 10, h*0.5 + 50) 의 +오프셋

## 반환 = **룰렛이 결론 날 때까지의 초**. 원작 `initInterface` 가 개시 연출들의 지연을
## `fVar24` 에 누적해 마지막에 `setActionParam`(= 액션 재생)에 넘기는 것과 같은 자리다 —
## 무대가 정해지기 전에 전투가 시작되면 안 된다(사용자 지적 2026-08-05).
func _build_stage_roulette(vis: Vector2) -> float:
	if _stage.is_empty():
		return 0.0
	var A: Dictionary = Colosseum.stage_cfg().get("anim", {})
	var step_sec := float(A.get("step_sec", 0.1))
	var step_px := float(A.get("step_px", 150.0))
	var base_steps := int(A.get("base_steps", 11))
	var window := int(A.get("window", 3))
	var fade := float(A.get("fade_sec", 0.3))
	var icon_s := float(A.get("icon_scale", 0.825))
	var lead := float(A.get("lead_sec", 1.0))
	var idx := int(_stage.get("index", 0))
	var wheel := Colosseum.stage_wheel()
	if wheel.is_empty():
		return 0.0
	var total := base_steps + idx           # 원작 Delay((idx+11)×0.1) 의 스텝 수

	# ① 바닥 띠 — 원작 프레임 그대로, 가로 꽉 채움.
	var bar := _spr(CO, "scene_colosseum_stage_bg")
	if bar == null:
		return 0.0
	var bw := float(bar.texture.get_width())
	var bh := float(bar.texture.get_height())
	var k := vis.x / bw                      # 원작 setScale(VisibleRect::right / w)
	bar.scale = Vector2(k, k)
	bar.centered = false
	bar.position = Vector2(0.0, vis.y - bh * k)
	bar.z_index = 15                         # 원작 addChild(bar, 15)
	add_child(bar)

	# 룰렛 좌표는 **바 로컬**이다(원작도 바의 자식으로 붙인다).
	# ⚠️ Cocos 는 부모 좌하단 기준·y 위쪽 증가라 `(w*0.5+10, h*0.5+50)` 은 **바 윗변보다 위**다
	#   (43 높이 바에서 71.5 ⇒ 윗변 +28.5). Godot 은 y 아래쪽 증가라 뒤집는다(§Design).
	#   이 뒤집기를 빠뜨리면 아이콘이 바 **아래**(화면 밖)로 가 하나도 안 보인다.
	var org := Vector2(bw * 0.5 + STAGE_ANCHOR.x, bh - (bh * 0.5 + STAGE_ANCHOR.y))

	# ② 룰렛 띠. j = 몇 스텝 뒤에 기준점에 닿는가 = 그 칸이 중앙에 서는 순서다.
	#    당첨 칸이 마지막 스텝(j = total = base_steps + idx)에 와야 하므로
	#    `wheel[(j − base_steps) mod 9]` 로 깐다 ⇒ j = total 일 때 `wheel[idx]` ✓.
	#    (원작은 −600 → +600 wrap 으로 같은 결과를 낸다.)
	var phase := base_steps
	var gen := _gen
	for j in range(window, total + 1):
		var el := String(wheel[posmod(j - phase, wheel.size())])
		var ic := _spr("item_etc", "item_etc_ele_%s" % ELE_FRAME.get(el, "ground"))
		if ic == null:
			continue
		ic.position = org + Vector2(float(j) * step_px, 0.0)
		ic.scale = Vector2.ZERO
		ic.modulate.a = 0.0
		bar.add_child(ic)
		# 이동은 스텝마다의 MoveBy(-150) 를 이어 붙인 것과 같다(등속) ⇒ 트윈 하나로 낸다.
		# 모든 트윈이 원작 첫 Delay(1.0)(`lead`) 만큼 늦게 시작한다.
		# 🔴 모든 칸이 **같은 속도**(150pt / 0.1초)로 움직여야 j 번째가 정확히 j 스텝째에
		#   기준점에 온다. 도착점을 org.x 로 고정하면 칸마다 속도가 달라져 전부 중앙으로
		#   모여든다(2026-08-05 첫 캡처에서 아이콘이 한 장만 보이던 원인).
		var mv := ic.create_tween()
		mv.tween_interval(lead)
		mv.tween_property(ic, "position:x", org.x + float(j - total) * step_px,
			float(total) * step_sec).set_trans(Tween.TRANS_LINEAR)
		# 등장 — 창 안(+window 칸)에 들어오는 순간.
		var tin := ic.create_tween()
		tin.tween_interval(lead + float(j - window) * step_sec)
		tin.tween_property(ic, "modulate:a", 1.0, fade)
		tin.parallel().tween_property(ic, "scale", Vector2(icon_s, icon_s), fade)
		if j == total:
			# 당첨 칸 — 소멸하지 않고 기준점에서 튄다(원작 ScaleTo 0.1→0.9, 0.05→0.825).
			var pop := ic.create_tween()
			pop.tween_interval(lead + float(total) * step_sec)
			pop.tween_property(ic, "scale", Vector2(0.9, 0.9), 0.1)
			pop.tween_property(ic, "scale", Vector2(icon_s, icon_s), 0.05)
		else:
			# 나머지 — 기준점에 닿을 때 사라진다.
			var out := ic.create_tween()
			out.tween_interval(lead + float(j) * step_sec)
			out.tween_property(ic, "modulate:a", 0.0, fade)
			out.parallel().tween_property(ic, "scale", Vector2.ZERO, fade)
			out.tween_callback(ic.queue_free)

	# ②-b 배경도 룰렛과 **같이 돈다** — 🟦 사용자 확정 2026-08-05
	#   ("각 원소에 할당된 배경화면으로 배경도 같이 바뀌다가 확정 원소 배경으로 고정된다").
	#   ⚠️ 원작 근거는 여기까지다: 스텝마다 도는 콜백(`CCCallFunc`, 람다 @010c7668)을 ASM 으로
	#     풀어 보면 하는 일이 **효과음 `music/effect_element_match.mp3`(vol 1.0) 뿐**이고,
	#     배경은 `DuelFightInitWidget` 이 무대 속성 한 장을 `Show → FadeIn(1.0)` 으로 띄운다.
	#     즉 "스텝마다 배경 교체"는 원작 코드에서 확인되지 않는다 — 사용자 기억에 따른 확장이다.
	#   기준점에 서는 칸이 곧 그 순간의 배경이므로 스텝 t 의 속성 = `wheel[(t − phase) mod 9]`.
	if _bg != null:
		_bg.texture = _stage_bg_tex(String(wheel[posmod(-phase, wheel.size())]))
		for t in range(1, total + 1):
			var bel := String(wheel[posmod(t - phase, wheel.size())])
			var at := lead + float(t) * step_sec
			get_tree().create_timer(at).timeout.connect(func() -> void:
				if gen != _gen:
					return
				# 스텝 효과음 — 원작 람다가 내는 유일한 것(위 주석).
				Bgm.sfx("effect_element_match")
				if is_instance_valid(_bg):
					_bg.texture = _stage_bg_tex(bel))

	# ③ 큰 도장 — 당첨 아이콘이 확대 상태에서 내려앉는다.
	var stamp := _spr("item_etc",
		"item_etc_ele_%s" % ELE_FRAME.get(String(_stage.get("element", "")), "ground"))
	if stamp != null:
		var ss := float(A.get("stamp_scale", 2.5))
		stamp.position = org
		stamp.scale = Vector2(ss, ss)
		stamp.modulate.a = 0.0
		bar.add_child(stamp)
		var st := stamp.create_tween()
		# 원작 도장 딜레이 = `Delay(idx×0.1 + 1.0)` 이고 그건 `createElement` 안이라
		# 바의 첫 `Delay(1.0)` 뒤에 온다 ⇒ 시작 기준 `lead + idx×0.1 + 1.0`.
		st.tween_interval(lead + float(idx) * step_sec + lead)
		st.tween_property(stamp, "modulate:a",
			float(A.get("stamp_alpha", 200)) / 255.0, float(A.get("stamp_sec", 0.25)))
		st.parallel().tween_property(stamp, "scale", Vector2(icon_s, icon_s),
			float(A.get("stamp_sec", 0.25)))
		st.tween_callback(stamp.queue_free)

	# ④ 바 자체의 수명 — 결정 후 hold_sec 쥐고 있다가 out_sec 에 걸쳐 사라진다.
	var life := bar.create_tween()
	life.tween_interval(lead + float(total) * step_sec + float(A.get("hold_sec", 1.0)))
	life.tween_property(bar, "modulate:a", 0.0, float(A.get("out_sec", 0.5)))
	life.tween_callback(bar.queue_free)

	# ⑤ 무대 버프 스파인 — 룰렛이 결정되는 순간 속성이 맞는 드래곤 전원에게 붙는다.
	#   원작 `checkStageBuff` 는 이걸 전투 시작 지연에 물리는데, 우리는 **결정 시점**에 맞춘다
	#   (룰렛이 우리 쪽에선 로그 바와 같은 타임라인이라, 그래야 원인과 결과가 이어져 보인다).
	get_tree().create_timer(lead + float(total) * step_sec).timeout.connect(func() -> void:
		if gen == _gen:
			_stage_buff_fx())

	# 전투 개시 시점 = 룰렛이 멈추고 **도장이 다 내려앉은 뒤**.
	return lead + float(total) * step_sec + float(A.get("stamp_sec", 0.25))


## 무대 버프 — 원작 `MakeInterface::showStageBuff` @0105f4b8.
## 종족이 무대 속성과 같은 드래곤 **양 진영 전원**에게 `battle/stage_<race>_buff_spine` 을
## 드래곤 레이어 중앙에 scale 1.5 · z=10 으로 붙이고 `"animation"` 을 **1회** 재생한다.
## 변환본 = `scenes/buffs/stage_buff_<element>.tscn`(탐험 `battle.gd::_build_field_buff` 와 공유).
func _stage_buff_fx() -> void:
	var el := String(_stage.get("element", ""))
	if el == "":
		return
	var path := "res://scenes/buffs/stage_buff_%s.tscn" % el
	if not ResourceLoader.exists(path):
		return
	var bs := float((Colosseum.stage_cfg().get("anim", {}) as Dictionary).get("buff_scale", 1.5))
	for tag in _views:
		var v: Dictionary = _views[tag]
		if not bool(v.get("stage_buff", false)) or bool(v.get("dead", false)):
			continue
		var node = v.get("node")
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		var holder := Node2D.new()
		# 우리 holder 원점 = 발밑 중앙이라 몸통 중앙까지 올린다(원작은 레이어 contentSize×0.5).
		holder.position = Vector2(0.0, -float(v.get("dragon_h", DRAGON_H)) * 0.5)
		holder.scale = Vector2(bs, bs)
		holder.z_index = 10                     # 원작 addChild(spine, 10)
		(node as Node2D).add_child(holder)
		var inst = (load(path) as PackedScene).instantiate()
		holder.add_child(inst)
		# ⚠️ 이 스파인은 **원점 보정을 하면 안 된다.** 변환 씬의 스프라이트가 전부
		#   `visible = false` 로 시작해(애니가 켠다) 경계 실측이 빈 사각형으로 나오고,
		#   무엇보다 `root/bone1:position` 트랙이 y −196 까지 **올라가는 것이 이 이펙트의 안무**다
		#   (불길이 드래곤 몸에서 솟는다). 원작도 레이어 중앙에 그대로 붙인다.
		var ap := _find_anim_player(inst)
		if ap != null:
			var anims := ap.get_animation_list()
			if anims.size() > 0:
				ap.get_animation(anims[0]).loop_mode = Animation.LOOP_NONE
				ap.play(anims[0])
				var t := holder.create_tween()
				t.tween_interval(ap.get_animation(anims[0]).length)
				t.tween_callback(holder.queue_free)


# ---------- 팀 배치 ----------

## 슬롯 좌표 — 원작 `FUN_0105564c` 의 태그별 분기를 그대로 옮긴다(위 상수 주석 참조).
## 반환은 **Godot 좌표**(y-flip 완료). `slot` 0=앞줄 1=중간 2=뒷줄.
func _slot_pos(mine: bool, slot: int, vis: Vector2) -> Vector2:
	if _mode != "team":
		# 1vs1 — 원작 type 0 가지. 기준이 `left()`/`right()` = 화면 **세로 중앙**이다.
		#   Cocos (225, h/2 − 50) → Godot y = h − (h/2 − 50) = h/2 + 50.
		return Vector2(SOLO_SLOT.x if mine else vis.x - SOLO_SLOT.x,
			vis.y * 0.5 - SOLO_SLOT.y)
	var off: Vector2 = SLOT_OFF[slot % SLOT_OFF.size()]
	return Vector2(off.x if mine else vis.x - off.x, vis.y - off.y)


func _build_team(team: Array, mine: bool, vis: Vector2, recs: Array = []) -> void:
	for i in team.size():
		var p: Dictionary = team[i]
		var tag := ("A%d" if mine else "E%d") % i
		var slot := _slot_pos(mine, i, vis)
		var x := slot.x
		var y := slot.y

		var holder := Node2D.new()
		holder.position = Vector2(x, y)
		add_child(holder)

		# ⚠️ **콜로세움은 항상 성체 스파인이다.**
		#   ① 원작 입장 조건이 레벨 25(=성체) 이상이라 애초에 유생이 못 들어온다
		#      (`ColosseumInError` "테이머 자격증 이벤트를 완수하셔야 입장할 수 있습니다. (레벨 25)").
		#   ② 실측(2026-08-04): 공격 모션은 **성체에만 있다** —
		#      adult 134/134 에 `attack` 존재, child 132/133 · baby 132/133 은 **없음**.
		#      종전엔 레벨 30 미만이면 child 를 띄워서, 저레벨 드래곤이 공격해도 아무 모션이
		#      없었다(사용자 지적).
		# 🔴 2026-08-05 보강(사용자 지적) — "성체"는 **각성체를 포함하지 않는다.**
		#   각성한 드래곤은 `_e` 스파인이 정답이다(`Growth.spine_stage` — `_dragon_spine` 참조).
		# 발밑 그림자 — 원작 `MakeInterface::setShadow` @01050b10 이
		#   `common/shadow.png` 를 드래곤 위치 −(0, s*95) 에 `setScale(s + 1.0)` 로 깐다
		#   (z=1, tag=-0x226). 우리 holder 원점 = 스프라이트 **바닥 중앙**이라 그 자리에 둔다.
		var sh := _spr(CM, "common_shadow", Design.ASSET_SCALE)
		if sh != null:
			sh.scale *= (DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO)
			sh.z_index = -1
			holder.add_child(sh)

		# 🔴 2026-08-05 — **정규화를 뺐다.** `PartySelect._spine_node(…, DRAGON_H)` 는 모든 종을
		#   같은 높이(170pt)로 눌러 담는 **우리 장치**다(편성 카드용). 원작 `makeDragonLayer` 는
		#   스파인을 **native 크기 그대로** 놓고 3v3=0.75 / 1v1=1.0 만 곱한다 ⇒ 종마다 크기가 다르다.
		#   실측(2026-08-05): 성체 native 높이 288~296pt → 3v3 이면 ~217pt.
		#   종전 값(170×0.75=127pt)은 레퍼런스(`docs/ref/pvp/`, 드래곤 210~250pt)의 절반이었다.
		# 단계는 **각성 여부만** 본다 — 레벨로 유생/아성체까지 가르는 `Growth.spine_stage` 를
		# 그대로 쓰면 저레벨 봇이 공격 모션 없는 child 로 떨어진다(위 ②). 콜로세움은 성체 이상만이다.
		var sp := _dragon_spine(int(p.get("id", 0)),
			"e" if bool(p.get("awakened", false)) else "adult")
		var ap: AnimationPlayer = null
		if sp != null:
			# 원작 makeDragonLayer 의 최종 setScale — 3v3 은 0.75 로 줄인다.
			var ds := DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO
			sp.scale *= ds
			# 스파인 기본 방향이 왼쪽이므로 **왼쪽 진영(내 팀)** 을 뒤집어 마주 보게 한다
			# (원작도 태그 11·13·15 = 내 팀만 flipX 한다).
			if mine:
				sp.scale = Vector2(-absf(sp.scale.x), sp.scale.y)
			holder.add_child(sp)
			ap = _find_anim_player(sp)

		# HUD 는 드래곤 **머리 위**다 — 종마다 키가 다르므로 실측 높이를 넘긴다.
		var dh := DRAGON_H
		var dw := DRAGON_H
		if sp != null:
			var rb := PartySelect._bounds(sp, Transform2D.IDENTITY)
			if rb.size.y > 1.0:
				dh = rb.size.y
				dw = rb.size.x
		# 🟦 2026-08-05 사용자 확정 — **1vs1 은 드래곤을 내려서 HP바를 안 가리게** 한다.
		#   1vs1 은 원작 배율이 1.0(3v3 은 0.75)이라 성체가 ~290pt 로 크고, 원작 좌표
		#   `left() + (225, −50)` 는 화면 세로 중앙이라 머리가 상단 HUD 자리까지 올라온다.
		#   HUD 를 위로 clamp 하는 대신(그러면 HUD 가 몸통에 겹친다) **드래곤을 내린다** —
		#   머리 위에 HUD + 아이콘 줄이 들어갈 만큼만, 종별 실측 높이로 자동 계산한다.
		if _mode != "team":
			var need := HUD_TOP_MIN + ICON_ROW_UP + HUD_LIFT + dh
			if y < need:
				y = need
				holder.position = Vector2(x, y)
		var hud := _make_hud(p, Vector2(x, y), dh)
		add_child(hud["root"])

		_views[tag] = {
			"node": holder, "bar": hud["fill"], "barh": hud["root"],
			# 🔴 HUD 의 라벨은 원작대로 낱말 "레벨" 이라 **이름 출처가 될 수 없다**
			#   (2026-08-05). 로그 문구용 표시 이름은 여기 따로 들고 있는다.
			"dname": String(p.get("name", "")), "icons": hud["icons"],
			"hp_label": hud["hp_label"], "anim": ap, "id": int(p.get("id", 0)),
			"element": String(p.get("element", "")),
			"awakened": bool(p.get("awakened", false)),
			# 무대 속성 일치 — `PartyStats` 가 스탯 보정과 **같은 조건**으로 채워 준다.
			"stage_buff": bool(p.get("stage_buff", false)),
			"hp": int(p.get("hp_max", 1)), "hp_max": maxi(1, int(p.get("hp_max", 1))),
			"dead": false, "pos": Vector2(x, y), "mine": mine, "slot": i,
			# 이동 연출의 **원점**. 평소엔 슬롯이고, 자리 교대 중에만 `_swap_position` 이 옮긴다.
			# 이게 없으면 공격 복귀가 "지금 자리"로 돌아가 턴마다 앞으로 밀린다(2026-08-05).
			"home": Vector2(x, y),
			"dragon_h": dh,        # 실측 스파인 높이 — 무대 버프 스파인을 몸통 중앙에 올릴 때 쓴다
			"dragon_w": dw,        # 히트테스트용(원작 boundingBox × 0.75)
			# 드래곤 터치 상태창이 읽을 **원본 레코드**(봇은 세이브에 없어 그대로 들고 온다).
			"rec": (recs[i] as Dictionary) if i < recs.size() else {},
			# 등장 연출(`_appear_intro`)이 따로 만지는 부분들.
			"spine": sp, "shadow": sh,
		}


# ---------- 등장 연출 — 원작 `MakeInterface::duelDragonAppear` @010c2464 이식 ----------
#
# 사용자 지적 2026-08-05: "전투 시작 시 드래곤이 단상 위에 올라가 있다가 단상이 사라지며
# 땅에 착지하는 연출이 원작에 있었다." — 채굴해 보니 **그 함수가 통째로 남아 있었다.**
#
# 원작이 하는 일(리터럴 그대로, `i` = 슬롯 0~5 · `dir` = 홀수 태그(내 팀) +1 / 짝수(상대) −1):
#   단상 = `Stand::create(FightManager::getStandNumber())` → `Stand::getImagePath()`,
#     드래곤 레이어 위치 −(0, 레이어높이×0.5 − **27.5**) 에 setScale(**1.0**) · z=1 로 깐다.
#   ① 단상 : Delay(1.5 + i×0.05) → MoveBy(0.1, dir×centerX) → MoveBy(0.05, −dir×10)
#            → MoveBy(0.05, +dir×10) → Delay(**2.6** − i×0.05) → FadeTo(0.25, 0) → remove
#   ② 그림자: 같은 진입 + (0, **−35**) → Delay(0.1) → FadeTo(0, 0)  [착지 전엔 안 보인다]
#            → Delay(**2.85** − i×0.05) → ScaleTo(0,0) → Spawn(FadeTo(0.25,255), ScaleTo(0.25, s+1))
#   ③ 레이어: 같은 진입 → Delay(**2.85** − i×0.05) → MoveTo(0.1, 최종 슬롯좌표)   [= 착지]
#   ④ 스파인: Delay(**4.65**) → ScaleTo(0.1, dir×−1.1, 0.9) → CallFunc → ScaleTo(0.05, dir×−0.9, 1.1)
#            → ScaleTo(0.05, −dir, 1.0)                                   [= 착지 스쿼시]
#   반환값 0x40533333 = **3.3초**(이 연출이 잡아먹는 지연).
#
# ⚠️ 스태거가 상쇄된다 — `1.5 + i×0.05` 와 `2.6/2.85 − i×0.05` 가 짝이라 **등장만 어긋나고
#   착지는 전원 동시**(단상 4.30 페이드 시작 · 레이어 4.55 낙하 · 4.65 착지)다.
#
# ⚠️ 호출부는 원작에서 `BattleScene`(Dual 계열)이다. `FightScene` 자신의 등장 연출은
#   `DragonAppearAni` 인데 그건 **혼돈의 공포(9012)/라지드(9013·9014) 보스 전용 분기**라
#   보통 드래곤에겐 아무것도 안 한다. 단상 스킨(`AccountManager::getStandSelected`)이 PvP
#   재화 상품인 것까지 보면 이 연출의 자리는 대전 화면이 맞다 ⇒ 콜로세움에 붙인다.
const APPEAR_LEAD := 1.5
const APPEAR_STAGGER := 0.05
const APPEAR_SLIDE := 0.1
const APPEAR_BOUNCE := 0.05
const APPEAR_BOUNCE_PX := 10.0
const STAND_HOLD := 2.6
const STAND_FADE := 0.25
const DROP_HOLD := 2.85
const DROP_SEC := 0.1
const LAND_AT := 4.65             # 원작 스파인 스쿼시의 절대 지연
const SQUASH := [Vector2(1.1, 0.9), Vector2(0.9, 1.1), Vector2(1.0, 1.0)]
const SQUASH_SEC := [0.1, 0.05, 0.05]
const SHADOW_DROP := 35.0
const STAND_FEET := 27.5          # 원작 −(0, h×0.5 − 27.5) 의 27.5

## 단상 스킨 프레임 키.
##
## 내 팀은 세이브가 든 것(원작 `AccountManager::getStandSelected`)을 쓴다.
## 상대는 서버가 정하던 값이라 유실 ⇒ 🟦 **사용자 확정 2026-08-05** 규칙으로 채운다:
##   초급 봇 = 기본(1번) · 중급 봇 = **랜덤** · 랭커 = 15번 ·
##   연승방지봇 누리 = 5번 · 라온·선대군 = 4번
## 랜덤은 `_rng`(전투 시드)로 굴려 같은 시드면 같은 단상이 나온다.
const STAND_GUARD := {"nuri": 5, "raon": 4, "sundaegun": 4}
const STAND_GRADE := {"novice": 1, "ranker": 15}

func _stand_key(mine: bool) -> String:
	var sman := AtlasUI.manifest(ST)
	var n := maxi(1, sman.size())
	var idx := 1
	if mine:
		idx = posmod(int(UserDB.get_skin("stand_skin")), n) + 1
	else:
		var gk := String(_foe.get("guard_key", ""))
		if STAND_GUARD.has(gk):
			idx = int(STAND_GUARD[gk])
		else:
			var grade := String(_foe.get("grade", "novice"))
			if bool(_foe.get("ranker", false)):
				grade = "ranker"
			if STAND_GRADE.has(grade):
				idx = int(STAND_GRADE[grade])
			else:
				idx = _rng.randi_range(1, n)      # 중급(adept) = 랜덤
	var key := "stand_stand%d" % idx
	return key if sman.has(key) else "stand_stand1"


## 등장 연출을 걸고 **총 소요 초**를 돌려준다(전투 개시가 이만큼 늦는다).
func _appear_intro(vis: Vector2) -> float:
	if _views.is_empty():
		return 0.0
	var ds := DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO
	var slide := vis.x * 0.5                       # 원작 MoveBy(dir × VisibleRect::center().x)
	var keys: Array = _views.keys()
	keys.sort()
	var i := -1
	for k in keys:
		i += 1
		var v: Dictionary = _views[k]
		var holder = v.get("node")
		if not (holder is Node2D) or not is_instance_valid(holder):
			continue
		var slot: Vector2 = v.get("pos", (holder as Node2D).position)
		var dir := 1.0 if bool(v.get("mine", false)) else -1.0
		var enter := APPEAR_LEAD + float(i) * APPEAR_STAGGER

		# 단상 — 밑변이 땅(슬롯 y)에 닿게 깐다.
		# # ASSUMPTION: 원작의 최종 슬롯좌표를 주는 `FUN_0105564c` 를 못 읽어서 **낙하 높이**는
		#   단상 도형에서 유도했다 — 단상 중심이 발끝보다 27.5 위(원작 상수)이고 단상 밑변이
		#   땅이므로 `lift = 그려진높이×0.5 − 27.5×드래곤배율`.
		# ⚠️ `spr_cocos` 는 **Node2D 홀더**를 돌려주고(트림 보정 스프라이트를 감싼다)
		#   안쪽에서 이미 `Design.ASSET_SCALE` 을 곱한다 ⇒ 인자에는 배율만 넘긴다.
		#   (2026-08-05: 여기서 `stand.texture` 를 읽어 스크립트 예외가 났고, 그 바람에
		#    등장 연출 전체가 중간에 끊겨 있었다. 크기는 `size_pt` 로 얻는다.)
		var skey := _stand_key(bool(v.get("mine", false)))
		var stand := AtlasUI.spr_cocos(ST, skey, ds)
		var lift := 0.0
		if stand != null:
			var sh_h := AtlasUI.size_pt(ST, skey).y * ds
			lift = maxf(0.0, sh_h * 0.5 - STAND_FEET * ds)
			stand.position = Vector2(slot.x - dir * slide, slot.y - sh_h * 0.5)
			stand.z_index = -2                     # 원작 addChild(stand, 1) — 드래곤보다 뒤
			add_child(stand)
			var stw := stand.create_tween()
			stw.tween_interval(enter)
			stw.tween_property(stand, "position:x", slot.x, APPEAR_SLIDE)
			stw.tween_property(stand, "position:x", slot.x - dir * APPEAR_BOUNCE_PX, APPEAR_BOUNCE)
			stw.tween_property(stand, "position:x", slot.x, APPEAR_BOUNCE)
			stw.tween_interval(STAND_HOLD - float(i) * APPEAR_STAGGER)
			stw.tween_property(stand, "modulate:a", 0.0, STAND_FADE)
			stw.tween_callback(stand.queue_free)

		# 드래곤 레이어 — 단상 위(공중)에서 시작해 같이 밀려 들어왔다가 착지한다.
		var air := Vector2(slot.x - dir * slide, slot.y - lift)
		(holder as Node2D).position = air
		var tw := (holder as Node2D).create_tween()
		tw.tween_interval(enter)
		tw.tween_property(holder, "position:x", slot.x, APPEAR_SLIDE)
		tw.tween_property(holder, "position:x", slot.x - dir * APPEAR_BOUNCE_PX, APPEAR_BOUNCE)
		tw.tween_property(holder, "position:x", slot.x, APPEAR_BOUNCE)
		tw.tween_interval(DROP_HOLD - float(i) * APPEAR_STAGGER)
		tw.tween_property(holder, "position:y", slot.y, DROP_SEC)

		# 그림자 — 착지 전엔 안 보이고, 착지 순간 원래 크기로 부풀며 나타난다.
		var shadow = v.get("shadow")
		if shadow is Node2D and is_instance_valid(shadow):
			var base_s: Vector2 = (shadow as Node2D).scale
			(shadow as Node2D).modulate.a = 0.0
			var sw := (shadow as Node2D).create_tween()
			sw.tween_interval(LAND_AT)
			sw.tween_callback(func() -> void:
				if is_instance_valid(shadow):
					(shadow as Node2D).scale = Vector2.ZERO)
			sw.tween_property(shadow, "modulate:a", 1.0, STAND_FADE)
			sw.parallel().tween_property(shadow, "scale", base_s, STAND_FADE)

		# HUD — 원작도 `setHUD(dragon, fVar24)` 로 **지연 뒤** 만든다(등장이 끝나야 붙는다).
		var barh = v.get("barh")
		if barh is CanvasItem and is_instance_valid(barh):
			(barh as CanvasItem).modulate.a = 0.0
			var hw := (barh as CanvasItem).create_tween()
			hw.tween_interval(LAND_AT)
			hw.tween_property(barh, "modulate:a", 1.0, STAND_FADE)

		# 착지 스쿼시 — 스파인 자체를 눌렀다 편다(원작 ④).
		var sp = v.get("spine")
		if sp is Node2D and is_instance_valid(sp):
			var bs: Vector2 = (sp as Node2D).scale
			var qw := (sp as Node2D).create_tween()
			qw.tween_interval(LAND_AT)
			for q in SQUASH.size():
				var f: Vector2 = SQUASH[q]
				qw.tween_property(sp, "scale",
					Vector2(bs.x * f.x, bs.y * f.y), float(SQUASH_SEC[q]))
	return LAND_AT + SQUASH_SEC[0] + SQUASH_SEC[1] + SQUASH_SEC[2]


# ---------- 드래곤 HUD — 원작 `MakeInterface::setHUD` @01050ffc 이식 ----------
#
# 종전엔 다른 화면 프레임(`9patch/bar_bg2` + `bar1/bar3`)으로 자작 바를 그렸다.
# 콜로세움 전용 프레임이 **네 장 다 있다**(사용자 지적 2026-08-04로 재조회):
#   `scene/colosseum/bar_cover_bg`(118×19) · `bar_cover`(156×29) · `bar_bg`(119×17) · `bar`(119×17)
#
# 원작 조립 순서(그대로 옮긴다):
#   layer = 드래곤 노드. **HUD 는 그 위 100pt**(pos = 레이어중심 + (0, h*0.5 + 100)).
#   ① `bar_cover_bg`  addChild(z=7,  tag=5)
#   ② `bar_cover`     같은 위치, addChild(z=10, tag=6)
#        └ 속성 아이콘: pos(17.5, 19.75), setScale(28.5 / 아이콘폭), addChild(z=0)
#   ③ `bar_bg`        anchor(0, 0.5), pos = cover + (15 - w*0.5, 1), addChild(z=8, tag=4)
#   ④ `bar`(채움)     anchor(0, 0.5), pos = bar_bg.pos,             addChild(z=9, tag=3)
#   ⑤ 이름 BMFont(subtitle) anchor(0,0) scale 0.5, pos = cover + (-coverW*0.5, coverH*0.5)
#   ⑥ 레벨 BMFont(subtitle) anchor(0.65,0.85), pos = 이름.pos + (이름폭, coverH*0.5)
#   ⑦ "현재 / 최대" BMFont(subtitle) scale 0.75, pos = cover + (17.5, 1.5)
#   등장 = DelayTime(d) → Show → ScaleTo(0.05, 1.1) → ScaleTo(0.05, 1.0)
#   라벨만 DelayTime(d) → DelayTime(0.25) → FadeTo(0.5, 255)

const DRAGON_H := 170.0             # `_spine_node` 정규화 높이
const HUD_LIFT := 18.0              # 원작은 100(원작 레이어 크기 기준) — 위 주석 참조
const HUD_TOP_MIN := 155.0          # 상단 프로필 판 아래로만 — 아래 ⚠️
const ICON_ROW_UP := 48.0           # 상태이상 아이콘 줄이 커버보다 위인 거리
## 🟦 2026-08-05 사용자 확정 — 원작 리터럴은 `(17.5, 19.75)` 인데 우리 커버 프레임 기준으로는
##   아이콘이 원형 구멍에서 왼쪽으로 벗어난다 ⇒ x 를 **+25** 한다(원작 값은 이 주석에 보존).
const HUD_ELEM_POS := Vector2(17.5 + 25.0, 19.75)
const HUD_ELEM_W := 28.5

func _make_hud(p: Dictionary, at: Vector2, dragon_h := DRAGON_H) -> Dictionary:
	var S := Design.ASSET_SCALE
	var root := Node2D.new()
	# 원작 pos = 레이어중심 + (0, h*0.5 + 100) = **레이어 꼭대기에서 100pt 위**.
	# ⚠️ 그 100 은 원작 드래곤 레이어 크기 기준이라 우리 정규화 높이(170)에 그대로 쓰면
	#   HUD 가 위 슬롯까지 올라간다. 구조·프레임·내부 오프셋은 원작 그대로 두고
	#   **머리 위 여백만** 우리 배치에 맞춘다(= 레이어 꼭대기 + HUD_LIFT).
	# `PartySelect._spine_node` 규약상 holder 원점 = 스프라이트 **바닥 중앙**이다.
	# ⚠️ 위 클램프는 원작에 없다 — 우리 사정이다. 원작 드래곤 레이어는 화면 위쪽 여백을 알고
	#   배치됐지만, 우리는 스파인을 native 크기로 놓기 시작하면서(2026-08-05) 앞줄 드래곤의
	#   HUD 가 상단 프로필 판(높이 ~103pt) 밑으로 파고들었다. 판 아래로만 밀어 준다.
	#   # ASSUMPTION: 원작이 이 충돌을 어떻게 피했는지(레이어 크기? 슬롯 y?)는 미확인.
	root.position = at + Vector2(0.0, -(dragon_h + HUD_LIFT))
	# 🔴 2026-08-05(사용자 지적 "뼈 부수기가 발동해도 디버프 창이 안 뜬다") —
	#   로직은 멀쩡했다(`probe_debuff_events.gd`: 이벤트에 debuff·skill_id·turns 다 있다).
	#   **상태이상 아이콘 줄이 화면 밖이었다.** 아이콘 줄은 커버보다 `ICON_ROW_UP`(48pt) 더
	#   위인데, 클램프가 커버 기준이라 HUD 가 상단에 붙는 순간 아이콘이 상단 프로필 판 뒤로
	#   숨었다 ⇒ **아이콘 줄까지 포함해서** 클램프한다.
	root.position.y = maxf(root.position.y, HUD_TOP_MIN + ICON_ROW_UP)

	var cover_bg := _spr(CO, "scene_colosseum_bar_cover_bg", S)
	if cover_bg != null:
		root.add_child(cover_bg)                       # z=7
	var cover := _spr(CO, "scene_colosseum_bar_cover", S)
	if cover != null:
		root.add_child(cover)                          # z=10
	var cover_w := 156.0 * S
	var cover_h := 29.0 * S

	# 속성 아이콘 — 원작 `FightDragon::getElementSprite()`.
	#   `element->setPosition(17.5, 19.75)` · `setScale(28.5 / contentSize.width)`
	# ⚠️ §9 규칙 2 — 원작 좌표·크기 리터럴은 **이미 포인트**다. ASSET_SCALE 을 다시 곱하지 않는다.
	#   Cocos 자식 좌표 원점 = 부모의 **좌하단** → cover 중심 기준으로 환산해 넣는다.
	var es := _element_sprite(String(p.get("element", "")))
	if es != null and cover != null:
		es.position = Vector2(HUD_ELEM_POS.x - cover_w * 0.5,
			cover_h * 0.5 - HUD_ELEM_POS.y)
		var iw := float(es.texture.get_width())
		if iw > 0.0:
			es.scale = Vector2.ONE * (HUD_ELEM_W / iw)   # 화면에 28.5pt 폭으로
		cover.add_child(es)

	# 게이지 — 원작 `bar_bg` anchor(0, 0.5), pos = cover + (15 - w*0.5, 1). `bar` 는 같은 자리.
	var bar_w := 119.0 * S
	var bar_h := 17.0 * S
	var bar_left := Vector2(15.0 - bar_w * 0.5, -1.0 - bar_h * 0.5)
	var bg := _spr(CO, "scene_colosseum_bar_bg", S)
	if bg != null:
		bg.centered = false
		bg.position = bar_left
		root.add_child(bg)                             # 원작 z=8, tag=4
	var fill := _spr(CO, "scene_colosseum_bar", S)
	if fill != null:
		fill.centered = false
		fill.position = bar_left
		fill.region_enabled = true
		fill.region_rect = Rect2(0, 0, 119, 17)
		root.add_child(fill)                           # 원작 z=9, tag=3

	# ⑤ — 🔴 2026-08-05 정정: **여기 들어가는 건 드래곤 이름이 아니라 낱말 "레벨"** 이다.
	#   원작은 `StringManager::getString(...)` 결과를 BMFont 로 찍는데, 그 키가
	#   `<ColosseumLevel>레벨</ColosseumLevel>`(stringsData_KR.xml)이고 곧바로 ⑥ 에서
	#   `FightDragon::getLevel()` 을 "%d" 로 붙인다 — 레퍼런스 스크린샷(`docs/ref/pvp/`)의
	#   "레벨 35" 가 그것이다. 종전엔 드래곤 이름을 찍어 원작에 없는 정보를 내고 있었다.
	#   cover 좌상단, anchor(0,0).
	var nm := Label.new()
	nm.text = String(Data.colosseum.get("log", {}).get("level", "레벨"))
	nm.position = Vector2(-cover_w * 0.5, -cover_h * 0.5 - 21.0)
	_bm_style(nm, 16, Color.WHITE)
	root.add_child(nm)

	# ⑥ 레벨 숫자 — 원작 anchor(0.65,0.85), 이름 오른쪽. 폭을 런타임에 못 재므로 낱말 폭만큼
	#   띄운다(같은 줄·이름 바로 오른쪽이라는 성질은 같다).
	var lv := Label.new()
	lv.text = "%d" % int(p.get("level", 1))
	lv.size = Vector2(cover_w, 22.0)
	lv.position = Vector2(-cover_w * 0.5 + 42.0, -cover_h * 0.5 - 24.0)
	_bm_style(lv, 21, Color.WHITE)
	root.add_child(lv)

	# 상태이상 아이콘 줄 — 원작 `createIcon` 이 드래곤 레이어에 태그로 붙인다(아래 §상태이상).
	# 레퍼런스에서는 "레벨" 줄 **위** 왼쪽부터 오른쪽으로 늘어선다.
	# 아이콘 중심 기준이므로 반 칸(≈21pt) 만큼 안쪽으로 들여 "레벨" 줄 **위**에 얹는다.
	var icons := Node2D.new()
	icons.position = Vector2(-cover_w * 0.5 + 22.0, -cover_h * 0.5 - ICON_ROW_UP)
	root.add_child(icons)

	# "현재 / 최대" — 원작 pos = cover + (17.5, 1.5), scale 0.75, anchor 중앙.
	var hp := Label.new()
	var hpm := maxi(1, int(p.get("hp_max", 1)))
	hp.text = "%d / %d" % [hpm, hpm]
	hp.size = Vector2(bar_w, 18.0)
	hp.position = Vector2(17.5 - bar_w * 0.5, -1.5 - 9.0)
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bm_style(hp, 13, Color.WHITE)
	root.add_child(hp)

	return {"root": root, "fill": fill, "hp_label": hp, "name_label": nm, "icons": icons}


## 속성 아이콘 — 원작 `FightDragon::getElementSprite()` @010373fc.
##
## 🔴 2026-08-05 정정(사용자 지적 "HP바 왼쪽 원형 구멍에 **정기 아이콘**이 들어가야 하는데
##   시너지 이펙트가 쓰이고 있다") — 종전의 `battle/element_%s_mark` 는 틀렸다.
##   원작 함수는 **`item/item_small/ele_*.png`**(= 속성 **정기 아이템** 아이콘)를 쓴다:
##       if (elementIndex < 9) createWithSpriteFrameName(PTR_s_item_item_small_ele_ground_png[i])
##       else                  createWithSpriteFrameName("item/item_small/ele_shadow.png")
##   테이블 첫 항목이 `ele_ground` 라 프레임 세트가 특정된다(9종 + shadow 폴백).
## ⚠️ 어휘 — 데이터의 `element` 는 aqua/earth, 프레임은 water/ground(`ELE_FRAME`).
func _element_sprite(element: String) -> Sprite2D:
	if element == "":
		return null
	# 원작의 index≥9 폴백과 같은 자리 — 표에 없는 이름이면 shadow.
	var key: String = String(ELE_FRAME.get(element, "shadow"))
	return _spr("item_small_ui", "item_item_small_ele_%s" % key, 1.0)


## 원작 BMFont(`GameManager::getFontName_subtitle`).
var _bmfonts := {}
func _bmfont(name: String) -> FontFile:
	if _bmfonts.has(name):
		return _bmfonts[name]
	var path := "res://assets/converted/font_ui/%s.fnt" % name
	if not ResourceLoader.exists(path):
		_bmfonts[name] = null
		return null
	var f: FontFile = load(path).duplicate()
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	var fb := SystemFont.new()
	fb.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Gulim"])
	f.fallbacks = [fb]
	_bmfonts[name] = f
	return f


func _bm_style(l: Label, size: int, col: Color, font := "font_subtitle") -> void:
	var f := _bmfont(font)
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE


# ---------- 상단 정보 — 원작 `MakeInterface::ColosseumFightInitWidget` @010519b0 ----------
#
# 🔴 2026-08-05 재이식(사용자 레퍼런스 `docs/ref/pvp/*.png` 대조). 종전엔 `profilebox` 를
#   9patch 로 **330×80 으로 늘려** 놓고 "닉네임\n점수" 를 한 줄 라벨로 찍었다 — 원작은
#   9patch 가 아니라 **스프라이트 원본 크기 그대로**이고, 안에 초상·티어·칭호·닉네임이 들어간다.
#
# 원작 조립(리터럴·좌표 그대로. §9 규칙 2 — 이 수치들은 이미 포인트다):
#   ① `scene/colosseum/profilebox.png`(338×77) 스프라이트, anchor(0,1)
#      pos = leftTop − (20, 0)  / 반대편은 rightTop 기준 대칭. z=15
#      등장 = MoveBy(0,+h) → Delay(3.85) → MoveBy(0.1,−h) → MoveBy(0.05,+10) → MoveBy(0.05,−10)
#   ② `common/box1.png`(50×50) = 초상 받침.
#      pos = (box1.w·0.5 + 35, plateH − box1.h·0.5 − 7.5)
#      └ 등급 테두리 `common/dragon_frame_<tier>.png`(FightManager::getScrambleBorderName) 를
#        받침 중앙에, 그 위에 초상(`getUserProfileImagePath`)을 받침에 맞춰 축소해 얹는다.
#   ③ 랭크 아이콘  pos = box1.pos + (box1.w + 5, 0), 폭이 60 을 넘으면 60/w 로 축소
#   ④ 닉네임 `CCLabelTTF(nick, "Thonburi", 20)` anchor(0,1) pos(195, 62)
#   ⑤ 칭호 이미지(`getUserTitleImagePath`) anchor(0,0) pos(195, 62), 폭 220 초과 시 축소
#   ⑥ 가운데 `scene/colosseum/vs_bg.png` + `vs.png`
#
# ⚠️ ③의 프레임은 원작에서 **서버가 준 경로**(`FightManager::getUserRankImagePath` 는 멤버
#   문자열을 그대로 돌려주는 게터다) — 레퍼런스의 ◇◇ / ★★ 이 그 자리다. 그 아트는 유실이라
#   같은 슬롯의 다른 분기(랭크시드전)가 쓰는 **`common/tier_icon_<tier>.png` 5종**을 쓴다.
#   우리 티어 사다리와 같은 축이라 의미도 맞는다(§Colosseum 티어 = 5단).
const PLATE_EDGE := 20.0            # 원작 leftTop − (20, 0)
const PLATE_AVATAR_X := 35.0
const PLATE_AVATAR_DY := 7.5
const PLATE_RANK_GAP := 5.0
const PLATE_RANK_MAX := 60.0
const PLATE_TEXT := Vector2(195.0, 62.0)
const PLATE_TITLE_MAX := 220.0
const PLATE_DROP_DELAY := 3.85      # 원작 CCDelayTime(0x40766666)

func _build_top(vis: Vector2) -> void:
	_side_plate(true, UserDB.user_nickname(), Colosseum.rating_of(_mode), vis)
	_side_plate(false, String(_foe.get("nick", "")), int(_foe.get("rating", 0)), vis)

	# 상단 가운데 VS 표식 — 원작이 부르는 건 `vs_bg`(101×90) + `vs`(79×68) 두 장이다.
	# 종전엔 `mini_vs`(30×18)를 얹어 좁쌀만 하게 나왔다(레퍼런스 대조).
	var cx := vis.x * 0.5
	var vb := _spr(CO, "scene_colosseum_vs_bg", Design.ASSET_SCALE)
	if vb != null:
		vb.position = Vector2(cx, 56.0)
		add_child(vb)
	var v := _spr(CO, "scene_colosseum_vs", Design.ASSET_SCALE)
	if v != null:
		v.position = Vector2(cx, 56.0)
		add_child(v)


## 대전 개시 연출 — 원작 `scene/colosseum/fight_spine`("FIGHT!").
##
## ⚠️ **2026-08-04 미해결**: `build_colosseum_fx.py` + `build_spine_scene.gd` 로 변환·씬 빌드는
##   끝났고(`scenes/fx/colosseum_fight.tscn`, 12본/8슬롯/anim=animation) 파일도 생기는데,
##   화면에 **아무것도 안 그려진다**(헤드리스 스크린샷 확인). 원인 미규명 —
##   슬롯 초기 가시성/스케일/앵커 중 하나로 보이나 근거 없이 만지지 않는다.
##   ⇒ 그때까지는 **보유 프레임 `vs`** 로 낸다(원작 아트다. 자작 도형이 아니다).
##   고치면 `USE_SPINE` 만 true 로 돌리면 된다.
##
## ✅ 2026-08-04 — "인트로가 중앙이 아니라 상단에 뜬다"던 종전 메모는 **내 오독이었다.**
##   실측: vis=(1230,692) · 스프라이트 pos=(615,346) = 정확히 중앙.
##   상단의 큰 흰 형체는 `_build_top` 이 상시로 까는 `vs_bg` 였다(무대 배경의 광선과도 겹쳤다).
const FIGHT_SPINE := "res://scenes/fx/colosseum_fight.tscn"
const USE_SPINE := false

func _vs_intro() -> void:
	var vis := _vis()
	if USE_SPINE and ResourceLoader.exists(FIGHT_SPINE):
		var holder := Node2D.new()
		holder.z_index = 100
		holder.position = vis * 0.5
		add_child(holder)
		var inst = (load(FIGHT_SPINE) as PackedScene).instantiate()
		holder.add_child(inst)
		var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
		if ap and ap.has_animation("animation"):
			ap.get_animation("animation").loop_mode = Animation.LOOP_NONE
			ap.play("animation")
		var tw := holder.create_tween()
		tw.tween_interval(1.4)
		tw.tween_property(holder, "modulate:a", 0.0, 0.3)
		tw.tween_callback(holder.queue_free)
		return
	var v := _spr(CO, "scene_colosseum_vs", Design.ASSET_SCALE * 1.6)
	if v != null:
		v.z_index = 100
		v.position = vis * 0.5
		add_child(v)
		var tw2 := create_tween()
		tw2.tween_interval(1.2)
		tw2.tween_property(v, "modulate:a", 0.0, 0.3)
		tw2.tween_callback(v.queue_free)


## 한쪽 진영의 프로필 판. `mine` = 왼쪽(내 쪽) / false = 오른쪽(상대) 대칭 배치.
##
## 판 안의 좌표는 **원작 그대로 cocos(좌하단 원점)** 로 적고 마지막에만 y 를 뒤집는다.
## 오른쪽 판은 x 를 판 폭 기준으로 되접는다(원작도 rightTop 기준 대칭이다).
func _side_plate(mine: bool, nick: String, rating: int, vis: Vector2) -> void:
	var S := Design.ASSET_SCALE
	var pw := 338.0 * S
	var ph := 77.0 * S
	var plate := Node2D.new()
	plate.position = Vector2(-PLATE_EDGE if mine else vis.x + PLATE_EDGE - pw, 0.0)
	add_child(plate)

	# 오른쪽 판은 **좌우 반전**이다 — 원작도 rightTop 기준 대칭이고, 레퍼런스에서 상대 쪽은
	# 초상이 바깥(오른쪽)·글자 칸이 안쪽이다. 뒤집지 않으면 글자가 판 밖으로 밀린다.
	var bg := _spr(CO, "scene_colosseum_profilebox", S)
	if bg != null:
		bg.centered = false
		if not mine:
			bg.scale.x = -bg.scale.x
			bg.position.x = pw
		plate.add_child(bg)

	# 판 안의 한 점(cocos 좌하단 원점, 포인트) → plate 로컬 Godot 좌표.
	var P := func(x: float, y: float) -> Vector2:
		return Vector2(x if mine else pw - x, ph - y)

	# ② 초상 받침 + 등급 테두리 + 초상
	var bw := 50.0 * S
	var av: Vector2 = P.call(bw * 0.5 + PLATE_AVATAR_X, ph - bw * 0.5 - PLATE_AVATAR_DY)
	var box := _spr(CM, "common_box1", S)
	if box != null:
		box.position = av
		plate.add_child(box)
	var por := _plate_portrait(mine)
	if por != null:
		# 원작: 받침에 들어가도록 가로/세로 비 중 작은 쪽으로 축소한다.
		var tw := maxf(1.0, float(por.texture.get_width()))
		var th := maxf(1.0, float(por.texture.get_height()))
		por.scale = Vector2.ONE * minf(bw / tw, bw / th)
		por.position = av
		plate.add_child(por)
	# 등급 테두리 = 원작 `getScrambleBorderName` → `common/dragon_frame_<tier>.png`.
	var bf := Colosseum.tier_frame(rating, "dragon")
	if bf != "":
		var bs := _spr(CM, _frame_key(bf), S)
		if bs != null:
			bs.position = av
			plate.add_child(bs)

	# ③ 랭크 아이콘(우리는 티어 아이콘 — 위 ⚠️)
	var tf := Colosseum.tier_frame(rating, "icon")
	if tf != "":
		var ts := _spr(CM, _frame_key(tf), S)
		if ts != null:
			var iw := float(ts.texture.get_width()) * S
			if iw > PLATE_RANK_MAX:
				ts.scale *= PLATE_RANK_MAX / iw
			ts.position = av + Vector2((bw + PLATE_RANK_GAP + iw * 0.5) * (1.0 if mine else -1.0),
				0.0)
			plate.add_child(ts)

	# ⑤ 칭호 이미지 — 원작 `getUserTitleImagePath`. 우리 칭호 아트는 `title_<no>_kr`.
	var anchor: Vector2 = P.call(PLATE_TEXT.x, PLATE_TEXT.y)
	var tno := UserDB.user_title_no() if mine else 0
	var tpath := "res://assets/converted/%s/title_%d_kr.tres" % [
		String(Data.titles.get("atlas_dir", "title_ui")), tno]
	if tno > 0 and ResourceLoader.exists(tpath):
		var tt: Texture2D = load(tpath)
		var tr := Sprite2D.new()
		tr.texture = tt
		tr.centered = false
		tr.material = _pma
		var tws := float(tt.get_width()) * S
		var tsc := S * (PLATE_TITLE_MAX / tws if tws > PLATE_TITLE_MAX else 1.0)
		tr.scale = Vector2(tsc, tsc)
		var thh := float(tt.get_height()) * tsc
		tr.position = Vector2(anchor.x if mine else anchor.x - float(tt.get_width()) * tsc,
			anchor.y - thh)
		plate.add_child(tr)

	# ④ 닉네임 — 원작 CCLabelTTF("Thonburi", 20). 한글이라 우리 TTF 로 낸다.
	var l := Label.new()
	l.text = nick
	l.size = Vector2(pw - PLATE_TEXT.x - 24.0, 28.0)
	l.position = Vector2(anchor.x if mine else anchor.x - l.size.x, anchor.y)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if mine else HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 20)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(l)

	# 등장 — 원작 MoveBy(0,+h) → Delay(3.85) → MoveBy(0.1,−h) → MoveBy(0.05,+10) → (0.05,−10).
	# Cocos +y 는 위, Godot 은 아래이므로 부호를 뒤집는다.
	var home := plate.position
	plate.position = home - Vector2(0.0, ph)
	var tw2 := plate.create_tween()
	tw2.tween_interval(PLATE_DROP_DELAY)
	tw2.tween_property(plate, "position", home, 0.1)
	tw2.tween_property(plate, "position", home - Vector2(0.0, 10.0), 0.05)
	tw2.tween_property(plate, "position", home, 0.05)


## `Colosseum.tier_frame` 는 원작 경로("common/tier_icon_gold.png")를 돌려준다 → 매니페스트 키로.
func _frame_key(path: String) -> String:
	return path.replace("/", "_").replace(".png", "")


## 프로필 초상 — 원작 `getUserProfileImagePath`(유저가 지정한 사진/드래곤).
## 우리는 메인 HUD 와 같은 규약을 쓴다: 내 쪽 = 활성 드래곤, 상대 = 선두 드래곤.
func _plate_portrait(mine: bool) -> Sprite2D:
	var did := 0
	if mine:
		var a := UserDB.active_dragon()
		did = int(a.get("id", 0))
	elif not _fo.is_empty():
		did = int((_fo[0] as Dictionary).get("id", 0))
	if did <= 0:
		return null
	var dir := "portrait_%d" % did
	var man := _man(dir)
	for stage in ["evolution", "adult"]:
		var k := "dragon_dragon_%d_box_%s" % [did, stage]
		if man.has(k):
			return _spr(dir, k, 1.0)
	return null


# ---------- 하단 로그 — 원작 `ColosseumTextBox::init` @010327c0 이식 ----------
#
# 🔴 2026-08-05 재이식(레퍼런스 `docs/ref/pvp/*.png` 대조). 종전엔 높이 66 짜리 상자에
#   한 줄 라벨만 있었고 **배속·SKIP·접기 버튼이 통째로 빠져 있었다**.
#
# 원작 조립(리터럴·좌표 그대로):
#   레이어 anchor(0.5,0), pos = VisibleRect::bottom + (0, 10)
#   ① `9patch/dialogue_box.png` 스케일9, contentSize = (visW − 20, 90)
#   ② `common/btn_up.png` 접기/펼치기 — pos = (boxW − 50, boxH·0.5)
#      (`foldTextBox`/`spreadTextBox` 가 짝. 우리는 줄 수만 바꾼다)
#   ③ SKIP `scene/adventure/bt_skip_%s.png` — pos = boxSize + (−skipW·0.5, 30) = 상자 위 오른쪽
#   ④ 배속 `scene/colosseum/btn_forward.png` — pos = (btnW·0.5, boxH + 30) = 상자 위 왼쪽
#      └ `CCString("x%d", getFightTimeScale())` BMFont(subtitle) at 버튼중심 + (−15, 12.5), scale 1.25
#   ⑤ 본문 CCScrollView size = (boxW − 125, boxH − 22.5) at (25, 20)
#   등장 = Delay(param) → Delay(0.6) → 메뉴 켜기
const LOG_H := 90.0
const LOG_MARGIN := 20.0
const LOG_BOTTOM := 10.0
const LOG_BTN_LIFT := 30.0
const LOG_FOLD_INSET := 50.0
const LOG_TEXT_PAD := Vector2(25.0, 20.0)
const LOG_TEXT_TRIM := Vector2(125.0, 22.5)
const SPEEDS := [1, 2, 3]           # 원작 FightManager::getFightTimeScale
const LOG_LINES := 2                # 접힌 상태(레퍼런스 2줄) ↔ 펼치면 더 보인다

var _log_host: Control
var _log_box: NinePatchRect
var _log_lines: Array[String] = []
var _speed_label: Label
var _speed := 1
var _folded := true
var _skipped := false

func _build_log(vis: Vector2) -> void:
	var bw := vis.x - LOG_MARGIN
	var host := Control.new()
	host.position = Vector2(LOG_MARGIN * 0.5, vis.y - LOG_BOTTOM - LOG_H)
	host.size = Vector2(bw, LOG_H)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)
	_log_host = host

	_log_box = _nine("9patch_dialogue_box", host.size, Rect2(10, 10, 4, 4))
	if _log_box != null:
		host.add_child(_log_box)

	_log = Label.new()
	_log.position = LOG_TEXT_PAD
	_log.size = host.size - LOG_TEXT_TRIM
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.add_theme_font_size_override("font_size", 19)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(_log)

	# ② 접기/펼치기 ▲
	var up := _btn(CM, "common_btn_up", host,
		Vector2(bw - LOG_FOLD_INSET, LOG_H * 0.5), _toggle_fold)
	if up != null:
		up.rotation = 0.0

	# ③ SKIP — 남은 이벤트를 즉시 소화하고 결과로 간다(원작 onClickSkipBattle 과 같은 역할).
	var sk: Dictionary = _man("adventure_ui").get("scene_adventure_bt_skip_kr", {})
	var skw := float(sk.get("w", 71)) * Design.ASSET_SCALE
	_btn("adventure_ui", "scene_adventure_bt_skip_kr", host,
		Vector2(bw - skw * 0.5, -LOG_BTN_LIFT), _on_skip)

	# ④ 배속
	var fw := float((_man(CO).get("scene_colosseum_btn_forward", {}) as Dictionary).get("w", 81))
	var fwp := fw * Design.ASSET_SCALE
	var fb := _btn(CO, "scene_colosseum_btn_forward", host,
		Vector2(fwp * 0.5, -LOG_BTN_LIFT), _cycle_speed)
	_speed_label = Label.new()
	_speed_label.text = "x%d" % _speed
	_speed_label.size = Vector2(60.0, 24.0)
	# 원작 라벨 offset (−15, +12.5) — cocos y-up 이라 Godot 은 위로 12.5.
	_speed_label.position = Vector2(fwp * 0.5 - 15.0 - 30.0, -LOG_BTN_LIFT - 12.5 - 12.0)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bm_style(_speed_label, 17, Color(0.25, 0.2, 0.15))
	_speed_label.scale = Vector2.ONE * 1.25           # 원작 setScale(1.25)
	if fb != null:
		host.add_child(_speed_label)


## 상자 위/안의 원작 버튼 하나. 프레임 원본 크기 그대로 쓰고 클릭만 우리가 붙인다.
func _btn(dir: String, key: String, host: Control, at: Vector2, cb: Callable) -> TextureButton:
	var t := _tex(dir, key)
	if t == null:
		return null
	var b := TextureButton.new()
	b.texture_normal = t
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.size = Vector2(t.get_width(), t.get_height()) * Design.ASSET_SCALE
	b.position = at - b.size * 0.5
	b.material = _pma
	b.pressed.connect(cb)
	host.add_child(b)
	return b


func _toggle_fold() -> void:
	# 원작 `foldTextBox`/`spreadTextBox` — 접힘(2줄) ↔ 펼침(상자를 키워 더 많이 보여 준다).
	_folded = not _folded
	var vis := _vis()
	var h := LOG_H if _folded else LOG_H * 2.2
	_log_host.position.y = vis.y - LOG_BOTTOM - h
	_log_host.size.y = h
	if _log_box != null:
		_log_box.size.y = h
	if _log != null:
		_log.size.y = h - LOG_TEXT_TRIM.y
	_render_log()


func _cycle_speed() -> void:
	_speed = SPEEDS[(SPEEDS.find(_speed) + 1) % SPEEDS.size()]
	if _speed_label != null:
		_speed_label.text = "x%d" % _speed


func _on_skip() -> void:
	_skipped = true


func _say(t: String) -> void:
	_log_lines.append(t)
	if _log_lines.size() > 12:
		_log_lines = _log_lines.slice(_log_lines.size() - 12)
	_render_log()


func _render_log() -> void:
	if _log == null:
		return
	var n := LOG_LINES if _folded else 6
	var take: Array = _log_lines.slice(maxi(0, _log_lines.size() - n))
	_log.text = "\n".join(PackedStringArray(take))


# ---------- 전투 재생 ----------
#
# 원작 `FightScene::setActionParam` 이 서버 액션 큐를 훑던 자리.
# 우리는 `Battle.simulate()` 이벤트 배열을 같은 방식으로 훑는다.

## `intro_delay` = 개시 연출(무대 룰렛)이 끝날 때까지의 초. 시뮬레이션 자체는 바로 돌리고
## **재생만** 미룬다 — 원작도 액션 큐는 이미 손에 있고 `setActionParam` 만 지연시킨다.
func _start(intro_delay := 0.0) -> void:
	var cfg := _json("res://data/combat.json")
	var skills := _json("res://data/skills.json")
	var pa := _combatants(_my, "ally")
	var pb := _combatants(_fo, "enemy")
	var res: Dictionary = Battle.simulate(pa, pb, _rng, cfg, skills)
	_events = res.get("events", [])
	_winner = String(res.get("winner", ""))
	if intro_delay > 0.0:
		var gen := _gen
		await get_tree().create_timer(intro_delay).timeout
		if gen != _gen:
			return
	_play()


## 요약 행 → 전투원. **탐험 전투(`battle.gd::_run_and_replay`)와 같은 조립**이다.
##
## 🔴 2026-08-05 정정 — 종전엔 스탯만 넘겨서 콜로세움 전투에 **스킬·각성스킬·장비 조건부
##   효과가 하나도 안 들어갔다**(양 진영 모두). 스킬 2칸이 무의미했고, 연승방지봇 시트의
##   스킬·장비 칸도 그림의 떡이었다. 넘겨야 하는 필드는 `make_combatant` 인자 목록 그대로다.
func _combatants(team: Array, side: String) -> Array:
	var out: Array = []
	for i in team.size():
		var p: Dictionary = team[i]
		var c := Battle.make_combatant(("A%d" if side == "ally" else "E%d") % i,
			side, String(p.get("element", "")), p.get("stats", {}), 0.0,
			p.get("skills", []), p.get("skill_slots", []))
		c["hp_max"] = int(p.get("hp_max", c["hp_max"]))
		c["hp"] = int(p.get("hp", c["hp_max"]))
		# 각성 스킬·장비 효과는 `_apply_passives`(전투 시작 전)가 이미 산출해 뒀다 —
		# 체력은 위에서 값으로 들어왔고, 나머지는 효과 목록으로 옮긴다.
		c["awaken_no"] = int(p.get("awaken_skill", 0))
		c["grade"] = float(p.get("grade", 0.0))
		c["dragon_id"] = int(p.get("id", 0))
		c["atk_type"] = String(p.get("atk_type", ""))
		c["awaken_gauge"] = float(p.get("awaken_gauge", 0.0))
		for e in (p.get("awaken_effects", []) as Array):
			(c["effects"] as Array).append((e as Dictionary).duplicate())
		out.append(c)
	return out


## 각성 스킬 + 장비 조건부 효과를 **양 진영에** 얹는다.
##
## 원작은 서버가 계산해 결과만 내려줬다 — 우리는 탐험 전투와 **같은 함수**(`PartyStats.apply_passives`)
## 를 쓴다. 상대 쪽도 같은 대우를 받아야 봇의 전용 장비(선대군의 `한울의 불꽃` 등)가 산다.
## 조건 판정용 '적'은 상대 진영 첫 드래곤의 더미다(원작도 이 단계에선 더미만 본다).
func _apply_passives() -> void:
	var mine_head: Dictionary = _my[0] if not _my.is_empty() else {}
	var foe_head: Dictionary = _fo[0] if not _fo.is_empty() else {}
	var ctx := {"field_element": String(_stage.get("element", "")), "enemy_boss": false}
	if not _my.is_empty():
		PartyStats.apply_passives(_my, {"element": String(foe_head.get("element", "")),
			"hp": int(foe_head.get("hp_max", 1))}, ctx)
	if not _fo.is_empty():
		PartyStats.apply_passives(_fo, {"element": String(mine_head.get("element", "")),
			"hp": int(mine_head.get("hp_max", 1))}, ctx)


## 연승방지봇의 등장 대사 — **줄 하나가 대화창 하나**다(🟦 사용자 확정 2026-08-05).
##
## 라온·누리 대사는 원작 그대로(`ColosseumRaonTalk*`/`ColosseumNuriTalk*`)이고 어느 단계를
## 쓰는지는 연승 스케줄이 정한다(25 누리A · 50 라온A · 75 누리B · 100 라온B · 150 라온C).
## 선대군은 사용자 CSV(`docs/input/sheets/colosseum_guard.csv`)다 — 그 칸에서
## `(최초 조우 시)` / `(반복)` 두 벌로 갈라 적을 수 있고, 어느 쪽을 쓸지는 로직이
## 이미 정해서 넘겨 준다(`Colosseum.make_guard` → `first_meet`).
##
## 표시는 마을 NPC 대화와 **같은 위젯**(`NpcTalkLayer` = 원작 `ScenarioTextBox` + 중앙 화자)이라
## 타자기·▶화살표·탭 넘기기가 그대로 온다. 초상은 `data/npc_face.json` 키(= 방지봇 키)로 찾고,
## 원작에 없는 오리지널 캐릭터(선대군)는 초상 없이 대사창만 뜬다.
func _guard_talk() -> void:
	var gen := _gen
	var lines: Array = _foe.get("lines", [])
	var firsts: Array = _foe.get("lines_first", [])
	if bool(_foe.get("first_meet", false)) and not firsts.is_empty():
		lines = firsts
	if lines.is_empty():
		return
	var nick := String(_foe.get("nick", ""))
	var npc := String(_foe.get("guard_key", ""))
	var tl := NpcTalkLayer.open(self, npc if NpcPortrait.has_art(npc) else "", nick, "")
	for ln in lines:
		if _skipped or gen != _gen or not is_instance_valid(tl):
			break
		# ⚠️ 전투 로그(`_say`)에 같이 남기지 않는다 — 로그 상자와 대사창이 **같은 자리**라
		#    글자가 겹쳐 보인다(2026-08-05 캡처 검수).
		tl.set_text(String(ln))
		await tl.advanced
		# ⚠️ 한 프레임 쉬고 다음 줄로 간다. 바로 이어 붙이면 **아직 emit 중인 신호**에 다음
		#    `await` 가 연결돼 그 한 번의 탭이 남은 줄을 통째로 밀어 버린다(실측 2026-08-05).
		await get_tree().process_frame
	if is_instance_valid(tl):
		tl.close()


func _play() -> void:
	var gen := _gen
	await _guard_talk()
	if gen != _gen: return
	_say("%s 와(과)의 대전!" % String(_foe.get("nick", "")))
	_vs_intro()                 # 원작 fight_spine("FIGHT!") 개시 연출
	await _wait(1.8)
	if gen != _gen: return
	for ev in _events:
		# SKIP — 원작 `MakeInterface::onClickSkipBattle`. 남은 이벤트는 **결과만** 반영하고
		# 연출을 건너뛴다(로직 결과는 이미 정해져 있으므로 승패는 바뀌지 않는다).
		if _skipped:
			_apply_silent(ev)
			continue
		_apply(ev)
		# 원작 간격 = 애니 길이 + 0.5(복귀) + 0.5(다음까지). 애니 길이를 모르는 이벤트는 짧게.
		await _wait(_evt_delay(ev))
		if gen != _gen: return
	await _wait(0.5)
	if gen != _gen: return
	_finish()


## 이벤트 사이 간격 — 원작은 `Delay(getDuration(anim) + 0.5)` + `Delay(0.5)` 로 벌린다.
## 실제 애니 길이는 `_motion` 이 재생하며 알게 되므로 여기선 종류별 대표값을 쓴다.
func _evt_delay(ev: Dictionary) -> float:
	match String(ev.get("type", "")):
		"awaken":
			# 🔴 2026-08-05 — 종전 2.0 초는 자작이었다. 원작 `UltimateLayer::getDuration()`
			#   @01001200 이 읽는 표(`UltimateFx.DURATION`, 콜로세움 `DAT_021af294`)가
			#   **속성별 9.0~12.0초**다. 2초에 다음 이벤트로 넘어가면 각성기 연출이 도는
			#   동안 뒤 전투가 겹쳐 재생된다(사용자 지적 "연출이 원작과 다르다"의 한 갈래).
			var av: Dictionary = _views.get(_actor_tag(ev), {})
			return float(UltimateFx.DURATION.get(String(av.get("element", "")), 2.0))
		"normal", "double":
			# 🟦 크리티컬은 모션이 길어졌으므로(위 `CRIT_ANIM_SPEED`) 다음 이벤트도 그만큼 미룬다.
			return 2.1 if bool(ev.get("crit", false)) else 1.15
		"dot", "effect_tick":
			return 0.35
	return 0.7


## 이벤트 1건을 화면에 반영 — HP 감소 · 데미지 숫자 · 사망 처리.
func _apply(ev: Dictionary) -> void:
	var t := String(ev.get("type", ""))
	# 🔴 2026-08-05 — `confused`/`status_skip` 은 **피격자 칸이 없고 `actor` 만** 있다.
	#   종전엔 여기서 곧장 return 해 버려 혼란·기절이 화면에 전혀 안 나왔다.
	var dfn := String(ev.get("defender", ev.get("target", "")))
	if dfn == "" and t in ["confused", "status_skip"]:
		dfn = String(ev.get("actor", ""))
	var dmg := int(ev.get("damage", 0))
	if dfn == "" or not _views.has(dfn):
		return
	var v: Dictionary = _views[dfn]

	# 🔴 2026-08-05(사용자 지적) — 상태이상 아이콘이 **붙기만 하고 갱신·제거가 없었다.**
	#   `Battle.simulate` 는 소유자 행동 뒤마다 `{type:"effect_tick", target, source(스킬id),
	#   turns(남은 턴)}` 을 흘려 준다. 그걸 안 읽어서 숫자가 안 줄고, 만료돼도 안 사라졌다.
	if t == "effect_tick":
		_tick_icon(v, int(ev.get("source", 0)), int(ev.get("turns", 0)))
		return
	#   빛의 정화(26)는 대상마다 `cleanse: true` 를 낸다 — 그 대상의 **해로운** 아이콘을 지운다.
	if bool(ev.get("cleanse", false)):
		_clear_debuff_icons(v)

	_motion(ev, t, _actor_tag(ev), dfn)                   # 스파인 공격/피격 모션
	if bool(ev.get("miss", false)):
		# 회피 워드아트는 `_evade_effect`(원작 evadeEffect)가 낸다 — 여기서 또 찍지 않는다.
		_log_line(ev, t, dfn, 0, 0)
		return
	# 🔴 각성기는 **연출 도중에** 맞는다 — 원작 `getDamageTextTime()` @01020e4c 이
	#   속성별로 5.5~8.65초를 준다(불 7.8 · 땅 5.5 …). 종전엔 각성기 시작과 동시에 피가 깎여
	#   9~12초짜리 연출이 도는 내내 결과가 이미 나와 있었다.
	if t == "awaken":
		var atk_v: Dictionary = _views.get(_actor_tag(ev), {})
		# 시전 줄은 지금(연출 시작) 낸다 — 피해 줄은 아래 `_apply_hit` → `_log_line` 이 낸다.
		var LU: Dictionary = Data.colosseum.get("log", {})
		if not LU.is_empty():
			_say(String(LU.get("ultimate", "")) % _who(_actor_tag(ev)))
		_ultimate_damage(ev, t, dfn, v, String(atk_v.get("element", "")))
		return
	_apply_hit(ev, t, dfn, v)


## ---------- 각성기 피해 **분할 표시** — 원작 `UltimateLayer::calculateDamage` @0100f070 ----------
##
## 🔵 2026-08-05 백로그 9-5 재조사 결론 — **수치 계산은 여기 없다.**
##   `calculateDamage(FightDragon* 대상, int 피해)` 는 피해를 **인자로 받는다**.
##   그 인자의 출처는 `FightScene` @00f8cd6c 의 `UltimateLayer::setDamage(this, a, b, c)` 이고,
##   a/b/c 는 서버 전투 로그에서 읽은 값이다(메모리 `dv2-battle-is-server-replay`).
##   ⇒ 우리 각성기 피해 **수치는 계속 `Battle.simulate()` 소유**다. 원작 공식으로 대체 불가 —
##     클라이언트에 그 공식이 애초에 없다.
##
##   대신 이 함수가 진짜로 쥐고 있는 것은 **표시 방식**이다: 총 피해를 속성마다 다른 횟수·시각으로
##   쪼개 `showDamage` + `damagedEffect` 를 예약한다. 우리는 숫자를 **한 번** 띄우고 있었으므로
##   그 부분은 이식 대상이 맞다. 아래 표는 전부 실측.
##
##   | el | 잔타(각 share 비율) | 마무리 |
##   |---|---|---|
##   | aqua   | 4.6 + i×0.1 (10회) · 각 **1**(총 피해 50 이상일 때만) | 7.3 |
##   | chaos  | 없음 | 7.45 |
##   | dark   | 4.75 + cumsum[0,.2,.2,.2,.15,.1×10] (15회) · D/30 | 7.9 |
##   | earth  | 1.75 + i×0.5 (4회) + 4.15 (1회) · D/10 | 4.75 |
##   | fire   | `UltimateFx.FIRE_DELAYS[i] + 1.5` (6회) · D/20 | FIRE_DELAYS[6] + 1.5 = 4.8 |
##   | holy   | 7.0 · 7.25 (2회) · D/3 | 7.5 |
##   | light  | 2.5(1) + 3.25 + cumsum(0.27 − 0.009(i+1)) (30회) · D/31 | 마지막 잔타 ≈ 7.165 |
##   | wind   | 2.1(1) + 2.75 + i×0.1 (45회) · D/46 | 마지막 잔타 = 7.15 |
##   | shadow | 2.75 + i×0.5 (4회) + 5.15 (1회) · D/10 | 5.25 |
##
##   ⚪ 원작이 잔타마다 얹는 `rand()` 흔들림(±D/60 등)은 **넣지 않았다** — 눈에만 보이는
##      난수라 이식 이득이 없고, 합계가 마무리 타로 정확히 떨어지는 편이 낫다.
##   ⚠️ `getDamageTextTime`(= `UltimateFx.DMG_TIME`)과 값이 다르다. 실제로 숫자를 예약하는
##      쪽은 이 함수이므로 **마무리 시각은 여기 표를 따른다**(fire 7.8 → 4.8 등).

## `[잔타 시각들, 잔타 1회 몫(비율), 마무리 시각]`
static func _ult_dmg_plan(element: String) -> Array:
	match element:
		"aqua":
			var a: Array = []
			for i in 10:
				a.append(4.6 + float(i) * 0.1)
			return [a, -1.0, 7.3]              # −1 = 비율이 아니라 **1 고정**
		"chaos":
			return [[], 0.0, 7.45]
		"dark":
			var step := [0.0, 0.2, 0.2, 0.2, 0.15, 0.1, 0.1, 0.1, 0.1, 0.1,
				0.1, 0.1, 0.1, 0.1, 0.1]        # `.rodata` DAT_021a8150
			var a: Array = []
			var t := 4.75
			for s: float in step:
				t += s
				a.append(t)
			return [a, 1.0 / 30.0, 7.9]
		"earth":
			return [[1.75, 2.25, 2.75, 3.25, 4.15], 1.0 / 10.0, 4.75]
		"shadow":
			return [[2.75, 3.25, 3.75, 4.25, 5.15], 1.0 / 10.0, 5.25]
		"fire":
			var a: Array = []
			for i in 6:
				a.append(float(UltimateFx.FIRE_DELAYS[i]) + 1.5)
			return [a, 1.0 / 20.0, float(UltimateFx.FIRE_DELAYS[6]) + 1.5]
		"holy":
			return [[7.0, 7.25], 1.0 / 3.0, 7.5]
		"light":
			var a: Array = []
			var t := 3.25
			for i in 30:
				t += 0.27 - 0.009 * float(i + 1)
				a.append(t)
			var last: float = a.pop_back()
			a.push_front(2.5)
			return [a, 1.0 / 31.0, last]
		"wind":
			var a: Array = [2.1]
			for i in 44:
				a.append(2.75 + float(i) * 0.1)
			return [a, 1.0 / 46.0, 2.75 + 44.0 * 0.1]
	return [[], 0.0, 8.0]


func _ultimate_damage(ev: Dictionary, t: String, dfn: String, v: Dictionary, element: String) -> void:
	var plan := _ult_dmg_plan(element)
	var chips: Array = plan[0]
	var share := float(plan[1])
	var last := float(plan[2]) / maxf(0.05, float(_speed))
	var total := int(ev.get("damage", 0))
	_ultimate_knockback(v, last, element)
	var gen := _gen
	var spent := 0
	for ct: float in chips:
		var amount := 1 if share < 0.0 else int(float(total) * share)
		if share < 0.0 and total < 50:
			amount = 0                          # 원작 `param_2 < -50` 가드
		amount = clampi(amount, 0, maxi(0, total - spent - 1))
		if amount <= 0:
			continue
		spent += amount
		var a := amount
		get_tree().create_timer(ct / maxf(0.05, float(_speed))).timeout.connect(func() -> void:
			if not is_instance_valid(self) or gen != _gen or bool(v.get("dead", false)):
				return
			v["hp"] = maxi(0, int(v["hp"]) - a)
			_set_bar(v)
			_float_text(v["pos"], str(a), Color(1, 1, 1)))
	# 마무리 타 — 나머지를 싣고 사망·로그까지 여기서 낸다(원작도 마지막 호출만 flag=1).
	var ev2 := ev.duplicate(true)
	ev2["damage"] = maxi(0, total - spent)
	get_tree().create_timer(last).timeout.connect(func() -> void:
		if is_instance_valid(self) and gen == _gen:
			_apply_hit(ev2, t, dfn, v))


## 각성기 피격 반응 — 원작 `damage<El>_C` 가 대상에게 거는 것.
## `damageEarth_C` 실측: `JumpBy(0.2, …, S×150)` 을 0.3초 간격으로 **네 번** 저글링한 뒤
## `JumpBy(…, S×800)` 으로 **높이 띄운다**. 마지막 큰 점프가 피해 표시 시각과 맞물린다.
const ULT_KNOCK_SEC := 0.2
const ULT_KNOCK_GAP := 0.3
const ULT_KNOCK_N := 4
const ULT_KNOCK_H := 150.0
const ULT_LAUNCH_H := 800.0

## 속성별 피격 반응 — 원작 `damage<El>_C` 실측(2026-08-05 `resolve_actions.py`).
##   [시작초, 저글링 횟수, 저글링 1회 시간, 저글링 간격, 저글링 높이(×S), 마무리 높이(×S)]
## 공통 골격: `Delay(T)` → `JumpTo(0.25, 무대, S*150, 1)` → `JumpBy(t, …, S*h, 1)` 반복
##   → 마지막에 크게 띄운다. 땅은 S*800, 그림자는 S*1000 으로 가장 크게 난다.
## ⚪ 원작이 저글링마다 같이 거는 몸통 스쿼시(`ScaleTo(0.1, ×1.05, 0.95)`)와
##   `MakeInterface::shakeLayerToVertical`(화면 흔들기)은 아직 안 넣었다 — 아래 §백로그.
const ULT_KNOCK := {
	"aqua":   [1.0,  1, 0.25, 0.5,  150.0, 175.0],
	"chaos":  [1.95, 1, 6.0,  0.0,  30.0,  30.0],
	"dark":   [2.75, 1, 0.25, 1.25, 100.0, 300.0],
	"earth":  [1.0,  4, 0.2,  0.3,  150.0, 800.0],
	# fire = 감쇠 연타 20타(0.5→0.1초 · 높이 200→50, damageFire_C L1505)의 근사 —
	# 잦은 타수·짧은 간격이 영상의 "폭발마다 튀는" 저글링을 낸다.
	"fire":   [1.0,  14, 0.18, 0.03, 150.0, 150.0],
	"holy":   [4.5,  1, 0.95, 0.2,  100.0, 100.0],
	"light":  [2.5,  2, 0.1,  0.05, 75.0,  150.0],
	"shadow": [3.0,  5, 0.2,  0.2,  150.0, 1000.0],
	"wind":   [1.0,  5, 0.25, 0.3,  120.0, 200.0],
}

func _ultimate_knockback(v: Dictionary, at_sec: float, element := "") -> void:
	var n = v.get("node")
	if not (n is Node2D) or not is_instance_valid(n) or bool(v.get("dead", false)):
		return
	var node := n as Node2D
	var s := DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO
	var home: Vector2 = v.get("home", node.position)
	var k: Array = ULT_KNOCK.get(element, [1.0, 4, 0.2, 0.3, 150.0, 800.0])
	var n_j := int(k[1])
	var sec := float(k[2])
	var gap := float(k[3])
	var hop := float(k[4])
	var big := float(k[5])
	# 🔴 2026-08-05 재작성 — `damageFire_C` 실측(sequences.md L1505):
	#   Delay(1.0) → **JumpTo(0.25, 무대점, S×150)** ← 피격자가 연출 지점으로 끌려간다
	#   → 감쇠 저글링(S×200→50, 매 타 shakeLayerToVertical) → … → JumpTo(0.25, 제자리, S×150)
	#   종전엔 ① 무대점 이동이 없어 피격자가 슬롯에서 튀었고 ② 높이에 ×0.35 를 곱해
	#   원작(영상: 화면 절반까지 던져진다)보다 훨씬 낮았다.
	var vis := _vis()
	var stage := Vector2(ULT_DX if bool(v.get("mine", false)) else vis.x - ULT_DX,
		vis.y * 0.5 + ULT_DROP)
	# 어둠 — 피격자는 무대점이 아니라 **소용돌이 중심**(화면 중앙 중단)으로 빨려 들어가
	# 그 안에서 저글링당하다 폭발에 튕겨 나온다(영상 51.25~53.5s 실측).
	if element == "dark":
		stage = Vector2(vis.x * 0.5, vis.y * 0.45)
	var lead := maxf(float(k[0]), at_sec - (sec + gap) * float(n_j) - 0.6)
	var old = v.get("move_tw")
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	# 선행 포즈 — 원작 `damage<El>_C`(물 = 침수에 `down` → 물고기 떼에 `love`).
	for pre in UltimateFx.TGT_PRE_POSE.get(element, []):
		var pt := node.create_tween()
		pt.tween_interval(maxf(0.01, float(pre[0])))
		var pname := String(pre[1])
		pt.tween_callback(func() -> void: _play_anim(v, pname))
	var t := create_tween()
	v["move_tw"] = t
	t.tween_interval(lead - 0.25)
	_tween_jump(t, node, home, stage, 150.0 * s, 0.25, 1.0)   # 무대점으로 끌려간다
	for i in n_j:
		# 타격마다 — 피격음(두 음원 교대, 원작 볼륨식) + **damaged 재생**(원작은 연타마다
		# runSpine "damaged" 를 다시 튼다 — fire 13·dark 13·shadow 15회 실측).
		var hit_track := "effect_dragon_damaged_%d" % (1 + i % 2)
		t.tween_callback(func() -> void:
			Bgm.sfx(hit_track, float(randi() % 6) * 0.05 + 0.25)
			_play_anim(v, "damaged"))
		var d := Vector2((-40.0 if bool(v.get("mine", false)) else 40.0) * 0.5, 0.0)
		_tween_jump(t, node, stage + d * float(i), stage + d * float(i + 1),
			hop * s, sec, 1.0)
		t.tween_interval(gap)
	# 마지막 — `down` 으로 엎어진 채 크게 띄워졌다가 제자리로, `wait` 복귀(원작 3단계).
	t.tween_callback(func() -> void: _play_anim(v, "down"))
	_tween_jump(t, node, node.position, stage, big * s, 0.6, 1.0)
	t.tween_interval(0.35)
	_tween_jump(t, node, stage, home, 150.0 * s, 0.25, 1.0)
	t.tween_callback(func() -> void:
		if is_instance_valid(node):
			node.position = v.get("home", home)
		var ap = v.get("anim")
		if ap is AnimationPlayer and is_instance_valid(ap) \
				and (ap as AnimationPlayer).has_animation("wait"):
			(ap as AnimationPlayer).get_animation("wait").loop_mode = Animation.LOOP_LINEAR
			(ap as AnimationPlayer).play("wait"))



## 피격 결과(HP·수치·사망)를 실제로 반영한다. 각성기만 시각을 늦춰 부른다.
func _apply_hit(ev: Dictionary, t: String, dfn: String, v: Dictionary) -> void:
	var dmg := int(ev.get("damage", 0))
	if dmg > 0:
		v["hp"] = maxi(0, int(v["hp"]) - dmg)
		_set_bar(v)
		var col := Color(1.0, 0.85, 0.3) if bool(ev.get("crit", false)) else Color(1, 1, 1)
		_float_text(v["pos"], str(dmg), col)
	# 방어 스킬 발동(철갑 방패·신의 결계·복수의 거울·보호의 장막) — 🔴 2026-08-05 신설.
	#   시전이 아니라 **피격 처리**에서 나오므로 `_motion` 경로가 아니다. 종전엔 콜로세움이
	#   `def_skill` 을 아예 안 읽어서, 발동해도 화면·로그에 흔적이 하나도 없었다
	#   (사용자에겐 "철갑 방패가 발동하지 않는다"로 보였다).
	_defense_fired(v, ev)

	var heal := int(ev.get("heal", 0))
	if heal > 0:
		v["hp"] = mini(int(v["hp_max"]), int(v["hp"]) + heal)
		_set_bar(v)
		_float_text(v["pos"], "+%d" % heal, Color(0.5, 1.0, 0.5), true)
	if bool(ev.get("dead", false)) and not bool(v["dead"]):
		# 원작 사망 = `deadTypeNormalDamage` / `deadTypeBigDamage` 가 **"damaged" → "down"**
		# 두 단계로 낸다. `damaged` 가 여기(사망 도입부)에만 쓰이는 게 원작 사양이다.
		# 원작 `MakeInterface::deadEffect` @0109a654 —
		#   `particle/scene/colosseum/effect_dead.plist` 를 대상 중앙에 뿌리고
		#   `music/effect_dead.mp3` 를 **볼륨 0.5**(0x3f000000)로 낸다.
		_dead_fx(v)
		var d0 := _play_anim(v, "damaged")
		var gen0 := _gen
		get_tree().create_timer(maxf(0.15, d0)).timeout.connect(func() -> void:
			if gen0 == _gen:
				_play_anim(v, "down"))
		v["dead"] = true
		# 스파인만 지우면 **빈 HP 바와 이름표가 허공에 남는다**(2026-08-04 스크린샷에서 확인).
		# 셋을 함께 없앤다. down 을 볼 수 있게 조금 늦춘다.
		for k in ["node", "barh"]:
			var n = v.get(k)
			if n != null and is_instance_valid(n):
				# damaged → down 두 단계를 다 보여 준 뒤에 사라진다.
				var tw := create_tween()
				tw.tween_interval(1.4)
				tw.tween_property(n, "modulate:a", 0.0, 0.45)
	_log_line(ev, t, dfn, dmg, heal)


## SKIP 중 — 연출 없이 **상태만** 굴린다(HP·사망·로그). 원작 `onClickSkipBattle` 과 같은 자리.
func _apply_silent(ev: Dictionary) -> void:
	var dfn := String(ev.get("defender", ev.get("target", "")))
	if dfn == "" or not _views.has(dfn):
		return
	var v: Dictionary = _views[dfn]
	if not bool(ev.get("miss", false)):
		var dmg := int(ev.get("damage", 0))
		if dmg > 0:
			v["hp"] = maxi(0, int(v["hp"]) - dmg)
		var heal := int(ev.get("heal", 0))
		if heal > 0:
			v["hp"] = mini(int(v["hp_max"]), int(v["hp"]) + heal)
		_set_bar(v)
	if bool(ev.get("dead", false)) and not bool(v["dead"]):
		v["dead"] = true
		for k in ["node", "barh"]:
			var n = v.get(k)
			if n != null and is_instance_valid(n):
				(n as CanvasItem).modulate.a = 0.0


## 하단 로그 문구 — **원작 `ColosseumTextBox` 가 쓰던 문장 그대로**.
## 출처 = `DV2/string/stringsData_KR.xml`(사용자 지적 2026-08-04로 채굴). 유실이 아니었다.
## 종전엔 "스킬 발동!" 같은 자작 문구를 냈다.
func _log_line(ev: Dictionary, t: String, dfn: String, dmg: int, heal: int) -> void:
	var L: Dictionary = Data.colosseum.get("log", {})
	if L.is_empty():
		return
	var an := _who(_actor_tag(ev))
	var dn := _who(dfn)
	match t:
		"normal", "double":
			var kind := String(L.get("atk_critical", "")) if bool(ev.get("crit", false)) \
				else String(L.get("atk_double" if t == "double" else "atk_normal", ""))
			if bool(ev.get("miss", false)):
				_say(String(L.get("evade", "")) % [dn, an, kind])
			elif bool(ev.get("block", false)):
				_say(String(L.get("defend", "")) % [dn, an, kind, dmg])
			else:
				_say(String(L.get("attack", "")) % [an, dn, kind, dmg])
		"awaken":
			# 시전 줄(`ColosseumUltimate`)은 **시전 순간**에 이미 냈다(`_apply` 의 각성기 분기).
			# 여기는 피해가 실제로 들어가는 시각이므로 피해 줄만 낸다.
			# 원작 문자열 `ColosseumUltimateDamage` — 표에는 있었는데 아무 데서도 안 읽고 있었다.
			if dmg > 0:
				_say(String(L.get("ultimate_damage", "")) % [dn, dmg])
		"skill":
			var sn := String(ev.get("skill_name", ""))
			if sn != "":
				_say(String(L.get("skill", "")) % [an, dn, sn])
			# 연승방지봇의 면역(이벤트 규칙) — 피해 0 인 이유를 안 알려 주면
			# 스킬이 고장 난 것처럼 보인다.
			if bool(ev.get("immune", false)) and sn != "":
				_say(String(L.get("immune", "")) % [dn, sn])
		"dot":
			_say(String(L.get("poison", "")) % [dn, dmg])
	if heal > 0:
		_say(String(L.get("recover", "")) % [dn, heal])
	if bool(ev.get("dead", false)):
		_say(String(L.get("stun", "")) % dn)


## 방어 스킬 발동 표시 — 원작 실드 스파인 + 문구.
##
## 원작 조건(`battle.gd::_shield_impact` 와 **같은 근거**): `startAttack` @00c89038 이 피격
## 처리 중 `setCheckShildImpact(slot)` 을 부르고, 그 안이 `iVar5 != 0xb`(= 스킬 11 철갑 방패)
## 이면 건너뛴다 ⇒ 실드 연출은 **철갑 방패 전용**이다. 나머지 방어 스킬은 문구만 남는다.
## 문구는 원작 문자열 `<ColosseumBuff>`("%s이(가) 자신에게 %s을(를) 사용하였습니다.").
const SHIELD_SKILL := 11
const SHIELD_SPINE := "res://scenes/worldmap_fx/skill_adbloking_spine.tscn"

func _defense_fired(v: Dictionary, ev: Dictionary) -> void:
	var nm := String(ev.get("def_skill", ""))
	if nm == "":
		return
	var L: Dictionary = Data.colosseum.get("log", {})
	_say(String(L.get("buff", "%s / %s")) % [String(v.get("dname", "")), nm])
	if int(ev.get("def_skill_id", 0)) != SHIELD_SKILL:
		return
	if not ResourceLoader.exists(SHIELD_SPINE):
		return
	var holder := Node2D.new()
	holder.z_index = 60
	holder.position = _body_pos(v)
	add_child(holder)
	var inst = (load(SHIELD_SPINE) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap := _find_anim_player(inst)
	if ap != null and ap.get_animation_list().size() > 0:
		var a0 := ap.get_animation_list()[0]
		ap.get_animation(a0).loop_mode = Animation.LOOP_NONE
		ap.play(a0)
	# 원작 `Delay(0.7) → Hide`.
	var tw := holder.create_tween()
	tw.tween_interval(0.7)
	tw.tween_callback(holder.queue_free)


## 이벤트의 **행동 주체** 태그 — 🔴 2026-08-05(사용자 지적 "철갑 방패가 안 나오고
## 무언의 압박만 나온다")로 드러난 배선 누락.
##
## `Battle.simulate()` 의 이벤트는 종류마다 주체 칸 이름이 다르다:
##   평타/연타/각성기(`_deal_attack`·`resolve_awaken`) → **`attacker`**
##   스킬(`_apply_skill_effect`)                       → **`caster`**
##   혼란·기절(`_act`)                                 → **`actor`**
## 종전엔 `attacker` 만 봐서 **스킬 이벤트의 주체가 통째로 비었다** ⇒ 시전자가 공격 모션도
## 이동도 안 하고, 로그의 시전자 이름도 빈칸으로 찍혔다. 방어 스킬(철갑 방패)은 애초에
## 이 경로가 아니라 피격 처리에서 나오므로(`fired`) 아래 `_defense_fired` 가 따로 낸다.
func _actor_tag(ev: Dictionary) -> String:
	for k in ["attacker", "caster", "actor"]:
		var s := String(ev.get(k, ""))
		if s != "" and _views.has(s):
			return s
	return ""


## 내부 전투원 이름(A0/E0) → 화면에 낼 드래곤 이름.
func _who(tag: String) -> String:
	if tag == "" or not _views.has(tag):
		return ""
	return String((_views[tag] as Dictionary).get("dname", tag))


## HP 게이지 갱신 — 원작 `MakeInterface::decreaseHP`/`increaseHP` 와 같은 자리.
## 채움은 `bar.png` 를 **왼쪽부터 잘라** 보여 준다(원작도 anchor(0,0.5) 스프라이트다).
func _set_bar(v: Dictionary) -> void:
	var r := clampf(float(v["hp"]) / float(v["hp_max"]), 0.0, 1.0)
	var b = v.get("bar")
	if b is Sprite2D and is_instance_valid(b):
		var s := b as Sprite2D
		var t := s.texture
		if t != null:
			s.region_rect = Rect2(0, 0, float(t.get_width()) * r, t.get_height())
	var hl = v.get("hp_label")
	if hl is Label and is_instance_valid(hl):
		(hl as Label).text = "%d / %d" % [maxi(0, int(v["hp"])), int(v["hp_max"])]


# ---------- 스파인 안무(원작 FightScene / MakeInterface) ----------
#
# 🔴 2026-08-04 정정 (사용자 지적: "일반 피격엔 모션이 없었다") — **맞았다.**
#   종전엔 `FightScene::onClickDebug` 의 시퀀스를 안무로 읽었는데, 그건 애니를 차례로
#   돌려보는 **디버그 뷰어**다. 근거: 거기서 쓰는 `MakeInterface::runSpineWithAnimationName`
#   의 호출자가 전 디컴프에서 **onClickDebug 뿐**이다(다른 호출자 0건).
#
# 진짜 어휘는 `MakeInterface` 에서 전투 중 애니를 바꾸는 **세 곳뿐**이다
# (`translateSpineAnimationName` 호출 지점 전수):
#     makeDragonLayer        @0105072c → "wait"    (루프, 상시)
#     castSkill              @0108a924 → "attack"  → 끝나면 "wait"
#     deadTypeBigDamage      @…        → "damaged" → "down"
#     deadTypeNormalDamage   @…        → "damaged" → "down"
#   (패킹 문자열 디코드: 0x0c+"attack" · 0x7469617708="wait" ·
#    0x646567616d61640e="damaged" · 0x6e776f6408="down")
#
# ⇒ **일반 피격에는 애니가 없다.** `damaged` 는 피격 반응이 아니라 **사망 도입부**다.
#   `critical`/`ultimate1`/`ultimate2` 는 콜로세움 경로에서 트리거되지 않는다
#   (변환본엔 있지만 원작 PvP 가 안 쓴다 — 안 쓰는 게 원작 정합이다).
#
# 🔴 2026-08-05 — 안무 마스터 `MakeInterface::action` @01062fd4 를 **드디어 읽었다**.
#
# 종전 주석의 "Delay → [ScaleTo(1.5) + MoveBy] → …" 는 **내가 지어낸 것**이었다.
# 그 함수는 28,968B 라 Ghidra 디컴파일이 타임아웃으로 죽었고(`process: timeout`),
# 나는 못 읽은 채 안무를 상상해 적었다. `scripts/tools/decomp_big.py --asm-only` +
# `asm_read.py` 로 **주석 붙은 디스어셈블리**를 뽑아 실제 시퀀스를 복원했다
# (근거 = `docs/ref/orig_code/probe/action_asm.c` 줄 176~465).
#
# ## 원작 기본 공격 시퀀스 (CCSequence 인자 순서 그대로)
#   ① `CCDelayTime(현재애니길이 + 0.05)`            ← 진행 중 모션이 끝나길 기다린다
#   ② `CCCallFuncN → runSpineWithAnimationName(dragon, "attack", 1.125)`  ← 재생속도 1.125배
#   ③ `CCDelayTime(getAttackFrame() / 30 / 1.125)` ← **타격 프레임**까지의 시간
#   ④ `CCScaleTo(0.05, base×1.25, 1.05)`           ┐
#   ⑤ `CCScaleTo(0.05, base×0.90, 0.95)`           ├ 타격 순간의 **스쿼시&스트레치**
#   ⑥ `CCScaleTo(0.05, base×1.00, 1.00)`           ┘
#   ⑦ `CCDelayTime(전체길이/1.125 − 타격시간 − 0.1)` ← 공격 애니 잔여분
#   ⑧ `CCCallFuncN → runSpineWithAnimationName(dragon, "wait", 1.0)`
#   ⑨ `CCScaleTo(0, base, 1.0)`
#
# 상수 출처(부동소수 리터럴 디코드): 0x3d088815=1/30 · 0x3f900000=1.125 · 0x3fa00000=1.25 ·
#   0x3f866666=1.05 · 0x3f666666=0.90 · 0x3f733333=0.95 · 0x3d4ccccd=0.05 · 0xbdcccccd=−0.1
#
# 🔴 2026-08-05 정정 — 종전에 여기 "이 분기에 이동이 없다"고 적어 뒀던 것은 **틀렸다**.
#   위 ①~⑨는 스케일 펄스 쪽만 본 것이고, 같은 핸들러의 **다른 갈래**(@0107070c, 공격유형 ≠ 4)에
#   `CCJumpTo` 두 번 + `CCMoveTo` 복귀가 그대로 들어 있다 — `_attack_jump` 참조.
#   못 찾은 이유: 디컴프가 `action` 을 `[skip>8000]` 으로 건너뛰어 ASM 으로만 읽히는데,
#   그때 스케일 펄스 구간만 읽고 "이동 없음"으로 단정했다.
const ATK_ANIM_SPEED := 1.125       # 원작 runSpineWithAnimationName(…, 1.125)
const CRIT_ANIM_SPEED := 0.75       # 🟦 크리티컬은 평타보다 느리게(= 길게) — 위 주석
const ATK_FPS := 30.0               # 원작 getAttackFrame() ÷ 30
const ATK_PULSE_SEC := 0.05         # 원작 ScaleTo 지속시간(3단 공통)
const ATK_PULSE := [Vector2(1.25, 1.05), Vector2(0.90, 0.95), Vector2(1.00, 1.00)]
const ATK_TAIL := 0.1               # 원작 마지막 Delay 의 −0.1
const ATK_LEAD := 0.05              # 원작 ①의 +0.05
const MOVE_SEC := 0.18

## 우리 변환본 드래곤 씬이 실제로 갖고 있는 애니(2026-08-04 실측):
##   wait · attack · critical · damaged · down · love · ultimate1 · ultimate2
## 즉 **연출에 필요한 건 전부 이미 변환돼 있었다** — 지금까지 wait 만 틀고 있었을 뿐이다.
const ANIM_IDLE := "wait"


## 콜로세움 드래곤 스파인 — **native 크기 그대로**, 원점 = 발밑 중앙(우리 배치 규약).
## 원작 `makeDragonLayer` 와 같다: 크기를 건드리지 않고 3v3/1v1 배율만 밖에서 곱한다.
##
## 🔴 2026-08-05 수정(사용자 지적) — **각성 드래곤이 성체로 나오고 있었다.**
##   종전엔 `dragon_%d_adult` 로 못 박아서, 각성체(`_e`) 스파인이 있는 드래곤도 성체 그림이 떴다.
##   단계 판정은 원작 `Dragon::getImagePathSpineJson` 의 각성 분기를 옮긴
##   **`Growth.spine_stage`** 한 곳뿐이다(도감·동굴·편성이 이미 쓰는 그 함수).
##   실측 2026-08-05: `_e` 씬 **134/134 에 `attack` 이 있다** ⇒ 전투 모션도 문제 없다.
##   콜로세움은 입장 레벨 25 이상이라 유생·아성체는 애초에 못 들어오지만,
##   각성 스파인이 없는 종(`_e` 미보유)은 성체로 안전하게 떨어진다.
static func _dragon_spine(id: int, stage := "adult") -> Node2D:
	var path := "res://scenes/dragons/dragon_%d_%s.tscn" % [id, stage]
	if id <= 0 or not ResourceLoader.exists(path):
		path = "res://scenes/dragons/dragon_%d_adult.tscn" % id
	if id <= 0 or not ResourceLoader.exists(path):
		return null
	var holder := Node2D.new()
	var inst = (load(path) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap := _find_anim_player(inst)
	if ap != null and ap.has_animation(ANIM_IDLE):
		ap.get_animation(ANIM_IDLE).loop_mode = Animation.LOOP_LINEAR
		ap.play(ANIM_IDLE)
	# 바닥 중앙 정렬만 한다(스케일은 건드리지 않는다).
	var r := PartySelect._bounds(inst, Transform2D.IDENTITY)
	if r.size.y > 1.0:
		inst.position -= Vector2(r.get_center().x, r.position.y + r.size.y)
	return holder


## 그 전투원의 스파인이 이 애니를 갖고 있나(종마다 편차가 있다).
func _has_anim(v: Dictionary, name: String) -> bool:
	var ap = v.get("anim")
	return ap is AnimationPlayer and is_instance_valid(ap) \
		and (ap as AnimationPlayer).has_animation(name)


static func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null


## 애니 1회 재생 후 대기 모션 복귀. 반환 = 그 애니 길이(초).
func _play_anim(v: Dictionary, name: String) -> float:
	var ap = v.get("anim")
	if not (ap is AnimationPlayer) or not is_instance_valid(ap):
		return 0.0
	var p := ap as AnimationPlayer
	if not p.has_animation(name):
		return 0.0
	var a := p.get_animation(name)
	a.loop_mode = Animation.LOOP_NONE
	# 원작 `runSpineWithAnimationName(dragon, name, 1.125)` — 공격은 1.125배로 돌린다.
	# 🟦 2026-08-05 사용자 확정 — 크리티컬은 **평타보다 모션이 길었다**. 평타가 1.125배로
	#   빨리 감기는 반면 크리티컬은 그보다 느리게 돈다 ⇒ `CRIT_ANIM_SPEED`.
	#   # ASSUMPTION: 원작이 코드 43 핸들러(@01064f2c)에서 `critical` 에 넘기는 배속 값은
	#   `action` 이 `[skip>8000]` 이라 아직 못 읽었다. 확보하면 이 상수만 갈아 끼우면 된다.
	var speed := ATK_ANIM_SPEED if name == "attack" else 1.0
	if name == "critical":
		speed = CRIT_ANIM_SPEED
	p.play(name, -1.0, speed)
	var dur := a.length / speed
	# 원작 ⑦: 잔여 = 전체/1.125 − 타격시간 − 0.1. 여기서는 애니가 끝난 뒤 복귀시키면 되므로
	# 같은 값(= dur − 0.1)을 쓴다.
	var gen := _gen
	get_tree().create_timer(maxf(0.1, dur - ATK_TAIL)).timeout.connect(func() -> void:
		if gen != _gen or not is_instance_valid(p) or bool(v.get("dead", false)):
			return
		if p.has_animation(ANIM_IDLE):
			p.get_animation(ANIM_IDLE).loop_mode = Animation.LOOP_LINEAR
			p.play(ANIM_IDLE))
	return dur


## 피격 깜빡임 — 원작 `MakeInterface::damagedColor` @01089208 그대로.
##
##   FadeTo(0.0, 0)                              ← 즉시 투명
##   DelayTime(getDuration("damaged") − 0.1)     ← "damaged" 애니 **길이만 잰다**(재생 안 함)
##   FadeTo(0.1, 255)                            ← 0.1초에 걸쳐 복귀
##   (tag = −0xc0dc8, 이미 걸려 있으면 stopActionByTag 로 끊고 다시)
##
## ✅ 이게 "일반 피격에 모션이 없다"의 정확한 내막이다 —
##   `action` code 0(기본 피격)이 `getDuration(spine, "damaged", 0)` 를 부르지만
##   **재생이 아니라 측정**이고(실측: 반환값이 곧장 CCDelayTime 으로 간다),
##   눈에 보이는 반응은 이 **깜빡임**이다. 종전엔 이걸 통째로 빠뜨렸다.
##
## 🔊 2026-08-05 — **피격 효과음의 주인을 찾았다.**
##   `MakeInterface::runSpineWithAnimationName` @0104f468 이 애니 이름이 `"damaged"` 로
##   시작하면 `rand()&1` 로 `music/effect_dragon_damaged_1.mp3` / `_2.mp3` 를 고르고
##   **볼륨 `(rand()%6) × 0.05 + 0.25`**(= 0.25~0.50) 로 낸다.
##   그리고 `asm_cfg.py --table` 로 확인한 code 0 핸들러(@01067300)의 도달 호출에
##   `runSpineWithAnimationName` 가 **있다** ⇒ 기본 피격도 이 소리를 낸다.
##   깜빡임(=투명) 중에 애니가 도니 화면엔 안 보이고 **소리만** 남는 게 원작 동작이다.
##   같은 이유로 `battle.gd` 도 `InterFace::setCallHitSound` 로 같은 두 음원을 쓴다.
## 🔴 2026-08-05(사용자 지적 "피격 때 스파인이 통째로 사라져 점멸한다") — **엔진 차이 보정.**
##   원작 `CCFadeTo(0.0, 0)` 은 Cocos2d-x 에서 **그 노드의 opacity 만** 바꾼다 —
##   `setCascadeOpacityEnabled` 를 켜지 않으면 자식(=스파인 슬롯)으로 안 내려간다.
##   Godot 의 `modulate` 는 **항상 자식까지 내려가서**, 같은 값을 그대로 옮기면 드래곤이
##   통째로 지워진다. `damagedColor` 를 받는 노드가 레이어인지 스파인인지는 호출부가
##   `action`(`[skip>8000]`) 안이라 아직 못 짚었다 ⇒ 시퀀스·시간은 원작 그대로 두고
##   **깊이만** 완전 투명(0.0)이 아니라 얕은 값으로 둔다(🟦 사용자 확정).
##   원작 프레임을 확보해 판정이 서면 이 상수 하나만 0.0 으로 되돌리면 된다.
const HIT_BLINK_ALPHA := 0.35       # 원작 리터럴은 0 — 위 주석 참조
const HIT_BLINK_BACK := 0.1         # 원작 FadeTo(0.1, 255)
const HIT_SFX_VOL_BASE := 0.25      # 원작 (rand()%6)*0.05 + 0.25
const HIT_SFX_VOL_STEP := 0.05
const HIT_SFX_VOL_N := 6

func _hit_sfx() -> void:
	Bgm.sfx("effect_dragon_damaged_%d" % (1 + (_rng.randi() & 1)),
		HIT_SFX_VOL_BASE + float(_rng.randi() % HIT_SFX_VOL_N) * HIT_SFX_VOL_STEP)


func _damaged_color(v: Dictionary) -> void:
	var n = v.get("node")
	if not (n is Node2D) or not is_instance_valid(n):
		return
	var node := n as Node2D
	# "damaged" 애니 길이 = 깜빡임 유지 시간(원작과 같은 출처).
	var hold := 0.3
	var ap = v.get("anim")
	if ap is AnimationPlayer and is_instance_valid(ap) and (ap as AnimationPlayer).has_animation("damaged"):
		hold = (ap as AnimationPlayer).get_animation("damaged").length
	var tw := node.create_tween()
	tw.tween_property(node, "modulate:a", HIT_BLINK_ALPHA, 0.0)
	tw.tween_interval(maxf(0.05, hold - HIT_BLINK_BACK))
	tw.tween_property(node, "modulate:a", 1.0, HIT_BLINK_BACK)


## 피격 좌우 흔들림 — 원작 `MakeInterface::shakeLayerToHorizontal` @010892c0.
##   MoveBy(0.05, dir×+20) → (0.05, dir×−35) → (0.05, dir×+25) → (0.05, dir×−10)
## 합이 0 이라 제자리로 돌아온다(총 0.2초).
const HIT_SHAKE := [20.0, -35.0, 25.0, -10.0]
const HIT_SHAKE_SEC := 0.05

func _shake_horizontal(v: Dictionary, dir: float) -> void:
	var n = v.get("node")
	if not (n is Node2D) or not is_instance_valid(n):
		return
	var node := n as Node2D
	# ⚠️ 복귀 지점은 `v["pos"]`(슬롯 원위치)가 아니라 **지금 자리**다 —
	#   `_swap_position` 이 자리를 옮겨 둔 도중에 흔들리면 원위치로 튕겨 버린다(2026-08-05).
	var base := node.position
	var tw := node.create_tween()
	for d: float in HIT_SHAKE:
		tw.tween_property(node, "position:x",
			node.position.x + d * dir, HIT_SHAKE_SEC).as_relative()
	tw.tween_property(node, "position", base, 0.0)


## 타격 순간의 **스쿼시&스트레치** — 원작 `action` @01062fd4 의 ScaleTo 3단.
##   ScaleTo(0.05, base×1.25, 1.05) → (0.05, base×0.90, 0.95) → (0.05, base×1.00, 1.00)
## X 는 드래곤 자기 스케일에 **곱하고**(뒤집힘 부호가 살아 있어야 한다) Y 는 절대값이다.
## 시작 시점은 애니 시작 + `getAttackFrame()/30/1.125` = **타격 프레임**.
## 우리는 프레임 수를 못 읽으므로 애니 길이의 절반을 타격 시점으로 잡는다
## (# ASSUMPTION: getAttackFrame() 은 스파인 변환본에 남지 않는 원작 DB 값이다).
func _attack_pulse(v: Dictionary, target: Dictionary, anim_dur: float) -> void:
	var n = v.get("node")
	if not (n is Node2D) or not is_instance_valid(n):
		return
	var node := n as Node2D
	var base := _base_scale(v)
	var hit := clampf(anim_dur * 0.5, 0.05, 1.2)

	var tw := create_tween()
	tw.tween_interval(hit)
	for f: Vector2 in ATK_PULSE:
		# X 부호 유지(내 팀은 flipX 상태다), Y 는 원작대로 절대 배율.
		tw.tween_property(node, "scale",
			Vector2(base.x * f.x, absf(base.y) * f.y), ATK_PULSE_SEC)
	tw.tween_property(node, "scale", base, 0.0)

	_attack_jump(v, target, hit, anim_dur)


## 평타 이동 — 원작 액션 코드 **5** 핸들러(@010665d8 → @0107070c, ASM 실측 2026-08-05).
##
## 🔴 종전 주석 "원작 기본공격엔 이동이 없다"는 **오판**이었다(사용자 지적 + 레퍼런스
##   `docs/ref/pvp/화면 캡처 …202613.png` 에서 공격자가 상대 위에 올라가 있다).
##   `action` 이 `[skip>8000]` 이라 디컴프에 안 보였을 뿐, ASM 에 안무가 그대로 있다:
##
##     ① CCJumpTo(dur, home + (**175** × dir × scale, 0), height **100** × scale, jumps 1)
##          └ CCEaseOut(rate **0.5**)
##     ② CCDelayTime(**0.1**)                                    (0x3dcccccd)
##     ③ CCJumpTo(dur, home + (**100** × dir × scale, 0), height **50** × scale, jumps 1)
##          └ CCEaseOut(rate **0.125**)
##     ④ CCDelayTime(애니길이/1.5 − 타격시점 + 0.1)
##     ⑤ CCMoveTo(제자리)
##
##   상수 출처(리터럴): 0x432f0000=175 · 0x42c80000=100 · 0x42480000=50 ·
##   0x3f000000=0.5 · 0x3e000000=0.125 · 0x3dcccccd=0.1.
##   `dir` 은 원작에서 `[sp+0x4d0]`(±1 뒤집기 부호), `scale` 은 `[sp+0x580]`(3v3=0.75).
##
## # ASSUMPTION: 두 점프의 **지속시간**은 원작이 타격 시점에서 파생시키는데
##   (`s2 = 타격시점 + [sp+0x4f8]`) 그 덧셈항을 특정하지 못했다. 타격 시점을 그대로 쓴다 —
##   그래야 ①이 끝나는 순간이 곧 타격이라 화면과 로그가 맞는다.
const ATK_JUMP1_DX := 175.0         # 원작 0x432f0000
const ATK_JUMP1_H := 100.0          # 원작 0x42c80000
const ATK_JUMP2_DX := 100.0         # 원작 두 번째 점프의 x
const ATK_JUMP2_H := 50.0           # 원작 0x42480000
const ATK_JUMP1_EASE := 0.5         # 원작 CCEaseOut(0x3f000000)
const ATK_JUMP2_EASE := 0.125       # 원작 CCEaseOut(0x3e000000)
const ATK_JUMP_GAP := 0.1           # 원작 CCDelayTime(0x3dcccccd)

## 🔴 2026-08-05 두 건 수정(사용자 지적).
##
## ① **턴마다 앞으로 밀리던 버그** — 복귀 지점을 `node.position`(호출 순간의 자리)로 잡고
##    있었다. 앞선 공격의 복귀 트윈이 아직 안 끝났거나 `_swap_position`·`_shake_horizontal`
##    이 자리를 옮겨 둔 상태에서 다음 공격이 시작되면 **전진한 자리가 새 원점**이 돼 누적된다.
##    ⇒ 원점을 슬롯 좌표(`v["pos"]`)로 고정하고, 이 드래곤에 걸려 있던 이동 트윈은 죽인다.
##    (자리 교대 중이면 `v["home"]` 을 `_swap_position` 이 갱신해 준다 — 그때는 그 자리가 원점이다.)
##
## ② **밀착** — 원작 상수 175/100 은 절대 거리라 우리 슬롯 간격(≈560pt)에서는 절반도 못 간다.
##    🟦 사용자 확정: 상대와 닿도록 늘린다. 원작의 **두 단계 구조와 되돌아오는 75pt 는 유지**하고
##    착지점만 상대 몸통 옆으로 잡는다 — 폭은 실측값(`dragon_w`)이라 종마다 자동으로 맞는다.
const CONTACT_OVERLAP := 0.8        # 두 몸통 반폭 합에 곱한다(1.0=딱 붙음, <1=살짝 겹침)

func _attack_jump(v: Dictionary, target: Dictionary, hit: float, anim_dur: float) -> void:
	if target.is_empty() or _mode == "":
		return
	var n = v.get("node")
	if not (n is Node2D) or not is_instance_valid(n):
		return
	var node := n as Node2D
	var home: Vector2 = v.get("home", node.position)
	var tp: Vector2 = target.get("home", target.get("pos", home))
	# 전방 = 상대가 있는 쪽. 원작의 ±1 부호 자리다.
	var dir := signf(tp.x - home.x)
	if is_zero_approx(dir):
		return
	# 원작이 곱하는 `[sp+0x580]` = 드래곤 레이어 배율(3v3 0.75 / 1v1 1.0).
	var s := DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO
	# 착지점 = 상대 옆(몸통 반폭 합만큼 떨어진 자리). 원작 구조상 ②가 최종 정지 자리다.
	var reach := (float(v.get("dragon_w", DRAGON_H)) + float(target.get("dragon_w", DRAGON_H))) \
		* 0.5 * CONTACT_OVERLAP
	var far := absf(tp.x - home.x) - reach
	var dx2: float = maxf(ATK_JUMP2_DX * s, far)
	var dx1: float = dx2 + (ATK_JUMP1_DX - ATK_JUMP2_DX) * s   # 원작의 오버슈트 75×s 유지
	var p1 := home + Vector2(dir * dx1, 0.0)
	var p2 := home + Vector2(dir * dx2, 0.0)
	var gen := _gen
	# 이 드래곤에 남아 있던 이동 트윈을 끊는다(①).
	var old = v.get("move_tw")
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var t := create_tween()
	v["move_tw"] = t
	_tween_jump(t, node, home, p1, ATK_JUMP1_H * s, hit, ATK_JUMP1_EASE)
	t.tween_interval(ATK_JUMP_GAP)
	_tween_jump(t, node, p1, p2, ATK_JUMP2_H * s, hit, ATK_JUMP2_EASE)
	t.tween_interval(maxf(0.0, anim_dur - hit) + ATK_JUMP_GAP)
	t.tween_property(node, "position", home, MOVE_SEC)
	t.tween_callback(func() -> void:
		if gen == _gen and is_instance_valid(node):
			node.position = v.get("home", home))


## Cocos `CCJumpTo` + `CCEaseOut` 한 구간을 트윈에 붙인다.
##   CCJumpTo:  frac = fmod(t × jumps, 1) → y += height × 4 × frac × (1 − frac),
##              x·y 는 시작→끝을 t 로 선형 보간 (jumps = 1 이므로 frac = t)
##   CCEaseOut: t' = pow(t, 1 / rate)  (rate 0.5 → t², 0.125 → t⁸)
## Godot 에는 대응 트위너가 없어 `tween_method` 로 같은 식을 직접 낸다.
func _tween_jump(t: Tween, node: Node2D, from: Vector2, to: Vector2,
		height: float, sec: float, ease_rate: float) -> void:
	var dur := maxf(0.05, sec)
	var inv := 1.0 / maxf(0.001, ease_rate)
	t.tween_method(func(x: float) -> void:
		if not is_instance_valid(node):
			return
		var e: float = pow(clampf(x, 0.0, 1.0), inv)
		var pos: Vector2 = from.lerp(to, e)
		# Cocos 는 y 가 위쪽이고 우리는 아래쪽이라 부호를 뒤집는다(§Design).
		pos.y -= height * 4.0 * e * (1.0 - e)
		node.position = pos,
		0.0, 1.0, dur)


func _base_scale(v: Dictionary) -> Vector2:
	if not v.has("base_scale"):
		var n = v.get("node")
		v["base_scale"] = (n as Node2D).scale if n is Node2D else Vector2.ONE
	return v["base_scale"]


# ---------- 액션 코드 배선 (2026-08-05) ----------
#
# `MakeInterface::action` @01062fd4 의 점프테이블 53핸들러를 전수 특정한 결과
# (`docs/ref/porting/Colosseum.md` §7.5)를 **우리 이벤트에 실제로 연결한다.**
# 종전엔 지도만 만들어 두고 `_motion` 은 여전히 우리 자체 타입 3가지로만 갈렸다.
#
# 원작은 서버가 액션 코드를 보내 줬다 → 우리는 `Battle.simulate()` 이벤트에서 **역으로 판정**한다.
# 이 판정은 render 층 일이다(§8): logic 은 "무슨 일이 있었나"만 말하고,
# "그 일을 원작이 어느 코드로 연출했나"는 화면의 어휘다.
const AC_HIT := 0          # 기본 피격
const AC_CONFUSE := 1      # 혼란 — 자기 자신을 때린다
const AC_DOUBLE := 2       # 연속 공격
const AC_EVADE := 3        # 회피
const AC_CUTIN := 4        # 각성기 컷인(`showCutIn`) — 아래 🔴 참조
const AC_CRIT_FX := 41     # 크리티컬 이펙트(`criticalEffectMake`)
const AC_CRIT_ANIM := 43   # 크리티컬 애니(`"critical"` → `"wait"`)
const AC_SWAP := 42        # 위치 교대
const AC_STUN := -15       # 기절(행동 불가)
const AC_POISON := -32     # 중독
const AC_BIGHIT := -54     # 대형 타격

## 이벤트 1건 → 원작 액션 코드. 양수 스킬 코드는 `skill_id` 가 그대로 코드다(§7.5 결론 ①).
func _action_code(ev: Dictionary, t: String) -> int:
	if bool(ev.get("miss", false)):
		return AC_EVADE
	match t:
		"confused":
			return AC_CONFUSE
		"double":
			return AC_DOUBLE
		"status_skip":
			return AC_STUN
		"dot":
			return AC_POISON
		"skill":
			return int(ev.get("skill_id", 0))
		"awaken":
			return AC_CUTIN
	if bool(ev.get("crit", false)):
		return AC_CRIT_FX
	return AC_HIT


## 이펙트가 붙는 **몸통 중앙** — 🔴 2026-08-05 정정(사용자 지적 "이펙트가 드래곤과 안 겹친다").
##
## 원작은 이펙트를 **드래곤 레이어**(앵커 중앙)에 붙이므로 기준점이 몸통 한가운데다.
## 우리 holder 원점은 `PartySelect._spine_node` 규약대로 스프라이트 **바닥 중앙**(발밑)이라
## 그대로 쓰면 이펙트가 전부 발치에 깔린다 ⇒ 실측 높이의 절반만큼 올려 원작 앵커로 맞춘다.
## (같은 보정을 `_damaged_particle` 은 이미 하고 있었다 — 나머지가 빠져 있었던 것.)
func _body_pos(v: Dictionary) -> Vector2:
	if v.is_empty():
		return _vis() * 0.5
	var p: Vector2 = v.get("pos", _vis() * 0.5)
	return p - Vector2(0.0, float(v.get("dragon_h", DRAGON_H)) * 0.5)


## 한 이벤트의 스파인 연출 — 공격자/피격자를 함께 움직인다.
func _motion(ev: Dictionary, t: String, atk_tag: String, dfn_tag: String) -> void:
	var atk: Dictionary = _views.get(atk_tag, {})
	var dfn: Dictionary = _views.get(dfn_tag, {})
	var code := _action_code(ev, t)

	# code −15 기절 — 원작은 공격 자체가 없다(턴만 소모). 문자열 `ColosseumStuned`.
	if code == AC_STUN:
		var st: Dictionary = _views.get(String(ev.get("actor", "")), {})
		if not st.is_empty():
			_shake_horizontal(st, 1.0 if bool(st.get("mine", false)) else -1.0)
			_status_icon(st, int(ev.get("source", 0)), false, int(ev.get("turns", 0)))
		return

	# code 1 혼란 — 원작은 `swapPosition` 으로 자리를 바꾼 뒤 자기 스파인으로 자기를 친다.
	if code == AC_CONFUSE:
		var me: Dictionary = _views.get(String(ev.get("actor", "")), {})
		if not me.is_empty():
			_swap_position(me, 0.8)
			var d0 := _play_anim(me, "attack")
			_attack_pulse(me, me, d0)
			_damaged_color(me)
			_shake_horizontal(me, 1.0 if bool(me.get("mine", false)) else -1.0)
		return

	if not atk.is_empty() and not bool(atk.get("dead", false)):
		# 🔴 2026-08-05 정정(사용자 지적 "크리티컬 모션이 없다") — 종전 주석
		#   "콜로세움은 크리티컬용 별도 애니를 안 부른다"는 **틀렸다.**
		#   액션 코드 **43** 핸들러(@01064f2c)의 배타 키가 `critical` · `wait` 이고
		#   `runSpineWithAnimationName` + `getDuration` 을 부른다 ⇒ 크리티컬은 드래곤 자신의
		#   **`critical` 애니**를 틀고 끝나면 `wait` 로 돌아간다(`asm_cfg.py --table` 로 확인).
		#   변환본 성체·각성체 스파인에 `critical` 이 **전부** 들어 있다(2026-08-04 실측).
		# 각성기는 드래곤 자신의 `ultimate1` 애니다 — 변환본 성체·각성체 스파인에 전부 있다
		# (2026-08-05 실측: attack/critical/damaged/down/love/**ultimate1**/wait).
		# 종전엔 `attack` 을 틀어 평타와 구분이 안 갔다.
		var anim := "attack"
		if t == "awaken" and _has_anim(atk, "ultimate1"):
			anim = "ultimate1"
		elif code == AC_CRIT_FX and _has_anim(atk, "critical"):
			anim = "critical"
		var dur := _play_anim(atk, anim)
		# 각성기는 제자리에서 낸다(원작도 UltimateLayer 가 화면을 덮는다).
		if t != "awaken":
			_attack_pulse(atk, dfn, dur)
		# code 2 연속 공격 — 원작 `isDoubleAttack` 분기는 타격 시점을 **두 번** 잡는다
		# (`activeIcon` 이 `getAttackFrame()/30/1.5` 와 그 2배를 쓴다) ⇒ 펄스를 한 번 더.
		if code == AC_DOUBLE:
			var gen2 := _gen
			get_tree().create_timer(maxf(0.1, dur * 0.5)).timeout.connect(func() -> void:
				if gen2 == _gen and not bool(atk.get("dead", false)):
					_attack_pulse(atk, dfn, dur * 0.6))

	# code 3 회피 — 원작 `evadeEffect` + `setInvisibleSpine`/`setVisibleSpine`.
	if code == AC_EVADE:
		if not dfn.is_empty():
			_evade_back(dfn)
			_evade_effect(dfn)
		return

	# 피격 반응 — **애니는 없지만 반응은 있다**(2026-08-05 `action` 코드지도로 확정).
	#   code 0(기본 피격) → `damagedColor` = 깜빡임
	#   code −32(중독)    → `damagedColor` + `shakeLayerToHorizontal`
	#   code −54(대형 타격) → `shakeLayerAllDirection`(화면 전체 흔들림)
	# 종전엔 "모션이 없다"를 "아무것도 안 한다"로 잘못 옮겨 피격이 전혀 안 보였다.
	if not dfn.is_empty() and not bool(dfn.get("dead", false)) \
			and int(ev.get("damage", 0)) > 0:
		_damaged_color(dfn)
		# 소리·파티클은 깜빡임과 같은 순간이다 —
		#   소리 = `runSpineWithAnimationName("damaged")` (위 `_hit_sfx` 주석)
		#   파티클 = `MakeInterface::damagedEffect` @0108f4cc 의
		#            `particle/scene/colosseum/effect_damaged.plist` (대상에 붙는다)
		_hit_sfx()
		_damaged_particle(dfn)
		if code == AC_POISON or code == AC_CRIT_FX:
			# 흔들림 방향 = 맞은 쪽이 밀리는 방향(공격자 반대편).
			_shake_horizontal(dfn, 1.0 if bool(dfn.get("mine", false)) else -1.0)
		if code == AC_BIGHIT:
			_shake_screen(0.4, 1.0)

	# 상태이상 부여 — 원작 code −14 가 `activeIcon`/`getSkillIndex` 로 아이콘을 세운다.
	var buff := String(ev.get("buff", ""))
	var debuff := String(ev.get("debuff", ""))
	if buff != "" and not atk.is_empty():
		_status_icon(atk, int(ev.get("skill_id", 0)), true, int(ev.get("turns", 0)))
	if debuff != "" and not dfn.is_empty():
		_status_icon(dfn, int(ev.get("skill_id", 0)), false, int(ev.get("turns", 0)))

	# 이펙트 스파인은 **드래곤 모션과 별개**로 얹힌다(원작 castSkill 이 그렇게 만든다).
	var at: Vector2 = _body_pos(dfn)
	match t:
		"skill":
			# 원작 `createIcon` 은 이펙트와 함께 **화면 상단 스킬 이름 배너**도 낸다.
			_skill_banner(String(ev.get("skill_name", "")), int(ev.get("skill_id", 0)))
			_skill_sfx(int(ev.get("skill_id", 0)))
			_skill_spine(int(ev.get("skill_id", 0)), at)
			# 원작 `castSkill` @0108a924 의 `particle/skill/skill_%d.plist` ·
			# `particleEffect` @010908d8 의 `skill_%d_effect.plist`.
			_skill_particle(int(ev.get("skill_id", 0)), at)
		"awaken":
			# 원작 `FightScene` @00f8cd6c: `showCutIn(actor, 0.5)` → `UltimateLayer`.
			# `showCutIn` 은 `getNo()` 가 **9013/9014**(이벤트 드래곤)일 때만 전면 컷인
			# (`getImagePathCutIn`/`CutBg`)을 내고, 나머지는 크리티컬 보이스만 낸다.
			# 우리 드래곤에 9013/9014 는 없다 ⇒ 보이스 + 각성기 레이어.
			# 🟦 2026-08-05 — 원작 탐험 `setAnimatedAttackC`(코드 4·7)와 같이 **컷인을 낸다**.
			_cutin(atk)
			_crit_voice(atk)
			_awaken_fx(atk, at)
		_:
			if atk.is_empty():
				pass
			elif code == AC_CRIT_FX:
				# 코드 41 은 `criticalEffectMake` 와 함께 **`swapPosition`** 도 부른다 —
				# 뒷줄이 크리티컬을 내면 앞줄과 자리를 바꾼다(3v3 한정).
				_swap_position(atk, 0.8)
				# 크리티컬 = **공격한 드래곤 자기 크리티컬 스파인**(원작 criticalEffectMake).
				_critical_effect(atk, dfn)
				_cutin(atk)              # 🟦 위 각성기와 같은 근거(코드 4·7)
				_crit_voice(atk)
				# 드빌1에서 온 종만 자기 이펙트 시퀀스를 위에 더 얹는다(800 로키 = `col_action2`).
				_dragon_fx_seq(int(atk.get("id", 0)), "col_action2", at)
			else:
				# 평타 — 드빌1에서 온 종만 전용 평타 이펙트를 갖는다(`col_action1`).
				# 없으면 아무것도 안 뜬다(원작 콜로세움 평타에도 이펙트가 없다).
				_dragon_fx_seq(int(atk.get("id", 0)), "col_action1", at)


## 위치 교대 — 원작 `MakeInterface::swapPosition` @01087ea4 (액션 코드 **1**·**41**·**42**).
##
## 원작이 하는 일(디컴프 + 룩업표 실측):
##   행동한 드래곤의 태그 `t` 로 `DAT_021c4ae8`(태그 11~15 구간)을 찾아 **교대 상대 태그**를 얻는다.
##   실측값 = `[11, 10, 11, 10, 11]`, 구간 밖은 `10`
##   ⇒ 태그 11(내 앞줄)·10(상대 앞줄)은 **자기 자신** ⇒ 앞줄이 행동하면 교대가 없다.
##     태그 13·15(내 뒷줄) → 11, 12·14(상대 뒷줄) → 10 ⇒ **자기 진영 앞줄과 자리를 바꾼다.**
##
## ✅ 2026-08-05 **좌표 재채굴 — 종전 ASSUMPTION 두 개가 다 틀렸다**(사용자 지적 6번).
##   `swapPosition(layer, d1, d2, param4, param5)` 를 끝까지 읽고 확정한 것:
##
##     sign  = `ABS(spine.scaleX) / spine.scaleX`   ← `layer->getChildByTag(**1**)` = 스파인
##     sy    = `layer->getScaleY()`
##     슬롯  = `FUN_0105564c(layer, sceneType)`     ← **절대 슬롯 좌표**(위 SLOT_OFF 주석)
##
##     앞줄 레이어 : Delay(d1) → MoveBy(0.05, (**sign×210**, 0)) → Delay(d2+0.1)
##                   → MoveTo(0.05, **앞줄 슬롯**)
##     앞줄 그림자 : 같은 시퀀스, 목적지만 앞줄 슬롯 + (0, **sy×−95**)
##     행동자 레이어: Delay(d1+0.05) → MoveTo(0.05, **앞줄 슬롯**) → Delay(d2)
##                   → MoveTo(0.05, **자기 슬롯**)
##     행동자 그림자: 같은 시퀀스, 두 목적지 모두 −(0, sy×95)
##     반환 = d1 + **0.15**
##
##   🔴 정정 ① **방향** — `sign` 은 스파인 flipX 부호다. 우리도 원작대로 **내 팀만 flipX**
##      (scaleX<0) 하므로 sign 은 내 팀 −1 · 상대 +1 ⇒ 앞줄은 **자기 진영 바깥으로** 비켜난다.
##      종전엔 "앞으로 비켜 준다"고 읽어 **중앙 쪽**으로 밀어 반대로 움직이고 있었다.
##   🔴 정정 ② **목적지** — 원작은 전부 **슬롯 절대좌표**로 간다. 종전엔 호출 시점의 현재
##      위치(`node.position`)를 기준으로 상대 이동시켜, 다른 연출과 겹치면 자리가 어긋났다.
##   ℹ️ `getChildByTag(부모, 태그×−50)` 은 HUD 가 아니라 **그림자**다(`setShadow` 의 태그
##      −500/−550/−600… 과 정확히 일치). 우리는 그림자가 holder 의 **자식**이라 따라오고,
##      대신 HUD(`barh`)가 형제라 같이 옮긴다 — 구조는 다르지만 화면 결과는 같다.
const SWAP_STEP := 210.0
const SWAP_SEC := 0.05
const SWAP_TAIL := 0.15             # 원작 반환값 d1 + 0.15

func _swap_position(actor: Dictionary, hold: float) -> void:
	if _mode != "team" or actor.is_empty():
		return
	if int(actor.get("slot", 0)) == 0:
		return                                   # 앞줄이 행동하면 교대 없음(룩업표 11→11 / 10→10)
	var mine := bool(actor.get("mine", false))
	var front: Dictionary = _views.get(("A0" if mine else "E0"), {})
	if front.is_empty() or bool(front.get("dead", false)):
		return
	# 원작 `sign` = 스파인 flipX 부호. 내 팀만 뒤집으므로 −1 ⇒ **자기 진영 바깥**으로 비켜난다.
	var sign := -1.0 if mine else 1.0
	var fhome: Vector2 = front.get("pos", Vector2.ZERO)
	var ahome: Vector2 = actor.get("pos", Vector2.ZERO)
	var aside := Vector2(fhome.x + sign * SWAP_STEP, fhome.y)

	# 앞줄 — 옆으로 비켜났다 **자기 슬롯**으로.
	for k in ["node", "barh"]:
		var fn = front.get(k)
		if fn is Node2D and is_instance_valid(fn):
			var d: Vector2 = (fn as Node2D).position - fhome   # 슬롯 대비 이 노드의 고정 오프셋
			var t1 := (fn as Node2D).create_tween()
			t1.tween_property(fn, "position", aside + d, SWAP_SEC)
			t1.tween_interval(hold + 0.1)
			t1.tween_property(fn, "position", fhome + d, SWAP_SEC)
	# 행동자 — **앞줄 슬롯**으로 갔다 **자기 슬롯**으로.
	for k2 in ["node", "barh"]:
		var an = actor.get(k2)
		if an is Node2D and is_instance_valid(an):
			var d2: Vector2 = (an as Node2D).position - ahome
			var t2 := (an as Node2D).create_tween()
			t2.tween_interval(SWAP_SEC)
			t2.tween_property(an, "position", fhome + d2, SWAP_SEC)
			t2.tween_interval(hold)
			t2.tween_property(an, "position", ahome + d2, SWAP_SEC)
	# 교대해 있는 동안은 **그 자리가 원점**이다 — 이걸 안 옮기면 그 사이 공격의 복귀가
	# 원래 슬롯으로 튀어 자리 교대가 풀린다(`_attack_jump` ① 참조).
	front["home"] = aside
	actor["home"] = fhome
	var gen := _gen
	get_tree().create_timer(SWAP_SEC * 2.0 + hold + 0.1).timeout.connect(func() -> void:
		if gen != _gen:
			return
		front["home"] = front.get("pos", fhome)
		actor["home"] = actor.get("pos", ahome))


## 회피 — 원작 `MakeInterface::evadeEffect` @0108f078.
##   `battle.img_plist` 의 `battle/miss_%s.png` 를 피격 지점에 놓고
##   Delay(0.25) → ScaleTo(0, 2.0) → ScaleTo(0.25, 1.0) → Delay(0.25)
##   → MoveBy(0.5, (0, 75)) → FadeTo(0.5, 0) → 제거.
## (프레임 이름은 SSO 바이트 복원: 길이 0x24>>1=18 · "battle" + "/m" + "iss_%s.p" + "ng")
const EVADE_LIFT := 75.0
const EVADE_POP := 2.0

## 회피 백스텝 — 🟦 사용자 확정 2026-08-05("원작은 회피 시 드래곤 스파인이 뒤로 빠졌다").
##
## ⚠️ 근거 범위를 밝혀 둔다: 원작 `evadeEffect` @0108f078 은 **MISS 프레임 하나**만 낸다
##   (Delay 0.25 → ScaleTo 0/2.0 → ScaleTo 0.25/1.0 → Delay 0.25 → MoveBy 0.5 (0,75)
##    → FadeTo 0.5 → remove). 몸이 빠지는 안무는 이 함수에 없다 — 액션 코드 3 핸들러 쪽인데
##   `action` 이 `[skip>8000]` 이라 디컴프에 없고 아직 ASM 으로 못 짚었다.
## ⇒ 크기·시간은 같은 파일에서 이미 확인된 피격 흔들림(`shakeLayerToHorizontal`,
##   0.05초 단위)과 같은 단위로 맞췄다. 원작 상수를 찾으면 여기만 갈아 끼우면 된다.
const EVADE_BACK_PX := 45.0
const EVADE_BACK_SEC := 0.08
const EVADE_HOLD := 0.12

## 회피한 드래곤이 공격자 반대쪽으로 물러났다 돌아온다.
func _evade_back(v: Dictionary) -> void:
	var n = v.get("node")
	if not (n is Node2D) or not is_instance_valid(n):
		return
	var node := n as Node2D
	var home: Vector2 = v.get("home", node.position)
	# 뒤 = 자기 진영 바깥쪽(내 팀은 −x, 상대는 +x).
	var back := -1.0 if bool(v.get("mine", false)) else 1.0
	var old = v.get("move_tw")
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var t := node.create_tween()
	v["move_tw"] = t
	t.tween_property(node, "position",
		home + Vector2(back * EVADE_BACK_PX, 0.0), EVADE_BACK_SEC)
	t.tween_interval(EVADE_HOLD)
	t.tween_property(node, "position", home, EVADE_BACK_SEC)

func _evade_effect(dfn: Dictionary) -> void:
	# 회피 효과음 — 원작 `music/effect_evade.mp3`(실재). 전투 씬이
	# `MakeInterface::preloadHeavyResource`(MakeInterface.c:37956)로 올려 두는 음원이라
	# 소유는 전투다. 모험(`battle.gd` miss 분기)과 같은 음원을 쓴다.
	Bgm.sfx("effect_evade")
	var at: Vector2 = dfn.get("pos", _vis() * 0.5)
	var s := _spr("battle_ui", "battle_miss_kr", Design.ASSET_SCALE)
	if s == null:
		return
	s.position = at - Vector2(0.0, DMG_LIFT)
	s.z_index = 100
	s.scale *= EVADE_POP
	add_child(s)
	var base := Design.ASSET_SCALE
	var tw := s.create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(s, "scale", Vector2(base, base), 0.25)
	tw.tween_interval(0.25)
	tw.tween_property(s, "position", s.position - Vector2(0.0, EVADE_LIFT), 0.5)
	tw.parallel().tween_property(s, "modulate:a", 0.0, 0.5)
	tw.tween_callback(s.queue_free)


# ---------- 상태이상 아이콘 — 원작 `MakeInterface::createIcon` @0109272c ----------
#
# 원작 자산(리터럴 전수): `skill/%d.png`(스킬 아이콘 75×75) · `skill/buff.png` ·
#   `skill/debuff.png`(85×85 테두리) · `font/font_normal.fnt`(남은 턴) ·
#   `skill/skill_zzing_spine`(부여 순간의 반짝임) · `scene/colosseum/skill_txt_bg.png`(이름 배너)
# 지속 아이콘의 기본 크기는 `MakeInterface::activeIcon` @01092044 의 마지막
#   `ScaleTo(t, 0.375)` 에서 읽는다 — 발동할 때마다
#   `ScaleTo(t, 0.5, 0.3) → (0.3, 0.5) → (0.375)` 로 튄다.
const ICON_BASE := 0.375
const ICON_PULSE := 0.1
const ICON_STEP := 40.0
const ICON_MAX := 4

func _status_icon(v: Dictionary, skill_id: int, is_buff: bool, turns: int) -> void:
	var host = v.get("icons")
	if not (host is Node2D) or not is_instance_valid(host):
		return
	var box := host as Node2D
	# 같은 스킬이 이미 붙어 있으면 원작 `activeIcon` 처럼 **다시 튀게만** 한다.
	var name_key := "ic%d" % skill_id
	var old := box.get_node_or_null(NodePath(name_key))
	if old != null:
		_icon_pulse(old as Node2D)
		var lb := old.get_node_or_null("t")
		if lb is Label:
			(lb as Label).text = str(maxi(0, turns))
		return
	if box.get_child_count() >= ICON_MAX:
		return
	_zzing(v)                       # 새로 붙는 순간에만 — 재발동은 위 `activeIcon` 펄스다

	var holder := Node2D.new()
	holder.name = name_key
	holder.position = Vector2(box.get_child_count() * ICON_STEP, 0.0)
	holder.scale = Vector2.ONE * ICON_BASE
	box.add_child(holder)

	var ring := _spr("skill_ui", "skill_buff" if is_buff else "skill_debuff", Design.ASSET_SCALE)
	if ring != null:
		holder.add_child(ring)
	var ic := _spr("skill_ui", "skill_%d" % skill_id, Design.ASSET_SCALE)
	if ic != null:
		holder.add_child(ic)
	if turns > 0:
		var l := Label.new()
		l.name = "t"
		l.text = str(turns)
		l.size = Vector2(80.0, 40.0)
		l.position = Vector2(-4.0, -66.0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_bm_style(l, 36, Color.WHITE, "font_normal")
		holder.add_child(l)
	# 정화(26)가 **해로운 것만** 지울 수 있게 성격을 남긴다.
	holder.set_meta("buff", is_buff)
	_icon_pulse(holder)


## 남은 턴 갱신 — 0 이하면 아이콘을 떼고 줄을 다시 붙인다(원작 `removeIcon` 자리).
func _tick_icon(v: Dictionary, skill_id: int, turns: int) -> void:
	var host = v.get("icons")
	if not (host is Node2D) or not is_instance_valid(host) or skill_id <= 0:
		return
	var box := host as Node2D
	var n := box.get_node_or_null(NodePath("ic%d" % skill_id))
	if n == null:
		return
	if turns <= 0:
		box.remove_child(n)
		n.queue_free()
		_relayout_icons(box)
		return
	var lb = n.get_node_or_null("t")
	if lb is Label:
		(lb as Label).text = str(turns)


## 해로운 효과 아이콘 전부 제거(빛의 정화).
func _clear_debuff_icons(v: Dictionary) -> void:
	var host = v.get("icons")
	if not (host is Node2D) or not is_instance_valid(host):
		return
	var box := host as Node2D
	for c in box.get_children():
		if not bool((c as Node).get_meta("buff", false)):
			box.remove_child(c)
			c.queue_free()
	_relayout_icons(box)


## 아이콘 줄을 왼쪽부터 다시 붙인다.
func _relayout_icons(box: Node2D) -> void:
	var i := 0
	for c in box.get_children():
		if c is Node2D:
			(c as Node2D).position = Vector2(float(i) * ICON_STEP, 0.0)
		i += 1


## 상태이상이 **새로 붙는 순간**의 반짝임 — 원작 `createIcon` 이 같은 시퀀스 안에서 낸다.
##   `skill/skill_zzing_spine.spine_json` + `.img_plist`, createWithFile(…, 1.0)
##   Delay(param_6 + **0.5**) → … → runSpineWithAnimationName("animation") → Delay(**1.0**) → 제거
const ZZING_SCENE := "res://scenes/fx/skill_zzing_spine.tscn"
const ZZING_DELAY := 0.5
const ZZING_HOLD := 1.0

func _zzing(v: Dictionary) -> void:
	if not ResourceLoader.exists(ZZING_SCENE):
		return
	var holder := Node2D.new()
	holder.z_index = 101
	holder.position = _body_pos(v)
	holder.visible = false
	add_child(holder)
	var inst = (load(ZZING_SCENE) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap := _find_anim_player(inst)
	var gen := _gen
	get_tree().create_timer(ZZING_DELAY).timeout.connect(func() -> void:
		if gen != _gen or not is_instance_valid(holder):
			return
		holder.visible = true
		if ap != null and ap.has_animation("animation"):
			ap.get_animation("animation").loop_mode = Animation.LOOP_NONE
			ap.play("animation"))
	var tw := holder.create_tween()
	tw.tween_interval(ZZING_DELAY + ZZING_HOLD)
	tw.tween_callback(holder.queue_free)


## 원작 `activeIcon` 의 발동 펄스. 기본 0.375 로 돌아온다.
func _icon_pulse(n: Node2D) -> void:
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector2(0.5, 0.3), ICON_PULSE)
	tw.tween_property(n, "scale", Vector2(0.3, 0.5), ICON_PULSE)
	tw.tween_property(n, "scale", Vector2.ONE * ICON_BASE, ICON_PULSE)


# ---------- 스킬 이름 배너 — 같은 `createIcon` 의 상단 표시 ----------
#
# 원작: `scene/colosseum/skill_txt_bg.png`(530×47) 를 `VisibleRect::top + (0, −150)` 에 두고
#   opacity 0 → Delay → FadeTo(0.15, 255) → Delay(1.15) → FadeTo(0.1, 0) → 제거.
#   그 위에 `getSkillName()` BMFont(subtitle), 아래 `Skill::getShort()` 짧은 설명이
#   `top + (0, −200)` 자리에서 배너로 올라온다(ScaleTo 1.65/1.35 + MoveTo 0.25).
# ⚠️ 우리는 **최종 배치**(레퍼런스 `docs/ref/pvp/화면 캡처 …202630.png` 의 "철갑 방패 / 적 피해 감소")
#   와 페이드 타이밍까지 옮기고, 설명 라벨이 이름 자리에서 배너로 **날아오르는 중간 안무**는
#   생략했다 — 원작 시퀀스의 인자 순서를 디컴프에서 확신할 수 없어서다(HARD RULE 6).
const BANNER_Y := 150.0
const BANNER_SUB_Y := 200.0
const BANNER_IN := 0.15
const BANNER_HOLD := 1.15
const BANNER_OUT := 0.1

func _skill_banner(sname: String, skill_id: int) -> void:
	if sname == "":
		return
	var vis := _vis()
	var root := Node2D.new()
	root.z_index = 120
	root.modulate.a = 0.0
	add_child(root)

	var bg := _spr(CO, "scene_colosseum_skill_txt_bg", Design.ASSET_SCALE)
	if bg != null:
		bg.position = Vector2(vis.x * 0.5, BANNER_Y)
		root.add_child(bg)

	var nm := Label.new()
	nm.text = sname
	nm.size = Vector2(vis.x, 40.0)
	nm.position = Vector2(0.0, BANNER_Y - 20.0)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bm_style(nm, 30, Color.WHITE)
	root.add_child(nm)

	# 짧은 설명 — 원작 `Skill::getShort()` @01523868 은 `info_skill` 의 별도 열을 그대로 돌려주는
	# 게터인데(멤버 +0x130), **그 열은 서버 DB 와 함께 유실**됐다. 우리가 가진 가장 가까운 것이
	# `skills.json` 의 `effect_text` 라 그걸 쓴다(레퍼런스의 "적 피해 감소" 자리).
	var short := String((Data.skills.get(str(skill_id), {}) as Dictionary).get("effect_text", ""))
	if short != "":
		var sl := Label.new()
		sl.text = short
		sl.size = Vector2(vis.x, 32.0)
		sl.position = Vector2(0.0, BANNER_SUB_Y - 16.0)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_bm_style(sl, 21, Color.WHITE)
		root.add_child(sl)

	var tw := root.create_tween()
	tw.tween_property(root, "modulate:a", 1.0, BANNER_IN)
	tw.tween_interval(BANNER_HOLD)
	tw.tween_property(root, "modulate:a", 0.0, BANNER_OUT)
	tw.tween_callback(root.queue_free)


# ---------- 스킬/크리티컬 이펙트 스파인 ----------
#
# 원작 `MakeInterface::castSkill` @0108a924 이 쓰는 자산(리터럴 전수):
#     "skill/skill_%d_spine.spine_json" + "skill/skill_%d_spine.img_plist"
#     "particle/skill/skill_%d.plist"
#     애니명 "animation"
# ⇒ 스킬 연출은 **드래곤 모션이 아니라 별도 이펙트 스파인**이다(castSkill 은 드래곤 애니로는
#   "attack" 만 건드린다). 노출 시간은 원작이 애니 길이와 무관하게 0.7초 뒤 Hide 다.
#
# 우리 프로젝트엔 이 파이프라인이 **이미 있다** — `scenes/fx/skill_<id>_spine.tscn` 41종 +
# `battle.gd::_play_skill_spine` 이 같은 규약(z=100 · animation/work/destroy · 0.7초)으로
# 재생한다. 새로 짜지 않고 같은 규약을 따른다(§3 우리 코드 먼저).
const SKILL_SPINE_SEC := 0.7


# ---------- 효과음 / 파티클 ----------
#
# 🔎 2026-08-05 조회 결과(사용자 지적 "콜로세움 공격 효과음·이펙트"):
#   `MakeInterface` 안의 `SoundManager::playEffect` 13곳을 전수로 함수에 매핑했더니
#   **전투 중 소리를 내는 곳은 둘뿐**이다 —
#     ① `runSpineWithAnimationName` @0104f468 — 애니가 `"damaged"` 면 피격음(위 `_hit_sfx`),
#        `"appear"` 면 `music/voice1.mp3`.
#     ② `deadEffect` @0109a654 — `music/effect_dead.mp3` 볼륨 0.5.
#   나머지는 전부 버튼/로비음이고, `castSkill` @0108a924 · `action` @01062fd4(ASM 전수)에는
#   **사운드 문자열이 하나도 없다.**
#
#   ⚠️ 그래서 **스킬 효과음의 재생 지점은 콜로세움 경로에서 못 찾았다.**
#      `FightScene::init` 이 `preloadHeavyResource` 로 `effect_skill_%d.mp3` 24종을 통째로
#      올리지만, 그 프리로드는 `BattleScene`·`OpeningBattleScene` 과 **공유**라 근거가 못 된다.
#      # ASSUMPTION: 탐험(`AdventureScene` @57622 `music/effect_skill_%d.mp3`)에서 **전수 대조로
#      확정된** 같은 규약을 그대로 쓴다(N 24종이 전부 skills.json 의 스킬 id). 파일이 없으면
#      아무 소리도 내지 않는다 — 카테고리 폴백 같은 자작 대체는 두지 않는다.

## 스킬 효과음 — 전용 음원이 있는 스킬만 낸다.
func _skill_sfx(sid: int) -> void:
	if sid <= 0:
		return
	var own := "effect_skill_%d" % sid
	if ResourceLoader.exists("res://assets/music/%s.mp3" % own):
		Bgm.sfx(own)


## 피격 파티클 — 원작 `MakeInterface::damagedEffect` @0108f4cc.
## `particle/scene/colosseum/effect_damaged.plist` 를 **대상 드래곤 레이어**에 z=6 으로 붙인다.
func _damaged_particle(v: Dictionary) -> void:
	var n = v.get("node")
	if not (n is Node2D) or not is_instance_valid(n):
		return
	CocosParticle.spawn(n as Node2D, "colosseum_damaged",
		Vector2(0.0, -float(v.get("dragon_h", DRAGON_H)) * 0.5), 6, 0.9)


## 격파 연출 — 원작 `MakeInterface::deadEffect` @0109a654.
## `particle/scene/colosseum/effect_dead.plist` + `music/effect_dead.mp3`(볼륨 0.5).
const DEAD_SFX_VOL := 0.5           # 원작 playEffect 3번째 인자 0x3f000000

func _dead_fx(v: Dictionary) -> void:
	Bgm.sfx("effect_dead", DEAD_SFX_VOL)
	var n = v.get("node")
	if n is Node2D and is_instance_valid(n):
		CocosParticle.spawn(n as Node2D, "colosseum_dead",
			Vector2(0.0, -float(v.get("dragon_h", DRAGON_H)) * 0.5), 7, 0.9)


## 스킬 파티클 — 원작 `castSkill` 의 `particle/skill/skill_%d.plist` 와
## `particleEffect` @010908d8 의 `particle/skill/skill_%d_effect.plist`.
## 변환된 것만 뜬다(원작에 있는 파일도 6종뿐이다).
func _skill_particle(sid: int, at: Vector2) -> void:
	if sid <= 0:
		return
	for name in ["skill_%d" % sid, "skill_%d_effect" % sid]:
		if CocosParticle.spawn(self, name, at, 101, 0.9) != null:
			return


## 스킬 이펙트 스파인 1회 재생. 없으면 false.
func _skill_spine(sid: int, at: Vector2) -> bool:
	var path := "res://scenes/fx/skill_%d_spine.tscn" % sid
	if sid <= 0 or not ResourceLoader.exists(path):
		return false
	var holder := Node2D.new()
	holder.z_index = 100                       # 원작 addChild(spine, 100)
	holder.position = at
	add_child(holder)
	var inst = (load(path) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap := _find_anim_player(inst)
	if ap != null:
		# 원작 스킬 스파인은 `animation`(본체) + `work`/`destroy`(뒤처리)를 갖는다.
		var pick := ""
		for cand in ["animation", "work", "destroy"]:
			if ap.has_animation(cand):
				pick = cand
				break
		if pick == "":
			holder.queue_free()
			return false
		ap.get_animation(pick).loop_mode = Animation.LOOP_NONE
		ap.play(pick)
	var t := holder.create_tween()
	t.tween_interval(SKILL_SPINE_SEC)          # 원작 Delay(0.7) → Hide
	t.tween_callback(holder.queue_free)
	return true


## 드래곤 **전용 이펙트 프레임 시퀀스** 1회 재생. 없으면 false.
##
## DV2 원작에는 "드래곤별 이펙트"라는 축이 없다 — 이펙트는 스킬 단위(`skill_<id>_spine`)다.
## 이 경로는 **드빌1에서 이식한 종**이 자기 이펙트를 들고 오기 때문에 생겼다
## (800 로키: `col_action1` 12프레임 = 평타 · `col_action2` 16프레임 = 크리티컬).
## 🟦 사용자 확정 2026-08-04. 상세 = `docs/ref/porting/DragonLoki800.md` §5-C.
##
## 프레임마다 크기가 달라서 **원본 캔버스(src 800×480) 기준 트림 오프셋(off)** 으로 정렬한다.
## 안 그러면 재생 중 중심이 흔들린다(`dv2-atlas-trim-offset` 과 같은 축).
const FX_SEQ_FPS := 24.0

func _dragon_fx_seq(did: int, prefix: String, at: Vector2) -> bool:
	if did <= 0:
		return false
	var dir := "dragon_%d_fx" % did
	var man := _man(dir)
	if man.is_empty():
		return false
	var keys: Array = []
	for k in man:
		if String(k).begins_with("dragon_%d_%s_" % [did, prefix]):
			keys.append(String(k))
	if keys.is_empty():
		return false
	keys.sort()                                   # …_00, _01, … 프레임 순서
	var holder := Node2D.new()
	holder.z_index = 100                          # 스킬 이펙트와 같은 층
	holder.position = at
	add_child(holder)
	var shown: Array[Sprite2D] = []
	for k in keys:
		var ent: Dictionary = man.get(k, {})
		var spr := _spr(dir, k, Design.ASSET_SCALE)
		if spr == null:
			continue
		var off: Array = ent.get("off", [0, 0])
		# cocos off = (트림중심 − 원본캔버스중심), y-up → Godot 은 y 를 뒤집는다.
		spr.position = Vector2(float(off[0]), -float(off[1])) * Design.ASSET_SCALE
		spr.visible = false
		holder.add_child(spr)
		shown.append(spr)
	if shown.is_empty():
		holder.queue_free()
		return false
	var step := 1.0 / FX_SEQ_FPS        # 콜로세움엔 전투 배속 개념이 없다(탐험과 다른 점)
	var tw := holder.create_tween()
	for i in shown.size():
		var s: Sprite2D = shown[i]
		var prev: Sprite2D = shown[i - 1] if i > 0 else null
		tw.tween_callback(func() -> void:
			if prev != null and is_instance_valid(prev):
				prev.visible = false
			if is_instance_valid(s):
				s.visible = true)
		tw.tween_interval(step)
	tw.tween_callback(holder.queue_free)
	return true


## 크리티컬 이펙트 — 원작 `MakeInterface::criticalEffectMake` @01089a1c (액션 코드 **41**).
##
##   getAwaken()==0 ? "dragon/dragon_%d_critical_spine.spine_json"
##                  : "dragon/dragon_%d_e_critical_spine.spine_json"   (폴백 `dragon_9998_…`)
##   아틀라스 = `dragon/dragon_%d_spine.img_plist` · createWithFile(…, 1.0)
##   setScaleX(음수 = 공격 방향으로 X 반전) · addChild(spine, **8**, −2)
##   재생 = Show → runSpineWithAnimationName("animation") → DelayTime(getDuration("animation"))
##   ⚠️ 붙는 곳은 **공격자가 아니라 대상(target)의 레이어**다 — 스파인만 공격자 것을 쓴다.
##   (탐험 쪽 `battle.gd::_critical_spine` 이 같은 함수를 이미 이식해 뒀다 — 같은 규약을 따른다.)
##
## 🔴🔴 2026-08-05 **재정정** — 하루 전의 "원작 크리티컬은 공용 9999 컷인" 은 **틀렸다.**
##   사용자 지적("전투 중간에 금발 소녀 애니가 뜬다")으로 다시 팠더니:
##     · `dragon/dragon_9999_critical{,_ready,_shot}_spine` 을 만드는 블록은 `action` 안에서
##       **`01064694 cmp w19,#0x29a` / `01064698 b.eq 0x01069eac` 단 한 곳**으로만 들어온다.
##       `w19` = 액션 코드이므로 그 컷인은 **액션 코드 666 전용**이다(점프테이블 −54~170 밖의
##       특수 코드라 `default` 비교 사다리에서 걸린다). 우리 `Battle.simulate()` 는 666 을
##       만들지 않는다 ⇒ **어떤 대전에서도 뜨면 안 되는 연출**이었다.
##     · dragon 9999 는 드래곤이 아니다 — `dragons.json` 에 없고, 스켈레톤을 렌더해 보면
##       **거대한 새총을 든 금발 소녀**(누리)다. 이벤트 매치용 캐릭터로 보인다.
##     · 진짜 크리티컬은 **41 `criticalEffectMake`**(공격자 자기 크리티컬 스파인, 폴백 9998) 와
##       **43**(공격자 스파인의 `"critical"` → `"wait"` 애니) 다. 코드 0 의 배타 신호에도
##       `isCritical`/`getCriticalFrame` 이 있어 **타격 프레임만 크리티컬용으로 바뀐다**.
##     · **4 `showCutIn` 은 각성기 컷인**이다 — `FightScene` 이 `UltimateLayer` 를 만들기
##       **직전에** 부르고(@00f8cd6c), 내부는 `getNo()==0x2335(9013) || 0x2336(9014)` 일 때만
##       `Cutin::show(getImagePathCutIn, getImagePathCutBg)` 를 낸다. 그 밖의 드래곤은
##       `getDragonVoiceCriticalFilePath()` = **보이스만**.
##   ⇒ 9999 컷인 코드는 지웠다. 되살릴 근거(액션 코드 666 을 쓰는 이벤트 매치)가 생기면
##     복원 안무는 `docs/ref/porting/Colosseum.md` §8.7 에 적어 뒀다.
## ⚫ 원작 `criticalEffectMake` 의 폴백(`dragon_9998_critical`)은 **쓰지 않는다** —
##    아래 `_critical_effect` 주석 참조(에셋 미다운로드 자리표시자였다).

func _critical_effect(atk: Dictionary, dfn: Dictionary) -> bool:
	var cid := int(atk.get("id", 0))
	# 🔴 2026-08-05 — 각성 여부를 본다. 종전엔 `_e_critical` 이 있으면 **미각성 드래곤도**
	#   각성 크리티컬 스파인을 썼다(본체 스파인과 단계가 어긋난다).
	var path := "res://scenes/dragons/dragon_%d_critical.tscn" % cid
	if bool(atk.get("awakened", false)):
		var ep := "res://scenes/dragons/dragon_%d_e_critical.tscn" % cid
		if ResourceLoader.exists(ep):
			path = ep
	# 🔴 2026-08-05(사용자 지적 "크리티컬에 울음소리만 난다") — **원작 폴백을 빠뜨렸다.**
	#   `criticalEffectMake` @01089a1c 는 자기 크리 스파인이 없으면
	#   `dragon/dragon_**9998**_critical_spine.spine_json` 를 쓴다 — 그래서 폴백을 달았었다.
	#
	# 🔴🔴 2026-08-05 **재정정(사용자 지적 "노란 다운로드 아이콘 박스가 뜬다")** — 그 폴백은
	#   연출이 아니라 **원작의 '에셋 미다운로드' 자리표시자**였다. 변환본
	#   `assets/converted/critical_9998/dragon_9998_critical.png` 을 열어 보면
	#   **노란 다운로드 아이콘 상자 + 드래곤 금지 표지 5개**다 — 그림 자체가 "이 종의 리소스를
	#   아직 못 받았다"는 개발용 표시다(원작은 드래곤 에셋을 온디맨드로 내려받았다).
	#   우리는 전 에셋이 로컬에 있으므로 이 상태가 존재할 수 없다 ⇒ **폴백을 쓰지 않는다.**
	#   크리 스파인이 없는 종은 원작에서도 볼 수 없던 그림 대신 아무것도 내지 않고,
	#   호출부가 그 자리에서 크리티컬 보이스·타격 프레임만 낸다(`_motion` 코드 41/43 경로).
	if cid <= 0 or not ResourceLoader.exists(path):
		return false
	var holder := Node2D.new()
	holder.z_index = 8                          # 원작 addChild(spine, 8, −2)
	# 원작은 **대상 레이어**에 붙인다.
	var node = dfn.get("node")
	if node is Node2D and is_instance_valid(node):
		(node as Node2D).add_child(holder)
		# 원작 레이어 앵커는 몸통 중앙 — 우리 holder 원점은 발밑이다(`_body_pos` 주석).
		holder.position = Vector2(0.0, -float(dfn.get("dragon_h", DRAGON_H)) * 0.5)
	else:
		add_child(holder)
		holder.position = _body_pos(dfn)
	# 원작 setScaleX(음수) — 공격 방향으로 뒤집는다.
	holder.scale = Vector2(-1.0 if bool(atk.get("mine", false)) else 1.0, 1.0)
	var inst = (load(path) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap := _find_anim_player(inst)
	var pick := ""
	if ap != null:
		# 원작은 `"animation"` 하나만 쓴다. 일부 스켈레톤은 이름이 `critical` 이다(데이터 편차).
		for cand in ["animation", "critical"]:
			if ap.has_animation(cand):
				pick = cand
				break
	if pick == "":
		holder.queue_free()
		return false
	ap.get_animation(pick).loop_mode = Animation.LOOP_NONE
	ap.play(pick)
	# 원작 CCDelayTime(getDuration("animation")) — 고정 초가 아니라 애니 길이만큼.
	var t := holder.create_tween()
	t.tween_interval(ap.get_animation(pick).length)
	t.tween_callback(holder.queue_free)
	return true


## 크리티컬 보이스 — 원작 `showCutIn` 의 비-이벤트 분기가 내는 유일한 것
## (`Dragon::getDragonVoiceCriticalFilePath()` → `music/voice<N>.mp3`).
## 매핑은 `data/dragon_voices.json` `voices.<id>.critical`(유실분을 사용자 검수로 채운 값).
func _crit_voice(atk: Dictionary) -> void:
	var id := int(atk.get("id", 0))
	var v := int((Data.dragon_voices.get("voices", {}).get(str(id), {}) as Dictionary).get("critical", 0))
	if v > 0:
		Bgm.sfx("voice%d" % v)


## 화면 흔들림 — 원작 `MakeInterface::shakeLayerToVertical` / `Shake::actionWithDuration`.
## 진폭은 원작 인자(0.5)를 픽셀로 환산한 값이 아니라 **비율**이므로 화면 크기에 맞춰 쓴다.
## # ASSUMPTION: Shake 클래스의 진폭 단위를 특정하지 못해 픽셀 환산은 우리가 정했다.
func _shake_screen(sec: float, amp: float) -> void:
	var base := position
	var tw := create_tween()
	var steps := maxi(2, int(sec / 0.05))
	for k in steps:
		var d := amp * 18.0 * (1.0 - float(k) / float(steps))
		tw.tween_property(self, "position",
			base + Vector2(0.0, d if k % 2 == 0 else -d), 0.05)
	tw.tween_property(self, "position", base, 0.05)


## 각성기(궁극기) 이펙트 — 원작 `UltimateLayer`(138메서드)가 **속성별 전용 아트**를 쓴다:
##     `skill/ultimate/<element>/<element>_*.png`  (aqua/chaos/dark/earth/fire/holy/light/
##     shadow/wind 9종 — 2026-08-04 cocos_export 로 전량 변환)
## 각 속성이 바닥 링 `<el>_circle1~3` + 번호가 붙은 시퀀스(fire=explosion1~6 ·
## wind=whirl1~4 · aqua=shark1~3 …)를 갖는다 ⇒ **링 + 프레임 시퀀스**가 기본 골격이다.
##
## ⚠️ 여기 구현한 건 그 골격까지다. `UltimateLayer` 전체 안무(속성별 개별 연출 · 카메라 ·
##   `battle/<combine>/combine_outline` 합체 외곽선 · `particle/scene/colosseum/effect_damaged`)
##   는 아직 이식 전이다 — 자산은 이제 다 있으니 이어서 붙이면 된다.
##
## 2026-08-05 **본체를 `scripts/ui/ultimate_fx.gd` 로 옮겼다** — 개발 확인 창
## (`scripts/tools/dev_ultimate_fx.gd`, 씬 `scenes/dev_ultimate_fx.tscn`)이 **대전과 같은 코드**를
## 재생해야 "구현상황 확인"이 성립한다. 연출 수정은 그 파일에서 한다.
# ---------- 각성기 시전자 배치 — 원작 `UltimateLayer::initPosition` @00fe75ec ----------
#
# 🔴 2026-08-05(사용자 지적 6번 "각성기 때 양측 드래곤 위치가 원작과 다르다") — 그 자리를 찾았다.
#   `runUltimate` 는 속성별 `run<El>` 을 돌리기 **전에** `initPosition(actorLayer, element, delay)`
#   로 시전자를 무대 가운데로 옮긴다. 리터럴 전수:
#
#     sign = ABS(spine.scaleX)/spine.scaleX      ← `layer->getChildByTag(1)`(= 스파인)
#     dx   = **+225** (sign == −1, 즉 내 팀) / **−225** (상대)      ⇒ 둘 다 **중앙 쪽**
#     hold = `DAT_021af270[element−1]` = 7.85~10.25초(속성별)
#     s    = 시전자 레이어 스케일(`this+0x22c`, 3v3 0.75 / 1v1 1.0)
#
#     레이어 : Delay(d) → CCJumpBy(**0.25**, (dx,0), height **s×150**, jumps 1)
#              → Delay(hold) → CCJumpTo(0.25, 원래 슬롯, height s×150, 1)
#     그림자 : Delay(d) → MoveBy(0.25, (dx,0)) + Seq(ScaleTo(0.125, s×1.75), ScaleTo(0.125, s×2))
#              → Delay(hold) → MoveTo(0.25, 원자리) + 같은 스케일 펄스
#     스파인 : Delay(hold + d + **0.5**) → ScaleTo(0.1, sx, **0.95**) → (0.1, sx', **1.05**)
#              → (0.1, sx, 1.0)                                   = 착지 스쿼시
#
# ⚠️ 우리 구조 차이 — 그림자는 holder 의 **자식**이라 이동은 저절로 따라온다(원작은 형제라
#    따로 옮긴다). 스케일 펄스만 따로 준다.
# ⚠️ `hold` 는 위 표 대신 **`UltimateFx.DURATION`**(같은 원작 계열의 콜로세움 표
#    `DAT_021af294`)을 쓴다 — 화면에 실제로 도는 우리 연출의 길이가 그쪽이라
#    (`_evt_delay("awaken")` 도 같은 표) 복귀 시점이 연출 끝과 맞는다.
const ULT_DX := 225.0               # 원작 ±225 — **화면 가장자리에서** 안쪽으로
const ULT_DROP := 50.0              # 원작 (…, −50)
const ULT_JUMP_SEC := 0.25
const ULT_JUMP_H := 150.0           # 원작 s × 150
const ULT_LAND_LAG := 0.5           # 원작 Delay(hold + d + 0.5)
const ULT_SQUASH := [Vector2(1.0, 0.95), Vector2(1.0, 1.05), Vector2(1.0, 1.0)]
const ULT_SQUASH_SEC := 0.1
const ULT_TAKEOFF_LAG := 0.2        # 원작 initPosition: 도약 0.2초 뒤 ScaleTo(0.1, 1.05, 0.95)
const ULT_SHADOW_PULSE := [1.75, 2.0]
const ULT_SHADOW_SEC := 0.125
## 원작 `initPosition` 이 쓰는 hold 표(`DAT_021af270`, 탐험 쪽). 기록용 — 위 ⚠️ 참조.
const ULT_HOLD_ORIG := {"aqua": 9.75, "chaos": 9.65, "dark": 9.75, "earth": 7.85,
	"fire": 9.25, "holy": 10.0, "light": 10.25, "shadow": 9.4, "wind": 9.4}

## 시전자를 무대로 올린다. 반환 = 총 소요 초.
##
## 🔴 2026-08-05 재작성 — `runUltimate`/`initPosition`/`action<El>_C` 재정독 + 레퍼런스 영상으로
##   종전의 세 가지 오류를 바로잡았다:
##   ① **시전자는 사라지지 않는다.** `adjustActionAllChild(…, false)` 는 **tag 1(몸통)을 제외**하고
##      페이드를 건다 — 사라지는 건 HUD 뿐이다(영상 실측: HP 바만 사라지고 몸통은 계속 불을 뿜는다).
##   ② **적군은 숨지 않는다.** `initPosition` 이 옮기는 건 시전자 **팀의 나머지 2마리**(태그
##      ±{10,12,14} 세트)뿐 — 화면 반폭만큼 점프해 퇴장했다가 hold 뒤 복귀한다. 피격자는
##      그대로 서서 저글링당한다. (+ 죽은 드래곤 시체는 Hide/Show.)
##   ③ **1.0초 지연 후 점프.** `runUltimate(1.0)` 의 delay 가 모든 무대 연출 앞에 붙는다.
func _ultimate_position(atk: Dictionary) -> float:
	var n = atk.get("node")
	if not (n is Node2D) or not is_instance_valid(n):
		return 0.0
	var node := n as Node2D
	var home: Vector2 = atk.get("home", node.position)
	var mine := bool(atk.get("mine", false))
	var s := DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO
	# 무대 자리 = 절대 좌표. 원작 `initPosition`:
	#   내 팀 → `VisibleRect::left() + (225, −50)` · 상대 → `right() + (−225, −50)`
	var vis := _vis()
	var stage := Vector2(ULT_DX if mine else vis.x - ULT_DX,
		vis.y * 0.5 + ULT_DROP)     # cocos −50(y-up) ⇒ 우리 화면에선 아래로 +50
	var el := String(atk.get("element", ""))
	# 팀원 퇴장 hold = 원작 `DAT_021af270`(탐험 표) — 복귀 시각이 연출 끝과 맞물린다.
	var hold := float(ULT_HOLD_ORIG.get(el, 9.0))

	var old = atk.get("move_tw")
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	# 시전자 — `initPosition`: Delay(1.0) → JumpTo(0.25, stage, S*150, 1).
	# 그 뒤의 무대 안무(부양·통통 점프·중앙 이동·소멸/재등장)와 스파인 3단계
	# (ultimate1 → ultimate2 → wait)는 **속성별 실측**을 `UltimateFx.caster_fx` 가 낸다.
	var t := create_tween()
	atk["move_tw"] = t
	t.tween_interval(UltimateFx.LEAD)
	_tween_jump(t, node, home, stage, ULT_JUMP_H * s, ULT_JUMP_SEC, 1.0)
	var total := UltimateFx.caster_fx({
		"node": node, "anim": atk.get("anim"), "shadow": atk.get("shadow"),
		"home": home, "stage": stage, "scale": s, "host": self,
	}, el)
	# 각성기가 도는 동안은 무대 자리가 원점이다(공격 복귀가 슬롯으로 튀지 않게).
	atk["home"] = stage
	var gen := _gen
	get_tree().create_timer(total).timeout.connect(func() -> void:
		if gen == _gen:
			atk["home"] = atk.get("pos", home))

	# 그림자 — `initPosition`: Delay(1.0) → Spawn(MoveTo(0.25, stage−(0,S*95)),
	#   ScaleTo(0.125, S*1.75) → ScaleTo(0.125, S*2.0)). 끝에 원복.
	# (물·바람은 caster_fx 가 속성 전용 그림자 안무를 내므로 여기선 건너뛴다.)
	var shadow = atk.get("shadow")
	if shadow is Node2D and is_instance_valid(shadow) and not (el in ["aqua", "wind"]):
		var bs: Vector2 = (shadow as Node2D).scale
		var sw := (shadow as Node2D).create_tween()
		sw.tween_interval(UltimateFx.LEAD)
		for m: float in ULT_SHADOW_PULSE:
			sw.tween_property(shadow, "scale", bs * m, ULT_SHADOW_SEC)
		sw.tween_interval(maxf(0.0, total - UltimateFx.LEAD - ULT_SHADOW_SEC * 2.0))
		sw.tween_property(shadow, "scale", bs, ULT_JUMP_SEC)

	# 도약 스쿼시 — `initPosition`: Delay(1.0+0.2) → ScaleTo(0.1, ±1.05, 0.95)
	#   → ScaleTo(0.1, ±0.95, 1.05) → ScaleTo(0.1, 1, 1) 3단.
	var sp0 = atk.get("spine")
	if sp0 is Node2D and is_instance_valid(sp0):
		var b0: Vector2 = (sp0 as Node2D).scale
		var tk := (sp0 as Node2D).create_tween()
		tk.tween_interval(UltimateFx.LEAD + ULT_TAKEOFF_LAG)
		tk.tween_property(sp0, "scale", Vector2(b0.x * 1.05, b0.y * 0.95), ULT_SQUASH_SEC)
		tk.tween_property(sp0, "scale", Vector2(b0.x * 0.95, b0.y * 1.05), ULT_SQUASH_SEC)
		tk.tween_property(sp0, "scale", b0, ULT_SQUASH_SEC)

	# HUD — 원작은 드래곤 레이어의 자식이라 같이 뛰고, `action<El>_C` 가 **HUD 만**
	#   `FadeTo(1.0, 0) → Delay(T_el) → FadeTo(1.0, 255)` 로 지운다(몸통 tag 1 은 제외).
	var hb = atk.get("barh")
	if hb is CanvasItem and is_instance_valid(hb):
		var hbn := hb as CanvasItem
		var hd: Vector2 = (hbn as Node2D).position - home
		var ht := (hbn as Node2D).create_tween()
		ht.tween_interval(UltimateFx.LEAD)
		ht.tween_property(hbn, "position", stage + hd, ULT_JUMP_SEC)
		ht.tween_interval(total - UltimateFx.LEAD - ULT_JUMP_SEC * 2.0)
		ht.tween_property(hbn, "position", home + hd, ULT_JUMP_SEC)
		var back := float(ULT_ACTOR_BACK.get(el, 7.0))
		hbn.modulate.a = 1.0
		var ft := hbn.create_tween()
		ft.tween_interval(UltimateFx.ACT_AT)
		ft.tween_property(hbn, "modulate:a", 0.0, 1.0)
		ft.tween_interval(back)
		ft.tween_property(hbn, "modulate:a", 1.0, 1.0)

	# 팀원 퇴장/복귀 + 죽은 드래곤 Hide — 원작 `initPosition` 그대로.
	_ultimate_hide_others(atk, hold)
	return total


const ULT_HIDE_TAIL := 0.5          # 원작 Delay(T + 0.25 + 0.25)
## 시전자가 **다시 나타나는** 시각 — 각 `action<El>_C` 의 첫 `CCDelayTime`(실측 2026-08-05).
## 속성마다 다르다(땅 5.8 이 가장 빠르고 빛 8.35 가 가장 늦다) = 연출 길이와 짝이 맞는다.
const ULT_ACTOR_BACK := {
	"aqua": 7.75, "chaos": 7.65, "dark": 7.75, "earth": 5.8, "fire": 6.75,
	"holy": 7.5, "light": 8.35, "wind": 6.15, "shadow": 7.75,
}

## 시전자 **팀의 나머지**만 무대에서 비켜 준다 → `hold` 뒤에 돌아온다.
## 🔴 2026-08-05 재작성 — 종전엔 피격자까지 전부 `visible=false` 로 숨겼는데, 원작
##   `initPosition` 은 ① 시전자 팀원 2마리를 `Delay(1.0) → JumpBy(0.25, (±화면반폭, 0), S*150)`
##   으로 **화면 밖으로 점프**시켰다가 `Delay(hold) → JumpTo(0.25, 제자리)` 로 되돌리고
##   ② **죽은 드래곤의 시체**(전 슬롯)를 `Hide → Delay(hold+0.5) → Show` 할 뿐이다.
##   피격자는 그대로 서서 저글링당한다(영상 실측 — 불기둥 속에서 튕기는 게 보인다).
func _ultimate_hide_others(atk: Dictionary, hold: float) -> void:
	var s := DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO
	var mine := bool(atk.get("mine", false))
	var vis := _vis()
	var gen := _gen
	for k in _views.keys():
		var v: Dictionary = _views[k]
		if v == atk:
			continue
		var node = v.get("node")
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		if bool(v.get("dead", false)):
			# 시체 — Hide → Delay(hold+0.5) → Show. (이미 안 보이면 그대로다.)
			for key in ["node", "barh"]:
				var o = v.get(key)
				if o is CanvasItem and is_instance_valid(o) and (o as CanvasItem).visible:
					(o as CanvasItem).visible = false
					get_tree().create_timer(UltimateFx.LEAD + hold + 0.5).timeout.connect(
						func() -> void:
							if is_instance_valid(self) and gen == _gen \
									and is_instance_valid(o):
								(o as CanvasItem).visible = true)
			continue
		if bool(v.get("mine", false)) != mine:
			continue                        # 상대 진영은 건드리지 않는다
		# 팀원 — 자기 진영 가장자리 밖으로 점프해 퇴장.
		var nd := node as Node2D
		var home: Vector2 = v.get("home", nd.position)
		var off := home + Vector2((-vis.x * 0.5) if mine else (vis.x * 0.5), 0.0)
		for pair in [["node", nd], ["barh", v.get("barh")]]:
			var o2 = pair[1]
			if not (o2 is Node2D) or not is_instance_valid(o2):
				continue
			var n2 := o2 as Node2D
			var p0: Vector2 = n2.position
			var d := off - home
			var t := n2.create_tween()
			t.tween_interval(UltimateFx.LEAD)
			_tween_jump(t, n2, p0, p0 + d, ULT_JUMP_H * s, ULT_JUMP_SEC, 1.0)
			t.tween_interval(hold)
			_tween_jump(t, n2, p0 + d, p0, ULT_JUMP_H * s, ULT_JUMP_SEC, 1.0)


func _awaken_fx(atk: Dictionary, at: Vector2) -> void:
	var gen := _gen
	_ultimate_position(atk)
	# 원작은 **시전자** 기준으로 무대를 짠다 — 링은 시전자 발밑, 좌표는 시전 방향(dir)으로 편다.
	# 종전엔 `at`(피격자 위치)만 넘겨서 링이 맞는 편에 깔리지 않았다.
	# ⚠️ 링은 **무대 자리**(위 `_ultimate_position` 이 옮긴 곳) 발밑에 깔아야 한다 —
	#   슬롯 좌표로 깔면 시전자가 뛰어간 자리와 어긋난다.
	var caster: Vector2 = _body_pos(atk) if not atk.is_empty() else at
	if not atk.is_empty():
		# `_ultimate_position` 이 옮긴 **절대 무대 자리**를 그대로 쓴다. 슬롯 기준 상대이동으로
		# 계산하면(종전) 3v3 뒷줄에서 링이 시전자와 다른 곳에 깔린다.
		var vis := _vis()
		caster = Vector2(ULT_DX if bool(atk.get("mine", false)) else vis.x - ULT_DX,
			vis.y * 0.5 + ULT_DROP) - Vector2(0.0, float(atk.get("dragon_h", DRAGON_H)) * 0.5)
	# 🔴 2026-08-05 재확정 — 기준점·방향은 `UltimateFx.base_at()` 이 원작 `initWithDragon` 의
	#   race 스위치대로 계산한다(earth/fire/shadow/aqua = **시전자 반대편**, 나머지 = 중앙 계열).
	#   여기서는 시전자 진영(`mine`)만 넘긴다. 바닥 링만 시전자 발밑(`ring_at`)이다.
	UltimateFx.play(self, {
		"element": String(atk.get("element", "")),
		"mine": bool(atk.get("mine", false)),
		"ring_at": caster,
		# 원작 `this+0x22c` = 시전자 레이어 스케일(3v3 = 0.75, 1v1 = 1.0).
		"scale": DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO,
		"speed": _speed,
		"mat": _pma,
		"alive": func() -> bool: return is_instance_valid(self) and gen == _gen,
	})
	_ultimate_hitstop(String(atk.get("element", "")))


# ---------- 각성기 히트스톱 — 원작 `MakeInterface::setScheduleWithTimeScale` @0108a1f4 ----------
#
# 🔵 2026-08-05 백로그 해소. 종전엔 "전역 시간 배율이라 우리 구조와 안 맞는다"고 미뤘는데,
#    함수를 읽어 보니 **원작도 전역**(`CCDirector::getScheduler()->timeScale`)이다.
#    가정이 틀렸을 뿐 이식 못 할 이유가 없었다.
#
#    ```
#    if (scheduler->timeScale > 1.0 && FightManager::getFightTimeScale() == 1.0) return;
#    if (parent has child tag −9 or −10) return;
#    if (FightManager::getFightTimeScale() == 1.35) scheduler->timeScale = param;
#    ```
#    ⇒ **배속이 x1 일 때만** 걸린다. 콜로세움의 fightTimeScale 은 `FightScene` 이 1.35 로 깔고
#      배속 버튼이 1.35 / 2.7 / 5.4 로 올린다(`ColosseumTextBox`) = 우리 `SPEEDS` [1,2,3] 과 1:1.
#      그래서 x2·x3 에서는 원작도 히트스톱이 없다.
#
#    실측 창(값 0.2 → 되돌림 1.35). 시각은 각성기 시작 기준 게임초:
#      aqua   `runAqua`        5.0+0.15+0.12 = 5.27 부터 0.15
#      dark   `actionDark_C`   1.0+6.9       = 7.90 부터 0.04
#      shadow `actionShadow_C` 1.0+6.9       = 7.90 부터 0.04
#      earth  `runEarth`       3.00 부터 0.05 · `actionEarth_C` 3.60·4.55 부터 각 0.1
#    나머지 5속성은 원작에도 호출이 없다(전 클래스 grep 5건이 전부).
const ULT_SLOW := 0.2 / 1.35            # 되돌림 값 대비 = 0.148배
const ULT_HITSTOP := {
	"aqua":   [[5.27, 0.15]],
	"dark":   [[7.90, 0.04]],
	"shadow": [[7.90, 0.04]],
	"earth":  [[3.00, 0.05], [3.60, 0.10], [4.55, 0.10]],
}

func _ultimate_hitstop(element: String) -> void:
	if _speed != 1:
		return                                   # 원작도 x1 에서만 건다
	var wins: Array = ULT_HITSTOP.get(element, [])
	if wins.is_empty():
		return
	var gen := _gen
	for w: Array in wins:
		var onset := float(w[0])
		var span := float(w[1]) / ULT_SLOW       # 느려진 동안의 **실제** 길이
		get_tree().create_timer(onset).timeout.connect(func() -> void:
			if not is_instance_valid(self) or gen != _gen:
				return
			Engine.time_scale = ULT_SLOW
			# 되돌리는 타이머는 배율을 무시해야 한다 — 아니면 자기가 느려져 못 깨어난다.
			get_tree().create_timer(span, true, false, true).timeout.connect(func() -> void:
				Engine.time_scale = 1.0))


func _exit_tree() -> void:
	Engine.time_scale = 1.0                      # 히트스톱 중에 씬을 떠나도 배율은 되돌린다


# ---------- 드래곤 컷인 — 원작 `Cutin::show` @Cutin.c:450 ----------
#
# 🔴 2026-08-05(사용자 지적 "각성기/크리티컬에 드래곤 에셋 컷인이 안 나온다") — **자산을 찾았다.**
#   종전엔 "원작 컷인은 이벤트 드래곤 9013/9014 전용"이라고 결론지었는데, 그건
#   `MakeInterface::showCutIn`(콜로세움) **한 경로만** 본 것이었다.
#   `Dragon::getImagePathCutIn` @Dragon.c:8879 은 종마다 그림을 만든다:
#       미각성 `dragon/dragon_%d_critical/cut_in.png` · 각성 `…/e_cut_in.png`
#       (폴백 `dragon/dragon_9998_critical/cut_in.png` — §미다운로드 자리표시자라 안 쓴다)
#   배경은 `Dragon::getImagePathCutBg` @0125e144 가 **속성 letter** 로 고른다:
#       `dragon/cut_in_<e|a|f|w|l|d|h|c|s>/bg_cut{1,2,3}.png`
#   ⇒ 변환본 실측: `assets/converted/critical_*` **388종**에 `cut_in`/`e_cut_in`,
#     `assets/converted/cut_in_*` 9종에 `bg_cut1~3`. **전부 보유하고 있었다.**
#
# 원작 호출부 두 갈래:
#   · 탐험 `BattleDragon::setAnimatedAttackC(int)` @00d1d9b4 — `param_1 == 4 || param_1 == 7`
#     이면 `Cutin::show(0, **2.0**(0x40000000), cutIn, cutBg, voice, 0)` ⇒ **모든 드래곤**이 낸다.
#   · 콜로세움 `MakeInterface::showCutIn` @01086348 — `getNo()==0x2335||0x2336` 일 때만.
#   🟦 사용자 확정 2026-08-05: 콜로세움에서도 **탐험과 같이** 낸다(크리티컬·각성기).
#
# `Cutin::show` 안무(리터럴):
#   가림막  Delay(d) → FadeTo(t, **150**) → Delay(dur×0.4) → FadeTo(t, 0) → 제거
#   배경띠  `bg_cut1→2→3` 을 `CCRepeatForever` 로 돌리고,
#           Delay(d) → Spawn(EaseOut(ScaleTo(t, s, s×**1.05**), rate **0.25**),
#                            Seq(Delay(dur×0.5), FadeTo(t2, **100**), Spawn(FadeTo(t,0), MoveBy)))
#   초상    Delay(d) → Delay(t2) → Spawn(FadeTo(t, **255**), MoveTo(t, …))
# # ASSUMPTION: 세부 시간 `t`/`t2` 와 이동 벡터는 Ghidra 가 float 레지스터로 흘려 못 읽었다 —
#   `dur`(2.0)에서 나눈 비율로 둔다. 값을 확보하면 아래 상수만 갈아 끼우면 된다.
## 컷인 상수는 전부 `DragonCutin`(scripts/ui/cutin.gd)이 들고 있다 — 위 주석의 원작 리터럴은
## 그 파일에 같은 값으로 있다. 여기서 다시 정의하지 않는다.

func _cutin(atk: Dictionary) -> void:
	# 🔴 2026-08-05(사용자 지적 "컷인이 작아서 화면 일부에만 뜬다") — 여기서 따로 그리지
	#   않는다. 탐험(`battle.gd::_critical_cutin`)이 쓰는 **같은 이식본** `DragonCutin` 을
	#   부른다. 그쪽이 원작 `Cutin::show` 의 전체화면 밴드(`vis.x / 576` 배율)·막·보이스
	#   타이밍까지 갖춘 본체다 — 화면마다 컷인을 따로 두면 또 갈라진다(§3 "같은 일을 하는
	#   헬퍼가 이미 있는지 grep").
	# `caster` 규약 = {id, element, awakened} — 우리 view dict 가 그대로 들고 있다.
	DragonCutin.show(self, atk, _speed)

func _man(dir: String) -> Dictionary:
	if _mans.has(dir):
		return _mans[dir]
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text()) if f else {}
	_mans[dir] = d
	return d


## 피해/회복 수치 — 원작 `MakeInterface::showDamage` @010910ac 이식.
##   폰트: 피해 = `font/font_total.fnt` · 회복 = `font/font_heal.fnt`(둘 다 보유)
##   위치: 대상 기준 (0, 235) 위
##   연출: Delay → Show → **ScaleTo(0, 1.75) → ScaleTo(0.25, 1.0)** → Delay(0.5) → 사라짐
##   ⇒ 종전의 "위로 떠오르며 페이드"는 자작이었다. 원작은 **크게 떴다가 제 크기로 줄어드는** 팝이다.
const DMG_LIFT := 235.0 * 0.5       # 원작 (0,235) — 우리 드래곤 크기(170) 기준으로 절반만
const DMG_POP_BIG := 1.75           # 원작 ScaleTo(0, 1.75)
const DMG_POP_SEC := 0.25           # 원작 ScaleTo(0.25, 1.0)
const DMG_HOLD := 0.5               # 원작 DelayTime(0.5)

func _float_text(pos: Vector2, text: String, col: Color, heal := false) -> void:
	var l := Label.new()
	l.text = text
	l.size = Vector2(140.0, 40.0)
	l.pivot_offset = l.size * 0.5
	l.position = pos + Vector2(-70.0, -DMG_LIFT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bm_style(l, 30, col, "font_heal" if heal else "font_total")
	l.scale = Vector2.ONE * DMG_POP_BIG
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, DMG_POP_SEC)
	tw.tween_interval(DMG_HOLD)
	tw.tween_property(l, "modulate:a", 0.0, 0.2)
	tw.tween_callback(l.queue_free)


# ---------- 결과 ----------
#
# 원작 `MakeInterface::loadWinUI` @010ac410 / `loadLoseUI` — 2026-08-05 재채굴(사용자 지적
# "승리 연출이 텍스트뿐이고 드래곤 모션·화면 처리가 불완전하다"). 새로 밝혀진 것:
#
#   ① **결과는 곧바로 안 뜬다.** `createGameEndPopup` 이 내용물마다
#      `CCDelayTime(4.95) → CCShow` 를 걸어 둔다 ⇒ 전장이 한 박자 그대로 보인다.
#   ② `scene/colosseum/result_popup1.png` 를 **setScale(0.9)**(0x3f666666) 로 화면 바닥에
#      깔고(z=1) 그 위에 `popup_win_%s` / `popup_win_bg_%s` 를 얹는다. **셋 다 보유.**
#   ③ 연승 표시 = `scene/colosseum/icon_fist%d.png` + BMFont(subtitle) `"X%d"`
#      (`FightManager::getUserWinningStreak`). ⇒ 전투 화면 우상단의 정체불명 `X14`/`X7`
#      뱃지가 **이것**이었다(종전 미해결 메모 해소).
#   ④ 승패 문구 스파인 = `scene/colosseum/colosseum_win_and_lose_spine`
#      (애니 `colosseum_win_spine` / `colosseum_lose_spine`, SSO 바이트 복원).
#      🟠 **우리 덤프에 없다** — `DV2/480/scene/colosseum/` 에 있는 스파인은 colo_waiting ·
#      fight · lightning 셋뿐이다. 같은 함수가 부르는 `colosseum_9patch/popup_eff_lose2.png` ·
#      `popup_lose_%s2.png` 도 없다(후기 UI 세트). ⇒ 보유 프레임(`popup_win_kr` 계열)로 낸다.
#
# ⚠️ **드래곤 승리 모션은 원작에 없다.** MakeInterface 전체에서 스파인 애니 리터럴은
#    `wait`(7회) · `down`(3회) · `damaged`(3회) **뿐**이고 `love` 는 한 번도 안 나온다
#    (SSO 0x65766f6c08 검색 → MakeInterface·FightScene 0건, 동굴·상태창 등 다른 화면만).
#    ⇒ 이긴 드래곤은 `wait` 로 돌아가고, 진 드래곤은 `down` 으로 쓰러져 있는 것이 원작 화면이다.
#    없는 모션을 지어내지 않는다(§2-6).
## 🟦 2026-08-05 사용자 확정 — 원작 값은 **4.95**(`createGameEndPopup` 의 CCDelayTime)인데
##   기다림이 너무 길다는 지적으로 **1초**로 줄인다. 원작 상수는 아래 주석에 보존.
const RESULT_DELAY := 1.0           # 원작 createGameEndPopup 의 CCDelayTime(4.95)
const RESULT_PANEL_SCALE := 0.9     # 원작 result_popup1 setScale(0x3f666666)

func _finish() -> void:
	var win := _winner == "ally"
	# 로직에 결과를 넘긴다 — 레이팅·연승·연승방지 갱신은 전부 Colosseum 이 한다.
	var r := Colosseum.apply_result(_mode, win, String(_foe.get("nick", "")), _foe)

	# ① 살아남은 드래곤은 대기 자세로 돌아간다(원작이 쓰는 유일한 종료 애니).
	for k in _views.keys():
		var v: Dictionary = _views[k]
		if not bool(v.get("dead", false)) and _has_anim(v, "wait"):
			_play_anim(v, "wait")
	# 전장을 한 박자 보여 준 뒤 결과를 띄운다(원작 4.95초).
	await _wait(RESULT_DELAY)
	if not is_instance_valid(self):
		return

	var vis := _vis()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = vis
	add_child(dim)

	# ② ⚪ 원작 `result_popup1`(setScale 0.9)은 **안 깐다.**
	#   원작 좌표가 `VisibleRect::bottom() − (0, h×0.5)` = 판 중심이 화면 바닥보다 h/2 아래,
	#   즉 **완전히 화면 밖**이다(그래서 `setVisible(false)` + `Delay(4.95) → Show` 와 짝이다).
	#   올라오는 목적지를 주는 코드를 아직 못 짚어서, 임의 위치에 놓으면 전장을 통째로 가린다
	#   (2026-08-05 캡처에서 확인). 근거를 찾으면 여기만 되살리면 된다.

	# 원작 승패 아트 — popup_win_kr / popup_lose_kr (+ _bg). 전부 보유.
	var bgk := "scene_colosseum_popup_win_bg_kr" if win else "scene_colosseum_popup_lose_bg_kr"
	var fgk := "scene_colosseum_popup_win_kr" if win else "scene_colosseum_popup_lose_kr"
	var b := _spr(CO, bgk, Design.ASSET_SCALE)
	if b != null:
		b.position = Vector2(vis.x * 0.5, vis.y * 0.42)
		add_child(b)
	var f := _spr(CO, fgk, Design.ASSET_SCALE)
	if f != null:
		f.position = Vector2(vis.x * 0.5, vis.y * 0.42)
		add_child(f)

	# ③ 연승 — 원작 `icon_fist%d` + BMFont "X%d".
	var streak := int(r.get("streak", 0))
	if streak > 0:
		var fist := _spr(CO, "scene_colosseum_icon_fist%d" % (2 if _mode == "team" else 1),
			Design.ASSET_SCALE)
		if fist != null:
			fist.position = Vector2(vis.x * 0.5 - 40.0, vis.y * 0.42 + 165.0)
			add_child(fist)
		var sl := Label.new()
		sl.text = "X%d" % streak
		sl.size = Vector2(120.0, 34.0)
		sl.position = Vector2(vis.x * 0.5 + 2.0, vis.y * 0.42 + 149.0)
		_bm_style(sl, 26, Color.WHITE)
		add_child(sl)

	var info := Label.new()
	var d := int(r.get("delta", 0))
	# 연승은 위 ③(원작 `icon_fist` + "X%d")이 낸다 — 여기서 또 적지 않는다.
	info.text = "%s%d점  →  %d점 (%s)" % [
		"+" if d >= 0 else "", d, int(r.get("rating_after", 0)),
		String((r.get("tier_after", {}) as Dictionary).get("name", ""))]
	info.size = Vector2(vis.x, 60.0)
	info.position = Vector2(0.0, vis.y * 0.42 + 90.0)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 24)
	add_child(info)

	# 원작 `ColosseumTierupPopup` — 승급/강등이 있으면 결과 위에 띄운다.
	if bool(r.get("tier_up", false)) or bool(r.get("tier_down", false)):
		ColosseumTierupPopup.open(self, r)

	AtlasUI.frame_button(self, "확인", Vector2(vis.x * 0.5 - 90.0, vis.y - 130.0),
		Vector2(180.0, 48.0), func() -> void:
			Scenes.goto("colosseum", {"from": "fight"}))


# ---------- 헬퍼 ----------

## 원작 `FightManager::getFightTimeScale()` — 배속 버튼이 정하는 재생 속도로 대기를 줄인다.
func _wait(sec: float) -> void:
	await get_tree().create_timer(maxf(0.01, sec / float(maxi(1, _speed)))).timeout

func _vis() -> Vector2:
	return get_viewport_rect().size

func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var j = JSON.parse_string(f.get_as_text())
	return j if typeof(j) == TYPE_DICTIONARY else {}

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
	return _nine9(key, sz_pt, cap, NP)

func _nine9(key: String, sz_pt: Vector2, cap: Rect2, dir: String) -> NinePatchRect:
	var tex := _tex(dir, key)
	if tex == null:
		return null
	var inv := 1.0 / Design.ASSET_SCALE
	var l := cap.position.x * inv
	var t := cap.position.y * inv
	var cw := cap.size.x * inv
	var ch := cap.size.y * inv
	var np := NinePatchRect.new()
	np.texture = tex
	np.patch_margin_left = int(round(l))
	np.patch_margin_top = int(round(t))
	np.patch_margin_right = int(round(maxf(0.0, tex.get_width() - l - cw)))
	np.patch_margin_bottom = int(round(maxf(0.0, tex.get_height() - t - ch)))
	np.size = sz_pt
	np.material = _pma
	return np


# ---------- 드래곤 터치 → 상태창 (원작 `FightScene::ccTouchesBegan` @00f8f02c) ----------
#
# 원작이 하는 일:
#   ① 태그 −9 / −10 자식(= 결과 팝업류)이 떠 있으면 **무시**한다.
#   ② 드래곤 슬롯 태그 10~15 를 훑으며 각 드래곤 레이어의 사각형
#      `CCRect(x − w×0.5×0.75, y − h×0.5×0.75, w×0.75, h×0.75)` 에 터치가 들었는지 본다
#      ⇒ **경계상자의 75%** 만 유효 타격 범위다.
#   ③ 들었으면 `FightManager::getDragonIndexFromDirection(tag)` 로 인덱스를 얻어
#      `MakeInterface::showDragonInfo(fightDragon)` @010b22bc,
#      아무 데도 안 들었으면 `MakeInterface::removeDragonInfo` @010b2664.
#
# 우리 대응: 같은 75% 규칙으로 히트테스트하고 `StatusLayer.open_panel` 을 띄운다.
# 패널 본체는 **원작과 같은 클래스**(`CharacterInfoPopup`)를 우리가 이미 이식해 둔 것을 쓴다
# (상태창 우측 패널과 같은 코드 — §3 "같은 일을 하는 헬퍼가 이미 있는지 grep").
const TOUCH_BOX := 0.75             # 원작 boundingBox × 0.75

var _info_panel: StatusLayer = null

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	# ① 이미 패널이 떠 있으면 그쪽이 입력을 먹는다(원작도 팝업이 있으면 히트테스트를 건너뛴다).
	if _info_panel != null and is_instance_valid(_info_panel):
		return
	var hit := _dragon_at(mb.position)
	if hit.is_empty():
		return
	var rec: Dictionary = hit.get("rec", {})
	if rec.is_empty():
		return
	accept_event()
	# 내 팀은 왼쪽에 서므로 패널도 왼쪽에 — 원작도 터치한 쪽에 낸다.
	_info_panel = StatusLayer.open_panel(self, rec, bool(hit.get("mine", false)))


## 그 지점에 있는 전투원(없으면 {}). 원작과 같은 **경계상자 75%** 규칙.
func _dragon_at(p: Vector2) -> Dictionary:
	for tag in _views:
		var v: Dictionary = _views[tag]
		if bool(v.get("dead", false)):
			continue
		var n = v.get("node")
		if not (n is Node2D) or not is_instance_valid(n):
			continue
		var pos: Vector2 = (n as Node2D).position
		var w := float(v.get("dragon_w", DRAGON_H)) * TOUCH_BOX
		var h := float(v.get("dragon_h", DRAGON_H)) * TOUCH_BOX
		var s := DRAGON_SCALE_TEAM if _mode == "team" else DRAGON_SCALE_SOLO
		w *= s
		h *= s
		# 우리 노드 원점은 **발밑 중앙**이라 상자는 그 위로 올라간다.
		if Rect2(pos - Vector2(w * 0.5, h), Vector2(w, h)).has_point(p):
			return v
	return {}
