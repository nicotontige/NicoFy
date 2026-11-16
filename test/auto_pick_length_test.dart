
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:nicofy/services/common_services.dart';
import 'package:nicofy/services/settings_manager.dart';

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('nicofy_auto_pick').path);
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

  group('a radio', () {
    Map<String, dynamic> video(String ytid, {int minutes = 4}) => {
      'ytid': ytid,
      'duration': minutes * 60,
      'isLive': false,
    };

    List<String?> ytids(List<Map> songs) =>
        songs.map((song) => song['ytid'] as String?).toList();

    test('takes each song once, none of those already heard', () {
      autoPickLength.value = 'any';
      final seen = {'b'};

      final picked = pickRadioSongs(
        [video('a'), video('b'), video('a'), video('c')],
        seenYtIds: seen,
        count: 25,
      );

      expect(ytids(picked), ['a', 'c']);
      expect(seen, {'a', 'b', 'c'}, reason: 'the next page skips them');
    });

    test('keeps to the songs/mixes setting of the song picker', () {
      autoPickLength.value = 'songs';

      final picked = pickRadioSongs(
        [video('a'), video('set', minutes: 90), video('c')],
        seenYtIds: {},
        count: 25,
      );

      expect(ytids(picked), ['a', 'c']);
    });

    test('stops at the length asked for', () {
      autoPickLength.value = 'any';

      final picked = pickRadioSongs(
        [video('a'), video('b'), video('c')],
        seenYtIds: {},
        count: 2,
      );

      expect(ytids(picked), ['a', 'b']);
    });
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
