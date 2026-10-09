// Documents in units (ADR-0019) on Node: the units engine reads the
// document's scheme files through Node's file system, and the output is
// the same as for the oracle's rendering of the document.

import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'

import { Ptome, SafeMode } from 'ptome'

const fixtures = join(import.meta.dirname, '..', 'units', 'fixtures')

test('a document in units converts as its rendering does', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'ptome-units-'))
  try {
    const ad = new Ptome({ safe: SafeMode.unsafe })
    const attributes = { reproducible: '' }
    for (const doc of ['bible/sample', 'law/eu-sample']) {
      const name = doc.replace('/', '-')
      await ad.convertFile(join(fixtures, `${doc}.adoc`), {
        toFile: join(dir, `${name}.html`),
        attributes,
      })
      await ad.convertFile(join(fixtures, `${doc}.lowered.adoc`), {
        toFile: join(dir, `${name}.lowered.html`),
        attributes,
      })
      const native = readFileSync(join(dir, `${name}.html`), 'utf8')
      assert.equal(native, readFileSync(join(dir, `${name}.lowered.html`), 'utf8'))
    }
    const html = readFileSync(join(dir, 'bible-sample.html'), 'utf8')
    assert.match(html, /id="v-exo-34-6"/)
    assert.match(html, /<span class="nd">Lord<\/span>/)
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})
