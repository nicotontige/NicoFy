import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nicofy/services/remote_control/remote_protocol.dart';

import 'fake_target.dart';

/// What the other end gets: the map after a trip through JSON.
Map<String, dynamic> wire(Map<String, dynamic> map) =>
    jsonDecode(jsonEncode(map)) as Map<String, dynamic>;

void main() {
  group('snapshot', () {
    test('carries the song playing and those after it, not the played', () {
      final target = FakeTarget(
        queue: [song('a'), song('b'), song('c'), song('d')],
        currentIndex: 1,
      );
      final snapshot = RemoteSnapshot.fromMap(
        wire(buildRemoteSnapshot(target).toMap()),
      );

      expect(snapshot.track!.ytid, 'b');
      expect(snapshot.track!.index, 1);
      expect(snapshot.track!.title, 'Title b');
      expect(snapshot.track!.artist, 'Artist b');
      expect(
        snapshot.track!.artworkUrl,
        'https://i.ytimg.com/vi/b/hqdefault.jpg',
      );
      expect(snapshot.playing, isTrue);
      expect(snapshot.processing, RemoteProcessing.ready);
      expect(snapshot.positionMs, 42000);
      expect(snapshot.durationMs, 180000);
      expect(snapshot.canNext, isTrue);
      expect(snapshot.isActive, isTrue);
      // Real indexes, so that tapping one plays that very entry.
      expect(snapshot.upcoming!.map((t) => (t.index, t.ytid)), [
        (2, 'c'),
        (3, 'd'),
      ]);
    });

    test('leaves the queue out when the remote already has it', () {
      final target = FakeTarget();
      final first = buildRemoteSnapshot(target);
      expect(first.upcoming, isNotNull);

      final same = buildRemoteSnapshot(
        target,
        knownQueue: first.queueSignature,
      );
      expect(same.upcoming, isNull);

      target.currentIndex = 1;
      final moved = buildRemoteSnapshot(
        target,
        knownQueue: first.queueSignature,
      );
      expect(moved.queueSignature, isNot(first.queueSignature));
      expect(moved.upcoming!.map((t) => t.ytid), ['c']);

      target.queue = [...target.queue, song('z')];
      final grown = buildRemoteSnapshot(
        target,
        knownQueue: moved.queueSignature,
      );
      expect(grown.upcoming!.map((t) => t.ytid), ['c', 'z']);
    });

    test('caps the queue it sends', () {
      final target = FakeTarget(
        queue: [for (var i = 0; i < 500; i++) song('s$i')],
      );
      final snapshot = buildRemoteSnapshot(target);
      expect(snapshot.upcoming, hasLength(remoteQueueLimit));
      expect(snapshot.upcoming!.last.index, remoteQueueLimit);
    });

    test('sends web artwork only: a local file means nothing there', () {
      final local = RemoteTrack.fromSong(
        song('a', image: '/storage/emulated/0/artwork.jpg'),
        0,
      );
      expect(local.artworkUrl, isNull);
      final lowRes = RemoteTrack.fromSong({
        'ytid': 'a',
        'title': 't',
        'artist': 'x',
        'highResImage': 'file:///a.jpg',
        'lowResImage': 'https://i.ytimg.com/vi/a/default.jpg',
      }, 0);
      expect(lowRes.artworkUrl, 'https://i.ytimg.com/vi/a/default.jpg');
      expect(
        RemoteTrack.fromMap({'index': 0, 'artwork': 'javascript:alert(1)'})
            .artworkUrl,
        isNull,
      );
    });

    test('nothing loaded is nothing playing', () {
      final target = FakeTarget(queue: []);
      final snapshot = RemoteSnapshot.fromMap(
        wire(buildRemoteSnapshot(target).toMap()),
      );
      expect(snapshot.track, isNull);
      expect(snapshot.isActive, isFalse);
      expect(snapshot.upcoming, isEmpty);
    });

    test('the position moves on while it plays, and stops at the end', () {
      final snapshot = RemoteSnapshot.fromMap({
        'track': {'index': 0, 'ytid': 'a'},
        'playing': true,
        'state': 'ready',
        'positionMs': 10000,
        'durationMs': 12000,
      });
      expect(
        snapshot.positionAfter(const Duration(seconds: 1)),
        const Duration(seconds: 11),
      );
      expect(
        snapshot.positionAfter(const Duration(seconds: 30)),
        const Duration(seconds: 12),
      );
      final paused = snapshot.copyWith(playing: false);
      expect(
        paused.positionAfter(const Duration(seconds: 5)),
        const Duration(seconds: 10),
      );
    });

    test('rejects what is not a snapshot', () {
      expect(() => RemoteSnapshot.fromMap('x'), throwsFormatException);
      expect(
        () => RemoteSnapshot.fromMap({'queue': 'x'}),
        throwsFormatException,
      );
      expect(
        () => RemoteSnapshot.fromMap({
          'track': {'index': -1},
        }),
        throwsFormatException,
      );
    });
  });

  group('command', () {
    test('survives the trip', () {
      final track = RemoteTrack.fromSong(song('b'), 4);
      for (final command in [
        const RemoteCommand.play(),
        const RemoteCommand.pause(),
        const RemoteCommand.next(),
        const RemoteCommand.previous(),
        const RemoteCommand.radio(),
        RemoteCommand.seek(const Duration(seconds: 30)),
        RemoteCommand.skipTo(track),
      ]) {
        final back = RemoteCommand.fromMap(wire(command.toMap()));
        expect(back.toMap(), command.toMap());
      }
    });

    test('refuses what the protocol does not define', () {
      for (final raw in [
        <String, dynamic>{},
        {'action': 'format_disk'},
        {'action': 'seek'},
        {'action': 'seek', 'positionMs': -5},
        {'action': 'skipTo', 'index': 2},
        {'action': 'skipTo', 'index': '2', 'ytid': 'b'},
      ]) {
        expect(() => RemoteCommand.fromMap(raw), throwsFormatException);
      }
    });

    test('each action reaches the player', () async {
      final target = FakeTarget(queue: [song('a'), song('b'), song('c')]);
      Future<void> run(RemoteCommand command) =>
          dispatchRemoteCommand(target, command);

      await run(const RemoteCommand.pause());
      await run(const RemoteCommand.play());
      await run(const RemoteCommand.next());
      await run(const RemoteCommand.previous());
      await run(RemoteCommand.seek(const Duration(seconds: 7)));
      await run(RemoteCommand.skipTo(RemoteTrack.fromSong(song('c'), 2)));
      expect(target.calls, [
        'pause',
        'play',
        'next',
        'previous',
        'seek:7000',
        'skipTo:2',
      ]);
      expect(target.currentIndex, 2);
    });

    test('a seek past the end stops at the end', () async {
      final target = FakeTarget();
      await dispatchRemoteCommand(
        target,
        RemoteCommand.seek(const Duration(hours: 2)),
      );
      expect(target.calls, ['seek:180000']);
    });

    test('never plays another song than the one tapped', () async {
      final target = FakeTarget(queue: [song('a'), song('b'), song('c')]);
      final shown = RemoteTrack.fromSong(song('c'), 2);
      // The queue changed there after the list was shown.
      target.queue = [song('a'), song('x'), song('y')];
      final moved = await dispatchRemoteCommand(
        target,
        RemoteCommand.skipTo(shown),
      );
      expect(moved.error, RemoteCommandError.queueChanged);

      final gone = await dispatchRemoteCommand(
        target,
        RemoteCommand.skipTo(RemoteTrack.fromSong(song('c'), 9)),
      );
      expect(gone.error, RemoteCommandError.queueChanged);
      expect(target.calls, isEmpty);
    });

    test('the radio says how many songs it queued', () async {
      final target = FakeTarget();
      final result = await dispatchRemoteCommand(
        target,
        const RemoteCommand.radio(),
      );
      expect(result.added, 25);
      expect(target.calls, ['radio']);

      final idle = FakeTarget(queue: []);
      final none = await dispatchRemoteCommand(
        idle,
        const RemoteCommand.radio(),
      );
      expect(none.error, RemoteCommandError.nothingPlaying);
      expect(idle.calls, isEmpty);
    });

    test('a slow command does not hold the reply', () async {
      final target = _SlowTarget();
      final stopwatch = Stopwatch()..start();
      await dispatchRemoteCommand(
        target,
        const RemoteCommand.next(),
        settle: const Duration(milliseconds: 50),
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      target.loading.complete();
    });
  });
}

class _SlowTarget extends FakeTarget {
  final loading = Completer<void>();

  @override
  Future<void> skipToNext() => loading.future;
}
