// PDFs and EPUBs from JavaScript: the backends load on demand (separate
// parts of the bundle), and fonts are given as bytes.
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
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

test('a font that is not installed: a built-in one stands in, with a warning', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'asciidart-files-'))
  try {
    writeFileSync(join(dir, 'theme.yml'), 'extends: default\nbase:\n  font_family: No Such Family\n')
    const messages = []
    const ad = new Asciidart({ safe: 'unsafe', onDiagnostic: (d) => messages.push(d.message) })
    const pdf = await ad.convertToBytesAsync('Hello.', {
      backend: 'pdf',
      attributes: { 'pdf-theme': join(dir, 'theme.yml') },
    })
    assert.equal(text(pdf, 5), '%PDF-')
    assert.ok(
      messages.some((m) => m.includes('font family No Such Family is not installed')),
      messages.join('\n')
    )
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
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

test('asciidart doctor runs on Node.js', () => {
  const bin = join(import.meta.dirname, '..', '..', 'build', 'npm', 'bin', 'asciidart.js')
  const usage = execFileSync(process.execPath, [bin, 'doctor', '--help'], { encoding: 'utf8' })
  assert.match(usage, /Usage: asciidart doctor/)
})
