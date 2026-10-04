// The top-level functions of the Asciidoctor.js API.

import { bridge } from './bridge.js'
import { adapt } from './converters.js'
import { uncarry, wrap } from './nodes.js'

/** The version of this package. */
export function getVersion() {
  return bridge().version
}

/** The version of Asciidoctor whose behavior this package matches. */
export function getCoreVersion() {
  return bridge().coreVersion
}

/**
 * The options handed to the core: a `converter` class or instance becomes
 * the adapter the core calls.
 */
function settings(options) {
  if (options == null) return {}
  const converter = options.converter
  if (converter == null) return options
  const instance =
    typeof converter === 'function' ? new converter(options.backend ?? 'html5', {}) : converter
  return { ...options, converter: adapt(instance) }
}

/** The result of the core's `promise`, with errors of JavaScript code uncarried. */
async function core(promise) {
  try {
    return await promise
  } catch (error) {
    throw uncarry(error)
  }
}

function input(source) {
  if (source == null) return null
  if (typeof source === 'string' || Array.isArray(source)) return source
  if (source instanceof Uint8Array) return source
  return String(source)
}

/**
 * Parses AsciiDoc source (a string, an array of lines, or a Buffer) into a
 * Document.
 * @returns {Promise<import('./nodes.js').Document>}
 */
export async function load(source, options = {}) {
  return wrap(await core(bridge().load(input(source), settings(options))))
}

/**
 * Parses the AsciiDoc file `filename` into a Document.
 * @returns {Promise<import('./nodes.js').Document>}
 */
export async function loadFile(filename, options = {}) {
  return wrap(await core(bridge().loadFile(String(filename), settings(options))))
}

/**
 * Converts AsciiDoc source to the output, or to the Document when the
 * output is written to a file (`to_file` or `to_dir`).
 * @returns {Promise<string|import('./nodes.js').Document>}
 */
export async function convert(source, options = {}) {
  const result = await core(bridge().convert(input(source), settings(options)))
  return typeof result === 'string' ? result : wrap(result)
}

/**
 * Converts the AsciiDoc file `filename`, writing the output next to it (or
 * to `to_file`/`to_dir`) and returning the Document; with `to_file: false`,
 * returns the output instead.
 * @returns {Promise<string|import('./nodes.js').Document>}
 */
export async function convertFile(filename, options = {}) {
  const result = await core(bridge().convertFile(String(filename), settings(options)))
  return typeof result === 'string' ? result : wrap(result)
}
