/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     Musify is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     Musify is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about Musify, including how to contribute,
 *     please visit: https://github.com/gokadzev/Musify
 */

import 'package:material_ui/material_ui.dart';

PersistentBottomSheetController? _currentBottomSheetController;

PersistentBottomSheetController? showCustomBottomSheet(
  BuildContext context,
  Widget content,
) {
  final size = MediaQuery.sizeOf(context);
  final colorScheme = Theme.of(context).colorScheme;

  final controller = showBottomSheet(
    enableDrag: true,
    context: context,
    builder: (context) => _SheetFocus(
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: size.width * 0.92,
                maxHeight: size.height * 0.65,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16),
                child: content,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  _currentBottomSheetController = controller;
  controller.closed.whenComplete(() {
    if (_currentBottomSheetController == controller) {
      _currentBottomSheetController = null;
    }
  });

  return controller;
}

void closeCurrentBottomSheet() {
  try {
    _currentBottomSheetController?.close();
  } catch (_) {}
  _currentBottomSheetController = null;
}

/// The sheet is not a route, so opening it leaves focus on the page behind,
/// out of reach of a TV remote. Move focus onto its first item and keep the
/// arrow keys inside it until it closes.
class _SheetFocus extends StatefulWidget {
  const _SheetFocus({required this.child});

  final Widget child;

  @override
  State<_SheetFocus> createState() => _SheetFocusState();
}

class _SheetFocusState extends State<_SheetFocus> {
  final _scopeNode = FocusScopeNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scopeNode.traversalDescendants.firstOrNull?.requestFocus();
    });
  }

  @override
  void dispose() {
    _scopeNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(node: _scopeNode, child: widget.child);
  }
}
