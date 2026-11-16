import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nicofy/theme/remote_focus_theme.dart';
import 'package:nicofy/utilities/device_identity.dart';
import 'package:nicofy/widgets/remote_focusable.dart';

void main() {
  final theme = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: Brightness.dark,
    ),
  );

  tearDown(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    isTelevision = false;
  });

  Border? outlineOf(WidgetTester tester, Finder frame) =>
      (tester
                      .widget<DecoratedBox>(
                        find
                            .descendant(
                              of: frame,
                              matching: find.byType(DecoratedBox),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration)
              .border
          as Border?;

  Future<void> pumpTile(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: withRemoteFocusStyle(theme),
        home: Scaffold(
          body: Column(
            children: [
              RemoteFocusable(
                onActivate: () {},
                child: const SizedBox(width: 100, height: 100),
              ),
              RemoteFocusFrame(
                child: Material(
                  child: InkWell(
                    onTap: () {},
                    child: const SizedBox(width: 100, height: 40),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  group('a remote-reachable tile', () {
    testWidgets('is outlined while focused with a remote in hand', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      await pumpTile(tester);
      final tile = find.byType(RemoteFocusFrame).first;
      expect(outlineOf(tester, tile), isNull);

      primaryFocus!.nextFocus();
      await tester.pumpAndSettle();

      final border = outlineOf(tester, tile)!;
      expect(border.top.width, RemoteFocusStyle.outlineWidth);
      expect(border.top.color, theme.colorScheme.onSurface);
      expect(
        tester
            .widget<AnimatedScale>(
              find.descendant(of: tile, matching: find.byType(AnimatedScale)),
            )
            .scale,
        1,
        reason: 'the focused tile comes up to full size',
      );

      // On to the ink well: it takes the outline, the tile gives it back.
      primaryFocus!.nextFocus();
      await tester.pumpAndSettle();
      expect(outlineOf(tester, tile), isNull);
      expect(outlineOf(tester, find.byType(RemoteFocusFrame).last), isNotNull);
    });

    testWidgets('shows nothing to a finger', (tester) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      await pumpTile(tester);
      final tile = find.byType(RemoteFocusFrame).first;

      primaryFocus!.nextFocus();
      await tester.pumpAndSettle();

      expect(outlineOf(tester, tile), isNull);
      expect(
        tester
            .widget<AnimatedScale>(
              find.descendant(of: tile, matching: find.byType(AnimatedScale)),
            )
            .scale,
        1,
        reason: 'tiles keep their size on a phone',
      );
    });

    testWidgets('is outlined on a TV whatever the highlight mode', (
      tester,
    ) async {
      isTelevision = true;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      await pumpTile(tester);
      primaryFocus!.nextFocus();
      await tester.pumpAndSettle();

      expect(outlineOf(tester, find.byType(RemoteFocusFrame).first), isNotNull);
    });
  });

  group('the remote focus theme', () {
    testWidgets('outlines a focused button, and only that one', (tester) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      final first = FocusNode();
      addTearDown(first.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: withRemoteFocusStyle(theme),
          home: Scaffold(
            body: Row(
              children: [
                IconButton(
                  focusNode: first,
                  icon: const Icon(Icons.play_arrow),
                  onPressed: () {},
                ),
                IconButton(icon: const Icon(Icons.stop), onPressed: () {}),
              ],
            ),
          ),
        ),
      );

      BorderSide sideOf(int index) {
        final material = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(IconButton).at(index),
                matching: find.byType(Material),
              )
              .first,
        );
        return (material.shape! as OutlinedBorder).side;
      }

      first.requestFocus();
      await tester.pumpAndSettle();

      expect(sideOf(0).width, RemoteFocusStyle.outlineWidth);
      expect(sideOf(0).color, theme.colorScheme.onSurface);
      expect(sideOf(1), BorderSide.none);
    });

    test('is used with a remote or on a TV, never for a finger', () {
      expect(usesRemoteFocusStyle(FocusHighlightMode.traditional), isTrue);
      expect(usesRemoteFocusStyle(FocusHighlightMode.touch), isFalse);
      isTelevision = true;
      expect(usesRemoteFocusStyle(FocusHighlightMode.touch), isTrue);
    });
  });
}
