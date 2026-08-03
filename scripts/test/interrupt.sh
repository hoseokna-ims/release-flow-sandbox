#!/usr/bin/env bash
#
# 강제 중단 복구 검증 — finish 를 각 단계 경계에서 kill -9 로 죽였을 때
#   ① 토픽 브랜치가 살아남는가  ② 재실행으로 완주하는가
# 를 확인한다. set -e 의 ERR 트랩은 시그널에 걸리지 않으므로, 롤백이 전혀
# 돌지 않는 최악의 중단(Ctrl-C·터미널 종료·크래시)을 재현하는 것이 목적이다.
#
# 사용법: bash scripts/test/interrupt.sh
#
source "$(dirname "$0")/lib/harness.sh"
harness_init interrupt

case_hdr "I1  Phase 1 — bump 커밋 직전 강제 종료"
fixture i1 release
KILL_ON='commit -qm chore: release 0.2.0' bash scripts/release.sh finish >/dev/null 2>&1
alive release/0.2.0
[ -n "$(git status --porcelain --untracked-files=no)" ]; ok "워킹트리 더러움(중단 흔적)" $?
run "bash scripts/release.sh finish"
# 남은 게 Phase 1 자기 산출물뿐이면 stash 없이 다시 생성해 이어간다 (FE-1040)
expect_success
expect_has "중단된 준비 단계의 산출물"
released

case_hdr "I2  Phase 2 — master 머지 직후, 태그 직전 강제 종료"
fixture i2 release
KILL_ON='tag -a -m 0.2.0 0.2.0' bash scripts/release.sh finish >/dev/null 2>&1
alive release/0.2.0
head_is master
[ "$(git rev-list --count origin/master..master)" -gt 0 ]; ok "master 가 ahead 상태로 남음" $?
expect_no_tag 0.2.0
run "git switch -q release/0.2.0 && RELEASE_ASSUME_YES=1 bash scripts/release.sh finish"
expect_success
expect_has "중단된 finish 의 재실행"
released

case_hdr "I3  Phase 2 — 태그 직후, develop 되머지 직전 강제 종료"
fixture i3 release
KILL_ON='merge --no-ff 0.2.0' bash scripts/release.sh finish >/dev/null 2>&1
alive release/0.2.0
expect_tag 0.2.0
[ "$(git rev-list --count origin/develop..develop)" -eq 0 ]; ok "develop 되머지 아직 안 됨" $?
run "git switch -q release/0.2.0 && RELEASE_ASSUME_YES=1 bash scripts/release.sh finish"
expect_success
released

case_hdr "I4  Phase 3 — push 직전 강제 종료"
fixture i4 release
KILL_ON='push --atomic origin master develop 0.2.0' bash scripts/release.sh finish >/dev/null 2>&1
alive release/0.2.0
head_is develop
[ "$(git rev-list --count origin/master..master)" -gt 0 ] && [ "$(git rev-list --count origin/develop..develop)" -gt 0 ]
ok "master·develop 둘 다 ahead" $?
[ "$(git rev-parse origin/master)" != "$(git rev-parse master)" ]; ok "원격은 무변경" $?
run "git switch -q release/0.2.0 && RELEASE_ASSUME_YES=1 bash scripts/release.sh finish"
expect_success
released

case_hdr "I5  중단 후 브랜치 밖에서 재실행 → 자동 이어받기 (FE-1040)"
fixture i5 release
KILL_ON='push --atomic origin master develop 0.2.0' bash scripts/release.sh finish >/dev/null 2>&1
run "RELEASE_ASSUME_YES=1 bash scripts/release.sh finish"   # HEAD=develop 인 상태 그대로
expect_success
expect_has "중단된 finish 를 발견했습니다"
released

case_hdr "I6  push 실패(preflight 이후 원격 선행) — 롤백 경로"
fixture i6 release
# 다른 클론을 미리 준비하고, 우리 push '직전'에 origin/master 를 진행시킨다.
# (픽스처 직후에 밀면 Phase 0 의 fetch 에서 behind 로 먼저 막혀 롤백 경로를 못 탄다)
CL="${WORK}/i6-other"; "${GIT_REAL}" clone -q "${WORK}/i6.git" "${CL}" 2>/dev/null
( cd "${CL}"
  "${GIT_REAL}" config user.email test@example.com; "${GIT_REAL}" config user.name test
  "${GIT_REAL}" switch -q master; echo z > z.txt; "${GIT_REAL}" add z.txt
  "${GIT_REAL}" commit -qm "chore: other" ) >/dev/null 2>&1
BASE_MASTER_SHA="$(git rev-parse master)"; BASE_ORIGIN_DEV="$(git rev-parse origin/develop)"
run "RACE_ON='push --atomic origin master develop 0.2.0' \
     RACE_MARK='${WORK}/i6.raced' \
     RACE_CMD='cd ${CL} && ${GIT_REAL} push -q origin master' \
     bash scripts/release.sh finish"
expect_blocked
expect_has "원격은 --atomic 으로 아무것도 반영되지 않았고"
alive release/0.2.0
[ "$(git rev-parse master)" = "${BASE_MASTER_SHA}" ]; ok "master 가 시작 SHA 로 정확히 롤백" $?
expect_no_tag 0.2.0
git fetch -q origin --prune
[ "$(git rev-parse origin/develop)" = "${BASE_ORIGIN_DEV}" ]; ok "원격 develop 무반영(스플릿 없음)" $?
run "git switch -q develop && git pull -q && git switch -q master && git pull -q \
     && git switch -q release/0.2.0 && bash scripts/release.sh finish"
expect_success
released

harness_summary
