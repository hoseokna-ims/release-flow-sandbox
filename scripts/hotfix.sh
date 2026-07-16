#!/usr/bin/env bash
#
# 운영 핫픽스 (2단계: 시작 → 수정·커밋 → 마무리).
#   ./hotfix.sh start [minor|major]   master 기준 hotfix 브랜치 생성 (기본 minor)
#   (여기서 수정하고 커밋)
#   ./hotfix.sh finish                bump + changelog + finish(머지·태그) + push
#
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

start() {
  local TYPE="${1:-minor}"
  case "${TYPE}" in
    minor|major) ;;
    *) echo "사용법: ./hotfix.sh start [minor|major]"; exit 1 ;;
  esac
  git fetch origin --prune
  [ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "❌ 워킹트리 클린 아님"; exit 1; }
  read -r behind _ < <(git rev-list --left-right --count "origin/master...master" 2>/dev/null || echo "0 0")
  [ "${behind}" -gt 0 ] && { echo "❌ master 가 origin 보다 뒤처짐 → git pull 후 재시도"; exit 1; }

  local NEXT; NEXT="$(node scripts/next-version.mjs "${TYPE}")"
  git rev-parse "${NEXT}" >/dev/null 2>&1 && { echo "❌ 태그 ${NEXT} 이미 존재"; exit 1; }

  git flow hotfix start "${NEXT}"
  echo "✅ hotfix/${NEXT} 시작. 수정·커밋 후 → ./hotfix.sh finish"
}

finish() {
  local BRANCH; BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  case "${BRANCH}" in
    hotfix/*) ;;
    *) echo "❌ hotfix/* 브랜치에서 실행하세요 (현재: ${BRANCH})"; exit 1 ;;
  esac
  local VERSION="${BRANCH#hotfix/}"
  [ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "❌ 수정사항을 먼저 커밋하세요"; exit 1; }

  trap 'echo "❌ 핫픽스 finish 중단. git status 확인 후 수동 마무리하세요."' ERR
  echo "▶ bump + changelog (${VERSION})"
  node scripts/bump-version.mjs "${VERSION}" >/dev/null
  node scripts/changelog.mjs "${VERSION}"
  git add package.json
  [ -f package-lock.json ] && git add package-lock.json || true
  [ -f CHANGELOG.md ] && git add CHANGELOG.md || true
  git commit -qm "chore: hotfix ${VERSION}"

  echo "▶ git flow hotfix finish (master·develop 머지 + 태그 ${VERSION})"
  GIT_MERGE_AUTOEDIT=no git flow hotfix finish -m "${VERSION}" "${VERSION}"

  echo "▶ push (master 푸시 = 운영 배포 트리거)"
  git push origin master develop --tags
  echo "✅ 핫픽스 ${VERSION} 완료 — 태그 ${VERSION}, master 배포 트리거됨."
}

CMD="${1:-}"
case "${CMD}" in
  start) shift; start "${@:-}" ;;
  finish) finish ;;
  *) echo "사용법: ./hotfix.sh start [minor|major]  |  ./hotfix.sh finish"; exit 1 ;;
esac
