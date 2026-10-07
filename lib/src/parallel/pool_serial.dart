/// Where isolates aren't available (JavaScript): no pool, every job runs
/// serially (see `parallel.dart`).
library;

import 'package:asciidart/src/parallel.dart';

/// The serial pool, whatever the size.
Parallel pool(int size) => Parallel.serial;

/// One core.
int get physicalCores => 1;
