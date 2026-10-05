// The browser build converts like the Node.js build (proven identical to
// Asciidoctor 2.0.26 by the parity gates), in headless Chromium.
import assert from 'node:assert/strict'
import { readdirSync, readFileSync } from 'node:fs'
import { createServer } from 'node:http'
import { join } from 'node:path'
import { after, before, test } from 'node:test'
import { build } from 'esbuild'
import { chromium } from 'playwright-core'
import { convert } from 'asciidart'

const fixtures = join(import.meta.dirname, '..', '..', 'vendor', 'asciidoctor', 'test', 'fixtures')
const executablePath = process.env.CHROMIUM_PATH ?? '/usr/bin/chromium'

let server
let browser
let page

before(async () => {
  const bundle = await build({
    stdin: {
      contents:
        "import * as asciidoctor from 'asciidart'\nglobalThis.asciidoctor = asciidoctor\n",
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
  await page.waitForFunction(() => globalThis.asciidoctor !== undefined)
  assert.deepEqual(errors, [])
})

after(async () => {
  await browser?.close()
  server?.close()
})

test('reports the versions', async () => {
  const versions = await page.evaluate(() => [
    globalThis.asciidoctor.getVersion(),
    globalThis.asciidoctor.getCoreVersion(),
  ])
  assert.deepEqual(versions, ['0.1.0', '2.0.26'])
})

for (const name of readdirSync(fixtures).filter((file) => file.endsWith('.adoc')).sort()) {
  test(`converts ${name} like Node.js`, async () => {
    const source = readFileSync(join(fixtures, name), 'utf8')
    const expected = await convert(source, { safe: 'secure' })
    const actual = await page.evaluate(
      (input) => globalThis.asciidoctor.convert(input, { safe: 'secure' }),
      source
    )
    assert.equal(actual, expected)
  })
}

test('includes behave as missing files without a file system', async () => {
  const output = await page.evaluate(() =>
    globalThis.asciidoctor.convert('include::other.adoc[]', { safe: 'safe' })
  )
  assert.match(output, /Unresolved directive in &lt;stdin&gt; - include::other\.adoc\[\]/)
})
