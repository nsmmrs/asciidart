// Generates lib/src/languages/*.g.dart from highlight.js.
//
// Each upstream language definition is run against the real highlight.js
// (the version pinned in package.json), and the raw mode graph it returns is
// written out as Dart that builds the same graph: every object becomes one
// `Mode` (shared objects stay shared, frozen ones stay frozen), and the
// handful of JavaScript callbacks map to their Dart ports in
// lib/src/callbacks.dart by source text. Anything the generator does not
// know (a key, a value shape, a callback) fails the run, naming the
// language and the path.
//
// Usage: node tool/generate/generate.mjs   (from the repository root)
import { createRequire } from 'node:module';
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

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

// Callbacks by normalized source text -> Dart expression.
const callbacks = new Map();
function addCallback(fn, dart) { callbacks.set(normalize(fn.toString()), dart); }
function normalize(source) { return source.replace(/\s+/g, ' ').trim(); }

addCallback(hljs.SHEBANG()['on:begin'], 'callbacks.shebangOnBegin');
const sameAsBegin = hljs.END_SAME_AS_BEGIN({ begin: /a/, end: /a/ });
addCallback(sameAsBegin['on:begin'], 'callbacks.endSameAsBeginOnBegin');
addCallback(sameAsBegin['on:end'], 'callbacks.endSameAsBeginOnEnd');

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
// Keys the engine never reads: `binary` (shebang metadata) and `exports`
// (modes a language shares with others while they are being defined).
const ignoredKeys = new Set(['binary', 'exports']);
const dartKey = (key) => ({ 'on:begin': 'onBegin', 'on:end': 'onEnd' })[key] ?? key;
const languageKeys = new Set([
  'name', 'aliases', 'case_insensitive', 'unicodeRegex', 'classNameAliases',
  'disableAutodetect', 'supersetOf',
]);

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

class Writer {
  constructor(language) {
    this.language = language;
    this.ids = new Map();
    this.queue = [];
    this.lines = [];
    this.usesCallbacks = false;
  }

  modeRef(obj, path) {
    if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) {
      throw new Error(`${path}: expected a mode`);
    }
    if (!this.ids.has(obj)) {
      this.ids.set(obj, `m${this.ids.size}`);
      this.queue.push([obj, path]);
    }
    return this.ids.get(obj);
  }

  value(kind, value, path) {
    if (value === undefined || value === null) return 'null';
    switch (kind) {
      case 'regex':
        if (Array.isArray(value)) {
          return `RegexList([${value.map((v, i) => dartString(regexSource(v, `${path}[${i}]`))).join(', ')}])`;
        }
        return `RegexSource(${dartString(regexSource(value, path))})`;
      case 'string':
        if (typeof value !== 'string') throw new Error(`${path}: expected a string`);
        return dartString(value);
      case 'number':
        if (typeof value !== 'number') throw new Error(`${path}: expected a number`);
        return Number.isInteger(value) ? `${value}` : `${value}`;
      case 'bool':
        return value ? 'true' : 'false';
      case 'scope':
        if (typeof value === 'string') return `ScopeName(${dartString(value)})`;
        if (typeof value === 'object') {
          const entries = Object.entries(value).map(([k, v]) => {
            if (!/^[0-9]+$/.test(k)) throw new Error(`${path}: scope key ${k}`);
            return `${k}: ${dartString(v)}`;
          });
          return `ScopeGroups({${entries.join(', ')}})`;
        }
        throw new Error(`${path}: bad scope`);
      case 'keywords':
        return this.keywords(value, path);
      case 'contains':
        return `[${this.containsEntries(value, path).join(', ')}]`;
      case 'modes':
        if (!Array.isArray(value)) throw new Error(`${path}: expected a list`);
        return `[${value.map((m, i) => this.modeRef(m, `${path}[${i}]`)).join(', ')}]`;
      case 'mode':
        return this.modeRef(value, path);
      case 'subLanguage':
        if (typeof value === 'string') return `SubLanguageName(${dartString(value)})`;
        if (Array.isArray(value)) return `SubLanguageList([${value.map(dartString).join(', ')}])`;
        throw new Error(`${path}: bad subLanguage`);
      case 'callback': {
        const dart = callbacks.get(normalize(value.toString()));
        if (!dart) throw new Error(`${path}: unknown callback:\n${value.toString()}`);
        this.usesCallbacks = true;
        return dart;
      }
    }
    throw new Error(`${path}: unknown kind ${kind}`);
  }

  containsEntries(value, path) {
    if (!Array.isArray(value)) throw new Error(`${path}: contains is not a list`);
    return value.map((entry, i) => {
      if (entry === 'self') return 'self';
      if (Array.isArray(entry)) {
        return `ModeGroup([${this.containsEntries(entry, `${path}[${i}]`).join(', ')}])`;
      }
      return this.modeRef(entry, `${path}[${i}]`);
    });
  }

  keywords(value, path) {
    const group = (scope, words, fromList) =>
      `(scope: ${scope === null ? 'null' : dartString(scope)}, words: [${words.map(dartString).join(', ')}], fromList: ${fromList})`;
    if (typeof value === 'string') {
      return `RawKeywords([${group(null, value.split(' '), false)}])`;
    }
    if (Array.isArray(value)) {
      return `RawKeywords([${group(null, value, true)}])`;
    }
    if (typeof value === 'object') {
      const groups = [];
      let pattern = null;
      for (const [scope, words] of Object.entries(value)) {
        if (scope === '$pattern') {
          pattern = regexSource(words, `${path}.$pattern`);
          continue;
        }
        if (typeof words === 'string') groups.push(group(scope, words.split(' '), false));
        else if (Array.isArray(words)) groups.push(group(scope, words, true));
        else throw new Error(`${path}.${scope}: bad keyword list`);
      }
      return `RawKeywords([${groups.join(', ')}]${pattern === null ? '' : `, pattern: ${dartString(pattern)}`})`;
    }
    throw new Error(`${path}: bad keywords`);
  }

  // Writes the assignments of every queued mode.
  drain() {
    while (this.queue.length) {
      const [obj, path] = this.queue.shift();
      const id = this.ids.get(obj);
      const parts = [];
      const isRoot = id === 'm0';
      for (const key of Object.keys(obj)) {
        if (isRoot && languageKeys.has(key)) continue;
        if (ignoredKeys.has(key)) continue;
        const kind = modeKeys.get(key);
        if (!kind) throw new Error(`${path}: unknown key ${key}`);
        if (obj[key] === null) {
          // JavaScript's null, as opposed to undefined (see Mode.isJsNull).
          parts.push(`..setJsNull(ModeKey.${dartKey(key)})`);
          continue;
        }
        parts.push(`..${dartKey(key)} = ${this.value(kind, obj[key], `${path}.${key}`)}`);
      }
      if (Object.isFrozen(obj)) parts.push('..frozen = true');
      if (parts.length) this.lines.push(`  ${id}\n    ${parts.join('\n    ')};`);
    }
  }
}

function camel(name) {
  const parts = name.split(/[^A-Za-z0-9]+/).filter(Boolean);
  const id = parts.map((p, i) => (i === 0 ? p : p[0].toUpperCase() + p.slice(1))).join('');
  return /^[0-9]/.test(id) ? `l${id}` : id;
}

function generate(name, file) {
  const definition = require(join(hljsDir, 'lib/languages', file));
  // Language-specific callbacks: match them by source with the functions
  // the definition holds, using the Dart ports in callbacks.dart.
  const lang = definition(hljs);
  const w = new Writer(name);
  w.modeRef(lang, name);
  w.drain();
  const ids = [...w.ids.values()];
  const language = [
    `name: ${dartString(lang.name ?? name)}`,
    lang.aliases ? `aliases: [${(Array.isArray(lang.aliases) ? lang.aliases : [lang.aliases]).map(dartString).join(', ')}]` : null,
    lang.case_insensitive ? 'caseInsensitive: true' : null,
    lang.unicodeRegex ? 'unicodeRegex: true' : null,
    lang.classNameAliases ? `classNameAliases: {${Object.entries(lang.classNameAliases).map(([k, v]) => `${dartString(k)}: ${dartString(v)}`).join(', ')}}` : null,
    lang.disableAutodetect ? 'disableAutodetect: true' : null,
    lang.supersetOf ? `supersetOf: ${dartString(lang.supersetOf)}` : null,
  ].filter(Boolean);
  const fn = `build${camel(name)[0].toUpperCase()}${camel(name).slice(1)}`;
  const body = [
    '// GENERATED by tool/generate/generate.mjs from highlight.js ' + version + '. Do not edit.',
    '// ignore_for_file: type=lint',
    '',
    "import 'package:plain_highlighting/src/mode.dart';",
    w.usesCallbacks ? "import 'package:plain_highlighting/src/callbacks.dart' as callbacks;" : null,
    '',
    `/// The \`${name}\` language (${(lang.name ?? name).replace(/[\n\r]/g, ' ')}).`,
    `Language ${fn}() {`,
    `  final m0 = Language(${language.join(', ')});`,
    ids.length > 1 ? `  final ${ids.slice(1).map((id) => `${id} = Mode()`).join(', ')};` : null,
    ...w.lines,
    '  return m0;',
    '}',
    '',
  ].filter((l) => l !== null);
  return { fn, source: body.join('\n') };
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
  for (const fn of find(mathematica)) addCallback(fn, 'callbacks.mathematicaSystemSymbol');
  for (const fn of find(require(join(hljsDir, 'lib/languages/gcode'))(hljs))) {
    addCallback(fn, 'callbacks.gcodeLetterBoundary');
  }
  for (const fn of find(require(join(hljsDir, 'lib/languages/javascript'))(hljs))) {
    if (!callbacks.has(normalize(fn.toString()))) addCallback(fn, 'callbacks.javascriptIsTrulyOpeningTag');
  }
  const php = require(join(hljsDir, 'lib/languages/php'))(hljs);
  const phpFns = find(php).filter((fn) => !callbacks.has(normalize(fn.toString())));
  for (const fn of phpFns) addCallback(fn, 'callbacks.phpHeredocOnBegin');
  const findEnd = (obj, seen = new Set()) => {
    if (!obj || typeof obj !== 'object' || seen.has(obj)) return [];
    seen.add(obj);
    const found = typeof obj['on:end'] === 'function' ? [obj['on:end']] : [];
    for (const v of Object.values(obj)) found.push(...findEnd(v, seen));
    return found;
  };
  for (const fn of findEnd(php)) {
    if (!callbacks.has(normalize(fn.toString()))) addCallback(fn, 'callbacks.phpHeredocOnEnd');
  }
}

const outDir = join(root, 'lib/src/languages');
rmSync(outDir, { recursive: true, force: true });
mkdirSync(outDir, { recursive: true });
const registry = [];
for (const { name, file } of order) {
  const { fn, source } = generate(name, file);
  writeFileSync(join(outDir, `${file.replace(/[^a-z0-9_]/gi, '_')}.g.dart`), source);
  const lang = require(join(hljsDir, 'lib/languages', file))(hljs);
  const aliases = lang.aliases ? (Array.isArray(lang.aliases) ? lang.aliases : [lang.aliases]) : [];
  registry.push({ name, fn, aliases, file: `${file.replace(/[^a-z0-9_]/gi, '_')}.g.dart` });
}
writeFileSync(join(outDir, 'all.g.dart'), [
  `// GENERATED by tool/generate/generate.mjs from highlight.js ${version}. Do not edit.`,
  '// ignore_for_file: type=lint',
  '',
  "import 'package:plain_highlighting/src/mode.dart';",
  ...registry.map((r) => `import '${r.file}';`),
  '',
  '/// Every language, in the order highlight.js registers them (which',
  '/// decides auto-detection ties): name, aliases and builder.',
  'const List<(String, List<String>, Language Function())> allLanguages = [',
  ...registry.map((r) => `  (${dartString(r.name)}, [${r.aliases.map(dartString).join(', ')}], ${r.fn}),`),
  '];',
  '',
].join('\n'));
// The symbols the Mathematica callback accepts (a closure upstream).
{
  const text = readFileSync(join(root, 'vendor/highlight.js/src/languages/lib/mathematica.js'), 'utf8');
  const body = text.slice(text.indexOf('['), text.lastIndexOf(']') + 1);
  const symbols = [...body.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((m) => JSON.parse(`"${m[1]}"`));
  writeFileSync(join(outDir, 'mathematica_symbols.g.dart'), [
    `// GENERATED by tool/generate/generate.mjs from highlight.js ${version}. Do not edit.`,
    '// ignore_for_file: type=lint',
    '',
    '/// The system symbols of Mathematica (`SYSTEM_SYMBOLS` upstream).',
    'const Set<String> mathematicaSystemSymbols = {',
    ...symbols.map((s) => `  ${dartString(s)},`),
    '};',
    '',
  ].join('\n'));
  console.log(`mathematica: ${symbols.length} system symbols`);
}
console.log(`generated ${registry.length} languages from highlight.js ${version}`);
