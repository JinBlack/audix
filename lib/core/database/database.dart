import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// How a server exposes its audiobook folders. Stored as the enum index.
enum ServerType { autoindex, webdav, json }

@DataClassName('Server')
class Servers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get baseUrl => text()();
  TextColumn get username => text().withDefault(const Constant(''))();
  IntColumn get type => intEnum<ServerType>().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Book')
class Books extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Source server, or null for a book imported from the device / detached.
  IntColumn get serverId => integer().nullable()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();

  /// Paths are RELATIVE to the app documents directory (see FilePaths).
  TextColumn get m4bPath => text()();
  TextColumn get cuePath => text().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  TextColumn get coverPath => text().nullable()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Chapter')
class Chapters extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get chapterIndex => integer()();
  TextColumn get title => text()();
  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();
}

@DataClassName('PlaybackProgress')
class Playback extends Table {
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  IntColumn get currentChapter => integer().withDefault(const Constant(0))();
  RealColumn get speed => real().withDefault(const Constant(1.0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {bookId};
}

@DriftDatabase(tables: [Servers, Books, Chapters, Playback])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'audix'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          // Required so KeyAction.cascade foreign keys are enforced.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  // ---------------------------------------------------------------- Servers
  Stream<List<Server>> watchServers() =>
      (select(servers)..orderBy([(s) => OrderingTerm(expression: s.name)]))
          .watch();

  Future<List<Server>> allServers() => select(servers).get();

  Future<Server?> serverById(int id) =>
      (select(servers)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<int> insertServer(ServersCompanion server) =>
      into(servers).insert(server);

  Future<bool> updateServer(Server server) => update(servers).replace(server);

  /// Removes a server. Downloaded books are kept (their [serverId] is cleared)
  /// so they remain available in the local library.
  Future<void> deleteServer(int id) async {
    await (update(books)..where((b) => b.serverId.equals(id)))
        .write(const BooksCompanion(serverId: Value(null)));
    await (delete(servers)..where((s) => s.id.equals(id))).go();
  }

  // ------------------------------------------------------------------ Books
  Stream<List<Book>> watchBooks() =>
      (select(books)..orderBy([(b) => OrderingTerm.desc(b.addedAt)])).watch();

  Future<Book?> bookById(int id) =>
      (select(books)..where((b) => b.id.equals(id))).getSingleOrNull();

  Future<int> insertBook(BooksCompanion book) => into(books).insert(book);

  Future<bool> updateBook(Book book) => update(books).replace(book);

  Future<void> deleteBook(int id) =>
      (delete(books)..where((b) => b.id.equals(id))).go();

  /// Books that have a saved position, most-recently-played first.
  Stream<List<Book>> watchContinueListening() {
    final query = select(books).join(
      [innerJoin(playback, playback.bookId.equalsExp(books.id))],
    )
      ..where(books.completed.equals(false))
      ..orderBy([OrderingTerm.desc(playback.updatedAt)]);
    return query
        .watch()
        .map((rows) => rows.map((r) => r.readTable(books)).toList());
  }

  // --------------------------------------------------------------- Chapters
  Future<void> insertChapters(List<ChaptersCompanion> rows) =>
      batch((b) => b.insertAll(chapters, rows));

  Future<List<Chapter>> chaptersFor(int bookId) => (select(chapters)
        ..where((c) => c.bookId.equals(bookId))
        ..orderBy([(c) => OrderingTerm(expression: c.chapterIndex)]))
      .get();

  // --------------------------------------------------------------- Playback
  Future<PlaybackProgress?> playbackFor(int bookId) =>
      (select(playback)..where((p) => p.bookId.equals(bookId)))
          .getSingleOrNull();

  Future<void> savePosition(
    int bookId, {
    required int positionMs,
    required int chapterIndex,
    double? speed,
    bool? completed,
  }) async {
    await into(playback).insertOnConflictUpdate(
      PlaybackCompanion.insert(
        bookId: Value(bookId),
        positionMs: Value(positionMs),
        currentChapter: Value(chapterIndex),
        speed: speed == null ? const Value.absent() : Value(speed),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (completed != null) {
      await (update(books)..where((b) => b.id.equals(bookId)))
          .write(BooksCompanion(completed: Value(completed)));
    }
  }

  /// Fills in a book's file paths, metadata, and duration after import/download.
  Future<void> finalizeImportedBook(
    int id, {
    required String m4bPath,
    String? cuePath,
    String? author,
    required String title,
    required int durationMs,
  }) {
    return (update(books)..where((b) => b.id.equals(id))).write(BooksCompanion(
      m4bPath: Value(m4bPath),
      cuePath: Value(cuePath),
      author: Value(author),
      title: Value(title),
      durationMs: Value(durationMs),
    ));
  }
}
