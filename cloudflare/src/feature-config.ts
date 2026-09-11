/** Central production feature registry. Values are read at the boundary so
 * routes and scheduled work cannot drift into separate flag logic. */
export type FeatureKey = 'spotMarket' | 'bankDeposits' | 'bankLoans' | 'patents' | 'technologyLicenses' | 'futures' | 'mortality' | 'forcedLiquidation' | 'institutionDistress' | 'communities';
export type FeatureConfig = Record<FeatureKey, boolean>;
export type FeatureActivationStage = 'all' | 'baseline' | 'bank_loans' | 'mortality' | 'patents' | 'technology_licensing' | 'institution_distress' | 'delivery_futures' | 'forced_liquidation';

/** Ordered rollout gates for advanced closed-beta mechanics. */
export const FEATURE_ACTIVATION_ORDER: ReadonlyArray<{ stage: Exclude<FeatureActivationStage, 'all' | 'baseline'>; feature: FeatureKey }> = [
  { stage: 'bank_loans', feature: 'bankLoans' },
  { stage: 'mortality', feature: 'mortality' },
  { stage: 'patents', feature: 'patents' },
  { stage: 'technology_licensing', feature: 'technologyLicenses' },
  { stage: 'institution_distress', feature: 'institutionDistress' },
  { stage: 'delivery_futures', feature: 'futures' },
  { stage: 'forced_liquidation', feature: 'forcedLiquidation' },
];

const ENV_KEYS: Record<FeatureKey, string> = {
  spotMarket: 'FEATURE_SPOT_MARKET', bankDeposits: 'FEATURE_BANK_DEPOSITS', bankLoans: 'FEATURE_BANK_LOANS',
  patents: 'FEATURE_PATENTS', technologyLicenses: 'FEATURE_TECH_LICENSES', futures: 'FEATURE_FUTURES',
  mortality: 'FEATURE_MORTALITY', forcedLiquidation: 'FEATURE_FORCED_LIQUIDATION', institutionDistress: 'FEATURE_INSTITUTION_DISTRESS', communities: 'FEATURE_COMMUNITIES',
};

const DEFAULTS: FeatureConfig = {
  spotMarket: true, bankDeposits: true, bankLoans: true, patents: true, technologyLicenses: true,
  futures: true, mortality: true, forcedLiquidation: false, institutionDistress: true, communities: true,
};

function parseFlag(value: unknown, fallback: boolean): boolean {
  if (value === undefined || value === null || value === '') return fallback;
  return ['1', 'true', 'yes', 'on', 'enabled'].includes(String(value).trim().toLowerCase());
}

export function featureConfigForStage(base: FeatureConfig, stage: FeatureActivationStage): FeatureConfig {
  if (stage === 'all') return { ...base };
  const result = { ...base };
  const enabledThrough = stage === 'baseline' ? -1 : FEATURE_ACTIVATION_ORDER.findIndex((entry) => entry.stage === stage);
  FEATURE_ACTIVATION_ORDER.forEach((entry, index) => {
    if (index > enabledThrough) result[entry.feature] = false;
  });
  return result;
}

export function featureConfig(env: unknown): FeatureConfig {
  const source = (env ?? {}) as Record<string, unknown>;
  const base = (Object.keys(DEFAULTS) as FeatureKey[]).reduce((config, key) => {
    config[key] = parseFlag(source[ENV_KEYS[key]], DEFAULTS[key]);
    return config;
  }, {} as FeatureConfig);
  const requestedStage = String(source.EARTH_FEATURE_ACTIVATION_STAGE ?? 'all').trim().toLowerCase() as FeatureActivationStage;
  const stage = (['all', 'baseline', ...FEATURE_ACTIVATION_ORDER.map((entry) => entry.stage)] as string[]).includes(requestedStage)
    ? requestedStage
    : 'all';
  return featureConfigForStage(base, stage);
}

export function featureEnabled(env: unknown, feature: FeatureKey): boolean { return featureConfig(env)[feature]; }

export function featureDisabledResponse(feature: FeatureKey): Response {
  return Response.json({ ok: false, error: `Feature '${ENV_KEYS[feature]}' is disabled` }, { status: 404 });
}
