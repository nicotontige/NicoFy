import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nicofy/widgets/text_field_remote_navigation.dart';

/// A TV remote only has arrows; inside a text field they moved the caret and
/// nothing else, so the remote could not get out of a search field.
void main() {
  group('textFieldLetsFocusLeave', () {
    TextEditingValue caretAt(String text, int offset) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );

    test('an empty field lets every arrow out', () {
      for (final direction in TraversalDirection.values) {
        expect(
          textFieldLetsFocusLeave(
            value: TextEditingValue.empty,
            isMultiline: false,
            direction: direction,
          ),
          isTrue,
        );
      }
    });

    test('up and down always leave a single-line field', () {
      for (final direction in [
        TraversalDirection.up,
        TraversalDirection.down,
      ]) {
        expect(
          textFieldLetsFocusLeave(
            value: caretAt('abba', 2),
            isMultiline: false,
            direction: direction,
          ),
          isTrue,
        );
      }
    });

    test('left and right leave only from the ends of the text', () {
      bool leaves(int offset, TraversalDirection direction) =>
          textFieldLetsFocusLeave(
            value: caretAt('abba', offset),
            isMultiline: false,
            direction: direction,
          );

      expect(leaves(0, TraversalDirection.left), isTrue);
      expect(leaves(2, TraversalDirection.left), isFalse);
      expect(leaves(4, TraversalDirection.left), isFalse);
      expect(leaves(4, TraversalDirection.right), isTrue);
      expect(leaves(2, TraversalDirection.right), isFalse);
      expect(leaves(0, TraversalDirection.right), isFalse);
    });

    test('a selection keeps the arrows', () {
      expect(
        textFieldLetsFocusLeave(
          value: const TextEditingValue(
            text: 'abba',
            selection: TextSelection(baseOffset: 0, extentOffset: 4),
          ),
          isMultiline: false,
          direction: TraversalDirection.right,
        ),
        isFalse,
      );
    });

    test('a multiline field leaves vertically from its ends only', () {
      expect(
        textFieldLetsFocusLeave(
          value: caretAt('one\ntwo', 5),
          isMultiline: true,
          direction: TraversalDirection.down,
        ),
        isFalse,
      );
      expect(
        textFieldLetsFocusLeave(
          value: caretAt('one\ntwo', 7),
          isMultiline: true,
          direction: TraversalDirection.down,
        ),
        isTrue,
      );
    });

    test('a word being composed keeps the arrows', () {
      expect(
        textFieldLetsFocusLeave(
          value: const TextEditingValue(
            text: 'abba',
            selection: TextSelection.collapsed(offset: 4),
            composing: TextRange(start: 0, end: 4),
          ),
          isMultiline: false,
          direction: TraversalDirection.right,
        ),
        isFalse,
      );
    });
  });

  group('TextFieldRemoteNavigation', () {
    late FocusNode fieldNode;
    late FocusNode aboveNode;
    late FocusNode belowNode;
    late TextEditingController controller;

    Future<void> pumpPage(WidgetTester tester, {String text = ''}) async {
      fieldNode = FocusNode();
      aboveNode = FocusNode();
      belowNode = FocusNode();
      controller = TextEditingController(text: text);
      addTearDown(fieldNode.dispose);
      addTearDown(aboveNode.dispose);
      addTearDown(belowNode.dispose);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => TextFieldRemoteNavigation(child: child!),
          home: Scaffold(
            body: Column(
              children: [
                TextButton(
                  focusNode: aboveNode,
                  onPressed: () {},
                  child: const Text('above'),
                ),
                TextField(focusNode: fieldNode, controller: controller),
                TextButton(
                  focusNode: belowNode,
                  onPressed: () {},
                  child: const Text('below'),
                ),
              ],
            ),
          ),
        ),
      );
      fieldNode.requestFocus();
      await tester.pump();
    }

    testWidgets('down and up leave the field', (tester) async {
      await pumpPage(tester, text: 'abba');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(belowNode.hasPrimaryFocus, isTrue);

      fieldNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(aboveNode.hasPrimaryFocus, isTrue);
    });

    testWidgets('left inside the text still moves the caret', (tester) async {
      await pumpPage(tester, text: 'abba');
      controller.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      expect(fieldNode.hasPrimaryFocus, isTrue);
      expect(controller.selection.baseOffset, 3);
    });

    testWidgets('shift keeps the arrows for selecting', (tester) async {
      await pumpPage(tester, text: 'abba');
      controller.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(fieldNode.hasPrimaryFocus, isTrue);
    });
  });
}
