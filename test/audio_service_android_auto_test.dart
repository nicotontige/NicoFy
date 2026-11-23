import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:nicofy/services/audio_service_android_auto.dart';
import 'package:nicofy/services/common_services.dart';
import 'package:nicofy/services/settings_manager.dart';

void main() {
  late Directory temporaryDirectory;
  late _FakeAndroidAutoHost host;
  late AndroidAutoBrowser browser;

  setUpAll(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'nicofy_android_auto_test',
    );
    Hive.init(temporaryDirectory.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
  });

  setUp(() {
    host = _FakeAndroidAutoHost();
    browser = AndroidAutoBrowser(host);
  });

  tearDownAll(() async {
    await Hive.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('browsable root exposes the expected categories', () async {
    final children = await browser.children(AudioService.browsableRootId);

    expect(children.map((item) => item.id), [
      'current_queue',
      'liked_songs',
      'playlists',
      'offline_songs',
      'recently_played',
    ]);
    expect(children.every((item) => item.playable == false), isTrue);
  });

  test('queue item media IDs resolve back to their song', () async {
    host.queue.add(_song());

    final queueItems = await browser.children('current_queue');
    expect(queueItems, hasLength(1));
    expect(queueItems.single.id, 'song:current_queue:entry-1');
    expect(queueItems.single.playable, isTrue);

    final resolved = await browser.mediaItemForId(queueItems.single.id);
    expect(resolved?.id, 'song:current_queue:entry-1');
    expect(resolved?.title, 'Song');
  });

  test('prepareFromId publishes the resolved item through the host', () async {
    host.queue.add(_song());

    await browser.prepareFromId('song:current_queue:entry-1');

    expect(host.preparedItem?.id, 'song:current_queue:entry-1');
    expect(host.preparedItem?.title, 'Song');
  });

  // A head unit draws a tick on a row already listened to and a progress bar
  // on the one playing, from extras androidx.media defines. Without them the
  // whole queue looks like it is still waiting its turn.
  group('the marks a car draws on the queue rows', () {
    const statusKey = 'android.media.extra.PLAYBACK_STATUS';
    const percentageKey =
        'androidx.media.MediaItem.Extras.COMPLETION_PERCENTAGE';

    setUp(() {
      host.queue.addAll([
        _song(title: 'First'),
        _song(ytid: 'video-2', title: 'Second'),
        _song(ytid: 'video-3', title: 'Third'),
      ]);
    });

    test('what is behind is ticked, what is ahead is left alone', () async {
      host
        ..playbackIndex = 1
        ..playbackProgress = 0.25;

      final rows = await browser.children('current_queue');

      expect(rows[0].extras?[statusKey], 2, reason: 'played');
      expect(rows[1].extras?[statusKey], 1, reason: 'playing');
      expect(rows[2].extras?[statusKey], 0, reason: 'still to come');
    });

    test('the song playing carries how far into it playback is', () async {
      host
        ..playbackIndex = 1
        ..playbackProgress = 0.25;

      final rows = await browser.children('current_queue');

      expect(rows[1].extras?[percentageKey], 0.25);
      expect(rows[0].extras?.containsKey(percentageKey), isFalse);
      expect(rows[2].extras?.containsKey(percentageKey), isFalse);
    });

    test('an unknown duration still marks the song as being played', () async {
      host
        ..playbackIndex = 0
        ..playbackProgress = null;

      final rows = await browser.children('current_queue');

      expect(rows[0].extras?[statusKey], 1);
      expect(rows[0].extras?.containsKey(percentageKey), isFalse);
    });

    test('nothing playing leaves every row unmarked', () async {
      final rows = await browser.children('current_queue');

      for (final row in rows) {
        expect(row.extras?.containsKey(statusKey), isFalse);
      }
    });

    test('the songs already played are left out of the car', () async {
      host
        ..queueStart = 1
        ..playbackIndex = 1
        ..playbackProgress = 0.25;

      final rows = await browser.children('current_queue');

      expect(rows.map((row) => row.title), ['Second', 'Third']);
      expect(rows[0].extras?[statusKey], 1, reason: 'playing');
      expect(rows[0].extras?[percentageKey], 0.25);
      expect(rows[1].extras?[statusKey], 0, reason: 'still to come');
    });

    test('a row of the shortened queue plays with its shown index', () async {
      host.queueStart = 1;

      final rows = await browser.children('current_queue');
      await browser.playFromMediaId(rows[1].id);

      expect(host.skippedTo, [1], reason: 'Third, second row shown');
    });

    // Everywhere else is a library: what was played earlier says nothing
    // about the row, so marking it would only mislead.
    test('only the queue is marked, not the rest of the tree', () async {
      host
        ..playbackIndex = 1
        ..playbackProgress = 0.25;

      final rows = await browser.children('liked_songs');

      for (final row in rows) {
        expect(row.extras?.containsKey(statusKey), isFalse);
      }
    });
  });

  group('shuffling from the car', () {
    setUp(() {
      userLikedSongsList.value = [
        _song(ytid: 'a', title: 'A'),
        _song(ytid: 'b', title: 'B'),
      ];
    });
    tearDown(() => userLikedSongsList.value = []);

    test('a list of songs opens with a shuffle row', () async {
      final rows = await browser.children('liked_songs');

      expect(rows.first.id, 'shuffle:liked_songs');
      expect(rows.first.playable, isTrue);
      expect(rows.skip(1).map((row) => row.title), ['A', 'B']);
    });

    test('the queue is never offered for shuffling', () async {
      host.queue
        ..add(_song(ytid: 'a'))
        ..add(_song(ytid: 'b'));

      final rows = await browser.children('current_queue');

      expect(rows.any((row) => row.id.startsWith('shuffle:')), isFalse);
    });

    test('a single song gets no shuffle row', () async {
      userLikedSongsList.value = [_song(ytid: 'a')];

      final rows = await browser.children('liked_songs');

      expect(rows.map((row) => row.id), isNot(contains('shuffle:liked_songs')));
    });

    test('the shuffle row plays the whole list shuffled', () async {
      final played = await browser.playFromMediaId('shuffle:liked_songs');

      expect(played, isTrue);
      expect(host.shuffledSongs?.map((song) => song['ytid']), ['a', 'b']);
    });
  });

  // "Ok Google, mets <artiste> sur NicoFy", on a phone, in a car or on a TV:
  // the assistant hands the words over through the media session.
  group('playing what was asked by voice', () {
    late bool wasOffline;

    setUp(() {
      // Only the library: the YouTube search is the network.
      wasOffline = offlineMode.value;
      offlineMode.value = true;
      userLikedSongsList.value = [
        {..._song(ytid: 'a', title: 'Get Lucky'), 'artist': 'Daft Punk'},
        {..._song(ytid: 'b', title: 'Clocks'), 'artist': 'Coldplay'},
        {..._song(ytid: 'c', title: 'One More Time'), 'artist': 'Daft Punk'},
      ];
    });
    tearDown(() {
      userLikedSongsList.value = [];
      offlineMode.value = wasOffline;
    });

    test('an artist plays their songs, the first one first', () async {
      await browser.playFromSearch('daft punk');

      expect(host.playedSongs?.map((song) => song['ytid']), ['a', 'c']);
      expect(host.playedIndex, 0);
    });

    test('a title plays that song', () async {
      await browser.playFromSearch('Clocks');

      expect(host.playedSongs?.map((song) => song['ytid']), ['b']);
    });

    test('offline, each song plays once whatever the video', () async {
      userLikedSongsList.value = [
        {..._song(ytid: 'a', title: 'Get Lucky'), 'artist': 'Daft Punk'},
        {..._song(ytid: 'a2', title: 'Get Lucky Live'), 'artist': 'Daft Punk'},
        {..._song(ytid: 'c', title: 'One More Time'), 'artist': 'Daft Punk'},
        {
          ..._song(ytid: 'a3', title: 'Get Lucky (feat. Pharrell Williams)'),
          'artist': 'Daft Punk',
        },
      ];

      await browser.playFromSearch('daft punk');

      expect(host.playedSongs?.map((song) => song['ytid']), ['a', 'c']);
      expect(host.radiosStarted, 0, reason: 'no radio offline');
    });

    test('online, the best match plays alone and a radio follows', () async {
      // Enough matches in the library that the search does not reach
      // YouTube, which tests cannot.
      offlineMode.value = false;
      userLikedSongsList.value = [
        for (var i = 0; i < 30; i++)
          {..._song(ytid: 'v$i', title: 'Get Lucky'), 'artist': 'Daft Punk'},
      ];

      await browser.playFromSearch('get lucky');

      expect(host.playedSongs?.map((song) => song['ytid']), ['v0']);
      expect(host.playedIndex, 0);
      expect(host.radiosStarted, 1);
    });

    test('nothing named just resumes what was playing', () async {
      host.queue.add(_song());

      await browser.playFromSearch('');

      expect(host.resumed, 1);
      expect(host.playedSongs, isNull);
    });

    test('no match leaves playback alone', () async {
      await browser.playFromSearch('nothing like it');

      expect(host.playedSongs, isNull);
      expect(host.resumed, 0);
    });
  });
}

Map<String, dynamic> _song({String ytid = 'video-1', String title = 'Song'}) =>
    {
      'ytid': ytid,
      'id': ytid,
      'title': title,
      'artist': 'Artist',
      'highResImage': 'https://example.com/song.jpg',
      'lowResImage': 'https://example.com/song-small.jpg',
      'isLive': false,
    };

class _FakeAndroidAutoHost implements AndroidAutoHost {
  final List<Map> queue = [];
  final Map<Object, String> _entryIds = {};
  MediaItem? preparedItem;

  /// Where playback stands, as the handler would report it.
  int playbackIndex = -1;
  double? playbackProgress;

  @override
  List<Map> get browserQueue => queue;

  /// Where the queue shown in the car starts, as the handler would report it.
  int queueStart = 0;

  @override
  int get browserQueueStart => queueStart;

  final List<int> skippedTo = [];

  @override
  Stream<List<MediaItem>> get browserQueueStream => const Stream.empty();

  @override
  Stream<void> get browserNowPlayingStream => const Stream.empty();

  @override
  ({int index, double? progress}) get browserPlaybackProgress =>
      (index: playbackIndex, progress: playbackProgress);

  @override
  Map? latestResumableSong() => queue.isEmpty ? null : queue.first;

  @override
  Map<String, dynamic>? normaliseResumableSong(Map song) {
    final ytid = song['ytid']?.toString();
    if (ytid == null || ytid.isEmpty) return null;
    return {
      ...Map<String, dynamic>.from(song),
      'id': ytid,
      'ytid': ytid,
      'highResImage': song['highResImage'] ?? song['lowResImage'] ?? '',
      'lowResImage': song['lowResImage'] ?? song['highResImage'] ?? '',
      'isLive': song['isLive'] ?? false,
    };
  }

  @override
  Future<void> playResumableSong(Map song) =>
      playBrowserPlaylist([song], songIndex: 0);

  @override
  String ensureBrowserQueueEntryId(Map song) =>
      _entryIds.putIfAbsent(song, () => 'entry-${_entryIds.length + 1}');

  @override
  void logBrowserError(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {}

  int resumed = 0;

  @override
  Future<void> resumeAudio() async => resumed++;

  @override
  Future<void> skipToQueueItem(int index) async => skippedTo.add(index);

  List<Map>? playedSongs;
  int? playedIndex;

  @override
  Future<void> playBrowserPlaylist(
    List<Map> songs, {
    required int songIndex,
  }) async {
    playedSongs = songs;
    playedIndex = songIndex;
  }

  int radiosStarted = 0;

  @override
  Future<int> startBrowserRadio() async {
    radiosStarted++;
    return 25;
  }

  List<Map>? shuffledSongs;

  @override
  Future<void> shuffleBrowserPlaylist(List<Map> songs) async {
    shuffledSongs = songs;
  }

  @override
  void publishPreparedBrowserItem(MediaItem item) {
    preparedItem = item;
  }
}
