import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nicofy/services/remote_control/remote_protocol.dart';

import 'fake_target.dart';

Map<String, dynamic> wire(Map<String, dynamic> map) =>
    jsonDecode(jsonEncode(map)) as Map<String, dynamic>;

RemoteCommand trip(RemoteCommand command) =>
    RemoteCommand.fromMap(wire(command.toMap()));

void main() {
  group('songs sent over', () {
    test('keep what plays and shows, never a path of this device', () {
      final sent = remoteSong({
        ...song('a'),
        'album': 'Album',
        'audioPath': '/storage/emulated/0/a.m4a',
        'artworkPath': '/storage/emulated/0/a.jpg',
        'lowResImage': '/data/thumb.jpg',
      })!;
      expect(sent['ytid'], 'a');
      expect(sent['title'], 'Title a');
      expect(sent['album'], 'Album');
      expect(sent['duration'], 180);
      expect(sent['highResImage'], 'https://i.ytimg.com/vi/a/hqdefault.jpg');
      expect(sent.keys, isNot(contains('audioPath')));
      expect(sent.keys, isNot(contains('artworkPath')));
      expect(sent.keys, isNot(contains('lowResImage')));
    });

    test('a song with no YouTube id cannot go', () {
      expect(remoteSong({'title': 'Only here'}), isNull);
      expect(remoteSong({'ytid': '', 'title': 'x'}), isNull);
      expect(remoteSong('x'), isNull);
    });
  });

  group('a long list', () {
    final long = [for (var i = 0; i < 1200; i++) song('s$i')];

    test('goes whole when small, without what cannot play', () {
      final window = remoteListWindow([
        song('a'),
        {'title': 'only here'},
        song('b'),
      ], startIndex: 2);
      expect(window.songs.map((s) => s['ytid']), ['a', 'b']);
      expect(window.startIndex, 1);
    });

    test('is cut around the song it starts from', () {
      final window = remoteListWindow(long, startIndex: 700);
      expect(window.songs, hasLength(remoteListLimit));
      expect(window.songs[window.startIndex!]['ytid'], 's700');
      expect(window.startIndex, 50, reason: 'a few songs before it');
    });

    test('near its end still sends a full window', () {
      final window = remoteListWindow(long, startIndex: 1190);
      expect(window.songs, hasLength(remoteListLimit));
      expect(window.songs.last['ytid'], 's1199');
      expect(window.songs[window.startIndex!]['ytid'], 's1190');
    });

    test('shuffled, keeps the song tapped first', () {
      final window = remoteListWindow(
        long,
        startIndex: 3,
        shuffle: true,
        random: Random(1),
      );
      expect(window.songs, hasLength(remoteListLimit));
      expect(window.startIndex, 0);
      expect(window.songs.first['ytid'], 's3');
    });

    test('says when the song tapped cannot go', () {
      final window = remoteListWindow([
        {'title': 'only here'},
        song('b'),
      ], startIndex: 0);
      expect(window.startIndex, isNull);
    });
  });

  group('commands', () {
    final track = RemoteTrack.fromSong(song('b'), 3, entryId: 'entry-b');

    test('survive the trip', () {
      for (final command in [
        RemoteCommand.playList([remoteSong(song('a'))!], startIndex: 0),
        RemoteCommand.playList([remoteSong(song('a'))!], shuffle: true),
        RemoteCommand.enqueue([remoteSong(song('a'))!], next: true),
        RemoteCommand.playSong(remoteSong(song('a'))!),
        RemoteCommand.playStation(
          id: 'fip',
          name: 'FIP',
          streamUrl: 'https://example.org/fip.mp3',
          image: 'https://example.org/fip.png',
          genre: 'Jazz',
        ),
        RemoteCommand.removeEntry(track),
        RemoteCommand.moveEntry(track, 5),
        RemoteCommand.playEntryNext(track),
        RemoteCommand.skipTo(track),
        const RemoteCommand.clearQueue(),
        const RemoteCommand.shuffleQueue(),
      ]) {
        expect(trip(command).toMap(), command.toMap());
      }
    });

    test('refuse what is malformed', () {
      final ok = remoteSong(song('a'))!;
      for (final raw in <Map<String, dynamic>>[
        {'action': 'playList', 'songs': <Object>[]},
        {
          'action': 'playList',
          'songs': [for (var i = 0; i <= remoteListLimit; i++) ok],
        },
        {
          'action': 'playList',
          'songs': [ok],
          'startIndex': 1,
        },
        {
          'action': 'playList',
          'songs': [
            {'title': 'no id'},
          ],
        },
        {
          'action': 'playList',
          'songs': [ok],
          'shuffle': 'yes',
        },
        {'action': 'enqueue', 'songs': 'a'},
        {'action': 'playSong'},
        {
          'action': 'playStation',
          'id': 'x',
          'name': 'x',
          'streamUrl': 'file:///etc/passwd',
          'image': '',
        },
        {'action': 'removeEntry'},
        {'action': 'moveEntry', 'entry': 'e'},
        {'action': 'playEntryNext', 'entry': ''},
      ]) {
        expect(
          () => RemoteCommand.fromMap(raw),
          throwsFormatException,
          reason: '$raw',
        );
      }
    });
  });

  group('dispatch', () {
    FakeTarget fourSongs() =>
        FakeTarget(queue: [song('a'), song('b'), song('c'), song('d')]);

    Future<({RemoteCommandError? error, int? added})> run(
      FakeTarget target,
      RemoteCommand command,
    ) => dispatchRemoteCommand(target, trip(command));

    test('a list plays there from the song tapped', () async {
      final target = fourSongs();
      await run(
        target,
        RemoteCommand.playList([
          remoteSong(song('x'))!,
          remoteSong(song('y'))!,
        ], startIndex: 1),
      );
      expect(target.calls, ['playList:2:1:null']);
      expect(target.queue[target.currentIndex]['ytid'], 'y');
    });

    test('songs are queued there, next or at the end', () async {
      final target = fourSongs();
      await run(target, RemoteCommand.enqueue([remoteSong(song('x'))!]));
      await run(
        target,
        RemoteCommand.enqueue([remoteSong(song('y'))!], next: true),
      );
      expect(target.queue.map((s) => s['ytid']), [
        'a',
        'y',
        'b',
        'c',
        'd',
        'x',
      ]);
    });

    test('a song and a station play there', () async {
      final target = fourSongs();
      await run(target, RemoteCommand.playSong(remoteSong(song('x'))!));
      final station = await run(
        target,
        RemoteCommand.playStation(
          id: 'fip',
          name: 'FIP',
          streamUrl: 'https://example.org/fip.mp3',
          image: '',
        ),
      );
      expect(station.error, isNull);
      target.stationPlays = false;
      final dead = await run(
        target,
        RemoteCommand.playStation(
          id: 'dead',
          name: 'Dead',
          streamUrl: 'https://example.org/dead.mp3',
          image: '',
        ),
      );
      expect(dead.error, RemoteCommandError.unplayable);
      expect(target.calls, [
        'playSong:x',
        'station:fip:https://example.org/fip.mp3',
        'station:dead:https://example.org/dead.mp3',
      ]);
    });

    test('an entry is removed by its id, wherever it moved', () async {
      final target = fourSongs();
      final shown = RemoteTrack.fromSong(song('c'), 2, entryId: 'entry-c');
      // Something was queued before it meanwhile.
      target.queue.insert(1, song('x'));
      await run(target, RemoteCommand.removeEntry(shown));
      expect(target.calls, ['remove:3']);
      expect(target.queue.map((s) => s['ytid']), ['a', 'x', 'b', 'd']);
    });

    test('an entry that is gone is not touched', () async {
      final target = fourSongs();
      final gone = RemoteTrack.fromSong(song('z'), 2, entryId: 'entry-z');
      for (final command in [
        RemoteCommand.removeEntry(gone),
        RemoteCommand.moveEntry(gone, 1),
        RemoteCommand.playEntryNext(gone),
        RemoteCommand.skipTo(gone),
      ]) {
        expect(
          (await run(target, command)).error,
          RemoteCommandError.queueChanged,
        );
      }
      expect(target.calls, isEmpty);
    });

    test('moves stay below the song playing', () async {
      final target = fourSongs()..currentIndex = 1;
      final d = RemoteTrack.fromSong(song('d'), 3, entryId: 'entry-d');
      await run(target, RemoteCommand.moveEntry(d, 0));
      expect(target.calls, ['move:entry-d:2']);
      expect(target.queue.map((s) => s['ytid']), ['a', 'b', 'd', 'c']);

      final playing = RemoteTrack.fromSong(song('b'), 1, entryId: 'entry-b');
      expect(
        (await run(target, RemoteCommand.moveEntry(playing, 3))).error,
        RemoteCommandError.queueChanged,
      );
    });

    test('play next brings an entry right after the song playing', () async {
      final target = fourSongs();
      final d = RemoteTrack.fromSong(song('d'), 3, entryId: 'entry-d');
      await run(target, RemoteCommand.playEntryNext(d));
      expect(target.queue.map((s) => s['ytid']), ['a', 'd', 'b', 'c']);
      // Already next: nothing to do.
      await run(target, RemoteCommand.playEntryNext(d));
      expect(target.calls, ['move:entry-d:1']);
    });

    test('tapping an entry plays it even after the queue moved', () async {
      final target = fourSongs();
      final c = RemoteTrack.fromSong(song('c'), 2, entryId: 'entry-c');
      target.queue.insert(0, song('x'));
      await run(target, RemoteCommand.skipTo(c));
      expect(target.calls, ['skipTo:3']);
    });

    test('the queue is cleared and shuffled there', () async {
      final target = fourSongs();
      await run(target, const RemoteCommand.shuffleQueue());
      await run(target, const RemoteCommand.clearQueue());
      expect(target.calls, ['shuffle', 'clear']);
      expect(target.queue.map((s) => s['ytid']), ['a']);
    });

    test('snapshots carry the entry ids', () {
      final snapshot = RemoteSnapshot.fromMap(
        wire(buildRemoteSnapshot(fourSongs()).toMap()),
      );
      expect(snapshot.track!.entryId, 'entry-a');
      expect(snapshot.upcoming!.map((t) => t.entryId), [
        'entry-b',
        'entry-c',
        'entry-d',
      ]);
      expect(snapshot.upcoming!.first.toSong()['ytid'], 'b');
    });
  });
}
