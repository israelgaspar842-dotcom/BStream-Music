import 'lyric_word.dart';

class LyricLine {
  const LyricLine({
    required this.timestamp,
    required this.text,
    this.words = const [],
  });

  final Duration timestamp;
  final String text;
  final List<LyricWord> words;

  /// Invalid or incomplete timing must never replace the line fallback.
  bool get hasWordTiming {
    if (words.isEmpty) return false;
    var previousOffset = 0;
    var previousStart = timestamp;
    for (final word in words) {
      if (word.text.trim().isEmpty ||
          word.start < Duration.zero ||
          word.start < timestamp ||
          word.start < previousStart ||
          word.end <= word.start ||
          word.startOffset < previousOffset ||
          word.endOffset <= word.startOffset ||
          word.endOffset > text.length ||
          _meaningfulText.hasMatch(
            text.substring(previousOffset, word.startOffset),
          ) ||
          text.substring(word.startOffset, word.endOffset) != word.text) {
        return false;
      }
      previousOffset = word.endOffset;
      previousStart = word.start;
    }
    return !_meaningfulText.hasMatch(text.substring(previousOffset));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LyricLine &&
            runtimeType == other.runtimeType &&
            timestamp == other.timestamp &&
            text == other.text &&
            _wordsEqual(words, other.words);
  }

  @override
  int get hashCode => Object.hash(timestamp, text, Object.hashAll(words));

  @override
  String toString() => 'LyricLine($timestamp, $text)';
}

final _meaningfulText = RegExp(r'[\p{L}\p{N}]', unicode: true);

bool _wordsEqual(List<LyricWord> left, List<LyricWord> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
