// The npm package contains exactly the files it should.

import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { test } from 'node:test'

const packageDir = fileURLToPath(new URL('../../build/npm', import.meta.url))

test('npm pack lists the expected files', () => {
  const [report] = JSON.parse(
    execFileSync('npm', ['pack', '--dry-run', '--json', packageDir], { encoding: 'utf8' })
  )
  const files = report.files.map((file) => file.path).sort()
  // The parts of the core that load on demand (the PDF and EPUB backends),
  // as dart2js numbers them.
  const parts = files.filter((file) => /^parts\/part-\d+\.js$/.test(file))
  assert.ok(parts.length >= 2, `parts: ${parts}`)
  assert.deepEqual(files.filter((file) => !parts.includes(file)), [
    'LICENSE',
    'README.md',
    'bin/ptome.js',
    'browser.js',
    'node.cjs',
    'node.js',
    'package.json',
    'ptome.js',
    'src/api.g.js',
    'src/core.js',
    'src/index.js',
    'src/page_fonts.js',
    'types/index.d.cts',
    'types/index.d.ts',
  ])
  // The bundle stays under 1.8 MB: 1.57 MB on 2026-10-08 (688 KB
  // gzipped), of which the 193 highlight.js languages are 322 KB of data
  // (plain_highlighting's grammars, Brotli-compressed; they were 1.5 MB of
  // code, the bundle 2.74 MB) and ptome (math, formats) the rest. The
  // units engine (ADR-0019: schemes, templates, the engine, citations)
  // added 125 KB the same day (1.72 MB). Units rendered natively
  // (ADR-0020) are 1.75 MB on 2026-10-09 while milestone 1's lowering is
  // still there beside them; removing it (phase 8) takes the margin back.
  const bundle = report.files.find((file) => file.path === 'ptome.js')
  assert.ok(bundle.size < 1_800_000, `bundle is ${bundle.size} bytes`)
  // The parts under 2.4 MB together: 2.24 MB on 2026-10-08 (the PDF
  // backend with plain_pdf, hyphenation and themes; the EPUB backend).
  const partsSize = report.files
    .filter((file) => parts.includes(file.path))
    .reduce((sum, file) => sum + file.size, 0)
  assert.ok(partsSize < 2_400_000, `parts are ${partsSize} bytes`)
})
