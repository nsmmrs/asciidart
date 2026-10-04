/// Dart port of `test/paths_test.rb`.
///
/// Mirrors all 50 Ruby test blocks. Five are marked skipped with a documented
/// reason: two assert Ruby-stdlib `File.dirname` behavior (not
/// `PathResolver` behavior), and three are JRuby-only classloader tests
/// (`PathResolver.isRoot` mirrors MRI Ruby, where a classloader URI is not a
/// root).
library;

import 'dart:io';

import 'package:asciidoctor/src/path_resolver.dart';
import 'package:test/test.dart';

/// Collects warning messages passed to [PathResolver.onWarn].
///
/// Mirrors `Asciidoctor::MemoryLogger` for the warnings `PathResolver` emits
/// (the only severity it ever logs is `warn`).
class MemoryLog {
  /// Messages received so far, in order.
  final List<String> messages = [];

  /// Records [message].
  void call(String message) => messages.add(message);

  /// Discards all recorded messages.
  void clear() {
    messages.clear();
  }
}

/// Asserts [log] holds exactly one warning equal to [expected], or — when
/// [expected] starts with `~` — containing the remainder, mirroring
/// `assert_message` in the Ruby `test_helper`.
void expectWarn(MemoryLog log, String expected) {
  expect(log.messages, hasLength(1));
  if (expected.startsWith('~')) {
    expect(log.messages.single, contains(expected.substring(1)));
  } else {
    expect(log.messages.single, equals(expected));
  }
}

void main() {
  group('Web Paths', () {
    late PathResolver resolver;

    setUp(() {
      resolver = PathResolver();
    });

    test('target with absolute path', () {
      expect(resolver.webPath('/images'), equals('/images'));
      expect(resolver.webPath('/images', ''), equals('/images'));
      expect(resolver.webPath('/images'), equals('/images'));
    });

    test('target with relative path', () {
      expect(resolver.webPath('images'), equals('images'));
      expect(resolver.webPath('images', ''), equals('images'));
      expect(resolver.webPath('images'), equals('images'));
    });

    test('target with hidden relative path', () {
      expect(resolver.webPath('.images'), equals('.images'));
      expect(resolver.webPath('.images', ''), equals('.images'));
      expect(resolver.webPath('.images'), equals('.images'));
    });

    test('target with path relative to current directory', () {
      expect(resolver.webPath('./images'), equals('./images'));
      expect(resolver.webPath('./images', ''), equals('./images'));
      expect(resolver.webPath('./images'), equals('./images'));
    });

    test('target with absolute path ignores start path', () {
      expect(resolver.webPath('/images', 'foo'), equals('/images'));
      expect(resolver.webPath('/images', '/foo'), equals('/images'));
      expect(resolver.webPath('/images', './foo'), equals('/images'));
    });

    test('target with relative path appended to start path', () {
      expect(resolver.webPath('images', 'assets'), equals('assets/images'));
      expect(resolver.webPath('images', '/assets'), equals('/assets/images'));
      //expect(resolver.webPath('tiger.png', '/assets//images'),
      //    equals('/assets/images/tiger.png'));
      expect(resolver.webPath('images', './assets'), equals('./assets/images'));
      expect(resolver.webPath('theme.css', '/'), equals('/theme.css'));
      expect(resolver.webPath('theme.css', '/css/'), equals('/css/theme.css'));
    });

    test(
      'target with path relative to current directory appended to start path',
      () {
        expect(resolver.webPath('./images', 'assets'), equals('assets/images'));
        expect(
          resolver.webPath('./images', '/assets'),
          equals('/assets/images'),
        );
        expect(
          resolver.webPath('./images', './assets'),
          equals('./assets/images'),
        );
      },
    );

    test('target with relative path appended to url start path', () {
      expect(
        resolver.webPath('images', 'http://www.example.com/assets'),
        equals('http://www.example.com/assets/images'),
      );
    });

    // enable if we want to allow web_path to detect and preserve a target URI
    //test('target with file url appended to relative path', () {
    //  expect(resolver.webPath('file:///home/username/styles/asciidoctor.css', '.'),
    //      equals('file:///home/username/styles/asciidoctor.css'));
    //});

    // enable if we want to allow web_path to detect and preserve a target URI
    //test('target with http url appended to relative path', () {
    //  expect(resolver.webPath('http://example.com/asciidoctor.css', '.'),
    //      equals('http://example.com/asciidoctor.css'));
    //});

    test('normalize target', () {
      expect(resolver.webPath('../images/../images'), equals('../images'));
    });

    test('append target to start path and normalize', () {
      expect(
        resolver.webPath('../images/../images', '../images'),
        equals('../images'),
      );
      expect(resolver.webPath('../images', '..'), equals('../../images'));
    });

    test('normalize parent directory that follows root', () {
      expect(resolver.webPath('/../tiger.png'), equals('/tiger.png'));
      expect(resolver.webPath('/../../tiger.png'), equals('/tiger.png'));
    });

    test('uses start when target is empty', () {
      expect(resolver.webPath('', 'assets/images'), equals('assets/images'));
      expect(resolver.webPath(null, 'assets/images'), equals('assets/images'));
    });

    test('posixifies windows paths', () {
      resolver.fileSeparator = r'\';
      expect(resolver.webPath(r'\images'), equals('/images'));
      expect(resolver.webPath(r'..\images'), equals('../images'));
      expect(resolver.webPath(r'\..\images'), equals('/images'));
      expect(resolver.webPath(r'assets\images'), equals('assets/images'));
      expect(
        resolver.webPath(r'assets\images', r'..\images\..'),
        equals('../assets/images'),
      );
    });

    test('URL encode spaces in path', () {
      expect(
        resolver.webPath('lots of images', 'assets and stuff'),
        equals('assets%20and%20stuff/lots%20of%20images'),
      );
    });
  });

  group('System Paths', () {
    const jail = '/home/doctor/docs';
    late PathResolver resolver;
    late MemoryLog log;

    setUp(() {
      log = MemoryLog();
      resolver = PathResolver(onWarn: log.call);
    });

    test('raises security error if jail is not an absolute path', () {
      expect(
        () =>
            resolver.systemPath('images/tiger.png', start: '/etc', jail: 'foo'),
        throwsA(isA<SecurityError>()),
      );
    });

    //test('raises security error if jail is not a canonical path', () {
    //  expect(
    //    () => resolver.systemPath(
    //        'images/tiger.png', start: '/etc', jail: '$jail/../foo'),
    //    throwsA(isA<SecurityError>()),
    //  );
    //});

    test('prevents access to paths outside of jail', () {
      final result = resolver.systemPath(
        '../../../../../css',
        start: '$jail/assets/stylesheets',
        jail: jail,
      );
      expect(result, equals('$jail/css'));
      expectWarn(
        log,
        'path has illegal reference to ancestor of jail; '
        'recovering automatically',
      );

      log.clear();
      final absoluteResult = resolver.systemPath(
        '/../../../../../css',
        start: '$jail/assets/stylesheets',
        jail: jail,
      );
      expect(absoluteResult, equals('$jail/css'));
      expectWarn(log, 'path is outside of jail; recovering automatically');

      log.clear();
      final relativeStartResult = resolver.systemPath(
        '../../../css',
        start: '../../..',
        jail: jail,
      );
      expect(relativeStartResult, equals('$jail/css'));
      expectWarn(
        log,
        'path has illegal reference to ancestor of jail; '
        'recovering automatically',
      );
    });

    test('throws exception for illegal path access if recover is false', () {
      expect(
        () => resolver.systemPath(
          '../../../../../css',
          start: '$jail/assets/stylesheets',
          jail: jail,
          recover: false,
        ),
        throwsA(isA<SecurityError>()),
      );
    });

    test('resolves start path if target is empty', () {
      expect(
        resolver.systemPath('', start: '$jail/assets/stylesheets', jail: jail),
        equals('$jail/assets/stylesheets'),
      );
      expect(
        resolver.systemPath(
          null,
          start: '$jail/assets/stylesheets',
          jail: jail,
        ),
        equals('$jail/assets/stylesheets'),
      );
    });

    test('expands parent references in start path if target is empty', () {
      expect(
        resolver.systemPath(
          '',
          start: '$jail/assets/../stylesheets',
          jail: jail,
        ),
        equals('$jail/stylesheets'),
      );
    });

    test('expands parent references in start path if target is not empty', () {
      expect(
        resolver.systemPath(
          'site.css',
          start: '$jail/assets/../stylesheets',
          jail: jail,
        ),
        equals('$jail/stylesheets/site.css'),
      );
    });

    test('resolves start path if target is dot', () {
      expect(
        resolver.systemPath('.', start: '$jail/assets/stylesheets', jail: jail),
        equals('$jail/assets/stylesheets'),
      );
      expect(
        resolver.systemPath(
          './',
          start: '$jail/assets/stylesheets',
          jail: jail,
        ),
        equals('$jail/assets/stylesheets'),
      );
    });

    test('treats absolute target outside of jail as relative when jail '
        'is specified', () {
      final rootResult = resolver.systemPath(
        '/',
        start: '$jail/assets/stylesheets',
        jail: jail,
      );
      expect(rootResult, equals(jail));
      expectWarn(log, 'path is outside of jail; recovering automatically');

      log.clear();
      final fooResult = resolver.systemPath(
        '/foo',
        start: '$jail/assets/stylesheets',
        jail: jail,
      );
      expect(fooResult, equals('$jail/foo'));
      expectWarn(log, 'path is outside of jail; recovering automatically');

      log.clear();
      final dotDotResult = resolver.systemPath(
        '/../foo',
        start: '$jail/assets/stylesheets',
        jail: jail,
      );
      expect(dotDotResult, equals('$jail/foo'));
      expectWarn(log, 'path is outside of jail; recovering automatically');

      log.clear();
      resolver.fileSeparator = r'\';
      final windowsResult = resolver.systemPath(
        'baz.adoc',
        start: 'C:/foo',
        jail: 'C:/bar',
      );
      expect(windowsResult, equals('C:/bar/baz.adoc'));
      expectWarn(log, 'path is outside of jail; recovering automatically');
    });

    test('allows use of absolute target or start if resolved path is '
        'sub-path of jail', () {
      expect(
        resolver.systemPath('$jail/my/path', start: '', jail: jail),
        equals('$jail/my/path'),
      );
      expect(
        resolver.systemPath('$jail/my/path', jail: jail),
        equals('$jail/my/path'),
      );
      expect(
        resolver.systemPath('', start: '$jail/my/path', jail: jail),
        equals('$jail/my/path'),
      );
      expect(
        resolver.systemPath(null, start: '$jail/my/path', jail: jail),
        equals('$jail/my/path'),
      );
      expect(
        resolver.systemPath('path', start: '$jail/my', jail: jail),
        equals('$jail/my/path'),
      );
      expect(
        resolver.systemPath('/foo/bar/baz.adoc', jail: '/'),
        equals('/foo/bar/baz.adoc'),
      );
      expect(
        resolver.systemPath('baz.adoc', start: '/foo/bar', jail: '/'),
        equals('/foo/bar/baz.adoc'),
      );
      expect(
        resolver.systemPath('baz.adoc', start: 'foo/bar', jail: '/'),
        equals('/foo/bar/baz.adoc'),
      );
    });

    test('uses jail path if start path is empty', () {
      expect(
        resolver.systemPath('images/tiger.png', start: '', jail: jail),
        equals('$jail/images/tiger.png'),
      );
      expect(
        resolver.systemPath('images/tiger.png', jail: jail),
        equals('$jail/images/tiger.png'),
      );
    });

    test('warns if start is not contained within jail', () {
      final result = resolver.systemPath(
        'images/tiger.png',
        start: '/etc',
        jail: jail,
      );
      expect(result, equals('$jail/images/tiger.png'));
      expectWarn(log, 'path is outside of jail; recovering automatically');

      log.clear();
      final dotResult = resolver.systemPath('.', start: '/etc', jail: jail);
      expect(dotResult, equals(jail));
      expectWarn(log, 'path is outside of jail; recovering automatically');

      log.clear();
      resolver.fileSeparator = r'\';
      final windowsResult = resolver.systemPath(
        '.',
        start: 'C:/foo',
        jail: 'C:/bar',
      );
      expect(windowsResult, equals('C:/bar'));
      expectWarn(log, 'path is outside of jail; recovering automatically');
    });

    test('allows start path to be parent of jail if resolved target is '
        'inside jail', () {
      expect(
        resolver.systemPath('foo/path', start: jail, jail: '$jail/foo'),
        equals('$jail/foo/path'),
      );
      resolver.fileSeparator = r'\';
      expect(
        resolver.systemPath(
          'project/README.adoc',
          start: 'C:/dev',
          jail: 'C:/dev/project',
        ),
        equals('C:/dev/project/README.adoc'),
      );
    });

    test(
      'relocates target to jail if resolved value fails outside of jail',
      () {
        final result = resolver.systemPath(
          'bar/baz.adoc',
          start: jail,
          jail: '$jail/foo',
        );
        expect(result, equals('$jail/foo/bar/baz.adoc'));
        expectWarn(log, 'path is outside of jail; recovering automatically');

        log.clear();
        resolver.fileSeparator = r'\';
        final windowsResult = resolver.systemPath(
          'bar/baz.adoc',
          start: 'D:/',
          jail: 'C:/foo',
        );
        expect(windowsResult, equals('C:/foo/bar/baz.adoc'));
        expectWarn(log, '~outside of jail root');
      },
    );

    test('raises security error if start is not contained within jail '
        'and recover is disabled', () {
      expect(
        () => resolver.systemPath(
          'images/tiger.png',
          start: '/etc',
          jail: jail,
          recover: false,
        ),
        throwsA(isA<SecurityError>()),
      );
      expect(
        () =>
            resolver.systemPath('.', start: '/etc', jail: jail, recover: false),
        throwsA(isA<SecurityError>()),
      );
    });

    test(
      'expands parent references in absolute path if jail is not specified',
      () {
        expect(
          resolver.systemPath('/usr/share/../../etc/stylesheet.css'),
          equals('/etc/stylesheet.css'),
        );
      },
    );

    test('resolves absolute directory if jail is not specified', () {
      expect(
        resolver.systemPath(
          '/usr/share/stylesheet.css',
          start: '/home/dallen/docs/assets/stylesheets',
        ),
        equals('/usr/share/stylesheet.css'),
      );
    });

    test('resolves ancestor directory of start if jail is not specified', () {
      expect(
        resolver.systemPath(
          '../../../../../usr/share/stylesheet.css',
          start: '/home/dallen/docs/assets/stylesheets',
        ),
        equals('/usr/share/stylesheet.css'),
      );
    });

    test(
      'resolves absolute path if start is absolute and target is relative',
      () {
        expect(
          resolver.systemPath('assets/stylesheet.css', start: '/usr/share'),
          equals('/usr/share/assets/stylesheet.css'),
        );
      },
    );

    test(
      'File.dirname preserves UNC path root on Windows',
      skip:
          'PERMANENT: asserts Ruby-stdlib File.dirname behavior, which '
          'has no Dart '
          'equivalent; UNC resolution is covered by the PathResolver tests '
          'below',
      () {},
    );

    test(
      'File.dirname preserves posix-style UNC path root on Windows',
      skip:
          'PERMANENT: asserts Ruby-stdlib File.dirname behavior, which '
          'has no Dart '
          'equivalent; UNC resolution is covered by the PathResolver tests '
          'below',
      () {},
    );

    test('resolves UNC path if start is absolute and target is relative', () {
      expect(
        resolver.systemPath(
          'assets/stylesheet.css',
          start: r'//QA/c$/users/asciidoctor',
        ),
        equals(r'//QA/c$/users/asciidoctor/assets/stylesheet.css'),
      );
    });

    test('resolves UNC path if target is UNC path', () {
      resolver.fileSeparator = r'\';
      expect(
        resolver.systemPath(r'\\server\docs\output.html'),
        equals('//server/docs/output.html'),
      );
    });

    test('resolves UNC path if target is posix-style UNC path', () {
      expect(
        resolver.systemPath('//server/docs/output.html'),
        equals('//server/docs/output.html'),
      );
    });

    test(
      'resolves classloader path if start is classloader path and '
      'target is relative',
      skip:
          'PERMANENT: JRuby-only; isRoot mirrors MRI Ruby, where a '
          'classloader URI '
          'is not a root',
      () {},
    );

    test(
      'resolves classloader path if start is root-relative classloader '
      'path and target is relative',
      skip:
          'PERMANENT: JRuby-only; isRoot mirrors MRI Ruby, where a '
          'classloader URI '
          'is not a root',
      () {},
    );

    test(
      'preserves classloader path if start is absolute path and target '
      'is classloader path',
      skip:
          'PERMANENT: JRuby-only; isRoot mirrors MRI Ruby, where a '
          'classloader URI '
          'is not a root',
      () {},
    );

    test('resolves relative target relative to current directory if '
        'start is empty', () {
      // Directory.current.path uses native separators; posixify it the way
      // the resolver does so the expectation holds on every platform.
      final pwd = resolver.posixify(Directory.current.path);
      expect(
        resolver.systemPath('images/tiger.png', start: ''),
        equals('$pwd/images/tiger.png'),
      );
      expect(
        resolver.systemPath('images/tiger.png'),
        equals('$pwd/images/tiger.png'),
      );
      expect(
        resolver.systemPath('images/tiger.png'),
        equals('$pwd/images/tiger.png'),
      );
    });

    test('resolves relative hidden target relative to current '
        'directory if start is empty', () {
      final pwd = resolver.posixify(Directory.current.path);
      expect(
        resolver.systemPath('.images/tiger.png', start: ''),
        equals('$pwd/.images/tiger.png'),
      );
      expect(
        resolver.systemPath('.images/tiger.png'),
        equals('$pwd/.images/tiger.png'),
      );
    });

    test('resolves and normalizes start when target is empty', () {
      final pwd = resolver.posixify(Directory.current.path);
      expect(
        resolver.systemPath('', start: '/home/doctor/docs'),
        equals('/home/doctor/docs'),
      );
      expect(
        resolver.systemPath('', start: '/home/doctor/./docs'),
        equals('/home/doctor/docs'),
      );
      expect(
        resolver.systemPath(null, start: '/home/doctor/docs'),
        equals('/home/doctor/docs'),
      );
      expect(
        resolver.systemPath(null, start: '/home/doctor/./docs'),
        equals('/home/doctor/docs'),
      );
      expect(
        resolver.systemPath(null, start: 'assets/images'),
        equals('$pwd/assets/images'),
      );
      resolver.systemPath('', start: '../assets/images', jail: jail);
      expectWarn(
        log,
        'path has illegal reference to ancestor of jail; '
        'recovering automatically',
      );
    });

    test('posixifies windows paths', () {
      resolver.fileSeparator = r'\';
      expect(
        resolver.systemPath(
          r'..\css',
          start: r'assets\stylesheets',
          jail: jail,
        ),
        equals('$jail/assets/css'),
      );
    });

    test('resolves windows paths when file separator is backlash', () {
      resolver.fileSeparator = r'\';

      expect(
        resolver.systemPath(
          '..',
          start: r'C:\data\docs\assets',
          jail: r'C:\data\docs',
        ),
        equals('C:/data/docs'),
      );

      final parentResult = resolver.systemPath(
        r'..\..',
        start: r'C:\data\docs\assets',
        jail: r'C:\data\docs',
      );
      expect(parentResult, equals('C:/data/docs'));
      expectWarn(
        log,
        'path has illegal reference to ancestor of jail; '
        'recovering automatically',
      );

      log.clear();
      final cssResult = resolver.systemPath(
        r'..\..\css',
        start: r'C:\data\docs\assets',
        jail: r'C:\data\docs',
      );
      expect(cssResult, equals('C:/data/docs/css'));
      expectWarn(
        log,
        'path has illegal reference to ancestor of jail; '
        'recovering automatically',
      );
    });

    test('should calculate relative path', () {
      final filename = resolver.systemPath(
        'part1/chapter1/section1.adoc',
        jail: jail,
      );
      expect(filename, equals('$jail/part1/chapter1/section1.adoc'));
      expect(
        resolver.relativePath(filename, jail),
        equals('part1/chapter1/section1.adoc'),
      );
    });

    test(
      'should resolve relative path to filename outside of base directory',
      () {
        const filename = '/home/shared/partials';
        const baseDir = '/home/user/docs';
        final result = resolver.relativePath(filename, baseDir);
        expect(result, equals('../../shared/partials'));
      },
    );

    test('should return original path if relative path cannot be computed', () {
      // The Ruby test is Windows-only because CRuby's Pathname only raises
      // for different drive letters on Windows. The Dart port computes the
      // relative path itself, independent of platform, so this runs
      // everywhere.
      const filename = 'D:/path/to/include/file.txt';
      const baseDir = 'C:/docs';
      final result = resolver.relativePath(filename, baseDir);
      expect(result, equals('D:/path/to/include/file.txt'));
    });

    test(
      'should resolve relative path relative to base dir in unsafe mode',
      () {
        // Mirrors `doc.normalize_system_path 'tiger.png', 'images'` in unsafe
        // mode, where the start is joined to the base dir and no jail applies.
        final baseDir = '${Directory.current.path}/test/fixtures/base';
        final expected = '$baseDir/images/tiger.png';
        final actual = resolver.systemPath(
          'tiger.png',
          start: '$baseDir/images',
        );
        expect(actual, equals(expected));
      },
    );

    test('should resolve absolute path as absolute in unsafe mode', () {
      // Mirrors `doc.normalize_system_path 'tiger.png', '/etc/images'` in
      // unsafe mode: an absolute start with no jail applies.
      final actual = resolver.systemPath('tiger.png', start: '/etc/images');
      expect(actual, equals('/etc/images/tiger.png'));
    });
  });
}
