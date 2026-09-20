import type { PostgresRepository } from './repository.ts';
import { WORLD_CONDITION_EFFECT_REGISTRY, type WorldConditionEffect } from './world-conditions.ts';

export type InitiativeOutcome =
  | { type: 'ECONOMIC_MODIFIER'; effectType: WorldConditionEffect; targetKey: string; modifierBps: number; description?: string }
  | { type: 'SERVICE_CAPACITY'; serviceType: string; capacityUnits: string; targetScope: 'EARTH' | 'CORPORATION'; targetId?: string }
  | { type: 'TECHNOLOGY_EFFECT'; technologyId: string; effectCode: string; targetScope: 'EARTH' | 'CORPORATION'; targetId?: string }
  | { type: 'CAPACITY_EFFECT'; capacityCode: string; capacityUnits: string; targetScope: 'EARTH' | 'CORPORATION'; targetId?: string }
  | { type: 'PUBLIC_ASSET'; buildingCatalogId: string; targetScope: 'EARTH' | 'CORPORATION'; targetId?: string }
  | { type: 'PRESTIGE'; label: string; description: string };

const TYPES = new Set(['ECONOMIC_MODIFIER', 'SERVICE_CAPACITY', 'TECHNOLOGY_EFFECT', 'CAPACITY_EFFECT', 'PUBLIC_ASSET', 'PRESTIGE']);
const EFFECT_TYPES = new Set(Object.keys(WORLD_CONDITION_EFFECT_REGISTRY));

function positiveUnits(value: unknown, field: string): string {
  if (!/^\d+$/.test(String(value ?? '')) || BigInt(String(value)) <= 0n) throw new Error(`${field} must be a positive integer`);
  return String(value);
}

export function validateInitiativeOutcome(value: unknown): InitiativeOutcome {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Initiative outcome must be an object');
  const outcome = value as Record<string, unknown>;
  const type = String(outcome.type ?? '');
  if (!TYPES.has(type)) throw new Error(`Unsupported Initiative outcome type: ${type || 'missing'}`);
  if (type === 'ECONOMIC_MODIFIER') {
    if (!EFFECT_TYPES.has(String(outcome.effectType)) || !String(outcome.targetKey ?? '').trim()) throw new Error('Economic modifier requires effectType and targetKey');
    const modifierBps = Number(outcome.modifierBps);
    if (!Number.isInteger(modifierBps) || modifierBps < -5000 || modifierBps > 5000) throw new Error('Economic modifier must be an integer between -5000 and 5000 BPS');
    return { type, effectType: outcome.effectType as WorldConditionEffect, targetKey: String(outcome.targetKey), modifierBps, description: outcome.description == null ? undefined : String(outcome.description) };
  }
  if (type === 'SERVICE_CAPACITY' || type === 'CAPACITY_EFFECT') {
    const targetScope = String(outcome.targetScope) as 'EARTH' | 'CORPORATION';
    if (!['EARTH', 'CORPORATION'].includes(targetScope) || (targetScope === 'CORPORATION' && !String(outcome.targetId ?? '').trim())) throw new Error(`${type} requires a valid target scope`);
    if (type === 'SERVICE_CAPACITY') return { type, serviceType: String(outcome.serviceType ?? '').trim(), capacityUnits: positiveUnits(outcome.capacityUnits, 'Service capacity'), targetScope, targetId: outcome.targetId == null ? undefined : String(outcome.targetId) };
    return { type, capacityCode: String(outcome.capacityCode ?? '').trim(), capacityUnits: positiveUnits(outcome.capacityUnits, 'Capacity effect'), targetScope, targetId: outcome.targetId == null ? undefined : String(outcome.targetId) };
  }
  if (type === 'TECHNOLOGY_EFFECT') {
    const targetScope = String(outcome.targetScope) as 'EARTH' | 'CORPORATION';
    if (!String(outcome.technologyId ?? '').trim() || !String(outcome.effectCode ?? '').trim() || !['EARTH', 'CORPORATION'].includes(targetScope) || (targetScope === 'CORPORATION' && !String(outcome.targetId ?? '').trim())) throw new Error('Technology effect requires technology, effect, and target');
    return { type, technologyId: String(outcome.technologyId), effectCode: String(outcome.effectCode), targetScope, targetId: outcome.targetId == null ? undefined : String(outcome.targetId) };
  }
  if (type === 'PUBLIC_ASSET') {
    if (!String(outcome.buildingCatalogId ?? '').trim() || !['EARTH', 'CORPORATION'].includes(String(outcome.targetScope))) throw new Error('Public asset outcome requires a building catalog and target scope');
    if (outcome.targetScope === 'CORPORATION' && !String(outcome.targetId ?? '').trim()) throw new Error('Corporation public asset requires a Corporation target');
    return { type, buildingCatalogId: String(outcome.buildingCatalogId), targetScope: outcome.targetScope as 'EARTH' | 'CORPORATION', targetId: outcome.targetId == null ? undefined : String(outcome.targetId) };
  }
  if (!String(outcome.label ?? '').trim() || !String(outcome.description ?? '').trim()) throw new Error('Prestige outcome requires a label and description');
  return { type, label: String(outcome.label), description: String(outcome.description) };
}

/** Applies an outcome through its named subsystem bridge, never as a generic program output. */
export async function applyInitiativeOutcome(tx: PostgresRepository, input: { initiativeId: string; outcomeId: string; outcome: InitiativeOutcome; gameDay: number }): Promise<void> {
  const { initiativeId, outcomeId, outcome, gameDay } = input;
  if (outcome.type === 'ECONOMIC_MODIFIER') {
    const conditionId = `INIT-EFFECT-${outcomeId}`;
    await tx.query(`INSERT INTO world_conditions
      (id, condition_code, title, description, source_type, source_id, scope_type,
       effective_from_game_day, rules_version, definition_version, severity)
      VALUES ($1,$2,$3,$4,'GOVERNANCE',$5,'EARTH',$6,'initiative-outcome-v1','initiative-outcome-v1','INFO')
      ON CONFLICT (id) DO NOTHING`, [conditionId, `INITIATIVE:${initiativeId}:${outcome.effectType}`, outcome.effectType, outcome.description ?? `Initiative ${outcome.effectType.toLowerCase()}`, initiativeId, gameDay]);
    await tx.query(`INSERT INTO world_condition_effects
      (id, condition_id, effect_type, target_key, modifier_bps, effect_order)
      VALUES ($1,$2,$3,$4,$5,0)
      ON CONFLICT (condition_id, effect_type, target_key) DO UPDATE SET modifier_bps = EXCLUDED.modifier_bps`,
    [`${conditionId}-MODIFIER`, conditionId, outcome.effectType, outcome.targetKey, outcome.modifierBps]);
    return;
  }
  await tx.query(`INSERT INTO initiative_effect_applications
    (id, initiative_id, outcome_id, effect_type, target_scope, target_id, payload, applied_game_day, status)
    VALUES ($1,$2,$3,$4,$5,$6,$7::JSONB,$8,'APPLIED')
    ON CONFLICT (outcome_id) DO NOTHING`, [`INIT-EFFECT-${outcomeId}`, initiativeId, outcomeId, outcome.type, outcome.targetScope ?? 'EARTH', outcome.targetId ?? null, JSON.stringify(outcome), gameDay]);
}
