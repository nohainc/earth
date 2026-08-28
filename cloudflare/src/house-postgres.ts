import type { PostgresRepository } from './repository.ts';

async function transactional<T>(repository: PostgresRepository, work: () => Promise<T>): Promise<T> {
  return repository.transaction(async () => work());
}

export interface HouseRecord {
  id: string;
  email: string;
  house_name: string;
  motto: string;
  founder_human_id: string | null;
  legacy_points: number;
  total_wealth_generated: string | number;
  created_at: string;
}

export interface LineageRecord {
  id: string;
  house_id: string;
  human_id: string;
  predecessor_human_id: string | null;
  generation: number;
  name: string;
  title: string;
  birth_game_day: number;
  death_game_day: number | null;
  is_incumbent: boolean;
  cause_of_death: string | null;
  epitaph: string | null;
  lifetime_wealth: string | number;
  businesses_founded: number;
  proposals_authored: number;
  legacy_score: number;
  created_at: string;
}

export interface HousePerk {
  id: string;
  house_id: string;
  perk_key: string;
  perk_name: string;
  perk_category: string;
  tier: number;
  unlocked_game_day: number;
}

export interface HouseHeirloom {
  id: string;
  house_id: string;
  name: string;
  heirloom_type: string;
  quality_tier: string;
  stat_buff: string;
  equipped_by_human_id: string | null;
  inscription: string;
  created_at: string;
}

export const HOUSE_PERK_CATALOG = [
  {
    key: 'industrialist_lineage',
    name: 'Industrialist Lineage',
    category: 'Operations',
    cost: 100,
    description: '+10% Building Construction Speed & -15% Business Startup Fees',
  },
  {
    key: 'diplomatic_house',
    name: 'Diplomatic House',
    category: 'Governance',
    cost: 100,
    description: '+15% Senate & City Council Voting Influence',
  },
  {
    key: 'financial_magnate',
    name: 'Financial Magnate',
    category: 'Finance',
    cost: 120,
    description: '+8% Corporate Dividend Yields & -20% Loan Margins',
  },
  {
    key: 'technological_pioneers',
    name: 'Technological Pioneers',
    category: 'Research',
    cost: 150,
    description: '+15% Compute Research Efficiency & +25% Patent Royalties',
  },
  {
    key: 'planetary_agronomists',
    name: 'Planetary Agronomists',
    category: 'Resources',
    cost: 120,
    description: '+20% Food Production Efficiency',
  },
];

export async function getHouseOverview(
  client: PostgresRepository,
  email: string,
  humanId: string = 'H-0044',
  humanName: string = 'Amara Vance'
): Promise<{
  ok: boolean;
  house: HouseRecord;
  lineage: LineageRecord[];
  perks: HousePerk[];
  heirlooms: HouseHeirloom[];
  catalogPerks: typeof HOUSE_PERK_CATALOG;
}> {
  return transactional(client, async () => {
    // Ensure house exists or create initial one
    let houseRes = await client.query(
      `SELECT * FROM houses WHERE email = $1 OR id = $2 LIMIT 1`,
      [email, `HSE-${humanId}`]
    );

    let house: HouseRecord;
    if (houseRes.rows.length === 0) {
      const houseId = `HSE-${humanId}`;
      const surname = humanName.split(' ').pop() || 'Pioneer';
      const houseName = `House of ${surname}`;
      const insertRes = await client.query(
        `INSERT INTO houses (id, email, house_name, motto, founder_human_id, legacy_points, total_wealth_generated)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING *`,
        [
          houseId,
          email,
          houseName,
          'From the Red Dust We Build Eternity',
          humanId,
          0,
          0.0,
        ]
      );
      house = insertRes.rows[0];

      // Seed initial founder & incumbent
      await client.query(
        `INSERT INTO house_lineage_records (
           id, house_id, human_id, predecessor_human_id, generation, name, title,
           birth_game_day, death_game_day, is_incumbent, cause_of_death, epitaph,
           lifetime_wealth, businesses_founded, proposals_authored, legacy_score
         ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
         ON CONFLICT (id) DO NOTHING`,
        [
          `LIN-${houseId}-1`,
          houseId,
          humanId,
          null,
          1,
          humanName,
          'Founding House Head',
          1,
          null,
          true,
          null,
          'Pioneering the dawn of the United Corporations era.',
          0.0,
          0,
          0,
          0,
        ]
      );

      // Seed starter heirloom
      await client.query(
        `INSERT INTO house_heirlooms (
           id, house_id, name, heirloom_type, quality_tier, stat_buff, equipped_by_human_id, inscription
         ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         ON CONFLICT (id) DO NOTHING`,
        [
          `HLM-${houseId}-1`,
          houseId,
          `${houseName} Founding Seal`,
          'founder_seal',
          'Legendary',
          '+10% Machine Build Speed & -15% Business Startup Fees',
          humanId,
          'Awarded to the founder upon pioneering planetary settlement.',
        ]
      );
    } else {
      house = houseRes.rows[0];
    }

    const lineageRes = await client.query(
      `SELECT * FROM house_lineage_records WHERE house_id = $1 ORDER BY generation ASC, birth_game_day ASC`,
      [house.id]
    );

    const perksRes = await client.query(
      `SELECT * FROM house_perks WHERE house_id = $1 ORDER BY tier ASC, perk_name ASC`,
      [house.id]
    );

    const heirloomsRes = await client.query(
      `SELECT * FROM house_heirlooms WHERE house_id = $1 ORDER BY quality_tier DESC, name ASC`,
      [house.id]
    );

    const heirlooms = heirloomsRes.rows.map((h) => ({
      ...h,
      is_equipped: Boolean(h.equipped_by_human_id),
      isEquipped: Boolean(h.equipped_by_human_id),
      equippedBy: h.equipped_by_human_id,
    }));

    return {
      ok: true,
      house,
      lineage: lineageRes.rows,
      perks: perksRes.rows,
      heirlooms,
      catalogPerks: HOUSE_PERK_CATALOG,
    };
  });
}

export async function unlockHousePerk(
  client: PostgresRepository,
  email: string,
  perkKey: string,
  gameDay: number = 1,
  correlationId?: string
): Promise<{ ok: boolean; perkKey: string; remainingPoints: number; perkName: string }> {
  const catalogItem = HOUSE_PERK_CATALOG.find((p) => p.key === perkKey);
  if (!catalogItem) {
    throw new Error(`Invalid or unknown house perk key '${perkKey}'.`);
  }

  return transactional(client, async () => {
    const houseRes = await client.query(
      `SELECT * FROM houses WHERE email = $1 LIMIT 1`,
      [email]
    );
    if (houseRes.rows.length === 0) {
      throw new Error('House not found for this account.');
    }
    const house = houseRes.rows[0];

    if (house.legacy_points < catalogItem.cost) {
      throw new Error(
        `Insufficient house legacy points. Required: ${catalogItem.cost} LP, available: ${house.legacy_points} LP.`
      );
    }

    const existingPerk = await client.query(
      `SELECT * FROM house_perks WHERE house_id = $1 AND perk_key = $2`,
      [house.id, perkKey]
    );
    if (existingPerk.rows.length > 0) {
      throw new Error(`House perk '${catalogItem.name}' is already unlocked.`);
    }

    const perkId = `PRK-${house.id}-${perkKey}`;
    await client.query(
      `INSERT INTO house_perks (id, house_id, perk_key, perk_name, perk_category, tier, unlocked_game_day)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [
        perkId,
        house.id,
        perkKey,
        catalogItem.name,
        catalogItem.category.toLowerCase(),
        1,
        gameDay,
      ]
    );

    const updateRes = await client.query(
      `UPDATE houses
       SET legacy_points = legacy_points - $1
       WHERE id = $2
       RETURNING legacy_points`,
      [catalogItem.cost, house.id]
    );

    const remaining = updateRes.rows[0].legacy_points;

    return {
      ok: true,
      perkKey,
      perkName: catalogItem.name,
      remainingPoints: remaining,
    };
  });
}

export async function equipHouseHeirloom(
  client: PostgresRepository,
  email: string,
  heirloomId: string,
  humanId: string,
  correlationId?: string
): Promise<{ ok: boolean; heirloomId: string; isEquipped: boolean; equippedBy: string | null }> {
  return transactional(client, async () => {
    const houseRes = await client.query(
      `SELECT * FROM houses WHERE email = $1 LIMIT 1`,
      [email]
    );
    if (houseRes.rows.length === 0) {
      throw new Error('House not found for this account.');
    }
    const house = houseRes.rows[0];

    const hRes = await client.query(
      `SELECT * FROM house_heirlooms WHERE id = $1 AND house_id = $2 LIMIT 1`,
      [heirloomId, house.id]
    );
    if (hRes.rows.length === 0) {
      throw new Error('Heirloom not found or does not belong to your house.');
    }
    const heirloom = hRes.rows[0];

    const currentlyEquipped = heirloom.equipped_by_human_id === humanId;
    const newEquipped = currentlyEquipped ? null : humanId;

    await client.query(
      `UPDATE house_heirlooms SET equipped_by_human_id = $1 WHERE id = $2`,
      [newEquipped, heirloomId]
    );

    return {
      ok: true,
      heirloomId,
      isEquipped: newEquipped !== null,
      equippedBy: newEquipped,
    };
  });
}

export async function forgeHouseHeirloom(
  client: PostgresRepository,
  email: string,
  name: string,
  heirloomType: string,
  inscription: string,
  statBuff: string,
  correlationId?: string
): Promise<{ ok: boolean; heirloom: HouseHeirloom }> {
  return transactional(client, async () => {
    const houseRes = await client.query(
      `SELECT * FROM houses WHERE email = $1 LIMIT 1`,
      [email]
    );
    if (houseRes.rows.length === 0) {
      throw new Error('House not found for this account.');
    }
    const house = houseRes.rows[0];

    const allowedTypes = ['founder_seal', 'senate_gavel', 'quantum_cipher', 'pioneer_chronometer', 'house_standard'];
    if (!allowedTypes.includes(heirloomType)) {
      throw new Error(`Invalid heirloom type. Allowed: ${allowedTypes.join(', ')}`);
    }

    const heirloomId = correlationId
      ? `HLM-${house.id}-${correlationId}`
      : `HLM-${house.id}-${crypto.randomUUID()}`;
    const insertRes = await client.query(
      `INSERT INTO house_heirlooms (id, house_id, name, heirloom_type, quality_tier, stat_buff, equipped_by_human_id, inscription)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       ON CONFLICT (id) DO UPDATE SET id = house_heirlooms.id
       RETURNING *`,
      [
        heirloomId,
        house.id,
        name.trim(),
        heirloomType,
        'Legendary',
        statBuff.trim(),
        null,
        inscription.trim(),
      ]
    );

    return {
      ok: true,
      heirloom: insertRes.rows[0],
    };
  });
}

export async function updateHouseMotto(
  client: PostgresRepository,
  email: string,
  motto: string,
  houseName?: string,
  correlationId?: string
): Promise<{ ok: boolean; motto: string; houseName: string }> {
  return transactional(client, async () => {
    const houseRes = await client.query(
      `SELECT * FROM houses WHERE email = $1 LIMIT 1`,
      [email]
    );
    if (houseRes.rows.length === 0) {
      throw new Error('House not found for this account.');
    }
    const house = houseRes.rows[0];

    const newMotto = motto.trim() || house.motto;
    const newName = houseName && houseName.trim() ? houseName.trim() : house.house_name;

    await client.query(
      `UPDATE houses SET motto = $1, house_name = $2 WHERE id = $3`,
      [newMotto, newName, house.id]
    );

    return {
      ok: true,
      motto: newMotto,
      houseName: newName,
    };
  });
}
