#!/usr/bin/env bash
#
# 지정한 작업 브랜치들을 최신 staging 브랜치에 머지하고 스테이징 배포까지 한 번에.
#   yarn staging:merge <branch> [branch ...]
#     → 최신 staging checkout/pull → 인자 브랜치들을 순서대로 --no-ff 머지
#       → (모두 성공 시) patch +1(딱 한 번) → commit → push → staging 배포
#   현재 위치(브랜치)와 무관하게 동작한다 — 대상은 인자로만 지정한다.
#   머지 충돌 시: 즉시 중단하고 안내(해결·커밋 후 yarn staging:deploy 로 마무리).
#
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

if [ "$#" -eq 0 ]; then
  echo "사용법: yarn staging:merge <branch> [branch ...]"
  echo "  예) yarn staging:merge feature/FE-1010 feature/FE-1011"
  exit 1
fi
BRANCHES=("$@")

[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "❌ 워킹트리 클린 아님 (작업을 먼저 커밋하세요)"; exit 1; }

git fetch origin --prune
LATEST="$(git branch -r --list 'origin/staging/*' | sed 's#.*origin/##' | sort | tail -1 || true)"
[ -n "${LATEST}" ] || { echo "❌ staging 브랜치가 없습니다 → 먼저 yarn staging:new"; exit 1; }

echo "▶ 최신 staging: ${LATEST}"
git switch "${LATEST}"
git pull origin "${LATEST}" --no-edit

for BR in "${BRANCHES[@]}"; do
  # origin/<branch> 우선, 없으면 로컬 <branch>
  if git rev-parse --verify --quiet "refs/remotes/origin/${BR}" >/dev/null; then
    REF="origin/${BR}"
  elif git rev-parse --verify --quiet "refs/heads/${BR}" >/dev/null; then
    REF="${BR}"
  else
    echo "❌ 브랜치를 찾을 수 없습니다: ${BR} (origin/${BR}·로컬 모두 없음)"
    exit 1
  fi

  echo "▶ ${REF} → ${LATEST} 머지"
  if ! git merge --no-ff -m "Merge branch '${BR}' into ${LATEST}" "${REF}"; then
    echo
    echo "❌ 머지 충돌이 발생했습니다: ${BR}"
    echo "   충돌 해결 → git add → git commit 후 → yarn staging:deploy 로 마무리하세요."
    echo "   (아직 머지 안 된 인자 브랜치가 있으면 배포 후 yarn staging:merge 로 이어서 진행하세요.)"
    exit 1
  fi
done

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
echo "✅ [${BRANCHES[*]}] → ${LATEST} 머지·배포 완료 (${AFTER})"
