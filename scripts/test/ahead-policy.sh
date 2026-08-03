#!/usr/bin/env bash
#
# 동기화 정책 검증 — behind/diverged/ahead 를 전부 차단하고,
# 중단된 finish 재실행만 예외로 통과시키는지 확인한다. (FE-1039)
#
# 사용법: bash scripts/test/ahead-policy.sh
#
source "$(dirname "$0")/lib/harness.sh"
harness_init ahead-policy

commit_on() { # commit_on <브랜치> <파일이름>
  git switch -q "$1"; echo "$2" > "$2.txt"; git add "$2.txt"; git commit -qm "feat: $2"
}

# Phase 2(머지·태그)까지 끝나고 push 전에 죽은 상태를, 실제 함수를 호출해 재현한다.
phase2_state() {
  node scripts/bump-version.mjs 0.2.0 >/dev/null
  node scripts/changelog.mjs 0.2.0 >/dev/null
  git add -A >/dev/null; git commit -qm "chore: release 0.2.0"
  bash -c 'source scripts/lib/checks.sh; topic_merge_and_tag release 0.2.0' >/dev/null 2>&1
  git switch -q release/0.2.0
}

case_hdr "T1  release start / develop behind → 차단"
fixture t1
commit_on develop b; git push -q origin develop; git reset -q --hard HEAD~1
run "bash scripts/release.sh start"
expect_blocked
expect_has "뒤처졌습니다"

case_hdr "T2  release start / develop ahead → 차단"
fixture t2
commit_on develop b
run "bash scripts/release.sh start"
expect_blocked
expect_has "push 안 된 로컬 커밋"
expect_has "git switch develop && git push"

case_hdr "T3  release start / master ahead → 차단 (진단 안내)"
fixture t3
commit_on master b; git switch -q develop
run "bash scripts/release.sh start"
expect_blocked
expect_has "우회 조작의 흔적"
expect_has "직접 push 하지 마세요"

case_hdr "T4  hotfix start / master ahead → 차단"
fixture t4
commit_on master b
run "bash scripts/hotfix.sh start"
expect_blocked
expect_has "우회 조작의 흔적"

case_hdr "T5  hotfix start / develop ahead → 차단"
fixture t5
commit_on develop b; git switch -q master
run "bash scripts/hotfix.sh start"
expect_blocked
expect_has "git switch develop && git push"

case_hdr "T6  release finish / develop ahead(재실행 아님) → 차단 + 무변경"
fixture t6 release
commit_on develop b; git switch -q release/0.2.0
run "bash scripts/release.sh finish"
expect_blocked
expect_has "push 안 된 로컬 커밋"
expect_no_tag 0.2.0
expect_same master origin/master
[ "$(git log -1 --format=%s release/0.2.0)" != "chore: release 0.2.0" ]; ok "bump 커밋 생성 안 됨" $?

case_hdr "T7  hotfix finish / bump 없이 머지·태그만 된 상태 → 재실행 오인 없이 차단"
fixture t7 hotfix
echo fix > fix.txt; git add fix.txt; git commit -qm "fix: x"
git checkout -q master; GIT_MERGE_AUTOEDIT=no git merge -q --no-ff hotfix/0.2.0 >/dev/null
git tag -a -m 0.2.0 0.2.0; git switch -q hotfix/0.2.0
MASTER_BEFORE="$(git rev-parse master)"
run "bash scripts/hotfix.sh finish"
expect_blocked
expect_has "우회 조작의 흔적"
[ "$(git rev-parse master)" = "${MASTER_BEFORE}" ]; ok "master 무변경" $?

case_hdr "T8  release finish 재실행(Phase 2 완료) → 예외 통과 후 완료"
fixture t8 release
phase2_state
run "RELEASE_ASSUME_YES=1 bash scripts/release.sh finish"
expect_success
expect_has "중단된 finish 의 재실행으로 보입니다"
expect_same master origin/master
released

case_hdr "T9  재실행 + 비대화형 + ASSUME_YES 없음 → 안전 중단"
fixture t9 release
phase2_state
run "bash scripts/release.sh finish </dev/null"
expect_blocked
expect_has "비대화형"

case_hdr "T10 정상 release start→finish (회귀)"
fixture t10
run "bash scripts/release.sh start && bash scripts/release.sh finish"
expect_success
released
! git rev-parse -q --verify refs/heads/release/0.2.0 >/dev/null; ok "release 브랜치 삭제됨" $?

case_hdr "T11 정상 hotfix start→finish (회귀)"
fixture t11 hotfix
echo fix > fix.txt; git add fix.txt; git commit -qm "fix: x"
run "bash scripts/hotfix.sh finish"
expect_success
released

case_hdr "T12 release start / develop diverged → 차단"
fixture t12
commit_on develop b; git push -q origin develop; git reset -q --hard HEAD~1
echo c > c.txt; git add c.txt; git commit -qm "feat: c"
run "bash scripts/release.sh start"
expect_blocked
expect_has "갈라졌습니다"

harness_summary
