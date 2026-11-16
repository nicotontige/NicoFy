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
import 'package:material_ui/material_ui.dart';
import 'package:nicofy/main.dart';
import 'package:nicofy/services/common_services.dart';
import 'package:nicofy/services/lyrics/lyrics_models.dart';
import 'package:nicofy/services/settings_manager.dart';
import 'package:nicofy/widgets/flip_card.dart';
import 'package:nicofy/widgets/now_playing/bottom_actions_row.dart';
import 'package:nicofy/widgets/now_playing/chapter_bar.dart';
import 'package:nicofy/widgets/now_playing/marquee_text_widget.dart';
import 'package:nicofy/widgets/now_playing/now_playing_artwork.dart';
import 'package:nicofy/widgets/now_playing/now_playing_controls.dart';
import 'package:nicofy/widgets/now_playing/synced_lyrics_view.dart';
import 'package:nicofy/widgets/now_playing/tv_remote.dart';
import 'package:nicofy/widgets/playback_icon_button.dart';
import 'package:nicofy/widgets/position_slider.dart';
import 'package:nicofy/widgets/remote_focusable.dart';
import 'package:nicofy/widgets/song_artwork.dart';

/// The now-playing screen of a TV, laid out for a remote that only has
/// arrows: from top to bottom, what plays, the secondary actions (like,
/// radio, queue, lyrics…), the transport row with play/pause in the middle,
/// then the progress bar. The remote rests on play/pause, so up is the
/// actions, down the progress bar, left and right previous and next.
///
/// [ambient] is the calm form the idle timer opens: big artwork, title,
/// artist, progress and the synced lyrics when there are any, and nothing
/// for the remote to land on.
class TvNowPlayingLayout extends StatelessWidget {
  const TvNowPlayingLayout({
    super.key,
    required this.metadata,
    required this.lyricsController,
    required this.playFocusNode,
    required this.ambient,
  });

  final MediaItem metadata;
  final FlipCardController lyricsController;
  final FocusNode playFocusNode;
  final bool ambient;

  bool get _isLive => metadata.extras?['isLive'] ?? false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(40, ambient ? 32 : 8, 40, 24),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Center(
              child: ambient
                  ? SongArtworkWidget(
                      metadata: metadata,
                      size: size.height * 0.72,
                      errorWidgetIconSize: size.height / 6,
                      borderRadius: 24,
                    )
                  : NowPlayingArtwork(
                      size: size,
                      metadata: metadata,
                      lyricsController: lyricsController,
                      imageSize: size.height * 0.6,
                    ),
            ),
          ),
          const SizedBox(width: 40),
          Expanded(
            flex: 5,
            child: ambient
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ..._buildTitle(context, colorScheme),
                      ..._buildAmbient(),
                    ],
                  )
                // Scrolls rather than overflows if a large font setting
                // makes it taller than the screen; focus keeps it in view.
                : Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ..._buildTitle(context, colorScheme),
                          ..._buildControls(context),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTitle(BuildContext context, ColorScheme colorScheme) {
    final artist = metadata.artist;
    final artistText = artist == null
        ? null
        : MarqueeTextWidget(
            text: artist,
            fontColor: colorScheme.onSurfaceVariant,
            fontSize: ambient ? 24 : 20,
            fontWeight: FontWeight.w500,
          );
    return [
      MarqueeTextWidget(
        text: metadata.title,
        fontColor: colorScheme.secondary,
        fontSize: ambient ? 36 : 28,
        fontWeight: FontWeight.bold,
      ),
      const SizedBox(height: 6),
      // The artist opens with a tap on a phone; here OK on it does.
      if (artistText != null)
        if (!ambient && canOpenNowPlayingArtist(metadata))
          RemoteFocusable(
            onActivate: () => openNowPlayingArtist(context, metadata),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: artistText,
            ),
          )
        else
          artistText,
    ];
  }

  List<Widget> _buildControls(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return [
      const SizedBox(height: 20),
      BottomActionsRow(
        metadata: metadata,
        iconSize: 26,
        // The queue button stays: the queue is not beside the controls here.
        isLargeScreen: false,
        lyricsController: lyricsController,
      ),
      const SizedBox(height: 20),
      if (_isLive)
        // A radio station has no songs to skip, but it pauses.
        Center(
          child: PlaybackIconButton(
            focusNode: playFocusNode,
            iconSize: 36,
            iconColor: colorScheme.onPrimary,
            backgroundColor: colorScheme.primary,
          ),
        )
      else ...[
        PlayerControlButtons(
          metadata: metadata,
          iconSize: 40,
          miniIconSize: 24,
          playFocusNode: playFocusNode,
        ),
        const SizedBox(height: 12),
        TvSeekBar(
          position: () => audioHandler.currentPositionData.position,
          duration: () => audioHandler.currentPositionData.duration,
          onSeek: audioHandler.seek,
          child: const PositionSlider(),
        ),
        const ChapterBar(),
      ],
    ];
  }

  List<Widget> _buildAmbient() => [
    const SizedBox(height: 16),
    Expanded(child: _AmbientLyrics(metadata: metadata)),
    const SizedBox(height: 16),
    if (!_isLive) const ExcludeFocus(child: PositionSlider()),
  ];
}

/// The synced lyrics of the ambient screen, scrolling with the song. Plain
/// lyrics or none at all leave the space empty: nobody reads a block of
/// text from the couch.
class _AmbientLyrics extends StatefulWidget {
  const _AmbientLyrics({required this.metadata});

  final MediaItem metadata;

  @override
  State<_AmbientLyrics> createState() => _AmbientLyricsState();
}

class _AmbientLyricsState extends State<_AmbientLyrics> {
  String? _key;
  Future<Lyrics?>? _lyrics;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(_AmbientLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolve();
  }

  void _resolve() {
    final metadata = widget.metadata;
    final key = '${metadata.artist} - ${metadata.title}';
    if (key == _key) return;
    _key = key;
    _lyrics = offlineMode.value || !syncedLyricsEnabled.value
        ? null
        : getSongLyricsResult(
            metadata.artist,
            metadata.title,
            duration: metadata.duration,
            album: metadata.album,
          );
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = _lyrics;
    if (lyrics == null) return const SizedBox.shrink();
    return FutureBuilder<Lyrics?>(
      future: lyrics,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null || !data.isSynced) return const SizedBox.shrink();
        // Lines seek when tapped; the remote has nothing to do in there.
        return ExcludeFocus(
          child: SyncedLyricsView(key: ValueKey(_key), lyrics: data),
        );
      },
    );
  }
}
