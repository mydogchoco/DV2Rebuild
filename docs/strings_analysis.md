# strings XML 구조 분석 (Phase 0)

> `scripts/tools/analyze_strings.py` 생성. 원본 `DV2/string/` (읽기 전용).

## 언어별 키 개수 (번역 커버리지)

| 언어 | 키 수 |
|---|---|
| KR | 9585 |
| EN | 9487 |
| JP | 5403 |
| CN | 5290 |
| TW | 5290 |

- KR 마스터 총 키: **9585**

## 분류 요약

- 포맷 템플릿(%d/%s/%f 포함): **729**개 → 런타임 포맷 문자열
- 순수 숫자/기호 값(데이터 냄새): **0**개
- 엔티티 인덱스 패밀리(번호 포함, 3개 이상): **301**종

## 엔티티 인덱스 패밀리 (데이터 엔티티와 연결될 텍스트)

> `#`은 ID 자리. 이 키들이 dragon/skill/stage 등 `data/*.json` 항목의 이름·설명으로 연결됨.

| 패턴(skeleton) | 개수 | 예시 |
|---|---|---|
| `ScenarioTalk#_#` | 2683 | ScenarioTalk1033_1, ScenarioTalk1033_2, ScenarioTalk1033_3 |
| `ScenarioTalk#_#_#` | 2334 | ScenarioTalk100_1_1, ScenarioTalk100_1_2, ScenarioTalk100_1_3 |
| `Tip_#` | 107 | Tip_1, Tip_10, Tip_100 |
| `QuestTitle#` | 88 | QuestTitle100, QuestTitle102, QuestTitle104 |
| `EventTalk#_#` | 79 | EventTalk1_1, EventTalk1_10, EventTalk1_11 |
| `GuildMsg#` | 71 | GuildMsg1, GuildMsg10, GuildMsg11 |
| `Strategy_Tutorial_#` | 64 | Strategy_Tutorial_1, Strategy_Tutorial_10, Strategy_Tutorial_11 |
| `Tutorial_#` | 45 | Tutorial_1, Tutorial_10, Tutorial_11 |
| `AdventureBattleMission_#` | 36 | AdventureBattleMission_1, AdventureBattleMission_10, AdventureBattleMission_11 |
| `SystemMsg#` | 34 | SystemMsg1, SystemMsg10, SystemMsg11 |
| `PrologueTalk#` | 34 | PrologueTalk0, PrologueTalk1, PrologueTalk10 |
| `ScrambleWord#` | 33 | ScrambleWord1, ScrambleWord10, ScrambleWord11 |
| `GuildErrorMsg#` | 31 | GuildErrorMsg1, GuildErrorMsg10, GuildErrorMsg11 |
| `Combine#` | 30 | Combine1, Combine10, Combine11 |
| `Combine_Comment_#` | 30 | Combine_Comment_1, Combine_Comment_10, Combine_Comment_11 |
| `CaveBagMsg#` | 29 | CaveBagMsg1, CaveBagMsg10, CaveBagMsg11 |
| `AdventureField_#` | 29 | AdventureField_1, AdventureField_10, AdventureField_11 |
| `AlchemyMsg#` | 27 | AlchemyMsg1, AlchemyMsg10, AlchemyMsg11 |
| `errorMsg#` | 26 | errorMsg1, errorMsg10, errorMsg11 |
| `CaveToastMsg#` | 26 | CaveToastMsg1, CaveToastMsg10, CaveToastMsg11 |
| `Scramble_tutorial_#` | 25 | Scramble_tutorial_1, Scramble_tutorial_10, Scramble_tutorial_11 |
| `CashMsg#` | 24 | CashMsg1, CashMsg10, CashMsg11 |
| `MailMsg#` | 24 | MailMsg1, MailMsg10, MailMsg11 |
| `SettingMsg#` | 23 | SettingMsg1, SettingMsg10, SettingMsg11 |
| `DragonBallEvent_msg#` | 23 | DragonBallEvent_msg1, DragonBallEvent_msg10, DragonBallEvent_msg11 |
| `worldmap_side_menu_#_#` | 22 | worldmap_side_menu_4_0, worldmap_side_menu_4_1, worldmap_side_menu_4_2 |
| `RaidMsg#` | 21 | RaidMsg1, RaidMsg10, RaidMsg11 |
| `SkillLab_NpcTalk_#_#` | 21 | SkillLab_NpcTalk_0_0, SkillLab_NpcTalk_1_0, SkillLab_NpcTalk_1_1 |
| `WorldmapMenu#` | 20 | WorldmapMenu1, WorldmapMenu10, WorldmapMenu11 |
| `MagicErrorMsg#` | 19 | MagicErrorMsg1, MagicErrorMsg10, MagicErrorMsg11 |
| `SocialMsg#` | 19 | SocialMsg1, SocialMsg10, SocialMsg11 |
| `NurtureTrainingMsg#` | 18 | NurtureTrainingMsg1, NurtureTrainingMsg10, NurtureTrainingMsg11 |
| `new_equip_sort_#_#` | 16 | new_equip_sort_0_0, new_equip_sort_0_1, new_equip_sort_0_2 |
| `CaveItemEquipComent#` | 15 | CaveItemEquipComent1, CaveItemEquipComent10, CaveItemEquipComent11 |
| `ScrambleMsg#` | 13 | ScrambleMsg1, ScrambleMsg10, ScrambleMsg11 |
| `CaveItemEquipMsg#` | 13 | CaveItemEquipMsg1, CaveItemEquipMsg10, CaveItemEquipMsg11 |
| `CaveEggBronMsg#` | 13 | CaveEggBronMsg1, CaveEggBronMsg10, CaveEggBronMsg11 |
| `MissionTitle#` | 13 | MissionTitle1, MissionTitle10, MissionTitle11 |
| `AdventureAlert_#` | 13 | AdventureAlert_1, AdventureAlert_10, AdventureAlert_11 |
| `GuideMenu#_#` | 13 | GuideMenu1_1, GuideMenu1_2, GuideMenu1_3 |

## 순수 숫자 값 키 (있다면 데이터일 수 있음)

없음 — strings에는 실제 수치 데이터가 들어있지 않음(라벨/템플릿뿐).

## 최상위 prefix 분포 (상위 30)

| prefix | 키 수 |
|---|---|
| ScenarioTalk46 | 139 |
| Tip | 107 |
| ScenarioTalk34 | 102 |
| ScenarioTalk24 | 88 |
| Auction | 86 |
| ScenarioTalk55 | 80 |
| ScenarioTalk50 | 78 |
| ScenarioTalk102 | 74 |
| ScenarioTalk94 | 70 |
| ScenarioTalk90 | 66 |
| ScenarioTalk97 | 66 |
| ScenarioTalk43 | 65 |
| Strategy | 64 |
| NPC | 62 |
| ScenarioTalk88 | 62 |
| ScenarioTalk95 | 61 |
| ScenarioTalk27 | 60 |
| ScenarioTalk96 | 60 |
| ScenarioTalk52 | 59 |
| ScenarioTalk104 | 59 |
| ScenarioTalk86 | 58 |
| ScenarioTalk57 | 57 |
| ScenarioTalk78 | 57 |
| ScenarioTalk132 | 54 |
| ScenarioTalk42 | 53 |
| ScenarioTalk106 | 53 |
| ScenarioTalk41 | 52 |
| ScenarioTalk89 | 52 |
| ScenarioTalk136 | 52 |
| ScenarioTalk74 | 51 |

## 결론 (Phase 0)

- strings의 정체 = **UI 라벨 + 시스템/에러 메시지 + 시나리오 대사 + 튜토리얼/퀘스트/팁**의 다국어 로컬라이제이션.
- **엔티티 이름은 여기 없음.** 드래곤/스킬/몬스터 이름을 ID로 담는 패밀리 미발견(검출 21종). 예: '철갑방패' 같은 스킬명·드래곤명이 strings에 부재.
  ⇒ 드래곤/스킬/몬스터 **이름도 마스터 데이터처럼 사용자가 위키 기반으로 복원**해야 함(에셋 미수록).
- 순수 숫자 값 키: 위 표 기준 — 게임 수치 데이터로 볼 만한 항목은 사실상 없음(대사 말줄임표 등 제외).
- 활용: 시나리오/튜토리얼/UI 텍스트는 `data/strings.json`으로 파싱해 그대로 사용 가능(번역 5개 언어).
- 번역 커버리지: KR 9585 / EN 9487 (거의 전수) vs JP·CN·TW ~5403 (부분, 주로 시나리오 누락 추정).
