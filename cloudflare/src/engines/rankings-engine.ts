import type { PostgresRepository } from '../repository.ts';

export interface RankingsSettlementResult {
  corporationsSettled: number;
  citiesSettled: number;
  citizensSettled: number;
  gameDay: number;
}

export function formatCompact(num: number): string {
  const n = Math.abs(num);
  if (n >= 1_000_000_000) {
    const val = (num / 1_000_000_000).toFixed(1);
    return `${val.endsWith('.0') ? val.slice(0, -2) : val}B`;
  }
  if (n >= 1_000_000) {
    const val = (num / 1_000_000).toFixed(1);
    return `${val.endsWith('.0') ? val.slice(0, -2) : val}M`;
  }
  if (n >= 1_000) {
    const val = (num / 1_000).toFixed(1);
    return `${val.endsWith('.0') ? val.slice(0, -2) : val}k`;
  }
  return `${Math.round(num)}`;
}

export async function settleContinuousRankings(
  repo: PostgresRepository,
  currDay: number,
  prevDay?: number,
): Promise<RankingsSettlementResult> {
  // ---------------------------------------------------------
  // 1. Settle Cities Rankings First (Base of Corporate Hierarchy)
  // ---------------------------------------------------------
  const cityRows = (
    await repo.query<{
      id: string;
      name: string;
      corporation_id: string | null;
      residents: number;
      housing_capacity: number;
      energy_capacity: number;
      connectivity_capacity: number;
      health_capacity: number;
      treasury: number | string;
      corporation_name: string | null;
      businesses_count: number | string;
      buildings_valuation: number | string;
    }>(`
      SELECT c.id,
             ci.name,
             COALESCE(
               c.corporation_id,
               (SELECT m.corporation_id FROM memberships m WHERE m.city_id = c.id AND m.corporation_id IS NOT NULL LIMIT 1),
               (SELECT corp.id FROM corporations corp WHERE corp.capital_city_id = c.id OR corp.institution_id = c.corporation_id LIMIT 1)
             ) AS corporation_id,
             GREATEST(1, c.residents) AS residents,
             GREATEST(0, c.housing_capacity) AS housing_capacity,
             GREATEST(0, c.energy_capacity) AS energy_capacity,
             GREATEST(0, c.connectivity_capacity) AS connectivity_capacity,
             GREATEST(0, c.health_capacity) AS health_capacity,
             GREATEST(0, COALESCE(c.treasury, 0)) AS treasury,
             COALESCE(
               (SELECT i.name FROM institutions i WHERE i.id = c.corporation_id),
               (SELECT i.name FROM corporations corp JOIN institutions i ON i.id = corp.institution_id WHERE corp.id = c.corporation_id),
               (SELECT i.name FROM memberships m JOIN corporations corp ON corp.id = m.corporation_id JOIN institutions i ON i.id = corp.institution_id WHERE m.city_id = c.id LIMIT 1),
               'Independent'
             ) AS corporation_name,
             COALESCE((SELECT COUNT(*) FROM businesses b JOIN memberships m ON m.human_id = b.owner_id WHERE m.city_id = c.id AND b.status = 'active'), 0)::integer AS businesses_count,
             COALESCE((SELECT SUM(COALESCE(bld.tier * 10000, 5000)) FROM buildings bld WHERE bld.city_id = c.id), 0)::numeric AS buildings_valuation
      FROM cities c
      JOIN institutions ci ON ci.id = c.institution_id
      WHERE c.status = 'active'
    `)
  ).rows;

  // Calculate City Capitalizations: Liquid Treasury + Real Estate/Infrastructure Valuation
  const rawCityList = cityRows.map((c) => {
    const res = Number(c.residents) || 1;
    const treasury = Number(c.treasury) || 0;
    const buildingsVal = Number(c.buildings_valuation) || 0;
    const infrastructureVal = (c.housing_capacity + c.energy_capacity + c.connectivity_capacity + c.health_capacity) * 25;
    const capitalization = treasury + buildingsVal + infrastructureVal;

    const housingRatio = c.housing_capacity / res;
    const energyRatio = c.energy_capacity / res;
    const connectivityRatio = c.connectivity_capacity / res;
    const healthVal = c.health_capacity;
    const coverageComposite = (housingRatio + energyRatio + connectivityRatio + (healthVal / 100.0)) / 4.0;
    const businesses = Number(c.businesses_count) || 0;

    return {
      ...c,
      res,
      treasury,
      capitalization,
      coverageComposite,
      businesses,
    };
  });

  let maxCityCap = 1;
  let maxCityCoverage = 1;
  let maxCityBiz = 1;
  let maxCityRes = 1;

  for (const c of rawCityList) {
    if (c.capitalization > maxCityCap) maxCityCap = c.capitalization;
    if (c.coverageComposite > maxCityCoverage) maxCityCoverage = c.coverageComposite;
    if (c.businesses > maxCityBiz) maxCityBiz = c.businesses;
    if (c.res > maxCityRes) maxCityRes = c.res;
  }

  const computedCities = rawCityList.map((c) => {
    const subCap = Math.min(1, Math.max(0, c.capitalization / maxCityCap));
    const subCoverage = Math.min(1, Math.max(0, c.coverageComposite / maxCityCoverage));
    const subBiz = Math.min(1, Math.max(0, c.businesses / maxCityBiz));
    const subRes = Math.min(1, Math.max(0, c.res / maxCityRes));

    const finalScore = Math.round(35 * subCap + 35 * subCoverage + 20 * subBiz + 10 * subRes);
    const metricsLine = `${formatCompact(c.capitalization)} Cap · ${c.businesses} Biz · ${c.res} Res`;

    return {
      entityId: c.id,
      entityName: c.name || 'City',
      corporationId: c.corporation_id,
      finalScore,
      capitalization: c.capitalization,
      businesses: c.businesses,
      residents: c.res,
      metricsLine,
      subIndexes: {
        capitalization: Number(subCap.toFixed(4)),
        infrastructure: Number(subCoverage.toFixed(4)),
        businesses: Number(subBiz.toFixed(4)),
        residents: Number(subRes.toFixed(4)),
      },
      rawMetrics: {
        capitalization: c.capitalization,
        treasury: c.treasury,
        housing_capacity: c.housing_capacity,
        energy_capacity: c.energy_capacity,
        connectivity_capacity: c.connectivity_capacity,
        health_capacity: c.health_capacity,
        businesses: c.businesses,
        residents: c.res,
      },
      affiliation: c.corporation_name || 'Independent',
      sortScore: finalScore * 1000000 + c.capitalization,
    };
  });

  computedCities.sort((a, b) => b.sortScore - a.sortScore);

  for (let idx = 0; idx < computedCities.length; idx++) {
    const item = computedCities[idx];
    const newRank = idx + 1;

    await repo.query(
      `INSERT INTO civic_rankings (
        id, category, entity_id, entity_name, rank, rank_delta, final_score, metrics_line, sub_indexes, raw_metrics, affiliation, game_day, updated_at
      ) VALUES (
        $1, 'cities', $2, $3, $4, 0, $5, $6, $7::jsonb, $8::jsonb, $9, $10, CURRENT_TIMESTAMP
      ) ON CONFLICT (category, entity_id) DO UPDATE SET
        entity_name = EXCLUDED.entity_name,
        rank_delta = civic_rankings.rank - EXCLUDED.rank,
        rank = EXCLUDED.rank,
        final_score = EXCLUDED.final_score,
        metrics_line = EXCLUDED.metrics_line,
        sub_indexes = EXCLUDED.sub_indexes,
        raw_metrics = EXCLUDED.raw_metrics,
        affiliation = EXCLUDED.affiliation,
        game_day = EXCLUDED.game_day,
        updated_at = CURRENT_TIMESTAMP`,
      [
        `city:${item.entityId}`,
        item.entityId,
        item.entityName,
        newRank,
        item.finalScore,
        item.metricsLine,
        JSON.stringify(item.subIndexes),
        JSON.stringify(item.rawMetrics),
        item.affiliation,
        currDay,
      ],
    );
  }

  // ---------------------------------------------------------
  // 2. Settle Corporations Rankings (Hierarchical Rollup from Cities)
  // ---------------------------------------------------------
  const corpRows = (
    await repo.query<{
      id: string;
      name: string;
      member_count: number;
      treasury: number | string;
    }>(`
      SELECT c.id,
             i.name,
             GREATEST(0, c.member_count) AS member_count,
             GREATEST(0, COALESCE(c.treasury, 0)) AS treasury
      FROM corporations c
      JOIN institutions i ON i.id = c.institution_id
      WHERE i.status = 'active'
    `)
  ).rows;

  const rawCorpList = corpRows.map((c) => {
    const directTreasury = Number(c.treasury) || 0;
    const directMembers = Number(c.member_count) || 0;

    // Roll up from constituent cities
    const corpCities = computedCities.filter((city) => city.corporationId === c.id);
    const rolledUpCityCap = corpCities.reduce((sum, city) => sum + city.capitalization, 0);
    const rolledUpCityBiz = corpCities.reduce((sum, city) => sum + city.businesses, 0);
    const rolledUpCityRes = corpCities.reduce((sum, city) => sum + city.residents, 0);
    const avgCityScore = corpCities.length > 0
      ? corpCities.reduce((sum, city) => sum + city.finalScore, 0) / corpCities.length
      : 0;

    const totalCapitalization = directTreasury + rolledUpCityCap;
    const totalBusinesses = rolledUpCityBiz;
    const totalResidents = Math.max(directMembers, rolledUpCityRes);

    return {
      id: c.id,
      name: c.name,
      totalCapitalization,
      totalBusinesses,
      totalResidents,
      avgCityScore,
      directTreasury,
      directMembers,
    };
  });

  let maxCorpCap = 1;
  let maxCorpBiz = 1;
  let maxCorpRes = 1;

  for (const c of rawCorpList) {
    if (c.totalCapitalization > maxCorpCap) maxCorpCap = c.totalCapitalization;
    if (c.totalBusinesses > maxCorpBiz) maxCorpBiz = c.totalBusinesses;
    if (c.totalResidents > maxCorpRes) maxCorpRes = c.totalResidents;
  }

  const computedCorps = rawCorpList.map((c) => {
    const subCap = Math.min(1, Math.max(0, c.totalCapitalization / maxCorpCap));
    const subBiz = Math.min(1, Math.max(0, c.totalBusinesses / maxCorpBiz));
    const subCityScore = Math.min(1, Math.max(0, c.avgCityScore / 100.0));
    const subRes = Math.min(1, Math.max(0, c.totalResidents / maxCorpRes));

    const finalScore = Math.round(45 * subCap + 30 * subBiz + 15 * subCityScore + 10 * subRes);
    const metricsLine = `${formatCompact(c.totalCapitalization)} Cap · ${c.totalBusinesses} Biz · ${c.totalResidents} Res`;

    return {
      entityId: c.id,
      entityName: c.name || 'Corporation',
      finalScore,
      metricsLine,
      subIndexes: {
        capitalization: Number(subCap.toFixed(4)),
        businesses: Number(subBiz.toFixed(4)),
        municipalExcellence: Number(subCityScore.toFixed(4)),
        residents: Number(subRes.toFixed(4)),
      },
      rawMetrics: {
        totalCapitalization: c.totalCapitalization,
        totalBusinesses: c.totalBusinesses,
        totalResidents: c.totalResidents,
        avgCityScore: c.avgCityScore,
        directTreasury: c.directTreasury,
      },
      affiliation: null,
      sortScore: finalScore * 1000000 + c.totalCapitalization,
    };
  });

  computedCorps.sort((a, b) => b.sortScore - a.sortScore);

  for (let idx = 0; idx < computedCorps.length; idx++) {
    const item = computedCorps[idx];
    const newRank = idx + 1;

    await repo.query(
      `INSERT INTO civic_rankings (
        id, category, entity_id, entity_name, rank, rank_delta, final_score, metrics_line, sub_indexes, raw_metrics, affiliation, game_day, updated_at
      ) VALUES (
        $1, 'corporations', $2, $3, $4, 0, $5, $6, $7::jsonb, $8::jsonb, $9, $10, CURRENT_TIMESTAMP
      ) ON CONFLICT (category, entity_id) DO UPDATE SET
        entity_name = EXCLUDED.entity_name,
        rank_delta = civic_rankings.rank - EXCLUDED.rank,
        rank = EXCLUDED.rank,
        final_score = EXCLUDED.final_score,
        metrics_line = EXCLUDED.metrics_line,
        sub_indexes = EXCLUDED.sub_indexes,
        raw_metrics = EXCLUDED.raw_metrics,
        affiliation = EXCLUDED.affiliation,
        game_day = EXCLUDED.game_day,
        updated_at = CURRENT_TIMESTAMP`,
      [
        `corp:${item.entityId}`,
        item.entityId,
        item.entityName,
        newRank,
        item.finalScore,
        item.metricsLine,
        JSON.stringify(item.subIndexes),
        JSON.stringify(item.rawMetrics),
        item.affiliation,
        currDay,
      ],
    );
  }

  // ---------------------------------------------------------
  // 3. Settle Citizens Rankings (Personal Legacy + Standing + Personal Net Worth)
  // ---------------------------------------------------------
  const citizenRows = (
    await repo.query<{
      id: string;
      display_name: string;
      standing: number;
      legacy: number;
      credits: number | string;
      machine_assets_val: number | string;
      city_name: string | null;
      corporation_name: string | null;
    }>(`
      SELECT humans.id,
             humans.display_name,
             GREATEST(0, humans.standing) AS standing,
             GREATEST(0, humans.legacy) AS legacy,
             GREATEST(0, COALESCE(ab.balance, 0)) AS credits,
             COALESCE((SELECT COUNT(*) * 5000 FROM machines m WHERE m.owner_id = humans.id), 0)::numeric AS machine_assets_val,
             COALESCE(
               (SELECT i.name FROM institutions i WHERE i.id = memberships.city_id),
               (SELECT i.name FROM cities c JOIN institutions i ON i.id = c.institution_id WHERE c.id = memberships.city_id)
             ) AS city_name,
             COALESCE(
               (SELECT i.name FROM institutions i WHERE i.id = memberships.corporation_id),
               (SELECT i.name FROM corporations corp JOIN institutions i ON i.id = corp.institution_id WHERE corp.id = memberships.corporation_id),
               (SELECT i.name FROM cities c JOIN corporations corp ON corp.id = c.corporation_id JOIN institutions i ON i.id = corp.institution_id WHERE c.id = memberships.city_id)
             ) AS corporation_name
      FROM humans
      LEFT JOIN account_balances ab ON ab.account_id = humans.account_id AND ab.currency = 'CREDIT'
      LEFT JOIN memberships ON memberships.human_id = humans.id
      WHERE humans.life_status = 'active'
    `)
  ).rows;

  const rawCitizenList = citizenRows.map((h) => {
    const leg = Number(h.legacy) || 0;
    const std = Number(h.standing) || 0;
    const liquidCredits = Number(h.credits) || 0;
    const machineVal = Number(h.machine_assets_val) || 0;
    const personalCapitalization = liquidCredits + machineVal;

    return {
      ...h,
      leg,
      std,
      liquidCredits,
      personalCapitalization,
    };
  });

  let maxLegacy = 1;
  let maxStanding = 1;
  let maxCitizenCap = 1;

  for (const h of rawCitizenList) {
    if (h.leg > maxLegacy) maxLegacy = h.leg;
    if (h.std > maxStanding) maxStanding = h.std;
    if (h.personalCapitalization > maxCitizenCap) maxCitizenCap = h.personalCapitalization;
  }

  const computedCitizens = rawCitizenList.map((h) => {
    const subLegacy = Math.min(1, Math.max(0, h.leg / maxLegacy));
    const subStanding = Math.min(1, Math.max(0, h.std / maxStanding));
    const subCap = Math.min(1, Math.max(0, h.personalCapitalization / maxCitizenCap));

    const finalScore = Math.round(45 * subLegacy + 35 * subStanding + 20 * subCap);
    const metricsLine = `${h.leg} Leg · ${h.std} Std · ${formatCompact(h.personalCapitalization)} Cap`;

    const affParts: string[] = [];
    if (h.corporation_name && h.corporation_name !== 'Independent') affParts.push(h.corporation_name);
    if (h.city_name && h.city_name !== 'Independent') affParts.push(h.city_name);
    const affiliation = affParts.length > 0 ? affParts.join(' · ') : 'Independent';

    return {
      entityId: h.id,
      entityName: h.display_name || 'Citizen',
      finalScore,
      metricsLine,
      subIndexes: {
        legacy: Number(subLegacy.toFixed(4)),
        standing: Number(subStanding.toFixed(4)),
        capitalization: Number(subCap.toFixed(4)),
      },
      rawMetrics: {
        legacy: h.leg,
        standing: h.std,
        liquidCredits: h.liquidCredits,
        personalCapitalization: h.personalCapitalization,
      },
      affiliation,
      sortScore: finalScore * 1000000 + h.std * 1000 + h.leg,
    };
  });

  computedCitizens.sort((a, b) => b.sortScore - a.sortScore);

  for (let idx = 0; idx < computedCitizens.length; idx++) {
    const item = computedCitizens[idx];
    const newRank = idx + 1;

    await repo.query(
      `INSERT INTO civic_rankings (
        id, category, entity_id, entity_name, rank, rank_delta, final_score, metrics_line, sub_indexes, raw_metrics, affiliation, game_day, updated_at
      ) VALUES (
        $1, 'citizens', $2, $3, $4, 0, $5, $6, $7::jsonb, $8::jsonb, $9, $10, CURRENT_TIMESTAMP
      ) ON CONFLICT (category, entity_id) DO UPDATE SET
        entity_name = EXCLUDED.entity_name,
        rank_delta = civic_rankings.rank - EXCLUDED.rank,
        rank = EXCLUDED.rank,
        final_score = EXCLUDED.final_score,
        metrics_line = EXCLUDED.metrics_line,
        sub_indexes = EXCLUDED.sub_indexes,
        raw_metrics = EXCLUDED.raw_metrics,
        affiliation = EXCLUDED.affiliation,
        game_day = EXCLUDED.game_day,
        updated_at = CURRENT_TIMESTAMP`,
      [
        `citizen:${item.entityId}`,
        item.entityId,
        item.entityName,
        newRank,
        item.finalScore,
        item.metricsLine,
        JSON.stringify(item.subIndexes),
        JSON.stringify(item.rawMetrics),
        item.affiliation,
        currDay,
      ],
    );
  }

  return {
    corporationsSettled: computedCorps.length,
    citiesSettled: computedCities.length,
    citizensSettled: computedCitizens.length,
    gameDay: currDay,
  };
}
