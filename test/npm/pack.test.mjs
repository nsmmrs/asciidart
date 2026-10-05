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
    'src/api.js',
    'src/bridge.js',
    'src/constants.js',
    'src/converters.js',
    'src/extensions.js',
    'src/index.js',
    'src/logging.js',
    'src/nodes.js',
    'types/index.d.cts',
    'types/index.d.ts',
    'types/logging.d.cts',
    'types/logging.d.ts',
  ])
  // The bundle stays well under a megabyte.
  const bundle = report.files.find((file) => file.path === 'asciidart.js')
  assert.ok(bundle.size < 1_000_000, `bundle is ${bundle.size} bytes`)
})
