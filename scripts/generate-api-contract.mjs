import fs from 'node:fs/promises';
import path from 'node:path';
import { API_ROUTES, API_AUTH_CLASSES, API_ROUTE_OWNERS } from '../cloudflare/src/api-registry.ts';

const output = path.resolve('generated/api-contract.json');
const contract = {
  version: 1,
  owners: API_ROUTE_OWNERS,
  authClasses: API_AUTH_CLASSES,
  routes: API_ROUTES,
};

await fs.mkdir(path.dirname(output), { recursive: true });
await fs.writeFile(output, `${JSON.stringify(contract, null, 2)}\n`);
console.log(`Generated ${path.relative(process.cwd(), output)} (${API_ROUTES.length} routes)`);
