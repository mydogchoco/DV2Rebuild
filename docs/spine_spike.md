# Spine 로딩 스파이크 결과 (Phase 0)

> 도구: `scripts/tools/analyze_spine.py`(버전, 60샘플), `scripts/tools/scan_attachments.py`(어태치먼트 복잡도, 200샘플). 작성일 2026-06-24.

## ✅ 최종 결정 (2026-06-24, 사용자 승인)

**옵션 4 — GDScript 자작 중, 특히 「1b: 오프라인 변환기」 방식으로 확정.**
일회성 도구로 각 `spine_json` → **Godot 네이티브 `Skeleton2D` + `AnimationPlayer` 씬**으로
변환한다. 재생·블렌딩·에디터 프리뷰는 Godot 기본 애니 시스템이 담당. 근거는 아래
"어태치먼트 복잡도" 측정(=region 100%, mesh/deform 0%). Godot 유지(엔진 교체 안 함).

## 결론 요약

**DV2의 spine_json은 전부 구버전(Spine 2.0.x / 2.1.x / 3.0.x / 3.5.x 혼재)이다.**
최신 **spine-godot 런타임(Spine 4.x 전용)으로는 로드할 수 없다** — 사실상 확정.
이는 **Godot만의 문제가 아니라** 에셋 버전 문제(모든 엔진의 최신 spine 런타임이 옛 포맷 거부).
단 옛 `spine-cocos2dx`/`spine-ts`는 옛 버전 런타임이 존재 — 그러나 버전 혼재 + 엔진 교체
비용 때문에 채택 안 함(자세한 비교는 "전략 옵션"·"엔진 교체 검토").

## 근거 (샘플 60개)

- `skeleton.spine` 버전 필드: `3.0.09`, `2.1.27`, `2.1.18`, `2.1.09`, `2.1.08`, `2.1.07`,
  `2.0.23`, `3.5.18` 등으로 확인. **샘플의 절반(31/60)은 `skeleton` 블록조차 없음**(최古 2.x).
- `animations`, `skins` 컨테이너가 **dict 구조**(구포맷). 4.x는 list 구조.
- 애니메이션 키는 풍부: `wait, love, attack, critical, damaged, down, ultimate1, ultimate2,
  groggy, walk, breath` 등 → 전투 연출에 충분.

## 어태치먼트 복잡도 (자작 난이도의 핵심 변수, 200샘플)

- 어태치먼트 **5,573개 전부 `region`**(단순 스프라이트). **mesh/weighted/linkedmesh = 0개.**
- **deform/FFD 타임라인 = 0개.**
- ⇒ 폴리곤 변형·가중치 본·FFD 등 "어려운 부분"이 **전무**. 강체 골격(본 회전/이동/스케일
  + region 스프라이트)뿐이라 **Godot `Bone2D`+`Sprite2D`에 거의 1:1 매핑** 가능.
- 버전 분포(200샘플): noblock(최古 2.x) 108 / 3.0 60 / 2.1 30 / 기타(3.6, 1.9) 소수.

## 에셋 구조 추가 발견 (변환기 설계 단순화, 2026-06-24)

- 드래곤 spine의 `.img_plist`는 **XML plist가 아니라 표준 Spine 아틀라스(.atlas) 텍스트 포맷**.
  region 이름이 spine_json 어태치먼트와 정확히 일치. ⇒ `spine_json + .img_plist(=atlas) + .png`가
  **완전한 표준 Spine 에셋 3종 세트**(확장자만 비표준).
  - ⚠️ 주의: `.img_plist`에는 두 종류가 공존 — (a) 위 **Spine 아틀라스**(dragon spine 등),
    (b) **Cocos2d-x XML plist**(monster `1_image.img_plist` 등 일반 스프라이트 아틀라스). 변환기는
    첫 줄로 포맷 판별(XML 선언 → Cocos plist / 그 외 → Spine 아틀라스).
- 한 드래곤 스켈레톤은 **멀티페이지**: 예) `dragon_1_spine.img_plist`(메인 111리전) +
  `dragon_1_spine/skin_1_spine.img_plist`(스킨 28리전). baby/child/adult 리전이 두 페이지의
  **union에 100% 존재**(검증 완료). 변환기는 두 아틀라스를 병합해야 함.
- 아틀라스 헤더의 페이지 이미지는 `*.pvr.ccz`(PVR 압축)로 적혀 있으나, 폴더에 **디코딩된 `.png`가
  같이 있음** → `.png`를 페이지 텍스처로 사용(.pvr.ccz 무시).
- ⇒ 4b 변환기 입력: spine_json(스켈레톤) + Spine 아틀라스 1~N개(.img_plist) + 페이지 PNG들.

## 전략 옵션

| # | 방안 | 장점 | 단점 |
|---|---|---|---|
| 1 | 최신 spine-godot 직접 로드 | 즉시 | **불가**(버전 불일치) |
| 2 | 구버전 spine-godot/런타임 | 공식 런타임 | Godot 4용 2.x/3.x spine 런타임이 **존재하지 않음** |
| 3 | 옛→4.x 포맷 변환 후 spine-godot | 이후 표준화 | .spine 프로젝트 없음+JSON 직수입 불가, **유료 Spine 에디터 필요**, 변환 손실 |
| 4a | GDScript 런타임 인터프리터 | 의존성 0, 완전 제어 | 실행 중 매 프레임 보간/그리기순서/블렌딩을 직접 구현·유지 |
| **4b** | **오프라인 변환기 → Godot 네이티브 씬 (★채택)** | 의존성 0, 재생·블렌딩·프리뷰를 Godot 애니 시스템이 담당, region-only라 변환 깔끔 | 변환 도구 작성 필요, 본 계층·커브 변환 정확도 확보 필요 |
| 5 | 스프라이트 시트로 베이크(폴백) | 런타임 단순 | 베이크할 렌더러가 없음(닭-달걀), 부드러운 보간 손실 |

## 엔진 교체 검토 (왜 Godot 유지)

- 옛 포맷 거부는 **모든 엔진의 최신 spine 런타임 공통** → Godot 고유 결함 아님.
- 원작 엔진 Cocos2d-x의 옛 `spine-cocos2dx`(2.x/3.x)나 옛 `spine-ts`는 옛 런타임이 존재하나:
  ① 버전이 섞여 있어(2.x+3.0) 옛 런타임 하나로 일부만 커버 → 어차피 변환 필요,
  ② Cocos2d-x는 C++·구형 툴체인으로 무겁고 GDScript 편의·Godot 결정 포기,
  ③ **region-only라 자작 비용이 이미 충분히 낮음** → 옛 런타임의 이점 상쇄.
- ⇒ 알려진(이제 작아진) 문제를 큰 교체 비용과 맞바꾸지 않음. **Godot 유지.**

## 권장 → 채택

**옵션 4b(오프라인 변환기)** 로 확정. 의존성 없이 Godot 4.7에서 동작하며, region-only +
mesh/deform 0% 라 변환이 깔끔하고 Godot 네이티브 애니로 재생/블렌딩됨. plist 아틀라스를
텍스처 소스로 사용. **다음 단계(Phase 2)**: 우선 **idle(`wait`) 1종**만 변환·재생해
드래곤 1마리를 화면에 띄워 검증 → 이후 attack/damaged/critical 등으로 확장.
