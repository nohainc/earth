import test from 'node:test';
import assert from 'node:assert/strict';

class OrderBookSimulator {
  constructor() {
    this.bids = []; // sorted descending by price
    this.asks = []; // sorted ascending by price
    this.trades = [];
  }

  limitBuy(buyerId, price, quantity) {
    let remaining = quantity;
    while (remaining > 0 && this.asks.length > 0 && this.asks[0].price <= price) {
      const bestAsk = this.asks[0];
      const matchQty = Math.min(remaining, bestAsk.quantity);
      const matchPrice = bestAsk.price; // execute at maker's ask price

      this.trades.push({
        buyerId,
        sellerId: bestAsk.sellerId,
        price: matchPrice,
        quantity: matchQty,
        cost: matchPrice * matchQty,
      });

      remaining -= matchQty;
      bestAsk.quantity -= matchQty;
      if (bestAsk.quantity <= 0) {
        this.asks.shift();
      }
    }

    if (remaining > 0) {
      this.bids.push({ buyerId, price, quantity: remaining });
      this.bids.sort((a, b) => b.price - a.price);
    }
  }

  limitSell(sellerId, price, quantity) {
    let remaining = quantity;
    while (remaining > 0 && this.bids.length > 0 && this.bids[0].price >= price) {
      const bestBid = this.bids[0];
      const matchQty = Math.min(remaining, bestBid.quantity);
      const matchPrice = bestBid.price; // execute at maker's bid price

      this.trades.push({
        buyerId: bestBid.buyerId,
        sellerId,
        price: matchPrice,
        quantity: matchQty,
        cost: matchPrice * matchQty,
      });

      remaining -= matchQty;
      bestBid.quantity -= matchQty;
      if (bestBid.quantity <= 0) {
        this.bids.shift();
      }
    }

    if (remaining > 0) {
      this.asks.push({ sellerId, price, quantity: remaining });
      this.asks.sort((a, b) => a.price - b.price);
    }
  }
}

function runMarketFuzz({ agentsCount = 40, rounds = 200, seed = 1337 } = {}) {
  let rng = seed;
  const next = () => {
    rng = (rng * 1664525 + 1013904223) >>> 0;
    return rng / 0x100000000;
  };

  const book = new OrderBookSimulator();
  const agents = Array.from({ length: agentsCount }, (_, i) => ({
    id: `AGENT-${i}`,
    credits: 100000.0,
    energy: 500.0,
  }));

  const initialTotalCredits = agents.reduce((s, a) => s + a.credits, 0);
  const initialTotalEnergy = agents.reduce((s, a) => s + a.energy, 0);

  for (let r = 0; r < rounds; r++) {
    const agent = agents[Math.floor(next() * agentsCount)];
    const isBuy = next() > 0.5;
    const price = Math.round((1.0 + next() * 4.0) * 100) / 100; // 1.00 to 5.00
    const qty = Math.floor(1 + next() * 10);

    if (isBuy) {
      const maxCost = price * qty;
      if (agent.credits >= maxCost) {
        agent.credits -= maxCost; // lock escrow
        const beforeTradeCount = book.trades.length;
        book.limitBuy(agent.id, price, qty);

        // Refund any price-improvement delta
        for (let t = beforeTradeCount; t < book.trades.length; t++) {
          const trade = book.trades[t];
          if (trade.buyerId === agent.id) {
            const refund = (price - trade.price) * trade.quantity;
            agent.credits += refund;
            agent.energy += trade.quantity;
            const seller = agents.find((a) => a.id === trade.sellerId);
            if (seller) seller.credits += trade.cost;
          }
        }
      }
    } else {
      if (agent.energy >= qty) {
        agent.energy -= qty; // lock commodity escrow
        const beforeTradeCount = book.trades.length;
        book.limitSell(agent.id, price, qty);

        for (let t = beforeTradeCount; t < book.trades.length; t++) {
          const trade = book.trades[t];
          if (trade.sellerId === agent.id) {
            agent.credits += trade.cost;
            const buyer = agents.find((a) => a.id === trade.buyerId);
            if (buyer) buyer.energy += trade.quantity;
          }
        }
      }
    }
  }

  // Calculate unspent bids in book escrow
  const unspentBidCredits = book.bids.reduce((s, b) => s + b.price * b.quantity, 0);
  const unspentAskEnergy = book.asks.reduce((s, a) => s + a.quantity, 0);

  const currentTotalCredits = agents.reduce((s, a) => s + a.credits, 0) + unspentBidCredits;
  const currentTotalEnergy = agents.reduce((s, a) => s + a.energy, 0) + unspentAskEnergy;

  return {
    tradesCount: book.trades.length,
    initialCredits: initialTotalCredits,
    finalCredits: currentTotalCredits,
    creditsConserved: Math.abs(initialTotalCredits - currentTotalCredits) < 0.001,
    energyConserved: Math.abs(initialTotalEnergy - currentTotalEnergy) < 0.001,
    allAgentsSolvent: agents.every((a) => a.credits >= 0 && a.energy >= 0),
  };
}

test('Tier 3: Multi-Agent Double Auction Market Clearing Invariant Fuzzing', () => {
  const testSeeds = [42, 100, 777, 9999, 123456];
  for (const seed of testSeeds) {
    const res1 = runMarketFuzz({ seed });
    const res2 = runMarketFuzz({ seed });

    assert.deepEqual(res1, res2, `Seed ${seed} must be 100% deterministic`);
    assert.equal(res1.creditsConserved, true, 'Total currency in market simulation must be strictly conserved');
    assert.equal(res1.energyConserved, true, 'Total commodity volume in market simulation must be strictly conserved');
    assert.equal(res1.allAgentsSolvent, true, 'Zero negative balances allowed during or after trading');
    assert.ok(res1.tradesCount > 0, 'Market matching must successfully execute trades');
  }
});
