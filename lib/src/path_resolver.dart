/// Handles all operations for resolving, cleaning and joining paths.
///
/// Dart port of `lib/asciidoctor/path_resolver.rb`. This class includes
/// operations for handling both web paths (request URIs) and system paths.
///
/// The main emphasis of the class is on creating clean and secure paths. Clean
/// paths are void of duplicate parent and current directory references in the
/// path name. Secure paths are paths which are restricted from accessing
/// directories outside of a jail path, if specified.
///
/// Since joining two paths can result in an insecure path, this class also
/// handles the task of joining a parent (start) and child (target) path.
///
/// This class makes no use of path utilities from the Dart libraries. Instead,
/// it handles all aspects of path manipulation. The main benefit of
/// internalizing these operations is that the class is able to handle both
/// posix and windows paths independent of the operating system on which it
/// runs. This makes the class both deterministic and easier to test.
///
/// Methods correspond to Asciidoctor's (`webPath` is `web_path`,
/// `systemPath` is `system_path`, ...).
library;

import 'dart:io';

/// Error raised when a path breaches the jail and recovery is disabled.
///
/// Thrown by [PathResolver.systemPath].
class SecurityError extends Error {
  /// Creates a security error with the given [message].
  new(this.message);

  /// Human-readable description of the security violation.
  final String message;

  @override
  String toString() => 'SecurityError: $message';
}

/// Handles all operations for resolving, cleaning and joining paths.
///
/// See the library documentation for an overview.
class PathResolver {
  /// Constructs a new instance of [PathResolver], optionally specifying the
  /// [fileSeparator] (to override the system default) and the [workingDir]
  /// (to override the current working directory). The working directory is
  /// expanded to an absolute path inside the constructor.
  new({
    String? fileSeparator,
    String? workingDir,
    void Function(String message)? onWarn,
  }) : fileSeparator = fileSeparator ?? Platform.pathSeparator,
       onWarn = onWarn ?? _defaultWarn,
       workingDir = _resolveWorkingDir(
         workingDir,
         fileSeparator ?? Platform.pathSeparator,
       );

  /// Self (current directory) path segment.
  static const String dot = '.';

  /// Parent directory path segment.
  static const String dotDot = '..';

  /// Current directory root prefix for relative paths (`./`).
  static const String dotSlash = './';

  /// Posix path separator.
  static const String slash = '/';

  /// Windows path separator.
  static const String backslash = r'\';

  /// UNC path root prefix (`//`).
  static const String doubleSlash = '//';

  /// URI prefix of Java classloader paths.
  ///
  /// [isRoot] does not treat such URIs as roots, so this prefix only takes
  /// effect if a subclass ever does.
  static const String uriClassloader = 'uri:classloader:';

  /// Matches a Windows root: an optional drive letter followed by a separator.
  static final RegExp windowsRootRx = RegExp(r'^(?:[a-zA-Z]:)?[\\/]');

  /// Sniffs a URI scheme prefix (e.g. `http://`, `file:///`, `data:`).
  ///
  /// Deliberately does not match a Windows drive prefix such as
  /// `c:/sample.adoc`. URI schemes are ASCII by definition (RFC 3986), so
  /// only ASCII letters and digits are matched.
  static final RegExp _uriSniffRx = RegExp(r'^[A-Za-z][A-Za-z0-9.+\-]+:/{0,2}');

  /// The file separator to use for path operations.
  ///
  /// Defaults to the platform separator. Set to [backslash] to resolve
  /// Windows paths on any platform.
  String fileSeparator;

  /// The working directory used to resolve relative paths.
  String workingDir;

  /// Receives recoverable-path warning messages.
  ///
  /// A per-instance callback keeps path resolution decoupled from the
  /// global logger. Defaults to writing
  /// `asciidoctor: WARNING: <message>` lines to stderr.
  void Function(String message) onWarn;

  final Map<String, ({List<String> segments, String? root})> _partitionPathSys =
      {};
  final Map<String, ({List<String> segments, String? root})> _partitionPathWeb =
      {};

  static void _defaultWarn(String message) {
    stderr.writeln('asciidoctor: WARNING: $message');
  }

  static String _resolveWorkingDir(String? workingDir, String fileSeparator) {
    if (workingDir == null) {
      return Directory.current.path;
    } else if (_isRoot(workingDir, fileSeparator)) {
      return _posixify(workingDir, fileSeparator);
    } else {
      return _expandPath(
        '${Directory.current.path}/$workingDir',
        fileSeparator,
      );
    }
  }

  /// Checks whether the specified path is an absolute path.
  ///
  /// This operation considers both posix paths and Windows paths. The path
  /// does not have to be posixified beforehand. This operation does not handle
  /// URIs.
  ///
  /// Unix absolute paths start with a slash. UNC paths can start with a slash
  /// or backslash. Windows roots can start with a drive letter.
  bool isAbsolutePath(String path) => _isAbsolutePath(path, fileSeparator);

  static bool _isAbsolutePath(String path, String fileSeparator) =>
      path.startsWith(slash) ||
      (fileSeparator == backslash && windowsRootRx.hasMatch(path));

  static bool _isRoot(String path, String fileSeparator) =>
      _isAbsolutePath(path, fileSeparator);

  /// Checks if the specified path is an absolute root path.
  ///
  /// Same as [isAbsolutePath].
  bool isRoot(String path) => isAbsolutePath(path);

  /// Determines if the path is a UNC (root) path.
  bool isUnc(String path) => path.startsWith(doubleSlash);

  /// Determines if the path is an absolute (root) web path.
  bool isWebRoot(String path) => path.startsWith(slash);

  /// Determines whether [path] descends from [base].
  ///
  /// If [path] equals [base], or [base] is a parent of [path], returns the
  /// offset (the number of characters to skip to get the relative portion).
  /// Otherwise returns `null`. Callers must null-check, not zero-check: `0`
  /// means [path] equals [base].
  int? descendsFrom(String path, String base) {
    if (base == path) {
      return 0;
    } else if (base == slash) {
      return path.startsWith(slash) ? 1 : null;
    } else {
      return path.startsWith('$base$slash') ? base.length + 1 : null;
    }
  }

  /// Calculates the relative path to the absolute [path] from the specified
  /// base directory [base].
  ///
  /// If [path] is not an absolute path, the path is not contained within the
  /// base directory and the relative path cannot be computed, the original
  /// path is returned.
  String relativePath(String path, String base) {
    if (isRoot(path)) {
      final offset = descendsFrom(path, base);
      if (offset != null) {
        return path.substring(offset);
      } else {
        return _relativePathFrom(path, base) ?? path;
      }
    } else {
      return path;
    }
  }

  /// Computes the relative path from [base] to [path], or `null` when they
  /// have no common root (then [relativePath] falls back to the original
  /// path).
  ///
  /// When the roots differ (e.g. `D:/...` vs `C:/...`) the result is always
  /// `null`, on every platform; Asciidoctor answers this platform-dependently
  /// and its tests assert this Windows behavior.
  String? _relativePathFrom(String path, String base) {
    final pathSegments = _splitPath(path);
    final baseSegments = _splitPath(base);
    var common = 0;
    while (common < pathSegments.length &&
        common < baseSegments.length &&
        pathSegments[common] == baseSegments[common]) {
      common++;
    }
    if (common == 0) {
      return null;
    }
    return [
      ...List.filled(baseSegments.length - common, dotDot),
      ...pathSegments.sublist(common),
    ].join(slash);
  }

  static List<String> _splitPath(String path) {
    var value = path;
    while (value.length > 1 && value.endsWith(slash)) {
      value = value.substring(0, value.length - 1);
    }
    return value.split(slash);
  }

  /// Normalizes path by converting any backslashes to forward slashes.
  ///
  /// A `null` path normalizes to the empty string.
  String posixify(String? path) => _posixify(path, fileSeparator);

  static String _posixify(String? path, String fileSeparator) {
    if (path == null) {
      return '';
    }
    return fileSeparator == backslash && path.contains(backslash)
        ? path.replaceAll(backslash, slash)
        : path;
  }

  /// Expands the specified path by converting the path to a posix path,
  /// resolving parent references (`..`), and removing self references (`.`).
  ///
  /// Returns a posix path with parent references resolved and self references
  /// removed. The result is relative if the path is relative and absolute if
  /// the path is absolute.
  String expandPath(String path) {
    final (segments: pathSegments, root: pathRoot) = partitionPath(path);
    return _joinExpanded(path, pathSegments, pathRoot);
  }

  static String _expandPath(String path, String fileSeparator) {
    final (segments: pathSegments, root: pathRoot) = _partition(
      path,
      web: false,
      fileSeparator: fileSeparator,
    );
    return _joinExpanded(path, pathSegments, pathRoot);
  }

  static String _joinExpanded(
    String path,
    List<String> pathSegments,
    String? pathRoot,
  ) {
    if (!path.contains(dotDot)) {
      return _join(pathSegments, pathRoot);
    }
    final resolvedSegments = <String>[];
    for (final segment in pathSegments) {
      if (segment == dotDot) {
        // `..` at the top has nothing to pop.
        if (resolvedSegments.isNotEmpty) {
          resolvedSegments.removeLast();
        }
      } else {
        resolvedSegments.add(segment);
      }
    }
    return _join(resolvedSegments, pathRoot);
  }

  /// Partitions the path into path segments, removing self references (`.`)
  /// and the trailing slash, if present. Prior to being partitioned, the path
  /// is converted to a posix path.
  ///
  /// Parent references are not resolved by this method since the consumer
  /// often needs to handle this resolution in a certain context (checking for
  /// the breach of a jail, for instance).
  ///
  /// Returns a record containing the list of path segments and the path root
  /// (e.g. `/`, `./`, `c:/`, or `//`), which is `null` unless the path is
  /// absolute.
  ({List<String> segments, String? root}) partitionPath(
    String path, {
    bool web = false,
  }) {
    final cache = web ? _partitionPathWeb : _partitionPathSys;
    final cached = cache[path];
    if (cached != null) {
      return cached;
    }
    final result = _partition(path, web: web, fileSeparator: fileSeparator);
    cache[path] = result;
    return result;
  }

  static ({List<String> segments, String? root}) _partition(
    String path, {
    required bool web,
    required String fileSeparator,
  }) {
    final posixPath = _posixify(path, fileSeparator);

    String? root;
    if (web) {
      // ex. /sample/path
      if (posixPath.startsWith(slash)) {
        root = slash;
      }
      // ex. ./sample/path
      else if (posixPath.startsWith(dotSlash)) {
        root = dotSlash;
      }
      // otherwise ex. sample/path
    } else if (_isRoot(posixPath, fileSeparator)) {
      // ex. //sample/path
      if (posixPath.startsWith(doubleSlash)) {
        root = doubleSlash;
      }
      // ex. /sample/path
      else if (posixPath.startsWith(slash)) {
        root = slash;
      }
      // ex. uri:classloader:sample/path (or uri:classloader:/sample/path)
      else if (posixPath.startsWith(uriClassloader)) {
        root = posixPath.substring(0, uriClassloader.length);
      }
      // ex. C:/sample/path (or file:///sample/path in browser environment)
      else {
        root = posixPath.substring(0, posixPath.indexOf(slash) + 1);
      }
    }
    // ex. ./sample/path
    else if (posixPath.startsWith(dotSlash)) {
      root = dotSlash;
    }
    // otherwise ex. sample/path

    final rest = root != null ? posixPath.substring(root.length) : posixPath;
    // Drop trailing empty fields.
    final pathSegments = rest.isEmpty ? <String>[] : rest.split(slash);
    while (pathSegments.isNotEmpty && pathSegments.last.isEmpty) {
      pathSegments.removeLast();
    }
    // strip out all dot entries
    pathSegments.removeWhere((segment) => segment == dot);
    return (segments: pathSegments, root: root);
  }

  /// Joins the segments using the posix file separator. Uses the [root], if
  /// specified, to construct an absolute path. Otherwise joins the segments as
  /// a relative path.
  String joinPath(List<String> segments, [String? root]) =>
      _join(segments, root);

  static String _join(List<String> segments, String? root) =>
      root != null ? '$root${segments.join(slash)}' : segments.join(slash);

  /// Securely resolves a system path.
  ///
  /// Resolves the [target] to an absolute path on the current filesystem. The
  /// target is assumed to be relative to the [start] path, [jail] path, or
  /// working directory (specified in the constructor), in that order. If a
  /// jail path is specified, the resolved path is forced to descend from the
  /// jail path. If a jail path is not provided, the resolved path may be any
  /// location on the system. If the target is an absolute path, it is used as
  /// is (unless it breaches the jail path). Expands all parent and self
  /// references in the resolved path.
  ///
  /// [jail] must be an absolute path when specified. When [recover] is false,
  /// a path that breaches the jail throws a [SecurityError] instead of being
  /// recovered automatically. [targetName] is used in messages to refer to the
  /// path being resolved.
  ///
  /// Returns an absolute path relative to the [start] path, if specified, and
  /// confined to the [jail] path, if specified. The path is posixified and all
  /// parent and self references in the path are expanded.
  String systemPath(
    String? target, {
    String? start,
    String? jail,
    bool recover = true,
    String? targetName,
  }) {
    final name = targetName ?? 'path';

    var jailPath = jail;
    if (jailPath != null) {
      if (!isRoot(jailPath)) {
        throw SecurityError('Jail is not an absolute path: $jailPath');
      }
      jailPath = posixify(jailPath);
    }

    List<String> targetSegments;
    if (target != null) {
      if (isRoot(target)) {
        final targetPath = expandPath(target);
        if (jailPath != null && descendsFrom(targetPath, jailPath) == null) {
          if (!recover) {
            throw SecurityError(
              '$name $target is outside of jail: $jailPath '
              '(disallowed in safe mode)',
            );
          }
          onWarn('$name is outside of jail; recovering automatically');
          final (segments: absoluteSegments, :root) = partitionPath(targetPath);
          final (segments: jailSegments, root: jailRoot) = partitionPath(
            jailPath,
          );
          return joinPath([...jailSegments, ...absoluteSegments], jailRoot);
        }
        return targetPath;
      } else {
        targetSegments = partitionPath(target).segments;
      }
    } else {
      targetSegments = [];
    }

    var startPath = start;
    if (targetSegments.isEmpty) {
      if (startPath == null || startPath.isEmpty) {
        return jailPath ?? workingDir;
      } else if (isRoot(startPath)) {
        if (jailPath == null) {
          return expandPath(startPath);
        }
        startPath = posixify(startPath);
      } else {
        targetSegments = partitionPath(startPath).segments;
        startPath = jailPath ?? workingDir;
      }
    } else if (startPath == null || startPath.isEmpty) {
      startPath = jailPath ?? workingDir;
    } else if (isRoot(startPath)) {
      if (jailPath != null) {
        startPath = posixify(startPath);
      }
    } else {
      //startPath = systemPath(startPath, jailPath, jailPath, recover, name)
      startPath = '${_chompSlash(jailPath ?? workingDir)}/$startPath';
    }

    // both jail and start have been posixified at this point if jail is set
    var recheck = jailPath != null && descendsFrom(startPath, jailPath) == null;
    List<String> startSegments;
    String? pathRoot;
    List<String>? jailSegments;
    if (jailPath != null && recheck && fileSeparator == backslash) {
      final (segments: parsedStart, root: startRoot) = partitionPath(startPath);
      startSegments = parsedStart;
      final (segments: parsedJail, root: parsedJailRoot) = partitionPath(
        jailPath,
      );
      jailSegments = parsedJail;
      pathRoot = parsedJailRoot;
      if (startRoot != parsedJailRoot) {
        if (!recover) {
          throw SecurityError(
            'start path for $name $startPath refers to location outside jail '
            'root: $jailPath (disallowed in safe mode)',
          );
        }
        onWarn(
          'start path for $name is outside of jail root; '
          'recovering automatically',
        );
        startSegments = jailSegments;
        recheck = false;
      }
    } else {
      final (segments: parsedStart, root: parsedRoot) = partitionPath(
        startPath,
      );
      startSegments = parsedStart;
      pathRoot = parsedRoot;
    }

    var resolvedSegments = [...startSegments, ...targetSegments];
    if (resolvedSegments.contains(dotDot)) {
      final unresolvedSegments = resolvedSegments;
      resolvedSegments = [];
      if (jailPath != null) {
        jailSegments ??= partitionPath(jailPath).segments;
        var warned = false;
        for (final segment in unresolvedSegments) {
          if (segment == dotDot) {
            if (resolvedSegments.length > jailSegments.length) {
              resolvedSegments.removeLast();
            } else if (recover) {
              if (!warned) {
                onWarn(
                  '$name has illegal reference to ancestor of jail; '
                  'recovering automatically',
                );
                warned = true;
              }
            } else {
              throw SecurityError(
                '$name $target refers to location outside jail: $jailPath '
                '(disallowed in safe mode)',
              );
            }
          } else {
            resolvedSegments.add(segment);
          }
        }
      } else {
        for (final segment in unresolvedSegments) {
          if (segment == dotDot) {
            // `..` at the top has nothing to pop.
            if (resolvedSegments.isNotEmpty) {
              resolvedSegments.removeLast();
            }
          } else {
            resolvedSegments.add(segment);
          }
        }
      }
    }

    if (recheck) {
      final targetPath = joinPath(resolvedSegments, pathRoot);
      if (descendsFrom(targetPath, jailPath!) != null) {
        return targetPath;
      } else if (recover) {
        onWarn('$name is outside of jail; recovering automatically');
        jailSegments ??= partitionPath(jailPath).segments;
        return joinPath([...jailSegments, ...targetSegments], pathRoot);
      } else {
        throw SecurityError(
          '$name $target is outside of jail: $jailPath '
          '(disallowed in safe mode)',
        );
      }
    } else {
      return joinPath(resolvedSegments, pathRoot);
    }
  }

  /// Resolves a web path from the [target] and [start] paths.
  /// The main function of this operation is to resolve any parent
  /// references and remove any self references.
  ///
  /// The target is assumed to be a path, not a qualified URI.
  /// That check should happen before this method is invoked.
  ///
  /// Returns a path that joins the target path with the
  /// start path with any parent references resolved and self
  /// references removed.
  String webPath(String? target, [String? start]) {
    var targetPath = posixify(target);
    final startPath = posixify(start);
    String? uriPrefix;

    if (startPath.isNotEmpty && !isWebRoot(targetPath)) {
      final joined = startPath.endsWith(slash)
          ? '$startPath$targetPath'
          : '$startPath/$targetPath';
      final (:stripped, :prefix) = _extractUriPrefix(joined);
      targetPath = stripped;
      uriPrefix = prefix;
    }

    final (segments: targetSegments, root: targetRoot) = partitionPath(
      targetPath,
      web: true,
    );
    final resolvedSegments = <String>[];
    for (final segment in targetSegments) {
      if (segment == dotDot) {
        if (resolvedSegments.isEmpty) {
          if (targetRoot == null || targetRoot == dotSlash) {
            resolvedSegments.add(segment);
          }
        } else if (resolvedSegments.last == dotDot) {
          resolvedSegments.add(segment);
        } else {
          resolvedSegments.removeLast();
        }
      } else {
        resolvedSegments.add(segment);
        // checking for empty would eliminate repeating forward slashes
        //resolvedSegments.add(segment) unless segment.empty?
      }
    }

    var resolvedPath = joinPath(resolvedSegments, targetRoot);
    if (resolvedPath.contains(' ')) {
      resolvedPath = resolvedPath.replaceAll(' ', '%20');
    }

    return uriPrefix != null ? '$uriPrefix$resolvedPath' : resolvedPath;
  }

  /// Efficiently extracts the URI prefix from [str] if the string is a URI.
  ///
  /// Uses the URI-sniffing pattern to match the URI prefix in the specified
  /// string (e.g. `http://`). If present, the prefix is removed.
  ///
  /// Returns a record containing the specified string without the URI prefix,
  /// if present, and the extracted URI prefix.
  ({String stripped, String? prefix}) _extractUriPrefix(String str) {
    if (str.contains(':')) {
      final match = _uriSniffRx.matchAsPrefix(str);
      if (match != null) {
        return (stripped: str.substring(match.end), prefix: match.group(0));
      }
    }
    return (stripped: str, prefix: null);
  }
}

/// Removes a single trailing `/`.
String _chompSlash(String value) =>
    value.endsWith(PathResolver.slash) && value.isNotEmpty
    ? value.substring(0, value.length - 1)
    : value;
