#!/bin/bash

#######################################################################
# 🐳 Git Tag 배포 스크립트 for staging & prod 환경
#
# 사용법:
# sh ./push-tag.sh ENV
#
# ENV:
#   staging     스테이징 서버 배포 트리거
#   prod        프로덕션 서버 배포 트리거
#
# 예시:
# sh ./push-tag.sh staging
# sh ./push-tag.sh prod
#######################################################################

ENV=$1
USAGE_STRING="Usage: ./push-tag.sh ENV\n
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

# 2. 실제 태그 삭제 및 재생성
echo "🔄 Releasing deployment for [$ENV]..."

# 태그가 로컬에 존재하면 삭제
if git show-ref --tags | grep -q "refs/tags/$ENV"; then
  echo "🧹 Removing local tag: $ENV"
  git tag -d "$ENV"
fi

# 원격 태그 삭제
echo "🧹 Removing remote tag: $ENV"
git push origin ":refs/tags/$ENV"

# 태그 생성 및 푸시
echo "🏷️ Creating new tag: $ENV"
git tag "$ENV"
git push origin "$ENV"

echo "✅ Successfully pushed tag [$ENV]"
