import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/providers.dart';
import 'server_browse_screen.dart';
import 'server_form_screen.dart';

class ServersScreen extends ConsumerWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serversAsync = ref.watch(serversProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Servers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add server',
            onPressed: () => _openForm(context),
          ),
        ],
      ),
      body: serversAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (servers) {
          if (servers.isEmpty) {
            return _EmptyServers(onAdd: () => _openForm(context));
          }
          return ListView(
            children: [
              for (final server in servers)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.dns)),
                  title: Text(server.name),
                  subtitle: Text(server.baseUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') _openForm(context, server);
                      if (value == 'delete') {
                        _deleteServer(context, ref, server);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ServerBrowseScreen(server: server),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _openForm(BuildContext context, [Server? server]) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ServerFormScreen(server: server)),
    );
  }

  Future<void> _deleteServer(
      BuildContext context, WidgetRef ref, Server server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete server?'),
        content: Text(
          'Remove "${server.name}" and its saved credentials? '
          'Downloaded books stay in your library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(databaseProvider).deleteServer(server.id);
    await ref.read(credentialsStoreProvider).deletePassword(server.id);
  }
}

class _EmptyServers extends StatelessWidget {
  const _EmptyServers({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('No servers yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Add an HTTP server that hosts folders of .m4b + .cue files to '
              'browse and download audiobooks.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add server'),
            ),
          ],
        ),
      ),
    );
  }
}
