#!/usr/bin/env bash
#
# CHANGELOG.md 에 새 버전 섹션을 맨 위(헤더 아래)에 prepend 한다.
# 범위 = 직전 semver 태그..HEAD → prefix(feat/fix/...) 별로 그룹핑.
# 커밋 해시는 GitHub 커밋 URL 로 링크된다(origin 원격에서 repo URL 도출).
#
# 사용법: bash scripts/changelog.sh <version>
#
set -euo pipefail

VERSION="${1:?사용법: bash scripts/changelog.sh <version>}"
FILE="CHANGELOG.md"
DATE="$(date +%Y-%m-%d)"

# 직전 릴리스 태그 (v 유무 모두 허용)
PREV="$(git tag --list --sort=-version:refname | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)"
RANGE="HEAD"
[ -n "${PREV}" ] && RANGE="${PREV}..HEAD"

# origin → https 형태 repo URL (ssh/토큰 임베드 정규화, .git 제거). 없으면 빈값 → 링크 없이 해시만.
REMOTE_URL="$(git remote get-url origin 2>/dev/null || echo '')"
REPO_URL="$(printf '%s' "${REMOTE_URL}" | sed -E 's#^git@github\.com:#https://github.com/#; s#^https://[^@]*@#https://#; s#\.git$##')"

# prefix 그룹 출력 헬퍼: <섹션 제목> <grep 패턴>
section() {
  local title="$1" pattern="$2" raw
  # 구분자 = unit separator(\x1f) → 커밋 제목에 특수문자 있어도 안전
  raw="$(git log ${RANGE} --no-merges --pretty='%s%x1f%h%x1f%H' 2>/dev/null | grep -iE "^(${pattern})(\(|:| )" || true)"
  [ -z "${raw}" ] && return 0
  printf '### %s\n' "${title}"
  printf '%s\n' "${raw}" | while IFS=$'\x1f' read -r subject short full; do
    # "feat(scope): 내용" → "내용"
    subject="$(printf '%s' "${subject}" | sed -E 's/^[a-zA-Z]+(\([^)]*\))?:[[:space:]]*//')"
    if [ -n "${REPO_URL}" ]; then
      printf -- '- %s ([%s](%s/commit/%s))\n' "${subject}" "${short}" "${REPO_URL}" "${full}"
    else
      printf -- '- %s (%s)\n' "${subject}" "${short}"
    fi
  done
  printf '\n'
}

NEW="$(mktemp)"
{
  printf '## [%s] - %s\n\n' "${VERSION}" "${DATE}"
  section "Added" "feat"
  section "Fixed" "fix"
  section "Changed" "refactor|style|perf"
  section "Chore" "chore|docs|test|build"
} >"${NEW}"

if [ -f "${FILE}" ] && head -1 "${FILE}" | grep -qiE '^#[[:space:]]'; then
  { head -1 "${FILE}"; printf '\n'; cat "${NEW}"; tail -n +2 "${FILE}"; } >"${FILE}.tmp"
elif [ -f "${FILE}" ]; then
  { printf '# Changelog\n\n'; cat "${NEW}"; cat "${FILE}"; } >"${FILE}.tmp"
else
  { printf '# Changelog\n\n'; cat "${NEW}"; } >"${FILE}.tmp"
fi
mv "${FILE}.tmp" "${FILE}"
rm -f "${NEW}"
echo "  CHANGELOG.md 갱신 (${VERSION}, 범위 ${RANGE})"
