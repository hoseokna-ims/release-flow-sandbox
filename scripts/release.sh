#!/usr/bin/env bash
#
# 운영 릴리스 (2단계: 시작 → (선택)안정화 작업 → 마무리).
#   yarn release start [minor|major]   develop 기준 release 브랜치 생성 (기본 minor)
#   (여기서 막판 안정화 작업·커밋 — 선택)
#   yarn release finish                bump + changelog + finish(머지·태그) + push
#
# 원샷 실행은 지원하지 않는다(실수 방지). 반드시 start → finish.
#
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
source scripts/lib/checks.sh

start() {
  local TYPE="${1:-minor}"
  case "${TYPE}" in
    minor|major) ;;
    *) echo "사용법: yarn release start [minor|major]"; exit 1 ;;
  esac

  echo "▶ [사전검사] 워킹트리·잔재 브랜치"
  require_clean_tree
  require_no_stale_topic release

  echo "▶ [사전검사] fetch + develop/master 동기화"
  require_synced develop master

  local NEXT; NEXT="$(node scripts/next-version.mjs "${TYPE}")"
  echo "▶ 다음 버전: ${NEXT} (${TYPE})"
  require_semver_version "${NEXT}"
  require_tag_absent "${NEXT}"

  echo "▶ [사전검사] master 머지 충돌 시뮬 (package.json/lock 제외)"
  require_merge_clean master develop

  topic_start release "${NEXT}" develop
  echo "✅ release/${NEXT} 시작. (선택) 안정화 작업·커밋 후 → yarn release finish"
}

finish() {
  local BRANCH VERSION LAST RESUMABLE
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"

  # ── Phase 0: PREFLIGHT ──────────────────────────────────────────────
  # 읽기 전용. 하나라도 실패하면 아무것도 건드리지 않고 끝낸다(P1).
  case "${BRANCH}" in
    release/*) ;;
    *)
      # 중단된 finish 는 HEAD 를 master/develop 에 두고 죽는다(Phase 2 가 그 둘을
      # 체크아웃한다). 그 자리에서 재실행한 것이라면 이어받을 브랜치를 찾아 자동
      # 전환한다 — 스크립트가 만든 상태일 때만이고, 사용자가 브랜치를 잘못 고른
      # 경우는 그대로 막는다(find_resumable_topic 은 후보가 정확히 하나일 때만 답한다).
      RESUMABLE="$(find_resumable_topic release)"
      if [ -n "${RESUMABLE}" ]; then
        require_clean_tree
        echo "ℹ️  중단된 finish 를 발견했습니다 → ${RESUMABLE} 로 전환해 이어서 진행합니다."
        git switch -q "${RESUMABLE}"
        BRANCH="${RESUMABLE}"
      else
        echo "❌ release/* 브랜치에서 실행하세요 (현재: ${BRANCH})"
        LAST="$(git for-each-ref --format='%(refname:short)' 'refs/heads/release/*' | tail -1)"
        if [ -n "${LAST}" ]; then
          echo "   → git switch ${LAST} 후 다시 실행하세요."
        fi
        exit 1
      fi
      ;;
  esac
  VERSION="${BRANCH#release/}"

  echo "▶ [사전검사] 버전·워킹트리·동기화·머지 충돌"
  require_semver_version "${VERSION}"
  require_clean_tree_or_own_artifacts "${VERSION}"
  # Phase 2 까지 끝나고 push 전에 죽은 재실행이면 master/develop 의 ahead 는 이 스크립트가
  # 만든 것이다 — 여기서 막으면 설계된 재실행 경로가 막힌다. 그 경우만 확인 후 통과시킨다.
  ALLOW_AHEAD_RESUME=0
  if is_resumed_finish release "${VERSION}"; then ALLOW_AHEAD_RESUME=1; fi
  require_not_in_other_worktree master develop
  require_synced master develop
  require_topic_synced "${BRANCH}"
  require_merge_clean master  "${BRANCH}"
  require_merge_clean develop "${BRANCH}"
  record_baseline "${BRANCH}"

  # ── Phase 1: PREPARE ────────────────────────────────────────────────
  # 실패하면 브랜치를 시작 tip 으로 되돌린다 — 더럽혀진 트리가 남아 재실행이
  # 다른 에러로 튕기는 2차 함정을 없앤다(P3).
  if git log -1 --format=%s | grep -qF "chore: release ${VERSION}"; then
    # bump 커밋이 정본이다. 남은 산출물 수정은 되돌린다 — 더러운 채로 두면 Phase 2 의
    # checkout 이 실패하고, 그러면 태그가 master 가 아닌 곳에 붙는다(FE-1043).
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
      echo "ℹ️  bump 커밋이 이미 있습니다 → 남은 산출물 변경을 되돌리고 skip"
      # 실제로 더러운 경로만 되돌린다 — 고정 목록을 쓰면 없는 파일(package-lock.json 등)
      # 하나 때문에 git checkout 전체가 실패해 아무것도 복원되지 않는다.
      git status --porcelain --untracked-files=no | cut -c4- | while IFS= read -r P; do
        [ -n "${P}" ] && git checkout -- "${P}"
      done
    else
      echo "ℹ️  bump 커밋이 이미 있습니다 → 준비 단계 skip (재실행)"
    fi
  else
    trap 'rollback_baseline "${VERSION}"; echo "❌ 준비 단계 실패 — 브랜치를 시작 상태로 되돌렸습니다." >&2; echo "   원인(위 메시지)을 해결한 뒤 같은 명령을 재실행하세요." >&2' ERR
    echo "▶ bump + changelog (${VERSION})"
    node scripts/bump-version.mjs "${VERSION}" >/dev/null
    node scripts/changelog.mjs "${VERSION}"
    git add package.json
    [ -f package-lock.json ] && git add package-lock.json || true
    [ -f CHANGELOG.md ] && git add CHANGELOG.md || true
    git commit -qm "chore: release ${VERSION}"
    trap - ERR
  fi

  # ── Phase 2: MERGE/TAG ──────────────────────────────────────────────
  echo "▶ master·develop 머지 + 태그 ${VERSION}"
  if ! topic_merge_and_tag release "${VERSION}"; then
    rollback_baseline "${VERSION}"
    echo "❌ 머지 실패 — master/develop/태그를 시작 전 상태로 복원했습니다." >&2
    echo "   ${BRANCH} 는 그대로 있습니다. 충돌을 해결한 뒤 같은 명령을 재실행하세요." >&2
    exit 1
  fi

  # ── Phase 3: PUBLISH ────────────────────────────────────────────────
  # 브랜치 삭제는 push 성공 뒤에만 한다(P2) — 실패 시 재실행이 가능해야 하고,
  # 고아 태그가 남으면 다음 버전 계산(next-version.mjs)이 그 값을 건너뛴다.
  echo "▶ push (master 푸시 = 운영 배포 트리거)"
  # --atomic: master/develop/태그 3개 ref 를 전부 성공 or 전부 실패로 push (부분 반영=스플릿 방지)
  if ! git push --atomic origin master develop "${VERSION}"; then
    rollback_baseline "${VERSION}"
    echo "❌ push 실패 — 원격은 --atomic 으로 아무것도 반영되지 않았고, 로컬도 시작 전 상태로 복원했습니다." >&2
    echo "   → git fetch 후 master/develop 을 최신화하고 같은 명령을 재실행하세요." >&2
    exit 1
  fi
  if ! topic_delete release "${VERSION}"; then
    echo "⚠️ ${BRANCH} 삭제 실패 — 릴리스는 완료됐습니다. 수동 정리: git branch -d ${BRANCH}" >&2
  fi
  echo "✅ 릴리스 ${VERSION} 완료 — 태그 ${VERSION}, master 배포 트리거됨."

  # ── Phase 4: STAGING (best-effort) ──────────────────────────────────
  # 릴리스는 이미 끝났다 → staging 리프레시가 실패해도 릴리스 성공을 유지한다.
  trap - ERR
  echo "▶ staging 라인 리프레시 (develop 기준 새 staging + carry-over 자동 머지·배포)"
  if ! bash scripts/refresh-staging.sh; then
    echo "⚠️ staging 리프레시 미완료 — 릴리스(${VERSION})는 정상 완료됨. 위 안내대로 수동 마무리하세요." >&2
  fi
}

CMD="${1:-}"
case "${CMD}" in
  start) shift; start "${@:-}" ;;
  finish) finish ;;
  *) echo "사용법: yarn release start [minor|major]  |  yarn release finish"; exit 1 ;;
esac
