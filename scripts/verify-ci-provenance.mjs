const repository = process.env.GITHUB_REPOSITORY;
const sourceSha = process.env.SOURCE_SHA;
const token = process.env.GITHUB_TOKEN;
if (!repository || !sourceSha || !token) throw new Error('GITHUB_REPOSITORY, SOURCE_SHA, and GITHUB_TOKEN are required');

const response = await fetch(`https://api.github.com/repos/${repository}/actions/runs?head_sha=${encodeURIComponent(sourceSha)}&event=push&per_page=100`, {
  headers: { Accept: 'application/vnd.github+json', Authorization: `Bearer ${token}`, 'X-GitHub-Api-Version': '2022-11-28' },
});
if (!response.ok) throw new Error(`Unable to verify CI provenance: GitHub returned ${response.status}`);
const payload = await response.json();
const required = payload.workflow_runs?.find((run) => run.name === 'EARTH tests' && run.head_sha === sourceSha);
if (!required || required.conclusion !== 'success') throw new Error(`Required CI run for ${sourceSha} is not successful (found ${required?.conclusion ?? 'none'})`);
console.log(JSON.stringify({ ok: true, sourceSha, workflow: required.name, runId: required.id, conclusion: required.conclusion }));
