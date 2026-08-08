import 'dart:io';
import 'package:path/path.dart' as path;

/// Represents an HTML file with its filename and last modification date.
class HtmlFile {
  String fileName = "";
  DateTime lastModified = DateTime.now();

  /// Creates a new HtmlFile instance.
  ///
  /// Args:
  ///   fileName: The name/path of the HTML file
  ///   lastModified: The last modification timestamp of the file
  HtmlFile(this.fileName, this.lastModified);
}

/// Handles file system operations for the sitemap generator.
class FileHandler {
  /// Gets all root-level directories in the specified source directory.
  /// Used primarily for multi-language support where each language has its own directory.
  ///
  /// Args:
  ///   source: The directory to scan for root-level directories
  ///
  /// Returns:
  ///   `List<String>`: Names of all root-level directories
  static List<String> getRootDirs(Directory source) {
    var output = <String>[];
    source.listSync(recursive: false).forEach((var entity) {
      if (entity is Directory) {
        output.add(path.basename(entity.path));
      }
    });

    return output;
  }

  /// Recursively collects all HTML files from the specified directory and its subdirectories.
  ///
  /// Args:
  ///   source: The directory to scan for HTML files
  ///
  /// Returns:
  ///   `List<HtmlFile>`: List of HtmlFile objects representing all found HTML files
  static List<HtmlFile> getAllHtmlFiles(Directory source) {
    var output = <HtmlFile>[];
    source.listSync(recursive: true).forEach((var entity) {
      if (entity is File &&
          (entity.path.endsWith('.html') || entity.path.endsWith('.htm'))) {
        var htmlFile = HtmlFile(
            getRelativeFilePath(entity.path), entity.lastModifiedSync());
        output.add(htmlFile);
      }
    });

    return output;
  }

  /// Converts an absolute file path to a sitemap path relative to the current working directory.
  ///
  /// Args:
  ///   filePath: The absolute file path to convert
  ///
  /// Returns:
  ///   String: The relative URL path from the current working directory to the file
  static String getRelativeFilePath(filePath) {
    final relativePath =
        path.relative(filePath.toString(), from: Directory.current.path);
    return normalizePathForSitemap(relativePath, path.context);
  }

  /// Converts a platform-specific relative path to a sitemap URL path.
  static String normalizePathForSitemap(
      String relativePath, path.Context pathContext) {
    return path.posix.joinAll(pathContext.split(relativePath));
  }
}
