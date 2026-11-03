
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/settings_manager.dart';

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('musify_auto_pick').path);
    await Hive.openBox('settings');
  });

  final song = {'duration': 4 * 60, 'isLive': false};
  final mix = {'duration': 75 * 60, 'isLive': false};
  final live = {'duration': null, 'isLive': true};
  final unknown = {'duration': null, 'isLive': false};

  test('any length lets everything through', () {
    autoPickLength.value = 'any';
    expect([song, mix, live, unknown].every(matchesAutoPickLength), isTrue);
  });

  test('songs only keeps mixes and live streams out', () {
    autoPickLength.value = 'songs';
    expect(matchesAutoPickLength(song), isTrue);
    expect(matchesAutoPickLength(unknown), isTrue);
    expect(matchesAutoPickLength(mix), isFalse);
    expect(matchesAutoPickLength(live), isFalse);
  });

  test('mixes only keeps songs out', () {
    autoPickLength.value = 'mixes';
    expect(matchesAutoPickLength(mix), isTrue);
    expect(matchesAutoPickLength(live), isTrue);
    expect(matchesAutoPickLength(song), isFalse);
  });

  test('the threshold itself counts as a mix', () {
    autoPickLength.value = 'mixes';
    expect(
      matchesAutoPickLength({
        'duration': autoPickMixMinDuration.inSeconds,
        'isLive': false,
      }),
      isTrue,
    );
  });
}
