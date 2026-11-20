/// A timed word or syllable within its parent line. Character offsets use
/// Dart/Flutter UTF-16 indices; timing is absolute in the song timeline.
class LyricWord {
  const LyricWord({
    required this.text,
    required this.start,
    required this.end,
    required this.startOffset,
    required this.endOffset,
  });

  final String text;
  final Duration start;
  final Duration end;
  final int startOffset;
  final int endOffset;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricWord &&
          text == other.text &&
          start == other.start &&
          end == other.end &&
          startOffset == other.startOffset &&
          endOffset == other.endOffset;

  @override
  int get hashCode => Object.hash(text, start, end, startOffset, endOffset);
}
