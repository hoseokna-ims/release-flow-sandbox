#!/usr/bin/env bash
#
# carry-over 브랜치 목록 산출 (공유 헬퍼).
#   carry-over = (이전 staging 에 머지된 브랜치) − (이미 develop 에 반영된 브랜치)
#   = "이전 staging 에선 테스트 중이었지만 이번 릴리스(develop)엔 아직 안 들어간" 작업 브랜치.
#
# 판별: origin/develop..origin/<staging> 의 feature|hotfix|fix 머지 커밋 중,
#   도입 tip(^2)이 origin/develop 의 ancestor 가 아닌 것만 (브랜치명은 머지 메시지에서 추출 → 삭제 무관).
#
# 사용법: bash scripts/carryover-branches.sh <staging-ref>   # 예: staging/0.23
#   출력: "<브랜치명>\t<도입 tip(^2) 커밋SHA>" 한 줄에 하나 (브랜치별 최신 머지, 정렬). 없으면 빈 출력.
#   SHA 를 함께 내보내는 이유: 브랜치가 origin 에서 삭제돼도 머지 기록(^2)으로 carry-over 를
#   보존할 수 있게 한다(refresh-staging 의 폴백). ※ git fetch 는 호출자 책임.
#
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

LATEST="${1:-}"
[ -n "${LATEST}" ] || { echo "사용법: bash scripts/carryover-branches.sh <staging-ref>" >&2; exit 1; }
# 'staging/0.23' / '0.23' / 'origin/staging/0.23' 모두 허용 → origin/staging/<line> 으로 정규화
LINE="${LATEST#origin/}"; LINE="${LINE#staging/}"
STAGING_REF="origin/staging/${LINE}"
git rev-parse --verify --quiet "${STAGING_REF}" >/dev/null \
  || { echo "❌ staging ref 없음: ${STAGING_REF}" >&2; exit 1; }

CARRY=""
SEEN=" "
while IFS=$'\x1f' read -r hash subject; do
  br="$(printf '%s' "${subject}" | grep -oE '(feature|hotfix|fix)/[A-Za-z0-9._/-]+' | head -1 || true)"
  [ -z "${br}" ] && continue
  case "${SEEN}" in *" ${br} "*) continue ;; esac  # 같은 브랜치는 최신 머지만 (git log 는 최신순)
  p2="$(git rev-parse "${hash}^2" 2>/dev/null)" || continue
  git merge-base --is-ancestor "${p2}" origin/develop && continue  # 이미 develop 반영 → 제외
  SEEN="${SEEN}${br} "
  CARRY="${CARRY}$(printf '%s\t%s' "${br}" "${p2}")"$'\n'
done < <(git log "origin/develop..${STAGING_REF}" --merges --pretty='%H%x1f%s')

printf '%s' "${CARRY}" | sed '/^$/d' | sort
