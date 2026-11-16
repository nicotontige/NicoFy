import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:nicofy/services/audio_service.dart';
import 'package:nicofy/services/queue_persistence_service.dart';
import 'package:nicofy/services/settings_manager.dart';

/// A queue restored at launch has to resume at the place it stopped, even
/// when the app or the car saves its state before anything was played.
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
    directory = await Directory.systemTemp.createTemp('nicofy_restored_position');
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

  group('a restored queue resumes where it stopped', () {
    // Opening the app and leaving it, or the car stopping the session, saves
    // the position before anything is loaded: the player then says zero.
    test('saving before the song is loaded keeps the stored place', () async {
      await restoredHandler();

      await handler!.persistPlaybackState();

      expect(
        queuePersistenceService.read()?.position,
        const Duration(seconds: 42),
      );
    });

    test('a first attempt that fails does not use the place up', () async {
      await restoredHandler();

      // Offline, with nothing downloaded: loading the song fails.
      await handler!.play();
      await handler!.persistPlaybackState();

      expect(
        queuePersistenceService.read()?.position,
        const Duration(seconds: 42),
      );
    });
  });
}
