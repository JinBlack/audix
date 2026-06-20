import 'package:flutter_test/flutter_test.dart';

import 'package:audix/core/cue/cue_parser.dart';

void main() {
  group('CueParser.parse', () {
    const sample = '''
PERFORMER "Jane Author"
TITLE "The Great Book"
FILE "book.m4b" WAVE
  TRACK 01 AUDIO
    TITLE "Introduction"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Chapter One"
    INDEX 01 00:30:37
  TRACK 03 AUDIO
    TITLE "Chapter Two"
    INDEX 01 10:15:00
''';

    test('reads sheet-level metadata', () {
      final sheet = CueParser.parse(sample);
      expect(sheet.title, 'The Great Book');
      expect(sheet.performer, 'Jane Author');
      expect(sheet.file, 'book.m4b');
      expect(sheet.tracks, hasLength(3));
    });

    test('converts MM:SS:FF (75 frames/sec) to milliseconds', () {
      final sheet = CueParser.parse(sample);
      expect(sheet.tracks[0].startMs, 0);
      // 30s + 37 frames = 30000 + round(37 * 1000 / 75) = 30000 + 493 = 30493.
      expect(sheet.tracks[1].startMs, 30493);
      // 10m15s exactly = 615s = 615000ms.
      expect(sheet.tracks[2].startMs, 615000);
      expect(sheet.tracks[1].title, 'Chapter One');
    });

    test('handles minutes beyond 59', () {
      final sheet = CueParser.parse('''
TRACK 01 AUDIO
  TITLE "Long"
  INDEX 01 123:04:00
''');
      // 123m4s = 7384s = 7384000ms.
      expect(sheet.tracks.single.startMs, 7384000);
    });

    test('prefers INDEX 01 over INDEX 00 pregap', () {
      final sheet = CueParser.parse('''
TRACK 01 AUDIO
  TITLE "A"
  INDEX 00 00:00:00
  INDEX 01 00:02:30
''');
      // 2s + 30 frames = 2000 + 400 = 2400ms.
      expect(sheet.tracks.single.startMs, 2400);
    });

    test('falls back to a default title when a track has none', () {
      final sheet = CueParser.parse('''
TRACK 01 AUDIO
  INDEX 01 00:00:00
''');
      expect(sheet.tracks.single.title, 'Chapter 1');
    });

    test('tolerates unquoted titles', () {
      final sheet = CueParser.parse('''
TITLE Plain Title
TRACK 01 AUDIO
  TITLE First
  INDEX 01 00:00:00
''');
      expect(sheet.title, 'Plain Title');
      expect(sheet.tracks.single.title, 'First');
    });
  });

  group('chaptersFromCue', () {
    test('computes endMs from the next chapter / duration', () {
      final sheet = CueParser.parse('''
TRACK 01 AUDIO
  TITLE "One"
  INDEX 01 00:00:00
TRACK 02 AUDIO
  TITLE "Two"
  INDEX 01 00:30:37
TRACK 03 AUDIO
  TITLE "Three"
  INDEX 01 10:15:00
''');
      final chapters = chaptersFromCue(sheet, durationMs: 700000);
      expect(chapters, hasLength(3));
      expect(chapters[0].startMs, 0);
      expect(chapters[0].endMs, 30493);
      expect(chapters[1].startMs, 30493);
      expect(chapters[1].endMs, 615000);
      expect(chapters[2].startMs, 615000);
      expect(chapters[2].endMs, 700000);
      expect(chapters[2].index, 2);
    });

    test('returns a single spanning chapter when there are no tracks', () {
      final sheet = CueParser.parse('TITLE "Solo"\nFILE "x.m4b" WAVE\n');
      final chapters = chaptersFromCue(sheet, durationMs: 5000);
      expect(chapters, hasLength(1));
      expect(chapters.single.title, 'Solo');
      expect(chapters.single.startMs, 0);
      expect(chapters.single.endMs, 5000);
    });
  });

  group('singleChapter', () {
    test('spans the whole book', () {
      final chapters = singleChapter(durationMs: 12345, title: 'My Book');
      expect(chapters.single.startMs, 0);
      expect(chapters.single.endMs, 12345);
      expect(chapters.single.title, 'My Book');
    });
  });
}
