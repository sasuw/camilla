import 'dart:io';

import 'package:args/args.dart';
import 'package:camilla/fileHandler.dart';
import 'package:xml/xml.dart';
import 'package:intl/intl.dart';

final builder = XmlBuilder();
var baseUrl = 'https://example.com';

var rootDirContainsLangDirs = false;
var rootDirs = <String>[];
var numberOfHtmlFiles = 0;

void main(List<String> args) {
  var stopwatch = Stopwatch()..start();

  if (args.isEmpty) {
    stdout.writeln(
        'Usage: camilla --baseDirContainsLanguageDirs --version --baseUrl [baseUrl]');
    stdout.writeln(
        'Creates sitemap.xml of html files when run in the base directory.');
    exit(0);
  }

  final parser = ArgParser()
    ..addFlag('version', negatable: false, abbr: 'v')
    ..addFlag('baseDirContainsLanguageDirs', negatable: false, abbr: 'l')
    ..addOption('baseUrl', abbr: 'b');
  var argResults = parser.parse(args);
  if (argResults['version']) {
    var version = getAppVersion();
    stdout.writeln('camilla ' + version);
    exit(0);
  }

  rootDirContainsLangDirs = argResults['baseDirContainsLanguageDirs'];
  if (rootDirContainsLangDirs) {
    rootDirs = FileHandler.getRootDirs(Directory.current);
  }

  baseUrl = argResults['baseUrl'];
  if (baseUrl == null) {
    stdout.writeln('Option --baseUrl is mandatory');
    exit(1);
  }

  builder.processing('xml', 'version="1.0"');
  builder.element('urlset', nest: () {
    builder.attribute('xmlns', 'http://www.sitemaps.org/schemas/sitemap/0.9');
    builder.attribute('xmlns:xhtml', 'http://www.w3.org/1999/xhtml');
    addUrl();
  });

  final xmlDoc = builder.buildDocument();
  var xmlDocContents = xmlDoc.toXmlString(pretty: true);

  var siteMapFile = File('sitemap.xml');
  siteMapFile.writeAsStringSync(xmlDocContents);

  var stopwatchElapsed = stopwatch.elapsedMilliseconds;
  print('camilla finished in ${(stopwatchElapsed / 1000).toString()} s.');
  var resultStr = 'sitemap.xml with ' + numberOfHtmlFiles.toString() + ' pages';
  if (rootDirContainsLangDirs) {
    resultStr = resultStr + ' in ' + rootDirs.length.toString() + ' languages';
  }
  resultStr = resultStr + ' created';
  print(resultStr);
}

void addUrl() {
  var allHtmlFiles = collectAllPages();
  numberOfHtmlFiles = allHtmlFiles.length;
  for (var htmlFile in allHtmlFiles) {
    builder.element('url', nest: () {
      addLoc(htmlFile.fileName);
      addLastmod(htmlFile.lastModified);
      if (rootDirContainsLangDirs) {
        for (var rootDir in rootDirs) {
          if (htmlFile.fileName.contains('/')) {
            var htmlFileNameWithoutFirstDir =
                htmlFile.fileName.substring(htmlFile.fileName.indexOf('/') + 1);
            var htmlFileName = rootDir + '/' + htmlFileNameWithoutFirstDir;
            addXhtmlLink(rootDir, htmlFileName);
          }
        }
      }
    });
  }
}

void addLoc(pageName) {
  builder.element('loc', nest: () {
    builder.text(baseUrl + '/' + pageName);
  });
}

void addLastmod(lastModDateTime) {
  var formatter = DateFormat('yyyy-MM-dd');
  var formatted = formatter.format(lastModDateTime);

  builder.element('lastmod', nest: () {
    builder.text(formatted);
  });
}

void addXhtmlLink(hreflang, pathName) {
  builder.element('xhtml:link ', nest: () {
    builder.attribute('rel', 'alternate');
    builder.attribute('hreflang', hreflang);
    builder.attribute('href', baseUrl + '/' + pathName);
  });
}

List<HtmlFile> collectAllPages() {
  var allHtmlFiles = FileHandler.getAllHtmlFiles(Directory.current);
  return allHtmlFiles;
}

String getAppVersion() {
  return '1.0.0';
}
