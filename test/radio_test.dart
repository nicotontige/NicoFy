import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:nicofy/services/audio_service.dart';
import 'package:nicofy/services/queue_persistence_service.dart';
import 'package:nicofy/services/settings_manager.dart';

/// The radio: the song playing carries on, and what follows it gives way to
/// songs related to it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  NicoFyAudioHandler? handler;

  Map<String, dynamic> song(String id) => {
    'ytid': id,
    'title': id,
    'artist': 'Artist',
    'highResImage': '',
    'lowResImage': '',
    'isLive': false,
    'queueEntryId': 'entry-$id',
  };

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('nicofy_radio');
    Hive.init(directory.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
  });

  /// A queue of a, b, c, d stored by the last session, stopped on b.
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    playNextSongAutomatically.value = false;
    offlineMode.value = true;
    repeatNotifier.value = AudioServiceRepeatMode.none;
    await queuePersistenceService.clear();
    queuePersistenceService
      ..saveQueue([song('a'), song('b'), song('c'), song('d')], const [], 1)
      ..savePosition(1, 'entry-b', const Duration(seconds: 42), force: true);
    await queuePersistenceService.flush();
  });

  tearDown(() async {
    await handler?.audioPlayer.dispose();
    handler = null;
    await queuePersistenceService.clear();
    offlineMode.value = true;
    debugDefaultTargetPlatformOverride = null;
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  /// Builds the handler and waits for the stored queue to be back: asking
  /// for a media item is one of the calls that waits for it.
  Future<NicoFyAudioHandler> restoredHandler() async {
    final restored = handler = NicoFyAudioHandler();
    await restored.getMediaItem('nothing');
    return restored;
  }

  List<String?> fullQueue() =>
      handler!.browserQueue.map((song) => song['ytid'] as String?).toList();

  List<String?> shownQueue() => handler!.queue.value
      .map((item) => item.extras?['ytid'] as String?)
      .toList();

  group('the radio', () {
    Set<String>? excludedAsked;

    /// Hands back [songs] as related to whatever is asked. Offline mode is
    /// turned back on as it answers, so that the preload of the songs that
    /// follow stays away from the network.
    void relatedSongs(List<Map<String, dynamic>> songs) {
      offlineMode.value = false;
      handler!.radioSongsFetcher =
          (ytid, {excludedYtIds = const {}, count = 25}) async {
            excludedAsked = excludedYtIds;
            offlineMode.value = true;
            return songs;
          };
    }

    setUp(() => excludedAsked = null);

    test('replaces what follows the song playing', () async {
      await restoredHandler();
      relatedSongs([song('x'), song('y'), song('z')]);

      final queued = await handler!.startRadio();

      expect(queued, 3);
      expect(fullQueue(), ['a', 'b', 'x', 'y', 'z']);
      expect(handler!.currentSong?['ytid'], 'b', reason: 'b keeps playing');
      expect(shownQueue(), ['b', 'x', 'y', 'z']);
    });

    test('does not ask for the songs already played', () async {
      await restoredHandler();
      relatedSongs([song('x')]);

      await handler!.startRadio();

      expect(excludedAsked, containsAll(['a', 'b']));
    });

    test('is kept for the next launch', () async {
      await restoredHandler();
      relatedSongs([song('x'), song('y')]);

      await handler!.startRadio();
      await queuePersistenceService.flush();

      expect(
        queuePersistenceService.read()?.queue.map((song) => song['ytid']),
        ['a', 'b', 'x', 'y'],
      );
    });

    test('found empty leaves the queue alone and says so', () async {
      await restoredHandler();
      relatedSongs(const []);

      final queued = await handler!.startRadio();

      expect(queued, 0);
      expect(fullQueue(), ['a', 'b', 'c', 'd']);
      expect(handler!.playbackState.value.errorMessage, isNotNull);
    });

    test('is not attempted offline', () async {
      await restoredHandler();

      final queued = await handler!.startRadio();

      expect(queued, 0);
      expect(fullQueue(), ['a', 'b', 'c', 'd']);
    });
  });
}
