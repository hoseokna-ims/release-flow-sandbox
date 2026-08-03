#!/bin/bash

#######################################################################
# 🐳 Git Tag 배포 스크립트 for staging & prod 환경
#
# 사용법:
# bash scripts/push-tag.sh ENV
#
# ENV:
#   staging     스테이징 서버 배포 트리거 (staging/* 브랜치에서만)
#   prod        프로덕션 서버 배포 트리거 (origin/master 최신 커밋에서만)
#
# 예시:
# bash scripts/push-tag.sh staging
# bash scripts/push-tag.sh prod
#######################################################################

set -euo pipefail

ENV=${1:-}
USAGE_STRING="Usage: scripts/push-tag.sh ENV\n
\n
ENV:\n
\tstaging\n
\tprod\n"

# 1. ENV가 없거나 허용되지 않은 경우
if [ -z "$ENV" ]; then
  echo -e "$USAGE_STRING"
  exit 1
fi

if [ "$ENV" != "staging" ] && [ "$ENV" != "prod" ]; then
  echo -e "$USAGE_STRING"
  exit 2
fi

# 2. 배포 컨텍스트 가드 — 잘못된 커밋으로 배포가 트리거되는 것을 차단
#    (태그 push 는 pre-push 의 master 버전 가드에 걸리지 않으므로 여기서 직접 막는다)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
case "$ENV" in
  prod)
    # prod 태그 = 운영 배포 트리거. origin/master 의 최신 커밋에서만 허용.
    git fetch origin master --quiet
    if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/master)" ]; then
      echo "❌ prod 태그는 origin/master 최신 커밋에서만 푸시할 수 있습니다. (현재: $CURRENT_BRANCH)"
      echo "   → git switch master && git pull 후 다시 실행하세요."
      exit 1
    fi
    VERSION=$(node -p "require('./package.json').version")
    if [ "${VERSION##*.}" != "0" ]; then
      echo "❌ 운영 버전이 아닙니다: $VERSION (patch 는 0 이어야 함)"
      exit 1
    fi
    ;;
  staging)
    # staging 태그 = 스테이징 배포 트리거. staging/* 브랜치에서만 허용.
    case "$CURRENT_BRANCH" in
      staging/*) ;;
      *)
        echo "❌ staging 태그는 staging/* 브랜치에서만 푸시할 수 있습니다. (현재: $CURRENT_BRANCH)"
        echo "   → yarn staging:merge 또는 yarn staging:deploy 를 사용하세요."
        exit 1
        ;;
    esac
    ;;
esac

# 3. 태그 강제 갱신 + push
#    삭제→재생성(원격 조작 2회) 대신 force push 1회 — 중간 실패로 태그가 사라진 채
#    남는 공백이 없고, push 가 실패해도 원격의 기존 태그는 그대로 유지된다.
echo "🔄 Releasing deployment for [$ENV]..."
git tag -f "$ENV"
git push --force origin "refs/tags/$ENV"

echo "✅ Successfully pushed tag [$ENV]"
