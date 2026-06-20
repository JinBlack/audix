import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import '../database/database.dart';

/// A folder or file discovered on a remote server.
class RemoteEntry {
  const RemoteEntry({
    required this.name,
    required this.isDir,
    required this.url,
    this.size,
  });

  final String name;
  final bool isDir;
  final Uri url;
  final int? size;
}

/// Lists the folders/files at a remote path. Implementations are pluggable so
/// new server protocols can be added without changing the browse/download UI.
abstract class RemoteSource {
  Future<List<RemoteEntry>> list(Uri path);
}

String basicAuthHeader(String username, String password) =>
    'Basic ${base64.encode(utf8.encode('$username:$password'))}';

/// Lists entries by parsing a standard HTTP directory-listing ("autoindex")
/// HTML page, as served by nginx, Apache, `rclone serve http`, etc.
class HttpAutoindexSource implements RemoteSource {
  HttpAutoindexSource({required this.dio, this.authHeader});

  final Dio dio;
  final String? authHeader;

  @override
  Future<List<RemoteEntry>> list(Uri path) async {
    final response = await dio.getUri<String>(
      path,
      options: Options(
        responseType: ResponseType.plain,
        headers: {if (authHeader != null) 'Authorization': authHeader},
      ),
    );

    final document = html_parser.parse(response.data ?? '');
    final entries = <RemoteEntry>[];
    final seen = <String>{};

    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'];
      if (href == null || href.isEmpty) continue;
      // Skip sort links, fragments, and parent/breadcrumb/absolute links.
      if (href.startsWith('?') ||
          href.startsWith('#') ||
          href.startsWith('/') ||
          href.contains('..')) {
        continue;
      }

      try {
        final resolved = path.resolve(href);
        if (resolved.host != path.host) continue;

        // pathSegments are already percent-decoded; do NOT decode again.
        final segments =
            resolved.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segments.isEmpty) continue;
        if (!seen.add(resolved.toString())) continue;

        entries.add(RemoteEntry(
          name: segments.last,
          isDir: href.endsWith('/'),
          url: resolved,
        ));
      } catch (_) {
        // Skip an entry with malformed percent-encoding rather than failing
        // the whole listing.
        continue;
      }
    }

    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }
}

/// Builds the right [RemoteSource] for a server. WebDAV and JSON-index sources
/// are not yet implemented and fall back to autoindex parsing.
RemoteSource createRemoteSource(Server server, String? password, {Dio? dio}) {
  final client = dio ?? Dio();
  final header = server.username.isEmpty
      ? null
      : basicAuthHeader(server.username, password ?? '');
  switch (server.type) {
    case ServerType.autoindex:
    case ServerType.webdav:
    case ServerType.json:
      return HttpAutoindexSource(dio: client, authHeader: header);
  }
}
