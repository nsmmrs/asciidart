/// TEMP-SHIM (html5): minimal substitutor surface for the html5 port.
///
/// This file is owned by branch `port/html5` and will be DELETED on merge:
/// the sibling `port/substitutors` branch ports the real
/// `lib/asciidoctor/substitutors.rb` (including `sub_macros`). The merger
/// deletes this file on conflict and rewires call sites to the real file.
///
/// It contains ONLY the substitutor signatures `html5.dart` calls that do
/// not already exist on [AbstractNode] (which already declares
/// `applySubs`, `applyTitleSubs`, `applyReftextSubs`, `subSpecialchars`,
/// `subReplacements`, `subQuotes`, `subPlaceholder` and `commitSubs` as
/// `UnimplementedError` stubs awaiting the substitutors wave). Each body
/// throws `UnimplementedError` with the `TEMP-SHIM` marker.
///
/// Signature derived mechanically from Ruby (`snake_case` -> `camelCase`,
/// same parameters): `Substitutors#sub_macros(text)`.
library;

import 'abstract_node.dart';

/// TEMP-SHIM extension: `Substitutors#sub_macros` (see library docs).
extension TempSubstitutorsShim on AbstractNode {
  /// Applies macro substitutions (e.g. email, url) to [text].
  ///
  /// TEMP-SHIM: throws until replaced by the `port/substitutors` merge.
  String subMacros(String text) => throw UnimplementedError(
    'TEMP-SHIM: replaced by port/substitutors merge',
  );
}
