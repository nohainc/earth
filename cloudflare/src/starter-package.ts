/** Fixed House genesis bundle. Values are display units; registration converts
 * them through economic_assets.unit_scale before ledger issuance.
 * V5 provides enough CREDIT, FOOD, ENERGY, MATERIAL, COMPONENTS, and COMPUTE
 * to survive initially and construct approximately one Tier-1 commodity facility.
 */
export const STARTER_PACKAGE_V2 = {
  credits: 50_000,
  resources: { food: 14, material: 140, components: 15, energy: 20, compute: 10 },
  design: {
    survivalDays: 14,
    intendedFirstProducer: 'SOLAR-MICROGRID-T1 or VERTICAL-FARM-T1 or MATERIALS-RECOVERY-T1',
    marketParticipation: true,
    immediatelySelfSufficient: false,
  },
} as const;

export function calculateStarterPackage() {
  return structuredClone(STARTER_PACKAGE_V2);
}
