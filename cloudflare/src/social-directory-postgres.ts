import type { PostgresRepository } from './repository.ts';

/**
 * Neutral entity directory retained for successor selection and other pickers.
 * It intentionally has no initiative, relationship, or social-history data.
 */
export async function listSocialDirectory(repo: PostgresRepository, viewerId: string, query = '') {
  const term = `%${query.trim().slice(0, 80)}%`;
  const [humans, cities, corporations, communities] = await Promise.all([
    repo.query(`SELECT h.id, h.display_name, d.house_name, d.house_name AS dynasty_name,
                       h.standing, h.final_legacy AS legacy,
                       r.territory_id, t.name AS territory_name
                  FROM humans h
                  LEFT JOIN houses d ON d.id = h.house_id
                  LEFT JOIN house_residencies r ON r.house_id = h.house_id
                   AND r.status = 'ACTIVE' AND r.residency_class = 'PRIMARY'
                  LEFT JOIN territories t ON t.id = r.territory_id
                 WHERE h.status = 'ACTIVE' AND h.id <> $1
                   AND ($2 = '%%' OR h.display_name ILIKE $2 OR d.house_name ILIKE $2)
                 ORDER BY h.standing DESC LIMIT 40`, [viewerId, term]),
    repo.query(`SELECT t.id, t.name, t.status,
                       COUNT(DISTINCT r.house_id)::INTEGER AS residents,
                       NULL::TEXT AS treasury
                  FROM territories t
                  LEFT JOIN house_residencies r ON r.territory_id = t.id AND r.status = 'ACTIVE'
                 WHERE ($1 = '%%' OR t.name ILIKE $1)
                 GROUP BY t.id, t.name, t.status
                 ORDER BY residents DESC, t.id LIMIT 30`, [term]),
    repo.query(`SELECT o.id, o.name, o.status,
                       COUNT(m.house_id)::INTEGER AS member_count,
                       NULL::TEXT AS treasury
                  FROM organizations o
                  LEFT JOIN organization_memberships m ON m.organization_id = o.id AND m.status = 'ACTIVE'
                 WHERE o.archetype = 'CORPORATION' AND o.status = 'ACTIVE'
                   AND ($1 = '%%' OR o.name ILIKE $1)
                 GROUP BY o.id, o.name, o.status
                 ORDER BY member_count DESC, o.id LIMIT 30`, [term]),
    repo.query(`SELECT o.id, o.name, o.status,
                       COUNT(m.house_id)::INTEGER AS member_count
                  FROM organizations o
                  LEFT JOIN organization_memberships m ON m.organization_id = o.id AND m.status = 'ACTIVE'
                 WHERE o.archetype = 'COMMUNITY' AND o.status = 'ACTIVE'
                   AND ($1 = '%%' OR o.name ILIKE $1)
                 GROUP BY o.id, o.name, o.status
                 ORDER BY member_count DESC, o.id LIMIT 30`, [term]),
  ]);
  return { humans: humans.rows, businesses: [], cities: cities.rows, corporations: corporations.rows, communities: communities.rows };
}
