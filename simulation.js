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
