// Deterministic balance harness for validating EARTH's core economic invariants.
export function runSimulation({ days = 365, humans = 30, seed = 42 } = {}) {
  let random = seed;
  const next = () => {
    random = (random * 1664525 + 1013904223) >>> 0;
    return random / 0x100000000;
  };
  const players = Array.from({ length: humans }, (_, index) => ({ id: `SIM-${index + 1}`, credits: 1000, components: 20, machineCondition: 100 }));
  const initialCredits = players.reduce((total, player) => total + player.credits, 0);
  let trades = 0;
  let maintenanceDemand = 0;
  for (let day = 1; day <= days; day += 1) {
    for (const player of players) {
      player.machineCondition = Math.max(0, player.machineCondition - 0.25);
      maintenanceDemand += 0.25;
      if (player.machineCondition < 70 && player.components >= 2) {
        player.components -= 2;
        player.machineCondition = Math.min(100, player.machineCondition + 12);
        maintenanceDemand -= 2;
      }
      if (next() < 0.35 && player.credits >= 10) {
        player.credits -= 10;
        players[Math.floor(next() * players.length)].credits += 10;
        trades += 1;
      }
    }
  }
  const finalCredits = players.reduce((total, player) => total + player.credits, 0);
  return {
    days,
    humans,
    trades,
    maintenanceDemand,
    creditsConserved: finalCredits === initialCredits,
    nonNegativeBalances: players.every((player) => player.credits >= 0 && player.components >= 0),
    boundedMachineCondition: players.every((player) => player.machineCondition >= 0 && player.machineCondition <= 100),
    initialCredits,
    finalCredits,
  };
}
