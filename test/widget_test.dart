import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:audix/app.dart';
import 'package:audix/core/audio/audio_providers.dart';
import 'package:audix/core/database/database.dart';
import 'package:audix/core/providers.dart';

void main() {
  testWidgets('App boots to an empty Library', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          booksProvider.overrideWith((ref) => Stream.value(const <Book>[])),
          continueListeningProvider
              .overrideWith((ref) => Stream.value(const <Book>[])),
          serversProvider.overrideWith((ref) => Stream.value(const <Server>[])),
          mediaItemProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: const AudixApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Library'), findsWidgets);
    expect(find.text('No audiobooks yet'), findsOneWidget);
  });
}
