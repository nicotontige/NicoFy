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
import 'dart:math';

// What one NicoFy device says about its playback to another that controls
// it, and the commands it accepts. Plain data, so both ends and the tests
// share it; the transport and its encryption live in remote_session.dart.

/// Bumped when a field changes meaning; both ends must agree.
const int remoteApiVersion = 1;

/// How many of the songs after the one playing a snapshot carries.
const int remoteQueueLimit = 100;

/// Where the player is, as the remote shows it.
enum RemoteProcessing { idle, loading, buffering, ready, completed, error }

String _text(Object? value, int maxLength) {
  final text = value?.toString() ?? '';
  return text.length <= maxLength ? text : text.substring(0, maxLength);
}

int? _nonNegativeInt(Object? value) =>
    value is int && value >= 0 ? value : null;

/// Only a web address is worth sending: a file path on the other device
/// shows nothing here.
String? remoteArtworkUrl(Map song) {
  for (final key in ['highResImage', 'lowResImage', 'image']) {
    final value = song[key]?.toString();
    if (value == null) continue;
    final uri = Uri.tryParse(value);
    if (uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty &&
        value.length <= 2048) {
      return value;
    }
  }
  return null;
}

int? _songDurationMs(Object? raw) {
  // Songs store their length in seconds, sometimes as text.
  final seconds = raw is num ? raw : num.tryParse(raw?.toString() ?? '');
  if (seconds == null || !seconds.isFinite || seconds <= 0) return null;
  return (seconds * 1000).round();
}

/// A song of the controlled device's queue, at [index] in its full queue.
class RemoteTrack {
  const RemoteTrack({
    required this.index,
    required this.ytid,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.durationMs,
    this.isLive = false,
  });

  factory RemoteTrack.fromSong(Map song, int index) => RemoteTrack(
    index: index,
    ytid: _text(song['ytid'], 64),
    title: _text(song['title'], 300),
    artist: _text(song['artist'], 300).trim(),
    artworkUrl: remoteArtworkUrl(song),
    durationMs: _songDurationMs(song['duration']),
    isLive: song['isLive'] == true,
  );

  /// Throws [FormatException] when [map] is not a track.
  factory RemoteTrack.fromMap(Object? map) {
    if (map is! Map) throw const FormatException('Invalid remote track');
    final index = _nonNegativeInt(map['index']);
    if (index == null) throw const FormatException('Invalid remote track');
    final artwork = map['artwork'];
    return RemoteTrack(
      index: index,
      ytid: _text(map['ytid'], 64),
      title: _text(map['title'], 300),
      artist: _text(map['artist'], 300),
      artworkUrl:
          artwork is String && remoteArtworkUrl({'image': artwork}) != null
          ? artwork
          : null,
      durationMs: _nonNegativeInt(map['durationMs']),
      isLive: map['live'] == true,
    );
  }

  /// Index in the controlled device's full queue, the songs already played
  /// included: that is what [RemoteCommand.skipTo] refers to.
  final int index;
  final String ytid;
  final String title;
  final String artist;
  final String? artworkUrl;
  final int? durationMs;
  final bool isLive;

  Map<String, dynamic> toMap() => {
    'index': index,
    'ytid': ytid,
    'title': title,
    'artist': artist,
    if (artworkUrl != null) 'artwork': artworkUrl,
    if (durationMs != null) 'durationMs': durationMs,
    if (isLive) 'live': true,
  };
}

/// The controlled device's playback at one moment.
class RemoteSnapshot {
  const RemoteSnapshot({
    required this.track,
    required this.playing,
    required this.processing,
    required this.positionMs,
    required this.durationMs,
    required this.speed,
    required this.canNext,
    required this.canPrevious,
    required this.queueSignature,
    this.upcoming,
  });

  /// Throws [FormatException] when [map] is not a snapshot.
  factory RemoteSnapshot.fromMap(Object? map) {
    if (map is! Map) throw const FormatException('Invalid remote snapshot');
    final rawTrack = map['track'];
    final rawQueue = map['queue'];
    if (rawQueue != null && rawQueue is! List) {
      throw const FormatException('Invalid remote queue');
    }
    final speed = map['speed'];
    return RemoteSnapshot(
      track: rawTrack == null ? null : RemoteTrack.fromMap(rawTrack),
      playing: map['playing'] == true,
      processing: RemoteProcessing.values.firstWhere(
        (value) => value.name == map['state'],
        orElse: () => RemoteProcessing.idle,
      ),
      positionMs: _nonNegativeInt(map['positionMs']) ?? 0,
      durationMs: _nonNegativeInt(map['durationMs']),
      speed: speed is num && speed.isFinite && speed > 0 && speed <= 4
          ? speed.toDouble()
          : 1,
      canNext: map['canNext'] == true,
      canPrevious: map['canPrevious'] == true,
      queueSignature: _text(map['queueSignature'], 128),
      upcoming: rawQueue is List
          ? rawQueue.take(remoteQueueLimit).map(RemoteTrack.fromMap).toList()
          : null,
    );
  }

  /// Null when nothing is loaded there.
  final RemoteTrack? track;
  final bool playing;
  final RemoteProcessing processing;
  final int positionMs;
  final int? durationMs;
  final double speed;
  final bool canNext;
  final bool canPrevious;

  /// Changes whenever the songs after the current one change, so the queue
  /// is only sent again when it did.
  final String queueSignature;

  /// The songs after the current one, the played ones left out like in the
  /// queue of this device; null when the remote already has them.
  final List<RemoteTrack>? upcoming;

  bool get isActive =>
      track != null &&
      processing != RemoteProcessing.idle &&
      processing != RemoteProcessing.error;

  /// Where playback is [elapsed] after this snapshot was taken, without
  /// asking: the position moves on its own while it plays.
  Duration positionAfter(Duration elapsed) {
    var position = positionMs;
    if (playing && processing == RemoteProcessing.ready) {
      position += (elapsed.inMilliseconds * speed).round();
    }
    final duration = durationMs;
    if (duration != null && duration > 0) position = min(position, duration);
    return Duration(milliseconds: position);
  }

  RemoteSnapshot copyWith({
    bool? playing,
    int? positionMs,
    List<RemoteTrack>? upcoming,
  }) => RemoteSnapshot(
    track: track,
    playing: playing ?? this.playing,
    processing: processing,
    positionMs: positionMs ?? this.positionMs,
    durationMs: durationMs,
    speed: speed,
    canNext: canNext,
    canPrevious: canPrevious,
    queueSignature: queueSignature,
    upcoming: upcoming ?? this.upcoming,
  );

  Map<String, dynamic> toMap() => {
    'track': track?.toMap(),
    'playing': playing,
    'state': processing.name,
    'positionMs': positionMs,
    if (durationMs != null) 'durationMs': durationMs,
    'speed': speed,
    'canNext': canNext,
    'canPrevious': canPrevious,
    'queueSignature': queueSignature,
    if (upcoming != null) 'queue': upcoming!.map((e) => e.toMap()).toList(),
  };
}

enum RemoteAction { play, pause, next, previous, seek, skipTo, radio }

/// Something the remote asks the controlled device to do.
class RemoteCommand {
  const RemoteCommand._(this.action, {this.positionMs, this.index, this.ytid});

  const RemoteCommand.play() : this._(RemoteAction.play);
  const RemoteCommand.pause() : this._(RemoteAction.pause);
  const RemoteCommand.next() : this._(RemoteAction.next);
  const RemoteCommand.previous() : this._(RemoteAction.previous);
  const RemoteCommand.radio() : this._(RemoteAction.radio);

  RemoteCommand.seek(Duration position)
    : this._(RemoteAction.seek, positionMs: max(0, position.inMilliseconds));

  /// Plays [track]; refused if the queue there moved since it was listed.
  RemoteCommand.skipTo(RemoteTrack track)
    : this._(RemoteAction.skipTo, index: track.index, ytid: track.ytid);

  /// Throws [FormatException] for anything the protocol does not define.
  factory RemoteCommand.fromMap(Map map) {
    final action = RemoteAction.values
        .where((value) => value.name == map['action'])
        .firstOrNull;
    switch (action) {
      case null:
        throw const FormatException('Unknown remote action');
      case RemoteAction.seek:
        final position = _nonNegativeInt(map['positionMs']);
        if (position == null) throw const FormatException('Invalid seek');
        return RemoteCommand._(action, positionMs: position);
      case RemoteAction.skipTo:
        final index = _nonNegativeInt(map['index']);
        final ytid = map['ytid'];
        if (index == null || ytid is! String) {
          throw const FormatException('Invalid skip');
        }
        return RemoteCommand._(action, index: index, ytid: ytid);
      default:
        return RemoteCommand._(action);
    }
  }

  final RemoteAction action;
  final int? positionMs;
  final int? index;
  final String? ytid;

  Map<String, dynamic> toMap() => {
    'action': action.name,
    if (positionMs != null) 'positionMs': positionMs,
    if (index != null) 'index': index,
    if (ytid != null) 'ytid': ytid,
  };
}

/// The player a remote drives: the audio handler in the app, a fake in tests.
abstract class RemotePlaybackTarget {
  /// The whole queue, the songs already played included.
  List<Map> get queue;
  int get currentIndex;
  bool get playing;
  RemoteProcessing get processing;
  Duration get position;
  Duration? get duration;
  double get speed;
  bool get canSkipToNext;
  bool get hasPrevious;

  Future<void> play();
  Future<void> pause();
  Future<void> skipToNext();
  Future<void> skipToPrevious();
  Future<void> seek(Duration position);

  /// [index] is in the whole queue, as in [queue].
  Future<void> skipToSong(int index);

  /// Returns how many songs were queued.
  Future<int> startRadio();
}

/// Identifies the songs after the current one, cheaply, so an unchanged
/// queue is not sent again every second. It only has to differ from what the
/// same device said before, never to mean anything elsewhere.
String remoteQueueSignature(List<Map> queue, int currentIndex) {
  final end = min(queue.length, currentIndex + 1 + remoteQueueLimit);
  final start = min(max(currentIndex, 0), end);
  final ids = [
    for (var i = start; i < end; i++)
      '${queue[i]['ytid']}\u0000${queue[i]['title']}',
  ];
  return '$currentIndex:${queue.length}:${Object.hashAll(ids)}';
}

/// What [target] is playing, with the songs that follow when the remote's
/// [knownQueue] signature is not the current one.
RemoteSnapshot buildRemoteSnapshot(
  RemotePlaybackTarget target, {
  String? knownQueue,
}) {
  final queue = target.queue;
  final index = target.currentIndex;
  final hasTrack = index >= 0 && index < queue.length;
  final signature = remoteQueueSignature(queue, index);
  final track = hasTrack ? RemoteTrack.fromSong(queue[index], index) : null;
  final duration = target.duration;
  return RemoteSnapshot(
    track: track,
    playing: target.playing,
    processing: hasTrack ? target.processing : RemoteProcessing.idle,
    positionMs: max(0, target.position.inMilliseconds),
    durationMs: duration != null && duration > Duration.zero
        ? duration.inMilliseconds
        : track?.durationMs,
    speed: target.speed,
    canNext: target.canSkipToNext,
    canPrevious: hasTrack,
    queueSignature: signature,
    upcoming: knownQueue == signature
        ? null
        : [
            if (hasTrack)
              for (
                var i = index + 1;
                i < min(queue.length, index + 1 + remoteQueueLimit);
                i++
              )
                RemoteTrack.fromSong(queue[i], i),
          ],
  );
}

/// Why a command was refused, as sent back to the remote.
enum RemoteCommandError { queueChanged, nothingPlaying }

/// Runs [command] on [target]. Waits at most [settle] for it, so the reply
/// can already show the result of a quick command, while a slow one (loading
/// the next song) carries on and shows up in the next snapshot.
Future<({RemoteCommandError? error, int? added})> dispatchRemoteCommand(
  RemotePlaybackTarget target,
  RemoteCommand command, {
  Duration settle = const Duration(milliseconds: 1500),
  void Function(Object error, StackTrace stackTrace)? onError,
}) async {
  Future<void> run(Future<void> Function() action) async {
    final future = action();
    unawaited(
      future.catchError((Object e, StackTrace s) => onError?.call(e, s)),
    );
    await Future.any([future.catchError((_) {}), Future<void>.delayed(settle)]);
  }

  switch (command.action) {
    case RemoteAction.play:
      await run(target.play);
    case RemoteAction.pause:
      await run(target.pause);
    case RemoteAction.next:
      await run(target.skipToNext);
    case RemoteAction.previous:
      await run(target.skipToPrevious);
    case RemoteAction.seek:
      var position = Duration(milliseconds: command.positionMs!);
      final duration = target.duration;
      if (duration != null && duration > Duration.zero && position > duration) {
        position = duration;
      }
      await run(() => target.seek(position));
    case RemoteAction.skipTo:
      final queue = target.queue;
      final index = command.index!;
      // The list the remote tapped in may be a second old: never play
      // another song than the one shown.
      if (index >= queue.length ||
          (queue[index]['ytid']?.toString() ?? '') != command.ytid) {
        return (error: RemoteCommandError.queueChanged, added: null);
      }
      await run(() => target.skipToSong(index));
    case RemoteAction.radio:
      final queue = target.queue;
      final index = target.currentIndex;
      if (index < 0 || index >= queue.length) {
        return (error: RemoteCommandError.nothingPlaying, added: null);
      }
      // The remote wants to know whether it worked: wait for it, the radio
      // gives up on its own after a while.
      try {
        return (error: null, added: await target.startRadio());
      } catch (e, stackTrace) {
        onError?.call(e, stackTrace);
        return (error: null, added: 0);
      }
  }
  return (error: null, added: null);
}
