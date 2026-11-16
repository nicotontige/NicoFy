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

/// The long press of a TV remote: holding select (OK) on [focusNode].
///
/// Flutter never turns a held key into a long press, so this times the key
/// itself. A short press runs [onPress] when the key comes back up, a press
/// held for [holdDuration] runs [onHold] at once, without waiting for the
/// release, the way a remote's long press behaves elsewhere on Android TV.
///
/// Only presses made while [focusNode] itself has focus count: a button
/// nested inside [child] keeps its own select key.
class RemoteHoldDetector extends StatefulWidget {
  const RemoteHoldDetector({
    super.key,
    required this.focusNode,
    required this.onPress,
    required this.onHold,
    required this.child,
    this.holdDuration = const Duration(milliseconds: 500),
  });

  final FocusNode focusNode;
  final VoidCallback onPress;
  final VoidCallback onHold;
  final Widget child;
  final Duration holdDuration;

  static bool isSelectKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButtonA;

  @override
  State<RemoteHoldDetector> createState() => _RemoteHoldDetectorState();
}

class _RemoteHoldDetectorState extends State<RemoteHoldDetector> {
  Timer? _holdTimer;
  LogicalKeyboardKey? _pressedKey;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (!RemoteHoldDetector.isSelectKey(event.logicalKey)) {
      return KeyEventResult.ignored;
    }

    if (event is KeyDownEvent) {
      if (FocusManager.instance.primaryFocus != widget.focusNode) {
        return KeyEventResult.ignored;
      }
      _pressedKey = event.logicalKey;
      _holdTimer?.cancel();
      _holdTimer = Timer(widget.holdDuration, _onHeld);
      return KeyEventResult.handled;
    }

    if (event.logicalKey != _pressedKey) return KeyEventResult.ignored;
    if (event is KeyRepeatEvent) return KeyEventResult.handled;

    // Key up before the hold fired: a plain press.
    _pressedKey = null;
    final wasShortPress = _holdTimer?.isActive ?? false;
    _holdTimer?.cancel();
    _holdTimer = null;
    if (wasShortPress) widget.onPress();
    return KeyEventResult.handled;
  }

  void _onHeld() {
    final key = _pressedKey;
    _pressedKey = null;
    _holdTimer = null;
    if (key == null || !mounted) return;
    _swallowUntilReleased(key);
    widget.onHold();
  }

  void _cancel() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _pressedKey = null;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      onFocusChange: (hasFocus) {
        if (!hasFocus) _cancel();
      },
      child: widget.child,
    );
  }
}

/// [RemoteHoldDetector.onHold] usually opens a menu while the key is still
/// down. Its repeats, and its release, would then land on the menu's first
/// item and pick it, so they are dropped before they reach the focus tree.
void _swallowUntilReleased(LogicalKeyboardKey key) {
  late KeyEventResult Function(KeyEvent) handler;
  handler = (event) {
    if (event.logicalKey != key) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      // The release went somewhere else; this is a new press.
      FocusManager.instance.removeEarlyKeyEventHandler(handler);
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) {
      FocusManager.instance.removeEarlyKeyEventHandler(handler);
    }
    return KeyEventResult.handled;
  };
  FocusManager.instance.addEarlyKeyEventHandler(handler);
}
