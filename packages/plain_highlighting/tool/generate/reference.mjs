// Records highlight.js's auto-detection results for hilite's tests:
// test/reference/detect.json maps each sample (upstream's detection samples
// and markup inputs) to the detected language, its relevance and the
// runner-up, as highlight.js 11.12.0 computes them.
//
// Usage: node tool/generate/reference.mjs   (from the repository root)
import { createRequire } from 'node:module';
import { mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const require = createRequire(import.meta.url);
const hljs = require('highlight.js');
const root = process.cwd();
const results = {};
for (const kind of ['detect', 'markup']) {
  const base = join(root, 'vendor/highlight.js/test', kind);
  for (const lang of readdirSync(base).sort()) {
    const dir = join(base, lang);
    if (!statSync(dir).isDirectory()) continue;
    for (const file of readdirSync(dir).sort()) {
      if (kind === 'markup' && (file.endsWith('.expect.txt') || !file.endsWith('.txt'))) continue;
      const code = readFileSync(join(dir, file), 'utf8');
      const r = hljs.highlightAuto(code);
      results[`${kind}/${lang}/${file}`] = {
        language: r.language ?? null,
        relevance: r.relevance,
        secondBest: r.secondBest ? r.secondBest.language ?? null : null,
      };
    }
  }
}
mkdirSync(join(root, 'test/reference'), { recursive: true });
writeFileSync(join(root, 'test/reference/detect.json'), JSON.stringify(results, null, 1) + '\n');
console.log(`recorded ${Object.keys(results).length} detections`);
