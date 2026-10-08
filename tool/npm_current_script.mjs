// Gives the compiled core a script to load its parts relative to.
//
// dart2js records the script it runs from (`document.currentScript`) to
// find the parts it loads on demand, and fails without one: there is none
// in Node.js, nor for an ES module in a browser. The npm package loads the
// parts itself (the `dartDeferredLibraryLoader` hook, by their names), so
// a stand-in script named after the bundle is enough.
//
// Usage: node tool/npm_current_script.mjs FILE   (rewrites FILE in place)
import { readFileSync, writeFileSync } from 'node:fs'

const file = process.argv[2]
const source = readFileSync(file, 'utf8')
// `(function(a){v.currentScript=a` (minified names vary).
const pattern = /\(function\((\w+)\)\{(\w+)\.currentScript=\1(?=[\n;])/
if (!pattern.test(source)) {
  console.error('npm_current_script: unexpected dart2js output (no currentScript)')
  process.exit(1)
}
const stand = '{src:"ptome.js",nonce:"",crossOrigin:null,getAttribute:function(){return null}}'
writeFileSync(
  file,
  source.replace(pattern, (_, arg, init) => `(function(${arg}){${init}.currentScript=${arg}||${stand}`),
)
console.log('npm_current_script: done')
