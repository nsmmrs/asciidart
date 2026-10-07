// A PDF converted with its work on other cores (ADR-0016) is the same,
// byte for byte, as one converted serially, at any number of workers.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:asciidart/src/internal.dart';
import 'package:asciidart/src/pdf/pdf.dart';
import 'package:test/test.dart';

/// A [width] by [height] RGBA PNG, its colors and alpha varying.
Uint8List _png(int width, int height, {int seed = 0}) {
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0);
    for (var x = 0; x < width; x++) {
      raw.add([(x * 7 + seed) & 0xff, (y * 5) & 0xff, 90, (x + y) & 0xff]);
    }
  }
  Uint8List chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    final out = ByteData(8 + data.length + 4)..setUint32(0, data.length);
    out.buffer.asUint8List().setRange(4, 4 + body.length, body);
    out.setUint32(8 + data.length, _crc(body));
    return out.buffer.asUint8List();
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  return Uint8List.fromList([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
    ...chunk('IHDR', header.buffer.asUint8List()),
    ...chunk('IDAT', zlib.encode(raw.takeBytes())),
    ...chunk('IEND', const []),
  ]);
}

int _crc(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var k = 0; k < 8; k++) {
      crc = crc & 1 != 0 ? 0xedb88320 ^ (crc >> 1) : crc >> 1;
    }
  }
  return crc ^ 0xffffffff;
}

void main() {
  setUpAll(registerPdf);

  test('images encoded on workers make the serial bytes', () async {
    final dir = Directory.systemTemp.createTempSync('asciidart-pdf.');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (var i = 0; i < 6; i++) {
      File('${dir.path}/a$i.png').writeAsBytesSync(_png(120, 80, seed: i));
    }
    File('${dir.path}/doc.adoc').writeAsStringSync(
      [
        '= Images',
        '',
        for (var i = 0; i < 6; i++) ...['image::a$i.png[]', ''],
        'image::a0.png[]',
      ].join('\n'),
    );
    AsciidoctorOptions options(String out, String jobs) => AsciidoctorOptions(
      safe: SafeMode.unsafe,
      backend: 'pdf',
      toFile: out,
      attributes: {'jobs': jobs, 'localdatetime': '2020-01-01 00:00:00 +0000'},
    );
    final serial = '${dir.path}/serial.pdf';
    convertFile('${dir.path}/doc.adoc', options(serial, '4'));
    final reference = File(serial).readAsBytesSync();
    for (final jobs in ['1', '3', '4']) {
      final out = '${dir.path}/j$jobs.pdf';
      await convertFileFinishing('${dir.path}/doc.adoc', options(out, jobs));
      expect(File(out).readAsBytesSync(), reference, reason: 'jobs=$jobs');
    }
  });
}
