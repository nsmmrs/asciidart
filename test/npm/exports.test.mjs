// The type declarations describe exactly the package's runtime exports.

import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { test } from 'node:test'

import * as api from 'asciidoctor-dart'

const require = createRequire(import.meta.url)

/** The value exports named by a declaration file (types and interfaces aside). */
function declaredValues(file) {
  const source = readFileSync(file, 'utf8')
  const names = new Set()
  for (const [, name] of source.matchAll(/^export (?:declare )?(?:class|function|const|namespace) (\w+)/gm)) {
    names.add(name)
  }
  for (const [, list] of source.matchAll(/^export \{([^}]*)\} from '[^']+'/gm)) {
    for (const entry of list.split(',').map((name) => name.trim())) {
      if (entry && !entry.startsWith('type ')) names.add(entry)
    }
  }
  return names
}

test('every runtime export is declared, and every declared value exported', () => {
  const types = require.resolve('asciidoctor-dart/package.json').replace('package.json', 'types/index.d.ts')
  const declared = declaredValues(types)
  const runtime = new Set(Object.keys(api))
  assert.deepEqual([...runtime].filter((name) => !declared.has(name)).sort(), [])
  assert.deepEqual([...declared].filter((name) => !runtime.has(name)).sort(), [])
})
