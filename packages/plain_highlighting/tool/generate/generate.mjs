// Generates lib/src/languages/*.g.dart from highlight.js.
//
// Each upstream language definition is run against the real highlight.js
// (the version pinned in package.json), and the raw mode graph it returns is
// written out as a grammar (data that lib/src/grammar.dart reads back into
// the same graph): every object becomes one `Mode` (shared objects stay
// shared, frozen ones stay frozen), its keys in their order, and the
// handful of JavaScript callbacks map to their Dart ports in
// lib/src/callbacks.dart by source text. Anything the generator does not
// know (a key, a value shape, a callback) fails the run, naming the
// language and the path.
//
// A grammar is bytes: a table of the strings it uses, the language's
// metadata, then each mode's keys and values (unsigned LEB128 numbers,
// strings by their index in the table; see grammar.dart for the layout).
// The grammars of all languages are one Brotli stream (they share much),
// in base64 in all.g.dart, decoded the first time a language is used; each
// language is read from where its grammar starts.
//
// Usage: node tool/generate/generate.mjs   (from the repository root)
import { createRequire } from 'node:module';
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { brotliCompressSync, brotliDecompressSync, constants as zlib } from 'node:zlib';

const require = createRequire(import.meta.url);
const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const hljsDir = dirname(require.resolve('highlight.js/package.json'));
const hljs = require('highlight.js/lib/core');
const version = require('highlight.js/package.json').version;

// The registration order of lib/index.js decides auto-detection ties.
const order = [...readFileSync(join(hljsDir, 'lib/index.js'), 'utf8')
  .matchAll(/registerLanguage\('([^']+)', require\('\.\/languages\/([^']+)'\)\)/g)]
  .map((m) => ({ name: m[1], file: m[2] }));

// The callbacks of lib/src/callbacks.dart, in the order grammar.dart lists
// them (a grammar names one by its index).
const callbackNames = [
  'shebangOnBegin', 'endSameAsBeginOnBegin', 'endSameAsBeginOnEnd',
  'phpHeredocOnBegin', 'phpHeredocOnEnd', 'mathematicaSystemSymbol',
  'gcodeLetterBoundary', 'javascriptIsTrulyOpeningTag',
];

// Callbacks by normalized source text -> their index.
const callbacks = new Map();
function addCallback(fn, name) {
  const index = callbackNames.indexOf(name);
  if (index < 0) throw new Error(`unknown callback ${name}`);
  callbacks.set(normalize(fn.toString()), index);
}
function normalize(source) { return source.replace(/\s+/g, ' ').trim(); }

addCallback(hljs.SHEBANG()['on:begin'], 'shebangOnBegin');
const sameAsBegin = hljs.END_SAME_AS_BEGIN({ begin: /a/, end: /a/ });
addCallback(sameAsBegin['on:begin'], 'endSameAsBeginOnBegin');
addCallback(sameAsBegin['on:end'], 'endSameAsBeginOnEnd');

// The keys of a mode, in the order of grammar.dart's (ModeKey's), and the
// kind of their values.
const modeKeys = new Map([
  ['begin', 'regex'], ['end', 'regex'], ['match', 'regex'],
  ['beforeMatch', 'regex'], ['illegal', 'regex'],
  ['keywords', 'keywords'], ['beginKeywords', 'string'],
  ['scope', 'scope'], ['className', 'scope'], ['beginScope', 'scope'],
  ['endScope', 'scope'], ['contains', 'contains'], ['variants', 'modes'],
  ['starts', 'mode'], ['relevance', 'number'], ['excludeBegin', 'bool'],
  ['excludeEnd', 'bool'], ['returnBegin', 'bool'], ['returnEnd', 'bool'],
  ['endsParent', 'bool'], ['endsWithParent', 'bool'], ['skip', 'bool'],
  ['subLanguage', 'subLanguage'], ['on:begin', 'callback'],
  ['on:end', 'callback'], ['label', 'string'],
]);
const keyIndex = new Map([...modeKeys.keys()].map((key, i) => [key, i]));
// Keys the engine never reads: `binary` (shebang metadata) and `exports`
// (modes a language shares with others while they are being defined).
const ignoredKeys = new Set(['binary', 'exports']);
const languageKeys = new Set([
  'name', 'aliases', 'case_insensitive', 'unicodeRegex', 'classNameAliases',
  'disableAutodetect', 'supersetOf',
]);

// A key's flags in a grammar: set to JavaScript's null, or to undefined
// (both without a value).
const JS_NULL = 0x80;
const UNDEFINED = 0x40;

function dartString(s) {
  let out = "'";
  for (const ch of s) {
    const c = ch.codePointAt(0);
    if (ch === '\\') out += '\\\\';
    else if (ch === "'") out += "\\'";
    else if (ch === '$') out += '\\$';
    else if (ch === '\n') out += '\\n';
    else if (ch === '\r') out += '\\r';
    else if (ch === '\t') out += '\\t';
    else if (c < 0x20 || c === 0x7f || (c >= 0x80 && c < 0xa0) || c === 0x2028 || c === 0x2029) {
      out += `\\u{${c.toString(16)}}`;
    } else out += ch;
  }
  return out + "'";
}

function regexSource(value, path) {
  // `false` behaves exactly like an empty pattern (both are falsy).
  if (value === false) return '';
  if (typeof value === 'string') return value;
  if (value instanceof RegExp) return value.source;
  throw new Error(`${path}: not a regex: ${typeof value}`);
}

// Bytes being written: unsigned LEB128 numbers, strings by their index in
// the grammar's table.
class Bytes {
  constructor(strings) {
    this.strings = strings;
    this.out = [];
  }

  byte(b) { this.out.push(b); }

  uint(n) {
    if (!Number.isInteger(n) || n < 0) throw new Error(`not an unsigned integer: ${n}`);
    do {
      let b = n & 0x7f;
      n = Math.floor(n / 128);
      if (n) b |= 0x80;
      this.out.push(b);
    } while (n);
  }

  str(s) {
    if (typeof s !== 'string') throw new Error(`not a string: ${s}`);
    let index = this.strings.get(s);
    if (index === undefined) {
      index = this.strings.size;
      this.strings.set(s, index);
    }
    this.uint(index);
  }

  // A string or none (0), the string's index plus one.
  optStr(s) {
    if (s === null || s === undefined) {
      this.uint(0);
      return;
    }
    let index = this.strings.get(s);
    if (index === undefined) {
      index = this.strings.size;
      this.strings.set(s, index);
    }
    this.uint(index + 1);
  }

  append(other) { for (const b of other.out) this.out.push(b); }
}

class Writer {
  constructor(language) {
    this.language = language;
    this.strings = new Map();
    this.ids = new Map();
    this.queue = [];
    this.modes = [];
  }

  modeRef(obj, path) {
    if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) {
      throw new Error(`${path}: expected a mode`);
    }
    if (!this.ids.has(obj)) {
      this.ids.set(obj, this.ids.size);
      this.queue.push([obj, path]);
    }
    return this.ids.get(obj);
  }

  value(out, kind, value, path) {
    switch (kind) {
      case 'regex':
        if (Array.isArray(value)) {
          out.byte(1);
          out.uint(value.length);
          value.forEach((v, i) => out.str(regexSource(v, `${path}[${i}]`)));
        } else {
          out.byte(0);
          out.str(regexSource(value, path));
        }
        return;
      case 'string':
        if (typeof value !== 'string') throw new Error(`${path}: expected a string`);
        out.str(value);
        return;
      case 'number':
        if (typeof value !== 'number') throw new Error(`${path}: expected a number`);
        out.str(`${value}`);
        return;
      case 'bool':
        out.byte(value ? 1 : 0);
        return;
      case 'scope':
        if (typeof value === 'string') {
          out.byte(0);
          out.str(value);
          return;
        }
        if (typeof value === 'object') {
          const entries = Object.entries(value);
          out.byte(1);
          out.uint(entries.length);
          for (const [k, v] of entries) {
            if (!/^[0-9]+$/.test(k)) throw new Error(`${path}: scope key ${k}`);
            out.uint(Number(k));
            out.str(v);
          }
          return;
        }
        throw new Error(`${path}: bad scope`);
      case 'keywords':
        this.keywords(out, value, path);
        return;
      case 'contains':
        this.containsEntries(out, value, path);
        return;
      case 'modes':
        if (!Array.isArray(value)) throw new Error(`${path}: expected a list`);
        out.uint(value.length);
        value.forEach((m, i) => out.uint(this.modeRef(m, `${path}[${i}]`)));
        return;
      case 'mode':
        out.uint(this.modeRef(value, path));
        return;
      case 'subLanguage':
        if (typeof value === 'string') {
          out.byte(0);
          out.str(value);
          return;
        }
        if (Array.isArray(value)) {
          out.byte(1);
          out.uint(value.length);
          value.forEach((v) => out.str(v));
          return;
        }
        throw new Error(`${path}: bad subLanguage`);
      case 'callback': {
        const index = callbacks.get(normalize(value.toString()));
        if (index === undefined) throw new Error(`${path}: unknown callback:\n${value.toString()}`);
        out.byte(index);
        return;
      }
    }
    throw new Error(`${path}: unknown kind ${kind}`);
  }

  containsEntries(out, value, path) {
    if (!Array.isArray(value)) throw new Error(`${path}: contains is not a list`);
    out.uint(value.length);
    value.forEach((entry, i) => {
      if (entry === 'self') {
        out.byte(1);
      } else if (Array.isArray(entry)) {
        out.byte(2);
        this.containsEntries(out, entry, `${path}[${i}]`);
      } else {
        out.byte(0);
        out.uint(this.modeRef(entry, `${path}[${i}]`));
      }
    });
  }

  keywords(out, value, path) {
    const groups = [];
    let pattern = null;
    if (typeof value === 'string') {
      groups.push([null, value.split(' '), false]);
    } else if (Array.isArray(value)) {
      groups.push([null, value, true]);
    } else if (typeof value === 'object') {
      for (const [scope, words] of Object.entries(value)) {
        if (scope === '$pattern') {
          pattern = regexSource(words, `${path}.$pattern`);
          continue;
        }
        if (typeof words === 'string') groups.push([scope, words.split(' '), false]);
        else if (Array.isArray(words)) groups.push([scope, words, true]);
        else throw new Error(`${path}.${scope}: bad keyword list`);
      }
    } else {
      throw new Error(`${path}: bad keywords`);
    }
    out.uint(groups.length);
    for (const [scope, words, fromList] of groups) {
      out.optStr(scope);
      out.uint(words.length);
      words.forEach((w) => out.str(w));
      out.byte(fromList ? 1 : 0);
    }
    out.optStr(pattern);
  }

  // Writes the keys of every queued mode.
  drain() {
    while (this.queue.length) {
      const [obj, path] = this.queue.shift();
      const id = this.ids.get(obj);
      const out = new Bytes(this.strings);
      const keys = Object.keys(obj).filter((key) =>
        !(id === 0 && languageKeys.has(key)) && !ignoredKeys.has(key));
      out.uint(keys.length);
      for (const key of keys) {
        const kind = modeKeys.get(key);
        if (!kind) throw new Error(`${path}: unknown key ${key}`);
        const index = keyIndex.get(key);
        if (obj[key] === null) {
          // JavaScript's null, as opposed to undefined (see Mode.isJsNull).
          out.byte(index | JS_NULL);
        } else if (obj[key] === undefined) {
          out.byte(index | UNDEFINED);
        } else {
          out.byte(index);
          this.value(out, kind, obj[key], `${path}.${key}`);
        }
      }
      out.byte(Object.isFrozen(obj) ? 1 : 0);
      this.modes[id] = out;
    }
  }
}

function grammar(name, file) {
  const definition = require(join(hljsDir, 'lib/languages', file));
  const lang = definition(hljs);
  const w = new Writer(name);
  const header = new Bytes(w.strings);
  header.str(lang.name ?? name);
  const aliases = lang.aliases ? (Array.isArray(lang.aliases) ? lang.aliases : [lang.aliases]) : [];
  header.uint(aliases.length);
  aliases.forEach((a) => header.str(a));
  header.byte((lang.case_insensitive ? 1 : 0) | (lang.unicodeRegex ? 2 : 0) | (lang.disableAutodetect ? 4 : 0));
  const classNameAliases = Object.entries(lang.classNameAliases ?? {});
  header.uint(classNameAliases.length);
  for (const [k, v] of classNameAliases) {
    header.str(k);
    header.str(v);
  }
  header.optStr(lang.supersetOf ?? null);
  w.modeRef(lang, name);
  w.drain();
  // The strings (each as its UTF-8 length and bytes), the header, the
  // modes.
  const table = new Bytes(new Map());
  table.uint(w.strings.size);
  for (const s of w.strings.keys()) {
    const utf8 = Buffer.from(s, 'utf8');
    table.uint(utf8.length);
    for (const b of utf8) table.byte(b);
  }
  table.append(header);
  table.uint(w.modes.length);
  for (const mode of w.modes) table.append(mode);
  return { aliases, bytes: Buffer.from(table.out) };
}

// Language-specific callbacks.
{
  const mathematica = require(join(hljsDir, 'lib/languages/mathematica'))(hljs);
  const find = (obj, seen = new Set()) => {
    if (!obj || typeof obj !== 'object' || seen.has(obj)) return [];
    seen.add(obj);
    const found = typeof obj['on:begin'] === 'function' ? [obj['on:begin']] : [];
    for (const v of Object.values(obj)) found.push(...find(v, seen));
    return found;
  };
  for (const fn of find(mathematica)) addCallback(fn, 'mathematicaSystemSymbol');
  for (const fn of find(require(join(hljsDir, 'lib/languages/gcode'))(hljs))) {
    addCallback(fn, 'gcodeLetterBoundary');
  }
  for (const fn of find(require(join(hljsDir, 'lib/languages/javascript'))(hljs))) {
    if (!callbacks.has(normalize(fn.toString()))) addCallback(fn, 'javascriptIsTrulyOpeningTag');
  }
  const php = require(join(hljsDir, 'lib/languages/php'))(hljs);
  const phpFns = find(php).filter((fn) => !callbacks.has(normalize(fn.toString())));
  for (const fn of phpFns) addCallback(fn, 'phpHeredocOnBegin');
  const findEnd = (obj, seen = new Set()) => {
    if (!obj || typeof obj !== 'object' || seen.has(obj)) return [];
    seen.add(obj);
    const found = typeof obj['on:end'] === 'function' ? [obj['on:end']] : [];
    for (const v of Object.values(obj)) found.push(...findEnd(v, seen));
    return found;
  };
  for (const fn of findEnd(php)) {
    if (!callbacks.has(normalize(fn.toString()))) addCallback(fn, 'phpHeredocOnEnd');
  }
}

// [bytes] Brotli-compressed, in base64: as the constant [name] of the
// generated [file] has them when its content is the same (Brotli's output
// differs between versions, the content doesn't), else compressed anew.
function packed(file, name, bytes) {
  let existing;
  try {
    existing = readFileSync(file, 'utf8');
  } catch {
    existing = '';
  }
  const old = new RegExp(`const String ${name} =\\s*'([A-Za-z0-9+/=]*)';`).exec(existing)?.[1];
  if (old !== undefined) {
    try {
      if (brotliDecompressSync(Buffer.from(old, 'base64')).equals(bytes)) return old;
    } catch {
      // Damaged: compressed anew.
    }
  }
  return brotliCompressSync(bytes, {
    params: {
      [zlib.BROTLI_PARAM_QUALITY]: zlib.BROTLI_MAX_QUALITY,
      [zlib.BROTLI_PARAM_LGWIN]: zlib.BROTLI_MAX_WINDOW_BITS,
      [zlib.BROTLI_PARAM_SIZE_HINT]: bytes.length,
    },
  }).toString('base64');
}

const outDir = join(root, 'lib/src/languages');
const allFile = join(outDir, 'all.g.dart');
const symbolsFile = join(outDir, 'mathematica_symbols.g.dart');
const registry = [];
let raw = 0;
for (const { name, file } of order) {
  const { aliases, bytes } = grammar(name, file);
  registry.push({ name, aliases, at: raw, bytes });
  raw += bytes.length;
}
const grammars = packed(allFile, 'grammars', Buffer.concat(registry.map((r) => r.bytes)));
const symbols = (() => {
  const text = readFileSync(join(root, 'vendor/highlight.js/src/languages/lib/mathematica.js'), 'utf8');
  const body = text.slice(text.indexOf('['), text.lastIndexOf(']') + 1);
  return [...body.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((m) => JSON.parse(`"${m[1]}"`));
})();
if (symbols.some((s) => s.includes('\n'))) throw new Error('a Mathematica symbol with a line break');
const symbolsData = packed(symbolsFile, 'mathematicaSystemSymbolsData', Buffer.from(symbols.join('\n'), 'utf8'));
rmSync(outDir, { recursive: true, force: true });
mkdirSync(outDir, { recursive: true });
writeFileSync(allFile, [
  `// GENERATED by tool/generate/generate.mjs from highlight.js ${version}. Do not edit.`,
  '// ignore_for_file: type=lint',
  '',
  '/// Every language, in the order highlight.js registers them (which',
  '/// decides auto-detection ties): name, aliases and where its grammar',
  '/// starts in [grammars] (see `readGrammar`).',
  'const List<(String, List<String>, int)> allLanguages = [',
  ...registry.map((r) => `  (${dartString(r.name)}, [${r.aliases.map(dartString).join(', ')}], ${r.at}),`),
  '];',
  '',
  '/// The grammars of [allLanguages], one after another, Brotli-compressed,',
  '/// in base64.',
  `const String grammars = '${grammars}';`,
  '',
].join('\n'));
// The symbols the Mathematica callback accepts (a closure upstream), one
// per line.
writeFileSync(symbolsFile, [
  `// GENERATED by tool/generate/generate.mjs from highlight.js ${version}. Do not edit.`,
  '// ignore_for_file: type=lint',
  '',
  '/// The system symbols of Mathematica (`SYSTEM_SYMBOLS` upstream), one',
  '/// per line, Brotli-compressed, in base64.',
  `const String mathematicaSystemSymbolsData = '${symbolsData}';`,
  '',
].join('\n'));
console.log(`mathematica: ${symbols.length} system symbols`);
console.log(`generated ${registry.length} languages from highlight.js ${version}: ${raw} bytes of grammar, ${grammars.length} in base64 Brotli`);
