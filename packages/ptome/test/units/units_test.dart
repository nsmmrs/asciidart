// Documents in units (ADR-0019): ptome reads the units syntax itself, and
// its output equals its output for the oracle's rendering of the same
// document (`*.lowered.adoc`, written by the loci experiment's lowering).
import 'package:ptome/src/internal.dart';
import 'package:test/test.dart';

const _fixtures = 'test/units/fixtures';

String _convert(String path, String backend, {bool native = false}) => loadFile(
  path,
  options: AsciidoctorOptions(
    safe: SafeMode.unsafe,
    backend: backend,
    standalone: true,
    attributes: {
      'reproducible': '',
      'units-engine': ?(native ? 'native' : null),
    },
  ),
).convert();

void main() {
  for (final doc in ['bible/sample', 'law/eu-sample']) {
    for (final backend in ['html5', 'docbook5']) {
      test('$doc ($backend): the same as its rendering', () {
        expect(
          _convert('$_fixtures/$doc.adoc', backend),
          _convert('$_fixtures/$doc.lowered.adoc', backend),
        );
      });
    }
  }

  test('markers become anchors and labels; notes, ranges and terms render', () {
    final html = _convert('$_fixtures/bible/sample.adoc', 'html5');
    expect(html, contains('id="v-exo-34-6"'));
    expect(html, contains('<sup>6</sup>'));
    // The divine name in small capitals, the words of Jesus as a range.
    expect(html, contains('<span class="nd">Lord</span>'));
    expect(html, contains('<span class="wj">Blessed'));
    // A reference by address is a link to the verse.
    expect(html, contains('href="#v-exo-34-6"'));
    expect(html, isNot(contains('@ ')));
  });

  test('parallel texts: two documents side by side, by address', () {
    final html = _convert('$_fixtures/bible/psalm23-parallel.adoc', 'html5');
    // A heading that is only a marker shows its unit's name.
    expect(html, contains('<h4 id="_psalms_23">Psalms 23</h4>'));
    // Each verse a row: the translation beside it, matched by address.
    final row = RegExp(
      r'<tr>\s*<td[^>]*><p[^>]*><a id="v-psa-23-1"></a><sup>1</sup>&#160;'
      r'The LORD <em>is</em> my shepherd; I shall not want.</p></td>\s*'
      '<td[^>]*><p[^>]*><sup>1</sup>&#160;Dominus regit me, et nihil '
      'mihi deerit:</p></td>',
    );
    expect(html, matches(row));
  });

  test('a document without :units: is read as before', () {
    expect(
      _convert('$_fixtures/plain.adoc', 'html5'),
      contains('@ stays text, note:x[not a note].'),
    );
  });

  test('labels out of order warn through the logger', () {
    final logger = MemoryLogger();
    final previous = LoggerManager.logger;
    LoggerManager.logger = logger;
    addTearDown(() => LoggerManager.logger = previous);
    _convert('$_fixtures/bible/out-of-order.adoc', 'html5');
    expect(
      logger.messages.map((m) => m.message.text).join('\n'),
      contains('out-of-order.adoc:10:1: verse 2 after 5'),
    );
  });

  group('native (ADR-0020)', () {
    String html(String doc) =>
        _convert('$_fixtures/$doc.adoc', 'html5', native: true);

    test('headings that are units: ID, title, role and attributes', () {
      final out = html('bible/sample');
      expect(out, contains('<div class="sect1 book">'));
      expect(out, contains('<h2 id="b-exo">Exodus</h2>'));
      expect(out, contains('<div class="sect2 chapter">'));
      expect(out, contains('<h3 id="c-exo-34">Chapter 34</h3>'));
    });

    test('markers print anchors and labels, never the syntax', () {
      final out = html('bible/sample');
      expect(out, contains('<a id="v-exo-34-6"></a><sup>6</sup>\u00a0'));
      // The first verse of a chapter has its anchor but no number.
      expect(out, contains('<p><a id="v-exo-34-1"></a>And the'));
      final body = out.substring(out.indexOf('<body'));
      expect(body, isNot(contains('@')));
      expect(body, isNot(contains('note:')));
    });

    test('notes: callers and entries, footnotes with origin and lemma', () {
      final out = html('bible/sample');
      expect(
        out,
        contains('<span class="xref"><strong>34:6</strong> <sup>a</sup>\u00a0'),
      );
      expect(out, contains('<sup class="xref-mark">a</sup>merciful'));
      expect(
        out,
        contains('<strong>34:7</strong> <em>forgiving</em>: Heb. bearing'),
      );
    });

    test('ranges and terms are role spans around the markup inside', () {
      final out = html('bible/sample');
      expect(out, contains('<span class="nd">Lord</span>'));
      expect(
        out,
        contains('<span class="wj">Blessed <em>are</em> the poor in spirit'),
      );
      // A range that crosses markup: a span on each side of the tag.
      expect(
        html('bible/native'),
        contains(
          '<span class="wj">without </span><strong>'
          '<span class="wj">form</span> and</strong>',
        ),
      );
    });

    test('a note keeps brackets in its text', () {
      expect(
        html('bible/native'),
        contains('<em>God</em>: the word [Elohim] is plural'),
      );
    });

    test('block units: the block is the unit; `@^` resumes', () {
      final out = html('law/eu-sample');
      expect(out, contains('<div id="art-6-1-a" class="paragraph point">'));
      expect(out, contains('<p>(a) the data subject'));
      expect(out, contains('<div class="paragraph paragraph resumed">'));
      expect(out, contains('Point <a href="#art-6-1-f">(f)</a> of'));
    });

    test('the source keeps its syntax; DocBook renders too', () {
      final doc = loadFile(
        '$_fixtures/bible/sample.adoc',
        options: const AsciidoctorOptions(
          safe: SafeMode.unsafe,
          attributes: {'units-engine': 'native'},
        ),
      );
      final verse = doc.findBy(context: BlockContext.paragraph).first as Block;
      expect(verse.source(), startsWith('@ And the LORD'));
      expect(
        _convert('$_fixtures/bible/sample.adoc', 'docbook5', native: true),
        contains('<anchor xml:id="v-exo-34-6"'),
      );
    });
  });
}
