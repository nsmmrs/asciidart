// Compiled to JavaScript in CI: reads a WOFF2 font, subsets it and prints
// a digest of the bytes; the CI job compares it with the Dart VM's, as the
// output must be the same bytes on both.
import 'dart:convert';

import 'package:compression/compression.dart' show adler32;
import 'package:fonts/fonts.dart';

void main() {
  final font = OpenTypeFont.parse(base64.decode(_woff2));
  final glyphs = glyphClosure(font, [
    for (final c in 'web'.codeUnits) font.glyphFor(c),
  ]);
  final subset = subsetTrueType(font, glyphs);
  // The digest is the program's output.
  // ignore: avoid_print
  print('${font.familyName} ${adler32(font.bytes)} ${adler32(subset)}');
}

/// Noto Serif, subset to "web fonts", as WOFF2 with its glyf, loca and
/// hmtx tables transformed (by fontTools).
const String _woff2 =
    'd09GMgABAAAAAAQgAA0AAAAABsQAAAPQAAID1wAAAAAAAAAAAAAAAAAAAAAAAAAAGhYbIBw2'
    'BmAAXAqGcIVuATYCJEMoKQsWAAQgBW4HIBtGBSAehU3ZW7hwJpPfasi1ej3yQTz7l7RTs7N2'
    '7tH+sMjD5+31N9l5d2FpFngeWDJI4vhzSJHU/wDhnKdO1U8oF0os0cUUoTVs7WKrc1uV1qby'
    'pF4FywXFalXn2GHkGKY6oIU92AECUAI6KYJSIBPXCEyZI3tscjbkeAD+CwBQaE/e+FnGvWen'
    'ZthcnWqaAuKu6NI6TgThNB/ZZAIkQF+aDyCp7SAnPIdIgIaESiUfm/KbDGNn3JEWRw5g1r26'
    '/LtN4JGhNJJO9FSnJQ5AodG6OATnxV+iTo6SslSpVpsuuicnDFE1WnX+hltgnummmBQBVHBC'
    'F8CAbAB5AI8HnV6AyMH7yKI0lNmISqWrqU/FqGuuQrZA2OjdRDLwlCAQhgELFuiy9dfZ6KvI'
    'K7mjr5OB14RRV5BX+TYZOFWk/K+yu8Np6kwM2HOliGNns4V0rorE8rPIHcLATeo1GCEG7GQM'
    'bg3ctVmSwzYvKM5aQlnJPXNlRNxvUh5wTrB6OetgbPTlulWnEk9dO0Qu7BEGHqpgT+lszsmr'
    'G8WCYAUnkNHbTVZvtmCpaHuftuUGmHKkaNYq16ABK/bO1MuZuXChEZt93aKIFczc2KtfnJc3'
    'fTYZSCtY5guF799SqQiMd8+VaqUsEOWqH26GzjIrubhjhxavKfAtcT6BVfVDJkysH9opLNK/'
    'taHJvz4qNaC+uT6gFeatpdf4QWM6j22saO3e3TWFNCdWxnvHi8aVG9V0S1IsbaLT3cuD/YIL'
    '+RyYrGqqH27di9yKPAtKSzNTr1mY3LEx32jnZBERFjTWbWx3tx8qOxGmWTzJ3/m5lURcpEyX'
    'PE9WuaflF9e9cRuhkojrCiLc40JckvUTnC47P2Px1tTce+TYMd1GdAl3jRgzttvIDq+k4E7t'
    '7SFtSQVq+z864WJLKvDxNik5rfR2TQzxGeRglJbK20WKcqfo2vic+AQfO5Nwa8/pzl57rO1G'
    'RBrHRDi9FFObUvG+JUdH56YmO2jv+0Cyalx7Dw4YnOE1X6V9+ZPz0QAkfuufmHHid1HN/IKR'
    'PE50XV53aoslF6+ffqTOJazKvrvhJUtukFmpx4LgZLlHpEy8JqqZvX44YH76iIVjF6YBAEAA'
    'tFy/c2pAcZlG8Fe5jHsBwN28dACAx/34o79J/3oLb3lDAFIUhOIRDbCRgPydLgpH8DIhaD7h'
    'aS01IB10KI0gh0k5V4pSgDY/Jkz5caHzF/rgN0O9SBFm8n6OI+KQqgChC12WUqdbKaWiknrm'
    'b2ljKUuNThrUylSjTlfNKnQiDVOmuZjNAdf/5QkA';
