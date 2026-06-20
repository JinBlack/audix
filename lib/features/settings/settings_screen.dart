import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(booksProvider).value ?? const [];
    final servers = ref.watch(serversProvider).value ?? const [];
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _Header('Library'),
          ListTile(
            leading: const Icon(Icons.library_books),
            title: const Text('Books'),
            trailing: Text('${books.length}'),
          ),
          ListTile(
            leading: const Icon(Icons.dns),
            title: const Text('Servers'),
            trailing: Text('${servers.length}'),
          ),
          const Divider(),
          const _Header('Security'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              color: scheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Server passwords are stored in the device keystore / keychain. '
                  'Prefer HTTPS servers: basic auth over plain HTTP is only '
                  'base64-encoded, not encrypted.',
                ),
              ),
            ),
          ),
          const Divider(),
          AboutListTile(
            icon: const Icon(Icons.info_outline),
            applicationName: 'Audix',
            applicationVersion: '1.0.0',
            applicationLegalese: 'Audiobook player with cue-based chapters.',
            aboutBoxChildren: const [
              SizedBox(height: 12),
              Text(
                'Local library, background playback, headset controls, and '
                'downloads from your own HTTP servers.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
