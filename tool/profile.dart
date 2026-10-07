/// Profiles the asciidart CLI: runs `bin/asciidart.dart` on the Dart VM
/// with its service on, collects the CPU samples when the program ends,
/// and prints the functions where the time goes.
///
/// ```sh
/// dart run tool/profile.dart [--top N] [--period MICROS] [--callers NAME]
///     [--] ARGS...
/// ```
///
/// ARGS are the CLI's (run from the current directory). Two tables: by
/// self time (the function on top of the stack) and by inclusive time (the
/// function anywhere on the stack), each with the share of all samples;
/// with `--callers NAME` (repeatable), the callers (outside its library and
/// the core's) of the samples with a function named NAME on top.
/// The VM runs the code JIT-compiled, so the shares are close to, not the
/// same as, the native executable's.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  var top = 40;
  var period = 250;
  final callersOf = <String>[];
  final cliArgs = <String>[];
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--top':
        top = int.parse(args[++i]);
      case '--period':
        period = int.parse(args[++i]);
      case '--callers':
        callersOf.add(args[++i]);
      case '--':
        cliArgs.addAll(args.sublist(i + 1));
        i = args.length;
      default:
        cliArgs.add(args[i]);
    }
  }
  final script = File.fromUri(Platform.script.resolve('../bin/asciidart.dart'))
      .path;
  final process = await Process.start(Platform.resolvedExecutable, [
    '--observe=0',
    '--disable-service-auth-codes',
    '--pause-isolates-on-exit',
    '--profile-period=$period',
    script,
    ...cliArgs,
  ]);
  final uri = Completer<String>();
  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (line) {
      final match = RegExp(r'listening on (http://\S+)').firstMatch(line);
      if (match != null && !uri.isCompleted) {
        uri.complete(match[1]);
      } else if (uri.isCompleted) {
        stdout.writeln(line);
      }
    },
  );
  process.stderr.transform(utf8.decoder).listen(stderr.write);
  final http = Uri.parse(await uri.future);
  final ws = http.replace(
    scheme: 'ws',
    path: '${http.path.endsWith('/') ? http.path : '${http.path}/'}ws',
  );
  final service = await vmServiceConnectUri(ws.toString());
  final watch = Stopwatch()..start();
  // Wait for the main isolate to end (paused at its exit).
  String? isolateId;
  while (isolateId == null) {
    final vm = await service.getVM();
    for (final ref in vm.isolates ?? const <IsolateRef>[]) {
      final isolate = await service.getIsolate(ref.id!);
      if (isolate.pauseEvent?.kind == EventKind.kPauseExit) {
        isolateId = ref.id;
      }
    }
    if (isolateId == null) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  final wall = watch.elapsedMilliseconds;
  final samples = await service.getCpuSamples(isolateId, 0, 1 << 62);
  final functions = samples.functions ?? const <ProfileFunction>[];
  String nameOf(int index) {
    final function = functions[index].function;
    final owner = switch (function) {
      FuncRef(:final owner) => switch (owner) {
        ClassRef(:final name) => '$name.',
        _ => '',
      },
      _ => '',
    };
    final name = switch (function) {
      FuncRef(:final name) => name,
      NativeFunction(:final name) => name,
      _ => '$function',
    };
    final library = switch (functions[index].resolvedUrl) {
      final String url when url.isNotEmpty => url.split('/').last,
      _ => '',
    };
    return '$owner$name ($library)';
  }

  final self = <int, int>{};
  final inclusive = <int, int>{};
  final all = samples.samples ?? const <CpuSample>[];
  for (final sample in all) {
    final stack = sample.stack ?? const <int>[];
    if (stack.isEmpty) continue;
    self.update(stack.first, (n) => n + 1, ifAbsent: () => 1);
    for (final index in stack.toSet()) {
      inclusive.update(index, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  void table(String title, Map<int, int> counts) {
    stdout.writeln('\n$title (${all.length} samples, ~$wall ms to exit):');
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in entries.take(top)) {
      final share = (100 * entry.value / all.length).toStringAsFixed(1);
      stdout.writeln('${share.padLeft(6)}%  ${nameOf(entry.key)}');
    }
  }

  table('Self', self);
  table('Inclusive', inclusive);
  // The first frame up the stack outside [name]'s library, for each
  // sample with [name] on top (who calls into it).
  for (final name in callersOf) {
    final callers = <String, int>{};
    var total = 0;
    for (final sample in all) {
      final stack = sample.stack ?? const <int>[];
      if (stack.isEmpty || !nameOf(stack.first).contains(name)) continue;
      total++;
      final library = nameOf(stack.first).split('(').last;
      final caller = stack
          .skip(1)
          .map(nameOf)
          .firstWhere(
            (frame) =>
                !frame.endsWith(library) &&
                !frame.contains('(regexp_patch') &&
                !frame.contains('(string_patch') &&
                !frame.contains('(iterable.dart') &&
                !frame.contains('(core_patch'),
            orElse: () => '?',
          );
      callers.update(caller, (n) => n + 1, ifAbsent: () => 1);
    }
    stdout.writeln('\nCallers of $name ($total samples on top):');
    final entries = callers.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in entries.take(top)) {
      final share = (100 * entry.value / all.length).toStringAsFixed(1);
      stdout.writeln('${share.padLeft(6)}%  ${entry.key}');
    }
  }
  await service.resume(isolateId);
  await service.dispose();
  await process.exitCode;
}
