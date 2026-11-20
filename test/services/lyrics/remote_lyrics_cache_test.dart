import 'package:bstream_music/features/music/domain/entities/lyrics.dart';
import 'package:bstream_music/services/lyrics/lrclib_transport.dart';
import 'package:bstream_music/services/lyrics/remote_lyrics_service_base.dart';
import 'package:flutter_test/flutter_test.dart';

const _firstLookup = LyricsLookup(
  title: 'First song',
  artist: 'Artist',
  duration: Duration(minutes: 1),
);
const _secondLookup = LyricsLookup(
  title: 'Second song',
  artist: 'Artist',
  duration: Duration(minutes: 1),
);

void main() {
  test(
    'a cached document retains its word timeline without another request',
    () async {
      final transport = _Transport();
      final service = _WordTimedService(transport: transport, wordCount: 3);
      addTearDown(service.dispose);

      final first = await service.findLyrics(_firstLookup);
      final cached = await service.findLyrics(_firstLookup);

      expect(cached, same(first));
      expect(cached!.lines.first.hasWordTiming, isTrue);
      expect(cached.lines.first.words, same(first!.lines.first.words));
      expect(transport.requests, hasLength(1));
    },
  );

  test('dense word metadata that exceeds the budget is not retained', () async {
    final transport = _Transport();
    final service = _WordTimedService(transport: transport, wordCount: 5000);
    addTearDown(service.dispose);

    final first = await service.findLyrics(_firstLookup);
    final second = await service.findLyrics(_firstLookup);

    expect(first!.lines.first.hasWordTiming, isTrue);
    expect(second!.lines.first.hasWordTiming, isTrue);
    expect(transport.requests, hasLength(2));
  });

  test(
    'combined word metadata evicts the least recently used document',
    () async {
      final transport = _Transport();
      final service = _WordTimedService(transport: transport, wordCount: 2100);
      addTearDown(service.dispose);

      await service.findLyrics(_firstLookup);
      await service.findLyrics(_firstLookup);
      expect(transport.requests, hasLength(1));

      await service.findLyrics(_secondLookup);
      await service.findLyrics(_firstLookup);

      expect(transport.requests, hasLength(3));
      expect(
        transport.requests.last.queryParameters['title'],
        _firstLookup.title,
      );
    },
  );
}

class _WordTimedService extends RemoteLyricsServiceBase {
  _WordTimedService({
    required LrclibTransport transport,
    required this.wordCount,
  }) : super(userAgent: 'test', transport: transport);

  final int wordCount;

  @override
  String get provider => 'Word timeline fixture';

  @override
  Uri requestUri(LyricsLookup lookup) =>
      Uri.https('lyrics.example.test', '/lyrics', {'title': lookup.title});

  @override
  Future<LyricsDocument?> parseResponse(
    String body,
    LyricsLookup lookup,
  ) async {
    final text = List.filled(wordCount, 'a').join(' ');
    return LyricsDocument(
      provider: provider,
      trackName: lookup.title,
      artistName: lookup.artist,
      duration: lookup.duration,
      lines: [
        LyricLine(
          timestamp: Duration.zero,
          text: text,
          words: [
            for (var index = 0; index < wordCount; index++)
              LyricWord(
                text: 'a',
                start: Duration(milliseconds: index * 2),
                end: Duration(milliseconds: index * 2 + 1),
                startOffset: index * 2,
                endOffset: index * 2 + 1,
              ),
          ],
        ),
        const LyricLine(timestamp: Duration(seconds: 20), text: 'Next line'),
      ],
    );
  }
}

class _Transport implements LrclibTransport {
  final requests = <Uri>[];

  @override
  Future<LrclibResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    Duration? timeout,
  }) async {
    requests.add(uri);
    return LrclibResponse(statusCode: 200, body: '{}');
  }

  @override
  void close() {}
}
