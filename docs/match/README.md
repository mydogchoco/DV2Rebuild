# 에셋 ↔ 데이터 매칭 시트 (사용자 작성용)

> Claude가 ID·에셋 보유여부를 자동 채운 skeleton입니다. 사용자는 **빈 칸(name/element/
> type/star/generation)만** 채우면 됩니다. Excel에서 열어 편집하고 저장하세요(UTF-8 CSV).
> 다 채우면 Claude가 `data/dragons.json`으로 변환합니다.

## dragons.csv 컬럼 설명

| 컬럼 | 채움 주체 | 값 |
|---|---|---|
| `id` | 자동 | 드래곤 ID (에셋 `dragon_{id}` 기준) |
| `name` | **사용자** | 드래곤 이름 (strings에 없음 — 위키/기억으로) |
| `element` | **사용자** | `aqua / earth / fire / wind / light / dark / holy / chaos / shadow` 중 |
| `type` | **사용자** | `atk(공격) / hp(체력) / def(방어) / ha(체공) / ad(공방) / hd(체방)` 중 |
| `star` | **사용자** | 레어도 `4 / 5 / 6` |
| `generation` | **사용자** | 세대 (예 `1`, `2.4`, `3` …) |
| `has_baby/child/adult/critical/e` | 자동 | 해당 spine 변형 보유 여부 (`Y`/공백) |
| `notes` | 선택 | 비고 (각성형/이벤트/조합전용 등) |

## 채우기 팁

- **전부 채울 필요 없습니다.** MPV용으로 우선 **소수(예 10마리)**만 채워도 진행 가능.
- `star`↔`generation` 매핑은 DragonStat.xlsx 티어 기준(2.4세대까지 4성, 그 이상 5/6성).
- `element`/`type`은 위 영문 키로 통일(§K-9 확정).
- 모르는 항목은 비워두면 Claude가 TODO로 처리합니다.

## 다른 매칭 시트 (추후 생성 예정)

- `skills.csv` — `id(skill/{id}.png) | name | type(△□○☆) | element | 효과식`
- `monsters.csv` — `id | name | 유형 | 속성 | 등장 스테이지`
- `assets_unknown.csv` — 용도 불분명 에셋: `파일경로 | 인게임 용도`
