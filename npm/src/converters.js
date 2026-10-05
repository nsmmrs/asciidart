// Converters with the Asciidoctor.js API: the converter factory, the
// ConverterBase class and the built-in converters. A JavaScript converter
// is handed to the compiled core as an adapter (`JsConverter` in
// `lib/src/js/bridge.dart`), which calls it synchronously for each node.

import { bridge } from './bridge.js'
import { getContextLogger, LoggerManager } from './logging.js'
import { fromCore, unwrap, wrap } from './nodes.js'

const TRAITS = ['basebackend', 'filetype', 'outfilesuffix', 'htmlsyntax']

/** The traits of `backend`: base backend, file type, suffix and HTML syntax. */
export function deriveBackendTraits(backend, basebackend = null) {
  return { ...bridge().deriveBackendTraits(String(backend), basebackend) }
}

/** The backend traits a converter declares, in any Asciidoctor.js style. */
function traitsOf(converter) {
  const declared =
    converter.backendTraits ??
    (typeof converter._getBackendTraits === 'function' ? converter._getBackendTraits() : null)
  const traits = {}
  for (const name of TRAITS) {
    const value = declared?.[name] ?? converter[name]
    if (typeof value === 'string') traits[name] = value
  }
  return traits
}

/**
 * The object the core calls for `converter`: node views are wrapped into
 * facade nodes and the result checked to be synchronous.
 * @internal
 */
export function adapt(converter) {
  const adapter = {
    ...traitsOf(converter),
    convert: fromCore((view, transform) => {
      const result = converter.convert(wrap(view), transform)
      if (result && typeof result.then === 'function') {
        throw new Error(
          'asciidart: a converter returned a promise; asynchronous converters are not supported'
        )
      }
      return result == null ? null : String(result)
    }),
  }
  if (typeof converter.handles === 'function') {
    adapter.handles = fromCore((transform) => Boolean(converter.handles(transform)))
  }
  return adapter
}

/** The base class of converters: dispatches to `convert_<transform>` methods. */
export class ConverterBase {
  /** Registers this class for `backends` with the global factory. */
  static registerFor(...backends) {
    ConverterFactory.register(this, ...backends)
  }

  constructor(backend = undefined, opts = {}) {
    this.backend = backend
    this.opts = opts ?? {}
  }

  get logger() {
    return getContextLogger() ?? LoggerManager.getLogger()
  }

  getLogger() {
    return this.logger
  }

  convert(node, transform = null, opts = null) {
    const name = transform ?? node.getNodeName()
    const method = this[`convert_${name}`]
    if (typeof method !== 'function') {
      throw new Error(`asciidart: no convert_${name} method in ${this.constructor.name}`)
    }
    return opts == null ? method.call(this, node) : method.call(this, node, opts)
  }

  handles(transform) {
    return typeof this[`convert_${transform}`] === 'function'
  }

  contentOnly(node) {
    return node.getContent()
  }

  skip(_node) {}
}

/** A built-in converter: subclass it and add `convert_<transform>` methods. */
class BuiltInConverter extends ConverterBase {
  convert(node, transform = null, opts = null) {
    const name = transform ?? node.getNodeName()
    if (typeof this[`convert_${name}`] === 'function') return super.convert(node, name, opts)
    return bridge().convertBuiltIn(this.$builtIn, unwrap(node), name) ?? undefined
  }

  handles(transform) {
    return super.handles(transform) || bridge().builtInHandles(this.$builtIn, String(transform))
  }

  /** The built-in output for `node`, ignoring this class's overrides. */
  convertBuiltIn(node, transform = null) {
    return bridge().convertBuiltIn(this.$builtIn, unwrap(node), transform ?? node.getNodeName())
  }
}

/** The HTML 5 converter. */
export class Html5Converter extends BuiltInConverter {
  constructor(backend = 'html5', opts = {}) {
    super(backend, opts)
    this.$builtIn = 'html5'
    this.backendTraits = deriveBackendTraits(backend, 'html')
  }
}

/** The DocBook 5 converter. */
export class Docbook5Converter extends BuiltInConverter {
  constructor(backend = 'docbook5', opts = {}) {
    super(backend, opts)
    this.$builtIn = 'docbook5'
    this.backendTraits = deriveBackendTraits(backend, 'docbook')
  }
}

/** The man page converter. */
export class ManpageConverter extends BuiltInConverter {
  constructor(backend = 'manpage', opts = {}) {
    super(backend, opts)
    this.$builtIn = 'manpage'
    this.backendTraits = deriveBackendTraits(backend, 'manpage')
  }
}

const BUILT_INS = { html5: Html5Converter, docbook5: Docbook5Converter, manpage: ManpageConverter }

const instantiate = (entry, backend, opts) =>
  typeof entry === 'function' ? new entry(backend, opts) : entry

/** A converter registry of its own (it does not register with the core). */
export class ConverterCustomFactory {
  constructor(seedRegistry = {}) {
    this.$registry = { ...seedRegistry }
  }

  register(converter, ...backends) {
    for (const backend of backends.flat()) this.$registry[String(backend)] = converter
  }

  for(backend) {
    return this.$registry[backend] ?? this.$registry['*']
  }

  createSync(backend, opts = {}) {
    const entry = this.for(backend)
    return entry == null ? null : instantiate(entry, backend, opts)
  }

  async create(backend, opts = {}) {
    return this.createSync(backend, opts)
  }

  converters() {
    return { ...this.$registry }
  }

  unregisterAll() {
    this.$registry = {}
  }
}

/** The global converter factory, shared with the core. */
class DefaultConverterFactory extends ConverterCustomFactory {
  /**
   * Registers `converter` (a class, created per document with `(backend,
   * opts)`, or an instance) for `backends`; `'*'` registers it for every
   * backend without a converter.
   */
  register(converter, ...backends) {
    const names = backends.flat().map(String)
    super.register(converter, ...names)
    bridge().registerConverter((backend) => adapt(instantiate(converter, backend, {})), names)
  }

  for(backend) {
    return super.for(backend) ?? BUILT_INS[backend]
  }

  getRegistry() {
    return { ...BUILT_INS, ...this.$registry }
  }

  getDefault() {
    return this
  }

  unregisterAll() {
    super.unregisterAll()
    bridge().unregisterConverters()
  }
}

export const ConverterFactory = new DefaultConverterFactory()

export { DefaultConverterFactory }
