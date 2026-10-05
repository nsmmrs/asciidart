// The facade's extension and converter APIs, and the behavior of facade
// nodes under util.inspect and deep equality.

import assert from 'node:assert/strict'
import { afterEach, describe, test } from 'node:test'
import { inspect } from 'node:util'

import {
  ConverterBase,
  ConverterFactory,
  convert,
  deriveBackendTraits,
  Extensions,
  Block,
  Html5Converter,
  load,
  PreprocessorReader,
  Reader,
} from 'asciidart'

afterEach(() => {
  Extensions.unregisterAll()
  ConverterFactory.unregisterAll()
})

describe('nodes', () => {
  test('inspecting a node stays small', async () => {
    const doc = await load('[#intro]\nHello\n\n* one\n* two\n')
    assert.equal(inspect(doc.blocks[0]), 'Block <paragraph#intro>')
    assert.ok(inspect(doc, { depth: 1000 }).length < 200)
  })

  test('a failed assertion on nodes reports quickly', async () => {
    const doc = await load('* one\n* two\n* three\n')
    const items = doc.blocks[0].getItems()
    assert.throws(() => assert.deepEqual(items, 'text'), /Expected values/)
  })

  test('arrays from the core are plain arrays', async () => {
    const doc = await load('para\n\n* one\n* two\n')
    for (const array of [
      doc.blocks[0].applySubs(['*a*']),
      doc.blocks[0].getRoles(),
      doc.blocks[0].getSubstitutions(),
      doc.getAuthors(),
      doc.findBy({ context: 'list_item' }),
    ]) {
      assert.deepEqual(Object.getOwnPropertySymbols(array), [])
    }
    assert.deepEqual(doc.blocks[0].applySubs(['*a*']), ['<strong>a</strong>'])
  })

  test('the content of a list is its items', async () => {
    const doc = await load('* one\n* two\n')
    const list = doc.blocks[0]
    assert.deepEqual(await list.content(), list.getItems())
  })
})

describe('substitutions', () => {
  test('applySubs with the normal, named and no substitutions', async () => {
    const doc = await load('para')
    const para = doc.blocks[0]
    assert.equal(para.applySubs('*a* & b'), '<strong>a</strong> &amp; b')
    assert.equal(para.applySubs('*a* & b', ['specialcharacters']), '*a* &amp; b')
    assert.equal(para.applySubs('*a* & b', 'quotes'), '<strong>a</strong> & b')
    assert.equal(para.applySubs('*a*', null), '*a*')
    assert.deepEqual(para.applySubs(['*a*', '_b_']), ['<strong>a</strong>', '<em>b</em>'])
  })

  test('the single substitutions', async () => {
    const para = (await load('para', { attributes: { name: 'value' } })).blocks[0]
    assert.equal(para.subQuotes('*a*'), '<strong>a</strong>')
    assert.equal(para.subSpecialchars('<a>'), '&lt;a&gt;')
    assert.equal(para.subAttributes('{name}'), 'value')
    assert.equal(para.subReplacements('(C)'), '&#169;')
    assert.equal(para.subMacros('https://example.org[x]'), '<a href="https://example.org">x</a>')
    assert.deepEqual(para.expandSubs('normal'), [
      'specialcharacters',
      'quotes',
      'attributes',
      'replacements',
      'macros',
      'post_replacements',
    ])
    assert.deepEqual(para.resolvePassSubs('q'), ['quotes'])
  })
})

describe('readers and factories', () => {
  test('a reader constructed from lines', () => {
    const reader = new Reader(['one', '', 'two'])
    assert.deepEqual(reader.peekLines(2), ['one', ''])
    assert.equal(reader.readLine(), 'one')
    assert.ok(reader.isNextLineEmpty())
    reader.skipBlankLines()
    assert.deepEqual(reader.readLinesUntil({ terminator: 'none' }), ['two'])
    assert.ok(reader.empty())
  })

  test('a preprocessor reader resolves directives', async () => {
    const doc = await load('', { attributes: { flag: '' } })
    const reader = new PreprocessorReader(doc, ['ifdef::flag[]', 'yes', 'endif::[]', 'after'])
    assert.deepEqual(reader.readLines(), ['yes', 'after'])
  })

  test('Block.create, list and item predicates, role setter', async () => {
    const doc = await load('* one\n* two\n')
    const block = Block.create(doc, 'paragraph', { source: 'made', attributes: { role: 'r' } })
    assert.equal(block.getSource(), 'made')
    block.role = 'changed'
    assert.equal(block.getRole(), 'changed')
    const list = doc.blocks[0]
    assert.ok(list.outline())
    assert.ok(list.getItems()[0].simple())
    assert.ok(!list.getItems()[0].compound())
  })
})

describe('extensions', () => {
  test('a global group with a DSL inline macro', async () => {
    Extensions.register(function () {
      this.inlineMacro('emoji', function () {
        this.process((parent, target) =>
          this.createInline(parent, 'quoted', `:${target}:`, { type: 'strong' })
        )
      })
    })
    assert.equal(
      await convert('Hi emoji:wave[]', { standalone: false }),
      '<div class="paragraph">\n<p>Hi <strong>:wave:</strong></p>\n</div>'
    )
  })

  test('a block processor reading its lines', async () => {
    const registry = Extensions.create()
    registry.block(function () {
      this.named('shout')
      this.onContext('paragraph')
      this.process((parent, reader) =>
        this.createBlock(parent, 'paragraph', reader.getLines().map((l) => l.toUpperCase()))
      )
    })
    const html = await convert('[shout]\nquiet words', { extension_registry: registry })
    assert.match(html, /<p>QUIET WORDS<\/p>/)
  })

  test('node methods inside a processor return values directly', async () => {
    let title
    Extensions.register(function () {
      this.treeProcessor(function () {
        this.process((doc) => {
          title = doc.blocks[0].convert()
        })
      })
    })
    await convert('Some *text*.')
    assert.match(title, /<strong>text<\/strong>/)
  })

  test('preprocessor, include processor, docinfo and postprocessor', async () => {
    const registry = Extensions.create(function () {
      this.preprocessor(function () {
        this.process((doc, reader) => {
          assert.ok(reader instanceof Reader)
          reader.unshiftLine('first line')
          return reader
        })
      })
      this.includeProcessor(function () {
        this.handles((target) => target.endsWith('.virtual'))
        this.process((doc, reader, target) => {
          reader.pushInclude(['included from ' + target], target, target, 1, {})
        })
      })
      this.docinfoProcessor(function () {
        this.atLocation('head')
        this.process(() => '<meta name="x" content="y">')
      })
      this.postprocessor(function () {
        this.process((doc, output) => output.replace('</body>', '<!-- post --></body>'))
      })
    })
    const html = await convert('include::a.virtual[]', {
      extension_registry: registry,
      standalone: true,
      safe: 'safe',
    })
    assert.match(html, /<p>first line\nincluded from a.virtual<\/p>/)
    assert.match(html, /<meta name="x" content="y">/)
    assert.match(html, /<!-- post --><\/body>/)
  })

  test('a processor returning a promise is rejected', async () => {
    Extensions.register(function () {
      this.treeProcessor(function () {
        this.process(async () => {})
      })
    })
    await assert.rejects(convert('text'), /asynchronous extensions are not supported/)
  })

  test('an error thrown by a processor reaches the caller', async () => {
    const failure = new TypeError('bad input')
    Extensions.register(function () {
      this.treeProcessor(function () {
        this.process(() => {
          throw failure
        })
      })
    })
    await assert.rejects(convert('text'), (error) => error === failure)
  })

  test('a registry with allow-uri-read keeps its processors', async () => {
    const registry = Extensions.create()
    registry.postprocessor(function () {
      this.process((doc, output) => output + '!')
    })
    const options = { extension_registry: registry, attributes: { 'allow-uri-read': '' } }
    assert.equal(await convert('text', options), '<div class="paragraph">\n<p>text</p>\n</div>!')
  })

  test('groups are listed and unregistered by name', () => {
    Extensions.register('one', function () {})
    Extensions.register('two', function () {})
    assert.deepEqual(Object.keys(Extensions.getGroups()).sort(), ['one', 'two'])
    Extensions.unregister('one')
    assert.deepEqual(Object.keys(Extensions.getGroups()), ['two'])
  })
})

describe('converters', () => {
  test('a ConverterBase subclass registered for a new backend', async () => {
    class TextConverter extends ConverterBase {
      constructor(backend, opts) {
        super(backend, opts)
        this.outfilesuffix = '.txt'
      }

      convert_document(node) {
        return node.getContent()
      }

      convert_embedded(node) {
        return node.getContent()
      }

      convert_paragraph(node) {
        return `[${node.getContent()}]`
      }
    }
    ConverterFactory.register(TextConverter, 'text')
    assert.equal(ConverterFactory.for('text'), TextConverter)
    assert.equal(await convert('one\n\ntwo', { backend: 'text' }), '[one]\n[two]')
  })

  test('an Html5Converter subclass overriding one transform', async () => {
    class Custom extends Html5Converter {
      convert_paragraph(node) {
        return `<p class="custom">${node.getContent()}</p>`
      }
    }
    const html = await convert('para\n\n----\ncode\n----', { converter: new Custom() })
    assert.match(html, /<p class="custom">para<\/p>/)
    assert.match(html, /<div class="listingblock">/)
  })

  test('backend traits', () => {
    assert.deepEqual(deriveBackendTraits('html5'), {
      basebackend: 'html',
      filetype: 'html',
      outfilesuffix: '.html',
      htmlsyntax: 'html',
    })
  })
})
