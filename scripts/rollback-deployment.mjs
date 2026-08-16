import { execSync } from 'node:child_process';

export function executeRollback(targetDeploymentId = null) {
  const result = {
    action: 'ROLLBACK',
    timestamp: new Date().toISOString(),
    status: 'pending',
    targetDeploymentId,
    message: '',
  };

  if (!targetDeploymentId) {
    result.status = 'SKIPPED';
    result.message = 'No deployment ID provided. To rollback in Cloudflare Worker: npx wrangler rollback <DEPLOYMENT_ID>';
    return result;
  }

  try {
    const out = execSync(`npx wrangler rollback ${targetDeploymentId}`, { encoding: 'utf8' });
    result.status = 'ROLLED_BACK';
    result.message = out;
  } catch (err) {
    result.status = 'FAILED';
    result.message = err.message;
  }

  return result;
}

if (process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/.*[/\\]/, ''))) {
  const depId = process.argv[2];
  const res = executeRollback(depId);
  console.log(JSON.stringify(res, null, 2));
}
