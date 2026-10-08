/// Remote content: resources read from URIs during a conversion.
library;

/// A resource read from a URI: its bytes and, when known, its media type
/// (for example `image/png`, without parameters).
typedef RemoteResource = ({List<int> body, String? contentType});

/// Reads the resource at a URI synchronously.
///
/// Throws an [Exception] when the resource cannot be read; the conversion
/// then warns and goes on, as it does for any unreadable content.
typedef UriReader = RemoteResource Function(String uri);

/// Fetches the resource at a URI, for the asynchronous entry points.
///
/// Throws when the resource cannot be fetched.
typedef UriFetcher = Future<RemoteResource> Function(Uri uri);
