/**
 * package.json 병합 드라이버: 나머지는 표준 3-way 병합, "version" 필드만 큰 값(max) 채택.
 *
 * git merge driver 규약으로 호출된다:
 *   node scripts/merge-version.js %O %A %B
 *   %O = 공통 조상, %A = 현재(ours, 결과를 여기에 기록), %B = 상대(theirs)
 * 종료코드: 0 = 완전 해소, 1 = version 외 충돌이 남음(사람이 해결)
 *
 * 등록: scripts/setup-versioning.sh (클론마다 1회) + .gitattributes 의 `package.json merge=maxversion`
 */
const { execSync } = require('node:child_process');
const { readFileSync, writeFileSync } = require('node:fs');

const [baseFile, oursFile, theirsFile] = process.argv.slice(2);

const readVersion = (filePath) => {
  try {
    return (readFileSync(filePath, 'utf8').match(/"version"\s*:\s*"(\d+\.\d+\.\d+)"/) || [])[1] || null;
  } catch {
    return null;
  }
};

const parseSemver = (value) => {
  const matched = /(\d+)\.(\d+)\.(\d+)/.exec(value || '');
  return matched ? [+matched[1], +matched[2], +matched[3]] : null;
};

const compareSemver = (a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2];

const oursVersion = parseSemver(readVersion(oursFile));
const theirsVersion = parseSemver(readVersion(theirsFile));
const maxVersion = oursVersion && theirsVersion
  ? (compareSemver(oursVersion, theirsVersion) >= 0 ? oursVersion : theirsVersion).join('.')
  : (oursVersion || theirsVersion || [0, 0, 0]).join('.');

/** 표준 3-way 병합 (결과를 ours 파일에 in-place 기록, 충돌 시 마커 삽입) */
try {
  execSync(`git merge-file "${oursFile}" "${baseFile}" "${theirsFile}"`, { stdio: 'ignore' });
} catch {
  /** 충돌 존재 — 아래에서 마커로 판별 */
}

let content = readFileSync(oursFile, 'utf8');

if (!content.includes('<<<<<<<')) {
  /** 충돌 없음 → version 만 max 로 정규화 */
  content = content.replace(/("version"\s*:\s*")\d+\.\d+\.\d+(")/, `$1${maxVersion}$2`);
  writeFileSync(oursFile, content);
  process.exit(0);
}

/** 충돌 있음: 충돌 블록이 version 라인만 담고 있으면 max 로 해소, 아니면 그대로 두고 1 반환 */
let hasNonVersionConflict = false;
content = content.replace(
  /<<<<<<<[^\n]*\n([\s\S]*?)\n=======\n([\s\S]*?)\n>>>>>>>[^\n]*\n/g,
  (whole, oursHunk, theirsHunk) => {
    const isVersionOnly = [oursHunk, theirsHunk].every((side) =>
      side.split('\n').every((line) => line.trim() === '' || /"version"\s*:/.test(line)),
    );
    if (isVersionOnly) {
      const indentMatch = oursHunk.match(/^(\s*)"version"/m) || theirsHunk.match(/^(\s*)"version"/m);
      const indent = indentMatch ? indentMatch[1] : '  ';
      return `${indent}"version": "${maxVersion}",\n`;
    }
    hasNonVersionConflict = true;
    return whole;
  },
);
writeFileSync(oursFile, content);
process.exit(hasNonVersionConflict ? 1 : 0);
