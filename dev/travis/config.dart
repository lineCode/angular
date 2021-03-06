import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

/// Writes `<root>/.travis.yml` based on the configuration in this file.
void main() {
  // Start the preamble of .travis.yml.
  final prefix = new File(
    p.join('dev', 'travis', 'prefix.yaml'),
  )
      .readAsStringSync();
  final postfix = new File(
    p.join('dev', 'travis', 'postfix.yaml'),
  )
      .readAsStringSync();

  // Find packages.
  final include = new Glob('**/pubspec.yaml');

  // TODO: Perhaps just import .gitignore as well.
  final exclude = [
    new Glob('dev/**'),
    new Glob('angular/tools/**'),
    new Glob('**/build'),
  ];

  // Make build stages.
  final stages = <String>[];
  final packages = include
      .listSync()
      .map((pubspec) => p.normalize(p.dirname(pubspec.path)))
      .toList()
        ..sort();

  for (final package in packages) {
    if (exclude.any((e) => e.matches(package))) {
      continue;
    }

    // Every package has a pre-submit and build phase.
    stages.add(_analyze(package));

    if (_isBuildable(package)) {
      stages.add(_build(package));
    }

    // Some packages will also build in "release" (Dart2JS) mode.
    if (_hasReleaseMode(package)) {
      stages.add(_build(package, release: true));
    }

    // Some packages will have tests.
    if (_hasTests(package)) {
      final requiresBrowser = _hasBrowserTests(package);
      stages.add(_test(package, browser: requiresBrowser));
      if (_hasReleaseMode(package)) {
        stages.add(_test(package, browser: requiresBrowser));
      }
    }
  }

  new File('.travis.yml').writeAsStringSync([
    prefix,
    stages.join('\n\n'),
    '',
    postfix,
    '',
  ].join('\n'));
}

/// Whether there is a `test/` directory in this [path].
bool _hasTests(String path) {
  return new Directory(p.join(path, 'test')).existsSync();
}

/// Whether there is a `build.release.yaml` in this [path].
bool _hasReleaseMode(String path) {
  return new File(p.join(path, 'build.release.yaml')).existsSync();
}

/// Whether there are browsers being run as part `dart_test.yaml`.
bool _hasBrowserTests(String path) {
  final config = new File(p.join(path, 'dart_test.yaml'));
  if (config.existsSync()) {
    final text = config.readAsStringSync();
    // This could be a lot better.
    return text.contains('chrome');
  }
  return false;
}

/// Whether there is a custom `tool/test.sh` in this package.
bool _hasCustomTestScript(String path) {
  return new File(p.join(path, 'tool', 'test.sh')).existsSync();
}

/// Whether there is `build_runner` in `pubspec.yaml`.
bool _isBuildable(String path) => new File(p.join(path, 'pubspec.yaml'))
    .readAsStringSync()
    .contains('build_runner:');

String _analyze(String package) {
  return [
    '    - stage: presubmit',
    '      script: ./tool/travis.sh analyze',
    '      env: PKG="$package"',
  ].join('\n');
}

String _build(String package, {bool release: false}) {
  return [
    '    - stage: building',
    '      script: ./tool/travis.sh build${release ? ':release': ''}',
    '      env: PKG="$package"',
    '      cache:',
    '        directories:',
    '          - $package/.dart_tool',
  ].join('\n');
}

String _test(
  String package, {
  bool browser: false,
  bool release: false,
}) {
  if (_hasCustomTestScript(package)) {
    return [
      '    - stage: testing',
      '      script:',
      '        - cd $package',
      '        - ./tool/test.sh',
      '      env: PKG="$package"',
      '      cache:',
      '        directories:',
      '          - $package/.dart_tool',
    ].join('\n');
  }
  final out = [
    '    - stage: testing',
    '      script: ./tool/travis.sh test${release ? ':release' : ''}',
    '      env: PKG="$package"',
    '      cache:',
    '        directories:',
    '          - $package/.dart_tool',
  ];
  if (browser) {
    out.addAll([
      r'      addons:',
      r'        chrome: stable',
      r'      before_install:',
      r'        - export DISPLAY=:99.0',
      r'        - sh -e /etc/init.d/xvfb start',
      r'        - "t=0; until (xdpyinfo -display :99 &> /dev/null || test $t -gt 10); do sleep 1; let t=$t+1; done"',
    ]);
  }
  return out.join('\n');
}
