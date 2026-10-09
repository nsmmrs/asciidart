/// The box tree and pagination: blocks, paragraphs, images, spacers,
/// drawings, breaks and column sets flow into the regions of pages made
/// from templates, splitting where they must. Keep rules, orphans and
/// widows are decided by a `PageBreaker` strategy. Running headers and
/// footers see the page number, the page count and running marks; page
/// references are resolved by laying out again until nothing moves.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:plain_typesetting/src/canvas.dart';
import 'package:plain_typesetting/src/color.dart';
import 'package:plain_typesetting/src/geometry.dart';
import 'package:plain_typesetting/src/graphic.dart';
import 'package:plain_typesetting/src/layout/inline.dart';
import 'package:plain_typesetting/src/layout/paragraph.dart';
import 'package:plain_typesetting/src/page.dart';

part 'flow/boxes.dart';
part 'flow/pagination.dart';
part 'flow/pass.dart';
part 'flow/notes.dart';
part 'flow/floats.dart';
part 'flow/leaves.dart';
part 'flow/tables.dart';
part 'flow/columns.dart';
part 'flow/placed.dart';
part 'flow/result.dart';
