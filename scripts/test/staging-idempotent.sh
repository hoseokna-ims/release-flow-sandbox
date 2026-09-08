#!/usr/bin/env bash
#
# 스테이징 bump 멱등화 검증 (FE-1046)
#
# 두 스크립트 모두 실행마다 무조건 patch +1 + "chore: staging deploy <ver>" 커밋을 만들었다.
# 그런데 merge-staging.sh 의 실패 안내가 "staging:deploy 로 마무리" 이고, ⑥ push 도중에
# 죽으면 미푸시 bump 커밋이 남는다 — 두 경우 모두 재실행이 patch 를 한 번 더 올려
# 배포된 적 없는 버전 번호를 소비했다.
#
# 여기서 확인하는 것
#   ① 이 버전의 미푸시 bump 커밋이 있으면 bump·changelog·커밋을 건너뛰는가
#   ② 사람이 흉내낸 커밋·이미 push 된 커밋을 재실행으로 오인하지 않는가 (판정 4조건)
#   ③ 내용이 달라졌으면(머지가 새 커밋을 추가) 그대로 bump 하는가 — changelog 정확성
#   ④ 정상 경로가 회귀하지 않는가
#
# 사용법: bash scripts/test/staging-idempotent.sh
#
source "$(dirname "$0")/lib/harness.sh"
harness_init staging-idempotent

# origin/staging/0.1 을 한 커밋 앞서게 만든다. package.json 은 건드리지 않는다 —
# 픽스처에는 maxversion 머지 드라이버가 없어(setup-versioning.sh 미실행) 양쪽이 version 을
# 고치면 pull 이 충돌해 다른 이유로 실패한다.
advance_remote() {
  local N="$1" CL="${WORK}/$1-other"
  "${GIT_REAL}" clone -q "${WORK}/${N}.git" "${CL}" 2>/dev/null
  ( cd "${CL}"
    "${GIT_REAL}" config user.email test@example.com; "${GIT_REAL}" config user.name test
    "${GIT_REAL}" switch -q staging/0.1; echo o > o.txt; "${GIT_REAL}" add o.txt
    "${GIT_REAL}" commit -qm "feat: other"; "${GIT_REAL}" push -q origin staging/0.1 ) >/dev/null 2>&1
}

# 판정 함수만 떼어 직접 호출한다 (guards.sh G7 과 같은 방식).
found_bump() { bash -c 'source scripts/lib/checks.sh; staging_unpushed_bump staging/0.1'; }

bumps_in()  { count_in "$1" 'chore: staging deploy'; }

# ══ D1  미푸시 bump 커밋 → skip ═══════════════════════════════════════
case_hdr "D1  미푸시 bump 커밋 존재 → staging:deploy 재실행이 skip (버전 불변)"
fixture_staging d1
git switch -q staging/0.1
KILL_ON='push origin HEAD:staging/0.1' bash scripts/deploy-staging.sh >/dev/null 2>&1
expect_unpushed 1 staging/0.1
expect_ver 0.1.1
run "RELEASE_ASSUME_YES=1 bash scripts/deploy-staging.sh"
expect_success
expect_has "bump·changelog·커밋을 건너뜁니다"
expect_has "chore: staging deploy 0.1.1"
expect_ver 0.1.1
git fetch -q origin --prune
expect_same staging/0.1 origin/staging/0.1
[ "$(bumps_in origin/staging/0.1)" -eq 1 ]; ok "bump 커밋 1개 (버전 1회 상승)" $?
[ "$(git rev-parse 'staging^{commit}')" = "$(git rev-parse staging/0.1)" ]; ok "staging 태그 == tip (배포 트리거 정상)" $?

# ══ D2  bump 커밋 없음 → 기존대로 ════════════════════════════════════
case_hdr "D2  bump 커밋 없음 → 기존대로 patch +1 (회귀)"
fixture_staging d2
git switch -q staging/0.1
run "bash scripts/deploy-staging.sh"
expect_success
expect_absent "건너뜁니다"                      # 부재 단언
expect_ver 0.1.1
git fetch -q origin --prune
[ "$(bumps_in origin/staging/0.1)" -eq 1 ]; ok "bump 커밋 1개" $?

# ══ D3  판정 4조건 (직접 호출) ════════════════════════════════════════
case_hdr "D3  staging_unpushed_bump 판정 — 정상 bump 커밋만 찾는다"
fixture_staging d3
git switch -q staging/0.1
node scripts/bump-version.mjs patch >/dev/null
git add package.json; git commit -qm "chore: staging deploy 0.1.1"
[ -n "$(found_bump)" ]; ok "① 정상 미푸시 bump 커밋을 찾는다" $?
git push -q origin HEAD:staging/0.1; git fetch -q origin --prune
[ -z "$(found_bump)" ]; ok "③ 이미 push 된 bump 커밋은 찾지 않는다" $?

case_hdr "D3b 버전이 package.json 과 다른 커밋 → 찾지 않는다"
fixture_staging d3b
git switch -q staging/0.1
git commit -q --allow-empty -m "chore: staging deploy 0.9.9"    # package.json 은 0.1.0
[ -z "$(found_bump)" ]; ok "② 버전 불일치 커밋은 찾지 않는다" $?

case_hdr "D3c version 을 올리지 않은 커밋 → 찾지 않는다"
fixture_staging d3c
git switch -q staging/0.1
git commit -q --allow-empty -m "chore: staging deploy 0.1.0"    # 제목·버전은 맞지만 빈 커밋
[ -z "$(found_bump)" ]; ok "④ version 을 올리지 않은 커밋은 찾지 않는다" $?
# 실제 스크립트도 이 커밋을 재실행으로 오인하지 않아야 한다
run "RELEASE_ASSUME_YES=1 bash scripts/deploy-staging.sh"
expect_success
expect_absent "건너뜁니다"                      # 부재 단언
expect_ver 0.1.1                               # 그대로 bump 했다

# ══ D4  이미 push 된 bump 커밋 → skip 안 함 ══════════════════════════
case_hdr "D4  이미 push 된 bump 커밋 → skip 하지 않음 (의도한 재배포)"
fixture_staging d4
git switch -q staging/0.1
bash scripts/deploy-staging.sh >/dev/null 2>&1
git fetch -q origin --prune
expect_ver 0.1.1
run "bash scripts/deploy-staging.sh"
expect_success
expect_absent "건너뜁니다"                      # 부재 단언
expect_ver 0.1.2
git fetch -q origin --prune
[ "$(bumps_in origin/staging/0.1)" -eq 2 ]; ok "bump 커밋 2개 (배포 2회니까 맞다)" $?

# ══ D5  FE-1044 롤백 후 deploy ════════════════════════════════════════
case_hdr "D5  FE-1044 롤백 후 staging:deploy → 버전 1회만 상승"
fixture_staging d5
prepush_fail_on
bash scripts/merge-staging.sh feature/FE-X >/dev/null 2>&1     # pre-push 거부 → 롤백
prepush_fail_off
expect_unpushed 0 staging/0.1                  # 롤백으로 아무것도 남지 않았다
expect_ver 0.1.0
git switch -q staging/0.1
run "bash scripts/deploy-staging.sh"
expect_success
expect_ver 0.1.1
git fetch -q origin --prune
[ "$(bumps_in origin/staging/0.1)" -eq 1 ]; ok "bump 커밋 1개" $?

# ══ D6  미푸시 bump 위에 pull 머지 커밋 ═══════════════════════════════
case_hdr "D6  미푸시 bump 커밋 위에 pull 머지 커밋이 얹힌 상태 → skip"
fixture_staging d6
git switch -q staging/0.1
KILL_ON='push origin HEAD:staging/0.1' bash scripts/deploy-staging.sh >/dev/null 2>&1
advance_remote d6
git pull --no-rebase --no-edit -q origin staging/0.1
[ "$(git rev-list --count --merges "origin/staging/0.1..staging/0.1")" -ge 1 ]; ok "pull 머지 커밋이 얹혔다 (HEAD 가 bump 커밋이 아니다)" $?
expect_ver 0.1.1
run "RELEASE_ASSUME_YES=1 bash scripts/deploy-staging.sh"
expect_success
expect_has "bump·changelog·커밋을 건너뜁니다"
expect_ver 0.1.1
git fetch -q origin --prune
expect_same staging/0.1 origin/staging/0.1
[ "$(bumps_in origin/staging/0.1)" -eq 1 ]; ok "bump 커밋 1개 (버전 1회만 상승)" $?

# ══ D7  merge-staging 재실행 — 미푸시 bump + 머지할 새 커밋 없음 ═════
case_hdr "D7  staging:merge 재실행 (미푸시 bump 존재 · 새 머지 없음) → skip (확장 범위 핵심)"
# ※ 이 상태를 merge-staging.sh 에 KILL_ON 을 걸어 만들 수는 없다 — FE-1044 가 push 출력을
#   $(...) 로 버퍼링하므로 셔임의 kill $PPID 는 캡처 서브셸만 죽이고, 스크립트는 push 실패로
#   보고 롤백을 완주한다(실측). 실제로 이 상태를 만드는 것은 스크립트 전체에 오는 시그널
#   (Ctrl-C·크래시)이므로, 여기서는 같은 상태를 실제 스크립트 실행으로 조립한다.
fixture_staging d7
bash scripts/merge-staging.sh feature/FE-X >/dev/null 2>&1        # ① 정상 배포 (0.1.1 push)
git switch -q staging/0.1
KILL_ON='push origin HEAD:staging/0.1' bash scripts/deploy-staging.sh >/dev/null 2>&1  # ② 미푸시 bump 0.1.2
expect_unpushed 1 staging/0.1
expect_ver 0.1.2
git switch -q feature/FE-X
run "RELEASE_ASSUME_YES=1 bash scripts/merge-staging.sh feature/FE-X"   # ③ 머지할 새 커밋 없음
expect_success
expect_has "중단된 실행의 재개입니다"
expect_has "bump·changelog·커밋을 건너뜁니다"
expect_absent "머지로 추가된 새 커밋이 없습니다"   # 부재 단언 — 빈 배포 경고가 아니다
expect_ver 0.1.2                                # 수정 전에는 0.1.3 이 됐다
git fetch -q origin --prune
expect_same staging/0.1 origin/staging/0.1
[ "$(bumps_in origin/staging/0.1)" -eq 2 ]; ok "bump 커밋 2개 (①의 0.1.1 + ②의 0.1.2 — ③ 이 더 만들지 않았다)" $?
[ "$(count_in origin/staging/0.1 "Merge branch 'feature/FE-X'")" -eq 1 ]; ok "머지 커밋 1개 (중복 머지 없음)" $?

case_hdr "D7b merge-staging 의 push 를 셔임으로 죽이면 롤백이 돈다 (위 주석의 근거)"
fixture_staging d7b
BASE="$(git rev-parse staging/0.1)"
run "KILL_ON='push origin HEAD:staging/0.1' bash scripts/merge-staging.sh feature/FE-X"
expect_blocked
[ "$(git rev-parse staging/0.1)" = "${BASE}" ]; ok "staging/0.1 == pull 후 SHA (롤백 완주)" $?
expect_unpushed 0 staging/0.1
expect_ver 0.1.0

# ══ D8  내용이 달라졌으면 bump 한다 ══════════════════════════════════
case_hdr "D8  미푸시 bump 위에 새 머지가 얹히면 skip 하지 않는다 (changelog 정확성)"
fixture_staging d8
git switch -q staging/0.1
KILL_ON='push origin HEAD:staging/0.1' bash scripts/deploy-staging.sh >/dev/null 2>&1
expect_ver 0.1.1
git switch -q feature/FE-X
run "RELEASE_ASSUME_YES=1 bash scripts/merge-staging.sh feature/FE-X"
expect_success
expect_absent "bump·changelog·커밋을 건너뜁니다"   # 부재 단언 — 내용이 달라졌다
expect_ver 0.1.2
git fetch -q origin --prune
# skip 했다면 0.1.1 시점의 changelog 가 그대로 배포돼 새 머지가 누락된다
git show origin/staging/0.1:STAGING_CHANGELOG.md | grep -qF 'feature/FE-X'
ok "STAGING_CHANGELOG 에 새로 머지된 내용이 반영됨" $?

harness_summary
