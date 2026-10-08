// TextBox keeps its placements: the layout probes a text many times over
// and lays the document out again for its index, footnote numbers and page
// references.
import 'package:ptome/src/logging.dart';
import 'package:ptome/src/pdf/fonts.dart';
import 'package:ptome/src/pdf/markup.dart';
import 'package:ptome/src/pdf/text_box.dart';
import 'package:ptome/src/pdf/theme.dart';
import 'package:test/test.dart';

void main() {
  final logger = MemoryLogger();
  TextBox box(String text, {TextLayout layout = const TextLayout()}) => TextBox(
    [Fragment(text)],
    const TextState(family: 'Helvetica', size: 10),
    layout,
    TextContext(
      fonts: FontCatalog(ThemeLoader(logger: logger).loadYaml('')),
      rootSize: 10,
      logger: logger,
    ),
  );

  setUp(logger.clear);

  test('the same placement for the same room', () {
    final text = box('word ' * 400, layout: const TextLayout(orphans: 2));
    final placed = text.place(100, 60, atTop: false);
    expect(placed, isNotNull);
    expect(placed!.rest, isNotNull);
    expect(text.place(100, 60, atTop: false), same(placed));
    final other = text.place(100, 80, atTop: false);
    expect(other, isNot(same(placed)));
    expect(other!.height, greaterThan(placed.height));
    expect(text.place(100, 60, atTop: true), isNot(same(placed)));
    expect(logger.messages, isEmpty);
  });

  test('text that cannot fit is reported on every placement', () {
    final text = box('word');
    for (var i = 1; i <= 3; i++) {
      final placed = text.place(100, 1, atTop: true);
      expect(placed!.height, 0);
      expect(logger.messages, hasLength(i));
      expect(
        logger.messages.last.message.text,
        startsWith('cannot fit formatted text on page'),
      );
    }
    // A probe that is not at the top of a region leaves the text for the
    // next region, quietly.
    expect(text.place(100, 1, atTop: false), isNull);
    expect(logger.messages, hasLength(3));
  });
}
