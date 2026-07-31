extends Control
## 게임 진입점(render/app 최상위). 부팅 시 새 게임을 보장하고 초기 씬으로 전환한다.
## render→logic(NewGame)→data(Data) 단방향만 사용. (CLAUDE.md §10.2)

func _ready() -> void:
	Scenes.bind_root($SceneRoot)
	begin_new_game()

## 새 게임 절차 = 초기 로드아웃 적용 → 메인 화면 → 최초 1회 닉네임 입력.
##
## 부팅(_ready)과 **세이브 데이터 초기화 직후**(`SettingLayer::_do_reset`)가 이 하나를 같이 쓴다.
## 🔴 2026-07-31 수정 — 종전엔 세 단계가 `_ready` 안에만 있어서, 게임을 켠 채로 세이브를
##    초기화하면 `UserDB.reset()` 이 빈 세이브를 만들어 놓고 아무도 다시 태우지 않았다:
##    시작 드래곤·재화·아이템이 0이고 닉네임 팝업도 뜨지 않았다(재실행해야 복구됐다).
func begin_new_game() -> void:
	NewGame.ensure(UserDB, Data.new_game_def())   # 진행 중 세이브 없으면 초기 로드아웃
	# 원작 메인 화면은 **WorldMapScene 의 유타칸 지역뷰(낮)** 다 — 양피지 전체지도
	# (`WorldMapFullLayer`)는 하단 메뉴 '월드맵'(tag 0x12)으로 따로 들어가는 화면이고,
	# 동굴도 하단 메뉴의 한 항목이다(`WorldMapScene::moveCave`, `menu_cave`).
	# 근거: 레퍼런스 `docs/ref/orig_image/old_screenshots/Yutakan_main.png` = 부팅 직후 화면 = 유타칸 섬.
	# 🔴 종전엔 `goto("worldmap")`(=overview 양피지)로 띄워 첫 화면이 원작과 달랐다(2026-07-28 수정).
	Scenes.goto("worldmap", {"region": "yutakan"})
	# 원작 User::getNickName 이 비어 있으면(=최초 실행) 닉네임을 받는다.
	# NickNameLayer::create(true) 상당 — 취소 없이 확정해야 진행된다.
	# SceneRoot 가 아니라 최상위(self)에 붙여 씬 전환과 무관하게 떠 있게 한다.
	if not UserDB.has_user_nickname():
		NickNamePopup.open(self, true)
