// The browser build converts like the Node.js build (proven identical to
// Asciidoctor by the parity gates), in headless Chromium.
import assert from 'node:assert/strict'
import { readdirSync, readFileSync } from 'node:fs'
import { createServer } from 'node:http'
import { join } from 'node:path'
import { after, before, test } from 'node:test'
import { build } from 'esbuild'
import { chromium } from 'playwright-core'
import { Ptome, FontFile, SafeMode } from 'ptome'

const fixtures = join(import.meta.dirname, '..', '..', 'vendor', 'asciidoctor', 'test', 'fixtures')
const webFonts = join(import.meta.dirname, '..', 'fixtures', 'fonts')
const executablePath = process.env.CHROMIUM_PATH ?? '/usr/bin/chromium'

let server
let browser
let page
// Another origin, for a cross-origin style sheet and its fonts (CORS).
let otherServer

before(async () => {
  const bundle = await build({
    stdin: {
      contents:
        "import * as ptome from 'ptome'\nglobalThis.ptome = ptome\n",
      resolveDir: import.meta.dirname,
    },
    bundle: true,
    platform: 'browser',
    format: 'esm',
    write: false,
  })
  const script = bundle.outputFiles[0].text
  server = createServer((request, response) => {
    if (request.url === '/bundle.js') {
      response.writeHead(200, { 'content-type': 'text/javascript' })
      response.end(script)
    } else if (request.url === '/fonts.html') {
      // A page with web fonts: one sheet imported for a medium, one of
      // another origin, whose rules can't be read (only fetched again).
      response.writeHead(200, { 'content-type': 'text/html' })
      response.end(
        '<!doctype html><style>@import url(/regular.css) screen;</style>' +
          `<link rel="stylesheet" href="http://localhost:${otherServer.address().port}/bold.css">` +
          '<script type="module" src="/bundle.js"></script>'
      )
    } else if (request.url === '/regular.css') {
      response.writeHead(200, { 'content-type': 'text/css' })
      response.end(
        '@font-face{font-family:"Page Serif";unicode-range:U+0400-045F;' +
          'src:url(/missing-cyrillic.woff2) format("woff2")}' +
          '@font-face{font-family:"Page Serif";unicode-range:U+0000-00FF;' +
          'src:url(/fonts/notoserif-regular-ascii.woff2) format("woff2")}'
      )
    } else if (request.url.startsWith('/fonts/')) {
      response.writeHead(200, { 'content-type': 'font/woff2' })
      response.end(readFileSync(join(webFonts, request.url.slice(7))))
    } else if (request.url.startsWith('/missing')) {
      response.writeHead(404)
      response.end()
    } else {
      response.writeHead(200, { 'content-type': 'text/html' })
      response.end('<!doctype html><script type="module" src="/bundle.js"></script>')
    }
  })
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  otherServer = createServer((request, response) => {
    const headers = { 'access-control-allow-origin': '*' }
    if (request.url === '/bold.css') {
      response.writeHead(200, { ...headers, 'content-type': 'text/css' })
      response.end(
        '@font-face{font-family:"Page Serif";font-weight:bold;' +
          'src:local("Nothing"),url(fonts/notoserif-bold-ascii.woff) format("woff")}'
      )
    } else if (request.url.startsWith('/fonts/')) {
      response.writeHead(200, { ...headers, 'content-type': 'font/woff' })
      response.end(readFileSync(join(webFonts, request.url.slice(7))))
    } else {
      response.writeHead(404, headers)
      response.end()
    }
  })
  await new Promise((resolve) => otherServer.listen(0, 'localhost', resolve))
  browser = await chromium.launch({ executablePath })
  page = await browser.newPage()
  const errors = []
  page.on('pageerror', (error) => errors.push(error))
  await page.goto(`http://127.0.0.1:${server.address().port}/`)
  await page.waitForFunction(() => globalThis.ptome !== undefined)
  assert.deepEqual(errors, [])
})

after(async () => {
  await browser?.close()
  server?.close()
  otherServer?.close()
})

test('reports the versions', async () => {
  const versions = await page.evaluate(() => [
    globalThis.ptome.ptomeVersion,
    globalThis.ptome.asciidoctorVersion,
  ])
  assert.deepEqual(versions, ['0.1.0', '2.1.0.alpha.0'])
})

// doctime-localtime.adoc prints the current time, which can tick between the
// two conversions.
const clockDependent = new Set(['doctime-localtime.adoc'])
const secure = new Ptome({ safe: SafeMode.secure })

for (const name of readdirSync(fixtures)
  .filter((file) => file.endsWith('.adoc') && !clockDependent.has(file))
  .sort()) {
  test(`converts ${name} like Node.js`, async () => {
    const source = readFileSync(join(fixtures, name), 'utf8')
    const expected = secure.convert(source)
    const actual = await page.evaluate(
      (input) => new globalThis.ptome.Ptome({ safe: 'secure' }).convert(input),
      source
    )
    assert.equal(actual, expected)
  })
}

test('includes behave as missing files without a file system', async () => {
  const output = await page.evaluate(() =>
    new globalThis.ptome.Ptome({ safe: 'safe' }).convert('include::other.adoc[]')
  )
  assert.match(output, /Unresolved directive in &lt;stdin&gt; - include::other\.adoc\[\]/)
})

test('makes a PDF in the browser like Node.js, its part loaded on demand', async () => {
  const fonts = join(import.meta.dirname, '..', '..', 'vendor', 'asciidoctor-pdf', 'data', 'fonts')
  const regular = readFileSync(join(fonts, 'notoserif-regular-subset.ttf'))
  const attributes = { localdatetime: '2020-01-01 00:00:00 +0000' }
  const expected = await new Ptome({
    fonts: [new FontFile('notoserif-regular-subset.ttf', regular)],
  }).convertToBytesAsync('Hello, browser.', { backend: 'pdf', attributes })
  const actual = await page.evaluate(
    async ({ font, attributes }) => {
      const { Ptome, FontFile } = globalThis.ptome
      const ad = new Ptome({ fonts: [new FontFile('notoserif-regular-subset.ttf', new Uint8Array(font))] })
      return Array.from(await ad.convertToBytesAsync('Hello, browser.', { backend: 'pdf', attributes }))
    },
    { font: Array.from(regular), attributes }
  )
  assert.deepEqual(Uint8Array.from(actual), expected)
})

test("makes a PDF in the page's web fonts (WOFF2 and WOFF), like Node.js given them", async () => {
  const fontsPage = await browser.newPage()
  await fontsPage.goto(`http://127.0.0.1:${server.address().port}/fonts.html`)
  await fontsPage.waitForFunction(() => globalThis.ptome !== undefined)
  const source = 'Hello, *page* fonts.'
  const attributes = { localdatetime: '2020-01-01 00:00:00 +0000' }
  const convert = (pageFonts) =>
    fontsPage.evaluate(
      async ({ source, attributes, pageFonts }) => {
        const { Ptome } = globalThis.ptome
        const messages = []
        const ad = new Ptome({ pageFonts, onDiagnostic: (d) => messages.push(d.message) })
        const pdf = await ad.convertToBytesAsync(source, { backend: 'pdf', attributes })
        return { pdf: Array.from(pdf), messages }
      },
      { source, attributes, pageFonts }
    )
  const withPageFonts = await convert(true)
  assert.deepEqual(
    withPageFonts.messages.filter((m) => m.includes('not installed')),
    []
  )
  const expected = await new Ptome({
    fonts: ['notoserif-regular-ascii.woff2', 'notoserif-bold-ascii.woff'].map(
      (name) => new FontFile(name, readFileSync(join(webFonts, name)))
    ),
  }).convertToBytesAsync(source, { backend: 'pdf', attributes })
  assert.deepEqual(Uint8Array.from(withPageFonts.pdf), expected)
  const without = await convert(false)
  assert.ok(without.messages.some((m) => m.includes('Noto Serif is not installed')))
  await fontsPage.close()
})

/** The entry names of the ZIP archive [bytes], from its central directory. */
function zipNames(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  let end = bytes.length - 22
  while (end >= 0 && view.getUint32(end, true) !== 0x06054b50) end--
  const count = view.getUint16(end + 10, true)
  let at = view.getUint32(end + 16, true)
  const names = []
  for (let i = 0; i < count; i++) {
    const nameLength = view.getUint16(at + 28, true)
    const extra = view.getUint16(at + 30, true)
    const comment = view.getUint16(at + 32, true)
    names.push(new TextDecoder().decode(bytes.subarray(at + 46, at + 46 + nameLength)))
    at += 46 + nameLength + extra + comment
  }
  return names
}

test('makes an EPUB in the browser, without a host zlib, with the files Node.js makes', async () => {
  const source = '= Book\n:doctype: book\n\n== One\n\nText.\n'
  const attributes = { reproducible: '' }
  const expected = await new Ptome().convertToBytesAsync(source, { backend: 'epub3', attributes })
  const actual = Uint8Array.from(
    await page.evaluate(
      async ({ source, attributes }) =>
        Array.from(
          await new globalThis.ptome.Ptome().convertToBytesAsync(source, {
            backend: 'epub3',
            attributes,
          })
        ),
      { source, attributes }
    )
  )
  assert.equal(new TextDecoder().decode(actual.subarray(30, 58)), 'mimetypeapplication/epub+zip')
  assert.deepEqual(zipNames(actual), zipNames(expected))
})
