/// The default [UriFetcher] of the asynchronous entry points.
library;

import 'package:asciidoctor/src/io.dart' as io;
import 'package:asciidoctor/src/remote.dart';

/// Fetches [uri] with an HTTP GET, following redirects: through `dart:io`
/// on the Dart VM and the global `fetch` on JavaScript.
///
/// Throws an `AsciidoctorException` for a response other than 2xx, and
/// the platform's error when the request fails.
Future<RemoteResource> fetchHttp(Uri uri) => io.fetchUri(uri);
