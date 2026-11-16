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

import 'package:material_ui/material_ui.dart';
import 'package:nicofy/theme/remote_focus_theme.dart';

/// Lets a TV remote or a keyboard reach [child], which on its own only
/// answers to touch: it takes focus, shows it the remote way (see
/// [RemoteFocusFrame], growing like a tile on the TV home screen), and runs
/// [onActivate] on select or enter.
class RemoteFocusable extends StatelessWidget {
  const RemoteFocusable({
    super.key,
    required this.onActivate,
    required this.child,
    this.borderRadius = 12,
  });

  final VoidCallback onActivate;
  final Widget child;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return RemoteFocusFrame(
      borderRadius: BorderRadius.circular(borderRadius),
      grow: true,
      child: FocusableActionDetector(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onActivate();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}

/// Draws the remote focus outline around [child] while the first focusable
/// widget inside it, an [InkWell] or a [FocusableActionDetector] for
/// instance, has focus. Not while a button nested further in has it: that
/// button shows its own.
///
/// The outline is drawn in the foreground because what is wrapped here is
/// mostly artwork or a coloured box, which would hide an ink highlight
/// painted behind it. With [grow], the child rests slightly smaller and
/// comes up to full size when focused, so that it never spills out of a
/// list that clips it. Touch users see none of it.
class RemoteFocusFrame extends StatefulWidget {
  const RemoteFocusFrame({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.circle = false,
    this.grow = false,
  });

  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final bool circle;
  final bool grow;

  @override
  State<RemoteFocusFrame> createState() => _RemoteFocusFrameState();
}

class _RemoteFocusFrameState extends State<RemoteFocusFrame> {
  final _node = FocusNode(canRequestFocus: false, skipTraversal: true);
  bool _remoteStyle = usesRemoteFocusStyle(FocusManager.instance.highlightMode);
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_update);
    FocusManager.instance.addHighlightModeListener(_onHighlightModeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_update);
    FocusManager.instance.removeHighlightModeListener(_onHighlightModeChanged);
    _node.dispose();
    super.dispose();
  }

  void _onHighlightModeChanged(FocusHighlightMode mode) {
    final remoteStyle = usesRemoteFocusStyle(mode);
    if (remoteStyle != _remoteStyle && mounted) {
      setState(() => _remoteStyle = remoteStyle);
    }
  }

  void _update() {
    final focused = _framesPrimaryFocus();
    if (focused != _focused && mounted) setState(() => _focused = focused);
  }

  /// Whether focus sits on the outermost focusable widget inside the frame.
  bool _framesPrimaryFocus() {
    if (!_node.hasFocus) return false;
    var node = FocusManager.instance.primaryFocus?.parent;
    while (node != null) {
      if (node == _node) return true;
      if (node.canRequestFocus && !node.skipTraversal) return false;
      node = node.parent;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final shown = _remoteStyle && _focused;
    final colorScheme = Theme.of(context).colorScheme;
    // Always there, outline or not: adding a wrapper only when focused
    // would rebuild the child, and lose the very focus being shown.
    Widget framed = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: shown
          ? BoxDecoration(
              border: Border.fromBorderSide(
                RemoteFocusStyle.outline(colorScheme),
              ),
              shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: widget.circle ? null : widget.borderRadius,
            )
          : const BoxDecoration(),
      child: widget.child,
    );
    if (widget.grow) {
      framed = AnimatedScale(
        scale: !_remoteStyle || shown ? 1 : 1 / RemoteFocusStyle.tileScale,
        duration: RemoteFocusStyle.animation,
        child: framed,
      );
    }
    return Focus(
      focusNode: _node,
      canRequestFocus: false,
      skipTraversal: true,
      child: framed,
    );
  }
}
