# Changelog

## [0.20.0] - 2026-07-20

### feature/FE-1020
- feat: staging 브랜치를 날짜(YYMMDD) → 버전 라인(staging/<major>.<minor>)으로 전환 ([65a3501](https://github.com/hoseokna-ims/release-flow-sandbox/commit/65a3501cefd6dcfdd8b24b2f6dd07de96f851b8d))

## [0.19.0] - 2026-07-16

### feature/FE-1019
- docs: README 배포 명령어 안내 추가 (imsform FE-2714) ([d501da7](https://github.com/hoseokna-ims/release-flow-sandbox/commit/d501da7ce03c17d7587b31fe9e29d9117ec53d52))
- chore: setup-versioning 에 git-flow init 자동화(가드) 추가 (imsform FE-2714) ([d4be70f](https://github.com/hoseokna-ims/release-flow-sandbox/commit/d4be70f9cf9f8c22316bc4bef34014fbb58dabd5))
- fix: 배포 스크립트 Gemini 리뷰 지적 4건 역-반영 (imsform FE-2714) ([1134828](https://github.com/hoseokna-ims/release-flow-sandbox/commit/1134828e2cce5dcb76b3e5f57f14a9e9700a1678))

## [0.18.0] - 2026-07-16

### hotfix/0.18.0
- chore: test ([842b340](https://github.com/hoseokna-ims/release-flow-sandbox/commit/842b34084f39e1425e2ef21513075870ca5647f1))

## [0.17.0] - 2026-07-16

### feature/FE-2000
- chore: 테스트 ([e102e7c](https://github.com/hoseokna-ims/release-flow-sandbox/commit/e102e7cc3af0fef64a17207368c4c69c89ab63e1))

## [0.16.0] - 2026-07-16

### feature/FE-1018
- refactor: pre-push 를 imsform 구조로 재작성 (husky 관리 + node -p 버전 읽기) ([bc1064d](https://github.com/hoseokna-ims/release-flow-sandbox/commit/bc1064d0f5074aa6b486376007921ff59b55f4ba))
- refactor: setup-versioning 에서 core.hooksPath 제거 (husky 가 관리) ([ddbb24b](https://github.com/hoseokna-ims/release-flow-sandbox/commit/ddbb24bd6cabd0882de4946312cbfc1aaaa5025b))
- chore: husky 도입 — imsform 과 동일한 훅 관리 방식으로 정렬 ([09e5b69](https://github.com/hoseokna-ims/release-flow-sandbox/commit/09e5b691466bb88a95132776b7fe4abd3283ffa9))
- chore: postinstall 로 setup-versioning 자동 실행 (merge driver 활성화) ([69be39f](https://github.com/hoseokna-ims/release-flow-sandbox/commit/69be39f8b84cd2b3c50de2482dbdbf908e45823b))
- feat: 로컬 안전망 복원 — merge.ff/pull.ff + pre-push 훅(.husky) ([ce8ec94](https://github.com/hoseokna-ims/release-flow-sandbox/commit/ce8ec9476b0bf7ab9fb096cf98fa6dbac13eeeed))
- fix: release/hotfix finish push 를 --atomic 으로 (스플릿 방지) ([0f994ed](https://github.com/hoseokna-ims/release-flow-sandbox/commit/0f994ed0f3c64b98736d811a716c6901c81eb0e6))

## [0.15.0] - 2026-07-16

### feature/FE-1015
- docs: 기여 가이드(CONTRIBUTING.md) 추가 ([341d762](https://github.com/hoseokna-ims/release-flow-sandbox/commit/341d762e267d9fb78d6479f2a1ccae5fb1494396))
- feat: 사이트 공통 설정 상수 모듈 추가 ([ae455ce](https://github.com/hoseokna-ims/release-flow-sandbox/commit/ae455cecb2e5fcb71b0ca63daeaeb9222e58188e))

### feature/FE-1012
- style: 푸터 안내 문구 보강 ([28d5814](https://github.com/hoseokna-ims/release-flow-sandbox/commit/28d58149fd4ba880a187485ebd0f3d6a655c742e))
- style: CTA 버튼 문구 다듬기 ([436289b](https://github.com/hoseokna-ims/release-flow-sandbox/commit/436289b9dbf47523c1a6b6f119b41d2c57a43cb6))
- feat: 버전 배지에 릴리스 상태 라벨 표시 ([d17a8ca](https://github.com/hoseokna-ims/release-flow-sandbox/commit/d17a8cac74cfcc5233dbfc53fa685c9afc544c59))
- feat: 릴리스 상태 판별 helper 추가 및 버전 동기화 ([9ae1ed9](https://github.com/hoseokna-ims/release-flow-sandbox/commit/9ae1ed90ca7c2d64126989321458d7db92c60fdf))

### feature/FE-1011
- style: 링크 색상 전환 효과 추가 ([3c564bd](https://github.com/hoseokna-ims/release-flow-sandbox/commit/3c564bd2944dbd9cea2f2bb9d51ed0e385d580ef))
- docs: README 상단에 프로젝트 소개 추가 ([e62ff6b](https://github.com/hoseokna-ims/release-flow-sandbox/commit/e62ff6b7fde47f8456609657411249ae983664c4))
- feat: 푸터에 저장소·이슈 링크 추가 ([21fd50e](https://github.com/hoseokna-ims/release-flow-sandbox/commit/21fd50e3aa262fade307497cba0ce1b494d76052))
- feat: 저장소 URL 상수 추가 ([1426fab](https://github.com/hoseokna-ims/release-flow-sandbox/commit/1426fab8a5e4a06b2d55821ea981916ce4e252b2))

### feature/FE-1010
- docs: 앱 메타데이터 문구 한글화 및 보강 ([701299e](https://github.com/hoseokna-ims/release-flow-sandbox/commit/701299e17815a2f761f35b9a005c4a06b9808d4a))
- style: 전역 accent 색상 토큰 추가 ([a076f94](https://github.com/hoseokna-ims/release-flow-sandbox/commit/a076f9427a05d106730ba9d609535cd1fcd88409))
- feat: 메인 헤드라인 문구 개선 및 배지에 배포 채널 표시 ([96a23d3](https://github.com/hoseokna-ims/release-flow-sandbox/commit/96a23d3e65c3fa248a776098b5db42fdf430597d))
- feat: 릴리스 배포 채널 상수 추가 ([b5446ad](https://github.com/hoseokna-ims/release-flow-sandbox/commit/b5446ad6cf2bc0105e4b968e33021df939af73c2))

## [0.14.0] - 2026-07-16

### hotfix/0.14.0
- chore: yarn.lock으로 변경 ([e322491](https://github.com/hoseokna-ims/release-flow-sandbox/commit/e322491e1ea5a118a017d77b352e6ae09bdb5d74))

## [0.13.0] - 2026-07-16

### hotfix/0.13.0
- chore: 문구 제거 ([8e08632](https://github.com/hoseokna-ims/release-flow-sandbox/commit/8e08632c29e0c0262d1f7316511f69ea0e02359c))

## [0.12.0] - 2026-07-16

### hotfix/0.12.0
- chore: 테스트용 커밋 ([1ba2e95](https://github.com/hoseokna-ims/release-flow-sandbox/commit/1ba2e95d262e931b2597ca89192b5854a612b4f8))
- feat: staging:merge 다중 인자화 + staging:new 초기 bump 제거 ([a6a4b0b](https://github.com/hoseokna-ims/release-flow-sandbox/commit/a6a4b0bd1c8e6b459b04891f98534f2632aa6cc8))

## [0.11.0] - 2026-07-16

### feature/FE-1013
- docs: 스크립트 안내 문구를 yarn 명령 표기로 통일 ([b294845](https://github.com/hoseokna-ims/release-flow-sandbox/commit/b294845e45038425ac955ceee105d04055dd0ffc))

## [0.10.0] - 2026-07-16

### feature/FE-1009
- feat: CHANGELOG 을 소스 브랜치별로 그룹핑 (changelog.sh → changelog.mjs) ([7782236](https://github.com/hoseokna-ims/release-flow-sandbox/commit/7782236bffc639a3487de8efde39c4ffdfc815db))

### feature/FE-1008
- refactor: clean-check는 tracked 수정만 + 명시적 staging ([8c2112b](https://github.com/hoseokna-ims/release-flow-sandbox/commit/8c2112b8a0dbf563229716a98eca01e7a913e328))

## [0.9.0] - 2026-07-15

### Added
- staging:merge 추가 + staging:new 가드/carry-over 안내 ([56b4740](https://github.com/hoseokna-ims/release-flow-sandbox/commit/56b474095243b7fbb0f86d9609b5ab90b0a3377d))
- 메인 하단에 안내 문구 푸터 추가 ([ddb7605](https://github.com/hoseokna-ims/release-flow-sandbox/commit/ddb76053e338721e0ebc18e75171ea05e6e271c8))
- CTA 버튼 문구·링크를 릴리스 흐름에 맞게 변경 ([02820e5](https://github.com/hoseokna-ims/release-flow-sandbox/commit/02820e5286534d8788f0440932213b62644d5c53))
- 메인 상단에 현재 버전 배지 UI 추가 ([e45a1c3](https://github.com/hoseokna-ims/release-flow-sandbox/commit/e45a1c319e9594a2a3f7dfe3d22aa43903c8a264))
- 메인 헤드라인·설명 문구를 한글 안내로 교체 ([f85936c](https://github.com/hoseokna-ims/release-flow-sandbox/commit/f85936c107576bb74758b971bc9840a13b827c06))
- 앱 메타데이터 문구를 서비스에 맞게 수정 ([c977505](https://github.com/hoseokna-ims/release-flow-sandbox/commit/c9775058ad2816e57ea8cbbbedabdf19ead5eacb))
- staging 배포에 운영 버전(patch==0) 차단 가드 추가 ([3da75a4](https://github.com/hoseokna-ims/release-flow-sandbox/commit/3da75a43fc5f95fc3029370239ecaa442ca30980))


## [0.8.0] - 2026-07-15

### Added
- release 를 start/finish 2단계로 전환 (원샷 제거) ([75425fd](https://github.com/hoseokna-ims/release-flow-sandbox/commit/75425fd14710208a31724b8a697868816cb21031))


## [0.7.0] - 2026-07-15

### Added
- release-notes 를 PR 유무 기반으로 자동 판별 ([5e8377e](https://github.com/hoseokna-ims/release-flow-sandbox/commit/5e8377e4a35887512d5518c142683502e86803db))
- CHANGELOG 커밋 해시에 GitHub 커밋 링크 추가 ([f4ed2cc](https://github.com/hoseokna-ims/release-flow-sandbox/commit/f4ed2cc1865b06626616d9000fef4d84e171934e))


## [0.6.0] - 2026-07-15


## [0.5.0] - 2026-07-15

### Fixed
- 버전 bump 를 npm version → node 스크립트로 교체 (npm 경고 제거) (b8d04f5)


## [0.4.0] - 2026-07-15

### Fixed
- 메인 페이지 h1 문구 변경 (핫픽스 데모) (98648c4)


## [0.3.0] - 2026-07-15

### Added
- version-info 모듈 추가 (d7686f2)

### Fixed
- release/hotfix 가 신규 CHANGELOG.md 를 커밋하도록 수정 (622a10d)

