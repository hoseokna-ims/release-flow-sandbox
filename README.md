# Release Flow Sandbox

브랜치 전략·버전 자동화·배포 가드까지 릴리스 전 과정을 실제 서비스 영향 없이 연습하기 위한 샌드박스 프로젝트입니다. [Next.js](https://nextjs.org) 기반으로 구성되어 있습니다.

## 배포 명령어

git-flow 기반으로 스테이징/운영 배포를 자동화합니다. 버전은 `package.json` 단일 소스이며 **patch 값**으로 채널을 구분합니다.

- `patch != 0` → **스테이징** (예: `0.18.1`, `0.18.2` …)
- `patch == 0` → **운영** (예: `0.18.0`, `1.0.0`)

### 스테이징 배포

릴리스 라인별 통합 브랜치 `staging/<major>.<minor>`(예: `staging/0.20`)에 여러 작업 브랜치를 모아 반복 배포합니다. 이름은 develop 마이너 라인과 일치하고, 그 위 배포는 `0.20.1`, `0.20.2` … 로 올라갑니다.

```
// 1) 라인 브랜치 생성 (릴리스 라인당 1회, 아무 위치에서나)
//    origin/develop 마이너 버전으로 staging/<major>.<minor> 생성 + 이전 미출시 브랜치(carry-over) 안내
yarn staging:new

// 2) 작업 브랜치 반영 + 배포 (주력) — 브랜치명을 인자로, 여러 개 한 번에 가능
//    최신 staging 에 --no-ff 머지 → patch +1 → push → 배포 트리거
yarn staging:merge feature/FE-XXXX [feature/FE-YYYY ...]
//    인자 없이 실행하면 현재 브랜치를 머지 (feature/fix/hotfix 작업 브랜치에서만)
yarn staging:merge

// 3) 폴백 — 머지 충돌을 직접 해결·커밋했거나 수동 머지 후 마무리 배포할 때
yarn staging:deploy
```

> **스테이징 changelog**: staging 배포(`staging:merge`/`staging:deploy`)마다 `STAGING_CHANGELOG.md`
> 를 라인 스냅샷으로 **전체 재생성**합니다(브랜치별 그룹, 배포용 chore 커밋 제외). 이 파일은
> **staging 브랜치 전용**이라 master/develop 에는 반영되지 않고 라인과 함께 폐기됩니다 — 현재
> 라인에 뭐가 들어있는지 QA 가 보기 위한 용도입니다. 운영 이력은 `CHANGELOG.md` 가 담당합니다.

### 운영 배포 (release / hotfix)

실수 배포 방지를 위해 **원샷 실행은 없으며** 반드시 `start` → `finish` 2단계로 진행합니다.
`finish` 가 bump + CHANGELOG + master/develop 머지 + 태그 + push(배포 트리거)를 처리합니다.

```
// 정규 릴리스 (develop 기준) — 기본 minor, major 선택 가능
yarn release start [minor|major]
//   (선택) 막판 안정화 작업·커밋
yarn release finish

// 핫픽스 (master 기준) — patch 는 스테이징 전용이므로 핫픽스도 minor 로 올림
yarn hotfix start [minor|major]
//   버그 수정 작업·커밋 (또는 브랜치 --no-ff 머지)
yarn hotfix finish
```

> **finish 후 staging 자동 리프레시**: `release finish`·`hotfix finish` 는 운영 push 성공 뒤
> 새 라인 `staging/<major>.<minor>` 를 develop 기준으로 만들고, **carry-over**(이전 staging 엔
> 머지됐지만 아직 develop 에 없는 작업 브랜치)를 자동 머지한 뒤 배포(patch +1)까지 진행합니다.
> — 이 단계는 best-effort 라 실패해도 릴리스는 그대로 완료되며, carry-over 머지 충돌 시엔
> origin 에 빈 라인만 만들고 `yarn staging:merge` 로 수동 마무리하도록 안내합니다.

> 최초 클론 시 `yarn install`(postinstall)이 버전 병합 드라이버·ff 정책·git-flow init 을 자동 등록합니다.
> git-flow 는 avh 에디션을 권장합니다: `brew install git-flow-avh`

## Getting Started

First, run the development server:

```bash
npm run dev
# or
yarn dev
# or
pnpm dev
# or
bun dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

You can start editing the page by modifying `app/page.tsx`. The page auto-updates as you edit the file.

This project uses [`next/font`](https://nextjs.org/docs/app/building-your-application/optimizing/fonts) to automatically optimize and load [Geist](https://vercel.com/font), a new font family for Vercel.

## Learn More

To learn more about Next.js, take a look at the following resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.

You can check out [the Next.js GitHub repository](https://github.com/vercel/next.js) - your feedback and contributions are welcome!

## Deploy on Vercel

The easiest way to deploy your Next.js app is to use the [Vercel Platform](https://vercel.com/new?utm_medium=default-template&filter=next.js&utm_source=create-next-app&utm_campaign=create-next-app-readme) from the creators of Next.js.

Check out our [Next.js deployment documentation](https://nextjs.org/docs/app/building-your-application/deploying) for more details.
