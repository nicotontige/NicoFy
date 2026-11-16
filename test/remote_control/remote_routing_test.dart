import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:nicofy/services/audio_service.dart';
import 'package:nicofy/services/queue_persistence_service.dart';
import 'package:nicofy/services/remote_control/playback_redirect.dart';
import 'package:nicofy/services/settings_manager.dart';

/// Records what the screens would have sent to the controlled device.
class FakeRedirect implements PlaybackRedirect {
  @override
  bool isActive = true;
  final calls = <String>[];

  @override
  Future<void> playList(
    List<Map> songs, {
    int? startIndex,
    bool? shuffle,
  }) async => calls.add(
    'playList:${songs.map((s) => s['ytid']).join(',')}:$startIndex:$shuffle',
  );

  @override
  Future<void> enqueue(
    List<Map> songs, {
    bool next = false,
    int? startIndex,
  }) async => calls.add(
    'enqueue:${songs.map((s) => s['ytid']).join(',')}:$next:$startIndex',
  );

  @override
  Future<void> playSong(Map song) async =>
      calls.add('playSong:${song['ytid']}');

  @override
  Future<bool> playStation({
    required String id,
    required String name,
    required String streamUrl,
    required String image,
    String? genre,
  }) async {
    calls.add('station:$id');
    return true;
  }
}

/// While this device controls another, what the screens start goes there,
/// and this device's own queue is left alone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  NicoFyAudioHandler? handler;
  late FakeRedirect redirect;

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
    directory = await Directory.systemTemp.createTemp('nicofy_routing');
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
    queuePersistenceService.saveQueue([song('a'), song('b')], const [], 0);
    await queuePersistenceService.flush();
    final restored = handler = NicoFyAudioHandler();
    await restored.getMediaItem('nothing');
    redirect = FakeRedirect();
    restored.playbackRedirect = redirect;
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

  List<String?> localQueue() =>
      handler!.browserQueue.map((s) => s['ytid'] as String?).toList();

  test('a song tapped in a list plays there, from that song', () async {
    await handler!.playPlaylistSong(
      playlist: {
        'list': [song('x'), song('y'), song('z')],
      },
      songIndex: 1,
    );
    await handler!.addPlaylistToQueue(
      [song('x'), song('y')],
      replace: true,
      shuffle: true,
    );
    expect(redirect.calls, ['playList:x,y,z:1:null', 'playList:x,y:null:true']);
    expect(localQueue(), ['a', 'b']);
  });

  test('queue actions add to the queue there', () async {
    await handler!.addToQueue(song('x'));
    await handler!.playNext(song('y'));
    await handler!.addPlaylistToQueue([song('z'), song('w')]);
    expect(redirect.calls, [
      'enqueue:x:false:null',
      'enqueue:y:true:null',
      'enqueue:z,w:false:null',
    ]);
    expect(localQueue(), ['a', 'b']);
  });

  test('a single song and a radio station play there', () async {
    expect(await handler!.playSong(song('x')), isTrue);
    expect(
      await handler!.playRadioStream(
        id: 'fip',
        name: 'FIP',
        streamUrl: 'https://example.org/fip',
        image: '',
      ),
      isTrue,
    );
    expect(redirect.calls, ['playSong:x', 'station:fip']);
  });

  test('not controlling anything, it all stays here', () async {
    redirect.isActive = false;
    await handler!.addToQueue(song('x'));
    expect(redirect.calls, isEmpty);
    expect(localQueue(), ['a', 'b', 'x']);
  });

  test('what the system asks for stays here', () async {
    // The notification or the car adding a song: not the screens.
    await handler!.customAction('addToQueue', {'song': song('x')});
    expect(redirect.calls, isEmpty);
    expect(localQueue(), ['a', 'b', 'x']);
  });
}
