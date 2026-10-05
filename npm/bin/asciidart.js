#!/usr/bin/env node
// The asciidart command on Node.js.
import process from 'node:process'
import '../asciidart.js'

// A reader that exits early (`asciidart ... | head`) closes stdout;
// stop quietly instead of failing.
process.stdout.on('error', (error) => {
  if (error.code === 'EPIPE') process.exit(process.exitCode ?? 0)
  throw error
})

process.exitCode = await globalThis.asciidartCore.runCli(process.argv.slice(2))
