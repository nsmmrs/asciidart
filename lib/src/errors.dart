/// The exception type for failures caused by the input, the options or the
/// environment, as opposed to programming errors.
library;

/// A failure to load, convert or write a document that is reported to the
/// user as is: an unknown backend or template engine, an input that is not
/// valid UTF-8, an output path that would overwrite the input, a missing
/// target directory, and the like.
///
/// [toString] returns the bare [message], so the error reads well when
/// printed.
class AsciidoctorException implements Exception {
  /// Creates an exception with the given [message].
  const new(this.message);

  /// A description of the failure, without a trailing period.
  final String message;

  @override
  String toString() => message;
}
