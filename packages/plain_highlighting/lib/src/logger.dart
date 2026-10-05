/// Diagnostics from the engine (`src/lib/logger.js` upstream logs to the
/// console). A library should not print, so messages go to [sink], which
/// discards them unless set.
library;

/// Receives the engine's messages (default: none).
void Function(String message)? sink;

/// Reports an error.
void error(String message) => sink?.call('ERROR: $message');

/// Reports a warning.
void warn(String message) => sink?.call('WARN: $message');
