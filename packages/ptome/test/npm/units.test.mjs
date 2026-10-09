// Documents in units (ADR-0020) on Node: the units engine reads the
// document's scheme files through Node's file system, and the output
// renders the units as it does in Dart.

import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'

import { Ptome, SafeMode } from 'ptome'

const fixtures = join(import.meta.dirname, '..', 'units', 'fixtures')

test('a document in units renders its units', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'ptome-units-'))
  try {
    const ad = new Ptome({ safe: SafeMode.unsafe })
    await ad.convertFile(join(fixtures, 'bible', 'sample.adoc'), {
      toFile: join(dir, 'sample.html'),
      attributes: { reproducible: '' },
    })
    const html = readFileSync(join(dir, 'sample.html'), 'utf8')
    assert.match(
      html,
      /<span id="v-exo-34-6" class="unit" data-scheme="bible" data-level="verse" data-unit="Exod 34:6"><sup>6<\/sup><\/span>/,
    )
    assert.match(html, /<span class="nd">Lord<\/span>/)
    assert.match(html, /<span class="wj">Blessed <em>are<\/em>/)
    assert.doesNotMatch(html.slice(html.indexOf('<body')), /@ /)

    // The units through the API, as in Dart.
    const doc = await ad.parseFile(join(fixtures, 'bible', 'sample.adoc'))
    assert.equal(doc.units[0].level, 'book')
    const verse = doc.unit('Exodus 34:6')
    assert.equal(verse.id, 'v-exo-34-6')
    assert.equal(verse.citation, 'Exod 34:6')
    assert.deepEqual(verse.labels, { book: 'EXO', chapter: '34', verse: '6' })
    assert.equal(doc.unit('Rev 22:21'), null)
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})
