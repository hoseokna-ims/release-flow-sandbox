#!/usr/bin/env bash
#
# 현재 작업 브랜치를 최신 staging 브랜치에 머지하고 스테이징 배포까지 한 번에.
#   (작업 브랜치에서) ./merge-staging.sh
#     → 최신 staging checkout → 작업 브랜치 --no-ff 머지 → patch +1 → push → staging 배포
#   머지 충돌 시: 중단하고 안내(해결·커밋 후 ./deploy-staging.sh 로 마무리).
#
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

WORK="$(git rev-parse --abbrev-ref HEAD)"
case "${WORK}" in
  staging/*|master|develop|HEAD)
    echo "❌ 작업 브랜치(feature/fix/hotfix 등)에서 실행하세요. (현재: ${WORK})"; exit 1 ;;
esac
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "❌ 워킹트리 클린 아님 (작업을 먼저 커밋하세요)"; exit 1; }

git fetch origin --prune
LATEST="$(git branch -r --list 'origin/staging/*' | sed 's#.*origin/##' | sort | tail -1 || true)"
[ -n "${LATEST}" ] || { echo "❌ staging 브랜치가 없습니다 → 먼저 yarn staging:new"; exit 1; }

echo "▶ 최신 staging: ${LATEST} 에 ${WORK} 머지"
git switch "${LATEST}"
git pull origin "${LATEST}" --no-edit

if ! git merge --no-ff -m "Merge branch '${WORK}' into ${LATEST}" "${WORK}"; then
  echo
  echo "❌ 머지 충돌이 발생했습니다."
  echo "   충돌 해결 → git add → git commit 후 → yarn staging:deploy 로 마무리하세요."
  exit 1
fi

BEFORE="$(node -p "require('./package.json').version")"
node scripts/bump-version.mjs patch >/dev/null
AFTER="$(node -p "require('./package.json').version")"
git add package.json
[ -f package-lock.json ] && git add package-lock.json || true
[ -f CHANGELOG.md ] && git add CHANGELOG.md || true
git commit -qm "chore: staging deploy ${AFTER}"
echo "▶ 스테이징 버전 ${BEFORE} -> ${AFTER}"

if ! git push origin "HEAD:${LATEST}"; then
  echo "⚠️ push 거부됨(원격이 앞섬). 'git pull --no-rebase' 후 yarn staging:deploy 로 마무리하세요."
  exit 1
fi

sh scripts/push-tag.sh staging
echo "✅ ${WORK} → ${LATEST} 머지·배포 완료 (${AFTER})"
