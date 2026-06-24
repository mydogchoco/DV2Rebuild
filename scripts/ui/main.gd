extends Control
## 게임 진입점(render/app 최상위). 부팅 시 새 게임을 보장하고 초기 씬으로 전환한다.
## render→logic(NewGame)→data(Data) 단방향만 사용. (CLAUDE.md §10.2)

func _ready() -> void:
	NewGame.ensure(UserDB, Data.new_game_def())   # 진행 중 세이브 없으면 초기 로드아웃
	Scenes.bind_root($SceneRoot)
	Scenes.goto("cave")
