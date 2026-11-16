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
import 'package:nicofy/utilities/device_identity.dart';

/// How focus looks once a remote or a keyboard is in hand: Material's own
/// focus tint is a faint wash, invisible from a couch three metres away.
/// The focused element gets a thick outline in the text colour (white on the
/// dark theme, near black on the light one) over a clearly lighter fill, and
/// artwork tiles grow a little, as on the Android TV home screen.
abstract final class RemoteFocusStyle {
  static const double outlineWidth = 3;
  static const double tileScale = 1.05;
  static const Duration animation = Duration(milliseconds: 120);

  static Color outlineColor(ColorScheme colorScheme) => colorScheme.onSurface;

  static Color fillColor(ColorScheme colorScheme) =>
      colorScheme.onSurface.withValues(alpha: 0.2);

  static BorderSide outline(ColorScheme colorScheme) =>
      BorderSide(color: outlineColor(colorScheme), width: outlineWidth);
}

/// Whether focus should be drawn the remote way. On a TV always; elsewhere
/// as soon as a key moved focus, which is when Flutter itself starts showing
/// it. A finger on a phone keeps the touch look untouched.
bool usesRemoteFocusStyle(FocusHighlightMode mode) =>
    isTelevision || mode == FocusHighlightMode.traditional;

/// [theme] with every focused state drawn the remote way: buttons, chips,
/// switches, sliders, check boxes, list tiles, the navigation rail and text
/// fields. Only the focused state changes, so nothing looks different until
/// something has focus.
ThemeData withRemoteFocusStyle(ThemeData theme) {
  final colorScheme = theme.colorScheme;
  final outline = RemoteFocusStyle.outline(colorScheme);
  final fill = RemoteFocusStyle.fillColor(colorScheme);
  final halo = RemoteFocusStyle.outlineColor(colorScheme)
      .withValues(alpha: 0.35);

  bool isFocused(Set<WidgetState> states) =>
      states.contains(WidgetState.focused);

  // Null outside the focused state, so each button keeps its own look there.
  final buttonStyle = ButtonStyle(
    side: WidgetStateProperty.resolveWith(
      (states) => isFocused(states) ? outline : null,
    ),
    overlayColor: WidgetStateProperty.resolveWith(
      (states) => isFocused(states) ? fill : null,
    ),
  );
  final focusHalo = WidgetStateProperty.resolveWith<Color?>(
    (states) => isFocused(states) ? halo : null,
  );

  return theme.copyWith(
    // InkWell, ListTile, menu items and the rail destinations tint with it.
    focusColor: fill,
    iconButtonTheme: IconButtonThemeData(style: buttonStyle),
    textButtonTheme: TextButtonThemeData(style: buttonStyle),
    filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
    elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
    segmentedButtonTheme: SegmentedButtonThemeData(style: buttonStyle),
    chipTheme: theme.chipTheme.copyWith(
      side: WidgetStateBorderSide.resolveWith(
        (states) => isFocused(states) ? outline : null,
      ),
    ),
    switchTheme: theme.switchTheme.copyWith(overlayColor: focusHalo),
    checkboxTheme: theme.checkboxTheme.copyWith(overlayColor: focusHalo),
    radioTheme: theme.radioTheme.copyWith(overlayColor: focusHalo),
    sliderTheme: theme.sliderTheme.copyWith(overlayColor: halo),
    // The tint follows a rounded tile rather than a hard box.
    listTileTheme: theme.listTileTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: outline,
      ),
    ),
  );
}
