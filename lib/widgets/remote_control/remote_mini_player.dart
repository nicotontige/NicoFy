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
import 'package:nicofy/extensions/l10n.dart';
import 'package:nicofy/screens/remote_player_page.dart';
import 'package:nicofy/services/remote_control/remote_control_controller.dart';
import 'package:nicofy/services/remote_control/remote_protocol.dart';
import 'package:nicofy/widgets/mini_player.dart';

/// The mini player while this device controls another: what plays there,
/// play/pause and next, and a tap opens [RemotePlayerPage].
class RemoteMiniPlayer extends StatelessWidget {
  const RemoteMiniPlayer({super.key, required this.remote});

  final RemoteControlState remote;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    final colorScheme = Theme.of(context).colorScheme;
    final snapshot = remote.snapshot;
    final track = snapshot != null && snapshot.isActive ? snapshot.track : null;
    final controller = RemoteControlController.instance;

    final title = switch (remote.status) {
      RemoteLinkStatus.connecting => l10n.remoteConnecting(remote.name),
      RemoteLinkStatus.unreachable => l10n.remoteUnreachable(remote.name),
      RemoteLinkStatus.failed => l10n.remoteErrorFailed(remote.name),
      RemoteLinkStatus.connected =>
        track?.title ?? l10n.remoteNothingPlaying(remote.name),
    };
    final loading =
        snapshot?.processing == RemoteProcessing.loading ||
        snapshot?.processing == RemoteProcessing.buffering;

    return Material(
      color: colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => openRemotePlayer(context),
        child: SizedBox(
          height: MiniPlayer.playerHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                if (track != null)
                  RemoteArtwork(url: track.artworkUrl, size: 52)
                else
                  SizedBox(
                    width: 52,
                    child: Icon(
                      FluentIcons.cast_24_filled,
                      color: colorScheme.primary,
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.secondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            FluentIcons.cast_24_filled,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              l10n.remotePlayingOn(remote.name),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colorScheme.primary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (track != null &&
                    remote.status == RemoteLinkStatus.connected) ...[
                  if (loading)
                    const SizedBox(
                      width: 48,
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    )
                  else
                    IconButton(
                      onPressed: controller.togglePlay,
                      icon: Icon(
                        snapshot!.playing
                            ? FluentIcons.pause_24_filled
                            : FluentIcons.play_24_filled,
                        color: colorScheme.primary,
                      ),
                    ),
                  if (snapshot!.canNext)
                    IconButton(
                      onPressed: controller.next,
                      icon: Icon(
                        FluentIcons.next_24_filled,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
