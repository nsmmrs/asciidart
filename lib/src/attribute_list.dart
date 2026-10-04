/// AsciiDoc attribute list parsing for the Dart port of Asciidoctor.
///
/// Port of `lib/asciidoctor/attribute_list.rb`.
library;

import 'dart:math' show min;

import 'core_ext.dart';

/// Minimal surface of a block needed by [AttributeList]: single-quoted
/// values have substitutions applied through [applySubs].
abstract class SubsApplier {
  /// Applies substitutions to [value] and returns the result.
  String applySubs(String value);
}

/// Parses AsciiDoc attribute lists into key/value pairs.
///
/// Attributes are separated by commas and values may be quoted. A value
/// without a key is assigned to a 1-based positional key; positional
/// attributes can be "rekeyed" via [parse]'s [positionalAttrs] argument or
/// after the fact with [rekey].
///
/// ```dart
/// final attrlist = AttributeList('quote, Famous Person, Famous Book (2001)');
/// attrlist.parse(['style', 'attribution', 'citetitle']);
/// // {1: 'quote', 'style': 'quote', 2: 'Famous Person', ...}
/// ```
class AttributeList {
  /// Creates a parser for [source], optionally applying substitutions
  /// through [block]. Only the default comma [delimiter] is supported.
  AttributeList(String source, [SubsApplier? block, String delimiter = ','])
    : _scanner = _StringScanner(source),
      _block = block,
      _delimiter = delimiter {
    if (delimiter != ',') {
      throw ArgumentError('Only the default comma delimiter is supported');
    }
  }

  // Attribute name: word char followed by word chars or hyphens. Ruby's
  // `\p{Word}` is unknown to Dart's RegExp, hence the emulation, verified
  // equivalent against Ruby over letters, marks, decimal numbers,
  // connector punctuation and join controls (see ADR-0001 D1 notes).
  static final RegExp _nameRx = RegExp(
    '[\\p{Alpha}\\p{M}\\p{Nd}\\p{Pc}\u200C\u200D][\\p{Alpha}\\p{M}\\p{Nd}\\p{Pc}\u200C\u200D-]*',
    unicode: true,
  );
  static final RegExp _blankRx = RegExp('[ \t]+');
  static final RegExp _skipComma = RegExp('[ \t]*(,|\$)');
  static final RegExp _boundaryComma = RegExp('.*?(?=[ \t]*(,|\$))');
  static final RegExp _boundaryQuot = RegExp(r'.*?[^\\](?=")');
  static final RegExp _boundaryApos = RegExp(r".*?[^\\](?=')");

  static const String _apos = "'";
  static const String _quot = '"';
  static const String _backslash = r'\';

  final _StringScanner _scanner;
  final SubsApplier? _block;
  final String _delimiter;
  Map<Object, String?>? _attributes;

  /// Parses the source into [attributes] and returns it.
  Map<Object, String?> parseInto(
    Map<Object, String?> attributes, [
    List<String?> positionalAttrs = const [],
  ]) {
    attributes.addAll(parse(positionalAttrs));
    return attributes;
  }

  /// Parses the source into a map of attribute names (or 1-based positional
  /// keys) to values. Blank positional attributes map to `null`.
  Map<Object, String?> parse([List<String?> positionalAttrs = const []]) {
    final cached = _attributes;
    if (cached != null) return cached;
    final attributes = <Object, String?>{};
    _attributes = attributes;
    var index = 0;
    while (_parseAttribute(index, positionalAttrs)) {
      if (_scanner.isEos) break;
      _skipDelimiter();
      index++;
    }
    return attributes;
  }

  /// Rekeys this list's positional attributes per [positionalAttrs].
  Map<Object, String?> rekey(List<String?> positionalAttrs) =>
      AttributeList.rekeyAttributes(_attributes!, positionalAttrs);

  /// Assigns positional attribute names to the positional entries of
  /// [attributes]: entry `index + 1` (when non-`null`) is also stored under
  /// `positionalAttrs[index]` (when non-`null`). Returns [attributes].
  static Map<Object, String?> rekeyAttributes(
    Map<Object, String?> attributes,
    List<String?> positionalAttrs,
  ) {
    for (var index = 0; index < positionalAttrs.length; index++) {
      final key = positionalAttrs[index];
      if (key == null) continue;
      final val = attributes[index + 1];
      if (val == null) continue;
      attributes[key] = val;
    }
    return attributes;
  }

  bool _parseAttribute(int index, List<String?> positionalAttrs) {
    var cont = true;
    _skipBlank();
    String? name;
    String? value;
    var singleQuoted = false;
    final peeked = _scanner.peek(1);
    if (peeked == _quot) {
      name = _parseAttributeValue(_scanner.getByte()!);
    } else if (peeked == _apos) {
      name = _parseAttributeValue(_scanner.getByte()!);
      if (!name.startsWith(_apos)) singleQuoted = true;
    } else {
      final scannedName = _scanName();
      final skipped = scannedName == null ? 0 : (_skipBlank() ?? 0);
      name = scannedName;
      if (_scanner.isEos) {
        if (name == null && !_scanner.string.rstrip().endsWith(_delimiter)) {
          return false;
        }
        cont = false;
      } else {
        final c = _scanner.getByte()!;
        if (c == _delimiter) {
          _scanner.unscan();
        } else if (name != null) {
          if (c == '=') {
            _skipBlank();
            final c2 = _scanner.getByte();
            if (c2 != null && c2 == _quot) {
              value = _parseAttributeValue(c2);
            } else if (c2 != null && c2 == _apos) {
              value = _parseAttributeValue(c2);
              if (!value.startsWith(_apos)) singleQuoted = true;
            } else if (c2 == _delimiter) {
              value = '';
              _scanner.unscan();
            } else if (c2 == null) {
              value = '';
            } else {
              value = '$c2${_scanToDelimiter() ?? ''}';
              if (value == 'None') return true;
            }
          } else {
            name = '$name${' ' * skipped}$c${_scanToDelimiter() ?? ''}';
          }
        } else {
          name = '$c${_scanToDelimiter() ?? ''}';
        }
      }
    }

    final attributes = _attributes!;
    if (value != null) {
      if (name == 'options' || name == 'opts') {
        if (value.contains(',')) {
          var list = value;
          if (list.contains(' ')) list = list.replaceAll(' ', '');
          for (final opt in list.split(',')) {
            if (opt.isNotEmpty) attributes['$opt-option'] = '';
          }
        } else {
          if (value.isNotEmpty) attributes['$value-option'] = '';
        }
      } else {
        final block = _block;
        if (singleQuoted &&
            block != null &&
            name != 'title' &&
            name != 'reftext') {
          attributes[name!] = block.applySubs(value);
        } else {
          attributes[name!] = value;
        }
      }
    } else {
      final block = _block;
      if (singleQuoted && block != null && name != null) {
        name = block.applySubs(name);
      }
      final positionalName = index < positionalAttrs.length
          ? positionalAttrs[index]
          : null;
      if (positionalName != null && name != null) {
        attributes[positionalName] = name;
      }
      attributes[index + 1] = name;
    }

    return cont;
  }

  String _parseAttributeValue(String quote) {
    // Empty quoted value.
    if (_scanner.peek(1) == quote) {
      _scanner.getByte();
      return '';
    }
    final value = _scanToQuote(quote);
    if (value != null) {
      _scanner.getByte();
      return value.contains(_backslash)
          ? value.replaceAll('$_backslash$quote', quote)
          : value;
    }
    // Leading quote only.
    return '$quote${_scanToDelimiter() ?? ''}';
  }

  int? _skipBlank() => _scanner.skip(_blankRx);

  int? _skipDelimiter() => _scanner.skip(_skipComma);

  String? _scanName() => _scanner.scan(_nameRx);

  String? _scanToDelimiter() => _scanner.scan(_boundaryComma);

  String? _scanToQuote(String quote) =>
      _scanner.scan(quote == _quot ? _boundaryQuot : _boundaryApos);
}

/// Minimal port of Ruby's `StringScanner` covering the operations
/// [AttributeList] needs: all matches are anchored at the scan position.
class _StringScanner {
  _StringScanner(this.string);

  /// The scanned string.
  final String string;
  int _pos = 0;
  int _prevPos = 0;

  /// Whether the scan position is at the end of the string.
  bool get isEos => _pos >= string.length;

  /// Returns up to [n] characters from the scan position without advancing.
  String peek(int n) => string.substring(_pos, min(_pos + n, string.length));

  /// Consumes and returns the next character (one rune), or `null` at end.
  ///
  /// Ruby's `get_byte` advances a single byte; advancing a whole rune keeps
  /// multibyte characters intact while behaving identically for the ASCII
  /// delimiters, quotes and operators this scanner inspects.
  String? getByte() {
    if (isEos) return null;
    _prevPos = _pos;
    var end = _pos + 1;
    final first = string.codeUnitAt(_pos);
    if ((first & 0xfc00) == 0xd800 && end < string.length) {
      final second = string.codeUnitAt(end);
      if ((second & 0xfc00) == 0xdc00) end++;
    }
    final result = string.substring(_pos, end);
    _pos = end;
    return result;
  }

  /// Restores the scan position to before the most recent match.
  void unscan() {
    _pos = _prevPos;
  }

  /// Matches [pattern] at the scan position, advancing past it on success.
  String? scan(RegExp pattern) {
    final match = pattern.matchAsPrefix(string, _pos);
    if (match == null) return null;
    _prevPos = _pos;
    _pos = match.end;
    return match.group(0);
  }

  /// Skips [pattern] at the scan position, returning the matched length.
  int? skip(RegExp pattern) {
    final match = pattern.matchAsPrefix(string, _pos);
    if (match == null) return null;
    _prevPos = _pos;
    _pos = match.end;
    return match.end - _prevPos;
  }
}
