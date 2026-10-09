/// The documents Asciidoctor's own tests convert, with the options they
/// pass (`drivers/ruby/capture.rb` records them while the suite runs).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../spec/conversion.dart';
import '../spec/profile.dart';
import 'entry.dart';
import 'source.dart';

String capturePath(RubyProfile profile) =>
    p.join(poolDir, 'capture', '${profile.name}.jsonl');

/// Runs [profile]'s test suite with the capture hook; returns the number of
/// documents recorded.
Future<int> capture(RubyProfile profile, {required String repoRoot}) async {
  final out = File(capturePath(profile))..parent.createSync(recursive: true);
  final result = await Process.run(
    'systemd-run',
    [
      '--user',
      '--scope',
      '-q',
      '-p',
      'MemoryMax=4G',
      '-p',
      'MemorySwapMax=0', //
      'ruby', p.join(repoRoot, 'drivers', 'ruby', 'capture.rb'),
    ],
    workingDirectory: profile.adocRoot,
    environment: {
      'ADOC_ROOT': profile.adocRoot,
      'CAPTURE_OUT': out.path,
      'GEM_HOME': ?profile.gemHome,
      'GEM_PATH': ?profile.gemHome,
      'TZ': 'UTC',
      'LANG': 'C.UTF-8',
    },
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      'ruby',
      ['capture.rb'],
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
  return out.readAsLinesSync().length;
}

/// The pool entries of [profile]'s captured documents: the options Asciidoctor
/// and ptome share become typed fields, the rest pass through to Ruby.
List<PoolEntry> capturedEntries(RubyProfile profile) {
  final file = File(capturePath(profile));
  if (!file.existsSync()) return const [];
  final testDir = p.join(profile.adocRoot, 'test');
  final seen = <String, int>{};
  final entries = <PoolEntry>[];
  for (final line in file.readAsLinesSync()) {
    final record = jsonDecode(line) as Map<String, Object?>;
    if (record.containsKey('capture_error')) continue;
    final test = record['test'] as String? ?? 'unknown';
    final n = seen[test] = (seen[test] ?? 0) + 1;
    final options = Map<String, Object?>.of(
      (record['options'] as Map? ?? const {}).cast(),
    );
    final attributes = _attributes(options.remove('attributes'));
    final baseDir = switch (options.remove('base_dir')) {
      final String dir => p.isAbsolute(dir) ? dir : p.join(testDir, dir),
      _ => testDir,
    };
    // Every entry converts to every format, so the test's backend goes.
    options.remove('backend');
    final standalone =
        options.remove('standalone') ?? options.remove('header_footer');
    final entry = PoolEntry(
      id: 'capture-${profile.name}/$test.$n',
      source: 'capture-${profile.name}',
      baseDir: baseDir,
      path: record['path'] as String?,
      text: record['path'] == null ? record['input'] as String? ?? '' : null,
      doctype: options.remove('doctype') as String?,
      safe: switch (options.remove('safe')) {
        final String name => Safe.values.asNameMap()[name],
        final int level => const {
          0: Safe.unsafe,
          1: Safe.safe,
          10: Safe.server,
          20: Safe.secure,
        }[level],
        _ => null,
      },
      standalone: standalone is bool ? standalone : null,
      attributes: attributes,
      // Options that change nothing about the conversion itself go.
      extra: options..removeWhere((k, _) => _inert.contains(k)),
    );
    entries.add(entry);
  }
  return entries;
}

/// Captured options with no effect on a conversion's output.
const _inert = {
  'to_file',
  'to_dir',
  'mkdirs',
  'parse',
  'warnings',
  'failure_level',
  'catalog_assets',
  'header_footer',
  'standalone',
};

/// Asciidoctor accepts attributes as a hash, an array of `name=value`, or
/// a string of them.
Map<String, String> _attributes(Object? value) {
  final result = <String, String>{};
  void entry(String name, Object? v) {
    switch (v) {
      case null || false:
        result['${name.replaceAll('!', '')}!'] = '';
      case true:
        result[name] = '';
      default:
        if (name.endsWith('!')) {
          result[name] = '';
        } else {
          result[name] = v.toString();
        }
    }
  }

  void pair(String text) {
    final eq = text.indexOf('=');
    if (eq < 0) {
      entry(text, '');
    } else {
      entry(text.substring(0, eq), text.substring(eq + 1));
    }
  }

  switch (value) {
    case final Map<Object?, Object?> map:
      map.forEach((k, v) => entry(k! as String, v));
    case final List<Object?> list:
      for (final item in list) {
        pair(item.toString());
      }
    case final String text:
      for (final item
          in text.split(RegExp(r'\s+')).where((s) => s.isNotEmpty)) {
        pair(item);
      }
  }
  return result;
}
