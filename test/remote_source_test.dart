import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:audix/core/remote/remote_source.dart';

/// Returns canned HTML for any request, so the autoindex parser can be tested
/// without a network.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.html);

  final String html;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      html,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/html'],
      },
    );
  }
}

void main() {
  test('basicAuthHeader base64-encodes user:password', () {
    expect(basicAuthHeader('user', 'pass'), 'Basic dXNlcjpwYXNz');
  });

  test('HttpAutoindexSource parses a directory listing', () async {
    const html = '''
<html><body>
<a href="?C=N;O=D">Name</a>
<a href="../">Parent Directory</a>
<a href="Book%20One/">Book One/</a>
<a href="Another%20Book/">Another Book/</a>
<a href="audio.m4b">audio.m4b</a>
<a href="index.cue">index.cue</a>
</body></html>
''';
    final dio = Dio()..httpClientAdapter = _FakeAdapter(html);
    final source = HttpAutoindexSource(dio: dio, authHeader: null);

    final entries = await source.list(Uri.parse('http://example.com/books/'));
    final names = entries.map((e) => e.name).toList();

    expect(names,
        containsAll(['Book One', 'Another Book', 'audio.m4b', 'index.cue']));
    // Sort links and parent/breadcrumb links are filtered out.
    expect(names, isNot(contains('Name')));
    expect(names, isNot(contains('books')));

    final bookOne = entries.firstWhere((e) => e.name == 'Book One');
    expect(bookOne.isDir, isTrue);
    expect(bookOne.url.toString(), 'http://example.com/books/Book%20One/');

    final audio = entries.firstWhere((e) => e.name == 'audio.m4b');
    expect(audio.isDir, isFalse);

    // Directories are listed before files.
    expect(entries.first.isDir, isTrue);
    expect(entries.last.isDir, isFalse);
  });

  test('parses names containing % and tolerates a malformed href', () async {
    const html = '''
<a href="Book%20100%25/">Book 100%/</a>
<a href="audiobook.m4b">audiobook.m4b</a>
<a href="bad%ZZ/">bad</a>
''';
    final dio = Dio()..httpClientAdapter = _FakeAdapter(html);
    final source = HttpAutoindexSource(dio: dio, authHeader: null);

    // Must not throw even though one href has invalid percent-encoding.
    final entries =
        await source.list(Uri.parse('http://example.com/audio-books/'));
    final names = entries.map((e) => e.name).toList();

    expect(names, contains('Book 100%'));
    expect(names, contains('audiobook.m4b'));
  });
}
