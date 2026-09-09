#!/usr/bin/env bash
#
# 스테이징 배포: patch +1 → 커밋 → push → staging 태그 트리거.
# 이 버전의 미푸시 bump 커밋이 이미 있으면 bump·changelog·커밋을 건너뛴다(멱등).
# 반드시 최신 staging/* 라인에서, feature 머지·커밋이 끝난 상태에서 실행한다.
#
# 사용법: yarn staging:deploy [--force]
#   --force : 최신 라인 검사를 건너뛴다(옛 라인을 의도적으로 배포할 때만).
#             refresh-staging.sh 가 방금 만든 라인에 배포할 때도 사용한다.
#
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
source scripts/lib/checks.sh

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
case "${BRANCH}" in
  staging/*) ;;
  *) echo "❌ staging/* 브랜치에서만 실행하세요. (현재: ${BRANCH})"; exit 1 ;;
esac

# 최신 라인 가드: 옛 라인에서 배포하면 'staging' 태그가 옛 코드로 이동해 QA 서버가 되돌아간다.
# (merge-staging.sh 의 라인 불일치 가드와 대칭 — 폴백 경로에도 같은 안전망을 둔다)
if [ "${FORCE}" -eq 0 ]; then
  git fetch origin --prune
  LATEST="$(git branch -r --list 'origin/staging/*' | sed 's#.*origin/staging/##' \
    | grep -E '^[0-9]+\.[0-9]+$' | sort -t. -k1,1n -k2,2n | tail -1 || true)"
  if [ -n "${LATEST}" ] && [ "staging/${LATEST}" != "${BRANCH}" ]; then
    echo "❌ 현재 브랜치(${BRANCH})는 최신 staging 라인(staging/${LATEST})이 아닙니다."
    echo "   옛 라인을 배포하면 스테이징 서버가 옛 코드로 교체됩니다."
    echo "   → git switch staging/${LATEST} 후 다시 실행하세요."
    echo "   (의도한 옛 라인 배포라면: yarn staging:deploy --force)"
    exit 1
  fi
fi

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "❌ 커밋 안 된 변경이 있습니다. (feature 머지 후 커밋 완료 상태에서 실행하세요)"
  exit 1
fi

# 미푸시 커밋 가드 — bump(첫 파괴적 변경) 전에 끝낸다. merge-staging.sh 와 같은 구멍이었다.
# 이 스크립트는 pull 하지 않으므로 behind 도 차단한다 — 그대로 두면 bump·커밋을 만든 뒤
# push 가 반드시 거부되고, 그 안내를 따라 pull 하면 다음 실행이 patch 를 또 올린다.
#
# fetch 는 --force 경로에서만 한다. 위 최신 라인 가드가 이미 `git fetch origin --prune` 으로
# 모든 remote-tracking ref 를 갱신했고, fetch 1회는 실측 2.3~3.2초(imsform → GitHub)로
# 이 스크립트에서 가장 비싼 단계다 — 무조건 한 번 더 하면 정상 배포마다 그만큼 느려진다.
if [ "${FORCE}" -eq 1 ]; then
  git fetch -q origin "+refs/heads/${BRANCH}:refs/remotes/origin/${BRANCH}" 2>/dev/null || true
fi
require_staging_synced "${BRANCH}" block

# 설치 정합성 사전검사 — 첫 파괴적 변경(bump) 이전.
# 이 스크립트가 라인을 전환하지는 않지만, 사용자는 `git switch staging/<라인>` 을 손으로 하고
# 그 자리에서 이 명령을 실행한다 — merge-staging.sh 의 switch 와 같은 스큐원이다.
# HEAD 는 옮기지 않으므로 안내하는 yarn install 이 이 라인의 락파일 기준으로 돈다.
#
# 파일이 없으면 건너뛴다(merge-staging.sh 와 같은 이유 — 이식 전 라인에서도 배포는 돼야 한다).
if [ -f scripts/check-install-sync.mjs ]; then
  node scripts/check-install-sync.mjs && INSTALL_ST=0 || INSTALL_ST=$?
  # 3 = 스큐 확정, 그 외 비-0 = 검사기 자체 실패(node 는 예외·문법오류를 모두 1 로 낸다)
  case "${INSTALL_ST}" in
    0) ;;
    3)
      echo "   현재 브랜치는 ${BRANCH} 입니다 — 이 라인의 락파일 기준으로 설치됩니다."
      echo "   bump 는 시작하지 않았습니다. 설치를 맞춘 뒤 같은 명령을 다시 실행하세요:"
      echo "     yarn install && yarn staging:deploy"
      exit 1
      ;;
    *)
      echo "   설치 상태 문제가 아닙니다 — yarn install 로는 해결되지 않습니다."
      echo "   bump 는 시작하지 않았습니다. 검사기를 고친 뒤 다시 실행하세요."
      exit 1
      ;;
  esac
else
  echo "ℹ️  이 라인(${BRANCH})에는 설치 정합성 검사가 아직 없습니다 — 건너뜁니다."
fi

BEFORE="$(node -p "require('./package.json').version")"

# 멱등: 이 버전의 미푸시 bump 커밋이 이미 있으면 다시 만들지 않는다.
# merge-staging.sh 의 실패 안내가 "staging:deploy 로 마무리" 이므로 그 안내를 따를 때마다
# patch 가 한 번 더 올라갔다 — 배포된 적 없는 버전 번호를 소비하면서.
AFTER="${BEFORE}"
RESUME_BUMP="$(staging_unpushed_bump "${BRANCH}")"
if [ -n "${RESUME_BUMP}" ]; then
  echo "ℹ️  미푸시 bump 커밋이 이미 있어 bump·changelog·커밋을 건너뜁니다 (버전 ${AFTER} 유지):"
  git log -1 --oneline "${RESUME_BUMP}" | sed 's/^/     /'
else
  node scripts/bump-version.mjs patch >/dev/null
  AFTER="$(node -p "require('./package.json').version")"
  node scripts/changelog.mjs "${AFTER}" --staging   # STAGING_CHANGELOG.md 재생성 (라인 스냅샷)
  # 산출물만 스테이징한다. package-lock.json 분기는 이 리포(yarn)에 존재하지 않아 죽은
  # 코드였다 — 고정 목록은 없는 파일 하나로 전체가 실패하는 함정이 된다(#40).
  git add package.json
  [ -f CHANGELOG.md ] && git add CHANGELOG.md || true
  [ -f STAGING_CHANGELOG.md ] && git add STAGING_CHANGELOG.md || true
  git commit -qm "chore: staging deploy ${AFTER}"
  echo "▶ 스테이징 버전 ${BEFORE} -> ${AFTER}"
fi

# push — pre-push 훅이 여기서 콘텐츠 검사(tsc·test)를 돌린다. 원인을 메시지 문구가 아니라
# '상태' 로 판정한다(git 로케일·버전 무관). 셋을 뭉개고 모두에게 git pull 을 안내하면
# pre-push 거부에서도 pull 이 실행되고, 그 위에 재실행이 patch 를 또 올린다(2026-09 사건).
# 롤백하지 않는 이유: bump 커밋이 남아도 재실행이 staging_unpushed_bump 로 건너뛰므로
# 버전이 두 번 오르지 않는다. 되돌리면 오히려 changelog 를 다시 만들어야 한다.
if ! PUSH_OUT="$(git push origin "HEAD:${BRANCH}" 2>&1)"; then
  printf '%s\n' "${PUSH_OUT}"
  echo
  # 원인 판정 — 값싼 신호부터. dry-run 은 마지막 폴백이다.
  #   ⓐ 원격이 거부했다는 표시가 출력에 있으면 원격 문제로 확정한다. `--dry-run` 은 ref 를
  #      실제로 보내지 않아 원격 pre-receive 훅·브랜치 보호가 돌지 않으므로, 그 경우에도
  #      dry-run 은 성공한다 — 탐침만 믿으면 원격 거부를 로컬 훅 실패로 오분류한다(Codex 리뷰 P2).
  #   ⓑ husky 가 낸 로컬 훅 실패 마커가 있으면 로컬 훅으로 확정한다.
  #   ⓒ 표시가 없으면 dry-run(--no-verify) 탐침 — 성공하면 막은 것은 로컬 훅뿐이다.
  #   ⓓ 아니면 원격 tip 이 우리 계보 밖인지 확인한다 → non-fast-forward.
  #   ⓔ 그 외(네트워크·권한 등).
  # 뭉개고 모두에게 'git pull' 을 안내하면 pre-push 거부에서도 pull 이 실행되고, 그 위에
  # 재실행이 patch 를 또 올려 버전이 두 번 오른다(2026-09 사건).
  if printf '%s' "${PUSH_OUT}" | grep -qE 'remote rejected|pre-receive hook declined|protected branch'; then
    echo "❌ 원격이 push 를 거부했습니다 — 로컬 검사(.husky/pre-push)는 통과했습니다."
    echo "   위 remote 출력이 원인입니다(브랜치 보호 규칙·서버 훅·권한)."
    echo "   → 원격 설정을 확인한 뒤 같은 명령을 다시 실행하세요: yarn staging:deploy"
    echo "     (bump 커밋은 재사용되므로 버전이 두 번 오르지 않습니다)"
    exit 1
  fi
  if printf '%s' "${PUSH_OUT}" | grep -qE 'husky - pre-push|pre-push (hook|script)' \
    || git push --no-verify --dry-run origin "HEAD:${BRANCH}" >/dev/null 2>&1; then
    echo "❌ push 가 로컬 검사(.husky/pre-push)에 막혔습니다 — 원격은 변경되지 않았습니다."
    echo "   위 실패 내용이 원인입니다. bump 커밋(${AFTER})은 로컬에 남아 있고, 재실행은 그것을"
    echo "   그대로 재사용하므로 버전이 두 번 오르지 않습니다."
    echo "   → 원인을 고친 뒤 같은 명령을 다시 실행하세요: yarn staging:deploy"
    exit 1
  fi
  git fetch -q origin "+refs/heads/${BRANCH}:refs/remotes/origin/${BRANCH}" 2>/dev/null || true
  if ! git merge-base --is-ancestor "refs/remotes/origin/${BRANCH}" HEAD 2>/dev/null; then
    echo "❌ push 거부됨 — 원격 ${BRANCH} 가 앞서 있습니다(다른 사람이 먼저 배포했습니다)."
    echo "   → git pull --no-rebase 후 다시 실행하세요: yarn staging:deploy"
    echo "     (bump 커밋은 재사용되므로 버전이 두 번 오르지 않습니다)"
    exit 1
  fi
  echo "❌ push 실패 — 원인은 위 출력을 확인하세요(네트워크·권한·원격 설정 등)."
  echo "   → 원인을 해결한 뒤 같은 명령을 다시 실행하세요: yarn staging:deploy"
  exit 1
fi
printf '%s\n' "${PUSH_OUT}"

bash scripts/push-tag.sh staging
echo "✅ 스테이징 배포 트리거 완료 (${AFTER})"
