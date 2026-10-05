/// The supported API of asciidart (see `doc/api.md`).
///
/// Everything public in this library is exported by
/// `package:asciidart/asciidart.dart`; the rest of `lib/src` stays private.
/// The types here are a typed layer over the implementation: nodes are
/// views of the implementation's nodes, extensions and output overrides
/// adapt to its registry and converters, and diagnostics are collected per
/// document instead of going to a global logger.
library;

import 'dart:async';

import 'package:asciidart/src/abstract_block.dart' as impl;
import 'package:asciidart/src/abstract_node.dart' as impl;
import 'package:asciidart/src/block.dart' as impl;
import 'package:asciidart/src/converter.dart' as impl;
import 'package:asciidart/src/document.dart' as impl;
import 'package:asciidart/src/errors.dart' as impl;
import 'package:asciidart/src/extensions.dart' as impl;
import 'package:asciidart/src/highlight/highlight.dart' as impl;
import 'package:asciidart/src/highlight/syntax_highlighter.dart' as impl;
import 'package:asciidart/src/html5.dart' as impl;
import 'package:asciidart/src/inline.dart' as impl;
import 'package:asciidart/src/inline_tree.dart' as impl;
import 'package:asciidart/src/io.dart' as impl;
import 'package:asciidart/src/list.dart' as impl;
import 'package:asciidart/src/load.dart' as impl;
import 'package:asciidart/src/logging.dart' as impl;
import 'package:asciidart/src/options.dart' as impl;
import 'package:asciidart/src/reader.dart' as impl;
import 'package:asciidart/src/section.dart' as impl;
import 'package:asciidart/src/table.dart' as impl;
import 'package:asciidart/src/version.dart' as impl;
import 'package:meta/meta.dart';

part 'asciidart.dart';
part 'attributes.dart';
part 'diagnostics.dart';
part 'extensions.dart';
part 'files.dart';
part 'highlighter.dart';
part 'inlines.dart';
part 'nodes.dart';
part 'render.dart';
