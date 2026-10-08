// In-process throughput of the npm package (build/npm) on Node.js: the
// corpus, options and method of benchmark/throughput.dart.
//
// Usage (from the repo root, after tool/build-npm.sh):
//   node benchmark/throughput.mjs [--copies 20] [--iterations 15] [--warmup 5]
//   node benchmark/throughput.mjs --ajs PATH/TO/@asciidoctor/core/src/index.js
//
// --ajs also times Asciidoctor.js (its `convert` with the same options) for
// comparison.
import { readFileSync } from 'node:fs'
import { performance } from 'node:perf_hooks'
import { parseArgs } from 'node:util'

const sources = [
  'vendor/asciidoctor/benchmark/sample-data/mdbasics.adoc',
  'vendor/asciidoctor/data/reference/syntax.adoc',
  'vendor/asciidoctor/test/fixtures/sample.adoc',
]

const { values } = parseArgs({
  options: {
    copies: { type: 'string', default: '20' },
    iterations: { type: 'string', default: '15' },
    warmup: { type: 'string', default: '5' },
    backend: { type: 'string', multiple: true, default: ['html5', 'docbook5', 'manpage'] },
    ajs: { type: 'string' },
  },
})

const base = sources.map((path) => readFileSync(path, 'utf8')).join('\n\n')
const corpus = Array(Number(values.copies)).fill(base).join('\n\n')
const iterations = Number(values.iterations)
const warmup = Number(values.warmup)

const median = (samples) => {
  const sorted = [...samples].sort((a, b) => a - b)
  return sorted[Math.floor(sorted.length / 2)]
}

async function time(label, convert, backend) {
  for (let i = 0; i < warmup; i++) await convert(corpus, backend)
  const samples = []
  for (let i = 0; i < iterations; i++) {
    const start = performance.now()
    await convert(corpus, backend)
    samples.push(performance.now() - start)
  }
  console.log(`${label} ${backend}: ${median(samples).toFixed(1)} ms`)
}

// ptome collects diagnostics on the document rather than printing them.
const ptome = await import('../build/npm/node.js')
const ad = new ptome.Ptome({ safe: ptome.SafeMode.safe })
const implementations = [
  ['ptome', (source, backend) => ad.convert(source, { backend, doctype: 'book', standalone: true })],
]
if (values.ajs) {
  // The corpus repeats ids; silence the warnings so that only conversion is
  // timed.
  const { pathToFileURL } = await import('node:url')
  const ajs = await import(pathToFileURL(values.ajs).href)
  ajs.LoggerManager.setLogger(new ajs.NullLogger())
  implementations.push([
    'asciidoctor.js',
    (source, backend) => ajs.convert(source, { safe: 'safe', backend, doctype: 'book', standalone: true }),
  ])
}

console.log(`corpus: ${corpus.length} chars, node ${process.version}`)
for (const backend of values.backend) {
  for (const [label, convert] of implementations) await time(label, convert, backend)
}
