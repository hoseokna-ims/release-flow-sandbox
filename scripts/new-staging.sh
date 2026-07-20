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
#
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

git fetch origin --prune

# 브랜치명: develop 의 마이너 라인 (0.20.0 → 0.20). 인자로 override 가능.
DEV_VERSION="$(git show origin/develop:package.json | grep -m1 '"version"' \
  | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
MINOR="${1:-${DEV_VERSION%.*}}"
BRANCH="staging/${MINOR}"

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "❌ 워킹트리에 커밋 안 된 변경이 있습니다. 정리 후 다시 실행하세요."
  exit 1
fi

# 최신 staging 라인 (버전 숫자정렬: 0.9 < 0.10 정확히. 레거시 날짜 브랜치는 제외)
LATEST="$(git branch -r --list 'origin/staging/*' | sed 's#.*origin/staging/##' \
  | grep -E '^[0-9]+\.[0-9]+$' | sort -t. -k1,1n -k2,2n | tail -1 || true)"
[ -n "${LATEST}" ] && LATEST="staging/${LATEST}"

# 가드: 최신 staging 이 이미 현재 develop 을 포함하면 새 staging 불필요
if [ -n "${LATEST}" ] && git merge-base --is-ancestor origin/develop "origin/${LATEST}"; then
  echo "❌ 최신 staging(${LATEST})이 이미 현재 develop 을 포함합니다 → 새 staging 불필요."
  echo "   기존 브랜치에 작업을 올리려면: (작업 브랜치에서) yarn staging:merge"
  exit 1
fi

if git show-ref --verify --quiet "refs/heads/${BRANCH}" \
  || git ls-remote --exit-code --heads origin "${BRANCH}" >/dev/null 2>&1; then
  echo "❌ ${BRANCH} 가 이미 존재합니다."
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
  CARRY=""
  while IFS=$'\x1f' read -r hash subject; do
    br="$(printf '%s' "${subject}" | grep -oE '(feature|hotfix|fix)/[A-Za-z0-9._/-]+' | head -1 || true)"
    [ -z "${br}" ] && continue
    p2="$(git rev-parse "${hash}^2" 2>/dev/null)" || continue
    git merge-base --is-ancestor "${p2}" origin/develop && continue  # 이미 develop 반영 → 제외
    CARRY="${CARRY}${br}"$'\n'
  done < <(git log "origin/develop..origin/${LATEST}" --merges --pretty='%H%x1f%s')
  CARRY="$(printf '%s' "${CARRY}" | sed '/^$/d' | sort -u)"
  if [ -n "${CARRY}" ]; then
    echo
    echo "ℹ️  이전 staging(${LATEST})에 있었지만 아직 develop 에 없는 브랜치 (필요 시 각 브랜치에서 yarn staging:merge):"
    printf '%s\n' "${CARRY}" | sed 's/^/     - /'
  fi
fi
