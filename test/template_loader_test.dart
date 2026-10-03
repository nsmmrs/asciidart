/// Tests for the template wave B seam (`lib/src/template_loader.dart`).
///
/// Covers the three-way [TemplateLoader] seam (VM scan, in-memory map,
/// Node stub + runtime detection), the `template_cache` semantics, the
/// `-E/--template-engine` vocabulary and the CLI `-T`/`-E` wiring into the
/// convert flow. Mustache rendering itself is template wave A.
library;

import 'dart:async' show FutureOr;
import 'dart:io';

import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/cli/invoker.dart';
import 'package:asciidoctor/src/converter.dart';
import 'package:asciidoctor/src/document.dart';
import 'package:asciidoctor/src/html5.dart';
import 'package:asciidoctor/src/load.dart';
import 'package:asciidoctor/src/logging.dart';
import 'package:asciidoctor/src/template.dart';
import 'package:asciidoctor/src/template_loader.dart';
import 'package:test/test.dart';

/// Finds the enclosing repository checkout directory.
String _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/dart/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/test/fixtures').existsSync()) {
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
String get sampleFile => '${_findRepoRoot()}/test/fixtures/sample.adoc';

/// A minimal [Converter] capturing the options it was created with.
class _CapturingConverter extends Converter {
  /// The options the factory received.
  final Map<String, Object?> seen;

  /// Creates a converter recording [opts] into [seen].
  _CapturingConverter(super.backend, Map<String, Object?> opts)
    : seen = Map.of(opts);

  @override
  Object? convert(
    AbstractNode node, [
    String? transform,
    Map<String, Object?>? opts,
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
  );
  invoker.redirectStreams(out, err);
  final savedLogger = LoggerManager.logger;
  LoggerManager.logger = Logger(logdev: err)..level = savedLogger.level;
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
    test('all three loaders implement the shared interface', () {
      final TemplateLoader vm = VmTemplateLoader(templateDirs: const []);
      final TemplateLoader memory = InMemoryTemplateLoader(
        const <String, String>{},
      );
      final TemplateLoader node = NodeTemplateLoader(templateDirs: const []);
      // The bound-method tear-offs pin the exact seam shape
      // `FutureOr<Map<String, String>> load()`: any signature drift fails
      // to compile here (and in wave A's identical interface).
      final FutureOr<Map<String, String>> Function() vmLoad = vm.load;
      final FutureOr<Map<String, String>> Function() memoryLoad = memory.load;
      final FutureOr<Map<String, String>> Function() nodeLoad = node.load;
      expect(vmLoad, isNotNull);
      expect(memoryLoad, isNotNull);
      expect(nodeLoad, isNotNull);
    });
  });

  group('VmTemplateLoader', () {
    setUp(TemplateCache.clearCaches);
    tearDown(TemplateCache.clearCaches);

    test('loads mustache files keyed by basename minus extension', () {
      final dir = _makeTemplateDir({
        'paragraph.mustache': '<p>{{content}}</p>',
        'document.mustache': '<html>{{content}}</html>',
      });
      final loaded = VmTemplateLoader(templateDirs: [dir.path]).load();
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
      final loaded = VmTemplateLoader(templateDirs: [dir.path]).load();
      expect(loaded, isEmpty);
    });

    test('last template dir wins across dirs in order', () {
      final first = _makeTemplateDir({
        'paragraph.mustache': 'first',
        'only-first.mustache': 'first',
      });
      final second = _makeTemplateDir({'paragraph.mustache': 'second'});
      final loaded = VmTemplateLoader(templateDirs: [first.path, second.path])
          .load();
      expect(loaded, equals({'paragraph': 'second', 'only-first': 'first'}));
      // Reversed order reverses the winner.
      final flipped = VmTemplateLoader(
        templateDirs: [second.path, first.path],
        templateCache: false,
      ).load();
      expect(flipped['paragraph'], equals('first'));
    });

    test('skips missing directories and file paths', () {
      final dir = _makeTemplateDir({'paragraph.mustache': 'kept'});
      final notADir = File('${dir.path}/paragraph.mustache').path;
      final loaded = VmTemplateLoader(
        templateDirs: ['/no/such/dir', notADir, dir.path],
      ).load();
      expect(loaded, equals({'paragraph': 'kept'}));
    });

    test('empty templateDirs loads an empty map', () {
      expect(VmTemplateLoader(templateDirs: const []).load(), isEmpty);
    });

    test('returns a fresh map per load', () {
      final dir = _makeTemplateDir({'paragraph.mustache': 'x'});
      final loader = VmTemplateLoader(templateDirs: [dir.path]);
      final first = loader.load();
      first['paragraph'] = 'mutated';
      first['extra'] = 'mutated';
      expect(loader.load(), equals({'paragraph': 'x'}));
    });

    test('caches scans by default within the process', () {
      final dir = _makeTemplateDir({'paragraph.mustache': 'v1'});
      final loader = VmTemplateLoader(templateDirs: [dir.path]);
      expect(loader.load(), equals({'paragraph': 'v1'}));
      File('${dir.path}/paragraph.mustache').writeAsStringSync('v2');
      // The shared cache still serves the first scan ...
      expect(loader.load(), equals({'paragraph': 'v1'}));
      // ... even for a second loader over the same directory.
      expect(
        VmTemplateLoader(templateDirs: [dir.path]).load(),
        equals({'paragraph': 'v1'}),
      );
    });

    test('templateCache false disables the cache', () {
      final dir = _makeTemplateDir({'paragraph.mustache': 'v1'});
      final loader = VmTemplateLoader(
        templateDirs: [dir.path],
        templateCache: false,
      );
      expect(loader.load(), equals({'paragraph': 'v1'}));
      File('${dir.path}/paragraph.mustache').writeAsStringSync('v2');
      expect(loader.load(), equals({'paragraph': 'v2'}));
      // Disabled loaders also leave the shared cache untouched.
      expect(TemplateCache.shared.scans, isEmpty);
    });

    test('templateCache null disables the cache (Ruby parity)', () {
      final dir = _makeTemplateDir({'paragraph.mustache': 'v1'});
      final loader = VmTemplateLoader(
        templateDirs: [dir.path],
        templateCache: null,
      );
      expect(loader.load(), equals({'paragraph': 'v1'}));
      File('${dir.path}/paragraph.mustache').writeAsStringSync('v2');
      expect(loader.load(), equals({'paragraph': 'v2'}));
      expect(TemplateCache.shared.scans, isEmpty);
    });

    test('a custom TemplateCache store is populated and shared', () {
      final dir = _makeTemplateDir({'paragraph.mustache': 'v1'});
      final custom = TemplateCache();
      final loader = VmTemplateLoader(
        templateDirs: [dir.path],
        templateCache: custom,
      );
      expect(loader.load(), equals({'paragraph': 'v1'}));
      expect(custom.scans.keys, hasLength(1));
      expect(TemplateCache.shared.scans, isEmpty);
      File('${dir.path}/paragraph.mustache').writeAsStringSync('v2');
      // The custom store serves the stale scan to a second loader.
      expect(
        VmTemplateLoader(
          templateDirs: [dir.path],
          templateCache: custom,
        ).load(),
        equals({'paragraph': 'v1'}),
      );
    });

    test('clearCaches drops shared scan entries', () {
      final dir = _makeTemplateDir({'paragraph.mustache': 'v1'});
      final loader = VmTemplateLoader(templateDirs: [dir.path]);
      expect(loader.load(), equals({'paragraph': 'v1'}));
      File('${dir.path}/paragraph.mustache').writeAsStringSync('v2');
      TemplateCache.clearCaches();
      expect(loader.load(), equals({'paragraph': 'v2'}));
    });

    test('resolveTemplateCache maps the option to a store', () {
      final custom = TemplateCache();
      expect(resolveTemplateCache(true), same(TemplateCache.shared));
      expect(resolveTemplateCache(custom), same(custom));
      expect(resolveTemplateCache(false), isNull);
      expect(resolveTemplateCache(null), isNull);
      expect(resolveTemplateCache('yes'), isNull);
      expect(resolveTemplateCache(42), isNull);
    });

    test('relative spellings of one directory share a cache entry', () {
      final dir = _makeTemplateDir({'paragraph.mustache': 'v1'});
      final loader = VmTemplateLoader(
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

  group('NodeTemplateLoader', () {
    test('load throws UnimplementedError naming the npm work', () {
      final loader = NodeTemplateLoader(templateDirs: const ['dir']);
      expect(
        loader.load,
        throwsA(
          isA<UnimplementedError>().having(
            (e) => e.message,
            'message',
            contains('npm/JS build'),
          ),
        ),
      );
    });

    test('isRunningOnNode is false on the VM', () {
      // The conditional import selects the stub (no dart:js_interop) on
      // native targets; the JS side is proven by compiling the probe in
      // /tmp (see the wave report) and running it under node.
      expect(isRunningOnNode(), isFalse);
    });
  });

  group('template engines', () {
    test('supportedTemplateEngines is mustache plus dart', () {
      expect(supportedTemplateEngines, equals({'mustache', 'dart'}));
    });

    test('validateTemplateEngine accepts missing and known engines', () {
      expect(() => validateTemplateEngine(null), returnsNormally);
      expect(() => validateTemplateEngine(false), returnsNormally);
      expect(() => validateTemplateEngine('mustache'), returnsNormally);
      expect(() => validateTemplateEngine('dart'), returnsNormally);
    });

    test('validateTemplateEngine rejects unknown engines like Ruby', () {
      for (final engine in ['haml', 'slim', 'erb', '', 42, true]) {
        expect(
          () => validateTemplateEngine(engine),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('asciidoctor: FAILED'),
                contains('$engine'),
                contains('Processing aborted.'),
              ),
            ),
          ),
          reason: 'engine: $engine',
        );
      }
    });

    test('factory validates the engine before the template wave gap', () {
      // Unknown engines fail with the missing-engine diagnostic even
      // while TemplateConverter itself is still unported (no
      // UnimplementedError); known engines reach the wave gap.
      Html5Converter.registerFor();
      expect(
        () => Converter.create('html5', {
          'template_dirs': ['dir'],
          'template_engine': 'haml',
        }),
        throwsArgumentError,
      );
      expect(
        () => Converter.create('html5', {
          'template_dirs': ['dir'],
          'template_engine': 'mustache',
        }),
        throwsUnimplementedError,
      );
      // Without template_dirs the engine stays inert (Ruby parity).
      expect(Converter.create('html5', {'template_engine': 'haml'}), isNotNull);
    });

    test('document coerces template dirs and defaults template_cache', () {
      Map<String, Object?>? seen;
      final factory = ConverterFactory(null, false);
      factory.register((String backend, Map<String, Object?> opts) {
        seen = Map.of(opts);
        return _CapturingConverter(backend, opts);
      }, ['capture-backend']);
      final doc = Document('hi', {
        'backend': 'capture-backend',
        'converter_factory': factory,
        'template_dirs': 'just-a-dir',
      });
      expect(seen, isNotNull);
      expect(seen!['template_dirs'], equals(['just-a-dir']));
      expect(seen!['template_cache'], isTrue);
      expect(seen!['document'], same(doc));
      expect(seen!['safe'], equals(doc.safe));
    });

    test('document passes explicit template options through', () {
      Map<String, Object?>? seen;
      final factory = ConverterFactory(null, false);
      factory.register((String backend, Map<String, Object?> opts) {
        seen = Map.of(opts);
        return _CapturingConverter(backend, opts);
      }, ['capture-backend']);
      const engineOptions = {
        'mustache': {'escape': false},
      };
      Document('hi', {
        'backend': 'capture-backend',
        'converter_factory': factory,
        'template_dir': ['d1', 'd2'],
        'template_cache': false,
        'template_engine': 'mustache',
        'template_engine_options': engineOptions,
        'eruby': 'erubi',
        'safe': SafeMode.safe,
      });
      expect(seen, isNotNull);
      expect(seen!['template_dirs'], equals(['d1', 'd2']));
      expect(seen!['template_cache'], isFalse);
      expect(seen!['template_engine'], equals('mustache'));
      expect(seen!['template_engine_options'], equals(engineOptions));
      expect(seen!['eruby'], equals('erubi'));
      expect(seen!['safe'], equals(SafeMode.safe));
    });

    test('convert surfaces the missing-engine error', () {
      expect(
        () => convert('hi', {
          'template_dirs': ['dir'],
          'template_engine': 'slim',
        }),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('asciidoctor: FAILED'), contains('slim')),
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
      expect(invoker.readError(), contains('asciidoctor: FAILED'));
      expect(invoker.readError(), contains('haml'));
      expect(invoker.readError(), contains('Use --trace to show backtrace'));
    });

    test('unknown engine with --trace rethrows', () {
      final dir = _makeTemplateDir({'paragraph.mustache': 'x'});
      final out = StringBuffer();
      final err = StringBuffer();
      final invoker = Invoker.fromArgs(
        ['--trace', '-T', dir.path, '-E', 'haml', '-o', '-', sampleFile],
        out: out,
        err: err,
        environment: <String, String>{},
      );
      invoker.redirectStreams(out, err);
      expect(invoker.invoke, throwsArgumentError);
      expect(invoker.code, equals(1));
    });
  });
}
