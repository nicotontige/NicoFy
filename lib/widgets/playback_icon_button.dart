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

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nicofy/extensions/l10n.dart';
import 'package:nicofy/main.dart';
import 'package:nicofy/widgets/remote_focusable.dart';

Widget buildPlaybackIconButton(
  double iconSize,
  Color iconColor,
  Color backgroundColor, {
  EdgeInsets? padding,
  FocusNode? focusNode,
}) {
  return StreamBuilder<PlaybackState>(
    stream: audioHandler.playbackState.distinct((previous, current) {
      // Only rebuild if relevant state changes
      return previous.playing == current.playing &&
          previous.processingState == current.processingState;
    }),
    builder: (context, snapshot) {
      final playbackState = snapshot.data;
      final processingState = playbackState?.processingState;
      final isPlaying = playbackState?.playing ?? false;

      Widget iconWidget;
      VoidCallback? onPressed;
      String? semanticLabel;

      if (processingState == AudioProcessingState.loading ||
          processingState == AudioProcessingState.buffering) {
        iconWidget = SizedBox(
          width: iconSize,
          height: iconSize,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(iconColor),
          ),
        );
        // A disabled button drops focus, and the remote would lose its place
        // on every change of song: one that keeps focus does nothing instead.
        onPressed = focusNode == null ? null : () {};
        semanticLabel = context.l10n!.loading;
      } else if (processingState == AudioProcessingState.completed) {
        iconWidget = Icon(
          FluentIcons.arrow_counterclockwise_24_regular,
          color: iconColor,
          size: iconSize,
        );
        onPressed = () => audioHandler.playAgain();
        semanticLabel = context.l10n!.replay;
      } else {
        iconWidget = Icon(
          isPlaying
              ? FluentIcons.pause_24_regular
              : FluentIcons.play_24_regular,
          color: iconColor,
          size: iconSize,
        );
        onPressed = isPlaying ? audioHandler.pause : audioHandler.play;
        semanticLabel = isPlaying ? context.l10n!.pause : context.l10n!.play;
      }

      return RemoteFocusFrame(
        circle: true,
        child: RawMaterialButton(
          focusNode: focusNode,
          elevation: 0,
          onPressed: onPressed,
          fillColor: backgroundColor,
          splashColor: Colors.transparent,
          padding: padding ?? EdgeInsets.all(iconSize * 0.35),
          shape: const CircleBorder(),
          constraints: BoxConstraints.tightFor(
            width: iconSize * 2,
            height: iconSize * 2,
          ),
          materialTapTargetSize: MaterialTapTargetSize.padded,
          child: Semantics(
            label: semanticLabel,
            button: true,
            child: iconWidget,
          ),
        ),
      );
    },
  );
}

class PlaybackIconButton extends StatelessWidget {
  const PlaybackIconButton({
    super.key,
    required this.iconSize,
    required this.iconColor,
    required this.backgroundColor,
    this.padding,
    this.focusNode,
  });

  final double iconSize;
  final Color iconColor;
  final Color backgroundColor;
  final EdgeInsets? padding;

  /// Kept by the TV now-playing screen, where the remote rests on this
  /// button; the button then stays focusable while a song loads.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return buildPlaybackIconButton(
      iconSize,
      iconColor,
      backgroundColor,
      padding: padding,
      focusNode: focusNode,
    );
  }
}
