import test from 'node:test';
import assert from 'node:assert/strict';
import {
  getDynastyOverview,
  unlockDynastyPerk,
  equipDynastyHeirloom,
  forgeDynastyHeirloom,
  updateDynastyMotto,
} from '../cloudflare/src/dynasty-postgres.ts';

function createMockDb(initialData = {}) {
  const dynasties = initialData.dynasties || [
    {
      id: 'DYN-H0044',
      email: 'amara@earth.local',
      dynasty_name: 'House Vance',
      motto: 'From the Red Dust We Build Eternity',
      founder_human_id: 'H-0044',
      legacy_points: 350,
      total_wealth_generated: '450000.00',
      created_at: new Date().toISOString(),
    },
  ];

  const lineage = initialData.lineage || [
    {
      id: 'LIN-001',
      dynasty_id: 'DYN-H0044',
      human_id: 'H-0044',
      predecessor_human_id: null,
      generation: 1,
      name: 'Cassian Vance I',
      title: 'Pioneer Patriarch',
      birth_game_day: 1,
      death_game_day: 140,
      is_incumbent: false,
      cause_of_death: 'Hyperbaric Decompression',
      epitaph: 'Laid the foundation stones of Neo-Tokyo.',
      lifetime_wealth: '280000.00',
      businesses_founded: 3,
      proposals_authored: 4,
      legacy_score: 180,
      created_at: new Date().toISOString(),
    },
  ];

  const perks = initialData.perks || [];
  const heirlooms = initialData.heirlooms || [
    {
      id: 'HLM-001',
      dynasty_id: 'DYN-H0044',
      name: 'The Vance Founding Signet',
      heirloom_type: 'founder_seal',
      quality_tier: 'Legendary',
      stat_buff: '+10% Machine Build Speed & -15% Business Startup Fees',
      equipped_by_human_id: null,
      inscription: 'Forged from titanium.',
      created_at: new Date().toISOString(),
    },
  ];

  return {
    async query(sql, params = []) {
      const s = sql.trim().toUpperCase();

      if (s.includes('FROM DYNASTIES WHERE EMAIL = $1')) {
        const found = dynasties.find((d) => d.email === params[0] || d.id === params[1]);
        return { rows: found ? [found] : [] };
      }

      if (s.includes('FROM DYNASTY_LINEAGE_RECORDS WHERE DYNASTY_ID = $1')) {
        const rows = lineage.filter((l) => l.dynasty_id === params[0]);
        return { rows };
      }

      if (s.includes('FROM DYNASTY_PERKS WHERE DYNASTY_ID = $1 AND PERK_KEY = $2')) {
        const rows = perks.filter((p) => p.dynasty_id === params[0] && p.perk_key === params[1]);
        return { rows };
      }

      if (s.includes('FROM DYNASTY_PERKS WHERE DYNASTY_ID = $1')) {
        const rows = perks.filter((p) => p.dynasty_id === params[0]);
        return { rows };
      }

      if (s.includes('FROM DYNASTY_HEIRLOOMS WHERE ID = $1 AND DYNASTY_ID = $2')) {
        const found = heirlooms.find((h) => h.id === params[0] && h.dynasty_id === params[1]);
        return { rows: found ? [found] : [] };
      }

      if (s.includes('FROM DYNASTY_HEIRLOOMS WHERE DYNASTY_ID = $1')) {
        const rows = heirlooms.filter((h) => h.dynasty_id === params[0]);
        return { rows };
      }

      if (s.includes('INSERT INTO DYNASTY_PERKS')) {
        const newPerk = {
          id: params[0],
          dynasty_id: params[1],
          perk_key: params[2],
          perk_name: params[3],
          perk_category: params[4],
          tier: params[5],
          unlocked_game_day: params[6],
        };
        perks.push(newPerk);
        return { rows: [newPerk] };
      }

      if (s.includes('UPDATE DYNASTIES') && s.includes('SET LEGACY_POINTS = LEGACY_POINTS - $1')) {
        const dyn = dynasties.find((d) => d.id === params[1]);
        if (dyn) dyn.legacy_points -= params[0];
        return { rows: [dyn] };
      }

      if (s.includes('UPDATE DYNASTY_HEIRLOOMS SET EQUIPPED_BY_HUMAN_ID = $1 WHERE ID = $2')) {
        const h = heirlooms.find((x) => x.id === params[1]);
        if (h) h.equipped_by_human_id = params[0];
        return { rows: [h] };
      }

      if (s.includes('INSERT INTO DYNASTY_HEIRLOOMS')) {
        const newH = {
          id: params[0],
          dynasty_id: params[1],
          name: params[2],
          heirloom_type: params[3],
          quality_tier: params[4],
          stat_buff: params[5],
          equipped_by_human_id: params[6],
          inscription: params[7],
        };
        heirlooms.push(newH);
        return { rows: [newH] };
      }

      if (s.includes('UPDATE DYNASTIES SET MOTTO = $1, DYNASTY_NAME = $2 WHERE ID = $3')) {
        const dyn = dynasties.find((d) => d.id === params[2]);
        if (dyn) {
          dyn.motto = params[0];
          dyn.dynasty_name = params[1];
        }
        return { rows: [dyn] };
      }

      return { rows: [] };
    },
  };
}

test('getDynastyOverview queries dynasty, lineage, perks, and catalog', async () => {
  const db = createMockDb();
  const res = await getDynastyOverview(db, 'amara@earth.local', 'H-0044', 'Amara Vance');

  assert.equal(res.ok, true);
  assert.equal(res.dynasty.dynasty_name, 'House Vance');
  assert.equal(res.lineage.length, 1);
  assert.equal(res.heirlooms.length, 1);
  assert.equal(res.catalogPerks.length, 5);
});

test('unlockDynastyPerk deducts legacy points and records perk', async () => {
  const db = createMockDb();
  const res = await unlockDynastyPerk(db, 'amara@earth.local', 'industrialist_lineage', 140);

  assert.equal(res.ok, true);
  assert.equal(res.perkKey, 'industrialist_lineage');
  assert.equal(res.remainingPoints, 250); // 350 - 100
});

test('equipDynastyHeirloom toggles equip status', async () => {
  const db = createMockDb();
  const res1 = await equipDynastyHeirloom(db, 'amara@earth.local', 'HLM-001', 'H-0044');
  assert.equal(res1.ok, true);
  assert.equal(res1.isEquipped, true);
  assert.equal(res1.equippedBy, 'H-0044');

  const res2 = await equipDynastyHeirloom(db, 'amara@earth.local', 'HLM-001', 'H-0044');
  assert.equal(res2.ok, true);
  assert.equal(res2.isEquipped, false);
  assert.equal(res2.equippedBy, null);
});

test('forgeDynastyHeirloom and updateDynastyMotto succeed', async () => {
  const db = createMockDb();
  const forgeRes = await forgeDynastyHeirloom(
    db,
    'amara@earth.local',
    'Senate Gavel of Truth',
    'senate_gavel',
    'Used to ratify World Charter.',
    '+20% Voting Weight'
  );
  assert.equal(forgeRes.ok, true);
  assert.equal(forgeRes.heirloom.name, 'Senate Gavel of Truth');

  const mottoRes = await updateDynastyMotto(db, 'amara@earth.local', 'Per Aspera Ad Astra', 'House Vance-Neo');
  assert.equal(mottoRes.ok, true);
  assert.equal(mottoRes.motto, 'Per Aspera Ad Astra');
  assert.equal(mottoRes.dynastyName, 'House Vance-Neo');
});
