import { spawnSync } from 'node:child_process';

const result = spawnSync('npm', ['audit', '--omit=dev', '--json'], {
  encoding: 'utf8',
  env: process.env,
  maxBuffer: 16 * 1024 * 1024,
});

if (result.error) throw new Error(`Dependency audit could not run: ${result.error.message}`);
let report;
try {
  report = JSON.parse(result.stdout || '{}');
} catch {
  throw new Error(`Dependency audit returned invalid JSON: ${result.stderr || result.stdout}`);
}

const exceptions = new Set(
  String(process.env.SECURITY_AUDIT_EXCEPTION_IDS || '')
    .split(',')
    .map((id) => id.trim())
    .filter(Boolean),
);
const vulnerabilities = report.vulnerabilities || {};
const blocking = [];
for (const [name, advisory] of Object.entries(vulnerabilities)) {
  const severity = advisory.severity;
  const ids = (advisory.via || [])
    .filter((via) => typeof via === 'object')
    .map((via) => String(via.source || via.url || ''));
  const exempt = [name, ...ids].some((id) => exceptions.has(id));
  if (!exempt && ['high', 'critical'].includes(severity)) blocking.push({ name, severity, ids });
}

if (blocking.length) {
  throw new Error(`Blocking runtime dependency vulnerabilities:\n${blocking.map((item) => `- ${item.severity}: ${item.name}${item.ids.length ? ` (${item.ids.join(', ')})` : ''}`).join('\n')}`);
}
if (result.status !== 0 && !report.metadata) {
  throw new Error(`Dependency audit failed: ${result.stderr || 'unknown audit failure'}`);
}
console.log(JSON.stringify({ ok: true, scope: 'runtime', vulnerabilities: report.metadata?.vulnerabilities ?? {}, exceptions: [...exceptions] }));
