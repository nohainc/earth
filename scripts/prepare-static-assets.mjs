import { cpSync, mkdirSync, rmSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(new URL('..', import.meta.url).pathname);
const source = resolve(root, 'flutter_client/web');
const target = resolve(root, 'static-site');

rmSync(target, { recursive: true, force: true });
mkdirSync(target, { recursive: true });
cpSync(resolve(source, 'landing.html'), resolve(target, 'landing.html'));
cpSync(resolve(source, 'landing.css'), resolve(target, 'landing.css'));
console.log(`Prepared ${target}`);
