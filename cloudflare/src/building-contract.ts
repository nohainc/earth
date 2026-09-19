/** Canonical V5 Buildings read/quote contract. Monetary and resource values
 * are atomic units serialized as decimal strings at the JSON boundary. */

export type BuildingOwnerType = 'HOUSE' | 'CORPORATION';
export type BuildingScope = 'PRIVATE' | 'PUBLIC';

export type BuildingPermissions = {
  canBuild: boolean;
  canPropose: boolean;
  canView: boolean;
  canOperate: boolean;
  canUpgrade: boolean;
  canRetrofit: boolean;
  canDemolish: boolean;
};

export type BuildingSettlement = {
  latestGameDay: number | null;
  status: string | null;
  operatingCreditUnits: string | null;
  inputUnits: Record<string, string> | null;
  outputUnits: Record<string, string> | null;
};

export type BuildingOperatingPolicy = {
  currentMode: string | null;
  allowedModes: string[];
  effectsByMode: Record<string, {
    utilizationBps: number;
    inputUnits: Record<string, string> | null;
    outputUnits: Record<string, string> | null;
    operatingCreditUnits: string | null;
  }>;
};

export type BuildingAsset = {
  id: string;
  catalogId: string;
  buildingType: string;
  ownerType: BuildingOwnerType;
  ownerId: string;
  ownershipScope: BuildingScope;
  status: string;
  constructionState: string | null;
  installedGeneration: number | null;
  startedGameDay: number | null;
  commissionedGameDay: number | null;
  slotFootprintUnits: string;
  utilizationBps: number | null;
  operatingPolicy: BuildingOperatingPolicy;
  permissions: BuildingPermissions;
  allowedActions: string[];
  settlement: BuildingSettlement;
};

export type BuildingCatalogEntry = {
  id: string;
  code: string;
  familyCode: string | null;
  tier: number;
  ownershipScope: BuildingScope;
  economicRole: string | null;
  constructionCreditUnits: string;
  constructionMinutes: number;
  operatingCreditUnits: string | null;
  slotFootprintUnits: string;
  technologyDomain: string | null;
  minimumScaleCapability: string | null;
  resourceFlows: unknown[];
};

export type BuildingPortfolio = {
  houseAssets: BuildingAsset[];
  corporationPublicAssets: BuildingAsset[];
  catalog: BuildingCatalogEntry[];
  corporationPermissions: BuildingPermissions;
  generatedFrom: 'postgres-canonical-building-contract-v5';
};

export type BuildingQuote = {
  ok: true;
  eligible: boolean;
  blockers: string[];
  ownerType: BuildingOwnerType;
  ownerId: string;
  buildingType: string;
  buildingCatalogId: string;
  footprintUnits: string;
  creditCostUnits: string;
  resourceRequirements: Array<{
    code: string;
    requiredUnits: string;
    availableUnits: string;
    missingUnits: string;
  }>;
  effectiveConstructionMinutes: number;
  capacity: Record<string, unknown> | null;
  permissions: { canConstruct: boolean };
  allowedActions: string[];
};

function text(value: unknown, fallback = '0'): string {
  return value == null ? fallback : String(value);
}

function nullableNumber(value: unknown): number | null {
  if (value == null || value === '') return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function unitObject(value: unknown): Record<string, string> | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const result = Object.fromEntries(Object.entries(value as Record<string, unknown>)
    .map(([key, item]) => [key, text(item)]));
  return Object.keys(result).length ? result : null;
}

function scaleUnits(value: Record<string, string> | null, numerator: number, denominator: number): Record<string, string> | null {
  if (!value || denominator <= 0) return null;
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, ((BigInt(item) * BigInt(numerator)) / BigInt(denominator)).toString()]));
}

export function buildingAssetFromRow(
  row: Record<string, unknown>,
  permissions: BuildingPermissions,
): BuildingAsset {
  const inputUnits = unitObject(row.settlement_input_units);
  const outputUnits = unitObject(row.settlement_output_units);
  const currentUtilizationBps = nullableNumber(row.utilization_bps) ?? 0;
  const currentCredit = row.settlement_operating_credit_units == null ? null : text(row.settlement_operating_credit_units);
  const currentMode = row.operating_mode == null ? null : String(row.operating_mode);
  const effectsByMode: BuildingOperatingPolicy['effectsByMode'] = {};
  for (const [mode, utilizationBps] of Object.entries({ CONSERVATIVE: 7000, BALANCED: 10000, GROWTH: 10000 })) {
    effectsByMode[mode] = {
      utilizationBps,
      inputUnits: scaleUnits(inputUnits, utilizationBps, currentUtilizationBps),
      outputUnits: scaleUnits(outputUnits, utilizationBps, currentUtilizationBps),
      operatingCreditUnits: currentCredit == null || currentUtilizationBps <= 0
        ? null
        : ((BigInt(currentCredit) * BigInt(utilizationBps)) / BigInt(currentUtilizationBps)).toString(),
    };
  }
  return {
    id: text(row.id, ''),
    catalogId: text(row.catalog_id, ''),
    buildingType: text(row.building_type ?? row.code, ''),
    ownerType: String(row.owner_type ?? 'HOUSE') as BuildingOwnerType,
    ownerId: text(row.owner_id, ''),
    ownershipScope: String(row.ownership_scope ?? 'PRIVATE') as BuildingScope,
    status: text(row.status, 'UNKNOWN'),
    constructionState: row.construction_state == null ? null : String(row.construction_state),
    installedGeneration: nullableNumber(row.installed_generation),
    startedGameDay: nullableNumber(row.started_game_day),
    commissionedGameDay: nullableNumber(row.commissioned_game_day),
    slotFootprintUnits: text(row.slot_footprint),
    utilizationBps: nullableNumber(row.utilization_bps),
    operatingPolicy: {
      currentMode,
      allowedModes: ['CONSERVATIVE', 'BALANCED', 'GROWTH'],
      effectsByMode,
    },
    permissions,
    allowedActions: [
      ...(permissions.canUpgrade ? ['UPGRADE'] : []),
      ...(permissions.canRetrofit ? ['RETROFIT'] : []),
      ...(permissions.canDemolish ? ['DEMOLISH'] : []),
    ],
    settlement: {
      latestGameDay: nullableNumber(row.latest_settlement_game_day),
      status: row.latest_settlement_status == null ? null : String(row.latest_settlement_status),
      operatingCreditUnits: row.settlement_operating_credit_units == null ? null : text(row.settlement_operating_credit_units),
      inputUnits,
      outputUnits,
    },
  };
}

export function buildingCatalogEntryFromRow(row: Record<string, unknown>): BuildingCatalogEntry {
  return {
    id: text(row.id, ''),
    code: text(row.code, ''),
    familyCode: row.family_code == null ? null : String(row.family_code),
    tier: Number(row.tier ?? 0),
    ownershipScope: String(row.ownership_scope ?? 'PRIVATE') as BuildingScope,
    economicRole: row.economic_role == null ? null : String(row.economic_role),
    constructionCreditUnits: text(row.construction_credit_units),
    constructionMinutes: Number(row.construction_minutes ?? 0),
    operatingCreditUnits: row.operating_credit_units == null ? null : text(row.operating_credit_units),
    slotFootprintUnits: text(row.slot_footprint),
    technologyDomain: row.technology_domain == null ? null : String(row.technology_domain),
    minimumScaleCapability: row.minimum_scale_capability == null ? null : String(row.minimum_scale_capability),
    resourceFlows: Array.isArray(row.resource_flows) ? row.resource_flows : [],
  };
}

export function buildingPortfolio(
  houseRows: Record<string, unknown>[],
  corporationRows: Record<string, unknown>[],
  catalogRows: Record<string, unknown>[],
  corporationPermissionRow?: Record<string, unknown>,
): BuildingPortfolio {
  const permissionsRow = corporationPermissionRow ?? corporationRows[0];
  const corporationPermissions = permissionsRow
    ? {
        canBuild: permissionsRow.viewer_can_build === true,
        canPropose: permissionsRow.viewer_can_propose === true,
        canView: true,
        canOperate: permissionsRow.viewer_can_operate === true,
        canUpgrade: permissionsRow.viewer_can_upgrade === true,
        canRetrofit: permissionsRow.viewer_can_retrofit === true,
        canDemolish: false,
      }
    : {
        canBuild: false, canPropose: false, canView: false,
        canOperate: false, canUpgrade: false, canRetrofit: false,
        canDemolish: false,
      };
  return {
    houseAssets: houseRows.map((row) => buildingAssetFromRow(row, {
      canBuild: true, canPropose: false,
      canView: true, canOperate: true, canUpgrade: true, canDemolish: true,
      canRetrofit: true,
    })),
    corporationPublicAssets: corporationRows.map((row) => buildingAssetFromRow(row, corporationPermissions)),
    catalog: catalogRows.map(buildingCatalogEntryFromRow),
    corporationPermissions,
    generatedFrom: 'postgres-canonical-building-contract-v5',
  };
}
