// The document model of the facade: JavaScript classes around the views of
// the Dart nodes (`lib/src/js/nodes.dart`), with the Asciidoctor.js method
// and property names.

import { bridge } from './bridge.js'
import { Registry } from './extensions.js'
import { getContextLogger, LoggerManager } from './logging.js'

// One facade object per Dart node.
const wrappers = new WeakMap()

/**
 * Returns the facade object for a node view of the Dart core (the same object
 * every time), or undefined for null/undefined.
 * @internal
 */
export function wrap(view) {
  if (view == null) return undefined
  let node = wrappers.get(view)
  if (!node) {
    const NodeClass = classes[view.kind] ?? Block
    node = new NodeClass(view)
    wrappers.set(view, node)
  }
  return node
}

/**
 * Returns the node view behind a facade object (or the view itself).
 * @internal
 */
export function unwrap(node) {
  return node?.$bridge ?? node ?? null
}

// The depth of calls from the core into JavaScript (converters and
// extensions), which run synchronously.
let coreCallbacks = 0

/**
 * Returns `fn` marked as called by the core: while it runs, the node methods
 * that return promises return their values directly.
 * @internal
 */
export function fromCore(fn) {
  return function (...args) {
    coreCallbacks++
    try {
      return fn.apply(this, args)
    } catch (error) {
      throw carrier(error)
    } finally {
      coreCallbacks--
    }
  }
}

// The property of the error that carries one thrown by JavaScript code
// through the core: dart2js turns some errors (TypeError, RangeError) into
// its own when the core catches them, but leaves a plain Error alone.
const CARRIED = Symbol.for('asciidart.carried')

function carrier(error) {
  if (error?.[CARRIED] !== undefined) return error
  const message = error instanceof Error ? error.message : String(error)
  return Object.assign(new Error(message), { [CARRIED]: error })
}

/**
 * The error thrown by JavaScript code that `error` carries through the
 * core, else `error` itself.
 * @internal
 */
export function uncarry(error) {
  return error?.[CARRIED] ?? error
}

/**
 * The result of `body`: a promise, except during a call from the core,
 * which cannot wait for one.
 */
function settle(body) {
  if (coreCallbacks > 0) return body()
  try {
    return Promise.resolve(body())
  } catch (error) {
    return Promise.reject(uncarry(error))
  }
}

/**
 * Stores the core's view of a facade object. The property is hidden from
 * enumeration, so that util.inspect and deep equality do not walk the
 * compiled core's heap behind it.
 * @internal
 */
export function hold(target, view) {
  Object.defineProperty(target, '$bridge', { value: view })
}

const inspect = Symbol.for('nodejs.util.inspect.custom')

const wrapAll = (views) => Array.from(views ?? [], wrap)
const orUndefined = (value) => (value === null ? undefined : value)
const str = (value) => (value == null ? null : String(value))

/** A position in a source file. */
export class Cursor {
  constructor(file, dir = null, path = null, lineno = 1) {
    if (file && typeof file === 'object' && 'lineno' in file) {
      ;({ file, dir, path, lineno } = file)
    }
    this.file = file ?? null
    this.dir = dir ?? null
    this.path = path ?? null
    this.lineno = lineno
  }

  advance(num) {
    this.lineno += num
  }

  get lineInfo() {
    return `${this.path}: line ${this.lineno}`
  }

  toString() {
    return this.lineInfo
  }

  getLineNumber() {
    return this.lineno
  }

  getFile() {
    return this.file ?? undefined
  }

  getDirectory() {
    return this.dir ?? undefined
  }

  getPath() {
    return this.path ?? undefined
  }

  getLineInfo() {
    return this.lineInfo
  }
}

/** A document title, split into a main title and a subtitle. */
export class DocumentTitle {
  constructor(val, opts = {}) {
    if (val && typeof val === 'object') {
      this.main = val.main
      this.subtitle = val.subtitle ?? undefined
      this.combined = val.combined
      this._sanitized = val.sanitized
      return
    }
    const separator = opts.separator ?? ':'
    let text = String(val)
    this._sanitized = Boolean(opts.sanitize)
    if (this._sanitized && text.includes('<')) {
      text = text.replace(/<[^>]+>/g, '').replace(/ +/g, ' ').trim()
    }
    const sep = `${separator} `
    const idx = separator ? text.lastIndexOf(sep) : -1
    this.main = idx < 0 ? text : text.slice(0, idx)
    this.subtitle = idx < 0 ? undefined : text.slice(idx + sep.length)
    this.combined = text
  }

  get title() {
    return this.main
  }

  isSanitized() {
    return this._sanitized
  }

  hasSubtitle() {
    return this.subtitle != null
  }

  getMain() {
    return this.main
  }

  getCombined() {
    return this.combined
  }

  getSubtitle() {
    return this.subtitle
  }

  toString() {
    return this.combined
  }
}

/** A document author. */
export class Author {
  constructor(name, firstname, middlename, lastname, initials, email) {
    this.name = name ?? undefined
    this.firstname = firstname ?? undefined
    this.middlename = middlename ?? undefined
    this.lastname = lastname ?? undefined
    this.initials = initials ?? undefined
    this.email = email ?? undefined
  }

  getName() {
    return this.name
  }

  getFirstName() {
    return this.firstname
  }

  getMiddleName() {
    return this.middlename
  }

  getLastName() {
    return this.lastname
  }

  getInitials() {
    return this.initials
  }

  getEmail() {
    return this.email
  }
}

/** The revision information of a document. */
export class RevisionInfo {
  constructor(number, date, remark) {
    this.number = number ?? undefined
    this.date = date ?? undefined
    this.remark = remark ?? undefined
  }

  isEmpty() {
    return this.number == null && this.date == null && this.remark == null
  }

  getNumber() {
    return this.number
  }

  getDate() {
    return this.date
  }

  getRemark() {
    return this.remark
  }
}

/** A footnote registered in the document catalog. */
export class Footnote {
  constructor(index, id, text) {
    this.index = index
    this.id = id ?? undefined
    this.text = text
  }

  getIndex() {
    return Number(this.index)
  }

  getId() {
    return this.id
  }

  getText() {
    return this.text
  }
}

/** An image registered in the document catalog. */
export class ImageReference {
  constructor(target, imagesdir) {
    this.target = target
    this.imagesdir = imagesdir ?? undefined
  }

  getTarget() {
    return this.target
  }

  getImagesDirectory() {
    return this.imagesdir
  }

  toString() {
    return this.target
  }
}

/** The base class of all nodes. */
export class AbstractNode {
  constructor(view) {
    hold(this, view)
  }

  [inspect]() {
    const id = this.$bridge.getId()
    return `${this.constructor.name} <${this.context}${id ? `#${id}` : ''}>`
  }

  get context() {
    return this.$bridge.getContext()
  }

  get nodeName() {
    return this.$bridge.getNodeName()
  }

  get id() {
    return orUndefined(this.$bridge.getId())
  }

  set id(value) {
    this.$bridge.setId(str(value))
  }

  get parent() {
    return wrap(this.$bridge.getParent())
  }

  get document() {
    return wrap(this.$bridge.getDocument())
  }

  get attributes() {
    return this.$bridge.getAttributes()
  }

  get role() {
    return orUndefined(this.$bridge.getRole())
  }

  set role(value) {
    this.setRole(value)
  }

  get roles() {
    return Array.from(this.$bridge.getRoles())
  }

  get reftext() {
    return this.$bridge.getReftext()
  }

  getContext() {
    return this.context
  }

  getNodeName() {
    return this.nodeName
  }

  getId() {
    return this.id
  }

  setId(id) {
    this.id = id
  }

  getParent() {
    return this.parent
  }

  setParent() {
    throw new Error('asciidart: setParent is not supported')
  }

  getDocument() {
    return this.document
  }

  isBlock() {
    return this.$bridge.isBlock()
  }

  isInline() {
    return this.$bridge.isInline()
  }

  getAttribute(name, defaultValue = undefined, fallbackName = undefined) {
    const fallback =
      fallbackName === true ? name : fallbackName ? String(fallbackName) : null
    const value = this.$bridge.getAttribute(String(name), null, fallback)
    return value ?? defaultValue
  }

  getAttributes() {
    return this.attributes
  }

  hasAttribute(name, expectedValue = undefined, fallbackName = undefined) {
    const fallback =
      fallbackName === true ? name : fallbackName ? String(fallbackName) : null
    return this.$bridge.hasAttribute(
      String(name),
      expectedValue == null ? null : String(expectedValue),
      fallback
    )
  }

  isAttribute(name, expectedValue = undefined, fallbackName = undefined) {
    return this.hasAttribute(name, expectedValue, fallbackName)
  }

  setAttribute(name, value = '', overwrite = true) {
    return this.$bridge.setAttribute(String(name), str(value), overwrite)
  }

  removeAttribute(name) {
    return orUndefined(this.$bridge.removeAttribute(String(name)))
  }

  hasOption(name) {
    return this.$bridge.hasOption(String(name))
  }

  isOption(name) {
    return this.hasOption(name)
  }

  setOption(name) {
    this.$bridge.setOption(String(name))
  }

  enabledOptions() {
    return new Set(this.$bridge.getOptions())
  }

  getOptions() {
    return Object.fromEntries(
      Array.from(this.$bridge.getOptions(), (name) => [name, ''])
    )
  }

  getRole() {
    return this.role
  }

  setRole(...names) {
    const value = names.flat().join(' ')
    this.$bridge.setRole(value)
    return value
  }

  getRoles() {
    return this.roles
  }

  hasRole(name) {
    return this.$bridge.hasRole(String(name))
  }

  hasRoleAttribute(expectedValue = null) {
    return this.$bridge.hasRole(expectedValue == null ? null : String(expectedValue))
  }

  addRole(name) {
    return this.$bridge.addRole(String(name))
  }

  removeRole(name) {
    return this.$bridge.removeRole(String(name))
  }

  /**
   * Applies `subs` to `text` (a string or an array of lines): the normal
   * substitutions by default, none for `null`, or the names in an array or
   * a comma-separated spec.
   */
  applySubs(text, subs = undefined) {
    const source = Array.isArray(text) ? text.map(String) : String(text ?? '')
    const names = Array.isArray(subs) ? subs.map(String) : subs == null ? null : String(subs)
    return this.$bridge.applySubs(source, names, subs === undefined)
  }

  applyNormalSubs(text) {
    return this.applySubs(text)
  }

  applyHeaderSubs(text) {
    return this.$bridge.substitute('header', String(text))
  }

  applyTitleSubs(text) {
    return this.$bridge.substitute('title', String(text))
  }

  applyReftextSubs(text) {
    return this.$bridge.substitute('reftext', String(text))
  }

  subSpecialchars(text) {
    return this.$bridge.substitute('specialcharacters', String(text))
  }

  subSpecialcharacters(text) {
    return this.subSpecialchars(text)
  }

  subQuotes(text) {
    return this.$bridge.substitute('quotes', String(text))
  }

  subAttributes(text) {
    return this.$bridge.substitute('attributes', String(text))
  }

  subReplacements(text) {
    return this.$bridge.substitute('replacements', String(text))
  }

  subMacros(text) {
    return this.$bridge.substitute('macros', String(text))
  }

  subPostReplacements(text) {
    return this.$bridge.substitute('post_replacements', String(text))
  }

  subCallouts(text) {
    return this.$bridge.substitute('callouts', String(text))
  }

  /** The substitutions the spec `subs` resolves to for `type`, or undefined. */
  resolveSubs(subs, type = 'block', defaults = null, subject = null) {
    const names = this.$bridge.resolveSubs(str(subs), String(type), defaults, str(subject))
    return names == null ? undefined : Array.from(names)
  }

  resolveBlockSubs(subs, defaults = null, subject = null) {
    return this.resolveSubs(subs, 'block', defaults, subject)
  }

  resolvePassSubs(subs) {
    return this.resolveSubs(subs, 'inline', null, 'passthrough macro')
  }

  expandSubs(subs, subject = null) {
    if (Array.isArray(subs)) return subs.map(String)
    return subs === 'none' ? undefined : this.resolveSubs(subs, 'inline', null, subject)
  }

  getReftext() {
    return orUndefined(this.reftext)
  }

  hasReftext() {
    return this.$bridge.hasReftext()
  }

  isReftext() {
    return this.hasReftext()
  }

  precomputeReftext() {
    return settle(() => undefined)
  }

  iconUri(name) {
    return settle(() => this.$bridge.getIconUri(String(name)))
  }

  getIconUri(name) {
    return this.iconUri(name)
  }

  imageUri(targetImage, assetDirKey = 'imagesdir') {
    return settle(() => this.$bridge.getImageUri(String(targetImage), assetDirKey))
  }

  getImageUri(targetImage, assetDirKey = 'imagesdir') {
    return this.imageUri(targetImage, assetDirKey)
  }

  mediaUri(target, assetDirKey = 'imagesdir') {
    return this.$bridge.getMediaUri(String(target), assetDirKey)
  }

  getMediaUri(target, assetDirKey = 'imagesdir') {
    return this.mediaUri(target, assetDirKey)
  }

  normalizeWebPath(target, start = null, preserveUriTarget = true) {
    return this.$bridge.normalizeWebPath(String(target), str(start), preserveUriTarget)
  }

  normalizeSystemPath(target, start = null, jail = null) {
    return this.$bridge.normalizeSystemPath(String(target), str(start), str(jail))
  }

  readAsset(path, opts = {}) {
    return settle(() => this.$bridge.readAsset(String(path), Boolean(opts.warn_on_failure)) ?? null)
  }

  isUri(value) {
    return /^[a-zA-Z][a-zA-Z0-9.+-]+:\/\//.test(String(value))
  }

  get logger() {
    return getContextLogger() ?? LoggerManager.getLogger()
  }

  getLogger() {
    return this.logger
  }

  toString() {
    return `${this.constructor.name}(context: ${this.context})`
  }
}

/** The base class of block-level nodes. */
export class AbstractBlock extends AbstractNode {
  get blocks() {
    return wrapAll(this.$bridge.getBlocks())
  }

  get title() {
    return this.$bridge.getTitle()
  }

  set title(value) {
    this.$bridge.setTitle(str(value))
  }

  get caption() {
    return this.$bridge.getCaption()
  }

  set caption(value) {
    this.$bridge.setCaption(str(value))
  }

  get style() {
    return this.$bridge.getStyle()
  }

  set style(value) {
    this.$bridge.setStyle(str(value))
  }

  get level() {
    return this.$bridge.getLevel()
  }

  set level(value) {
    this.$bridge.setLevel(value)
  }

  get contentModel() {
    return this.$bridge.getContentModel()
  }

  set contentModel(value) {
    this.$bridge.setContentModel(String(value))
  }

  get sourceLocation() {
    const location = this.$bridge.getSourceLocation()
    return location ? new Cursor(location) : undefined
  }

  get file() {
    return this.$bridge.getFile()
  }

  get lineno() {
    return this.$bridge.getLineNumber()
  }

  get numeral() {
    return orUndefined(this.$bridge.getNumeral())
  }

  set numeral(value) {
    this.$bridge.setNumeral(str(value))
  }

  get number() {
    const numeral = this.numeral
    return numeral != null && /^\d+$/.test(numeral) ? Number(numeral) : numeral
  }

  get subs() {
    return Array.from(this.$bridge.getSubstitutions())
  }

  precomputeTitle() {
    return settle(() => undefined)
  }

  commitSubs() {
    this.$bridge.commitSubs()
  }

  hasTitle() {
    return this.$bridge.hasTitle()
  }

  convert() {
    return settle(() => this.$bridge.convert() ?? '')
  }

  render() {
    return settle(() => this.convert())
  }

  content() {
    return settle(() => this.$bridge.getContent())
  }

  getContent() {
    return settle(() => this.content())
  }

  append(block) {
    this.$bridge.append(unwrap(block))
    return this
  }

  hasBlocks() {
    return this.$bridge.hasBlocks()
  }

  hasSections() {
    return this.$bridge.hasSections()
  }

  sections() {
    return wrapAll(this.$bridge.getSections())
  }

  alt() {
    return this.$bridge.getAlt() ?? ''
  }

  getAlt() {
    return this.alt()
  }

  captionedTitle() {
    return this.$bridge.getCaptionedTitle()
  }

  hasSub(name) {
    return this.$bridge.hasSubstitution(String(name))
  }

  removeSub(name) {
    this.$bridge.removeSubstitution(String(name))
  }

  xreftext(xrefstyle = null) {
    return settle(() => this.$bridge.getXrefText(str(xrefstyle)))
  }

  assignCaption(value = null, captionContext = undefined) {
    this.$bridge.assignCaption(str(value), str(captionContext))
  }

  nextAdjacentBlock() {
    return wrap(this.$bridge.getNextAdjacentBlock()) ?? null
  }

  /**
   * Finds the blocks matching the selector (`context`, `style`, `role`,
   * `id`, `traverse_documents`), passed in turn to the optional filter.
   */
  findBy(selector = {}, filter = undefined) {
    if (typeof selector === 'function') {
      filter = selector
      selector = {}
    }
    return wrapAll(
      this.$bridge.findBy(
        str(selector.context),
        str(selector.style),
        str(selector.role),
        str(selector.id),
        Boolean(selector.traverse_documents),
        filter ? (view) => filter(wrap(view)) : null
      )
    )
  }

  query(selector, filter) {
    return this.findBy(selector, filter)
  }

  getContentModel() {
    return this.contentModel
  }

  setContentModel(value) {
    this.contentModel = value
  }

  getBlocks() {
    return this.blocks
  }

  getSections() {
    return this.sections()
  }

  getTitle() {
    return this.title
  }

  setTitle(value) {
    this.title = value
  }

  getCaption() {
    return orUndefined(this.caption)
  }

  setCaption(value) {
    this.caption = value
  }

  getCaptionedTitle() {
    return this.captionedTitle()
  }

  getStyle() {
    return this.style
  }

  setStyle(value) {
    this.style = value
  }

  getLevel() {
    return this.level
  }

  setLevel(value) {
    this.level = value
  }

  getFile() {
    return orUndefined(this.file)
  }

  getLineNumber() {
    return orUndefined(this.lineno)
  }

  getXrefText(xrefstyle = null) {
    return this.xreftext(xrefstyle)
  }

  getSourceLocation() {
    return this.sourceLocation
  }

  getSubstitutions() {
    return this.subs
  }

  hasSubstitution(name) {
    return this.hasSub(name)
  }

  addSubstitution(name) {
    this.$bridge.addSubstitution(String(name))
  }

  removeSubstitution(name) {
    this.removeSub(name)
  }

  getNumeral() {
    return this.numeral
  }

  setNumeral(value) {
    this.numeral = value
  }
}

/** A block: a paragraph, listing, image, admonition, and so on. */
export class Block extends AbstractBlock {
  /**
   * Creates a block: `opts.source` (a string or lines), `opts.attributes`
   * and `opts.content_model`.
   */
  static create(parent, context, opts = {}) {
    const source = opts.source ?? opts.lines ?? null
    return wrap(
      bridge().factories.createBlock(
        unwrap(parent),
        String(context),
        Array.isArray(source) ? source.map(String) : source,
        opts.attributes ?? {},
        opts.content_model ?? null
      )
    )
  }

  get blockname() {
    return this.context
  }

  get source() {
    return this.$bridge.getSource()
  }

  get lines() {
    return Array.from(this.$bridge.getSourceLines())
  }

  set lines(value) {
    this.$bridge.setLines(Array.from(value, String))
  }

  getSource() {
    return this.source
  }

  getSourceLines() {
    return this.lines
  }

  getBlockName() {
    return this.blockname
  }
}

/** A section. */
export class Section extends AbstractBlock {
  get index() {
    return this.$bridge.getIndex()
  }

  get sectname() {
    return this.$bridge.getSectionName()
  }

  set sectname(value) {
    this.$bridge.setSectionName(str(value))
  }

  get special() {
    return this.$bridge.isSpecial()
  }

  get numbered() {
    return this.$bridge.isNumbered()
  }

  get name() {
    return this.title
  }

  sectnum(delimiter = '.', append = null) {
    return this.$bridge.sectnum(delimiter, append === false ? '' : str(append))
  }

  getIndex() {
    return this.index
  }

  getSectionName() {
    return this.sectname
  }

  setSectionName(value) {
    this.sectname = value
  }

  isSpecial() {
    return this.special
  }

  isNumbered() {
    return this.numbered
  }

  getName() {
    return this.name
  }

  getSectionNumeral() {
    return this.numeral
  }

  getSectionNumber() {
    return this.numeral
  }
}

/** An inline node: a quoted span, link, anchor, image, and so on. */
export class Inline extends AbstractNode {
  get text() {
    return this.$bridge.getText()
  }

  set text(value) {
    this.$bridge.setText(str(value))
  }

  get type() {
    return this.$bridge.getType()
  }

  get target() {
    return this.$bridge.getTarget()
  }

  convert() {
    return settle(() => this.$bridge.convert() ?? '')
  }

  render() {
    return settle(() => this.convert())
  }

  alt() {
    return this.$bridge.getAlt() ?? ''
  }

  xreftext(xrefstyle = null) {
    return settle(() => this.$bridge.getXrefText(str(xrefstyle)))
  }

  getText() {
    return orUndefined(this.text)
  }

  setText(value) {
    this.text = value
  }

  getType() {
    return orUndefined(this.type)
  }

  getTarget() {
    return orUndefined(this.target)
  }

  getAlt() {
    return this.alt()
  }

  getXrefText(xrefstyle = null) {
    return this.xreftext(xrefstyle)
  }
}

/** A list: unordered, ordered, description or callout. */
export class List extends AbstractBlock {
  get items() {
    return Array.from(this.$bridge.getItems(), (item) =>
      Array.isArray(item) ? [wrapAll(item[0]), wrap(item[1])] : wrap(item)
    )
  }

  hasItems() {
    return this.$bridge.hasItems()
  }

  getItems() {
    return this.items
  }

  outline() {
    return this.$bridge.isOutline()
  }

  isOutline() {
    return this.outline()
  }

  /** The items, as in Asciidoctor (a list has no converted content). */
  content() {
    return settle(() => this.items)
  }
}

/** An item of a list. */
export class ListItem extends AbstractBlock {
  get text() {
    return this.$bridge.getText()
  }

  set text(value) {
    this.$bridge.setText(str(value))
  }

  get marker() {
    return orUndefined(this.$bridge.getMarker())
  }

  set marker(value) {
    this.$bridge.setMarker(str(value))
  }

  get list() {
    return this.parent
  }

  simple() {
    return this.$bridge.isSimple()
  }

  isSimple() {
    return this.simple()
  }

  compound() {
    return this.$bridge.isCompound()
  }

  isCompound() {
    return this.compound()
  }

  hasText() {
    return this.$bridge.hasText()
  }

  getText() {
    return orUndefined(this.text)
  }

  setText(value) {
    this.text = value
  }

  getMarker() {
    return this.marker
  }

  setMarker(value) {
    this.marker = value
  }

  getList() {
    return this.list
  }
}

/** A table. */
export class Table extends AbstractBlock {
  get rows() {
    const rows = this.$bridge.getRows()
    const section = (list) => Array.from(list ?? [], (row) => wrapAll(row))
    return { head: section(rows.head), body: section(rows.body), foot: section(rows.foot) }
  }

  get columns() {
    return wrapAll(this.$bridge.getColumns())
  }

  getRows() {
    return this.rows
  }

  getColumns() {
    return this.columns
  }

  getHeadRows() {
    return this.rows.head
  }

  getBodyRows() {
    return this.rows.body
  }

  getFootRows() {
    return this.rows.foot
  }

  hasHeadRows() {
    return this.rows.head.length > 0
  }

  hasBodyRows() {
    return this.rows.body.length > 0
  }

  hasFootRows() {
    return this.rows.foot.length > 0
  }
}

/** A column of a table. */
export class TableColumn extends AbstractNode {}

/** A cell of a table. */
export class TableCell extends AbstractBlock {
  get text() {
    return this.$bridge.getText()
  }

  set text(value) {
    this.$bridge.setText(str(value))
  }

  get column() {
    return wrap(this.$bridge.getColumn())
  }

  get colspan() {
    return orUndefined(this.$bridge.getColumnSpan())
  }

  get rowspan() {
    return orUndefined(this.$bridge.getRowSpan())
  }

  get innerDocument() {
    return wrap(this.$bridge.getInnerDocument())
  }

  getText() {
    return this.text
  }

  setText(value) {
    this.text = value
  }

  getColumn() {
    return this.column
  }

  getColumnSpan() {
    return this.colspan
  }

  getRowSpan() {
    return this.rowspan
  }

  getInnerDocument() {
    return this.innerDocument
  }
}

Table.Column = TableColumn
Table.Cell = TableCell

/** The root of a parsed document. */
export class Document extends AbstractBlock {
  get doctype() {
    return this.$bridge.getDoctype()
  }

  get backend() {
    return this.$bridge.getBackend()
  }

  get safe() {
    return this.$bridge.getSafe()
  }

  get baseDir() {
    return this.$bridge.getBaseDir()
  }

  get header() {
    return wrap(this.$bridge.getHeader())
  }

  get footnotes() {
    return Array.from(
      this.$bridge.getFootnotes(),
      (f) => new Footnote(f.index, f.id, f.text)
    )
  }

  get sourcemap() {
    return this.$bridge.getSourcemap()
  }

  set sourcemap(value) {
    this.$bridge.setSourcemap(Boolean(value))
  }

  get references() {
    return this.getCatalog()
  }

  get catalog() {
    return this.getCatalog()
  }

  get name() {
    return this.getDoctitle()
  }

  get author() {
    return this.$bridge.getAuthor()
  }

  get revdate() {
    return this.$bridge.getRevisionDate()
  }

  get title() {
    return this.$bridge.getTitle()
  }

  set title(value) {
    this.setAttribute('title', value)
  }

  nested() {
    return this.$bridge.isNested()
  }

  isNested() {
    return this.nested()
  }

  isEmbedded() {
    return this.$bridge.isEmbedded()
  }

  isParsed() {
    return this.$bridge.isParsed()
  }

  parse() {
    return settle(() => {
      this.$bridge.parse()
      return this
    })
  }

  counter(name, seed = null) {
    return this.$bridge.counter(String(name), seed == null ? null : String(seed))
  }

  resolveId(text) {
    return this.$bridge.resolveId(String(text))
  }

  hasFootnotes() {
    return this.$bridge.hasFootnotes()
  }

  hasExtensions() {
    return this.$bridge.hasExtensions()
  }

  source() {
    return this.$bridge.getSource()
  }

  sourceLines() {
    return Array.from(this.$bridge.getSourceLines())
  }

  basebackend(base) {
    return this.$bridge.isBasebackend(String(base))
  }

  isBasebackend(base) {
    return this.basebackend(base)
  }

  authors() {
    return Array.from(
      this.$bridge.getAuthors(),
      (a) =>
        new Author(a.name, a.firstname, a.middlename, a.lastname, a.initials, a.email)
    )
  }

  isNotitle() {
    return this.$bridge.getNotitle()
  }

  isNoheader() {
    return this.$bridge.getNoheader()
  }

  isNofooter() {
    return this.$bridge.getNofooter()
  }

  firstSection() {
    return wrap(this.$bridge.getFirstSection())
  }

  hasHeader() {
    return this.$bridge.hasHeader()
  }

  setAttribute(name, value = '') {
    return this.$bridge.setDocumentAttribute(String(name), str(value))
  }

  deleteAttribute(name) {
    return this.$bridge.deleteAttribute(String(name))
  }

  removeAttribute(name) {
    const value = this.getAttribute(name)
    this.deleteAttribute(name)
    return value
  }

  isAttributeLocked(name) {
    return this.$bridge.isAttributeLocked(String(name))
  }

  attributeLocked(name) {
    return this.isAttributeLocked(name)
  }

  setHeaderAttribute(name, value = '', overwrite = true) {
    return this.$bridge.setHeaderAttribute(String(name), str(value), overwrite)
  }

  /** Converts the document; `standalone` (or `header_footer`) overrides the load option. */
  convert(opts = {}) {
    return settle(() => {
      const standalone = opts.standalone ?? opts.header_footer
      return this.$bridge.convertDocument(standalone ?? null)
    })
  }

  render(opts = {}) {
    return settle(() => this.convert(opts))
  }

  docinfo(location = 'head', suffix = null) {
    return settle(() => this.$bridge.getDocinfo(location, suffix))
  }

  getDocinfo(location = 'head', suffix = null) {
    return this.docinfo(location, suffix)
  }

  restoreAttributes() {
    this.$bridge.restoreAttributes()
  }

  /** Returns the document title; with `partition`, a DocumentTitle. */
  getDoctitle(opts = {}) {
    const title = this.$bridge.getDoctitle(
      Boolean(opts.partition),
      Boolean(opts.sanitize),
      Boolean(opts.use_fallback)
    )
    if (title == null) return undefined
    return opts.partition ? new DocumentTitle(title) : title
  }

  doctitle(opts = {}) {
    return this.getDoctitle(opts)
  }

  /** The extension registry of this document, if it uses extensions. */
  getExtensions() {
    const view = this.$bridge.getExtensions()
    return view == null ? undefined : Registry.wrap(view)
  }

  getDocumentTitle(opts = {}) {
    return this.getDoctitle(opts)
  }

  getDoctype() {
    return this.doctype
  }

  getBackend() {
    return this.backend
  }

  getSafe() {
    return this.safe
  }

  getCompatMode() {
    return this.$bridge.getCompatMode()
  }

  getSourcemap() {
    return this.sourcemap
  }

  setSourcemap(value) {
    this.sourcemap = value
  }

  getOutfilesuffix() {
    return this.$bridge.getOutfilesuffix()
  }

  getSource() {
    return this.source()
  }

  getSourceLines() {
    return this.sourceLines()
  }

  getFootnotes() {
    return this.footnotes
  }

  getCatalog() {
    const refs = this.getRefs()
    return {
      refs,
      footnotes: this.footnotes,
      images: this.getImages(),
      links: this.getLinks(),
      includes: Object.fromEntries(
        Array.from(this.$bridge.getIncludes(), (name) => [name, true])
      ),
    }
  }

  getReferences() {
    return this.getCatalog()
  }

  getAuthor() {
    return orUndefined(this.author)
  }

  getAuthors() {
    return this.authors()
  }

  getBaseDir() {
    return this.baseDir
  }

  getRevisionInfo() {
    return new RevisionInfo(
      this.$bridge.getRevisionNumber(),
      this.$bridge.getRevisionDate(),
      this.$bridge.getRevisionRemark()
    )
  }

  getRevisionDate() {
    return orUndefined(this.$bridge.getRevisionDate())
  }

  getRevdate() {
    return this.getRevisionDate()
  }

  getRevisionNumber() {
    return orUndefined(this.$bridge.getRevisionNumber())
  }

  getRevisionRemark() {
    return orUndefined(this.$bridge.getRevisionRemark())
  }

  hasRevisionInfo() {
    return !this.getRevisionInfo().isEmpty()
  }

  getNotitle() {
    return this.isNotitle()
  }

  getNoheader() {
    return this.isNoheader()
  }

  getNofooter() {
    return this.isNofooter()
  }

  getHeader() {
    return this.header ?? null
  }

  getParentDocument() {
    return wrap(this.$bridge.getParentDocument())
  }

  getRefs() {
    const refs = this.$bridge.getRefs()
    return Object.fromEntries(Object.entries(refs).map(([id, view]) => [id, wrap(view)]))
  }

  getImages() {
    return Array.from(
      this.$bridge.getImages(),
      (image) => new ImageReference(image.target, image.imagesdir)
    )
  }

  getLinks() {
    return Array.from(this.$bridge.getLinks())
  }
}

const classes = {
  document: Document,
  section: Section,
  block: Block,
  inline: Inline,
  list: List,
  list_item: ListItem,
  table: Table,
  table_cell: TableCell,
  table_column: TableColumn,
}
