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

/// Lets a TV remote or a keyboard reach [child], which on its own only
/// answers to touch: it takes focus, draws an outline on top of it while
/// focused, and runs [onActivate] on select or enter.
///
/// The outline is drawn in the foreground because the children wrapped here
/// are mostly artwork, which would hide an ink highlight painted behind them.
class RemoteFocusable extends StatefulWidget {
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
  State<RemoteFocusable> createState() => _RemoteFocusableState();
}

class _RemoteFocusableState extends State<RemoteFocusable> {
  bool _showOutline = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onActivate();
            return null;
          },
        ),
      },
      // Only reported in keyboard highlight mode, so touch users never see it.
      onShowFocusHighlight: (show) => setState(() => _showOutline = show),
      child: Container(
        foregroundDecoration: _showOutline
            ? BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(widget.borderRadius),
              )
            : null,
        child: widget.child,
      ),
    );
  }
}
