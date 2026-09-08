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
# 성공하면 실행 전 브랜치로 복귀한다 — staging 에 남으면 곧바로 이어지는
# yarn release/hotfix finish 가 브랜치 검사에서 튕겨 수동 우회를 유발한다.
#
# bump·커밋(⑤) 이후의 실패는 staging 라인을 "git pull 직후" 상태로 되돌린다(FE-1044).
#
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
source scripts/lib/checks.sh

# 실행 전 브랜치 기억. 최종 HEAD 위치는 성공·실패 원인에 따라 셋으로 갈린다.
#   · 성공, 그리고 롤백까지 끝난 실패(bump·커밋 실패, push 거부) → ORIG_BRANCH 복귀.
#     되돌린 staging 위에 남을 이유가 없고, staging 에 남으면 곧바로 이어지는
#     yarn release/hotfix finish 가 브랜치 검사에서 튕긴다(2026-07-29 사고 방아쇠).
#   · 머지 충돌 → staging 잔류. 충돌 해결·커밋은 staging 위에서 이어져야 한다.
#   · 배포 트리거 태그 push 실패 → staging 잔류. 안내하는 재실행 명령
#     (scripts/push-tag.sh staging)이 staging/* 브랜치를 요구한다.
ORIG_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
restore_branch() { git switch "${ORIG_BRANCH}" >/dev/null 2>&1 || true; }

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
  # 최신 staging 이 develop 보다 '앞선' 라인이면 선행 라인이다 — 이때는 staging:new 도
  # "이미 develop 포함" 가드에 걸려 양쪽이 잠긴다. 원인을 구분해 안내한다.
  if [ "$(printf '%s\n%s\n' "${LATEST_LINE}" "${DEV_MINOR}" | sort -t. -k1,1n -k2,2n | tail -1)" = "${LATEST_LINE}" ]; then
    echo "   ${LATEST} 가 develop 보다 앞선 라인입니다 — 선행 라인입니다."
    echo "   yarn staging:new 도 막히므로 먼저 정리해야 합니다."
    echo "   → 배포 이력이 없다면 삭제 후 재실행하세요: git push origin --delete ${LATEST}"
  else
    echo "   릴리스로 라인이 올라갔습니다 → 먼저 'yarn staging:new'(staging/${DEV_MINOR} 생성) 후 다시 실행하세요."
  fi
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

# 로컬 staging 라인의 미푸시 커밋 가드 — switch/pull 전(=첫 변경 전)에 끝낸다.
# behind 는 통과시킨다(바로 아래 git pull 이 받아온다). ahead·diverged 만 차단한다.
require_staging_synced "${LATEST}" pull

echo "▶ 최신 staging: ${LATEST}"
git switch "${LATEST}"
git pull origin "${LATEST}" --no-edit

# 빈 배포 판정 기준 = 롤백 기준 SHA = 머지를 시작하기 직전의 tip("git pull 이후").
# pull 까지 되돌리지 않는다 — 되돌리면 재실행마다 다시 pull 해야 하고 로컬이 origin 보다
# 뒤처진 채 남는다. 여기부터 아래 push 성공까지가 롤백 적용 구간이다.
MERGE_BASE_TIP="$(git rev-parse HEAD)"
record_baseline_ref "${LATEST}" "${MERGE_BASE_TIP}"

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

# 머지로 추가된 새 커밋이 0 인 경우는 두 가지이고, 안내가 정반대다.
#   · 미푸시 커밋도 없다      → 이미 전부 반영된 브랜치. 버전만 올라가는 빈 배포이므로
#                               의도한 재배포일 수 있어 차단하지 않고 확인만 받는다.
#   · 미푸시 커밋이 남아 있다 → 중단된 실행(kill·Ctrl-C·크래시. set -e 의 ERR 트랩은
#                               시그널에 걸리지 않는다)이 만든 머지 커밋이다. 여기서
#                               "이미 반영됨" 경고를 띄우면 사용자는 중단을 택하고
#                               머지 커밋이 push 되지 않은 채 영구히 남는다.
# 미푸시 bump 커밋이 섞여 있으면 재개로 보지 않는다 — 그건 ⑥ 이후에서 죽은 상태이고
# 이어서 bump 하면 버전이 두 번 오른다(멱등화는 FE-1046 범위).
if [ "$(git rev-list --count "${MERGE_BASE_TIP}..HEAD")" -eq 0 ]; then
  UNPUSHED_SUBJECTS="$(git log --format=%s "origin/${LATEST}..HEAD" 2>/dev/null || true)"
  if [ -n "${UNPUSHED_SUBJECTS}" ] && ! printf '%s\n' "${UNPUSHED_SUBJECTS}" \
    | grep -qE '^chore: staging deploy [0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "ℹ️  중단된 실행의 재개입니다 — 머지는 이미 로컬에 있고 아직 push 되지 않았습니다:"
    git log --oneline "origin/${LATEST}..HEAD" | sed 's/^/     /'
    echo "   이어서 bump·push 를 진행합니다."
  else
    echo "⚠️  머지로 추가된 새 커밋이 없습니다 — 이미 ${LATEST} 에 반영된 브랜치입니다."
    echo "   계속하면 변경 없이 patch 만 올라가는 빈 배포가 됩니다."
    confirm "   그래도 배포할까요?"
  fi
fi

# ⑤ 첫 파괴적 변경. 여기서 실패하면(bump·changelog·커밋 훅 거부 등) 머지 커밋까지
#    함께 되돌린다 — 반쯤 진행된 트리가 남으면 재실행이 워킹트리 검사에서 튕긴다(2차 함정).
trap 'rollback_baseline_ref; restore_branch;
      echo "❌ 버전 bump·커밋 단계가 실패했습니다 — ${LATEST} 를 시작 상태로 되돌렸습니다(머지·bump 커밋 없음)." >&2;
      echo "   → 위 원인을 해결한 뒤 같은 명령을 다시 실행하세요: yarn staging:merge ${BRANCHES[*]}" >&2' ERR
BEFORE="$(node -p "require('./package.json').version")"
node scripts/bump-version.mjs patch >/dev/null
AFTER="$(node -p "require('./package.json').version")"
node scripts/changelog.mjs "${AFTER}" --staging   # STAGING_CHANGELOG.md 재생성 (라인 스냅샷)
git add package.json
[ -f package-lock.json ] && git add package-lock.json || true
[ -f CHANGELOG.md ] && git add CHANGELOG.md || true
[ -f STAGING_CHANGELOG.md ] && git add STAGING_CHANGELOG.md || true
git commit -qm "chore: staging deploy ${AFTER}"
trap - ERR
echo "▶ 스테이징 버전 ${BEFORE} -> ${AFTER}"

# ⑥ push — pre-push 훅이 여기서 처음 콘텐츠 검사(tsc·test)를 돌린다.
#    출력을 버퍼링하는 이유: 실패 원인 판정 전에 훅이 낸 실패 내용을 먼저 보여줘야 한다.
if ! PUSH_OUT="$(git push origin "HEAD:${LATEST}" 2>&1)"; then
  printf '%s\n' "${PUSH_OUT}"
  echo
  # 원인을 메시지 문구가 아니라 '상태' 로 판정한다(git 로케일·버전 무관).
  #   ⓐ --no-verify 재시도(dry-run)가 성공한다 → 막은 것은 로컬 훅뿐이다.
  #      원격은 도달 가능하고 fast-forward 도 가능하다는 뜻이므로 git pull 은 무의미하다.
  #   ⓑ 아니면 원격 tip 이 우리 계보 밖으로 갔는지 확인한다 → non-fast-forward.
  #   ⓒ 둘 다 아니면 그 외(네트워크·권한·원격 설정).
  # ⓐ·ⓑ 를 뭉개고 모두에게 'git pull' 을 안내하면 pre-push 거부에서도 pull 이 실행되고,
  # 그 위에 staging:deploy 가 patch 를 또 올려 버전이 두 번 오른다(2026-09 사건).
  if git push --no-verify --dry-run origin "HEAD:${LATEST}" >/dev/null 2>&1; then
    rollback_baseline_ref
    restore_branch
    echo "❌ push 가 로컬 검사(.husky/pre-push)에 막혔습니다 — 원격은 변경되지 않았습니다."
    echo "   위 실패 내용이 원인입니다. ${LATEST} 는 시작 상태로 되돌렸습니다(머지·bump 커밋 없음)."
    echo "   → 원인을 고쳐 작업 브랜치에 커밋·push 한 뒤 같은 명령을 다시 실행하세요:"
    echo "     yarn staging:merge ${BRANCHES[*]}"
    exit 1
  fi
  # 명시 refspec 으로 fetch 한다 — remote-tracking ref 갱신을 git 버전에 의존하지 않기 위해.
  git fetch -q origin "+refs/heads/${LATEST}:refs/remotes/origin/${LATEST}" 2>/dev/null || true
  if ! git merge-base --is-ancestor "refs/remotes/origin/${LATEST}" HEAD 2>/dev/null; then
    rollback_baseline_ref
    restore_branch
    echo "❌ push 거부됨 — 원격 ${LATEST} 가 앞서 있습니다(다른 사람이 먼저 배포했습니다)."
    echo "   ${LATEST} 는 시작 상태로 되돌렸습니다 — 재실행이 git pull 로 원격 변경을 받아옵니다."
    echo "   → 그대로 다시 실행하세요: yarn staging:merge ${BRANCHES[*]}"
    exit 1
  fi
  rollback_baseline_ref
  restore_branch
  echo "❌ push 실패 — 원인은 위 출력을 확인하세요(네트워크·권한·원격 설정 등)."
  echo "   ${LATEST} 는 시작 상태로 되돌렸습니다."
  echo "   → 원인을 해결한 뒤 같은 명령을 다시 실행하세요: yarn staging:merge ${BRANCHES[*]}"
  exit 1
fi
printf '%s\n' "${PUSH_OUT}"

# ⑦ 배포 트리거 태그. 여기서 실패하면 롤백하지 않는다 — ${LATEST} 는 이미 원격에
#    반영됐고, 되돌리면 로컬이 origin 보다 뒤처져 다음 실행이 그 커밋을 다시 pull 한 뒤
#    patch 를 또 올린다(이중 bump). 남은 일은 태그 하나뿐이므로 그것만 다시 밀면 된다.
#    ORIG_BRANCH 로 복귀하지 않는다 — 안내하는 명령이 staging/* 브랜치를 요구한다.
if ! bash scripts/push-tag.sh staging; then
  echo
  echo "❌ 배포 트리거 태그(staging) push 에 실패했습니다 — 스테이징 서버는 아직 갱신되지 않았습니다."
  echo "   ${LATEST}(${AFTER})는 이미 원격에 반영됐으므로 되돌리지 않습니다."
  echo "   → 태그만 다시 밀면 됩니다(현재 브랜치 ${LATEST} 에서): bash scripts/push-tag.sh staging"
  exit 1
fi
echo "✅ [${BRANCHES[*]}] → ${LATEST} 머지·배포 완료 (${AFTER})"

restore_branch
echo "↩︎ ${ORIG_BRANCH} 브랜치로 돌아왔습니다."
