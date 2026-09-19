export type CorporationMembershipState = 'MEMBER' | 'PENDING' | 'ELIGIBLE' | 'INELIGIBLE';

export type CorporationPolicy = {
  ruleCode: string;
  value: unknown;
  source: 'EARTH' | 'CORPORATION';
  version: number | string | null;
  effectiveFromGameDay: number | null;
  calculationKey: string | null;
  policyGroup: string | null;
  valueType: string | null;
  articleCode: string | null;
};

export type CorporationProfile = {
  identity: {
    id: string;
    name: string;
    admissionPolicy: string;
    charterVersion: string;
  };
  membership: {
    memberHouseCount: number;
    canJoin: boolean;
    membershipState: CorporationMembershipState;
  };
  capacity: {
    occupiedUnits: string;
    availableUnits: string;
    residentialUnits: string;
    privateProductiveUnits: string;
    publicUnits: string;
    standardBlockUnits: string;
    requiredBlocks: string;
    utilizationBps: number;
    houseBaseRateUnits: string | null;
    status: string;
  };
  capacityFinance: {
    houseRevenueUnits: string | null;
    earthExpenseUnits: string | null;
    marginUnits: string | null;
    arrearsUnits: string | null;
  };
  accounts: {
    treasuryUnits: string;
    operationsUnits: string;
    reserveUnits: string;
  };
  fiscal: {
    authorizedUnits: string | null;
    committedUnits: string | null;
    availableUnits: string | null;
    dailyRevenueUnits: string | null;
    dailyExpenseUnits: string | null;
  };
  technology: {
    adoptedCount: number;
    activeResearchCount: number;
  };
  governance: {
    openProposalCount: number;
    roles: string[];
    permissions: string[];
  };
  constitution: {
    rules: Record<string, unknown>;
    provenance: Record<string, unknown>;
    policies: CorporationPolicy[];
  };
};

export type CorporationDirectoryEntry = {
  id: string;
  name: string;
  admissionPolicy: string;
  memberHouseCount: number;
  incomeTaxBps: number | null;
  salesTaxBps: number | null;
  corporateTaxBps: number | null;
  propertyTaxBps: number | null;
  houseCapacityBaseRateUnits: string | null;
  occupiedCapacityUnits: string;
  standardCapacityUnits: string;
  requiredStandardUnits: string;
  capacityUtilizationBps: number;
  houseCapacityRevenueUnits: string;
  earthCapacityExpenseUnits: string;
  capacityMarginUnits: string;
  capacityStatus: string;
  treasuryUnits: string;
  operationsUnits: string;
  reserveUnits: string;
  technologyCount: number;
  activeResearchCount: number;
  canJoin: boolean;
  membershipState: CorporationMembershipState;
};

type CorporationProfileSource = Record<string, unknown>;

const text = (source: CorporationProfileSource, ...keys: string[]): string => {
  for (const key of keys) {
    if (source[key] != null) return String(source[key]);
  }
  return '0';
};

const optionalText = (source: CorporationProfileSource, ...keys: string[]): string | null => {
  for (const key of keys) {
    if (source[key] != null) return String(source[key]);
  }
  return null;
};

const numberValue = (source: CorporationProfileSource, ...keys: string[]): number => {
  for (const key of keys) {
    if (source[key] != null) return Number(source[key]);
  }
  return 0;
};

const optionalNumber = (source: CorporationProfileSource, ...keys: string[]): number | null => {
  for (const key of keys) {
    if (source[key] != null) return Number(source[key]);
  }
  return null;
};

export function corporationProfileFromSource(source: CorporationProfileSource): CorporationProfile {
  const membershipState = String(source.membershipState ?? source.membership_state ?? 'INELIGIBLE') as CorporationMembershipState;
  const occupiedUnits = text(source, 'occupiedCapacityUnits', 'occupied_capacity_units', 'v5_occupied_capacity');
  const standardBlockUnits = text(source, 'standardCapacityUnits', 'standard_capacity_units', 'v5_standard_territory_capacity');
  const requiredBlocks = text(source, 'requiredStandardUnits', 'required_standard_units', 'v5_required_territory_units');
  const availableUnits = text(source, 'availableCapacityUnits', 'available_capacity_units');
  return {
    identity: {
      id: text(source, 'id'),
      name: text(source, 'name'),
      admissionPolicy: String(source.admissionPolicy ?? source.admission_policy ?? 'UNKNOWN'),
      charterVersion: String(source.charterVersion ?? source.charter_version ?? 'UNKNOWN'),
    },
    membership: {
      memberHouseCount: numberValue(source, 'memberHouseCount', 'member_house_count', 'member_count'),
      canJoin: Boolean(source.canJoin ?? source.can_join),
      membershipState,
    },
    capacity: {
      occupiedUnits,
      availableUnits,
      residentialUnits: text(source, 'residentialUnits', 'residential_units'),
      privateProductiveUnits: text(source, 'privateProductiveUnits', 'private_productive_units'),
      publicUnits: text(source, 'publicUnits', 'public_units'),
      standardBlockUnits,
      requiredBlocks,
      utilizationBps: numberValue(source, 'capacityUtilizationBps', 'capacity_utilization_bps'),
      houseBaseRateUnits: optionalText(source, 'houseCapacityBaseRateUnits', 'house_capacity_base_rate_units'),
      status: String(source.capacityStatus ?? source.capacity_status ?? 'CURRENT'),
    },
    capacityFinance: {
      houseRevenueUnits: optionalText(source, 'houseCapacityRevenueUnits', 'house_capacity_revenue_units'),
      earthExpenseUnits: optionalText(source, 'earthCapacityExpenseUnits', 'earth_capacity_expense_units'),
      marginUnits: optionalText(source, 'capacityMarginUnits', 'capacity_margin_units'),
      arrearsUnits: optionalText(source, 'capacityArrearsUnits', 'capacity_arrears_units'),
    },
    accounts: {
      treasuryUnits: text(source, 'treasuryUnits', 'treasury_units'),
      operationsUnits: text(source, 'operationsUnits', 'operations_units'),
      reserveUnits: text(source, 'reserveUnits', 'reserve_units'),
    },
    fiscal: {
      authorizedUnits: optionalText(source, 'authorizedUnits', 'authorized_units'),
      committedUnits: optionalText(source, 'committedUnits', 'committed_units'),
      availableUnits: optionalText(source, 'availableUnits', 'available_units'),
      dailyRevenueUnits: optionalText(source, 'dailyRevenueUnits', 'daily_revenue_units'),
      dailyExpenseUnits: optionalText(source, 'dailyExpenseUnits', 'daily_expense_units'),
    },
    technology: {
      adoptedCount: numberValue(source, 'technologyCount', 'technology_count'),
      activeResearchCount: numberValue(source, 'activeResearchCount', 'active_research_count'),
    },
    governance: {
      openProposalCount: numberValue(source, 'openProposalCount', 'open_proposal_count'),
      roles: Array.isArray(source.roles) ? source.roles.map(String) : [],
      permissions: Array.isArray(source.permissions) ? source.permissions.map(String) : [],
    },
    constitution: {
      rules: (source.rules ?? source.constitutionRules ?? source.constitution_rules) && typeof (source.rules ?? source.constitutionRules ?? source.constitution_rules) === 'object'
        ? (source.rules ?? source.constitutionRules ?? source.constitution_rules) as Record<string, unknown>
        : {},
      provenance: source.provenance && typeof source.provenance === 'object' ? source.provenance as Record<string, unknown> : {},
      policies: Array.isArray(source.policies) ? source.policies as CorporationPolicy[] : [],
    },
  };
}

export function corporationPoliciesFromConstitution(readModel: Record<string, unknown>): CorporationPolicy[] {
  const rules = readModel.rules && typeof readModel.rules === 'object' ? readModel.rules as Record<string, unknown> : {};
  const provenance = readModel.provenance && typeof readModel.provenance === 'object' ? readModel.provenance as Record<string, unknown> : {};
  const definitions = Array.isArray(readModel.definitions) ? readModel.definitions as Array<Record<string, unknown>> : [];
  const history = Array.isArray(readModel.history) ? readModel.history as Array<Record<string, unknown>> : [];
  return Object.entries(rules).map(([ruleCode, value]) => {
    const source = String(provenance[ruleCode] ?? 'EARTH') as 'EARTH' | 'CORPORATION';
    const definition = definitions.find((row) => String(row.rule_code) === ruleCode);
    const version = history.find((row) => String(row.rule_code) === ruleCode && String(row.authority_type) === source);
    return {
      ruleCode,
      value,
      source,
      version: version?.version == null ? null : version.version as number | string,
      effectiveFromGameDay: version?.effective_from_game_day == null ? null : Number(version.effective_from_game_day),
      calculationKey: definition?.calculation_key == null ? null : String(definition.calculation_key),
      policyGroup: definition?.policy_group == null ? null : String(definition.policy_group),
      valueType: definition?.value_type == null ? null : String(definition.value_type),
      articleCode: definition?.article_code == null ? null : String(definition.article_code),
    };
  });
}

export function corporationDirectoryEntryFromProfile(profile: CorporationProfile, source: CorporationProfileSource = {}): CorporationDirectoryEntry {
  const tax = (ruleCode: string, ...legacyKeys: string[]): number | null => {
    const rule = profile.constitution.rules[ruleCode];
    if (rule != null) return Number(rule);
    return optionalNumber(source, ...legacyKeys);
  };
  return {
    id: profile.identity.id,
    name: profile.identity.name,
    admissionPolicy: profile.identity.admissionPolicy,
    memberHouseCount: profile.membership.memberHouseCount,
    incomeTaxBps: tax('CORPORATION.TAX.INCOME_RATE', 'incomeTaxBps', 'income_tax_bps'),
    salesTaxBps: tax('CORPORATION.TAX.SALES_RATE', 'salesTaxBps', 'sales_tax_bps'),
    corporateTaxBps: tax('CORPORATION.TAX.CORPORATE_RATE', 'corporateTaxBps', 'corporate_tax_bps'),
    propertyTaxBps: tax('CORPORATION.TAX.PROPERTY_RATE', 'propertyTaxBps', 'property_tax_bps'),
    houseCapacityBaseRateUnits: profile.capacity.houseBaseRateUnits,
    occupiedCapacityUnits: profile.capacity.occupiedUnits,
    standardCapacityUnits: profile.capacity.standardBlockUnits,
    requiredStandardUnits: profile.capacity.requiredBlocks,
    capacityUtilizationBps: profile.capacity.utilizationBps,
    houseCapacityRevenueUnits: profile.capacityFinance.houseRevenueUnits ?? '0',
    earthCapacityExpenseUnits: profile.capacityFinance.earthExpenseUnits ?? '0',
    capacityMarginUnits: profile.capacityFinance.marginUnits ?? '0',
    capacityStatus: profile.capacity.status,
    treasuryUnits: profile.accounts.treasuryUnits,
    operationsUnits: profile.accounts.operationsUnits,
    reserveUnits: profile.accounts.reserveUnits,
    technologyCount: profile.technology.adoptedCount,
    activeResearchCount: profile.technology.activeResearchCount,
    canJoin: profile.membership.canJoin,
    membershipState: profile.membership.membershipState,
  };
}
