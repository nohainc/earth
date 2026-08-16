export async function verifyCanary(targetUrl = 'http://127.0.0.1:8787') {
  const results = {
    target: targetUrl,
    timestamp: new Date().toISOString(),
    probes: {},
    allPassed: false,
  };

  try {
    // 1. Health Probe
    const healthRes = await fetch(`${targetUrl}/api/health`);
    results.probes.health = healthRes.ok && (await healthRes.json()).ok === true;
  } catch (err) {
    results.probes.health = false;
  }

  try {
    // 2. Readiness Probe
    const readyRes = await fetch(`${targetUrl}/api/ready`);
    results.probes.readiness = readyRes.ok && (await readyRes.json()).ok === true;
  } catch (err) {
    results.probes.readiness = false;
  }

  try {
    // 3. Landing & Flutter Shell Probe
    const shellRes = await fetch(`${targetUrl}/app`);
    const shellHtml = await shellRes.text();
    results.probes.flutterShell = shellRes.ok && shellHtml.includes('flutter_bootstrap.js');
  } catch (err) {
    results.probes.flutterShell = false;
  }

  try {
    // 4. World State Snapshot Probe
    const worldRes = await fetch(`${targetUrl}/api/world`);
    results.probes.worldSnapshot = worldRes.ok && (await worldRes.json()).clock !== undefined;
  } catch (err) {
    results.probes.worldSnapshot = false;
  }

  results.allPassed = Object.values(results.probes).every(Boolean);
  return results;
}

if (process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/.*[/\\]/, ''))) {
  const url = process.argv[2] || process.env.CANARY_TARGET_URL || 'http://127.0.0.1:8787';
  verifyCanary(url).then((res) => {
    console.log(JSON.stringify(res, null, 2));
    if (!res.allPassed) process.exit(1);
  });
}
