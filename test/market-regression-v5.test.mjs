import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {
  calculateFeeUnits,
  calculateQuoteUnits,
  displayPriceToUnits,
  displayQuantityToUnits,
  priceUnitsToDisplayPrice,
  unitsToDisplayQuantity,
} from '../cloudflare/src/market-units.ts';
import { formatCreditUnits } from '../cloudflare/src/money.ts';
import { MARKET_ASSET_IDS, spotInstrumentSymbol } from '../cloudflare/src/market-model.ts';
import { serializeMarketOrder } from '../cloudflare/src/market-order-read-model.ts';

const api = fs.readFileSync(new URL('../cloudflare/src/market-api.ts', import.meta.url), 'utf8');
const market = fs.readFileSync(new URL('../cloudflare/src/market-postgres.ts', import.meta.url), 'utf8');
const policy = fs.readFileSync(new URL('../cloudflare/src/house-policy-execution.ts', import.meta.url), 'utf8');
const dto = fs.readFileSync(new URL('../cloudflare/src/types/market.dto.ts', import.meta.url), 'utf8');

test('Market uses exact commodity, price, and CREDIT scales at the boundary', () => {
  assert.equal(displayQuantityToUnits('10'), 10_000_000n);
  assert.equal(displayPriceToUnits('2.50'), 250n);
  assert.equal(unitsToDisplayQuantity('9007199254740991000000'), '9007199254740991.000000');
  assert.equal(priceUnitsToDisplayPrice(250n), '2.50');
  assert.equal(formatCreditUnits(50_000n), '500.00');
  assert.equal(calculateQuoteUnits(10_000_000n, 250n), 2_500n);
});

test('fee-bearing BUY escrow and quote/submit conversion use the same integer math', () => {
  const quantityUnits = displayQuantityToUnits('10');
  const priceUnits = displayPriceToUnits('2.50');
  const quoteUnits = calculateQuoteUnits(quantityUnits, priceUnits);
  const feeUnits = calculateFeeUnits(quoteUnits, '0.05');
  assert.equal(quoteUnits, 2_500n);
  assert.equal(feeUnits, 125n);
  assert.equal(quoteUnits + feeUnits, 2_625n);
  assert.match(api, /displayQuantityToUnits\(quantity\)/);
  assert.match(api, /displayPriceToUnits\(limitPrice\)/);
  assert.match(market, /displayQuantityToUnits\(input\.quantity\)/);
  assert.match(market, /displayPriceToUnits\(input\.limitPrice\)/);
});

test('partial, filled, and cancelled orders preserve authoritative aggregates', () => {
  const base = {
    id: 'ORD-1', instrument_id: 'SPOT-FOOD', symbol: 'SPOT-FOOD', instrument_status: 'ACTIVE',
    instrument_rules_version: 'spot-v1', base_asset_id: 6, base_asset_code: 'FOOD', quote_asset_id: 1,
    quote_asset_code: 'CREDIT', side: 'BUY', limit_price_units: '250', quantity_units: '10000000',
    remaining_units: '6000000', filled_quantity_units: '4000000', average_price_units: '240', gross_value_units: '960',
    fees_paid_units: '48', fill_count: 2, initial_escrow_units: '2625', reserved_escrow_units: '1577',
    escrow_asset_id: 1, reservation_status: 'PARTIAL', cancellation_refund_units: '1048',
    released_escrow_units: '1048', source_type: 'MANUAL', status: 'PARTIAL',
  };
  const partial = serializeMarketOrder(base);
  assert.equal(partial.status, 'PARTIAL');
  assert.equal(partial.quantity, '10.000000');
  assert.equal(partial.filledQuantity, '4.000000');
  assert.equal(partial.remainingQuantity, '6.000000');
  assert.equal(partial.totalFeePaid, '0.48');
  assert.equal(partial.remainingReservation, '15.77');
  assert.equal(partial.cancellationRefund, '10.48');

  const cancelled = serializeMarketOrder({ ...base, status: 'CANCELLED', remaining_units: '0', reserved_escrow_units: '0', reservation_status: 'RELEASED' });
  assert.equal(cancelled.status, 'CANCELLED');
  assert.equal(cancelled.remainingReservation, '0.00');
});

test('open and historical order contracts use one serializer and real lifecycle filters', () => {
  assert.match(api, /path === '\/api\/market\/orders\/my' && request\.method === 'GET'/);
  assert.match(api, /readMarketOrderRows/);
  assert.match(api, /serializeMarketOrder\(row\)/);
  assert.match(market, /readMarketOrderRows\(repository, \{ product, limit: 100 \}\)/);
  assert.match(policy, /submitMarketOrder\(repository/);
  assert.match(policy, /sourceType: 'HOUSE_POLICY'/);
  assert.match(dto, /export type MarketOrder/);
});

test('all five canonical commodity instruments and candle fields remain typed', () => {
  const products = ['material', 'components', 'energy', 'compute', 'food'];
  assert.deepEqual(products.map(spotInstrumentSymbol), [
    'SPOT-MATERIAL', 'SPOT-COMPONENTS', 'SPOT-ENERGY', 'SPOT-COMPUTE', 'SPOT-FOOD',
  ]);
  assert.deepEqual(MARKET_ASSET_IDS, { CREDIT: 1, MATERIAL: 2, COMPONENTS: 3, ENERGY: 4, COMPUTE: 5, FOOD: 6 });
  assert.match(api, /open_price_units/);
  assert.match(api, /high_price_units/);
  assert.match(api, /low_price_units/);
  assert.match(api, /close_price_units/);
  assert.match(api, /unitsToDisplayQuantity\(String\(row\.volume_units/);
  assert.match(dto, /export type MarketCandle/);
  assert.match(dto, /volume: string/);
});

test('Market API never converts authoritative quantities or prices through Number', () => {
  assert.doesNotMatch(api, /function numberUnits/);
  assert.doesNotMatch(api, /Number\(BigInt\(String\(row\.(quantity|volume|gross_quote|buyer_fee|seller_fee)_units/);
  assert.match(api, /formatCreditUnits\(BigInt\(String\(row\.gross_quote_units/);
  assert.match(api, /formatCreditUnits\(BigInt\(String\(row\.buyer_fee_units/);
});
