// The PDF theme loader, after asciidoctor-pdf 2.3.27's
// spec/theme_loader_spec.rb (vendor/asciidoctor-pdf/test/spec).
@TestOn('vm')
library;

import 'dart:io';

import 'package:ptome/src/logging.dart';
import 'package:ptome/src/pdf/theme.dart';
import 'package:test/test.dart';

const String fixtures = 'vendor/asciidoctor-pdf/test/spec/fixtures';

/// The theme of the YAML [text] (the gem's `ThemeLoader.new.load`), and
/// the warnings logged.
(Theme, List<String>) load(String text) {
  final logger = MemoryLogger();
  final theme = ThemeLoader(logger: logger).loadYaml(text);
  return (theme, [for (final m in logger.messages) m.message.text]);
}

Theme theme(String text) => load(text).$1;

late Directory _dir;
var _files = 0;

/// A theme file holding [text]; returns its path.
String themeFile(String text) {
  final file = File('${_dir.path}/theme-${_files++}-theme.yml')
    ..writeAsStringSync(text);
  return file.path;
}

String basename(String path) => path.split('/').last;

void main() {
  setUpAll(() => _dir = Directory.systemTemp.createTempSync('pdf-theme.'));
  tearDownAll(() => _dir.deleteSync(recursive: true));

  group('load', () {
    test('empty data', () {
      expect(theme('').keys, isEmpty);
    });

    test('keys are flattened', () {
      final t = theme('''
page:
  size: A4
base:
  font:
    family: Times-Roman
  border_width: 0.5
admonition:
  label:
    font_style: bold
''');
      expect(t.string('page_size'), 'A4');
      expect(t.string('base_font_family'), 'Times-Roman');
      expect(t['base_border_width'], const ThemeNumber(0.5));
      expect(t.string('admonition_label_font_style'), 'bold');
    });

    test('admonition icon keys are not flattened', () {
      final t = theme('''
admonition:
  icon:
    tip:
      name: far-lightbulb
      stroke_color: ffff00
      size: 24
    advice: ~
''');
      final tip = t['admonition_icon_tip']! as ThemeMap;
      expect(tip.entries, {
        'name': const ThemeString('far-lightbulb'),
        'stroke_color': const HexColor('FFFF00'),
        'size': const ThemeNumber(24),
      });
      expect(t['admonition_icon_advice'], isNull);
    });

    test('hyphens in keys become underscores, except in role names', () {
      final t = theme('''
page-size: A4
base:
  font-family: Times-Roman
admonition:
  icon:
    tip:
      stroke-color: FFFF00
role:
  flaming-red:
    font-color: ff0000
  BOLD:
    font-style: bold
''');
      expect(t.has('page_size'), isTrue);
      expect(t.has('base_font_family'), isTrue);
      expect(
        (t['admonition_icon_tip']! as ThemeMap).entries,
        contains('stroke_color'),
      );
      expect(t['role_flaming-red_font_color'], const HexColor('FF0000'));
      expect(t.string('role_BOLD_font_style'), 'bold');
    });

    test('content keys are strings', () {
      final t = theme('''
menu:
  caret_content:
  - '>'
ulist:
  marker:
    disc:
      content: 0
footer:
  recto:
    left:
      content: true
    right:
      content: 2 * 2
''');
      expect(t.string('menu_caret_content'), '[">"]');
      expect(t.string('ulist_marker_disc_content'), '0');
      expect(t.string('footer_recto_left_content'), 'true');
      expect(t.string('footer_recto_right_content'), '2 * 2');
    });

    test('align keys are text-align keys', () {
      final (t, warnings) = load(r'''
base:
  align: center
heading:
  align: left
  h2:
    align: right
sidebar:
  title:
    align: $heading-align
caption:
  align: $base-align
  text-align: $heading-align
''');
      expect(warnings, isEmpty);
      expect(t['base_align'], isNull);
      expect(t.string('base_text_align'), 'center');
      expect(t.string('heading_h2_text_align'), 'right');
      expect(t.string('sidebar_title_text_align'), 'left');
      expect(t.string('caption_align'), 'center');
      expect(t.string('caption_text_align'), 'left');
    });

    test('deprecated categories are renamed, with a warning', () {
      final (t, warnings) = load('''
outline_list:
  indent: 40
blockquote:
  font-size: 13
key:
  font-family: Courier
literal:
  font-color: 333333
table:
  caption:
    side: bottom
''');
      expect(t['list_indent'], const ThemeNumber(40));
      expect(t['quote_font_size'], const ThemeNumber(13));
      expect(t.string('kbd_font_family'), 'Courier');
      expect(t['codespan_font_color'], const HexColor('333333'));
      expect(t.string('table_caption_end'), 'bottom');
      String renamed(String from, String to) =>
          'the $from theme category is deprecated; use the $to category '
          'instead';
      expect(warnings, [
        renamed('outline-list', 'list'),
        renamed('blockquote', 'quote'),
        renamed('key', 'kbd'),
        renamed('literal', 'codespan'),
      ]);
    });

    test('the bottom padding hack is neutralized', () {
      final t = theme('''
example:
  padding: [12, 12, 0, 12]
quote:
  padding: [0, 12, -12, 12]
sidebar:
  padding: [-6, 12, 0, 12]
''');
      expect(t['example_padding'], theme('x: [12, 12, 12, 12]')['x']);
      expect(t['quote_padding'], theme('x: [0, 12, 0, 12]')['x']);
      expect(t['sidebar_padding'], theme('x: [-6, 12, 0, 12]')['x']);
    });

    test('the font catalog', () {
      final t = theme(r'''
vars:
  serif-font: /path/to/serif-font.ttf
font:
  catalog:
    Serif:
      normal: $vars-serif-font
    Once: /path/to/once.ttf
    Star:
      '*': /path/to/star.ttf
      bold: /path/to/star-bold.ttf
    Regular:
      regular: /path/to/regular.ttf
  fallbacks:
  - Serif
  unknown: ignored
''');
      final families = t.fontCatalog!.families;
      expect(families['Serif'], {'normal': '/path/to/serif-font.ttf'});
      expect(families['Once']!.keys, [
        'normal',
        'bold',
        'italic',
        'bold_italic',
      ]);
      expect(families['Star']!['bold'], '/path/to/star-bold.ttf');
      expect(families['Star']!['italic'], '/path/to/star.ttf');
      expect(families['Regular'], {'normal': '/path/to/regular.ttf'});
      expect(t.fontFallbacks, ['Serif']);
      expect(t.has('font_unknown'), isFalse);
      expect(theme('font: x').has('font_catalog'), isFalse);
      expect(theme('font_catalog: x')['font_catalog'], const ThemeNull());
      expect(theme('font_fallbacks: ~').fontFallbacks, isEmpty);
      expect(
        theme('font_catalog: {F: GEM_FONTS_DIR/x.ttf}')
            .fontCatalog!
            .families['F']!['normal'],
        'GEM_FONTS_DIR/x.ttf',
      );
    });
  });

  group('data types', () {
    test('null and transparent colors', () {
      expect(
        theme('page: {background_color: null}').value('page_background_color'),
        isNull,
      );
      expect(
        theme(
          'sidebar: {background_color: transparent}',
        )['sidebar_background_color'],
        const TransparentColor(),
      );
    });

    test('colors expand to six hex digits', () {
      for (final MapEntry(key: input, value: resolved) in {
        '0': '000000',
        '9': '000009',
        '000000': '000000',
        '222': '222222',
        '123': '112233',
        // YAML 1.1 reads a leading zero as octal, as the gem does.
        '000011': '000009',
        '2222': '002222',
        '11223344': '112233',
      }.entries) {
        expect(
          theme('page:\n  background_color: $input')['page_background_color'],
          HexColor(resolved),
          reason: input,
        );
      }
    });

    test('CMYK colors', () {
      final t = theme('''
page:
  background_color: [0, 0, 0, 0]
base:
  font_color: [100, 100, 100, 100]
heading:
  font-color: [0, 0, 0, 0.92]
link:
  font-color: [67.33%, 31.19%, 0, 20.78%]
codespan:
  font-color: [0%, 0%, 0%, 0.87]
''');
      expect(t['page_background_color'], const HexColor('FFFFFF'));
      expect(t['base_font_color'], const HexColor('000000'));
      expect(t['heading_font_color'], const CmykThemeColor([0, 0, 0, 92]));
      expect(
        t['link_font_color'],
        const CmykThemeColor([67.33, 31.19, 0, 20.78]),
      );
      expect(t['codespan_font_color'], const CmykThemeColor([0, 0, 0, 87]));
    });

    test('hex and RGB colors', () {
      final t = theme('''
page:
  background_color: 'ffffff'
heading:
  font-color: 333333
link:
  font-color: 428bca
codespan:
  font-color: 222
base:
  font_color: [66, 139, 202]
table:
  grid-color: [[255, 0, 0], [0, 255, 0]]
  border-color: [[0, 1, 1, 0], [1, 0, 1, 0]]
toc:
  font-color: ['fff', 'fff']
''');
      expect(t['page_background_color'], const HexColor('FFFFFF'));
      expect(t['heading_font_color'], const HexColor('333333'));
      expect(t['link_font_color'], const HexColor('428BCA'));
      expect(t['codespan_font_color'], const HexColor('222222'));
      expect(t['base_font_color'], const HexColor('428BCA'));
      expect(
        t['table_grid_color'],
        const ThemeList([HexColor('FF0000'), HexColor('00FF00')]),
      );
      expect(
        t['table_border_color'],
        const ThemeList([
          CmykThemeColor([0, 100, 100, 0]),
          CmykThemeColor([100, 0, 100, 0]),
        ]),
      );
      expect(t['toc_font_color'], const HexColor('FFFFFF'));
      expect(
        theme('menu: {caret: {content: 4a4a4a}}').string('menu_caret_content'),
        '4a4a4a',
      );
    });

    test('hex colors with # and color-like numbers in theme files', () {
      final t = ThemeLoader().load('hex-color-shorthand', fixtures);
      expect(t['base_font_color'], const HexColor('222222'));
      expect(t['base_border_color'], const HexColor('DDDDDD'));
      expect(t['page_background_color'], const HexColor('FEFEFE'));
      expect(t['link_font_color'], const HexColor('428BCA'));
      expect(t['codespan_font_color'], const HexColor('AA0000'));
      expect(t['footer_font_color'], const HexColor('000099'));
      expect(t.value('footer_background_color'), isNull);
      expect(
        ThemeLoader().load('color-like-value', fixtures)['footer_height'],
        const ThemeNumber(100),
      );
    });

    test('measurements', () {
      for (final value in ['36', '36.0', '48.24']) {
        expect(
          theme('footer:\n  padding: $value')['footer_padding'],
          ThemeNumber(num.parse(value)),
        );
      }
      for (final value in ['0.5in', '36pt', '48px', '12.7mm', '1.27cm']) {
        final padding = theme('footer:\n  padding: $value')
            .number('footer_padding')!;
        expect(padding.toDouble(), closeTo(36, 0.005), reason: value);
      }
      expect(
        theme('role: {big: {font-size: 1.2em}}').string('role_big_font_size'),
        '1.2em',
      );
    });
  });

  group('interpolation', () {
    test('variable references', () {
      final t = theme(r'''
brand:
  blue: '0000FF'
  blue-color: '0000FF'
base:
  font_color: $brand_blue
heading:
  font_color: $base-font-color
link:
  font_color: $brand-blue-color
''');
      expect(t['base_font_color'], const HexColor('0000FF'));
      expect(t['heading_font_color'], const HexColor('0000FF'));
      expect(t['link_font_color'], const HexColor('0000FF'));
    });

    test('unresolved references are warned about', () {
      final (t, warnings) = load(r'''
base:
  font_color: $brand-red
block:
  margin-bottom: -$vertical-rhythm
heading:
  font_family: Noto $brand-font-family-variant
''');
      expect(t['base_font_color'], const HexColor(r'$BRAND'));
      expect(t.string('block_margin_bottom'), r'-$vertical-rhythm');
      expect(
        t.string('heading_font_family'),
        r'Noto $brand-font-family-variant',
      );
      expect(warnings, [
        r'unknown variable reference in PDF theme: $brand-red',
        r'unknown variable reference in PDF theme: $vertical-rhythm',
        r'unknown variable reference in PDF theme: $brand-font-family-variant',
      ]);
    });

    test('interpolated strings', () {
      final t = theme(r'''
brand:
  font_family_name: Noto
  font_family_variant: Serif
base:
  font_family: $brand_font_family_name $brand_font_family_variant
''');
      expect(t.string('base_font_family'), 'Noto Serif');
    });

    test('arithmetic', () {
      final t = theme(r'''
base:
  font_size: 10
  line_height_length: 12
  line_height: $base_line_height_length / $base_font_size
  font_size_large: $base_font_size * 1.25
  font_size_min: $base_font_size * 3 / 4
  border_radius: 3 ^ 2
quote:
  border_width: 5
  padding: [-0.001, $base_line_height_length - 2, $base_line_height_length * -0.75, $base_line_height_length + $quote_border_width / 2]
vertical-rhythm: 12
block:
  anchor-top: -$vertical-rhythm
footer:
  padding: [0, -0.67in, 0, -0.67in]
brand:
  ten: 10
  a_string: ten*10
  another_string: ten-10
title-page:
  title:
    top: 3in / 4
''');
      expect(t['base_line_height'], const ThemeNumber(1.2));
      expect(t['base_font_size_large'], const ThemeNumber(12.5));
      expect(t['base_font_size_min'], const ThemeNumber(7.5));
      expect(t['base_border_radius'], const ThemeNumber(9));
      expect(
        t['quote_padding'],
        const ThemeList([
          ThemeNumber(-0.001),
          ThemeNumber(10),
          ThemeNumber(-9),
          ThemeNumber(14.5),
        ]),
      );
      expect(t['block_anchor_top'], const ThemeNumber(-12));
      expect(
        t['footer_padding'],
        const ThemeList([
          ThemeNumber(0),
          ThemeNumber(-48.24),
          ThemeNumber(0),
          ThemeNumber(-48.24),
        ]),
      );
      expect(t['brand_ten'], const ThemeNumber(10));
      expect(t.string('brand_a_string'), 'ten*10');
      expect(t.string('brand_another_string'), 'ten-10');
      expect(t['title_page_title_top'], const ThemeNumber(54));
    });

    test('precision functions', () {
      final t = theme(r'''
base:
  font_size: 10.5
heading:
  h1_font_size: ceil($base_font_size * 2.6)
  h2_font_size: floor($base_font_size * 2.1)
  h3_font_size: round($base_font_size * 1.5)
''');
      expect(t['heading_h1_font_size'], const ThemeNumber(28));
      expect(t['heading_h2_font_size'], const ThemeNumber(22));
      expect(t['heading_h3_font_size'], const ThemeNumber(16));
    });
  });

  group('files and extends', () {
    test('empty and null theme files', () {
      expect(ThemeLoader().loadFile('$fixtures/empty-theme.yml').keys, isEmpty);
      expect(ThemeLoader().loadFile('$fixtures/nil-theme.yml').keys, isEmpty);
    });

    test('a theme indented with tabs fails with its file name', () {
      expect(
        () => ThemeLoader().loadFile('$fixtures/tab-indentation-theme.yml'),
        throwsA(
          isA<ThemeException>().having(
            (e) => e.message,
            'message',
            contains('tab-indentation-theme.yml'),
          ),
        ),
      );
    });

    test('extends: an array, relative and absolute paths', () {
      final custom = themeFile('base:\n  font-family: Times-Roman\n');
      final red = themeFile('base:\n  font-color: ff0000\n');
      final path = themeFile('''
extends:
- ${basename(custom)}
- ./${basename(red)}
- ${File('$fixtures/custom-theme.yml').absolute.path}
base:
  text-align: justify
''');
      final t = ThemeLoader().loadFile(path, themesDir: _dir.path);
      expect(t.string('base_text_align'), 'justify');
      expect(t.string('base_font_family'), 'Times-Roman');
      expect(t['base_font_color'], const HexColor('FF0000'));
    });

    test('extends: the bundled themes, base last, once unless !important', () {
      final red = themeFile('base:\n  font-color: ff0000\n');
      final t = ThemeLoader().loadFile(
        themeFile(
          'extends:\n- default\n- ${basename(red)}\n'
          'base:\n  font-color: 0000ff\n',
        ),
        themesDir: _dir.path,
      );
      expect(t.string('base_font_family'), 'Noto Serif');
      expect(t['base_font_color'], const HexColor('0000FF'));

      final heading = themeFile('heading:\n  font-color: #AA0000\n');
      final last = ThemeLoader().loadFile(
        themeFile('extends:\n- ${basename(heading)}\n- base\n'),
        themesDir: _dir.path,
      );
      expect(last['heading_font_color'], const HexColor('AA0000'));
      expect(last.string('base_font_family'), 'Helvetica');

      final extendedBase = themeFile(
        'extends: base\n'
        'base:\n  font-color: 222222\n  font-family: Times-Roman\n',
      );
      final forced = ThemeLoader().loadFile(
        themeFile('extends:\n- ${basename(extendedBase)}\n- base !important\n'),
        themesDir: _dir.path,
      );
      // The base theme is loaded as it is: its colors are strings.
      expect(forced.string('base_font_color'), '000000');
      expect(forced.string('base_font_family'), 'Helvetica');
      final once = ThemeLoader().loadFile(
        themeFile('extends:\n- ${basename(extendedBase)}\n- base\n'),
        themesDir: _dir.path,
      );
      expect(once['base_font_color'], const HexColor('222222'));
    });

    test('a merged font catalog', () {
      final t = ThemeLoader().loadFile(
        themeFile('''
extends: default
font:
  catalog:
    merge: true
    M+ 1mn:
      normal: /path/to/mplus1mn-regular.ttf
    VLGothic:
      normal: &VLGothic /path/to/vlgothic-regular.ttf
      bold: *VLGothic
      italic: *VLGothic
      bold_italic: *VLGothic
  fallbacks:
  - VLGothic
'''),
      );
      final families = t.fontCatalog!.families;
      expect(families.keys, containsAll(['Noto Serif', 'M+ 1mn', 'VLGothic']));
      expect(families.length, 3);
      expect(families['Noto Serif']!.length, 4);
      expect(families['M+ 1mn'], {'normal': '/path/to/mplus1mn-regular.ttf'});
      expect(families['VLGothic']!.values.toSet().length, 1);
      expect(t.fontFallbacks, ['VLGothic']);
    });
  });

  group('load theme', () {
    test('base and default', () {
      final base = ThemeLoader().load('base');
      expect(base.string('base_font_family'), 'Helvetica');
      expect(base.string('codespan_font_family'), 'Courier');
      final defaults = ThemeLoader().load();
      expect(defaults.string('base_font_family'), 'Noto Serif');
      expect(defaults.directory, isNull);
      for (final name in bundledThemeNames) {
        expect(ThemeLoader().load(name).keys, isNotEmpty, reason: name);
      }
    });

    test('required keys in a theme of its own', () {
      final t = ThemeLoader().load('bare', fixtures);
      expect(t.string('base_text_align'), 'left');
      expect(t['base_line_height'], const ThemeNumber(1));
      expect(t['base_font_color'], const HexColor('000000'));
      expect(t.string('code_font_family'), 'Courier');
      expect(t.string('conum_font_family'), 'Courier');
      expect(t.directory, File(fixtures).absolute.path.replaceAll(r'\', '/'));
    });

    test('code and conum fonts follow codespan; titles follow headings', () {
      final t = ThemeLoader().loadFile(
        themeFile('''
codespan:
  font-family: M+ 1mn
heading:
  font-family: Noto Sans
'''),
      );
      expect(t.has('code_font_family'), isFalse, reason: 'load_file alone');
      final loaded = ThemeLoader().load(
        basename(
          themeFile('''
codespan:
  font-family: M+ 1mn
heading:
  font-family: Noto Sans
'''),
        ).replaceAll('-theme.yml', ''),
        _dir.path,
      );
      expect(loaded.string('code_font_family'), 'M+ 1mn');
      expect(loaded.string('conum_font_family'), 'M+ 1mn');
      expect(loaded.string('abstract_title_font_family'), 'Noto Sans');
      expect(loaded.string('sidebar_title_font_family'), 'Noto Sans');
    });

    test('a missing theme', () {
      expect(
        () => ThemeLoader().load('nonexistent'),
        throwsA(isA<ThemeException>()),
      );
      expect(
        () => ThemeLoader().load('nonexistent', fixtures),
        throwsA(isA<ThemeException>()),
      );
    });
  });

  test('Ruby number formatting', () {
    expect(rubyNumber(12), '12');
    expect(rubyNumber(36.0), '36.0');
    expect(rubyNumber(10.5), '10.5');
    expect(rubyNumber(1e20), '1.0e+20');
    expect(rubyNumber(0.00001), '1.0e-05');
    expect(rubyNumber(-48.24), '-48.24');
  });
}
