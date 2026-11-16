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

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nicofy/extensions/l10n.dart';
import 'package:nicofy/services/remote_control/remote_control_controller.dart';
import 'package:nicofy/services/remote_control/remote_protocol.dart';
import 'package:nicofy/services/router_service.dart';
import 'package:nicofy/utilities/flutter_toast.dart';
import 'package:nicofy/utilities/formatter.dart';
import 'package:nicofy/widgets/confirmation_dialog.dart';
import 'package:nicofy/widgets/no_artwork_cube.dart';
import 'package:nicofy/widgets/popup_menu_item.dart';
import 'package:nicofy/widgets/queue_list_view.dart';
import 'package:nicofy/widgets/remote_control/remote_device_picker.dart';
import 'package:nicofy/widgets/song_bar.dart';

/// Opens the player of the device this one controls, in place of the
/// current page when [replace] is set.
void openRemotePlayer(BuildContext context, {bool replace = false}) {
  final navigator = Navigator.of(context);
  unawaited(
    (replace ? navigator.pushReplacement : navigator.push)(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, _) => const RemotePlayerPage(),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        transitionsBuilder: (context, animation, _, child) => SlideTransition(
          position: animation.drive(
            Tween(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeInOut)),
          ),
          child: child,
        ),
      ),
    ),
  );
}

/// Artwork from the other device: a web address, or the placeholder.
class RemoteArtwork extends StatelessWidget {
  const RemoteArtwork({
    super.key,
    required this.url,
    required this.size,
    this.radius = 14,
  });

  final String? url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = NullArtworkWidget(
      size: size,
      iconSize: size * 0.4,
      borderRadius: radius,
    );
    final url = this.url;
    if (url == null) return placeholder;
    return CachedNetworkImage(
      imageUrl: url,
      width: size,
      height: size,
      imageBuilder: (_, image) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image(
          image: image,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
      placeholder: (_, __) => placeholder,
      errorWidget: (_, __, ___) => placeholder,
    );
  }
}

String _time(Duration duration) => formatDuration(duration.inSeconds);

/// The full player, in remote mode: shows and drives what plays on the
/// device this one controls.
class RemotePlayerPage extends StatefulWidget {
  const RemotePlayerPage({super.key});

  @override
  State<RemotePlayerPage> createState() => _RemotePlayerPageState();
}

class _RemotePlayerPageState extends State<RemotePlayerPage> {
  final _controller = RemoteControlController.instance;
  Timer? _ticker;
  double? _dragging;

  /// One per queue tile, as in the local queue.
  final Map<String, FocusNode> _tileFocusNodes = {};

  @override
  void initState() {
    super.initState();
    _controller.state.addListener(_onState);
    // The position moves between two refreshes.
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final snapshot = _controller.state.value?.snapshot;
      if (mounted && (snapshot?.playing ?? false)) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.state.removeListener(_onState);
    for (final node in _tileFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _onState() {
    if (!mounted) return;
    // Disconnected: there is nothing left to show here.
    if (_controller.state.value == null) {
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      if (route.isCurrent) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).removeRoute(route);
      }
      return;
    }
    setState(() {});
  }

  Future<void> _retry() async {
    final remote = _controller.state.value;
    if (remote == null) return;
    final failure = await _controller.retry();
    if (failure != null && mounted) {
      showToast(
        context,
        remoteFailureMessage(context.l10n!, failure, remote.name),
        icon: FluentIcons.error_circle_24_regular,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final remote = _controller.state.value;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: remote == null
            ? const SizedBox.shrink()
            : Column(
                children: [
                  _buildAppBar(colorScheme),
                  _Banner(remote: remote),
                  Expanded(child: _buildBody(context, remote)),
                ],
              ),
      ),
    );
  }

  Widget _buildAppBar(ColorScheme colorScheme) {
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
          RemoteDevicesButton(style: style, onConnected: (_) {}),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, RemoteControlState remote) {
    final l10n = context.l10n!;
    switch (remote.status) {
      case RemoteLinkStatus.connecting:
        return _Message(
          icon: FluentIcons.cast_24_regular,
          text: l10n.remoteConnecting(remote.name),
          busy: true,
        );
      case RemoteLinkStatus.failed:
        return _Message(
          icon: FluentIcons.error_circle_24_regular,
          text: remoteFailureMessage(
            l10n,
            remote.failure ?? RemoteFailure.failed,
            remote.name,
          ),
          actions: [
            FilledButton(onPressed: _retry, child: Text(l10n.remoteRetry)),
          ],
        );
      case RemoteLinkStatus.connected:
      case RemoteLinkStatus.unreachable:
        final snapshot = remote.snapshot;
        if (snapshot == null || !snapshot.isActive) {
          return _Message(
            icon: FluentIcons.speaker_2_24_regular,
            text: l10n.remoteNothingPlaying(remote.name),
          );
        }
        return _buildPlayer(context, remote, snapshot);
    }
  }

  Widget _buildPlayer(
    BuildContext context,
    RemoteControlState remote,
    RemoteSnapshot snapshot,
  ) {
    final l10n = context.l10n!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final track = snapshot.track!;
    final width = MediaQuery.sizeOf(context).width;
    final artSize = (width - 80).clamp(120.0, 320.0);
    final duration = snapshot.durationMs == null
        ? null
        : Duration(milliseconds: snapshot.durationMs!);
    final position = _controller.position;
    final max = duration?.inMilliseconds.toDouble() ?? 0;
    final value = (_dragging ?? position.inMilliseconds.toDouble()).clamp(
      0.0,
      max > 0 ? max : 0.0,
    );
    final loading =
        snapshot.processing == RemoteProcessing.loading ||
        snapshot.processing == RemoteProcessing.buffering;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          sliver: SliverList.list(
            children: [
              if (remote.status == RemoteLinkStatus.unreachable)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(
                        FluentIcons.wifi_warning_24_regular,
                        color: colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.remoteUnreachable(remote.name),
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              Center(
                child: RemoteArtwork(
                  url: track.artworkUrl,
                  size: artSize,
                  radius: 20,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                track.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colorScheme.secondary,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (track.artist.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    track.artist,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 12),
              if (!track.isLive && max > 0) ...[
                Slider(
                  max: max,
                  value: value,
                  onChanged: (v) => setState(() => _dragging = v),
                  onChangeEnd: (v) {
                    setState(() => _dragging = null);
                    unawaited(
                      _controller.seek(Duration(milliseconds: v.round())),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_time(Duration(milliseconds: value.round()))),
                      Text(_time(duration!)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 40,
                    icon: const Icon(FluentIcons.previous_24_filled),
                    onPressed: snapshot.canPrevious
                        ? _controller.previous
                        : null,
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: loading
                        ? const Padding(
                            padding: EdgeInsets.all(18),
                            child: CircularProgressIndicator(),
                          )
                        : IconButton.filled(
                            iconSize: 40,
                            icon: Icon(
                              snapshot.playing
                                  ? FluentIcons.pause_24_filled
                                  : FluentIcons.play_24_filled,
                            ),
                            onPressed: _controller.togglePlay,
                          ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    iconSize: 40,
                    icon: const Icon(FluentIcons.next_24_filled),
                    onPressed: snapshot.canNext ? _controller.next : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (!track.isLive)
                Center(
                  child: TextButton.icon(
                    icon: const Icon(FluentIcons.live_24_regular),
                    label: Text(l10n.startRadio),
                    onPressed: () => _startRadio(remote.name),
                  ),
                ),
            ],
          ),
        ),
        if (remote.upcoming.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
            sliver: SliverToBoxAdapter(child: _buildQueueHeader(remote)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
            sliver: _buildQueue(remote),
          ),
        ],
      ],
    );
  }

  /// "Up next", and what the local queue offers on the whole of it.
  Widget _buildQueueHeader(RemoteControlState remote) {
    final l10n = context.l10n!;
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.remoteUpNext,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        if (remote.upcoming.length > 1)
          IconButton.filledTonal(
            onPressed: _controller.shuffleQueue,
            icon: const Icon(FluentIcons.arrow_shuffle_24_filled, size: 18),
            tooltip: l10n.shuffle,
            visualDensity: VisualDensity.compact,
          ),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          onPressed: _confirmClearQueue,
          icon: const Icon(FluentIcons.dismiss_24_regular, size: 18),
          label: Text(l10n.clear),
          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
      ],
    );
  }

  void _confirmClearQueue() {
    final l10n = context.l10n!;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        confirmationMessage: l10n.clearQueueQuestion,
        submitMessage: l10n.clear,
        isDangerous: true,
        onCancel: () => Navigator.pop(dialogContext),
        onSubmit: () {
          Navigator.pop(dialogContext);
          unawaited(_controller.clearQueue());
        },
      ),
    );
  }

  FocusNode _focusNodeFor(String key) =>
      _tileFocusNodes.putIfAbsent(key, FocusNode.new);

  /// The songs to come over there, edited like the local queue: swipe to
  /// take one out, drag to move it, hold for its menu.
  Widget _buildQueue(RemoteControlState remote) {
    final colorScheme = Theme.of(context).colorScheme;
    final upcoming = remote.upcoming;
    final showMoreButton = MediaQuery.sizeOf(context).width >= 600;
    final keys = {for (final track in upcoming) _keyOf(track)};
    _tileFocusNodes.removeWhere((key, node) {
      if (keys.contains(key)) return false;
      WidgetsBinding.instance.addPostFrameCallback((_) => node.dispose());
      return true;
    });
    return SliverReorderableList(
      itemCount: upcoming.length,
      onReorderItem: (oldIndex, newIndex) {
        if (oldIndex == newIndex) return;
        unawaited(_controller.moveEntry(upcoming[oldIndex], newIndex));
      },
      proxyDecorator: (child, index, animation) => Material(
        elevation: 8,
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        shadowColor: colorScheme.shadow.withValues(alpha: 0.35),
        child: child,
      ),
      itemBuilder: (context, index) {
        final track = upcoming[index];
        final key = _keyOf(track);
        return QueueTile(
          key: ValueKey(key),
          song: track.toSong(),
          index: index,
          queueEntryId: key,
          isCurrentSong: false,
          focusNode: _focusNodeFor(key),
          colorScheme: colorScheme,
          showMoreButton: showMoreButton,
          onTap: () => _skipTo(track, remote.name),
          onShowMenu: (tileContext) => _showSongMenu(tileContext, track),
          onDismissed: () => unawaited(_controller.removeEntry(track)),
        );
      },
    );
  }

  /// A queue entry as a key: its id over there, when that device sent one.
  String _keyOf(RemoteTrack track) =>
      track.entryId.isNotEmpty ? track.entryId : '${track.ytid}_${track.index}';

  /// The menu of the local queue: up next and out of the queue act on the
  /// queue over there; liking, playlists or downloads stay on this device.
  Future<void> _showSongMenu(
    BuildContext tileContext,
    RemoteTrack track,
  ) async {
    final l10n = context.l10n!;
    final colorScheme = Theme.of(context).colorScheme;
    final upcoming = _controller.state.value?.upcoming ?? const [];
    final canPlayNext =
        upcoming.isNotEmpty && upcoming.first.entryId != track.entryId;
    final song = track.toSong();

    await showSongOptionsMenu(
      context: context,
      song: song,
      position: menuPositionFor(tileContext),
      // Adding to the queue a song already in it would only duplicate it.
      showQueueActions: false,
      leadingItems: [
        if (canPlayNext)
          buildPopupMenuItem<String>(
            value: 'queue_play_next',
            icon: FluentIcons.receipt_play_24_regular,
            label: l10n.playNext,
            colorScheme: colorScheme,
          ),
      ],
      trailingItems: [
        buildPopupMenuItem<String>(
          value: 'queue_remove',
          icon: FluentIcons.delete_24_regular,
          label: l10n.removeFromQueue,
          colorScheme: colorScheme,
        ),
      ],
      onSelected: (value) async {
        switch (value) {
          case 'queue_play_next':
            await _controller.playEntryNext(track);
            return true;
          case 'queue_remove':
            await _controller.removeEntry(track);
            return true;
          case 'go_to_artist':
            _goToArtist(song);
            return true;
        }
        return false;
      },
    );
  }

  /// This page is a route above the pages: the artist page opens underneath
  /// it unless it goes first.
  void _goToArtist(Map song) {
    final artistName = song['artist']?.toString().trim() ?? '';
    if (artistName.isEmpty) return;
    Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
    unawaited(
      NavigationManager.router.push(
        '${NavigationManager.searchPath}/artist/${Uri.encodeComponent(artistName)}',
        extra: {'title': artistName, 'ytid': artistName},
      ),
    );
  }

  Future<void> _skipTo(RemoteTrack track, String name) async {
    final done = await _controller.skipTo(track);
    if (!done && mounted && _controller.state.value != null) {
      showToast(
        context,
        context.l10n!.remoteQueueChanged(name),
        icon: FluentIcons.info_20_regular,
      );
    }
  }

  Future<void> _startRadio(String name) async {
    final queued = await _controller.startRadio();
    if (queued == null || !mounted) return;
    final l10n = context.l10n!;
    showToast(
      context,
      queued > 0 ? l10n.radioStarted(queued) : l10n.radioUnavailable,
      icon: queued > 0 ? null : FluentIcons.info_20_regular,
    );
  }
}

/// "Playing on the TV", always in sight, with the way back to this device.
class _Banner extends StatelessWidget {
  const _Banner({required this.remote});

  final RemoteControlState remote;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.cast_24_filled,
            color: colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.l10n!.remotePlayingOn(remote.name),
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: RemoteControlController.instance.disconnect,
            child: Text(context.l10n!.remoteDisconnect),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.busy = false,
    this.actions = const [],
  });

  final IconData icon;
  final String text;
  final bool busy;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const CircularProgressIndicator()
            else
              Icon(icon, size: 48, color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(spacing: 12, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}
