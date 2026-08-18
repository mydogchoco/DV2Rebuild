extends SceneTree

const D := preload("res://scripts/systems/darknix.gd")
const B := preload("res://scripts/systems/battle.gd")

const N := 30000

func _init() -> void:
	var fails := 0
	var stages: Dictionary = (_json(_data_file("stages.json")) as Dictionary)["stages"]
	var st: Dictionary = stages["8"]

	fails += _true("8번이 소환형", D.is_summon_stage(st))
	fails += _true("일반 던전은 소환형 아님", not D.is_summon_stage(stages["7"]))
	var cfg: Dictionary = st["summon"]
	fails += _eq("포탈 아이템 키", String(cfg.get("item", "")), "portal")
	fails += _eq("다이아 대체가", int(cfg.get("cash", 0)), 1)
	fails += _eq("유지시간(초)", int(cfg.get("duration", 0)), 3600)

	var now := 1000000
	var none := {"status": 0, "until": 0, "face": 0}
	fails += _eq("미소환+포탈 보유 → 아이템",
		String(D.gate(cfg, none, now, 3, 0).get("action", "")), D.USE_ITEM)
	fails += _eq("미소환+포탈 없음+다이아 있음 → 다이아",
		String(D.gate(cfg, none, now, 0, 5).get("action", "")), D.USE_CASH)
	fails += _eq("미소환+둘 다 없음 → 환전 안내",
		String(D.gate(cfg, none, now, 0, 0).get("action", "")), D.NO_CASH)
	var live := {"status": 1, "until": now + 10, "face": 0}
	fails += _eq("상주 중 → 입장",
		String(D.gate(cfg, live, now, 0, 0).get("action", "")), D.ENTER)
	fails += _eq("상주 중엔 포탈 재소모 안 함",
		String(D.gate(cfg, live, now, 9, 9).get("action", "")), D.ENTER)

	var expired := {"status": 2, "until": now, "face": 0}
	fails += _true("만료면 비활성", not D.is_active(expired, now))
	fails += _eq("만료 후엔 다시 소환 게이트",
		String(D.gate(cfg, expired, now, 1, 0).get("action", "")), D.USE_ITEM)
	fails += _eq("남은 시간(만료)", D.remain(expired, now), 0)
	fails += _eq("남은 시간(상주)", D.remain(live, now), 10)

	var rng := RandomNumberGenerator.new(); rng.seed = 20260731
	var cnt := {1: 0, 2: 0, 3: 0}
	for i in N:
		var v := D.roll(cfg, now, rng)
		cnt[int(v["status"])] = int(cnt[int(v["status"])]) + 1
		if i == 0:
			fails += _eq("소환 만료시각 = now + duration",
				int(v["until"]), now + int(cfg["duration"]))
			fails += _eq("소환 직후 face=0", int(v["face"]), D.FACE_NONE)
	for pair in [[1, 0.5], [2, 0.3], [3, 0.2]]:
		var got := float(cnt[int(pair[0])]) / float(N)
		fails += _near("status %d 비중" % int(pair[0]), got, float(pair[1]), 0.02)

	var enemies: Array = st["enemies"]
	var expect := {1: 36, 2: 138, 3: 139}
	for s in [1, 2, 3]:
		var idx := int(D.variant_of(cfg, s).get("enemy", -1))
		fails += _true("status %d 인덱스 유효" % s, idx >= 0 and idx < enemies.size())
		if idx >= 0 and idx < enemies.size():
			fails += _eq("status %d → 몬스터 번호" % s,
				int((enemies[idx] as Dictionary).get("id", 0)), int(expect[s]))
		fails += _eq("status %d appear 애니" % s, D.anim_of(cfg, s, 0),
			"appear" if s == 1 else "appear%d" % s)
		fails += _eq("status %d breath 애니" % s, D.anim_of(cfg, s, 1),
			"breath" if s == 1 else "breath%d" % s)
		fails += _eq("status %d touch 애니" % s, D.anim_of(cfg, s, 2),
			"touch" if s == 1 else "touch%d" % s)
		fails += _eq("status %d enemy_index" % s,
			D.enemy_index(cfg, {"status": s, "until": now + 5}, now), idx)
	fails += _eq("미소환이면 enemy_index=-1", D.enemy_index(cfg, none, now), -1)

	var p2: Dictionary = cfg.get("phase2", {})
	fails += _near("전환 임계", float(p2.get("hp_threshold", 0.0)), 0.33, 0.0001)
	fails += _near("피해 배수", float(p2.get("damage_taken_mult", 1.0)), 0.5, 0.0001)
	var boss := {"name": "boss", "alive": true, "hp": 1000, "hp_max": 1000, "effects": [],
		"phase": 1, "phase2_at": 0.33, "phase2_taken_mult": 0.5}
	var flagged := 0
	var hits := 0
	while bool(boss["alive"]) and hits < 60:
		var r: Dictionary = B._apply_dmg(boss, 100)
		hits += 1
		if r.has("phase2"):
			flagged += 1
			fails += _eq("전환 시점 HP", int(boss["hp"]), 300)
			fails += _eq("전환을 만든 타격은 감면 없음", int(r["dmg"]), 100)
		elif int(boss.get("phase", 1)) == 2:
			fails += _eq("2페이즈 피해(타격 %d)" % hits, int(r["dmg"]), 50)
	fails += _eq("전환 이벤트는 1회만", flagged, 1)
	fails += _eq("최종 phase", int(boss.get("phase", 1)), 2)
	fails += _eq("총 타격 수", hits, 13)
	var plain := {"name": "m", "alive": true, "hp": 1000, "hp_max": 1000, "effects": []}
	var pr: Dictionary = B._apply_dmg(plain, 100)
	fails += _true("일반 몬스터는 전환 없음", not pr.has("phase2"))
	fails += _eq("일반 몬스터 피해 그대로", int(pr["dmg"]), 100)

	print("\n%s  (%d 실패)" % ["FAIL" if fails > 0 else "OK", fails])
	quit(1 if fails > 0 else 0)

func _json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f != null else null

func _true(label: String, cond: bool) -> int:
	print("  %s %s" % ["✔" if cond else "✘", label])
	return 0 if cond else 1

func _eq(label: String, got, want) -> int:
	var ok: bool = got == want
	print("  %s %s : %s%s" % ["✔" if ok else "✘", label, str(got),
		"" if ok else " (기대 %s)" % str(want)])
	return 0 if ok else 1

func _near(label: String, got: float, want: float, tol: float) -> int:
	var ok := absf(got - want) <= tol
	print("  %s %s : %.4f%s" % ["✔" if ok else "✘", label, got,
		"" if ok else " (기대 %.4f ±%.3f)" % [want, tol]])
	return 0 if ok else 1

static func _data_file(name: String) -> String:
	var side := "res://data/text/" + name
	return side if FileAccess.file_exists(side) else "res://data/" + name
