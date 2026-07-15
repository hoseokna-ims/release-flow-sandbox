/**
 * CHANGELOG.md 에 새 버전 섹션을 맨 위에 prepend 한다. 커밋을 "소스 브랜치별"로 그룹핑.
 *
 * 브랜치 귀속: feature/hotfix/fix 머지 커밋의 ^1..^2(도입 커밋)를 그 브랜치에 매핑.
 *   - 머지는 오래된 것부터(--reverse) 순회 + first-wins → 중첩 머지 시 안쪽(구체) 브랜치 우선.
 *   - 브랜치명은 머지 메시지에서 추출(브랜치 삭제와 무관).
 *   - 어느 머지에도 안 잡힌 직접 커밋(예: hotfix 직접 커밋)은 현재 브랜치로 귀속.
 * 커밋 해시는 GitHub 커밋 URL 로 링크(origin 에서 repo URL 도출).
 *
 * 사용법: node scripts/changelog.mjs <version>
 */
import { execSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';

const version = process.argv[2];
if (!version) {
  process.stderr.write('사용법: node scripts/changelog.mjs <version>\n');
  process.exit(1);
}

const runGit = (cmd) => execSync(cmd, { encoding: 'utf8' }).trim();
const gitLines = (cmd) => {
  const out = runGit(cmd);
  return out ? out.split('\n') : [];
};

/** 직전 semver 태그 → 범위 */
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

/** 범위 내 커밋(머지 제외, 최신순)을 conventional prefix 로 필터 후 브랜치별 그룹 */
const CONVENTIONAL = /^(feat|fix|refactor|perf|style|chore|docs|test|build)(\(|:| )/i;
const groups = new Map(); // 브랜치 → 라인 배열 (첫 등장 순서 유지)
for (const line of gitLines(`git log ${range} --no-merges --pretty=%H%x1f%h%x1f%s`)) {
  const [full, short, subject] = line.split('\x1f');
  if (!CONVENTIONAL.test(subject || '')) continue;
  const branch = branchOfCommit.get(full) || currentBranch;
  const link = repoUrl ? `([${short}](${repoUrl}/commit/${full}))` : `(${short})`;
  if (!groups.has(branch)) groups.set(branch, []);
  groups.get(branch).push(`- ${subject} ${link}`);
}

const today = new Date().toISOString().slice(0, 10);
let section = `## [${version}] - ${today}\n\n`;
for (const [branch, lines] of groups) {
  section += `### ${branch}\n${lines.join('\n')}\n\n`;
}

const FILE = 'CHANGELOG.md';
let content;
if (existsSync(FILE)) {
  const current = readFileSync(FILE, 'utf8');
  if (/^#\s/.test(current)) {
    const nl = current.indexOf('\n');
    const header = current.slice(0, nl);
    const rest = current.slice(nl + 1).replace(/^\n+/, '');
    content = `${header}\n\n${section}${rest}`;
  } else {
    content = `# Changelog\n\n${section}${current}`;
  }
} else {
  content = `# Changelog\n\n${section}`;
}
writeFileSync(FILE, content);
process.stdout.write(`  CHANGELOG.md 갱신 (${version}, 범위 ${range}, 브랜치별 그룹)\n`);
