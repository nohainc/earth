import type { PostgresRepository } from './repository.ts';
import { listCommunities } from './communities-postgres.ts';

export async function worldSnapshot(repository: PostgresRepository, viewerId?: string, viewerHouseId?: string): Promise<Record<string, unknown>> {
  const [world, institutions, humans, assets, communities] = await Promise.all([
    repository.query("SELECT id, game_day, game_minute, world_seed, status FROM world_state WHERE id = 'WORLD'"),
    repository.query('SELECT id, kind, name, status FROM institutions ORDER BY id'),
    repository.query("SELECT id, house_id, display_name, age_years, standing, final_legacy, status FROM humans WHERE status = 'ACTIVE' ORDER BY id"),
    repository.query('SELECT code, asset_kind FROM economic_assets ORDER BY id'),
    listCommunities(repository, viewerHouseId),
  ]);
  return {
    ok: true,
    viewerId: viewerId ?? null,
    world: world.rows[0] ?? null,
    institutions: institutions.rows,
    humans: humans.rows,
    economicAssets: assets.rows,
    communities: communities.communities,
  };
}
