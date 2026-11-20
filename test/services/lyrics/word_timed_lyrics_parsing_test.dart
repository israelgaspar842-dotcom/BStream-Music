import 'dart:convert';

import 'package:bstream_music/features/music/domain/entities/lyrics.dart';
import 'package:bstream_music/services/lyrics/lrclib_transport.dart';
import 'package:bstream_music/services/lyrics/remote_lyrics_parsing.dart';
import 'package:bstream_music/services/lyrics/youlyplus_lyrics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TTML retains syllables, punctuation and exact UTF-16 ranges', () {
    final result = parseRemoteLyricsTtml('''
<tt xmlns:ttm="http://www.w3.org/ns/ttml#metadata"><body><div>
<p begin="1s" end="3s"> (<span begin="1s" end="1.5s">🎵 Ho</span><span begin="1.5s" end="2s">la</span>, <span begin="2s" end="3s">mundo!</span>)<span ttm:role="x-translation">Wrong</span></p>
</div></body></tt>''');
    final line = result.lines.single;
    expect(line.text, '(🎵 Hola, mundo!)');
    expect(line.hasWordTiming, isTrue);
    expect(line.words.map((word) => word.text), ['🎵 Ho', 'la', 'mundo!']);
    expect(line.words.map((word) => (word.startOffset, word.endOffset)), [
      (1, 6),
      (6, 8),
      (10, 16),
    ]);
    expect(line.words.last.end, const Duration(seconds: 3));
    for (final word in line.words) {
      expect(line.text.substring(word.startOffset, word.endOffset), word.text);
    }
    expect(() => line.words.clear(), throwsUnsupportedError);
  });

  test(
    'TTML infers only bounded missing ends and supports nested spans/dur',
    () {
      final line = parseRemoteLyricsTtml('''
<tt><body><p begin="10s" end="12s"><span><span begin="10s">First </span><span begin="11s" dur="1s">sample</span></span></p></body></tt>
''').lines.single;
      expect(line.hasWordTiming, isTrue);
      expect(line.words.first.end, const Duration(seconds: 11));
      expect(line.words.last.end, const Duration(seconds: 12));
    },
  );

  test('TTML missing word ends skip untimed inter-span punctuation', () {
    final line = parseRemoteLyricsTtml(
      '<tt><body><p begin="1s" end="3s"><span begin="1s">First</span>, <span begin="2s">sample</span>!</p></body></tt>',
    ).lines.single;
    expect(line.text, 'First, sample!');
    expect(line.hasWordTiming, isTrue);
    expect(line.words.map((word) => word.end), [
      const Duration(seconds: 2),
      const Duration(seconds: 3),
    ]);
    expect(line.words.map((word) => (word.startOffset, word.endOffset)), [
      (0, 5),
      (7, 13),
    ]);
  });

  for (final source in [
    '<p begin="1s"><span begin="1s">First </span><span begin="2s">sample</span></p>',
    '<p begin="1s" end="4s"><span begin="2s" end="3s">First </span><span begin="1s" end="4s">sample</span></p>',
    '<p begin="1s" end="4s"><span begin="1s" end="2s">First </span>sample</p>',
    '<p begin="1s" end="4s"><span begin="1s" end="bad">First </span><span begin="2s" end="4s">sample</span></p>',
    '<p begin="1s" end="4s">First sample</p>',
  ]) {
    test(
      'TTML incomplete or invalid token timing keeps the parent line: $source',
      () {
        final line = parseRemoteLyricsTtml(
          '<tt><body>$source</body></tt>',
        ).lines.single;
        expect(line.text, 'First sample');
        expect(line.timestamp, const Duration(seconds: 1));
        expect(line.words, isEmpty);
        expect(line.hasWordTiming, isFalse);
      },
    );
  }

  test(
    'LyricsPlus keeps millisecond token durations and spaces from line text',
    () async {
      final result = await _youly({
        'type': 'Word',
        'lyrics': [
          {
            'time': 1000,
            'duration': 2000,
            'text': 'Hello, world!',
            'syllabus': [
              {'time': 1000, 'duration': 500, 'text': 'Hel'},
              {'time': 1500, 'duration': 500, 'text': 'lo'},
              {'time': 2000, 'duration': 1000, 'text': 'world!'},
            ],
          },
        ],
      });
      final line = result!.lines.single;
      expect(line.hasWordTiming, isTrue);
      expect(line.text, 'Hello, world!');
      expect(line.words.map((word) => (word.startOffset, word.endOffset)), [
        (0, 3),
        (3, 5),
        (7, 13),
      ]);
      expect(line.words.first.start, const Duration(seconds: 1));
      expect(line.words.first.end, const Duration(milliseconds: 1500));
      expect(line.words.last.end, const Duration(seconds: 3));
    },
  );

  for (final tokens in [
    [
      {'time': 1000, 'duration': 500, 'text': 'First '},
      {'time': 1500, 'text': 'sample'},
    ],
    [
      {'time': 1000, 'duration': -1, 'text': 'First '},
      {'time': 1500, 'duration': 500, 'text': 'sample'},
    ],
    [
      {'time': 1000, 'duration': 500, 'text': 'Different '},
      {'time': 1500, 'duration': 500, 'text': 'sample'},
    ],
  ]) {
    test(
      'LyricsPlus invalid or incomplete word data falls back to its line: $tokens',
      () async {
        final result = await _youly({
          'type': 'Word',
          'lyrics': [
            {'time': 1000, 'text': 'First sample', 'syllabus': tokens},
          ],
        });
        expect(result!.lines.single.text, 'First sample');
        expect(result.lines.single.words, isEmpty);
      },
    );
  }

  test(
    'Line and None do not manufacture word timing from token-like data',
    () async {
      for (final type in ['Line', 'None']) {
        final result = await _youly({
          'type': type,
          'lyrics': [
            {
              'time': 1000,
              'text': 'First sample',
              'syllabus': [
                {'time': 1000, 'duration': 2000, 'text': 'First sample'},
              ],
            },
          ],
        });
        expect(result!.lines.every((line) => !line.hasWordTiming), isTrue);
        expect(result.hasPlainLyrics, isTrue);
      }
    },
  );
}

Future<LyricsDocument?> _youly(Map<String, Object?> payload) async {
  final service = YouLyPlusLyricsService(
    userAgent: 'test',
    transport: _Transport(jsonEncode(payload)),
  );
  try {
    return await service.findLyrics(
      const LyricsLookup(title: 'Sample', artist: 'Artist'),
    );
  } finally {
    service.dispose();
  }
}

class _Transport implements LrclibTransport {
  _Transport(this.body);
  final String body;
  @override
  Future<LrclibResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    Duration? timeout,
  }) async => LrclibResponse(statusCode: 200, body: body);
  @override
  void close() {}
}
