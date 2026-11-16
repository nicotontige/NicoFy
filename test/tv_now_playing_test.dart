import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nicofy/widgets/now_playing/tv_remote.dart';

void main() {
  group('the remote on the TV player', () {
    late FocusNode play;
    late FocusNode next;

    setUp(() {
      play = FocusNode(debugLabel: 'play');
      next = FocusNode(debugLabel: 'next');
    });

    tearDown(() {
      play.dispose();
      next.dispose();
    });

    /// The transport row of a song: [song] keys it, as a change of song
    /// rebuilds the buttons, and [hasNext] whether next is there at all.
    Widget player({
      String song = 'a',
      bool hasNext = true,
      bool covered = false,
    }) => MaterialApp(
      home: Scaffold(
        body: TvPlayFocusKeeper(
          playFocusNode: play,
          isCovered: () => covered,
          child: Row(
            key: ValueKey(song),
            children: [
              TextButton(
                focusNode: play,
                onPressed: () {},
                child: const Text('play'),
              ),
              if (hasNext)
                TextButton(
                  focusNode: next,
                  onPressed: () {},
                  child: const Text('next'),
                ),
            ],
          ),
        ),
      ),
    );

    testWidgets('lands on play/pause when the screen opens', (tester) async {
      await tester.pumpWidget(player());
      await tester.pump();

      expect(play.hasPrimaryFocus, isTrue);
    });

    testWidgets('stays on play/pause when the song changes', (tester) async {
      await tester.pumpWidget(player());
      await tester.pump();

      await tester.pumpWidget(player(song: 'b'));
      await tester.pump();

      expect(play.hasPrimaryFocus, isTrue);
    });

    testWidgets('comes back to play/pause when its control goes away', (
      tester,
    ) async {
      await tester.pumpWidget(player());
      await tester.pump();
      next.requestFocus();
      await tester.pump();
      expect(next.hasPrimaryFocus, isTrue);

      await tester.pumpWidget(player(hasNext: false));
      await tester.pump();

      expect(play.hasPrimaryFocus, isTrue);
    });

    testWidgets('leaves focus alone under a sheet', (tester) async {
      await tester.pumpWidget(player(covered: true));
      await tester.pump();

      expect(play.hasFocus, isFalse);
    });
  });

  group('the progress bar', () {
    late Duration position;
    late List<Duration> seeks;
    late FocusNode bar;

    setUp(() {
      position = const Duration(seconds: 30);
      seeks = [];
      bar = FocusNode(debugLabel: 'bar');
    });

    tearDown(() => bar.dispose());

    Future<void> pumpBar(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextButton(onPressed: () {}, child: const Text('play')),
                TvSeekBar(
                  focusNode: bar,
                  position: () => position,
                  duration: () => const Duration(minutes: 3),
                  onSeek: seeks.add,
                  child: const SizedBox(height: 40, width: 300),
                ),
              ],
            ),
          ),
        ),
      );
      bar.requestFocus();
      await tester.pump();
    }

    testWidgets('right and left move ten seconds, and say so', (tester) async {
      await pumpBar(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(seeks, [const Duration(seconds: 40)]);
      expect(find.text('+10 s'), findsOneWidget);

      // The player has not caught up yet: the next press goes on from 40.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(seeks.last, const Duration(seconds: 50));
      expect(find.text('+20 s'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining(' s'), findsNothing);

      position = const Duration(seconds: 50);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(seeks.last, const Duration(seconds: 40));
      expect(find.text('−10 s'), findsOneWidget);
      expect(bar.hasPrimaryFocus, isTrue, reason: 'left stays on the bar');
    });

    testWidgets('stops at the start of the song', (tester) async {
      position = const Duration(seconds: 4);
      await pumpBar(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      expect(seeks, [Duration.zero]);
    });

    testWidgets('up leaves the bar', (tester) async {
      await pumpBar(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();

      expect(seeks, isEmpty);
      expect(bar.hasPrimaryFocus, isFalse);
    });
  });

  group('the ambient screen', () {
    testWidgets('wakes on the first key without pressing anything', (
      tester,
    ) async {
      var active = true;
      var wakes = 0;
      var presses = 0;
      final button = FocusNode();
      addTearDown(button.dispose);

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            home: RemoteWakeGuard(
              active: active,
              onWake: () => setState(() {
                wakes++;
                active = false;
              }),
              child: Scaffold(
                body: TextButton(
                  focusNode: button,
                  onPressed: () => presses++,
                  child: const Text('play'),
                ),
              ),
            ),
          ),
        ),
      );
      button.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(wakes, 1);
      expect(presses, 0, reason: 'the waking key does nothing else');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(wakes, 1);
      expect(presses, 1, reason: 'awake, keys work again');
    });

    testWidgets('lets back through', (tester) async {
      var wakes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: RemoteWakeGuard(
            active: true,
            onWake: () => wakes++,
            child: const SizedBox(),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(wakes, 0);
    });
  });

  group('the idle timer', () {
    testWidgets('opens the player after a minute without a key', (
      tester,
    ) async {
      var playing = true;
      var idles = 0;
      final watcher = TvIdleWatcher(
        delay: const Duration(seconds: 60),
        isPlaying: () => playing,
        onIdle: () => idles++,
      )..start();
      addTearDown(watcher.dispose);
      await tester.pumpWidget(const SizedBox());

      await tester.pump(const Duration(seconds: 59));
      expect(idles, 0);

      // A key starts the wait over.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(seconds: 59));
      expect(idles, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(idles, 1);

      // Paused: nothing opens.
      playing = false;
      watcher.restart();
      await tester.pump(const Duration(seconds: 61));
      expect(idles, 1);
    });
  });
}
