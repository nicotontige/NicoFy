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
import 'package:nicofy/extensions/l10n.dart';
import 'package:nicofy/services/playlist_download_service.dart';
import 'package:nicofy/utilities/flutter_toast.dart';
import 'package:nicofy/widgets/confirmation_dialog.dart';

void showRemoveOfflinePlaylistDialog(BuildContext context, String playlistId) {
  showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return ConfirmationDialog(
        confirmationMessage: context.l10n!.removeOfflinePlaylistConfirm,
        submitMessage: context.l10n!.remove,
        isDangerous: true,
        onCancel: () => Navigator.pop(context),
        onSubmit: () {
          offlinePlaylistService.removeOfflinePlaylist(playlistId);
          Navigator.pop(context);
          showToast(context, context.l10n!.playlistRemovedFromOffline);
        },
      );
    },
  );
}
