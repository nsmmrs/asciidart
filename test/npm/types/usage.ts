// Compiled with tsc --noEmit: typical uses of the API must type-check.
import {
  ConverterBase,
  ConverterFactory,
  convert,
  Extensions,
  Html5Converter,
  load,
  MemoryLogger,
  LoggerManager,
  SafeMode,
  type AbstractNode,
  type Document,
  type Section,
} from 'asciidart'

async function main(): Promise<void> {
  const doc: Document = await load('= Title\n\n== Section\n\ntext', { safe: 'safe', attributes: { icons: 'font' } })
  const sections: Section[] = doc.getSections()
  const title: string | undefined = sections[0]?.getTitle()
  const html: string | Document = await convert('*hi*', { standalone: false, safe: SafeMode.SERVER })
  const found = doc.findBy({ context: 'paragraph' }, (block) => block.getRole() !== 'skip')
  console.log(title, html, found.length, doc.getRevisionInfo().getNumber())

  const logger = MemoryLogger.create()
  LoggerManager.setLogger(logger)
  console.log(logger.getMessages().map((message) => message.getText()))

  Extensions.register(function () {
    this.inlineMacro('emoji', function () {
      this.positionalAttributes('size')
      this.process(function (parent, target, attrs) {
        return this.createInline(parent, 'quoted', `:${target}:${attrs.size ?? ''}`, { type: 'strong' })
      })
    })
    this.treeProcessor(function () {
      this.process((tree) => {
        tree.setAttribute('processed', '')
      })
    })
  })
  const registry = Extensions.create()
  registry.block('shout', function () {
    this.onContext('paragraph')
    this.process((parent, reader) => this.createBlock(parent, 'paragraph', reader.getLines().map((l) => l.toUpperCase())))
  })
  await convert('[shout]\nhi', { extension_registry: registry })

  class TextConverter extends ConverterBase {
    convert_paragraph(node: AbstractNode): string {
      return String(node.getAttribute('text', ''))
    }
  }
  ConverterFactory.register(TextConverter, 'text')
  class Custom extends Html5Converter {
    convert_paragraph(node: AbstractNode): string | undefined {
      return `<p class="custom">${this.convertBuiltIn(node)}</p>`
    }
  }
  await convert('para', { converter: new Custom() })
}

void main()
