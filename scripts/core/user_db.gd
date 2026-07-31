extends Node
## Autoload "UserDB": 유저 데이터베이스 — 가변 플레이어 상태의 단일 진실 공급원.
##
## 설계 원칙 (CLAUDE.md §5):
##   - 게임 기능(UI/시스템)은 이 API만 호출한다. raw dict(_data)를 직접 만지지 않는다.
##   - 영구 보존 대상 = 보유 드래곤별 육성 상태 + 아이템 인벤토리 + 재화 + 외형/진행도.
##   - 저장은 SaveSystem(순수 파일IO)에 위임. 마스터 데이터(불변)는 Data가 담당.
##   - 드래곤은 배열 인덱스가 아니라 안정적 고유 uid로 식별한다(방생/정렬에도 안전).

const SCHEMA_VERSION := 15  # v15=알 강화 등급이 곁 테이블(`meta.egg_grades`)→**인벤 키 접미사**(`egg:17#2`, EggItem). 원작 AccountManager::setInfoEggs 가 등급별로 목록 항목을 따로 두어 가방에서 다른 칸이 된다(2026-07-31) · v14=혼돈의 틈새 소환 상태(`darknix` {status,until,face}) — 원작 AccountManager 의 서버 계정 상태를 세이브로 옮김(2026-07-31) · v13=알 강화 등급이 `{알키:등급}`→**`{알키:{등급:개수}}`**(원작 Egg 개체 grade 를 스택 아이템에 옮긴 곁 테이블, 2026-07-30) · v12=피로도→**허기**(hunger) 개칭·정식 필드화(원작 후기판은 피로도 삭제·허기만 남음, 사용자 확정 2026-07-30) · v11=장비칸 해금이 개수(int)→**해금 칸 id 배열**(원작 드래곤 강화는 임의 순서 해금) · v10=레벨 자동 습득 기록(skill_grants 10·25·45) · v9=스킬 학습 풀/장착 2칸 분리(skill_equip) · v1=인덱스기반 → v2=uid기반 → v3=개체 편차(stat_bonus)/grade 파생화 → v4=레벨업 롤 누적(gain_log) → v5=드래곤 보관소(storage, '드래곤의 고삐') → v6=젬 슬롯 타입(gems.types, 원작 getGemType) → v7=슬롯 타입 불일치 젬 회수 → v8=유저 프로필(user.nickname, 원작 User::getNickName)

var _data: Dictionary = {}
var _autosave := true       # false면 변경이 메모리에만 반영(일괄 작업 후 save())

func _ready() -> void:
	var loaded = SaveSystem.load_or_backup()
	if loaded == null:
		_data = _default()
		SaveSystem.save(_data)
	else:
		_data = _migrate(loaded)
	print("[UserDB] v%d 로드 — 드래곤 %d마리, 골드 %d" % [
		int(_data.get("version", 0)), dragon_count(), gold()])

# ============================================================ 스키마
func _default() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"next_uid": 1,                                # 다음에 발급할 드래곤 고유 uid
		# 유저 프로필 — 원작 `User` 모델(AccountManager::getUser)의 오프라인 잔존분.
		# 원작 게터 전수(`grep -o "User::get[A-Za-z]*" docs/ref/orig_code/decomp/*.c`)에 **유저 레벨은 없다**
		# (getNestLevel = 둥지 레벨). 메인화면 좌상단의 "Lv50"은 대표 드래곤 레벨이다
		# (원작 TownMainMenuLayer::setInfoDragon 이 common/dragon_cover1 + 그 드래곤 레벨을 그린다).
		# 나머지 필드(getCash/getGradePvp/getWarPoint …)는 전부 온라인 전용이라 컷(§2-1).
		"user": {"nickname": ""},                     # 원작 User::getNickName / setNickName
		"currency": {"gold": 0, "diamond": 0},        # §I
		"dragons": [],                                # 보유 드래곤 인스턴스 목록(동굴 슬롯)
		"storage": [],                                # 드래곤 보관소(고삐로 넣은 드래곤 — 편성·관리 불가)
		"active_uid": 0,                              # 현재 활성 드래곤 uid (0=없음)
		"inventory": {},                             # {아이템명: 수량}
		"cosmetics": {"cave_skin": 0, "stand_skin": 0, "wall_skin": 0},
		"progress": {},                              # 스테이지/퀘스트 진행도
		"dex_master": [],                            # **오라성체까지 키운 전적**이 있는 도감 id 목록(가방 알칸 `M` 배지)
		# 혼돈의 틈새 소환 상태(원작 AccountManager 의 darknix 3필드). 아래 §혼돈의 틈새 참조.
		"darknix": {"status": 0, "until": 0, "face": 0},
		"rng_seed": null,
	}

## 기준선(grade 7.0) 대비 개체 편차 0 — 갓 부화한 드래곤 기본값(grade 정확히 7.0). (§K-10)
func _zero_bonus() -> Dictionary:
	return {"base": {"hp": 0, "att": 0, "def": 0}, "growth": {"hp": 0, "att": 0, "def": 0}}

## 보유 드래곤 1마리의 영구 저장 스키마. 미사용 필드도 예약(향후 세이브 포맷 안정성).
## stat_bonus = 개체 스탯 편차(grade는 여기서 파생, 저장 안 함 §K-10).
## 스펙 5요소(스탯/젬/장신구/스킬/각성) 중 각성만 현재 필드 보유 — 나머지는 해당 시스템 구현 시 추가.
func _new_dragon(id: int, level: int, stat_bonus: Dictionary) -> Dictionary:
	var uid := int(_data["next_uid"])
	_data["next_uid"] = uid + 1
	return {
		"uid": uid,
		"id": id,                # 도감 ID (마스터 데이터 Data.get_dragon용)
		"level": level,
		"exp": 0,
		"stat_bonus": stat_bonus,            # 기준선 대비 편차 {base/growth × hp/att/def}
		"gain_log": [],          # 레벨업 롤 누적 [{hp,att,def} …] (§K-1 정정, 랜덤롤 모델). 불변식 level==1+size
		"awakened": false,       # 각성 여부 → 레벨캡 45/50
		# 각성 스킬 no (data/skill_awaken.json). 종족 고유라 각성 시 Data.awaken_skill_of 로 채운다.
		# 0 = 미각성이거나 배정표에 아직 없는 종족.
		"awaken_skill": 0,
		# 행동불능 해제 시각(유닉스, 0=정상). 원작 Dragon::cureTime 과 같은 표현.
		"cure_time": 0,
		# 허기 게이지(FOOD). **상한=배부름 … 0=굶음** — 원작 용어 `Dragon::isFood` /
		# `common/bar_food` / `StatusLayer::onClickFood` 를 따른다.
		# 사용자 확정(2026-07-30): 원작 초기의 **피로도 5칸은 후기판에서 삭제**되고 허기만 남았다
		# → 우리는 피로도를 구현하지 않는다. 전투마다 줄고(`battle.gd FOOD_PER_BATTLE`),
		# **속성이 맞는 먹이**로만 회복한다(전량/절반 = 먹이 종류. 규칙 = `ItemEffect.food_after_feed`).
		# 0이면 탐험 입장 불가 · 탐험 중 0이 되면 즉시 종료.
		"food": ItemEffect.FOOD_MAX,
		"nickname": "",
		"locked": false,         # 방생 잠금(퀵패널 안전잠금, 레시피 §6)
		"favorite": false,       # 즐겨찾기(퀵패널, 레시피 §6)
		# 학습 풀 [{id,level,dedicated}] — 원작 `Dragon::getSkillList()`. **상한 없음.**
		# 비면 전투 진입 시 기본배정(Loadout.default_skills).
		"skills": [],
		# 장착 2칸(원작 `Dragon::getSkill(0/1)`) — 학습 풀의 스킬 번호, 0=빈칸. Lv10/35 해금.
		"skill_equip": [0, 0],
		# 자동 습득을 이미 받은 레벨 목록(Loadout.SKILL_GRANT_LEVELS = 10·25·45).
		"skill_grants": [],
		# 젬 3칸 — 원작 Dragon::getGemType(slot) 대응. 사용자 확정(2026-07-27):
		# **부화 시 칸마다 4종(ATT/DEF/HP/ALL) 중 랜덤 1종**. 알도 같은 레코드라 여기서 부여하며
		# (부화 때 다시 뽑아도 결과 분포는 같다), '샌즈의 비약'으로 재부여할 수 있다.
		"gems": {"types": Gem.random_types(Data.gems), "slots": [null, null, null]},
		# 스킬 2칸의 타입(원작 Dragon::getSkillType). '다이즈의 호신부'로 재부여.
		"skill_slots": Loadout.random_slot_types(),
		"acquired_at": int(Time.get_unix_time_from_system()),
	}

# ============================================================ 유저 프로필
## 원작 User::getNickName. 미설정이면 "" — 호출부는 이걸로 "최초 1회 입력" 여부를 판단한다.
func user_nickname() -> String:
	return String(_data.get("user", {}).get("nickname", ""))

func has_user_nickname() -> bool:
	return user_nickname().strip_edges() != ""

## 원작 User::setNickName(AccountManager.c:13173). 길이 제한은 render 쪽(NickNameLayer)이 건다.
func set_user_nickname(name: String) -> void:
	if not _data.has("user"): _data["user"] = {"nickname": ""}
	_data["user"]["nickname"] = name.strip_edges()
	_commit()

## 장착 칭호(원작 User::getTitle). 저장 위치는 기존 meta.title_no 를 그대로 쓴다(중복 스키마 금지).
func user_title_no() -> int:
	return int(get_pmeta("title_no", 0))

# ============================================================ 드래곤
func dragons() -> Array:
	return _data["dragons"]

func dragon_count() -> int:
	return _data["dragons"].size()

func get_dragon(uid: int) -> Dictionary:
	for d in _data["dragons"]:
		if int(d["uid"]) == uid:
			return d
	return {}

func add_dragon(id: int, level: int = 1, stat_bonus: Dictionary = {}) -> Dictionary:
	var inst := _new_dragon(id, level, _zero_bonus() if stat_bonus.is_empty() else stat_bonus)
	_data["dragons"].append(inst)
	if active_uid() == 0:
		_data["active_uid"] = inst["uid"]
	_commit()
	return inst

## ---- 알(부화 대기) ----
## 원작 Dragon::setHatchTime/setEggGrade: **알도 드래곤 레코드**로 둥지 슬롯에 들어간다.
## 규칙(등급 롤·소요시간)은 logic 층 Hatchery — 여기서는 상태 저장/조회만 한다.
## inherit = 커스텀 종(600·700)이 재료 드래곤에서 물려받는 것 {art_id, element, nickname}.
## 그 종들은 마스터 데이터에 `stages`·`element` 가 비어 있어서(플레이어 선택권 드래곤)
## **개체가 스스로 들고 있어야** 그림·속성을 알 수 있다. 규칙은 `Summon.plan`, 읽는 쪽은
## `Icons.art_id_of` / `element_of`. 일반 알은 이 인자를 넘기지 않는다.
func add_egg(id: int, grade: float, seconds: int, enhance := 0, inherit: Dictionary = {},
		blessed := false) -> Dictionary:
	var inst := _new_dragon(id, 1, _zero_bonus())
	inst["egg"] = true
	inst["egg_grade"] = snappedf(grade, 0.1)
	inst["egg_enhance"] = int(enhance)          # 이름 앞 "+N" 배지(연구소 알 강화, 미구현)
	# 축복받은 둥지로 시작한 알인가. 원작은 `User::getNestLevel()`(계정 상태)로 갈렸지만
	# 우리 축복은 **1회성**이라 알 개체에 기록한다. 읽는 곳 = `cave.gd` 의 둥지 그림
	# (nest_holy1/2 + 먼지)과 부화 연출의 보너스 성급 분리 표시(docs/ref/porting/EggHatch.md §1).
	inst["egg_blessed"] = bool(blessed)
	inst["hatch_at"] = int(Time.get_unix_time_from_system()) + maxi(0, seconds)
	if not inherit.is_empty():
		if int(inherit.get("art_id", 0)) > 0:
			inst["art_id"] = int(inherit["art_id"])
		if typeof(inherit.get("element")) == TYPE_STRING:
			inst["element"] = String(inherit["element"])
		if String(inherit.get("nickname", "")) != "":
			inst["nickname"] = String(inherit["nickname"])
	_data["dragons"].append(inst)
	if active_uid() == 0:
		_data["active_uid"] = inst["uid"]
	_commit()
	return inst

func is_egg(d: Dictionary) -> bool:
	return bool(d.get("egg", false))

## 남은 부화 시간(초). 알이 아니면 0.
func hatch_remain(d: Dictionary) -> int:
	if not is_egg(d):
		return 0
	return maxi(0, int(d.get("hatch_at", 0)) - int(Time.get_unix_time_from_system()))

## 타이머가 끝난 알을 레벨1 드래곤으로 부화시킨다. 성공 시 true.
## 초기 등급은 stat_bonus로 환산해 적용(Hatchery.stat_bonus_for_grade).
func hatch_egg(uid: int, stat_bonus: Dictionary) -> bool:
	for d in _data["dragons"]:
		if int(d["uid"]) != uid or not is_egg(d):
			continue
		if hatch_remain(d) > 0:
			return false
		d.erase("egg"); d.erase("hatch_at"); d.erase("egg_blessed")
		d["level"] = 1
		d["stat_bonus"] = stat_bonus
		_commit()
		return true
	return false


## 알의 부화 시각을 **지금**으로 당긴다(원작 `onClickEggDia` = 다이아 즉시 부화).
## 원작은 서버가 `hatch_time` 을 되돌려 주고 클라는 `Dragon::setHatchTime` 만 한다.
func set_hatch_now(uid: int) -> bool:
	for d in _data["dragons"]:
		if int(d["uid"]) == uid and is_egg(d):
			d["hatch_at"] = int(Time.get_unix_time_from_system())
			_commit()
			return true
	return false

# --- 드래곤 보관소(원작 '드래곤의 고삐') -----------------------------------
# 사용자 확정(2026-07-27): 고삐 = 동굴 슬롯의 드래곤을 보관소에 **임시로** 넣어 슬롯을 비운다.
# 보관된 드래곤은 편성·관리 불가 → `dragons()` 에서 빠져야 한다(그래서 배열을 옮긴다).

func storage_dragons() -> Array:
	return _data.get("storage", [])

## 드래곤을 보관소로 옮긴다. 잠긴 개체·마지막 1마리·알은 거부(false).
func store_dragon(uid: int) -> bool:
	var arr: Array = _data["dragons"]
	if arr.size() <= 1:
		return false                       # 동굴이 비면 활성 드래곤이 사라진다
	for i in arr.size():
		if int(arr[i]["uid"]) != uid:
			continue
		if bool(arr[i].get("locked", false)) or is_egg(arr[i]):
			return false
		var d: Dictionary = arr[i]
		arr.remove_at(i)
		(_data["storage"] as Array).append(d)
		if active_uid() == uid:
			_data["active_uid"] = int(arr[0]["uid"]) if not arr.is_empty() else 0
		_commit()
		return true
	return false

## 보관소에서 동굴 슬롯으로 되돌린다.
func unstore_dragon(uid: int) -> bool:
	var st: Array = _data.get("storage", [])
	for i in st.size():
		if int(st[i]["uid"]) != uid:
			continue
		var d: Dictionary = st[i]
		st.remove_at(i)
		(_data["dragons"] as Array).append(d)
		_commit()
		return true
	return false

func release_dragon(uid: int) -> bool:
	var arr: Array = _data["dragons"]
	for i in arr.size():
		if int(arr[i]["uid"]) == uid:
			if bool(arr[i].get("locked", false)):
				return false
			# 원작 `DragonHistoryLayer`(육성 화면 '하늘둥지' 탭)는 떠나보낸 드래곤을 기록해 두고
			# `callRevive` 로 되살릴 수 있게 한다 → 방출 시 여기에 남긴다.
			_push_sky_nest(arr[i])
			arr.remove_at(i)
			if active_uid() == uid:
				_data["active_uid"] = int(arr[0]["uid"]) if not arr.is_empty() else 0
			_commit()
			return true
	return false

## 드래곤을 **소멸**시킨다 — 방생(`release_dragon`)과 달리 하늘둥지에 기록을 남기지 않는다.
## 점술집 '드래곤 소환'이 재료를 소비할 때 쓴다: 떠나보낸 것이 아니라 알로 변한 것이라
## `callRevive`(하늘둥지 되살리기)로 다시 불러올 수 있으면 안 된다 — 되살리면 커스텀 종
## 1마리 상한을 우회해 재료를 무한히 재사용할 수 있다. 잠긴 개체는 거부(방생과 같은 가드).
func consume_dragon(uid: int) -> bool:
	var arr: Array = _data["dragons"]
	for i in arr.size():
		if int(arr[i]["uid"]) != uid:
			continue
		if bool(arr[i].get("locked", false)):
			return false
		arr.remove_at(i)
		if active_uid() == uid:
			_data["active_uid"] = int(arr[0]["uid"]) if not arr.is_empty() else 0
		_commit()
		return true
	return false

## 하늘둥지 기록 추가(최근 것이 위). 상한은 data/promote.json `sky_nest.max_records`.
func _push_sky_nest(d: Dictionary) -> void:
	var recs = get_pmeta("sky_nest", [])
	var arr: Array = (recs as Array).duplicate() if recs is Array else []
	arr.push_front({
		"id": int(d.get("id", 0)),
		"name": String(d.get("name", "")),
		"level": int(d.get("level", 1)),
		"date": Time.get_date_string_from_system(),
	})
	var cap := int(Data.promote.get("sky_nest", {}).get("max_records", 50))
	while arr.size() > maxi(1, cap):
		arr.pop_back()
	set_pmeta("sky_nest", arr)

func active_uid() -> int:
	return int(_data.get("active_uid", 0))

func active_dragon() -> Dictionary:
	return get_dragon(active_uid())

func set_active(uid: int) -> void:
	if not get_dragon(uid).is_empty():
		_data["active_uid"] = uid
		_commit()

## 전투 파티(원작 Select3DragonsLayer): 출전 드래곤 uid 목록(최대 3). 비면 전투가 활성+보유순 폴백.
func party() -> Array:
	var raw: Array = _data.get("party", [])
	var out: Array = []
	for u in raw:
		if not get_dragon(int(u)).is_empty() and not out.has(int(u)):
			out.append(int(u))   # 유효(보유중)한 uid만
	return out.slice(0, 3)

func in_party(uid: int) -> bool:
	return party().has(int(uid))

## 파티 토글: 있으면 제거, 없으면 추가(최대 3). 반환=성공여부(꽉 찬 상태서 추가 시 false).
func toggle_party(uid: int) -> bool:
	if get_dragon(uid).is_empty(): return false
	var p := party()
	if p.has(int(uid)):
		p.erase(int(uid))
	elif p.size() < 3:
		p.append(int(uid))
	else:
		return false
	_data["party"] = p
	_commit()
	return true

func clear_party() -> void:
	_data["party"] = []
	_commit()

func set_level(uid: int, level: int) -> void:
	var d := get_dragon(uid)
	if not d.is_empty():
		d["level"] = level
		_commit()
		sync_skill_grants(uid)

func add_exp(uid: int, n: int) -> void:
	var d := get_dragon(uid)
	if not d.is_empty():
		d["exp"] = int(d.get("exp", 0)) + n
		_commit()

## 레벨업 결과 반영(랜덤롤 모델): 롤 gains([{hp,att,def} …])를 gain_log에 누적 + 레벨/잔여exp 갱신. 1회 커밋.
## 불변식 level==1+gain_log.size() 유지. 규칙 계산은 LevelSystem(logic), 여기선 저장만.
func apply_levelups(uid: int, new_level: int, new_exp: int, gains: Array) -> void:
	var d := get_dragon(uid)
	if d.is_empty():
		return
	var gl: Array = d.get("gain_log", [])
	for g in gains:
		gl.append({"hp": int(g.get("hp", 0)), "att": int(g.get("att", 0)), "def": int(g.get("def", 0))})
	d["gain_log"] = gl
	d["level"] = new_level
	d["exp"] = new_exp
	_commit()
	sync_skill_grants(uid)   # 레벨 10·25·45 자동 습득
	# 도감 '오라성체' 전적(방생해도 남는 영구 기록 → 도감 단계 5 · 가방 알칸 노란 `M` 배지).
	# 🔴 2026-07-30: 기록을 세우는 곳이 여태 **아무데도 없어서** 단계 5에 영원히 도달할 수 없었다.
	# 조건 = 오라성체 도달(Lv.45, `Growth.AURA_ADULT_LEVEL` — 사용자 확정 + 클라 근거).
	if Growth.is_aura_adult(new_level):
		mark_dex_master(int(d.get("id", 0)))

## LV-1 아이템: 직전 레벨업 롤 1개 무효화(gain_log 팝) + 레벨-1 + 잔여exp 0. 반환=성공(레벨>1일 때만).
func level_down(uid: int) -> bool:
	var d := get_dragon(uid)
	if d.is_empty() or int(d.get("level", 1)) <= 1:
		return false
	var gl: Array = d.get("gain_log", [])
	if not gl.is_empty():
		gl.remove_at(gl.size() - 1)
	d["gain_log"] = gl
	d["level"] = int(d["level"]) - 1
	d["exp"] = 0
	_commit()
	return true

## LV+1/축복 아이템: 지정 롤(gain={hp,att,def})로 1레벨 상승(gain_log 누적). 반환=성공(상한 미만일 때).
## 상한 판정은 호출측(cave)이 Growth/Data로 수행 — 여기선 저장만. exp는 유지.
func level_up_with(uid: int, gain: Dictionary) -> bool:
	var d := get_dragon(uid)
	if d.is_empty():
		return false
	var gl: Array = d.get("gain_log", [])
	gl.append({"hp": int(gain.get("hp", 0)), "att": int(gain.get("att", 0)), "def": int(gain.get("def", 0))})
	d["gain_log"] = gl
	d["level"] = int(d.get("level", 1)) + 1
	_commit()
	sync_skill_grants(uid)   # 레벨 10·25·45 자동 습득
	return true

## 능력치 다시뽑기(리롤): 직전 레벨의 롤을 새 gain으로 교체(레벨 불변). 반환=성공(gain_log 있을 때).
func replace_last_gain(uid: int, gain: Dictionary) -> bool:
	var d := get_dragon(uid)
	if d.is_empty():
		return false
	var gl: Array = d.get("gain_log", [])
	if gl.is_empty():
		return false
	gl[gl.size() - 1] = {"hp": int(gain.get("hp", 0)), "att": int(gain.get("att", 0)), "def": int(gain.get("def", 0))}
	d["gain_log"] = gl
	_commit()
	return true

func set_dragon_field(uid: int, key: String, value) -> void:
	var d := get_dragon(uid)
	if not d.is_empty():
		d[key] = value
		_commit()

# ---- 행동불능(원작 Dragon::cureTime) ----
## 원작은 상태를 **해제 시각(유닉스) 한 개**로 들고 있었다(`isStun` = `now < cureTime`,
## docs/ref/orig_code/decomp/Dragon.c:11359). 우리도 같은 표현을 쓴다 — 0 = 정상.
## 판정·비용은 `Incapacitation`(logic), 여기는 저장만 한다.
func cure_time(uid: int) -> int:
	return int(get_dragon(uid).get("cure_time", 0))

func set_cure_time(uid: int, t: int) -> void:
	set_dragon_field(uid, "cure_time", maxi(0, t))

## 지금 행동불능인가(= 전투에 못 나간다).
func is_down(uid: int) -> bool:
	return Incapacitation.is_down(cure_time(uid), int(Time.get_unix_time_from_system()))

# ---- 스킬(스펙 5요소 중 하나) ----
## **학습 풀** [{id,level,dedicated}] — 원작 `Dragon::getSkillList()`. 상한 없음.
## 순수 저장 — 배정/습득 규칙은 logic(Loadout)이 담당.
func dragon_skills(uid: int) -> Array:
	return get_dragon(uid).get("skills", [])

## 장착 2칸의 스킬 번호(0=빈칸). 원작 `Dragon::getSkill(slot)`.
func dragon_skill_equip(uid: int) -> Array:
	return Loadout.equipped_ids(get_dragon(uid))

## 장착 칸에 꽂힌 스킬 레코드만 순서대로([{id,level,dedicated}], 빈칸은 건너뜀).
## 전투가 쓰는 것은 학습 풀 전체가 아니라 **이것**이다.
## 반환 {skills, slot_types} — Battle 이 인덱스 정렬을 전제로 하므로 칸 타입도 같이 좁혀 준다.
func dragon_battle_skills(uid: int) -> Dictionary:
	var dr := get_dragon(uid)
	var types: Array = Loadout.slot_types(dr)
	var out: Array = []
	var tys: Array = []
	for i in Loadout.SKILL_SLOTS:
		var e := Loadout.equipped_entry(dr, i)
		if e.is_empty():
			continue
		out.append(e)
		tys.append(String(types[i]) if i < types.size() else "star")
	return {"skills": out, "slot_types": tys}

## 레벨 자동 습득 동기화 — 레벨 10·25·45 를 넘겼는데 아직 안 받은 게 있으면 그만큼 배운다.
## 멱등(받은 레벨은 `skill_grants` 에 기록). 레벨이 바뀌는 모든 경로에서 호출한다.
## 반환 = 이번에 배운 목록 [{level, id, name}] (연출·토스트용, 없으면 빈 배열).
##
## 규칙 출처 = 위키("레벨 10·25·45 달성 시 스킬을 랜덤으로 하나씩 자동 습득"). 서버가 하던 일이라
## 클라 디컴프에 없다 → 무엇을 뽑는지는 **아직 안 배운 usable 스킬 중 무작위**(ASSUMPTION).
## 시드는 (uid, 마일스톤) 고정이라 같은 드래곤은 몇 번을 돌려도 같은 스킬을 배운다.
##
## ASSUMPTION: 배운 스킬은 **열려 있는 빈 칸이 있으면 자동 장착**한다. Lv10 에 첫 스킬을 배우는데
##   칸이 비어 있으면 전투에 아무것도 안 나가기 때문(원작은 서버가 장착까지 해 줬을 가능성이 크다).
func sync_skill_grants(uid: int) -> Array:
	var d := get_dragon(uid)
	if d.is_empty():
		return []
	var level := int(d.get("level", 1))
	# JSON 왕복에서 숫자가 float 로 돌아오므로 int 로 정규화한다(`has()` 비교 안전).
	var claimed: Array = []
	for c in (d.get("skill_grants", []) as Array):
		claimed.append(int(c))
	var due := Loadout.due_grants(level, claimed)
	if due.is_empty():
		return []
	var pool: Array = d.get("skills", [])
	var learned: Array = []
	for m in due:
		var r := RandomNumberGenerator.new()
		r.seed = hash("skillgrant_%d_%d" % [uid, int(m)])
		var got := Loadout.roll_grant(pool, Data.skills, r)
		claimed.append(int(m))
		if got.is_empty():
			continue          # 더 배울 스킬이 없다 — 마일스톤은 소진 처리
		pool.append({"id": int(got["id"]), "level": int(got["level"]), "dedicated": false})
		learned.append({"level": int(m), "id": int(got["id"]),
			"name": String(Data.skills.get(str(int(got["id"])), {}).get("name", "스킬"))})
	d["skills"] = pool
	d["skill_grants"] = claimed
	# 열린 빈 칸에 자동 장착
	var eq: Array = Loadout.equipped_ids(d)
	for e in learned:
		for i in Loadout.SKILL_SLOTS:
			if int(eq[i]) == 0 and Loadout.slot_unlocked(i, level):
				eq[i] = int(e["id"])
				break
	d["skill_equip"] = eq
	_commit()
	return learned

## 칸에 스킬을 꽂거나(skill_id>0) 해제(0). 규칙은 Loadout.equip_skill.
func set_dragon_skill_equip(uid: int, slot: int, skill_id: int) -> void:
	var d := get_dragon(uid)
	if d.is_empty():
		return
	d["skill_equip"] = Loadout.equip_skill(d, slot, skill_id)
	_commit()

## 비어 있을 때만 채운다(전투 첫 진입 시 기본배정 영속화용). 멱등.
## ASSUMPTION: 기본배정분은 **빈 칸에 그대로 장착**해 준다. 원작의 개체별 보유/장착 스킬은
##   서버와 함께 유실됐고(Loadout 머리말), 스타터가 풀에만 있고 칸이 비면 전투에 스킬이
##   하나도 안 나간다. 습득(스크롤)은 원작대로 자동 장착하지 않는다 — 그건 SkillsPopup 의 일.
func ensure_dragon_skills(uid: int, skills: Array) -> void:
	var d := get_dragon(uid)
	if not d.is_empty() and (d.get("skills", []) as Array).is_empty():
		d["skills"] = skills
		var eq: Array = Loadout.equipped_ids(d)
		for i in Loadout.SKILL_SLOTS:
			if int(eq[i]) == 0 and i < skills.size():
				eq[i] = int((skills[i] as Dictionary).get("id", 0))
		d["skill_equip"] = eq
		_commit()

func set_dragon_skills(uid: int, skills: Array) -> void:
	var d := get_dragon(uid)
	if not d.is_empty():
		d["skills"] = skills
		_commit()

## 퀵패널 토글(레시피 §6). 상태 조회/반전 — render는 이 API만 호출.
func is_locked(uid: int) -> bool:
	return bool(get_dragon(uid).get("locked", false))

func is_favorite(uid: int) -> bool:
	return bool(get_dragon(uid).get("favorite", false))

func toggle_locked(uid: int) -> bool:
	var d := get_dragon(uid)
	if d.is_empty(): return false
	d["locked"] = not bool(d.get("locked", false))
	_commit()
	return bool(d["locked"])

func toggle_favorite(uid: int) -> bool:
	var d := get_dragon(uid)
	if d.is_empty(): return false
	d["favorite"] = not bool(d.get("favorite", false))
	_commit()
	return bool(d["favorite"])

## 도감: 해당 도감 id를 보유한 적이 있는가(현재 보유 목록 기준).
func dex_seen(id: int) -> bool:
	for d in _data["dragons"]:
		if int(d["id"]) == id:
			return true
	return false

## 도감: 보유한 같은 id 중 최고 레벨(없으면 0). 진화/각성 시스템 전이라 단계는 레벨로 근사.
func dex_best_level(id: int) -> int:
	var best := 0
	for d in _data["dragons"]:
		if int(d["id"]) == id:
			best = maxi(best, int(d["level"]))
	return best

## 도감: 해당 id를 각성시킨 적이 있는가 — 보유 개체 중 각성체(`awakened`)가 있으면 참.
## (각성 시스템 배선 2026-07-29. 방생해도 남는 영구 이력은 TODO — 필요해지면 dex_master 처럼
## 저장 필드로 승격한다.)
func dex_awakened(id: int) -> bool:
	for d in _data["dragons"]:
		if int(d["id"]) == id and bool(d.get("awakened", false)):
			return true
	return false

## 도감 마스터 기록: 같은 종을 **오라성체까지 키운 전적**이 있는가.
## 가방 알 칸의 노란 `M` 배지 조건 — 사용자 확인(docs/input/review/lost_text_sheet.md §3).
## 보유 목록이 아니라 **영구 기록**이다(방생해도 남는다) → dex_seen 과 달리 저장 필드를 본다.
func dex_master(id: int) -> bool:
	# ⚠️ JSON 왕복으로 숫자가 float 이 된다(세이브를 다시 읽으면 54 → 54.0) → `has(54)` 가 실패한다.
	#    _ensure_schema 에서 int 로 되돌리지만, 구버전 세이브 대비로 여기서도 값으로 비교한다.
	for v in _data["dex_master"]:
		if int(v) == id:
			return true
	return false

## 도감 단계(원작 Book::getStep 대응): 0=미등록 1=알 2=해치 3=해츨링 4=성체 5=오라성체 6=각성.
## 원작 값은 서버 소유였고 우리는 보유 이력에서 파생한다: 각성 이력>오라성체(마스터) 기록>
## 최고 레벨의 성장 단계>알 보유(가상 키 `egg:<id>`) 순.
func dex_step(id: int) -> int:
	if dex_awakened(id):
		return 6
	if dex_master(id):
		return 5
	if dex_seen(id):
		match Growth.stage_for_level(dex_best_level(id)):
			"adult": return 4
			"child": return 3
			_: return 2
	if item_count("egg:%d" % id) > 0:
		return 1
	return 0

## 오라성체 도달을 도감에 영구 기록한다(멱등).
## ⚪ 호출부: 오라성체 진화가 구현되면 그 지점에서 부른다. 현재 진화는 baby/child/adult 까지만이라
##    아직 세워지는 곳이 없다(Growth.stage_for_level 참조) — 기록 스키마만 먼저 둔다.
func mark_dex_master(id: int) -> void:
	if dex_master(id):
		return
	_data["dex_master"].append(id)
	_commit()

# ============================================================ 인벤토리
func inventory() -> Dictionary:
	return _data["inventory"]

func item_count(key: String) -> int:
	return int(_data["inventory"].get(key, 0))

func add_item(key: String, n: int = 1) -> void:
	var inv: Dictionary = _data["inventory"]
	inv[key] = int(inv.get(key, 0)) + n
	if inv[key] <= 0:
		inv.erase(key)
	_commit()

## 아이템을 n개 소비. 부족하면 아무것도 안 하고 false.
func use_item(key: String, n: int = 1) -> bool:
	var inv: Dictionary = _data["inventory"]
	var have := int(inv.get(key, 0))
	if have < n:
		return false
	inv[key] = have - n
	if inv[key] <= 0:
		inv.erase(key)
	_commit()
	return true

# ============================================================ 재화
func currency(kind: String) -> int:
	return int(_data["currency"].get(kind, 0))

func gold() -> int:
	return currency("gold")

func diamond() -> int:
	return currency("diamond")

func add_currency(kind: String, amount: int) -> void:
	_data["currency"][kind] = currency(kind) + amount
	_commit()

## 최상위 메타 저장(일일보상 날짜 등 진행성 잡데이터). 세이브에 없으면 즉석 생성.
func get_pmeta(key: String, default = null):
	return _data.get("meta", {}).get(key, default)

func set_pmeta(key: String, value) -> void:
	if not _data.has("meta"): _data["meta"] = {}
	_data["meta"][key] = value
	_commit()

## ---- 알 강화 등급 ----
## v15 부터 **곁 테이블이 없다.** 등급은 인벤 키에 실린다(`egg:17#2` — `EggItem`).
## 근거: 원작 `AccountManager::setInfoEggs` 가 서버 행마다 `Egg` 개체를 따로 만들어 목록에
## 넣으므로 같은 알 번호라도 등급이 다르면 **가방에서 다른 칸**이다(EggItem 주석 전문).
## 그래서 조회는 `EggItem.grade_of(key)`, 보유수는 그냥 `item_count(key)` 다.

## 일일 퀘스트 카운터(날짜 바뀌면 자동 리셋). bump=증가, count=조회, is_claimed/claim=보상 수령.
func quest_count(key: String) -> int:
	var q: Dictionary = get_pmeta("quests", {})
	if String(q.get("date", "")) != Time.get_date_string_from_system(): return 0
	return int(q.get(key, 0))

func bump_quest(key: String) -> void:
	var today := Time.get_date_string_from_system()
	var q: Dictionary = (get_pmeta("quests", {}) as Dictionary).duplicate()
	if String(q.get("date", "")) != today: q = {"date": today}
	q[key] = int(q.get(key, 0)) + 1
	set_pmeta("quests", q)

func quest_claimed(key: String) -> bool:
	var q: Dictionary = get_pmeta("quests", {})
	if String(q.get("date", "")) != Time.get_date_string_from_system(): return false
	return bool(q.get("claimed_" + key, false))

## 🔴 `bump_quest` 과 **똑같이 날짜를 찍는다.** 안 찍으면 어제 날짜가 남은 딕셔너리에 기록되고,
##    바로 뒤의 `bump_quest` 가 날짜 불일치를 보고 `{"date": today}` 로 갈아엎어 **수령 기록이
##    조용히 사라진다.** 마을 미션은 카운터가 0 이면 완료가 안 되니 종전엔 드러나지 않았는데,
##    라온 도움(다이아 결제)은 카운터와 무관하게 완료시키므로 날짜가 바뀐 뒤 첫 동작이면
##    **다이아만 빠져나갔다**(2026-07-31 townwire 회귀 검사가 잡음).
func claim_quest(key: String) -> void:
	var today := Time.get_date_string_from_system()
	var q: Dictionary = (get_pmeta("quests", {}) as Dictionary).duplicate()
	if String(q.get("date", "")) != today: q = {"date": today}
	q["claimed_" + key] = true
	set_pmeta("quests", q)

## ---- 마을 미션 수락/포기 (원작 TownQuestManager 흐름) ----
## 원작은 서버가 퀘스트 상태를 들고 있다(`requestTownQuest`/`responseTownQuest`).
## 오프라인은 같은 `quests` 일일 딕셔너리에 상태를 얹는다:
##   `accepted_<key>` 수락 여부 · `base_<key>` 수락 시점의 카운터(그 뒤 증가분만 진행도로 센다)
##   · `gaveup_<key>` 포기(원작 `GiveUpQuest` = "포기한 퀘스트는 다시 진행할 수 없습니다")
func quest_accepted(key: String) -> bool:
	var q: Dictionary = get_pmeta("quests", {})
	if String(q.get("date", "")) != Time.get_date_string_from_system(): return false
	return bool(q.get("accepted_" + key, false))

func quest_gaveup(key: String) -> bool:
	var q: Dictionary = get_pmeta("quests", {})
	if String(q.get("date", "")) != Time.get_date_string_from_system(): return false
	return bool(q.get("gaveup_" + key, false))

## 수락. 카운터는 전역이므로(전투·부화 등은 수락 여부를 모른다) **수락 시점 값을 기준선으로**
## 남겨 그 뒤 증가분만 진행도로 센다.
func accept_quest(key: String) -> void:
	var today := Time.get_date_string_from_system()
	var q: Dictionary = (get_pmeta("quests", {}) as Dictionary).duplicate()
	if String(q.get("date", "")) != today: q = {"date": today}
	q["accepted_" + key] = true
	q["base_" + key] = int(q.get(key, 0))
	set_pmeta("quests", q)

func giveup_quest(key: String) -> void:
	var today := Time.get_date_string_from_system()
	var q: Dictionary = (get_pmeta("quests", {}) as Dictionary).duplicate()
	if String(q.get("date", "")) != today: q = {"date": today}
	q["gaveup_" + key] = true
	q.erase("accepted_" + key)
	set_pmeta("quests", q)

## 수락 이후의 진행도. 미수락이면 0.
func quest_progress(key: String) -> int:
	if not quest_accepted(key): return 0
	var q: Dictionary = get_pmeta("quests", {})
	return maxi(0, int(q.get(key, 0)) - int(q.get("base_" + key, 0)))

## kind 재화를 amount만큼 소비. 부족하면 false.
func spend(kind: String, amount: int) -> bool:
	if currency(kind) < amount:
		return false
	_data["currency"][kind] = currency(kind) - amount
	_commit()
	return true

# ============================================================ 외형/진행도
func get_skin(slot: String) -> int:
	return int(_data["cosmetics"].get(slot, 0))

func set_skin(slot: String, idx: int) -> void:
	_data["cosmetics"][slot] = idx
	_commit()

func get_progress(key: String, default = null):
	return _data["progress"].get(key, default)

func set_progress(key: String, value) -> void:
	_data["progress"][key] = value
	_commit()

# ============================================================ 혼돈의 틈새 소환 상태
# 원작 `AccountManager` 의 다크닉스 3필드를 그대로 옮긴 것 —
#   `getDarkNixStatus()`     → status (1/2/3, 어느 보스가 소환됐나)
#   `getLimitTime_darknix()` → until  (unix초, 이 시각까지 월드맵에 상주)
#   `getDarknixFace()`       → face   (0 없음 / 1 조우~1차전투 / 2 마무리 일격 대기)
# 원작은 셋 다 **서버가 내려주던 계정 상태**다(로그인 응답 + `cash_darknix.hb` 응답).
# 오프라인에선 세이브가 그 자리를 대신한다. 규칙 판정은 `Darknix`(logic), 여기는 저장만(§8.2).
func darknix() -> Dictionary:
	var d = _data.get("darknix", {})
	return (d as Dictionary) if d is Dictionary else {}

## 소환 확정 — `Darknix.roll()` 결과를 그대로 받는다(`{status, enemy, until, face}`).
func darknix_summon(v: Dictionary) -> void:
	_data["darknix"] = {
		"status": int(v.get("status", 1)),
		"until": int(v.get("until", 0)),
		"face": int(v.get("face", 0)),
		"seen": 0,                      # 갓 소환 → 등장 연출을 한 번 보여준다
	}
	_commit()

## 등장 연출(`appear`)을 이미 보여줬는가 — 원작 `AccountManager::getAlarm_darknix()==2`.
## 원작 `showDarknix`(:5123)는 이 값이 2면 `showDarknix(false)`(등장 생략, 곧바로 breath),
## 아니면 2로 세우고 `showDarknix(true)`(등장 재생)한다. `hideDarknix` 가 0으로 되돌린다.
## 🔴 이게 없으면 월드맵을 떠났다 돌아올 때마다 5.2초짜리 `appear` 가 다시 돌아
##    그동안 드래곤 슬롯이 꺼져 있어 **보스가 사라지고 이펙트만 뜬 것처럼** 보인다
##    (2026-07-31 사용자 신고: 상점 갔다 오면 그렇다).
func darknix_seen() -> bool:
	return int(darknix().get("seen", 0)) != 0

func darknix_mark_seen() -> void:
	var d := darknix()
	d["seen"] = 1
	_data["darknix"] = d
	_commit()

## 대면 단계 갱신(원작 `setDarknixFace`).
func darknix_set_face(face: int) -> void:
	var d := darknix()
	d["face"] = face
	_data["darknix"] = d
	_commit()

## 처치/만료 — 원작 `setLimitTime_darknix(0)` + `setDarknixFace(0)`.
func darknix_clear() -> void:
	_data["darknix"] = {"status": 0, "until": 0, "face": 0}
	_commit()

# ============================================================ 저장 제어
func _commit() -> void:
	if _autosave:
		SaveSystem.save(_data)

## ---- 커스텀 종(600·700)의 종 이름 ----
## 원작에 없는 축이다. 커스텀 종은 마스터 `name` 이 비어 있고(`name_from_player: true`)
## **점술집 '드래곤 소환'에서 재료가 된 드래곤의 이름을 종 이름으로 물려받는다**
## (사용자 확정 2026-07-30 — 예: 고대신룡 "별밤이"를 수비형 재료로 쓰면 600 의 종 이름이 "별밤이").
## 종당 1마리 상한(`Summon.species_available`)이라 세이브당 종 이름이 하나로 정해진다.
## 읽는 쪽은 `Icons.species_name` / `Icons.name_of` — 여기서는 저장/조회만 한다(§8.2).
func species_name(id: int) -> String:
	var all = get_pmeta("species_names", {})
	if not (all is Dictionary):
		return ""
	return String((all as Dictionary).get(str(id), ""))

func set_species_name(id: int, name: String) -> void:
	var all = get_pmeta("species_names", {})
	var d: Dictionary = (all as Dictionary) if all is Dictionary else {}
	d[str(id)] = name
	set_pmeta("species_names", d)

## 일괄 변경 시: begin_batch() → ...여러 변경... → save() 로 디스크 쓰기 1회.
func begin_batch() -> void:
	_autosave = false

func save() -> void:
	_autosave = true
	SaveSystem.save(_data)

func reset() -> void:
	_data = _default()
	SaveSystem.save(_data)

## 디스크에서 다시 읽어 메모리 상태를 교체(저장 슬롯 로드/재시작용).
func reload() -> void:
	var loaded = SaveSystem.load_or_backup()
	_data = _default() if loaded == null else _migrate(loaded)

## 디버그/검증 전용. UI/시스템 코드에서는 쓰지 말 것(스키마 우회 금지).
func raw() -> Dictionary:
	return _data

# ============================================================ 마이그레이션
func _migrate(d: Dictionary) -> Dictionary:
	var ver := int(d.get("version", 1))
	if ver < 2:
		d = _migrate_v1_to_v2(d)        # 인덱스 → uid 구조 변환(드래곤 필드는 _ensure_schema가 v3로 보강)
	d = _ensure_schema(d)               # 누락 키 + 구버전 드래곤 필드 보강 + 버전 갱신
	if ver < SCHEMA_VERSION:
		print("[UserDB] 세이브 마이그레이션 v%d → v%d (%d마리)" % [ver, SCHEMA_VERSION, d["dragons"].size()])
		SaveSystem.save(d)
	return d

## v1(인덱스 기반) → v2(uid 기반) 구조 변환만 수행(필드 채움은 _ensure_schema).
## 주의: 구버전의 저장된 grade는 폐기(v3에서 grade는 stat_bonus 파생 — 역산 불가, 편차 0=grade 7.0에서 시작).
func _migrate_v1_to_v2(d: Dictionary) -> Dictionary:
	var base := _default()
	base["currency"] = d.get("currency", base["currency"])
	base["inventory"] = d.get("inventory", base["inventory"])
	base["progress"] = d.get("progress", base["progress"])
	base["rng_seed"] = d.get("rng_seed", null)
	base["cosmetics"] = {
		"cave_skin": int(d.get("cave_skin", 0)),
		"stand_skin": int(d.get("stand_skin", 0)),
		"wall_skin": int(d.get("wall_skin", 0)),
	}
	var old_list: Array = d.get("owned_dragons", [])
	var active_idx := int(d.get("active_dragon", 0))
	var uid := 1
	for i in old_list.size():
		var od: Dictionary = old_list[i]
		base["dragons"].append({
			"uid": uid, "id": int(od.get("id", 0)),
			"level": int(od.get("level", 1)), "exp": int(od.get("exp", 0)),
		})
		if i == active_idx:
			base["active_uid"] = uid
		uid += 1
	base["next_uid"] = uid
	if active_uid_of(base) == 0 and not base["dragons"].is_empty():
		base["active_uid"] = int(base["dragons"][0]["uid"])
	return base

func active_uid_of(d: Dictionary) -> int:
	return int(d.get("active_uid", 0))

## 누락된 키/드래곤 필드를 현재(v3) 스키마로 보강 + 버전 갱신(같은 버전 호출 시 멱등).
func _ensure_schema(d: Dictionary) -> Dictionary:
	var base := _default()
	for k in base.keys():
		if not d.has(k):
			d[k] = base[k]
	for k in base["cosmetics"].keys():
		if not d["cosmetics"].has(k):
			d["cosmetics"][k] = base["cosmetics"][k]
	# v8: 유저 프로필 — 구세이브는 user 블록 자체가 없다(위 루프가 통째로 채운다).
	# 여기서는 블록은 있는데 키가 빠진 경우만 보강한다.
	for k in base["user"].keys():
		if not d["user"].has(k):
			d["user"][k] = base["user"][k]
	# JSON 로드는 숫자를 float 으로 준다 → 도감 id 목록을 int 로 정규화(중복도 제거).
	var dm := []
	for v in d.get("dex_master", []):
		var iv := int(v)
		if not dm.has(iv):
			dm.append(iv)
	# v12 백필: 오라성체 전적. `apply_levelups` 가 기록을 세우게 된 것은 2026-07-30 이고,
	# 그전에 이미 Lv.45 를 넘긴 개체는 기록이 없다 → 보유·보관 개체를 훑어 채운다(멱등).
	for dr0 in (d.get("dragons", []) as Array) + (d.get("storage", []) as Array):
		if Growth.is_aura_adult(int((dr0 as Dictionary).get("level", 1))):
			var mid := int((dr0 as Dictionary).get("id", 0))
			if mid > 0 and not dm.has(mid):
				dm.append(mid)
	d["dex_master"] = dm
	# v15: 알 강화 등급 곁 테이블(`meta.egg_grades = {알키: {등급: 개수}}`)을 **인벤 키로 옮긴다**.
	#   `egg:17` 8개 중 2강 1개·1강 2개  →  `egg:17` 5개 + `egg:17#1` 2개 + `egg:17#2` 1개.
	# 원작이 알 개체를 목록에 따로 담아 **등급별로 다른 칸**이 되는 것에 맞춘다(EggItem 주석).
	# 곁 테이블은 옮긴 뒤 지우므로 재실행해도 no-op = 멱등.
	var eg = d.get("meta", {}).get("egg_grades", null)
	if eg is Dictionary and not (eg as Dictionary).is_empty():
		var inv: Dictionary = d.get("inventory", {})
		var moved := 0
		for k in (eg as Dictionary):
			# ⚠️ 변수명 `base` 금지 — 이 함수 첫 줄의 `var base := _default()` 와 충돌해
			#    스크립트 전체가 파스 에러가 난다(2026-07-31).
			var ekey := String(k)
			for g in EggUpgrade.normalize((eg as Dictionary)[ekey]):
				var n := mini(int(EggUpgrade.normalize((eg as Dictionary)[ekey])[g]),
					int(inv.get(ekey, 0)))
				if n <= 0:
					continue
				# 0강 스택에서 빼서 등급 스택으로 옮긴다(총량 보존).
				inv[ekey] = int(inv.get(ekey, 0)) - n
				if int(inv[ekey]) <= 0:
					inv.erase(ekey)
				var gk := EggItem.key(ekey, int(g))
				inv[gk] = int(inv.get(gk, 0)) + n
				moved += n
		d["inventory"] = inv
		print("[UserDB] v15: 강화 알 %d개를 등급별 인벤 칸으로 분리" % moved)
	if d.has("meta") and (d["meta"] as Dictionary).has("egg_grades"):
		(d["meta"] as Dictionary).erase("egg_grades")
	for dr in d.get("dragons", []):
		_ensure_dragon_schema(dr, d["inventory"])
	for dr2 in d.get("storage", []):        # 보관소 개체도 같은 스키마로 보강(v5 추가)
		_ensure_dragon_schema(dr2, d["inventory"])
	d["version"] = SCHEMA_VERSION
	return d

## 드래곤 1마리를 v3 스키마로 보강. 파생/컷 필드는 제거(멱등):
## grade=stat_bonus 파생(§K-10), crest(문장)·engravings(각인)=에셋 부재로 시스템 컷.
## inv = 세이브의 inventory dict. 슬롯 타입에 안 맞는 젬을 빼서 여기에 돌려준다(v7).
func _ensure_dragon_schema(dr: Dictionary, inv: Dictionary) -> void:
	dr.erase("grade")
	dr.erase("crest")
	dr.erase("engravings")
	if typeof(dr.get("stat_bonus")) != TYPE_DICTIONARY:
		dr["stat_bonus"] = _zero_bonus()
	# v11: 장비칸 해금 = 개수(int) → 해금 칸 id 배열. 원작은 순차가 아니라 임의 순서로 연다
	# (docs/ref/Lab/드래곤강화4.png 주의문). 구세이브의 개수 n 은 앞 n칸을 연 것으로 환산한다.
	if typeof(dr.get("equip_slots")) != TYPE_ARRAY:
		var n := clampi(int(dr.get("equip_slots", 1)), 1, Equipment.SLOT_ORDER.size())
		dr["equip_slots"] = Equipment.SLOT_ORDER.slice(0, n)
	# v4: 레벨업 롤 누적(gain_log). 구버전 드래곤은 현 스탯을 정확 보존하도록 백필(멱등).
	if typeof(dr.get("gain_log")) != TYPE_ARRAY:
		dr["gain_log"] = _backfill_gain_log(dr)
	# v12: 피로도(`fatigue`, 0→100 누적) → **허기 FOOD**(상한→0 소모). 사용자 확정(2026-07-30)대로
	# 원작 후기판에는 피로도가 없고 허기만 있다. 눈금 방향이 반대라 **뒤집어** 물려받는다
	# (누적치를 버리지 않는다 — 전투 4회분 피로 60 이면 food 40 으로 이어진다). 멱등.
	if dr.has("fatigue"):
		if not dr.has("food"):
			dr["food"] = clampi(ItemEffect.FOOD_MAX - int(dr["fatigue"]), 0, ItemEffect.FOOD_MAX)
		dr.erase("fatigue")
	var defaults := {"exp": 0, "awakened": false, "awaken_skill": 0, "cure_time": 0,
		"food": ItemEffect.FOOD_MAX,
		"nickname": "", "locked": false, "favorite": false, "skills": [], "acquired_at": 0}
	for k in defaults.keys():
		if not dr.has(k):
			dr[k] = defaults[k]
	# 이미 각성해 둔 구형 세이브 — 각성스킬 배정표가 나중에 생겼으므로 백필(멱등).
	if bool(dr.get("awakened", false)) and int(dr.get("awaken_skill", 0)) <= 0:
		dr["awaken_skill"] = Data.awaken_skill_of(int(dr.get("id", 0)))
	# v6: 젬 슬롯 타입(원작 Dragon::getGemType). 부화 시 칸마다 4종 중 랜덤 1종이므로
	#     구형 세이브에도 **랜덤으로** 부여한다(고정 부여하면 전 개체가 같은 색이 된다).
	if typeof(dr.get("gems")) != TYPE_DICTIONARY:
		dr["gems"] = {}
	var gf: Dictionary = dr["gems"]
	if typeof(gf.get("types")) != TYPE_ARRAY or (gf["types"] as Array).size() < Gem.SLOTS:
		gf["slots"] = Gem.entries(gf)          # 조밀 배열 → 칸 고정 배열로 먼저 정규화
		gf["types"] = Gem.random_types(Data.gems)
	# v7: 칸 타입에 **맞지 않는 젬은 빼서 가방으로 돌려준다.**
	#   v6 에서는 "진행도 보존"이라며 그대로 뒀는데, 그 결과 체력 칸에 공격 젬이 박힌 상태가
	#   화면에 그대로 보였다(사용자 보고 2026-07-27). 원작 규칙(`CaveGemEuqipMsg2`
	#   "선택한 젬과 맞는 슬롯이 없습니다")과 어긋나므로 정리한다. 젬은 잃지 않는다.
	#   멱등 — 이후 장착은 Gem.equip_at 이 타입을 검사하므로 다시 생기지 않는다.
	var gtypes: Array = Gem.types(gf)
	var gents: Array = Gem.entries(gf)
	var moved := false
	for i in Gem.SLOTS:
		var e = gents[i]
		if e == null:
			continue
		if Gem.accepts(String(gtypes[i]), String(e["name"]), Data.gems):
			continue
		var rk := Gem.item_key(String(e["name"]), int(e["tier"]))
		inv[rk] = int(inv.get(rk, 0)) + 1
		gents[i] = null
		moved = true
	if moved:
		gf["slots"] = gents
		print("[UserDB] uid=%d 슬롯 타입 불일치 젬을 가방으로 반환" % int(dr.get("uid", 0)))
	if typeof(dr.get("skill_slots")) != TYPE_ARRAY or (dr["skill_slots"] as Array).size() < Loadout.SKILL_SLOTS:
		dr["skill_slots"] = Loadout.random_slot_types()
	# v9: 학습 풀과 장착칸 분리(원작 `Dragon::getSkillList` vs `getSkill(0/1)`).
	#   구형 세이브의 `skills` 는 둘을 겸한 배열이었으므로 **앞 2개를 그대로 장착분으로** 본다
	#   (화면에 보이던 그대로 유지 = 진행도 보존). 풀은 손대지 않는다.
	if typeof(dr.get("skill_equip")) != TYPE_ARRAY or (dr["skill_equip"] as Array).size() < Loadout.SKILL_SLOTS:
		var eq: Array = []
		var sk: Array = dr.get("skills", [])
		for i in Loadout.SKILL_SLOTS:
			eq.append(int((sk[i] as Dictionary).get("id", 0)) if i < sk.size() else 0)
		dr["skill_equip"] = eq
	# v10: 레벨 자동 습득(10·25·45) 기록. 구형 드래곤은 **이미 지난 마일스톤을 받은 것으로 처리**한다
	#   — 지금 소급 지급하면 스크롤로 배운 것 위에 공짜 스킬이 얹힌다(진행도 왜곡). 앞으로의
	#   레벨업분만 지급된다. 새 드래곤은 `_new_dragon` 이 빈 배열로 시작해 Lv10 부터 정상 지급.
	if typeof(dr.get("skill_grants")) != TYPE_ARRAY:
		var claimed: Array = []
		for m in Loadout.SKILL_GRANT_LEVELS:
			if int(dr.get("level", 1)) >= int(m):
				claimed.append(int(m))
		dr["skill_grants"] = claimed

## v3→v4 백필: 구모델(결정론 base+growth×(L-1))의 현 스탯을 보존하도록 gain_log 재구성.
## 레벨 L 드래곤 = (티어growth + 개체growth편차)를 (L-1)회 누적한 것과 동치. Data(오토로드, 먼저 로드됨) 사용.
## 티어 미매칭(row 없음)이면 빈 로그(레벨1 스탯) — 정상 드래곤엔 발생 안 함.
func _backfill_gain_log(dr: Dictionary) -> Array:
	var level := int(dr.get("level", 1))
	if level <= 1:
		return []
	var ddef: Dictionary = Data.get_dragon(int(dr.get("id", 0)))
	var row := Growth._tier_row(ddef, Data.stat_table)
	if row.is_empty():
		push_warning("[UserDB] gain_log 백필 실패(티어 미매칭) uid=%d id=%s" % [int(dr.get("uid", 0)), str(dr.get("id"))])
		return []
	var gb: Dictionary = (dr.get("stat_bonus", {}) as Dictionary).get("growth", {})
	var per := {}
	for k in ["hp", "att", "def"]:
		per[k] = int(row["growth"][k]) + int(gb.get(k, 0))
	var out: Array = []
	for i in level - 1:
		out.append(per.duplicate())
	return out
