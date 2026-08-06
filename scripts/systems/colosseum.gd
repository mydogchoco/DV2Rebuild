class_name Colosseum
## 콜로세움(솔로잉 재설계) — 순수 로직.
##
## 🟦 사용자 확정 2026-08-04. 원작 콜로세움은 PvP 라 CLAUDE.md §2-1 에서 CUT 이었으나,
## **상대를 봇으로만 채운 솔로 콜로세움**으로 되살린다. 네트워크 코드는 없다.
## 설계 전문 = docs/ref/porting/Colosseum.md · 데이터 = data/colosseum.json(build_colosseum.py).
##
## §8 계층: 여기는 logic 이다 — 노드·씬·프레임을 모른다. 티어 프레임 **경로 문자열**만
## data 에서 꺼내 주고, 실제 로드는 render(`scripts/ui/colosseum.gd`)가 한다.
##
## 전투 판정은 만들지 않는다 — 기존 `Battle.simulate(party_a, party_b, …)` 가 이미 대칭이라
## 드래곤 vs 드래곤에 그대로 쓴다(scripts/systems/battle.gd:1395).
##
## 원작 대응:
##   상대 목록  ColosseumScene::_responseList @00f4ca90 의 `match1_list`/`match3_list`
##   레이팅     같은 응답의 `single`(1vs1) / `tournament`(3vs3)
##   연승       `straight_single` / `straight_team` (+ `_best`)
##   입장권     `energy` + ColosseumBattleInfo::updateStamina
##   티어       StrategyManager::GetTier @0170f130 (경계값 원작 채굴 — 유실 아님)

const PMETA_KEY := "colosseum"

# 봇 uid 는 UserDB 와 절대 겹치면 안 된다(UserDB 는 1부터 증가).
const BOT_UID_BASE := 900000


# --- 상태(세이브) -----------------------------------------------------------
#
# 원작 `_responseList` 의 키 이름을 그대로 쓴다 — 나중에 원작 로그와 대조하기 쉽도록.

static func _default_state() -> Dictionary:
	var start := int(_cfg().get("rating", {}).get("start", 1000))
	return {
		"single": start, "tournament": start,          # 모드별 레이팅
		"straight_single": 0, "straight_team": 0,       # 연승
		"straight_single_best": 0, "straight_team_best": 0,
		"energy": int(_cfg().get("ticket", {}).get("max", 10)),
		"energy_at": 0,                                 # 마지막 회복 계산 시각(Unix)
		# 🟦 사용자 확정 2026-08-06 — 방지봇은 **문턱당 딱 한 판**만 나온다. 그래서 남은 횟수를
		#   세는 카운터(옛 `guard_left`)가 아니라 **이미 붙어 본 문턱**을 모드별로 적어 둔다
		#   {모드: [25, 50…]}. 카운터는 한 번이라도 차감을 놓치면 방지봇이 눌러앉지만,
		#   이 형태는 같은 문턱에서 두 번 나올 수가 없다(연승이 끊기면 그 모드 기록을 비운다).
		"guard_served": {},
		"guard_met": {},                                # 방지봇별 조우 횟수 {키: N} — 대사 최초/반복 판정
		"tier_paid": [],                                # 승급 보너스를 이미 받은 티어 id 들

		"history": [],                                  # 최근 전적 (원작 last_record)
		"popup_welcome": false,
	}


static func _cfg() -> Dictionary:
	return Data.colosseum


static func state() -> Dictionary:
	var s: Dictionary = UserDB.get_pmeta(PMETA_KEY, {})
	var d := _default_state()
	if s.is_empty():
		return d
	# 스키마가 늘어나도 기존 세이브가 깨지지 않게 기본값 위에 덮는다.
	for k in s:
		d[k] = s[k]
	# 옛 세이브 마이그레이션 — `guard_left`(카운트다운) 시절엔 `guard_served` 가 없다.
	#   지금 연승에서 이미 지나온 문턱은 **붙어 본 것으로 친다**(안 그러면 32연승 세이브가
	#   다음 판에 25문턱 방지봇을 다시 만난다).
	if not s.has("guard_served"):
		d["guard_served"] = _served_from_streaks(d)
	d.erase("guard_left")
	return d


## 마이그레이션 전용 — 모드별 현재 연승으로 "이미 지나온 문턱" 목록을 만든다.
static func _served_from_streaks(s: Dictionary) -> Dictionary:
	var out := {}
	for mode in (_cfg().get("modes", {}) as Dictionary):
		var sk := String((mode_cfg(String(mode))).get("streak_key", ""))
		var streak := int(s.get(sk, 0))
		var done: Array = []
		for g: Dictionary in (_cfg().get("guards", []) as Array):
			var at := int(g.get("streak_at", 0))
			if at <= streak:
				done.append(at)
		if not done.is_empty():
			out[String(mode)] = done
	return out


static func save_state(s: Dictionary) -> void:
	UserDB.set_pmeta(PMETA_KEY, s)


## 모드 설정. mode = "single"(1vs1) | "team"(3vs3).
static func mode_cfg(mode: String) -> Dictionary:
	return (_cfg().get("modes", {}) as Dictionary).get(mode, {})


static func party_size(mode: String) -> int:
	return int(mode_cfg(mode).get("party", 3))


## 출전 자격 — 원작 입장 조건은 **레벨 25 이상**이다
## (`ColosseumInError` "테이머 자격증 이벤트를 완수하셔야 입장할 수 있습니다. (레벨 25)").
## ⚫ 테이머 자격증 이벤트는 서버 이벤트라 CUT — 레벨 조건만 적용한다.
## 이게 곧 **성체 조건**이기도 하다: 공격 모션이 성체 스파인에만 있다(fight.gd 주석).
static func min_level() -> int:
	return int(_cfg().get("entry", {}).get("min_level", 25))


## 그 드래곤이 콜로세움에 나갈 수 있나.
static func eligible(uid: int) -> bool:
	var d := UserDB.get_dragon(uid)
	return not d.is_empty() and int(d.get("level", 1)) >= min_level()


## 출전 가능한 보유 드래곤 uid 목록(편성창에 넘길 후보).
static func eligible_uids() -> Array:
	var out: Array = []
	for d in UserDB.dragons():
		if int((d as Dictionary).get("level", 1)) >= min_level():
			out.append(int((d as Dictionary).get("uid", 0)))
	return out


static func rating_of(mode: String) -> int:
	return int(state().get(String(mode_cfg(mode).get("rating_key", "tournament")), 0))


static func streak_of(mode: String) -> int:
	return int(state().get(String(mode_cfg(mode).get("streak_key", "straight_team")), 0))


# --- 티어 -------------------------------------------------------------------
#
# 경계값은 원작 `StrategyManager::GetTier` 하드코딩 그대로다(자작 아님).

## 레이팅 → 티어 dict {id,key,name,min_rating}. 표가 비면 {}.
static func tier_of(rating: int) -> Dictionary:
	var list: Array = (_cfg().get("tier", {}) as Dictionary).get("list", [])
	var best: Dictionary = {}
	for t: Dictionary in list:
		if rating >= int(t.get("min_rating", 0)):
			if best.is_empty() or int(t["min_rating"]) >= int(best["min_rating"]):
				best = t
	return best


## 티어 프레임 경로. kind = "border"|"dragon"|"icon"|"header".
## render 층이 로드한다 — logic 은 경로 문자열만 만든다(§8.4 에셋 카탈로그).
static func tier_frame(rating: int, kind: String) -> String:
	var t := tier_of(rating)
	if t.is_empty():
		return ""
	var pat := String((_cfg().get("tier", {}) as Dictionary).get("frames", {}).get(kind, ""))
	if pat == "":
		return ""
	# DIAMOND 는 원작 규칙엔 있으나 아이콘이 추출 에셋에 없다 → 표시만 대체(§10).
	var key := String(t.get("icon_fallback", "")) if String(t.get("icon_fallback", "")) != "" \
		else String(t.get("key", ""))
	return pat % key


## 다음 티어까지 남은 레이팅(최상위면 0).
static func to_next_tier(rating: int) -> int:
	var list: Array = (_cfg().get("tier", {}) as Dictionary).get("list", [])
	var nxt := -1
	for t: Dictionary in list:
		var m := int(t.get("min_rating", 0))
		if m > rating and (nxt < 0 or m < nxt):
			nxt = m
	return 0 if nxt < 0 else nxt - rating


# --- 레이팅 증감 -------------------------------------------------------------
#
# ⚠️ ASSUMPTION — 원작은 서버가 증감치를 내려줬다(getDuelBaseRankPoint/getDuelAddRankPoint 는
#   서버가 채운 vector 를 읽는 게터다). 아래 수치는 data/colosseum.json `rating` 노브.

## 이번 판의 레이팅 증감. `streak` = 이 판 **이전까지의** 연승.
static func rating_delta(win: bool, streak: int, rating: int) -> int:
	var r: Dictionary = _cfg().get("rating", {})
	if win:
		var bonus := mini(int(r.get("streak_bonus_per", 0)) * maxi(0, streak),
			int(r.get("streak_bonus_max", 0)))
		return int(r.get("win", 0)) + bonus
	var t := tier_of(rating)
	var mult := float((r.get("lose_mult_by_tier", {}) as Dictionary).get(
		str(int(t.get("id", 3))), 1.0))
	return int(round(float(int(r.get("lose", 0))) * mult))


## 전투 결과를 상태에 반영한다. 반환 = 연출에 필요한 요약
## {delta, rating_before, rating_after, tier_before, tier_after, tier_up, tier_down, streak, best,
##  unlocked} — `unlocked` 는 이 판으로 해금 보상이 열렸을 때만 true(화면이 안내를 띄운다).
## `foe` = 이번 상대(`roll_match`/`make_guard` 결과). 해금 판정에 쓴다.
static func apply_result(mode: String, win: bool, opponent_nick := "",
		foe: Dictionary = {}) -> Dictionary:
	var s := state()
	var mc := mode_cfg(mode)
	var rk := String(mc.get("rating_key", "tournament"))
	var sk := String(mc.get("streak_key", "straight_team"))
	var bk := sk + "_best"

	var before := int(s.get(rk, 0))
	var streak := int(s.get(sk, 0))
	var delta := rating_delta(win, streak, before)
	var after := maxi(int(_cfg().get("rating", {}).get("min", 0)), before + delta)

	var t_before := tier_of(before)
	var t_after := tier_of(after)

	s[rk] = after
	s[sk] = streak + 1 if win else 0
	s[bk] = maxi(int(s.get(bk, 0)), int(s[sk]))

	# 연승방지 — 등장 판정은 여기서 하지 않는다. `pending_guard()` 가 **연승 수만 보고**
	#   "이 문턱을 아직 안 붙어 봤으면 나온다"로 정한다(문턱당 1판).
	#
	# 🔴 2026-08-06 정정: 종전엔 여기서 `guard_left = guard_repeat(3)` 을 무장했다. 그래서
	#   ① 25연승 뒤 **세 판 연속** 방지봇이 나오고(사용자 규칙은 1회),
	#   ② 차감(`consume_guard`)을 한 번이라도 못 타는 경로가 있으면 방지봇이 눌러앉았다.
	#   지금 하는 일은 하나뿐 — **연승이 끊기면 그 모드의 문턱 기록을 비운다**(다시 쌓으면 또 만난다).
	if not win:
		var srv: Dictionary = (s.get("guard_served", {}) as Dictionary).duplicate()
		srv.erase(mode)
		s["guard_served"] = srv

	var hist: Array = (s.get("history", []) as Array).duplicate()
	hist.push_front({"mode": mode, "win": win, "delta": delta, "foe": opponent_nick})
	while hist.size() > 20:
		hist.pop_back()
	s["history"] = hist

	# 주화 — 판당 지급 + 최초 승급 보너스. `streak` 은 이 판 **이전까지의** 연승이라
	# 레이팅 보너스와 같은 값을 본다(첫 승은 보너스 0).
	var coin := match_coin(mode, win, streak)
	var tier_bonus := 0
	if int(t_after.get("id", 0)) > int(t_before.get("id", 0)):
		var paid: Array = (s.get("tier_paid", []) as Array).duplicate()
		var tid := int(t_after.get("id", 0))
		if not paid.has(tid):
			tier_bonus = int((_cfg().get("coin", {}).get("tier_up", {}) as Dictionary)
				.get(str(tid), 0))
			paid.append(tid)
			s["tier_paid"] = paid
	save_state(s)
	var total_coin := coin + tier_bonus
	if total_coin > 0:
		UserDB.add_item(coin_key(), total_coin)

	var unlocked := _grant_unlock(win, foe)

	return {
		"delta": delta, "rating_before": before, "rating_after": after,
		"tier_before": t_before, "tier_after": t_after,
		# id = ColosseumProfile::getRatingBorder 의 case 번호(0 BRONZE … 5 MASTER) — **클수록 높다**.
		# 🔴 2026-08-04: 종전엔 StrategyManager 규약(작을수록 높다)이라 부호가 반대였다.
		"tier_up": int(t_after.get("id", 0)) > int(t_before.get("id", 0)),
		"tier_down": int(t_after.get("id", 0)) < int(t_before.get("id", 0)),
		"streak": int(s[sk]), "best": int(s[bk]),
		"coin": coin, "coin_tier_bonus": tier_bonus,
		"unlocked": unlocked,
	}


# --- 주화(재화) ---------------------------------------------------------------
#
# 원작 재화 `Colosseum_Coin` "콜로세움 주화". 원작은 **일일/주간 보상으로만** 줬고
# (`claim_rewards`), 판당 지급은 없었다 → 🟦 사용자 확정 2026-08-06 으로 새로 낸 수도꼭지다.
# 표 = `data/colosseum.json` `coin.per_match` / `coin.tier_up`(전부 `_authored`).

## 주화의 인벤 키(`data/items.json` `colosseum_coin`).
static func coin_key() -> String:
	return String((_cfg().get("coin", {}) as Dictionary).get("key", "colosseum_coin"))


## 보유 주화.
static func coin() -> int:
	return UserDB.item_count(coin_key())


## 이번 판이 주는 주화. `streak` = 이 판 **이전까지의** 연승(승리일 때만 보너스가 붙는다).
static func match_coin(mode: String, win: bool, streak: int) -> int:
	var pm: Dictionary = (_cfg().get("coin", {}) as Dictionary).get("per_match", {})
	if pm.is_empty():
		return 0
	var base := int(pm.get("win", 0)) if win else int(pm.get("lose", 0))
	if win:
		base += mini(int(pm.get("streak_bonus_per", 0)) * maxi(0, streak),
			int(pm.get("streak_bonus_max", 0)))
	var mult := float((pm.get("mode_mult", {}) as Dictionary).get(mode, 1.0))
	return int(round(float(base) * mult))


# --- 오리지널 컨텐츠 보상 ----------------------------------------------------
#
# 🟦 사용자 확정 2026-08-05 — **999연승을 채우면 1000번째 판에 선대군이 확정 등장하고,
#   그 판에서 패배하는 것**이 조건이다. 선대군의 대사가 그대로 그 규칙이다
#   ("아쉽게도 연승은 여기까지입니다 … 대결이 끝나면 점술집으로 가 보시겠어요?").
#   등장 자체는 이미 스케줄(999)이 보장한다 — 여기서는 **패배**만 본다.
#
#   🟦 2026-08-06 갱신 — 선대군도 **문턱당 1회**다(예외 없음, `pending_guard`). 그 한 판을
#   이겨 버리면 해금은 이번 연승에서 끝이고, 다시 받으려면 연승을 끊고 999를 다시 쌓아야 한다.
#   사용자 확정: 아무리 강한 덱이어도 **약한 드래곤을 대신 출전시켜 일부러 질 수 있으므로**
#   해금이 막히지 않는다.
const UNLOCK_GUARD_KEY := "sundaegun"

## 이 판의 결과로 해금 보상이 열렸으면 true(이미 열려 있었으면 false).
static func _grant_unlock(win: bool, foe: Dictionary) -> bool:
	if win or not bool(foe.get("guard", false)):
		return false
	if String(foe.get("guard_key", "")) != UNLOCK_GUARD_KEY:
		return false
	if bool(UserDB.get_pmeta(Summon.FLAG_UNLOCK, false)):
		return false
	UserDB.set_pmeta(Summon.FLAG_UNLOCK, true)
	return true


# --- 입장권 -----------------------------------------------------------------
#
# 원작 `energy` + `ColosseumBattleInfo::updateStamina` 의 "마지막 시각부터 경과분을 회복" 구조.

## 경과 시간만큼 회복시킨 상태를 반환(저장까지 한다).
static func refresh_ticket(now_unix: int = -1) -> Dictionary:
	var s := state()
	var tc: Dictionary = _cfg().get("ticket", {})
	var mx := int(tc.get("max", 10))
	var per := maxi(1, int(tc.get("recover_seconds", 600)))
	var now := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	var last := int(s.get("energy_at", 0))
	if last <= 0:
		s["energy_at"] = now
		save_state(s)
		return s
	var have := int(s.get("energy", 0))
	if have >= mx:
		s["energy_at"] = now
		save_state(s)
		return s
	var gained := int((now - last) / per)
	if gained > 0:
		s["energy"] = mini(mx, have + gained)
		s["energy_at"] = last + gained * per
		save_state(s)
	return s


static func can_enter() -> bool:
	return int(refresh_ticket().get("energy", 0)) >= int(_cfg().get("ticket", {}).get("cost_per_match", 1))


## 입장권 상한.
static func ticket_max() -> int:
	return int(_cfg().get("ticket", {}).get("max", 10))


## 입장권을 n 회복시킨다. 반환 = **실제로 채워진 양**(이미 만땅이면 0).
##
## 원작은 피로도를 **다이아 1개**로 1 충전했다(`_orig_rules.stamina`). 오프라인에서는
## 자양강장제(items.json `drink`)가 그 자리를 잇는다 — 원작 설명문이 "피로를 풀어주는"
## 이고, 우리는 탐험 피로도를 삭제했으므로(§K-7) 남은 피로도는 콜로세움 것뿐이다.
static func add_ticket(n := 1) -> int:
	if n <= 0:
		return 0
	var s := refresh_ticket()            # 먼저 경과분을 반영해야 상한 판정이 맞다
	var mx := ticket_max()
	var have := int(s.get("energy", 0))
	if have >= mx:
		return 0
	var got := mini(n, mx - have)
	s["energy"] = have + got
	save_state(s)
	return got


## 입장권 1회 소모. 부족하면 false.
static func spend_ticket() -> bool:
	var s := refresh_ticket()
	var cost := int(_cfg().get("ticket", {}).get("cost_per_match", 1))
	if int(s.get("energy", 0)) < cost:
		return false
	s["energy"] = int(s["energy"]) - cost
	save_state(s)
	return true


# --- 상대 목록 새로고침 ------------------------------------------------------
#
# 원작은 **골드**를 받는다(`Colosseum_Refresh_Msg` "새로고침에는 %1$d 골드가 필요합니다").
# `Colosseum_Error_2` 가 "무료 갱신 제공"을 말하므로 하루 몇 회는 무료로 둔다.
# 금액·무료 횟수는 서버 유실 → data/colosseum.json `refresh` 노브.

static func _today() -> int:
	return int(Time.get_unix_time_from_system() / 86400)


## 이번 새로고침이 무료인가(하루 free_per_day 회).
static func refresh_is_free() -> bool:
	var s := state()
	var cfg: Dictionary = _cfg().get("refresh", {})
	if int(s.get("refresh_day", -1)) != _today():
		return true
	return int(s.get("refresh_used", 0)) < int(cfg.get("free_per_day", 0))


static func refresh_cost() -> int:
	return 0 if refresh_is_free() else int(_cfg().get("refresh", {}).get("gold", 0))


## 새로고침 1회 지불. 골드가 모자라면 false(호출측이 `Colosseum_Refresh_Error` 를 낸다).
static func pay_refresh() -> bool:
	var s := state()
	if int(s.get("refresh_day", -1)) != _today():
		s["refresh_day"] = _today()
		s["refresh_used"] = 0
	var cost := 0
	if int(s.get("refresh_used", 0)) >= int(_cfg().get("refresh", {}).get("free_per_day", 0)):
		cost = int(_cfg().get("refresh", {}).get("gold", 0))
	if cost > 0:
		if not UserDB.spend("gold", cost):
			return false
	s["refresh_used"] = int(s.get("refresh_used", 0)) + 1
	save_state(s)
	return true


# --- 일일/주간 보상 ----------------------------------------------------------
#
# 원작: 일일·주간 보상이 **다이아 + 콜로세움 주화**를 우편함으로 지급한다
# (`Colosseum_Daily_Result_1/2` · `Colosseum_Weekly_Result_1/2` · 재화명 `Colosseum_Coin`).
# ⚫ 우편함은 온라인이라 CUT → 즉시 지급한다. 지급량은 서버 유실 → `coin.daily/weekly` 노브.

## 아직 안 받은 일일/주간 보상을 지급한다. 반환 = [{kind, dia, coin}] (연출용, 없으면 빈 배열).
static func claim_rewards() -> Array:
	var s := state()
	var cfg: Dictionary = _cfg().get("coin", {})
	if cfg.is_empty():
		return []
	var out: Array = []
	var day := _today()
	var week := int(day / 7)
	# 티어는 3vs3 레이팅 기준(원작 주간결과도 모드별이지만 우리는 대표 하나로 준다).
	var tier := tier_of(rating_of("team"))
	var tk := str(int(tier.get("id", 0)))
	for pair in [["daily", "reward_day", day], ["weekly", "reward_week", week]]:
		var kind := String(pair[0])
		var key := String(pair[1])
		var now := int(pair[2])
		if int(s.get(key, -1)) == now:
			continue
		var r: Dictionary = (cfg.get(kind, {}) as Dictionary).get(tk, {})
		if r.is_empty():
			continue
		var dia := int(r.get("dia", 0))
		var coin := int(r.get("coin", 0))
		if dia > 0:
			UserDB.add_currency("diamond", dia)
		if coin > 0:
			UserDB.add_item(String(cfg.get("key", "colosseum_coin")), coin)
		s[key] = now
		out.append({"kind": kind, "dia": dia, "coin": coin})
	if not out.is_empty():
		save_state(s)
	return out


# --- 닉네임 생성 -------------------------------------------------------------
#
# 원작엔 생성기가 없다 — 상대가 실유저라 닉이 서버 소유였다(심볼 전수: Bot/RandomName 0건,
# NickNameLayer·ChatNickPopup 은 **유저 본인** 닉 입력 UI). 그래서 새로 만든다.
# 조각 풀 = data/colosseum.json `nick`(docs/input/sheets/colosseum_nick.csv 로 교체 가능).

static func gen_nick(rng: RandomNumberGenerator) -> String:
	var n: Dictionary = _cfg().get("nick", {})
	var pre: Array = n.get("prefix", [])
	var noun: Array = n.get("noun", [])
	var suf: Array = n.get("suffix", [])
	if noun.is_empty():
		return "도전자%d" % (rng.randi() % 9000 + 1000)
	var s := ""
	# 수식어는 70% 확률로만 붙인다 — 전부 붙으면 목록이 균질해 보인다.
	if not pre.is_empty() and rng.randf() < 0.7:
		s += String(pre[rng.randi() % pre.size()])
	s += String(noun[rng.randi() % noun.size()])
	if not suf.is_empty():
		s += String(suf[rng.randi() % suf.size()])
	return s


## 중복 없는 닉 n 개. 조각 풀이 작아도 무한루프에 빠지지 않게 시도 상한을 둔다.
static func gen_nicks(count: int, rng: RandomNumberGenerator, taken: Array = []) -> Array:
	var seen := {}
	for t in taken:
		seen[String(t)] = true
	var out: Array = []
	var guard := count * 40 + 50
	while out.size() < count and guard > 0:
		guard -= 1
		var nk := gen_nick(rng)
		if seen.has(nk):
			continue
		seen[nk] = true
		out.append(nk)
	while out.size() < count:                       # 풀 고갈 — 번호로 강제 분리
		out.append("도전자%d" % (rng.randi() % 9000 + 1000))
	return out


# --- 봇 생성 -----------------------------------------------------------------
#
# 핵심 규칙: 봇 드래곤은 **UserDB 레코드와 같은 모양의 dict** 다. 그래야
# `PartyStats.resolve()` 가 플레이어와 **같은 경로**로 젬·장비·팀버프·각성을 계산한다.
# 봇 전용 밸런스 코드는 없다.

## 봇 1기의 드래곤 레코드 1건.
static func _make_bot_dragon(id: int, uid: int, spec: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var ddef := Data.get_dragon(id)
	var level := int(spec.get("level", 50))
	var awakened := bool(spec.get("awakened", false))

	var d := {
		"id": id, "uid": uid, "level": level,
		"exp": 0, "awakened": awakened, "awaken_skill": 0,
		"stat_bonus": {"base": {"hp": 0, "att": 0, "def": 0},
					   "growth": {"hp": 0, "att": 0, "def": 0}},
		"gain_log": _gain_log_for(ddef, level),
		"gems": {"types": Gem.random_types(Data.gems, rng), "slots": [null, null, null]},
		"equip": {"slots": []},
		"skills": [],
		"skill_slots": Loadout.random_slot_types(rng),   # 칸 타입(tri/sq/cir/star)
		"skill_equip": [],                               # 실제로 낀 스킬 id
		"cure_time": 0, "drink_buffs": {},
	}
	if awakened:
		d["awaken_skill"] = Data.awaken_skill_of(id)
	# 🟦 연승방지봇(이벤트성 매치)은 구성을 **시트가 전부 정한다** — 굴리지 않는다.
	#   안 적힌 칸은 비운 채로 두고 `_apply_guard_spec` 이 적힌 것만 채운다.
	#   (랜덤 에픽 장비가 붙으면 저작한 스탯·연출 의도가 무너진다.)
	if not bool(spec.get("no_roll", false)):
		d["gems"] = _roll_gems(d["gems"], spec.get("gem", {}), rng)
		d["equip"] = _roll_equip(spec.get("equip", {}), rng, id)
		d["skills"] = _roll_skills(spec.get("skill", {}), rng)
	# 학습 풀과 장착 칸은 별개다(§ Loadout) — 배운 것을 열린 칸에 그대로 낀다.
	var eq: Array = []
	for i in Loadout.SKILL_SLOTS:
		if i < d["skills"].size() and Loadout.slot_unlocked(i, level):
			eq.append(int((d["skills"][i] as Dictionary).get("id", 0)))
		else:
			eq.append(0)
	d["skill_equip"] = eq
	return d


## 레벨 L 짜리 성장 이력. UserDB._backfill_gain_log 와 같은 방식(불변식 level == 1+size).
static func _gain_log_for(ddef: Dictionary, level: int) -> Array:
	if level <= 1:
		return []
	var g := Growth.tier_growth(ddef, Data.stat_table)
	if g.is_empty():
		return []
	var per := {"hp": int(g.get("hp", 0)), "att": int(g.get("att", 0)), "def": int(g.get("def", 0))}
	var out: Array = []
	for _i in level - 1:
		out.append(per.duplicate())
	return out


## 젬 3칸. 칸마다 슬롯 타입 제약(Gem.accepts)을 지키는 젬 중에서 고른다.
static func _roll_gems(gems_field: Dictionary, rule: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var cats: Array = rule.get("categories", ["normal", "hybrid", "soul"])
	var want_tier := int(rule.get("tier", -1)) if typeof(rule.get("tier")) != TYPE_STRING else -2
	var names: Array = []
	for k in Data.gems.get("gems", {}):
		var gd: Dictionary = Data.gems["gems"][k]
		if cats.has(String(gd.get("category", ""))):
			names.append(String(k))
	if names.is_empty():
		return gems_field
	var out := gems_field
	for slot in 3:
		var ty := String(Gem.types(out)[slot])
		# 이 칸이 받아 주는 젬만 후보로.
		var fit: Array = []
		for nm: String in names:
			if Gem.accepts(ty, nm, Data.gems):
				fit.append(nm)
		if fit.is_empty():
			continue
		var pick := String(fit[rng.randi() % fit.size()])
		var mx := Gem.max_tier(pick, Data.gems)
		var tier := mx if want_tier < 0 else mini(want_tier, mx)
		if want_tier == -2:                              # "random"
			tier = rng.randi_range(0, maxi(0, mx))
		var next := Gem.equip_at(out, slot, pick, tier, Data.gems)
		if not next.is_empty():
			out = next
	return out


## 장비 4칸(모든/전투형/보조형/아티팩트). 등급 범위 안에서 굴린다.
static func _roll_equip(rule: Dictionary, rng: RandomNumberGenerator, dragon_id: int) -> Dictionary:
	var field := {"slots": []}
	var cat := Equipment.catalog(Data.equipment)
	if cat.is_empty():
		return field
	var gmin := int(rule.get("grade_min", 0))
	var gmax := int(rule.get("grade_max", 5))
	for slot_id: String in Equipment.slot_ids(true):
		# 그 칸에 낄 수 있고, 종족 제한(전용 장비)에 걸리지 않는 것만.
		var fit: Array = []
		for key: String in cat:
			var item: Dictionary = cat[key]
			if Equipment.can_equip(item, slot_id) and Equipment.species_allows(item, dragon_id):
				fit.append(key)
		if fit.is_empty():
			continue
		var key2 := String(fit[rng.randi() % fit.size()])
		var grade := rng.randi_range(gmin, maxi(gmin, gmax))
		var meta := {"rarity": grade, "options": Equipment.roll_options(grade, rng, Data.equipment)}
		var next := Equipment.equip(field, slot_id, key2, Data.equipment, meta, dragon_id)
		if not next.is_empty():
			field = next
	return field


## 장착 스킬. 원작 슬롯은 2칸(§ dv2-slot-systems) — 모양 제약 없이 낀다.
static func _roll_skills(rule: Dictionary, rng: RandomNumberGenerator) -> Array:
	var pool := Loadout.usable_pool(Data.skills)
	if pool.is_empty():
		return []
	var want := mini(int(rule.get("count", 2)), pool.size())
	var lo := int(rule.get("level_min", 1))
	var hi := maxi(lo, int(rule.get("level_max", 5)))
	var picked := {}
	var out: Array = []
	var guard := want * 20 + 20
	while out.size() < want and guard > 0:
		guard -= 1
		var sid := int(pool[rng.randi() % pool.size()])
		if picked.has(sid):
			continue
		picked[sid] = true
		out.append({"id": sid, "level": rng.randi_range(lo, hi)})
	return out


## 봇 1기 완성 — {nick, grade, tier, rating, dragons:[레코드…]}.
static func make_bot(grade_key: String, mode: String, rating: int,
		rng: RandomNumberGenerator, nick := "") -> Dictionary:
	var spec: Dictionary = (_cfg().get("bots", {}) as Dictionary).get("grades", {}).get(grade_key, {})
	var n := party_size(mode)
	var ids := _dragon_pool()
	var dragons: Array = []
	var used := {}
	for i in n:
		if ids.is_empty():
			break
		var id := 0
		# 같은 봇 안에서 같은 종이 겹치지 않게(팀버프가 이상해진다).
		for _try in 20:
			id = int(ids[rng.randi() % ids.size()])
			if not used.has(id):
				break
		used[id] = true
		dragons.append(_make_bot_dragon(id, BOT_UID_BASE + rng.randi() % 90000, spec, rng))
	return {
		"nick": nick if nick != "" else gen_nick(rng),
		"grade": grade_key, "rating": rating,
		"tier": tier_of(rating), "dragons": dragons, "bot": true,
	}


## 봇으로 쓸 수 있는 드래곤 도감 id.
##
## 자체 필터를 짜지 않는다 — `Data.dragon_ids_random()` 이 이미 "무작위 입수 풀"의 단일 기준이고
## (도감 숨김 + 지정 획득처 전용 600/700/666/777 제외), 봇도 같은 기준을 따라야 한다.
static func _dragon_pool() -> Array:
	return Data.dragon_ids_random()


## 랭커 CSV 1행 → 봇. 빈 칸은 랭커 분류의 폴백 규칙으로 채운다.
##
## `authored` = 연승방지봇처럼 **시트가 구성을 전부 정한 상대**. 이때는 랜덤 굴림을 끄고
## 시트에 적힌 것만 채운다(안 적은 칸 = 없음). 랭커는 종전대로 빈 칸을 굴린다.
static func _make_ranker(rec: Dictionary, mode: String, rng: RandomNumberGenerator,
		authored := false) -> Dictionary:
	var spec: Dictionary = (_cfg().get("bots", {}) as Dictionary).get("grades", {}).get("ranker", {})
	var n := party_size(mode)
	var src: Array = _pick_roster(rec.get("dragons", []), n, rng, authored)
	var dragons: Array = []
	for i in n:
		if i < src.size():
			var r: Dictionary = src[i]
			var sp := spec.duplicate(true)
			sp["level"] = int(r.get("level", spec.get("level", 50)))
			sp["awakened"] = bool(r.get("awakened", spec.get("awakened", true)))
			sp["no_roll"] = authored
			var bd := _make_bot_dragon(int(r.get("id", 0)),
				BOT_UID_BASE + 500000 + i, sp, rng)
			_apply_sheet_spec(bd, r, rng)
			dragons.append(bd)
		elif not src.is_empty():
			break                                   # CSV 가 지정한 수만큼만
	var rating := int(rec.get("rating", 0))
	if rating <= 0:
		rating = _tier_mid_rating(String(rec.get("tier", "master")))
	return {
		"nick": String(rec.get("nick", "")), "grade": "ranker", "rating": rating,
		"tier": tier_of(rating), "dragons": dragons, "bot": true, "ranker": true,
	}


## 시트가 적어 준 드래곤 중 이번 판에 나올 `n`마리.
##
## 랭커 시트는 한 사람이 **3~4마리**를 적을 수 있고(실제로 제라드빠텐더·청의대장군이 4마리),
## 1vs1 은 1마리만 쓴다. 항상 앞에서 자르면 4번째는 영영 안 나오고 1vs1 은 늘 같은 드래곤이
## 나오므로, **적어 둔 명단에서 골라** 쓴다(시트 순서는 유지 — 우열이 아니라 조합만 바뀐다).
## `authored`(연승방지봇)는 이벤트 매치라 **적힌 순서 그대로** 둔다.
static func _pick_roster(src: Array, n: int, rng: RandomNumberGenerator,
		authored: bool) -> Array:
	if authored or src.size() <= n:
		return src
	var idx: Array = []
	for i in src.size():
		idx.append(i)
	# 뒤에서부터 무작위로 빼며 n개만 남긴다(Fisher–Yates 부분 셔플).
	while idx.size() > n:
		idx.remove_at(rng.randi() % idx.size())
	idx.sort()
	var out: Array = []
	for i: int in idx:
		out.append(src[i])
	return out


## 시트가 적어 준 구성(젬·스킬·장비·임의스탯·면역)을 봇 드래곤 레코드에 얹는다.
##
## 🟦 사용자 확정 2026-08-04 — 연승방지봇은 **이벤트성 매치**라 일반 매칭과 규칙이 다르다.
## 출처 = `docs/input/sheets/colosseum_guard.csv` → `build_colosseum.py` 가 이름을 실제
## id·키로 확정해 `data/colosseum.json` `guards[].dragons[]` 에 실어 둔 것을 여기서 푼다.
## 이름 해석·검증은 전부 빌더가 끝냈다 — 여기서는 **장착만** 한다(못 끼우면 조용히 넘어가지
## 않고 push_warning 으로 남긴다).
static func _apply_sheet_spec(bd: Dictionary, r: Dictionary, rng: RandomNumberGenerator) -> void:
	var did := int(bd.get("id", 0))
	# 젬 — 칸 타입까지 시트가 정한다. 봇은 부화를 거치지 않으므로 랜덤 칸 타입 때문에
	#   지정한 젬이 안 들어가는 일이 없어야 한다(빌더가 젬에 맞는 타입을 계산해 둔다).
	var gm: Dictionary = r.get("gems", {})
	if not gm.is_empty():
		var field: Dictionary = {"types": gm.get("types", []), "slots": [null, null, null]}
		field = Gem.set_types(field, gm.get("types", []))
		for e: Dictionary in (gm.get("list", []) as Array):
			var next := Gem.equip_at(field, int(e.get("slot", 0)), String(e.get("name", "")),
				int(e.get("tier", 0)), Data.gems)
			if next.is_empty():
				push_warning("[Colosseum] 젬 장착 실패: %s (드래곤 %d)" % [e, did])
				continue
			field = next
		bd["gems"] = field
	# 스킬 — 배운 것과 장착 칸은 별개다(§ Loadout). 칸은 원작대로 **2개**다.
	# 🟦 사용자 확정 2026-08-05: 시트에 **2개보다 많이 적으면 그 중 랜덤 2개**를 장착한다
	#   ("전투마다" — 상대는 판마다 새로 만들어지므로 매 판 다시 뽑힌다).
	#   2개 이하면 적힌 것이 그대로 들어간다(뽑기 자체가 없다).
	var sk: Array = r.get("skills", [])
	if not sk.is_empty():
		var learned: Array = []
		for s: Dictionary in sk:
			learned.append({"id": int(s.get("id", 0)), "level": int(s.get("level", 1))})
		bd["skills"] = learned
		var pick: Array = []
		for i in learned.size():
			pick.append(i)
		while pick.size() > Loadout.SKILL_SLOTS:
			pick.remove_at(rng.randi() % pick.size())
		var eq: Array = []
		for i in Loadout.SKILL_SLOTS:
			eq.append(int((learned[pick[i]] as Dictionary).get("id", 0))
				if i < pick.size() and Loadout.slot_unlocked(i, int(bd.get("level", 50)))
				else 0)
		bd["skill_equip"] = eq
	# 장비 — 칸(all/battle/support/artifact)은 빌더가 주 능력치로 정해 둔다.
	#   희귀도·옵션·강화는 시트 **비고**에 적힌 만큼만 얹는다(안 적혔으면 주 능력만인 맨 장비).
	#   랭커 시트 비고 예: "모든 장비 [에픽] 최대 강화, 최적 옵션 장착(…)"
	#   ⚠️ 강화 수치는 빌더가 짓지 않는다 — 여기서 **원작 규칙 그대로**(`Equipment.enhance`,
	#      옵션 하나를 골라 +enhance_step_pct%) 적힌 횟수만큼 굴린다.
	var ep: Array = r.get("equip", [])
	if not ep.is_empty():
		var field2 := {"slots": []}
		for e2: Dictionary in ep:
			var slot_id := String(e2.get("slot", "all"))
			var meta := {
				"rarity": int(e2.get("rarity", 0)),
				"options": (e2.get("options", []) as Array).duplicate(true),
			}
			var next2 := Equipment.equip(field2, slot_id,
				String(e2.get("key", "")), Data.equipment, meta, did)
			if next2.is_empty():
				push_warning("[Colosseum] 장비 장착 실패: %s (드래곤 %d)" % [e2, did])
				continue
			field2 = next2
			for _i in int(e2.get("enhance", 0)):
				var up := Equipment.enhance(field2, slot_id, rng, Data.equipment)
				if up.is_empty():
					break                      # 상한(enchant_blocked) 에 닿았다
				field2 = up
		bd["equip"] = field2
	# 임의 스탯 — 확정값 + 범위값(범위는 상대를 만들 때마다 굴린다).
	var ov: Dictionary = (r.get("stats", {}) as Dictionary).duplicate()
	for k in (r.get("stats_roll", {}) as Dictionary):
		var span: Array = r["stats_roll"][k]
		if span.size() >= 2:
			ov[k] = rng.randf_range(float(span[0]), float(span[1]))
	if not ov.is_empty():
		bd["stat_override"] = ov
	if r.has("grade"):
		bd["grade_override"] = float(r["grade"])
	# 면역(비고 칸) — 전투가 읽는다. {skills:[id…], pure: bool, bonus: bool}
	var im: Dictionary = r.get("immune", {})
	if not im.is_empty():
		bd["immune"] = im.duplicate()


static func _tier_mid_rating(tier_key: String) -> int:
	var list: Array = (_cfg().get("tier", {}) as Dictionary).get("list", [])
	for t: Dictionary in list:
		if String(t.get("key", "")) == tier_key:
			return int(t.get("min_rating", 0)) + 100
	return int(_cfg().get("rating", {}).get("start", 1000))


# --- 상대 목록 -----------------------------------------------------------------
#
# ⚠️ 이 함수는 **로비가 쓰지 않는다**. 구판 로비는 후보 목록을 보여 주지 않는다(아래 `roll_match`
#   주석 참조 — `match1_list`/`match3_list` 는 후기판 전용 키였다).
#   남겨 두는 이유: 스크린샷 도구(`shot_helper.gd`)와 테스트가 "봇 여러 기를 한 번에" 만들 때 쓴다.
static func roll_opponents(mode: String, rng: RandomNumberGenerator = null) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var rating := rating_of(mode)
	var tier := tier_of(rating)
	var tkey := String(tier.get("key", "bronze"))
	var bots: Dictionary = _cfg().get("bots", {})
	var mix: Dictionary = (bots.get("tier_mix", {}) as Dictionary).get(tkey, {})
	var count := int(bots.get("list_size", 5))
	var gpend := pending_guard(mode)
	var guard_on := not gpend.is_empty()

	var rankers: Array = _cfg().get("rankers", [])
	var nicks := gen_nicks(count, rng)
	var out: Array = []
	# 연승방지가 걸려 있으면 **이름 있는 방지봇 1기**를 목록 맨 위에 넣는다.
	# (나머지 자리는 평소대로 굴린다 — 원작 목록도 여러 상대 중에서 고르는 형태다.)
	var guard_slot := -1
	if guard_on:
		out.append(make_guard(gpend, mode, rng))
		guard_slot = 0
	# 랭커는 **한 목록에 같은 사람이 두 번 나오지 않게** 뽑는다(비복원 추출).
	# 🔴 2026-08-06: 종전엔 매번 `rankers[randi() % size]` 라 같은 랭커가 두 칸을 차지했고,
	#   랭커 닉은 시트 고정이라 목록에 **동명이인**이 생겼다(test_colosseum "닉 중복 없음" 이
	#   그걸 잡았다). 랭커 시트가 비어 있던 동안은 전부 adept 로 떨어져 드러나지 않았다.
	var used_rankers := {}
	for i in count - out.size():
		var g := _pick_grade(mix, rng)
		if guard_on and guard_slot < 0:
			g = _grade_up(g)
		if g == "ranker" and used_rankers.size() >= rankers.size():
			g = "adept"                              # 랭커를 다 썼다 — 중급으로 대체
		if g == "ranker" and not rankers.is_empty():
			var ri := rng.randi() % rankers.size()
			while used_rankers.has(ri):
				ri = (ri + 1) % rankers.size()
			used_rankers[ri] = true
			out.append(_make_ranker(rankers[ri], mode, rng))
			continue
		if g == "ranker":
			g = "adept"                              # 랭커 CSV 가 비었으면 중급으로 대체
		# 상대 레이팅은 내 레이팅 언저리에서 흔든다.
		var r := maxi(0, rating + rng.randi_range(-120, 160))
		out.append(make_bot(g, mode, r, rng, String(nicks[i])))
	return out


static func _pick_grade(mix: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in mix:
		total += maxf(0.0, float(mix[k]))
	if total <= 0.0:
		return "novice"
	var r := rng.randf() * total
	var acc := 0.0
	var last := "novice"
	for k in mix:
		acc += maxf(0.0, float(mix[k]))
		last = String(k)
		if r < acc:
			return last
	return last


# --- 연승방지봇(라온 / 누리 / 선대군) ----------------------------------------
#
# 🟦 사용자 확정 2026-08-04 — 연승을 끊으러 오는 상대는 **이름 있는 3단계**다.
#   라온(5연승~) · 누리(15연승~) — **원작 캐릭터**이고 콜로세움 대사까지 실재한다
#     (`ColosseumRaonTalkA/B/C` · `ColosseumNuriTalkA/B`, stringsData_KR.xml — 유실 아님).
#   선대군(999연승) — **원작에 없는 오리지널 캐릭터**. 대사·구성 전부 사용자 CSV.
# 드래곤 구성은 셋 다 `docs/input/sheets/colosseum_guard.csv`(사용자 작성).

## 지금 연승에서 **도달한 가장 높은 문턱**의 등장 항목. 없으면 {}.
##
## 🟦 스케줄(사용자 확정): 25 누리A · 50 라온A · 75 누리B · 100 라온B · 150 라온C · 999 선대군.
## 한 항목이 "누가 + 어느 대사 단계"를 함께 정한다 — 원작 대사 단계 수와 정확히 맞는다
## (누리 A/B 2단계 · 라온 A/B/C 3단계).
static func guard_for(streak: int) -> Dictionary:
	var best: Dictionary = {}
	for g: Dictionary in (_cfg().get("guards", []) as Array):
		var at := int(g.get("streak_at", 0))
		if streak >= at and (best.is_empty() or at >= int(best.get("streak_at", 0))):
			best = g
	return best


## 다음 연승방지봇까지 남은 연승(없으면 0) — 로비 안내용.
static func next_guard_in(streak: int) -> int:
	var nxt := -1
	for g: Dictionary in (_cfg().get("guards", []) as Array):
		var at := int(g.get("streak_at", 0))
		if at > streak and (nxt < 0 or at < nxt):
			nxt = at
	return 0 if nxt < 0 else nxt - streak


## 연승방지봇 1기를 상대로 만든다. CSV 에 드래곤이 없으면 랭커 규칙으로 채운다.
static func make_guard(g: Dictionary, mode: String, rng: RandomNumberGenerator) -> Dictionary:
	var rec := {
		"nick": String(g.get("name", "")),
		"tier": "master",
		"rating": int(g.get("rating", 0)),
		"dragons": g.get("dragons", []),
	}
	var bot := _make_ranker(rec, mode, rng, true)     # authored — 시트가 구성을 전부 정한다
	var key := String(g.get("key", ""))
	bot["guard"] = true
	bot["guard_key"] = key
	bot["guard_at"] = int(g.get("streak_at", 0))
	bot["talk_stage"] = String(g.get("talk_stage", ""))
	# 대사 단계는 스케줄이 이미 확정해 뒀다. 최초 조우 / 반복 조우를 가르는 기준은
	#   `first_meet()` 한 곳이 정한다 — 시트의 `(최초 조우 시)` / `(반복)` 구역.
	#   원작 대사(라온·누리)는 등장마다 단계가 달라 `lines_first` 가 비어 있고, 그러면
	#   화면은 그냥 `lines` 를 쓴다.
	# 한 줄 = `{text, npc, name, body, emotion, pos, first_show, small}` — 원작
	#   `MatchingLayer::showNuriEvent`/`showRaonEvent` 의 `TalkNpc` 인자를 그대로 굽는다
	#   (누리 이벤트는 누리 + 즈믄 2인극이다). logic 은 내용을 모르고 그대로 넘기기만 한다.
	bot["lines"] = g.get("lines", [])
	bot["lines_first"] = g.get("lines_first", [])
	bot["first_meet"] = first_meet(key)
	return bot


## 이 방지봇을 몇 번 만났나(대사 최초/반복 판정용).
## `guard_met` 은 **모드 축이 없다** — 키가 봇 이름뿐이라 1vs1·3vs3 을 통틀어 센다.
static func met_count(guard_key: String) -> int:
	return int((state().get("guard_met", {}) as Dictionary).get(guard_key, 0))


## 이번 등장에 `(최초 조우 시)` 대사를 쓰나.
##
## 🔴 2026-08-07 사용자 지적 — **선대군만 기준이 다르다.** 다른 방지봇은 "만난 적이 있는가"
##   (`guard_met`)로 갈리지만, 선대군의 최초 대사는 해금 선물을 예고하는 안내라
##   ("특별한 선물을 하나 준비했습니다 … 점술집으로 가 보시겠어요?") **선물을 실제로 받을
##   때까지** 나와야 한다. 그 선물 = `Summon.FLAG_UNLOCK`(평문 이름 `MeetAdmin`)이고
##   `_grant_unlock` 이 **패배**할 때만 세운다 ⇒ 조우 횟수로 가르면 첫 판을 이겨 버렸을 때
##   플래그는 false 인데 최초 대사만 소진돼 안내가 영영 안 나온다.
##   ⇒ 선대군은 **플래그**로 가른다. 플래그도 모드 축이 없어(세이브 pmeta 한 칸)
##     1vs1·3vs3 을 통틀어 딱 한 번만 최초 대사 + 해금 이벤트가 뜬다.
static func first_meet(guard_key: String) -> bool:
	if guard_key == UNLOCK_GUARD_KEY:
		return not bool(UserDB.get_pmeta(Summon.FLAG_UNLOCK, false))
	return met_count(guard_key) <= 0


static func _grade_up(g: String) -> String:
	match g:
		"novice": return "adept"
		"adept": return "ranker"
		_: return "ranker"


## 이번 판 상대가 될 연승방지봇의 스케줄 항목. 없으면 {}.
##
## 🟦 사용자 확정 2026-08-06 — **문턱당 1회, 예외 없다.** 트리거 연승을 밟으면 바로 다음 판에
## 방지봇이 나오고, 그 한 판이 끝나면 다음 문턱까지는 일반 봇이다. **선대군(999)도 마찬가지** —
## 다시 만나려면 패배해서 연승을 끊고 999를 다시 쌓아야 한다. 해금(= 선대군에게 패배)이
## 막히지 않는 이유도 사용자가 확정했다: 약한 드래곤을 대신 출전시키면 언제든 질 수 있다.
##
## 🟦 2026-08-06 — `skip_if_admin` 이 붙은 항목(선대군)은 **관리자 모드에서 아예 안 나온다**.
## 거르는 자리를 여기로 잡은 이유: `guard_for()` 는 "그 연승의 담당자"를 묻는 순수 조회라
## 검증 씬·시뮬레이터가 그대로 쓴다(`test_colosseum.gd`·`sim_matchup.gd`). 실제 상대를
## 정하는 곳은 이 함수 하나뿐이다.
## ⚠️ 딸린 결과: 선대군에게 져서 열리는 해금(`_grant_unlock` → `Summon.FLAG_UNLOCK`)도
##   관리자 모드에서는 콜로세움으로 못 연다.
static func pending_guard(mode: String) -> Dictionary:
	var g := guard_for(streak_of(mode))
	if g.is_empty():
		return {}
	if bool(g.get("skip_if_admin", false)) and UserDB.is_admin():
		return {}
	return {} if _guard_served(mode, int(g.get("streak_at", 0))) else g


## 이 모드의 이 문턱을 이미 붙어 봤나.
static func _guard_served(mode: String, at: int) -> bool:
	var done: Array = (state().get("guard_served", {}) as Dictionary).get(mode, [])
	for v in done:
		if int(v) == at:
			return true
	return false


## 연승방지봇이 이번 상대인가(연출·라벨용).
static func guard_active(mode: String) -> bool:
	return not pending_guard(mode).is_empty()


## 상대를 하나 골라 실제로 붙기 직전에 호출 — **그 문턱을 붙어 본 것으로 적고** 조우를 기록한다.
## `foe` = `roll_match()` 가 돌려준 상대(일반 봇이면 아무것도 하지 않는다).
## ⚠️ 호출 순서가 중요하다 — `make_guard()` 가 `first_meet` 을 **이 기록 전에** 읽어 간다.
static func consume_guard(mode: String, foe: Dictionary = {}) -> void:
	if not bool(foe.get("guard", false)):
		return
	var s := state()
	var at := int(foe.get("guard_at", 0))
	if at > 0 and not _guard_served(mode, at):
		var srv: Dictionary = (s.get("guard_served", {}) as Dictionary).duplicate()
		var done: Array = (srv.get(mode, []) as Array).duplicate()
		done.append(at)
		srv[mode] = done
		s["guard_served"] = srv
	var key := String(foe.get("guard_key", ""))
	if key != "":
		var met: Dictionary = (s.get("guard_met", {}) as Dictionary).duplicate()
		met[key] = int(met.get(key, 0)) + 1
		s["guard_met"] = met
	save_state(s)


# --- 랜덤 매칭 --------------------------------------------------------------
#
# 🔴 정정 2026-08-04 — 종전의 `roll_opponents()`(후보 5명 목록에서 고르기)는 **후기판 오독**이었다.
#   구판 로비 클래스 `__ColosseumScene`(libgame.so 에 그대로 남아 있다) 의 흐름은
#     `onClickedColosseum1vs1` @00f257a4 / `onClickedColosseum3vs3` @00f25570
#       → 피로도 검사(`this+0x260 → +0x40 == 0` 이면 토스트)
#       → `checkDragon()` 실패면 토스트
#       → `LoadingLayer::show` + `FightManager::setType(0|1)`
#       → `Select1vs1Layer/Select3vs3Layer::create(1)` → `show()`
#   즉 **시작 버튼 → 덱 선택 → 서버가 상대를 배정**이다. 로비에 후보 목록이 없다는 것은
#   구판 `responseList` 가 처리하는 JSON 키에도 드러난다 — `pvp_total_rank`/`pvp_week_rank`
#   (랭킹 보드)는 있고 `match1_list`/`match3_list`(후보 목록)는 **후기판에만** 있다.
#   ⇒ 서버가 하던 "상대 1명 배정"을 이 함수가 대신한다(§2-1 예외, 배선 교체).

## 이번 판 상대 1기를 굴린다. 연승방지가 걸려 있으면 그 봇이 우선한다.
static func roll_match(mode: String, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var rating := rating_of(mode)
	var tkey := String(tier_of(rating).get("key", "bronze"))
	var bots: Dictionary = _cfg().get("bots", {})
	var mix: Dictionary = (bots.get("tier_mix", {}) as Dictionary).get(tkey, {})

	var gnpc := pending_guard(mode)
	if not gnpc.is_empty():
		return make_guard(gnpc, mode, rng)

	var g := _pick_grade(mix, rng)
	var rankers: Array = _cfg().get("rankers", [])
	if g == "ranker" and not rankers.is_empty():
		return _make_ranker(rankers[rng.randi() % rankers.size()], mode, rng)
	if g == "ranker":
		g = "adept"                                  # 랭커 CSV 가 비었으면 중급으로
	# ASSUMPTION: 상대 레이팅 폭(-120 ~ +160)은 서버 매칭 규칙이 유실돼 우리가 정한 값이다.
	var r := maxi(0, rating + rng.randi_range(-120, 160))
	return make_bot(g, mode, r, rng, gen_nick(rng))


# --- 랭킹 보드 (원작 pvp_total_rank / pvp_week_rank) --------------------------
#
# 구판 로비 왼쪽 CCTableView 가 보여 주던 것. 서버 소유 데이터라 유실 →
# 봇 사다리로 대신 채운다(§2-1 예외 · 사용자 확정 "봇으로만 구성").
# 한 번 만들면 세이브에 남아 순위가 흔들리지 않고, **새로고침(원작 onClickedRefresh)** 으로만 갈린다.

const LADDER_SIZE := 30

## 랭킹 보드 행 목록(내림차순). 없으면 만들어 저장한다.
## `weekly` = 주간 탭(원작 `pvp_week_rank`) — 같은 사다리에 주간 점수를 얹는다.
static func ladder(mode: String, weekly := false, rng: RandomNumberGenerator = null) -> Array:
	var s := state()
	var key := "pvp_week_rank" if weekly else "pvp_total_rank"
	var by_mode: Dictionary = s.get(key, {})
	if typeof(by_mode) != TYPE_DICTIONARY:
		by_mode = {}
	# 사다리 위쪽은 **랭커 시트가 차지한다**(_gen_ladder). 시트가 바뀌면 세이브에 굳어 있는
	# 보드가 옛 이름을 계속 보여 주므로, 시트 서명이 달라졌으면 **네 보드를 통째로 버린다**
	# (1vs1/3vs3 × 누적/주간 — 하나만 버리면 나머지가 서명만 새로 달고 남는다).
	# 그 밖에는 원작대로 새로고침(onClickedRefresh)으로만 갈린다.
	var sig := _ranker_sig()
	if String(s.get("pvp_rank_sig", "")) != sig:
		s["pvp_total_rank"] = {}
		s["pvp_week_rank"] = {}
		s["pvp_rank_sig"] = sig
		by_mode = {}
	var rows: Array = by_mode.get(mode, [])
	if rows.is_empty():
		rows = _gen_ladder(mode, weekly, rng)
		by_mode[mode] = rows
		s[key] = by_mode
		save_state(s)
	return rows


## 새로고침 — 사다리를 다시 굴린다(원작 `onClickedRefresh` 가 목록을 다시 받는 것과 같은 자리).
static func reroll_ladder(mode: String, rng: RandomNumberGenerator = null) -> void:
	var s := state()
	for weekly in [false, true]:
		var key := "pvp_week_rank" if weekly else "pvp_total_rank"
		var by_mode: Dictionary = s.get(key, {})
		if typeof(by_mode) != TYPE_DICTIONARY:
			by_mode = {}
		by_mode[mode] = _gen_ladder(mode, weekly, rng)
		s[key] = by_mode
	s["pvp_rank_sig"] = _ranker_sig()
	save_state(s)


## 내 순위 — 나보다 점수가 높은 봇 수 + 1 (원작 `my_rank` / `my_week_rank`).
static func my_rank(mode: String, weekly := false) -> int:
	var mine := rating_of(mode)
	var n := 1
	for r: Dictionary in ladder(mode, weekly):
		if int(r.get("rating", 0)) > mine:
			n += 1
	return n


## 랭커 시트의 서명 — 닉네임 목록이 바뀌면 사다리를 다시 굴리는 기준.
static func _ranker_sig() -> String:
	var names: Array = []
	for r: Dictionary in (_cfg().get("rankers", []) as Array):
		names.append(String(r.get("nick", "")))
	return "|".join(names)


static func _gen_ladder(mode: String, weekly: bool, rng: RandomNumberGenerator) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var tiers: Array = (_cfg().get("tier", {}) as Dictionary).get("list", [])
	var top := 2000
	if not tiers.is_empty():
		top = int((tiers[tiers.size() - 1] as Dictionary).get("min_rating", 2000))
	var rankers: Array = _cfg().get("rankers", [])
	var nicks := gen_nicks(LADDER_SIZE, rng)
	var out: Array = []
	for i in LADDER_SIZE:
		# ASSUMPTION: 사다리 점수 분포(1위 = 마스터 상단, 아래로 계단식)는 유실된 서버 값 대체다.
		var base := top + 420 - i * 26 + rng.randi_range(-12, 12)
		var nick := String(nicks[i])
		if i < rankers.size():                       # 상위 칸은 사용자 랭커 풀이 차지한다
			nick = String((rankers[i] as Dictionary).get("nick", nick))
		var row := {"nick": nick, "rating": maxi(0, base)}
		if weekly:
			row["rating"] = maxi(0, 900 - i * 22 + rng.randi_range(-10, 10))
		out.append(row)
	return out


# ---------- 대전 무대(스테이지) 속성 ----------
#
# 원작은 전투 시작에 무대 속성을 **룰렛**으로 뽑고(`MakeInterface::createElement` @0105daf0),
# 그 속성과 같은 종족의 드래곤 전원에게 버프 스파인을 붙인다
# (`checkStageBuff` @0105f368 → `showStageBuff` @0105f4b8). 배경도 그 속성으로 갈린다
# (`DualManager::getAttributeBgImage` @00f88b28).
#
# 여기(logic)는 **무엇이 뽑혔는가**만 정하고, 룰렛 연출·배경·스파인은 render(`fight.gd`)가 한다(§8).
# 표·상수는 전부 `data/colosseum.json` `stage` (= `build_colosseum.py` STAGE).

static func stage_cfg() -> Dictionary:
	return _cfg().get("stage", {})


## 룰렛 9칸 — 인덱스가 곧 원작 `FightManager::getStageElement()` 값이다.
static func stage_wheel() -> Array:
	return stage_cfg().get("wheel", [])


## 무대 1회 추첨. 반환 = `{index, element, bg}` (`bg` = `stage_<N>.jpg` 의 N).
## `rng` 를 주면 시드 고정이 되고(재현 가능), 안 주면 전역 난수를 쓴다.
static func roll_stage(rng: RandomNumberGenerator = null) -> Dictionary:
	var w := stage_wheel()
	if w.is_empty():
		return {}
	return stage_at(int((rng.randi() if rng != null else randi()) % w.size()))


## 룰렛 칸 번호로 직접 만든다(추첨 없이). 원작에선 서버가 이 값을 내려줬다
## (`FightManager::getStageElement`) — 검수·재현용 진입점이 여기다.
static func stage_at(index: int) -> Dictionary:
	var w := stage_wheel()
	if w.is_empty():
		return {}
	var i := posmod(index, w.size())
	var el := String(w[i])
	return {
		"index": i,
		"element": el,
		"bg": int((stage_cfg().get("bg", {}) as Dictionary).get(el, 3)),
	}


## 속성 이름으로 무대를 만든다(못 찾으면 {}). 검수용.
static func stage_of(element: String) -> Dictionary:
	var i := stage_wheel().find(element)
	return stage_at(i) if i >= 0 else {}


## 무대 속성이 일치하는 드래곤에게 걸리는 스탯 배수.
## 🟦 +10% = 사용자 확정 2026-08-05(원작 수치는 서버와 함께 유실 — 클라는 연출만 한다).
static func stage_mult() -> float:
	return 1.0 + float(stage_cfg().get("buff_pct", 0)) / 100.0


## 그 배수가 걸리는 스탯 키 목록.
static func stage_stats() -> Array:
	return stage_cfg().get("buff_stats", [])


# ---------- BGM ----------
#
# 로비는 원작이 명시한다(`ColosseumScene::onEnterTransitionDidFinish` @00f41e00).
# 대전 BGM 은 **매 판 랜덤**(🟦 사용자 확정 2026-08-05) — 클라에 재생 호출이 없어 곡 목록도
# 확인할 수 없다. 목록은 `data/colosseum.json` `bgm.battle` 이 튜닝 노브다.

static func lobby_bgm() -> String:
	return String((_cfg().get("bgm", {}) as Dictionary).get("lobby", "bg_colosseum"))


## 이번 판의 대전 BGM 1곡. `rng` 를 주면 재현 가능.
static func battle_bgm(rng: RandomNumberGenerator = null) -> String:
	var list: Array = (_cfg().get("bgm", {}) as Dictionary).get("battle", [])
	if list.is_empty():
		return "bg_colosseum_battle_2"
	return String(list[int((rng.randi() if rng != null else randi()) % list.size())])


## 매칭 대기 연출 길이(초). 🟦 사용자 확정 2026-08-05 — 원작은 서버 응답 대기라 고정이 아니었다.
static func matching_seconds() -> float:
	return float(_cfg().get("entry", {}).get("matching_seconds", 3))
