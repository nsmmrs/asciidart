/// How units look (scheme format v2, ADR-0020 decision 5): text templates
/// for what a unit prints, and how each part is set (a style and a role),
/// with no markup. Converters render the parts in each backend's own way.
library;

import 'package:ptome/src/units/scheme_yaml.dart';

/// How a printed part is set.
enum PartStyle {
  /// As text.
  plain,

  /// Raised (a verse number).
  superscript,

  /// In bold (a question's number).
  strong,

  /// In italics (a lemma).
  emphasis;

  /// The style named [name] (`plain` when `null`).
  static PartStyle parse(String? name) =>
      name == null ? plain : values.byName(name);
}

/// How the units of a level look.
final class LevelLook {
  /// The look a level's scheme-file entries give ([map]).
  new(this.map);

  /// The level's entries.
  final SchemeMap map;

  /// What a unit prints at its start (a template); `null` or empty: no
  /// label.
  String? get label => map.string('label');

  /// How the label is set.
  PartStyle get labelStyle => PartStyle.parse(map.string('label-style'));

  /// The role the label is set in, if any (`pnum`, `lineno`).
  String? get labelRole => map.string('label-role');

  /// Text before the label.
  String get labelBefore => map.string('label-before') ?? '';

  /// Text after the label (a space, a no-break space).
  String get labelAfter => map.string('label-after') ?? '';

  /// Whether a unit's start is an anchor (its ID); `anchor: false` for a
  /// unit only its label marks.
  bool get anchor => map.flag('anchor') ?? true;

  /// More anchors at a unit's start, as templates (a through-line number).
  List<String> get anchors => map.strings('anchors');

  /// Text between what a unit prints and its text (a shared line's
  /// indentation), a template.
  String? get indent => map.string('indent');

  /// The title of a section that is a unit, a template (with `title`, the
  /// title as written); `null`: the title as written, or the label.
  String? get title => map.string('title');

  /// The role of a section or block that is a unit.
  String? get role => map.string('role');

  /// More attributes of a section that is a unit, as templates.
  Map<String, String> get attributes => map.map('attributes')?.templates ?? {};

  /// The role of a block a unit starts (a statute's paragraph).
  String? get blockRole => map.string('block-role');

  /// Options of a block a unit starts (`hardbreaks`).
  List<String> get blockOptions => map.strings('block-options');

  /// What a unit prints at its end, a template (an ayah's number).
  String? get end => map.string('end');

  /// The role the end text is set in.
  String? get endRole => map.string('end-role');

  /// Text before the end text.
  String get endBefore => map.string('end-before') ?? '';

  /// Whether the end text goes on a line of its own (a response).
  bool get endBreak => map.string('end-break') == 'line';

  /// This look with [overrides]' entries added over its own.
  LevelLook merged(SchemeMap overrides) => LevelLook(map.merged(overrides));
}

/// How the notes of a stream look.
final class StreamLook {
  /// The look a stream's scheme-file entries give ([map]).
  new(this.map);

  /// The stream's entries.
  final SchemeMap map;

  /// How a caller is set (in the text and in an entry).
  PartStyle get callerStyle => PartStyle.parse(map.string('caller-style'));

  /// The role a caller in the text is set in (`xref-mark`).
  String? get callerRole => map.string('caller-role');

  /// Text after a caller in an entry.
  String get callerAfter => map.string('caller-after') ?? '';

  /// How a note's origin is set (`34:7`).
  PartStyle get originStyle => PartStyle.parse(map.string('origin-style'));

  /// How a note's lemma is set.
  PartStyle get lemmaStyle => PartStyle.parse(map.string('lemma-style'));

  /// Text after a lemma (`: `).
  String get lemmaAfter => map.string('lemma-after') ?? '';

  /// Text before a note's body (`M: `).
  String get prefix => map.string('prefix') ?? '';

  /// The role of an entry (the notes gathered at a unit).
  String? get entryRole => map.string('entry-role');

  /// Text after an entry.
  String get entryAfter => map.string('entry-after') ?? '';

  /// Whether an entry is a block of its own (a catechism's proofs).
  bool get entryBlock => map.string('entry-break') == 'block';

  /// Text between two notes of an entry.
  String get noteSeparator => map.string('note-separator') ?? ' ';
}
