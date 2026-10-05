// The JavaScript projection of the Dart API: the scenarios of doc/api.md
// (test/api/scenarios_test.dart in Dart), plus what JavaScript adds:
// identity, instanceof, inspection, errors and promises.

import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, test } from 'node:test'
import { inspect } from 'node:util'

import {
  Admonition,
  AdmonitionKind,
  Asciidart,
  AsciidartException,
  asciidartVersion,
  asciidoc,
  asciidoctorVersion,
  Backend,
  Block,
  BlockKind,
  BlockMacro,
  CustomBlock,
  DiagnosticCode,
  Docinfo,
  Document,
  Highlighter,
  Formatted,
  FormattedKind,
  Image,
  IncludeResolver,
  InlineText,
  Link,
  InlineImage,
  InlineMacro,
  ListItem,
  Listing,
  Node,
  Paragraph,
  Postprocessor,
  Preprocessor,
  SafeMode,
  Section,
  TreeProcessor,
  UnorderedList,
} from 'asciidart'

const guide = `= Guide

== Install

Run the installer.

[source,java]
----
class Main {}
----

== Use

NOTE: Read the docs.

* one
* two
`

describe('1. render AsciiDoc to HTML', () => {
  test('convert returns the body, synchronously', () => {
    assert.equal(
      asciidoc.convert('Hello, *World*!'),
      '<div class="paragraph">\n<p>Hello, <strong>World</strong>!</p>\n</div>'
    )
  })

  test('standalone pages, attributes and backends', () => {
    const page = asciidoc.convert('= T\n\nNOTE: x', { standalone: true, attributes: { icons: 'font' } })
    assert.match(page, /^<!DOCTYPE html>/)
    assert.match(page, /<i class="fa icon-note"/)
    assert.equal(asciidoc.convert('text', { backend: Backend.docbook5 }), '<simpara>text</simpara>')
  })
})

describe('2. read metadata, then render', () => {
  test('typed attributes, the title as written, the header', () => {
    const doc = asciidoc.parse("= Don't stop\n:status: doing\n:priority: 2\n:labels: a, b\n\nThe *body*.")
    assert.ok(doc instanceof Document)
    assert.equal(doc.sourceTitle, "Don't stop")
    assert.equal(doc.attributes.get('status'), 'doing')
    assert.equal(doc.attributes.intValue('priority'), 2)
    assert.deepEqual(doc.attributes.listValue('labels'), ['a', 'b'])
    assert.deepEqual(doc.headerAttributes, { status: 'doing', priority: '2', labels: 'a, b' })
    assert.match(doc.toHtml(), /<strong>body<\/strong>/)
    assert.equal(asciidoc.parseHeader('= T\n:x: y\n\nbody').blocks.length, 0)
  })

  test('edit a header attribute, keeping the rest as written', () => {
    const source = '= T\n:status: doing\n// note\n:priority:  2\n\nbody\n'
    const edited = asciidoc.parse(source).withAttribute('status', 'done')
    assert.ok(edited instanceof Document)
    assert.equal(edited.source, source.replace(':status: doing', ':status: done'))
    assert.equal(edited.attributes.get('status'), 'done')
    assert.equal(edited.withoutAttribute('priority').source, '= T\n:status: done\n// note\n\nbody\n')
    assert.throws(
      () => asciidoc.parse('= T\nifdef::x[]\n:status: a\nendif::[]\n\nb').withAttribute('status', 'b'),
      AsciidartException,
    )
  })
})

describe('3. walk and query the tree', () => {
  const doc = asciidoc.parse(guide)

  test('descendants by class, with instanceof and identity', () => {
    const sections = doc.descendants(Section)
    assert.deepEqual(sections.map((s) => s.title), ['Install', 'Use'])
    assert.ok(sections[0] instanceof Section)
    assert.ok(sections[0] instanceof Block)
    assert.ok(sections[0] instanceof Node)
    assert.ok(!(sections[0] instanceof Paragraph))
    assert.equal(sections[0], doc.descendants(Section)[0])
    assert.equal(sections[0].parent, doc)
    assert.equal(doc.descendants(Listing)[0].language, 'java')
    assert.equal(doc.descendants(Admonition)[0].kind, AdmonitionKind.note)
    assert.deepEqual(doc.descendants(ListItem).map((i) => i.plainText), ['one', 'two'])
    assert.ok(doc.descendants().length > 5)
  })

  test('diagnostics', () => {
    const broken = asciidoc.parse('See <<nowhere>>.')
    broken.convert()
    assert.ok(broken.diagnostics.some((d) => d.code === DiagnosticCode.unknownReference))
  })

  test('arrays from the core are plain arrays, and inspection stays small', () => {
    const blocks = doc.blocks
    assert.equal(Object.getPrototypeOf(blocks), Array.prototype)
    assert.deepEqual(Object.getOwnPropertySymbols(blocks), [])
    // Projected objects have no own properties: their members live on the
    // class, and the Dart object behind them out of reach.
    assert.deepEqual(Reflect.ownKeys(doc), [])
    assert.ok(inspect(doc, { depth: 1000, showHidden: true }).length < 20000)
    // Assertion messages ignore the inspect hook; they must not walk the
    // Dart heap either.
    assert.throws(
      () => assert.deepEqual(blocks, 'text'),
      (error) => error.message.length < 20000
    )
  })
})

describe('4. your own renderer', () => {
  test('a switch over classes', () => {
    const render = (block) =>
      block instanceof Section
        ? `# ${block.title}\n${block.blocks.map(render).join('')}`
        : block instanceof Paragraph
          ? `${block.plainText}\n`
          : block instanceof UnorderedList
            ? block.items.map((i) => `- ${i.plainText}\n`).join('')
            : ''
    assert.equal(
      asciidoc.parse(guide).blocks.map(render).join(''),
      '# Install\nRun the installer.\n# Use\n- one\n- two\n'
    )
  })
})

describe('4b. inline content as a tree', () => {
  test('text and elements, nested', () => {
    const md = (content) =>
      content instanceof InlineText
        ? content.text
        : content instanceof Formatted && content.kind === FormattedKind.strong
          ? `**${content.children.map(md).join('')}**`
          : content instanceof Formatted && content.kind === FormattedKind.emphasis
            ? `_${content.children.map(md).join('')}_`
            : content instanceof Link
              ? `[${content.children.map(md).join('')}](${content.target})`
              : content.plainText
    const doc = asciidoc.parse('= The *Guide*\n\nRead *the https://example.org[_fine_ manual]* -- now.')
    assert.equal(
      doc.blocks[0].inlines.map(md).join(''),
      'Read **the [_fine_ manual](https://example.org)**\u2009—\u2009now.'
    )
    assert.equal(doc.titleInlines.map(md).join(''), 'The **Guide**')
  })
})

describe('5. customize the HTML', () => {
  test('override some nodes, keep the rest', () => {
    const ad = new Asciidart({
      html: (node, defaults) =>
        node instanceof Admonition
          ? `<aside class="${node.kind}">${defaults.content(node)}</aside>`
          : node instanceof InlineImage
            ? defaults.render(node).replace('<img', '<img loading="lazy"')
            : defaults.render(node),
    })
    const html = ad.convert('NOTE: *Hi*\n\nimage:a.png[] text')
    assert.match(html, /<aside class="note"><strong>Hi<\/strong><\/aside>/)
    assert.match(html, /<img loading="lazy" src="a.png"/)
  })
})

describe('6. extensions', () => {
  test('every kind', () => {
    const ad = new Asciidart({
      extensions: [
        new InlineMacro('issue', (m) => m.link(`https://example.org/${m.target}`, { text: `#${m.target}` })),
        new BlockMacro('hello', (m) => m.html(`<p>hello ${m.target}</p>`)),
        new CustomBlock('shout', (b) => b.paragraph(b.source.toUpperCase()), { on: [BlockKind.paragraph] }),
        new IncludeResolver((r) => (r.target === 'db:intro' ? 'Included *text*.' : null)),
        new TreeProcessor((doc) => {
          for (const image of doc.descendants(Image)) image.target = `https://cdn.example.org/${image.target}`
        }),
        new Preprocessor((lines) => lines.map((l) => l.replace('TODO', 'done'))),
        new Postprocessor((output) => `${output}\n<!-- end -->`),
        new Docinfo(() => '<meta name="x-test">'),
      ],
    })
    const html = ad.convert('issue:7[]\n\nhello::world[]\n\n[shout]\nquiet please\n\ninclude::db:intro[]\n\nimage::a.png[]\n\nTODO\n')
    assert.match(html, /<a href="https:\/\/example.org\/7">#7<\/a>/)
    assert.match(html, /<p>hello world<\/p>/)
    assert.match(html, /QUIET PLEASE/)
    assert.match(html, /Included <strong>text<\/strong>\./)
    assert.match(html, /src="https:\/\/cdn.example.org\/a.png"/)
    assert.match(html, /<p>done<\/p>/)
    assert.match(html, /<!-- end -->$/)
    assert.match(ad.convert('x', { standalone: true }), /<meta name="x-test">/)
  })

  test('an asynchronous include resolver', async () => {
    const ad = new Asciidart({
      extensions: [new IncludeResolver(async (r) => (r.target === 'remote' ? 'From *far*.' : null))],
    })
    const doc = await ad.parseAsync('include::remote[]')
    assert.match(doc.toHtml(), /From <strong>far<\/strong>\./)
    assert.throws(() => ad.parse('include::remote[]'), AsciidartException)
  })
})

describe('7. fail on warnings', () => {
  test('diagnostics have severities and locations, and onDiagnostic sees them', () => {
    const reported = []
    const ad = new Asciidart({ onDiagnostic: (d) => reported.push(d) })
    const doc = ad.parse('== A\n\n==== B\n', { path: 'docs/index.adoc' })
    const warnings = doc.diagnostics.filter((d) => d.severity === 'warning')
    assert.equal(warnings[0].code, DiagnosticCode.sectionOutOfSequence)
    assert.equal(warnings[0].location.line, 3)
    assert.equal(reported.length, doc.diagnostics.length)
  })
})

describe('8. files', () => {
  test('convertFile, convertTree and parseFile', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'asciidart-npm-'))
    try {
      mkdirSync(join(dir, 'docs', 'guide'), { recursive: true })
      writeFileSync(join(dir, 'docs', 'index.adoc'), '= Home\n\nhi')
      writeFileSync(join(dir, 'docs', 'guide', 'start.adoc'), '= Start\n\ngo')
      writeFileSync(join(dir, 'docs', '_partial.adoc'), 'skip')
      const ad = new Asciidart({ safe: SafeMode.unsafe })
      const doc = await ad.convertFile(join(dir, 'docs', 'index.adoc'))
      assert.equal(doc.title, 'Home')
      assert.match(readFileSync(join(dir, 'docs', 'index.html'), 'utf8'), /hi/)
      const outputs = []
      for await (const result of ad.convertTree(join(dir, 'docs'), { toDir: join(dir, 'build') })) {
        outputs.push(result.outputPath.slice(join(dir, 'build').length + 1))
      }
      assert.deepEqual(outputs, ['guide/start.html', 'index.html'])
      assert.equal((await ad.parseFile(join(dir, 'docs', 'index.adoc'))).title, 'Home')
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })
})

describe('also supported', () => {
  test('a highlighter implemented in JavaScript', () => {
    class Upper extends Highlighter {
      highlight(code) {
        return code.source.toUpperCase()
      }

      get head() {
        return '<style>.upper{}</style>'
      }
    }
    const ad = new Asciidart({ highlighters: { upper: new Upper() }, attributes: { 'source-highlighter': 'upper' } })
    const html = ad.convert('[source,txt]\n----\nabc\n----', { standalone: true })
    assert.match(html, /ABC/)
    assert.match(html, /<style>\.upper\{\}<\/style>/)
  })

  test('errors from JavaScript callbacks reach the caller unchanged', () => {
    const mine = new RangeError('mine')
    const ad = new Asciidart({ extensions: [new InlineMacro('boom', () => { throw mine })] })
    assert.throws(() => ad.convert('boom:x[]'), (error) => error === mine)
  })

  test('wrong argument types fail with a TypeError', () => {
    assert.throws(() => asciidoc.convert(42), TypeError)
    assert.throws(() => new Asciidart({ safe: 'nope' }), Error)
  })

  test('nodes are not constructible', () => {
    assert.throws(() => new Section(), TypeError)
  })

  test('versions', () => {
    assert.equal(asciidoctorVersion, '2.0.26')
    assert.match(asciidartVersion, /^\d+\.\d+\.\d+/)
  })
})
