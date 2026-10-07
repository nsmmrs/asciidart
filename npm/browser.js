// The browser entry point: without a file system, includes and file APIs
// behave as for missing files (see lib/src/io/js.dart); PDFs and EPUBs
// find the page's web fonts (see src/page_fonts.js).
import './asciidart.js'
import './src/page_fonts.js'

export * from './src/index.js'
