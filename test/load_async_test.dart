/// Tests for the asynchronous entry points (`loadAsync`, `convertAsync`,
/// ...) and the `uriReader` option that serves remote content.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:asciidart/src/internal.dart';
import 'package:test/test.dart';

/// A loopback HTTP server serving [files] by path, counting requests.
final class FileServer {
  new(this.files);

  /// Response bodies by request path; other paths answer 404.
  final Map<String, String> files;

  /// Requests seen, by path.
  final Map<String, int> hits = {};

  late final HttpServer _server;

  /// The base URI of the server (no trailing slash).
  String get base => 'http://127.0.0.1:${_server.port}';

  /// Starts the server and stops it when the test ends.
  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => _server.close(force: true));
    _server.listen((request) {
      final path = request.uri.path;
      hits[path] = (hits[path] ?? 0) + 1;
      final body = files[path];
      final response = request.response;
      if (body == null) {
        response.statusCode = HttpStatus.notFound;
      } else {
        if (path.endsWith('.png')) {
          response.headers.contentType = ContentType('image', 'png');
        }
        response.write(body);
      }
      unawaited(response.close());
    });
  }
}

/// Options allowing remote content in [safe] mode, with [attributes].
AsciidoctorOptions remoteOptions([
  Map<String, String?> attributes = const {},
  int safe = SafeMode.server,
]) => AsciidoctorOptions(
  safe: safe,
  attributes: {'allow-uri-read': '', ...attributes},
);

/// Runs [body] with a memory logger installed and returns its messages.
Future<List<String>> loggedBy(Future<void> Function() body) async {
  final saved = LoggerManager.logger;
  final logger = MemoryLogger();
  LoggerManager.logger = logger;
  try {
    await body();
  } finally {
    LoggerManager.logger = saved;
  }
  return [for (final record in logger.messages) '${record.message}'];
}

void main() {
  group('convertAsync', () {
    test('fetches a remote include', () async {
      final server = FileServer({'/inc.adoc': 'included *text*\n'});
      await server.start();
      final output = await convertAsync(
        'include::${server.base}/inc.adoc[]',
        remoteOptions(),
      );
      expect(output, contains('included <strong>text</strong>'));
      expect(server.hits['/inc.adoc'], equals(1));
    });

    test('follows includes nested in fetched content', () async {
      final server = FileServer({
        '/docs/outer.adoc': 'outer\n\ninclude::inner.adoc[]\n',
        '/docs/inner.adoc': 'inner\n',
      });
      await server.start();
      final output = await convertAsync(
        'include::${server.base}/docs/outer.adoc[]',
        remoteOptions(),
      );
      expect(output, contains('<p>outer</p>'));
      expect(output, contains('<p>inner</p>'));
    });

    test('embeds a remote image as a data URI', () async {
      final server = FileServer({'/dot.png': 'PNG'});
      await server.start();
      final output = await convertAsync(
        'image::${server.base}/dot.png[Dot]',
        remoteOptions({'data-uri': ''}),
      );
      expect(
        output,
        contains(
          'src="data:image/png;base64,${base64Encode(utf8.encode('PNG'))}"',
        ),
      );
    });

    test('warns once for content that cannot be fetched', () async {
      final server = FileServer({});
      await server.start();
      late String output;
      final messages = await loggedBy(() async {
        output = await convertAsync(
          'before\n\ninclude::${server.base}/missing.adoc[]\n\nafter',
          remoteOptions(),
        );
      });
      expect(output, contains('<p>after</p>'));
      expect(messages, hasLength(1));
      expect(messages.single, contains('include uri not readable'));
    });

    test('fetches nothing without allow-uri-read', () async {
      final server = FileServer({'/inc.adoc': 'included\n'});
      await server.start();
      final output = await convertAsync(
        'include::${server.base}/inc.adoc[]',
        const AsciidoctorOptions(safe: SafeMode.server),
      );
      expect(server.hits, isEmpty);
      expect(output, contains('href="${server.base}/inc.adoc"'));
    });

    test('uses the given fetcher', () async {
      final requested = <Uri>[];
      final output = await convertAsync(
        'include::https://example.org/inc.adoc[]',
        remoteOptions(),
        (uri) async {
          requested.add(uri);
          return (body: utf8.encode('fetched\n'), contentType: null);
        },
      );
      expect(requested, equals([Uri.parse('https://example.org/inc.adoc')]));
      expect(output, contains('<p>fetched</p>'));
    });

    test('keeps fetched content across conversions with cache-uri', () async {
      final server = FileServer({'/cached.adoc': 'cached\n'});
      await server.start();
      final input = 'include::${server.base}/cached.adoc[]';
      final options = remoteOptions({'cache-uri': ''});
      await convertAsync(input, options);
      final output = await convertAsync(input, options);
      expect(output, contains('<p>cached</p>'));
      expect(server.hits['/cached.adoc'], equals(1));
    });

    test('logs messages from the final conversion only', () async {
      final server = FileServer({'/inc.adoc': 'text {undefined}\n'});
      await server.start();
      final messages = await loggedBy(() async {
        await convertAsync(
          'include::${server.base}/inc.adoc[]',
          remoteOptions({'attribute-missing': 'warn'}),
        );
      });
      expect(
        messages,
        equals(['skipping reference to missing attribute: undefined']),
      );
    });
  });

  group('loadAsync and file variants', () {
    test('loadAsync parses fetched includes', () async {
      final server = FileServer({'/inc.adoc': '== Included Section\n'});
      await server.start();
      final doc = await loadAsync(
        'include::${server.base}/inc.adoc[]',
        options: remoteOptions(),
      );
      expect(doc.sections.single.title, equals('Included Section'));
    });

    test('loadFileAsync and convertFileAsync read the file', () async {
      final server = FileServer({'/inc.adoc': 'remote\n'});
      await server.start();
      final dir = Directory.systemTemp.createTempSync('load_async_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final input = File('${dir.path}/doc.adoc')
        ..writeAsStringSync('include::${server.base}/inc.adoc[]\n');

      final doc = await loadFileAsync(input.path, options: remoteOptions());
      expect(doc.blocks.single.contextName, equals('paragraph'));

      final output = StringBuffer();
      await convertFileAsync(input.path, remoteOptions(), output);
      expect(output.toString(), contains('<p>remote</p>'));
    });

    test('convertToTargetAsync writes to the sink', () async {
      final server = FileServer({'/inc.adoc': 'remote\n'});
      await server.start();
      final output = StringBuffer();
      await convertToTargetAsync(
        'include::${server.base}/inc.adoc[]',
        remoteOptions(),
        output,
      );
      expect(output.toString(), contains('<p>remote</p>'));
    });
  });

  group('uriReader option', () {
    test('serves remote content to the synchronous API', () {
      final requested = <String>[];
      final output = convert(
        'include::https://example.org/inc.adoc[]',
        remoteOptions().copyWith(
          uriReader: (uri) {
            requested.add(uri);
            return (
              body: utf8.encode('read by the reader\n'),
              contentType: null,
            );
          },
        ),
      );
      expect(requested, equals(['https://example.org/inc.adoc']));
      expect(output, contains('<p>read by the reader</p>'));
    });

    test('a failing reader makes the content unreadable', () async {
      final messages = await loggedBy(() async {
        convert(
          'include::https://example.org/inc.adoc[]',
          remoteOptions().copyWith(
            uriReader: (uri) => throw const AsciidoctorException('offline'),
          ),
        );
      });
      expect(messages.single, contains('include uri not readable'));
    });
  });
}
