#!/usr/bin/env bash
#
# 지정한 작업 브랜치들을 최신 staging 브랜치에 머지하고 스테이징 배포까지 한 번에.
#   yarn staging:merge <branch> [branch ...]   # 대상 명시 (위치 무관, 주력)
#   yarn staging:merge                         # 인자 없으면 현재 브랜치 (feature/fix/hotfix 에서만)
#     → 최신 staging checkout/pull → 대상 브랜치들을 순서대로 --no-ff 머지 (origin/<branch> 기준)
#       → (모두 성공 시) patch +1(딱 한 번) → commit → push → staging 배포
#   대상은 origin 기준으로 머지한다 → 로컬에 push 안 된 커밋이 있으면 차단(먼저 push 하도록).
#   머지 충돌 시: 즉시 중단하고 안내(해결·커밋 후 yarn staging:deploy 로 마무리).
#
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

if [ "$#" -eq 0 ]; then
  # 인자 없음 → 현재 브랜치를 대상으로 (실행 중 staging 으로 switch 하므로 work 브랜치에서만 허용)
  CURRENT="$(git rev-parse --abbrev-ref HEAD)"
  case "${CURRENT}" in
    feature/*|fix/*|hotfix/*)
      BRANCHES=("${CURRENT}")
      echo "ℹ️  인자 없음 → 현재 브랜치 '${CURRENT}' 를 최신 staging 에 머지합니다."
      ;;
    *)
      echo "사용법: yarn staging:merge <branch> [branch ...]"
      echo "  예) yarn staging:merge feature/FE-1010 feature/FE-1011"
      echo "  인자 없이 실행하려면 feature/fix/hotfix 작업 브랜치에서 실행하세요. (현재: ${CURRENT})"
      exit 1
      ;;
  esac
else
  BRANCHES=("$@")
fi

[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "❌ 워킹트리 클린 아님 (작업을 먼저 커밋하세요)"; exit 1; }

git fetch origin --prune
# 최신 staging 라인 (버전 숫자정렬: 0.9 < 0.10 정확히. 레거시 날짜 브랜치는 제외)
LATEST="$(git branch -r --list 'origin/staging/*' | sed 's#.*origin/staging/##' \
  | grep -E '^[0-9]+\.[0-9]+$' | sort -t. -k1,1n -k2,2n | tail -1 || true)"
[ -n "${LATEST}" ] || { echo "❌ staging 브랜치가 없습니다 → 먼저 yarn staging:new"; exit 1; }
LATEST_LINE="${LATEST}"
LATEST="staging/${LATEST}"

# 라인 불일치 가드: develop 이 최신 staging 보다 앞선 릴리스 라인이면 옛 staging 에 섞이는 것 차단.
# (staging:new 의 "중복 생성 차단" 가드와 대칭 — 라인 올라가면 새 staging 을 강제)
DEV_MINOR="$(git show origin/develop:package.json | grep -m1 '"version"' \
  | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
DEV_MINOR="${DEV_MINOR%.*}"
if [ "${DEV_MINOR}" != "${LATEST_LINE}" ]; then
  echo "❌ develop 은 ${DEV_MINOR} 라인인데 최신 staging 은 ${LATEST}(${LATEST_LINE} 라인)입니다."
  echo "   릴리스로 라인이 올라갔습니다 → 먼저 'yarn staging:new'(staging/${DEV_MINOR} 생성) 후 다시 실행하세요."
  exit 1
fi

# 사전검사(fail-fast, staging 으로 switch 하기 전): 대상 브랜치 존재 + push 안 된 로컬 커밋 차단.
# staging 은 origin 기준으로 머지하므로, 로컬이 origin 보다 앞서면 그 커밋이 조용히 누락됨 → 막는다.
for BR in "${BRANCHES[@]}"; do
  if git rev-parse --verify --quiet "refs/remotes/origin/${BR}" >/dev/null; then
    if git rev-parse --verify --quiet "refs/heads/${BR}" >/dev/null; then
      AHEAD="$(git rev-list --count "origin/${BR}..${BR}" 2>/dev/null || echo 0)"
      if [ "${AHEAD}" -gt 0 ]; then
        echo "❌ '${BR}' 로컬에 push 안 된 커밋 ${AHEAD}개 — staging 은 origin 기준으로 머지합니다."
        echo "   'git push origin ${BR}' 후 다시 실행하세요."
        exit 1
      fi
    fi
  elif ! git rev-parse --verify --quiet "refs/heads/${BR}" >/dev/null; then
    echo "❌ 브랜치를 찾을 수 없습니다: ${BR} (origin/${BR}·로컬 모두 없음)"
    exit 1
  fi
done

echo "▶ 최신 staging: ${LATEST}"
git switch "${LATEST}"
git pull origin "${LATEST}" --no-edit

for BR in "${BRANCHES[@]}"; do
  # origin/<branch> 우선, 없으면 로컬 <branch>
  if git rev-parse --verify --quiet "refs/remotes/origin/${BR}" >/dev/null; then
    REF="origin/${BR}"
  elif git rev-parse --verify --quiet "refs/heads/${BR}" >/dev/null; then
    REF="${BR}"
  else
    echo "❌ 브랜치를 찾을 수 없습니다: ${BR} (origin/${BR}·로컬 모두 없음)"
    exit 1
  fi

  echo "▶ ${REF} → ${LATEST} 머지"
  if ! git merge --no-ff -m "Merge branch '${BR}' into ${LATEST}" "${REF}"; then
    echo
    echo "❌ 머지 충돌이 발생했습니다: ${BR}"
    echo "   충돌 해결 → git add → git commit 후 → yarn staging:deploy 로 마무리하세요."
    echo "   (아직 머지 안 된 인자 브랜치가 있으면 배포 후 yarn staging:merge 로 이어서 진행하세요.)"
    exit 1
  fi
done

BEFORE="$(node -p "require('./package.json').version")"
node scripts/bump-version.mjs patch >/dev/null
AFTER="$(node -p "require('./package.json').version")"
node scripts/changelog.mjs "${AFTER}" --staging   # STAGING_CHANGELOG.md 재생성 (라인 스냅샷)
git add package.json
[ -f package-lock.json ] && git add package-lock.json || true
[ -f CHANGELOG.md ] && git add CHANGELOG.md || true
[ -f STAGING_CHANGELOG.md ] && git add STAGING_CHANGELOG.md || true
git commit -qm "chore: staging deploy ${AFTER}"
echo "▶ 스테이징 버전 ${BEFORE} -> ${AFTER}"

if ! git push origin "HEAD:${LATEST}"; then
  echo "⚠️ push 거부됨(원격이 앞섬). 'git pull --no-rebase' 후 yarn staging:deploy 로 마무리하세요."
  exit 1
fi

sh scripts/push-tag.sh staging
echo "✅ [${BRANCHES[*]}] → ${LATEST} 머지·배포 완료 (${AFTER})"
