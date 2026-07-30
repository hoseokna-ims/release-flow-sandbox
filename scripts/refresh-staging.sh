#!/usr/bin/env bash
#
# 릴리스 직후 staging 라인 리프레시 (release/hotfix finish 가 push 성공 뒤 자동 호출).
#   1) develop 마이너 라인으로 새 staging/<major>.<minor> 를 origin/develop 기준 생성
#   2) carry-over(이전 staging 엔 있었지만 아직 develop 미반영) 브랜치들을 --no-ff 자동 머지
#   3) 항상 patch +1 배포까지 (deploy-staging.sh 위임) — carry-over 가 없어도 배포
#
# 설계상 best-effort: 이 스크립트가 실패해도 이미 끝난 릴리스는 되돌리지 않는다(호출자에서 비치명 처리).
#   - 대상 라인이 이미 존재/최신이면 멱등 skip(0).
#   - carry-over 머지 충돌이면 origin 엔 '빈 라인(develop 기준)'만 남기고 로컬을 되돌린 뒤,
#     남은 carry-over 를 수동(yarn staging:merge)으로 잇도록 안내하고 non-zero 로 종료.
#
# 사용법: bash scripts/refresh-staging.sh
#
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

ORIG_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
restore_branch() { git switch "${ORIG_BRANCH}" >/dev/null 2>&1 || true; }

git fetch origin --prune

# 대상 라인: develop 의 마이너 (0.24.0 → 0.24)
DEV_VERSION="$(git show origin/develop:package.json | grep -m1 '"version"' \
  | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
MINOR="${DEV_VERSION%.*}"
TARGET="staging/${MINOR}"

# 최신 staging 라인 (버전 숫자정렬, 레거시 날짜 브랜치 제외)
LATEST="$(git branch -r --list 'origin/staging/*' | sed 's#.*origin/staging/##' \
  | grep -E '^[0-9]+\.[0-9]+$' | sort -t. -k1,1n -k2,2n | tail -1 || true)"

# 멱등 가드: 대상 라인이 이미 origin 에 존재하면 skip (release finish 재실행/중복 호출 안전)
if git ls-remote --exit-code --heads origin "${TARGET}" >/dev/null 2>&1; then
  echo "ℹ️  ${TARGET} 가 이미 존재합니다 → staging 리프레시 skip."
  exit 0
fi

# carry-over 산출: 최신 staging(대상보다 이전 라인) 기준. 없으면 빈 목록.
CARRY=""
if [ -n "${LATEST}" ] && [ "${LATEST}" != "${MINOR}" ]; then
  CARRY="$(bash scripts/carryover-branches.sh "staging/${LATEST}" || true)"
fi

echo "▶ 새 staging 라인 생성: ${TARGET} (origin/develop=${DEV_VERSION} 기준)"
git switch -c "${TARGET}" origin/develop

# carry-over 자동 머지. origin/<branch> 있으면 최신 tip, 삭제됐으면 머지 기록(^2)으로 폴백.
# (조용한 skip 금지 — carry-over 를 잃지 않는다. ^2 도 없을 때만 skip.)
MERGED=()
if [ -n "${CARRY}" ]; then
  echo "▶ carry-over 자동 머지 대상:"; printf '%s\n' "${CARRY}" | cut -f1 | sed 's/^/     - /'
  while IFS=$'\t' read -r BR SHA; do
    [ -z "${BR}" ] && continue
    if git rev-parse --verify --quiet "refs/remotes/origin/${BR}" >/dev/null; then
      REF="origin/${BR}"                       # 브랜치 살아있음 → 최신 tip (테스트 계속)
    elif [ -n "${SHA}" ] && git rev-parse --verify --quiet "${SHA}^{commit}" >/dev/null; then
      REF="${SHA}"                             # 삭제됨 → 머지 기록(^2) 스냅샷으로 보존
      echo "  ℹ️  origin/${BR} 없음 → 머지 기록(${SHA:0:9})으로 carry-over 보존"
    else
      echo "  ⚠️  ${BR}: origin ref·머지 기록 모두 없음 → skip"
      continue
    fi
    echo "  ▶ ${BR} (${REF}) → ${TARGET} 머지"
    if ! git merge --no-ff -m "Merge branch '${BR}' into ${TARGET}" "${REF}"; then
      git merge --abort || true
      # origin 엔 빈 라인만 남기고(수동 인계용) 로컬 되돌림
      git reset --hard origin/develop >/dev/null
      git push -u origin "${TARGET}" >/dev/null
      restore_branch
      echo
      echo "❌ carry-over 머지 충돌: ${BR}"
      echo "   ${TARGET} 는 origin 에 develop 기준으로 생성됐습니다(빈 라인)."
      echo "   충돌을 해결하며 수동으로 이어서 진행하세요:"
      echo "     yarn staging:merge $(printf '%s\n' "${CARRY}" | cut -f1 | tr '\n' ' ')"
      echo "   (충돌 해결 → git add → git commit → yarn staging:deploy)"
      exit 1
    fi
    MERGED+=("${BR}")
  done < <(printf '%s\n' "${CARRY}")
fi

# origin 에 라인 push (deploy-staging 이 HEAD:staging/<line> push 하려면 upstream 필요)
git push -u origin "${TARGET}" >/dev/null

# 항상 배포 (patch +1) — carry-over 유무 무관. bump+commit+push+staging 태그는 deploy-staging 에 위임.
# --force: 방금 만든 라인이므로 deploy-staging 의 '최신 라인' 검사는 불필요하다.
#   (선행 라인이 원격에 남아 있으면 그 검사가 오작동해 정상 리프레시를 막을 수 있다)
bash scripts/deploy-staging.sh --force

restore_branch
if [ "${#MERGED[@]}" -gt 0 ]; then
  echo "✅ staging 리프레시 완료: ${TARGET} (carry-over: ${MERGED[*]})"
else
  echo "✅ staging 리프레시 완료: ${TARGET} (carry-over 없음)"
fi
