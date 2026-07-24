/**
 * 커밋을 "소스 브랜치별"로 그룹핑해 changelog 를 생성한다. 두 가지 모드:
 *
 *  - 운영(기본): CHANGELOG.md 맨 위에 `## [version]` 섹션을 prepend (누적).
 *      node scripts/changelog.mjs <version>
 *  - 스테이징(--staging): STAGING_CHANGELOG.md 를 매번 전체 재생성 (라인 스냅샷, 누적 아님).
 *      node scripts/changelog.mjs <version> --staging
 *      · staging 브랜치 전용 파일 — master/develop 에 반영되지 않는다(라인과 함께 폐기).
 *      · "chore: staging deploy/release/hotfix" 같은 배포용 노이즈 커밋은 제외.
 *
 * 브랜치 귀속: feature/hotfix/fix 머지 커밋의 ^1..^2(도입 커밋)를 그 브랜치에 매핑.
 *   - 머지는 오래된 것부터(--reverse) 순회 + first-wins → 중첩 머지 시 안쪽(구체) 브랜치 우선.
 *   - 브랜치명은 머지 메시지에서 추출(브랜치 삭제와 무관).
 *   - 어느 머지에도 안 잡힌 직접 커밋은 현재 브랜치로 귀속.
 * 커밋 해시는 GitHub 커밋 URL 로 링크(origin 에서 repo URL 도출). 범위 = 직전 semver 태그..HEAD.
 */
import { execSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';

const args = process.argv.slice(2);
const isStaging = args.includes('--staging');
const version = args.find((a) => !a.startsWith('--'));
if (!version) {
  process.stderr.write('사용법: node scripts/changelog.mjs <version> [--staging]\n');
  process.exit(1);
}

const runGit = (cmd) => execSync(cmd, { encoding: 'utf8' }).trim();
const gitLines = (cmd) => {
  const out = runGit(cmd);
  return out ? out.split('\n') : [];
};

/** 직전 semver 태그 → 범위 (스테이징은 이 라인이 올라앉은 릴리스 기준점이 된다) */
const parseSemver = (v) => v.replace(/^v/, '').split('.').map(Number);
const semverTags = gitLines('git tag --list')
  .map((t) => t.trim())
  .filter((t) => /^v?\d+\.\d+\.\d+$/.test(t))
  .sort((a, b) => {
    const A = parseSemver(a);
    const B = parseSemver(b);
    return B[0] - A[0] || B[1] - A[1] || B[2] - A[2];
  });
const prevTag = semverTags[0] || '';
const range = prevTag ? `${prevTag}..HEAD` : 'HEAD';

/** origin → https repo URL (없으면 링크 없이 해시만) */
let repoUrl = '';
try {
  repoUrl = runGit('git remote get-url origin')
    .replace(/^git@github\.com:/, 'https://github.com/')
    .replace(/^https:\/\/[^@]*@/, 'https://')
    .replace(/\.git$/, '');
} catch {
  repoUrl = '';
}

/** 커밋 → 브랜치 귀속 맵 (feature/hotfix/fix 머지의 ^1..^2, 안쪽 우선) */
const branchOfCommit = new Map();
for (const line of gitLines(`git log ${range} --merges --reverse --pretty=%H%x1f%s`)) {
  const [mergeSha, subject] = line.split('\x1f');
  const matched = /(feature|hotfix|fix)\/[A-Za-z0-9._/-]+/.exec(subject || '');
  if (!matched) continue;
  const branch = matched[0];
  let introduced = [];
  try {
    introduced = gitLines(`git rev-list ${mergeSha}^1..${mergeSha}^2 --no-merges`);
  } catch {
    introduced = [];
  }
  for (const sha of introduced) {
    if (!branchOfCommit.has(sha)) branchOfCommit.set(sha, branch);
  }
}

const currentBranch = runGit('git rev-parse --abbrev-ref HEAD');

/**
 * 범위 내 커밋(머지 제외, 최신순)을 conventional prefix 로 필터 후 브랜치별 그룹.
 * 선행 [태그] 접두사(예: "[feature/x] fix: ...")를 허용 — 일부 브랜치는 커밋 제목 앞에
 * [브랜치명] 을 붙이는데, 이게 없으면 conventional 커밋이 통째로 누락된다(핫픽스 changelog 빈 섹션 사고).
 */
const TAG_PREFIX = /^\[[^\]]*\]\s*/;
const CONVENTIONAL = /^(\[[^\]]*\]\s*)?(feat|fix|refactor|perf|style|chore|docs|test|build)(\(|:| )/i;
/**
 * 배포용 자동 bump 커밋만 제외 — "chore: <release|hotfix|staging deploy> <버전>" 형태(버전번호 동반 시에만).
 * 버전번호를 요구해 기계 생성 bump 만 정확히 잡는다. 일반 chore 작업(예: "chore: eslint 규칙 추가",
 * "chore: release notes 작성")은 changelog 에 그대로 포함된다.
 */
const DEPLOY_NOISE = /^chore:\s*(staging deploy|release|hotfix)\s+v?\d+\.\d+\.\d+\b/i;
const groups = new Map(); // 브랜치 → 라인 배열 (첫 등장 순서 유지)
for (const line of gitLines(`git log ${range} --no-merges --pretty=%H%x1f%h%x1f%s`)) {
  const [full, short, subject] = line.split('\x1f');
  if (!CONVENTIONAL.test(subject || '')) continue;
  // 선행 [태그] 는 제거 — 브랜치별 헤딩(### feature/x)과 중복이라 본문에선 뺀다.
  const cleaned = (subject || '').replace(TAG_PREFIX, '');
  if (DEPLOY_NOISE.test(cleaned)) continue;
  const branch = branchOfCommit.get(full) || currentBranch;
  const link = repoUrl ? `([${short}](${repoUrl}/commit/${full}))` : `(${short})`;
  if (!groups.has(branch)) groups.set(branch, []);
  groups.get(branch).push(`- ${cleaned} ${link}`);
}

/**
 * 안전망: 머지로 잡힌 브랜치인데 항목이 하나도 안 남으면 경고(조용한 누락 방지).
 * allowlist 특성상 예상 못한 커밋 제목 형식은 통째로 사라질 수 있어, 0.40.0 류 사고를 조기 감지한다.
 */
const mergedBranches = new Set(branchOfCommit.values());
const emptyBranches = [...mergedBranches].filter((branch) => !groups.has(branch));
if (emptyBranches.length) {
  process.stderr.write(
    `⚠️  changelog: 머지됐지만 changelog 항목이 0개인 브랜치가 있습니다 ` +
      `(커밋 제목이 conventional 형식인지 확인하세요): ${emptyBranches.join(', ')}\n`,
  );
}

const today = new Date().toISOString().slice(0, 10);
const renderGroups = () => {
  let body = '';
  for (const [branch, lines] of groups) {
    body += `### ${branch}\n${lines.join('\n')}\n\n`;
  }
  return body;
};

if (isStaging) {
  /** 스테이징: 라인 스냅샷을 매번 전체 재생성 (누적 아님) */
  const groupsBody = groups.size ? renderGroups() : '_(이 라인에 반영된 변경 없음)_\n\n';
  const content =
    `# Staging Changelog\n\n` +
    `> ${currentBranch} 전용 — 배포마다 재생성되며 master/develop 에는 반영되지 않습니다.\n\n` +
    `## ${currentBranch} · ${version} — ${today}\n\n` +
    groupsBody;
  writeFileSync('STAGING_CHANGELOG.md', content);
  process.stdout.write(`  STAGING_CHANGELOG.md 재생성 (${version}, 범위 ${range}, 브랜치별 그룹)\n`);
} else {
  /** 운영: CHANGELOG.md 맨 위에 섹션 prepend (누적) */
  const section = `## [${version}] - ${today}\n\n${renderGroups()}`;
  const FILE = 'CHANGELOG.md';
  let content;
  if (existsSync(FILE)) {
    const current = readFileSync(FILE, 'utf8');
    if (/^#\s/.test(current)) {
      const nl = current.indexOf('\n');
      const header = nl !== -1 ? current.slice(0, nl) : current;
      const rest = nl !== -1 ? current.slice(nl + 1).replace(/^\n+/, '') : '';
      content = `${header}\n\n${section}${rest}`;
    } else {
      content = `# Changelog\n\n${section}${current}`;
    }
  } else {
    content = `# Changelog\n\n${section}`;
  }
  writeFileSync(FILE, content);
  process.stdout.write(`  CHANGELOG.md 갱신 (${version}, 범위 ${range}, 브랜치별 그룹)\n`);
}
