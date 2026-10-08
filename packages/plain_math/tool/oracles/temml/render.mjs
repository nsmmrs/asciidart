// Reads a JSON array of {tex, display} on standard input and writes, as a
// JSON array, Temml's MathML for each (or {error} where Temml throws),
// trusting the commands that need it (\id, \class, \style...).
import temml from 'temml';

let input = '';
for await (const chunk of process.stdin) input += chunk;
const out = JSON.parse(input).map(({ tex, display }) => {
  try {
    return { mathml: temml.renderToString(tex, { displayMode: display, throwOnError: true, trust: true }) };
  } catch (e) {
    return { error: String(e.message ?? e) };
  }
});
process.stdout.write(JSON.stringify(out));
