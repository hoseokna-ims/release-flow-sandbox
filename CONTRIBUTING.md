# Contributing

릴리스 플로우 샌드박스 기여 가이드입니다. 이 저장소는 버전/배포 자동화를 운영 프로젝트에 반영하기 전 검증하는 공간입니다.

## 브랜치 전략

git-flow 브랜칭 모델을 따릅니다. **도구(`git-flow`) 설치는 필요하지 않습니다** — 릴리스 스크립트가 머지·태그·브랜치 정리를 직접 수행합니다.

| 접두사 | 용도 | 만드는 방법 |
|---|---|---|
| `feature/*` | 기능 작업 | 최신 `develop` 기준으로 직접 생성 |
| `fix/*` | 버그 수정 작업 | 최신 `develop` 기준으로 직접 생성 |
| `release/X.Y.0` | 정규 릴리스 | **`yarn release start`** 가 생성 |
| `hotfix/X.Y.0` | 운영 핫픽스 | **`yarn hotfix start`** 가 생성 |
| `staging/<major>.<minor>` | 스테이징 통합 라인 | `yarn staging:new` 가 생성 |

### ⚠️ `release/`·`hotfix/` 접두사는 릴리스 전용입니다

**작업 브랜치에 `hotfix/` 를 쓰지 마세요. `fix/` 를 사용하세요.**

`hotfix/FE-1234` 같은 브랜치가 로컬에 있으면 `yarn hotfix start` 가 차단됩니다 — 릴리스는 한 번에 하나만 진행하기 때문입니다. 더 위험한 것은, 그 브랜치를 릴리스로 오인해 `finish` 를 실행하면 **작업 브랜치가 master 에 머지되고 태그까지 생성**된다는 점입니다.

이미 만들어 둔 브랜치가 있다면 이름을 바꾸세요:

```bash
git branch -m hotfix/FE-1234 fix/FE-1234
```

## 커밋 메시지

- 형식: `prefix: 한 줄 요약` (`feat`/`fix`/`refactor`/`style`/`chore`/`docs`/`test`)
- 본문에 무엇을/왜를 불릿으로 서술하고, 푸터에 `- refs: <TICKET>` 을 남깁니다.
- **changelog 는 conventional prefix 가 붙은 커밋만 수집합니다.** prefix 를 빠뜨리면 릴리스 노트에서 통째로 누락됩니다.
- `chore: release X.Y.Z` / `chore: hotfix X.Y.Z` / `chore: staging deploy X.Y.Z` 는 스크립트가 만드는 배포 커밋이며 changelog 에서 자동 제외됩니다. 사람이 직접 이 형식으로 커밋하지 마세요.

## 릴리스/배포

```
스테이징   yarn staging:new  →  yarn staging:merge <branch> [branch ...]  →  yarn staging:deploy
운영       yarn release start [minor|major]  →  yarn release finish
           yarn hotfix  start [minor|major]  →  yarn hotfix  finish
```

버전은 `package.json` 단일 소스이며 **patch 값으로 채널을 구분**합니다 — `patch != 0` 은 스테이징, `patch == 0` 은 운영입니다.

### 스크립트를 우회하지 마세요

`git flow` 직접 호출, 수동 머지·태그로 운영 배포를 진행하면 **bump·changelog·태그가 생성되지 않습니다.** 실제로 이 경로로 같은 버전이 재배포된 사고가 있었습니다.

`pre-push` 훅과 `prod.yaml` 이 "master 로 나가는 커밋은 자기 `package.json` version 과 같은 이름의 태그가 자신을 가리켜야 한다"를 검사해 우회를 차단합니다. 정상 플로우(`yarn release/hotfix finish`)는 master·develop·태그를 `--atomic` 으로 함께 push 하므로 통과합니다.

### 실패했을 때

모든 실패 메시지에는 원인과 **다음에 실행할 명령**이 함께 나옵니다. 그대로 따르면 됩니다.

`finish` 는 어느 단계에서 실패하든 시작 상태로 되돌립니다. push 가 거부돼도 브랜치·태그가 그대로 복원되므로 **원인을 고치고 같은 명령을 다시 실행**하면 됩니다. 손으로 수습하지 마세요.

### 자주 만나는 상황

| 메시지 | 뜻 | 대응 |
|---|---|---|
| `push 안 된 로컬 커밋 N개` (develop) | develop 의 미푸시 커밋이 리뷰·CI 없이 릴리스에 실려 나감 | `git switch develop && git push` 로 먼저 올리고 재실행 |
| `push 안 된 로컬 커밋 N개` (master) | 릴리스 스크립트 밖에서 master 를 건드린 흔적 (미푸시 master 커밋 = 운영 배포) | 진행 중인 릴리스가 있으면 그 브랜치에서 `finish`, 잔재로 확인되면 `git reset --hard origin/master`. **master 를 직접 push 하지 말 것** |
| `중단된 finish 의 재실행으로 보입니다` | 머지·태그까지 끝나고 push 전에 죽은 상태 | 목록을 확인하고 맞으면 `y` — 이어서 마무리됩니다 |
| `origin 과 갈라졌습니다` | 로컬·원격이 diverged | `git pull --rebase` (맨 `git pull` 은 `pull.ff=only` 로 실패) |
| `선행 라인입니다` | staging 라인 번호가 develop 보다 앞서 staging 명령이 잠김 | 안내된 `git push origin --delete staging/X.Y` |
| `push 안 된 로컬 커밋 N개` (staging/*) | 스테이징 스크립트 밖에서 `staging/*` 에 직접 커밋한 흔적 — 리뷰·CI 없이 스테이징에 배포됨 | 필요한 작업이면 작업 브랜치로 옮겨 push 후 `yarn staging:merge`, 잔재면 안내된 `git reset --hard origin/staging/X.Y` |
| `중단된 스테이징 배포의 재실행으로 보입니다` | 앞선 `staging:merge`/`staging:deploy` 가 push 전에 죽어 미푸시 커밋이 남음 | 목록을 확인하고 맞으면 `y` — 이어서 마무리됩니다 |
| `staging/X.Y 가 origin 보다 N 커밋 뒤처졌습니다` | `staging:deploy` 는 pull 하지 않으므로 이대로면 push 가 거부됨 | 안내된 `git pull` 후 재실행 (`staging:merge` 는 스스로 pull 하므로 이 메시지가 없습니다) |
| `hotfix/* 브랜치에서 실행하세요` | 다른 브랜치에서 finish 를 실행함 | 안내된 `git switch hotfix/X.Y.0` |
| `중단된 finish 를 발견했습니다` | 앞선 finish 가 강제 종료돼 이어받을 브랜치가 있음 | 자동으로 전환해 이어갑니다 — 그대로 두면 됩니다 |
| `중단된 준비 단계의 산출물이 남아 있습니다` | 앞선 finish 가 bump·changelog 를 만들다 죽음 | 다시 생성해 이어갑니다 — stash 하지 않아도 됩니다 |
| `master 가 다른 worktree 에 체크아웃돼 있습니다` | 릴리스는 master·develop 로 전환해야 하는데 다른 worktree 가 잡고 있음 | 안내된 `git -C <경로> switch --detach` 후 재실행 |
| `태그 X 가 이번 push 에 포함되지 않았습니다` | master 만 push 하려 함 — 원격에 태그가 없으면 배포가 트리거되지 않음 | `yarn release/hotfix finish` 로 진행. 이미 로컬 머지·태그까지 끝났다면 안내된 `git push --atomic origin master develop X` |

## 로컬 세팅

`yarn install` (postinstall) 이 자동으로 등록합니다:

- `package.json` version 충돌을 큰 값으로 해소하는 merge driver
- `merge.ff false` — 머지커밋 보존 (changelog 브랜치 귀속·carry-over 판별이 여기에 의존)
- `pull.ff only` — 의도치 않은 머지커밋 방지

자세한 버전·배포 정책은 운영 저장소의 `docs/versioning-policy.md`, 스크립트 설계 배경은 `docs/release-flow-hardening.md` 를 참고하세요.
