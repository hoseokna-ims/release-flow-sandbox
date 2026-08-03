# 릴리스 플로우 검증 하네스

`release`·`hotfix`·`staging` 스크립트가 **의도대로 막고, 의도대로 복구되는지**를 확인하는 통합 테스트입니다.
릴리스 스크립트를 건드렸다면 머지 전에 돌리세요.

```bash
yarn test:release-flow                 # 전체 (93건, 약 1~2분)
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

## 구성

| 파일 | 검사 | 내용 |
|---|---|---|
| `ahead-policy.sh` | 33 | behind/diverged/ahead 차단 · 차단 시 무변경 · 우회 상태 오인 방지 · 재실행 예외 · 정상 플로우 회귀 |
| `interrupt.sh` | 34 | 단계 경계 4곳에서 `kill -9` · push 실패 레이스 · 롤백 후 재실행 |
| `dx.sh` | 26 | 자동 이어받기 · Phase 1 산출물 재생성 · 오작동 방지 4종 |
| `guards.sh` | 8 | pre-push 태그 동반 검사 · 이식성(bash 전용 스크립트를 `sh` 로 호출 금지, `dash -n`) |
| `lib/harness.sh` | — | 픽스처·git 셔임·단언 헬퍼 |
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
