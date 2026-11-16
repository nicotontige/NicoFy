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
import 'package:nicofy/widgets/remote_focusable.dart';

/// The building blocks of the TV now-playing screen. The Mi Box remote has
/// no play, pause or skip keys, only arrows, OK and back, so the screen is
/// laid out for them, the way Spotify does it on Android TV: the remote
/// lands on play/pause, left and right reach previous and next, up the
/// secondary actions, down the progress bar.

/// How far left or right on the progress bar moves in the song.
const tvSeekStep = Duration(seconds: 10);

/// Keeps the remote on [playFocusNode]: puts it there when the screen opens,
/// and back there whenever focus falls off the screen, which is what
/// happens when the button under it is rebuilt for the next song, or a
/// control disappears. Never while a sheet or a route sits over the screen.
class TvPlayFocusKeeper extends StatefulWidget {
  const TvPlayFocusKeeper({
    super.key,
    required this.playFocusNode,
    required this.child,
    this.isCovered,
  });

  final FocusNode playFocusNode;
  final Widget child;

  /// Whether something shown over the screen (a bottom sheet) has focus to
  /// itself, in which case focus is left alone.
  final bool Function()? isCovered;

  @override
  State<TvPlayFocusKeeper> createState() => _TvPlayFocusKeeperState();
}

class _TvPlayFocusKeeperState extends State<TvPlayFocusKeeper> {
  bool _restoreScheduled = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
    _scheduleRestore(force: true);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    super.dispose();
  }

  /// Focus that rests on a scope rather than on a control was lost.
  bool get _focusLost {
    final primary = FocusManager.instance.primaryFocus;
    return primary == null || primary is FocusScopeNode;
  }

  void _onFocusChanged() {
    if (_focusLost) _scheduleRestore();
  }

  void _scheduleRestore({bool force = false}) {
    if (_restoreScheduled) return;
    _restoreScheduled = true;
    // After the frame, once the rebuilt button has its focus node back.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreScheduled = false;
      if (!mounted || !(force || _focusLost)) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      if (widget.isCovered?.call() ?? false) return;
      final node = widget.playFocusNode;
      if (node.context == null || !node.canRequestFocus) {
        // Still loading, the button is not there yet: try the next frame.
        if (force) _scheduleRestore(force: true);
        return;
      }
      node.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The progress bar of the TV now-playing screen, which a remote can reach:
/// left and right move [tvSeekStep] back or forth, and say so next to it.
/// Up and down leave it as from anywhere else.
///
/// Presses in a row add up from where the last one aimed, not from the
/// player's position, which takes a moment to follow a seek.
class TvSeekBar extends StatefulWidget {
  const TvSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.child,
    this.focusNode,
  });

  final Duration Function() position;
  final Duration Function() duration;
  final ValueChanged<Duration> onSeek;
  final FocusNode? focusNode;

  /// The bar drawn, out of the remote's reach: this widget takes its keys.
  final Widget child;

  @override
  State<TvSeekBar> createState() => _TvSeekBarState();
}

class _TvSeekBarState extends State<TvSeekBar> {
  static const _feedbackDuration = Duration(milliseconds: 1200);

  Duration? _target;

  /// How far the presses in a row have moved, in seconds, for the label.
  int _movedSeconds = 0;
  Timer? _feedbackTimer;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final int direction;
    if (key == LogicalKeyboardKey.arrowRight) {
      direction = 1;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      direction = -1;
    } else {
      return KeyEventResult.ignored;
    }
    _seek(direction);
    return KeyEventResult.handled;
  }

  void _seek(int direction) {
    final duration = widget.duration();
    final from = _target ?? widget.position();
    var target = from + tvSeekStep * direction;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;

    widget.onSeek(target);
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(_feedbackDuration, () {
      if (mounted) {
        setState(() {
          _target = null;
          _movedSeconds = 0;
        });
      }
    });
    setState(() {
      _movedSeconds += (target - from).inSeconds;
      _target = target;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final moved = _movedSeconds;
    final label = moved > 0 ? '+$moved s' : '−${moved.abs()} s';

    return RemoteFocusFrame(
      borderRadius: BorderRadius.circular(16),
      child: Focus(
        focusNode: widget.focusNode,
        onKeyEvent: _onKey,
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            ExcludeFocus(child: widget.child),
            if (_target != null)
              Positioned(
                top: -6,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.inverseSurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: colorScheme.onInverseSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// While [active], the ambient screen is up: the first key pressed only
/// brings the controls back ([onWake]) and does nothing else, not even the
/// press of the button under focus. Back is let through, to leave.
class RemoteWakeGuard extends StatefulWidget {
  const RemoteWakeGuard({
    super.key,
    required this.active,
    required this.onWake,
    required this.child,
  });

  final bool active;
  final VoidCallback onWake;
  final Widget child;

  static bool isBackKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.goBack ||
      key == LogicalKeyboardKey.escape ||
      key == LogicalKeyboardKey.browserBack;

  @override
  State<RemoteWakeGuard> createState() => _RemoteWakeGuardState();
}

class _RemoteWakeGuardState extends State<RemoteWakeGuard> {
  bool _installed = false;

  /// The key that woke the screen, swallowed until it comes back up.
  LogicalKeyboardKey? _swallowing;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(RemoteWakeGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    if (_installed) {
      FocusManager.instance.removeEarlyKeyEventHandler(_onKey);
    }
    super.dispose();
  }

  void _sync() {
    final wanted = widget.active || _swallowing != null;
    if (wanted == _installed) return;
    _installed = wanted;
    if (wanted) {
      FocusManager.instance.addEarlyKeyEventHandler(_onKey);
    } else {
      FocusManager.instance.removeEarlyKeyEventHandler(_onKey);
    }
  }

  KeyEventResult _onKey(KeyEvent event) {
    final swallowing = _swallowing;
    if (swallowing != null) {
      if (event.logicalKey != swallowing) return KeyEventResult.ignored;
      if (event is KeyUpEvent) {
        _swallowing = null;
        // Removing the handler while the manager walks its handlers is not
        // allowed: after this event.
        scheduleMicrotask(() {
          if (mounted) _sync();
        });
      }
      return KeyEventResult.handled;
    }

    if (!widget.active || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (RemoteWakeGuard.isBackKey(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    _swallowing = event.logicalKey;
    widget.onWake();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Opens the now-playing screen by itself after [delay] without a key
/// pressed while music plays, like the ambient screen of a TV. Every key
/// pressed anywhere starts the wait over; so does playback starting again.
///
/// [onIdle] decides whether the moment suits (no dialog, sheet, keyboard…)
/// and does the opening.
class TvIdleWatcher {
  TvIdleWatcher({
    required this.delay,
    required this.isPlaying,
    required this.onIdle,
  });

  final Duration delay;
  final bool Function() isPlaying;
  final VoidCallback onIdle;

  Timer? _timer;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    HardwareKeyboard.instance.addHandler(_onKey);
    restart();
  }

  /// Starts the wait over, as a key press does.
  void restart() {
    if (!_started) return;
    _timer?.cancel();
    _timer = Timer(delay, _onTimeout);
  }

  void dispose() {
    _timer?.cancel();
    if (_started) HardwareKeyboard.instance.removeHandler(_onKey);
    _started = false;
  }

  bool _onKey(KeyEvent event) {
    restart();
    // Only watching: the key goes on to wherever it was going.
    return false;
  }

  void _onTimeout() {
    _timer = null;
    // Paused: wait for playback to start again, which calls [restart].
    if (isPlaying()) onIdle();
  }
}
