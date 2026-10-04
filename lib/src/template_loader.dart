/// Three-way template source loading for the Dart port of Asciidoctor.
///
/// Port of the directory-scanning half of
/// `lib/asciidoctor/converter/template.rb` (`TemplateConverter#scan` /
/// `#scan_dir`), per ADR-0002 T1(b) + T5. The rendering half (Mustache
/// adapter, pre-flattened context, `TemplateConverter`, composite wiring)
/// belongs to template wave A; this library owns the loader seam, the
/// `template_cache` semantics and the `-E/--template-engine` vocabulary.
///
/// ## The seam
///
/// [TemplateLoader] is the platform seam: it resolves template directories
/// to node name -> Mustache source with last-wins already applied. The three
/// T5 implementations are [VmTemplateLoader] (`dart:io` scan, the `-T` CLI
/// path), [NodeTemplateLoader] (Node `fs` via JS interop; stubbed until the
/// npm/JS build lands) and [InMemoryTemplateLoader] (browser path + tests).
/// [TemplateLoader] itself is defined in `template.dart` (single home for
/// the seam contract).
///
/// ## Scan semantics (Ruby parity + deliberate divergences)
///
/// Like Ruby, every directory in `template_dirs` is scanned top-level only
/// (no recursion), missing entries are skipped, and later directories win
/// for a repeated node name. Divergences, all forced by ADR-0002 T1(b):
///
/// - Single extension: only `*.mustache` files load (Tilt's per-engine
///   extensions and auto-detection have no Dart analog).
/// - No engine/backend subdirectories: Ruby descends into per-engine and
///   per-backend subdirectories; Dart resolves Asciidoctor.js style (flat
///   directory, no backend infix).
/// - No `block_` prefix stripping or `block_ruler` renaming: the node name
///   is exactly the file basename minus `.mustache`.
/// - No `helpers.rb`: arbitrary code loading is impossible on Dart
///   (ADR-0002 T4); custom helpers are Dart lambdas via path (a).
///
/// ## Template cache
///
/// [TemplateCache] ports Ruby's `{ scans:, templates: }` process-lifetime
/// caches: [TemplateCache.scans] memoizes directory scans (name -> source)
/// and [TemplateCache.templates] reserves the per-file parsed-template slot
/// the wave-A renderer fills. The `template_cache` document option selects
/// the store (see [resolveTemplateCache]): absent or `true` (the default)
/// shares the process-wide [TemplateCache.shared]; an explicit `false`,
/// `null` or anything else disables caching; a [TemplateCache] instance is
/// used as a custom store. [TemplateCache.clearCaches] ports Ruby's
/// `TemplateConverter.clear_caches`.
///
/// ## Template engines
///
/// `-E/--template-engine` keeps flag parity with a Dart-side vocabulary
/// (see [supportedTemplateEngines]): only `mustache` (file templates) and
/// `dart` (code-registered transforms, path (a)) exist. Parsing records any
/// name untouched (Ruby parity: `options_test.rb` expects `-E haml` to
/// parse); the name is validated when templates engage (see
/// [validateTemplateEngine], called from the converter factory while
/// `template_dirs` is set). An unknown engine throws the port's analog of
/// Ruby's missing-engine `LoadError` (`Helpers.require_library :abort`),
/// e.g. ``asciidoctor: FAILED: required template engine 'haml' is not
/// available. Processing aborted.`` — reported by the invoker with the
/// `Use --trace to show backtrace` hint (exit 1) and rethrown under
/// `--trace`, exactly like Ruby.
library;

import 'dart:io' show Directory, File, FileSystemEntity, FileSystemException;

import 'package:asciidoctor/src/path_resolver.dart';
import 'package:asciidoctor/src/template.dart';
import 'package:asciidoctor/src/template_node_detect_js.dart'
    if (dart.library.io) 'template_node_detect_stub.dart'
    as detect;

/// The only file extension the VM scanner loads (ADR-0002 T1(b)).
const String _mustacheExtension = '.mustache';

/// Scans `template_dirs` for `*.mustache` files using `dart:io`.
///
/// The Dart VM / AOT implementation of [TemplateLoader] (the `-T` CLI
/// path): every directory is scanned top-level only, missing entries are
/// skipped, and later directories win for a repeated node name. The node
/// name is the file basename minus `.mustache`.
final class VmTemplateLoader implements TemplateLoader {
  /// Creates a loader scanning [templateDirs] in order.
  ///
  /// [templateCache] selects the [TemplateCache] store via
  /// [resolveTemplateCache] (default `true`, the process-shared cache).
  VmTemplateLoader({
    required List<String> templateDirs,
    Object? templateCache = true,
  }) : templateDirs = List.unmodifiable(templateDirs),
       _cache = resolveTemplateCache(templateCache);

  /// The template directories to scan, in resolution order.
  final List<String> templateDirs;

  /// The scan store, or `null` when caching is disabled.
  final TemplateCache? _cache;

  @override
  Map<String, String> load() {
    final merged = <String, String>{};
    final resolver = PathResolver();
    for (final dir in templateDirs) {
      // Resolved exactly like Ruby (`path_resolver.system_path`), so
      // relative spellings of one directory share a cache entry.
      final resolved = resolver.systemPath(dir, start: Directory.current.path);
      final cached = _cache?.scans[resolved];
      if (cached != null) {
        merged.addAll(cached);
        continue;
      }
      // A missing entry skips without a cache write (Ruby's
      // `next unless File.directory?`).
      final scanned = _scanDir(resolved);
      if (scanned != null) {
        _cache?.scans[resolved] = scanned;
        merged.addAll(scanned);
      }
    }
    // A fresh map per call: mutating the result never poisons the cache.
    return merged;
  }

  /// Scans [templateDir] top-level for `*.mustache` files.
  ///
  /// Returns `null` when [templateDir] is not a directory (skipped, like
  /// Ruby); otherwise the node name -> source map (possibly empty).
  static Map<String, String>? _scanDir(String templateDir) {
    final directory = Directory(templateDir);
    if (!directory.existsSync()) return null;
    final List<FileSystemEntity> entries;
    try {
      // Default `followLinks: true` matches Ruby's `File.file?` (a symlink
      // to a file counts); `recursive: false` keeps the scan top-level.
      entries = directory.listSync();
    } on FileSystemException {
      // Ruby's `Dir.glob` on an unreadable directory yields nothing.
      return <String, String>{};
    }
    final result = <String, String>{};
    for (final entry in entries) {
      if (entry is! File) continue;
      final basename = entry.path.split(RegExp(r'[\\/]')).last;
      if (!basename.endsWith(_mustacheExtension)) continue;
      final name = basename.substring(
        0,
        basename.length - _mustacheExtension.length,
      );
      if (name.isEmpty) continue;
      result[name] = entry.readAsStringSync();
    }
    return result;
  }
}

/// Serves templates from a map (browser path + tests).
///
/// The browser implementation of [TemplateLoader]: directory enumeration
/// is impossible there, so templates arrive pre-registered (ADR-0002 T5).
/// Also the deterministic loader for unit tests.
final class InMemoryTemplateLoader implements TemplateLoader {
  /// Creates a loader serving [templates].
  InMemoryTemplateLoader(Map<String, String> templates)
    : _templates = Map.of(templates);

  final Map<String, String> _templates;

  @override
  Map<String, String> load() => Map.of(_templates);
}

/// Loads templates with Node.js `fs` (JS-on-Node stub).
///
/// The Node implementation of [TemplateLoader] (ADR-0002 T5): one npm
/// bundle serves both JS environments, selected at runtime via
/// [isRunningOnNode]. The `fs` interop ships with the deferred npm/JS
/// build; until then [load] throws [UnimplementedError].
final class NodeTemplateLoader implements TemplateLoader {
  /// Creates a stub loader for [templateDirs] (kept for API symmetry with
  /// [VmTemplateLoader]; unused until the npm work lands).
  NodeTemplateLoader({required List<String> templateDirs})
    : templateDirs = List.unmodifiable(templateDirs);

  /// The template directories to scan once implemented.
  final List<String> templateDirs;

  @override
  Future<Map<String, String>> load() {
    throw UnimplementedError(
      'NodeTemplateLoader.load() is not implemented yet: reading template '
      'directories with Node.js fs interop ships with the deferred npm/JS '
      'build (ADR-0002 T5). On the Dart VM use VmTemplateLoader; in the '
      'browser use InMemoryTemplateLoader.',
    );
  }
}

/// Whether the current runtime is Node.js.
///
/// Defensive port of `typeof process?.versions?.node === 'string'`, behind
/// the platform seam: the `dart.library.io` conditional import selects the
/// VM stub (always `false`, no `dart:js_interop` import) on native
/// targets and the `dart:js_interop` walk on JS targets, so this helper is
/// safe to call everywhere.
bool isRunningOnNode() => detect.isRunningOnNode();

/// Process-lifetime template caches.
///
/// Port of `TemplateConverter.caches` (`{ scans:, templates: }`): [scans]
/// memoizes directory scans (absolute directory path -> node name ->
/// source) and [templates] holds parsed templates by absolute file path
/// (populated by the wave-A renderer; typed `Object?` so the loader seam
/// stays independent of the Mustache adapter).
final class TemplateCache {
  /// Creates an empty cache (a custom `template_cache` store).
  TemplateCache();

  /// Scan results by absolute directory path.
  final Map<String, Map<String, String>> scans = {};

  /// Parsed templates by absolute file path (wave-A renderer slot).
  final Map<String, Object?> templates = {};

  /// Clears both stores.
  void clear() {
    scans.clear();
    templates.clear();
  }

  /// The process-shared cache (the default `template_cache` store).
  static final TemplateCache shared = TemplateCache();

  /// Clears the process-shared cache.
  ///
  /// Port of `TemplateConverter.clear_caches`.
  static void clearCaches() => shared.clear();
}

/// Resolves the `template_cache` option to a [TemplateCache] store.
///
/// Port of the `case opts[:template_cache]` in `TemplateConverter#new`:
/// `true` (and the option's absent default, resolved by the caller to
/// `true`) selects [TemplateCache.shared]; a [TemplateCache] is used as a
/// custom store; anything else (`false`, `null`, ...) disables caching.
TemplateCache? resolveTemplateCache(Object? option) {
  if (option is TemplateCache) return option;
  if (option == true) return TemplateCache.shared;
  return null;
}

/// Template engines with a Dart implementation (ADR-0002 T1).
///
/// `mustache` resolves `*.mustache` files under `template_dirs`;
/// `dart` resolves code-registered transforms (path (a)) and scans no
/// files. Until further engines exist, anything else is rejected by
/// [validateTemplateEngine].
const Set<String> supportedTemplateEngines = {'mustache', 'dart'};

/// Validates the `template_engine` option, if templates engage.
///
/// A missing (`null`/`false`) engine selects auto-detection (currently the
/// `mustache` file scan); a known engine passes; anything else throws
/// [ArgumentError] with the port's missing-engine diagnostic (see the
/// library documentation). Called from the converter factory while
/// `template_dirs` is set — an engine without directories stays inert,
/// exactly as in Ruby.
void validateTemplateEngine(Object? engine) {
  if (engine == null || engine == false) return;
  if (engine is String && supportedTemplateEngines.contains(engine)) return;
  throw ArgumentError(
    "asciidoctor: FAILED: required template engine '$engine' is not "
    'available. Processing aborted.',
  );
}
