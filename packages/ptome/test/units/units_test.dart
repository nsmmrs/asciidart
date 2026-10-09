// Documents in units (ADR-0020): ptome's parser reads the units syntax,
// the engine analyzes it, and every backend renders what units print as
// inline and block nodes of their own kinds.
import 'package:ptome/src/internal.dart';
import 'package:test/test.dart';

const _fixtures = 'test/units/fixtures';

String _convert(String path, String backend) => loadFile(
  path,
  options: AsciidoctorOptions(
    safe: SafeMode.unsafe,
    backend: backend,
    standalone: true,
    attributes: const {'reproducible': ''},
  ),
).convert();

void main() {
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

  group('rendering', () {
    String html(String doc) => _convert('$_fixtures/$doc.adoc', 'html5');

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
        options: const AsciidoctorOptions(safe: SafeMode.unsafe),
      );
      final verse = doc.findBy(context: BlockContext.paragraph).first as Block;
      expect(verse.source(), startsWith('@ And the LORD'));
      expect(
        _convert('$_fixtures/bible/sample.adoc', 'docbook5'),
        contains('<anchor xml:id="v-exo-34-6"'),
      );
    });

    test('includes: a block again by ID, a passage quoted and spliced', () {
      final out = html('bible/includes');
      // The repeat has no ID of its own.
      expect('class="quoteblock verse"'.allMatches(out), hasLength(2));
      expect('id="refrain"'.allMatches(out), hasLength(1));
      // Quoted: no anchors or numbers, cited.
      expect(
        out,
        contains(
          '<blockquote>\n<div class="paragraph">\n<p>And the '
          '<span class="nd">Lord</span> passed by',
        ),
      );
      expect(out, contains('&#8212; Exodus 34:6–7'));
      // Spliced: as the work prints it.
      expect(
        out,
        contains('<a id="v-mat-5-4"></a><sup>4</sup>\u00a0<span class="wj">'),
      );
    });

    test('parallel texts: a table, unit by unit', () {
      final out = html('bible/psalm23-parallel');
      expect(out, contains('class="tableblock frame-none grid-rows'));
      expect(
        out,
        matches(
          RegExp(
            r'<td[^>]*><p[^>]*><a id="v-psa-23-1"></a><sup>1</sup>\u00a0'
            'The <span class="nd">Lord</span> <em>is</em> my shepherd',
          ),
        ),
      );
    });
  });
}
