export type ClearingOrder = {
  id: string;
  ownerId: string;
  side: 'BUY' | 'SELL';
  quantityUnits: bigint;
  filledUnits?: bigint;
  limitPriceUnits: bigint;
  sequenceNo: bigint;
};

export type MarketFill = { buyOrderId: string; sellOrderId: string; quantityUnits: bigint; priceUnits: bigint };
export type SelfTradeAction = { cancelledOrderId: string; preventedUnits: bigint; counterpartyOrderId: string };
export type ClearingResult = {
  clearingPriceUnits: bigint | null;
  fills: MarketFill[];
  unfilledOrders: Array<{ orderId: string; remainingUnits: bigint }>;
  selfTradeActions: SelfTradeAction[];
  statistics: {
    candidateCount: number;
    demandUnits: bigint;
    supplyUnits: bigint;
    executableUnits: bigint;
    selfTradePreventedUnits: bigint;
  };
};

function remaining(order: ClearingOrder): bigint {
  const value = order.quantityUnits - (order.filledUnits ?? 0n);
  return value > 0n ? value : 0n;
}

function absolute(value: bigint): bigint {
  return value < 0n ? -value : value;
}

function compareBuy(a: ClearingOrder, b: ClearingOrder): number {
  return a.limitPriceUnits > b.limitPriceUnits ? -1 : a.limitPriceUnits < b.limitPriceUnits ? 1 : a.sequenceNo < b.sequenceNo ? -1 : a.sequenceNo > b.sequenceNo ? 1 : a.id.localeCompare(b.id);
}

function compareSell(a: ClearingOrder, b: ClearingOrder): number {
  return a.limitPriceUnits < b.limitPriceUnits ? -1 : a.limitPriceUnits > b.limitPriceUnits ? 1 : a.sequenceNo < b.sequenceNo ? -1 : a.sequenceNo > b.sequenceNo ? 1 : a.id.localeCompare(b.id);
}

/** Pure deterministic call auction. It never performs I/O or mutates its inputs. */
export function clearMarketAuction(input: {
  previousClearingPriceUnits: bigint;
  buyOrders: ClearingOrder[];
  sellOrders: ClearingOrder[];
}): ClearingResult {
  const candidates = new Set<bigint>([input.previousClearingPriceUnits]);
  for (const order of [...input.buyOrders, ...input.sellOrders]) candidates.add(order.limitPriceUnits);
  const prices = [...candidates].filter((price) => price > 0n).sort((a, b) => a < b ? -1 : a > b ? 1 : 0);
  let best: { price: bigint; executable: bigint; imbalance: bigint } | null = null;
  for (const price of prices) {
    const demand = input.buyOrders.filter((order) => order.limitPriceUnits >= price).reduce((sum, order) => sum + remaining(order), 0n);
    const supply = input.sellOrders.filter((order) => order.limitPriceUnits <= price).reduce((sum, order) => sum + remaining(order), 0n);
    const executable = demand < supply ? demand : supply;
    const candidate = { price, executable, imbalance: absolute(demand - supply) };
    if (!best || executable > best.executable || (executable === best.executable && (candidate.imbalance < best.imbalance || (candidate.imbalance === best.imbalance && (absolute(price - input.previousClearingPriceUnits) < absolute(best.price - input.previousClearingPriceUnits) || (absolute(price - input.previousClearingPriceUnits) === absolute(best.price - input.previousClearingPriceUnits) && price < best.price)))))) best = candidate;
  }
  if (!best || best.executable === 0n) return { clearingPriceUnits: best?.price ?? null, fills: [], unfilledOrders: [...input.buyOrders, ...input.sellOrders].map((order) => ({ orderId: order.id, remainingUnits: remaining(order) })), selfTradeActions: [], statistics: { candidateCount: prices.length, demandUnits: 0n, supplyUnits: 0n, executableUnits: 0n, selfTradePreventedUnits: 0n } };

  const buys = input.buyOrders.filter((order) => order.limitPriceUnits >= best!.price && remaining(order) > 0n).map((order) => ({ ...order })).sort(compareBuy);
  const sells = input.sellOrders.filter((order) => order.limitPriceUnits <= best!.price && remaining(order) > 0n).map((order) => ({ ...order })).sort(compareSell);
  const remainingById = new Map([...buys, ...sells].map((order) => [order.id, remaining(order)]));
  const fills: MarketFill[] = [];
  const selfTradeActions: SelfTradeAction[] = [];
  let buyIndex = 0; let sellIndex = 0;
  while (buyIndex < buys.length && sellIndex < sells.length) {
    const buy = buys[buyIndex]; const sell = sells[sellIndex];
    const buyRemaining = remainingById.get(buy.id) ?? 0n; const sellRemaining = remainingById.get(sell.id) ?? 0n;
    if (buyRemaining === 0n) { buyIndex += 1; continue; }
    if (sellRemaining === 0n) { sellIndex += 1; continue; }
    if (buy.ownerId === sell.ownerId) {
      const newer = buy.sequenceNo > sell.sequenceNo || (buy.sequenceNo === sell.sequenceNo && buy.id > sell.id) ? buy : sell;
      const preventedUnits = remainingById.get(newer.id) ?? 0n;
      remainingById.set(newer.id, 0n);
      selfTradeActions.push({ cancelledOrderId: newer.id, preventedUnits, counterpartyOrderId: newer.id === buy.id ? sell.id : buy.id });
      continue;
    }
    const quantityUnits = buyRemaining < sellRemaining ? buyRemaining : sellRemaining;
    fills.push({ buyOrderId: buy.id, sellOrderId: sell.id, quantityUnits, priceUnits: best.price });
    remainingById.set(buy.id, buyRemaining - quantityUnits);
    remainingById.set(sell.id, sellRemaining - quantityUnits);
  }
  const allOrders = [...buys, ...sells];
  return {
    clearingPriceUnits: best.price,
    fills,
    unfilledOrders: allOrders.map((order) => ({ orderId: order.id, remainingUnits: remainingById.get(order.id) ?? 0n })).filter((order) => order.remainingUnits > 0n),
    selfTradeActions,
    statistics: {
      candidateCount: prices.length,
      demandUnits: input.buyOrders.filter((order) => order.limitPriceUnits >= best!.price).reduce((sum, order) => sum + remaining(order), 0n),
      supplyUnits: input.sellOrders.filter((order) => order.limitPriceUnits <= best!.price).reduce((sum, order) => sum + remaining(order), 0n),
      executableUnits: fills.reduce((sum, fill) => sum + fill.quantityUnits, 0n),
      selfTradePreventedUnits: selfTradeActions.reduce((sum, action) => sum + action.preventedUnits, 0n),
    },
  };
}
