/// Runs conversion jobs for `-j`: on a pool of isolates on the Dart VM, one
/// after another where isolates are unavailable (JavaScript), with the same
/// results in both cases.
library;

export 'workers_serial.dart' if (dart.library.io) 'workers_isolate.dart';
