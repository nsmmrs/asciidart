/// Long-lived Asciidoctor processes (`drivers/ruby/worker.rb`) that convert
/// over an NDJSON pipe, so interpreter startup is paid once per worker.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../spec/conversion.dart';
import '../spec/profile.dart';

/// Every relevant line and branch arm of an Asciidoctor checkout's `lib/`.
final class CoverageUniverse {
  const CoverageUniverse(
    this.lines,
    this.branches, {
    this.loadTimeLines = const [],
    this.loadTimeBranches = const [],
  });

  /// `file:line`.
  final List<String> lines;

  /// `file:line:col:type:arm@line:col`.
  final List<String> branches;

  /// What loading alone reaches (class bodies, constants): covered by every
  /// conversion, but never reported per case.
  final List<int> loadTimeLines;
  final List<int> loadTimeBranches;

  Map<String, Object> toJson() => {
    'lines': lines,
    'branches': branches,
    'load_time': {'lines': loadTimeLines, 'branches': loadTimeBranches},
  };

  static CoverageUniverse fromJson(
    Map<String, Object?> json, {
    Map<String, Object?>? loadTime,
  }) {
    final load = loadTime ?? json['load_time'] as Map<String, Object?>?;
    return CoverageUniverse(
      (json['lines']! as List).cast<String>(),
      (json['branches']! as List).cast<String>(),
      loadTimeLines: (load?['lines'] as List? ?? const []).cast<int>(),
      loadTimeBranches: (load?['branches'] as List? ?? const []).cast<int>(),
    );
  }
}

/// One worker process.
final class RubyWorker {
  RubyWorker._(
    this._process,
    Stream<String> lines,
    this._stderr,
    this.version,
    this.universe,
  ) {
    lines.listen(_onLine, onDone: _onExit);
  }

  final Process _process;
  final StringBuffer _stderr;

  /// `Asciidoctor::VERSION` of the checkout.
  final String version;

  /// Set when the worker runs with coverage.
  final CoverageUniverse? universe;

  final Queue<(Conversion, Completer<Outcome>, Stopwatch)> _pending = Queue();
  bool _dead = false;

  static Future<RubyWorker> start(
    RubyProfile profile, {
    required String repoRoot,
    bool coverage = false,
  }) async {
    final worker = p.join(repoRoot, 'drivers', 'ruby', 'worker.rb');
    final env = {
      ...Platform.environment,
      'ADOC_ROOT': profile.adocRoot,
      'TZ': 'UTC',
      'LANG': 'C.UTF-8',
      if (profile.gemHome != null) 'GEM_HOME': profile.gemHome!,
      if (profile.gemHome != null) 'GEM_PATH': profile.gemHome!,
    };
    final ruby = ['ruby', worker, if (coverage) '--coverage'];
    // A memory cap keeps a runaway input from taking the machine down.
    final command = profile.memoryMax == null
        ? ruby
        : [
            'systemd-run',
            '--user',
            '--scope',
            '-q',
            '-p',
            'MemoryMax=${profile.memoryMax}',
            '-p',
            'MemorySwapMax=0',
            ...ruby,
          ];
    final process = await Process.start(
      command.first,
      command.skip(1).toList(),
      environment: env,
      includeParentEnvironment: false,
    );
    final stderrText = StringBuffer();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .forEach(stderrText.write);
    final lines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    // The header arrives first; the rest of stdout goes to the worker.
    final controller = StreamController<String>();
    final header = Completer<Map<String, Object?>>();
    lines.listen(
      (line) => header.isCompleted
          ? controller.add(line)
          : header.complete(jsonDecode(line) as Map<String, Object?>),
      onDone: () {
        if (!header.isCompleted) {
          stderrDone.then((_) {
            header.completeError(
              StateError('Ruby worker exited before its header:\n$stderrText'),
            );
          });
        }
        controller.close();
      },
    );
    final head = await header.future;
    final universe = head['universe'] as Map<String, Object?>?;
    final loadTime = head['load_time'] as Map<String, Object?>?;
    return RubyWorker._(
      process,
      controller.stream,
      stderrText,
      head['version']! as String,
      universe == null
          ? null
          : CoverageUniverse.fromJson(universe, loadTime: loadTime),
    );
  }

  int get pending => _pending.length;
  bool get dead => _dead;

  /// Converts [conversion]; times out after [timeout] by killing the worker.
  Future<Outcome> convert(
    Conversion conversion, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    if (_dead) {
      return Future.error(StateError('Ruby worker is dead: $_stderr'));
    }
    final completer = Completer<Outcome>();
    final watch = Stopwatch()..start();
    _pending.add((conversion, completer, watch));
    _process.stdin.writeln(jsonEncode(conversion.toJson()));
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        kill();
        return TimedOut(id: conversion.id, micros: watch.elapsedMicroseconds);
      },
    );
  }

  void _onLine(String line) {
    if (_pending.isEmpty) return;
    final (conversion, completer, _) = _pending.removeFirst();
    final json = jsonDecode(line) as Map<String, Object?>;
    final micros = ((json['ms']! as num) * 1000).round();
    final coverage = json.containsKey('lines')
        ? CaseCoverage(
            (json['lines']! as List).cast<int>(),
            (json['branches']! as List).cast<int>(),
          )
        : null;
    if (completer.isCompleted) return;
    if (json['ok'] == true) {
      completer.complete(
        Converted(
          id: conversion.id,
          micros: micros,
          output: json['output']! as String,
          log: [
            for (final entry
                in (json['log']! as List).cast<Map<String, Object?>>())
              LogEntry(
                entry['severity']! as String,
                entry['message']! as String,
                line: entry['lineno'] as int?,
              ),
          ],
          coverage: coverage,
        ),
      );
    } else {
      completer.complete(
        Crashed(
          id: conversion.id,
          micros: micros,
          error: json['err']! as String,
          frame: json['frame'] as String?,
          coverage: coverage,
        ),
      );
    }
  }

  void _onExit() {
    _dead = true;
    while (_pending.isNotEmpty) {
      final (conversion, completer, watch) = _pending.removeFirst();
      if (!completer.isCompleted) {
        completer.complete(
          Crashed(
            id: conversion.id,
            micros: watch.elapsedMicroseconds,
            error: 'worker exited: ${_stderr.toString().trim()}',
          ),
        );
      }
    }
  }

  void kill() {
    _dead = true;
    _process.kill(ProcessSignal.sigkill);
  }

  Future<void> close() async {
    await _process.stdin.close();
    await _process.exitCode;
  }
}

/// [size] workers of one profile; conversions go to the least busy one, and
/// a worker that dies (timeout, crash) is replaced.
final class RubyPool {
  RubyPool._(this.profile, this._repoRoot, this._coverage, this._workers);

  final RubyProfile profile;
  final String _repoRoot;
  final bool _coverage;
  final List<RubyWorker> _workers;

  static Future<RubyPool> start(
    RubyProfile profile, {
    required String repoRoot,
    int size = 1,
    bool coverage = false,
  }) async {
    final workers = await Future.wait([
      for (var i = 0; i < size; i++)
        RubyWorker.start(profile, repoRoot: repoRoot, coverage: coverage),
    ]);
    return RubyPool._(profile, repoRoot, coverage, workers);
  }

  String get version => _workers.first.version;
  CoverageUniverse? get universe => _workers.first.universe;

  Future<Outcome> convert(
    Conversion conversion, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    for (var i = 0; i < _workers.length; i++) {
      if (_workers[i].dead) {
        _workers[i] = await RubyWorker.start(
          profile,
          repoRoot: _repoRoot,
          coverage: _coverage,
        );
      }
    }
    var best = _workers.first;
    for (final worker in _workers) {
      if (worker.pending < best.pending) best = worker;
    }
    return best.convert(conversion, timeout: timeout);
  }

  /// Converts every conversion, one at a time per worker (so each time
  /// limit covers only its own conversion), in completion order.
  Stream<Outcome> convertAll(
    Iterable<Conversion> conversions, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    final next = conversions.iterator;
    final out = StreamController<Outcome>();
    Future<void> lane(int i) async {
      while (next.moveNext()) {
        final conversion = next.current;
        if (_workers[i].dead) {
          _workers[i] = await RubyWorker.start(
            profile,
            repoRoot: _repoRoot,
            coverage: _coverage,
          );
        }
        out.add(await _workers[i].convert(conversion, timeout: timeout));
      }
    }

    Future.wait([for (var i = 0; i < _workers.length; i++) lane(i)])
        .whenComplete(out.close);
    return out.stream;
  }

  Future<void> close() => Future.wait([
    for (final worker in _workers)
      if (!worker.dead) worker.close(),
  ]);
}
