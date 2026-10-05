// Makes the compiled core survive bundlers (esbuild, Rollup, webpack).
//
// dart2js finds an object's runtime type through its constructor's `name`
// (and marks interfaces with `"$i" + name`), while bundlers may rename
// functions to avoid clashes with other names in a bundle (esbuild turns
// `A` into `A2`). This inserts, before dart2js sets up its classes, a step
// that gives every function on the program's holder objects back the name
// of its holder key when a bundler renamed it (the key itself, being a
// property name, is never renamed).
//
// Usage: node tool/npm_pin_names.mjs FILE   (rewrites FILE in place)
import { readFileSync, writeFileSync } from 'node:fs'

const file = process.argv[2]
const source = readFileSync(file, 'utf8')
// `var w=[A,J,B]` (minified) or `var holders = [A, J, B];`.
const holders = /var \w+ ?= ?(\[[A-Z, ]+\])/.exec(source)
const inheritance = /\(function inheritance\(\) ?\{/.exec(source)
const at = inheritance ? inheritance.index : -1
if (!holders || at < 0) {
  console.error('npm_pin_names: unexpected dart2js output (no holders or inheritance)')
  process.exit(1)
}
const pin =
  `;(function pinNames(){for(var h of ${holders[1]})for(var k of Object.keys(h)){` +
  'var f=h[k];if(typeof f=="function"&&f.name!==k&&f.name.startsWith(k)&&' +
  '/^[0-9]+$/.test(f.name.slice(k.length)))' +
  'Object.defineProperty(f,"name",{value:k,configurable:true})}})()'
writeFileSync(file, `${source.slice(0, at)}${pin};${source.slice(at)}`)
console.log(`npm_pin_names: holders ${holders[1]}`)
