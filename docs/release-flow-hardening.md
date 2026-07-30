# 릴리스 플로우 안정화 설계 (release/hotfix/staging 스크립트 개선)

> 2026-07-29 imsform-mobile-web hotfix 0.49.0 사고(버전 bump 없이 0.48.0 재배포) 분석에서 도출된
> 릴리스 스크립트 전면 보완 설계. 모든 근거는 격리 하네스 실측으로 검증됨(§8 검증 계획 참고).
>
> 상태: **구현 진행 중** · 작성 2026-07-30
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

**아키텍처 결정: git flow 위임 유지 (A안)**

finish 의 머지·태그 실행은 `git flow ... finish -k` 에 계속 위임한다. 근거:

- 동기화 검사는 우리 preflight 가 직접 수행하므로 git flow 검사의 무력함은 무관해짐
- `-k`(keep) 로 "push 전 브랜치 삭제" 문제 해결 — 삭제는 래퍼가 push 성공 후 수행
- 머지 실패 롤백도 래퍼가 git flow 를 감싸서 구현 가능
- 검증된 resume 로직(이미 된 머지·태그 skip) 재사용, 팀 친숙성 유지
- **전제 조건**: avh 에디션에서 `-k` 와 실패 시 종료코드 동작 실측 확인 (§8). 예상 밖 동작이면 B안(직접 구현)으로 에스컬레이션

---

## 3. 작업 목록 및 우선순위

| # | 샌드박스 브랜치 | 항목 | 심각도 | 파일 | 상태 |
|---|---|---|---|---|---|
| 1 | `feature/FE-1029` | `push-tag.sh` prod/staging 가드 + force-push 방식 (§4.1) | 🔴 | `scripts/push-tag.sh` | ✅ 구현·검증 완료 |
| 2 | `feature/FE-1030` | `merge-staging.sh` 원래 브랜치 복귀 + `deploy-staging.sh` 최신 라인 가드 (§4.2·4.3) | 🔴 | staging 2종 | 대기 |
| 3 | `feature/FE-1031` | `new-staging.sh` 3겹 개선(안내·인자 검증·데드락 감지) (§4.4) | 🔴 | `scripts/new-staging.sh` | 대기 |
| 4 | `feature/FE-1032` | pre-push·prod.yaml **태그 정합성 가드** (§4.5) | 🔴 | `.husky/pre-push`, `prod.yaml` | 대기 |
| 5 | `feature/FE-1033` | 공통 검사 라이브러리 + **start 보강** (§5·6.2) | 🟠 | `scripts/lib/checks.sh`(신규), release/hotfix | 대기 |
| 6 | `feature/FE-1034` | finish 재구성 (preflight→prepare→git flow `-k`→publish) + changelog 멱등화 (§6.1·6.3) | 🟠 | release/hotfix, `changelog.mjs` | 대기 (#5 의존) |
| 7 | `feature/FE-1035` | 문구 통일·M3 빈 배포 확인·`CONTRIBUTING.md` 팀 규칙 (§6.4) | 🟡 | 다수 | 대기 |

1~5 는 상호 독립이라 병렬 리뷰·머지 가능. 6 은 5 에 의존, 7 은 마무리.
각 PR 본문에 해당 probe 케이스 전후 비교 결과를 첨부한다(§8).

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

**문제(실측, 0.50 사건 재현)**: ① "이미 존재합니다" 메시지가 막다른 골목 → 사용자를 임의 override 로 유도 ② override 인자 무검증(`staging/banana` 생성됨, develop 라인과 무관한 `0.27` 도 통과) ③ 오펀 라인 생성 시 `staging:merge`·`staging:new` 가 상호 차단(데드락).

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

# ③ 데드락 감지: 최신 staging 라인 > develop 라인이면 오펀으로 판정
if [ -n "${LATEST}" ] && [ "$(printf '%s\n%s' "${LATEST#staging/}" "${DEV_MINOR}" | sort -t. -k1,1n -k2,2n | tail -1)" != "${DEV_MINOR}" ]; then
  echo "⚠️  최신 staging(${LATEST})이 develop(${DEV_MINOR}) 보다 앞선 라인입니다 — 오펀 라인으로 보입니다."
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

---

## 5. 상세 설계 — 공통 검사 라이브러리 (#6)

`scripts/lib/checks.sh` (신규). start 와 finish 가 공유한다.

```bash
# require_synced <branch>...  : fetch 후 behind/diverged 차단, ahead 는 목록 표시 + 명시적 확인
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
    elif [ "$ahead" -gt 0 ]; then
      echo "⚠️  ${BR} 에 push 안 된 로컬 커밋 ${ahead}개 — 이번 릴리스에 함께 나갑니다:"
      git log --oneline "origin/${BR}..${BR}" | sed 's/^/     /'
      confirm "   포함하고 계속할까요?"
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
```

**설계 노트**
- `ahead` 확인은 git-flow 계열 어디에도 없는 검사 — 이 리포에서는 미푸시 master 커밋이 곧 운영 배포이므로 반드시 래퍼가 수행.
- 비대화형 환경에서 `confirm` 은 **차단**이 기본값(안전 우선). CI 에서 의도적으로 진행하려면 환경변수(`RELEASE_ASSUME_YES=1`) opt-in.
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

### 6.2 start — 검증 격차 해소

| 변경 | 대상 | 근거(실측) |
|---|---|---|
| `require_synced master develop` 적용 (ahead 확인 포함) | release·hotfix 공통 | hotfix start 는 develop 미검사, 둘 다 ahead 를 `_` 로 버림 |
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
| develop/master ahead | 조용히 통과, 미푸시 커밋 유출 | 커밋 목록 + 명시적 확인 |
| stale (팀원 push, fetch 안 함) | 마지막 push 에서 status:5 | Phase 0 fetch 로 사전 감지 |
| push 실패 | 브랜치 삭제됨·고아 태그·수동 수습 | 완전 복원, 같은 명령 재실행 |
| finish 재실행 | CHANGELOG 섹션 중복 | 멱등 (Phase 1 skip + changelog 교체) |
| 옛 staging 라인 deploy (D1) | staging 태그가 옛 코드로 이동 | #3 라인 가드 차단 |
| staging:new 임의 인자 (N2/N3) | staging/banana·오펀 라인 → 데드락 | #4 검증·확인·데드락 감지 |
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
