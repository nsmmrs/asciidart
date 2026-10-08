import 'package:ptome/src/text_case.dart';
import 'package:test/test.dart';

void main() {
  group('case mapping as Ruby performs it', () {
    test('ASCII', () {
      expect(upcase('Hello, World 1!'), equals('HELLO, WORLD 1!'));
      expect(downcase('Hello, World 1!'), equals('hello, world 1!'));
    });

    test('special upper-case mappings expand', () {
      expect(upcase('Das große Ganze'), equals('DAS GROSSE GANZE'));
      expect(upcase('ﬁle ŉ'), equals('FILE ʼN'));
    });

    test('lower case has no final sigma and keeps the dot of İ', () {
      expect(downcase('ΑΣ ΒΣ'), equals('ασ βσ'));
      expect(downcase('İ').runes, equals([0x69, 0x307]));
    });

    test('code points newer than the platform tables', () {
      // Latin Capital Letter Middle Scots S (Unicode 17).
      expect(upcase(String.fromCharCode(0x019b)), equals('\u{a7dc}'));
    });

    test('characters without a case mapping are kept', () {
      expect(upcase('日本語 – ✓'), equals('日本語 – ✓'));
    });
  });
}
