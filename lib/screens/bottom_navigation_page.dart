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
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nicofy/extensions/l10n.dart';
import 'package:nicofy/main.dart';
import 'package:nicofy/services/remote_control/remote_control_controller.dart';
import 'package:nicofy/services/router_service.dart';
import 'package:nicofy/services/settings_manager.dart';
import 'package:nicofy/utilities/flutter_bottom_sheet.dart'
    show closeCurrentBottomSheet, isBottomSheetOpen;
import 'package:nicofy/widgets/mini_player.dart';
import 'package:nicofy/widgets/queue_list_view.dart';
import 'package:nicofy/widgets/remote_control/remote_mini_player.dart';

class BottomNavigationPage extends StatefulWidget {
  const BottomNavigationPage({required this.child, super.key});

  final StatefulNavigationShell child;

  @override
  State<BottomNavigationPage> createState() => _BottomNavigationPageState();
}

class _BottomNavigationPageState extends State<BottomNavigationPage> {
  late final _miniPlayerVisibilityStream = audioHandler.mediaItem
      .map((mediaItem) => mediaItem != null)
      .distinct();

  bool? _previousOfflineMode;

  /// Track the previously selected shell branch to detect reselects.
  int? _previousShellIndex;

  final _railFocusNode = FocusNode(skipTraversal: true);

  /// Not a branch: the rail entry that opens the queue.
  static const _queueShellIndex = -1;

  /// The queue shows in place of the page, beside the rail, rather than as
  /// a route over the whole shell, which hid the rail.
  bool _showingQueue = false;

  /// The rail entry last drawn as selected, for focus to come back to.
  int _railSelectedIndex = 0;

  @override
  void initState() {
    super.initState();
    NavigationManager.router.routerDelegate.addListener(_onRouteChanged);
  }

  @override
  void dispose() {
    NavigationManager.router.routerDelegate.removeListener(_onRouteChanged);
    _railFocusNode.dispose();
    super.dispose();
  }

  /// Navigating anywhere, from the queue's song menu for instance, has to
  /// show where it went.
  void _onRouteChanged() {
    if (_showingQueue && mounted) setState(() => _showingQueue = false);
  }

  @override
  Widget build(BuildContext context) {
    // An open sheet must keep back for itself, even on the home tab, where
    // back would otherwise leave the app.
    return ValueListenableBuilder<bool>(
      valueListenable: isBottomSheetOpen,
      builder: (context, isSheetOpen, child) => PopScope(
        canPop: widget.child.currentIndex == 0 && !isSheetOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (isSheetOpen) return closeCurrentBottomSheet();

          final currentIndex = widget.child.currentIndex;
          if (currentIndex != 0) {
            widget.child.goBranch(0);
          } else {
            SystemNavigator.pop();
          }
        },
        child: child!,
      ),
      child: ValueListenableBuilder<bool>(
        valueListenable: offlineMode,
        builder: (context, isOfflineMode, _) {
          if (_previousOfflineMode != null &&
              _previousOfflineMode != isOfflineMode) {
            SchedulerBinding.instance.addPostFrameCallback((_) {
              _handleOfflineModeChange(isOfflineMode);
            });
          }
          _previousOfflineMode = isOfflineMode;

          return StreamBuilder<bool>(
            initialData: audioHandler.mediaItem.value != null,
            stream: _miniPlayerVisibilityStream,
            builder: (context, playingSnapshot) {
              final isLargeScreen = MediaQuery.of(context).size.width >= 600;
              final canShowQueue =
                  isLargeScreen && (playingSnapshot.data ?? false);
              final items = _getNavigationItems(
                isOfflineMode,
                showQueue: canShowQueue,
              );
              // Playback stopped: the queue entry is gone, and the queue
              // must not come back by itself with the next song.
              if (!canShowQueue) _showingQueue = false;
              final isQueueShown = _showingQueue;
              final selectedIndex = isQueueShown
                  ? items.indexWhere(
                      (item) => item.shellIndex == _queueShellIndex,
                    )
                  : _getCurrentIndex(items, isOfflineMode);
              _railSelectedIndex = selectedIndex;

              return Scaffold(
                body: SafeArea(
                  child: Actions(
                    actions: {
                      DirectionalFocusIntent:
                          CallbackAction<DirectionalFocusIntent>(
                            onInvoke: (intent) =>
                                _moveFocus(intent, selectedIndex),
                          ),
                    },
                    child: Row(
                      children: [
                        if (isLargeScreen)
                          Focus(
                            focusNode: _railFocusNode,
                            child: NavigationRail(
                              labelType: NavigationRailLabelType.selected,
                              destinations: items
                                  .map(
                                    (item) => NavigationRailDestination(
                                      icon: Icon(item.icon),
                                      selectedIcon: Icon(item.selectedIcon),
                                      label: Text(item.label),
                                    ),
                                  )
                                  .toList(),
                              selectedIndex: selectedIndex,
                              onDestinationSelected: (index) =>
                                  items[index].shellIndex == _queueShellIndex
                                  ? _showQueue()
                                  : _onTabTapped(index, items),
                            ),
                          ),
                        Expanded(
                          child: StreamBuilder<bool>(
                            initialData: audioHandler.mediaItem.value != null,
                            stream: _miniPlayerVisibilityStream,
                            builder: (context, snapshot) {
                              final isMiniPlayerVisible =
                                  snapshot.data ?? false;

                              // Below the page rather than floating over it:
                              // a TV remote scrolls just far enough to show
                              // the focused row, which then sat under the bar.
                              return Column(
                                children: [
                                  Expanded(
                                    child: _buildPage(showQueue: isQueueShown),
                                  ),
                                  // While this device controls another, the
                                  // bar shows and drives that one instead.
                                  ValueListenableBuilder<RemoteControlState?>(
                                    valueListenable:
                                        RemoteControlController.instance.state,
                                    builder: (context, remote, _) =>
                                        remote == null && !isMiniPlayerVisible
                                        ? const SizedBox.shrink()
                                        : Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 8,
                                            ),
                                            child: remote == null
                                                ? const MiniPlayer()
                                                : RemoteMiniPlayer(
                                                    remote: remote,
                                                  ),
                                          ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                bottomNavigationBar: !isLargeScreen
                    ? NavigationBar(
                        selectedIndex: selectedIndex,
                        labelBehavior: languageSetting == const Locale('en', '')
                            ? NavigationDestinationLabelBehavior
                                  .onlyShowSelected
                            : NavigationDestinationLabelBehavior.alwaysHide,
                        onDestinationSelected: (index) =>
                            _onTabTapped(index, items),
                        destinations: items
                            .map(
                              (item) => NavigationDestination(
                                icon: Icon(item.icon),
                                selectedIcon: Icon(item.selectedIcon),
                                label: item.label,
                              ),
                            )
                            .toList(),
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  List<_NavigationItem> _getNavigationItems(
    bool isOfflineMode, {
    bool showQueue = false,
  }) {
    final items = <_NavigationItem>[
      _NavigationItem(
        icon: FluentIcons.home_24_regular,
        selectedIcon: FluentIcons.home_24_filled,
        label: context.l10n?.home ?? 'Home',
        shellIndex: 0,
      ),
    ];

    // On a TV the mini player sits at the far end of every page and the queue
    // one more screen behind it, so the rail gets a way straight to the queue.
    if (showQueue) {
      items.add(
        _NavigationItem(
          icon: FluentIcons.play_24_regular,
          selectedIcon: FluentIcons.play_24_filled,
          label: context.l10n?.queue ?? 'Queue',
          shellIndex: _queueShellIndex,
        ),
      );
    }

    // Only add search tab in online mode
    if (!isOfflineMode) {
      items.add(
        _NavigationItem(
          icon: FluentIcons.search_24_regular,
          selectedIcon: FluentIcons.search_24_filled,
          label: context.l10n?.search ?? 'Search',
          shellIndex: 1,
        ),
      );
    }

    items.addAll([
      _NavigationItem(
        icon: FluentIcons.book_24_regular,
        selectedIcon: FluentIcons.book_24_filled,
        label: context.l10n?.library ?? 'Library',
        shellIndex: 2,
      ),
      _NavigationItem(
        icon: FluentIcons.settings_24_regular,
        selectedIcon: FluentIcons.settings_24_filled,
        label: context.l10n?.settings ?? 'Settings',
        shellIndex: 3,
      ),
    ]);

    return items;
  }

  /// A TV remote has no other way to reach the rail: when nothing in the page
  /// lies further left, the left key lands on the selected tab.
  void _moveFocus(DirectionalFocusIntent intent, int selectedIndex) {
    final tabs = _railFocusNode.traversalDescendants.toList();
    final moved = primaryFocus?.focusInDirection(intent.direction) ?? false;
    if (moved ||
        intent.direction != TraversalDirection.left ||
        tabs.isEmpty ||
        _railFocusNode.hasFocus ||
        // Inside an open bottom sheet: stay there.
        isBottomSheetOpen.value) {
      return;
    }
    tabs[selectedIndex.clamp(0, tabs.length - 1)].requestFocus();
  }

  /// The branch pages, with the queue over them while it is open. The pages
  /// stay built underneath, so going back finds them as they were, but out of
  /// reach of the remote and with their animations stopped.
  Widget _buildPage({required bool showQueue}) {
    return Stack(
      children: [
        Positioned.fill(
          child: Offstage(
            offstage: showQueue,
            child: ExcludeFocus(
              excluding: showQueue,
              child: TickerMode(enabled: !showQueue, child: widget.child),
            ),
          ),
        ),
        if (showQueue)
          Positioned.fill(
            child: BackButtonListener(
              onBackButtonPressed: () async {
                // A menu or a dialog opened from the queue goes first.
                if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
                  await Navigator.of(context).maybePop();
                  return true;
                }
                _hideQueue(focusRail: true);
                return true;
              },
              child: const Material(
                child: Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: QueueWidget(focusCurrentSong: true),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// A page of the shell rather than a bottom sheet, which sits beside the
  /// page where a remote can wander out of it, or a route, which covered the
  /// rail: left from the queue reaches the rail like from any page.
  void _showQueue() {
    closeCurrentBottomSheet();
    setState(() => _showingQueue = true);
  }

  void _hideQueue({bool focusRail = false}) {
    if (!_showingQueue) return;
    setState(() => _showingQueue = false);
    if (!focusRail) return;
    // The queue had focus and is gone: back lands on the rail, on the page
    // it returns to.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tabs = _railFocusNode.traversalDescendants.toList();
      if (!mounted || tabs.isEmpty) return;
      tabs[_railSelectedIndex.clamp(0, tabs.length - 1)].requestFocus();
    });
  }

  void _handleOfflineModeChange(bool isOfflineMode) {
    if (!mounted) return;

    final currentRoute = GoRouterState.of(context).matchedLocation;

    // If we're switching to offline mode and currently on search tab
    if (isOfflineMode && currentRoute.startsWith('/search')) {
      // Navigate to home
      widget.child.goBranch(0);
    }
  }

  void _onTabTapped(int index, List<_NavigationItem> items) {
    if (index < items.length) {
      final item = items[index];
      // Leaving the queue for the page under it is not a reselect: that
      // page keeps where it was.
      final isReselect =
          _previousShellIndex == item.shellIndex && !_showingQueue;

      // Close any open bottom sheet before switching tabs
      closeCurrentBottomSheet();
      _hideQueue();

      // If user taps the same tab again, reset it to initial state.
      // Otherwise, preserve the branch state.
      if (isReselect) {
        widget.child.goBranch(item.shellIndex, initialLocation: true);
      } else {
        widget.child.goBranch(item.shellIndex);
      }

      _previousShellIndex = item.shellIndex;
    }
  }

  int _getCurrentIndex(List<_NavigationItem> items, bool isOfflineMode) {
    final currentShellIndex = widget.child.currentIndex;

    if (items.isEmpty) return 0;

    // Try to find the current shell index in the available items
    final matchedIndex = items.indexWhere(
      (item) => item.shellIndex == currentShellIndex,
    );
    if (matchedIndex != -1) return matchedIndex;

    // If the Search branch (1) is active but Search is hidden in offline mode,
    // fall back to the Home tab.
    if (isOfflineMode && currentShellIndex == 1) return 0;

    // Final fallback: return the first tab to keep UI in a valid state.
    return 0;
  }
}

class _NavigationItem {
  const _NavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.shellIndex,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int shellIndex;
}
