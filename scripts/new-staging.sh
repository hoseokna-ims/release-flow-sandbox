#!/usr/bin/env bash
#
# 스테이징 통합 브랜치 생성 (사이클당 1회).
# - 최신 staging 이 이미 현재 develop 을 반영했으면 생성을 막는다(중복 방지).
# - origin/develop 기준으로 staging/YYMMDD 생성 (초기 bump 없음 — develop 버전 그대로).
#   첫 배포(staging:merge/deploy)에서 patch +1 되어 .1 이 된다.
# - 생성 후, 이전 staging 에는 있었지만 아직 develop 에 없는(=미릴리스) 브랜치 목록을 안내한다.
#
# 사용법: yarn staging:new [YYMMDD]
#
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

DATE="${1:-$(date +%y%m%d)}"
BRANCH="staging/${DATE}"

git fetch origin --prune
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "❌ 워킹트리에 커밋 안 된 변경이 있습니다. 정리 후 다시 실행하세요."
  exit 1
fi

# 최신 staging 브랜치 (이름 YYMMDD = 사전순 = 시간순)
LATEST="$(git branch -r --list 'origin/staging/*' | sed 's#.*origin/##' | sort | tail -1 || true)"

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
    br="$(printf '%s' "${subject}" | grep -oE '(feature|hotfix|fix)/[A-Za-z0-9._/-]+' | head -1)"
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
