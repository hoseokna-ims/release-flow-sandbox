#!/usr/bin/env bash
#
# 릴리스 플로우 공용 사전검사 라이브러리.
#
# release.sh / hotfix.sh 가 source 해서 쓴다 (리포 루트로 cd 한 뒤):
#   source scripts/lib/checks.sh
#
# 설계 원칙
#  - 모든 검사는 "첫 변경 전"에 끝낸다. 실패하면 아무것도 건드리지 않고 종료한다.
#  - 모든 실패 메시지는 "무엇이 왜 안 되는지 한 줄" + "복사해 실행할 다음 명령"을 포함한다.
#  - git flow 의 원격 동기화 검사(require_branches_equal)는 has() 헬퍼의 인용 문제로
#    실제로 실행되지 않는다(nvie 0.4.1 실측). 그래서 동기화는 여기서 직접 확인한다.
#
# 이 파일의 함수는 실패 시 exit 1 한다(source 된 호출 스크립트가 종료된다).
#

# 대화형이면 y/N 확인, 비대화형이면 중단(안전측 기본값).
# RELEASE_ASSUME_YES=1 로 비대화형 자동 승인 가능 — CI 에서 의도적으로 쓸 때만.
confirm() {
  local MSG="$1"
  if [ "${RELEASE_ASSUME_YES:-}" = "1" ]; then
    echo "${MSG} → RELEASE_ASSUME_YES=1 로 자동 승인"
    return 0
  fi
  if [ -t 0 ]; then
    local ANS
    printf '%s [y/N] ' "${MSG}"
    read -r ANS
    case "${ANS}" in
      y | Y) return 0 ;;
      *) echo "중단했습니다."; exit 1 ;;
    esac
  fi
  echo "${MSG}"
  echo "   → 비대화형 환경에서는 자동 중단합니다. 정리 후 재실행하세요."
  echo "     (의도적으로 진행하려면 RELEASE_ASSUME_YES=1)"
  exit 1
}

require_gitflow() {
  command -v git-flow >/dev/null 2>&1 && return 0
  echo "❌ git-flow 가 설치되어 있지 않습니다."
  echo "   → brew install git-flow-avh"
  echo "     설치 후 다음 yarn install 에서 git flow init 이 자동 실행됩니다."
  exit 1
}

require_clean_tree() {
  [ -z "$(git status --porcelain --untracked-files=no)" ] && return 0
  echo "❌ 워킹트리에 커밋 안 된 변경이 있습니다:"
  git status --short --untracked-files=no | sed 's/^/     /'
  echo "   → 커밋하거나 git stash 후 재실행하세요."
  exit 1
}

# 릴리스 버전 형식(X.Y.0). 운영 버전은 patch=0 이 규칙이다.
require_semver_version() {
  local V="$1"
  [[ "${V}" =~ ^[0-9]+\.[0-9]+\.0$ ]] && return 0
  echo "❌ 릴리스 버전 형식이 아닙니다: '${V}' (X.Y.0 이어야 합니다)"
  echo "   운영 버전은 patch=0 입니다. 브랜치명 또는 package.json 의 version 을 확인하세요."
  exit 1
}

require_tag_absent() {
  local TAG="$1"
  if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null 2>&1; then
    echo "❌ 태그 ${TAG} 가 이미 로컬에 있습니다."
    echo "   이전 릴리스가 중단돼 남은 태그일 수 있습니다(그대로 두면 다음 버전 계산이 이 값을 건너뜁니다)."
    echo "   → 원격에 없는 태그라면 삭제하세요: git tag -d ${TAG}"
    exit 1
  fi
  if git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
    echo "❌ 태그 ${TAG} 가 이미 원격에 있습니다 — 이미 릴리스된 버전입니다."
    exit 1
  fi
}

# 로컬 브랜치가 origin 과 동기화됐는지 확인.
#  - behind / diverged → 차단 (안내는 pull.ff=only 설정을 반영해 구분한다)
#  - ahead            → 커밋 목록을 보여주고 명시적 확인 (git-flow 계열은 ahead 를 '무해'로
#                       보지만, 이 리포에서는 미푸시 master 커밋이 곧 운영 배포다)
require_synced() {
  git fetch origin --prune
  local BR BEHIND AHEAD
  for BR in "$@"; do
    if ! git rev-parse --verify --quiet "refs/heads/${BR}" >/dev/null; then
      echo "❌ 로컬 브랜치가 없습니다: ${BR}"
      echo "   → git switch -c ${BR} origin/${BR}"
      exit 1
    fi
    read -r BEHIND AHEAD < <(git rev-list --left-right --count "origin/${BR}...${BR}" 2>/dev/null || echo "0 0")
    if [ "${BEHIND}" -gt 0 ] && [ "${AHEAD}" -gt 0 ]; then
      echo "❌ ${BR} 가 origin 과 갈라졌습니다 (behind ${BEHIND}, ahead ${AHEAD})."
      echo "   → git switch ${BR} && git pull --rebase"
      echo "     (맨 git pull 은 pull.ff=only 설정 때문에 'Not possible to fast-forward' 로 실패합니다)"
      exit 1
    elif [ "${BEHIND}" -gt 0 ]; then
      echo "❌ ${BR} 가 origin 보다 ${BEHIND} 커밋 뒤처졌습니다."
      echo "   → git switch ${BR} && git pull"
      exit 1
    elif [ "${AHEAD}" -gt 0 ]; then
      echo "⚠️  ${BR} 에 push 안 된 로컬 커밋 ${AHEAD}개가 있습니다 — 이번 릴리스에 함께 나갑니다:"
      git log --oneline "origin/${BR}..${BR}" | sed 's/^/     /'
      confirm "   포함하고 계속할까요?"
    fi
  done
}

# <base> 에 <topic> 을 머지할 때 충돌이 예상되는지 미리 확인.
# package.json / package-lock.json 은 maxversion 머지 드라이버가 자동 해소하므로 제외한다.
require_merge_clean() {
  local BASE="$1" TOPIC="$2" MT CONFLICTS
  MT="$(mktemp)"
  if ! git merge-tree --write-tree --name-only "${BASE}" "${TOPIC}" >"${MT}" 2>/dev/null; then
    CONFLICTS="$(tail -n +2 "${MT}" | grep -v -e '^$' -e '^package.json$' -e '^package-lock.json$' || true)"
    if [ -n "${CONFLICTS}" ]; then
      rm -f "${MT}"
      echo "❌ ${BASE} ← ${TOPIC} 머지 충돌이 예상됩니다:"
      printf '%s\n' "${CONFLICTS}" | sed 's/^/     /'
      echo "   → 먼저 '${BASE}' 를 '${TOPIC}' 로 머지해 충돌을 해결·커밋한 뒤 재실행하세요."
      exit 1
    fi
  fi
  rm -f "${MT}"
}

# 남아 있는 release/* 또는 hotfix/* 로컬 브랜치를 먼저 진단한다.
# git flow 의 "Finish that one first" 는 브랜치명이 뭉개져 보이고, 작업 브랜치를
# finish 하라는 뜻으로 읽혀 위험하다(작업 브랜치가 master 에 머지되고 태그까지 붙는다).
require_no_stale_topic() {
  local PREFIX="$1" FOUND NON_SEMVER B
  FOUND="$(git for-each-ref --format='%(refname:short)' "refs/heads/${PREFIX}/*" || true)"
  [ -z "${FOUND}" ] && return 0

  echo "❌ 로컬에 ${PREFIX}/* 브랜치가 이미 있습니다:"
  printf '%s\n' "${FOUND}" | sed 's/^/     - /'
  echo "   git flow 는 ${PREFIX}/* 가 하나라도 있으면 새 ${PREFIX} 를 시작할 수 없습니다."

  NON_SEMVER="$(printf '%s\n' "${FOUND}" | grep -vE "^${PREFIX}/[0-9]+\.[0-9]+\.[0-9]+$" || true)"
  if [ -n "${NON_SEMVER}" ]; then
    echo
    echo "   ※ ${PREFIX}/ 접두사는 릴리스 플로우 전용입니다. 아래는 작업 브랜치로 보입니다:"
    while IFS= read -r B; do
      [ -z "${B}" ] && continue
      echo "     → git branch -m ${B} fix/${B#"${PREFIX}"/}     (이름 변경 후 재실행)"
    done < <(printf '%s\n' "${NON_SEMVER}")
    echo "     (작업 브랜치는 fix/ 를 사용하세요 — ${PREFIX} finish 를 실행하면 그 브랜치가"
    echo "      master 에 머지되고 태그까지 생성됩니다)"
  fi
  echo
  echo "   진행 중인 릴리스라면 먼저 마무리하세요: yarn ${PREFIX} finish"
  exit 1
}
