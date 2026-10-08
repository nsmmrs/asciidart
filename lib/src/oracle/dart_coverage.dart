/// asciidart's own coverage, read in-process through the VM service: which
/// coverage points (calls) and branch points of `package:asciidart` have
/// run so far in this isolate group.
///
/// The VM records hits as booleans that never reset, so per-case coverage
/// is the difference between snapshots taken before and after a case.
/// Needs a JIT VM started with `--branch-coverage` for branch points.
library;

import 'dart:developer';
import 'dart:io';
import 'dart:isolate';

import 'package:vm_service/vm_service.dart' hide Isolate;
import 'package:vm_service/vm_service_io.dart';

const _kinds = [SourceReportKind.kCoverage, SourceReportKind.kBranchCoverage];

final class DartCoverage {
  DartCoverage._(this._vm, this._isolate, this._filters);

  final VmService _vm;
  final String _isolate;
  final List<String> _filters;

  /// `uri:pos:kind` of every element, kind `c` (coverage point) or `b`
  /// (branch point); an element's number is its index here.
  final List<String> universe = [];
  final Map<String, int> _index = {};

  /// Whether this VM records branch coverage.
  static bool get branchCoverage =>
      Platform.executableArguments.contains('--branch-coverage');

  /// Connects to this process's VM service (starting it if needed) and
  /// reads the full universe of [libraries] (URI prefixes).
  static Future<DartCoverage> connect({
    List<String> libraries = const ['package:asciidart/'],
  }) async {
    final info = await Service.controlWebServer(
      enable: true,
      silenceOutput: true,
    );
    final vm = await vmServiceConnectUri(info.serverWebSocketUri.toString());
    final coverage = DartCoverage._(
      vm,
      Service.getIsolateId(Isolate.current)!,
      libraries,
    );
    final report = await vm.getSourceReport(
      coverage._isolate,
      _kinds,
      forceCompile: true,
      libraryFilters: libraries,
    );
    coverage._read(report, (_) {});
    return coverage;
  }

  /// The elements hit so far.
  Future<Set<int>> hits() async {
    final report = await _vm.getSourceReport(
      _isolate,
      _kinds,
      libraryFilters: _filters,
    );
    final hit = <int>{};
    _read(report, hit.add);
    return hit;
  }

  void _read(SourceReport report, void Function(int) onHit) {
    int element(String uri, int pos, String kind) {
      final key = '$uri:$pos:$kind';
      return _index[key] ??= (universe..add(key)).length - 1;
    }

    for (final range in report.ranges ?? const <SourceReportRange>[]) {
      final uri = report.scripts![range.scriptIndex!].uri!;
      final c = range.coverage;
      for (final pos in c?.hits ?? const <int>[]) {
        onHit(element(uri, pos, 'c'));
      }
      for (final pos in c?.misses ?? const <int>[]) {
        element(uri, pos, 'c');
      }
      final b = range.branchCoverage;
      for (final pos in b?.hits ?? const <int>[]) {
        onHit(element(uri, pos, 'b'));
      }
      for (final pos in b?.misses ?? const <int>[]) {
        element(uri, pos, 'b');
      }
    }
  }

  Future<void> close() => _vm.dispose();
}
