/// The icon sets of the PDF backend (prawn-icon's): Font Awesome's solid,
/// regular and brands sets, Foundation Icons and PaymentFont, by name, and
/// the deprecated `fa` set's Font Awesome 4 names.
library;

import 'package:ptome/src/pdf/assets.g.dart';

/// The icon sets, by the prefix that names them.
const Set<String> iconSets = {'fab', 'far', 'fas', 'fi', 'pf'};

/// The Font Awesome sets, in the order an icon of the `fa` set is looked
/// for.
const List<String> fontAwesomeSets = ['fab', 'far', 'fas'];

final Map<String, Map<String, String>> _glyphs = {};
Map<String, String>? _legacy;

Map<String, String> _table(String path) => {
  for (final line in (PdfAssets.text(path) ?? '').split('\n'))
    if (line.split('\t') case [final name, final value]) name: value,
};

/// The character of icon [name] in icon [set], or null.
String? iconGlyph(String set, String name) {
  if (!iconSets.contains(set)) return null;
  final code = (_glyphs[set] ??= _table('icons/$set.tsv'))[name];
  if (code == null) return null;
  final value = int.tryParse(code, radix: 16);
  return value == null ? null : String.fromCharCode(value);
}

/// The icon (`<set>-<name>`) that Font Awesome 4's icon [name] became,
/// or null.
String? legacyIcon(String name) => (_legacy ??= _table('icons/fa.tsv'))[name];
