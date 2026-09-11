import type { PostgresRepository } from './repository.ts';

/**
 * Neutral entity directory retained for successor selection and other pickers.
 * It intentionally has no initiative, relationship, or social-history data.
 */
export async function listSocialDirectory(repo: PostgresRepository, viewerId: string, query = '') {
  const term = `%${query.trim().slice(0, 80)}%`;
  const [humans, cities, corporations, communities] = await Promise.all([
    repo.query(`SELECT h.id, h.display_name, d.house_name, d.house_name AS dynasty_name, h.standing, h.legacy, m.city_id, ci.id AS city_name FROM humans h LEFT JOIN houses d ON d.founder_human_id = h.id LEFT JOIN memberships m ON m.human_id = h.id LEFT JOIN cities ci ON ci.id = m.city_id WHERE h.life_status = 'active' AND h.id <> $1 AND ($2 = '%%' OR h.display_name ILIKE $2 OR d.house_name ILIKE $2) ORDER BY h.standing DESC LIMIT 40`, [viewerId, term]),
    repo.query(`SELECT c.id, i.name, i.status, c.residents,
      COALESCE((SELECT a.balance / 100.0 FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = c.id AND a.asset_id = 1 AND a.account_type = 3 AND a.is_default_settlement AND a.status = 'active'), 0) AS treasury
      FROM cities c JOIN institutions i ON i.id = c.institution_id
      WHERE i.status = 'active' AND ($1 = '%%' OR i.name ILIKE $1) ORDER BY c.residents DESC LIMIT 30`, [term]),
    repo.query(`SELECT c.id, i.name, i.status, c.member_count,
      COALESCE((SELECT a.balance / 100.0 FROM economic_accounts a JOIN owner_registry o ON o.economic_id = a.owner_economic_id WHERE o.id = c.id AND a.asset_id = 1 AND a.account_type = 3 AND a.is_default_settlement AND a.status = 'active'), 0) AS treasury
      FROM corporations c JOIN institutions i ON i.id = c.institution_id
      WHERE i.status = 'active' AND ($1 = '%%' OR i.name ILIKE $1) ORDER BY c.member_count DESC LIMIT 30`, [term]),
    repo.query(`SELECT id, name, status, member_count FROM communities WHERE status = 'active' AND ($1 = '%%' OR name ILIKE $1) ORDER BY member_count DESC LIMIT 30`, [term]),
  ]);
  return { humans: humans.rows, businesses: [], cities: cities.rows, corporations: corporations.rows, communities: communities.rows };
}
