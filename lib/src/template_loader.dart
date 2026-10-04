/// Three-way template source loading for the Dart port of Asciidoctor.
///
/// Port of the directory-scanning half of
/// `lib/asciidoctor/converter/template.rb` (`TemplateConverter#scan` /
/// `#scan_dir`), per ADR-0002 T1(b) + T5. The rendering half lives in
/// `template.dart` and `template_context.dart`; this library owns the
/// loaders, the `template_cache` semantics and the `-E/--template-engine`
/// vocabulary.
///
/// ## The seam
///
/// [TemplateLoader] resolves template directories to node name -> Mustache
/// source with last-wins already applied. [FileTemplateLoader] scans the
/// file system through the I/O seam (`io.dart`), so it serves the `-T` CLI
/// path on the Dart VM and on Node.js alike; [InMemoryTemplateLoader] serves
/// a browser and tests. [TemplateLoader] itself is defined in
/// `template.dart`.
///
/// ## Scan semantics
///
/// As in Asciidoctor, every directory in `template_dirs` is scanned top-level
/// only (no recursion), missing entries are skipped, and later directories win
/// for a repeated node name. Divergences, all forced by ADR-0002 T1(b):
///
/// - Single extension: only `*.mustache` files load (Tilt's per-engine
///   extensions and auto-detection have no Dart analog).
/// - No engine/backend subdirectories (Asciidoctor descends into them);
///   directories are flat, as in Asciidoctor.js.
/// - No `block_` prefix stripping or `block_ruler` renaming: the node name
///   is exactly the file basename minus `.mustache`.
/// - No `helpers.rb`: arbitrary code loading is impossible on Dart
///   (ADR-0002 T4); custom helpers are Dart lambdas via path (a).
///
/// ## Template cache
///
/// [TemplateCache] holds the process-lifetime cache of directory scans
/// ([TemplateCache.scans], name -> source). The `templateCache` option
/// selects the process-wide [TemplateCache.shared] (the default) or no
/// caching; the `templateCacheStore` option supplies a custom store.
/// [TemplateCache.clearCaches] ports `TemplateConverter.clear_caches`.
///
/// ## Template engines
///
/// `-E/--template-engine` keeps flag parity with a Dart-side vocabulary
/// (see [supportedTemplateEngines]): only `mustache` (file templates) and
/// `dart` (code-registered transforms, path (a)) exist. Parsing records any
/// name untouched (so `-E haml` parses, as in Asciidoctor); the name is
/// validated when templates engage (see [validateTemplateEngine], called from
/// the converter factory while `template_dirs` is set). An unknown engine fails
/// like Asciidoctor's missing-engine error, e.g. ``asciidoctor: FAILED:
/// required template engine 'haml' is not available. Processing aborted.`` —
/// reported by the invoker with the `Use --trace to show backtrace` hint (exit
/// 1) and rethrown under `--trace`.
library;

import 'dart:convert' show utf8;

import 'package:asciidoctor/src/errors.dart';
import 'package:asciidoctor/src/io.dart' as io;
import 'package:asciidoctor/src/path_resolver.dart';
import 'package:asciidoctor/src/template.dart';

/// The only file extension the VM scanner loads (ADR-0002 T1(b)).
const String _mustacheExtension = '.mustache';

/// Scans `template_dirs` for `*.mustache` files.
///
/// The file system implementation of [TemplateLoader] (the `-T` CLI
/// path): every directory is scanned top-level only, missing entries are
/// skipped, and later directories win for a repeated node name. The node
/// name is the file basename minus `.mustache`.
final class FileTemplateLoader implements TemplateLoader {
  /// Creates a loader scanning [templateDirs] in order.
  ///
  /// [templateCacheStore] is the cache to use; otherwise [templateCache]
  /// selects the process-shared cache (the default) or no caching.
  new({
    required List<String> templateDirs,
    bool templateCache = true,
    TemplateCache? templateCacheStore,
  }) : templateDirs = List.unmodifiable(templateDirs),
       _cache =
           templateCacheStore ?? (templateCache ? TemplateCache.shared : null);

  /// The template directories to scan, in resolution order.
  final List<String> templateDirs;

  /// The scan store, or `null` when caching is disabled.
  final TemplateCache? _cache;

  @override
  Map<String, String> load() {
    final merged = <String, String>{};
    final resolver = PathResolver();
    for (final dir in templateDirs) {
      // Resolved with the path resolver, so relative spellings of one
      // directory share a cache entry.
      final resolved = resolver.systemPath(dir, start: io.currentDirectory);
      final cached = _cache?.scans[resolved];
      if (cached != null) {
        merged.addAll(cached);
        continue;
      }
      // A missing entry skips without a cache write.
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
  /// Returns `null` when [templateDir] is not a directory (skipped);
  /// otherwise the node name -> source map (possibly empty).
  static Map<String, String>? _scanDir(String templateDir) {
    if (!io.isDirectory(templateDir)) return null;
    final List<String> files;
    try {
      // A symlink to a file counts as a file; the scan stays top-level.
      files = [
        for (final entry in io.listDirectory(templateDir))
          if (entry.isFile) entry.path,
      ];
    } on io.IoException {
      // An unreadable directory yields nothing.
      return <String, String>{};
    }
    final result = <String, String>{};
    for (final file in files) {
      final basename = file.split(RegExp(r'[\\/]')).last;
      if (!basename.endsWith(_mustacheExtension)) continue;
      final name = basename.substring(
        0,
        basename.length - _mustacheExtension.length,
      );
      if (name.isEmpty) continue;
      result[name] = utf8.decode(io.readBytes(file));
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
  new(Map<String, String> templates) : _templates = Map.of(templates);

  final Map<String, String> _templates;

  @override
  Map<String, String> load() => Map.of(_templates);
}

/// Process-lifetime template caches.
///
/// Port of `TemplateConverter.caches`: [scans] memoizes directory scans
/// (absolute directory path -> node name -> source).
final class TemplateCache {
  /// Creates an empty cache (a custom `template_cache` store).
  new();

  /// Scan results by absolute directory path.
  final Map<String, Map<String, String>> scans = {};

  /// Clears the store.
  void clear() {
    scans.clear();
  }

  /// The process-shared cache (the default `template_cache` store).
  static final TemplateCache shared = TemplateCache();

  /// Clears the process-shared cache.
  ///
  /// Port of `TemplateConverter.clear_caches`.
  static void clearCaches() => shared.clear();
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
///.
void validateTemplateEngine(String? engine) {
  if (engine == null || supportedTemplateEngines.contains(engine)) return;
  throw AsciidoctorException(
    "unknown template engine '$engine' "
    '(supported: ${supportedTemplateEngines.join(', ')})',
  );
}
