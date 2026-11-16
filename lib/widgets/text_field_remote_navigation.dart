/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     NicoFy is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     NicoFy is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     NicoFy is a modified version of Musify by Valeri Gokadze
 *     (https://github.com/gokadzev/Musify).
 *     For more information about NicoFy, please visit:
 *     https://github.com/nicotontige/NicoFy
 */

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Lets a TV remote leave a text field, in every text field of the app.
///
/// A text field keeps the arrow keys to move its caret, so a remote that
/// lands on one, which has nothing but arrows, cannot get out. Placed once
/// above the navigator, this sees the arrows before the text field does:
///
/// * up and down always leave a single-line field; a multiline one only from
///   its first or last character;
/// * left leaves from the start of the text, right from its end, and both
///   at once when the field is empty;
/// * shift or another modifier keeps the key for the text selection.
///
/// Focus moves the way the arrow would have moved it anywhere else, through
/// the nearest [DirectionalFocusIntent] action, so the rail keeps catching
/// left on large screens.
///
/// On top of that, when a remote or a keyboard drives the app, reaching a
/// field no longer pops the on-screen keyboard up, which then took the arrows
/// for itself: select (OK) on the field opens it.
class TextFieldRemoteNavigation extends StatefulWidget {
  const TextFieldRemoteNavigation({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  State<TextFieldRemoteNavigation> createState() =>
      _TextFieldRemoteNavigationState();
}

class _TextFieldRemoteNavigationState extends State<TextFieldRemoteNavigation> {
  FocusNode? _lastFocus;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == _lastFocus) return;
    _lastFocus = focus;
    if (!widget.enabled || !_drivenByKeys) return;
    if (_editableTextOf(focus) == null) return;
    // The field opened the keyboard as it took focus. Sent after it, this
    // closes it again; select reopens it.
    unawaited(
      Future<void>.microtask(
        () => SystemChannels.textInput.invokeMethod<void>('TextInput.hide'),
      ),
    );
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (!widget.enabled || event is KeyUpEvent) return KeyEventResult.ignored;
    final editable = _editableTextOf(FocusManager.instance.primaryFocus);
    if (editable == null) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA) {
      if (event is KeyDownEvent) editable.requestKeyboard();
      return KeyEventResult.handled;
    }

    final direction = _directionOf(key);
    if (direction == null || _modifierPressed) return KeyEventResult.ignored;
    if (!textFieldLetsFocusLeave(
      value: editable.textEditingValue,
      isMultiline: editable.widget.maxLines != 1,
      direction: direction,
    )) {
      return KeyEventResult.ignored;
    }

    // From above the text field, whose own action ignores the arrows.
    final fieldContext = editable.context;
    final intent = DirectionalFocusIntent(direction, ignoreTextFields: false);
    if (Actions.maybeFind<DirectionalFocusIntent>(fieldContext) != null) {
      Actions.invoke(fieldContext, intent);
    } else {
      FocusManager.instance.primaryFocus?.focusInDirection(direction);
    }
    return KeyEventResult.handled;
  }

  static bool get _drivenByKeys =>
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  static bool get _modifierPressed {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed;
  }

  static TraversalDirection? _directionOf(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp) return TraversalDirection.up;
    if (key == LogicalKeyboardKey.arrowDown) return TraversalDirection.down;
    if (key == LogicalKeyboardKey.arrowLeft) return TraversalDirection.left;
    if (key == LogicalKeyboardKey.arrowRight) return TraversalDirection.right;
    return null;
  }

  static EditableTextState? _editableTextOf(FocusNode? focus) =>
      focus?.context?.findAncestorStateOfType<EditableTextState>();

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      child: widget.child,
    );
  }
}

/// Whether an arrow pressed in a text field holding [value] should take focus
/// out of it, rather than move the caret.
bool textFieldLetsFocusLeave({
  required TextEditingValue value,
  required bool isMultiline,
  required TraversalDirection direction,
}) {
  // The keyboard is still putting a word together.
  if (value.composing.isValid && !value.composing.isCollapsed) return false;

  final text = value.text;
  if (text.isEmpty) return true;

  final selection = value.selection;
  final caret = selection.isValid && selection.isCollapsed
      ? selection.baseOffset
      : null;
  final atStart = caret == 0;
  final atEnd = caret == text.length;

  switch (direction) {
    case TraversalDirection.up:
      return !isMultiline || atStart;
    case TraversalDirection.down:
      return !isMultiline || atEnd;
    case TraversalDirection.left:
      return atStart;
    case TraversalDirection.right:
      return atEnd;
  }
}

/// What submitting a search field does with focus. On a touch screen it
/// lets go of the field, which closes the keyboard. Driven by a remote, focus
/// stays on the field, with the keyboard closed: let go, it fell back on the
/// page as a whole, and the remote had to find its way from nowhere.
void releaseTextFieldAfterSubmit(FocusNode node) {
  if (FocusManager.instance.highlightMode == FocusHighlightMode.traditional &&
      node.hasFocus) {
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    return;
  }
  node.unfocus();
}
