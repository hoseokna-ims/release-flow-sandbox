#!/usr/bin/env bash
#
# CHANGELOG.md 에 새 버전 섹션을 맨 위(헤더 아래)에 prepend 한다.
# 범위 = 직전 semver 태그..HEAD → prefix(feat/fix/...) 별로 그룹핑.
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

# prefix 그룹 출력 헬퍼: <섹션 제목> <grep 패턴>
section() {
  local title="$1" pattern="$2" lines
  lines="$(git log ${RANGE} --no-merges --pretty='%s (%h)' 2>/dev/null | grep -iE "^(${pattern})(\(|:| )" || true)"
  if [ -n "${lines}" ]; then
    printf '### %s\n' "${title}"
    # "feat(scope): 내용" → "- 내용"
    printf '%s\n' "${lines}" | sed -E 's/^[a-zA-Z]+(\([^)]*\))?:[[:space:]]*/- /'
    printf '\n'
  fi
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
