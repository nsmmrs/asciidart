// The highlight.js counterpart of benchmark/throughput.dart.
// Usage: node benchmark/throughput.mjs FILE   (from tool/generate's modules)
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const require = createRequire(join(process.cwd(), 'tool/generate/package.json'));
const hljs = require('highlight.js');
const blocks = readFileSync(process.argv[2], 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
const pass = () => {
  const t = performance.now();
  for (const b of blocks) hljs.highlight(b.code, { language: b.language, ignoreIllegals: true });
  return Math.round(performance.now() - t);
};
const cold = pass();
const warm = Array.from({ length: 5 }, pass).sort((a, b) => a - b);
console.log(`highlight.js: ${blocks.length} blocks: first pass ${cold} ms, warm ${warm[0]} ms`);
