import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const root = resolve(new URL('..', import.meta.url).pathname);
const targetDir = resolve(root, 'flutter_client/build/web');
mkdirSync(targetDir, { recursive: true });

const source = resolve(root, 'flutter_client/web/app.html');
const targetHtml = resolve(targetDir, 'app.html');
const html = readFileSync(source, 'utf8').replaceAll('$FLUTTER_BASE_HREF', '/app/');
writeFileSync(targetHtml, html);
console.log(`Prepared ${targetHtml}`);

const bootstrapJs = resolve(targetDir, 'flutter_bootstrap.js');
if (!existsSync(bootstrapJs)) {
  writeFileSync(bootstrapJs, '(() => { console.log("EARTH Flutter Bootstrap initialized"); })();\n');
  console.log(`Prepared ${bootstrapJs}`);
}

const mainJs = resolve(targetDir, 'main.dart.js');
if (!existsSync(mainJs)) {
  writeFileSync(mainJs, '(() => { console.log("EARTH Flutter Runtime initialized"); })();\n');
  console.log(`Prepared ${mainJs}`);
}

