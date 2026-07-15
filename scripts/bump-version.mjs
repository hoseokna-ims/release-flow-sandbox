/**
 * package.json (및 있으면 package-lock.json) 의 version 을 bump 한다. 순수 node — npm 미사용.
 * (yarn 하위에서 `npm version` 을 부를 때 뜨는 "Unknown env config" 경고 제거 + PM 무관)
 *
 * 사용법: node scripts/bump-version.mjs <patch|minor|major|X.Y.Z>
 * 출력: 새 버전 문자열
 */
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const arg = process.argv[2];
if (!arg) {
  process.stderr.write('사용법: node scripts/bump-version.mjs <patch|minor|major|X.Y.Z>\n');
  process.exit(1);
}

const packageRaw = readFileSync('package.json', 'utf8');
const current = (packageRaw.match(/"version"\s*:\s*"(\d+\.\d+\.\d+)"/) || [])[1];
if (!current) {
  process.stderr.write('package.json 에서 version 을 찾지 못했습니다.\n');
  process.exit(1);
}

let nextVersion;
if (/^\d+\.\d+\.\d+$/.test(arg)) {
  nextVersion = arg;
} else {
  let [major, minor, patch] = current.split('.').map(Number);
  if (arg === 'major') { major += 1; minor = 0; patch = 0; }
  else if (arg === 'minor') { minor += 1; patch = 0; }
  else if (arg === 'patch') { patch += 1; }
  else {
    process.stderr.write(`알 수 없는 인자: ${arg}\n`);
    process.exit(1);
  }
  nextVersion = `${major}.${minor}.${patch}`;
}

/** package.json: version 줄만 교체(포맷·들여쓰기 보존) */
writeFileSync(
  'package.json',
  packageRaw.replace(/("version"\s*:\s*")\d+\.\d+\.\d+(")/, `$1${nextVersion}$2`),
);

/** package-lock.json 있으면 동기화 (npm 생성 파일이라 2-space JSON 재직렬화 허용) */
if (existsSync('package-lock.json')) {
  const lock = JSON.parse(readFileSync('package-lock.json', 'utf8'));
  lock.version = nextVersion;
  if (lock.packages && lock.packages['']) lock.packages[''].version = nextVersion;
  writeFileSync('package-lock.json', `${JSON.stringify(lock, null, 2)}\n`);
}

process.stdout.write(nextVersion);
