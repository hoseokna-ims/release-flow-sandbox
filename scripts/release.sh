#!/usr/bin/env bash
#
# 운영 릴리스 (2단계: 시작 → (선택)안정화 작업 → 마무리).
#   ./release.sh start [minor|major]   develop 기준 release 브랜치 생성 (기본 minor)
#   (여기서 막판 안정화 작업·커밋 — 선택)
#   ./release.sh finish                bump + changelog + finish(머지·태그) + push
#
# 원샷 실행은 지원하지 않는다(실수 방지). 반드시 start → finish.
#
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

start() {
  local TYPE="${1:-minor}"
  case "${TYPE}" in
    minor|major) ;;
    *) echo "사용법: ./release.sh start [minor|major]"; exit 1 ;;
  esac

  echo "▶ [사전검사] fetch + 최신/클린 확인"
  git fetch origin --prune
  [ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "❌ 워킹트리 클린 아님"; exit 1; }
  for BR in develop master; do
    read -r behind _ < <(git rev-list --left-right --count "origin/${BR}...${BR}" 2>/dev/null || echo "0 0")
    [ "${behind}" -gt 0 ] && { echo "❌ ${BR} 가 origin 보다 ${behind} 커밋 뒤처짐 → git pull 후 재시도"; exit 1; }
  done

  local NEXT; NEXT="$(node scripts/next-version.mjs "${TYPE}")"
  echo "▶ 다음 버전: ${NEXT} (${TYPE})"
  git rev-parse "${NEXT}" >/dev/null 2>&1 && { echo "❌ 태그 ${NEXT} 가 이미 존재합니다."; exit 1; }

  echo "▶ [사전검사] master 머지 충돌 시뮬 (package.json/lock 제외)"
  local MT; MT="$(mktemp)"
  if ! git merge-tree --write-tree --name-only master develop >"${MT}" 2>/dev/null; then
    local CONFLICTS; CONFLICTS="$(tail -n +2 "${MT}" | grep -v -e '^$' -e 'package.json' -e 'package-lock.json' || true)"
    if [ -n "${CONFLICTS}" ]; then
      echo "❌ master 머지 충돌 예상:"; echo "${CONFLICTS}"; rm -f "${MT}"; exit 1
    fi
  fi
  rm -f "${MT}"

  git flow release start "${NEXT}"
  echo "✅ release/${NEXT} 시작. (선택) 안정화 작업·커밋 후 → ./release.sh finish"
}

finish() {
  local BRANCH; BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  case "${BRANCH}" in
    release/*) ;;
    *) echo "❌ release/* 브랜치에서 실행하세요 (현재: ${BRANCH})"; exit 1 ;;
  esac
  local VERSION="${BRANCH#release/}"
  [ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "❌ 작업을 먼저 커밋하세요"; exit 1; }

  trap 'echo "❌ release finish 중단. git status 확인 후 수동 마무리하세요."' ERR
  echo "▶ bump + changelog (${VERSION})"
  node scripts/bump-version.mjs "${VERSION}" >/dev/null
  bash scripts/changelog.sh "${VERSION}"
  git add package.json
  [ -f package-lock.json ] && git add package-lock.json || true
  [ -f CHANGELOG.md ] && git add CHANGELOG.md || true
  git commit -qm "chore: release ${VERSION}"

  echo "▶ git flow release finish (master·develop 머지 + 태그 ${VERSION})"
  GIT_MERGE_AUTOEDIT=no git flow release finish -m "${VERSION}" "${VERSION}"

  echo "▶ push (master 푸시 = 운영 배포 트리거)"
  git push origin master develop --tags
  echo "✅ 릴리스 ${VERSION} 완료 — 태그 ${VERSION}, master 배포 트리거됨."
}

CMD="${1:-}"
case "${CMD}" in
  start) shift; start "${@:-}" ;;
  finish) finish ;;
  *) echo "사용법: ./release.sh start [minor|major]  |  ./release.sh finish"; exit 1 ;;
esac
