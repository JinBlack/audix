import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../database/database.dart';
import '../providers.dart';
import '../storage/file_paths.dart';
import 'audiobook_handler.dart';

/// The app's audio handler. Overridden in `main()` with the initialised
/// instance returned by [AudiobookHandler.init].
final audioHandlerProvider = Provider<AudiobookHandler>(
  (ref) => throw UnimplementedError(
    'audioHandlerProvider must be overridden in main()',
  ),
);

final mediaItemProvider = StreamProvider<MediaItem?>(
  (ref) => ref.watch(audioHandlerProvider).mediaItem,
);

final playbackStateProvider = StreamProvider<PlaybackState>(
  (ref) => ref.watch(audioHandlerProvider).playbackState,
);

final positionProvider = StreamProvider<Duration>(
  (ref) => ref.watch(audioHandlerProvider).positionStream,
);

final chapterIndexProvider = StreamProvider<int>(
  (ref) => ref.watch(audioHandlerProvider).chapterIndexStream,
);

/// Id of the currently loaded book, derived from the active media item.
final currentBookIdProvider = Provider<int?>((ref) {
  final item = ref.watch(mediaItemProvider).value;
  if (item == null) return null;
  return int.tryParse(item.id);
});

/// The currently loaded book row (title/author/cover/duration).
final currentBookProvider = FutureProvider<Book?>((ref) async {
  final id = ref.watch(currentBookIdProvider);
  if (id == null) return null;
  return ref.watch(databaseProvider).bookById(id);
});

/// Chapters of the currently loaded book, ordered by index.
final currentChaptersProvider = FutureProvider<List<Chapter>>((ref) async {
  final id = ref.watch(currentBookIdProvider);
  if (id == null) return const [];
  return ref.watch(databaseProvider).chaptersFor(id);
});

/// Remaining time on the sleep timer, or null when it is off.
final sleepRemainingProvider = StreamProvider<Duration?>(
  (ref) => ref.watch(playerControllerProvider).sleepRemainingStream,
);

final playerControllerProvider = Provider<PlayerController>((ref) {
  final controller = PlayerController(
    handler: ref.watch(audioHandlerProvider),
    db: ref.watch(databaseProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// Orchestrates loading a book into the handler, restoring the saved position,
/// persisting playback progress, and the sleep timer.
class PlayerController {
  PlayerController({required this.handler, required this.db});

  final AudiobookHandler handler;
  final AppDatabase db;

  int? _bookId;
  int _durationMs = 0;
  Timer? _saveTimer;
  StreamSubscription<bool>? _playingSub;

  Timer? _sleepTimer;
  final BehaviorSubject<Duration?> _sleepRemaining =
      BehaviorSubject<Duration?>.seeded(null);

  int? get currentBookId => _bookId;
  Stream<Duration?> get sleepRemainingStream => _sleepRemaining.stream;

  /// Loads [book], seeking to its saved position (unless finished) and applying
  /// its saved speed, then begins autosaving progress.
  Future<void> openBook(Book book) async {
    await _saveNow();
    _bookId = book.id;
    _durationMs = book.durationMs;

    final rows = await db.chaptersFor(book.id);
    final marks = [
      for (final c in rows)
        ChapterMark(startMs: c.startMs, endMs: c.endMs, title: c.title),
    ];
    final saved = await db.playbackFor(book.id);
    final startMs = book.completed ? 0 : (saved?.positionMs ?? 0);
    final speed = saved?.speed ?? 1.0;

    final filePath = await FilePaths.absolutePath(book.m4bPath);
    String? artPath;
    if (book.coverPath != null) {
      artPath = await FilePaths.absolutePath(book.coverPath!);
    }

    await handler.loadBook(
      id: book.id.toString(),
      filePath: filePath,
      title: book.title,
      author: book.author,
      artPath: artPath,
      durationMs: book.durationMs,
      chapters: marks,
      initialPositionMs: startMs,
      speed: speed,
    );
    _startAutosave();
  }

  void _startAutosave() {
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (handler.playing) _saveNow();
    });
    _playingSub?.cancel();
    // Persist immediately whenever playback pauses or stops.
    _playingSub = handler.playingStream.listen((playing) {
      if (!playing) _saveNow();
    });
  }

  Future<void> _saveNow() async {
    final id = _bookId;
    if (id == null) return;
    final posMs = handler.position.inMilliseconds;
    final completed = _durationMs > 0 && posMs >= _durationMs - 5000;
    await db.savePosition(
      id,
      positionMs: posMs,
      chapterIndex: handler.currentChapter,
      speed: handler.speed,
      completed: completed ? true : null,
    );
  }

  Future<void> play() => handler.play();
  Future<void> pause() => handler.pause();
  Future<void> togglePlayPause() =>
      handler.playing ? handler.pause() : handler.play();
  Future<void> seek(Duration position) => handler.seek(position);
  Future<void> skipForward() => handler.fastForward();
  Future<void> skipBackward() => handler.rewind();
  Future<void> nextChapter() => handler.skipToNext();
  Future<void> previousChapter() => handler.skipToPrevious();

  Future<void> setSpeed(double speed) async {
    await handler.setSpeed(speed);
    await _saveNow();
  }

  // ------------------------------------------------------------ sleep timer
  void startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    var remaining = duration;
    _sleepRemaining.add(remaining);
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      remaining -= const Duration(seconds: 1);
      if (remaining <= Duration.zero) {
        t.cancel();
        _sleepRemaining.add(null);
        handler.pause();
      } else {
        _sleepRemaining.add(remaining);
      }
    });
  }

  /// Schedules a pause at the end of the current chapter.
  void startSleepTimerEndOfChapter() {
    final i = handler.currentChapter;
    final chapters = handler.chapters;
    if (i < 0 || i >= chapters.length) return;
    final remainingMs = chapters[i].endMs - handler.position.inMilliseconds;
    if (remainingMs <= 0) {
      handler.pause();
      return;
    }
    startSleepTimer(Duration(milliseconds: remainingMs));
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepRemaining.add(null);
  }

  Future<void> dispose() async {
    _saveTimer?.cancel();
    _sleepTimer?.cancel();
    await _playingSub?.cancel();
    await _saveNow();
    await _sleepRemaining.close();
  }
}
