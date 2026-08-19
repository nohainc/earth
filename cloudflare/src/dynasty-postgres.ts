import type { PostgresRepository } from './repository.ts';

async function transactional<T>(repository: PostgresRepository, work: () => Promise<T>): Promise<T> {
  return repository.transaction(async () => work());
}

export interface DynastyRecord {
  id: string;
  email: string;
  dynasty_name: string;
  motto: string;
  founder_human_id: string | null;
  legacy_points: number;
  total_wealth_generated: string | number;
  created_at: string;
}

export interface LineageRecord {
  id: string;
  dynasty_id: string;
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

export interface DynastyPerk {
  id: string;
  dynasty_id: string;
  perk_key: string;
  perk_name: string;
  perk_category: string;
  tier: number;
  unlocked_game_day: number;
}

export interface DynastyHeirloom {
  id: string;
  dynasty_id: string;
  name: string;
  heirloom_type: string;
  quality_tier: string;
  stat_buff: string;
  equipped_by_human_id: string | null;
  inscription: string;
  created_at: string;
}

export const DYNASTY_PERK_CATALOG = [
  {
    key: 'industrialist_lineage',
    name: 'Industrialist Lineage',
    category: 'Operations',
    cost: 100,
    description: '+10% Machine Build Speed & -15% Business Startup Fees',
  },
  {
    key: 'diplomatic_dynasty',
    name: 'Diplomatic Dynasty',
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

export async function getDynastyOverview(
  client: PostgresRepository,
  email: string,
  humanId: string = 'H-0044',
  humanName: string = 'Amara Vance'
): Promise<{
  ok: boolean;
  dynasty: DynastyRecord;
  lineage: LineageRecord[];
  perks: DynastyPerk[];
  heirlooms: DynastyHeirloom[];
  catalogPerks: typeof DYNASTY_PERK_CATALOG;
}> {
  return transactional(client, async () => {
  // Ensure dynasty exists or create initial one
  let dynastyRes = await client.query(
    `SELECT * FROM dynasties WHERE email = $1 OR id = $2 LIMIT 1`,
    [email, `DYN-${humanId}`]
  );

  let dynasty: DynastyRecord;
  if (dynastyRes.rows.length === 0) {
    const dynId = `DYN-${humanId}`;
    const dynastyName = `House ${humanName.split(' ').pop() || 'Pioneer'}`;
    const insertRes = await client.query(
      `INSERT INTO dynasties (id, email, dynasty_name, motto, founder_human_id, legacy_points, total_wealth_generated)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING *`,
      [
        dynId,
        email,
        dynastyName,
        'From the Red Dust We Build Eternity',
        humanId,
        250,
        150000.0,
      ]
    );
    dynasty = insertRes.rows[0];

    // Seed initial founder & incumbent
    await client.query(
      `INSERT INTO dynasty_lineage_records (
         id, dynasty_id, human_id, predecessor_human_id, generation, name, title,
         birth_game_day, death_game_day, is_incumbent, cause_of_death, epitaph,
         lifetime_wealth, businesses_founded, proposals_authored, legacy_score
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
       ON CONFLICT (id) DO NOTHING`,
      [
        `LIN-${dynId}-1`,
        dynId,
        humanId,
        null,
        1,
        humanName,
        'Founding Dynastic Head',
        1,
        null,
        true,
        null,
        'Pioneering the dawn of the United Corporations era.',
        150000.0,
        2,
        1,
        120,
      ]
    );

    // Seed starter heirloom
    await client.query(
      `INSERT INTO dynasty_heirlooms (
         id, dynasty_id, name, heirloom_type, quality_tier, stat_buff, equipped_by_human_id, inscription
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       ON CONFLICT (id) DO NOTHING`,
      [
        `HLM-${dynId}-1`,
        dynId,
        `${dynastyName} Founding Seal`,
        'founder_seal',
        'Legendary',
        '+10% Machine Build Speed & -15% Business Startup Fees',
        humanId,
        'Awarded to the founder upon pioneering planetary settlement.',
      ]
    );
  } else {
    dynasty = dynastyRes.rows[0];
  }

  const lineageRes = await client.query(
    `SELECT * FROM dynasty_lineage_records WHERE dynasty_id = $1 ORDER BY generation ASC, birth_game_day ASC`,
    [dynasty.id]
  );

  const perksRes = await client.query(
    `SELECT * FROM dynasty_perks WHERE dynasty_id = $1 ORDER BY tier ASC, perk_name ASC`,
    [dynasty.id]
  );

  const heirloomsRes = await client.query(
    `SELECT * FROM dynasty_heirlooms WHERE dynasty_id = $1 ORDER BY quality_tier DESC, name ASC`,
    [dynasty.id]
  );

  return {
    ok: true,
    dynasty,
    lineage: lineageRes.rows,
    perks: perksRes.rows,
    heirlooms: heirloomsRes.rows,
    catalogPerks: DYNASTY_PERK_CATALOG,
  };
  });
}

export async function unlockDynastyPerk(
  client: PostgresRepository,
  email: string,
  perkKey: string,
  gameDay: number = 1,
  correlationId?: string
): Promise<{ ok: boolean; perkKey: string; remainingPoints: number; perkName: string }> {
  const catalogItem = DYNASTY_PERK_CATALOG.find((p) => p.key === perkKey);
  if (!catalogItem) {
    throw new Error(`Invalid or unknown dynasty perk key '${perkKey}'.`);
  }

  return transactional(client, async () => {
  const dynRes = await client.query(
    `SELECT * FROM dynasties WHERE email = $1 LIMIT 1`,
    [email]
  );
  if (dynRes.rows.length === 0) {
    throw new Error('Dynasty not found for this account.');
  }
  const dynasty = dynRes.rows[0];

  if (dynasty.legacy_points < catalogItem.cost) {
    throw new Error(
      `Insufficient dynasty legacy points. Required: ${catalogItem.cost} LP, available: ${dynasty.legacy_points} LP.`
    );
  }

  const existingPerk = await client.query(
    `SELECT * FROM dynasty_perks WHERE dynasty_id = $1 AND perk_key = $2`,
    [dynasty.id, perkKey]
  );
  if (existingPerk.rows.length > 0) {
    throw new Error(`Dynastic perk '${catalogItem.name}' is already unlocked.`);
  }

  const perkId = `PRK-${dynasty.id}-${perkKey}`;
  await client.query(
    `INSERT INTO dynasty_perks (id, dynasty_id, perk_key, perk_name, perk_category, tier, unlocked_game_day)
     VALUES ($1, $2, $3, $4, $5, $6, $7)`,
    [
      perkId,
      dynasty.id,
      perkKey,
      catalogItem.name,
      catalogItem.category.toLowerCase(),
      1,
      gameDay,
    ]
  );

  const updateRes = await client.query(
    `UPDATE dynasties
     SET legacy_points = legacy_points - $1
     WHERE id = $2
     RETURNING legacy_points`,
    [catalogItem.cost, dynasty.id]
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

export async function equipDynastyHeirloom(
  client: PostgresRepository,
  email: string,
  heirloomId: string,
  humanId: string,
  correlationId?: string
): Promise<{ ok: boolean; heirloomId: string; isEquipped: boolean; equippedBy: string | null }> {
  return transactional(client, async () => {
  const dynRes = await client.query(
    `SELECT * FROM dynasties WHERE email = $1 LIMIT 1`,
    [email]
  );
  if (dynRes.rows.length === 0) {
    throw new Error('Dynasty not found for this account.');
  }
  const dynasty = dynRes.rows[0];

  const hRes = await client.query(
    `SELECT * FROM dynasty_heirlooms WHERE id = $1 AND dynasty_id = $2 LIMIT 1`,
    [heirloomId, dynasty.id]
  );
  if (hRes.rows.length === 0) {
    throw new Error('Heirloom not found or does not belong to your dynasty.');
  }
  const heirloom = hRes.rows[0];

  const currentlyEquipped = heirloom.equipped_by_human_id === humanId;
  const newEquipped = currentlyEquipped ? null : humanId;

  await client.query(
    `UPDATE dynasty_heirlooms SET equipped_by_human_id = $1 WHERE id = $2`,
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

export async function forgeDynastyHeirloom(
  client: PostgresRepository,
  email: string,
  name: string,
  heirloomType: string,
  inscription: string,
  statBuff: string,
  correlationId?: string
): Promise<{ ok: boolean; heirloom: DynastyHeirloom }> {
  return transactional(client, async () => {
  const dynRes = await client.query(
    `SELECT * FROM dynasties WHERE email = $1 LIMIT 1`,
    [email]
  );
  if (dynRes.rows.length === 0) {
    throw new Error('Dynasty not found for this account.');
  }
  const dynasty = dynRes.rows[0];

  const allowedTypes = ['founder_seal', 'senate_gavel', 'quantum_cipher', 'pioneer_chronometer', 'dynasty_standard'];
  if (!allowedTypes.includes(heirloomType)) {
    throw new Error(`Invalid heirloom type. Allowed: ${allowedTypes.join(', ')}`);
  }

  // A client retry reuses the correlationId and therefore cannot forge twice.
  const heirloomId = correlationId
      ? `HLM-${dynasty.id}-${correlationId}`
      : `HLM-${dynasty.id}-${crypto.randomUUID()}`;
  const insertRes = await client.query(
    `INSERT INTO dynasty_heirlooms (id, dynasty_id, name, heirloom_type, quality_tier, stat_buff, equipped_by_human_id, inscription)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     ON CONFLICT (id) DO UPDATE SET id = dynasty_heirlooms.id
     RETURNING *`,
    [
      heirloomId,
      dynasty.id,
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

export async function updateDynastyMotto(
  client: PostgresRepository,
  email: string,
  motto: string,
  dynastyName?: string,
  correlationId?: string
): Promise<{ ok: boolean; motto: string; dynastyName: string }> {
  return transactional(client, async () => {
  const dynRes = await client.query(
    `SELECT * FROM dynasties WHERE email = $1 LIMIT 1`,
    [email]
  );
  if (dynRes.rows.length === 0) {
    throw new Error('Dynasty not found for this account.');
  }
  const dynasty = dynRes.rows[0];

  const newMotto = motto.trim() || dynasty.motto;
  const newName = dynastyName && dynastyName.trim() ? dynastyName.trim() : dynasty.dynasty_name;

  await client.query(
    `UPDATE dynasties SET motto = $1, dynasty_name = $2 WHERE id = $3`,
    [newMotto, newName, dynasty.id]
  );

  return {
    ok: true,
    motto: newMotto,
    dynastyName: newName,
  };
  });
}
