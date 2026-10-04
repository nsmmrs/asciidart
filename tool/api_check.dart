/// Checks that the public API is closed: every `package:asciidoctor` type
/// that appears in an exported signature (supertypes, constructor and
/// method parameters, return types, fields, typedefs) is itself exported by
/// one of the public libraries. Exits nonzero and lists the offenders
/// otherwise.
///
/// ```sh
/// dart run tool/api_check.dart
/// ```
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

// Resolved relative to this file: tool/ -> repository root.
final String repo = File.fromUri(Platform.script).parent.parent.path;
const publicLibs = [
  'asciidoctor.dart',
  'extensions.dart',
  'converter.dart',
  'syntax_highlighter.dart',
  'cli.dart',
];

Future<void> main() async {
  final collection = AnalysisContextCollection(
    includedPaths: [for (final l in publicLibs) '$repo/lib/$l'],
  );
  final exported = <Element>{};
  for (final l in publicLibs) {
    final path = '$repo/lib/$l';
    final session = collection.contextFor(path).currentSession;
    final result = await session.getResolvedLibrary(path);
    if (result is! ResolvedLibraryResult) {
      stderr.writeln('cannot resolve $path');
      exit(2);
    }
    exported.addAll(result.element.exportNamespace.definedNames2.values);
  }
  final missing = <String, Set<String>>{};
  void checkElement(Element e, String where) {
    final uri = e.library?.uri.toString() ?? '';
    if (!uri.startsWith('package:asciidoctor/')) return;
    if (e.name == null || e.name!.startsWith('_')) return;
    if (exported.contains(e)) return;
    missing
        .putIfAbsent('${e.name} (${uri.split('/').last})', () => {})
        .add(where);
  }

  void checkType(DartType? type, String where) {
    if (type == null) return;
    final alias = type.alias;
    if (alias != null) {
      checkElement(alias.element, where);
      for (final a in alias.typeArguments) {
        checkType(a, where);
      }
    }
    if (type is InterfaceType) {
      checkElement(type.element, where);
      for (final a in type.typeArguments) {
        checkType(a, where);
      }
    } else if (type is FunctionType) {
      checkType(type.returnType, where);
      for (final p in type.formalParameters) {
        checkType(p.type, where);
      }
    }
  }

  for (final e in exported) {
    final name = e.name ?? '?';
    if (e is InterfaceElement) {
      checkType(e.supertype, '$name extends');
      for (final m in e.mixins) {
        checkType(m, '$name with');
      }
      for (final i in e.interfaces) {
        checkType(i, '$name implements');
      }
      for (final c in e.constructors) {
        if (c.isPrivate) continue;
        for (final p in c.formalParameters) {
          checkType(p.type, '$name.${c.name}(${p.name})');
        }
      }
      for (final f in e.fields) {
        if (f.isPrivate) continue;
        checkType(f.type, '$name.${f.name}');
      }
      for (final m in e.methods) {
        if (m.isPrivate) continue;
        checkType(m.returnType, '$name.${m.name}()');
        for (final p in m.formalParameters) {
          checkType(p.type, '$name.${m.name}(${p.name})');
        }
      }
    } else if (e is TopLevelFunctionElement) {
      checkType(e.returnType, '$name()');
      for (final p in e.formalParameters) {
        checkType(p.type, '$name(${p.name})');
      }
    } else if (e is TypeAliasElement) {
      checkType(e.aliasedType, 'typedef $name');
    } else if (e is TopLevelVariableElement) {
      checkType(e.type, name);
    }
  }
  final keys = missing.keys.toList()..sort();
  for (final k in keys) {
    final w = missing[k]!.toList()..sort();
    final more = w.length > 4 ? ' (+${w.length - 4})' : '';
    stdout.writeln('$k  <- ${w.take(4).join('; ')}$more');
  }
  stdout.writeln('${keys.length} unexported types referenced');
  if (keys.isNotEmpty) exitCode = 1;
}
