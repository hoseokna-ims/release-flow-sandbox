#!/usr/bin/env bash
#
# 로컬 staging/* 미푸시 커밋(ahead) 가드 검증 (FE-1045)
#
# merge-staging.sh 의 사전검사는 '대상 브랜치' 의 미푸시 커밋만 봤다. 로컬 staging/* 자체는
# 아무도 보지 않았고 git pull 은 ahead 를 fast-forward 로 조용히 통과시킨다. deploy-staging.sh
# 도 clean tree 만 봤다. #36·#37 의 ahead 정책이 release/hotfix 전용으로만 적용돼 있었다.
#
# 여기서 확인하는 것
#   ① 사람이 staging 에 직접 만든 커밋은 첫 변경 전에 차단되는가
#   ② 예외(스크립트 자신이 만든 커밋뿐)는 목록 + 확인을 거쳐 통과하는가
#   ③ 형식만 흉내낸 커밋을 재실행으로 오인하지 않는가
#   ④ 정상 플로우·새 클론·behind 가 회귀하지 않는가
#
# 사용법: bash scripts/test/staging-ahead.sh
#
source "$(dirname "$0")/lib/harness.sh"
harness_init staging-ahead

# origin/staging/0.1 을 한 커밋 앞서게 만든다(다른 사람이 먼저 배포한 상황).
advance_remote() {
  local N="$1" CL="${WORK}/$1-other"
  "${GIT_REAL}" clone -q "${WORK}/${N}.git" "${CL}" 2>/dev/null
  ( cd "${CL}"
    "${GIT_REAL}" config user.email test@example.com; "${GIT_REAL}" config user.name test
    "${GIT_REAL}" switch -q staging/0.1; echo o > o.txt; "${GIT_REAL}" add o.txt
    "${GIT_REAL}" commit -qm "feat: other"; "${GIT_REAL}" push -q origin staging/0.1 ) >/dev/null 2>&1
}

# 사람이 staging 에 직접 커밋한 상태를 만든다(push 하지 않음).
commit_on_staging() {
  git switch -q staging/0.1
  echo u > u.txt; git add u.txt; git commit -qm "fix: 사람이 직접 고친 것"
  git switch -q feature/FE-X
}

# ══ A1  사용자 커밋 ahead → 차단 ══════════════════════════════════════
case_hdr "A1  로컬 staging ahead(사용자 커밋) → 차단 · 머지·bump 미실행 · 원격 무변경"
fixture_staging a1
REMOTE_BEFORE="$(remote_sha staging/0.1)"
commit_on_staging
BASE="$(git rev-parse staging/0.1)"
run "bash scripts/merge-staging.sh feature/FE-X"
expect_blocked
expect_has "push 안 된 로컬 커밋 1개가 있습니다"
expect_has "우회 조작의 흔적"
expect_has "git reset --hard origin/staging/0.1"
expect_absent "중단된 스테이징 배포의 재실행"    # 부재 단언 — 사용자 커밋을 재실행으로 오인 금지
# 첫 변경 전에 막혔는가 — staging tip 이 그대로고 머지 커밋도 bump 도 없다
[ "$(git rev-parse staging/0.1)" = "${BASE}" ]; ok "staging/0.1 무변경 (첫 변경 전 차단)" $?
[ "$(git rev-list --count --merges "origin/staging/0.1..staging/0.1")" -eq 0 ]; ok "머지 미실행" $?
expect_ver 0.1.0
[ "$(remote_sha staging/0.1)" = "${REMOTE_BEFORE}" ]; ok "원격 staging/0.1 무변경" $?
head_is feature/FE-X

# ══ A2 · A3  예외: 자기 bump 커밋뿐 ═══════════════════════════════════
case_hdr "A2  ahead 가 자기 bump 커밋뿐 → 목록 + 확인 (비대화형은 자동 중단)"
fixture_staging a2
git switch -q staging/0.1
# push 직전에 죽여 '미푸시 bump 커밋 1개' 상태를 만든다 (deploy-staging 은 머지를 하지 않는다)
KILL_ON='push origin HEAD:staging/0.1' bash scripts/deploy-staging.sh >/dev/null 2>&1
expect_unpushed 1 staging/0.1
expect_ver 0.1.1
git switch -q feature/FE-X
run "bash scripts/merge-staging.sh feature/FE-X"
expect_blocked                                   # 확인을 받지 못하면 진행하지 않는다
expect_has "중단된 스테이징 배포의 재실행으로 보입니다"
expect_has "chore: staging deploy 0.1.1"         # 무엇을 push 하려는지 목록으로 보여준다
expect_has "비대화형 환경에서는 자동 중단"
expect_absent "우회 조작의 흔적"                   # 부재 단언 — 자기 커밋을 우회로 오인 금지

case_hdr "A3  RELEASE_ASSUME_YES=1 + A2 → 자동 승인 후 완주"
run "RELEASE_ASSUME_YES=1 bash scripts/merge-staging.sh feature/FE-X"
expect_success
expect_has "RELEASE_ASSUME_YES=1 로 자동 승인"
git fetch -q origin --prune
expect_same staging/0.1 origin/staging/0.1
expect_unpushed 0 staging/0.1
# 버전이 두 번 오른다(0.1.0 → 0.1.1 → 0.1.2). FE-1046 검토 결과 이건 격차가 아니라
# 의도된 동작이다 — 미푸시 bump(0.1.1) 위에 **새 머지가 얹혔으므로 내용이 달라졌다.**
# 여기서 bump 를 건너뛰면 0.1.1 시점에 생성된 STAGING_CHANGELOG.md 가 그대로 배포되어
# 새로 머지된 내용이 누락된다. 배포된 적 없는 patch 번호 하나를 소비하는 편이 낫다.
# FE-1046 이 닫은 것은 "내용이 그대로인데 두 번 오르는" 경우다
# (staging-idempotent.sh D7 = skip, D8 = 이 케이스와 같은 상황이라 skip 하지 않음).
expect_ver 0.1.2
[ "$(count_in origin/staging/0.1 'chore: staging deploy')" -eq 2 ]; ok "bump 커밋 2개 (내용이 달라졌으므로 의도된 동작)" $?

# ══ A4  ahead 없음 → 경고 미출력 ══════════════════════════════════════
case_hdr "A4  ahead 없음 → 정상 완주, 가드 문구 미출력 (부재 단언)"
fixture_staging a4
run "bash scripts/merge-staging.sh feature/FE-X"
expect_success
expect_absent "push 안 된 로컬 커밋"
expect_absent "중단된 스테이징 배포의 재실행"
expect_absent "우회 조작의 흔적"
expect_absent "뒤처졌습니다"
expect_ver 0.1.1

# ══ A5  deploy-staging.sh 단독 ════════════════════════════════════════
case_hdr "A5  deploy-staging.sh 단독 실행 + ahead → 차단 (같은 구멍)"
fixture_staging a5
REMOTE_BEFORE="$(remote_sha staging/0.1)"
git switch -q staging/0.1
echo u > u.txt; git add u.txt; git commit -qm "fix: 사람이 직접 고친 것"
run "bash scripts/deploy-staging.sh"
expect_blocked
expect_has "우회 조작의 흔적"
expect_ver 0.1.0                                 # bump 전에 막혔다
expect_clean_tree
[ "$(remote_sha staging/0.1)" = "${REMOTE_BEFORE}" ]; ok "원격 staging/0.1 무변경" $?

# ══ A6  behind — 호출부에 따라 갈린다 ═════════════════════════════════
case_hdr "A6  behind + merge-staging → 통과 (바로 git pull 한다)"
fixture_staging a6
advance_remote a6
run "bash scripts/merge-staging.sh feature/FE-X"
expect_success
expect_absent "뒤처졌습니다"                      # 부재 단언 — behind 를 막으면 정상 플로우가 죽는다
expect_ver 0.1.1
git fetch -q origin --prune
expect_same staging/0.1 origin/staging/0.1

case_hdr "A6b behind + deploy-staging → 차단 (pull 하지 않으므로 push 가 반드시 거부된다)"
fixture_staging a6b
advance_remote a6b
git switch -q staging/0.1
run "bash scripts/deploy-staging.sh"
expect_blocked
expect_has "뒤처졌습니다"
expect_ver 0.1.0                                 # bump 전에 막혔다
expect_clean_tree

# ══ A7  새 클론 회귀 ══════════════════════════════════════════════════
case_hdr "A7  로컬 staging 브랜치가 없음 → 통과 (새 클론에서 첫 배포)"
fixture_staging a7
git branch -q -D staging/0.1                     # origin 에만 있는 상태로 되돌린다
run "bash scripts/merge-staging.sh feature/FE-X"
expect_success
expect_absent "로컬 브랜치가 없습니다"             # 부재 단언 — require_synced 를 그대로 쓰면 여기서 죽는다
expect_ver 0.1.1

# ══ A8  FE-1044 회귀 ═════════════════════════════════════════════════
case_hdr "A8  FE-1044 재개 상태(미푸시 머지 커밋) → 예외로 통과 (R5 회귀)"
fixture_staging a8
KILL_ON='rev-list --count *..HEAD' bash scripts/merge-staging.sh feature/FE-X >/dev/null 2>&1
[ "$(git rev-list --count --merges "origin/staging/0.1..staging/0.1")" -eq 1 ]; ok "미푸시 머지 커밋 1개" $?
run "RELEASE_ASSUME_YES=1 bash scripts/merge-staging.sh feature/FE-X"
expect_success
expect_has "중단된 스테이징 배포의 재실행으로 보입니다"
expect_absent "우회 조작의 흔적"                   # 부재 단언 — 자기 머지 커밋을 차단하면 R5 가 죽는다
expect_ver 0.1.1

# ══ A9  형식만 흉내낸 커밋 ════════════════════════════════════════════
case_hdr "A9  버전이 다른 bump 커밋 → 재실행으로 오인하지 않음"
fixture_staging a9
git switch -q staging/0.1
git commit -q --allow-empty -m "chore: staging deploy 9.9.9"   # package.json 은 0.1.0
git switch -q feature/FE-X
run "bash scripts/merge-staging.sh feature/FE-X"
expect_blocked
expect_has "우회 조작의 흔적"
expect_absent "중단된 스테이징 배포의 재실행"      # 부재 단언

case_hdr "A9b 미푸시 브랜치를 머지한 머지 커밋 → 재실행으로 오인하지 않음"
# 머지 커밋 형식은 같지만 2번째 부모가 origin 에 없다 = 미푸시 작업이 묻어 나가는 상태.
fixture_staging a9b
git switch -q -c fix/local-only develop
echo l > l.txt; git add l.txt; git commit -qm "fix: 로컬에만 있는 작업"
git switch -q staging/0.1
GIT_MERGE_AUTOEDIT=no git merge -q --no-ff -m "Merge branch 'fix/local-only' into staging/0.1" fix/local-only
git switch -q feature/FE-X
run "bash scripts/merge-staging.sh feature/FE-X"
expect_blocked
expect_has "우회 조작의 흔적"
expect_absent "중단된 스테이징 배포의 재실행"      # 부재 단언

# ══ A10  diverged ════════════════════════════════════════════════════
case_hdr "A10 diverged(사용자 커밋 + 원격 선행) → 차단"
fixture_staging a10
advance_remote a10
commit_on_staging
run "bash scripts/merge-staging.sh feature/FE-X"
expect_blocked
expect_has "우회 조작의 흔적"
expect_ver 0.1.0
head_is feature/FE-X

harness_summary
