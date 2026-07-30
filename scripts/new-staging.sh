#!/usr/bin/env bash
#
# 스테이징 통합 브랜치 생성 (릴리스 라인당 1회).
# - 브랜치명은 origin/develop 의 마이너 라인: staging/<major>.<minor> (예: develop=0.20.0 → staging/0.20).
#   master/develop 버전 라인과 일치해 인식이 쉽다. 이름은 라인, 그 위 배포는 0.20.1, 0.20.2 …(patch).
# - 최신 staging 이 이미 현재 develop 을 반영했으면 생성을 막는다(중복 방지).
# - 초기 bump 없음 — develop 버전 그대로. 첫 배포(staging:merge/deploy)에서 patch +1 되어 .1 이 된다.
# - 생성 후, 이전 staging 에는 있었지만 아직 develop 에 없는(=미릴리스) 브랜치 목록을 안내한다.
#
# 사용법: yarn staging:new [minor]    # minor 생략 시 develop 버전에서 자동 도출 (예: 0.20)
#   인자로 override 할 때는 형식(X.Y)을 검증하고, develop 라인과 다르면 확인을 받는다 —
#   develop 과 다른 라인은 staging:merge·staging:new 양쪽 가드에 걸려 잠기기 때문.
#
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

git fetch origin --prune

# 브랜치명: develop 의 마이너 라인 (0.20.0 → 0.20). 인자로 override 가능.
DEV_VERSION="$(git show origin/develop:package.json | grep -m1 '"version"' \
  | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
DEV_MINOR="${DEV_VERSION%.*}"

# 인자 override 검증 (fail-fast — 가장 값싼 검사부터)
if [ -n "${1:-}" ]; then
  if ! [[ "$1" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "❌ 라인 형식이 아닙니다: '$1'"
    echo "   → 마이너 라인만 지정하세요. 예: yarn staging:new ${DEV_MINOR}"
    exit 1
  fi
  if [ "$1" != "${DEV_MINOR}" ]; then
    echo "⚠️  develop 은 ${DEV_MINOR} 라인인데 '$1' 을 지정했습니다."
    echo "   develop 과 다른 라인을 만들면 이후 yarn staging:merge 는 라인 불일치로,"
    echo "   yarn staging:new 는 '이미 develop 포함' 가드로 막혀 양쪽이 잠깁니다."
    printf "   정말 계속할까요? [y/N] "
    if [ -t 0 ]; then read -r ANSWER; else ANSWER=n; echo "(비대화형 → 자동 중단)"; fi
    [ "${ANSWER}" = "y" ] || { echo "중단했습니다."; exit 1; }
  fi
fi

MINOR="${1:-${DEV_MINOR}}"
BRANCH="staging/${MINOR}"

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "❌ 워킹트리에 커밋 안 된 변경이 있습니다. 정리 후 다시 실행하세요."
  exit 1
fi

# 최신 staging 라인 (버전 숫자정렬: 0.9 < 0.10 정확히. 레거시 날짜 브랜치는 제외)
LATEST_LINE="$(git branch -r --list 'origin/staging/*' | sed 's#.*origin/staging/##' \
  | grep -E '^[0-9]+\.[0-9]+$' | sort -t. -k1,1n -k2,2n | tail -1 || true)"
LATEST=""
[ -n "${LATEST_LINE}" ] && LATEST="staging/${LATEST_LINE}"

# 오펀 라인 가드: 최신 staging 이 develop 보다 앞선 라인이면 정상 플로우로는 생길 수 없는 상태다.
# 그대로 두면 staging:merge 가 라인 불일치로 계속 차단되므로(양쪽 잠김) 먼저 정리하게 만든다.
if [ -n "${LATEST_LINE}" ] && [ "${LATEST_LINE}" != "${DEV_MINOR}" ] && [ \
  "$(printf '%s\n%s\n' "${LATEST_LINE}" "${DEV_MINOR}" | sort -t. -k1,1n -k2,2n | tail -1)" = "${LATEST_LINE}" ]; then
  echo "❌ 최신 staging(${LATEST})이 develop(${DEV_MINOR}) 보다 앞선 라인입니다 — 오펀 라인입니다."
  echo "   이 상태에서는 yarn staging:merge 가 라인 불일치로 계속 차단됩니다."
  echo "   → 배포 이력이 없다면 삭제 후 재실행하세요: git push origin --delete ${LATEST}"
  exit 1
fi

# 가드: 최신 staging 이 이미 현재 develop 을 포함하면 새 staging 불필요
if [ -n "${LATEST}" ] && git merge-base --is-ancestor origin/develop "origin/${LATEST}"; then
  echo "❌ 최신 staging(${LATEST})이 이미 현재 develop 을 포함합니다 → 새 staging 불필요."
  echo "   기존 브랜치에 작업을 올리려면: (작업 브랜치에서) yarn staging:merge"
  exit 1
fi

if git show-ref --verify --quiet "refs/heads/${BRANCH}" \
  || git ls-remote --exit-code --heads origin "${BRANCH}" >/dev/null 2>&1; then
  echo "❌ ${BRANCH} 가 이미 존재합니다."
  echo "   → 작업을 올리려면: (작업 브랜치에서) yarn staging:merge"
  echo "   → 라인을 처음부터 다시 만들려면: git push origin --delete ${BRANCH} 후 재실행"
  exit 1
fi

echo "▶ 스테이징 브랜치 생성: ${BRANCH} (origin/develop 기준)"
git switch -c "${BRANCH}" origin/develop

VERSION="$(node -p "require('./package.json').version")"
echo "  현재 버전(${VERSION}) 유지 — 초기 bump 없음 (첫 staging:merge/deploy 에서 patch +1)"

git push -u origin "${BRANCH}"
echo "✅ ${BRANCH} 준비 완료."

# carry-over 안내: 이전 staging 머지 중 아직 develop 에 없는 것(머지커밋 ^2 기준 → 브랜치 삭제 무관)
if [ -n "${LATEST}" ]; then
  CARRY="$(bash scripts/carryover-branches.sh "${LATEST}")"
  if [ -n "${CARRY}" ]; then
    echo
    echo "ℹ️  이전 staging(${LATEST})에 있었지만 아직 develop 에 없는 브랜치 (필요 시 각 브랜치에서 yarn staging:merge):"
    printf '%s\n' "${CARRY}" | cut -f1 | sed 's/^/     - /'
  fi
fi
