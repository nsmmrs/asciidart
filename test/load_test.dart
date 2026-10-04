/// Tests for the top-level load/convert entry points (`load.dart`).
///
/// Ports the load/convert API assertions from `test/api_test.rb` (contexts
/// `Load` and `Convert`) and the `:logger API option` context from
/// `test/logger_test.rb`, adapted to the typed API: inputs are strings or
/// file paths, options are [AsciidoctorOptions], and attributes are string
/// maps. Ruby-only input forms (IO objects, line arrays, attribute strings
/// and arrays, hash-likes, boolean `to_file`) have no Dart counterpart and
/// are not ported.
///
/// The remote-stylesheet tests convert through [convertAsync] against a
/// loopback HTTP server. Output-writing tests use a jailed scratch
/// directory under the working directory, since safe mode confines
/// `toDir`/`toFile` targets to it.
library;

import 'dart:async' show unawaited;
import 'dart:io';

import 'package:asciidoctor/src/internal.dart';
import 'package:test/test.dart';

/// Joins a fixture [name] to the Ruby fixtures directory (port of
/// `fixture_path`; tests run with `dart/` as the working directory).
String fixturePath(String name) => 'test/fixtures/$name';

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

void main() {
  group('load', () {
    test('assigns docfile attributes for file input', () {
      withTempDir((dir) {
        final input = File('${dir.path}/sample.adoc')
          ..writeAsStringSync('text\n');
        final doc = loadFile(
          input.path,
          options: const AsciidoctorOptions(safe: SafeMode.safe),
        );
        expect(doc.attr('docfile'), equals(input.path));
        expect(doc.attr('docdir'), equals(dir.path));
        expect(doc.attr('docname'), equals('sample'));
        expect(doc.attr('docfilesuffix'), equals('.adoc'));
      });
    });

    test('should load input file', () {
      final sampleInputPath = fixturePath('sample.adoc');
      final doc = loadFile(
        sampleInputPath,
        options: const AsciidoctorOptions(safe: SafeMode.safe),
      );
      expect(doc.doctitle(), equals('Document Title'));
      expect(doc.attr('docfile'), endsWith('/test/fixtures/sample.adoc'));
      expect(doc.attr('docdir'), endsWith('/test/fixtures'));
      expect(doc.attr('docfilesuffix'), equals('.adoc'));
    });

    test('loads string input without file attributes', () {
      const input = 'Document Title\n==============\n\npreamble\n';
      final doc = load(
        input,
        options: const AsciidoctorOptions(safe: SafeMode.safe),
      );
      expect(doc.hasAttr('docfile'), isFalse);
      expect(doc.attr('docdir'), equals(doc.baseDir));
    });

    test('should load input string', () {
      const input = 'Document Title\n==============\n\npreamble\n';
      final doc = load(
        input,
        options: const AsciidoctorOptions(safe: SafeMode.safe),
      );
      expect(doc.doctitle(), equals('Document Title'));
      expect(doc.hasAttr('docfile'), isFalse);
      expect(doc.attr('docdir'), equals(doc.baseDir));
    });

    test('should load nil input', () {
      final doc = load(
        null,
        options: const AsciidoctorOptions(safe: SafeMode.safe),
      );
      expect(doc, isNotNull);
      expect(doc.blocks, isEmpty);
    });

    test('sets outfilesuffix from string to_file option when loading', () {
      final doc = loadFile(
        fixturePath('sample.adoc'),
        options: const AsciidoctorOptions(
          safe: SafeMode.safe,
          toFile: 'out.htm',
        ),
      );
      expect(doc, isNotNull);
      expect(doc.attr('outfilesuffix'), equals('.htm'));
    });

    test('should set outfilesuffix attribute to file extension of value of '
        ':to_file option if value is a string', () {
      final doc = loadFile(
        fixturePath('sample.adoc'),
        options: const AsciidoctorOptions(
          safe: SafeMode.safe,
          toFile: 'out.htm',
        ),
      );
      expect(doc, isNotNull);
      expect(doc.doctitle(), equals('Document Title'));
      expect(doc.attr('outfilesuffix'), equals('.htm'));
    });

    test(
      'should not expand value of docdir attribute if specified via API',
      () {
        const docdir = 'virtual/directory';
        final doc = load(
          '',
          options: const AsciidoctorOptions(
            safe: SafeMode.safe,
            attributes: {'docdir': docdir},
          ),
        );
        expect(doc.attr('docdir'), equals(docdir));
        expect(doc.baseDir, equals(docdir));
      },
    );

    test('should not modify attributes argument', () {
      final attributes = Map<String, String?>.unmodifiable({});
      final doc = loadFile(
        fixturePath('sample.adoc'),
        options: AsciidoctorOptions(
          safe: SafeMode.safe,
          attributes: attributes,
        ),
      );
      expect(attributes, isEmpty);
      expect(identical(attributes, doc.attributes), isFalse);
    });

    test('should not load file with unrecognized encoding', () {
      withTempDir((dir) {
        // NOTE using a character whose code differs between UTF-8 and IBM437.
        final path = '${dir.path}/test-unrecognized.adoc';
        File(path).writeAsBytesSync([0xc6, 0x0a]);
        expect(
          () => loadFile(
            path,
            options: const AsciidoctorOptions(safe: SafeMode.safe),
          ),
          throwsA(
            isA<AsciidoctorException>().having(
              (e) => e.message,
              'message',
              allOf(
                startsWith('failed to load $path: '),
                endsWith(
                  'source is either binary or contains invalid Unicode data',
                ),
              ),
            ),
          ),
        );
      });
    });

    test('should not load invalid file', () {
      Object? error;
      StackTrace? stackTrace;
      try {
        loadFile(
          fixturePath('hello-asciidoctor.pdf'),
          options: const AsciidoctorOptions(safe: SafeMode.safe),
        );
      } on Object catch (e, st) {
        error = e;
        stackTrace = st;
      }
      expect(
        error,
        isA<AsciidoctorException>().having(
          (e) => e.message,
          'message',
          contains('source is either binary or contains invalid Unicode data'),
        ),
      );
      // The original stack trace is preserved (points into load.dart).
      expect('$stackTrace', contains('load.dart'));
    });

    test('returns unparsed document when parse is false', () {
      final doc = load('text', parse: false);
      expect(doc.isParsed, isFalse);
      final parsed = doc.parse();
      expect(parsed.isParsed, isTrue);
      expect(parsed.blocks, hasLength(1));
    });

    test('records read and parse timings when timings option is given', () {
      final timings = Timings();
      loadFile(
        fixturePath('sample.adoc'),
        options: AsciidoctorOptions(timings: timings),
      );
      expect(timings.log.keys, containsAll(['read', 'parse']));
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
      final doc = load(
        'text',
        options: const AsciidoctorOptions(
          backend: 'html5',
          standalone: true,
          attributes: {'linkcss': ''},
        ),
      );
      final result = doc.convert();
      expect(doc.hasAttr('docdate'), isTrue);
      expect(doc.hasAttr('reproducible'), isFalse);
      // Ruby asserts an xpath match on the footer; the port checks the text.
      expect(result, contains('Last updated'));
    });

    test(
      'should not output timestamps if reproducible attribute is set in HTML 5',
      () {
        final doc = load(
          'text',
          options: const AsciidoctorOptions(
            backend: 'html5',
            standalone: true,
            attributes: {'linkcss': '', 'reproducible': ''},
          ),
        );
        final result = doc.convert();
        expect(doc.hasAttr('docdate'), isTrue);
        expect(doc.hasAttr('reproducible'), isTrue);
        expect(result, isNot(contains('Last updated')));
      },
    );

    test('should not output timestamps if reproducible attribute is set in '
        'DocBook', () {
      final doc = load(
        'text',
        options: const AsciidoctorOptions(
          backend: 'docbook',
          standalone: true,
          attributes: {'reproducible': ''},
        ),
      );
      final result = doc.convert();
      expect(doc.hasAttr('docdate'), isTrue);
      expect(doc.hasAttr('reproducible'), isTrue);
      expect(result, isNot(contains('<date>')));
    });

    test('timings are recorded for each step when load and convert are called '
        'separately', () {
      final timings = Timings();
      loadFile(
        fixturePath('asciidoc_index.txt'),
        options: AsciidoctorOptions(timings: timings),
      ).convert();
      expect(timings.readParse?.toStringAsFixed(5), isNot(equals('0.00000')));
      expect(timings.convert?.toStringAsFixed(5), isNot(equals('0.00000')));
      expect(timings.total, isNot(equals(timings.readParse)));
    });

    test('should coerce encoding of file to UTF-8', () {
      final output = loadFile(
        fixturePath('encoding.adoc'),
        options: const AsciidoctorOptions(safe: SafeMode.safe),
      ).convert();
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
          convertFile(
            inputPath,
            const AsciidoctorOptions(
              safe: SafeMode.safe,
              attributes: {'linkcss': '', '!copycss': ''},
            ),
          );
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
      final doc = loadFile(
        fixturePath('sample.adoc'),
        options: const AsciidoctorOptions(safe: SafeMode.safe),
      );
      // Ruby asserts exact `File.expand_path` equality; the port pins the
      // stable suffix plus lexical `..` normalization (see `_absolutePath`).
      final docfile = doc.attr('docfile')!;
      expect(docfile, endsWith('/test/fixtures/sample.adoc'));
      expect(docfile, isNot(contains('..')));
      expect(doc.attr('docdir'), endsWith('/test/fixtures'));
      expect(doc.attr('docname'), equals('sample'));
      expect(doc.attr('docfilesuffix'), equals('.adoc'));
    });

    test('should load input file from filename', () {
      final sampleInputPath = fixturePath('sample.adoc');
      final doc = loadFile(
        sampleInputPath,
        options: const AsciidoctorOptions(safe: SafeMode.safe),
      );
      expect(doc.doctitle(), equals('Document Title'));
      expect(doc.attr('docfile'), endsWith('/test/fixtures/sample.adoc'));
      expect(doc.attr('docdir'), endsWith('/test/fixtures'));
      expect(doc.attr('docfilesuffix'), equals('.adoc'));
    });

    test('loads file with alternate extension', () {
      withTempDir((dir) {
        final input = File('${dir.path}/sample.asciidoc')
          ..writeAsStringSync('text\n');
        final doc = loadFile(
          input.path,
          options: const AsciidoctorOptions(safe: SafeMode.safe),
        );
        expect(doc.attr('docfile'), equals(input.path));
        expect(doc.attr('docdir'), equals(dir.path));
        expect(doc.attr('docname'), equals('sample'));
        expect(doc.attr('docfilesuffix'), equals('.asciidoc'));
      });
    });

    test('should load input file with alternate file extension', () {
      final sampleInputPath = fixturePath('sample-alt-extension.asciidoc');
      final doc = loadFile(
        sampleInputPath,
        options: const AsciidoctorOptions(safe: SafeMode.safe),
      );
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
  });

  group('convert', () {
    test('returns document without converting when to_file is /dev/null', () {
      final doc = convertToTarget(
        'text',
        const AsciidoctorOptions(toFile: '/dev/null'),
      );
      expect(doc.blocks, hasLength(1));
      expect(doc.isParsed, isTrue);
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('text\n');
        final fileDoc = convertFile(
          inputPath,
          const AsciidoctorOptions(toFile: '/dev/null'),
        );
        expect(fileDoc.blocks, hasLength(1));
        expect(
          File('${dir.path}/sample.html').existsSync(),
          isFalse,
          reason: 'no output file is written',
        );
      });
    });

    test('returns the converted string', () {
      // Ruby: stream output leaves standalone unset, so the transform is
      // embedded (`convert "text", to_file: false` => paragraph divs).
      final output = convert('text');
      expect(output, isNotEmpty);
      expect(output, contains('<p>text</p>'));
      expect(output, isNot(contains('<html')));
    });

    test('defaults standalone when writing to a file', () {
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        final doc = convertFile(
          inputPath,
          const AsciidoctorOptions(safe: SafeMode.safe),
        );
        expect(doc.options.standalone, isTrue);
        expect(File('${dir.path}/sample.html').existsSync(), isTrue);
      });
    });

    test('leaves standalone unset for stream output unless header_footer', () {
      final buffer = StringBuffer();
      final doc = convertToTarget('', const AsciidoctorOptions(), buffer);
      expect(doc.options.standalone, isNull);
      // Ruby: an empty document converts to the empty embedded string.
      expect(buffer.toString(), isEmpty);

      final buffer2 = StringBuffer();
      final doc2 = convertToTarget(
        '',
        const AsciidoctorOptions(standalone: true),
        buffer2,
      );
      expect(doc2.options.standalone, isTrue);
    });

    test('writes sibling output file by default', () {
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        final doc = convertFile(
          inputPath,
          const AsciidoctorOptions(safe: SafeMode.safe),
        );
        final expectedOut = '${dir.path}/sample.html';
        expect(File(expectedOut).existsSync(), isTrue);
        expect(doc.attr('outfile'), equals(expectedOut));
        expect(doc.attr('outdir'), equals(dir.path));
      });
    });

    test('writes to explicit to_file path', () {
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        final outputPath = '${dir.path}/result.html';
        final doc = convertFile(
          inputPath,
          AsciidoctorOptions(
            toFile: outputPath,
            baseDir: dir.path,
            safe: SafeMode.safe,
          ),
        );
        expect(File(outputPath).existsSync(), isTrue);
        expect(doc.attr('outfile'), equals(outputPath));
      });
    });

    test('resolves relative to_file against base_dir', () {
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        convertFile(
          inputPath,
          AsciidoctorOptions(
            toFile: 'result.html',
            baseDir: dir.path,
            safe: SafeMode.safe,
          ),
        );
        expect(File('${dir.path}/result.html').existsSync(), isTrue);
      });
    });

    test('writes output bytes without newline conversion', () {
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        convertFile(inputPath, const AsciidoctorOptions(safe: SafeMode.safe));
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
          final doc = convertFile(
            inputPath,
            AsciidoctorOptions(
              toFile: outputPath,
              toDir: dir.path,
              safe: SafeMode.unsafe,
            ),
          );
          expect(File(outputPath).existsSync(), isTrue);
          expect(doc.options.toFile, equals(outputPath));
          expect(doc.options.toDir, equals(dir.path));
        });
      },
    );

    test('should respect outfilesuffix soft set from API', () {
      // ADAPTED: empty input (Ruby uses sample.adoc); the written name is
      // the only assertion and sample content needs TASK-2h31dk.
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        convertFile(
          inputPath,
          AsciidoctorOptions(
            toDir: dir.path,
            baseDir: dir.path,
            attributes: {'outfilesuffix': '.htm@'},
          ),
        );
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
        convertFile(
          inputPath,
          AsciidoctorOptions(toDir: outputDir, baseDir: dir.path),
        );
        expect(File('$outputDir/sample.html').existsSync(), isTrue);
      });
    });

    test('missing directories should be created if mkdirs is enabled', () {
      // ADAPTED: empty input (Ruby uses sample.adoc); see above.
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        final outputDir = '${dir.path}/test_output/subdir';
        convertFile(
          inputPath,
          AsciidoctorOptions(toDir: outputDir, baseDir: dir.path, mkdirs: true),
        );
        expect(File('$outputDir/sample.html').existsSync(), isTrue);
      });
    });

    test(
      'should raise exception if an attempt is made to overwrite input file',
      () {
        final sampleInputPath = fixturePath('sample.adoc');
        expect(
          () => convertFile(
            sampleInputPath,
            const AsciidoctorOptions(attributes: {'outfilesuffix': '.adoc'}),
          ),
          throwsA(
            isA<AsciidoctorException>().having(
              (e) => e.message,
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
        convertFile(
          inputPath,
          AsciidoctorOptions(
            toDir: dir.path,
            baseDir: dir.path,
            toFile: 'test_output/result.html',
          ),
        );
        expect(File('$outputDir/result.html').existsSync(), isTrue);
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
          final doc = convertFile(
            inputPath,
            AsciidoctorOptions(toFile: outputPath, baseDir: dir.path),
          );
          expect(doc.options.toDir, equals(dir.path));
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
        final doc = convertFile(
          inputPath,
          AsciidoctorOptions(
            toDir: dir.path,
            baseDir: dir.path,
            toFile: 'fixtures/basic.html',
          ),
        );
        expect(doc.options.toDir, equals(outputDir));
      });
    });

    test('raises when target directory does not exist without mkdirs', () {
      withTempDir((dir) {
        final inputPath = '${dir.path}/sample.adoc';
        File(inputPath).writeAsStringSync('');
        final missingDir = '${dir.path}/no-such-dir';
        expect(
          () => convertFile(
            inputPath,
            AsciidoctorOptions(toDir: missingDir, baseDir: dir.path),
          ),
          throwsA(
            isA<AsciidoctorException>().having(
              (e) => e.message,
              'message',
              allOf([
                contains('target directory does not exist'),
                contains('mkdirs option'),
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
        convertFile(
          inputPath,
          AsciidoctorOptions(
            safe: SafeMode.safe,
            toDir: outputDir,
            baseDir: dir.path,
            attributes: {'linkcss': '', 'copycss': ''},
          ),
        );
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
        convertFile(
          inputPath,
          AsciidoctorOptions(
            safe: SafeMode.safe,
            toDir: outputDir,
            baseDir: dir.path,
            mkdirs: true,
            attributes: {
              'stylesheet': 'custom.css',
              'linkcss': '',
              'copycss': '',
            },
          ),
        );
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
        convertFile(
          inputPath,
          AsciidoctorOptions(
            safe: SafeMode.safe,
            toDir: outputDir,
            mkdirs: true,
            baseDir: dir.path,
            attributes: {
              'stylesheet': 'styles.css',
              'linkcss': '',
              'copycss': 'custom.css',
            },
          ),
        );
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
        convertFile(
          inputPath,
          AsciidoctorOptions(
            safe: SafeMode.safe,
            toDir: outputDir,
            mkdirs: true,
            baseDir: dir.path,
            attributes: {
              'stylesheet': 'stylesheets/custom.css',
              'linkcss': '',
              'copycss': '',
            },
          ),
        );
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
          () => convertFile(
            inputPath,
            AsciidoctorOptions(
              safe: SafeMode.safe,
              toDir: outputDir,
              baseDir: dir.path,
              attributes: {
                'stylesdir': 'no-such-dir',
                'linkcss': '',
                'copycss': '',
              },
            ),
          ),
          throwsA(
            isA<AsciidoctorException>().having(
              (e) => e.message,
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
          convertFile(
            sampleInputPath,
            const AsciidoctorOptions(standalone: false),
          );
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
      final output = loadFile(
        fixturePath('sample.adoc'),
        options: const AsciidoctorOptions(standalone: true),
      ).convert();
      expect(output, isNotEmpty);
      expect(output, contains('<html lang="en">'));
      expect(output, contains('<title>Document Title</title>'));
    });

    test(
      'lines in output should be separated by line feed (universal newline)',
      () {
        final output = loadFile(
          fixturePath('sample.adoc'),
          options: const AsciidoctorOptions(standalone: true),
        ).convert();
        expect(output, isNotEmpty);
        expect(output, isNot(contains('\r')));
      },
    );

    test(
      'should link to default stylesheet by default when safe mode is SECURE '
      'or greater',
      () {
        final output = loadFile(
          fixturePath('basic.adoc'),
          options: const AsciidoctorOptions(standalone: true),
        ).convert();
        expect(output, contains('href="./asciidoctor.css"'));
      },
    );

    test('should embed default stylesheet by default if SafeMode is less than '
        'SECURE', () {
      const input = '= Document Title\n\ntext\n';
      final output = convert(
        input,
        const AsciidoctorOptions(safe: SafeMode.server, standalone: true),
      );
      expect(output, isNot(contains('href="./asciidoctor.css"')));
      expect(output, contains('<style>'));
    });

    test('should embed remote stylesheet by default if SafeMode is less than '
        'SECURE and allow-uri-read is set', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      try {
        server.listen((request) {
          final response = request.response..write('body { color: green; }');
          unawaited(response.close());
        });
        const input = '= Document Title\n\ntext\n';
        final output = await convertAsync(
          input,
          AsciidoctorOptions(
            safe: SafeMode.server,
            standalone: true,
            attributes: {
              'allow-uri-read': '',
              'stylesheet': 'http://127.0.0.1:${server.port}/custom.css',
            },
          ),
        );
        expect(output, contains('<style>'));
        expect(output, contains('color: green'));
      } finally {
        await server.close();
      }
    });

    test(
      'should not allow linkcss be unset from document if SafeMode is SECURE '
      'or greater',
      () {
        const input = '= Document Title\n:linkcss!:\n\ntext\n';
        final output = convert(
          input,
          const AsciidoctorOptions(standalone: true),
        );
        expect(output, contains('href="./asciidoctor.css"'));
      },
    );

    test('should embed default stylesheet if linkcss is unset from API and '
        'SafeMode is SECURE or greater', () {
      const input = '= Document Title\n\ntext\n';
      for (final attrs in [
        {'linkcss!': ''},
        {'linkcss': null},
        {'linkcss!': '@'},
      ]) {
        final output = convert(
          input,
          AsciidoctorOptions(standalone: true, attributes: attrs),
        );
        expect(output, isNot(contains('href="./asciidoctor.css"')));
        expect(output, contains('<style>'));
      }
    });

    test('should embed default stylesheet if safe mode is less than SECURE and '
        'linkcss is unset from API', () {
      final output = loadFile(
        fixturePath('basic.adoc'),
        options: const AsciidoctorOptions(
          standalone: true,
          safe: SafeMode.safe,
          attributes: {'linkcss!': ''},
        ),
      ).convert();
      expect(output, contains('<style>'));
    });

    test('should not link to stylesheet if stylesheet is unset', () {
      const input = '= Document Title\n\ntext\n';
      final output = convert(
        input,
        const AsciidoctorOptions(
          standalone: true,
          attributes: {'stylesheet!': ''},
        ),
      );
      expect(output, isNot(contains('rel="stylesheet"')));
    });

    test(
      'should link to custom stylesheet if specified in stylesheet attribute',
      () {
        const input = '= Document Title\n\ntext\n';
        final output = convert(
          input,
          const AsciidoctorOptions(
            standalone: true,
            attributes: {'stylesheet': './custom.css'},
          ),
        );
        expect(output, contains('href="./custom.css"'));
      },
    );

    test('should resolve custom stylesheet relative to stylesdir', () {
      const input = '= Document Title\n\ntext\n';
      final output = convert(
        input,
        const AsciidoctorOptions(
          standalone: true,
          attributes: {
            'stylesheet': 'custom.css',
            'stylesdir': './stylesheets',
          },
        ),
      );
      expect(output, contains('href="./stylesheets/custom.css"'));
    });

    test('should resolve custom stylesheet to embed relative to stylesdir', () {
      final output = loadFile(
        fixturePath('basic.adoc'),
        options: const AsciidoctorOptions(
          standalone: true,
          safe: SafeMode.safe,
          attributes: {
            'stylesheet': 'custom.css',
            'stylesdir': './stylesheets',
            'linkcss!': '',
          },
        ),
      ).convert();
      expect(output, contains('<style>'));
    });

    test(
      'should embed custom remote stylesheet if SafeMode is less than SECURE '
      'and allow-uri-read is set',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        try {
          server.listen((request) {
            final response = request.response..write('body { color: green; }');
            unawaited(response.close());
          });
          const input = '= Document Title\n\ntext\n';
          final output = await convertAsync(
            input,
            AsciidoctorOptions(
              safe: SafeMode.server,
              standalone: true,
              attributes: {
                'allow-uri-read': '',
                'stylesheet': 'http://127.0.0.1:${server.port}/custom.css',
              },
            ),
          );
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
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        try {
          server.listen((request) {
            final response = request.response..write('body { color: green; }');
            unawaited(response.close());
          });
          const input = '= Document Title\n\ntext\n';
          final output = await convertAsync(
            input,
            AsciidoctorOptions(
              safe: SafeMode.server,
              standalone: true,
              attributes: {
                'allow-uri-read': '',
                'stylesdir': 'http://127.0.0.1:${server.port}/fixtures',
                'stylesheet': 'custom.css',
              },
            ),
          );
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
          convertFile(
            sampleInputPath,
            AsciidoctorOptions(
              safe: SafeMode.safe,
              toDir: dir.path,
              mkdirs: true,
              attributes: {
                'stylesheet': 'stylesheets/custom.css',
                'linkcss': '',
                'copycss': '',
              },
            ),
          );
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
          convertFile(
            fixturePath('sample.adoc'),
            AsciidoctorOptions(
              safe: SafeMode.safe,
              toDir: dir.path,
              mkdirs: true,
              attributes: {
                'stylesheet': 'custom.css',
                'linkcss': '',
                'copycss': '',
              },
            ),
          );
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
          convertFile(
            fixturePath('sample.adoc'),
            AsciidoctorOptions(
              safe: SafeMode.safe,
              toDir: dir.path,
              mkdirs: true,
              attributes: {
                'stylesheet': 'styles.css',
                'linkcss': '',
                'copycss': 'custom.css',
              },
            ),
          );
          expect(File('${dir.path}/sample.html').existsSync(), isTrue);
          expect(File('${dir.path}/styles.css').existsSync(), isTrue);
        });
      },
    );

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

    test('should convert source file and write to specified file', () {
      // ADAPTED: output goes to a jailed scratch dir instead of
      // fixtures/result.html (Ruby's cwd-rooted jail contains its fixtures
      // dir; Dart's dart/-rooted jail does not).
      final sampleInputPath = fixturePath('sample.adoc');
      withJailedTempDir((dir) {
        final sampleOutputPath = '${dir.path}/result.html';
        convertFile(
          sampleInputPath,
          AsciidoctorOptions(toFile: sampleOutputPath),
        );
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
          convertFile(
            sampleInputPath,
            AsciidoctorOptions(toFile: 'result.html', baseDir: fixturePath('')),
          );
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
        convertToTarget(
          '{outfilesuffix}',
          AsciidoctorOptions(toFile: sampleOutputPath),
        );
        expect(File(sampleOutputPath).existsSync(), isTrue);
        final output = File(sampleOutputPath).readAsStringSync();
        expect(output, isNotEmpty);
        expect(output, contains('<p>.htm</p>'));
      });
    });

    test('timings are recorded for each step', () {
      final timings = Timings();
      loadFile(
        fixturePath('asciidoc_index.txt'),
        options: AsciidoctorOptions(timings: timings),
      ).convert();
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
        load('contents', options: AsciidoctorOptions(logger: newLogger));
        expect(identical(newLogger, LoggerManager.logger), isTrue);
      } finally {
        LoggerManager.logger = oldLogger;
      }
    });

    test('should be able to set logger when invoking load_file API', () {
      final oldLogger = LoggerManager.logger;
      final newLogger = MemoryLogger();
      try {
        loadFile(
          fixturePath('basic.adoc'),
          options: AsciidoctorOptions(logger: newLogger),
        );
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
        convert('contents', AsciidoctorOptions(logger: newLogger));
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
        convertFile(
          fixturePath('basic.adoc'),
          AsciidoctorOptions(toFile: '/dev/null', logger: newLogger),
        );
        expect(identical(newLogger, LoggerManager.logger), isTrue);
      } finally {
        LoggerManager.logger = oldLogger;
      }
    });
  });
}
