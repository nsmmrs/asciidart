#!/usr/bin/env node
// The asciidoctor-dart command: the Asciidoctor CLI on Node.js.
import process from 'node:process'
import '../asciidoctor-dart.js'

// A reader that exits early (`asciidoctor-dart ... | head`) closes stdout;
// stop quietly instead of failing.
process.stdout.on('error', (error) => {
  if (error.code === 'EPIPE') process.exit(process.exitCode ?? 0)
  throw error
})

process.exitCode = await globalThis.asciidoctorDart.runCli(process.argv.slice(2))
