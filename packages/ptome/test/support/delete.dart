/// Deletes a directory with what is in it, where the platform can (the
/// Dart VM); a no-op elsewhere.
library;

export 'delete_none.dart' if (dart.library.io) 'delete_vm.dart';
