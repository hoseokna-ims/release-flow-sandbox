# Changelog

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

