import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * Strips single-line and multi-line comments from JSONC text.
 */
export function stripJsonComments(jsonc) {
  return jsonc
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^\\:])\/\/.*$/gm, '$1');
}

/**
 * Parses JSON or JSONC file safely.
 */
export function parseConfigFile(filePath) {
  const content = readFileSync(filePath, 'utf8');
  try {
    return JSON.parse(stripJsonComments(content));
  } catch (err) {
    throw new Error(`Failed to parse config at ${filePath}: ${err.message}`);
  }
}

/**
 * Normalizes route definition to object format.
 */
export function normalizeRoute(route, workerName, configPath) {
  if (typeof route === 'string') {
    return {
      pattern: route,
      zone_name: route.split('/')[0],
      custom_domain: false,
      workerName,
      configPath,
    };
  }
  return {
    pattern: route.pattern || '',
    zone_name: route.zone_name || (route.pattern ? route.pattern.split('/')[0] : ''),
    custom_domain: Boolean(route.custom_domain),
    workerName,
    configPath,
  };
}

/**
 * Validates route and custom-domain configurations across all Wrangler files.
 */
export function verifyDeploymentConfig(options = {}) {
  const rootDir = options.rootDir || process.cwd();
  const configPaths = options.configPaths || [
    resolve(rootDir, 'wrangler.api.jsonc'),
    resolve(rootDir, 'wrangler.app.jsonc'),
    resolve(rootDir, 'wrangler.static.jsonc'),
  ];

  const report = {
    timestamp: new Date().toISOString(),
    status: 'VALID',
    workers: [],
    routes: [],
    customDomains: [],
    conflicts: [],
    errors: [],
    coverage: {
      rootAndLanding: false,
      appShellAndAssets: false,
      apiSurface: false,
      edgeEvents: false,
      healthChecks: false,
    },
  };

  const parsedConfigs = [];

  for (const configPath of configPaths) {
    if (!existsSync(configPath)) {
      report.errors.push(`Config file not found: ${configPath}`);
      continue;
    }

    try {
      const config = parseConfigFile(configPath);
      const workerName = config.name || 'unnamed-worker';
      parsedConfigs.push({ configPath, workerName, config });
      report.workers.push({
        name: workerName,
        configPath,
        main: config.main,
        assets: config.assets ? config.assets.directory : undefined,
      });

      // Extract custom domains from routes or custom_domains setting
      if (Array.isArray(config.custom_domains)) {
        for (const cd of config.custom_domains) {
          const domain = typeof cd === 'string' ? cd : cd.name;
          report.customDomains.push({ domain, workerName, configPath });
        }
      }

      const routes = Array.isArray(config.routes) ? config.routes : [];
      for (const route of routes) {
        const normalized = normalizeRoute(route, workerName, configPath);
        if (normalized.custom_domain) {
          report.customDomains.push({
            domain: normalized.pattern,
            zone_name: normalized.zone_name,
            workerName,
            configPath,
          });
        }
        report.routes.push(normalized);
      }
    } catch (err) {
      report.errors.push(err.message);
    }
  }

  // 1. Detect Duplicate Route Patterns Across Different Workers
  const routePatternsByWorker = new Map();
  for (const r of report.routes) {
    if (!r.pattern) {
      report.conflicts.push({
        type: 'MALFORMED_ROUTE',
        message: `Route in ${r.workerName} (${r.configPath}) is missing pattern.`,
      });
      continue;
    }
    if (!routePatternsByWorker.has(r.pattern)) {
      routePatternsByWorker.set(r.pattern, []);
    }
    routePatternsByWorker.get(r.pattern).push(r);
  }

  for (const [pattern, entries] of routePatternsByWorker.entries()) {
    const distinctWorkers = [...new Set(entries.map((e) => e.workerName))];
    if (distinctWorkers.length > 1) {
      report.conflicts.push({
        type: 'DUPLICATE_ROUTE_PATTERN',
        pattern,
        workers: distinctWorkers,
        message: `Route pattern "${pattern}" is claimed by multiple workers: ${distinctWorkers.join(', ')}. This creates unpredictable routing precedence in Cloudflare.`,
      });
    }
  }

  // 2. Detect Custom Domain vs Route Shadowing Conflicts
  for (const cd of report.customDomains) {
    const domainHost = cd.domain.replace(/^https?:\/\//, '').split('/')[0];
    const conflictingRoutes = report.routes.filter(
      (r) => r.workerName !== cd.workerName && r.pattern.startsWith(`${domainHost}/`)
    );
    if (conflictingRoutes.length > 0) {
      const shadowedWorkers = [...new Set(conflictingRoutes.map((r) => r.workerName))];
      report.conflicts.push({
        type: 'CUSTOM_DOMAIN_ROUTE_SHADOWING',
        domain: cd.domain,
        customDomainWorker: cd.workerName,
        shadowedWorkers,
        shadowedPatterns: conflictingRoutes.map((r) => r.pattern),
        message: `Custom domain "${cd.domain}" on worker "${cd.customDomainWorker}" may intercept traffic before sub-routes on workers: ${shadowedWorkers.join(', ')}.`,
      });
    }
  }

  // 3. Detect Zone Name Inconsistencies
  const allZones = [...new Set(report.routes.map((r) => r.zone_name).filter(Boolean))];
  if (allZones.length > 1) {
    // If multiple zones exist, check if intentional or misconfigured
    const hasMismatchedApex = allZones.some((z) => !z.includes('earthuc.com') && !z.includes('localhost'));
    if (hasMismatchedApex) {
      report.conflicts.push({
        type: 'ZONE_MISMATCH',
        zones: allZones,
        message: `Detected divergent zone names across workers: ${allZones.join(', ')}. Ensure all production services share the authoritative zone.`,
      });
    }
  }

  // 4. Verify Coverage of Required Production Endpoints
  const allPatterns = report.routes.map((r) => r.pattern);

  // Check / and /landing (typically earthuc.com/* or earthuc.com/ or earthuc.com/landing)
  report.coverage.rootAndLanding = allPatterns.some(
    (p) => p.includes('/*') || p.endsWith('/') || p.includes('/landing')
  );

  // Check /app and /app/*
  report.coverage.appShellAndAssets = allPatterns.some(
    (p) => p.includes('/app') || p.includes('/app/*')
  );

  // Check /api/*
  report.coverage.apiSurface = allPatterns.some((p) => p.includes('/api/*'));

  // Check /edge/* (events stream)
  report.coverage.edgeEvents = allPatterns.some(
    (p) => p.includes('/edge/*') || p.includes('/edge/events') || p.includes('/api/*')
  );

  // Check health checks (/health, /ready, /api/health)
  report.coverage.healthChecks = allPatterns.some(
    (p) => p.includes('/health') || p.includes('/ready') || p.includes('/api/*')
  );

  // Check if any required coverage is missing
  const missingCoverage = Object.entries(report.coverage)
    .filter(([_, covered]) => !covered)
    .map(([key]) => key);

  if (missingCoverage.length > 0) {
    report.conflicts.push({
      type: 'INCOMPLETE_PRODUCTION_COVERAGE',
      missingSurfaces: missingCoverage,
      message: `Production routing is missing explicit coverage for: ${missingCoverage.join(', ')}.`,
    });
  }

  // 5. Final Status Calculation
  if (report.errors.length > 0) {
    report.status = 'INVALID_CONFIG';
  } else if (report.conflicts.length > 0) {
    report.status = 'CONFLICT_DETECTED';
  } else {
    report.status = 'VALID';
  }

  return report;
}

if (process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/.*[/\\]/, ''))) {
  const report = verifyDeploymentConfig();
  console.log(JSON.stringify(report, null, 2));
  if (report.status !== 'VALID') {
    process.exit(1);
  }
}
