// The browser build converts like the Node.js build (proven identical to
// Asciidoctor by the parity gates), in headless Chromium.
import assert from 'node:assert/strict'
import { readdirSync, readFileSync } from 'node:fs'
import { createServer } from 'node:http'
import { join } from 'node:path'
import { after, before, test } from 'node:test'
import { build } from 'esbuild'
import { chromium } from 'playwright-core'
import { Asciidart, FontFile, SafeMode } from 'asciidart'

const fixtures = join(import.meta.dirname, '..', '..', 'vendor', 'asciidoctor', 'test', 'fixtures')
const executablePath = process.env.CHROMIUM_PATH ?? '/usr/bin/chromium'

let server
let browser
let page

before(async () => {
  const bundle = await build({
    stdin: {
      contents:
        "import * as asciidart from 'asciidart'\nglobalThis.asciidart = asciidart\n",
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
    } else {
      response.writeHead(200, { 'content-type': 'text/html' })
      response.end('<!doctype html><script type="module" src="/bundle.js"></script>')
    }
  })
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
  browser = await chromium.launch({ executablePath })
  page = await browser.newPage()
  const errors = []
  page.on('pageerror', (error) => errors.push(error))
  await page.goto(`http://127.0.0.1:${server.address().port}/`)
  await page.waitForFunction(() => globalThis.asciidart !== undefined)
  assert.deepEqual(errors, [])
})

after(async () => {
  await browser?.close()
  server?.close()
})

test('reports the versions', async () => {
  const versions = await page.evaluate(() => [
    globalThis.asciidart.asciidartVersion,
    globalThis.asciidart.asciidoctorVersion,
  ])
  assert.deepEqual(versions, ['0.1.0', '2.1.0.alpha.0'])
})

// doctime-localtime.adoc prints the current time, which can tick between the
// two conversions.
const clockDependent = new Set(['doctime-localtime.adoc'])
const secure = new Asciidart({ safe: SafeMode.secure })

for (const name of readdirSync(fixtures)
  .filter((file) => file.endsWith('.adoc') && !clockDependent.has(file))
  .sort()) {
  test(`converts ${name} like Node.js`, async () => {
    const source = readFileSync(join(fixtures, name), 'utf8')
    const expected = secure.convert(source)
    const actual = await page.evaluate(
      (input) => new globalThis.asciidart.Asciidart({ safe: 'secure' }).convert(input),
      source
    )
    assert.equal(actual, expected)
  })
}

test('includes behave as missing files without a file system', async () => {
  const output = await page.evaluate(() =>
    new globalThis.asciidart.Asciidart({ safe: 'safe' }).convert('include::other.adoc[]')
  )
  assert.match(output, /Unresolved directive in &lt;stdin&gt; - include::other\.adoc\[\]/)
})

test('makes a PDF in the browser like Node.js, its part loaded on demand', async () => {
  const fonts = join(import.meta.dirname, '..', '..', 'vendor', 'asciidoctor-pdf', 'data', 'fonts')
  const regular = readFileSync(join(fonts, 'notoserif-regular-subset.ttf'))
  const attributes = { localdatetime: '2020-01-01 00:00:00 +0000' }
  const expected = await new Asciidart({
    fonts: [new FontFile('notoserif-regular-subset.ttf', regular)],
  }).convertToBytesAsync('Hello, browser.', { backend: 'pdf', attributes })
  const actual = await page.evaluate(
    async ({ font, attributes }) => {
      const { Asciidart, FontFile } = globalThis.asciidart
      const ad = new Asciidart({ fonts: [new FontFile('notoserif-regular-subset.ttf', new Uint8Array(font))] })
      return Array.from(await ad.convertToBytesAsync('Hello, browser.', { backend: 'pdf', attributes }))
    },
    { font: Array.from(regular), attributes }
  )
  assert.deepEqual(Uint8Array.from(actual), expected)
})
