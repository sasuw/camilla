import 'dart:io';

import 'package:camilla/file_handler.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory fixture;

  setUp(() {
    fixture = Directory.current.createTempSync('camilla-test-');
    Directory('${fixture.path}/nested').createSync();
    File('${fixture.path}/included.html').createSync();
    File('${fixture.path}/nested/included.htm').createSync();
    File('${fixture.path}/excluded.HTML').createSync();
    File('${fixture.path}/excluded.html.bak').createSync();
    File('${fixture.path}/excluded.txt').createSync();
  });

  tearDown(() {
    fixture.deleteSync(recursive: true);
  });

  test('collects lowercase HTML and HTM files only', () {
    final pages = FileHandler.getAllHtmlFiles(fixture);
    final pageNames = pages.map((page) => page.fileName).toList();

    expect(pageNames, hasLength(2));
    expect(pageNames, contains(endsWith('included.html')));
    expect(pageNames, contains(endsWith('nested/included.htm')));
  });

  test('normalizes Windows paths for sitemap URLs', () {
    expect(
      FileHandler.normalizePathForSitemap(r'nested\about.html', path.windows),
      'nested/about.html',
    );
  });

  test(
      'reports error when --baseUrl is missing without throwing unhandled exception',
      () async {
    final result = await Process.run(
      Platform.executable,
      ['bin/camilla.dart', '-l'],
    );
    expect(result.exitCode, 1);
    expect(result.stdout, contains('Option --baseUrl is mandatory'));
    expect(result.stderr, isEmpty);
  });
}
