// CRC-32, gzip and ZIP: known vectors and round trips, and, where the
// tools are installed, the gzip, zip, unzip, zipinfo and Python zipfile
// programs reading what this package writes and writing what it reads;
// damaged archives are rejected.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:plain_compression/plain_compression.dart';
import 'package:test/test.dart';

bool _has(String tool) =>
    Process.runSync('which', [tool]).exitCode == 0 ||
    Process.runSync('where', [tool], runInShell: true).exitCode == 0;

final bool _tools =
    _has('gzip') &&
    _has('zip') &&
    _has('unzip') &&
    _has('zipinfo') &&
    _has('python3');

ProcessResult _run(String exe, List<String> args, {String? dir}) {
  final r = Process.runSync(exe, args, workingDirectory: dir);
  expect(r.exitCode, 0, reason: '$exe ${args.join(' ')}: ${r.stderr}');
  return r;
}

/// Checks an archive of ours with Python's zipfile: argv 1 is the archive,
/// argv 2 the file `dir/binary.bin` must equal.
const String _pythonChecks = '''
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
assert z.testzip() is None
assert z.read("dir/binary.bin") == open(sys.argv[2], "rb").read()
assert "naïve-ñame.txt" in z.namelist()
''';

/// Writes argv 1 with Python's zipfile: a UTF-8 name, a code page 437
/// name, and an entry with a forced ZIP64 header.
const String _pythonWrites = '''
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("café.txt", "x")
    z.writestr(zipfile.ZipInfo("plain.txt"), "plain")
    with z.open("big.txt", "w", force_zip64=True) as f:
        f.write(b"y" * 100000)
''';

void main() {
  final random = Random(20261008);
  final text = utf8.encode('Plain text, plain bytes. ' * 2000);
  final binary = Uint8List.fromList([
    for (var i = 0; i < 50000; i++) random.nextInt(256),
  ]);

  group('CRC-32', () {
    test('known vectors', () {
      expect(crc32(utf8.encode('123456789')), 0xcbf43926);
      expect(crc32(const []), 0);
      expect(
        crc32(utf8.encode('The quick brown fox jumps over the lazy dog')),
        0x414fa339,
      );
    });

    test('ranges and continuation', () {
      final bytes = utf8.encode('xx123456789yy');
      expect(crc32(bytes, start: 2, end: 11), 0xcbf43926);
      final first = crc32(utf8.encode('12345'));
      expect(crc32(utf8.encode('6789'), crc: first), 0xcbf43926);
    });
  });

  group('gzip', () {
    test('round trips, at every level', () {
      for (final data in [<int>[], text, binary]) {
        for (var level = 0; level <= 9; level++) {
          expect(gzipDecode(gzipEncode(data, level: level)), data);
        }
      }
    });

    test('the same bytes for the same input', () {
      expect(gzipEncode(text), gzipEncode(text));
      expect(gzipEncode(text).sublist(0, 10), [
        0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 255, //
      ]);
    });

    test('damaged data throws FormatExceptions', () {
      final good = gzipEncode(text);
      for (final bad in [
        good.sublist(0, good.length - 1),
        [...good]..[good.length - 5] ^= 1, // CRC
        [...good]..[2] = 7, // method
        utf8.encode('not gzip at all, but long enough'),
      ]) {
        expect(() => gzipDecode(bad), throwsFormatException);
      }
    });

    test(
      'reads what gzip writes (names, levels, members), and gzip reads ours',
      () {
        final tmp = Directory.systemTemp.createTempSync('gzip_test.');
        addTearDown(() => tmp.deleteSync(recursive: true));
        final file = File('${tmp.path}/data.txt')..writeAsBytesSync(text);
        for (final level in ['-1', '-6', '-9']) {
          // gzip -c keeps the file name and time in the header (FNAME).
          final r = Process.runSync('gzip', [
            '-c',
            level,
            file.path,
          ], stdoutEncoding: null);
          expect(gzipDecode(r.stdout as List<int>), text);
        }
        final one = gzipEncode(utf8.encode('one,'));
        final two = gzipEncode(utf8.encode('two'));
        expect(utf8.decode(gzipDecode([...one, ...two])), 'one,two');
        final ours = File('${tmp.path}/ours.gz')
          ..writeAsBytesSync(gzipEncode(binary, level: 9));
        _run('gzip', ['-t', ours.path]);
        final back = Process.runSync('gzip', [
          '-dc',
          ours.path,
        ], stdoutEncoding: null);
        expect(back.stdout, binary);
      },
      skip: _tools ? false : 'gzip, zip, unzip, zipinfo or python3 missing',
      tags: ['tools'],
    );
  });

  group('ZIP', () {
    Uint8List archive({bool zip64 = false}) =>
        (ZipWriter(zip64: zip64)
              ..add(
                'mimetype',
                utf8.encode('application/epub+zip'),
                method: ZipMethod.stored,
              )
              ..add('text.txt', text)
              ..add('dir/binary.bin', binary)
              ..add('dir/empty', const [])
              ..add('naïve-ñame.txt', utf8.encode('unicode name')))
            .finish();

    test('round trips', () {
      for (final zip64 in [false, true]) {
        final entries = readZip(archive(zip64: zip64));
        expect(
          [for (final e in entries) e.name],
          [
            'mimetype',
            'text.txt',
            'dir/binary.bin',
            'dir/empty',
            'naïve-ñame.txt',
          ],
        );
        expect(entries[0].method, ZipMethod.stored);
        expect(utf8.decode(entries[0].bytes), 'application/epub+zip');
        expect(entries[1].bytes, text);
        expect(entries[2].bytes, binary);
        expect(entries[3].bytes, isEmpty);
      }
    });

    test('reproducible, with the layout EPUB containers need', () {
      final a = archive();
      expect(archive(), a);
      // The first entry stored, its name and data at fixed offsets
      // (OCF: "mimetype" at byte 30, its value right after).
      expect(latin1.decode(a.sublist(30, 38)), 'mimetype');
      expect(latin1.decode(a.sublist(38, 58)), 'application/epub+zip');
      // A deflated entry compressed with the given function.
      var calls = 0;
      final zip = ZipWriter(
        deflate: (bytes) {
          calls++;
          return deflate(bytes, level: 1);
        },
      )..add('a', text);
      expect(readZip(zip.finish()).single.bytes, text);
      expect(calls, 1);
    });

    test('more than 65,535 entries: ZIP64', () {
      final zip = ZipWriter();
      for (var i = 0; i < 70000; i++) {
        zip.add('f$i', [i & 0xff], method: ZipMethod.stored);
      }
      final entries = readZip(zip.finish());
      expect(entries, hasLength(70000));
      expect(entries.last.name, 'f69999');
      expect(entries.last.bytes, [69999 & 0xff]);
    });

    test('damaged archives are read or rejected with FormatExceptions', () {
      final good = archive();
      for (var i = 0; i < 3000; i++) {
        final copy = Uint8List.fromList(good);
        for (var k = 0; k < 1 + random.nextInt(6); k++) {
          copy[random.nextInt(copy.length)] = random.nextInt(256);
        }
        final input = i % 3 == 0
            ? Uint8List.sublistView(copy, 0, random.nextInt(copy.length))
            : copy;
        try {
          readZip(input);
        } on FormatException {
          // Rejected, as it should be.
        }
      }
      expect(
        () => readZip(utf8.encode('PK not really')),
        throwsFormatException,
      );
    });

    test(
      'unzip, zipinfo and Python read ours; we read zip and Python',
      () {
        final tmp = Directory.systemTemp.createTempSync('zip_test.');
        addTearDown(() => tmp.deleteSync(recursive: true));
        for (final zip64 in [false, true]) {
          final ours = File('${tmp.path}/ours$zip64.zip')
            ..writeAsBytesSync(archive(zip64: zip64));
          _run('unzip', ['-tq', ours.path]);
          final info = _run('zipinfo', ['-v', ours.path]).stdout as String;
          expect(info, contains('text.txt'));
          _run('python3', [
            '-I',
            '-c',
            _pythonChecks,
            ours.path,
            (File('${tmp.path}/binary.bin')..writeAsBytesSync(binary)).path,
          ]);
        }
        // Theirs: zip (deflated and stored), Python (code page 437 names,
        // UTF-8 names, forced ZIP64).
        Directory('${tmp.path}/src/sub').createSync(recursive: true);
        File('${tmp.path}/src/a.txt').writeAsBytesSync(text);
        File('${tmp.path}/src/sub/b.bin').writeAsBytesSync(binary);
        _run('zip', ['-qr', '../zipped.zip', '.'], dir: '${tmp.path}/src');
        _run('zip', ['-qr0', '../stored.zip', '.'], dir: '${tmp.path}/src');
        for (final name in ['zipped', 'stored']) {
          final entries = {
            for (final e in readZip(
              File('${tmp.path}/$name.zip').readAsBytesSync(),
            ))
              e.name: e.bytes,
          };
          expect(entries['a.txt'], text, reason: name);
          expect(entries['sub/b.bin'], binary, reason: name);
        }
        _run('python3', ['-I', '-c', _pythonWrites, '${tmp.path}/python.zip']);
        final python = {
          for (final e in readZip(
            File('${tmp.path}/python.zip').readAsBytesSync(),
          ))
            e.name: e.bytes,
        };
        expect(utf8.decode(python['café.txt']!), 'x');
        expect(utf8.decode(python['plain.txt']!), 'plain');
        expect(python['big.txt'], List.filled(100000, 0x79));
      },
      skip: _tools ? false : 'gzip, zip, unzip, zipinfo or python3 missing',
      tags: ['tools'],
    );
  });
}
