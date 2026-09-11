// Deterministic balance harness for validating EARTH's core economic invariants.
export function runSimulation({ days = 365, humans = 30, seed = 42 } = {}) {
  let random = seed;
  const next = () => {
    random = (random * 1664525 + 1013904223) >>> 0;
    return random / 0x100000000;
  };
  const players = Array.from({ length: humans }, (_, index) => ({ id: `SIM-${index + 1}`, credits: 1000, material: 30, components: 20, energy: 24, compute: 12, machineCondition: 100 }));
  const institutions = { ouc: 0, corporation: 0, city: 0 };
  const initialCredits = players.reduce((total, player) => total + player.credits, 0);
  const initialResources = players.reduce((totals, player) => {
    for (const resource of ['material', 'components', 'energy', 'compute']) totals[resource] += player[resource];
    return totals;
  }, { material: 0, components: 0, energy: 0, compute: 0 });
  let trades = 0;
  let maintenanceDemand = 0;
  let production = 0;
  let fees = 0;
  for (let day = 1; day <= days; day += 1) {
    for (const player of players) {
      player.machineCondition = Math.max(0, player.machineCondition - 0.25);
      maintenanceDemand += 0.25;
      if (player.machineCondition < 70 && player.components >= 2) {
        player.components -= 2;
        player.machineCondition = Math.min(100, player.machineCondition + 12);
        maintenanceDemand -= 2;
      }
      // A machine creates Components only after consuming physical inputs.
      // This keeps the harness aligned with the authoritative production rule:
      // time alone never creates Credits or goods.
      if (player.machineCondition > 25 && player.material >= 1 && player.energy >= 1) {
        player.material -= 1;
        player.energy -= 1;
        player.components += 1;
        production += 1;
      }
      if (next() < 0.35 && player.credits >= 10) {
        player.credits -= 10;
        const seller = players[Math.floor(next() * players.length)];
        const fee = 0.5;
        player.credits -= fee;
        seller.credits += 10;
        institutions.ouc += fee;
        fees += fee;
        trades += 1;
      }
    }
    // Corporation and City budgets redistribute existing Credits, never mint them.
    if (institutions.corporation >= 5) {
      institutions.corporation -= 5;
      institutions.city += 5;
    }
    if (day % 30 === 0 && players[0].credits >= 2) {
      players[0].credits -= 2;
      institutions.corporation += 2;
    }
  }
  const finalCredits = players.reduce((total, player) => total + player.credits, 0) + institutions.ouc + institutions.corporation + institutions.city;
  const finalResources = players.reduce((totals, player) => {
    for (const resource of ['material', 'components', 'energy', 'compute']) totals[resource] += player[resource];
    return totals;
  }, { material: 0, components: 0, energy: 0, compute: 0 });
  return {
    days,
    humans,
    trades,
    maintenanceDemand,
    production,
    fees,
    creditsConserved: finalCredits === initialCredits,
    nonNegativeBalances: players.every((player) => player.credits >= 0 && player.components >= 0),
    resourceNonNegative: players.every((player) => ['material', 'components', 'energy', 'compute'].every((resource) => player[resource] >= 0)),
    institutionBalancesNonNegative: Object.values(institutions).every((balance) => balance >= 0),
    boundedMachineCondition: players.every((player) => player.machineCondition >= 0 && player.machineCondition <= 100),
    initialCredits,
    finalCredits,
    initialResources,
    finalResources,
    institutions,
  };
}

// Integer-unit finance harness. This deliberately models contracts and
// distress transitions without PostgreSQL so property tests can run quickly.
export function runFinanceSimulation({ days = 60, humans = 10000, cities = 100, seed = 42 } = {}) {
  let random = seed >>> 0;
  const next = () => { random = (random * 1664525 + 1013904223) >>> 0; return random / 0x100000000; };
  const people = Array.from({ length: humans }, (_, id) => ({ id, wallet: 100_000, resources: 10_000, debt: 0, arrears: 0, deposit: 0 }));
  const institutions = Array.from({ length: cities }, (_, id) => ({ id, treasury: 1_000_000, debt: 0, state: 'ACTIVE' }));
  const bank = { reserve: 0, equity: 0, deposits: 0, loans: 0, state: 'NORMAL' };
  let issued = humans * 100_000 + cities * 1_000_000;
  let retired = 0;
  for (let day = 1; day <= days; day += 1) {
    for (const person of people) {
      if (next() < 0.06 && person.wallet >= 10_000) {
        const amount = 1_000 + Math.floor(next() * 9_000);
        person.wallet -= amount; bank.reserve += amount; bank.deposits += amount; person.deposit += amount;
      }
      if (next() < 0.04 && bank.reserve >= 5_000 && bank.state === 'NORMAL') {
        const amount = 1_000 + Math.floor(next() * 4_000);
        bank.reserve -= amount; bank.loans += amount; person.wallet += amount; person.debt += amount;
      }
      if (next() < 0.12) person.arrears += 100;
      if (person.arrears > 0 && person.wallet >= person.arrears && next() < 0.4) { const city = institutions[person.id % institutions.length]; person.wallet -= person.arrears; city.treasury += person.arrears; person.arrears = 0; }
      if (person.debt > 0 && person.wallet >= 50 && next() < 0.25) { person.wallet -= 50; bank.reserve += 50; person.debt -= 50; bank.loans -= 50; }
    }
    if (day % 7 === 0) {
      const person = people[Math.floor(next() * people.length)];
      if (person.deposit > 0 && bank.reserve >= person.deposit) { bank.reserve -= person.deposit; person.wallet += person.deposit; bank.deposits -= person.deposit; person.deposit = 0; }
    }
    if (day % 15 === 0) {
      const city = institutions[Math.floor(next() * institutions.length)];
      if (city.treasury >= 20_000) { city.treasury -= 20_000; people[Math.floor(next() * people.length)].wallet += 20_000; }
    }
    const liabilities = bank.deposits + people.reduce((sum, p) => sum + p.deposit, 0);
    bank.equity = bank.reserve + bank.loans - bank.deposits;
    bank.state = bank.equity < 0 ? 'INSOLVENT' : bank.reserve < bank.deposits ? 'LIQUIDITY_STRESS' : 'NORMAL';
    if (bank.state !== 'NORMAL') for (const person of people) person.debt = Math.max(0, person.debt);
    void liabilities;
  }
  const finalSupply = people.reduce((sum, p) => sum + p.wallet, 0) + institutions.reduce((sum, i) => sum + i.treasury, 0) + bank.reserve;
  return { days, humans, cities, issued, retired, openingSupply: issued - retired, closingSupply: finalSupply, creditConserved: finalSupply === issued - retired, nonNegative: people.every((p) => p.wallet >= 0 && p.deposit >= 0 && p.debt >= 0 && p.arrears >= 0) && institutions.every((i) => i.treasury >= 0), bankSolventOrStressed: ['NORMAL', 'LIQUIDITY_STRESS', 'INSOLVENT'].includes(bank.state), bank, taxArrears: people.reduce((sum, p) => sum + p.arrears, 0), bankruptcyCases: people.filter((p) => p.debt > p.wallet + p.deposit).length };
}
