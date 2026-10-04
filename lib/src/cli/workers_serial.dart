/// `-j` conversion jobs without isolates (see `workers.dart`).
library;

import 'package:asciidoctor/src/cli/parallel.dart';

/// Converts [requests] one after another, returning the responses in
/// request order; [workerCount] has no effect without isolates.
Future<List<ConversionResponse>> convertOnWorkers(
  List<ConversionRequest> requests,
  int workerCount,
) async => [for (final request in requests) await runConversionJob(request)];
