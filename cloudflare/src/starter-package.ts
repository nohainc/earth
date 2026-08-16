export const STARTER_PACKAGE_BASE = {
  credits: 18_420,
  material: 420,
  components: 86,
  energy: 92,
  compute: 64,
} as const;

const MIN_INDEX = 0.5;
const MAX_INDEX = 3;

export function boundedIndex(value: unknown, fallback = 1): number {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return fallback;
  return Math.max(MIN_INDEX, Math.min(MAX_INDEX, numeric));
}

export function economicStartIndex(referenceMarketPrice: unknown): number {
  const price = Number(referenceMarketPrice);
  if (!Number.isFinite(price) || price <= 0) return 1;
  return boundedIndex(price / 50);
}

export function calculateStarterPackage(livingCostIndex: unknown, economicIndex: unknown) {
  const living = boundedIndex(livingCostIndex);
  const economic = boundedIndex(economicIndex);
  return {
    livingCostIndex: living,
    economicStartIndex: economic,
    credits: Math.round(STARTER_PACKAGE_BASE.credits * living),
    resources: {
      material: Math.round(STARTER_PACKAGE_BASE.material * economic),
      components: Math.round(STARTER_PACKAGE_BASE.components * economic),
      energy: Math.round(STARTER_PACKAGE_BASE.energy * living),
      compute: Math.round(STARTER_PACKAGE_BASE.compute * economic),
    },
  };
}
