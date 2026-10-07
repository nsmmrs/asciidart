/// `asciidart doctor`: checks that the fonts the built-in PDF themes use
/// are installed, and offers to download the missing ones from their
/// official sources into this user's font folder.
///
/// asciidart compiles no fonts in: the backends use the fonts installed
/// on the machine (see `font_index.dart`), and a theme can name any of
/// them. The built-in themes name Noto, M+ (M PLUS) and the icon fonts of
/// prawn-icon; `doctor` finds them as the PDF backend does (by the gem's
/// file names, then by family) and fetches what is missing: the Noto and
/// M PLUS families from Google Fonts (each file checked to be the family
/// asked for), the icon fonts from their projects' repositories at pinned
/// commits (each file checked against its SHA-256 digest). Each font's
/// license is saved beside it.
library;

import 'dart:convert';

import 'package:asciidart/src/font_index.dart';
import 'package:asciidart/src/io.dart' as io;
import 'package:asciidart/src/remote.dart';
import 'package:asciidart/src/sha256.dart';
import 'package:libpdf/libpdf.dart' show OpenTypeFont;

/// Usage text for `doctor` (printed by `--help` and on misuse).
const String doctorUsage = '''
Usage: asciidart doctor [options]

Checks that the fonts of asciidart's built-in PDF themes are installed
(Noto Serif, Noto Sans, M+ 1mn for code, the fallback fonts, Noto Sans
Math and the icon fonts), and offers to download the missing ones from
their official sources (Google Fonts, the projects' repositories) into
this user's font folder, in a folder of its own named asciidart.

Options:
  -y, --yes      install the missing fonts without asking
  -c, --check    only check: exit with status 1 when fonts are missing
  -h, --help     show this help
''';

/// A face of a family.
enum FontStyle {
  /// Regular.
  normal('regular'),

  /// Bold.
  bold('bold'),

  /// Italic.
  italic('italic'),

  /// Bold italic.
  boldItalic('bold italic');

  new(this.label);

  /// The style's name in messages.
  final String label;

  /// Whether the style is bold.
  bool get isBold => this == bold || this == boldItalic;

  /// Whether the style is italic.
  bool get isItalic => this == italic || this == boldItalic;
}

/// A file to download, pinned to its digest.
typedef PinnedFile = ({String url, String sha256, String name});

/// Where a font comes from.
sealed class FontSource {
  const new();

  /// The source, as `doctor` names it.
  String get description;
}

/// A family of Google Fonts: the files of each style in its download
/// (`static/NotoSerif-Bold.ttf`), and its license file.
final class GoogleFonts extends FontSource {
  /// [family]'s [files] by style.
  const new(this.family, this.files, {this.license = 'OFL.txt'});

  /// The family's name on Google Fonts.
  final String family;

  /// The file of each style in the family's download.
  final Map<FontStyle, String> files;

  /// The license file in the download.
  final String license;

  @override
  String get description => '$family from Google Fonts';
}

/// Files from a project's repository, pinned to their digests.
final class PinnedFiles extends FontSource {
  /// The [files] of each style, and the [license] file (with
  /// [licenseInHeader], a file whose first comment states it).
  const new(
    this.project,
    this.files,
    this.license, {
    this.licenseInHeader = false,
  });

  /// The project, as `doctor` names it.
  final String project;

  /// The file of each style.
  final Map<FontStyle, PinnedFile> files;

  /// The license file.
  final PinnedFile license;

  /// Whether the license is the first comment of [license] (a stylesheet
  /// stating it).
  final bool licenseInHeader;

  @override
  String get description => project;
}

/// A font the built-in themes use.
final class NeededFont {
  /// A font named [name] (in messages), used by [usedBy], found by
  /// [fileNames] or [families] in [styles], from [source] under
  /// [license].
  const new({
    required this.name,
    required this.usedBy,
    required this.families,
    required this.styles,
    required this.fileNames,
    required this.source,
    required this.license,
  });

  /// The font, as `doctor` names it.
  final String name;

  /// What uses it.
  final String usedBy;

  /// The families it may be installed as (the first is the theme's).
  final List<String> families;

  /// The styles needed.
  final List<FontStyle> styles;

  /// The file names it may be installed under, by style (the gem's
  /// subsets, the project's own files).
  final Map<FontStyle, List<String>> fileNames;

  /// Where it comes from.
  final FontSource source;

  /// Its license, as `doctor` names it.
  final String license;
}

const List<FontStyle> _all = FontStyle.values;

GoogleFonts _google(String family, String prefix, List<FontStyle> styles) =>
    GoogleFonts(family, {
      for (final style in styles)
        style:
            'static/$prefix-${switch (style) {
              FontStyle.normal => 'Regular',
              FontStyle.bold => 'Bold',
              FontStyle.italic => 'Italic',
              FontStyle.boldItalic => 'BoldItalic',
            }}.ttf',
    });

Map<FontStyle, List<String>> _gemSubsets(String prefix) => {
  for (final style in _all)
    style: [
      '$prefix-${switch (style) {
        FontStyle.normal => 'regular',
        FontStyle.bold => 'bold',
        FontStyle.italic => 'italic',
        FontStyle.boldItalic => 'bold_italic',
      }}-subset.ttf',
    ],
};

const String _fontAwesome =
    'https://raw.githubusercontent.com/FortAwesome/Font-Awesome/5.15.1';
const String _foundation =
    'https://raw.githubusercontent.com/zurb/foundation-icon-fonts/'
    'afed003521ff971bc614de68bba2676e16ce39f4';
const String _paymentFont =
    'https://raw.githubusercontent.com/AlexanderPoellmann/PaymentFont/'
    'c9dcb62cc507d778c2aa92ecf4f7b1c5a63cd4c9';

const String _foundationDigest =
    '7e1dd03dd4ce90b658052554cd7459df16716717389a552fa4c6d56a5f8933e6';
const String _paymentFontDigest =
    '03eb1d6b2b330ea611766452bdc66c9236ab695e80e43af1e6609250b8cc09e9';

const PinnedFile _fontAwesomeLicense = (
  url: '$_fontAwesome/LICENSE.txt',
  sha256: 'e779748dfe75e84f974df3c7bc07f842011a100159158b0f1f49b2f2a5a515cb',
  name: 'FontAwesome-LICENSE.txt',
);

/// The fonts of the built-in PDF themes, their fallbacks, math and icons.
final List<NeededFont> neededFonts = [
  NeededFont(
    name: 'Noto Serif',
    usedBy: 'the default theme',
    families: const ['Noto Serif'],
    styles: _all,
    fileNames: _gemSubsets('notoserif'),
    source: _google('Noto Serif', 'NotoSerif', _all),
    license: 'SIL Open Font License 1.1',
  ),
  NeededFont(
    name: 'Noto Sans',
    usedBy: "asciidart's theme, default-sans",
    families: const ['Noto Sans'],
    styles: _all,
    fileNames: _gemSubsets('notosans'),
    source: _google('Noto Sans', 'NotoSans', _all),
    license: 'SIL Open Font License 1.1',
  ),
  NeededFont(
    name: 'M+ 1mn',
    usedBy: 'code in the default themes',
    families: const ['M+ 1mn', 'M PLUS 1 Code'],
    // (Italics are slanted from these: M PLUS 1 Code has none.)
    styles: const [FontStyle.normal, FontStyle.bold],
    fileNames: _gemSubsets('mplus1mn'),
    source: _google('M PLUS 1 Code', 'MPLUS1Code', const [
      FontStyle.normal,
      FontStyle.bold,
    ]),
    license: 'SIL Open Font License 1.1',
  ),
  const NeededFont(
    name: 'M+ 1p',
    usedBy: 'the fallback font of the *-with-font-fallbacks themes',
    families: ['M+ 1p', 'M PLUS 1p'],
    styles: [FontStyle.normal],
    fileNames: {
      FontStyle.normal: ['mplus1p-regular-fallback.ttf'],
    },
    source: GoogleFonts('M PLUS 1p', {FontStyle.normal: 'MPLUS1p-Regular.ttf'}),
    license: 'SIL Open Font License 1.1',
  ),
  const NeededFont(
    name: 'Noto Emoji',
    usedBy: 'the emoji fallback of the *-with-font-fallbacks themes',
    families: ['Noto Emoji'],
    styles: [FontStyle.normal],
    fileNames: {
      FontStyle.normal: ['notoemoji-subset.ttf'],
    },
    source: GoogleFonts('Noto Emoji', {
      FontStyle.normal: 'static/NotoEmoji-Regular.ttf',
    }),
    license: 'SIL Open Font License 1.1',
  ),
  const NeededFont(
    name: 'Noto Sans Math',
    usedBy: 'math (stem) in PDFs',
    families: ['Noto Sans Math'],
    styles: [FontStyle.normal],
    fileNames: {
      FontStyle.normal: ['notosansmath-regular.ttf'],
    },
    source: GoogleFonts('Noto Sans Math', {
      FontStyle.normal: 'NotoSansMath-Regular.ttf',
    }),
    license: 'SIL Open Font License 1.1',
  ),
  const NeededFont(
    name: 'Font Awesome 5 Free Solid',
    usedBy: 'icons (fas), admonition icons',
    families: ['Font Awesome 5 Free Solid'],
    styles: [FontStyle.normal],
    fileNames: {
      FontStyle.normal: ['fa-solid.ttf', 'fa-solid-900.ttf'],
    },
    source: PinnedFiles('Font Awesome Free 5.15.1', {
      FontStyle.normal: (
        url: '$_fontAwesome/webfonts/fa-solid-900.ttf',
        sha256:
            'e3b4ee7d2dc2641317d00347cb27f06120dcda110d85af9a47f5ba29e6747e76',
        name: 'fa-solid-900.ttf',
      ),
    }, _fontAwesomeLicense),
    license: 'SIL Open Font License 1.1',
  ),
  const NeededFont(
    name: 'Font Awesome 5 Free Regular',
    usedBy: 'icons (far), admonition icons',
    families: ['Font Awesome 5 Free Regular'],
    styles: [FontStyle.normal],
    fileNames: {
      FontStyle.normal: ['fa-regular.ttf', 'fa-regular-400.ttf'],
    },
    source: PinnedFiles('Font Awesome Free 5.15.1', {
      FontStyle.normal: (
        url: '$_fontAwesome/webfonts/fa-regular-400.ttf',
        sha256:
            '5a6a7730b932700ce3bb607e6bf933ff0e9a62208ebeaa71a584151ab213151b',
        name: 'fa-regular-400.ttf',
      ),
    }, _fontAwesomeLicense),
    license: 'SIL Open Font License 1.1',
  ),
  const NeededFont(
    name: 'Font Awesome 5 Brands',
    usedBy: 'icons (fab)',
    families: ['Font Awesome 5 Brands'],
    styles: [FontStyle.normal],
    fileNames: {
      FontStyle.normal: ['fa-brands.ttf', 'fa-brands-400.ttf'],
    },
    source: PinnedFiles('Font Awesome Free 5.15.1', {
      FontStyle.normal: (
        url: '$_fontAwesome/webfonts/fa-brands-400.ttf',
        sha256:
            '0097aaf99df2ae041aeccda155c791b155c01039e0942d1ca36ec737982f67f7',
        name: 'fa-brands-400.ttf',
      ),
    }, _fontAwesomeLicense),
    license: 'SIL Open Font License 1.1',
  ),
  const NeededFont(
    name: 'Foundation Icons',
    usedBy: 'icons (fi)',
    families: [],
    styles: [FontStyle.normal],
    fileNames: {
      FontStyle.normal: ['foundation-icons.ttf'],
    },
    source: PinnedFiles(
      'Foundation Icons 3 (ZURB)',
      {
        FontStyle.normal: (
          url: '$_foundation/foundation-icons.ttf',
          sha256: _foundationDigest,
          name: 'foundation-icons.ttf',
        ),
      },
      (
        url: '$_foundation/foundation-icons.css',
        sha256:
            '09696d0bf5be7a592450a862b5cced3e249f137004a7302fae4984a81ebc2f1d',
        name: 'FoundationIcons-LICENSE.txt',
      ),
      licenseInHeader: true,
    ),
    license: 'MIT',
  ),
  const NeededFont(
    name: 'PaymentFont',
    usedBy: 'icons (pf)',
    families: [],
    styles: [FontStyle.normal],
    fileNames: {
      FontStyle.normal: ['paymentfont-webfont.ttf'],
    },
    source: PinnedFiles(
      'PaymentFont',
      {
        FontStyle.normal: (
          url: '$_paymentFont/fonts/paymentfont-webfont.ttf',
          sha256: _paymentFontDigest,
          name: 'paymentfont-webfont.ttf',
        ),
      },
      (
        url: '$_paymentFont/LICENSE',
        sha256:
            'a81002fa8cd21d4b4a21101bde70a1fb9b7803608f23012e04248b770a1b2dd1',
        name: 'PaymentFont-LICENSE.txt',
      ),
    ),
    license: 'MIT',
  ),
];

/// Where [font] in [style] is installed in [index], if it is: under one of
/// its file names, else as one of its families in that very style.
String? installedPath(FontIndex index, NeededFont font, FontStyle style) {
  for (final name in font.fileNames[style] ?? const <String>[]) {
    if (index.fileNamed(name) case final path?) return path;
  }
  for (final family in font.families) {
    final found = index.find(
      family,
      bold: style.isBold,
      italic: style.isItalic,
    );
    if (found != null &&
        found.bold == style.isBold &&
        found.italic == style.isItalic) {
      return found.path;
    }
  }
  return null;
}

/// Runs `asciidart doctor` with [args]; its exit status (0 when every font
/// is installed, 1 when some are missing or couldn't be installed, 64 on
/// misuse). The fonts are looked up in [index] (the installed fonts) and
/// installed into [installDirectory] (this user's font folder's
/// `asciidart`), fetched with [fetch]; a question is asked when
/// [interactive] (standard input is a terminal) and answered by
/// [readLine].
Future<int> runDoctor(
  List<String> args, {
  StringSink? out,
  StringSink? err,
  FontIndex Function()? index,
  String? installDirectory,
  Future<RemoteResource> Function(Uri uri)? fetch,
  bool? interactive,
  String? Function()? readLine,
}) async {
  final output = out ?? io.standardOutput;
  final errors = err ?? io.standardError;
  var yes = false;
  var check = false;
  for (final arg in args) {
    switch (arg) {
      case '-y' || '--yes':
        yes = true;
      case '-c' || '--check':
        check = true;
      case '-h' || '--help':
        output.write(doctorUsage);
        return 0;
      default:
        errors
          ..writeln('asciidart doctor: unknown option $arg')
          ..write(doctorUsage);
        return 64;
    }
  }
  final fonts = (index ?? FontIndex.machine)();
  final missing = <(NeededFont, List<FontStyle>)>[];
  output.writeln("The fonts of asciidart's built-in PDF themes:");
  for (final font in neededFonts) {
    final absent = <FontStyle>[];
    final found = <String>{};
    for (final style in font.styles) {
      final path = installedPath(fonts, font, style);
      if (path == null) {
        absent.add(style);
      } else {
        found.add(_folderOf(path));
      }
    }
    final status = absent.isEmpty
        ? 'installed'
        : absent.length == font.styles.length
        ? 'missing'
        : 'missing ${absent.map((s) => s.label).join(', ')}';
    output.writeln(
      '  ${font.name.padRight(28)} ${status.padRight(10)} ${font.usedBy}'
      '${found.isEmpty ? '' : ' (${found.join(', ')})'}',
    );
    if (absent.isNotEmpty) missing.add((font, absent));
  }
  if (missing.isEmpty) {
    output.writeln('Every font is installed.');
    return 0;
  }
  output
    ..writeln()
    ..writeln(
      '${missing.length} of ${neededFonts.length} fonts are missing; in their '
      'place PDFs use the built-in PDF fonts (Times, Helvetica, Courier) and '
      'show icons as text.',
    );
  if (check) return 1;
  final String target;
  try {
    target = installDirectory ?? _join(io.userFontDirectory, 'asciidart');
  } on Exception {
    errors.writeln('asciidart doctor: no font folder on this platform');
    return 1;
  }
  output
    ..writeln('They can be downloaded and installed into $target:')
    ..writeln();
  for (final (font, styles) in missing) {
    output.writeln(
      '  ${font.name.padRight(28)} ${font.source.description}, '
      '${font.license} (${styles.map((s) => s.label).join(', ')})',
    );
  }
  output.writeln();
  if (!yes) {
    if (!(interactive ?? io.hasTerminal)) {
      output.writeln('Run `asciidart doctor --yes` to install them.');
      return 1;
    }
    output.write('Download and install them? [y/N] ');
    final answer = (readLine ?? io.readLine)()?.trim().toLowerCase() ?? '';
    if (answer != 'y' && answer != 'yes') {
      output.writeln('Nothing installed.');
      return 1;
    }
  }
  final download = fetch ?? io.fetchUri;
  final installed = <String>[];
  var failed = 0;
  final licenses = <String>{};
  for (final (font, styles) in missing) {
    try {
      final files = await _fetchFont(font, styles, download, licenses);
      io.createDirectories(target);
      for (final (name, bytes) in files) {
        final path = _join(target, name);
        io.writeBytes(path, bytes);
        if (name.endsWith('.ttf') || name.endsWith('.otf')) {
          installed.add(path);
        }
      }
      output.writeln('  installed ${font.name}');
    } on Exception catch (error) {
      failed++;
      errors.writeln('asciidart doctor: ${font.name}: $error');
    }
  }
  if (installed.isNotEmpty) _register(installed);
  output.writeln(
    failed == 0
        ? 'Installed ${installed.length} font files into $target.'
        : 'Installed ${installed.length} font files into $target; '
              '$failed fonts could not be installed.',
  );
  return failed == 0 ? 0 : 1;
}

/// The files of [font] in [styles] (and its license, once per source),
/// fetched with [fetch]: their names and contents.
Future<List<(String, List<int>)>> _fetchFont(
  NeededFont font,
  List<FontStyle> styles,
  Future<RemoteResource> Function(Uri uri) fetch,
  Set<String> licenses,
) async {
  final files = <(String, List<int>)>[];
  switch (font.source) {
    case GoogleFonts(:final family, files: final wanted, :final license):
      final manifest = await _manifest(family, fetch);
      for (final style in styles) {
        final name = wanted[style];
        final url = name == null ? null : manifest.urls[name];
        if (name == null || url == null) {
          throw DoctorException('Google Fonts has no $name for $family');
        }
        final bytes = (await fetch(Uri.parse(url))).body;
        final actual = _familyOf(bytes);
        if (actual == null ||
            !actual.toLowerCase().startsWith(family.toLowerCase())) {
          throw DoctorException(
            '$name is not a font of $family (${actual ?? 'not a font'})',
          );
        }
        files.add((_baseName(name), bytes));
      }
      final licenseName = '${family.replaceAll(' ', '')}-$license';
      if (manifest.license case final text? when licenses.add(licenseName)) {
        files.add((licenseName, utf8.encode(text)));
      }
    case PinnedFiles(
      files: final wanted,
      :final license,
      :final licenseInHeader,
    ):
      for (final style in styles) {
        if (wanted[style] case final file?) {
          files.add((file.name, await _pinned(file, fetch)));
        }
      }
      if (licenses.add(license.name)) {
        var text = await _pinned(license, fetch);
        if (licenseInHeader) {
          final source = utf8.decode(text, allowMalformed: true);
          final end = source.indexOf('*/');
          text = utf8.encode(
            '${end < 0 ? source : source.substring(0, end + 2)}\n',
          );
        }
        files.add((license.name, text));
      }
  }
  return files;
}

/// The family name of the font in [bytes], or null when it isn't one.
String? _familyOf(List<int> bytes) {
  try {
    return OpenTypeFont.parse(bytes).familyName;
  } on Exception {
    return null;
  }
}

/// [file]'s contents, checked against its digest.
Future<List<int>> _pinned(
  PinnedFile file,
  Future<RemoteResource> Function(Uri uri) fetch,
) async {
  final bytes = (await fetch(Uri.parse(file.url))).body;
  if (sha256Hex(bytes) != file.sha256) {
    throw DoctorException(
      '${file.url} is not the file expected (its SHA-256 differs)',
    );
  }
  return bytes;
}

/// The files of [family]'s download from Google Fonts, by name, and its
/// license's text.
Future<({Map<String, String> urls, String? license})> _manifest(
  String family,
  Future<RemoteResource> Function(Uri uri) fetch,
) async {
  final response = await fetch(
    Uri.https('fonts.google.com', '/download/list', {'family': family}),
  );
  final text = utf8.decode(response.body, allowMalformed: true);
  final start = text.indexOf('{');
  if (start < 0) throw DoctorException('Google Fonts has no $family');
  final urls = <String, String>{};
  String? license;
  if (jsonDecode(text.substring(start)) case {
    'manifest': {'fileRefs': [...final refs], 'files': [...final files]},
  }) {
    for (final ref in refs) {
      if (ref case {'filename': final String name, 'url': final String url}) {
        urls[name] = url;
      }
    }
    for (final file in files) {
      if (file
          case {
            'filename': final String name,
            'contents': final String contents,
          }
          when name.endsWith('.txt')) {
        license ??= contents;
      }
    }
  } else {
    throw DoctorException('Google Fonts sent no list of files for $family');
  }
  return (urls: urls, license: license);
}

/// Makes the fonts at [paths] known to the system: fontconfig's cache on
/// Linux, the user's font registry on Windows (macOS finds them).
void _register(List<String> paths) {
  if (io.isWindows) {
    for (final path in paths) {
      final name =
          '${_baseName(path).replaceAll(RegExp(r'\.[^.]+$'), '')} '
          '(TrueType)';
      io.commandOutput('reg', [
        'add',
        r'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts',
        '/v',
        name,
        '/t',
        'REG_SZ',
        '/d',
        path,
        '/f',
      ]);
    }
    return;
  }
  final folder = _folderOf(paths.first);
  io.commandOutput('fc-cache', ['-f', folder]);
}

/// A failure to download or check a font.
final class DoctorException implements Exception {
  /// A failure with [message].
  const new(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => message;
}

String _join(String dir, String name) => dir.endsWith('/') || dir.endsWith(r'\')
    ? '$dir$name'
    : '$dir${io.isWindows ? r'\' : '/'}$name';

String _folderOf(String path) {
  final slash = path.lastIndexOf(RegExp(r'[/\\]'));
  return slash < 0 ? '.' : path.substring(0, slash);
}

String _baseName(String path) {
  final slash = path.lastIndexOf(RegExp(r'[/\\]'));
  return slash < 0 ? path : path.substring(slash + 1);
}
