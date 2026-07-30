#!/usr/bin/env bash
#
# 스테이징 배포: patch +1 (운영형 버전 퇴행 복구 자동 포함) → 커밋 → push → staging 태그 트리거.
# 반드시 최신 staging/* 라인에서, feature 머지·커밋이 끝난 상태에서 실행한다.
#
# 사용법: yarn staging:deploy [--force]
#   --force : 최신 라인 검사를 건너뛴다(옛 라인을 의도적으로 배포할 때만).
#             refresh-staging.sh 가 방금 만든 라인에 배포할 때도 사용한다.
#
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
case "${BRANCH}" in
  staging/*) ;;
  *) echo "❌ staging/* 브랜치에서만 실행하세요. (현재: ${BRANCH})"; exit 1 ;;
esac

# 최신 라인 가드: 옛 라인에서 배포하면 'staging' 태그가 옛 코드로 이동해 QA 서버가 되돌아간다.
# (merge-staging.sh 의 라인 불일치 가드와 대칭 — 폴백 경로에도 같은 안전망을 둔다)
if [ "${FORCE}" -eq 0 ]; then
  git fetch origin --prune
  LATEST="$(git branch -r --list 'origin/staging/*' | sed 's#.*origin/staging/##' \
    | grep -E '^[0-9]+\.[0-9]+$' | sort -t. -k1,1n -k2,2n | tail -1 || true)"
  if [ -n "${LATEST}" ] && [ "staging/${LATEST}" != "${BRANCH}" ]; then
    echo "❌ 현재 브랜치(${BRANCH})는 최신 staging 라인(staging/${LATEST})이 아닙니다."
    echo "   옛 라인을 배포하면 스테이징 서버가 옛 코드로 교체됩니다."
    echo "   → git switch staging/${LATEST} 후 다시 실행하세요."
    echo "   (의도한 옛 라인 배포라면: yarn staging:deploy --force)"
    exit 1
  fi
fi

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
