#!/usr/bin/env bash
#
# 릴리스 플로우 공용 사전검사 라이브러리.
#
# release.sh / hotfix.sh 가 source 해서 쓴다 (리포 루트로 cd 한 뒤):
#   source scripts/lib/checks.sh
#
# 설계 원칙
#  - 모든 검사는 "첫 변경 전"에 끝낸다. 실패하면 아무것도 건드리지 않고 종료한다.
#  - 모든 실패 메시지는 "무엇이 왜 안 되는지 한 줄" + "복사해 실행할 다음 명령"을 포함한다.
#  - 외부 릴리스 도구(git flow)에 의존하지 않는다. 사전검사뿐 아니라 머지·태그·브랜치
#    정리까지 이 라이브러리가 직접 수행한다(topic_start / topic_finish).
#    동작 기준은 gitflow-avh 1.12.3 — 팀 다수가 쓰던 에디션이라 히스토리 모양을 맞춘다.
#
# 이 파일의 함수는 실패 시 exit 1 한다(source 된 호출 스크립트가 종료된다).
#

# 대화형이면 y/N 확인, 비대화형이면 중단(안전측 기본값).
# RELEASE_ASSUME_YES=1 로 비대화형 자동 승인 가능 — CI 에서 의도적으로 쓸 때만.
confirm() {
  local MSG="$1"
  if [ "${RELEASE_ASSUME_YES:-}" = "1" ]; then
    echo "${MSG} → RELEASE_ASSUME_YES=1 로 자동 승인"
    return 0
  fi
  if [ -t 0 ]; then
    local ANS
    printf '%s [y/N] ' "${MSG}"
    read -r ANS
    case "${ANS}" in
      y | Y) return 0 ;;
      *) echo "중단했습니다."; exit 1 ;;
    esac
  fi
  echo "${MSG}"
  echo "   → 비대화형 환경에서는 자동 중단합니다. 정리 후 재실행하세요."
  echo "     (의도적으로 진행하려면 RELEASE_ASSUME_YES=1)"
  exit 1
}

# <ref> 가 <branch> 에 이미 머지됐는가 (avh git_is_branch_merged_into 동등)
is_merged_into() {
  [ "$(git merge-base "$1^{}" "$2^{}")" = "$(git rev-parse "$1^{}")" ]
}

# 두 ref 관계 (avh git_compare_refs 동등)
#   0=동일  1=$1 이 $2 의 조상(behind)  2=$2 가 $1 의 조상(ahead)  3=diverged  4=공통조상 없음
compare_refs() {
  local C1 C2 BASE
  C1="$(git rev-parse "$1^{}")"; C2="$(git rev-parse "$2^{}")"
  [ "${C1}" = "${C2}" ] && return 0
  BASE="$(git merge-base "${C1}" "${C2}" 2>/dev/null)" || return 4
  [ -z "${BASE}" ] && return 4
  [ "${C1}" = "${BASE}" ] && return 1
  [ "${C2}" = "${BASE}" ] && return 2
  return 3
}

require_clean_tree() {
  [ -z "$(git status --porcelain --untracked-files=no)" ] && return 0
  echo "❌ 워킹트리에 커밋 안 된 변경이 있습니다:"
  git status --short --untracked-files=no | sed 's/^/     /'
  echo "   → 커밋하거나 git stash 후 재실행하세요."
  exit 1
}

# finish 전용 — 워킹트리가 깨끗하거나, 더러운 게 'Phase 1 이 만들다 만 자기 산출물'
# 뿐이면 통과시킨다. Phase 1 이 중단되면(Ctrl-C 등 시그널에는 ERR 트랩이 안 걸린다)
# bump·changelog 가 커밋 안 된 채 남는데, 이건 사용자 작업이 아니라 스크립트 출력이고
# Phase 1 은 멱등이라(bump 는 같은 값, changelog.mjs 는 같은 버전 섹션을 교체) 그대로
# 덮어쓰면 된다. 여기서 막으면 사용자는 자기가 만들지도 않은 변경을 stash 해야 한다.
#
# 판정은 좁게 — 두 조건을 다 만족할 때만.
#   1) 더러운 경로가 {package.json, package-lock.json, CHANGELOG.md} 안에만 있다
#   2) package.json 의 version 이 이미 이번 릴리스 버전이다 (= 우리 bump 가 돌았다는 증거)
# 하나라도 어긋나면 사용자 변경일 수 있으므로 기존대로 차단한다.
require_clean_tree_or_own_artifacts() {
  local VERSION="$1" DIRTY P PKG_VERSION
  DIRTY="$(git status --porcelain --untracked-files=no)"
  [ -z "${DIRTY}" ] && return 0

  PKG_VERSION="$(node -p "require('./package.json').version" 2>/dev/null || echo "")"
  if [ "${PKG_VERSION}" = "${VERSION}" ]; then
    local OURS=1
    while IFS= read -r P; do
      [ -z "${P}" ] && continue
      P="${P:3}"                                   # porcelain v1: XY<space><path>
      case "${P}" in
        *" -> "*) OURS=0 ;;                        # 리네임 — 우리 산출물이 아니다
        package.json | package-lock.json | CHANGELOG.md) ;;
        *) OURS=0 ;;
      esac
    done < <(printf '%s\n' "${DIRTY}")
    if [ "${OURS}" -eq 1 ]; then
      echo "ℹ️  중단된 준비 단계의 산출물이 남아 있습니다 → 다시 생성해 이어갑니다:"
      git status --short --untracked-files=no | sed 's/^/     /'
      return 0
    fi
  fi

  require_clean_tree
}

# 이어받을 수 있는 토픽 브랜치를 찾는다 — 정확히 하나일 때만 이름을 출력한다.
# (한 개도 없거나 둘 이상이면 추측하지 않는다: 무출력)
find_resumable_topic() {
  local PREFIX="$1" B FOUND="" COUNT=0
  while IFS= read -r B; do
    [ -z "${B}" ] && continue
    [[ "${B}" =~ ^${PREFIX}/[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    if is_resumed_finish "${PREFIX}" "${B#"${PREFIX}"/}"; then
      FOUND="${B}"; COUNT=$((COUNT + 1))
    fi
  done < <(git for-each-ref --format='%(refname:short)' "refs/heads/${PREFIX}/*" || true)
  [ "${COUNT}" -eq 1 ] && printf '%s' "${FOUND}"
  return 0
}

# 릴리스 버전 형식(X.Y.0). 운영 버전은 patch=0 이 규칙이다.
require_semver_version() {
  local V="$1"
  [[ "${V}" =~ ^[0-9]+\.[0-9]+\.0$ ]] && return 0
  echo "❌ 릴리스 버전 형식이 아닙니다: '${V}' (X.Y.0 이어야 합니다)"
  echo "   운영 버전은 patch=0 입니다. 브랜치명 또는 package.json 의 version 을 확인하세요."
  exit 1
}

require_tag_absent() {
  local TAG="$1"
  if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null 2>&1; then
    echo "❌ 태그 ${TAG} 가 이미 로컬에 있습니다."
    echo "   이전 릴리스가 중단돼 남은 태그일 수 있습니다(그대로 두면 다음 버전 계산이 이 값을 건너뜁니다)."
    echo "   → 원격에 없는 태그라면 삭제하세요: git tag -d ${TAG}"
    exit 1
  fi
  if git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
    echo "❌ 태그 ${TAG} 가 이미 원격에 있습니다 — 이미 릴리스된 버전입니다."
    exit 1
  fi
}

# 중단된 finish 의 재실행 상태인가 — Phase 2(머지·태그)까지 끝나고 push 전에 죽은 경우.
# 이 상태에서만 master/develop 의 ahead 가 '스크립트 자신이 만든 것' 이다.
#
# 세 조건을 모두 요구한다. 사고(2026-07-29) 형태 — bump 없이 수동 `git flow finish` 를
# 호출해 master 에 머지·태그만 만들어진 상태 — 를 재실행으로 오인하지 않기 위해서다.
#   1) 토픽 브랜치 tip 이 이 버전의 bump 커밋   (수동 git flow 에는 없다)
#   2) 그 브랜치가 이미 master 에 머지됨        (Phase 2 를 지났다)
#   3) 태그가 없거나 master tip 을 가리킴        (다른 커밋을 가리키면 bump 없는 재배포다)
is_resumed_finish() {
  local PREFIX="$1" VERSION="$2" BRANCH="$1/$2" TAG_SHA
  git log -1 --format=%s "${BRANCH}" 2>/dev/null | grep -qF "chore: ${PREFIX} ${VERSION}" || return 1
  is_merged_into "${BRANCH}" master || return 1
  TAG_SHA="$(git rev-parse -q --verify "refs/tags/${VERSION}^{commit}" 2>/dev/null || true)"
  [ -z "${TAG_SHA}" ] || [ "${TAG_SHA}" = "$(git rev-parse master)" ] || return 1
  return 0
}

# 로컬 브랜치가 origin 과 동기화됐는지 확인.
#  - behind / diverged → 차단 (안내는 pull.ff=only 설정을 반영해 구분한다)
#  - ahead            → 차단. 미푸시 커밋은 리뷰·CI 를 거치지 않은 채 이번 릴리스에 실려
#                       나가고, master 의 미푸시 커밋은 그대로 운영 배포다. git-flow 계열은
#                       ahead 를 '무해'로 보지만 이 리포에서는 유해하다(설계문서 §5).
#                       ※ pre-push 태그 정합성 가드는 이걸 잡지 못한다 — 우회로 만든 커밋
#                         위에 정상 릴리스를 얹으면 태그가 새 master tip 을 가리켜 통과한다.
#  - 예외             → 중단된 finish 의 재실행(ALLOW_AHEAD_RESUME=1)일 때만 목록 + 확인.
ALLOW_AHEAD_RESUME="${ALLOW_AHEAD_RESUME:-0}"
require_synced() {
  git fetch origin --prune
  local BR BEHIND AHEAD
  for BR in "$@"; do
    if ! git rev-parse --verify --quiet "refs/heads/${BR}" >/dev/null; then
      echo "❌ 로컬 브랜치가 없습니다: ${BR}"
      echo "   → git switch -c ${BR} origin/${BR}"
      exit 1
    fi
    read -r BEHIND AHEAD < <(git rev-list --left-right --count "origin/${BR}...${BR}" 2>/dev/null || echo "0 0")
    if [ "${BEHIND}" -gt 0 ] && [ "${AHEAD}" -gt 0 ]; then
      echo "❌ ${BR} 가 origin 과 갈라졌습니다 (behind ${BEHIND}, ahead ${AHEAD})."
      echo "   → git switch ${BR} && git pull --rebase"
      echo "     (맨 git pull 은 pull.ff=only 설정 때문에 'Not possible to fast-forward' 로 실패합니다)"
      exit 1
    elif [ "${BEHIND}" -gt 0 ]; then
      echo "❌ ${BR} 가 origin 보다 ${BEHIND} 커밋 뒤처졌습니다."
      echo "   → git switch ${BR} && git pull"
      exit 1
    elif [ "${AHEAD}" -gt 0 ] && [ "${ALLOW_AHEAD_RESUME}" = "1" ]; then
      echo "⚠️  ${BR} 에 push 안 된 로컬 커밋 ${AHEAD}개 — 중단된 finish 의 재실행으로 보입니다:"
      git log --oneline "origin/${BR}..${BR}" | sed 's/^/     /'
      confirm "   이어서 마무리할까요?"
    elif [ "${AHEAD}" -gt 0 ]; then
      echo "❌ ${BR} 에 push 안 된 로컬 커밋 ${AHEAD}개가 있습니다 — 리뷰·CI 를 거치지 않은 채 이번 릴리스에 실려 나갑니다:"
      git log --oneline "origin/${BR}..${BR}" | sed 's/^/     /'
      if [ "${BR}" = "master" ]; then
        # master 는 finish 의 Phase 2→3 사이에서만 잠깐 ahead 다. 그 외의 ahead 는
        # 래퍼 밖에서 master 를 건드렸다는 뜻이므로 'push 하세요' 로 안내하면 안 된다
        # (master push = 운영 배포).
        echo "   master 는 릴리스 스크립트 밖에서 커밋·머지하지 않습니다 — 우회 조작의 흔적입니다."
        echo "   → 진행 중인 릴리스가 남아 있으면: git switch release/<버전> (또는 hotfix/<버전>) 후 finish"
        echo "   → 위 커밋이 불필요한 잔재임을 확인했으면: git reset --hard origin/master"
        echo "     (master 를 직접 push 하지 마세요 — 그 자체가 운영 배포입니다)"
      else
        echo "   → 릴리스에 묻어 나가지 않도록 먼저 올리세요: git switch ${BR} && git push"
      fi
      exit 1
    fi
  done
}

# <base> 에 <topic> 을 머지할 때 충돌이 예상되는지 미리 확인.
# package.json / package-lock.json 은 maxversion 머지 드라이버가 자동 해소하므로 제외한다.
require_merge_clean() {
  local BASE="$1" TOPIC="$2" MT CONFLICTS
  MT="$(mktemp)"
  if ! git merge-tree --write-tree --name-only "${BASE}" "${TOPIC}" >"${MT}" 2>/dev/null; then
    CONFLICTS="$(tail -n +2 "${MT}" | grep -v -e '^$' -e '^package.json$' -e '^package-lock.json$' || true)"
    if [ -n "${CONFLICTS}" ]; then
      rm -f "${MT}"
      echo "❌ ${BASE} ← ${TOPIC} 머지 충돌이 예상됩니다:"
      printf '%s\n' "${CONFLICTS}" | sed 's/^/     /'
      echo "   → 먼저 '${BASE}' 를 '${TOPIC}' 로 머지해 충돌을 해결·커밋한 뒤 재실행하세요."
      exit 1
    fi
  fi
  rm -f "${MT}"
}

# 남아 있는 release/* 또는 hotfix/* 로컬 브랜치를 먼저 진단한다.
# 릴리스는 한 번에 하나만 진행한다(avh 의 require_no_existing_*_branches 와 동등).
# 접두사를 작업 브랜치에 오용한 경우가 특히 위험하다 — 그대로 finish 하면 그 브랜치가
# master 에 머지되고 태그까지 붙는다.
require_no_stale_topic() {
  local PREFIX="$1" FOUND B HAS_WORK=0 HAS_MERGED=0
  FOUND="$(git for-each-ref --format='%(refname:short)' "refs/heads/${PREFIX}/*" || true)"
  [ -z "${FOUND}" ] && return 0

  echo "❌ 로컬에 ${PREFIX}/* 브랜치가 이미 있습니다 — ${PREFIX} 는 한 번에 하나만 진행할 수 있습니다."
  echo

  # 브랜치마다 성격을 판정해 각각 맞는 명령을 제시한다.
  #  · 비-semver        → 작업 브랜치 오용. rename
  #  · semver + 머지완료 → 지난 릴리스의 잔재. 삭제 (finish 를 실행하면 안 된다)
  #  · semver + 미머지   → 진행 중인 릴리스. finish
  while IFS= read -r B; do
    [ -z "${B}" ] && continue
    if ! [[ "${B}" =~ ^${PREFIX}/[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      HAS_WORK=1
      echo "     - ${B}   (작업 브랜치로 보입니다 — ${PREFIX}/ 는 릴리스 전용)"
      echo "       → git branch -m ${B} fix/${B#"${PREFIX}"/}"
    elif git rev-parse --verify --quiet master >/dev/null 2>&1 \
      && is_merged_into "${B}" master 2>/dev/null; then
      HAS_MERGED=1
      echo "     - ${B}   (master 에 머지 완료 — 지난 릴리스의 잔재)"
      echo "       → git branch -d ${B}"
    else
      echo "     - ${B}   (미머지 — 진행 중인 릴리스로 보입니다)"
      echo "       → git switch ${B} && yarn ${PREFIX} finish"
    fi
  done < <(printf '%s\n' "${FOUND}")

  if [ "${HAS_WORK}" -eq 1 ]; then
    echo
    echo "   ※ 작업 브랜치는 fix/ 를 사용하세요 — ${PREFIX} finish 를 실행하면 그 브랜치가"
    echo "      master 에 머지되고 태그까지 생성됩니다."
  fi
  if [ "${HAS_MERGED}" -eq 1 ]; then
    echo
    echo "   ※ 머지 완료된 브랜치에 ${PREFIX} finish 를 실행하지 마세요 — 이미 배포된 버전입니다."
  fi
  exit 1
}

# topic 브랜치가 origin 에 있으면 원격이 앞서지 않는지 확인.
# (avh 는 finish 에서 항상 topic 브랜치를 fetch 하고 require_branches_equal 한다 —
#  staging:merge 로 topic 브랜치를 push 해 두는 흐름이 있어 실제로 의미가 있다)
require_topic_synced() {
  local BRANCH="$1" BEHIND AHEAD
  git rev-parse --verify --quiet "refs/remotes/origin/${BRANCH}" >/dev/null || return 0
  git fetch -q origin "${BRANCH}" 2>/dev/null || true
  read -r BEHIND AHEAD < <(git rev-list --left-right --count "origin/${BRANCH}...${BRANCH}" 2>/dev/null || echo "0 0")
  if [ "${BEHIND}" -gt 0 ]; then
    echo "❌ ${BRANCH} 가 origin 보다 ${BEHIND} 커밋 뒤처졌습니다 — 원격 커밋이 릴리스에서 누락됩니다."
    if [ "${AHEAD}" -gt 0 ]; then
      echo "   → git switch ${BRANCH} && git pull --rebase 후 재실행하세요. (갈라짐: ahead ${AHEAD})"
    else
      echo "   → git switch ${BRANCH} && git pull 후 재실행하세요."
    fi
    exit 1
  fi
}

# ── git flow 대체 구현 ────────────────────────────────────────────────
# gitflow-avh 1.12.3 의 `git flow {release,hotfix} start|finish` 와 동등하게 동작한다.
# git-flow 는 nvie·avh 모두 upstream 아카이브 상태이고 avh 는 Homebrew 에서 제거돼
# 신규 설치가 불가능하다(설계문서 §2). 하는 일이 checkout·merge·tag·merge·delete
# 다섯 단계뿐이라 직접 구현해 도구 의존을 끊는다.

topic_start() {
  local PREFIX="$1" VERSION="$2" BASE="$3" BRANCH="$1/$2"
  if git rev-parse --verify --quiet "refs/heads/${BRANCH}" >/dev/null; then
    echo "❌ 브랜치가 이미 존재합니다: ${BRANCH}"
    exit 1
  fi
  git switch -q -c "${BRANCH}" "${BASE}"
}

# 1) master 머지 → 2) 태그 → 3) develop 에 '태그' 되머지
# 각 단계는 이미 완료됐으면 건너뛴다 (중단 후 재실행 대비 — avh 와 동일).
# 브랜치 삭제는 topic_delete 로 분리했다 — push 성공 뒤에만 지우기 위해서다(P2).
topic_merge_and_tag() {
  local PREFIX="$1" VERSION="$2" BRANCH="$1/$2"

  if ! is_merged_into "${BRANCH}" master; then
    git checkout -q master
    GIT_MERGE_AUTOEDIT=no git merge --no-ff "${BRANCH}" || return 1
  fi

  if ! git rev-parse -q --verify "refs/tags/${VERSION}" >/dev/null; then
    git checkout -q master
    git tag -a -m "${VERSION}" "${VERSION}" || return 1
  fi

  # 브랜치가 아니라 '태그' 를 머지한다 — avh 기본 동작(`git describe` 정합성).
  # 히스토리에 "Merge tag 'X' into develop" 으로 남는다. skip 판정도 master 기준(avh 동일).
  if ! is_merged_into master develop; then
    git checkout -q develop
    GIT_MERGE_AUTOEDIT=no git merge --no-ff "${VERSION}" || return 1
  fi
}

# 브랜치 정리 — 원격 먼저, 로컬 나중 (avh 순서: 로컬을 먼저 지우면 경고가 난다)
topic_delete() {
  local PREFIX="$1" VERSION="$2" BRANCH="$1/$2" AFTER_DELETE
  # 삭제 직전 돌아갈 브랜치: release→master, hotfix→develop (avh 동작)
  case "${PREFIX}" in
    release) AFTER_DELETE=master ;;
    *)       AFTER_DELETE=develop ;;
  esac
  if [ "$(git rev-parse --abbrev-ref HEAD)" = "${BRANCH}" ]; then
    git checkout -q "${AFTER_DELETE}"
  fi
  if git rev-parse --verify --quiet "refs/remotes/origin/${BRANCH}" >/dev/null; then
    git push -q origin ":refs/heads/${BRANCH}" 2>/dev/null || true
  fi
  git branch -q -d "${BRANCH}"
}

# ── 롤백 지원 ─────────────────────────────────────────────────────────
# finish 는 ref 를 여러 개 순차로 바꾼다(브랜치 tip → master → 태그 → develop).
# 중간에 실패하면 반쯤 끝난 상태가 남아 재실행이 불가능해지므로, 시작 전 SHA 를
# 기록해 두고 실패 시 전부 되돌린다.
#
# 기준은 origin 이 아니라 "시작 시점의 로컬 SHA" 다 — preflight 에서 ahead 를
# 승인받은 경우 origin 으로 리셋하면 승인된 로컬 커밋이 유실된다.
BASE_MASTER=""; BASE_DEVELOP=""; BASE_TOPIC_TIP=""; BASE_TOPIC_BRANCH=""

record_baseline() {
  BASE_TOPIC_BRANCH="$1"
  BASE_MASTER="$(git rev-parse master)"
  BASE_DEVELOP="$(git rev-parse develop)"
  BASE_TOPIC_TIP="$(git rev-parse "${BASE_TOPIC_BRANCH}")"
}

# 실패 시 master/develop/태그/토픽 브랜치를 기록된 시작 상태로 되돌린다.
# 원격은 --atomic push 덕분에 애초에 무변경이므로 로컬만 복원하면 재실행 가능 상태가 된다.
rollback_baseline() {
  local VERSION="${1:-}"
  git merge --abort >/dev/null 2>&1 || true

  # 토픽 브랜치를 먼저 복원·체크아웃한다 — master/develop 을 -f 로 옮기려면
  # 그 브랜치가 체크아웃돼 있지 않아야 한다.
  if ! git rev-parse --verify --quiet "refs/heads/${BASE_TOPIC_BRANCH}" >/dev/null; then
    git branch "${BASE_TOPIC_BRANCH}" "${BASE_TOPIC_TIP}" >/dev/null 2>&1 || true
  fi
  git checkout -q -f "${BASE_TOPIC_BRANCH}" >/dev/null 2>&1 || true
  git reset -q --hard "${BASE_TOPIC_TIP}" >/dev/null 2>&1 || true

  git branch -f master  "${BASE_MASTER}"  >/dev/null 2>&1 || true
  git branch -f develop "${BASE_DEVELOP}" >/dev/null 2>&1 || true
  if [ -n "${VERSION}" ]; then
    git tag -d "${VERSION}" >/dev/null 2>&1 || true
  fi
  return 0
}
