/// The `ascii_docs` subcommands.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import 'commands/check.dart';
import 'commands/regen.dart';
import 'spec/conversion.dart';
import 'spec/corpus.dart';
import 'spec/profile.dart';

final class RegenCommand extends Command<int> {
  RegenCommand() {
    argParser
      ..addMultiOption(
        'profile',
        abbr: 'p',
        help: 'Profiles to run (default: all).',
      )
      ..addFlag(
        'check',
        help: 'Write nothing; fail if a recorded result changed.',
      )
      ..addOption(
        'jobs',
        abbr: 'j',
        defaultsTo: '4',
        help: 'Ruby workers per profile.',
      );
  }

  @override
  String get name => 'regen';

  @override
  String get description =>
      'Convert cases with each profile and record the results.\n'
      'Arguments limit the cases to those whose id starts with one of them.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final corpus = Corpus.open();
    final names = args.multiOption('profile');
    final profiles = [
      for (final MapEntry(:key, :value) in corpus.profiles.entries)
        if (names.isEmpty || names.contains(key)) value,
    ];
    final check = args.flag('check');
    final cases = corpus.cases(args.rest);
    final report = await regen(
      corpus,
      cases,
      profiles: profiles,
      check: check,
      jobs: int.parse(args.option('jobs')!),
    );
    stdout.writeln(
      '${report.converted} conversions, ${cases.length} cases, '
      '${report.changed.length} ${check ? 'mismatched' : 'changed'}',
    );
    for (final id in report.changed) {
      stdout.writeln('  ${check ? 'mismatch' : 'changed'}: $id');
    }
    for (final id in report.undocumented) {
      stdout.writeln(
        '  differs from its reference without a divergence note: $id',
      );
    }
    return (check && report.changed.isNotEmpty) ||
            report.undocumented.isNotEmpty
        ? 1
        : 0;
  }
}

final class TestCommand extends Command<int> {
  TestCommand() {
    argParser.addMultiOption(
      'format',
      abbr: 'f',
      help: 'Formats to check (default: all).',
      allowed: [for (final f in Format.values) f.name],
    );
  }

  @override
  String get name => 'test';

  @override
  String get description =>
      'Convert cases with asciidart and compare with the recorded results.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final corpus = Corpus.open();
    final profile = corpus.profiles.values.whereType<AsciidartProfile>().single;
    final cases = corpus.cases(args.rest);
    final report = checkCases(
      cases,
      profile,
      formats: {
        for (final name in args.multiOption('format')) Format.parse(name),
      },
    );
    for (final failure in report.failures) {
      stdout.writeln('FAIL ${failure.testId}\n${failure.detail}');
    }
    stdout.writeln(
      '${report.passed} passed, ${report.failures.length} failed, '
      '${report.skipped} skipped in ${report.watch.elapsedMilliseconds} ms',
    );
    return report.failures.isEmpty ? 0 : 1;
  }
}
