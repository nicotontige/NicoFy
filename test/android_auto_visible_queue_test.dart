import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:nicofy/services/audio_service.dart';
import 'package:nicofy/services/queue_persistence_service.dart';
import 'package:nicofy/services/settings_manager.dart';

/// A car lists the queue from the song playing on: the songs already played
/// stay in the queue, for previous, but are no longer shown.
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
    directory = await Directory.systemTemp.createTemp('nicofy_visible_queue');
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

  group('the queue a car is shown', () {
    test('starts at the song playing, the played ones left out', () async {
      await restoredHandler();

      expect(shownQueue(), ['b', 'c', 'd']);
      expect(handler!.playbackState.value.queueIndex, 0);
      expect(fullQueue(), ['a', 'b', 'c', 'd'], reason: 'kept for previous');
    });

    test('a row picked in the car plays the song shown on it', () async {
      await restoredHandler();
      final started = <String?>[];
      final subscription = handler!.mediaItem.listen(
        (item) => started.add(item?.extras?['ytid'] as String?),
      );

      await handler!.skipToQueueItem(1);
      await subscription.cancel();

      expect(started, contains('c'));
      expect(started, isNot(contains('d')));
    });
  });
}
