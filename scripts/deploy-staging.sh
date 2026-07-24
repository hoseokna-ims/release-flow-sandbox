#!/usr/bin/env bash
#
# 스테이징 배포: patch +1 (운영형 버전 퇴행 복구 자동 포함) → 커밋 → push → staging 태그 트리거.
# 반드시 staging/* 브랜치에서, feature 머지·커밋이 끝난 상태에서 실행한다.
#
# 사용법: yarn staging:deploy
#
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
case "${BRANCH}" in
  staging/*) ;;
  *) echo "❌ staging/* 브랜치에서만 실행하세요. (현재: ${BRANCH})"; exit 1 ;;
esac

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "❌ 커밋 안 된 변경이 있습니다. (feature 머지 후 커밋 완료 상태에서 실행하세요)"
  exit 1
fi

BEFORE="$(node -p "require('./package.json').version")"
node scripts/bump-version.mjs patch >/dev/null
AFTER="$(node -p "require('./package.json').version")"
node scripts/changelog.mjs "${AFTER}" --staging   # STAGING_CHANGELOG.md 재생성 (라인 스냅샷)
git add package.json
[ -f package-lock.json ] && git add package-lock.json || true
[ -f CHANGELOG.md ] && git add CHANGELOG.md || true
[ -f STAGING_CHANGELOG.md ] && git add STAGING_CHANGELOG.md || true
git commit -qm "chore: staging deploy ${AFTER}"
echo "▶ 스테이징 버전 ${BEFORE} -> ${AFTER}"

if ! git push origin "HEAD:${BRANCH}"; then
  echo "⚠️ push 거부됨(원격이 앞섬). 'git pull --no-rebase' 후 다시 yarn staging:deploy 실행하세요."
  exit 1
fi

sh scripts/push-tag.sh staging
echo "✅ 스테이징 배포 트리거 완료 (${AFTER})"
