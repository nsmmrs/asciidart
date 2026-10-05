// Compiled with tsc --noEmit: the scenarios of doc/api.md must type-check.
import {
  Admonition,
  Asciidart,
  asciidoc,
  Backend,
  BlockKind,
  CustomBlock,
  Highlighter,
  IncludeResolver,
  InlineMacro,
  Paragraph,
  SafeMode,
  Section,
  Severity,
  TreeProcessor,
  type Block,
  type Diagnostic,
  type Document,
  type SourceCode,
} from 'asciidart'

const body: string = asciidoc.convert('Hello, *World*!')
const page: string = asciidoc.convert('= T', { standalone: true, backend: Backend.html5, attributes: { icons: 'font' } })

const doc: Document = asciidoc.parse('= Title\n:priority: 2\n\n== Section\n\ntext')
const title: string | null = doc.sourceTitle
const priority: number | null = doc.attributes.intValue('priority')
const header: Record<string, string | null> = doc.headerAttributes
const sections: Section[] = doc.descendants(Section)
const sectionTitles: (string | null)[] = sections.map((s) => s.title)

const render = (block: Block): string =>
  block instanceof Section ? `# ${block.title}\n` : block instanceof Paragraph ? `${block.plainText}\n` : ''
const markdown: string = doc.blocks.map(render).join('')

class Upper extends Highlighter {
  highlight(code: SourceCode): string {
    return code.source.toUpperCase()
  }
}

const reported: Diagnostic[] = []
const ad = new Asciidart({
  safe: SafeMode.server,
  html: (node, defaults) =>
    node instanceof Admonition ? `<aside>${defaults.content(node)}</aside>` : defaults.render(node),
  extensions: [
    new InlineMacro('issue', (m) => m.link(`https://example.org/${m.target}`, { text: `#${m.target}` })),
    new CustomBlock('shout', (b) => b.paragraph(b.source.toUpperCase()), { on: [BlockKind.paragraph] }),
    new IncludeResolver(async (r) => (r.target === 'remote' ? 'From far.' : null)),
    new TreeProcessor((d) => {
      d.title = d.title ?? 'Untitled'
    }),
  ],
  highlighters: { upper: new Upper() },
  onDiagnostic: (d) => reported.push(d),
})

async function main(): Promise<void> {
  const remote: Document = await ad.parseAsync('include::remote[]')
  const failed = remote.diagnostics.some((d) => d.severity === Severity.warning)
  for await (const result of ad.convertTree('docs', { toDir: 'build' })) {
    console.log(result.outputPath)
  }
  console.log(body, page, title, priority, header, sectionTitles, markdown, failed, reported.length)
}

void main()
