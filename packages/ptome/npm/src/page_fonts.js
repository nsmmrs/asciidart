// The fonts a browser has that aren't in font folders, for PDFs and EPUBs
// (the `pageFonts` and `localFonts` options): the page's web fonts, the
// sources of its @font-face rules fetched again (usually from the
// browser's cache), and the visitor's installed fonts of the families
// asked for, through the Local Font Access API. Installed by the browser
// entry point.

import { core } from './core.js'

/** The font files fetched, by URL: promises of their bytes (or null). */
const fetched = new Map()

function fetchBytes(url) {
  if (!fetched.has(url)) {
    fetched.set(
      url,
      fetch(url)
        .then((response) => (response.ok ? response.arrayBuffer() : null))
        .then((buffer) => buffer && new Uint8Array(buffer))
        .catch(() => null)
    )
  }
  return fetched.get(url)
}

/** The @font-face rules of the page's style sheets: `{src, range, base}`. */
async function fontFaces() {
  const faces = []
  const seen = new Set()
  function addText(text, base) {
    for (const [, body] of text.matchAll(/@font-face\s*\{([^}]*)\}/g)) {
      const descriptor = (name) =>
        body.match(new RegExp(`(?:^|;)\\s*${name}\\s*:([^;]*)`, 'i'))?.[1].trim() ?? ''
      faces.push({ src: descriptor('src'), range: descriptor('unicode-range'), base })
    }
  }
  function addRules(rules, base) {
    for (const rule of rules) {
      if (rule.type === CSSRule.FONT_FACE_RULE) {
        faces.push({
          src: rule.style.getPropertyValue('src'),
          range: rule.style.getPropertyValue('unicode-range'),
          base,
        })
      } else if (rule.type === CSSRule.IMPORT_RULE) {
        if (rule.styleSheet) pending.push(addSheet(rule.styleSheet))
      } else if (rule.cssRules) {
        // @media, @supports, @layer and the like.
        addRules(rule.cssRules, base)
      }
    }
  }
  const pending = []
  async function addSheet(sheet) {
    if (seen.has(sheet)) return
    seen.add(sheet)
    const base = sheet.href || document.baseURI
    let rules = null
    try {
      rules = sheet.cssRules
    } catch {
      // A cross-origin sheet: its rules aren't readable, its text may be.
    }
    if (rules) {
      addRules(rules, base)
    } else if (sheet.href) {
      try {
        const response = await fetch(sheet.href)
        if (response.ok) addText(await response.text(), sheet.href)
      } catch {
        // Neither: its fonts are left out.
      }
    }
  }
  for (const sheet of [...document.styleSheets, ...(document.adoptedStyleSheets ?? [])]) {
    pending.push(addSheet(sheet))
  }
  while (pending.length > 0) await pending.shift()
  return faces
}

const FORMATS = new Set([
  'woff2',
  'woff',
  'truetype',
  'opentype',
  'woff2-variations',
  'woff-variations',
  'truetype-variations',
  'opentype-variations',
])

/** The URLs of the font files a `src` descriptor lists, `local()` left out. */
function sourceUrls(src, base) {
  const urls = []
  const pattern =
    /url\(\s*(?:"([^"]*)"|'([^']*)'|([^)\s]*))\s*\)(?:\s*format\(\s*["']?([\w-]+)["']?\s*\))?/g
  for (const match of src.matchAll(pattern)) {
    const format = match[4]?.toLowerCase()
    if (format && !FORMATS.has(format)) continue
    try {
      urls.push(new URL(match[1] ?? match[2] ?? match[3], base).href)
    } catch {
      // Not a URL.
    }
  }
  return urls
}

/** Whether a `unicode-range` (all of Unicode when empty) covers Latin "A". */
function coversLatin(range) {
  if (!range) return true
  return range.split(',').some((part) => {
    const match = part.trim().match(/^u\+([0-9a-f?]+)(?:-([0-9a-f]+))?$/i)
    if (!match) return false
    const low = parseInt(match[1].replace(/\?/g, '0'), 16)
    const high = parseInt(match[2] ?? match[1].replace(/\?/g, 'f'), 16)
    return low <= 0x41 && 0x41 <= high
  })
}

/**
 * The page's web fonts, as `{name, bytes}`: each @font-face rule's first
 * source that loads. Rules for the Latin range come first, so that a
 * family split into subsets by script (as Google Fonts' are) is found by
 * its Latin subset.
 */
export async function pageFonts() {
  const faces = (await fontFaces()).sort((a, b) => coversLatin(b.range) - coversLatin(a.range))
  const files = await Promise.all(
    faces.map(async ({ src, base }) => {
      for (const url of sourceUrls(src, base)) {
        const bytes = await fetchBytes(url)
        if (bytes) {
          const name = decodeURIComponent(new URL(url).pathname.split('/').pop() || 'font')
          return { name, bytes, url }
        }
      }
      return null
    })
  )
  const seen = new Set()
  return files.filter((file) => file && !seen.has(file.url) && seen.add(file.url))
}

/**
 * The visitor's installed fonts of `families`, as `{name, bytes}`, through
 * the Local Font Access API (none where it isn't available or allowed).
 */
export async function localFonts(families) {
  if (families.length === 0 || typeof globalThis.queryLocalFonts !== 'function') return []
  const wanted = new Set(families.map((family) => family.toLowerCase()))
  let fonts
  try {
    fonts = await globalThis.queryLocalFonts()
  } catch {
    return []
  }
  const files = []
  for (const font of fonts) {
    if (!wanted.has(font.family.toLowerCase())) continue
    try {
      const bytes = new Uint8Array(await (await font.blob()).arrayBuffer())
      files.push({ name: font.postscriptName, bytes })
    } catch {
      // Not readable: left out.
    }
  }
  return files
}

core.setFontSource(async (page, families) => [
  ...(page ? await pageFonts() : []),
  ...(await localFonts(families)),
])
