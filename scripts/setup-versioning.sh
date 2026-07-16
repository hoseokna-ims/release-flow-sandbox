#!/usr/bin/env bash
#
# 버전 관리 자동화 로컬 세팅 (클론마다 1회 실행 — postinstall 에서 자동 실행됨).
#  - package.json "version" merge driver('maxversion') 등록 → 되머지 충돌 자동 해소
#  - merge.ff false / pull.ff only → 머지커밋 보존(changelog 귀속·carry-over 판별 안전망)
#  - git-flow(avh) 초기화 → 신규 클론에서 yarn release/hotfix start 즉시 사용 가능
#
# 훅(pre-push)은 husky 가 관리한다(core.hooksPath=.husky/_, postinstall 의 `husky`).
# 여기서 core.hooksPath 를 건드리지 않는다 — husky 설정과 충돌 방지.
#
# 사용법: bash scripts/setup-versioning.sh
#
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

git config merge.maxversion.name "package.json version: keep larger (max)"
git config merge.maxversion.driver "node scripts/merge-version.js %O %A %B"

# 머지커밋 보존: fast-forward 머지를 막아 브랜치 귀속(^2) 이 깨지지 않게 한다.
git config merge.ff false
git config pull.ff only

# git-flow(avh) 초기화: 설치돼 있으면 기본값으로 init 한다.
#  - 멱등 — 이미 초기화된 repo 에서 재실행해도 gitflow.* 를 같은 기본값으로 다시 set 할 뿐(누적·에러·프롬프트 없음).
#  - -d(기본값) 라 대화형 입력 없음. 미설치 머신에서도 위 merge driver/ff 등록이 보장되도록
#    맨 뒤에 두고 `command -v git-flow` 가드 + `|| true` 로 install(postinstall) 을 절대 깨지 않는다.
command -v git-flow >/dev/null 2>&1 && git flow init -d >/dev/null 2>&1 || true

echo "✅ merge driver 'maxversion' + ff 정책(merge.ff/pull.ff) 등록 완료."
if command -v git-flow >/dev/null 2>&1; then
  echo "✅ git-flow 초기화 완료(git flow init -d)."
else
  echo "ℹ️  git-flow 미설치 — release/hotfix 사용 전 각자 1회: brew install git-flow-avh (init 은 다음 install 시 자동)"
fi
