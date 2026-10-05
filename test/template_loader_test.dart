/// Tests for the template wave B seam (`lib/src/template_loader.dart`).
///
/// Covers the three-way [TemplateLoader] seam (VM scan, in-memory map,
/// Node stub + runtime detection), the `template_cache` semantics, the
/// `-E/--template-engine` vocabulary and the CLI `-T`/`-E` wiring into the
/// convert flow. Mustache rendering itself is template wave A.
@TestOn('vm')
library;

import 'dart:io';

import 'package:asciidart/src/internal.dart';
import 'package:test/test.dart';

/// Finds the enclosing repository checkout directory.
String _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/vendor/asciidoctor/test/fixtures')
            .existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'repository checkout not found above ${Directory.current.path}',
      );
    }
    dir = parent;
  }
}

/// An existing oracle fixture used as the CLI input file.
String get sampleFile =>
    '${_findRepoRoot()}/vendor/asciidoctor/test/fixtures/sample.adoc';

/// A minimal [Converter] capturing the options it was created with.
class _CapturingConverter extends Converter {
  /// Creates a converter for [backend] with [opts].
  new(super.backend, super.opts);

  @override
  String convert(
    AbstractNode node, [
    String? transform,
    ConvertOptions? opts,
  ]) => 'captured';
}

/// Invokes the CLI with buffered streams, returning the invoker.
Invoker _invoke(List<String> argv) {
  final out = StringBuffer();
  final err = StringBuffer();
  final invoker = Invoker.fromArgs(
    [...argv, sampleFile],
    out: out,
    err: err,
    environment: <String, String>{},
  )..redirectStreams(out, err);
  final savedLogger = LoggerManager.logger;
  LoggerManager.logger = Logger(sink: err)..level = savedLogger.level;
  try {
    invoker.invoke();
  } finally {
    LoggerManager.logger = savedLogger;
  }
  return invoker;
}

/// Creates a temp dir holding [files] (relative path -> content).
Directory _makeTemplateDir(Map<String, String> files) {
  final dir = Directory.systemTemp.createTempSync('templates');
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final entry in files.entries) {
    final file = File('${dir.path}/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
  return dir;
}

void main() {
  group('TemplateLoader seam contract', () {
    test('both loaders implement the shared interface', () {
      final TemplateLoader files = FileTemplateLoader(templateDirs: const []);
      final TemplateLoader memory = InMemoryTemplateLoader(
        const <String, String>{},
      );
      // The bound-method tear-offs pin the exact seam shape
      // `FutureOr<Map<String, String>> load()`: any signature drift fails
      // to compile here.
      final filesLoad = files.load;
      final memoryLoad = memory.load;
      expect(filesLoad, isNotNull);
      expect(memoryLoad, isNotNull);
    });
  });

  group('FileTemplateLoader', () {
    setUp(TemplateCache.clearCaches);
    tearDown(TemplateCache.clearCaches);

    test('loads mustache files keyed by basename minus extension', () {
      final dir = _makeTemplateDir({
        'paragraph.mustache': '<p>{{content}}</p>',
        'document.mustache': '<html>{{content}}</html>',
      });
      final loaded = FileTemplateLoader(templateDirs: [dir.path]).load();
      expect(
        loaded,
        equals({
          'paragraph': '<p>{{content}}</p>',
          'document': '<html>{{content}}</html>',
        }),
      );
    });

    test('ignores non-mustache files, subdirs and extensionless files', () {
      final dir = _makeTemplateDir({
        'paragraph.slim': 'p =content',
        'helpers.rb': 'def x; end',
        'README': 'not a template',
        'nested/document.mustache': 'too deep',
        '.mustache': 'nameless',
      });
      final loaded = FileTemplateLoader(templateDirs: [dir.path]).load();
      expect(loaded, isEmpty);
    });

    test('last template dir wins across dirs in order', () {
      final first = _makeTemplateDir({
        'paragraph.mustache': 'first',
        'only-first.mustache': 'first',
      });
      final second = _makeTemplateDir({'paragraph.mustache': 'second'});
      final loaded = FileTemplateLoader(templateDirs: [first.path, second.path])
          .load();
      expect(loaded, equals({'paragraph': 'second', 'only-first': 'first'}));
      // Reversed order reverses the winner.
      final flipped = FileTemplateLoader(
        templateDirs: [second.path, first.path],
        templateCache: false,
      ).load();
      expect(flipped['paragraph'], equals('first'));
    });

    test('skips missing directories and file paths', () {
      final dir = _makeTemplateDir({'paragraph.mustache': 'kept'});
      final notADir = File('${dir.path}/paragraph.mustache').path;
      final loaded = FileTemplateLoader(
        templateDirs: ['/no/such/dir', notADir, dir.path],
      ).load();
      expect(loaded, equals({'paragraph': 'kept'}));
    });

    test('empty templateDirs loads an empty map', () {
      expect(FileTemplateLoader(templateDirs: const []).load(), isEmpty);
    });

    test('returns a fresh map per load', () {
      final dir = _makeTemplateDir({'paragraph.mustache': 'x'});
      final loader = FileTemplateLoader(templateDirs: [dir.path]);
      final first = loader.load();
      first['paragraph'] = 'mutated';
      first['extra'] = 'mutated';
      expect(loader.load(), equals({'paragraph': 'x'}));
    });

    test('caches scans by default within the process', () {
      final dir = _makeTemplateDir({'paragraph.mustache': 'v1'});
      final loader = FileTemplateLoader(templateDirs: [dir.path]);
      expect(loader.load(), equals({'paragraph': 'v1'}));
      File('${dir.path}/paragraph.mustache').writeAsStringSync('v2');
      // The shared cache still serves the first scan ...
      expect(loader.load(), equals({'paragraph': 'v1'}));
      // ... even for a second loader over the same directory.
      expect(
        FileTemplateLoader(templateDirs: [dir.path]).load(),
        equals({'paragraph': 'v1'}),
      );
    });

    test('templateCache false disables the cache', () {
      final dir = _makeTemplateDir({'paragraph.mustache': 'v1'});
      final loader = FileTemplateLoader(
        templateDirs: [dir.path],
        templateCache: false,
      );
      expect(loader.load(), equals({'paragraph': 'v1'}));
      File('${dir.path}/paragraph.mustache').writeAsStringSync('v2');
      expect(loader.load(), equals({'paragraph': 'v2'}));
      // Disabled loaders also leave the shared cache untouched.
      expect(TemplateCache.shared.scans, isEmpty);
    });

    test('a custom TemplateCache store is populated and shared', () {
      final dir = _makeTemplateDir({'paragraph.mustache': 'v1'});
      final custom = TemplateCache();
      final loader = FileTemplateLoader(
        templateDirs: [dir.path],
        templateCacheStore: custom,
      );
      expect(loader.load(), equals({'paragraph': 'v1'}));
      expect(custom.scans.keys, hasLength(1));
      expect(TemplateCache.shared.scans, isEmpty);
      File('${dir.path}/paragraph.mustache').writeAsStringSync('v2');
      // The custom store serves the stale scan to a second loader.
      expect(
        FileTemplateLoader(
          templateDirs: [dir.path],
          templateCacheStore: custom,
        ).load(),
        equals({'paragraph': 'v1'}),
      );
    });

    test('clearCaches drops shared scan entries', () {
      final dir = _makeTemplateDir({'paragraph.mustache': 'v1'});
      final loader = FileTemplateLoader(templateDirs: [dir.path]);
      expect(loader.load(), equals({'paragraph': 'v1'}));
      File('${dir.path}/paragraph.mustache').writeAsStringSync('v2');
      TemplateCache.clearCaches();
      expect(loader.load(), equals({'paragraph': 'v2'}));
    });

    test('relative spellings of one directory share a cache entry', () {
      final dir = _makeTemplateDir({'paragraph.mustache': 'v1'});
      final loader = FileTemplateLoader(
        templateDirs: [dir.path, '${dir.path}/.'],
      );
      expect(loader.load(), equals({'paragraph': 'v1'}));
      expect(TemplateCache.shared.scans.keys, hasLength(1));
    });
  });

  group('InMemoryTemplateLoader', () {
    test('serves the map and copies on construct and on load', () {
      final source = {'paragraph': 'a'};
      final loader = InMemoryTemplateLoader(source);
      source['paragraph'] = 'mutated';
      source['extra'] = 'mutated';
      expect(loader.load(), equals({'paragraph': 'a'}));
      final loaded = loader.load();
      loaded['paragraph'] = 'mutated';
      expect(loader.load(), equals({'paragraph': 'a'}));
    });
  });

  group('template engines', () {
    test('supportedTemplateEngines is mustache plus dart', () {
      expect(supportedTemplateEngines, equals({'mustache', 'dart'}));
    });

    test('validateTemplateEngine accepts missing and known engines', () {
      expect(() => validateTemplateEngine(null), returnsNormally);
      expect(() => validateTemplateEngine('mustache'), returnsNormally);
      expect(() => validateTemplateEngine('dart'), returnsNormally);
    });

    test('validateTemplateEngine rejects unknown engines', () {
      for (final engine in ['haml', 'slim', 'erb', '']) {
        expect(
          () => validateTemplateEngine(engine),
          throwsA(
            isA<AsciidoctorException>().having(
              (e) => e.message,
              'message',
              equals(
                "unknown template engine '$engine' (supported: mustache, dart)",
              ),
            ),
          ),
          reason: 'engine: $engine',
        );
      }
    });

    test('factory validates the engine before engaging templates', () {
      // Unknown engines fail with the missing-engine diagnostic; known
      // engines build a real template chain (template wave C). A missing
      // directory simply contributes no templates.
      Html5Converter.registerFor();
      expect(
        () => Converter.create(
          'html5',
          const ConverterOptions(templateDirs: ['dir'], templateEngine: 'haml'),
        ),
        throwsA(isA<AsciidoctorException>()),
      );
      expect(
        Converter.create(
          'html5',
          const ConverterOptions(
            templateDirs: ['dir'],
            templateEngine: 'mustache',
          ),
        ),
        isA<CompositeConverter>(),
      );
      // Without template directories the engine stays inert.
      expect(
        Converter.create(
          'html5',
          const ConverterOptions(templateEngine: 'haml'),
        ),
        isNotNull,
      );
    });

    test('document passes template dirs and the default template cache', () {
      ConverterOptions? seen;
      final factory = (ConverterFactory(proxyDefault: false))
        ..register((backend, opts) {
          seen = opts;
          return _CapturingConverter(backend, opts);
        }, ['capture-backend']);
      final doc = Document(
        'hi',
        AsciidoctorOptions(
          backend: 'capture-backend',
          converterFactory: factory,
          templateDirs: ['just-a-dir'],
        ),
      );
      expect(seen, isNotNull);
      expect(seen!.templateDirs, equals(['just-a-dir']));
      expect(seen!.templateCache, isTrue);
      expect(seen!.document, same(doc));
      expect(seen!.safe, equals(doc.safe));
    });

    test('document passes explicit template options through', () {
      ConverterOptions? seen;
      final factory = (ConverterFactory(proxyDefault: false))
        ..register((backend, opts) {
          seen = opts;
          return _CapturingConverter(backend, opts);
        }, ['capture-backend']);
      Document(
        'hi',
        AsciidoctorOptions(
          backend: 'capture-backend',
          converterFactory: factory,
          templateDirs: const ['d1', 'd2'],
          templateCache: false,
          templateEngine: 'mustache',
          safe: SafeMode.safe,
        ),
      );
      expect(seen, isNotNull);
      expect(seen!.templateDirs, equals(['d1', 'd2']));
      expect(seen!.templateCache, isFalse);
      expect(seen!.templateEngine, equals('mustache'));
      expect(seen!.safe, equals(SafeMode.safe));
    });

    test('convert surfaces the missing-engine error', () {
      expect(
        () => convert(
          'hi',
          const AsciidoctorOptions(
            templateDirs: ['dir'],
            templateEngine: 'slim',
          ),
        ),
        throwsA(
          isA<AsciidoctorException>().having(
            (e) => e.message,
            'message',
            contains("unknown template engine 'slim'"),
          ),
        ),
      );
    });
  });

  group('CLI template wiring', () {
    test('-T is repeatable and -E is recorded', () {
      final invoker = Invoker.fromArgs(
        ['-T', 'd1', '-T', 'd2', '-E', 'mustache', sampleFile],
        out: StringBuffer(),
        err: StringBuffer(),
        environment: <String, String>{},
      );
      expect(invoker.options, isNotNull);
      expect(invoker.options!.templateDirs, equals(['d1', 'd2']));
      expect(invoker.options!.templateEngine, equals('mustache'));
    });

    test('unknown engine fails the conversion with exit 1', () {
      final dir = _makeTemplateDir({'paragraph.mustache': 'x'});
      final invoker = _invoke(['-T', dir.path, '-E', 'haml', '-o', '-']);
      expect(invoker.code, equals(1));
      expect(invoker.readError(), contains('asciidart: FAILED'));
      expect(invoker.readError(), contains('haml'));
      expect(invoker.readError(), contains('Use --trace to show backtrace'));
    });

    test('unknown engine with --trace rethrows', () {
      final dir = _makeTemplateDir({'paragraph.mustache': 'x'});
      final out = StringBuffer();
      final err = StringBuffer();
      final invoker = (Invoker.fromArgs(
        ['--trace', '-T', dir.path, '-E', 'haml', '-o', '-', sampleFile],
        out: out,
        err: err,
        environment: <String, String>{},
      ))..redirectStreams(out, err);
      expect(invoker.invoke, throwsA(isA<AsciidoctorException>()));
      expect(invoker.code, equals(1));
    });
  });
}
