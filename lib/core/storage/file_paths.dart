import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Downloaded / imported audiobook files live under
/// `<appDocuments>/audiobooks/<bookId>/`.
///
/// The database stores paths RELATIVE to the documents directory because the
/// absolute container path can change between launches (notably on iOS), which
/// would otherwise break resume + playback of previously stored books.
class FilePaths {
  static const String _booksDir = 'audiobooks';

  static Future<Directory> _docs() => getApplicationDocumentsDirectory();

  /// Ensures `<docs>/audiobooks/<bookId>/` exists and returns it.
  static Future<Directory> ensureBookDir(int bookId) async {
    final docs = await _docs();
    final dir = Directory(p.join(docs.path, _booksDir, '$bookId'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// A db-storable path (relative to documents) for a file in a book's folder.
  static String relativePath(int bookId, String filename) =>
      p.join(_booksDir, '$bookId', filename);

  /// Resolves a db-stored relative path to an absolute [File] for this run.
  static Future<File> resolve(String relativePath) async {
    final docs = await _docs();
    return File(p.join(docs.path, relativePath));
  }

  /// Resolves a db-stored relative path to an absolute path string.
  static Future<String> absolutePath(String relativePath) async {
    final docs = await _docs();
    return p.join(docs.path, relativePath);
  }

  /// Removes a book's entire folder (used when deleting a book).
  static Future<void> deleteBookDir(int bookId) async {
    final docs = await _docs();
    final dir = Directory(p.join(docs.path, _booksDir, '$bookId'));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
