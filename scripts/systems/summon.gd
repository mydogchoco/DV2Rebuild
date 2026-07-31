class_name Summon
extends RefCounted
## 드래곤 소환(점술집) 규칙 — logic 층(CLAUDE.md §8). 화면·에셋을 모른다.
##
## 원작과의 관계
## -------------
## 원작 `TransDragonLayer` 는 **드래곤빌리지 1의 드래곤을 계정 연동으로 2로 가져오는** 기능이었다.
## 계정·서버가 전제라 §2-1(온라인 삭제) 대상이고 변환표도 서버 소유라 유실됐다.
## ⇒ 사용자 확정(2026-07-30): **기능을 바꾼다.** 보유 중인 드래곤 하나를 재료로 삼아
##    `data/dragons.json` 의 **커스텀 종(600 수비형 / 700 공격형)** 알로 변환한다.
##    원작 껍데기(소환진·받침대)는 그대로 쓰고 내용만 갈아 끼운다.
##
## 규칙(전부 사용자 확정 2026-07-30)
## ---------------------------------
##   · **기본 잠김.** 해금 플래그가 서 있을 때만 소환할 수 있다. 플래그는 나중에 추가할
##     오리지널 컨텐츠의 완료 보상으로 준다(카드 코드로도 줄 수 있다 — `CardCode` 의 flag 보상).
##   · 플래그는 **변환 실행 시점에 소비**된다(= 한 번 받을 때마다 1회).
##   · 600·700 은 **세이브당 각 1마리**가 상한. 이미 가진(또는 도감에 등록된) 종은 고를 수 없다.
##   · 600/700 중 어느 쪽이 될지는 **플레이어가 직접 고른다**(재료 드래곤과 무관).
##   · 재료 드래곤은 **소멸**한다. 변환 비용은 **없다**(트리거 자체가 대가).
##   · 결과는 알이다 — **최고 등급 고정**(`Hatchery.GRADE_MAX`) · 그 등급의 표준 부화 시간.
##     **알 강화 불가**(둥지에 직접 생기므로 인벤토리 알 `egg:<id>` 을 대상으로 하는
##     연구소 알 강화 화면에 애초에 뜨지 않는다).
##   · 커스텀 종은 `stages` 가 비어 있다 — 그림·속성·별명을 **재료 드래곤에서 물려받는다**
##     (`data/dragons.json` 600/700 의 `_player_basis`: "선택권으로 지정한 드래곤의 디자인,
##     속성, 별명을 따름").
##   · **종 이름도 재료를 따른다**(사용자 확정 2026-07-30): 마스터 `name` 은 비어 있고
##     (`name_from_player: true`) 재료 드래곤의 이름이 그대로 600·700 의 종 이름이 된다 —
##     예: 고대신룡 "별밤이"를 수비형 재료로 쓰면 600 의 종 이름이 "별밤이".
##     "재료의 이름" = 별명이 있으면 별명, 없으면 재료의 종 이름.
##     종당 1마리 상한이라 세이브당 이름이 하나로 정해진다(저장 = `UserDB.set_species_name`).
##
## ⚠️ 해금 플래그의 **이름은 빌드에 남기지 않는다**(사용자 요청 2026-07-30 — 게임 파일을 뜯어
##    트리거 조건을 미리 보는 것을 막는다). 세이브에도 코드에도 아래 해시만 존재한다.
##    평문 이름 ↔ 해시 대응은 `scripts/tools/build_card_codes.py --flag <이름>` 으로 얻는다.

## 해금 플래그의 저장 키 = sha256("dv2.flag.v1:" + 이름)[:32].
const FLAG_UNLOCK := "68c55dc64051b3eeca117e5cf77d59fe"

## 변환 결과 종 — 수비형 / 공격형. `data/dragons.json` 의 `type` 과 같은 축이다.
const SPECIES_DEF := 600
const SPECIES_ATK := 700
const SPECIES := [SPECIES_DEF, SPECIES_ATK]


## 해금됐는가. 잠겨 있으면 화면은 소환진만 보여 주고 실행을 막는다.
static func unlocked(meta_flag: bool) -> bool:
	return meta_flag


## 이 종을 아직 만들 수 있는가(세이브당 1마리 상한).
##   owned_step = UserDB.dex_step(species) — 0이면 알조차 가진 적이 없다.
static func species_available(species: int, owned_step: int) -> bool:
	return SPECIES.has(species) and owned_step <= 0


## 지금 고를 수 있는 종 목록. 둘 다 이미 있으면 빈 배열(= 소환할 것이 없다).
##   steps = {종: dex_step}
static func available_species(steps: Dictionary) -> Array:
	var out := []
	for s in SPECIES:
		if species_available(int(s), int(steps.get(s, 0))):
			out.append(s)
	return out


## 재료 자격 하한 — 🟦 사용자 확정(2026-07-30). 밸런스 노브라 여기 한 곳에서만 바꾼다.
## 소환은 재료를 **소멸**시키고 최고 등급 알을 주므로, 아무 개체나 갈아 넣지 못하게 막는다.
## ⚠️ 등급 눈금은 우리 것(`Growth.compute_grade`, 기준선 7.0)이다 — 원작 0~6 눈금이 아니다.
##    7.0 은 "모든 롤이 기준선 그대로"이고, 그 위는 부화 편차 + 초월(아모르의 축복 등)로만 오른다
##    (축복 1회 = +0.3). 10.0 = 기준선 대비 Δhp/4 + Δatt + Δdef = 30.
const MATERIAL_MIN_LEVEL := 45
const MATERIAL_MIN_GRADE := 10.0

## 재료로 쓸 수 있는 드래곤인가.
## 알·잠금(방생 잠금) 개체는 제외한다 — 방생과 같은 성격의 소멸이라 같은 가드를 쓴다.
## 이미 커스텀 종인 개체도 제외한다(600을 700으로 되굴리는 것은 상한 규칙을 우회한다).
##
## `grade` = `Growth.compute_grade` 결과. **호출측이 계산해 넘긴다** — 등급은 마스터 정의와
## 스탯표가 있어야 나오는데(§8.2) 그것들을 여기서 읽으면 logic 이 data 로더에 매이기 때문이다.
## 넘기지 않으면 기본값 -1 이라 등급 조건에서 **막힌다**(자격 검사는 열린 실패보다 닫힌 실패가 낫다).
static func can_be_material(inst: Dictionary, grade := -1.0) -> bool:
	if inst.is_empty():
		return false
	if bool(inst.get("egg", false)) or bool(inst.get("locked", false)):
		return false
	if SPECIES.has(int(inst.get("id", 0))):
		return false
	if int(inst.get("level", 0)) < MATERIAL_MIN_LEVEL:
		return false
	return grade >= MATERIAL_MIN_GRADE


## 변환 한 건의 **결과만** 산출한다(§8.3 — 상태 반영·연출은 호출측).
## 반환:
##   {} = 불가(해금 안 됐거나 종이 이미 있거나 재료가 부적격)
##   {"species", "grade", "seconds", "inherit": {"art_id", "element", "nickname", "name"}}
##     inherit = 커스텀 종이 물려받을 것. 호출측이 알 레코드에 실어 준다.
##     `name` 만 개체가 아니라 **종**에 붙는다(`UserDB.set_species_name`).
##   material_grade = `Growth.compute_grade(재료)` — 자격 하한 검사에 쓴다(위 주석 참조).
static func plan(species: int, material: Dictionary, material_master: Dictionary,
		flag: bool, owned_step: int, material_grade := -1.0) -> Dictionary:
	if not unlocked(flag):
		return {}
	if not species_available(species, owned_step):
		return {}
	if not can_be_material(material, material_grade):
		return {}
	var grade := Hatchery.GRADE_MAX
	var nick := String(material.get("nickname", ""))
	return {
		"species": species,
		"grade": grade,
		"seconds": Hatchery.hatch_seconds(grade),
		"inherit": {
			# 그림은 재료의 **아트 id**를 따른다(재료가 이미 다른 드래곤의 그림을 빌려 쓰는
			# 경우까지 그대로 물려받게 — build_dragon_art_alias.py 의 art_id 규약).
			"art_id": int(material_master.get("art_id", material.get("id", 0))),
			"element": material_master.get("element", null),
			"nickname": nick,
			# 새 **종 이름** = 재료의 이름(별명 우선, 없으면 재료의 종 이름).
			"name": nick if nick != "" else String(material_master.get("name", "")),
		},
	}
