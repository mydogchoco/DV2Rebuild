extends Control
## Battle(전투) 씬 — 파티(하단 카드 1~3) vs 중앙 대형 적. render 층. (CLAUDE.md §10)
## 레퍼런스: docs/Ref/battle1.png·battle3.png (PvE 어드벤처 전투. 대칭 3v3 레시피는 컷된 PvP용→미사용).
## 로직: Battle.simulate(party_a,party_b,rng,cfg,skills_db) → {winner,events,rounds}.
##   render는 events를 타이밍 재생(§10.3): HP드레인·데미지숫자·crit/miss/block·공격큐·사망·DoT·승패.
## 좌표: 692 고정높이(design.gd). 전환은 Scenes.goto()만(§10.4).
##
## ⚠️ 적 스탯·스테이지 구성은 원작 서버데이터라 유실 → 자작(ASSUMPTION). data/stages 신설 예정.
##    파티 스킬은 UserDB에 스킬 필드가 아직 없음 → 현재 평타 위주(스킬↔드래곤 연결 시 스킬연출 자동 활성).

const FLOOR := 692.0   # = Design.DESIGN_HEIGHT

var _pma: CanvasItemMaterial
var _adv: Dictionary = {}
var _bat: Dictionary = {}
var _portrait_man: Dictionary = {}
var _params: Dictionary = {}
var _enemy: Dictionary = {}
var _party: Array = []                    # [{id,level,name,element,uid,stats}]
var _drink_users: Array = []              # 이번 전투에 드링크 버프가 걸려 있던 uid(종료 시 턴 차감)
## 이번 전투에서 레벨이 오른 드래곤들 → `LevelUpResult` 모달 입력.
## 탐험이 이어지면 `Scenes.goto("adventure", {"levelups": …})` 로 넘겨 **탐험 쪽에서** 띄우고,
## 던전이 끝나면 결과 화면에서 바로 띄운다. (원작에는 창이 없었다 — levelup_result.gd 헤더 참조)
var _levelup_queue: Array = []

# 재생 상태
var _views: Dictionary = {}               # 내부이름(A0/E0) -> view dict
var _events: Array = []
var _winner := ""
var _speed := 1.0
var _skip := false
var _playing := false
var _finished := false
var _log_label: Label
var _speed_btn: Button
var _speed_spr: Sprite2D   # 속도 버튼 원작 이미지(speed_0/1/2 전환)

func enter(params: Dictionary = {}) -> void:
	_params = params
	if _pma != null:
		_rebuild()

func _ready() -> void:
	_pma = CanvasItemMaterial.new()
	_pma.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_adv = _man("adventure_ui")
	_bat = _man("battle_ui")
	_rebuild()

func _rebuild() -> void:
	_gen += 1        # 진행 중이던 재생 코루틴 무효화(아래 _play_events 참조)
	for c in get_children():
		c.queue_free()
	_views.clear()
	_events.clear()
	_winner = ""
	_skip = false
	_setup_enemy()
	_setup_party()
	# 원작 AdventureScene: 일반몹=bg_colosseum_battle_2, 보스(Monster::isBoss)=bg_battle_boss.
	# 근거: docs/ref/orig_code/decomp/AdventureScene.c:16317-16333 (SoundManager::playBackground).
	Bgm.play("bg_battle_boss" if _is_boss() else "bg_colosseum_battle_2")
	_build_bg()
	_build_enemy()
	_build_enemy_hpbar()
	_build_party_cards()
	# 원작 setCheckFieldBuffToUi: 필드 속성과 같은 속성의 드래곤 **카드**에 붙는다 → 카드 생성 뒤.
	_build_field_buff()
	_build_textbox()
	_build_hud()
	_maybe_team_buff_intro()    # 원작 AdventureScene::setCheckTeamBuff — 조합 연출 뒤 전투 시작

# ---------- 데이터 조립 ----------
func _setup_enemy() -> void:
	# 스테이지 데이터(data/stages.json, 사용자 작성)가 있으면 그걸로 구성. 없으면 params.enemy 또는 스텁.
	var st: Dictionary = _stage_rec()
	if st.get("bg") != null and not _params.has("bg"):   # bg=null(미매칭) 가드
		_params["bg"] = int(st["bg"])
	# 조우 인덱스(enc): 어드벤처 다중 조우에서 몇 번째 몹인지. 마지막=보스.
	var enemies: Array = st.get("enemies", [])
	var enc := clampi(int(_params.get("enc", 0)), 0, maxi(0, enemies.size() - 1))
	# 랜덤 보스 스테이지(원작 혼돈의 틈새 등): 일반몹 없이 보스전만 — 입장 시 목록서 랜덤 1마리.
	if bool(st.get("random_boss", false)) and not enemies.is_empty():
		# enc가 지정되면 그걸(재현), 아니면 무작위. hp_state 이월과 무관한 단발 보스.
		if not _params.has("enc"):
			var rr := RandomNumberGenerator.new(); rr.randomize()
			enc = rr.randi() % enemies.size()
	# 🔒 소환형(혼돈의 틈새)은 **항상** 소환 때 확정된 보스다 — enc 유무·재추첨과 무관.
	#    (2026-07-31 사용자 지적: 나갔다 들어오면 다른 보스가 나왔다.)
	if Darknix.is_summon_stage(st):
		var dkp := Darknix.enemy_index(st["summon"], UserDB.darknix(),
			int(Time.get_unix_time_from_system()))
		if dkp >= 0 and dkp < enemies.size():
			enc = dkp
	# 요일별 보스 교대(원작 우노 '미지의 터'). 위키 dungeon_4.pdf §4.2 가 요일을 특정한다 —
	# 월=볼케이노 화=윗치 수=드라고노이드 목=골드 토=퍼플립스, 일요일은 전부 등장(=무작위).
	# stages.json `boss_by_weekday` = {"1"(월)…"7"(일): enemies 인덱스, -1 = 무작위}.
	var wd_map: Dictionary = st.get("boss_by_weekday", {})
	if not wd_map.is_empty() and not enemies.is_empty() and not _params.has("enc"):
		# Godot Time 은 weekday 0=일요일 → 우리 키(1=월 … 7=일)로 옮긴다.
		var g := int(Time.get_datetime_dict_from_system().get("weekday", 0))
		var key := str(7 if g == 0 else g)
		var idx := int(wd_map.get(key, -1))
		if idx < 0 or idx >= enemies.size():
			var wr := RandomNumberGenerator.new(); wr.randomize()
			idx = wr.randi() % enemies.size()
		enc = idx
	var e: Dictionary = (enemies[enc] if not enemies.is_empty() else _params.get("enemy", {}))
	# 몬스터 에셋 id 미매칭(위키 데이터엔 이름만, 스프라이트 id 매칭은 TODO) → null이면 플레이스홀더 스프라이트.
	# 이름·레벨·스탯은 위키값 사용(월드맵→던전→전투 루프가 실 데이터로 동작). # ASSUMPTION: sprite=1 폴백.
	var eid: Variant = e.get("id", 1)
	_enemy = {
		"id": int(eid) if eid != null else 1,
		"asset_id": int(e.get("asset_id", eid)) if eid != null else 1,
		"name": String(e.get("name", "분홍 몬스터")),
		"level": int(e.get("level", 15)),
		"element": String(e.get("element", "grass")),
		"hp_max": int(e.get("hp_max", 520)),
		"hp": int(e.get("hp", e.get("hp_max", 520))),
		"att": int(e.get("att", 60)),
		"def": int(e.get("def", 40)),
		# 원작 `Monster::isBoss` — BGM·등장 연출·보상 배수가 이걸 본다.
		# `stages.json` 의 각 적 항목이 들고 있다(혼돈의 틈새 3종·밤 지역보스 등).
		"boss": bool(e.get("boss", false)),
		# 몬스터 보유 스킬(스킬 id 목록). 원작 몬스터도 스킬을 쓴다 —
		# `BattleMonster::setReadySkill`/`callReadySkill`/`setAnimatedReadySkill`(준비 모션)이 실재하고
		# `FightManager::getActorSkillNumber`/`getTargetSkillNumber` 는 진영을 가리지 않는다.
		# 값은 위키 dungeon_*.pdf → `data/monsters.json` → `data/stages.json`
		# (기입 도구 `scripts/tools/build_monster_skills.py`). 없으면 빈 배열 = 종전과 동일한 전투.
		"skills": (e.get("skills", []) as Array).duplicate(),
	}
	# 영웅 난이도에서만 실리는 스킬(stages.json `skills_hero`) — 우노 '검은 섬' 관문의 수호자의
	# 철갑 방패가 그렇다. 위키 §4.1 표기도 '철갑 방패[영웅]' 이고 🟦 사용자 확정(2026-07-30).
	if bool(_params.get("hero", false)):
		for hs in (e.get("skills_hero", []) as Array):
			if not (_enemy["skills"] as Array).has(int(hs)):
				(_enemy["skills"] as Array).append(int(hs))
		# 영웅 난이도 스탯 배수 — 🟦 사용자 원작 영상 실측 2026-08-02:
		# **일반 대비 체력 ×3, 공격력·방어력 ×1.5**. 레벨은 건드리지 않는다
		# (보상 exp/골드가 적 레벨 파생이라 레벨을 올리면 보상까지 같이 뛴다).
		# 순서: 여기서 먼저 곱하고, 파티 인원 배수·정예·카데스가 그 위에 다시 곱한다.
		# 스테이지가 자기 `hero_stat_mult` 를 가지면 그게 이긴다 — 우노 '검은 섬'(24)의 숫자 1.0은
		# 세 스탯 모두 ×1로 해석한다
		# (🟦 사용자 확정 2026-07-31: 거기는 영웅/일반 적 스탯이 같고, 난이도는 인원 배수가 담당).
		var hmult := Battle.hero_stat_multipliers(st,
			Data.stages.get("_variant_rules", {}) as Dictionary)
		var hp_mult := float(hmult.get("hp", 1.0))
		var att_mult := float(hmult.get("att", 1.0))
		var def_mult := float(hmult.get("def", 1.0))
		_enemy["hp_max"] = maxi(1, int(round(float(int(_enemy["hp_max"])) * hp_mult)))
		_enemy["hp"] = maxi(1, int(round(float(int(_enemy["hp"])) * hp_mult)))
		_enemy["att"] = maxi(1, int(round(float(int(_enemy["att"])) * att_mult)))
		_enemy["def"] = maxi(1, int(round(float(int(_enemy["def"])) * def_mult)))
	# 파티 **인원수** 연동 보스(원작 우노 '검은 섬' 관문의 수호자).
	# 🟦 사용자 확정(2026-07-30): 기본 스탯 × (출전 드래곤 수)^power (power=2) —
	#   1마리 ×1 · 2마리 ×4 · 3마리 ×9. 위키 §4.1 의 "여러 마리를 사용할 경우 난이도가 급등",
	#   "한 마리만 쓸 때의 스펙이 훨씬 낮다" 서술과 맞는다.
	# ⚠️ 종전 `scale_to_party`(파티 평균 **스탯** × 자작 계수)는 같은 위키 서술을 스탯 연동으로
	#   해석한 자작이었다 — 경로는 남겨 두되(다른 스테이지가 쓰면 동작) 우노는 이쪽을 쓴다.
	var pc: Dictionary = st.get("scale_by_party_count", {})
	if not pc.is_empty():
		_apply_party_count_scaling(pc)
	else:
		var sc: Dictionary = st.get("scale_to_party", {})
		if not sc.is_empty():
			_apply_party_scaling(sc)
	# 원작 setEventMonster: 정예 몬스터 — 스탯 ×1.5(공/방/체), 보상은 _finish에서 2배.
	if bool(_params.get("elite", false)):
		_enemy["hp_max"] = int(_enemy["hp_max"] * 1.5)
		_enemy["hp"] = _enemy["hp_max"]
		_enemy["att"] = int(_enemy["att"] * 1.4)
		_enemy["def"] = int(_enemy["def"] * 1.3)
	if _is_kades():
		_apply_kades_enemy(bool(e.get("boss", false)))

## 적 전투원에 실을 스킬 목록 — `Battle.make_combatant` 형식 `[{id, level}]`.
##
## 스킬 **레벨**은 원작 표가 서버와 함께 유실됐다(위키는 몬스터의 보유 스킬 이름만 적는다).
## # ASSUMPTION: 1레벨(가장 약한 눈금)로 쓴다 — 지어낸 강화치로 밸런스를 흔들지 않는 쪽.
##   되살릴 근거가 생기면 `data/stages.json` 편성에 레벨 칸을 더하고 여기만 고치면 된다.
## 스킬 봉인 던전에서는 `skills_db` 가 비어 이 목록이 그대로 무효가 된다(드래곤과 같은 규칙).
## 전투 1회당 줄어드는 허기 게이지(FOOD). # ASSUMPTION — 원작 속도는 서버 유실. `_finish` 에서 쓴다.
const FOOD_PER_BATTLE := 15

const ENEMY_SKILL_LEVEL := 1
func _enemy_skills() -> Array:
	var out: Array = []
	for sid in (_enemy.get("skills", []) as Array):
		# JSON 숫자는 float 로 들어온다 — `make_combatant` 도 int 로 정규화하지만
		# 여기서 먼저 맞춰 둔다(str(30.0)="30.0" 조회 실패 함정, §7 기록).
		out.append({"id": int(sid), "level": ENEMY_SKILL_LEVEL})
	return out

## 카데스의 공간 몬스터 강화 — 위키 dungeon_1.pdf §2.
##   "기존 지역에 등장했던 몬스터들이 더욱더 강해져서 돌아오며, 보스는 더욱 강력해지며
##    외형까지 바뀐다" / "보스 몬스터의 레벨은 120~200 사이로 랜덤하게 정해지며,
##    이에 따라 능력치도 달라진다."
## 보스 레벨 구간은 **위키 확정**이고, 그 레벨에서의 스탯은 원작 표가 서버 유실이라
## 기본 필드 스탯을 레벨비로 끌어올린다(# ASSUMPTION — data/kades.json `_boss_note`).
## 일반몹 배수는 자작 노브(`data/kades.json` monster_mult)다.
func _apply_kades_enemy(boss: bool) -> void:
	var lv0 := maxi(1, int(_enemy.get("level", 1)))
	if boss:
		var r := RandomNumberGenerator.new()
		# 조우 재현성 — 같은 스테이지/조우에서는 같은 보스 레벨이 나오게 한다.
		r.seed = hash("kades_boss_%s_%d" % [String(_params.get("stage", "")),
			int(_params.get("enc", 0))])
		var lv := Kades.boss_level(Data.kades, r)
		if lv > 0:
			# 스탯별 배수 = 낮 보스 레벨곡선 f(lv)/f(lv0) (data/kades.json boss_stat_curve).
			# 🔴 종전의 단순 레벨비(lv/lv0)는 Lv.1 던전을 ×120~200 으로 부풀려
			#    희망의 숲(카데스)이 칼바람의 산맥(카데스)보다 훨씬 세지는 역전이 났다.
			_enemy["level"] = lv
			_enemy["hp_max"] = maxi(1, int(round(float(_enemy["hp_max"])
				* Kades.boss_stat_mult(Data.kades, "hp", lv, lv0))))
			_enemy["hp"] = _enemy["hp_max"]
			_enemy["att"] = maxi(1, int(round(float(_enemy["att"])
				* Kades.boss_stat_mult(Data.kades, "att", lv, lv0))))
			_enemy["def"] = maxi(0, int(round(float(_enemy["def"])
				* Kades.boss_stat_mult(Data.kades, "def", lv, lv0))))
		_enemy["name"] = "%s [전설]" % String(_enemy["name"])
	else:
		var m := float(Data.kades.get("monster_mult", 2.0))
		_enemy["hp_max"] = maxi(1, int(round(float(_enemy["hp_max"]) * m)))
		_enemy["hp"] = _enemy["hp_max"]
		_enemy["att"] = maxi(1, int(round(float(_enemy["att"]) * m)))
		_enemy["def"] = maxi(0, int(round(float(_enemy["def"]) * m)))

## 카데스의 공간인가. 진입은 **변형 필드 id(601~614)** 로 이뤄진다 → 스테이지가 답을 갖고 있다.
## `params.kades` 는 adventure 가 명시로 넘겨 주거나 테스트가 덮어쓰는 override.
## 이번 런의 난이도 키(일반/영웅/밤/카데스). **params 만 본다** — `_is_kades()` 를 부르면
## 그쪽이 다시 스테이지를 읽어 순환한다.
## 드랍 키 → 표시 이름. 가상 키(스킬/알/젬·장비)는 items.json 에 없으므로 합성한다.
func _drop_display_name(key: String) -> String:
	var sk := Loadout.parse_item_key(key)
	if not sk.is_empty():
		return "%s Lv.%d 스크롤" % [
			String(Data.skills.get(str(int(sk["id"])), {}).get("name", "스킬")), int(sk["level"])]
	if key.begins_with(EggGacha.KEY_PREFIX):
		return String(EggGacha.item_def(key, Data.dragons).get("name", "알"))
	var gn := Drops.display_name(key, Data.gems, Data.equipment)
	return gn if gn != key else Data.item_name(key)

func _variant_mode() -> String:
	return Drops.mode_of(bool(_params.get("hero", false)),
		bool(_params.get("night", false)), bool(_params.get("kades", false)))

## 이번 런이 쓸 **필드 레코드**. 유타칸 밤(+500)·카데스(+600)는 원작에서 별도 필드 레코드였고
## (`Field.c` setInfo), 우리는 `stages.json` 의 `night`/`kades` 블록을 덮어 재현한다.
## 🔴 2026-07-31 이전에는 이 해석이 없어서 **밤에 입장해도 낮 몬스터·낮 드래곤 알**이 나왔다.
func _stage_rec() -> Dictionary:
	if not _params.has("stage"):
		return {}
	return Field.apply_variant(Data.stage(str(_params.get("stage", ""))), _variant_mode())

func _is_kades() -> bool:
	if _params.has("kades"):
		return bool(_params.get("kades"))
	var st: Dictionary = _stage_rec()
	return String(st.get("variant", "")) == "kades"

## 기본 필드 id(1~15). 아티팩트 배정표 조회용.
func _base_field() -> int:
	if _params.has("field"):
		return int(_params.get("field"))
	var st: Dictionary = _stage_rec()
	return DungeonBG.base_field(DungeonBG.field_id(st))

## 스토리 서브퀘스트에 이번 던전 완주를 보고한다 — 원작 `AdventureScene::setEventScenario`
## (`QuestData::setCount(getCount()+1)` @AdventureScene.c:45749) + 던전 클리어 시의
## `CompleteLayer`(시나리오 진행 처리) 자리.
##
## ⚠️ ASSUMPTION — **세는 시점**: 원작은 탐험 이벤트 테이블의 `case 0x20`(setEventScenario)이
##    뜰 때 1 올렸고, 그 이벤트 확률은 서버 `InfoEventData` 소유라 유실이다. 확률을 지어내지
##    않기로 하고(CLAUDE.md §2-6) **던전 1회 완주 = 1회**로 센다 — 원작 문자열
##    `QuestTitle_ADVENTURE` = "%d회 탐험" 의 문면과도 맞는다.
## 판정·저장은 logic(`StoryQuest`)이 하고 여기서는 상황(필드/밤/카데스)만 넘긴다(§8.3).
func _note_story_quest(st: Dictionary) -> void:
	var field := DungeonBG.base_field(DungeonBG.field_id(st))
	var is_night := bool(UserDB.get_pmeta("yutakan_night", false))
	var variant := {"kades": 1 if String(st.get("variant", "")) == "kades" else 0}
	var done := StoryProgress.note_adventure(field, is_night, variant)
	if done > 0:
		Toast.show(self, "서브미션 달성! %d화가 열렸습니다." % done)


## 파티 평균 스탯 × 계수로 보스 스탯을 세운다. 마릿수가 늘면 난이도가 오르도록 인원 배수를 곱한다
## (위키: "여러 마리를 사용할 경우 난이도가 급등"). 계수·인원 배수는 `data/stages.json` 의
## `scale_to_party` — 원작 공식은 서버 유실이라 **자작 튜닝 노브**다. # ASSUMPTION
## 출전 **드래곤 수** 연동 보스 — 기본 스탯 × n^power. 🟦 사용자 확정(2026-07-30, 검은 섬).
## `enemies` 의 hp_max/att/def 가 **1마리 기준 기본값**이다(543/180/130).
func _apply_party_count_scaling(pc: Dictionary) -> void:
	var n := 0
	for u in _party_uids_for_scaling():
		var d: Dictionary = UserDB.get_dragon(int(u))
		if d.is_empty() or UserDB.is_egg(d):
			continue
		n += 1
	if n <= 1:
		return                      # ×1 — 기본값 그대로
	var mult := pow(float(n), float(pc.get("power", 2)))
	_enemy["att"] = maxi(1, int(round(float(_enemy["att"]) * mult)))
	_enemy["def"] = maxi(0, int(round(float(_enemy["def"]) * mult)))
	_enemy["hp_max"] = maxi(1, int(round(float(_enemy["hp_max"]) * mult)))
	_enemy["hp"] = _enemy["hp_max"]

## 스케일링이 셀 파티 — 이번 탐험이 정한 출전 인원(`party_uids`), 없으면 활성 드래곤 1마리.
func _party_uids_for_scaling() -> Array:
	var uids: Array = _params.get("party_uids", [])
	if uids.is_empty():
		var au := UserDB.active_uid()
		if au > 0:
			uids = [au]
	return uids

func _apply_party_scaling(sc: Dictionary) -> void:
	var uids: Array = _party_uids_for_scaling()
	if uids.is_empty():
		return
	var n := 0
	var sum_att := 0.0
	var sum_def := 0.0
	var sum_hp := 0.0
	for u in uids:
		var d: Dictionary = UserDB.get_dragon(int(u))
		if d.is_empty() or UserDB.is_egg(d):
			continue
		var s: Dictionary = Growth.compute_stats(Data.get_dragon(int(d.get("id", 1))),
			Data.stat_table, int(d.get("level", 1)))
		sum_att += float(s.get("att", 0))
		sum_def += float(s.get("def", 0))
		sum_hp += float(s.get("hp", 0))
		n += 1
	if n == 0:
		return
	# 인원 배수: 1마리=1.0, 마리당 +0.5 (위키 '여러 마리면 난이도 급등'을 반영한 자작값).
	var crowd := 1.0 + 0.5 * float(n - 1)
	_enemy["att"] = maxi(1, int(round(sum_att / n * float(sc.get("att", 1.0)) * crowd)))
	_enemy["def"] = maxi(0, int(round(sum_def / n * float(sc.get("def", 1.0)) * crowd)))
	_enemy["hp_max"] = maxi(1, int(round(sum_hp / n * float(sc.get("hp", 1.0)) * crowd)))
	_enemy["hp"] = _enemy["hp_max"]

func _setup_party() -> void:
	_party.clear()
	_drink_users.clear()
	var owned: Array = UserDB.dragons()
	var active := UserDB.active_uid()
	var ordered: Array = []
	# 출전 인원은 **이번 탐험이 정한 것**을 그대로 쓴다(adventure 가 `party_uids` 로 넘긴다).
	# 원작 일반 탐험은 리더 1마리(`AdventureScene::initMainDragon` → `Dragon::isSelected`)이고,
	# 3마리는 레이드·영웅·유타칸 밤·카데스의 공간·혼돈의 틈새에서만이다(2026-07-27 사용자 확정).
	# ⚠️ 여기서 전역 `UserDB.party()` 를 다시 읽으면 1인 탐험에도 3마리가 나온다.
	var chosen: Array = _params.get("party_uids", [])
	if chosen.is_empty():
		chosen = UserDB.party()      # 탐험을 거치지 않은 직접 진입(데모·테스트) 폴백
	if not chosen.is_empty():
		for uid in chosen:
			var d := UserDB.get_dragon(int(uid))
			if not d.is_empty(): ordered.append(d)
	else:
		for d in owned:
			if int(d["uid"]) == active:
				ordered.push_front(d)
			else:
				ordered.append(d)
	# 종족 조합 팀버프(원작 TeamBuff, docs/ref/design/team_buff_analysis.md): 파티 전체 구성으로 1회 산출.
	# ✅ race_dim=element 는 2026-07-31 확정 — 더 이상 ASSUMPTION 이 아니다.
	#    `CombineElementsLayer::combine`(decomp :1341-1394)이 Dragon::getRace() 를 문자열로 바꾸는
	#    switch 를 갖고 있다: 0=earth 1=aqua 2=fire 3=wind 4=light 5=dark 6=holy 7=chaos 8=shadow.
	var party3: Array = ordered.slice(0, 3)
	var team_delta := _team_buff_delta(party3)
	_active_team_buffs = _team_buff_list(party3)
	_team_races = _party_race_keys(party3)   # 조합 연출(CombineElements)이 쓰는 속성 3종

	for i in mini(3, ordered.size()):
		var d: Dictionary = ordered[i]
		var id := int(d["id"])
		var ddef := Data.get_dragon(id)
		var level := int(d.get("level", 1))
		# 실 스탯 파이프라인(base+gain_log → 젬 → 장비 → 장신구 → 팀버프 → 드링크 → 카데스)은
		# **탐험 하단 파티 카드와 공유**한다 — `PartyStats.resolve`(scripts/systems/party_stats.gd).
		# 원작은 탐험·전투가 같은 씬이라 카드가 하나로 이어지는데(레퍼런스 docs/ref/adventure/
		# 4_전투시작.png ↔ 전투4.png ↔ 승리9.png), 우리는 두 씬으로 나눠 놔서 여기서 따로 계산하면
		# 탐험 카드와 전투 카드의 숫자가 어긋난다. 순서가 결과를 바꾸므로 모듈 한 곳에만 둔다.
		var stats := PartyStats.resolve(d, ddef, team_delta, _is_kades(), _field_element())
		if PartyStats.uses_drink(d):
			_drink_users.append(int(d["uid"]))
		# 조우 간 HP 영속(어드벤처 다중 조우): hp_state에 uid별 잔여HP가 있으면 그걸로 시작.
		var hpmax := int(stats.get("hp", 1))
		var carried: Dictionary = _params.get("hp_state", {})
		var hp0 := int(carried.get(str(int(d["uid"])), hpmax)) if not carried.is_empty() else hpmax
		var eq: Dictionary = _resolve_skills(int(d["uid"]), ddef)
		_party.append({
			"id": id, "uid": int(d["uid"]), "level": level,
			"name": Icons.name_of(d),
			"element": String(ddef.get("element", "")),
			"stats": stats,
			"hp": clampi(hp0, 0, hpmax), "hp_max": hpmax,
			"skills": eq["skills"],
			# 스킬 칸 타입(원작 Dragon::getSkillType). 스킬 타입과 일치하면 추가효과
			# (`<ToolTipDragonSkillExplain>`) — Battle 이 `skill_slot_match` 로 반영한다.
			# 빈 칸을 건너뛴 만큼 타입도 같이 좁혀 온다(skills 와 인덱스가 맞아야 한다).
			"skill_slots": eq["slot_types"],
			# 각성 여부 — 원작 `Dragon::setAwaken(bool)`. 크리티컬 컷인/타격 아트가 이 플래그
			# 하나로 `e_` 변형으로 갈린다(Dragon.c:8621 · :8935 가 같은 오프셋 0xac 를 본다).
			"awakened": bool(d.get("awakened", false)),
			# 크리티컬 보이스 번호 — 원작 `info_dragon_v2.voice_critical_no` → `music/voice<N>.mp3`.
			# 실제 번호가 복구된 경우에만 재생한다(없으면 0 = 속성 효과음 폴백).
			"voice_critical": _critical_voice_no(id, ddef),
			# 크리티컬 연타 횟수 — 원작 `info_dragon_v2.critical_hit`. 유실 → 있으면 쓰고
			# 없으면 combat.json `judge.crit_hits` 로 폴백(`_crit_hits`).
			"critical_hit": int(ddef.get("critical_hit", 0)),
			# 각성 스킬 번호(data/skill_awaken.json). 효과는 아래 `_apply_awaken_skills` 가 얹는다.
			"awaken_skill": int(d.get("awaken_skill", 0)) if bool(d.get("awakened", false)) else 0,
			# 개체 등급(§K-10). 각성스킬 18·100 이 아군끼리 비교할 때 쓴다.
			"grade": Growth.compute_grade(ddef, Data.stat_table, d.get("stat_bonus", {}),
				d.get("gain_log", []), Data.level_curve.get("grade", {})),
			# 전투 유형(원작 `Dragon::getAttackType`) = dragons.json 의 `type`.
			# 해골요새 특수 장비가 공격자/방어자 양쪽 유형을 본다(`Battle` 의 `dmg_deal_vs_type`).
			"atk_type": String(ddef.get("type", "")),
		})
	_apply_awaken_skills()

## 각성 스킬(상시 특성)을 파티에 반영한다. 판정 = `AwakenSkill`(logic) · 표 = data/skill_awaken.json.
##
## ⚠️ **여기(카드 생성 전)에서 해야 한다.** 체력을 올리는 스킬(57 생명의 기운 등)이 있어서
##   `_build_party_cards` 뒤에 걸면 카드의 HP 게이지가 옛 최대치로 그려진다.
##   그래서 임시 전투원을 만들어 효과를 얹고, 결과를 `_party` 로 되돌려 적는다.
##   `_run_and_replay` 는 이 결과(stats·hp_max·awaken_effects)로 진짜 전투원을 만든다.
##
## 각성스킬은 '스킬'이 아니라 상시 특성이라 Battle 의 skill_uses 흐름을 타지 않는다.
var _awaken_fired: Array = []      # 이번 전투에 실제로 발동한 것 [{no, name, owner}]
var _equip_fired: Array = []       # 장비 조건부 효과로 실제로 걸린 것 [{key, name, owner}]

## 이번 파티의 각성 스킬 **탐험 보너스** 합 {gold_pct, artifact_chance_pct}.
## 전투 밖 보상(골드·아티팩트 확률)에 쓴다 — 전투 계수와 달리 combatant 가 필요 없다.
func _awaken_explore() -> Dictionary:
	var lst: Array = []
	for p in _party:
		# 장비 수정자도 함께 넘긴다 — 구드라의 가호(아티팩트 확률)를 고치는 장비가 있다.
		var e := {"awaken_no": int((p as Dictionary).get("awaken_skill", 0)),
			"equip_keys": EquipEffect.keys_of((p as Dictionary).get("equip", {}))}
		EquipEffect.awaken_mods([e], Data.equip_effects)
		lst.append(e)
	return AwakenSkill.explore_bonus(lst, Data.skill_awaken)


func _apply_awaken_skills() -> void:
	_awaken_fired = []
	_equip_fired = []
	# 본체는 `PartyStats.apply_passives`(logic) — **탐험 하단 파티 카드와 공유**한다.
	# 여기에만 두면 탐험 카드가 체력을 올리는 각성 스킬(57 생명의 기운 등)을 반영하지 못해
	# 전투 카드와 최대 HP 가 달라진다(원작은 탐험·전투가 한 씬이라 그런 갈림이 없었다).
	#
	# ⚠️ `awaken_effects` 는 이름과 달리 **각성스킬 + 장비 조건부 효과**를 함께 담는다.
	#    둘 다 '전투 시작 시 1회 심는 상시 특성'이고 같은 효과 목록으로 흐르기 때문이다.
	#    (`_run_and_replay` 는 이 배열을 그대로 전투원에 옮기고 다시 심지 않는다 — 이중 적용 방지)
	#
	# 활성 팀버프 이름은 `_setup_party` 가 이미 산출해 둔 것을 조건 판정용으로 넘긴다
	# (전용 장비 세로님의 전쟁보닛이 "팀버프 [흑풍]을 활성화한 경우" 로 이 값을 본다).
	var tbnames: Array = []
	for b in _active_team_buffs:
		tbnames.append(String((b as Dictionary).get("name", "")))
	var fired := PartyStats.apply_passives(_party,
		{"element": String(_enemy.get("element", "")), "hp": int(_enemy.get("hp_max", 1))},
		{"field_element": _field_element(), "enemy_boss": _is_boss(), "team_buffs": tbnames,
			"explore_gold_pct": int(_awaken_explore().get("gold_pct", 0))})
	_awaken_fired = fired["awaken_fired"]
	_equip_fired = fired["equip_fired"]


## 속성 조합 팀버프 집계 — 로직=원작 TeamBuff::isActivate 복원(scripts/systems/team_buff.gd).
## 데이터=data/team_buffs.json: 이름·효과 30종을 위키 §2.3.3.1 에서 복원했고,
## **combine(조합 구성)도 30/30 채워져 있다**(각 버프가 정확히 3마리 조합 → 파티 3마리로 전부 발동 가능).
## ⚠️ 2026-07-30 주석 정정 — 종전엔 "combine 미복원 → 전 버프 미발동"이라고 적혀 있었으나
##   그 뒤 채워졌고 실측(`data/team_buffs.json` 30건 전부 combine 합계 3)으로 확인했다.
## 반환 = TeamBuff.aggregate_typed 형식 {stat: {pct, point, flat}}. atk 별칭은 TeamBuff.apply 가 att로 정규화.
## ⚠️ race_dim=element는 ASSUMPTION(원작 DragonRace id 유실 — 위키가 "속성 조합 버프"라 부르는 근거).
## 활성 팀버프 목록(연출용). 원작 TeamBuff::createIcon 이 아이콘을 만드는 그 목록이다.
var _active_team_buffs: Array = []
## 파티 3마리의 속성 키 — 조합 연출 `CombineElements` 의 진입 데이터(원작 combine() 이
## `Dragon::getRace()` 로 뽑아 `this+0x198/0x1a0/0x1a8` 에 넣는 그 3개).
var _team_races: Array = []

## 파티 → race 키 목록. race_dim 은 테이블이 선언한다(현재 element, 위 근거로 확정).
func _party_race_keys(party: Array) -> Array:
	var table: Dictionary = Data.team_buffs
	var race_dim := String(table.get("race_dim", "element"))
	var race_keys: Array = []
	for d in party:
		race_keys.append(String(Data.get_dragon(int(d["id"])).get(race_dim, "")))
	return race_keys

func _team_buff_list(party: Array) -> Array:
	var table: Dictionary = Data.team_buffs
	if table.is_empty() or (table.get("buffs", []) as Array).is_empty():
		return []
	return TeamBuff.active_buffs(_party_race_keys(party), table)

## 🔴 2026-07-31 제거: 전투 HUD 의 **팀버프 배지는 자작**이었다.
## `TeamBuff::createIcon` 호출자를 전수 조회하면 `SkinPopup`(드래곤 정보 팝업) **하나뿐**이고
## (`grep -rn createIcon docs/ref/orig_code/decomp/`), 원작 전투 화면엔 이 배지가 없다.
## 원작이 조합 버프를 알리는 유일한 방법 = 전투 개시 직전의 연출 `CombineElementsLayer`
## (`docs/ref/porting/CombineElementsLayer.md`) — 아래 `_maybe_team_buff_intro` 로 이식돼 있다.
## 수치 적용은 `_team_buff_delta` 가 그대로 담당한다(화면 표시만 사라진다).

func _team_buff_delta(party: Array) -> Dictionary:
	var table: Dictionary = Data.team_buffs
	if table.is_empty() or (table.get("buffs", []) as Array).is_empty():
		return {}
	return TeamBuff.typed_for_party(_party_race_keys(party), table)

## 조합 연출(원작 `AdventureScene::setCheckTeamBuff`, AdventureScene.c:55692) — 전투 개시 직전.
## 원작 원문:
##   if (아직 안 틀었음 && 3슬롯 전원 && 레이드 아님) {
##       layer = CombineElementsLayer::create(d0,d1,d2);
##       runningScene->addChild(layer, 1000); layer->active();
##       runAction(Seq(DelayTime(layer->getDuration()), CallFunc(setEventFightStart)));
##   } else setEventFightStart(this);
## ⇒ **연출이 끝날 때까지(7초) 전투 시작을 미룬다.** 우리는 `_run_and_replay()` 를 그만큼 늦춘다.
## 재생 대상은 **첫 번째로 발동한 버프 하나**(원작 combine() 이 첫 발동에서 루프를 끊는다).
## 연출 상세 = `docs/ref/porting/CombineElementsLayer.md`.
func _maybe_team_buff_intro() -> void:
	var gen := _gen
	var buff: Dictionary = _active_team_buffs[0] if not _active_team_buffs.is_empty() else {}
	# 원작 this[0x39a] = "이 탐험에서 한 번만". 우리 전투 씬은 조우마다 새로 생기므로 탐험 키로 판별.
	var run_key := "%s:%d" % [String(_params.get("stage", "")), int(_params.get("run_seed", 0))]
	if buff.is_empty() or not CombineElements.can_play(run_key, _team_races.size(), buff):
		_run_and_replay()
		return
	var layer := CombineElements.play(self, _team_races, buff, Data.team_buffs)
	if layer == null:
		_run_and_replay()
		return
	CombineElements.mark_played(run_key)
	await get_tree().create_timer(CombineElements.DURATION).timeout
	if gen != _gen or not is_inside_tree():
		return
	_run_and_replay()

## 전투에 나가는 스킬 = **장착 2칸에 꽂힌 것만**(원작 `Dragon::getSkill(0/1)`).
## 학습 풀(`dragon_skills`)은 가지고만 있는 목록이라 전투에 안 나간다 — 종전엔 풀 전체를 넘겼다.
## 반환 {skills, slot_types} — 칸 타입을 같이 좁혀 인덱스 정렬을 지킨다(Battle.slot_match_mult 전제).
## 유실 매핑이라 기본배정은 ASSUMPTION([[Loadout]]).
func _resolve_skills(uid: int, ddef: Dictionary) -> Dictionary:
	# override(`data/dragon_skills.json`, 사용자 정밀배정)가 있으면 그것으로 채운다(멱등).
	# 없으면 빈 채로 두고 — 스킬은 레벨 10·25·45 자동 습득과 스크롤로만 생긴다(위키 규칙).
	if (UserDB.dragon_skills(uid) as Array).is_empty():
		UserDB.ensure_dragon_skills(uid,
			Loadout.default_skills(ddef, Data.skills, Data.dragon_skill_overrides()))
	UserDB.sync_skill_grants(uid)   # 레벨업이 다른 경로로 들어온 경우까지 보정(멱등)
	return UserDB.dragon_battle_skills(uid)

# ---------- 배경 ----------
func _build_bg() -> void:
	# 던전 배경(DungeonBG): 원작 scene/adventure/bg/<필드id>/ 의 원경 + 전경 2겹.
	# 스테이지를 못 정하면 params.bg → battle_bg/bg_1 폴백.
	var st: Dictionary = _stage_rec()
	# 🟦 스토리 전투 배경(사용자 확정 2026-07-31: 기계 만드라고낙=몽환의 수정터 ·
	#    정령 스파이크젤=오색호수 · 다크프로스티=칼바람의 산맥).
	#    `stage` 를 그냥 넘기면 **그 던전의 적 편성이 이겨서** 스토리 몹이 사라진다
	#    (`_setup_enemy` 는 stage.enemies 를 먼저 본다) ⇒ 배경 전용 인자를 따로 둔다.
	#    500+/600+ 은 밤·카데스 변형 필드라 기본 필드로 되돌려 변형을 입힌다.
	if st.is_empty() and _params.has("bg_stage"):
		var f0 := int(_params.get("bg_stage", 0))
		var mode := ""
		if f0 > 600:
			f0 -= 600; mode = "kades"
		elif f0 > 500:
			f0 -= 500; mode = "night"
		var bst: Dictionary = Field.apply_variant(Data.stage(str(f0)), mode)
		if not bst.is_empty() and DungeonBG.build(self, bst) != null:
			return
	if not st.is_empty() and DungeonBG.build(self, st) != null:
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

# ---------- 적(중앙) ----------
## 필드 버프 파티클(`battle/stage_<속성>_buff_spine`) — 원작 `AdventureScene::setCheckFieldBuffToUi`
## (AdventureScene.c:38080-38370) 축자 이식.
##
##   Field::create(fieldNo) → Field::getAttribute()  = **필드(던전)의 속성 문자 1글자**
##   출전 드래곤 3칸을 돌며:
##      if Dragon::getIsFieldBuff(d) and Dragon::getRace(d) == 필드속성:
##           spine = stage_<race>_buff_spine
##           spine.position = InterFace::getBackSprite(카드).contentSize * 0.5   ← **그 드래곤 카드 중앙**
##           backSprite->addChild(spine, 100, 0xbc7);  setRaceParticleOn(true)
##   그리고 `setIsFieldBuff` 자체가 `dragon.race == Field::getAttribute()` 의 결과다
##   (AdventureScene.c:37434-37658 의 종족별 memcmp "E"/"F"/"W"/"L"/"D"/"H"/"C"/"S").
##
## 🔴 2026-07-27 정정: 종전 구현은 **적(몬스터) 속성**으로 골라 화면 중앙 바닥에 한 장 깔았다.
##   그래서 빛 속성 드래곤 1마리로 칼바람의 산맥(몹 aqua/wind)에 들어가면 물·바람 이펙트가
##   떴다(사용자 신고). 원작은 적 속성과 무관하며, **속성이 맞는 드래곤 카드에만** 붙는다.
##
## 필드 속성: `Field::setInfo` 가 읽던 서버 DB(info_field) 값은 유실이지만, 던전별 속성은
##   `data/stages.json` 의 `element` 에 배정돼 있다(23/25 — 우노 24·25 만 없음). 그 값을 쓰고,
##   없을 때만 **그 던전 몬스터의 최빈 속성**으로 대신한다(# ASSUMPTION).
func _build_field_buff() -> void:
	var fel := _field_element()
	if fel == "" or fel == "none":
		return
	var path := "res://scenes/buffs/stage_buff_%s.tscn" % fel
	if not ResourceLoader.exists(path):
		return
	for i in _party.size():
		if String(_party[i].get("element", "")) != fel:
			continue                       # = Dragon::getIsFieldBuff(d) == false
		var v: Dictionary = _views.get("A%d" % i, {})
		var card = v.get("node", null)
		if not (card is Control):
			continue
		var c := card as Control
		var holder := Node2D.new()
		holder.position = c.size * 0.5     # 원작: 백스프라이트 contentSize 중앙
		holder.z_index = 1                 # 원작 addChild(spine, 100) — 카드 아트 위
		holder.scale = Vector2(1.5, 1.5)   # 원작 `*(float*)(spine+0x150) = 0x3fc00000` = 1.5
		c.add_child(holder)
		var inst = (load(path) as PackedScene).instantiate()
		holder.add_child(inst)
		var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			var anims := ap.get_animation_list()
			if anims.size() > 0:
				# 원작 `setAnimation(spine, "animation", false, 0)` — **loop=false**, 전투 시작에 1회.
				ap.get_animation(anims[0]).loop_mode = Animation.LOOP_NONE
				ap.play(anims[0])

## 필드(던전) 속성. stages.json `element` = **던전별 배정값**이고 이게 정답이다.
## 🔴 2026-07-31 수정: 여기서 `field_element` 라는 **다른 키**만 찾다가 하나도 못 찾고
##   매번 '몬스터 최빈 속성' 폴백으로 떨어지고 있었다(배정은 23스테이지에 이미 있었다).
##   그래서 카데스 미각성 페널티의 '던전 속성과 같은 속성 → 25%' 와 각성스킬
##   `field_element` 조건이 추정값으로 판정됐다. 밤·카데스 변형(5xx/6xx)은
##   `data_loader._variant_stage` 가 기본 필드를 `duplicate(true)` 하므로 같은 속성을 물려받는다
##   (= 사용자 확인: 일반/밤/카데스의 던전별 속성은 동일).
## `field_element` 는 배정과 다른 값을 쓰고 싶을 때의 **덮어쓰기 키**로만 남긴다.
##
## ⚠️ 반드시 `Drops.normalize_element` 를 통과시킨다 — `stages.json` 은 `ground`/`water` 로,
##   `dragons.json` 은 `earth`/`aqua` 로 같은 속성을 다르게 적는다(먹이·정기 드롭도 같은
##   정규화를 쓴다, `drops.gd` ELEMENT_ALIAS). 정규화 없이 비교하면 흙·물 던전에서
##   카데스 '속성 일치 -25%' 와 각성스킬 필드조건이 **영원히 거짓**이 된다.
func _field_element() -> String:
	var st: Dictionary = _stage_rec()
	var authored := Drops.normalize_element(st.get("field_element", ""))
	if authored == "":
		authored = Drops.normalize_element(st.get("element", ""))   # 우노 24·25 는 null
	if authored != "" and authored != "none":
		return authored
	var tally: Dictionary = {}
	for e in st.get("enemies", []):
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

func _build_enemy() -> void:
	var vis := _vis()
	var cx := vis.x * 0.5
	# 보스는 네이티브 스파인이 커서 상단 HP UI를 가림 → 더 아래로 내리고 살짝 작게(구도 개선).
	var boss := _is_boss()
	var ey := 360.0 if boss else 300.0   # ASSUMPTION: 보스는 하단 배치로 상단 UI 확보
	var e_scale := 0.66 if boss else 0.85
	var sh := _spr("adventure_ui", "scene_adventure_shadow", _adv, 1.6 if boss else 1.4)
	if sh: sh.position = Vector2(cx, ey + 130.0); add_child(sh)
	# 정예 몬스터: 금빛 방사 오라(가산) — 적 뒤에 배치, 맥동.
	if bool(_params.get("elite", false)):
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 0.85, 0.3, 0.55)); grad.set_color(1, Color(1.0, 0.8, 0.2, 0.0))
		var gtex := GradientTexture2D.new(); gtex.gradient = grad
		gtex.fill = GradientTexture2D.FILL_RADIAL; gtex.fill_from = Vector2(0.5, 0.5); gtex.fill_to = Vector2(1.0, 0.5)
		gtex.width = 420; gtex.height = 420
		var glow := Sprite2D.new(); glow.texture = gtex; glow.position = Vector2(cx, ey)
		var am := CanvasItemMaterial.new(); am.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = am; glow.z_index = -1
		add_child(glow)
		var gt := glow.create_tween().set_loops()
		gt.tween_property(glow, "scale", Vector2(1.15, 1.15), 1.0).set_trans(Tween.TRANS_SINE)
		gt.tween_property(glow, "scale", Vector2.ONE, 1.0).set_trans(Tween.TRANS_SINE)
	# 원작 방식: 몬스터=스파인 idle('wait') 상시. att프레임은 공격 시만(basicAction) 사용.
	# 변환된 몬스터 스파인 씬이 있으면 그걸로, 없으면 정적 att 프레임 폴백.
	var mid := int(_enemy.get("asset_id", _enemy["id"]))
	var mspr: Node2D = null
	var att_spr: Sprite2D = null      # 공격 순간용 att 프레임(평소 숨김)
	var hit_spr: Sprite2D = null      # 피격 순간용 hit 프레임(평소 숨김)
	var mdir := "monster_%d" % mid
	var mman := _man(mdir)
	att_spr = _spr(mdir, "monster_%d_%d_image_att" % [mid, mid], mman, 1.6)
	# 원작 `BattleMonster::setAnimatedHit` 는 피격 시 `monster/%d/%d_image/hit.png` 로 교체한다
	# (Monster::getImagePathHit). 변환된 몬스터만 있으므로 없으면 틴트 플래시만 남는다.
	hit_spr = _spr(mdir, "monster_%d_%d_image_hit" % [mid, mid], mman, 1.6)
	var mscn_path := "res://scenes/monsters/monster_%d.tscn" % mid
	if ResourceLoader.exists(mscn_path):
		# 변환된 Spine 씬은 슬롯별 Sprite2D 가 원작 draw-order 를 z_index 1~108 로
		# 보존한다. 씬을 전투 루트에 바로 붙이면 그 내부 z 값이 형제인 하단 파티 카드까지
		# 넘어가 가운데 카드를 덮는다. CanvasGroup 은 자식들을 먼저 한 장으로 합성하므로
		# 몬스터 내부 draw-order 는 유지하면서, 완성된 몬스터 한 장은 뒤에 추가되는
		# InterFace 카드 아래에 놓인다(원작 카드는 AdventureScene 자식 z=400).
		var group := CanvasGroup.new()
		var inst = (load(mscn_path) as PackedScene).instantiate()
		group.add_child(inst)
		mspr = group
		mspr.scale = Vector2(e_scale, e_scale)   # 보스=더 작게(상단 UI 확보)
		var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.has_animation("wait"):
			ap.play("wait")   # idle
	else:
		mspr = att_spr        # 스파인 없으면 att 프레임을 상시 표시(폴백)
		att_spr = null
	if mspr:
		mspr.position = Vector2(cx, ey)
		add_child(mspr)
	if att_spr:
		att_spr.position = Vector2(cx, ey)
		att_spr.visible = false        # 공격 시에만(_cue) 표시
		add_child(att_spr)
	if hit_spr:
		hit_spr.position = Vector2(cx, ey)
		hit_spr.visible = false        # 피격 시에만(_hurt) 표시
		add_child(hit_spr)
	_views["E0"] = {"kind": "enemy", "node": mspr, "att_node": att_spr, "hit_node": hit_spr,
		"center": Vector2(cx, ey), "base_pos": Vector2(cx, ey), "alive": true,
		# 원작 Bicon은 몬스터 몸 위가 아니라 상단 InterFace 좌측 아래에 붙는다
		# (docs/ref/orig_image/battle/battle3.png). 화면 좌끝이 아니라 몬스터 네임플레이트의
		# 좌측 모서리를 기준으로 해야 탐험 미션 패널과도 겹치지 않는다.
		"bicon_origin": Vector2(cx - float(_adv.get(
			"scene_adventure_monster_box2" if boss else "scene_adventure_monster_box", {}).get("w", 476))
			* Design.ASSET_SCALE * 0.5 + 18.0, 81.0),
		"anim": (mspr.find_child("AnimationPlayer", true, false) if mspr else null),
		"groggy": false, "base_scale": (mspr.scale if mspr else Vector2.ONE),
		"element": String(_enemy.get("element", ""))}
	_monster_income(mspr)

# ---------- 적 인터페이스(상단) — 원작 InterFace::UI_InterFace(type4=몬스터) ----------
# 원작 구조(docs/ref/orig_code/decomp/InterFace.c:238-283, 745-1010 · AdventureScene.c:50261-50270):
#   · backSprite = `scene/adventure/monster_box_bg`(392×21, HP바 트랙) — **앵커(0.5,1.0)**,
#     위치 = VisibleRect::top() = 화면 상단 중앙. z=6 tag=100.
#     프레임 선택 분기(InterFace.c:246-283): 보스아님+비카데스 → monster_box / 보스+비던전 →
#     monster_box2 / 보스+카데스 → monster_box3. **우리는 카데스 없음** ⇒ 일반=monster_box,
#     보스=monster_box2.  (이전 구현은 일반=monster_box2, 보스=monster_box3 → 🔴 한 칸씩 밀림)
#   · 그 자식으로 네임플레이트 `monster_box`(476×55) 앵커(0,0) pos(0,0).
#   · HP 게이지 = Scale9 `scene/adventure/hp_bar10`.
#   · 현재HP BMFont(subtitle, scale 0.8) 앵커(0,0.5) @ (w*0.5-8, h*0.5-10)  ← 몬스터 분기
#   · att_icon-hd 앵커(0,1) scale 0.9 @ (w-150, h*0.5+30) / def_icon-hd @ (w-70, h*0.5+30)
#   · 등장: backSprite를 y+h*2 위(=화면 밖)에서 MoveTo 0.7 EaseExponentialInOut.
# 크기 배율은 Design.ASSET_SCALE(=4/3, 원작 contentScaleFactor 0.75의 역수).
func _build_enemy_hpbar() -> void:
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var boss := _is_boss()
	var bg_key := "scene_adventure_monster_box2_bg" if boss else "scene_adventure_monster_box_bg"
	var plate_key := "scene_adventure_monster_box2" if boss else "scene_adventure_monster_box"
	# 레이아웃 기준은 **네임플레이트**(monster_box / monster_box2). 게이지 트랙(`*_bg`)은
	# 플레이트 안쪽 홈에 가로·세로 중앙정렬된다 — 레퍼런스 실측(docs/ref/orig_image/battle/몬스터싸움.png):
	#   플레이트 x 321..985(665px), 빨간 게이지 x 379..926(548px) → 양쪽 여백 40px로 대칭 = 중앙정렬,
	#   548/1.062(스샷배율) = 516 디자인px ≒ monster_box_bg 392 × 4/3 = 523 ✓
	var bgi: Dictionary = _adv.get(bg_key, {})
	var pli: Dictionary = _adv.get(plate_key, {})
	var pw := float(pli.get("w", 476)) * S
	var ph := float(pli.get("h", 55)) * S
	var w := float(bgi.get("w", 392)) * S
	var h := float(bgi.get("h", 21)) * S
	# 원작 앵커(0.5,1.0)·pos=VisibleRect::top → 박스 상단이 화면 최상단에 붙는다.
	var root := Node2D.new()
	root.position = Vector2(vis.x * 0.5 - pw * 0.5, 0.0)
	add_child(root)
	var plate := _spr("adventure_ui", plate_key, _adv, S)
	if plate:
		plate.position = Vector2(pw * 0.5, ph * 0.5)
		root.add_child(plate)
	var trk_org := Vector2((pw - w) * 0.5, (ph - h) * 0.5)
	var track := _spr("adventure_ui", bg_key, _adv, S)
	if track:
		track.position = trk_org + Vector2(w * 0.5, h * 0.5)
		root.add_child(track)
	# HP fill — 원작 hp_bar10 Scale9. 트랙 안쪽(테두리 2px×배율만큼 인셋).
	var pad := 2.0 * S
	var bar_w := w - pad * 2.0
	var bar_h := h - pad * 2.0
	var fill := _hp_fill(bar_w, bar_h, true)
	fill.position = trk_org + Vector2(pad, pad)
	root.add_child(fill)
	# 이름·레벨 — 네임플레이트 위. 원작 몬스터 이름은 흰색(레퍼런스 docs/ref/orig_image/battle/몬스터싸움.png).
	var nm := Label.new()
	nm.text = "레벨 %d  %s" % [int(_enemy["level"]), String(_enemy["name"])]
	nm.add_theme_font_size_override("font_size", 22)
	nm.add_theme_color_override("font_color", Color.WHITE)
	nm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	nm.add_theme_constant_override("outline_size", 4)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.size = Vector2(pw, trk_org.y); nm.position = Vector2(0, 0)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(nm)
	# 현재/최대 HP — 원작 BMFont(font_subtitle, scale 0.8) 게이지 중앙.
	var hp := _bmf_label("subtitle", 0.8 * S)
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp.size = Vector2(w, h); hp.position = trk_org
	root.add_child(hp)
	# 공/방 — 원작 att_icon-hd @ (w-150, h*0.5+30) / def_icon-hd @ (w-70, h*0.5+30), 앵커(0,1).
	# ⚠️ 원작 리터럴(150/70/30)은 **포인트 단위**다 — contentSize가 이미 px/0.75 이므로 ASSET_SCALE을
	#    다시 곱하지 않는다. 기준 w,h는 네임플레이트 contentSize(=476×4/3=635, 55×4/3=73).
	#    검증: pw-150 = 485 ≒ 레퍼런스 실측 att 493 디자인px, pw-70 = 565 ≒ def 586. ✓
	var sy := ph - (ph * 0.5 + 30.0)
	_stat_icon(root, "scene_adventure_att_icon-hd", int(_enemy.get("att", 0)),
		Vector2(pw - 150.0, sy), S)
	_stat_icon(root, "scene_adventure_def_icon-hd", int(_enemy.get("def", 0)),
		Vector2(pw - 70.0, sy), S)
	# 속성 아이콘 — 🔴 2026-07-30 수정(사용자 지적): 종전엔 `battle/element_*_mark`+`_outline`을
	#   맥동시켜 그렸는데 그건 **속성 조합(시너지) 연출 자산**이다 — 전 디컴프에서 그 두 프레임을
	#   쓰는 클래스는 `CombineElementsLayer` 뿐이다(grep "battle/element_%s_mark").
	#   원작 몬스터 네임플레이트는 **'정기' 아이템과 같은 `item/item_small/ele_*`** 를 쓴다
	#   (`InterFace.c:575-640` 의 속성 switch → 앵커(0,1) · pos(10, 플레이트높이 − 5) · scale 0.5 · z 2).
	#   레퍼런스 `docs/ref/orig_image/battle/battle3.png` 의 보스 플레이트 좌상단 금색 원이 그것이고,
	#   무속성 몬스터(같은 폴더 `몬스터싸움.png` 데스웜)에는 **아이콘이 없다** — 원작 switch 의
	#   default 가 스프라이트를 만들지 않는 것과 일치한다. 둥지 상단바도 같은 오진을 고친 적이 있다.
	var elem := String(_enemy.get("element", ""))
	var ekey := Icons.element_small_frame(elem)
	if ekey != "":
		# 원작 리터럴(10, −5)은 포인트 단위 → ASSET_SCALE 을 다시 곱하지 않는다(§9-2).
		# 앵커(0,1)=좌상단 기준 → 중앙앵커 Sprite2D 로 보정(+절반).
		# size_pt 는 이미 ASSET_SCALE 이 곱해진 포인트 크기다 → scale 0.5 만 더 반영한다.
		var esz := AtlasUI.size_pt("item_small_ui", ekey) * 0.5
		var ei := AtlasUI.spr("item_small_ui", ekey, 0.5 * S)
		if ei != null:
			ei.position = Vector2(10.0 + esz.x * 0.5, 5.0 + esz.y * 0.5)
			ei.z_index = 2
			root.add_child(ei)
	var v: Dictionary = _views["E0"]
	v["hp"] = int(_enemy["hp"]); v["hp_max"] = int(_enemy["hp_max"])
	v["hp_fill"] = fill; v["hp_label"] = hp; v["bar_w"] = bar_w; v["bar_x"] = pad
	v["bar_local"] = true
	_refresh_bar(v)
	# 원작 등장 연출: 화면 위(y - h*2)에서 0.7s EaseExponentialInOut로 내려온다.
	root.position.y = -ph * 2.0
	create_tween().tween_property(root, "position:y", 0.0, 0.7)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)

## 원작 InterFace 공/방 표기: 아이콘(앵커 0,1, scale 0.9) + 그 오른쪽에 BMFont 수치(scale 0.6, 앵커 0,0.5).
## 근거: InterFace.c:787-800(att), 843-860(def), 824-840(수치 = 아이콘pos + (iconW, -10)).
func _stat_icon(parent: Node2D, frame: String, value: int, gpos: Vector2, s: float) -> void:
	var info: Dictionary = _adv.get(frame, {})
	var iw := float(info.get("w", 21)) * 0.9 * s
	var ih := float(info.get("h", 21)) * 0.9 * s
	var ic := _spr("adventure_ui", frame, _adv, 0.9 * s)
	if ic:
		ic.position = gpos + Vector2(iw * 0.5, ih * 0.5)   # 앵커(0,1)=좌상단 → 중앙앵커 보정
		parent.add_child(ic)
	var lb := _bmf_label("subtitle", 0.6 * s)
	lb.text = str(value)
	lb.position = gpos + Vector2(iw + 2.0, -2.0)
	lb.size = Vector2(90, ih + 6.0)
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(lb)

## 원작 BMFont 라벨(font/font_*.fnt). GameManager::getFontName_subtitle → font_subtitle.fnt,
## getFontName_common → font_common.fnt (docs/ref/orig_code/decomp/GameManager.c:2161/2009).
const _BMF := {
	"subtitle": "res://assets/480/font/font_subtitle.fnt",
	"common": "res://assets/480/font/font_common.fnt",
	"total": "res://assets/480/font/font_total.fnt",
	# 원작 `Bicon::init` 이 버프 아이콘의 남은 턴에 쓰는 폰트(숫자 12자뿐이라 그대로 쓸 수 있다).
	"heal": "res://assets/480/font/font_heal.fnt",
}
var _bmf_cache: Dictionary = {}
func _bmf_font(kind: String) -> Font:
	if not _bmf_cache.has(kind):
		var p: String = _BMF.get(kind, _BMF["subtitle"])
		_bmf_cache[kind] = load(p) if ResourceLoader.exists(p) else null
	return _bmf_cache[kind]

func _bmf_label(kind: String, scale := 1.0) -> Label:
	var l := Label.new()
	var f := _bmf_font(kind)
	if f:
		l.add_theme_font_override("font", f)
		# BMFont 원본 크기 × scale (Cocos setScale 대응). fixed_size=0이면 32 기준.
		var base: float = float(f.fixed_size) if f.fixed_size > 0 else 32.0
		l.add_theme_font_size_override("font_size", int(round(base * scale)))
	else:
		l.add_theme_font_size_override("font_size", int(round(24.0 * scale)))
		l.add_theme_color_override("font_color", Color.WHITE)
	return l

# ---------- 파티 카드(하단) ----------
# 원작 AdventureScene::setInterfaceDragon (docs/ref/orig_code/decomp/AdventureScene.c:50024-50110):
#   1번째 = VisibleRect::leftBottom()  + (20, 128)
#   2번째 = VisibleRect::bottom()      + (-cardW*0.5, 128)      ← 화면 하단 중앙
#   3번째 = VisibleRect::rightBottom() + (-20 - cardW, 128)
#   z=400, tag 0xbc0/1/2. 등장: backSprite를 y - h*3(화면 아래)에서 MoveTo 0.7 EaseExponentialInOut.
# 좌표는 Cocos(y-up) 기준이므로 Godot y = FLOOR - 128 - cardH.
func _build_party_cards() -> void:
	var vis := _vis()
	var n := _party.size()
	if n == 0:
		return
	var S := Design.ASSET_SCALE
	var cw := float(_adv.get("scene_adventure_stat_box3", {}).get("w", 220)) * S
	var ch := float(_adv.get("scene_adventure_stat_box3", {}).get("h", 79)) * S
	# Cocos y=128 = 카드 좌하단 → Godot 좌상단 y = 화면높이 - 128 - ch.
	var cardY := vis.y - 128.0 - ch
	var xs: Array[float] = []
	match n:
		1: xs = [20.0]
		2: xs = [20.0, vis.x * 0.5 - cw * 0.5]
		_: xs = [20.0, vis.x * 0.5 - cw * 0.5, vis.x - 20.0 - cw]
	for i in n:
		_party_card(i, _party[i], xs[mini(i, xs.size() - 1)], cardY, cw, ch)

# 원작 InterFace::UI_InterFace(param_2=드래곤) — docs/ref/orig_code/decomp/InterFace.c:238-243, 745-1010.
#   backSprite = `scene/adventure/stat_box3_bg`(136×21, HP바 트랙) 앵커(0,0),
#     그 자식으로 카드 아트 `scene/adventure/stat_box3`(220×79) 앵커(0,0) @(0,0), z=2 tag=100.
#   · profile_bg  @ (50, h*0.5+3)                          (InterFace.c:313-318)
#   · 레벨 BMFont(subtitle, scale 0.75) 앵커(0,0) @ (profile_bg.x+40, h*0.5+22)   (:750-768)
#   · 이름 TTF Thonburi 17, color #353535 앵커(0,0), 레벨라벨 오른쪽                (:806-822)
#   · HP게이지 Scale9 hp_bar10, **contentSize(177,30)**(포인트) @ (97, 40)          (:828-834)
#   · 현재HP BMFont(subtitle, scale 0.8) 앵커(0,0.5) @ (w*0.5+30, h*0.5+2)          (:884-889)
#   · att_icon-hd 앵커(0,1) scale0.9 @ (w*0.5-50, h*0.5-19) / def_icon-hd @ (w*0.5+30, ")
#   · 수치 BMFont scale 0.6 @ 아이콘pos + (iconW, -10)
#   여기서 w,h = backSprite(stat_box3_bg) contentSize = 136,21 픽셀 × ASSET_SCALE.
func _party_card(idx: int, pd: Dictionary, x: float, y: float, w: float, ch: float) -> void:
	var S := Design.ASSET_SCALE
	var card := Control.new()
	card.set_meta("party_card", true)   # 검증용 표식(test_party_flow.gd 가 장수를 센다)
	# 원작 AdventureScene::setInterfaceDragon 은 세 카드를 모두 AdventureScene 자식
	# z=400 으로 붙인다(AdventureScene.c:70831, 70841, 70870, 70900).
	# 변환된 몬스터 Spine 슬롯은 내부 draw-order 때문에 z=108까지 쓰므로, 이 값을
	# 생략하면 가운데 카드가 몬스터 뒤로 들어간다.
	card.z_index = 400
	card.position = Vector2(x, y)
	card.size = Vector2(w, ch)
	card.pivot_offset = Vector2(w * 0.5, ch * 0.5)
	add_child(card)
	# 좌표 기준 = 카드 아트(stat_box3) contentSize = 220×79 px ÷ 0.75 = **293×105 포인트**.
	# ⚠️ 원작 소스의 리터럴(50/40/22/97/30/-50/-19…)은 이미 포인트 단위 → ASSET_SCALE을 곱하지 않는다.
	#    스프라이트 "그림 크기"만 ASSET_SCALE 배로 커진다(_spr(..., S)).
	# Cocos(y-up, 원점=카드 좌하단) → Godot(y-down, 원점=카드 좌상단): gy = ch - cy.
	var C := func(cx: float, cy: float) -> Vector2: return Vector2(cx, ch - cy)
	var bg := _spr("adventure_ui", "scene_adventure_stat_box3", _adv, S)
	if bg: bg.position = Vector2(w * 0.5, ch * 0.5); card.add_child(bg)
	# 슬롯별 테두리 프레임(stat_box_frame1/2/3, 227×85) — 카드보다 살짝 크게 중앙정렬.
	var frame := _spr("adventure_ui", "scene_adventure_stat_box_frame%d" % (idx % 3 + 1), _adv, S)
	if frame: frame.position = Vector2(w * 0.5, ch * 0.5); card.add_child(frame)
	var stage := Growth.portrait_stage(pd)
	# 초상 — 원작 profile_bg @ (50, h*0.5+3), 앵커 중앙.
	var ppos: Vector2 = C.call(50.0, ch * 0.5 + 3.0)
	var pbg := _spr("common_ui", "common_profile_bg", _man("common_ui"), S)
	if pbg: pbg.position = ppos; card.add_child(pbg)
	# 초상(box 이미지)은 원작 setScale(0x3f2147ae = **0.63**) — InterFace.c:535.
	var por := _portrait(int(pd["id"]), stage, 0.63 * S)
	if por: por.position = ppos; card.add_child(por)
	# 레벨 — 원작 BMFont(subtitle, scale 0.75) 앵커(0,0) @ (profile_bg.x + 40, h*0.5 + 22).
	# Cocos 앵커(0,0)=좌하단 → Godot Label(좌상단 기준)은 라벨 높이만큼 위로 올린다.
	# ⚠️ "레벨" 접두는 TTF로 낸다: Godot 4.7 BMFont 임포터가 원작 .fnt의 한글 1160자를 읽지 못한다
	#    (FontFile.get_supported_chars() 길이 96 = ASCII만, has_char(0xB808 '레')=false.
	#     .fnt 파일 자체에는 `char id=47112` 존재). 숫자는 정상 → 원작이 BMFont를 쓰는
	#     HP/공/방/데미지/레벨 **수치**는 전부 원작 폰트를 그대로 쓴다.
	var lv_org: Vector2 = C.call(ppos.x + 40.0, ch * 0.5 + 22.0) - Vector2(0, 22.0)
	var lvk := Label.new()
	lvk.text = "레벨"
	lvk.add_theme_font_size_override("font_size", 15)
	lvk.add_theme_color_override("font_color", Color8(0x35, 0x35, 0x35))
	lvk.position = lv_org + Vector2(0, 4.0)
	card.add_child(lvk)
	var lv := _bmf_label("subtitle", 0.75 * S)
	lv.text = "%d" % int(pd["level"])
	lv.add_theme_color_override("font_color", Color8(0x35, 0x35, 0x35))
	lv.position = lv_org + Vector2(32.0, 0.0)
	card.add_child(lv)
	# 이름 TTF Thonburi 17 #353535 — 레벨 라벨 오른쪽(원작 :806-822).
	var nm := Label.new()
	nm.text = String(pd["name"])
	nm.add_theme_font_size_override("font_size", 17)
	nm.add_theme_color_override("font_color", Color8(0x35, 0x35, 0x35))
	nm.position = lv_org + Vector2(66.0, 3.0)
	card.add_child(nm)
	# HP 게이지 — 원작 Scale9 hp_bar10 contentSize(177,30) 앵커(0,0) @ (97,40).
	var bar_w := 177.0
	var bar_h := 30.0
	var bar_org: Vector2 = C.call(97.0, 40.0 + bar_h)   # Cocos 좌하단 → Godot 좌상단
	var hbg := _spr("adventure_ui", "scene_adventure_stat_box3_bg", _adv, S)
	if hbg:
		hbg.position = bar_org + Vector2(bar_w * 0.5, bar_h * 0.5)
		card.add_child(hbg)
	var hfl := _hp_fill(bar_w - 10.0, bar_h - 14.0)
	hfl.position = bar_org + Vector2(5.0, 7.0)
	card.add_child(hfl)
	var hp := _bmf_label("subtitle", 0.8 * S)
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp.size = Vector2(bar_w, bar_h); hp.position = bar_org
	card.add_child(hp)
	# 공/방 — 원작 att @ (w*0.5-50, h*0.5-19), def @ (w*0.5+30, h*0.5-19), 앵커(0,1).
	var ay := ch * 0.5 - 19.0
	_stat_icon_ui(card, "scene_adventure_att_icon-hd", int(pd["stats"].get("att", 0)),
		C.call(w * 0.5 - 50.0, ay), S)
	_stat_icon_ui(card, "scene_adventure_def_icon-hd", int(pd["stats"].get("def", 0)),
		C.call(w * 0.5 + 30.0, ay), S)
	# 각성 게이지(원작 super attack 충전) — **숨긴 게이지**.
	# 사용자 지시(2026-07-27): 시스템(충전·발동)은 그대로 두되 유저에게는 보이지 않는다.
	#   원작 카드에도 이 노란 바는 없다 — 우리가 디버그용으로 그려 두었던 것.
	#   `_set_gauge` 가 계속 이 노드의 size 를 갱신하므로 노드는 남기고 visible 만 끈다.
	var gauge_w := w - 100.0
	var gfl := ColorRect.new(); gfl.color = Color(1, 0.8, 0.25)
	gfl.size = Vector2(0, 5); gfl.position = Vector2(97.0, ch - 12.0)
	gfl.visible = false
	card.add_child(gfl)
	var v := {"kind": "party", "node": card, "center": Vector2(x + w * 0.5, y - 10),
		"base_pos": Vector2(x, y), "alive": true, "element": String(pd.get("element", "")),
		# 원작 파티 Bicon은 각 카드 좌상단 바로 위에서 오른쪽으로 늘어난다
		# (docs/ref/adventure/보스승리1.png).
		"bicon_origin": Vector2(x + 42.0, y - 26.0),
		# 🔴 2026-07-27 수정: 여기에 `id`/`awakened`/`voice_critical`/`critical_hit` 이 빠져 있었다.
		#   재생 코드(`_play_event`)는 `_views` 의 이 dict 를 크리티컬 연출에 그대로 넘기므로
		#   `caster.get("id", 0)` 이 **0** 이 되어 `critical_0` 아틀라스를 찾다 실패했다:
		#     · `_critical_art` — 폴백이 없어 **화면 전체 아트가 아예 안 떴다**(사용자 신고 증상)
		#     · `_critical_cutin` — 얼굴만 dragon_1 폴백(Cutin.c:699)으로 떠서 **컷인은 보였다**
		#       (단 어떤 드래곤이든 1번 얼굴이었다)
		#     · `_crit_voice`/`_crit_hits` — 드래곤별 값 대신 항상 폴백 경로
		#   `_party[idx]`(=pd) 는 이 값들을 이미 갖고 있다(:180-196) → 뷰로 전달만 하면 된다.
		"id": int(pd.get("id", 0)), "awakened": bool(pd.get("awakened", false)),
		"voice_critical": int(pd.get("voice_critical", 0)),
		"critical_hit": int(pd.get("critical_hit", 0)),
		"hp": int(pd["hp"]), "hp_max": int(pd["hp_max"]),
		"hp_fill": hfl, "hp_label": hp, "bar_w": bar_w - 8.0, "bar_x": bar_org.x, "bar_local": true,
		"gauge": 0.0, "gauge_fill": gfl, "gauge_w": gauge_w}
	_views["A%d" % idx] = v
	_refresh_bar(v)
	# 원작 등장: 카드가 화면 아래(y - h*3)에서 0.7s EaseExponentialInOut로 올라온다.
	card.position.y = y + ch * 3.0
	create_tween().tween_property(card, "position:y", y, 0.7)\
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)

## _stat_icon의 Control(카드) 버전.
func _stat_icon_ui(parent: Control, frame: String, value: int, gpos: Vector2, s: float) -> void:
	var info: Dictionary = _adv.get(frame, {})
	var iw := float(info.get("w", 21)) * 0.9 * s
	var ih := float(info.get("h", 21)) * 0.9 * s
	var ic := _spr("adventure_ui", frame, _adv, 0.9 * s)
	if ic:
		ic.position = gpos + Vector2(iw * 0.5, ih * 0.5)
		parent.add_child(ic)
	var lb := _bmf_label("subtitle", 0.6 * s)
	lb.text = str(value)
	lb.position = gpos + Vector2(iw + 2.0, -1.0)
	lb.size = Vector2(80, ih + 6.0)
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(lb)

# ---------- HUD ----------
func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.layer = 10
	add_child(hud)
	var vis := _vis()
	# 원작 HUD 버튼 이미지(scene/adventure/auto·speed_N·bt_skip_kr). 회전 아틀라스라 _spr(자동 -90° 복원) 사용.
	var autob := _img_button("scene_adventure_auto", Vector2(74, 30))
	autob.position = Vector2(16, 12); autob.toggle_mode = true; autob.button_pressed = true
	hud.add_child(autob)
	# 속도(=원작 FF) 버튼 — 원작 setFastBattleButton: **VisibleRect::right() 기준 안쪽 100**,
	# 즉 우측 가장자리 **세로 중앙**. (docs/ref/orig_code/decomp/AdventureScene.c:47144 VisibleRect::right + (100,0),
	#  프레임 scene/adventure/speed_0 ↔ speed_2 토글, z=999999 tag=0x6a)
	# 레퍼런스 docs/ref/orig_image/battle/몬스터피격.png의 ▶▶ 위치(우측, 화면 세로 중앙)와 일치.
	var S := Design.ASSET_SCALE
	var fw := 74.0 * S
	var fh := 40.0 * S
	_speed_btn = _img_button("scene_adventure_speed_0", Vector2(fw, fh), S)
	_speed_btn.position = Vector2(vis.x - 100.0 - fw * 0.5, vis.y * 0.5 - fh * 0.5)
	_speed_btn.pressed.connect(_cycle_speed)
	if _speed_btn.get_child_count() > 0: _speed_spr = _speed_btn.get_child(0) as Sprite2D
	hud.add_child(_speed_btn)
	var skip := _img_button("scene_adventure_bt_skip_kr", Vector2(74, 32))
	skip.position = Vector2(vis.x - 90, vis.y * 0.5 + fh)
	skip.pressed.connect(func(): _skip = true)
	hud.add_child(skip)
	# 전투 메뉴(원작 `onClickBattleMenu` → PopAutoSettingLayer) 진입 버튼.
	# 🔴 2026-07-31 교체: 종전엔 `⚙` **텍스트 글리프 버튼**이었다(자작).
	#   원작 아이콘을 찾았다 — `AdventureScene::setEventFightEnd` 가
	#   `CCMenuItemImageEx::create(CCSprite("common/icon_sword1.png"), onClickBattleMenu, 1.05)` 로 만든다.
	#   좌표도 그 함수 그대로: `VisibleRect::right()` 기준 **x-150**, **y = H*0.75**(cocos), tag 0x83.
	#   등장 안무 `Spawn(ScaleTo(0.5,2.0), FadeTo(0.5,255))` → `ScaleTo(1.0, 1.5)` 이라 상주 크기는 **1.5**.
	var sw: Dictionary = _man("common_ui")
	var sword := _img_button_from("common_ui", "common_icon_sword1", sw, 1.5 * S)
	if sword:
		sword.position = Vector2(vis.x - 150.0 - sword.size.x * 0.5,
			Design.flip_y(vis.y * 0.75, vis.y) - sword.size.y * 0.5)
		sword.pressed.connect(_open_battle_settings)
		hud.add_child(sword)
	# 🔴 2026-07-31 제거: "ROUND N" 라벨은 **자작**이었다. 원작 전투 HUD 에 라운드 표시가 없다 —
	#   문자열 테이블에 `ROUND`/`라운드` 0건이고 AdventureScene 359메서드 어디에도 턴 카운터
	#   표시가 없다(전량 디컴파일, [skip>8000] 0건). 턴 전환은 텍스트박스 문구로만 알린다.
	_build_exp_panel(hud)
	_build_mission_labels(hud)
	_log("%s 이(가) 나타났다!" % String(_enemy["name"]))

# ---------- EXP 패널(좌상단) + 전투 미션 ----------
## 원작 AdventureScene::setExpAddIcon (docs/ref/orig_code/decomp/AdventureScene.c:46555-46700):
##   · 배경 = **CCScale9Sprite** `scene/colosseum/week_time_bg.png`, contentSize **(190, 30)**,
##     앵커(0,0.5) @ (visW*0.03, visH*0.85), z=123 tag=123        (AdventureScene.c:46633-46645)
##   · 날개 EXP 아트 `scene/adventure/bonus_exp_mini(2).png` 앵커(0,0.5) @ (-10, h*0.5 + 5)
##     ← 배경 왼쪽으로 삐져나온다(레퍼런스 docs/ref/orig_image/battle/몬스터피격.png 그대로)
##   · 획득 EXP = BMFont 앵커(1,0.5) @ (w-10, h*0.5+2)
## Cocos y-up(0.85=위쪽) → Godot y = visH*(1-0.85) = visH*0.15.
const _EXP_PANEL := Vector2(190.0, 30.0)
var _exp_label: Label
var _exp_gained := 0
func _build_exp_panel(hud: CanvasLayer) -> void:
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var w := _EXP_PANEL.x
	var h := _EXP_PANEL.y
	var root := Control.new()
	root.position = Vector2(vis.x * 0.03, vis.y * 0.15 - h * 0.5)   # 앵커(0,0.5) 보정
	root.size = Vector2(w, h)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)
	var bg := NinePatchRect.new()
	bg.texture = load("res://assets/converted/colosseum_ui/scene_colosseum_week_time_bg.tres")
	bg.patch_margin_left = 10; bg.patch_margin_right = 10
	bg.patch_margin_top = 6; bg.patch_margin_bottom = 6
	bg.size = Vector2(w, h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	# 날개 EXP 아트 — 원작 `setExpAddIcon` 은 **두 장을 같은 자리에 겹쳐** 붙인다:
	#   ① `bonus_exp_mini2.png` 를 먼저(뒤) ② `bonus_exp_mini.png` 를 나중(앞)
	#   둘 다 앵커(0,0.5) @ (-10, h*0.5 + 5). 종전엔 ②만 그려서 뒷장이 빠져 있었다(2026-07-31 보강).
	for key in ["scene_adventure_bonus_exp_mini2", "scene_adventure_bonus_exp_mini"]:
		var wing := _spr("adventure_ui", key, _adv, S)
		if wing == null:
			continue
		var wi: Dictionary = _adv.get(key, {})
		wing.position = Vector2(-10.0 + float(wi.get("w", 64)) * S * 0.5, h * 0.5 - 5.0)
		root.add_child(wing)
	_exp_label = _bmf_label("subtitle", S)
	_exp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_exp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_exp_label.size = Vector2(w - 10.0, h); _exp_label.position = Vector2(0, -2.0)
	_exp_label.text = "0"
	root.add_child(_exp_label)

## 원작 QuestAndBattleLabel 행(전투 미션). EXP 패널 바로 아래로 두 줄.
## 근거: QuestAndBattleLabel.c:459-700 —
##   Scale9 `scene/adventure/quest_shadow.png` capInsets(10,10,4,4) 앵커(0,0.5), contentSize(…,60),
##   `common/profile_bg.png` scale 0.5 @ (40,h/2) + `common/checked.png` 같은 자리(달성 시 표시),
##   제목 TTF Thonburi 22 #f6f6f6 @ (80,h/2), 카운트 BMFont "[cur/max]" 색 #d65f5f scale 0.8,
##   보상 아이콘 + 보상 텍스트 TTF 22.
## 진입 연출: 화면 위에서 MoveBy 0.5s EaseExponentialInOut (AdventureScene.c:53500-53525).
var _mission_rows: Array = []      # [{def, cnt_label, check}]
var _missions: Array = []
const _MISSION_ROW_H := 60.0
func _build_mission_labels(hud: CanvasLayer) -> void:
	var defs: Dictionary = Data.battle_missions
	if defs.is_empty(): return
	var rng := RandomNumberGenerator.new(); rng.randomize()
	_missions = BattleMission.pick(defs, rng)
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var top := vis.y * 0.15 + 22.0
	var bw := 400.0
	for i in _missions.size():
		var m: Dictionary = _missions[i]
		var y := top + i * _MISSION_ROW_H
		var row := NinePatchRect.new()
		row.texture = load("res://assets/converted/adventure_ui/scene_adventure_quest_shadow.tres")
		row.patch_margin_left = 10; row.patch_margin_right = 10
		row.patch_margin_top = 4; row.patch_margin_bottom = 4
		row.size = Vector2(bw, _MISSION_ROW_H)
		row.position = Vector2(vis.x * 0.03, y)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(row)
		# 체크박스(원작 profile_bg + checked) @ x=40
		var pbg := _spr("common_ui", "common_profile_bg", _man("common_ui"), 0.5 * S)
		if pbg: pbg.position = Vector2(40, _MISSION_ROW_H * 0.5); row.add_child(pbg)
		var chk := _spr("common_ui", "common_checked", _man("common_ui"), 0.9 * S)
		if chk:
			chk.position = Vector2(40, _MISSION_ROW_H * 0.5); chk.visible = false
			row.add_child(chk)
		# 제목 TTF 22 #f6f6f6 @ x=80
		var t := Label.new()
		t.text = String(m.get("text", ""))
		t.add_theme_font_size_override("font_size", 22)
		t.add_theme_color_override("font_color", Color8(0xf6, 0xf6, 0xf6))
		t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		t.position = Vector2(80, 0); t.size = Vector2(200, _MISSION_ROW_H)
		row.add_child(t)
		# 카운트 BMFont [0/N] — 원작 색 #d65f5f, scale 0.8
		var cnt := _bmf_label("subtitle", 0.8 * S)
		cnt.text = "[0/%d]" % int(m.get("goal", 1))
		cnt.add_theme_color_override("font_color", Color8(0xd6, 0x5f, 0x5f))
		cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cnt.position = Vector2(250, 0); cnt.size = Vector2(90, _MISSION_ROW_H)
		row.add_child(cnt)
		# 보상: 원작 EXP 아이콘 + "+NN%"
		var ico := _spr("adventure_ui", "scene_adventure_bonus_exp_mini", _adv, 0.85 * S)
		if ico: ico.position = Vector2(bw - 110, _MISSION_ROW_H * 0.5); row.add_child(ico)
		var rw := Label.new()
		rw.text = "+%d%%" % int(round(float(m.get("exp_bonus", 0.0)) * 100.0))
		rw.add_theme_font_size_override("font_size", 22)
		rw.add_theme_color_override("font_color", Color8(0xf6, 0xf6, 0xf6))
		rw.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rw.position = Vector2(bw - 76, 0); rw.size = Vector2(70, _MISSION_ROW_H)
		row.add_child(rw)
		_mission_rows.append({"def": m, "cnt": cnt, "check": chk})
		# 원작 진입: 화면 위에서 0.5s EaseExponentialInOut로 내려온다.
		row.position.y = y - vis.y * 0.5
		create_tween().tween_property(row, "position:y", y, 0.5)\
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)

## 재생 중 누적 이벤트로 미션 진행도 갱신(판정은 logic 층 BattleMission).
func _update_missions(played: Array) -> void:
	if _mission_rows.is_empty(): return
	var names: Array = []
	for p in _party: names.append(String(p.get("name", "")))
	var prog: Array = BattleMission.evaluate(_missions, played, names)
	for i in mini(prog.size(), _mission_rows.size()):
		var r: Dictionary = _mission_rows[i]
		var p: Dictionary = prog[i]
		var cl = r.get("cnt")
		if is_instance_valid(cl):
			(cl as Label).text = "[%d/%d]" % [int(p["count"]), int((p["mission"] as Dictionary).get("goal", 1))]
		var ck = r.get("check")
		if is_instance_valid(ck):
			(ck as Sprite2D).visible = bool(p["done"])

var _auto := true
var _settings_layer: CanvasLayer
## 원작 PopAutoSettingLayer 1:1: popup4 + pop_title_bg + close_btn + 체크박스(자동전투) + arrow(속도/반복횟수).
## 근거: PopAutoSettingLayer.c makeBaseUI(popup4/pop_title_bg/close_btn)+initBattleFight(자동전투)+
##   initAdvCount(반복횟수 arrow, max 50)+onClickCheck/onClickArrow. ⚠️라벨=StringManager 유실→기능명 사용(ASSUMPTION).
func _open_battle_settings() -> void:
	if is_instance_valid(_settings_layer):
		return
	var vis := _vis()
	_settings_layer = CanvasLayer.new(); _settings_layer.layer = 70; add_child(_settings_layer)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.6); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_layer.add_child(dim)
	const BW := 460.0
	const BH := 330.0
	var win := NinePatchRect.new()
	win.texture = load("res://assets/converted/ninepatch_ui/9patch_popup4.tres")
	win.patch_margin_left = 130; win.patch_margin_top = 190; win.patch_margin_right = 55; win.patch_margin_bottom = 81
	win.size = Vector2(BW, BH); win.position = Vector2(round((vis.x - BW) * 0.5), round((vis.y - BH) * 0.5))
	_settings_layer.add_child(win)
	var tbar := NinePatchRect.new()
	tbar.texture = load("res://assets/converted/ninepatch_ui/9patch_pop_title_bg.tres")
	tbar.patch_margin_left = 20; tbar.patch_margin_right = 20; tbar.patch_margin_top = 12; tbar.patch_margin_bottom = 12
	tbar.size = Vector2(300, 52); tbar.position = Vector2((BW - 300) * 0.5, 12); win.add_child(tbar)
	var title := Label.new(); title.text = "자동 설정"
	title.add_theme_font_size_override("font_size", 28); title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size = tbar.size; tbar.add_child(title)
	var xb := TextureButton.new(); xb.texture_normal = load("res://assets/converted/common_ui/common_close_btn.tres")
	xb.position = Vector2(BW - 58, 14); xb.pressed.connect(_close_battle_settings); win.add_child(xb)
	# 행1: 자동 전투(체크 토글). 원작 initBattleFight + checkbox_on/off(scene/guild 미변환→토글 대체).
	_setting_row(win, "자동 전투", 88, func() -> String: return "켜짐" if _auto else "꺼짐",
		func(): _auto = not _auto)
	# 행2: 전투 속도(arrow, x1/x2/x4). 우리 _speed 구동.
	_setting_arrow_row(win, "전투 속도", 148, func() -> String: return "x%d" % int(_speed),
		func(d: int): _cycle_speed())
	# 행3: 반복 횟수(arrow 1~50). 원작 initAdvCount max 50 → UserDB pmeta adv_repeat 저장.
	_setting_arrow_row(win, "반복 횟수", 208, func() -> String: return "%d회" % int(UserDB.get_pmeta("adv_repeat", 1)),
		func(d: int): UserDB.set_pmeta("adv_repeat", clampi(int(UserDB.get_pmeta("adv_repeat", 1)) + d, 1, 50)))
	var ok := Button.new(); ok.text = "확인"; ok.size = Vector2(160, 44); ok.position = Vector2((BW - 160) * 0.5, BH - 62)
	ok.pressed.connect(_close_battle_settings); win.add_child(ok)

func _close_battle_settings() -> void:
	if is_instance_valid(_settings_layer): _settings_layer.queue_free(); _settings_layer = null

func _setting_row(win: Control, label: String, y: float, val: Callable, toggle: Callable) -> void:
	var lb := Label.new(); lb.text = label; lb.add_theme_font_size_override("font_size", 22)
	lb.add_theme_color_override("font_color", Color(0.28, 0.18, 0.05)); lb.position = Vector2(150, y); lb.size = Vector2(160, 30)
	win.add_child(lb)
	var b := Button.new(); b.size = Vector2(96, 34); b.position = Vector2(300, y - 2); b.text = String(val.call())
	b.pressed.connect(func(): toggle.call(); b.text = String(val.call())); win.add_child(b)

func _setting_arrow_row(win: Control, label: String, y: float, val: Callable, adj: Callable) -> void:
	var lb := Label.new(); lb.text = label; lb.add_theme_font_size_override("font_size", 22)
	lb.add_theme_color_override("font_color", Color(0.28, 0.18, 0.05)); lb.position = Vector2(150, y); lb.size = Vector2(150, 30)
	win.add_child(lb)
	var vlb := Label.new(); vlb.add_theme_font_size_override("font_size", 22)
	vlb.add_theme_color_override("font_color", Color(0.3, 0.2, 0.05)); vlb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vlb.position = Vector2(316, y); vlb.size = Vector2(70, 30)
	var upd := func(): vlb.text = String(val.call())
	upd.call()
	# 원작 common/btn_arrow1(좌)/btn_arrow2(우).
	var la := TextureButton.new(); la.texture_normal = load("res://assets/converted/common_ui/common_btn_arrow1.tres")
	la.position = Vector2(300, y - 2); la.pressed.connect(func(): adj.call(-1); upd.call()); win.add_child(la)
	var ra := TextureButton.new(); ra.texture_normal = load("res://assets/converted/common_ui/common_btn_arrow2.tres")
	ra.position = Vector2(388, y - 2); ra.pressed.connect(func(): adj.call(1); upd.call()); win.add_child(ra)
	win.add_child(vlb)

func _cycle_speed() -> void:
	_speed = {1.0: 2.0, 2.0: 4.0, 4.0: 1.0}[_speed]
	# 원작 speed_0/1/2 이미지 전환(x1/x2/x4).
	var idx: int = {1.0: 0, 2.0: 1, 4.0: 2}[_speed]
	if is_instance_valid(_speed_spr):
		var p := "res://assets/converted/adventure_ui/scene_adventure_speed_%d.tres" % idx
		if ResourceLoader.exists(p): _speed_spr.texture = load(p)
	else:
		_speed_btn.text = "▶ x%d" % int(_speed)

## 원작 BattleTextBox — 화면 하단 전폭 대화상자. 전투 로그는 전부 여기로 나간다.
## 근거: docs/ref/orig_code/decomp/BattleTextBox.c:167-205
##   · Scale9 `9patch/dialogue_box.png` capInsets Rect(10,10,4,4), 앵커(0,0), 박스 z=100
##   · 박스 앵커(0.5, 0.0) @ VisibleRect::bottom() → 하단 중앙
##   · contentSize = (visibleRect.width - 10, **120**)   ← 포인트 단위(ASSET_SCALE 미적용)
##   · CCLabelTTF("", "Thonburi", **28**) 좌정렬, dimensions(width-20, 0) 워드랩,
##     앵커(0, 0.5) @ (10, height*0.5 - 2), 흰색, z=200
## 레퍼런스 실측(docs/ref/orig_image/battle/몬스터싸움.png): 하단 박스 높이 123px / (735/692) = 119 디자인px ✓
const _TEXTBOX_H := 120.0
func _build_textbox() -> void:
	var vis := _vis()
	var lay := CanvasLayer.new(); lay.layer = 8
	add_child(lay)
	var box := NinePatchRect.new()
	box.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres")
	box.patch_margin_left = 10; box.patch_margin_right = 10
	box.patch_margin_top = 4; box.patch_margin_bottom = 4
	box.size = Vector2(vis.x - 10.0, _TEXTBOX_H)
	box.position = Vector2(5.0, vis.y - _TEXTBOX_H)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lay.add_child(box)
	_log_label = Label.new()
	_log_label.add_theme_font_size_override("font_size", 28)
	_log_label.add_theme_color_override("font_color", Color.WHITE)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_log_label.size = Vector2(box.size.x - 20.0, _TEXTBOX_H - 8.0)
	_log_label.position = Vector2(10.0, 4.0)
	_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_log_label)
	if _pending_log != "":
		_log_label.text = _pending_log

var _pending_log := ""
func _log(msg: String) -> void:
	_pending_log = msg
	if _log_label:
		_log_label.text = msg

## 원작 `탐험끝.png`: 종료 문구 뒤에는 자작 텍스트 버튼이 아니라 BattleTextBox 우하단의
## `btn_arrow2`만 표시되고, 그 화살표를 눌러 탐험에서 빠져나간다.
func _show_finish_arrow(region: String) -> void:
	if not is_instance_valid(_log_label):
		Scenes.goto("worldmap", {"region": region})
		return
	var box := _log_label.get_parent() as Control
	if box == null:
		Scenes.goto("worldmap", {"region": region})
		return
	var arrow := TextureButton.new()
	arrow.texture_normal = load("res://assets/converted/common_ui/common_btn_arrow2.tres")
	arrow.position = Vector2(box.size.x - 62.0, box.size.y - 58.0)
	arrow.pressed.connect(func(): Scenes.goto("worldmap", {"region": region}))
	box.add_child(arrow)
	# 원작 탐험 종료 상태는 화살표가 다음 클릭을 안내하는 텍스트 진행 상태다.
	# 작은 화살표만 정확히 누르지 않아도 화면 클릭으로 지역을 벗어나도록,
	# BattleTextBox 위 전체에 투명 탭 캐처를 둔다. LevelUpScreen(layer 30)보다 아래다.
	var tap_layer := CanvasLayer.new()
	tap_layer.layer = 9
	tap_layer.set_meta("finish_click_catcher", true)
	add_child(tap_layer)
	var tap := Button.new()
	tap.flat = true
	tap.focus_mode = Control.FOCUS_NONE
	tap.position = Vector2.ZERO
	tap.size = _vis()
	tap.pressed.connect(func(): Scenes.goto("worldmap", {"region": region}))
	tap_layer.add_child(tap)

# ---------- 전투 실행 + 재생 ----------
func _run_and_replay() -> void:
	# combatant 조립(내부이름 A0../E0로 뷰 매핑). 파티=ally, 적=enemy.
	var pa: Array = []
	for i in _party.size():
		var pd: Dictionary = _party[i]
		var c := Battle.make_combatant("A%d" % i, "ally", String(pd["element"]),
			pd["stats"], 0.0, pd.get("skills", []))
		c["hp"] = int(pd["hp"]); c["hp_max"] = int(pd["hp_max"])
		# 각성 스킬 효과는 `_apply_awaken_skills`(카드 생성 전)가 이미 산출해 뒀다.
		# 체력은 `_party` 값에 이미 반영돼 있고, 나머지는 효과 목록으로 옮긴다.
		c["awaken_no"] = int(pd.get("awaken_skill", 0))
		c["grade"] = float(pd.get("grade", 0.0))
		c["dragon_id"] = int(pd.get("id", 0))
		c["atk_type"] = String(pd.get("atk_type", ""))
		c["awaken_gauge"] = float(pd.get("awaken_gauge", 0.0))   # 97 하얀매의 친구
		for e in (pd.get("awaken_effects", []) as Array):
			(c["effects"] as Array).append((e as Dictionary).duplicate())
		pa.append(c)
	var eb := Battle.make_combatant("E0", "enemy", String(_enemy["element"]),
		{"hp": int(_enemy["hp_max"]), "att": int(_enemy["att"]), "def": int(_enemy["def"]), "cri": 8, "evd": 6, "blk": 8},
		0.0, _enemy_skills())
	_apply_boss_phase(eb)
	var pb: Array = [eb]
	if pa.is_empty():
		_log("출전할 드래곤이 없습니다."); return
	# 스킬 봉인 던전(원작 우노 '미지의 터'). 위키 dungeon_4.pdf §4.2:
	# "알수없는 기운으로 인해 드래곤들이 스킬을 사용할수 없다" → 스킬 DB 를 비운 채 시뮬레이션한다.
	# (드래곤의 스킬 장착은 그대로 두고 **발동만** 막는다 — 상태 변화가 아니라 이 전투 한정 규칙.)
	var st_now: Dictionary = _stage_rec()
	var skills_db: Dictionary = {} if bool(st_now.get("no_skills", false)) else Data.skills
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var res := Battle.simulate(pa, pb, rng, Data.combat, skills_db)
	_events = res.get("events", [])
	_winner = String(res.get("winner", "draw"))
	_play_events()

## 재생 세대(generation). `_rebuild()` 가 증가시키고, 재생 코루틴은 매 await 뒤에 자기 세대를
## 확인해 낡았으면 즉시 빠진다.
## 🔴 근거(2026-07-27 실제 버그): 씬이 두 번 빌드되면(당시 Scenes.goto 순서 문제) 1차 빌드의
##   이 코루틴이 살아남아 **2차 빌드의 이벤트 배열을 같이 재생**했다. `_views` 는 멤버라
##   같은 뷰를 두 코루틴이 때려 뷰 HP가 두 배로 깎였고, 몬스터 HP 표시가 0인데 로직상은
##   살아 있어 전투가 계속됐다. 근본원인은 scene_manager 에서 고쳤고 이건 이중 안전장치다.
var _gen := 0
func _play_events() -> void:
	var gen := _gen
	_playing = true
	_battle_opening()          # 원작 OpeningBattleScene: 전투 시작 배너 스윕
	await _wait(1.0)
	if gen != _gen: return
	var played: Array = []
	for ev in _events:
		_play_event(ev)
		played.append(ev)
		_update_missions(played)      # 원작 QuestAndBattleLabel 카운트 실시간 갱신
		await _wait(_evt_delay(ev))
		if gen != _gen: return
	await _wait(0.3)
	if gen != _gen: return
	_finish()
	_playing = false

func _evt_delay(ev: Dictionary) -> float:
	var t := String(ev.get("type", ""))
	if t == "effect_tick":
		return 0.01
	if t == "status_skip":
		return 0.35
	# 각성기는 타수만큼 이벤트가 온다 — 한 발치 간격을 타수로 나눠 총 길이를 유지한다
	# (안 나누면 바람 46타×대상 = 수십 초). `volley` = 이번 발동의 전체 이벤트 수.
	if t == "awaken":
		return 1.2 / maxf(1.0, float(ev.get("volley", 1)))
	# 크리티컬은 컷인(막+밴드+얼굴) → 연타 → 화면 전체 아트까지 약 0.7초가 더 붙는다.
	# 기본 간격 0.6 그대로 두면 다음 이벤트가 아트 위로 겹쳐 들어온다.
	if bool(ev.get("crit", false)):
		return 1.3
	return 0.6

var _cur_round := 0

func _play_event(ev: Dictionary) -> void:
	# 라운드는 내부 상태로만 센다 — 화면 표시는 없다(위 _build_hud 의 제거 사유 참조).
	if ev.has("round") and int(ev["round"]) != _cur_round:
		_cur_round = int(ev["round"])
	match String(ev.get("type", "")):
		"normal", "double", "awaken":
			var atk: Dictionary = _find(String(ev.get("attacker", "")))
			var dfn: Dictionary = _find(String(ev.get("defender", "")))
			if String(ev.get("type", "")) == "awaken":
				# 🟦 2026-08-06 — 각성기는 **타수만큼** 이벤트로 온다(`Battle.resolve_awaken`,
				#   원작 `calculateDamage` 분할). 발동 연출·게이지 리셋은 첫 이벤트에서 한 번만.
				#   종전엔 여기가 대상 수만큼 돌아 배너·플래시가 겹쳐 떴다.
				if bool(ev.get("volley_lead", false)):
					_super_attack_fx(atk)   # 원작 setSuperAttackStart: 각성기 발동 연출
			# 🟦 2026-08-06 — 게이지는 **진영 공유**이고 행동·피격·react 가 함께 올린다.
			#   화면이 자체 추정하면 반드시 어긋나므로 `simulate` 가 이벤트에 실어 준 실값을 쓴다.
			_sync_gauge(ev)
			var is_crit := bool(ev.get("crit", false)) and int(ev.get("damage", 0)) > 0
			if not atk.is_empty(): _cue(atk, is_crit)
			if bool(ev.get("miss", false)):
				# 회피 효과음 — 원작 `music/effect_evade.mp3`(실재). 전투 씬이
				# `MakeInterface::preloadHeavyResource`(MakeInterface.c:37956)로 올려 두는 음원이다.
				Bgm.sfx("effect_evade")
				_fx_text(dfn, "battle_miss_kr", "MISS", Color(0.8, 0.8, 0.8), "scene_adventure_txt_miss")
				_log("%s의 공격 — 빗나감!" % _disp(ev.get("attacker", "")))
			else:
				if int(ev.get("damage", 0)) > 0:
					# 크리티컬 시퀀스 = 드래곤 음성 + 컷인 → hit 타격 연타 → 화면 전체 아트.
					# 근거·재구성 경위는 `_critical_sequence` 주석 참조. 아군 크리에서만 낸다(원작도 내 얼굴을 띄운다).
					if is_crit and String(atk.get("kind", "")) == "party":
						# ⚠️ **await 필수** — 안 기다리면 데미지 숫자·파티클·의성어가 컷인과 동시에 터지고
						#   실제 타격은 0.5초 뒤에 들어와 순서가 뒤집힌다(2026-07-27 발견·수정).
						#   `_play_event` 는 재생 루프가 await 없이 부르므로 여기서 기다려도 루프는 안 막힌다.
						await _critical_sequence(atk, dfn)
						_log("%s 크리티컬 발동~!" % _disp(ev.get("attacker", "")))
					elif not (is_crit and String(atk.get("kind", "")) == "enemy"):
						_strike(dfn, false, 1)
					# 몬스터가 맞았을 때만 붓글씨 의성어(원작 monster/hit_talk) — 몬스터의 비명이다.
					if String(dfn.get("kind", "")) == "enemy":
						_hit_talk()
					_hurt(dfn, int(ev["damage"]), is_crit)
					_attr_particles(dfn, String(atk.get("element", "")), is_crit, int(atk.get("voice_critical", 0)))
				if bool(ev.get("block", false)):
					_fx_text(dfn, "battle_block_kr", "BLOCK", Color(0.6, 0.8, 1.0)); Bgm.sfx("effect_block")
				_shield_impact(dfn, int(ev.get("def_skill_id", 0)))   # 원작 setCheckShildImpact
				if bool(ev.get("dead", false)): _kill(dfn)
				if int(ev.get("lifesteal", 0)) > 0:
					_vamp_impact(dfn, atk)          # 원작 setVampImpact
					_heal(atk, int(ev["lifesteal"]))
				if int(ev.get("reflect", 0)) > 0:
					_hurt(atk, int(ev["reflect"]), false)
					if bool(ev.get("reflect_dead", false)): _kill(atk)
				# 쓰러진 경우 _kill 이 원작 격파 서사를 이미 넣었다 → 피해 줄로 덮어쓰지 않는다.
				if not bool(ev.get("dead", false)):
					_log("%s → %s  %d 피해%s" % [_disp(ev.get("attacker", "")), _disp(ev.get("defender", "")),
						int(ev.get("damage", 0)), ("  치명타!" if ev.get("crit", false) else "")])
		"skill":
			_play_skill(ev)
		"confused":
			var a: Dictionary = _find(String(ev.get("actor", "")))
			_hurt(a, int(ev.get("damage", 0)), false)
			if bool(ev.get("dead", false)): _kill(a)
			_log("%s 혼란 — 자해 %d" % [_disp(ev.get("actor", "")), int(ev.get("damage", 0))])
		"dot", "timed":
			var tg: Dictionary = _find(String(ev.get("target", "")))
			_hurt(tg, int(ev.get("damage", 0)), false)
			_bicon_add(tg, int(ev.get("source", 0)), false, int(ev.get("turns", 0)))   # 지속피해 = 디버프
			_burning_fx(tg)   # 원작 setViewBurningEffect: 지속피해 화염 연출
			if bool(ev.get("dead", false)): _kill(tg)
			_log("%s 지속피해 %d" % [_disp(ev.get("target", "")), int(ev.get("damage", 0))])
		"status_skip":
			_bicon_add(_find(String(ev.get("actor", ""))), int(ev.get("source", 0)), false, int(ev.get("turns", 0)))
			_log("%s 행동불가!" % _disp(ev.get("actor", "")))
		"effect_tick":
			_bicon_tick(_find(String(ev.get("target", ""))), int(ev.get("source", 0)),
				int(ev.get("turns", 0)))

## 스킬 이벤트 연출(증분 3). 공격형=피해, 힐/디버프/정화 각 표시. per-드래곤 spine은 폴리시 TODO.
func _play_skill(ev: Dictionary) -> void:
	var caster: Dictionary = _find(String(ev.get("caster", "")))
	_sync_gauge(ev)         # 진영 게이지는 simulate 실값으로 그린다(§_sync_gauge)
	if not caster.is_empty(): _cue(caster)
	var sname := String(ev.get("skill_name", "스킬"))
	_skill_banner(sname)
	var tgt: Dictionary = _find(String(ev.get("target", "")))
	# 원작 skillMimic/skillBomb/skillBlock: 스킬 카테고리별 시각 이펙트 분기.
	_skill_fx(ev, caster, tgt)
	if bool(ev.get("interrupt", false)):
		_log("%s! %s의 스킬 무효화" % [sname, _disp(ev.get("target", ""))])
		return
	if int(ev.get("damage", 0)) > 0:
		_hurt(tgt, int(ev["damage"]), false)
		if bool(ev.get("dead", false)): _kill(tgt)
	if int(ev.get("heal", 0)) > 0:
		_heal(tgt, int(ev["heal"]))
	if int(ev.get("target_loss", 0)) > 0:
		_hurt(tgt, int(ev["target_loss"]), false)
	if int(ev.get("self_loss", 0)) > 0:
		_hurt(caster, int(ev["self_loss"]), false)
	if ev.has("debuff"):
		_fx_text(tgt, "", String(ev["debuff"]), Color(0.9, 0.6, 1.0))
		_bicon_add(tgt, int(ev.get("skill_id", 0)), false, int(ev.get("turns", 0)))
	if bool(ev.get("cleanse", false)):
		_fx_text(tgt, "", "정화", Color(0.7, 1.0, 0.8))
	# 버프/방어 카테고리 스킬 → 시전자에 강화 배지.
	var scat := String(Data.skills.get(str(int(ev.get("skill_id", 0))), {}).get("category", ""))
	if scat == "buff" or scat == "defense":
		_bicon_add(caster, int(ev.get("skill_id", 0)), true, int(ev.get("turns", 0)))
	_log("%s 발동 — %s" % [sname, _disp(ev.get("caster", ""))])

## 스킬 카테고리별 이펙트(원작 skillMimic/skillBomb/skillBlock 분기).
## attack/debuff/cleanse=대상에, buff/defense=시전자에 링+스킬아이콘 버스트. 색=카테고리.
## 원작 스킬 이펙트 스파인 노출 시간 — AdventureScene.c:38859 `CCDelayTime::create(0.7)` 뒤 Hide/Blink.
const _SKILL_SPINE_SEC := 0.7

const _SKILL_FX := {
	"attack":    {"col": Color(1.0, 0.5, 0.2), "on": "target"},
	"debuff":    {"col": Color(0.85, 0.4, 1.0), "on": "target"},
	"heal":      {"col": Color(0.4, 1.0, 0.5), "on": "target"},
	"buff":      {"col": Color(1.0, 0.85, 0.3), "on": "caster"},
	"defense":   {"col": Color(0.4, 0.7, 1.0), "on": "caster"},
	"cleanse":   {"col": Color(0.8, 1.0, 0.9), "on": "target"},
	"interrupt": {"col": Color(1.0, 0.9, 0.4), "on": "target"},
}
## 스킬 카테고리별 발동 SFX(원작 effect_*). 속성 스킬은 element 우선.
const _SKILL_SFX := {
	"attack": "effect_bite", "heal": "effect_blink", "debuff": "effect_dark_clap",
	"buff": "effect_buildup", "defense": "effect_block", "cleanse": "effect_blink",
	"dot": "effect_burn", "reflect": "effect_bomb",
}
const _ELEM_SFX := {"fire": "effect_burn", "chaos": "effect_bomb", "dark": "effect_dark_clap"}
func _skill_fx(ev: Dictionary, caster: Dictionary, target: Dictionary) -> void:
	var sid := int(ev.get("skill_id", 0))
	var sdef: Dictionary = Data.skills.get(str(sid), {})
	var cat := String(sdef.get("category", "attack"))
	var sel := String(sdef.get("element", ""))
	# 원작은 **스킬별 전용 효과음**을 쓴다: `music/effect_skill_%d.mp3`
	#   근거: docs/ref/orig_code/decomp/AdventureScene.c:57622
	#         `CCString::createWithFormat("music/effect_skill_%d.mp3", …)`
	#   대응 확인: `DV2/music/effect_skill_N.mp3` 의 N 24종
	#         {11,12,14,15,20,21,22,23,24,26,29,30,32,36,46,50,54,56,60,70,90,100,110,170} 이
	#         **전부 data/skills.json 의 스킬 id에 포함**되고, 스킬 id가 아닌 N은 하나도 없다
	#         → N = 스킬 id 로 확정(# ASSUMPTION 이 아니라 전수 대조 결과).
	#   파일이 있는 스킬만 전용음, 없으면 기존 카테고리/속성 효과음으로 폴백한다.
	var own := "effect_skill_%d" % sid
	if sid > 0 and ResourceLoader.exists("res://assets/music/%s.mp3" % own):
		Bgm.sfx(own)
	else:
		Bgm.sfx(_ELEM_SFX.get(sel, _SKILL_SFX.get(cat, "effect_cut_in")))
	# 원작 **스킬 전용 이펙트 스파인** — `skill/skill_{id}_spine.spine_json`.
	#   근거: 스파인 34종의 N 중 33종이 data/skills.json 의 스킬 id이고, 스킬 id가 아닌 N은 `2` 하나뿐
	#         (사운드 `effect_skill_{id}.mp3` 24종이 전부 스킬 id였던 것과 같은 규약).
	#   변환: scripts/tools/build_skill_fx.py → build_skill_fx_scenes.gd → scenes/fx/skill_{id}_spine.tscn
	#   있으면 그걸 쓰고, 없으면 아래 카테고리별 도형 이펙트로 폴백한다.
	if sid > 0 and _play_skill_spine(sid, (target if not target.is_empty() else caster)):
		return
	var spec: Dictionary = _SKILL_FX.get(cat, _SKILL_FX["attack"])
	var v: Dictionary = caster if String(spec["on"]) == "caster" else target
	if v.is_empty(): v = caster
	if v.is_empty() or not v.has("center"): return
	var center: Vector2 = v["center"]
	_fx_ring(center, spec["col"])
	# 스킬 아이콘 버스트
	var icon_p := "res://assets/converted/skill/skill_%d.tres" % sid
	if ResourceLoader.exists(icon_p):
		var ic := Sprite2D.new(); ic.texture = load(icon_p); ic.material = _pma
		ic.position = center + Vector2(0, -8); ic.z_index = 101; ic.scale = Vector2(0.3, 0.3)
		add_child(ic)
		var t := create_tween()
		t.tween_property(ic, "scale", Vector2(1.05, 1.05), 0.16).set_trans(Tween.TRANS_BACK)
		t.tween_interval(0.14)
		t.tween_property(ic, "modulate:a", 0.0, 0.22)
		t.parallel().tween_property(ic, "scale", Vector2(1.35, 1.35), 0.22)
		t.tween_callback(ic.queue_free)

## 확장·페이드 링(스킬 이펙트 공통). 색=카테고리.
func _fx_ring(center: Vector2, col: Color) -> void:
	var ring := Line2D.new()
	ring.width = 5.0; ring.default_color = col; ring.closed = true; ring.antialiased = true
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		pts.append(Vector2(cos(a), sin(a)) * 42.0)
	ring.points = pts
	ring.position = center; ring.z_index = 100; ring.scale = Vector2(0.25, 0.25)
	add_child(ring)
	var t := create_tween()
	t.tween_property(ring, "scale", Vector2(1.7, 1.7), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(ring, "modulate:a", 0.0, 0.4)
	t.tween_callback(ring.queue_free)

# ---------- 연출 primitives ----------
## 원작 HP fill(9-slice). 파티=hp_bar10(134×21), 몬스터=hp_bar9(594×23). 회전/아틀라스라 표준 PNG로 추출.
const _HP_BAR := "res://assets/converted/battle_extra/hp_bar10.png"       # 파티 카드용
const _HP_BAR_MONSTER := "res://assets/converted/battle_extra/hp_bar9.png" # 적(몬스터)용
func _hp_fill(w: float, h: float, monster := false) -> NinePatchRect:
	var np := NinePatchRect.new()
	var tex_path := _HP_BAR_MONSTER if monster else _HP_BAR
	if not ResourceLoader.exists(tex_path): tex_path = _HP_BAR
	if ResourceLoader.exists(tex_path):
		np.texture = load(tex_path)
	np.patch_margin_left = 8; np.patch_margin_right = 8
	np.patch_margin_top = 3; np.patch_margin_bottom = 3
	np.size = Vector2(w, h); np.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return np

func _refresh_bar(v: Dictionary) -> void:
	var frac := clampf(float(v["hp"]) / maxf(1.0, float(v["hp_max"])), 0.0, 1.0)
	var fill: Control = v["hp_fill"]
	fill.size.x = maxf(0.0, float(v["bar_w"]) * frac)
	(v["hp_label"] as Label).text = "%d / %d" % [int(v["hp"]), int(v["hp_max"])]

func _hurt(v: Dictionary, dmg: int, crit: bool) -> void:
	if v.is_empty(): return
	# 원작 InterFace::setCallHitSound(@00d3adec)는 드래곤 인터페이스가 맞을 때마다
	# effect_dragon_damaged_1/2 중 하나를 rand() & 1로 골라 즉시 재생한다.
	# 몬스터 피격 콜백은 `_queue_monster_hit_sfx`가 같은 음원 풀을 지연 재생한다.
	if String(v.get("kind", "")) == "party":
		Bgm.sfx("effect_dragon_damaged_%d" % (1 + (randi() & 1)))
	v["hp"] = maxi(0, int(v["hp"]) - dmg)
	var fill: Control = v["hp_fill"]
	var frac := clampf(float(v["hp"]) / maxf(1.0, float(v["hp_max"])), 0.0, 1.0)
	create_tween().tween_property(fill, "size:x", maxf(0.0, float(v["bar_w"]) * frac), 0.25)
	(v["hp_label"] as Label).text = "%d / %d" % [int(v["hp"]), int(v["hp_max"])]
	# 데미지 숫자(원작 font_normal — 숫자전용 비트맵). 크리는 색·크기로 표현(원작도 "!"글자 없음).
	_dmg_number(v["center"], dmg, crit)
	# 피격 모션. 몬스터는 원작 BattleMonster::setAnimatedHit(hit 아트 교체 + 붉은 점멸 2회 + Shake),
	# 파티(드래곤 카드)는 종전의 짧은 플래시 + 흔들림.
	if String(v.get("kind", "")) == "enemy":
		_monster_hit_motion(v)
	else:
		var node: Node = v["node"]
		if node is CanvasItem:
			var ci := node as CanvasItem
			var t := create_tween()
			t.tween_property(ci, "modulate", Color(1.4, 0.5, 0.5), 0.06)
			t.tween_property(ci, "modulate", Color.WHITE, 0.14)
		_screen_shake(8.0 if crit else 4.0)   # 원작 피격 임팩트: 화면 흔들림(crit 강)
	_check_groggy(v)

## 몬스터 "중상" 상태 — 원작 몬스터 스파인의 **`groggy`** 애니메이션.
## 근거: 변환된 `scenes/monsters/monster_N.tscn` 의 AnimationLibrary 에 `wait` 와 함께 `groggy` 가
##   들어 있다(monster_1.tscn 확인). 원작도 같은 이름을 쓴다 —
##   `Monster::getImagePathSpineJsonBossGroggy` → `monster/%d/%d_monster_groggy_spine.spine_json`
##   (Monster.c:881-899), `CCSkeletonAnimation::setAnimation(…, "groggy", true, 0)` (ScenarioLayer.c:11435).
## 레퍼런스 docs/ref/orig_image/battle/몬스터중상.png = 몸에 흰 상처 표시가 붙은 그 상태.
## # ASSUMPTION: **전환 HP 임계값은 복원하지 못했다.** 레퍼런스의 관측점 하나(17/279 = 6%)뿐이라
##   0.25로 둔다. 원작 수치를 아는 값처럼 적지 않는다.
const _GROGGY_HP_RATIO := 0.25
func _check_groggy(v: Dictionary) -> void:
	if v.is_empty() or String(v.get("kind", "")) != "enemy": return
	if bool(v.get("groggy", false)) or not bool(v.get("alive", true)): return
	if float(v["hp"]) > float(v["hp_max"]) * _GROGGY_HP_RATIO: return
	var ap = v.get("anim")
	if ap is AnimationPlayer and (ap as AnimationPlayer).has_animation("groggy"):
		(ap as AnimationPlayer).play("groggy")
		v["groggy"] = true

## 화면 흔들림(원작 전투 임팩트). battle=Control이라 Camera2D.offset을 지터 → 정착.
## HUD가 별도 CanvasLayer면 필드만 흔들리고, 아니면 전체가 짧게 흔들린다(둘 다 유효한 연출).
var _shake_cam: Camera2D
var _shake_tw: Tween
func _screen_shake(intensity: float = 6.0) -> void:
	if not is_instance_valid(_shake_cam):
		_shake_cam = Camera2D.new()
		_shake_cam.position = _vis() * 0.5   # 콘텐츠(0..vis) 중심을 봄 → 기본 정렬 유지
		add_child(_shake_cam)
		_shake_cam.make_current()
	if is_instance_valid(_shake_tw): _shake_tw.kill()
	_shake_tw = create_tween()
	var amt := intensity
	for i in 5:
		var off := Vector2(randf_range(-amt, amt), randf_range(-amt, amt))
		_shake_tw.tween_property(_shake_cam, "offset", off, 0.03)
		amt *= 0.68
	_shake_tw.tween_property(_shake_cam, "offset", Vector2.ZERO, 0.05)

## 원작 setAttributeParticleEffect: 피격 지점에 공격자 속성색 파티클 버스트(에셋 부재→프리미티브).
const _ELEM_COL := {
	"fire": Color(1.0, 0.45, 0.2), "aqua": Color(0.35, 0.7, 1.0), "wind": Color(0.5, 1.0, 0.6),
	"earth": Color(0.8, 0.6, 0.35), "light": Color(1.0, 0.95, 0.5), "dark": Color(0.7, 0.4, 1.0),
	"holy": Color(1.0, 0.9, 0.45), "chaos": Color(1.0, 0.4, 0.85), "shadow": Color(0.6, 0.55, 0.8),
}
const _CRIT_SFX := {
	"fire": "effect_critical_fire_1", "aqua": "effect_critical_ice_1",
	"wind": "effect_critical_lightning_1", "light": "effect_critical_lightning_1",
}
## ⚠️ `v` 는 **피격자**, `element`/`crit_voice` 는 **공격자** 것이다(소리는 때린 쪽이 낸다).
func _attr_particles(v: Dictionary, element: String, crit: bool, crit_voice := 0) -> void:
	if v.is_empty(): return
	# ⚠️ 크리티컬 소리는 여기서 내지 않는다 — `_critical_sequence` 시작에서 `_crit_voice` 가
	#   드래곤별 보이스로 낸다(원작 순서: 음성 → 컷인 → 타격). 여기 두면 타격 뒤에 또 나온다.
	var col: Color = _ELEM_COL.get(element, Color(1, 1, 1))
	var p := CPUParticles2D.new()
	p.position = v["center"]
	p.z_index = 95
	p.one_shot = true; p.explosiveness = 1.0
	p.amount = 18 if crit else 11
	p.lifetime = 0.5
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 12.0
	p.direction = Vector2(-1, -0.4); p.spread = 130.0
	p.initial_velocity_min = 80.0; p.initial_velocity_max = (240.0 if crit else 170.0)
	p.gravity = Vector2(0, 180.0)
	p.scale_amount_min = 2.0; p.scale_amount_max = (5.0 if crit else 3.5)
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.95)); g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = g
	var mat := CanvasItemMaterial.new(); mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	add_child(p)
	p.emitting = true
	get_tree().create_timer(0.9).timeout.connect(func(): if is_instance_valid(p): p.queue_free())

## 원작 setViewBurningEffect: 지속피해(DoT) 대상에 불타는 파티클(에셋 부재→프리미티브 화염 모트).
func _burning_fx(v: Dictionary) -> void:
	if v.is_empty() or not v.has("center"): return
	var p := CPUParticles2D.new()
	p.position = (v["center"] as Vector2) + Vector2(0, 10)
	p.z_index = 96
	p.one_shot = true; p.explosiveness = 0.4
	p.amount = 14
	p.lifetime = 0.6
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(28, 6)
	p.direction = Vector2(0, -1); p.spread = 24.0
	p.initial_velocity_min = 60.0; p.initial_velocity_max = 130.0
	p.gravity = Vector2(0, -40.0)
	p.scale_amount_min = 2.5; p.scale_amount_max = 5.0
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.3, 0.95))   # 노랑 → 주황 → 투명(불꽃)
	g.add_point(0.5, Color(1.0, 0.5, 0.15, 0.7))
	g.set_color(1, Color(0.8, 0.2, 0.1, 0.0))
	p.color_ramp = g
	var mat := CanvasItemMaterial.new(); mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	add_child(p); p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(func(): if is_instance_valid(p): p.queue_free())

func _heal(v: Dictionary, amt: int) -> void:
	if v.is_empty(): return
	v["hp"] = mini(int(v["hp_max"]), int(v["hp"]) + amt)
	var fill: Control = v["hp_fill"]
	var frac := clampf(float(v["hp"]) / maxf(1.0, float(v["hp_max"])), 0.0, 1.0)
	create_tween().tween_property(fill, "size:x", float(v["bar_w"]) * frac, 0.25)
	(v["hp_label"] as Label).text = "%d / %d" % [int(v["hp"]), int(v["hp_max"])]
	_heal_number(v["center"], amt)

## 원작 힐 숫자 폰트. InterFace.c:6381 `CCLabelBMFont::create(n, "font/font_heal.fnt")` —
## 데미지는 font_normal(위 _dmg_number), 힐은 **전용 font_heal** 비트맵을 쓴다.
## 숫자 전용 폰트라 "+"는 별도 라벨 없이 숫자만 담는다(두부 방지).
const _HEAL_FONT := "res://assets/480/font/font_heal.fnt"
var _heal_font_cache: Font = null
func _heal_number(pos: Vector2, amt: int) -> void:
	var l := Label.new()
	l.text = str(amt)
	if _heal_font_cache == null and ResourceLoader.exists(_HEAL_FONT):
		_heal_font_cache = load(_HEAL_FONT)
	if _heal_font_cache != null:
		l.add_theme_font_override("font", _heal_font_cache)
	else:
		l.text = "+%d" % amt   # 폰트 부재 시 폴백
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
	l.add_theme_color_override("font_outline_color", Color(0, 0.25, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.z_index = 101
	l.position = pos + Vector2(-10, -16)
	add_child(l)
	var t := create_tween()
	t.tween_property(l, "position:y", l.position.y - 44, 0.6)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)

func _kill(v: Dictionary) -> void:
	if v.is_empty() or not bool(v.get("alive", true)): return
	v["alive"] = false
	_bicon_clear(v)          # 원작 setRemoveAllBicon: 쓰러지면 버프 아이콘도 전부 걷힌다
	Bgm.sfx("effect_dead")   # 원작 사망 효과음
	# 원작 `makeSkillParticle` @00c9e4a4 의 격파 파티클(`pt_monster_dead_2_2.plist`).
	if v.has("center"):
		CocosParticle.spawn(self, "pt_monster_dead_2_2", v["center"], 98, 0.9)
	var node: Node = v["node"]
	if node is CanvasItem:
		create_tween().tween_property(node, "modulate:a", 0.25 if v["kind"] == "party" else 0.0, 0.4)
	# 원작 몬스터 격파 서사 — 레퍼런스 docs/ref/orig_image/battle/몬스터승리.png 하단:
	#   "데스웜은 힘없이 비틀거리다가 쓰러졌다."  (몬스터가 사라지고 이 문장만 남는다)
	if String(v.get("kind", "")) == "enemy":
		var mn := String(_enemy.get("name", "몬스터"))
		_log("%s%s 힘없이 비틀거리다가 쓰러졌다." % [mn, _josa(mn, "은", "는")])
		# 비틀거리다 쓰러지는 동작: 좌우로 기울다가 아래로 가라앉으며 사라짐.
		if node is Node2D:
			var n2 := node as Node2D
			var t := n2.create_tween()
			t.tween_property(n2, "rotation", 0.12, 0.18).set_trans(Tween.TRANS_SINE)
			t.tween_property(n2, "rotation", -0.14, 0.20).set_trans(Tween.TRANS_SINE)
			t.tween_property(n2, "rotation", 0.5, 0.35).set_trans(Tween.TRANS_BACK)
			t.parallel().tween_property(n2, "position:y", n2.position.y + 60.0, 0.35)

## 한글 조사 선택(받침 유무). 원작 문장을 그대로 쓰기 위한 표기 헬퍼.
func _josa(word: String, with_batchim: String, without: String) -> String:
	if word.is_empty(): return without
	var c := word.unicode_at(word.length() - 1)
	if c < 0xAC00 or c > 0xD7A3: return without
	return with_batchim if ((c - 0xAC00) % 28) != 0 else without

func _cue(v: Dictionary, critical := false) -> void:
	if v.is_empty() or not bool(v.get("alive", true)): return
	var node: Node = v["node"]
	if v["kind"] == "enemy" and node is Node2D:
		if critical:
			_monster_critical_attack(v)
		else:
			_monster_attack(v)
	elif v["kind"] == "party" and node is Control:
		# 원작 basicAction: 공격자가 대상(적) 방향으로 짧게 돌진 후 복귀.
		var base: Vector2 = v["base_pos"]
		var center: Vector2 = v["center"]
		var enemy_c: Vector2 = _views.get("E0", {}).get("center", center + Vector2(0, -80))
		var dir: Vector2 = (enemy_c - center).normalized()
		var t := create_tween()
		t.tween_property(node, "position", base + dir * 34.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(node, "scale", Vector2(1.08, 1.08), 0.1)
		t.tween_property(node, "position", base, 0.16).set_trans(Tween.TRANS_QUAD)
		t.parallel().tween_property(node, "scale", Vector2.ONE, 0.16)

# ─────────────────────────────────────────────────────────────────────────────
# 몬스터 조우/공격/피격 연출 — 원작 1:1 복원
#
# 원작 근거(값까지 그대로):
#   · 등장  `AdventureScene::showMonster` (AdventureScene.c:121191~121461)
#       SFX `music/effect_monster_in.mp3` (:121299) 후 몬스터 노드에 시퀀스:
#         Spawn(ScaleTo 0.3 → 1.2 , MoveBy 0.3 (0,+130))        위로 솟구치며 확대
#         Spawn(ScaleTo 0.15 → 0.8, MoveBy 0.15 (0,-120),
#               ScaleTo 0.15 → (0.9, 0.8))                       내려찍으며 납작(스쿼시)
#         CallFunc(setAllViewShake)                              착지 순간 화면 흔들림
#         Spawn(ScaleTo 0.2 → 1.0 , MoveBy 0.2 (0,+20))          반동 후 정착
#       (Cocos y+ = 위 → Godot y- 로 부호 반전)
#   · 화면 플래시 `AdventureScene::incomeMonster(bool)` (:16274~)
#       일반: CCLayerColor(0xEAEAEA, a=0x64) → FadeTo(0.2,200) → FadeOut(0.7)
#       보스: CCLayerColor(0xCC3D3D, a=0)    → Delay(0.3) → FadeTo(0.2,255) → FadeOut(0.7)
#       파티클 `particle/scene/adventure/pt_monster_income_1.plist` 를 화면 상단에 z=999999.
#   · 흔들림 세기 `Shake::actionWithDuration(0.5, 10.0)` (setMonsterThreat :100609)

## 몬스터 등장(원작 showMonster + incomeMonster).
func _monster_income(node: Node2D) -> void:
	var vis := _vis()
	var boss := _is_boss()
	# 화면 플래시(원작 incomeMonster CCLayerColor). 보스는 붉은색 + 0.3s 지연.
	var flash := ColorRect.new()
	flash.color = Color(0.8, 0.24, 0.24, 0.0) if boss else Color(0.918, 0.918, 0.918, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fl := CanvasLayer.new(); fl.layer = 90; add_child(fl); fl.add_child(flash)
	var ft := flash.create_tween()
	if boss:
		ft.tween_interval(0.3)
		ft.tween_property(flash, "color:a", 1.0, 0.2)      # FadeTo(0.2, 255)
	else:
		ft.tween_property(flash, "color:a", 200.0 / 255.0, 0.2)   # FadeTo(0.2, 200)
	ft.tween_property(flash, "color:a", 0.0, 0.7)          # FadeOut(0.7)
	ft.tween_callback(fl.queue_free)
	# 등장 파티클(원작 pt_monster_income_1, 화면 상단).
	_levelup_particle("pt_monster_income_1", vis.x * 0.5, 40.0)
	Bgm.sfx("effect_monster_in")
	if node == null or not is_instance_valid(node):
		return
	# 몬스터 본체 시퀀스(원작 showMonster). 배율은 우리 배치 배율(base)에 곱해 적용한다.
	var base: Vector2 = node.scale
	var pos: Vector2 = node.position
	node.scale = base
	var t := node.create_tween()
	t.tween_property(node, "scale", base * 1.2, 0.3)
	t.parallel().tween_property(node, "position", pos + Vector2(0, -130), 0.3)
	t.tween_property(node, "scale", Vector2(base.x * 0.9, base.y * 0.8), 0.15)
	t.parallel().tween_property(node, "position", pos + Vector2(0, -10), 0.15)
	t.tween_callback(func(): _screen_shake(10.0))          # 원작 setAllViewShake
	t.tween_property(node, "scale", base, 0.2)
	t.parallel().tween_property(node, "position", pos, 0.2)

## 몬스터 공격 — 원작 `BattleMonster::setAnimatedAttack` (BattleMonster.c:1310~1630).
## 원작 구조:
##   1) 스프라이트를 `att.png`(또는 att1/att2)로 교체 — Monster::getImagePathAtt (:1448)
##   2) ScaleTo(0.15, base×2.2) → ScaleTo(0.05, base×2.0)   화면 쪽으로 확 다가온다 (:1561-1562)
##   3) 4px 진동: MoveTo 0.02초 ×5(+4+4 → -4-4 → -4+4 → +4-4 → 원위치)를 **8회 반복** (:1606-1629, :1567)
## 즉 원작 몬스터 공격은 "앞으로 나오는 돌진"이 아니라 **att 아트가 2배로 확대되며 부르르 떠는** 연출이다.
## (이전 구현의 y+24 짧은 바운스는 원작에 없다.)
const _MON_ATK_JITTER := 4.0     # 원작 리터럴 4px
const _MON_ATK_REPEAT := 8       # 원작 CCSequence 에 진동 시퀀스가 8번 들어간다
func _monster_attack(v: Dictionary) -> void:
	var node: Node2D = v["node"]
	var base_pos: Vector2 = v["base_pos"]
	var att: Sprite2D = v.get("att_node")
	var sp := maxf(0.5, _speed)
	# att 포즈로 교체(원작 1단계). 없으면 스파인 그대로 확대만.
	var target: Node2D = node
	if att != null and is_instance_valid(att):
		att.position = base_pos
		att.scale = Vector2.ONE * 1.6      # _spr 로 만들 때의 기준 배율
		node.visible = false; att.visible = true
		target = att
	var base_scale: Vector2 = target.scale
	var t := target.create_tween()
	t.tween_property(target, "scale", base_scale * 2.2, 0.15 / sp)
	t.tween_property(target, "scale", base_scale * 2.0, 0.05 / sp)
	# 진동(원작 3단계) — 대각 4방향을 0.02초씩 돌고 원위치, 8회.
	var d := _MON_ATK_JITTER
	for i in _MON_ATK_REPEAT:
		for off in [Vector2(d, d), Vector2(-d, -d), Vector2(-d, d), Vector2(d, -d), Vector2.ZERO]:
			t.tween_property(target, "position", base_pos + off, 0.02 / sp)
	t.tween_property(target, "scale", base_scale, 0.1 / sp)
	t.tween_callback(func():
		if is_instance_valid(node): node.visible = true
		if att != null and is_instance_valid(att): att.visible = false)

## Original BattleMonster::setAnimatedCritical (BattleMonster.c:1994-2495):
## boss monsters swap to att_cri, place att_effect_cri at screen center, then run
## Delay 0.15 -> Fade/Scale 0.3 -> 12 px shake x8 -> Fade/Scale 0.05.
## Non-boss critical attacks use the ordinary att/att_effect frames.
const _MON_CRIT_EFFECT_START_SCALE := 1.7
const _MON_CRIT_EFFECT_PEAK_SCALE := 2.3
const _MON_CRIT_EFFECT_END_SCALE := 2.1
const _MON_CRIT_EFFECT_JITTER := 12.0
const _MON_CRIT_EFFECT_REPEAT := 8
const _MON_CRIT_POSE_REPEAT := 10
func _monster_critical_attack(v: Dictionary) -> void:
	var node := v.get("node") as Node2D
	if node == null or not is_instance_valid(node):
		return
	var sp := maxf(0.5, _speed)
	var base_pos: Vector2 = v.get("base_pos", node.position)
	var boss := _is_boss()
	var mid := int(_enemy.get("id", 0))
	var mdir := "monster_%d" % mid
	var mman := _man(mdir)

	var pose: Node2D = null
	var owns_pose := false
	if boss:
		pose = _spr(mdir, "monster_%d_%d_image_att_cri" % [mid, mid], mman, 1.6)
		if pose != null:
			pose.position = base_pos
			pose.visible = true
			pose.z_index = node.z_index
			add_child(pose)
			owns_pose = true
	if pose == null:
		pose = v.get("att_node") as Sprite2D
	if pose == null or not is_instance_valid(pose):
		pose = node
	if pose != node:
		node.visible = false
		pose.visible = true
		pose.position = base_pos
	var pose_scale := pose.scale
	var pt := pose.create_tween()
	# Ground type 1 branch in the original: 2.15 over 0.1, 3 px shake x10,
	# then 2.0 over 0.05. The referenced Black Robe attacker is ground type 1.
	pt.tween_property(pose, "scale", pose_scale * 2.15, 0.1 / sp)
	var pd := 3.0
	for i in _MON_CRIT_POSE_REPEAT:
		for off in [Vector2(pd, pd), Vector2(-pd, -pd), Vector2(-pd, pd), Vector2(pd, -pd), Vector2.ZERO]:
			pt.tween_property(pose, "position", base_pos + off, 0.02 / sp)
	pt.tween_property(pose, "scale", pose_scale * 2.0, 0.05 / sp)
	pt.tween_callback(func():
		if is_instance_valid(node): node.visible = true
		if owns_pose and is_instance_valid(pose):
			pose.queue_free()
		elif pose != node and is_instance_valid(pose):
			pose.visible = false)

	Bgm.sfx("effect_critical_ice_2")
	var effect_key := ("monster_%d_%d_image_att_effect_cri" % [mid, mid] if boss
		else "monster_%d_%d_image_att_effect" % [mid, mid])
	var effect := _spr(mdir, effect_key, mman,
		Design.ASSET_SCALE * _MON_CRIT_EFFECT_START_SCALE)
	if effect == null:
		return
	var center := _vis() * 0.5
	effect.position = center
	effect.modulate.a = 0.0
	effect.z_index = 120
	var lay := CanvasLayer.new()
	lay.layer = 35
	add_child(lay)
	lay.add_child(effect)
	var et := effect.create_tween()
	et.tween_interval(0.15 / sp)
	et.tween_property(effect, "modulate:a", 1.0, 0.3 / sp)
	et.parallel().tween_property(effect, "scale",
		Vector2.ONE * Design.ASSET_SCALE * _MON_CRIT_EFFECT_PEAK_SCALE, 0.3 / sp)
	var ed := _MON_CRIT_EFFECT_JITTER
	for i in _MON_CRIT_EFFECT_REPEAT:
		for off in [Vector2(ed, -ed), Vector2(-ed, ed), Vector2(-ed, -ed), Vector2(ed, ed), Vector2.ZERO]:
			et.tween_property(effect, "position", center + off, 0.02 / sp)
	et.tween_property(effect, "scale",
		Vector2.ONE * Design.ASSET_SCALE * _MON_CRIT_EFFECT_END_SCALE, 0.05 / sp)
	et.parallel().tween_property(effect, "modulate:a", 0.0, 0.05 / sp)
	et.tween_callback(func(): if is_instance_valid(lay): lay.queue_free())

## 몬스터 피격 — 원작 `BattleMonster::setAnimatedHit` (BattleMonster.c:3333~3705).
## 원작 구조:
##   1) 스프라이트를 `hit.png`(또는 hit1/hit2)로 교체 — Monster::getImagePathHit (:3644)
##   2) 붉은 틴트 점멸 2회: TintTo(0,255,0,0) → Delay(t×0.025) → TintTo(0,255,255,255)
##      → Delay(t×0.05) → 같은 쌍 한 번 더 (:3688-3697)
##   3) ScaleTo(0.05, base) (:3698) + Shake(t×0.7, 10.0) (:3702)
## t = 연출 시간계수(속도배속). 우리는 _speed 로 나눈다.
func _monster_hit_motion(v: Dictionary) -> void:
	var node: Node2D = v.get("node")
	if node == null or not is_instance_valid(node): return
	var sp := maxf(0.5, _speed)
	var hit: Sprite2D = v.get("hit_node")
	var target: CanvasItem = node
	if hit != null and is_instance_valid(hit):
		hit.position = v["base_pos"]
		node.visible = false; hit.visible = true
		target = hit
	var red := Color(1, 0, 0)
	var white := Color.WHITE
	var t := target.create_tween()
	for i in 2:                                   # 원작: 붉은 점멸 2회
		t.tween_callback(func(): if is_instance_valid(target): target.modulate = red)
		t.tween_interval(0.025 / sp)
		t.tween_callback(func(): if is_instance_valid(target): target.modulate = white)
		t.tween_interval(0.05 / sp)
	t.tween_callback(func():
		if is_instance_valid(target): target.modulate = white
		if hit != null and is_instance_valid(hit): hit.visible = false
		if is_instance_valid(node): node.visible = true)
	_screen_shake(10.0)                           # 원작 Shake(t×0.7, 10.0)

## 크리티컬 연타 횟수. 원작 `Dragon::getCriticalHit()`(DB `info_dragon_v2.critical_hit`)이고
## 타이밍은 `FightDragon::createCriticalFrame` 이 DB `critical_frame` 을 30fps 프레임으로 파싱한다
## (`(i*0.1 + 1.0) / 0.033332903`, docs/ref/orig_code/decomp/FightDragon.c:351-405) — 즉 **0.1초 간격**.
## 두 값 모두 서버 DB라 유실 → 드래곤별 값이 있으면 그걸, 없으면 `combat.json judge.crit_hits`.
func _crit_hits(caster: Dictionary) -> int:
	var n := int(caster.get("critical_hit", 0))
	if n <= 0:
		n = int((Data.combat.get("judge", {}) as Dictionary).get("crit_hits", 1))
	return maxi(1, n)

## 타격 n회(연타).
##
## 간격 0.1초는 원작에서 나온 값이다 — `FightDragon::createCriticalFrame` 이 DB `critical_frame`
## 을 `(i*0.1 + 1.0) / 0.033332903`(30fps 프레임)로 바꾼다. 반면 **횟수(`critical_hit`)는 유실**이라
## 2026-07-27 사용자 승인으로 HARD RULE 6(수치 날조 금지)의 **예외**로 두고 우리가 설계했다:
##   · 기본 2회 (`combat.json judge.crit_hits`) — 드래곤별 값이 있으면 그쪽이 우선
##   · 총 피해량은 **바뀌지 않는다**. 연출만 n회로 쪼갠다(로직 층은 손대지 않음 → §8 계층 유지)
##   · 마지막 타가 가장 세게 보이도록 임팩트를 뒤로 갈수록 키운다(연타의 타감)
func _strike(target: Dictionary, crit: bool, hits: int) -> void:
	var n := maxi(1, hits)
	for i in n:
		if i > 0:
			await get_tree().create_timer(0.1 / maxf(0.5, _speed)).timeout
			if not is_inside_tree() or target.is_empty():
				return
		# 크리티컬은 타격 스파인이 다르다 — case 3·4(hit, x2.5) + effect_headbutt.
		var attack_sfx_played := _normal_attack_fx(target, _CRIT_FX if crit else {})
		if attack_sfx_played and String(target.get("kind", "")) == "enemy":
			_queue_monster_hit_sfx()
		# 마지막 타에만 유리깨짐(원작 monster/hit_effect)을 크게 — 중간 타는 임팩트만.
		_normal_impact(target, crit and i == n - 1)
		if i == n - 1:
			_hit_crack(target, crit)

## AdventureScene::startAttack calls BattleDragon::setAnimatedAttack and then
## BattleMonster::setAnimatedHit. The latter has no direct sound call, but the
## original client routes InterFace::setCallHitSound through its hit callback;
## that callback randomly uses effect_dragon_damaged_1/2. The observed client
## timing places it about 0.2 seconds after the dragon attack sound.
const _MONSTER_HIT_SFX_DELAY := 0.2
func _queue_monster_hit_sfx() -> void:
	var timer := get_tree().create_timer(_MONSTER_HIT_SFX_DELAY / maxf(0.5, _speed))
	timer.timeout.connect(func():
		if is_instance_valid(self) and is_inside_tree():
			Bgm.sfx("effect_dragon_damaged_%d" % (1 + (randi() & 1))))

## 크리티컬 전체 시퀀스 (2026-07-27 사용자 지정 순서로 재구성):
##
##   드래곤별 음성(voice_critical) + 컷인  →  hit 타격음·타격효과 × 연타  →  화면 전체 크리티컬 아트
##
## 각 조각의 근거는 해당 함수 주석에 있다:
##   `_crit_voice`(Dragon.c:13478-13526 voice_critical_no) · `_critical_cutin`(PvP·PvE 공통) ·
##   `_CRIT_FX`(firstAttackEffect case 3·4) · `_critical_art`(getImagePathCritical, 화면 전체).
## 타격 간격 0.1초는 원작 확정값(createCriticalFrame), 횟수는 `_crit_hits`(설계값).
## 🔴 2026-07-27 수정 — 세 조각이 서로를 가려서 **타격 스파인이 한 프레임도 안 보였다**.
##   컷인은 CanvasLayer 40, 크리티컬 아트는 41 인데 타격 스파인은 몬스터 노드의 자식(레이어 0)이다.
##   타이밍이 0.5초 대기 → 타격(0.2초짜리 ×2) → 즉시 아트였으므로 타격 구간 0.5~0.8초가
##   앞은 컷인 막(alpha 150)에, 뒤는 화면 전체 아트에 완전히 덮였다.
##   ⇒ 순서(사용자 지정)는 그대로 두고 **겹침만 없앤다**: 컷인이 걷힌 뒤 때리고, 마지막 타의
##     스파인이 끝난 뒤 아트를 띄운다.
func _critical_sequence(caster: Dictionary, target: Dictionary) -> void:
	_start_critical_audio(caster)
	# 컷인 오버레이(막 + 밴드)가 **완전히 걷힌 뒤** 타격으로 넘어간다 — 정리 시각과 같은 식.
	await get_tree().create_timer(_CUTIN_TOTAL / maxf(0.5, _speed)).timeout
	if not is_inside_tree():
		return
	var n := _crit_hits(caster)
	await _strike(target, true, n)
	if not is_inside_tree():
		return
	# 마지막 타의 hit 스파인이 끝날 시간을 준다. 아트는 화면 전체(CanvasLayer 41)라 겹치면 덮는다.
	await get_tree().create_timer(_HIT_FX_DUR / maxf(0.5, _speed)).timeout
	if not is_inside_tree():
		return
	# 원본 크리티컬 아트가 없는 종은 **전용 이펙트 밴드**로 대신한다(800 로키 = 드빌1
	# `adv_action1/2` 중 랜덤 1장). 🟦 사용자 확정 2026-08-04 — 상세는 `_critical_fx_band`.
	if not _critical_art(caster):
		_critical_fx_band(caster)

func _start_critical_audio(caster: Dictionary) -> void:
	# 원작 MakeInterface::showCutIn은 Cutin::show에 voice_critical 경로를 넘긴다.
	# Cutin은 effect_cut_in 연출을 먼저 시작하고 param_2*0.05초 뒤 보이스를 호출한다
	# (Cutin.c:720-805). 즉시 동시 호출하면 보이스가 컷인음의 첫 타격을 가린다.
	_critical_cutin(caster)
	var voice_delay := DragonCutin.VOICE_DELAY / maxf(0.5, _speed)
	get_tree().create_timer(voice_delay).timeout.connect(_crit_voice.bind(caster))

## 크리티컬 음성 — 원작은 드래곤마다 다른 보이스(`voice_critical_no` → `music/voice<N>.mp3`).
## 매핑이 유실이라 값이 없으면 속성별 `effect_critical*` 로 폴백한다.
func _critical_voice_no(dragon_id: int, ddef: Dictionary) -> int:
	var direct := int(ddef.get("voice_critical", 0))
	if direct > 0:
		return direct
	# 원작의 별도 열을 그대로 받을 자리. 성장단계 보이스를 임의로 대신 쓰지 않는다.
	# 🟦 2026-08-07 — 커스텀 종 600·700 은 **소환 재료 종의 소리**를 낸다.
	return int(Icons.voice_row(dragon_id).get("critical", 0))

func _crit_voice(caster: Dictionary) -> void:
	var v := int(caster.get("voice_critical", 0))
	if v > 0:
		Bgm.sfx("voice%d" % v)
	else:
		Bgm.sfx(_CRIT_SFX.get(String(caster.get("element", "")), "effect_critical"))

## PvE 크리티컬 아트 — `dragon/dragon_%d_critical/critical.png`(각성이면 `e_critical.png`).
## 원작 게터는 `Dragon::getImagePathCritical`(Dragon.c:8576-8650, 각성 분기는 컷인과 같은 0xac).
##
## 배치 근거: **화면 정중앙 · 화면 전체 크기**(2026-07-27 사용자 확인).
##   프레임 실측이 이를 뒷받침한다 — 372종 중 대부분이 384×260, 일부가 **768×519**인데
##   768×519 는 원작 리소스 기준 화면 크기 그 자체다(CLAUDE.md §9). 384×260 은 정확히 그 절반이라
##   **가로를 화면 폭에 맞추면 두 변형 모두 화면을 꽉 채운다**(260×2.67≒692 = 디자인 높이).
##   그래서 배율은 `vis.x / w` 하나로 충분하다.
## ⚠️ PvP 크리티컬(왼→오른쪽으로 쏘는 작은 연출)은 `MakeInterface::criticalEffectMake` 의
##   스파인이며 별개다 — `_critical_spine()` 에 남겨 뒀지만 탐험에서는 부르지 않는다.
func _critical_art(caster: Dictionary) -> bool:
	var cid := int(caster.get("id", 0))
	var dir := "critical_%d" % cid
	var man := _man(dir)
	if man.is_empty():
		return false
	var key := "dragon_dragon_%d_critical_critical" % cid
	if bool(caster.get("awakened", false)):
		var ekey := "dragon_dragon_%d_critical_e_critical" % cid
		if man.has(ekey):
			key = ekey
	var ent: Dictionary = man.get(key, {})
	# ⚠️ 배율은 **트림된 프레임(w)이 아니라 원본 캔버스(src)** 기준이어야 한다.
	#   아틀라스가 투명 여백을 잘라내서 프레임 크기가 드래곤마다 제각각이다(280×260 … 384×260).
	#   src 는 대부분 384×260(일부 768×519·576×389)이고 셋 다 화면비 1.48 = 768/519 로 같다.
	#   ⇒ src 가로를 화면 폭에 맞추면 어떤 변형이든 화면을 꽉 채운다.
	var src: Array = ent.get("src", [ent.get("w", 0), ent.get("h", 0)])
	var sw := float(src[0])
	if sw <= 0.0:
		return false
	var vis := _vis()
	var s := vis.x / sw
	var spr := _spr(dir, key, man, s)
	if spr == null:
		return false
	# 트림 오프셋 보정 — cocos off = (트림중심 − 원본캔버스중심), y-up (dungeon_bg.gd 와 같은 규약).
	var off: Array = ent.get("off", [0, 0])
	spr.position = vis * 0.5 + Vector2(float(off[0]), -float(off[1])) * s
	spr.z_index = 120
	var lay := CanvasLayer.new()
	lay.layer = 41                    # 컷인(40) 위
	add_child(lay)
	lay.add_child(spr)
	var t := spr.create_tween()
	t.tween_interval(0.45 / maxf(0.5, _speed))
	t.tween_property(spr, "modulate:a", 0.0, 0.18)
	t.tween_callback(func(): if is_instance_valid(lay): lay.queue_free())
	return true

## 드래곤 **전용 크리티컬 이펙트 밴드** — 원본 크리티컬 아트가 없는 종의 대체 연출.
##
## DV2 원작에는 "드래곤별 이펙트"라는 축이 없다(이펙트는 스킬 단위다). 이 경로는 **드빌1에서
## 이식한 종**이 자기 이펙트를 들고 오기 때문에 생겼다 — 800 로키의 `adv_action1/2` 는
## 400×120 짜리 **가로 밴드**(속도선 + 포효하는 얼굴)라 크리티컬 연출로 그려진 그림이다.
## 🟦 사용자 확정 2026-08-04: 탐험 크리티컬은 **둘 중 랜덤 1장**. 상세 = `DragonLoki800.md` §5-B.
##
## 배치는 `_critical_art` 와 같은 규약이다 — 화면 정중앙, 가로를 화면 폭에 맞춤, CanvasLayer 41.
## 무작위는 **연출용**이라 전투 RNG(시드 고정 대상)를 쓰지 않는다.
func _critical_fx_band(caster: Dictionary) -> bool:
	var cid := int(caster.get("id", 0))
	var dir := "dragon_%d_fx" % cid
	var man := _man(dir)
	if man.is_empty():
		return false
	var keys: Array = []
	for k in man:
		if String(k).begins_with("dragon_%d_adv_action" % cid):
			keys.append(String(k))
	if keys.is_empty():
		return false
	keys.sort()
	var key: String = keys[randi() % keys.size()]
	var ent: Dictionary = man.get(key, {})
	var w := float(ent.get("w", 0))
	if w <= 0.0:
		return false
	var vis := _vis()
	var spr := _spr(dir, key, man, vis.x / w)
	if spr == null:
		return false
	spr.position = vis * 0.5
	spr.z_index = 120
	var lay := CanvasLayer.new()
	lay.layer = 41                    # 컷인(40) 위 — `_critical_art` 와 같은 층
	add_child(lay)
	lay.add_child(spr)
	var t := spr.create_tween()
	t.tween_interval(0.45 / maxf(0.5, _speed))
	t.tween_property(spr, "modulate:a", 0.0, 0.18)
	t.tween_callback(func(): if is_instance_valid(lay): lay.queue_free())
	return true


## 일반공격 아트 — 원작 `MakeInterface::firstAttackEffect(CCNode*, int attackType)`
## (`MakeInterface.c:14990-15120`, `secondAttackEffect`:31409 도 동일 3종). 타입별 파라미터까지 원작 그대로:
##
## | attackType | 스파인 | 원작 tag | 원작 파라미터 |
## |---|---|---|---|
## | 1 | `skill/skill_1_bite_spine`    | -0xf3dda   | tint 0xfff0c226 · 지속 1.0 |
## | 2 | `skill/skill_1_scratch_spine` | -0xd151c   | tint 0xfff2eae4 · **setScaleX 음수(X반전)** · 지속 1.5 |
## | 3,4 | `skill/skill_1_hit_spine`   | -0xc3ca11  | tint 0xff3c35ef · **배율 ×2.5** |
##
## 공통: `createWithFile(json, atlas, 1.0)` → `setVisible(0)` → `addChild(spine, 10)`.
##
## ⚠️ ASSUMPTION — **타입 선택은 매 공격 랜덤**(사용자 확인: "같은 드래곤이라도 발톱/물기가 섞인다").
##   `Dragon::getAttackType()` 은 스킨 문자열 처리 후 필드를 돌려주는 게터라 자체 랜덤이 없고,
##   `firstAttackEffect` 의 **호출부는 디컴파일 400+클래스에 없어** 선택 규칙을 코드로 확인하지 못했다.
##   가중치는 균등으로 둔다(근거 없음 — 확인되면 여기만 고친다).
## 효과음도 타입별로 다르다. `effect_scratch` · `effect_headbutt` 는 원작 전투 프리로드 목록
##   (`MakeInterface::preloadHeavyResource`)에 **실재**하고, `effect_bite` 는 파일은 있으나
##   그 목록엔 없다 → bite 사운드는 이름 대응으로 둔 ASSUMPTION.
## 일반공격은 case 1·2(물기·발톱)만 쓴다 — 사용자 확인: 탐험 일반공격에서 타격(case 3·4)은 본 적이 없다.
const _ATK_FX := [
	{"scene": "skill_1_bite_spine", "sfx": "effect_bite", "scale": 1.0, "flip": false},
	{"scene": "skill_1_scratch_spine", "sfx": "effect_scratch", "scale": 1.0, "flip": true},
]

## 크리티컬 타격 = 원작 스위치 case 3·4(`skill_1_hit_spine`, **배율 ×2.5**, tint 0xff3c35ef).
##
## 재구성 근거(2026-07-27 사용자 가설 → 스키마로 확인). 직접 증거는 아니고 정황이 전부 맞는 것이다:
##  · `info_dragon_v2` 의 컬럼 6~9 가 연속된 int 4개다 —
##      6 `attack_type` · 7 **`critical_type`** · 8 `critical_hit`(횟수) · 9 **`critical_type_ad`**
##    ⇒ 일반공격 타입과 크리티컬 타입이 **별개 컬럼**이다. `firstAttackEffect(node, int)` 는
##    타입 번호만 받으므로 같은 3종 스파인을 일반은 attack_type, 크리 는 critical_type 으로 고른다.
##  · `firstAttackEffect`/`secondAttackEffect` 가 같은 3종을 쓰면서 **태그가 다르다**
##    (first: -0xf3dda/-0xd151c/-0xc3ca11, second: -0xb6901/-0x2c6c65/-0xb7b3e5)
##    ⇒ 1타·2타를 따로 띄우는 구조 = 연타. `critical_type`(1타) + `critical_type_ad`(2타) 쌍과 맞물린다.
##  · 셋 중 hit 만 ×2.5 로 가장 크다 — 크리티컬용이라는 해석에 부합.
##  · `effect_headbutt` 은 원작 전투 프리로드 목록에 실재한다(`MakeInterface::preloadHeavyResource`).
## ⚠️ 미확정: `firstAttackEffect` 의 **호출부가 디컴파일 400+클래스에 없어** 인자가 attack_type 인지
##   critical_type 인지는 코드로 못 봤다. critical_type 의 값(3인지 4인지)도 서버 데이터라 유실.
const _CRIT_FX := {"scene": "skill_1_hit_spine", "sfx": "effect_headbutt", "scale": 2.5, "flip": false}
## 타격 스파인 재생 길이 — `scenes/fx/skill_1_hit_spine.tscn` 의 `animation` 길이(0.2초, 30fps 6프레임).
## 크리티컬 시퀀스가 이 시간을 기다린 뒤 전체 아트로 넘어간다(안 기다리면 아트가 타격을 덮는다).
const _HIT_FX_DUR := 0.2
## 🔴 원작 노드 구조 (2026-07-27 디컴프로 확정) — **이펙트는 몸통의 형제다**
##
## `BattleMonster` 는 `getAnimatedSpriteNode()`(this+0x58) 컨테이너 하나를 두고 그 **자식으로**
## 몸통과 이펙트를 나란히 붙인다(BattleMonster.c:3578-3596 정리 루프에서 태그가 드러난다):
##
##     컨테이너 (getAnimatedSpriteNode)
##     ├─ tag 200    idle 스파인 `wait`      ← 피격 시 setVisible(false)  (:3589-3591)
##     ├─ tag 300    hit 아트 스프라이트      ← 피격 시 생성해 addChild    (:3655-3657)
##     ├─ tag 0x12f  att 아트 스프라이트      ← 정리 루프가 건너뛴다       (:3592-3593)
##     ├─ tag 0xbc8  상시 이펙트 스파인       ← 정리 루프 **예외**         (:3582, :5122)
##     └─ 그 외      removeFromParentAndCleanup(true)                     (:3594-3596)
##
## 즉 **원작도 피격 때 스파인을 숨긴다**(프레임 교체가 아니다). 그래도 이펙트가 안 사라지는 이유는
## 이펙트가 스파인의 자식이 아니라 **컨테이너의 형제**이기 때문이다. 스킬 이펙트도 같다 —
## `AdventureScene::setCheckShildImpact` 가 `BattleMonster::getAnimatedSpriteNode()` 를 부모로
## `addChild(spine, 100)` 한다(AdventureScene.c:38855, 부모 추적 = plVar10).
##
## 우리 트리에서는 `self` 가 그 컨테이너 역할이다(mspr·att_spr·hit_spr 가 전부 self 의 자식).
## 그래서 이펙트도 **self 의 자식**으로 붙인다.
##   🔴 이전에는 `node`(=몬스터 스파인)의 자식으로 붙여서 `_monster_hit_motion` 이
##      `node.visible = false` 하는 0.15초 동안 이펙트가 함께 사라졌다(2026-07-27 수정).
##   부수 효과로 몸통 진동/확대를 물려받지 않게 되는데 **그게 원작과 같다** — 원작이 흔드는 것은
##   컨테이너가 아니라 att/hit 스프라이트다(setAnimatedAttack/Hit 가 그 스프라이트에 runAction).
##
## `entry` 를 주면 그 타입으로, 안 주면 일반공격 2종 중 랜덤.
func _normal_attack_fx(target: Dictionary, entry := {}) -> bool:
	if target.is_empty(): return false
	var pick: Dictionary = entry if not entry.is_empty() else _ATK_FX[randi() % _ATK_FX.size()]
	var path := "res://scenes/fx/%s.tscn" % pick["scene"]
	if not ResourceLoader.exists(path):
		return false
	var holder := Node2D.new()
	holder.z_index = 10                                  # 원작 addChild(spine, 10)
	add_child(holder)
	holder.position = target.get("center", _vis() * 0.5)
	# 몸통 배율(몬스터 0.85 / 보스 0.66)은 우리 레이아웃 값이라 이펙트에도 같이 곱해 크기를 유지한다.
	var bs: Vector2 = target.get("base_scale", Vector2.ONE)
	var s := float(pick["scale"])
	holder.scale = Vector2(-s if bool(pick["flip"]) else s, s) * bs
	var inst = (load(path) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
	if ap == null or not ap.has_animation("animation"):
		holder.queue_free()
		return false
	ap.get_animation("animation").loop_mode = Animation.LOOP_NONE
	ap.play("animation")
	Bgm.sfx(String(pick["sfx"]))
	var t := holder.create_tween()
	t.tween_interval(ap.get_animation("animation").length / maxf(0.5, _speed))
	t.tween_callback(holder.queue_free)
	return true

## 원작 일반공격 타격 연출: scene/adventure/effect_bullet(임팩트) + txt_hit(HIT). 피격 지점에 순간 표시.
func _normal_impact(v: Dictionary, crit: bool) -> void:
	if v.is_empty(): return
	var c: Vector2 = v.get("center", _vis() * 0.5)
	# effect_bullet(229×201): 타격 임팩트 — 작게 팡 터지고 사라짐(가산 블렌드).
	var b := _spr("adventure_ui", "scene_adventure_effect_bullet", _adv, 1.0)
	if b:
		b.position = c
		b.z_index = 95
		b.scale = Vector2(0.35, 0.35) * (1.25 if crit else 1.0)
		var am := CanvasItemMaterial.new(); am.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		b.material = am
		add_child(b)
		var tb := b.create_tween()
		tb.tween_property(b, "scale", Vector2(0.72, 0.72) * (1.25 if crit else 1.0), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tb.parallel().tween_property(b, "rotation", randf_range(-0.3, 0.3), 0.12)
		tb.tween_property(b, "modulate:a", 0.0, 0.16)
		tb.tween_callback(b.queue_free)
	# 🔴 2026-07-26 제거: 여기서 `scene/adventure/txt_hit`("HIT!")를 띄우고 있었지만,
	#   그 프레임의 원작 소유자는 **ShadowMonsterLayer**(탐험의 그림자 몬스터 탭 미니게임)다
	#   (`asset_index.py --grep txt_hit` → orig=ShadowMonsterLayer). 전투 화면에는 쓰이지 않는다.
	#   레퍼런스 docs/ref/orig_image/battle/{몬스터피격,몬스터피격2,몬스터중상}.png 어디에도 "HIT!"가 없고,
	#   대신 **붓글씨 의성어**(monster/hit_talk)와 큰 데미지 숫자만 뜬다 → _hit_talk()로 대체.
	#   txt_hit/txt_miss는 adventure.gd의 그림자 미니게임에서 계속 원작대로 쓴다.

## 몬스터 피격 유리깨짐 — 원작 `monster/hit_effect/hit_effect_1.png` · `_2.png`(384×260).
## 근거: `asset_index.py --grep hit_effect` → 원작 사용(libgame.so), 우리는 미사용이었다(🟠).
##   레퍼런스 docs/ref/orig_image/battle/몬스터공격.png = 몬스터 위에 흰 유리 균열이 크게 깔린다.
## 2프레임을 빠르게 갈아끼워 "쩍" 하고 갈라진 뒤 흩어지듯 사라진다.
func _hit_crack(v: Dictionary, crit: bool) -> void:
	if v.is_empty(): return
	var man := _man("hit_effect")
	var f1 := _spr("hit_effect", "monster_hit_effect_hit_effect_1", man, Design.ASSET_SCALE)
	if f1 == null: return
	var c: Vector2 = v.get("center", _vis() * 0.5)
	f1.position = c
	f1.z_index = 97
	f1.scale *= (1.25 if crit else 1.0)
	f1.rotation += randf_range(-0.25, 0.25)
	add_child(f1)
	var f2 := _spr("hit_effect", "monster_hit_effect_hit_effect_2", man, Design.ASSET_SCALE)
	if f2:
		f2.position = c; f2.z_index = 97; f2.visible = false
		f2.scale = f1.scale; f2.rotation = f1.rotation
		add_child(f2)
	var t := create_tween()
	t.tween_interval(0.07)
	t.tween_callback(func():
		if is_instance_valid(f1): f1.visible = false
		if is_instance_valid(f2): f2.visible = true)
	t.tween_interval(0.10)
	t.tween_callback(func():
		for n: Sprite2D in [f1, f2]:
			if not is_instance_valid(n): continue
			var ft: Tween = n.create_tween()
			ft.tween_property(n, "modulate:a", 0.0, 0.18)
			ft.parallel().tween_property(n, "scale", n.scale * 1.15, 0.18)
			ft.tween_callback(n.queue_free))

## 몬스터 타격 의성어 — 원작 `monster/hit_talk/story{N}_{KR|EN|JP}.png`(붓글씨 "우쩍/크엑!/컥!" 등 31종).
## 근거: `asset_index.py --grep hit_talk` → 93프레임(언어 3종 × 31), 원작 패턴
##   `monster/hit_talk/story%d_%s.png`, 우리는 전량 미사용이었다(🟠). DV2/480/monster/hit_talk.img_plist.
## 레퍼런스 docs/ref/orig_image/battle/몬스터피격2.png: 몬스터를 때린 순간 화면 **우상단**에 큰 붓글씨("우쩍")가
##   기울어져 팍 나타났다 사라진다. 폭은 화면의 약 30%(390px/1305 → 실측).
var _hit_talk_keys: Array = []
## 화면에 떠 있는 의성어 한 장(원작은 동시에 하나).
var _hit_talk_node: Node2D = null
## 레퍼런스 실측값 — 위 bbox 계산 근거.
const _HIT_TALK_W := 0.293
const _HIT_TALK_CX := 0.696
const _HIT_TALK_CY := 0.174

func _hit_talk() -> void:
	if _hit_talk_keys.is_empty():
		var man := _man("hit_talk")
		for k in man.keys():
			if String(k).ends_with("_KR"): _hit_talk_keys.append(String(k))
		_hit_talk_keys.sort()
	if _hit_talk_keys.is_empty(): return
	# 원작 레퍼런스(docs/ref/orig_image/battle/몬스터피격2.png)에는 의성어가 **항상 한 장뿐**이다.
	# 연타 시 이전 것을 지우지 않아 겹쳐 쌓이던 버그를 여기서 막는다.
	if is_instance_valid(_hit_talk_node):
		_hit_talk_node.queue_free()
		_hit_talk_node = null
	var key: String = _hit_talk_keys[randi() % _hit_talk_keys.size()]
	var man2 := _man("hit_talk")
	var info: Dictionary = man2.get(key, {})
	var w := maxf(1.0, float(info.get("w", 180)))
	var vis := _vis()
	# 레퍼런스 실측(docs/ref/orig_image/battle/몬스터피격2.png, 1304x740 / 워터마크 제외 흰테두리 검은획 bbox):
	#   폭 382/1304 = 0.293 · 중심 x 0.696 · 중심 y 0.174(위가 화면 밖으로 잘려 실제는 더 위)
	var sp := _spr("hit_talk", key, man2, (vis.x * _HIT_TALK_W) / w)
	if sp == null: return
	sp.position = Vector2(vis.x * _HIT_TALK_CX, vis.y * _HIT_TALK_CY)
	_hit_talk_node = sp
	sp.rotation = randf_range(-0.12, 0.12)
	sp.z_index = 99
	add_child(sp)
	sp.scale *= 0.5
	var target := sp.scale * 2.0
	var t := sp.create_tween()
	t.tween_property(sp, "scale", target, 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.30)
	t.tween_property(sp, "modulate:a", 0.0, 0.20)
	t.tween_callback(sp.queue_free)

## 크리티컬 컷인. 본체 = `scripts/ui/cutin.gd`(DragonCutin) — 레벨업 화면의 트리플맥스가
## 같은 컷인을 쓰므로 공용 헬퍼로 뽑았다(2026-07-27). 원작 근거·시간값은 그쪽 헤더에 있다.
## 크리티컬 시퀀스가 이 값만큼 기다린 뒤 타격을 넣는다(그 전에 때리면 막 아래에 깔려 안 보인다).
const _CUTIN_TOTAL := DragonCutin.TOTAL

func _critical_cutin(caster: Dictionary) -> void:
	# 본체는 `scripts/ui/cutin.gd`(DragonCutin) 로 옮겼다 — 레벨업 화면의 트리플맥스 연출이
	# 같은 컷인을 쓰기 때문(사용자 확인 2026-07-27). 연출 파라미터·원작 근거는 그쪽 주석 참조.
	DragonCutin.show(self, caster, _speed)


## 크리티컬 스파인 — 원작 `MakeInterface::criticalEffectMake`(MakeInterface.c:9853-9925) +
## `criticalPlaceEffect`(:9935-) 를 그대로 옮긴 것. 포팅 카드: `docs/ref/porting/MakeInterface_critical.md`.
##
##   getAwaken()==0 ? "dragon/dragon_%d_critical_spine.spine_json"
##                  : "dragon/dragon_%d_e_critical_spine.spine_json"
##   아틀라스 = dragon/dragon_%d_spine.img_plist   ← 크리티컬 전용이 아니라 **일반 스파인 아틀라스**
##   createWithFile(json, atlas, 1.0) · setScaleX(음수 = X반전) · addChild(spine, 8, -2)
##   재생 = Show → runSpineWithAnimationName("animation") → DelayTime(getDuration("animation"))
##
## ⚠️ 붙는 곳은 **공격자가 아니라 대상(target)의 레이어**다 — 원작이 param_2(target)의
##    getDragonLayer() 에 addChild 한다. 스파인 자체는 공격자(param_1) 것을 쓴다.
func _critical_spine(caster: Dictionary, target: Dictionary) -> bool:
	# 🔴 2026-08-07 — 그림 id 는 `PartyStats` 가 실어 준 상속 art_id 를 먼저 본다.
	var cid := int(caster.get("art_id", caster.get("id", 0)))
	var stage := "e_critical" if bool(caster.get("awakened", false)) else "critical"
	var path := "res://scenes/dragons/dragon_%d_%s.tscn" % [cid, stage]
	if not ResourceLoader.exists(path):
		# 각성본이 없으면 기본 크리티컬로 폴백(원본에 e_ 스켈레톤이 없는 드래곤이 다수다).
		path = "res://scenes/dragons/dragon_%d_critical.tscn" % cid
		if not ResourceLoader.exists(path):
			return false
	var holder := Node2D.new()
	holder.z_index = 8                                   # 원작 addChild(spine, 8, -2)
	var node = target.get("node")
	if node is Node2D and is_instance_valid(node):
		node.add_child(holder)
	else:
		add_child(holder)
		holder.position = target.get("center", _vis() * 0.5)
	# 원작 setScaleX(-(|scaleX|/scaleY) * n) — 부호가 핵심(공격 방향으로 뒤집는다).
	# ASSUMPTION: 배율 크기는 대상 레이어의 스케일 비에서 오는데 우리 카드/스프라이트는
	#   그 계층이 없다 → 반전만 취하고 크기는 원작 createWithFile 배율 1.0 을 쓴다.
	holder.scale = Vector2(-1.0, 1.0)
	var inst = (load(path) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
	if ap == null:
		holder.queue_free()
		return false
	# 원작은 `runSpineWithAnimationName("animation")` 하나만 쓴다. 다만 원본 스켈레톤 중
	# `dragon_4007` 은 애니 이름이 `critical` 이라 그대로는 아무것도 재생되지 않는다
	# (원작에서도 마찬가지였을 것이다). ASSUMPTION: 데이터 편차로 보고 대체명을 하나 허용한다.
	var pick := ""
	for cand in ["animation", "critical"]:
		if ap.has_animation(cand):
			pick = cand
			break
	if pick == "":
		holder.queue_free()          # dragon_9999(플레이스홀더 스켈레톤) 등
		return false
	ap.get_animation(pick).loop_mode = Animation.LOOP_NONE
	ap.play(pick)
	# 원작은 `CCDelayTime(getDuration("animation"))` — 애니 길이만큼만 띄운다(고정 초가 아니다).
	var t := holder.create_tween()
	t.tween_interval(ap.get_animation(pick).length / maxf(0.5, _speed))
	t.tween_callback(holder.queue_free)
	return true

## 원작 데미지 숫자 폰트(font_normal = "Fontdinerdotcom Huggable", 숫자 0-9 전용 비트맵).
## 숫자만 담아 두부 위험 0. 크리티컬 = 금색+확대(원작도 별도 "!"글자 없음).
const _NUM_FONT := "res://assets/480/font/font_normal.fnt"
var _num_font_cache: Font = null
func _dmg_number(pos: Vector2, dmg: int, crit: bool) -> void:
	var l := Label.new()
	l.text = str(dmg)   # 순수 숫자만(font_normal 커버)
	if _num_font_cache == null and ResourceLoader.exists(_NUM_FONT):
		_num_font_cache = load(_NUM_FONT)
	if _num_font_cache != null:
		l.add_theme_font_override("font", _num_font_cache)
	# 원작 InterFace::setDamagedHp — font_normal.fnt(원본 size **56**)에 setScale **1.5**(일반)/
	# **2.0**(강타·크리)를 건다 ⇒ 표시 크기 84 / 112 포인트.
	# 근거: docs/ref/orig_code/decomp/InterFace.c:6435 CCLabelBMFont(font/font_normal.fnt),
	#       :6544-6553 fVar29 = 1.5 / 2.0, :6554 CCScaleTo(0, fVar29);
	#       assets/480/font/font_normal.fnt `info ... size=56`.
	# 레퍼런스 실측(docs/ref/orig_image/battle/몬스터피격.png "45") 숫자 높이 ≈ 90px / 1.062 = 85 디자인px ≒ 84 ✓
	# (이전 구현은 28/40 — 원작의 1/3 크기였다.)
	var base := 56.0
	var s := 2.0 if crit else 1.5
	l.add_theme_font_size_override("font_size", int(round(base * s)))
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2) if crit else Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0.4, 0.1, 0.0, 0.9) if crit else Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6 if crit else 5)
	l.z_index = 101
	l.position = pos + Vector2(-24 if crit else -18, -60)
	add_child(l)
	# 원작 연출: JumpTo(0.5·dur, 목표, 높이 **150**, 1회) EaseInOut(0.375) +
	#   ScaleTo(0.05·dur, s*1.1) → ScaleTo(0.05·dur, s) → ScaleTo(0.4·dur, s*0.8) +
	#   Delay(0.25·dur) → FadeTo(0.25·dur, 0) EaseOut.  (InterFace.c:6554-6570)
	#   목표 x 오프셋 = ±75(일반) / ±112.5(강타).
	const DUR := 0.9
	var dx := (112.5 if crit else 75.0) * (1.0 if (dmg % 2) == 0 else -1.0)
	l.pivot_offset = Vector2(20, 20)
	var jt := create_tween()
	jt.tween_property(l, "position:x", l.position.x + dx, DUR * 0.5).set_trans(Tween.TRANS_SINE)
	var jy := create_tween()   # 점프 궤적(위로 150 올랐다 내려옴)
	jy.tween_property(l, "position:y", l.position.y - 150.0, DUR * 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	jy.tween_property(l, "position:y", l.position.y, DUR * 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var st := create_tween()
	st.tween_property(l, "scale", Vector2(1.1, 1.1), DUR * 0.05)
	st.tween_property(l, "scale", Vector2.ONE, DUR * 0.05)
	st.tween_property(l, "scale", Vector2(0.8, 0.8), DUR * 0.4)
	var ft := create_tween()
	ft.tween_interval(DUR * 0.25)
	ft.tween_property(l, "modulate:a", 0.0, DUR * 0.25).set_ease(Tween.EASE_OUT)
	ft.tween_callback(l.queue_free)

func _float(pos: Vector2, text: String, color: Color, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.position = pos + Vector2(-10, -10)
	l.z_index = 100
	add_child(l)
	var t := create_tween()
	t.tween_property(l, "position:y", l.position.y - 46, 0.6)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)

func _fx_text(v: Dictionary, frame: String, fallback: String, col: Color, adv_frame := "") -> void:
	if v.is_empty(): return
	# 1순위 battle_ui, 2순위 adventure_ui(원작 txt_miss 등), 최후 텍스트 폴백.
	var s: Sprite2D = null
	if frame != "":
		s = _spr("battle_ui", frame, _bat, 0.9)
	if s == null and adv_frame != "":
		s = _spr("adventure_ui", adv_frame, _adv, 0.9)
	if s:
		s.position = v["center"] + Vector2(0, -30)
		s.z_index = 100
		add_child(s)
		var t := create_tween()
		t.tween_property(s, "position:y", s.position.y - 30, 0.5)
		t.parallel().tween_property(s, "modulate:a", 0.0, 0.5)
		t.tween_callback(s.queue_free)
		return
	_float(v["center"] + Vector2(0, -20), fallback, col, 20)

## 각성 게이지 미러. 충전량은 로직(Battle._act)과 **같은 출처**를 본다 —
## `data/combat.json awaken.charge_per_turn`. 여기 숫자를 박아 두면 로직과 어긋난다.
## ⚠️ 게이지 바 자체는 숨김이다(_party_card 참조). 시스템은 그대로 돌아간다.
## 진영 게이지 동기화 — 🟦 2026-08-06. 게이지는 **드래곤당이 아니라 진영당**이고
## (`Battle._bind_side_gauge`), 행동·피격·react 가 함께 올린다. 화면이 `charge_per_turn` 으로
## 자체 추정하던 종전 방식(`_charge_gauge`)은 이제 반드시 어긋나므로 폐기했다 —
## `simulate` 가 모든 이벤트에 실어 주는 `gauge_ally`/`gauge_enemy` 를 그대로 그린다.
func _sync_gauge(ev: Dictionary) -> void:
	if not ev.has("gauge_ally"):
		return                     # 구 세이브·구 이벤트 로그 호환(그리지 않는다)
	var val := float(ev.get("gauge_ally", 0.0))
	for v in _views.values():
		if v is Dictionary and (v as Dictionary).get("kind") == "party":
			_set_gauge(v, val)


func _set_gauge(v: Dictionary, val: float) -> void:
	if v.is_empty() or v.get("kind") != "party": return
	v["gauge"] = val
	var fill = v.get("gauge_fill", null)
	if fill != null and is_instance_valid(fill):
		var w := float(v.get("gauge_w", 100)) * clampf(val / 100.0, 0.0, 1.0)
		create_tween().tween_property(fill, "size:x", w, 0.2)
		# 만충 시 반짝(발동 임박)
		(fill as ColorRect).color = Color(1, 0.95, 0.5) if val >= 100.0 else Color(1, 0.8, 0.25)

## 상태효과 배지(원작 버프/디버프/DoT 표시): 대상 위에 상태 아이콘이 뜨고 잠시 유지 후 페이드.
## 전투 승리 시 드래곤별 경험치 바 — 원작 **`SmallExpLayer`**(`SmallExpLayer.c`, 전량 디컴파일).
## 원작 `AdventureScene::setDragonExpIncrease` → `setDragonExpLabel(dragon, pos, …)` 가 만들고
## `MoveBy(0.25, (0, …+110))` + `EaseExponentialOut` 으로 카드 위로 떠오르게 한다.
##
## 원작 구성(`SmallExpLayer::initWidget` @00d11e3c · `setExpFinish` @00d1214c):
##   · `9patch/dialogue_box` 스케일9, capInsets **(10,10,4,4)**, contentSize **(250, 60)**, 앵커(0.5,0.5)
##   · `common/bar_bg2` 앵커(0.5,0.5) @ (w/2, h/2 **- 5**)
##   · `common/bar_exp` 앵커(0,0) — `Delay(0.5)` 뒤 `ScaleTo(0.6, 비율, 1.0)` 로 차오른다
##   · `scene/adventure/icon_exp` 앵커(0,0.5) + 획득량 BMFont(font_subtitle) 앵커(0,0.5)
##   · 등장 = `Delay(0.3)` → `Spawn(FadeTo(0.25,255), EaseExponentialOut(MoveBy(0.25,(0,25))))`
##          → `ScaleTo(0.25, s+0.2)` → `ScaleTo(0.25, s)`
const _SMALLEXP_SIZE := Vector2(250.0, 60.0)
func _small_exp_layer(uid: int, gained: int, slot: int) -> void:
	if gained <= 0:
		return
	var d := UserDB.get_dragon(uid)
	if d.is_empty():
		return
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var w := _SMALLEXP_SIZE.x
	var h := _SMALLEXP_SIZE.y
	# 원작은 드래곤 카드 위 좌표를 넘겨받는다 — 우리 카드 3칸 배치에 맞춰 그 위로 띄운다.
	var col := vis.x * (0.18 + 0.32 * float(clampi(slot, 0, 2)))
	# 결산 오버레이(CanvasLayer 60)보다 위에 떠야 한다 — 원작도 보상 시퀀스 위에 뜬다.
	var lay := CanvasLayer.new(); lay.layer = 62; add_child(lay)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.position = Vector2(col - w * 0.5 * S, vis.y - 150.0)
	root.scale = Vector2(S, S)
	root.modulate.a = 0.0
	lay.add_child(root)
	var box := NinePatchRect.new()
	box.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres")
	box.patch_margin_left = 10; box.patch_margin_right = 10
	box.patch_margin_top = 4; box.patch_margin_bottom = 4
	box.size = Vector2(w, h)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	# 경험치 게이지 — bar_bg2 위에 bar_exp(앵커 좌하단)를 얹어 가로로 채운다.
	var cm := _man("common_ui")
	var bg := _spr("common_ui", "common_bar_bg2", cm, 1.0)
	if bg:
		bg.position = Vector2(w * 0.5, h * 0.5 - 5.0)
		root.add_child(bg)
		var fill := _spr("common_ui", "common_bar_exp", cm, 1.0)
		if fill:
			var fw := float((cm.get("common_bar_exp", {}) as Dictionary).get("w", 1))
			var fh := float((cm.get("common_bar_exp", {}) as Dictionary).get("h", 1))
			fill.centered = false                                   # 원작 앵커(0,0)
			fill.position = Vector2(-fw * 0.5, -fh * 0.5)
			bg.add_child(fill)
			var lv := int(d.get("level", 1))
			var need := maxi(1, LevelSystem.exp_to_next(Data.level_curve, lv))
			var ratio: float = clampf(float(int(d.get("exp", 0)) + gained) / float(need), 0.0, 1.0)
			fill.scale = Vector2(0.0, 1.0)
			var tf := fill.create_tween()
			tf.tween_interval(0.5)                                   # 원작 Delay(0.5)
			tf.tween_property(fill, "scale", Vector2(ratio, 1.0), 0.6)
	var ic := _spr("adventure_ui", "scene_adventure_icon_exp", _adv, 1.0)
	if ic:
		ic.position = Vector2(18.0, h * 0.5 + 16.0)
		root.add_child(ic)
	var lb := _bmf_label("subtitle", 1.0)
	lb.text = "+%d" % gained
	lb.position = Vector2(36.0, h * 0.5 + 4.0)
	root.add_child(lb)
	# 등장 안무(원작 setExpFinish 그대로).
	var t := root.create_tween()
	t.tween_interval(0.3)
	t.tween_property(root, "modulate:a", 1.0, 0.25)
	# 원작은 두 겹으로 띄운다: setDragonExpLabel 이 레이어째 **+110**, setExpFinish 가 내부에서 **+25**.
	t.parallel().tween_property(root, "position:y", root.position.y - 135.0, 0.25) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(root, "scale", Vector2(S + 0.2, S + 0.2), 0.25)
	t.tween_property(root, "scale", Vector2(S, S), 0.25)
	t.tween_interval(1.2)
	t.tween_property(root, "modulate:a", 0.0, 0.3)
	t.tween_callback(lay.queue_free)

## 방어막 임팩트 — 원작 `AdventureScene::setCheckShildImpact` @00c8cdb4.
##
## 🔴 2026-07-31 정정: 처음엔 "전용 스파인이 없는 **방어 카테고리 스킬 시전**"에 붙였는데
##   **원작 조건이 아니었고, 심지어 죽은 코드였다**(방어 스킬 5종 11·12·13·20·28 이 전부 전용
##   스파인을 갖고 있어 그 앞의 `_play_skill_spine` 에서 return 돼 도달 자체를 못 했다).
##   원작 조건은 `startAttack` @00c89038 이 **피격 처리 중** 슬롯마다 `setCheckShildImpact(slot)` 을
##   부르고, 그 안에서 `iVar5 != 0xb && !InterFace::isBuffDebuffExist(대상, 0xb)` 이면 건너뛴다 —
##   즉 **스킬 `0xb`=11(철갑 방패) 판정**이다. 그래서 "그 피격에서 방어 스킬이 발동했는가"에 붙인다.
##
## 원작 연출: `skill/skill_adbloking_spine` `setAnimation("animation", loop=false)` → `Delay(0.7)` → Hide.
## 파티클 `pt_shild` 는 `makeSkillParticle` @00c9e4a4 소유인데 **그 함수의 호출자를 400클래스에서
## 못 찾았다**(함수 포인터로 불리는 듯) → 조건 불명. 이름이 실드로 명확해 같은 순간에 함께 낸다
## (# ASSUMPTION — 조건이 밝혀지면 여기만 고친다).
const _SHIELD_SKILL := 11              # 원작 리터럴 0xb = 철갑 방패
func _shield_impact(v: Dictionary, fired_skill_id: int) -> void:
	if v.is_empty() or fired_skill_id != _SHIELD_SKILL:
		return
	_play_fx_spine_scene("res://scenes/worldmap_fx/skill_adbloking_spine.tscn", v)
	if v.has("center"):
		CocosParticle.spawn(self, "pt_shild", v["center"], 99, 0.4)

## 흡혈 임팩트 — 원작 `AdventureScene::setVampImpact` @00ca52e4 (`(피격 위치, 시전자 위치)`).
## 원작이 하는 일 두 가지:
##   ① `common/backlight1.png` 를 피격 지점에 anchor(0.5,0.5)·scale **0.1**·색 **(0xdb,0x83,0x83)**
##      으로 놓고 → ScaleTo(0.3, 0.4) → (0.1↔0.4 3회 맥동) + RepeatForever(RotateBy(0.5, 360°))
##      → MoveTo(0.6, 시전자) + FadeOut(0.3)  = 붉은 구슬이 돌며 시전자에게 빨려간다
##   ② 파티클 `particle/scene/adventure/pt_skill_14_vamp.plist` 를 같은 지점에 scale **0.8**
##
## ⚠️ ①의 `common/backlight1.png` 은 **추출 아틀라스에 없다** — `grep -c backlight1
##    DV2/480/common.img_plist` → 0 (backlight3·backlight4 만 실재). 그림이 없으니 흉내 내지 않고
##    **파티클(②)만** 낸다(CLAUDE.md §3). 프레임을 확보하면 여기 한 곳에 ①을 더하면 된다.
func _vamp_impact(victim: Dictionary, attacker: Dictionary) -> void:
	if victim.is_empty() or not victim.has("center"):
		return
	CocosParticle.spawn(self, "pt_skill_14_vamp", victim["center"], 131, 0.6)

## 버프/디버프 아이콘(원작 **Bicon**) — 전투원에 걸린 효과를 **그 효과를 건 스킬 아이콘**으로 쌓아 둔다.
##
## 🔴 2026-07-31 교체: 종전엔 `독`·`▲`·`▼`·`!` **텍스트 글리프**를 그렸다 — 전부 자작이었다.
##   원작은 `AdventureScene::setBiconSkillSetting` @00ca42b4 이 **`skill/%d.png`(스킬 아이콘)**을
##   띄우고, `InterFace::setBiconPositioning` @00d3c3f0 이 전투원마다 행으로 늘어놓는다
##   (`CCArray` @InterFace+0x120, 기준점 `getBuffDebuffBasicPoint`).
##
## 원작 안무(setBiconSkillSetting 그대로):
##   Spawn(EaseExponentialInOut(MoveBy 0.4), ScaleTo(0.4, 0.5))
##   → ScaleTo(0.4, 1.8) → ScaleTo(0.4, 1.5) → ScaleTo(0.2, 1.7) → ScaleTo(0.2, 0.7)
##   → Spawn(EaseExponentialInOut(MoveTo 0.4, 슬롯), ScaleTo(0.4, 0.1)) → FadeOut(0.2)
## 정렬은 MoveTo(0.2) 로 `기준점 + (270*n, dy)`.
##
## ⚠️ 간격 리터럴 270 은 원작 InterFace 의 좌표계(카드가 훨씬 크다) 값이라 그대로 쓰면 화면을
##   벗어난다 → **아이콘 실폭 비율로 환산**해 쓴다(원작 리터럴은 `_BICON_STEP_ORIG` 에 보존).
##   원작 카드 계층(InterFace)을 그대로 이식하면 그때 리터럴로 되돌린다.
const _BICON_STEP_ORIG := 270.0        # 원작 setBiconPositioning 가로 간격
const _BICON_BASE_PX := 85.0           # skill/buff·debuff 실측
const _BICON_SCALE := 0.42             # 카드 위에 얹히는 크기(바탕 85px → 약 36pt)
const _BICON_MAX := 4                  # 카드 폭을 넘지 않는 선

## 아이콘 한 장을 붙인다 — **원작 `Bicon::init` @00d2ffd4 구조 그대로**
## (2026-07-31 `batch_decompile.py --classes Bicon` 으로 새로 디컴파일해 확정):
##   ① 바탕 = `skill/buff.png`(버프) / `skill/debuff.png`(디버프)  ← 85×85
##   ② 스킬 아이콘 = `skill/%d.png` 를 **scale 0.9** 로 바탕 중앙에
##   ③ 남은 턴 = 버프면 `font/font_heal.fnt` **scale 1.5**, 디버프면 `font/font_total.fnt` scale 1.0.
##      바탕 중앙에 앵커 **(0.0, 0.2)** 로 붙는다(= 오른쪽 아래로 흘러나오는 숫자).
## `Bicon::setTurnCount` 가 턴이 줄 때마다 이 숫자를 갱신한다.
## 출처 스킬을 모르면 아무것도 그리지 않는다 — 원작 아이콘의 근거가 스킬이라 대체물이 없다.
func _bicon_add(v: Dictionary, skill_id: int, is_buff := false, turns := 0) -> void:
	if v.is_empty() or not v.has("center") or skill_id <= 0:
		return
	var icon_path := "res://assets/converted/skill/skill_%d.tres" % skill_id
	if not ResourceLoader.exists(icon_path):
		return
	var sm := _man("skill")
	var row: Array = v.get("bicons", [])
	# 원작 InterFace의 Bicon 배열은 같은 스킬을 무제한 쌓지 않는다.
	# 이미 있는 아이콘은 추가하지 않고 남은 턴만 갱신한다.
	for existing in row:
		if is_instance_valid(existing) and int(existing.get_meta("skill_id", 0)) == skill_id:
			if turns == 0:
				row.erase(existing)
				existing.queue_free()
				v["bicons"] = row
				_bicon_positioning(v)
			else:
				_bicon_set_turn(existing as Sprite2D, turns)
			return
	# -1은 영구 효과(원작 Bicon에 숫자 없이 표시), 0만 만료다.
	if turns == 0:
		return
	if row.size() >= _BICON_MAX:
		var old: Sprite2D = row.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var c: Vector2 = v.get("bicon_origin", v["center"])
	# ① 바탕
	var base := _spr("skill", "skill_buff" if is_buff else "skill_debuff", sm, _BICON_SCALE * 0.5)
	if base == null:
		return
	base.z_index = 96
	base.set_meta("skill_id", skill_id)
	base.set_meta("is_buff", is_buff)
	add_child(base)          # ⚠️ battle.gd 의 `_spr` 은 트리에 붙이지 않는다(생성만)
	base.position = c
	# ② 스킬 아이콘(바탕 중앙, 0.9)
	var ico := Sprite2D.new()
	ico.texture = load(icon_path)
	ico.material = _pma
	ico.scale = Vector2.ONE * 0.9
	base.add_child(ico)
	# ③ 남은 턴
	if turns > 0:
		var lb := _bmf_label("heal" if is_buff else "total", 1.5 if is_buff else 1.0)
		lb.name = "TurnCount"
		lb.text = str(turns)
		lb.position = Vector2(0, -_BICON_BASE_PX * 0.2)   # 원작 앵커(0.0, 0.2)
		base.add_child(lb)
	row.append(base)
	v["bicons"] = row
	# 원작 setBiconSkillSetting 의 스케일 비트(0.5 → 1.8 → 1.5 → 1.7 → 0.7 → 슬롯).
	var t := base.create_tween()
	t.tween_property(base, "scale", Vector2.ONE * _BICON_SCALE * 0.5, 0.4) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(base, "scale", Vector2.ONE * _BICON_SCALE * 1.8, 0.4)
	t.tween_property(base, "scale", Vector2.ONE * _BICON_SCALE * 1.5, 0.4)
	t.tween_property(base, "scale", Vector2.ONE * _BICON_SCALE * 1.7, 0.2)
	t.tween_property(base, "scale", Vector2.ONE * _BICON_SCALE * 0.7, 0.2)
	t.tween_callback(_bicon_positioning.bind(v))
	_bicon_positioning(v)

## 원작 `Bicon::setTurnCount` 동작: 같은 아이콘의 숫자만 갱신한다.
func _bicon_set_turn(base: Sprite2D, turns: int) -> void:
	var lb := base.get_node_or_null("TurnCount") as Label
	if lb != null:
		lb.text = str(turns)

## 로직이 보낸 실제 효과 잔여 턴으로 Bicon을 갱신/제거한다.
func _bicon_tick(v: Dictionary, skill_id: int, turns: int) -> void:
	if v.is_empty() or skill_id <= 0:
		return
	var row: Array = v.get("bicons", [])
	for existing in row.duplicate():
		if not is_instance_valid(existing) or int(existing.get_meta("skill_id", 0)) != skill_id:
			continue
		if turns > 0:
			_bicon_set_turn(existing as Sprite2D, turns)
		else:
			row.erase(existing)
			existing.queue_free()
	v["bicons"] = row
	_bicon_positioning(v)

## 원작 `AdventureScene::setRemoveAllBicon` @00c7ee40 — 그 전투원의 버프 아이콘을 전부 걷는다.
func _bicon_clear(v: Dictionary) -> void:
	for s in (v.get("bicons", []) as Array):
		if is_instance_valid(s):
			s.queue_free()
	v["bicons"] = []

## 원작 `InterFace::setBiconPositioning` — 행을 기준점부터 일정 간격으로 다시 늘어놓는다(MoveTo 0.2).
func _bicon_positioning(v: Dictionary) -> void:
	var row: Array = v.get("bicons", [])
	var live: Array = []
	for s in row:
		if is_instance_valid(s):
			live.append(s)
	v["bicons"] = live
	if live.is_empty() or not v.has("center"):
		return
	var c: Vector2 = v.get("bicon_origin", v["center"])
	var step := _BICON_BASE_PX * _BICON_SCALE * (_BICON_STEP_ORIG / 256.0)   # 원작 비율 환산
	var x0 := c.x
	for i in live.size():
		var s: Sprite2D = live[i]
		var tw := s.create_tween()
		tw.tween_property(s, "position", Vector2(x0 + step * i, c.y), 0.2)
		tw.parallel().tween_property(s, "scale", Vector2.ONE * _BICON_SCALE, 0.2)

## 스킬명 표시 — 원작 `AdventureScene::setSkillEffectName` @00ca3040.
##
## 🔴 2026-07-31 교체: 종전엔 30px 노란 라벨을 화면 y=150 에 그냥 얹었다(자작).
##   원작은 **`9patch/dialogue_box` 스케일9 패널 + `CCLabelTTF("Thonburi", 23)`** 이고,
##   패널 크기는 글자 크기 + **(20, 20)**, 라벨은 패널 중앙, 패널 앵커는 **(0.5, 0)** 이다.
##   (setSkillEffectName 리터럴: `9patch/dialogue_box.png` · `effect_skill_%d.mp3`)
func _skill_banner(name: String) -> void:
	if name == "":
		return
	var vis := _vis()
	var holder := Control.new()
	holder.z_index = 110
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var l := Label.new()
	l.text = name
	l.add_theme_font_size_override("font_size", 23)          # 원작 CCLabelTTF(…, 23.0)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(l)
	l.reset_size()
	var box := NinePatchRect.new()                            # 원작 CCScale9Sprite
	box.texture = load("res://assets/converted/ninepatch_ui/9patch_dialogue_box.tres")
	box.patch_margin_left = 10; box.patch_margin_right = 10
	box.patch_margin_top = 4; box.patch_margin_bottom = 4
	box.size = l.size + Vector2(20, 20)                       # 원작 setContentSize(w+20, h+20)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(box)
	holder.move_child(box, 0)                                 # 패널이 라벨 아래
	# 앵커(0.5, 0) = 가로 중앙 기준. 원작 좌표계는 y-up 이라 화면 위쪽 1/4 자리에 둔다.
	box.position = Vector2(vis.x * 0.5 - box.size.x * 0.5, vis.y * 0.22)
	l.position = box.position + Vector2(10, 10)
	var t := holder.create_tween()
	t.tween_interval(0.7)
	t.tween_property(holder, "modulate:a", 0.0, 0.2).from(1.0)
	t.tween_callback(holder.queue_free)

## 전투 오프닝(원작 OpeningBattleScene): "전투 시작!" 배너가 좌→우로 스윕 + 살짝 플래시.
## 이 전투가 보스 조우인지(스테이지 마지막 조우). params.boss로도 강제 가능.
## 이번 상대가 보스인가 — BGM(`bg_battle_boss`) · 등장 연출(`_boss_show_effect`) ·
## 보상 배수가 이걸 본다.
##
## 🔴 2026-07-31 (사용자 지적: 혼돈의 틈새인데 일반몹 BGM이 나온다).
##   종전엔 **조우 순번**(`enc + 1 >= total`)으로만 봤다. 그 판정은 `enemies` 가 "순서대로
##   만나는 목록"인 던전에서만 맞는다. 혼돈의 틈새·유타칸 밤처럼 `enemies` 가 **후보 목록**인
##   곳에서는 3종 중 1·2번째를 뽑으면 `enc+1 < total` 이라 보스인데도 일반몹이 됐다.
##   원작은 순번이 아니라 **그 몬스터가 보스인가**(`Monster::isBoss`)를 본다 → 그쪽을 먼저 본다.
##   순번 판정은 뒤에 남겨 둔다(보스 플래그가 없는 기존 던전 데이터용 폴백).
func _is_boss() -> bool:
	if _params.has("boss"): return bool(_params["boss"])
	if bool(_enemy.get("boss", false)): return true
	if not _params.has("stage"): return false
	var st: Dictionary = _stage_rec()
	var total := int((st.get("enemies", []) as Array).size())
	var enc := int(_params.get("enc", 0))
	return total > 0 and enc + 1 >= total

## 전투 개시 연출. **일반 조우엔 아무 연출도 없다** — 보스일 때만 `setNormalBossShowEffect`.
##
## 🔴 2026-07-31 제거: 종전엔 "전투 시작!" 반투명 띠 스윕 + 흰 플래시를 그렸는데 **전부 자작**이었다.
##   원작 `setEventFightStart`(AdventureScene.c)는 `Delay→CallFunc` 두 개가 전부고,
##   주석이 출처로 적어 둔 `OpeningBattleScene` 은 **프롤로그 전용**이다(`OpeningScene` 만 호출).
func _battle_opening() -> void:
	pass # 보스 출현 연출은 조우 즉시 adventure.gd에서 이미 재생된다.

## 원작 `AdventureScene::setNormalBossShowEffect` @00c7d0d8 — "보"·"스"·"출"·"현" 4글자가
## 화면 밖에서 날아와 자리를 잡는다. 리터럴은 딱 둘뿐이다(`effect_cut_in.mp3`, `txt_boss%d_%s.png`)
## — 붉은 비네트도, 보스 스프라이트 확대·흔들림도 원작엔 없다(2026-07-31 제거).
##
## 원작 그대로:
##   레이어 z=999998, 사운드 `music/effect_cut_in.mp3`
##   글자 i 초기 scale **2.0**, 시작 위치(cocos, W=가로 H=세로, Y0=H*0.75):
##     1 `(-300-W, Y0)`  2 `(W*0.35, Y0+300)`  3 `(W*0.7, Y0+300)`  4 `(W+300, Y0)`
##   각각 `Delay(0.6/0.9/1.2/1.5)` → `Spawn(ScaleTo(0.75, 1.0), EaseExponentialIn(MoveTo(0.8, 목표)))`
##   목표 x = 중앙 `-260 / -130+20 / +130-20 / +260`, y = `H*0.75` (가운뎃 간격만 넓다 — 원작 그대로)
## ⚠️ `local_22c`(시작 y)는 Ghidra 가 대입을 잃었다. 목표 y 와 같은 `H*0.75` 로 읽는 것이
##   1·4번 글자가 수평으로 날아오는 유일한 해석이라 그렇게 둔다(# ASSUMPTION).
const _BOSS_GLYPH_DELAY: Array[float] = [0.6, 0.9, 1.2, 1.5]
const _BOSS_GLYPH_DX: Array[float] = [-260.0, -110.0, 110.0, 260.0]
func _boss_show_effect() -> void:
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var cx := vis.x * 0.5
	var y := Design.flip_y(vis.y * 0.75, vis.y)      # cocos y-up → Godot
	var layer := Node2D.new()
	layer.z_index = 130
	add_child(layer)
	Bgm.sfx("effect_cut_in")                         # 원작 setPlayEffectSound(music/effect_cut_in.mp3)
	# 시작 위치도 cocos 리터럴 그대로 옮긴다(y 는 flip).
	var starts := [
		Vector2(-300.0 - vis.x, y),
		Vector2(vis.x * 0.35, y - 300.0),
		Vector2(vis.x * 0.7, y - 300.0),
		Vector2(vis.x + 300.0, y),
	]
	for i in 4:
		var g := _spr("adventure_ui", "scene_adventure_txt_boss%d_kr" % (i + 1), _adv, 2.0 * S)
		if g == null:
			continue
		g.position = starts[i]
		layer.add_child(g)
		var t := g.create_tween()
		t.tween_interval(_BOSS_GLYPH_DELAY[i])
		t.tween_property(g, "scale", Vector2.ONE * S, 0.75)
		t.parallel().tween_property(g, "position", Vector2(cx + _BOSS_GLYPH_DX[i], y), 0.8) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	# 마지막 글자가 자리를 잡고(1.5+0.8) 잠깐 머문 뒤 레이어째 사라진다.
	# ⚠️ 원작 지연은 `fVar24 + 1.0` 인데 Ghidra 가 fVar24 의 마지막 대입을 잃었다 → 2.3 으로 읽는다.
	var tl := layer.create_tween()
	tl.tween_interval(2.3 + 0.4)
	tl.tween_callback(layer.queue_free)

## 원작 setSuperAttackStart + makeSkillParticle: 각성기(awaken 평타) 발동 연출.
## 금빛 화면 플래시 + "각성기!" 배너 + 시전자 발광 + 방사 파티클.
func _super_attack_fx(caster: Dictionary) -> void:
	var vis := _vis()
	_screen_shake(14.0)
	Bgm.sfx("effect_bigbang")   # 원작 각성기 효과음   # 각성기 임팩트: 강한 화면 흔들림
	# 금빛 플래시
	var flash := ColorRect.new(); flash.color = Color(1, 0.92, 0.6, 0.0); flash.z_index = 118
	flash.set_anchors_preset(Control.PRESET_FULL_RECT); flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	var tf := flash.create_tween()
	tf.tween_property(flash, "color:a", 0.6, 0.1)
	tf.tween_property(flash, "color:a", 0.0, 0.4)
	tf.tween_callback(flash.queue_free)
	# "각성기!" 배너(팝)
	var banner := Label.new(); banner.text = "각성기!"
	banner.add_theme_font_size_override("font_size", 48)
	banner.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	banner.add_theme_color_override("font_outline_color", Color(0.4, 0.15, 0, 0.9))
	banner.add_theme_constant_override("outline_size", 7)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.size = Vector2(vis.x, 60); banner.position = Vector2(0, vis.y * 0.2)
	banner.z_index = 119; banner.pivot_offset = Vector2(vis.x * 0.5, 30); banner.scale = Vector2(0.4, 0.4)
	add_child(banner)
	var bt := banner.create_tween()
	bt.tween_property(banner, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
	bt.tween_interval(0.5)
	bt.tween_property(banner, "modulate:a", 0.0, 0.3)
	bt.tween_callback(banner.queue_free)
	# 시전자 발광 + 방사 파티클(makeSkillParticle)
	if not caster.is_empty() and caster.has("center"):
		var c: Vector2 = caster["center"]
		var burst := CPUParticles2D.new()
		burst.position = c; burst.z_index = 117; burst.emitting = true; burst.one_shot = true
		burst.amount = 28; burst.lifetime = 0.6; burst.explosiveness = 0.95
		burst.direction = Vector2(0, -1); burst.spread = 180.0
		burst.initial_velocity_min = 120.0; burst.initial_velocity_max = 280.0
		burst.gravity = Vector2(0, 60.0); burst.scale_amount_min = 3.0; burst.scale_amount_max = 7.0
		burst.color = Color(1, 0.9, 0.45)
		add_child(burst)
		get_tree().create_timer(0.9).timeout.connect(func(): if is_instance_valid(burst): burst.queue_free())
		var node = caster.get("node", null)
		if node is CanvasItem:
			var ci := node as CanvasItem
			var t := create_tween()
			t.tween_property(ci, "modulate", Color(1.6, 1.4, 0.8), 0.12)
			t.tween_property(ci, "modulate", Color.WHITE, 0.3)

## 승리 보상 연출(원작 CoinEffectLayer/GoldImpLayer/ExpLayer): 코인 버스트 + EXP 아이콘 상승.
func _reward_fx(gold: int, _exp: int) -> void:
	Bgm.sfx("effect_coin")   # 원작 코인 효과음
	var vis := _vis()
	var origin := Vector2(vis.x * 0.5, vis.y * 0.46)
	var cman := _man("common_ui")
	# 코인 버스트: 중앙서 여러 코인이 위로 튀었다가 낙하+페이드(양=골드 비례).
	var n := clampi(6 + gold / 40, 6, 14)
	for i in n:
		var cname: String = ["common_coin_small1", "common_coin_small2", "common_coin"][i % 3]
		var coin := _spr("common_ui", cname, cman, 0.7)
		if coin == null: continue
		coin.position = origin; coin.z_index = 120
		add_child(coin)
		var ang := randf_range(-PI * 0.82, -PI * 0.18)
		var peak := origin + Vector2(cos(ang), sin(ang)) * randf_range(70.0, 175.0)
		var t := coin.create_tween()
		t.tween_property(coin, "position", peak, 0.33).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(coin, "position", peak + Vector2(randf_range(-24, 24), 130.0), 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(coin, "modulate:a", 0.0, 0.42)
		t.tween_callback(coin.queue_free)
	# 🟠 2026-08-01 걷어냄(사용자 지적 — 자작 텍스트가 보상 페이즈와 **이중으로** 나왔다):
	#   종전 여기 있던 "골드 획득!" TTF 배너 · 대표 코인+`X %d` · `+N EXP` 초록 플로트 ·
	#   골드 텍스트박스 줄은 전부 `_play_reward_phases`(원작 setEventReward 이식)가 담당한다.
	#   이 함수에는 승리 순간의 **코인 산개**(보스승리1 의 전리품 산개 근사)만 남긴다.
	#   (원작 EXP 표기는 SmallExpLayer + 보상 페이즈 텍스트박스 몫)

## 경험치 지급 + 레벨업 처리 코디네이터(render→logic→data). UserDB 상태를 읽어 LevelSystem에 넘기고
## 결과(새 레벨/잔여 exp)를 다시 UserDB에 영속화한다. 반환=레벨업 이벤트(연출용). 규칙은 LevelSystem이 소유.
func _grant_exp(uid: int, amount: int) -> Dictionary:
	var d := UserDB.get_dragon(uid)
	if d.is_empty():
		return {"levels_gained": 0}
	var ddef := Data.get_dragon(int(d.get("id", 0)))
	var max_stats := Growth.tier_growth(ddef, Data.stat_table)   # 레벨당 스탯별 최대 상승량
	var roll_cfg: Dictionary = Data.level_curve.get("roll", {})
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var ev := LevelSystem.apply_exp(Data.level_curve, roll_cfg, max_stats,
		int(d.get("level", 1)), int(d.get("exp", 0)), amount, rng, bool(d.get("awakened", false)))
	# 롤 결과를 gain_log에 누적 + 레벨/exp 영속화(1회 커밋). 연출용 gains는 ev로 반환.
	# apply_levelups 안에서 레벨 10·25·45 자동 습득(sync_skill_grants)이 함께 돈다.
	var before := {}
	for s in UserDB.dragon_skills(uid):
		before[int((s as Dictionary).get("id", 0))] = true
	UserDB.apply_levelups(uid, int(ev["level"]), int(ev["exp"]), ev.get("gains", []))
	ev["max_stats"] = max_stats   # 연출: +상승/max 분모 표시용
	# 이번에 새로 배운 스킬(연출용) — 풀의 증분.
	var learned: Array = []
	for s in UserDB.dragon_skills(uid):
		var sid := int((s as Dictionary).get("id", 0))
		if not before.has(sid):
			learned.append(String(Data.skills.get(str(sid), {}).get("name", "스킬")))
	ev["learned_skills"] = learned
	return ev

## 레벨업 연출(원작 AdventureResultExpLevelup): 레벨 오른 드래곤마다 배지를 순차 팝업.
## 레벨 오른 드래곤마다 상세 패널을 순차 팝업. 원작 DragonEnchantResultLayer 재현:
## per-스탯 "+상승/max" + MAX/MAX+ 뱃지(초월=보라), 트리플맥스 시 LEVEL UP 날개 배너 + pt_3max + effect_max_fun.
const _STAT_KR := {"hp": "생명력", "att": "공격력", "def": "방어력"}
func _levelup_fx(events: Array) -> void:
	var vis := _vis()
	var iman := _man("item_etc")
	for i in events.size():
		var nm := String(events[i]["name"])
		var ev: Dictionary = events[i]["ev"]
		var gains: Array = ev.get("gains", [])
		if gains.is_empty():
			continue
		var max_stats: Dictionary = ev.get("max_stats", {})
		# per-스탯 집계: 총 상승 / 맥스 횟수 / 초월 여부. (여러 레벨이 한 번에 오르면 합산)
		var agg := {}
		for k in ["hp", "att", "def"]:
			agg[k] = {"gain": 0, "maxn": 0, "trans": false}
		var triples := 0
		for g in gains:
			if bool(g.get("triple", false)):
				triples += 1
			var ismax: Dictionary = g.get("is_max", {})
			var tm: Dictionary = g.get("tmax", {})
			for k in ["hp", "att", "def"]:
				agg[k]["gain"] = int(agg[k]["gain"]) + int(g.get(k, 0))
				if bool(ismax.get(k, false)):
					agg[k]["maxn"] = int(agg[k]["maxn"]) + 1
				if bool(tm.get(k, false)):
					agg[k]["trans"] = true
		var final_lv := int(ev.get("level", 0))
		var from_lv := final_lv - int(ev.get("levels_gained", gains.size()))
		_levelup_panel(iman, nm, from_lv, final_lv, agg, max_stats, gains.size(), triples,
			vis, i, 0.3 + i * 0.6, ev.get("learned_skills", []))

## 상세 레벨업 패널(원작 스탯 비교 화면 재현). agg=per-스탯 집계, single=1레벨(분모 /max 표기), triples=트리플맥스 레벨 수.
func _levelup_panel(iman: Dictionary, nm: String, from_lv: int, to_lv: int,
		agg: Dictionary, max_stats: Dictionary, levels: int, triples: int,
		vis: Vector2, idx: int, delay: float, learned: Array = []) -> void:
	var w := 424.0
	var row_h := 26.0
	var head_h := 32.0
	# 레벨 10·25·45 자동 습득이 걸린 레벨업이면 한 줄 더 붙인다.
	var h := head_h + row_h * (3.0 + (1.0 if not learned.is_empty() else 0.0)) + 12.0
	var any_trans := bool(agg["hp"]["trans"]) or bool(agg["att"]["trans"]) or bool(agg["def"]["trans"])
	var accent := Color(1.0, 0.82, 0.32)                # 일반 = 금색
	if triples > 0:
		accent = Color(1.0, 0.9, 0.42)                  # 트리플맥스 = 밝은 금
	elif any_trans:
		accent = Color(0.78, 0.58, 1.0)                 # 초월맥스 = 보라(원작)
	var cx_w := vis.x
	var y := vis.y * 0.06 + idx * (h + 8.0)
	var root := Control.new()
	root.z_index = 132
	root.position = Vector2(0, y)
	root.modulate.a = 0.0
	root.pivot_offset = Vector2(cx_w * 0.5, h * 0.5)
	root.scale = Vector2(0.62, 0.62)
	add_child(root)
	# 🟠 정정: 전투 중 레벨업 알림 패널이 자작 StyleBoxFlat 이었다.
	#   원작은 어두운 라운드 정보판에 `9patch/train_box4` 를 쓴다(레벨업 결과 계열에서 우리도 사용 중).
	#   트리플/초월일 때만 accent 로 물들여 강조한다.
	var panel := NinePatchRect.new()
	panel.texture = load("res://assets/converted/ninepatch_ui/9patch_train_box4.tres")
	panel.patch_margin_left = 22; panel.patch_margin_right = 22
	panel.patch_margin_top = 16; panel.patch_margin_bottom = 16
	panel.size = Vector2(w, h)
	panel.position = Vector2((cx_w - w) * 0.5, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if triples > 0 or any_trans:
		panel.modulate = accent.lerp(Color.WHITE, 0.55)
	root.add_child(panel)
	# 헤더: 레벨업 아이콘 + 이름 + Lv.a→b
	var icon := _spr("item_etc", "item_etc_level_up", iman, 0.6)
	if icon:
		icon.position = Vector2(28, head_h * 0.5 + 2)
		panel.add_child(icon)
	var hd := Label.new()
	hd.text = "%s      Lv.%d ▶ %d" % [nm, from_lv, to_lv]
	hd.add_theme_font_size_override("font_size", 19)
	hd.add_theme_color_override("font_color", Color(1, 0.92, 0.55))
	hd.add_theme_color_override("font_outline_color", Color(0.2, 0.12, 0, 0.9))
	hd.add_theme_constant_override("outline_size", 3)
	hd.position = Vector2(58, 5)
	panel.add_child(hd)
	# 스탯 3행
	var ry := head_h + 2.0
	for k in ["hp", "att", "def"]:
		var a: Dictionary = agg[k]
		var gain := int(a["gain"])
		var maxn := int(a["maxn"])
		var trans := bool(a["trans"])
		var lab := Label.new()
		lab.text = String(_STAT_KR[k])
		lab.add_theme_font_size_override("font_size", 16)
		lab.add_theme_color_override("font_color", Color(0.86, 0.6, 0.28))
		lab.position = Vector2(26, ry)
		panel.add_child(lab)
		var val := Label.new()
		# 1레벨 = "+상승/max"(분모 표기), 다레벨 = "+합계".
		if levels == 1 and max_stats.has(k):
			var denom := int(max_stats[k]) + (int({"hp": 4, "att": 1, "def": 1}[k]) if trans else 0)
			val.text = "+%d / %d" % [gain, denom]
		else:
			val.text = "+%d" % gain
		val.add_theme_font_size_override("font_size", 16)
		val.add_theme_color_override("font_color", accent if trans else Color(0.7, 1.0, 0.76))
		val.position = Vector2(150, ry)
		panel.add_child(val)
		# MAX 뱃지(맥스 발생 시). 초월=MAX+ 보라, 일반=MAX 금. 다레벨은 ×n.
		if maxn > 0:
			var badge := Label.new()
			var btxt := "MAX+" if trans else "MAX"
			if levels > 1:
				btxt += "×%d" % maxn
			badge.text = btxt
			badge.add_theme_font_size_override("font_size", 15)
			badge.add_theme_color_override("font_color", Color(0.85, 0.6, 1.0) if trans else Color(1.0, 0.85, 0.3))
			badge.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0, 0.9))
			badge.add_theme_constant_override("outline_size", 3)
			badge.position = Vector2(300, ry)
			panel.add_child(badge)
		ry += row_h
	# 자동 습득(위키: 레벨 10·25·45) — 배운 스킬 이름을 스탯 아래 한 줄로.
	if not learned.is_empty():
		var sl := Label.new()
		sl.text = "새 스킬  %s" % ", ".join(learned)
		sl.add_theme_font_size_override("font_size", 16)
		sl.add_theme_color_override("font_color", Color(0.72, 0.92, 1.0))
		sl.add_theme_color_override("font_outline_color", Color(0.1, 0.14, 0.25, 0.9))
		sl.add_theme_constant_override("outline_size", 3)
		sl.position = Vector2(26, ry)
		panel.add_child(sl)
	# 애니: 스케일 팝인 → 유지 → 상승 페이드아웃. 트리플맥스=전용 연출.
	var tw := root.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		if triples > 0:
			Bgm.sfx("effect_max_fun")
			_levelup_particle("pt_3max1", cx_w * 0.5, y + h * 0.5)
			_levelup_particle("pt_3max2", cx_w * 0.5, y + h * 0.5)
		else:
			Bgm.sfx("effect_level_updown" if _has_sfx("effect_level_updown") else "effect_coin")
			_levelup_particle("pt_levelup_light", cx_w * 0.5, y + h - 6.0))
	tw.tween_property(root, "modulate:a", 1.0, 0.22)
	tw.parallel().tween_property(root, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.7 if triples > 0 else 1.35)
	tw.tween_property(root, "position:y", y - 34.0, 0.45)
	tw.parallel().tween_property(root, "modulate:a", 0.0, 0.45)
	tw.tween_callback(root.queue_free)

func _has_sfx(name: String) -> bool:
	return ResourceLoader.exists("res://assets/music/%s.mp3" % name)

## 원작 Cocos 파티클 1회 발사 — 본체는 공용 헬퍼 CocosParticle(scripts/ui/cocos_particle.gd).
## (원래 여기 있었는데 레벨업 화면(cave.gd)과 공유하려고 뽑아냈다 — 중복 작성 금지.)
func _levelup_particle(name: String, x: float, y: float) -> void:
	CocosParticle.spawn(self, name, Vector2(x, y), 131,
		0.9 if name.begins_with("pt_3max") else 0.5)

## 전투 후 파티 잔여 HP(uid→hp) — 어드벤처 조우 간 이월용.
# ---------- 계속/그만 화면 회복 물약(레퍼런스 승리9/10 카드 위 버튼) ----------
## 원작 setRetryButton 화면에도 InterFace 의 물약 버튼이 남아 있다(승리9/10 캡처).
## 회복은 카드 HP(_views["A%d"].hp)에 얹혀 '계속하기'의 `_party_hp_state()` 로 이월된다.
## 물약 선택·회복량 규칙은 adventure.gd `_attach_cure_button`/`_use_heal_potion` 과 동일
## (`ItemEffect` logic 층 + `PartyCardView`(공유 렌더러)).
func _attach_retry_cure_buttons() -> void:
	for i in _party.size():
		var v: Dictionary = _views.get("A%d" % i, {})
		var card = v.get("node")
		if card == null or not is_instance_valid(card):
			continue
		for c in card.get_children():   # 갱신 호출 대비 — 기존 버튼 제거
			if c is Control and c.has_meta("cure_button"):
				c.queue_free()
		var lv := int(_party[i].get("level", 1))
		var key := ""
		for t in (Data.item_effects.get("heal_potion", {}).get("tiers", []) as Array):
			var k := String((t as Dictionary).get("key", ""))
			if ItemEffect.heal_usable(Data.item_effects, k, lv):
				key = k
				break
		if key == "" or UserDB.item_count(key) <= 0:
			continue
		var dead := int(v.get("hp", 1)) <= 0
		PartyCardView.build_cure_button(card, key, UserDB.item_count(key), dead, _pma,
			_retry_use_potion.bind(i, key))

## 물약 1개 소모 → 카드 HP 회복(원작 setRecoverItemHeal — skill_29 파티클 + 효과음).
## ⚫ 사망 개체의 다이아 부활 갈래는 §2-1 CUT — 산 드래곤만 회복한다.
func _retry_use_potion(idx: int, key: String) -> void:
	var v: Dictionary = _views.get("A%d" % idx, {})
	if v.is_empty() or int(v.get("hp", 0)) <= 0:
		return
	var hp := int(v.get("hp", 0))
	var hp_max := int(v.get("hp_max", 1))
	var healed := ItemEffect.heal_amount(Data.item_effects, hp, hp_max)
	if healed <= 0 or not UserDB.use_item(key, 1):
		return
	v["hp"] = clampi(hp + healed, 0, hp_max)
	_views["A%d" % idx] = v
	_refresh_bar(v)
	if v.has("center"):
		CocosParticle.spawn(self, "skill_29", v["center"], 132, 0.9)
	Bgm.sfx("effect_skill_29")            # 원작 music/effect_skill_29.mp3
	_attach_retry_cure_buttons()           # 수량/사망 표시 갱신

func _party_hp_state() -> Dictionary:
	var out := {}
	for i in _party.size():
		var v: Dictionary = _views.get("A%d" % i, {})
		var uid := int(_party[i]["uid"])
		out[str(uid)] = int(v.get("hp", _party[i].get("hp", 0)))
	return out

# ---------- 종료/결과 ----------
func _finish() -> void:
	_finished = true
	# 드링크 버프 턴 소모 — 이번 전투에서 진행된 라운드 수만큼 차감(0턴이면 소멸).
	# 위키 §2.3 "짧은 턴동안" + 사용자 확정 지속 10턴. 판정=ItemEffect(logic).
	for uid in _drink_users:
		var db: Dictionary = UserDB.get_dragon(int(uid)).get("drink_buffs", {})
		for _r in maxi(1, _cur_round):
			db = ItemEffect.tick(db)
		UserDB.set_dragon_field(int(uid), "drink_buffs", db)
	# 전투 참여 → 파티 **허기(FOOD) 소모**. 원작 후기판에는 피로도가 없고 허기만 있다(사용자 확정
	# 2026-07-30) → 회복은 동굴에서 **속성이 맞는 먹이**를 먹이는 것뿐이다(`cave.gd::_use_food`).
	# 0이 되면 탐험 입장이 막히고, 탐험 중이면 `adventure.gd` 가 즉시 종료한다.
	# # ASSUMPTION: 소모 속도는 서버 유실 → 전투 1회당 −15(튜닝 노브는 이 상수 하나).
	var fmax := ItemEffect.food_max(Data.item_effects)
	for pv in _party:
		var uid := int(pv["uid"])
		var fd := maxi(0, int(UserDB.get_dragon(uid).get("food", fmax)) - FOOD_PER_BATTLE)
		UserDB.set_dragon_field(uid, "food", fd)
	var vis := _vis()
	var win := _winner == "ally"
	# 🟦 스토리 전투는 **져야 하는 연출**이다(사용자 확정 2026-07-31) — 이벤트 26·27 은 원작
	#    스탯이 lv99 · hp/공/방 90000 이라 이길 수 없게 짜여 있다. 패배 페널티(행동불능)를
	#    걸면 연출 한 번에 출전 드래곤이 1시간 묶인다 ⇒ 스토리 전투에서는 적용하지 않는다.
	if not win and _winner == "enemy" and not _params.has("story_return"):
		_apply_defeat_incapacitation()
	if win: Bgm.sfx("bg_ad_win_short")   # 원작 승리 팡파레
	# 🟠 2026-08-01 걷어냄 — 승리 시의 "승리!" 배너 + 즉석 어둠막은 **자작**이었다.
	#   원작 승리 흐름(레퍼런스 승리2~10)에는 결과 배너가 없다: 몬스터가 도망친 뒤 곧장
	#   보상 페이즈(검은 막 FadeTo(0.5,200) + 워드아트)로 이어진다 → `_play_reward_phases`.
	#   패배 문구는 원작 문자열 <Dungeon_LastMent>를 하단 전투 텍스트박스에 표시한다.
	if not win:
		# 원작 stringsData_KR.xml <Dungeon_LastMent>. 중앙의 "패배...", "다시
		# 도전해보세요", 행동불능 안내는 원작 setRetryButtonDungeon 에 없는 자작 UI였고
		# 같은 세로 영역의 버튼과 겹쳤다. 그 함수는 투명 CCLayer만 추가하므로 자작 암막도
		# 제거하고, 패배 상태는 원작처럼 이 한 줄로만 알린다.
		_log("던전에서 패배하였습니다." if _winner == "enemy" else "무승부")
	# 어드벤처 다중 조우: 이긴 몹이 마지막(보스)이 아니면 탐험으로 복귀해 다음 조우.
	var st: Dictionary = _stage_rec()
	var total := int((st.get("enemies", []) as Array).size())
	var enc := int(_params.get("enc", 0))
	var region := String(_params.get("region", "yutakan"))
	# 랜덤 보스 스테이지는 단발 보스전(다중 조우 아님) → 항상 클리어(more=false).
	# 유타칸 **밤**은 조우 1회로 끝난다 — '계속하기'를 띄우지 않는다.
	# 원작 문구 그대로: `<NightTutorial_talk10>` "강력한 만큼 긴 전투 때문에 탐험은 단 한번!
	# 계속 이어갈 수가 없어." 코드도 같다 — `AdventureScene::checkAdventureNightEnd` 가
	# `m_nEventType = 0x1d`(Finish) 로 놓고 런을 끝낸다.
	var night_run := bool(_params.get("night", false))
	var more := win and total > 0 and enc + 1 < total \
		and not bool(st.get("random_boss", false)) and not night_run
	# ── 소환형 보스 처치 ────────────────────────────────────────────────────────────
	# 🔴 2026-07-31 정정 2회: "마무리 일격 버튼"(자작)도, "탐험을 두 번 하는 2연전"(원작
	#   `getDarknixFace` 1→2 + `WorldMapScene::onEnter` 자동 재진입을 그렇게 읽은 것)도
	#   **둘 다 틀렸다**(사용자 확인). 원작의 2페이즈는 **한 번의 전투 안에서** 보스 잔여
	#   체력이 임계 밑으로 떨어질 때 일어나는 분기다(중상/배리어 → 아군 회복 찬스 턴 →
	#   보스 피해 반감). 그 기믹은 서버 계산이라 수치가 유실됐다 — 미구현이고 확정 대기.
	#   상세 = docs/ref/porting/ChaosRiftDarknix.md §4-A.
	# ⇒ 지금은 **한 번의 전투에서 이기면 처치**다(페이즈 분기 없음).
	var dk_cfg: Dictionary = (st.get("summon", {}) as Dictionary) if Darknix.is_summon_stage(st) else {}
	var dk_live := not dk_cfg.is_empty() \
		and Darknix.is_active(UserDB.darknix(), int(Time.get_unix_time_from_system()))
	var dk_pending := false
	var dk_kill := win and dk_live
	# 보상: 스테이지 rewards가 유실(null)이라 처치 몹 레벨 기반 파생(ASSUMPTION). 보스=보너스.
	# 표시(연출)는 원작 `setEventReward` 이식인 `_play_reward_phases` 가 담당한다 —
	# 여기서는 지급하면서 페이즈 목록만 쌓는다(render 분리).
	var reward_txt := ""
	var phases: Array = []
	if win:
		UserDB.bump_quest("battles")   # 마을 퀘스트: 전투 승리 카운트
		var rlv := maxi(1, int(_enemy.get("level", 1)))
		var boss := (not more) and total > 0
		var exp_r := rlv * 8 + 20
		var gold_r := rlv * 12 + 30
		if boss: exp_r *= 3; gold_r *= 3
		if bool(_params.get("elite", false)): exp_r *= 2; gold_r *= 2   # 정예 몬스터 보상 2배
		# 원작 텍스트박스 `<AdventureResultGoldBonus>` "%d(+%d) 골드…" 의 괄호는
		# 실제 탐험 보너스(각성 등) 몫이다(레퍼런스 승리4 "163(+38)").
		var gold_base := gold_r
		# 각성 스킬 '부유한 기운'(42) — 탐험시 골드 획득량 50% 증가. 판정=AwakenSkill(logic).
		gold_r = int(round(float(gold_r) * AwakenSkill.mult_of(_awaken_explore(), "gold_pct")))
		# 탐험 보상 배수권(골드 2·4배) — 실시간 1시간 버프. 규칙 = 원작 설명문 + 위키 §9.6,
		# 판정 = ItemEffect(logic), 상태 = UserDB `reward_buff`(게임을 꺼도 시간이 흐른다).
		# 각성 보너스 **뒤에** 곱한다 → 괄호(+N)에 배수권 몫도 함께 실린다.
		var _now := int(Time.get_unix_time_from_system())
		var _rb: Dictionary = UserDB.reward_buff()
		var gold_mult := ItemEffect.reward_buff_mult(_rb, "gold", _now)
		if gold_mult > 1.0:
			gold_r = int(round(float(gold_r) * gold_mult))
		phases.append({"kind": "gold", "total": gold_r, "base": gold_base,
			"bonus": gold_r - gold_base})
		# 전투 미션 달성 EXP 보너스(원작 QuestAndBattleLabel "+40%/+20%"). 판정=BattleMission(logic).
		var names: Array = []
		for p in _party: names.append(String(p.get("name", "")))
		var mbonus := BattleMission.exp_bonus(BattleMission.evaluate(_missions, _events, names))
		if mbonus > 0.0:
			exp_r = int(exp_r * (1.0 + mbonus))
		# 탐험 보상 배수권(경험치 2·4배) — 미션 보너스까지 얹힌 최종 경험치에 곱한다.
		var exp_mult := ItemEffect.reward_buff_mult(_rb, "exp", _now)
		if exp_mult > 1.0:
			exp_r = int(round(float(exp_r) * exp_mult))
		_exp_gained += exp_r
		if is_instance_valid(_exp_label): _exp_label.text = str(_exp_gained)
		UserDB.add_currency("gold", gold_r)
		# 경험치 지급 → 레벨업 판정(logic=LevelSystem). 원작은 서버가 계산해 change1/2/3 JSON을 내려줬고
		# 클라 CheckLevelUp이 적용만 했다(reverse_engineering.md §Tier2) — 서버유실분을 LevelSystem이 대신 계산.
		var levelups: Array = []
		for pv in _party:
			# 원작 setDragonExpIncrease → setDragonExpLabel: 드래곤마다 SmallExpLayer 를 띄운다.
			_small_exp_layer(int(pv["uid"]), exp_r, int(_party.find(pv)))
			var lev := _grant_exp(int(pv["uid"]), exp_r)
			if int(lev.get("levels_gained", 0)) > 0:
				levelups.append({"name": String(pv["name"]), "ev": lev})
				# 레벨업 결과창(LevelUpResult)에 넘길 항목. 탐험이 이어지면 params로 이월한다.
				var lv_to := int(lev.get("level", 1))
				_levelup_queue.append({
					"uid": int(pv["uid"]), "name": String(pv["name"]),
					"from_lv": lv_to - int(lev.get("levels_gained", 1)), "to_lv": lv_to,
					"gains": lev.get("gains", []), "max_stats": lev.get("max_stats", {})})
				# 원작 동작 유지 — 하단 텍스트박스 한 줄(stringsData_KR `AdventureResultExpLevelup`).
				_log("%s이(가) 경험치를 %d 얻고 레벨업 했습니다." % [String(pv["name"]), exp_r])
			else:
				# 원작 `setEventExpText` — 레벨업이 없어도 드래곤마다 한 줄(`AdventureResultExp`).
				_log("%s이(가) 경험치를 %d 얻었습니다." % [String(pv["name"]), exp_r])
		_reward_fx(gold_r, exp_r)   # 코인 버스트 + EXP 아이콘(원작 CoinEffectLayer/ExpLayer)
		# ⚠️ 예전의 자동 소멸 배지(_levelup_fx)는 더 이상 부르지 않는다 — 같은 정보를
		#    `LevelUpResult` 모달이 담당하고(사용자 지시: 닫기 전까지 탐험 정지), 둘을 같이 띄우면 중복이다.
		#    배지 코드는 참고용으로 남겨 둔다(호출부 없음).
		reward_txt = "  +EXP %d / +골드 %d" % [exp_r, gold_r]
		# ── 아이템 드롭 — **화이트리스트**(사용자 확정 2026-07-31) ──────────────
		# 탐험에서 나오는 것은 일곱 가지뿐이다: 특수 드랍 / 먹이 / 속성 정기 /
		#   **희귀 속성(신성·혼돈·그림자)** / **드링크 1·2단계** / 드래곤 알 / 젬·장비.
		#   뒤의 둘은 🟦 사용자 확정 2026-08-04 로 추가됐다(수급처 전무 6+12종을 여는 경로).
		# 판정은 전부 `Drops`(logic), 표는 `data/drops.json` + `stages.json drops`.
		# 🟠 걷어낸 것: 드랍표가 없는 던전에서 `items_by("consumable")+("material")`(+한때 food)
		#   풀에서 **아무 아이템이나** 시드 추첨해 주던 폴백. 지역과 무관한 재료가 쏟아지고
		#   불 지역에서 물 드래곤 먹이가 나오던 원인이다.
		var fsrc := Drops.SOURCE_BOSS if boss else Drops.SOURCE_NORMAL
		var frng := RandomNumberGenerator.new(); frng.randomize()
		var hero_mode := bool(_params.get("hero", false))
		# 드랍 풀은 난이도마다 다르다 — 일반/영웅/밤(유타칸 +500)/카데스(+600).
		# 사용자 확정 2026-07-31. 표 = `stages.json drops` 의 난이도별 블록.
		var dmode := Drops.mode_of(hero_mode, bool(_params.get("night", false)), _is_kades())
		# 1) 특수 드랍 — 그 지역 전용 표(`stages.json drops`). 사용자가 CSV 로 채운다:
		#    docs/input/sheets/adventure_drop_pool.csv ↔ scripts/tools/build_adventure_drops.py
		#    🔴 2026-07-29: 이 표는 데이터에만 있고 **아무도 읽지 않고 있었다** — 우노의
		#    아니마·보네르가 인게임에서 나올 길이 없어 각성 자체가 도달 불가였다.
		#    영웅 난이도는 `hero_min/hero_max`(위키 item.pdf 각주 [40]: 일반 5~10 / 영웅 15~20).
		# `boss_only` 판정을 로직에 넘긴다 — 사용자 표의 "보스에서만 드랍".
		# 소환형 2연전의 **1차 승리에서는 건너뛴다** — 전리품은 2차 승리 뒤
		# (원작 state 10 `initEvent` case 10)에 `_darknix_kill()` 이 같은 판정으로 준다.
		for sd in (Drops.roll_special(st, frng, dmode, boss) if not dk_live else []):
			var skey := String((sd as Dictionary)["key"])
			var sqty := int((sd as Dictionary)["count"])
			UserDB.add_item(skey, sqty)
			reward_txt += " / %s x%d" % [_drop_display_name(skey), sqty]
			phases.append({"key": skey, "count": sqty})
		# 2) 먹이 — **그 지역 속성에 맞는 것만**(사용자 확정 2026-07-30).
		#    지역 속성이 비어 있으면(우노 24·25 = element null) 아무것도 안 나온다.
		if frng.randf() < float((Data.drops.get("food", {}).get("chance", {}) as Dictionary).get(fsrc, 0.0)):
			var fkey := Drops.roll_food(Data.items, st.get("element", ""), frng)
			if fkey != "":
				var fc: Dictionary = Data.drops.get("food", {}).get("count", {})
				var fqty := frng.randi_range(int(fc.get("min", 1)), maxi(int(fc.get("min", 1)), int(fc.get("max", 1))))
				UserDB.add_item(fkey, fqty)
				reward_txt += " / %s x%d" % [Data.item_name(fkey), fqty]
				phases.append({"key": fkey, "count": fqty})
		# 2b) **몬스터별 고유 드랍** — 장소가 아니라 그 몬스터에 붙는 것.
		#     밤 공용 조우 4종(#160 골드 임프·#161 실버 임프·#162 검은 로브의 사도·#175 블랙 윗치)과
		#     혼돈의 틈새 랜덤 보스 3종(#36·#138·#139). 원작 근거 = `<NightTutorial_talk11>`
		#     "보물들을 훔쳐간 골드임프, 실버임프를 만날 수 있어. 그 훔쳐간 보물들을 수집해서 오면".
		#     표 = data/monster_drops.json (사용자 CSV). **지역 표와 합산**된다.
		#     소환형 2연전 1차 승리에서는 건너뛴다(위 특수 드랍과 같은 이유) —
		#     혼돈의 틈새 보스가 주는 드래곤 알이 바로 이 표에 있다.
		for md in (Drops.roll_monster(Data.monster_drops, int(_enemy.get("id", 0)), frng) if not dk_live else []):
			var mrow: Dictionary = md
			var mqty := int(mrow["count"])
			if String(mrow.get("kind", "item")) == "currency":
				# 재화는 아이템이 아니다(블랙 윗치의 다이아).
				UserDB.add_currency(String(mrow["currency"]), mqty)
				reward_txt += " / 다이아 x%d" % mqty
				phases.append({"kind": "dia", "count": mqty})
				continue
			var mkey := String(mrow["key"])
			UserDB.add_item(mkey, mqty)
			reward_txt += " / %s x%d" % [_drop_display_name(mkey), mqty]
			phases.append({"key": mkey, "count": mqty})
		# 소환형 보스 처치 확정 — 원작은 1·2차 어느 쪽도 전리품을 안 주다가 **2차 승리**
		# (state 10)에서만 준다. 위 두 표를 여기서 한 번에 굴리고 월드맵에서 보스를 지운다.
		if dk_kill:
			reward_txt += _darknix_kill(st, phases)
		# 3) 속성 정기 — 그 지역 속성의 `ele_*`(items.json currency/essence 9종).
		var ess := Drops.roll_essence(Data.drops, Data.items, st.get("element", ""), fsrc, frng)
		if not ess.is_empty():
			UserDB.add_item(String(ess["key"]), int(ess["count"]))
			reward_txt += " / %s x%d" % [Data.item_name(String(ess["key"])), int(ess["count"])]
			phases.append({"key": String(ess["key"]), "count": int(ess["count"])})
		# 3b) 희귀 속성 드랍(신성·혼돈·그림자) — 🟦 사용자 확정 2026-08-04.
		#     지역 속성은 6종뿐이라 이 3속성의 정기·큰 먹이는 위 3)·2) 로는 영영 안 나온다
		#     (수급처 전수 대조 2026-08-04). 지역이 아니라 **난이도**에 붙는다:
		#     일반(·밤)=보스 처치 / 영웅=전투 승리 / 카데스=전투 승리 → 25%.
		var rare := Drops.roll_rare_element(Data.drops, dmode, boss, frng)
		if not rare.is_empty():
			UserDB.add_item(String(rare["key"]), int(rare["count"]))
			reward_txt += " / %s x%d" % [Data.item_name(String(rare["key"])), int(rare["count"])]
			phases.append({"key": String(rare["key"]), "count": int(rare["count"])})
		# 3c) 드링크(버프 물약 1·2단계) — 🟦 사용자 확정 2026-08-04.
		#     상점은 3단계만 판다 → **모든 전투 승리**에서 10% 로 1·2단계 중 한 종.
		var drk := Drops.roll_drink(Data.drops, Data.items, frng)
		if not drk.is_empty():
			UserDB.add_item(String(drk["key"]), int(drk["count"]))
			reward_txt += " / %s x%d" % [Data.item_name(String(drk["key"])), int(drk["count"])]
			phases.append({"key": String(drk["key"]), "count": int(drk["count"])})
		# 4) 드래곤 알 — **그 탐험지 팝업에 등재된 드래곤만**, H 는 영웅 난이도 희귀 드롭
		#    (사용자 확정 2026-07-30). 원작 근거 = <AdventureResultEgg> "%1$s의 알" +
		#    AdventureRewardLayer 의 EGG 셀(포팅 카드 AdventureEventFlow.md §5).
		#    가상 인벤 키 `egg:<드래곤id>` 라 items.json 이 아니라 EggGacha 가 이름을 만든다.
		var ekey := Drops.roll_egg(Data.drops, st, fsrc, frng, bool(_params.get("hero", false)))
		if ekey != "":
			UserDB.add_item(ekey, 1)
			reward_txt += " / %s x1" % String(EggGacha.item_def(ekey, Data.dragons).get("name", "알"))
			phases.append({"key": ekey, "count": 1})
		# 젬·장비 드롭(사용자 확정 2026-07-27): **탐험이 기본 획득처**다. 고레벨 지역일수록,
		# 일반몹 < 보스 일수록 더 좋은 것이 나온다(보물상자는 adventure.gd 담당).
		# 판정=Drops(logic) · 표=data/drops.json.
		# 카데스의 공간(유타칸 전설 모드)이면 아티팩트도 나온다. 종류는 던전마다 다르다
		# (위키 dungeon_1.pdf §2 — 배정표는 자작, data/drops.json kades.artifact_by_dungeon).
		var grng := RandomNumberGenerator.new(); grng.randomize()
		var gkey := Drops.roll_exploration(Data.drops, rlv,
			Drops.SOURCE_BOSS if boss else Drops.SOURCE_NORMAL, Data.equipment, grng,
			_is_kades(), _base_field(),
			# 각성 스킬 '구드라의 가호'(17) — 전설 난이도 지역 아티팩트 확률 50% 증가.
			AwakenSkill.mult_of(_awaken_explore(), "artifact_chance_pct"))
		if gkey != "":
			UserDB.add_item(gkey, 1)
			reward_txt += " / %s x1" % Drops.display_name(gkey, Data.gems, Data.equipment)
			phases.append({"key": gkey, "count": 1})
	# 🟠 2026-08-01: 종전의 흰 자막(`sub` — "클리어!" / 전리품 로그 한 줄)은 걷어냈다.
	#   원작은 클리어 자막 없이 결산 팝업(AdventureRewardLayer)으로, 전리품은 페이즈별
	#   텍스트박스 줄(`AdventureItemName`)로 알린다 — `_play_reward_phases` 가 담당.
	if win and not more:
		var sid := str(_params.get("stage", ""))
		if sid != "":
			UserDB.set_progress("cleared_" + sid, true)   # 원작 setScenarioMark용 진행도 기록(던전 클리어)
		_note_story_quest(st)
	# 보상 페이즈 **뒤에** 이어질 것들(계속/그만 버튼·탐험 종료 대사) — 원작도
	# setEventReward 슬롯을 전부 소진한 다음에야 setRetryButton 으로 넘어간다.
	var after_rewards := func() -> void:
		# 원작 계속/중단 선택 = `AdventureScene::setRetryButton`(포팅 카드 AdventureEventFlow.md §3).
		#   좌 = `btn1.png`(붉은) + `choice_stop_KR`   tag 0xbbc → onClickStop
		#   우 = `btn2.png`(초록) + `choice_continue_KR` tag 0xbbb → onClickRetry
		#   레퍼런스 승리9/10 과 일치(붉은 그만하기 좌 · 초록 계속하기 우).
		if more:
			_log("탐험을 계속 이어가시겠습니까?")   # 원작 <AdventureBattleRetry>
			# 레벨업 결과창은 **다음 탐험 구간으로 이월**한다 — 탐험이 이어지는 동안 창이 뜨고,
			# 닫기 전까지 배회가 멈춘다(adventure.gd `_open_levelup_result`). 사용자 지시 2026-07-27.
			var lvq := _levelup_queue.duplicate()
			_levelup_queue.clear()
			# 회복 물약 버튼(레퍼런스 승리9/10 — 카드 위 십자+물약+x수량). 2026-08-01 배선.
			_attach_retry_cure_buttons()
			_retry_buttons(
				func(): Scenes.goto("worldmap", {"region": region}),
				func(): Scenes.goto("adventure",
					# ⚠️ hp_state 는 **클릭 시점**에 계산한다 — 이 화면에서 물약을 쓰면 카드 HP
					#   (_views)가 회복되고, 그 값이 다음 조우로 이월돼야 한다.
					{"stage": _params.get("stage", ""), "region": region, "enc": enc + 1,
					"hp_state": _party_hp_state(),
					# 🔴 난이도 플래그를 이월하지 않으면 '계속하기' 이후 조우가 **일반 난이도로 되돌아간다**
					#   (영웅 스탯 배율도, 영웅/밤 드랍 풀도 사라진다). 2026-07-31 발견.
					"hero": bool(_params.get("hero", false)), "night": bool(_params.get("night", false)),
					"run_seed": int(_params.get("run_seed", 0)),
					"party_uids": _params.get("party_uids", []).duplicate(), "party_ready": true,
					"levelups": lvq}))
		else:
			# 던전이 끝나 이어질 탐험이 없다 → 결과 화면에서 바로 띄운다(이월할 곳이 없으므로).
			if win:
				_log("더 이상 탐험할 곳이 없어 이 지역을 벗어납니다.")   # 원작 <AdventureEventEnd>(탐험끝.png)
			if not _levelup_queue.is_empty():
				var q := _levelup_queue.duplicate()
				_levelup_queue.clear()
				# 🔀 2026-07-31: 동굴 축복 아이템과 **같은 화면**을 공유한다(LevelUpScreen).
				LevelUpScreen.open_queue(self, q)
			if win:
				_show_finish_arrow(region)
			else:
				_big_button("월드맵으로", "9patch_btn2", Vector2(vis.x * 0.5 + 20.0, vis.y * 0.38),
					func(): Scenes.goto("worldmap", {"region": region}))
	# ── 스토리 전투 복귀 ────────────────────────────────────────────────────
	# 원작은 `AdventureScene` 을 **push** 해서 끝나면 시나리오로 pop 한다
	# (`ScenarioSupport::scenarioBattle` → `CCDirector::pushScene`). 우리는 씬 스택이 없어
	# story.gd 가 복귀 지점을 들려 보내고 여기서 그대로 되돌린다.
	if _params.has("story_return"):
		# 🟦 사용자 확정 2026-07-31: 스토리 전투는 **승패와 무관하게** 전투가 끝나면 이야기가
		#    이어진다(이벤트 26·27 은 애초에 이길 수 없는 연출 전투다).
		#    ⇒ 재도전·월드맵 같은 갈림길을 두지 않는다. 버튼 하나로만 나간다.
		var sr: Dictionary = _params["story_return"]
		# 🔴 2026-08-04 (사용자 신고 "전투 승리 후 진행이 안 된다 / 전투가 안 끝나는 것 같다"):
		#    종전 위치 `y*0.5 + 120`(=466) 은 **파티 카드 띠 한가운데**였다 —
		#    카드는 `cardY = vis.y - 128 - ch` = 459 부터 시작하고 `z_index = 400`,
		#    `_big_button` 은 124 라 버튼이 카드 **뒤로** 깔린다. 그리면서 클릭 영역까지
		#    가려져 이야기로 돌아갈 방법이 없었다(전투가 안 끝난 것처럼 보인다).
		#    ⇒ 다른 결과 버튼과 같은 띠(`y*0.38`)로 올린다 — 거기는 카드 위쪽 빈 배경이다.
		_big_button("이야기 계속", "9patch_btn2", Vector2(vis.x * 0.5 - 140.0, vis.y * 0.38),
			func() -> void:
				Scenes.goto("story", {"no": int(sr.get("no", 1)), "part": int(sr.get("part", 0)),
					"resume_flow": int(sr.get("resume_flow", 0)),
					"back": sr.get("back", "worldmap"),
					"back_params": sr.get("back_params", {})}))
		return
	# 승리면 보상 페이즈(원작 setEventReward 연쇄)를 먼저 돌리고, 끝난 뒤 버튼을 낸다.
	if win and not phases.is_empty():
		_play_reward_phases(phases, after_rewards)
	else:
		after_rewards.call()
	# 원작 onClickRetry/setRetryButton: 패배 시 재도전(부활+현 조우 재시작, 골드 비용).
	var btn_y := vis.y * 0.38
	if not win and _winner == "enemy":
		const RETRY_COST := 100
		_big_button("재도전 (%dG)" % RETRY_COST, "9patch_btn3",
			Vector2(vis.x * 0.5 - 300.0, btn_y), func():
				if not UserDB.spend("gold", RETRY_COST): return
				# 던전을 나가지 않았으므로 방금 건 행동불능을 되돌린다(원작 setCureTime(0)).
				_undo_defeat_incapacitation()
				# 현 조우를 처음부터(파티 풀피=hp_state 없이) 재시작.
				Scenes.goto("adventure", {"stage": _params.get("stage", ""), "region": region, "enc": enc,
					"hero": bool(_params.get("hero", false)),
					"night": bool(_params.get("night", false)),
					"run_seed": int(_params.get("run_seed", 0)),
					"party_uids": _params.get("party_uids", []).duplicate(), "party_ready": true}))

## 던전 패배 → 출전 드래곤 **행동불능**(원작 `Dragon::setCureTime`). 사용자 확정 2026-07-29:
##   "패배 후 던전 나가면 해당 던전에 들어갔던 드래곤이 행동불능 상태가 되어 치료제를 쓰거나
##    회복시간 1시간을 채우기 전까지 전투 참여가 불가능했음."
## 부적(장비 `cure` %)은 **여기에 걸리지 않을 확률**이다(같은 줄에서 확정).
## 재도전(골드)을 누르면 그 자리에서 해제한다 — "던전을 나가지 않았으므로".
func _apply_defeat_incapacitation() -> void:
	var cfg: Dictionary = Data.incapacitation
	if cfg.is_empty():
		return
	var now := int(Time.get_unix_time_from_system())
	var until := Incapacitation.down_until(cfg, now)
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var avoid_stat := String(cfg.get("avoid_stat", "cure"))
	_downed_uids.clear()
	for pv in _party:
		var uid := int(pv["uid"])
		var cure := int((pv.get("stats", {}) as Dictionary).get(avoid_stat, 0))
		if Incapacitation.avoids(cure, rng):
			continue                      # 부적이 막았다
		UserDB.set_cure_time(uid, until)
		_downed_uids.append(uid)

var _downed_uids: Array = []    # 이번 패배로 행동불능이 된 uid (재도전 시 되돌린다)

## 재도전 = 던전을 나가지 않은 것 → 방금 건 행동불능을 취소한다(원작 setCureTime(0)).
func _undo_defeat_incapacitation() -> void:
	for uid in _downed_uids:
		UserDB.set_cure_time(int(uid), 0)
	_downed_uids.clear()

## 원작 `setRetryButton` — 그만하기(좌·붉은) / 계속하기(우·초록).
##
## 원작 리터럴 그대로:
##   · 배경 `scene/adventure/btn1.png`(붉은) · `btn2.png`(초록) — 262×94
##   · 라벨 `scene/adventure/choice_stop_%s.png` · `choice_continue_%s.png`
##   · 배치 y = 버튼높이*0.5 + 20(하단 기준) · x = 중앙 ∓ (버튼폭*0.5 + 50)
##   · 등장 `CCMoveTo(0.5)` + `CCEaseExponentialInOut` — **그만하기는 화면 왼쪽 밖**(x = -50-w),
##     계속하기는 오른쪽 밖에서 밀려 들어온다.
##
## ⚫ 자동반복(`getIsAutoRetry` → `CounterButton::create(..., onClickRetry, ...)` 카운트다운)은
##   미구현이다. 프레임 `scene/adventure/btn3|btn4`(CounterButton)는 보유하고 있으므로
##   되살릴 때 여기만 손대면 된다.
const _RETRY_BTN := Vector2(262.0, 94.0)      # scene/adventure/btn1|btn2 실측

func _retry_buttons(on_stop: Callable, on_continue: Callable) -> void:
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var w := _RETRY_BTN.x * S
	# Cocos 좌표 y = 화면높이*0.5 + 20 (원점 좌하단) → godot_y = visH*0.5 - 20 ≈ 화면 47%.
	# 레퍼런스 docs/ref/orig_image/battle/전리품드랍후.png 의 버튼 높이와 일치한다.
	var y := vis.y * 0.5 - 20.0
	var man := _man("adventure_ui")
	_retry_button("scene_adventure_btn1", "scene_adventure_choice_stop_KR", man,
		Vector2(vis.x * 0.5 - (w * 0.5 + 50.0), y), Vector2(-50.0 - w, y), on_stop)
	_retry_button("scene_adventure_btn2", "scene_adventure_choice_continue_KR", man,
		Vector2(vis.x * 0.5 + (w * 0.5 + 50.0), y), Vector2(vis.x + 50.0 + w, y), on_continue)

func _retry_button(bg_key: String, label_key: String, man: Dictionary,
		to: Vector2, from: Vector2, cb: Callable) -> void:
	var S := Design.ASSET_SCALE
	var holder := Node2D.new()
	holder.position = from
	# 🔴 결과 화면의 몬스터 스파인(holder z_index 8~100)보다 항상 위 — 2026-07-27 실제 버그.
	holder.z_index = 124
	add_child(holder)
	var bg := _spr("adventure_ui", bg_key, man, S)
	if bg:
		holder.add_child(bg)
	var lb := _spr("adventure_ui", label_key, man, S)
	if lb:
		holder.add_child(lb)
	var hit := Button.new()
	hit.flat = true
	hit.size = _RETRY_BTN * S
	hit.position = -_RETRY_BTN * S * 0.5
	hit.pressed.connect(cb)
	holder.add_child(hit)
	var tw := holder.create_tween()
	tw.tween_property(holder, "position", to, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)

# ---------- 승리 보상 페이즈(원작 AdventureScene::setEventReward @00c7f11c 이식) ----------
## 원작은 보상 슬롯(골드→아이템→…)마다 setEventReward 를 재진입하며 한 페이즈씩 낸다.
## 페이즈 공통(디컴프 리터럴):
##   · 검은 막 CCLayerColor {0,0,0} FadeTo(0.5, 200) — tag 0x75, 페이즈 연쇄 동안 유지
##   · 워드아트 = `WordArt.burst`(font_title, 제목은 stringsData 키 `AdventureReward*`)
##   · 효과음 `music/effect_holy_wing.mp3` · 파티클 `pt_monster_income_1`(top, scale 1.4)
## 골드 페이즈(:65642-65691): `common/coin_big`(scale 1.5) @ (cx−110, cy) +
##   NumberingLabel "x%d"(scale 1.2) @ (cx+100, cy), 슬라이드 인 0.5s EaseBackInOut,
##   텍스트박스 `<AdventureResultGold(Bonus)>` "%d(+%d) 골드를 얻었습니다."(승리4/5).
## 아이템 페이즈(:64650-64990 + setRewardItemDesc/`setRewardBackLight`):
##   · 아이콘 팝인 Delay(0.8) → FadeTo∥ScaleTo(1.6)∥RotateTo(720°) 0.2s → ScaleTo(1.4)
##     → 왼쪽으로 이동(레퍼런스 승리7/8: 최종 x≈38%) → 우측에 상세 블록
##   · 백라이트 = `common/backlight3` RotateBy(3s, 20°) 반복 + 페이드 인(setRewardBackLight)
##   · 상세 = font_common: 이름 `<AdventureItemCount>` "%s  -  {#4374D9:%d개}" /
##     설명(items.json desc — 없으면 생략, 문장 생성 금지) /
##     `<AdventureItemTotalCount>` "{#BDBDBD:(보유 수량 : %d개)}"
##   · 텍스트박스 `<AdventureItemName>` "%s을(를) 획득하였습니다."
## 진행: 원작 NumberingLabel confirm/터치 = 우리 전면 탭 버튼(즉시 다음), 자동 진행 3.4s.
var _phase_dim: ColorRect
var _phase_box: Node2D          # 현재 페이즈의 연출 묶음(중복 실행 시 정리용)
var _phase_run := 0             # 실행 세대 — 새 실행이 시작되면 이전 연쇄는 스스로 멈춘다
func _play_reward_phases(phases: Array, done: Callable) -> void:
	# 이중 실행 가드 — 이전 연쇄의 막·박스를 걷고 세대를 올린다(테스트 주입 + 실제 승리가
	# 겹쳐도 마지막 호출만 살아남는다).
	_phase_run += 1
	if is_instance_valid(_phase_dim):
		_phase_dim.queue_free()
	if is_instance_valid(_phase_box):
		_phase_box.queue_free()
	var vis := _vis()
	_phase_dim = ColorRect.new()
	_phase_dim.color = Color(0, 0, 0, 0)
	_phase_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_phase_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_phase_dim.z_index = 120
	add_child(_phase_dim)
	_phase_dim.create_tween().tween_property(_phase_dim, "color:a", 200.0 / 255.0, 0.5)
	Bgm.sfx("effect_holy_wing")
	_run_reward_phase(phases, 0, done, _phase_run)

func _run_reward_phase(phases: Array, i: int, done: Callable, run_id: int) -> void:
	if run_id != _phase_run:
		return   # 더 새로운 실행이 시작됐다 — 이 연쇄는 여기서 끝
	if i >= phases.size():
		# 페이즈 소진 → 막을 걷고 다음(계속/그만 버튼 등)으로. 레퍼런스 승리9: 버튼 화면은 밝다.
		if is_instance_valid(_phase_dim):
			var d := _phase_dim
			_phase_dim = null
			var t := d.create_tween()
			t.tween_property(d, "color:a", 0.0, 0.3)
			t.tween_callback(d.queue_free)
		done.call()
		return
	var ph: Dictionary = phases[i]
	var vis := _vis()
	var S := Design.ASSET_SCALE
	var box := Node2D.new()
	box.z_index = 122
	add_child(box)
	_phase_box = box
	CocosParticle.spawn(box, "pt_monster_income_1", Vector2(vis.x * 0.5, 40.0), 123, 1.4)
	var kind := String(ph.get("kind", "item"))
	match kind:
		"gold":
			WordArt.burst(box, "골드 획득!", vis, 125, 60.0)   # <AdventureRewardGold>, 골드는 +60
			var man := _man("common_ui")
			var coin := _spr("common_ui", "common_coin_big", man, 1.5 * S)
			if coin:
				coin.position = Vector2(vis.x * 0.5 - 110.0 + 80.0, vis.y * 0.5)
				coin.modulate.a = 0.0
				box.add_child(coin)
				var ct := coin.create_tween()
				ct.tween_interval(0.5)
				ct.tween_property(coin, "modulate:a", 1.0, 0.15)
				ct.parallel().tween_property(coin, "position:x", vis.x * 0.5 - 110.0, 0.5) \
					.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
			var cnt := _bmfont_label("", "font_common", 30)
			cnt.position = Vector2(vis.x * 0.5 + 20.0, vis.y * 0.5 - 20.0)
			cnt.size = Vector2(260, 40)
			cnt.scale = Vector2(1.2, 1.2)
			cnt.modulate.a = 0.0
			box.add_child(cnt)
			# 원작 NumberingLabel — 수치가 0→N 으로 구른다.
			var total := int(ph.get("total", 0))
			var nt := cnt.create_tween()
			nt.tween_interval(0.5)
			nt.tween_property(cnt, "modulate:a", 1.0, 0.15)
			nt.tween_method(func(v: float): cnt.text = "X %d" % int(round(v)),
				0.0, float(total), 0.8)
			var bonus := int(ph.get("bonus", 0))
			_log(("%d(+%d) 골드를 얻었습니다." % [int(ph.get("base", total)), bonus]) if bonus > 0
				else "%d 골드를 얻었습니다." % total)
		"dia":
			WordArt.burst(box, "다이아 획득!", vis, 125, 60.0)   # <AdventureRewardDia>
			var man := _man("common_ui")
			var dia := _spr("common_ui", "common_diamond_small1", man, 1.5 * S)
			if dia:
				dia.position = Vector2(vis.x * 0.5 - 110.0, vis.y * 0.5)
				box.add_child(dia)
			var cnt := _bmfont_label("X %d" % int(ph.get("count", 0)), "font_common", 30)
			cnt.position = Vector2(vis.x * 0.5 + 20.0, vis.y * 0.5 - 20.0)
			cnt.size = Vector2(260, 40)
			cnt.scale = Vector2(1.2, 1.2)
			box.add_child(cnt)
			_log("다이아를 %d개 얻었습니다." % int(ph.get("count", 0)))   # <AdventureResultDia>
		_:
			var key := String(ph.get("key", ""))
			var count := int(ph.get("count", 1))
			WordArt.burst(box, _reward_title_for(key), vis, 125, 100.0)
			var icon_end := Vector2(vis.x * 0.38, vis.y * 0.47)
			# 백라이트(setRewardBackLight): 아이콘과 함께 페이드 인, RotateBy(3.0, 20°) 반복.
			var bl := _spr("common_ui", "common_backlight3", _man("common_ui"), 1.3 * S)
			if bl:
				bl.position = icon_end
				bl.modulate = Color(1, 0.95, 0.65, 0.0)
				box.add_child(bl)
				var brot := bl.create_tween().set_loops()
				brot.tween_property(bl, "rotation_degrees", 360.0, 54.0).from(0.0)   # 20°/3s
				var bt := bl.create_tween()
				bt.tween_interval(0.8)
				bt.tween_property(bl, "modulate:a", 0.9, 0.2)
				bt.parallel().tween_property(bl, "scale", Vector2(1.1 * S, 1.1 * S), 0.2) \
					.from(Vector2(1.3 * S, 1.3 * S))
			var tex := _reward_icon_texture(key)
			if tex:
				var icon := Sprite2D.new()
				icon.texture = tex
				icon.material = _pma
				icon.position = Vector2(vis.x * 0.5, vis.y * 0.47)
				icon.modulate.a = 0.0
				icon.scale = Vector2.ZERO
				box.add_child(icon)
				var it := icon.create_tween()
				it.tween_interval(0.8)
				it.tween_property(icon, "modulate:a", 1.0, 0.2)
				it.parallel().tween_property(icon, "scale", Vector2(1.6 * S, 1.6 * S), 0.2)
				it.parallel().tween_property(icon, "rotation_degrees", 720.0, 0.2).from(0.0)
				it.tween_property(icon, "scale", Vector2(1.4 * S, 1.4 * S), 0.2)
				it.tween_property(icon, "position", icon_end, 0.2) \
					.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN_OUT)
			var nm := _drop_display_name(key)
			# 우측 상세 블록(setRewardItemDesc, font_common) — 아이콘이 자리 잡은 뒤 페이드 인.
			var blk := Control.new()
			blk.position = Vector2(vis.x * 0.55, vis.y * 0.3)
			blk.modulate.a = 0.0
			box.add_child(blk)
			var name_l := _bmfont_rich("%s  -  [color=#4374d9]%d개[/color]" % [nm, count], 24)
			name_l.position = Vector2(0, 0); name_l.size = Vector2(vis.x * 0.42, 36)
			blk.add_child(name_l)
			var desc := String(Data.get_item(key).get("desc", ""))
			var dy := 48.0
			if desc != "":
				var desc_l := _bmfont_rich(desc, 20)
				desc_l.position = Vector2(0, dy); desc_l.size = Vector2(vis.x * 0.36, 130)
				blk.add_child(desc_l)
				dy += minf(130.0, 30.0 * ceilf(desc.length() / 18.0)) + 12.0
			# 보유 수량 — 방금 지급분이 이미 들어간 값(원작도 지급 후 조회).
			var owned := UserDB.item_count(key)
			if owned > 0:
				var own_l := _bmfont_rich("[color=#bdbdbd](보유 수량 : %d개)[/color]" % owned, 18)
				own_l.position = Vector2(0, dy); own_l.size = Vector2(vis.x * 0.36, 30)
				blk.add_child(own_l)
			var kt := blk.create_tween()
			kt.tween_interval(1.2)
			kt.tween_property(blk, "modulate:a", 1.0, 0.25)
			_log("%s%s 획득하였습니다." % [nm, "을" if _has_batchim(nm) else "를"])
	# 진행 — 탭 즉시 / 자동 3.4s(전투 배속 반영).
	var adv_done := [false]
	var advance := func() -> void:
		if adv_done[0] or not is_instance_valid(box):
			return
		adv_done[0] = true
		var ft := box.create_tween()
		ft.tween_property(box, "modulate:a", 0.0, 0.15)
		ft.tween_callback(box.queue_free)
		ft.tween_callback(func(): _run_reward_phase(phases, i + 1, done, run_id))
	var tap := Button.new()
	tap.flat = true
	tap.position = Vector2.ZERO
	tap.size = vis
	tap.pressed.connect(advance)
	box.add_child(tap)
	get_tree().create_timer(3.4 / maxf(_speed, 1.0)).timeout.connect(advance)

## 워드아트 제목 — stringsData_KR `AdventureReward*` 키(원작 setEventReward 가 슬롯별로 고른다).
func _reward_title_for(key: String) -> String:
	if Gem.parse_item_key(key).size() > 0 or Equipment.parse_item_key(key) != "":
		return "장착 아이템 획득!"                       # <AdventureRewardEquip>
	if key.begins_with(EggGacha.KEY_PREFIX):
		return "드래곤 알 획득!"                         # <AdventureRewardEgg>
	if not Loadout.parse_item_key(key).is_empty():
		return "스킬 스크롤 획득!"                       # <AdventureRewardSkill>
	return "아이템 획득!"                                # <AdventureRewardItem>

## 보상 아이콘 — 가상 인벤 키(gem:/equip:/egg:)는 Icons(카탈로그 계층), 그 외 items.json icon.
func _reward_icon_texture(key: String) -> Texture2D:
	var g := Gem.parse_item_key(key)
	if not g.is_empty():
		return Icons.gem_texture(
			String(Gem.gem_def(String(g["name"]), Data.gems).get("code", "")), int(g["tier"]))
	var ck := Equipment.parse_item_key(key)
	if ck != "":
		return Icons.equip_texture(Equipment.catalog(Data.equipment).get(ck, {}))
	if key.begins_with(EggGacha.KEY_PREFIX):
		var did := int(key.get_slice(":", 1))
		return Icons.dragon_egg_texture(did)
	var path := String(Data.item_icon_path(key))
	if path != "" and ResourceLoader.exists(path):
		return load(path)
	return null

## font_common BMFont 라벨(수량/카운트용). 비트맵이라 fixed_size_scale_mode 필요(§10 표).
func _bmfont_label(text: String, fnt_name: String, size: int) -> Label:
	var lb := Label.new()
	lb.text = text
	var fp := "res://assets/converted/font_ui/%s.fnt" % fnt_name
	if ResourceLoader.exists(fp):
		lb.add_theme_font_override("font", load(fp))
	lb.add_theme_font_size_override("font_size", size)
	return lb

## font_common RichTextLabel — `<AdventureItemCount>` 의 {#4374D9:…} 색 마크업을 BBCode 로 낸다.
func _bmfont_rich(bb: String, size: int) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.text = bb
	rt.fit_content = true
	rt.scroll_active = false
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fp := "res://assets/converted/font_ui/font_common.fnt"
	if ResourceLoader.exists(fp):
		rt.add_theme_font_override("normal_font", load(fp))
		rt.add_theme_font_size_override("normal_font_size", size)
	else:
		rt.add_theme_font_size_override("normal_font_size", size)
	return rt

## 받침 유무(을/를) — 원작 문자열 키는 "%s을(를)" 이지만 실화면(승리8)은 조사가 정리돼 있다.
func _has_batchim(word: String) -> bool:
	if word.is_empty(): return false
	var c := word.unicode_at(word.length() - 1)
	if c < 0xAC00 or c > 0xD7A3: return false
	return ((c - 0xAC00) % 28) != 0

## 원작 대형 버튼 — `9patch/btn*` 프레임 위에 라벨. 레퍼런스의 그만하기/계속하기 크기(약 280×86)를 따른다.
## (계속/그만은 위 `_retry_buttons` 가 원작 프레임으로 그린다 — 여기 남은 호출처는
##  '월드맵으로'·'재도전' 처럼 원작에 대응 프레임이 없는 버튼뿐이다.)
## 🔴 2026-07-31 제거: 2페이즈 **진입 연출**(붉은 플래시 + "중상을 입고 몸을 웅크렸다" 배너
##   + effect_chaos_explosion + 전투 로그)은 전부 자작이었다. 근거:
##   · 문자열 테이블에 `중상` **0건**
##   · 디컴프 397클래스에 phase/2페이즈 개념 **0건** — 원작 보스는 단일 페이즈다
##   피해 감면 **기전**(아래 `_apply_boss_phase`)은 사용자가 만든 데이터(`stages.json summon.phase2`)라
##   남긴다. 다만 **화면에는 아무것도 알리지 않는다** — 원작에 그 알림이 없다.

## 보스 2페이즈 배선 — 데이터(`stages.json` `summon.phase2`)를 전투원에 실어 준다.
## logic(`Battle._apply_dmg`)은 스테이지를 모르고 전투원의 필드만 본다(§8.2 단방향 의존).
func _apply_boss_phase(eb: Dictionary) -> void:
	var st := _stage_rec()
	if not Darknix.is_summon_stage(st):
		return
	var p: Dictionary = (st["summon"] as Dictionary).get("phase2", {})
	if p.is_empty():
		return
	eb["phase"] = 1
	eb["phase2_at"] = float(p.get("hp_threshold", 0.0))
	eb["phase2_taken_mult"] = float(p.get("damage_taken_mult", 1.0))

## ── 혼돈의 틈새 2차전 처치 (원작 face==2 승리) ──────────────────────────────
## 원작 `AdventureScene::setEventFightEnd` face==2 승리 가지(:61050~61058):
##   `setWinSound` + 승리 대사 + state 10(보상) + **`setLimitTime_darknix(0)`**
##   = 월드맵에서 보스 소멸. 전리품은 `initEvent` case 10(:22194)이 준다 —
##   원작은 인벤 여유와 무관하게 우편함이었으나 오프라인엔 우편함이 없어(§2-1) 인벤 직행.
func _darknix_kill(st: Dictionary, phases: Array) -> String:
	var frng := RandomNumberGenerator.new(); frng.randomize()
	var dmode := Drops.mode_of(bool(_params.get("hero", false)),
		bool(_params.get("night", false)), _is_kades())
	var txt := ""
	for sd in Drops.roll_special(st, frng, dmode, true):
		var skey := String((sd as Dictionary)["key"])
		var sqty := int((sd as Dictionary)["count"])
		UserDB.add_item(skey, sqty)
		txt += " / %s x%d" % [_drop_display_name(skey), sqty]
		phases.append({"key": skey, "count": sqty})
	for md in Drops.roll_monster(Data.monster_drops, int(_enemy.get("id", 0)), frng):
		var mrow: Dictionary = md
		var mqty := int(mrow["count"])
		if String(mrow.get("kind", "item")) == "currency":
			UserDB.add_currency(String(mrow["currency"]), mqty)
			txt += " / 다이아 x%d" % mqty
			phases.append({"kind": "dia", "count": mqty})
			continue
		var mkey := String(mrow["key"])
		UserDB.add_item(mkey, mqty)
		txt += " / %s x%d" % [_drop_display_name(mkey), mqty]
		phases.append({"key": mkey, "count": mqty})
	UserDB.darknix_clear()   # 원작 setLimitTime_darknix(0) — 월드맵에서 사라진다
	return txt

func _big_button(text: String, frame: String, pos: Vector2, cb: Callable) -> void:
	var np := NinePatchRect.new()
	np.texture = load("res://assets/converted/ninepatch_ui/%s.tres" % frame)
	np.patch_margin_left = 16; np.patch_margin_right = 16
	np.patch_margin_top = 16; np.patch_margin_bottom = 16
	np.size = Vector2(280, 86); np.position = pos
	# 🔴 2026-07-27: 패배 결과에서 살아남은 몬스터 스파인(holder z_index 8~100)이
	#   '재도전/도망치기' 버튼을 덮었다(사용자 신고). 결과 버튼은 전투원보다 항상 위.
	np.z_index = 124
	add_child(np)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = np.size; l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	np.add_child(l)
	var b := Button.new()
	b.flat = true; b.size = np.size
	b.pressed.connect(cb)
	np.add_child(b)

# ---------- helpers ----------
func _find(internal_name: String) -> Dictionary:
	return _views.get(internal_name, {})

func _disp(internal_name) -> String:
	var n := String(internal_name)
	if n == "E0":
		return String(_enemy.get("name", "적"))
	if n.begins_with("A") and n.substr(1).is_valid_int():
		var i := int(n.substr(1))
		if i < _party.size():
			return String(_party[i].get("name", "드래곤"))
	return n

func _wait(base: float) -> void:
	var t := 0.03 if _skip else base / _speed
	await get_tree().create_timer(t).timeout

func _vis() -> Vector2:
	return get_viewport_rect().size

func _man(dir: String) -> Dictionary:
	var f := FileAccess.open("res://assets/converted/%s/_manifest.json" % dir, FileAccess.READ)
	if f == null: return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func _portrait(id: int, stage: String, scale := 1.0) -> Sprite2D:
	var dir := "portrait_%d" % id
	if not _portrait_man.has(dir):
		_portrait_man[dir] = _man(dir)
	var frame := "dragon_dragon_%d_box_%s" % [id, stage]
	# 원본에 evolution 프레임이 없는 비각성 가능 종/미변환 개발 빌드만 adult로 대체한다.
	if not (_portrait_man[dir] as Dictionary).has(frame) and stage == "evolution":
		frame = "dragon_dragon_%d_box_adult" % id
	return _spr(dir, frame, _portrait_man[dir], scale)

## 원작 아틀라스 프레임을 얹은 플랫 버튼(클릭영역=Button, 비주얼=_spr 자동 회전복원 스프라이트 중앙배치).
func _img_button(frame: String, size: Vector2, scale := 1.0) -> Button:
	var b := Button.new()
	b.size = size
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	var sp := _spr("adventure_ui", frame, _adv, scale)
	if sp:
		sp.position = size * 0.5
		b.add_child(sp)
	else:
		b.text = frame.get_slice("_", -1)   # 폴백: 프레임명 꼬리
	return b

## 아틀라스 지정 이미지 버튼 — 크기는 프레임 실측 × scale 로 잡는다(원작 CCMenuItemImageEx 처럼
## 프레임이 곧 클릭 영역). 프레임이 없으면 null 을 돌려 호출측이 생략하게 한다(자작 대체 금지).
func _img_button_from(dir: String, frame: String, man: Dictionary, scale := 1.0) -> Button:
	var sp := _spr(dir, frame, man, scale)
	if sp == null:
		return null
	var fi: Dictionary = man.get(frame, {})
	var b := Button.new()
	b.size = Vector2(float(fi.get("w", 32)), float(fi.get("h", 32))) * scale
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	sp.position = b.size * 0.5
	b.add_child(sp)
	return b

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

## 스킬 전용 이펙트 스파인 재생. 씬이 없으면 false 를 돌려 호출측이 폴백하게 한다.
##
## 원작 배치(AdventureScene.c:38828-38856) — 그대로 옮긴다:
##   CCSkeletonAnimation::createWithFile(json, atlas, **1.0**)   ← 스파인 자체 배율 1.0
##   setScale(1.0)                                               ← (특수 케이스 param_1==4 만 2.0, +y130)
##   setPosition(target.contentSize * 0.5)                       ← **컨테이너의 중심**
##   target->addChild(spine, 100)                                ← z=100
##   runAction(Sequence(callfunc, DelayTime(0.7), Hide|Blink))    ← 0.7초 재생 후 숨김
## 🔴 여기서 `target` 은 몬스터 스파인이 아니라 `BattleMonster::getAnimatedSpriteNode()`
##   **컨테이너**다(AdventureScene.c:38855 의 부모 = plVar10 추적). 원작 노드 구조와 왜 형제로
##   붙여야 하는지는 `_normal_attack_fx` 위의 구조 주석에 정리해 뒀다.
## 임의 경로의 스파인 씬 한 번 재생 — `_play_skill_spine` 과 같은 배치 규약(z=100, 0.7초 뒤 정리).
func _play_fx_spine_scene(path: String, v: Dictionary) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var holder := Node2D.new()
	holder.z_index = 100
	add_child(holder)
	holder.position = v.get("center", _vis() * 0.5)
	holder.scale = v.get("base_scale", Vector2(0.85, 0.85))
	var inst = (load(path) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
	if ap and ap.has_animation("animation"):
		ap.get_animation("animation").loop_mode = Animation.LOOP_NONE
		ap.play("animation")            # 원작 setAnimation("animation", loop=false)
	var t2 := holder.create_tween()
	t2.tween_interval(_SKILL_SPINE_SEC)   # 원작 Delay(0.7) → Hide → 제거
	t2.tween_callback(holder.queue_free)
	return true

func _play_skill_spine(sid: int, v: Dictionary) -> bool:
	var path := "res://scenes/fx/skill_%d_spine.tscn" % sid
	if not ResourceLoader.exists(path):
		return false
	var holder := Node2D.new()
	holder.z_index = 100                                  # 원작 addChild(spine, 100)
	add_child(holder)
	holder.position = v.get("center", _vis() * 0.5)
	# 원작 스파인 자체 배율은 1.0. 몸통 배율(몬스터 0.85/보스 0.66)은 우리 레이아웃 값이라
	# 종전 모습(스파인 자식으로 물려받던 크기)을 유지하도록 그대로 곱한다.
	# ASSUMPTION: 카드(Control) 대상은 base_scale 이 없어 몬스터 기본값 0.85 로 둔다(종전과 동일).
	holder.scale = v.get("base_scale", Vector2(0.85, 0.85))
	var inst = (load(path) as PackedScene).instantiate()
	holder.add_child(inst)
	var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
	if ap:
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
	# 원작은 애니 길이와 무관하게 **0.7초 뒤 숨김**(Hide/Blink) 이다.
	var t := holder.create_tween()
	t.tween_interval(_SKILL_SPINE_SEC)
	t.tween_callback(holder.queue_free)
	return true
