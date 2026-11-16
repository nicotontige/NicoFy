import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nicofy/widgets/remote_hold_detector.dart';

/// Holding select on a TV remote is its long press; Flutter only sees a key
/// held down.
void main() {
  late FocusNode tileNode;
  late FocusNode menuNode;
  late int presses;
  late int holds;
  late int menuActivations;

  Future<void> pumpTile(WidgetTester tester) async {
    tileNode = FocusNode();
    menuNode = FocusNode();
    presses = 0;
    holds = 0;
    menuActivations = 0;
    addTearDown(tileNode.dispose);
    addTearDown(menuNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              RemoteHoldDetector(
                focusNode: tileNode,
                onPress: () => presses++,
                onHold: () {
                  holds++;
                  // Like a menu opening while the key is still down.
                  menuNode.requestFocus();
                },
                child: InkWell(
                  focusNode: tileNode,
                  onTap: () => presses++,
                  child: const SizedBox(width: 100, height: 40),
                ),
              ),
              InkWell(
                focusNode: menuNode,
                onTap: () => menuActivations++,
                child: const SizedBox(width: 100, height: 40),
              ),
            ],
          ),
        ),
      ),
    );
    tileNode.requestFocus();
    await tester.pump();
  }

  testWidgets('a short press activates once', (tester) async {
    await pumpTile(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(presses, 1);
    expect(holds, 0);
  });

  testWidgets('holding opens the menu before the key is released', (
    tester,
  ) async {
    await pumpTile(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));

    expect(holds, 1);
    expect(presses, 0);
  });

  testWidgets('the held key does not pick the first menu item', (tester) async {
    await pumpTile(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    expect(menuNode.hasPrimaryFocus, isTrue);

    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(menuActivations, 0);

    // The next press is an ordinary one again.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(menuActivations, 1);
  });
}
