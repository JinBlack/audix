import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/settings/settings_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookCount = ref.watch(libraryEntriesProvider).value?.length ?? 0;
    final servers = ref.watch(serversProvider).value ?? const [];
    final settings = ref.watch(settingsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _Header('Playback'),
          ListTile(
            leading: const Icon(Icons.fast_forward),
            title: const Text('Skip interval'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final s in const [10, 15, 30, 60])
                    ChoiceChip(
                      label: Text('${s}s'),
                      selected: settings.skipSeconds == s,
                      onSelected: (_) =>
                          ref.read(settingsProvider.notifier).setSkipSeconds(s),
                    ),
                ],
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.replay),
            title: const Text('Rewind on resume'),
            subtitle: const Text('Skip back a few seconds when you resume'),
            value: settings.smartResume,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setSmartResume(v),
          ),
          const Divider(),
          const _Header('Library'),
          ListTile(
            leading: const Icon(Icons.library_books),
            title: const Text('Books'),
            trailing: Text('$bookCount'),
          ),
          ListTile(
            leading: const Icon(Icons.dns),
            title: const Text('Servers'),
            trailing: Text('${servers.length}'),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Fetch missing covers'),
            subtitle: const Text('Extract cover art for books that have none'),
            onTap: () => _fetchCovers(context, ref),
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
            applicationVersion: '1.2.0',
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

  Future<void> _fetchCovers(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Fetching covers…')));
    final added = await ref.read(bookFinalizerProvider).backfillCovers();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          added == 0 ? 'No new covers found' : 'Added $added cover(s)',
        ),
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
