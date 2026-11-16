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
    this.entryId = '',
  });

  factory RemoteTrack.fromSong(Map song, int index, {String entryId = ''}) =>
      RemoteTrack(
        index: index,
        entryId: _text(entryId, 128),
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
      entryId: _text(map['entry'], 128),
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

  /// The entry's id in the queue over there: it stays the same while the
  /// songs around it move, so a queue edit reaches the song that was shown.
  final String entryId;

  /// As a song of this device's library, for what stays here: liking it,
  /// adding it to a playlist, downloading it.
  Map<String, dynamic> toSong() => {
    'ytid': ytid,
    'title': title,
    'artist': artist,
    if (artworkUrl != null) 'highResImage': artworkUrl,
    if (artworkUrl != null) 'lowResImage': artworkUrl,
    if (durationMs != null) 'duration': durationMs! ~/ 1000,
    if (isLive) 'isLive': true,
  };

  Map<String, dynamic> toMap() => {
    'index': index,
    if (entryId.isNotEmpty) 'entry': entryId,
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

enum RemoteAction {
  play,
  pause,
  next,
  previous,
  seek,
  skipTo,
  radio,

  /// Replaces the queue with a list and plays it from one of its songs.
  playList,

  /// Adds songs to the queue, after the current one or at its end.
  enqueue,

  /// Plays one song, the queue left as it is.
  playSong,

  /// Plays a radio station's stream.
  playStation,
  removeEntry,
  moveEntry,

  /// Brings a queued song right after the current one.
  playEntryNext,
  clearQueue,
  shuffleQueue,
}

/// How many songs a list sent to the other device may hold. A bigger list is
/// cut around the song it starts from (see [remoteListWindow]).
const int remoteListLimit = 500;

/// The keys of a song that are worth sending: what it takes to play it there
/// and show it. Paths of files on this device are left out.
const _songKeys = {
  'ytid',
  'title',
  'artist',
  'album',
  'artistId',
  'videoAuthor',
  'duration',
  'isLive',
};

/// [song] as sent to the other device; null when it cannot play there, as it
/// has no YouTube id.
Map<String, dynamic>? remoteSong(Object? song) {
  if (song is! Map) return null;
  final ytid = song['ytid']?.toString() ?? '';
  if (ytid.isEmpty || ytid.length > 64) return null;
  final result = <String, dynamic>{};
  for (final key in _songKeys) {
    final value = song[key];
    if (value is String) {
      result[key] = _text(value, 300);
    } else if (value is num && value.isFinite) {
      result[key] = value;
    } else if (value is bool) {
      result[key] = value;
    }
  }
  for (final key in ['highResImage', 'lowResImage']) {
    final url = remoteArtworkUrl({'image': song[key]});
    if (url != null) result[key] = url;
  }
  return result;
}

/// The part of [songs] that is sent to play from [startIndex]: the songs that
/// can play there, at most [remoteListLimit] of them, a few before the start
/// and the rest after it. A shuffled list is shuffled here first, so that the
/// cut does not always keep the same songs. [startIndex] is null when the
/// song it pointed at cannot play there.
({List<Map<String, dynamic>> songs, int? startIndex}) remoteListWindow(
  List<Map> songs, {
  int? startIndex,
  bool shuffle = false,
  Random? random,
}) {
  final sendable = <Map<String, dynamic>>[];
  int? start;
  for (var i = 0; i < songs.length; i++) {
    final song = remoteSong(songs[i]);
    if (song == null) continue;
    if (i == startIndex) start = sendable.length;
    sendable.add(song);
  }
  if (sendable.length <= remoteListLimit) {
    return (songs: sendable, startIndex: start);
  }
  if (shuffle) {
    final first = start == null ? null : sendable.removeAt(start);
    sendable.shuffle(random);
    return (
      songs: [
        ?first,
        ...sendable.take(remoteListLimit - (first == null ? 0 : 1)),
      ],
      startIndex: first == null ? null : 0,
    );
  }
  const before = 50;
  final from = start == null
      ? 0
      : max(0, min(start - before, sendable.length - remoteListLimit));
  return (
    songs: sendable.sublist(from, from + remoteListLimit),
    startIndex: start == null ? null : start - from,
  );
}

List<Map<String, dynamic>> _songs(Object? raw) {
  if (raw is! List || raw.isEmpty || raw.length > remoteListLimit) {
    throw const FormatException('Invalid song list');
  }
  return [
    for (final song in raw)
      remoteSong(song) ?? (throw const FormatException('Invalid song')),
  ];
}

String _entry(Object? raw) {
  if (raw is! String || raw.isEmpty || raw.length > 128) {
    throw const FormatException('Invalid queue entry');
  }
  return raw;
}

bool _isWebUrl(Object? raw) {
  if (raw is! String || raw.length > 2048) return false;
  final uri = Uri.tryParse(raw);
  return uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty;
}

/// Something the remote asks the controlled device to do.
class RemoteCommand {
  const RemoteCommand._(this.action, [this.args = const {}]);

  const RemoteCommand.play() : this._(RemoteAction.play);
  const RemoteCommand.pause() : this._(RemoteAction.pause);
  const RemoteCommand.next() : this._(RemoteAction.next);
  const RemoteCommand.previous() : this._(RemoteAction.previous);
  const RemoteCommand.radio() : this._(RemoteAction.radio);
  const RemoteCommand.clearQueue() : this._(RemoteAction.clearQueue);
  const RemoteCommand.shuffleQueue() : this._(RemoteAction.shuffleQueue);

  RemoteCommand.seek(Duration position)
    : this._(RemoteAction.seek, {
        'positionMs': max(0, position.inMilliseconds),
      });

  /// Plays [track]; refused if the queue there moved since it was listed.
  RemoteCommand.skipTo(RemoteTrack track)
    : this._(RemoteAction.skipTo, {
        'index': track.index,
        'ytid': track.ytid,
        if (track.entryId.isNotEmpty) 'entry': track.entryId,
      });

  /// [songs] as made by [remoteListWindow]; [shuffle] null leaves it to the
  /// other device's shuffle setting.
  RemoteCommand.playList(
    List<Map<String, dynamic>> songs, {
    int? startIndex,
    bool? shuffle,
  }) : this._(RemoteAction.playList, {
         'songs': songs,
         'startIndex': ?startIndex,
         'shuffle': ?shuffle,
       });

  RemoteCommand.enqueue(
    List<Map<String, dynamic>> songs, {
    bool next = false,
    int? startIndex,
  }) : this._(RemoteAction.enqueue, {
         'songs': songs,
         if (next) 'next': true,
         'startIndex': ?startIndex,
       });

  RemoteCommand.playSong(Map<String, dynamic> song)
    : this._(RemoteAction.playSong, {'song': song});

  RemoteCommand.playStation({
    required String id,
    required String name,
    required String streamUrl,
    required String image,
    String? genre,
  }) : this._(RemoteAction.playStation, {
         'id': id,
         'name': name,
         'streamUrl': streamUrl,
         'image': image,
         'genre': ?genre,
       });

  RemoteCommand.removeEntry(RemoteTrack track)
    : this._(RemoteAction.removeEntry, {'entry': track.entryId});

  /// Moves [track] to [toIndex], an index of the whole queue over there.
  RemoteCommand.moveEntry(RemoteTrack track, int toIndex)
    : this._(RemoteAction.moveEntry, {
        'entry': track.entryId,
        'toIndex': max(0, toIndex),
      });

  RemoteCommand.playEntryNext(RemoteTrack track)
    : this._(RemoteAction.playEntryNext, {'entry': track.entryId});

  /// Throws [FormatException] for anything the protocol does not define.
  factory RemoteCommand.fromMap(Map map) {
    final action = RemoteAction.values
        .where((value) => value.name == map['action'])
        .firstOrNull;
    if (action == null) throw const FormatException('Unknown remote action');
    int? optionalIndex(String key) {
      final value = map[key];
      if (value == null) return null;
      return _nonNegativeInt(value) ??
          (throw const FormatException('Invalid index'));
    }

    switch (action) {
      case RemoteAction.seek:
        final position = _nonNegativeInt(map['positionMs']);
        if (position == null) throw const FormatException('Invalid seek');
        return RemoteCommand._(action, {'positionMs': position});
      case RemoteAction.skipTo:
        final index = _nonNegativeInt(map['index']);
        final ytid = map['ytid'];
        if (index == null || ytid is! String) {
          throw const FormatException('Invalid skip');
        }
        return RemoteCommand._(action, {
          'index': index,
          'ytid': ytid,
          if (map['entry'] != null) 'entry': _entry(map['entry']),
        });
      case RemoteAction.playList:
        final shuffle = map['shuffle'];
        if (shuffle != null && shuffle is! bool) {
          throw const FormatException('Invalid shuffle');
        }
        final songs = _songs(map['songs']);
        final start = optionalIndex('startIndex');
        if (start != null && start >= songs.length) {
          throw const FormatException('Invalid start');
        }
        return RemoteCommand._(action, {
          'songs': songs,
          'startIndex': ?start,
          'shuffle': ?shuffle,
        });
      case RemoteAction.enqueue:
        final songs = _songs(map['songs']);
        final start = optionalIndex('startIndex');
        if (start != null && start >= songs.length) {
          throw const FormatException('Invalid start');
        }
        return RemoteCommand._(action, {
          'songs': songs,
          if (map['next'] == true) 'next': true,
          'startIndex': ?start,
        });
      case RemoteAction.playSong:
        final song = remoteSong(map['song']);
        if (song == null) throw const FormatException('Invalid song');
        return RemoteCommand._(action, {'song': song});
      case RemoteAction.playStation:
        final id = map['id'];
        final name = map['name'];
        final image = map['image'];
        final genre = map['genre'];
        if (id is! String ||
            id.isEmpty ||
            name is! String ||
            !_isWebUrl(map['streamUrl']) ||
            (genre != null && genre is! String)) {
          throw const FormatException('Invalid station');
        }
        return RemoteCommand._(action, {
          'id': _text(id, 128),
          'name': _text(name, 300),
          'streamUrl': map['streamUrl'],
          'image': _isWebUrl(image) ? image : '',
          'genre': ?(genre == null ? null : _text(genre, 300)),
        });
      case RemoteAction.removeEntry:
      case RemoteAction.playEntryNext:
        return RemoteCommand._(action, {'entry': _entry(map['entry'])});
      case RemoteAction.moveEntry:
        final toIndex = _nonNegativeInt(map['toIndex']);
        if (toIndex == null) throw const FormatException('Invalid move');
        return RemoteCommand._(action, {
          'entry': _entry(map['entry']),
          'toIndex': toIndex,
        });
      case RemoteAction.play:
      case RemoteAction.pause:
      case RemoteAction.next:
      case RemoteAction.previous:
      case RemoteAction.radio:
      case RemoteAction.clearQueue:
      case RemoteAction.shuffleQueue:
        return RemoteCommand._(action);
    }
  }

  final RemoteAction action;

  /// What goes with [action], already checked when it came from the network.
  final Map<String, dynamic> args;

  int? get positionMs => args['positionMs'] as int?;
  int? get index => args['index'] as int?;
  String? get ytid => args['ytid'] as String?;
  String? get entryId => args['entry'] as String?;
  int? get startIndex => args['startIndex'] as int?;
  int? get toIndex => args['toIndex'] as int?;
  bool? get shuffle => args['shuffle'] as bool?;
  bool get playNext => args['next'] == true;
  List<Map<String, dynamic>> get songs =>
      (args['songs'] as List? ?? const []).cast<Map<String, dynamic>>();
  Map<String, dynamic>? get song => args['song'] as Map<String, dynamic>?;

  Map<String, dynamic> toMap() => {'action': action.name, ...args};
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

  /// The id of a queue entry, which does not change while it moves.
  String entryIdOf(Map song);

  Future<void> play();
  Future<void> pause();
  Future<void> skipToNext();
  Future<void> skipToPrevious();
  Future<void> seek(Duration position);

  /// [index] is in the whole queue, as in [queue].
  Future<void> skipToSong(int index);

  /// Returns how many songs were queued.
  Future<int> startRadio();

  /// Replaces the queue with [songs], playing from [startIndex].
  Future<void> playList(List<Map> songs, {int? startIndex, bool? shuffle});

  /// Adds [songs] after the current song when [next], else at the end,
  /// playing from [startIndex] when given.
  Future<void> enqueue(List<Map> songs, {bool next = false, int? startIndex});

  Future<void> playSong(Map song);

  Future<bool> playStation({
    required String id,
    required String name,
    required String streamUrl,
    required String image,
    String? genre,
  });

  Future<void> removeFromQueue(int index);

  /// Moves the entry [entryId] to [toIndex] in the whole queue.
  Future<void> moveEntry(String entryId, int toIndex);
  Future<void> clearQueue();
  Future<void> shuffleQueue();
}

/// Identifies the songs after the current one, cheaply, so an unchanged
/// queue is not sent again every second. It only has to differ from what the
/// same device said before, never to mean anything elsewhere.
String remoteQueueSignature(
  List<Map> queue,
  int currentIndex, [
  String Function(Map song)? entryIdOf,
]) {
  final end = min(queue.length, currentIndex + 1 + remoteQueueLimit);
  final start = min(max(currentIndex, 0), end);
  String id(Map song) =>
      '${song['ytid']}\u0000${song['title']}\u0000${entryIdOf?.call(song)}';
  final ids = [for (var i = start; i < end; i++) id(queue[i])];
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
  final signature = remoteQueueSignature(queue, index, target.entryIdOf);
  RemoteTrack trackAt(int i) =>
      RemoteTrack.fromSong(queue[i], i, entryId: target.entryIdOf(queue[i]));
  final track = hasTrack ? trackAt(index) : null;
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
                trackAt(i),
          ],
  );
}

/// Why a command was refused, as sent back to the remote.
enum RemoteCommandError { queueChanged, nothingPlaying, unplayable }

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

  const done = (error: null, added: null);
  const queueChanged = (error: RemoteCommandError.queueChanged, added: null);
  final queue = target.queue;
  final current = target.currentIndex;

  /// Where the entry the remote showed is now, -1 when it is gone.
  int entryIndex(String? entryId) => entryId == null
      ? -1
      : queue.indexWhere((song) => target.entryIdOf(song) == entryId);

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
      // The list the remote tapped in may be a second old: never play
      // another song than the one shown.
      var index = command.index!;
      if (command.entryId != null) {
        index = entryIndex(command.entryId);
        if (index == -1) return queueChanged;
      } else if (index >= queue.length ||
          (queue[index]['ytid']?.toString() ?? '') != command.ytid) {
        return queueChanged;
      }
      await run(() => target.skipToSong(index));
    case RemoteAction.radio:
      if (current < 0 || current >= queue.length) {
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
    case RemoteAction.playList:
      await run(
        () => target.playList(
          command.songs,
          startIndex: command.startIndex,
          shuffle: command.shuffle,
        ),
      );
    case RemoteAction.enqueue:
      await run(
        () => target.enqueue(
          command.songs,
          next: command.playNext,
          startIndex: command.startIndex,
        ),
      );
    case RemoteAction.playSong:
      await run(() => target.playSong(command.song!));
    case RemoteAction.playStation:
      final args = command.args;
      // A stream starts quickly, or not at all: wait to say which.
      try {
        final started = await target.playStation(
          id: args['id'] as String,
          name: args['name'] as String,
          streamUrl: args['streamUrl'] as String,
          image: args['image'] as String,
          genre: args['genre'] as String?,
        );
        if (started) return done;
      } catch (e, stackTrace) {
        onError?.call(e, stackTrace);
      }
      return (error: RemoteCommandError.unplayable, added: null);
    case RemoteAction.removeEntry:
      final index = entryIndex(command.entryId);
      if (index == -1) return queueChanged;
      await run(() => target.removeFromQueue(index));
    case RemoteAction.moveEntry:
      final index = entryIndex(command.entryId);
      // Only the songs still to come move, and never above the one playing.
      if (index == -1 || index <= current) return queueChanged;
      final to = command.toIndex!.clamp(current + 1, queue.length - 1);
      await run(() => target.moveEntry(command.entryId!, to));
    case RemoteAction.playEntryNext:
      final index = entryIndex(command.entryId);
      if (index == -1 || index <= current) return queueChanged;
      if (index > current + 1) {
        await run(() => target.moveEntry(command.entryId!, current + 1));
      }
    case RemoteAction.clearQueue:
      await run(target.clearQueue);
    case RemoteAction.shuffleQueue:
      await run(target.shuffleQueue);
  }
  return done;
}
