import Image from "next/image";
import { APP_VERSION, getReleaseStatus } from "./version-info";

export default function Home() {
  return (
    <div className="flex flex-col flex-1 items-center justify-center bg-zinc-50 font-sans dark:bg-black">
      <main className="flex flex-1 w-full max-w-3xl flex-col items-center justify-between py-32 px-16 bg-white dark:bg-black sm:items-start">
        <Image
          className="dark:invert"
          src="/next.svg"
          alt="Next.js logo"
          width={100}
          height={20}
          priority
        />
        <span className="inline-flex items-center gap-1.5 rounded-full border border-black/[.08] bg-black/[.03] px-3 py-1 text-sm font-medium text-zinc-600 dark:border-white/[.145] dark:bg-white/[.06] dark:text-zinc-400">
          <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
          현재 버전 v{APP_VERSION} · {getReleaseStatus()}
        </span>
        <div className="flex flex-col items-center gap-6 text-center sm:items-start sm:text-left">
          <h1 className="max-w-md text-3xl font-semibold leading-10 tracking-tight text-black dark:text-zinc-50">
            릴리스 플로우 샌드박스
          </h1>
          <p className="max-w-md text-lg leading-8 text-zinc-600 dark:text-zinc-400">
            브랜치 전략과 버전 자동화, 배포 가드까지 릴리스 전 과정을 안전하게
            연습하는 공간입니다. 실제 서비스에 영향 없이 흐름을 검증하세요.
          </p>
        </div>
        <div className="flex flex-col gap-4 text-base font-medium sm:flex-row">
          <a
            className="flex h-12 w-full items-center justify-center gap-2 rounded-full bg-foreground px-5 text-background transition-colors hover:bg-[#383838] dark:hover:bg-[#ccc] md:w-[180px]"
            href="https://github.com/hoseokna-ims/release-flow-sandbox/actions"
            target="_blank"
            rel="noopener noreferrer"
          >
            <Image
              className="dark:invert"
              src="/vercel.svg"
              alt=""
              width={16}
              height={16}
            />
            릴리스 파이프라인 열기
          </a>
          <a
            className="flex h-12 w-full items-center justify-center rounded-full border border-solid border-black/[.08] px-5 transition-colors hover:border-transparent hover:bg-black/[.04] dark:border-white/[.145] dark:hover:bg-[#1a1a1a] md:w-[180px]"
            href="https://github.com/hoseokna-ims/release-flow-sandbox/blob/develop/CHANGELOG.md"
            target="_blank"
            rel="noopener noreferrer"
          >
            릴리스 노트
          </a>
        </div>
        <footer className="mt-8 w-full border-t border-black/[.06] pt-6 text-sm text-zinc-500 dark:border-white/[.1] dark:text-zinc-500">
          <p>
            이 환경은 실제 배포에 영향을 주지 않는 릴리스 연습용 샌드박스입니다.
          </p>
          <p className="mt-1">© 2026 IMS Mobility · Release Flow Sandbox</p>
        </footer>
      </main>
    </div>
  );
}
