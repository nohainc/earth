import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
let Pool;
try { ({ Pool } = require('pg')); } catch { Pool = null; }

export function createDatabase(connectionString = process.env.DATABASE_URL) {
  if (!connectionString || !Pool) return null;
  const pool = new Pool({ connectionString, max: Number(process.env.PG_POOL_SIZE || 5) });
  const readOnly = process.env.DATABASE_READ_ONLY !== 'false';
  const write = (operation) => readOnly ? Promise.resolve() : operation();
  return {
    async saveSuccession(successor) { await write(() => pool.query(`insert into succession_plans (human_id, successor_name, registered_game_day, estate_period_days) values ('H-0044',$1,$2,$3) on conflict (human_id) do update set successor_name=excluded.successor_name, registered_game_day=excluded.registered_game_day`, [successor.name, successor.registeredOnDay, 30])); },
    async saveWorld(world) { await write(() => pool.query(`update world_state set game_day=$1, game_minute=$2, health=$3, market_batch_seconds=$4 where id='WORLD'`, [world.day, world.minute, world.health, world.batch])); },
    async saveBusiness(business) { await write(() => pool.query(`update businesses set policy=$1, condition=$2 where id=$3`, [business.policy, business.condition, business.id])); },
    async saveResources(resources) { await write(async () => { for (const [resource, amount] of Object.entries(resources)) await pool.query(`insert into resource_balances (owner_id, resource, amount) values ('H-0044',$1,$2) on conflict (owner_id,resource) do update set amount=excluded.amount`, [resource, amount]); }); },
    async saveTechnology(technology) { await write(() => pool.query(`update technologies set progress=$1 where id=$2`, [technology.progress, technology.id])); },
    async loadCanonical() {
      // 1. Required queries: must exist in PostgreSQL
      const [worldRes, humanRes] = await Promise.all([
        pool.query('select game_day, game_minute, health, market_batch_seconds from world_state where id=$1', ['WORLD']),
        pool.query(`
          select h.id, h.display_name, h.standing, h.legacy, h.age_years, h.life_status, h.political_eligibility_game_day,
                 coalesce(ab.balance, (select balance from account_balances where owner_id = h.id and currency = 'CREDIT' limit 1), 0) as credits
          from humans h
          left join account_balances ab on ab.account_id = h.account_id and ab.currency = 'CREDIT'
          where h.id = $1
        `, ['H-0044']),
      ]);

      if (!worldRes.rows[0]) {
        throw new Error('Database hydration failed: Required entity missing (world_state WORLD)');
      }
      if (!humanRes.rows[0]) {
        throw new Error('Database hydration failed: Required entity missing (human H-0044)');
      }

      const safeQuery = async (queryText, params = [], fallback = []) => {
        try {
          const res = await pool.query(queryText, params);
          return res.rows;
        } catch {
          return fallback;
        }
      };

      // 2. Optional queries: resilient to missing tables, columns, or empty rows
      const [
        resources,
        businessRows,
        technologyRows,
        orders,
        proposals,
        ballots,
        successionRows,
        institutions,
        cities,
        corporations,
        businesses,
        ledger,
        activeHumansRows,
        membershipRows
      ] = await Promise.all([
        safeQuery('select resource, amount from resource_balances where owner_id=$1', ['H-0044']),
        safeQuery('select id, name, policy, condition from businesses where id=$1', ['B-1048']),
        safeQuery('select id, name, progress from technologies where id=$1', ['TECH-001']),
        safeQuery(`select id, human_id, product, quantity, limit_price, filled_quantity, status, extract(epoch from created_at)*1000 as created_at from market_orders where status in ('open','partial') order by created_at`),
        safeQuery('select id, institution_id, title, body, status, quorum, approval_threshold, implementation_delay_days, outcome, execution_status, correlation_id, closes_game_day, closes_game_minute, implementation_game_day, implementation_game_minute, extract(epoch from opens_at)*1000 as opens_at, extract(epoch from closes_at)*1000 as closes_at, extract(epoch from implementation_at)*1000 as implementation_at, extract(epoch from resolved_at)*1000 as resolved_at, extract(epoch from executed_at)*1000 as executed_at from proposals order by id asc limit 20'),
        safeQuery('select proposal_id, human_id, choice, weight from ballots'),
        safeQuery('select successor_name, registered_game_day, estate_period_days from succession_plans where human_id=$1', ['H-0044']),
        safeQuery('select id, kind, name, status from institutions'),
        safeQuery('select id, institution_id, residents, housing_capacity, energy_capacity, connectivity_capacity, health_capacity, treasury from cities'),
        safeQuery('select id, institution_id, member_count, treasury, constitution_version from corporations'),
        safeQuery('select id, owner_id, name, policy, condition, status, sector from businesses'),
        safeQuery('select id, game_day, debit_account, credit_account, amount, currency, reason_type, correlation_id from ledger_entries order by created_at desc limit 25'),
        safeQuery("select count(*)::integer as count from humans where life_status = 'active'"),
        safeQuery(`
          select m.human_id, m.corporation_id, m.city_id, c.member_count, ci.residents
          from memberships m
          left join corporations c on c.id = m.corporation_id
          left join cities ci on ci.id = m.city_id
          where m.human_id = $1
          limit 1
        `, ['H-0044'])
      ]);

      const mem = membershipRows[0] || null;
      const pop = Number(mem?.member_count ?? mem?.residents ?? 0);
      const votingWeight = Math.round((1 + Math.min(2, pop / 100)) * 1000) / 1000;
      return {
        world: worldRes.rows[0],
        human: humanRes.rows[0],
        resources,
        business: businessRows[0] || null,
        technology: technologyRows[0] || null,
        orders,
        proposals,
        ballots,
        succession: successionRows[0] || null,
        institutions,
        cities,
        corporations,
        businesses,
        ledger,
        activeHumans: Number(activeHumansRows[0]?.count ?? 0),
        membership: mem,
        votingWeight
      };
    },
    async saveLedger(entry) { await write(() => pool.query(`insert into ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, correlation_id) values ($1,$2,$3,$4,$5,$6,$7,$8,$9) on conflict (id) do nothing`, [entry.id, entry.gameDay, entry.debit, entry.credit, entry.amount, entry.currency, entry.reason, entry.reasonId || null, entry.correlationId])); },
    async saveOrder(order) { await write(() => pool.query(`insert into market_orders (id, human_id, product, quantity, limit_price, filled_quantity, status, created_at) values ($1,$2,$3,$4,$5,$6,$7,to_timestamp($8/1000.0)) on conflict (id) do update set filled_quantity=excluded.filled_quantity,status=excluded.status`, [order.id, order.humanId === 'amara' ? 'H-0044' : order.humanId, order.product, order.quantity, order.limitPrice, order.filled, order.status, order.createdAt])); },
    async saveBallot(proposalId, humanId, choice, weight = 1) { await write(() => pool.query(`insert into ballots (proposal_id, human_id, choice, weight) values ($1,$2,$3,$4) on conflict (proposal_id,human_id) do nothing`, [proposalId, humanId === 'amara' ? 'H-0044' : humanId, choice, weight])); },
    async loadMarketHistory(product, days = 30) {
      const limit = Math.max(2, Math.min(Number(days) || 30, 90));
      const result = await pool.query(`
        select game_day, close_price
        from market_ohlc_snapshots
        where commodity = $1
        order by game_day desc
        limit $2
      `, [product, limit]);
      return result.rows.reverse();
    },
    readOnly,
    async health() { const result = await pool.query('select 1 as ok'); return result.rows[0].ok === 1; }
  };
}
