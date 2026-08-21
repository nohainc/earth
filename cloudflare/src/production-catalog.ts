export type MachineCatalogEntry = {
  output: string;
  credit: number;
  material: number;
  capacity: number;
};

/**
 * The playable production catalog is a read-only product boundary. Keeping it
 * outside the Worker router makes catalog changes easy to review and keeps
 * acquisition validation tied to the same source of truth.
 */
export const MACHINE_CATALOG: Record<string, MachineCatalogEntry> = {
  extractor: { output: 'material', credit: 4200, material: 80, capacity: 2 },
  'energy-array': { output: 'energy', credit: 3600, material: 60, capacity: 2 },
  'food-synthesizer': { output: 'food', credit: 4400, material: 75, capacity: 1.8 },
  'compute-node': { output: 'compute', credit: 5200, material: 100, capacity: 1.5 },
  fabricator: { output: 'components', credit: 4800, material: 90, capacity: 1.8 },
  'housing-fabricator': { output: 'components', credit: 5000, material: 110, capacity: 1.6 },
  'research-cluster': { output: 'compute', credit: 7000, material: 140, capacity: 1.2 },
};

export function productionCatalogResponse(): Response {
  return Response.json({
    sectors: [
      { id: 'energy', name: 'Energy', output: 'energy', machineTypes: ['energy-array'], acquisition: MACHINE_CATALOG['energy-array'] },
      { id: 'food', name: 'Food', output: 'food', machineTypes: ['food-synthesizer'], acquisition: MACHINE_CATALOG['food-synthesizer'] },
      { id: 'extraction', name: 'Extraction', output: 'material', machineTypes: ['extractor'], acquisition: MACHINE_CATALOG.extractor },
      { id: 'components', name: 'Components', output: 'components', machineTypes: ['fabricator'], acquisition: MACHINE_CATALOG.fabricator },
      { id: 'machines', name: 'Machines', output: 'components', machineTypes: ['assembly-line'] },
      { id: 'maintenance', name: 'Maintenance', output: 'components', machineTypes: ['service-robot'] },
      { id: 'housing', name: 'Housing', output: 'components', machineTypes: ['housing-fabricator'], acquisition: MACHINE_CATALOG['housing-fabricator'] },
      { id: 'compute', name: 'Compute', output: 'compute', machineTypes: ['compute-node'], acquisition: MACHINE_CATALOG['compute-node'] },
      { id: 'r-and-d', name: 'R&D', output: 'compute', machineTypes: ['research-cluster'], acquisition: MACHINE_CATALOG['research-cluster'] },
      { id: 'it-services', name: 'IT Services', output: 'service', machineTypes: [] },
      { id: 'consulting', name: 'Consulting', output: 'service', machineTypes: [] },
      { id: 'logistics', name: 'Logistics', output: 'service', machineTypes: [] },
      { id: 'healthcare', name: 'Healthcare', output: 'service', machineTypes: [] },
      { id: 'education', name: 'Education', output: 'service', machineTypes: [] },
    ],
    rules: { serverAuthoritative: true, productionRequiresUtilization: true, depreciationApplied: true },
    persistence: 'planetscale-postgres',
  });
}
