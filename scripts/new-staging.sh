#!/usr/bin/env bash
#
# 스테이징 통합 브랜치 생성 + 스테이징 버전 초기화 (사이클당 1회).
# origin/develop 기준으로 staging/YYMMDD 를 만들고, 운영형 버전이면 patch bump.
#
# 사용법: ./new-staging.sh [YYMMDD]
#
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

DATE="${1:-$(date +%y%m%d)}"
BRANCH="staging/${DATE}"

echo "▶ 스테이징 브랜치 생성: ${BRANCH}"

git fetch origin --prune
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ 워킹트리에 커밋 안 된 변경이 있습니다. 정리 후 다시 실행하세요."
  exit 1
fi

if git show-ref --verify --quiet "refs/heads/${BRANCH}" \
  || git ls-remote --exit-code --heads origin "${BRANCH}" >/dev/null 2>&1; then
  echo "❌ ${BRANCH} 가 이미 존재합니다."
  exit 1
fi

git switch -c "${BRANCH}" origin/develop

VERSION="$(node -p "require('./package.json').version")"
PATCH="${VERSION##*.}"
if [ "${PATCH}" = "0" ]; then
  node scripts/bump-version.mjs patch >/dev/null
  NEW="$(node -p "require('./package.json').version")"
  git commit -aqm "chore: init staging ${BRANCH} -> ${NEW}"
  echo "  스테이징 버전 초기화: ${VERSION} -> ${NEW}"
else
  echo "  이미 스테이징 버전(${VERSION}) 유지"
fi

git push -u origin "${BRANCH}"
echo "✅ ${BRANCH} 준비 완료. 이후 'feature 머지 → ./deploy-staging.sh' 를 반복하세요."
