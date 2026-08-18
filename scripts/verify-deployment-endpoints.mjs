/**
 * Automated Deployment Verification Probes for EARTH: United Corporations
 * Verifies all 7 critical production endpoints:
 *  - /
 *  - /landing
 *  - /app
 *  - /app/main.dart.js
 *  - /api/health
 *  - /api/auth/me
 *  - /edge/events
 */

export async function verifyDeploymentEndpoints(targetUrl = 'http://127.0.0.1:8787', options = {}) {
  const normalizedTarget = targetUrl.replace(/\/+$/, '');
  const timeoutMs = options.timeoutMs || 8000;

  const report = {
    target: normalizedTarget,
    timestamp: new Date().toISOString(),
    probes: {
      root: false,
      landing: false,
      app: false,
      appMainDartJs: false,
      apiHealth: false,
      apiAuthMe: false,
      edgeEvents: false,
    },
    details: {},
    allPassed: false,
    errors: [],
  };

  const fetchWithTimeout = async (url, fetchOptions = {}) => {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch(url, {
        ...fetchOptions,
        signal: controller.signal,
      });
      return response;
    } finally {
      clearTimeout(timeout);
    }
  };

  // 1. Probe Root (/)
  try {
    const res = await fetchWithTimeout(`${normalizedTarget}/`);
    const cType = res.headers.get('content-type') || '';
    const body = await res.text();
    const ok = res.status === 200 && cType.includes('text/html') && body.length > 50;
    report.probes.root = ok;
    report.details.root = {
      status: res.status,
      contentType: cType,
      bytes: body.length,
      ok,
    };
    if (!ok) report.errors.push(`Root probe (/) failed: status=${res.status}, type=${cType}`);
  } catch (err) {
    report.probes.root = false;
    report.details.root = { error: err.message, ok: false };
    report.errors.push(`Root probe (/) error: ${err.message}`);
  }

  // 2. Probe Landing (/landing)
  try {
    const res = await fetchWithTimeout(`${normalizedTarget}/landing`);
    const cType = res.headers.get('content-type') || '';
    const body = await res.text();
    const ok = res.status === 200 && cType.includes('text/html') && body.length > 50;
    report.probes.landing = ok;
    report.details.landing = {
      status: res.status,
      contentType: cType,
      bytes: body.length,
      ok,
    };
    if (!ok) report.errors.push(`Landing probe (/landing) failed: status=${res.status}, type=${cType}`);
  } catch (err) {
    report.probes.landing = false;
    report.details.landing = { error: err.message, ok: false };
    report.errors.push(`Landing probe (/landing) error: ${err.message}`);
  }

  // 3. Probe App Shell (/app)
  try {
    const res = await fetchWithTimeout(`${normalizedTarget}/app`);
    const cType = res.headers.get('content-type') || '';
    const body = await res.text();
    const ok = res.status === 200 && cType.includes('text/html') && (body.includes('flutter') || body.includes('app.html') || body.includes('<base href'));
    report.probes.app = ok;
    report.details.app = {
      status: res.status,
      contentType: cType,
      bytes: body.length,
      ok,
    };
    if (!ok) report.errors.push(`App shell probe (/app) failed: status=${res.status}, type=${cType}`);
  } catch (err) {
    report.probes.app = false;
    report.details.app = { error: err.message, ok: false };
    report.errors.push(`App shell probe (/app) error: ${err.message}`);
  }

  // 4. Probe App Main Dart JS (/app/main.dart.js)
  try {
    const res = await fetchWithTimeout(`${normalizedTarget}/app/main.dart.js`);
    const cType = res.headers.get('content-type') || '';
    const body = await res.text();
    const ok = res.status === 200 && (cType.includes('javascript') || cType.includes('octet-stream')) && body.length > 0;
    report.probes.appMainDartJs = ok;
    report.details.appMainDartJs = {
      status: res.status,
      contentType: cType,
      bytes: body.length,
      ok,
    };
    if (!ok) report.errors.push(`Flutter runtime JS probe (/app/main.dart.js) failed: status=${res.status}, type=${cType}`);
  } catch (err) {
    report.probes.appMainDartJs = false;
    report.details.appMainDartJs = { error: err.message, ok: false };
    report.errors.push(`Flutter runtime JS probe (/app/main.dart.js) error: ${err.message}`);
  }

  // 5. Probe API Health (/api/health)
  try {
    const res = await fetchWithTimeout(`${normalizedTarget}/api/health`);
    const cType = res.headers.get('content-type') || '';
    const json = await res.json();
    const ok = res.status === 200 && cType.includes('json') && json.ok === true;
    report.probes.apiHealth = ok;
    report.details.apiHealth = {
      status: res.status,
      contentType: cType,
      payload: json,
      ok,
    };
    if (!ok) report.errors.push(`API Health probe (/api/health) failed: status=${res.status}, ok=${json?.ok}`);
  } catch (err) {
    report.probes.apiHealth = false;
    report.details.apiHealth = { error: err.message, ok: false };
    report.errors.push(`API Health probe (/api/health) error: ${err.message}`);
  }

  // 6. Probe Auth Session (/api/auth/me)
  try {
    const res = await fetchWithTimeout(`${normalizedTarget}/api/auth/me`);
    const cType = res.headers.get('content-type') || '';
    const json = await res.json();
    // 200 or 401 are both acceptable auth responses for unauthenticated health probes
    const ok = (res.status === 200 || res.status === 401) && cType.includes('json') && json !== null && typeof json === 'object';
    report.probes.apiAuthMe = ok;
    report.details.apiAuthMe = {
      status: res.status,
      contentType: cType,
      payload: json,
      ok,
    };
    if (!ok) report.errors.push(`Auth Me probe (/api/auth/me) failed: status=${res.status}`);
  } catch (err) {
    report.probes.apiAuthMe = false;
    report.details.apiAuthMe = { error: err.message, ok: false };
    report.errors.push(`Auth Me probe (/api/auth/me) error: ${err.message}`);
  }

  // 7. Probe Edge Events Stream (/edge/events)
  try {
    const res = await fetchWithTimeout(`${normalizedTarget}/edge/events`, {
      headers: { Accept: 'text/event-stream' },
    });
    const cType = res.headers.get('content-type') || '';
    const ok = res.status === 200 && (cType.includes('text/event-stream') || cType.includes('application/json'));
    // Read the first chunk and cancel stream
    const reader = res.body?.getReader();
    if (reader) {
      await reader.read();
      reader.cancel();
    }
    report.probes.edgeEvents = ok;
    report.details.edgeEvents = {
      status: res.status,
      contentType: cType,
      ok,
    };
    if (!ok) report.errors.push(`Edge events probe (/edge/events) failed: status=${res.status}, type=${cType}`);
  } catch (err) {
    report.probes.edgeEvents = false;
    report.details.edgeEvents = { error: err.message, ok: false };
    report.errors.push(`Edge events probe (/edge/events) error: ${err.message}`);
  }

  report.allPassed = Object.values(report.probes).every(Boolean);
  return report;
}

if (process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/.*[/\\]/, ''))) {
  const url = process.argv[2] || process.env.DEPLOYMENT_TARGET_URL || 'http://127.0.0.1:8787';
  verifyDeploymentEndpoints(url).then((report) => {
    console.log(JSON.stringify(report, null, 2));
    if (!report.allPassed) {
      process.exit(1);
    }
  });
}
