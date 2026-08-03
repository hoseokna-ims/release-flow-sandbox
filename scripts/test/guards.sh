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

case_hdr "G3  태그가 이미 원격에 있으면 master 단독 push 허용"
fixture g3 release
phase2_state
git push -q origin 0.2.0          # 태그만 따로 먼저
git switch -q master
run "git push origin master"
expect_success

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

harness_summary
