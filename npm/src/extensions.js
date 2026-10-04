// Extensions with the Asciidoctor.js API: registries, the processor
// classes and their DSL. A processor's configuration and process function
// are handed to the compiled core (`lib/src/js/extensions.dart`), which
// calls the function synchronously while it parses or converts.

import { bridge } from './bridge.js'
import { Cursor, fromCore, hold, unwrap, wrap } from './nodes.js'

const readers = new WeakMap()
const factories = () => bridge().factories

// Constructs facade objects around existing views.
const VIEW = Symbol('view')

/** A reader of source lines, handed to processors. */
export class Reader {
  /** A reader of `data` (a string or an array of lines), positioned at `cursor`. */
  constructor(data = null, cursor = null, opts = undefined) {
    if (data === VIEW) {
      hold(this, cursor)
      return
    }
    void opts
    hold(this, factories().createReader(source(data), cursor, null))
  }

  /** @internal */
  static wrap(view) {
    if (view == null) return undefined
    let reader = readers.get(view)
    if (!reader) {
      reader = view.isPreprocessor
        ? new PreprocessorReader(VIEW, view)
        : new Reader(VIEW, view)
      readers.set(view, reader)
    }
    return reader
  }

  getLines() {
    return Array.from(this.$bridge.getLines())
  }

  get lines() {
    return this.getLines()
  }

  readLines() {
    return Array.from(this.$bridge.readLines())
  }

  getString() {
    return this.getLines().join('\n')
  }

  read() {
    return this.readLines().join('\n')
  }

  readLine() {
    return this.$bridge.readLine() ?? undefined
  }

  peekLine() {
    return this.$bridge.peekLine() ?? undefined
  }

  hasMoreLines() {
    return this.$bridge.hasMoreLines()
  }

  isEmpty() {
    return this.$bridge.isEmpty()
  }

  advance() {
    return this.$bridge.advance()
  }

  skipBlankLines() {
    return this.$bridge.skipBlankLines() ?? undefined
  }

  unshiftLine(line) {
    this.$bridge.unshiftLine(String(line))
  }

  restoreLine(line) {
    this.unshiftLine(line)
  }

  getSource() {
    return this.$bridge.getSource()
  }

  getSourceLines() {
    return Array.from(this.$bridge.getSourceLines())
  }

  getCursor() {
    return new Cursor(this.$bridge.getCursor())
  }

  getLineNumber() {
    return this.$bridge.getLineNumber()
  }

  getFile() {
    return this.$bridge.getFile() ?? undefined
  }

  getPath() {
    return this.$bridge.getPath()
  }

  peekLines(num = null, direct = false) {
    return Array.from(this.$bridge.peekLines(num, Boolean(direct)))
  }

  isNextLineEmpty() {
    return this.$bridge.isNextLineEmpty()
  }

  empty() {
    return this.isEmpty()
  }

  isEof() {
    return this.isEmpty()
  }

  /**
   * Reads lines until `options.terminator` or another stop condition
   * (`break_on_blank_lines`, `break_on_list_continuation`, ...), or until
   * `test` accepts a line.
   */
  readLinesUntil(options = {}, test = undefined) {
    if (typeof options === 'function') [options, test] = [{}, options]
    const accept = test ? fromCore((line) => Boolean(test(line))) : null
    return Array.from(this.$bridge.readLinesUntil(options ?? {}, accept))
  }
}

const source = (data) =>
  Array.isArray(data) ? data.map(String) : data == null ? null : String(data)

/** The reader that also resolves preprocessor directives and includes. */
export class PreprocessorReader extends Reader {
  /** A preprocessor reader of `data` for `document`, positioned at `cursor`. */
  constructor(document, data = null, cursor = null, opts = undefined) {
    if (document === VIEW) {
      super(VIEW, data)
      return
    }
    void opts
    super(VIEW, factories().createReader(source(data), cursor, unwrap(document)))
  }

  pushInclude(data, file = null, path = null, lineno = 1, attributes = {}) {
    this.$bridge.pushInclude(
      Array.isArray(data) ? data.map(String) : String(data ?? ''),
      file,
      path,
      lineno,
      attributes ?? {}
    )
    return this
  }
}


/** The base class of processors: configuration and node factories. */
export class Processor {
  constructor(config = {}) {
    this.config = { ...config }
    this.name = config.name
  }

  /** Adds the DSL methods (`named`, `onContext`, ...) to this class. */
  static useDsl() {
    for (const [name, method] of Object.entries(DSL)) {
      if (!(name in this.prototype)) this.prototype[name] = method
    }
  }

  /** Processes the input; subclasses implement it. */
  process() {
    const kind = KINDS.find((Kind) => this instanceof Kind) ?? Processor
    throw new Error(
      `${kind.name} subclass ${this.constructor.name} must implement the process method`
    )
  }

  /** Sets a configuration option (snake_case, as in Asciidoctor.js). */
  option(key, value) {
    this.config[key] = value
  }

  updateConfig(config) {
    Object.assign(this.config, config)
  }

  prefer() {
    this.config.preferred = true
  }

  prepend() {
    this.prefer()
  }

  createBlock(parent, context, source, attrs = {}, opts = {}) {
    const lines = Array.isArray(source) ? source.map(String) : source ?? null
    return wrap(
      factories().createBlock(
        unwrap(parent),
        String(context),
        lines,
        attrs ?? {},
        opts.content_model ?? null
      )
    )
  }

  createParagraph(parent, source, attrs = {}, opts = {}) {
    return this.createBlock(parent, 'paragraph', source, attrs, opts)
  }

  createOpenBlock(parent, source, attrs = {}, opts = {}) {
    return this.createBlock(parent, 'open', source, attrs, opts)
  }

  createExampleBlock(parent, source, attrs = {}, opts = {}) {
    return this.createBlock(parent, 'example', source, attrs, opts)
  }

  createPassBlock(parent, source, attrs = {}, opts = {}) {
    return this.createBlock(parent, 'pass', source, attrs, opts)
  }

  createListingBlock(parent, source, attrs = {}, opts = {}) {
    return this.createBlock(parent, 'listing', source, attrs, opts)
  }

  createLiteralBlock(parent, source, attrs = {}, opts = {}) {
    return this.createBlock(parent, 'literal', source, attrs, opts)
  }

  createImageBlock(parent, attrs = {}) {
    return wrap(factories().createImageBlock(unwrap(parent), attrs ?? {}))
  }

  createInline(parent, context, text, opts = {}) {
    return wrap(
      factories().createInline(
        unwrap(parent),
        String(context),
        text == null ? null : String(text),
        opts.type ?? null,
        opts.target ?? null,
        opts.id ?? null,
        opts.attributes ?? null
      )
    )
  }

  createAnchor(parent, text, opts = {}) {
    return this.createInline(parent, 'anchor', text, opts)
  }

  createInlinePass(parent, text, opts = {}) {
    return this.createInline(parent, 'quoted', text, opts)
  }

  createList(parent, context, attrs = null) {
    return wrap(factories().createList(unwrap(parent), String(context), attrs))
  }

  createListItem(parent, text = null) {
    return wrap(
      factories().createListItem(unwrap(parent), text == null ? null : String(text))
    )
  }

  createSection(parent, title, attrs = {}, opts = {}) {
    return wrap(
      factories().createSection(
        unwrap(parent),
        String(title),
        attrs ?? {},
        opts.level ?? null,
        opts.numbered ?? null
      )
    )
  }

  parseContent(parent, content, attributes = null) {
    const source =
      content instanceof Reader
        ? content.$bridge
        : Array.isArray(content)
          ? content.map(String)
          : String(content ?? '')
    return wrap(factories().parseContent(unwrap(parent), source, attributes))
  }
}

/** Processes the source lines before parsing. */
export class Preprocessor extends Processor {}

/** Processes the parsed document before conversion. */
export class TreeProcessor extends Processor {}

/** Processes the converted output. */
export class Postprocessor extends Processor {}

/** Supplies the content of include directives. */
export class IncludeProcessor extends Processor {
  handles(_doc, _target) {
    return true
  }
}

/** Adds content to the head or footer of a standalone document. */
export class DocinfoProcessor extends Processor {
  constructor(config = {}) {
    super({ location: 'head', ...config })
  }
}

/** Processes a named block. */
export class BlockProcessor extends Processor {
  constructor(name = undefined, config = {}) {
    if (name && typeof name === 'object') [name, config] = [undefined, name]
    super({ contexts: ['open', 'paragraph'], content_model: 'compound', ...config })
    if (name != null) this.name = name
  }
}

/** The base class of macro processors. */
export class MacroProcessor extends Processor {
  constructor(name = undefined, config = {}) {
    if (name && typeof name === 'object') [name, config] = [undefined, name]
    super({ content_model: 'attributes', ...config })
    if (name != null) this.name = name
  }
}

/** Processes a named block macro (`name::target[attrs]`). */
export class BlockMacroProcessor extends MacroProcessor {}

/** Processes a named inline macro (`name:target[attrs]`). */
export class InlineMacroProcessor extends MacroProcessor {}

// The processor kinds, most specific first.
const KINDS = []

const flat = (values) => values.flat().map(String)

KINDS.push(
  BlockMacroProcessor,
  InlineMacroProcessor,
  Preprocessor,
  TreeProcessor,
  Postprocessor,
  IncludeProcessor,
  DocinfoProcessor,
  BlockProcessor,
  MacroProcessor
)

/** The DSL methods processors configured with a function call on `this`. */
const DSL = {
  named(value) {
    this.name = String(value)
  },
  /** Sets the process function, or calls it (when given other arguments). */
  process(...args) {
    if (args.length === 1 && typeof args[0] === 'function') {
      this.$process = args[0]
      return undefined
    }
    return this.$process?.apply(this, args)
  },
  onContext(...contexts) {
    this.config.contexts = flat(contexts)
  },
  onContexts(...contexts) {
    this.config.contexts = flat(contexts)
  },
  boundTo(...contexts) {
    this.config.contexts = flat(contexts)
  },
  bindTo(...contexts) {
    this.config.contexts = flat(contexts)
  },
  contexts(...contexts) {
    this.config.contexts = flat(contexts)
  },
  contentModel(value) {
    this.config.content_model = String(value)
  },
  parseContentAs(value) {
    this.config.content_model = String(value)
  },
  positionalAttributes(...names) {
    this.config.positional_attrs = flat(names)
  },
  positionalAttrs(...names) {
    this.config.positional_attrs = flat(names)
  },
  namePositionalAttributes(...names) {
    this.config.positional_attrs = flat(names)
  },
  nameAttributes(...names) {
    this.config.positional_attrs = flat(names)
  },
  defaultAttributes(value) {
    this.config.default_attrs = { ...value }
  },
  defaultAttrs(value) {
    this.config.default_attrs = { ...value }
  },
  resolveAttributes(...args) {
    if (args.length === 1 && args[0] === false) {
      this.config.content_model = 'text'
      return
    }
    const specs = args.flat()
    const names = []
    const defaults = {}
    for (const spec of specs) {
      if (typeof spec === 'object' && spec !== null) {
        Object.assign(defaults, spec)
        continue
      }
      let [name, value] = String(spec).split('=')
      if (name.includes(':')) name = name.slice(name.indexOf(':') + 1)
      names.push(name)
      if (value !== undefined) defaults[name] = value
    }
    this.config.content_model = 'attributes'
    this.config.positional_attrs = names
    this.config.default_attrs = defaults
  },
  resolvesAttributes(...args) {
    DSL.resolveAttributes.apply(this, args)
  },
  matchFormat(value) {
    this.config.format = String(value)
  },
  usingFormat(value) {
    this.config.format = String(value)
  },
  format(value) {
    this.config.format = String(value)
  },
  match(value) {
    this.config.regexp = value instanceof RegExp ? value.source : String(value)
  },
  atLocation(value) {
    this.config.location = String(value)
  },
  handles(fn) {
    this.$handles = fn
  },
}

function dsl(processor) {
  for (const [name, method] of Object.entries(DSL)) {
    if (!(name in processor) || name === 'handles' || name === 'process') {
      processor[name] = method
    }
  }
  return processor
}

/**
 * The processor for a registration argument: a DSL function (called with
 * the processor as `this`), a processor class, or a processor instance.
 */
function resolve(Kind, arg, name) {
  let processor
  if (typeof arg === 'function' && !(arg.prototype instanceof Processor)) {
    processor = dsl(new Kind())
    arg.call(processor, processor)
  } else if (typeof arg === 'function') {
    processor = new arg()
  } else if (arg instanceof Processor || (arg && typeof arg === 'object')) {
    processor = arg
  } else {
    throw new TypeError(`asciidoctor-dart: invalid ${Kind.name} registration`)
  }
  if (name != null) processor.name = String(name)
  const process =
    processor.$process ??
    (typeof processor.process === 'function' && processor.process !== DSL.process
      ? processor.process
      : undefined)
  if (!process) {
    throw new Error(`asciidoctor-dart: no process function for the ${Kind.name}`)
  }
  return { processor, process }
}

/** A registered processor. */
export class ProcessorExtension {
  constructor(kind, processor) {
    this.kind = kind
    this.instance = processor
    this.config = processor.config
  }

  getKind() {
    return this.kind
  }

  getInstance() {
    return this.instance
  }

  getConfig() {
    return this.config
  }
}

const registries = new WeakMap()

/** A set of extensions, activated for each document that uses it. */
export class Registry {
  constructor(view) {
    hold(this, view)
    Object.defineProperty(this, '$extensions', { value: [] })
  }

  /** @internal */
  static wrap(view) {
    let registry = registries.get(view)
    if (!registry) {
      registry = new Registry(view)
      registries.set(view, registry)
    }
    return registry
  }

  get document() {
    return wrap(this.$bridge.getDocument())
  }

  getDocument() {
    return this.document
  }

  #add(kind, processor) {
    const extension = new ProcessorExtension(kind, processor)
    // The document the registry was activated for: a registry used again
    // for another document starts over, as in Asciidoctor.
    Object.defineProperty(extension, '$document', { value: this.$bridge.getDocument() ?? null })
    this.$extensions.push(extension)
    return extension
  }

  preprocessor(arg) {
    const { processor, process } = resolve(Preprocessor, arg)
    const run = fromCore((doc, reader) =>
      unwrapReader(process.call(processor, wrap(doc), Reader.wrap(reader)))
    )
    this.$bridge.addPreprocessor(processor.config, run)
    return this.#add('preprocessor', processor)
  }

  treeProcessor(arg) {
    const { processor, process } = resolve(TreeProcessor, arg)
    const run = fromCore((doc) => unwrap(process.call(processor, wrap(doc))))
    this.$bridge.addTreeProcessor(processor.config, run)
    return this.#add('tree_processor', processor)
  }

  treeprocessor(arg) {
    return this.treeProcessor(arg)
  }

  postprocessor(arg) {
    const { processor, process } = resolve(Postprocessor, arg)
    const run = fromCore((doc, output) => process.call(processor, wrap(doc), output))
    this.$bridge.addPostprocessor(processor.config, run)
    return this.#add('postprocessor', processor)
  }

  includeProcessor(arg) {
    const { processor, process } = resolve(IncludeProcessor, arg)
    const handles =
      processor.$handles ??
      (typeof processor.handles === 'function' && processor.handles !== DSL.handles
        ? processor.handles
        : null)
    const run = fromCore((doc, reader, target, attrs) =>
      process.call(processor, wrap(doc), Reader.wrap(reader), target, attrs)
    )
    const accepts =
      handles &&
      fromCore((target) =>
        handles.length >= 2
          ? handles.call(processor, this.document, target)
          : handles.call(processor, target)
      )
    this.$bridge.addIncludeProcessor(processor.config, run, accepts || null)
    return this.#add('include_processor', processor)
  }

  docinfoProcessor(arg) {
    const { processor, process } = resolve(DocinfoProcessor, arg)
    const run = fromCore((doc) => process.call(processor, wrap(doc)))
    this.$bridge.addDocinfoProcessor({ location: 'head', ...processor.config }, run)
    return this.#add('docinfo_processor', processor)
  }

  block(arg, name = undefined) {
    if (typeof arg === 'string') [arg, name] = [name, arg]
    const { processor, process } = resolve(BlockProcessor, arg, name)
    const config = {
      contexts: ['open', 'paragraph'],
      content_model: 'compound',
      ...processor.config,
    }
    const run = fromCore((parent, reader, attrs) =>
      unwrap(process.call(processor, wrap(parent), Reader.wrap(reader), attrs))
    )
    this.$bridge.addBlock(String(processor.name), config, run)
    return this.#add('block', processor)
  }

  blockMacro(arg, name = undefined) {
    if (typeof arg === 'string') [arg, name] = [name, arg]
    const { processor, process } = resolve(BlockMacroProcessor, arg, name)
    const config = { content_model: 'attributes', ...processor.config }
    const run = fromCore((parent, target, attrs) =>
      unwrap(process.call(processor, wrap(parent), target, attrs))
    )
    this.$bridge.addBlockMacro(String(processor.name), config, run)
    return this.#add('block_macro', processor)
  }

  inlineMacro(arg, name = undefined) {
    if (typeof arg === 'string') [arg, name] = [name, arg]
    const { processor, process } = resolve(InlineMacroProcessor, arg, name)
    const config = { content_model: 'attributes', ...processor.config }
    const run = fromCore((parent, target, attrs) =>
      unwrap(process.call(processor, wrap(parent), target, attrs))
    )
    this.$bridge.addInlineMacro(String(processor.name), config, run)
    return this.#add('inline_macro', processor)
  }

  #of(kind) {
    const document = this.$bridge.getDocument() ?? null
    return this.$extensions.filter(
      (extension) =>
        extension.kind === kind &&
        (extension.$document === null || extension.$document === document)
    )
  }

  getPreprocessors() {
    return this.#of('preprocessor')
  }

  getTreeProcessors() {
    return this.#of('tree_processor')
  }

  getPostprocessors() {
    return this.#of('postprocessor')
  }

  getIncludeProcessors() {
    return this.#of('include_processor')
  }

  getDocinfoProcessors(location = null) {
    return this.#of('docinfo_processor').filter(
      (extension) => location == null || (extension.config.location ?? 'head') === location
    )
  }

  getBlocks() {
    return this.#of('block')
  }

  getBlockMacros() {
    return this.#of('block_macro')
  }

  getInlineMacros() {
    return this.#of('inline_macro')
  }

  hasPreprocessors() {
    return this.getPreprocessors().length > 0
  }

  hasTreeProcessors() {
    return this.getTreeProcessors().length > 0
  }

  hasPostprocessors() {
    return this.getPostprocessors().length > 0
  }

  hasIncludeProcessors() {
    return this.getIncludeProcessors().length > 0
  }

  hasDocinfoProcessors(location = null) {
    return this.getDocinfoProcessors(location).length > 0
  }

  hasBlocks() {
    return this.getBlocks().length > 0
  }

  hasBlockMacros() {
    return this.getBlockMacros().length > 0
  }

  hasInlineMacros() {
    return this.getInlineMacros().length > 0
  }
}

function unwrapReader(reader) {
  return reader instanceof Reader ? reader.$bridge : null
}

function asBuild(fn) {
  if (typeof fn === 'function') {
    return fromCore((view) => {
      const registry = Registry.wrap(view)
      fn.call(registry, registry)
    })
  }
  if (fn && typeof fn.activate === 'function') {
    return fromCore((view) => fn.activate(Registry.wrap(view)))
  }
  throw new TypeError('asciidoctor-dart: an extension group must be a function')
}

/** An extension group: a class whose `activate(registry)` registers processors. */
export class Group {
  static register(name = null) {
    return Extensions.register(name, new this())
  }

  activate(_registry) {}
}

/** The global extension groups and standalone registries. */
export const Extensions = {
  /** Registers a global extension group, applied to every document. */
  register(name, group = undefined) {
    if (group === undefined) [name, group] = [null, name]
    return bridge().registerExtensionGroup(name == null ? null : String(name), asBuild(group))
  },

  /** Unregisters the global extension groups named `names`. */
  unregister(...names) {
    bridge().unregisterExtensions(flat(names))
  },

  /** Unregisters every global extension group. */
  unregisterAll() {
    bridge().unregisterExtensions(null)
  },

  /** The names of the global extension groups. */
  getGroups() {
    return Object.fromEntries(
      Array.from(bridge().extensionGroupNames(), (name) => [name, true])
    )
  },

  /** A standalone registry, passed as the `extension_registry` option. */
  create(name = null, group = undefined) {
    if (typeof name === 'function') [name, group] = [null, name]
    return Registry.wrap(
      bridge().createRegistry(
        name == null ? null : String(name),
        group === undefined ? null : asBuild(group)
      )
    )
  },

  Group,
  Processor,
  Preprocessor,
  TreeProcessor,
  Postprocessor,
  IncludeProcessor,
  DocinfoProcessor,
  BlockProcessor,
  BlockMacroProcessor,
  InlineMacroProcessor,
}
