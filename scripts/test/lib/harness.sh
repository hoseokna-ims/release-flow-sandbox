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

# 셔뱅 + 모의 콘텐츠 검사 + 가드 블록(ZERO= 이후).
#
# 실제 리포의 pre-push 는 앞에 yarn tsc / yarn test 가 있는데 픽스처에는 node_modules 가
# 없어 실행할 수 없다. 그 자리에 마커 파일(.prepush-fail)로 제어하는 모의 검사를 둔다 —
# "pre-push 가 콘텐츠 검사로 push 를 거부" 하는 경로를 결정론적으로 재현하기 위한 것이다.
# 마커가 없으면 아무 일도 하지 않으므로 기존 케이스의 동작은 바뀌지 않는다.
# 가드 블록 자체는 원본 그대로 검증된다.
_install_pre_push() {
  {
    printf '%s\n' '#!/usr/bin/env sh'
    printf '%s\n' 'if [ -f .prepush-fail ]; then'
    printf '%s\n' '  echo "❌ tsc --noEmit 실패 5건 (하네스 모의 콘텐츠 검사)"'
    printf '%s\n' '  exit 1'
    printf '%s\n' 'fi'
    # 1행(셔뱅)은 위에서 직접 썼으므로 버린다. ZERO= 부터 끝까지가 가드 블록이다.
    # 1행 액션에서 플래그를 세우면(NR==1||f||/^ZERO=/{f=1;print}) 전체가 출력된다 — 주의.
    awk 'NR==1{next} /^ZERO=/{f=1} f{print}' "${SRC}/.husky/pre-push"
  } > .husky/pre-push
  chmod +x .husky/pre-push
}

# 모의 콘텐츠 검사 on/off. 마커는 untracked 이므로 --untracked-files=no 를 쓰는
# 워킹트리 검사에는 걸리지 않고, 브랜치를 옮겨도 살아남는다.
prepush_fail_on()  { : > "${REPO}/.prepush-fail"; }
prepush_fail_off() { rm -f "${REPO}/.prepush-fail"; }

# 스테이징 픽스처 — staging 라인 + 작업 브랜치까지 만들어 둔다.
#   fixture_staging <케이스명> [작업브랜치]
#
# merge-staging.sh 의 라인 불일치 가드(52-69행)가 origin/develop 의 마이너 라인과 최신
# staging 라인의 일치를 요구하므로, develop 0.1.0 → staging/0.1 로 맞춘다.
#
# 끝나면 HEAD 는 작업 브랜치이고 origin 에는 master·develop·staging/0.1·<작업브랜치> 가
# 올라가 있다. 작업 브랜치는 develop 에서 따므로 staging 에 아직 머지되지 않은 상태다.
fixture_staging() {
  local N="$1" WORKBR="${2:-feature/FE-X}"
  fixture "${N}"
  git switch -q -c staging/0.1 develop
  git push -q -u origin staging/0.1
  git switch -q -c "${WORKBR}" develop
  echo w > w.txt; git add w.txt; git commit -qm "feat: w"
  git push -q -u origin "${WORKBR}"
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
# ⚠️ ok 에 넘길 상태는 반드시 먼저 변수로 받는다. `ok "... $(cmd)" $?` 로 쓰면
#    설명 안의 명령치환이 실행되면서 $? 를 덮어써 항상 0(통과)이 전달된다 —
#    head_is 가 실제로 이 형태였고, 모든 하네스의 HEAD 단언이 무의미하게 통과했다(FE-1044).
head_is() {
  local ACTUAL ST_
  ACTUAL="$(git rev-parse --abbrev-ref HEAD)"
  [ "${ACTUAL}" = "$1" ]; ST_=$?
  ok "HEAD=$1 (실제: ${ACTUAL})" "${ST_}"
}

# ── 스테이징 공용 헬퍼 ────────────────────────────────────────────────
# 버전은 워킹트리가 아니라 '커밋된 브랜치 tip' 에서 읽는다 — 스테이징 성공 경로는 HEAD 를
# 작업 브랜치로 되돌려 놓으므로 워킹트리 package.json 은 bump 되지 않은 값이다.
ver_of() {
  git show "$1:package.json" 2>/dev/null \
    | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}
expect_ver() {
  local BR="${2:-staging/0.1}" ACTUAL ST_
  ACTUAL="$(ver_of "${BR}")"
  [ "${ACTUAL}" = "$1" ]; ST_=$?
  ok "${BR} 버전 = $1 (실제: ${ACTUAL})" "${ST_}"
}
expect_unpushed() {
  local ACTUAL ST_
  ACTUAL="$(git rev-list --count "origin/$2..$2")"
  [ "${ACTUAL}" = "$1" ]; ST_=$?
  ok "$2 미푸시 커밋 ${1}개 (실제: ${ACTUAL})" "${ST_}"
}
expect_clean_tree() { [ -z "$(git status --porcelain --untracked-files=no)" ]; ok "워킹트리 클린" $?; }
remote_sha()        { git ls-remote origin "refs/heads/$1" | cut -f1; }
count_in()          { git log --oneline "$1" | grep -cF "$2"; }

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
