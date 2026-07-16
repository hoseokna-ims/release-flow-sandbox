/** FE-1000: 앱 메타 정보 (릴리스 자동화 데모용 feature) */
export const APP_NAME = 'release-flow-sandbox';
export const APP_DESCRIPTION = '버전/릴리스 자동화 테스트 프로젝트';

/** FE-1006: package.json 과 동기화되는 현재 릴리스 버전 */
export const APP_VERSION = '0.9.0';

/** FE-1012: 버전 문자열로 릴리스 상태 라벨을 도출 */
export function getReleaseStatus(version: string = APP_VERSION): string {
  const patch = Number(version.split('.')[2] ?? 0);
  return patch === 0 ? '정식 릴리스' : '핫픽스';
}
export const APP_VERSION = '0.8.0';

/** FE-1011: 저장소 링크 (푸터/CTA 에서 재사용) */
export const APP_REPO_URL = 'https://github.com/hoseokna-ims/release-flow-sandbox';
