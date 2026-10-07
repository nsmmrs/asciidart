/// The entry point of the npm package's compiled core.
///
/// Running the bundle installs the projection of the public API
/// (`api.g.dart`) as `globalThis.asciidartCore`, which `npm/src/core.js`
/// initializes and the generated `npm/src/api.g.js` calls into.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:asciidart/src/api/file_backends_js.dart';
import 'package:asciidart/src/cli/run.dart' show runCliCode;
import 'package:asciidart/src/js/api.g.dart';
import 'package:asciidart/src/js/runtime.dart';

/// The real global object (the bundle's own `self` shadows it; see
/// `npm/preamble.js`).
@JS('globalThis')
external JSObject get _global;

void main() {
  final core = createJSInteropWrapper<Core>(Core())
    ..setProperty('init'.toJS, initRuntime.toJS)
    ..setProperty(
      'runCli'.toJS,
      ((JSArray<JSString> args) => promise(
        _runCli([for (final a in args.toDart) a.toDart]),
        (code) => code.toJS,
      )).toJS,
    );
  _global.setProperty('asciidartCore'.toJS, core);
}

/// Runs the command line with [args], loading the part of the bundle of a
/// backend that makes files (`-b pdf`, `--backend=epub3`) first.
Future<int> _runCli(List<String> args) async {
  for (final (i, arg) in args.indexed) {
    final backend = switch (arg) {
      '-b' || '--backend' when i + 1 < args.length => args[i + 1],
      _ when arg.startsWith('--backend=') => arg.substring(10),
      _ when arg.startsWith('-b') && arg.length > 2 => arg.substring(2),
      _ => null,
    };
    if (backend == 'pdf' || backend == 'epub3') {
      await loadFileBackend(backend!);
    }
  }
  return await runCliCode(args);
}
