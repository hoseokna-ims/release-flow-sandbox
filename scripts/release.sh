#!/usr/bin/env bash
#
# 운영 릴리스: 사전검사 → git-flow release start → bump(minor|major) + changelog
#              → finish(머지 + 태그) → push(master 푸시 = 운영 배포 트리거).
#
# 사용법: ./release.sh [minor|major]   (기본 minor)
#
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
trap 'echo "❌ 릴리스 중단. git status 로 상태 확인 후 수동 마무리하거나 재시도하세요."' ERR

TYPE="${1:-minor}"
case "${TYPE}" in
  minor|major) ;;
  *) echo "사용법: ./release.sh [minor|major]"; exit 1 ;;
esac

echo "▶ [사전검사] fetch + 최신/클린 확인"
git fetch origin --prune
[ -z "$(git status --porcelain)" ] || { echo "❌ 워킹트리 클린 아님"; exit 1; }
for BR in develop master; do
  read -r behind _ < <(git rev-list --left-right --count "origin/${BR}...${BR}" 2>/dev/null || echo "0 0")
  [ "${behind}" -gt 0 ] && { echo "❌ ${BR} 가 origin 보다 ${behind} 커밋 뒤처짐 → git pull 후 재시도"; exit 1; }
done

NEXT="$(node scripts/next-version.mjs "${TYPE}")"
echo "▶ 다음 버전: ${NEXT} (${TYPE})"
if git rev-parse "${NEXT}" >/dev/null 2>&1; then
  echo "❌ 태그 ${NEXT} 가 이미 존재합니다."; exit 1
fi

echo "▶ [사전검사] master 머지 충돌 시뮬 (package.json 제외)"
MT="$(mktemp)"
if ! git merge-tree --write-tree --name-only master develop >"${MT}" 2>/dev/null; then
  CONFLICTS="$(tail -n +2 "${MT}" | grep -v -e '^$' -e 'package.json' || true)"
  if [ -n "${CONFLICTS}" ]; then
    echo "❌ master 머지 충돌 예상:"; echo "${CONFLICTS}"; rm -f "${MT}"; exit 1
  fi
fi
rm -f "${MT}"

echo "▶ git flow release start ${NEXT}"
git flow release start "${NEXT}"

echo "▶ bump + changelog"
node scripts/bump-version.mjs "${NEXT}" >/dev/null
bash scripts/changelog.sh "${NEXT}"
git add -A && git commit -qm "chore: release ${NEXT}"

echo "▶ git flow release finish (master·develop 머지 + 태그 ${NEXT})"
GIT_MERGE_AUTOEDIT=no git flow release finish -m "${NEXT}" "${NEXT}"

echo "▶ push (master 푸시 = 운영 배포 트리거)"
git push origin master develop --tags

echo "✅ 릴리스 ${NEXT} 완료 — 태그 ${NEXT}, master 배포 트리거됨."
