/// Tests for the timings port (`lib/src/timings.dart`).
///
/// Ruby ships no dedicated timings tests, so these are direct behavioral
/// tests; every expectation was verified against `lib/asciidoctor/timings.rb`
/// via `ruby -Ilib -e` probes (see the wave report).
library;

import 'package:asciidoctor/src/timings.dart';
import 'package:test/test.dart';

void main() {
  group('Timings', () {
    test('fresh timings report null for every phase', () {
      final timings = Timings();
      expect(timings.read, isNull);
      expect(timings.parse, isNull);
      expect(timings.readParse, isNull);
      expect(timings.convert, isNull);
      expect(timings.readParseConvert, isNull);
      expect(timings.write, isNull);
      expect(timings.total, isNull);
    });

    test('time with no keys or unknown keys returns null', () {
      final timings = Timings();
      expect(timings.time(), isNull);
      expect(timings.time('bogus'), isNull);
      expect(timings.time('bogus', 'nope'), isNull);
    });

    test('recording without starting throws StateError', () {
      // Ruby raises `TypeError: nil can't be coerced into Float` here.
      expect(() => Timings().record('read'), throwsStateError);
    });

    test('start returns a timestamp, record returns the duration', () {
      final timings = Timings();
      final started = timings.start('read');
      expect(started, isA<double>());
      final duration = timings.record('read');
      expect(duration, isA<double>());
      expect(duration, greaterThanOrEqualTo(0));
      expect(timings.read, equals(duration));
    });

    test('starting twice restarts the timer', () {
      final timings = Timings();
      timings.start('parse');
      timings.start('parse');
      expect(timings.record('parse'), greaterThanOrEqualTo(0));
      expect(() => timings.record('parse'), throwsStateError);
    });

    test('phase getters combine recorded phases', () {
      final timings = Timings();
      timings.start('read');
      timings.record('read');
      expect(timings.read, isNotNull);
      expect(timings.parse, isNull);
      expect(timings.readParse, equals(timings.read));
      expect(timings.total, equals(timings.read));

      timings.start('parse');
      timings.record('parse');
      expect(timings.readParse, equals(timings.read! + timings.parse!));

      timings.start('convert');
      timings.record('convert');
      expect(
        timings.readParseConvert,
        equals(timings.readParse! + timings.convert!),
      );

      timings.start('write');
      timings.record('write');
      expect(timings.total, equals(timings.readParseConvert! + timings.write!));
    });

    test('printReport with subject prints four lines', () {
      final timings = Timings();
      timings.start('read');
      timings.record('read');
      timings.start('convert');
      timings.record('convert');
      final buffer = StringBuffer();
      timings.printReport(buffer, 'in.adoc');
      final lines = buffer.toString().split('\n');
      expect(lines, hasLength(5)); // trailing newline yields an empty tail
      expect(lines[0], equals('Input file: in.adoc'));
      expect(
        lines[1],
        matches(r'^  Time to read and parse source: \d+\.\d{5}$'),
      );
      expect(lines[2], matches(r'^  Time to convert document: \d+\.\d{5}$'));
      expect(
        lines[3],
        matches(r'^  Total time \(read, parse and convert\): \d+\.\d{5}$'),
      );
      expect(
        double.parse(lines[3].split(': ').last),
        closeTo(
          double.parse(lines[1].split(': ').last) +
              double.parse(lines[2].split(': ').last),
          0.00001,
        ),
      );
    });

    test('printReport without subject omits the header and zeroes gaps', () {
      final buffer = StringBuffer();
      Timings().printReport(buffer);
      expect(
        buffer.toString(),
        equals(
          '  Time to read and parse source: 0.00000\n'
          '  Time to convert document: 0.00000\n'
          '  Total time (read, parse and convert): 0.00000\n',
        ),
      );
    });

    test('printReport does not lose precision', () {
      final timings = Timings();
      timings.log['read'] = 0.00001;
      timings.log['parse'] = 0.00003;
      timings.log['convert'] = 0.00005;
      final buffer = StringBuffer();
      timings.printReport(buffer);
      const expected = ['0.00004', '0.00005', '0.00009'];
      // Port of `l.sub(/.*:\s*([\d.]+)/, '\1')`.
      final result = buffer
          .toString()
          .trim()
          .split('\n')
          .map(
            (line) =>
                RegExp(r'.*:\s*([\d.]+)').firstMatch(line)?.group(1) ?? line,
          )
          .toList();
      expect(result, orderedEquals(expected));
    });
  });
}
