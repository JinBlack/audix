import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/providers.dart';

class ServerFormScreen extends ConsumerStatefulWidget {
  const ServerFormScreen({super.key, this.server});

  final Server? server;

  @override
  ConsumerState<ServerFormScreen> createState() => _ServerFormScreenState();
}

class _ServerFormScreenState extends ConsumerState<ServerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _username;
  final _password = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  bool get _isEdit => widget.server != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.server?.name ?? '');
    _url = TextEditingController(text: widget.server?.baseUrl ?? '');
    _username = TextEditingController(text: widget.server?.username ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showHttpWarning = _url.text.trim().toLowerCase().startsWith('http://');

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit server' : 'Add server')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://example.com/audiobooks/',
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final value = v?.trim() ?? '';
                final uri = Uri.tryParse(value);
                if (uri == null ||
                    !(uri.isScheme('http') || uri.isScheme('https')) ||
                    uri.host.isEmpty) {
                  return 'Enter a valid http(s) URL';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _username,
              decoration:
                  const InputDecoration(labelText: 'Username (optional)'),
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: _isEdit
                    ? 'Password (leave blank to keep)'
                    : 'Password (optional)',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (showHttpWarning) ...[
              const SizedBox(height: 16),
              const _HttpWarning(),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final db = ref.read(databaseProvider);
    final creds = ref.read(credentialsStoreProvider);
    final name = _name.text.trim();
    final username = _username.text.trim();
    var baseUrl = _url.text.trim();
    if (!baseUrl.endsWith('/')) baseUrl = '$baseUrl/';

    try {
      if (_isEdit) {
        await db.updateServer(widget.server!
            .copyWith(name: name, baseUrl: baseUrl, username: username));
        if (_password.text.isNotEmpty) {
          await creds.setPassword(widget.server!.id, _password.text);
        }
      } else {
        final id = await db.insertServer(ServersCompanion.insert(
          name: name,
          baseUrl: baseUrl,
          username: Value(username),
        ));
        if (_password.text.isNotEmpty) {
          await creds.setPassword(id, _password.text);
        }
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _HttpWarning extends StatelessWidget {
  const _HttpWarning();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_open, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'This server uses plain HTTP. Basic-auth credentials are only '
                'base64-encoded, not encrypted — anyone on the network can read '
                'them. Use HTTPS whenever possible.',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
