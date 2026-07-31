#!/usr/bin/env bash
#
# 버전 관리 자동화 로컬 세팅 (클론마다 1회 실행 — postinstall 에서 자동 실행됨).
#  - package.json "version" merge driver('maxversion') 등록 → 되머지 충돌 자동 해소
#  - merge.ff false / pull.ff only → 머지커밋 보존(changelog 귀속·carry-over 판별 안전망)
#
# git-flow 는 더 이상 필요하지 않다 — release/hotfix 스크립트가 머지·태그를 직접 수행한다.
# (nvie·avh 모두 upstream 아카이브, avh 는 Homebrew 에서 제거됨. 설계문서 §2)
# 기존 클론에 남아 있는 gitflow.* config 는 건드리지 않는다 — 손으로 git flow 를 쓰는
# 사람에게 영향을 주지 않기 위해서다(우리 스크립트는 그 값을 읽지 않는다).
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
