// Canonical simulator mirror of db/migrations/007_core_resource_graph_t1.sql.
// The live settlement engine reads these same normalized rows from PostgreSQL.
export const RESOURCE_FLOW_DEFINITIONS = Object.freeze({
  'MATERIAL-FAB-T1': { inputs: {}, outputs: { MATERIAL: 100 } },
  'ENERGY-PLANT-T1': { inputs: { MATERIAL: 5 }, outputs: { ENERGY: 120 } },
  'COMPONENT-FAB-T1': { inputs: { MATERIAL: 25, ENERGY: 20 }, outputs: { COMPONENTS: 50 } },
  'COMPUTE-FAB-T1': { inputs: { ENERGY: 30, COMPONENTS: 5 }, outputs: { COMPUTE: 40 } },
  'FOOD-FARM-T1': { inputs: { MATERIAL: 10, ENERGY: 8 }, outputs: { FOOD: 80 } },
});

export const RESOURCE_CODES = Object.freeze(['MATERIAL', 'COMPONENTS', 'ENERGY', 'COMPUTE', 'FOOD']);
export const SPECIALIZATIONS = Object.freeze({
  balanced: ['ENERGY-PLANT-T1', 'FOOD-FARM-T1', 'COMPONENT-FAB-T1', 'COMPUTE-FAB-T1', 'MATERIAL-FAB-T1'],
  energy: ['ENERGY-PLANT-T1', 'ENERGY-PLANT-T1', 'MATERIAL-FAB-T1'],
  food: ['FOOD-FARM-T1', 'FOOD-FARM-T1', 'ENERGY-PLANT-T1'],
  compute: ['COMPUTE-FAB-T1', 'COMPUTE-FAB-T1', 'ENERGY-PLANT-T1'],
  components: ['COMPONENT-FAB-T1', 'COMPONENT-FAB-T1', 'ENERGY-PLANT-T1'],
  materials: ['MATERIAL-FAB-T1', 'MATERIAL-FAB-T1', 'ENERGY-PLANT-T1'],
});
