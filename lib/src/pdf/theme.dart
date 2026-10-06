/// PDF themes: the YAML theme files of asciidoctor-pdf 2.3.27, read as the
/// gem's theme loader reads them (`extends`, variables, arithmetic,
/// measurement units, colors, the font catalog, deprecated keys) into a
/// flat map of typed values.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:asciidart/src/io.dart' as io;
import 'package:asciidart/src/logging.dart';
import 'package:asciidart/src/path_resolver.dart';
import 'package:asciidart/src/pdf/assets.g.dart';
import 'package:asciidart/src/pdf/yaml11.dart';
import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart' show YamlException;

/// A theme value.
@immutable
sealed class ThemeValue {
  const new();

  /// The value as Ruby's `to_s` writes it (variables are substituted into
  /// strings this way).
  String get rubyString;
}

/// A string.
final class ThemeString extends ThemeValue {
  /// The string [value].
  const new(this.value);

  /// The string.
  final String value;

  @override
  String get rubyString => value;

  @override
  bool operator ==(Object other) =>
      other is ThemeString && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ThemeString($value)';
}

/// A number: an integer or a float, as Ruby keeps them apart.
final class ThemeNumber extends ThemeValue {
  /// The number [value].
  const new(this.value);

  /// The number (an `int` or a `double`).
  final num value;

  @override
  String get rubyString => rubyNumber(value);

  @override
  bool operator ==(Object other) =>
      other is ThemeNumber &&
      other.value == value &&
      (other.value is int) == (value is int);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ThemeNumber($rubyString)';
}

/// A boolean.
final class ThemeBool extends ThemeValue {
  /// The boolean [value].
  // A boolean value is its value.
  // ignore: avoid_positional_boolean_parameters
  const new(this.value);

  /// The boolean.
  final bool value;

  @override
  String get rubyString => '$value';

  @override
  bool operator ==(Object other) => other is ThemeBool && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// An explicit null (a key set to nothing, overriding the one extended).
final class ThemeNull extends ThemeValue {
  /// Null.
  const new();

  @override
  String get rubyString => '';

  @override
  bool operator ==(Object other) => other is ThemeNull;

  @override
  int get hashCode => 0;
}

/// A list.
final class ThemeList extends ThemeValue {
  /// The list of [values].
  const new(this.values);

  /// The values.
  final List<ThemeValue> values;

  @override
  String get rubyString => '[${values.map(_inspect).join(', ')}]';

  /// [value] as Ruby's `inspect` writes it in an array.
  static String _inspect(ThemeValue value) =>
      value is ThemeString ? '"${value.value}"' : value.rubyString;

  @override
  bool operator ==(Object other) =>
      other is ThemeList &&
      other.values.length == values.length &&
      [for (var i = 0; i < values.length; i++) i]
          .every((i) => other.values[i] == values[i]);

  @override
  int get hashCode => Object.hashAll(values);

  @override
  String toString() => 'ThemeList($values)';
}

/// A map (the entries of `admonition_icon_<name>`).
final class ThemeMap extends ThemeValue {
  /// The map of [entries].
  const new(this.entries);

  /// The entries.
  final Map<String, ThemeValue> entries;

  @override
  String get rubyString => entries.toString();
}

/// A color.
sealed class ThemeColor extends ThemeValue {
  const new();
}

/// An RGB color as six hex digits (`FF8000`).
final class HexColor extends ThemeColor {
  /// The color of [hex] (six upper-case hex digits).
  const new(this.hex);

  /// The hex digits.
  final String hex;

  @override
  String get rubyString => hex;

  @override
  bool operator ==(Object other) => other is HexColor && other.hex == hex;

  @override
  int get hashCode => hex.hashCode;

  @override
  String toString() => 'HexColor($hex)';
}

/// A CMYK color, each component from 0 to 100.
final class CmykThemeColor extends ThemeColor {
  /// The color of [components].
  const new(this.components);

  /// Cyan, magenta, yellow and black, 0 to 100.
  final List<num> components;

  @override
  String get rubyString => '[${components.map(rubyNumber).join(', ')}]';

  @override
  bool operator ==(Object other) =>
      other is CmykThemeColor &&
      other.components.length == components.length &&
      [for (var i = 0; i < components.length; i++) i]
          .every((i) => other.components[i] == components[i]);

  @override
  int get hashCode => Object.hashAll(components);
}

/// No color.
final class TransparentColor extends ThemeColor {
  /// Transparent.
  const new();

  @override
  String get rubyString => 'transparent';

  @override
  bool operator ==(Object other) => other is TransparentColor;

  @override
  int get hashCode => 1;
}

/// The font catalog: font families, each a map of styles (`normal`,
/// `bold`, `italic`, `bold_italic`) to font files.
final class ThemeFontCatalog extends ThemeValue {
  /// A catalog of [families].
  const new(this.families);

  /// The families.
  final Map<String, Map<String, String>> families;

  @override
  String get rubyString => families.toString();
}

/// [value] as Ruby's `to_s` writes it (`12`, `10.5`, `36.0`, `1.0e+20`).
String rubyNumber(num value) {
  if (value is int) return '$value';
  final v = value.toDouble();
  if (v.isNaN) return 'NaN';
  if (v.isInfinite) return v > 0 ? 'Infinity' : '-Infinity';
  if (v == v.truncateToDouble() && v.abs() < 1e16) {
    return '${v.toInt()}.0';
  }
  final abs = v.abs();
  if (abs >= 1e16 || abs < 1e-4) {
    // Ruby: shortest digits in exponent form, e.g. 1.0e-05.
    final digits = v.toStringAsExponential();
    final m = RegExp(r'^(-?\d)(?:\.(\d+))?e([+-])(\d+)$').firstMatch(digits)!;
    final fraction = m[2] ?? '0';
    final exponent = m[4]!.padLeft(2, '0');
    return '${m[1]}.${fraction}e${m[3]}$exponent';
  }
  return '$v';
}

/// A theme: its flat keys (`base_font_size`, `heading_h2_font_color`...)
/// and the directory its files are relative to.
final class Theme {
  new _(this._values, this.directory);

  final Map<String, ThemeValue> _values;

  /// The directory the theme's relative paths (fonts, images) start from;
  /// null for the bundled themes, whose files are embedded.
  String? directory;

  /// The keys looked up in any theme, while not null (to tell the keys
  /// the converter honors: `tool/pdf_theme_keys.dart`).
  @internal
  static Set<String>? lookups;

  /// The value of [key] (null when the key is not set).
  ThemeValue? operator [](String key) {
    lookups?.add(key);
    return _values[key];
  }

  /// Sets [key] to [value].
  void operator []=(String key, ThemeValue value) => _values[key] = value;

  /// Whether [key] is set (to anything, null included).
  bool has(String key) {
    lookups?.add(key);
    return _values.containsKey(key);
  }

  /// The keys, in the order they were set.
  Iterable<String> get keys => _values.keys;

  /// The value of [key] unless it is unset or null.
  ThemeValue? value(String key) => switch (this[key]) {
    null || ThemeNull() => null,
    final v => v,
  };

  /// [key] as a string (numbers and colors as Ruby writes them).
  String? string(String key) => switch (value(key)) {
    null => null,
    ThemeString(:final value) => value,
    final v => v.rubyString,
  };

  /// [key] as a number, when it is one.
  num? number(String key) => switch (value(key)) {
    ThemeNumber(:final value) => value,
    _ => null,
  };

  /// [key] as a color, when it is one.
  ThemeColor? color(String key) => switch (value(key)) {
    final ThemeColor color => color,
    _ => null,
  };

  /// The font catalog.
  ThemeFontCatalog? get fontCatalog => switch (value('font_catalog')) {
    final ThemeFontCatalog catalog => catalog,
    _ => null,
  };

  /// The fallback font families.
  List<String> get fontFallbacks => switch (value('font_fallbacks')) {
    ThemeList(:final values) => [for (final v in values) v.rubyString],
    _ => const [],
  };

  /// A copy of this theme.
  Theme copy() => Theme._({..._values}, directory);
}

/// The bundled themes, by name (`default`, `default-sans`...).
List<String> get bundledThemeNames => [
  for (final path in PdfAssets.paths)
    if (path.startsWith('data/themes/') && path.endsWith('-theme.yml'))
      path.substring('data/themes/'.length, path.length - '-theme.yml'.length),
];

/// Where a theme file is: a bundled theme (by name) or a file.
@immutable
sealed class _ThemeSource {
  const new();
}

final class _Bundled extends _ThemeSource {
  const new(this.name);

  final String name;

  String get path => 'data/themes/$name-theme.yml';
}

final class _File extends _ThemeSource {
  const new(this.path, this.directory);

  final String path;
  final String directory;
}

/// Loads PDF themes.
final class ThemeLoader {
  /// A loader reporting to [logger].
  new({LoggerBase? logger}) : _logger = logger ?? LoggerManager.logger;

  final LoggerBase _logger;

  static const Map<String, String> _deprecatedCategories = {
    'blockquote': 'quote',
    'key': 'kbd',
    'literal': 'codespan',
    'outline_list': 'list',
  };

  static final Map<String, String> _deprecatedKeys = {
    'table_caption_side': 'table_caption_end',
    for (final prefix in [
      'base',
      'heading',
      'heading_h1',
      'heading_h2',
      'heading_h3',
      'heading_h4',
      'heading_h5',
      'heading_h6',
      'title_page',
      'abstract',
      'abstract_title',
      'admonition_label',
      'sidebar_title',
      'toc_title',
    ])
      '${prefix}_align': '${prefix}_text_align',
  };

  static const Set<String> _paddingBottomHacks = {
    'example_padding',
    'quote_padding',
    'sidebar_padding',
    'verse_padding',
  };

  /// The base theme, as it is (no processing).
  Theme loadBase() {
    final data = _yaml(PdfAssets.text('data/themes/base-theme.yml')!, 'base');
    final theme = Theme._({}, null);
    if (data case YMap(:final entries)) {
      for (final MapEntry(:key, :value) in entries.entries) {
        theme[key] = _fromYaml(value);
      }
    }
    return theme;
  }

  /// The theme [name] (a bundled theme's name, or a `.yml` path), looked
  /// up in [themesDir] (the bundled themes when null).
  Theme load([String? name, String? themesDir]) {
    final source = _resolve(name, themesDir);
    if (source case _Bundled(name: 'base')) return loadBase();
    final theme = Theme._({'base_font_size': const ThemeNumber(12)}, null);
    final loaded = <String>{};
    final result = _loadFile(source, theme, loaded, themesDir);
    if (source is _File && !_isBundledDirectory(source.directory)) {
      void orDefault(String key, ThemeValue value) {
        if (result.value(key) == null) result[key] = value;
      }

      orDefault('base_text_align', const ThemeString('left'));
      orDefault('base_line_height', const ThemeNumber(1));
      orDefault('base_font_color', const HexColor('000000'));
      final codespanFamily =
          result.value('codespan_font_family') ?? const ThemeString('Courier');
      orDefault('code_font_family', codespanFamily);
      orDefault('conum_font_family', codespanFamily);
      if (result.value('heading_font_family') case final family?) {
        orDefault('abstract_title_font_family', family);
        orDefault('sidebar_title_font_family', family);
      }
    }
    result.directory = switch (source) {
      _Bundled() => null,
      _File(:final directory) => directory,
    };
    return result;
  }

  /// The theme file at [path] with the themes it extends (looked up in
  /// [themesDir], else beside it), added to [theme]: the gem's
  /// `ThemeLoader.load_file`.
  Theme loadFile(String path, {Theme? theme, String? themesDir}) {
    final absolute = _absolute(path);
    return _loadFile(
      _File(absolute, themesDir ?? _dirname(absolute)),
      theme ?? Theme._({}, null),
      {},
      themesDir,
    );
  }

  /// Bundled themes are embedded: no directory on disk is theirs.
  static bool _isBundledDirectory(String directory) => false;

  _ThemeSource _resolve(String? name, String? themesDir) {
    if (name != null && name.endsWith('.yml')) {
      final path = _absolute(name, themesDir);
      return _File(
        path,
        themesDir == null ? _dirname(path) : _absolute(themesDir),
      );
    }
    if (themesDir == null) return _Bundled(name ?? 'default');
    final directory = _absolute(themesDir);
    return _File(
      _absolute('${name ?? 'default'}-theme.yml', directory),
      directory,
    );
  }

  Theme _loadFile(
    _ThemeSource source,
    Theme theme,
    Set<String> loaded,
    String? themesDir,
  ) {
    final String text;
    final String key;
    switch (source) {
      case _Bundled(:final path, :final name):
        final content = PdfAssets.text(path);
        if (content == null) {
          throw ThemeException(
            'could not locate or load the built-in pdf '
            "theme `$name'",
          );
        }
        text = content;
        key = path;
      case _File(:final path):
        try {
          text = _quoteHexColors(
            utf8.decode(io.readBytes(path)).replaceAll('\r\n', '\n'),
          );
        } on io.IoException {
          throw ThemeException(
            "could not locate or load the pdf theme `$path'",
          );
        }
        key = path;
    }
    loaded.add(key);
    final data = _yaml(text, key);
    var result = theme;
    if (data case YMap(entries: final original)) {
      final entries = {...original};
      final extends_ = entries.remove('extends');
      // `extends: ~` extends nothing (Ruby's `Array(nil)` is empty).
      if (extends_ != null && _fromYaml(extends_) != const ThemeNull()) {
        final paths = switch (extends_) {
          YList(:final items) => [for (final p in items) _rubyToS(p)],
          final other => [_rubyToS(other)],
        };
        for (var path in paths) {
          final force = path.endsWith(' !important');
          if (force) path = path.substring(0, path.length - 11);
          if (path == 'base') {
            if (loaded.add('base') || force) {
              final base = loadBase();
              result = Theme._({...result._values, ...base._values}, null);
            }
            continue;
          }
          final _ThemeSource next;
          if (bundledThemeNames.contains(path)) {
            next = _Bundled(path);
          } else if (path.startsWith('./')) {
            final from = switch (source) {
              _File(:final path) => _dirname(path),
              _Bundled() => null,
            };
            next = _resolve(path, from);
          } else {
            next = _resolve(path, themesDir);
          }
          final nextKey = switch (next) {
            _Bundled(:final path) => path,
            _File(:final path) => path,
          };
          if (loaded.add(nextKey) || force) {
            result = _loadFile(next, result, loaded, switch (next) {
              _File(:final directory) => directory,
              _Bundled() => themesDir,
            });
          }
        }
      }
      for (final MapEntry(:key, :value) in entries.entries) {
        _process(key, value, result, normalizeKey: true);
      }
    }
    return result;
  }

  /// Hex color values the YAML would read as numbers or comments, quoted
  /// (as the gem does for theme files outside its own directory).
  static String _quoteHexColors(String text) => text
      .split('\n')
      .map(
        (line) => line.replaceFirstMapped(
          RegExp(
            r'''^( *\S+): +(?!null$)(["']?)(#)?([0-9a-fA-F]{3,6})\2 *(?:#.*)?$''',
          ),
          (m) {
            final key = m[1]!;
            final quoted = m[3] != null || key.endsWith('color');
            return '$key: ${quoted ? "'${m[4]}'" : m[4]}';
          },
        ),
      )
      .join('\n');

  Y? _yaml(String text, String source) {
    try {
      return parseYaml11(text, sourceUrl: Uri.file(source));
    } on YamlException catch (error) {
      throw ThemeException('failed to load theme $source: ${error.message}');
    }
  }

  /// The theme value of a YAML node, unprocessed.
  static ThemeValue _fromYaml(Y? node) => switch (node) {
    null => const ThemeNull(),
    YScalar(:final value) => value,
    YList(:final items) => ThemeList([for (final e in items) _fromYaml(e)]),
    YMap(:final entries) => ThemeMap({
      for (final MapEntry(:key, :value) in entries.entries)
        key: _fromYaml(value),
    }),
  };

  /// Loads the entries of the YAML document [text] into [theme] (a new
  /// theme when null), without resolving `extends`: the gem's
  /// `ThemeLoader#load`.
  Theme loadYaml(String text, [Theme? theme]) {
    final data = theme ?? Theme._({}, null);
    if (_yaml(text, 'theme') case YMap(:final entries)) {
      for (final MapEntry(:key, :value) in entries.entries) {
        _process(key, value, data, normalizeKey: true);
      }
    }
    return data;
  }

  void _process(
    String rawKey,
    Y? value,
    Theme data, {
    bool normalizeKey = false,
  }) {
    var key = normalizeKey ? rawKey.replaceAll('-', '_') : rawKey;
    if (key == 'font') {
      if (value case YMap(:final entries)) {
        for (final MapEntry(key: sub, value: v) in entries.entries) {
          if (sub == 'catalog' || sub == 'fallbacks') {
            _process('font_$sub', v, data);
          }
        }
      }
    } else if (key == 'font_catalog') {
      data[key] = _catalog(value, data) ?? const ThemeNull();
    } else if (key == 'font_fallbacks') {
      data[key] = ThemeList([
        if (value case YList(:final items))
          for (final name in items)
            ThemeString(_expand(_rubyToS(name), data).rubyString),
      ]);
    } else if (key.startsWith('admonition_icon_')) {
      if (value case YMap(:final entries)) {
        data[key] = ThemeMap({
          for (final MapEntry(key: k, value: v) in entries.entries)
            k.replaceAll('-', '_'): k.endsWith('_color') || k.endsWith('-color')
                ? _toColor(_evaluate(v, data, math: false))
                : _evaluate(v, data),
        });
      }
    } else if (value is YMap) {
      if (_deprecatedCategories[key] case final rekey?) {
        _logger.warn(
          'the ${key.replaceAll('_', '-')} theme category is deprecated; use '
          'the ${rekey.replaceAll('_', '-')} category instead',
        );
        key = rekey;
      }
      for (final MapEntry(key: subKey, value: v) in value.entries.entries) {
        final part = key == 'role' || !subKey.contains('-')
            ? subKey
            : subKey.replaceAll('-', '_');
        _process('${key}_$part', v, data);
      }
    } else if (_deprecatedKeys[key] case final rekey?) {
      data[rekey] = _evaluate(value, data, math: false);
    } else if (key.startsWith('role_') &&
        key.endsWith('_align') &&
        RegExp(r'(?:_text)?_align$').hasMatch(key)) {
      data[key.replaceFirst(RegExp(r'(?:_text)?_align$'), '_text_align')] =
          _evaluate(value, data, math: false);
    } else if (_paddingBottomHacks.contains(key)) {
      var v = _evaluate(value, data);
      if (v case ThemeList(:final values) when values.length > 2) {
        final top = _toFloat(values[0]);
        final bottom = _toFloat(values[2]);
        if (top >= 0 && bottom <= 0) {
          v = ThemeList([...values]..[2] = values[0]);
        }
      }
      data[key] = v;
    } else if (key.endsWith('_color')) {
      if (value case YList(:final items)
          when key == 'table_border_color' ||
              (key == 'table_grid_color' && items.length == 2)) {
        data[key] = ThemeList([
          for (final v in items) _toColor(_evaluate(v, data, math: false)),
        ]);
      } else {
        data[key] = _toColor(_evaluate(value, data, math: false));
      }
    } else if (key.endsWith('_content')) {
      data[key] = ThemeString(_expand(_rubyToS(value), data).rubyString);
    } else {
      data[key] = _evaluate(value, data);
    }
  }

  /// [value] as Ruby's `to_s` writes it.
  static String _rubyToS(Y? value) => _fromYaml(value).rubyString;

  static double _toFloat(ThemeValue value) => switch (value) {
    ThemeNumber(:final value) => value.toDouble(),
    final v => _rubyToF(v.rubyString),
  };

  /// Ruby's `String#to_f`: the leading number, or 0.
  static double _rubyToF(String text) =>
      double.tryParse(
        RegExp(r'^\s*[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?')
                .stringMatch(text) ??
            '',
      ) ??
      0;

  /// Ruby's `String#to_i`.
  static int _rubyToI(String text) =>
      int.tryParse(RegExp(r'^\s*[+-]?\d+').stringMatch(text)?.trim() ?? '') ??
      0;

  ThemeFontCatalog? _catalog(Y? value, Theme data) {
    if (value is! YMap) return null;
    final entries = {...value.entries};
    final merge = entries.remove('merge');
    final mergeValue = _fromYaml(merge);
    final families = <String, Map<String, String>>{
      if (merge != null &&
          mergeValue != const ThemeBool(false) &&
          mergeValue != const ThemeNull())
        ...?data.fontCatalog?.families.map((k, v) => MapEntry(k, {...v})),
    };
    for (final MapEntry(key: name, value: styles) in entries.entries) {
      final styleMap = switch (styles) {
        YScalar(value: ThemeString()) => {'*': styles},
        YMap(:final entries) => entries,
        _ => null,
      };
      if (styleMap == null) continue;
      final out = <String, String>{};
      for (final MapEntry(key: style, value: pathValue) in styleMap.entries) {
        var path = _rubyToS(pathValue);
        if (path.startsWith('GEM_FONTS_DIR') && path.length > 13) {
          path = 'GEM_FONTS_DIR/${path.substring(14)}';
        }
        final expanded = _expand(path, data).rubyString;
        switch (style) {
          case '*':
            for (final s in ['normal', 'bold', 'italic', 'bold_italic']) {
              out[s] = expanded;
            }
          case 'regular':
            out['normal'] = expanded;
          default:
            out[style] = expanded;
        }
      }
      families[name] = out;
    }
    return ThemeFontCatalog(families);
  }

  ThemeValue _evaluate(Y? expression, Theme vars, {bool math = true}) =>
      switch (expression) {
        YScalar(value: ThemeString(value: final s)) =>
          math ? _evaluateMath(_expand(s, vars)) : _expand(s, vars),
        YList(:final items) => ThemeList([
          for (final e in items) _evaluate(e, vars, math: math),
        ]),
        _ => _fromYaml(expression),
      };

  static final RegExp _variable = RegExp(r'\$([a-z0-9_-]+)');
  static final RegExp _loneVariable = RegExp(r'^\$([a-z0-9_-]+)$');

  /// [expression] with its variables replaced: a lone variable gives the
  /// variable's value, others are substituted as strings.
  ThemeValue _expand(String expression, Theme vars) {
    final index = expression.indexOf(r'$');
    if (index < 0) return ThemeString(expression);
    if (index == 0) {
      if (_loneVariable.firstMatch(expression) case final m?) {
        return _resolveVariable(vars, expression, m[1]!);
      }
    } else if (index == 1 && expression.startsWith('-')) {
      final negated = expression.substring(1);
      if (_loneVariable.firstMatch(negated) case final m?) {
        final value = _resolveVariable(vars, negated, m[1]!);
        return switch (value) {
          ThemeNumber(:final value) => ThemeNumber(-value),
          final other => ThemeString('-${other.rubyString}'),
        };
      }
    }
    return ThemeString(
      expression.replaceAllMapped(
        _variable,
        (m) => _resolveVariable(vars, m[0]!, m[1]!).rubyString,
      ),
    );
  }

  ThemeValue _resolveVariable(Theme vars, String reference, String name) {
    var variable = name.replaceAll('-', '_');
    if (!vars.has(variable)) {
      String? replacement;
      for (final MapEntry(key: old, value: renamed)
          in _deprecatedCategories.entries) {
        if (variable.startsWith('${old}_')) {
          final candidate = renamed + variable.substring(old.length);
          if (vars.has(candidate)) {
            replacement = candidate;
            break;
          }
        }
      }
      replacement ??= switch (_deprecatedKeys[variable]) {
        final key? when vars.has(key) => key,
        _ => null,
      };
      if (replacement == null) {
        _logger.warn('unknown variable reference in PDF theme: $reference');
        return ThemeString(reference);
      }
      variable = replacement;
    }
    return vars[variable] ?? const ThemeNull();
  }

  static final RegExp _multiplyDivide = RegExp(
    r'(-?\d+(?:\.\d+)?) +([*/^]) +(-?\d+(?:\.\d+)?)',
  );
  static final RegExp _addSubtract = RegExp(
    r'(-?\d+(?:\.\d+)?) +([+-]) +(-?\d+(?:\.\d+)?)',
  );
  static final RegExp _precision = RegExp(r'^(round|floor|ceil)\(');

  /// The value of [value]'s arithmetic, when it is a string with some.
  ThemeValue _evaluateMath(ThemeValue value) {
    if (value is! ThemeString) return value;
    final original = value.value;
    var expression = resolveMeasurementValues(original);
    while (RegExp('[*/^]').hasMatch(expression)) {
      final result = expression.replaceAllMapped(_multiplyDivide, (m) {
        final a = double.parse(m[1]!);
        final b = double.parse(m[3]!);
        return rubyNumber(switch (m[2]) {
          '*' => a * b,
          '/' => a / b,
          _ => _power(a, b),
        });
      });
      if (result == expression) break;
      expression = result;
    }
    while (RegExp('[+-]').hasMatch(expression)) {
      final result = expression.replaceAllMapped(_addSubtract, (m) {
        final a = double.parse(m[1]!);
        final b = double.parse(m[3]!);
        return rubyNumber(m[2] == '+' ? a + b : a - b);
      });
      if (result == expression) break;
      expression = result;
    }
    if (expression.endsWith(')')) {
      if (_precision.firstMatch(expression) case final m?) {
        final op = m[1]!;
        final number = _rubyToF(
          expression.substring(op.length + 1, expression.length - 1),
        );
        expression = switch (op) {
          'round' => '${_rubyRound(number)}',
          'floor' => '${number.floor()}',
          _ => '${number.ceil()}',
        };
      }
    }
    if (expression == original) return value;
    final integer = _rubyToI(expression);
    final float = _rubyToF(expression);
    return integer == float ? ThemeNumber(integer) : ThemeNumber(float);
  }

  static double _power(double a, double b) => math.pow(a, b).toDouble();

  /// Ruby's `Float#round` (half away from zero).
  static int _rubyRound(double value) =>
      value < 0 ? -((-value) + 0.5).floor() : (value + 0.5).floor();

  ThemeValue _toColor(ThemeValue value) {
    switch (value) {
      case ThemeColor():
        return value;
      case ThemeList(:final values) when values.length == 4:
        final components = [
          for (final e in values)
            () {
              var n = switch (e) {
                ThemeNumber(:final value) => value <= 1 ? value * 100.0 : value,
                final other => _rubyToF(other.rubyString.replaceAll('%', '')),
              };
              if (n == n.toInt()) n = n.toInt();
              return n;
            }(),
        ];
        if (components.every((c) => c == 0)) return const HexColor('FFFFFF');
        if (components.every((c) => c == 100)) return const HexColor('000000');
        return CmykThemeColor(components);
      case ThemeList(:final values) when values.length == 3:
        return HexColor(
          [
            for (final e in values)
              (switch (e) {
                ThemeNumber(:final value) => value.toInt(),
                final other => _rubyToI(other.rubyString),
              }).toRadixString(16).toUpperCase().padLeft(2, '0'),
          ].join(),
        );
      case ThemeNull():
        return value;
      default:
        break;
    }
    var text = switch (value) {
      ThemeList(:final values) => values.map((v) => v.rubyString).join(),
      final other => other.rubyString,
    };
    if (value is ThemeString && text == 'transparent') {
      return const TransparentColor();
    }
    if (text.length == 6) return HexColor(text.toUpperCase());
    text = switch (text.length) {
      3 => text.split('').map((c) => '$c$c').join(),
      _ => (text.length > 6 ? text.substring(0, 6) : text).padLeft(6, '0'),
    };
    return HexColor(text.toUpperCase());
  }
}

/// A theme that can't be loaded.
final class ThemeException implements Exception {
  /// An exception with [message].
  const new(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => message;
}

final RegExp _measurementHint = RegExp(r'\d(in|mm|cm|p[txc])');
final RegExp _insetMeasurement = RegExp(
  r'(?<=^| |\()(-?\d+(?:\.\d+)?)(in|mm|cm|p[txc])(?=$| |\))',
);

/// [value] in points from [units] (`in`, `mm`, `cm`, `px`, `pc`, `pt`).
double toPoints(double value, String? units) => switch (units) {
  null || '' || 'pt' => value,
  'in' => value * 72,
  'mm' => value * (72 / 25.4),
  'cm' => value * (720 / 25.4),
  'px' => value * 0.75,
  'pc' => value * 12,
  _ => throw ArgumentError('unknown unit of measurement: $units'),
};

/// [text] with its measurements (`0.5in`) in points (`36.0`).
String resolveMeasurementValues(String text) {
  if (!_measurementHint.hasMatch(text)) return text;
  return text.replaceAllMapped(
    _insetMeasurement,
    (m) => rubyNumber(toPoints(double.parse(m[1]!), m[2])),
  );
}

/// [text] in points: a number with an optional unit (`0.5in`, `100px`);
/// anything else is read as Ruby's `to_f` reads it.
double strToPoints(String text) {
  final m = RegExp(r'(\d+|\d*\.\d+)(in|mm|cm|p[txc])?$').firstMatch(text);
  if (m != null) return toPoints(double.parse(m[1]!), m[2]);
  return double.tryParse(text) ?? 0;
}

/// [path] made absolute against [base] (the working directory when null).
String _absolute(String path, [String? base]) =>
    PathResolver().systemPath(path, start: base);

/// The directory part of [path] (Ruby's `File.dirname`).
String _dirname(String path) {
  final index = path.lastIndexOf('/');
  return index <= 0 ? (index == 0 ? '/' : '.') : path.substring(0, index);
}
