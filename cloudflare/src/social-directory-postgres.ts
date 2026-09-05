import type { PostgresRepository } from './repository.ts';

/**
 * Neutral entity directory retained for successor selection and other pickers.
 * It intentionally has no initiative, relationship, or social-history data.
 */
export async function listSocialDirectory(repo: PostgresRepository, viewerId: string, query = '') {
  const term = `%${query.trim().slice(0, 80)}%`;
  const [humans, cities, corporations, communities] = await Promise.all([
    repo.query(`SELECT h.id, h.display_name, d.house_name, d.house_name AS dynasty_name, h.standing, h.legacy, m.city_id, ci.id AS city_name FROM humans h LEFT JOIN houses d ON d.founder_human_id = h.id LEFT JOIN memberships m ON m.human_id = h.id LEFT JOIN cities ci ON ci.id = m.city_id WHERE h.life_status = 'active' AND h.id <> $1 AND ($2 = '%%' OR h.display_name ILIKE $2 OR d.house_name ILIKE $2) ORDER BY h.standing DESC LIMIT 40`, [viewerId, term]),
    repo.query(`SELECT id, name, status, residents, treasury FROM cities WHERE status = 'active' AND ($1 = '%%' OR name ILIKE $1) ORDER BY residents DESC LIMIT 30`, [term]),
    repo.query(`SELECT id, name, status, member_count, treasury FROM corporations WHERE status = 'active' AND ($1 = '%%' OR name ILIKE $1) ORDER BY member_count DESC LIMIT 30`, [term]),
    repo.query(`SELECT id, name, status, member_count FROM communities WHERE status = 'active' AND ($1 = '%%' OR name ILIKE $1) ORDER BY member_count DESC LIMIT 30`, [term]),
  ]);
  return { humans: humans.rows, businesses: [], cities: cities.rows, corporations: corporations.rows, communities: communities.rows };
}
