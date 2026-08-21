import type { PostgresRepository } from '../repository.ts';
import { processMortality } from '../lifecycle-postgres.ts';

export interface LifecycleSettlementResult {
  humansAged: number;
  mortalityEvents: number;
}

export async function settleContinuousLifecycle(
  repo: PostgresRepository,
  currentDay: number,
  previousDay: number,
): Promise<LifecycleSettlementResult> {
  let humansAged = 0;
  let mortalityEvents = 0;

  // Check if a full world year boundary (365 game days) was crossed
  const prevYear = Math.floor(previousDay / 365);
  const currYear = Math.floor(currentDay / 365);
  const yearsElapsed = currYear - prevYear;

  if (yearsElapsed > 0) {
    const aged = await repo.query<{ id: string }>(
      `UPDATE humans
       SET age_years = age_years + $1,
           legacy = legacy + CASE WHEN standing > 0 THEN $1 ELSE 0 END
       WHERE life_status = 'active'
       RETURNING id`,
      [yearsElapsed],
    );
    humansAged = aged.rows.length;

    // Process mortality for elders
    for (let y = 0; y < yearsElapsed; y++) {
      const yearDay = (prevYear + y + 1) * 365;
      await processMortality(repo, yearDay);
      mortalityEvents += 1;
    }
  }

  return { humansAged, mortalityEvents };
}
