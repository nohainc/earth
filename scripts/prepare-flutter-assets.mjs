import { copyFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const root = resolve(new URL('..', import.meta.url).pathname);
const source = resolve(root, 'flutter_client/web/app.html');
const target = resolve(root, 'flutter_client/build/web/app.html');

mkdirSync(dirname(target), { recursive: true });
copyFileSync(source, target);
console.log(`Prepared ${target}`);
