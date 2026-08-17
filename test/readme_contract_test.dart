import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String english = File('README.md').readAsStringSync();
  final String chinese = File('README.zh-CN.md').readAsStringSync();

  test('English and Chinese READMEs share identical Dart snippets', () {
    final List<String> englishSnippets = _dartBlocks(english);
    final List<String> chineseSnippets = _dartBlocks(chinese);

    expect(englishSnippets, isNotEmpty);
    expect(chineseSnippets, englishSnippets);
  });

  test('English and Chinese READMEs share badge sources and section count', () {
    expect(_badgeSources(chinese), _badgeSources(english));
    expect(
        _levelTwoHeadings(chinese).length, _levelTwoHeadings(english).length);
  });

  test('README local links and local images resolve inside the package', () {
    for (final String document in <String>[english, chinese]) {
      for (final String target in _localTargets(document)) {
        expect(File(target).existsSync(), isTrue, reason: 'Missing $target');
      }
    }
  });

  test('README badges contain no static performance or readiness claims', () {
    for (final String source in _badgeSources(english)) {
      final String normalized = source.toLowerCase();
      expect(normalized, isNot(contains('120')));
      expect(normalized, isNot(contains('fps')));
      expect(normalized, isNot(contains('production--ready')));
      expect(normalized, isNot(contains('all--platforms')));
    }
  });
}

List<String> _dartBlocks(String markdown) {
  return RegExp(
    r'```dart\n(.*?)\n```',
    dotAll: true,
  ).allMatches(markdown).map((Match match) => match.group(1)!).toList();
}

List<String> _badgeSources(String markdown) {
  return RegExp(
    r'<img src="(https://img\.shields\.io/[^"]+)"',
  ).allMatches(markdown).map((Match match) => match.group(1)!).toList();
}

List<String> _levelTwoHeadings(String markdown) {
  return RegExp(
    r'^## .+$',
    multiLine: true,
  ).allMatches(markdown).map((Match match) => match.group(0)!).toList();
}

Iterable<String> _localTargets(String markdown) sync* {
  final Set<String> targets = <String>{};
  final Iterable<Match> markdownLinks = RegExp(
    r'!?\[[^\]]*\]\(([^)]+)\)',
  ).allMatches(markdown);
  final Iterable<Match> htmlLinks = RegExp(
    r'(?:href|src)="([^"]+)"',
  ).allMatches(markdown);
  for (final Match match in <Match>[
    ...markdownLinks,
    ...htmlLinks,
  ]) {
    final String target = match.group(1)!;
    if (target.startsWith('http://') ||
        target.startsWith('https://') ||
        target.startsWith('#')) {
      continue;
    }
    targets.add(target.split('#').first);
  }
  yield* targets;
}
