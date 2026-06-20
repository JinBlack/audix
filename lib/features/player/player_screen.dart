import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_providers.dart';
import '../../core/database/database.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/util/format.dart';
import '../bookmarks/bookmarks_sheet.dart';

const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  double? _dragMs;
  ScaffoldMessengerState? _messenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    // Don't let the "Bookmark added" snackbar linger over other screens.
    _messenger?.clearSnackBars();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(playerControllerProvider);
    final mediaItem = ref.watch(mediaItemProvider).value;
    final state = ref.watch(playbackStateProvider).value;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final chapterIndex = ref.watch(chapterIndexProvider).value ?? 0;
    final chapters = ref.watch(currentChaptersProvider).value ?? const <Chapter>[];
    final sleepRemaining = ref.watch(sleepRemainingProvider).value;

    final playing = state?.playing ?? false;
    final speed = state?.speed ?? 1.0;
    final skip = ref.watch(settingsProvider).skipSeconds;
    final duration = mediaItem?.duration ?? Duration.zero;
    final maxMs = duration.inMilliseconds.toDouble();
    final sliderMs =
        (_dragMs ?? position.inMilliseconds.toDouble()).clamp(0.0, maxMs <= 0 ? 1.0 : maxMs);

    final chapterTitle = chapters.isNotEmpty && chapterIndex < chapters.length
        ? chapters[chapterIndex].title
        : mediaItem?.displaySubtitle;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Now Playing'),
        actions: [
          IconButton(
            tooltip: 'Bookmarks',
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: () => showBookmarksSheet(context),
          ),
          if (chapters.isNotEmpty)
            IconButton(
              tooltip: 'Chapters',
              icon: const Icon(Icons.list),
              onPressed: () => _showChapters(context, chapters, chapterIndex),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Expanded(child: _Cover(artUri: mediaItem?.artUri)),
              const SizedBox(height: 24),
              Text(
                mediaItem?.title ?? 'No book loaded',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (mediaItem?.artist != null) ...[
                const SizedBox(height: 4),
                Text(
                  mediaItem!.artist!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 12),
              if (chapters.isNotEmpty)
                Text(
                  'Chapter ${chapterIndex + 1} of ${chapters.length}'
                  '${chapterTitle != null ? '  •  $chapterTitle' : ''}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 8),
              Slider(
                value: sliderMs,
                max: maxMs <= 0 ? 1.0 : maxMs,
                onChanged: maxMs <= 0
                    ? null
                    : (v) => setState(() => _dragMs = v),
                onChangeEnd: maxMs <= 0
                    ? null
                    : (v) {
                        controller.seek(Duration(milliseconds: v.round()));
                        setState(() => _dragMs = null);
                      },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatDuration(Duration(milliseconds: sliderMs.round()))),
                    Text(formatDuration(duration)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _Controls(
                playing: playing,
                skipSeconds: skip,
                onPrevChapter: chapters.isEmpty ? null : controller.previousChapter,
                onNextChapter: chapters.isEmpty ? null : controller.nextChapter,
                onRewind: controller.skipBackward,
                onForward: controller.skipForward,
                onToggle: controller.togglePlayPause,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.speed),
                    label: Text('${_trim(speed)}x'),
                    onPressed: () => _showSpeed(context, controller, speed),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Bookmark'),
                    onPressed: () => _addBookmark(context, controller),
                  ),
                  TextButton.icon(
                    icon: Icon(
                      sleepRemaining != null
                          ? Icons.bedtime
                          : Icons.bedtime_outlined,
                    ),
                    label: Text(
                      sleepRemaining != null
                          ? formatDuration(sleepRemaining)
                          : 'Sleep',
                    ),
                    onPressed: () => _showSleep(context, controller, sleepRemaining != null),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(1) : v.toString();

  void _showChapters(BuildContext context, List<Chapter> chapters, int current) {
    final controller = ref.read(playerControllerProvider);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView.builder(
        itemCount: chapters.length,
        itemBuilder: (context, i) {
          final c = chapters[i];
          return ListTile(
            selected: i == current,
            leading: CircleAvatar(child: Text('${i + 1}')),
            title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text(formatDuration(Duration(milliseconds: c.startMs))),
            onTap: () {
              controller.seek(Duration(milliseconds: c.startMs));
              Navigator.pop(context);
            },
          );
        },
      ),
    );
  }

  void _showSpeed(BuildContext context, PlayerController controller, double current) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Playback speed')),
              for (final s in _speeds)
                ListTile(
                  title: Text('${_trim(s)}x'),
                  trailing: s == current ? const Icon(Icons.check) : null,
                  onTap: () {
                    controller.setSpeed(s);
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSleep(BuildContext context, PlayerController controller, bool active) {
    const minutes = [5, 10, 15, 30, 45, 60];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Sleep timer')),
              if (active)
                ListTile(
                  leading: const Icon(Icons.cancel),
                  title: const Text('Turn off'),
                  onTap: () {
                    controller.cancelSleepTimer();
                    Navigator.pop(context);
                  },
                ),
              for (final m in minutes)
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text('$m minutes'),
                  onTap: () {
                    controller.startSleepTimer(Duration(minutes: m));
                    Navigator.pop(context);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('End of chapter'),
                onTap: () {
                  controller.startSleepTimerEndOfChapter();
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addBookmark(
      BuildContext context, PlayerController controller) async {
    final messenger = _messenger;
    final id = await controller.addBookmark();
    if (id == null || messenger == null || !mounted) return;
    messenger.clearSnackBars();
    final snackBar = messenger.showSnackBar(SnackBar(
      content: const Text('Bookmark added'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      action: SnackBarAction(
        label: 'Add note',
        onPressed: () {
          if (mounted) showBookmarkNoteDialog(context, ref, id, null);
        },
      ),
    ));
    // Some accessibility services keep snackbars open indefinitely; force-close.
    Future<void>.delayed(const Duration(seconds: 3), snackBar.close);
  }

}

class _Cover extends StatelessWidget {
  const _Cover({this.artUri});

  final Uri? artUri;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget placeholder() => Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.menu_book, size: 96, color: scheme.primary),
        );

    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: artUri != null && artUri!.isScheme('file')
              ? Image.file(
                  File.fromUri(artUri!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => placeholder(),
                )
              : placeholder(),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.playing,
    required this.skipSeconds,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onRewind,
    required this.onForward,
    required this.onToggle,
  });

  final bool playing;
  final int skipSeconds;
  final VoidCallback? onPrevChapter;
  final VoidCallback? onNextChapter;
  final VoidCallback onRewind;
  final VoidCallback onForward;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          iconSize: 32,
          icon: const Icon(Icons.skip_previous),
          tooltip: 'Previous chapter',
          onPressed: onPrevChapter,
        ),
        IconButton(
          iconSize: 36,
          icon: Icon(_rewindIcon(skipSeconds)),
          tooltip: 'Back ${skipSeconds}s',
          onPressed: onRewind,
        ),
        FilledButton(
          onPressed: onToggle,
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(20),
          ),
          child: Icon(playing ? Icons.pause : Icons.play_arrow, size: 36),
        ),
        IconButton(
          iconSize: 36,
          icon: Icon(_forwardIcon(skipSeconds)),
          tooltip: 'Forward ${skipSeconds}s',
          onPressed: onForward,
        ),
        IconButton(
          iconSize: 32,
          icon: const Icon(Icons.skip_next),
          tooltip: 'Next chapter',
          onPressed: onNextChapter,
        ),
      ],
    );
  }
}

IconData _rewindIcon(int s) => switch (s) {
      5 => Icons.replay_5,
      10 => Icons.replay_10,
      30 => Icons.replay_30,
      _ => Icons.replay,
    };

IconData _forwardIcon(int s) => switch (s) {
      5 => Icons.forward_5,
      10 => Icons.forward_10,
      30 => Icons.forward_30,
      _ => Icons.forward,
    };
