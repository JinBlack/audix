/// Formats a [Duration] as `h:mm:ss` (or `m:ss` when under an hour).
String formatDuration(Duration d) {
  final negative = d.isNegative;
  d = d.abs();
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  final seconds = d.inSeconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  final text = hours > 0 ? '$hours:$mm:$ss' : '$minutes:$ss';
  return negative ? '-$text' : text;
}
