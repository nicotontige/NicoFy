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
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nicofy/extensions/l10n.dart';
import 'package:nicofy/main.dart';
import 'package:nicofy/utilities/flutter_bottom_sheet.dart';
import 'package:nicofy/utilities/queue_entry_utils.dart';
import 'package:nicofy/widgets/confirmation_dialog.dart';
import 'package:nicofy/widgets/no_artwork_cube.dart';

/// The songs still to come: the one playing, at the top, and those after it.
///
/// The songs already played stay in the queue, so that back plays them again,
/// but are not listed. Every list position therefore maps to a queue index
/// offset by the index of the song playing; anything that talks to the audio
/// handler converts first.
class QueueWidget extends StatefulWidget {
  const QueueWidget({
    super.key,
    this.isBottomSheet = false,
    this.focusCurrentSong = false,
  });

  final bool isBottomSheet;

  /// Puts a TV remote on the current song as soon as the queue shows.
  final bool focusCurrentSong;

  @override
  State<QueueWidget> createState() => _QueueWidgetState();
}

class _QueueWidgetState extends State<QueueWidget> {
  /// The whole queue, played songs included, indexed like the audio handler.
  List<Map> _queue = [];
  late StreamSubscription<List<Map>> _subscription;
  late StreamSubscription<MediaItem?> _mediaSubscription;
  bool _isDismissing = false;
  bool _hasFocusedInitially = false;
  final ScrollController _scrollController = ScrollController();

  /// One per tile, so that focus can be put back on a tile after the list
  /// changed under it.
  final Map<String, FocusNode> _tileFocusNodes = {};

  /// Queue index of the first song listed.
  int get _start =>
      upcomingQueueStart(audioHandler.currentQueueIndex, _queue.length);

  bool get _startsWithCurrentSong {
    final currentIndex = audioHandler.currentQueueIndex;
    return currentIndex >= 0 && currentIndex < _queue.length;
  }

  int get _visibleCount => _queue.length - _start;

  @override
  void initState() {
    super.initState();
    _subscription = audioHandler.queueAsMapStream.listen((queue) {
      if (mounted && !_isDismissing) {
        _updateKeepingFocus(() => _queue = List<Map>.from(queue));
        if (widget.focusCurrentSong &&
            !_hasFocusedInitially &&
            queue.isNotEmpty) {
          _hasFocusedInitially = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _focusViewIndex(0),
          );
        }
      }
    });
    // A new song moves the top of the list, even when the queue is unchanged.
    _mediaSubscription = audioHandler.mediaItem
        .distinct((prev, next) => prev?.id == next?.id)
        .listen((_) {
          if (mounted && !_isDismissing) _updateKeepingFocus(() {});
        });
  }

  @override
  void dispose() {
    _subscription.cancel();
    _mediaSubscription.cancel();
    _scrollController.dispose();
    for (final node in _tileFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Applies [change], then, if it took away the tile a TV remote was on (the
  /// song that just ended, a song removed), focuses the tile now in its place
  /// rather than leaving the remote nowhere.
  void _updateKeepingFocus(VoidCallback change) {
    final focusedViewIndex = _focusedViewIndex();
    setState(change);
    if (focusedViewIndex == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusedViewIndex() == null) {
        _focusViewIndex(focusedViewIndex);
      }
    });
  }

  int? _focusedViewIndex() {
    final start = _start;
    for (var index = start; index < _queue.length; index++) {
      final node = _tileFocusNodes[_queueEntryKey(_queue[index], index)];
      if (node != null && node.hasFocus) return index - start;
    }
    return null;
  }

  void _focusViewIndex(int viewIndex, {bool retry = true}) {
    if (!mounted || _visibleCount <= 0) return;
    final clamped = viewIndex.clamp(0, _visibleCount - 1);
    final index = _start + clamped;
    final node = _tileFocusNodes[_queueEntryKey(_queue[index], index)];
    final nodeContext = node?.context;
    if (node != null && nodeContext != null) {
      node.requestFocus();
      Scrollable.ensureVisible(nodeContext, alignment: 0.1);
      return;
    }
    // Not built yet: the list is scrolled away from it. Only the top is
    // worth scrolling back to.
    if (retry && clamped == 0 && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusViewIndex(0, retry: false),
      );
    }
  }

  FocusNode _focusNodeFor(String key) =>
      _tileFocusNodes.putIfAbsent(key, FocusNode.new);

  /// Drops the focus nodes of songs no longer in the queue, once their tiles
  /// are gone.
  void _pruneFocusNodes() {
    final keys = {
      for (var index = 0; index < _queue.length; index++)
        _queueEntryKey(_queue[index], index),
    };
    final stale = _tileFocusNodes.keys.where((k) => !keys.contains(k)).toList();
    if (stale.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final key in stale) {
        if (keys.contains(key)) continue;
        _tileFocusNodes.remove(key)?.dispose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    _pruneFocusNodes();

    if (widget.isBottomSheet) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context, colorScheme, textTheme, compact: true),
          _buildBottomSheetContent(context, colorScheme),
        ],
      );
    }

    return Column(
      children: [
        _buildHeader(context, colorScheme, textTheme, compact: false),
        Divider(
          height: 1,
          thickness: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          indent: 8,
          endIndent: 8,
        ),
        Expanded(
          child: _queue.isEmpty
              ? _buildEmptyState(context, colorScheme, textTheme)
              : _buildList(context, colorScheme),
        ),
      ],
    );
  }

  Future<void> _shuffleQueue() async {
    await audioHandler.shuffleQueue();
    if (mounted && _scrollController.hasClients) {
      unawaited(
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  void _confirmClearQueue(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        confirmationMessage: context.l10n!.clearQueueQuestion,
        submitMessage: context.l10n!.clear,
        isDangerous: true,
        onCancel: () => Navigator.pop(dialogContext),
        onSubmit: () {
          Navigator.pop(dialogContext);
          audioHandler.clearQueue();
          if (widget.isBottomSheet) closeCurrentBottomSheet();
        },
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme, {
    required bool compact,
  }) {
    final upcomingCount = _visibleCount;
    return Padding(
      padding: compact
          ? const EdgeInsets.only(left: 10, right: 8, bottom: 12)
          : const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(compact ? 8 : 10),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              FluentIcons.apps_list_24_regular,
              color: colorScheme.onPrimaryContainer,
              size: compact ? 20.0 : 22.0,
            ),
          ),
          SizedBox(width: compact ? 12 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n!.queue,
                  style: compact
                      ? TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        )
                      : textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                ),
                if (upcomingCount > 0)
                  Text(
                    '$upcomingCount ${context.l10n!.songs.toLowerCase()}',
                    style: compact
                        ? TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          )
                        : textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                  ),
              ],
            ),
          ),
          if (_queue.length > 1)
            IconButton.filledTonal(
              onPressed: _shuffleQueue,
              icon: const Icon(FluentIcons.arrow_shuffle_24_filled, size: 18),
              tooltip: context.l10n!.shuffle,
              visualDensity: VisualDensity.compact,
            ),
          if (_queue.isNotEmpty) ...[
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: () => _confirmClearQueue(context),
              icon: const Icon(FluentIcons.dismiss_24_regular, size: 18),
              label: Text(context.l10n!.clear),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomSheetContent(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    if (_queue.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          context.l10n!.noSongsInQueue,
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
        ),
      );
    }
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.52,
      child: _buildList(context, colorScheme, closeOnTap: true),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                FluentIcons.music_note_1_24_regular,
                color: colorScheme.onSurfaceVariant,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n!.noSongsInQueue,
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Stable across the song changes and removals that shift queue indexes,
  /// so a tile keeps its state, and its focus, while the list moves.
  String _queueEntryKey(Map song, int index) {
    final entryId = song['queueEntryId']?.toString();
    if (entryId != null && entryId.isNotEmpty) return entryId;
    return '${song['ytid']}_$index';
  }

  int _queueIndexOfKey(String key) {
    for (var index = 0; index < _queue.length; index++) {
      if (_queueEntryKey(_queue[index], index) == key) return index;
    }
    return -1;
  }

  void _onReorder(int oldViewIndex, int newViewIndex) {
    final start = _start;
    final pinned = _startsWithCurrentSong;
    // The song playing has no handle; nothing moves it from here.
    if (pinned && oldViewIndex == 0) return;

    final oldIndex = start + oldViewIndex;
    final newIndex = queueIndexForUpcomingDrop(
      start: start,
      viewIndex: newViewIndex,
      startsWithCurrentSong: pinned,
    );
    if (oldIndex == newIndex || oldIndex >= _queue.length) return;

    final movingId = _queue[oldIndex]['queueEntryId']?.toString();
    setState(() {
      final item = _queue.removeAt(oldIndex);
      _queue.insert(newIndex.clamp(0, _queue.length), item);
    });
    if (movingId != null) audioHandler.reorderQueueById(movingId, newIndex);
  }

  Widget _buildList(
    BuildContext context,
    ColorScheme colorScheme, {
    bool closeOnTap = false,
  }) {
    final start = _start;
    final pinned = _startsWithCurrentSong;

    return ReorderableListView.builder(
      scrollController: _scrollController,
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.only(top: 4, bottom: 24, left: 8, right: 8),
      itemCount: _visibleCount,
      onReorderItem: _onReorder,
      proxyDecorator: (child, index, animation) => Material(
        elevation: 8,
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        shadowColor: colorScheme.shadow.withValues(alpha: 0.35),
        child: child,
      ),
      itemBuilder: (context, viewIndex) {
        final index = start + viewIndex;
        final song = _queue[index];
        final isCurrentSong = pinned && viewIndex == 0;
        final queueEntryId = _queueEntryKey(song, index);
        return QueueTile(
          key: ValueKey(queueEntryId),
          song: song,
          index: viewIndex,
          queueEntryId: queueEntryId,
          isCurrentSong: isCurrentSong,
          canReorder: !isCurrentSong,
          autofocus: isCurrentSong && widget.focusCurrentSong,
          focusNode: _focusNodeFor(queueEntryId),
          colorScheme: colorScheme,
          onTap: () {
            final actualIndex = _queueIndexOfKey(queueEntryId);
            if (actualIndex == -1) return;
            audioHandler.skipToSong(actualIndex);
            if (closeOnTap) closeCurrentBottomSheet();
          },
          confirmDismiss: (_) async {
            _isDismissing = true;
            return true;
          },
          onDismissed: () {
            final actualIndex = _queueIndexOfKey(queueEntryId);
            if (actualIndex == -1) {
              _isDismissing = false;
              return;
            }
            setState(() {
              _isDismissing = false;
              _queue.removeAt(actualIndex);
            });
            audioHandler.removeFromQueue(actualIndex);
          },
        );
      },
    );
  }
}

class QueueTile extends StatelessWidget {
  const QueueTile({
    super.key,
    required this.song,
    required this.index,
    required this.queueEntryId,
    required this.isCurrentSong,
    required this.focusNode,
    this.autofocus = false,
    this.canReorder = true,
    required this.colorScheme,
    required this.onTap,
    required this.onDismissed,
    this.confirmDismiss,
  });

  final Map song;

  /// Position in the list shown, which is not the queue index.
  final int index;
  final String queueEntryId;
  final bool isCurrentSong;
  final FocusNode focusNode;
  final bool autofocus;
  final bool canReorder;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  final VoidCallback onDismissed;
  final Future<bool?> Function(DismissDirection)? confirmDismiss;

  static const double _artSize = 46;
  static const double _artRadius = 10;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(queueEntryId),
      confirmDismiss: confirmDismiss,
      onDismissed: (_) => onDismissed(),
      background: _DismissBackground(
        alignment: Alignment.centerLeft,
        colorScheme: colorScheme,
      ),
      secondaryBackground: _DismissBackground(
        alignment: Alignment.centerRight,
        colorScheme: colorScheme,
      ),
      child: Material(
        color: isCurrentSong
            ? colorScheme.primaryContainer.withValues(alpha: 0.45)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          focusNode: focusNode,
          autofocus: autofocus,
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.transparent,
          highlightColor: colorScheme.onSurface.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Row(
      children: [
        _ArtworkThumbnail(
          song: song,
          size: _artSize,
          radius: _artRadius,
          colorScheme: colorScheme,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song['title']?.toString() ?? '',
                style: TextStyle(
                  color: isCurrentSong
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: isCurrentSong ? FontWeight.w600 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                song['artist']?.toString() ?? '',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (isCurrentSong) ...[
          Icon(
            FluentIcons.music_note_2_24_regular,
            color: colorScheme.primary,
            size: 16,
          ),
          const SizedBox(width: 6),
        ],
        if (canReorder)
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              child: Icon(
                FluentIcons.re_order_24_regular,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          // Keeps the current song's text as wide as the others'.
          const SizedBox(width: 40),
      ],
    );
  }
}

class _ArtworkThumbnail extends StatelessWidget {
  const _ArtworkThumbnail({
    required this.song,
    required this.size,
    required this.radius,
    required this.colorScheme,
  });

  final Map song;
  final double size;
  final double radius;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final artworkPath = song['artworkPath'] as String?;
    if (artworkPath != null && artworkPath.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          File(artworkPath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(),
        ),
      );
    }
    final imageUrl = song['lowResImage']?.toString() ?? '';
    if (imageUrl.isEmpty) return _fallback();
    // Low-res YouTube 'default.jpg' thumbnails ship with baked-in black
    // letterbox bars, so BoxFit.cover keeps them visible. Detect that case and
    // stretch over the bars with fill + centerSlice, otherwise crop with cover —
    // matching SongBar so the queue frames covers the same way (no black bars).
    final isImageSmall = imageUrl.contains('default.jpg');
    return CachedNetworkImage(
      width: size,
      height: size,
      imageUrl: imageUrl,
      imageBuilder: (_, imageProvider) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image(
          image: imageProvider,
          width: size,
          height: size,
          fit: isImageSmall ? BoxFit.fill : BoxFit.cover,
          centerSlice: isImageSmall ? const Rect.fromLTRB(1, 1, 1, 1) : null,
        ),
      ),
      placeholder: (_, __) => _loading(),
      errorWidget: (_, __, ___) => _fallback(),
    );
  }

  Widget _fallback() => NullArtworkWidget(
    size: size,
    borderRadius: radius,
    iconSize: size * 0.45,
  );

  Widget _loading() => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class _DismissBackground extends StatelessWidget {
  const _DismissBackground({
    required this.alignment,
    required this.colorScheme,
  });

  final Alignment alignment;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        FluentIcons.delete_24_regular,
        color: colorScheme.onErrorContainer,
        size: 22,
      ),
    );
  }
}
