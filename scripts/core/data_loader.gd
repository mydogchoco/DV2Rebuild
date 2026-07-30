extends Node
## Autoload "Data": data 층 — 정적 게임 정의(data/*.json)를 읽어 제공만 한다. (CLAUDE.md §10)
## 규칙(스탯 공식/레벨→단계 등 logic)은 여기 두지 않는다 → scripts/systems/(Growth 등).
## Master data is restored by the user (see docs/game_design.md), not in assets.

var dragons: Dictionary = {}     # id(int) -> dragon dict
var stat_table: Dictionary = {}  # type -> tier -> {base,growth}
var new_game: Dictionary = {}    # 새 게임 초기 로드아웃 정의
var dex_meta: Dictionary = {}    # str(id) -> {awaken, evo} (도감 진화루트 메타)
var items: Dictionary = {}       # 아이템키(str) -> 마스터 정의(name/category/icon/effect/use…). `_` 메타는 제외
var items_meta: Dictionary = {}  # items.json 의 `_` 로 시작하는 메타(출처·offline 상태 설명)
var combat: Dictionary = {}      # 전투 상수·속성 상성 (§K-2~K-6, §B)
var skills: Dictionary = {}      # str(id) -> 스킬 마스터 정의 (§C, docs/input/skills/skills_skeleton.csv)
var worldmap: Dictionary = {}    # 월드맵 지역/노드 정의(자작 ASSUMPTION — 서버데이터 유실)
var dragon_skills: Dictionary = {}   # 드래곤별 스킬 override(자작 — 유실). 없으면 Loadout 기본배정.
var stages: Dictionary = {}          # 스테이지 정의(적/배경/보상). 자작 — 유실(사용자 작성).
## 스토리 대사(원작 stringsData_KR.xml 전량 추출, build_scenario.py).
var scenario: Dictionary = {}
## 스토리 **연출 흐름**(회차별 화자·표정·위치·배경·삽화·BGM).
## 🔴 2026-07-31 정정: 종전 "흐름 데이터 = ScenarioScript(서버 JSON) 전량 유실" 은 **오진**이었다.
## `ScenarioManager::makeScenarioLayer(sn)` 이 회차를 `Scenario1~8`/`_zimon`/`_mamorudic`/
## `_Kadeath` 로 가르고 그 클래스들이 연출을 **하드코딩**한다(102화 이상만 `ScenarioCommon`
## = 서버 script 라 진짜 유실). 추출 = extract_scenario_flow.py → parse_scenario_flow.py.
var scenario_flow: Dictionary = {}
## 스토리 **목차**(회차 제목·챕터·서브미션·해금레벨). 원작은 로컬 SQLite `info_scenario_v2`
## (`min_lv`·`title`·`daynight`)에서 읽었는데 그 .db 가 우리 덤프에 없어 나무위키에서 뽑았다
## — scripts/tools/build_story_index.py. (종전 주석의 "서버 유실"은 오진, 2026-07-30 정정)
var story: Dictionary = {}
## 스토리 **서브퀘스트 조건**(회차별 던전·탐험 클릭 수·이벤트 전투·월드맵 마크).
## 원작 `ScenarioSubQuestData` 의 하드코딩분을 그대로 추출한 것 — 자작이 아니다.
## 도구 = scripts/tools/extract_story_subquest.py. 규칙 = scripts/systems/story_quest.gd.
var story_subquest: Dictionary = {}
var item_effects: Dictionary = {}      # 드링크 버프·회복물약 수치(위키 규칙 + 사용자 확정)
var battle_missions: Dictionary = {}   # 전투 미션(원작 initJsonBattleMission, 유실→Ref_battle 스샷 복원)
var egg_fragments: Dictionary = {}   # 알조각 세트→드래곤(원작 LaboratoryEggLayer 조합). items.json 세트 구조 기반.
var team_buffs: Dictionary = {}      # 종족 조합 버프(원작 info_dragon_team_buf). 로직=클라복원, 테이블=유실(빈 시작). docs/ref/design/team_buff_analysis.md.
var combine_egg: Dictionary = {}     # 알 조합 레시피(원작 CombineEgg/info_combine_egg). 스키마=클라복원, 행값=유실(빈 시작). docs/input/review/combine_egg_sheet.md.
var combine_item: Dictionary = {}    # 아이템 조합 레시피(원작 CombineItem/info_combine_item). 스키마=클라복원, 행값=유실(빈 시작). docs/input/review/combine_item_sheet.md.
var upgrade_egg: Dictionary = {}     # 알 업그레이드 레시피(원작 UpgradeEgg/info_upgrade_egg). 스키마=클라복원, 행값=유실(빈 시작). docs/input/review/upgrade_egg_sheet.md.
var skill_awaken: Dictionary = {}    # 각성 스킬 표시정보(원작 SkillAwaken/info_skill_awaken). 스키마=클라복원, 행값=유실(빈 시작). docs/input/review/skill_awaken_sheet.md.
var level_curve: Dictionary = {}     # 레벨업 경험치 곡선(req[]/cap). ASSUMPTION — 서버유실, 관측앵커로 복원(build_level_curve.py).
var dragon_voices: Dictionary = {}   # 드래곤별 보이스 번호(baby/child/adult). 원작=info_dragon_v2 컬럼(Dragon.c:13478) → 유실. 값=dragons.csv voice_* 열(사용자 검수 2026-07-31), 반영=build_dragon_voice_sheet.py --apply.
var gems: Dictionary = {}            # 젬 14종×티어(일반/혼성/소울). 위키 전량(build_gems.py), 타입코드=클라복원(Dragon.c).
var titles: Dictionary = {}          # 칭호 149종(원작 AchieveTitleLayer/info_title_v). 아트=title/<no>_kr.png, 획득조건=자작.
var icon_map: Dictionary = {}        # 논리키→원본 아이콘 프레임(build_item_icons.py). render 층(Icons)만 사용.
var equipment: Dictionary = {}       # 장비(장신구/특수/아티팩트/편린) + 옵션표. 위키 전량(build_equipment.py), 슬롯·옵션스키마=클라복원.
var npc_lines_doc: Dictionary = {}   # 마을 NPC 이름/대사(원작 stringsData_KR.xml, build_npc_lines.py). 유실 아님.
var drops: Dictionary = {}           # 젬·장비 획득처(탐험드롭/상점/가챠). 규칙=사용자확정+위키, 확률·가격=자작 노브. 로직=Drops.
var shop: Dictionary = {}            # 상점(원작 ShopScene) 탭·NPC·재고. 구조=클라복원, 가격=Ref_shop 스크린샷 실측.
var laboratory: Dictionary = {}      # 연구소(원작 LaboratoryScene). 기능·수치는 docs/ref/orig_image/lab/labwiki.pdf 위키 확정 + 일부 자작.
var promote: Dictionary = {}         # 육성(원작 PromoteScene) 훈련캠프·교배·하늘둥지. 수치는 서버유실→자작 노브.
var npc_talk: Dictionary = {}        # NPC 대사(원작 stringsData_KR.xml 전량, build_npc_talk.py). 유실 아님.
var npc_face: Dictionary = {}        # NPC 얼굴 파츠(눈/입) 몸통 로컬 좌표. libgame.so NpcManager::setTarget 하드코딩 추출.
var card_game: Dictionary = {}       # 탐험 카드 미니게임(원작 CardMiniGameLayer). 규칙·보상종류=위키 확정, 가중치=자작. 로직=CardGame.
var imp_shop: Dictionary = {}       # 임프상인(원작 ImpShopScene) 재고·가격. 랭킹은 ⚫CUT. 로직=ImpShop.
var monster_drops: Dictionary = {}   # 몬스터별 고유 드랍(밤 공용 조우 4종·혼돈의 틈새 보스). 원작 드랍표=서버유실 → 사용자 CSV. 로직=Drops.roll_monster.
var adventure_events: Dictionary = {}  # 탐험 이벤트 큐(원작은 서버 exe_event 배열 — 클라에 생성 코드 없음). 로직=AdventureRun.
var awaken: Dictionary = {}          # 드래곤 각성 규칙. 재료수량=위키 item.pdf 확정, 레벨조건·상한=자작.
var gacha_eggs: Dictionary = {}      # 뽑기 알(의문의 알/빛문알/속성알) 개봉 풀. 성급범위=위키 item.pdf §5, 가중치=자작 노브. 로직=EggGacha.
var kades: Dictionary = {}           # 카데스의 공간(유타칸 전설 모드) 규칙. BGM=원작 디컴프 확정, 페널티·보스레벨=위키 확정. 로직=Kades.
## 에자녹 스크롤 → 스킬 아이템 변환표(등급=획득 스킬 레벨). 원작 근거는 파일 `_basis` 참조.
var skill_scrolls: Dictionary = {}
var incapacitation: Dictionary = {}  # 행동불능(원작 Dragon::cureTime). 상태표현·다이아비용=원작 확정, 발생조건·1시간=사용자 확정. 로직=Incapacitation.
## 카드 코드(원작 CodeLayer). 원작 판정=서버 유실 → 사용자 이스터에그 표.
## **암호문이다** — 항목은 `{id,n,d,t}` 뿐이고 코드·보상은 입력한 코드로만 풀린다(로직=CardCode).
## 평문 원본은 docs/input/sheets/card_codes.csv(gitignore), 빌드는 build_card_codes.py.
var card_codes: Dictionary = {}
## 도감 설명 텍스트(원작 info_dragon.comment — "획득방법: …"+플레이버). **서버 유실** →
## 선택 파일 data/dex_comments.json(str(id)→문자열)이 채워진 만큼만 표시(위키 추출 후보).
var dex_comments: Dictionary = {}

func _ready() -> void:
	_load_dragons("res://data/dragons.json")
	stat_table = _load_json("res://data/stat_table.json")
	new_game = _load_json("res://data/new_game.json")
	dex_meta = _load_json("res://data/dex_meta.json")
	items = _load_json("res://data/items.json")
	# items.json 은 "아이템키 → 정의" **평면 맵**이다. 출처·상태 설명 같은 메타는 `_` 로 시작하는
	# 키에 담기는데, 그대로 두면 `for k in Data.items` 로 도는 코드가 문자열을 아이템으로 오인한다
	# (2026-07-29 실제 사고: `_use_basis`(문자열)에 `.get()` 을 불러 런타임 에러).
	# ⇒ 로드 직후 분리한다. 다른 data 파일은 최상위가 이미 블록 구조라 해당 없음.
	items_meta = {}
	for k in items.keys():
		if String(k).begins_with("_"):
			items_meta[k] = items[k]
			items.erase(k)
	combat = _load_json("res://data/combat.json")
	skills = _load_json("res://data/skills.json")
	worldmap = _load_json("res://data/worldmap.json")
	dragon_skills = _load_json("res://data/dragon_skills.json")
	stages = _load_json("res://data/stages.json")
	egg_fragments = _load_json("res://data/egg_fragments.json")
	team_buffs = _load_json("res://data/team_buffs.json")
	combine_egg = _load_json("res://data/combine_egg.json")
	combine_item = _load_json("res://data/combine_item.json")
	upgrade_egg = _load_json("res://data/upgrade_egg.json")
	skill_awaken = _load_json("res://data/skill_awaken.json")
	level_curve = _load_json("res://data/level_curve.json")
	dragon_voices = _load_json("res://data/dragon_voices.json")
	battle_missions = _load_json("res://data/battle_missions.json")
	item_effects = _load_json("res://data/item_effects.json")
	npc_lines_doc = _load_json("res://data/npc_lines.json")
	gems = _load_json("res://data/gems.json")
	equipment = _load_json("res://data/equipment.json")
	drops = _load_json("res://data/drops.json")
	icon_map = _load_json("res://data/icon_map.json")
	titles = _load_json("res://data/titles.json")
	scenario = _load_json("res://data/scenario.json")
	scenario_flow = _load_json("res://data/scenario_flow.json")
	story = _load_json("res://data/story.json")
	story_subquest = _load_json("res://data/story_subquest.json")
	shop = _load_json("res://data/shop.json")
	npc_face = _load_json("res://data/npc_face.json")
	promote = _load_json("res://data/promote.json")
	laboratory = _load_json("res://data/laboratory.json")
	npc_talk = _load_json("res://data/npc_talk.json")
	gacha_eggs = _load_json("res://data/gacha_eggs.json")
	kades = _load_json("res://data/kades.json")
	incapacitation = _load_json("res://data/incapacitation.json")
	card_codes = _load_json("res://data/card_codes.json")
	skill_scrolls = _load_json("res://data/skill_scrolls.json")
	awaken = _load_json("res://data/awaken.json")
	card_game = _load_json("res://data/card_game.json")
	adventure_events = _load_json("res://data/adventure_events.json")
	imp_shop = _load_json("res://data/imp_shop.json")
	if FileAccess.file_exists("res://data/monster_drops.json"):
		monster_drops = _load_json("res://data/monster_drops.json")
	# 선택 파일 — 없으면 조용히 빈 채로 둔다(유실 데이터, 채워지는 만큼만 표시).
	if FileAccess.file_exists("res://data/dex_comments.json"):
		dex_comments = _load_json("res://data/dex_comments.json")
	print("[Data] %d dragons, %d items, stat types=%s" % [
		dragons.size(), items.size(), str(stat_table.keys())])

func _load_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[Data] missing " + path); return {}
	return JSON.parse_string(f.get_as_text())

func _load_dragons(path: String) -> void:
	var arr = _load_json(path)
	for d in arr:
		dragons[int(d["id"])] = d

func get_dragon(id: int) -> Dictionary:
	return dragons.get(id, {})

func new_game_def() -> Dictionary:
	return new_game

func dragon_dex_meta(id: int) -> Dictionary:
	return dex_meta.get(str(id), {})

## 도감 설명(원작 Dragon::getComment). 서버 유실 → **사용자가 `dragons.csv` 의 `도감 설명`
## 열에 복원**한 것이 정본이고(`build_data.py` → dragons.json `desc`), `dex_comments.json`
## 은 그 위에 얹는 선택적 덮어쓰기다(있으면 우선). 둘 다 없으면 "".
func dragon_comment(id: int) -> String:
	var over := String(dex_comments.get(str(id), ""))
	if over != "":
		return over
	return String(get_dragon(id).get("desc", ""))

## 게임에 노출되는 드래곤 id 목록 — **`dex_hidden` 종은 빠진다.**
##
## 사용자 확정(2026-07-30): `dragons.csv` 이름 칸이 비었거나 `null` 인 행은 미구현 더미다.
## 완전 공백 21건은 `build_data.py` 가 아예 싣지 않고, `null` 2건(600·700 = 플레이어 선택권
## 드래곤)은 `dex_hidden: true` 로 실려 **기본적으로 도감·입수처에서 제외**된다.
## ⇒ 이 함수 하나를 거치는 곳(도감 목록 · 부화/조합 랜덤 풀 · 속성별 집계)이 전부 따라온다.
## 트리거로 보여야 하는 화면(도감)은 `dragon_ids_hidden()` 을 따로 받아 조건부로 덧붙인다.
func dragon_ids() -> Array:
	var ids := []
	for k in dragons:
		if not bool((dragons[k] as Dictionary).get("dex_hidden", false)):
			ids.append(k)
	ids.sort()
	return ids

## 기본 숨김 종(현재 600·700). 특수 트리거로 노출하는 화면만 쓴다.
func dragon_ids_hidden() -> Array:
	var ids := []
	for k in dragons:
		if bool((dragons[k] as Dictionary).get("dex_hidden", false)):
			ids.append(k)
	ids.sort()
	return ids

## 이 종이 기본 숨김인가(도감·입수처 제외 대상).
func dragon_hidden(id: int) -> bool:
	return bool(dragons.get(id, {}).get("dex_hidden", false))

## **무작위 입수 풀**에 들어가도 되는 드래곤 id 목록.
##
## `dragon_ids()`(도감 목록)에서 `acquire_locked` 종을 더 뺀다. 사용자 확정(2026-07-30):
## 커스텀 세대는 **지정된 방법으로만** 얻는다 —
##   · 600(수비형)·700(공격형) = 점술집 '드래곤 소환'(`Summon`)
##   · 666 샛별 · 777 한울      = 점술집 '카드 코드'(`magicshop.gd::_grant_card_reward`)
## 666·777 은 도감에는 정상 등재되므로 `dex_hidden` 으로는 못 막는다(축이 다르다).
## ⇒ **랜덤으로 드래곤/알을 주는 코드는 이 함수를 쓴다**(부화·조합·가챠·탐험 보상 등).
func dragon_ids_random() -> Array:
	var ids := []
	for k in dragons:
		var d: Dictionary = dragons[k]
		if bool(d.get("dex_hidden", false)) or bool(d.get("acquire_locked", false)):
			continue
		ids.append(k)
	ids.sort()
	return ids

## 이 종이 지정 획득처 전용인가(무작위 풀 제외 대상).
func dragon_acquire_locked(id: int) -> bool:
	return bool(dragons.get(id, {}).get("acquire_locked", false))

# ---- 아이템 마스터 데이터 ----
func get_item(key: String) -> Dictionary:
	return items.get(key, {})

func item_name(key: String) -> String:
	return items.get(key, {}).get("name", key)

## 아이템 아이콘 AtlasTexture 경로(res://). 없으면 "".
func item_icon_path(key: String) -> String:
	var ic: String = items.get(key, {}).get("icon", "")
	return "res://assets/converted/%s.tres" % ic if ic != "" else ""

## 월드맵 지역 목록(자작 데이터). render 층 worldmap.gd가 사용.
func worldmap_regions() -> Array:
	return worldmap.get("regions", [])

## 드래곤 스킬 override 맵(도감ID(str) → 스킬목록). 유실→자작. 비면 Loadout 기본배정 사용.
func dragon_skill_overrides() -> Dictionary:
	return dragon_skills.get("overrides", {})

## 스테이지 정의(id → {name,bg,enemies,rewards}). 유실→사용자 자작(data/stages.json). 없으면 {}.
## 반환 dict에 `id`(=키, 원작 필드 id)를 넣어 준다 — 배경 리졸버(DungeonBG) 등이 호출자에서
## 키를 다시 들고 다니지 않아도 되게. 원본 dict는 건드리지 않는다(마스터 데이터=읽기전용).
func stage(id: String) -> Dictionary:
	var s: Dictionary = stages.get("stages", {}).get(id, {})
	if s.is_empty():
		s = _variant_stage(id)          # 유타칸 밤(500+) · 카데스의 공간(600+)
		if s.is_empty():
			return s
	if s.has("id"):
		return s
	var out := s.duplicate()
	out["id"] = int(id) if id.is_valid_int() else id
	return out

## 변형 필드(밤 501~514 / 카데스 601~614) 스테이지. `data/stages.json` 에 전용 정의가 있으면
## 그것이 우선이고(위에서 이미 걸린다), **없으면 기본 필드에서 상속**한다.
##
## 원작에서 변형 필드의 몬스터 편성·레벨은 서버 DB(유실)였다. 여기서 수치를 지어내지 않고
## 기본 필드의 편성을 그대로 물려받되, 배경·이름·3인편성만 변형 규칙대로 바꾼다.
## 사용자가 채울 자리는 `docs/input/review/yutakan_night_kades_sheet.md` 에 표로 열어 뒀다 —
## 시트를 채워 `data/stages.json` 에 "501" 같은 키를 넣으면 이 상속을 덮어쓴다.
##
## ⚠️ 3인 편성(`party3`)은 사용자 확정 규칙이다(2026-07-27): 일반 탐험은 리더 1마리지만
##    **유타칸 밤·카데스의 공간**은 3마리가 함께 나선다.
const _VARIANT_SUFFIX := {"night": "밤", "kades": "카데스의 공간"}
func _variant_stage(id: String) -> Dictionary:
	if not id.is_valid_int():
		return {}
	var fid := int(id)
	var kind := DungeonBG.variant_of(fid)
	if kind == "":
		return {}
	var base := DungeonBG.base_field(fid)
	if DungeonBG.variant_field(base, kind == "night", kind == "kades") != fid:
		return {}                       # 변형이 없는 필드(6·8·15+)의 500/600 번대는 만들지 않는다
	var src: Dictionary = stages.get("stages", {}).get(str(base), {})
	if src.is_empty():
		return {}
	var out := src.duplicate(true)
	out["id"] = fid
	out["bg"] = fid                     # 배경만 변형본(scene/adventure/bg/<fid>/bg.jpg)
	# ⚠️ `name` 은 기본 필드 이름 그대로 둔다 — 한글 조사 선택(`_josa_ro`)이 이름 끝 글자를 보는데
	#    "희망의 숲 (밤)" 처럼 괄호로 끝나면 "…(밤)로 모험을 떠났습니다" 가 된다.
	#    변형 표기는 `variant_label` 로 따로 주고, 표시하는 쪽에서 덧붙인다.
	out["variant_label"] = String(_VARIANT_SUFFIX[kind])
	out["party3"] = true
	out["variant"] = kind
	out["base_field"] = base
	# 변형 필드는 **전용 몬스터만** 등장한다(사용자 확정 2026-07-29) — 낮 편성을 물려받지 않는다.
	#   밤     = 그 던전 전용 보스 1종(#163~174) + 지역 전역 랜덤 4종(#160~162·175) 중 1마리
	#   카데스 = 그 던전 전용 보스 1종(#182~193)만
	# 편성 표 = 각 스테이지의 `night`/`kades` 블록(`scripts/tools/build_yutakan_variants.py` 기입,
	# 출처 = 위키 dungeon_1 §1.2/§1.3/§2.1 + 사용자 확정 몬스터 번호).
	var vv: Dictionary = src.get(kind, {})
	# 밤 변형은 별도 필드 행(레벨 50·전용 등장 드래곤·전용 설명문) — 원작 Field 5xx.
	# 출처 = 레퍼런스 스크린샷 전사(data/stages.json 각 스테이지의 `night` 블록, `_popup_basis`).
	if kind == "night":
		for k in ["level", "desc", "dragons"]:
			if vv.has(k):
				out[k] = vv[k]
			else:
				out.erase(k)            # 미확보 필드는 낮 값을 밤에 그대로 쓰지 않는다(TODO)
	elif kind == "kades":
		# 카데스 필드(6xx)의 등장 드래곤·설명문은 미확보(원작은 보상 아이템 줄 + 전용 desc) → 표시 안 함.
		out.erase("dragons")
		out.erase("desc")
	# 편성 교체. 표가 아직 없는 필드만 낮 편성을 남긴다(`_inherited` = 검수 대상 표시).
	if vv.has("enemies"):
		out["enemies"] = vv["enemies"]
		out["boss"] = _boss_name(vv["enemies"])
		out["random_boss"] = bool(vv.get("random_boss", false))
	else:
		out["_inherited"] = true
	out.erase("night")
	out.erase("kades")
	return out

## 편성에서 보스 이름 하나(팝업·조우 배너용). 보스 표시가 없으면 마지막 항목 이름.
func _boss_name(enemies: Array) -> String:
	for e in enemies:
		if bool((e as Dictionary).get("boss", false)):
			return String((e as Dictionary).get("name", ""))
	if enemies.is_empty():
		return ""
	return String((enemies[-1] as Dictionary).get("name", ""))

## 알 조합 레시피 목록(원작 CombineEgg/info_combine_egg). 각 원소 {combine_no,target,materials,cost}.
## 스키마=클라복원(CombineEgg.c:306), 행값=서버유실→사용자 작성(빈 배열이면 조합 미제공). breeding.gd가 사용.
func combine_egg_recipes() -> Array:
	return combine_egg.get("recipes", [])

## 재료 아이템 키 집합에 정확히 맞는 조합 레시피를 찾는다(순서 무관). 없으면 {}.
func combine_egg_match(material_keys: Array) -> Dictionary:
	var want := material_keys.duplicate(); want.sort()
	for r in combine_egg_recipes():
		var mats: Array = (r as Dictionary).get("materials", [])
		var have := mats.duplicate(); have.sort()
		if have == want:
			return r
	return {}

## 아이템 조합 레시피 목록(원작 CombineItem/info_combine_item). 각 {target,item1,item1_cnt,item2,item2_cnt,cost,cost_type}.
## 스키마=클라복원(CombineItem.c:516), 행값=서버유실→사용자 작성(빈 배열이면 조합 미제공).
func combine_item_recipes() -> Array:
	return combine_item.get("recipes", [])

## 결과 아이템 키로 조합 레시피 조회. 없으면 {}.
func combine_item_for(target_key: String) -> Dictionary:
	for r in combine_item_recipes():
		if String((r as Dictionary).get("target", "")) == target_key:
			return r
	return {}

## 알 업그레이드 레시피 목록(원작 UpgradeEgg/info_upgrade_egg). 각 {upgrade_no,type,grade,materials,cost}.
## 스키마=클라복원(UpgradeEgg.c), 행값=서버유실→사용자 작성(빈 배열이면 미제공).
func upgrade_egg_recipes() -> Array:
	return upgrade_egg.get("recipes", [])

## (알 종류 type, 현재 grade)로 업그레이드 레시피 조회. 원작 where type=%s and grade=%d.
## 재료의 `@element_crystal` 토큰과 와일드카드 행(type='*')은 **해석되지 않은 원본 행**이다 —
## 실제 재료는 `EggUpgrade.recipe_for(...)`(logic)가 알 속성으로 해석한다. 없으면 {}.
func upgrade_egg_for(type_key: String, grade: int) -> Dictionary:
	return EggUpgrade.row_for(type_key, grade, upgrade_egg)

## 각성 스킬 표시정보 목록(원작 SkillAwaken/info_skill_awaken). 각 {no,name,comment}.
## 스키마=클라복원(SkillAwaken.c), 행값=서버유실→사용자 작성(빈 배열이면 미제공).
func skill_awaken_list() -> Array:
	return skill_awaken.get("skills", [])

## 각성 스킬 no로 조회. 원작 where no=%d. 없으면 {}.
func skill_awaken_for(no: int) -> Dictionary:
	for r in skill_awaken_list():
		if int((r as Dictionary).get("no", -1)) == no:
			return r
	return {}

## 도감 id → 그 드래곤이 갖는 각성 스킬 no. 없으면 0.
## 배정표는 서버 유실분을 사용자가 복원한 것이다. **정본 = `dragons.csv` 의 `각성스킬id` 열**
## (→ dragons.json `awaken_skill`). `skill_awaken.csv` 의 `비고`(스킬→드래곤 이름들)는 같은
## 사실의 반대 방향 기입이라 `build_skill_awaken.py` 가 둘을 대조하고(`_drift`), 여기서는
## 드래곤 레코드를 먼저 본 뒤 by_dragon 으로 떨어진다. 아직 배정이 없는 종이 많다 → 0.
func awaken_skill_of(dragon_id: int) -> int:
	var own := int(get_dragon(dragon_id).get("awaken_skill", 0))
	if own > 0:
		return own
	var by: Dictionary = skill_awaken.get("by_dragon", {})
	var lst: Array = by.get(str(dragon_id), [])
	return int(lst[0]) if not lst.is_empty() else 0

## 아트(스파인·초상·알·크리티컬)를 어느 도감 id 것으로 그릴까. 보통 자기 자신.
##
## 자작 드래곤은 다른 드래곤의 그림을 빌려 쓸 수 있다 — `dragons.csv` 의 `notes` 에
## `"루시퍼"와 동일한 이미지 사용` 처럼 적으면 `build_data.py` 가 `art_id` 로 굳힌다.
## **render 층에서 그림 경로를 만들 때는 `id` 가 아니라 이 값을 쓴다.**
## (스탯·속성·이름·각성스킬은 그대로 자기 것이다 — 갈아끼우는 건 그림뿐이다.)
func art_id(dragon_id: int) -> int:
	return int(get_dragon(dragon_id).get("art_id", dragon_id))

## 각성 스킬 아이콘 번호(1~18). 원작 자산 `skill/evolution/<icon>.png`.
## ⚠️ 스킬 no 와 다른 축이다 — 서로 다른 스킬이 같은 아이콘을 공유한다(사용자 확인 2026-07-29).
func awaken_skill_icon(no: int) -> int:
	return int(skill_awaken_for(no).get("icon", 0))

## ---- 레벨업 경험치 곡선(data 층: 값 제공만, 판정은 logic=LevelSystem) ----
## 레벨 L → L+1 필요 경험치. req[L-1]. 범위 밖(상한 이상/미만)이면 0. ASSUMPTION(서버유실).
func exp_to_next(level: int) -> int:
	var req: Array = level_curve.get("req", [])
	if level < 1 or level > req.size():
		return 0
	return int(req[level - 1])

## 레벨 상한(각성 시 확장). 없으면 45/50 기본.
func level_cap(awakened := false) -> int:
	if awakened:
		return int(level_curve.get("cap_awakened", 50))
	return int(level_curve.get("cap", 45))

## category(예: "food") 또는 subcategory(예: "feed")로 필터. offline 상태로도 필터 가능.
func items_by(category := "", subcategory := "", offline := "") -> Array:
	var out: Array = []
	for k in items:
		var v: Dictionary = items[k]
		if category != "" and v.get("category", "") != category:
			continue
		if subcategory != "" and v.get("subcategory", "") != subcategory:
			continue
		if offline != "" and v.get("offline", "") != offline:
			continue
		out.append(k)
	out.sort()
	return out

## ---- 스토리(시나리오) ----
## 대사 텍스트는 원작에 전량 남아 있다(stringsData_KR.xml → build_scenario.py).
## 유실된 것은 흐름 데이터(ScenarioScript: npcNo/bgNo/bgmNo/emotionNo/…)뿐이다.
## 상세: scripts/ui/story.gd 헤더 · docs/input/review/scenario_sheet.md.
func scenario_def(no: String) -> Dictionary:
	return scenario.get("scenarios", {}).get(no, {})

## 회차 연출 스텝 목록 `[{op, …}]`. 원작 클라 하드코딩분이 있는 회차만(없으면 빈 배열).
func scenario_flow_of(no: int) -> Array:
	return scenario_flow.get("flows", {}).get(str(no), [])

## 연출 스텝의 NPC 번호 → `npc/<폴더>` (원작 `ScenarioSupport::getNPCname`).
func scenario_npc_folder(npc_no: int) -> String:
	return String(scenario_flow.get("npc_names", {}).get(str(npc_no), ""))

## 연출 스텝의 배경 번호 → 원작 경로들[원경, 전경아이템?] (`ScenarioSupport::changeBackGround`).
func scenario_bg_paths(bg_no: int) -> Array:
	return scenario_flow.get("backgrounds", {}).get(str(bg_no), [])

## NPC 표시 이름(원작 `<NPC_<폴더>>` 62종). 없으면 폴더명 그대로.
func npc_name(folder: String) -> String:
	if folder == "":
		return ""
	return String(scenario.get("npc_names", {}).get(folder, folder))

## ---- 스토리 목차(원작 MissionStoryLayer 가 서버에서 받던 것) ----
## 회차 정보 {title, chapter, unlock_level, submission?, no_lines?}. 없으면 {}.
func story_episode(no: int) -> Dictionary:
	return story.get("episodes", {}).get(str(no), {})

## 회차 번호 목록(오름차순).
func story_episodes() -> Array:
	var out: Array = []
	for k in story.get("episodes", {}).keys():
		out.append(int(k))
	out.sort()
	return out

## 챕터 목록 [{no, title, from, to}].
func story_chapters() -> Array:
	return story.get("chapters", [])

## ---- 스토리 서브퀘스트(원작 `ScenarioSubQuestData` 하드코딩분) ----
## 회차의 서브퀘스트 던전 {field, night, requires?} — 없으면 {}.
## 원작 `getScenarioSubQuestFiled(sn_s, isNight)` switch. sn_s(서브 단계)가 2일 때만 유효했다.
func story_subquest_field(no: int) -> Dictionary:
	return story_subquest.get("subquest_field", {}).get(str(no), {})

## 회차의 탐험 클릭 수 — 원작 `scenairoClickCountCheck()`. 없으면 0.
func story_click_count(no: int) -> int:
	return int(story_subquest.get("click_count", {}).get(str(no), 0))

## 배틀 완료 후 다음 시나리오까지의 클릭 수 — 원작 `isBattleCountClick(sn, …)`. 없으면 0.
func story_battle_click_count(no: int) -> int:
	var t: Dictionary = story_subquest.get("battle_click_count", {})
	return int(t.get(str(no), 0))

## 월드맵 이벤트 마크를 찍을 필드 — 원작 `getEventMarkFieldValue` .rodata 표(회차 79~146).
func story_mark_field(no: int) -> int:
	return int(story_subquest.get("mark_field", {}).get(str(no), 0))

## 스토리 이벤트 전투 정의(키 = AdventureScene 이벤트 번호 26/27/29) — 원작 `getEventBattleData`.
func story_event_battle(event_no: int) -> Dictionary:
	return story_subquest.get("event_battle", {}).get(str(event_no), {})

## 회차별 **특별보상 드래곤** — 원작 `ScenarioManager::setSpecialReward` 하드코딩 3건(26·58·78화).
## {raw, dragon_no, level, rating, gems[3], gem_colors[3], skills[{no,lv}]}. 없으면 {}.
func story_special_reward(no: int) -> Dictionary:
	return story_subquest.get("special_reward", {}).get(str(no), {})

## 특별보상이 걸린 회차 목록(오름차순).
func story_special_reward_episodes() -> Array:
	var out: Array = []
	for k in story_subquest.get("special_reward", {}).keys():
		out.append(int(k))
	out.sort()
	return out

## 시나리오 번호 목록(오름차순).
func scenario_numbers() -> Array:
	var out: Array = []
	for k in scenario.get("scenarios", {}).keys():
		out.append(int(k))
	out.sort()
	return out

## 마을 NPC 이름/대사. 원작 TownNpcManager::showNpcText 가 NPC_<name>/<Name>Talk 를 조회한 것을
## build_npc_lines.py 가 stringsData_KR.xml 에서 뽑아 둔 것. 키 = 스파인 이름(sd_<key>).
func npc_lines() -> Dictionary:
	return npc_lines_doc.get("npcs", {})
