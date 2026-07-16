#!/usr/bin/env bash
#
# 버전 관리 자동화 로컬 세팅 (클론마다 1회 실행 — postinstall 에서 자동 실행됨).
#  - package.json "version" merge driver('maxversion') 등록 → 되머지 충돌 자동 해소
#  - merge.ff false / pull.ff only → 머지커밋 보존(changelog 귀속·carry-over 판별 안전망)
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

echo "✅ merge driver 'maxversion' + ff 정책(merge.ff/pull.ff) 등록 완료."
echo "ℹ️  git-flow 는 avh 권장 — 각자 1회: brew install git-flow-avh && git flow init -d"
