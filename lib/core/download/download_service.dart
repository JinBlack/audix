import 'package:background_downloader/background_downloader.dart';

import '../database/database.dart';
import '../remote/remote_source.dart';

/// Downloads a book's files (the `.m4b` and optional `.cue`) into the app's
/// storage using background_downloader, adding the server's basic-auth header.
class DownloadService {
  Future<void> downloadBook({
    required RemoteEntry m4b,
    RemoteEntry? cue,
    required Server server,
    required String? password,
    required int bookId,
    void Function(double progress)? onProgress,
  }) async {
    final headers = <String, String>{};
    if (server.username.isNotEmpty) {
      headers['Authorization'] =
          basicAuthHeader(server.username, password ?? '');
    }
    final directory = 'audiobooks/$bookId';

    final m4bTask = DownloadTask(
      url: m4b.url.toString(),
      filename: 'audio.m4b',
      directory: directory,
      baseDirectory: BaseDirectory.applicationDocuments,
      headers: headers,
      updates: Updates.statusAndProgress,
      allowPause: true,
    );
    final result = await FileDownloader().download(
      m4bTask,
      onProgress: (progress) {
        if (progress >= 0) onProgress?.call(progress);
      },
    );
    if (result.status != TaskStatus.complete) {
      throw Exception('Audio download ${result.status.name}');
    }

    if (cue != null) {
      final cueTask = DownloadTask(
        url: cue.url.toString(),
        filename: 'index.cue',
        directory: directory,
        baseDirectory: BaseDirectory.applicationDocuments,
        headers: headers,
      );
      await FileDownloader().download(cueTask);
    }
  }
}
