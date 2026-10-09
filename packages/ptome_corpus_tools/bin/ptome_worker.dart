// A long-lived ptome conversion server speaking drivers/ruby/worker.rb's
// protocol, so the fuzzer can run ptome in its own process (a hang or a
// crash costs one process, never the harness).
//
// Writes a header line {"ready": true, "version": ...}, then one response
// per request line: {"id", "ok", "output" | "output_base64", "log", "err"?,
// "frame"?, "ms"}.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ptome_corpus_tools/ptome_corpus_tools.dart';

Future<void> main() async {
  stdout.writeln(jsonEncode({'ready': true, 'version': 'ptome'}));
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final request = jsonDecode(line) as Map<String, Object?>;
    final conversion = Conversion(
      id: request['id']! as String,
      input: request['input']! as String,
      format: Format.parse(request['backend'] as String? ?? 'html5'),
      baseDir: request['base_dir']! as String,
      doctype: request['doctype'] as String?,
      safe: Safe.parse(request['safe'] as String? ?? 'safe'),
      standalone: request['standalone'] as bool? ?? false,
      attributes: (request['attributes'] as Map? ?? const {})
          .cast<String, String>(),
    );
    final outcome = convertWithPtome(conversion);
    final response = <String, Object?>{
      'id': conversion.id,
      'ms': outcome.micros / 1000,
    };
    switch (outcome) {
      case Converted(:final output, :final log):
        response['ok'] = true;
        if (output is Uint8List) {
          response['output_base64'] = base64.encode(output);
        } else {
          response['output'] = output;
        }
        response['log'] = [
          for (final entry in log)
            {
              'severity': entry.severity,
              'message': entry.message,
              'lineno': ?entry.line,
            },
        ];
      case Crashed(:final error, :final frame):
        response['ok'] = false;
        response['err'] = error;
        response['frame'] = frame;
        response['log'] = const [];
      case TimedOut():
        response['ok'] = false;
        response['err'] = 'timeout';
        response['log'] = const [];
    }
    stdout.writeln(jsonEncode(response));
  }
}
