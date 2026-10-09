/// The supported API of Ptome (see `doc/api.md`).
///
/// Everything public in this library is exported by
/// `package:ptome/ptome.dart`; the rest of `lib/src` stays private.
/// The types here are a typed layer over the implementation: nodes are
/// views of the implementation's nodes, extensions and output overrides
/// adapt to its registry and converters, and diagnostics are collected per
/// document instead of going to a global logger.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:ptome/src/abstract_block.dart' as impl;
import 'package:ptome/src/abstract_node.dart' as impl;
import 'package:ptome/src/api/file_backends.dart'
    if (dart.library.js_interop) 'package:ptome/src/api/file_backends_js.dart'
    as file_backends;
import 'package:ptome/src/block.dart' as impl;
import 'package:ptome/src/converter.dart' as impl;
import 'package:ptome/src/document.dart' as impl;
import 'package:ptome/src/errors.dart' as impl;
import 'package:ptome/src/extensions.dart' as impl;
import 'package:ptome/src/font_index.dart' as impl;
import 'package:ptome/src/header_edit.dart' as impl;
import 'package:ptome/src/highlight/highlight.dart' as impl;
import 'package:ptome/src/highlight/syntax_highlighter.dart' as impl;
import 'package:ptome/src/html5.dart' as impl;
import 'package:ptome/src/index_catalog.dart' as impl;
import 'package:ptome/src/inline.dart' as impl;
import 'package:ptome/src/inline_tree.dart' as impl;
import 'package:ptome/src/io.dart' as impl;
import 'package:ptome/src/list.dart' as impl;
import 'package:ptome/src/load.dart' as impl;
import 'package:ptome/src/logging.dart' as impl;
import 'package:ptome/src/options.dart' as impl;
import 'package:ptome/src/parallel.dart' as impl;
import 'package:ptome/src/reader.dart' as impl;
import 'package:ptome/src/section.dart' as impl;
import 'package:ptome/src/table.dart' as impl;
import 'package:ptome/src/units/citation.dart' as impl;
import 'package:ptome/src/units/document.dart' as impl show Loc;
import 'package:ptome/src/units/engine.dart' as impl;
import 'package:ptome/src/version.dart' as impl;

part 'attributes.dart';
part 'diagnostics.dart';
part 'extensions.dart';
part 'files.dart';
part 'highlighter.dart';
part 'inlines.dart';
part 'nodes.dart';
part 'ptome.dart';
part 'render.dart';
part 'units.dart';
