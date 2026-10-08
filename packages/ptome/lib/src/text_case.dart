/// Case mapping as Asciidoctor performs it (Ruby's `String#upcase` and
/// `String#downcase`): full Unicode mappings code point by code point, such
/// as `ß` to `SS`, with no context rules (no final sigma). plain_unicode's
/// tables are checked against Ruby's for every code point.
library;

import 'package:plain_unicode/plain_unicode.dart' show lowerCase, upperCase;

/// [text] in upper case, as Ruby's `String#upcase` gives it.
String upcase(String text) => upperCase(text);

/// [text] in lower case, as Ruby's `String#downcase` gives it.
String downcase(String text) => lowerCase(text);
