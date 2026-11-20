import '../../domain/entities/lyric_line.dart';
import '../../domain/entities/lyric_word.dart';

class LrcParser {
  const LrcParser();

  List<LyricLine> parse(String? source) {
    if (source == null || source.trim().isEmpty) {
      return const [];
    }

    final normalized = source
        .replaceFirst('\uFEFF', '')
        .replaceAll('\r\n', '\n');
    final rows = normalized.split('\n');
    final offset = _globalOffset(rows);
    final parsed = <_IndexedLyricLine>[];
    var sourceIndex = 0;

    for (final row in rows) {
      final leadingTags = _leadingTags.firstMatch(row);
      if (leadingTags == null) {
        continue;
      }

      final tags = _tag.allMatches(leadingTags.group(1)!);
      final timestamps = <Duration>[];
      for (final tag in tags) {
        final timestamp = _parseTimestamp(tag.group(1)!);
        if (timestamp != null) {
          timestamps.add(timestamp);
        }
      }
      if (timestamps.isEmpty) {
        continue;
      }

      final sourceText = leadingTags.group(2)!.trim();
      final wordTags = _wordTag.allMatches(sourceText).toList();
      final text = sourceText.replaceAll(_wordTag, '').trim();
      for (final timestamp in timestamps) {
        final shiftedMilliseconds = timestamp.inMilliseconds + offset;
        parsed.add(
          _IndexedLyricLine(
            line: LyricLine(
              timestamp: Duration(
                milliseconds: shiftedMilliseconds < 0 ? 0 : shiftedMilliseconds,
              ),
              text: text,
            ),
            sourceIndex: sourceIndex++,
            enhancedSource: sourceText,
            wordTags: wordTags,
            wordOffset: offset + (timestamp - timestamps.first).inMilliseconds,
          ),
        );
      }
    }

    parsed.sort((left, right) {
      final byTimestamp = left.line.timestamp.compareTo(right.line.timestamp);
      return byTimestamp != 0
          ? byTimestamp
          : left.sourceIndex.compareTo(right.sourceIndex);
    });
    final nextTimes = List<Duration?>.filled(parsed.length, null);
    Duration? later;
    for (var i = parsed.length - 1; i >= 0; i--) {
      if (i + 1 < parsed.length &&
          parsed[i + 1].line.timestamp > parsed[i].line.timestamp) {
        later = parsed[i + 1].line.timestamp;
      }
      nextTimes[i] = later;
    }
    return List.unmodifiable(
      List.generate(parsed.length, (i) {
        final entry = parsed[i];
        final line = entry.line;
        final words = _words(
          entry.enhancedSource,
          line.text,
          entry.wordTags,
          entry.wordOffset,
          nextTimes[i],
        );
        final timed = LyricLine(
          timestamp: line.timestamp,
          text: line.text,
          words: words,
        );
        return timed.hasWordTiming ? timed : line;
      }),
    );
  }

  List<LyricWord> _words(
    String source,
    String text,
    List<RegExpMatch> tags,
    int offset,
    Duration? nextLine,
  ) {
    if (tags.isEmpty) return const [];
    if (source.substring(0, tags.first.start).trim().isNotEmpty) {
      return const [];
    }
    final words = <LyricWord>[];
    Duration shifted(Duration value) {
      final milliseconds = value.inMilliseconds + offset;
      return Duration(milliseconds: milliseconds < 0 ? 0 : milliseconds);
    }

    var cursor = 0;
    for (var i = 0; i < tags.length; i++) {
      final tag = tags[i];
      final next = i + 1 < tags.length ? tags[i + 1] : null;
      final raw = source.substring(tag.end, next?.start ?? source.length);
      final part = raw.trim();
      if (part.isEmpty) continue;
      final start = _parseTimestamp(tag.group(1)!);
      final end = next == null ? null : _parseTimestamp(next.group(1)!);
      // A final closing marker or the next line is a known boundary. The last
      // line without either remains line synced instead of guessing its pace.
      if (start == null ||
          (next != null && end == null) ||
          (end == null && nextLine == null)) {
        return const [];
      }
      final startOffset = text.indexOf(part, cursor);
      if (startOffset < 0) return const [];
      final endOffset = startOffset + part.length;
      words.add(
        LyricWord(
          text: part,
          start: shifted(start),
          end: end == null ? nextLine! : shifted(end),
          startOffset: startOffset,
          endOffset: endOffset,
        ),
      );
      cursor = endOffset;
    }
    return List.unmodifiable(words);
  }

  int _globalOffset(List<String> rows) {
    var offset = 0;
    for (final row in rows) {
      for (final match in _offset.allMatches(row)) {
        offset = int.tryParse(match.group(1)!) ?? offset;
      }
    }
    return offset;
  }

  Duration? _parseTimestamp(String rawTag) {
    final tag = rawTag.trim();
    final parts = tag.split(':');
    if (parts.length != 2 && parts.length != 3) {
      return null;
    }

    final hasHours = parts.length == 3;
    final hours = hasHours ? int.tryParse(parts[0]) : 0;
    final minutes = int.tryParse(parts[hasHours ? 1 : 0]);
    final secondParts = parts.last.split(RegExp(r'[\.,]'));
    if (secondParts.length > 2) {
      return null;
    }
    final seconds = int.tryParse(secondParts.first);
    final milliseconds = secondParts.length == 1
        ? 0
        : _fractionMilliseconds(secondParts.last);

    if (hours == null ||
        minutes == null ||
        seconds == null ||
        hours < 0 ||
        minutes < 0 ||
        seconds < 0 ||
        seconds >= 60 ||
        (hasHours && minutes >= 60) ||
        milliseconds == null) {
      return null;
    }

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  int? _fractionMilliseconds(String fraction) {
    if (fraction.isEmpty || fraction.length > 3) {
      return null;
    }
    final value = int.tryParse(fraction);
    if (value == null) {
      return null;
    }
    return switch (fraction.length) {
      1 => value * 100,
      2 => value * 10,
      _ => value,
    };
  }

  static final _leadingTags = RegExp(r'^\s*((?:\[[^\]]*\]\s*)+)(.*)$');
  static final _tag = RegExp(r'\[([^\]]*)\]');
  static final _wordTag = RegExp(r'<(\d+(?::\d+){1,2}(?:[.,]\d+)?)>');
  static final _offset = RegExp(
    r'\[\s*offset\s*:\s*([+-]?\d+)\s*\]',
    caseSensitive: false,
  );
}

class _IndexedLyricLine {
  const _IndexedLyricLine({
    required this.line,
    required this.sourceIndex,
    required this.enhancedSource,
    required this.wordTags,
    required this.wordOffset,
  });

  final LyricLine line;
  final int sourceIndex;
  final String enhancedSource;
  final List<RegExpMatch> wordTags;
  final int wordOffset;
}
