/// Tests for the top-level load/convert entry points (`load.dart`).
///
/// Ports the load/convert API assertions from `test/api_test.rb` (contexts
/// `Load` and `Convert`) and the `:logger API option` context from
/// `test/logger_test.rb`.
///
/// Adaptation policy: each in-scope Ruby test appears exactly once, under its
/// Ruby name. All ported tests pass except the three remote-stylesheet tests
/// under [needsSyncHttp], which are permanently skipped (synchronous
/// `convert` cannot fetch `http(s)` URIs in Dart). A few passing tests are
/// marked ADAPTED where only the input fixture or output location was
/// changed (empty document instead of `sample.adoc`; jailed scratch dir
/// instead of `fixtures/output`, since the Dart test jail is `dart/` while
/// Ruby's repo-root jail contains its fixtures dir). Focused
/// `load.dart`-behavior tests (descriptive names) cover entry-point branches
/// (file-attribute assignment, `/dev/null`, stream output, standalone
/// defaulting, stylesheet copying, error types).
///
/// Test seam: [Document] does not consult the converter factory yet (it
/// carries `_BuiltinConverterStub`; see `document.dart`), and substitutions
/// throw until TASK-2h31dk lands, so convert-flow tests pass an explicitly
/// created factory converter via the `'converter'` option and convert empty
/// documents, for which conversion succeeds end to end. This exercises the
/// real entry-point → converter → writer flow; only substituted content is
/// out of reach.
///
/// Deliberately not ported (other waves' surfaces, not entry-point
/// assertions): `find_by` tests, sourcemap/lineno tests (except option
/// threading, which is covered), node-method alias tests, the `AST` and
/// `SafeMode` contexts, syntax-highlighter tests, and the JRuby-only tests.
library;

import 'dart:io';

import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/converter.dart';
import 'package:asciidoctor/src/document.dart';
import 'package:asciidoctor/src/html5.dart';
import 'package:asciidoctor/src/load.dart';
import 'package:asciidoctor/src/logging.dart';
import 'package:asciidoctor/src/timings.dart';
import 'package:test/test.dart';

/// Permanent skip reason for the remote-stylesheet tests.
///
/// `dart:io` offers no synchronous HTTP client, so the synchronous
/// `convert` flow cannot fetch `http(s)` stylesheets the way Ruby's
/// `open-uri` does (`AbstractNode.fetchUri` throws `UnimplementedError` by
/// design). These bodies spin up a real loopback `HttpServer` and stay
/// skipped until a (future) async convert flow can reach it; the
/// allow-uri-read warning paths are covered by passing tests elsewhere.
const String needsSyncHttp =
    'PERMANENT SKIP: sync convert cannot fetch http(s) stylesheets in Dart '
    '(dart:io has no sync HTTP client; AbstractNode.fetchUri throws by design)';

/// Joins a fixture [name] to the Ruby fixtures directory (port of
/// `fixture_path`; tests run with `dart/` as the working directory).
String fixturePath(String name) => '../test/fixtures/$name';

/// Runs [fn] with a fresh temporary directory, deleted afterwards.
void withTempDir(void Function(Directory dir) fn) {
  final dir = Directory.systemTemp.createTempSync('asciidoctor-load-test-');
  try {
    fn(dir);
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// Runs [fn] with a fresh temporary directory under the working directory.
///
/// Mirrors Ruby's `fixture_path 'output'` scratch dir: with safe mode at or
/// above `SafeMode.safe`, `to_dir`/`to_file` targets must stay inside the
/// jail (the working directory; see `lib/asciidoctor/convert.rb`), so tests
/// that write output files cannot use [withTempDir] (`/tmp` is outside the
/// jail). Deleted afterwards.
void withJailedTempDir(void Function(Directory dir) fn) {
  final dir = Directory.current.createTempSync('asciidoctor-load-test-');
  try {
    fn(dir);
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// Splits [text] into lines, keeping the terminators (port of `String#lines`).
List<String> linesOf(String text) {
  final lines = text.split(RegExp('(?<=\n)'));
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines;
}

/// Creates an HTML5 converter via the converter factory.
///
/// Test seam: passed explicitly through the `'converter'` option because
/// [Document] does not consult the factory yet (see the library docs).
Converter html5Converter() {
  Html5Converter.registerFor();
  return Converter.create('html5')!;
}

/// A duck-typed attribute map (port of the `Hashlike` test double).
class FakeHashlike {
  /// Attribute table.
  final Map<String, Object?> table = {'toc': ''};

  /// Returns the attribute names.
  List<String> keys() => table.keys.toList();

  /// Returns the value of attribute [key].
  Object? operator [](Object? key) => table[key];
}

void main() {
  group('load', () {
    test('assigns docfile attributes for File input', () {
      withTempDir((dir) {
        final input = File('${dir.path}/sample.adoc')
          ..writeAsStringSync('text\n');
        final doc = load(input, {'safe': SafeMode.safe});
        expect(doc.attr('docfile'), equals(input.path));
        expect(doc.attr('docdir'), equals(dir.path));
        expect(doc.attr('docname'), equals('sample'));
        expect(doc.attr('docfilesuffix'), equals('.adoc'));
      });
    });

    test('should load input file', () {
      final sampleInputPath = fixturePath('sample.adoc');
      final file = File(sampleInputPath);
      final doc = load(file, {'safe': SafeMode.safe});
      expect(doc.doctitle(), equals('Document Title'));
      expect(doc.attr('docfile'), endsWith('/test/fixtures/sample.adoc'));
      expect(doc.attr('docdir'), endsWith('/test/fixtures'));
      expect(doc.attr('docfilesuffix'), equals('.adoc'));
    });

    test('loads string input without file attributes', () {
      const input = 'Document Title\n==============\n\npreamble\n';
      final doc = load(input, {'safe': SafeMode.safe});
      expect(doc.hasAttr('docfile'), isFalse);
      expect(doc.attr('docdir'), equals(doc.baseDir));
    });

    test('should load input string', () {
      const input = 'Document Title\n==============\n\npreamble\n';
      final doc = load(input, {'safe': SafeMode.safe});
      expect(doc.doctitle(), equals('Document Title'));
      expect(doc.hasAttr('docfile'), isFalse);
      expect(doc.attr('docdir'), equals(doc.baseDir));
    });

    test('loads line-list input without file attributes', () {
      const input = 'Document Title\n==============\n\npreamble\n';
      final doc = load(linesOf(input), {'safe': SafeMode.safe});
      expect(doc.hasAttr('docfile'), isFalse);
      expect(doc.attr('docdir'), equals(doc.baseDir));
      expect(doc.blocks, isNotEmpty);
    });

    test('should load input string array', () {
      const input = 'Document Title\n==============\n\npreamble\n';
      final doc = load(linesOf(input), {'safe': SafeMode.safe});
      expect(doc.doctitle(), equals('Document Title'));
      expect(doc.hasAttr('docfile'), isFalse);
      expect(doc.attr('docdir'), equals(doc.baseDir));
    });

    test('loads RandomAccessFile input without file attributes', () {
      withTempDir((dir) {
        final path = '${dir.path}/input.adoc';
        File(path).writeAsStringSync('Document Title\n\npreamble\n');
        final raf = File(path).openSync();
        try {
          final doc = load(raf, {'safe': SafeMode.safe});
          expect(doc.hasAttr('docfile'), isFalse);
          expect(doc.attr('docdir'), equals(doc.baseDir));
          expect(doc.blocks, isNotEmpty);
        } finally {
          raf.closeSync();
        }
      });
    });

    test('should load input IO', () {
      withTempDir((dir) {
        final path = '${dir.path}/input.adoc';
        File(path)
            .writeAsStringSync('Document Title\n==============\n\npreamble\n');
        final raf = File(path).openSync();
        try {
          final doc = load(raf, {'safe': SafeMode.safe});
          expect(doc.doctitle(), equals('Document Title'));
          expect(doc.hasAttr('docfile'), isFalse);
          expect(doc.attr('docdir'), equals(doc.baseDir));
        } finally {
          raf.closeSync();
        }
      });
    });

    test('should load nil input', () {
      final doc = load(null, {'safe': 'safe'});
      expect(doc, isNotNull);
      expect(doc.blocks, isEmpty);
    });

    test('ignores truthy non-string to_file option when loading', () {
      final doc = loadFile(fixturePath('sample.adoc'), {
        'safe': 'safe',
        'to_file': true,
      });
      expect(doc, isNotNull);
      expect(doc.attr('outfilesuffix'), equals('.html'));
    });

    test(
      'should ignore :to_file option if value is truthy but not a string',
      () {
        final sampleInputPath = fixturePath('sample.adoc');
        final doc = loadFile(sampleInputPath, {
          'safe': 'safe',
          'to_file': true,
        });
        expect(doc, isNotNull);
        expect(doc.doctitle(), equals('Document Title'));
        expect(doc.attr('outfilesuffix'), equals('.html'));
        expect(
          doc.convert(),
          equals(
            convertFile(sampleInputPath, {'safe': 'safe', 'to_file': false}),
          ),
        );
      },
    );

    test('sets outfilesuffix from string to_file option when loading', () {
      final doc = loadFile(fixturePath('sample.adoc'), {
        'safe': 'safe',
        'to_file': 'out.htm',
      });
      expect(doc, isNotNull);
      expect(doc.attr('outfilesuffix'), equals('.htm'));
    });

    test('should set outfilesuffix attribute to file extension of value of '
        ':to_file option if value is a string', () {
      final doc = loadFile(fixturePath('sample.adoc'), {
        'safe': 'safe',
        'to_file': 'out.htm',
      });
      expect(doc, isNotNull);
      expect(doc.doctitle(), equals('Document Title'));
      expect(doc.attr('outfilesuffix'), equals('.htm'));
    });

    test('should accept attributes as array', () {
      final doc = load('text', {
        'attributes': <String>[
          'toc',
          'sectnums',
          'source-highlighter=coderay',
          'idprefix',
          'idseparator=-',
        ],
      });
      expect(doc.attributes, isA<Map<String, Object?>>());
      expect(doc.hasAttr('toc'), isTrue);
      expect(doc.attr('toc'), equals(''));
      expect(doc.hasAttr('sectnums'), isTrue);
      expect(doc.attr('sectnums'), equals(''));
      expect(doc.hasAttr('source-highlighter'), isTrue);
      expect(doc.attr('source-highlighter'), equals('coderay'));
      expect(doc.hasAttr('idprefix'), isTrue);
      expect(doc.attr('idprefix'), equals(''));
      expect(doc.hasAttr('idseparator'), isTrue);
      expect(doc.attr('idseparator'), equals('-'));
    });

    test('should accept attributes as empty array', () {
      final doc = load('text', {'attributes': <String>[]});
      expect(doc.attributes, isA<Map<String, Object?>>());
    });

    test('should accept attributes as string', () {
      final doc = load('text', {
        'attributes':
            'toc sectnums\nsource-highlighter=coderay\nidprefix\nidseparator=-',
      });
      expect(doc.attributes, isA<Map<String, Object?>>());
      expect(doc.hasAttr('toc'), isTrue);
      expect(doc.attr('toc'), equals(''));
      expect(doc.hasAttr('sectnums'), isTrue);
      expect(doc.attr('sectnums'), equals(''));
      expect(doc.hasAttr('source-highlighter'), isTrue);
      expect(doc.attr('source-highlighter'), equals('coderay'));
      expect(doc.hasAttr('idprefix'), isTrue);
      expect(doc.attr('idprefix'), equals(''));
      expect(doc.hasAttr('idseparator'), isTrue);
      expect(doc.attr('idseparator'), equals('-'));
    });

    test('should accept values containing spaces in attributes string', () {
      final doc = load('text', {
        'attributes':
            'idprefix idseparator=-   note-caption=Note\\ to\\\tself toc',
      });
      expect(doc.attributes, isA<Map<String, Object?>>());
      expect(doc.hasAttr('idprefix'), isTrue);
      expect(doc.attr('idprefix'), equals(''));
      expect(doc.hasAttr('idseparator'), isTrue);
      expect(doc.attr('idseparator'), equals('-'));
      expect(doc.hasAttr('note-caption'), isTrue);
      expect(doc.attr('note-caption'), equals('Note to\tself'));
    });

    test('should accept attributes as empty string', () {
      final doc = load('text', {'attributes': ''});
      expect(doc.attributes, isA<Map<String, Object?>>());
    });

    test('should accept attributes as nil', () {
      final doc = load('text', {'attributes': null});
      expect(doc.attributes, isA<Map<String, Object?>>());
    });

    test('should accept attributes if hash like', () {
      final doc = load('text', {'attributes': FakeHashlike()});
      expect(doc.attributes, isA<Map<String, Object?>>());
      expect(doc.attributes.containsKey('toc'), isTrue);
    });

    test(
      'should not expand value of docdir attribute if specified via API',
      () {
        const docdir = 'virtual/directory';
        final doc = load('', {
          'safe': 'safe',
          'attributes': {'docdir': docdir},
        });
        expect(doc.attr('docdir'), equals(docdir));
        expect(doc.baseDir, equals(docdir));
      },
    );

    test('should not modify options argument', () {
      final options = <String, Object?>{'safe': SafeMode.safe};
      final doc = loadFile(fixturePath('sample.adoc'), options);
      expect(identical(options, doc.options), isFalse);
      expect(options, equals(<String, Object?>{'safe': SafeMode.safe}));
    });

    test('should not modify attributes Hash argument', () {
      final attributes = Map<String, Object?>.unmodifiable({});
      final options = <String, Object?>{
        'safe': SafeMode.safe,
        'attributes': attributes,
      };
      final doc = loadFile(fixturePath('sample.adoc'), options);
      expect(identical(attributes, doc.options['attributes']), isFalse);
      expect(identical(attributes, doc.attributes), isFalse);
    });

    test('should not load file with unrecognized encoding', () {
      withTempDir((dir) {
        // NOTE using a character whose code differs between UTF-8 and IBM437.
        final path = '${dir.path}/test-unrecognized.adoc';
        File(path).writeAsBytesSync([0xc6, 0x0a]);
        expect(
          () => loadFile(path, {'safe': 'safe'}),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains(
                'Failed to load AsciiDoc document - source is either binary '
                'or contains invalid Unicode data',
              ),
            ),
          ),
        );
      });
    });

    test('should not load invalid file', () {
      try {
        loadFile(fixturePath('hello-asciidoctor.pdf'), {'safe': SafeMode.safe});
        fail('expected an ArgumentError');
      } on ArgumentError catch (e, st) {
        expect(
          e.message,
          contains(
            'Failed to load AsciiDoc document - source is either binary or '
            'contains invalid Unicode data',
          ),
        );
        // The original stack trace is preserved (points into load.dart).
        expect(st.toString(), contains('load.dart'));
      }
    });

    test('returns unparsed document when parse is false', () {
      final doc = load('text', {'parse': false});
      expect(doc.isParsed, isFalse);
      final parsed = doc.parse();
      expect(parsed.isParsed, isTrue);
      expect(parsed.blocks, hasLength(1));
    });

    test('records read and parse timings when timings option is given', () {
      final timings = Timings();
      loadFile(fixturePath('sample.adoc'), {'timings': timings});
      expect(timings.log.keys, containsAll(['read', 'parse']));
    });

    test('raises ArgumentError for unsupported input type', () {
      for (final input in [42, true]) {
        expect(
          () => load(input),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('unsupported input type'),
            ),
          ),
        );
      }
    });

    test('raises ArgumentError for illegal attributes type', () {
      expect(
        () => load('text', {'attributes': 42}),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('illegal type for attributes option'),
          ),
        ),
      );
    });

    test('wraps unreadable file input with stdin context', () {
      expect(
        () => load(File('/no-such-dir/missing.adoc')),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'message',
            contains('<stdin>'),
          ),
        ),
      );
    });

    test('converts block to output format when convert is called', () {
      final doc = load('paragraph text');
      expect(doc.blocks, hasLength(1));
      expect(doc.blocks[0].context, equals('paragraph'));
      expect(
        doc.blocks[0].convert(),
        equals('<div class="paragraph">\n<p>paragraph text</p>\n</div>'),
      );
    });

    test(
      'should be able to restore header attributes after call to convert',
      () {
        const input =
            '= Document Title\n:foo: bar\n\ncontent\n\n:foo: baz\n\ncontent\n';
        final doc = load(input);
        expect(doc.attr('foo'), equals('bar'));
        doc.convert();
        expect(doc.attr('foo'), equals('baz'));
        doc.restoreAttributes();
        expect(doc.attr('foo'), equals('bar'));
      },
    );

    test('should output timestamps by default', () {
      final doc = load('text', {
        'backend': 'html5',
        'standalone': true,
        'attributes': {'linkcss': ''},
      });
      final result = doc.convert() as String;
      expect(doc.hasAttr('docdate'), isTrue);
      expect(doc.hasAttr('reproducible'), isFalse);
      // Ruby asserts an xpath match on the footer; the port checks the text.
      expect(result, contains('Last updated'));
    });

    test(
      'should not output timestamps if reproducible attribute is set in HTML 5',
      () {
        final doc = load('text', {
          'backend': 'html5',
          'standalone': true,
          'attributes': {'linkcss': '', 'reproducible': ''},
        });
        final result = doc.convert() as String;
        expect(doc.hasAttr('docdate'), isTrue);
        expect(doc.hasAttr('reproducible'), isTrue);
        expect(result, isNot(contains('Last updated')));
      },
    );

    test('should not output meta generator tag in HTML 5 if reproducible '
        'attribute is set', () {
      final doc = load('text', {
        'backend': 'html5',
        'standalone': true,
        'attributes': {'linkcss': '', 'reproducible': ''},
      });
      final result = doc.convert() as String;
      expect(doc.hasAttr('reproducible'), isTrue);
      expect(result, isNot(contains('<meta name="generator"')));
    });

    test('should not output timestamps if reproducible attribute is set in '
        'DocBook', () {
      final doc = load('text', {
        'backend': 'docbook',
        'standalone': true,
        'attributes': {'reproducible': ''},
      });
      final result = doc.convert() as String;
      expect(doc.hasAttr('docdate'), isTrue);
      expect(doc.hasAttr('reproducible'), isTrue);
      expect(result, isNot(contains('<date>')));
    });

    test('timings are recorded for each step when load and convert are called '
        'separately', () {
      final timings = Timings();
      loadFile(fixturePath('asciidoc_index.txt'), {
        'timings': timings,
      }).convert();
      expect(timings.readParse?.toStringAsFixed(5), isNot(equals('0.00000')));
      expect(timings.convert?.toStringAsFixed(5), isNot(equals('0.00000')));
      expect(timings.total, isNot(equals(timings.readParse)));
    });

    test('should coerce encoding of file to UTF-8', () {
      final output = convertFile(fixturePath('encoding.adoc'), {
        'to_file': false,
        'safe': 'safe',
      }) as String;
      expect(output, contains('Romé'));
    });

    test(
      'should convert filename that contains non-ASCII characters independent '
      'of default encodings',
      () {
        withTempDir((dir) {
          final inputPath = '${dir.path}/test-ＵＴＦ８-.adoc';
          File(inputPath).writeAsStringSync('ＵＴＦ８\n');
          final outputPath = inputPath.replaceAll('.adoc', '.html');
          convertFile(inputPath, {
            'safe': 'safe',
            'attributes': 'linkcss !copycss',
          });
          expect(File(outputPath).existsSync(), isTrue);
          final output = File(outputPath).readAsStringSync();
          expect(output, isNotEmpty);
          expect(output, contains('ＵＴＦ８'));
        });
      },
    );
  });

  group('loadFile', () {
    test('loads file from path string and assigns file attributes', () {
      final doc = loadFile(fixturePath('sample.adoc'), {'safe': SafeMode.safe});
      // Ruby asserts exact `File.expand_path` equality; the port pins the
      // stable suffix plus lexical `..` normalization (see `_absolutePath`).
      final docfile = doc.attr('docfile') as String;
      expect(docfile, endsWith('/test/fixtures/sample.adoc'));
      expect(docfile, isNot(contains('..')));
      expect(doc.attr('docdir'), endsWith('/test/fixtures'));
      expect(doc.attr('docname'), equals('sample'));
      expect(doc.attr('docfilesuffix'), equals('.adoc'));
    });

    test('should load input file from filename', () {
      final sampleInputPath = fixturePath('sample.adoc');
      final doc = loadFile(sampleInputPath, {'safe': SafeMode.safe});
      expect(doc.doctitle(), equals('Document Title'));
      expect(doc.attr('docfile'), endsWith('/test/fixtures/sample.adoc'));
      expect(doc.attr('docdir'), endsWith('/test/fixtures'));
      expect(doc.attr('docfilesuffix'), equals('.adoc'));
    });

    test('loads file from File and Uri filenames', () {
      final path = fixturePath('sample.adoc');
      for (final filename in [File(path), Uri.file(path)]) {
        final doc = loadFile(filename, {'safe': 'safe'});
        expect(
          doc.attr('docfile'),
          endsWith('/test/fixtures/sample.adoc'),
          reason: 'for filename $filename',
        );
        expect(doc.attr('docdir'), endsWith('/test/fixtures'));
        expect(doc.attr('docfilesuffix'), equals('.adoc'));
      }
    });

    test('should load input file from pathname', () {
      final doc = loadFile(Uri.file(fixturePath('sample.adoc')), {
        'safe': 'safe',
      });
      expect(doc.doctitle(), equals('Document Title'));
      expect(doc.attr('docfile'), endsWith('/test/fixtures/sample.adoc'));
      expect(doc.attr('docdir'), endsWith('/test/fixtures'));
      expect(doc.attr('docfilesuffix'), equals('.adoc'));
    });

    test('loads file with alternate extension', () {
      withTempDir((dir) {
        final input = File('${dir.path}/sample.asciidoc')
          ..writeAsStringSync('text\n');
        final doc = loadFile(input.path, {'safe': 'safe'});
        expect(doc.attr('docfile'), equals(input.path));
        expect(doc.attr('docdir'), equals(dir.path));
        expect(doc.attr('docname'), equals('sample'));
        expect(doc.attr('docfilesuffix'), equals('.asciidoc'));
      });
    });

    test('should load input file with alternate file extension', () {
      final sampleInputPath = fixturePath('sample-alt-extension.asciidoc');
      final doc = loadFile(sampleInputPath, {'safe': 'safe'});
      expect(doc.doctitle(), equals('Document Title'));
      expect(doc.attr('docfile'), endsWith('sample-alt-extension.asciidoc'));
      expect(doc.attr('docdir'), endsWith('/test/fixtures'));
      expect(doc.attr('docfilesuffix'), equals('.asciidoc'));
    });

    test('raises FileSystemException for missing file', () {
      expect(
        () => loadFile('/no-such-dir/missing.adoc'),
        throwsA(
          isA<FileSystemException>().having(
            (e) => e.message,
            'message',
            isNot(contains('FAILED')),
          ),
        ),
      );
    });

    test('raises ArgumentError for invalid filename type', () {
      expect(() => loadFile(42), throwsArgumentError);
      expect(() => convertFile(42), throwsArgumentError);
    });
  });

  group('convert', () {
    test('render is aliased to convert', () {
      // ignore: deprecated_member_use
      final viaRender = render('text', {'to_file': '/dev/null'});
      final viaConvert = convert('text', {'to_file': '/dev/null'});
      expect(viaRender, isA<Document>());
      expect(viaConvert, isA<Document>());
      expect(
        (viaRender as Document).blocks.length,
        equals((viaConvert as Document).blocks.length),
      );
    });

    test('render_file is aliased to convert_file', () {
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('text\n');
        // ignore: deprecated_member_use
        final viaRender = renderFile(inputPath, {'to_file': '/dev/null'});
        final viaConvert = convertFile(inputPath, {'to_file': '/dev/null'});
        expect(viaRender, isA<Document>());
        expect(
          (viaRender as Document).attr('docfile'),
          equals((viaConvert as Document).attr('docfile')),
        );
      });
    });

    test('returns document without converting when to_file is /dev/null', () {
      final doc = convert('text', {'to_file': '/dev/null'}) as Document;
      expect(doc.blocks, hasLength(1));
      expect(doc.isParsed, isTrue);
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('text\n');
        final fileDoc =
            convertFile(inputPath, {'to_file': '/dev/null'}) as Document;
        expect(fileDoc.blocks, hasLength(1));
        expect(
          File('${dir.path}/sample.html').existsSync(),
          isFalse,
          reason: 'no output file is written',
        );
      });
    });

    test('returns converted string when to_file is false', () {
      // Ruby: stream output leaves standalone unset, so the transform is
      // embedded (`convert "text", to_file: false` => paragraph divs).
      final output = convert('text', {
        'to_file': false,
        'converter': html5Converter(),
      }) as String;
      expect(output, isNotEmpty);
      expect(output, contains('<p>text</p>'));
      expect(output, isNot(contains('<html')));
    });

    test('ignores parse option', () {
      // `parse: false` is deleted by `convert`, so the document is parsed.
      final doc =
          convert('text', {'to_file': '/dev/null', 'parse': false}) as Document;
      expect(doc.isParsed, isTrue);
    });

    test('defaults standalone when writing to a file', () {
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        final doc = convertFile(inputPath, {
          'safe': SafeMode.safe,
          'converter': html5Converter(),
        }) as Document;
        expect(doc.options['standalone'], equals(true));
        expect(File('${dir.path}/sample.html').existsSync(), isTrue);
      });
    });

    test('leaves standalone unset for stream output unless header_footer', () {
      final buffer = StringBuffer();
      final doc = convert('', {
        'to_file': buffer,
        'converter': html5Converter(),
      }) as Document;
      expect(doc.options.containsKey('standalone'), isFalse);
      // Ruby: an empty document converts to the empty embedded string.
      expect(buffer.toString(), isEmpty);

      final buffer2 = StringBuffer();
      final doc2 = convert('', {
        'to_file': buffer2,
        'header_footer': true,
        'converter': html5Converter(),
      }) as Document;
      expect(doc2.options['standalone'], equals(true));
    });

    test('writes sibling output file by default', () {
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        final doc = convertFile(inputPath, {
          'safe': SafeMode.safe,
          'converter': html5Converter(),
        }) as Document;
        final expectedOut = '${dir.path}/sample.html';
        expect(File(expectedOut).existsSync(), isTrue);
        expect(doc.attr('outfile'), equals(expectedOut));
        expect(doc.attr('outdir'), equals(dir.path));
      });
    });

    test('writes sibling output for File and Uri filenames', () {
      withTempDir((dir) {
        for (final filename in [
          File('${dir.path}/a.adoc'),
          Uri.file('${dir.path}/b.adoc'),
        ]) {
          final path = filename is File
              ? filename.path
              : (filename as Uri).toFilePath();
          File(path).writeAsStringSync('');
          final doc = convertFile(filename, {
            'safe': SafeMode.safe,
            'converter': html5Converter(),
          }) as Document;
          expect(doc, isA<Document>());
          expect(
            File(path.replaceAll('.adoc', '.html')).existsSync(),
            isTrue,
            reason: 'for filename $filename',
          );
        }
      });
    });

    test('writes to explicit to_file path', () {
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        final outputPath = '${dir.path}/result.html';
        final doc = convertFile(inputPath, {
          'to_file': outputPath,
          'base_dir': dir.path,
          'safe': SafeMode.safe,
          'converter': html5Converter(),
        }) as Document;
        expect(File(outputPath).existsSync(), isTrue);
        expect(doc.attr('outfile'), equals(outputPath));
      });
    });

    test('writes sibling output when to_file is true', () {
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        final doc = convertFile(inputPath, {
          'to_file': true,
          'safe': SafeMode.safe,
          'converter': html5Converter(),
        }) as Document;
        expect(doc, isA<Document>());
        expect(File('${dir.path}/sample.html').existsSync(), isTrue);
      });
    });

    test('resolves relative to_file against base_dir', () {
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        convertFile(inputPath, {
          'to_file': 'result.html',
          'base_dir': dir.path,
          'safe': SafeMode.safe,
          'converter': html5Converter(),
        });
        expect(File('${dir.path}/result.html').existsSync(), isTrue);
      });
    });

    test('writes output bytes without newline conversion', () {
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        convertFile(inputPath, {
          'safe': SafeMode.safe,
          'converter': html5Converter(),
        });
        final output = File('${dir.path}/sample.html').readAsStringSync();
        expect(output, isNotEmpty);
        expect(output, contains('\n'));
        expect(output, isNot(contains('\r')));
        expect(output, endsWith('</body>\n</html>'));
        expect(output.endsWith('\n'), isFalse);
      });
    });

    test(
      'should resolve :to_dir option correctly when both :to_dir and :to_file '
      'options are set to an absolute path',
      () {
        // ADAPTED: empty input (Ruby uses sample.adoc); the option echoes
        // are input-independent, and sample content needs TASK-2h31dk.
        withTempDir((dir) {
          final inputPath = '${dir.path}/sample.adoc';
          File(inputPath).writeAsStringSync('');
          final outputPath = '${dir.path}/out.html';
          final doc = convertFile(inputPath, {
            'to_file': outputPath,
            'to_dir': dir.path,
            'safe': 'unsafe',
            'converter': html5Converter(),
          }) as Document;
          expect(File(outputPath).existsSync(), isTrue);
          expect(doc.options['to_file'], equals(outputPath));
          expect(doc.options['to_dir'], equals(dir.path));
        });
      },
    );

    test('in_place option is ignored when to_file is specified', () {
      // ADAPTED: empty input (Ruby uses sample.adoc); existence is the
      // only assertion and sample content needs TASK-2h31dk.
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        convertFile(inputPath, {
          'to_file': '${dir.path}/result.html',
          'base_dir': dir.path,
          'in_place': true,
          'converter': html5Converter(),
        });
        expect(File('${dir.path}/result.html').existsSync(), isTrue);
      });
    });

    test('in_place option is ignored when to_dir is specified', () {
      // ADAPTED: empty input (Ruby uses sample.adoc); see above.
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        convertFile(inputPath, {
          'to_dir': dir.path,
          'base_dir': dir.path,
          'in_place': true,
          'converter': html5Converter(),
        });
        expect(File('${dir.path}/sample.html').existsSync(), isTrue);
      });
    });

    test('should respect outfilesuffix soft set from API', () {
      // ADAPTED: empty input (Ruby uses sample.adoc); the written name is
      // the only assertion and sample content needs TASK-2h31dk.
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        convertFile(inputPath, {
          'to_dir': dir.path,
          'base_dir': dir.path,
          'attributes': {'outfilesuffix': '.htm@'},
          'converter': html5Converter(),
        });
        expect(File('${dir.path}/sample.htm').existsSync(), isTrue);
      });
    });

    test('output should be relative to to_dir option', () {
      // ADAPTED: empty input (Ruby uses sample.adoc); see above.
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        final outputDir = '${dir.path}/test_output';
        Directory(outputDir).createSync();
        convertFile(inputPath, {
          'to_dir': outputDir,
          'base_dir': dir.path,
          'converter': html5Converter(),
        });
        expect(File('$outputDir/sample.html').existsSync(), isTrue);
      });
    });

    test('missing directories should be created if mkdirs is enabled', () {
      // ADAPTED: empty input (Ruby uses sample.adoc); see above.
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        final outputDir = '${dir.path}/test_output/subdir';
        convertFile(inputPath, {
          'to_dir': outputDir,
          'base_dir': dir.path,
          'mkdirs': true,
          'converter': html5Converter(),
        });
        expect(File('$outputDir/sample.html').existsSync(), isTrue);
      });
    });

    test(
      'should raise exception if an attempt is made to overwrite input file',
      () {
        final sampleInputPath = fixturePath('sample.adoc');
        expect(
          () => convertFile(sampleInputPath, {
            'attributes': {'outfilesuffix': '.adoc'},
          }),
          throwsA(
            isA<IOException>().having(
              (e) => e.toString(),
              'message',
              contains('input file and output file cannot be the same'),
            ),
          ),
        );
      },
    );

    test('to_file should be relative to to_dir when both given', () {
      // ADAPTED: empty input (Ruby uses sample.adoc); see above.
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        final outputDir = '${dir.path}/test_output';
        Directory(outputDir).createSync();
        convertFile(inputPath, {
          'to_dir': dir.path,
          'base_dir': dir.path,
          'to_file': 'test_output/result.html',
          'converter': html5Converter(),
        });
        expect(File('$outputDir/result.html').existsSync(), isTrue);
      });
    });

    test('should not modify options argument', () {
      // ADAPTED: empty input file (Ruby uses sample.adoc); option
      // immutability is input-independent and needs no output assertions.
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        final output = StringBuffer();
        final options = <String, Object?>{
          'safe': SafeMode.safe,
          'to_file': output,
          'converter': html5Converter(),
        };
        final doc = convertFile(inputPath, options) as Document;
        expect(identical(options, doc.options), isFalse);
        expect(options.keys, containsAll(['safe', 'to_file', 'converter']));
        expect(options, hasLength(3));
        // Ruby: an empty document converts to the empty embedded string.
        expect(output.toString(), isEmpty);
      });
    });

    test(
      'should set to_dir option to parent directory of specified output file',
      () {
        // ADAPTED: empty input (Ruby uses basic.adoc); the option echo is
        // input-independent and sample content needs TASK-2h31dk.
        withTempDir((dir) {
          final inputPath = '${dir.path}/basic.adoc';
          File(inputPath).writeAsStringSync('');
          final outputPath = '${dir.path}/basic.html';
          final doc = convertFile(inputPath, {
            'to_file': outputPath,
            'base_dir': dir.path,
            'converter': html5Converter(),
          }) as Document;
          expect(doc.options['to_dir'], equals(dir.path));
        });
      },
    );

    test('should set to_dir option to parent directory of specified output '
        'directory and file', () {
      // ADAPTED: empty input (Ruby uses basic.adoc); see above.
      withTempDir((dir) {
        final inputPath = '${dir.path}/basic.adoc';
        File(inputPath).writeAsStringSync('');
        final outputDir = '${dir.path}/fixtures';
        Directory(outputDir).createSync();
        final doc = convertFile(inputPath, {
          'to_dir': dir.path,
          'base_dir': dir.path,
          'to_file': 'fixtures/basic.html',
          'converter': html5Converter(),
        }) as Document;
        expect(doc.options['to_dir'], equals(outputDir));
      });
    });

    test('raises when target directory does not exist without mkdirs', () {
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        final missingDir = '${dir.path}/no-such-dir';
        expect(
          () => convertFile(inputPath, {
            'to_dir': missingDir,
            'base_dir': dir.path,
            'converter': html5Converter(),
          }),
          throwsA(
            isA<IOException>().having(
              (e) => e.toString(),
              'message',
              allOf([
                contains('target directory does not exist'),
                contains(':mkdirs option'),
              ]),
            ),
          ),
        );
      });
    });

    test('copies default stylesheet when linkcss and copycss are set', () {
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        final outputDir = '${dir.path}/output';
        Directory(outputDir).createSync();
        convertFile(inputPath, {
          'safe': SafeMode.safe,
          'to_dir': outputDir,
          'base_dir': dir.path,
          'converter': html5Converter(),
          'attributes': {'linkcss': '', 'copycss': ''},
        });
        final copied = File('$outputDir/asciidoctor.css');
        expect(copied.existsSync(), isTrue);
        expect(copied.readAsStringSync(), isNotEmpty);
      });
    });

    test('copies custom stylesheet when copycss is set', () {
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        File('${dir.path}/custom.css')
            .writeAsStringSync('body { color: green; }\n');
        final outputDir = '${dir.path}/output';
        Directory(outputDir).createSync();
        convertFile(inputPath, {
          'safe': SafeMode.safe,
          'to_dir': outputDir,
          'base_dir': dir.path,
          'mkdirs': true,
          'converter': html5Converter(),
          'attributes': {
            'stylesheet': 'custom.css',
            'linkcss': '',
            'copycss': '',
          },
        });
        final copied = File('$outputDir/custom.css');
        expect(copied.existsSync(), isTrue);
        expect(copied.readAsStringSync(), contains('color: green'));
      });
    });

    test('copies custom stylesheet from copycss path string', () {
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        File('${dir.path}/custom.css')
            .writeAsStringSync('body { color: green; }\n');
        final outputDir = '${dir.path}/output';
        Directory(outputDir).createSync();
        convertFile(inputPath, {
          'safe': SafeMode.safe,
          'to_dir': outputDir,
          'mkdirs': true,
          'converter': html5Converter(),
          'base_dir': dir.path,
          'attributes': {
            'stylesheet': 'styles.css',
            'linkcss': '',
            'copycss': 'custom.css',
          },
        });
        final copied = File('$outputDir/styles.css');
        expect(copied.existsSync(), isTrue);
        expect(copied.readAsStringSync(), contains('color: green'));
      });
    });

    test('copies custom stylesheet from Uri copycss location', () {
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        final src = File('${dir.path}/custom.css')
          ..writeAsStringSync('body { color: green; }\n');
        final outputDir = '${dir.path}/output';
        Directory(outputDir).createSync();
        convertFile(inputPath, {
          'safe': SafeMode.safe,
          'to_dir': outputDir,
          'mkdirs': true,
          'converter': html5Converter(),
          'base_dir': dir.path,
          'attributes': {
            'stylesheet': 'styles.css',
            'linkcss': '',
            'copycss': Uri.file(src.path),
          },
        });
        final copied = File('$outputDir/styles.css');
        expect(copied.existsSync(), isTrue);
        expect(copied.readAsStringSync(), contains('color: green'));
      });
    });

    test('copies custom stylesheet in subfolder preserving structure', () {
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        Directory('${dir.path}/stylesheets').createSync();
        File('${dir.path}/stylesheets/custom.css')
            .writeAsStringSync('body { color: green; }\n');
        final outputDir = '${dir.path}/output';
        Directory(outputDir).createSync();
        convertFile(inputPath, {
          'safe': SafeMode.safe,
          'to_dir': outputDir,
          'mkdirs': true,
          'converter': html5Converter(),
          'base_dir': dir.path,
          'attributes': {
            'stylesheet': 'stylesheets/custom.css',
            'linkcss': '',
            'copycss': '',
          },
        });
        final copied = File('$outputDir/stylesheets/custom.css');
        expect(copied.existsSync(), isTrue);
        expect(copied.readAsStringSync(), contains('color: green'));
      });
    });

    test('raises when stylesheet dir is missing without mkdirs', () {
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        final outputDir = '${dir.path}/output';
        Directory(outputDir).createSync();
        expect(
          () => convertFile(inputPath, {
            'safe': SafeMode.safe,
            'to_dir': outputDir,
            'base_dir': dir.path,
            'converter': html5Converter(),
            'attributes': {
              'stylesdir': 'no-such-dir',
              'linkcss': '',
              'copycss': '',
            },
          }),
          throwsA(
            isA<IOException>().having(
              (e) => e.toString(),
              'message',
              contains('target stylesheet directory does not exist'),
            ),
          ),
        );
      });
    });

    test(
      'should convert source document to embedded document when header_footer '
      'is false',
      () {
        final sampleInputPath = fixturePath('sample.adoc');
        final sampleOutputPath = fixturePath('sample.html');
        try {
          convertFile(sampleInputPath, {'header_footer': false});
          expect(File(sampleOutputPath).existsSync(), isTrue);
          final output = File(sampleOutputPath).readAsStringSync();
          expect(output, isNotEmpty);
          expect(output, isNot(contains('<html')));
          expect(output, contains('id="preamble"'));
        } finally {
          File(sampleOutputPath).deleteSync();
        }
      },
    );

    test('should convert source document to standalone document string when '
        'to_file is false and standalone is true', () {
      final output = convertFile(fixturePath('sample.adoc'), {
        'standalone': true,
        'to_file': false,
      }) as String;
      expect(output, isNotEmpty);
      expect(output, contains('<html lang="en">'));
      expect(output, contains('<title>Document Title</title>'));
    });

    test('should convert source document to standalone document string when '
        'to_file is false and header_footer is true', () {
      final output = convertFile(fixturePath('sample.adoc'), {
        'header_footer': true,
        'to_file': false,
      }) as String;
      expect(output, isNotEmpty);
      expect(output, contains('<html lang="en">'));
      expect(output, contains('<title>Document Title</title>'));
    });

    test(
      'lines in output should be separated by line feed (universal newline)',
      () {
        final output = convertFile(fixturePath('sample.adoc'), {
          'standalone': true,
          'to_file': false,
        }) as String;
        expect(output, isNotEmpty);
        expect(output, isNot(contains('\r')));
      },
    );

    test('should accept attributes as array', () {
      final output = convertFile(fixturePath('sample.adoc'), {
        'attributes': ['sectnums', 'idprefix', 'idseparator=-'],
        'to_file': false,
      }) as String;
      expect(output, contains('id="section-a"'));
    });

    test('should accept attributes as string', () {
      final output = convertFile(fixturePath('sample.adoc'), {
        'attributes': 'sectnums idprefix idseparator=-',
        'to_file': false,
      }) as String;
      expect(output, contains('id="section-a"'));
    });

    test(
      'should link to default stylesheet by default when safe mode is SECURE '
      'or greater',
      () {
        final output = convertFile(fixturePath('basic.adoc'), {
          'standalone': true,
          'to_file': false,
        }) as String;
        expect(output, contains('href="./asciidoctor.css"'));
      },
    );

    test('should embed default stylesheet by default if SafeMode is less than '
        'SECURE', () {
      const input = '= Document Title\n\ntext\n';
      final output = convert(input, {
        'safe': SafeMode.server,
        'standalone': true,
      }) as String;
      expect(output, isNot(contains('href="./asciidoctor.css"')));
      expect(output, contains('<style>'));
    });

    test(
      'should embed remote stylesheet by default if SafeMode is less than '
      'SECURE and allow-uri-read is set',
      skip: needsSyncHttp,
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        try {
          server.listen((request) {
            request.response
              ..write('body { color: green; }')
              ..close();
          });
          const input = '= Document Title\n\ntext\n';
          final output = convert(input, {
            'safe': SafeMode.server,
            'standalone': true,
            'attributes': {
              'allow-uri-read': '',
              'stylesheet': 'http://127.0.0.1:${server.port}/custom.css',
            },
          }) as String;
          expect(output, contains('<style>'));
          expect(output, contains('color: green'));
        } finally {
          await server.close();
        }
      },
    );

    test(
      'should not allow linkcss be unset from document if SafeMode is SECURE '
      'or greater',
      () {
        const input = '= Document Title\n:linkcss!:\n\ntext\n';
        final output = convert(input, {'standalone': true}) as String;
        expect(output, contains('href="./asciidoctor.css"'));
      },
    );

    test('should embed default stylesheet if linkcss is unset from API and '
        'SafeMode is SECURE or greater', () {
      const input = '= Document Title\n\ntext\n';
      for (final attrs in [
        {'linkcss!': ''},
        {'linkcss': null},
        {'linkcss': false},
      ]) {
        final output =
            convert(input, {'standalone': true, 'attributes': attrs}) as String;
        expect(output, isNot(contains('href="./asciidoctor.css"')));
        expect(output, contains('<style>'));
      }
    });

    test('should embed default stylesheet if safe mode is less than SECURE and '
        'linkcss is unset from API', () {
      final output = convertFile(fixturePath('basic.adoc'), {
        'standalone': true,
        'to_file': false,
        'safe': SafeMode.safe,
        'attributes': {'linkcss!': ''},
      }) as String;
      expect(output, contains('<style>'));
    });

    test('should not link to stylesheet if stylesheet is unset', () {
      const input = '= Document Title\n\ntext\n';
      final output = convert(input, {
        'standalone': true,
        'attributes': {'stylesheet!': ''},
      }) as String;
      expect(output, isNot(contains('rel="stylesheet"')));
    });

    test(
      'should link to custom stylesheet if specified in stylesheet attribute',
      () {
        const input = '= Document Title\n\ntext\n';
        final output = convert(input, {
          'standalone': true,
          'attributes': {'stylesheet': './custom.css'},
        }) as String;
        expect(output, contains('href="./custom.css"'));
      },
    );

    test('should resolve custom stylesheet relative to stylesdir', () {
      const input = '= Document Title\n\ntext\n';
      final output = convert(input, {
        'standalone': true,
        'attributes': {
          'stylesheet': 'custom.css',
          'stylesdir': './stylesheets',
        },
      }) as String;
      expect(output, contains('href="./stylesheets/custom.css"'));
    });

    test('should resolve custom stylesheet to embed relative to stylesdir', () {
      final output = convertFile(fixturePath('basic.adoc'), {
        'standalone': true,
        'safe': SafeMode.safe,
        'to_file': false,
        'attributes': {
          'stylesheet': 'custom.css',
          'stylesdir': './stylesheets',
          'linkcss!': '',
        },
      }) as String;
      expect(output, contains('<style>'));
    });

    test(
      'should embed custom remote stylesheet if SafeMode is less than SECURE '
      'and allow-uri-read is set',
      skip: needsSyncHttp,
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        try {
          server.listen((request) {
            request.response
              ..write('body { color: green; }')
              ..close();
          });
          const input = '= Document Title\n\ntext\n';
          final output = convert(input, {
            'safe': SafeMode.server,
            'standalone': true,
            'attributes': {
              'allow-uri-read': '',
              'stylesheet': 'http://127.0.0.1:${server.port}/custom.css',
            },
          }) as String;
          expect(output, contains('<style>'));
          expect(output, contains('color: green'));
        } finally {
          await server.close();
        }
      },
    );

    test(
      'should embed custom stylesheet in remote stylesdir if SafeMode is less '
      'than SECURE and allow-uri-read is set',
      skip: needsSyncHttp,
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        try {
          server.listen((request) {
            request.response
              ..write('body { color: green; }')
              ..close();
          });
          const input = '= Document Title\n\ntext\n';
          final output = convert(input, {
            'safe': SafeMode.server,
            'standalone': true,
            'attributes': {
              'allow-uri-read': '',
              'stylesdir': 'http://127.0.0.1:${server.port}/fixtures',
              'stylesheet': 'custom.css',
            },
          }) as String;
          expect(output, contains('<style>'));
          expect(output, contains('color: green'));
        } finally {
          await server.close();
        }
      },
    );

    test(
      'should copy custom stylesheet in folder to same folder in destination '
      'dir if copycss is set',
      () {
        withJailedTempDir((dir) {
          final sampleInputPath = fixturePath('sample.adoc');
          final sampleOutputPath = '${dir.path}/sample.html';
          convertFile(sampleInputPath, {
            'safe': 'safe',
            'to_dir': dir.path,
            'mkdirs': true,
            'attributes': {
              'stylesheet': 'stylesheets/custom.css',
              'linkcss': '',
              'copycss': '',
            },
          });
          expect(File(sampleOutputPath).existsSync(), isTrue);
          expect(
            File('${dir.path}/stylesheets/custom.css').existsSync(),
            isTrue,
          );
        });
      },
    );

    test(
      'should copy custom stylesheet to destination dir if copycss is true',
      () {
        withJailedTempDir((dir) {
          convertFile(fixturePath('sample.adoc'), {
            'safe': 'safe',
            'to_dir': dir.path,
            'mkdirs': true,
            'attributes': {
              'stylesheet': 'custom.css',
              'linkcss': true,
              'copycss': true,
            },
          });
          expect(File('${dir.path}/sample.html').existsSync(), isTrue);
          expect(File('${dir.path}/custom.css').existsSync(), isTrue);
        });
      },
    );

    test(
      'should copy custom stylesheet to destination dir if copycss is a path '
      'string',
      () {
        withJailedTempDir((dir) {
          convertFile(fixturePath('sample.adoc'), {
            'safe': 'safe',
            'to_dir': dir.path,
            'mkdirs': true,
            'attributes': {
              'stylesheet': 'styles.css',
              'linkcss': true,
              'copycss': 'custom.css',
            },
          });
          expect(File('${dir.path}/sample.html').existsSync(), isTrue);
          expect(File('${dir.path}/styles.css').existsSync(), isTrue);
        });
      },
    );

    test('should copy custom stylesheet to destination dir if copycss is a '
        'Pathname object', () {
      withJailedTempDir((dir) {
        convertFile(fixturePath('sample.adoc'), {
          'safe': 'safe',
          'to_dir': dir.path,
          'mkdirs': true,
          'attributes': {
            'stylesheet': 'styles.css',
            'linkcss': true,
            // Absolute URI: Ruby's fixture_path is absolute, and a relative
            // copycss source would resolve against base_dir, not the cwd.
            'copycss': File(fixturePath('custom.css')).absolute.uri,
          },
        });
        expect(File('${dir.path}/sample.html').existsSync(), isTrue);
        expect(File('${dir.path}/styles.css').existsSync(), isTrue);
      });
    });

    test(
      'should convert source file and write result to adjacent file by default',
      () {
        final sampleInputPath = fixturePath('sample.adoc');
        final sampleOutputPath = fixturePath('sample.html');
        try {
          convertFile(sampleInputPath);
          expect(File(sampleOutputPath).existsSync(), isTrue);
          final output = File(sampleOutputPath).readAsStringSync();
          expect(output, isNotEmpty);
          expect(output, contains('<html lang="en">'));
          expect(output, contains('<title>Document Title</title>'));
        } finally {
          File(sampleOutputPath).deleteSync();
        }
      },
    );

    test('should convert source file specified by pathname and write result to '
        'adjacent file by default', () {
      final sampleInputPath = Uri.file(fixturePath('sample.adoc'));
      final sampleOutputPath = fixturePath('sample.html');
      try {
        final doc = convertFile(sampleInputPath, {'safe': 'safe'}) as Document;
        expect(doc.attr('outfile'), endsWith('/test/fixtures/sample.html'));
        expect(File(sampleOutputPath).existsSync(), isTrue);
        final output = File(sampleOutputPath).readAsStringSync();
        expect(output, isNotEmpty);
        expect(output, contains('<html lang="en">'));
      } finally {
        File(sampleOutputPath).deleteSync();
      }
    });

    test('should convert source file and write to specified file', () {
      // ADAPTED: output goes to a jailed scratch dir instead of
      // fixtures/result.html (Ruby's cwd-rooted jail contains its fixtures
      // dir; Dart's dart/-rooted jail does not).
      final sampleInputPath = fixturePath('sample.adoc');
      withJailedTempDir((dir) {
        final sampleOutputPath = '${dir.path}/result.html';
        convertFile(sampleInputPath, {'to_file': sampleOutputPath});
        expect(File(sampleOutputPath).existsSync(), isTrue);
        final output = File(sampleOutputPath).readAsStringSync();
        expect(output, isNotEmpty);
        expect(output, contains('<html lang="en">'));
        expect(output, contains('<title>Document Title</title>'));
      });
    });

    test(
      'should convert source file and write to specified file in base_dir',
      () {
        final sampleInputPath = fixturePath('sample.adoc');
        final sampleOutputPath = fixturePath('result.html');
        try {
          convertFile(sampleInputPath, {
            'to_file': 'result.html',
            'base_dir': fixturePath(''),
          });
          expect(File(sampleOutputPath).existsSync(), isTrue);
          final output = File(sampleOutputPath).readAsStringSync();
          expect(output, isNotEmpty);
          expect(output, contains('<html lang="en">'));
        } finally {
          if (File(sampleOutputPath).existsSync()) {
            File(sampleOutputPath).deleteSync();
          }
        }
      },
    );

    test('should write file in bin mode and thus not convert line feeds to '
        'system-dependent newline', () {
      final sampleInputPath = fixturePath('sample.adoc');
      final sampleOutputPath = fixturePath('sample.html');
      try {
        convertFile(sampleInputPath);
        expect(File(sampleOutputPath).existsSync(), isTrue);
        final output = File(sampleOutputPath).readAsStringSync();
        expect(output, isNotEmpty);
        expect(output, contains('\n'));
        expect(output, isNot(contains('\r')));
        expect(output, contains('</body>\n</html>'));
        expect(output.endsWith('\n'), isFalse);
      } finally {
        File(sampleOutputPath).deleteSync();
      }
    });

    test('should set outfilesuffix to match file extension of target file', () {
      withJailedTempDir((dir) {
        final sampleOutputPath = '${dir.path}/result.htm';
        convert('{outfilesuffix}', {'to_file': sampleOutputPath});
        expect(File(sampleOutputPath).existsSync(), isTrue);
        final output = File(sampleOutputPath).readAsStringSync();
        expect(output, isNotEmpty);
        expect(output, contains('<p>.htm</p>'));
      });
    });

    test('timings are recorded for each step', () {
      final timings = Timings();
      convertFile(fixturePath('asciidoc_index.txt'), {
        'timings': timings,
        'to_file': false,
      });
      expect(timings.readParse?.toStringAsFixed(5), isNot(equals('0.00000')));
      expect(timings.convert?.toStringAsFixed(5), isNot(equals('0.00000')));
      expect(timings.total, isNot(equals(timings.readParse)));
    });
  });

  group('logger option', () {
    test('should be able to set logger when invoking load API', () {
      final oldLogger = LoggerManager.logger;
      final newLogger = MemoryLogger();
      try {
        load('contents', {'logger': newLogger});
        expect(identical(newLogger, LoggerManager.logger), isTrue);
      } finally {
        LoggerManager.logger = oldLogger;
      }
    });

    test('should be able to set logger when invoking load_file API', () {
      final oldLogger = LoggerManager.logger;
      final newLogger = MemoryLogger();
      try {
        loadFile(fixturePath('basic.adoc'), {'logger': newLogger});
        expect(identical(newLogger, LoggerManager.logger), isTrue);
      } finally {
        LoggerManager.logger = oldLogger;
      }
    });

    test('should be able to set logger when invoking convert API', () {
      // ADAPTED: `/dev/null` output (full conversion needs TASK-2h31dk);
      // logger setup funnels through `load` either way.
      final oldLogger = LoggerManager.logger;
      final newLogger = MemoryLogger();
      try {
        convert('contents', {'logger': newLogger, 'to_file': '/dev/null'});
        expect(identical(newLogger, LoggerManager.logger), isTrue);
      } finally {
        LoggerManager.logger = oldLogger;
      }
    });

    test('should be able to set logger when invoking convert_file API', () {
      // ADAPTED: `/dev/null` output; see above.
      final oldLogger = LoggerManager.logger;
      final newLogger = MemoryLogger();
      try {
        convertFile(fixturePath('basic.adoc'), {
          'to_file': '/dev/null',
          'logger': newLogger,
        });
        expect(identical(newLogger, LoggerManager.logger), isTrue);
      } finally {
        LoggerManager.logger = oldLogger;
      }
    });

    test('should be able to set logger to NullLogger by setting :logger option '
        'to a falsy value', () {
      for (final falsyValue in [null, false]) {
        final oldLogger = LoggerManager.logger;
        try {
          load('contents', {'logger': falsyValue});
          expect(LoggerManager.logger, isA<NullLogger>());
        } finally {
          LoggerManager.logger = oldLogger;
        }
      }
    });
  });
}
