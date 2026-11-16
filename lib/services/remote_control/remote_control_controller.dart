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

import 'package:material_ui/material_ui.dart';
import 'package:nicofy/main.dart';
import 'package:nicofy/services/local_sync_service.dart';
import 'package:nicofy/services/remote_control/remote_protocol.dart';
import 'package:nicofy/services/remote_control/remote_session.dart';

enum RemoteLinkStatus {
  connecting,
  connected,

  /// Requests stopped getting through; still trying.
  unreachable,

  /// The other device refuses: see [RemoteControlState.failure].
  failed,
}

enum RemoteFailure { untrusted, remoteOff, updateRequired, unreachable, failed }

/// What the remote knows of the device it controls.
class RemoteControlState {
  const RemoteControlState({
    required this.device,
    required this.name,
    required this.status,
    this.snapshot,
    this.receivedAt = Duration.zero,
    this.upcoming = const [],
    this.failure,
  });

  final DiscoveredSyncDevice device;
  final String name;
  final RemoteLinkStatus status;
  final RemoteSnapshot? snapshot;

  /// When [snapshot] arrived, on [RemoteControlController.clock].
  final Duration receivedAt;
  final List<RemoteTrack> upcoming;
  final RemoteFailure? failure;

  RemoteControlState copyWith({
    DiscoveredSyncDevice? device,
    String? name,
    RemoteLinkStatus? status,
    RemoteSnapshot? snapshot,
    Duration? receivedAt,
    List<RemoteTrack>? upcoming,
    RemoteFailure? failure,
  }) => RemoteControlState(
    device: device ?? this.device,
    name: name ?? this.name,
    status: status ?? this.status,
    snapshot: snapshot ?? this.snapshot,
    receivedAt: receivedAt ?? this.receivedAt,
    upcoming: upcoming ?? this.upcoming,
    failure: failure ?? this.failure,
  );
}

/// This device as the remote of another one: one connection at a time,
/// refreshed every second while the app is in front. The position moves on
/// by itself between two refreshes.
class RemoteControlController {
  RemoteControlController._();

  static final RemoteControlController instance = RemoteControlController._();

  static const Duration pollInterval = Duration(seconds: 1);

  /// Failed refreshes in a row before the remote says it lost the device.
  static const int _failuresBeforeUnreachable = 3;

  final ValueNotifier<RemoteControlState?> state = ValueNotifier(null);
  final Stopwatch _stopwatch = Stopwatch()..start();

  Duration get clock => _stopwatch.elapsed;

  bool get isActive => state.value != null;

  RemoteControlClient? _client;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  StreamSubscription<bool>? _localPlayback;
  bool _foreground = true;
  bool _polling = false;
  int _failures = 0;
  int _ticks = 0;

  /// Replies are applied in the order requests were sent: a refresh sent
  /// before a command must not undo what the command's reply showed.
  int _sent = 0;
  int _applied = 0;
  String? _knownQueue;

  /// Changes on every connection, so late replies to an old one are dropped.
  int _generation = 0;

  /// Where playback is on the other device now.
  Duration get position {
    final current = state.value;
    final snapshot = current?.snapshot;
    if (current == null || snapshot == null) return Duration.zero;
    if (current.status != RemoteLinkStatus.connected) {
      return Duration(milliseconds: snapshot.positionMs);
    }
    return snapshot.positionAfter(clock - current.receivedAt);
  }

  /// Connects to [device], which must be paired. Returns why it could not,
  /// leaving this device as it was; null once in control.
  Future<RemoteFailure?> connect(DiscoveredSyncDevice device) async {
    disconnect();
    final service = LocalSyncService.instance;
    final client = service.remoteClientFor(device);
    if (client == null) return RemoteFailure.untrusted;
    final generation = _generation;
    _client = client;
    final paired = service.pairedDevices.value
        .where((d) => d.deviceId == device.deviceId)
        .firstOrNull;
    state.value = RemoteControlState(
      device: device,
      name: paired?.name ?? device.name,
      status: RemoteLinkStatus.connecting,
    );
    try {
      await client.open();
      if (generation != _generation) return null;
      await service.rememberControlledDevice(device, client.remoteName);
      final snapshot = await client.fetchState();
      if (generation != _generation) return null;
      _apply(snapshot, ++_sent);
      state.value = state.value?.copyWith(
        name: client.remoteName,
        status: RemoteLinkStatus.connected,
      );
    } catch (e) {
      if (generation == _generation) {
        disconnect();
        return _failureFor(e) ?? RemoteFailure.unreachable;
      }
      return null;
    }

    // Playback stays over there: this device stops making its own sound.
    if (audioHandler.playbackState.value.playing) await audioHandler.pause();
    if (generation != _generation) return null;
    // Playing something here again means listening here: control ends.
    _localPlayback = audioHandler.playbackState
        .map((s) => s.playing)
        .distinct()
        .skip(1)
        .where((playing) => playing)
        .listen((_) => disconnect());
    _lifecycle = AppLifecycleListener(
      onStateChange: (lifecycle) {
        _foreground =
            lifecycle == AppLifecycleState.resumed ||
            lifecycle == AppLifecycleState.inactive;
        if (lifecycle == AppLifecycleState.resumed) unawaited(_poll());
      },
    );
    _timer = Timer.periodic(pollInterval, (_) => _tick());
    return null;
  }

  /// Back to this device's own playback.
  void disconnect() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    unawaited(_localPlayback?.cancel());
    _localPlayback = null;
    _client?.close();
    _client = null;
    _failures = 0;
    _knownQueue = null;
    _polling = false;
    _foreground = true;
    state.value = null;
  }

  /// Tries again after a failure, from the same device.
  Future<RemoteFailure?> retry() async {
    final current = state.value;
    if (current == null) return null;
    return connect(current.device);
  }

  void _tick() {
    if (!_foreground) return;
    final current = state.value;
    if (current == null || current.status == RemoteLinkStatus.failed) return;
    _ticks++;
    // Lost: try less often, and look for it again on the network every so
    // often, as it may have come back on another address or port.
    if (current.status == RemoteLinkStatus.unreachable) {
      if (_ticks % 3 != 0) return;
      if (_ticks % 15 == 0) {
        unawaited(_rediscover());
        return;
      }
    }
    unawaited(_poll());
  }

  Future<void> _poll() async {
    final client = _client;
    if (client == null || _polling) return;
    _polling = true;
    final generation = _generation;
    final sequence = ++_sent;
    try {
      final snapshot = await client.fetchState(knownQueue: _knownQueue);
      if (generation != _generation) return;
      _apply(snapshot, sequence);
    } catch (e) {
      if (generation == _generation) _onFailure(e);
    } finally {
      if (generation == _generation) _polling = false;
    }
  }

  Future<void> _rediscover() async {
    final current = state.value;
    if (current == null) return;
    final generation = _generation;
    final found = await LocalSyncService.instance.discoverDevices(
      duration: const Duration(seconds: 2),
    );
    if (generation != _generation) return;
    final device = found
        .where((d) => d.deviceId == current.device.deviceId)
        .firstOrNull;
    if (device == null) return;
    if (device.ip == current.device.ip && device.port == current.device.port) {
      unawaited(_poll());
      return;
    }
    final client = LocalSyncService.instance.remoteClientFor(device);
    if (client == null) return;
    _client?.close();
    _client = client;
    _knownQueue = null;
    state.value = state.value?.copyWith(device: device);
    unawaited(_poll());
  }

  void _apply(RemoteSnapshot snapshot, int sequence) {
    final current = state.value;
    if (current == null || sequence < _applied) return;
    _applied = sequence;
    _failures = 0;
    final upcoming = snapshot.upcoming;
    if (upcoming != null) _knownQueue = snapshot.queueSignature;
    state.value = current.copyWith(
      status: RemoteLinkStatus.connected,
      snapshot: snapshot,
      receivedAt: clock,
      upcoming: upcoming,
    );
  }

  void _onFailure(Object error) {
    final current = state.value;
    if (current == null) return;
    final failure = _failureFor(error);
    if (failure != null) {
      state.value = current.copyWith(
        status: RemoteLinkStatus.failed,
        failure: failure,
      );
      return;
    }
    _failures++;
    if (_failures >= _failuresBeforeUnreachable &&
        current.status != RemoteLinkStatus.unreachable) {
      state.value = current.copyWith(status: RemoteLinkStatus.unreachable);
    }
  }

  /// Null for what may pass by itself: a timeout, the network.
  RemoteFailure? _failureFor(Object error) {
    if (error is! RemoteRequestFailure) return null;
    return switch (error.status) {
      403 when error.code == 'not_paired' => RemoteFailure.untrusted,
      503 => RemoteFailure.remoteOff,
      404 || 426 => RemoteFailure.updateRequired,
      _ => RemoteFailure.failed,
    };
  }

  /// Sends [command]; null when it did not get through.
  Future<RemoteCommandReply?> _send(RemoteCommand command) async {
    final client = _client;
    if (client == null) return null;
    final generation = _generation;
    final sequence = ++_sent;
    try {
      final reply = await client.send(command, knownQueue: _knownQueue);
      if (generation != _generation) return null;
      _apply(reply.snapshot, sequence);
      return reply;
    } catch (e) {
      if (generation == _generation) _onFailure(e);
      return null;
    }
  }

  /// Shows [playing] and [position] straight away, before the device
  /// confirms: a button that waits for the network feels broken.
  void _assume({bool? playing, Duration? position}) {
    final current = state.value;
    final snapshot = current?.snapshot;
    if (current == null || snapshot == null) return;
    state.value = current.copyWith(
      snapshot: snapshot.copyWith(
        playing: playing,
        positionMs: (position ?? this.position).inMilliseconds,
      ),
      receivedAt: clock,
    );
  }

  Future<void> togglePlay() async {
    final snapshot = state.value?.snapshot;
    if (snapshot == null) return;
    final play = !snapshot.playing;
    _assume(playing: play);
    await _send(
      play ? const RemoteCommand.play() : const RemoteCommand.pause(),
    );
  }

  Future<void> next() => _send(const RemoteCommand.next());

  Future<void> previous() => _send(const RemoteCommand.previous());

  Future<void> seek(Duration position) async {
    _assume(position: position);
    await _send(RemoteCommand.seek(position));
  }

  /// False when the queue over there changed and [track] is no longer where
  /// it was; the list is refreshed meanwhile.
  Future<bool> skipTo(RemoteTrack track) async {
    final reply = await _send(RemoteCommand.skipTo(track));
    return reply != null && reply.error == null;
  }

  /// How many songs the radio queued there, null when it did not get through.
  Future<int?> startRadio() async {
    final reply = await _send(const RemoteCommand.radio());
    if (reply == null) return null;
    return reply.added ?? 0;
  }
}
