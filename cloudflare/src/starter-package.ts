/** Fixed House genesis bundle. Values are display units; registration converts
 * them through economic_assets.unit_scale before ledger issuance. */
export const STARTER_PACKAGE_V2 = {
  credits: 100_000,
  resources: { food: 14, material: 50, components: 0, energy: 20, compute: 0 },
  design: {
    survivalDays: 14,
    intendedFirstProducer: 'ENERGY-PLANT-T1 or MATERIAL-FAB-T1',
    marketParticipation: true,
    immediatelySelfSufficient: false,
  },
} as const;

export function calculateStarterPackage() {
  return structuredClone(STARTER_PACKAGE_V2);
}
