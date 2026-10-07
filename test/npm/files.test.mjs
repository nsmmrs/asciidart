// PDFs and EPUBs from JavaScript: the backends load on demand (separate
// parts of the bundle), and fonts are given as bytes.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { test } from 'node:test'

import { Asciidart, FontFile, asciidoc } from 'asciidart'

const fonts = join(import.meta.dirname, '..', '..', 'vendor', 'asciidoctor-pdf', 'data', 'fonts')
const notoSerif = (style) =>
  new FontFile(`notoserif-${style}-subset.ttf`, readFileSync(join(fonts, `notoserif-${style}-subset.ttf`)))
const date = { localdatetime: '2020-01-01 00:00:00 +0000' }
const text = (bytes, length) => new TextDecoder('latin1').decode(bytes.slice(0, length))

test('a PDF, its backend loaded on demand, in the fonts given', async () => {
  const messages = []
  const ad = new Asciidart({
    fonts: ['regular', 'bold', 'italic', 'bold_italic'].map(notoSerif),
    onDiagnostic: (d) => messages.push(d.message),
  })
  const pdf = await ad.convertToBytesAsync('Hello, *world*.', { backend: 'pdf', attributes: date })
  assert.ok(pdf instanceof Uint8Array)
  assert.equal(text(pdf, 5), '%PDF-')
  assert.deepEqual(messages.filter((m) => m.includes('not installed')), [])
  // Loaded: the synchronous conversion works, with the same bytes.
  const again = ad.convertToBytes('Hello, *world*.', { backend: 'pdf', attributes: date })
  assert.deepEqual(again, pdf)
})

test('without the fonts, built-in ones stand in, with a warning', async () => {
  const messages = []
  const ad = new Asciidart({ onDiagnostic: (d) => messages.push(d.message) })
  const pdf = await ad.convertToBytesAsync('Hello.', { backend: 'pdf' })
  assert.equal(text(pdf, 5), '%PDF-')
  assert.ok(messages.some((m) => m.includes('font family Noto Serif is not installed')), messages)
})

test('an EPUB', async () => {
  const epub = await asciidoc.convertToBytesAsync('= Book\n:doctype: book\n\n== One\n\nText.\n', {
    backend: 'epub3',
  })
  assert.equal(text(epub, 2), 'PK')
})

test('text formats and file formats each have their method', () => {
  assert.throws(() => asciidoc.convert('Hello.', { backend: 'pdf' }), /convertToBytes/)
})
