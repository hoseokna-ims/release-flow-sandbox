#!/usr/bin/env bash
#
# 릴리스 플로우 검증 하네스 전체 실행.
#
# 사용법:
#   yarn test:release-flow
#   bash scripts/test/run-all.sh
#   SRC=/path/to/other-repo bash scripts/test/run-all.sh   # 다른 리포의 스크립트 검증
#
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

HARNESSES=(ahead-policy interrupt dx guards staging-rollback staging-ahead staging-idempotent)
TOTAL_PASS=0; TOTAL_FAIL=0; FAILED_HARNESSES=()
LOG_DIR="${TMPDIR:-/tmp}/release-flow-test"
mkdir -p "${LOG_DIR}"

for H in "${HARNESSES[@]}"; do
  LOG="${LOG_DIR}/${H}.log"
  SRC="${SRC:-}" bash "scripts/test/${H}.sh" >"${LOG}" 2>&1
  STATUS=$?
  SUMMARY="$(grep -E '^══' "${LOG}" | tail -1)"
  P="$(printf '%s' "${SUMMARY}" | sed -n 's/.*PASS=\([0-9]*\).*/\1/p')"
  F="$(printf '%s' "${SUMMARY}" | sed -n 's/.*FAIL=\([0-9]*\).*/\1/p')"
  TOTAL_PASS=$((TOTAL_PASS + ${P:-0}))
  TOTAL_FAIL=$((TOTAL_FAIL + ${F:-0}))

  if [ "${STATUS}" -eq 0 ]; then
    printf '  ✅ %-14s PASS=%-3s  (%s)\n' "${H}" "${P:-?}" "${LOG}"
  else
    FAILED_HARNESSES+=("${H}")
    printf '  ❌ %-14s PASS=%-3s FAIL=%-3s  (%s)\n' "${H}" "${P:-?}" "${F:-?}" "${LOG}"
    grep -E '^  ❌|^  - ' "${LOG}" | head -20 | sed 's/^/       /'
  fi
done

printf '\n══ 합계: PASS=%d FAIL=%d ══\n' "${TOTAL_PASS}" "${TOTAL_FAIL}"
if [ "${#FAILED_HARNESSES[@]}" -gt 0 ]; then
  printf '실패한 하네스: %s\n' "${FAILED_HARNESSES[*]}"
  echo "전체 출력은 위 로그 경로를 확인하세요."
  exit 1
fi
