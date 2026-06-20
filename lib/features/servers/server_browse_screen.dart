import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/remote/remote_providers.dart';
import '../../core/remote/remote_source.dart';

class ServerBrowseScreen extends ConsumerWidget {
  const ServerBrowseScreen({
    super.key,
    required this.server,
    this.path,
    this.title,
  });

  final Server server;

  /// Current folder URL. Defaults to the server's base URL.
  final String? path;

  /// Folder name shown in the app bar (and used as the downloaded book title).
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = path ?? server.baseUrl;
    final listing = ref.watch(remoteListingProvider((server.id, url)));
    final downloads = ref.watch(downloadsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(title ?? server.name)),
      body: listing.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ListingError(
          message: '$e',
          onRetry: () =>
              ref.invalidate(remoteListingProvider((server.id, url))),
        ),
        data: (entries) {
          final m4b = _firstMatch(
              entries, (e) => !e.isDir && e.name.toLowerCase().endsWith('.m4b'));
          final cue = _firstMatch(
              entries, (e) => !e.isDir && e.name.toLowerCase().endsWith('.cue'));
          final dirs = entries.where((e) => e.isDir).toList();

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(remoteListingProvider((server.id, url))),
            child: ListView(
              children: [
                if (m4b != null)
                  _DownloadBanner(
                    folderName: title ?? server.name,
                    progress: downloads[url],
                    onDownload: () => _download(context, ref, url, m4b, cue),
                  ),
                for (final dir in dirs)
                  ListTile(
                    leading: const Icon(Icons.folder),
                    title: Text(dir.name),
                    trailing: downloads.containsKey(dir.url.toString())
                        ? _MiniProgress(value: downloads[dir.url.toString()]!)
                        : const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ServerBrowseScreen(
                          server: server,
                          path: dir.url.toString(),
                          title: dir.name,
                        ),
                      ),
                    ),
                  ),
                if (entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('This folder is empty')),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _download(BuildContext context, WidgetRef ref, String url,
      RemoteEntry m4b, RemoteEntry? cue) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(downloadsProvider.notifier).downloadBookAt(
            server: server,
            folderName: title ?? server.name,
            folderKey: url,
            m4b: m4b,
            cue: cue,
          );
      messenger.showSnackBar(
        const SnackBar(content: Text('Downloaded to library')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }
}

RemoteEntry? _firstMatch(
    List<RemoteEntry> entries, bool Function(RemoteEntry) test) {
  for (final entry in entries) {
    if (test(entry)) return entry;
  }
  return null;
}

class _DownloadBanner extends StatelessWidget {
  const _DownloadBanner({
    required this.folderName,
    required this.progress,
    required this.onDownload,
  });

  final String folderName;
  final double? progress;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.menu_book),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    folderName,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (progress != null) ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text('Downloading… ${(progress! * 100).round()}%'),
            ] else
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniProgress extends StatelessWidget {
  const _MiniProgress({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(value: value, strokeWidth: 2),
    );
  }
}

class _ListingError extends StatelessWidget {
  const _ListingError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 56),
            const SizedBox(height: 16),
            const Text(
              "Couldn't load this folder",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            const Text(
              'Check the URL and credentials (a 401 means wrong username or '
              'password).',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
