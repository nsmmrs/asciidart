/// `-j` conversion jobs on a pool of worker isolates (see `workers.dart`).
library;

import 'dart:isolate';

import 'package:asciidart/src/cli/parallel.dart';
import 'package:asciidart/src/job_pool.dart';
import 'package:asciidart/src/parallel.dart';

/// Worker isolate entry point for conversion jobs (each converted
/// serially: the files are the parallel work).
void conversionWorkerMain(SendPort mainPort) {
  Parallel.nested = true;
  serveJobs<ConversionRequest, ConversionResponse>(
    mainPort,
    runConversionJob,
  );
}

/// Converts [requests] on [workerCount] worker isolates, returning the
/// responses in request order.
Future<List<ConversionResponse>> convertOnWorkers(
  List<ConversionRequest> requests,
  int workerCount,
) async {
  final pool =
      await IsolateJobPool.spawn<ConversionRequest, ConversionResponse>(
        size: workerCount,
        entryPoint: conversionWorkerMain,
      );
  try {
    return await pool.runOrdered(requests);
  } finally {
    await pool.close();
  }
}
