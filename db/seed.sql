insert into humans (id, account_id, display_name, age_years, standing, legacy)
values ('H-0044', 'account-amara', 'Amara Kline', 31, 742, 31)
on conflict (id) do nothing;

insert into institutions (id, kind, name) values
  ('OUC-001', 'OUC', 'Organization of United Corporations'),
  ('CORP-001', 'CORPORATION', 'Helios Cooperative'),
  ('CITY-0084', 'CITY', 'New Carthage'),
  ('BUS-1048', 'BUSINESS', 'Kline Works')
on conflict (id) do nothing;

insert into cities (id, institution_id, residents, housing_capacity, energy_capacity, connectivity_capacity, health_capacity, treasury)
values ('CITY-0084', 'CITY-0084', 0, 100, 100, 100, 50, 0)
on conflict (id) do nothing;

insert into corporations (id, institution_id, member_count, treasury, constitution_version)
values ('CORP-001', 'CORP-001', 0, 0, 1)
on conflict (id) do nothing;

insert into technologies (id, name, owner_id, progress)
values ('TECH-001', 'Building Systems Optimization', 'H-0044', 72)
on conflict (id) do nothing;

insert into world_state (id, game_day, game_minute, health, market_batch_seconds)
values ('WORLD', 184, 462, 68, 498)
on conflict (id) do nothing;

insert into businesses (id, owner_id, name, policy, condition)
values ('B-1048', 'H-0044', 'Kline Works', 'reliability', 96)
on conflict (id) do nothing;

insert into resource_balances (owner_id, resource, amount) values
  ('H-0044', 'material', 420), ('H-0044', 'components', 86),
  ('H-0044', 'energy', 92), ('H-0044', 'compute', 64)
on conflict (owner_id, resource) do nothing;

insert into business_financials (business_id, revenue, operating_costs, profit, taxed_revenue, last_game_day)
values ('B-1048', 1240, 820, 420, 0, 184)
on conflict (business_id) do nothing;

insert into business_shares (business_id, holder_id, shares)
values ('B-1048', 'H-0044', 100)
on conflict (business_id, holder_id) do nothing;

insert into business_management (business_id, manager_id, appointed_by, appointed_game_day)
values ('B-1048', 'H-0044', 'H-0044', 184)
on conflict (business_id) do nothing;

insert into business_constitutions (business_id, updated_by, updated_game_day)
values ('B-1048', 'H-0044', 184)
on conflict (business_id) do nothing;

insert into research_projects (id, technology_id, owner_id, budget, progress, status, started_game_day)
values ('R-1048-01', 'TECH-001', 'H-0044', 120, 25, 'active', 180)
on conflict (id) do nothing;

-- Local UI/API test fixtures. IDs are namespaced so this block is safe to re-run
-- and easy to remove from a disposable local database.
insert into humans (id, account_id, display_name, age_years, standing, legacy)
values
  ('TEST-H-001', 'test-account-001', 'Mira Solberg', 28, 610, 12),
  ('TEST-H-002', 'test-account-002', 'Jonas Reed', 42, 488, 35),
  ('TEST-H-003', 'test-account-003', 'Leila Okafor', 36, 815, 20),
  ('TEST-H-004', 'test-account-004', 'Tomas Varga', 24, 355, 4)
on conflict (id) do nothing;

insert into institutions (id, kind, name)
values
  ('TEST-CORP-001', 'CORPORATION', 'Northstar Systems'),
  ('TEST-CORP-002', 'CORPORATION', 'Verdant Grid Cooperative'),
  ('TEST-CORP-003', 'CORPORATION', 'Orbital Freight Union'),
  ('TEST-CITY-001', 'CITY', 'Aurora Basin'),
  ('TEST-CITY-002', 'CITY', 'Port Meridian'),
  ('TEST-CITY-003', 'CITY', 'Cedar Reach')
on conflict (id) do nothing;

insert into cities (id, institution_id, residents, housing_capacity, energy_capacity, connectivity_capacity, health_capacity, treasury)
values
  ('TEST-CITY-001', 'TEST-CITY-001', 2, 240, 180, 210, 165, 18500),
  ('TEST-CITY-002', 'TEST-CITY-002', 1, 140, 260, 190, 120, 9200),
  ('TEST-CITY-003', 'TEST-CITY-003', 1, 180, 150, 130, 205, 12750)
on conflict (id) do nothing;

insert into corporations (id, institution_id, member_count, treasury, constitution_version, capital_city_id, admission_policy)
values
  ('TEST-CORP-001', 'TEST-CORP-001', 2, 78000, 3, 'TEST-CITY-001', 'open'),
  ('TEST-CORP-002', 'TEST-CORP-002', 1, 42500, 2, 'TEST-CITY-002', 'approval'),
  ('TEST-CORP-003', 'TEST-CORP-003', 1, 61000, 4, 'TEST-CITY-003', 'open')
on conflict (id) do nothing;

update cities
set corporation_id = case id
  when 'TEST-CITY-001' then 'TEST-CORP-001'
  when 'TEST-CITY-002' then 'TEST-CORP-002'
  when 'TEST-CITY-003' then 'TEST-CORP-003'
end
where id in ('TEST-CITY-001', 'TEST-CITY-002', 'TEST-CITY-003');

insert into memberships (human_id, corporation_id, city_id, joined_game_day)
values
  ('TEST-H-001', 'TEST-CORP-001', 'TEST-CITY-001', 210),
  ('TEST-H-002', 'TEST-CORP-001', 'TEST-CITY-001', 215),
  ('TEST-H-003', 'TEST-CORP-002', 'TEST-CITY-002', 220),
  ('TEST-H-004', 'TEST-CORP-003', 'TEST-CITY-003', 225)
on conflict (human_id) do nothing;

insert into humans (id, account_id, display_name, age_years, standing, legacy)
values
  ('TEST-H-005', 'test-account-005', 'Nia Bennett', 31, 540, 9),
  ('TEST-H-006', 'test-account-006', 'Oskar Lind', 47, 675, 42),
  ('TEST-H-007', 'test-account-007', 'Priya Nandakumar', 39, 730, 27),
  ('TEST-H-008', 'test-account-008', 'Rafael Costa', 26, 402, 7),
  ('TEST-H-009', 'test-account-009', 'Sana Ito', 33, 590, 18),
  ('TEST-H-010', 'test-account-010', 'Elias Novak', 52, 460, 51)
on conflict (id) do nothing;

insert into institutions (id, kind, name)
values
  ('TEST-CITY-004', 'CITY', 'Northstar Landing'),
  ('TEST-CITY-005', 'CITY', 'Summit Vale'),
  ('TEST-CITY-006', 'CITY', 'Delta Commons'),
  ('CITY-0091', 'CITY', 'Helios Cooperative Harbor')
on conflict (id) do nothing;

insert into cities (id, institution_id, residents, housing_capacity, energy_capacity, connectivity_capacity, health_capacity, treasury)
values
  ('TEST-CITY-004', 'TEST-CITY-004', 2, 220, 230, 175, 145, 16400),
  ('TEST-CITY-005', 'TEST-CITY-005', 1, 160, 195, 220, 135, 11100),
  ('TEST-CITY-006', 'TEST-CITY-006', 1, 200, 170, 160, 190, 13800),
  ('CITY-0091', 'CITY-0091', 2, 180, 210, 155, 130, 7600)
on conflict (id) do nothing;

update cities
set corporation_id = case id
  when 'TEST-CITY-004' then 'TEST-CORP-001'
  when 'TEST-CITY-005' then 'TEST-CORP-001'
  when 'TEST-CITY-006' then 'TEST-CORP-002'
  when 'CITY-0091' then 'CORP-001'
end
where id in ('TEST-CITY-004', 'TEST-CITY-005', 'TEST-CITY-006', 'CITY-0091');

insert into memberships (human_id, corporation_id, city_id, joined_game_day)
values
  ('TEST-H-005', 'TEST-CORP-001', 'TEST-CITY-004', 230),
  ('TEST-H-006', 'TEST-CORP-001', 'TEST-CITY-004', 231),
  ('TEST-H-007', 'TEST-CORP-001', 'TEST-CITY-005', 232),
  ('TEST-H-008', 'TEST-CORP-002', 'TEST-CITY-006', 233),
  ('TEST-H-009', 'CORP-001', 'CITY-0091', 234),
  ('TEST-H-010', 'CORP-001', 'CITY-0091', 235)
on conflict (human_id) do nothing;

update corporations
set member_count = (select count(*) from memberships where memberships.corporation_id = corporations.id)
where id in ('CORP-001', 'TEST-CORP-001', 'TEST-CORP-002');

update institutions
set name = 'Northstar Landing'
where id = 'TEST-CITY-004';

update cities
set residents = (select count(*) from memberships where memberships.city_id = cities.id)
where id in ('CITY-0091', 'TEST-CITY-004', 'TEST-CITY-005', 'TEST-CITY-006');

insert into communities (id, name, founder_id, status, shared_credits, description, admission_policy)
values
  ('TEST-COMM-001', 'Aurora Makers Guild', 'TEST-H-001', 'active', 1250, 'A practical community for builders, repairers, and industrial designers.', 'open'),
  ('TEST-COMM-002', 'Port Meridian Civic Lab', 'TEST-H-003', 'active', 640, 'Residents experimenting with better civic services and shared infrastructure.', 'approval'),
  ('TEST-COMM-003', 'Freight & Futures Circle', 'TEST-H-004', 'active', 300, 'A discussion and trading group for logistics, markets, and long-range planning.', 'open'),
  ('TEST-COMM-004', 'Cedar Commons', 'TEST-H-007', 'active', 2100, 'A neighborhood commons focused on learning, health, and mutual support.', 'approval')
on conflict (id) do nothing;

insert into community_members (community_id, human_id, role, joined_game_day)
values
  ('TEST-COMM-001', 'TEST-H-001', 'founder', 240),
  ('TEST-COMM-001', 'TEST-H-002', 'member', 241),
  ('TEST-COMM-001', 'TEST-H-005', 'admin', 242),
  ('TEST-COMM-001', 'TEST-H-007', 'member', 243),
  ('TEST-COMM-002', 'TEST-H-003', 'founder', 244),
  ('TEST-COMM-002', 'TEST-H-008', 'member', 245),
  ('TEST-COMM-002', 'TEST-H-009', 'member', 246),
  ('TEST-COMM-003', 'TEST-H-004', 'founder', 247),
  ('TEST-COMM-003', 'TEST-H-006', 'member', 248),
  ('TEST-COMM-003', 'TEST-H-010', 'member', 249),
  ('TEST-COMM-004', 'TEST-H-007', 'founder', 250),
  ('TEST-COMM-004', 'TEST-H-001', 'member', 251),
  ('TEST-COMM-004', 'TEST-H-003', 'admin', 252)
on conflict (community_id, human_id) do nothing;

insert into community_membership_requests (id, community_id, human_id, status, requested_game_day)
values
  ('TEST-COMM-REQ-001', 'TEST-COMM-002', 'TEST-H-006', 'pending', 253),
  ('TEST-COMM-REQ-002', 'TEST-COMM-004', 'TEST-H-010', 'pending', 254)
on conflict (id) do nothing;

-- Archive and house page fixtures.
insert into humans (id, account_id, display_name, age_years, standing, legacy, life_status, political_eligibility_game_day)
values
  ('TEST-H-011', 'test-account-011', 'Ada Mercer', 88, 920, 410, 'deceased', 0),
  ('TEST-H-012', 'test-account-012', 'Bastien Okoro', 74, 780, 295, 'deceased', 0),
  ('TEST-H-013', 'test-account-013', 'Clara Mercer', 67, 865, 340, 'deceased', 0),
  ('TEST-H-014', 'test-account-014', 'Darius Okoro', 61, 705, 260, 'deceased', 0)
on conflict (id) do nothing;

insert into houses (id, email, house_name, motto, founder_human_id, legacy_points, total_wealth_generated)
values
  ('TEST-HSE-001', 'ada.mercer@earth.local', 'House Mercer', 'Measure twice, build for generations.', 'TEST-H-011', 820, 980000),
  ('TEST-HSE-002', 'bastien.okoro@earth.local', 'House Okoro', 'Knowledge is the longest inheritance.', 'TEST-H-012', 560, 640000)
on conflict (id) do nothing;

insert into deceased_profiles (
  human_id, display_name, death_game_day, final_standing, final_legacy, successor_name,
  birth_game_day, cause_of_death, epitaph, lifetime_dividends, predecessor_human_id, house_name
)
values
  ('TEST-H-011', 'Ada Mercer', 310, 920, 410, 'Clara Mercer', 12, 'Natural Aging', 'Her civic designs became the blueprint for three thriving cities.', 18400, null, 'House Mercer'),
  ('TEST-H-012', 'Bastien Okoro', 298, 780, 295, 'Darius Okoro', 34, 'Quiet Orbital Passage', 'He connected the first open research exchanges across the southern arc.', 12750, null, 'House Okoro'),
  ('TEST-H-013', 'Clara Mercer', 366, 865, 340, 'Mira Solberg', 105, 'Natural Aging', 'She made public infrastructure a shared inheritance.', 16200, 'TEST-H-011', 'House Mercer'),
  ('TEST-H-014', 'Darius Okoro', 351, 705, 260, 'Priya Nandakumar', 126, 'Frontier Transit Incident', 'He carried House Okoro into the age of intercity trade.', 10900, 'TEST-H-012', 'House Okoro')
on conflict (human_id) do nothing;

insert into life_events (id, human_id, event_type, game_day, successor_name, estate_credits)
values
  ('TEST-LIFE-011-DEATH', 'TEST-H-011', 'death', 310, 'Clara Mercer', 218000),
  ('TEST-LIFE-012-DEATH', 'TEST-H-012', 'death', 298, 'Darius Okoro', 154000),
  ('TEST-LIFE-013-DEATH', 'TEST-H-013', 'death', 366, 'Mira Solberg', 192000),
  ('TEST-LIFE-014-DEATH', 'TEST-H-014', 'death', 351, 'Priya Nandakumar', 137000)
on conflict (id) do nothing;

insert into character_lineage (id, email, human_id, predecessor_human_id, generation, birth_game_day, death_game_day, final_legacy, house_name)
values
  ('TEST-LINEAGE-011', 'ada.mercer@earth.local', 'TEST-H-011', null, 1, 12, 310, 410, 'House Mercer'),
  ('TEST-LINEAGE-013', 'ada.mercer@earth.local', 'TEST-H-013', 'TEST-H-011', 2, 105, 366, 340, 'House Mercer'),
  ('TEST-LINEAGE-012', 'bastien.okoro@earth.local', 'TEST-H-012', null, 1, 34, 298, 295, 'House Okoro'),
  ('TEST-LINEAGE-014', 'bastien.okoro@earth.local', 'TEST-H-014', 'TEST-H-012', 2, 126, 351, 260, 'House Okoro')
on conflict (id) do nothing;

insert into house_lineage_records (
  id, house_id, human_id, predecessor_human_id, generation, name, title,
  birth_game_day, death_game_day, is_incumbent, cause_of_death, epitaph,
  lifetime_wealth, businesses_founded, proposals_authored, legacy_score
)
values
  ('TEST-HLR-011', 'TEST-HSE-001', 'TEST-H-011', null, 1, 'Ada Mercer', 'Founding Architect', 12, 310, false, 'Natural Aging', 'Her civic designs became the blueprint for three thriving cities.', 520000, 5, 11, 410),
  ('TEST-HLR-013', 'TEST-HSE-001', 'TEST-H-013', 'TEST-H-011', 2, 'Clara Mercer', 'Civic Steward', 105, 366, false, 'Natural Aging', 'She made public infrastructure a shared inheritance.', 460000, 4, 8, 340),
  ('TEST-HLR-012', 'TEST-HSE-002', 'TEST-H-012', null, 1, 'Bastien Okoro', 'Research Pioneer', 34, 298, false, 'Quiet Orbital Passage', 'He connected the first open research exchanges across the southern arc.', 350000, 2, 14, 295),
  ('TEST-HLR-014', 'TEST-HSE-002', 'TEST-H-014', 'TEST-H-012', 2, 'Darius Okoro', 'Trade Navigator', 126, 351, false, 'Frontier Transit Incident', 'He carried House Okoro into the age of intercity trade.', 290000, 3, 6, 260)
on conflict (id) do nothing;

insert into house_perks (id, house_id, perk_key, perk_name, perk_category, tier, unlocked_game_day)
values
  ('TEST-PRK-001', 'TEST-HSE-001', 'civic_foundation', 'Civic Foundation', 'governance', 2, 210),
  ('TEST-PRK-002', 'TEST-HSE-002', 'research_patronage', 'Research Patronage', 'technology', 2, 205)
on conflict (house_id, perk_key) do nothing;

insert into house_heirlooms (id, house_id, name, heirloom_type, quality_tier, stat_buff, equipped_by_human_id, inscription)
values
  ('TEST-HLM-001', 'TEST-HSE-001', 'Mercer Civic Seal', 'founder_seal', 'Legendary', '+8% civic project completion', null, 'Carried by the first architect of Aurora Basin.'),
  ('TEST-HLM-002', 'TEST-HSE-002', 'Okoro Research Cipher', 'quantum_cipher', 'Epic', '+10% research progress', null, 'A promise that knowledge remains open to the next generation.')
on conflict (id) do nothing;
