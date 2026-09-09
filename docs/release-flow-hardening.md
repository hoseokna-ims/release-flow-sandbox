# 릴리스 플로우 안정화 설계 (release/hotfix/staging 스크립트 개선)

> 2026-07-29 imsform-mobile-web hotfix 0.49.0 사고(버전 bump 없이 0.48.0 재배포) 분석에서 도출된
> 릴리스 스크립트 전면 보완 설계. 모든 근거는 격리 하네스 실측으로 검증됨(§8 검증 계획 참고).
>
> 상태: **샌드박스 구현 완료** (2026-07-31, develop 반영) · `imsform-mobile-web` FE-2793 이식 대기
>
> - 구현·검증: 이 저장소(release-flow-sandbox)에서 단위별 PR로 진행
> - 최종 이식 대상: `imsform-mobile-web` **FE-2793** (PR 1개로 통합)
> - 이식 선례: [PR #1399](https://github.com/Rencar-dev/imsform-mobile-web/pull/1399)(FE-2714 초기 도입) ·
>   [PR #1418](https://github.com/Rencar-dev/imsform-mobile-web/pull/1418)(FE-2770 staging 리프레시)

---

## 1. 배경 — 무엇이 실패했나

### 1.1 사고 요약 (reflog 로 확정)

| 시각 | 사건 |
|---|---|
| 17:34 | `yarn staging:merge hotfix/0.49.0` → 스테이징 배포 성공. **HEAD 가 staging/0.48 에 잔류** |
| ~17:44 | `yarn hotfix finish` 시도(추정) → `❌ hotfix/* 브랜치에서 실행하세요` 로 중단 |
| 17:44:25 | hotfix/0.49.0 으로 수동 복귀 |
| 17:44:44 | **`git flow hotfix finish` 직접 호출** → bump·changelog 없이 master 머지 + 태그 + develop 되머지 |
| ~17:45 | master push → **prod 가 0.48.0(동일 버전)으로 재배포** — pre-push/CI 가드는 `patch==0` 만 검사해 통과 |
| 17:48~50 | develop 수습(reset ×2 + force push) → **develop 직접 커밋 1개 유실, 되머지 4건 유실** |
| 17:50~56 | `staging:new 0.50`(임의 override) → **staging 명령 상호 차단(데드락)** |

### 1.2 실측으로 확인된 구조적 문제

1. **`yarn hotfix finish` 가 bump 커밋 없이 중단되는 경로 21개** — 그중 10개는 검증이 bump *이후* 에 있어 늦게 실패하고, 5개는 워킹트리를 더럽힌 채 남아 재실행이 다른 에러로 튕김(2차 함정).
2. **git flow(nvie 0.4.1)의 원격 동기화 검사는 전부 무력** — `gitflow-common` 의 `has()` 헬퍼가 인용된 다중행 인자와 매칭 불가(`has "$ORIGIN/$BRANCH" "$(git_remote_branches)"` → 항상 false → `require_branches_equal` 블록 통째로 skip). behind/diverged 상태에서 경고 없이 머지 진행.
3. **finish 는 push 전에 브랜치를 삭제** — push 실패 시 재실행 불가 + 로컬 고아 태그가 남아 다음 버전 계산(`next-version.mjs` = max(태그, package.json))을 오염(0.49→0.50 건너뜀 사건).
4. **ahead(로컬 미푸시 커밋)는 어떤 구현도 검사하지 않음** — develop/master 의 미푸시 커밋이 조용히 릴리스·운영 배포에 포함됨. git-flow 계열 설계 자체가 "ahead 무해"(소스 주석) 입장이나, 이 리포에서는 유해.
5. **staging 명령 계열 결함** — `merge-staging` 브랜치 미복귀(사고 방아쇠), `deploy-staging` 옛 라인 가드 부재(스테이징이 옛 코드로 교체됨), `new-staging` 인자 무검증+막다른 메시지(데드락 유발), `push-tag.sh prod` 무가드(**아무 브랜치에서나 운영 배포 트리거 가능**).
6. **가드 부재** — pre-push/prod.yaml 은 `patch==0` 만 검사. "이미 존재하는 버전의 재배포", "태그 없는 배포(래퍼 우회)" 를 잡는 장치가 없음.

---

## 2. 설계 원칙

| # | 원칙 | 의미 |
|---|---|---|
| **P1** | **모든 검증은 첫 변경 전에** | preflight 단계에서 전부 검사. 하나라도 실패하면 아무것도 건드리지 않고 중단 (fail-fast, 부작용 0) |
| **P2** | **원격 반영 성공 전까지 로컬을 파괴하지 않는다** | 브랜치 삭제는 push 성공 후에만. 실패 시 태그·머지도 기준점으로 복원 |
| **P3** | **실패 시 상태 복원 + 메시지에 "다음 행동"** | 사용자 멘탈 모델은 항상 "원인 고치고 같은 명령 재실행" 하나. 모든 ❌ 메시지에 복사해 쓸 수 있는 다음 명령 1줄 포함 |

**메시지 스타일 기준** (기존 코드의 모범 사례 `merge-staging.sh` 사전검사를 표준으로):

```
❌ <무엇이 왜 안 되는지 한 줄>
   → <복사해 실행할 수 있는 다음 명령>
```

**아키텍처 결정: git flow 의존 제거 (B안)** — 2026-07-31 변경

> 최초 설계는 A안(`git flow ... finish -k` 위임 유지)이었다. 근거는 "팀이 쓰던 도구의 안정성·친숙함"
> 이었으나, 아래 사실 확인으로 그 전제가 성립하지 않아 B안으로 전환한다.

| 구현 | 리포 상태 | 마지막 커밋 | Homebrew |
|---|---|---|---|
| `nvie/gitflow` (현재 이 리포가 쓰는 것) | **archived** | 2025-10-14 | deprecated(2025-12-19) → **2026-12-19 제거 예정** |
| `petervanderdoes/gitflow-avh` (팀 다수가 쓰는 것) | **archived** | **2023-08-17** | **2026-03-05 formula 제거됨** |
| `git-flow-next` (Go 재구현) | 유지보수 중 | — | 설치 가능 (1.1.0) |

- `brew install git-flow-avh` 는 **이미 실패한다**(formula 없음). 신규 팀원 셋업이 이미 막혀 있다.
- 두 구현 모두 아카이브라 avh 로 통일해도 유지보수되는 도구로 가는 것이 아니다.
- 살아 있는 선택지는 `git-flow-next` 뿐인데, 세 번째 구현이라 어차피 재검증이 필요하다.
- `git flow ... finish` 가 하는 일은 checkout·merge·tag·merge·delete 다섯 단계뿐이고,
  동기화 검사는 이미 `scripts/lib/checks.sh` 가 직접 수행한다(§5).
- 의존을 끊으면 **도구 수명 · 에디션 불일치(`Merge tag` vs `Merge branch`) · 설치 마찰**이 한 번에 사라진다.

**구현 기준은 gitflow-avh 1.12.3** — 팀 다수가 avh 를 쓰므로 히스토리 모양을 avh 에 맞춘다.
소스에서 확인한 동작(nvie 와 다른 점):

| 단계 | avh 1.12.3 동작 |
|---|---|
| master 머지 | `git merge --no-ff <BRANCH>` (nvie 동일) |
| 태그 | master 체크아웃 후 `git tag -a -m <msg> <VERSION>` (nvie 동일) |
| **develop 되머지** | **태그를 머지**: `git merge --no-ff <TAG>` → `Merge tag 'X' into develop` |
| 되머지 skip 조건 | **master 가 develop 에 머지됐는지** (nvie 는 BRANCH 기준) |
| 삭제 전 checkout | release → master / hotfix → develop. 원격 먼저, 로컬 나중 |
| 동기화 검사 | **실제로 동작한다** — `git_remote_branch_exists` 가 `git for-each-ref` 를 직접 써서 nvie 의 `has()` 인용 버그가 없다 |

마지막 항목은 §1.2-2 의 정정이다: 동기화 검사 무력화는 **nvie 한정**이며 avh 에서는 동작한다.
다만 `ahead` 는 avh 에서도 `warn only` 이므로(소스 주석: *there is no harm in being ahead*)
미푸시 커밋이 릴리스에 섞이는 것은 어느 에디션도 막지 않는다 — 그래서 `checks.sh` 가 직접 확인한다.

---

## 3. 작업 목록 및 우선순위

| # | 샌드박스 브랜치 | 항목 | PR | 검증 | 상태 |
|---|---|---|---|---|---|
| 1 | `FE-1029` | `push-tag.sh` prod/staging 가드 + force-push (§4.1) | #26 | 11 | ✅ |
| 2 | `FE-1030` | `merge-staging` 브랜치 복귀 + `deploy-staging` 최신 라인 가드 (§4.2·4.3) | #27 | 17 | ✅ |
| 3 | `FE-1031` | `new-staging.sh` 인자 검증·선행 라인 차단·안내 개선 (§4.4) | #28 | 25 | ✅ |
| 4 | `FE-1032` | pre-push·prod.yaml **태그 정합성 가드** (§4.5) | #29 | 18 | ✅ |
| 5 | `FE-1033` | 공통 검사 라이브러리 + start 보강 (§5·6.2) | #30 | 39 | ✅ |
| 6 | `FE-1034` | **git flow 의존 제거** — avh 1.12.3 동등 직접 구현 (§6.1) | #31 | 35 | ✅ |
| 7 | `FE-1035` | **finish 4단계 재구성** — 사전검증·롤백·push 후 삭제 (§6.2·6.3) | #32 | 41 | ✅ |
| 8 | `FE-1036` | staging 안내 보강·빈 배포 확인·`CONTRIBUTING.md` (§6.4) | #33 | 20 | ✅ |
| 9 | `FE-1037` | 잔재 topic 브랜치 성격별 판정(잔재/진행중/오용) (§5) | #34 | 47 | ✅ |

**최종 통합 검증**: develop 기준 probe 8종 전건 재실행 **205/205 FAIL=0**, 사고 타임라인 재연 9개 지점 전부 의도대로(차단 5 · 통과 4).

### #6 과 #7 을 나눈 이유

성격이 다르다. 섞으면 diff 에서 "대체된 것"과 "바뀐 것"이 구분되지 않고, 문제 발생 시 원인 격리가
어려우며, postinstall 변경(팀 전체 셋업 영향)만 따로 되돌릴 수 없다.

| | 목적 | 성격 | 검증 질문 |
|---|---|---|---|
| **#6** | 의존성 제거 | **동등 대체** — 동작은 그대로 | "git flow 없이 똑같이 동작하는가" |
| **#7** | 실패 복구·재실행 안전 | **동작 변경** | "실패해도 복원되고 재실행되는가" |

**#6 은 알려진 결함도 그대로 둔다** — push *전* 브랜치 삭제, 실패 시 더러운 트리 잔류.
둘 다 #7 에서 고친다. 두 PR 사이 기간에 결함이 남지만 현재와 동일하므로 악화는 아니다.

---

## 4. 상세 설계 — 가드 계열 (#1~#5)

### 4.1 `push-tag.sh` — 배포 태그 가드 (#1)

**문제(실측)**: feature 브랜치에서 `sh scripts/push-tag.sh prod` 실행 시 feature HEAD 에 `prod` 태그가 push 되어 **운영 배포가 트리거**됨. `set -e` 없음. 원격 태그 삭제→재생성 사이 실패 시 태그 공백.

**설계**:

```bash
set -euo pipefail

# ENV 별 실행 컨텍스트 가드
case "$ENV" in
  prod)
    git fetch origin master --quiet
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/master)" ] || {
      echo "❌ prod 태그는 origin/master 최신 커밋에서만 푸시할 수 있습니다."
      echo "   → git switch master && git pull 후 다시 실행하세요."; exit 1; }
    VERSION=$(node -p "require('./package.json').version")
    [ "${VERSION##*.}" = "0" ] || { echo "❌ 운영 버전이 아닙니다: ${VERSION} (patch==0 필요)"; exit 1; }
    ;;
  staging)
    case "$(git rev-parse --abbrev-ref HEAD)" in staging/*) ;; *)
      echo "❌ staging 태그는 staging/* 브랜치에서만 푸시할 수 있습니다."; exit 1 ;; esac
    ;;
esac

# 삭제→재생성 대신 강제 갱신 (태그 공백 race 제거)
git tag -f "$ENV"
git push --force origin "refs/tags/$ENV"
```

### 4.2 `merge-staging.sh` — 원래 브랜치 복귀 (#2)

**문제(실측)**: 실행 후 HEAD 가 staging 에 잔류 → 직후 `yarn hotfix finish` 가 브랜치 검사에서 튕김 → **이번 사고의 방아쇠**.

**설계**: `refresh-staging.sh` 와 동일 패턴.

```bash
ORIG_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
restore_branch() { git switch "${ORIG_BRANCH}" >/dev/null 2>&1 || true; }
# ... 성공 경로 마지막과 charge-over 안내 직전에 restore_branch
# 단, 머지 충돌로 중단할 때는 복귀하지 않는다(사용자가 staging 위에서 해결해야 하므로)
```

충돌 중단 시에는 현재 동작(staging 에 남음)이 옳다 — 안내 메시지가 이미 "해결 → commit → staging:deploy" 흐름을 전제한다.

### 4.2.1 `merge-staging.sh` — 스테이징 경로 롤백 + 실패 원인 구분 (FE-1044)

**문제(실측, 2026-09 사건)**: `yarn staging:merge feature/FE-2996` 이 머지 → `0.61.5→0.61.6` bump
커밋까지 만든 뒤 `.husky/pre-push` 의 `tsc --noEmit` 5건으로 push 거부. **스크립트는 아무것도
되돌리지 않았고** 로컬 `staging/0.61` 이 7커밋 ahead 로 남아 사람이 `git reset --hard` 로 치웠다.

`release.sh`·`hotfix.sh` 는 §6.1 에서 Phase 롤백을 받았지만 **스테이징 경로는 받지 못했다.**
겹친 문제가 셋이다.

| # | 문제 | 결과 |
|---|---|---|
| 1 | ⑤ bump+commit 이후 실패에 복구 없음 | 머지·bump 커밋이 로컬에 잔류 |
| 2 | 모든 push 실패에 `원격이 앞섬 + git pull --no-rebase` 를 출력 | pre-push 거부에도 pull 을 유도 → 그 위에 `staging:deploy` 가 patch 를 또 올려 **버전이 두 번 오른다** |
| 3 | 중단(Ctrl-C/kill)에 대한 설계 없음 | 머지 커밋만 남고, 재실행하면 "머지로 추가된 새 커밋이 없습니다 — 빈 배포" 경고가 **오작동**해 사용자를 오해시킨다 |

**설계**

- **`record_baseline_ref` / `rollback_baseline_ref` 신규** (`checks.sh`). 기존
  `record_baseline`/`rollback_baseline` 은 `master`/`develop` 을 하드코딩하고 복원 시
  `git branch -f master`·`git tag -d` 까지 하므로 스테이징 경로에서 재사용할 수 없다 —
  여기서 움직이는 ref 는 `staging/<라인>` 하나뿐이고 토픽 브랜치도 버전 태그도 없다.
- **롤백 기준 SHA = `git pull` 이후의 staging tip.** pull 까지 되돌리면 재실행마다 다시 pull 해야
  하고 로컬이 origin 보다 뒤처진 채 남는다. §6.1 의 "시작 시점 로컬 SHA" 근거(preflight 에서
  승인받은 ahead 를 보존한다)는 스테이징에 없다 — 스테이징 경로엔 ahead 승인 절차가 없다.
- **push 실패 원인은 메시지 문구가 아니라 '상태' 로 판정한다** (git 로케일·버전 무관). 실측 결과:

  | 원인 | `git push --no-verify --dry-run` | 원격 tip 이 HEAD 의 조상 | 안내 |
  |---|---|---|---|
  | ⓐ pre-push 훅 거부 | **성공** | 예 | 원인 수정 후 **재실행**. `git pull` 을 안내하지 않는다 |
  | ⓑ non-fast-forward | 실패 | 아니오 | 원격 선행 — 재실행이 `git pull` 로 받아온다 |
  | ⓒ 그 외(네트워크·권한) | 실패 | 예 | 위 출력 확인 후 재실행 |

  ⓐ 에서 dry-run 이 성공한다는 것은 "원격은 도달 가능하고 fast-forward 도 가능하다" 는 뜻이므로
  `git pull` 은 애초에 무의미하다. 두 원인을 뭉갠 것이 위 표의 문제 2 였다.
- **빈 배포 판정에 재실행 예외.** 머지로 추가된 새 커밋이 0 이어도 **미푸시 커밋이 남아 있으면**
  그건 '이미 반영된 브랜치' 가 아니라 중단된 실행이 만든 머지 커밋이다(`set -e` 의 ERR 트랩은
  시그널에 걸리지 않는다 — §6.1.1). 재개로 안내한다. 미푸시 **bump** 커밋이 섞여 있으면 재개로
  보지 않는다 — 그건 ⑥ 이후에서 죽은 상태이고 이어서 bump 하면 버전이 두 번 오른다(FE-1046 범위).

**최종 HEAD 위치** — §4.2 의 "중단 경로에서는 복귀하지 않는다" 는 롤백 도입으로 근거가 셋으로 갈린다.

| 경로 | HEAD | 근거 |
|---|---|---|
| 성공 · 롤백까지 끝난 실패 | `ORIG_BRANCH` | 되돌린 staging 위에 남을 이유가 없다. staging 잔류는 사고 방아쇠(§1.1) |
| 머지 충돌 | staging 잔류 | 충돌 해결·커밋을 staging 위에서 이어가야 한다 |
| 배포 트리거 태그 push 실패 | staging 잔류 | 안내하는 `scripts/push-tag.sh staging` 이 `staging/*` 브랜치를 요구한다 |

**⑦ 태그 push 실패는 롤백하지 않는다** (티켓 초안에서 수정). 그 시점에 `${LATEST}` 는 **이미 원격에
반영됐다.** 되돌리면 로컬이 origin 보다 뒤처져 다음 실행이 그 커밋을 다시 pull 한 뒤 patch 를 또
올린다 — 고치려던 이중 bump 를 스스로 만든다. 남은 일은 태그 하나뿐이므로 그것만 다시 밀게 한다.

> `deploy-staging.sh` 헤더의 "(운영형 버전 퇴행 복구 자동 포함)" 은 실제 코드에 없어 함께 지웠다.

**검증**: `scripts/test/staging-rollback.sh` 67건. 음성 대조(수정 전 `7586374` 를 `SRC`) → 신규 30건 실패,
회귀 케이스(R7 머지 충돌·R8 정상 완주)는 양쪽 통과. 수정 전 R1 재현 상태가 사건과 일치한다
(미푸시 3커밋 · 버전 이미 0.1.1 · HEAD staging 잔류).

### 4.2.2 로컬 `staging/*` ahead 가드 (FE-1045)

**문제(실측)**: `merge-staging.sh` 의 사전검사는 **대상 브랜치**의 미푸시 커밋만 본다. 로컬
`staging/*` 자체는 아무도 보지 않으며, `git pull origin <staging>` 은 ahead 상태를
fast-forward 로 조용히 통과시킨다. `deploy-staging.sh` 도 clean tree 만 본다.
§5.1 의 ahead 정책이 **release/hotfix 전용으로만** 적용돼 있었다.

결과: 사람이 `staging/*` 에 직접 만든 커밋이 리뷰·CI 없이 배포되고, 사고 잔여 상태
(로컬 staging 이 ahead)에서 재실행하면 그 위에 또 bump 가 얹혀 미푸시 bump 커밋이 한 번에
push 된다. 수정 전 실측: 사용자 커밋이 bump 와 함께 원격에 올라가고(A1), 재실행 2회로
버전이 `0.1.0 → 0.1.3` 까지 뛴다(A3).

**설계** — `require_staging_synced <branch> [pull|block]` 신규.

`require_synced` 를 그대로 쓰지 않는 이유는 **behind 처리가 반대**이기 때문이다.
release/hotfix 는 behind 를 차단해야 하지만 `merge-staging.sh` 는 곧바로 `git pull` 한다 —
behind 차단을 그대로 쓰면 "원격이 앞선 staging 에 머지" 라는 정상 플로우가 전부 막힌다.
그래서 behind 정책을 호출부가 정한다.

| 호출부 | 위치 | behind | 근거 |
|---|---|---|---|
| `merge-staging.sh` | `git switch` 전 (=첫 변경 전) | `pull` — 통과 | 바로 아래 `git pull` 이 받아온다 |
| `deploy-staging.sh` | bump 전 | `block` — 차단 | pull 하지 않으므로 push 가 반드시 거부된다. 첫 파괴적 변경 전에 잡는다(P1) |

`require_synced` 와 달리 **로컬 브랜치가 없으면 통과**시킨다 — 새 클론에서 첫 배포를 하면
로컬 `staging/*` 이 없고 `git switch` 가 origin 에서 만든다. 그대로 재사용하면
"❌ 로컬 브랜치가 없습니다" 로 죽는다(A7).

**예외 판정 `staging_ahead_is_ours`** — §5.1 의 `is_resumed_finish` 와 같은 방식으로,
first-parent 체인의 **모든** 커밋이 아래 둘 중 하나여야 하고 하나라도 어긋나면 차단한다.

| 조건 | 배제하는 오인 |
|---|---|
| `Merge branch '<X>' into <BR>` 형식 + **2번째 부모가 origin 의 어느 remote-tracking 브랜치에서 도달 가능** | 미푸시 로컬 브랜치를 머지한 커밋 — 그 작업이 묻어 나간다(A9b) |
| `chore: staging deploy <ver>` + `<ver>` 가 `<BR>` tip 의 `package.json` 과 일치 | 사람이 형식만 흉내낸 커밋(A9) |

2번째 부모로 들어온 커밋들은 첫 조건이 보증하므로 first-parent 체인만 본다. 버전은 워킹트리가
아니라 `<BR>` tip 에서 읽는다 — `merge-staging.sh` 는 staging 으로 switch 하기 전에 호출한다.

**머지 커밋을 예외에 포함한 이유**: §4.2.1(FE-1044)의 재개 경로가 만드는 상태가 정확히
"미푸시 머지 커밋" 이다. bump 커밋만 예외로 두면 그 재개 경로가 죽는다(A8 = R5 회귀).

**예외에도 목록 + 확인을 거친다**(§5.1 과 동일). 그래서 §4.2.1 의 중단 후 재실행은 이제
확인 프롬프트를 한 번 지난다 — 비대화형에서는 `RELEASE_ASSUME_YES=1` 이 필요하다.

> **A3 의 이중 bump 는 격차가 아니다** (FE-1046 에서 결론). 그 경로는 미푸시 bump 위에
> **새 머지가 얹히므로 내용이 달라진다** — 여기서 bump 를 건너뛰면 이전 버전 시점에 생성된
> `STAGING_CHANGELOG.md` 가 그대로 배포되어 새 내용이 누락된다. 배포된 적 없는 patch 번호
> 하나를 소비하는 편이 낫다. §4.2.3 이 닫은 것은 **내용이 그대로인데 두 번 오르는** 경우다.

**검증**: `scripts/test/staging-ahead.sh` 60건. 음성 대조(FE-1045 직전 `7acbdcc` 를 `SRC`)
→ 신규 26건 실패, 회귀 케이스(A4 ahead 없음 · A6 behind · A7 새 클론)는 양쪽 통과.

### 4.2.3 스테이징 bump 멱등화 (FE-1046)

**문제**: 두 스크립트 모두 실행마다 **무조건** `patch +1` + `chore: staging deploy <ver>`
커밋을 만들었다. 그런데 같은 내용을 다시 올리는 경로가 둘 있다.

| 경로 | 결과 |
|---|---|
| `merge-staging.sh` 의 실패 안내가 "`staging:deploy` 로 마무리" → 그대로 따른다 | patch 가 한 번 더 오른다. `0.61.6` 은 배포된 적 없이 소멸 |
| ⑥ push 도중 시그널(Ctrl-C·크래시)로 죽어 미푸시 bump 커밋이 남는다 | 재실행이 **같은 내용에** patch 를 또 올린다 (§4.2.1 이 재개 대상에서 제외해 둔 경로) |

측정(수정 전): `staging:deploy` 재실행 → `0.1.1` 이 아니라 `0.1.2`. `staging:merge` 재실행
→ `0.1.3`.

**설계 — 판정 `staging_unpushed_bump <BR>`**

`origin/<BR>..<BR>` 의 first-parent 체인에서 아래 **넷을 모두** 만족하는 커밋을 찾는다.
있으면 bump·changelog·커밋을 건너뛰고 push 로 진행한다.

| 조건 | 배제하는 오인 |
|---|---|
| 제목이 `chore: staging deploy <ver>` 와 정확히 일치 | 다른 커밋 |
| `<ver>` 가 `<BR>` tip 의 `package.json` 과 일치 | 사람이 다른 버전으로 흉내낸 커밋 (D3b) |
| 미푸시 — `origin/<BR>..<BR>` 범위 안 | 이미 배포된 지난 bump. 그걸 재실행으로 보면 의도한 재배포가 막힌다 (D4) |
| 그 커밋이 실제로 version 을 `<ver>` 로 올렸다(부모의 버전이 다르다) | 빈 커밋·제목만 흉내낸 커밋 (D3c) |

`HEAD` 가 bump 커밋인지로 좁게 보면 실제 후속 경로를 놓친다 — 안내대로 `git pull` 을 먼저 하면
머지 커밋이 위에 얹혀 `HEAD` 가 bump 커밋이 아니게 된다(D6). 그래서 **범위 검색**이다.
first-parent 로 한정하는 이유는 우리 bump 커밋이 항상 staging 의 first-parent 위에 있고
(`git pull` 의 머지도 1번째 부모가 로컬 쪽이다) 머지로 들여온 남의 커밋을 잡지 않기 때문이다.

**`merge-staging.sh` 에는 조건이 하나 더 붙는다** — 머지가 새 커밋을 추가하지 않았을 때만
건너뛴다. 규칙으로 쓰면 *"push 할 트리가 그 bump 커밋이 기술한 그대로일 때만 건너뛴다."*
새 머지가 얹혔다면 내용이 달라졌으므로 그대로 bump 한다 — 그래야 `STAGING_CHANGELOG.md` 가
실제 배포 내용과 맞는다(D8). 배포된 적 없는 patch 번호 하나를 소비하는 것은 스테이징 라인에서
무해하지만, 배포된 changelog 가 내용을 빠뜨리는 것은 그 파일의 유일한 용도를 깨뜨린다.

**§4.2.2 의 판정을 제목 기반에서 부모 기반으로 바꿨다.** `staging_ahead_is_ours` 는 머지 커밋을
`Merge branch '<X>' into <BR>` 제목으로 알아봤는데, `git pull` 이 만드는 머지는
`Merge branch '<X>' of <url>` 로 형식이 달라 **D6(정상적인 pull 후 재실행)이 차단됐다**(실측).
지키려는 불변식은 제목이 아니라 *"새로 나가는 내용은 이미 origin 에 있는 것뿐"* 이므로,
**1번째를 뺀 모든 부모가 origin 에서 도달 가능한지**로 판정한다. 형식과 무관하게 같은 보증을
주고, 로컬에만 있는 브랜치를 머지한 커밋은 그대로 걸러진다(A9b 유지).

**부수 정리**: `[ -f package-lock.json ] && git add package-lock.json` 은 이 리포(yarn)와
imsform(Yarn Berry) 양쪽에 존재하지 않아 죽은 코드였다 — 두 스테이징 스크립트에서 제거했다.
`changelog.mjs` 의 노이즈 필터
`/^chore:\s*(staging deploy|release|hotfix)\s+v?\d+\.\d+\.\d+\b/i` 가 커밋 메시지 형식에
의존하므로 형식은 바꾸지 않았다(#32 리뷰 요청 사항).

**검증**: `scripts/test/staging-idempotent.sh` 56건. 음성 대조(FE-1046 직전 `fd52a1f` 를 `SRC`)
→ 신규 13건 실패, 회귀·음성 판정 케이스(D2·D3b·D3c·D4·D5·D7b·D8)는 양쪽 통과.
수정 전 D6 는 **차단(exit=1)** 된다 — 위 제목 기반 판정의 결함이 그대로 드러난다.

### 4.2.4 설치 정합성 사전검사 (FE-1047)

**문제(실측)**: 사고에서 `tsc --noEmit` 이 5건 실패했는데 **4건은 코드 결함이 아니었다.**
로컬 설치본이 `react 18.3.1` / `@types/react 18.3.28` 인데 `staging/0.61` 은
`next 16.2.12` / `react ^19` / `@types/react ^19` 였다. 사용자는 자기 코드가 5군데
깨졌다고 읽고 그걸 고치려 든다. 아무 스크립트도 이를 확인하지 않았다.

§1.2 의 라인 스큐가 상시 조건이므로(#1464·#1468 이 develop 머지 대상이 아니다) 이 오인은
1회성이 아니라 반복 조건이다. 앞의 세 티켓이 *"실패했을 때 안전한가"* 를 다뤘고 이 티켓은
*"왜 실패했는지 오인하지 않는가"* 를 다룬다.

**`yarn install --immutable` 은 해법이 아니다.** `yarn install --help` 그대로
*"Abort with an error exit code if the lockfile was to be modified"* — **락파일이 바뀔 때만**
실패한다. `node_modules` 가 어긋나면 보고하지 않고 링크 단계를 실행해 조용히 고친다(exit 0).
즉 진단하지 못하면서 배포 스크립트가 install 을 시작하는 결과가 된다.
`node_modules/.yarn-state.yml` 에도 락파일 체크섬이 없다(`grep -ic checksum` → 0).
Yarn 4 에 읽기 전용 정합성 판정의 1급 수단이 없다.

**설계 — `scripts/check-install-sync.mjs` (읽기 전용, node 만 사용)**

`package.json` 의 `dependencies`/`devDependencies` 각 항목에 대해 `yarn.lock` 의 resolution
버전과 `node_modules/<pkg>/package.json` 의 실제 버전을 대조하고, 불일치 목록과 함께
non-zero 로 종료한다. 외부 명령은 `git show origin/develop:package.json` 하나뿐이다.

**yarn 을 호출하지 않는 것이 하드 제약이다** — 하네스 픽스처에는 yarn 도 `.yarnrc.yml` 의
`yarnPath` 도 없고 셔임은 git 하나뿐이다. 픽스처가 부를 수 있는 것은 `node` 뿐이다(E10 이 고정).

**락파일 형식 둘을 모두 다룬다.** 이 저장소는 yarn 1, imsform 은 Berry v8 이다 — 형식을
하나만 다루면 이식본에서 검사가 **조용히 무력화**된다.

| | descriptor | version 줄 |
|---|---|---|
| yarn 1 | `"left-pad@^1.0.0":` | `  version "1.3.0"` |
| Berry v2+ | `"left-pad@npm:^1.0.0":` | `  version: 1.3.0` |

실측으로 파서가 공허하지 않음을 확인했다 — imsform 의 선언 **84개 전부** 락파일에 매칭된다
(`react = 19.2.8`, `next = 16.2.12`).

**호출 위치: `git switch` + `git pull` 이후, `git merge` 이전.**

이 문제의 핵심은 **원인과 증상이 다른 단계에 있다**는 것이다. imsform-mobile-web 의 훅 실물을
기준으로 어디서 무엇이 도는지 확정해 둔다(`.husky/pre-commit`·`.husky/pre-push` 실측).

```
② git switch staging/0.61 + git pull      ← 원인(스큐)이 여기서 '생긴다'
③ [설치 정합성 검사]                       ← 여기서 '잡는다'
④ git merge --no-ff                        훅 없음
⑤ git commit  chore: staging deploy <ver>  pre-commit → no-op
⑥ git push → pre-push → yarn tsc --noEmit  ← 증상이 여기서 '나타난다'  ★
⑦ bash scripts/push-tag.sh staging
```

| 단계 | 도는 훅 | 실제로 실행되는 것 |
|---|---|---|
| ④ 머지 커밋 | — | 아무것도. git 은 머지 커밋에 `pre-merge-commit` 을 쓰고 imsform 엔 그 훅이 없다 |
| ⑤ bump 커밋 | `pre-commit` | 아무것도. 훅이 `git diff --cached \| grep -E '\.(js\|jsx\|ts\|tsx)$'` 로 걸러서 통과한다 — staged 는 `package.json`·`CHANGELOG.md`·`STAGING_CHANGELOG.md` 뿐이다 |
| ⑥ push | **`pre-push`** | **`yarn tsc --noEmit`** → 실패 시 중단. 그다음 `yarn test`(vitest), 그다음 태그 가드(#39·#40) |

즉 **eslint 는 이 경로에서 아예 돌지 않는다**(`lint-staged` 는 `pre-commit` 전용). 사고에서
5건을 낸 것은 `pre-push` 의 `tsc --noEmit` 이다. ②에서 이미 깨진 상태인데 ⑥까지 아무도
모르고, 그 사이에 커밋 2개(머지·bump)가 생긴다.

> 예외: **머지 충돌을 손으로 해결하고 `git commit` 하는 경로**는 다르다. 충돌 파일이
> `.tsx` 면 `pre-commit` 이 `eslint --fix` + `prettier --write` 를 돌린다. 그 커밋은
> 스크립트가 아니라 사용자가 만드는 것이라 이 설계의 대상이 아니다.

②와 ⑥ 사이 어디에 둘지가 유일한 선택지이고, ③을 고른 이유는 둘이다.

| | ③ 에 두면 | ⑥ 메시지만 개선하면 |
|---|---|---|
| 오해를 부르는 tsc 출력 | **아예 나오지 않는다** | 일단 보고 나서 설명을 읽는다 |
| 되돌릴 커밋 | 0개 (아직 만들지 않았다) | 2개 (§4.2.1 의 롤백이 처리) |

P1(모든 검사는 첫 변경 전에)과도 맞고, §4.2.1 과 짝이 된다 — **설치가 맞은 상태에서 ⑥ 이
실패하면 그건 진짜 결함**이므로 그때는 "pre-push 훅 거부 → 원인 수정 후 재실행" 안내가
정확해진다.

Phase 0(switch 전)에 두면 이번 사고를 못 잡는다 — develop 라인 브랜치에서 실행하면 그 시점
`package.json`·락파일과는 일치하므로 통과하고, 스큐는 switch 직후에 발생한다
(E6 이 양쪽을 다 확인한다: 작업 브랜치에서 직접 실행 → 통과, 같은 상태의 `staging:merge` → 차단).

**⑥ 에서 tsc 가 실패하는 원인은 세 종류이고 이 티켓이 닫는 것은 하나다.**

| 원인 | 사고 당시 | 이 티켓 |
|---|---|---|
| ① 설치본 스큐 (`react 18.3.1` vs 라인의 `^19` → `LegacyRef` 시그니처 변경) | **4건** | **✅ ③ 에서 차단 + 불일치 목록** |
| ② 진짜 코드 결함 (`noUncheckedIndexedAccess`) | 1건 | ❌ 당연히. §4.2.1 이 안전하게 롤백하고 재실행으로 안내 |
| ③ `generate:routes` 산출물 stale (`CONTRACT_DRIVING_EVALUATION_CONTRACT_ID` 없음) | 잠재(실측 재현) | ❌ **미해결** — 아래 |

③ 도 코드 결함이 아닌 환경 문제이고 같은 위치에서 같은 오인을 만든다. 산출물 3개가 모두
gitignore 라 라인을 전환해도 이전 라인의 것이 그대로 남는다. 이 티켓에서 뺀 이유는 읽기 전용
판정이 불가능하기 때문이다 — 최신성을 확인하려면 생성기를 돌려야 하고 그건 (a) 쓰기 작업이며
(b) `yarn` 호출이라 위 하드 제약을 깬다. P1 의 `CONTRIBUTING.md` 에 "라인 전환 후
`yarn install` + `yarn generate:routes`" 를 적는 것으로 대응한다. 스크립트로 닫으려면
별도 티켓이 필요하고, 그때 설계의 핵심은 "생성물 최신성을 어떻게 읽기 전용으로 판정하느냐" 다.

**차단 시 HEAD 는 staging 에 남긴다.** §4.2.1 의 "롤백까지 끝난 실패는 `ORIG_BRANCH` 복귀"
규칙의 예외다 — 안내하는 `yarn install` 이 **이 라인의 락파일** 기준으로 돌아야 하고,
`ORIG_BRANCH` 로 되돌리면 develop 라인 의존성을 설치하게 된다.

**오탐을 만들지 않는다.** 이 검사는 배포 경로를 차단하므로 오탐이 곧 배포 차단이고, 그러면
사람이 `RELEASE_ASSUME_YES` 나 `HUSKY=0` 으로 도망가 #39·#40 의 태그 가드까지 함께 꺼진다.
그래서 **판정할 수 있는 것만 판정한다.**

| 상황 | 처리 |
|---|---|
| `yarn.lock` 없음 · `.pnp.cjs` 있음 | 조용히 통과 — 비교 기준이 없다(하네스 픽스처가 이 조건이다) |
| 락파일에서 선언을 찾지 못함 | **차단하지 않고** "판정하지 않은 N건" 만 알린다. 대개 락파일이 낡은 것이다(실측: 이 저장소의 `husky@9.0.2` 가 `yarn.lock` 에 없다) |
| 라인 의존성 격차(develop 과 선언이 다름) | **차단하지 않고** 정보성 한 줄. 두 라인이 크게 어긋난 시기에는 상시 성립해서(실측 17건) 확인을 걸면 매 배포가 confirm 이 된다 |
| 설치본 ≠ 락파일 · `node_modules` 없음 | **차단** + 목록 + `yarn install` |

라인 격차 안내의 목적은 행동 지시가 아니라 **감각 교정**이다 — "pre-push 의 타입 검사가
실패하면 내 코드가 아니라 라인 차이일 수 있다" 를 미리 알려주는 것이 사고의 오인을 막는다.

**`deploy-staging.sh` 에는 넣지 않았다.** 그 스크립트는 라인을 전환하지 않으므로 스큐를
*만들지* 못한다. 넣으면 폴백 배포가 라인 전환과 무관한 조건에 걸리게 된다. 필요하면 한 줄이다.

**생성물(`generate:routes`) 갱신은 범위 밖이다.** 산출물은 모두 gitignore 이고 검증을
스크립트에 넣지 않기로 했으므로(§보류) pre-push 가 계속 담당한다. P1 의 `CONTRIBUTING.md` 에
"라인 전환 후 `yarn install` + `yarn generate:routes`" 를 적는다.

**성능 — 지배 비용은 네트워크 fetch 다** (실측, imsform → GitHub).

| 단계 | 비용 |
|---|---|
| `git fetch` 1회 | **2.3~3.2초** |
| `check-install-sync.mjs` 전체 | 0.04초 (node 시작 0.015 + 락파일 435KB 파싱 0.0009 + `git show` 0.01) |
| `git branch -r --contains` (원격 브랜치 1186개 · 커밋 9095개) | 0.01초. `staging_ahead_is_ours` 안에서 ahead > 0 일 때만 돈다 |

그래서 FE-1044~1047 이 추가한 로컬 검사들은 전부 합쳐도 fetch 1회의 2% 미만이다.
반대로 **§4.2.2 가 `deploy-staging.sh` 에 넣은 단일 refspec fetch 는 정상 경로에서 최신 라인
가드의 `git fetch --prune` 과 중복돼 매 배포에 ~2.4초를 더하고 있었다** — `--force` 경로
(최신 라인 가드를 건너뛰므로 fetch 도 건너뛴다)에서만 하도록 고쳤다. `--force` 에서도 fetch 가
빠지지 않는지는 `staging-ahead.sh` A6c 가 고정한다(behind 를 놓치면 실패한다).

**검증**: `scripts/test/staging-install-sync.sh` 54건 + `staging-ahead.sh` A5b·A6c(`--force`
경로) 2건. 음성 대조(FE-1047 직전 `827edd3` 를 `SRC`) → 신규 22건 실패, 회귀 케이스
(E2 일치 · E4 문구 부재 · E8b Berry 일치 · E9 락파일 없음 · E9b PnP)는 양쪽 통과.

### 4.2.5 이식이 드러낸 것들 — imsform 역이식 (FE-1048)

FE-1044~1047 을 `imsform-mobile-web` 에 이식하면서 네 가지가 드러났다. 셋은 이 저장소의 결함이고
하나는 이식 과도기에만 생기는 조건인데, 신규 스크립트를 추가할 때마다 재발하므로 여기서 닫는다.

**① switch 이후 실행되는 리포 파일은 그 라인에 없을 수 있다**

`merge-staging.sh` 는 실행 도중 `git switch "${LATEST}"` 로 staging 라인으로 넘어간다. 그 이후에
호출하는 리포 파일(`node scripts/*.mjs`, `bash scripts/*.sh`)은 **전환된 라인의 판**이다. 신규
스크립트는 아직 그 라인에 머지되지 않았으므로 존재하지 않는다.

실측(imsform, 2026-09): 이식 커밋이 feature 브랜치에만 있는 상태로 `yarn staging:merge` 를 돌리자
`check-install-sync.mjs` 가 `MODULE_NOT_FOUND`(exit 1)로 죽었고, 호출부가 그것을 '설치 스큐' 로
오인해 `yarn install` 을 안내했다 — 설치로는 고쳐지지 않는 문제인데도.

- **존재 가드 + 경고 한 줄 후 계속.** 차단은 답이 아니다 — 그 파일을 추가하는 이식 머지 자체가
  영원히 막힌다(닭-달걀). 무음 skip 도 아니다: 가드 없이 배포된다는 사실은 보여야 한다.
- 전환 **전에** source 되는 `scripts/lib/checks.sh` 는 메모리에 있으므로 이 규칙의 대상이 아니다.

**② 검사기 종료 코드 계약 — `0` / `3` / 그 외**

node 는 예외·문법 오류·`MODULE_NOT_FOUND` 를 **모두 exit 1** 로 끝낸다(공식 문서: *"By default,
Node.js prints the stack trace to stderr and exits with code 1"*; 핸들러를 달면 종료 코드를
바꿀 수 있다). 스큐 판정을 1 로 두면 "검사기가 깨진 경우" 와 구분되지 않아, 검사기가 고장 나도
사용자가 `yarn install` 을 안내받고 헛수고한다.

| 코드 | 뜻 | 호출부 |
|---|---|---|
| `0` | 이상 없음(또는 판정 대상 아님) | 계속 |
| `3` | 스큐 확정 | `yarn install` 안내 후 차단 |
| 그 외 | 검사기 자체 실패 | "설치 문제가 아니다" 안내 후 차단 |

`check-install-sync.mjs` 는 `uncaughtException` 을 잡아 exit 2 로 끝내고, node 가 그냥 죽는 경우(1)도
같은 분기로 흐른다.

**③ `deploy-staging.sh` 의 비대칭 해소**

FE-1044 는 `merge-staging.sh` 만 고쳤다. `deploy-staging.sh` 에는 모든 push 실패에
`원격이 앞섬 + git pull --no-rebase` 를 출력하는 옛 문구가 남아 있었다 — 이중 bump 를 유도했던
바로 그 문장이다(FE-1046 의 멱등화로 피해는 닫혔지만 진단은 여전히 틀린다). 또 FE-1047 이
"deploy 는 라인을 전환하지 않으므로" 설치 검사를 제외했는데, 사용자는 `git switch staging/<라인>` 을
손으로 한 뒤 이 명령을 실행한다 — 같은 스큐원이다. 둘 다 merge 쪽과 동일하게 맞춘다.

**④ push 실패 판정에서 dry-run 은 마지막 폴백이다**

`git push --dry-run` 은 ref 를 실제로 보내지 않으므로 **원격 `pre-receive` 훅·브랜치 보호가 돌지
않는다.** 즉 원격이 거부하는 상황에서도 탐침은 성공하고, 그것을 로컬 훅 실패로 오분류한다.
`--no-verify` 는 문서상 **클라이언트 pre-push 만** 우회한다.

판정 순서를 값싸고 확실한 신호부터로 바꾼다:

1. `remote rejected` · `pre-receive hook declined` · `protected branch` → 원격 거부 확정
2. `husky - pre-push` 마커 → 로컬 훅 거부 확정
3. dry-run(`--no-verify`) 탐침 → 성공하면 로컬 훅
4. 원격 tip 이 계보 밖 → non-fast-forward
5. 그 외

**⑤ bump 커밋 판정에 경로를 넣는다**

`staging_ahead_is_ours` 의 bump 분기가 제목만 봤다. 제목·버전만 맞춘 커밋에 애플리케이션 변경을
얹으면 '우리 것' 으로 승인돼, 리뷰·CI 를 거치지 않은 코드가 확인 프롬프트 하나만 지나 배포된다.
제목은 흉내낼 수 있어도 **무엇을 바꿨는가는 흉내낼 수 없으므로** 경로로 확정한다 —
`package.json`·`package-lock.json`·`CHANGELOG.md`·`STAGING_CHANGELOG.md` 밖의 경로가 하나라도
있으면 거부한다(`staging_unpushed_bump` 도 같은 조건을 받는다). 부수 효과로 빈 커밋도 걸린다.

**검증**: 하네스 360 → **391건**. 신규 A11·A11b(경로 검사) · R11(원격 거부 분류) · E11·E12·E12b
(존재 가드·종료 코드) · B6(실행 중 switch 와 스크립트 자기 자신). imsform 쪽에서 동일 391건으로
먼저 검증한 뒤 역이식했다.

> **되돌리지 않은 것**: imsform 에는 `merge-staging.sh` 에 라우터 생성물 재생성 단계가 있다
> (`plugins/routePathGenerator.mjs`, gitignore 된 생성물이라 라인 전환 시 낡은 채로 남는다).
> 이 저장소에는 생성기가 없어 죽은 코드가 되므로 가져오지 않았다. ① 의 규칙만 공유한다.

### 4.3 `deploy-staging.sh` — 최신 라인 가드 (#3)

**문제(실측)**: 옛 라인 `staging/0.20` 체크아웃 상태에서 실행하면 그대로 배포되어 **`staging` 태그가 옛 코드로 이동** (스테이징 서버 교체).

**설계**: `merge-staging.sh:36-52` 의 최신 라인 산출 + 불일치 가드를 그대로 복제. 현재 브랜치 ≠ 최신 staging 라인이면:

```
❌ 현재 브랜치(staging/0.20)는 최신 staging 라인(staging/0.26)이 아닙니다.
   옛 라인을 배포하면 스테이징 서버가 옛 코드로 교체됩니다.
   → git switch staging/0.26 후 다시 실행하세요.
```

의도적 옛 라인 배포가 필요한 경우를 위해 `--force` 플래그 허용(명시적 opt-in).

### 4.4 `new-staging.sh` — 3겹 개선 (#4)

**문제(실측, 0.50 사건 재현)**: ① "이미 존재합니다" 메시지가 막다른 골목 → 사용자를 임의 override 로 유도 ② override 인자 무검증(`staging/banana` 생성됨, develop 라인과 무관한 `0.27` 도 통과) ③ 선행 라인 생성 시 `staging:merge`·`staging:new` 가 상호 차단(데드락).

**설계**:

```bash
# ① 인자 형식 검증 (스크립트 초입)
if [ -n "${1:-}" ]; then
  [[ "$1" =~ ^[0-9]+\.[0-9]+$ ]] || { echo "❌ 라인 형식이 아닙니다: '$1' (예: 0.26)"; exit 1; }
  # develop 라인과 다르면 경고 + 명시적 확인
  if [ "$1" != "${DEV_VERSION%.*}" ]; then
    echo "⚠️  develop 은 ${DEV_VERSION%.*} 라인인데 $1 을 지정했습니다."
    echo "   develop 과 다른 라인은 staging:merge 가 차단되는 데드락을 만듭니다."
    printf "   정말 계속할까요? [y/N] "; read -r A; [ "$A" = y ] || exit 1
  fi
fi

# ② "이미 존재" 메시지에 다음 행동
echo "❌ ${BRANCH} 가 이미 존재합니다."
echo "   → 작업을 올리려면: (작업 브랜치에서) yarn staging:merge"
echo "   → 라인을 다시 만들려면: git push origin --delete ${BRANCH} 후 재실행"

# ③ 데드락 감지: 최신 staging 라인 > develop 라인이면 선행 라인으로 판정
if [ -n "${LATEST}" ] && [ "$(printf '%s\n%s' "${LATEST#staging/}" "${DEV_MINOR}" | sort -t. -k1,1n -k2,2n | tail -1)" != "${DEV_MINOR}" ]; then
  echo "⚠️  최신 staging(${LATEST})이 develop(${DEV_MINOR}) 보다 앞선 라인입니다 — 선행 라인입니다."
  echo "   → 배포 이력이 없다면 삭제하세요: git push origin --delete ${LATEST}"
fi
```

동일한 데드락 감지·안내를 `merge-staging.sh` 의 라인 불일치 가드에도 추가한다(현재는 "staging:new 하세요" 라고 안내하지만 staging:new 도 막히는 상황이 존재).

### 4.5 pre-push · prod.yaml — 태그 정합성 가드 (#5)

**문제**: 현행 가드는 `patch==0` 만 검사 → ① 동일 버전 재배포(이번 사고) ② 래퍼 우회(태그 없는 배포) ③ 수동 머지 배포를 전부 통과시킴. **이번 사고를 잡을 수 있었던 유일한 지점.**

**설계** — master 로 나가는 커밋은 "자기 버전과 같은 이름의 태그가 자신을 가리켜야 한다":

`.husky/pre-push` (기존 patch==0 검사에 추가):

```sh
if [ "$remote_ref" = "refs/heads/master" ]; then
  VERSION=$(node -p "require('./package.json').version")
  # (기존) patch==0 검사 ...
  TAG_SHA=$(git rev-parse -q --verify "refs/tags/${VERSION}^{commit}" || true)
  if [ -z "$TAG_SHA" ]; then
    echo "❌ 태그 ${VERSION} 이 없습니다 — 정상 릴리스 플로우(yarn release/hotfix finish)를 통해 푸시하세요."
    exit 1
  fi
  if [ "$TAG_SHA" != "$local_sha" ]; then
    echo "❌ 태그 ${VERSION} 은 다른 커밋을 가리킵니다 — 버전 bump 없는 재배포이거나 태그 불일치입니다."
    exit 1
  fi
fi
```

`prod.yaml` Version guard 스텝에 동일 검사 추가(CI 이중화, `fetch-depth: 0` + `fetch-tags: true` 필요).
`yarn release/hotfix finish` 는 `--atomic` 으로 master 와 태그를 함께 밀므로... **주의**: pre-push 시점에 태그는 로컬에 존재하고 `local_sha` 와 비교하므로 통과. CI 는 push 완료 후이므로 태그도 도착해 있어 통과. 우회 경로(수동 push, git flow 후 태그 누락 push)만 정확히 차단된다.

#### 4.5.1 태그 동반 검사 (FE-1042)

위 검사는 **로컬 태그만** 본다. 그래서 로컬에 태그를 만들어 둔 뒤 `git push origin master` 만 실행하면 통과한다 — 원격엔 태그가 없으니 prod.yaml 의 Tag guard 가 배포를 막고, **master 만 올라간 '반쯤 릴리스' 상태**로 남는다(재현: `scripts/test/guards.sh` G1).

그래서 조건을 하나 더 요구한다: **그 태그가 이번 push 에 함께 올라갈 것.**

```sh
REFS=$(cat)      # stdin 은 한 번만 읽힌다 → 먼저 버퍼링
                 # (파이프로 while 을 돌리면 서브셸이라 exit 1 이 훅을 종료시키지 못한다.
                 #  아래 루프는 here-doc 으로 현재 셸에서 돈다)

tag_in_push() { printf '%s\n' "$REFS" | awk -v t="refs/tags/$1" '$3 == t {found=1} END {exit found?0:1}'; }

# 이미 원격에 같은 커밋으로 올라가 있으면(태그를 따로 먼저 민 경우) 통과시킨다
if ! tag_in_push "$VERSION" && [ "$(remote_tag_commit "$VERSION")" != "$local_sha" ]; then
  … 차단
fi
```

훅은 `#!/usr/bin/env sh` 이므로 추가 코드도 **POSIX 문법**이어야 한다(Ubuntu 는 `/bin/sh` 가 dash). `guards.sh` G5 가 `dash -n` 으로 검사한다.

#### 4.5.2 태그 쪽 검사 (FE-1043)

위 검사는 `refs/heads/master` 라인이 있을 때만 돈다. 그런데 **머지·태그 단계가 어긋난 릴리스는 '태그만' push 된다** — master/develop 가 원격과 이미 같으면 git 이 그 ref 를 아예 보내지 않기 때문이다. 그러면 위 루프가 한 번도 돌지 않고 통과한다.

그래서 semver 태그(`X.Y.Z`)에 대한 검사를 따로 둔다: **태그가 가리키는 커밋이 이번 push 의 master 이거나, 이미 원격 master 의 조상일 것.** 배포 트리거 태그(`staging`·`prod`)는 semver 형식이 아니라 대상이 아니다.

> 4.5.1 의 "이미 원격에 같은 커밋으로 있으면 통과" 예외는 이제 사실상 도달하기 어렵다(태그 단독 push 가 막히므로). 다른 머신에서 태그가 먼저 올라간 경우를 위한 안전판으로 남겨 둔다.

---

## 5. 상세 설계 — 공통 검사 라이브러리 (#6)

`scripts/lib/checks.sh` (신규). start 와 finish 가 공유한다.

```bash
# require_synced <branch>...  : fetch 후 behind/diverged/ahead 차단 (ahead 예외는 아래 5.1)
require_synced() {
  git fetch origin --prune
  for BR in "$@"; do
    read -r behind ahead < <(git rev-list --left-right --count "origin/${BR}...${BR}")
    if [ "$behind" -gt 0 ] && [ "$ahead" -gt 0 ]; then
      echo "❌ ${BR} 가 origin 과 갈라졌습니다 (behind ${behind}, ahead ${ahead})."
      echo "   → git switch ${BR} && git pull --rebase   (맨 git pull 은 pull.ff=only 로 실패)"
      exit 1
    elif [ "$behind" -gt 0 ]; then
      echo "❌ ${BR} 가 origin 보다 ${behind} 커밋 뒤처짐."
      echo "   → git switch ${BR} && git pull 후 재실행"
      exit 1
    elif [ "$ahead" -gt 0 ] && [ "$ALLOW_AHEAD_RESUME" = "1" ]; then
      echo "⚠️  ${BR} 에 push 안 된 로컬 커밋 ${ahead}개 — 중단된 finish 의 재실행으로 보입니다:"
      git log --oneline "origin/${BR}..${BR}" | sed 's/^/     /'
      confirm "   이어서 마무리할까요?"
    elif [ "$ahead" -gt 0 ]; then
      echo "❌ ${BR} 에 push 안 된 로컬 커밋 ${ahead}개 — 리뷰·CI 를 거치지 않은 채 이번 릴리스에 실려 나갑니다:"
      git log --oneline "origin/${BR}..${BR}" | sed 's/^/     /'
      # master 는 'push 하세요' 로 안내하면 안 된다 — master push = 운영 배포
      exit 1
    fi
  done
}

# confirm <msg> : TTY 면 y/N 프롬프트, 비대화형(CI 등)이면 차단
confirm() {
  if [ -t 0 ]; then
    printf '%s [y/N] ' "$1"; read -r A; [ "$A" = y ] || { echo "중단."; exit 1; }
  else
    echo "$1 → 비대화형 환경에서는 자동 차단합니다. 로컬 커밋을 push 하거나 정리 후 재실행하세요."
    exit 1
  fi
}

# require_merge_clean <base> <topic> : merge-tree 시뮬 (package.json/lock 충돌 제외 — merge driver 자동 해소분)
# require_semver_version <ver>       : X.Y.0 형식 검증
# require_gitflow                    : command -v git-flow, 미설치 시 brew 안내
# record_baseline / rollback_baseline: master/develop/브랜치 tip SHA 기록·복원 (§6)
# record_baseline_ref / rollback_baseline_ref: 단일 ref 기록·복원 — 스테이징 경로용 (§4.2.1)
```

**설계 노트**
- `ahead` 검사는 git-flow 계열 어디에도 없다 — 이 리포에서는 미푸시 master 커밋이 곧 운영 배포이므로 반드시 래퍼가 수행.
- 비대화형 환경에서 `confirm` 은 **차단**이 기본값(안전 우선). CI 에서 의도적으로 진행하려면 환경변수(`RELEASE_ASSUME_YES=1`) opt-in.

### 5.1 ahead 정책 — 확인이 아니라 차단 (FE-1039)

초기 설계는 ahead 를 "커밋 목록 + y/N 확인"으로 통과시켰다. 이를 **차단**으로 바꾼다.

- 미푸시 커밋은 리뷰·CI 를 거치지 않은 채 릴리스에 실려 나가고, master 의 미푸시 커밋은 그대로 운영 배포다.
- **`.husky/pre-push` 태그 정합성 가드(§4)는 이 경로를 잡지 못한다.** 그 가드는 "푸시되는 master tip 의 `package.json` version == 그 커밋을 가리키는 태그"만 본다. 우회로 만든 커밋 **위에** 정상 릴리스를 얹으면 새 태그가 새 master tip 을 정확히 가리켜 통과하고, 아래에 깔린 우회 커밋은 그대로 운영에 나간다. 즉 확인 프롬프트의 `y` 가 사실상 마지막 관문이었다 — 하필 그게 눌리는 시점은 야간 핫픽스 도중이다.
- 안내 문구는 브랜치 성격에 따라 다르다. **develop** 은 `git push` 로 먼저 올리면 끝이지만, **master** 는 `push` 자체가 운영 배포이므로 진단으로 유도한다(진행 중인 릴리스가 있으면 finish, 잔재면 `git reset --hard origin/master`).

**유일한 예외 — 중단된 finish 의 재실행.** Phase 2(머지·태그)까지 끝나고 push 전에 프로세스가 죽으면 master·develop 이 ahead 로 남는데, 이 ahead 는 스크립트 자신이 만든 것이다. 여기서 막으면 설계된 재실행 경로(§6.1)가 죽고 사용자는 수동 git 말고 할 수 있는 게 없어진다. `is_resumed_finish` 가 **세 조건을 모두** 만족할 때만 예외로 두고, 그때도 목록 + 확인을 거친다.

| 조건 | 배제하는 오인 |
|---|---|
| 토픽 브랜치 tip 이 이 버전의 `chore: {release,hotfix} <ver>` bump 커밋 | 수동 `git flow finish` 는 bump 를 만들지 않는다 |
| 그 브랜치가 이미 master 에 머지됨 | Phase 2 를 지나지 않은 상태 |
| 태그가 없거나 master tip 을 가리킴 | 태그가 다른 커밋 = bump 없는 재배포(사고 본체) |

사고(2026-07-29) 형태 — bump 없이 수동 `git flow hotfix finish` 로 머지·태그만 만들어진 상태 — 는 1·3 에서 걸러져 재실행으로 오인되지 않는다.
- 안내 문구 원칙: behind 는 `git pull`(pull.ff=only 로 FF 성공), diverged 는 `git pull --rebase`. `--no-rebase` 도 동작함을 실측 확인했으나 rebase 를 표준으로 안내(불필요한 머지 커밋 방지).

---

## 6. 상세 설계 — release/hotfix 재구성 (#7, #8)

### 6.1 finish — 4단계 구조

```
Phase 0  PREFLIGHT   읽기 전용 검증. 실패 → 무변경 중단
Phase 1  PREPARE     bump + changelog + commit. 실패 → 브랜치 tip 리셋(완전 복원)
Phase 2  MERGE/TAG   git flow <topic> finish -k 위임. 실패 → 기준점 롤백 (브랜치는 -k 로 생존)
Phase 3  PUBLISH     push --atomic. 실패 → 기준점 롤백. 성공 후에야 브랜치 삭제
Phase 4  STAGING     refresh-staging (기존 유지, best-effort)
```

```bash
finish() {
  # ── Phase 0: PREFLIGHT ────────────────────────────────
  require_topic_branch "hotfix"          # 실패 메시지에 → git switch <최근 hotfix 브랜치> 안내
  require_semver_version "${VERSION}"    # 비-semver 브랜치명을 bump 전에 차단
  require_clean_tree
  require_gitflow
  require_synced master develop          # fetch + behind/diverged 차단 + ahead 확인
  require_tag_absent "${VERSION}"        # 로컬·원격 모두
  require_merge_clean master  HEAD       # master 머지 사전 시뮬
  require_merge_clean develop HEAD       # 되머지 사전 시뮬 (diverged+충돌의 '반쯤 끝난 상태' 방지)
  record_baseline                        # BASE_MASTER/BASE_DEVELOP/BASE_TIP 기록

  # ── Phase 1: PREPARE ─────────────────────────────────
  # 재실행 멱등: bump 커밋이 이미 있으면 skip
  if ! git log -1 --format=%s | grep -qF "chore: hotfix ${VERSION}"; then
    trap 'git reset -q --hard "${BASE_TIP}"; echo "❌ 준비 단계 실패 — 브랜치를 원상 복구했습니다. 원인 해결 후 같은 명령을 재실행하세요."' ERR
    node scripts/bump-version.mjs "${VERSION}" >/dev/null
    node scripts/changelog.mjs "${VERSION}"
    git add package.json CHANGELOG.md; [ -f package-lock.json ] && git add package-lock.json
    git commit -qm "chore: hotfix ${VERSION}"
    trap - ERR
  fi

  # ── Phase 2: MERGE/TAG (git flow 위임, -k 로 브랜치 보존) ──
  if ! GIT_MERGE_AUTOEDIT=no git flow hotfix finish -k -m "${VERSION}" "${VERSION}"; then
    rollback_baseline    # merge --abort + master/develop 리셋 + 태그 삭제 + 브랜치 복귀
    echo "❌ 머지 실패 — master/develop/태그를 시작 전 상태로 복원했습니다. (${BRANCH} 는 그대로)"
    exit 1
  fi

  # ── Phase 3: PUBLISH ─────────────────────────────────
  if ! git push --atomic origin master develop "${VERSION}"; then
    rollback_baseline    # 원격은 --atomic 으로 무변경 → 로컬도 복원하면 완전한 재실행 가능 상태
    echo "❌ push 실패 — 로컬을 시작 전 상태로 복원했습니다."
    echo "   → git fetch 후 master/develop 을 최신화하고 같은 명령을 재실행하세요."
    exit 1
  fi
  git branch -d "${BRANCH}"
  git push origin ":refs/heads/${BRANCH}" 2>/dev/null || true   # 원격 사본 있으면 정리
  git checkout -q develop

  # ── Phase 4: STAGING (기존과 동일) ────────────────────
  trap - ERR
  bash scripts/refresh-staging.sh || echo "⚠️ staging 리프레시 미완료 — 릴리스는 정상 완료." >&2
}
```

`release.sh` 도 동일 구조(문구·prefix 만 차이). 공통 부분은 `checks.sh` 로.

**rollback_baseline 사양**:

```bash
rollback_baseline() {
  git merge --abort 2>/dev/null || true
  git checkout -q master  && git reset -q --hard "${BASE_MASTER}"
  git checkout -q develop && git reset -q --hard "${BASE_DEVELOP}"
  git tag -d "${VERSION}" 2>/dev/null || true
  git checkout -q "${BRANCH}"
}
```

- 롤백 기준은 **origin 이 아니라 Phase 0 에서 기록한 SHA** — preflight 에서 ahead 를 승인받은 경우 origin 으로 리셋하면 승인된 로컬 커밋이 유실되기 때문.
- push 실패 롤백 후 bump 커밋은 브랜치에 남는다 → 재실행 시 Phase 1 이 skip 되어 멱등.
- 고아 태그가 남지 않으므로 `next-version.mjs` 버전 건너뜀(0.49→0.50) 재발 불가.

#### 6.1.1 강제 중단 복구 (FE-1040)

위 롤백은 **스크립트가 살아 있을 때**만 돈다. `set -e` 의 ERR 트랩은 시그널에 걸리지 않으므로 Ctrl-C·터미널 종료·크래시에는 아무것도 복구되지 않는다. 실측하면 토픽 브랜치는 어느 지점에서 죽어도 살아남고 재실행으로 완주하지만, 사용자가 손으로 메워야 하는 틈이 둘 있었다.

| 틈 | 원인 | 조치 |
|---|---|---|
| 재실행 전 `git switch` 한 번 | Phase 2 가 master·develop 을 체크아웃하므로 중단 직후 HEAD 가 토픽 브랜치에 없다 | `find_resumable_topic` 으로 이어받을 브랜치를 찾아 **자동 전환** |
| Phase 1 중단 후 `git stash` 한 번 | bump·changelog 가 커밋 안 된 채 남아 `require_clean_tree` 에 걸린다 | 더러운 게 **자기 산출물뿐**이면 다시 생성해 이어감 |

둘 다 "스크립트가 만든 상태"로 판정 범위를 좁혔다.

- **자동 전환**은 `is_resumed_finish`(§5.1) 를 만족하는 후보가 **정확히 하나**일 때만 한다. 0개(사용자가 브랜치를 잘못 고름)나 2개 이상(모호)이면 추측하지 않고 기존 안내로 막는다. 전환 전 `require_clean_tree` 를 건다.
- **산출물 판정**은 ① 더러운 경로가 `{package.json, package-lock.json, CHANGELOG.md}` 안에만 있고 ② `package.json` 의 version 이 이미 이번 릴리스 버전일 때만 성립한다(= 우리 bump 가 돌았다는 증거). 하나라도 어긋나면 사용자 변경일 수 있으므로 기존대로 차단한다. Phase 1 은 멱등이므로(bump 는 같은 값, `changelog.mjs` 는 같은 버전 섹션을 교체 — `changelog.mjs:147`) 그대로 덮어쓰면 된다.

> 남은 divergence: 성공한 `release finish` 는 HEAD 를 develop 에 두고 끝난다(avh 는 master). Phase 2 끝에서 토픽 브랜치로 되돌리면 `topic_delete` 가 avh 와 같은 위치로 정리하지만, 눈에 보이는 동작 변화라 이번 범위에서는 손대지 않았다.

#### 6.1.2 checkout 실패를 성공으로 처리하던 결함 (FE-1043)

`topic_merge_and_tag` 는 `if ! topic_merge_and_tag ...` 로 호출된다. **그 문맥에서는 함수 본문 전체에서 `set -e` 가 꺼진다.** 그런데 세 곳의 `git checkout` 이 반환값을 확인하지 않아, checkout 이 실패해도 다음 명령이 그대로 이어졌다.

실패 경로는 이렇게 흘렀다.

1. `git checkout master` 실패 → HEAD 가 토픽 브랜치에 남는다
2. `git merge --no-ff <토픽>` → **자기 자신을 머지**해 "Already up to date" 로 성공
3. 두 번째 `git checkout master` 도 실패
4. `git tag` 가 master 가 아닌 **토픽 tip** 에 붙는다
5. 함수가 0 을 반환하고 Phase 3 으로 진행
6. master/develop 가 원격과 같으므로 `--atomic` push 는 **태그만** 전송 → pre-push 의 master 검사는 돌지 않음
7. 원격에 잘못된 커밋을 가리키는 버전 태그만 남고, 스크립트는 **성공 메시지를 출력**한다

이후 `next-version.mjs` 가 그 태그를 최댓값으로 잡아 다음 버전을 건너뛴다.

**확인된 트리거 두 가지**

| 트리거 | worktree 필요 | 비고 |
|---|---|---|
| master/develop 가 다른 worktree 에 체크아웃됨 | 필요 | 실제 운영 환경이 worktree 여러 개인 경우 흔하다 |
| bump 커밋이 있어 Phase 1 을 skip 했는데 허용된 산출물이 더러운 채로 남음 | **불필요** | §6.1.1 의 완화가 연 경로 |

**대응 — 세 겹**

1. `checkout_or_fail` 로 실패를 원인과 함께 즉시 `return 1`
2. 함수 성공 전 **사후 검증** — 토픽이 master 에 머지됐는가 · master 가 develop 에 머지됐는가 · 태그가 master 를 가리키는가. 개별 명령을 하나씩 막는 것보다 "끝난 뒤 상태가 맞는가" 를 보는 편이 확실하다
3. Phase 0 에 `require_not_in_other_worktree` — 실패 후 롤백보다 시작 전 차단이 낫다. finish 는 토픽 브랜치에서만 실행되므로, master/develop 를 잡고 있는 worktree 가 있다면 그건 언제나 '다른' worktree 다(경로 비교 불필요)

그리고 §6.1.1 의 skip 경로가 더러운 산출물을 남기지 않도록, bump 커밋이 이미 있으면 **남은 산출물 변경을 되돌린 뒤** skip 한다.

> 되돌릴 때 고정 파일 목록(`package.json package-lock.json CHANGELOG.md`)을 쓰면 안 된다 —
> 없는 파일 하나 때문에 `git checkout --` 전체가 실패해 **아무것도 복원되지 않는다**(Yarn Berry 리포에는 `package-lock.json` 이 없다). 실제로 더러운 경로만 골라 되돌린다.

### 6.2 start — 검증 격차 해소

| 변경 | 대상 | 근거(실측) |
|---|---|---|
| `require_synced master develop` 적용 (ahead 차단 포함) | release·hotfix 공통 | hotfix start 는 develop 미검사, 둘 다 ahead 를 `_` 로 버림 |
| `require_merge_clean develop HEAD`(hotfix: 되머지 방향) 추가 | hotfix | release 만 merge-tree 시뮬 보유 |
| `require_gitflow` 를 fetch 전에 | 공통 | 미설치 시 검사 다 통과 후 의미불명 출력으로 사망 |
| 잔재 topic 브랜치 선검사 | 공통 | git flow 의 "Finish that one first" 는 뭉개진 브랜치명 + 위험한 유도(작업 브랜치를 finish 하라고 읽힘) |

잔재 브랜치 메시지 설계:

```
❌ 로컬에 hotfix/* 브랜치가 이미 있습니다: hotfix/FE-1234
   릴리스용이 아닌 작업 브랜치라면 이름을 바꾸거나 삭제 후 재실행하세요:
   → git branch -m hotfix/FE-1234 fix/FE-1234     (이름 변경)
   → git branch -D hotfix/FE-1234                 (삭제)
   ※ hotfix/ 접두사는 릴리스 플로우 전용입니다. 작업 브랜치는 fix/ 를 사용하세요.
```

### 6.3 changelog 멱등화 (#9)

`changelog.mjs` 운영 모드: prepend 전에 동일 버전 섹션(`## [X.Y.0]`) 존재 시 **해당 섹션을 교체**. finish 재실행·수동 복구 시 중복 섹션 방지.

### 6.4 기타 (#9)

- `merge-staging.sh` M3: 머지 결과 신규 커밋이 0 이면 `⚠️ 새 변경 없음 — 그래도 배포(patch +1)할까요?` confirm.
- 문구 교체: `release.sh`·`hotfix.sh` 의 `git pull 후 재시도` → §5 의 상태별 안내로 통일.

---

## 7. 실패 시나리오 전후 비교

| 시나리오 (실측 ID) | 현재 | 개선 후 |
|---|---|---|
| staging/* 에서 finish (1-A-1, **사고 방아쇠**) | ❌ 만 출력 → git flow 우회 유도 | #2 로 원천 제거 + 안내 메시지 |
| git flow 직접 호출로 bump 없이 master push (**사고 본체**) | 통과 → 0.48.0 재배포 | **#5 태그 정합성 가드가 push 차단** |
| 비-semver 브랜치 finish (2-A-1~3) | bump 도중 실패 | Phase 0 무변경 중단 |
| GPG·훅·lock 커밋 실패 (2-D) | 더러운 트리 잔류 → 재실행 튕김 | Phase 1 자동 복원 → 재실행 OK |
| develop behind/diverged finish (3-A-2/3) | master 머지·태그·**브랜치 삭제 후** push 실패 | Phase 0 무변경 중단 |
| develop/master ahead | 조용히 통과, 미푸시 커밋 유출 | **차단** + 브랜치별 대응 안내 (§5.1) |
| Phase 2 후 죽은 finish 재실행 (master·develop ahead) | — | `is_resumed_finish` 3조건 충족 시에만 확인 후 통과 |
| 강제 중단(kill/Ctrl-C) 후 재실행 | 브랜치는 살지만 `git switch` + `git stash` 를 손으로 | 자동 이어받기 + 산출물 재생성 (§6.1.1) |
| stale (팀원 push, fetch 안 함) | 마지막 push 에서 status:5 | Phase 0 fetch 로 사전 감지 |
| push 실패 | 브랜치 삭제됨·고아 태그·수동 수습 | 완전 복원, 같은 명령 재실행 |
| finish 재실행 | CHANGELOG 섹션 중복 | 멱등 (Phase 1 skip + changelog 교체) |
| 옛 staging 라인 deploy (D1) | staging 태그가 옛 코드로 이동 | #3 라인 가드 차단 |
| staging:new 임의 인자 (N2/N3) | staging/banana·선행 라인 → 데드락 | #4 검증·확인·데드락 감지 |
| feature 에서 push-tag prod (P1) | **운영 배포 트리거** | #1 가드 차단 |

---

## 8. 검증 계획

기존 격리 하네스(`$CLAUDE_JOB_DIR/tmp/probe4~7.sh`, bare origin + 클론, 사용자 리포 무변경) 재사용:

1. **회귀**: probe4(finish 중단 21케이스) · probe5(동기화 7상태) · probe6/7(start·staging 13케이스) 를 패치 후 재실행 → §7 표의 "개선 후" 열과 전건 일치 확인.
2. **신규**: 롤백 후 재실행 멱등성(같은 명령 2회 = 1회와 동일 결과), confirm 비대화형 차단, push-tag force 방식.
3. **avh 실측** (§2 전제): avh 설치 환경에서 `finish -k` 브랜치 보존·실패 종료코드·태그 생성 순서 확인. 불일치 시 B안 전환 여부 재결정.
4. **사고 재연 시나리오**: 17:25~17:56 타임라인을 하네스로 재연 → 각 단계에서 새 가드가 차단하는지 확인.

## 9. 배포 순서

1. 이 샌드박스에서 단위별 PR (`feature/FE-1029` ~ `FE-1035`) — 각 PR 마다 하네스 검증 첨부
2. 팀 리뷰 (이 문서 + 전후 비교표)
3. `imsform-mobile-web` **FE-2793** 으로 통합 이식 (PR 1개)
4. `CONTRIBUTING.md` 팀 규칙 반영: `hotfix/` 접두사는 릴리스 전용, 작업 브랜치는 `fix/`;
   git-flow 는 avh 로 통일 + `gitflow.{release,hotfix}.finish.fetch true`

### 이식 시 리포 간 차이 (선례 PR #1399 · #1418 기준)

| 항목 | 차이 | 대응 |
|---|---|---|
| `.husky/pre-push` | 실제 리포는 tsc·test 검사가 앞에 있음 | 태그 정합성 가드를 기존 **버전 가드 블록에 append** (샌드박스 pre-push 주석에도 명시된 규칙) |
| `.github/workflows/prod.yaml` | 샌드박스는 stub, 실제는 실배포 | Version guard 스텝 구조 확인 후 검증 로직만 삽입. 태그 조회를 위해 `fetch-depth: 0` + `fetch-tags: true` 필요 |
| `changelog.mjs` 등 `.mjs` | 포맷·주석 차이(로직 동일), imsform 은 SSH host alias(`git@github.com-ims:`) → https 정규화 보유 | **통째 복사 금지** — 로직만 외과적으로 병합, imsform 전용 코드·prettier 포맷 보존 (#1418 선례) |
| 셸 스크립트 7종 | 로직 동일(diff 없음) 확인됨 | 샌드박스 최종본과 바이트 동일 여부 확인 후 이식 |
| 패키지 매니저 | 실제 리포는 Yarn Berry (`package-lock.json` 없음) | `[ -f package-lock.json ]` 분기는 그대로 무해 |
| 기존 `hotfix/FE-*` 원격 브랜치 | `hotfix/FE-2694`·`FE-2712`·`SearchInputProps` 존재 → start 차단 유발 | 팀 공지 후 `fix/` 로 일괄 rename (#10) |

## 10. 미결정 / 확인 필요

| 항목 | 상태 |
|---|---|
| avh `finish -k`·종료코드 동작 | **실측 필요** (§8-3) — A안의 전제 |
| `RELEASE_ASSUME_YES` 환경변수 이름·범위 | 리뷰에서 결정 |
| deploy-staging `--force`(옛 라인 의도 배포) 필요 여부 | 실사용 사례 확인 후 결정 |
| 기존 `hotfix/FE-*` 원격 브랜치(FE-2694 등) 정리 | 팀 공지 후 일괄 rename |
