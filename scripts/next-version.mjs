/**
 * 다음 릴리스 버전 계산.
 * 기준 = max(모든 semver 태그, package.json version) → type(minor|major)만큼 bump.
 * package.json 이 태그보다 뒤처진 드리프트 상황에서도 안전하게 다음 버전을 고른다.
 *
 * 사용법: node scripts/next-version.mjs <minor|major>
 * 출력: 다음 버전 문자열 (예: 0.36.0)
 */
import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const type = process.argv[2] || 'minor';
if (type !== 'minor' && type !== 'major') {
  process.stderr.write('사용법: node scripts/next-version.mjs <minor|major>\n');
  process.exit(1);
}

/** "v1.2.3" | "1.2.3" → [1,2,3] | null */
const parseSemver = (value) => {
  const matched = /(\d+)\.(\d+)\.(\d+)/.exec(String(value ?? '').trim());
  return matched ? [+matched[1], +matched[2], +matched[3]] : null;
};
const compareSemver = (a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2];

const packageVersion = parseSemver(JSON.parse(readFileSync('./package.json', 'utf8')).version);

let tagVersions = [];
try {
  tagVersions = execSync('git tag --list', { encoding: 'utf8' })
    .split('\n')
    .map(parseSemver)
    .filter(Boolean);
} catch {
  /** 태그 조회 실패 시 package.json 만으로 계산 */
}

const candidates = [packageVersion, ...tagVersions].filter(Boolean).sort(compareSemver);
const base = candidates[candidates.length - 1] ?? [0, 0, 0];

const [a, b] = base;
const next = type === 'major' ? [a + 1, 0, 0] : [a, b + 1, 0];
process.stdout.write(next.join('.'));
