#!/usr/bin/env bash
#
# 릴리스 플로우 검증 하네스 공용 라이브러리.
#
# 격리 방식: 케이스마다 로컬 bare 리포를 origin 으로 만들고 그 클론에서만 스크립트를 돌린다.
# 실제 리포와 실제 원격은 절대 건드리지 않는다.
#
# 사용법 (케이스 파일 맨 위):
#   source "$(dirname "$0")/lib/harness.sh"
#   harness_init ahead-policy
#
# 다른 리포의 스크립트를 검증하려면 SRC 로 그 리포 루트를 지정한다:
#   SRC=/path/to/imsform-mobile-web bash scripts/test/ahead-policy.sh
#
set -uo pipefail

SRC="${SRC:-$(git rev-parse --show-toplevel)}"
GIT_REAL="$(command -v git)"

PASS=0; FAIL=0; FAILED=(); OUT=""; ST=0; REPO=""; WORK=""; HARNESS_NAME=""

# ── 초기화 ────────────────────────────────────────────────────────────
harness_init() {
  HARNESS_NAME="$1"
  WORK="${TMPDIR:-/tmp}/release-flow-test/${HARNESS_NAME}"

  # 검사 대상이 이식된 리포인지 먼저 확인한다. 없는 채로 진행하면 케이스가
  # '조용히' 엉뚱한 이유로 실패해 원인 파악이 어려워진다.
  [ -f "${SRC}/scripts/lib/checks.sh" ] || {
    echo "❌ ${SRC}/scripts/lib/checks.sh 가 없습니다 — 이식되지 않은 리포입니다." >&2
    exit 1
  }
  grep -q '^ZERO=' "${SRC}/.husky/pre-push" 2>/dev/null || {
    echo "❌ ${SRC}/.husky/pre-push 에 가드 블록(ZERO=)이 없습니다 — 이식되지 않은 리포입니다." >&2
    exit 1
  }

  rm -rf "${WORK}"; mkdir -p "${WORK}/bin"
  _write_git_shim
  export PATH="${WORK}/bin:${PATH}"
  printf '▶ %s   (SRC=%s)\n' "${HARNESS_NAME}" "${SRC}"
}

# git 셔임 — 리포 밖(${WORK}/bin)에 둔다.
# 리포 안에 두면 픽스처의 git add -A 가 커밋해버려 checkout 시 사라진다.
_write_git_shim() {
  cat > "${WORK}/bin/git" <<SHIM
#!/bin/sh
# KILL_ON: 패턴과 일치하는 git 호출 '직전'에 부모(스크립트)를 kill -9.
#          트랩·롤백이 전혀 돌지 않는 최악의 중단을 결정론적으로 재현한다.
if [ -n "\${KILL_ON:-}" ]; then
  case "\$*" in
    \${KILL_ON}) kill -9 \$PPID 2>/dev/null; exit 137 ;;
  esac
fi
# RACE_ON: 패턴과 일치하는 호출 '직전'에 RACE_CMD 를 한 번 실행.
#          preflight 이후에 원격이 앞서가는 상황을 재현한다(마커 파일로 재진입 방지).
if [ -n "\${RACE_ON:-}" ] && [ ! -f "\${RACE_MARK:-/dev/null}" ]; then
  case "\$*" in
    \${RACE_ON}) : > "\${RACE_MARK}"; sh -c "\${RACE_CMD}" >/dev/null 2>&1 ;;
  esac
fi
exec "${GIT_REAL}" "\$@"
SHIM
  chmod +x "${WORK}/bin/git"
}

# ── 픽스처 ────────────────────────────────────────────────────────────
# fixture <케이스명> [none|release|hotfix]
#   세 번째 인자를 주면 해당 토픽 브랜치를 start 까지 만들어 둔다.
#   끝나면 REPO 로 cd 된 상태이고, origin 은 ${WORK}/<케이스명>.git 이다.
#
# 기본 상태: master(0.1.0, 태그 0.1.0) → develop 에 feat 커밋 1개.
#   master != develop 이어야 '미머지' 상태를 만들 수 있다.
fixture() {
  local N="$1" START="${2:-none}" ORIGIN
  ORIGIN="${WORK}/${N}.git"; REPO="${WORK}/${N}"

  "${GIT_REAL}" init -q --bare "${ORIGIN}"
  "${GIT_REAL}" init -q -b master "${REPO}"
  cd "${REPO}" || exit 1
  git config user.email test@example.com
  git config user.name  test
  git config core.hooksPath .husky

  mkdir -p .husky scripts
  cp -R "${SRC}/scripts/." scripts/
  rm -rf scripts/test                     # 하네스 자신은 픽스처에 넣지 않는다
  _install_pre_push
  cp "${SRC}/.gitattributes" .gitattributes 2>/dev/null || true
  printf '{\n  "name": "fixture",\n  "version": "0.1.0",\n  "private": true\n}\n' > package.json

  git add -A >/dev/null; git commit -qm "chore: init"
  git tag -a -m 0.1.0 0.1.0
  git switch -q -c develop
  echo a > a.txt; git add a.txt; git commit -qm "feat: a"
  git remote add origin "${ORIGIN}"
  git push -q -u origin master develop 0.1.0

  case "${START}" in
    release) git switch -q develop; bash scripts/release.sh start >/dev/null 2>&1 ;;
    hotfix)  git switch -q master;  bash scripts/hotfix.sh  start >/dev/null 2>&1 ;;
    *)       git switch -q develop ;;
  esac
}

# 셔뱅 + 가드 블록(ZERO= 이후)만 남긴다.
# 실제 리포의 pre-push 는 앞에 yarn tsc / yarn test 가 있는데 픽스처에는 node_modules 가
# 없어 실행할 수 없다. 가드 블록 자체는 원본 그대로 검증된다.
_install_pre_push() {
  awk 'NR==1{print; next} /^ZERO=/{f=1} f{print}' "${SRC}/.husky/pre-push" > .husky/pre-push
  chmod +x .husky/pre-push
}

# Phase 2(머지·태그)까지 끝나고 push 전에 죽은 상태를, 실제 함수를 호출해 재현한다.
# 전제: fixture <이름> release 로 release/<버전> 브랜치에 있어야 한다.
phase2_state() {
  local V="${1:-0.2.0}"
  node scripts/bump-version.mjs "${V}" >/dev/null
  node scripts/changelog.mjs "${V}" >/dev/null
  git add -A >/dev/null; git commit -qm "chore: release ${V}"
  bash -c "source scripts/lib/checks.sh; topic_merge_and_tag release ${V}" >/dev/null 2>&1
  git switch -q "release/${V}"
}

# ── 실행·단언 ─────────────────────────────────────────────────────────
run()      { OUT="$(eval "$1" 2>&1)"; ST=$?; }
case_hdr() { printf '\n── %s ──\n' "$1"; }

ok() { # ok <설명> <상태(0=통과)>
  if [ "$2" = "0" ]; then
    PASS=$((PASS + 1)); printf '  ✅ %s\n' "$1"
  else
    FAIL=$((FAIL + 1)); FAILED+=("[${HARNESS_NAME}] $1")
    printf '  ❌ %s\n' "$1"
    printf '%s\n' "${OUT}" | sed 's/^/       | /'
  fi
}

expect_blocked() { [ "${ST}" -ne 0 ]; ok "차단됨 (exit=${ST})" $?; }
expect_success() { [ "${ST}" -eq 0 ]; ok "성공 (exit=${ST})" $?; }
expect_has()     { printf '%s' "${OUT}" | grep -qF "$1"; ok "메시지 포함: $1" $?; }

# grep -qv 는 '한 줄이라도 일치하지 않으면 참' 이라 부재 검사에 쓰면 항상 통과한다.
# 반드시 grep -q 의 부정으로 쓴다.
expect_absent()  { ! printf '%s' "${OUT}" | grep -qF "$1"; ok "메시지 없음: $1" $?; }

expect_no_tag()  { ! git rev-parse -q --verify "refs/tags/$1" >/dev/null; ok "태그 $1 없음" $?; }
expect_tag()     { git rev-parse -q --verify "refs/tags/$1" >/dev/null; ok "태그 $1 존재" $?; }
expect_same()    { [ "$(git rev-parse "$1")" = "$(git rev-parse "$2")" ]; ok "$1 == $2" $?; }
alive()          { git rev-parse --verify --quiet "refs/heads/$1" >/dev/null; ok "브랜치 $1 생존" $?; }
head_is()        { [ "$(git rev-parse --abbrev-ref HEAD)" = "$1" ]; ok "HEAD=$1 (실제: $(git rev-parse --abbrev-ref HEAD))" $?; }

# 릴리스가 원격까지 완주했는가 — 태그가 origin/master 를 정확히 가리켜야 한다.
released() {
  local V="${1:-0.2.0}"
  [ "$(git rev-parse "${V}^{commit}" 2>/dev/null)" = "$(git rev-parse origin/master 2>/dev/null)" ]
  ok "태그 ${V} == origin/master" $?
}

# ── 마무리 ────────────────────────────────────────────────────────────
harness_summary() {
  printf '\n══ %s: PASS=%d FAIL=%d ══\n' "${HARNESS_NAME}" "${PASS}" "${FAIL}"
  if [ "${FAIL}" -gt 0 ]; then
    printf '실패:\n'; printf '  - %s\n' "${FAILED[@]}"
    return 1
  fi
  return 0
}
