export const RANKING_RULES_VERSION = 'rankings-v2';

export const RANKING_METRICS = [
  'LIQUID_CREDIT', 'PRODUCTIVE_CAPACITY', 'LEGACY', 'TECHNOLOGY',
  'PUBLIC_GOODS', 'MARKET_VOLUME_30D',
  'CORPORATION_MEMBER_HOUSES', 'CORPORATION_LIQUID_CREDIT',
  'CORPORATION_TREASURY', 'CORPORATION_OCCUPIED_CAPACITY',
  'CORPORATION_CAPACITY', 'CORPORATION_SERVICE_CAPACITY',
  'CORPORATION_FISCAL_HEADROOM', 'CORPORATION_TECHNOLOGY',
  'CORPORATION_MARKET_VOLUME_30D',
] as const;

export type RankingMetric = typeof RANKING_METRICS[number];
export type RankingSubjectType = 'HOUSE' | 'CORPORATION';

export type RankingMetricDefinition = {
  code: RankingMetric;
  subjectType: RankingSubjectType;
  title: string;
  description: string;
  formula: string;
  valueType: 'CREDIT_UNITS' | 'CAPACITY_UNITS' | 'POINTS' | 'COUNT';
  unit: 'CREDIT' | 'CAPACITY' | 'LEGACY_POINTS' | 'COUNT';
  calculationSource: string;
  timeWindow: 'CURRENT' | 'ALL_TIME' | 'TRAILING_30_GAME_DAYS';
  rulesVersion: typeof RANKING_RULES_VERSION;
  tieBehavior: 'VALUE_DESC_SUBJECT_ID_ASC';
};

/** Canonical rankings-v2 metadata shared by settlement and read models. */
export const RANKING_DEFINITIONS: readonly RankingMetricDefinition[] = [
  {
    code: 'LIQUID_CREDIT',
    subjectType: 'HOUSE',
    title: 'Liquid CREDIT',
    description: 'Current CREDIT account balance owned by the House; unlike resource inventories are excluded.',
    formula: 'SUM(economic_accounts.balance_units) grouped by House where account is ACTIVE and economic_assets.code=CREDIT',
    valueType: 'CREDIT_UNITS',
    unit: 'CREDIT',
    calculationSource: 'economic_accounts.balance_units joined to economic_assets.code=CREDIT',
    timeWindow: 'CURRENT',
    rulesVersion: RANKING_RULES_VERSION,
    tieBehavior: 'VALUE_DESC_SUBJECT_ID_ASC',
  },
  {
    code: 'PRODUCTIVE_CAPACITY',
    subjectType: 'HOUSE',
    title: 'Productive capacity',
    description: 'Sum of active building capacity footprints owned by the House.',
    formula: 'SUM(building_catalog.slot_footprint) grouped by House where building.status=ACTIVE',
    valueType: 'CAPACITY_UNITS',
    unit: 'CAPACITY',
    calculationSource: 'buildings.slot_footprint via building_catalog.slot_footprint where building.status=ACTIVE',
    timeWindow: 'CURRENT',
    rulesVersion: RANKING_RULES_VERSION,
    tieBehavior: 'VALUE_DESC_SUBJECT_ID_ASC',
  },
  {
    code: 'LEGACY',
    subjectType: 'HOUSE',
    title: 'Legacy',
    description: 'The House legacy value recorded in the canonical House state.',
    formula: 'houses.dynasty_legacy for each active House',
    valueType: 'POINTS',
    unit: 'LEGACY_POINTS',
    calculationSource: 'houses.dynasty_legacy',
    timeWindow: 'CURRENT',
    rulesVersion: RANKING_RULES_VERSION,
    tieBehavior: 'VALUE_DESC_SUBJECT_ID_ASC',
  },
  {
    code: 'TECHNOLOGY',
    subjectType: 'HOUSE',
    title: 'House technology patents',
    description: 'Active technology patents owned by the House; Corporation-wide access is excluded.',
    formula: 'COUNT(DISTINCT technology_patents.id) grouped by House where patent.status=ACTIVE and owner is the House',
    valueType: 'COUNT',
    unit: 'COUNT',
    calculationSource: 'technology_patents.id where owner is the House and status=ACTIVE',
    timeWindow: 'CURRENT',
    rulesVersion: RANKING_RULES_VERSION,
    tieBehavior: 'VALUE_DESC_SUBJECT_ID_ASC',
  },
  {
    code: 'PUBLIC_GOODS',
    subjectType: 'HOUSE',
    title: 'Successful Initiative contribution',
    description: 'House CREDIT contributions applied to Initiatives that completed successfully.',
    formula: 'SUM(initiative_contributions.amount_units) grouped by House where contribution.status=APPLIED and Initiative.status=COMPLETED',
    valueType: 'CREDIT_UNITS',
    unit: 'CREDIT',
    calculationSource: 'initiative_contributions.amount_units where status=APPLIED and v5_initiatives.status=COMPLETED',
    timeWindow: 'ALL_TIME',
    rulesVersion: RANKING_RULES_VERSION,
    tieBehavior: 'VALUE_DESC_SUBJECT_ID_ASC',
  },
  {
    code: 'MARKET_VOLUME_30D',
    subjectType: 'HOUSE',
    title: 'Market volume · 30d',
    description: 'Gross CREDIT quote value of finalized market fills involving the House during the trailing 30 game days.',
    formula: 'SUM(market_fills.gross_quote_units) for House buyer or seller where batch.status=COMPLETED, quote asset=CREDIT, and game_day is snapshot_day-29 through snapshot_day',
    valueType: 'CREDIT_UNITS',
    unit: 'CREDIT',
    calculationSource: 'market_fills.gross_quote_units joined to COMPLETED market_batches and CREDIT-quoted instruments',
    timeWindow: 'TRAILING_30_GAME_DAYS',
    rulesVersion: RANKING_RULES_VERSION,
    tieBehavior: 'VALUE_DESC_SUBJECT_ID_ASC',
  },
  {
    code: 'CORPORATION_MEMBER_HOUSES',
    subjectType: 'CORPORATION',
    title: 'Member Houses',
    description: 'Active Houses affiliated with the Corporation.',
    formula: 'COUNT(DISTINCT house_affiliations.house_id) grouped by Corporation where affiliation.status=ACTIVE',
    valueType: 'COUNT',
    unit: 'COUNT',
    calculationSource: 'house_affiliations.house_id joined to corporations where affiliation.status=ACTIVE',
    timeWindow: 'CURRENT',
    rulesVersion: RANKING_RULES_VERSION,
    tieBehavior: 'VALUE_DESC_SUBJECT_ID_ASC',
  },
  {
    code: 'CORPORATION_LIQUID_CREDIT',
    subjectType: 'CORPORATION',
    title: 'Corporation liquid CREDIT',
    description: 'Current CREDIT account balance owned by the Corporation.',
    formula: 'SUM(economic_accounts.balance_units) grouped by Corporation where account is ACTIVE and economic_assets.code=CREDIT',
    valueType: 'CREDIT_UNITS',
    unit: 'CREDIT',
    calculationSource: 'economic_accounts.balance_units joined to economic_assets.code=CREDIT for Corporation owner',
    timeWindow: 'CURRENT',
    rulesVersion: RANKING_RULES_VERSION,
    tieBehavior: 'VALUE_DESC_SUBJECT_ID_ASC',
  },
  {
    code: 'CORPORATION_CAPACITY',
    subjectType: 'CORPORATION',
    title: 'Corporation capacity',
    description: 'Active building capacity footprints owned by the Corporation.',
    formula: 'SUM(building_catalog.slot_footprint) grouped by Corporation where building.status=ACTIVE',
    valueType: 'CAPACITY_UNITS',
    unit: 'CAPACITY',
    calculationSource: 'buildings.slot_footprint via building_catalog.slot_footprint where owner is a Corporation and building.status=ACTIVE',
    timeWindow: 'CURRENT',
    rulesVersion: RANKING_RULES_VERSION,
    tieBehavior: 'VALUE_DESC_SUBJECT_ID_ASC',
  },
  {
    code: 'CORPORATION_TECHNOLOGY',
    subjectType: 'CORPORATION',
    title: 'Corporation technology access',
    description: 'Active technologies adopted or made available through the Corporation technology registry.',
    formula: 'COUNT(DISTINCT corporation_technology_access.technology_id) grouped by Corporation where access.status=ACTIVE',
    valueType: 'COUNT',
    unit: 'COUNT',
    calculationSource: 'corporation_technology_access.technology_id where access.status=ACTIVE',
    timeWindow: 'CURRENT',
    rulesVersion: RANKING_RULES_VERSION,
    tieBehavior: 'VALUE_DESC_SUBJECT_ID_ASC',
  },
  {
    code: 'CORPORATION_TREASURY',
    subjectType: 'CORPORATION',
    title: 'Corporation treasury',
    description: 'Current CREDIT held in the Corporation treasury account.',
    formula: 'SUM(economic_accounts.balance_units) grouped by Corporation where account_type=TREASURY, account.status=ACTIVE, and economic_assets.code=CREDIT',
    valueType: 'CREDIT_UNITS',
    unit: 'CREDIT',
    calculationSource: 'economic_accounts treasury balance joined to Corporation owner and economic_assets.code=CREDIT',
    timeWindow: 'CURRENT',
    rulesVersion: RANKING_RULES_VERSION,
    tieBehavior: 'VALUE_DESC_SUBJECT_ID_ASC',
  },
  {
    code: 'CORPORATION_OCCUPIED_CAPACITY',
    subjectType: 'CORPORATION',
    title: 'Occupied capacity',
    description: 'Latest canonical occupied capacity across member Houses and Corporation public assets.',
    formula: 'Latest corporation_capacity_state_v5.total_occupied_units per Corporation',
    valueType: 'CAPACITY_UNITS',
    unit: 'CAPACITY',
    calculationSource: 'corporation_capacity_state_v5.total_occupied_units at the latest finalized game day',
    timeWindow: 'CURRENT',
    rulesVersion: RANKING_RULES_VERSION,
    tieBehavior: 'VALUE_DESC_SUBJECT_ID_ASC',
  },
  {
    code: 'CORPORATION_SERVICE_CAPACITY',
    subjectType: 'CORPORATION',
    title: 'Public service capacity',
    description: 'Latest authoritative capacity delivered by Corporation public infrastructure.',
    formula: 'Latest corporation_operating_snapshots.service_capacity_units per Corporation',
    valueType: 'CAPACITY_UNITS',
    unit: 'CAPACITY',
    calculationSource: 'corporation_operating_snapshots.service_capacity_units at the latest finalized game day',
    timeWindow: 'CURRENT',
    rulesVersion: RANKING_RULES_VERSION,
    tieBehavior: 'VALUE_DESC_SUBJECT_ID_ASC',
  },
  {
    code: 'CORPORATION_FISCAL_HEADROOM',
    subjectType: 'CORPORATION',
    title: 'Fiscal budget headroom',
    description: 'Uncommitted and unspent budget authority in the latest Corporation financial snapshot.',
    formula: 'MAX(0, budget_authorized_units - budget_committed_units - budget_spent_units) from latest institution_financial_snapshots row',
    valueType: 'CREDIT_UNITS',
    unit: 'CREDIT',
    calculationSource: 'institution_financial_snapshots budget authority and commitments for Corporation institution',
    timeWindow: 'CURRENT',
    rulesVersion: RANKING_RULES_VERSION,
    tieBehavior: 'VALUE_DESC_SUBJECT_ID_ASC',
  },
  {
    code: 'CORPORATION_MARKET_VOLUME_30D',
    subjectType: 'CORPORATION',
    title: 'Corporation market volume · 30d',
    description: 'Gross CREDIT quote value of finalized market fills involving the Corporation during the trailing 30 game days.',
    formula: 'SUM(market_fills.gross_quote_units) for Corporation buyer or seller where batch.status=COMPLETED, quote asset=CREDIT, and game_day is snapshot_day-29 through snapshot_day',
    valueType: 'CREDIT_UNITS',
    unit: 'CREDIT',
    calculationSource: 'market_fills.gross_quote_units joined to Corporation owner, COMPLETED market_batches, and CREDIT-quoted instruments',
    timeWindow: 'TRAILING_30_GAME_DAYS',
    rulesVersion: RANKING_RULES_VERSION,
    tieBehavior: 'VALUE_DESC_SUBJECT_ID_ASC',
  },
];

export function rankMetricRows(rows: Array<{ subjectId: string; subjectName: string; value: string | number }>) {
  return rows
    .map((row) => ({ ...row, value: String(row.value), exactValue: BigInt(String(row.value)) }))
    .sort((a, b) => (a.exactValue === b.exactValue ? a.subjectId.localeCompare(b.subjectId) : a.exactValue > b.exactValue ? -1 : 1))
    .slice(0, 100)
    .map((row, index) => ({ rank: index + 1, subjectId: row.subjectId, subjectName: row.subjectName, value: row.value }));
}

export function isRankingMetric(value: string | undefined): value is RankingMetric {
  return value != null && (RANKING_METRICS as readonly string[]).includes(value);
}
