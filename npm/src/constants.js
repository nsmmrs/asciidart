// Constants of the Asciidoctor.js API.

/** The safe mode levels. */
export const SafeMode = {
  UNSAFE: 0,
  SAFE: 1,
  SERVER: 10,
  SECURE: 20,

  /** The level named `name` (case-insensitive), or undefined. */
  valueForName(name) {
    const value = SafeMode[String(name).toUpperCase()]
    return typeof value === 'number' ? value : undefined
  },

  getValueForName(name) {
    return this.valueForName(name)
  },

  /** The name of level `value`, or undefined. */
  nameForValue(value) {
    return { 0: 'unsafe', 1: 'safe', 10: 'server', 20: 'secure' }[value]
  },

  getNameForValue(value) {
    return this.nameForValue(value)
  },

  /** The names of the levels. */
  names() {
    return ['unsafe', 'safe', 'server', 'secure']
  },

  getNames() {
    return this.names()
  },
}

/** The content models of blocks. */
export const ContentModel = {
  COMPOUND: 'compound',
  SIMPLE: 'simple',
  VERBATIM: 'verbatim',
  RAW: 'raw',
  EMPTY: 'empty',
}
