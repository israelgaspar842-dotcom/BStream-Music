import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bstream_music/features/music/domain/entities/lyric_word.dart';
import 'package:bstream_music/features/music/presentation/widgets/lyrics_word_timing_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _style = TextStyle(
  inherit: false,
  fontFamily: 'Ahem',
  fontSize: 30,
  height: 1.2,
  color: Colors.white,
);
const _text = 'ONE TWO';
const _words = [
  LyricWord(
    text: 'ONE',
    start: Duration(seconds: 1),
    end: Duration(seconds: 2),
    startOffset: 0,
    endOffset: 3,
  ),
  LyricWord(
    text: 'TWO',
    start: Duration(seconds: 3),
    end: Duration(seconds: 4),
    startOffset: 4,
    endOffset: 7,
  ),
];

void main() {
  testWidgets('sweeps the active word, pauses and seeks without reshaping', (
    tester,
  ) async {
    var clock = Duration.zero;
    final playback = ValueNotifier(
      const LyricsWordPlaybackSample(
        position: Duration(milliseconds: 500),
        sampledAt: Duration.zero,
        isPlaying: false,
      ),
    );
    addTearDown(playback.dispose);
    await tester.pumpWidget(_app(playback, () => clock));
    final dynamic state = tester.state(find.byType(LyricsWordTimingText));
    final initialLayouts = state.debugParagraphLayoutCount as int;
    final before = await _pixels(tester);

    playback.value = const LyricsWordPlaybackSample(
      position: Duration(seconds: 1),
      sampledAt: Duration.zero,
      isPlaying: true,
    );
    await tester.pump();
    clock = const Duration(milliseconds: 500);
    await tester.pump(const Duration(milliseconds: 50));
    final half = await _pixels(tester);
    expect(half.alphaSum(), greaterThan(before.alphaSum()));

    clock = const Duration(seconds: 1);
    await tester.pump(const Duration(milliseconds: 50));
    final completed = await _pixels(tester);
    expect(completed.alphaSum(), greaterThan(half.alphaSum()));
    expect(state.debugTickerActive, isFalse, reason: 'Wait through word gaps.');

    playback.value = LyricsWordPlaybackSample(
      position: const Duration(milliseconds: 1500),
      sampledAt: clock,
      isPlaying: false,
    );
    await tester.pump();
    final paused = await _pixels(tester);
    clock += const Duration(seconds: 10);
    await tester.pump(const Duration(seconds: 1));
    expect((await _pixels(tester)).alphaSum(), paused.alphaSum());
    expect(state.debugTickerActive, isFalse);

    playback.value = LyricsWordPlaybackSample(
      position: const Duration(milliseconds: 500),
      sampledAt: clock,
      isPlaying: false,
    );
    await tester.pump();
    expect((await _pixels(tester)).alphaSum(), before.alphaSum());
    expect(state.debugParagraphLayoutCount, initialLayouts);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion advances whole words at their real boundaries', (
    tester,
  ) async {
    var clock = Duration.zero;
    final playback = ValueNotifier(
      const LyricsWordPlaybackSample(
        position: Duration.zero,
        sampledAt: Duration.zero,
        isPlaying: true,
      ),
    );
    addTearDown(playback.dispose);
    await tester.pumpWidget(_app(playback, () => clock, reducedMotion: true));
    final dynamic state = tester.state(find.byType(LyricsWordTimingText));
    final before = await _pixels(tester);
    expect(state.debugTickerActive, isFalse);

    clock = const Duration(seconds: 1);
    await tester.pump(const Duration(seconds: 1));
    final first = await _pixels(tester);
    expect(first.alphaSum(), greaterThan(before.alphaSum()));
    clock = const Duration(milliseconds: 1700);
    await tester.pump(const Duration(milliseconds: 700));
    expect((await _pixels(tester)).alphaSum(), first.alphaSum());

    clock = const Duration(seconds: 3);
    await tester.pump(const Duration(milliseconds: 1300));
    expect((await _pixels(tester)).alphaSum(), greaterThan(first.alphaSum()));
    expect(state.debugTickerActive, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('retains wrapping and fills Hebrew from its visual right edge', (
    tester,
  ) async {
    const text = 'שלום עולם';
    const words = [
      LyricWord(
        text: 'שלום',
        start: Duration(seconds: 1),
        end: Duration(seconds: 2),
        startOffset: 0,
        endOffset: 4,
      ),
      LyricWord(
        text: 'עולם',
        start: Duration(seconds: 3),
        end: Duration(seconds: 4),
        startOffset: 5,
        endOffset: 9,
      ),
    ];
    final playback = ValueNotifier(
      const LyricsWordPlaybackSample(
        position: Duration.zero,
        sampledAt: Duration.zero,
        isPlaying: false,
      ),
    );
    addTearDown(playback.dispose);
    await tester.pumpWidget(
      _app(
        playback,
        () => Duration.zero,
        text: text,
        words: words,
        width: 130,
        direction: TextDirection.rtl,
      ),
    );
    final before = await _pixels(tester);
    final paragraph = TextPainter(
      text: const TextSpan(text: text, style: _style),
      textDirection: TextDirection.rtl,
    )..layout(minWidth: 130, maxWidth: 130);
    try {
      expect(before.height, greaterThan(36));
      final box = paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 4),
          )
          .first;
      expect(box.direction, TextDirection.rtl);
      playback.value = const LyricsWordPlaybackSample(
        position: Duration(milliseconds: 1500),
        sampledAt: Duration.zero,
        isPlaying: false,
      );
      await tester.pump();
      final half = await _pixels(tester);
      expect(half.width, before.width);
      expect(half.height, before.height);
      final rect = box.toRect();
      final left = Rect.fromLTRB(
        rect.left,
        rect.top,
        rect.center.dx,
        rect.bottom,
      );
      final right = Rect.fromLTRB(
        rect.center.dx,
        rect.top,
        rect.right,
        rect.bottom,
      );
      expect(
        half.alphaSum(right) - before.alphaSum(right),
        greaterThan(half.alphaSum(left) - before.alphaSum(left)),
      );
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel(text), findsOneWidget);
      semantics.dispose();
    } finally {
      paragraph.dispose();
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('stops its paint clock while hidden and after the final word', (
    tester,
  ) async {
    var clock = Duration.zero;
    final playback = ValueNotifier(
      const LyricsWordPlaybackSample(
        position: Duration(seconds: 1),
        sampledAt: Duration.zero,
        isPlaying: true,
      ),
    );
    addTearDown(playback.dispose);
    await tester.pumpWidget(_app(playback, () => clock));
    final dynamic state = tester.state(find.byType(LyricsWordTimingText));
    expect(state.debugTickerActive, isTrue);
    final before = await _pixels(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    clock = const Duration(milliseconds: 500);
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.debugTickerActive, isFalse);
    expect((await _pixels(tester)).alphaSum(), before.alphaSum());

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(state.debugTickerActive, isTrue);
    expect((await _pixels(tester)).alphaSum(), greaterThan(before.alphaSum()));
    clock = const Duration(seconds: 4);
    await tester.pump(const Duration(milliseconds: 50));
    expect(state.debugTickerActive, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _app(
  ValueNotifier<LyricsWordPlaybackSample> playback,
  Duration Function() clock, {
  String text = _text,
  List<LyricWord> words = _words,
  double width = 240,
  bool reducedMotion = false,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: Directionality(
      textDirection: direction,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: RepaintBoundary(
            key: const ValueKey('word-capture'),
            child: LyricsWordTimingText(
              text: text,
              words: words,
              style: _style,
              textAlign: TextAlign.start,
              active: true,
              playback: playback,
              monotonicClock: clock,
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<_Pixels> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('word-capture')),
  );
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
  try {
    final bytes = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    return _Pixels(image.width, image.height, bytes);
  } finally {
    image.dispose();
  }
}

class _Pixels {
  _Pixels(this.width, this.height, this.bytes);

  final int width;
  final int height;
  final ByteData bytes;

  int alphaSum([Rect? rect]) {
    var sum = 0;
    final region =
        rect ?? Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    for (
      var y = region.top.ceil().clamp(0, height).toInt();
      y < region.bottom.floor().clamp(0, height);
      y++
    ) {
      for (
        var x = region.left.ceil().clamp(0, width).toInt();
        x < region.right.floor().clamp(0, width);
        x++
      ) {
        sum += bytes.getUint8(((y * width + x) * 4) + 3);
      }
    }
    return sum;
  }
}
