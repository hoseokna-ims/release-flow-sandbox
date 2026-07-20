/** FE-1022: 기능 플래그 (staging 배포 플로우 테스트용) */
export const FEATURE_FLAGS = {
  /** 스테이징 배포 파이프라인 검증용 샘플 플래그 */
  stagingSmokeTest: true,
} as const;

export type FeatureFlagKey = keyof typeof FEATURE_FLAGS;
