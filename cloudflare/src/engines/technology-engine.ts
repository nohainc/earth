import type { PostgresRepository } from '../repository.ts';

export interface TechSettlementResult {
  projectsProgressed: number;
  patentsUnlocked: number;
  royaltiesSettled: number;
}

export async function settleContinuousTechnology(
  repo: PostgresRepository,
  elapsedDays: number,
  gameDay: number,
): Promise<TechSettlementResult> {
  if (elapsedDays <= 0) return { projectsProgressed: 0, patentsUnlocked: 0, royaltiesSettled: 0 };

  let projectsProgressed = 0;
  let patentsUnlocked = 0;

  // 1. Progress active research projects
  const activeProjects = await repo.query<{
    id: string;
    technology_id: string;
    owner_id: string;
    progress: string;
    budget: string;
  }>("SELECT rp.id, rp.technology_id, rp.owner_id, rp.progress, rp.budget FROM research_projects rp JOIN memberships m ON m.human_id = rp.owner_id AND m.city_id IS NOT NULL WHERE rp.status = 'active' AND rp.budget > 0 FOR UPDATE OF rp");

  for (const proj of activeProjects.rows) {
    const currentProgress = Number(proj.progress ?? 0);
    const budget = Number(proj.budget ?? 0);
    const dailyRate = Math.min(10, Math.max(1, budget / 100));
    const deltaProgress = Math.round(dailyRate * elapsedDays * 100) / 100;
    const newProgress = Math.min(100, currentProgress + deltaProgress);

    await repo.query(
      'UPDATE research_projects SET progress = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
      [newProgress, proj.id],
    );

    if (proj.technology_id) {
      await repo.query(
        'UPDATE technologies SET progress = $1 WHERE id = $2',
        [newProgress, proj.technology_id],
      );
    }

    if (newProgress >= 100 && currentProgress < 100) {
      await repo.query("UPDATE research_projects SET status = 'completed' WHERE id = $1", [proj.id]);
      await repo.query("UPDATE technologies SET status = 'patented' WHERE id = $1", [proj.technology_id]);
      patentsUnlocked += 1;
    }

    projectsProgressed += 1;
  }

  // 2. Settle technology royalties
  // technology_licenses uses patent_id; join patents to get technology_id for audit trail
  const activeLicenses = await repo.query<{
    id: string;
    patent_id: string;
    technology_id: string;
    licensor_id: string;
    licensee_id: string;
    royalty_rate: string;
  }>("SELECT tl.id, tl.patent_id, p.technology_id, tl.licensor_id, tl.licensee_id, tl.royalty_rate FROM technology_licenses tl JOIN patents p ON p.id = tl.patent_id WHERE tl.status = 'active'");

  let royaltiesSettled = 0;
  for (const lic of activeLicenses.rows) {
    const dailyRoyalty = Number(lic.royalty_rate ?? 10);
    const amount = Math.round(dailyRoyalty * elapsedDays * 100) / 100;
    if (amount <= 0) continue;

    // Deduct licensee, credit licensor
    await repo.query(
      "UPDATE account_balances SET balance = balance - $1 WHERE owner_id = $2 AND currency = 'CREDIT'",
      [amount, lic.licensee_id],
    );
    await repo.query(
      "UPDATE account_balances SET balance = balance + $1 WHERE owner_id = $2 AND currency = 'CREDIT'",
      [amount, lic.licensor_id],
    );

    await repo.query(
      'INSERT INTO technology_events (id, technology_id, event_type, actor_id, target_id, details, game_day) VALUES ($1,$2,$3,$4,$5,$6,$7)',
      [crypto.randomUUID(), lic.technology_id, 'royalty_payment', lic.licensee_id, lic.licensor_id, JSON.stringify({ amount, gameDay }), Math.floor(gameDay)],
    );
    royaltiesSettled += 1;
  }

  return { projectsProgressed, patentsUnlocked, royaltiesSettled };
}
