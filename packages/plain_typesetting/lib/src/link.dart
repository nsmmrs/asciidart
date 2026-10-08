/// Where a link goes: a web address or a named destination; a backend
/// adds its own kinds (plain_pdf's explicit destinations).
library;

import 'package:meta/meta.dart';

/// Where a link goes.
@immutable
abstract base class LinkTarget {
  /// A target (for subclasses).
  const new();

  /// The web address [uri].
  const factory uri(String uri) = UriTarget;

  /// The named destination [name].
  const factory named(String name) = NamedTarget;
}

/// A web address.
final class UriTarget extends LinkTarget {
  /// A link to [uri].
  const new(this.uri);

  /// The address.
  final String uri;
}

/// A named destination.
final class NamedTarget extends LinkTarget {
  /// A link to the destination [name].
  const new(this.name);

  /// The destination's name.
  final String name;
}
