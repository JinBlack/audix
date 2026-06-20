import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../download/download_service.dart';
import '../providers.dart';
import '../storage/file_paths.dart';
import 'remote_source.dart';

final downloadServiceProvider =
    Provider<DownloadService>((ref) => DownloadService());

/// Lists a server path. Keyed by `(serverId, url)` so navigating folders and
/// refreshing are cheap and cache-friendly.
final remoteListingProvider = FutureProvider.autoDispose
    .family<List<RemoteEntry>, (int, String)>((ref, args) async {
  final (serverId, url) = args;
  final db = ref.read(databaseProvider);
  final server = await db.serverById(serverId);
  if (server == null) return const [];
  final password =
      await ref.read(credentialsStoreProvider).getPassword(serverId);
  final source = createRemoteSource(server, password);
  return source.list(Uri.parse(url));
});

/// Tracks active downloads as `folderKey -> progress` (0..1).
final downloadsProvider =
    NotifierProvider<DownloadsNotifier, Map<String, double>>(
  DownloadsNotifier.new,
);

class DownloadsNotifier extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => {};

  bool isDownloading(String key) => state.containsKey(key);

  /// Creates a book row for [folderName], downloads its files with progress,
  /// then finalizes metadata + chapters. Cleans up on failure.
  Future<void> downloadBookAt({
    required Server server,
    required String folderName,
    required String folderKey,
    required RemoteEntry m4b,
    RemoteEntry? cue,
  }) async {
    if (state.containsKey(folderKey)) return;
    state = {...state, folderKey: 0};

    final db = ref.read(databaseProvider);
    final password =
        await ref.read(credentialsStoreProvider).getPassword(server.id);
    final id = await db.insertBook(BooksCompanion.insert(
      title: folderName,
      m4bPath: '',
      serverId: Value(server.id),
    ));

    try {
      await ref.read(downloadServiceProvider).downloadBook(
            m4b: m4b,
            cue: cue,
            server: server,
            password: password,
            bookId: id,
            onProgress: (p) => state = {...state, folderKey: p},
          );
      await ref
          .read(bookFinalizerProvider)
          .finalize(id, fallbackTitle: folderName, hasCue: cue != null);
    } catch (e) {
      await db.deleteBook(id);
      await FilePaths.deleteBookDir(id);
      state = {...state}..remove(folderKey);
      rethrow;
    }
    state = {...state}..remove(folderKey);
  }
}
