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
import 'package:nicofy/main.dart';
import 'package:nicofy/screens/remote_player_page.dart';
import 'package:nicofy/utilities/device_identity.dart';
import 'package:nicofy/utilities/flutter_bottom_sheet.dart'
    show isBottomSheetOpen;
import 'package:nicofy/widgets/flip_card.dart';
import 'package:nicofy/widgets/now_playing/bottom_actions_row.dart';
import 'package:nicofy/widgets/now_playing/now_playing_artwork.dart';
import 'package:nicofy/widgets/now_playing/now_playing_controls.dart';
import 'package:nicofy/widgets/now_playing/tv_now_playing_layout.dart';
import 'package:nicofy/widgets/now_playing/tv_remote.dart';
import 'package:nicofy/widgets/queue_list_view.dart';
import 'package:nicofy/widgets/remote_control/remote_device_picker.dart';

/// Opens the now-playing screen over everything, sliding up from the bottom.
/// With [ambient], in its calm TV form, as the idle timer opens it.
void openNowPlaying(BuildContext context, {bool ambient = false}) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      pageBuilder: (context, animation, _) => NowPlayingPage(ambient: ambient),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final tween = Tween(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeInOut));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    ),
  );
}

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key, this.ambient = false});

  /// Opened by the TV idle timer: big artwork and lyrics, no controls until
  /// a key is pressed.
  final bool ambient;

  /// The screen open at the moment, if any.
  static _NowPlayingPageState? _open;

  /// Whether a now-playing screen is open, covered or not. The idle timer
  /// then leaves it to that screen rather than opening a second one.
  static bool get isOpen => _open?.mounted ?? false;

  /// Turns the open screen ambient, if it is the one on show: not under a
  /// dialog or with a sheet open.
  static void showAmbientIfOnTop() => _open?._enterAmbientIfOnTop();

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  final _lyricsController = FlipCardController();

  /// Where the remote rests on a TV.
  final _playFocusNode = FocusNode(debugLabel: 'Play/pause');

  late bool _ambient = widget.ambient;

  @override
  void initState() {
    super.initState();
    NowPlayingPage._open = this;
  }

  @override
  void dispose() {
    if (NowPlayingPage._open == this) NowPlayingPage._open = null;
    _playFocusNode.dispose();
    super.dispose();
  }

  void _enterAmbientIfOnTop() {
    if (!mounted || _ambient || isBottomSheetOpen.value) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    setState(() => _ambient = true);
  }

  /// The first key after the ambient screen only brings the controls back,
  /// with the remote on play/pause.
  void _wake() {
    setState(() => _ambient = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _playFocusNode.canRequestFocus) {
        _playFocusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isTelevision) return _buildTv(context);
    final size = MediaQuery.sizeOf(context);
    final isLargeScreen = size.width > 800 && size.height > 600;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = size.width;
    final baseIconSize = screenWidth < 360
        ? 36.0
        : screenWidth < 400
        ? 40.0
        : 44.0;
    final miniIconSize = screenWidth < 360 ? 18.0 : 22.0;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: StreamBuilder<MediaItem?>(
          stream: audioHandler.mediaItem,
          builder: (context, snapshot) {
            if (snapshot.data == null || !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final metadata = snapshot.data!;
            return Column(
              children: [
                _buildAppBar(context, colorScheme),
                Expanded(
                  child: isLargeScreen
                      ? _DesktopLayout(
                          metadata: metadata,
                          size: size,
                          adjustedIconSize: baseIconSize,
                          adjustedMiniIconSize: miniIconSize,
                          lyricsController: _lyricsController,
                        )
                      : _MobileLayout(
                          metadata: metadata,
                          size: size,
                          adjustedIconSize: baseIconSize,
                          adjustedMiniIconSize: miniIconSize,
                          isLargeScreen: isLargeScreen,
                          lyricsController: _lyricsController,
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// On a TV, the screen the remote is made for, see [TvNowPlayingLayout].
  Widget _buildTv(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return RemoteWakeGuard(
      active: _ambient,
      onWake: _wake,
      child: TvPlayFocusKeeper(
        playFocusNode: _playFocusNode,
        isCovered: () => isBottomSheetOpen.value || _ambient,
        child: Scaffold(
          backgroundColor: colorScheme.surface,
          body: SafeArea(
            child: StreamBuilder<MediaItem?>(
              stream: audioHandler.mediaItem,
              builder: (context, snapshot) {
                final metadata = snapshot.data;
                if (metadata == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Column(
                  children: [
                    if (!_ambient) _buildAppBar(context, colorScheme),
                    Expanded(
                      child: TvNowPlayingLayout(
                        metadata: metadata,
                        lyricsController: _lyricsController,
                        playFocusNode: _playFocusNode,
                        ambient: _ambient,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, ColorScheme colorScheme) {
    final style = IconButton.styleFrom(
      backgroundColor: colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            iconSize: 26,
            icon: const Icon(FluentIcons.chevron_down_24_regular),
            style: style,
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          // Controlling another device takes this page's place: its buttons
          // would drive this device's player.
          RemoteDevicesButton(
            style: style,
            onConnected: (context) => openRemotePlayer(context, replace: true),
          ),
        ],
      ),
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({
    required this.metadata,
    required this.size,
    required this.adjustedIconSize,
    required this.adjustedMiniIconSize,
    required this.lyricsController,
  });
  final MediaItem metadata;
  final Size size;
  final double adjustedIconSize;
  final double adjustedMiniIconSize;
  final FlipCardController lyricsController;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 16),
                Expanded(
                  flex: 5,
                  child: Center(
                    child: NowPlayingArtwork(
                      size: size,
                      metadata: metadata,
                      lyricsController: lyricsController,
                    ),
                  ),
                ),
                if (!(metadata.extras?['isLive'] ?? false))
                  Expanded(
                    flex: 4,
                    child: NowPlayingControls(
                      size: size,
                      audioId: metadata.extras?['ytid'],
                      adjustedIconSize: adjustedIconSize,
                      adjustedMiniIconSize: adjustedMiniIconSize,
                      metadata: metadata,
                    ),
                  ),
                BottomActionsRow(
                  metadata: metadata,
                  iconSize: adjustedMiniIconSize,
                  isLargeScreen: true,
                  lyricsController: lyricsController,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        const Expanded(child: QueueWidget()),
      ],
    );
  }
}

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({
    required this.metadata,
    required this.size,
    required this.adjustedIconSize,
    required this.adjustedMiniIconSize,
    required this.isLargeScreen,
    required this.lyricsController,
  });
  final MediaItem metadata;
  final Size size;
  final double adjustedIconSize;
  final double adjustedMiniIconSize;
  final bool isLargeScreen;
  final FlipCardController lyricsController;

  @override
  Widget build(BuildContext context) {
    final isLandscape = size.width > size.height;

    if (isLandscape) {
      return _buildLandscapeLayout(context);
    }
    return _buildPortraitLayout(context);
  }

  Widget _buildPortraitLayout(BuildContext context) {
    final isLive = metadata.extras?['isLive'] ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Expanded(
            flex: 5,
            child: Center(
              child: NowPlayingArtwork(
                size: size,
                metadata: metadata,
                lyricsController: lyricsController,
              ),
            ),
          ),
          if (!isLive)
            Expanded(
              flex: 4,
              child: NowPlayingControls(
                size: size,
                audioId: metadata.extras?['ytid'],
                adjustedIconSize: adjustedIconSize,
                adjustedMiniIconSize: adjustedMiniIconSize,
                metadata: metadata,
              ),
            ),
          BottomActionsRow(
            metadata: metadata,
            iconSize: adjustedMiniIconSize,
            isLargeScreen: isLargeScreen,
            lyricsController: lyricsController,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildLandscapeLayout(BuildContext context) {
    final isLive = metadata.extras?['isLive'] ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Center(
              child: NowPlayingArtwork(
                size: size,
                metadata: metadata,
                lyricsController: lyricsController,
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!isLive)
                  Expanded(
                    child: NowPlayingControls(
                      size: size,
                      audioId: metadata.extras?['ytid'],
                      adjustedIconSize: adjustedIconSize,
                      adjustedMiniIconSize: adjustedMiniIconSize,
                      metadata: metadata,
                    ),
                  ),
                BottomActionsRow(
                  metadata: metadata,
                  iconSize: adjustedMiniIconSize,
                  isLargeScreen: isLargeScreen,
                  lyricsController: lyricsController,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
