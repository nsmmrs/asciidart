/// The default [UriFetcher]: HTTP(S) GET through `dart:io`.
library;

import 'dart:io';

import 'package:asciidoctor/src/errors.dart';
import 'package:asciidoctor/src/remote.dart';

/// Fetches [uri] with an HTTP GET, following redirects.
///
/// Throws an [AsciidoctorException] for a response other than 2xx and the
/// underlying [IOException] when the request fails.
Future<RemoteResource> fetchHttp(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    final body = await response.fold<List<int>>(
      <int>[],
      (bytes, chunk) => bytes..addAll(chunk),
    );
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw AsciidoctorException(
        'cannot read $uri: HTTP ${response.statusCode}',
      );
    }
    return (body: body, contentType: response.headers.contentType?.mimeType);
  } finally {
    client.close(force: true);
  }
}
