# 릴리스 플로우 검증 하네스

`release`·`hotfix`·`staging` 스크립트가 **의도대로 막고, 의도대로 복구되는지**를 확인하는 통합 테스트입니다.
릴리스 스크립트를 건드렸다면 머지 전에 돌리세요.

```bash
yarn test:release-flow                 # 전체 (242건, 약 1~2분)
bash scripts/test/ahead-policy.sh      # 하나만
```

## 다른 리포 검증

이식이 제대로 됐는지 확인할 때 씁니다. `SRC` 에 그 리포 루트를 주면 **그쪽 스크립트**로 전 케이스를 돌립니다.

```bash
SRC=/path/to/imsform-mobile-web yarn test:release-flow
```

## 격리 방식

케이스마다 **로컬 bare 리포를 origin 으로 만들고 그 클론에서만** 스크립트를 실행합니다.
실제 리포·실제 원격은 건드리지 않습니다. 작업물은 `$TMPDIR/release-flow-test/` 아래에 남으므로
실패한 케이스는 그 디렉터리에 들어가 직접 확인할 수 있습니다.

기본 픽스처: `master`(0.1.0, 태그 `0.1.0`) → `develop` 에 커밋 1개.
`fixture <이름> release|hotfix` 로 토픽 브랜치 start 까지 만들어 둘 수 있습니다.
스테이징 경로는 `fixture_staging <이름> [작업브랜치]` — `staging/0.1` 과 미머지 작업 브랜치까지
만들어 둡니다(`merge-staging.sh` 의 라인 불일치 가드가 develop 라인과의 일치를 요구하므로 `0.1` 고정).

픽스처의 `pre-push` 에는 실제 리포의 `yarn tsc`·`yarn test` 자리를 대신하는 **모의 콘텐츠 검사**가
들어 있습니다. `prepush_fail_on` / `prepush_fail_off` 로 켜고 끄며(마커 파일 `.prepush-fail`),
꺼져 있으면 아무 일도 하지 않습니다.

## 구성

| 파일 | 검사 | 내용 |
|---|---|---|
| `ahead-policy.sh` | 33 | behind/diverged/ahead 차단 · 차단 시 무변경 · 우회 상태 오인 방지 · 재실행 예외 · 정상 플로우 회귀 |
| `interrupt.sh` | 34 | 단계 경계 4곳에서 `kill -9` · push 실패 레이스 · 롤백 후 재실행 |
| `dx.sh` | 30 | 자동 이어받기 · Phase 1 산출물 재생성 · 오작동 방지 4종 |
| `guards.sh` | 17 | pre-push 태그 동반·계보 검사 · worktree 점유 차단 · `topic_merge_and_tag` checkout 실패 처리 · 이식성(`sh` 호출 금지, `dash -n`) |
| `staging-rollback.sh` | 68 | 스테이징 경로 롤백 · push 실패 원인 3분기 · 중단 후 재개 · 롤백하면 안 되는 두 경로 |
| `staging-ahead.sh` | 60 | 로컬 `staging/*` ahead·diverged 차단 · 재실행 예외 3조건 · behind 정책 · 새 클론 회귀 |
| `lib/harness.sh` | — | 픽스처·git 셔임·단언 헬퍼(`fixture_staging`, `expect_ver`, `ver_of` …) |
| `run-all.sh` | — | 전체 실행 + 합계 |

`guards.sh` G5 는 `dash` 가 설치돼 있을 때만 돕니다(없으면 건너뛰고 합계가 1 줄어듭니다).
macOS 는 `/bin/sh` 가 bash 라 POSIX 위반이 로컬에서 드러나지 않으므로, `brew install dash` 를 권합니다.

## 중단·레이스를 재현하는 방법

`PATH` 앞에 `git` 셔임을 놓고 환경변수로 제어합니다.

```bash
# 특정 git 호출 '직전'에 부모 프로세스를 kill -9 (트랩·롤백이 전혀 안 도는 최악의 중단)
KILL_ON='tag -a -m 0.2.0 0.2.0' bash scripts/release.sh finish

# 특정 git 호출 '직전'에 다른 명령을 한 번 실행 (원격이 앞서가는 레이스)
RACE_ON='push --atomic origin master develop 0.2.0' \
RACE_MARK=/tmp/raced RACE_CMD='cd /path/to/other && git push origin master' \
  bash scripts/release.sh finish
```

## 하네스를 고칠 때 걸렸던 함정

같은 실수를 반복하지 않도록 기록해 둡니다. 대부분 **테스트가 조용히 통과해버리는** 종류입니다.

1. **`grep -qv` 로 부재를 검사하지 말 것.** 여러 줄 입력에서 "한 줄이라도 일치하지 않으면 참"이라
   사실상 항상 통과합니다. `expect_absent` 처럼 `! grep -q` 로 쓰세요. (실제로 이 버그로
   "자동 전환하지 않음" 단언 3건이 무의미하게 통과하고 있었습니다.)
2. **`awk` 로 파일 앞부분을 잘라낼 때 1행 액션에서 플래그를 세우지 말 것.**
   `NR==1 || f || /^ZERO=/{f=1; print}` 는 1행에서 `f=1` 이 되어 **전체를 출력**합니다.
   `NR==1{print; next} /^ZERO=/{f=1} f{print}` 가 맞습니다.
3. **셔임은 리포 밖에 둘 것.** 리포 안에 두면 픽스처의 `git add -A` 가 커밋해버려
   checkout 시 사라집니다.
4. **미정의 헬퍼는 `command not found` 로 조용히 넘어갑니다.** `harness_init` 이 대상 리포에
   `scripts/lib/checks.sh` 와 pre-push 가드 블록이 있는지 먼저 확인하는 이유입니다.
5. **`master == develop` 으로 시작하면 "미머지" 상태를 만들 수 없습니다.** 픽스처가 develop 에
   커밋을 하나 더 얹는 이유입니다.
6. **머지 충돌이 나면 다른 이유로 실패해 테스트가 무의미해집니다.** `dx.sh` A5 에서 두 번째
   브랜치를 develop 이 아니라 '첫 머지 이후의 master' 에서 따는 이유입니다
   (둘 다 `package.json` 을 bump 하면 충돌 → merging 중 상태).
7. **레이스는 preflight '이후'에 일어나야 합니다.** 픽스처 직후에 원격을 밀면 Phase 0 의
   fetch 에서 behind 로 먼저 막혀 정작 검사하려던 롤백 경로를 타지 못합니다.
8. **픽스처의 pre-push 는 가드 블록만 남깁니다.** 실제 리포 판은 앞에 `yarn tsc`·`yarn test` 가
   있는데 픽스처에는 `node_modules` 가 없어 실행할 수 없습니다. 가드 자체는 원본 그대로 검증됩니다.
9. **`git checkout -- <고정 목록>` 을 쓰지 말 것.** 목록 중 하나라도 리포에 없으면
   (Yarn Berry 에는 `package-lock.json` 이 없다) **전체가 실패해 아무것도 복원되지 않습니다.**
   실제로 더러운 경로만 골라 되돌리세요. 이 실수 때문에 수정이 동작하지 않는 것을 테스트가 잡았습니다.
10. **`if ! func` 로 호출하면 함수 본문 전체에서 `set -e` 가 꺼집니다.** 실패는 명시적으로
   `return 1` 해야 하고, 마지막에 사후 검증을 두는 편이 확실합니다.
11. **`ok "... $(cmd)" $?` 로 쓰지 말 것.** 인자를 왼쪽부터 확장하므로 설명 안의 명령치환이
   먼저 실행되어 `$?` 를 **자기 종료코드로 덮어씁니다** → 항상 0(통과)이 전달됩니다.
   상태를 먼저 변수로 받으세요. `head_is` 가 실제로 이 형태였고, 모든 하네스의 HEAD 단언이
   무의미하게 통과하고 있었습니다(FE-1044 에서 새 헬퍼를 쓰다 발견).
