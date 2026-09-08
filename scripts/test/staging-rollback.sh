#!/usr/bin/env bash
#
# 스테이징 경로 롤백 + 실패 원인 구분 검증 (FE-1044)
#
# merge-staging.sh 는 ⑤ bump+commit 이후의 실패에 복구가 없었다. 실제 사고에서는
# pre-push 의 tsc 가 실패하자 머지·bump 커밋이 로컬 staging 에 그대로 남고, 실패 안내가
# 모든 push 실패에 "원격이 앞섬 + git pull" 을 출력해 이중 bump 를 유도했다.
#
# 여기서 확인하는 것
#   ① ⑤ 이후 어느 경로로 실패해도 staging 이 "git pull 직후" 상태로 되돌아가는가
#   ② 실패 원인(pre-push 거부 / non-fast-forward / 그 외)이 구분되고 안내가 다른가
#   ③ 되돌린 뒤 같은 명령 재실행으로 완주하며 버전이 한 번만 오르는가
#   ④ 롤백하면 안 되는 두 경로(머지 충돌 · 태그 push 실패)에서는 롤백하지 않는가
#
# 사용법: bash scripts/test/staging-rollback.sh
#
source "$(dirname "$0")/lib/harness.sh"
harness_init staging-rollback

# ── 케이스 전용 단언 (공용 헬퍼는 lib/harness.sh) ─────────────────────
expect_rolled_back(){ [ "$(git rev-parse "$2")" = "$1" ]; ok "$2 == pull 후 SHA (롤백 완료)" $?; }

# ══ R1 · R4  pre-push 훅 거부 ═════════════════════════════════════════
case_hdr "R1  pre-push 거부 → 롤백 (bump 커밋 미생성 · 원격 무변경 · ORIG_BRANCH 복귀)"
fixture_staging r1
BASE="$(git rev-parse staging/0.1)"
REMOTE_BEFORE="$(remote_sha staging/0.1)"
prepush_fail_on
run "bash scripts/merge-staging.sh feature/FE-X"
expect_blocked
expect_has "로컬 검사(.husky/pre-push)"
expect_has "tsc --noEmit 실패 5건"          # 훅이 낸 실패 내용을 판정 전에 먼저 보여준다
expect_rolled_back "${BASE}" staging/0.1
expect_unpushed 0 staging/0.1                # 머지 커밋·bump 커밋 모두 없음
expect_ver 0.1.0
[ "$(remote_sha staging/0.1)" = "${REMOTE_BEFORE}" ]; ok "원격 staging/0.1 무변경" $?
expect_clean_tree
head_is feature/FE-X

case_hdr "R4  pre-push 거부 메시지에 pull 안내 부재 (부재 단언)"
# 같은 실행의 출력을 그대로 재검사한다. 이 문구가 살아 있으면 사용자가 pull 후
# staging:deploy 로 마무리해 patch 가 두 번 오른다 — 사고의 2차 피해 경로다.
expect_absent "git pull --no-rebase"
expect_absent "git pull"
expect_absent "원격이 앞섬"
expect_absent "앞서 있습니다"

# ══ R2  원인 제거 후 재실행 ═══════════════════════════════════════════
case_hdr "R2  R1 후 원인 제거 → 재실행 완주 (머지 커밋 중복 없음 · 버전 1회 상승)"
prepush_fail_off
run "bash scripts/merge-staging.sh feature/FE-X"
expect_success
expect_ver 0.1.1
git fetch -q origin --prune
[ "$(count_in origin/staging/0.1 "Merge branch 'feature/FE-X'")" -eq 1 ]; ok "머지 커밋 1개 (중복 없음)" $?
[ "$(count_in origin/staging/0.1 'chore: staging deploy')" -eq 1 ]; ok "bump 커밋 1개 (버전 1회 상승)" $?
head_is feature/FE-X

# ══ R3  non-fast-forward ══════════════════════════════════════════════
case_hdr "R3  non-fast-forward 거부 → 롤백 + 원격 선행 안내 (R1 과 다른 메시지)"
fixture_staging r3
BASE="$(git rev-parse staging/0.1)"
# 다른 클론을 준비하고, 우리 push '직전'에 origin/staging/0.1 을 진행시킨다.
# (픽스처 직후에 밀면 스크립트의 git pull 이 그걸 받아버려 non-ff 가 되지 않는다)
CL="${WORK}/r3-other"; "${GIT_REAL}" clone -q "${WORK}/r3.git" "${CL}" 2>/dev/null
( cd "${CL}"
  "${GIT_REAL}" config user.email test@example.com; "${GIT_REAL}" config user.name test
  "${GIT_REAL}" switch -q staging/0.1; echo o > o.txt; "${GIT_REAL}" add o.txt
  "${GIT_REAL}" commit -qm "feat: other" ) >/dev/null 2>&1
run "RACE_ON='push origin HEAD:staging/0.1' \
     RACE_MARK='${WORK}/r3.raced' \
     RACE_CMD='cd ${CL} && ${GIT_REAL} push -q origin staging/0.1' \
     bash scripts/merge-staging.sh feature/FE-X"
expect_blocked
expect_has "원격 staging/0.1 가 앞서 있습니다"
expect_has "git pull"                        # R1 과 달리 여기서는 pull 을 언급한다
expect_absent "로컬 검사(.husky/pre-push)"     # 원인을 뭉개지 않는다
expect_rolled_back "${BASE}" staging/0.1
expect_unpushed 0 staging/0.1
expect_ver 0.1.0
expect_clean_tree
head_is feature/FE-X

# ══ R5  머지~bump 사이 강제 중단 ══════════════════════════════════════
case_hdr "R5  머지~bump 사이 kill -9 → 재실행 완주, '빈 배포' 경고 미출력"
fixture_staging r5
# 빈 배포 판정용 rev-list 직전에 죽인다 = 머지 커밋만 남고 워킹트리는 깨끗한 상태.
# (사전검사의 rev-list 는 'origin/<br>..<br>' 이라 이 패턴에 걸리지 않는다)
KILL_ON='rev-list --count *..HEAD' bash scripts/merge-staging.sh feature/FE-X >/dev/null 2>&1
head_is staging/0.1
# 미푸시 커밋은 머지 커밋 + 그 브랜치가 들여온 커밋이다. 재개 판정에서 중요한 것은
# "머지는 있고 bump 는 없다" 이므로 그 둘을 따로 센다.
[ "$(git rev-list --count --merges origin/staging/0.1..staging/0.1)" -eq 1 ]; ok "미푸시 머지 커밋 1개" $?
[ "$(count_in origin/staging/0.1..staging/0.1 'chore: staging deploy')" -eq 0 ]; ok "미푸시 bump 커밋 없음" $?
expect_clean_tree
expect_ver 0.1.0
# FE-1045 부터 미푸시 커밋은 require_staging_synced 의 확인을 거친다 — 재개 상태도
# 예외로 통과시키되 목록 + 확인을 받으므로(#36 설계), 비대화형에서는 자동 승인이 필요하다.
run "RELEASE_ASSUME_YES=1 bash scripts/merge-staging.sh feature/FE-X"
expect_success
expect_has "중단된 스테이징 배포의 재실행으로 보입니다"
expect_has "중단된 실행의 재개입니다"
expect_absent "머지로 추가된 새 커밋이 없습니다"   # 부재 단언 — 오작동 경고 제거
expect_absent "빈 배포"                            # 부재 단언
expect_ver 0.1.1
git fetch -q origin --prune
[ "$(count_in origin/staging/0.1 "Merge branch 'feature/FE-X'")" -eq 1 ]; ok "머지 커밋 1개" $?
[ "$(count_in origin/staging/0.1 'chore: staging deploy')" -eq 1 ]; ok "bump 커밋 1개 (버전 1회 상승)" $?

# ══ R6  bump 커밋 실패 ════════════════════════════════════════════════
case_hdr "R6  bump 후 커밋 실패(훅 거부) → 워킹트리 클린 + 롤백"
fixture_staging r6
BASE="$(git rev-parse staging/0.1)"
REMOTE_BEFORE="$(remote_sha staging/0.1)"
# git merge --no-ff 는 pre-commit 이 아니라 pre-merge-commit 을 쓴다 — 그래서 이 훅으로는
# ⑤ 의 bump 커밋만 정확히 실패시킬 수 있다(머지는 정상 통과). 훅 파일은 untracked 라
# --untracked-files=no 를 쓰는 워킹트리 검사에 걸리지 않는다.
printf '#!/usr/bin/env sh\nexit 1\n' > .husky/pre-commit; chmod +x .husky/pre-commit
run "bash scripts/merge-staging.sh feature/FE-X"
rm -f .husky/pre-commit
expect_blocked
expect_has "버전 bump·커밋 단계가 실패했습니다"
expect_clean_tree                            # staged 로 남은 bump 산출물까지 정리
expect_rolled_back "${BASE}" staging/0.1
expect_unpushed 0 staging/0.1
expect_ver 0.1.0
[ "$(remote_sha staging/0.1)" = "${REMOTE_BEFORE}" ]; ok "원격 staging/0.1 무변경" $?
head_is feature/FE-X

# ══ R7  머지 충돌 — 롤백하지 않는다 ══════════════════════════════════
case_hdr "R7  머지 충돌 → 기존 동작 유지 (롤백 없음 · staging 잔류, #27 회귀)"
fixture_staging r7
git switch -q staging/0.1; echo staging > a.txt; git commit -qam "fix: s"; git push -q origin staging/0.1
git switch -q feature/FE-X;  echo work    > a.txt; git commit -qam "fix: w"; git push -q origin feature/FE-X
run "bash scripts/merge-staging.sh feature/FE-X"
expect_blocked
expect_has "머지 충돌이 발생했습니다"
expect_absent "시작 상태로 되돌렸습니다"        # 부재 단언 — 충돌은 롤백 대상이 아니다
head_is staging/0.1
[ -e .git/MERGE_HEAD ]; ok "머지 진행 중 상태 유지 (사용자가 해결·커밋)" $?
git merge --abort >/dev/null 2>&1 || true

# ══ R8  정상 완주 회귀 ════════════════════════════════════════════════
case_hdr "R8  정상 완주 회귀 (bump 1회 · staging 태그 갱신 · ORIG_BRANCH 복귀)"
fixture_staging r8
run "bash scripts/merge-staging.sh feature/FE-X"
expect_success
expect_ver 0.1.1
git fetch -q origin --prune
expect_same staging/0.1 origin/staging/0.1
[ "$(git rev-parse 'staging^{commit}')" = "$(git rev-parse staging/0.1)" ]; ok "staging 태그 == staging/0.1 tip" $?
[ -n "$(git ls-remote --tags origin refs/tags/staging | cut -f1)" ]; ok "원격에 staging 태그 존재 (배포 트리거)" $?
[ "$(count_in origin/staging/0.1 'chore: staging deploy')" -eq 1 ]; ok "bump 커밋 1개" $?
head_is feature/FE-X
expect_has "브랜치로 돌아왔습니다"

# ══ R9  배포 트리거 태그 push 실패 — 롤백하지 않는다 ═════════════════
case_hdr "R9  태그 push 실패 → 롤백 없음 (브랜치는 이미 원격 반영됨 = 되돌리면 이중 bump)"
fixture_staging r9
# 브랜치 push 성공 직후, 태그 push '직전'에 origin 을 치워 태그 push 만 실패시킨다.
run "RACE_ON='push --force origin refs/tags/staging' \
     RACE_MARK='${WORK}/r9.raced' \
     RACE_CMD='mv ${WORK}/r9.git ${WORK}/r9.git.gone' \
     bash scripts/merge-staging.sh feature/FE-X"
mv "${WORK}/r9.git.gone" "${WORK}/r9.git" 2>/dev/null || true
expect_blocked
expect_has "태그만 다시 밀면 됩니다"
expect_absent "시작 상태로 되돌렸습니다"        # 부재 단언 — 되돌리면 원격보다 뒤처진다
head_is staging/0.1                            # 안내 명령이 staging/* 를 요구한다
expect_ver 0.1.1
git fetch -q origin --prune
expect_same staging/0.1 origin/staging/0.1     # 브랜치 push 는 이미 성공했다
[ -z "$(git ls-remote --tags origin refs/tags/staging | cut -f1)" ]; ok "원격 staging 태그 미생성 (배포 미트리거)" $?

harness_summary
