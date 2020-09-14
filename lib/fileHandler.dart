import 'dart:io';
import 'package:path/path.dart' as path;

class HtmlFile {
  String fileName;
  DateTime lastModified;

  HtmlFile(String fileName, DateTime lastModified) {
    this.fileName = fileName;
    this.lastModified = lastModified;
  }
}

class FileHandler {
  static List<String> getRootDirs(Directory source) {
    var output = <String>[];
    source.listSync(recursive: false).forEach((var entity) {
      if (entity is Directory) {
        output.add(path.basename(entity.path));
      }
    });

    return output;
  }

  static List<HtmlFile> getAllHtmlFiles(Directory source) {
    var output = <HtmlFile>[];
    source.listSync(recursive: true).forEach((var entity) {
      if (entity is File && entity.path.endsWith('.html')) {
        var htmlFile = HtmlFile(
            getRelativeFilePath(entity.path), entity.lastModifiedSync());
        output.add(htmlFile);
      }
    });

    return output;
  }

  //when given a file path, the relative file path to current working
  //directory is returned.
  static String getRelativeFilePath(filePath) {
    var currentDirPath = Directory.current.path;
    return filePath
        .toString()
        .replaceFirst(currentDirPath + Platform.pathSeparator, '');
  }
}
