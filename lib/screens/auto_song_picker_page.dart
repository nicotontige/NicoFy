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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nicofy/constants/app_constants.dart';
import 'package:nicofy/extensions/l10n.dart';
import 'package:nicofy/services/data_manager.dart';
import 'package:nicofy/services/settings_manager.dart';
import 'package:nicofy/widgets/custom_bar.dart';
import 'package:nicofy/widgets/mini_player_bottom_space.dart';

/// Turns the automatic song picker on and off, and says which lengths it may
/// pick: songs, mixes, or both.
class AutoSongPickerPage extends StatelessWidget {
  const AutoSongPickerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    final lengths = [
      ('songs', l10n.autoPickSongs, FluentIcons.music_note_1_24_regular),
      ('mixes', l10n.autoPickMixes, FluentIcons.timer_24_regular),
      ('any', l10n.autoPickAny, FluentIcons.apps_list_24_regular),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.automaticSongPicker)),
      body: SingleChildScrollView(
        padding: commonSingleChildScrollViewPadding,
        child: Column(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: playNextSongAutomatically,
              builder: (_, enabled, __) => CustomBar(
                l10n.automaticSongPicker,
                FluentIcons.music_note_2_play_20_regular,
                description: l10n.automaticSongPickerDescription,
                borderRadius: commonCustomBarRadius,
                trailing: Switch(value: enabled, onChanged: _setEnabled),
              ),
            ),
            const SizedBox(height: 20),
            ValueListenableBuilder<bool>(
              valueListenable: playNextSongAutomatically,
              builder: (_, enabled, __) => ValueListenableBuilder<String>(
                valueListenable: autoPickLength,
                builder: (_, selected, __) => Column(
                  children: [
                    for (final (index, (value, name, icon)) in lengths.indexed)
                      CustomBar(
                        name,
                        icon,
                        borderRadius: index == 0
                            ? commonCustomBarRadiusFirst
                            : index == lengths.length - 1
                            ? commonCustomBarRadiusLast
                            : BorderRadius.zero,
                        onTap: enabled ? () => _setLength(value) : null,
                        textColor: enabled
                            ? null
                            : Theme.of(context).disabledColor,
                        trailing: selected == value
                            ? const Icon(FluentIcons.checkmark_20_filled)
                            : null,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const MiniPlayerBottomSpace(),
          ],
        ),
      ),
    );
  }

  void _setEnabled(bool value) {
    addOrUpdateData<bool>('settings', 'playNextSongAutomatically', value);
    playNextSongAutomatically.value = value;
  }

  void _setLength(String value) {
    addOrUpdateData<String>('settings', 'autoPickLength', value);
    autoPickLength.value = value;
  }
}
