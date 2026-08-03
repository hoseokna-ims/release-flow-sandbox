#!/usr/bin/env bash
#
# 바깥 문(pre-push · push-tag) 가드 검증. (FE-1042)
#
#  G1~G3  pre-push 태그 동반 검사 — master 만 올라가 '반쯤 릴리스' 되는 경로를 막는다
#  G4~G5  이식성 — bash 전용 스크립트를 sh 로 부르지 않는지, sh 로 실행되는 파일이
#         POSIX 문법인지 (macOS 는 /bin/sh 가 bash 라 로컬에서 드러나지 않는다)
#
# 사용법: bash scripts/test/guards.sh
#
source "$(dirname "$0")/lib/harness.sh"
harness_init guards

remote_master() { git ls-remote origin refs/heads/master 2>/dev/null | cut -f1; }

case_hdr "G1  태그 없이 master 단독 push → 차단"
fixture g1 release
phase2_state
git switch -q master
run "git push origin master"
expect_blocked
expect_has "이번 push 에 포함되지 않았습니다"
[ "$(remote_master)" != "$(git rev-parse master)" ]; ok "원격 master 무변경" $?

case_hdr "G2  --atomic 으로 태그 동봉 → 통과 (정상 플로우 회귀)"
fixture g2 release
phase2_state
run "git push --atomic origin master develop 0.2.0"
expect_success
released

case_hdr "G3  semver 태그 단독 push → 차단 (master 계보 밖)"
# master ref 가 push 에 없으면 위 루프는 아예 돌지 않는다. 머지·태그가 어긋난 릴리스는
# '태그만' push 되므로(master/develop 가 원격과 같으면 git 이 그 ref 를 안 보낸다)
# 태그 쪽도 따로 검사해야 한다.
fixture g3 release
phase2_state
run "git push origin 0.2.0"
expect_blocked
expect_has "master 계보 위에 있지 않습니다"
[ -z "$(git ls-remote origin 'refs/tags/0.2.0')" ]; ok "원격에 태그 생성 안 됨" $?

case_hdr "G4  bash 전용 스크립트를 sh 로 호출하지 않는다"
# push-tag.sh 의 셔뱅은 #!/bin/bash 인데 `sh scripts/push-tag.sh` 로 부르면 셔뱅이 무시된다.
# dash 인 환경(Ubuntu·WSL)에서 `set -o pipefail` 로 즉시 죽는다.
HITS="$(grep -rnE '\bsh +scripts/[a-z-]+\.sh' "${SRC}/scripts" 2>/dev/null | grep -vE ':[[:space:]]*#' || true)"
[ -z "${HITS}" ]; ok "sh 로 호출하는 곳 없음${HITS:+ — 발견: ${HITS}}" $?

case_hdr "G5  sh 로 실행되는 파일은 POSIX 문법"
if command -v dash >/dev/null 2>&1; then
  dash -n "${SRC}/.husky/pre-push" 2>/dev/null
  ok "pre-push 가 POSIX 문법 (dash -n)" $?
else
  printf '  ⏭  dash 미설치 — 건너뜀 (macOS /bin/sh 는 bash 라 로컬 재현 불가)\n'
fi

case_hdr "G6  master 가 다른 worktree 에 점유되면 Phase 0 에서 차단"
# checkout 실패는 finish 도중에 잡는 것보다 시작 전에 막는 편이 낫다.
fixture g6 hotfix
echo fix > fix.txt; git add fix.txt; git commit -qm "fix: x"
git worktree add -q "${WORK}/g6-wt" master
run "RELEASE_ASSUME_YES=1 bash scripts/hotfix.sh finish"
expect_blocked
expect_has "다른 worktree 에 체크아웃돼 있습니다"
expect_no_tag 0.2.0
expect_same master origin/master

case_hdr "G7  topic_merge_and_tag 는 checkout 실패를 성공으로 처리하지 않는다"
# Phase 0 가드를 우회해 함수를 직접 호출한다 — 방어 두 겹이 각각 동작하는지 확인.
# 예전에는 checkout 이 실패해도 자기 자신을 머지해 "Already up to date" 로 넘어가고,
# 태그가 master 가 아닌 토픽 tip 에 붙은 채 0 을 반환했다.
fixture g7 hotfix
echo fix > fix.txt; git add fix.txt; git commit -qm "fix: x"
git worktree add -q "${WORK}/g7-wt" master
run "bash -c 'source scripts/lib/checks.sh; topic_merge_and_tag hotfix 0.2.0'"
expect_blocked
expect_has "master 로 전환하지 못했습니다"
expect_no_tag 0.2.0

harness_summary
