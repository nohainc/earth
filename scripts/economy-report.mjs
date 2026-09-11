import { Client } from 'pg';

// Development-only balance report. It reads projections and catalogs; it never
// mutates the game database or substitutes live market prices for reference values.
const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  throw new Error('DATABASE_URL is required; refusing to report against an implicit database');
}

const jsonOutput = process.argv.includes('--json');
const client = new Client({
  connectionString,
  application_name: 'earth-economy-balance-report',
  connectionTimeoutMillis: 5000,
  query_timeout: 30000,
});

const number = (value) => Number(value ?? 0);
const money = (value) => number(value).toLocaleString('en-US', { maximumFractionDigits: 2 });
const compact = (value) => number(value).toLocaleString('en-US', { maximumFractionDigits: 4 });
const table = (columns, rows) => {
  if (!rows.length) return '(none)';
  const values = rows.map((row) => columns.map(({ key, format }) => format ? format(row[key], row) : String(row[key] ?? '')));
  const widths = columns.map((column, index) => Math.max(column.label.length, ...values.map((row) => row[index].length)));
  const line = (row) => row.map((value, index) => value.padEnd(widths[index])).join('  ');
  return [line(columns.map((column) => column.label)), line(widths.map((width) => '-'.repeat(width))), ...values.map(line)].join('\n');
};

const warnings = [];
const errors = [];
const report = { buildings: [], technologies: [], taxScenarios: [], warnings, errors };

await client.connect();
try {
  const buildingResult = await client.query(`
    SELECT building_type, tier, name, construction_reference_value,
      daily_credit_operating_cost, total_daily_cost, expected_daily_revenue,
      operating_margin, payback_game_days, payback_real_hours,
      output_materials, output_components, output_energy, output_compute, output_food
    FROM building_economic_balance_model
    ORDER BY building_type, tier`);
  report.buildings = buildingResult.rows;

  const dominance = await client.query(`
    SELECT building_family, lower_tier, higher_tier
    FROM building_tier_balance_flags
    WHERE unintended_dominance
    ORDER BY building_family, lower_tier, higher_tier`);
  for (const row of dominance.rows) errors.push(`T${row.higher_tier} dominated by T${row.lower_tier} in ${row.building_family}.`);

  const cycles = await client.query(`
    SELECT start_asset, asset_path, value_multiplier
    FROM economic_recipe_cycles
    WHERE exceeds_reference_value
    ORDER BY value_multiplier DESC`);
  for (const row of cycles.rows) errors.push(`Reference-value production cycle detected from ${row.start_asset}: multiplier ${compact(row.value_multiplier)}.`);

  const coverage = await client.query(`SELECT asset, source_buildings, sink_buildings, has_source_and_sink_model FROM economic_resource_flow_coverage ORDER BY asset`);
  const coverageByAsset = new Map(coverage.rows.map((row) => [row.asset, row]));
  const outputFields = { MATERIAL: 'output_materials', COMPONENTS: 'output_components', ENERGY: 'output_energy', COMPUTE: 'output_compute', FOOD: 'output_food' };
  for (const building of report.buildings) {
    for (const [asset, field] of Object.entries(outputFields)) {
      if (number(building[field]) > 0 && number(coverageByAsset.get(asset)?.sink_buildings) === 0) {
        warnings.push(`${building.name} T${building.tier} outputs ${asset} with no modeled consumer.`);
      }
    }
    if (building.payback_game_days !== null && number(building.payback_game_days) < 2) {
      warnings.push(`${building.name} T${building.tier} pays back in under 2 game days.`);
    }
  }
  for (const row of coverage.rows) {
    if (row.asset !== 'CREDIT' && (number(row.source_buildings) === 0 || number(row.sink_buildings) === 0)) {
      warnings.push(`${row.asset} lacks a sufficient modeled ${number(row.source_buildings) === 0 ? 'source' : 'sink'}.`);
    }
  }

  const technologyResult = await client.query(`
    SELECT code, name, research_credit_cost_units, research_points_required,
      expected_research_completion_days, expected_real_completion_hours,
      expected_daily_impact_value, economic_payback_game_days,
      economic_payback_real_hours, balance_assessment
    FROM technology_economic_balance_model
    ORDER BY code`);
  report.technologies = technologyResult.rows;
  for (const row of report.technologies) {
    if (row.economic_payback_game_days !== null && number(row.economic_payback_game_days) < 1) {
      warnings.push(`${row.name} technology pays back in under 1 game day.`);
    }
  }

  const taxRules = await client.query(`
    SELECT scope, category, minimum_rate_bps, maximum_rate_bps
    FROM tax_governance_rules
    WHERE category IN ('personal_income', 'corporate_income')
    ORDER BY scope, category`);
  for (const rule of taxRules.rows) {
    for (const income of [1000, 5000, 20000]) {
      for (const rate of [0, 5, 10, 20]) {
        const rateBps = rate * 100;
        report.taxScenarios.push({
          scope: rule.scope,
          category: rule.category,
          income,
          rate,
          effectiveCashflow: income - (income * rateBps / 10000),
          withinCap: rateBps >= number(rule.minimum_rate_bps) && rateBps <= number(rule.maximum_rate_bps),
        });
      }
    }
  }

  if (jsonOutput) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    console.log('BUILDING BALANCE\n');
    console.log(table([
      { label: 'Building', key: 'name' }, { label: 'Tier', key: 'tier' },
      { label: 'CapEx', key: 'construction_reference_value', format: money },
      { label: 'Daily cost', key: 'total_daily_cost', format: money },
      { label: 'Daily revenue', key: 'expected_daily_revenue', format: money },
      { label: 'Margin', key: 'operating_margin', format: money },
      { label: 'Payback days', key: 'payback_game_days', format: compact },
    ], report.buildings));
    console.log('\nTECHNOLOGY BALANCE\n');
    console.log(table([
      { label: 'Technology', key: 'name' }, { label: 'Cost', key: 'research_credit_cost_units', format: money },
      { label: 'RP', key: 'research_points_required', format: compact },
      { label: 'Days', key: 'expected_research_completion_days', format: compact },
      { label: 'Benefit/day', key: 'expected_daily_impact_value', format: money },
      { label: 'Payback days', key: 'economic_payback_game_days', format: compact },
    ], report.technologies));
    console.log('\nTAX SCENARIOS (daily income units)\n');
    console.log(table([
      { label: 'Scope', key: 'scope' }, { label: 'Category', key: 'category' },
      { label: 'Income', key: 'income', format: money }, { label: 'Rate %', key: 'rate' },
      { label: 'Cashflow', key: 'effectiveCashflow', format: money }, { label: 'Within cap', key: 'withinCap' },
    ], report.taxScenarios));
    console.log(`\nWARNINGS (${warnings.length})`);
    warnings.forEach((warning) => console.log(`WARNING: ${warning}`));
    console.log(`\nERRORS (${errors.length})`);
    errors.forEach((error) => console.log(`ERROR: ${error}`));
  }
  if (errors.length && process.env.ECONOMY_REPORT_ALLOW_ERRORS !== 'true') process.exitCode = 2;
} finally {
  await client.end();
}
