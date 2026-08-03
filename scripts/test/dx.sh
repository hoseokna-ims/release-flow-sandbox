#!/usr/bin/env bash
#
# 중단 복구 DX 검증 (FE-1040)
#   A) 중단 후 브랜치 밖에서 재실행 → 자동 이어받기 (git switch 불필요)
#   B) Phase 1 중단이 남긴 자기 산출물 → stash 없이 그대로 이어감
# 오작동 방지(브랜치 오선택·모호한 후보·사용자 변경 혼입)도 함께 본다.
#
# 사용법: bash scripts/test/dx.sh
#
source "$(dirname "$0")/lib/harness.sh"
harness_init dx

# ── A: 자동 이어받기 ──────────────────────────────────────────────────
case_hdr "A1  Phase 2(태그 직전) 중단 → HEAD=master 에서 그대로 재실행"
fixture a1 release
KILL_ON='tag -a -m 0.2.0 0.2.0' bash scripts/release.sh finish >/dev/null 2>&1
head_is master
run "RELEASE_ASSUME_YES=1 bash scripts/release.sh finish"
expect_success
expect_has "release/0.2.0 로 전환해 이어서 진행"
released

case_hdr "A2  Phase 3(push 직전) 중단 → HEAD=develop 에서 그대로 재실행"
fixture a2 release
KILL_ON='push --atomic origin master develop 0.2.0' bash scripts/release.sh finish >/dev/null 2>&1
head_is develop
run "RELEASE_ASSUME_YES=1 bash scripts/release.sh finish"
expect_success
released

case_hdr "A3  hotfix 도 동일하게 이어받기"
fixture a3 hotfix
echo fix > fix.txt; git add fix.txt; git commit -qm "fix: x"
KILL_ON='push --atomic origin master develop 0.2.0' bash scripts/hotfix.sh finish >/dev/null 2>&1
run "RELEASE_ASSUME_YES=1 bash scripts/hotfix.sh finish"
expect_success
released

case_hdr "A4  사용자 실수(start 직후 develop 에서 finish) → 자동 전환 안 함"
fixture a4 release
git switch -q develop
run "bash scripts/release.sh finish"
expect_blocked
expect_has "git switch release/0.2.0"
expect_absent "전환해 이어서 진행"

case_hdr "A5  이어받을 후보가 둘이면 추측하지 않음"
fixture a5 release
# 태그 없이 master 에 머지된 bump 브랜치를 둘 만든다(조건 ③ 은 태그가 없으면 통과).
# 두 번째는 '첫 머지 이후의 master' 에서 따야 package.json 이 충돌하지 않는다
# (충돌하면 merging 중 상태가 되어 다른 이유로 실패해 테스트가 무의미해진다).
node scripts/bump-version.mjs 0.2.0 >/dev/null; git add -A >/dev/null
git commit -qm "chore: release 0.2.0"
git checkout -q master; GIT_MERGE_AUTOEDIT=no git merge -q --no-ff release/0.2.0 >/dev/null
git switch -q -c release/0.3.0 master
node scripts/bump-version.mjs 0.3.0 >/dev/null; git add -A >/dev/null
git commit -qm "chore: release 0.3.0"
git checkout -q master; GIT_MERGE_AUTOEDIT=no git merge -q --no-ff release/0.3.0 >/dev/null
git switch -q develop
[ ! -e .git/MERGE_HEAD ]; ok "픽스처 전제: 머지 진행중 아님" $?
run "bash scripts/release.sh finish"
expect_blocked
expect_has "release/* 브랜치에서 실행하세요"
expect_absent "전환해 이어서 진행"

# ── B: Phase 1 자기 산출물 ────────────────────────────────────────────
case_hdr "B1  Phase 1(bump 커밋 직전) 중단 → stash 없이 그대로 재실행"
fixture b1 release
KILL_ON='commit -qm chore: release 0.2.0' bash scripts/release.sh finish >/dev/null 2>&1
[ -n "$(git status --porcelain --untracked-files=no)" ]; ok "워킹트리 더러움(중단 흔적)" $?
run "bash scripts/release.sh finish"
expect_success
expect_has "중단된 준비 단계의 산출물"
released
[ "$(git show origin/master:CHANGELOG.md | grep -c '^## \[0.2.0\]')" -eq 1 ]; ok "CHANGELOG 섹션 중복 없음" $?

case_hdr "B2  사용자 변경이 섞이면 여전히 차단"
fixture b2 release
KILL_ON='commit -qm chore: release 0.2.0' bash scripts/release.sh finish >/dev/null 2>&1
echo "user work" >> a.txt          # 산출물 외 파일 수정
run "bash scripts/release.sh finish"
expect_blocked
expect_has "커밋하거나 git stash"

case_hdr "B3  bump 안 된 상태의 CHANGELOG 수정은 차단 (우리 산출물 아님)"
fixture b3 release
echo "manual" >> CHANGELOG.md 2>/dev/null || echo "manual" > CHANGELOG.md
git add CHANGELOG.md >/dev/null 2>&1 || true
run "bash scripts/release.sh finish"
expect_blocked

case_hdr "B5  bump 커밋 + 산출물 더러움 → 되돌리고 skip (FE-1043)"
# Phase 0 는 산출물 더러움을 통과시키고 Phase 1 은 bump 커밋이 있으면 skip 한다.
# 둘이 동시에 성립하면 더러운 파일이 Phase 2 까지 살아남아 checkout 을 막았다.
fixture b5 release
node scripts/bump-version.mjs 0.2.0 >/dev/null
node scripts/changelog.mjs 0.2.0 >/dev/null
git add -A >/dev/null; git commit -qm "chore: release 0.2.0"
echo "- 손으로 한 줄 추가" >> CHANGELOG.md
run "RELEASE_ASSUME_YES=1 bash scripts/release.sh finish"
expect_success
expect_has "남은 산출물 변경을 되돌리고 skip"
released
git merge-base --is-ancestor 0.2.0^{commit} master; ok "태그가 master 계보 위" $?

case_hdr "B4  정상 플로우 회귀 (깨끗한 트리)"
fixture b4 release
run "bash scripts/release.sh finish"
expect_success
released

harness_summary
