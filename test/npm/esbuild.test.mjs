// The package bundles for browsers without Node.js built-ins.
import assert from 'node:assert/strict'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { build } from 'esbuild'

test('esbuild bundles the package for the browser', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'asciidart-esbuild-'))
  try {
    const entry = join(dir, 'consumer.js')
    writeFileSync(
      entry,
      "import { asciidoc } from 'asciidart'\nconsole.log(asciidoc.convert('*hi*'))\n"
    )
    const result = await build({
      entryPoints: [entry],
      bundle: true,
      platform: 'browser',
      format: 'esm',
      write: false,
      logLevel: 'silent',
      nodePaths: [join(import.meta.dirname, 'node_modules')],
    })
    assert.deepEqual(result.errors, [])
    const output = result.outputFiles[0].text
    assert.doesNotMatch(output, /from ["']node:/)
    assert.doesNotMatch(output, /require\(["']node:/)
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})
