/// Generates the npm package's projection of the public Dart API.
///
/// Reads the public libraries (`lib/ptome.dart`, `lib/io.dart`) with the
/// analyzer and writes:
///
/// - `lib/src/js/api.g.dart`: a JavaScript-exported wrapper for every
///   public class (one per Dart object, so identity holds), the
///   conversions between Dart and JavaScript values (callbacks and promises
///   included), factories for the public constructors, and adapters for the
///   classes JavaScript code implements (`Highlighter`);
/// - `npm/src/api.g.js`: the JavaScript classes (for `new`, `instanceof`
///   and documentation), the enums as frozen objects, and the top-level
///   values;
/// - `npm/types/index.d.ts`: the TypeScript declarations, with the dartdoc
///   comments as JSDoc (`tool/build-npm.sh` derives `index.d.cts`).
///
/// The projection is 1:1: the same names and shapes as the Dart API. Named
/// parameters become a trailing options object, enums become their names,
/// lists and maps become arrays and plain objects, futures become promises,
/// streams become async iterables, and `descendants<T>()` takes the class
/// as an argument (`descendants(Section)`). A type the generator does not
/// know fails the run, naming the member.
///
/// ```sh
/// dart run tool/generate_js.dart          # write the files
/// dart run tool/generate_js.dart --check  # fail if they are out of date
/// ```
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

final String repo = File.fromUri(Platform.script).parent.parent.path;

String libraryPath(String name) =>
    File.fromUri(Directory(repo).uri.resolve('lib/$name')).path;

Future<void> main(List<String> args) async {
  final check = args.contains('--check');
  final elements = await _exported(['ptome.dart', 'io.dart']);
  final model = Model(elements);
  final outputs = {
    'lib/src/js/api.g.dart': _formatted(DartEmitter(model).emit()),
    'npm/src/api.g.js': JsEmitter(model).emit(),
    'npm/types/index.d.ts': DtsEmitter(model).emit(),
  };
  var stale = false;
  for (final MapEntry(key: path, value: text) in outputs.entries) {
    final file = File('$repo/$path');
    if (check) {
      if (!file.existsSync() || file.readAsStringSync() != text) {
        stderr.writeln('generate_js: $path is out of date');
        stale = true;
      }
    } else {
      file.writeAsStringSync(text);
    }
  }
  if (check && stale) {
    stderr.writeln('run: dart run tool/generate_js.dart');
    exitCode = 1;
  } else if (!check) {
    stdout.writeln(
      'generate_js: ${model.classes.length} classes, '
      '${model.enums.length} enums, ${model.values.length} values',
    );
  }
}

/// [source] (Dart) as `dart format` writes it, formatted inside the
/// package so that its settings apply.
String _formatted(String source) {
  final dir = Directory('$repo/.dart_tool/generate_js')
    ..createSync(recursive: true);
  final file = File('${dir.path}/api.g.dart')..writeAsStringSync(source);
  final result = Process.runSync('dart', ['format', file.path]);
  if (result.exitCode != 0) {
    throw StateError('dart format failed: ${result.stderr}');
  }
  return file.readAsStringSync();
}

Future<List<Element>> _exported(List<String> libraries) async {
  final collection = AnalysisContextCollection(
    includedPaths: [for (final l in libraries) libraryPath(l)],
  );
  final result = <Element>{};
  for (final l in libraries) {
    final path = libraryPath(l);
    final session = collection.contextFor(path).currentSession;
    final resolved = await session.getResolvedLibrary(path);
    if (resolved is! ResolvedLibraryResult) {
      throw StateError('cannot resolve $path');
    }
    result.addAll(resolved.element.exportNamespace.definedNames2.values);
  }
  return result.toList()
    ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
}

/// What the generator projects.
final class Model {
  new(List<Element> elements) {
    for (final e in elements) {
      switch (e) {
        case EnumElement():
          enums.add(e);
        case ClassElement():
          classes.add(e);
        case ExtensionElement():
          extensions.add(e);
        case GetterElement():
          values.add(e);
        case TopLevelVariableElement():
          values.add(e.getter!);
        case TypeAliasElement():
          break; // function typedefs are expanded where used
        default:
          break;
      }
    }
    classes.sort(_bySuperFirst);
    names.addAll([for (final c in classes) c.name!]);
    // A sealed class without members that classes only implement is a
    // union of them: a type in TypeScript, nothing at run time.
    for (final c in [...classes]) {
      if (!c.isSealed || c.fields.any((f) => f.isPublic)) continue;
      if (c.methods.any((m) => m.isPublic)) continue;
      final members = [
        for (final k in classes)
          if (k.interfaces.any((t) => t.element == c)) k,
      ];
      if (members.isEmpty || classes.any((k) => k.supertype?.element == c)) {
        continue;
      }
      unions[c] = members;
      classes.remove(c);
    }
  }

  /// Sealed classes that are unions of the classes implementing them, with
  /// those classes.
  final Map<ClassElement, List<ClassElement>> unions = {};

  final List<ClassElement> classes = [];
  final List<EnumElement> enums = [];
  final List<ExtensionElement> extensions = [];
  final List<GetterElement> values = [];
  final Set<String> names = {};

  int _bySuperFirst(ClassElement a, ClassElement b) {
    final da = _depth(a);
    final db = _depth(b);
    return da != db ? da - db : a.name!.compareTo(b.name!);
  }

  int _depth(InterfaceElement c) {
    var d = 0;
    for (var s = c.supertype; s != null; s = s.element.supertype) {
      d++;
    }
    return d;
  }

  bool isExported(InterfaceElement e) =>
      e is EnumElement || (e is ClassElement && names.contains(e.name));

  /// The exported superclass of [c], if any.
  ClassElement? superOf(ClassElement c) {
    final s = c.supertype?.element;
    return s is ClassElement && names.contains(s.name) ? s : null;
  }

  /// Whether [c] has a public getter [name] (declared or inherited).
  bool hasGetter(ClassElement c, String name) => _sources(c, own: false).any(
    (k) => k.fields.any((f) => f.name == name && (f.getter?.isPublic ?? false)),
  );

  /// Whether [c] has a public setter [name] (declared or inherited).
  bool settable(ClassElement c, String name) => _sources(c, own: false).any(
    (k) => k.fields.any((f) => f.name == name && (f.setter?.isPublic ?? false)),
  );

  /// The classes whose JavaScript class carries members: the exported
  /// classes Dart objects are projected as (not the exceptions, nor the
  /// classes JavaScript code implements).
  bool isProjected(ClassElement c) => !isException(c) && !isImplementable(c);

  bool isException(ClassElement c) => c.allSupertypes.any(
    (t) => t.element.name == 'Exception' && t.element.library.isDartCore,
  );

  /// Abstract classes JavaScript code implements: abstract, not sealed,
  /// with a public generative constructor.
  bool isImplementable(ClassElement c) =>
      c.isAbstract &&
      !c.isSealed &&
      c.constructors.any((k) => k.isPublic && k.isGenerative);

  bool isConstructible(ClassElement c) =>
      !c.isAbstract && c.constructors.any((k) => k.isPublic);

  /// The extension methods that apply to [c] (`PtomeFiles`).
  List<MethodElement> extensionMethodsOf(ClassElement c) => [
    for (final x in extensions)
      if (x.extendedType case InterfaceType(:final element) when element == c)
        ...x.methods.where((m) => m.isPublic),
  ];

  /// The public instance properties of [c] (fields and getters), the most
  /// derived declaration of each, including inherited and mixed-in ones.
  List<FieldElement> propertiesOf(ClassElement c, {bool own = false}) {
    final seen = <String>{};
    final result = <FieldElement>[];
    for (final source in _sources(c, own: own)) {
      for (final f in source.fields) {
        if (f.isStatic || !f.isPublic || f.isEnumConstant) continue;
        if (_ignoredProperties.contains(f.name)) continue;
        if (seen.add(f.name!)) result.add(f);
      }
    }
    return result;
  }

  /// The public instance methods of [c], as [propertiesOf].
  List<MethodElement> methodsOf(ClassElement c, {bool own = false}) {
    final seen = <String>{};
    final result = <MethodElement>[];
    for (final source in _sources(c, own: own)) {
      for (final m in source.methods) {
        if (m.isStatic || !m.isPublic) continue;
        if (m.isOperator && !_projectedOperators.containsKey(m.name)) continue;
        if (_ignoredMethods.contains(m.name)) continue;
        if (seen.add(m.name!)) result.add(m);
      }
    }
    return result;
  }

  /// [c], its mixins, then (unless [own]) its superclasses and theirs, up
  /// to `Object`. With [own], exported superclasses are left out, as their
  /// members are declared there, but private ones are kept.
  Iterable<InterfaceElement> _sources(
    ClassElement c, {
    required bool own,
  }) sync* {
    for (InterfaceElement? k = c; k != null; k = k.supertype?.element) {
      if (k.library.isDartCore) break;
      if (own && k != c && isExported(k)) break;
      yield k;
      for (final m in k.mixins.reversed) {
        yield m.element;
      }
    }
  }
}

const _ignoredProperties = {'hashCode', 'runtimeType'};
const _ignoredMethods = {'noSuchMethod', 'toString', '=='};
const _projectedOperators = {'[]': 'get', '[]=': 'set'};

String _jsName(MethodElement m) => _projectedOperators[m.name] ?? m.name!;

/// The name of the core function for the member [name] of [c]: `get` and
/// `set` mark property accessors (`Section$get$title`).
String coreName(ClassElement c, String name, [String? accessor]) =>
    accessor == null ? '${c.name}\$$name' : '${c.name}\$$accessor\$$name';

/// Whether [t] is bytes: `Uint8List`, or `List<int>` (a font file's, say),
/// both a `Uint8Array` in JavaScript.
bool _isBytes(DartType t) =>
    t is InterfaceType &&
    (t.element.name == 'Uint8List' ||
        (t.isDartCoreList && t.typeArguments.single.isDartCoreInt));

bool _nullable(DartType t) =>
    t.nullabilitySuffix == NullabilitySuffix.question ||
    t is DynamicType ||
    t.isDartCoreNull;

String _docOf(Element e) => e.documentationComment ?? '';

/// Emits `lib/src/js/api.g.dart`.
final class DartEmitter {
  new(this.m);

  final Model m;
  final StringBuffer _out = StringBuffer();

  /// [t] as Dart source, with the public API's names prefixed `api.`.
  String type(DartType t) {
    final q = t.nullabilitySuffix == NullabilitySuffix.question ? '?' : '';
    if (t is VoidType) return 'void';
    if (t is DynamicType) return 'dynamic';
    if (t is TypeParameterType) return '${t.element.name}$q';
    if (t is FunctionType) {
      final params = t.formalParameters.map((p) => type(p.type)).join(', ');
      return '${type(t.returnType)} Function($params)$q';
    }
    if (t is InterfaceType) {
      final e = t.element;
      final name = m.isExported(e) ? 'api.${e.name}' : e.name!;
      final args = t.typeArguments.isEmpty
          ? ''
          : '<${t.typeArguments.map(type).join(', ')}>';
      return '$name$args$q';
    }
    throw StateError('no Dart type for $t');
  }

  /// A default value's source with the public API's names prefixed.
  String defaultCode(String code) => code.replaceAllMapped(
    RegExp(r'\b([A-Z]\w*)\b'),
    (x) => m.names.contains(x[1]) || m.enums.any((e) => e.name == x[1])
        ? 'api.${x[1]}'
        : x[1]!,
  );

  String emit() {
    _out.writeln('''
// GENERATED by tool/generate_js.dart from the public Dart API. Do not edit.
// ignore_for_file: type=lint

/// The JavaScript projection of the public API: wrappers, conversions and
/// factories (see tool/generate_js.dart).
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:ptome/ptome.dart' as api;
import 'package:ptome/io.dart' as api;
import 'package:ptome/src/js/runtime.dart' as rt;
''');
    _emitWrap();
    _emitUnwrap();
    for (final c in m.classes) {
      if (m.isImplementable(c)) _emitAdapter(c);
    }
    _emitCore();
    return _out.toString();
  }

  void _emitWrap() {
    _out
      ..writeln('/// The JavaScript object for the public Dart object [o].')
      ..writeln('JSObject wrap(Object o) => switch (o) {');
    for (final c in m.classes.reversed) {
      if (c.isAbstract || !m.isProjected(c)) continue;
      _out.writeln("  api.${c.name}() => rt.handle(o, '${c.name}'),");
    }
    for (final c in m.classes) {
      if (!m.isImplementable(c)) continue;
      _out.writeln('  _${c.name}FromJs(:final js) => js,');
    }
    _out.writeln(
      "  _ => throw ArgumentError('no JavaScript projection for '\n"
      "      '\${o.runtimeType}'),\n};\n",
    );
  }

  void _emitUnwrap() {
    for (final c in m.classes) {
      if (!m.isImplementable(c)) continue;
      _out.writeln('''
/// The Dart [${c.name}] for a JavaScript object: a projected Dart object, or
/// an object implementing it in JavaScript.
api.${c.name} unwrap${c.name}(JSAny? value) {
  return rt.tryUnwrap<api.${c.name}>(value) ??
      _${c.name}FromJs(value! as JSObject);
}
''');
    }
  }

  /// The core functions for the members [c] declares: what its JavaScript
  /// class calls, with the object as the first argument.
  void _emitMembers(ClassElement c) {
    final self = 'rt.unwrap<api.${c.name}>(self)';
    for (final f in m.propertiesOf(c, own: true)) {
      final name = f.name!;
      final where = '${c.name}.$name';
      if (m.hasGetter(c, name)) {
        _out.writeln(
          '  JSAny? ${coreName(c, name, 'get')}(JSAny? self) '
          '${_guarded(toJs(f.type, '$self.$name', where))}',
        );
      }
      if (m.settable(c, name)) {
        final assign = '$self.$name = ${fromJs(f.type, 'value', where)}';
        _out.writeln(
          '  void ${coreName(c, name, 'set')}(JSAny? self, JSAny? value) '
          '${_guarded(assign, returns: false)}',
        );
      }
    }
    for (final method in [
      ...m.methodsOf(c, own: true),
      ...m.extensionMethodsOf(c),
    ]) {
      _emitMethod(c, method, self);
    }
  }

  /// A member body evaluating [code] at the boundary with JavaScript: a
  /// failure leaves as a JavaScript error (inline rather than through a
  /// closure, which would cost a class per member in the bundle).
  static String _guarded(String code, {bool returns = true}) =>
      '{ try { ${returns ? 'return ' : ''}$code; } '
      'catch (e, s) { rt.fail(e, s); } }';

  void _emitMethod(ClassElement c, MethodElement method, String self) {
    final where = '${c.name}.${method.name}';
    final params = method.formalParameters;
    final positional = params.where((p) => p.isPositional).toList();
    final named = params.where((p) => p.isNamed).toList();
    final generic = method.typeParameters.isNotEmpty;
    final dartParams = [
      'JSAny? self',
      for (final p in positional)
        if (p.isOptionalPositional)
          '[JSAny? ${p.name}]'
        else
          'JSAny? ${p.name}',
      if (named.isNotEmpty) '[JSAny? options]',
    ];
    // Optional positionals and the options object are each in their own
    // bracket list in the loop above; merge them into one.
    final required = dartParams.where((p) => !p.startsWith('[')).toList();
    final optional = [
      for (final p in dartParams)
        if (p.startsWith('[')) p.substring(1, p.length - 1),
    ];
    final signature = [
      ...required,
      if (optional.isNotEmpty) '[${optional.join(', ')}]',
    ].join(', ');
    final args = [
      for (final p in positional)
        if (p.isOptionalPositional && p.defaultValueCode != null)
          'rt.isMissing(${p.name}) ? ${defaultCode(p.defaultValueCode!)} : '
              '${fromJs(p.type, p.name!, where)}'
        else
          fromJs(p.type, p.name!, where),
      for (final p in named) '${p.name}: ${_namedArg(p, where)}',
    ];
    // A generic method (`descendants<T>()`) returns every match of the
    // bound; the JavaScript class filters by the class it is given.
    final typeArgs = generic
        ? '<${type(method.typeParameters.single.bound!)}>'
        : '';
    final call = switch (method.name) {
      '[]' => '$self[${args.single}]',
      '[]=' => '($self[${args[0]}] = ${args[1]})',
      _ => '$self.${method.name}$typeArgs(${args.join(', ')})',
    };
    final result = generic
        ? 'rt.jsArray([for (final x in $call) wrap(x)])'
        : toJs(method.returnType, call, where);
    _out.writeln(
      '  JSAny? ${coreName(c, _jsName(method))}($signature) '
      '${_guarded(result)}',
    );
  }

  String _namedArg(FormalParameterElement p, String where) {
    final read = "rt.option(options, '${p.name}')";
    final value = fromJs(p.type, read, where);
    final fallback = p.defaultValueCode == null
        ? (p.isRequiredNamed ? null : 'null')
        : defaultCode(p.defaultValueCode!);
    if (fallback == null) return value;
    return "rt.hasOption(options, '${p.name}') ? $value : $fallback";
  }

  void _emitAdapter(ClassElement c) {
    _out
      ..writeln('final class _${c.name}FromJs extends api.${c.name} {')
      ..writeln('  _${c.name}FromJs(this.js);')
      ..writeln('  final JSObject js;');
    for (final f in m.propertiesOf(c, own: true)) {
      final where = '${c.name}.${f.name}';
      _out
        ..writeln('  @override')
        ..writeln(
          "  ${type(f.type)} get ${f.name} => js.has('${f.name}') "
          '? ${fromJs(f.type, "js['${f.name}']", where)} : super.${f.name};',
        );
    }
    for (final method in m.methodsOf(c, own: true)) {
      final where = '${c.name}.${method.name}';
      final params = method.formalParameters;
      final decl = params.map((p) => '${type(p.type)} ${p.name}').join(', ');
      final jsArgs = params.map((p) => toJs(p.type, p.name!, where)).join(', ');
      final call = "rt.invokeMethod(js, '${method.name}', [$jsArgs])";
      _out
        ..writeln('  @override')
        ..writeln(
          '  ${type(method.returnType)} ${method.name}($decl) => '
          '${fromJs(method.returnType, call, where)};',
        );
    }
    _out.writeln('}\n');
  }

  void _emitCore() {
    _out
      ..writeln('/// The object the npm package calls into.')
      ..writeln('@JSExport()')
      ..writeln('final class Core {')
      ..writeln(
        '  JSAny? describe(JSAny? self) '
        "${_guarded('rt.unwrap<Object>(self).toString().toJS')}",
      );
    for (final c in m.classes) {
      if (m.isProjected(c)) _emitMembers(c);
    }
    for (final g in m.values) {
      _out.writeln(
        '  JSAny? get ${g.name} '
        '${_guarded(toJs(g.returnType, 'api.${g.name}', g.name!))}',
      );
    }
    for (final c in m.classes) {
      if (!m.isConstructible(c) || m.isException(c)) continue;
      for (final k in c.constructors.where((k) => k.isPublic)) {
        final where = '${c.name}()';
        final params = k.formalParameters;
        final positional = params.where((p) => p.isPositional).toList();
        final named = params.where((p) => p.isNamed).toList();
        final sig = [
          ...positional.map((p) => 'JSAny? ${p.name}'),
          if (named.isNotEmpty) '[JSAny? options]',
        ];
        final req = sig.where((s) => !s.startsWith('['));
        final opt = sig
            .where((s) => s.startsWith('['))
            .map((s) => s.substring(1, s.length - 1));
        final signature = [
          ...req,
          if (opt.isNotEmpty) '[${opt.join(', ')}]',
        ].join(', ');
        final args = [
          for (final p in positional) fromJs(p.type, p.name!, where),
          for (final p in named) '${p.name}: ${_namedArg(p, where)}',
        ];
        final ctor = k.name == 'new' || k.name == null || k.name!.isEmpty
            ? c.name!
            : '${c.name}.${k.name}';
        final jsName = ctor.replaceAll('.', r'$');
        _out.writeln(
          "  @JSExport('$jsName')\n  JSAny? new\$$jsName($signature) "
          '${_guarded('wrap(api.$ctor(${args.join(', ')}))')}',
        );
      }
    }
    _out.writeln('}');
  }

  /// The expression converting the Dart value [expr] of type [t] to
  /// JavaScript.
  String toJs(DartType t, String expr, String where) {
    final nullable = _nullable(t);
    String guard(String nonNull) => nullable
        ? '(($expr) == null ? null : ${nonNull.replaceAll('#', '($expr)!')})'
        : nonNull.replaceAll('#', expr);
    if (t is VoidType) return '(() { $expr; return null; })()';
    if (t.isDartCoreString) return guard('#.toJS');
    if (t.isDartCoreInt || t.isDartCoreDouble || t.isDartCoreNum) {
      return guard('#.toJS');
    }
    if (t.isDartCoreBool) return guard('#.toJS');
    if (_isBytes(t)) return guard('rt.jsBytes(#)');
    if (t is InterfaceType) {
      final e = t.element;
      if (e is EnumElement) return guard('#.name.toJS');
      if (m.isExported(e)) return guard('wrap(#)');
      if (t.isDartCoreList || t.isDartCoreIterable || t.isDartCoreSet) {
        final a = t.typeArguments.single;
        return guard('rt.jsArray([for (final x in #) ${toJs(a, 'x', where)}])');
      }
      if (t.isDartCoreMap) {
        final v = t.typeArguments[1];
        final value = toJs(v, 'e.value', where);
        return guard('rt.jsObject({for (final e in #.entries) e.key: $value})');
      }
      if (t.isDartAsyncFuture) {
        final a = t.typeArguments.single;
        return guard('rt.promise(#, (x) => ${toJs(a, 'x', where)})');
      }
      if (t.isDartAsyncStream) {
        final a = t.typeArguments.single;
        return guard('rt.asyncIterable(#, (x) => ${toJs(a, 'x', where)})');
      }
      if (t.isDartAsyncFutureOr) {
        final a = t.typeArguments.single;
        return 'rt.jsFutureOr($expr, (x) => ${toJs(a, 'x', where)})';
      }
    }
    if (t is FunctionType) {
      final params = t.formalParameters;
      final names = [for (var i = 0; i < params.length; i++) 'a$i'];
      final conv = [
        for (var i = 0; i < params.length; i++)
          fromJs(params[i].type, names[i], where),
      ];
      final plain = type(t).replaceFirst(RegExp(r'\?$'), '');
      final f =
          '(${names.map((n) => 'JSAny? $n').join(', ')}) => '
          '${toJs(t.returnType, '_f(${conv.join(', ')})', where)}';
      final wrapped = '(($plain _f) => ($f).toJS)';
      return nullable
          ? '(($expr) == null ? null : $wrapped(($expr)!))'
          : '$wrapped($expr)';
    }
    throw StateError('$where: no JavaScript projection for $t');
  }

  /// The expression converting the JavaScript value [expr] to the Dart type
  /// [t].
  String fromJs(DartType t, String expr, String where) {
    final nullable = _nullable(t);
    String guard(String nonNull) =>
        nullable ? '(rt.isMissing($expr) ? null : $nonNull)' : nonNull;
    if (t.isDartCoreString) return guard('rt.str($expr)');
    if (t.isDartCoreInt) return guard('rt.integer($expr)');
    if (t.isDartCoreDouble || t.isDartCoreNum) return guard('rt.number($expr)');
    if (t.isDartCoreBool) return guard('rt.boolean($expr)');
    if (_isBytes(t)) return guard('rt.bytes($expr)');
    if (t is InterfaceType) {
      final e = t.element;
      if (e is EnumElement) {
        return guard('api.${e.name}.values.byName(rt.str($expr))');
      }
      if (e is ClassElement && m.isImplementable(e)) {
        return guard('unwrap${e.name}($expr)');
      }
      if (m.isExported(e)) return guard('rt.unwrap<api.${e.name}>($expr)');
      if (t.isDartCoreList || t.isDartCoreIterable) {
        final a = t.typeArguments.single;
        return guard(
          '[for (final x in rt.list($expr)) ${fromJs(a, 'x', where)}]',
        );
      }
      if (t.isDartCoreSet) {
        final a = t.typeArguments.single;
        return guard(
          '{for (final x in rt.list($expr)) ${fromJs(a, 'x', where)}}',
        );
      }
      if (t.isDartCoreMap) {
        final v = t.typeArguments[1];
        final value = fromJs(v, 'e.value', where);
        return guard('{for (final e in rt.entries($expr)) e.key: $value}');
      }
      if (t.isDartAsyncFutureOr) {
        final a = t.typeArguments.single;
        return guard('rt.futureOr($expr, (x) => ${fromJs(a, 'x', where)})');
      }
    }
    if (t is FunctionType) {
      final params = t.formalParameters;
      final decl = [
        for (var i = 0; i < params.length; i++) '${type(params[i].type)} a$i',
      ];
      final args = [
        for (var i = 0; i < params.length; i++)
          toJs(params[i].type, 'a$i', where),
      ];
      final call = 'rt.invoke(f, [${args.join(', ')}])';
      final closure = t.returnType is VoidType
          ? '(${decl.join(', ')}) { $call; }'
          : '(${decl.join(', ')}) => ${fromJs(t.returnType, call, where)}';
      return guard('((JSFunction f) => $closure)(rt.fn($expr))');
    }
    throw StateError('$where: no Dart conversion for $t');
  }
}

/// Emits `npm/src/api.g.js`.
final class JsEmitter {
  new(this.m);

  final Model m;

  String emit() {
    final out = StringBuffer('''
// GENERATED by tool/generate_js.dart from the public Dart API. Do not edit.
// The JavaScript projection of ptome: the same names and shapes as the
// Dart API (see npm/README.md and tool/generate_js.dart).

import { core, errorClasses, filterByClass, registerClasses } from './core.js'

''');
    for (final c in m.classes) {
      final ext = m.superOf(c);
      final extendsClause = m.isException(c)
          ? ' extends Error'
          : ext == null
          ? ''
          : ' extends ${ext.name}';
      out.writeln('export class ${c.name}$extendsClause {');
      if (m.isException(c)) {
        out
          ..writeln('  constructor(message) {')
          ..writeln('    super(message)')
          ..writeln("    this.name = '${c.name}'")
          ..writeln('  }');
      } else if (m.isImplementable(c)) {
        // Implemented by JavaScript classes: a plain base class.
      } else {
        if (m.isConstructible(c)) {
          out
            ..writeln('  constructor(...args) {')
            ..writeln('    return core.${c.name}(...args)')
            ..writeln('  }');
        } else {
          out
            ..writeln('  constructor() {')
            ..writeln(
              "    throw new TypeError('${c.name} objects come from ptome; "
              "they cannot be created with new')",
            )
            ..writeln('  }');
        }
        _members(out, c);
      }
      out.writeln('}\n');
    }
    final concrete = [
      for (final c in m.classes)
        if (!c.isAbstract && m.isProjected(c)) c.name,
    ];
    out.writeln('registerClasses({ ${concrete.join(', ')} })\n');
    for (final e in m.enums) {
      final values = e.constants
          .map((v) => "  ${v.name}: '${v.name}',")
          .join('\n');
      out.writeln('export const ${e.name} = Object.freeze({\n$values\n})\n');
    }
    for (final g in m.values) {
      out.writeln('export const ${g.name} = core.${g.name}');
    }
    for (final c in m.classes.where(m.isException)) {
      out.writeln('errorClasses.${c.name} = ${c.name}');
    }
    return out.toString();
  }

  /// The members [c] declares, each calling its core function.
  void _members(StringBuffer out, ClassElement c) {
    if (m.superOf(c) == null) {
      out
        ..writeln('  toString() {')
        ..writeln('    return core.describe(this)')
        ..writeln('  }');
    }
    for (final f in m.propertiesOf(c, own: true)) {
      final name = f.name!;
      if (m.hasGetter(c, name)) {
        out
          ..writeln('  get $name() {')
          ..writeln('    return core.${coreName(c, name, 'get')}(this)')
          ..writeln('  }');
      }
      if (m.settable(c, name)) {
        out
          ..writeln('  set $name(value) {')
          ..writeln('    core.${coreName(c, name, 'set')}(this, value)')
          ..writeln('  }');
      }
    }
    for (final method in [
      ...m.methodsOf(c, own: true),
      ...m.extensionMethodsOf(c),
    ]) {
      final name = _jsName(method);
      if (method.typeParameters.isNotEmpty) {
        out
          ..writeln('  $name(type) {')
          ..writeln(
            '    return filterByClass(core.${coreName(c, name)}(this), type)',
          )
          ..writeln('  }');
      } else {
        out
          ..writeln('  $name(...args) {')
          ..writeln('    return core.${coreName(c, name)}(this, ...args)')
          ..writeln('  }');
      }
    }
  }
}

/// Emits `npm/types/index.d.ts`.
final class DtsEmitter {
  new(this.m);

  final Model m;

  String emit() {
    final out = StringBuffer('''
// GENERATED by tool/generate_js.dart from the public Dart API. Do not edit.
// Types of Ptome for JavaScript: the same names and shapes as the Dart
// API.

''');
    for (final e in m.enums) {
      out
        ..write(_jsdoc(_docOf(e), ''))
        ..writeln(
          'export type ${e.name} = '
          '${e.constants.map((v) => "'${v.name}'").join(' | ')};',
        )
        ..writeln('export declare const ${e.name}: {')
        ..writeAll([
          for (final v in e.constants)
            "${_jsdoc(_docOf(v), '  ')}  readonly ${v.name}: '${v.name}';\n",
        ])
        ..writeln('};\n');
    }
    for (final MapEntry(key: c, value: members) in m.unions.entries) {
      out
        ..write(_jsdoc(_docOf(c), ''))
        ..writeln(
          'export type ${c.name} = '
          '${members.map((k) => k.name).join(' | ')};\n',
        );
    }
    for (final c in m.classes) {
      final sup = m.superOf(c);
      final ext = m.isException(c)
          ? ' extends Error'
          : sup == null
          ? ''
          : ' extends ${sup.name}';
      final abstract = c.isAbstract ? 'abstract ' : '';
      out
        ..write(_jsdoc(_docOf(c), ''))
        ..writeln('export declare ${abstract}class ${c.name}$ext {');
      if (m.isException(c)) {
        out.writeln('  constructor(message: string);');
      } else if (m.isImplementable(c)) {
        out.writeln('  constructor();');
      } else if (m.isConstructible(c)) {
        for (final k in c.constructors.where((k) => k.isPublic)) {
          out
            ..write(_jsdoc(_docOf(k), '  '))
            ..writeln('  constructor(${_params(k.formalParameters)});');
        }
      } else {
        out.writeln('  protected constructor();');
      }
      final implementable = m.isImplementable(c);
      for (final f in m.propertiesOf(c, own: true)) {
        if (m.isException(c) && f.name == 'message') {
          out.writeln('  readonly message: string;');
          continue;
        }
        final readonly = m.settable(c, f.name!) ? '' : 'readonly ';
        out
          ..write(_jsdoc(_docOf(f.getter ?? f), '  '))
          ..writeln(
            implementable
                ? '  ${f.name}?: ${_ts(f.type)};'
                : '  $readonly${f.name}: ${_ts(f.type)};',
          );
      }
      for (final method in [
        ...m.methodsOf(c, own: true),
        ...m.extensionMethodsOf(c),
      ]) {
        final generic = method.typeParameters.isNotEmpty;
        final params = generic
            ? 'type?: { prototype: T }'
            : _params(method.formalParameters);
        final ret = generic ? 'T[]' : _ts(method.returnType);
        final bound = generic ? method.typeParameters.single.bound : null;
        final typeParams = generic ? '<T extends $bound = $bound>' : '';
        final abstract = implementable && method.isAbstract ? 'abstract ' : '';
        out
          ..write(_jsdoc(_docOf(method), '  '))
          ..writeln('  $abstract${_jsName(method)}$typeParams($params): $ret;');
      }
      out.writeln('}\n');
    }
    for (final g in m.values) {
      out
        ..write(_jsdoc(_docOf(g.variable), ''))
        ..writeln('export declare const ${g.name}: ${_ts(g.returnType)};');
    }
    return out.toString();
  }

  String _params(List<FormalParameterElement> params) {
    final positional = params.where((p) => p.isPositional);
    final named = params.where((p) => p.isNamed).toList();
    final optional = named.any((p) => p.isRequiredNamed) ? '' : '?';
    final options = '{ ${named.map(_option).join('; ')} }';
    return [
      for (final p in positional)
        '${p.name}${p.isOptionalPositional ? '?' : ''}: ${_ts(p.type)}',
      if (named.isNotEmpty) 'options$optional: $options',
    ].join(', ');
  }

  String _option(FormalParameterElement p) =>
      '${p.name}${p.isRequiredNamed ? '' : '?'}: ${_ts(p.type)}';

  String _ts(DartType t) {
    final base = _tsBase(t);
    if (!_nullable(t) || t is VoidType) return base;
    return t is FunctionType ? '($base) | null' : '$base | null';
  }

  String _tsBase(DartType t) {
    if (t is VoidType) return 'void';
    if (t.isDartCoreString) return 'string';
    if (t.isDartCoreInt || t.isDartCoreDouble || t.isDartCoreNum) {
      return 'number';
    }
    if (t.isDartCoreBool) return 'boolean';
    if (_isBytes(t)) return 'Uint8Array';
    if (t is TypeParameterType) return t.element.name!;
    if (t is InterfaceType) {
      final e = t.element;
      if (e is EnumElement || m.isExported(e)) return e.name!;
      if (t.isDartCoreList || t.isDartCoreIterable || t.isDartCoreSet) {
        final a = _ts(t.typeArguments.single);
        return a.contains('|') || a.contains('=>') ? 'Array<$a>' : '$a[]';
      }
      if (t.isDartCoreMap) {
        return 'Record<string, ${_ts(t.typeArguments[1])}>';
      }
      if (t.isDartAsyncFuture) return 'Promise<${_ts(t.typeArguments.single)}>';
      if (t.isDartAsyncFutureOr) {
        final a = _ts(t.typeArguments.single);
        return '$a | Promise<$a>';
      }
      if (t.isDartAsyncStream) {
        return 'AsyncIterable<${_ts(t.typeArguments.single)}>';
      }
    }
    if (t is FunctionType) {
      final params = [
        for (final p in t.formalParameters)
          '${(p.name ?? '').isEmpty ? 'arg' : p.name}: ${_ts(p.type)}',
      ];
      // Unnamed function type parameters get positional names.
      var i = 0;
      final named = params.map(
        (p) => p.startsWith('arg:') ? 'arg${i++}${p.substring(3)}' : p,
      );
      return '(${named.join(', ')}) => ${_ts(t.returnType)}';
    }
    throw StateError('no TypeScript type for $t');
  }

  /// [doc] (a dartdoc comment) as a JSDoc comment indented by [indent].
  String _jsdoc(String doc, String indent) {
    if (doc.isEmpty) return '';
    final lines = [
      for (final line in doc.split('\n'))
        line.replaceFirst(RegExp(r'^\s*/// ?'), ''),
    ];
    final text = lines
        .join('\n')
        .replaceAllMapped(
          RegExp(r'\[([A-Za-z_][\w.]*)\]'),
          (x) => '{@link ${x[1]}}',
        )
        .replaceAll('*/', r'*\/');
    return '$indent/**\n${text.split('\n').map((l) => '$indent *${l.isEmpty ? '' : ' $l'}').join('\n')}\n$indent */\n';
  }
}
