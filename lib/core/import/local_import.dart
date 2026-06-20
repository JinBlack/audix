import 'dart:io';

import 'package:path/path.dart' as p;

import '../database/database.dart';
import '../library/book_finalizer.dart';
import '../storage/file_paths.dart';

/// Imports an audiobook (an `.m4b` plus optional `.cue`) from device storage:
/// copies the files into the app's per-book folder, then finalizes metadata
/// and chapters via [BookFinalizer].
class LocalImporter {
  LocalImporter(this.db, this.finalizer);

  final AppDatabase db;
  final BookFinalizer finalizer;

  Future<int> importBook({
    required String m4bSourcePath,
    String? cueSourcePath,
  }) async {
    final fallbackTitle = p.basenameWithoutExtension(m4bSourcePath);

    // Insert first to obtain the id used for the storage folder name.
    final id = await db.insertBook(
      BooksCompanion.insert(title: fallbackTitle, m4bPath: ''),
    );

    final dir = await FilePaths.ensureBookDir(id);
    await File(m4bSourcePath).copy(p.join(dir.path, 'audio.m4b'));
    if (cueSourcePath != null) {
      await File(cueSourcePath).copy(p.join(dir.path, 'index.cue'));
    }

    await finalizer.finalize(
      id,
      fallbackTitle: fallbackTitle,
      hasCue: cueSourcePath != null,
    );
    return id;
  }
}
