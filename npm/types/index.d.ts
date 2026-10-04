// Types of asciidoctor-dart: the Asciidoctor.js 4.1 API over the Dart
// port of Asciidoctor 2.0.26.

import type { LoggerLike } from './logging.js'

export {
  Logger,
  LoggerManager,
  LogMessage,
  MemoryLogger,
  NullLogger,
  Severity,
  withLogger,
} from './logging.js'

/** AsciiDoc source: a string, an array of lines, or UTF-8 bytes. */
export type Input = string | string[] | Uint8Array

/** A safe mode, by level or name. */
export type SafeModeValue = number | 'unsafe' | 'safe' | 'server' | 'secure' | 'UNSAFE' | 'SAFE' | 'SERVER' | 'SECURE'

/**
 * Document attributes: an object (a `false` or `null` value unsets the
 * attribute), a `name=value` string separated by spaces, or an array of
 * such entries.
 */
export type Attributes = Record<string, string | number | boolean | null | undefined> | string | string[]

/** The options of load, loadFile, convert and convertFile. */
export interface ProcessorOptions {
  safe?: SafeModeValue
  backend?: string
  doctype?: string
  attributes?: Attributes
  standalone?: boolean
  /** The former name of `standalone`. */
  header_footer?: boolean
  base_dir?: string
  /** A path to write the output to, or `false` to return it. */
  to_file?: string | boolean
  to_dir?: string
  mkdirs?: boolean
  sourcemap?: boolean
  parse?: boolean
  parse_header_only?: boolean
  catalog_assets?: boolean
  template_dir?: string
  template_dirs?: string[]
  template_engine?: string
  template_cache?: boolean
  /** A registry from {@link Extensions.create}. */
  extension_registry?: Registry
  /** A converter instance or class used in place of the backend's. */
  converter?: Converter | ConverterClass
}

/** The version of this package. */
export function getVersion(): string
/** The version of Asciidoctor whose behavior this package matches (2.0.26). */
export function getCoreVersion(): string
/** Parses AsciiDoc source into a Document. */
export function load(input: Input, options?: ProcessorOptions): Promise<Document>
/** Parses the AsciiDoc file `filename` into a Document. */
export function loadFile(filename: string, options?: ProcessorOptions): Promise<Document>
/**
 * Converts AsciiDoc source to the output, or to the Document when the output
 * is written to a file (`to_file` or `to_dir`).
 */
export function convert(input: Input, options?: ProcessorOptions): Promise<string | Document>
/**
 * Converts the AsciiDoc file `filename`, writing the output next to it (or to
 * `to_file`/`to_dir`) and returning the Document; with `to_file: false`,
 * returns the output.
 */
export function convertFile(filename: string, options?: ProcessorOptions): Promise<string | Document>

export const SafeMode: {
  readonly UNSAFE: 0
  readonly SAFE: 1
  readonly SERVER: 10
  readonly SECURE: 20
  valueForName(name: string): number | undefined
  getValueForName(name: string): number | undefined
  nameForValue(value: number): string | undefined
  getNameForValue(value: number): string | undefined
  names(): string[]
  getNames(): string[]
}

export const ContentModel: {
  readonly COMPOUND: 'compound'
  readonly SIMPLE: 'simple'
  readonly VERBATIM: 'verbatim'
  readonly RAW: 'raw'
  readonly EMPTY: 'empty'
}

/**
 * A value from the core: a promise, except inside a converter or an extension,
 * which the core calls synchronously and which receive the value itself.
 * `await` works in both cases.
 */
export type Deferred<T> = Promise<T> | T

/** A location in the source. */
export class Cursor {
  constructor(file?: string | null, dir?: string | null, path?: string | null, lineno?: number)
  file: string | null
  dir: string | null
  path: string | null
  lineno: number
  readonly lineInfo: string
  advance(num: number): void
  getLineNumber(): number
  getFile(): string | undefined
  getDirectory(): string | undefined
  getPath(): string | undefined
  getLineInfo(): string
  toString(): string
}

export class DocumentTitle {
  constructor(val: string | { main: string; subtitle?: string; combined: string }, opts?: { separator?: string })
  main: string
  subtitle?: string
  combined: string
  readonly title: string
  isSanitized(): boolean
  hasSubtitle(): boolean
  getMain(): string
  getCombined(): string
  getSubtitle(): string | undefined
  toString(): string
}

export class Author {
  constructor(name?: string, firstname?: string, middlename?: string, lastname?: string, initials?: string, email?: string)
  name?: string
  firstname?: string
  middlename?: string
  lastname?: string
  initials?: string
  email?: string
  getName(): string | undefined
  getFirstName(): string | undefined
  getMiddleName(): string | undefined
  getLastName(): string | undefined
  getInitials(): string | undefined
  getEmail(): string | undefined
}

export class RevisionInfo {
  constructor(number?: string, date?: string, remark?: string)
  number?: string
  date?: string
  remark?: string
  isEmpty(): boolean
  getNumber(): string | undefined
  getDate(): string | undefined
  getRemark(): string | undefined
}

export class Footnote {
  constructor(index: number, id: string | undefined, text: string)
  index: number
  id?: string
  text: string
  getIndex(): number
  getId(): string | undefined
  getText(): string
}

export class ImageReference {
  constructor(target: string, imagesdir?: string)
  target: string
  imagesdir?: string
  getTarget(): string
  getImagesDirectory(): string | undefined
  toString(): string
}

/** A selector for {@link AbstractBlock.findBy}. */
export interface Selector {
  context?: string
  style?: string
  role?: string
  id?: string
  traverse_documents?: boolean
}

/** A filter for {@link AbstractBlock.findBy}: `'prune'`, `'reject'` and `'stop'` steer the walk. */
export type SelectorFilter = (node: AbstractBlock) => boolean | 'prune' | 'reject' | 'stop' | undefined | void

/** The base class of all nodes. */
export class AbstractNode {
  protected constructor()
  readonly context: string
  readonly nodeName: string
  id: string | undefined
  readonly parent: AbstractNode | undefined
  readonly document: Document
  readonly attributes: Record<string, string>
  role: string | undefined
  readonly roles: string[]
  readonly reftext: string | undefined
  readonly logger: LoggerLike
  getContext(): string
  getNodeName(): string
  getId(): string | undefined
  setId(id: string | undefined): void
  getParent(): AbstractNode | undefined
  getDocument(): Document
  isBlock(): boolean
  isInline(): boolean
  getAttribute(name: string, defaultValue?: unknown, fallbackName?: string | boolean): any
  getAttributes(): Record<string, string>
  hasAttribute(name: string, expectedValue?: unknown, fallbackName?: string | boolean): boolean
  isAttribute(name: string, expectedValue?: unknown, fallbackName?: string | boolean): boolean
  setAttribute(name: string, value?: unknown, overwrite?: boolean): boolean
  removeAttribute(name: string): string | undefined
  hasOption(name: string): boolean
  isOption(name: string): boolean
  setOption(name: string): void
  enabledOptions(): Set<string>
  getOptions(): Record<string, string>
  getRole(): string | undefined
  setRole(...names: string[]): string
  getRoles(): string[]
  hasRole(name: string): boolean
  hasRoleAttribute(expectedValue?: string | null): boolean
  addRole(name: string): boolean
  removeRole(name: string): boolean
  /**
   * Applies `subs` to `text`: the normal substitutions by default, none for
   * `null`, or the names in an array or a comma-separated spec.
   */
  applySubs(text: string, subs?: string[] | string | null): string
  applySubs(text: string[], subs?: string[] | string | null): string[]
  applyNormalSubs(text: string): string
  applyHeaderSubs(text: string): string
  applyTitleSubs(text: string): string
  applyReftextSubs(text: string): string
  subSpecialchars(text: string): string
  subSpecialcharacters(text: string): string
  subQuotes(text: string): string
  subAttributes(text: string): string
  subReplacements(text: string): string
  subMacros(text: string): string
  subPostReplacements(text: string): string
  subCallouts(text: string): string
  resolveSubs(subs: string, type?: 'block' | 'inline', defaults?: string[] | null, subject?: string | null): string[] | undefined
  resolveBlockSubs(subs: string, defaults?: string[] | null, subject?: string | null): string[] | undefined
  resolvePassSubs(subs: string): string[] | undefined
  expandSubs(subs: string | string[], subject?: string | null): string[] | undefined
  getReftext(): string | undefined
  hasReftext(): boolean
  isReftext(): boolean
  precomputeReftext(): Deferred<void>
  iconUri(name: string): Deferred<string>
  getIconUri(name: string): Deferred<string>
  imageUri(targetImage: string, assetDirKey?: string): Deferred<string>
  getImageUri(targetImage: string, assetDirKey?: string): Deferred<string>
  mediaUri(target: string, assetDirKey?: string): string
  getMediaUri(target: string, assetDirKey?: string): string
  normalizeWebPath(target: string, start?: string | null, preserveUriTarget?: boolean): string
  normalizeSystemPath(target: string, start?: string | null, jail?: string | null): string
  readAsset(path: string, opts?: { warn_on_failure?: boolean }): Deferred<string | null>
  isUri(value: string): boolean
  getLogger(): LoggerLike
  toString(): string
}

/** The base class of block nodes. */
export class AbstractBlock extends AbstractNode {
  readonly blocks: AbstractBlock[]
  title: string | undefined
  caption: string | undefined
  style: string | undefined
  level: number
  contentModel: string
  readonly sourceLocation: Cursor | undefined
  readonly file: string | undefined
  readonly lineno: number | undefined
  numeral: string | undefined
  readonly number: string | undefined
  readonly subs: string[]
  precomputeTitle(): Deferred<void>
  hasTitle(): boolean
  commitSubs(): void
  convert(): Deferred<string>
  render(): Deferred<string>
  content(): Deferred<string>
  getContent(): Deferred<string>
  append(block: AbstractBlock): this
  hasBlocks(): boolean
  hasSections(): boolean
  sections(): Section[]
  alt(): string
  getAlt(): string
  captionedTitle(): string | undefined
  hasSub(name: string): boolean
  removeSub(name: string): void
  xreftext(xrefstyle?: string | null): Deferred<string | undefined>
  getXrefText(xrefstyle?: string | null): Deferred<string | undefined>
  assignCaption(value?: string | null, captionContext?: string): void
  nextAdjacentBlock(): AbstractBlock | undefined
  findBy(selector?: Selector | SelectorFilter, filter?: SelectorFilter): AbstractBlock[]
  query(selector?: Selector | SelectorFilter, filter?: SelectorFilter): AbstractBlock[]
  getContentModel(): string
  setContentModel(value: string): void
  getBlocks(): AbstractBlock[]
  getSections(): Section[]
  getTitle(): string | undefined
  setTitle(value: string | undefined): void
  getCaption(): string | undefined
  setCaption(value: string | undefined): void
  getCaptionedTitle(): string | undefined
  getStyle(): string | undefined
  setStyle(value: string | undefined): void
  getLevel(): number
  setLevel(value: number): void
  getFile(): string | undefined
  getLineNumber(): number | undefined
  getSourceLocation(): Cursor | undefined
  getSubstitutions(): string[]
  hasSubstitution(name: string): boolean
  addSubstitution(name: string): void
  removeSubstitution(name: string): void
  getNumeral(): string | undefined
  setNumeral(value: string | undefined): void
}

export class Block extends AbstractBlock {
  static create(
    parent: AbstractBlock,
    context: string,
    opts?: { source?: string | string[]; lines?: string[]; attributes?: Record<string, unknown>; content_model?: string }
  ): Block
  readonly blockname: string
  readonly source: string
  lines: string[]
  getSource(): string
  getSourceLines(): string[]
  getBlockName(): string
}

export class Section extends AbstractBlock {
  readonly index: number
  sectname: string
  readonly special: boolean
  readonly numbered: boolean
  readonly name: string
  sectnum(delimiter?: string, append?: string | boolean | null): string
  getIndex(): number
  getSectionName(): string
  setSectionName(value: string): void
  isSpecial(): boolean
  isNumbered(): boolean
  getName(): string
  getSectionNumeral(): string | undefined
  getSectionNumber(): string | undefined
}

export class Inline extends AbstractNode {
  text: string | undefined
  readonly type: string | undefined
  readonly target: string | undefined
  convert(): Deferred<string>
  render(): Deferred<string>
  alt(): string
  xreftext(xrefstyle?: string | null): Deferred<string | undefined>
  getText(): string | undefined
  setText(value: string): void
  getType(): string | undefined
  getTarget(): string | undefined
  getAlt(): string
  getXrefText(xrefstyle?: string | null): Deferred<string | undefined>
}

/** A description list item: the terms and the description. */
export type DescriptionListEntry = [ListItem[], ListItem | undefined]

export class List extends AbstractBlock {
  readonly items: Array<ListItem | DescriptionListEntry>
  hasItems(): boolean
  outline(): boolean
  isOutline(): boolean
  getItems(): Array<ListItem | DescriptionListEntry>
  /** The items, as in Asciidoctor (a list has no converted content of its own). */
  content(): Deferred<any>
}

export class ListItem extends AbstractBlock {
  text: string | undefined
  marker: string | undefined
  readonly list: List
  hasText(): boolean
  simple(): boolean
  isSimple(): boolean
  compound(): boolean
  isCompound(): boolean
  getText(): string | undefined
  setText(value: string): void
  getMarker(): string | undefined
  setMarker(value: string): void
  getList(): List
}

export interface TableRows {
  head: TableCell[][]
  body: TableCell[][]
  foot: TableCell[][]
}

export class Table extends AbstractBlock {
  readonly rows: TableRows
  readonly columns: TableColumn[]
  getRows(): TableRows
  getColumns(): TableColumn[]
  getHeadRows(): TableCell[][]
  getBodyRows(): TableCell[][]
  getFootRows(): TableCell[][]
  hasHeadRows(): boolean
  hasBodyRows(): boolean
  hasFootRows(): boolean
}

export class TableColumn extends AbstractNode {}

export class TableCell extends AbstractBlock {
  text: string | undefined
  readonly column: TableColumn | undefined
  readonly colspan: number | undefined
  readonly rowspan: number | undefined
  readonly innerDocument: Document | undefined
  getText(): string | undefined
  setText(value: string): void
  getColumn(): TableColumn | undefined
  getColumnSpan(): number | undefined
  getRowSpan(): number | undefined
  getInnerDocument(): Document | undefined
}

export interface Catalog {
  refs: Record<string, AbstractNode>
  footnotes: Footnote[]
  images: ImageReference[]
  links: string[]
  [key: string]: unknown
}

export interface DoctitleOptions {
  partition?: boolean
  sanitize?: boolean
  use_fallback?: boolean
}

export class Document extends AbstractBlock {
  readonly doctype: string
  readonly backend: string
  readonly safe: number
  readonly baseDir: string
  readonly header: Section | undefined
  readonly footnotes: Footnote[]
  sourcemap: boolean
  readonly references: Catalog
  readonly catalog: Catalog
  readonly name: string | undefined
  readonly author: string | undefined
  readonly revdate: string | undefined
  nested(): boolean
  isNested(): boolean
  isEmbedded(): boolean
  isParsed(): boolean
  parse(): Deferred<this>
  counter(name: string, seed?: string | number | null): string | number
  resolveId(text: string): string | undefined
  hasFootnotes(): boolean
  hasExtensions(): boolean
  source(): string
  sourceLines(): string[]
  basebackend(base: string): boolean
  isBasebackend(base: string): boolean
  authors(): Author[]
  isNotitle(): boolean
  isNoheader(): boolean
  isNofooter(): boolean
  firstSection(): Section | undefined
  hasHeader(): boolean
  setAttribute(name: string, value?: unknown): boolean
  deleteAttribute(name: string): boolean
  isAttributeLocked(name: string): boolean
  attributeLocked(name: string): boolean
  setHeaderAttribute(name: string, value?: unknown, overwrite?: boolean): boolean
  convert(opts?: { standalone?: boolean; header_footer?: boolean }): Deferred<string>
  render(opts?: { standalone?: boolean; header_footer?: boolean }): Deferred<string>
  docinfo(location?: 'head' | 'header' | 'footer', suffix?: string | null): Deferred<string>
  getDocinfo(location?: 'head' | 'header' | 'footer', suffix?: string | null): Deferred<string>
  restoreAttributes(): void
  doctitle(opts?: DoctitleOptions): string | DocumentTitle | undefined
  getDoctitle(opts?: DoctitleOptions): string | DocumentTitle | undefined
  /** The extension registry of this document, if it uses extensions. */
  getExtensions(): Registry | undefined
  getDocumentTitle(opts?: DoctitleOptions): string | DocumentTitle | undefined
  getDoctype(): string
  getBackend(): string
  getSafe(): number
  getCompatMode(): boolean
  getSourcemap(): boolean
  setSourcemap(value: boolean): void
  getOutfilesuffix(): string
  getSource(): string
  getSourceLines(): string[]
  getFootnotes(): Footnote[]
  getCatalog(): Catalog
  getReferences(): Catalog
  getAuthor(): string | undefined
  getAuthors(): Author[]
  getBaseDir(): string
  getRevisionInfo(): RevisionInfo
  getRevisionDate(): string | undefined
  getRevdate(): string | undefined
  getRevisionNumber(): string | undefined
  getRevisionRemark(): string | undefined
  hasRevisionInfo(): boolean
  getNotitle(): boolean
  getNoheader(): boolean
  getNofooter(): boolean
  getHeader(): Section | null
  getParentDocument(): Document | undefined
  getRefs(): Record<string, AbstractNode>
  getImages(): ImageReference[]
  getLinks(): string[]
}

// ── Extensions ──────────────────────────────────────────────────────────────

/** A reader of source lines, handed to processors. */
export class Reader {
  /** A reader of `data` (a string or lines), positioned at `cursor`. */
  constructor(data?: string | string[] | null, cursor?: Cursor | null, opts?: unknown)
  readonly lines: string[]
  getLines(): string[]
  readLines(): string[]
  getString(): string
  read(): string
  readLine(): string | undefined
  peekLine(): string | undefined
  hasMoreLines(): boolean
  isEmpty(): boolean
  advance(): boolean
  skipBlankLines(): number | undefined
  unshiftLine(line: string): void
  restoreLine(line: string): void
  getSource(): string
  getSourceLines(): string[]
  getCursor(): Cursor
  getLineNumber(): number
  getFile(): string | undefined
  getPath(): string
  peekLines(num?: number | null, direct?: boolean): string[]
  isNextLineEmpty(): boolean
  empty(): boolean
  isEof(): boolean
  readLinesUntil(options?: ReadLinesUntilOptions, test?: (line: string) => boolean): string[]
  readLinesUntil(test: (line: string) => boolean): string[]
}

export interface ReadLinesUntilOptions {
  terminator?: string
  break_on_blank_lines?: boolean
  break_on_list_continuation?: boolean
  skip_first_line?: boolean
  preserve_last_line?: boolean
  read_last_line?: boolean
  skip_line_comments?: boolean
  skip_processing?: boolean
  context?: string
}

/** The reader that also resolves preprocessor directives and includes. */
export class PreprocessorReader extends Reader {
  /** A preprocessor reader of `data` for `document`, positioned at `cursor`. */
  constructor(document: Document, data?: string | string[] | null, cursor?: Cursor | null, opts?: unknown)
  pushInclude(
    data: string | string[],
    file?: string | null,
    path?: string | null,
    lineno?: number,
    attributes?: Record<string, string>
  ): this
}

/** The configuration of a processor (snake_case keys, as in Asciidoctor.js). */
export interface ProcessorConfig {
  name?: string
  contexts?: string[]
  content_model?: string
  positional_attrs?: string[]
  default_attrs?: Record<string, string>
  format?: 'short' | 'long'
  regexp?: string
  location?: 'head' | 'footer'
  preferred?: boolean
  [key: string]: unknown
}

export interface CreateInlineOptions {
  type?: string
  target?: string
  id?: string
  attributes?: Record<string, string>
}

/** The base class of processors: configuration and node factories. */
export class Processor {
  constructor(config?: ProcessorConfig)
  /** Adds the DSL methods (`named`, `onContext`, ...) to this class. */
  static useDsl(): void
  config: ProcessorConfig
  name: string | undefined
  /** Processes the input; subclasses implement it (the base throws). */
  process(...args: any[]): unknown
  option(key: string, value: unknown): void
  updateConfig(config: ProcessorConfig): void
  prefer(): void
  prepend(): void
  createBlock(parent: AbstractBlock, context: string, source: string | string[] | null, attrs?: Record<string, unknown>, opts?: { content_model?: string }): Block
  createParagraph(parent: AbstractBlock, source: string | string[], attrs?: Record<string, unknown>, opts?: { content_model?: string }): Block
  createOpenBlock(parent: AbstractBlock, source: string | string[] | null, attrs?: Record<string, unknown>, opts?: { content_model?: string }): Block
  createExampleBlock(parent: AbstractBlock, source: string | string[] | null, attrs?: Record<string, unknown>, opts?: { content_model?: string }): Block
  createPassBlock(parent: AbstractBlock, source: string | string[], attrs?: Record<string, unknown>, opts?: { content_model?: string }): Block
  createListingBlock(parent: AbstractBlock, source: string | string[], attrs?: Record<string, unknown>, opts?: { content_model?: string }): Block
  createLiteralBlock(parent: AbstractBlock, source: string | string[], attrs?: Record<string, unknown>, opts?: { content_model?: string }): Block
  createImageBlock(parent: AbstractBlock, attrs: Record<string, unknown>): Block
  createInline(parent: AbstractNode, context: string, text: string | null, opts?: CreateInlineOptions): Inline
  createAnchor(parent: AbstractNode, text: string | null, opts?: CreateInlineOptions): Inline
  createInlinePass(parent: AbstractNode, text: string, opts?: CreateInlineOptions): Inline
  createList(parent: AbstractBlock, context: string, attrs?: Record<string, unknown> | null): List
  createListItem(parent: List, text?: string | null): ListItem
  createSection(parent: AbstractBlock, title: string, attrs?: Record<string, unknown>, opts?: { level?: number; numbered?: boolean }): Section
  parseContent(parent: AbstractBlock, content: string | string[] | Reader, attributes?: Record<string, unknown> | null): AbstractBlock
}

export class Preprocessor extends Processor {}
export class TreeProcessor extends Processor {}
export class Postprocessor extends Processor {}
export class IncludeProcessor extends Processor {
  handles(doc: Document, target: string): boolean
}
export class DocinfoProcessor extends Processor {}
export class BlockProcessor extends Processor {
  constructor(name?: string, config?: ProcessorConfig)
  constructor(config?: ProcessorConfig)
}
export class MacroProcessor extends Processor {
  constructor(name?: string, config?: ProcessorConfig)
  constructor(config?: ProcessorConfig)
}
export class BlockMacroProcessor extends MacroProcessor {}
export class InlineMacroProcessor extends MacroProcessor {}

/** The DSL available as `this` inside a processor definition function. */
export interface ProcessorDsl<P extends Processor, F> extends Processor {
  named(name: string): void
  /** Sets the process function, or calls it when given other arguments. */
  process(fn: F): void
  process(...args: unknown[]): unknown
  option(key: string, value: unknown): void
}

export interface SyntaxProcessorDsl<P extends Processor, F> extends ProcessorDsl<P, F> {
  onContext(...contexts: Array<string | string[]>): void
  onContexts(...contexts: Array<string | string[]>): void
  boundTo(...contexts: Array<string | string[]>): void
  bindTo(...contexts: Array<string | string[]>): void
  contexts(...contexts: Array<string | string[]>): void
  contentModel(value: string): void
  parseContentAs(value: string): void
  positionalAttributes(...names: Array<string | string[]>): void
  positionalAttrs(...names: Array<string | string[]>): void
  namePositionalAttributes(...names: Array<string | string[]>): void
  nameAttributes(...names: Array<string | string[]>): void
  defaultAttributes(value: Record<string, string>): void
  defaultAttrs(value: Record<string, string>): void
  resolveAttributes(...specs: Array<string | string[] | Record<string, string> | boolean>): void
  resolvesAttributes(...specs: Array<string | string[] | Record<string, string> | boolean>): void
}

export interface MacroProcessorDsl<P extends Processor, F> extends SyntaxProcessorDsl<P, F> {
  matchFormat(value: 'short' | 'long'): void
  usingFormat(value: 'short' | 'long'): void
  format(value: 'short' | 'long'): void
  match(value: RegExp | string): void
}

export type PreprocessorFunction = (this: Preprocessor, doc: Document, reader: PreprocessorReader) => Reader | void
export type TreeProcessorFunction = (this: TreeProcessor, doc: Document) => Document | void
export type PostprocessorFunction = (this: Postprocessor, doc: Document, output: string) => string
export type IncludeProcessorFunction = (
  this: IncludeProcessor,
  doc: Document,
  reader: PreprocessorReader,
  target: string,
  attributes: Record<string, string>
) => void
export type DocinfoProcessorFunction = (this: DocinfoProcessor, doc: Document) => string | undefined | void
export type BlockProcessorFunction = (
  this: BlockProcessor,
  parent: AbstractBlock,
  reader: Reader,
  attributes: Record<string, string>
) => AbstractBlock | undefined | void
export type BlockMacroProcessorFunction = (
  this: BlockMacroProcessor,
  parent: AbstractBlock,
  target: string,
  attributes: Record<string, string>
) => AbstractBlock | undefined | void
export type InlineMacroProcessorFunction = (
  this: InlineMacroProcessor,
  parent: AbstractNode,
  target: string,
  attributes: Record<string, string>
) => Inline | string | undefined | void

export interface IncludeProcessorDsl extends ProcessorDsl<IncludeProcessor, IncludeProcessorFunction> {
  handles(fn: ((target: string) => boolean) | ((doc: Document, target: string) => boolean)): void
}

export interface DocinfoProcessorDsl extends ProcessorDsl<DocinfoProcessor, DocinfoProcessorFunction> {
  atLocation(value: 'head' | 'footer'): void
}

/** A processor registration: a DSL function, a processor class or an instance. */
export type Registration<P extends Processor, Dsl> =
  | ((this: Dsl, dsl: Dsl) => void)
  | (new () => P)
  | P

/** A registered processor. */
export class ProcessorExtension {
  protected constructor()
  readonly kind: string
  readonly instance: Processor
  readonly config: ProcessorConfig
  getKind(): string
  getInstance(): Processor
  getConfig(): ProcessorConfig
}

/** A set of extensions, activated for each document that uses it. */
export class Registry {
  protected constructor()
  readonly document: Document | undefined
  getDocument(): Document | undefined
  preprocessor(arg: Registration<Preprocessor, ProcessorDsl<Preprocessor, PreprocessorFunction>>): ProcessorExtension
  treeProcessor(arg: Registration<TreeProcessor, ProcessorDsl<TreeProcessor, TreeProcessorFunction>>): ProcessorExtension
  treeprocessor(arg: Registration<TreeProcessor, ProcessorDsl<TreeProcessor, TreeProcessorFunction>>): ProcessorExtension
  postprocessor(arg: Registration<Postprocessor, ProcessorDsl<Postprocessor, PostprocessorFunction>>): ProcessorExtension
  includeProcessor(arg: Registration<IncludeProcessor, IncludeProcessorDsl>): ProcessorExtension
  docinfoProcessor(arg: Registration<DocinfoProcessor, DocinfoProcessorDsl>): ProcessorExtension
  block(arg: Registration<BlockProcessor, SyntaxProcessorDsl<BlockProcessor, BlockProcessorFunction>>, name?: string): ProcessorExtension
  block(name: string, arg: Registration<BlockProcessor, SyntaxProcessorDsl<BlockProcessor, BlockProcessorFunction>>): ProcessorExtension
  blockMacro(arg: Registration<BlockMacroProcessor, MacroProcessorDsl<BlockMacroProcessor, BlockMacroProcessorFunction>>, name?: string): ProcessorExtension
  blockMacro(name: string, arg: Registration<BlockMacroProcessor, MacroProcessorDsl<BlockMacroProcessor, BlockMacroProcessorFunction>>): ProcessorExtension
  inlineMacro(arg: Registration<InlineMacroProcessor, MacroProcessorDsl<InlineMacroProcessor, InlineMacroProcessorFunction>>, name?: string): ProcessorExtension
  inlineMacro(name: string, arg: Registration<InlineMacroProcessor, MacroProcessorDsl<InlineMacroProcessor, InlineMacroProcessorFunction>>): ProcessorExtension
  getPreprocessors(): ProcessorExtension[]
  getTreeProcessors(): ProcessorExtension[]
  getPostprocessors(): ProcessorExtension[]
  getIncludeProcessors(): ProcessorExtension[]
  getDocinfoProcessors(location?: 'head' | 'footer' | null): ProcessorExtension[]
  getBlocks(): ProcessorExtension[]
  getBlockMacros(): ProcessorExtension[]
  getInlineMacros(): ProcessorExtension[]
  hasPreprocessors(): boolean
  hasTreeProcessors(): boolean
  hasPostprocessors(): boolean
  hasIncludeProcessors(): boolean
  hasDocinfoProcessors(location?: 'head' | 'footer' | null): boolean
  hasBlocks(): boolean
  hasBlockMacros(): boolean
  hasInlineMacros(): boolean
}

/** An extension group: a class whose `activate(registry)` registers processors. */
export class Group {
  static register(name?: string | null): string
  activate(registry: Registry): void
}

/** An extension group: a function called with the registry as `this`, or a group instance. */
export type GroupDefinition = ((this: Registry, registry: Registry) => void) | { activate(registry: Registry): void }

export const Extensions: {
  /** Registers a global extension group, applied to every document; returns its name. */
  register(group: GroupDefinition): string
  register(name: string | null, group: GroupDefinition): string
  unregister(...names: Array<string | string[]>): void
  unregisterAll(): void
  getGroups(): Record<string, true>
  /** A standalone registry, passed as the `extension_registry` option. */
  create(group?: GroupDefinition): Registry
  create(name: string | null, group?: GroupDefinition): Registry
  Group: typeof Group
  Processor: typeof Processor
  Preprocessor: typeof Preprocessor
  TreeProcessor: typeof TreeProcessor
  Postprocessor: typeof Postprocessor
  IncludeProcessor: typeof IncludeProcessor
  DocinfoProcessor: typeof DocinfoProcessor
  BlockProcessor: typeof BlockProcessor
  BlockMacroProcessor: typeof BlockMacroProcessor
  InlineMacroProcessor: typeof InlineMacroProcessor
}

// ── Converters ──────────────────────────────────────────────────────────────

export interface BackendTraits {
  basebackend: string
  filetype: string
  outfilesuffix: string
  htmlsyntax?: string
}

/** The traits of `backend`: base backend, file type, suffix and HTML syntax. */
export function deriveBackendTraits(backend: string, basebackend?: string | null): BackendTraits

/**
 * A converter: `convert` is called synchronously for each node and returns
 * the output (not a promise). Backend traits may be declared as
 * `backendTraits` or as properties.
 */
export interface Converter {
  convert(node: AbstractNode, transform?: string, opts?: unknown): string | undefined | null
  handles?(transform: string): boolean
  backendTraits?: Partial<BackendTraits>
  basebackend?: string
  filetype?: string
  outfilesuffix?: string
  htmlsyntax?: string
}

export type ConverterClass = new (backend: string, opts?: Record<string, unknown>) => Converter

/** The base class of converters: dispatches to `convert_<transform>` methods. */
export class ConverterBase implements Converter {
  static registerFor(...backends: Array<string | string[]>): void
  constructor(backend?: string, opts?: Record<string, unknown>)
  backend: string | undefined
  opts: Record<string, unknown>
  readonly logger: LoggerLike
  getLogger(): LoggerLike
  convert(node: AbstractNode, transform?: string | null, opts?: unknown): any
  handles(transform: string): boolean
  contentOnly(node: AbstractBlock): Deferred<string>
  skip(node: AbstractNode): void
  [method: `convert_${string}`]: ((node: any, opts?: unknown) => any) | undefined
}

declare class BuiltInConverter extends ConverterBase {
  backendTraits: BackendTraits
  /** The built-in output for `node`, ignoring the subclass's overrides. */
  convertBuiltIn(node: AbstractNode, transform?: string | null): string | undefined
}

/** The HTML 5 converter; subclass it and add `convert_<transform>` methods. */
export class Html5Converter extends BuiltInConverter {
  constructor(backend?: string, opts?: Record<string, unknown>)
}
/** The DocBook 5 converter. */
export class Docbook5Converter extends BuiltInConverter {
  constructor(backend?: string, opts?: Record<string, unknown>)
}
/** The man page converter. */
export class ManpageConverter extends BuiltInConverter {
  constructor(backend?: string, opts?: Record<string, unknown>)
}

/** A converter registry of its own (it does not register with the core). */
export class ConverterCustomFactory {
  constructor(seedRegistry?: Record<string, Converter | ConverterClass>)
  register(converter: Converter | ConverterClass, ...backends: Array<string | string[]>): void
  for(backend: string): Converter | ConverterClass | undefined
  createSync(backend: string, opts?: Record<string, unknown>): Converter | null
  create(backend: string, opts?: Record<string, unknown>): Promise<Converter | null>
  converters(): Record<string, Converter | ConverterClass>
  unregisterAll(): void
}

/** The type of the global converter factory. */
export class DefaultConverterFactory extends ConverterCustomFactory {
  protected constructor()
  getRegistry(): Record<string, Converter | ConverterClass>
  getDefault(): this
}

/** The global converter factory, shared with the core. */
export const ConverterFactory: DefaultConverterFactory
