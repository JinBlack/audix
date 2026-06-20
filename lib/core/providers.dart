import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database/database.dart';
import 'import/local_import.dart';
import 'library/book_finalizer.dart';
import 'storage/credentials_store.dart';

/// Single app-wide drift database instance.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Secure store for server passwords.
final credentialsStoreProvider =
    Provider<CredentialsStore>((ref) => CredentialsStore());

/// All books, most recently added first.
final booksProvider = StreamProvider<List<Book>>(
  (ref) => ref.watch(databaseProvider).watchBooks(),
);

/// Books with saved progress, most recently played first.
final continueListeningProvider = StreamProvider<List<Book>>(
  (ref) => ref.watch(databaseProvider).watchContinueListening(),
);

/// Configured servers, ordered by name.
final serversProvider = StreamProvider<List<Server>>(
  (ref) => ref.watch(databaseProvider).watchServers(),
);

final bookFinalizerProvider = Provider<BookFinalizer>(
  (ref) => BookFinalizer(ref.watch(databaseProvider)),
);

final localImporterProvider = Provider<LocalImporter>(
  (ref) => LocalImporter(
    ref.watch(databaseProvider),
    ref.watch(bookFinalizerProvider),
  ),
);
