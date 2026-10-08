/// Runs conversion jobs for `-j` on the pool of worker isolates (see
/// `parallel.dart`), or one after another where there is none
/// (JavaScript), with the same results in both cases.
library;

import 'package:ptome/src/cli/parallel.dart';
import 'package:ptome/src/parallel.dart';

/// A file's conversion on a worker (converted serially there: the files
/// are the parallel work).
final class _Conversion extends Job<ConversionResponse> {
  const new(this.request, this.setup);

  final ConversionRequest request;

  /// What the command registered (its backends), registered again on the
  /// worker.
  final void Function()? setup;

  @override
  Future<ConversionResponse> run() {
    Parallel.nested = true;
    setup?.call();
    return runConversionJob(request);
  }
}

/// Converts [requests] on [workerCount] workers, each [setup] first (it
/// must be idempotent), returning the responses in request order.
Future<List<ConversionResponse>> convertOnWorkers(
  List<ConversionRequest> requests,
  int workerCount, {
  void Function()? setup,
}) async {
  final pool = Parallel.ofSize(workerCount);
  // (Serially, one at a time: a conversion has the logger to itself.)
  if (pool.workers == 0) {
    return [for (final request in requests) await runConversionJob(request)];
  }
  return await Future.wait([
    for (final request in requests) pool.submit(_Conversion(request, setup)),
  ]);
}
