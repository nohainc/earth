import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const root = resolve(new URL('..', import.meta.url).pathname);
const source = resolve(root, 'flutter_client/web/app.html');
const target = resolve(root, 'flutter_client/build/web/app.html');

mkdirSync(dirname(target), { recursive: true });
const html = readFileSync(source, 'utf8').replaceAll('$FLUTTER_BASE_HREF', '/app/');
writeFileSync(target, html);
console.log(`Prepared ${target}`);
