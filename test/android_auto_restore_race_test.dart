import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:nicofy/services/audio_service.dart';
import 'package:nicofy/services/queue_persistence_service.dart';
import 'package:nicofy/services/settings_manager.dart';

/// Android Auto starts the app and asks it to play in the same breath. These
/// commands used to reach the handler before the stored queue was back, play a
/// lone recent song instead, and overwrite the stored playlist with it.
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
  };

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('nicofy_auto_restore');
    Hive.init(directory.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
  });

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    playNextSongAutomatically.value = false;
    offlineMode.value = true;
    repeatNotifier.value = AudioServiceRepeatMode.none;
    await queuePersistenceService.clear();
    queuePersistenceService.saveQueue(
      [song('a'), song('b'), song('c'), song('d')],
      const [],
      1,
    );
    await queuePersistenceService.flush();
  });

  tearDown(() async {
    await handler?.audioPlayer.dispose();
    handler = null;
    await queuePersistenceService.clear();
    debugDefaultTargetPlatformOverride = null;
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  List<String?> queuedIds() => handler!.queue.value
      .map((item) => item.extras?['ytid'] as String?)
      .toList();

  test('play straight after launch resumes the stored queue', () async {
    handler = NicoFyAudioHandler();
    await handler!.play();

    expect(queuedIds(), ['a', 'b', 'c', 'd']);
  });

  test('the recent item played at launch stays inside its queue', () async {
    handler = NicoFyAudioHandler();
    await handler!.playFromMediaId('recent:b');

    expect(queuedIds(), ['a', 'b', 'c', 'd']);
  });

  test('preparing the recent item keeps the whole queue visible', () async {
    handler = NicoFyAudioHandler();
    await handler!.prepareFromMediaId('recent:b');

    expect(queuedIds(), ['a', 'b', 'c', 'd']);
  });

  test('an empty voice search at launch resumes the stored queue', () async {
    handler = NicoFyAudioHandler();
    await handler!.playFromSearch('');

    expect(queuedIds(), ['a', 'b', 'c', 'd']);
  });
}
