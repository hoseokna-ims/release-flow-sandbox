# Contributing

릴리스 플로우 샌드박스 기여 가이드입니다. 이 저장소는 버전/배포 자동화를 운영 프로젝트에 반영하기 전 검증하는 공간입니다.

## 브랜치 전략

- git-flow(avh) 기반: `feature/*`, `fix/*`, `hotfix/*`
- 작업 브랜치는 최신 `develop` 기준으로 생성합니다.

## 커밋 메시지

- 형식: `prefix: 한 줄 요약` (`feat`/`fix`/`refactor`/`style`/`chore`/`docs`/`test`)
- 본문에 무엇을/왜를 불릿으로 서술하고, 푸터에 `- refs: <TICKET>` 을 남깁니다.

## 릴리스/배포

- 스테이징: `yarn staging:new` → `yarn staging:merge <branch> [branch ...]` → `yarn staging:deploy`
- 운영: `yarn release start|finish`, `yarn hotfix start|finish`

자세한 버전·배포 정책은 운영 저장소의 `docs/versioning-policy.md` 를 참고하세요.
