import type { PostgresRepository } from './repository.ts';

export type FinancialQuote = {
  quoteType: 'CONSTRUCTION' | 'UPGRADE' | 'RETROFIT' | 'OVERHAUL' | 'RESEARCH' | 'TECHNOLOGY_ADOPTION' | 'LICENSING' | 'PUBLIC_PROJECT';
  baseAmount: Record<string, string>;
  fees: Record<string, string>;
  taxes: Record<string, string>;
  total: Record<string, string>;
  payer: { principalId: string; accountPurpose: string };
  recipientTreatment: { type: string; principalId: string | null; accountPurpose: string | null };
  ruleVersion: string;
  definitionVersion: string;
  subject: Record<string, unknown>;
};

const ZERO = '0';
const MULTIPLIERS: Record<string, { bps: bigint; rule: string }> = {
  CONSTRUCTION: { bps: 10000n, rule: 'construction-credit-v1' },
  PUBLIC_PROJECT: { bps: 10000n, rule: 'public-project-credit-v1' },
  UPGRADE: { bps: 5000n, rule: 'upgrade-credit-v1' },
  RETROFIT: { bps: 4000n, rule: 'retrofit-credit-v1' },
  OVERHAUL: { bps: 7500n, rule: 'overhaul-credit-v1' },
};

function creditQuote(input: { quoteType: FinancialQuote['quoteType']; baseUnits: string; payer: FinancialQuote['payer']; recipientTreatment: FinancialQuote['recipientTreatment']; ruleVersion: string; definitionVersion: string; subject: Record<string, unknown>; resourceFees?: Record<string, string> }): FinancialQuote {
  const base = BigInt(input.baseUnits);
  const fees = { ...(input.resourceFees ?? {}), CREDIT: ZERO };
  const taxes = { CREDIT: ZERO };
  const total = { ...fees, CREDIT: (base + BigInt(fees.CREDIT ?? ZERO) + BigInt(taxes.CREDIT)).toString() };
  return { quoteType: input.quoteType, baseAmount: { CREDIT: base.toString() }, fees, taxes, total, payer: input.payer, recipientTreatment: input.recipientTreatment, ruleVersion: input.ruleVersion, definitionVersion: input.definitionVersion, subject: input.subject };
}

async function catalogQuote(repository: PostgresRepository, input: { quoteType: 'CONSTRUCTION' | 'UPGRADE' | 'RETROFIT' | 'OVERHAUL' | 'PUBLIC_PROJECT'; ownerId: string; territoryId: string; buildingType: string }): Promise<FinancialQuote> {
  const row = (await repository.query<{ catalog_id: string; code: string; ownership_scope: 'PRIVATE' | 'PUBLIC'; construction_credit_units: string; definition_version: number; owner_economic_id: string; account_purpose: string }>(
    `SELECT c.id AS catalog_id, c.code, c.ownership_scope, c.construction_credit_units::TEXT, c.definition_version,
            chosen.economic_id AS owner_economic_id, chosen.account_purpose
       FROM building_catalog c
       JOIN territories t ON t.id = $2 AND t.status = 'ACTIVE'
       JOIN humans h ON h.id = $3 AND h.status = 'ACTIVE'
       JOIN owner_registry house ON house.id = h.house_id AND house.owner_type = 'HOUSE'
       JOIN owner_registry corporation ON corporation.id = t.corporation_id AND corporation.owner_type = 'CORPORATION'
       CROSS JOIN LATERAL (SELECT house.economic_id, 'WALLET'::TEXT AS account_purpose WHERE c.ownership_scope = 'PRIVATE'
                           UNION ALL SELECT corporation.economic_id, 'TREASURY'::TEXT WHERE c.ownership_scope = 'PUBLIC') chosen
      WHERE (c.id = $1 OR c.code = $1 OR lower(c.code) = lower($1))
      LIMIT 1`, [input.buildingType, input.territoryId, input.ownerId])).rows[0];
  if (!row) throw new Error('Building quote definition or ownership context not found');
  const multiplier = MULTIPLIERS[input.quoteType];
  const base = (BigInt(row.construction_credit_units) * multiplier.bps / 10000n).toString();
  return creditQuote({ quoteType: input.quoteType, baseUnits: base, payer: { principalId: row.owner_economic_id, accountPurpose: row.account_purpose }, recipientTreatment: { type: 'SYSTEM_SETTLEMENT', principalId: 'ECON-CONSTRUCTION-SETTLEMENT', accountPurpose: 'SYSTEM_ACCOUNT' }, ruleVersion: multiplier.rule, definitionVersion: String(row.definition_version), subject: { catalogId: row.catalog_id, code: row.code, ownershipScope: row.ownership_scope } });
}

export async function getFinancialQuote(repository: PostgresRepository, input: { quoteType: FinancialQuote['quoteType']; ownerId: string; territoryId?: string; buildingType?: string; technologyId?: string; licenseId?: string }): Promise<FinancialQuote> {
  if (['CONSTRUCTION', 'UPGRADE', 'RETROFIT', 'OVERHAUL', 'PUBLIC_PROJECT'].includes(input.quoteType)) {
    if (!input.territoryId || !input.buildingType) throw new Error('Territory and building definition are required');
    return catalogQuote(repository, { quoteType: input.quoteType as 'CONSTRUCTION' | 'UPGRADE' | 'RETROFIT' | 'OVERHAUL' | 'PUBLIC_PROJECT', ownerId: input.ownerId, territoryId: input.territoryId, buildingType: input.buildingType });
  }
  if (input.quoteType === 'RESEARCH' || input.quoteType === 'TECHNOLOGY_ADOPTION') {
    if (!input.technologyId) throw new Error('Technology definition is required');
    const row = (await repository.query<{ economic_id: string; cost: string; definition_version: number; code: string }>(
      `SELECT o.economic_id, tc.research_credit_cost_units::TEXT AS cost, tc.definition_version, tc.code
         FROM humans h JOIN house_affiliations ha ON ha.house_id = h.house_id AND ha.status = 'ACTIVE'
         JOIN owner_registry o ON o.id = ha.corporation_id AND o.owner_type = 'CORPORATION'
         JOIN technology_catalog tc ON (tc.id = $2 OR tc.code = $2) AND tc.status = 'ACTIVE'
        WHERE h.id = $1 ORDER BY tc.definition_version DESC LIMIT 1`, [input.ownerId, input.technologyId])).rows[0];
    if (!row) throw new Error('Technology quote definition or Corporation context not found');
    return creditQuote({ quoteType: input.quoteType, baseUnits: row.cost, payer: { principalId: row.economic_id, accountPurpose: 'OPERATIONS' }, recipientTreatment: { type: 'SYSTEM_RESEARCH_ACCOUNT', principalId: 'SYSTEM', accountPurpose: 'SYSTEM_ACCOUNT' }, ruleVersion: input.quoteType === 'RESEARCH' ? 'technology-research-v1' : 'technology-adoption-v1', definitionVersion: String(row.definition_version), subject: { technologyId: input.technologyId, code: row.code } });
  }
  if (!input.licenseId) throw new Error('License definition is required');
  const row = (await repository.query<{ licensee_economic_id: string; licensor_economic_id: string; licensee_type: string; licensor_type: string; upfront_fee_units: string; daily_fee_units: string; rules_version: string }>(`SELECT c.licensee_economic_id, c.licensor_economic_id, licensee.owner_type AS licensee_type, licensor.owner_type AS licensor_type,
      c.upfront_fee_units::TEXT, c.daily_fee_units::TEXT, c.rules_version
    FROM technology_license_contracts c
    JOIN owner_registry licensee ON licensee.economic_id = c.licensee_economic_id
    JOIN owner_registry licensor ON licensor.economic_id = c.licensor_economic_id
    WHERE c.id = $1`, [input.licenseId])).rows[0];
  if (!row) throw new Error('License quote definition not found');
  return creditQuote({ quoteType: 'LICENSING', baseUnits: row.upfront_fee_units, payer: { principalId: row.licensee_economic_id, accountPurpose: row.licensee_type === 'HOUSE' ? 'WALLET' : 'OPERATIONS' }, recipientTreatment: { type: 'EXTERNAL_TRANSFER', principalId: row.licensor_economic_id, accountPurpose: row.licensor_type === 'HOUSE' ? 'WALLET' : 'OPERATIONS' }, ruleVersion: row.rules_version, definitionVersion: row.rules_version, subject: { licenseId: input.licenseId, dailyFeeUnits: row.daily_fee_units } });
}
