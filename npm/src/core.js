// The compiled Dart core (`lib/src/js/entry.dart`), installed as
// `globalThis.asciidartCore` when the bundle loads, with the helpers it
// needs from JavaScript.

const core = globalThis.asciidartCore
if (!core) {
  throw new Error(
    'asciidart: the compiled core is not loaded; import the package entry ' +
      'point (asciidart) rather than its src/ modules'
  )
}

/** The error an error thrown by JavaScript code is carried in through Dart. */
const CARRIED = Symbol('asciidart.carried')

/** The error classes the core's exceptions become (set by api.g.js). */
export const errorClasses = Object.create(null)

/** The projected classes by name (set by api.g.js). */
const classes = Object.create(null)

/** The boxed Dart object behind each projected object. */
const boxes = new WeakMap()

/** Registers the classes Dart objects are projected as. */
export function registerClasses(map) {
  Object.assign(classes, map)
}

/** The elements of `values` that are instances of `type` (all without one). */
export function filterByClass(values, type) {
  return type === undefined ? values : values.filter((value) => value instanceof type)
}

// dart2js alters some JavaScript errors (TypeError, RangeError) when Dart
// code catches them, but leaves a plain Error alone: carry the original in
// one.
function carry(error) {
  if (error?.[CARRIED] !== undefined) return error
  const message = error instanceof Error ? error.message : String(error)
  return Object.assign(new Error(message), { [CARRIED]: error })
}

core.init({
  create(kind, box) {
    const object = Object.create(classes[kind].prototype)
    boxes.set(object, box)
    return object
  },
  boxOf(value) {
    return (typeof value === 'object' && value !== null && boxes.get(value)) || null
  },
  carried: CARRIED,
  asyncIterator: Symbol.asyncIterator,
  throwRaw(error) {
    throw error
  },
  invoke(f, args) {
    try {
      return f(...args)
    } catch (error) {
      throw carry(error)
    }
  },
  invokeMethod(target, name, args) {
    try {
      return target[name](...args)
    } catch (error) {
      throw carry(error)
    }
  },
  error(name, message) {
    const ErrorClass = errorClasses[name] ?? globalThis[name] ?? Error
    const error = new ErrorClass(message)
    if (ErrorClass === Error && name !== 'Error') error.name = name
    return error
  },
  carry,
})

export { core }
