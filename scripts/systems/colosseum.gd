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
		"guard_left": 0,                                # 연승방지봇 남은 횟수
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
	return d


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
## {delta, rating_before, rating_after, tier_before, tier_after, tier_up, tier_down, streak, best}.
static func apply_result(mode: String, win: bool, opponent_nick := "") -> Dictionary:
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

	# 연승방지 — 임계에 닿으면 다음 guard_repeat 판은 상대 등급이 한 단계 올라간다.
	var st: Dictionary = _cfg().get("streak", {})
	var guard_at := int(st.get("guard_at", 0))
	if guard_at > 0 and win and int(s[sk]) >= guard_at:
		s["guard_left"] = int(st.get("guard_repeat", 1))
	elif not win:
		s["guard_left"] = 0

	var hist: Array = (s.get("history", []) as Array).duplicate()
	hist.push_front({"mode": mode, "win": win, "delta": delta, "foe": opponent_nick})
	while hist.size() > 20:
		hist.pop_back()
	s["history"] = hist
	save_state(s)

	return {
		"delta": delta, "rating_before": before, "rating_after": after,
		"tier_before": t_before, "tier_after": t_after,
		# id = ColosseumProfile::getRatingBorder 의 case 번호(0 BRONZE … 5 MASTER) — **클수록 높다**.
		# 🔴 2026-08-04: 종전엔 StrategyManager 규약(작을수록 높다)이라 부호가 반대였다.
		"tier_up": int(t_after.get("id", 0)) > int(t_before.get("id", 0)),
		"tier_down": int(t_after.get("id", 0)) < int(t_before.get("id", 0)),
		"streak": int(s[sk]), "best": int(s[bk]),
	}


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
static func _make_ranker(rec: Dictionary, mode: String, rng: RandomNumberGenerator) -> Dictionary:
	var spec: Dictionary = (_cfg().get("bots", {}) as Dictionary).get("grades", {}).get("ranker", {})
	var n := party_size(mode)
	var src: Array = rec.get("dragons", [])
	var dragons: Array = []
	for i in n:
		if i < src.size():
			var r: Dictionary = src[i]
			var sp := spec.duplicate(true)
			sp["level"] = int(r.get("level", spec.get("level", 50)))
			sp["awakened"] = bool(r.get("awakened", spec.get("awakened", true)))
			dragons.append(_make_bot_dragon(int(r.get("id", 0)),
				BOT_UID_BASE + 500000 + i, sp, rng))
		elif not src.is_empty():
			break                                   # CSV 가 지정한 수만큼만
	var rating := int(rec.get("rating", 0))
	if rating <= 0:
		rating = _tier_mid_rating(String(rec.get("tier", "master")))
	return {
		"nick": String(rec.get("nick", "")), "grade": "ranker", "rating": rating,
		"tier": tier_of(rating), "dragons": dragons, "bot": true, "ranker": true,
	}


static func _tier_mid_rating(tier_key: String) -> int:
	var list: Array = (_cfg().get("tier", {}) as Dictionary).get("list", [])
	for t: Dictionary in list:
		if String(t.get("key", "")) == tier_key:
			return int(t.get("min_rating", 0)) + 100
	return int(_cfg().get("rating", {}).get("start", 1000))


# --- 상대 목록(원작 match1_list / match3_list 자리) ---------------------------

## 지금 티어에 맞는 상대 목록을 굴린다. 원작이 서버에서 받던 그 배열이다.
##
## `guard` 가 켜져 있으면(연승방지) 한 단계 위 분류가 섞인다.
static func roll_opponents(mode: String, rng: RandomNumberGenerator = null) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var s := state()
	var rating := rating_of(mode)
	var tier := tier_of(rating)
	var tkey := String(tier.get("key", "bronze"))
	var bots: Dictionary = _cfg().get("bots", {})
	var mix: Dictionary = (bots.get("tier_mix", {}) as Dictionary).get(tkey, {})
	var count := int(bots.get("list_size", 5))
	var guard_on := int(s.get("guard_left", 0)) > 0

	var rankers: Array = _cfg().get("rankers", [])
	var nicks := gen_nicks(count, rng)
	var out: Array = []
	# 연승방지가 걸려 있으면 **이름 있는 방지봇 1기**를 목록 맨 위에 넣는다.
	# (나머지 자리는 평소대로 굴린다 — 원작 목록도 여러 상대 중에서 고르는 형태다.)
	var guard_slot := -1
	if guard_on:
		var gnpc := guard_for(streak_of(mode))
		if not gnpc.is_empty():
			out.append(make_guard(gnpc, mode, rng))
			guard_slot = 0
	for i in count - out.size():
		var g := _pick_grade(mix, rng)
		if guard_on and guard_slot < 0:
			g = _grade_up(g)
		if g == "ranker" and not rankers.is_empty():
			out.append(_make_ranker(rankers[rng.randi() % rankers.size()], mode, rng))
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
	var bot := _make_ranker(rec, mode, rng)
	bot["guard"] = true
	bot["guard_key"] = String(g.get("key", ""))
	bot["talk_stage"] = String(g.get("talk_stage", ""))
	bot["lines"] = g.get("lines", [])       # 대사 단계는 스케줄이 이미 확정해 뒀다
	return bot


static func _grade_up(g: String) -> String:
	match g:
		"novice": return "adept"
		"adept": return "ranker"
		_: return "ranker"


## 연승방지봇이 이번 상대인가(연출·라벨용).
static func guard_active() -> bool:
	return int(state().get("guard_left", 0)) > 0


## 상대를 하나 골라 실제로 붙기 직전에 호출 — 연승방지 카운터를 1 깎는다.
static func consume_guard() -> void:
	var s := state()
	if int(s.get("guard_left", 0)) > 0:
		s["guard_left"] = int(s["guard_left"]) - 1
		save_state(s)
