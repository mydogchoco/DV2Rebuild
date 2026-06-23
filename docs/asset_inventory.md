# 에셋 인벤토리 (Phase 0 자동 카탈로깅)

> `scripts/tools/catalog_assets.py`로 생성. 원본: `DV2/` (읽기 전용).

- 총 용량(.git 제외): **562 MB**

## 파일 포맷 분포

| 확장자 | 개수 |
|---|---|
| spine_json | 2129 |
| png | 2027 |
| img_plist | 2020 |
| jpg | 392 |
| mp3 | 318 |
| plist | 76 |
| fnt | 9 |
| h | 8 |
| xml | 5 |
| txt | 4 |
| ccz | 2 |
| md | 1 |
| fsh | 1 |

## 엔티티 ID 커버리지

- 드래곤 ID: 1~9999 (390개)
- 몬스터 ID: 1~193 (172개)
- 스킬 아이콘 ID: 10~170 (39개)

### 드래곤 spine 변형별 개수

| 변형 | 개수 |
|---|---|
| adult | 387 |
| baby | 371 |
| child | 371 |
| critical | 315 |
| e | 135 |
| e_critical | 115 |
| (base) | 25 |

## 480/ 카테고리별 파일 수

| 카테고리 | 파일 수 |
|---|---|
| battle | 75 |
| card | 194 |
| dragon | 4183 |
| font | 18 |
| item | 32 |
| monster | 890 |
| npc | 84 |
| scenario | 121 |
| scene | 801 |
| skill | 149 |

## 메모

- Spine 포맷: 구버전(2.0/2.1/3.0/3.5 혼재) — `analyze_spine.py` 참고.
- 게임플레이 수치 데이터는 에셋에 없음(역설계 대상).
