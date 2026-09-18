import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {
  SettlementCatchupBarrierError,
  isSettlementBarrierError,
  assertEconomyCaughtUp,
  runEconomicMutation,
  withSettledEconomy,
} from '../cloudflare/src/settlement-barrier-postgres.ts';
import { errorResponse } from '../cloudflare/src/errors.ts';

test('SettlementCatchupBarrierError serializes properly when catching up', () => {
  const cursor = {
    settledThroughGameDay: 8,
    lastClosedGameDay: 9,
    backlogDays: 1,
    status: 'CATCHING_UP',
    failedGameDay: null,
    failedPhase: null,
    failedError: null,
  };

  const err = new SettlementCatchupBarrierError(cursor, 10);
  assert.equal(err.name, 'SettlementCatchupBarrierError');
  assert.equal(err.code, 'WORLD_SETTLEMENT_CATCHING_UP');
  assert.equal(err.statusCode, 409);
  assert.equal(err.status, 409);
  assert.equal(err.currentGameDay, 10);
  assert.equal(err.settledThroughGameDay, 8);
  assert.equal(err.lastClosedGameDay, 9);
  assert.equal(err.backlogDays, 1);
  assert.ok(isSettlementBarrierError(err));

  const resp = err.toResponse();
  assert.equal(resp.status, 409);
});

test('SettlementCatchupBarrierError serializes properly when failed', async () => {
  const cursor = {
    settledThroughGameDay: 7,
    lastClosedGameDay: 9,
    backlogDays: 2,
    status: 'FAILED',
    failedGameDay: 8,
    failedPhase: 'MARKET_SETTLEMENT',
    failedError: 'Deadlock detected',
  };

  const err = new SettlementCatchupBarrierError(cursor, 10);
  assert.equal(err.name, 'SettlementCatchupBarrierError');
  assert.equal(err.code, 'WORLD_SETTLEMENT_FAILED');
  assert.equal(err.statusCode, 409);
  assert.equal(err.failedGameDay, 8);
  assert.equal(err.failedPhase, 'MARKET_SETTLEMENT');
  assert.equal(err.failedError, 'Deadlock detected');

  const resp = err.toResponse();
  assert.equal(resp.status, 409);
  const data = await resp.json();
  assert.equal(data.ok, false);
  assert.equal(data.code, 'WORLD_SETTLEMENT_FAILED');
  assert.equal(data.failedGameDay, 8);
  assert.equal(data.failedPhase, 'MARKET_SETTLEMENT');
});

test('errorResponse formats SettlementCatchupBarrierError as 409 JSON', async () => {
  const cursor = {
    settledThroughGameDay: 3,
    lastClosedGameDay: 4,
    backlogDays: 1,
    status: 'CATCHING_UP',
    failedGameDay: null,
    failedPhase: null,
    failedError: null,
  };

  const err = new SettlementCatchupBarrierError(cursor, 5);
  const resp = errorResponse(err);
  assert.equal(resp.status, 409);
  const body = await resp.json();
  assert.equal(body.ok, false);
  assert.equal(body.code, 'WORLD_SETTLEMENT_CATCHING_UP');
  assert.equal(body.settledThroughGameDay, 3);
  assert.equal(body.lastClosedGameDay, 4);
});

function createMockRepo({ gameDay = 10, gameMinute = 720, settledThrough = 9, controlStatus = 'active', failureRun = null } = {}) {
  const repo = {
    async query(sql, params) {
      const sqlStr = typeof sql === 'string' ? sql : sql?.text || '';
      if (sqlStr.includes('earth_get_current_game_time')) {
        return {
          rows: [{
            game_day: gameDay,
            game_minute: gameMinute,
            total_game_minutes: gameDay * 1440 + gameMinute,
            genesis_at: new Date(Date.now() - 1000000).toISOString(),
            server_now: new Date().toISOString(),
            elapsed_real_seconds: 1000,
            real_seconds_per_game_minute: 1,
          }],
        };
      }
      if (sqlStr.includes('daily_settlement_control')) {
        return {
          rows: [{
            status: controlStatus,
            settled_through_game_day: settledThrough,
          }],
        };
      }
      if (sqlStr.includes('daily_settlement_runs')) {
        return {
          rows: failureRun ? [failureRun] : [],
        };
      }
      return { rows: [] };
    },
    async transaction(callback) {
      return callback(this);
    },
  };
  return repo;
}

test('assertEconomyCaughtUp passes when settled through lastClosedGameDay', async () => {
  // Day 10 -> lastClosedGameDay = 9. settledThrough = 9 -> caught up!
  const mockRepo = createMockRepo({ gameDay: 10, gameMinute: 720, settledThrough: 9 });

  const context = await assertEconomyCaughtUp(mockRepo);
  assert.equal(context.gameDay, 10);
  assert.equal(context.gameMinute, 720);
  assert.equal(context.settledThroughGameDay, 9);
  assert.equal(context.lastClosedGameDay, 9);
  assert.equal(context.backlogDays, 0);
  assert.equal(context.status, 'CURRENT');
});

test('assertEconomyCaughtUp blocks with SettlementCatchupBarrierError when behind', async () => {
  // Day 10 -> lastClosedGameDay = 9. settledThrough = 8 -> 1 day behind!
  const mockRepo = createMockRepo({ gameDay: 10, gameMinute: 720, settledThrough: 8 });

  await assert.rejects(
    () => assertEconomyCaughtUp(mockRepo),
    (err) => {
      assert.ok(isSettlementBarrierError(err));
      assert.equal(err.code, 'WORLD_SETTLEMENT_CATCHING_UP');
      assert.equal(err.settledThroughGameDay, 8);
      assert.equal(err.lastClosedGameDay, 9);
      assert.equal(err.backlogDays, 1);
      return true;
    }
  );
});

test('assertEconomyCaughtUp blocks with WORLD_SETTLEMENT_FAILED when next day run failed', async () => {
  // Day 10 -> lastClosedGameDay = 9. settledThrough = 8, day 9 failed.
  const mockRepo = createMockRepo({
    gameDay: 10,
    gameMinute: 720,
    settledThrough: 8,
    failureRun: {
      status: 'failed',
      current_phase: 'MARKET_SETTLEMENT',
      error_message: 'Deadlock on batch execution',
    },
  });

  await assert.rejects(
    () => assertEconomyCaughtUp(mockRepo),
    (err) => {
      assert.ok(isSettlementBarrierError(err));
      assert.equal(err.code, 'WORLD_SETTLEMENT_FAILED');
      assert.equal(err.failedGameDay, 9);
      assert.equal(err.failedPhase, 'MARKET_SETTLEMENT');
      assert.equal(err.failedError, 'Deadlock on batch execution');
      return true;
    }
  );
});

test('runEconomicMutation executes mutation within transaction when caught up', async () => {
  let executed = false;
  const mockRepo = createMockRepo({ gameDay: 12, gameMinute: 100, settledThrough: 11 });

  const result = await runEconomicMutation(mockRepo, async (tx, clock) => {
    executed = true;
    assert.equal(clock.gameDay, 12);
    assert.equal(clock.gameMinute, 100);
    assert.equal(clock.settledThroughGameDay, 11);
    return { ok: true, mutated: true };
  });

  assert.equal(executed, true);
  assert.deepEqual(result, { ok: true, mutated: true });
});

test('architecture scan: all critical economic mutation modules use runEconomicMutation / assertEconomyCaughtUp', () => {
  const root = path.resolve(process.cwd(), 'cloudflare/src');

  const filesToCheck = [
    { file: 'v5-building-postgres.ts', symbols: ['purchaseV5Building', 'suspendBuilding', 'reactivateBuilding'] },
    { file: 'building-investment-postgres.ts', symbols: ['upgradeCorporationBuilding', 'upgradeBuilding', 'retrofitBuilding', 'decommissionBuilding', 'setBuildingOperatingMode'] },
    { file: 'building-age-postgres.ts', symbols: ['startCorporationCapitalProject', 'startBuildingCapitalProject'] },
    { file: 'corporation-building-research-postgres.ts', symbols: ['startCorporationBuildingResearch'] },
    { file: 'banking-postgres.ts', symbols: ['originateBankLoan', 'repayBankLoan', 'addBankLoanGuarantee'] },
    { file: 'global-bank-postgres.ts', symbols: ['createBankDeposit', 'withdrawBankDeposit'] },
    { file: 'territory-rights-postgres.ts', symbols: ['acquireTerritoryRight', 'releaseTerritoryRight'] },
    { file: 'commons-dividends-postgres.ts', symbols: ['declareCommonsDividend'] },
    { file: 'corporation-fiscal-postgres.ts', symbols: ['spendCorporationBudget'] },
    { file: 'credit-settlement-postgres.ts', symbols: ['externalTransfer', 'internalTransfer', 'settleObligation'] },
    { file: 'market-postgres.ts', symbols: ['submitMarketOrder', 'cancelMarketOrder'] },
  ];

  for (const { file, symbols } of filesToCheck) {
    const fullPath = path.join(root, file);
    assert.ok(fs.existsSync(fullPath), `File must exist: ${file}`);
    const content = fs.readFileSync(fullPath, 'utf8');

    assert.ok(
      content.includes('runEconomicMutation') ||
      content.includes('withSettledEconomy') ||
      content.includes('assertEconomyCaughtUp'),
      `${file} must import and use runEconomicMutation or assertEconomyCaughtUp`
    );

    for (const sym of symbols) {
      assert.ok(
        content.includes(sym),
        `${file} must define ${sym}`
      );
    }
  }
});
