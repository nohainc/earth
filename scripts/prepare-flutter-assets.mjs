import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(new URL('..', import.meta.url).pathname);
const targetDir = resolve(root, 'flutter_client/build/web');
mkdirSync(targetDir, { recursive: true });

const buildIndexHtml = resolve(targetDir, 'index.html');
const targetHtml = resolve(targetDir, 'app.html');

if (existsSync(buildIndexHtml)) {
  let html = readFileSync(buildIndexHtml, 'utf8');
  if (html.includes('$FLUTTER_BASE_HREF')) {
    html = html.replaceAll('$FLUTTER_BASE_HREF', '/app/');
  }
  writeFileSync(targetHtml, html);
  console.log(`Prepared ${targetHtml} from build/web/index.html`);
} else {
  const source = resolve(root, 'flutter_client/web/app.html');
  if (existsSync(source)) {
    const html = readFileSync(source, 'utf8').replaceAll('$FLUTTER_BASE_HREF', '/app/');
    writeFileSync(targetHtml, html);
    console.log(`Prepared ${targetHtml} from web/app.html`);
  }
}

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
