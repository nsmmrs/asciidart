// The top-level functions of the Asciidoctor.js API.

import { bridge } from './bridge.js'
import { wrap } from './nodes.js'

/** The version of this package. */
export function getVersion() {
  return bridge().version
}

/** The version of Asciidoctor whose behavior this package matches. */
export function getCoreVersion() {
  return bridge().coreVersion
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
  return wrap(await bridge().load(input(source), options ?? {}))
}

/**
 * Parses the AsciiDoc file `filename` into a Document.
 * @returns {Promise<import('./nodes.js').Document>}
 */
export async function loadFile(filename, options = {}) {
  return wrap(await bridge().loadFile(String(filename), options ?? {}))
}

/**
 * Converts AsciiDoc source to the output, or to the Document when the
 * output is written to a file (`to_file` or `to_dir`).
 * @returns {Promise<string|import('./nodes.js').Document>}
 */
export async function convert(source, options = {}) {
  const result = await bridge().convert(input(source), options ?? {})
  return typeof result === 'string' ? result : wrap(result)
}

/**
 * Converts the AsciiDoc file `filename`, writing the output next to it (or
 * to `to_file`/`to_dir`) and returning the Document; with `to_file: false`,
 * returns the output instead.
 * @returns {Promise<string|import('./nodes.js').Document>}
 */
export async function convertFile(filename, options = {}) {
  const result = await bridge().convertFile(String(filename), options ?? {})
  return typeof result === 'string' ? result : wrap(result)
}
