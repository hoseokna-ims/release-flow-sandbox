/**
 * 설치 정합성 사전검사 — 로컬 node_modules 가 이 라인의 락파일과 맞는지 확인한다.
 * 읽기 전용이고 node 만 사용한다(파일 읽기 + git show 한 번).
 *
 * 사용법: node scripts/check-install-sync.mjs
 *   종료코드 0 = 통과(또는 검사 대상 아님), 1 = 불일치·미설치
 *
 * ── 왜 필요한가 ─────────────────────────────────────────────────────────
 * 2026-09 사고에서 pre-push 의 `tsc --noEmit` 이 5건 실패했는데 그중 4건은 코드 결함이
 * 아니라 로컬 설치본이 대상 라인과 다른 것이었다(설치본 react 18.3.1 / 대상 라인 react ^19
 * + next 16). 사용자는 자기 코드가 5군데 깨졌다고 읽고 그걸 고치려 든다. 어떤 스크립트도
 * 이를 확인하지 않았다.
 *
 * ── 왜 `yarn install --immutable` 이 해법이 아닌가 ───────────────────────
 * `yarn install --help` 그대로 *"Abort with an error exit code if the lockfile was to be
 * modified"* — **락파일이 바뀔 때만** 실패한다. node_modules 가 어긋나면 보고하지 않고
 * 링크 단계를 실행해 조용히 고친다(exit 0). 즉 진단하지 못하면서 배포 스크립트가 install 을
 * 시작하는 결과가 된다. `node_modules/.yarn-state.yml` 에도 락파일 체크섬이 없다.
 * Yarn 4 에 읽기 전용 정합성 판정의 1급 수단이 없어 직접 만든다.
 *
 * ── yarn 을 호출하지 않는 것이 하드 제약이다 ─────────────────────────────
 * 검증 하네스의 픽스처에는 yarn 도 `.yarnrc.yml` 의 yarnPath 도 없고 셔임은 git 하나뿐이다
 * (`scripts/test/lib/harness.sh`). 픽스처가 부를 수 있는 것은 `node` 뿐이다.
 *
 * ── 오탐을 만들지 않는다 ─────────────────────────────────────────────────
 * 이 검사는 배포 경로를 차단하므로 오탐이 곧 배포 차단이고, 그러면 사람이
 * `RELEASE_ASSUME_YES` 나 `HUSKY=0` 으로 도망간다. 그래서 **판정할 수 있는 것만 판정한다** —
 * 락파일에서 선언을 찾지 못하면(형식 변화·프로토콜 등) 그 항목은 비교하지 않고 넘긴다.
 * 불일치를 확신할 때만 차단한다.
 */
import { existsSync, readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const read = (path) => readFileSync(path, 'utf8');
const out = (text) => process.stdout.write(text);

const pkg = JSON.parse(read('package.json'));
/** dependencies + devDependencies — 선언된 것은 모두 설치돼 있어야 한다 */
const declared = { ...(pkg.dependencies || {}), ...(pkg.devDependencies || {}) };

/**
 * 라인 의존성 격차 안내 (정보성 — 차단하지 않는다).
 *
 * 현재 라인과 develop 이 서로 다른 의존성을 선언하고 있으면, develop 기준으로 검증한
 * 브랜치는 스테이징 머지 시점에 처음 그 조합을 만난다. 이때 pre-push 의 타입 검사가
 * 실패하면 원인이 자기 코드가 아닐 수 있다는 것을 알려주는 것이 목적이다.
 *
 * 차단하지 않는 이유: 두 라인이 크게 어긋난 시기에는 이 조건이 상시 성립해서(실측:
 * next 14 vs 16, react ^18 vs ^19) 확인을 걸면 매 배포가 confirm 이 되고
 * `RELEASE_ASSUME_YES` 상시화로 이어진다.
 */
function reportLineGap() {
  let developPkg;
  try {
    developPkg = JSON.parse(
      execFileSync('git', ['show', 'origin/develop:package.json'], {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore'],
      }),
    );
  } catch {
    return; // origin/develop 을 못 읽으면(얕은 클론 등) 안내를 생략한다
  }
  const developDeclared = {
    ...(developPkg.dependencies || {}),
    ...(developPkg.devDependencies || {}),
  };
  /** 양쪽이 모두 선언한 것 중 범위가 다른 항목만 — 한쪽에만 있는 것은 라인 차이가 아니다 */
  const diffs = Object.entries(declared)
    .filter(([name, range]) => developDeclared[name] && developDeclared[name] !== range)
    .map(([name, range]) => `${name} ${developDeclared[name]} → ${range}`);
  if (diffs.length === 0) return;

  const shown = diffs.slice(0, 3).join(', ');
  const rest = diffs.length > 3 ? ` 외 ${diffs.length - 3}건` : '';
  out(`ℹ️  이 라인은 develop 과 의존성 선언이 다릅니다 (${shown}${rest}).\n`);
  out('   develop 기준으로 검증한 브랜치는 여기서 처음 이 조합을 만납니다 —\n');
  out('   pre-push 의 타입 검사가 실패하면 내 코드가 아니라 라인 차이일 수 있습니다.\n');
}

/**
 * yarn.lock 을 `{ descriptor: version }` 으로 읽는다. yarn 1(classic)과 Yarn Berry(v2+)
 * 형식을 모두 다룬다 — 이 저장소는 v1, imsform-mobile-web 은 Berry v8 이다.
 *
 *   v1     `"left-pad@^1.0.0":`      →  `  version "1.3.0"`
 *   Berry  `"left-pad@npm:^1.0.0":`  →  `  version: 1.3.0`
 *
 * 항목 헤더는 들여쓰기가 없고 `:` 로 끝나는 줄이다. descriptor 가 여러 개면 쉼표로 묶이는데
 * v1 은 각각을 따옴표로 감싸고(`"a@^1", "a@^2":`) Berry 는 전체를 한 번에 감싼다
 * (`"a@npm:^1, a@npm:^2":`) — 쉼표로 나눈 뒤 각 조각의 따옴표를 벗기면 양쪽이 같아진다.
 */
function parseLockfile(text) {
  const versionOf = new Map();
  let descriptors = [];
  for (const line of text.split('\n')) {
    if (!line || line.startsWith('#')) continue;
    if (!/^\s/.test(line)) {
      descriptors = [];
      if (!line.endsWith(':')) continue;
      const header = line.slice(0, -1).trim();
      if (header === '__metadata') continue;
      descriptors = header
        .split(',')
        .map((d) => d.trim().replace(/^"/, '').replace(/"$/, ''))
        .filter(Boolean);
      continue;
    }
    if (descriptors.length === 0) continue;
    /** v1 은 `version "X"`, Berry 는 `version: X` */
    const matched = /^\s+version:?\s+"?([^"\s]+)"?\s*$/.exec(line);
    if (matched) {
      for (const descriptor of descriptors) {
        if (!versionOf.has(descriptor)) versionOf.set(descriptor, matched[1]);
      }
      descriptors = [];
    }
  }
  return versionOf;
}

reportLineGap();

/**
 * 검사 대상이 아닌 경우는 조용히 통과한다.
 *  - yarn.lock 이 없다 → 비교 기준이 없다. 이 조건이 검증 하네스의 픽스처 상태다.
 *  - .pnp.cjs 가 있다 → PnP 설치라 node_modules 를 비교할 대상이 아니다.
 */
if (!existsSync('yarn.lock') || existsSync('.pnp.cjs')) process.exit(0);

if (!existsSync('node_modules')) {
  out('❌ node_modules 가 없습니다 — 이 라인의 의존성이 설치되지 않았습니다.\n');
  out('   이대로 진행하면 pre-push 의 타입 검사가 내 코드와 무관한 오류를 냅니다.\n');
  out('   → yarn install 후 다시 실행하세요.\n');
  process.exit(1);
}

const versionOf = parseLockfile(read('yarn.lock'));
/** 락파일 descriptor 는 v1 이 `name@range`, Berry 가 `name@npm:range` 다 */
const lockedVersion = (name, range) =>
  versionOf.get(`${name}@${range}`) ?? versionOf.get(`${name}@npm:${range}`);

const mismatches = [];
const unlocked = [];
for (const [name, range] of Object.entries(declared)) {
  const want = lockedVersion(name, range);
  if (!want) {
    unlocked.push(`${name}@${range}`);
    continue; // 락파일에서 못 찾음 → 판정하지 않는다(오탐 방지)
  }
  const manifest = `node_modules/${name}/package.json`;
  if (!existsSync(manifest)) {
    mismatches.push({ name, want, got: '설치되지 않음' });
    continue;
  }
  let got;
  try {
    got = JSON.parse(read(manifest)).version;
  } catch {
    got = '읽을 수 없음';
  }
  if (got !== want) mismatches.push({ name, want, got });
}

/**
 * 락파일에서 찾지 못한 선언 — 판정하지 않았다는 사실만 알린다(차단하지 않는다).
 * 대개 락파일이 낡은 것이고(실측: 이 저장소의 husky 선언이 yarn.lock 에 없다) 그 항목은
 * 버전이 고정되지 않아 CI 와 다르게 설치될 수 있다. 파서가 못 읽은 형식일 수도 있으므로
 * 차단은 하지 않는다 — 오탐이 곧 배포 차단이기 때문이다.
 */
if (unlocked.length > 0) {
  const shown = unlocked.slice(0, 5).join(', ');
  const rest = unlocked.length > 5 ? ` 외 ${unlocked.length - 5}건` : '';
  out(`ℹ️  yarn.lock 에서 찾지 못해 판정하지 않은 선언 ${unlocked.length}건 (${shown}${rest}).\n`);
  out('   락파일이 낡았을 수 있습니다 — 그 항목은 버전이 고정되지 않습니다.\n');
}

if (mismatches.length === 0) process.exit(0);

out('❌ 설치본이 이 라인의 락파일과 다릅니다 — 이대로 진행하면 pre-push 의 타입 검사가\n');
out('   내 코드와 무관한 오류를 냅니다(2026-09 사고의 5건 중 4건이 이것이었습니다):\n');
const width = Math.max(...mismatches.map((m) => m.name.length));
for (const { name, want, got } of mismatches.slice(0, 10)) {
  out(`     ${name.padEnd(width)}  락파일 ${want}  ≠  설치본 ${got}\n`);
}
if (mismatches.length > 10) out(`     ... 외 ${mismatches.length - 10}건\n`);
out('   → yarn install 후 다시 실행하세요.\n');
process.exit(1);
