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
  assert.deepEqual(files, [
    'LICENSE',
    'README.md',
    'asciidart.js',
    'bin/asciidart.js',
    'browser.js',
    'node.cjs',
    'node.js',
    'package.json',
    'src/api.g.js',
    'src/core.js',
    'src/index.js',
    'types/index.d.cts',
    'types/index.d.ts',
  ])
  // The bundle stays under 2.75 MB: 2.64 MB on 2026-10-07, of which the
  // 193 highlight.js languages hilite compiles in are 1.5 MB and asciidart
  // (math, formats) the rest. See the board card on the bundle size.
  const bundle = report.files.find((file) => file.path === 'asciidart.js')
  assert.ok(bundle.size < 2_750_000, `bundle is ${bundle.size} bytes`)
})
