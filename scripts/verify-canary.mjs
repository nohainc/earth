import { verifyDeploymentEndpoints } from './verify-deployment-endpoints.mjs';

export async function verifyCanary(targetUrl = 'http://127.0.0.1:8787') {
  const deploymentReport = await verifyDeploymentEndpoints(targetUrl);

  const results = {
    target: deploymentReport.target,
    timestamp: deploymentReport.timestamp,
    probes: {
      ...deploymentReport.probes,
      // Backwards-compatible probe alias keys
      health: deploymentReport.probes.apiHealth,
      flutterShell: deploymentReport.probes.app,
    },
    details: deploymentReport.details,
    errors: deploymentReport.errors,
    allPassed: deploymentReport.allPassed,
  };

  try {
    // Additional World State Snapshot Probe
    const worldRes = await fetch(`${deploymentReport.target}/api/world`);
    results.probes.worldSnapshot = worldRes.ok && (await worldRes.json()).clock !== undefined;
  } catch (err) {
    results.probes.worldSnapshot = false;
  }

  try {
    // Additional Readiness Probe
    const readyRes = await fetch(`${deploymentReport.target}/api/ready`);
    results.probes.readiness = readyRes.ok && (await readyRes.json()).ok === true;
  } catch (err) {
    results.probes.readiness = false;
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
