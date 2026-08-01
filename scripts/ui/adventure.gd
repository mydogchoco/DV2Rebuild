extends Control
## Adventure(던전 탐험) 씬 — worldmap↔battle 사이 "탐험" 단계. render 층(§10).
## 원작 AdventureScene::setAdventureWalk 기반: 진행바(scene/adventure/bar.png) 위를 파티가 자동보행하며
## 조우 지점에서 전투. 최소 구현: 탐험 진행바 채움 → boss 조우 → battle. (다중 조우·회복샘·보상=후속 TODO)
## 좌표: 692 고정높이. 전환은 Scenes.goto()만.

const FLOOR := 692.0

var _pma: CanvasItemMaterial
var _adv: Dictionary = {}
var _params: Dictionary = {}
var _stage: Dictionary = {}
var _speed := 1.0
var _t := 0.0
var _dur := 1.8                  # 조우까지 배회할 시간(초). 한 배회 사이클 = 7×0.3 = 2.1s
var _done := false
var _healed := false
var _event_open := false         # 이벤트(회복샘·보물·갈림길·상점·카드·레벨업) 진행 중 = 보행 정지
# 원작 탐험 보행은 아바타 없이 1인칭 — 배경 사본이 확대·이동하며 전진한다(setAdventureWalk).
var _cam: Camera2D               # setAllViewShake(Shake 액션) 전용 카메라
var _walking := false
var _speed_btn: Button

func enter(params: Dictionary = {}) -> void:
	_params = params
	if _pma != null:
		_rebuild()

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_adv = _man("adventure_ui")
	# ⚠️ `_rebuild()` 가 레벨업 큐를 소비(`_params.erase("levelups")`)하므로 **먼저** 기억해 둔다.
	var had_levelups := _params.has("levelups")
	_rebuild()
	# 원작 BattleTextBox: 스테이지 진입 스토리 대사. 대사 텍스트=유실(서버/시나리오 데이터) → stages.json "intro"
	# (사용자 작성)가 있을 때만 첫 진입에 표시. 없으면 미표시(지어내지 않음, 원칙2).
	# ⚠️ 레벨업 결과창·3인 편성창이 대기 중이면 인트로 대사를 띄우지 않는다 — 대사 레이어(80)의
	#   전면 탭 캐처가 그 창들(30/31) 위를 덮어 **버튼이 안 눌리게 된다**(2026-08-01 실측 2건).
	var party_pending := _party_capacity() == 3 and not bool(_params.get("party_ready", false))
	if int(_params.get("enc", 0)) == 0 and not had_levelups and not party_pending:
		var intro := String(_stage.get("intro", ""))
		if intro != "":
			_open_dialogue(intro)

## 던전 탐험(비전투) BGM: stages.json "bgm"(명시 override) → **bg_<필드id>** → 지역 bgm → yutakan 폴백.
## 원작 음원 `music/bg_<n>.mp3` 는 배경 `scene/adventure/bg/<n>/bg.jpg` 와 **같은 번호 체계**다
## (n = 필드 id, 1=희망의 숲…). 보유 원본은 bg_1~12·15~19·22·24·25 — 13/14/20/21/23 은 음원이
## 추출 덤프에 없어 지역 폴백으로 떨어진다(CLAUDE.md §10 판본 불일치).
## 사용자 지정분: 13·14=bg_12 / 21=bg_24 / 23=bg_22 (stages.json 의 "bgm"). 20 광물산맥만 미지정.
func _explore_bgm() -> String:
	var b := String(_stage.get("bgm", ""))
	if b != "": return b
	var fid := DungeonBG.field_id(_stage)
	if fid > 0 and ResourceLoader.exists("res://assets/music/bg_%d.mp3" % fid):
		return "bg_%d" % fid
	# 변형 필드(밤 501+ / 카데스 601+)는 전용 음원이 없다(원본 music/ 에 bg_5xx·bg_6xx 부재)
	# → 기본 필드의 곡을 그대로 쓴다.
	var bfid := DungeonBG.base_field(fid)
	if bfid != fid and bfid > 0 and ResourceLoader.exists("res://assets/music/bg_%d.mp3" % bfid):
		return "bg_%d" % bfid
	# 지역은 스테이지 정의가 우선 — params.region 은 "어느 지도에서 눌렀나"라서 비거나 다를 수 있다.
	var region := String(_stage.get("region", ""))
	if region == "":
		region = String(_params.get("region", "yutakan"))
	for r in Data.worldmap_regions():
		if String(r.get("id", "")) == region:
			var rb := String(r.get("bgm", ""))
			if rb != "": return rb
	return "bg_yutakan"


## ── 출전 인원 (원작 구조) ───────────────────────────────────────────────────────
## 원작 일반 탐험은 **파티가 없다** — `AdventureScene::initMainDragon` 이 `Dragon::isSelected`
## 로 고른 **리더 1마리**(동굴에서 선택 중인 드래곤)가 혼자 나선다. 드래곤 추가는 입장 **후**
## `clickAddDragon` → `setAddDragonPopupLayer` 로 한다.
## 3마리가 함께 싸우는 건 **레이드 · 영웅 단계 · 유타칸 밤 · 카데스의 공간 · 혼돈의 틈새** 뿐이다
## (2026-07-27 사용자 확정).
##
## 판정: 영웅 난이도(`hero`) · 랜덤보스 스테이지(혼돈의 틈새 = `random_boss`) · stages.json 의
## `party3: true`(유타칸 밤·카데스의 공간처럼 아직 미이식인 곳을 표시하는 자리) 중 하나면 3마리.
func _party_capacity() -> int:
	if bool(_params.get("hero", false)):
		return 3
	if bool(_stage.get("random_boss", false)) or bool(_stage.get("party3", false)):
		return 3
	return 1

## 이번 탐험에 나가는 uid 목록. 1인 탐험이면 리더만.
var _run_party: Array = []

## 리더 1마리 — 원작 `initMainDragon` 이 `Dragon::isSelected` 로 고르는 그 드래곤.
## **대체하지 않는다**(2026-07-30 수정). 원작 `WorldMapPopupLayer::getDragonStatus` 는 선택 중인
## 드래곤이 기절/허기면 **입장 자체를 취소**하지, 다른 드래곤을 대신 내보내지 않는다 —
## 그 검사는 월드맵 팝업(`worldmap.gd::_selected_block`)이 하고, 여기서는 선택 개체를 그대로 쓴다.
## (종전엔 여기서 멀쩡한 다음 드래곤으로 갈아치워, 유저가 고른 것과 다른 개체가 나갔다.)
## 굶은 개체로 들어온 경우는 `_check_starving_end` 가 즉시 종료시킨다.
func _leader_party() -> Array:
	var uid := UserDB.active_uid()
	if uid > 0 and not UserDB.get_dragon(uid).is_empty():
		return [uid]
	return []

## 3인 단계 편성창 — 입장 후에 뜬다(원작 `clickAddDragon` → `setAddDragonPopupLayer`).
var _pending_levelup_after_party := false
func _open_party_select() -> void:
	_event_open = true                     # 편성 중 보행 정지
	# 안내는 우리 텍스트박스로(원작 <AdventureAddDragonHardDungeon> — 편성창 자체 박스와
	# 겹치면 글이 뒤섞인다 → show_msg=false).
	_narrate("추가로 전투에 참가할 드래곤을 최대 3마리 선택할 수 있습니다.")
	PartySelect.open_run(self, _run_party, func(picked: Array):
		_run_party = picked
		_params["party_ready"] = true
		_event_open = false
		# 편성 → 레벨업창 → 이벤트 큐 순으로 **하나씩** 흘린다.
		# (셋을 동시에 띄우면 CanvasLayer 가 겹친다 — 이벤트 큐를 도입한 이유와 같은 문제다.)
		if _pending_levelup_after_party:
			_pending_levelup_after_party = false
			if _open_levelup_result():
				return
		_advance_step(),
		false)   # show_msg=false — 안내는 위 _narrate 가 담당

var _rboss_enc := -1   # 랜덤 보스 스테이지: 이번 진입에 선택된 보스 인덱스(-1=일반)
## 소환형(혼돈의 틈새)에서 **월드맵 소환 때 확정된** 보스 인덱스. -1=소환형 아님/미소환.
## 이벤트 큐나 재추첨이 이걸 덮지 못하게 마지막에 다시 박는다.
var _dk_pin := -1
func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_done = false; _t = 0.0
	_done_battle_ready = false        # 조우 전 선택지는 조우당 1번(씬 재빌드마다 초기화)
	_ready_layer = null
	# 유타칸 밤(+500)·카데스(+600)는 원작에서 **별도 필드 레코드**였다(Field.c setInfo) —
	# `stages.json` 의 night/kades 블록을 덮어 재현한다(Field.apply_variant, logic).
	# 🔴 2026-07-31 이전에는 이 해석이 없어 밤에도 낮 몬스터가 나왔다.
	_stage = Field.apply_variant(Data.stage(String(_params.get("stage", ""))),
		Drops.mode_of(bool(_params.get("hero", false)),
			bool(_params.get("night", false)), bool(_params.get("kades", false))))
	if _stage.get("bg") != null and not _params.has("bg"):
		_params["bg"] = int(_stage["bg"])
	# 원작: 비전투 탐험 = 던전 고유 BGM(Field.getSoundPath, setIsBasicBg=true). 전투 진입 시 battle이 bg_colosseum_battle_2로 전환.
	# 던전별 값은 서버데이터 유실 → stages.json "bgm"(사용자 매핑), 없으면 bg_<필드id>, 그다음 지역 폴백. 근거: AdventureScene.c:48371.
	# ⚠️ 반드시 `_stage` 를 채운 **뒤에** 부를 것 — 먼저 부르면 _stage가 비어 있어 필드 BGM이
	#    영영 선택되지 않고 지역 BGM만 나온다(2026-07-27 수정한 실제 버그).
	Bgm.play(_explore_bgm())
	# 랜덤 보스 스테이지(혼돈의 틈새 등): 보스 목록서 랜덤 1마리 선택 → 단발 보스전.
	# 유타칸 밤(501~514)도 같은 구조다 — 위키 "밤에는 … 한번밖에 탐험할 수 없으며 보통은
	# 처음부터 보스를 마주하지만 … 다른 몬스터가 나올 수도 있다". 편성의 `weight` 로
	# 그 '보통/가끔' 을 표현한다(없으면 1 = 균등, 종전 동작 그대로).
	_rboss_enc = -1
	if bool(_stage.get("random_boss", false)):
		var bosses: Array = _stage.get("enemies", [])
		if not bosses.is_empty():
			var rr := RandomNumberGenerator.new(); rr.randomize()
			_rboss_enc = _pick_weighted(bosses, rr)
	# 🔒 소환형(혼돈의 틈새) — **여기서 다시 뽑지 않는다.** 어느 보스인지는 월드맵에서
	# 소환할 때 이미 정해졌고(원작 `getDarkNixStatus`, 서버가 소환 시점에 확정) 그 개체가
	# 월드맵 스파인으로 상주 중이다. 매 진입 재추첨하면 화면의 보스와 실제로 싸우는 보스가
	# 달라진다. 원작 `AdventureScene` 도 서버가 내려준 몬스터를 그대로 받는다(pop_darknix.hb).
	_dk_pin = -1
	if Darknix.is_summon_stage(_stage):
		_dk_pin = Darknix.enemy_index(_stage["summon"], UserDB.darknix(),
			int(Time.get_unix_time_from_system()))
		if _dk_pin >= 0:
			_rboss_enc = _dk_pin
	_build_bg()
	_build_walk()
	_build_topinfo()
	_build_narration()   # 원작 BattleTextBox: 탐험 서사가 흐르는 하단 전폭 텍스트박스
	# 🟠 2026-07-30: 여기서 회복샘·보물·갈림길·상점·카드게임을 **각자 독립 확률로 동시에** 굴리던
	#   자리다. 원작은 이벤트 큐의 **순차 스텝**이라(포팅 카드 AdventureEventFlow.md §1) 큐 생성은
	#   AdventureRun(logic)에 넘기고, 여기서는 배열만 받아 둔다. 재생은 `_advance_step` 이 하나씩.
	_steps = AdventureRun.build_steps(_stage, Data.adventure_events,
		int(_params.get("enc", 0)),
		{
			"hurt": not (_params.get("hp_state", {}) as Dictionary).is_empty(),
			"fortress": _is_fortress(),
			"random_boss": _rboss_enc >= 0,
			"night": _is_night(),
			# 소환형은 밤과 같은 단일 조우(100% 보스). 사전 이벤트도 '아무것도 못 찾음'도 없다.
			"single_boss": _dk_pin >= 0,
		},
		_step_rng())
	_step_i = 0
	# 밤은 큐가 **조우 대상까지** 정한다(2:3:5 로 아무것도/공용몹/지역보스). 그 선택을
	# 기존 '강제 조우 인덱스' 통로(`_rboss_enc`)에 실어 아래 연출·전투가 그대로 따라오게 한다.
	for s in _steps:
		if String((s as Dictionary).get("type", "")) == AdventureRun.MONSTER \
				and (s as Dictionary).has("enemy_index"):
			_rboss_enc = int((s as Dictionary)["enemy_index"])
	# 🔴 2026-07-31 (사용자 지적: "나갔다 다시 들어가면 소환한 보스가 아닌 다른 보스가 나온다").
	#   소환형은 **큐가 정하게 두면 안 된다** — 어느 보스인지는 월드맵에서 소환할 때 이미
	#   확정됐고 그 개체가 스파인으로 상주 중이다. 위 큐 루프가 핀을 덮어쓰고 있었다.
	#   (그 위 `random_boss` 재추첨도 같은 이유로 무효화된다.)
	if _dk_pin >= 0:
		_rboss_enc = _dk_pin
	_build_hud()
	_maybe_dungeon_tutorial()   # 원작 DungeonTutorialLayer: 최초 던전 진입 시 튜토리얼
	# 출전 인원 확정 — 원작은 **입장 후**에 편성한다(월드맵 팝업에는 편성 단계가 없다).
	#   1인 탐험: 리더(동굴 선택 드래곤) 그대로 시작.
	#   3인 단계: 편성창을 띄우고, 확정 전까지 보행을 멈춘다.
	_run_party = _leader_party()
	# 허기(FOOD) 소진 게이트 — 전투마다 줄고, 이 씬은 전투가 끝날 때마다 다시 지어지므로
	# (`battle.gd` → `Scenes.goto("adventure")`) 여기가 매 조우 뒤 통과하는 지점이다.
	# 🟠 2026-08-01 정정(사용자 지적): 종전엔 **무조건 쫓아냈는데**, 원작은 가방에 먹을 수 있는
	#   먹이가 있으면 **먹이기 확인 팝업**을 띄우고 탐험을 잇는다 —
	#   `AdventureScene::checkNightHungry` → `WorldMapScene::setDragonFoodWithSelectedDragon`
	#   (`<CaveDragonFoodMsg_Ad_1/2>` "…배고픔이 상당히/약간 채워집니다", 탐험 중에만 쓰는
	#   드래곤 이름 판). 없을 때만 `<CaveDragonFoodMsg_Ad_3>` "…상점으로 이동하시겠습니까?".
	#   골드로 사 먹이는 `AdventureFoodByGold` 경로는 비용이 서버 유실이라 이식하지 않는다.
	if _check_starving_end():
		return
	_after_food_gate()

## 허기 게이트 통과 후의 진입 연쇄(편성 → 레벨업 → 이벤트 큐). 먹이기 팝업이
## 끼어들면 그 확인 콜백이 이 함수로 되돌아온다.
func _after_food_gate() -> void:
	if _party_capacity() == 3 and not bool(_params.get("party_ready", false)):
		_pending_levelup_after_party = true   # 편성 → 레벨업창 순서로 하나씩(둘 다 배회를 멈춘다)
		_open_party_select()
	elif not _open_levelup_result():
		# 레벨업 결과창이 없을 때만 곧바로 이벤트 큐로. 있으면 그 창의 닫기 콜백이 이어받는다.
		_advance_step()

# ---------- 이벤트 큐 재생 (원작 initEvent → setNextEventChange → setNextEventExe) ----------
#
# 큐 자체는 `AdventureRun`(logic)이 만들고, 여기서는 **하나씩 꺼내 재생**한다.
# 원작은 스텝 사이에 `CCDelayTime(0.3)` + 텍스트박스 대기를 뒀다(`setNextEventExe`/`setEventFunc`)
# → 우리도 `_STEP_DELAY` 만큼 쉬고 다음으로 간다.
var _steps: Array = []      # 이번 조우 구간의 이벤트 열. 마지막은 항상 monster.
var _step_i := 0
const _STEP_DELAY := 0.3    # 원작 setNextEventExe 의 CCDelayTime(0.3)

## 큐 생성용 RNG. 스테이지·조우 인덱스로 시드를 고정해 **씬이 다시 지어져도 같은 큐**가 나오게
## 한다(종전 `_maybe_*` 들도 같은 방식이었다 — 재빌드마다 이벤트가 바뀌면 안 된다).
func _step_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	# `run_seed` 는 **이번 진입** 고유값(월드맵이 넣고 전투가 이월한다). 이게 빠지면
	# 같은 지역·같은 조우번호가 영영 같은 큐를 낸다 — 밤(1회 조우)에서 특히 치명적이다.
	r.seed = hash("advq_%s_%d_%d" % [String(_params.get("stage", "")),
		int(_params.get("enc", 0)), int(_params.get("run_seed", 0))])
	return r

## 다음 스텝으로. 사전 이벤트면 그것을 열고(끝나면 다시 이 함수를 부른다), 몬스터면 배회 시작.
func _advance_step() -> void:
	if _done or not is_inside_tree():
		return
	while _step_i < _steps.size():
		var ev: Dictionary = _steps[_step_i]
		_step_i += 1
		if String(ev.get("type", "")) == AdventureRun.MONSTER:
			_begin_walk()
			return
		if _play_event(ev):
			return                    # 화면을 열었다 — 콜백이 _advance_step 을 다시 부른다
	_begin_walk()                     # 큐가 비었다(있을 수 없지만 방어)

## 사전 이벤트 1개 재생. **화면을 열었으면 true**(그 이벤트의 종료 콜백이 다음 스텝을 부른다).
func _play_event(ev: Dictionary) -> bool:
	match String(ev.get("type", "")):
		AdventureRun.NOTHING:
			# 원작 `setEventNothing`(이벤트 1). 문구도 원작 그대로 —
			# stringsData_KR `<AdventureNothing>`.
			# 밤에서는 이게 **종료 이벤트**다(NightTutorial_talk10 "탐험은 단 한번!").
			_narrate("해가 질 때까지 돌아다녔지만 아무것도 찾지 못했다.")
			if AdventureRun.is_final(ev):
				_end_run_after(2.0)   # 원작 checkAdventureNightEnd 의 CCDelayTime(2.0)
				return true
			return false
		AdventureRun.HEAL_HOLY:
			_show_fountain(true)
			return true
		AdventureRun.HEAL_PLAIN:
			_show_fountain(false)
			return true
		# ⚫ AdventureRun.TREASURE(0x15) 는 **풀에서 뺐다** — data/adventure_events.json
		#   `steps._cut_treasure`. 종착지(seek)가 유실돼 입구만 열어 둘 수 없다. 아래 §CUT 주석 참조.
		AdventureRun.CHOICE:
			_open_choice(_event_rng("choice"))
			return true
		AdventureRun.SHOP:
			_open_shop(_event_rng("shop"))
			return true
		AdventureRun.CARDGAME:
			# 어느 종류인지도 서버가 정했다(0x18/0x19) → 유실. 반반으로 고른다. # ASSUMPTION
			var r := _event_rng("card")
			_open_cardgame("match" if r.randf() < 0.5 else "avoid")
			return true
	return false                      # nothing 등 — 화면 없이 지나간다

## 이벤트 내부 판정용 RNG(보상 굴림 등). 큐 RNG 와 분리해 이벤트별로 고정한다.
func _event_rng(tag: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s_%s_%d" % [tag, String(_params.get("stage", "")), int(_params.get("enc", 0))])
	return r

## 이벤트가 끝났다 → 원작처럼 0.3초 쉬고 다음 스텝.
func _step_done() -> void:
	_event_open = false
	if _done or not is_inside_tree():
		return
	get_tree().create_timer(_STEP_DELAY).timeout.connect(func():
		if is_instance_valid(self):
			_advance_step())

## 유타칸 밤인가. 드랍 풀·필드 레코드·이벤트 큐가 전부 이 플래그를 본다.
func _is_night() -> bool:
	if _params.has("night"):
		return bool(_params.get("night"))
	return String(_stage.get("variant", "")) == "night"

## 원작 `checkAdventureNightEnd` — 텍스트 한 줄을 읽을 시간을 주고 런을 끝낸다
## (원작은 `m_nEventType = 0x1d`(Finish) + `CCDelayTime(2.0)`).
func _end_run_after(secs: float) -> void:
	_done = true
	get_tree().create_timer(secs).timeout.connect(func():
		if is_instance_valid(self):
			Scenes.goto("worldmap", {"region": _params.get("region", "yutakan"),
				"night": _is_night()}))

## 배회 시작 — 사전 이벤트가 전부 끝난 뒤에만 불린다.
func _begin_walk() -> void:
	if _done:
		return
	_walking = true
	# 원작 `setAllHideUiButton` — 전진 애니 동안은 하단 파티 카드를 감춘다
	# (레퍼런스 `docs/ref/adventure/배회1~5.png` 에 카드가 없다). 조우 선택지에서 다시 뜬다.
	_hide_party_cards()
	_start_walk_cycle()

## 출전 인원 중 굶은 드래곤이 있으면 원작대로 **먹이기 팝업**으로 잇는다. 흐름을 가로챘으면 true.
## 원작 = `checkNightHungry` → `setDragonFoodWithSelectedDragon`(문구 `<CaveDragonFoodMsg_Ad_*>`)
## — 월드맵의 `_popup_dragon_food` 와 같은 창의 탐험 판(드래곤 이름이 들어간다).
## 판정·회복량은 전부 `ItemEffect`(logic 층).
func _check_starving_end() -> bool:
	var starved := ItemEffect.starving_uids(Data.item_effects, _run_party,
		func(uid: int): return UserDB.get_dragon(uid))
	if starved.is_empty():
		return false
	_ask_feed_starving(int(starved[0]))
	return true

## 굶은 드래곤 1마리에 대한 먹이기 확인. 확인 → 먹이고 다음 굶은 드래곤(있으면) →
## 전부 해결되면 `_after_food_gate` 로 복귀. 취소/먹이 없음 이탈 → 탐험 종료.
func _ask_feed_starving(uid: int) -> void:
	var d := UserDB.get_dragon(uid)
	var nm := String(d.get("name", "드래곤"))
	var el := String(Data.get_dragon(int(d.get("id", 0))).get("element", ""))
	var key := ItemEffect.find_matching_feed(UserDB.inventory(), Data.items, el)
	var leave := func():
		Scenes.goto("worldmap", {"region": _params.get("region", "yutakan")})
	if key == "":
		# `<CaveDragonFoodMsg_Ad_3>` — 이 드래곤이 먹을 먹이가 가방에 없다.
		PopupType.open(self, "먹이", "%s이(가) 먹을 수 있는 음식이 없습니다.\n\n상점으로 이동하시겠습니까?" % nm,
			func(): Scenes.goto("shop", {"area": "elpis"}),
			"확인", "취소", -1, 0, leave)
		return
	# `<CaveDragonFoodMsg_Ad_1/2>` — 상당히(전량) / 약간(절반)은 먹이 종류가 정한다.
	var much := "상당히" if ItemEffect.feed_is_full(Data.item_effects, key) else "약간"
	PopupType.open(self, "먹이",
		"%s 아이템을 사용하면\n%s의 배고픔이 %s 채워집니다.\n사용하시겠습니까?"
			% [Data.item_name(key), nm, much],
		func():
			# 원작 onClickFood — 1개 소모, 회복량 = ItemEffect.food_after_feed.
			if int(UserDB.inventory().get(key, 0)) > 0:
				UserDB.add_item(key, -1)
				UserDB.set_dragon_field(uid, "food",
					ItemEffect.food_after_feed(Data.item_effects, Data.get_item(key), key, el,
						int(UserDB.get_dragon(uid).get("food", 0))))
				Bgm.sfx("effect_button")
				_narrate("%s이(가) 맛있게 먹이를 먹었습니다." % nm)
			# 아직 굶은 드래곤이 남았으면 반복, 아니면 진입 연쇄로 복귀.
			if not _check_starving_end():
				_after_food_gate(),
		"확인", "취소", -1, 0, leave)

## 직전 전투에서 넘어온 레벨업 결과창. 열려 있는 동안 `_event_open` 으로 배회를 멈춘다
## (사용자 지시 2026-07-27). 원작에는 이 창이 없었고 하단 텍스트박스 한 줄뿐이었다 —
## 근거·판단은 `scripts/ui/levelup_screen.gd` 헤더에 정리해 뒀다.
## **창을 열었으면 true** — 그때는 닫기 콜백이 이벤트 큐를 이어받는다(호출부가 이 값을 본다).
##
## 🔀 2026-07-31: 자작 모달 `LevelUpResult` 를 버리고 **동굴에서 축복 아이템을 쓸 때와
##   완전히 같은 화면**(`LevelUpScreen`)을 쓴다. 사용자 지시 — "축복류 아이템과 똑같은
##   레벨업 팝업을 공유해야 해." 아이템 슬롯·능력치 다시뽑기·AUTO 까지 동일하다.
func _open_levelup_result() -> bool:
	var q: Array = _params.get("levelups", [])
	if q.is_empty():
		return false
	_params.erase("levelups")          # 씬이 재빌드돼도 두 번 뜨지 않게
	_event_open = true
	# 여러 마리가 올랐으면 한 마리씩 차례로. 전부 닫히면 이벤트 큐를 잇는다.
	LevelUpScreen.open_queue(self, q, func():
		_event_open = false
		_advance_step())
	return true

## 원작 DungeonTutorialLayer: 최초 던전 진입 시 튜토리얼 이미지 페이지(dungeon_tutorial_N_KR.jpg) + next.
## 근거: DungeonTutorialLayer.c initWidget(VisibleRect 전체 + dungeon_tutorial_%d_%s.jpg + btn_arrow2 setNext).
const _TUT_PAGES := 2
func _maybe_dungeon_tutorial() -> void:
	if not _is_fortress():
		return                             # DungeonTutorialLayer 도 해골 요새 콘텐츠다
	if bool(UserDB.get_pmeta("dungeon_tut_seen", false)):
		return
	UserDB.set_pmeta("dungeon_tut_seen", true)
	_open_dungeon_tutorial(0)

func _open_dungeon_tutorial(page: int) -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 40; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.82); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var p := "res://assets/converted/tutorial_ui/dungeon_tutorial_%d_KR.jpg" % (page + 1)
	if ResourceLoader.exists(p):
		var tr := TextureRect.new(); tr.texture = load(p)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(tr)
	var last := page + 1 >= _TUT_PAGES
	# 다음/닫기(원작 btn_arrow2 setNext). 마지막 페이지=시작하기.
	var nb := Button.new()
	nb.text = "시작하기" if last else "다음 ▶"
	nb.add_theme_font_size_override("font_size", 22); nb.size = Vector2(160, 48)
	nb.position = Vector2(vis.x - 184, vis.y - 68)
	nb.pressed.connect(func():
		if is_instance_valid(layer): layer.queue_free()
		if not last: _open_dungeon_tutorial(page + 1))
	layer.add_child(nb)
	# 페이지 표시
	var pg := Label.new(); pg.text = "%d / %d" % [page + 1, _TUT_PAGES]
	pg.add_theme_font_size_override("font_size", 18); pg.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	pg.position = Vector2(24, vis.y - 60); layer.add_child(pg)

## 🔴 **"Dungeon" 키워드 = 해골 요새 전용이다** (사용자 확정 2026-07-28)
##
## 우리는 모든 스테이지를 "던전"이라 부르지만, **원작에서 `Dungeon*` 은 해골 요새의 층별 탐색
## 콘텐츠**를 가리킨다. 근거는 자산 쪽이 더 분명하다 — `scene/adventure/skeleton_fortress`
## 아틀라스 39프레임이 곧 그 시스템 전체다:
##   칸 아이콘 `icon_card_on/off` · `icon_shop_on/off` · `icon_treasurebox_on/off` ·
##   `icon_monster/boss/gold/question_on/off` · 층 `floor_icon_bg` · `floor_stair` ·
##   성 지하 `under_castle_top/bot_bar` · `icon_under_castle` · `money_bg_castle` ·
##   입장/퇴장 `btn_join` · `btn_exit` · `btn_tuto` · 결과 `result_bg` · `result_rank_box` ·
##   버프 카드 `buf_atk` · `buf_def`
## 클래스도 한 묶음이다: `DungeonScene` · `DungeonStage(Layer)` · `DungeonShuffleLayer` ·
##   `DungeonRewardLayer` · `DungeonFinishLayer` · `DungeonTutorialLayer` · `WeeklyDungeonScene`.
##
## ⇒ `setEventDungeonCardGame1/2` · `setEventDungeonShop` · `setEventDungeonChoice` 는
##   **일반 스테이지에서 뜨면 안 된다.** (반면 `setEventTreasure`·`setEventHealArea` 는
##   Dungeon 키워드가 없다 = 일반 탐험 이벤트다.)
## ⚠️ NPC **아임**도 해골 요새 전용이다 — `Tip_49` "해골요새의 아임과 퐁은 다섯 현자로 알려진
##   로쿠난의 제자입니다", `ShopWelcomeImp9`(임프 상점). 일반 탐험에 등장시키지 않는다.
##
## 우리는 층 구조 던전 콘텐츠를 아직 안 만들었으므로, 그때까지는 **해골 요새 스테이지**에서만
## 이 이벤트들을 띄운다 — 위키 map.pdf 도 "해골요새를 탐험하다보면 … 카드가 그려진 그림이
## 있을 텐데" 라고 그 위치를 특정한다.
const FORTRESS_STAGE := "6"      # data/stages.json 6 = 해골 요새

func _is_fortress() -> bool:
	return String(_params.get("stage", "")) == FORTRESS_STAGE

## 카데스의 공간(유타칸 전설 모드)인가. 진입 자체가 **변형 필드 id(601~614)** 로 이뤄지므로
## 스테이지 id 만 보면 알 수 있다 — `params.kades` 는 테스트/직접호출용 override 로만 남긴다.
## 근거: 원작 `WorldMapPopupLayer::init` 이 kades 일 때 fieldNo = 600 + field (DungeonBG).
func _is_kades() -> bool:
	if _params.has("kades"):
		return bool(_params.get("kades"))
	return String(_stage.get("variant", "")) == "kades"

## 기본 필드 id(1~15). 카데스 변형이면 600을 뺀 값. 아티팩트 배정표 조회에 쓴다.
func _base_field() -> int:
	return DungeonBG.base_field(DungeonBG.field_id(_stage))

## 이번 탐험에 나선 드래곤들의 각성 스킬 **탐험 보너스** 합 {gold_pct, artifact_chance_pct}.
## 42 부유한 기운(골드 +50%) · 17 구드라의 가호(아티팩트 확률 +50%). 판정=AwakenSkill(logic).
func _awaken_explore() -> Dictionary:
	var lst: Array = []
	for uid in _run_party:
		var d := UserDB.get_dragon(int(uid))
		if d.is_empty() or not bool(d.get("awakened", false)):
			continue
		lst.append({"awaken_no": int(d.get("awaken_skill", 0))})
	return AwakenSkill.explore_bonus(lst, Data.skill_awaken)

## 탐험 중 얻는 골드는 **전부 여기를 지난다** — 각성 스킬 '부유한 기운'이 한 곳에서 걸리게.
## 반환 = 실제로 지급한 금액(표시 문구에 그대로 쓸 것).
func _grant_gold(amount: int) -> int:
	var g := int(round(float(amount) * AwakenSkill.mult_of(_awaken_explore(), "gold_pct")))
	UserDB.add_currency("gold", g)
	return g

## 원작 카드게임 — `AdventureScene` 이벤트 분기의 **0x18 `setEventDungeonCardGame1`** ·
## **0x19 `setEventDungeonCardGame2`** 두 종류다(AdventureScene.c:18009/18012).
## 위키 dungeon_1.pdf 도 "2종류가 있는데 하나는 8개의 카드를 섞어 4번의 기회중 1번이라도 2개의
## 짝을 맞추면 성공, 다른 하나는 3개의 카드들 중 1~2개의 꽝이 있는데 그 꽝을 피하면 성공" 이라고
## 적는다. 규칙·보상 = `data/card_game.json`, 판정 = `CardGame`(logic), 화면 = `CardMiniGame`(render).
##
## 🟠 정정(2026-07-28): 종전 구현은 "3장 중 1장을 골라 골드/아이템" 이라는 **자작**이었다.
##   원작이 2종이라는 것도, 짝맞추기가 있다는 것도 반영돼 있지 않았다. 전면 교체한다.
##   등장 확률(원작 값은 서버 소유라 유실)은 `data/adventure_events.json` 로 옮겼다 —
##   이제 다른 이벤트와 **한 스텝을 두고 배타 추첨**된다(AdventureRun.build_steps).
func _open_cardgame(mode: String) -> void:
	_event_open = true
	Bgm.sfx("effect_card_shuffle")
	var vis := _vis()
	# 원작 카드게임 시작 아트 `txt_go`(191×78) — 미니게임 위로 팝했다 사라진다.
	var golayer := CanvasLayer.new()
	golayer.layer = 90
	add_child(golayer)
	var go := _spr("card_game", "scene_adventure_card_game_txt_go", _man("card_game"),
		Design.ASSET_SCALE)
	if go:
		go.position = Vector2(vis.x * 0.5, vis.y * 0.13)
		golayer.add_child(go)
		go.scale *= 0.4
		var gt := go.create_tween()
		gt.tween_property(go, "scale", go.scale * 2.5, 0.22).set_trans(Tween.TRANS_BACK)
		gt.tween_interval(0.7)
		gt.tween_property(go, "modulate:a", 0.0, 0.3)
		gt.tween_callback(golayer.queue_free)
	else:
		golayer.queue_free()
	# 원작 인트로 대사 — `CardMiniGame_Dungeon_Ready1~6`(각 2줄) 중 한 세트.
	# 어느 세트인지는 서버가 정했다(유실) → 스테이지·조우 시드로 고른다.
	var rr := RandomNumberGenerator.new()
	rr.seed = hash("cardtalk_%s_%d" % [String(_params.get("stage", "")), int(_params.get("enc", 0))])
	var ready: Array = Data.card_game.get("talk", {}).get("dungeon", {}).get("ready", [])
	if not ready.is_empty():
		var set_: Array = ready[rr.randi_range(0, ready.size() - 1)]
		for line in set_:
			_narrate_npc("아임", String(line))
	CardMiniGame.open(self, mode, func(res): _on_cardgame_done(res))

## 미니게임 결과 → 보상 지급. **지급은 여기(호출자)에서 한다** — CardMiniGame 은 규칙도
## 인벤토리도 모른다(§8.3). 보상 종류는 위키 확정분이고 수치는 data/card_game.json.
func _on_cardgame_done(res: Dictionary) -> void:
	var win := bool(res.get("win", false))
	var rw: Dictionary = res.get("reward", {})
	var msg := "꽝!"
	if win and not rw.is_empty():
		msg = _grant_card_reward(rw)
	# NPC **아임은 해골 요새 전용**이다(`Tip_49` "해골요새의 아임과 퐁은 … 로쿠난의 제자입니다",
	# `ShopWelcomeImp9` 임프 상점). 그 밖에서는 이름을 붙이지 않는다 — 사용자 확정 2026-07-28.
	if _is_fortress():
		# 원작 `CardMiniGame_Dungeon_Success_1` / `Fail_1` 그대로. 얻은 것은 뒤에 덧붙인다.
		var tk: Dictionary = Data.card_game.get("talk", {}).get("dungeon", {})
		var pool: Array = tk.get("success" if win else "fail", [])
		var line := String(pool[0]) if not pool.is_empty() else ("좋았어!" if win else "다음 기회에!")
		_narrate_npc("아임", ("%s
(%s)" % [line, msg]) if win else line)
	else:
		_narrate("%s" % msg if win else "꽝!")
	_step_done()

## 카드 보상 1건 지급. 반환 = 표시 문구.
##   heal/buff 는 **이번 탐험의 전투 상태**에 얹고(물약과 같은 통로), gold/diamond/egg 는 UserDB.
func _grant_card_reward(rw: Dictionary) -> String:
	match String(rw.get("kind", "")):
		"gold":
			var g := _grant_gold(int(rw.get("amount", 0)))
			return "골드 +%d" % g
		"diamond":
			var dm := int(rw.get("amount", 0))
			UserDB.add_currency("diamond", dm)
			return "다이아 +%d" % dm
		"egg":
			# 뽑기 알과 같은 가상 인벤 키로 넣는다(EggGacha 소유 규약).
			var did := int(rw.get("dragon_id", 0))
			if did > 0:
				UserDB.add_item(EggGacha.key_for(did), 1)
				return "%s의 알" % String(Data.get_dragon(did).get("name", "드래곤"))
			return "알"
		"heal":
			# 원작 map.pdf "드래곤을 회복시켜주기도" — 회복샘(setEventHealArea)과 **같은 통로**를 쓴다.
			# `_healed = true` 면 다음 전투를 풀피로 시작한다(_go_battle 이 hp_state 를 비운다).
			_healed = true
			return "체력 회복"
		"buff_att", "buff_def":
			# 드링크와 **같은 통로**(UserDB 드래곤의 `drink_buffs`) — battle.gd 가 그걸 읽는다.
			# 수치도 새로 만들지 않고 item_effects.json 의 drink 규칙을 그대로 쓴다.
			var stat := "att" if String(rw.get("kind", "")) == "buff_att" else "def"
			var per := int(Data.item_effects.get("drink", {}).get("pct_per_tier", 5))
			var turns := int(Data.item_effects.get("drink", {}).get("duration_turns", 10))
			var tier := int(rw.get("tier", 1))
			var eff := {"stat": stat, "tier": tier, "pct": per * tier, "turns": turns}
			for uid in _run_party:
				var cur: Dictionary = UserDB.get_dragon(int(uid)).get("drink_buffs", {})
				UserDB.set_dragon_field(int(uid), "drink_buffs",
					ItemEffect.apply_drink(cur, eff))
			return "%s +%d%% (%d턴)" % ["공격력" if stat == "att" else "방어력",
				per * tier, turns]
	return "꽝"

## 원작 setEventDungeonShop(0x1a): 떠돌이 상인 → 아이템 3종 판매(골드).
## 등장 확률은 `data/adventure_events.json`(해골요새 전용, 다른 이벤트와 배타 추첨).
func _open_shop(r: RandomNumberGenerator) -> void:
	# 원작 DungeonShopScene 1:1(순수 클라). 근거: DungeonShopScene.c playBackground(1378)="music/bg_shop.mp3",
	#   setTalker(상인 NPC), common/item_bg 아이템셀 + coin_small1 + money_bg_castle. 오버레이 적응(전용씬 아님).
	_event_open = true
	Bgm.play("bg_shop")   # 원작 DungeonShopScene BGM(DungeonShopScene.c:1378)
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 20; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.75); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	# 상인 스파인(배회 상인 재활용)
	if ResourceLoader.exists("res://scenes/npc/wonder.tscn"):
		var mh := Node2D.new(); mh.position = Vector2(vis.x * 0.22, vis.y * 0.55); mh.scale = Vector2(0.7, 0.7)
		layer.add_child(mh)
		var mi = (load("res://scenes/npc/wonder.tscn") as PackedScene).instantiate(); mh.add_child(mi)
		var ap := mi.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.get_animation_list().size() > 0:
			ap.get_animation(ap.get_animation_list()[0]).loop_mode = Animation.LOOP_LINEAR
			ap.play(ap.get_animation_list()[0])
	var title := Label.new(); title.text = "떠돌이 상인  —  필요한 것을 사세요"
	title.add_theme_font_size_override("font_size", 24); title.add_theme_color_override("font_color", Color(1, 0.92, 0.6))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.size = Vector2(vis.x, 34); title.position = Vector2(0, vis.y * 0.16)
	layer.add_child(title)
	# 보유 골드(원작 money_bg_castle + coin_small1). 우상단.
	var cman := _man("common_ui")
	var gcoin := _spr("common_ui", "common_coin_small1", cman, 1.0)
	if gcoin: gcoin.position = Vector2(vis.x * 0.5 - 96, vis.y * 0.24); layer.add_child(gcoin)
	var glabel := Label.new()
	glabel.add_theme_font_size_override("font_size", 20); glabel.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	glabel.size = Vector2(160, 26); glabel.position = Vector2(vis.x * 0.5 - 78, vis.y * 0.24 - 12)
	layer.add_child(glabel)
	var upd_gold := func(): glabel.text = "%d" % UserDB.gold()
	upd_gold.call()
	# 판매 아이템 3종(소비/재료 풀서 시드추첨). 원작 common/item_bg 셀 + 아이콘 + 이름 + coin 가격.
	var pool: Array = Data.items_by("consumable") + Data.items_by("material")
	for i in 3:
		if pool.is_empty(): break
		var key: String = pool[r.randi() % pool.size()]
		var price := 150 + r.randi() % 350
		var cx := vis.x * 0.5; var cy := vis.y * 0.36 + i * 92.0
		# 원작 common/item_bg 슬롯 프레임.
		var slot := _spr("common_ui", "common_item_bg", cman, 1.0)
		if slot: slot.position = Vector2(cx - 150, cy); layer.add_child(slot)
		var ip := Data.item_icon_path(key)
		if ResourceLoader.exists(ip):
			var icon := Sprite2D.new(); icon.texture = load(ip); icon.material = _pma
			icon.scale = Vector2(0.62, 0.62); icon.position = Vector2(cx - 150, cy); layer.add_child(icon)
		var nm := Label.new(); nm.text = Data.item_name(key)
		nm.add_theme_font_size_override("font_size", 20); nm.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
		nm.position = Vector2(cx - 110, cy - 16); nm.size = Vector2(200, 24); layer.add_child(nm)
		var pcoin := _spr("common_ui", "common_coin_small1", cman, 0.8)
		if pcoin: pcoin.position = Vector2(cx + 96, cy); layer.add_child(pcoin)
		var pl := Label.new(); pl.text = "%d" % price
		pl.add_theme_font_size_override("font_size", 18); pl.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
		pl.position = Vector2(cx + 108, cy - 12); pl.size = Vector2(70, 22); layer.add_child(pl)
		var buy := Button.new(); buy.text = "구매"; buy.size = Vector2(80, 40); buy.position = Vector2(cx + 150, cy - 20)
		layer.add_child(buy)
		buy.pressed.connect(func():
			if UserDB.spend("gold", price):
				UserDB.add_item(key, 1); Bgm.sfx("effect_coin")
				buy.text = "✓"; buy.disabled = true; upd_gold.call()
			else:
				buy.text = "부족")
	var leave := Button.new(); leave.text = "떠나기"; leave.size = Vector2(160, 44)
	leave.position = Vector2(vis.x * 0.5 - 80, vis.y * 0.36 + 3 * 92.0)
	leave.pressed.connect(func():
		Bgm.play(_explore_bgm())   # 원작 던전 BGM 복귀
		if is_instance_valid(layer): layer.queue_free()
		_step_done())
	layer.add_child(leave)

## 원작 setEventDungeonChoice(0x1b): 갈림길. 두 길 중 선택 → 즉시 결과.
## 등장 확률은 `data/adventure_events.json`(해골요새 전용, 다른 이벤트와 배타 추첨).
## ⚠️ 원작의 4변형(사다리/물약/샘/상자 + 성공·실패 문구 `AdventureDungeonChoice1~4`)은
##   버튼 라벨 프레임(`choice_up/pass/drink/open`)이 추출 에셋에 없어 아직 이식하지 못했다 —
##   아래 '안전한 길/위험한 길'은 **자작**이다(포팅 카드 AdventureEventFlow.md §4).

func _open_choice(r: RandomNumberGenerator) -> void:
	_event_open = true
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 20; add_child(layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.72); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var title := Label.new(); title.text = "갈림길  —  어느 길로 갈까요?"
	title.add_theme_font_size_override("font_size", 24); title.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.size = Vector2(vis.x, 34); title.position = Vector2(0, vis.y * 0.2)
	layer.add_child(title)
	# 두 길: 안전(작은 확정 보상) vs 위험(큰 확률 보상 or 꽝). 결과는 시드로 미리 롤.
	var paths := [
		{"name": "안전한 길", "desc": "확정 소량 보상", "col": Color(0.4, 0.7, 0.9)},
		{"name": "위험한 길", "desc": "큰 보상 or 꽝", "col": Color(0.9, 0.5, 0.4)},
	]
	# 원작 버튼 프레임: `scene/adventure/btn1.png` / `btn2.png` (262x94).
	# 근거: AdventureScene.c 리터럴 + docs/ref/orig_image/battle/화면 캡처 2026-07-26 024440.png
	# (탐험 중 "그만하기"(적)/"계속하기"(녹) 2버튼). 자작 StyleBox 박스를 원작 프레임으로 교체.
	var BTN_W := 262.0
	var BTN_H := 94.0
	for i in 2:
		var p: Dictionary = paths[i]
		var holder := Control.new()
		holder.size = Vector2(BTN_W, BTN_H)
		holder.position = Vector2(vis.x * 0.5 + (-BTN_W - 24.0 if i == 0 else 24.0), vis.y * 0.40)
		layer.add_child(holder)
		var frame := _spr("adventure_ui", "scene_adventure_btn%d" % (2 if i == 0 else 1), _adv, 1.0)
		if frame:
			frame.position = Vector2(BTN_W * 0.5, BTN_H * 0.5)
			holder.add_child(frame)
		var lb := Label.new()
		lb.text = String(p["name"])
		lb.add_theme_font_size_override("font_size", 26)
		lb.add_theme_color_override("font_color", Color.WHITE)
		lb.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0, 0.9))
		lb.add_theme_constant_override("outline_size", 4)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.size = Vector2(BTN_W, 30); lb.position = Vector2(0, 16)
		holder.add_child(lb)
		var sub := Label.new()
		sub.text = String(p["desc"])
		sub.add_theme_font_size_override("font_size", 15)
		sub.add_theme_color_override("font_color", Color(1, 0.97, 0.85, 0.92))
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.size = Vector2(BTN_W, 22); sub.position = Vector2(0, 50)
		holder.add_child(sub)
		var hit := Button.new(); hit.flat = true
		hit.size = Vector2(BTN_W, BTN_H)
		holder.add_child(hit)
		hit.pressed.connect(_choose_path.bind(i, r, title, layer))

func _choose_path(idx: int, r: RandomNumberGenerator, title: Label, layer: CanvasLayer) -> void:
	if not is_instance_valid(layer): return
	var msg := ""
	if idx == 0:   # 안전: 확정 소량 골드
		var g := _grant_gold(60 + r.randi() % 90)
		msg = "안전한 길 — +골드 %d" % g
	else:   # 위험: 60% 큰 보상, 40% 꽝
		if r.randf() < 0.6:
			var g := _grant_gold(200 + r.randi() % 300)
			var pool: Array = Data.items_by("consumable") + Data.items_by("material")
			var it := ""
			if not pool.is_empty():
				var key: String = pool[r.randi() % pool.size()]
				UserDB.add_item(key, 1); it = " / %s" % Data.item_name(key)
			Bgm.sfx("effect_coin"); msg = "위험한 길 — 대박!  +골드 %d%s" % [g, it]
		else:
			msg = "위험한 길 — 아무것도 없었다…"
	title.text = msg
	# 버튼 제거(하위 Button만)
	for c in layer.get_children():
		if c is Button: c.queue_free()
	get_tree().create_timer(1.2).timeout.connect(func():
		if is_instance_valid(layer): layer.queue_free()
		_step_done())

## ⚫ **CUT — 보물지도 조우(원작 `setEventTreasure` 0x15)** (사용자 확정 2026-07-31)
##
## 탐험 이벤트 풀에서 뺐다(`data/adventure_events.json` `steps._cut_treasure`, 종전 weight=22).
## 이유: 원작의 이 이벤트는 "보물**지도**를 줍는다"이고, 주운 지도는
##   `setAdventureMiniMapIcon`(미니맵 아이콘) → `use_map.hb` → "보물찾기 시작!" 으로 이어져
##   결국 **seek(탐색)** 로 간다. 그런데 seek 은 **칸별 배치를 서버가 정하던 시스템**이라
##   규칙(`avail_way`/`quest_goal`)이 유실됐고 UI 자산(`newScene/seek/`·`new9patch/st_*`)도 없다.
##   ⇒ 종착지가 없는 입구를 열어 두지 않는다.
##
## 원작 연출(워드아트 안무·플래시·효과음·문자열 키)은 전부
## `docs/ref/porting/AdventureScene.md` §5 에 기록해 뒀다 — 되살릴 근거가 생기면 거기서 시작한다.
## 안무 자체는 회복샘이 같은 것을 쓰므로 아래 `_wordart_burst` 로 살아 있다.
## 원작 이벤트 워드아트 — `setEventTreasure` · `setEventHealArea` 가 **같은 안무**를 쓴다.
##
## `CCLabelBMFont::create(text, GameManager::getFontName_title(), -1.0)` @ (w*0.5, h*0.7) 에
## 아래 순서로 액션을 건다(디컴프 리터럴 그대로):
##   ScaleTo(0.4, **1.7**) ∥ RotateTo(0.2, **380°**)
##   → RotateTo(0.1333, **−30**) → RotateTo(0.1333, **15**) → RotateTo(0.1333, **−5**)
##   → ScaleTo(0.1, **1.2**) → (0.7 대기) → MoveBy(0.2, **(0, 140)**)
## 곁들이는 것: 전체화면 `CCLayerColor` FadeTo(0.5, **200**) 플래시 +
##   파티클 `particle/scene/adventure/pt_monster_income_1.plist`.
##
## 안무 자체는 `WordArt.burst`(scripts/ui/word_art.gd)로 추출 — 전투 보상 페이즈(battle.gd)와
## 같은 리터럴을 쓰기 위해서다. 총 길이 상수도 거기 것을 쓴다.
## 🟠 2026-08-01 걷어냄: 종전엔 여기서 **흰색 플래시**를 만들었는데 원작은 **검은 막**
##   (CCLayerColor {0,0,0} FadeTo(0.5, 200), tag 0x75)이고 수명도 이벤트 전체다 →
##   `_event_dim_show/_clear` 로 분리(setEventHealArea 디컴프 :62410-62414).
const _WORDART_SECS := WordArt.SECS

func _wordart_burst(text: String) -> void:
	var vis := _vis()
	WordArt.burst(self, text, vis, 195, 100.0, true)
	CocosParticle.spawn(self, "pt_monster_income_1", Vector2(vis.x * 0.5, vis.y * 0.3), 194, 0.8)

## 이벤트 검은 막 — 원작 tag 0x75 레이어(CCLayerColor {0,0,0,0} → FadeTo(0.5, 200)).
## 이벤트 연출(회복샘 등)이 도는 동안 화면을 어둡게 하고, 끝나면 `_event_dim_clear` 로 걷는다.
var _event_dim: ColorRect
func _event_dim_show() -> void:
	if is_instance_valid(_event_dim):
		return
	_event_dim = ColorRect.new()
	_event_dim.color = Color(0, 0, 0, 0)
	_event_dim.size = _vis()
	_event_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_event_dim.z_index = 188
	add_child(_event_dim)
	_event_dim.create_tween().tween_property(_event_dim, "color:a", 200.0 / 255.0, 0.5)

func _event_dim_clear() -> void:
	if not is_instance_valid(_event_dim):
		return
	var d := _event_dim
	_event_dim = null
	var t := d.create_tween()
	t.tween_property(d, "color:a", 0.0, 0.3)
	t.tween_callback(d.queue_free)


## 회복샘 — 원작 `setEventHealArea(bool)` (0x13 = 성스러운 / 0x14 = 평범한).
##
## ⚠️ **원작에는 선택지가 없다.** `setEventHealArea` 는 버튼을 만들지 않고 연출과 회복만 한다
##   (`BattleDragon::getHealAreaRecoverHp()` 만큼). 선택형 샘은 별개 이벤트인
##   `setEventDungeonChoice`(해골요새 전용, 프레임 미보유)다 — 포팅 카드 §4.
##
## 원작 연출(리터럴 그대로):
##   · `music/effect_holy_well_2.mp3`(성스러운) / `music/effect_water_in.mp3`(평범한)
##   · 평범한 쪽은 샘 스프라이트에 청록 틴트(ccColor3B 0x80bf/0xf2), 성스러운 쪽은 WHITE
##   · `scene/adventure/fountain/dv2_fountain_base.png` + `dv2_fountain_01~05.png`
##   · 제목 라벨: ScaleTo(0.4, 1.7) + RotateBy(0.2, 380°) 로 회전하며 커진 뒤
##     0.7초 뒤 위로 MoveBy(0.2, +100)
##   · 파티클 `particle/scene/adventure/pt_monster_income_1.plist`
##
## holy = 0x13(성스러운) / false = 0x14(평범한).
func _show_fountain(holy: bool) -> void:
	_event_open = true
	_healed = true    # 이 조우 전투는 풀피로 시작(hp_state 초기화)
	Bgm.sfx("effect_holy_well_2" if holy else "effect_water_in")
	var vis := _vis()
	# 검은 이벤트 막 — 원작 setEventHealArea :62410 CCLayerColor {0,0,0} FadeTo(0.5, 200), tag 0x75.
	_event_dim_show()
	# 회복샘 그래픽 — 원작 `scene/adventure/fountain` 아틀라스(base + 01~05, 천사상 분수).
	# 원작 안무(:62510-62579 리터럴):
	#   · setScale(배율×0.7) · 시작 위치 = 화면 중앙 + (0, 높이+10) → Delay(0.5) 후
	#     MoveBy(0.25, (0, −높이)) + EaseExponentialOut — **위에서 떨어져 내려온다**
	#   · 물결 5프레임은 base 의 **자식**으로 (w*0.5, h*0.38) 에 놓고 0.1s 간격 순환
	# 🟦 틴트(사용자 확정 2026-08-01): 원작은 평범한 쪽(0x14)에 보라 틴트(0xbf,0x80,0xf2)를
	#   먹이지만, 그 색이 해골요새 '저주받은 샘'처럼 보인다는 지적으로 **틴트를 걷고 원본
	#   fountain.png 그대로** 낸다(성/평범의 차이는 효과음만 남긴다).
	var S := Design.ASSET_SCALE
	var fman := _man("adventure_fountain")
	var f := _spr("adventure_fountain", "scene_adventure_fountain_dv2_fountain_base", fman, S * 0.7)
	if f:
		var fh := float(fman.get("scene_adventure_fountain_dv2_fountain_base", {}).get("h", 400)) * S * 0.7
		var end_y := vis.y * 0.5 - 10.0            # cocos 중앙+(0,+10) → godot 중앙−10
		f.position = Vector2(vis.x * 0.5, end_y - fh)
		f.z_index = 189                            # 검은 막(188) 위, 워드아트(195) 아래
		add_child(f)
		_fountain_node = f
		var dt := f.create_tween()
		dt.tween_interval(0.5)
		dt.tween_property(f, "position:y", end_y, 0.25) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		# 물결 애니 — base 자식 @ (w*0.5, h*0.38) → 중심 기준 (0, +0.12h). 0.1s 순환(원작
		# CCCallFuncN + CCDelayTime(0.1) RepeatForever).
		var frames: Array = []
		for i in range(1, 6):
			var tp := "res://assets/converted/adventure_fountain/scene_adventure_fountain_dv2_fountain_%02d.tres" % i
			if ResourceLoader.exists(tp):
				frames.append(load(tp))
		if not frames.is_empty():
			var wave := Sprite2D.new()
			wave.texture = frames[0]
			wave.material = f.material
			var bh := float(fman.get("scene_adventure_fountain_dv2_fountain_base", {}).get("h", 400))
			wave.position = Vector2(0, bh * 0.12)   # 부모 스케일을 그대로 물려받는다(원작 자식 구조)
			f.add_child(wave)
			if frames.size() > 1:
				var wt := wave.create_tween().set_loops()
				for tex in frames:
					wt.tween_callback(func(): wave.texture = tex)
					wt.tween_interval(0.1)
	# 원작 `setEventHealArea` 가 쓰는 파티클은 **`pt_monster_income_1.plist` 하나뿐**이다.
	CocosParticle.spawn(self, "pt_monster_income_1",
		Vector2(vis.x * 0.5, FLOOR * 0.5), 194, 0.7)
	# 워드아트 `<AdventureQuestCount_heal>` + 텍스트박스 `<AdventureHealArea>` (원작 문자열 그대로).
	_wordart_burst("회복의 샘 발견")
	_narrate("회복의 샘을 발견하여 체력이 조금 회복되었습니다.")
	# 회복샘은 원작에서 **선택지 없이** 흘러가는 스텝이다 → 연출이 끝나면 정리하고 다음 스텝으로.
	# 🔴 2026-08-01: 종전엔 샘·막을 **아무도 지우지 않아** 탐험 내내 화면에 남았다(사용자 신고).
	get_tree().create_timer((_WORDART_SECS + 0.6) / maxf(_speed, 1.0)).timeout.connect(_end_fountain)

var _fountain_node: Sprite2D
func _end_fountain() -> void:
	_event_dim_clear()
	if is_instance_valid(_fountain_node):
		var f := _fountain_node
		_fountain_node = null
		var t := f.create_tween()
		t.tween_property(f, "modulate:a", 0.0, 0.3)
		t.tween_callback(f.queue_free)
	_step_done()

## 혼돈의 틈새 화염 — 원작 `AdventureScene::init`(:20929)이 **다크닉스 모드일 때만**
## `particle/scene/adventure/pt_monster_fire_back.plist` 를 새 CCLayer(z=999999 / tag=0x9c)에
## 담아 `VisibleRect::bottom()` 에 놓는다. 문자열도 이 연출을 말한다 —
## `<AdventureField_8>` "작열하는 화염 속에서 무시무시한 존재가 당신을 기다립니다."
## 변환 = `scripts/tools/particle_export.py` → assets/converted/particles/pt_monster_fire_back.json.
func _build_chaos_fire() -> void:
	if not Darknix.is_summon_stage(_stage):
		return
	var f := FileAccess.open("res://assets/converted/particles/pt_monster_fire_back.json", FileAccess.READ)
	if f == null:
		return
	var c = JSON.parse_string(f.get_as_text())
	if typeof(c) != TYPE_DICTIONARY:
		return
	var vis := get_viewport_rect().size
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g; tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5); tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32; tex.height = 32
	var p := CPUParticles2D.new()
	p.texture = tex
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD if bool(c.get("additive", true)) \
		else CanvasItemMaterial.BLEND_MODE_MIX
	p.material = m
	p.amount = int(c.get("amount", 30))
	p.lifetime = float(c.get("lifetime", 6.0))
	p.lifetime_randomness = float(c.get("lifetime_randomness", 0.0))
	p.direction = Vector2(float(c["direction"][0]), float(c["direction"][1]))
	p.spread = float(c.get("spread", 0.0))
	p.initial_velocity_min = maxf(0.0, float(c.get("vmin", 0.0)))
	p.initial_velocity_max = maxf(0.0, float(c.get("vmax", 0.0)))
	p.gravity = Vector2(float(c["gravity"][0]), float(c["gravity"][1]))
	p.radial_accel_min = float(c.get("radial_min", 0.0))
	p.radial_accel_max = float(c.get("radial_max", 0.0))
	p.tangential_accel_min = float(c.get("tangential_min", 0.0))
	p.tangential_accel_max = float(c.get("tangential_max", 0.0))
	# ⚠️ `scale_min/max` 는 **이미 최종 배율**이다 — `particle_export.py` 가 절차생성 점 텍스처
	#    기준(BASE=32px)으로 나눠 놓는다. 여기에 또 곱하면 입자가 그만큼 커진다
	#    (🔴 2026-07-31: ×24 를 곱해 화면이 하얗게 덮였다).
	p.scale_amount_min = float(c.get("scale_min", 0.1))
	p.scale_amount_max = float(c.get("scale_max", 1.0))
	# 수명에 따라 줄어드는 크기(원작 finishParticleSize / startParticleSize).
	var er := float(c.get("scale_end_ratio", 1.0))
	if not is_equal_approx(er, 1.0):
		var sc := Curve.new()
		sc.add_point(Vector2(0.0, 1.0))
		sc.add_point(Vector2(1.0, maxf(0.01, er)))
		p.scale_amount_curve = sc
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(float(c["emit_rect"][0]), maxf(1.0, float(c["emit_rect"][1])))
	# 🔴 `color` 만 주면 시작색이 수명 내내 유지된다 — 가산 블렌드에서는 입자가 절대 사라지지
	#    않고 계속 쌓여 화면이 하얗게 된다. 원작 plist 는 start→finish 알파 램프를 갖는다.
	var cs: Array = c.get("color_start", [1, 1, 1, 1])
	var ce: Array = c.get("color_end", [0, 0, 0, 0])
	var cg := Gradient.new()
	cg.set_color(0, Color(float(cs[0]), float(cs[1]), float(cs[2]), float(cs[3])))
	cg.set_color(1, Color(float(ce[0]), float(ce[1]), float(ce[2]), float(ce[3])))
	p.color_ramp = cg
	# 원작 VisibleRect::bottom() = 화면 하단 중앙.
	p.position = Vector2(vis.x * 0.5, vis.y)
	p.z_index = 60          # 배경 위·텍스트박스 아래(원작 z=999999 는 그 레이어 안에서의 값)
	add_child(p)

var _bg_node: Control            # 정지 배경 — 배회 사본을 이 **바로 위**에 넣는다

func _build_bg() -> void:
	# 던전 배경(DungeonBG) — 원작 scene/adventure/bg/<필드id>/ 의 원경 bg.jpg + 전경 bg_item.
	# battle과 동일 리졸버라 탐험/전투 배경이 일치한다.
	_bg_node = DungeonBG.build(self, _stage)
	_build_chaos_fire()
	if _bg_node != null:
		return
	var bg := TextureRect.new()
	var p := "res://assets/converted/battle_bg/bg_%d.jpg" % int(_params.get("bg", 1))
	if ResourceLoader.exists(p):
		bg.texture = load(p)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_bg_node = bg

# ---------- 배회(1인칭 전진) — 원작 setAdventureWalk 축자 이식 ----------
## 🔴 2026-07-27 전면 교체. 이전 구현은 Camera2D 상하 bob + 자작 먼지 파티클이었는데
##   **원작에는 둘 다 없다**. 원작 `AdventureScene::setAdventureWalk`(AdventureScene.c:33530-34110,
##   특히 :34043-34090 의 액션 시퀀스)는 이렇게 한다:
##
##   1. 정지 배경 위에 **배경 이미지 사본을 한 장 더** 만든다
##      (`CCSprite::create(<Field 문자열로 조립한 경로>)`, 앵커(0.5,0.5) @ `VisibleRect::center`,
##       `addChild(sprite, 1)`).  ← 사본이라서 확대·이동해도 정지 배경이 뒤를 메운다
##   2. 그 사본에 아래 시퀀스를 건다(스텝시간 t = `InfoEventData[0x128]`, 기본 **0.3s**):
##        Spawn(FadeIn(t), ScaleBy(t,1.1),   MoveBy(t, (   0,-20)))
##        Spawn(          ScaleBy(t,1.05),   MoveBy(t, ( -50,+10)))   → CallFunc
##        Spawn(          ScaleBy(t,1.05),   MoveBy(t, (   0,-20)))
##        Spawn(          ScaleBy(t,1.055),  MoveBy(t, (+100,+10)))   → CallFunc
##        Spawn(          ScaleBy(t,1.05),   MoveBy(t, (   0,-20)))
##        Spawn(          ScaleBy(t,1.055),  MoveBy(t, ( -50,+10)))   → CallFunc
##        FadeOut(t) → removeFromParent → **setAdventureWalk 재호출(무한 루프)**
##      ⇒ 누적 배율 1.1×1.05×1.05×1.055×1.05×1.055 = **1.4173**, 한 사이클 7t = 2.1s.
##   3. 던전 모드면 사본 중앙에 `skeleton_fortress/gate_light.png` 를
##      RepeatForever(FadeTo(1.0,255) → FadeTo(1.25,0)) 로 겹친다.
##
##   ⚠️ Cocos 는 y-up 이라 MoveBy 의 y 부호를 뒤집어 Godot 좌표로 옮겼다.
##   Camera2D 는 남기되 **흔들림 전용**이다(원작 setAllViewShake = Shake 액션).
const _WALK_STEP := 0.3                       # InfoEventData[0x128] 기본값
## 각 스텝의 **누적** 배율/오프셋(Godot 좌표, y 부호 반전 완료).
const _WALK_SCALES := [1.1, 1.155, 1.21275, 1.279456, 1.343429, 1.417316]
const _WALK_OFFS := [Vector2(0, 20), Vector2(-50, 10), Vector2(-50, 30),
	Vector2(50, 20), Vector2(50, 40), Vector2(0, 30)]

var _walk_layer: TextureRect     # 전진하는 배경 사본(매 사이클 새로 만들고 버린다)
var _walk_tw: Tween

func _build_walk() -> void:
	var vis := _vis()
	_cam = Camera2D.new()          # setAllViewShake 전용 — 보행 bob 은 원작에 없다
	_cam.position = vis * 0.5
	add_child(_cam); _cam.make_current()
	# ⚠️ 여기서 배회를 **시작하지 않는다**. 사전 이벤트(회복샘·보물·상점…)가 먼저 끝나야 한다 —
	#   시작은 `_begin_walk()` 가 이벤트 큐의 monster 스텝에서 부른다(원작 순차 스텝 구조).

## 배경 사본 한 장 = 한 사이클. 끝나면 스스로 다음 사이클을 걸거나(원작 재귀) 조우로 넘어간다.
func _start_walk_cycle() -> void:
	if _done or not _walking:
		return
	var vis := _vis()
	var p := DungeonBG.path_for(_stage)
	if p == "":
		p = "res://assets/converted/battle_bg/bg_%d.jpg" % int(_params.get("bg", 1))
	if not ResourceLoader.exists(p):
		return
	var tr := TextureRect.new()
	tr.texture = load(p)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.size = vis
	tr.position = Vector2.ZERO
	tr.pivot_offset = vis * 0.5      # 원작 앵커(0.5,0.5) @ VisibleRect::center
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate.a = 0.0
	# ⚠️ z_index 는 0으로 둔다. 원작의 `addChild(sprite, 1)` 은 "UI(z 수백~)보다 훨씬 아래"라는 뜻인데,
	#    Godot 에서 z_index=1 을 주면 뒤에 추가되는 HUD(z=0) 를 **덮어버린다**(던전명·로드맵·나가기가 사라졌다).
	#    형제 순서만으로 정지 배경 바로 위에 놓는다.
	tr.z_index = 0
	add_child(tr)
	# 🔴 2026-07-27: 종전엔 `move_child(tr, 1)` 로 **인덱스 1**에 넣었다. 씬이 두 번 지어지던
	#   시절(scene_manager 순서 버그) 1차 자식들이 아직 queue_free 대기 중이라 인덱스 1이
	#   **2차 정지 배경보다 아래**였고, 전진하는 배경 사본이 정지 배경에 완전히 가려
	#   "배회 모션이 없다"로 보였다(사용자 신고). 이제 배경 노드 기준으로 바로 위에 꽂는다.
	if is_instance_valid(_bg_node) and _bg_node.get_parent() == self:
		move_child(tr, _bg_node.get_index() + 1)
	else:
		move_child(tr, 1)
	DungeonBG.add_overlay(tr, _stage)   # 전경 오버레이도 함께 전진
	_walk_layer = tr
	var t := _WALK_STEP
	_walk_tw = tr.create_tween()
	for i in 6:
		var st := float(_WALK_SCALES[i])
		var of: Vector2 = _WALK_OFFS[i]
		if i == 0:
			_walk_tw.tween_property(tr, "modulate:a", 1.0, t)
			_walk_tw.parallel().tween_property(tr, "scale", Vector2(st, st), t)
			_walk_tw.parallel().tween_property(tr, "position", of, t)
		else:
			_walk_tw.tween_property(tr, "scale", Vector2(st, st), t)
			_walk_tw.parallel().tween_property(tr, "position", of, t)
	_walk_tw.tween_property(tr, "modulate:a", 0.0, t)
	_walk_tw.set_speed_scale(_speed)          # ▶x2/x3 = 보행 가속
	_walk_tw.finished.connect(func() -> void:
		if is_instance_valid(tr):
			tr.queue_free()
		if _done or not _walking:
			return
		if _t >= _dur:                        # 한 사이클을 마치고 조우로
			_done = true
			_monster_meet()
		else:
			_start_walk_cycle())

# ---------- 상단 정보(던전명 + 로드맵 + 보스 경고) ----------
# 🔴 2026-07-26 정정: 이 함수는 원래 화면 하단에 `scene/adventure/bar.png` + `bar_deco_*_move` +
#   진행 토큰으로 **빨간 진행바**를 그렸다. 원작 탐험 화면에는 그런 바가 없다 —
#   레퍼런스 4장(docs/ref/orig_image/battle/배회1인칭.png, 화면 캡처 …024440 / …024622 / …024723.png)
#   어디에도 하단 진행바가 없고, 하단은 전부 **전폭 텍스트박스**다.
#   그리고 `bar.png`/`bar_deco_*_move`의 원작 용처는 진행바가 아니라 **몬스터 조우 경고 스윕**이다:
#   `AdventureScene::setAlertMonster`(AdventureScene.c:34291-34470)가 VisibleRect::center 기준
#   화면 밖(±w)에서 중앙으로 밀고 들어오는 가로 띠로 쓴다. → _alert_mark 로 옮겼다.
## 🟠 2026-08-01 걷어냄 2건(사용자 지적 — 레퍼런스 배회1~5·승리 전장면에 상단 중앙은 비어 있다):
##   ① 스테이지 이름 + "(n/N)" 흰 라벨 — 원작 탐험 화면에 없는 자작 UI.
##   ② 상단 로드맵(양피지 지도 + 토글 아이콘) — `AdventureMapLayer` 는 **`setEventTreasure`
##      안에서만 생성**된다(AdventureScene.c:67180, tag 0x84). 즉 보물지도를 주웠을 때만
##      뜨는 보물찾기 전용 UI 다. 보물지도 조우는 ⚫컷(포팅 카드 §5)이므로 상시 표시는 오배치.
##      (레퍼런스 승리9/10 에 양피지가 보이는 건 그 영상 런이 보물지도를 주웠기 때문이다.)
## 조우 수(enc/total)는 하단 텍스트박스 서사와 보스 게이지(_build_adventure_navi)가 이미 낸다.
## 보스 경고는 조우 순간의 `setAlertMonster` 컷인이 담당한다(_alert_monster).
func _build_topinfo() -> void:
	pass

# ---------- 하단 서사 텍스트박스(원작 BattleTextBox) + EXP 게이지 ----------
## 원작 탐험 화면의 하단은 **전폭 텍스트박스 하나**다. 레퍼런스 4장 모두 동일:
##   docs/ref/orig_image/battle/배회1인칭.png("당신은 수중동굴로 모험을 떠났습니다…"),
##   화면 캡처 …024440("탐험을 계속 이어가시겠습니까?"), …024622(NPC 대사 `[바루스]`),
##   …024723("마모된 발톱을 획득하였습니다." + 우측 ▶).
## 사양: BattleTextBox.c:167-205 — 9patch/dialogue_box(capInsets 10,10,4,4), contentSize(폭-10, 120),
##   Thonburi 28 흰색 좌정렬, 좌패딩 10. 다음 화살표 = `common/btn_arrow2`(tag 0xc9, :718).
const _NARR_H := 120.0
var _narr_label: Label
var _narr_arrow: Sprite2D
func _build_narration() -> void:
	var vis := _vis()
	var lay := CanvasLayer.new(); lay.layer = 6
	add_child(lay)
	var box := NinePatchRect.new()
	box.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres")
	box.patch_margin_left = 10; box.patch_margin_right = 10
	box.patch_margin_top = 4; box.patch_margin_bottom = 4
	box.size = Vector2(vis.x - 10.0, _NARR_H)
	box.position = Vector2(5.0, vis.y - _NARR_H)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lay.add_child(box)
	_narr_label = Label.new()
	_narr_label.add_theme_font_size_override("font_size", 28)
	_narr_label.add_theme_color_override("font_color", Color.WHITE)
	_narr_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_narr_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_narr_label.size = Vector2(box.size.x - 20.0, _NARR_H - 8.0)
	_narr_label.position = Vector2(10.0, 4.0)
	_narr_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_narr_label)
	# 다음 화살표(원작 common/btn_arrow2) — 우측 하단, 깜빡임.
	_narr_arrow = _spr("common_ui", "common_btn_arrow2", _man("common_ui"), Design.ASSET_SCALE)
	if _narr_arrow:
		_narr_arrow.position = Vector2(box.size.x - 40.0, _NARR_H * 0.5)
		box.add_child(_narr_arrow)
		var at := _narr_arrow.create_tween().set_loops()
		at.tween_property(_narr_arrow, "modulate:a", 0.25, 0.5)
		at.tween_property(_narr_arrow, "modulate:a", 1.0, 0.5)
	# 진입 서사 — 원작 배회1인칭.png 형식("당신은 <던전>로 모험을 떠났습니다.").
	var nm := String(_stage.get("name", "던전"))
	var line := "당신은 %s%s 모험을 떠났습니다." % [nm, _josa_ro(nm)]
	# 원작은 2줄이다(레퍼런스 배회1인칭.png). 2번째 줄 = 던전별 분위기 문장인데 시나리오
	# 서버데이터라 유실 → `data/stages.json` 의 `"intro"`. 유타칸 10던전은 사용자가 작성해 채웠고
	# (docs/input/review/lost_text_sheet.md §1), 나머지는 필드가 없어 1줄만 나온다(문장 생성 금지).
	# ⚠️ 줄바꿈은 반드시 `\n` 이스케이프로. 이 저장소는 CRLF 라서 **문자열 리터럴 안에 실제 개행을
	#    넣으면 `\r\n` 이 되고**, Label 이 `\r` 을 줄바꿈으로 한 번 더 세어 3줄이 되어 잘렸다.
	var intro := String(_stage.get("intro", ""))
	if intro != "":
		line += "\n" + intro
	_narrate(line)

func _narrate(text: String) -> void:
	if is_instance_valid(_narr_label):
		_narr_label.text = text

## NPC 대사 — 원작 형식(레퍼런스 docs/ref/orig_image/battle/화면 캡처 2026-07-26 024622.png):
##   1행 `[ 이름 ]`, 2행 대사. 같은 하단 텍스트박스를 쓴다.
func _narrate_npc(display_name: String, line: String) -> void:
	_narrate("[ %s ]\n%s" % [display_name, line])

## 원작 NPC 파츠 합성 — body + mouth + eye.
## ⚠️ 2026-07-27 현재 **호출부 없음**. 원래는 탐색(seek) 종료 시 안내 NPC 누리를 띄웠는데,
##   탐색 미니게임을 걷어내면서 함께 빠졌다(사용자 확인: 누리는 탐험 중 등장하지 않는다).
##   레이아웃 이식분은 §7-b 백로그의 "NPC 대화 초상" 작업에 쓰려고 남겨 둔다.
## 근거: PopSeekFinishLayer.c:191-217 — `npc/nuri/body_1.png` 를 VisibleRect 기준
##   **화면 하단 중앙**(앵커 (w*0.5, 0))에 두고, 그 자식으로 `mouth_3_2` @(103,310),
##   `eye_4_1` @(104,346) 를 붙인다(=body 로컬, Cocos y-up).
## `asset_index.py --gap npc` 가 83건 전량 미사용이라고 알려준 카테고리다 — 여기서 처음 쓴다.
var _npc_node: Node2D
func _show_npc(npc: String, body := 1, eye := "4_1", mouth := "3_2") -> void:
	_hide_npc()
	var dir := "npc_%s" % npc
	var man := _man(dir)
	if man.is_empty(): return
	var bkey := "npc_%s_body_%d" % [npc, body]
	var bi: Dictionary = man.get(bkey, {})
	if bi.is_empty(): return
	var S := Design.ASSET_SCALE
	var bw := float(bi.get("w", 219)) * S
	var bh := float(bi.get("h", 351)) * S
	var vis := _vis()
	_npc_node = Node2D.new()
	# Cocos 앵커(0.5, 0) @ (visW*0.5, 0) → Godot: 몸통 하단이 텍스트박스 윗변에 닿게.
	_npc_node.position = Vector2(vis.x * 0.5, vis.y - _NARR_H)
	_npc_node.z_index = 4
	add_child(_npc_node)
	var b := _spr(dir, bkey, man, S)
	if b == null: return
	b.position = Vector2(0, -bh * 0.5)
	_npc_node.add_child(b)
	# 파츠 좌표계 변환.
	#   원작: body 로컬 = **포인트** 공간(=픽셀÷0.75), 원점 좌하단, y-up, 자식 앵커 기본 (0.5,0.5).
	#   Godot: body 스프라이트는 텍스처 픽셀 공간(219×351)에 중앙 앵커, 자식은 body의 scale을 상속.
	#   ⇒ godot_x = pos.x/S - w_px/2 ,  godot_y = h_px/2 - pos.y/S   (S로 나눠 포인트→픽셀)
	var bw_px := float(bi.get("w", 219))
	var bh_px := float(bi.get("h", 351))
	for part in [["mouth", mouth, Vector2(103, 310)], ["eye", eye, Vector2(104, 346)]]:
		var key := "npc_%s_%s_%s" % [npc, part[0], part[1]]
		if not man.has(key): continue
		var ps := _spr(dir, key, man, 1.0)   # body의 scale을 상속 → 여기서 또 곱하지 않는다
		if ps == null: continue
		var pos: Vector2 = part[2]
		ps.position = Vector2(pos.x / S - bw_px * 0.5, bh_px * 0.5 - pos.y / S)
		b.add_child(ps)
	# 등장: 아래에서 스윽 올라옴.
	_npc_node.position.y += bh
	create_tween().tween_property(_npc_node, "position:y", vis.y - _NARR_H, 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _hide_npc() -> void:
	if is_instance_valid(_npc_node):
		_npc_node.queue_free()
	_npc_node = null

## ⚫ 2026-08-01 삭제 — 자작 전리품 오버레이(`_show_loot`/`_item_icon_sprite`/`_gear_texture`).
## 보상 표시는 원작 `setEventReward` 이식(battle.gd `_play_reward_phases`)이 담당한다 —
## 이 오버레이는 보물상자 컷 이후 호출처가 없었고, 배치도 레퍼런스(승리4~8)와 달랐다.

## 한글 조사 선택: 받침 없음/ㄹ 받침 → "로", 그 외 → "으로". (원작 문장 "수중동굴로 모험을 떠났습니다")
func _josa_ro(word: String) -> String:
	if word.is_empty(): return "로"
	var c := word.unicode_at(word.length() - 1)
	if c < 0xAC00 or c > 0xD7A3: return "로"
	var jong := (c - 0xAC00) % 28
	return "로" if (jong == 0 or jong == 8) else "으로"

## 받침 유무로 은/는 · 이/가 · 을/를 선택.
func _josa(word: String, with_batchim: String, without: String) -> String:
	if word.is_empty(): return without
	var c := word.unicode_at(word.length() - 1)
	if c < 0xAC00 or c > 0xD7A3: return without
	return with_batchim if ((c - 0xAC00) % 28) != 0 else without

# ---------- HUD(속도 토글 + 나가기) ----------
func _build_hud() -> void:
	var vis := _vis()
	_speed_btn = Button.new()
	_speed_btn.text = "▶ x1"; _speed_btn.position = Vector2(vis.x - 90, 12); _speed_btn.size = Vector2(74, 30)
	_speed_btn.pressed.connect(_cycle_speed)
	add_child(_speed_btn)
	var out := Button.new()
	out.text = "나가기"; out.position = Vector2(16, 12); out.size = Vector2(74, 30)
	out.pressed.connect(func(): Scenes.goto("worldmap", {"region": _params.get("region", "yutakan")}))
	add_child(out)
	_build_objective(int(_params.get("enc", 0)), int((_stage.get("enemies", []) as Array).size()))
	_build_adventure_navi()


# ---------- 보스 게이지(원작 AdventureScene::setAdventureNavi @00c54604) ----------
#
# 레퍼런스 `docs/ref/adventure/승리11_탐험재개.png` 우상단: "보스" 라벨 + 초록→노랑 게이지 +
# 오른쪽 끝 악마 얼굴 아이콘. 탐험이 진행될수록 차오르고 보스 조우에서 가득 찬다.
#
# 원작이 쓰는 프레임(재디컴프 리터럴 전수, 전부 **우리 보유분**):
#   · `scene/adventure/skeleton_fortress/icon_boss_on.png`  — 악마 얼굴(보스 도달 전)
#   · `scene/adventure/skeleton_fortress/icon_boss2_on.png` — 보스 도달(강조 변형)
#   · `scene/laboratory/upgrade_gauge_bg.png` / `upgrade_gauge_bar.png` — 게이지 트랙/채움
#   · `9patch/box1.png` — "보스" 라벨 박스
#   · `%d/%d` 진행 카운트 라벨
#   · 아이콘 펄스: CCScaleTo(0.1, s−0.03) → (0.1, s+0.03) → (0.1, s) 반복
#
# ⚠️ 원작의 등장 트윈 좌표 리터럴은 `CCPoint(60,-120) → CCPoint(60,60)` 인데, 이 값이 어느
#   컨테이너 기준인지(부모 노드의 앵커·위치)를 디컴프에서 확정하지 못했다. 그래서 **바의 절대
#   배치만 레퍼런스 스크린샷 실측으로** 잡고(우상단 고정), 등장 방향(위에서 아래로 0.7초)과
#   펄스 애니는 원작 리터럴 그대로 쓴다. 좌표 근거가 잡히면 이 함수 한 곳만 고치면 된다.
var _boss_bar_fill: Sprite2D
var _boss_count: Label

func _build_adventure_navi() -> void:
	var total := int((_stage.get("enemies", []) as Array).size())
	if total <= 0:
		return
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var lab := _man("laboratory_ui")
	var sf := _man("skeleton_fortress")
	var navi := Node2D.new()
	navi.z_index = 50
	add_child(navi)
	# 실측(레퍼런스 1267×717 → 디자인 692 기준으로 환산): 바 폭 ≈275, 우측 여백 20, y ≈58.
	var bar_w := 275.0
	var right := vis.x - 20.0
	var y := 58.0
	var track := _spr("laboratory_ui", "scene_laboratory_upgrade_gauge_bg", lab, S)
	if track:
		var tw := float((lab.get("scene_laboratory_upgrade_gauge_bg", {}) as Dictionary).get("w", 200)) * S
		if tw > 0.0:
			track.scale = Vector2(bar_w / tw * S, S)
		track.position = Vector2(right - bar_w * 0.5, y)
		navi.add_child(track)
	# 채움 — 진행도만큼 가로로 자른다(앵커를 왼쪽으로 옮겨 scale.x 로 늘린다).
	_boss_bar_fill = _spr("laboratory_ui", "scene_laboratory_upgrade_gauge_bar", lab, S)
	if _boss_bar_fill:
		_boss_bar_fill.centered = false
		_boss_bar_fill.position = Vector2(right - bar_w, y - 7.0)
		navi.add_child(_boss_bar_fill)
	# 악마 얼굴 — 바 오른쪽 끝. 보스 조우면 icon_boss2_on(강조).
	var enc := int(_params.get("enc", 0))
	var at_boss := (enc + 1) >= total
	var ikey := "scene_adventure_skeleton_fortress_icon_boss%s_on" % ("2" if at_boss else "")
	var icon := _spr("skeleton_fortress", ikey, sf, 0.55 * S)
	if icon:
		icon.position = Vector2(right, y)
		navi.add_child(icon)
		# 원작 펄스 — CCScaleTo(0.1) 3연.
		var base := 0.55 * S
		var pt := icon.create_tween().set_loops()
		pt.tween_property(icon, "scale", Vector2(base - 0.03, base - 0.03), 0.1)
		pt.tween_property(icon, "scale", Vector2(base + 0.03, base + 0.03), 0.1)
		pt.tween_property(icon, "scale", Vector2(base, base), 0.1)
		pt.tween_interval(0.5)
	# "보스" 라벨(원작 9patch/box1) — 바 왼쪽 위.
	var box := NinePatchRect.new()
	var boxp := "res://assets/converted/ninepatch_ui/9patch_box1.tres"
	if ResourceLoader.exists(boxp):
		box.texture = load(boxp)
	box.patch_margin_left = 10; box.patch_margin_right = 10
	box.patch_margin_top = 10; box.patch_margin_bottom = 10
	box.size = Vector2(52, 26)
	box.position = Vector2(right - bar_w, y - 40.0)
	add_child(box)
	var bl := Label.new()
	bl.text = "보스"
	bl.add_theme_font_size_override("font_size", 16)
	bl.add_theme_color_override("font_color", Color(1, 1, 1))
	# box1 은 밝은 패널이라 흰 글씨만으론 안 보인다 — 레퍼런스(승리11_탐험재개.png)의
	# "보스" 도 짙은 테두리가 있다.
	bl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	bl.add_theme_constant_override("outline_size", 4)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bl.size = box.size
	box.add_child(bl)
	# 진행 카운트 `%d/%d`(원작 리터럴) — "보스" 라벨 **오른쪽**에 붙인다.
	# ⚠️ 우측 끝에 두면 속도 버튼(vis.x−90, 74×30)과 겹친다.
	_boss_count = Label.new()
	_boss_count.add_theme_font_size_override("font_size", 15)
	_boss_count.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	_boss_count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_boss_count.add_theme_constant_override("outline_size", 4)
	_boss_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_boss_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_boss_count.size = Vector2(80, 26)
	_boss_count.position = Vector2(box.position.x + box.size.x + 8.0, box.position.y)
	add_child(_boss_count)
	_update_adventure_navi()
	# 등장 — 원작 MoveTo 0.7 (위에서 내려온다).
	navi.position = Vector2(0, -120.0)
	navi.create_tween().tween_property(navi, "position", Vector2.ZERO, 0.7) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func _update_adventure_navi() -> void:
	var total := int((_stage.get("enemies", []) as Array).size())
	if total <= 0:
		return
	# 같은 화면의 목표 라벨(`_build_objective`)이 `enc+1 / total` 로 세므로 여기도 맞춘다 —
	# 한 화면에 1/5 와 2/5 가 같이 뜨면 어느 쪽이 진짜인지 알 수 없다.
	var done := clampi(int(_params.get("enc", 0)) + 1, 0, total)
	if _boss_count:
		_boss_count.text = "%d/%d" % [done, total]
	if is_instance_valid(_boss_bar_fill):
		var lab := _man("laboratory_ui")
		var fw := float((lab.get("scene_laboratory_upgrade_gauge_bar", {}) as Dictionary).get("w", 200))
		if fw > 0.0:
			var ratio := float(done) / float(total)
			_boss_bar_fill.scale = Vector2(275.0 / fw * ratio, Design.ASSET_SCALE)


# ---------- 하단 파티 카드(원작 setInterfaceDragon) ----------
#
# 레퍼런스: `4_전투시작.png`(탐험 시작) · `전투4/5.png`(선택지) · `승리9/10.png`(계속하기)에
# 전부 떠 있고, 배회 애니 중(`배회1~5.png`)에만 사라진다 — 원작 `setAllHideUiButton`/`setAllUiButton`.
# 그리기 = `PartyCardView`(battle.gd 의 애니메이션판과 같은 InterFace.c 규약).
# 숫자 = `PartyStats`(logic) — 전투 카드와 **같은 파이프라인**이라 어긋나지 않는다.
var _party_cards: Array = []

func _show_party_cards() -> void:
	_hide_party_cards()
	var uids: Array = _run_party if not _run_party.is_empty() else _leader_party()
	if uids.is_empty():
		return
	var hp_state: Dictionary = {} if _healed else _params.get("hp_state", {})
	var party := PartyStats.summary(uids, _is_kades(), _field_element_key(), hp_state)
	# 각성 스킬·장비 조건부 효과까지 얹어야 전투 카드와 최대 HP 가 같아진다
	# (`PartyStats.apply_passives` = battle.gd::_apply_awaken_skills 와 **같은 함수**).
	# 적은 **다음 조우 몬스터**를 넣는다 — 원작도 이 단계에서 적을 더미로만 쓰지만
	# 조건부 효과 일부가 적 속성·보스 여부를 보므로 실제 대상과 맞춰야 값이 일치한다.
	PartyStats.apply_passives(party, _next_enemy_ref(), {
		"field_element": _field_element_key(), "enemy_boss": _next_is_boss(),
		"team_buffs": PartyStats.team_buff_names(uids),
		"explore_gold_pct": int(_awaken_explore().get("gold_pct", 0))})
	_party_cards = PartyCardView.build_row(self, self, party, _vis(), _pma)
	# 카드 위 회복 물약 버튼(원작 InterFace::setUiButton) — 레퍼런스 전투4/5.png.
	for i in mini(_party_cards.size(), party.size()):
		_attach_cure_button(_party_cards[i], party[i])


## 카드 1장에 회복 버튼을 단다. 물약 등급은 그 드래곤의 **레벨대**로 고른다
## (`ItemEffect.heal_usable` — data/item_effects.json `heal_potion.tiers`, 위키 §2.2).
func _attach_cure_button(card: Control, pd: Dictionary) -> void:
	if card == null:
		return
	var lv := int(pd.get("level", 1))
	var key := ""
	for t in (Data.item_effects.get("heal_potion", {}).get("tiers", []) as Array):
		var k := String((t as Dictionary).get("key", ""))
		if ItemEffect.heal_usable(Data.item_effects, k, lv):
			key = k
			break
	if key == "":
		return
	var dead := int(pd.get("hp", 1)) <= 0
	PartyCardView.build_cure_button(card, key, UserDB.item_count(key), dead, _pma,
		_use_heal_potion.bind(int(pd.get("uid", 0)), key))


## 회복 물약 사용 — 원작 `InterFace::setRecoverItemHeal`(파티클 skill_29 + effect_skill_29.mp3).
## ⚠️ 회복 결과는 **이번 탐험의 hp_state** 에 얹는다(전투가 그걸 읽어 시작 HP 를 잡는다).
##   원작의 다이아 결제 갈래는 §2-1 로 ⚫CUT — 보유 물약이 없으면 아무 일도 하지 않는다.
func _use_heal_potion(uid: int, key: String) -> void:
	if not UserDB.use_item(key, 1):
		return
	var hp_state: Dictionary = (_params.get("hp_state", {}) as Dictionary).duplicate()
	var uids: Array = _run_party if not _run_party.is_empty() else _leader_party()
	var party := PartyStats.summary(uids, _is_kades(), _field_element_key(), hp_state)
	for pd: Dictionary in party:
		if int(pd.get("uid", 0)) != uid:
			continue
		var hp := int(pd.get("hp", 0))
		var hp_max := int(pd.get("hp_max", 1))
		hp_state[str(uid)] = clampi(hp + ItemEffect.heal_amount(Data.item_effects, hp, hp_max),
			0, hp_max)
		break
	_params["hp_state"] = hp_state
	# 원작 setRecoverItemHeal: 카드 중앙에 particle/scene/adventure/skill_29.plist + 효과음.
	for i in mini(_party_cards.size(), uids.size()):
		if int(uids[i]) != uid:
			continue
		var c: Control = _party_cards[i]
		if is_instance_valid(c):
			CocosParticle.spawn(self, "skill_29", c.position + c.size * 0.5, 132, 0.9)
		break
	Bgm.sfx("effect_skill_29")            # 원작 music/effect_skill_29.mp3
	_show_party_cards()                    # 게이지·수량 갱신


func _hide_party_cards() -> void:
	for c in _party_cards:
		if is_instance_valid(c):
			c.queue_free()
	_party_cards.clear()


## 다음 조우 몬스터의 더미 참조 — `PartyStats.apply_passives` 가 조건 판정에만 쓴다
## (원작도 이 단계에서 적을 att/def=1 더미로만 만든다). 없으면 빈 값 → 조건부 효과 미발동.
func _next_enemy_ref() -> Dictionary:
	var enemies: Array = _stage.get("enemies", [])
	var ei := _rboss_enc if _rboss_enc >= 0 else int(_params.get("enc", 0))
	if ei < 0 or ei >= enemies.size():
		return {"element": "", "hp": 1}
	var e: Dictionary = enemies[ei]
	return {"element": Drops.normalize_element(e.get("element", "")),
		"hp": maxi(1, int(e.get("hp", 1)))}


## 다음 조우가 보스인가 — 목표 라벨·보스 게이지와 같은 판정.
func _next_is_boss() -> bool:
	var total := int((_stage.get("enemies", []) as Array).size())
	return (total > 0 and int(_params.get("enc", 0)) + 1 >= total) or _rboss_enc >= 0


## 카데스 감산 판정에 쓰는 던전 속성 — battle.gd::_field_element 와 같은 규칙.
func _field_element_key() -> String:
	var authored := Drops.normalize_element(_stage.get("field_element", ""))
	if authored == "":
		authored = Drops.normalize_element(_stage.get("element", ""))
	if authored != "" and authored != "none":
		return authored
	var tally: Dictionary = {}
	for e in _stage.get("enemies", []):
		var el := Drops.normalize_element((e as Dictionary).get("element", ""))
		if el == "" or el == "none":
			continue
		tally[el] = int(tally.get(el, 0)) + 1
	var best := ""
	var best_n := 0
	for k in tally:
		if int(tally[k]) > best_n:
			best_n = int(tally[k]); best = String(k)
	return best

## 원작 QuestAndBattleLabel 1:1: 던전 목표 라벨 — quest_shadow 패널 + profile_bg 아이콘 + 텍스트 + 카운트 + checked(완료).
## 근거: QuestAndBattleLabel::initWidget (QuestAndBattleLabel.c:462 CCScale9Sprite 'scene/adventure/quest_shadow.png'
##   capInsets Rect(10,10,4,4) 앵커(0.0,0.5); contentSize(…+300, 60); CCLabelTTF 'Thonburi' 22(:483);
##   common/profile_bg.png @(40,h/2)(:598); common/checked.png @(80,h/2) 완료시(:606); CCLabelBMFont 카운트(:567)).
## ⚠️ 목표 텍스트 문자열=시나리오/미션 서버데이터 유실 → 스테이지명(사용자작성)+조우수로 구성(지어내지 않음). count=조우 진행.
func _build_objective(enc: int, total: int) -> void:
	if total <= 0: return
	var done := (enc + 1) >= total
	const H := 48.0
	var bw := 250.0
	var panel := NinePatchRect.new()   # 원작 quest_shadow Scale9(capInsets 10,10,4,4)
	panel.texture = load("res://assets/converted/adventure_ui/scene_adventure_quest_shadow.tres")
	panel.patch_margin_left = 12; panel.patch_margin_top = 12; panel.patch_margin_right = 12; panel.patch_margin_bottom = 12
	panel.size = Vector2(bw, H); panel.position = Vector2(16, 50)   # 좌상단(앵커 0.0,0.5 → 좌측정렬)
	add_child(panel)
	# profile_bg 아이콘 + quest 아이콘(원작 @x40). 우리 quest 아이콘 세트(icon_quest1) 사용.
	var pbg := _spr("common_ui", "common_profile_bg", _man("common_ui"), 0.5)
	if pbg: pbg.position = Vector2(28, H * 0.5); panel.add_child(pbg)
	var qic := _spr("adventure_ui", "scene_adventure_icon_quest1", _man("adventure_ui"), 0.5)
	if qic: qic.position = Vector2(28, H * 0.5); panel.add_child(qic)
	# checked(원작 @x80, 완료시만).
	if done:
		var chk := _spr("common_ui", "common_checked", _man("common_ui"), 0.6)
		if chk: chk.position = Vector2(28, H * 0.5); panel.add_child(chk)
	# Thonburi 22 목표 텍스트 = 스테이지명(사용자작성) 기반.
	var lbl := Label.new()
	lbl.text = String(_stage.get("name", "던전")) if not done else (String(_stage.get("name", "던전")) + " 완료")
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(1, 0.97, 0.85))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7)); lbl.add_theme_constant_override("outline_size", 3)
	lbl.position = Vector2(56, 4); lbl.size = Vector2(bw - 110, H - 8)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; panel.add_child(lbl)
	# 카운트(원작 CCLabelBMFont setCountNumberIncrease) — 조우 진행 X/Y.
	var cnt := Label.new(); cnt.text = "%d/%d" % [mini(enc + 1, total), total]
	cnt.add_theme_font_size_override("font_size", 20)
	cnt.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	cnt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7)); cnt.add_theme_constant_override("outline_size", 3)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cnt.position = Vector2(bw - 60, 4); cnt.size = Vector2(48, H - 8)
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; panel.add_child(cnt)
	_build_story_objective(H)


## 스토리 서브퀘스트 진행 라벨 — 이 던전이 지금 진행 중인 회차의 서브퀘스트 대상일 때만 뜬다.
## 원작도 같은 `QuestAndBattleLabel` 로 **스토리 퀘스트**를 표시했다(`QuestManager::getQuest` →
## `QuestData::getTitle()` + `getCount()/getMax()`, `AdventureScene::setEventScenario`).
## 우리 첫 줄은 던전 조우 목표(자작)라 스토리 줄은 **그 아래 한 칸**에 같은 프레임으로 얹는다.
func _build_story_objective(h: float) -> void:
	var no := StoryProgress.active_episode()
	var sp := StoryProgress.spec(no)
	var field := DungeonBG.base_field(DungeonBG.field_id(_stage))
	var is_night := bool(UserDB.get_pmeta("yutakan_night", false))
	var variant := {"kades": 1 if _is_kades() else 0}
	if not StoryQuest.counts_for(sp, field, is_night, variant):
		return
	var cur := StoryProgress.count(no)
	var need := int(sp["need"])
	var bw := 250.0
	var panel := NinePatchRect.new()
	panel.texture = load("res://assets/converted/adventure_ui/scene_adventure_quest_shadow.tres")
	panel.patch_margin_left = 12; panel.patch_margin_top = 12
	panel.patch_margin_right = 12; panel.patch_margin_bottom = 12
	panel.size = Vector2(bw, h); panel.position = Vector2(16, 50 + h + 6)
	add_child(panel)
	var pbg := _spr("common_ui", "common_profile_bg", _man("common_ui"), 0.5)
	if pbg: pbg.position = Vector2(28, h * 0.5); panel.add_child(pbg)
	var qic := _spr("adventure_ui", "scene_adventure_icon_quest2", _man("adventure_ui"), 0.5)
	if qic == null:
		qic = _spr("adventure_ui", "scene_adventure_icon_quest1", _man("adventure_ui"), 0.5)
	if qic: qic.position = Vector2(28, h * 0.5); panel.add_child(qic)
	if cur >= need:
		var chk := _spr("common_ui", "common_checked", _man("common_ui"), 0.6)
		if chk: chk.position = Vector2(28, h * 0.5); panel.add_child(chk)
	var lbl := Label.new()
	lbl.text = "%d화 서브미션" % no
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 1))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.position = Vector2(56, 4); lbl.size = Vector2(bw - 110, h - 8)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; panel.add_child(lbl)
	var cnt := Label.new(); cnt.text = "%d/%d" % [mini(cur, need), need]
	cnt.add_theme_font_size_override("font_size", 20)
	cnt.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	cnt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	cnt.add_theme_constant_override("outline_size", 3)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cnt.position = Vector2(bw - 70, 4); cnt.size = Vector2(58, h - 8)
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; panel.add_child(cnt)

## ⚫ 2026-08-01 삭제 — 상단 로드맵(`_build_roadmap`/`_toggle_roadmap`/`_anim_map_item`).
## `AdventureMapLayer` 는 조우 진행 표시가 아니라 **보물찾기(setEventTreasure) 전용 UI** 였다
## (AdventureScene.c:67180 — 그 함수 안에서만 create, tag 0x84). 보물지도 조우를 컷했으므로
## 이 UI 가 뜰 상황 자체가 없다(사용자 지적: 원작에서 보물지도 이벤트 외에는 안 나온다).
## 복원 근거가 생기면 git 이력(2026-07-31 커밋)과 포팅 카드 §5 에서 시작한다.
## 변환 자산(assets/converted/roadmap_ui) · data/roadmap_spots.json 은 그대로 둔다.

func _cycle_speed() -> void:
	_speed = 2.0 if _speed == 1.0 else (3.0 if _speed == 2.0 else 1.0)
	_speed_btn.text = "▶ x%d" % int(_speed)
	if is_instance_valid(_walk_tw):
		_walk_tw.set_speed_scale(_speed)   # 배회 사이클도 같이 가속

# ---------- 진행 ----------
## 배회 시간만 누적한다. **조우 시점은 배회 사이클 끝**(원작도 walk 액션의 마지막 CallFunc 가
## 다음 이벤트를 부른다) — _start_walk_cycle 의 finished 콜백이 _monster_meet 을 호출한다.
func _process(delta: float) -> void:
	if _done or not _walking:
		return
	if _event_open:                        # 이벤트 진행 중 = 보행 정지
		if is_instance_valid(_walk_tw) and _walk_tw.is_running():
			_walk_tw.pause()
		return
	if is_instance_valid(_walk_tw) and not _walk_tw.is_running():
		_walk_tw.play()
	_t += delta * _speed

## 몬스터 조우 연출 — 원작 3단 구성 축자 이식.
##   1. 보스면 `setAlertMonster`(AdventureScene.c:34281-34590) : 검은 막이 맥동하고
##      **보스 컷인 아트**가 우측에서 밀려들어오며 DANGER 스트라이프 2줄이 흐른다(약 3초).
##   2. `showMonsterShadow`(:62000-62077) : `scene/adventure/shadow.png` 지면 그림자를
##      RepeatForever(ScaleTo(1.0, s-0.1) → ScaleTo(1.0, s)) 로 숨쉬게 한다.
##   3. `showMonster`(:61736-62000) : `music/effect_monster_in.mp3` +
##        Spawn(ScaleTo(0.3,1.2),  MoveBy(0.3,(0,+130)))       ← 위로 튀어오르며 커짐
##        Spawn(ScaleTo(0.15,0.8), MoveBy(0.15,(0,-120)), ScaleTo(0.15,(0.9,0.8)))  ← 급강하+찌그러짐
##        CallFuncN → **setAllViewShake**(Shake 액션)          ← 착지 순간 화면 흔들림
##        Spawn(ScaleTo(0.2,1.0),  MoveBy(0.2,(0,+20)))        ← 반동 복귀
##      (Cocos y-up → Godot y-down 이라 y 부호를 반전했다. 순 이동 = 시작점보다 30px 위)
##
## 🔴 이전 구현(실루엣이 작게 등장 → 커지며 밝아짐)은 **원작에 없는 자작 연출**이었다.
##    원작의 실루엣 조우는 별개 이벤트(`setIsMonsterShadowMode` / `setMonsterShadowMeet` +
##    `txt_shadow_kr.png` + `ShadowMonsterLayer`)이고, 일반/보스 조우는 위 점프-착지다.
func _monster_meet() -> void:
	var vis := _vis()
	var mid := _enemy_id_for_enc()
	var total := int((_stage.get("enemies", []) as Array).size())
	var enc := int(_params.get("enc", 0))
	var is_boss := (total > 0 and enc + 1 >= total) or _rboss_enc >= 0   # 랜덤보스=보스취급
	# 보행 정지 — 전진하던 배경 사본을 정리한다.
	_walking = false
	if is_instance_valid(_walk_tw): _walk_tw.kill()
	if is_instance_valid(_walk_layer):
		var wl := _walk_layer
		var wt := wl.create_tween()
		wt.tween_property(wl, "modulate:a", 0.0, 0.2)
		wt.tween_callback(wl.queue_free)
		_walk_layer = null
	# 원작 조우 서사(레퍼런스 docs/ref/orig_image/battle/몬스터싸움.png 하단).
	var enemies: Array = _stage.get("enemies", [])
	var ei := _rboss_enc if _rboss_enc >= 0 else enc
	var mn := "몬스터"
	if ei >= 0 and ei < enemies.size():
		mn = String((enemies[ei] as Dictionary).get("name", "몬스터"))
	_narrate("길을 잃고 헤매던 중 %s의 으슥한 곳에서\n%s%s 만났다."
		% [String(_stage.get("name", "던전")), mn, _josa(mn, "을", "를")])
	# 0) 조우 도착 연출(원작 `incomeMonster(bool)` @00c336c4) — 화면 전체 플래시 + 상단 파티클 + BGM 전환.
	_income_monster(is_boss)
	# 1) 보스 컷인 경고(원작 setAlertMonster). 일반 조우에는 없다.
	var delay := 0.0
	if is_boss:
		_alert_monster(mid)
		delay = 3.0 / maxf(_speed, 1.0)
	# 2)+3) 그림자 → 점프 착지
	get_tree().create_timer(delay).timeout.connect(
		_show_monster.bind(mid, is_boss, vis))

## 원작 `AdventureScene::incomeMonster(bool)` @00c336c4 — **몬스터가 페이드인하는 게 아니라
## 화면 전체가 번쩍인다.** 레퍼런스 `docs/ref/adventure/전투1~3.png` 에서 몬스터가 점점 진해지는
## 것처럼 보이던 건 이 **흰 오버레이가 걷히는** 것이었다(배경까지 같이 희끄무레하다).
##
## 원작 리터럴 그대로:
##   · BGM — 보스면 `music/bg_battle_boss.mp3`, 아니면 `music/bg_colosseum_battle_2.mp3`
##   · 파티클 `particle/scene/adventure/pt_monster_income_1.plist` 을 배경 레이어(tag 1) z=999999,
##     `VisibleRect::top()`(화면 상단 중앙)에
##   · 전체 화면 `CCLayerColor` z=999999 —
##       일반(false): ccColor4B(234,234,234,**100**) → FadeTo(0.2,200) → FadeOut(0.7)
##       보스(true) : ccColor4B(204, 61, 61,  **0**) → Delay(0.3) → FadeTo(0.2,255) → FadeOut(0.7)
##
## `alert` 인자는 원작 `setEventMonster` 의 `bVar3` =
## `isBoss && !(dungeonMode || raidMode || scenarioBattleMode || darknixMode)` — **일반 필드 보스**.
func _income_monster(alert: bool) -> void:
	var vis := _vis()
	# 화면 전체 플래시.
	var flash := ColorRect.new()
	flash.color = Color8(204, 61, 61, 0) if alert else Color8(234, 234, 234, 100)
	flash.size = vis
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 200
	add_child(flash)
	var t := flash.create_tween()
	if alert:
		t.tween_interval(0.3)
		t.tween_property(flash, "color:a", 1.0, 0.2)
	else:
		t.tween_property(flash, "color:a", 200.0 / 255.0, 0.2)
	t.tween_property(flash, "color:a", 0.0, 0.7)
	t.tween_callback(flash.queue_free)        # 원작 finishImpact = 오버레이 제거
	# 상단 파티클 — 원작 VisibleRect::top().
	CocosParticle.spawn(self, "pt_monster_income_1", Vector2(vis.x * 0.5, 0.0), 199, 0.6)
	# BGM 전환.
	Bgm.play("bg_battle_boss" if alert else "bg_colosseum_battle_2")


## 원작 showMonsterShadow + showMonster. 착지 후 setAllViewShake → 전투 전환.
func _show_monster(mid: int, is_boss: bool, vis: Vector2) -> void:
	if not is_inside_tree():
		return
	var meet := Node2D.new(); add_child(meet)
	var cx := vis.x * 0.5
	var cy := FLOOR * 0.56
	var full := Vector2(0.75, 0.75) * (1.3 if is_boss else 1.0)
	var mscn := "res://scenes/monsters/monster_%d.tscn" % mid
	var mnode: Node2D = null
	if ResourceLoader.exists(mscn):
		mnode = (load(mscn) as PackedScene).instantiate()
		var ap := mnode.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.has_animation("wait"): ap.play("wait")
	else:
		mnode = _spr("adventure_ui", "scene_adventure_shadow", _adv, 2.0)
	if mnode == null:
		_show_battle_ready(is_boss); return
	# ── showMonsterShadow: 지면 그림자 + 숨쉬는 스케일 루프
	var sbase := 1.5 * (1.3 if is_boss else 1.0)
	var sh := _spr("adventure_ui", "scene_adventure_shadow", _adv, sbase)
	if sh:
		sh.position = Vector2(cx, cy + 96.0)
		meet.add_child(sh)
		var st := sh.create_tween().set_loops()
		st.tween_property(sh, "scale", Vector2(sbase - 0.1, sbase - 0.1), 1.0)
		st.tween_property(sh, "scale", Vector2(sbase, sbase), 1.0)
	# ── showMonster: 아래에서 튀어올라 착지
	meet.add_child(mnode)
	var p0 := Vector2(cx, cy + 30.0)          # 순 이동 +30(위) 를 상쇄한 시작점
	mnode.position = p0
	mnode.scale = full
	Bgm.sfx("effect_monster_in")              # 원작 music/effect_monster_in.mp3
	var t := meet.create_tween()
	t.tween_property(mnode, "scale", full * 1.2, 0.3)
	t.parallel().tween_property(mnode, "position", p0 + Vector2(0, -130.0), 0.3)
	t.tween_property(mnode, "scale", Vector2(full.x * 0.9, full.y * 0.8), 0.15)
	t.parallel().tween_property(mnode, "position", p0 + Vector2(0, -10.0), 0.15)
	t.tween_callback(func():                  # setAllViewShake + 착지 파티클
		_arrive_impact(cx, cy, is_boss))
	t.tween_property(mnode, "scale", full, 0.2)
	t.parallel().tween_property(mnode, "position", p0 + Vector2(0, -30.0), 0.2)
	t.tween_interval(0.55)
	# 원작은 몬스터가 착지한 **뒤** `setReadyFight`(0x17) → `setBattleReady` 로 선택지를 띄운다.
	# 전투는 '싸운다'를 눌러야 시작된다(포팅 카드 AdventureEventFlow.md §2).
	t.tween_callback(_show_battle_ready.bind(is_boss))

# ---------- 조우 전 선택지 — 원작 setBattleReady ----------
#
# 원작 구성(재디컴프 리터럴 그대로):
#   좌: `scene/adventure/btn2.png`(초록, 262×94) + `choice_fight_%s.png`   tag 0xbbe → onClickFight
#   우: `scene/adventure/btn1.png`(붉은)        + `choice_run_%s.png`      tag 0xbbf → onClickRun
#       (해골요새 = `getIsDungeonMode()` 면 `choice_giveup_%s.png` '포기한다')
#   등장: `CCMoveTo(0.5)` + `CCEaseExponentialInOut` — 화면 밖에서 밀려 들어온다.
#
# 단일 버튼(도망 불가)은 **영웅 난이도 + hard-auto 부스트 결제**일 때뿐이라 ⚫CUT →
# 우리는 항상 두 버튼(판정 = `AdventureRun.offers_escape`).
const _READY_BTN := Vector2(262.0, 94.0)      # scene/adventure/btn1|btn2 실측
var _ready_layer: CanvasLayer

func _show_battle_ready(is_boss: bool) -> void:
	if _done_battle_ready:
		return
	_done_battle_ready = true
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var w := _READY_BTN.x * S
	# 원작 배치(setBattleReady/setRetryButton 공통): Cocos 좌표로 y = **화면높이*0.5 + 20**,
	# x = 중앙 ∓ (버튼폭*0.5 + 50). Cocos 는 원점이 좌하단이므로 y 를 뒤집으면
	#   godot_y = visH - (visH*0.5 + 20) = visH*0.5 - 20   → 화면 47% 지점(하단 텍스트박스 위).
	# ⚠️ 2026-07-31 수정: 처음엔 `local_12c` 를 버튼 높이로 읽어 하단에 붙였는데, 그러면
	#   하단 전폭 텍스트박스를 덮는다. 레퍼런스(docs/ref/orig_image/battle/전리품드랍후.png)의
	#   버튼은 화면 46~47% 지점이라 `local_12c` = **가시영역 높이**가 맞다.
	var y := vis.y * 0.5 - 20.0
	_ready_layer = CanvasLayer.new(); _ready_layer.layer = 60
	add_child(_ready_layer)
	# 좌 = 도망간다/포기한다(btn1 붉은) · 우 = 싸운다(btn2 초록).
	# ⚠️ 2026-07-31 정정 — 종전 주석("setBattleReady 는 setRetryButton 과 반대")은 **오독**이었다.
	#   재디컴프한 setBattleReady(@00c57170) 를 변수까지 따라가면 둘은 같은 배치다:
	#     pCVar24 = btn2 + choice_fight_%s + setTag(0xbbe) → MoveTo(0.5, aCStack_198)
	#               aCStack_198 = (centerX + btnW*0.5 + 50, …)  ⇒ **우측**
	#               시작점 aCStack_1f0 = (centerX + btnW + 50, …) = 화면 밖 오른쪽
	#     pCVar25 = btn1 + choice_run_%s/choice_giveup_%s + setTag(0xbbf) → MoveTo(0.5, aCStack_1a0)
	#               aCStack_1a0 = (centerX − btnW*0.5 − 50, …)  ⇒ **좌측**
	#               시작점 aCStack_190 = (−50 − btnW, …) = 화면 밖 왼쪽
	#   레퍼런스 `docs/ref/adventure/전투5.png` 도 좌=주황 '도망간다' / 우=초록 '싸 운 다' 이고,
	#   `승리10.png`(그만하기/계속하기)와도 같은 방향이다 — 붉은 좌, 초록 우로 일관된다.
	_ready_button("scene_adventure_btn1", AdventureRun.escape_frame(_is_fortress()),
		Vector2(vis.x * 0.5 - (w * 0.5 + 50.0), y), Vector2(-w - 60.0, y),
		_on_choice_run.bind(is_boss))
	_ready_button("scene_adventure_btn2", "scene_adventure_choice_fight_KR",
		Vector2(vis.x * 0.5 + (w * 0.5 + 50.0), y), Vector2(vis.x + w + 60.0, y), _on_choice_fight)
	# 원작 문자열 `<AdventureMonster2>` 전문(2줄) — DV2/string/stringsData_KR.xml.
	_narrate("어떻게 하시겠습니까?\n몬스터의 능력치를 잘 보고 결정하세요.")
	_show_party_cards()

var _done_battle_ready := false

## 버튼 1개 — 배경 프레임 + 라벨 프레임을 얹고 화면 밖(from)에서 목표(to)로 0.5초 슬라이드.
func _ready_button(bg_key: String, label_key: String, to: Vector2, from: Vector2,
		cb: Callable) -> void:
	var S := Design.ASSET_SCALE
	var holder := Node2D.new()
	holder.position = from
	# 최종 배치 x — 좌우 배정을 검증(test_adventure_screen.gd)할 수 있게 남긴다.
	holder.set_meta("target_x", to.x)
	_ready_layer.add_child(holder)
	var bg := _spr("adventure_ui", bg_key, _adv, S)
	if bg:
		holder.add_child(bg)
	var lb := _spr("adventure_ui", label_key, _adv, S)
	if lb:
		holder.add_child(lb)
	var hit := Button.new()
	hit.flat = true
	hit.size = _READY_BTN * S
	hit.position = -_READY_BTN * S * 0.5
	hit.pressed.connect(cb)
	holder.add_child(hit)
	# 원작 CCMoveTo(0.5) + CCEaseExponentialInOut.
	var tw := holder.create_tween()
	tw.tween_property(holder, "position", to, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)

func _clear_battle_ready() -> void:
	if is_instance_valid(_ready_layer):
		_ready_layer.queue_free()
	_ready_layer = null

## 원작 onClickFight — 그대로 전투로.
func _on_choice_fight() -> void:
	_clear_battle_ready()
	_go_battle()

## 원작 onClickRun(→ setEventRun 0x9). 성공하면 전투 없이 이번 조우를 넘기고,
## 실패하면 그대로 싸운다. 성공률은 서버 소유였다 → `data/adventure_events.json` `run`(자작).
func _on_choice_run(is_boss: bool) -> void:
	_clear_battle_ready()
	var r := _event_rng("run")
	if not AdventureRun.run_succeeds(Data.adventure_events, is_boss, r):
		_narrate("도망치지 못했다!")
		get_tree().create_timer(1.0).timeout.connect(_go_battle)
		return
	# 도망 성공 = 탐험 종료(월드맵 복귀). 원작 setEventRun 도 런을 끝낸다.
	_narrate("무사히 도망쳤다.")
	get_tree().create_timer(1.2).timeout.connect(func():
		if is_instance_valid(self):
			Scenes.goto("worldmap", {"region": _params.get("region", "yutakan")}))

## 원작 AdventureMapLayer setShakeMap+setArriveParticle: 몬스터 리빌 순간 화면 흔들림 + 도착 파티클.
func _arrive_impact(x: float, y: float, is_boss: bool) -> void:
	_map_shake(9.0 if is_boss else 5.0)
	var burst := CPUParticles2D.new()
	burst.position = Vector2(x, y)
	burst.one_shot = true; burst.explosiveness = 1.0
	burst.amount = 20 if is_boss else 12
	burst.lifetime = 0.5
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 14.0
	burst.direction = Vector2(0, -1); burst.spread = 180.0
	burst.initial_velocity_min = 90.0; burst.initial_velocity_max = 210.0
	burst.gravity = Vector2(0, 320.0)
	burst.scale_amount_min = 2.0; burst.scale_amount_max = 4.5
	var g := Gradient.new()
	var c: Color = Color(1.0, 0.45, 0.25) if is_boss else Color(1.0, 0.92, 0.6)
	g.set_color(0, Color(c.r, c.g, c.b, 0.9)); g.set_color(1, Color(c.r, c.g, c.b, 0.0))
	burst.color_ramp = g
	burst.z_index = 30
	add_child(burst)
	burst.emitting = true
	get_tree().create_timer(1.0).timeout.connect(func(): if is_instance_valid(burst): burst.queue_free())

## 화면 흔들림(원작 AdventureMapLayer::setShakeMap = Shake(0.5s,10)). 보행 카메라(_cam)를 지터.
var _shake_tw: Tween
func _map_shake(intensity: float) -> void:
	if not is_instance_valid(_cam):
		_cam = Camera2D.new()
		_cam.position = _vis() * 0.5
		add_child(_cam); _cam.make_current()
	if is_instance_valid(_shake_tw): _shake_tw.kill()
	_shake_tw = _cam.create_tween()
	var amt := intensity
	for i in 6:
		_shake_tw.tween_property(_cam, "offset", Vector2(randf_range(-amt, amt), randf_range(-amt, amt)), 0.03)
		amt *= 0.68
	_shake_tw.tween_property(_cam, "offset", Vector2.ZERO, 0.05)

## 원작 `AdventureScene::setAlertMonster`(AdventureScene.c:34281-34590) 축자 이식 — **보스 컷인 경고**.
##
## 🔴 이전 구현은 이 함수를 "가로 띠가 0.22초 스윕하고 사라짐"으로 오해했다. 실제 구성은:
##   · `CCLayerColor(검정, w+200, h+200)` @ (-100,-100), z=100, tag 0x9b
##     → FadeTo(0.5, **150**) 후 RepeatForever(FadeTo(0.5,150) ↔ FadeTo(0.5,**50**))  = 맥동하는 암막
##   · `Monster::getImagePathBossCutin()` = **`monster/<id>/<id>_image/cutin.png`**
##     (:34370-34392) 를 앵커(0.5,0.5)·scale 2S 로 화면 중앙 + (w+100, 100) 에 두고
##     MoveBy(0.5, (-w, 0)) + **CCEaseExponentialOut** 으로 밀어 넣는다
##     → `asset_index.py --grep cutin` = 78장 전부 🟠 미사용이던 자산. 여기서 처음 쓴다.
##   · `scene/adventure/bar.png` 2줄(위=flipX, 아래=정방향), 각각
##       - `bar_deco_right/left_move.png` 를 **200장 타일링**해 MoveBy(9.0, ±w) → 느린 무한 스크롤 띠
##       - `txt_danger.png`(scale 0.5S) 를 **10장 반복**해 MoveBy(4.5, ±2w) → DANGER 문자열 흐름
##   · 하단 텍스트박스(tag 7)는 MoveTo(0.5, (w/2, -h/2)) 로 화면 아래로 빠진다
##   · 총 길이 = Delay(3.0) → CallFunc (그 뒤 setAlertMonsterShowEnd)
##
## 타일 200장/10장은 화면 밖까지 채우기 위한 수치다 — 우리는 화면폭에 필요한 만큼만 깐다(가시결과 동일).
func _alert_monster(mid: int) -> void:
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var lay := CanvasLayer.new(); lay.layer = 30; add_child(lay)
	var root := Node2D.new(); lay.add_child(root)
	# ── 맥동하는 암막(CCLayerColor 검정, alpha 150↔50)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)
	dim.position = Vector2(-100, -100)
	dim.size = vis + Vector2(200, 200)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lay.add_child(dim)
	lay.move_child(dim, 0)
	var dt := dim.create_tween()
	dt.tween_property(dim, "color:a", 150.0 / 255.0, 0.5)
	var dl := dim.create_tween().set_loops()
	dl.tween_interval(0.5)
	dl.tween_property(dim, "color:a", 50.0 / 255.0, 0.5)
	dl.tween_property(dim, "color:a", 150.0 / 255.0, 0.5)
	# ── 하단 텍스트박스 퇴장(원작: getChildByTag(7) → MoveTo(0.5, (w*0.5, -h*0.5)))
	var narr_par: Node = _narr_label.get_parent() if is_instance_valid(_narr_label) else null
	var narr_home := Vector2.ZERO
	if narr_par is Control:
		narr_home = (narr_par as Control).position
		(narr_par as Control).create_tween().tween_property(narr_par, "position:y", vis.y + 40.0, 0.5)
	# ── 보스 컷인(우측 화면 밖 → 중앙, EaseExponentialOut). 스케일 2S(원작 vtable 0x78 인자 = S+S).
	#    컷인 원본은 가로로 긴 띠다(예: monster_5 = 354×74) → 2S 로 그리면 화면폭을 거의 채운다.
	var cp := "res://assets/converted/monster_%d/monster_%d_%d_image_cutin.tres" % [mid, mid, mid]
	var cut_h := 74.0 * S * 2.0        # 컷인이 없을 때의 기본 띠 높이
	if ResourceLoader.exists(cp):
		var cut := Sprite2D.new()
		cut.texture = load(cp)
		cut.material = _pma
		cut.scale = Vector2(S * 2.0, S * 2.0)
		cut.z_index = 10
		cut.position = Vector2(vis.x * 1.5, vis.y * 0.5)
		root.add_child(cut)
		var ch := cut.texture.get_size().y
		if ch > 1.0:
			cut_h = ch * S * 2.0
		cut.create_tween().tween_property(cut, "position:x", vis.x * 0.5, 0.5)\
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	# ── DANGER 스트라이프 2줄 — 원작은 바를 `center ± 컷인높이×S`에 둬서 **컷인을 위아래로 감싼다**
	#    (:34406 `getContentSize(this_01).height * (S+S) * 0.5`, this_01 = 컷인 스프라이트).
	var bar_h := float(_adv.get("scene_adventure_bar", {}).get("h", 23)) * S
	for i in 2:
		var bar := _spr("adventure_ui", "scene_adventure_bar", _adv, S)
		if bar == null: continue
		bar.flip_h = (i == 0)                                   # 원작: 위쪽 바만 flipX(1)
		bar.position = Vector2(vis.x * 0.5,
			vis.y * 0.5 + (-cut_h * 0.5 if i == 0 else cut_h * 0.5))
		bar.z_index = 15                                        # 컷인 위에 겹친다
		root.add_child(bar)
		var dir := 1.0 if i == 0 else -1.0
		_alert_scroll(bar, "scene_adventure_bar_deco_%s_move" % ("right" if i == 0 else "left"),
			S, 0.0, dir * vis.x, 9.0, vis.x)
		# DANGER 문자열은 바 **바깥쪽**으로(위 바는 위, 아래 바는 아래) 흐른다.
		_alert_scroll(bar, "scene_adventure_txt_danger",
			S * 0.5, (-bar_h * 0.5 - 26.0) if i == 0 else (bar_h * 0.5 + 26.0),
			dir * vis.x * 2.0, 4.5, vis.x)
	# ── 3초 뒤 정리(원작 Delay(3.0) → setAlertMonsterShowEnd)
	var life := 3.0 / maxf(_speed, 1.0)
	get_tree().create_timer(life).timeout.connect(func() -> void:
		if is_instance_valid(narr_par) and narr_par is Control:
			(narr_par as Control).create_tween().tween_property(narr_par, "position", narr_home, 0.3)
		if is_instance_valid(lay):
			var ft := dim.create_tween()
			ft.tween_property(root, "modulate:a", 0.0, 0.25)
			ft.parallel().tween_property(dim, "color:a", 0.0, 0.25)
			ft.tween_callback(lay.queue_free))

## 바 하나에 프레임을 화면폭+여유만큼 타일링해 붙이고 통째로 흘려보낸다(원작 200장/10장 타일링 대응).
func _alert_scroll(bar: Sprite2D, key: String, scale: float, y: float,
		travel: float, dur: float, screen_w: float) -> void:
	var e: Dictionary = _adv.get(key, {})
	var w := float(e.get("w", 0)) * scale
	if w <= 1.0:
		return
	var n := int(ceil((screen_w * 2.0 + absf(travel)) / w)) + 1
	var strip := Node2D.new()
	strip.position = Vector2(0, y)
	bar.add_child(strip)
	var x0 := -screen_w - (w if travel > 0.0 else 0.0)
	for i in n:
		var s := _spr("adventure_ui", key, _adv, scale)
		if s == null:
			strip.queue_free(); return
		# bar 스프라이트의 scale 을 상속하므로 로컬 좌표는 bar 픽셀 공간이다.
		s.scale /= bar.scale.x
		s.position = Vector2((x0 + w * i) / bar.scale.x, 0)
		strip.add_child(s)
	var tw := strip.create_tween().set_loops()
	tw.tween_property(strip, "position:x", travel / bar.scale.x, dur).from(0.0)

func _go_battle() -> void:
	var hp_state: Dictionary = {} if _healed else _params.get("hp_state", {})
	# 랜덤 보스면 선택된 보스 enc를 전달(meet↔battle 일치). 아니면 일반 enc.
	var enc := _rboss_enc if _rboss_enc >= 0 else int(_params.get("enc", 0))
	# 원작 setEventMonster: 비보스 조우 ~10%가 정예(스탯↑·금빛·보상2배).
	var total := int((_stage.get("enemies", []) as Array).size())
	var is_boss := (total > 0 and enc + 1 >= total) or _rboss_enc >= 0
	var elite := false
	if not is_boss:
		var er := RandomNumberGenerator.new(); er.seed = hash("elite_%s_%d" % [String(_params.get("stage", "")), enc])
		elite = er.randf() < 0.10
	Scenes.goto("battle", {"stage": String(_params.get("stage", "")),
		"region": _params.get("region", "yutakan"), "enc": enc, "elite": elite,
		"hp_state": hp_state, "streak": int(_params.get("streak", 0)),
		# 이번 탐험의 출전 인원 — 일반은 리더 1마리, 3인 단계는 편성 결과.
		# 전투가 전역 UserDB.party() 를 다시 읽으면 1인 탐험에서도 3마리가 나온다.
		# 카데스의 공간 여부는 스테이지 id(601+)로 이미 정해지지만, 전투가 다시 계산하지 않도록
		# 명시해서 넘긴다(아티팩트 드롭·미각성 페널티가 여기에 걸린다).
		"kades": _is_kades(), "field": _base_field(),
		# 밤 변형 여부도 넘긴다 — 드랍 풀이 일반/영웅/밤으로 나뉜다(Drops.mode_of).
		"night": bool(_params.get("night", false)),
		"run_seed": int(_params.get("run_seed", 0)),
		"party_uids": _run_party.duplicate(), "hero": bool(_params.get("hero", false))})

## 편성에서 `weight`(기본 1) 비례로 하나를 고른다. 합이 0 이면 균등.
func _pick_weighted(rows: Array, rr: RandomNumberGenerator) -> int:
	var total := 0.0
	for r in rows:
		total += maxf(0.0, float((r as Dictionary).get("weight", 1)))
	if total <= 0.0:
		return rr.randi() % rows.size()
	var t := rr.randf() * total
	for i in rows.size():
		t -= maxf(0.0, float((rows[i] as Dictionary).get("weight", 1)))
		if t <= 0.0:
			return i
	return rows.size() - 1

## 현 조우(enc)의 몬스터 asset id. 랜덤 보스면 선택된 보스, 아니면 stage.enemies[enc].id.
func _enemy_id_for_enc() -> int:
	var enemies: Array = _stage.get("enemies", [])
	if enemies.is_empty(): return 1
	var enc := _rboss_enc if _rboss_enc >= 0 else clampi(int(_params.get("enc", 0)), 0, enemies.size() - 1)
	var e: Dictionary = enemies[enc]
	var eid: Variant = e.get("id", 1)
	return int(eid) if eid != null else 1

## 원작 BattleTextBox 1:1: 하단 대화상자 — dialogue_box 9patch + 타자기 텍스트 + next 화살표 + 탭 진행.
## 근거: BattleTextBox::init (BattleTextBox.c:170 CCScale9Sprite '9patch/dialogue_box.png' capInsets Rect(10,10,4,4);
##   this 앵커(0.5,0.0)+VisibleRect::bottom 하단중앙; contentSize(visW-10, 120); CCLabelTTF "Thonburi" 28 좌측정렬(:187-191);
##   setDimensions(boxW-20) 워드랩(:195); dialogue_box 자식 앵커(0.0,0.5) pos(10, h*0.5-2)(:170-55)).
##   타자기: setTextSpeed/showString/showStringAll/schedule(문자 순차노출); showNextArrow/removeNextArrow(btn_arrow2);
##   ccTouchBegan(BattleTextBox.c:38): 타이핑중=전체표시(showStringAll), 완료=다음(on_done).
## ⚠️ 문자노출 속도(cps)는 연출용 클라 설정 — 정확값 미확정 → 기본 40cps ASSUMPTION(게임수치 아님, 코스메틱).
func _open_dialogue(text: String, on_done := Callable()) -> void:
	var vis := _vis()
	var layer := CanvasLayer.new(); layer.layer = 80; add_child(layer)
	const BH := 120.0
	var bw: float = vis.x - 20.0
	var box := NinePatchRect.new()
	box.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres")
	box.patch_margin_left = 16; box.patch_margin_top = 16; box.patch_margin_right = 16; box.patch_margin_bottom = 16
	box.size = Vector2(bw, BH); box.position = Vector2(10, vis.y - BH - 12)   # 하단중앙(원작 bottom 앵커)
	layer.add_child(box)
	# Thonburi 28 좌측정렬 라벨 + 워드랩(boxW-20). 우리 폰트로 대체(비트맵 폰트 미적용).
	var lbl := Label.new(); lbl.text = text
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", Color(0.15, 0.1, 0.03))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.position = Vector2(14, 12); lbl.size = Vector2(bw - 28, BH - 24)
	lbl.visible_characters = 0   # 타자기 시작
	box.add_child(lbl)
	# next 화살표(btn_arrow2) — 완료 시 우하단에 점멸. 원작 showNextArrow.
	var arrow := _spr("common_ui", "common_btn_arrow2", _man("common_ui"), 0.8)
	if arrow:
		arrow.position = Vector2(bw - 26, BH - 22); arrow.visible = false; box.add_child(arrow)
	# 타자기: 40cps로 visible_characters 증가(ASSUMPTION 속도). 완료 시 화살표 표시.
	var total := text.length()
	var done := {"v": false}
	var timer := Timer.new(); timer.wait_time = 1.0 / 40.0; timer.one_shot = false
	layer.add_child(timer)
	var reveal_all := func() -> void:
		lbl.visible_characters = -1; done["v"] = true
		if timer and is_instance_valid(timer): timer.stop()
		if arrow:
			arrow.visible = true
			var tw := arrow.create_tween().set_loops()
			tw.tween_property(arrow, "position:y", BH - 16, 0.4).as_relative()
			tw.tween_property(arrow, "position:y", BH - 22, 0.4)
	timer.timeout.connect(func() -> void:
		lbl.visible_characters += 1
		if lbl.visible_characters >= total: reveal_all.call())
	timer.start()
	# 탭 진행(원작 ccTouchBegan): 타이핑중=전체표시, 완료=on_done+닫기.
	var catcher := Control.new(); catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			if not done["v"]:
				reveal_all.call()
			else:
				if is_instance_valid(layer): layer.queue_free()
				if on_done.is_valid(): on_done.call())
	layer.add_child(catcher)

# ---------- 헬퍼 ----------
func _vis() -> Vector2:
	return get_viewport_rect().size

func _man(dir: String) -> Dictionary:
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func _spr(dir: String, name: String, man: Dictionary, scale := 1.0) -> Sprite2D:
	var p := "res://assets/converted/%s/%s.tres" % [dir, name]
	if not ResourceLoader.exists(p):
		return null
	var s := Sprite2D.new()
	s.texture = load(p)
	s.material = _pma
	# 회전 보정 불필요 — 변환 단계가 흡수(scripts/tools/fix_rotated_frames.py)
	s.scale = Vector2(scale, scale)
	return s

func _portrait(id: int, stage: String, scale := 1.0) -> Sprite2D:
	var dir := "portrait_%d" % id
	return _spr(dir, "dragon_dragon_%d_box_%s" % [id, stage], _man(dir), scale)

## NPC 대사 조회 — data/npc_lines.json { "<npc>": { "<상황>": "대사" } }.
## 파일이 없거나 키가 없으면 fallback(임시 문구)을 그대로 쓴다. 문장을 지어내지 않는다.
var _npc_lines_cache: Dictionary = {}
var _npc_lines_loaded := false
func _npc_line(npc: String, situation: String, fallback: String) -> String:
	if not _npc_lines_loaded:
		_npc_lines_loaded = true
		var f := FileAccess.open("res://data/npc_lines.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary: _npc_lines_cache = d
	var byn: Dictionary = _npc_lines_cache.get(npc, {})
	var v = byn.get(situation, "")
	return String(v) if typeof(v) == TYPE_STRING and String(v) != "" else fallback
