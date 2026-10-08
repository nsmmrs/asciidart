// Writes highlight.js's output for real code to a JSON Lines file, for
// tool/differential.dart to compare hilite against.
//
// Code comes from the source blocks of AsciiDoc files below DIR
// (`[source,lang]` + `----`); each line of OUT holds the language, the
// code and highlight.js's HTML, relevance and illegal flag, plus an
// auto-detection result for every tenth block.
//
// Usage: node tool/generate/differential.mjs DIR OUT
import { createRequire } from 'node:module';
import { readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const require = createRequire(import.meta.url);
const hljs = require('highlight.js');
const [dir, out] = process.argv.slice(2);
const files = [];
(function walk(d) {
  for (const name of readdirSync(d)) {
    const p = join(d, name);
    const st = statSync(p);
    if (st.isDirectory()) walk(p);
    else if (/\.(adoc|asciidoc)$/.test(name)) files.push(p);
  }
})(dir);
files.sort();
const lines = [];
let n = 0;
for (const file of files) {
  const text = readFileSync(file, 'utf8').split('\n');
  for (let i = 0; i < text.length - 1; i++) {
    const m = /^\[source,\s*([A-Za-z0-9_+#.-]+)/.exec(text[i]);
    if (!m || !/^-{4,}\s*$/.test(text[i + 1])) continue;
    const fence = text[i + 1].trim();
    const end = text.indexOf(fence, i + 2);
    if (end < 0) continue;
    const code = text.slice(i + 2, end).join('\n');
    const language = m[1].toLowerCase();
    if (!hljs.getLanguage(language)) continue;
    const r = hljs.highlight(code, { language, ignoreIllegals: true });
    const entry = { language, code, html: r.value, relevance: r.relevance, illegal: r.illegal };
    if (n % 10 === 0) {
      const a = hljs.highlightAuto(code);
      entry.auto = { language: a.language ?? null, relevance: a.relevance, html: a.value };
    }
    lines.push(JSON.stringify(entry));
    n++;
  }
}
writeFileSync(out, lines.join('\n') + '\n');
console.log(`${n} source blocks from ${files.length} files`);
