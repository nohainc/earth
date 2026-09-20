import test from 'node:test';
import assert from 'node:assert/strict';
import {
  normalizeHouseCommodityPosition,
} from '../cloudflare/src/market-house-position.ts';
import { serializeMarketOrder } from '../cloudflare/src/market-order-read-model.ts';
// Keep the fixed-point and lifecycle regression suite in the mandatory Market certification run.
import './market-regression-v5.test.mjs';

test('normalizes atomic resource balances without losing quantity scale', () => {
  const position = normalizeHouseCommodityPosition({
    product: 'food',
    current_units: '10000000',
    reserved_units: '2500000',
  });

  assert.equal(position.currentQuantity, '10.000000');
  assert.equal(position.reservedQuantity, '2.500000');
  assert.equal(position.availableQuantity, '7.500000');
  assert.equal(position.availableUnits, '7500000');
});

test('partial sell reservations reduce MAX sell to the available position', () => {
  const position = normalizeHouseCommodityPosition({
    product: 'food',
    current_units: '10000000',
    reserved_units: '4000000',
  });

  assert.equal(position.currentQuantity, '10.000000');
  assert.equal(position.reservedQuantity, '4.000000');
  assert.equal(position.availableQuantity, '6.000000');
});

test('inconsistent reservations fail closed instead of creating sellable stock', () => {
  assert.throws(
    () => normalizeHouseCommodityPosition({
      product: 'food',
      current_units: '10000000',
      reserved_units: '10000001',
    }),
    /exceeds current balance/,
  );
});

test('shared Market order serializer exposes authoritative aggregates', () => {
  const order = serializeMarketOrder({
    id: 'ORD-1', instrument_id: 'SPOT-FOOD', symbol: 'SPOT-FOOD',
    instrument_status: 'ACTIVE', instrument_rules_version: 'spot-v1',
    base_asset_id: 2, base_asset_code: 'FOOD', quote_asset_id: 1,
    quote_asset_code: 'CREDIT', side: 'SELL', status: 'CANCELLED',
    quantity_units: '10000000', remaining_units: '0',
    filled_quantity_units: '7500000', limit_price_units: '250',
    initial_escrow_units: '10000000', reserved_escrow_units: '0',
    escrow_asset_id: 2, reservation_status: 'RELEASED',
    released_escrow_units: '2500000', cancellation_refund_units: '0',
    average_price_units: '240', gross_value_units: '1800',
    fees_paid_units: '125', fill_count: 2,
    source_type: 'MANUAL',
  });
  assert.equal(order.quantity, '10.000000');
  assert.equal(order.filledQuantity, '7.500000');
  assert.equal(order.releasedEscrow, '2.500000');
  assert.equal(order.feesPaid, '1.25');
  assert.equal(order.filledGrossValue, '18.00');
  assert.equal(order.weightedAverageFillPrice, '2.40');
  assert.equal(order.remainingReservation, '0.000000');
  assert.equal(order.instrument?.baseAsset.code, 'FOOD');
});
