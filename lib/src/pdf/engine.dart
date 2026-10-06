/// The layout engines of the PDF backend.
library;

import 'package:asciidart/src/document.dart';
import 'package:asciidart/src/logging.dart';

/// How the PDF backend lays a document out.
enum PdfEngine {
  /// asciidart's own layout (the default): the same converter and themes,
  /// with typesetting asciidoctor-pdf doesn't do (see the Hypermedia
  /// Systems roadmap).
  modern,

  /// As asciidoctor-pdf 2.3.27 lays documents out: Prawn's line wrapping
  /// and the gem's page rules (`-a pdf-compat`).
  asciidoctorPdf;

  /// The engine [document] asks for: [asciidoctorPdf] when its
  /// `pdf-compat` attribute is set (empty or `asciidoctor-pdf`; another
  /// value is reported through [logger]), else [modern].
  static PdfEngine of(Document document, LoggerBase logger) {
    final compat = document.attr('pdf-compat');
    if (compat == null) return modern;
    if (compat.isNotEmpty && compat != 'asciidoctor-pdf') {
      logger.warn(
        'unknown pdf-compat value: $compat (only asciidoctor-pdf is '
        'available); using asciidoctor-pdf',
      );
    }
    return asciidoctorPdf;
  }
}
