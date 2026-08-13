import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
let Pool;
try { ({ Pool } = require('pg')); } catch { Pool = null; }

export function createDatabase(connectionString = process.env.DATABASE_URL) {
  if (!connectionString || !Pool) return null;
  const pool = new Pool({ connectionString, max: Number(process.env.PG_POOL_SIZE || 5) });
  return {
    async saveSuccession(successor) { await pool.query(`insert into succession_plans (human_id, successor_name, registered_game_day, estate_period_days) values ('H-0044',$1,$2,$3) on conflict (human_id) do update set successor_name=excluded.successor_name, registered_game_day=excluded.registered_game_day`, [successor.name, successor.registeredOnDay, 30]); },
    async saveWorld(world) { await pool.query(`update world_state set game_day=$1, game_minute=$2, health=$3, market_batch_seconds=$4 where id='WORLD'`, [world.day, world.minute, world.health, world.batch]); },
    async saveBusiness(business) { await pool.query(`update businesses set policy=$1, condition=$2 where id=$3`, [business.policy, business.condition, business.id]); },
    async saveResources(resources) { for (const [resource, amount] of Object.entries(resources)) await pool.query(`insert into resource_balances (owner_id, resource, amount) values ('H-0044',$1,$2) on conflict (owner_id,resource) do update set amount=excluded.amount`, [resource, amount]); },
    async saveTechnology(technology) { await pool.query(`update technologies set progress=$1 where id=$2`, [technology.progress, technology.id]); },
    async loadCanonical() {
      const [world, human, resources, business, technology, orders, proposalBallots] = await Promise.all([
        pool.query('select game_day, game_minute, health, market_batch_seconds from world_state where id=$1', ['WORLD']),
        pool.query('select id, display_name, standing, legacy from humans where id=$1', ['H-0044']),
        pool.query('select resource, amount from resource_balances where owner_id=$1', ['H-0044']),
        pool.query('select id, name, policy, condition from businesses where id=$1', ['B-1048']),
        pool.query('select id, name, progress from technologies where id=$1', ['TECH-001']),
        pool.query(`select id, human_id, product, quantity, limit_price, filled_quantity, status, extract(epoch from created_at)*1000 as created_at from market_orders where status in ('open','partial') order by created_at`),
        pool.query(`select proposal_id, human_id, choice from ballots where proposal_id=$1`, ['042'])
      ]);
      return { world: world.rows[0], human: human.rows[0], resources: resources.rows, business: business.rows[0], technology: technology.rows[0], orders: orders.rows, ballots: proposalBallots.rows };
    },
    async saveLedger(entry) { await pool.query(`insert into ledger_entries (id, game_day, debit_account, credit_account, amount, currency, reason_type, reason_id, correlation_id) values ($1,$2,$3,$4,$5,$6,$7,$8,$9) on conflict (id) do nothing`, [entry.id, entry.gameDay, entry.debit, entry.credit, entry.amount, entry.currency, entry.reason, entry.reasonId || null, entry.correlationId]); },
    async saveOrder(order) { await pool.query(`insert into market_orders (id, human_id, product, quantity, limit_price, filled_quantity, status, created_at) values ($1,$2,$3,$4,$5,$6,$7,to_timestamp($8/1000.0)) on conflict (id) do update set filled_quantity=excluded.filled_quantity,status=excluded.status`, [order.id, order.humanId === 'amara' ? 'H-0044' : order.humanId, order.product, order.quantity, order.limitPrice, order.filled, order.status, order.createdAt]); },
    async saveBallot(proposalId, humanId, choice) { await pool.query(`insert into ballots (proposal_id, human_id, choice) values ($1,$2,$3) on conflict (proposal_id,human_id) do nothing`, [proposalId, humanId === 'amara' ? 'H-0044' : humanId, choice]); },
    async health() { const result = await pool.query('select 1 as ok'); return result.rows[0].ok === 1; }
  };
}
