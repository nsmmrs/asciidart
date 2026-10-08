// Runs a dart2js program with deferred parts on Node.js (CI's node_check):
// `self` is the global object, a script element stands in for the program,
// and each part is read from the program's folder when dart2js asks for it.
globalThis.self = globalThis
// dart2js finds where the parts are from the running script.
globalThis.document = { currentScript: { src: `file://${__filename}` } }
self.dartDeferredLibraryLoader = (uri, success, error) => {
  try {
    const fs = require('node:fs')
    const path = require('node:path')
    const vm = require('node:vm')
    const file = path.resolve(__dirname, path.basename(uri))
    vm.runInThisContext(fs.readFileSync(file, 'utf8'), { filename: file })
    success()
  } catch (e) {
    error(e)
  }
}
