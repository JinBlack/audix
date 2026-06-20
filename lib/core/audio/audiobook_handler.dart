import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

/// A chapter boundary used for in-player navigation and current-chapter display.
class ChapterMark {
  const ChapterMark({
    required this.startMs,
    required this.endMs,
    required this.title,
  });

  final int startMs;
  final int endMs;
  final String title;
}

/// Hosts a [just_audio] player inside an [audio_service] handler so playback
/// continues in the background and is controllable from the lock screen,
/// notification, and headset buttons.
class AudiobookHandler extends BaseAudioHandler with SeekHandler {
  AudiobookHandler._() {
    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object _, StackTrace _) {},
    );
    _player.positionStream.listen(_onPosition);
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _player.pause();
      }
    });
    _initSession();
  }

  /// Initialises audio_service and returns the singleton handler.
  static Future<AudiobookHandler> init() {
    return AudioService.init(
      builder: () => AudiobookHandler._(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.audix.audix.audio',
        androidNotificationChannelName: 'Playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        fastForwardInterval: Duration(seconds: 30),
        rewindInterval: Duration(seconds: 30),
      ),
    );
  }

  final AudioPlayer _player = AudioPlayer();
  final BehaviorSubject<int> _chapterIndex = BehaviorSubject<int>.seeded(0);
  List<ChapterMark> _chapters = const [];

  // ------------------------------------------------------------- accessors
  bool get playing => _player.playing;
  Duration get position => _player.position;
  double get speed => _player.speed;
  int get currentChapter => _chapterIndex.value;
  List<ChapterMark> get chapters => _chapters;

  Stream<bool> get playingStream => _player.playingStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<int> get chapterIndexStream => _chapterIndex.stream;

  // --------------------------------------------------------------- session
  Future<void> _initSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    // Pause when headphones/earbuds are removed, so audio does not suddenly
    // blast out of the phone speaker.
    session.becomingNoisyEventStream.listen((_) {
      if (_player.playing) pause();
    });
  }

  // --------------------------------------------------------------- loading
  Future<void> loadBook({
    required String id,
    required String filePath,
    required String title,
    String? author,
    String? artPath,
    required int durationMs,
    required List<ChapterMark> chapters,
    int initialPositionMs = 0,
    double speed = 1.0,
  }) async {
    _chapters = chapters;
    _chapterIndex.add(0);
    mediaItem.add(MediaItem(
      id: id,
      title: title,
      artist: author,
      duration: Duration(milliseconds: durationMs),
      artUri: artPath != null ? Uri.file(artPath) : null,
      displaySubtitle: chapters.isNotEmpty ? chapters.first.title : null,
    ));
    await _player.setAudioSource(
      AudioSource.file(filePath),
      initialPosition: Duration(milliseconds: initialPositionMs),
    );
    await _player.setSpeed(speed);
  }

  // -------------------------------------------------------------- chapters
  /// Index of the last chapter whose start is at or before [ms] (binary search).
  int _chapterAt(int ms) {
    if (_chapters.isEmpty) return 0;
    var lo = 0;
    var hi = _chapters.length - 1;
    var ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_chapters[mid].startMs <= ms) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  void _onPosition(Duration pos) {
    if (_chapters.isEmpty) return;
    final idx = _chapterAt(pos.inMilliseconds);
    if (idx != _chapterIndex.value) {
      _chapterIndex.add(idx);
      final current = mediaItem.value;
      if (current != null && idx >= 0 && idx < _chapters.length) {
        mediaItem.add(current.copyWith(displaySubtitle: _chapters[idx].title));
      }
    }
  }

  // -------------------------------------------------------------- controls
  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  /// Headset "next track" / next-chapter button.
  @override
  Future<void> skipToNext() async {
    final next = _chapterIndex.value + 1;
    if (next < _chapters.length) {
      await seek(Duration(milliseconds: _chapters[next].startMs));
    }
  }

  /// Headset "previous track" button: restart the current chapter, or jump to
  /// the previous one when already near its start.
  @override
  Future<void> skipToPrevious() async {
    final i = _chapterIndex.value;
    final posMs = _player.position.inMilliseconds;
    if (i >= 0 && i < _chapters.length && posMs - _chapters[i].startMs > 3000) {
      await seek(Duration(milliseconds: _chapters[i].startMs));
    } else if (i - 1 >= 0) {
      await seek(Duration(milliseconds: _chapters[i - 1].startMs));
    } else {
      await seek(Duration.zero);
    }
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.rewind,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.fastForward,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [1, 2, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    ));
  }
}
