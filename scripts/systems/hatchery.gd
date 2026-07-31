class_name Hatchery
extends RefCounted
## 부화(알) 규칙 — logic 층. 화면·에셋을 일절 모른다(CLAUDE.md §10.2).
##
## 원작 근거(디컴파일):
##   · `Dragon::getHatchTime/setHatchTime` — **알은 드래곤 레코드**로 둥지 슬롯에 들어가고
##     하나의 부화 시각을 갖는다. `CaveScene::countDownBreed/countDownBreedStart/getBreedTime`가
##     매 초 남은 시간을 갱신한다.
##   · `Dragon::getEggGrade/setEggGrade` — 알에 **초기 등급**이 붙는다.
##   · 표기 포맷 `"%02d : %02d"`(분:초) / `"%02d:%02d:%02d"`(시:분:초) — CaveScene.c 문자열.
##   · 화면: docs/ref/orig_image/cave/Screenshot_2016-05-22-02-24-05.png (받침대 위 알 + "59 : 53" +
##     스탯 ??? + 이름 앞 "+1" 배지 = **알 강화 단계** 표기).
##
## 사용자 확정 규칙(2026-07-26):
##   · 초기 등급 = 3.0~7.0 랜덤. "축복받은 둥지" 구매 시 고정 보정(값은 아래 상수).
##   · 부화 시간은 등급에 비례. 완료 시 **레벨 1**로 부화.
##   · **알 강화**(연구소)로 등급이 **확정**된다 — 위키 labwiki.pdf §2.1: 1강 7.0 / 2강 7.2 /
##     3강 7.5 (4강 8.0 은 이벤트 전용이라 강화 불가). 확정 등급은 랜덤 굴림을 **대체**한다.
##     단계는 이름 앞 "+N" 배지로 표기(원작 2016 스크린샷).
##
## ⚠️ ASSUMPTION: 등급↔시간 환산 계수는 원작 서버값이 유실됐다. 아래 상수는 튜닝 노브다.

const GRADE_MIN := 3.0
const GRADE_MAX := 7.0
# "축복받은 둥지" 고정 보정. 원작 확정(2026-07-31, 종전 임시치 +1.0 대체):
#   · 아이템 설명(items.json holynest, 원작 comment) "부화 될 모든 드래곤의 부화 능력치를
#     체력+8 공격력+2 방어력+2만큼 높여준다" → §K-10 공식(0.1×[Δhp/4+Δatt+Δdef])로 +0.6.
#   · 교차검증: CaveScene.c:3322-3326 — getNestLevel()==1 이면 성급 카운트를 rating−0.6 에서
#     멈추고 보너스를 따로 튕긴다(= 둥지 몫이 정확히 0.6).
#   · stat_bonus_for_grade 의 균등 배분(need=6 → per=2)이 원작 +8/+2/+2 를 그대로 재현한다.
const BLESSED_NEST_BONUS := 0.6

# ASSUMPTION: 등급 3.0=10분 → 7.0=60분 선형. 강화로 7.0을 넘으면 계속 늘어난다.
const SEC_AT_MIN := 600
const SEC_PER_GRADE := 750


## 알의 초기 등급을 굴린다. blessed=축복받은 둥지 보유 시 +BLESSED_NEST_BONUS.
## u = [0,1) 균등난수(호출측이 RNG 오토로드에서 뽑아 넘긴다 — 규칙층은 순수 함수로 유지).
static func roll_grade(u: float, blessed := false) -> float:
	var g := GRADE_MIN + clampf(u, 0.0, 0.9999) * (GRADE_MAX - GRADE_MIN)
	if blessed:
		g += BLESSED_NEST_BONUS
	return snappedf(g, 0.1)


## 부화시킬 알 하나의 초기 등급. **강화 단계(step)가 있으면 확정 등급**(위키), 없으면 랜덤 굴림.
##   step     : 연구소 알 강화 단계(0=미강화)
##   egg_cfg  : data/laboratory.json 의 `egg_upgrade` 블록(grades 표)
## 축복받은 둥지는 확정 등급 **위에도** 더한다 — 원작 설명이 "부화 될 **모든** 드래곤"이다
##    (items.json holynest desc). 강화 알만 예외로 뺄 근거가 없다.
static func grade_for(step: int, egg_cfg: Dictionary, u: float, blessed := false) -> float:
	var fixed := EggUpgrade.hatch_grade(maxi(0, step), egg_cfg)
	if fixed <= 0.0:
		return roll_grade(u, blessed)
	return snappedf(fixed + (BLESSED_NEST_BONUS if blessed else 0.0), 0.1)


## 이미 정해진 등급에 축복받은 둥지 보정을 얹는다 — 원작 설명이 "부화 될 **모든** 드래곤"
## 이므로 굴림(roll_grade)·강화 확정(grade_for) 밖의 부화 경로(소환 알, 교배 부화)도 이걸 쓴다.
static func bless(grade: float, blessed: bool) -> float:
	return snappedf(grade + (BLESSED_NEST_BONUS if blessed else 0.0), 0.1)


## 등급에 비례하는 부화 소요 시간(초).
static func hatch_seconds(grade: float) -> int:
	return int(round(SEC_AT_MIN + maxf(0.0, grade - GRADE_MIN) * SEC_PER_GRADE))


## 남은 초 → 원작 표기. 1시간 미만은 "MM : SS", 이상은 "H:MM:SS".
static func format_remain(sec: int) -> String:
	sec = maxi(0, sec)
	# 원작 `CaveScene::countDownFatigue` 의 포맷 두 종 그대로 — **콜론 양옆에 공백이 있다**
	# (레퍼런스 docs/ref/egg/타이머UI.png 의 "39 : 59 : 57").
	if sec < 3600:
		return "%02d : %02d" % [sec / 60, sec % 60]
	return "%02d : %02d : %02d" % [sec / 3600, (sec % 3600) / 60, sec % 60]


## 같은 시간의 **공백 없는** 표기. 원작 `onClickFatigue` 가 다이아 즉시부화 확인 문구
## (`CaveDiaBronMsg1` 의 `%1$s`)에만 쓰는 별도 포맷(`"%02d:%02d"` / `"%02d:%02d:%02d"`)이다.
static func format_remain_compact(sec: int) -> String:
	sec = maxi(0, sec)
	if sec < 3600:
		return "%02d:%02d" % [sec / 60, sec % 60]
	return "%02d:%02d:%02d" % [sec / 3600, (sec % 3600) / 60, sec % 60]


## 목표 등급이 나오도록 stat_bonus를 역산한다.
## Growth.compute_grade = BASE_GRADE + 0.1*(hp/4 + att + def) 의 역함수(세 스탯에 균등 배분).
static func stat_bonus_for_grade(grade: float) -> Dictionary:
	var need := (grade - Growth.BASE_GRADE) / 0.1     # hp/4 + att + def 합
	var per := need / 3.0
	return {
		"base": {"hp": snappedf(per * 4.0, 0.01), "att": snappedf(per, 0.01), "def": snappedf(per, 0.01)},
		"growth": {"hp": 0.0, "att": 0.0, "def": 0.0},
	}
