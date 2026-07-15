#!/usr/bin/env bash
#
# 버전 관리 자동화 로컬 세팅 (클론마다 1회 실행).
#  - package.json "version" merge driver('maxversion') 등록 → 되머지 충돌 자동 해소
#
# 사용법: bash scripts/setup-versioning.sh
#
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

git config merge.maxversion.name "package.json version: keep larger (max)"
git config merge.maxversion.driver "node scripts/merge-version.js %O %A %B"

echo "✅ merge driver 'maxversion' 등록 완료 (package.json version 충돌 자동 해소)."
echo "ℹ️  git-flow 는 avh 권장 — 각자 1회: brew install git-flow-avh"
