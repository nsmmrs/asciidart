/// The pages a layout is drawn on, and the document that makes them: the
/// interfaces a backend implements (plain_pdf's `LayoutPage` and
/// `PdfDocument`).
library;

import 'package:plain_typesetting/src/canvas.dart';
import 'package:plain_typesetting/src/geometry.dart';
import 'package:plain_typesetting/src/link.dart';

/// A page: what is drawn on it, and its links.
abstract interface class LayoutPage {
  /// What the page's content is drawn on.
  Canvas get canvas;

  /// Makes [rect] a link to [target].
  void link(Rect rect, LinkTarget target);
}

/// A document a layout adds its pages of type [P] to.
abstract interface class LayoutDocument<P extends LayoutPage> {
  /// Adds a page that is [mediaBox], with the [bleedBox] and the [trimBox]
  /// when the page bleeds; returns it.
  P addPage(Rect mediaBox, {Rect? bleedBox, Rect? trimBox});

  /// Makes the point ([left], [top]) of [page] the destination [name].
  void addAnchor(String name, P page, double left, double top);
}
