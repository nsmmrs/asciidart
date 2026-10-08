// Reads a JSON array of {tex, display} on standard input and writes, as a
// JSON array, the MathML of the engine named by the argument (temml or
// katex) for each, or {error} where it throws. Both trust the commands
// that need it (\id, \class, \style...).
import katex from 'katex';
import temml from 'temml';

const engines = {
  temml: (tex, display) =>
    temml.renderToString(tex, { displayMode: display, throwOnError: true, trust: true }),
  // KaTeX wraps its MathML in a span; its strict mode only warns.
  katex: (tex, display) =>
    katex
      .renderToString(tex, { displayMode: display, throwOnError: true, trust: true, strict: false, output: 'mathml' })
      .replace(/^<span class="katex">/, '')
      .replace(/<\/span>$/, ''),
};
const render = engines[process.argv[2]];
if (!render) throw new Error(`usage: node render.mjs temml|katex`);

let input = '';
for await (const chunk of process.stdin) input += chunk;
const out = JSON.parse(input).map(({ tex, display }) => {
  try {
    return { mathml: render(tex, display) };
  } catch (e) {
    return { error: String(e.message ?? e) };
  }
});
process.stdout.write(JSON.stringify(out));
