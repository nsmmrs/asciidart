// Access to the compiled Dart core (`lib/src/js/bridge.dart`), installed as
// `globalThis.asciidoctorDart` when the bundle loads.

import { getContextLogger, Logger, LoggerManager } from './logging.js'

let loggingInstalled = false

/** The current logger: the one bound by withLogger, else the global one. */
function currentLogger() {
  return getContextLogger() ?? LoggerManager.getLogger()
}

/** A source location with the Asciidoctor.js shape. */
class Location {
  constructor({ file, dir, path, lineno }) {
    this.file = file ?? null
    this.dir = dir ?? null
    this.path = path ?? null
    this.lineno = lineno
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

  getLineNumber() {
    return this.lineno
  }

  toString() {
    return `${this.path}: line ${this.lineno}`
  }
}

/**
 * The bridge into the compiled core. On first use, routes the core's log
 * records to the facade's loggers.
 * @internal
 */
export function bridge() {
  const core = globalThis.asciidoctorDart
  if (!core) {
    throw new Error(
      'asciidart: the compiled core is not loaded; import the package ' +
        'entry point (asciidart) rather than its src/ modules'
    )
  }
  if (!loggingInstalled) {
    loggingInstalled = true
    core.setLogHandler(
      (severity, text, location) => {
        const message = Logger.AutoFormattingMessage.attach({
          text,
          ...(location ? { source_location: new Location(location) } : {}),
        })
        currentLogger().add(severity, message)
      },
      () => currentLogger().level ?? 2
    )
  }
  return core
}
