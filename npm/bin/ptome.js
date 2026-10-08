#!/usr/bin/env node
// The ptome command on Node.js.
import process from 'node:process'
import '../ptome.js'

// A reader that exits early (`ptome ... | head`) closes stdout;
// stop quietly instead of failing.
process.stdout.on('error', (error) => {
  if (error.code === 'EPIPE') process.exit(process.exitCode ?? 0)
  throw error
})

process.exitCode = await globalThis.ptomeCore.runCli(process.argv.slice(2))
