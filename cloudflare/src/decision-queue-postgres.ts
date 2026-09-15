import type { PostgresRepository } from './repository.ts';
import { generateDecisionQueue, type DecisionQueueItem } from './decision-queue.ts';

export async function getDecisionQueue(repository: PostgresRepository, houseId: string, limit = 20): Promise<{ decisions: DecisionQueueItem[]; generatedFrom: string; gameDay: number }> {
  const [world, house, needs, proposals, obligations, research, market, buildings] = await Promise.all([
    repository.query<{ game_day: string }>("SELECT game_day FROM world_state WHERE id = 'WORLD'"),
    repository.query<{ has_successor: boolean }>(`SELECT successor_name IS NOT NULL AS has_successor FROM house_succession_plans WHERE house_id = $1`, [houseId]),
    repository.query<{ need_code: string; demand_units: string; allocated_units: string; shortfall_units: string; risk_level: string }>(`SELECT DISTINCT ON (need_code) need_code, demand_units::TEXT, allocated_units::TEXT, shortfall_units::TEXT, risk_level FROM house_need_assessments WHERE house_id = $1 ORDER BY need_code, game_day DESC`, [houseId]),
    repository.query<{ id: string; title: string; status: string }>(`SELECT id, action_type AS title, status FROM proposals WHERE status IN ('OPEN', 'open') AND (institution_id IS NULL OR institution_id IN (SELECT corporation_id FROM house_affiliations WHERE house_id = $1 AND status = 'ACTIVE')) ORDER BY created_game_day, id`, [houseId]),
    repository.query<{ unpaid: string }>(`SELECT COALESCE(SUM(principal_due_units + interest_due_units - paid_units), 0)::TEXT AS unpaid FROM financial_obligations f JOIN owner_registry o ON o.economic_id = f.debtor_economic_id WHERE o.id = $1 AND f.status IN ('DUE','PARTIAL','ARREARS')`, [houseId]),
    repository.query<{ progress: string }>(`SELECT COALESCE(ROUND(progress_research_points * 100.0 / NULLIF(required_research_points, 0), 2), 0)::TEXT AS progress FROM corporation_research_projects p JOIN owner_registry o ON o.economic_id = p.corporation_economic_id JOIN house_affiliations ha ON ha.corporation_id = o.id AND ha.house_id = $1 AND ha.status = 'ACTIVE' WHERE p.status IN ('QUEUED','ACTIVE') ORDER BY p.priority, p.id LIMIT 1`, [houseId]),
    repository.query<{ product: string; supply: string; demand: string; price: string }>(`SELECT LOWER(REPLACE(i.symbol, 'SPOT-', '')) AS product,
              COALESCE(s.open_sell_units, 0)::TEXT AS supply,
              COALESCE(s.open_buy_units, 0)::TEXT AS demand,
              COALESCE(s.last_clearing_price_units, 0)::TEXT AS price
         FROM market_instruments i
         LEFT JOIN market_instrument_state s ON s.instrument_id = i.id
        WHERE i.instrument_type = 'SPOT' AND i.status = 'ACTIVE'
        ORDER BY i.symbol`),
    repository.query<{ id: string; status: string; utilization_bps: string }>(`SELECT b.id, b.status,
              COALESCE(latest.utilization_bps, 10000)::TEXT AS utilization_bps
         FROM buildings b
         JOIN owner_registry o ON o.economic_id = b.owner_economic_id
         LEFT JOIN LATERAL (
           SELECT utilization_bps
             FROM building_settlement_journals
            WHERE building_id = b.id
            ORDER BY game_day DESC
            LIMIT 1
         ) latest ON TRUE
        WHERE o.id = $1 AND b.status = 'ACTIVE'
        ORDER BY b.id`, [houseId]),
  ]);
  const gameDay = Number(world.rows[0]?.game_day ?? 0);
  const decisions = generateDecisionQueue({
    gameDay,
    needs: needs.rows,
    proposals: proposals.rows,
    market: market.rows,
    buildings: buildings.rows,
    finance: { unpaid_tax: obligations.rows[0]?.unpaid ?? '0' },
    technology: { progress: research.rows[0]?.progress ?? '100' },
    house: { successor_id: house.rows[0]?.has_successor ? 'registered' : null },
  }).slice(0, Math.max(1, Math.min(100, limit)));
  return { decisions, generatedFrom: 'postgres-canonical-facts', gameDay };
}
