import 'dart:convert';

/// A single TRACK entry parsed from a `.cue` sheet.
class CueTrack {
  const CueTrack({
    required this.number,
    required this.title,
    required this.startMs,
  });

  final int number;
  final String title;
  final int startMs;
}

/// The parsed contents of a `.cue` sheet.
class CueSheet {
  const CueSheet({
    this.title,
    this.performer,
    this.file,
    required this.tracks,
  });

  /// Top-level album/book `TITLE`.
  final String? title;

  /// Top-level `PERFORMER` (typically the author/narrator).
  final String? performer;

  /// Referenced media `FILE` name (e.g. `book.m4b`).
  final String? file;

  final List<CueTrack> tracks;
}

/// A chapter with a resolved start/end, ready to store and seek to.
class CueChapter {
  const CueChapter({
    required this.index,
    required this.title,
    required this.startMs,
    required this.endMs,
  });

  /// Zero-based chapter index.
  final int index;
  final String title;
  final int startMs;
  final int endMs;
}

/// Parser for CUE sheets used to index audiobook chapters.
///
/// CUE timestamps are `MM:SS:FF` where `FF` is frames and there are **75
/// frames per second** (the CD-audio convention). `MM` is total minutes and
/// may exceed 59 for long audiobooks.
class CueParser {
  static final _trackRe = RegExp(r'^TRACK\s+(\d+)', caseSensitive: false);
  static final _indexRe =
      RegExp(r'^INDEX\s+(\d+)\s+(\d+):(\d+):(\d+)', caseSensitive: false);
  static final _titleRe = RegExp(r'^TITLE\s+(.*)$', caseSensitive: false);
  static final _performerRe =
      RegExp(r'^PERFORMER\s+(.*)$', caseSensitive: false);
  static final _fileRe = RegExp(r'^FILE\s+(.*)$', caseSensitive: false);

  static int _framesToMs(int mm, int ss, int ff) {
    final totalFrames = (mm * 60 + ss) * 75 + ff;
    return (totalFrames * 1000 / 75).round();
  }

  static String _unquote(String s) {
    final t = s.trim();
    if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
      return t.substring(1, t.length - 1);
    }
    return t;
  }

  static String _fileName(String s) {
    final t = s.trim();
    if (t.startsWith('"')) {
      final end = t.indexOf('"', 1);
      if (end > 0) return t.substring(1, end);
    }
    final space = t.indexOf(' ');
    return space > 0 ? t.substring(0, space) : t;
  }

  static CueSheet parse(String content) {
    String? sheetTitle;
    String? sheetPerformer;
    String? file;
    final tracks = <CueTrack>[];

    int? curNumber;
    String? curTitle;
    int? curStartMs;
    var sawIndex01 = false;

    void flush() {
      if (curNumber != null && curStartMs != null) {
        tracks.add(CueTrack(
          number: curNumber!,
          title: curTitle ?? 'Chapter $curNumber',
          startMs: curStartMs!,
        ));
      }
      curNumber = null;
      curTitle = null;
      curStartMs = null;
      sawIndex01 = false;
    }

    for (final raw in const LineSplitter().convert(content)) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      final track = _trackRe.firstMatch(line);
      if (track != null) {
        flush();
        curNumber = int.tryParse(track.group(1)!);
        continue;
      }

      final index = _indexRe.firstMatch(line);
      if (index != null && curNumber != null) {
        final indexNum = int.parse(index.group(1)!);
        final ms = _framesToMs(
          int.parse(index.group(2)!),
          int.parse(index.group(3)!),
          int.parse(index.group(4)!),
        );
        // Prefer INDEX 01 (track start). Only fall back to an earlier INDEX
        // (e.g. INDEX 00 pregap) if INDEX 01 has not been seen.
        if (!sawIndex01) curStartMs = ms;
        if (indexNum == 1) sawIndex01 = true;
        continue;
      }

      final title = _titleRe.firstMatch(line);
      if (title != null) {
        final value = _unquote(title.group(1)!);
        if (curNumber == null) {
          sheetTitle = value;
        } else {
          curTitle = value;
        }
        continue;
      }

      final performer = _performerRe.firstMatch(line);
      if (performer != null && curNumber == null) {
        sheetPerformer = _unquote(performer.group(1)!);
        continue;
      }

      final f = _fileRe.firstMatch(line);
      if (f != null && curNumber == null) {
        file = _fileName(f.group(1)!);
        continue;
      }
    }
    flush();

    return CueSheet(
      title: sheetTitle,
      performer: sheetPerformer,
      file: file,
      tracks: tracks,
    );
  }
}

/// Builds resolved chapters from a parsed [sheet]. Each chapter's `endMs` is
/// the next chapter's start (or [durationMs] for the last). When the sheet has
/// no tracks, returns a single chapter spanning the whole book.
List<CueChapter> chaptersFromCue(CueSheet sheet, {required int durationMs}) {
  if (sheet.tracks.isEmpty) {
    return [
      CueChapter(
        index: 0,
        title: sheet.title ?? 'Chapter 1',
        startMs: 0,
        endMs: durationMs,
      ),
    ];
  }

  final sorted = [...sheet.tracks]
    ..sort((a, b) => a.startMs.compareTo(b.startMs));

  return [
    for (var i = 0; i < sorted.length; i++)
      CueChapter(
        index: i,
        title: sorted[i].title,
        startMs: sorted[i].startMs,
        endMs: i + 1 < sorted.length
            ? sorted[i + 1].startMs
            : (durationMs > sorted[i].startMs ? durationMs : sorted[i].startMs),
      ),
  ];
}

/// A single chapter spanning the whole book, used when no cue file is present.
List<CueChapter> singleChapter({required int durationMs, required String title}) =>
    [CueChapter(index: 0, title: title, startMs: 0, endMs: durationMs)];
